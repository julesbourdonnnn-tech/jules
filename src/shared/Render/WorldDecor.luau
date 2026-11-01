--!strict
-- WorldDecor (paquet world, module d'aide de Shared/Render). Plan pur du décor de Wobbleton qui
-- n'est PAS une règle du jeu (GDD §11.1, §11.3) : lampadaires (64, une lumière sur quatre),
-- collines et nuages, sucettes et buissons-guimauves des quartiers, fleurs de la Prairie, plaques de
-- sucre glace et guirlandes du costume d'hiver. Lu par WorldService (construction côté serveur) et
-- par LightingController (décor d'hiver côté client) : une seule source, aucune recherche dans le
-- workspace. Déterministe (mêmes positions à chaque serveur et chaque client). Les positions de jeu
-- restent dans Logic/WorldLayout ; les maisons viennent de ses boîtes solides.

local WorldLayout = require(script.Parent.Parent.Logic.WorldLayout)

local WorldDecor = {}

local CONST = WorldLayout.Const

export type Lamp = { position: Vector3, lit: boolean, color: number }
export type Hill = { position: Vector3, size: Vector3, color: number }
export type House = { cframe: CFrame, size: Vector3, inner: boolean }
export type Prop = { position: Vector3, color: number, size: number }

-- Dimensions purement graphiques (studs), nommées
WorldDecor.Lamp = table.freeze({
	poleHeight = 9,
	poleDiameter = 0.6,
	bulbDiameter = 1.6,
	garlandHeight = 6,
	garlandDiameter = 1.8,
	garlandThickness = 0.5,
	lightRange = 16,
	lightBrightness = 1.2,
	litEvery = 4, -- une lumière sur quatre (budget de la console la plus faible, GDD §12.9)
})

WorldDecor.Icing = table.freeze({
	margin = 3, -- la plaque déborde de la maison de 3 studs de chaque côté
	thickness = 0.2,
	top = 0.04, -- au-dessus du sol (-0,05) et des rues (0)
})

local function polar(r: number, deg: number, y: number?): Vector3
	local a = math.rad(deg)
	return Vector3.new(r * math.cos(a), y or 0, r * math.sin(a))
end

-- Lampadaires : boulevard (32, côté intérieur), anneau intérieur (16, côté extérieur), place (8),
-- rues radiales (8, sur le côté) ; jamais sur une rue, une maison ou un ranch
local LAMPS: { Lamp } = {}
do
	local positions: { Vector3 } = {}
	for k = 0, 31 do
		table.insert(positions, polar(CONST.Boulevard - 9, 5.625 + 11.25 * k))
	end
	for k = 0, 15 do
		table.insert(positions, polar(CONST.InnerRing + 9, 11.25 + 22.5 * k))
	end
	for k = 0, 7 do
		table.insert(positions, polar(CONST.PlazaRadius + 3, 22.5 + 45 * k))
	end
	for k = 0, 7 do
		table.insert(positions, polar(130, 45 * k + 4.4))
	end
	for i, position in positions do
		table.insert(LAMPS, {
			position = position,
			lit = (i - 1) % WorldDecor.Lamp.litEvery == 0,
			color = (i - 1) % 4 + 1,
		})
	end
end

-- Lampadaires (64), dans un ordre fixe
function WorldDecor.lamps(): { Lamp }
	local out = {}
	for i, lamp in LAMPS do
		out[i] = { position = lamp.position, lit = lamp.lit, color = lamp.color }
	end
	return out
end

-- Collines : 40 boules aplaties pastel au-delà du mur du bord (r 320-420, hauteur 10-40), jamais en
-- deçà de r = 324 (rien de visible ne déborde dans l'aire de jeu)
local HILLS: { Hill } = {}
do
	local rng = Random.new(5112026)
	for i = 1, 40 do
		local width = rng:NextNumber(34, 64)
		local depth = rng:NextNumber(30, 56)
		local height = rng:NextNumber(10, 40)
		local reach = math.max(width, depth) / 2
		local r = rng:NextNumber(CONST.WallRadius + 2 + reach, CONST.HillsRadius)
		local angle = (i - 1) * 9 + rng:NextNumber(-3, 3)
		table.insert(HILLS, {
			position = polar(r, angle),
			size = Vector3.new(width, height * 2, depth),
			color = (i - 1) % 3 + 1,
		})
	end
end

function WorldDecor.hills(): { Hill }
	return table.clone(HILLS)
end

-- Nuages (tag « Float » : le client peut les faire flotter lentement)
function WorldDecor.clouds(): { Hill }
	local out = {}
	local rng = Random.new(1212)
	for i = 1, 6 do
		table.insert(out, {
			position = polar(
				rng:NextNumber(220, 380),
				(i - 1) * 60 + rng:NextNumber(0, 30),
				rng:NextNumber(110, 150)
			),
			size = Vector3.new(rng:NextNumber(30, 50), rng:NextNumber(8, 12), rng:NextNumber(16, 26)),
			color = 1,
		})
	end
	return out
end

-- Maisons-bonbons : les boîtes solides de WorldLayout qui ne sont ni le plateau, ni un mur de
-- ranch, ni le mur du bord (même géométrie que les règles du serveur)
function WorldDecor.houses(): { House }
	local out: { House } = {}
	for i, box in WorldLayout.solids() do
		local p = box.cframe.Position
		local r = math.sqrt(p.X * p.X + p.Z * p.Z)
		local isPlate = i == 1 or box.size.Y < CONST.SolidMinHeight
		local isEdge = r > CONST.WallRadius - 2
		local isFence = WorldLayout.ranchNear(p, 1) ~= 0
		if not isPlate and not isEdge and not isFence then
			table.insert(out, { cframe = box.cframe, size = box.size, inner = r < CONST.InnerRing })
		end
	end
	return out
end

-- Sucettes (2 par maison intérieure, de part et d'autre) et buissons-guimauves (entre les maisons
-- extérieures et devant chaque paire), hors des rues
function WorldDecor.lollipops(): { Prop }
	local out: { Prop } = {}
	for i = 0, 7 do
		for j, side in { -13, 13 } do
			table.insert(out, {
				position = polar(72.5, 45 * i + 22.5 + side),
				color = (i * 2 + j - 1) % 3 + 1,
				size = 3,
			})
		end
	end
	return out
end

function WorldDecor.bushes(): { Prop }
	local out: { Prop } = {}
	for i = 0, 7 do
		table.insert(out, { position = polar(130, 45 * i + 22.5), color = 1, size = 4 })
		table.insert(out, { position = polar(115, 45 * i + 22.5), color = 1, size = 3 })
	end
	return out
end

-- Centre de la Prairie des copains (sol fleuri, panneau) : celui de WorldLayout.meadowPoint
function WorldDecor.meadowCenter(): Vector3
	local sum = Vector3.zero
	for i = 1, 12 do
		sum += WorldLayout.meadowPoint(i)
	end
	return Vector3.new(sum.X / 12, 0, sum.Z / 12)
end

-- Fleurs de la Prairie des copains (autour de son centre, au nord)
function WorldDecor.flowers(): { Prop }
	local base = WorldDecor.meadowCenter()
	local out: { Prop } = {}
	local rng = Random.new(280)
	for i = 1, 20 do
		local a = math.rad((i - 1) * 18 + rng:NextNumber(-6, 6))
		local r = rng:NextNumber(4, 16)
		table.insert(out, {
			position = base + Vector3.new(r * math.cos(a), 0, r * math.sin(a)),
			color = (i - 1) % 4 + 1,
			size = rng:NextNumber(0.8, 1.2),
		})
	end
	return out
end

-- Plaques de sucre glace du costume d'hiver : une sous chaque maison, débordant de Icing.margin
function WorldDecor.icing(): { House }
	local out: { House } = {}
	local m = WorldDecor.Icing.margin * 2
	for _, house in WorldDecor.houses() do
		local p = house.cframe.Position
		local rot = house.cframe - p
		local y = WorldDecor.Icing.top - WorldDecor.Icing.thickness / 2
		table.insert(out, {
			cframe = CFrame.new(p.X, y, p.Z) * rot,
			size = Vector3.new(house.size.X + m, WorldDecor.Icing.thickness, house.size.Z + m),
			inner = house.inner,
		})
	end
	return out
end

return WorldDecor
