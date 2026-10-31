--!strict
-- WorldStateController — paquet « client-world » (docs/04-architecture.md §13.6).
-- Miroir client du monde, SEUL abonné des remotes de monde ; les autres modules lisent son API et
-- écoutent ses signaux (jamais les remotes directement).
-- Remotes possédés côté client : WorldSnapshot, PathStream, PathSnapshot, LineEvent, SnipEvent,
-- WildEvent, EventState, CrewState, PingShow ; émis : RequestWorld, RequestPath.
-- Responsabilités :
--   * WorldSnapshot à l'arrivée (et sur demande) : files, miettes, sauvages, événements, équipages
--     (l'instantané remplace tout ; les ops en attente plus récentes sont rejouées ensuite)
--   * miettes : un Trail miroir par slot dont la numérotation suit EXACTEMENT celle du serveur
--     (pas minimal nul, trous comblés par des points répétés) ; PathStream décodé par PathCodec
--     (pcall), points de seq ≤ dernier connu ignorés, trou de séquence → RequestPath(slot)
--     (au plus 1 / s par slot), PathSnapshot → reset du miroir puis rejeu des points plus récents ;
--     paquets plus vieux (tick u16, comparaison modulo 65536) ignorés
--   * files : ops LineEvent et SnipEvent appliquées dans l'ordre STRICT de `ver` par slot (tampon de
--     Balance.Net.VersionBufferSeconds pour les ops en avance, puis RequestWorld) ; op "owner" remet
--     la file et le miroir de miettes du slot à zéro (la numérotation des miettes continue)
--   * sauvages : WildEvent (apparitions / disparitions), Nebbies libres portés par SnipEvent et
--     LineEvent "clear" ; ids capturés retirés via LineEvent "add" ; ids retirés gardés 5 s pour
--     ignorer une apparition tardive ; expiration locale à expiresAt
--   * événements (EventState) et équipages (CrewState) ; pings (PingShow)
--   * positions : sauvages (ancre + SeededPath.wander, arc de dispersion), Gloomwisps
--     (SeededPath.newChordCursor), Comète (ciel, sol ou au-dessus du porteur)
-- Toute charge utile reçue est vérifiée (types, nombres finis, bornes) : une donnée illisible est
-- ignorée sans erreur. Une seule connexion Heartbeat (minuteries : tampon de versions, expirations,
-- relances de l'instantané).
-- GDD : §12.4, §12.5, §6.3, §6.4.
-- Dépendances : Shared/Net, Logic/Trail, Logic/PathCodec, Logic/SeededPath, Logic/WorldLayout,
-- Config/Balance, Config/Nebbies, Shared/Util/Clock, Shared/Util/Signal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Nebbies = require(Shared.Config.Nebbies)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)
local Trail = require(Shared.Logic.Trail)
local PathCodec = require(Shared.Logic.PathCodec)
local SeededPath = require(Shared.Logic.SeededPath)
local WorldLayout = require(Shared.Logic.WorldLayout)

local WorldStateController = {}

-- Premier WorldSnapshot appliqué
WorldStateController.Ready = Signal.new() :: Signal.Signal<>
-- Chaque op de file appliquée, dans l'ordre (slot, op)
WorldStateController.LineOp = Signal.new() :: Signal.Signal<number, Types.LineOp>
-- Capture : (slot, code, id du sauvage ou 0, position du sauvage au moment de la capture)
WorldStateController.Caught = Signal.new() :: Signal.Signal<number, Types.NebbyCode, number, Vector3?>
-- Parade : (slot, op bank)
WorldStateController.Banked = Signal.new() :: Signal.Signal<number, Types.LineBankOp>
-- Coupe confirmée par le serveur (effets joués SEULEMENT à ce moment)
WorldStateController.Snipped = Signal.new() :: Signal.Signal<Types.SnipEventPayload>
-- File vidée hors parade : (slot, raison)
WorldStateController.Cleared = Signal.new() :: Signal.Signal<number, string>
-- Nouveau propriétaire d'un slot : (slot, userId ; 0 = libre)
WorldStateController.OwnerChanged = Signal.new() :: Signal.Signal<number, number>
WorldStateController.WildAdded = Signal.new() :: Signal.Signal<Types.WildMirror>
-- (id, raison "expired" | "caught" | "cleared", slot du capteur ou 0)
WorldStateController.WildRemoved = Signal.new() :: Signal.Signal<number, string, number>
-- (nouvel état, ancien état ou nil)
WorldStateController.EventChanged =
	Signal.new() :: Signal.Signal<Types.EventStatePayload, Types.EventStatePayload?>
WorldStateController.CrewsChanged = Signal.new() :: Signal.Signal<Types.CrewStatePayload>
-- (userId, kind 1-6)
WorldStateController.PingShown = Signal.new() :: Signal.Signal<number, number>

-- Constantes (GDD §12.4, docs §10.4-§10.5) -----------------------------------------------------

