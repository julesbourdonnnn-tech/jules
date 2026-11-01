--!strict
-- Ranch (paquet world, aide de WorldService). Construit un ranch (GDD §11.2, docs/04 §3.1) dans son
-- repère local (WorldLayout.ranchCFrame : origine au portail, Z vers le fond) et garde les
-- références utiles (pièces à teinter, décorations, Tapis, Cuve, Bassin, dalles) pour que
-- setOwner / setBuild n'écrivent que ce qui change, sans jamais parcourir le modèle.
-- Positions : uniquement Logic/WorldLayout (anchor, padSocket, decorSlot) ; les murs solides sont
-- les boîtes de WorldLayout.solids() du ranch (passées par WorldService). Tout le reste est du décor
-- ancré et non solide ; la membrane du portail est non solide côté serveur (chaque client la rend
-- solide pour lui seul sur les ranchs des autres, RanchRenderer). Les 4 lumières du ranch sont
-- éteintes côté serveur (tag « RanchLight ») : seul le client du propriétaire allume les siennes
-- (budget de la console la plus faible, GDD §12.9).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Pads = require(Shared.Config.Pads)
local Balance = require(Shared.Config.Balance)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Palette = require(Shared.Render.Palette)

local World = ServerScriptService:WaitForChild("Server").World
local Parts = require(World.Parts)
local Decor = require(World.Decor)

local Ranch = {}

Ranch.LIGHT_TAG = "RanchLight"
Ranch.PAD_COUNT = #Pads.Order
Ranch.DECOR_COUNT = #Pads.Decor

local COLORS = Palette.World

-- Dimensions purement graphiques (studs), nommées
local DIM = table.freeze({
	postSpacing = 8, -- poteaux sucre d'orge tous les 8 studs (GDD §11.2)
	postSize = Vector3.new(0.8, 4.4, 0.8),
	railHeights = { 1.6, 3.2 },
	railThickness = 0.4,
	gatePostSize = Vector3.new(1, 10, 1),
	gateWidth = WorldLayout.Const.GateHalfWidth * 2,
	membraneHeight = 7,
	membraneThickness = 0.3,
	membraneTransparency = 0.45,
	archHeight = 10.5,
	lanternDiameter = 1.4,
	signSize = Vector3.new(1, 1, 1),
	penFloor = Vector3.new(58, 0.1, 36),
	penFloorTop = 0.03,
	snackMat = Vector3.new(54, 0.1, 32),
	snackMatTop = 0.07,
	dotDiameter = 3,
	dotThickness = 0.06,
	padDiameter = 4,
	padThickness = 0.3,
	lightRange = 14,
	lightBrightness = 1,
})

-- Vue d'un ranch construit (privée au paquet)
export type Handle = {
	slot: number,
	model: Model,
	tinted: { BasePart }, -- couleur du propriétaire (clôture, portail, lanternes)
	decor: { { BasePart } }, -- n° 1 … 18
	decorShown: number,
	mat: BasePart,
	dots: { BasePart },
	snackLevel: number,
	vat: { BasePart },
	vatShown: boolean,
	pool: { BasePart },
	poolShown: boolean,
	pads: { [string]: BasePart },
	padShown: { [string]: boolean },
	tiles: { [string]: any }, -- dernières dalles appliquées (dalles recalculées quand le propriétaire change)
	lights: { PointLight },
	owner: number,
}

local function localPos(slot: number, world: Vector3): Vector3
	return WorldLayout.toLocal(slot, world)
end

-- Bornes des dalles (niveau maximal : la dalle disparaît une fois tout acheté)
local function padMax(key: string): number?
	local tiles = (Balance :: any).Tiles
	local def = if type(tiles) == "table" then tiles[key] else nil
	if type(def) == "table" and type(def.Levels) == "number" then
		return def.Levels
	end
	if key == "decor" then
		return #Pads.Decor
	end
	return nil
end

