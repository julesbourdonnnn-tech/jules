--!strict
-- BigPlop (lot B5, étape 3 ; GDD v2.0 §4.15 « Chantier de Big Plop », §9.4 lignes « Chantier » et
-- « Un achat », §4.27 geste vers l'Observatoire ; plan B5 D19, D29) : un petit Big Plop du client,
-- UN modèle à la fois (SquishyBuilder, espèce Plop, nœud papillon, 3 studs de diamètre) avec deux
-- pièces à lui : la coiffe (casque jaune du chantier, bonnet d'hiver) et le maillet.
--
--   BigPlop.start()      -- VFXController.Start l'appelle (le module n'est pas dans l'ordre du client)
--   BigPlop.stop()       -- coupe tout, rend chaque instance (fin, specs)
--   BigPlop._step(dt)    -- une image (RenderStepped, seulement tant qu'il y a quelque chose à faire)
--   BigPlop.stats()      -- compteurs (specs, Diagnostics)
--   BigPlop._state()     -- spectacle en cours (specs)
--   BigPlop._configure(sources)   -- specs : son, vibration, instantané, attribut, coût d'un hiver
--   BigPlop._reset()     -- specs : le geste redevient possible (nouvelle séance)
--
-- Chantier (V6) : quand RanchRenderer.ElementBuilt(slot, id) part (premier passage d'un élément v2.0,
-- jamais au chargement) pour un ranch en détail complet, Big Plop casqué se tient 2 studs à côté de
-- RanchRenderer.elementCFrame(slot, id), tourné vers l'élément, et donne 3 coups de maillet (0,6 ;
-- 1,4 ; 2,2 s) pendant que la pièce se construit ; 4 s en tout, coupure dure à 6 s. Pour MON ranch
-- seulement : son ChantierTap (repli Click) et vibration « chantier » à chaque coup, étiquette
-- « Nouveau : <nom> » (clé card.unlockNew des cartes « Nouveau » du lot B3) 3 s. Non bloquant : la
-- caméra ne bouge jamais, aucune flèche, aucune entrée prise. Jamais pendant un grand spectacle
-- (Rush, MEGA, Grand Splorch, Ascension, danse) : coupé à l'image même s'il en commence un. Un seul
-- chantier à la fois : un élément qui arrive pendant un chantier n'en démarre pas un autre. Les
-- éléments du ciel et de la silhouette (sky, frame.golden, giant.sun) n'ont pas de chantier.
-- Geste vers l'Observatoire (V7) : dans MON ranch seulement, une fois par séance, 6 studs devant mon
-- personnage, tourné vers WorldLayout.observatory(), 3 bonds et une rangée de 3 points Neon vers
-- l'Observatoire, 4 s ; déclencheur = la condition de la carte Conseillé « Jelly Ascend » du lot B2
-- (attribut AscendReady de mon ranch, instantané de l'écran Améliorations valide, aucun achat de
-- pièces possible depuis Balance.Ascend.DeclineCardAfter = 300 s), lue 1 fois par seconde au plus,
-- seulement avec JellyAscend ouvert (World/Flags) ; UI/UpgradeSnapshot et Hud/UpgradeView ne sont
-- requis qu'à ce moment (pcall).
-- Hiver (V8) : tant que le costume d'hiver est posé (LightingController.resolve(...).winter, le même
-- test que l'éclairage), l'écharpe d'hiver remplace le nœud papillon et la coiffe est un bonnet (le
-- casque gagne pendant un chantier).
-- Interrupteurs coupés : ElementBuilt ne part jamais (aucun élément v2.0), JellyAscend fermé : aucune
-- boucle par image, aucune instance ; deux connexions de signaux seulement (ElementBuilt, Flags).
-- Système « bigPlop » de Render/VisualBudget : 17 pièces (12 du modèle, coiffe, maillet, 3 points).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Sounds = require(Shared.Config.Sounds)
local Species = require(Shared.Config.Species)
local WorldLayout = require(Shared.Logic.WorldLayout)
local SquishyBuilder = require(Shared.Render.SquishyBuilder)

local Client = script.Parent.Parent
local Flags = require(Client.World.Flags)
local Util = require(Client.World.Util)
local Prefs = require(Client.Util.Prefs)
local Haptics = require(Client.Util.Haptics)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local LightingController = require(Client.Controllers.LightingController)
local RanchRenderer = require(Client.Controllers.RanchRenderer)
local WorldText = require(Client.UI.WorldText)
local VisualBudget = require(Client.Render.VisualBudget)
-- lot B5, étape 4 : aucun Chantier ne commence sur un ranch dont le Petit Splorch (ou l'Ascension) se joue
local ShowsV2 = require(Client.World.ShowsV2)

local BigPlop = {}

-- Chantier (GDD §4.15, §9.4)
local CHANTIER_TIME = 4 -- s
local CHANTIER_CUT = 6 -- s : coupure dure
local TAPS = { 0.6, 1.4, 2.2 } -- s
local TAP_SWING = 0.25 -- s : le maillet monte puis frappe
local LABEL_TIME = 3 -- s
local SIDE = 2 -- studs à côté de l'élément
local NO_CHANTIER: { [string]: boolean } = { sky = true, ["frame.golden"] = true, ["giant.sun"] = true }
-- Geste (GDD §4.27)
local GESTURE_TIME = 4
local GESTURE_AHEAD = 6 -- studs devant mon personnage
local GESTURE_HOPS = { 0.3, 1.1, 1.9 } -- s : 3 bonds
local HOP_TIME = 0.5
local HOP_HEIGHT = 1.2
local DOT_GAP = 1.6 -- studs entre les points
local POLL = 1 -- s entre deux lectures de la condition
-- Modèle
local SCALE = 1.5 -- × diamètre de base (2 studs) : 3 studs, « petit Big Plop »
local SYSTEM = "bigPlop"
local LIMITS = table.freeze({ parts = 17, particles = 0, lights = 0 })
local DOTS = 3
local LABEL_DISTANCE = 80
local HELMET = Color3.fromRGB(255, 205, 40)
local HAT = Color3.fromRGB(220, 60, 70)
local MALLET = Color3.fromRGB(150, 100, 60)
local DOT = Color3.fromRGB(120, 220, 255)
local SHOW_CAP = 30 -- s : un grand spectacle compte ce temps-là au plus

type Show = {
	kind: "chantier" | "gesture",
	slot: number,
	id: string,
	mine: boolean,
	startedAt: number,
	base: CFrame, -- pied de Big Plop, tourné vers ce qu'il regarde
	taps: number, -- coups déjà donnés
	label: BillboardGui?,
	labelUntil: number,
	handle: SquishyBuilder.Handle?,
	head: Part?,
	mallet: Part?,
	dots: { Part },
	taken: number, -- pièces réservées dans le budget
}

local show: Show? = nil
local started = false
local connections: { RBXScriptConnection } = {}
local stepConn: RBXScriptConnection? = nil
local folder: Folder? = nil
local gestureDone = false
local pollAcc = 0
local firstSeenAt: number? = nil
local lastPayableAt: number? = nil
local declared = false
local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}
local partPool: { Part } = {}

local counters = { chantiers = 0, gestures = 0, taps = 0, cut = 0, labels = 0, polls = 0, refused = 0 }

-- Sources remplaçables par les specs
local sources: {
	play: ((string) -> ())?,
	haptic: ((string) -> ())?,
	snapshot: (() -> any)?,
	payable: ((any) -> boolean)?,
	attr: ((string) -> any)?,
	winter: (() -> boolean)?,
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

local function playSound(name: string, fallback: string)
	local def: any = (Sounds :: any)[name]
	local key = if type(def) == "table" and type(def.id) == "string" and def.id ~= "" then name else fallback
	local fn = sources.play
	if fn then
		pcall(fn, key)
		return
	end
	Util.safe("AudioController.play", nil, AudioController.play, key)
end

local function haptic(name: string)
	local fn = sources.haptic
	if fn then
		pcall(fn, name)
		return
	end
	Util.safe("Haptics.play", false, Haptics.play, name)
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
	local sub = (root :: Instance):FindFirstChild("BigPlop")
	if sub == nil or not sub:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = "BigPlop"
		created.Parent = root
		sub = created
	end
	folder = sub :: Folder
	return sub :: Folder
end

-- Grand spectacle en cours : Rush, MEGA, Grand Splorch, Ascension, danse de la jauge
local function bigShow(): boolean
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) ~= "table" then
		return false
	end
	if type(ev.rush) == "table" and ev.rush.active == true then
		return true
	end
	if type(ev.mega) == "table" and type(ev.mega.phase) == "string" and ev.mega.phase ~= "idle" then
		return true
	end
	local spectacle = ev.spectacle
	local current = if type(spectacle) == "table" then spectacle.current else nil
	if type(current) == "table" then
		local kind = current.kind
		if kind == "splorch" or kind == "dance" or kind == "ascend" then
			local ends = current.endsAt
			local now = Clock.now()
			return not finite(ends) or now <= math.min(ends, now + SHOW_CAP)
		end
	end
	return false
end

local function winter(): boolean
	local fn = sources.winter
	if fn then
		local ok, v = pcall(fn)
		return ok and v == true
	end
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	local ok, resolved = pcall(LightingController.resolve, ev, Clock.now(), false, Clock.unix())
	return ok and type(resolved) == "table" and resolved.winter == true
end

-- Nom (clé) d'un élément : paliers, Monuments, maisonnette (comme les cartes « Nouveau » du lot B3)
local function elementName(id: string): string?
	local n = tonumber(string.match(id, "^tier(%d)%.%a+$") or "")
	if n then
		return if n >= 1 and n <= 6 then "ranchTier." .. n else nil
	end
	local m = tonumber(string.match(id, "^monument%.(%d+)$") or "")
	if m then
		return if m >= 1 and m <= #Balance.Monuments.OpenAt then "monument." .. m else nil
	end
	if id == "helper.house" then
		return "helper.house"
	end
	return nil
end

-- =============================================================================================
-- Modèle
-- =============================================================================================

local function takePart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, neon: boolean): Part
	local p = table.remove(partPool)
	if p == nil then
		local created = Instance.new("Part")
		created.Anchored = true
		created.CanCollide = false
		created.CanQuery = false
		created.CanTouch = false
		created.CastShadow = false
		p = created
	end
	local part = p :: Part
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	-- un point du geste rendu encore invisible ne fait pas un casque invisible (relecture approfondie
	-- B5, journal B5-66)
	part.Transparency = 0
	part.Parent = clientFolder()
	return part
