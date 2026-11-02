--!strict
-- ErrorReporter (paquet meta, docs/04 §13.7) — erreurs et avertissements du client (GDD §12.11) :
-- ScriptContext.Error et LogService.MessageOut, sauvetages du focus (FocusRescued), WaitForChild arrivés
-- à leur délai (report). Normalisés par DiagRules (noms des joueurs remplacés, nombres → #), 1 par clé
-- et par minute, 30 par session, envoyés par ReportError avec un petit contexte (appareil, entrée,
-- résolution, langue, version, étape, fenêtre ouverte, événement). Interrupteur du serveur : features
-- .diagnostics du dernier EventState (false : aucun envoi, entries() continue de compter ; jamais
-- Config/Features lu côté client). File bornée (10) vidée au débit d'Intents.ReportError (un envoi toutes
-- les 2,2 s) : une cascade au démarrage n'est pas perdue par le débit du serveur. Celebrate « testError »
-- (administrateurs) : erreur volontaire dans un thread du client, qui suit le chemin normal (test manuel
-- M17). Premier module du client : attach() est appelé par Main.client juste après son require ; aucun
-- remote n'est attendu avant Start (jamais de yield dans un rapport). Garde de réentrance : ses propres
-- erreurs ne se rapportent jamais elles-mêmes ; il n'écrit jamais de warn.
-- Remotes : ReportError, SetInputType (envoi) ; EventState, Celebrate (« testError ») écoutés.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Intents = require(Shared.Config.Intents)
local DiagRules = require(Shared.Logic.DiagRules)

local ErrorReporter = {}

local LIMITS = DiagRules.Limits
ErrorReporter.QueueMax = 10
-- un envoi toutes les 2,2 s : sous le débit du serveur (Intents.ReportError, 1 / 2 s) avec de la marge
ErrorReporter.SendEvery = Intents.ReportError.rate[2] / Intents.ReportError.rate[1] * 1.1
ErrorReporter.InputEvery = Intents.SetInputType.rate[2] / Intents.SetInputType.rate[1] * 1.1
ErrorReporter.MaxEntries = 50
local DEDUP_WINDOW = 1 -- s (os.clock) : même erreur vue par ScriptContext.Error ET MessageOut
local TEST_ERROR = "[ErrorReporter] erreur volontaire du client (test M17)"

type Queued = { kind: number, key: string, message: string, trace: string, ctx: string }
type Entry = Types.DiagEntry

