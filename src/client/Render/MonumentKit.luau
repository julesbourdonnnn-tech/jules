--!strict
-- MonumentKit (lot B4, étape 4 ; GDD v2.0 §11.5 « Monuments », §4.29 ; décision D17 du plan B4).
-- Dessins PURS des 10 Monuments (noms : Strings monument.1 … monument.10) en lignes compactes de
-- Render/RanchKit, posés sur WorldLayout.monumentSlot(slot, n) (derrière le fond du ranch, face à la
-- place) ; 18 studs de haut au plus, emprise de rayon WorldLayout.Const.MonumentRadius (6) :
--   * « full » (ranch courant) : 20 pièces au plus ; « near » (ses 2 voisins) : 6 ; « reduced » (les
--     autres) : 1 silhouette ;
--   * 1 Moulin à Gelée, 2 Statue de Big Plop, 3 Grande Roue Guimauve, 4 Château de Pudding,
--     5 Bateau-Bonbon, 6 Fusée Sucette, 7 Jardin Suspendu, 8 Horloge Bonbon, 9 Pyramide de Dragées,
--     10 Cascade de Sirop.
-- Repère d'un dessin : origine au sol au centre de l'emplacement, Y vers le haut, −Z vers la place.
-- Rien n'est créé ici ; jamais d'erreur (numéro ou niveau inconnu : aucune pièce).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local WorldLayout = require(Shared.Logic.WorldLayout)

local RanchKit = require(script.Parent.RanchKit)

local MonumentKit = {}

type Row = RanchKit.Row
type Spec = RanchKit.Spec
type Design = { full: { Row }, near: { Row }, far: { Row } }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local P: { [string]: Color3 } = {
	stone = rgb(222, 206, 218),
	cream = rgb(255, 238, 214),
	white = rgb(255, 250, 245),
	pink = rgb(255, 160, 196),
	rose = rgb(255, 110, 155),
	blush = rgb(255, 205, 222),
	red = rgb(236, 78, 92),
	caramel = rgb(226, 152, 82),
	toffee = rgb(204, 124, 60),
	choco = rgb(124, 78, 56),
	wood = rgb(214, 160, 110),
	jelly = rgb(255, 120, 200),
	lemon = rgb(255, 228, 120),
	mint = rgb(150, 232, 200),
	sky = rgb(140, 205, 255),
	lilac = rgb(200, 168, 255),
	gold = rgb(255, 204, 84),
	grey = rgb(192, 192, 208),
	dark = rgb(70, 55, 75),
	green = rgb(122, 205, 122),
	leaf = rgb(92, 180, 104),
	sand = rgb(245, 225, 182),
	syrup = rgb(255, 170, 60),
	pancake = rgb(240, 200, 140),
	peach = rgb(255, 196, 160),
}
MonumentKit.PALETTE = P

MonumentKit.FULL_MAX = 20
MonumentKit.NEAR_MAX = 6
MonumentKit.FAR_MAX = 1

local seg = RanchKit.segment