end

local function givePart(p: Part?)
	if p == nil then
		return
	end
	p.Parent = nil
	if #partPool < 8 then
		table.insert(partPool, p)
	else
		p:Destroy()
	end
end

-- Construit le petit Big Plop d'un spectacle ; faux si le budget le refuse (rien n'est montré)
local function dress(s: Show, helmet: boolean, dots: boolean): boolean
	if not declared then
		declared = VisualBudget.declare(SYSTEM, LIMITS)
	end
	local cold = winter()
	local spec = {
		species = Species.PLOP,
		mutation = 0,
		stars = 0,
		displayScale = SCALE,
		lod = 1,
		outfit = if cold then "winterScarf" else "bowTie",
	}
	-- pièces à lui : casque et maillet (chantier), bonnet (hiver), 3 points (geste)
	local own = if helmet then 2 elseif cold then 1 else 0
	local need = SquishyBuilder.partCount(spec :: any) + own + (if dots then DOTS else 0)
	if not VisualBudget.take(SYSTEM, need) then
		counters.refused += 1
		return false
	end
	s.taken = need
	local ok, h = pcall(SquishyBuilder.build, spec :: any, clientFolder())
	if not ok or type(h) ~= "table" then
		VisualBudget.release(SYSTEM, need)
		s.taken = 0
		return false
	end
	s.handle = h
	pcall(SquishyBuilder.setParticles, h, 0)
	local d = Balance.SizeScale.BaseDiameter * SCALE
	if helmet then
		s.head =
			takePart("Helmet", Enum.PartType.Ball, Vector3.new(d * 0.55, d * 0.3, d * 0.55), HELMET, false)
		s.mallet = takePart("Mallet", Enum.PartType.Block, Vector3.new(0.5, 0.35, 0.8), MALLET, false)
	elseif cold then
		s.head =
			takePart("WinterHat", Enum.PartType.Ball, Vector3.new(d * 0.5, d * 0.35, d * 0.5), HAT, false)
	end
	if dots then
		for i = 1, DOTS do
			s.dots[i] = takePart("Dot" .. i, Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), DOT, true)
		end
	end
	return true
