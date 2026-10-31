--!strict
-- CongaService — paquet « conga » (docs/04-architecture.md §6 et §11.13).
-- DERNIER service initialisé : il orchestre le tick fixe de 10 Hz et possède les files.
-- Responsabilités :
--   * tick : accumulateur sur UNE connexion RunService.Heartbeat, pas fixe Balance.Tick.Step (0,1 s),
--     au plus MaxCatchUp (3) pas par image ; ordre EXACT des 12 étapes : §6 du contrat ; chaque
--     appel externe est protégé (pcall + avertissement au plus toutes les 10 s par étape) pour
--     qu'un service défaillant ne fige jamais le jeu
--   * miettes par joueur : trail (Trail.new(170, 0,5)) pour l'autorité, netTrail (Trail.new(170, 1,0,
--     firstSeq)) pour le réseau, numérotation contiguë par slot entre propriétaires successifs ;
--     poussées seulement si MoveCheck valide le tick ; remise à zéro sur saut ≥ 40 studs
--   * captures : joueurs avec place libre × SpawnService.query (rayon Attrait + 0,75, |Δy| ≤ 6,
--     Snip Rush ×1,5) ; le plus proche gagne, égalité → ordre tiré au hasard à chaque tick ;
--     file pleine → Feedback "feedback.lineFull" au plus toutes les 5 s ; plafond 1 500 captures/h
--     (au-delà : 5 min de suspension + flags.lbBanned) ; Signals.Caught ; bannières Légendaire+
--   * coupes : joueurs × files puis Gloomwisps × files (EventService.wispSweeps), SnipRules
--     (blockReason puis findCut, escorte via CrewService.escortersOf, port sûr via WorldLayout) ;
--     détache cutFrom(k, n) … n, Nebbies libres (SpawnService.spawnLoose silent, priorité victime),
--     immunités, recharges, Second Souffle (+4 pendant 3 s), Snip Rush (Attrait ×1,5, +5 Stardust par
--     Nebby plafonnée, pas de Stardust si le coupeur est sous bouclier) ; SnipEvent ; Signals.Snipped ;
--     Analytics SnipDealt / SnipReceived / SnipByInput / PostSnipQuit / WispSnip
--   * parades : boîte de la porte de SON Nid (WorldLayout.inGateBox), et anneau de la Balise quand
--     EventService.beaconOpen(), testées sur le déplacement VALIDÉ du tick (prev → pos, échantillons
--     de 1 stud : un pas de plus de 4 studs n'enjambe jamais la porte) ;
--     Glow = EconomyService.paradeGlow ; AtlasService.addNebbies ;
--     LineEvent "bank" ; Signals.Parade ; Méga Parade (≥ 30) ; QuestService.onSafeMoment ;
--     EventService.onBeaconParade ; forceParade (crochet de la Supernova) fait de même sans porte
--   * WalkSpeed (seul propriétaire de Humanoid.WalkSpeed) : Formulas.walkSpeed (Foulée, ralenti
--     au-delà des Guard Links, Comète ×0,85, Dash +10 pendant 1 s, Second Souffle +4) posé seulement
--     s'il change ; MoveCheck.noteSpeed ; remote Dash() 3/s (profil chargé, personnage vivant, pas
--     porteur, recharge serveur) → Signals.Dashed, attribut Player DashReadyAt
--   * mort / réinitialisation : file détachée (priorité au propriétaire, sans Second Souffle) ;
--     départ : détachée sans priorité ; LineEvent "clear" avec loose ; EventService.dropComet
--   * temps d'escorte (Signals.EscortTime), joueurs actifs (SpawnService/EventService.setActivePlayers)
--   * diffusion : LineEvent groupé par tick, SnipEvent (une par coupe, même suite de `ver`),
--     PathStream (PathCodec, non fiable, 10 Hz, 2 points répétés, découpé sous la limite moteur de
--     900 octets) ; remotes RequestWorld() 1/2 s → WorldSnapshot, RequestPath(slot 1-12) 4/s →
--     PathSnapshot (200 derniers points) ; WorldSnapshot à chaque arrivée, envoyé en fin de tick
--     APRÈS la diffusion des ops (aucune op en attente ne peut contredire l'instantané)
--   * remote SetInputType(kind 1-3) 1/5 s (aide tactile +0,3 aux coupes, champ analytique)
--   * MoveCheck : 3 infractions en 5 s → retour (PivotTo), 3 s sans capture/coupe/parade, attribut
--     « Unstable » ; flags.strikes ; 10 retours en 10 min → flags.lbBanned ; Signals.MoveViolation.
--     Acteur d'un tick refusé : à sa dernière position VALIDÉE (prev = pos) ; le balayage d'un tick
--     valide part toujours de la dernière position validée (jamais d'une position signalée) ; la
--     référence d'une apparition / d'un déplacement serveur est lue à l'instant du déplacement
--   * pose le crochet EconomyService.setLineBanker(forceParade) dans Init
-- GDD : §4.5-§4.8, §4.15.2, §4.15.4, §4.16, §4.17, §12.1, §12.3, §12.4, §12.7, §14.3.
-- Dépendances : TOUS les services précédents, Util/MoveCheck, Logic/*, Config/*, Signals,
-- Util/Notify, Util/RateLimit, Util/Analytics, Shared/Util/Clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Nebbies = require(Shared.Config.Nebbies)
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Logic.Formulas)
local PathCodec = require(Shared.Logic.PathCodec)
local SnipRules = require(Shared.Logic.SnipRules)
local Trail = require(Shared.Logic.Trail)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Validate = require(Shared.Util.Validate)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Analytics = require(Server.Util.Analytics)
local MoveCheck = require(Server.Util.MoveCheck)
local Notify = require(Server.Util.Notify)
local RateLimit = require(Server.Util.RateLimit)

local Services = script.Parent
local DataService = require(Services.DataService)
local NestService = require(Services.NestService)
local EconomyService = require(Services.EconomyService)
local AtlasService = require(Services.AtlasService)
local SpawnService = require(Services.SpawnService)
local EventService = require(Services.EventService)
local CrewService = require(Services.CrewService)
local QuestService = require(Services.QuestService)
local LeaderboardService = require(Services.LeaderboardService)

local CongaService = {}

local Conga = Balance.Conga
local Catch = Balance.Catch
local Snip = Balance.Snip
local NetCfg = Balance.Net

local STEP = Balance.Tick.Step
local SLOT_COUNT = Zones.Nests.Count
local TICK_MODULO = 65536
local WARN_INTERVAL = 10 -- s entre deux avertissements d'une même étape (docs §6)
-- Taille maximale d'un buffer PathStream : la limite moteur d'une charge d'UnreliableRemoteEvent
-- (900 octets) porte sur la charge SÉRIALISÉE (en-têtes de l'argument compris) ; au-delà, le
-- message est jeté sans erreur. Marge de sécurité (à 12 joueurs, un message fait ≈ 220 o : au plus
-- 1 miette nouvelle + 2 répétées par joueur et par tick).
local UNRELIABLE_MAX_BYTES = 800
local SWEEP_SAMPLE = 1 -- studs entre deux échantillons du balayage d'une porte de parade
local MAX_SWEEP_SAMPLES = 128
local ACTIVE_PUSH_INTERVAL = 1 -- joueurs actifs poussés au plus une fois par seconde
local HOUR = 3600 -- fenêtre du plafond de captures (Catch.MaxPerHour)
local INPUT_TOUCH = 1
local INPUT_DEFAULT = 2 -- clavier-souris tant que le client n'a rien déclaré (aucune aide)
local INPUT_KINDS = 3
local POST_SNIP_QUIT_WINDOW = 60 -- analytique PostSnipQuit (GDD §14.3)
local WALKSPEED_EPSILON = 1e-3
local CATCH_COMPACT = 256 -- compactage de la file des captures récentes

-- Raretés nommées (clés de Config/Nebbies)
local function rarityId(key: string): number
	for id, def in Nebbies.Rarities do
		if def.key == key then
			return id
		end
	end
	error(`[CongaService] rareté inconnue : {key}`)
end
local MYTHIC = rarityId("mythic")

-- ---------------------------------------------------------------------------------------------
-- État
-- ---------------------------------------------------------------------------------------------

type PlayerState = {
	player: Player,
	userId: number,
	slot: number, -- 0 = pas de Nid (aucun gameplay)
	trail: Trail.Trail, -- miettes d'autorité (pas 0,5)
	netTrail: Trail.Trail?, -- miettes réseau (pas 1,0), numérotées par slot
	netSentSeq: number, -- dernier numéro diffusé par PathStream
	stillTicks: number, -- renvois des derniers points après l'arrêt
	nodes: { Types.LineNode },
	nodeCache: { Vector3 }?,
	prev: Vector3?, -- dernière position VALIDÉE (départ du balayage des coupes, vols, portes)
	resetPending: boolean, -- apparition ou déplacement serveur à prendre en compte
	resetPos: Vector3?, -- position posée par le serveur, lue à l'instant du déplacement
	character: Model?,
	deathHandled: boolean,
	conns: { RBXScriptConnection },
	charConns: { RBXScriptConnection },
	dashUntil: number,
	dashReadyAt: number,
	snipCooldownUntil: number,
	pairCooldowns: { [number]: number }, -- UserId de la victime → fin de recharge
	immuneUntil: number,
	recent: { number }, -- coupes subies (fenêtre glissante)
	secondWindUntil: number,
	rushUntil: number,
	catchTimes: { number },
	catchHead: number,
	catchSuspendedUntil: number,
	fullWarnAt: number,
	inputType: number,
	escortAcc: number,
	activeSec: { number }, -- seaux d'activité (1 par seconde, fenêtre ActiveWindow)
	activeDist: { number },
	lastSnippedAt: number,
	lineChanged: boolean,
	walkSpeed: number,
	unstable: boolean,
	needsSnapshot: boolean,
	snapshotSent: boolean,
}

type SlotState = {
	owner: number, -- UserId (0 = libre)
	holder: PlayerState?,
	ver: number,
	nextSeq: number, -- prochain numéro de miette réseau (contigu entre propriétaires)
}

type Victim = {
	actor: Types.Actor,
	state: PlayerState,
	guard: number,
	party: SnipRules.Party,
	escort: { Vector3 }?,
	bounds: { number }?, -- boîte XZ de la partie coupable { minX, maxX, minZ, maxZ } (une fois par tick)
}

type Sweep = { minX: number, maxX: number, minZ: number, maxZ: number }

type Remotes = {
	LineEvent: RemoteEvent,
	SnipEvent: RemoteEvent,
	PathStream: UnreliableRemoteEvent,
	PathSnapshot: RemoteEvent,
	WorldSnapshot: RemoteEvent,
	Dash: RemoteEvent,
	SetInputType: RemoteEvent,
	RequestWorld: RemoteEvent,
	RequestPath: RemoteEvent,
}

local states: { [Player]: PlayerState } = {}
local slots: { SlotState } = {}
for slot = 1, SLOT_COUNT do
	slots[slot] = { owner = 0, holder = nil, ver = 0, nextSeq = 1 }
end

local pendingOps: { Types.LineOp } = {}
local pendingSnips: { Types.SnipEventPayload } = {}
local tickId = 0
local lastActivePush = -math.huge
local remotes: Remotes? = nil
local warnedAt: { [string]: number } = {}
local heartbeat: RBXScriptConnection? = nil -- l'unique connexion Heartbeat du serveur
local accumulator = 0
local rng = Random.new()

-- ---------------------------------------------------------------------------------------------
-- Appels protégés vers les autres services
-- ---------------------------------------------------------------------------------------------

local function report(label: string, err: any)
	local now = Clock.now()
	local last = warnedAt[label]
	if last == nil or now - last >= WARN_INTERVAL or now < last then
		warnedAt[label] = now
		warn("[CongaService] " .. label .. " :", err)
	end
end

-- Appelle fn(...) ; en cas d'erreur ou de résultat d'un autre type que `default`, rend `default`
local function safe<T>(label: string, default: T, fn: any, ...: any): T
	local ok, result = pcall(fn, ...)
	if not ok then
		report(label, result)
		return default
	end
	if result == nil or (default ~= nil and type(result) ~= type(default)) then
		return default
	end
	return result
end

local function call(label: string, fn: any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		report(label, err)
	end
end

local function getRemotes(): Remotes
	local r = remotes
	if r == nil then
		r = {
			LineEvent = Net.event("LineEvent"),
			SnipEvent = Net.event("SnipEvent"),
			PathStream = Net.unreliable("PathStream"),
			PathSnapshot = Net.event("PathSnapshot"),
			WorldSnapshot = Net.event("WorldSnapshot"),
			Dash = Net.event("Dash"),
			SetInputType = Net.event("SetInputType"),
			RequestWorld = Net.event("RequestWorld"),
			RequestPath = Net.event("RequestPath"),
		}
		remotes = r
	end
	return r :: Remotes
end

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function validSlot(slot: any): boolean
	return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= SLOT_COUNT
end

local function distXZ(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function upgradeLevel(data: { [string]: any }?, track: string): number
	if data == nil then
		return 0
	end
	local upgrades = data.upgrades
	if type(upgrades) ~= "table" then
		return 0
	end
	local v = upgrades[track]
	return if type(v) == "number" then v else 0
end

local function supernovasOf(data: { [string]: any }?): number
	local v = if data then data.supernovas else nil
	return if type(v) == "number" then v else 0
end

local function capacityOf(state: PlayerState): number
	return Formulas.congaCapacity(upgradeLevel(DataService.get(state.player), "conga"))
end

local function guardOf(state: PlayerState): number
	return Formulas.guardLinks(upgradeLevel(DataService.get(state.player), "guard"))
end

local function characterParts(state: PlayerState): (BasePart?, Humanoid?)
	local character = state.player.Character
	if character == nil or character.Parent == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

-- Positions serveur des nœuds 1 … n (abscisse HeadGap + (i − 1) × Spacing sur trail)
local function nodePositionsOf(state: PlayerState): { Vector3 }
	local cache = state.nodeCache
	local n = #state.nodes
	if cache and #cache == n then
		return cache
	end
	local positions = state.trail:sample(n, Conga.Spacing, Conga.HeadGap)
	state.nodeCache = positions
	return positions
end

local function codesOf(state: PlayerState): { Types.NebbyCode }
	local codes = table.create(#state.nodes)
	for i, node in state.nodes do
		codes[i] = node.code
	end
	return codes
end

local function nextVer(slot: number): number
	local s = slots[slot]
	s.ver += 1
	return s.ver
end

local function queueOp(op: Types.LineOp)
	table.insert(pendingOps, op)
end

local function mutateFlags(player: Player, fn: ({ strikes: number, lbBanned: boolean }) -> ())
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local flags = data.flags
	if type(flags) ~= "table" then
		flags = { strikes = 0, lbBanned = false }
		data.flags = flags
	end
	if type(flags.strikes) ~= "number" then
		flags.strikes = 0
	end
	fn(flags)
	DataService.markDirty(player, "flags")
end

local function safeMoment(state: PlayerState)
	call("onSafeMoment", QuestService.onSafeMoment, state.player)
end

-- ---------------------------------------------------------------------------------------------
-- Slots (une file par Nid) et propriétaires
-- ---------------------------------------------------------------------------------------------

-- Détache toute la file en Nebbies libres (positions actuelles des nœuds) ; rend les apparitions
local function detachAll(state: PlayerState, now: number, prioritySlot: number?): { Types.WildSpawn }
	if #state.nodes == 0 then
		return {}
	end
	local positions = nodePositionsOf(state)
	local codes = codesOf(state)
	table.clear(state.nodes)
	state.nodeCache = nil
	state.lineChanged = true
	local opts: SpawnService.LooseOptions = { prioritySlot = prioritySlot, silent = true }
	return safe("spawnLoose", {}, SpawnService.spawnLoose, codes, positions, now, opts)
end

local function clearLine(state: PlayerState, reason: "death" | "leave" | "reset" | "supernova", now: number)
	local slot = state.slot
	if slot == 0 or #state.nodes == 0 then
		return
	end
	local loose = detachAll(state, now, if reason == "death" then slot else nil)
	local op: Types.LineClearOp =
		{ op = "clear", slot = slot, ver = nextVer(slot), reason = reason, loose = loose }
	queueOp(op)
end

local function unbindSlot(state: PlayerState)
	local slot = state.slot
	if slot == 0 then
		return
	end
	local s = slots[slot]
	local net = state.netTrail
	if net then
		s.nextSeq = math.max(s.nextSeq, net:lastSeq() + 1)
	end
	s.owner = 0
	s.holder = nil
	s.ver = 0
	local op: Types.LineOwnerOp = { op = "owner", slot = slot, ver = 0, userId = 0 }
	queueOp(op)
	state.slot = 0
	state.netTrail = nil
end

local function bindSlot(state: PlayerState, slot: number)
	if slot == state.slot then
		return
	end
	if state.slot ~= 0 then
		clearLine(state, "reset", Clock.now())
		unbindSlot(state)
	end
	if not validSlot(slot) then
		return
	end
	local s = slots[slot]
	if s.owner ~= 0 and s.owner ~= state.userId then
		return -- Nid encore tenu : nouvel essai au prochain pas
	end
	s.owner = state.userId
	s.holder = state
	s.ver = 0
	state.slot = slot
	state.netTrail = Trail.new(Conga.TrailLength, Conga.NetMinStep, s.nextSeq)
	state.netSentSeq = s.nextSeq - 1
	state.stillTicks = NetCfg.StillResendTicks
	state.lineChanged = true
	local op: Types.LineOwnerOp = { op = "owner", slot = slot, ver = 0, userId = state.userId }
	queueOp(op)
end

-- ---------------------------------------------------------------------------------------------
-- Joueurs : arrivée, personnage, mort, départ
-- ---------------------------------------------------------------------------------------------

local function newState(player: Player): PlayerState
	local buckets = Balance.Spawn.ActiveWindow
	local activeSec = table.create(buckets, -math.huge)
	local activeDist = table.create(buckets, 0)
	return {
		player = player,
		userId = player.UserId,
		slot = 0,
		trail = Trail.new(Conga.TrailLength, Conga.TrailMinStep),
		netTrail = nil,
		netSentSeq = 0,
		stillTicks = NetCfg.StillResendTicks,
		nodes = {},
		nodeCache = nil,
		prev = nil,
		resetPending = true,
		resetPos = nil,
		character = nil,
		deathHandled = false,
		conns = {},
		charConns = {},
		dashUntil = -math.huge,
		dashReadyAt = 0,
		snipCooldownUntil = -math.huge,
		pairCooldowns = {},
		immuneUntil = -math.huge,
		recent = {},
		secondWindUntil = -math.huge,
		rushUntil = -math.huge,
		catchTimes = {},
		catchHead = 1,
		catchSuspendedUntil = -math.huge,
		fullWarnAt = -math.huge,
		inputType = INPUT_DEFAULT,
		escortAcc = 0,
		activeSec = activeSec,
		activeDist = activeDist,
		lastSnippedAt = -math.huge,
		lineChanged = false,
		walkSpeed = -1,
		unstable = false,
		needsSnapshot = true,
		snapshotSent = false,
	}
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, c in list do
		c:Disconnect()
	end
	table.clear(list)
end

-- Mort ou réinitialisation : la file se détache (priorité au propriétaire, sans Second Souffle)
local function onDeath(state: PlayerState)
	if state.deathHandled then
		return
	end
	state.deathHandled = true
	local hadLine = #state.nodes > 0
	clearLine(state, "death", Clock.now())
	if hadLine then
		safeMoment(state)
	end
	call("dropComet", EventService.dropComet, state.player)
end

-- Nouvelle référence MoveCheck au prochain pas. La position est lue TOUT DE SUITE (le serveur vient
-- de placer le personnage) : au pas suivant, un paquet du client d'avant le déplacement pourrait
-- l'avoir déjà écrasée, et la référence serait fausse.
local function requestReset(state: PlayerState, character: Model?)
	state.resetPending = true
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	state.resetPos = if root and root:IsA("BasePart") then root.Position else nil
end

local function bindCharacter(state: PlayerState, character: Model)
	disconnectAll(state.charConns)
	state.character = character
	state.deathHandled = false
	requestReset(state, character)
	state.prev = nil
	state.walkSpeed = -1
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(
			state.charConns,
			humanoid.Died:Connect(function()
				if state.character == character then
					onDeath(state)
				end
			end)
		)
	end
end

local function onPlayerAdded(player: Player)
	if states[player] or player.Parent == nil then
		return
	end
	local state = newState(player)
	states[player] = state
	-- attributs lus par le HUD (docs §3.3) : valeurs neutres dès l'arrivée
	player:SetAttribute("DashReadyAt", state.dashReadyAt)
	player:SetAttribute("ImmuneUntil", 0)
	player:SetAttribute("Unstable", false)
	player:SetAttribute("InputType", state.inputType)
	bindSlot(state, safe("slotOf", 0, NestService.slotOf, player))
	table.insert(
		state.conns,
		player.CharacterAdded:Connect(function(character: Model)
			if states[player] == state then
				bindCharacter(state, character)
			end
		end)
	)
	table.insert(
		state.conns,
		player.CharacterRemoving:Connect(function(character: Model)
			if states[player] == state and state.character == character then
				onDeath(state)
			end
		end)
	)
	local character = player.Character
	if character then
		bindCharacter(state, character)
	end
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if state == nil then
		return
	end
	local now = Clock.now()
	clearLine(state, "leave", now)
	unbindSlot(state)
	call("dropComet", EventService.dropComet, player)
	if now - state.lastSnippedAt < POST_SNIP_QUIT_WINDOW then
		Analytics.event(player, "PostSnipQuit", math.floor(now - state.lastSnippedAt))
	end
	local violations = MoveCheck.violations(player)
	if violations > 0 then
		Analytics.event(player, "MoveViolation", violations)
	end
	MoveCheck.clear(player)
	disconnectAll(state.charConns)
	disconnectAll(state.conns)
	states[player] = nil
	Signals.LineChanged:Fire(player, 0)
end

-- ---------------------------------------------------------------------------------------------
-- WalkSpeed
-- ---------------------------------------------------------------------------------------------

local function walkSpeedOf(state: PlayerState, now: number): number
	local data = DataService.get(state.player)
	return Formulas.walkSpeed({
		stride = upgradeLevel(data, "stride"),
		n = #state.nodes,
		guard = Formulas.guardLinks(upgradeLevel(data, "guard")),
		carrier = safe("isCarrier", false, EventService.isCarrier, state.player),
		dashing = now < state.dashUntil,
		secondWind = now < state.secondWindUntil,
	})
end

local function applyWalkSpeed(state: PlayerState, humanoid: Humanoid, speed: number, now: number)
	if state.walkSpeed == speed and math.abs(humanoid.WalkSpeed - speed) <= WALKSPEED_EPSILON then
		return
	end
	humanoid.WalkSpeed = speed
	state.walkSpeed = speed
	MoveCheck.noteSpeed(state.player, speed, now)
end

-- ---------------------------------------------------------------------------------------------
-- Activité (joueur actif : ≥ 4 studs parcourus pendant les 60 dernières s)
-- ---------------------------------------------------------------------------------------------

local function noteActivity(state: PlayerState, distance: number, now: number)
	if not (distance > 0) then
		return
	end
	local sec = math.floor(now)
	local idx = sec % #state.activeSec + 1
	if state.activeSec[idx] ~= sec then
		state.activeSec[idx] = sec
		state.activeDist[idx] = 0
	end
	state.activeDist[idx] += distance
end

local function activeAt(state: PlayerState, now: number): boolean
	local window = Balance.Spawn.ActiveWindow
	local total = 0
	for i, sec in state.activeSec do
		if sec > now - window and sec <= now then
			total += state.activeDist[i]
		end
	end
	return total >= Balance.Spawn.ActiveDistance
end

local function activeCountAt(now: number): number
	local n = 0
	for _, state in states do
		if state.slot ~= 0 and activeAt(state, now) then
			n += 1
		end
	end
	return n
end

-- ---------------------------------------------------------------------------------------------
-- Étape 2 : acteurs et miettes
-- ---------------------------------------------------------------------------------------------

local function onRewind(state: PlayerState, root: BasePart, back: Vector3, now: number, counted: boolean)
	local player = state.player
	local character = state.character
	if character then
		local rotation = root.CFrame - root.CFrame.Position
		character:PivotTo(CFrame.new(back) * rotation)
	end
	if counted then
		local recent = MoveCheck.recentRewinds(player, now)
		mutateFlags(player, function(flags)
			flags.strikes += 1
			if recent >= Balance.MoveCheck.StrikesForBan then
				flags.lbBanned = true
			end
		end)
	end
	if not state.unstable then
		state.unstable = true
		player:SetAttribute("Unstable", true)
		Notify.feedback(player, "feedback.unstable", nil, "info")
	end
	Signals.MoveViolation:Fire(player, MoveCheck.violations(player))
end

local function buildActors(now: number): { Types.Actor }
	local actors: { Types.Actor } = {}
	for player, state in states do
		-- le Nid peut être attribué (ou changer) après l'arrivée
		local slot = safe("slotOf", state.slot, NestService.slotOf, player)
		if slot ~= state.slot then
			bindSlot(state, slot)
		end
		state.nodeCache = nil
		local root, humanoid = characterParts(state)
		if humanoid and humanoid.Health <= 0 then
			onDeath(state) -- Died manqué : rattrapage
		end
		if root == nil or humanoid == nil or humanoid.Health <= 0 then
			state.prev = nil
			continue
		end
		local pos = root.Position
		if state.resetPending then
			state.resetPending = false
			local anchor = state.resetPos
			state.resetPos = nil
			if anchor == nil or anchor ~= anchor then
				anchor = pos
			end
			MoveCheck.reset(player, anchor, now)
			state.trail:reset(anchor)
			local net = state.netTrail
			if net then
				net:reset(anchor)
			end
			state.prev = anchor
			state.walkSpeed = -1
		end
		-- départ du balayage : la dernière position VALIDÉE (jamais une position signalée, sinon une
		-- téléportation aller-retour balaierait tout ce qui sépare les deux points)
		local prev = state.prev or pos
		local rewindsBefore = MoveCheck.recentRewinds(player, now)
		local verdict, back = MoveCheck.step(player, pos, STEP, now, WorldLayout.groundY(pos.X, pos.Z))
		if verdict == "rewind" and back ~= nil then
			onRewind(state, root, back, now, MoveCheck.recentRewinds(player, now) > rewindsBefore)
		end
		if verdict == "ok" then
			state.trail:push(pos)
			local net = state.netTrail
			if net then
				net:push(pos)
			end
			noteActivity(state, distXZ(prev, pos), now)
		else
			-- tick refusé (signalé ou ramené) : l'acteur reste à sa dernière position validée, pour
			-- tous les services (proximité de la Comète, escorte…) ; il ne peut de toute façon pas agir
			pos = MoveCheck.lastValid(player) or prev
			prev = pos
		end
		state.prev = pos
		if state.slot ~= 0 and DataService.get(player) ~= nil then
			table.insert(actors, {
				player = player,
				userId = state.userId,
				slot = state.slot,
				pos = pos,
				prev = prev,
				valid = verdict == "ok" and not MoveCheck.isRestricted(player, now),
				zen = safe("isZen", false, NestService.isZen, player),
				crewId = safe("crewOf", 0, CrewService.crewOf, player),
				rookie = safe("isRookie", false, QuestService.isRookie, player),
				touch = state.inputType == INPUT_TOUCH,
			})
		end
	end
	-- ordre de traitement tiré au hasard à chaque tick (égalités des captures, ordre des coupes)
	for i = #actors, 2, -1 do
		local j = rng:NextInteger(1, i)
		actors[i], actors[j] = actors[j], actors[i]
	end
	return actors
end

-- ---------------------------------------------------------------------------------------------
-- Étape 5 : captures
-- ---------------------------------------------------------------------------------------------

type Claim = { actor: number, wild: Types.WildNebby, d2: number }
type AddEntry = { state: PlayerState, op: Types.LineAddOp, recovered: boolean }

local function catchable(actor: Types.Actor, wild: Types.WildNebby, now: number): (boolean, number)
	local p = SpawnService.positionOf(wild, now)
	if math.abs(p.Y - actor.pos.Y) > Catch.MaxDy then
		return false, 0
	end
	if not SpawnService.canCatch(actor.player, actor.slot, wild, now) then
		return false, 0
	end
	local dx, dz = p.X - actor.pos.X, p.Z - actor.pos.Z
	return true, dx * dx + dz * dz
end

-- Plafond de 1 500 captures par heure glissante (au-delà : 5 min sans capture, exclusion des
-- classements)
local function recordCatch(state: PlayerState, now: number)
	local times = state.catchTimes
	table.insert(times, now)
	while state.catchHead <= #times and times[state.catchHead] <= now - HOUR do
		state.catchHead += 1
	end
	if state.catchHead > CATCH_COMPACT then
		local kept = table.move(times, state.catchHead, #times, 1, {})
		state.catchTimes = kept
		state.catchHead = 1
		times = kept
	end
	if #times - state.catchHead + 1 >= Catch.MaxPerHour then
		state.catchSuspendedUntil = now + Catch.SuspendSeconds
		state.catchTimes = {}
		state.catchHead = 1
		mutateFlags(state.player, function(flags)
			flags.lbBanned = true
		end)
	end
end

local function onCaught(state: PlayerState, wild: Types.WildNebby, entry: AddEntry, now: number)
	local player = state.player
	table.insert(state.nodes, { code = wild.code, at = now })
	state.nodeCache = nil
	state.lineChanged = true
	table.insert(entry.op.codes, wild.code)
	table.insert(entry.op.ids, wild.id)
	local s = Nebbies.unpack(wild.code)
	local rarity = Nebbies.rarityOf(s)
	local recovered = wild.loose and wild.prioritySlot ~= 0 and wild.prioritySlot == state.slot
	if recovered then
		entry.recovered = true
	end
	local info: Types.CatchInfo = {
		code = wild.code,
		rarity = rarity,
		zone = wild.zone,
		loose = wild.loose,
		recovered = recovered,
		personal = wild.onlyFor ~= 0,
		n = #state.nodes,
	}
	Signals.Caught:Fire(player, info)
	local def = Nebbies.Rarities[rarity]
	if def and def.banner then
		Notify.banner(
			if rarity >= MYTHIC then "mythicCatch" else "legendaryCatch",
			{ userId = state.userId, name = player.DisplayName, code = wild.code },
			player
		)
	end
	recordCatch(state, now)
end

local function stepCaptures(actors: { Types.Actor }, now: number)
	local claims: { Claim } = {}
	for i, actor in actors do
		local state = states[actor.player]
		if actor.valid and state and now >= state.catchSuspendedUntil then
			local data = DataService.get(actor.player)
			local radius = Formulas.lureRadius(upgradeLevel(data, "lure"), now < state.rushUntil)
				+ Catch.LatencyTolerance
			local full = #state.nodes >= capacityOf(state)
			if not full or now >= state.fullWarnAt + Catch.FullWarnInterval then
				local candidates = safe("query", {}, SpawnService.query, actor.pos, radius, now, actor.player)
				for _, wild in candidates do
					local ok, d2 = catchable(actor, wild, now)
					if ok then
						if full then
							-- file pleine : le Nebby reste là, le HUD clignote « PLEINE »
							state.fullWarnAt = now
							Notify.feedback(actor.player, "feedback.lineFull", nil, "warning")
							break
						end
						table.insert(claims, { actor = i, wild = wild, d2 = d2 })
					end
				end
			end
		end
	end
	if #claims == 0 then
		return
	end
	-- le plus proche gagne ; égalité → ordre des acteurs (mélangé à chaque tick)
	table.sort(claims, function(a, b)
		if a.d2 ~= b.d2 then
			return a.d2 < b.d2
		end
		if a.actor ~= b.actor then
			return a.actor < b.actor
		end
		return a.wild.id < b.wild.id
	end)
	local taken: { [number]: boolean } = {}
	local entries: { AddEntry } = {}
	local entryOf: { [PlayerState]: AddEntry } = {}
	for _, claim in claims do
		local wild = claim.wild
		if not taken[wild.id] then
			local actor = actors[claim.actor]
			local state = states[actor.player]
			if state and #state.nodes < capacityOf(state) and now >= state.catchSuspendedUntil then
				taken[wild.id] = true
				local got =
					safe("consume", nil :: Types.WildNebby?, SpawnService.consume, wild.id, actor.player)
				if got ~= nil and state.slot ~= 0 then
					local entry = entryOf[state]
					if entry == nil then
						-- l'op « add » (et sa version) est réservée à la première capture du tick :
						-- une op émise par un abonné de Signals.Caught passe après elle
						local op: Types.LineAddOp =
							{ op = "add", slot = state.slot, ver = nextVer(state.slot), codes = {}, ids = {} }
						queueOp(op)
						entry = { state = state, op = op, recovered = false }
						entryOf[state] = entry
						table.insert(entries, entry)
					end
					onCaught(state, got, entry, now)
				end
			end
		end
	end
	for _, entry in entries do
		if entry.recovered then
			Notify.feedback(entry.state.player, "feedback.recovered", nil, "success")
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Étape 7 : coupes
-- ---------------------------------------------------------------------------------------------

local function escortOf(victim: Victim, byPlayer: { [Player]: Types.Actor }): { Vector3 }
	local list = victim.escort
	if list ~= nil then
		return list
	end
	local out: { Vector3 } = {}
	local escorters = safe("escortersOf", {}, CrewService.escortersOf, victim.actor.player)
	for _, p in escorters do
		local a = byPlayer[p]
		if a and p ~= victim.actor.player then
			table.insert(out, a.pos)
		end
	end
	victim.escort = out
	return out
end

local function applyCut(
	victim: Victim,
	snipper: Types.Actor?,
	k: number,
	point: Vector3,
	now: number,
	wispId: number?
)
	local vstate = victim.state
	local victimPlayer = vstate.player
	local slot = vstate.slot
	local n = #vstate.nodes
	local c = SnipRules.cutFrom(k, n)
	if c > n or c < 1 then
		return
	end
	local positions = nodePositionsOf(vstate)
	local codes: { number } = {}
	local from: { Vector3 } = {}
	for i = c, n do
		table.insert(codes, vstate.nodes[i].code)
		table.insert(from, positions[i])
	end
	for i = n, c, -1 do
		vstate.nodes[i] = nil
	end
	vstate.nodeCache = nil
	vstate.lineChanged = true
	-- la coupe prend sa version tout de suite (avant tout appel externe)
	local ver = nextVer(slot)
	local count = #codes
	local opts: SpawnService.LooseOptions = { prioritySlot = slot, silent = true }
	local loose = safe("spawnLoose", {}, SpawnService.spawnLoose, codes, from, now, opts)
	local looseIds: { number } = table.create(#loose)
	for i, spawn in loose do
		looseIds[i] = spawn.id
	end
	-- victime : immunité (8 s, plafond par minute), Second Souffle
	vstate.immuneUntil, vstate.recent = SnipRules.applyCut(now, vstate.immuneUntil, vstate.recent)
	victimPlayer:SetAttribute("ImmuneUntil", vstate.immuneUntil)
	vstate.secondWindUntil = now + Balance.Speed.SecondWindDuration
	vstate.lastSnippedAt = now
	local dust = 0
	local snipperSlot = 0
	local snipperPlayer: Player? = nil
	if snipper ~= nil then
		local sstate = states[snipper.player]
		snipperPlayer = snipper.player
		snipperSlot = snipper.slot
		if sstate then
			sstate.snipCooldownUntil = now + Snip.SnipperCooldown
			sstate.pairCooldowns[vstate.userId] = now + Snip.PairCooldown
			sstate.rushUntil = now + Snip.RushDuration
		end
		if snipper.rookie then
			Notify.feedback(snipper.player, "feedback.rookieNoDust", nil, "info")
		else
			local wanted = Snip.RushDustPerNebby * count
			dust = math.max(
				0,
				math.floor(
					safe(
						"addStardustCapped",
						0,
						EconomyService.addStardustCapped,
						snipper.player,
						wanted,
						"snipDust",
						"Snip"
					)
				)
			)
			if dust <= 0 and wanted > 0 then
				Notify.feedback(snipper.player, "feedback.capReached", nil, "info")
			end
		end
		Notify.feedback(snipper.player, "feedback.snipDealt", { count = count, dust = dust }, "reward")
		Analytics.event(snipper.player, "SnipDealt", count)
		Analytics.event(snipper.player, "SnipByInput", if sstate then sstate.inputType else INPUT_DEFAULT)
		Analytics.event(victimPlayer, "SnipReceived", count)
	else
		call("onWispSnip", EventService.onWispSnip, wispId or 0, victimPlayer, count)
		Analytics.event(victimPlayer, "WispSnip", count)
	end
	Notify.feedback(victimPlayer, "feedback.snipped", nil, "warning")
	local payload: Types.SnipEventPayload = {
		snipperSlot = snipperSlot,
		victimSlot = slot,
		ver = ver,
		cutIndex = c,
		count = count,
		looseIds = looseIds,
		loose = loose,
		byWisp = snipper == nil,
		wispId = wispId,
		x = point.X,
		y = point.Y,
		z = point.Z,
		dust = dust,
	}
	table.insert(pendingSnips, payload)
	local info: Types.SnipInfo = {
		snipper = snipperPlayer,
		victim = victimPlayer,
		count = count,
		byWisp = snipper == nil,
		rewarded = dust > 0,
		dust = dust,
	}
	Signals.Snipped:Fire(info)
	if #vstate.nodes == 0 then
		safeMoment(vstate)
	end
end

local function stepSnips(actors: { Types.Actor }, now: number, truce: boolean, disabled: boolean)
	local victims: { Victim } = {}
	local byPlayer: { [Player]: Types.Actor } = {}
	for _, actor in actors do
		byPlayer[actor.player] = actor
		local state = states[actor.player]
		if state then
			local guard = guardOf(state)
			if #state.nodes > guard then
				table.insert(victims, {
					actor = actor,
					state = state,
					guard = guard,
					party = {
						userId = actor.userId,
						crewId = actor.crewId,
						zen = actor.zen,
						rookie = actor.rookie,
					},
					escort = nil,
					bounds = nil,
				})
			end
		end
	end
	if #victims == 0 then
		return
	end
	-- Élagage large : boîte XZ des segments coupables (calculée une fois par victime et par tick ;
	-- une coupe ne fait que retirer des nœuds, la boîte reste une enveloppe valide)
	local function boundsOf(victim: Victim): { number }
		local b = victim.bounds
		if b ~= nil then
			return b
		end
		local nodes = nodePositionsOf(victim.state)
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		local function grow(p: Vector3)
			local x, z = p.X, p.Z
			if x < minX then
				minX = x
			end
			if x > maxX then
				maxX = x
			end
			if z < minZ then
				minZ = z
			end
			if z > maxZ then
				maxZ = z
			end
		end
		-- segment k = [nœud k − 1, nœud k] pour k > G : la boîte part du nœud G (la tête si G = 0)
		if victim.guard == 0 then
			grow(victim.state.trail:head() or victim.actor.pos)
		end
		for i = math.max(1, victim.guard), #nodes do
			grow(nodes[i])
		end
		b = { minX, maxX, minZ, maxZ }
		victim.bounds = b
		return b
	end
	local function sweepOf(from: Vector3, to: Vector3, radius: number): Sweep
		return {
			minX = math.min(from.X, to.X) - radius,
			maxX = math.max(from.X, to.X) + radius,
			minZ = math.min(from.Z, to.Z) - radius,
			maxZ = math.max(from.Z, to.Z) + radius,
		}
	end
	local function mayTouch(victim: Victim, sweep: Sweep): boolean
		local b = boundsOf(victim)
		return sweep.maxX >= b[1] and sweep.minX <= b[2] and sweep.maxZ >= b[3] and sweep.minZ <= b[4]
	end
	local function tryCut(victim: Victim, from: Vector3, to: Vector3, radius: number): (number?, Vector3?)
		local nodes = nodePositionsOf(victim.state)
		local escort = escortOf(victim, byPlayer)
		local isEscorted: ((number, Vector3) -> boolean)? = nil
		if #escort > 0 then
			isEscorted = function(_k: number, p: Vector3): boolean
				for _, e in escort do
					if distXZ(e, p) <= Balance.Crew.EscortRadius then
						return true
					end
				end
				return false
			end
		end
		return SnipRules.findCut({
			nodes = nodes,
			head = victim.state.trail:head() or victim.actor.pos,
			from = from,
			to = to,
			radius = radius,
			maxDy = Snip.MaxDy,
			guard = victim.guard,
			isEscorted = isEscorted,
			inHarbor = WorldLayout.inHarbor,
		})
	end
	-- joueurs × files des autres (un coupeur coupe au plus une file par tick : recharge 1,5 s)
	for _, snipper in actors do
		local sstate = states[snipper.player]
		if snipper.valid and sstate then
			local party: SnipRules.Party = {
				userId = snipper.userId,
				crewId = snipper.crewId,
				zen = snipper.zen,
				rookie = snipper.rookie,
			}
			local radius = SnipRules.radius(snipper.touch, false)
			local sweep = sweepOf(snipper.prev, snipper.pos, radius)
			for _, victim in victims do
				local vstate = victim.state
				if
					victim.actor.player ~= snipper.player
					and #vstate.nodes > victim.guard
					and mayTouch(victim, sweep)
				then
					local reason = SnipRules.blockReason({
						now = now,
						truce = truce,
						snipsDisabled = disabled,
						isWisp = false,
						snipper = party,
						victim = victim.party,
						snipperCooldownUntil = sstate.snipCooldownUntil,
						pairCooldownUntil = sstate.pairCooldowns[vstate.userId] or -math.huge,
						victimImmuneUntil = vstate.immuneUntil,
						victimRecent = vstate.recent,
						snipperFlagged = not snipper.valid,
					})
					if reason == nil then
						local k, point = tryCut(victim, snipper.prev, snipper.pos, radius)
						if k ~= nil and point ~= nil then
							applyCut(victim, snipper, k, point, now, nil)
							break
						end
					end
				end
			end
		end
	end
	-- Gloomwisps × files (rayon 2,5 ; pas de recharge ni de récompense)
	if truce then
		return -- les Gloomwisps s'effacent pendant la trêve
	end
	local sweeps = safe("wispSweeps", {}, EventService.wispSweeps, now)
	local wispRadius = SnipRules.radius(false, true)
	for _, sweep in sweeps do
		if type(sweep) == "table" and typeof(sweep.from) == "Vector3" and typeof(sweep.to) == "Vector3" then
			local box = sweepOf(sweep.from, sweep.to, wispRadius)
			for _, victim in victims do
				local vstate = victim.state
				if #vstate.nodes > victim.guard and mayTouch(victim, box) then
					local reason = SnipRules.blockReason({
						now = now,
						truce = truce,
						snipsDisabled = disabled,
						isWisp = true,
						snipper = nil,
						victim = victim.party,
						snipperCooldownUntil = -math.huge,
						pairCooldownUntil = -math.huge,
						victimImmuneUntil = vstate.immuneUntil,
						victimRecent = vstate.recent,
						snipperFlagged = false,
					})
					if reason == nil then
						local k, point = tryCut(victim, sweep.from, sweep.to, wispRadius)
						if k ~= nil and point ~= nil then
							applyCut(
								victim,
								nil,
								k,
								point,
								now,
								if type(sweep.id) == "number" then sweep.id else 0
							)
						end
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Étape 9 : parades
-- ---------------------------------------------------------------------------------------------

-- Nouvelles entrées d'Atlas qu'apportera cette parade (espèce × forme pas encore enregistrées)
local function newAtlasEntries(data: { [string]: any }, codes: { number }): number
	local atlas = data.atlas
	if type(atlas) ~= "table" then
		return 0
	end
	local seen: { [number]: boolean } = {}
	local count = 0
	for _, code in codes do
		local s, f = Nebbies.unpack(code)
		if Nebbies.isSpeciesEnabled(s) and Nebbies.isFormEnabled(f) then
			local index = Nebbies.atlasIndex(s, f)
			if not seen[index] and not Nebbies.testBit(atlas, index) then
				seen[index] = true
				count += 1
			end
		end
	end
	return count
end

local function parade(state: PlayerState, atBeacon: boolean, forced: boolean): number
	local player = state.player
	local slot = state.slot
	local n = #state.nodes
	if n == 0 or slot == 0 then
		return 0
	end
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	local codes = codesOf(state)
	local okGlow, rawGlow = pcall(EconomyService.paradeGlow, player, codes, atBeacon)
	if not okGlow or type(rawGlow) ~= "number" or rawGlow ~= rawGlow then
		report("paradeGlow", rawGlow)
		return 0 -- la file est conservée : rien n'est perdu
	end
	local glow = math.max(0, math.floor(rawGlow))
	local newEntries = newAtlasEntries(data, codes)
	local okAdd, err =
		pcall(EconomyService.addGlow, player, glow, if atBeacon then "ParadeBeacon" else "Parade", "Gameplay")
	if not okAdd then
		report("addGlow", err)
		return 0
	end
	-- à partir d'ici la file est encaissée
	local uids = safe("addNebbies", {}, AtlasService.addNebbies, player, codes, "parade")
	if atBeacon then
		call("onBeaconParade", EventService.onBeaconParade, player, n)
	end
	table.clear(state.nodes)
	state.nodeCache = nil
	state.lineChanged = true
	local zen = safe("isZen", false, NestService.isZen, player)
	local bonus = Formulas.congaBonus(n, zen)
	local op: Types.LineBankOp = {
		op = "bank",
		slot = slot,
		ver = nextVer(slot),
		count = n,
		glow = glow,
		bonus = bonus,
		atBeacon = atBeacon,
		newEntries = newEntries,
	}
	queueOp(op)
	local rate = data.idleRate
	local idleSeconds = if type(rate) == "number" and rate > 0 and rate == rate then glow / rate else 0
	local info: Types.ParadeInfo = {
		count = n,
		codes = codes,
		uids = uids,
		glow = glow,
		bonus = bonus,
		atBeacon = atBeacon,
		idleSeconds = idleSeconds,
		newEntries = newEntries,
		forced = forced,
	}
	Signals.Parade:Fire(player, info)
	if n >= Balance.Parade.MegaParade then
		Notify.banner("megaParade", { userId = state.userId, name = player.DisplayName, n = n }, player)
	end
	safeMoment(state)
	Analytics.event(player, "ParadeLength", n)
	return glow
end

-- slot > 0 : boîte de la porte de ce Nid ; slot = 0 : anneau de la Balise
local function insideParadeZone(slot: number, p: Vector3): boolean
	if slot > 0 then
		return WorldLayout.inGateBox(slot, p)
	end
	return WorldLayout.inBeaconRing(p)
end

-- Le déplacement VALIDÉ prev → pos passe-t-il dans la zone ? À 10 Hz, avec la gigue du réseau, un
-- pas de plus de 4 studs (Dash, paquets groupés) peut enjamber la boîte de porte, profonde de 4 :
-- le joueur a traversé sa porte à l'écran, la parade doit avoir lieu (« ce que tu vois compte »).
-- prev est exclu (déjà testé au tick précédent) ; la longueur est bornée par MoveCheck.
local function sweepEnters(prev: Vector3, pos: Vector3, slot: number): boolean
	if insideParadeZone(slot, pos) then
		return true
	end
	local delta = pos - prev
	local samples = math.min(math.ceil(delta.Magnitude / SWEEP_SAMPLE), MAX_SWEEP_SAMPLES)
	for i = 1, samples - 1 do
		if insideParadeZone(slot, prev + delta * (i / samples)) then
			return true
		end
	end
	return false
end

local function stepParades(actors: { Types.Actor }, beaconOpen: boolean)
	for _, actor in actors do
		local state = states[actor.player]
		if actor.valid and state and #state.nodes > 0 then
			local atGate = sweepEnters(actor.prev, actor.pos, actor.slot)
			local atBeacon = not atGate and beaconOpen and sweepEnters(actor.prev, actor.pos, 0)
			if atGate or atBeacon then
				parade(state, atBeacon, false)
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Étape 10 : entretien par joueur
-- ---------------------------------------------------------------------------------------------

-- Temps d'escorte : au moins un Nebby coupable d'un équipier à ≤ 7 studs, hors port sûr et trêve
local function stepEscort(actors: { Types.Actor }, truce: boolean)
	if truce then
		return
	end
	local crews: { [number]: { Types.Actor } } = {}
	for _, actor in actors do
		if actor.crewId ~= 0 then
			local list = crews[actor.crewId]
			if list == nil then
				list = {}
				crews[actor.crewId] = list
			end
			table.insert(list, actor)
		end
	end
	for _, members in crews do
		if #members >= 2 then
			for _, escorter in members do
				local estate = states[escorter.player]
				if escorter.valid and estate then
					local escorting = false
					for _, mate in members do
						local mstate = states[mate.player]
						if mate.player ~= escorter.player and mstate then
							local nodes = nodePositionsOf(mstate)
							for i = guardOf(mstate) + 1, #nodes do
								local p = nodes[i]
								if
									distXZ(p, escorter.pos) <= Balance.Crew.EscortRadius
									and not WorldLayout.inHarbor(p)
								then
									escorting = true
									break
								end
							end
						end
						if escorting then
							break
						end
					end
					if escorting then
						estate.escortAcc += STEP
						if estate.escortAcc >= 1 then
							local whole = math.floor(estate.escortAcc)
							estate.escortAcc -= whole
							Signals.EscortTime:Fire(escorter.player, whole)
						end
					end
				end
			end
		end
	end
end

local function stepMaintenance(actors: { Types.Actor }, now: number, truce: boolean)
	for player, state in states do
		local _, humanoid = characterParts(state)
		if humanoid and humanoid.Health > 0 then
			applyWalkSpeed(state, humanoid, walkSpeedOf(state, now), now)
		end
		if state.unstable and not MoveCheck.isRestricted(player, now) then
			state.unstable = false
			player:SetAttribute("Unstable", false)
		end
	end
	stepEscort(actors, truce)
	if now - lastActivePush >= ACTIVE_PUSH_INTERVAL or now < lastActivePush then
		lastActivePush = now
		local n = activeCountAt(now)
		call("SpawnService.setActivePlayers", SpawnService.setActivePlayers, n)
		call("EventService.setActivePlayers", EventService.setActivePlayers, n)
	end
	for player, state in states do
		if state.lineChanged then
			state.lineChanged = false
			Signals.LineChanged:Fire(player, #state.nodes)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Étape 12 : diffusion
-- ---------------------------------------------------------------------------------------------

-- Garde les MAX_RUNS runs les plus récents (un buffer ne peut pas en porter davantage)
local function capRuns(runs: { Types.PathEntry }): { Types.PathEntry }
	if #runs <= PathCodec.MAX_RUNS then
		return runs
	end
	return table.move(runs, #runs - PathCodec.MAX_RUNS + 1, #runs, 1, {})
end

-- Runs d'un slot pour PathStream : nouveaux points + PathRepeat derniers déjà envoyés ; un joueur
-- arrêté est renvoyé StillResendTicks fois puis n'est plus inclus
local function streamEntries(state: PlayerState): { Types.PathEntry }
	local net = state.netTrail
	if net == nil or state.slot == 0 then
		return {}
	end
	local last = net:lastSeq()
	local from: number
	if last > state.netSentSeq then
		from = state.netSentSeq - NetCfg.PathRepeat + 1
		state.stillTicks = 0
	elseif state.stillTicks < NetCfg.StillResendTicks then
		from = last - NetCfg.PathRepeat + 1
		state.stillTicks += 1
	else
		return {}
	end
	state.netSentSeq = last
	local first, points = net:since(from, NetCfg.PathStreamMaxPoints)
	if #points == 0 then
		return {}
	end
	return PathCodec.split(state.slot, first, points)
end

local function snapshotEntries(state: PlayerState): { Types.PathEntry }
	local net = state.netTrail
	if net == nil or state.slot == 0 then
		return {}
	end
	local first, points = net:since(net.firstSeq, NetCfg.SnapshotPoints)
	if #points == 0 then
		return {}
	end
	return PathCodec.split(state.slot, first, points)
end

local function broadcastPaths(r: Remotes)
	local runs: { Types.PathEntry } = {}
	local bytes = PathCodec.HEADER_BYTES
	local function send()
		if #runs > 0 then
			r.PathStream:FireAllClients(PathCodec.encode(tickId, runs))
			runs = {}
			bytes = PathCodec.HEADER_BYTES
		end
	end
	for slot = 1, SLOT_COUNT do
		local holder = slots[slot].holder
		if holder then
			for _, entry in streamEntries(holder) do
				local size = PathCodec.size({ entry }) - PathCodec.HEADER_BYTES
				if #runs >= PathCodec.MAX_RUNS or bytes + size > UNRELIABLE_MAX_BYTES then
					send()
				end
				table.insert(runs, entry)
				bytes += size
			end
		end
	end
	send()
end

local function sendSnapshot(state: PlayerState, r: Remotes)
	state.needsSnapshot = false
	state.snapshotSent = true
	if state.player.Parent == nil then
		return
	end
	r.WorldSnapshot:FireClient(state.player, CongaService.worldSnapshot(state.player))
end

local function broadcast(now: number)
	local r = getRemotes()
	if #pendingOps > 0 then
		local ops = pendingOps
		pendingOps = {}
		r.LineEvent:FireAllClients(ops)
	end
	if #pendingSnips > 0 then
		local snips = pendingSnips
		pendingSnips = {}
		for _, payload in snips do
			r.SnipEvent:FireAllClients(payload)
		end
	end
	broadcastPaths(r)
	call("SpawnService.flush", SpawnService.flush, now, false)
	call("EventService.flush", EventService.flush)
	-- instantanés demandés (arrivée, RequestWorld) : aucune op n'est plus en attente
	for _, state in states do
		if state.needsSnapshot then
			sendSnapshot(state, r)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------------------------

local function onDash(player: Player)
	if not RateLimit.allow(player, "Dash", 3, 1) then
		return
	end
	local state = states[player]
	local data = DataService.get(player)
	if state == nil or data == nil then
		return
	end
	local _, humanoid = characterParts(state)
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local now = Clock.now()
	if safe("isCarrier", false, EventService.isCarrier, player) then
		Notify.feedback(player, "feedback.cometNoDash", nil, "warning")
		return
	end
	if now < state.dashReadyAt then
		Notify.feedback(player, "feedback.dashCooldown", nil, "info")
		return
	end
	state.dashUntil = now + Balance.Dash.Duration
	state.dashReadyAt = now + Formulas.dashCooldown(supernovasOf(data))
	player:SetAttribute("DashReadyAt", state.dashReadyAt)
	Signals.Dashed:Fire(player)
	applyWalkSpeed(state, humanoid, walkSpeedOf(state, now), now)
end

local function onSetInputType(player: Player, kind: unknown)
	if not RateLimit.allow(player, "SetInputType", 1, 5) then
		return
	end
	if not Validate.integer(kind, 1, INPUT_KINDS) then
		return
	end
	local state = states[player]
	if state == nil then
		return
	end
	state.inputType = kind :: number
	player:SetAttribute("InputType", state.inputType)
end

local function onRequestWorld(player: Player)
	if not RateLimit.allow(player, "RequestWorld", 1, 2) then
		return
	end
	local state = states[player]
	if state then
		state.needsSnapshot = true -- envoyé en fin de tick, après la diffusion des ops
	end
end

local function onRequestPath(player: Player, slot: unknown)
	if not RateLimit.allow(player, "RequestPath", 4, 1) then
		return
	end
	if not Validate.integer(slot, 1, SLOT_COUNT) then
		return
	end
	local index = slot :: number
	local holder = slots[index].holder
	local runs = if holder then capRuns(snapshotEntries(holder)) else {}
	getRemotes().PathSnapshot:FireClient(player, index, PathCodec.encode(tickId, runs))
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie du service
-- ---------------------------------------------------------------------------------------------

function CongaService.Init()
	getRemotes()
	call("setLineBanker", EconomyService.setLineBanker, function(player: Player)
		CongaService.forceParade(player)
	end)
end

function CongaService.Start()
	if heartbeat ~= nil then
		return -- déjà démarré
	end
	local r = getRemotes()
	r.Dash.OnServerEvent:Connect(onDash)
	r.SetInputType.OnServerEvent:Connect(onSetInputType)
	r.RequestWorld.OnServerEvent:Connect(onRequestWorld)
	r.RequestPath.OnServerEvent:Connect(onRequestPath)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Signals.ServerMoved:Connect(function(player: Player)
		local state = states[player]
		if state then
			requestReset(state, player.Character)
		end
	end)
	Signals.PlayerReady:Connect(function(player: Player, slot: number)
		local state = states[player]
		if state == nil then
			return
		end
		if validSlot(slot) and slot ~= state.slot then
			bindSlot(state, slot)
		end
		if not state.snapshotSent then
			state.needsSnapshot = true
		end
	end)
	-- filet de sécurité : la Supernova encaisse la file via le crochet ; s'il reste des Nebbies,
	-- ils sont encaissés plutôt que perdus
	Signals.Supernova:Connect(function(player: Player)
		local state = states[player]
		if state and #state.nodes > 0 then
			CongaService.forceParade(player)
		end
	end)

	heartbeat = RunService.Heartbeat:Connect(function(dt: number)
		if type(dt) == "number" and dt > 0 and dt == dt and dt ~= math.huge then
			accumulator += dt
		end
		local steps = 0
		while accumulator >= STEP and steps < Balance.Tick.MaxCatchUp do
			accumulator -= STEP
			steps += 1
			local ok, err = pcall(CongaService.tick, Clock.now())
			if not ok then
				report("tick", err)
			end
		end
		if accumulator >= STEP then
			accumulator = 0 -- au-delà de MaxCatchUp pas, le retard est abandonné
		end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Tick (docs §6)
-- ---------------------------------------------------------------------------------------------

-- Un pas fixe de tick (exposé pour les tests : Clock.freeze + CongaService.tick)
function CongaService.tick(now: number)
	-- 1. horloge
	tickId = (tickId + 1) % TICK_MODULO
	-- 2. acteurs et miettes
	local actors = buildActors(now)
	-- 3. événements
	call("EventService.step", EventService.step, now)
	-- 4. apparitions
	call("SpawnService.step", SpawnService.step, now)
	-- 5. captures
	stepCaptures(actors, now)
	-- 6. Comète
	call("EventService.stepComet", EventService.stepComet, now, actors)
	-- 7. coupes (joueurs puis Gloomwisps)
	local truce = safe("isTruce", false, EventService.isTruce)
	local disabled = safe("snipsDisabled", false, NestService.snipsDisabled)
	stepSnips(actors, now, truce, disabled)
	-- 8. Gloomwisps éclatés
	call("EventService.stepWisps", EventService.stepWisps, now, actors)
	-- 9. parades
	stepParades(actors, safe("beaconOpen", false, EventService.beaconOpen))
	-- 10. entretien (WalkSpeed, escorte, joueurs actifs, LineChanged)
	stepMaintenance(actors, now, truce)
	-- 11. services lents (chacun limite lui-même sa fréquence)
	call("EconomyService.step", EconomyService.step, now)
	call("QuestService.step", QuestService.step, now)
	call("CrewService.step", CrewService.step, now)
	call("LeaderboardService.step", LeaderboardService.step, now)
	-- 12. diffusion
	broadcast(now)
end

-- ---------------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------------

function CongaService.lineLength(player: Player): number
	local state = states[player]
	return if state then #state.nodes else 0
end

function CongaService.lineCodes(player: Player): { Types.NebbyCode }
	local state = states[player]
	return if state then codesOf(state) else {}
end

function CongaService.lineCapacity(player: Player): number
	local state = states[player]
	if state then
		return capacityOf(state)
	end
	return Formulas.congaCapacity(upgradeLevel(DataService.get(player), "conga"))
end

-- Positions serveur des nœuds 1 … n (abscisse HeadGap + (i − 1) × Spacing sur trail)
function CongaService.nodePositions(player: Player): { Vector3 }
	local state = states[player]
	if state == nil then
		return {}
	end
	return table.clone(nodePositionsOf(state))
end

-- Encaisse immédiatement la file (parade normale, sans test de porte) ; Glow crédité
function CongaService.forceParade(player: Player): number
	local state = states[player]
	if state == nil then
		return 0
	end
	return parade(state, false, true)
end

-- Joueur actif (≥ 4 studs parcourus pendant les 60 dernières s)
function CongaService.isActive(player: Player): boolean
	local state = states[player]
	return state ~= nil and activeAt(state, Clock.now())
end

function CongaService.activeCount(): number
	return activeCountAt(Clock.now())
end

-- Type d'entrée déclaré (1 tactile, 2 clavier-souris, 3 manette)
function CongaService.inputType(player: Player): number
	local state = states[player]
	return if state then state.inputType else INPUT_DEFAULT
end

function CongaService.worldSnapshot(player: Player): Types.WorldSnapshotPayload
	local now = Clock.now()
	local lines: { Types.LineSnapshot } = {}
	local runs: { Types.PathEntry } = {}
	for slot = 1, SLOT_COUNT do
		local s = slots[slot]
		local holder = s.holder
		if holder then
			table.insert(lines, { slot = slot, userId = s.owner, ver = s.ver, codes = codesOf(holder) })
			for _, entry in snapshotEntries(holder) do
				table.insert(runs, entry)
			end
		end
	end
	local fallbackEvents: Types.EventStatePayload = {
		t = now,
		wisps = {},
		snipsDisabled = false,
		activePlayers = activeCountAt(now),
	}
	return {
		serverTime = now,
		tick = tickId,
		lines = lines,
		paths = PathCodec.encode(tickId, capRuns(runs)),
		wild = safe("snapshotFor", {}, SpawnService.snapshotFor, player),
		events = safe("EventService.snapshot", fallbackEvents, EventService.snapshot),
		crews = safe("CrewService.snapshot", { crews = {} }, CrewService.snapshot),
	}
end

return CongaService
