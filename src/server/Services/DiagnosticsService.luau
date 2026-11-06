--!strict
-- DiagnosticsService (paquet meta, docs/04 §11.2) — Diagnostics en ligne (GDD §12.11) : erreurs et
-- avertissements du serveur (ScriptContext.Error, LogService.MessageOut), erreurs attrapées par les
-- pcall du tick et des handlers (reportCaught), états fermés par leur délai (stateTimedOut),
-- compteurs nommés des services v2.0 (count, lot A4 : « Count:<clé> », jamais une trace ni un
-- ServerError), réparations de profil (Signals.ProfileRepaired), et rapports des clients
-- (ReportError : validés, plafonnés, noms nettoyés une 2e fois). Par clé : nombre, joueurs touchés
-- (en mémoire, jamais envoyés), première et dernière fois, 3 exemples ; 200 clés au plus, puis un
-- compteur « autres ». Totaux du jour
-- dans un DataStore à part toutes les 5 min (UpdateAsync, DiagRules.mergeDaily, task.spawn) ;
-- analytique ServerError / ClientError une fois par clé et par 5 min. Panneau des administrateurs
-- seulement (Data/Admins, vérifié à chaque demande ; silence pour les autres ; « bonjour » tab 0 aux
-- administrateurs à PlayerReady). ClientEvent (qualityReduced, shopOpened) : analytique seulement.
-- v2.0 (lot A4, étape 6, D29, D30) : ClientMetric (faits que seul le client mesure : compteurs
-- UpgradeTimeout, TextScaleMeasured:<v>, StyleFallback:<v>, VisualBudgetExceeded et analytique,
-- 20 par session, chaque sorte derrière son interrupteur ; jamais un changement du jeu) ; démarre
-- Meta/MetaAnalytics (start dans Start, step dans step) et lui transmet UpgradeStale (count).
-- Premier service : attach() est appelé par Main.server juste après son require, AVANT Net.setup() :
-- aucun remote n'est touché avant Init. Garde de réentrance : une erreur de Diagnostics ne se rapporte
-- jamais elle-même et Diagnostics n'écrit jamais de warn.
-- Remotes : ReportError, RequestDiagnostics, SetInputType, ClientEvent, ClientMetric ; DiagnosticsSnapshot.
-- Clés : aucune.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Features = require(Shared.Config.Features)
local DiagRules = require(Shared.Logic.DiagRules)
local Admins = require(script.Parent.Parent.Data.Admins)
local Signals = require(script.Parent.Parent.Signals)
local Analytics = require(script.Parent.Parent.Util.Analytics)
local Guard = require(script.Parent.Parent.Meta.Guard)

export type Device = { kind: number, tenFoot: boolean }
export type Totals = { errors: number, warnings: number, timedOut: number, keys: number }

local DiagnosticsService = {}

local LIMITS = DiagRules.Limits
-- Réglages nommés (GDD §12.11)
DiagnosticsService.StoreName = "Diagnostics_v1"
DiagnosticsService.AnalyticsEvery = 300 -- s : ServerError / ClientError une fois par clé et par 5 min
DiagnosticsService.ClientEventsPerSession = 20
DiagnosticsService.ClientMetricsPerSession = 20 -- v2.0 (D29)
DiagnosticsService.ClientMetricValues = 8 -- valeurs distinctes gardées par compteur « <clé>:<valeur> »
local DEDUP_WINDOW = 1 -- s (os.clock) : même erreur vue par ScriptContext.Error ET MessageOut
local RECENT_MAX = 20

type Entry = {
	key: string,
	kind: number,
	text: string,
	source: "server" | "client",
	count: number,
	players: { [number]: boolean },
	playerCount: number,
	first: number,
	last: number,
	samples: { Types.DiagSample },
	analyticsAt: number, -- Clock.now() du dernier ServerError / ClientError
	analyticsCount: number, -- occurrences depuis ce dernier envoi
	flushed: number, -- occurrences déjà écrites dans les totaux du jour
	flushedPlayers: number,
	quiet: boolean, -- compteur nommé (count) : jamais d'analytique ServerError
}

type PlayerState = {
	reports: number, -- ReportError acceptés dans la session
	lastByKey: { [string]: number }, -- Clock.now() du dernier rapport accepté par clé
	events: number, -- ClientEvent acceptés
	touchLogged: boolean,
	metrics: number, -- ClientMetric acceptés (v2.0)
}

