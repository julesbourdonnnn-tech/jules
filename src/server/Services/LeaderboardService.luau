--!strict
-- LeaderboardService (paquet meta, docs/04 §11.13) — classements de la semaine (GDD §6.6, §6.9).
--   * 5 catégories (Types.LeaderboardCategory) : stamps (tampons et badges gagnés cette semaine),
--     combo (meilleur combo), catchScore (meilleure capture = rareté × mutation), helpful (pressions de
--     pet-sitting comptées : PetSitRewarded avec son 3e argument vrai), generous (bébés donnés : bébé né
--     d'une fuite capturée par un autre, cadeaux des Grands Splorch).
--   * Valeur codée (contrat v1.2, GDD §6.9) : un OrderedDataStore ne garde que des entiers ;
--     v = ((score × 2^20) + (2^20 − 1 − s)) × 2 + caché, s = secondes depuis lundi 00:00 UTC à l'écriture
--     (à score égal, le premier arrivé passe devant), caché = 1 si le nom est caché. Plus grande valeur :
--     500 000 → ≈ 1,05e12 < 2^53 (aucun arrondi). LeaderboardService.encode / decode (purs).
--   * Écritures groupées toutes les 60 s (UpdateAsync : jamais un record plus bas que celui du magasin ;
--     changement de « caché » : seul le drapeau est réécrit, l'heure d'arrivée est gardée), lectures du
--     top 10 toutes les 120 s, noms par UserService:GetUserInfosByUserIdsAsync (un appel, cache de la
--     semaine) ; tout en task.spawn et sous pcall, jamais dans le thread du tick. Caché, inconnu ou panne →
--     name = "" (le client écrit l'alias). Bannis (flags.lbBanUntil > Clock.unix()) jamais écrits.
--   * Changement de semaine (lundi 00:00 UTC) : weekly.prev, valeurs à 0 ; titres du top 10 de la semaine
--     passée accordés pour la semaine par CommunityService.unlockSession, à chaque arrivée.
--   * Statue : plus gros squishy du serveur toutes les 2 s (WorldService.setStatue, nom vide si caché) ;
--     fanfare du premier à 1e6, 1e9, 1e12, 1e15 sur ce serveur (Notify.banner « record », Celebrate
--     « fanfare »).
-- Remote : LeaderboardState. Clé : weekly.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Events = require(Shared.Config.Events)
local Cosmetics = require(Shared.Config.Cosmetics)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local Guard = require(Server.Meta.Guard)
local DataService = require(Server.Services.DataService)
local WorldService = require(Server.Services.WorldService)
local SquishyService = require(Server.Services.SquishyService)
local CommunityService = require(Server.Services.CommunityService)

local LeaderboardService = {}

local CATEGORIES = { "stamps", "combo", "catchScore", "helpful", "generous" }
local SHIFT = 2 ^ 20 -- une semaine compte 604 800 s < 2^20
local WEEK = 604800
local WEEK_EPOCH = 345600 -- lundi 05/01/1970 00:00 UTC (Clock.week)
LeaderboardService.WriteEvery = 60
LeaderboardService.ReadEvery = 120
LeaderboardService.StatueEvery = 2
LeaderboardService.TopSize = 10
LeaderboardService.StateEvery = 5 -- s : LeaderboardState après un record, au plus toutes les 5 s
LeaderboardService.MaxScore = 500000 -- meilleure capture : 5 000 × 100
LeaderboardService.CloseBudget = 20 -- s (os.clock) : écritures de la fermeture, sous les 30 s de BindToClose
LeaderboardService.TitlesEvery = 600 -- s : titres de la semaine passée relus (derniers lots des autres serveurs)

-- titre de la semaine suivante pour le top 10 de chaque catégorie (Config/Cosmetics, source weekly)
local TITLE_OF: { [string]: string } = {}
for _, def in Cosmetics.List do
	if def.kind == "title" and def.source.kind == "weekly" and def.source.key then
		TITLE_OF[def.source.key] = def.id
	end
end

type Pending = {
	week: number, -- semaine du record : écrit dans SON magasin, même si le lot part après lundi 00:00
	userId: number,
	category: string,
	score: number,
	hidden: boolean,
	s: number,
	hideOnly: boolean,
}

local pending: { [string]: Pending } = {} -- "<semaine>:<cat>:<userId>" → écriture du prochain lot
local recordAt: { [Player]: { [string]: number } } = {} -- seconde de la semaine du record (égalités du serveur)
local tops: { [string]: { Types.LeaderboardRow } } = {}
local names: { [number]: string } = {} -- cache de la semaine (UserService)
local prevTitles: { [number]: { string } } = {} -- userId → titres gagnés la semaine passée
local prevTitlesWeek = -1
local currentWeek = -1
local lastWrite = -math.huge
local lastRead = -math.huge
local lastStatue = -math.huge
local lastTitles = -math.huge
local writing = false
local reading = false
local stateDue: { [Player]: number } = {}
local fanfares: { [number]: boolean } = {}
local started = false

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x: any, default: number): number
	return if finite(x) then x else default
end

-- Profil du jeu chargé (clé weekly présente) ; un profil d'un autre schéma n'est jamais touché
local function profile(player: Player): { [string]: any }?
	local ok, data = pcall(DataService.get, player)
	if ok and type(data) == "table" and type(data.weekly) == "table" then
		return data
	end
	return nil
end

local function weekOf(t: number): number
	return math.floor((t - WEEK_EPOCH) / WEEK)
end

local function secondsSinceMonday(t: number): number
	return math.clamp(math.floor(t - (weekOf(t) * WEEK + WEEK_EPOCH)), 0, SHIFT - 1)
end

local function storeName(category: string, week: number): string
	return "Weekly_" .. category .. "_" .. tostring(week)
end

-- =============================================================================================
-- Valeur codée (pure)
-- =============================================================================================

-- ((score × 2^20) + (2^20 − 1 − s)) × 2 + caché ; score entier dans [0 ; MaxScore], s dans [0 ; 2^20[
function LeaderboardService.encode(score: number, seconds: number, hidden: boolean): number
	local sc = math.clamp(math.floor(num(score, 0)), 0, LeaderboardService.MaxScore)
	local s = math.clamp(math.floor(num(seconds, 0)), 0, SHIFT - 1)
	return ((sc * SHIFT) + (SHIFT - 1 - s)) * 2 + (if hidden then 1 else 0)
end

-- Décodage exact : (score, secondes depuis lundi, caché)
function LeaderboardService.decode(value: number): (number, number, boolean)
	local v = math.max(0, math.floor(num(value, 0)))
	local hidden = v % 2 == 1
	local u = math.floor(v / 2)
	local score = math.floor(u / SHIFT)
	local s = SHIFT - 1 - (u % SHIFT)
	return score, s, hidden
end

-- =============================================================================================
-- Valeurs de la semaine
-- =============================================================================================

local function weeklyOf(data: { [string]: any }): { [string]: any }
	if type(data.weekly) ~= "table" then
		data.weekly = { week = 0, prev = {} }
	end
	local w = data.weekly
	if type(w.prev) ~= "table" then
		w.prev = {}
	end
	for _, c in CATEGORIES do
		w[c] = math.max(0, math.floor(num(w[c], 0)))
		w.prev[c] = math.max(0, math.floor(num(w.prev[c], 0)))
	end
	return w
end

-- Semaine du profil remise à l'heure : la semaine passée devient prev, les valeurs repartent de 0
local function rollWeek(player: Player, data: { [string]: any }, week: number)
	local w = weeklyOf(data)
	if w.week == week then
		return
	end
	local prev = {}
	for _, c in CATEGORIES do
		prev[c] = if w.week == week - 1 then w[c] else 0
		w[c] = 0
	end
	w.prev = prev
	w.week = week
	DataService.markDirty(player, "weekly")
	recordAt[player] = {}
end

local function hiddenOf(player: Player): boolean
	return Guard.call("leaderboard:hidden", CommunityService.setting, false, player, "hideName") == true
end

local function queueWrite(player: Player, category: string, score: number, hideOnly: boolean)
	local key = tostring(currentWeek) .. ":" .. category .. ":" .. tostring(player.UserId)
	local existing = pending[key]
	-- heure d'arrivée : celle du record lui-même (un nouveau record dans le même lot la remplace) ; un
	-- simple changement de « caché » garde celle du record en attente ou du dernier record de la session
	local s
	if not hideOnly then
		s = secondsSinceMonday(Clock.unix())
	elseif existing ~= nil then
		s = existing.s
	else
		local at = recordAt[player]
		s = if at ~= nil and at[category] ~= nil then at[category] else secondsSinceMonday(Clock.unix())
	end
	pending[key] = {
		week = currentWeek,
		userId = player.UserId,
		category = category,
		score = score,
		hidden = hiddenOf(player),
		s = s,
		hideOnly = hideOnly and (existing == nil or existing.hideOnly),
	}
end

local function catchScore(info: any): number
	local rarity = Rarities.List[math.floor(num(info.rarity, 1))]
	local mutation = Mutations.ById[math.floor(num(info.mutation, 0))]
	local score = (if rarity then rarity.mult else 1) * (if mutation then mutation.mult else 1)
	return math.floor(score + 0.5)
end

-- =============================================================================================
-- Lectures, écritures (task.spawn, pcall)
-- =============================================================================================

local function writeBatch(batch: { [string]: Pending }, deadline: number?)
	for _, entry in batch do
		if deadline ~= nil and os.clock() > deadline then
			return -- fermeture : délai de BindToClose presque écoulé
		end
		pcall(function()
			local store = DataStoreService:GetOrderedDataStore(storeName(entry.category, entry.week))
			store:UpdateAsync(tostring(entry.userId), function(old: any)
				local fresh = LeaderboardService.encode(entry.score, entry.s, entry.hidden)
				if not finite(old) then
					return fresh
				end
				local oldScore, _, oldHidden = LeaderboardService.decode(old)
				if entry.score > oldScore then
					return fresh
				end
				if entry.score == oldScore and oldHidden ~= entry.hidden then
					-- seul le drapeau change : l'heure d'arrivée est gardée
					return math.floor(old / 2) * 2 + (if entry.hidden then 1 else 0)
				end
				return nil -- record du magasin gardé
			end)
		end)
	end
end

local function flushWrites()
	if writing or next(pending) == nil then
		return
	end
	local batch = pending
	pending = {}
	writing = true
	task.spawn(function()
		writeBatch(batch, nil)
		writing = false
	end)
end

-- Fermeture du serveur : le lot en vol se termine, puis ce qui attend est écrit dans ce thread
-- (borné : DataService partage les 30 s de BindToClose)
local function flushOnClose()
	local deadline = os.clock() + LeaderboardService.CloseBudget
	while writing and os.clock() < deadline do
		task.wait(0.1)
	end
	if next(pending) == nil then
		return
	end
	local batch = pending
	pending = {}
	writeBatch(batch, deadline)
end

local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if names[id] == nil then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and finite(info.Id) then
				local name = if type(info.DisplayName) == "string" and info.DisplayName ~= ""
					then info.DisplayName
					else info.Username
				names[info.Id] = if type(name) == "string" then string.sub(name, 1, 40) else ""
			end
		end
	end
	-- échec ou nom absent : "" (alias côté client), jamais un avertissement
end

-- Top 10 d'un magasin : lignes décodées (rang, userId, valeur, caché)
local function readTop(category: string, week: number): { { userId: number, score: number, hidden: boolean } }
	local out = {}
	local ok, pages = pcall(function()
		local store = DataStoreService:GetOrderedDataStore(storeName(category, week))
		return store:GetSortedAsync(false, LeaderboardService.TopSize)
	end)
	if not ok or pages == nil then
		return out
	end
	local okPage, page = pcall(function()
		return (pages :: any):GetCurrentPage()
	end)
	if not okPage or type(page) ~= "table" then
		return out
	end
	for _, item in page do
		local id = tonumber(item.key)
		if id ~= nil and finite(item.value) and #out < LeaderboardService.TopSize then
			local score, _, hidden = LeaderboardService.decode(item.value)
			table.insert(out, { userId = id, score = score, hidden = hidden })
		end
	end
	return out
end

local function sendState(player: Player)
	if player.Parent == nil then
		return
	end
	local data = profile(player)
	if data == nil then
		return
	end
	local w = weeklyOf(data)
	local boards = {}
	for _, c in CATEGORIES do
		local server = {}
		for _, p in Players:GetPlayers() do
			local d = profile(p)
			if d ~= nil and not LeaderboardService.isBanned(p) then
				local value = weeklyOf(d)[c]
				if value > 0 then
					local at = recordAt[p] and recordAt[p][c] or SHIFT
					table.insert(server, { p = p, value = value, at = at })
				end
			end
		end
		table.sort(server, function(a, b)
			if a.value ~= b.value then
				return a.value > b.value
			end
			if a.at ~= b.at then
				return a.at < b.at
			end
			return a.p.UserId < b.p.UserId
		end)
		local rows: { Types.LeaderboardRow } = {}
		local myRank = 0
		for i, row in server do
			if row.p == player then
				myRank = i
			end
			if i <= LeaderboardService.TopSize then
				table.insert(rows, {
					rank = i,
					userId = row.p.UserId,
					name = CommunityService.displayName(row.p),
					value = row.value,
				})
			end
		end
		boards[c] = {
			top = table.clone(tops[c] or {}),
			server = rows,
			mine = w[c],
			minePrev = w.prev[c],
			myServerRank = myRank,
		}
	end
	local payload: Types.LeaderboardPayload = { week = currentWeek, boards = boards }
	Net.event("LeaderboardState"):FireClient(player, payload)
end

local function readTops()
	if reading then
		return
	end
	reading = true
	local week = currentWeek
	task.spawn(function()
		local raw = {}
		local ids = {}
		for _, c in CATEGORIES do
			raw[c] = readTop(c, week)
			for _, row in raw[c] do
				if not row.hidden then
					table.insert(ids, row.userId)
				end
			end
		end
		resolveNames(ids)
		if week == currentWeek then
			for _, c in CATEGORIES do
				local rows: { Types.LeaderboardRow } = {}
				for i, row in raw[c] do
					table.insert(rows, {
						rank = i,
						userId = row.userId,
						name = if row.hidden then "" else (names[row.userId] or ""),
						value = row.score,
					})
				end
				tops[c] = rows
			end
		end
		reading = false
		for _, p in Players:GetPlayers() do
			sendState(p)
		end
	end)
end

-- Titres de la semaine : top 10 de chaque catégorie de la semaine passée
local function grantTitles(player: Player)
	local list = prevTitles[player.UserId]
	if list == nil then
		return
	end
	for _, id in list do
		Guard.try("leaderboard:unlock", CommunityService.unlockSession, player, "title", id)
	end
end

local function loadPrevTitles()
	local week = currentWeek
	if prevTitlesWeek == week then
		return
	end
	prevTitlesWeek = week
	task.spawn(function()
		local map: { [number]: { string } } = {}
		for _, c in CATEGORIES do
			local title = TITLE_OF[c]
			if title ~= nil then
				for _, row in readTop(c, week - 1) do
					if row.score > 0 then
						map[row.userId] = map[row.userId] or {}
						table.insert(map[row.userId], title)
					end
				end
			end
		end
		if prevTitlesWeek ~= week then
			return
		end
		prevTitles = map
		for _, p in Players:GetPlayers() do
			grantTitles(p)
		end
	end)
end

-- =============================================================================================
-- Statue et fanfare
-- =============================================================================================

local function stepStatue()
	local bestPlayer: Player? = nil
	local bestSize = 0
	local bestUid: string? = nil
	for _, p in Players:GetPlayers() do
		local ok, uid, size = pcall(SquishyService.biggest, p)
		if ok and type(uid) == "string" and finite(size) and size > bestSize then
			bestPlayer, bestSize, bestUid = p, size, uid
		end
	end
	if bestPlayer == nil or bestUid == nil then
		Guard.try("leaderboard:statue", WorldService.setStatue, 0, 0, 0, "")
		return
	end
	local okRec, rec = pcall(SquishyService.get, bestPlayer, bestUid)
	local species = if okRec and type(rec) == "table" then rec.s else 0
	local mutation = if okRec and type(rec) == "table" then rec.m else 0
	Guard.try(
		"leaderboard:statue",
		WorldService.setStatue,
		species,
		mutation,
		bestSize,
		CommunityService.displayName(bestPlayer)
	)
	for _, threshold in Events.Banners.RecordThresholds do
		if bestSize >= threshold and not fanfares[threshold] then
			fanfares[threshold] = true
			Notify.banner("record", { threshold = threshold }, bestPlayer)
			Notify.celebrate(bestPlayer, "fanfare", { threshold = threshold })
		end
	end
end

-- =============================================================================================
-- Signaux
-- =============================================================================================

local function bump(player: Player, category: string, value: number, mode: "add" | "max")
	local data = profile(player)
	if data == nil or not finite(value) or value <= 0 then
		return
	end
	rollWeek(player, data, currentWeek)
	local w = weeklyOf(data)
	local newValue = if mode == "add" then w[category] + math.floor(value) else math.floor(value)
	LeaderboardService.submit(player, category, newValue)
end

local function onReady(player: Player)
	local data = profile(player)
	if data == nil then
		return
	end
	rollWeek(player, data, currentWeek)
	grantTitles(player)
	sendState(player)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function LeaderboardService.Init()
	currentWeek = weekOf(Clock.unix())
	-- changement de semaine au chargement (avant l'instantané : aucun patch à l'arrivée)
	if type((DataService :: any).onPrepare) == "function" then
		DataService.onPrepare(function(player, data)
			if type(data) == "table" and type(data.weekly) == "table" then
				Guard.try("leaderboard:prepare", rollWeek, player, data, weekOf(Clock.unix()))
			end
		end)
	end
end

-- Connexions et boucles
function LeaderboardService.Start()
	if started then
		return
	end
	started = true
	local function on(signal: any, where: string, fn: (...any) -> ())
		signal:Connect(function(...)
			Guard.try(where, fn, ...)
		end)
	end
	on(Signals.PlayerReady, "leaderboard:ready", onReady)
	on(Signals.Stamped, "leaderboard:stamped", function(player: Player, n: number)
		bump(player, "stamps", n, "add")
	end)
	on(Signals.Fused, "leaderboard:fused", function(player: Player, _uid: string, k: number)
		local data = profile(player)
		if data ~= nil and finite(k) and k > weeklyOf(data).combo then
			bump(player, "combo", k, "max")
		end
	end)
	on(Signals.Caught, "leaderboard:caught", function(player: Player, info: any)
		if type(info) ~= "table" then
			return
		end
		local data = profile(player)
		local score = catchScore(info)
		if data ~= nil and score > weeklyOf(data).catchScore then
			bump(player, "catchScore", score, "max")
		end
		-- « Plus généreux » : le propriétaire de la fuite quand un AUTRE joueur reçoit un bébé
		if
			finite(info.ownerId)
			and info.ownerId > 0
			and type(info.babyUid) == "string"
			and info.babyUid ~= ""
		then
			local owner = Players:GetPlayerByUserId(info.ownerId)
			if owner ~= nil and owner ~= player then
				bump(owner, "generous", 1, "add")
			end
		end
	end)
	on(
		Signals.PetSitRewarded,
		"leaderboard:helpful",
		function(visitor: Player, _owner: Player, helpful: boolean)
			if helpful == true then
				bump(visitor, "helpful", 1, "add")
			end
		end
	)
	on(Signals.Splorched, "leaderboard:splorched", function(player: Player, _r: number, gifts: number)
		if finite(gifts) and gifts > 0 then
			bump(player, "generous", gifts, "add")
		end
	end)
	on(Signals.SettingChanged, "leaderboard:hideName", function(player: Player, key: string)
		if key ~= "hideName" then
			return
		end
		local data = profile(player)
		if data == nil or LeaderboardService.isBanned(player) then
			return
		end
		local w = weeklyOf(data)
		for _, c in CATEGORIES do
			if w[c] > 0 then
				queueWrite(player, c, w[c], true)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		recordAt[player] = nil
		stateDue[player] = nil
	end)
	pcall(function()
		game:BindToClose(function()
			Guard.try("leaderboard:close", flushOnClose)
		end)
	end)
	loadPrevTitles()
end

-- Tick : files d'écriture (60 s), lectures (120 s), statue, changement de semaine
function LeaderboardService.step(now: number)
	local t = if finite(now) then now else Clock.now()
	local week = weekOf(Clock.unix())
	if currentWeek < 0 then
		currentWeek = week
	end
	if week ~= currentWeek then
		-- lundi 00:00 UTC : lot de la semaine finie écrit d'abord, puis nouvelle semaine
		flushWrites()
		currentWeek = week
		tops = {}
		names = {}
		for _, p in Players:GetPlayers() do
			local data = profile(p)
			if data ~= nil then
				rollWeek(p, data, week)
			end
		end
		loadPrevTitles()
		lastRead = -math.huge
	end
	if t - lastWrite >= LeaderboardService.WriteEvery then
		lastWrite = t
		flushWrites()
	end
	if t - lastRead >= LeaderboardService.ReadEvery then
		lastRead = t
		readTops()
	end
	if t - lastTitles >= LeaderboardService.TitlesEvery then
		if lastTitles > -math.huge then
			prevTitlesWeek = -1 -- relecture : un serveur a pu écrire son dernier lot après lundi 00:00
			loadPrevTitles()
		end
		lastTitles = t
	end
	if t - lastStatue >= LeaderboardService.StatueEvery then
		lastStatue = t
		Guard.try("leaderboard:statueStep", stepStatue)
	end
	for player, due in stateDue do
		if t >= due then
			stateDue[player] = nil
			Guard.try("leaderboard:state", sendState, player)
		end
	end
end

-- Nouvelle valeur de la semaine (écrite si record battu)
function LeaderboardService.submit(player: Player, category: string, value: number)
	if not table.find(CATEGORIES, category) or not finite(value) then
		return
	end
	local data = profile(player)
	if data == nil then
		return
	end
	rollWeek(player, data, currentWeek)
	local w = weeklyOf(data)
	local v = math.clamp(math.floor(value), 0, LeaderboardService.MaxScore)
	if v <= w[category] then
		return
	end
	w[category] = v
	DataService.markDirty(player, "weekly")
	local at = recordAt[player]
	if at == nil then
		at = {}
		recordAt[player] = at
	end
	at[category] = secondsSinceMonday(Clock.unix())
	if not LeaderboardService.isBanned(player) then
		queueWrite(player, category, v, false)
	end
	if stateDue[player] == nil then
		stateDue[player] = Clock.now() + LeaderboardService.StateEvery
	end
end

-- Exclu des classements jusqu'à flags.lbBanUntil
function LeaderboardService.isBanned(player: Player): boolean
	local data = profile(player)
	if data == nil or type(data.flags) ~= "table" then
		return false
	end
	return num(data.flags.lbBanUntil, 0) > Clock.unix()
end

return LeaderboardService
