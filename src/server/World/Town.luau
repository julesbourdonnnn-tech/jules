--!strict
-- Town (paquet world, aide de WorldService). Les blocs de Wobbleton hors ranchs (GDD §11.1) :
-- plateau, collines, murs du bord, place (MEGA pad, statue, boutique, Autel de la Lune, jarre de la
-- jauge, scène de Big Plop, fontaine dorée, 5 tableaux), rues, quartiers (maisons-bonbons, sucettes,
-- buissons-guimauves), lampadaires (une lumière sur quatre), Prairie des copains, point d'apparition
-- neutre. Chaque bloc est une fonction appelée sous pcall par WorldService (un bloc en panne est
-- compté, les autres se construisent). Positions de jeu : Logic/WorldLayout ; décor : Render/WorldDecor.
-- Seules les boîtes de WorldLayout.solids() collisionnent (pièces « Solid » invisibles) ; tout le
-- décor visible est ancré et non solide. Textes : aucun (attribut « LabelKey » = clé de
-- Localization/Strings, traduite et dessinée par le client).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.Logic.WorldLayout)
local Palette = require(Shared.Render.Palette)
local WorldDecor = require(Shared.Render.WorldDecor)

local Parts = require(ServerScriptService:WaitForChild("Server").World.Parts)

local Town = {}

local COLORS = Palette.World
local CONST = WorldLayout.Const

Town.LAMP_TAG = "LampLight"
Town.FLOAT_TAG = "Float"
Town.LABEL_KEY = "LabelKey"
Town.LABEL_HEIGHT = "LabelHeight"
Town.LABEL_TIMER = "LabelTimer" -- étiquette dont le texte est un compte à rebours calculé par le client
Town.JAR_MIN_JELLY = 0.05 -- hauteur de la gelée de la jarre à 0 % (jamais nulle)
Town.JAR_MAX_JELLY = 11.6 -- hauteur de la gelée de la jarre à 100 %
Town.JAR_JELLY_BOTTOM = 1.1 -- bas de la gelée au-dessus du dessus de la place

-- Hauteurs des dessus (studs) : jamais deux surfaces visibles au même niveau (aucun scintillement)
local TOPS = table.freeze({
	ground = -0.05,
	hillBase = -0.3,
	street = 0,
	plazaBorder = 0.02,
	sidewalk = 0.03,
	meadow = 0.03,
	plaza = 0.06,
})

local PLANTER_RADIUS = CONST.PlazaRadius - 3 -- jardinières (Ø 3) au bord de la place

local function polar(r: number, deg: number, y: number?): Vector3
	local a = math.rad(deg)
	return Vector3.new(r * math.cos(a), y or 0, r * math.sin(a))
end

-- Repère au sol, tourné pour que −Z (LookVector) regarde `target`
local function facing(position: Vector3, target: Vector3): CFrame
	local flat = Vector3.new(target.X, position.Y, target.Z)
	if (flat - position).Magnitude < 1e-3 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flat)
end

local function label(part: BasePart, key: string, height: number)
	part:SetAttribute(Town.LABEL_KEY, key)
	part:SetAttribute(Town.LABEL_HEIGHT, height)
end

-- Plateau : boîte solide de WorldLayout (invisible) + sol visible (cylindre menthe) + base des collines
function Town.plate(root: Instance, box: WorldLayout.Box)
	local folder = Parts.folder(root, "Plate")
	Parts.solid(folder, "Solid", box.cframe, box.size)
	Parts.cylinder(
		folder,
		CFrame.new(0, TOPS.ground - 1, 0),
		(CONST.WallRadius + 8) * 2,
		1,
		{ name = "Ground", color = COLORS.ground, material = Enum.Material.Grass }
	)
	Parts.cylinder(
		folder,
		CFrame.new(0, TOPS.hillBase - 1, 0),
		(CONST.HillsRadius + 20) * 2,
		1,
		{ name = "HillBase", color = COLORS.hillBase, material = Enum.Material.Grass }
	)