-- v2.0 (lot A4, D29) : interrupteur de chaque sorte de ClientMetric ("" : toujours, diagnostics de
-- base de B1 / B4 envoyés par le client v2.0 seulement) ; une sorte liée à un interrupteur demande
-- aussi un profil v2
local METRIC_FLAG: { [string]: string } = {
	upgradeTimeout = "UpgradesScreen",
	upgradeMode = "UpgradesScreen",
	ascendPreview = "JellyAscend",
	ascendDeclined = "JellyAscend",
	textScale = "",
	styleFallback = "",
	visualBudget = "",
}
-- valeurs permises (sinon refusé) : mode d'achat (1 ×1, 10 ×10, 0 Max) ; étape de l'aperçu de
-- l'Ascension (0 ouvert, 1 annulé, 2 confirmé)
local UPGRADE_MODES: { [number]: string } = { [0] = "max", [1] = "x1", [10] = "x10" }
local PREVIEW_STEPS: { [number]: string } = { [0] = "opened", [1] = "cancelled", [2] = "confirmed" }
-- compteurs dont la clé porte la valeur envoyée : ClientMetricValues valeurs distinctes par serveur,
-- puis « <clé>:other » (un client ne remplit jamais les 64 compteurs nommés)
local metricValues: { [string]: { [number]: boolean } } = {}
local metricValueCount: { [string]: number } = {}
-- compteurs transmis à l'analytique (MetaAnalytics.counted)
local FORWARD: { [string]: boolean } = { UpgradeStale = true }
local meta: any = nil -- Meta/MetaAnalytics (chargé par Start : tous les services sont là)

local entries: { [string]: Entry } = {}
local order: { string } = {}
local others = 0
local totals: Totals = { errors = 0, warnings = 0, timedOut = 0, keys = 0 }
local perPlayer: { [Player]: PlayerState } = {}
local devices: { [Player]: Device } = {}
local recent: { { text: string, at: number, from: string } } = {}
local busy = false -- garde de réentrance
local attached = false
local started = false
local startedAt = 0
local lastFlush = 0
local flushing = false
local todayCache: { Types.DiagEntry } = {}
local todayDay = 0
local tickStats = { sum = 0, n = 0, max = 0 }
local internalErrors = 0
-- Compteurs nommés (count, lot A4, D29 ; note INT-A2-DIAG) : clé → nombre, en mémoire ; 64 clés au
-- plus, puis la clé « others ». Clé et texte de Diagnostics calculés une fois par clé (count est
-- appelé par des chemins chauds : pressions des Plopettes)
DiagnosticsService.CounterKeys = 64
local counterValues: { [string]: number } = {}
local counterKeys = 0
local counterText: { [string]: string } = {}
local counterDiagKey: { [string]: string } = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Noms à effacer : noms et noms d'affichage des joueurs présents et de l'envoyeur
local function names(sender: Player?): { string }
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
	if sender ~= nil then
		table.insert(out, sender.Name)
		table.insert(out, sender.DisplayName)
	end
	return out
end

-- Script d'une pile normalisée (premier élément « chemin:ligne »), sans les numéros
local function scriptOf(trace: string): string
	local first = string.match(trace, "^%s*([^\n]+)") or ""
	return string.match(first, "^([^:%s]+)") or ""
end

local function anyPlayer(preferred: Player?): Player?
	if preferred ~= nil and preferred.Parent ~= nil then
		return preferred
	end
	local best: Player? = nil
	for _, p in Players:GetPlayers() do
		if best == nil or p.UserId < (best :: Player).UserId then
			best = p
		end
	end
	return best
end

local function deviceName(device: Device?): string
	if device == nil then
		return "unknown"
	end
	if device.kind == 1 then
		return "touch"
	elseif device.kind == 2 then
		return "pcKeyboard"
	end
	return if device.tenFoot then "console" else "pcGamepad"
end

local function sendAnalytics(entry: Entry, player: Player?)
	local target = anyPlayer(player)
	if target == nil or entry.analyticsCount <= 0 then
		return
	end
	local name = if entry.source == "client" then "ClientError" else "ServerError"
	Analytics.custom(target, name, entry.analyticsCount, { key = entry.key })
	entry.analyticsAt = Clock.now()
	entry.analyticsCount = 0
end

