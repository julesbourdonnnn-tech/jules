--!strict
-- ChaseService (paquet chase) : tick de 10 Hz du serveur (le seul Heartbeat serveur, docs/04 §6) et
-- poursuites (GDD §4.11, §4.12, §4.21, §12.5, §12.8).
--   * Tick : acteurs (MoveCheck à chaque tick : budget d'action, retours, attribut « Unstable » ; sol =
--     WorldLayout.supportY(position), jamais un Blockcast ; Activity.noteMove avec la position validée),
--     puis les services dans l'ordre du §6, chaque étape sous pcall (erreur comptée par Diagnostics).
--   * Créatures (identifiants 1-65535, recyclés après la fin) : fuite personnelle (toutes les 60 s, 50
--     avec la famille Froggy, en pause pendant un Rush, un MEGA, son propre Grand Splorch, l'accueil
--     2:45 → 5:00 et quand tout est plein), Golden Wobbler, Wild Wobblers (partagés et personnels),
--     fuites du Rush (Signals.Booped), démonstration de Big Plop. Fin de chaque créature par son heure.
--   * Bond (Leap(dirX, dirZ, tClient)) : recharge 4 s (horloge du serveur), direction bornée, pas en
--     portage, canAct au départ ; tClient ramené dans [maintenant − ClientPast ; maintenant] ;
--     MoveCheck.grant (12 studs sur 0,35 s, rétroactif, un par 4 s) ; atterrissage LeapRules.landing
--     depuis la position reçue à l'ARRIVÉE du message (MoveCheck.positionAt(arrivée) : celle du client
--     à tClient, comme pour Catch ; note d'intégration 1) ; capture tentée à tClient + 0,35 s.
--   * Capture (Catch(id, tClient)) : mise en file, vérifiée au tick suivant dans l'ordre d'arrivée, à SON
--     instant : SeededPath.pos(tClient) contre la position validée du joueur interpolée dans l'anneau de
--     MoveCheck.positionAt à l'ARRIVÉE du message (ses positions et son message font le même trajet :
--     c'est sa position chez lui à tClient ; Chase.spec à 0, 100 et 250 ms), à plat ≤ rayon + 1,5,
--     pieds ≤ 8, canAct ; règles de RushRules.checkCatch pour les fuites du Rush ; la première arrivée
--     gagne. Récompenses (bébés, Héros, retours, « de près ») ; Caught / NearCatch (la jauge
--     vient de ces signaux, jamais d'un appel direct).
--   * ChaseEvent groupé à 4 Hz (tous, ou le seul concerné pour une créature personnelle).
--   * Anti-triche : « rewind » → PivotTo, attribut Unstable 3 s, flags.strikes, exclusion des
--     classements jusqu'à la fin de la semaine suivante après StrikesForBan retours en 10 min.
-- Émet MoveViolation, Caught, NearCatch, EscapeEnded. Remotes : Leap, Catch ; ChaseEvent.
-- Clés : flags, golden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Features = require(Shared.Config.Features)
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Hash = require(Shared.Logic.Hash)
local WorldLayout = require(Shared.Logic.WorldLayout)
local SeededPath = require(Shared.Logic.SeededPath)
local LeapRules = require(Shared.Logic.LeapRules)
local RushRules = require(Shared.Logic.RushRules)
local ZoneRules = require(Shared.Logic.ZoneRules)
local EventClock = require(Shared.Logic.EventClock)
local QuestRules = require(Shared.Logic.QuestRules)
local StateTimeouts = require(Shared.Logic.StateTimeouts)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local Activity = require(Server.Util.Activity)
local MoveCheck = require(Server.Util.MoveCheck)
local Tuning = require(Server.Movement.Tuning)
local Guard = require(Server.Chase.Guard)
local Babies = require(Server.Chase.Babies)

local DiagnosticsService = require(script.Parent.DiagnosticsService)
local DataService = require(script.Parent.DataService)
local RanchService = require(script.Parent.RanchService)
local EconomyService = require(script.Parent.EconomyService)
local SquishyService = require(script.Parent.SquishyService)
local QuestService = require(script.Parent.QuestService)
local CommunityService = require(script.Parent.CommunityService)
local EventService = require(script.Parent.EventService)
local RushService = require(script.Parent.RushService)
local SplorchService = require(script.Parent.SplorchService)
local HelperService = require(script.Parent.HelperService) -- v2.0 (lot A3) : Plopettes, stépées ici
local LeaderboardService = require(script.Parent.LeaderboardService)

local ChaseService = {}

-- =============================================================================================
-- Constantes (Config, Tuning)
-- =============================================================================================

local TICK = Tuning.TickStep
local MAX_DT = Tuning.TickStep * Tuning.MaxCatchUp
local CATCH = Balance.Catch
local LEAP = Balance.Leap
local RUSH = Events.Rush
local WILD = Events.Wild
local BROADCAST_EVERY = 0.25 -- ChaseEvent groupé à 4 Hz (GDD §12.5)
local MAX_ID = 65535
local MAX_QUEUED_CATCHES = 6 -- captures en file par joueur et par tick (débit Catch : 6 / s)
local UNSTABLE_SECONDS = StateTimeouts.seconds("unstable")
local WEEK_SECONDS = 7 * 24 * 3600 -- calendrier (exclusion jusqu'à la fin de la semaine suivante)
local FIRST_RUNAWAY_DELAY = Balance.Runaway.Interval -- runaway.nextAt repart à 60 s (docs/04 §20 n° 10)
local OUTCOME_CODE = { hero = 1, baby = 2, returned = 3, cozy = 4, left = 5 }

-- =============================================================================================
-- État
-- =============================================================================================

type Creature = {
	spawn: Types.ChaseSpawn,
	path: SeededPath.PathFn,
	endsAt: number,
	personal: Player?, -- seul joueur qui la voit et peut l'attraper
	owner: Player?, -- propriétaire du squishy en fuite (Rush)
	booper: Player?,
	rushIndex: number, -- Wild Wobbler partagé : Rush d'origine (2 par joueur et par Rush)
	lastPos: Vector3, -- dernière position calculée (récompense « de près » d'un Golden raté)
}

-- landing : point d'atterrissage provisoire (position validée à la réception) ; recalculé à l'échéance
-- depuis la position reçue à l'ARRIVÉE du message (celle du client à tClient : même trajet réseau)
type Leap = {
	at: number,
	landing: Vector3,
	dir: Vector3,
	arrival: number,
	rootOffset: number,
	startedAt: number,
}
type QueuedCatch = { player: Player, id: number, t: number, arrival: number }
type Outbox = { spawns: { Types.ChaseSpawn }, finishes: { Types.ChaseFinish } }
type WildPlan = {
	index: number,
	endsAt: number,
	total: number,
	released: number,
	nextWaveAt: number,
	personalAt: number,
	personalDone: boolean,
	sharedCaught: { [Player]: number },
}
type OnboardingScript = {
	active: boolean,
	runawayAt: number?,
	demoAt: number?,
	runawayPaused: boolean,
	vatScripted: boolean,
}

local actors: { [Player]: Types.TickActor } = {}
local creatures: { [number]: Creature } = {}
local nextId = 1
local lastTickAt: number? = nil
local accumulator = 0
local nextBroadcastAt = -math.huge

local seenCharacter: { [Player]: Instance } = {}
local lastSpeed: { [Player]: number } = {}
local unstableUntil: { [Player]: number } = {}
local leapAt: { [Player]: number } = {}
local leaps: { [Player]: Leap } = {}
local catchQueue: { QueuedCatch } = {}
local runawayNextAt: { [Player]: number } = {}
local scriptedRunawayDone: { [Player]: boolean } = {}
local demoDone: { [Player]: boolean } = {}
local goldenWarned: { [Player]: number } = {} -- id du Golden déjà signalé « laisse les autres gagner »
local wildPlan: WildPlan? = nil

local outAll: Outbox = { spawns = {}, finishes = {} }
local outPersonal: { [Player]: Outbox } = {}

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

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local function onboardingScript(player: Player): OnboardingScript
	local fallback: OnboardingScript =
		{ active = false, runawayAt = nil, demoAt = nil, runawayPaused = false, vatScripted = false }
	local value = Guard.call("chase:questScript", QuestService.script, fallback, player)
	return if type(value) == "table" then value :: OnboardingScript else fallback
end

local function playSeconds(player: Player): number
	local data = profile(player)
	local stored = if data
			and type(data.stats) == "table"
			and finite(data.stats.playSeconds)
		then data.stats.playSeconds
		else 0
	local value = Guard.call("chase:playSeconds", QuestService.playSeconds, stored, player)
	return if finite(value) then value else stored
end

local function displayName(player: Player): string
	local value = Guard.call("chase:displayName", CommunityService.displayName, "", player)
	return if type(value) == "string" then value else ""
end

local function biggestOf(player: Player): number
	local _, size = SquishyService.biggest(player)
	return if finite(size) then size else 0
end

local function moonActive(): boolean
	return Guard.call("chase:moon", EventService.moonActive, false) == true
end

-- Position de la créature à l'instant t, posée sur le sol analytique (écart vertical des captures)
local function creaturePos(c: Creature, t: number): Vector3
	local pos = c.path(t)
	return Vector3.new(pos.X, WorldLayout.groundY(pos.X, pos.Z), pos.Z)
end

local function visibleTo(c: Creature, player: Player): boolean
	return c.personal == nil or c.personal == player
end

local function allocateId(): number?
	for _ = 1, MAX_ID do
		local id = nextId
		nextId = if nextId >= MAX_ID then 1 else nextId + 1
		if creatures[id] == nil then
			return id
		end
	end
	return nil
end

local function outboxOf(player: Player): Outbox
	local box = outPersonal[player]
	if box == nil then
		box = { spawns = {}, finishes = {} }
		outPersonal[player] = box
	end
	return box
end

local function interval(player: Player): number
	local data = profile(player)
	if data and type(data.dex) == "table" and QuestRules.familyEarned(data.dex, "froggy") then
		local bonus = Species.Families.froggy.bonus
		if bonus and finite(bonus.value) then
			return bonus.value
		end
	end
	return Balance.Runaway.Interval
end

local function rngFor(c: Creature, player: Player, salt: number): Hash.Stream
	return Hash.stream(Hash.u32(c.spawn.seed, player.UserId, salt))
end

-- =============================================================================================
-- Créatures : apparition, fin
-- =============================================================================================

local function addCreature(
	fields: { [string]: any },
	personal: Player?,
	owner: Player?,
	booper: Player?
): Creature?
	local id = allocateId()
	if id == nil then
		return nil
	end
	local spawn: Types.ChaseSpawn = {
		id = id,
		kind = fields.kind,
		species = fields.species or Species.PLOP,
		mutation = fields.mutation or 0,
		size = fields.size or 1,
		stars = fields.stars or 0,
		ownerSlot = fields.ownerSlot or 0,
		booperSlot = fields.booperSlot or 0,
		uid = fields.uid or "",
		path = fields.path or "escape",
		seed = fields.seed or 0,
		t0 = fields.t0,
		startNode = fields.startNode or 0,
		awayAngle = fields.awayAngle or 0,
		center = fields.center or { x = 0, z = 0 },
		speed = fields.speed or RUSH.SpeedStart,
		duration = fields.duration,
		personal = personal ~= nil,
	}
	local path = SeededPath.fromSpawn(spawn)
	local c: Creature = {
		spawn = spawn,
		path = path,
		endsAt = spawn.t0 + spawn.duration,
		personal = personal,
		owner = owner,
		booper = booper,
		rushIndex = fields.rushIndex or 0,
		lastPos = Vector3.zero,
	}
	c.lastPos = creaturePos(c, spawn.t0)
	creatures[id] = c
	if personal then
		table.insert(outboxOf(personal).spawns, table.clone(spawn))
	else
		table.insert(outAll.spawns, table.clone(spawn))
	end
	return c
end

local function finish(c: Creature, reason: "caught" | "returned" | "expired", bySlot: number, now: number)
	local id = c.spawn.id
	if creatures[id] ~= c then
		return
	end
	creatures[id] = nil
	local entry: Types.ChaseFinish = { id = id, reason = reason, bySlot = bySlot, t = now }
	if c.personal then
		if c.personal.Parent ~= nil then
			table.insert(outboxOf(c.personal).finishes, entry)
		end
	else
		table.insert(outAll.finishes, entry)
	end
end

local function spawnRunaway(player: Player, now: number, scripted: boolean)
	local data = profile(player)
	local slot = RanchService.slotOf(player)
	if data == nil or slot == 0 then
		return
	end
	local seed = Hash.u32(player.UserId, math.floor(now * 10), 0x52)
	local rng = Hash.stream(seed)
	-- qualité du Record R (N1, lot A4 : EconomyService.recordR = R pour un profil v1)
	local baby =
		Babies.runaway(rng, EconomyService.recordR(player), biggestOf(player), moonActive(), Clock.unix())
	if scripted then
		-- première fuite de l'accueil (GDD §3) : Mochi Mew
		baby.s = Species.MOCHI_MEW
		baby.m = 0
		local def = Species.ById[Species.MOCHI_MEW]
		baby.rarity = if def then def.rarity else baby.rarity
	end
	local center = WorldLayout.anchor(slot, "fountain")
	addCreature({
		kind = "runaway",
		species = baby.s,
		mutation = baby.m,
		size = baby.z,
		stars = 0,
		ownerSlot = slot,
		path = "hop",
		seed = seed,
		t0 = now,
		center = { x = center.X, z = center.Z },
		speed = 0,
		duration = Balance.Runaway.Duration,
	}, player, player, nil)
end

local function spawnGolden(seed: number, t0: number)
	local start = WorldLayout.nearestNode(WorldLayout.plaza("goldenFountain"))
	local node = WorldLayout.graph().nodes[start]
	addCreature({
		kind = "golden",
		species = Species.PLOP,
		mutation = Mutations.GOLDEN,
		size = 1,
		path = "escape",
		seed = seed,
		t0 = t0,
		startNode = start,
		center = { x = if node then node.X else 0, z = if node then node.Z else 0 },
		speed = Balance.Golden.SpeedStart,
		duration = Events.Golden.Duration,
	}, nil, nil, nil)
end

local function spawnWild(
	kind: "wild" | "wildPersonal",
	seed: number,
	node: number,
	now: number,
	personal: Player?,
	rushIndex: number
)
	local graphNode = WorldLayout.graph().nodes[node]
	addCreature({
		kind = kind,
		species = Species.PLOP,
		mutation = 0,
		size = 1,
		path = "escape",
		seed = seed,
		t0 = now,
		startNode = node,
		awayAngle = Hash.range(0, 2 * math.pi, seed, 0x31),
		center = { x = if graphNode then graphNode.X else 0, z = if graphNode then graphNode.Z else 0 },
		speed = RUSH.SpeedStart,
		duration = WILD.Duration,
		rushIndex = rushIndex,
	}, personal, nil, nil)
end

local function spawnDemo(player: Player, now: number)
	local slot = RanchService.slotOf(player)
	if slot == 0 then
		return
	end
	local start = WorldLayout.gateOutside(slot)
	addCreature({
		kind = "demo",
		species = Species.PLOP,
		mutation = 0,
		size = 1,
		ownerSlot = slot,
		path = "escape",
		seed = Hash.u32(player.UserId, 0xD3), -- un seul trajet par compte (jamais rejouée)
		t0 = now,
		center = { x = start.X, z = start.Z },
		speed = Events.Demo.Speed,
		duration = Events.Demo.Duration,
	}, player, player, nil)
end

-- Fuite du Rush (Signals.Booped) : départ du nœud du boulevard devant le portail, premier bond à
-- l'opposé du boopeur ; visible par tous, attrapable par les joueurs Rush
local function startEscape(booper: Player, owner: Player, uid: string, angle: number)
	local rec = SquishyService.get(owner, uid)
	local slot = RanchService.slotOf(owner)
	if rec == nil or slot == 0 or owner.Parent == nil then
		return
	end
	if ChaseService.isEscaping(owner, uid) then
		return
	end
	local now = Clock.now()
	local node = WorldLayout.fountainNode(slot)
	local graphNode = WorldLayout.graph().nodes[node]
	local c = addCreature({
		kind = "escape",
		species = rec.s,
		mutation = rec.m,
		size = SquishyService.sizeOf(owner, uid),
		stars = rec.st,
		ownerSlot = slot,
		booperSlot = RanchService.slotOf(booper),
		uid = uid,
		path = "escape",
		seed = Hash.u32(owner.UserId, Hash.string(uid), math.floor(now * 10)),
		t0 = now,
		startNode = node,
		awayAngle = if finite(angle) then angle else 0,
		center = { x = if graphNode then graphNode.X else 0, z = if graphNode then graphNode.Z else 0 },
		speed = RUSH.SpeedStart,
		duration = RUSH.EscapeDuration,
	}, nil, owner, booper)
	if c then
		SquishyService.setEscaping(owner, uid, true)
	end
end

-- =============================================================================================
-- Fins des fuites du Rush
-- =============================================================================================

local function firstBoop(owner: Player): boolean
	local data = profile(owner)
	return data ~= nil and type(data.mode) == "table" and data.mode.postBoopCardShown ~= true
end

local function endEscape(c: Creature, outcome: string, catcher: Player?, now: number)
	local owner = c.owner
	local uid = c.spawn.uid
	finish(
		c,
		if outcome == "baby" or outcome == "hero" then "caught" else "returned",
		if catcher then RanchService.slotOf(catcher) else 0,
		now
	)
	if owner then
		Guard.try("chase:escaping", SquishyService.setEscaping, owner, uid, false)
		Signals.EscapeEnded:Fire(owner, uid, outcome, catcher)
		Guard.analytics(owner, "EscapeOutcome", OUTCOME_CODE[outcome] or 0)
	end
end

-- Personne ne l'a attrapée en 25 s : rentre avec + 30 min de croissance (une fois par jour)
local function escapeReturned(c: Creature, now: number)
	local owner = c.owner
	if owner and owner.Parent ~= nil then
		local uid = c.spawn.uid
		local grew = SquishyService.growFor(owner, uid, Balance.RushSize.ReturnGrowthSeconds)
		if grew then
			Notify.celebrate(owner, "returnedBigger", { uid = uid, species = c.spawn.species })
		end
		if firstBoop(owner) then
			Notify.celebrate(owner, "ownerReturn", {
				uid = uid,
				species = c.spawn.species,
				coins = 0,
				catcherId = 0,
				catcherName = "",
				firstBoop = true,
			})
		end
	end
	endEscape(c, "returned", nil, now)
end

-- =============================================================================================
-- Récompenses de capture
-- =============================================================================================

local function catchInfo(
	kind: Types.CreatureKind,
	baby: Babies.Baby?,
	c: Creature,
	hero: boolean,
	byLeap: boolean,
	babyUid: string
): Signals.CatchInfo
	local species = if baby then baby.s else c.spawn.species
	local def = Species.ById[species]
	return {
		kind = kind,
		species = species,
		rarity = if baby then baby.rarity elseif def then def.rarity else 1,
		mutation = if baby then baby.m else c.spawn.mutation,
		ownerId = if c.owner and c.spawn.kind == "escape" then c.owner.UserId else 0,
		hero = hero,
		byLeap = byLeap,
		babyUid = babyUid,
	}
end

local function giveBaby(player: Player, baby: Babies.Baby, source: string): string
	local uid = SquishyService.give(player, Babies.spec(baby), source)
	return uid or ""
end

-- Joueurs « de près » (≤ NearRadius à plat de `point`, position validée) sauf `except`
local function nearPlayers(point: Vector3, except: { [Player]: boolean }, rushOnly: boolean): { Player }
	local out = {}
	for player, actor in actors do
		if
			not except[player]
			and player.Parent ~= nil
			and ZoneRules.distXZ(actor.pos, point) <= CATCH.NearRadius
		then
			if not rushOnly or RushService.isRush(player) then
				table.insert(out, player)
			end
		end
	end
	return out
end

local function rewardNear(players: { Player }, seconds: number, sku: string, kind: string?)
	for _, player in players do
		local coins = EconomyService.addIncomeSeconds(player, seconds, sku)
		Notify.feedback(player, "feedback.nearCatch", { coins = coins }, "reward")
		if kind then
			Signals.NearCatch:Fire(player, kind)
		end
	end
end

local function onCaught(catcher: Player, c: Creature, now: number, byLeap: boolean, at: Vector3)
	local kind = c.spawn.kind
	local slot = RanchService.slotOf(catcher)
	if kind == "escape" then
		-- GDD §16.3 : une capture du Rush, segmentée par appareil (champ « device » posé par
		-- DiagnosticsService via Analytics.setSegment)
		Guard.analytics(catcher, "RushCatchByInput", 1)
		local owner = c.owner
		local uid = c.spawn.uid
		if owner == catcher then
			-- capture « Héros » : + 1 h de croissance (une fois par jour), 120 s de revenu, +2 Fame
			SquishyService.growFor(owner, uid, Balance.RushSize.HeroGrowthSeconds)
			local coins = EconomyService.addIncomeSeconds(owner, Balance.Rewards.Hero, "RushHero")
			EconomyService.addFame(owner, Balance.Fame.Hero, "rush")
			Notify.celebrate(owner, "catch", {
				kind = kind,
				species = c.spawn.species,
				mutation = c.spawn.mutation,
				uid = uid,
				coins = coins,
				hero = true,
				byLeap = byLeap,
			})
			local near = nearPlayers(at, { [catcher] = true }, true)
			endEscape(c, "hero", catcher, now)
			Signals.Caught:Fire(catcher, catchInfo(kind, nil, c, true, byLeap, ""))
			rewardNear(near, Balance.Rewards.RushNear, "RushNear", "rush")
			return
		end
		-- un autre joueur Rush : bébé pour lui (plafond du jour), le squishy rentre chez son propriétaire
		local babyUid, baby, coins = "", nil :: Babies.Baby?, 0
		if EconomyService.consumeCap(catcher, "rushBabies", 1) > 0 then
			local b = Babies.rush(
				rngFor(c, catcher, 0x11),
				{ s = c.spawn.species, m = c.spawn.mutation },
				c.spawn.size,
				biggestOf(catcher),
				EconomyService.recordR(catcher), -- Record R (N1, lot A4)
				moonActive()
			)
			baby = b
			babyUid = giveBaby(catcher, b, "rush")
		else
			coins = EconomyService.addIncomeSeconds(catcher, Balance.Babies.FallbackSeconds, "RushBabyCap")
		end
		if owner and owner.Parent ~= nil then
			local ownerCoins =
				EconomyService.addIncomeSeconds(owner, Balance.Rewards.OwnerReturn, "RushReturn")
			EconomyService.addFame(owner, Balance.Fame.Booped, "rush")
			Notify.celebrate(owner, "ownerReturn", {
				uid = uid,
				species = c.spawn.species,
				coins = ownerCoins,
				catcherId = catcher.UserId,
				catcherName = displayName(catcher),
				firstBoop = firstBoop(owner),
			})
		end
		Notify.celebrate(catcher, "catch", {
			kind = kind,
			species = if baby then baby.s else c.spawn.species,
			mutation = if baby then baby.m else c.spawn.mutation,
			uid = babyUid,
			coins = coins,
			hero = false,
			byLeap = byLeap,
		})
		local except = { [catcher] = true }
		if owner then
			except[owner] = true
		end
		local near = nearPlayers(at, except, true)
		endEscape(c, "baby", catcher, now)
		Signals.Caught:Fire(catcher, catchInfo(kind, baby, c, false, byLeap, babyUid))
		rewardNear(near, Balance.Rewards.RushNear, "RushNear", "rush")
		return
	end

	finish(c, "caught", slot, now)
	local baby: Babies.Baby
	local source: string = kind
	if kind == "runaway" then
		local def = Species.ById[c.spawn.species]
		baby = {
			s = c.spawn.species,
			m = c.spawn.mutation,
			st = 0,
			z = c.spawn.size,
			rarity = if def then def.rarity else 1,
		}
		runawayNextAt[catcher] = now + interval(catcher)
	elseif kind == "golden" then
		baby = Babies.golden(
			rngFor(c, catcher, 0x47),
			EconomyService.recordR(catcher), -- Record R (N1, lot A4)
			biggestOf(catcher),
			moonActive(),
			Clock.unix()
		)
		local data = profile(catcher)
		if data and type(data.golden) == "table" then
			data.golden.lastWinAt = Clock.unix()
			DataService.markDirty(catcher, "golden")
		end
		local near = nearPlayers(at, { [catcher] = true }, false)
		rewardNear(near, Balance.Rewards.GoldenNear, "Golden", "golden")
	elseif kind == "demo" then
		local plop = SquishyService.bestFriend(catcher, 1)
		local plopSize = if plop then SquishyService.sizeOf(catcher, plop) else 1
		baby = Babies.demo(plopSize, biggestOf(catcher))
		demoDone[catcher] = true
	else
		-- Wild Wobbler (partagé ou personnel) : +1 Fame du Rush
		baby = Babies.wild(rngFor(c, catcher, 0x57), biggestOf(catcher), moonActive(), Clock.unix())
		source = "wild"
		if kind == "wild" then
			local plan = wildPlan
			if plan and plan.index == c.rushIndex then
				plan.sharedCaught[catcher] = (plan.sharedCaught[catcher] or 0) + 1
			end
		end
		EconomyService.addFame(catcher, Balance.Fame.Wild, "rush")
	end
	local babyUid = giveBaby(catcher, baby, source)
	Notify.celebrate(catcher, "catch", {
		kind = kind,
		species = baby.s,
		mutation = baby.m,
		uid = babyUid,
		coins = 0,
		hero = false,
		byLeap = byLeap,
	})
	if kind == "golden" then
		Notify.banner(
			"goldenCaught",
			{ userId = catcher.UserId, name = displayName(catcher), species = baby.s, mutation = baby.m },
			catcher
		)
	end
	Signals.Caught:Fire(catcher, catchInfo(kind, baby, c, false, byLeap, babyUid))
end

-- =============================================================================================
-- Captures (file, vérification à l'instant tClient)
-- =============================================================================================

local function goldenCooldown(player: Player): boolean
	local data = profile(player)
	local last = if data
			and type(data.golden) == "table"
			and finite(data.golden.lastWinAt)
		then data.golden.lastWinAt
		else 0
	return last > 0 and Clock.unix() - last < Balance.Golden.WinCooldown
end

-- Le joueur peut-il attraper cette créature (règles de sorte, hors distance) ?
local function eligible(player: Player, c: Creature): boolean
	if not visibleTo(c, player) then
		return false
	end
	local kind = c.spawn.kind
	if kind == "golden" then
		return not goldenCooldown(player)
	elseif kind == "wild" then
		local plan = wildPlan
		local caught = if plan and plan.index == c.rushIndex then plan.sharedCaught[player] or 0 else 0
		return caught < WILD.SharedPerPlayerPerRush
	elseif kind == "runaway" or kind == "demo" or kind == "wildPersonal" then
		return c.personal == player
	end
	return true
end

-- Tente la capture à l'instant t (position du joueur `from` : positionAt(tClient) ou point
-- d'atterrissage du bond) ; rend vrai si accordée
local function attempt(
	player: Player,
	c: Creature,
	t: number,
	now: number,
	byLeap: boolean,
	from: Vector3?
): boolean
	local actor = actors[player]
	if actor == nil or player.Parent == nil or creatures[c.spawn.id] ~= c then
		return false
	end
	if not eligible(player, c) then
		return false
	end
	local pos = if from then from else MoveCheck.positionAt(player, t)
	if pos == nil then
		return false
	end
	local cpos = creaturePos(c, t)
	local isOwner = c.spawn.kind == "escape" and c.owner == player
	local distance = ZoneRules.distXZ(pos, cpos)
	local dy = ZoneRules.feetY(pos.Y, actor.rootOffset) - cpos.Y
	-- capture à l'atterrissage : canAct exigé au DÉPART du bond (la dette du bond ne l'annule pas)
	local canAct = byLeap or (actor.canAct and MoveCheck.canAct(player, now))
	if c.spawn.kind == "escape" then
		local ok = RushRules.checkCatch({
			catcherRush = RushService.isRush(player),
			isBooper = c.booper == player,
			age = now - c.spawn.t0,
			isOwner = isOwner,
			distance = distance,
			dy = dy,
			canAct = canAct,
		})
		if not ok then
			return false
		end
	else
		local radius = CATCH.Radius + CATCH.Tolerance
		if distance > radius or math.abs(dy) > CATCH.MaxDY or not canAct then
			return false
		end
	end
	onCaught(player, c, now, byLeap, cpos)
	return true
end

local function stepCatches(now: number)
	if #catchQueue == 0 then
		return
	end
	local queue = catchQueue
	catchQueue = {}
	for _, entry in queue do
		local c = creatures[entry.id]
		if c then
			-- position du joueur : celle que le serveur avait reçue à l'ARRIVÉE du message (interpolée dans
			-- l'anneau de MoveCheck.positionAt) ; ses positions et son message ont fait le même trajet,
			-- elle vaut donc sa position chez lui à l'instant tClient de l'appui (latence compensée)
			local from = MoveCheck.positionAt(entry.player, entry.arrival)
				or MoveCheck.positionAt(entry.player, entry.t)
			Guard.try("chase:catch", attempt, entry.player, c, entry.t, now, false, from)
		end
	end
end

-- Bonds dus : capture tentée à l'atterrissage (tClient + 0,35 s) sur la créature la plus proche
local function stepLeaps(now: number)
	for player, leap in leaps do
		if now >= leap.at then
			leaps[player] = nil
			if player.Parent ~= nil then
				local from = MoveCheck.positionAt(player, leap.arrival)
				if from then
					leap.landing = LeapRules.landing(from, leap.dir)
				end
				local best: Creature? = nil
				local bestDist = math.huge
				for _, c in creatures do
					if eligible(player, c) then
						local cpos = creaturePos(c, leap.at)
						local isOwner = c.spawn.kind == "escape" and c.owner == player
						if
							LeapRules.catchesOnLanding(
								leap.landing,
								cpos,
								isOwner,
								CATCH.Tolerance,
								leap.rootOffset
							)
						then
							local d = ZoneRules.distXZ(leap.landing, cpos)
							if d < bestDist then
								best, bestDist = c, d
							end
						end
					end
				end
				if best then
					Guard.try("chase:leapCatch", attempt, player, best, leap.at, now, true, leap.landing)
				end
			end
		end
	end
end

-- =============================================================================================
-- Créatures : horaires (fuites personnelles, Wild Wobblers, démonstration) et fins
-- =============================================================================================

local function storageFull(player: Player): boolean
	local c = SquishyService.counts(player)
	return c.pen + c.pool >= c.penCapacity and c.dodo >= Balance.Pens.Dodo and c.mail >= Balance.Pens.Mail
end

local function hasPersonal(player: Player, kind: Types.CreatureKind): boolean
	for _, c in creatures do
		if c.personal == player and c.spawn.kind == kind then
			return true
		end
	end
	return false
end

local function runawayPaused(player: Player): boolean
	if Guard.call("chase:rushActive", EventService.rushActive, false) == true then
		return true
	end
	if Guard.call("chase:mega", EventService.megaActive, false) == true then
		return true
	end
	if Guard.call("chase:spectacle", EventService.spectacleUserId, 0) == player.UserId then
		return true
	end
	if Guard.call("chase:queued", SplorchService.queued, nil, player) ~= nil then
		return true
	end
	return storageFull(player)
end

local function stepPlayerCreatures(player: Player, now: number)
	if not RanchService.isReady(player) or profile(player) == nil or RanchService.slotOf(player) == 0 then
		return
	end
	local onboarding = onboardingScript(player)
	-- démonstration de Big Plop (accueil, ~3:00 de jeu ; jamais rejouée)
	local data = profile(player)
	local demoAlready = demoDone[player] == true
		or (data ~= nil and type(data.onboarding) == "table" and data.onboarding.demoDone == true)
	if
		not demoAlready
		and finite(onboarding.demoAt)
		and playSeconds(player) >= (onboarding.demoAt :: number)
	then
		demoDone[player] = true
		spawnDemo(player, now)
	end
	-- fuites personnelles
	if hasPersonal(player, "runaway") then
		return
	end
	if onboarding.active then
		-- accueil : la première fuite suit le script (2:00), puis pause jusqu'à 5:00 de jeu
		if
			not onboarding.runawayPaused
			and not scriptedRunawayDone[player]
			and finite(onboarding.runawayAt)
			and playSeconds(player) >= (onboarding.runawayAt :: number)
		then
			scriptedRunawayDone[player] = true
			spawnRunaway(player, now, true)
		end
		return
	end
	local due = runawayNextAt[player]
	if due == nil then
		runawayNextAt[player] = now + FIRST_RUNAWAY_DELAY
		return
	end
	if now >= due and not runawayPaused(player) then
		spawnRunaway(player, now, false)
	end
end

local function stepWild(now: number)
	local plan = wildPlan
	if plan == nil then
		return
	end
	local nodes = WorldLayout.wildSpawnNodes()
	if #nodes == 0 then
		return
	end
	-- vagues de Wild Wobblers partagés : un tiers au début, puis toutes les 15 s, pendant le Rush
	local perWave = math.max(1, math.ceil(plan.total / 3))
	while plan.released < plan.total and now >= plan.nextWaveAt and now < plan.endsAt do
		for _ = 1, math.min(perWave, plan.total - plan.released) do
			plan.released += 1
			local k = plan.released
			local seed = EventClock.seed("wild", plan.index * 64 + k)
			spawnWild("wild", seed, nodes[(k - 1) % #nodes + 1], now, nil, plan.index)
		end
		plan.nextWaveAt += WILD.SharedWave
	end
	-- Wild Wobbler personnel (Rush ou Cozy), 15 s après le début, pas avant l'étape 9 de l'accueil
	if not plan.personalDone and now >= plan.personalAt then
		plan.personalDone = true
		if now < plan.endsAt then
			for player, actor in actors do
				local quiet = Guard.call("chase:newcomer", QuestService.isNewcomerQuiet, false, player)
					== true
				if not quiet then
					local best, bestD = nodes[1], math.huge
					for _, node in nodes do
						local p = WorldLayout.graph().nodes[node]
						local d = if p then ZoneRules.distXZ(p, actor.pos) else math.huge
						if d < bestD then
							best, bestD = node, d
						end
					end
					local seed = EventClock.seed("wildPersonal", plan.index * 4096 + (player.UserId % 4096))
					spawnWild("wildPersonal", seed, best, now, player, plan.index)
				end
			end
		end
	end
	if plan.released >= plan.total and plan.personalDone and now >= plan.endsAt then
		wildPlan = nil
	end
end

local function expire(c: Creature, now: number)
	local kind = c.spawn.kind
	if kind == "escape" then
		escapeReturned(c, now)
		return
	end
	if kind == "golden" then
		-- personne ne l'a attrapé : 30 s de revenu aux joueurs de près de sa dernière position
		local near = nearPlayers(creaturePos(c, c.endsAt), {}, false)
		finish(c, "expired", 0, now)
		rewardNear(near, Balance.Rewards.GoldenMiss, "Golden", nil)
		return
	end
	finish(c, "expired", 0, now)
	if kind == "runaway" and c.personal then
		runawayNextAt[c.personal] = now + interval(c.personal)
	end
end

local function stepCreatures(now: number)
	for _, player in Players:GetPlayers() do
		Guard.try("chase:playerCreatures", stepPlayerCreatures, player, now)
	end
	Guard.try("chase:wild", stepWild, now)
	local due = {}
	for _, c in creatures do
		if now >= c.endsAt then
			table.insert(due, c)
		end
	end
	table.sort(due, function(a: Creature, b: Creature): boolean
		return a.spawn.id < b.spawn.id
	end)
	for _, c in due do
		Guard.try("chase:expire", expire, c, now)
	end
	-- attribut « connexion instable » : 3 s après un retour forcé
	for player, untilT in unstableUntil do
		if now >= untilT or player.Parent == nil then
			unstableUntil[player] = nil
			if player.Parent ~= nil then
				player:SetAttribute("Unstable", false)
			end
		end
	end
end

-- =============================================================================================
-- Diffusion groupée (4 Hz)
-- =============================================================================================

local function merged(box: Outbox?): Types.ChaseEventPayload?
	local spawns = table.clone(outAll.spawns)
	local finishes = table.clone(outAll.finishes)
	if box then
		table.move(box.spawns, 1, #box.spawns, #spawns + 1, spawns)
		table.move(box.finishes, 1, #box.finishes, #finishes + 1, finishes)
	end
	if #spawns == 0 and #finishes == 0 then
		return nil
	end
	return { spawns = spawns, finishes = finishes }
end

local function flushBroadcast(now: number)
	if now < nextBroadcastAt then
		return
	end
	nextBroadcastAt = now + BROADCAST_EVERY - 1e-6
	local hasAll = #outAll.spawns > 0 or #outAll.finishes > 0
	if not hasAll and next(outPersonal) == nil then
		return
	end
	local remote = Net.event("ChaseEvent")
	for _, player in Players:GetPlayers() do
		if RanchService.isReady(player) then
			local payload = merged(outPersonal[player])
			if payload then
				remote:FireClient(player, payload)
			end
		end
	end
	outAll = { spawns = {}, finishes = {} }
	table.clear(outPersonal)
end

-- Créatures actives visibles par ce joueur (arrivée, RequestWorld), en un seul envoi
local function sendActive(player: Player)
	if player.Parent == nil then
		return
	end
	local spawns = {}
	for _, c in creatures do
		if visibleTo(c, player) then
			table.insert(spawns, table.clone(c.spawn))
		end
	end
	table.sort(spawns, function(a: Types.ChaseSpawn, b: Types.ChaseSpawn): boolean
		return a.id < b.id
	end)
	local payload: Types.ChaseEventPayload = { spawns = spawns, finishes = {} }
	Net.event("ChaseEvent"):FireClient(player, payload)
end

-- =============================================================================================
-- Acteurs (MoveCheck) et anti-triche
-- =============================================================================================

local function onRewind(player: Player, character: Model, root: BasePart, back: Vector3, now: number)
	Guard.try("chase:pivot", function()
		character:PivotTo(CFrame.new(back) * (root.CFrame - root.CFrame.Position))
	end)
	player:SetAttribute("Unstable", true)
	unstableUntil[player] = now + UNSTABLE_SECONDS
	local data = profile(player)
	if data and type(data.flags) == "table" then
		data.flags.strikes = (if finite(data.flags.strikes) then data.flags.strikes else 0) + 1
		if MoveCheck.recentRewinds(player, now) >= Tuning.MoveCheck.StrikesForBan then
			-- exclusion des classements jusqu'à la fin de la semaine suivante (jamais à vie)
			local untilT = Clock.unix() + Clock.untilNextWeek() + WEEK_SECONDS
			if not finite(data.flags.lbBanUntil) or data.flags.lbBanUntil < untilT then
				data.flags.lbBanUntil = untilT
			end
		end
		DataService.markDirty(player, "flags")
	end
	local violations = MoveCheck.violations(player)
	Signals.MoveViolation:Fire(player, violations)
	Guard.analytics(player, "MoveViolation", violations)
end

local function actorFor(player: Player, now: number, dt: number, out: { [Player]: Types.TickActor })
	if player.Parent == nil or not DataService.isLoaded(player) or not RanchService.isReady(player) then
		return
	end
	local root, humanoid = rootOf(player)
	if root == nil or humanoid == nil then
		return
	end
	local character = player.Character :: Model
	local pos = root.Position
	if seenCharacter[player] ~= character then
		seenCharacter[player] = character
		MoveCheck.reset(player, pos, now)
	end
	local speed = humanoid.WalkSpeed
	if lastSpeed[player] ~= speed then
		lastSpeed[player] = speed
		MoveCheck.noteSpeed(player, speed, now)
	end
	local verdict, back, burst = MoveCheck.step(player, pos, dt, now, WorldLayout.supportY(pos))
	if verdict == "rewind" and back then
		onRewind(player, character, root, back, now)
	end
	local valid = MoveCheck.lastValid(player) or pos
	out[player] = {
		player = player,
		slot = RanchService.slotOf(player),
		pos = valid,
		canAct = verdict == "ok" and not burst and MoveCheck.canAct(player, now),
		riding = SquishyService.riding(player),
		rootOffset = MoveCheck.rootOffset(player),
	}
	Activity.noteMove(player, valid, now)
end

local function buildActors(now: number, dt: number)
	local fresh: { [Player]: Types.TickActor } = {}
	for _, player in Players:GetPlayers() do
		Guard.try("tick:actor", actorFor, player, now, dt, fresh)
	end
	actors = fresh
end

-- =============================================================================================
-- Intentions
-- =============================================================================================

local function onLeap(player: Player, dirX: number, dirZ: number, tClient: number): boolean
	local now = Clock.now()
	local dir = LeapRules.validDir(dirX, dirZ)
	if dir == nil then
		return false
	end
	if now < (leapAt[player] or -math.huge) + LEAP.Cooldown then
		return false
	end
	if SquishyService.carried(player) ~= nil then
		return false
	end
	local actor = actors[player]
	if actor == nil or not actor.canAct or not MoveCheck.canAct(player, now) then
		return false
	end
	local t = math.clamp(tClient, now - CATCH.ClientPast, now)
	if not MoveCheck.grant(player, LEAP.Distance, LEAP.Duration, t, now) then
		return false
	end
	leapAt[player] = now
	-- départ du bond : position reçue à l'arrivée du message (latence compensée, comme Catch) ; repli
	-- provisoire : position à tClient, sinon dernière position validée
	local from = MoveCheck.positionAt(player, now) or MoveCheck.positionAt(player, t) or actor.pos
	leaps[player] = {
		at = t + LEAP.Duration,
		landing = LeapRules.landing(from, dir),
		dir = dir,
		arrival = now,
		rootOffset = actor.rootOffset,
		startedAt = t,
	}
	return true
end

local function onCatch(player: Player, id: number, tClient: number): boolean
	local c = creatures[id]
	if c == nil or not visibleTo(c, player) or actors[player] == nil then
		return false
	end
	if c.spawn.kind == "golden" and goldenCooldown(player) then
		-- « Laisse les autres gagner celle-ci ! » (une fois par Golden)
		if goldenWarned[player] ~= id then
			goldenWarned[player] = id
			Notify.feedback(player, "feedback.letOthersWin", {}, "info")
		end
		return false
	end
	local count = 0
	for _, entry in catchQueue do
		if entry.player == player then
			count += 1
		end
	end
	if count >= MAX_QUEUED_CATCHES then
		return false
	end
	local now = Clock.now()
	table.insert(
		catchQueue,
		{ player = player, id = id, t = math.clamp(tClient, now - CATCH.ClientPast, now), arrival = now }
	)
	return true
end

-- =============================================================================================
-- Signaux et cycle de vie
-- =============================================================================================

local function onEventPhase(kind: string, phase: string, index: number)
	local now = Clock.now()
	if kind == "golden" and phase == "spawn" then
		if Features.get("GoldenWobbler") ~= true then
			return
		end
		local g = EventClock.golden(now)
		local t0 = if g.active and g.index == index then g.spawnAt else now
		spawnGolden(EventClock.seed("golden", index), t0)
	elseif kind == "golden" and phase == "admin" then
		-- fête d'administrateur : Golden Wobblers en plus (EventService, Events.Party.AdminGoldens)
		spawnGolden(EventClock.seed("goldenAdmin", index), now)
	elseif kind == "rush" and phase == "start" then
		local rush = EventClock.rush(now)
		local endsAt = if rush.active and rush.index == index then rush.endsAt else now + RUSH.Duration
		local n = #Players:GetPlayers()
		wildPlan = {
			index = index,
			endsAt = endsAt,
			total = RushRules.wildShared(n),
			released = 0,
			nextWaveAt = now,
			personalAt = now + WILD.PersonalDelay,
			personalDone = false,
			sharedCaught = {},
		}
	end
end

local function onPlayerRemoving(player: Player)
	-- fuites de ce propriétaire : rentrent aussitôt (rien n'a quitté le profil)
	ChaseService.returnEscapes(player, "left")
	for _, c in creatures do
		if c.personal == player then
			finish(c, "expired", 0, Clock.now())
		end
	end
	for i = #catchQueue, 1, -1 do
		if catchQueue[i].player == player then
			table.remove(catchQueue, i)
		end
	end
	MoveCheck.clear(player) -- remarque A26
	actors[player] = nil
	seenCharacter[player] = nil
	lastSpeed[player] = nil
	unstableUntil[player] = nil
	leapAt[player] = nil
	leaps[player] = nil
	runawayNextAt[player] = nil
	scriptedRunawayDone[player] = nil
	demoDone[player] = nil
	goldenWarned[player] = nil
	outPersonal[player] = nil
	local plan = wildPlan
	if plan then
		plan.sharedCaught[player] = nil
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function ChaseService.Init()
	MoveCheck.setSurface(WorldLayout.groundY)
	Guard.connect("Leap", onLeap)
	Guard.connect("Catch", onCatch)
end

-- Connexions et boucles
function ChaseService.Start()
	Signals.ServerMoved:Connect(function(player: Player)
		local root = rootOf(player)
		if root then
			seenCharacter[player] = player.Character
			MoveCheck.reset(player, root.Position, Clock.now())
		end
	end)
	Signals.PlayerReady:Connect(function(player: Player)
		Guard.try("chase:ready", sendActive, player)
	end)
	Signals.WorldRequested:Connect(function(player: Player)
		Guard.try("chase:world", sendActive, player)
	end)
	Signals.Booped:Connect(function(booper: Player, owner: Player, uid: string, angle: number)
		Guard.try("chase:booped", startEscape, booper, owner, uid, angle)
	end)
	Signals.ModeChanged:Connect(function(player: Player, rush: boolean)
		if not rush then
			Guard.try("chase:cozy", ChaseService.returnEscapes, player, "cozy")
		end
	end)
	Signals.EventPhase:Connect(function(kind: string, phase: string, index: number)
		Guard.try("chase:phase", onEventPhase, kind, phase, index)
	end)
	Signals.SquishyRemoved:Connect(function(player: Player, uid: string)
		for _, c in creatures do
			if c.spawn.kind == "escape" and c.owner == player and c.spawn.uid == uid then
				Guard.try("chase:removed", endEscape, c, "returned", nil, Clock.now())
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Guard.try("chase:leave", onPlayerRemoving, player)
	end)
	-- le seul Heartbeat du serveur : accumulateur à pas fixe (docs/04 §6)
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += if finite(dt) and dt > 0 then dt else 0
		if accumulator + 1e-9 < TICK then
			return
		end
		accumulator = math.min(accumulator - TICK, MAX_DT)
		if accumulator + 1e-9 >= TICK then
			-- retard au-delà d'un pas : rattrapé par la durée du tick (bornée), jamais par des ticks au
			-- même instant
			accumulator = 0
		end
		ChaseService.tick(Clock.now())
	end)
end

-- Tick complet (docs/04 §6) ; chaque étape sous pcall, erreur comptée par Diagnostics
function ChaseService.tick(now: number)
	if not finite(now) then
		return
	end
	local startedAt = os.clock()
	local previous = lastTickAt
	local dt = if previous then math.clamp(now - previous, 0, MAX_DT) else TICK
	lastTickAt = now
	Guard.try("tick:actors", buildActors, now, dt)
	local acting = actors
	Guard.try("tick:ranch", RanchService.step, now, acting)
	Guard.try("tick:economy", EconomyService.step, now)
	Guard.try("tick:squishy", SquishyService.step, now, acting)
	Guard.try("tick:quest", QuestService.step, now)
	Guard.try("tick:community", CommunityService.step, now, acting)
	Guard.try("tick:event", EventService.step, now, acting)
	Guard.try("tick:rush", RushService.step, now, acting)
	Guard.try("tick:splorch", SplorchService.step, now)
	Guard.try("tick:helpers", HelperService.step, now, acting) -- v2.0 [Helpers] : rien interrupteur coupé
	Guard.try("tick:creatures", stepCreatures, now)
	Guard.try("tick:leaps", stepLeaps, now)
	Guard.try("tick:catches", stepCatches, now)
	Guard.try("tick:broadcast", flushBroadcast, now)
	Guard.try("tick:ranchFlush", RanchService.flush)
	Guard.try("tick:leaderboard", LeaderboardService.step, now)
	Guard.try("tick:diagnostics", DiagnosticsService.step, now)
	-- durée du tick (panneau Diagnostics, GDD §12.11 : moyenne et maximum)
	Guard.try("tick:noteTick", DiagnosticsService.noteTick, (os.clock() - startedAt) * 1000)
end

-- Acteurs du dernier tick (positions validées)
function ChaseService.actors(): { [Player]: Types.TickActor }
	return actors
end

-- Créatures actives
function ChaseService.active(): { [number]: Types.ChaseSpawn }
	local out: { [number]: Types.ChaseSpawn } = {}
	for id, c in creatures do
		out[id] = c.spawn
	end
	return out
end

-- Ce squishy est en fuite
function ChaseService.isEscaping(owner: Player, uid: string): boolean
	for _, c in creatures do
		if c.spawn.kind == "escape" and c.owner == owner and c.spawn.uid == uid then
			return true
		end
	end
	return false
end

-- Toutes les fuites de ce propriétaire rentrent aussitôt (Cozy, départ), sans bonus
function ChaseService.returnEscapes(owner: Player, reason: string)
	local now = Clock.now()
	local outcome = if reason == "left" then "left" else "cozy"
	local list = {}
	for _, c in creatures do
		if c.spawn.kind == "escape" and c.owner == owner then
			table.insert(list, c)
		end
	end
	for _, c in list do
		endEscape(c, outcome, nil, now)
	end
end

-- Recharge du bond restante
function ChaseService.leapCooldownLeft(player: Player, now: number): number
	local at = leapAt[player]
	if at == nil or not finite(now) then
		return 0
	end
	return math.max(0, at + LEAP.Cooldown - now)
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « runaway »,
-- « escape », « wild », « golden », « demo » (créatures), « leap » (bonds), « unstable » ; startedAt en
-- Clock.now()
function ChaseService.openStates(): { Types.OpenState }
	local out: { Types.OpenState } = {}
	for _, c in creatures do
		local kind = c.spawn.kind
		local name = if kind == "wildPersonal" then "wild" else kind
		table.insert(out, { name = name, startedAt = c.spawn.t0, player = c.personal or c.owner })
	end
	for player, leap in leaps do
		table.insert(out, { name = "leap", startedAt = leap.at - LEAP.Duration, player = player })
	end
	for player, untilT in unstableUntil do
		table.insert(out, { name = "unstable", startedAt = untilT - UNSTABLE_SECONDS, player = player })
	end
	return out
end

return ChaseService
