--!strict
-- WorldStateController (paquet client-world, docs/04 §13.3, §10.2, §10.5, GDD §12.5).
-- Miroir client de l'état du monde : ranchs (RanchSnapshot, RanchPatch numérotés : un trou →
-- RequestWorld), clôtures (Fence), créatures (ChaseEvent : pos(t) par SeededPath ; une créature dont
-- l'heure de fin est passée disparaît même sans « finish »), événements (EventState, MegaBeat ;
-- phases recalculées par EventClock entre deux messages), boops (BoopState), emotes (EmoteShow).
-- Applique EventState.offset à Clock.
-- Jamais d'état faux durable :
--   * après un trou de suite, les patchs sont ignorés et RequestWorld est renvoyé toutes les 3 s
--     (StateTimeouts « worldResync », jamais plus vite que le débit d'Intents) jusqu'à l'instantané ;
--   * aucun instantané 15 s après le Start (StateTimeouts « playerReady ») : même renvoi toutes les 3 s ;
--   * une créature est retirée à t0 + duration, un maintien de boop à endsAt + 0,5 s.
-- Start envoie UNE fois ReportBlocked avec StarterGui:GetCore("GetBlockedUserIds") sous pcall (liste
-- vide en cas d'échec, 200 au plus ; contrat v1.2, A21). Si GetCore a levé (CoreScripts pas encore
-- prêts, cas réel au démarrage), il est réessayé toutes les 2 s pendant 30 s ; dès qu'il répond une
-- liste non vide, elle repart UNE fois, au débit du serveur (1 / 10 s, CommunityService remplace la
-- liste) : sinon un joueur bloqué ne serait jamais filtré de la session (revue client-world).
-- Toute charge utile est vérifiée (types, nombres finis, bornes) : une charge hostile ou abîmée est
-- ignorée sans erreur ni avertissement. Une seule connexion Heartbeat (ménage à 4 Hz).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)
local SeededPath = require(Shared.Logic.SeededPath)
local Formulas = require(Shared.Logic.Formulas)
local StateTimeouts = require(Shared.Logic.StateTimeouts)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local Util = require(Client.World.Util)

local WorldStateController = {}

-- (slot, champs changés)
WorldStateController.RanchChanged = Signal.new() :: Signal.Signal<number, { string }>
-- (slot, uid, op)
WorldStateController.SquishyChanged = Signal.new() :: Signal.Signal<number, string, string>
-- (slot)
WorldStateController.FenceChanged = Signal.new() :: Signal.Signal<number>
WorldStateController.CreatureSpawned = Signal.new() :: Signal.Signal<Types.ChaseSpawn>
WorldStateController.CreatureFinished = Signal.new() :: Signal.Signal<Types.ChaseFinish>
WorldStateController.EventChanged = Signal.new() :: Signal.Signal<Types.EventStatePayload>
WorldStateController.MegaBeat = Signal.new() :: Signal.Signal<Types.MegaBeatPayload>
WorldStateController.BoopChanged = Signal.new() :: Signal.Signal<Types.BoopStatePayload>
WorldStateController.EmoteShown = Signal.new() :: Signal.Signal<Types.EmoteShowPayload>

local RANCHES = WorldLayout.Const.Ranches
local RESYNC = StateTimeouts.seconds("worldResync")
local FIRST_WAIT = StateTimeouts.seconds("playerReady")
local HOUSEKEEP = 0.25 -- s : ménage à 4 Hz (créatures et maintiens finis, renvois)
local BOOP_GRACE = 0.5 -- s après endsAt : maintien retiré sans message de fin (docs/04 §10.5)
local MAX_BLOCKED = 200
local BLOCKED_RETRY = 2 -- s entre deux essais de GetCore après un échec au Start
local BLOCKED_GIVE_UP = 30 -- s après le Start : plus aucun essai
local MAX_SQUISHIES = 84 -- par ranch (enclos + Bassin ≤ 24 ; marge pour un patch en vol)
local MAX_CREATURE_LIFE = 120 -- s : durée d'une créature acceptée au plus
local MAX_FENCE = 4

