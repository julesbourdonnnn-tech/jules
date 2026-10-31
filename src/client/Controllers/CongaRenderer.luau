--!strict
-- CongaRenderer — paquet « client-world » (docs/04-architecture.md §13.7).
-- Rendu de toutes les créatures (files, sauvages, perchés, Gloomwisps, Comète au sol / portée)
-- dans workspace.ClientWorld (dossier client), avec NebbyBuilder, niveaux de détail et réserves.
--   * files des AUTRES joueurs : nœuds échantillonnés sur le miroir de miettes serveur
--     (WorldStateController.trail), premier tronçon raccordé au personnage affiché s'il est chargé
--     (les nœuds coupables, au-delà de 8,2 studs, restent exactement sur le chemin serveur) ;
--     file du joueur LOCAL : Trail local alimenté chaque image
--   * un SEUL workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) par image ;
--     files lointaines (> 120 studs) à 20 Hz ; LOD < 50 complet, 50-120 boule, > 120 : sauvages
--     masqués, files réduites à la tête + étiquette « ×N » ; budgets §12.8 (≤ 100 complets,
--     ≤ 1 500 pièces, Highlights, lumières) décidés à 10 Hz par un planificateur trié par
--     distance (Highlights et lumières attribués de façon différentielle : rien n'est ré-adorné ni
--     re-parenté tant que le choix ne change pas) ; Graphismes légers : distances × 0,6, ni
--     Highlight (pas même le flash de coupe) ni Trail, lumières ≤ 60 studs
--   * animations : vague dans la file, face au précédent, inclinaison dans les virages, danse à
--     l'arrêt (> 1 s), rebond et clignement des sauvages, regard vers le joueur proche (≤ 15),
--     flânerie SeededPath, apparition ; saut de capture (parabole 0,3 s, écrasement), arcs de
--     dispersion (0,55 s) + étourdissement, parade : saut vers les perchoirs (≤ 2 s)
--   * lisibilité (§6.4) : anneaux rose (coupables) / doré (Guard Links) / bleu (escortés) quand le
--     joueur local est à ≤ 20 studs d'une file qu'il peut couper ; contour pointillé rose de sa
--     propre queue si un non-équipier est à ≤ 15 studs ; anneau de style sinon (Cosmetics.Styles,
--     auras), Trail de style sur le dernier Nebby ; bulle dorée (bouclier) ; couronne + Highlight
--     des files ≥ 20 (4 plus proches), paillettes ≥ 40 ; anneau doré sous ses Nebbies libres
--   * Atlas (§4.14) : petit « ? » doré persistant au-dessus de chaque Nebby de la file LOCALE dont
--     l'entrée (espèce × forme) n'est pas encore dans State.get("atlas") ; réserve de BillboardGuis
--     (12, 6 en Graphismes légers ; aucune pièce ajoutée au budget), attribuée par rig de façon
--     différentielle, retirée à l'enregistrement de l'entrée et à l'encaissement
--   * Nids (World/NestDisplay) : perchés, « +N », perchoir qui pousse, panneau, constellation,
--     liens d'équipage, SpotLight, stèle
--   * Gloomwisps (tremblement, Beam d'aperçu pointillé de 15 studs) et orbe de la Comète (au sol,
--     au-dessus du porteur, vol en arc de 0,2 s) ; la traversée du ciel est jouée par VFXController
-- GDD : §4.6 (position des Nebbies), §5.2, §6.4, §9.3, §9.4, §11.6, §12.4, §12.8.
-- Dépendances : StateController, Util/Prefs, UI/Juice, WorldStateController, Render/NebbyBuilder,
-- Logic/Trail, Logic/WorldLayout, Logic/Formulas, Config/*, Shared/Util/Clock, World/*.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Nebbies = require(Shared.Config.Nebbies)
local Zones = require(Shared.Config.Zones)
local Types = require(Shared.Types)
local Trail = require(Shared.Logic.Trail)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Formulas = require(Shared.Logic.Formulas)
local NebbyBuilder = require(Shared.Render.NebbyBuilder)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local Prefs = require(Client.Util.Prefs)
local Juice = require(Client.UI.Juice)
local WorldStateController = require(Client.Controllers.WorldStateController)
local World = Client.World
local Fx = require(World.Fx)
local RigPool = require(World.RigPool)
local LineSampler = require(World.LineSampler)
local NestDisplay = require(World.NestDisplay)

local CongaRenderer = {}

-- Constantes (GDD §4.6, §9.3, §9.4, §11.6, §12.8) ----------------------------------------------------

local Conga = Balance.Conga
local Render = Balance.Render
local SLOT_COUNT = 12
local ROOT_HEIGHT = 3 -- HumanoidRootPart au-dessus du sol (miettes = positions de la racine)
local STITCH_LENGTH = Conga.HeadGap + 2 * Conga.Spacing -- 8,2 studs : nœuds jamais coupables
local STITCH_MAX = 12 -- personnage trop loin de ses miettes : pas de raccord
local PLAN_INTERVAL = 0.1 -- planificateur de LOD et budgets (10 Hz)
local LOD_HYSTERESIS = 3
local MAX_REBUILDS = 24 -- constructions / changements de LOD par image (pas de pic)
local WAVE_AMP, WAVE_FREQ, WAVE_STEP = 0.35, 4, 0.5
local DANCE_HEIGHT, DANCE_HZ, DANCE_STEP = 0.6, 3, 0.5
local LEAN_FACTOR, LEAN_MAX, LEAN_SMOOTH = 0.15, 15, 0.25
local MOVE_EPSILON = 0.05
local HOP_SECONDS, HOP_APEX, HOP_RANGE = 0.3, 4, 120
local SQUASH_SECONDS = 0.2
local SQUASH = Vector3.new(1.25, 0.75, 1.25)
local WILD_BOB_AMP, WILD_BOB_SPEED = 0.25, 2.2
local BLINK_DISTANCE, BLINK_SECONDS, BLINK_MIN, BLINK_SPREAD = 40, 0.08, 3, 3
local LOOK_DISTANCE, LOOK_SMOOTH = 15, 0.15
local POP_SECONDS = 0.4
local DIZZY_BALLS, DIZZY_TURNS, DIZZY_RADIUS, DIZZY_SIZE = 3, 2, 0.75, 0.3
local DIZZY_COLOR = Color3.fromRGB(255, 240, 140)
local PARADE_STEP, PARADE_SPAN = 0.06, 2 -- un Nebby toutes les 0,06 s, séquence ≤ 2 s
local PARADE_HOP, PARADE_APEX, PARADE_SHRINK = 0.35, 3, 0.15
local PARADE_MARCH_HOP = 0.3 -- petits sauts pendant la marche vers la porte
local BEACON_TOP = Vector3.new(0, Zones.Beacon.StarY, 0) -- étoile de la Balise (parade de la Nuit de la Balise)
local RING_THICKNESS, RING_SCALE, RING_LIFT = 0.12, 1.25, 0.06
local CROWN_THICKNESS, CROWN_SCALE = 0.3, 0.7
local CROWN_COLOR = Color3.fromRGB(255, 215, 80)
local SPARKLE_RATE = 10
local LABEL_SIZE = UDim2.fromScale(4.5, 2)
local LABEL_DISTANCE = 600
local WISP_HOVER, WISP_BOB = 3, 0.3
local WISP_RANGE = 250
local WISP_PREVIEW_COLOR = Color3.fromRGB(150, 90, 220)
local ORB_HOVER, ORB_BOB, ORB_ARC = 2.5, 0.4, 3
local STEAL_SECONDS = 0.2 -- vol en arc de l'orbe vers le nouveau porteur (GDD §9.4)
local FLASH_SECONDS = 0.1
local HANDOFF_SECONDS = 1.5
local MAX_LINE_HIGHLIGHTS = Render.HighlightLines
local MAX_MYTHIC_HIGHLIGHTS = Render.HighlightMythics
local MAX_LIGHTS = Render.LegendaryLights
-- « ? » doré des entrées d'Atlas inconnues (file locale)
local MARK_MAX, MARK_MAX_LOW = 12, 6
local MARK_SIZE = UDim2.fromScale(1.4, 1.4)
local MARK_LIFT = 1.4 -- studs au-dessus du sommet du Nebby
local MARK_BOB, MARK_BOB_SPEED, MARK_BOB_STEP = 0.25, 3, 0.6
local MARK_POP = 0.25
local MARK_DISTANCE = 120
local MARK_COLOR = Color3.fromRGB(255, 205, 60)
local MARK_STROKE = Color3.fromRGB(70, 45, 10)
local TAU = 2 * math.pi

-- Types -------------------------------------------------------------------------------------------

type Rig = RigPool.Rig
type Lod = RigPool.Lod

type NodeView = RigPool.View & {
	pos: Vector3,
	yaw: number,
	prevYaw: number,
	roll: number,
	hopFrom: Vector3?,
	hopStart: number,
	ring: BasePart?,
	ringColor: Color3?,
	ringWarn: boolean,
	newEntry: boolean, -- entrée d'Atlas encore inconnue (file locale seulement)
	atlasVer: number, -- version de l'Atlas pour laquelle newEntry a été calculé
}

type LineView = {
	slot: number,
	userId: number,
	nodes: { NodeView },
	positions: { Vector3 },
	lastHead: Vector3?,
	movedAt: number,
	far: boolean,
	nextFar: number,
	dist: number,
	mode: "style" | "cut" | "warn",
	guard: number,
	escorted: { [number]: boolean },
	bubble: boolean,
	styleKey: string,
	nestColor: Color3,
	auraColor: Color3?,
	label: BillboardGui?,
	labelText: TextLabel?,
	labelCount: number,
	crown: BasePart?,
	sparkle: BasePart?,
	trail: Trail?,
	trailA0: Attachment?,
	trailA1: Attachment?,
	trailBody: BasePart?,
	trailRig: Rig?,
}

type WildView = RigPool.View & {
	id: number,
	mirror: Types.WildMirror,
	pos: Vector3,
	yaw: number,
	phase: number,
	blinkPeriod: number,
	dizzy: { BasePart },
	ring: BasePart?,
	scaled: boolean,
}

-- Nebby de parade : marche vers la porte (ou l'anneau de la Balise) jusqu'à son tour, puis saute
type Parader = {
	rig: Rig,
	from: Vector3,
	gate: Vector3,
	to: Vector3,
	t0: number,
	start: number,
	look: Vector3,
}
type Handoff = { code: number, rig: Rig?, from: Vector3?, at: number }

type WispView = { id: number, rig: Rig, preview: Beam, target: Attachment, pos: Vector3 }

type OrbView = { rig: Rig, pos: Vector3?, carrier: number, arcFrom: Vector3?, arcStart: number }

-- « ? » doré prêté au rig d'un nœud de la file locale
type Marker = {
	gui: BillboardGui,
	label: TextLabel,
	scale: UIScale,
	body: BasePart?,
	lift: number,
	index: number,
}

-- État -------------------------------------------------------------------------------------------------

local started = false
local folders: { [string]: Folder } = {}
local wispAnchor: BasePart? = nil
local lineViews: { [number]: LineView } = {}
local wildViews: { [number]: WildView } = {}
local wispViews: { [number]: WispView } = {}
local orb: OrbView? = nil
local paraders: { Parader } = {}
local catchHandoff: { [number]: { Handoff } } = {}
local wildHandoff: { [number]: { rig: Rig, at: number } } = {}
local localTrail: Trail.Trail = Trail.new(Conga.TrailLength, Conga.TrailMinStep)
local localSlotCache = 0
local nextPlan = -math.huge
local rebuilds = 0
local others: { { userId: number, pos: Vector3 } } = {}
local localPos: Vector3? = nil

-- Listes réutilisées d'une image à l'autre (aucune allocation par image)
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local planViews: { RigPool.View } = {}
local aliveWisps: { [number]: boolean } = {}

-- Réserves de pièces décoratives
local ringPool: { BasePart } = {}
local ballPool: { BasePart } = {}
local highlights: { Highlight } = {}
local lights: { PointLight } = {}
local highlightOf: { [Rig]: Highlight } = {}
local lightOf: { [Rig]: PointLight } = {}
local flashHighlight: Highlight? = nil

-- « ? » dorés : attribués par rig (rien n'est ré-adorné tant que le Nebby reste inconnu)
local markerOf: { [Rig]: Marker } = {}
local markerFree: { Marker } = {}
local markerWant: { [Rig]: number } = {} -- réutilisée : rig → index du nœud
local atlasVersion = 0 -- incrémentée à chaque changement de State "atlas"

-- Outils ----------------------------------------------------------------------------------------------

local function lowGraphics(): boolean
	return Prefs.lowGraphics()
end

local function distanceMult(): number
	return if lowGraphics() then Render.LowGraphicsDistanceMult else 1
end

local function rootOf(player: Player?): BasePart?
	local character = if player then player.Character else nil
	local part = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function cameraPosition(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

-- LOD selon la distance, avec hystérésis autour des seuils (aucun va-et-vient)
local function lodByDistance(dist: number, current: Lod, mult: number): Lod
	local full = Render.FullDistance * mult
	local ball = Render.BallDistance * mult
	if current == "full" then
		full += LOD_HYSTERESIS
	elseif current == "ball" then
		full -= LOD_HYSTERESIS
		ball += LOD_HYSTERESIS
	else
		ball -= LOD_HYSTERESIS
	end
	if dist < full then
		return "full"
	elseif dist < ball then
		return "ball"
	end
	return "hidden"
end

local function rarityOf(code: number): number
	return Nebbies.rarityOf((Nebbies.unpack(code)))
end

local function yawToward(from: Vector3, to: Vector3, fallback: number): number
	local dx, dz = to.X - from.X, to.Z - from.Z
	if dx * dx + dz * dz < 1e-4 then
		return fallback
	end
	return math.atan2(-dx, -dz)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % TAU - math.pi
end

local function append(part: BasePart, cf: CFrame)
	local n = #moveParts + 1
	moveParts[n] = part
	moveCFrames[n] = cf
end

-- Pièces décoratives en réserve ---------------------------------------------------------------------

local function takeRing(): BasePart
	local ring = table.remove(ringPool)
	if ring == nil then
		ring = Fx.ring("Ring", 1, RING_THICKNESS, Color3.new(1, 1, 1))
	end
	local r = ring :: BasePart
	r.Parent = folders.Lines
	return r
end

local function giveRing(ring: BasePart)
	ring.Parent = nil
	table.insert(ringPool, ring)
end

local function takeBall(): BasePart
	local ball = table.remove(ballPool)
	if ball == nil then
		ball = Fx.part("Dizzy", "Ball", Vector3.one * DIZZY_SIZE, DIZZY_COLOR)
	end
	local b = ball :: BasePart
	b.Parent = folders.Wild
	return b
end

local function giveBall(ball: BasePart)
	ball.Parent = nil
	table.insert(ballPool, ball)
end

-- Highlight / PointLight prêtés aux rigs : détachés avant toute reconstruction ou mise en réserve
local function detachDecor(rig: Rig)
	local hl = highlightOf[rig]
	if hl then
		highlightOf[rig] = nil
		hl.Adornee = nil
		hl.Enabled = false
	end
	local light = lightOf[rig]
	if light then
		lightOf[rig] = nil
		light.Parent = nil
	end
	if flashHighlight and flashHighlight.Adornee == rig.model then
		flashHighlight.Adornee = nil
		flashHighlight.Enabled = false
	end
	-- Trail de style posé sur le dernier Nebby : retiré avant que ses pièces ne soient détruites
	for _, view in lineViews do
		if view.trailRig == rig then
			view.trailRig = nil
			view.trailBody = nil
			if view.trail then
				view.trail.Parent = nil
			end
			if view.trailA0 then
				view.trailA0.Parent = nil
			end
			if view.trailA1 then
				view.trailA1.Parent = nil
			end
		end
	end
end

local function releaseRig(rig: Rig?)
	if rig then
		RigPool.release(rig)
	end
end

-- Assure le rig d'une vue au LOD voulu (dans la limite de MAX_REBUILDS par image)
local function ensureRig(view: RigPool.View, parent: Instance): Rig?
	local want = view.want
	local rig = view.rig
	if want == "hidden" then
		if rig then
			view.rig = nil
			RigPool.release(rig)
		end
		return nil
	end
	if rig == nil then
		if rebuilds >= MAX_REBUILDS then
			return nil
		end
		rebuilds += 1
		rig = RigPool.acquire(view.code, view.stars, want, view.bubble, parent)
		view.rig = rig
		return rig
	end
	local r = rig :: Rig
	if r.lod ~= want and rebuilds < MAX_REBUILDS then
		rebuilds += 1
		RigPool.setLod(r, want)
	end
	if rebuilds < MAX_REBUILDS and RigPool.conform(r, view.bubble) then
		rebuilds += 1
	end
	if r.model.Parent ~= parent then
		r.model.Parent = parent
	end
	return r
end

local function ensurePerched(view: RigPool.View): Rig?
	return ensureRig(view, folders.Perched)
end

-- Flash blanc de 0,1 s (Nebby coupé)
local function flash(rig: Rig)
	local hl = flashHighlight
	-- Mouvement réduit : pas de flash ; Graphismes légers : Highlight réservé au porteur de la Comète
	if hl == nil or Juice.reducedMotion() or lowGraphics() then
		return
	end
	hl.Adornee = rig.model
	hl.FillColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0
	hl.OutlineTransparency = 1
	hl.Enabled = true
	task.delay(FLASH_SECONDS, function()
		if hl.Adornee == rig.model then
			hl.Enabled = false
			hl.Adornee = nil
		end
	end)
end

-- Files ------------------------------------------------------------------------------------------------

local function newNode(code: number, pos: Vector3, focus: Vector3?, bubble: boolean): NodeView
	local rarity = rarityOf(code)
	local dist = if focus then (pos - focus).Magnitude else math.huge
	return {
		code = code,
		stars = 1,
		rig = nil,
		want = lodByDistance(dist, "hidden", distanceMult()),
		dist = dist,
		bubble = bubble,
		pinned = nil,
		mythic = rarity >= 6,
		bright = rarity >= 5,
		pos = pos,
		yaw = 0,
		prevYaw = 0,
		roll = 0,
		hopFrom = nil,
		hopStart = -math.huge,
		ring = nil,
		ringColor = nil,
		ringWarn = false,
		newEntry = false,
		atlasVer = -1,
	}
end

local function dropNode(node: NodeView)
	local ring = node.ring
	if ring then
		node.ring = nil
		node.ringColor = nil
		giveRing(ring)
	end
	local rig = node.rig
	if rig then
		node.rig = nil
		Fx.scaleRig(rig, Vector3.one)
		RigPool.release(rig)
	end
end

local function newLineView(slot: number, userId: number): LineView
	return {
		slot = slot,
		userId = userId,
		nodes = {},
		positions = {},
		lastHead = nil,
		movedAt = Clock.now(),
		far = false,
		nextFar = -math.huge,
		dist = math.huge,
		mode = "style",
		guard = Balance.Guard.Base,
		escorted = {},
		bubble = false,
		styleKey = "default",
		nestColor = NestDisplay.nestColor(slot),
		auraColor = nil,
		label = nil,
		labelText = nil,
		labelCount = -1,
		crown = nil,
		sparkle = nil,
		trail = nil,
		trailA0 = nil,
		trailA1 = nil,
		trailBody = nil,
		trailRig = nil,
	}
end

local function destroyExtras(view: LineView)
	if view.label then
		view.label:Destroy()
		view.label = nil
		view.labelText = nil
	end
	if view.crown then
		view.crown:Destroy()
		view.crown = nil
	end
	if view.sparkle then
		view.sparkle:Destroy()
		view.sparkle = nil
	end
	if view.trail then
		view.trail:Destroy()
		view.trail = nil
	end
	if view.trailA0 then
		view.trailA0:Destroy()
		view.trailA0 = nil
	end
	if view.trailA1 then
		view.trailA1:Destroy()
		view.trailA1 = nil
	end
	view.trailBody = nil
end

local function dropLine(slot: number)
	local view = lineViews[slot]
	if view == nil then
		return
	end
	lineViews[slot] = nil
	for _, node in view.nodes do
		dropNode(node)
	end
	destroyExtras(view)
end

local function playerOf(userId: number): Player?
	if userId == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

local function attr(player: Player?, name: string): any
	return if player then player:GetAttribute(name) else nil
end

-- Synchronise les nœuds rendus avec les codes du miroir (ajouts en queue, troncatures)
local function reconcileLine(view: LineView, codes: { Types.NebbyCode }, focus: Vector3, now: number)
	local nodes = view.nodes
	local k = 1
	while k <= #nodes and k <= #codes and nodes[k].code == codes[k] do
		k += 1
	end
	for i = #nodes, k, -1 do
		dropNode(nodes[i])
		nodes[i] = nil
	end
	if k > #codes then
		return
	end
	local queue = catchHandoff[view.slot]
	local tail = view.positions[#view.positions] or focus
	for i = k, #codes do
		local code = codes[i]
		local node = newNode(code, view.positions[i] or tail, focus, view.bubble)
		if queue then
			for qi, entry in queue do
				if entry.code == code then
					table.remove(queue, qi)
					if entry.rig then
						node.rig = entry.rig
						Fx.scaleRig(entry.rig, Vector3.one)
					end
					local from = entry.from
					if from and not Juice.reducedMotion() and (from - focus).Magnitude <= HOP_RANGE then
						node.hopFrom = from
						node.hopStart = now
					end
					break
				end
			end
		end
		nodes[i] = node
	end
end

local function styleRingColor(view: LineView, i: number, t: number): Color3
	local style = Cosmetics.Styles[view.styleKey]
	local base = if style and style.ringColor then style.ringColor else view.nestColor
	local animated = if style then style.animated else nil
	if animated == "hsv" then
		base = Color3.fromHSV((t * 0.25 + i * 0.06) % 1, 0.55, 1)
	elseif animated == "flicker" then
		local k = 0.75 + 0.25 * math.sin(t * 17 + i * 2.3)
		base = Color3.new(base.R * k, base.G * k, base.B * k)
	elseif animated == "twinkle" then
		if math.sin(t * 5 + i * 1.7) > 0.85 then
			base = Color3.new(1, 1, 1)
		end
	elseif animated == "wave" or animated == "ripple" or animated == "bubbles" then
		local k = 0.5 + 0.5 * math.sin(t * 6 - i * 0.6)
		base = base:Lerp(Color3.new(1, 1, 1), 0.35 * k)
	end
	local aura = view.auraColor
	if aura then
		base = base:Lerp(aura, 0.4)
	end
	return base
end

local function ringFor(view: LineView, i: number, t: number): (Color3, boolean)
	local mode = view.mode
	if mode == "cut" then
		if i <= view.guard then
			return Cosmetics.Readability.Guard, false
		elseif view.escorted[i] then
			return Cosmetics.Readability.Escort, false
		end
		return Cosmetics.Readability.Snippable, false
	elseif mode == "warn" and i > view.guard then
		return Cosmetics.Readability.Snippable, true
	end
	return styleRingColor(view, i, t), false
end

local function updateRing(node: NodeView, view: LineView, i: number, cf: CFrame, size: number, t: number)
	local ring = node.ring
	if ring == nil then
		ring = takeRing()
		node.ring = ring
		node.ringColor = nil
	end
	local r = ring :: BasePart
	local diameter = size * RING_SCALE
	if r.Size.Y ~= diameter then
		r.Size = Vector3.new(RING_THICKNESS, diameter, diameter)
	end
	local color, warn = ringFor(view, i, t)
	if node.ringColor ~= color then
		node.ringColor = color
		r.Color = color
	end
	if node.ringWarn ~= warn then
		node.ringWarn = warn
		r.Material = if warn then Enum.Material.ForceField else Enum.Material.Neon
	end
	local p = cf.Position
	local ground = p.Y - size / 2 + RING_LIFT
	append(r, CFrame.new(p.X, ground, p.Z) * Fx.FLAT)
end

local function dropRing(node: NodeView)
	local ring = node.ring
	if ring then
		node.ring = nil
		node.ringColor = nil
		giveRing(ring)
	end
end

-- Étiquette « ×N » d'une file lointaine (sur la boule de tête)
local function updateLabel(view: LineView, head: Rig?)
	local show = view.far and head ~= nil and head.lod ~= "hidden"
	if not show then
		if view.label and view.label.Enabled then
			view.label.Enabled = false
		end
		return
	end
	local gui = view.label
	if gui == nil then
		local g = Instance.new("BillboardGui")
		g.Name = "LineCount"
		g.Size = LABEL_SIZE
		g.StudsOffset = Vector3.new(0, 2.5, 0)
		g.AlwaysOnTop = true
		g.LightInfluence = 0
		g.MaxDistance = LABEL_DISTANCE
		g.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.Name = "Count"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.TextColor3 = view.nestColor
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(30, 22, 50)
		stroke.Parent = label
		label.Parent = g
		g.Parent = folders.Lines
		view.label = g
		view.labelText = label
		gui = g
	end
	local g = gui :: BillboardGui
	local rig = head :: Rig
	if g.Adornee ~= rig.body then
		g.Adornee = rig.body
	end
	g.Enabled = true
	local n = #view.nodes
	if view.labelCount ~= n and view.labelText then
		view.labelCount = n
		view.labelText.Text = Prefs.t("world.lineCount", { n = n })
	end
end

-- Couronne (file ≥ 20), paillettes (file ≥ 40), Trail de style sur le dernier Nebby
local function updateExtras(view: LineView, headCF: CFrame?, headSize: number, lastRig: Rig?)
	local n = #view.nodes
	local crownOn = headCF ~= nil and n >= Render.CrownLine and not view.far
	if crownOn then
		local crown = view.crown
		if crown == nil then
			crown = Fx.ring("Crown", 1, CROWN_THICKNESS, CROWN_COLOR)
			view.crown = crown
		end
		local c = crown :: BasePart
		if c.Parent ~= folders.Lines then
			c.Parent = folders.Lines
		end
		local d = headSize * CROWN_SCALE
		if c.Size.Y ~= d then
			c.Size = Vector3.new(CROWN_THICKNESS, d, d)
		end
		local color = view.auraColor or CROWN_COLOR
		if c.Color ~= color then
			c.Color = color
		end
		local p = (headCF :: CFrame).Position
		append(c, CFrame.new(p.X, p.Y + headSize / 2 + 0.25, p.Z) * Fx.FLAT)
	elseif view.crown and view.crown.Parent ~= nil then
		view.crown.Parent = nil
	end

	local sparkleOn = headCF ~= nil and n >= Render.SparkleLine and not view.far
	if sparkleOn then
		local sparkle = view.sparkle
		if sparkle == nil then
			local s = Fx.part("Sparkle", "Block", Vector3.new(2, 0.2, 2), Color3.new(1, 1, 1))
			s.Transparency = 1
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Glitter"
			emitter.Rate = SPARKLE_RATE
			emitter.Lifetime = NumberRange.new(0.8, 1.2)
			emitter.Speed = NumberRange.new(1, 3)
			emitter.SpreadAngle = Vector2.new(25, 25)
			emitter.LightEmission = 1
			emitter.Size = NumberSequence.new(0.25, 0)
			emitter.Color = ColorSequence.new(view.nestColor)
			emitter.Parent = s
			view.sparkle = s
			sparkle = s
		end
		local s = sparkle :: BasePart
		if s.Parent ~= folders.Lines then
			s.Parent = folders.Lines
		end
		local emitter = s:FindFirstChildOfClass("ParticleEmitter")
		if emitter then
			local rate = SPARKLE_RATE * (if lowGraphics() then Render.LowGraphicsParticleMult else 1)
			if emitter.Rate ~= rate then
				emitter.Rate = rate
			end
		end
		local p = (headCF :: CFrame).Position
		append(s, CFrame.new(p.X, p.Y - headSize / 2, p.Z))
	elseif view.sparkle and view.sparkle.Parent ~= nil then
		view.sparkle.Parent = nil
	end

	-- Trail de style sur le dernier Nebby (pas en Graphismes légers)
	local trailOn = lastRig ~= nil and lastRig.lod ~= "hidden" and not lowGraphics() and not view.far
	if trailOn then
		local body = (lastRig :: Rig).body
		if view.trail == nil then
			local a0 = Instance.new("Attachment")
			a0.Name = "StyleTrail0"
			local a1 = Instance.new("Attachment")
			a1.Name = "StyleTrail1"
			local trail = Instance.new("Trail")
			trail.Name = "StyleTrail"
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.5
			trail.MinLength = 0.1
			trail.FaceCamera = true
			trail.LightEmission = 0.8
			trail.Transparency = NumberSequence.new(0.2, 1)
			local style = Cosmetics.Styles[view.styleKey]
			local colors = if style then style.trailColors else nil
			local nest = view.nestColor
			trail.Color = if colors and #colors >= 2
				then ColorSequence.new(colors[1], colors[2])
				else ColorSequence.new(nest, Color3.new(1, 1, 1))
			view.trail = trail
			view.trailA0 = a0
			view.trailA1 = a1
		end
		if view.trailBody ~= body then
			view.trailBody = body
			view.trailRig = lastRig
			local size = (lastRig :: Rig).size
			local a0, a1 = view.trailA0 :: Attachment, view.trailA1 :: Attachment
			a0.Position = Vector3.new(0, size * 0.25, 0)
			a1.Position = Vector3.new(0, -size * 0.25, 0)
			a0.Parent = body
			a1.Parent = body;
			(view.trail :: Trail).Parent = body
		end
		local trail = view.trail :: Trail
		if not trail.Enabled then
			trail.Enabled = true
		end
	elseif view.trail then
		if view.trail.Enabled then
			view.trail.Enabled = false
		end
		if view.trailBody and view.trailBody.Parent == nil then
			view.trailBody = nil
		end
	end
end

local function moveLine(view: LineView, t: number, dt: number)
	local nodes = view.nodes
	local n = #nodes
	if n == 0 then
		updateLabel(view, nil)
		updateExtras(view, nil, 0, nil)
		return
	end
	local isLocal = view.slot == localSlotCache and view.slot ~= 0
	local points: { Vector3 }? = nil
	local head: Vector3? = nil
	if isLocal then
		points = localTrail.points
		head = localTrail:head()
	else
		local trail = WorldStateController.trail(view.slot)
		if trail then
			points = trail.points
			head = trail:head()
		end
	end
	if head == nil then
		-- aucune miette : rien à dessiner (rigs gardés, non déplacés)
		return
	end
	local h = head :: Vector3
	if view.lastHead == nil or (h - (view.lastHead :: Vector3)).Magnitude > MOVE_EPSILON then
		view.movedAt = t
	end
	view.lastHead = h
	if view.far then
		if t < view.nextFar then
			return -- files lointaines : 20 Hz
		end
		view.nextFar = t + 1 / Render.FarUpdateHz
	end
	local positions = LineSampler.sample(points, n, Conga.Spacing, Conga.HeadGap, view.positions)
	if not isLocal then
		local shown = rootOf(playerOf(view.userId))
		if shown and (shown.Position - h).Magnitude < STITCH_MAX then
			LineSampler.stitch(positions, h, shown.Position, Conga.Spacing, Conga.HeadGap, STITCH_LENGTH)
		end
	end
	local dancing = t - view.movedAt > Conga.DanceDelay
	local headCF: CFrame? = nil
	local headSize = 0
	local headRig: Rig? = nil
	local lastRig: Rig? = nil
	local parent = folders.Lines
	local reduced = Juice.reducedMotion()
	for i, node in nodes do
		local p = positions[i]
		node.pos = p
		local rig = ensureRig(node, parent)
		if rig == nil or rig.lod == "hidden" then
			dropRing(node)
			continue
		end
		local size = rig.size
		local ground = math.max(WorldLayout.groundY(p.X, p.Z), p.Y - ROOT_HEIGHT)
		local y = ground + size / 2
		if not reduced then
			if dancing then
				y += DANCE_HEIGHT * math.abs(math.sin(math.pi * DANCE_HZ * t + DANCE_STEP * i))
			else
				-- GDD §9.3 : Y = sin(4 t + 0,5 i) × 0,35, décalée de +0,35 (jamais sous le sol)
				y += WAVE_AMP * (1 + math.sin(WAVE_FREQ * t + WAVE_STEP * i))
			end
		end
		local target = if i == 1 then h else positions[i - 1]
		local yaw = yawToward(p, target, node.yaw)
		local rate = if dt > 0 then wrapAngle(yaw - node.prevYaw) / dt else 0
		node.prevYaw = yaw
		node.yaw = yaw
		local lean = math.rad(math.clamp(math.deg(rate) * LEAN_FACTOR, -LEAN_MAX, LEAN_MAX))
		node.roll += (lean - node.roll) * LEAN_SMOOTH
		local pos = Vector3.new(p.X, y, p.Z)
		local scale: Vector3? = nil
		local hopFrom = node.hopFrom
		if hopFrom then
			local a = (t - node.hopStart) / HOP_SECONDS
			if a < 1 then
				pos = hopFrom:Lerp(pos, a) + Vector3.new(0, Fx.arc(a, HOP_APEX), 0)
			else
				local sa = (t - node.hopStart - HOP_SECONDS) / SQUASH_SECONDS
				if sa < 1 then
					scale = SQUASH:Lerp(Vector3.one, Fx.backOut(sa))
				else
					node.hopFrom = nil
					Fx.scaleRig(rig, Vector3.one)
				end
			end
		end
		local cf = CFrame.new(pos)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(0, 0, if reduced then 0 else node.roll)
		if rig.lod == "full" then
			local blink = node.dist <= BLINK_DISTANCE and ((t + i * 0.37) % (BLINK_MIN + 1.5)) < BLINK_SECONDS
			NebbyBuilder.animate(
				rig,
				{ t = t, phase = i * 0.7, blink = blink, speed = if dancing then 0 else 12 }
			)
			updateRing(node, view, i, cf, size, t)
		else
			dropRing(node)
		end
		if scale then
			Fx.scaleRig(rig, scale)
			Fx.appendScaled(rig, cf, scale, moveParts, moveCFrames)
		else
			NebbyBuilder.appendCFrames(rig, cf, moveParts, moveCFrames)
		end
		if i == 1 then
			headCF = cf
			headSize = size
			headRig = rig
		end
		lastRig = rig
	end
	updateLabel(view, headRig)
	updateExtras(view, headCF, headSize, if n >= 1 and nodes[n].rig ~= nil then lastRig else nil)
end

-- Atlas : « ? » doré au-dessus des Nebbies inconnus de la file locale (GDD §4.14) ---------------------------

local function unknownEntry(atlas: any, code: number): boolean
	if type(atlas) ~= "table" then
		return false -- Atlas pas encore chargé : rien à signaler
	end
	local s, f = Nebbies.unpack(code)
	if s < 1 then
		return false
	end
	return not Nebbies.testBit(atlas, Nebbies.atlasIndex(s, f))
end

local function newMarker(): Marker
	local gui = Instance.new("BillboardGui")
	gui.Name = "NewEntry"
	gui.Size = MARK_SIZE
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = MARK_DISTANCE
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Mark"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextColor3 = MARK_COLOR
	label.Text = Prefs.t("world.newEntry")
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = MARK_STROKE
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	label.Parent = gui
	gui.Parent = folders.Lines
	return { gui = gui, label = label, scale = scale, body = nil, lift = 0, index = 0 }
end

local function freeMarker(m: Marker)
	m.gui.Enabled = false
	m.gui.Adornee = nil
	m.body = nil
	m.index = 0
	table.insert(markerFree, m)
end

-- Une passe par image : nœuds visibles de la file locale dont l'entrée est inconnue (tête d'abord,
-- au plus MARK_MAX), puis attribution différentielle des « ? » (pop à l'apparition, léger flottement)
local function updateMarkers(t: number)
	table.clear(markerWant)
	local view = if localSlotCache ~= 0 then lineViews[localSlotCache] else nil
	if view then
		local atlas = State.get("atlas")
		local cap = if lowGraphics() then MARK_MAX_LOW else MARK_MAX
		local used = 0
		for i, node in view.nodes do
			if node.atlasVer ~= atlasVersion then
				node.atlasVer = atlasVersion
				node.newEntry = unknownEntry(atlas, node.code)
			end
			local rig = node.rig
			if node.newEntry and rig and rig.lod ~= "hidden" then
				markerWant[rig] = i
				used += 1
				if used >= cap then
					break
				end
			end
		end
	end
	for rig, m in markerOf do
		if markerWant[rig] == nil then
			markerOf[rig] = nil
			freeMarker(m)
		end
	end
	local reduced = Juice.reducedMotion()
	local bob = not reduced and not lowGraphics()
	for rig, i in markerWant do
		local m = markerOf[rig]
		if m == nil then
			local created = table.remove(markerFree) or newMarker()
			markerOf[rig] = created
			created.label.Text = Prefs.t("world.newEntry")
			created.gui.Enabled = true
			if reduced then
				created.scale.Scale = 1
			else
				created.scale.Scale = 0
				Juice.tween(
					created.scale,
					MARK_POP,
					{ Scale = 1 },
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				)
			end
			m = created
		end
		local mk = m :: Marker
		mk.index = i
		if mk.body ~= rig.body then
			mk.body = rig.body
			mk.gui.Adornee = rig.body
		end
		local lift = rig.size / 2 + MARK_LIFT
		if bob then
			lift += MARK_BOB * math.sin(MARK_BOB_SPEED * t + MARK_BOB_STEP * i)
		end
		if mk.lift ~= lift then
			mk.lift = lift
			mk.gui.StudsOffset = Vector3.new(0, lift, 0)
		end
	end
end

-- Parade : les Nebbies sautent vers les perchoirs du Nid ---------------------------------------------------

local function paradeTarget(slot: number, k: number): (Vector3, Vector3)
	local count = math.max(NestDisplay.perchCount(slot), 0)
	if count > 0 then
		local index = (k - 1) % count + 1
		local top = NestDisplay.perchTop(slot, index)
		if top then
			local look = WorldLayout.perchCFrame(slot, index).LookVector
			return top, look
		end
	end
	local cf = WorldLayout.nestCFrame(slot)
	local angle = k * 2.4
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (4 + (k % 4) * 2)
	return cf.Position + offset, cf.LookVector
end

local function startParade(slot: number, atBeacon: boolean)
	local view = lineViews[slot]
	if view == nil then
		return
	end
	local nodes = view.nodes
	local n = #nodes
	local now = Clock.now()
	local step = math.min(PARADE_STEP, PARADE_SPAN / math.max(n, 1))
	local gatePos = WorldLayout.gateCFrame(slot).Position
	local head = if nodes[1] then nodes[1].pos else gatePos
	local gate = if atBeacon then Vector3.new(head.X, 0, head.Z) else Vector3.new(gatePos.X, 0, gatePos.Z)
	for k, node in nodes do
		local rig = node.rig
		dropRing(node)
		node.rig = nil
		if rig then
			if Juice.reducedMotion() or rig.lod == "hidden" then
				RigPool.release(rig)
			else
				Fx.scaleRig(rig, Vector3.one)
				local to, look = paradeTarget(slot, k)
				if atBeacon then
					-- parade à la Balise : les Nebbies s'envolent vers son sommet
					to = BEACON_TOP + Vector3.new(math.cos(k * 2.4), 0, math.sin(k * 2.4)) * 3
					look = Vector3.new(0, 0, 1)
				end
				table.insert(paraders, {
					rig = rig,
					from = node.pos,
					gate = gate,
					to = to + Vector3.new(0, rig.size / 2, 0),
					t0 = now,
					start = now + (k - 1) * step,
					look = look,
				})
			end
		end
	end
	table.clear(nodes)
end

-- Position du Nebby de parade qui marche vers la porte jusqu'à son tour de saut
local function marchPosition(p: Parader, t: number, size: number): Vector3
	local wait = p.start - p.t0
	local a = if wait > 1e-3 then Fx.quadOut((t - p.t0) / wait) else 0
	local xz = p.from:Lerp(p.gate, a)
	local hop = PARADE_MARCH_HOP * math.abs(math.sin(math.pi * DANCE_HZ * t + p.start * 7))
	return Vector3.new(xz.X, WorldLayout.groundY(xz.X, xz.Z) + size / 2 + hop, xz.Z)
end

local function moveParaders(t: number)
	for i = #paraders, 1, -1 do
		local p = paraders[i]
		local rig = p.rig
		local a = (t - p.start) / PARADE_HOP
		if a < 0 then
			local pos = marchPosition(p, t, rig.size)
			local yaw = yawToward(pos, p.gate, 0)
			NebbyBuilder.appendCFrames(
				rig,
				CFrame.new(pos) * CFrame.Angles(0, yaw, 0),
				moveParts,
				moveCFrames
			)
		elseif a < 1 then
			local from = marchPosition(p, p.start, rig.size)
			local pos = from:Lerp(p.to, a) + Vector3.new(0, Fx.arc(a, PARADE_APEX), 0)
			NebbyBuilder.appendCFrames(rig, CFrame.lookAt(pos, pos + p.look), moveParts, moveCFrames)
		else
			local sa = (t - p.start - PARADE_HOP) / PARADE_SHRINK
			if sa >= 1 then
				table.remove(paraders, i)
				RigPool.release(rig)
			else
				local s = Vector3.one * math.max(0.05, 1 - sa)
				Fx.scaleRig(rig, s)
				Fx.appendScaled(rig, CFrame.lookAt(p.to, p.to + p.look), s, moveParts, moveCFrames)
			end
		end
	end
end

-- Sauvages -------------------------------------------------------------------------------------------------

local function newWildView(mirror: Types.WildMirror, focus: Vector3?): WildView
	local rarity = rarityOf(mirror.code)
	local pos = mirror.from or mirror.anchor
	local dist = if focus then (pos - focus).Magnitude else math.huge
	local phase = (mirror.id * 0.618) % 1
	return {
		code = mirror.code,
		stars = 1,
		rig = nil,
		want = lodByDistance(dist, "hidden", distanceMult()),
		dist = dist,
		bubble = false,
		pinned = nil,
		mythic = rarity >= 6,
		bright = rarity >= 5,
		id = mirror.id,
		mirror = mirror,
		pos = pos,
		yaw = phase * TAU,
		phase = phase * TAU,
		blinkPeriod = BLINK_MIN + BLINK_SPREAD * phase,
		dizzy = {},
		ring = nil,
		scaled = false,
	}
end

local function dropWildDecor(view: WildView)
	for _, ball in view.dizzy do
		giveBall(ball)
	end
	table.clear(view.dizzy)
	if view.ring then
		view.ring.Parent = nil
		table.insert(ringPool, view.ring)
		view.ring = nil
	end
end

local function dropWild(id: number)
	local view = wildViews[id]
	if view == nil then
		return
	end
	wildViews[id] = nil
	dropWildDecor(view)
	local rig = view.rig
	if rig then
		view.rig = nil
		Fx.scaleRig(rig, Vector3.one)
		RigPool.release(rig)
	end
end

local function nearestLook(pos: Vector3): Vector3?
	local best: Vector3? = nil
	local bestD = LOOK_DISTANCE
	local lp = localPos
	if lp then
		local d = (lp - pos).Magnitude
		if d <= bestD then
			best, bestD = lp, d
		end
	end
	for _, o in others do
		local d = (o.pos - pos).Magnitude
		if d <= bestD then
			best, bestD = o.pos, d
		end
	end
	return best
end

local function moveWild(view: WildView, t: number)
	local m = view.mirror
	local p = WorldStateController.wildPosition(m, t)
	view.pos = p
	local rig = ensureRig(view, folders.Wild)
	if rig == nil or rig.lod == "hidden" then
		dropWildDecor(view)
		return
	end
	local reduced = Juice.reducedMotion()
	local size = rig.size
	local groundY = WorldLayout.groundY(p.X, p.Z)
	local y = groundY + size / 2
	local scatterEnd = m.t0 + Balance.Snip.ScatterTime
	local flying = m.from ~= nil and t < scatterEnd
	if flying then
		y += Fx.arc((t - m.t0) / Balance.Snip.ScatterTime, Balance.Snip.ScatterHeight)
	elseif not reduced then
		y += WILD_BOB_AMP * (1 + math.sin(WILD_BOB_SPEED * t + view.phase))
	end
	-- regard : joueur le plus proche (≤ 15 studs), sinon sens de la flânerie
	local target = nearestLook(p)
	local desired: number
	if target then
		desired = yawToward(p, target, view.yaw)
	else
		local ahead = WorldStateController.wildPosition(m, t + 0.25)
		desired = yawToward(p, ahead, view.yaw)
	end
	view.yaw += wrapAngle(desired - view.yaw) * LOOK_SMOOTH
	local pos = Vector3.new(p.X, y, p.Z)
	local cf = CFrame.new(pos) * CFrame.Angles(0, view.yaw, 0)
	-- échelle : apparition (0 → 1 Back Out), fin de vie (rétrécit pendant ShrinkTime)
	local scale = 1
	local age = t - m.t0
	if m.from == nil and age < POP_SECONDS and not reduced then
		scale = math.max(0.05, Fx.backOut(age / POP_SECONDS))
	end
	local left = m.expiresAt - t
	if left < Balance.Spawn.ShrinkTime then
		scale = math.min(scale, math.max(0.05, left / Balance.Spawn.ShrinkTime))
	end
	if rig.lod == "full" then
		local blink = view.dist <= BLINK_DISTANCE and ((t + view.phase) % view.blinkPeriod) < BLINK_SECONDS
		NebbyBuilder.animate(rig, { t = t, phase = view.phase, blink = blink, speed = 0 })
	end
	if scale < 1 then
		local s = Vector3.one * scale
		view.scaled = true
		Fx.scaleRig(rig, s)
		Fx.appendScaled(rig, cf, s, moveParts, moveCFrames)
	else
		if view.scaled then
			view.scaled = false
			Fx.scaleRig(rig, Vector3.one)
		end
		NebbyBuilder.appendCFrames(rig, cf, moveParts, moveCFrames)
	end
	-- étourdissement : 3 boules Néon autour de la tête pendant Snip.Dizzy après l'atterrissage
	local dizzyFor = t - scatterEnd
	local dizzy = m.from ~= nil
		and dizzyFor >= 0
		and dizzyFor < Balance.Snip.Dizzy
		and view.dist <= BLINK_DISTANCE
	if dizzy then
		for k = 1, DIZZY_BALLS do
			local ball = view.dizzy[k]
			if ball == nil then
				ball = takeBall()
				view.dizzy[k] = ball
			end
			local angle = TAU * DIZZY_TURNS * dizzyFor + (k - 1) * TAU / DIZZY_BALLS
			local r = DIZZY_RADIUS * size
			append(
				ball :: BasePart,
				CFrame.new(pos + Vector3.new(math.cos(angle) * r, size * 0.65, math.sin(angle) * r))
			)
		end
	elseif #view.dizzy > 0 then
		for _, ball in view.dizzy do
			giveBall(ball)
		end
		table.clear(view.dizzy)
	end
	-- priorité : anneau doré sous SES propres Nebbies libres (victime seulement)
	local mine = m.prioritySlot ~= 0 and m.prioritySlot == localSlotCache and t < m.dizzyUntil + 60
	if mine and not flying then
		local ring = view.ring
		if ring == nil then
			ring = takeRing()
			local r = ring :: BasePart
			r.Parent = folders.Wild
			r.Color = Cosmetics.Readability.Guard
			r.Material = Enum.Material.Neon
			view.ring = r
		end
		local r = ring :: BasePart
		local d = size * 1.5
		if r.Size.Y ~= d then
			r.Size = Vector3.new(RING_THICKNESS, d, d)
		end
		append(r, CFrame.new(p.X, groundY + RING_LIFT, p.Z) * Fx.FLAT)
	elseif view.ring then
		view.ring.Parent = nil
		table.insert(ringPool, view.ring)
		view.ring = nil
	end
end

local function reconcileWilds(focus: Vector3, now: number)
	local mirrors = WorldStateController.wilds()
	for id, view in wildViews do
		if mirrors[id] ~= view.mirror then
			dropWild(id)
		end
	end
	for id, mirror in mirrors do
		if wildViews[id] == nil then
			local view = newWildView(mirror, focus)
			local hand = wildHandoff[id]
			if hand then
				wildHandoff[id] = nil
				if hand.rig.code == mirror.code then
					view.rig = hand.rig
				else
					RigPool.release(hand.rig)
				end
			end
			wildViews[id] = view
		end
	end
	for id, hand in wildHandoff do
		if now - hand.at > HANDOFF_SECONDS then
			wildHandoff[id] = nil
			RigPool.release(hand.rig)
		end
	end
	for slot, queue in catchHandoff do
		for i = #queue, 1, -1 do
			local entry = queue[i]
			if now - entry.at > HANDOFF_SECONDS then
				table.remove(queue, i)
				releaseRig(entry.rig)
			end
		end
		if #queue == 0 then
			catchHandoff[slot] = nil
		end
	end
end

-- Gloomwisps -------------------------------------------------------------------------------------------

local function dropWisp(id: number)
	local view = wispViews[id]
	if view == nil then
		return
	end
	wispViews[id] = nil
	view.preview:Destroy()
	view.target:Destroy()
	NebbyBuilder.destroy(view.rig)
end

local function newWisp(id: number): WispView
	local rig = NebbyBuilder.buildWisp()
	rig.model.Name = "Gloomwisp_" .. id
	local a0 = Instance.new("Attachment")
	a0.Name = "Preview0"
	a0.Parent = rig.body
	local target = Instance.new("Attachment")
	target.Name = "WispAhead_" .. id
	target.Parent = wispAnchor
	local beam = Instance.new("Beam")
	beam.Name = "Preview"
	beam.Attachment0 = a0
	beam.Attachment1 = target
	beam.Width0 = 0.6
	beam.Width1 = 0.3
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(WISP_PREVIEW_COLOR)
	beam.Transparency = Fx.dashed(4)
	beam.Parent = rig.body
	rig.model.Parent = folders.Wisps
	return { id = id, rig = rig, preview = beam, target = target, pos = Vector3.zero }
end

local function moveWisps(t: number, focus: Vector3)
	local ev = WorldStateController.events()
	local alive = aliveWisps
	table.clear(alive)
	if ev then
		for _, w in ev.wisps do
			local ground = WorldStateController.wispPosition(w.id, t)
			if ground then
				alive[w.id] = true
				local view = wispViews[w.id]
				if view == nil then
					view = newWisp(w.id)
					wispViews[w.id] = view
				end
				local v = view :: WispView
				local pos = ground + Vector3.new(0, WISP_HOVER + WISP_BOB * math.sin(3 * t + w.id), 0)
				v.pos = pos
				if (pos - focus).Magnitude <= WISP_RANGE then
					local ahead = WorldStateController.wispPosition(w.id, t + 0.2) or ground
					local yaw = yawToward(ground, ahead, 0)
					NebbyBuilder.animate(
						v.rig,
						{ t = t, phase = w.id, blink = false, speed = Balance.Wisps.Speed }
					)
					NebbyBuilder.appendCFrames(
						v.rig,
						CFrame.new(pos) * CFrame.Angles(0, yaw, 0),
						moveParts,
						moveCFrames
					)
					local dir = ahead - ground
					local flat = Vector3.new(dir.X, 0, dir.Z)
					local unit = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
					v.target.Position = pos + unit * Balance.Wisps.PreviewStuds
					v.preview.Enabled = unit ~= Vector3.zero
				end
			end
		end
	end
	for id in wispViews do
		if not alive[id] then
			dropWisp(id)
		end
	end
end

-- Orbe de la Comète (au sol ou au-dessus du porteur) --------------------------------------------------------

local function moveOrb(t: number)
	local ev = WorldStateController.events()
	local c = if ev then ev.comet else nil
	local phase = if c then c.phase else nil
	if phase ~= "ground" and phase ~= "carried" then
		if orb then
			NebbyBuilder.destroy(orb.rig)
			orb = nil
		end
		return
	end
	local target = WorldStateController.cometPosition(t)
	if target == nil then
		return
	end
	local o = orb
	if o == nil then
		local rig = NebbyBuilder.buildCometOrb()
		rig.model.Parent = folders.Comet
		o = { rig = rig, pos = nil, carrier = 0, arcFrom = nil, arcStart = -math.huge }
		orb = o
	end
	local view = o :: OrbView
	local cometState = c :: Types.CometState
	local carrier = if phase == "carried" then cometState.carrierId or 0 else 0
	if carrier ~= view.carrier then
		-- ramassage, vol ou chute : l'orbe file en arc de 0,2 s vers sa nouvelle place
		view.carrier = carrier
		if view.pos and not Juice.reducedMotion() then
			view.arcFrom = view.pos
			view.arcStart = t
		end
	end
	local pos = target :: Vector3
	if phase == "ground" then
		pos += Vector3.new(0, ORB_HOVER + ORB_BOB * math.sin(2 * t), 0)
	end
	local arcFrom = view.arcFrom
	if arcFrom then
		local a = (t - view.arcStart) / STEAL_SECONDS
		if a < 1 then
			pos = arcFrom:Lerp(pos, a) + Vector3.new(0, Fx.arc(a, ORB_ARC), 0)
		else
			view.arcFrom = nil
		end
	end
	view.pos = pos
	NebbyBuilder.animate(view.rig, { t = t, phase = 0, blink = false, speed = 0 })
	NebbyBuilder.appendCFrames(view.rig, CFrame.new(pos), moveParts, moveCFrames)
end

-- Planificateur (10 Hz) : LOD, budgets, Highlights, lumières, lisibilité ------------------------------------

local function refreshOthers()
	table.clear(others)
	local me = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		if player ~= me then
			local part = rootOf(player)
			local pos: Vector3? = if part then part.Position else nil
			if pos == nil then
				local slot = WorldStateController.slotOf(player.UserId)
				local trail = if slot ~= 0 then WorldStateController.trail(slot) else nil
				pos = if trail then trail:head() else nil
			end
			if pos then
				table.insert(others, { userId = player.UserId, pos = pos })
			end
		end
	end
end

local function isTruce(t: number): boolean
	local ev = WorldStateController.events()
	local b = if ev then ev.beacon else nil
	if b == nil then
		return false
	end
	return (b.phase == "active" or b.phase == "success") and t >= b.startsAt and t < b.endsAt
end

local function guardOf(player: Player?, isLocal: boolean): number
	if isLocal then
		local upgrades = State.get("upgrades")
		local level = if type(upgrades) == "table" and type(upgrades.guard) == "number"
			then upgrades.guard
			else 0
		return Formulas.guardLinks(level)
	end
	local g = attr(player, "GuardLinks")
	if type(g) == "number" and g == g then
		return math.clamp(math.floor(g), 0, Balance.Guard.Max)
	end
	return Balance.Guard.Base
end

-- Mode des anneaux d'une file (rose/doré/bleu, pointillés de sa propre queue, ou style)
local function readability(view: LineView, t: number)
	local me = Players.LocalPlayer
	local isLocal = view.slot == localSlotCache and view.slot ~= 0
	local owner = playerOf(view.userId)
	view.guard = guardOf(owner, isLocal)
	view.bubble = attr(owner, "Rookie") == true
	view.styleKey = NestDisplay.lineStyle(view.slot)
	view.nestColor = NestDisplay.nestColor(view.slot)
	local r = attr(owner, "Supernovas")
	local auraKey = if type(r) == "number" and r == r then Formulas.auraFor(r) else nil
	local aura = if auraKey then Cosmetics.Auras[auraKey] else nil
	view.auraColor = if aura then aura.color else nil
	view.mode = "style"
	table.clear(view.escorted)
	local lp = localPos
	if lp == nil or #view.nodes == 0 or isTruce(t) then
		return
	end
	local ev = WorldStateController.events()
	if ev and ev.snipsDisabled then
		return
	end
	local function protected(player: Player?): boolean
		if player == nil then
			return false
		end
		local immune = player:GetAttribute("ImmuneUntil")
		return player:GetAttribute("Zen") == true
			or player:GetAttribute("Rookie") == true
			or (type(immune) == "number" and immune > t)
	end
	if isLocal then
		if protected(me) then
			return
		end
		local warnDistance = Render.TailWarnDistance
		for _, o in others do
			if not WorldStateController.isCrewmate(o.userId) then
				for i = view.guard + 1, #view.nodes do
					if (view.nodes[i].pos - o.pos).Magnitude <= warnDistance then
						view.mode = "warn"
						return
					end
				end
			end
		end
		return
	end
	if me == nil or WorldStateController.isCrewmate(view.userId) or protected(owner) then
		return
	end
	if me:GetAttribute("Zen") == true then
		return
	end
	local near = false
	local cutDistance = Render.CutWarnDistance
	for _, node in view.nodes do
		if (node.pos - lp).Magnitude <= cutDistance then
			near = true
			break
		end
	end
	if not near then
		return
	end
	view.mode = "cut"
	-- escorte : nœuds à ≤ EscortRadius d'un équipier du propriétaire
	local crew = WorldStateController.crewOf(view.userId)
	if crew ~= 0 then
		for _, o in others do
			if o.userId ~= view.userId and WorldStateController.crewOf(o.userId) == crew then
				for i, node in view.nodes do
					if (node.pos - o.pos).Magnitude <= Balance.Crew.EscortRadius then
						view.escorted[i] = true
					end
				end
			end
		end
	end
end

-- Attribution DIFFÉRENTIELLE des Highlights et PointLights (planificateur à 10 Hz) : un rig qui
-- garde sa décoration n'est ni ré-adorné ni re-parenté (sinon 10 changements d'Adornee / de
-- Parent par seconde et par décoration : recalculs du moteur et scintillement)
type DecorWant = { rig: Rig, color: Color3, fill: number }

local function keepExisting(
	wanted: { DecorWant },
	current: { [Rig]: any }
): ({ [Rig]: any }, { [any]: boolean })
	local keep: { [Rig]: any } = {}
	local used: { [any]: boolean } = {}
	for _, w in wanted do
		local decor = current[w.rig]
		if decor ~= nil and not used[decor] then
			keep[w.rig] = decor
			used[decor] = true
		end
	end
	return keep, used
end

local function applyHighlights(wanted: { DecorWant })
	local keep, used = keepExisting(wanted, highlightOf)
	for rig, hl in highlightOf do
		if keep[rig] ~= hl then
			highlightOf[rig] = nil
			if not used[hl] then
				hl.Enabled = false
				hl.Adornee = nil
			end
		end
	end
	local cursor = 1
	for _, w in wanted do
		local hl: Highlight? = keep[w.rig]
		if hl == nil then
			while highlights[cursor] ~= nil and used[highlights[cursor]] do
				cursor += 1
			end
			local free = highlights[cursor]
			if free == nil then
				local created = Instance.new("Highlight")
				created.Name = "NebbyHighlight"
				created.DepthMode = Enum.HighlightDepthMode.Occluded
				created.OutlineTransparency = 0
				created.Enabled = false
				created.Parent = folders.Lines
				highlights[cursor] = created
				free = created
			end
			used[free] = true
			hl = free
		end
		local h = hl :: Highlight
		highlightOf[w.rig] = h
		if h.Adornee ~= w.rig.model then
			h.Adornee = w.rig.model
		end
		if h.FillColor ~= w.color then
			h.FillColor = w.color
		end
		if h.OutlineColor ~= w.color then
			h.OutlineColor = w.color
		end
		if h.FillTransparency ~= w.fill then
			h.FillTransparency = w.fill
		end
		if h.OutlineTransparency ~= 0 then
			h.OutlineTransparency = 0
		end
		if not h.Enabled then
			h.Enabled = true
		end
	end
end

local function applyLights(wanted: { DecorWant })
	local keep, used = keepExisting(wanted, lightOf)
	for rig, light in lightOf do
		if keep[rig] ~= light then
			lightOf[rig] = nil
			if not used[light] then
				light.Parent = nil
			end
		end
	end
	local cursor = 1
	for _, w in wanted do
		local light: PointLight? = keep[w.rig]
		if light == nil then
			while lights[cursor] ~= nil and used[lights[cursor]] do
				cursor += 1
			end
			local free = lights[cursor]
			if free == nil then
				local created = Instance.new("PointLight")
				created.Name = "RarityLight"
				created.Shadows = false
				created.Brightness = 1.2
				lights[cursor] = created
				free = created
			end
			used[free] = true
			light = free
		end
		local l = light :: PointLight
		lightOf[w.rig] = l
		if l.Color ~= w.color then
			l.Color = w.color
		end
		local range = 6 + 2 * w.rig.size
		if l.Range ~= range then
			l.Range = range
		end
		if l.Parent ~= w.rig.body then
			l.Parent = w.rig.body
		end
	end
end

local function plan(t: number, focus: Vector3)
	localSlotCache = WorldStateController.localSlot()
	RigPool.setLowGraphics(lowGraphics())
	refreshOthers()
	local mult = distanceMult()
	table.clear(planViews)
	local lineOrder: { LineView } = {}
	for _, view in lineViews do
		readability(view, t)
		local headNode = view.nodes[1]
		view.dist = if headNode then (headNode.pos - focus).Magnitude else math.huge
		local farLimit = Render.BallDistance * mult + (if view.far then LOD_HYSTERESIS else -LOD_HYSTERESIS)
		view.far = view.dist > farLimit and view.slot ~= localSlotCache
		for i, node in view.nodes do
			node.dist = (node.pos - focus).Magnitude
			node.bubble = view.bubble
			node.pinned = if view.far then (if i == 1 then "ball" else "hidden") else nil
			table.insert(planViews, node :: any)
		end
		table.insert(lineOrder, view)
	end
	for _, view in wildViews do
		view.dist = (view.pos - focus).Magnitude
		table.insert(planViews, view :: any)
	end
	NestDisplay.views(planViews, focus)
	table.sort(planViews, function(a, b)
		return a.dist < b.dist
	end)
	local full, used = 0, 0
	local mythics: { RigPool.View } = {}
	local brights: { RigPool.View } = {}
	for _, v in planViews do
		local want: Lod
		if v.pinned then
			want = v.pinned :: Lod
		else
			local current: Lod = if v.rig then (v.rig :: Rig).lod else "hidden"
			want = lodByDistance(v.dist, current, mult)
		end
		if want == "full" and full >= Render.MaxFullDetail then
			want = "ball"
		end
		local cost = RigPool.partCount(v.code, want)
		if used + cost > Render.MaxNebbyParts then
			want = if used + 1 <= Render.MaxNebbyParts then "ball" else "hidden"
			cost = if want == "ball" then 1 else 0
		end
		if want == "full" then
			full += 1
			cost += 1 -- anneau sous le Nebby
		end
		used += cost
		v.want = want
		if v.mythic and want ~= "hidden" and #mythics < MAX_MYTHIC_HIGHLIGHTS then
			table.insert(mythics, v)
		end
		if v.bright and want == "full" and #brights < MAX_LIGHTS then
			table.insert(brights, v)
		end
	end
	-- Highlights : 4 files ≥ 20 les plus proches, 6 Mythiques+ (aucun en Graphismes légers)
	local wantHl: { DecorWant } = {}
	if not lowGraphics() then
		table.sort(lineOrder, function(a, b)
			return a.dist < b.dist
		end)
		local picked: { [Rig]: boolean } = {}
		local lineCount = 0
		for _, view in lineOrder do
			if lineCount >= MAX_LINE_HIGHLIGHTS then
				break
			end
			local head = view.nodes[1]
			local rig = if head then head.rig else nil
			if #view.nodes >= Render.CrownLine and head ~= nil and rig ~= nil and head.want ~= "hidden" then
				lineCount += 1
				picked[rig] = true
				local color = NestDisplay.nestColor(view.slot)
				table.insert(wantHl, { rig = rig, color = color, fill = 1 })
			end
		end
		for _, v in mythics do
			local rig = v.rig
			if rig and not picked[rig] then
				picked[rig] = true
				local rarity = Nebbies.Rarities[rarityOf(v.code)]
				table.insert(wantHl, { rig = rig, color = rarity.color, fill = 0.8 })
			end
		end
	end
	applyHighlights(wantHl)
	-- PointLights : 6 Légendaires+ en détail complet les plus proches (≤ 60 studs en Graphismes légers)
	local wantLights: { DecorWant } = {}
	for _, v in brights do
		local rig = v.rig
		if rig and rig.lod == "full" and (not lowGraphics() or v.dist <= Render.LowGraphicsLightDistance) then
			local rarity = Nebbies.Rarities[rarityOf(v.code)]
			table.insert(wantLights, { rig = rig, color = rarity.color, fill = 0 })
		end
	end
	applyLights(wantLights)
	NestDisplay.step(t, focus)
end

-- Image ----------------------------------------------------------------------------------------------------

local function onFrame(dt: number)
	local t = Clock.now()
	rebuilds = 0
	table.clear(moveParts)
	table.clear(moveCFrames)
	local me = Players.LocalPlayer
	local myRoot = rootOf(me)
	if myRoot then
		local p = myRoot.Position
		localPos = p
		localTrail:push(p)
	else
		localPos = nil
	end
	local focus = localPos or cameraPosition()
	NestDisplay.focus = focus
	-- files : création, suppression, réconciliation avec le miroir
	for slot = 1, SLOT_COUNT do
		local line = WorldStateController.line(slot)
		local view = lineViews[slot]
		if line == nil then
			if view then
				dropLine(slot)
			end
		else
			if view == nil or view.userId ~= line.userId then
				if view then
					dropLine(slot)
				end
				view = newLineView(slot, line.userId)
				lineViews[slot] = view
			end
			reconcileLine(view :: LineView, line.codes, focus, t)
		end
	end
	reconcileWilds(focus, t)
	if t >= nextPlan or t < nextPlan - 1 then
		nextPlan = t + PLAN_INTERVAL
		plan(t, focus)
	end
	for _, view in lineViews do
		moveLine(view, t, dt)
	end
	updateMarkers(t)
	for _, view in wildViews do
		moveWild(view, t)
	end
	NestDisplay.collect(t, moveParts, moveCFrames, ensurePerched)
	NestDisplay.animateLinks(t)
	moveParaders(t)
	moveWisps(t, focus)
	moveOrb(t)
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Réactions aux signaux de WorldStateController -------------------------------------------------------------

local function onCaught(slot: number, code: number, id: number, pos: Vector3?)
	local view = if id ~= 0 then wildViews[id] else nil
	local rig: Rig? = nil
	local from = pos
	if view then
		rig = view.rig
		view.rig = nil
		dropWildDecor(view)
		from = view.pos
	end
	local queue = catchHandoff[slot]
	if queue == nil then
		queue = {}
		catchHandoff[slot] = queue
	end
	table.insert(queue, { code = code, rig = rig, from = from, at = Clock.now() })
end

local function handOffNodes(view: LineView, first: number, ids: { number })
	local now = Clock.now()
	for k, id in ids do
		local node = view.nodes[first + k - 1]
		if node and node.rig and type(id) == "number" then
			local rig = node.rig :: Rig
			node.rig = nil
			Fx.scaleRig(rig, Vector3.one)
			local old = wildHandoff[id]
			if old then
				RigPool.release(old.rig)
			end
			wildHandoff[id] = { rig = rig, at = now }
		end
	end
	for i = #view.nodes, first, -1 do
		dropNode(view.nodes[i])
		view.nodes[i] = nil
	end
end

local function onSnipped(payload: Types.SnipEventPayload)
	local view = lineViews[payload.victimSlot]
	if view == nil then
		return
	end
	local cut = view.nodes[payload.cutIndex]
	if cut and cut.rig then
		flash(cut.rig)
	end
	handOffNodes(view, payload.cutIndex, payload.looseIds)
end

local function onLineOp(slot: number, op: Types.LineOp)
	if op.op == "clear" then
		local view = lineViews[slot]
		if view then
			local ids: { number } = {}
			for _, spawn in (op :: Types.LineClearOp).loose do
				if type(spawn) == "table" and type(spawn.id) == "number" then
					table.insert(ids, spawn.id)
				end
			end
			handOffNodes(view, 1, ids)
		end
	elseif op.op == "owner" then
		if slot == localSlotCache or slot == WorldStateController.localSlot() then
			localTrail = Trail.new(Conga.TrailLength, Conga.TrailMinStep)
		end
	end
end

-- Cycle de vie -----------------------------------------------------------------------------------------------

function CongaRenderer.Init()
	local world = Fx.clientWorld()
	for _, name in { "Lines", "Wild", "Perched", "Wisps", "Comet" } do
		folders[name] = Fx.folder(world, name)
	end
	wispAnchor = Fx.anchor("WispAnchor", folders.Wisps)
	local hl = Instance.new("Highlight")
	hl.Name = "SnipFlash"
	hl.Enabled = false
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = world
	flashHighlight = hl
	RigPool.beforeRebuild = detachDecor
	NestDisplay.init(folders.Perched)
end

function CongaRenderer.Start()
	if started then
		return
	end
	started = true
	NestDisplay.start()
	WorldStateController.Caught:Connect(onCaught)
	WorldStateController.Snipped:Connect(onSnipped)
	WorldStateController.LineOp:Connect(onLineOp)
	WorldStateController.Banked:Connect(function(slot: number, op: Types.LineBankOp)
		startParade(slot, op.atBeacon == true)
	end)
	-- Atlas modifié (encaissement, récompense, instantané) : les « ? » sont recalculés
	State.Changed:Connect(function(key: string)
		if key == "atlas" then
			atlasVersion += 1
		end
	end)
	local me = Players.LocalPlayer
	if me then
		me.CharacterAdded:Connect(function()
			localTrail = Trail.new(Conga.TrailLength, Conga.TrailMinStep)
		end)
	end
	RunService.RenderStepped:Connect(onFrame)
end

-- API ----------------------------------------------------------------------------------------------------------

-- Positions rendues des nœuds de la file d'un slot (dernière image)
function CongaRenderer.nodePositions(slot: number): { Vector3 }
	local view = lineViews[slot]
	if view == nil then
		return {}
	end
	local out = table.create(#view.nodes)
	for i, node in view.nodes do
		out[i] = node.pos
	end
	return out
end

-- Modèle rendu du nœud `index` du slot (nil si masqué)
function CongaRenderer.nodeModel(slot: number, index: number): Model?
	local view = lineViews[slot]
	local node = if view then view.nodes[index] else nil
	local rig = if node then node.rig else nil
	if rig and rig.lod ~= "hidden" then
		return rig.model
	end
	return nil
end

-- Modèle rendu d'un sauvage (nil si masqué)
function CongaRenderer.wildModel(id: number): Model?
	local view = wildViews[id]
	local rig = if view then view.rig else nil
	if rig and rig.lod ~= "hidden" then
		return rig.model
	end
	return nil
end

-- Nombre de pièces de Nebbies actuellement rendues (budget)
function CongaRenderer.renderedParts(): number
	local n = 0
	local function count(rig: Rig?)
		if rig and rig.lod ~= "hidden" then
			n += #rig.parts
		end
	end
	for _, view in lineViews do
		for _, node in view.nodes do
			count(node.rig)
		end
	end
	for _, view in wildViews do
		count(view.rig)
	end
	for slot = 1, SLOT_COUNT do
		for i = 1, NestDisplay.perchedCount(slot) do
			count(NestDisplay.perchedRig(slot, i))
		end
	end
	for _, p in paraders do
		count(p.rig)
	end
	return n
end

-- Ajouts du paquet client-world (lus par VFXController, plus tardif) ---------------------------------------------

-- Nebbies rendus en détail complet (budget ≤ 100)
function CongaRenderer.fullDetailCount(): number
	local n = 0
	for _, view in lineViews do
		for _, node in view.nodes do
			if node.rig and node.rig.lod == "full" then
				n += 1
			end
		end
	end
	for _, view in wildViews do
		if view.rig and view.rig.lod == "full" then
			n += 1
		end
	end
	for slot = 1, SLOT_COUNT do
		for i = 1, NestDisplay.perchedCount(slot) do
			local rig = NestDisplay.perchedRig(slot, i)
			if rig and rig.lod == "full" then
				n += 1
			end
		end
	end
	return n
end

-- Highlights et PointLights attribués par le planificateur (budgets §12.8)
function CongaRenderer.decorCounts(): (number, number)
	local h, l = 0, 0
	for _ in highlightOf do
		h += 1
	end
	for _ in lightOf do
		l += 1
	end
	return h, l
end

-- Mode des anneaux de lisibilité d'une file ("style" | "cut" | "warn"), nil si aucune file
function CongaRenderer.lineMode(slot: number): string?
	local view = lineViews[slot]
	return if view then view.mode else nil
end

-- Étiquette « ×N » affichée pour une file lointaine (nil sinon)
function CongaRenderer.lineLabel(slot: number): string?
	local view = lineViews[slot]
	if view and view.label and view.label.Enabled and view.labelText then
		return view.labelText.Text
	end
	return nil
end

-- Index (croissants) des nœuds de la file locale qui portent un « ? » doré (entrée d'Atlas inconnue)
function CongaRenderer.newEntryMarkers(): { number }
	local out: { number } = {}
	for _, m in markerOf do
		if m.gui.Enabled and m.index > 0 then
			table.insert(out, m.index)
		end
	end
	table.sort(out)
	return out
end

-- Nebbies en cours de saut vers les perchoirs
function CongaRenderer.paradeCount(): number
	return #paraders
end

function CongaRenderer.wispModel(id: number): Model?
	local view = wispViews[id]
	return if view then view.rig.model else nil
end

-- Orbe de la Comète (nil hors des phases au sol / portée)
function CongaRenderer.cometOrb(): Model?
	return if orb then orb.rig.model else nil
end

function CongaRenderer.cometOrbPosition(): Vector3?
	return if orb then orb.pos else nil
end

function CongaRenderer.perchTop(slot: number, index: number): Vector3?
	return NestDisplay.perchTop(slot, index)
end

function CongaRenderer.perchCount(slot: number): number
	return NestDisplay.perchCount(slot)
end

function CongaRenderer.constellationStar(slot: number, index: number): BasePart?
	return NestDisplay.constellationStar(slot, index)
end

function CongaRenderer.nestColor(slot: number): Color3
	return NestDisplay.nestColor(slot)
end

-- Position affichée de la tête de file d'un slot (personnage local ou miettes), nil si inconnue
function CongaRenderer.headPosition(slot: number): Vector3?
	if slot ~= 0 and slot == localSlotCache then
		return localTrail:head()
	end
	local trail = WorldStateController.trail(slot)
	return if trail then trail:head() else nil
end

CongaRenderer.NestDisplay = NestDisplay

return CongaRenderer
