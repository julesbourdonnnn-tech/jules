--!strict
-- SplorchService (paquet chase) : Grand Splorch (GDD §4.15, §6.7, §9.4).
--   * Entrée dans la file (GrandSplorch(film, flyer)) : plus gros ≥ objectif, dans son ranch (position
--     validée), rien de porté, AUCUN de ses squishies en fuite (Feedback waitEscape { species }), flyer
--     possédé et en enclos, pas déjà en file. Vérifié UNE seule fois, puis garanti :
--     SquishyService.setWaiting(flyer) (pendant l'attente, aucun squishy du joueur à la clôture),
--     EventService.enqueueSpectacle("splorch"), Feedback splorchQueued { time }.
--   * Départ (Signals.SpectacleStarted) : spectacle de 7,5 s, Celebrate "splorch" à tous (version courte
--     pour un spectateur qui a vu un spectacle complet il y a moins de FullShowGap s ; le héros a
--     toujours le spectacle complet) ; le squishy porté par le héros est posé.
--   * Éclatement (BurstAt = 3,2 s, minuteur du serveur), D'UN SEUL BLOC SANS YIELD :
--     EconomyService.applySplorch, SquishyService.resetSizes, setWaiting(nil), puis DataService.saveNow
--     (task.spawn) ; cadeaux aux autres (60 s de revenu 10 fois par jour puis 10 s, + 1 bébé sous le
--     plafond, réglage « Recevoir les cadeaux ») ; Signals.Splorched(héros, R, bébés) APRÈS les cadeaux ;
--     CommunityService.openClapWindow(héros, t + 8, spectateurs du spectacle complet) ; bannière ;
--     analytique SplorchReached (readyAtLogin), SplorchCoinsLost (multiples du Tapis 12), TileLevelAtSplorch.
--   * Départ du héros avant son tour ou avant l'éclatement : place rendue, rien remis à zéro, aucune pluie
--     de cadeaux (EventService efface le spectacle en cours, remarque A26).
-- Émet Splorched ; jamais EventService.addGauge (la jauge vient de Splorched). Remote : GrandSplorch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Hash = require(Shared.Logic.Hash)
local Formulas = require(Shared.Logic.Formulas)
local WorldLayout = require(Shared.Logic.WorldLayout)
local StateTimeouts = require(Shared.Logic.StateTimeouts)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local MoveCheck = require(Server.Util.MoveCheck)
local Guard = require(Server.Chase.Guard)
local Babies = require(Server.Chase.Babies)

local DataService = require(script.Parent.DataService)
local RanchService = require(script.Parent.RanchService)
local EconomyService = require(script.Parent.EconomyService)
local SquishyService = require(script.Parent.SquishyService)
local CommunityService = require(script.Parent.CommunityService)
local EventService = require(script.Parent.EventService)

local SplorchService = {}

-- =============================================================================================
-- État
-- =============================================================================================

local SPLORCH = Balance.Splorch
local CLAP_WINDOW = StateTimeouts.seconds("clapWindow")
local HARD_CUT = Events.Spectacles.splorch.hardCut
local SNACK_LOOP_LEVEL = Balance.Tiles.snack.Levels - 1 -- Tapis 12 (niveau 11 → 12)
-- Borne absolue d'une attente tenue par EventService : coupure dure de la tête de file, puis un grand
-- spectacle par place (16 Grands Splorch et une danse, écart compris) et le dernier spectacle
local MAX_SPECTACLES = 17
local QUEUE_LIMIT = Events.SplorchQueueHardCut
	+ MAX_SPECTACLES * (Events.SpectacleGap + StateTimeouts.seconds("spectacle"))
	+ StateTimeouts.seconds("spectacle")

type Queued = { flyer: string, at: number, film: boolean }
type Show = {
	hero: Player,
	startedAt: number,
	burstAt: number,
	endsAt: number,
	flyer: { s: number, m: number, st: number, z: number },
	flyerUid: string,
	level: number,
	short: { [Player]: boolean }, -- version courte par spectateur (décidée au départ)
	full: { Player }, -- spectateurs du spectacle complet (APPLAUDIR)
	burst: boolean,
}

local queued: { [Player]: Queued } = {}
local shows: { [Player]: Show } = {}
local lastFull: { [Player]: number } = {} -- dernier spectacle complet vu (mémoire de session)
local readyAtLogin: { [Player]: boolean } = {}
local lastSplorchAt: { [Player]: number } = {}

-- =============================================================================================
-- Aides
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function profile(player: Player): { [string]: any }?
	if not DataService.isLoaded(player) then
		return nil
	end
	return DataService.get(player)
end

local function displayName(player: Player): string
	local value = Guard.call("splorch:displayName", CommunityService.displayName, "", player)
	return if type(value) == "string" then value else ""
end

local function receivesGifts(player: Player): boolean
	local data = profile(player)
	local stored = not (data and type(data.settings) == "table" and data.settings.receiveGifts == false)
	local value = Guard.call("splorch:receiveGifts", CommunityService.setting, stored, player, "receiveGifts")
	return value ~= false
end

local function ready(player: Player): boolean
	local data = profile(player)
	if data == nil then
		return false
	end
	local _, biggest = SquishyService.biggest(player)
	return finite(biggest) and biggest >= Formulas.splorchTarget(EconomyService.R(player))
end

-- =============================================================================================
-- Entrée dans la file (vérifiée une seule fois)
-- =============================================================================================

local function onGrandSplorch(player: Player, film: boolean, flyer: string): boolean
	local data = profile(player)
	if data == nil then
		return false
	end
	if queued[player] ~= nil or shows[player] ~= nil or SquishyService.waiting(player) ~= nil then
		Notify.feedback(player, "feedback.waitingSplorch", {}, "info")
		return false
	end
	if not ready(player) then
		Notify.feedback(player, "feedback.splorchNotReady", {}, "info")
		return false
	end
	local slot = RanchService.slotOf(player)
	local pos = MoveCheck.lastValid(player)
	if slot == 0 or pos == nil or not WorldLayout.inRanch(slot, pos) then
		Notify.feedback(player, "feedback.onlyOwnRanch", {}, "info")
		return false
	end
	if SquishyService.carried(player) ~= nil then
		Notify.feedback(player, "feedback.carrying", {}, "info")
		return false
	end
	local escaping = SquishyService.anyEscaping(player)
	if escaping ~= nil then
		local rec = SquishyService.get(player, escaping)
		Notify.feedback(player, "feedback.waitEscape", { species = if rec then rec.s else 0 }, "info")
		return false
	end
	local rec = SquishyService.get(player, flyer)
	if rec == nil or rec.at ~= "pen" then
		Notify.feedback(player, "feedback.notOwned", {}, "info")
		return false
	end
	-- garanti à partir d'ici
	local now = Clock.now()
	SquishyService.setWaiting(player, flyer)
	queued[player] = { flyer = flyer, at = now, film = film == true }
	local startAt = EventService.enqueueSpectacle("splorch", player.UserId)
	Notify.feedback(
		player,
		"feedback.splorchQueued",
		{ time = math.max(0, math.ceil(startAt - now)) },
		"success"
	)
	return true
end

-- =============================================================================================
-- Spectacle
-- =============================================================================================

local function onSpectacleStarted(kind: string, userId: number, t: number)
	if kind ~= "splorch" then
		return
	end
	local hero = Players:GetPlayerByUserId(userId)
	if hero == nil then
		return
	end
	local entry = queued[hero]
	queued[hero] = nil
	local flyerUid = (entry and entry.flyer) or SquishyService.waiting(hero)
	local rec = if flyerUid then SquishyService.get(hero, flyerUid) else nil
	if flyerUid == nil or rec == nil then
		-- squishy introuvable (filet) : la place est rendue, rien n'est remis à zéro
		EventService.cancelSpectacle(userId)
		Guard.try("splorch:waiting", SquishyService.setWaiting, hero, nil)
		return
	end
	if SquishyService.carried(hero) ~= nil then
		SquishyService.endCarry(hero, "splorch")
	end
	local level = EconomyService.R(hero) + 1
	local flyer = { s = rec.s, m = rec.m, st = rec.st, z = SquishyService.sizeOf(hero, flyerUid) }
	local show: Show = {
		hero = hero,
		startedAt = t,
		burstAt = t + SPLORCH.BurstAt,
		endsAt = t + SPLORCH.Duration,
		flyer = flyer,
		flyerUid = flyerUid,
		level = level,
		short = {},
		full = {},
		burst = false,
	}
	shows[hero] = show
	EventService.describeSpectacle(userId, flyer, level)
	for _, player in Players:GetPlayers() do
		if RanchService.isReady(player) then
			local short = false
			if player ~= hero then
				local last = lastFull[player]
				short = last ~= nil and t - last < SPLORCH.FullShowGap
				if not short then
					lastFull[player] = t
					table.insert(show.full, player)
				end
			end
			show.short[player] = short
			Notify.celebrate(player, "splorch", {
				userId = userId,
				level = level,
				flyer = flyer,
				startedAt = t,
				burstAt = show.burstAt,
				endsAt = show.endsAt,
				short = short,
			})
		end
	end
end

-- Cadeaux à un autre joueur : pièces (10 par jour, ensuite 10 s), + 1 bébé sous le plafond
local function gift(show: Show, player: Player): number
	if player.Parent == nil or profile(player) == nil or not receivesGifts(player) then
		return 0
	end
	local seconds = if EconomyService.consumeCap(player, "splorchCoins", 1) > 0
		then SPLORCH.GiftSeconds
		else Balance.Rewards.GiftSecondsAfterCap
	local coins = EconomyService.addIncomeSeconds(player, seconds, "SplorchGift")
	local babyUid, species, given = "", 0, 0
	if EconomyService.consumeCap(player, "splorchGifts", 1) > 0 then
		local _, biggest = SquishyService.biggest(player)
		local rng = Hash.stream(Hash.u32(show.hero.UserId, player.UserId, math.floor(show.startedAt * 10)))
		local baby = Babies.gift(rng, show.flyer.s, show.flyer.m, biggest)
		local uid = SquishyService.give(player, Babies.spec(baby), "gift")
		babyUid = uid or ""
		species = baby.s
		given = 1
	end
	local short = show.short[player]
	Notify.celebrate(player, "giftRain", {
		heroId = show.hero.UserId,
		heroName = displayName(show.hero),
		coins = coins,
		uid = babyUid,
		species = species,
		short = short == true,
	})
	return given
end

-- Éclatement : application au profil d'un seul bloc, sans yield
local function burst(show: Show, now: number)
	show.burst = true
	local hero = show.hero
	local data = profile(hero)
	if data == nil or hero.Parent == nil then
		return
	end
	local R0 = EconomyService.R(hero)
	local tiles = type(data.tiles) == "table" and data.tiles or {}
	local snackBefore = if finite(tiles.snack) then tiles.snack else 0
	local decorBefore = if finite(tiles.decor) then tiles.decor else 0
	local lost = EconomyService.applySplorch(hero)
	SquishyService.resetSizes(hero)
	SquishyService.setWaiting(hero, nil)
	task.spawn(function()
		Guard.try("splorch:save", DataService.saveNow, hero)
	end)
	-- cadeaux pour chaque autre joueur (payés par le jeu, jamais pris au héros)
	local given = 0
	local others = {}
	for _, player in Players:GetPlayers() do
		if player ~= hero then
			table.insert(others, player)
		end
	end
	table.sort(others, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	for _, player in others do
		local ok, n = Guard.try("splorch:gift", gift, show, player)
		if ok and finite(n) then
			given += n
		end
	end
	local newR = EconomyService.R(hero)
	Signals.Splorched:Fire(hero, newR, given)
	Guard.call(
		"splorch:clap",
		CommunityService.openClapWindow,
		nil,
		hero,
		show.startedAt + CLAP_WINDOW,
		show.full
	)
	Notify.banner("splorch", { userId = hero.UserId, name = displayName(hero), level = show.level }, hero)
	-- analytique
	local previous = lastSplorchAt[hero]
	lastSplorchAt[hero] = now
	Guard.analytics(hero, "SplorchReached", newR, {
		minutes = if previous then (now - previous) / 60 else 0,
		readyAtLogin = if readyAtLogin[hero] then 1 else 0,
	})
	readyAtLogin[hero] = false
	local price = Formulas.tileCost("snack", SNACK_LOOP_LEVEL, R0)
	Guard.analytics(hero, "SplorchCoinsLost", if price > 0 then (lost or 0) / price else 0)
	Guard.analytics(hero, "TileLevelAtSplorch", snackBefore, { decor = decorBefore })
end

-- =============================================================================================
-- Cycle de vie
-- =============================================================================================

local function onPlayerRemoving(player: Player)
	-- départ avant son tour ou avant l'éclatement : place rendue, rien n'est remis à zéro
	if queued[player] ~= nil or (shows[player] ~= nil and not shows[player].burst) then
		EventService.cancelSpectacle(player.UserId)
		Guard.try("splorch:waiting", SquishyService.setWaiting, player, nil)
	end
	queued[player] = nil
	shows[player] = nil
	lastFull[player] = nil
	readyAtLogin[player] = nil
	lastSplorchAt[player] = nil
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function SplorchService.Init()
	Guard.connect("GrandSplorch", onGrandSplorch)
end

-- Connexions et boucles
function SplorchService.Start()
	Signals.SpectacleStarted:Connect(function(kind: string, userId: number, t: number)
		Guard.try("splorch:start", onSpectacleStarted, kind, userId, t)
	end)
	DataService.Loaded:Connect(function(player: Player)
		readyAtLogin[player] = Guard.call("splorch:ready", ready, false, player) == true
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Guard.try("splorch:leave", onPlayerRemoving, player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			readyAtLogin[player] = Guard.call("splorch:ready", ready, false, player) == true
		end
	end
end

-- Tick : éclatement dû, fin du spectacle (coupure dure à 10 s), file sans spectacle (filet)
function SplorchService.step(now: number)
	if not finite(now) then
		return
	end
	local list = {}
	for hero in shows do
		table.insert(list, hero)
	end
	table.sort(list, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	for _, hero in list do
		local show = shows[hero]
		if show then
			if not show.burst and now >= show.burstAt then
				local ok = Guard.try("splorch:burst", burst, show, now)
				show.burst = true
				-- éclatement en erreur (attrapée) : l'attente du flyer est levée quand même, jamais un
				-- squishy bloqué « en attente » pour la session
				if not ok and SquishyService.waiting(hero) ~= nil then
					Guard.try("splorch:waiting", SquishyService.setWaiting, hero, nil)
				end
			end
			if now >= math.min(show.endsAt, show.startedAt + HARD_CUT) then
				shows[hero] = nil
			end
		end
	end
	-- filet : place perdue par EventService (coupure, panne : plus dans sa file, spectacle jamais lancé)
	-- ou attente au-delà de la borne absolue → attente rendue, place annulée, rien remis à zéro. Une
	-- place encore tenue par EventService n'est jamais annulée ici (sa coupure dure la fait partir)
	for player, entry in queued do
		local held = Guard.call("splorch:queuedStartAt", EventService.queuedStartAt, nil, player.UserId)
			~= nil
		if (not held and now > entry.at) or now - entry.at > QUEUE_LIMIT then
			queued[player] = nil
			Guard.try("splorch:waiting", SquishyService.setWaiting, player, nil)
			EventService.cancelSpectacle(player.UserId)
		end
	end
end

-- Clock.now() de départ prévu si le joueur est dans la file
function SplorchService.queued(player: Player): number?
	local entry = queued[player]
	if entry == nil then
		return nil
	end
	local startAt = EventService.queuedStartAt(player.UserId)
	return if startAt ~= nil then startAt else entry.at
end

-- Ce squishy attend son Grand Splorch
function SplorchService.isWaiting(player: Player, uid: string): boolean
	return SquishyService.waiting(player) == uid
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « splorchQueue »
-- (en file), « splorchBurst » (éclatement dû) ; startedAt en Clock.now()
function SplorchService.openStates(): { { name: string, startedAt: number, player: Player? } }
	local out = {}
	for player, entry in queued do
		table.insert(out, { name = "splorchQueue", startedAt = entry.at, player = player })
	end
	for hero, show in shows do
		if not show.burst then
			table.insert(out, { name = "splorchBurst", startedAt = show.startedAt, player = hero })
		end
	end
	return out
end

return SplorchService