local SLOT_COUNT = 12
local TICK_MODULO = 65536
local TICK_HALF = 32768
-- Un paquet « plus vieux » de plus de 100 ticks (10 s) est un rebouclage du compteur (serveur
-- silencieux longtemps), pas un paquet en retard : il est accepté et sert de nouvelle référence
local STALE_TICKS = 100
local MIRROR_MIN_STEP = 0 -- tous les points sont gardés : numérotation identique au serveur
local MAX_GAP_FILL = 255 -- au-delà, le miroir repart du run reçu (trou trop grand)
local PATH_REQUEST_INTERVAL = 1 -- RequestPath au plus 1 / s par slot
local WORLD_REQUEST_INTERVAL = 2 -- RequestWorld : débit serveur 1 / 2 s
local SNAPSHOT_RETRY = 5 -- s sans WorldSnapshot → RequestWorld (puis toutes les 5 s)
local RETIRED_SECONDS = 5 -- ids retirés ignorés 5 s (apparition tardive)
local MAINTENANCE_INTERVAL = 0.1 -- s entre deux passes de minuteries
local MAX_LIST = 255 -- longueur maximale acceptée d'une liste reçue
local MAX_LINE = Balance.Conga.AbsoluteMax
local MAX_WILD_ID = 65535
local MAX_USER_ID = 2 ^ 53
local CARRY_HEIGHT = 5 -- studs : orbe de la Comète au-dessus de la HumanoidRootPart du porteur
-- Curseurs de corde par Gloomwisp : chacun reste monotone (t croissant). Le rendu demande la
-- position à t PUIS à t + 0,2 s (direction) : un seul curseur repartirait du tout début de la
-- trajectoire à chaque image proche d'une fin de corde (coût proportionnel à l'âge du Gloomwisp)
local WISP_CURSORS = 3
local BEACON_TIMES = { "warnAt", "startsAt", "endsAt", "points", "goal" }
local WINDOW_TIMES = { "startsAt", "endsAt" }
local END_TIME = { "endsAt" }

local CLEAR_REASONS = { death = true, leave = true, reset = true, supernova = true }
local DESPAWN_REASONS = { expired = true, caught = true, cleared = true }

-- État ---------------------------------------------------------------------------------------

type PendingEntry = { line: Types.LineOp?, snip: Types.SnipEventPayload? }
type Retired = { at: number, t0: number }
type CursorSlot = { cursor: SeededPath.ChordCursor, lastT: number }
type WispCursor = { seed: number, t0: number, cursors: { CursorSlot } }

type RemoteSet = {
	WorldSnapshot: RemoteEvent,
	PathStream: UnreliableRemoteEvent,
	PathSnapshot: RemoteEvent,
	LineEvent: RemoteEvent,
	SnipEvent: RemoteEvent,
	WildEvent: RemoteEvent,
	EventState: RemoteEvent,
	CrewState: RemoteEvent,
	PingShow: RemoteEvent,
	RequestWorld: RemoteEvent,
	RequestPath: RemoteEvent,
}

local remotes: RemoteSet? = nil
local started = false
local ready = false
local startedAt = 0
local lastWorldRequest = -math.huge
local lastMaintenance = -math.huge

local lines: { [number]: Types.LineMirror } = {}
local previous: { [number]: { Types.NebbyCode } } = {}
local trails: { [number]: Trail.Trail } = {}
local pathRequestedAt: { [number]: number } = {}
local pending: { [number]: { [number]: PendingEntry } } = {}
local pendingSince: { [number]: number } = {}
local lastTick: number? = nil

local wilds: { [number]: Types.WildMirror } = {}
local retired: { [number]: Retired } = {}

local events: Types.EventStatePayload? = nil
local wispById: { [number]: Types.WispState } = {}
local wispCursors: { [number]: WispCursor } = {}

local EMPTY_CREWS: Types.CrewStatePayload = { crews = {} }
local crews: Types.CrewStatePayload = EMPTY_CREWS
local crewByUser: { [number]: number } = {}

-- Validation des charges utiles reçues ---------------------------------------------------------

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function isInt(x: any, min: number, max: number): boolean
	return isFinite(x) and x % 1 == 0 and x >= min and x <= max
end

local function isList(x: any, maxLength: number): boolean
	if type(x) ~= "table" then
		return false
	end
	local n = #x
	if n > maxLength then
		return false
	end
	local count = 0
	for _ in x do
		count += 1
		if count > n then
			return false -- clés en trop : table mixte ou à trous
		end
	end
	return true
end

local function validSlot(x: any): boolean
	return isInt(x, 1, SLOT_COUNT)
end

local function optionalFinite(x: any): boolean
	return x == nil or isFinite(x)
end

-- UserId d'un joueur : entier non nul. Les serveurs de test de Studio (« Local Server ») donnent
-- des UserId NÉGATIFS (-1, -2…) : les refuser rendrait le jeu muet en test multijoueur
local function validUserId(x: any): boolean
	return isInt(x, -MAX_USER_ID, MAX_USER_ID) and x ~= 0
end

local function optionalUserId(x: any): boolean
	return x == nil or validUserId(x)
end

-- Sous-table d'état d'événement : table dont les champs `keys` sont des nombres finis
local function validTimes(s: any, keys: { string }): boolean
	if type(s) ~= "table" then
		return false
	end
	for _, key in keys do
		if not isFinite(s[key]) then
			return false
		end
	end
	return true
end