-- Champs de RanchPublic et leur sorte (un champ inconnu ou d'un mauvais type est ignoré)
local FIELDS: { [string]: string } = {
	slot = "number",
	userId = "number",
	name = "string",
	hidden = "boolean",
	R = "number",
	fame = "number",
	day = "number",
	mode = "string",
	shield = "boolean",
	boopable = "boolean",
	tiles = "table",
	vat = "boolean",
	pool = "boolean",
	vatFill = "number",
	growth = "table",
	carry = "string",
	ride = "string",
	saddle = "number",
	waiting = "string",
	theme = "string",
	flag = "string",
	title = "string",
	saddleColor = "string",
	trail = "string",
	best = "table",
}

local CREATURE_KINDS: { [string]: boolean } = {
	runaway = true,
	escape = true,
	wild = true,
	wildPersonal = true,
	golden = true,
	demo = true,
}

-- État du miroir
local ranches: { [number]: Types.RanchPublic } = {}
local squish: { [number]: { [string]: Types.PublicSquishy } } = {}
local fences: { [number]: { uids: { string }, reason: string } } = {}
local creatures: { [number]: Types.ChaseSpawn } = {}
local paths: { [number]: SeededPath.PathFn } = {}
local eventState: Types.EventStatePayload? = nil
local boopMap: { [string]: Types.BoopStatePayload } = {}

local isReady = false
local lastSeq = 0
local resyncing = false -- trou vu : patchs ignorés jusqu'au prochain instantané
local lastRequestAt = -math.huge
local startedAt = math.huge
local blockedSent = false
local blockedRetry = false -- GetCore a levé au Start : réessayé (housekeep) jusqu'à BLOCKED_GIVE_UP
local blockedTriedAt = -math.huge
local started = false
local connections: { RBXScriptConnection } = {}
local accum = 0

-- =============================================================================================
-- Lecture sûre des charges utiles
-- =============================================================================================

local function slotOf(key: any): number?
	local n = if type(key) == "string" then tonumber(key) elseif type(key) == "number" then key else nil
	return Util.int(n, 1, RANCHES)
end

local function validUid(uid: any): boolean
	return type(uid) == "string" and #uid >= 1 and #uid <= 8 and string.match(uid, "^[0-9a-z]+$") ~= nil
end

local function cleanGrowth(g: any): Types.Growth?
	if type(g) ~= "table" then
		return nil
	end
	return { G = Util.num(g.G, 0, 0), g = Util.num(g.g, 0, 0), t = Util.num(g.t, 0) }
end

local function cleanBest(b: any): { s: number, m: number, z: number, zg: number }?
	if type(b) ~= "table" then
		return nil
	end
	return {
		s = Util.int(b.s, 0, 65535) or 0,
		m = Util.int(b.m, 0, 255) or 0,
		z = Util.num(b.z, 0, 0),
		zg = Util.num(b.zg, 0, 0),
	}
end

local function cleanTiles(t: any): Types.Tiles?
	if type(t) ~= "table" then
		return nil
	end
	return {
		snack = Util.int(t.snack, 0, 1000) or 0,
		decor = Util.int(t.decor, 0, 1000) or 0,
		pens = Util.int(t.pens, 0, 1000) or 0,
		cozyBed = t.cozyBed == true,
		seen = Util.int(t.seen, 0, 2 ^ 31) or 0,
	}
end

-- Valeur nettoyée d'un champ de RanchPublic (nil : champ ignoré)
local function cleanField(field: string, value: any): any
	local kind = FIELDS[field]
	if kind == nil or type(value) ~= kind then
		return nil
	end
	if kind == "number" then
		return if Util.finite(value) then value else nil
	elseif kind == "string" then
		return Util.str(value, "", 64)
	elseif field == "growth" then
		return cleanGrowth(value)
	elseif field == "best" then
		return cleanBest(value)
	elseif field == "tiles" then
		return cleanTiles(value)
	end
	return value
end

-- Ranch vide (chaque champ a sa valeur « vide », remarque A27)
local function emptyRanch(slot: number): Types.RanchPublic
	return {
		slot = slot,
		userId = 0,
		name = "",
		hidden = false,
		R = 0,
		fame = 0,
		day = 0,
		mode = "cozy",
		shield = false,
		boopable = false,
		tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
		vat = false,
		pool = false,
		vatFill = 0,
		growth = { G = 0, g = 0, t = 0 },
		carry = "",
		ride = "",
		saddle = 0,
		waiting = "",
		theme = "",
		flag = "",
		title = "",
		saddleColor = "",
		trail = "",
		best = { s = 0, m = 0, z = 0, zg = 0 },
	}
end

-- Applique les champs de `src` à `ranch` ; rend la liste des champs changés
local function applyFields(ranch: any, src: any): { string }
	local changed = {}
	for field, value in src do
		if type(field) == "string" and field ~= "slot" then
			local v = cleanField(field, value)
			if v ~= nil then
				ranch[field] = v
				table.insert(changed, field)
			end
		end
	end
	table.sort(changed)
	return changed
end

local function cleanSquishy(rec: any): Types.PublicSquishy?
	if type(rec) ~= "table" then
		return nil
	end
	local at = if rec.at == "pool" then "pool" else "pen"
	return {
		s = Util.int(rec.s, 0, 65535) or 0,
		m = Util.int(rec.m, 0, 255) or 0,
		st = Util.int(rec.st, 0, 5) or 0,
		z = Util.num(rec.z, 1, 0),
		zg = Util.num(rec.zg, 0, 0),
		at = at,
		bf = Util.int(rec.bf, 0, 3) or 0,
		o = Util.str(rec.o, "", 32),
		ready = Util.num(rec.ready, 0, 0),
	}
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- =============================================================================================
-- Ranchs
-- =============================================================================================

local function requestWorld(force: boolean)
	local now = Clock.now()
	if now < lastRequestAt then
		lastRequestAt = now - RESYNC -- horloge reculée (décalage du serveur) : la demande est due
	end
	if not force and now - lastRequestAt < RESYNC then
		return
	end
	if Util.send("RequestWorld") then
		lastRequestAt = now
	end
end

local function onSnapshot(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local seq = Util.int(payload.seq, 0, 2 ^ 52)
	if seq == nil or type(payload.ranches) ~= "table" then
		return
	end
	local newRanches: { [number]: Types.RanchPublic } = {}
	for key, src in payload.ranches do
		local slot = slotOf(key)
		if slot and type(src) == "table" then
			local r: any = emptyRanch(slot)
			applyFields(r, src)
			newRanches[slot] = r
		end
	end
	local newSquish: { [number]: { [string]: Types.PublicSquishy } } = {}
	if type(payload.squishies) == "table" then
		for key, list in payload.squishies do
			local slot = slotOf(key)
			if slot and type(list) == "table" then
				local out = {}
				local n = 0
				for uid, rec in list do
					local clean = cleanSquishy(rec)
					if validUid(uid) and clean and n < MAX_SQUISHIES then
						out[uid] = clean
						n += 1
					end
				end
				newSquish[slot] = out
			end
		end
	end
	local oldSquish = squish
	ranches = newRanches
	squish = newSquish
	lastSeq = seq
	resyncing = false
	isReady = true
	for slot = 1, RANCHES do
		WorldStateController.RanchChanged:Fire(slot, { "*" })
		local before = oldSquish[slot] or {}
		local after = newSquish[slot] or {}
		for uid in before do
			if after[uid] == nil then
				WorldStateController.SquishyChanged:Fire(slot, uid, "remove")
			end
		end
		for uid in after do
			WorldStateController.SquishyChanged:Fire(slot, uid, if before[uid] then "update" else "add")
		end
	end
end

local function applyOp(op: any)
	if type(op) ~= "table" then
		return
	end
	local slot = slotOf(op.slot)
	if slot == nil or not validUid(op.uid) then
		return
	end
	local list = squish[slot]
	if list == nil then
		list = {}
		squish[slot] = list
	end
	if op.op == "remove" then
		if list[op.uid] ~= nil then
			list[op.uid] = nil
			WorldStateController.SquishyChanged:Fire(slot, op.uid, "remove")
		end
	elseif op.op == "add" or op.op == "update" then
		local clean = cleanSquishy(op.rec)
		if clean == nil then
			return
		end
		local existed = list[op.uid] ~= nil
		if not existed and count(list) >= MAX_SQUISHIES then
			return
		end
		list[op.uid] = clean
		WorldStateController.SquishyChanged:Fire(slot, op.uid, if existed then "update" else "add")
	end
end

local function onPatch(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local seq = Util.int(payload.seq, 0, 2 ^ 52)
	if seq == nil then
		return
	end
	if not isReady or resyncing then
		return -- en attente de l'instantané : patchs ignorés
	end
	if seq <= lastSeq then
		return -- doublon ou message en retard
	end
	if seq ~= lastSeq + 1 then
		resyncing = true
		requestWorld(false)
		return
	end
	lastSeq = seq
	if type(payload.ranches) == "table" then
		for key, src in payload.ranches do
			local slot = slotOf(key)
			if slot and type(src) == "table" then
				local r: any = ranches[slot]
				if r == nil then
					r = emptyRanch(slot)
					ranches[slot] = r
				end
				local changed = applyFields(r, src)
				if #changed > 0 then
					WorldStateController.RanchChanged:Fire(slot, changed)
				end
			end
		end
	end
	if type(payload.ops) == "table" then
		for i, op in payload.ops do
			if type(i) == "number" and i <= 2000 then
				applyOp(op)
			end
		end
	end
end

local function onFence(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local slot = slotOf(payload.slot)
	if slot == nil or type(payload.uids) ~= "table" then
		return
	end
	local reason = if payload.reason == "rush" or payload.reason == "petsit" then payload.reason else ""
	local uids = {}
	for _, uid in ipairs(payload.uids) do
		if validUid(uid) and #uids < MAX_FENCE then
			table.insert(uids, uid)
		end
	end
	if #uids == 0 then
		reason = ""
	end
	fences[slot] = { uids = uids, reason = reason }
	WorldStateController.FenceChanged:Fire(slot)
end

-- =============================================================================================
-- Créatures
-- =============================================================================================

local function cleanSpawn(s: any): Types.ChaseSpawn?
	if type(s) ~= "table" then
		return nil
	end
	local id = Util.int(s.id, 1, 65535)
	if id == nil or type(s.kind) ~= "string" or not CREATURE_KINDS[s.kind] then
		return nil
	end
	if not Util.finite(s.t0) or not Util.finite(s.duration) or s.duration <= 0 then
		return nil
	end
	local center = { x = 0, z = 0 }
	if type(s.center) == "table" then
		center = { x = Util.num(s.center.x, 0, -5000, 5000), z = Util.num(s.center.z, 0, -5000, 5000) }
	end
	return {
		id = id,
		kind = s.kind,
		species = Util.int(s.species, 0, 65535) or 0,
		mutation = Util.int(s.mutation, 0, 255) or 0,
		size = Util.num(s.size, 1, 0),
		stars = Util.int(s.stars, 0, 5) or 0,
		ownerSlot = Util.int(s.ownerSlot, 0, RANCHES) or 0,
		booperSlot = Util.int(s.booperSlot, 0, RANCHES) or 0,
		uid = if validUid(s.uid) then s.uid else "",
		path = if s.path == "hop" then "hop" else "escape",
		seed = Util.num(s.seed, 0),
		t0 = s.t0,
		startNode = Util.int(s.startNode, 0, 100000) or 0,
		awayAngle = Util.num(s.awayAngle, 0, -100, 100),
		center = center,
		speed = Util.num(s.speed, 0, 0, 200),
		duration = math.min(s.duration, MAX_CREATURE_LIFE),
		personal = s.personal == true,
	}
end

local function finishCreature(id: number, reason: string, bySlot: number, t: number)
	if creatures[id] == nil then
		return
	end
	creatures[id] = nil
	paths[id] = nil
	local finish: any = { id = id, reason = reason, bySlot = bySlot, t = t }
	WorldStateController.CreatureFinished:Fire(finish)
end

local function onChaseEvent(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local now = Clock.now()
	if type(payload.finishes) == "table" then
		for _, f in ipairs(payload.finishes) do
			if type(f) == "table" then
				local id = Util.int(f.id, 1, 65535)
				if id then
					local reason = if f.reason == "caught" or f.reason == "returned"
						then f.reason
						else "expired"
					finishCreature(id, reason, Util.int(f.bySlot, 0, RANCHES) or 0, Util.num(f.t, now))
				end
			end
		end
	end
	if type(payload.spawns) == "table" then
		for _, raw in ipairs(payload.spawns) do
			local s = cleanSpawn(raw)
			-- une créature déjà affichée (sendActive puis paquet groupé) ou déjà finie est ignorée
			if s and creatures[s.id] == nil and s.t0 + s.duration > now then
				local ok, fn = pcall(SeededPath.fromSpawn, s)
				if ok and type(fn) == "function" then
					creatures[s.id] = s
					paths[s.id] = fn
					WorldStateController.CreatureSpawned:Fire(s)
				end
			end
		end
	end
end

-- =============================================================================================
-- Événements, boops, emotes
-- =============================================================================================

local function onEventState(payload: any)
	if type(payload) ~= "table" or type(payload.features) ~= "table" then
		return
	end
	if type(payload.mega) ~= "table" or type(payload.gauge) ~= "table" or type(payload.rush) ~= "table" then
		return
	end
	if type(payload.spectacle) ~= "table" then
		payload.spectacle = { queue = {} }
	elseif type(payload.spectacle.queue) ~= "table" then
		payload.spectacle.queue = {}
	end
	if Util.finite(payload.offset) and math.abs(payload.offset) < 1e9 then
		if Clock.getOffset() ~= payload.offset then
			Clock.setOffset(payload.offset)
		end
	end
	eventState = payload
	WorldStateController.EventChanged:Fire(payload)
end

local function onMegaBeat(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if not (Util.finite(payload.points) and Util.finite(payload.target) and Util.finite(payload.t)) then
		return
	end
	local beat: Types.MegaBeatPayload = {
		points = Util.num(payload.points, 0, 0),
		target = Util.num(payload.target, 1, 0),
		presses = Util.num(payload.presses, 0, 0),
		t = payload.t,
	}
	WorldStateController.MegaBeat:Fire(beat)
end

local function boopKey(b: Types.BoopStatePayload): string
	return tostring(b.booperId) .. ":" .. tostring(b.ownerId) .. ":" .. b.uid
end

local function onBoopState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local booperId = Util.int(payload.booperId, 1, 2 ^ 53)
	local ownerId = Util.int(payload.ownerId, 1, 2 ^ 53)
	if booperId == nil or ownerId == nil or not validUid(payload.uid) or not Util.finite(payload.endsAt) then
		return
	end
	local state = payload.state
	if state ~= "hold" and state ~= "done" and state ~= "cancel" then
		return
	end
	local b: Types.BoopStatePayload =
		{ booperId = booperId, ownerId = ownerId, uid = payload.uid, endsAt = payload.endsAt, state = state }
	local key = boopKey(b)
	if state == "hold" then
		boopMap[key] = b
	else
		boopMap[key] = nil
	end
	WorldStateController.BoopChanged:Fire(b)
end

local function onEmote(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local userId = Util.int(payload.userId, 1, 2 ^ 53)
	local kind = Util.int(payload.kind, 1, 3)
	if userId == nil or kind == nil then
		return
	end
	WorldStateController.EmoteShown:Fire({
		userId = userId,
		kind = kind,
		emote = Util.str(payload.emote, "", 32),
	})
end

-- =============================================================================================
-- Liste de blocage (une fois)
-- =============================================================================================

local function blockedList(): ({ number }, boolean)
	local ok, list = pcall(StarterGui.GetCore, StarterGui, "GetBlockedUserIds")
	local out: { number } = {}
	if not ok or type(list) ~= "table" then
		return out, false
	end
	for _, id in ipairs(list) do
		if #out >= MAX_BLOCKED then
			break
		end
		local n = Util.int(id, 1, 2 ^ 53)
		if n then
			table.insert(out, n)
		end
	end
	return out, true
end

local function reportBlocked()
	if blockedSent then
		return
	end
	blockedSent = true
	local list, ok = blockedList()
	Util.send("ReportBlocked", list)
	blockedRetry = not ok
	blockedTriedAt = Clock.now()
end

-- Nouvel essai de GetCore après un échec au Start (ménage à 4 Hz) : la vraie liste part une fois
local function retryBlocked(now: number)
	if not blockedRetry then
		return
	end
	if now - startedAt > BLOCKED_GIVE_UP or now < startedAt then
		blockedRetry = false -- abandon : la liste vide envoyée au Start reste en vigueur
		return
	end
	if now - blockedTriedAt < BLOCKED_RETRY then
		return
	end
	blockedTriedAt = now
	local list, ok = blockedList()
	if not ok then
		return
	end
	-- liste vide : rien de bloqué, la liste vide du Start est la bonne ; sinon elle part dès que le
	-- débit du client (1 / 10 s, celui du serveur) le permet, réessayée au prochain pas d'ici là
	if #list == 0 or Util.send("ReportBlocked", list) then
		blockedRetry = false
	end
end

-- =============================================================================================
-- Ménage (4 Hz) : créatures et maintiens finis à leur heure, renvois de RequestWorld
-- =============================================================================================

local function housekeep()
	local now = Clock.now()
	for id, s in creatures do
		if now >= s.t0 + s.duration then
			finishCreature(id, "expired", 0, now)
		end
	end
	for key, b in boopMap do
		if now > b.endsAt + BOOP_GRACE then
			boopMap[key] = nil
			local ended: Types.BoopStatePayload = {
				booperId = b.booperId,
				ownerId = b.ownerId,
				uid = b.uid,
				endsAt = b.endsAt,
				state = "cancel",
			}
			WorldStateController.BoopChanged:Fire(ended)
		end
	end
	if resyncing or (not isReady and now - startedAt >= FIRST_WAIT) then
		requestWorld(false)
	end
	retryBlocked(now)
end

-- Pas du ménage (exposé aux specs ; appelé par la connexion Heartbeat)
function WorldStateController._step(dt: number)
	accum += Util.num(dt, 0, 0, 1)
	if accum < HOUSEKEEP then
		return
	end
	accum = 0
	housekeep()
end

-- =============================================================================================
-- Cycle de vie
-- =============================================================================================

-- Création des états ; aucun yield long
function WorldStateController.Init()
	ranches = {}
	squish = {}
	fences = {}
	creatures = {}
	paths = {}
	boopMap = {}
end

local function listen(name: string, handler: (any) -> (), unreliable: boolean?)
	local remote: any = if unreliable then Util.unreliable(name) else Util.remote(name)
	if remote == nil then
		return
	end
	table.insert(
		connections,
		remote.OnClientEvent:Connect(function(payload: any)
			Util.guard("WorldStateController." .. name, handler, payload)
		end)
	)
end

-- Connexions et boucles
function WorldStateController.Start()
	if started then
		return
	end
	started = true
	startedAt = Clock.now()
	listen("RanchSnapshot", onSnapshot)
	listen("RanchPatch", onPatch)
	listen("Fence", onFence)
	listen("ChaseEvent", onChaseEvent)
	listen("EventState", onEventState)
	listen("MegaBeat", onMegaBeat, true)
	listen("BoopState", onBoopState)
	listen("EmoteShow", onEmote)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			Util.guard("WorldStateController.step", WorldStateController._step, dt)
		end)
	)
	reportBlocked()
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Premier RanchSnapshot reçu
function WorldStateController.ready(): boolean
	return isReady
end

-- Ranch du joueur local (0 = aucun)
function WorldStateController.mySlot(): number
	local player = Players.LocalPlayer
	if player == nil then
		return 0
	end
	local id = player.UserId
	for slot, r in ranches do
		if r.userId == id and id ~= 0 then
			return slot
		end
	end
	return 0
end

-- État public d'un ranch
function WorldStateController.ranch(slot: number): Types.RanchPublic?
	if type(slot) ~= "number" then
		return nil
	end
	return ranches[slot]
end

-- Squishies visibles d'un ranch (copie : l'appelant peut la parcourir sans risque)
function WorldStateController.squishies(slot: number): { [string]: Types.PublicSquishy }
	local list = if type(slot) == "number" then squish[slot] else nil
	if list == nil then
		return {}
	end
	return table.clone(list)
end

local EMPTY: { [string]: Types.PublicSquishy } = table.freeze({}) :: any

-- Squishies visibles d'un ranch SANS copie, pour le rendu à chaque image (RanchRenderer : budget PS4) :
-- LECTURE SEULE ; la table change entre deux images (handlers des remotes), jamais pendant un parcours
function WorldStateController.squishiesView(slot: number): { [string]: Types.PublicSquishy }
	local list = if type(slot) == "number" then squish[slot] else nil
	return list or EMPTY
end

-- Taille prédite (z + G(t) − zg) ; 0 pour un squishy inconnu
function WorldStateController.sizeOf(slot: number, uid: string, t: number?): number
	local list = if type(slot) == "number" then squish[slot] else nil
	local rec = if list and type(uid) == "string" then list[uid] else nil
	local r = if type(slot) == "number" then ranches[slot] else nil
	if rec == nil or r == nil then
		return 0
	end
	local now = if Util.finite(t) then t :: number else Clock.now()
	local G = Formulas.G(r.growth, now)
	return Formulas.sizeAt(rec :: any, G)
end

-- Clôture d'un ranch (uids, raison)
function WorldStateController.fence(slot: number): ({ string }, string)
	local f = if type(slot) == "number" then fences[slot] else nil
	if f == nil then
		return {}, ""
	end
	return table.clone(f.uids), f.reason
end

-- Créatures actives visibles par ce joueur (le serveur n'envoie que celles qu'il peut voir)
function WorldStateController.creatures(): { [number]: Types.ChaseSpawn }
	local now = Clock.now()
	local out = {}
	for id, s in creatures do
		if now < s.t0 + s.duration then
			out[id] = s
		end
	end
	return out
end

-- Position d'une créature (SeededPath), nil si inconnue ou finie
function WorldStateController.creaturePos(id: number, t: number?): Vector3?
	local fn = if type(id) == "number" then paths[id] else nil
	local s = if type(id) == "number" then creatures[id] else nil
	if fn == nil or s == nil then
		return nil
	end
	local at = if Util.finite(t) then t :: number else Clock.now()
	local ok, pos = pcall(fn, at)
	if ok and Util.vec(pos) then
		return pos
	end
	return nil
end

-- Dernier EventState
function WorldStateController.event(): Types.EventStatePayload?
	return eventState
end

-- Maintiens de boop en cours (clé « booperId:ownerId:uid »)
function WorldStateController.boops(): { [string]: Types.BoopStatePayload }
	return table.clone(boopMap)
end

-- Nombre d'états ouverts (specs : ménage)
function WorldStateController.stats(): { [string]: number }
	return {
		ranches = count(ranches),
		creatures = count(creatures),
		boops = count(boopMap),
		seq = lastSeq,
		resyncing = if resyncing then 1 else 0,
	}
end

-- Coupe les connexions (fin de session, specs)
function WorldStateController._stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	started = false
end

return WorldStateController