-- Icône d'une dalle dessinée en Frames sur sa face du dessus (aucune image téléversée). Le disque est
-- un cylindre couché (axe X tourné vers le haut, Parts.UPRIGHT) : sa face ronde du dessus est la face
-- Right de la pièce ; la face Top est une tranche verticale de 0,3 stud (icône invisible)
local function padIcon(pad: BasePart, icon: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Icon"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = pad
	local function shape(name: string, size: UDim2, pos: UDim2, round: boolean, rotation: number?)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = COLORS.padIcon
		f.BorderSizePixel = 0
		f.Rotation = rotation or 0
		if round then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
		end
		f.Parent = gui
	end
	if icon == "mat" then -- tapis et 3 biscuits
		shape("Mat", UDim2.fromScale(0.6, 0.4), UDim2.fromScale(0.5, 0.5), false)
		for i, x in { 0.35, 0.5, 0.65 } do
			shape("Dot" .. i, UDim2.fromScale(0.1, 0.1), UDim2.fromScale(x, 0.5), true)
		end
	elseif icon == "decor" then -- fleur : cœur + 4 pétales
		shape("Heart", UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.5, 0.5), true)
		for i, p in { { 0.5, 0.3 }, { 0.7, 0.5 }, { 0.5, 0.7 }, { 0.3, 0.5 } } do
			shape("Petal" .. i, UDim2.fromScale(0.18, 0.18), UDim2.fromScale(p[1], p[2]), true)
		end
	elseif icon == "pen" then -- enclos : cadre et barreaux
		shape("Top", UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.5, 0.3), false)
		shape("Bottom", UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.5, 0.7), false)
		for i, x in { 0.25, 0.42, 0.58, 0.75 } do
			shape("Bar" .. i, UDim2.fromScale(0.07, 0.48), UDim2.fromScale(x, 0.5), false)
		end
	else -- lit : matelas + oreiller
		shape("Bed", UDim2.fromScale(0.64, 0.36), UDim2.fromScale(0.5, 0.56), false)
		shape("Pillow", UDim2.fromScale(0.22, 0.16), UDim2.fromScale(0.3, 0.32), true)
	end
end

-- Poteaux et lisses d'un côté de la clôture, de `a` à `b` (repère local, Y = 0)
local function fenceSide(
	folder: Instance,
	cf: CFrame,
	a: Vector3,
	b: Vector3,
	tinted: { BasePart },
	includeStart: boolean,
	includeEnd: boolean,
	name: string
)
	local delta = b - a
	local length = delta.Magnitude
	local intervals = math.max(1, math.ceil(length / DIM.postSpacing - 1e-6))
	local first = if includeStart then 0 else 1
	local last = if includeEnd then intervals else intervals - 1
	for i = first, last do
		local p = a + delta * (i / intervals)
		local post = Parts.block(
			folder,
			cf * CFrame.new(p.X, DIM.postSize.Y / 2, p.Z),
			DIM.postSize,
			{ name = name .. "Post" .. i, color = COLORS.freeRanch }
		)
		table.insert(tinted, post)
	end
	local mid = (a + b) / 2
	local axis = cf * CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(b.X, 0, b.Z))
	for j, h in DIM.railHeights do
		Parts.block(
			folder,
			axis + Vector3.new(0, h, 0),
			Vector3.new(DIM.railThickness, DIM.railThickness, length),
			{ name = name .. "Rail" .. j, color = COLORS.sign }
		)
	end
end