local function getRemotes(): RemoteSet
	local r = remotes
	if r then
		return r
	end
	local set: RemoteSet = {
		WorldSnapshot = Net.event("WorldSnapshot"),
		PathStream = Net.unreliable("PathStream"),
		PathSnapshot = Net.event("PathSnapshot"),
		LineEvent = Net.event("LineEvent"),
		SnipEvent = Net.event("SnipEvent"),
		WildEvent = Net.event("WildEvent"),
		EventState = Net.event("EventState"),
		CrewState = Net.event("CrewState"),
		PingShow = Net.event("PingShow"),
		RequestWorld = Net.event("RequestWorld"),
		RequestPath = Net.event("RequestPath"),
	}
	remotes = set
	return set
end

-- Sauvages --------------------------------------------------------------------------------------

local function groundPoint(x: number, z: number): Vector3
	return Vector3.new(x, WorldLayout.groundY(x, z), z)
end

-- WildSpawn reçu → miroir (nil si illisible)
local function toMirror(spawn: any): Types.WildMirror?
	if type(spawn) ~= "table" then
		return nil
	end
	if not isInt(spawn.id, 1, MAX_WILD_ID) or not Nebbies.isValidCode(spawn.code) then
		return nil
	end
	if not (isFinite(spawn.x) and isFinite(spawn.z) and isFinite(spawn.seed)) then
		return nil
	end
	if not (isFinite(spawn.t0) and isFinite(spawn.life) and spawn.life > 0) then
		return nil
	end
	if
		not (optionalFinite(spawn.dizzyUntil) and optionalFinite(spawn.fromX) and optionalFinite(spawn.fromZ))
	then
		return nil
	end
	local priority = spawn.prioritySlot
	if priority ~= nil and not isInt(priority, 0, SLOT_COUNT) then
		return nil
	end
	local from: Vector3? = nil
	if spawn.fromX ~= nil and spawn.fromZ ~= nil then
		from = groundPoint(spawn.fromX, spawn.fromZ)
	end
	return {
		id = spawn.id,
		code = spawn.code,
		anchor = groundPoint(spawn.x, spawn.z),
		seed = spawn.seed,
		t0 = spawn.t0,
		expiresAt = spawn.t0 + spawn.life,
		dizzyUntil = spawn.dizzyUntil or 0,
		prioritySlot = priority or 0,
		from = from,
		personal = spawn.personal == true,
	}
end

local function retire(id: number, t0: number)
	retired[id] = { at = Clock.now(), t0 = t0 }
end

local function removeWild(id: number, reason: string, slot: number): Types.WildMirror?
	local w = wilds[id]
	if w == nil then
		return nil
	end
	wilds[id] = nil
	retire(id, w.t0)
	WorldStateController.WildRemoved:Fire(id, reason, slot)
	return w
end

local function addWild(spawn: any)
	local mirror = toMirror(spawn)
	if mirror == nil then
		return
	end
	local id = mirror.id
	local old = retired[id]
	if old and mirror.t0 <= old.t0 then
		return -- apparition tardive d'un Nebby déjà capturé, expiré ou retiré
	end
	if mirror.expiresAt <= Clock.now() then
		return
	end
	local existing = wilds[id]
	if existing then
		if existing.t0 == mirror.t0 then
			return -- doublon
		end
		-- id réutilisé par le serveur : l'ancien n'existe plus
		removeWild(id, "expired", 0)
		retired[id] = nil
	end
	wilds[id] = mirror
	WorldStateController.WildAdded:Fire(mirror)
end

local function addLooseList(list: any)
	if not isList(list, MAX_LIST) then
		return
	end
	for _, spawn in list do
		addWild(spawn)
	end
end

-- Position (logique, comme SpawnService.positionOf) d'un sauvage à l'instant t
local function wildPositionAt(wild: Types.WildMirror, t: number): Vector3
	local from = wild.from
	local scatter = Balance.Snip.ScatterTime
	if from ~= nil and t < wild.t0 + scatter then
		local a = math.clamp((t - wild.t0) / scatter, 0, 1)
		return from + (wild.anchor - from) * a
	end
	return wild.anchor + SeededPath.wander(wild.seed, t - wild.t0)
end

-- Miettes ---------------------------------------------------------------------------------------

local function newMirror(firstSeq: number): Trail.Trail
	return Trail.new(Balance.Conga.TrailLength, MIRROR_MIN_STEP, firstSeq)
end

local function requestPath(slot: number)
	local now = Clock.now()
	local last = pathRequestedAt[slot]
	if last ~= nil and now - last < PATH_REQUEST_INTERVAL then
		return
	end
	pathRequestedAt[slot] = now
	getRemotes().RequestPath:FireServer(slot)
end

