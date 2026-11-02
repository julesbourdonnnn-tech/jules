--!strict
-- Wrapper sûr autour d'AnalyticsService (jamais bloquant, jamais d'erreur remontée).
--   Analytics.funnel(player, 3, "FirstUpgrade")       -- entonnoir de première session
--   Analytics.earn(player, "Coins", 50, balance, "Gameplay", "harvest")
--   Analytics.spend(player, "Coins", 100, balance, "Shop", "upgrade_speed")
--   Analytics.event(player, "RareFound", 1)
-- transactionType : nom d'un Enum.AnalyticsEconomyTransactionType (IAP, Shop, Gameplay,
-- ContextualPurchase, TimedReward, Onboarding).
--
-- Note INT-ANALYTICS (paquet meta, contrat v1.2, GDD §16) : le jeu vise 10 requêtes au plus par joueur
-- et par minute (Roblox : 120 + 20 × joueurs par serveur, au-delà tout est perdu, PostBoopQuit compris).
--   Analytics.earnIncome(player, sku, coins, incomePerSecond, txType)   -- source cumulée
--   Analytics.spendIncome(player, sku, coins, incomePerSecond, txType)  -- puits cumulé
--   Analytics.custom(player, name, value, fields?)                      -- événement personnalisé
--   Analytics.setSegment(player, "device" | "sessionBand", valeur)      -- champs de segmentation
--   Analytics.flush(player)                                             -- départ (et BindToClose)
--   Analytics.step(now)                                                 -- appelé par DiagnosticsService.step
-- * Économie : chaque source et chaque puits est CUMULÉ par joueur, par tranche de 5 min et par
--   (flux, itemSku, type de transaction) ; montants en SECONDES DE REVENU du joueur (chaque montant est
--   converti avec le revenu au moment où il arrive, le solde avec le dernier revenu connu) : un
--   événement par itemSku et par tranche, envoyé quand la tranche se ferme (ou au départ).
-- * Débit : seau de 10 requêtes par joueur sur 60 s glissantes (temps Clock.now() du serveur), commun à
--   l'entonnoir, à l'économie et aux événements personnalisés. Au-delà, la requête attend dans une file
--   bornée (40), vidée dès qu'une place se libère (Analytics.step, appel suivant) ; file pleine : la plus
--   ancienne requête ordinaire est jetée (les importantes, PostBoopQuit, SessionLength…, d'abord
--   gardées). Au départ et à la fermeture, ce qui dépasse le débit est jeté et compté (stats().dropped) :
--   la règle des 10 par minute n'est jamais dépassée.
-- * Champs personnalisés (Roblox : 3 au plus) : ceux de l'appelant s'il en donne (« clé:valeur », par
--   ordre de clé), sinon les 3 champs de segmentation du GDD §16 (device, serverBand, sessionBand).
-- Les appels qui échouent font un avertissement « [Analytics] » (socle), jamais une erreur.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Util.Clock)

local Analytics = {}

-- Réglages (nommés ; specs : Analytics_game)
Analytics.BucketSeconds = 300 -- tranche de cumul de l'économie
Analytics.PerPlayerPerMinute = 10 -- requêtes par joueur sur 60 s glissantes
Analytics.Window = 60
Analytics.QueueMax = 40

-- Catalogue des événements personnalisés du jeu (GDD §16.3) ; un nom hors catalogue part quand même
-- (compté dans stats().unknown : une faute de frappe se voit dans les specs). ShopHiddenByPolicy est
-- remplacé par PolicyPaidRandomRestricted (contrat v1.2).
-- stylua: ignore start
Analytics.Events = {
	"RushModeChosen", "ModeAtSessionEnd", "CozyAfterBoop", "RefuseBooper", "FirstBoopReceived",
	"PostBoopQuit", "QuitBaseline", "BoopDone", "EscapeOutcome", "RushCatchByInput", "MegaResult",
	"GaugeFilled", "SplorchReached", "TileLevelAtSplorch", "BoostShare", "ComboLength",
	"ObjectivesAllDone", "SplorchCoinsLost", "HatchRarity", "MutationGot", "RideStart", "PetSitPress",
	"FriendsOnServer", "ShopOpened", "PolicyPaidRandomRestricted", "MoveViolation", "ServerFullKick",
	"SleepyCardShown", "SessionLength", "ServerError", "ClientError", "FocusRescued", "StateTimedOut",
	"QualityReduced", "TouchDeviceJoined",
}
-- stylua: ignore end