-- Octogone (8 segments) de rayon r centré en (0, cy) dans le plan z
local function octagon(rows: { Row }, cy: number, r: number, z: number, t: number, colors: { string })
	for k = 0, 7 do
		local a1, a2 = math.rad(22.5 + 45 * k), math.rad(22.5 + 45 * (k + 1))
		table.insert(
			rows,
			seg(
				r * math.cos(a1),
				cy + r * math.sin(a1),
				r * math.cos(a2),
				cy + r * math.sin(a2),
				z,
				t,
				t,
				colors[k % #colors + 1],
				nil,
				t
			)
		)
	end
end

local DESIGNS: { Design } = {}

-- 1. Moulin à Gelée
do
	local full: { Row } = {
		{ "c", 0, 0.5, 0, 7, 1, 7, "stone" },
		{ "c", 0, 2.5, 0, 5.6, 3, 5.6, "cream" },
		{ "c", 0, 5.5, 0, 5, 3, 5, "pink" },
		{ "c", 0, 8.5, 0, 4.4, 3, 4.4, "cream" },
		{ "c", 0, 10.5, 0, 5, 1, 5, "caramel" },
		{ "c", 0, 11.5, 0, 3.8, 1, 3.8, "toffee" },
		{ "c", 0, 12.5, 0, 2.4, 1, 2.4, "caramel" },
		{ "s", 0, 9, -2.9, 1.2, 1.2, 1.2, "jelly", "n" },
	}
	for _, deg in { 45, 135, 225, 315 } do
		local a = math.rad(deg)
		table.insert(full, {
			"b",
			2.6 * math.cos(a),
			9 + 2.6 * math.sin(a),
			-3.1,
			0.9,
			4.6,
			0.15,
			"white",
			nil,
			0,
			0,
			deg - 90,
		})
	end
	for _, r in
		{
			{ "b", 0, 2.1, -2.85, 1.4, 2.2, 0.2, "choco" },
			{ "s", -1.15, 5.8, -2.35, 0.7, 0.7, 0.7, "lemon", "n" },
			{ "s", 1.15, 5.8, -2.35, 0.7, 0.7, 0.7, "lemon", "n" },
			{ "c", 3.7, 0.15, -2.6, 2.4, 0.3, 2.4, "jelly", "n" },
			{ "c", -3.6, 0.7, -2.6, 1.2, 1.4, 1.2, "wood" },
			{ "c", -4.3, 0.7, -1, 1.2, 1.4, 1.2, "wood" },
			{ "b", 0, 13.8, 0, 0.15, 1.6, 0.15, "white" },
			{ "b", 0.6, 14.2, 0, 1.2, 0.7, 0.08, "jelly" },
		} :: { Row }
	do
		table.insert(full, r)
	end
	DESIGNS[1] = {
		full = full,
		near = {
			{ "c", 0, 5.5, 0, 5.4, 11, 5.4, "cream" },
			{ "c", 0, 11.8, 0, 4, 1.6, 4, "caramel" },
			{ "s", 0, 9, -3, 1.2, 1.2, 1.2, "jelly", "n" },
			{ "b", 0, 9, -3.2, 0.9, 9.4, 0.15, "white", nil, 0, 0, 45 },
			{ "b", 0, 9, -3.2, 0.9, 9.4, 0.15, "white", nil, 0, 0, -45 },
			{ "b", 0, 2.1, -2.75, 1.4, 2.2, 0.2, "choco" },
		},
		far = { { "c", 0, 6, 0, 5, 12, 5, "cream" } },
	}
end

-- 2. Statue de Big Plop
DESIGNS[2] = {
	full = {
		{ "b", 0, 0.6, 0, 6, 1.2, 6, "white" },
		{ "b", 0, 1.7, 0, 5, 1, 5, "cream" },
		{ "b", 0, 1.7, -2.55, 2.4, 0.6, 0.1, "gold", "f" },
		{ "s", 0, 6.2, 0, 8, 8, 8, "pink" },
		{ "s", 0, 5.4, -1.8, 5, 5, 5, "blush" },
		{ "s", -1.3, 7.4, -3.5, 1.1, 1.1, 1.1, "dark" },
		{ "s", 1.3, 7.4, -3.5, 1.1, 1.1, 1.1, "dark" },
		{ "s", -1.15, 7.65, -3.95, 0.4, 0.4, 0.4, "white", "n" },
		{ "s", 1.15, 7.65, -3.95, 0.4, 0.4, 0.4, "white", "n" },
		{ "s", -2.3, 6.4, -3.1, 1, 1, 1, "rose" },
		{ "s", 2.3, 6.4, -3.1, 1, 1, 1, "rose" },
		{ "b", 0, 6.4, -3.9, 1, 0.25, 0.2, "dark" },
		{ "s", -2.4, 9.8, 0, 1.6, 1.6, 1.6, "pink" },
		{ "s", 2.4, 9.8, 0, 1.6, 1.6, 1.6, "pink" },
		{ "c", 0, 10.5, 0, 2.6, 0.8, 2.6, "gold", "f" },
		{ "b", 0, 11.3, -1.1, 0.4, 1, 0.4, "gold", "f" },
		{ "b", -0.95, 11.3, 0.55, 0.4, 1, 0.4, "gold", "f" },
		{ "b", 0.95, 11.3, 0.55, 0.4, 1, 0.4, "gold", "f" },
		{ "s", -1.8, 2.8, -1.5, 2, 2, 2, "pink" },
		{ "s", 1.8, 2.8, -1.5, 2, 2, 2, "pink" },
	},
	near = {
		{ "b", 0, 0.6, 0, 6, 1.2, 6, "white" },
		{ "s", 0, 6.2, 0, 8, 8, 8, "pink" },
		{ "s", 0, 5.4, -1.8, 5, 5, 5, "blush" },
		{ "s", -1.3, 7.4, -3.5, 1.1, 1.1, 1.1, "dark" },
		{ "s", 1.3, 7.4, -3.5, 1.1, 1.1, 1.1, "dark" },
		{ "c", 0, 10.5, 0, 2.6, 0.8, 2.6, "gold", "f" },
	},
	far = { { "s", 0, 5, 0, 8, 8, 8, "pink" } },
}

-- 3. Grande Roue Guimauve
do
	local full: { Row } = { { "b", 0, 0.3, 0, 9, 0.6, 4, "cream" } }
	for _, z in { -1.3, 1.3 } do
		table.insert(full, seg(-3, 0.6, 0, 9.6, z, 0.6, 0.6, "white"))
		table.insert(full, seg(3, 0.6, 0, 9.6, z, 0.6, 0.6, "white"))
	end
	table.insert(full, { "b", 0, 9.6, 0, 0.5, 0.5, 3.2, "white" })
	octagon(full, 9.6, 4.6, 0, 0.5, { "pink", "white" })
	table.insert(full, { "s", 0, 9.6, -0.4, 1.4, 1.4, 1.4, "jelly", "n" })
	local cabin = { "pink", "mint", "lemon", "sky" }
	for i, p in { { 4.25, 8.6 }, { 0, 12.95 }, { -4.25, 8.6 }, { 0, 4.45 } } do
		table.insert(full, { "b", p[1], p[2], 0, 1.2, 1.2, 1.2, cabin[i] })
	end
	table.insert(full, { "b", 0, 0.9, -2.6, 1.5, 1.8, 1.2, "mint" })
	local near: { Row } = {
		{ "b", 0, 0.3, 0, 9, 0.6, 4, "cream" },
		seg(-3, 0.6, 0, 9.6, -1.3, 0.6, 0.6, "white"),
		seg(3, 0.6, 0, 9.6, -1.3, 0.6, 0.6, "white"),
		{ "x", 0, 9.6, 0, 0.6, 9.2, 0, "pink", nil, 0, 90, 0 },
		{ "s", 0, 9.6, -0.6, 1.4, 1.4, 1.4, "jelly", "n" },
		{ "b", 0, 4.45, -0.6, 1.2, 1.2, 1.2, "mint" },
	}
	DESIGNS[3] =
		{ full = full, near = near, far = { { "x", 0, 9.6, 0, 0.6, 9.2, 0, "pink", nil, 0, 90, 0 } } }
end

-- 4. Château de Pudding
do
	local full: { Row } = {
		{ "b", 0, 3, 0, 6, 6, 6, "cream" },
		{ "b", 0, 6.4, 0, 6.4, 0.8, 6.4, "caramel" },
	}
	for _, p in { { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } } do
		table.insert(full, { "c", p[1], 4, p[2], 2.2, 8, 2.2, "peach" })
		table.insert(full, { "c", p[1], 8.5, p[2], 2.6, 1, 2.6, "caramel" })
		table.insert(full, { "s", p[1], 9.45, p[2], 0.9, 0.9, 0.9, "red" })
	end
	for _, r in
		{
			{ "b", 0, 1.5, -3.05, 2, 3, 0.2, "choco" },
			{ "c", 0, 8.8, 0, 3, 4, 3, "cream" },
			{ "c", 0, 11.3, 0, 3.4, 1, 3.4, "caramel" },
			{ "b", 0, 12.8, 0, 0.15, 2, 0.15, "white" },
			{ "b", 0.6, 13.3, 0, 1.2, 0.7, 0.08, "rose" },
			{ "s", 0, 9, -1.5, 0.8, 0.8, 0.8, "lemon", "n" },
		} :: { Row }
	do
		table.insert(full, r)
	end
	DESIGNS[4] = {
		full = full,
		near = {
			{ "b", 0, 3, 0, 6, 6, 6, "cream" },
			{ "b", 0, 6.4, 0, 6.4, 0.8, 6.4, "caramel" },
			{ "c", -3, 4, -3, 2.2, 8, 2.2, "peach" },
			{ "c", 3, 4, -3, 2.2, 8, 2.2, "peach" },
			{ "c", 0, 8.8, 0, 3, 4, 3, "cream" },
			{ "b", 0, 1.5, -3.05, 2, 3, 0.2, "choco" },
		},
		far = { { "b", 0, 4, 0, 6, 8, 6, "cream" } },
	}
end

-- 5. Bateau-Bonbon (de profil, proue vers +X)
DESIGNS[5] = {
	full = {
		{ "b", 0, 1.6, 0, 7, 1.6, 3, "rose" },
		{ "b", 3.5, 1.6, 0, 2.2, 1.6, 2.2, "rose", nil, 0, 45, 0 },
		{ "b", -3.8, 2, 0, 1, 2.4, 3, "rose" },
		{ "b", 0, 2.2, 0, 7.2, 0.4, 3.1, "white" },
		{ "b", 0, 2.5, 0, 7, 0.2, 2.6, "wood" },
		{ "b", 2.2, 0.4, 0, 0.6, 0.8, 3.2, "choco" },
		{ "b", -2.2, 0.4, 0, 0.6, 0.8, 3.2, "choco" },
		{ "c", 0, 7, 0, 0.4, 9, 0.4, "wood" },
		{ "b", -0.2, 7.2, 0.25, 4.4, 5, 0.1, "white" },
		{ "b", -0.1, 10.6, 0.25, 3, 1.6, 0.1, "pink" },
		{ "b", 0.6, 11.8, 0, 1.2, 0.6, 0.1, "jelly" },
		{ "s", -2, 1.5, -1.55, 0.6, 0.6, 0.6, "lemon", "n" },
		{ "s", 0, 1.5, -1.55, 0.6, 0.6, 0.6, "lemon", "n" },
		{ "s", 2, 1.5, -1.55, 0.6, 0.6, 0.6, "lemon", "n" },
		{ "s", 2.4, 3.1, 0.5, 1, 1, 1, "mint" },
		{ "s", 1.2, 3.1, -0.6, 1, 1, 1, "lemon" },
		{ "b", -2.6, 3.3, 0, 1.6, 1.4, 1.8, "cream" },
		{ "b", -2.6, 4.15, 0, 1.8, 0.3, 2, "rose" },
		{ "b", 5, 2.6, 0, 1.6, 0.25, 0.25, "wood" },
		{ "s", -3.8, 3.6, 0, 0.6, 0.6, 0.6, "lemon", "n" },
	},
	near = {
		{ "b", 0, 1.6, 0, 7, 1.6, 3, "rose" },
		{ "b", 3.5, 1.6, 0, 2.2, 1.6, 2.2, "rose", nil, 0, 45, 0 },
		{ "b", 0, 0.4, 0, 5, 0.8, 3.2, "choco" },
		{ "c", 0, 7, 0, 0.4, 9, 0.4, "wood" },
		{ "b", -0.2, 7.2, 0.25, 4.4, 5, 0.1, "white" },
		{ "b", 0.6, 11.8, 0, 1.2, 0.6, 0.1, "jelly" },
	},
	far = { { "b", 0, 1.6, 0, 8, 2.4, 3, "rose" } },
}

-- 6. Fusée Sucette
do
	local full: { Row } = {
		{ "c", 0, 0.3, 0, 6, 0.6, 6, "stone" },
		{ "c", 0, 0.9, 0, 2, 0.6, 2, "grey" },
		{ "c", 0, 2.7, 0, 3, 3, 3, "white" },
		{ "c", 0, 5.7, 0, 3, 3, 3, "pink" },
		{ "c", 0, 8.7, 0, 3, 3, 3, "white" },
		{ "c", 0, 11.45, 0, 0.4, 2.5, 0.4, "white" },
		{ "x", 0, 13.9, 0, 0.6, 3.6, 0, "rose", nil, 0, 90, 0 },
		{ "x", 0, 13.9, -0.35, 0.2, 2.4, 0, "white", nil, 0, 90, 0 },
		{ "x", 0, 13.9, -0.48, 0.1, 1.2, 0, "jelly", "n", 0, 90, 0 },
	}
	for k = 0, 2 do
		local a = math.rad(120 * k + 30)
		table.insert(
			full,
			{ "b", 2.2 * math.cos(a), 2.6, 2.2 * math.sin(a), 1.4, 2.4, 0.3, "rose", nil, 0, -math.deg(a), 0 }
		)
	end
	for _, r in
		{
			{ "s", 0, 7.5, -1.45, 1, 1, 1, "sky", "n" },
			{ "x", 0, 7.5, -1.42, 0.2, 1.4, 0, "gold", "f", 0, 90, 0 },
			{ "b", 3.4, 4.8, 0, 0.6, 9, 0.6, "grey" },
			{ "b", 2.5, 6, 0, 1.4, 0.3, 0.3, "grey" },
			{ "b", 2.5, 9, 0, 1.4, 0.3, 0.3, "grey" },
			{ "s", 0.9, 3, -1.25, 0.5, 0.5, 0.5, "lemon", "n" },
			{ "s", -0.9, 4.6, -1.25, 0.5, 0.5, 0.5, "lemon", "n" },
			{ "s", 0.9, 9.4, -1.25, 0.5, 0.5, 0.5, "lemon", "n" },
		} :: { Row }
	do
		table.insert(full, r)
	end
	DESIGNS[6] = {
		full = full,
		near = {
			{ "c", 0, 0.3, 0, 6, 0.6, 6, "stone" },
			{ "c", 0, 5.7, 0, 3, 9, 3, "white" },
			{ "c", 0, 11.45, 0, 0.4, 2.5, 0.4, "white" },
			{ "x", 0, 13.9, 0, 0.6, 3.6, 0, "rose", nil, 0, 90, 0 },
			{
				"b",
				2.2 * math.cos(math.rad(30)),
				2.6,
				2.2 * math.sin(math.rad(30)),
				1.4,
				2.4,
				0.3,
				"rose",
				nil,
				0,
				-30,
				0,
			},
			{
				"b",
				2.2 * math.cos(math.rad(150)),
				2.6,
				2.2 * math.sin(math.rad(150)),
				1.4,
				2.4,
				0.3,
				"rose",
				nil,
				0,
				-150,
				0,
			},
		},
		far = { { "c", 0, 6, 0, 3, 12, 3, "white" } },
	}
end

-- 7. Jardin Suspendu
do
	local full: { Row } = {
		{ "c", 0, 0.5, 0, 10, 1, 10, "stone" },
		{ "c", 0, 4.5, 0, 7, 1, 7, "stone" },
		{ "c", 0, 8.5, 0, 4, 1, 4, "stone" },
	}
	for _, deg in { 90, 210, 330 } do
		local a = math.rad(deg)
		table.insert(full, { "c", 3 * math.cos(a), 2.5, 3 * math.sin(a), 0.6, 3, 0.6, "white" })
	end
	for _, deg in { 30, 150, 270 } do
		local a = math.rad(deg)
		table.insert(full, { "c", 1.6 * math.cos(a), 6.5, 1.6 * math.sin(a), 0.5, 3, 0.5, "white" })
	end
	for _, deg in { 45, 135, 225, 315 } do
		local a = math.rad(deg)
		table.insert(full, { "b", 3.3 * math.cos(a), 2.75, 3.3 * math.sin(a), 0.3, 2.5, 0.3, "leaf" })
	end
	for _, deg in { 0, 120, 240 } do
		local a = math.rad(deg)
		table.insert(full, { "s", 4 * math.cos(a), 1.6, 4 * math.sin(a), 1.4, 1.4, 1.4, "green" })
	end
	table.insert(full, { "c", 0, 9.5, 0, 0.4, 1, 0.4, "wood" })
	table.insert(full, { "s", 0, 10.6, 0, 2.6, 2.6, 2.6, "leaf" })
	for i, deg in { 200, 340 } do
		local a = math.rad(deg)
		table.insert(full, {
			"s",
			2.8 * math.cos(a),
			5.25,
			2.8 * math.sin(a),
			0.5,
			0.5,
			0.5,
			if i == 1 then "jelly" else "lemon",
			"n",
		})
	end
	DESIGNS[7] = {
		full = full,
		near = {
			{ "c", 0, 0.5, 0, 10, 1, 10, "stone" },
			{ "c", 0, 4.5, 0, 7, 1, 7, "stone" },
			{ "c", 0, 8.5, 0, 4, 1, 4, "stone" },
			{ "c", 0, 4.5, 0, 1, 8, 1, "white" },
			{ "s", 0, 10.6, 0, 2.6, 2.6, 2.6, "leaf" },
			{ "s", 4, 1.6, 0, 1.4, 1.4, 1.4, "green" },
		},
		far = { { "c", 0, 4.5, 0, 8, 9, 8, "green" } },
	}
end

-- 8. Horloge Bonbon
DESIGNS[8] = {
	full = {
		{ "b", 0, 0.5, 0, 5, 1, 5, "choco" },
		{ "b", 0, 5.5, 0, 4, 9, 4, "pink" },
		{ "c", -2.05, 5.5, -2.05, 0.6, 9, 0.6, "white" },
		{ "c", 2.05, 5.5, -2.05, 0.6, 9, 0.6, "white" },
		{ "b", 0, 10.4, 0, 4.6, 0.8, 4.6, "caramel" },
		{ "b", 0, 11.2, 0, 3.4, 0.8, 3.4, "toffee" },
		{ "b", 0, 12, 0, 2.2, 0.8, 2.2, "caramel" },
		{ "s", 0, 12.9, 0, 1, 1, 1, "gold", "f" },
		{ "x", 0, 7.6, -2.1, 0.3, 3.2, 0, "white", nil, 0, 90, 0 },
		{ "x", 0, 7.6, -2.05, 0.2, 3.6, 0, "gold", "f", 0, 90, 0 },
		{ "b", 0, 7.95, -2.3, 0.25, 0.9, 0.1, "dark" },
		{ "b", 0.45, 7.85, -2.32, 0.2, 1.3, 0.1, "dark", nil, 0, 0, -60 },
		{ "s", 0, 8.9, -2.3, 0.3, 0.3, 0.3, "lemon", "n" },
		{ "s", 1.3, 7.6, -2.3, 0.3, 0.3, 0.3, "lemon", "n" },
		{ "s", 0, 6.3, -2.3, 0.3, 0.3, 0.3, "lemon", "n" },
		{ "s", -1.3, 7.6, -2.3, 0.3, 0.3, 0.3, "lemon", "n" },
		{ "b", 0, 2.1, -2.05, 1.4, 2.2, 0.1, "choco" },
		{ "b", 0, 4.6, -2.05, 1.6, 2.2, 0.1, "dark" },
		{ "s", 0, 4.1, -2.15, 0.6, 0.6, 0.6, "lemon", "n" },
		{ "s", 0, 9.75, -2.3, 0.5, 0.5, 0.5, "mint", "n" },
	},
	near = {
		{ "b", 0, 0.5, 0, 5, 1, 5, "choco" },
		{ "b", 0, 5.5, 0, 4, 9, 4, "pink" },
		{ "b", 0, 10.8, 0, 4.6, 1.6, 4.6, "caramel" },
		{ "x", 0, 7.6, -2.1, 0.3, 3.2, 0, "white", nil, 0, 90, 0 },
		{ "b", 0, 7.95, -2.3, 0.25, 0.9, 0.1, "dark" },
		{ "s", 0, 12.1, 0, 1, 1, 1, "gold", "f" },
	},
	far = { { "b", 0, 6, 0, 4, 12, 4, "pink" } },
}

-- 9. Pyramide de Dragées
do
	local beans = { "pink", "mint", "lemon", "sky", "lilac", "peach", "rose", "jelly", "green" }
	local full: { Row } = { { "b", 0, 0.25, 0, 8, 0.5, 8, "sand" } }
	local i = 0
	for _, x in { -2.6, 0, 2.6 } do
		for _, z in { -2.6, 0, 2.6 } do
			i += 1
			table.insert(full, { "s", x, 1.8, z, 2.6, 2.6, 2.6, beans[i] })
		end
	end
	for _, p in { { -1.3, -1.3 }, { 1.3, -1.3 }, { -1.3, 1.3 }, { 1.3, 1.3 } } do
		i += 1
		table.insert(full, { "s", p[1], 3.9, p[2], 2.6, 2.6, 2.6, beans[(i - 1) % #beans + 1] })
	end
	table.insert(full, { "s", 0, 6, 0, 2.6, 2.6, 2.6, "jelly" })
	table.insert(full, { "s", 0, 7.7, 0, 1.2, 1.2, 1.2, "gold", "n" })
	for _, p in { { 4.4, 0 }, { -4.4, 0 }, { 0, 4.4 }, { 0, -4.4 } } do
		table.insert(full, { "b", p[1], 1.75, p[2], 0.6, 2.5, 0.6, "white" })
	end
	DESIGNS[9] = {
		full = full,
		near = {
			{ "b", 0, 0.25, 0, 8, 0.5, 8, "sand" },
			{ "b", 0, 1.8, 0, 7.8, 2.6, 7.8, "pink" },
			{ "b", 0, 4.4, 0, 5.2, 2.6, 5.2, "mint" },
			{ "b", 0, 7, 0, 2.6, 2.6, 2.6, "lemon" },
			{ "s", 0, 8.9, 0, 1.2, 1.2, 1.2, "gold", "n" },
			{ "b", 0, 1.75, -4.4, 0.6, 2.5, 0.6, "white" },
		},
		far = { { "b", 0, 3, 0, 7, 6, 7, "pink" } },
	}
end

-- 10. Cascade de Sirop
DESIGNS[10] = {
	full = {
		{ "b", 0, 6, 2.5, 8, 12, 3, "caramel" },
		{ "b", -3, 3.5, 0.5, 2.5, 7, 3, "choco" },
		{ "b", 3, 3.5, 0.5, 2.5, 7, 3, "choco" },
		{ "b", 0, 12.4, 2, 7, 0.8, 4, "toffee" },
		{ "b", 0, 6.6, 0.8, 2.4, 10.4, 0.4, "syrup", "n" },
		{ "b", -1.8, 9, 0.85, 0.8, 6, 0.3, "syrup", "n" },
		{ "b", 1.8, 9, 0.85, 0.8, 6, 0.3, "syrup", "n" },
		{ "c", 0, 0.2, -2.2, 7, 0.4, 7, "syrup", "n" },
		{ "c", 0, 0.15, -2.2, 7.4, 0.3, 7.4, "choco" },
		{ "s", -0.8, 0.8, -0.6, 0.8, 0.8, 0.8, "syrup", "n" },
		{ "s", 0.8, 0.8, -0.6, 0.8, 0.8, 0.8, "syrup", "n" },
		{ "s", 0, 1, -1.2, 0.8, 0.8, 0.8, "syrup", "n" },
		{ "c", -4.5, 0.25, -2, 1.6, 0.5, 1.6, "pancake" },
		{ "c", -4.5, 0.75, -2, 1.6, 0.5, 1.6, "pancake" },
		{ "c", -4.5, 1.25, -2, 1.6, 0.5, 1.6, "pancake" },
		{ "b", -4.5, 1.7, -2, 0.7, 0.35, 0.7, "lemon" },
		{ "s", -2.5, 13.8, 2.5, 2, 2, 2, "leaf" },
		{ "s", 2.5, 13.8, 2.5, 2, 2, 2, "leaf" },
		{ "s", 3.4, 0.8, -1.4, 1.6, 1.6, 1.6, "caramel" },
		{ "s", -2.6, 0.8, -4.2, 1.6, 1.6, 1.6, "caramel" },
	},
	near = {
		{ "b", 0, 6, 2.5, 8, 12, 3, "caramel" },
		{ "b", 0, 12.4, 2, 7, 0.8, 4, "toffee" },
		{ "b", 0, 6.6, 0.8, 2.4, 10.4, 0.4, "syrup", "n" },
		{ "c", 0, 0.2, -2.2, 7, 0.4, 7, "syrup", "n" },
		{ "b", -3, 3.5, 0.5, 2.5, 7, 3, "choco" },
		{ "b", 3, 3.5, 0.5, 2.5, 7, 3, "choco" },
	},
	far = { { "b", 0, 6, 2.5, 8, 12, 3, "caramel" } },
}

MonumentKit.COUNT = #DESIGNS

local function rowsOf(n: number, level: string): { Row }?
	local d = DESIGNS[n]
	if d == nil then
		return nil
	end
	if level == "full" then
		return d.full
	elseif level == "near" then
		return d.near
	elseif level == "reduced" then
		return d.far
	end
	return nil
end

-- Pièces du Monument n (1 … 10) au niveau « full » | « near » | « reduced » sur le ranch `slot` ;
-- clés propres au niveau (un changement de niveau recrée les pièces, sans cascade)
function MonumentKit.specs(slot: number, n: number, level: string): { Spec }
	local rows = rowsOf(n, level)
	if rows == nil then
		return {}
	end
	local prefix = (if level == "full" then "mon" elseif level == "near" then "monN" else "monF") .. n .. "_"
	return RanchKit.rows({}, WorldLayout.monumentSlot(slot, n), prefix, rows, P)
end

-- Nombre de pièces du Monument n à ce niveau (0 : inconnu)
function MonumentKit.count(n: number, level: string): number
	local rows = rowsOf(n, level)
	return if rows then #rows else 0
end

-- Lignes d'un dessin (specs : emprise et hauteur)
function MonumentKit.rows(n: number, level: string): { Row }
	return rowsOf(n, level) or {}
end

return MonumentKit