-- Compte une occurrence sous une clé (texte, pile et contexte déjà normalisés)
local function record(
	key: string,
	kind: number,
	text: string,
	trace: string,
	ctx: string,
	source: "server" | "client",
	player: Player?,
	quiet: boolean?
)
	if kind == 1 then
		totals.errors += 1
	else
		totals.warnings += 1
	end
	local now = Clock.now()
	local unix = Clock.unix()
	local entry = entries[key]
	if entry == nil then
		if #order >= LIMITS.MaxKeys then
			others += 1
			return
		end
		entry = {
			key = key,
			kind = kind,
			text = text,
			source = source,
			count = 0,
			players = {},
			playerCount = 0,
			first = unix,
			last = unix,
			samples = {},
			analyticsAt = -math.huge,
			analyticsCount = 0,
			flushed = 0,
			flushedPlayers = 0,
			quiet = quiet == true,
		}
		entries[key] = entry
		table.insert(order, key)
		totals.keys = #order
	end
	entry.count += 1
	entry.last = unix
	if player ~= nil and not entry.players[player.UserId] then
		entry.players[player.UserId] = true
		entry.playerCount += 1
	end
	if #entry.samples < LIMITS.Samples then
		table.insert(entry.samples, { key = key, text = text, trace = trace, ctx = ctx, at = unix })
	end
	if entry.quiet then
		return -- compteur nommé : jamais d'analytique ServerError
	end
	entry.analyticsCount += 1
	if now - entry.analyticsAt >= DiagnosticsService.AnalyticsEvery then
		sendAnalytics(entry, player)
	end
end

-- Même erreur venue de l'autre source (ScriptContext.Error / MessageOut) à moins d'1 s : ignorée
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
	if #recent > RECENT_MAX then
		table.remove(recent, 1)
	end
	return false
end

local function guarded(fn: () -> ())
	if busy then
		return
	end
	busy = true
	local ok = pcall(fn)
	busy = false
	if not ok then
		internalErrors += 1 -- jamais un warn (il se rapporterait lui-même)
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Branche ScriptContext.Error et LogService.MessageOut au plus tôt (avant Net.setup : aucun remote)
function DiagnosticsService.attach()
	if attached then
		return
	end
	attached = true
	local okSc, scriptContext = pcall(function()
		return game:GetService("ScriptContext")
	end)
	if okSc and scriptContext ~= nil then
		pcall(function()
			scriptContext.Error:Connect(function(message: string, trace: string, origin: Instance?)
				local text = tostring(message)
				if busy or duplicate(text, "error") then
					return
				end
				local where = ""
				if typeof(origin) == "Instance" then
					local okName, full = pcall(function()
						return (origin :: Instance):GetFullName()
					end)
					where = if okName then full else ""
				end
				DiagnosticsService.report("server", 1, text, tostring(trace or ""), where, nil)
			end)
		end)
	end
	local okLog, logService = pcall(function()
		return game:GetService("LogService")
	end)
	if okLog and logService ~= nil then
		pcall(function()
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
				DiagnosticsService.report("server", kind, text, "", "", nil)
			end)
		end)
	end
end

-- Clé d'un compteur qui porte une valeur du client : « <préfixe>:<valeur> » pour les
-- ClientMetricValues premières valeurs vues sur le serveur, puis « <préfixe>:other »
local function metricKey(prefix: string, value: number): string
	local seen = metricValues[prefix]
	if seen == nil then
		seen = {}
		metricValues[prefix] = seen
	end
	if not seen[value] then
		local n = metricValueCount[prefix] or 0
		if n >= DiagnosticsService.ClientMetricValues then
			return prefix .. ":other"
		end
		seen[value] = true
		metricValueCount[prefix] = n + 1
	end
	return prefix .. ":" .. tostring(value)
end