-- Ajoute un point au miroir en gardant la numérotation du serveur (Trail.push garde tout point :
-- pas minimal nul ; un saut ≥ 40 studs remet l'historique à zéro en CONTINUANT la numérotation)
local function pushPoint(trail: Trail.Trail, p: Vector3)
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then
		return
	end
	if #trail.points == 0 then
		trail.points[1] = p
		return
	end
	trail:push(p)
end

-- Comble un trou de `missing` miettes en répétant le dernier point (segments de longueur nulle)
local function fillGap(trail: Trail.Trail, missing: number)
	local points = trail.points
	local last = points[#points]
	for _ = 1, missing do
		table.insert(points, last)
	end
end

-- Applique un run (points numérotés à partir de firstSeq) au miroir du slot
local function applyRun(slot: number, firstSeq: number, points: { Vector3 }, fromStream: boolean)
	local trail = trails[slot]
	if trail == nil then
		trail = newMirror(firstSeq)
		trails[slot] = trail
	end
	local known = trail:lastSeq()
	local lastSeqOfRun = firstSeq + #points - 1
	if lastSeqOfRun <= known then
		return -- déjà connu (points répétés)
	end
	if firstSeq > known + 1 then
		local missing = firstSeq - known - 1
		if fromStream then
			requestPath(slot)
		end
		if #trail.points == 0 or missing > MAX_GAP_FILL then
			trail:reset(points[1], firstSeq)
			for i = 2, #points do
				pushPoint(trail, points[i])
			end
			return
		end
		fillGap(trail, missing)
	end
	for i, p in points do
		if firstSeq + i - 1 > known then
			pushPoint(trail, p)
		end
	end
end

-- Remplace le miroir du slot par des runs complets (PathSnapshot, WorldSnapshot), puis rejoue
-- les points plus récents déjà reçus par le flux
local function replaceTrail(slot: number, runs: { Types.PathEntry })
	if #runs == 0 then
		return
	end
	table.sort(runs, function(a, b)
		return a.firstSeq < b.firstSeq
	end)
	local old = trails[slot]
	local snapLast = runs[#runs].firstSeq + #runs[#runs].points - 1
	local newerFirst, newer = 0, {} :: { Vector3 }
	if old ~= nil and old:lastSeq() > snapLast and #old.points > 0 then
		newerFirst, newer = old:since(snapLast + 1)
	end
	local trail = newMirror(runs[1].firstSeq)
	trails[slot] = trail
	for _, run in runs do
		applyRun(slot, run.firstSeq, run.points, false)
	end
	if #newer > 0 then
		applyRun(slot, newerFirst, newer, false)
	end
end

local function decodePaths(buf: any): (number?, { Types.PathEntry })
	if typeof(buf) ~= "buffer" then
		return nil, {}
	end
	local ok, tick, runs = pcall(PathCodec.decode, buf)
	if not ok or type(runs) ~= "table" then
		return nil, {}
	end
	return tick, runs
end

-- Runs groupés par slot valide
local function groupBySlot(runs: { Types.PathEntry }): { [number]: { Types.PathEntry } }
	local out: { [number]: { Types.PathEntry } } = {}
	for _, run in runs do
		if validSlot(run.slot) and #run.points > 0 then
			local list = out[run.slot]
			if list == nil then
				list = {}
				out[run.slot] = list
			end
			table.insert(list, run)
		end
	end
	return out
end

local function onPathStream(buf: any)
	local tick, runs = decodePaths(buf)
	if tick == nil then
		return
	end
	local previousTick = lastTick
	if previousTick ~= nil then
		local diff = (tick - previousTick) % TICK_MODULO
		if diff > TICK_HALF and TICK_MODULO - diff <= STALE_TICKS then
			return -- paquet en retard
		end
	end
	lastTick = tick
	for _, run in runs do
		if validSlot(run.slot) and #run.points > 0 then
			applyRun(run.slot, run.firstSeq, run.points, true)
		end
	end
end

local function onPathSnapshot(slot: any, buf: any)
	if not validSlot(slot) then
		return
	end
	local tick, runs = decodePaths(buf)
	if tick == nil then
		return
	end
	local grouped = groupBySlot(runs)
	local own = grouped[slot]
	if own then
		replaceTrail(slot, own)
	end
end

-- Files : application des ops ---------------------------------------------------------------------

local function cloneCodes(codes: { Types.NebbyCode }): { Types.NebbyCode }
	return table.clone(codes)
end

local function validCodes(codes: any, maxLength: number): boolean
	if not isList(codes, maxLength) then
		return false
	end
	for _, code in codes do
		if not Nebbies.isValidCode(code) then
			return false
		end
	end
	return true
end

-- Vérifie la forme d'une op de LineEvent (slot et ver déjà vérifiés)
local function validLineOp(op: any): boolean
	local kind = op.op
	if kind == "add" then
		if not validCodes(op.codes, MAX_LINE) or not isList(op.ids, MAX_LINE) then
			return false
		end
		for _, id in op.ids do
			if not isInt(id, 0, MAX_WILD_ID) then
				return false
			end
		end
		return true
	elseif kind == "bank" then
		return isInt(op.count, 0, MAX_LIST)
			and isFinite(op.glow)
			and isFinite(op.bonus)
			and type(op.atBeacon) == "boolean"
			and isInt(op.newEntries, 0, MAX_LIST)
	elseif kind == "clear" then
		return type(op.reason) == "string" and CLEAR_REASONS[op.reason] == true and isList(op.loose, MAX_LIST)
	elseif kind == "owner" then
		return op.ver == 0 and (op.userId == 0 or validUserId(op.userId))
	end
	return false
end

local function validSnip(p: any): boolean
	return type(p) == "table"
		and isInt(p.snipperSlot, 0, SLOT_COUNT)
		and validSlot(p.victimSlot)
		and isInt(p.ver, 1, 2 ^ 31)
		and isInt(p.cutIndex, 1, MAX_LIST)
		and isInt(p.count, 0, MAX_LIST)
		and isList(p.looseIds, MAX_LIST)
		and isList(p.loose, MAX_LIST)
		and type(p.byWisp) == "boolean"
		and (p.wispId == nil or isInt(p.wispId, 0, MAX_WILD_ID))
		and isFinite(p.x)
		and isFinite(p.y)
		and isFinite(p.z)
		and isFinite(p.dust)
end

local function applyOwner(op: Types.LineOwnerOp)
	local slot = op.slot
	local old = lines[slot]
	previous[slot] = if old then cloneCodes(old.codes) else {}
	if op.userId ~= 0 then
		lines[slot] = { slot = slot, userId = op.userId, ver = 0, codes = {} }
	else
		lines[slot] = nil
	end
	-- nouvelle vie : miroir vidé, numérotation des miettes continue (seq contigus entre propriétaires)
	local trail = trails[slot]
	if trail ~= nil then
		trails[slot] = newMirror(trail:lastSeq() + 1)
	end
	pending[slot] = nil
	pendingSince[slot] = nil
	WorldStateController.LineOp:Fire(slot, op)
	WorldStateController.OwnerChanged:Fire(slot, op.userId)
end

local function applyAdd(line: Types.LineMirror, op: Types.LineAddOp)
	local now = Clock.now()
	local caught: { { code: number, id: number, pos: Vector3? } } = {}
	for i, code in op.codes do
		if #line.codes < MAX_LINE then
			table.insert(line.codes, code)
		end
		local id = op.ids[i] or 0
		local pos: Vector3? = nil
		if id ~= 0 then
			local w = wilds[id]
			if w then
				pos = wildPositionAt(w, now)
			end
		end
		table.insert(caught, { code = code, id = id, pos = pos })
	end
	WorldStateController.LineOp:Fire(line.slot, op)
	for _, c in caught do
		WorldStateController.Caught:Fire(line.slot, c.code, c.id, c.pos)
		if c.id ~= 0 then
			if removeWild(c.id, "caught", line.slot) == nil then
				retire(c.id, now) -- apparition jamais reçue : l'ignorer si elle arrive en retard
			end
		end
	end
end

local function applyLine(op: Types.LineOp)
	local slot = op.slot
	if op.op == "owner" then
		applyOwner(op :: Types.LineOwnerOp)
		return
	end
	local line = lines[slot]
	if line == nil then
		return
	end
	line.ver = op.ver
	if op.op == "add" then
		applyAdd(line, op :: Types.LineAddOp)
	elseif op.op == "bank" then
		previous[slot] = cloneCodes(line.codes)
		table.clear(line.codes)
		WorldStateController.LineOp:Fire(slot, op)
		WorldStateController.Banked:Fire(slot, op :: Types.LineBankOp)
	elseif op.op == "clear" then
		local clearOp = op :: Types.LineClearOp
		previous[slot] = cloneCodes(line.codes)
		table.clear(line.codes)
		WorldStateController.LineOp:Fire(slot, op)
		addLooseList(clearOp.loose)
		WorldStateController.Cleared:Fire(slot, clearOp.reason)
	end
end

local function applySnip(p: Types.SnipEventPayload)
	local line = lines[p.victimSlot]
	if line == nil then
		return
	end
	line.ver = p.ver
	local codes = line.codes
	previous[p.victimSlot] = cloneCodes(codes)
	if p.cutIndex > #codes then
		-- miroir désynchronisé (nœuds manquants) : la version suit, l'instantané corrigera
		WorldStateController.requestWorld()
	end
	for i = #codes, p.cutIndex, -1 do
		table.remove(codes, i)
	end
	WorldStateController.Snipped:Fire(p)
	addLooseList(p.loose)
end

local function applyEntry(entry: PendingEntry)
	if entry.line then
		applyLine(entry.line)
	elseif entry.snip then
		applySnip(entry.snip)
	end
end

-- Rejoue les ops en attente devenues applicables (ordre strict de ver)
local function drain(slot: number)
	local queue = pending[slot]
	if queue == nil then
		return
	end
	while true do
		local line = lines[slot]
		if line == nil then
			break
		end
		for ver in queue do
			if ver <= line.ver then
				queue[ver] = nil
			end
		end
		local nextEntry = queue[line.ver + 1]
		if nextEntry == nil then
			break
		end
		queue[line.ver + 1] = nil
		applyEntry(nextEntry)
		if pending[slot] ~= queue then
			return -- une op "owner" a remis la file à zéro
		end
	end
	if next(queue) == nil then
		pending[slot] = nil
		pendingSince[slot] = nil
	end
end

local function buffer(slot: number, ver: number, entry: PendingEntry)
	local queue = pending[slot]
	if queue == nil then
		queue = {}
		pending[slot] = queue
	end
	queue[ver] = entry
	if pendingSince[slot] == nil then
		pendingSince[slot] = Clock.now()
	end
end

local function submit(slot: number, ver: number, entry: PendingEntry)
	local line = lines[slot]
	if line == nil then
		buffer(slot, ver, entry) -- slot inconnu (op "owner" manquée ?) : l'instantané tranchera
		return
	end
	if ver <= line.ver then
		return -- déjà appliquée
	end
	if ver == line.ver + 1 then
		applyEntry(entry)
		drain(slot)
	else
		buffer(slot, ver, entry)
	end
end

local function onLineEvent(ops: any)
	if not isList(ops, MAX_LIST * 4) then
		return
	end
	for _, op in ops do
		if type(op) == "table" and validSlot(op.slot) and isInt(op.ver, 0, 2 ^ 31) and validLineOp(op) then
			if op.op == "owner" then
				applyLine(op)
				drain(op.slot)
			elseif op.ver >= 1 then
				submit(op.slot, op.ver, { line = op })
			end
		end
	end
end

local function onSnipEvent(payload: any)
	if not validSnip(payload) then
		return
	end
	submit(payload.victimSlot, payload.ver, { snip = payload })
end

-- Événements et équipages -------------------------------------------------------------------------

local function validEvents(ev: any): boolean
	if type(ev) ~= "table" or not isFinite(ev.t) or not isList(ev.wisps, MAX_LIST) then
		return false
	end
	for _, w in ev.wisps do
		if
			type(w) ~= "table"
			or not isInt(w.id, 0, MAX_WILD_ID)
			or not isFinite(w.seed)
			or not isFinite(w.t0)
		then
			return false
		end
		if not (optionalFinite(w.poppedAt) and optionalFinite(w.respawnAt)) then
			return false
		end
	end
	local c = ev.comet
	if c ~= nil then
		if type(c) ~= "table" or type(c.phase) ~= "string" or not isFinite(c.id) then
			return false
		end
		if not (isFinite(c.x) and isFinite(c.z) and isFinite(c.impactAt) and isFinite(c.warnAt)) then
			return false
		end
		-- champs lus à chaque image (rendu de l'orbe, porteur) : un type faux figerait le rendu
		if
			not (
				optionalUserId(c.carrierId)
				and optionalUserId(c.prevCarrierId)
				and optionalFinite(c.carrierSince)
				and optionalFinite(c.burstAt)
				and optionalFinite(c.endedAt)
			)
		then
			return false
		end
	end
	local b = ev.beacon
	if
		b ~= nil
		and not (validTimes(b, BEACON_TIMES) and type(b.phase) == "string" and optionalUserId(b.topUserId))
	then
		return false
	end
	local w = ev.weather
	if w ~= nil and not (validTimes(w, WINDOW_TIMES) and type(w.key) == "string") then
		return false
	end
	if ev.starfall ~= nil and not validTimes(ev.starfall, WINDOW_TIMES) then
		return false
	end
	if ev.frenzy ~= nil and not validTimes(ev.frenzy, END_TIME) then
		return false
	end
	if ev.serverBoost ~= nil and not validTimes(ev.serverBoost, END_TIME) then
		return false
	end
	return true
end

local function setEvents(ev: any)
	if not validEvents(ev) then
		return
	end
	local old = events
	events = ev
	table.clear(wispById)
	for _, w in (ev :: Types.EventStatePayload).wisps do
		wispById[w.id] = w
		local cursor = wispCursors[w.id]
		if cursor == nil or cursor.seed ~= w.seed or cursor.t0 ~= w.t0 then
			wispCursors[w.id] = { seed = w.seed, t0 = w.t0, cursors = {} }
		end
	end
	for id in wispCursors do
		if wispById[id] == nil then
			wispCursors[id] = nil
		end
	end
	WorldStateController.EventChanged:Fire(ev, old)
end

local function setCrews(payload: any)
	if type(payload) ~= "table" or not isList(payload.crews, MAX_LIST) then
		return
	end
	local list: { Types.CrewEntry } = {}
	local byUser: { [number]: number } = {}
	for _, crew in payload.crews do
		if type(crew) == "table" and isInt(crew.id, 1, MAX_USER_ID) and isList(crew.userIds, 16) then
			local ids: { number } = {}
			for _, userId in crew.userIds do
				if validUserId(userId) then
					table.insert(ids, userId)
					byUser[userId] = crew.id
				end
			end
			table.insert(list, { id = crew.id, userIds = ids })
		end
	end
	crews = { crews = list }
	crewByUser = byUser
	WorldStateController.CrewsChanged:Fire(crews)
end

local function onWildEvent(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if isList(payload.despawns, MAX_LIST * 4) then
		for _, d in payload.despawns do
			if type(d) == "table" and isInt(d.id, 1, MAX_WILD_ID) and DESPAWN_REASONS[d.reason] then
				local slot = if isInt(d.slot, 0, SLOT_COUNT) then d.slot else 0
				if removeWild(d.id, d.reason, slot) == nil then
					retire(d.id, Clock.now())
				end
			end
		end
	end
	if isList(payload.spawns, MAX_LIST * 4) then
		for _, spawn in payload.spawns do
			addWild(spawn)
		end
	end
end

local function onPingShow(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if validUserId(payload.userId) and isInt(payload.kind, 1, Balance.Ping.Count) then
		WorldStateController.PingShown:Fire(payload.userId, payload.kind)
	end
end

-- Instantané du monde --------------------------------------------------------------------------------

local function applySnapshotLines(list: any)
	local seen: { [number]: boolean } = {}
	if isList(list, SLOT_COUNT * 2) then
		for _, l in list do
			if
				type(l) == "table"
				and validSlot(l.slot)
				and validUserId(l.userId)
				and isInt(l.ver, 0, 2 ^ 31)
				and validCodes(l.codes, MAX_LINE)
			then
				local old = lines[l.slot]
				lines[l.slot] = { slot = l.slot, userId = l.userId, ver = l.ver, codes = cloneCodes(l.codes) }
				seen[l.slot] = true
				if old == nil or old.userId ~= l.userId then
					previous[l.slot] = if old then cloneCodes(old.codes) else {}
					WorldStateController.OwnerChanged:Fire(l.slot, l.userId)
				end
			end
		end
	end
	for slot = 1, SLOT_COUNT do
		if not seen[slot] and lines[slot] ~= nil then
			local old = lines[slot] :: Types.LineMirror
			previous[slot] = cloneCodes(old.codes)
			lines[slot] = nil
			WorldStateController.OwnerChanged:Fire(slot, 0)
		end
	end
end

local function applySnapshotWild(list: any)
	if not isList(list, MAX_WILD_ID) then
		return
	end
	local keep: { [number]: boolean } = {}
	for _, spawn in list do
		if type(spawn) == "table" and isInt(spawn.id, 1, MAX_WILD_ID) then
			keep[spawn.id] = true
			local existing = wilds[spawn.id]
			if existing and existing.t0 ~= spawn.t0 then
				removeWild(spawn.id, "expired", 0)
				retired[spawn.id] = nil
			end
			if wilds[spawn.id] == nil then
				retired[spawn.id] = nil -- l'instantané fait foi
				addWild(spawn)
			end
		end
	end
	for id in table.clone(wilds) do
		if not keep[id] then
			removeWild(id, "cleared", 0)
		end
	end
end

local function onWorldSnapshot(snap: any)
	-- sans liste de files lisible, l'instantané entier est ignoré (sinon toutes les files du miroir
	-- seraient effacées comme si les Nids étaient libres)
	if type(snap) ~= "table" or not isList(snap.lines, SLOT_COUNT * 2) then
		return
	end
	applySnapshotLines(snap.lines)
	local tick, runs = decodePaths(snap.paths)
	if tick ~= nil then
		lastTick = tick
		for slot, list in groupBySlot(runs) do
			replaceTrail(slot, list)
		end
	end
	applySnapshotWild(snap.wild)
	if snap.events ~= nil then
		setEvents(snap.events)
	end
	if snap.crews ~= nil then
		setCrews(snap.crews)
	end
	-- ops en attente : celles déjà couvertes par l'instantané disparaissent, les autres sont rejouées ;
	-- celles d'un slot que l'instantané déclare LIBRE sont abandonnées (l'instantané fait foi : sans
	-- cela, le trou ne se comblerait jamais et RequestWorld repartirait toutes les 2 s, sans fin)
	for slot in table.clone(pending) do
		if lines[slot] == nil then
			pending[slot] = nil
			pendingSince[slot] = nil
		else
			drain(slot)
		end
	end
	local first = not ready
	ready = true
	if first then
		WorldStateController.Ready:Fire()
	end
end

-- Minuteries (une seule connexion Heartbeat) ---------------------------------------------------------

local function maintenance(now: number)
	-- ops en avance depuis plus de VersionBufferSeconds : trou persistant → instantané
	for slot, since in pendingSince do
		if now - since >= Balance.Net.VersionBufferSeconds then
			pendingSince[slot] = now
			WorldStateController.requestWorld()
		end
	end
	-- expirations locales
	for id, w in wilds do
		if now >= w.expiresAt then
			removeWild(id, "expired", 0)
		end
	end
	for id, r in retired do
		if now - r.at >= RETIRED_SECONDS then
			retired[id] = nil
		end
	end
	-- instantané jamais reçu : relance
	if not ready and now - startedAt >= SNAPSHOT_RETRY and now - lastWorldRequest >= SNAPSHOT_RETRY then
		WorldStateController.requestWorld()
	end
end

-- Cycle de vie ---------------------------------------------------------------------------------------

function WorldStateController.Init()
	getRemotes()
end

function WorldStateController.Start()
	if started then
		return
	end
	started = true
	startedAt = Clock.now()
	local r = getRemotes()
	r.WorldSnapshot.OnClientEvent:Connect(onWorldSnapshot)
	r.PathStream.OnClientEvent:Connect(onPathStream)
	r.PathSnapshot.OnClientEvent:Connect(onPathSnapshot)
	r.LineEvent.OnClientEvent:Connect(onLineEvent)
	r.SnipEvent.OnClientEvent:Connect(onSnipEvent)
	r.WildEvent.OnClientEvent:Connect(onWildEvent)
	r.EventState.OnClientEvent:Connect(setEvents)
	r.CrewState.OnClientEvent:Connect(setCrews)
	r.PingShow.OnClientEvent:Connect(onPingShow)
	RunService.Heartbeat:Connect(function()
		local now = Clock.now()
		if now - lastMaintenance >= MAINTENANCE_INTERVAL or now < lastMaintenance then
			lastMaintenance = now
			maintenance(now)
		end
	end)
end

-- API -----------------------------------------------------------------------------------------------

function WorldStateController.isReady(): boolean
	return ready
end

function WorldStateController.slotOf(userId: number): number
	for slot, line in lines do
		if line.userId == userId then
			return slot
		end
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local attr = player:GetAttribute("Slot")
		if isInt(attr, 1, SLOT_COUNT) then
			return attr :: number
		end
	end
	return 0
end

-- Slot du joueur local (0 tant qu'inconnu)
function WorldStateController.localSlot(): number
	local player = Players.LocalPlayer
	if player == nil then
		return 0
	end
	return WorldStateController.slotOf(player.UserId)
end

function WorldStateController.userAt(slot: number): number
	local line = lines[slot]
	return if line then line.userId else 0
end

function WorldStateController.line(slot: number): Types.LineMirror?
	return lines[slot]
end

function WorldStateController.lineLength(slot: number): number
	local line = lines[slot]
	return if line then #line.codes else 0
end

-- Codes de la file juste avant sa dernière parade, coupe, vidange ou changement de propriétaire
-- (animation de parade et de dispersion) ; ajout du paquet client-world
function WorldStateController.previousCodes(slot: number): { Types.NebbyCode }
	return previous[slot] or {}
end

-- Miroir des miettes serveur du slot (nil si inconnu)
function WorldStateController.trail(slot: number): Trail.Trail?
	return trails[slot]
end

function WorldStateController.wilds(): { [number]: Types.WildMirror }
	return wilds
end

function WorldStateController.wildPosition(wild: Types.WildMirror, t: number): Vector3
	return wildPositionAt(wild, t)
end

function WorldStateController.events(): Types.EventStatePayload?
	return events
end

-- Position au sol (Y = WorldLayout.groundY) d'un Gloomwisp vivant, nil s'il est éclaté ou inconnu
-- Curseur le plus avancé dont le dernier instant est ≤ t (chacun reste monotone) ; sinon un
-- nouveau curseur (au plus WISP_CURSORS, le plus en avance est remplacé)
local function wispCursorAt(c: WispCursor, t: number): SeededPath.ChordCursor
	local best: CursorSlot? = nil
	for _, slot in c.cursors do
		if slot.lastT <= t and (best == nil or slot.lastT > best.lastT) then
			best = slot
		end
	end
	if best == nil then
		local fresh: CursorSlot = { cursor = SeededPath.newChordCursor(c.seed, c.t0), lastT = -math.huge }
		if #c.cursors < WISP_CURSORS then
			table.insert(c.cursors, fresh)
		else
			local ahead = 1
			for i, slot in c.cursors do
				if slot.lastT > c.cursors[ahead].lastT then
					ahead = i
				end
			end
			c.cursors[ahead] = fresh
		end
		best = fresh
	end
	local chosen = best :: CursorSlot
	chosen.lastT = t
	return chosen.cursor
end

function WorldStateController.wispPosition(id: number, t: number): Vector3?
	local w = wispById[id]
	local c = wispCursors[id]
	if w == nil or c == nil or w.poppedAt ~= nil or not isFinite(t) then
		return nil
	end
	local p = wispCursorAt(c, t):at(t)
	return groundPoint(p.X, p.Z)
end

-- Position de la HumanoidRootPart d'un joueur : personnage s'il est chargé, sinon tête des miettes
local function playerPosition(userId: number): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local slot = WorldStateController.slotOf(userId)
	local trail = if slot ~= 0 then trails[slot] else nil
	return if trail then trail:head() else nil
end

-- Position de la Comète (dans le ciel, au sol ou au-dessus du porteur), nil si aucune
function WorldStateController.cometPosition(t: number): Vector3?
	local ev = events
	local c = if ev then ev.comet else nil
	if c == nil then
		return nil
	end
	local impact = groundPoint(c.x, c.z)
	if c.phase == "warn" then
		if t >= c.impactAt then
			return impact
		end
		local sky = Balance.Comet.SkySeconds
		local alpha = math.clamp((t - (c.impactAt - sky)) / sky, 0, 1)
		return SeededPath.cometSky(c.id, impact, alpha)
	elseif c.phase == "ground" then
		return impact
	elseif c.phase == "carried" then
		local carrier = c.carrierId
		local pos = if carrier then playerPosition(carrier) else nil
		if pos then
			return pos + Vector3.new(0, CARRY_HEIGHT, 0)
		end
		return impact
	end
	return nil
end

function WorldStateController.crews(): Types.CrewStatePayload
	return crews
end

function WorldStateController.crewOf(userId: number): number
	return crewByUser[userId] or 0
end

-- Équipier du joueur local ?
function WorldStateController.isCrewmate(userId: number): boolean
	local player = Players.LocalPlayer
	if player == nil or userId == player.UserId then
		return false
	end
	local mine = crewByUser[player.UserId]
	return mine ~= nil and crewByUser[userId] == mine
end

function WorldStateController.requestWorld()
	local now = Clock.now()
	if now - lastWorldRequest < WORLD_REQUEST_INTERVAL and now >= lastWorldRequest then
		return
	end
	lastWorldRequest = now
	getRemotes().RequestWorld:FireServer()
end

return WorldStateController
