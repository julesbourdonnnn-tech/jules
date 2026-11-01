--!strict
-- Decor (paquet world, aide de WorldService). Les 18 décorations du ranch (Config/Pads.Decor, GDD
-- §4.6, §11.2), en formes simples : 2 à 4 pièces chacune, emprise ≤ 2,5 studs autour de leur
-- emplacement (WorldLayout.decorSlot, tourné vers le milieu des enclos), jamais solides. Construites
-- cachées (Transparency 1) : WorldService.setRanchBuild montre les `tiles.decor` premières, le
-- client joue l'apparition (rebond). Dimensions purement graphiques, nommées dans chaque recette.

local ServerScriptService = game:GetService("ServerScriptService")

local Parts = require(ServerScriptService:WaitForChild("Server").World.Parts)

local Decor = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PINK = rgb(255, 150, 190)
local WHITE = rgb(255, 255, 255)
local MINT = rgb(150, 235, 200)
local LEMON = rgb(255, 230, 120)
local SKY = rgb(150, 210, 255)
local LILAC = rgb(200, 170, 255)
local CARAMEL = rgb(220, 160, 100)
local CHOCO = rgb(150, 100, 80)

type Builder = (folder: Instance, cf: CFrame) -> ()

-- Raccourcis en repère de l'emplacement (X en travers, Y vers le haut, −Z vers les enclos)
local function at(cf: CFrame, x: number, y: number, z: number): CFrame
	return cf * CFrame.new(x, y, z)
end

