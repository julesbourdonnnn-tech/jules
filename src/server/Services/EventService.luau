--!strict
-- EventService — paquet « events » (docs/04-architecture.md §11.8).
-- Propriétaire de l'état des événements de serveur (mémoire) : météo, Grande Comète, Nuit de la
-- Balise, Starfall Frenzy, Nuit d'Or, Gloomwisps, Starfall Saturday, boosts de serveur, LiveOps.
-- Responsabilités :
--   * transitions de phase pilotées par Logic/EventClock dans step(now) ; bannières
--     (Notify.banner) ; Signals.EventPhase ; SpawnService.setModifiers à chaque changement ;
--     EconomyService.setServerBoostUntil à chaque changement de boost
--   * Comète : alerte −8 s, impact au point déterministe, ramassage (premier joueur valide à ≤ 4 studs,
--     pas en Zen), vol « chat perché » (non-équipier, test balayé ≤ 4 studs ; nouveau porteur
--     immunisé 2 s, ancien interdit 4 s ; port sûr et bouclier ne protègent PAS), encaissement à la
--     porte de son Nid (Nebby → AtlasService.addNebbies "comet" + 120 s de revenu passif),
--     explosion à +75 s (5 Épiques libres, 1 par joueur, SpawnService.spawnLoose), participations
--     (≥ 3 s : +50 ; ≤ 20 studs à la fin : +15 et 30 s de revenu ; équipiers de l'encaisseur : +25),
--     chute si le porteur part, meurt ou passe en Zen (dropComet)
--   * Balise : alerte −15 s, trêve, barre de serveur (1 point par Nebby encaissé à l'anneau),
--     objectif Formulas.beaconGoal (miséricorde après 2 et 3 échecs) figé au début de la nuit,
--     réussite IMMÉDIATE quand la barre est pleine → Frenzy 60 s puis Nuit d'Or 5 min ; échec à la
--     fin : +15 par contributeur ; réussite : +40 par contributeur (aussi aux contributeurs tardifs),
--     bannière du meilleur contributeur ; Signals.BeaconResult
--   * Gloomwisps : nombre Formulas.wispCount (aucun pendant la Balise et Starfall), trajets
--     SeededPath (seed, t0), balayages pour les coupes (CongaService), éclatement à ≤ 4,5 studs
--     (+10 Stardust plafonnée, 20 s de revenu ; réapparition 10 s plus tard sur une nouvelle seed)
--   * Starfall Saturday : Rainbow continu, comètes toutes les 3 min, boost 20 min, présence ≥ 5 min
--     → 1 Nebby vedette Starborn envoyé au Nid à la fin
--   * boosts de serveur : une seule ligne de temps ×2 (Nuit d'Or, Starfall, Glow Party, LiveOps) ;
--     queueGlowParty prolonge depuis max(now, fin actuelle)
--   * LiveOps : remote AdminCommand (UserIds de Data/Admins seulement) → MessagingService
--     « LiveOps » → tous les serveurs ; attribut Player « Admin »
--   * EventState : état complet envoyé à tous à chaque changement (flush, au plus 1 par tick) et
--     à chaque arrivée
-- Aucun yield dans les fonctions stepées ; MessagingService en task.spawn + pcall.
-- GDD : §2.4, §4.15.1-§4.15.5, §4.10 (boosts), §7.6, §9.4, §14.3.
-- Dépendances : DataService, NestService, EconomyService, AtlasService, SpawnService,
-- Logic/EventClock, Logic/SeededPath, Logic/Formulas, Logic/Trail, Logic/WorldLayout, Logic/Hash,
-- Config/*, Data/Admins, Signals, Util/Notify, Util/RateLimit, Util/Analytics, Shared/Util/Clock,
-- Events/Safe, Events/Tuning.

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Nebbies = require(Shared.Config.Nebbies)
local Zones = require(Shared.Config.Zones)
local EventClock = require(Shared.Logic.EventClock)
local Formulas = require(Shared.Logic.Formulas)
local Hash = require(Shared.Logic.Hash)
local SeededPath = require(Shared.Logic.SeededPath)
local Trail = require(Shared.Logic.Trail)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Validate = require(Shared.Util.Validate)

local Server = script.Parent.Parent
local Admins = require(Server.Data.Admins)
local Signals = require(Server.Signals)
local Analytics = require(Server.Util.Analytics)
local Notify = require(Server.Util.Notify)
local RateLimit = require(Server.Util.RateLimit)
local Safe = require(Server.Events.Safe)
local Tuning = require(Server.Events.Tuning)

local DataService = require(script.Parent.DataService)
local NestService = require(script.Parent.NestService)
local EconomyService = require(script.Parent.EconomyService)
local AtlasService = require(script.Parent.AtlasService)
local SpawnService = require(script.Parent.SpawnService)

local EventService = {}

export type WispSweep = { id: number, from: Vector3, to: Vector3 }

local CometCfg = Balance.Comet
local BeaconCfg = Balance.Beacon
local WispCfg = Balance.Wisps
local SF = Events.Starfall
local STARBORN_BIT = Nebbies.Variants.starborn.bit
local TAG = "EventService"

-- Débits des remotes (docs §10.1)
local ADMIN_RATE = { n = 1, per = 2 }

-- ---------------------------------------------------------------------------------------------
-- État (mémoire du serveur)
-- ---------------------------------------------------------------------------------------------

type CometPhase = "warn" | "ground" | "carried" | "banked" | "burst"

type CometRun = {
	id: number,
	warnAt: number,
	impactAt: number,
	burstAt: number,
	forced: boolean,
	phase: CometPhase,
	pos: Vector3, -- point au sol (impact, chute) ou dernière position valide du porteur
	code: number,
	carrier: Player?,
	carrierSince: number,
	prevCarrierId: number?,
	immuneUntil: number, -- nouveau porteur intouchable jusqu'à
	retake: { [Player]: number }, -- reprise interdite jusqu'à (ancien porteur, lâcheur)
	held: { [Player]: number }, -- secondes de port cumulées sur cette Comète
	holdRewarded: { [Player]: boolean },
	nearRewarded: { [Player]: boolean },
	endedAt: number?,
}

type BeaconPhase = "warn" | "active" | "success" | "fail"

type BeaconRun = {
	id: number,
	warnAt: number,
	startsAt: number,
	endsAt: number,
	phase: BeaconPhase,
	points: number,
	goal: number,
	contributions: { [Player]: number },
	order: { Player }, -- contributeurs dans l'ordre de leur première contribution
	rewarded: { [Player]: boolean },
	top: Player?,
	topUserId: number?,
	topPoints: number,
}

type WispRun = {
	id: number,
	seed: number,
	t0: number,
	cursor: SeededPath.ChordCursor,
	pos: Vector3, -- position à ce tick (Y = sol + hauteur du corps)
	prev: Vector3, -- position au tick précédent
	poppedAt: number?,
	poppedBy: number?,
	respawnAt: number?,
}

type Positioned = { player: Player, pos: Vector3, slot: number }

local stateRemote: RemoteEvent? = nil

local lastNow = 0 -- now du dernier step (0 = jamais stepé)
local dirty = true
local activePlayers = 0

local weather: Types.WeatherState? = nil
local weatherShow = false -- la fenêtre courante est le Rainbow de Starfall
local forcedWeather: Types.WeatherState? = nil

local starfall: Types.StarfallState? = nil
local presence: { [Player]: number } = {}

local comet: CometRun? = nil
local doneComets: { [number]: boolean } = {} -- créneaux terminés ou remplacés (jamais relancés)

local beacon: BeaconRun? = nil
local doneBeaconId: number? = nil
local beaconFails = 0

local frenzyEndsAt = 0
local goldenNightAt: number? = nil -- début programmé de la Nuit d'Or (fin du Frenzy)
local goldenNightEndsAt = 0

local boostUntil = 0
local boostSource: string? = nil
local boostBuyerId: number? = nil

local wisps: { WispRun } = {}
local nextWispId = 1
local wispSeedCounter = 0
local wispSnips = 0 -- Nebbies grignotés par les Gloomwisps depuis le démarrage (diagnostic)

local modsKey = ""

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function finite(x: unknown): boolean
	return Validate.finiteNumber(x)
end

local function getStateRemote(): RemoteEvent
	local r = stateRemote
	if r == nil then
		r = Net.event("EventState")
		stateRemote = r
	end
	return r :: RemoteEvent
end

local function distXZ(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function speciesName(s: number): string
	local def = Nebbies.Species[s]
	return if def then def.name else ""
end

local function isPlayerArg(x: unknown): boolean
	return typeof(x) == "Instance" and (x :: Instance):IsA("Player")
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

local function hasLiveCharacter(player: Player): boolean
	local character = player.Character
	if character == nil or rootPosition(player) == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Positions de tous les joueurs (filet sans acteurs : résolution de l'explosion depuis step)
local function characterPositions(): { Positioned }
	local out: { Positioned } = {}
	for _, player in Players:GetPlayers() do
		local pos = rootPosition(player)
		if pos then
			table.insert(out, {
				player = player,
				pos = pos,
				slot = Safe.value(TAG .. ".slotOf", 0, NestService.slotOf, player),
			})
		end
	end
	return out
end

local function positionsOfActors(actors: { Types.Actor }): { Positioned }
	local out: { Positioned } = {}
	for _, a in actors do
		table.insert(out, { player = a.player, pos = a.pos, slot = a.slot })
	end
	return out
end

-- Analytique « une fois par événement » : il faut un joueur, on prend le plus pertinent présent
local function logServerEvent(preferred: Player?, name: string, value: number)
	local target = preferred
	if target == nil or target.Parent == nil then
		target = Players:GetPlayers()[1]
	end
	if target then
		Analytics.event(target, name, value)
	end
end

local function formOfKey(key: string): number?
	local def = Events.WeatherByKey[key]
	if def == nil or def.form == nil or not Nebbies.isVersionEnabled(def.version) then
		return nil
	end
	if not Nebbies.isFormEnabled(def.form) then
		return nil
	end
	return def.form
end

-- ---------------------------------------------------------------------------------------------
-- Boost ×2 de serveur (une seule ligne de temps, docs §16.11)
-- ---------------------------------------------------------------------------------------------

local function extendBoost(endsAt: number, source: string, buyerId: number?): number
	if endsAt > boostUntil then
		boostUntil = endsAt
		boostSource = source
		boostBuyerId = buyerId
		dirty = true
		Safe.call(TAG .. ".setServerBoostUntil", EconomyService.setServerBoostUntil, boostUntil)
	end
	return boostUntil
end

local function stepBoost(now: number)
	if boostSource ~= nil and now >= boostUntil then
		boostSource = nil
		boostBuyerId = nil
		dirty = true
	end
end

-- ---------------------------------------------------------------------------------------------
-- Starfall Frenzy et Nuit d'Or
-- ---------------------------------------------------------------------------------------------

local function startFrenzy(now: number, thenGoldenNight: boolean)
	local wasActive = frenzyEndsAt > now
	frenzyEndsAt = math.max(frenzyEndsAt, now + BeaconCfg.FrenzySeconds)
	if thenGoldenNight then
		goldenNightAt = frenzyEndsAt
	end
	dirty = true
	if not wasActive then
		Signals.EventPhase:Fire("frenzy", "start")
	end
end

local function startGoldenNight(now: number, source: string)
	local endsAt = now + BeaconCfg.GoldenNightSeconds
	goldenNightEndsAt = math.max(goldenNightEndsAt, endsAt)
	extendBoost(endsAt, source, nil)
	dirty = true
	Notify.banner("goldenNight", { endsAt = goldenNightEndsAt })
	Signals.EventPhase:Fire("goldenNight", "start")
end

local function stepFrenzy(now: number)
	if frenzyEndsAt > 0 and now >= frenzyEndsAt then
		frenzyEndsAt = 0
		dirty = true
		Signals.EventPhase:Fire("frenzy", "end")
	end
	local at = goldenNightAt
	if at ~= nil and now >= at then
		goldenNightAt = nil
		startGoldenNight(now, "goldenNight")
	end
	if goldenNightEndsAt > 0 and now >= goldenNightEndsAt then
		goldenNightEndsAt = 0
		dirty = true
		Signals.EventPhase:Fire("goldenNight", "end")
	end
end

-- ---------------------------------------------------------------------------------------------
-- Starfall Saturday
-- ---------------------------------------------------------------------------------------------

-- Nebby vedette Starborn garanti (présence ≥ PresenceSeconds pendant le show)
local function giveStarfallGift(player: Player, show: Types.StarfallState)
	if not DataService.isLoaded(player) then
		return
	end
	local code = Nebbies.pack(show.featured, 0, STARBORN_BIT)
	local ok = Safe.call(TAG .. ".starfallGift", AtlasService.addNebbies, player, { code }, "starfall")
	if ok then
		Notify.feedback(player, "feedback.starfallGift", { species = speciesName(show.featured) }, "reward")
	end
end

local function endStarfall(show: Types.StarfallState)
	dirty = true
	Signals.EventPhase:Fire("starfall", "end")
	for player, seconds in presence do
		if seconds >= SF.PresenceSeconds and player.Parent ~= nil then
			giveStarfallGift(player, show)
		end
	end
	table.clear(presence)
end

-- Départ, branché dès Init pour passer AVANT la sauvegarde de départ de DataService (qui copie le
-- profil) : ce qui est accordé ici est bien écrit.
--   * Starfall : un joueur déjà qualifié qui part pendant le show reçoit tout de suite son cadeau
--     « garanti » (sinon il le perdait en partant avant 16:20)
--   * Comète : le porteur la lâche ; son dernier temps de port (Signals.CometHeld → quête
--     « Porteur de Comète ») est compté avant la sauvegarde
local function onPlayerLeavingEarly(player: Player)
	EventService.dropComet(player)
	local show = starfall
	local seconds = presence[player]
	presence[player] = nil
	if show ~= nil and seconds ~= nil and seconds >= SF.PresenceSeconds then
		giveStarfallGift(player, show)
	end
end

local function stepStarfall(now: number, dt: number)
	local sf = EventClock.starfall(now)
	local current = starfall
	if current ~= nil and (sf == nil or sf.startsAt ~= current.startsAt) then
		starfall = nil
		endStarfall(current)
		current = nil
	end
	if sf ~= nil and current == nil then
		starfall = { startsAt = sf.startsAt, endsAt = sf.endsAt, featured = sf.featured }
		table.clear(presence)
		dirty = true
		extendBoost(sf.startsAt + SF.BoostSeconds, "starfall", nil)
		Notify.banner("starfall", {
			s = sf.featured,
			species = speciesName(sf.featured),
			code = Nebbies.pack(sf.featured, 0, 0),
			endsAt = sf.endsAt,
		})
		Signals.EventPhase:Fire("starfall", "start")
	end
	if starfall ~= nil and dt > 0 then
		for _, player in Players:GetPlayers() do
			if DataService.isLoaded(player) then
				presence[player] = (presence[player] or 0) + dt
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Météo (§4.15.1)
-- ---------------------------------------------------------------------------------------------

local function sameWeather(a: Types.WeatherState?, b: Types.WeatherState?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.key == b.key and a.startsAt == b.startsAt and a.endsAt == b.endsAt and a.forced == b.forced
end

-- Forme de la météo active à l'instant t (prévision exacte : planning déterministe + LiveOps)
local function weatherFormAt(t: number): number?
	local fw = forcedWeather
	if fw ~= nil and t >= fw.startsAt and t < fw.endsAt and EventClock.starfall(t) == nil then
		return fw.form
	end
	local w = EventClock.weather(t)
	return if w then w.form else nil
end

local function stepWeather(now: number)
	local fw = forcedWeather
	if fw ~= nil and now >= fw.endsAt then
		forcedWeather = nil
		fw = nil
	end
	local nextState: Types.WeatherState? = nil
	local show = false
	if fw ~= nil and starfall == nil then
		nextState =
			{ key = fw.key, form = fw.form, startsAt = fw.startsAt, endsAt = fw.endsAt, forced = true }
	else
		local w = EventClock.weather(now)
		if w then
			nextState = { key = w.key, form = w.form, startsAt = w.startsAt, endsAt = w.endsAt }
			show = w.starfall
		end
	end
	if sameWeather(weather, nextState) then
		return
	end
	local old = weather
	weather = nextState
	weatherShow = show
	dirty = true
	if old ~= nil then
		Signals.EventPhase:Fire("weather", "end")
	end
	if nextState ~= nil then
		if not show then
			Notify.banner("weather", {
				key = nextState.key,
				form = nextState.form,
				endsAt = nextState.endsAt,
				forced = nextState.forced == true,
			})
		end
		Signals.EventPhase:Fire("weather", "start")
	end
end

-- ---------------------------------------------------------------------------------------------
-- Modificateurs d'apparition (SpawnService)
-- ---------------------------------------------------------------------------------------------

local function computeModifiers(now: number): Types.SpawnModifiers
	local m: Types.SpawnModifiers = {
		form = nil,
		formChance = 0,
		intervalDiv = 1,
		capMult = 1,
		featured = nil,
		featuredChance = 0,
		starbornChance = 0,
	}
	local w = weather
	if w ~= nil then
		if w.form ~= nil then
			m.form = w.form
			m.formChance = Balance.Spawn.WeatherFormChance
		end
		local def = Events.WeatherByKey[w.key]
		if def ~= nil then
			m.intervalDiv *= def.intervalDiv or 1
			m.capMult *= def.capMult or 1
		end
	end
	if frenzyEndsAt > now then
		m.intervalDiv *= BeaconCfg.FrenzyIntervalDiv
		m.capMult *= BeaconCfg.FrenzyCapMult
	end
	local show = starfall
	if show ~= nil then
		m.featured = show.featured
		m.featuredChance = SF.FeaturedChance
		m.starbornChance = SF.StarbornChance
	end
	return m
end

local function pushModifiers(now: number)
	local m = computeModifiers(now)
	local key = table.concat({
		tostring(m.form),
		tostring(m.formChance),
		tostring(m.intervalDiv),
		tostring(m.capMult),
		tostring(m.featured),
		tostring(m.featuredChance),
		tostring(m.starbornChance),
	}, "|")
	if key ~= modsKey then
		modsKey = key
		Safe.call(TAG .. ".setModifiers", SpawnService.setModifiers, m)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Grande Comète (§4.15.2)
-- ---------------------------------------------------------------------------------------------

local function cometCode(id: number, form: number?): number
	local _, s = EventClock.cometContent(id)
	return Nebbies.pack(s, form or 0, 0)
end

local function newComet(
	id: number,
	warnAt: number,
	impactAt: number,
	burstAt: number,
	forced: boolean
): CometRun
	return {
		id = id,
		warnAt = warnAt,
		impactAt = impactAt,
		burstAt = burstAt,
		forced = forced,
		phase = "warn",
		pos = EventClock.cometImpact(id),
		code = cometCode(id, weatherFormAt(impactAt)),
		carrier = nil,
		carrierSince = 0,
		prevCarrierId = nil,
		immuneUntil = 0,
		retake = {},
		held = {},
		holdRewarded = {},
		nearRewarded = {},
		endedAt = nil,
	}
end

local function impactComet(c: CometRun)
	c.phase = "ground"
	c.pos = EventClock.cometImpact(c.id)
	-- contenu : forme de la météo active À L'IMPACT (Prismatic pendant Starfall), docs §16.8
	c.code = cometCode(c.id, weatherFormAt(c.impactAt))
	dirty = true
	Signals.EventPhase:Fire("comet", "impact")
	Signals.CometEvent:Fire({ kind = "impact", id = c.id })
end

local function beginComet(c: CometRun, now: number)
	comet = c
	dirty = true
	if now < c.impactAt then
		Notify.banner("cometWarn", { impactAt = c.impactAt, x = c.pos.X, z = c.pos.Z })
	end
	Signals.EventPhase:Fire("comet", "warn")
	Signals.CometEvent:Fire({ kind = "warn", id = c.id })
	if now >= c.impactAt then
		impactComet(c)
	end
end

-- Participation « tenue ≥ 3 s » (cumulée sur cette Comète), récompensée une fois
local function checkHoldReward(c: CometRun, player: Player, now: number)
	if c.holdRewarded[player] then
		return
	end
	local total = c.held[player] or 0
	if c.carrier == player then
		total += math.max(0, now - c.carrierSince)
	end
	if total < CometCfg.HoldMinSeconds then
		return
	end
	c.holdRewarded[player] = true
	local dust =
		Safe.value(TAG .. ".holdDust", 0, EconomyService.addStardust, player, CometCfg.HoldDust, "Comet")
	Notify.feedback(player, "feedback.cometHold", { dust = dust }, "reward")
	Signals.CometParticipation:Fire(player, "hold")
end

-- Fin d'un port (vol, chute, encaissement, explosion) : temps cumulé, signal, analytique
local function releaseHold(c: CometRun, player: Player, now: number)
	checkHoldReward(c, player, now)
	local stint = math.max(0, now - c.carrierSince)
	c.held[player] = (c.held[player] or 0) + stint
	if c.carrier == player then
		c.carrier = nil
	end
	c.prevCarrierId = player.UserId
	Signals.CometHeld:Fire(player, stint)
	Analytics.event(player, "CometHeld", math.floor(stint * 10 + 0.5) / 10)
end

local function canCarry(a: Types.Actor, c: CometRun, now: number): boolean
	return a.valid == true
		and a.slot > 0
		and not a.zen
		and a.player.Parent ~= nil
		and (c.retake[a.player] or -math.huge) <= now
end

local function takeComet(c: CometRun, now: number, actor: Types.Actor, from: Player?)
	if from ~= nil then
		releaseHold(c, from, now)
		c.retake[from] = now + CometCfg.RetakeCooldown
	end
	local player = actor.player
	c.carrier = player
	c.carrierSince = now
	c.immuneUntil = now + CometCfg.NewCarrierImmunity
	c.phase = "carried"
	c.pos = actor.pos
	dirty = true
	if from ~= nil then
		Notify.banner("cometStolen", {
			userId = player.UserId,
			name = player.DisplayName,
			fromId = from.UserId,
			fromName = from.DisplayName,
		}, player)
		Notify.feedback(from, "feedback.cometStolen", { name = player.DisplayName }, "warning")
		Signals.CometEvent:Fire({ kind = "steal", id = c.id, player = player, from = from })
	else
		Notify.banner("cometPickup", { userId = player.UserId, name = player.DisplayName }, player)
		Signals.CometEvent:Fire({ kind = "pickup", id = c.id, player = player })
	end
end

-- +15 Stardust et 30 s de revenu à ceux qui sont à ≤ 20 studs (XZ) lors de la fin (Zen compris)
local function nearRewards(c: CometRun, center: Vector3, positions: { Positioned }, exclude: Player?)
	for _, e in positions do
		local player = e.player
		if
			player ~= exclude
			and e.slot > 0
			and player.Parent ~= nil
			and not c.nearRewarded[player]
			and distXZ(e.pos, center) <= CometCfg.NearRadius
		then
			c.nearRewarded[player] = true
			local dust = Safe.value(
				TAG .. ".nearDust",
				0,
				EconomyService.addStardust,
				player,
				CometCfg.NearDust,
				"Comet"
			)
			Safe.call(
				TAG .. ".nearGlow",
				EconomyService.addGlowSeconds,
				player,
				CometCfg.NearIdleSeconds,
				"Comet"
			)
			Notify.feedback(player, "feedback.cometNear", { dust = dust }, "reward")
			Signals.CometParticipation:Fire(player, "near")
		end
	end
end

-- +25 Stardust aux équipiers présents de l'encaisseur (crédit de Comète partagé, GDD §6.1)
local function crewRewards(banker: Player, crewId: number)
	local id = crewId
	if id == 0 then
		local attr = banker:GetAttribute("CrewId")
		id = if type(attr) == "number" then attr else 0
	end
	if id == 0 then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= banker and other:GetAttribute("CrewId") == id and DataService.isLoaded(other) then
			local dust = Safe.value(
				TAG .. ".crewDust",
				0,
				EconomyService.addStardust,
				other,
				CometCfg.CrewDust,
				"Comet"
			)
			Notify.feedback(other, "feedback.cometCrew", { dust = dust }, "reward")
			Signals.CometParticipation:Fire(other, "crew")
		end
	end
end

local function finishComet(c: CometRun, now: number, phase: CometPhase)
	c.phase = phase
	c.endedAt = now
	c.carrier = nil
	doneComets[c.id] = true
	dirty = true
end

local function bankComet(c: CometRun, now: number, actor: Types.Actor, actors: { Types.Actor })
	local player = actor.player
	releaseHold(c, player, now)
	c.pos = actor.pos
	finishComet(c, now, "banked")
	-- 120 s du revenu passif AU MOMENT de l'encaissement (avant que le Nebby rejoigne un perchoir)
	local glow = Safe.value(
		TAG .. ".bankGlow",
		0,
		EconomyService.addGlowSeconds,
		player,
		CometCfg.BankIdleSeconds,
		"Comet"
	)
	Safe.call(TAG .. ".bankNebby", AtlasService.addNebbies, player, { c.code }, "comet")
	Notify.celebrate(player, "cometBanked", { glow = glow, code = c.code })
	-- bannière d'événement (une par Comète) : jamais retenue par la limite par joueur
	Notify.banner("cometBanked", { userId = player.UserId, name = player.DisplayName, code = c.code })
	nearRewards(c, actor.pos, positionsOfActors(actors), player)
	crewRewards(player, actor.crewId)
	Signals.EventPhase:Fire("comet", "bank")
	Signals.CometEvent:Fire({ kind = "bank", id = c.id, player = player })
	Analytics.event(player, "CometBanked", 1)
end

local function burstComet(c: CometRun, now: number, positions: { Positioned })
	local carrier = c.carrier
	if carrier ~= nil then
		releaseHold(c, carrier, now)
	end
	finishComet(c, now, "burst")
	local center = c.pos
	-- 5 Épiques libres au point d'explosion, 1 au plus par joueur (groupe burst:<id>)
	local epics = Nebbies.speciesOfRarity(CometCfg.BurstRarity)
	if #epics > 0 and CometCfg.BurstCount > 0 then
		local codes: { number } = {}
		local from: { Vector3 } = {}
		for i = 1, CometCfg.BurstCount do
			local s = epics[Hash.int(1, #epics, c.id, Events.Salts.CometSpecies, CometCfg.BurstRarity, i)]
			table.insert(codes, Nebbies.pack(s, 0, 0))
			table.insert(from, center)
		end
		local zone = Zones.byKey[WorldLayout.zoneAt(center) or ""]
		Safe.call(TAG .. ".burstSpawn", SpawnService.spawnLoose, codes, from, now, {
			group = "burst:" .. tostring(c.id),
			groupCap = CometCfg.BurstPerPlayer,
			life = if zone then zone.lifetime else nil,
		})
	end
	Notify.banner("cometBurst", { x = center.X, z = center.Z })
	nearRewards(c, center, positions, nil)
	Signals.EventPhase:Fire("comet", "burst")
	Signals.CometEvent:Fire({ kind = "burst", id = c.id, player = carrier })
	logServerEvent(carrier, "CometBurst", 1)
end

local function stepCometPhases(now: number)
	local c = comet
	if c ~= nil and c.endedAt == nil then
		if c.phase == "warn" and now >= c.impactAt then
			impactComet(c)
		end
		-- filet : stepComet n'a pas résolu l'explosion (erreur en amont) → résolution sans acteurs
		if now >= c.burstAt + Tuning.SlowStepInterval then
			burstComet(c, now, characterPositions())
		end
	end
	if c ~= nil and c.endedAt ~= nil and now >= (c.endedAt :: number) + Tuning.ResultLinger then
		comet = nil
		dirty = true
		c = nil
	end
	-- oubli des vieux créneaux (une heure suffit largement)
	for id in doneComets do
		if id < now - 3600 then
			doneComets[id] = nil
		end
	end
	local slot = EventClock.comet(now)
	if c ~= nil and c.endedAt == nil then
		-- une Comète forcée (LiveOps) en cours remplace un créneau normal qui la chevauche
		if c.forced and slot ~= nil and slot.id ~= c.id then
			doneComets[slot.id] = true
		end
		return
	end
	-- nouvelle Comète (elle remplace aussi un résultat encore affiché)
	if slot ~= nil and not doneComets[slot.id] and (c == nil or c.id ~= slot.id) then
		beginComet(newComet(slot.id, slot.warnAt, slot.impactAt, slot.burstAt, false), now)
	end
end

local function findActor(actors: { Types.Actor }, player: Player): Types.Actor?
	for _, a in actors do
		if a.player == player then
			return a
		end
	end
	return nil
end

local function stepGround(c: CometRun, now: number, actors: { Types.Actor })
	local best: Types.Actor? = nil
	local bestD = math.huge
	for _, a in actors do
		if canCarry(a, c, now) then
			local d = Trail.segmentDistanceXZ(a.prev, a.pos, c.pos, c.pos)
			if d <= CometCfg.PickupRadius and d < bestD then
				best, bestD = a, d
			end
		end
	end
	if best ~= nil then
		takeComet(c, now, best, nil)
	end
end

-- Le déplacement VALIDÉ prev → pos du porteur traverse-t-il la porte de son Nid ? Comme pour les
-- parades (CongaService) : à 10 Hz, avec la gigue du réseau, deux échantillons peuvent tomber de part
-- et d'autre de la boîte de porte (profonde de 4 studs) ; on la teste donc le long du pas, tous les
-- GATE_SWEEP_STEP studs. CongaService garantit que prev → pos est un déplacement validé.
local GATE_SWEEP_STEP = 1
local GATE_SWEEP_MAX = 128
local function sweptThroughGate(slot: number, prev: Vector3, pos: Vector3): boolean
	if WorldLayout.inGateBox(slot, pos) then
		return true
	end
	local delta = pos - prev
	local samples = math.min(math.ceil(delta.Magnitude / GATE_SWEEP_STEP), GATE_SWEEP_MAX)
	for i = 1, samples - 1 do
		if WorldLayout.inGateBox(slot, prev + delta * (i / samples)) then
			return true
		end
	end
	return false
end

local function stepCarried(c: CometRun, now: number, actors: { Types.Actor })
	local carrier = c.carrier :: Player
	local actor = findActor(actors, carrier)
	if actor == nil then
		if carrier.Parent == nil or not hasLiveCharacter(carrier) then
			EventService.dropComet(carrier)
		end
		return
	end
	if actor.zen then
		EventService.dropComet(carrier)
		return
	end
	if actor.valid then
		c.pos = actor.pos
	end
	checkHoldReward(c, carrier, now)
	-- encaissement : le porteur traverse la porte de SON Nid
	if actor.valid and actor.slot > 0 and sweptThroughGate(actor.slot, actor.prev, actor.pos) then
		bankComet(c, now, actor, actors)
		return
	end
	if now < c.immuneUntil then
		return
	end
	-- vol « chat perché » : balayage du voleur contre balayage du porteur (XZ)
	local best: Types.Actor? = nil
	local bestD = math.huge
	for _, a in actors do
		if
			a.player ~= carrier
			and canCarry(a, c, now)
			and not (a.crewId ~= 0 and a.crewId == actor.crewId)
		then
			local d = Trail.segmentDistanceXZ(a.prev, a.pos, actor.prev, actor.pos)
			if d <= CometCfg.StealRadius and d < bestD then
				best, bestD = a, d
			end
		end
	end
	if best ~= nil then
		takeComet(c, now, best, carrier)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Nuit de la Balise (§4.15.3)
-- ---------------------------------------------------------------------------------------------

local function rewardContributors(b: BeaconRun, success: boolean, list: { Player })
	local dust = if success then BeaconCfg.WinDust else BeaconCfg.FailDust
	local fresh: { Player } = {}
	for _, player in list do
		if not b.rewarded[player] then
			b.rewarded[player] = true
			table.insert(fresh, player)
			if player.Parent ~= nil then
				local got =
					Safe.value(TAG .. ".beaconDust", 0, EconomyService.addStardust, player, dust, "Beacon")
				Notify.feedback(
					player,
					if success then "feedback.beaconWin" else "feedback.beaconFail",
					{ dust = got },
					if success then "reward" else "info"
				)
			end
		end
	end
	Signals.BeaconResult:Fire(success, fresh)
end

local function startBeacon(b: BeaconRun)
	b.phase = "active"
	b.goal = Formulas.beaconGoal(activePlayers, beaconFails) -- figé pour toute la nuit
	dirty = true
	Notify.banner("beaconStart", { endsAt = b.endsAt, goal = b.goal })
	Signals.EventPhase:Fire("beacon", "start")
end

local function succeedBeacon(b: BeaconRun, now: number)
	b.phase = "success"
	beaconFails = 0
	dirty = true
	startFrenzy(now, true)
	Notify.banner("beaconWin", { points = b.points, goal = b.goal })
	local top = b.top
	if top ~= nil then
		Notify.banner("beaconTop", { userId = b.topUserId, name = top.DisplayName, n = b.topPoints })
	end
	Signals.EventPhase:Fire("beacon", "success")
	rewardContributors(b, true, table.clone(b.order))
	logServerEvent(top, "BeaconResult", 1)
end

local function failBeacon(b: BeaconRun)
	b.phase = "fail"
	beaconFails += 1
	dirty = true
	Notify.banner("beaconFail", { points = b.points, goal = b.goal })
	Signals.EventPhase:Fire("beacon", "fail")
	rewardContributors(b, false, table.clone(b.order))
	logServerEvent(b.top, "BeaconResult", 0)
end

local function stepBeacon(now: number)
	local b = beacon
	if b ~= nil then
		if b.phase == "warn" and now >= b.startsAt then
			startBeacon(b)
		end
		if b.phase == "active" and now >= b.endsAt then
			failBeacon(b)
		end
		-- fin de la trêve à endsAt ; un échec reste affiché ResultLinger secondes de plus
		local over = (b.phase == "success" and now >= b.endsAt)
			or (b.phase == "fail" and now >= b.endsAt + Tuning.ResultLinger)
		if over then
			beacon = nil
			dirty = true
			Signals.EventPhase:Fire("beacon", "end")
		end
		return
	end
	local w = EventClock.beacon(now)
	if w ~= nil and w.id ~= doneBeaconId then
		doneBeaconId = w.id
		local run: BeaconRun = {
			id = w.id,
			warnAt = w.warnAt,
			startsAt = w.startsAt,
			endsAt = w.endsAt,
			phase = "warn",
			points = 0,
			goal = Formulas.beaconGoal(activePlayers, beaconFails),
			contributions = {},
			order = {},
			rewarded = {},
			top = nil,
			topUserId = nil,
			topPoints = 0,
		}
		beacon = run
		dirty = true
		Signals.EventPhase:Fire("beacon", "warn")
		if now >= run.startsAt then
			startBeacon(run)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Gloomwisps (§4.15.4)
-- ---------------------------------------------------------------------------------------------

local function wispPoint(w: WispRun, now: number): Vector3
	local p = w.cursor:at(now)
	return Vector3.new(p.X, WorldLayout.groundY(p.X, p.Z) + Tuning.WispBodyHeight, p.Z)
end

local function newWispSeed(now: number): number
	wispSeedCounter += 1
	return Hash.u32(Events.Salts.Wisp, wispSeedCounter, math.floor(now))
end

local function resetWisp(w: WispRun, now: number)
	w.seed = newWispSeed(now)
	w.t0 = now
	w.cursor = SeededPath.newChordCursor(w.seed, now)
	w.poppedAt = nil
	w.poppedBy = nil
	w.respawnAt = nil
	local p = wispPoint(w, now)
	w.pos = p
	w.prev = p
end

local function spawnWisp(now: number)
	local origin = Vector3.new(0, 0, 0)
	local w: WispRun = {
		id = nextWispId,
		seed = 0,
		t0 = now,
		cursor = SeededPath.newChordCursor(0, now),
		pos = origin,
		prev = origin,
		poppedAt = nil,
		poppedBy = nil,
		respawnAt = nil,
	}
	nextWispId = nextWispId % 65535 + 1
	resetWisp(w, now)
	table.insert(wisps, w)
	dirty = true
end

local function wispsSuppressed(): boolean
	local b = beacon
	return starfall ~= nil or (b ~= nil and b.phase ~= "fail")
end

local function stepWispLifecycle(now: number)
	local target = Formulas.wispCount(activePlayers, wispsSuppressed())
	for _, w in wisps do
		local at = w.respawnAt
		if at ~= nil and now >= at then
			resetWisp(w, now)
			dirty = true
		end
	end
	while #wisps > target do
		table.remove(wisps)
		dirty = true
	end
	while #wisps < target do
		spawnWisp(now)
	end
	for _, w in wisps do
		if w.poppedAt == nil then
			w.prev = w.pos
			w.pos = wispPoint(w, now)
		end
	end
end

local function popWisp(w: WispRun, player: Player, now: number)
	w.poppedAt = now
	w.poppedBy = player.UserId
	w.respawnAt = now + WispCfg.RespawnDelay
	dirty = true
	local dust = Safe.value(
		TAG .. ".wispDust",
		0,
		EconomyService.addStardustCapped,
		player,
		WispCfg.PopDust,
		"wispDust",
		"Wisp"
	)
	Safe.call(TAG .. ".wispGlow", EconomyService.addGlowSeconds, player, WispCfg.PopIdleSeconds, "Wisp")
	if dust > 0 then
		Notify.feedback(player, "feedback.wispPop", { dust = dust }, "reward")
	else
		Notify.feedback(player, "feedback.capReached", nil, "info")
	end
	Signals.WispPopped:Fire(player)
	Analytics.event(player, "WispPopped", 1)
end

-- ---------------------------------------------------------------------------------------------
-- LiveOps (§7.6)
-- ---------------------------------------------------------------------------------------------

-- "comet" | "frenzy" | "goldenNight" | "weather:<clé>" → (nom, argument) ou nil
local function parseCommand(command: unknown): (string?, string?)
	if not Validate.string(command, Tuning.LiveOpsCommandMax) then
		return nil, nil
	end
	local cmd = command :: string
	local name, arg = string.match(cmd, "^(%w+):(%w+)$")
	if name == nil then
		name = string.match(cmd, "^(%w+)$")
		arg = nil
	end
	if name == nil or Events.LiveOps.Commands[name] ~= true then
		return nil, nil
	end
	if name == "weather" then
		local def = if arg ~= nil then Events.WeatherByKey[arg] else nil
		if def == nil or not Nebbies.isVersionEnabled(def.version) then
			return nil, nil
		end
	elseif arg ~= nil then
		return nil, nil
	end
	return name, arg
end

local function publishLiveOps(command: string)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(Events.LiveOps.Topic, {
				cmd = command,
				at = Clock.now(),
				job = game.JobId,
			})
		end)
		if not ok then
			warn("[EventService] LiveOps PublishAsync :", err)
		end
	end)
end

local function onLiveOpsMessage(message: any)
	if type(message) ~= "table" then
		return
	end
	local data = message.Data
	if type(data) ~= "table" then
		return
	end
	if data.job == game.JobId then
		return -- déjà exécutée localement par ce serveur
	end
	if not finite(data.at) or math.abs(Clock.now() - data.at) > Tuning.LiveOpsMaxAge then
		return
	end
	EventService.runLiveOps(data.cmd)
end

local function onAdminCommand(player: Player, command: unknown)
	if not RateLimit.allow(player, "AdminCommand", ADMIN_RATE.n, ADMIN_RATE.per) then
		return
	end
	if not Validate.string(command, Tuning.LiveOpsCommandMax) then
		return
	end
	if Admins[player.UserId] ~= true then
		return
	end
	if parseCommand(command) == nil then
		return
	end
	local cmd = command :: string
	EventService.runLiveOps(cmd)
	publishLiveOps(cmd)
	Notify.feedback(player, "feedback.liveOpsDone", nil, "success")
end

-- ---------------------------------------------------------------------------------------------
-- EventState
-- ---------------------------------------------------------------------------------------------

local function cometState(): Types.CometState?
	local c = comet
	if c == nil then
		return nil
	end
	local carrier = c.carrier
	return {
		id = c.id,
		phase = c.phase,
		x = c.pos.X,
		z = c.pos.Z,
		code = c.code,
		warnAt = c.warnAt,
		impactAt = c.impactAt,
		burstAt = c.burstAt,
		carrierId = if carrier then carrier.UserId else nil,
		carrierSince = if carrier then c.carrierSince else nil,
		prevCarrierId = c.prevCarrierId,
		endedAt = c.endedAt,
	}
end

local function beaconState(): Types.BeaconState?
	local b = beacon
	if b == nil then
		return nil
	end
	return {
		phase = b.phase,
		warnAt = b.warnAt,
		startsAt = b.startsAt,
		endsAt = b.endsAt,
		points = b.points,
		goal = b.goal,
		topUserId = b.topUserId,
	}
end

local function buildState(now: number): Types.EventStatePayload
	local w = weather
	local show = starfall
	local wispList: { Types.WispState } = {}
	for _, wisp in wisps do
		table.insert(wispList, {
			id = wisp.id,
			seed = wisp.seed,
			t0 = wisp.t0,
			poppedAt = wisp.poppedAt,
			poppedBy = wisp.poppedBy,
			respawnAt = wisp.respawnAt,
		})
	end
	return {
		t = now,
		weather = if w
			then { key = w.key, form = w.form, startsAt = w.startsAt, endsAt = w.endsAt, forced = w.forced }
			else nil,
		comet = cometState(),
		beacon = beaconState(),
		frenzy = if frenzyEndsAt > now then { endsAt = frenzyEndsAt } else nil,
		serverBoost = if boostSource ~= nil and boostUntil > now
			then { endsAt = boostUntil, source = boostSource :: any, buyerId = boostBuyerId }
			else nil,
		starfall = if show
			then { startsAt = show.startsAt, endsAt = show.endsAt, featured = show.featured }
			else nil,
		wisps = wispList,
		snipsDisabled = Safe.value(TAG .. ".snipsDisabled", false, NestService.snipsDisabled),
		activePlayers = activePlayers,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	player:SetAttribute("Admin", Admins[player.UserId] == true)
	getStateRemote():FireClient(player, buildState(Clock.now()))
end

local function onPlayerRemoving(player: Player)
	EventService.dropComet(player)
	presence[player] = nil
	local c = comet
	if c ~= nil then
		c.retake[player] = nil
		c.held[player] = nil
		c.holdRewarded[player] = nil
		c.nearRewarded[player] = nil
	end
end

function EventService.Init()
	stateRemote = Net.event("EventState")
	-- seule connexion faite dans Init (aucun yield) : elle doit passer avant celle de DataService
	Players.PlayerRemoving:Connect(onPlayerLeavingEarly)
end

function EventService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Signals.SettingChanged:Connect(function(player: Player, key: string, value: any)
		if key == "zen" and value == true and EventService.isCarrier(player) then
			EventService.dropComet(player)
			Notify.feedback(player, "feedback.cometNoZen", nil, "warning")
		elseif key == "privateNoSnip" then
			dirty = true
		end
	end)

	Net.event("AdminCommand").OnServerEvent:Connect(onAdminCommand)

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(Events.LiveOps.Topic, onLiveOpsMessage)
		end)
		if not ok then
			warn("[EventService] LiveOps SubscribeAsync :", err)
		end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- API stepée (tick de CongaService, docs §6)
-- ---------------------------------------------------------------------------------------------

-- Étape 3 du tick : transitions de phase, positions des Gloomwisps
function EventService.step(now: number)
	if not finite(now) then
		return
	end
	local dt = if lastNow > 0 then math.clamp(now - lastNow, 0, Tuning.MaxStepGap) else 0
	lastNow = now
	stepStarfall(now, dt)
	stepWeather(now)
	stepBeacon(now)
	stepFrenzy(now)
	stepBoost(now)
	stepCometPhases(now)
	stepWispLifecycle(now)
	pushModifiers(now)
end

-- Étape 6 du tick : ramassage, vol, encaissement, explosion de la Comète
function EventService.stepComet(now: number, actors: { Types.Actor })
	local c = comet
	if c == nil or c.endedAt ~= nil or c.phase == "warn" or not finite(now) then
		return
	end
	local list: { Types.Actor } = if type(actors) == "table" then actors else {}
	if now >= c.burstAt then
		burstComet(c, now, positionsOfActors(list))
		return
	end
	if c.phase == "carried" and c.carrier ~= nil then
		stepCarried(c, now, list)
	elseif c.phase == "ground" then
		stepGround(c, now, list)
	end
end

-- Étape 7 : balayages des Gloomwisps actifs depuis le tick précédent (vide pendant la trêve)
function EventService.wispSweeps(_now: number): { WispSweep }
	local out: { WispSweep } = {}
	if EventService.isTruce() then
		return out
	end
	for _, w in wisps do
		if w.poppedAt == nil then
			table.insert(out, { id = w.id, from = w.prev, to = w.pos })
		end
	end
	return out
end

-- Un Gloomwisp vient de couper une file (« miam ! » joué par le client sur SnipEvent ;
-- l'analytique WispSnip est envoyée par CongaService) : comptage de diagnostic
function EventService.onWispSnip(wispId: number, victim: Player, count: number)
	if not Validate.integer(wispId, 0) or not Validate.integer(count, 1) or not isPlayerArg(victim) then
		return
	end
	wispSnips += count
end

-- Étape 8 : Gloomwisps éclatés par les joueurs (balayage du joueur contre balayage du Gloomwisp)
function EventService.stepWisps(now: number, actors: { Types.Actor })
	if not finite(now) or type(actors) ~= "table" then
		return
	end
	for _, w in wisps do
		if w.poppedAt == nil then
			for _, a in actors do
				if a.valid and a.slot > 0 and a.player.Parent ~= nil then
					if Trail.segmentDistanceXZ(a.prev, a.pos, w.prev, w.pos) <= WispCfg.PopRadius then
						popWisp(w, a.player, now)
						break
					end
				end
			end
		end
	end
end

-- Étape 12 : envoie EventState si l'état a changé
function EventService.flush()
	if not dirty then
		return
	end
	dirty = false
	local now = if lastNow > 0 then lastNow else Clock.now()
	getStateRemote():FireAllClients(buildState(now))
end

-- ---------------------------------------------------------------------------------------------
-- Requêtes
-- ---------------------------------------------------------------------------------------------

-- Trêve de la Balise (aucune coupe, joueurs ni Gloomwisps)
function EventService.isTruce(): boolean
	local b = beacon
	return b ~= nil and (b.phase == "active" or b.phase == "success")
end

-- L'anneau de la Balise sert-il de porte de parade ?
function EventService.beaconOpen(): boolean
	return EventService.isTruce()
end

-- Parade à l'anneau de la Balise : `count` points pour la barre
function EventService.onBeaconParade(player: Player, count: number)
	local b = beacon
	if b == nil or (b.phase ~= "active" and b.phase ~= "success") then
		return
	end
	if not isPlayerArg(player) or not Validate.integer(count, 1) then
		return
	end
	local now = Clock.now()
	if b.contributions[player] == nil then
		table.insert(b.order, player)
	end
	local total = (b.contributions[player] or 0) + count
	b.contributions[player] = total
	b.points += count
	if total > b.topPoints then
		b.top = player
		b.topUserId = player.UserId
		b.topPoints = total
	end
	dirty = true
	if b.phase == "active" and b.points >= b.goal then
		succeedBeacon(b, now)
	elseif b.phase == "success" and not b.rewarded[player] then
		-- contributeur tardif : la nuit est déjà gagnée, il touche la récompense de réussite
		rewardContributors(b, true, { player })
	end
end

function EventService.isCarrier(player: Player): boolean
	local c = comet
	return c ~= nil and c.endedAt == nil and c.carrier ~= nil and c.carrier == player
end

function EventService.carrier(): Player?
	local c = comet
	if c == nil or c.endedAt ~= nil then
		return nil
	end
	return c.carrier
end

-- Le porteur lâche la Comète (départ, mort, Zen) : elle retombe à sa dernière position valide,
-- il ne peut pas la reprendre pendant RetakeCooldown (docs §16.7)
function EventService.dropComet(player: Player)
	local c = comet
	if c == nil or c.endedAt ~= nil or c.phase ~= "carried" or c.carrier ~= player then
		return
	end
	local now = Clock.now()
	releaseHold(c, player, now)
	c.phase = "ground"
	c.retake[player] = now + CometCfg.RetakeCooldown
	local p = WorldLayout.clampToIsland(c.pos)
	c.pos = Vector3.new(p.X, WorldLayout.groundY(p.X, p.Z), p.Z)
	dirty = true
	Signals.CometEvent:Fire({ kind = "drop", id = c.id, player = player })
end

-- Forme de la météo active (nil = aucune ou Meteor Shower)
function EventService.weatherForm(): number?
	local w = weather
	return if w then w.form else nil
end

function EventService.serverBoostActive(): boolean
	return boostUntil > Clock.now()
end

-- Glow Party : prolonge le boost ×2 de serveur depuis max(now, fin actuelle) ; jamais refusée
-- (docs §16.9) ; retourne la nouvelle fin
function EventService.queueGlowParty(buyer: Player, seconds: number): number
	if not finite(seconds) or seconds <= 0 then
		return boostUntil
	end
	local now = Clock.now()
	local buyerId = if isPlayerArg(buyer) then buyer.UserId else nil
	return extendBoost(math.max(now, boostUntil) + seconds, "glowParty", buyerId)
end

-- Secondes de boost ×2 de serveur restantes (bouton masqué au-delà de Balance.GlowParty.HideAbove)
function EventService.glowPartyRemaining(): number
	return math.max(0, boostUntil - Clock.now())
end

-- Poussé par CongaService (joueurs actifs) au plus une fois par seconde
function EventService.setActivePlayers(n: number)
	if not finite(n) then
		return
	end
	local v = math.max(0, math.floor(n))
	if v == activePlayers then
		return
	end
	activePlayers = v
	dirty = true
	local b = beacon
	if b ~= nil and b.phase == "warn" then
		b.goal = Formulas.beaconGoal(activePlayers, beaconFails) -- aperçu (figé au début)
	end
end

-- Exécute une commande LiveOps localement (après validation ou réception MessagingService)
function EventService.runLiveOps(command: string)
	local name, arg = parseCommand(command)
	if name == nil then
		return
	end
	local now = Clock.now()
	if name == "comet" then
		local c = comet
		if c ~= nil and c.endedAt == nil then
			warn("[EventService] LiveOps comet ignorée : une Comète est déjà en cours")
			return
		end
		local impactAt = math.ceil(now) + CometCfg.WarnSeconds
		beginComet(
			newComet(
				impactAt,
				impactAt - CometCfg.WarnSeconds,
				impactAt,
				impactAt + CometCfg.BurstAfter,
				true
			),
			now
		)
		Notify.banner("liveOps", { command = name })
	elseif name == "weather" and arg ~= nil then
		forcedWeather = {
			key = arg,
			form = formOfKey(arg),
			startsAt = now,
			endsAt = now + Events.Weather.Duration,
			forced = true,
		}
		stepWeather(now)
		pushModifiers(now)
	elseif name == "frenzy" then
		startFrenzy(now, false)
		Notify.banner("liveOps", { command = name })
		pushModifiers(now)
	elseif name == "goldenNight" then
		startGoldenNight(now, "liveOps")
	end
end

function EventService.snapshot(): Types.EventStatePayload
	return buildState(Clock.now())
end

-- Diagnostic (tests, console) : Nebbies grignotés par les Gloomwisps et échecs consécutifs
function EventService.debugCounters(): { wispSnips: number, beaconFails: number, weatherShow: boolean }
	return { wispSnips = wispSnips, beaconFails = beaconFails, weatherShow = weatherShow }
end

return EventService
