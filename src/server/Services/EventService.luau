--!strict
-- EventService (paquet chase) : événements du serveur (GDD §2.4, §4.11, §4.22, §4.23, §7.5).
--   * Phases (EventClock, ou forcées par AdminCommand) : Rush (siren, start, end), MEGA (warn, land,
--     end), Golden (spawn, end, admin), Lune (start, end), fêtes (party start, end) → Signals.EventPhase
--     une seule fois par index (idempotent même si le tick rattrape ou si l'horloge saute).
--   * MEGA SQUISH : N = joueurs ACTIFS à l'atterrissage (au moins 1), objectif MegaRules.target(N, échecs
--     de suite), MegaPress (phase, à plat ≤ 20 studs du centre à la position validée, pieds ≤ 8, canAct,
--     recharge 0,4 s, PERFECT 3 points), MegaBeat 4 Hz, fin (paliers de bébés, revenu, Fame, jauge).
--   * Jauge — règle unique : seul EventService convertit les faits du jeu en points (Events.Gauge.Points,
--     depuis les signaux) ; objectif 600 × max(2, N actifs) en direct ; pleine → danse de Big Plop (file
--     des spectacles) → WOBBLE PARTY 5 min (jauge figée) → 0 → sieste de Big Plop (RestSeconds) : les
--     points continuent, aucune fête avant la fin de la sieste.
--   * Joueurs actifs : Activity, ou ≤ 60 studs du centre de la place pendant l'alerte du MEGA.
--   * File des grands spectacles (Grand Splorch, danse ; v2.0 : Jelly Ascend, sorte « ascend » de
--     Events.Spectacles, 10 s, coupure 12 s) : ≥ 20 s entre deux départs, jamais pendant un Rush ou un
--     MEGA (± 20 s), place et attente prévue par entrée (durée de SA sorte), coupure dure à 480 s ; héros
--     parti avant l'éclatement de SA sorte (Grand Splorch 3,2 s, Jelly Ascend 4,0 s) : spectacle effacé
--     aussitôt (A26). Un seul prestige par joueur dans la file : règle de SplorchService.
--   * Boosts de serveur : payé > administrateur > Wobble Party, jamais cumulés (le moins prioritaire est
--     en pause) ; Squish Party : un reçu pendant une fête la PROLONGE de 600 s, segments par acheteur
--     (partyUnplayed).
--   * Jelly Moon : Autel (5 min de présence) → Goutte de Lune, une par séance et par compte (moon.lastSession).
--   * LiveOps (MessagingService, administrateurs) et AdminCommand ("clock" en Studio seulement).
--   * EventState : à chaque changement (jauge : au plus toutes les GAUGE_SEND s), à PlayerReady, à
--     RequestWorld et après chaque Features.set appliqué.
--   * v2.0 (lot A4, étape 3 ; GDD v2.0 §4.23, §5.6, §7.5 ; docs/04 §27.5) : jauge du Petit Splorch
--     (PrestigeApplied « petit » : Events.Gauge.Points.petitSplorch ; Splorched = Grand Splorch seulement ;
--     Jelly Ascend : 0) ; place en fête [Fete] (points en mémoire : Grand Splorch, Jelly Ascend, MEGA
--     réussi, Wobble Party ; EventState.fete = { level }) ; météo [Weather] (Meta/Weather, purement
--     visuelle : EventState.weather, renvoyé au début et à la fin de chaque fenêtre) ; moon.sessions d'un
--     profil v2 à chaque Goutte de Lune ; bébés du MEGA et de la Lune de la qualité du Record R
--     (EconomyService.recordR, = R pour un profil v1). Interrupteurs coupés : clés absentes d'EventState,
--     rien écrit, deux lectures d'interrupteur par tick et aucune allocation.
-- Émet EventPhase, SpectacleStarted, MegaJoined. Remotes : MegaPress, AdminCommand ; EventState,
-- MegaBeat. Clé : moon.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MessagingService = game:GetService("MessagingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Features = require(Shared.Config.Features)
local Hash = require(Shared.Logic.Hash)
local EventClock = require(Shared.Logic.EventClock)
local MegaRules = require(Shared.Logic.MegaRules)
local ZoneRules = require(Shared.Logic.ZoneRules)
local PressTiming = require(Shared.Logic.PressTiming)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local Activity = require(Server.Util.Activity)
local MoveCheck = require(Server.Util.MoveCheck)
local Admins = require(Server.Data.Admins)
local Guard = require(Server.Chase.Guard)
local Babies = require(Server.Chase.Babies)
local PadRules = require(Server.Ranch.PadRules)
local Weather = require(Server.Meta.Weather)

local DiagnosticsService = require(script.Parent.DiagnosticsService)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local RanchService = require(script.Parent.RanchService)
local EconomyService = require(script.Parent.EconomyService)
local SquishyService = require(script.Parent.SquishyService)
local CommunityService = require(script.Parent.CommunityService)

local EventService = {}

-- =============================================================================================
-- Constantes
-- =============================================================================================

local RUSH = Events.Rush
local MEGA = Events.Mega
local GAUGE = Events.Gauge
local GAP = Events.SpectacleGap
local SPECTACLES = Events.Spectacles
local FETE = Events.Fete
local PARTY = Events.Party
local MAX_DT = 0.3 -- s : durée maximale d'un pas (accroc du serveur)
local GAUGE_SEND = 1 -- s : EventState pour un simple changement de points, au plus une fois par seconde
local FIT_ITERATIONS = 8 -- décalages successifs au plus pour éviter les grands spectacles fixes
local MOON_WEEK_SLOTS = 8 -- numéro global d'une séance = semaine × 8 + séance (1-5)
local LIVEOPS_TRIES = 3
local LIVEOPS_RETRY = 30 -- s entre deux essais d'abonnement

-- =============================================================================================
-- État
-- =============================================================================================

type Forced = { index: number, startsAt: number, endsAt: number }
type ForcedMega = { index: number, warnAt: number, landsAt: number, endsAt: number, burstEndsAt: number }
type SpectacleKind = "splorch" | "dance" | "ascend"
type QueueEntry = {
	kind: SpectacleKind,
	userId: number,
	slot: number,
	enqueuedAt: number,
	startAt: number,
}
-- refunded : acheteur parti puis revenu sur ce serveur (ProductService lui a rendu ces secondes à son
-- départ) : le segment se joue jusqu'au bout pour tous, mais ne compte plus dans partyUnplayed
type Segment = {
	userId: number,
	name: string,
	showName: boolean,
	seconds: number,
	startedAt: number?,
	refunded: boolean?,
}

local lastStepAt: number? = nil
local fired: { [string]: number } = {} -- "sorte:phase" → dernier index émis
local forcedRush: Forced? = nil
local forcedMega: ForcedMega? = nil
local forcedCount = 0
local rushStarted: { index: number, endsAt: number }? = nil

local mega = {
	index = -math.huge,
	phase = "idle" :: "idle" | "warn" | "press" | "burst",
	warnAt = 0,
	landsAt = 0,
	endsAt = 0,
	burstEndsAt = 0,
	target = 0,
	points = 0,
	presses = 0,
	species = 0,
	moon = false,
	result = "" :: "" | "success" | "fail",
	n = 0,
	perPlayer = {} :: { [Player]: number },
	lastPress = {} :: { [Player]: number },
	nextBeatAt = 0,
	failStreak = 0,
	landed = -math.huge, -- index du dernier MEGA posé (une seule fois par index)
}

local gauge = {
	points = 0,
	restUntil = 0,
	danceQueued = false,
	lastFilledAt = nil :: number?,
	lastRatio = -1,
	lastTarget = 0,
}

local squish: { Segment } = {}
local adminRemaining = 0
local adminStartedAt = 0
local adminGoldens: { number } = {}
local adminGoldenCount = 0
local wobbleRemaining = 0
local boostApplied = { kind = "", untilT = 0 }
local partyCount = 0
-- index de « party:start » de chaque fête (chacune finit avec SON index, même chevauchée)
local partyIndex = { squish = 0, admin = 0, wobble = 0 }

local queue: { QueueEntry } = {}
local current: Types.SpectacleCurrent? = nil
local lastStartAt = -math.huge

local moonPresence: { [Player]: number } = {}
local moonSession: { id: number, endsAt: number }? = nil

-- v2.0 (lot A4) : place en fête (points du serveur, en mémoire, repart de 0 avec le serveur) et météo
-- (prochaine borne de fenêtre, Clock.now()) ; interrupteurs vus au tick précédent (changement en direct :
-- EventState renvoyé)
local fete = { points = 0, level = 0 }
local feteOn = false
local weatherOn = false
local weatherNextAt = -math.huge

local dirty = true
local gaugeDirty = false
local nextGaugeSendAt = 0

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

local function fire(kind: string, phase: string, index: number)
	local key = kind .. ":" .. phase
	if fired[key] == index then
		return
	end
	fired[key] = index
	dirty = true
	Signals.EventPhase:Fire(kind, phase, index)
end

local function displayName(player: Player): string
	local value = Guard.call("event:displayName", CommunityService.displayName, "", player)
	return if type(value) == "string" then value else ""
end

local function isAdmin(player: Player): boolean
	if Admins[player.UserId] == true then
		return true
	end
	return Guard.call("event:isAdmin", DiagnosticsService.isAdmin, false, player) == true
end

-- Rush en vigueur (forcé par un administrateur, sinon EventClock)
local function rushPhase(now: number): Types.RushPhase
	local f = forcedRush
	if f and now < f.endsAt then
		return {
			active = now >= f.startsAt,
			index = f.index,
			sirenAt = f.startsAt,
			startsAt = f.startsAt,
			endsAt = f.endsAt,
		}
	end
	return EventClock.rush(now)
end

local function megaPhase(now: number): Types.MegaPhase
	local f = forcedMega
	if f and now < f.burstEndsAt then
		return {
			active = now >= f.landsAt,
			index = f.index,
			warnAt = f.warnAt,
			landsAt = f.landsAt,
			endsAt = f.endsAt,
			burstEndsAt = f.burstEndsAt,
			moon = false,
		}
	end
	return EventClock.mega(now)
end

local function moonGlobal(phase: Types.MoonPhase): number
	return Clock.week(phase.startsAt) * MOON_WEEK_SLOTS + phase.session
end

local function readyPlayers(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if RanchService.isReady(player) then
			table.insert(out, player)
		end
	end
	return out
end

-- =============================================================================================
-- Joueurs actifs (GDD v1.3 §4.22)
-- =============================================================================================

local function nearPlaza(player: Player): boolean
	local pos = MoveCheck.lastValid(player)
	return pos ~= nil
		and ZoneRules.distXZ(pos, WorldLayout.plaza("center")) <= Events.Activity.MegaAlertRadius
end

local function countActive(now: number, alert: boolean): number
	local n = 0
	for _, player in Players:GetPlayers() do
		if Activity.isActive(player, now) or (alert and nearPlaza(player)) then
			n += 1
		end
	end
	return math.max(Events.Activity.MinPlayers, n)
end

-- =============================================================================================
-- Jauge
-- =============================================================================================

local function gaugeTarget(now: number): number
	return GAUGE.TargetPerPlayer * math.max(GAUGE.MinPlayers, countActive(now, mega.phase == "warn"))
end

local function partyRunning(): boolean
	return wobbleRemaining > 0
end

local function addPoints(points: number)
	if not finite(points) or points <= 0 or Features.get("ServerGauge") ~= true then
		return
	end
	if partyRunning() then
		return -- jauge figée pendant la fête
	end
	local target = gaugeTarget(Clock.now())
	local before = gauge.points
	gauge.points = math.clamp(gauge.points + points, 0, target)
	if gauge.points ~= before then
		gaugeDirty = true
	end
end

-- Niveau de la place en fête : nombre de seuils de Events.Fete.Levels atteints (0 à #Levels)
local function feteLevel(points: number): number
	local level = 0
	for i, threshold in FETE.Levels do
		if points >= threshold then
			level = i
		end
	end
	return level
end

-- Points de la place en fête [Fete] (v2.0, lot A4, D26) : comptés seulement interrupteur ouvert ;
-- EventState renvoyé quand le niveau change. Jamais lus par une récompense, une chance ou un prix
local function addFete(points: number)
	if not finite(points) or points <= 0 or Features.get("Fete") ~= true then
		return
	end
	fete.points += points
	local level = feteLevel(fete.points)
	if level ~= fete.level then
		fete.level = level
		dirty = true
	end
end

local function startWobbleParty()
	local running = wobbleRemaining > 0
	wobbleRemaining = GAUGE.PartyDuration
	if not running then
		partyCount += 1
		partyIndex.wobble = partyCount
		fire("party", "start", partyCount)
		addFete(FETE.Points.party)
	end
	Notify.banner("wobbleParty", { userId = 0, name = "" }, nil)
	dirty = true
end

-- =============================================================================================
-- File des grands spectacles
-- =============================================================================================

-- Sortes de grand spectacle d'un héros : Grand Splorch et Jelly Ascend (v2.0) ; la danse n'en a pas
local function heroKind(kind: string): boolean
	return kind == "splorch" or kind == "ascend"
end

-- Application au profil après le départ : Grand Splorch Balance.Splorch.BurstAt (3,2 s), Jelly Ascend
-- Balance.Ascend.BurstAt (4,0 s) ; danse : aucune (0)
local function burstDelay(kind: string): number
	if kind == "splorch" then
		return Balance.Splorch.BurstAt
	elseif kind == "ascend" then
		return Balance.Ascend.BurstAt
	end
	return 0
end

local function duration(kind: string): number
	local def = (SPECTACLES :: any)[kind]
	return if def then def.duration else SPECTACLES.splorch.duration
end

local function hardCut(kind: string): number
	local def = (SPECTACLES :: any)[kind]
	return if def then def.hardCut else SPECTACLES.splorch.hardCut
end

-- Premier instant ≥ t où un spectacle de `length` s ne chevauche aucun grand spectacle fixe (Rush,
-- MEGA), écart de GAP compris
local function fitStart(t: number, length: number): number
	local start = t
	for _ = 1, FIT_ITERATIONS do
		local moved = false
		local r = rushPhase(start - GAP)
		if start < r.endsAt + GAP and start + length > r.startsAt - GAP then
			start = r.endsAt + GAP
			moved = true
		end
		if Features.get("MegaSquish") == true then
			local m = megaPhase(start - GAP)
			if start < m.burstEndsAt + GAP and start + length > m.landsAt - GAP then
				start = m.burstEndsAt + GAP
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	return start
end

-- Reste du grand spectacle en cours (Rush, MEGA, Grand Splorch, danse)
local function remainingShow(now: number): number
	local left = 0
	local r = rushPhase(now)
	if r.active then
		left = math.max(left, r.endsAt - now)
	end
	if mega.phase == "press" or mega.phase == "burst" then
		left = math.max(left, mega.burstEndsAt - now)
	end
	local c = current
	if c then
		left = math.max(left, c.endsAt - now)
	end
	return math.max(0, left)
end

local function schedule(now: number)
	local prev = lastStartAt
	local c = current
	if c then
		prev = math.max(prev, c.startedAt)
	end
	for _, entry in queue do
		local t = math.max(now, prev + GAP)
		entry.startAt = fitStart(t, duration(entry.kind))
		prev = entry.startAt
	end
end

local function queuePayload(now: number): { Types.SpectacleEntry }
	local out: { Types.SpectacleEntry } = {}
	local rest = remainingShow(now)
	for i, entry in queue do
		table.insert(out, {
			kind = entry.kind,
			userId = entry.userId,
			startAt = entry.startAt,
			slot = entry.slot,
			position = i,
			eta = i * GAP + rest,
		})
	end
	return out
end

local function startSpectacle(entry: QueueEntry, now: number)
	local length = duration(entry.kind)
	current = {
		kind = entry.kind,
		userId = entry.userId,
		startedAt = now,
		burstAt = now + burstDelay(entry.kind),
		endsAt = now + math.min(length, hardCut(entry.kind)),
		flyer = nil,
		level = 0,
	}
	lastStartAt = now
	dirty = true
	Signals.SpectacleStarted:Fire(entry.kind, entry.userId, now)
end

local function stepSpectacles(now: number)
	local c = current
	if c and now >= c.endsAt then
		current = nil
		dirty = true
		if c.kind == "dance" then
			startWobbleParty()
		end
	end
	schedule(now)
	local head = queue[1]
	if head and current == nil then
		local waited = now - head.enqueuedAt
		local cut = waited >= Events.SplorchQueueHardCut
		if now >= head.startAt or cut then
			table.remove(queue, 1)
			if cut and now < head.startAt then
				Guard.try("event:stateTimedOut", DiagnosticsService.stateTimedOut, "splorchQueue", nil)
			end
			startSpectacle(head, now)
			schedule(now)
		end
	end
end

-- =============================================================================================
-- Boosts de serveur (payé > administrateur > Wobble Party, jamais cumulés)
-- =============================================================================================

local function activeBoost(now: number): (string, number, string)
	if #squish > 0 then
		local total = 0
		for _, seg in squish do
			total += seg.seconds
		end
		local head = squish[1]
		return "squish", now + total, if head.showName then head.name else ""
	elseif adminRemaining > 0 then
		return "admin", now + adminRemaining, ""
	elseif wobbleRemaining > 0 then
		return "wobble", now + wobbleRemaining, ""
	end
	return "", 0, ""
end

local function stepBoosts(now: number, dt: number)
	-- temps écoulé consommé par le boost actif, puis par les suivants (accroc ou saut d'horloge)
	local left = math.max(0, dt)
	for _ = 1, 64 do
		if left <= 0 then
			break
		end
		if #squish > 0 then
			local head = squish[1]
			if head.startedAt == nil then
				head.startedAt = now - left
			end
			local used = math.min(left, head.seconds)
			head.seconds -= used
			left -= used
			if head.seconds <= 1e-9 then
				table.remove(squish, 1)
				dirty = true
				if #squish == 0 then
					fire("party", "end", partyIndex.squish)
				else
					squish[1].startedAt = now - left
				end
			end
		elseif adminRemaining > 0 then
			local used = math.min(left, adminRemaining)
			adminRemaining -= used
			left -= used
			if adminRemaining <= 1e-9 then
				adminRemaining = 0
				dirty = true
				fire("party", "end", partyIndex.admin)
			end
		elseif wobbleRemaining > 0 then
			local used = math.min(left, wobbleRemaining)
			wobbleRemaining -= used
			left -= used
			if wobbleRemaining <= 1e-9 then
				-- fin de la WOBBLE PARTY : jauge à 0, sieste de Big Plop
				wobbleRemaining = 0
				gauge.points = 0
				gauge.restUntil = now - left + GAUGE.RestSeconds
				gauge.danceQueued = false
				dirty = true
				fire("party", "end", partyIndex.wobble)
			end
		else
			break
		end
	end
	if #squish > 0 and squish[1].startedAt == nil then
		squish[1].startedAt = now
	end
	local kind, untilT = activeBoost(now)
	if kind ~= boostApplied.kind or math.abs(untilT - boostApplied.untilT) > 0.5 then
		boostApplied = { kind = kind, untilT = untilT }
		EconomyService.setServerBoost(kind, untilT)
		dirty = true
	end
	-- Golden Wobblers de la fête d'administrateur
	while #adminGoldens > 0 and now >= adminGoldens[1] do
		table.remove(adminGoldens, 1)
		adminGoldenCount += 1
		if Features.get("GoldenWobbler") == true then
			Signals.EventPhase:Fire("golden", "admin", adminGoldenCount)
		end
	end
end

local function startAdminParty(now: number)
	-- deuxième commande pendant la fête d'administrateur : durée relancée, même fête (même index)
	if adminRemaining <= 0 then
		partyCount += 1
		partyIndex.admin = partyCount
		fire("party", "start", partyCount)
	end
	adminRemaining = PARTY.AdminBoostDuration
	adminStartedAt = now
	adminGoldens = {}
	local count = PARTY.AdminGoldens
	for i = 0, count - 1 do
		table.insert(adminGoldens, now + i * PARTY.AdminGoldenWindow / count)
	end
	Notify.banner("adminParty", { userId = 0, name = "" }, nil)
	dirty = true
end

-- =============================================================================================
-- MEGA SQUISH
-- =============================================================================================

local function megaLand(phase: Types.MegaPhase, now: number)
	mega.index = phase.index
	mega.phase = "press"
	mega.warnAt = phase.warnAt
	mega.landsAt = phase.landsAt
	mega.endsAt = phase.endsAt
	mega.burstEndsAt = phase.burstEndsAt
	mega.moon = phase.moon
	mega.n = countActive(now, true)
	mega.target = MegaRules.target(mega.n, mega.failStreak)
	mega.species = EventClock.megaSpecies(phase.landsAt)
	mega.points = 0
	mega.presses = 0
	mega.result = ""
	mega.perPlayer = {}
	mega.lastPress = {}
	mega.nextBeatAt = now
	dirty = true
end

local function megaEnd()
	local success = mega.points >= mega.target
	mega.result = if success then "success" else "fail"
	mega.phase = "burst"
	mega.failStreak = if success then 0 else mega.failStreak + 1
	if success then
		addFete(FETE.Points.mega) -- une fois par MEGA réussi (v2.0, lot A4)
	end
	local participants = 0
	for _, points in mega.perPlayer do
		if points >= MEGA.MinPoints then
			participants += 1
		end
	end
	local list = {}
	for player, points in mega.perPlayer do
		table.insert(list, { player = player, points = points })
	end
	table.sort(list, function(a, b): boolean
		return a.player.UserId < b.player.UserId
	end)
	for _, row in list do
		local player, points = row.player, row.points
		if player.Parent ~= nil then
			Guard.try("event:megaReward", function()
				local babies, coins = 0, 0
				if points >= MEGA.MinPoints then
					if success then
						local count = MegaRules.babiesFor(points)
						local rng = Hash.stream(Hash.u32(EventClock.seed("mega", mega.index), player.UserId))
						local _, biggest = SquishyService.biggest(player)
						for _ = 1, count do
							-- qualité du Record R (N1, lot A4 : = R pour un profil v1)
							local baby = Babies.mega(
								rng,
								EconomyService.recordR(player),
								biggest,
								mega.moon,
								Clock.unix()
							)
							SquishyService.give(player, Babies.spec(baby), "mega")
							babies += 1
						end
						coins = EconomyService.addIncomeSeconds(player, Balance.Rewards.MegaSuccess, "Mega")
						EconomyService.addFame(player, Balance.Fame.Mega, "mega")
						addPoints(GAUGE.Points.mega)
					else
						coins = EconomyService.addIncomeSeconds(player, Balance.Rewards.MegaFail, "Mega")
						Notify.feedback(player, "feedback.megaFail", {}, "info")
					end
				end
				Notify.celebrate(
					player,
					"megaResult",
					{ success = success, points = points, babies = babies, coins = coins }
				)
				Signals.MegaJoined:Fire(player, points, success)
				Guard.analytics(
					player,
					"MegaResult",
					if success then 1 else 0,
					{ n = mega.n, participants = participants, points = mega.points, target = mega.target }
				)
			end)
		end
	end
	dirty = true
end

local function stepMega(now: number)
	if mega.phase == "press" then
		if now >= mega.endsAt then
			megaEnd()
			fire("mega", "end", mega.index)
		elseif now >= mega.nextBeatAt then
			mega.nextBeatAt = now + MEGA.Beat - 1e-6
			local beat: Types.MegaBeatPayload =
				{ points = mega.points, target = mega.target, presses = mega.presses, t = now }
			for _, player in readyPlayers() do
				Net.unreliable("MegaBeat"):FireClient(player, beat)
			end
		end
		return
	end
	if mega.phase == "burst" then
		if now >= mega.burstEndsAt then
			mega.phase = "idle"
			dirty = true
		else
			return
		end
	end
	local phase = megaPhase(now)
	if Features.get("MegaSquish") ~= true then
		if mega.phase == "warn" then
			mega.phase = "idle"
			dirty = true
		end
		return
	end
	if now >= phase.landsAt and now < phase.endsAt then
		if mega.landed ~= phase.index then
			mega.landed = phase.index
			megaLand(phase, now)
			fire("mega", "land", phase.index)
		end
	elseif now >= phase.warnAt and now < phase.landsAt then
		if mega.phase ~= "warn" or mega.index ~= phase.index then
			mega.phase = "warn"
			mega.index = phase.index
			mega.landsAt = phase.landsAt
			mega.endsAt = phase.endsAt
			mega.burstEndsAt = phase.burstEndsAt
			mega.moon = phase.moon
			mega.species = EventClock.megaSpecies(phase.landsAt)
			mega.result = ""
			dirty = true
			fire("mega", "warn", phase.index)
		end
	elseif mega.phase == "warn" then
		mega.phase = "idle"
		dirty = true
	end
end

-- =============================================================================================
-- Phases : Rush, Golden, Lune
-- =============================================================================================

local function stepPhases(now: number)
	local r = rushPhase(now)
	if not r.active and now >= r.sirenAt and now < r.startsAt then
		fire("rush", "siren", r.index)
	end
	if r.active and (rushStarted == nil or rushStarted.index ~= r.index) then
		local previous = rushStarted
		if previous then
			fire("rush", "end", previous.index)
		end
		rushStarted = { index = r.index, endsAt = r.endsAt }
		fire("rush", "start", r.index)
	end
	local started = rushStarted
	if started and now >= started.endsAt then
		rushStarted = nil
		fire("rush", "end", started.index)
	end
	local f = forcedRush
	if f and now >= f.endsAt then
		forcedRush = nil
	end
	local fm = forcedMega
	if fm and now >= fm.burstEndsAt then
		forcedMega = nil
	end

	local g = EventClock.golden(now)
	local lastSpawn = fired["golden:spawn"]
	if lastSpawn ~= nil and fired["golden:end"] ~= lastSpawn and (not g.active or g.index ~= lastSpawn) then
		fire("golden", "end", lastSpawn)
	end
	if g.active then
		fire("golden", "spawn", g.index)
	end
end

local function stepMoon(now: number, dt: number, actors: { [Player]: Types.TickActor })
	local phase = EventClock.moon(now)
	local enabled = Features.get("JellyMoon") == true
	local session = moonSession
	if phase.active and enabled then
		local id = moonGlobal(phase)
		if session == nil or session.id ~= id then
			if session then
				-- séance précédente jamais fermée (saut d'horloge) : fermée maintenant
				moonSession = nil
			end
			moonSession = { id = id, endsAt = phase.endsAt }
			table.clear(moonPresence)
			fire("moon", "start", id)
		end
		for player, actor in actors do
			if ZoneRules.atAltar(actor.pos) then
				moonPresence[player] = (moonPresence[player] or 0) + dt
			end
		end
		return
	end
	if session == nil then
		return
	end
	-- fin de la séance : Goutte de Lune pour chaque présence ≥ 5 min, une par séance et par compte
	moonSession = nil
	fire("moon", "end", session.id)
	local list = {}
	for player, seconds in moonPresence do
		if seconds >= Events.Moon.AltarPresence and player.Parent ~= nil then
			table.insert(list, player)
		end
	end
	table.clear(moonPresence)
	table.sort(list, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	for _, player in list do
		Guard.try("event:lunarDrop", function()
			local data = profile(player)
			if data == nil or type(data.moon) ~= "table" or data.moon.lastSession == session.id then
				return
			end
			data.moon.lastSession = session.id
			-- v2.0 (lot A4, D8) : séances de Lune réussies d'un profil v2 (Déco perso « 1re / 4 Jelly Moon »)
			if PadRules.v2Profile(data) then
				local sessions = if finite(data.moon.sessions) then data.moon.sessions else 0
				data.moon.sessions = math.clamp(math.floor(sessions) + 1, 0, 1e9)
			end
			DataService.markDirty(player, "moon")
			local rng = Hash.stream(Hash.u32(session.id, player.UserId, 0x4C))
			-- qualité du Record R (N1, lot A4 : = R pour un profil v1)
			local baby = Babies.lunar(rng, EconomyService.recordR(player), Clock.unix())
			local uid = SquishyService.give(player, Babies.spec(baby), "lunar")
			Notify.celebrate(player, "lunarDrop", { uid = uid or "", species = baby.s, mutation = baby.m })
		end)
	end
end

-- =============================================================================================
-- Jauge : remplissage, danse, sieste
-- =============================================================================================

local function stepGauge(now: number)
	if Features.get("ServerGauge") ~= true then
		return
	end
	local target = gaugeTarget(now)
	if target ~= gauge.lastTarget then
		gauge.lastTarget = target
		gaugeDirty = true
	end
	if gauge.points > target and not partyRunning() then
		gauge.points = target
		gaugeDirty = true
	end
	if
		not partyRunning()
		and not gauge.danceQueued
		and now >= gauge.restUntil
		and gauge.points >= target
		and target > 0
	then
		gauge.danceQueued = true
		local previous = gauge.lastFilledAt
		gauge.lastFilledAt = now
		EventService.enqueueSpectacle("dance", 0)
		local first = Players:GetPlayers()[1]
		if first and previous then
			Guard.analytics(first, "GaugeFilled", (now - previous) / 60)
		end
		dirty = true
	end
	local ratio = if partyRunning() then 1 else math.clamp(gauge.points / math.max(1, target), 0, 1)
	if math.abs(ratio - gauge.lastRatio) >= 0.005 or (ratio == 1) ~= (gauge.lastRatio == 1) then
		gauge.lastRatio = ratio
		Guard.try("event:setGauge", WorldService.setGauge, ratio)
	end
end

-- =============================================================================================
-- EventState
-- =============================================================================================

local function features(): Types.EventFeatures
	return {
		boopRush = tostring(Features.get("BoopRush")),
		megaSquish = Features.get("MegaSquish") == true,
		golden = Features.get("GoldenWobbler") == true,
		jellyMoon = Features.get("JellyMoon") == true,
		gauge = Features.get("ServerGauge") == true,
		clips = Features.get("Clips") == true,
		costume = tostring(Features.get("Costumes") or ""),
		diagnostics = Features.get("Diagnostics") == true,
		-- v2.0 (lot B4, INT-B4-AMBIENCE) : clé présente seulement interrupteur Ambience ouvert (le client ne
		-- lit jamais Config/Features) ; absente sinon : charge de la v1.3 inchangée
		ambience = if Features.get("Ambience") == true then true else nil,
	}
end

local function buildState(now: number): Types.EventStatePayload
	local r = rushPhase(now)
	local nextRush = if r.active then rushPhase(r.endsAt).startsAt else r.startsAt
	local moon = EventClock.moon(now)
	local nextMoon = if moon.active then EventClock.moon(moon.endsAt).startsAt else moon.startsAt
	local g = EventClock.golden(now)
	local kind, untilT, byName = activeBoost(now)
	local c = current
	return {
		rush = {
			active = r.active,
			index = r.index,
			endsAt = r.endsAt,
			nextAt = nextRush,
			moonBoopable = EventClock.rushMoonBoopable(now),
		},
		mega = {
			phase = mega.phase,
			index = if finite(mega.index) then mega.index else 0,
			landsAt = mega.landsAt,
			endsAt = mega.endsAt,
			target = mega.target,
			points = mega.points,
			species = mega.species,
			moon = mega.moon,
			result = mega.result,
		},
		golden = {
			active = g.active and Features.get("GoldenWobbler") == true,
			id = g.index,
			endsAt = g.endsAt,
		},
		moon = {
			active = moon.active and Features.get("JellyMoon") == true,
			session = moonGlobal(moon),
			endsAt = moon.endsAt,
			nextAt = nextMoon,
		},
		gauge = {
			points = gauge.points,
			target = gaugeTarget(now),
			partyUntil = if wobbleRemaining > 0 then now + wobbleRemaining else 0,
			restUntil = if gauge.restUntil > now then gauge.restUntil else 0,
		},
		boost = { kind = kind :: any, untilT = untilT, byName = byName },
		spectacle = { current = if c then table.clone(c) else nil, queue = queuePayload(now) },
		features = features(),
		offset = Clock.getOffset(),
		-- v2.0 (lot A4) : visuels seulement, clés ABSENTES interrupteur coupé (charge de la v1.3 inchangée) ;
		-- météo suspendue pendant une séance de Jelly Moon, absente hors de ses fenêtres
		weather = if Features.get("Weather") == true
			then Weather.at(now, moon.active and Features.get("JellyMoon") == true)
			else nil,
		fete = if Features.get("Fete") == true then { level = fete.level } else nil,
	}
end

-- v2.0 (lot A4) : place en fête et météo vues au tick ; un interrupteur changé en direct renvoie
-- EventState, la météo aussi au début et à la fin de chaque fenêtre. Interrupteurs coupés : deux
-- lectures, rien d'autre (aucune allocation)
local function stepVisuals(now: number)
	local feteNow = Features.get("Fete") == true
	if feteNow ~= feteOn then
		feteOn = feteNow
		dirty = true
	end
	local weatherNow = Features.get("Weather") == true
	if weatherNow ~= weatherOn then
		weatherOn = weatherNow
		weatherNextAt = -math.huge
		dirty = true
	end
	if weatherNow and now >= weatherNextAt then
		-- prochaine borne de fenêtre (pure, sans allocation) ; en erreur : nouvel essai dans 60 s
		weatherNextAt = Guard.call("event:weather", Weather.nextChange, now + 60, now)
		dirty = true
	end
end

-- `only` : envoi à ce seul joueur (arrivée, RequestWorld) ; l'envoi en attente pour les autres reste
-- dû (drapeaux intacts)
local function sendState(now: number, only: Player?)
	local state = buildState(now)
	local remote = Net.event("EventState")
	if only then
		if only.Parent ~= nil then
			remote:FireClient(only, state)
		end
		return
	end
	dirty = false
	gaugeDirty = false
	nextGaugeSendAt = now + GAUGE_SEND
	for _, player in readyPlayers() do
		remote:FireClient(player, state)
	end
end

-- =============================================================================================
-- Intentions
-- =============================================================================================

local function onMegaPress(player: Player, tClient: number): boolean
	local now = Clock.now()
	if mega.phase ~= "press" or now < mega.landsAt or now >= mega.endsAt then
		return false
	end
	local last = mega.lastPress[player]
	if last and now - last < MEGA.Cooldown then
		return false
	end
	local pos = MoveCheck.lastValid(player)
	if pos == nil or not MoveCheck.canAct(player, now) then
		return false
	end
	local pad = WorldLayout.plaza("megaPad")
	local feet = ZoneRules.feetY(pos.Y, MoveCheck.rootOffset(player))
	if
		not ZoneRules.inMegaZone(pos)
		or math.abs(feet - WorldLayout.groundY(pad.X, pad.Z)) > Balance.Catch.MaxDY
	then
		return false
	end
	mega.lastPress[player] = now
	local perfect = MegaRules.isPerfect(mega.landsAt, PressTiming.clampClientTime(tClient, now))
	local points = if perfect then MEGA.PerfectPoints else MEGA.Points
	mega.perPlayer[player] = (mega.perPlayer[player] or 0) + points
	mega.points += points
	mega.presses += 1
	return true
end

local function applyFeature(arg: string): boolean
	local key, raw = string.match(arg, "^([%w_]+)=(.*)$")
	if key == nil or raw == nil then
		return false
	end
	local value: any = raw
	if raw == "true" then
		value = true
	elseif raw == "false" then
		value = false
	end
	return Features.set(key, value)
end

-- Mode photo de chaque administrateur (Diagnostics › Outils envoie « photo » sans argument : bascule)
local photoOn: { [Player]: boolean } = setmetatable({} :: any, { __mode = "k" })

local function onAdminCommand(player: Player, command: string, arg: string): boolean
	if not isAdmin(player) then
		return false -- ignoré sans réponse
	end
	local now = Clock.now()
	if command == "party" then
		startAdminParty(now)
	elseif command == "feature" then
		if applyFeature(arg) then
			sendState(now, nil)
		end
	elseif command == "clock" then
		-- Studio seulement (docs/04 §20 n° 25) : jamais sur un serveur privé qui écrit le vrai magasin
		local studio = Guard.call("event:isStudio", function()
			return RunService:IsStudio()
		end, false)
		local seconds = tonumber(arg)
		if studio == true and seconds and finite(seconds) then
			Clock.setOffset(seconds)
			sendState(Clock.now(), nil)
		end
	elseif command == "forceRush" then
		if not rushPhase(now).active and mega.phase == "idle" then
			forcedCount += 1
			forcedRush = { index = -forcedCount, startsAt = now, endsAt = now + RUSH.Duration }
			dirty = true
		end
	elseif command == "forceMega" then
		if not rushPhase(now).active and mega.phase == "idle" and Features.get("MegaSquish") == true then
			forcedCount += 1
			local landsAt = now + MEGA.Warn
			local endsAt = landsAt + MEGA.PressTime
			forcedMega = {
				index = -forcedCount,
				warnAt = now,
				landsAt = landsAt,
				endsAt = endsAt,
				burstEndsAt = endsAt + MEGA.BurstTime,
			}
			dirty = true
		end
	elseif command == "testError" then
		if arg == "client" then
			Notify.celebrate(player, "testError", {})
		else
			Guard.caught("admin:testError", "testError (server)")
		end
	elseif command == "photo" then
		-- « on » / « off » imposent l'état ; tout autre argument (dont "") bascule
		local on = if arg == "on" then true elseif arg == "off" then false else not photoOn[player]
		photoOn[player] = on
		Notify.celebrate(player, "photo", { on = on })
	end
	return false
end

-- LiveOps (MessagingService) : messages acceptés seulement s'ils portent l'UserId d'un administrateur
local function onLiveOps(message: any)
	local data = if type(message) == "table" then message.Data else nil
	if type(data) ~= "table" or not finite(data.userId) or Admins[data.userId] ~= true then
		return
	end
	local now = Clock.now()
	if data.command == "party" then
		startAdminParty(now)
	elseif data.command == "feature" and type(data.arg) == "string" and #data.arg <= 64 then
		if applyFeature(data.arg) then
			sendState(now, nil)
		end
	end
end

local function subscribeLiveOps()
	for attempt = 1, LIVEOPS_TRIES do
		local ok = pcall(function()
			MessagingService:SubscribeAsync(PARTY.LiveOpsTopic, function(message: any)
				Guard.try("event:liveOps", onLiveOps, message)
			end)
		end)
		if ok then
			return
		end
		if attempt < LIVEOPS_TRIES then
			task.wait(LIVEOPS_RETRY)
		end
	end
end

-- =============================================================================================
-- Signaux (jauge : source unique) et cycle de vie
-- =============================================================================================

local function connectGauge()
	local P = GAUGE.Points
	Signals.Pressed:Connect(function(_player: Player, info: Signals.PressInfo)
		if type(info) ~= "table" then
			return
		end
		if info.visitor ~= nil then
			addPoints(P.petSit)
		else
			addPoints(P.press + (if info.perfect == true then P.perfect else 0))
		end
	end)
	Signals.Hatched:Connect(function()
		addPoints(P.hatch)
	end)
	Signals.Fused:Connect(function()
		addPoints(P.fuseStep)
	end)
	Signals.Caught:Connect(function(_player: Player, info: Signals.CatchInfo)
		addPoints(if type(info) == "table" and info.kind == "escape" then P.rushCatch else P.catch)
	end)
	Signals.NearCatch:Connect(function(_player: Player, kind: string)
		if kind == "golden" then
			addPoints(P.catch)
		elseif kind == "rush" then
			addPoints(P.rushNear)
		end
	end)
	Signals.Fed:Connect(function()
		addPoints(P.feed)
	end)
	-- Splorched = Grand Splorch seulement (v1.3 et v2.0 ; jamais pour un Petit Splorch, lot A4 D3)
	Signals.Splorched:Connect(function()
		addPoints(P.splorch)
		addFete(FETE.Points.splorch)
	end)
	-- v2.0 (lot A4, D3, D26 ; GDD m9) : Petit Splorch 5 points de jauge, 0 à la fête ; Jelly Ascend 0 point
	-- de jauge (sa Pluie d'étoiles est son cadeau), + 1 à la fête ; Grand Splorch v2.0 : par Splorched
	Signals.PrestigeApplied:Connect(function(_player: Player, kind: string)
		if kind == "petit" then
			addPoints(P.petitSplorch)
		elseif kind == "ascend" then
			addFete(FETE.Points.ascend)
		end
	end)
end

-- Retour d'un acheteur sur ce serveur : ses segments encore en file datent de sa session précédente,
-- rendus à son départ (ProductService, sauvegarde de départ) : ils ne lui sont plus dus
local function onPlayerAdded(player: Player)
	for _, seg in squish do
		if seg.userId == player.UserId then
			seg.refunded = true
		end
	end
end

local function onPlayerRemoving(player: Player)
	EventService.cancelSpectacle(player.UserId)
	moonPresence[player] = nil
	mega.lastPress[player] = nil
	mega.perPlayer[player] = nil
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function EventService.Init()
	Guard.connect("MegaPress", onMegaPress)
	Guard.connect("AdminCommand", onAdminCommand)
end

-- Connexions et boucles
function EventService.Start()
	connectGauge()
	Signals.PlayerReady:Connect(function(player: Player)
		Guard.try("event:ready", sendState, Clock.now(), player)
	end)
	Signals.WorldRequested:Connect(function(player: Player)
		Guard.try("event:world", sendState, Clock.now(), player)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		Guard.try("event:join", onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Guard.try("event:leave", onPlayerRemoving, player)
	end)
	task.spawn(subscribeLiveOps)
end

-- Tick : phases, MEGA (agrégation, battement), jauge, fêtes, file des spectacles, Autel
function EventService.step(now: number, actors: { [Player]: Types.TickActor })
	if not finite(now) then
		return
	end
	local previous = lastStepAt
	local dt = if previous then math.clamp(now - previous, 0, MAX_DT) else 0
	lastStepAt = now
	Guard.try("event:phases", stepPhases, now)
	Guard.try("event:mega", stepMega, now)
	Guard.try("event:boosts", stepBoosts, now, if previous then math.max(0, now - previous) else 0)
	Guard.try("event:gauge", stepGauge, now)
	Guard.try("event:spectacles", stepSpectacles, now)
	Guard.try("event:moon", stepMoon, now, dt, actors or {})
	stepVisuals(now)
	if dirty or (gaugeDirty and now >= nextGaugeSendAt) then
		Guard.try("event:state", sendState, now, nil)
	end
end

-- État diffusé (construit à l'instant : mêmes champs que le dernier EventState, points du MEGA et de
-- la jauge à jour)
function EventService.state(): Types.EventStatePayload
	return buildState(Clock.now())
end

-- Fonction ajoutée : MEGA en cours (alerte, pression ou éclatement) — ChaseService (fuites en pause)
function EventService.megaActive(): boolean
	return mega.phase ~= "idle"
end

-- Fonction ajoutée : départ prévu du prestige de ce joueur en file (Grand Splorch ou Jelly Ascend ; nil =
-- pas en file) — SplorchService.queued et son filet
function EventService.queuedStartAt(userId: number): number?
	for _, entry in queue do
		if heroKind(entry.kind) and entry.userId == userId then
			return entry.startAt
		end
	end
	return nil
end

-- Fonction ajoutée : héros du grand spectacle en cours (Grand Splorch ou Jelly Ascend ; 0 = aucun ou
-- danse) — ChaseService
function EventService.spectacleUserId(): number
	local c = current
	return if c and heroKind(c.kind) then c.userId else 0
end

-- Rush en cours
function EventService.rushActive(): boolean
	return rushPhase(Clock.now()).active
end

-- Fonction ajoutée : Rush en vigueur (forcé ou EventClock) : RushService, ChaseService
function EventService.rushPhase(): Types.RushPhase
	return rushPhase(Clock.now())
end

-- Séance de Jelly Moon en cours
function EventService.moonActive(): boolean
	return Features.get("JellyMoon") == true and EventClock.moon(Clock.now()).active
end

-- Mode BOOP RUSH "events" : Lune ou fête d'administrateur en cours
function EventService.eventBoopActive(): boolean
	return EventService.moonActive() or adminRemaining > 0
end

-- Points de jauge (bornés, ignorés pendant la fête) : commandes d'administrateur et specs seulement
function EventService.addGauge(points: number)
	addPoints(points)
end

-- Fonction ajoutée (v2.0, lot A4) : points de la place en fête du serveur (lecture : specs, Diagnostics) ;
-- le niveau diffusé est EventState.fete.level
function EventService.fetePoints(): number
	return fete.points
end

-- Place dans la file ; rend le Clock.now() de départ prévu (même entrée rendue si déjà en file). Sortes :
-- "splorch", "dance" et (v2.0) "ascend" ; un seul prestige par joueur : règle de SplorchService
function EventService.enqueueSpectacle(kind: SpectacleKind, userId: number): number
	local now = Clock.now()
	if kind ~= "splorch" and kind ~= "dance" and kind ~= "ascend" then
		return now
	end
	for _, entry in queue do
		if entry.kind == kind and entry.userId == userId then
			return entry.startAt
		end
	end
	local slot = 0
	if heroKind(kind) then
		local player = Players:GetPlayerByUserId(userId)
		slot = if player then RanchService.slotOf(player) else 0
	end
	local entry: QueueEntry = { kind = kind, userId = userId, slot = slot, enqueuedAt = now, startAt = now }
	table.insert(queue, entry)
	schedule(now)
	dirty = true
	return entry.startAt
end

-- Retire de la file (départ du joueur avant son tour) ses entrées de Grand Splorch et de Jelly Ascend ;
-- héros parti pendant son spectacle avant l'éclatement de SA sorte (burstAt : 3,2 s ou 4,0 s) : spectacle
-- effacé aussitôt et EventState renvoyé (remarque A26) ; après l'éclatement, le spectacle continue
function EventService.cancelSpectacle(userId: number)
	local now = Clock.now()
	for i = #queue, 1, -1 do
		if queue[i].userId == userId and heroKind(queue[i].kind) then
			table.remove(queue, i)
			dirty = true
		end
	end
	local c = current
	if c and heroKind(c.kind) and c.userId == userId and now < c.burstAt then
		current = nil
		Guard.try("event:state", sendState, now, nil)
	end
	if dirty then
		schedule(now)
	end
end

-- Fonction ajoutée : détails du Grand Splorch en cours (SplorchService, au départ du spectacle)
function EventService.describeSpectacle(
	userId: number,
	flyer: { s: number, m: number, st: number, z: number }?,
	level: number
)
	local c = current
	if c and c.userId == userId then
		c.flyer = flyer
		c.level = if finite(level) then level else 0
		dirty = true
	end
end

-- Une Squish Party peut commencer aussitôt
function EventService.canStartParty(): boolean
	return #squish == 0
end

-- Démarre la fête payée (10 min, ×2 serveur) ; pendant une fête en cours, la PROLONGE de 600 s (reçu
-- croisé : jamais refusé, aucune file en mémoire) ; segment de 600 s noté pour cet acheteur
function EventService.startSquishParty(buyer: Player, showName: boolean): boolean
	local first = #squish == 0
	local name = displayName(buyer)
	table.insert(squish, {
		userId = buyer.UserId,
		name = name,
		showName = showName == true and name ~= "",
		seconds = PARTY.SquishPartyDuration,
		startedAt = nil,
	})
	if first then
		partyCount += 1
		partyIndex.squish = partyCount
		fire("party", "start", partyCount)
	end
	if showName == true and name ~= "" then
		Notify.banner("squishPartyBy", { userId = buyer.UserId, name = name }, buyer)
	else
		Notify.banner("squishParty", { userId = buyer.UserId, name = "" }, buyer)
	end
	dirty = true
	return true
end

-- Secondes de Squish Party achetées par ce joueur et pas encore jouées (≤ 600 par achat) : lecture pure
function EventService.partyUnplayed(userId: number): number
	local total = 0
	for _, seg in squish do
		if seg.userId == userId and seg.refunded ~= true then
			total += math.clamp(seg.seconds, 0, PARTY.SquishPartyDuration)
		end
	end
	return total
end

-- Joueurs sur le serveur (N)
function EventService.playerCount(): number
	return #Players:GetPlayers()
end

-- Joueur ACTIF (Activity.isActive, ou à MegaAlertRadius studs du centre de la place pendant l'alerte
-- du MEGA, position validée)
function EventService.isActive(player: Player, now: number): boolean
	if Activity.isActive(player, now) then
		return true
	end
	return mega.phase == "warn" and nearPlaza(player)
end

-- N actifs (au moins Events.Activity.MinPlayers) : objectif du MEGA à l'atterrissage, objectif de la jauge
function EventService.activeCount(now: number): number
	return countActive(now, mega.phase == "warn")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « mega »,
-- « spectacle », « splorchQueue », « squishParty », « wobbleParty », « gaugeRest »
function EventService.openStates(): { Types.OpenState }
	local now = Clock.now()
	local out: { Types.OpenState } = {}
	if mega.phase == "press" or mega.phase == "burst" then
		table.insert(out, { name = "mega", startedAt = mega.landsAt, player = nil })
	end
	local c = current
	if c then
		table.insert(out, { name = "spectacle", startedAt = c.startedAt, player = nil })
	end
	for _, entry in queue do
		if heroKind(entry.kind) then
			table.insert(out, {
				name = "splorchQueue",
				startedAt = entry.enqueuedAt,
				player = Players:GetPlayerByUserId(entry.userId),
			})
		end
	end
	local head = squish[1]
	if head and head.startedAt then
		table.insert(out, { name = "squishParty", startedAt = head.startedAt, player = nil })
	end
	if wobbleRemaining > 0 then
		table.insert(
			out,
			{ name = "wobbleParty", startedAt = now - (GAUGE.PartyDuration - wobbleRemaining), player = nil }
		)
	end
	if gauge.restUntil > now then
		table.insert(
			out,
			{ name = "gaugeRest", startedAt = gauge.restUntil - GAUGE.RestSeconds, player = nil }
		)
	end
	local _ = adminStartedAt
	return out
end

return EventService
