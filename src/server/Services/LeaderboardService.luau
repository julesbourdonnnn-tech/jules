--!strict
-- LeaderboardService — paquet « events » (docs/04-architecture.md §11.12).
-- Propriétaire de la clé de profil « weeklyBest » et des classements.
-- Responsabilités :
--   * tableau du serveur (mémoire) : top 5 des congas en cours (Signals.LineChanged), mis à jour
--     chaque seconde ; record de parade du serveur (Signals.Parade) → bannière serverRecord quand
--     un record existant est battu ; écrit sur la stèle (WorldService.board()) les attributs
--     Live / Record / Weekly (format "userId:name:n;userId:name:n…", noms Roblox Name)
--   * classements mondiaux : OrderedDataStore "WeeklyConga_<w>" (plus longue parade de la semaine) et
--     "AtlasAllTime" (entrées d'Atlas) ; écritures quand un joueur bat son record (file par serveur
--     vidée toutes les 60 s, en task.spawn + pcall + nouvelles tentatives), lecture du top 10 toutes
--     les 120 s ; joueurs flags.lbBanned jamais écrits
--   * titre « Roi / Reine de la Conga » : à l'arrivée, top 10 de la semaine précédente →
--     NestService.grantTemporary(player, "titles", "conga_royal")
--   * aucune boucle propre : step(now) est appelé par le tick de CongaService ; les appels
--     DataStore se font en task.spawn (jamais de yield dans step)
-- GDD : §6.4 (tableau), §6.7, §12.8 (budget DataStore).
-- Dépendances : DataService, NestService, WorldService, Signals, Util/Notify, Config/Balance,
-- Shared/Util/Clock, Events/Safe, Events/Tuning.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Validate = require(Shared.Util.Validate)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local Safe = require(Server.Events.Safe)
local Tuning = require(Server.Events.Tuning)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local NestService = require(script.Parent.NestService)

local LeaderboardService = {}

export type BoardEntry = { userId: number, name: string, n: number }

local Cfg = Balance.Leaderboard
local TAG = "LeaderboardService"
local WEEKLY_PREFIX = "WeeklyConga_"
local ATLAS_STORE = "AtlasAllTime"
local CROWN_TITLE = "conga_royal"

-- ---------------------------------------------------------------------------------------------
-- État (mémoire)
-- ---------------------------------------------------------------------------------------------

local lineLen: { [Player]: number } = {}
local live: { BoardEntry } = {}
local liveText = ""
local record: BoardEntry? = nil
local weekly: { BoardEntry } = {}
local weeklyOf = -1 -- semaine du top mondial affiché

local pendingWeekly: { [number]: { week: number, n: number } } = {} -- UserId → meilleure parade
local pendingAtlas: { [number]: number } = {} -- UserId → entrées d'Atlas

local lastLive = 0
local lastFlush = 0
local lastRead = 0
local currentWeek: number? = nil
local flushing = false
local reading = false

local crownWeek: number? = nil -- semaine dont le top 10 est connu (semaine précédente)
local crownIds: { [number]: boolean } = {}
local crownFetching = false

local nameCache: { [number]: string } = {}
local nameCacheSize = 0