-- Événements gardés en priorité quand la file déborde (indicateurs de sécurité, fin de session)
local IMPORTANT: { [string]: boolean } = {
	PostBoopQuit = true,
	QuitBaseline = true,
	SessionLength = true,
	ModeAtSessionEnd = true,
	BoostShare = true,
	ServerError = true,
	ClientError = true,
}

local KNOWN: { [string]: boolean } = {}
for _, name in Analytics.Events do
	KNOWN[name] = true
end

type Request = { important: boolean, run: () -> () }
type Entry = { flow: string, sku: string, txType: string, seconds: number }
type State = {
	bucket: number,
	entries: { [string]: Entry },
	order: { string },
	ips: number, -- dernier revenu connu (pièces par seconde)
	balance: number, -- dernier solde connu (pièces)
	sent: { number }, -- instants des requêtes des 60 dernières secondes
	queue: { Request },
	segments: { [string]: string },
}

local states: { [Player]: State } = {}
-- joueurs partis : fenêtre gardée (requêtes « au départ » des autres services), jamais de file
local gone: { [Player]: State } = setmetatable({}, { __mode = "k" }) :: any
local funnelDone: { [Player]: { [number]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local totals = { requests = 0, dropped = 0, queued = 0, unknown = 0 }

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function safe(fn: () -> ())
	task.spawn(function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[Analytics]", err)
		end
	end)
end

local function newState(): State
	return {
		bucket = -1,
		entries = {},
		order = {},
		ips = 0,
		balance = 0,
		sent = {},
		queue = {},
		segments = {},
	}
end

local function stateOf(player: Player): State
	local s = states[player] or gone[player]
	if s == nil then
		s = newState()
		if player.Parent == nil then
			gone[player] = s
		else
			states[player] = s
		end
	end
	return s
end

local function bucketOf(now: number): number
	return math.floor(now / Analytics.BucketSeconds)
end

-- Places libres dans la fenêtre glissante (les instants trop vieux sont oubliés)
local function freeSlots(s: State, now: number): number
	local keep = {}
	for _, t in s.sent do
		if now - t < Analytics.Window then
			table.insert(keep, t)
		end
	end
	s.sent = keep
	return Analytics.PerPlayerPerMinute - #keep
end

local function sendNow(s: State, now: number, request: Request)
	table.insert(s.sent, now)
	totals.requests += 1
	safe(request.run)
end

-- File pleine : la plus ancienne requête ordinaire part en premier (sinon la plus ancienne tout court)
local function enqueue(s: State, request: Request)
	if #s.queue >= Analytics.QueueMax then
		local victim = 1
		for i, r in s.queue do
			if not r.important then
				victim = i
				break
			end
		end
		if request.important or not s.queue[victim].important then
			table.remove(s.queue, victim)
			totals.dropped += 1
		else
			totals.dropped += 1
			return
		end
	end
	table.insert(s.queue, request)
	totals.queued += 1
end

-- Vide la file tant que la fenêtre le permet (les importantes d'abord)
local function drain(s: State, now: number)
	local free = freeSlots(s, now)
	while free > 0 and #s.queue > 0 do
		local index = 1
		for i, r in s.queue do
			if r.important then
				index = i
				break
			end
		end
		local request = table.remove(s.queue, index) :: Request
		sendNow(s, now, request)
		free -= 1
	end
end

local function request(player: Player, important: boolean, run: () -> ())
	local now = Clock.now()
	local s = stateOf(player)
	drain(s, now)
	local r: Request = { important = important, run = run }
	if #s.queue == 0 and freeSlots(s, now) > 0 then
		sendNow(s, now, r)
	elseif gone[player] == s then
		totals.dropped += 1 -- joueur parti : plus de file, jamais au-delà du débit
	else
		enqueue(s, r)
	end
end

-- Champs personnalisés (3 au plus) ; nil si l'énumération manque (jamais une erreur)
local FIELD_KEYS: { any } = {}
do
	local ok, enum = pcall(function()
		return (Enum :: any).AnalyticsCustomFieldKeys
	end)
	if ok and enum ~= nil then
		for _, name in { "CustomField01", "CustomField02", "CustomField03" } do
			local okItem, item = pcall(function()
				return enum[name]
			end)
			if okItem and item ~= nil then
				table.insert(FIELD_KEYS, item)
			end
		end
	end
end

local function fieldText(key: string, value: any): string
	local text = if type(value) == "number"
		then (if finite(value) then string.format("%.4g", value) else "0")
		else tostring(value)
	return string.sub(key .. ":" .. text, 1, 50)
end

local function serverBand(): string
	local n = #Players:GetPlayers()
	return if n <= 5 then "1-5" elseif n <= 10 then "6-10" else "11-16"
end

local function customFields(player: Player, fields: { [string]: any }?): { [any]: string }?
	if #FIELD_KEYS < 3 then
		return nil
	end
	local texts: { string } = {}
	if type(fields) == "table" and next(fields) ~= nil then
		local keys = {}
		for k in fields do
			if type(k) == "string" then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		for i = 1, math.min(3, #keys) do
			table.insert(texts, fieldText(keys[i], fields[keys[i]]))
		end
	else
		local s = stateOf(player)
		texts = {
			"device:" .. (s.segments.device or "unknown"),
			"serverBand:" .. serverBand(),
			"sessionBand:" .. (s.segments.sessionBand or "unknown"),
		}
	end
	local out: { [any]: string } = {}
	for i, text in texts do
		out[FIELD_KEYS[i]] = text
	end
	return out
end

-- =============================================================================================
-- API du socle (inchangée), désormais au débit commun
-- =============================================================================================

-- Étapes numérotées 1, 2, 3… ; chaque étape n'est envoyée qu'une fois par session
function Analytics.funnel(player: Player, step: number, stepName: string)
	local done = funnelDone[player]
	if not done then
		done = {}
		funnelDone[player] = done
	end
	if done[step] then
		return
	end
	done[step] = true
	request(player, true, function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

local function economy(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	if not finite(amount) or amount <= 0 then
		return
	end
	local safeBalance = if finite(balance) then balance else 0
	request(player, false, function()
		AnalyticsService:LogEconomyEvent(
			player,
			flow,
			currency,
			math.floor(amount),
			math.floor(safeBalance),
			transactionType,
			sku
		)
	end)
end

function Analytics.earn(
	player: Player,
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	economy(player, Enum.AnalyticsEconomyFlowType.Source, currency, amount, balance, transactionType, sku)
end

function Analytics.spend(
	player: Player,
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	economy(player, Enum.AnalyticsEconomyFlowType.Sink, currency, amount, balance, transactionType, sku)
end

function Analytics.event(player: Player, name: string, value: number?)
	Analytics.custom(player, name, value or 1, nil)
end

-- =============================================================================================
-- INT-ANALYTICS : cumul de l'économie, événements personnalisés, segmentation
-- =============================================================================================

-- Envoie les entrées cumulées de la tranche en cours (un événement par itemSku), en secondes de revenu
local function closeBucket(player: Player, s: State)
	if #s.order == 0 then
		return
	end
	local ips = if s.ips > 0 then s.ips else 1
	local balanceSeconds = math.floor(math.max(0, s.balance) / ips)
	local entries, order = s.entries, s.order
	s.entries, s.order = {}, {}
	for _, key in order do
		local e = entries[key]
		local seconds = math.max(1, math.floor(e.seconds + 0.5))
		local flow = if e.flow == "Sink"
			then Enum.AnalyticsEconomyFlowType.Sink
			else Enum.AnalyticsEconomyFlowType.Source
		local sku, txType = e.sku, e.txType
		request(player, false, function()
			AnalyticsService:LogEconomyEvent(player, flow, "Coins", seconds, balanceSeconds, txType, sku)
		end)
	end
end

local function accumulate(
	player: Player,
	flow: string,
	sku: string,
	coins: number,
	incomePerSecond: number,
	txType: string,
	balance: number?
)
	if not finite(coins) or coins <= 0 or type(sku) ~= "string" or sku == "" then
		return
	end
	local now = Clock.now()
	local s = stateOf(player)
	local b = bucketOf(now)
	if b ~= s.bucket then
		closeBucket(player, s)
		s.bucket = b
	end
	local ips = if finite(incomePerSecond) and incomePerSecond > 0 then incomePerSecond else 0
	if ips > 0 then
		s.ips = ips
	end
	if finite(balance) then
		s.balance = math.max(0, balance :: number)
	end
	local tx = if type(txType) == "string" and txType ~= "" then txType else "Gameplay"
	local key = flow .. "|" .. string.sub(sku, 1, 50) .. "|" .. tx
	local e = s.entries[key]
	if e == nil then
		e = { flow = flow, sku = string.sub(sku, 1, 50), txType = tx, seconds = 0 }
		s.entries[key] = e
		table.insert(s.order, key)
	end
	-- montant converti au revenu de son instant (un revenu nul compte 1 pièce = 1 s)
	e.seconds += coins / (if ips > 0 then ips else 1)
end

-- Source de pièces cumulée (balance : solde en pièces après la source, facultatif)
function Analytics.earnIncome(
	player: Player,
	sku: string,
	coins: number,
	incomePerSecond: number,
	txType: string,
	balance: number?
)
	accumulate(player, "Source", sku, coins, incomePerSecond, txType, balance)
end

-- Puits de pièces cumulé
function Analytics.spendIncome(
	player: Player,
	sku: string,
	coins: number,
	incomePerSecond: number,
	txType: string,
	balance: number?
)
	accumulate(player, "Sink", sku, coins, incomePerSecond, txType, balance)
end

-- Événement personnalisé (valeur finie ; champs facultatifs, 3 au plus)
function Analytics.custom(player: Player, name: string, value: number?, fields: { [string]: any }?)
	if type(name) ~= "string" or name == "" then
		return
	end
	if not KNOWN[name] then
		totals.unknown += 1
	end
	local v = if finite(value) then value :: number else 1
	local cf = customFields(player, fields)
	request(player, IMPORTANT[name] == true, function()
		if cf ~= nil then
			AnalyticsService:LogCustomEvent(player, name, v, cf)
		else
			AnalyticsService:LogCustomEvent(player, name, v)
		end
	end)
end

-- Champ de segmentation du joueur : "device" (console / pcGamepad / pcKeyboard / touch) ou
-- "sessionBand" (first / 2-5 / 6+) ; posé par DiagnosticsService et QuestService
function Analytics.setSegment(player: Player, key: string, value: string)
	if (key == "device" or key == "sessionBand") and type(value) == "string" then
		stateOf(player).segments[key] = string.sub(value, 1, 24)
	end
end

-- Ferme les tranches échues et vide les files (DiagnosticsService.step, 10 Hz : bon marché)
function Analytics.step(now: number)
	local t = if finite(now) then now else Clock.now()
	local b = bucketOf(t)
	for player, s in states do
		if s.bucket ~= b and #s.order > 0 then
			closeBucket(player, s)
			s.bucket = b
		end
		if #s.queue > 0 then
			drain(s, t)
		end
	end
end

-- Départ (ou fermeture) : la tranche en cours part, la file est vidée au débit ; le reste est jeté
-- et compté (jamais plus de 10 requêtes par minute, même au départ)
function Analytics.flush(player: Player)
	local s = states[player]
	if s == nil then
		return
	end
	closeBucket(player, s)
	drain(s, Clock.now())
	totals.dropped += #s.queue
	table.clear(s.queue)
	states[player] = nil
	gone[player] = s
end

-- Compteurs (specs) ; pending = requêtes en attente et entrées non envoyées du joueur
function Analytics.stats(player: Player?): {
	requests: number,
	dropped: number,
	queued: number,
	unknown: number,
	pending: number,
}
	local pending = 0
	if player ~= nil then
		local s = states[player]
		if s ~= nil then
			pending = #s.queue + #s.order
		end
	end
	return {
		requests = totals.requests,
		dropped = totals.dropped,
		queued = totals.queued,
		unknown = totals.unknown,
		pending = pending,
	}
end

-- Le nom est-il au catalogue du jeu ?
function Analytics.isKnown(name: string): boolean
	return KNOWN[name] == true
end

-- Départ : flush branché par l'utilitaire lui-même (comme RateLimit et Activity). Les services qui
-- envoient un événement « au départ » dans leur propre PlayerRemoving passent après : leur requête part
-- au débit restant (le joueur est encore là pendant l'événement).
Players.PlayerRemoving:Connect(function(player: Player)
	Analytics.flush(player)
	funnelDone[player] = nil
end)

-- Fermeture du serveur : la tranche en cours de chaque joueur présent part (au débit)
pcall(function()
	game:BindToClose(function()
		for player in states do
			Analytics.flush(player)
		end
	end)
end)

return Analytics