-- Construit le ranch n° slot sous `parent` ; `walls` = ses boîtes solides (WorldLayout.solids())
function Ranch.build(parent: Instance, slot: number, walls: { WorldLayout.Box }): Handle
	local cf = WorldLayout.ranchCFrame(slot)
	local model = Parts.model(parent, tostring(slot), cf)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("OwnerUserId", 0)
	local tinted: { BasePart } = {}
	local lights: { PointLight } = {}
	local function L(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function A(name: WorldLayout.Anchor): Vector3
		return localPos(slot, WorldLayout.anchor(slot, name))
	end

	-- Murs solides (boîtes exactes de WorldLayout) et clôture visible (non solide)
	local wallFolder = Parts.folder(model, "FenceWall")
	for i, box in walls do
		Parts.solid(wallFolder, "Wall" .. i, box.cframe, box.size)
	end
	local fence = Parts.folder(model, "Fence")
	local hw = WorldLayout.Const.RanchWidth / 2
	local depth = WorldLayout.Const.RanchDepth
	local t = WorldLayout.Const.FenceThickness / 2
	local gateX = WorldLayout.Const.GateHalfWidth + t
	local corners = {
		frontLeft = Vector3.new(-hw + t, 0, t),
		backLeft = Vector3.new(-hw + t, 0, depth - t),
		backRight = Vector3.new(hw - t, 0, depth - t),
		frontRight = Vector3.new(hw - t, 0, t),
	}
	fenceSide(fence, cf, corners.frontLeft, corners.backLeft, tinted, true, true, "Left")
	fenceSide(fence, cf, corners.backLeft, corners.backRight, tinted, false, false, "Back")
	fenceSide(fence, cf, corners.backRight, corners.frontRight, tinted, true, true, "Right")
	fenceSide(fence, cf, corners.frontLeft, Vector3.new(-gateX, 0, t), tinted, false, false, "FrontL")
	fenceSide(fence, cf, Vector3.new(gateX, 0, t), corners.frontRight, tinted, false, false, "FrontR")

	-- Portail : membrane de gelée non solide, poteaux, arche, lanternes (lumières éteintes)
	local gate = Parts.model(model, "Gate", L(0, 0, t))
	local membrane = Parts.block(
		gate,
		L(0, DIM.membraneHeight / 2, t),
		Vector3.new(DIM.gateWidth, DIM.membraneHeight, DIM.membraneThickness),
		{
			name = "Membrane",
			color = COLORS.fountainJelly,
			material = Enum.Material.Glass,
			transparency = DIM.membraneTransparency,
		}
	)
	membrane.CanCollide = false
	for _, side in { -1, 1 } do
		local x = side * gateX
		local label = if side < 0 then "L" else "R"
		local post = Parts.block(
			gate,
			L(x, DIM.gatePostSize.Y / 2, t),
			DIM.gatePostSize,
			{ name = "Post" .. label, color = COLORS.freeRanch }
		)
		table.insert(tinted, post)
		local lantern = Parts.ball(
			gate,
			L(x, DIM.gatePostSize.Y + DIM.lanternDiameter / 2, t).Position,
			DIM.lanternDiameter,
			{ name = "Lantern" .. label, color = COLORS.freeRanch, material = Enum.Material.Neon }
		)
		table.insert(tinted, lantern)
		table.insert(
			lights,
			Parts.light(
				lantern,
				COLORS.lampLight,
				DIM.lightRange,
				DIM.lightBrightness,
				false,
				Ranch.LIGHT_TAG
			)
		)
	end
	local arch = Parts.block(
		gate,
		L(0, DIM.archHeight, t),
		Vector3.new(gateX * 2 + 1, 1, 1),
		{ name = "Arch", color = COLORS.freeRanch }
	)
	table.insert(tinted, arch)

	-- Panneau : point d'attache invisible au-dessus du portail (BillboardGui dessiné par le client)
	local sign =
		Parts.block(model, CFrame.new(WorldLayout.anchor(slot, "sign")) * (cf - cf.Position), DIM.signSize, {
			name = "Sign",
			transparency = 1,
		})
	sign:SetAttribute(Parts.BASE_TRANSPARENCY, 1)

	-- Fontaine de Gelée (côté rue) : vasque, gelée, jet (lumière éteinte)
	local fountainPos = A("fountain")
	local fountain = Parts.model(model, "Fountain", L(fountainPos.X, 0, fountainPos.Z))
	local fBase = L(fountainPos.X, 0, fountainPos.Z)
	Parts.cylinder(fountain, fBase, 5, 1, { name = "Basin", color = COLORS.fountain })
	Parts.cylinder(fountain, fBase, 4, 1.05, { name = "Jelly", color = COLORS.fountainJelly })
	local jet = Parts.ellipsoid(
		fountain,
		fBase * CFrame.new(0, 2, 0),
		Vector3.new(1, 2.4, 1),
		{ name = "Jet", color = COLORS.fountainJelly, material = Enum.Material.Neon }
	)
	table.insert(
		lights,
		Parts.light(jet, COLORS.fountainJelly, DIM.lightRange, DIM.lightBrightness, false, Ranch.LIGHT_TAG)
	)

	-- Sol des enclos et Tapis à Goûter (13 aspects)
	Parts.block(
		model,
		L(0, DIM.penFloorTop - DIM.penFloor.Y / 2, 28),
		DIM.penFloor,
		{ name = "PenFloor", color = COLORS.penFloor }
	)
	local snack = Parts.model(model, "SnackMat", L(0, 0, 28))
	local look = Palette.snackLook(0)
	local mat = Parts.block(
		snack,
		L(0, DIM.snackMatTop - DIM.snackMat.Y / 2, 28),
		DIM.snackMat,
		{ name = "Mat", color = look.mat }
	)
	local dots: { BasePart } = {}
	for i = 1, Palette.SnackDots do
		local col = (i - 1) % 4
		local row = (i - 1) // 4
		local x = -18 + col * 12
		local z = 20 + row * 16
		local dot = Parts.cylinder(
			snack,
			L(x, DIM.snackMatTop, z),
			DIM.dotDiameter,
			DIM.dotThickness,
			{ name = "Dot" .. i, color = look.dots }
		)
		Parts.setVisible(dot, false)
		table.insert(dots, dot)
	end

	-- Pot à Pièces : marmite dorée (lumière éteinte dans le couvercle)
	local potPos = A("pot")
	local potBase = L(potPos.X, 0, potPos.Z)
	local pot = Parts.model(model, "Pot", potBase)
	Parts.cylinder(pot, potBase, 4, 3, { name = "Body", color = COLORS.pot, material = Enum.Material.Foil })
	Parts.cylinder(pot, potBase * CFrame.new(0, 3, 0), 4.6, 0.4, { name = "Rim", color = COLORS.pot })
	local lid = Parts.ellipsoid(
		pot,
		potBase * CFrame.new(0, 3.5, 0),
		Vector3.new(3.6, 1.4, 3.6),
		{ name = "Lid", color = COLORS.potLid }
	)
	table.insert(
		lights,
		Parts.light(lid, COLORS.gold, DIM.lightRange, DIM.lightBrightness, false, Ranch.LIGHT_TAG)
	)

	-- Cuve à Gelée (cachée jusqu'à sa construction gratuite de l'accueil)
	local vatPos = A("vat")
	local vatBase = L(vatPos.X, 0, vatPos.Z)
	local vatModel = Parts.model(model, "Vat", vatBase)
	Parts.cylinder(vatModel, vatBase, 7, 1, { name = "Base", color = COLORS.vatBase })
	Parts.cylinder(vatModel, vatBase * CFrame.new(0, 1, 0), 6, 9, {
		name = "Glass",
		color = COLORS.glass,
		material = Enum.Material.Glass,
		transparency = 0.5,
	})
	Parts.cylinder(
		vatModel,
		vatBase * CFrame.new(0, 1.1, 0),
		5.4,
		4.5,
		{ name = "Jelly", color = COLORS.vatJelly, material = Enum.Material.Neon }
	)
	Parts.cylinder(
		vatModel,
		vatBase * CFrame.new(0, 10, 0),
		6.4,
		0.6,
		{ name = "Lid", color = COLORS.vatBase }
	)
	Parts.block(
		vatModel,
		vatBase * CFrame.new(3.6, 2, 0),
		Vector3.new(2.4, 0.8, 0.8),
		{ name = "Pipe", color = COLORS.vatBase }
	)
	local vatParts = Parts.collect(vatModel)
	for _, p in vatParts do
		Parts.setVisible(p, false)
	end

	-- Bassin de Fusion (caché jusqu'à sa construction gratuite de l'accueil)
	local poolPos = A("pool")
	local poolBase = L(poolPos.X, 0, poolPos.Z)
	local poolModel = Parts.model(model, "Pool", poolBase)
	Parts.cylinder(poolModel, poolBase, 12, 0.8, { name = "Rim", color = COLORS.poolRim })
	Parts.cylinder(poolModel, poolBase, 11, 0.85, {
		name = "Water",
		color = COLORS.water,
		material = Enum.Material.Glass,
		transparency = 0.3,
	})
	local poolParts = Parts.collect(poolModel)
	for _, p in poolParts do
		Parts.setVisible(p, false)
	end

	-- Bol et coussin du Meilleur Ami, étagère à trophées
	local bowlPos = A("bowl")
	local bowlBase = L(bowlPos.X, 0, bowlPos.Z)
	local bowl = Parts.model(model, "Bowl", bowlBase)
	Parts.cylinder(bowl, bowlBase, 4, 1, { name = "Bowl", color = COLORS.bowl })
	Parts.cylinder(bowl, bowlBase, 3.2, 1.02, { name = "Inside", color = COLORS.bowlInside })
	local cushionPos = A("cushion")
	Parts.ellipsoid(
		model,
		L(cushionPos.X, 0.6, cushionPos.Z),
		Vector3.new(4, 1.2, 4),
		{ name = "Cushion", color = COLORS.cushion }
	)
	local shelfPos = A("shelf")
	local shelf = Parts.model(model, "Shelf", L(shelfPos.X, 0, shelfPos.Z))
	Parts.block(
		shelf,
		L(shelfPos.X, 3.5, shelfPos.Z + 0.45),
		Vector3.new(20, 7, 0.3),
		{ name = "Back", color = COLORS.shelf }
	)
	for i, y in { 1.5, 3.5, 5.5 } do
		Parts.block(
			shelf,
			L(shelfPos.X, y, shelfPos.Z),
			Vector3.new(20, 0.3, 1.2),
			{ name = "Plank" .. i, color = COLORS.shelf }
		)
	end
	for _, side in { -1, 1 } do
		Parts.block(
			shelf,
			L(shelfPos.X + side * 10, 3.5, shelfPos.Z),
			Vector3.new(0.3, 7, 1.2),
			{ name = if side < 0 then "SideL" else "SideR", color = COLORS.shelf }
		)
	end

	-- Prises de dalles (Config/Pads.Defs[].socket) : disques Neon avec leur icône, cachés tant qu'ils
	-- ne sont pas découverts
	local padsFolder = Parts.folder(model, "Pads")
	local pads: { [string]: BasePart } = {}
	local padShown: { [string]: boolean } = {}
	for _, key in Pads.Order do
		local def = Pads.Defs[key]
		local p = localPos(slot, WorldLayout.padSocket(slot, def.socket))
		local pad = Parts.cylinder(padsFolder, L(p.X, 0, p.Z), DIM.padDiameter, DIM.padThickness, {
			name = tostring(def.socket),
			color = Palette.ranchColor(slot, true),
			material = Enum.Material.Neon,
		})
		pad:SetAttribute("Tile", key)
		pad:SetAttribute("Icon", def.icon)
		padIcon(pad, def.icon)
		Parts.setVisible(pad, false)
		pads[key] = pad
		padShown[key] = false
	end

	-- 18 décorations, cachées tant qu'elles ne sont pas construites
	local decorFolder = Parts.folder(model, "Decor")
	local decor: { { BasePart } } = {}
	for i, key in Pads.Decor do
		local holder = Parts.model(decorFolder, tostring(i), WorldLayout.decorSlot(slot, i))
		holder:SetAttribute("Key", key)
		Decor.build(holder, key, WorldLayout.decorSlot(slot, i))
		local list = Parts.collect(holder)
		for _, part in list do
			Parts.setVisible(part, false)
		end
		decor[i] = list
	end

	return {
		slot = slot,
		model = model,
		tinted = tinted,
		decor = decor,
		decorShown = 0,
		mat = mat,
		dots = dots,
		snackLevel = 0,
		vat = vatParts,
		vatShown = false,
		pool = poolParts,
		poolShown = false,
		pads = pads,
		padShown = padShown,
		lights = lights,
		owner = 0,
		tiles = {},
	}
end

local refreshPads: (handle: Handle) -> ()

-- Couleur du propriétaire (clôture, portail, lanternes) ; gris et lumières éteintes s'il est libre
function Ranch.setOwner(handle: Handle, userId: number, color: Color3)
	local changed = handle.owner ~= userId
	handle.owner = userId
	if handle.model:GetAttribute("OwnerUserId") ~= userId then
		handle.model:SetAttribute("OwnerUserId", userId)
	end
	for _, part in handle.tinted do
		if part.Color ~= color then
			part.Color = color
		end
	end
	for key, pad in handle.pads do
		local _ = key
		if pad.Color ~= color then
			pad.Color = color
		end
	end
	-- côté serveur, les lumières restent éteintes (le client du propriétaire allume les siennes)
	for _, light in handle.lights do
		if light.Enabled then
			light.Enabled = false
		end
	end
	-- dalles découvertes : visibles seulement sur un ranch occupé (ordre des appels indifférent)
	if changed then
		refreshPads(handle)
	end
end

-- Nombre entier sûr dans [lo ; hi] (NaN, ±inf, type faux → lo)
local function int(x: any, lo: number, hi: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return lo
	end
	return math.clamp(math.floor(x), lo, hi)
end

-- Dalles : visibles une fois découvertes (bit de tiles.seen) sur un ranch occupé, cachées une fois
-- tout acheté (dernières dalles appliquées)
function refreshPads(handle: Handle)
	local t: any = handle.tiles
	local seen = int(t.seen, 0, 2 ^ 30)
	local owned = handle.owner ~= 0
	for key, pad in handle.pads do
		local def = Pads.Defs[key]
		local discovered = owned and bit32.btest(seen, def.seenBit)
		local maxed = false
		if key == "cozyBed" then
			maxed = t.cozyBed == true
		else
			local max = padMax(key)
			local level = int(t[key], 0, 1e6)
			maxed = max ~= nil and level >= max
		end
		local visible = discovered and not maxed
		if pad:GetAttribute("Maxed") ~= maxed then
			pad:SetAttribute("Maxed", maxed)
		end
		if visible ~= handle.padShown[key] then
			Parts.setVisible(pad, visible)
			handle.padShown[key] = visible
		end
	end
end

-- Montre les décorations construites, l'aspect du Tapis, la Cuve, le Bassin et les dalles découvertes
function Ranch.setBuild(handle: Handle, tiles: Types.Tiles, vat: boolean, pool: boolean)
	local t: any = if type(tiles) == "table" then tiles else {}
	local decorCount = int(t.decor, 0, #handle.decor)
	if decorCount ~= handle.decorShown then
		for i, list in handle.decor do
			local visible = i <= decorCount
			for _, part in list do
				Parts.setVisible(part, visible)
			end
		end
		handle.decorShown = decorCount
	end
	local snack = int(t.snack, 0, Palette.SnackLooks - 1)
	if snack ~= handle.snackLevel or handle.mat.Color ~= Palette.snackLook(snack).mat then
		local look = Palette.snackLook(snack)
		handle.mat.Color = look.mat
		for i, dot in handle.dots do
			if dot.Color ~= look.dots then
				dot.Color = look.dots
			end
			Parts.setVisible(dot, i <= look.count)
		end
		handle.snackLevel = snack
	end
	local showVat = vat == true
	if showVat ~= handle.vatShown then
		for _, part in handle.vat do
			Parts.setVisible(part, showVat)
		end
		handle.vatShown = showVat
	end
	local showPool = pool == true
	if showPool ~= handle.poolShown then
		for _, part in handle.pool do
			Parts.setVisible(part, showPool)
		end
		handle.poolShown = showPool
	end
	handle.tiles = table.clone(t)
	refreshPads(handle)
end

return Ranch