-- weeklyBest remis à zéro à l'arrivée : réplication groupée au prochain step (≤ 1 tick)
-- plutôt qu'un patch séparé juste après l'instantané d'arrivée
local pendingDirty: { [Player]: boolean } = {}

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function encode(entries: { BoardEntry }): string
	local parts = table.create(#entries)
	for _, e in entries do
		table.insert(parts, `{e.userId}:{e.name}:{e.n}`)
	end
	return table.concat(parts, ";")
end

local function setBoard(attribute: string, value: string)
	Safe.call(TAG .. ".board", function()
		WorldService.board():SetAttribute(attribute, value)
	end)
end

local function isBanned(data: { [string]: any }?): boolean
	local flags = if data then data.flags else nil
	return type(flags) == "table" and flags.lbBanned == true
end

-- Nom Roblox d'un UserId (joueur présent, cache, sinon GetNameFromUserIdAsync : yield, pcall)
local function resolveName(userId: number): string
	local present = Players:GetPlayerByUserId(userId)
	if present then
		return present.Name
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and type(name) == "string" then name else tostring(userId)
	if nameCacheSize >= Tuning.NameCacheMax then
		table.clear(nameCache)
		nameCacheSize = 0
	end
	nameCache[userId] = resolved
	nameCacheSize += 1
	return resolved
end

-- Appel DataStore avec nouvelles tentatives (à n'appeler que depuis un thread task.spawn)
local function withRetries(label: string, fn: () -> any, attempts: number?): (boolean, any)
	local tries = attempts or Tuning.DataStoreAttempts
	for attempt = 1, tries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt >= tries then
			warn(`[LeaderboardService] {label} :`, result)
			return false, nil
		end
		task.wait(Tuning.DataStoreRetryDelay * 2 ^ (attempt - 1))
	end
	return false, nil
end

local function topOf(storeName: string, count: number): { { userId: number, n: number } }?
	local ok, page = withRetries(storeName .. " GetSortedAsync", function()
		local store = DataStoreService:GetOrderedDataStore(storeName)
		local pages = store:GetSortedAsync(false, count)
		return pages:GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		return nil
	end
	local out: { { userId: number, n: number } } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		local n = item.value
		if userId ~= nil and type(n) == "number" and #out < count then
			table.insert(out, { userId = userId, n = n })
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Tableau du serveur
-- ---------------------------------------------------------------------------------------------

local function updateLive()
	local entries: { BoardEntry } = {}
	for player, n in lineLen do
		if player.Parent ~= nil and n > 0 then
			table.insert(entries, { userId = player.UserId, name = player.Name, n = n })
		end
	end
	table.sort(entries, function(a, b)
		if a.n ~= b.n then
			return a.n > b.n
		end
		return a.userId < b.userId
	end)
	while #entries > Cfg.TopLive do
		table.remove(entries)
	end
	live = entries
	local text = encode(entries)
	if text ~= liveText then
		liveText = text
		setBoard("Live", text)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Classements mondiaux
-- ---------------------------------------------------------------------------------------------

local function writeOrdered(storeName: string, userId: number, value: number, attempts: number?): boolean
	local ok = withRetries(storeName .. " UpdateAsync", function()
		local store = DataStoreService:GetOrderedDataStore(storeName)
		store:UpdateAsync(tostring(userId), function(old: any)
			local previous = if type(old) == "number" then old else 0
			if value > previous then
				return value
			end
			return nil -- rien à écrire
		end)
	end, attempts)
	return ok
end

local function hasPendingWrites(): boolean
	return next(pendingWeekly) ~= nil or next(pendingAtlas) ~= nil
end

-- Joueur présent signalé par l'anti-triche APRÈS la mise en file de son record : jamais écrit
local function bannedNow(userId: number): boolean
	local present = Players:GetPlayerByUserId(userId)
	return present ~= nil and isBanned(DataService.get(present))
end

-- Écrit toute la file (yield : à appeler depuis un thread séparé) ; les échecs sont remis en file
local function drainWrites(attempts: number?)
	local weeklyBatch = pendingWeekly
	local atlasBatch = pendingAtlas
	pendingWeekly = {}
	pendingAtlas = {}
	for userId, entry in weeklyBatch do
		if
			not bannedNow(userId)
			and not writeOrdered(WEEKLY_PREFIX .. tostring(entry.week), userId, entry.n, attempts)
		then
			local again = pendingWeekly[userId]
			if again == nil or (again.week == entry.week and again.n < entry.n) then
				pendingWeekly[userId] = entry
			end
		end
	end
	for userId, total in atlasBatch do
		if not bannedNow(userId) and not writeOrdered(ATLAS_STORE, userId, total, attempts) then
			pendingAtlas[userId] = math.max(pendingAtlas[userId] or 0, total)
		end
	end
end

-- Vide la file d'écriture (une fois par FlushInterval, thread séparé)
local function flushWrites()
	if flushing or not hasPendingWrites() then
		return
	end
	flushing = true
	task.spawn(function()
		drainWrites(nil)
		flushing = false
	end)
end

-- Fermeture du serveur : les records en file (jusqu'à 60 s de parades) seraient perdus. On attend
-- le vidage en cours puis on écrit le reste, une tentative par entrée, dans la limite de temps
-- de BindToClose (mesure technique : os.clock)
local function flushOnClose()
	local start = os.clock()
	while flushing and os.clock() - start < Tuning.CloseFlushTimeout do
		task.wait(0.1)
	end
	if flushing or not hasPendingWrites() then
		return
	end
	flushing = true
	drainWrites(1)
	flushing = false
end

-- Lit le top 10 mondial de la semaine (une fois par ReadInterval, thread séparé)
local function readWeekly(week: number)
	if reading then
		return
	end
	reading = true
	task.spawn(function()
		local top = topOf(WEEKLY_PREFIX .. tostring(week), Cfg.TopWeekly)
		if top ~= nil and currentWeek == week then
			local entries: { BoardEntry } = {}
			for _, e in top do
				table.insert(entries, { userId = e.userId, name = resolveName(e.userId), n = e.n })
			end
			if currentWeek == week then
				weekly = entries
				weeklyOf = week
				setBoard("Weekly", encode(entries))
			end
		end
		reading = false
	end)
end

local function crownIfTop(player: Player)
	if crownWeek ~= nil and crownIds[player.UserId] and player.Parent ~= nil then
		Safe.call(TAG .. ".grantTemporary", NestService.grantTemporary, player, "titles", CROWN_TITLE)
	end
end

-- Top 10 de la semaine précédente → titre temporaire « Roi / Reine de la Conga »
local function fetchCrown(week: number)
	if crownFetching then
		return
	end
	crownFetching = true
	task.spawn(function()
		local previous = week - 1
		local top = topOf(WEEKLY_PREFIX .. tostring(previous), Cfg.CrownTop)
		if top ~= nil then
			table.clear(crownIds)
			for _, e in top do
				crownIds[e.userId] = true
			end
			crownWeek = previous
			for _, player in Players:GetPlayers() do
				if DataService.isLoaded(player) then
					crownIfTop(player)
				end
			end
		end
		crownFetching = false
	end)
end

-- Meilleure parade de la semaine (clé de profil weeklyBest), remise à zéro le lundi
local function weeklyBestOf(
	player: Player,
	data: { [string]: any },
	week: number,
	later: boolean?
): { [string]: any }
	local wb = data.weeklyBest
	local changed = false
	if type(wb) ~= "table" then
		wb = { week = week, conga = 0 }
		data.weeklyBest = wb
		changed = true
	end
	if wb.week ~= week or type(wb.conga) ~= "number" or wb.conga ~= wb.conga then
		wb.week = week
		wb.conga = 0
		changed = true
	end
	if changed then
		if later then
			pendingDirty[player] = true
		else
			DataService.markDirty(player, "weeklyBest")
		end
	end
	return wb
end

-- ---------------------------------------------------------------------------------------------
-- Signaux
-- ---------------------------------------------------------------------------------------------

local function onLineChanged(player: Player, n: number)
	if not Validate.finiteNumber(n) or player.Parent == nil then
		return
	end
	local v = math.max(0, math.floor(n))
	lineLen[player] = if v > 0 then v else nil
end

local function onParade(player: Player, info: Types.ParadeInfo)
	if type(info) ~= "table" or not Validate.integer(info.count, 1) or player.Parent == nil then
		return
	end
	local count = info.count
	-- record du serveur : le premier est posé en silence, les suivants battus ont leur bannière
	local current = record
	if current == nil or count > current.n then
		record = { userId = player.UserId, name = player.Name, n = count }
		setBoard("Record", encode({ record :: BoardEntry }))
		if current ~= nil then
			Notify.banner(
				"serverRecord",
				{ userId = player.UserId, name = player.DisplayName, n = count },
				player
			)
		end
	end
	-- record de la semaine (mondial)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local week = Clock.week()
	local wb = weeklyBestOf(player, data, week)
	if count > wb.conga then
		wb.conga = count
		DataService.markDirty(player, "weeklyBest")
		if not isBanned(data) then
			pendingWeekly[player.UserId] = { week = week, n = count }
		end
	end
end

local function onAtlasEntry(player: Player, _s: number, _f: number, total: number)
	if not Validate.integer(total, 1) then
		return
	end
	local data = DataService.get(player)
	if data == nil or isBanned(data) then
		return
	end
	pendingAtlas[player.UserId] = math.max(pendingAtlas[player.UserId] or 0, total)
end

local function onLoaded(player: Player, data: { [string]: any })
	if player.Parent == nil or type(data) ~= "table" then
		return
	end
	weeklyBestOf(player, data, Clock.week(), true)
	crownIfTop(player)
end

local function onPlayerRemoving(player: Player)
	lineLen[player] = nil
	pendingDirty[player] = nil
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

function LeaderboardService.Init() end

function LeaderboardService.Start()
	DataService.Loaded:Connect(onLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Signals.LineChanged:Connect(onLineChanged)
	Signals.Parade:Connect(onParade)
	Signals.AtlasEntry:Connect(onAtlasEntry)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			task.spawn(onLoaded, player, data)
		end
	end
	setBoard("Live", "")
	setBoard("Record", "")
	setBoard("Weekly", "")
	game:BindToClose(flushOnClose)
end

-- Tableau en direct (1 s), file d'écriture (60 s), lecture du top 10 (120 s), semaine
function LeaderboardService.step(now: number)
	if not Validate.finiteNumber(now) then
		return
	end
	local week = Clock.week(now)
	if currentWeek ~= week then
		local first = currentWeek == nil
		currentWeek = week
		weekly = {}
		weeklyOf = -1
		lastRead = 0
		if not first then
			setBoard("Weekly", "")
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data then
					weeklyBestOf(player, data, week)
				end
			end
		end
		fetchCrown(week)
	end
	for player in pendingDirty do
		pendingDirty[player] = nil
		if player.Parent ~= nil then
			DataService.markDirty(player, "weeklyBest")
		end
	end
	if lastLive == 0 or now - lastLive >= Cfg.LiveInterval then
		lastLive = now
		updateLive()
	end
	if lastFlush == 0 or now - lastFlush >= Cfg.FlushInterval then
		lastFlush = now
		flushWrites()
	end
	if lastRead == 0 or now - lastRead >= Cfg.ReadInterval then
		lastRead = now
		readWeekly(week)
		-- couronne pas encore connue (lecture en échec au démarrage ou au changement de semaine) :
		-- nouvel essai au rythme des lectures, sinon personne n'aurait son titre de la semaine
		if crownWeek ~= week - 1 then
			fetchCrown(week)
		end
	end
end

function LeaderboardService.liveTop(): { BoardEntry }
	return table.clone(live)
end

function LeaderboardService.serverRecord(): BoardEntry?
	local r = record
	return if r then table.clone(r) else nil
end

function LeaderboardService.weeklyTop(): { BoardEntry }
	if weeklyOf ~= currentWeek then
		return {}
	end
	return table.clone(weekly)
end

return LeaderboardService