-- Création des remotes et des états ; aucun yield long
function DiagnosticsService.Init()
	startedAt = Clock.now()
	lastFlush = startedAt
	todayDay = Clock.day()

	Guard.connect("ReportError", function(player, kind, _key, message, trace, ctx)
		if Features.get("Diagnostics") == false then
			return false
		end
		local state = perPlayer[player]
		if state == nil then
			state = { reports = 0, lastByKey = {}, events = 0, touchLogged = false, metrics = 0 }
			perPlayer[player] = state
		end
		if state.reports >= LIMITS.PerSession then
			return false -- au-delà : ignoré sans réponse jusqu'à la fin de la session
		end
		local normalized = DiagRules.normalize(message, names(player))
		local normTrace = DiagRules.normalize(trace, names(player))
		local key = DiagRules.key(normalized, "client:" .. scriptOf(normTrace))
		local now = Clock.now()
		local last = state.lastByKey[key]
		if last ~= nil and now - last < LIMITS.PerKeyWindow then
			return false
		end
		state.lastByKey[key] = now
		state.reports += 1
		DiagnosticsService.report("client", kind, message, trace, ctx, player)
		-- sauvetage du focus (FocusGuard) : analytique FocusRescued avec l'écran
		local screen = string.match(normalized, "^FocusRescued:([%w_]+)")
		if screen ~= nil then
			Analytics.custom(player, "FocusRescued", 1, { screen = screen })
		end
		return true
	end)

	Guard.connect("RequestDiagnostics", function(player, tab)
		if not DiagnosticsService.isAdmin(player) then
			return false -- silence pour un non-administrateur
		end
		Net.event("DiagnosticsSnapshot"):FireClient(player, DiagnosticsService.snapshot(tab))
		return true
	end)

	Guard.connect("SetInputType", function(player, kind, tenFoot)
		local device: Device = { kind = kind, tenFoot = tenFoot }
		devices[player] = device
		Analytics.setSegment(player, "device", deviceName(device))
		if kind == 1 then
			local state = perPlayer[player]
			if state == nil then
				state = { reports = 0, lastByKey = {}, events = 0, touchLogged = false, metrics = 0 }
				perPlayer[player] = state
			end
			if not state.touchLogged then
				state.touchLogged = true
				Analytics.custom(player, "TouchDeviceJoined", 1)
			end
		end
		return true
	end)

	Guard.connect("ClientEvent", function(player, kind)
		local state = perPlayer[player]
		if state == nil then
			state = { reports = 0, lastByKey = {}, events = 0, touchLogged = false, metrics = 0 }
			perPlayer[player] = state
		end
		if state.events >= DiagnosticsService.ClientEventsPerSession then
			return false
		end
		state.events += 1
		if kind == "qualityReduced" then
			Analytics.custom(player, "QualityReduced", 1, { device = deviceName(devices[player]) })
		elseif kind == "shopOpened" then
			Analytics.custom(player, "ShopOpened", 1)
		end
		return true
	end)

	-- v2.0 (lot A4, D29) : faits mesurés par le client ; compteurs et analytique SEULEMENT
	Guard.connect("ClientMetric", function(player, kind, value)
		local flag = METRIC_FLAG[kind]
		if flag == nil then
			return false
		end
		if flag ~= "" and (Features.get(flag) ~= true or meta == nil or not meta.isV2(player)) then
			return false
		end
		if
			(kind == "upgradeMode" and UPGRADE_MODES[value] == nil)
			or (kind == "ascendPreview" and PREVIEW_STEPS[value] == nil)
		then
			return false
		end
		local state = perPlayer[player]
		if state == nil then
			state = { reports = 0, lastByKey = {}, events = 0, touchLogged = false, metrics = 0 }
			perPlayer[player] = state
		end
		if state.metrics >= DiagnosticsService.ClientMetricsPerSession then
			return false
		end
		state.metrics += 1
		if kind == "upgradeTimeout" then
			DiagnosticsService.count("UpgradeTimeout", player)
			Analytics.add(player, "UpgradeTimeout", 1)
		elseif kind == "upgradeMode" then
			Analytics.add(player, "UpgradeMode", 1, { mode = UPGRADE_MODES[value] })
		elseif kind == "ascendPreview" then
			Analytics.add(player, "AscendPreview", 1, { step = PREVIEW_STEPS[value] })
		elseif kind == "ascendDeclined" then
			Analytics.custom(player, "AscendDeclined", value) -- jours depuis que l'Ascension est prête
		elseif kind == "textScale" then
			DiagnosticsService.count(metricKey("TextScaleMeasured", value), player)
			Analytics.custom(player, "TextScaleMeasured", value) -- facteur mesuré × 100
		elseif kind == "styleFallback" then
			DiagnosticsService.count(metricKey("StyleFallback", value), player)
		elseif kind == "visualBudget" then
			DiagnosticsService.count("VisualBudgetExceeded", player)
		end
		return true
	end)
end

