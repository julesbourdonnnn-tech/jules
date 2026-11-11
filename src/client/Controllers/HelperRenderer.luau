--!strict
-- HelperRenderer (lot B5, étape 3 ; GDD v2.0 §4.28 ; docs/04 §27.5 HelperPress, §27.7, §27.11
-- INT-V2-ORDER ; plan B5 D13 à D16, D29) : les Plopettes dessinées dans le monde, derrière
-- l'interrupteur Helpers (vu par le client à travers les attributs Helpers et HelperMode des ranchs :
-- absents interrupteur coupé ou profil v1, rien n'est alors dessiné, rien n'est branché par image).
--
--   HelperRenderer.Init()  / Start()        -- ordre du client : juste après ChaseRenderer
--   HelperRenderer._step(dt)                -- une image (RenderStepped, specs)
--   HelperRenderer._stop()                  -- coupe tout, rend chaque instance (fin, specs)
--   HelperRenderer.stats()                  -- compteurs (specs, Diagnostics)
--   HelperRenderer._state(slot, k)          -- état d'une Plopette dessinée (specs)
--   HelperRenderer._configure(sources)      -- specs : son, gouttes, rebond capturés
--
-- État : attributs du modèle Wobbleton/Ranches/<k> posés par le serveur (HelperService par
-- RanchService.setV2Attributes, seulement quand ils changent) : Helpers (0 … 6 : Plopettes 1 … n,
-- 6 = la Plume) et HelperMode ("active" | "nap" | "paused"). Une connexion AttributeChanged par
-- modèle (comme Render/RanchV2) ; la boucle par image, l'écoute de HelperPress et celle du miroir ne
-- sont branchées que tant qu'un ranch porte au moins une Plopette (D29).
-- Dessin : SEULEMENT pour un ranch en détail complet (RanchRenderer.detail, D14 : le ranch courant et
-- ses 2 voisins), relu 4 fois par seconde ; un ranch qui quitte le détail complet, perd ses
-- Plopettes (interrupteur coupé, départ du propriétaire) ou change de propriétaire rend TOUTES ses
-- instances à la réserve (Render/HelperKit) à l'image même ; quand il y revient, les Plopettes
-- reparaissent à la maisonnette (ou endormies). Système « helpers » de Render/VisualBudget : 152
-- pièces déclarées (170 du GDD §11.5 moins les 18 de la maisonnette), 5 par Plopette dessinée ; une
-- réservation refusée laisse la Plopette sans dessin (jamais au-delà du budget).
-- Saut (D15) : HelperPress { ownerId, presses = { { helper, uid, tPress } } } (non fiable, regroupé
-- par tick ; jusqu'à 6 sauts ensemble au réveil). Lecture hostile sûre : une table, 6 sauts au plus,
-- helper entier 1 … 6 et au plus Helpers, uid chaîne de 1 à 32 caractères, tPress fini à 5 s au plus
-- de Clock.now() ; tout autre message est ignoré sans trace et sans instance. La Plopette part de là où
-- elle est DESSINÉE et atterrit à côté du squishy exactement à tPress (horloge du serveur) : durée =
-- tPress − maintenant, entre 0,1 et 3 s (au-delà de 3 s, le départ attend tPress − 3) ; un tPress
-- passé (paquet en retard) la pose sur sa cible sans arc. Son HelperHop au décollage (repli Boing,
-- 6 au plus par image), seulement pour mon ranch et le ranch courant.
-- « Pop » : RanchRenderer.play(slot, uid, "press") et 6 gouttes au plus, SEULEMENT si le miroir montre
-- la pression : WorldStateController.SquishyChanged de ce squishy avec un `ready` plus tard que tPress,
-- vu entre tPress − 0,3 s et tPress + 0,8 s. Sinon (saut abandonné par le serveur, joueur plus rapide,
-- règle des 12 studs : aucun message n'arrive jamais) l'atterrissage est doux. Aucun texte « +N ».
-- Positions locales et réparées toutes seules (D16) : départ devant la maisonnette (rangée devant la
-- porte de WorldLayout.helperHouse), puis à côté de la dernière cible ; le saut suivant part de là
-- où la Plopette est dessinée (un paquet perdu se répare au suivant).
-- Sieste : le saut en cours finit sans « pop », retour en sautillant à la maisonnette, sommeil en rangée
-- devant la porte avec UNE étiquette « z » (UI/WorldText) pour la maison ; réveil : elles attendent le
-- message suivant. Pause : le saut en cours finit sans « pop », puis elles attendent.
-- Coût : un seul workspace:BulkMoveTo par image avec des tableaux réutilisés ; les Plopettes au repos
-- des ranchs des autres à 15 Hz ; aucune table créée par image en régime établi.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Sounds = require(Shared.Config.Sounds)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Util = require(Client.World.Util)
local WorldStateController = require(Client.Controllers.WorldStateController)
local RanchRenderer = require(Client.Controllers.RanchRenderer)
local AudioController = require(Client.Controllers.AudioController)
local WorldText = require(Client.UI.WorldText)
local VisualBudget = require(Client.Render.VisualBudget)
local RanchV2 = require(Client.Render.RanchV2)
local HelperKit = require(Client.Render.HelperKit)

local HelperRenderer = {}

local RANCHES = WorldLayout.Const.Ranches
local MAX_HELPERS = HelperKit.COUNT
local SYSTEM = "helpers"
local LIMITS = table.freeze({ parts = 152, particles = 0, lights = 0 })

-- Saut (D15)
local MIN_HOP, MAX_HOP = 0.1, 3 -- s
local WINDOW = 5 -- s : tPress lu à 5 s au plus de maintenant
local POP_BEFORE, POP_AFTER = 0.3, 0.8 -- s : fenêtre où le miroir doit montrer la pression
local POP_DROPS = 6
local SOUNDS_PER_FRAME = 6
local BESIDE = 1.2 -- studs à côté de la cible, au moins
local GAP = 0.6 -- studs entre le bord du squishy et la Plopette
local HOME_SPEED = 12 -- studs par seconde pour rentrer à la maisonnette
local HOME_MIN, HOME_MAX = 0.5, 3 -- s
-- Rangée devant la porte (repère du ranch : porte de la maisonnette en (−28, 0, 60), cabane derrière)
local ROW_X, ROW_Z, ROW_STEP = -28, 59.2, 0.85
local LOOK_Z = 50 -- elles regardent l'enclos
local Z_HEIGHT = 2.2 -- studs au-dessus de la Plopette du milieu
local Z_DISTANCE = 60
-- Cadences
local DETAIL_EVERY = 0.25 -- s entre deux lectures du détail
local IDLE_HZ = 15 -- Plopettes au repos des ranchs des autres
local UID_MAX = 32

type HopState = "idle" | "wait" | "jump" | "home" | "sleep"
type PopState = "none" | "wait" | "seen" | "done"

type Hop = {
	k: number, -- rang (1 … Helpers) = numéro de la Plopette (6 = la Plume)
	kit: HelperKit.Kit?,
	state: HopState,
	pos: Vector3, -- pied dessiné
	yaw: number,
	p0: Vector3,
	p1: Vector3,
	t0: number,
	t1: number,
	height: number,
	uid: string,
	tPress: number,
	pop: PopState,
	phase: number,
	toSleep: boolean, -- rentrer dormir après ce saut (sieste)
}

type Ranch = {
	slot: number,
	model: Instance?,
	conn: RBXScriptConnection?,
	count: number,
	mode: string,
	ownerId: number,
	full: boolean,
	hops: { Hop },
	label: BillboardGui?,
	idleAcc: number,
}

local ranches: { [number]: Ranch } = {}
local active = 0 -- ranchs qui portent au moins une Plopette
local started = false
local live: { RBXScriptConnection } = {} -- branchées tant que active > 0
local watchConn: RBXScriptConnection? = nil
local folder: Folder? = nil
local declared = false
local detailAcc = 0
local soundsThisFrame = 0
local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}

local counters = {
	messages = 0,
	ignored = 0,
	jumps = 0,
	pops = 0,
	soft = 0,
	sounds = 0,
	refused = 0,
	steps = 0,
}

-- Sources remplaçables par les specs : son, gouttes du « pop », rebond du squishy
local sources: {
	play: ((string) -> ())?,
	drops: ((Vector3, Color3, number) -> ())?,
	press: ((number, string) -> ())?,
} =
	{}

-- =============================================================================================
-- Outils
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function mySlot(): number
	return Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
end

local function reducedMotion(): boolean
	return Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
end

local function ranchModel(slot: number): Instance?
	local root = workspace:FindFirstChild("Wobbleton")
	local list = root and root:FindFirstChild("Ranches")
	return list and list:FindFirstChild(tostring(slot))
end

local function clientFolder(): Folder
	local f = folder
	if f and f.Parent ~= nil then
		return f
	end
	local root = workspace:FindFirstChild("ClientWorld")
	if root == nil then
		local created = Instance.new("Folder")
		created.Name = "ClientWorld"
		created.Parent = workspace
		root = created
	end
	local sub = (root :: Instance):FindFirstChild("Helpers")
	if sub == nil or not sub:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = "Helpers"
		created.Parent = root
		sub = created
	end
	folder = sub :: Folder
	return sub :: Folder
end

local function ground(p: Vector3): Vector3
	return Vector3.new(p.X, WorldLayout.groundY(p.X, p.Z), p.Z)
end

-- Place k de la rangée devant la porte de la maisonnette (monde, au sol)
local function rowSpot(slot: number, k: number): Vector3
	return ground(WorldLayout.toWorld(slot, Vector3.new(ROW_X + (k - 3.5) * ROW_STEP, 0, ROW_Z)))
end

local function yawToward(from: Vector3, to: Vector3, fallback: number): number
	local dx, dz = to.X - from.X, to.Z - from.Z
	if dx * dx + dz * dz < 1e-6 then
		return fallback
	end
	return math.atan2(-dx, -dz)
end

local function homeYaw(slot: number, at: Vector3): number
	local look = WorldLayout.toWorld(slot, Vector3.new(ROW_X, 0, LOOK_Z))
	return yawToward(at, look, 0)
end

local function playSound(name: string)
	local fn = sources.play
	if fn then
		pcall(fn, name)
		return
	end
	Util.safe("AudioController.play", nil, AudioController.play, name)
end

local function soundOf(name: string, fallback: string): string
	local def: any = (Sounds :: any)[name]
	local has = type(def) == "table" and type(def.id) == "string" and def.id ~= ""
	return if has then name else fallback
end

-- =============================================================================================
-- Dessin d'une Plopette
-- =============================================================================================

local function ensureDeclared()
	if not declared then
		declared = VisualBudget.declare(SYSTEM, LIMITS)
	end
end

local function drawKit(hop: Hop)
	if hop.kit ~= nil then
		return
	end
	ensureDeclared()
	local recipe = HelperKit.recipe(hop.k)
	if recipe == nil then
		return
	end
	local n = #recipe.pieces
	if not VisualBudget.take(SYSTEM, n) then
		counters.refused += 1
		return
	end
	local kit = HelperKit.take(hop.k, clientFolder())
	if kit == nil then
		VisualBudget.release(SYSTEM, n)
		return
	end
	hop.kit = kit
end

local function dropKit(hop: Hop)
	local kit = hop.kit
	if kit == nil then
		return
	end
	hop.kit = nil
	VisualBudget.release(SYSTEM, #kit.parts)
	HelperKit.release(kit)
end

-- Pose d'une Plopette dans les tableaux de BulkMoveTo
local function queue(hop: Hop, lift: number, tilt: number)
	local kit = hop.kit
	if kit == nil then
		return
	end
	local root = CFrame.new(hop.pos.X, hop.pos.Y + lift, hop.pos.Z) * CFrame.Angles(0, hop.yaw, 0)
	if tilt ~= 0 then
		root *= CFrame.Angles(tilt, 0, 0)
	end
	local parts, offsets = kit.parts, kit.offsets
	for i = 1, #parts do
		table.insert(bulkParts, parts[i])
		table.insert(bulkCFrames, root * offsets[i])
	end
end

local function releaseLabel(r: Ranch)
	local gui = r.label
	if gui then
		r.label = nil
		pcall(WorldText.release, gui)
	end
end

-- Une seule étiquette « z » par maisonnette, sur la Plopette du milieu de la rangée
local function refreshLabel(r: Ranch)
	local sleeping = r.full and r.mode == "nap"
	local anchor: BasePart? = nil
	if sleeping then
		for _, hop in r.hops do
			if hop.state ~= "sleep" then
				sleeping = false
				break
			end
		end
	end
	if sleeping then
		local mid = r.hops[math.max(1, (#r.hops + 1) // 2)]
		local kit = if mid then mid.kit else nil
		anchor = if kit then kit.parts[1] else nil
	end
	if anchor == nil then
		releaseLabel(r)
		return
	end
	local gui = r.label
	if gui and gui.Adornee == anchor then
		return
	end
	releaseLabel(r)
	local ok, created = pcall(WorldText.create, anchor :: BasePart, {
		kind = "plus",
		maxDistance = Z_DISTANCE,
		studsOffset = Vector3.new(0, Z_HEIGHT, 0),
		name = "HelperNap",
	})
	if ok and created then
		pcall(WorldText.setText, created, "z")
		r.label = created
	end
end

-- =============================================================================================
-- État d'un ranch
-- =============================================================================================

local function newHop(r: Ranch, k: number): Hop
	local at = rowSpot(r.slot, k)
	return {
		k = k,
		kit = nil,
		state = if r.mode == "nap" then "sleep" else "idle",
		pos = at,
		yaw = homeYaw(r.slot, at),
		p0 = at,
		p1 = at,
		t0 = 0,
		t1 = 0,
		height = 0,
		uid = "",
		tPress = 0,
		pop = "none",
		phase = k * 0.37,
		toSleep = false,
	}
end

-- Rend toutes les instances d'un ranch (même image)
local function undraw(r: Ranch)
	releaseLabel(r)
	for _, hop in r.hops do
		dropKit(hop)
	end
end

local function syncCount(r: Ranch)
	for k = #r.hops + 1, r.count do
		local hop = newHop(r, k)
		table.insert(r.hops, hop)
		if r.full then
			drawKit(hop)
		end
	end
	for k = #r.hops, r.count + 1, -1 do
		dropKit(r.hops[k])
		table.remove(r.hops, k)
	end
end

-- Rentrer à la maisonnette (sieste) : petit saut vers sa place de la rangée
local function goHome(r: Ranch, hop: Hop, now: number)
	local spot = rowSpot(r.slot, hop.k)
	local dist = (spot - hop.pos).Magnitude
	hop.toSleep = false
	if dist < 0.05 then
		hop.pos = spot
		hop.state = "sleep"
		hop.yaw = homeYaw(r.slot, spot)
		return
	end
	hop.p0 = hop.pos
	hop.p1 = spot
	hop.t0 = now
	hop.t1 = now + math.clamp(dist / HOME_SPEED, HOME_MIN, HOME_MAX)
	hop.height = math.clamp(0.5 + dist * 0.08, 0.6, 2)
	hop.yaw = yawToward(hop.pos, spot, hop.yaw)
	hop.state = "home"
end

-- Sieste ou pause : chaque saut en cours finit sans « pop » ; en sieste, retour à la maisonnette
local function onMode(r: Ranch, now: number)
	for _, hop in r.hops do
		if hop.pop == "wait" or hop.pop == "seen" then
			hop.pop = "none"
			counters.soft += 1
		end
		if r.mode == "nap" then
			if hop.state == "jump" or hop.state == "wait" then
				hop.toSleep = true
			elseif hop.state == "idle" then
				goHome(r, hop, now)
			end
		else
			hop.toSleep = false
			if hop.state == "sleep" then
				hop.state = "idle" -- réveil : elles attendent le message suivant
			end
		end
	end
	refreshLabel(r)
end

local function readCount(model: Instance): number
	local ok, v = pcall(function()
		return model:GetAttribute("Helpers")
	end)
	if not ok or not finite(v) then
		return 0
	end
	return math.clamp(math.floor(v), 0, MAX_HELPERS)
end

local function readMode(model: Instance): string
	local ok, v = pcall(function()
		return model:GetAttribute("HelperMode")
	end)
	if ok and (v == "nap" or v == "paused") then
		return v
	end
	return "active"
end

local function ownerOf(slot: number): number
	local rec: any = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
	if type(rec) == "table" and finite(rec.userId) then
		return rec.userId
	end
	return 0
end

local connectLive, disconnectLive

-- Relit les attributs d'un ranch (signal AttributeChanged, premier regard)
local function refreshRanch(slot: number)
	local r = ranches[slot]
	if r == nil or r.model == nil then
		return
	end
	local model = r.model :: Instance
	local count = readCount(model)
	local mode = readMode(model)
	local before = r.count
	if count == 0 then
		if before > 0 then
			undraw(r)
			table.clear(r.hops)
			r.count = 0
			r.full = false
			active -= 1
			if active <= 0 then
				active = 0
				disconnectLive()
			end
		end
		r.mode = mode
		return
	end
	if before == 0 then
		active += 1
		r.ownerId = ownerOf(slot)
		r.mode = mode
		r.full = false
		detailAcc = DETAIL_EVERY -- détail lu à la prochaine image
		connectLive()
	end
	r.count = count
	syncCount(r)
	if mode ~= r.mode then
		r.mode = mode
		onMode(r, Clock.now())
	end
end

local function watchRanch(slot: number, model: Instance)
	local r = ranches[slot]
	if r == nil then
		r = {
			slot = slot,
			model = nil,
			conn = nil,
			count = 0,
			mode = "active",
			ownerId = 0,
			full = false,
			hops = {},
			label = nil,
			idleAcc = 0,
		}
		ranches[slot] = r
	end
	local rr = r :: Ranch
	if rr.model == model then
		return
	end
	if rr.conn then
		rr.conn:Disconnect()
	end
	rr.model = model
	rr.conn = model.AttributeChanged:Connect(function(name: string)
		if name == "Helpers" or name == "HelperMode" then
			Util.guard("HelperRenderer.attribute", refreshRanch, slot)
		end
	end)
	refreshRanch(slot)
end

-- Écoute les modèles des 16 ranchs ; vrai quand tous sont écoutés
local function watchAll(): boolean
	local all = true
	for slot = 1, RANCHES do
		local model = ranchModel(slot)
		if model == nil then
			all = false
		else
			watchRanch(slot, model)
		end
	end
	return all
end

-- =============================================================================================
-- Message HelperPress (lecture hostile sûre)
-- =============================================================================================

local function slotOfOwner(ownerId: number): number
	for slot, r in ranches do
		if r.count > 0 and r.ownerId == ownerId then
			return slot
		end
	end
	return 0
end

-- Point d'atterrissage à côté du squishy, du côté d'où vient la Plopette
local function landingFor(slot: number, uid: string, from: Vector3): Vector3?
	local center = Util.safe("RanchRenderer.positionOf", nil, RanchRenderer.positionOf, slot, uid)
	if typeof(center) ~= "Vector3" then
		return nil
	end
	local c = center :: Vector3
	local floor = WorldLayout.groundY(c.X, c.Z)
	local radius = math.max(0.5, c.Y - floor)
	local dx, dz = from.X - c.X, from.Z - c.Z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-3 then
		local side = WorldLayout.toWorld(slot, Vector3.new(1, 0, 0)) - WorldLayout.toWorld(slot, Vector3.zero)
		dx, dz, len = side.X, side.Z, math.max(1e-3, side.Magnitude)
	end
	local off = math.max(BESIDE, radius + GAP)
	local x, z = c.X + dx / len * off, c.Z + dz / len * off
	return Vector3.new(x, WorldLayout.groundY(x, z), z)
end

local function startJump(r: Ranch, hop: Hop, uid: string, tPress: number, now: number)
	local from = hop.pos
	local target = landingFor(r.slot, uid, from)
	if target == nil then
		return
	end
	local land = target :: Vector3
	-- un saut en cours est remplacé : il repart de là où il est dessiné (réparation, D16)
	if hop.pop == "wait" or hop.pop == "seen" then
		counters.soft += 1
	end
	hop.uid = uid
	hop.tPress = tPress
	hop.pop = "wait"
	hop.toSleep = false
	hop.p0 = from
	hop.p1 = land
	hop.yaw = yawToward(from, land, hop.yaw)
	counters.jumps += 1
	if tPress <= now then
		-- paquet en retard : posée sur sa cible, sans arc
		hop.pos = land
		hop.t0, hop.t1 = now, now
		hop.state = "idle"
		return
	end
	hop.t1 = math.max(tPress, now + MIN_HOP)
	hop.t0 = math.max(now, hop.t1 - MAX_HOP)
	local dist = (land - from).Magnitude
	local height = math.clamp(0.6 + dist * 0.12, 0.8, 3)
	hop.height = if reducedMotion() then height * 0.5 else height
	hop.state = "wait"
end

local function onPress(payload: any)
	counters.messages += 1
	local now = Clock.now()
	if type(payload) ~= "table" or not finite(payload.ownerId) or type(payload.presses) ~= "table" then
		counters.ignored += 1
		return
	end
	local slot = slotOfOwner(payload.ownerId)
	local r = if slot > 0 then ranches[slot] else nil
	if r == nil or not r.full or r.mode ~= "active" then
		counters.ignored += 1
		return
	end
	local list = payload.presses
	-- lecture complète avant tout effet : un seul champ illisible = message ignoré
	local n = 0
	for key, entry in list do
		n += 1
		if
			n > MAX_HELPERS
			or type(key) ~= "number"
			or key % 1 ~= 0
			or key < 1
			or key > MAX_HELPERS
			or type(entry) ~= "table"
		then
			counters.ignored += 1
			return
		end
		local helper, uid, tPress = entry.helper, entry.uid, entry.tPress
		if
			not finite(helper)
			or helper % 1 ~= 0
			or helper < 1
			or helper > r.count
			or type(uid) ~= "string"
			or #uid < 1
			or #uid > UID_MAX
			or not finite(tPress)
			or math.abs(tPress - now) > WINDOW
		then
			counters.ignored += 1
			return
		end
	end
	if n == 0 then
		counters.ignored += 1
		return
	end
	for i = 1, n do
		local entry = list[i]
		if entry == nil then
			continue
		end
		local hop = r.hops[entry.helper]
		if hop then
			startJump(r, hop, entry.uid, entry.tPress, now)
		end
	end
end

-- Le miroir montre-t-il la pression ? (`ready` posé plus tard que tPress, vu dans la fenêtre)
local function onSquishy(slot: number, uid: string)
	local r = ranches[slot]
	if r == nil or r.count == 0 or type(uid) ~= "string" then
		return
	end
	local now = Clock.now()
	for _, hop in r.hops do
		if hop.pop == "wait" and hop.uid == uid then
			if now >= hop.tPress - POP_BEFORE and now <= hop.tPress + POP_AFTER then
				local rec: any = WorldStateController.squishies(slot)[uid]
				if type(rec) == "table" and finite(rec.ready) and rec.ready > hop.tPress then
					hop.pop = "seen"
				end
			end
		end
	end
end

local function playPop(r: Ranch, hop: Hop)
	hop.pop = "done"
	counters.pops += 1
	local press = sources.press
	if press then
		pcall(press, r.slot, hop.uid)
	else
		Util.guard("RanchRenderer.play", RanchRenderer.play, r.slot, hop.uid, "press")
	end
	local color = if hop.kit then (hop.kit :: HelperKit.Kit).color else Color3.fromRGB(255, 255, 255)
	local at = hop.pos + Vector3.new(0, 0.6, 0)
	local drops = sources.drops
	if drops then
		pcall(drops, at, color, POP_DROPS)
		return
	end
	-- VFXController vient après ce module dans l'ordre du client : requis à la demande
	local ok, vfx = pcall(function(): any
		return require(Client.Controllers.VFXController) :: any
	end)
	if ok and type(vfx) == "table" and type(vfx.blobs) == "function" then
		Util.guard("VFXController.blobs", vfx.blobs, at, color, POP_DROPS)
	end
end

-- =============================================================================================
-- Image
-- =============================================================================================

-- Fin d'un saut : posée sur la cible ; « pop » si le miroir l'a déjà montré
local function land(r: Ranch, hop: Hop, now: number)
	hop.pos = hop.p1
	if hop.state == "home" then
		-- réveillées pendant le retour : elles attendent debout devant la porte
		hop.state = if r.mode == "nap" then "sleep" else "idle"
		hop.yaw = homeYaw(r.slot, hop.pos)
		refreshLabel(r)
		return
	end
	hop.state = "idle"
	if hop.toSleep or r.mode == "nap" then
		goHome(r, hop, now)
	end
end

local function stepPop(r: Ranch, hop: Hop, now: number)
	if hop.pop == "seen" and (hop.state == "idle" or hop.state == "home" or hop.state == "sleep") then
		if hop.state == "idle" and hop.pos == hop.p1 then
			playPop(r, hop)
		else
			hop.pop = "none"
			counters.soft += 1
		end
	elseif hop.pop == "wait" and now > hop.tPress + POP_AFTER then
		hop.pop = "none"
		counters.soft += 1
	end
end

local function canSound(r: Ranch): boolean
	if soundsThisFrame >= SOUNDS_PER_FRAME then
		return false
	end
	local cur = RanchV2.current()
	return r.slot == mySlot() or r.slot == cur
end

local function stepHop(r: Ranch, hop: Hop, now: number, idleTick: boolean)
	local state = hop.state
	if state == "wait" and now >= hop.t0 then
		hop.state = "jump"
		state = "jump"
		if canSound(r) then
			soundsThisFrame += 1
			counters.sounds += 1
			playSound(soundOf("HelperHop", "Boing"))
		end
	end
	if state == "jump" or state == "home" then
		local span = hop.t1 - hop.t0
		local u = if span > 0 then (now - hop.t0) / span else 1
		if u >= 1 then
			land(r, hop, now)
			queue(hop, 0, 0)
		else
			u = math.max(0, u)
			local p = hop.p0:Lerp(hop.p1, u)
			hop.pos = p
			queue(hop, hop.height * 4 * u * (1 - u), 0)
		end
	elseif idleTick then
		if state == "sleep" then
			-- respiration lente, penchée en avant
			local b = 0.5 + 0.5 * math.sin(now * 1.6 + hop.phase)
			queue(hop, 0.02 * b, math.rad(10))
		else
			local b = math.abs(math.sin(now * 3 + hop.phase))
			queue(hop, (if reducedMotion() then 0.03 else 0.06) * b, 0)
		end
	end
	stepPop(r, hop, now)
end

local function stepDetail()
	for _, r in ranches do
		if r.count > 0 then
			local full = Util.safe("RanchRenderer.detail", "reduced", RanchRenderer.detail, r.slot) == "full"
			local owner = ownerOf(r.slot)
			if owner ~= r.ownerId then
				-- propriétaire changé : tout est rendu, les Plopettes repartent de la maisonnette
				undraw(r)
				table.clear(r.hops)
				r.ownerId = owner
				r.full = false
				syncCount(r)
			end
			if full ~= r.full then
				r.full = full
				if full then
					-- elles reparaissent à la maisonnette (ou endormies)
					table.clear(r.hops)
					syncCount(r)
					refreshLabel(r)
				else
					undraw(r)
				end
			end
		end
	end
end

-- Une image (exposé aux specs ; appelé par RenderStepped)
function HelperRenderer._step(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	counters.steps += 1
	local now = Clock.now()
	detailAcc += d
	if detailAcc >= DETAIL_EVERY then
		detailAcc = 0
		stepDetail()
	end
	table.clear(bulkParts)
	table.clear(bulkCFrames)
	soundsThisFrame = 0
	local mine = mySlot()
	for _, r in ranches do
		if r.count > 0 and r.full then
			local idleTick = true
			if r.slot ~= mine then
				r.idleAcc += d
				idleTick = r.idleAcc >= 1 / IDLE_HZ
				if idleTick then
					r.idleAcc = 0
				end
			end
			for _, hop in r.hops do
				stepHop(r, hop, now, idleTick)
			end
		end
	end
	if #bulkParts > 0 then
		local ok, err = pcall(function()
			workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			Util.raise("HelperRenderer.bulk", tostring(err))
		end
	end
end

-- =============================================================================================
-- Branchements (D29)
-- =============================================================================================

function connectLive()
	if #live > 0 or not started then
		return
	end
	table.insert(
		live,
		RunService.RenderStepped:Connect(function(dt: number)
			Util.guard("HelperRenderer.step", HelperRenderer._step, dt)
		end)
	)
	local remote = Util.unreliable("HelperPress")
	if remote then
		table.insert(
			live,
			(remote :: any).OnClientEvent:Connect(function(payload: any)
				Util.guard("HelperRenderer.press", onPress, payload)
			end)
		)
	end
	table.insert(
		live,
		WorldStateController.SquishyChanged:Connect(function(slot: number, uid: string)
			Util.guard("HelperRenderer.squishy", onSquishy, slot, uid)
		end) :: any
	)
	detailAcc = DETAIL_EVERY -- première image : détail lu tout de suite
end

function disconnectLive()
	for _, c in live do
		c:Disconnect()
	end
	table.clear(live)
end

-- =============================================================================================
-- API
-- =============================================================================================

function HelperRenderer.Init()
	ranches = {}
	active = 0
end

function HelperRenderer.Start()
	if started then
		return
	end
	started = true
	if not watchAll() then
		-- modèles des ranchs pas encore répliqués : revus à chaque patch du miroir jusqu'au dernier
		watchConn = WorldStateController.RanchChanged:Connect(function()
			if Util.safe("HelperRenderer.watch", false, watchAll) then
				local c = watchConn
				watchConn = nil
				if c then
					c:Disconnect()
				end
			end
		end) :: any
	end
	if active > 0 then
		connectLive()
	end
end

function HelperRenderer._stop()
	disconnectLive()
	if watchConn then
		watchConn:Disconnect()
		watchConn = nil
	end
	for _, r in ranches do
		undraw(r)
		table.clear(r.hops)
		if r.conn then
			r.conn:Disconnect()
			r.conn = nil
		end
		r.model = nil
		r.count = 0
	end
	active = 0
	started = false
end

-- Compteurs (specs, Diagnostics)
function HelperRenderer.stats(): { [string]: number }
	local drawn, parts, ranchesOn, sleeping, labels = 0, 0, 0, 0, 0
	for _, r in ranches do
		if r.count > 0 then
			ranchesOn += 1
		end
		if r.label then
			labels += 1
		end
		for _, hop in r.hops do
			if hop.kit then
				drawn += 1
				parts += #(hop.kit :: HelperKit.Kit).parts
			end
			if hop.state == "sleep" then
				sleeping += 1
			end
		end
	end
	return {
		ranches = ranchesOn,
		drawn = drawn,
		parts = parts,
		sleeping = sleeping,
		labels = labels,
		connections = #live,
		messages = counters.messages,
		ignored = counters.ignored,
		jumps = counters.jumps,
		pops = counters.pops,
		soft = counters.soft,
		sounds = counters.sounds,
		refused = counters.refused,
		steps = counters.steps,
	}
end

-- État d'une Plopette (specs) : nil si elle n'existe pas
function HelperRenderer._state(slot: number, k: number): { [string]: any }?
	local r = ranches[slot]
	local hop = if r then r.hops[k] else nil
	if hop == nil then
		return nil
	end
	local kit = hop.kit
	return {
		state = hop.state,
		pos = hop.pos,
		target = hop.p1,
		t0 = hop.t0,
		t1 = hop.t1,
		uid = hop.uid,
		pop = hop.pop,
		drawn = kit ~= nil,
		parts = if kit then kit.parts else nil,
		model = if kit then kit.model else nil,
	}
end

-- Sources remplaçables (specs) : play(name), drops(pos, color, n), press(slot, uid)
function HelperRenderer._configure(options: any?)
	local o: any = if type(options) == "table" then options else {}
	sources.play = if type(o.play) == "function" then o.play else nil
	sources.drops = if type(o.drops) == "function" then o.drops else nil
	sources.press = if type(o.press) == "function" then o.press else nil
end

return HelperRenderer