local RECIPES: { [string]: Builder } = {
	-- barrière qui rebondit : 2 poteaux + lisse
	bouncy_fence = function(f, cf)
		Parts.block(f, at(cf, -2, 1, 0), Vector3.new(0.6, 2, 0.6), { name = "PostL", color = PINK })
		Parts.block(f, at(cf, 2, 1, 0), Vector3.new(0.6, 2, 0.6), { name = "PostR", color = PINK })
		Parts.block(f, at(cf, 0, 1.6, 0), Vector3.new(4.6, 0.5, 0.4), { name = "Rail", color = WHITE })
	end,
	-- lampe sucre d'orge : poteau + ampoule Neon
	candy_lamp = function(f, cf)
		Parts.cylinder(f, cf, 0.5, 5, { name = "Pole", color = WHITE })
		Parts.ball(
			f,
			at(cf, 0, 5.5, 0).Position,
			1.4,
			{ name = "Bulb", color = PINK, material = Enum.Material.Neon }
		)
	end,
	-- fleurs de gelée : 3 corolles
	jelly_flowers = function(f, cf)
		Parts.ball(f, at(cf, -1.2, 0.7, 0).Position, 1.1, { name = "Flower1", color = PINK })
		Parts.ball(f, at(cf, 0.2, 0.9, 0.6).Position, 1.2, { name = "Flower2", color = LEMON })
		Parts.ball(f, at(cf, 1.3, 0.7, -0.5).Position, 1.0, { name = "Flower3", color = LILAC })
	end,
	-- chemin de boules de gomme : 3 dômes
	gumdrop_path = function(f, cf)
		for i, x in { -1.8, 0, 1.8 } do
			local colors = { PINK, MINT, LEMON }
			Parts.ellipsoid(
				f,
				at(cf, x, 0.4, 0),
				Vector3.new(1.4, 0.8, 1.4),
				{ name = "Gumdrop" .. i, color = colors[i] }
			)
		end
	end,
	-- banc nuage : assise + 2 nuages
	cloud_bench = function(f, cf)
		Parts.block(f, at(cf, 0, 1.2, 0), Vector3.new(4, 0.5, 1.4), { name = "Seat", color = SKY })
		Parts.ellipsoid(
			f,
			at(cf, -1.5, 0.6, 0),
			Vector3.new(1.4, 1.2, 1.4),
			{ name = "PuffL", color = WHITE }
		)
		Parts.ellipsoid(f, at(cf, 1.5, 0.6, 0), Vector3.new(1.4, 1.2, 1.4), { name = "PuffR", color = WHITE })
	end,
	-- arbres-sucettes : bâton + disque
	lollipop_trees = function(f, cf)
		Parts.cylinder(f, cf, 0.4, 4, { name = "Stick", color = WHITE })
		Parts.disc(f, at(cf, 0, 4.8, 0), 2.6, 0.5, { name = "Candy", color = PINK })
	end,
	-- rochers-guimauves : 3 cylindres
	marshmallow_rocks = function(f, cf)
		Parts.cylinder(f, at(cf, -1.2, 0, 0), 1.6, 1.4, { name = "Rock1", color = WHITE })
		Parts.cylinder(f, at(cf, 0.6, 0, 0.6), 1.4, 1.0, { name = "Rock2", color = PINK })
		Parts.cylinder(f, at(cf, 1.0, 0, -0.9), 1.2, 1.6, { name = "Rock3", color = WHITE })
	end,
	-- mare à bulles : mare + 2 bulles
	bubble_pond = function(f, cf)
		Parts.cylinder(f, at(cf, 0, 0, 0), 4, 0.2, { name = "Pond", color = SKY })
		Parts.ball(f, at(cf, -0.6, 0.8, 0.2).Position, 0.8, { name = "Bubble1", color = WHITE })
		Parts.ball(f, at(cf, 0.7, 1.3, -0.3).Position, 0.6, { name = "Bubble2", color = PINK })
	end,
	-- arche à vermicelles : 2 piliers + linteau
	sprinkle_arch = function(f, cf)
		Parts.block(f, at(cf, -2, 2.5, 0), Vector3.new(0.8, 5, 0.8), { name = "PillarL", color = LILAC })
		Parts.block(f, at(cf, 2, 2.5, 0), Vector3.new(0.8, 5, 0.8), { name = "PillarR", color = MINT })
		Parts.block(f, at(cf, 0, 5.3, 0), Vector3.new(4.8, 0.8, 0.8), {
			name = "Top",
			color = PINK,
			material = Enum.Material.Neon,
		})
	end,
	-- hutte-pudding : base, dôme, porte
	pudding_hut = function(f, cf)
		Parts.cylinder(f, cf, 3.4, 2.4, { name = "Base", color = CARAMEL })
		Parts.ellipsoid(f, at(cf, 0, 2.6, 0), Vector3.new(3.6, 2, 3.6), { name = "Dome", color = LEMON })
		Parts.block(f, at(cf, 0, 0.8, -1.65), Vector3.new(1, 1.6, 0.2), { name = "Door", color = CHOCO })
	end,
	-- cerf-volant arc-en-ciel : mât, losange, queue
	rainbow_kite = function(f, cf)
		Parts.cylinder(f, cf, 0.2, 6, { name = "String", color = WHITE })
		Parts.block(f, at(cf, 0, 6.6, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(1.6, 1.6, 0.2), {
			name = "Kite",
			color = PINK,
		})
		Parts.block(f, at(cf, 0, 5.2, 0), Vector3.new(0.3, 1.4, 0.2), { name = "Tail", color = SKY })
	end,
	-- moulin étoilé : tour + 2 pales croisées
	star_windmill = function(f, cf)
		Parts.cylinder(f, cf, 1.2, 5, { name = "Tower", color = WHITE })
		Parts.block(f, at(cf, 0, 5, -0.7) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(4, 0.4, 0.2), {
			name = "BladeA",
			color = LEMON,
		})
		Parts.block(f, at(cf, 0, 5, -0.7) * CFrame.Angles(0, 0, math.rad(-45)), Vector3.new(4, 0.4, 0.2), {
			name = "BladeB",
			color = PINK,
		})
	end,
	-- balançoire à bonbons : 2 montants, barre, siège
	jellybean_swing = function(f, cf)
		Parts.block(f, at(cf, -2, 2, 0), Vector3.new(0.4, 4, 0.4), { name = "PostL", color = MINT })
		Parts.block(f, at(cf, 2, 2, 0), Vector3.new(0.4, 4, 0.4), { name = "PostR", color = MINT })
		Parts.block(f, at(cf, 0, 4.1, 0), Vector3.new(4.4, 0.4, 0.4), { name = "Bar", color = WHITE })
		Parts.ellipsoid(f, at(cf, 0, 1.4, 0), Vector3.new(1.6, 0.5, 0.9), { name = "Seat", color = PINK })
	end,
	-- fontaine-cupcake : base, crème, cerise
	cupcake_fountain = function(f, cf)
		Parts.cylinder(f, cf, 3, 1.6, { name = "Cup", color = CARAMEL })
		Parts.ellipsoid(f, at(cf, 0, 2, 0), Vector3.new(3.2, 1.6, 3.2), { name = "Frosting", color = PINK })
		Parts.ball(
			f,
			at(cf, 0, 3.1, 0).Position,
			0.8,
			{ name = "Cherry", color = rgb(240, 60, 90), material = Enum.Material.Neon }
		)
	end,
	-- pont en gomme : tablier + 2 garde-corps
	gummy_bridge = function(f, cf)
		Parts.block(f, at(cf, 0, 0.8, 0), Vector3.new(4.5, 0.5, 1.6), { name = "Deck", color = MINT })
		Parts.block(f, at(cf, 0, 1.6, 0.7), Vector3.new(4.5, 0.3, 0.2), { name = "RailA", color = PINK })
		Parts.block(f, at(cf, 0, 1.6, -0.7), Vector3.new(4.5, 0.3, 0.2), { name = "RailB", color = PINK })
	end,
	-- arbre à barbe à papa : tronc + nuage
	cotton_candy_tree = function(f, cf)
		Parts.cylinder(f, cf, 0.6, 3, { name = "Trunk", color = WHITE })
		Parts.ellipsoid(
			f,
			at(cf, 0, 4, 0),
			Vector3.new(3.4, 2.8, 3.4),
			{ name = "Puff", color = rgb(255, 190, 225) }
		)
	end,
	-- manège-donut : socle, mât, donut
	donut_carousel = function(f, cf)
		Parts.cylinder(f, cf, 3.6, 0.6, { name = "Base", color = SKY })
		Parts.cylinder(f, cf, 0.4, 3.5, { name = "Pole", color = WHITE })
		Parts.cylinder(f, at(cf, 0, 3.5, 0), 3.6, 0.8, { name = "Donut", color = PINK })
	end,
	-- télescope lunaire : trépied, tube, lentille
	moon_telescope = function(f, cf)
		Parts.cylinder(f, cf, 1.2, 2, { name = "Stand", color = LILAC })
		Parts.block(f, at(cf, 0, 2.6, 0) * CFrame.Angles(math.rad(35), 0, 0), Vector3.new(0.8, 0.8, 3), {
			name = "Tube",
			color = WHITE,
		})
		Parts.ball(
			f,
			at(cf, 0, 3.5, -1.2).Position,
			0.7,
			{ name = "Lens", color = LEMON, material = Enum.Material.Neon }
		)
	end,
}

-- Repli d'une clé inconnue (nouvelle décoration sans recette) : petit buisson rose
local function fallback(f: Instance, cf: CFrame)
	Parts.ellipsoid(f, at(cf, 0, 1, 0), Vector3.new(2, 2, 2), { name = "Bush", color = PINK })
end

-- Construit la décoration `key` dans `folder` à l'emplacement `cf` (repère tourné vers les enclos)
function Decor.build(folder: Instance, key: string, cf: CFrame)
	local recipe = RECIPES[key] or fallback
	recipe(folder, cf)
end

-- Recette connue (tests)
function Decor.has(key: string): boolean
	return RECIPES[key] ~= nil
end

return Decor