local entriesByKey: { [string]: Entry } = {}
local entryOrder: { string } = {}
local lastByKey: { [string]: number } = {}
local queue: { Queued } = {}
local queuedTotal = 0
local sentCount = 0
local context: { [string]: string } = {}
local recent: { { text: string, at: number, from: string } } = {}
local busy = false
local attached = false
local started = false
local enabled = true -- features.diagnostics du dernier EventState
local nextSend = 0
local remote: RemoteEvent? = nil
local inputRemote: RemoteEvent? = nil
local lastInput: { kind: number, tenFoot: boolean }? = nil
local nextInput = 0
local frames: { number } = {}
local frameAcc = 0
local probes: { [string]: () -> any } = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Noms à effacer : joueur local et joueurs présents (noms et noms d'affichage)
local function names(): { string }
	local out = {}
	local ok, list = pcall(function()
		return Players:GetPlayers()
	end)
	if ok then
		for _, p in list do
			table.insert(out, p.Name)
			table.insert(out, p.DisplayName)
		end
	end
	return out
end

local function scriptOf(trace: string): string
	local first = string.match(trace, "^%s*([^\n]+)") or ""
	return string.match(first, "^([^:%s]+)") or ""
end

local function inputKind(): number
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and typeof(last) == "EnumItem" then
		local name = (last :: EnumItem).Name
		if string.find(name, "Gamepad", 1, true) then
			return 3
		elseif name == "Touch" then
			return 1
		end
		return 2
	end
	return 3
end

local function tenFoot(): boolean
	local ok, value = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and value == true
end

-- Contexte du moment de l'envoi (lu sous pcall, jamais une erreur)
local function contextText(): string
	local fields: { [string]: any } = {}
	fields.device = if tenFoot() then "console" else "pc"
	fields.input = ({ "touch", "kbm", "pad" })[inputKind()] or "pad"
	pcall(function()
		local camera = workspace.CurrentCamera
		if camera ~= nil then
			fields.resolution = camera.ViewportSize
		end
	end)
	pcall(function()
		local LocalizationService = game:GetService("LocalizationService")
		fields.lang = LocalizationService.RobloxLocaleId
	end)
	pcall(function()
		fields.version = game.PlaceVersion
	end)
	for key, value in context do
		fields[key] = value
	end
	return DiagRules.context(fields)
end

local function duplicate(text: string, from: string): boolean
	local now = os.clock()
	for i = #recent, 1, -1 do
		local r = recent[i]
		if now - r.at > DEDUP_WINDOW then
			break
		end
		if
			r.from ~= from
			and (
				r.text == text
				or string.find(r.text, text, 1, true) ~= nil
				or string.find(text, r.text, 1, true) ~= nil
			)
		then
			return true
		end
	end
	table.insert(recent, { text = text, at = now, from = from })
	if #recent > 20 then
		table.remove(recent, 1)
	end
	return false
end

-- Compte puis met en file (1 par clé et par minute, 30 par session, file de 10)
local function record(kind: number, text: string, trace: string)
	local k = if kind == 2 then 2 else 1
	local who = names()
	local message = DiagRules.truncate(DiagRules.normalize(text, who), LIMITS.Message)
	local normTrace = DiagRules.truncate(DiagRules.normalize(trace, who), LIMITS.Trace)
	local key = DiagRules.key(message, "client:" .. scriptOf(normTrace))
	local unix = Clock.unix()
	local entry = entriesByKey[key]
	if entry == nil then
		if #entryOrder >= ErrorReporter.MaxEntries then
			local oldest = table.remove(entryOrder, 1) :: string
			entriesByKey[oldest] = nil
		end
		entry = {
			key = key,
			kind = k,
			text = message,
			source = "client",
			count = 0,
			players = 1,
			first = unix,
			last = unix,
		}
		entriesByKey[key] = entry
		table.insert(entryOrder, key)
	else
		-- la plus récente en dernier
		local index = table.find(entryOrder, key)
		if index ~= nil then
			table.remove(entryOrder, index)
		end
		table.insert(entryOrder, key)
	end
	entry.count += 1
	entry.last = unix
	local now = Clock.now()
	local last = lastByKey[key]
	if last ~= nil and now - last < LIMITS.PerKeyWindow then
		return
	end
	if queuedTotal >= LIMITS.PerSession or #queue >= ErrorReporter.QueueMax then
		return
	end
	lastByKey[key] = now
	queuedTotal += 1
	table.insert(queue, {
		kind = k,
		key = DiagRules.truncate(key, LIMITS.Key),
		message = message,
		trace = normTrace,
		ctx = contextText(),
	})
end

local function guarded(fn: () -> ())
	if busy then
		return
	end
	busy = true
	pcall(fn)
	busy = false
end

local function sendInput(now: number)
	local r = inputRemote
	if r == nil or now < nextInput then
		return
	end
	local current = { kind = inputKind(), tenFoot = tenFoot() }
	if lastInput ~= nil and lastInput.kind == current.kind and lastInput.tenFoot == current.tenFoot then
		return
	end
	lastInput = current
	nextInput = now + ErrorReporter.InputEvery
	pcall(function()
		r:FireServer(current.kind, current.tenFoot)
	end)
end

-- Une image : images par seconde, file vidée au débit, entrée déclarée
local function onFrame(dt: number)
	local now = Clock.now()
	frameAcc += 1
	table.insert(frames, os.clock())
	while #frames > 0 and os.clock() - frames[1] > 1 do
		table.remove(frames, 1)
	end
	local r = remote
	if r ~= nil and enabled and #queue > 0 and now >= nextSend then
		local item = table.remove(queue, 1) :: Queued
		nextSend = now + ErrorReporter.SendEvery
		sentCount += 1
		pcall(function()
			r:FireServer(item.kind, item.key, item.message, item.trace, item.ctx)
		end)
	end
	if frameAcc % 30 == 0 then
		sendInput(now)
	end
	local _ = dt
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Branche les sources d'erreurs au plus tôt (aucun remote attendu ici)
function ErrorReporter.attach()
	if attached then
		return
	end
	attached = true
	pcall(function()
		local scriptContext = game:GetService("ScriptContext")
		scriptContext.Error:Connect(function(message: string, trace: string)
			local text = tostring(message)
			if busy or duplicate(text, "error") then
				return
			end
			guarded(function()
				record(1, text, tostring(trace or ""))
			end)
		end)
	end)
	pcall(function()
		local logService = game:GetService("LogService")
		logService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
			if busy then
				return
			end
			local kind = 0
			if messageType == Enum.MessageType.MessageError then
				kind = 1
			elseif messageType == Enum.MessageType.MessageWarning then
				kind = 2
			end
			if kind == 0 then
				return
			end
			local text = tostring(message)
			if kind == 1 and duplicate(text, "log") then
				return
			end
			guarded(function()
				record(kind, text, "")
			end)
		end)
	end)