-- Connexions et boucles
function DiagnosticsService.Start()
	if started then
		return
	end
	started = true
	Signals.PlayerReady:Connect(function(player: Player)
		if DiagnosticsService.isAdmin(player) then
			-- « bonjour » : le seul moyen pour le client de savoir qu'il est administrateur
			Net.event("DiagnosticsSnapshot"):FireClient(player, DiagnosticsService.snapshot(0))
		end
	end)
	Signals.ProfileRepaired:Connect(function(player: Player, fixes: { string })
		if type(fixes) ~= "table" then
			return
		end
		guarded(function()
			for i, field in fixes do
				if i > 20 then
					break
				end
				local text = "ProfileRepaired:" .. DiagRules.truncate(tostring(field), 60)
				local key = DiagRules.key(text, "repair")
				-- réparations : comptées à part (jamais un « avertissement du moteur »)
				local before = totals.warnings
				record(key, 2, text, "", "", "server", player)
				totals.warnings = before
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		perPlayer[player] = nil
		devices[player] = nil
	end)
	-- v2.0 (lot A4, D30) : analytique des signaux v2.0, chargée ici (tous les services sont là) ; une
	-- panne de chargement remonte à Main.server (avertissement visible, jamais avalée)
	meta = require(script.Parent.Parent.Meta.MetaAnalytics) :: any
	meta.start()
end

-- Tick : analytique en attente, écriture groupée des totaux du jour (task.spawn, jamais de yield)
function DiagnosticsService.step(now: number)
	local t = if finite(now) then now else Clock.now()
	if meta ~= nil then
		Guard.try("diagnostics:meta", meta.step, t)
	end
	Guard.try("diagnostics:analytics", Analytics.step, t)
	if t - lastFlush < LIMITS.FlushInterval or flushing then
		return
	end
	lastFlush = t
	local delta: { Types.DiagEntry } = {}
	local marks: { { entry: Entry, count: number, players: number } } = {}
	for _, key in order do
		local e = entries[key]
		local add = e.count - e.flushed
		if add > 0 then
			table.insert(delta, {
				key = e.key,
				kind = e.kind,
				text = DiagRules.truncate(e.text, 80),
				source = e.source,
				count = add,
				players = math.max(0, e.playerCount - e.flushedPlayers),
				first = e.first,
				last = e.last,
			})
			table.insert(marks, { entry = e, count = e.count, players = e.playerCount })
		end
		if
			not e.quiet
			and e.analyticsCount > 0
			and t - e.analyticsAt >= DiagnosticsService.AnalyticsEvery
		then
			sendAnalytics(e, nil)
		end
	end
	if #delta == 0 then
		return
	end
	flushing = true
	local day = Clock.day()
	task.spawn(function()
		local ok, result = pcall(function()
			local store = DataStoreService:GetDataStore(DiagnosticsService.StoreName)
			return store:UpdateAsync("Diagnostics_" .. tostring(day), function(current)
				return DiagRules.mergeDaily(current, delta)
			end)
		end)
		flushing = false
		if ok then
			for _, m in marks do
				m.entry.flushed = m.count
				m.entry.flushedPlayers = m.players
			end
			if type(result) == "table" and type(result.entries) == "table" then
				todayCache = result.entries
				todayDay = day
			end
		else
			internalErrors += 1 -- réessayé au prochain lot (rien n'est perdu)
		end
	end)
end

-- Compte un rapport (déjà normalisé côté client, renormalisé ici)
function DiagnosticsService.report(
	source: "server" | "client",
	kind: number,
	text: string,
	trace: string,
	ctx: string,
	player: Player?
)
	guarded(function()
		local k = if kind == 2 then 2 else 1
		local who = names(player)
		local normalized = DiagRules.truncate(
			DiagRules.normalize(if type(text) == "string" then text else "", who),
			LIMITS.Message
		)
		local normTrace = DiagRules.truncate(
			DiagRules.normalize(if type(trace) == "string" then trace else "", who),
			LIMITS.Trace
		)
		local normCtx = DiagRules.truncate(
			DiagRules.normalize(if type(ctx) == "string" then ctx else "", who),
			LIMITS.Context
		)
		local src: "server" | "client" = if source == "client" then "client" else "server"
		local key = DiagRules.key(normalized, src .. ":" .. scriptOf(normTrace))
		record(key, k, normalized, normTrace, normCtx, src, player)
	end)
end

-- Erreur attrapée par un pcall du serveur (étape du tick, handler) : comptée sous la clé de `where`
function DiagnosticsService.reportCaught(where: string, err: any)
	guarded(function()
		local place = DiagRules.truncate(DiagRules.normalize(tostring(where), nil), LIMITS.Key)
		local message = DiagRules.truncate(DiagRules.normalize(tostring(err), names(nil)), LIMITS.Message)
		local key = DiagRules.key("caught:" .. place, "server")
		record(key, 1, "[caught] " .. place .. " : " .. message, "", "", "server", nil)
	end)
end

-- État fermé par son délai alors qu'il aurait dû finir seul (StateTimedOut)
function DiagnosticsService.stateTimedOut(name: string, player: Player?)
	guarded(function()
		local state = DiagRules.truncate(tostring(name), 40)
		totals.timedOut += 1
		local text = "StateTimedOut:" .. state
		local key = DiagRules.key(text, "timeout")
		local before = totals.warnings
		record(key, 2, text, "", "", "server", player)
		totals.warnings = before
		local target = anyPlayer(player)
		if target ~= nil then
			Analytics.custom(target, "StateTimedOut", 1, { state = state })
		end
	end)
end

-- Compteur nommé (corps de count, sous la garde de réentrance)
local function countKey(key: string, player: Player?)
	local name = DiagRules.truncate(key, 40)
	local n = counterValues[name]
	if n == nil and name ~= "others" then
		if counterKeys >= DiagnosticsService.CounterKeys then
			name = "others"
			n = counterValues.others
		else
			counterKeys += 1
		end
	end
	counterValues[name] = (n or 0) + 1
	local text = counterText[name]
	if text == nil then
		text = "Count:" .. name
		counterText[name] = text
		counterDiagKey[name] = DiagRules.key(text, "count")
	end
	-- compté et montré aux administrateurs comme stateTimedOut, jamais un « avertissement du moteur »
	local before = totals.warnings
	record(counterDiagKey[name], 2, text, "", "", "server", player, true)
	totals.warnings = before
end

-- Compteur nommé d'un service v2.0 (docs/04 §27.14 : UpgradeStale, UpgradeTimeout, ConfigRefused,
-- PrestigeRefused, compteurs des Plopettes… ; note INT-A2-DIAG) : nombre par clé en mémoire
-- (counters), ligne « Count:<clé> » du panneau des administrateurs et des totaux du jour ; jamais un
-- warn, jamais d'analytique ServerError ; 64 clés au plus, puis « others »
function DiagnosticsService.count(key: string, player: Player?)
	if busy or type(key) ~= "string" or key == "" then
		return
	end
	busy = true
	local who = if typeof(player) == "Instance" and player:IsA("Player") then player else nil
	local ok = pcall(countKey, key, who)
	busy = false
	if not ok then
		internalErrors += 1 -- jamais un warn (il se rapporterait lui-même)
	end
	-- v2.0 (lot A4, D30) : UpgradeStale part aussi en analytique (profil v2, interrupteur ouvert)
	if FORWARD[key] and who ~= nil and meta ~= nil then
		local okMeta = pcall(meta.counted, key, who)
		if not okMeta then
			internalErrors += 1
		end
	end
end

-- Compteurs nommés de la session (copie : clé → nombre ; « others » au-delà de CounterKeys clés)
function DiagnosticsService.counters(): { [string]: number }
	return table.clone(counterValues)
end

-- Temps d'un tick (ms), noté par ChaseService s'il le mesure (panneau : moyenne et maximum)
function DiagnosticsService.noteTick(ms: number)
	if finite(ms) and ms >= 0 then
		tickStats.sum += ms
		tickStats.n += 1
		tickStats.max = math.max(tickStats.max, ms)
	end
end

local function header(): any
	local okMem, memory = pcall(function()
		return game:GetService("Stats"):GetTotalMemoryUsageMb()
	end)
	local okVer, version = pcall(function()
		return game.PlaceVersion
	end)
	return {
		placeVersion = if okVer and finite(version) then version else 0,
		utc = Clock.unix(),
		uptime = math.max(0, Clock.now() - startedAt),
		players = #Players:GetPlayers(),
		tickAvgMs = if tickStats.n > 0 then tickStats.sum / tickStats.n else 0,
		tickMaxMs = tickStats.max,
		memoryMb = if okMem and finite(memory) then memory else 0,
		timedOut = totals.timedOut,
	}
end

local function publicEntry(e: Entry): Types.DiagEntry
	return {
		key = e.key,
		kind = e.kind,
		text = e.text,
		source = e.source,
		count = e.count,
		players = e.playerCount,
		first = e.first,
		last = e.last,
	}
end

local function encodedSize(value: any): number
	local ok, json = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if ok and type(json) == "string" then
		return #json
	end
	return math.huge
end

-- Paquet du panneau (≤ 20 Ko : exemples tronqués d'abord, puis les lignes les moins fréquentes)
function DiagnosticsService.snapshot(tab: number): Types.DiagnosticsSnapshot
	local t = if tab == 1 or tab == 2 or tab == 3 then tab else 0
	local snap: Types.DiagnosticsSnapshot = {
		tab = t,
		server = header(),
		entries = {},
		samples = {},
		today = {},
	}
	if t == 0 then
		snap.server = {
			placeVersion = 0,
			utc = 0,
			uptime = 0,
			players = 0,
			tickAvgMs = 0,
			tickMaxMs = 0,
			memoryMb = 0,
			timedOut = 0,
		}
		return snap
	end
	if t == 1 then
		local sorted = {}
		for _, key in order do
			table.insert(sorted, entries[key])
		end
		table.sort(sorted, function(a: Entry, b: Entry)
			if a.count ~= b.count then
				return a.count > b.count
			end
			return a.key < b.key
		end)
		for _, e in sorted do
			table.insert(snap.entries, publicEntry(e))
			for _, sample in e.samples do
				table.insert(snap.samples, table.clone(sample))
			end
		end
	elseif t == 3 then
		-- totaux de tous les serveurs (dernière écriture) + ce qui n'est pas encore écrit
		local merged = DiagRules.mergeDaily(
			if todayDay == Clock.day() then { entries = todayCache } else nil,
			(function()
				local list = {}
				for _, key in order do
					local e = entries[key]
					if e.count > e.flushed then
						local pe = publicEntry(e)
						pe.count = e.count - e.flushed
						table.insert(list, pe)
					end
				end
				return list
			end)()
		)
		snap.today = if type(merged.entries) == "table" then merged.entries else {}
	end
	-- borne de taille : exemples d'abord (piles, puis exemples entiers), puis lignes
	local budget = LIMITS.SnapshotBytes
	if encodedSize(snap) > budget then
		for _, sample in snap.samples do
			sample.trace = DiagRules.truncate(sample.trace, 120)
			sample.ctx = DiagRules.truncate(sample.ctx, 40)
		end
	end
	while #snap.samples > 0 and encodedSize(snap) > budget do
		table.remove(snap.samples)
	end
	while #snap.entries > 0 and encodedSize(snap) > budget do
		table.remove(snap.entries)
	end
	while #snap.today > 0 and encodedSize(snap) > budget do
		table.remove(snap.today)
	end
	return snap
end

-- UserId dans Data/Admins
function DiagnosticsService.isAdmin(player: Player): boolean
	if typeof(player) ~= "Instance" then
		return false
	end
	local ok, id = pcall(function()
		return player.UserId
	end)
	return ok and type(id) == "number" and Admins[id] == true
end

-- Appareil et entrée déclarés (analytique seulement)
function DiagnosticsService.device(player: Player): Device
	local d = devices[player]
	if d == nil then
		return { kind = 0, tenFoot = false }
	end
	return { kind = d.kind, tenFoot = d.tenFoot }
end

-- Totaux de la session (tests : règle zéro trace)
function DiagnosticsService.counts(): Totals
	return { errors = totals.errors, warnings = totals.warnings, timedOut = totals.timedOut, keys = #order }
end

-- Débogage (specs) : lignes comptées (dont « autres ») et pannes internes de Diagnostics
function DiagnosticsService.debugState(): { others: number, internal: number, keys: number }
	return { others = others, internal = internalErrors, keys = #order }
end

-- Erreurs attrapées comptées (lignes « [caught] ») : clé → { count, text } (tests : règle zéro trace,
-- tests/harness/ZeroLog)
function DiagnosticsService.caught(): { [string]: { count: number, text: string } }
	local out = {}
	for _, key in order do
		local e = entries[key]
		if string.sub(e.text, 1, 8) == "[caught]" then
			out[key] = { count = e.count, text = e.text }
		end
	end
	return out
end

-- Branché au chargement du module : les autres modules du paquet comptent leurs erreurs attrapées ici
Guard.setReporter(DiagnosticsService.reportCaught)

return DiagnosticsService