end

local function undress(s: Show)
	local h = s.handle
	s.handle = nil
	if h then
		pcall(SquishyBuilder.release, h)
	end
	givePart(s.head)
	givePart(s.mallet)
	s.head, s.mallet = nil, nil
	for i = #s.dots, 1, -1 do
		givePart(s.dots[i])
		s.dots[i] = nil
	end
	local gui = s.label
	s.label = nil
	if gui then
		pcall(WorldText.release, gui)
	end
	if s.taken > 0 then
		VisualBudget.release(SYSTEM, s.taken)
		s.taken = 0
	end
end

-- =============================================================================================
-- Boucle par image (branchée seulement tant qu'il y a quelque chose à faire, D29)
-- =============================================================================================

local function needLoop(): boolean
	return show ~= nil or (not gestureDone and Flags.on("JellyAscend"))
end

local refreshLoop

local function finish(cut: boolean)
	local s = show
	if s == nil then
		return
	end
	show = nil
	if cut then
		counters.cut += 1
	end
	undress(s)
	refreshLoop()
end

local function pose(s: Show, t: number)
	local h = s.handle
	if h == nil then
		return
	end
	local lift = 0
	local squash = 1
	if s.kind == "chantier" then
		-- petit écrasement à chaque coup
		for _, at in TAPS do
			local u = (t - at) / 0.2
			if u >= 0 and u <= 1 then
				squash = 1 - 0.12 * math.sin(u * math.pi) * (if reducedMotion() then 0.5 else 1)
			end
		end
	else
		for _, at in GESTURE_HOPS do
			local u = (t - at) / HOP_TIME
			if u >= 0 and u <= 1 then
				lift = HOP_HEIGHT * 4 * u * (1 - u) * (if reducedMotion() then 0.5 else 1)
			end
		end
	end
	pcall(SquishyBuilder.setSquash, h, 1 / math.sqrt(squash), squash, 1 / math.sqrt(squash))
	local root = s.base * CFrame.new(0, lift, 0)
	local parts, cfs = SquishyBuilder.pose(h, root)
	for i = 1, #parts do
		table.insert(bulkParts, parts[i])
		table.insert(bulkCFrames, cfs[i])
	end
	local head = s.head
	if head then
		local at = SquishyBuilder.attachments(h).head
		table.insert(bulkParts, head)
		table.insert(bulkCFrames, root * at)
	end
	local mallet = s.mallet
	if mallet then
		-- levé, puis frappe vers l'avant à chaque coup
		local angle = math.rad(-60)
		for _, at in TAPS do
			local u = (t - (at - TAP_SWING)) / TAP_SWING
			if u >= 0 and u <= 1 then
				angle = math.rad(-60 + 140 * u)
			end
		end
		local d = Balance.SizeScale.BaseDiameter * SCALE
		local hand = root * CFrame.new(d * 0.55, d * 0.55, 0) * CFrame.Angles(angle, 0, 0)
		table.insert(bulkParts, mallet)
		table.insert(bulkCFrames, hand * CFrame.new(0, 0, -0.6))
	end
	for i, dot in s.dots do
		local on = t >= 0.4 * i
		dot.Transparency = if on then 0 else 1
		table.insert(bulkParts, dot)
		table.insert(bulkCFrames, s.base * CFrame.new(0, 1.2, -(1.6 + DOT_GAP * i)))
	end
end

local function stepShow(s: Show, now: number)
	local t = now - s.startedAt
	local life = if s.kind == "chantier" then CHANTIER_TIME else GESTURE_TIME
	if t >= life or t >= CHANTIER_CUT or t < 0 then
		finish(false)
		return
	end
	if bigShow() then
		finish(true)
		return
	end
	if s.kind == "chantier" then
		if Util.safe("RanchRenderer.detail", "reduced", RanchRenderer.detail, s.slot) ~= "full" then
			finish(true)
			return
		end
		while s.taps < #TAPS and t >= TAPS[s.taps + 1] do
			s.taps += 1
			counters.taps += 1
			if s.mine then
				playSound("ChantierTap", "Click")
				haptic("chantier")
			end
		end
	end
	local gui = s.label
	if gui and now >= s.labelUntil then
		s.label = nil
		pcall(WorldText.release, gui)
	end
	pose(s, t)
end

-- Condition de la carte Conseillé « Jelly Ascend » (lot B2, D29) ; lue 1 fois par seconde au plus
local function snapshotNow(): any
	local fn = sources.snapshot
	if fn then
		local ok, snap = pcall(fn)
		return if ok then snap else nil
	end
	local ok, mod = pcall(function(): any
		return require(Client.UI.UpgradeSnapshot) :: any
	end)
	if not ok or type(mod) ~= "table" or type(mod.current) ~= "function" then
		return nil
	end
	local okSnap, snap = pcall(mod.current)
	return if okSnap then snap else nil
end

local function anyPayable(snap: any): boolean
	local fn = sources.payable
	if fn then
		local ok, v = pcall(fn, snap)
		return ok and v == true
	end
	local ok, view = pcall(function(): any
		return require(Client.UI.Hud.UpgradeView) :: any
	end)
	if not ok or type(view) ~= "table" or type(view.anyPayable) ~= "function" then
		return true -- illisible : jamais de geste
	end
	local okP, v = pcall(view.anyPayable, snap)
	return not okP or v == true
end

local function myAttr(name: string): any
	local fn = sources.attr
	if fn then
		local ok, v = pcall(fn, name)
		return if ok then v else nil
	end
	local slot = mySlot()
	if slot <= 0 then
		return nil
	end
	local root = workspace:FindFirstChild("Wobbleton")
	local list = root and root:FindFirstChild("Ranches")
	local model = list and list:FindFirstChild(tostring(slot))
	if model == nil then
		return nil
	end
	local ok, v = pcall(function()
		return (model :: Instance):GetAttribute(name)
	end)
	return if ok then v else nil
end

local function startGesture(now: number)
	local root = Util.localRoot()
	if root == nil then
		return
	end
	local slot = mySlot()
	local here = root.Position
	local inside = WorldLayout.toLocal(slot, here)
	-- dans MON ranch seulement (enclos, dalles, maisonnette : le repère local du ranch)
	if math.abs(inside.X) > 40 or inside.Z < -2 or inside.Z > 130 then
		return
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local at = here + flat.Unit * GESTURE_AHEAD
	at = Vector3.new(at.X, WorldLayout.groundY(at.X, at.Z), at.Z)
	local obs = WorldLayout.observatory().Position
	local base = CFrame.lookAt(at, Vector3.new(obs.X, at.Y, obs.Z))
	local s: Show = {
		kind = "gesture",
		slot = slot,
		id = "",
		mine = true,
		startedAt = now,
		base = base,
		taps = 0,
		label = nil,
		labelUntil = 0,
		handle = nil,
		head = nil,
		mallet = nil,
		dots = {},
		taken = 0,
	}
	gestureDone = true -- une fois par séance, même si le budget refuse le dessin
	if not dress(s, false, true) then
		refreshLoop()
		return
	end
	show = s
	counters.gestures += 1
	refreshLoop()
end

local function poll(now: number)
	counters.polls += 1
	if gestureDone or show ~= nil or not Flags.on("JellyAscend") then
		return
	end
	local snap = snapshotNow()
	if type(snap) ~= "table" then
		return
	end
	firstSeenAt = firstSeenAt or now
	if anyPayable(snap) then
		lastPayableAt = now
		return
	end
	local since = lastPayableAt or firstSeenAt or now
	if now - since < Balance.Ascend.DeclineCardAfter then
		return
	end
	if myAttr("AscendReady") ~= true or bigShow() then
		return
	end
	startGesture(now)
end

function BigPlop._step(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	local now = Clock.now()
	table.clear(bulkParts)
	table.clear(bulkCFrames)
	local s = show
	if s then
		stepShow(s, now)
	end
	pollAcc += d
	if pollAcc >= POLL then
		pollAcc = 0
		poll(now)
	end
	if #bulkParts > 0 then
		-- appel direct (aucune fermeture créée par image, lot B5 étape 6)
		local ok, err = pcall(
			workspace.BulkMoveTo,
			workspace,
			bulkParts,
			bulkCFrames,
			Enum.BulkMoveMode.FireCFrameChanged
		)
		if not ok then
			Util.raise("BigPlop.bulk", tostring(err))
		end
	end
end

function refreshLoop()
	if not started then
		return
	end
	local need = needLoop()
	if need and stepConn == nil then
		stepConn = RunService.RenderStepped:Connect(function(dt: number)
			Util.guard("BigPlop.step", BigPlop._step, dt)
		end)
	elseif not need and stepConn ~= nil then
		local c = stepConn :: RBXScriptConnection
		stepConn = nil
		c:Disconnect()
	end
end

-- =============================================================================================
-- Chantier
-- =============================================================================================

local function onElement(slot: any, id: any)
	if type(slot) ~= "number" or type(id) ~= "string" or #id > 64 or NO_CHANTIER[id] then
		return
	end
	if show ~= nil or bigShow() or Util.safe("ShowsV2.busy", false, ShowsV2.busy, slot) then
		return
	end
	if Util.safe("RanchRenderer.detail", "reduced", RanchRenderer.detail, slot) ~= "full" then
		return
	end
	local frame = Util.safe("RanchRenderer.elementCFrame", nil, RanchRenderer.elementCFrame, slot, id)
	if typeof(frame) ~= "CFrame" then
		return
	end
	local el = (frame :: CFrame).Position
	local side = WorldLayout.toWorld(slot, Vector3.new(1, 0, 0)) - WorldLayout.toWorld(slot, Vector3.zero)
	local at = el + Vector3.new(side.X, 0, side.Z).Unit * SIDE
	at = Vector3.new(at.X, WorldLayout.groundY(at.X, at.Z), at.Z)
	local now = Clock.now()
	local mine = slot == mySlot()
	local s: Show = {
		kind = "chantier",
		slot = slot,
		id = id,
		mine = mine,
		startedAt = now,
		base = CFrame.lookAt(at, Vector3.new(el.X, at.Y, el.Z)),
		taps = 0,
		label = nil,
		labelUntil = 0,
		handle = nil,
		head = nil,
		mallet = nil,
		dots = {},
		taken = 0,
	}
	if not dress(s, true, false) then
		return
	end
	show = s
	counters.chantiers += 1
	local key = elementName(id)
	local h = s.handle
	if mine and key and h then
		local ok, gui = pcall(WorldText.create, h.body, {
			kind = "text",
			maxDistance = LABEL_DISTANCE,
			studsOffset = Vector3.new(0, Balance.SizeScale.BaseDiameter * SCALE + 1.5, 0),
			name = "ChantierLabel",
		})
		if ok and gui then
			pcall(WorldText.setText, gui, Util.t("card.unlockNew", { name = Util.t(key :: string) }))
			s.label = gui
			s.labelUntil = now + LABEL_TIME
			counters.labels += 1
		end
	end
	refreshLoop()
end

-- =============================================================================================
-- API
-- =============================================================================================

function BigPlop.start()
	if started then
		return
	end
	started = true
	table.insert(
		connections,
		RanchRenderer.ElementBuilt:Connect(function(slot: number, id: string)
			Util.guard("BigPlop.element", onElement, slot, id)
		end) :: any
	)
	table.insert(
		connections,
		Flags.Changed:Connect(function()
			if show and show.kind == "gesture" and not Flags.on("JellyAscend") then
				finish(true)
			end
			refreshLoop()
		end) :: any
	)
	refreshLoop()
end

function BigPlop.stop()
	finish(true)
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	local c = stepConn
	stepConn = nil
	if c then
		c:Disconnect()
	end
	started = false
end

function BigPlop.stats(): { [string]: number }
	return {
		chantiers = counters.chantiers,
		gestures = counters.gestures,
		taps = counters.taps,
		cut = counters.cut,
		labels = counters.labels,
		polls = counters.polls,
		refused = counters.refused,
		live = if show then 1 else 0,
		looping = if stepConn then 1 else 0,
		connections = #connections + (if stepConn then 1 else 0),
	}
end

function BigPlop._state(): { [string]: any }?
	local s = show
	if s == nil then
		return nil
	end
	return {
		kind = s.kind,
		slot = s.slot,
		id = s.id,
		mine = s.mine,
		taps = s.taps,
		base = s.base,
		model = if s.handle then s.handle.model else nil,
		head = s.head,
		mallet = s.mallet,
		dots = #s.dots,
		label = s.label,
		outfit = if s.handle then s.handle.spec.outfit else nil,
	}
end

function BigPlop._configure(options: any?)
	local o: any = if type(options) == "table" then options else {}
	sources.play = if type(o.play) == "function" then o.play else nil
	sources.haptic = if type(o.haptic) == "function" then o.haptic else nil
	sources.snapshot = if type(o.snapshot) == "function" then o.snapshot else nil
	sources.payable = if type(o.payable) == "function" then o.payable else nil
	sources.attr = if type(o.attr) == "function" then o.attr else nil
	sources.winter = if type(o.winter) == "function" then o.winter else nil
end

function BigPlop._reset()
	gestureDone = false
	firstSeenAt = nil
	lastPayableAt = nil
	pollAcc = 0
	refreshLoop()
end

return BigPlop