end

-- Création des états ; aucun yield
function ErrorReporter.Init()
	nextSend = 0
end

-- Connexions : remotes attendus dans un thread à part (bornés par Net), une boucle par image
function ErrorReporter.Start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function(dt: number)
		guarded(function()
			onFrame(dt)
		end)
	end)
	task.spawn(function()
		local ok, r = pcall(Net.event, "ReportError")
		if ok then
			remote = r
		end
		local okInput, ri = pcall(Net.event, "SetInputType")
		if okInput then
			inputRemote = ri
			sendInput(Clock.now())
		end
		local okState, state = pcall(Net.event, "EventState")
		if okState then
			state.OnClientEvent:Connect(function(payload: any)
				if type(payload) == "table" and type(payload.features) == "table" then
					enabled = payload.features.diagnostics ~= false
				end
			end)
		end
		local okCelebrate, celebrate = pcall(Net.event, "Celebrate")
		if okCelebrate then
			celebrate.OnClientEvent:Connect(function(payload: any)
				if type(payload) == "table" and payload.kind == "testError" then
					-- erreur volontaire dans un thread du client : chemin normal (ScriptContext.Error)
					task.spawn(error, TEST_ERROR, 0)
				end
			end)
		end
	end)
end

-- Rapport interne (FocusRescued, délai de WaitForChild)
function ErrorReporter.report(kind: number, text: string, trace: string?)
	guarded(function()
		record(
			if kind == 2 then 2 else 1,
			if type(text) == "string" then text else tostring(text),
			if type(trace) == "string" then trace else ""
		)
	end)
end

-- Met à jour un champ du contexte (fenêtre ouverte, événement en cours)
function ErrorReporter.noteContext(key: string, value: string)
	if type(key) ~= "string" or #key > 16 then
		return
	end
	if value == nil or value == "" then
		context[key] = nil
	else
		context[key] = string.sub(tostring(value), 1, 40)
	end
end

-- Rapports envoyés dans la session (tests)
function ErrorReporter.sent(): number
	return sentCount
end

-- Rapports de ce client dans la session (onglet « Mon client » du panneau Diagnostics), les plus
-- récents en dernier, bornés (comptes par clé)
function ErrorReporter.entries(): { Types.DiagEntry }
	local out = {}
	for _, key in entryOrder do
		table.insert(out, table.clone(entriesByKey[key]))
	end
	return out
end

-- Sonde d'un contrôleur plus tardif (« reduced » : QualityController.reduced ; « connections ») :
-- jamais un appel direct vers un module initialisé après ErrorReporter (docs/04 §1 règle 10)
function ErrorReporter.setProbe(name: string, fn: (() -> any)?)
	if type(name) == "string" then
		probes[name] = fn :: any
	end
end

local function probe(name: string, default: any): any
	local fn = probes[name]
	if fn == nil then
		return default
	end
	local ok, value = pcall(fn)
	if ok and value ~= nil then
		return value
	end
	return default
end

-- Mesures du client pour l'onglet « Mon client » : images par seconde, mémoire (Stats), ping,
-- instances, connexions suivies, qualité réduite ou non
function ErrorReporter.stats(): {
	fps: number,
	memoryMb: number,
	pingMs: number,
	instances: number,
	connections: number,
	reduced: boolean,
}
	local memory, instances, ping = 0, 0, 0
	pcall(function()
		local Stats = game:GetService("Stats")
		local m = Stats:GetTotalMemoryUsageMb()
		memory = if finite(m) then m else 0
	end)
	pcall(function()
		local Stats = game:GetService("Stats") :: any
		local n = Stats.InstanceCount
		instances = if finite(n) then n else 0
	end)
	pcall(function()
		local p = Players.LocalPlayer
		if p ~= nil then
			local seconds = (p :: any):GetNetworkPing()
			ping = if finite(seconds) then seconds * 1000 else 0
		end
	end)
	local connections = probe("connections", 0)
	return {
		fps = #frames,
		memoryMb = memory,
		pingMs = ping,
		instances = instances,
		connections = if finite(connections) then connections else 0,
		reduced = probe("reduced", false) == true,
	}
end

-- Tests : état vidé (file, comptes, interrupteur)
function ErrorReporter._reset()
	table.clear(entriesByKey)
	table.clear(entryOrder)
	table.clear(lastByKey)
	table.clear(queue)
	table.clear(context)
	table.clear(recent)
	queuedTotal, sentCount, nextSend = 0, 0, 0
	enabled = true
end

-- Tests : file en attente et interrupteur
function ErrorReporter._queued(): number
	return #queue
end

function ErrorReporter._enabled(): boolean
	return enabled
end

return ErrorReporter