end

-- Collines de bonbons (au-delà du mur du bord) et quelques nuages (tag « Float »)
function Town.hills(root: Instance)
	local folder = Parts.folder(root, "Hills")
	for i, hill in WorldDecor.hills() do
		Parts.ellipsoid(
			folder,
			CFrame.new(hill.position),
			hill.size,
			{ name = "Hill" .. i, color = COLORS.hills[hill.color] or COLORS.hills[1] }
		)
	end
	for i, cloud in WorldDecor.clouds() do
		local part = Parts.ellipsoid(
			folder,
			CFrame.new(cloud.position),
			cloud.size,
			{ name = "Cloud" .. i, color = COLORS.cloud }
		)
		CollectionService:AddTag(part, Town.FLOAT_TAG)
	end
end

-- Murs invisibles du bord : exactement les boîtes de WorldLayout
function Town.walls(root: Instance, boxes: { WorldLayout.Box })
	local folder = Parts.folder(root, "Walls")
	for i, box in boxes do
		Parts.solid(folder, "Wall" .. i, box.cframe, box.size)
	end
end

-- Place (r < 50) et ses objets (positions : WorldLayout.plaza)
function Town.plaza(root: Instance)
	local plaza = Parts.folder(root, "Plaza")
	local center = WorldLayout.plaza("center")
	Parts.cylinder(
		plaza,
		CFrame.new(center.X, TOPS.plaza - 0.2, center.Z),
		CONST.PlazaRadius * 2,
		0.2,
		{ name = "Floor", color = COLORS.plaza }
	)
	Parts.cylinder(
		plaza,
		CFrame.new(center.X, TOPS.plazaBorder - 0.2, center.Z),
		(CONST.PlazaRadius + 2) * 2,
		0.2,
		{ name = "Border", color = COLORS.plazaBorder }
	)

	-- MEGA pad : disque rose clair Ø 30 + anneau Neon (allumé par le client à l'alerte)
	local mp = WorldLayout.plaza("megaPad")
	local mega = Parts.model(plaza, "MegaPad", CFrame.new(mp))
	Parts.cylinder(
		mega,
		CFrame.new(mp.X, TOPS.plaza, mp.Z),
		30,
		0.6,
		{ name = "Pad", color = COLORS.megaPad }
	)
	Parts.cylinder(
		mega,
		CFrame.new(mp.X, TOPS.plaza, mp.Z),
		31.5,
		0.5,
		{ name = "Ring", color = COLORS.megaRing, material = Enum.Material.Neon }
	)

	-- Statue : socle de marbre Ø 10 × 3 ; le squishy est dessiné par le client (attributs)
	local sp = WorldLayout.plaza("statue")
	local statue = Parts.model(plaza, "Statue", CFrame.new(sp))
	Parts.cylinder(
		statue,
		CFrame.new(sp.X, TOPS.plaza, sp.Z),
		10,
		3,
		{ name = "Socle", color = COLORS.marble, material = Enum.Material.Marble, shadow = true }
	)
	statue:SetAttribute("StatueSpecies", 0)
	statue:SetAttribute("StatueMutation", 0)
	statue:SetAttribute("StatueSize", 0)
	statue:SetAttribute("StatueName", "")

	-- Boutique : échoppe au toit rayé, tournée vers le centre
	local shp = WorldLayout.plaza("shop")
	local shopCf = facing(Vector3.new(shp.X, TOPS.plaza, shp.Z), center)
	local shop = Parts.model(plaza, "Shop", shopCf)
	Parts.block(
		shop,
		shopCf * CFrame.new(0, 1.5, 0),
		Vector3.new(8, 3, 2.4),
		{ name = "Counter", color = COLORS.shopCounter }
	)
	Parts.block(
		shop,
		shopCf * CFrame.new(0, 3, 2.6),
		Vector3.new(9, 6, 0.4),
		{ name = "Back", color = COLORS.sign }
	)
	for _, side in { -1, 1 } do
		Parts.block(
			shop,
			shopCf * CFrame.new(side * 4.2, 3.6, 2.2),
			Vector3.new(0.6, 7.2, 0.6),
			{ name = if side < 0 then "PostL" else "PostR", color = COLORS.sign }
		)
	end
	for i = 1, 4 do
		Parts.block(
			shop,
			shopCf * CFrame.new(-3.375 + (i - 1) * 2.25, 7.4, 0.6) * CFrame.Angles(math.rad(-12), 0, 0),
			Vector3.new(2.25, 0.4, 4.4),
			{ name = "Stripe" .. i, color = COLORS.shopStripes[(i - 1) % 2 + 1] }
		)
	end
	local shopSign = Parts.block(
		shop,
		shopCf * CFrame.new(0, 8.8, 2.4),
		Vector3.new(6, 1.6, 0.3),
		{ name = "Sign", color = COLORS.board }
	)
	label(shopSign, "world.shop", 2)

	-- Autel de la Lune : arche de marbre + croissant Neon (5 éclats en arc)
	local ap = WorldLayout.plaza("altar")
	local altarCf = facing(Vector3.new(ap.X, TOPS.plaza, ap.Z), center)
	local altar = Parts.model(plaza, "Altar", altarCf)
	Parts.block(
		altar,
		altarCf * CFrame.new(0, 0.3, 0),
		Vector3.new(12, 0.6, 5),
		{ name = "Step", color = COLORS.marble, material = Enum.Material.Marble }
	)
	for _, side in { -1, 1 } do
		Parts.block(altar, altarCf * CFrame.new(side * 4, 5.1, 0), Vector3.new(1.6, 9, 1.6), {
			name = if side < 0 then "PillarL" else "PillarR",
			color = COLORS.marble,
			material = Enum.Material.Marble,
			shadow = true,
		})
	end
	local beam = Parts.block(
		altar,
		altarCf * CFrame.new(0, 10.4, 0),
		Vector3.new(10, 1.6, 1.6),
		{ name = "Beam", color = COLORS.marble, material = Enum.Material.Marble }
	)
	-- compte à rebours du samedi (GDD §11.1) : étiquette du monde en px TV dessinée par le client
	-- (LightingController : EventClock.moon, interrupteur jellyMoon), jamais un texte posé ici
	label(beam, "event.altarCountdown", 5)
	beam:SetAttribute(Town.LABEL_TIMER, "moon")
	for i = 1, 5 do
		local a = math.rad(-60 + (i - 1) * 30)
		Parts.block(
			altar,
			altarCf
				* CFrame.new(2.2 * math.sin(a), 13.2 + 2.2 * math.cos(a) - 2.2, 0)
				* CFrame.Angles(0, 0, -a),
			Vector3.new(1.4, 0.7, 0.7),
			{ name = "Crescent" .. i, color = COLORS.altarCrescent, material = Enum.Material.Neon }
		)
	end

	-- Jarre de la jauge : verre Ø 8 × 12, gelée Neon dont la hauteur suit la jauge (setGauge)
	local gp = WorldLayout.plaza("gauge")
	local jarBase = CFrame.new(gp.X, TOPS.plaza, gp.Z)
	local jar = Parts.model(plaza, "GaugeJar", jarBase)
	Parts.cylinder(jar, jarBase, 9, 1, { name = "Base", color = COLORS.jarBase })
	Parts.cylinder(jar, jarBase * CFrame.new(0, 1, 0), 8, 12, {
		name = "Glass",
		color = COLORS.glass,
		material = Enum.Material.Glass,
		transparency = 0.55,
	})
	Parts.cylinder(
		jar,
		jarBase * CFrame.new(0, Town.JAR_JELLY_BOTTOM, 0),
		7.4,
		Town.JAR_MIN_JELLY,
		{ name = "Jelly", color = COLORS.jelly, material = Enum.Material.Neon }
	)
	local lid = Parts.cylinder(
		jar,
		jarBase * CFrame.new(0, 13, 0),
		8.6,
		0.8,
		{ name = "Lid", color = COLORS.jarBase }
	)
	label(lid, "world.gauge", 3)
	jar:SetAttribute("Fill", 0)

	-- Scène de Big Plop : disque surélevé Ø 10 (Big Plop est dessiné par le client)
	local stp = WorldLayout.plaza("stage")
	local stageBase = CFrame.new(stp.X, TOPS.plaza, stp.Z)
	local stage = Parts.model(plaza, "Stage", stageBase)
	Parts.cylinder(stage, stageBase, 11, 1.2, { name = "Rim", color = COLORS.sign })
	local disc = Parts.cylinder(stage, stageBase, 10, 1.5, { name = "Disc", color = COLORS.stage })
	label(disc, "world.bigPlop", 9)

	-- Fontaine dorée (départ du Golden Wobbler)
	local fp = WorldLayout.plaza("goldenFountain")
	local fBase = CFrame.new(fp.X, TOPS.plaza, fp.Z)
	local fountain = Parts.model(plaza, "GoldenFountain", fBase)
	Parts.cylinder(
		fountain,
		fBase,
		8,
		1.2,
		{ name = "Basin", color = COLORS.gold, material = Enum.Material.Foil }
	)
	Parts.cylinder(fountain, fBase, 7, 1.25, { name = "Water", color = COLORS.goldWater })
	Parts.cylinder(
		fountain,
		fBase,
		1,
		2.5,
		{ name = "Spout", color = COLORS.gold, material = Enum.Material.Neon }
	)

	-- 5 tableaux des classements en arc au nord (SurfaceGui « Board » rempli par le client)
	local boards = Parts.folder(plaza, "Boards")
	local bp = WorldLayout.plaza("boards")
	local radius = math.sqrt(bp.X * bp.X + bp.Z * bp.Z)
	local northDeg = math.deg(math.atan2(bp.Z, bp.X))
	for i = 1, 5 do
		local pos = polar(radius, northDeg + (i - 3) * 10, TOPS.plaza)
		local cf = facing(pos, center)
		local board = Parts.model(boards, tostring(i), cf)
		board:SetAttribute("Index", i)
		local panel = Parts.block(board, cf * CFrame.new(0, 4.4, 0), Vector3.new(7, 4.4, 0.4), {
			name = "Panel",
			color = COLORS.board,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Board"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0
		gui.Parent = panel
		for _, side in { -1, 1 } do
			Parts.block(
				board,
				cf * CFrame.new(side * 3, 1.1, 0),
				Vector3.new(0.4, 2.2, 0.4),
				{ name = if side < 0 then "PostL" else "PostR", color = COLORS.sign }
			)
		end
	end

	-- Jardinières aux quatre coins de la place, au bord (r = 47) : à r = 44, celle du sud-est
	-- empiétait sur la scène de Big Plop (27, 27) ; WorldBuild.spec vérifie qu'aucun objet de la place
	-- n'en chevauche un autre
	for i = 0, 3 do
		local pos = polar(PLANTER_RADIUS, 45 + 90 * i, TOPS.plaza)
		Parts.cylinder(plaza, CFrame.new(pos), 3, 1.4, { name = "Planter" .. (i + 1), color = COLORS.sign })
		Parts.ball(plaza, pos + Vector3.new(0, 2, 0), 2.4, {
			name = "Blossom" .. (i + 1),
			color = COLORS.flowers[i + 1] or COLORS.flowers[1],
		})
	end
	return plaza
end

-- Segments tangents d'un anneau (rayon du milieu r, largeur w, n segments)
local function ring(
	folder: Instance,
	name: string,
	r: number,
	w: number,
	n: number,
	top: number,
	color: Color3
)
	local outer = r + w / 2
	local length = 2 * outer * math.tan(math.pi / n) + 0.2
	for i = 0, n - 1 do
		local deg = 360 * i / n
		local pos = polar(r, deg, top - 0.1)
		local cf = CFrame.lookAt(pos, pos + polar(1, deg + 90))
		Parts.block(folder, cf, Vector3.new(w, 0.2, length), { name = name .. (i + 1), color = color })
	end
end

-- Rues : anneau intérieur (r = 95, 10 de large), grand boulevard (r = 166, 12 de large), trottoir
-- (jusqu'aux portails), 8 rues radiales de la place au boulevard
function Town.streets(root: Instance)
	local folder = Parts.folder(root, "Streets")
	ring(folder, "Ring", CONST.InnerRing, 10, 32, TOPS.street, COLORS.street)
	ring(folder, "Boulevard", CONST.Boulevard, 12, 48, TOPS.street, COLORS.street)
	local sidewalkInner = CONST.Boulevard + 6
	ring(
		folder,
		"Sidewalk",
		(sidewalkInner + CONST.GateRadius) / 2,
		CONST.GateRadius - sidewalkInner,
		48,
		TOPS.sidewalk,
		COLORS.sidewalk
	)
	local from, to = CONST.PlazaRadius, CONST.Boulevard - 6
	for i = 0, 7 do
		local deg = 45 * i
		local mid = polar((from + to) / 2, deg, TOPS.street - 0.1)
		local cf = CFrame.lookAt(mid, mid + polar(1, deg))
		Parts.block(
			folder,
			cf,
			Vector3.new(10, 0.2, to - from),
			{ name = "Radial" .. (i + 1), color = COLORS.street }
		)
	end
end

-- Quartiers : 24 maisons-bonbons (boîte solide invisible de 30 studs = boîte de WorldLayout ; corps,
-- toit à deux pans, 2 fenêtres Neon et une porte, non solides), sucettes, buissons-guimauves
function Town.houses(root: Instance, boxes: { WorldLayout.Box })
	local folder = Parts.folder(root, "Houses")
	for i, box in boxes do
		local house = Parts.model(folder, "House" .. i, box.cframe)
		Parts.solid(house, "Solid", box.cframe, box.size)
		local rot = box.cframe - box.cframe.Position
		local p = box.cframe.Position
		local w, d = box.size.X - 0.4, box.size.Z - 0.4
		local h = if box.size.X < 15 then 9 else 11
		local groundCf = CFrame.new(p.X, 0, p.Z) * rot
		local body = (i - 1) % #COLORS.houseBodies + 1
		local roof = (i - 1) % #COLORS.roofs + 1
		Parts.block(house, groundCf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), {
			name = "Body",
			color = COLORS.houseBodies[body],
			shadow = true,
		})
		local roofH = 5
		Parts.wedge(
			house,
			groundCf * CFrame.new(0, h + roofH / 2, -d / 4),
			Vector3.new(w + 1, roofH, d / 2 + 0.5),
			{
				name = "RoofFront",
				color = COLORS.roofs[roof],
				shadow = true,
			}
		)
		Parts.wedge(
			house,
			groundCf * CFrame.new(0, h + roofH / 2, d / 4) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(w + 1, roofH, d / 2 + 0.5),
			{ name = "RoofBack", color = COLORS.roofs[roof], shadow = true }
		)
		-- façade côté place (+Z de la boîte : vers le centre de la carte)
		for j, x in { -w / 4, w / 4 } do
			Parts.block(house, groundCf * CFrame.new(x, h * 0.62, d / 2 + 0.1), Vector3.new(2, 2, 0.2), {
				name = "Window" .. j,
				color = COLORS.window,
				material = Enum.Material.Neon,
			})
		end
		Parts.block(house, groundCf * CFrame.new(0, 2, d / 2 + 0.1), Vector3.new(2.4, 4, 0.2), {
			name = "Door",
			color = COLORS.door,
		})
	end
	local props = Parts.folder(folder, "Props")
	for i, lollipop in WorldDecor.lollipops() do
		local base = CFrame.new(lollipop.position)
		Parts.cylinder(props, base, 0.4, 3.6, { name = "Stick" .. i, color = COLORS.lollipopStick })
		Parts.ball(props, lollipop.position + Vector3.new(0, 4.6, 0), lollipop.size, {
			name = "Candy" .. i,
			color = COLORS.lollipops[lollipop.color] or COLORS.lollipops[1],
		})
	end
	for i, bush in WorldDecor.bushes() do
		Parts.ellipsoid(
			props,
			CFrame.new(bush.position + Vector3.new(0, bush.size * 0.35, 0)),
			Vector3.new(bush.size, bush.size * 0.8, bush.size),
			{ name = "Bush" .. i, color = COLORS.bush }
		)
	end
end

-- Lampadaires : poteau + boule Neon ; une PointLight sur quatre (tag « LampLight »), non solides
function Town.lamps(root: Instance)
	local folder = Parts.folder(root, "Lamps")
	local dim = WorldDecor.Lamp
	for i, lamp in WorldDecor.lamps() do
		local model = Parts.model(folder, "Lamp" .. i, CFrame.new(lamp.position))
		Parts.cylinder(model, CFrame.new(lamp.position), dim.poleDiameter, dim.poleHeight, {
			name = "Pole",
			color = COLORS.lampPole,
		})
		local bulb = Parts.ball(
			model,
			lamp.position + Vector3.new(0, dim.poleHeight + dim.bulbDiameter / 2, 0),
			dim.bulbDiameter,
			{
				name = "Bulb",
				color = COLORS.lampBulbs[lamp.color] or COLORS.lampBulbs[1],
				material = Enum.Material.Neon,
			}
		)
		if lamp.lit then
			Parts.light(bulb, COLORS.lampLight, dim.lightRange, dim.lightBrightness, true, Town.LAMP_TAG)
		end
	end
end

-- Prairie des copains : sol fleuri, fleurs, panneau « Coucou ! »
function Town.meadow(root: Instance)
	local folder = Parts.folder(root, "Meadow")
	local center = WorldDecor.meadowCenter()
	Parts.cylinder(folder, CFrame.new(center.X, TOPS.meadow - 0.2, center.Z), 36, 0.2, {
		name = "Field",
		color = COLORS.meadow,
		material = Enum.Material.Grass,
	})
	for i, flower in WorldDecor.flowers() do
		Parts.ball(folder, flower.position + Vector3.new(0, flower.size / 2, 0), flower.size, {
			name = "Flower" .. i,
			color = COLORS.flowers[flower.color] or COLORS.flowers[1],
		})
	end
	-- panneau tourné vers la place, au bord sud du champ
	local signPos = center + Vector3.new(0, 0, 14)
	local cf = facing(signPos, Vector3.zero)
	Parts.block(
		folder,
		cf * CFrame.new(0, 2, 0),
		Vector3.new(0.4, 4, 0.4),
		{ name = "SignPost", color = COLORS.wood }
	)
	local board = Parts.block(
		folder,
		cf * CFrame.new(0, 4, 0),
		Vector3.new(4, 2, 0.3),
		{ name = "Sign", color = COLORS.sign }
	)
	label(board, "world.meadow", 2)
end

-- Point d'apparition neutre sur la place (repli si le placement dans le ranch échoue), non solide
function Town.spawn(root: Instance): SpawnLocation
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "NeutralSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.CastShadow = false
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(-24, TOPS.plaza - 0.1, 24)
	spawn.Parent = root
	return spawn
end

return Town
