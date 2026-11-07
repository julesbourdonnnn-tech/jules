--!strict
-- SkyKit (lot B4, étape 5 ; GDD v2.0 §4.27, §11.5 ; décisions D25, D26 du plan B4). Dessins du ciel des
-- Ascensions, en listes PURES de specs (Render/RanchKit) posées au-dessus de la clôture du fond
-- (WorldLayout.v2Anchor(slot, "sky") : local (0, 34, 84), disque de rayon 12, 14 studs de haut, hors de
-- la colonne de la silhouette et au-dessus des Monuments) :
--   * A1 Nuage-coussin, A2 Arc de gelée, A3 Aurore sucrée (3 rubans Neon courbes, aucune particule),
--     A4 Planète bonbon, A5 Anneau prismatique, A6 à A9 anneaux menthe, lilas, doré et arc-en-ciel,
--     A10 Constellation (10 étoiles), puis une étoile de plus par Ascension jusqu'à A20 ;
--   * trois niveaux (détail par ranch, D6) : « near » (ranch courant, ≤ 40 pièces), « mid » (ses 2
--     voisins, ≤ 10), « far » (les autres, 3 pièces : la silhouette du dessin) ;
--   * les clés des pièces portent le dessin (« sky3.r1 ») : un nouveau dessin remplace toutes les
--     pièces (cascade entière), une étoile de plus n'ajoute que sa pièce et son trait ;
--   * tout est immobile (aucune écriture par image) ; matériaux SmoothPlastic, Neon, Foil.
-- Jamais d'erreur : A est borné, un niveau inconnu compte comme « far ».

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Visuals = require(Shared.Config.Visuals)
local Balance = require(Shared.Config.Balance)
local RanchLook = require(Shared.Logic.RanchLook)
local WorldLayout = require(Shared.Logic.WorldLayout)

local RanchKit = require(script.Parent.RanchKit)

local SkyKit = {}

export type Level = "near" | "mid" | "far"

SkyKit.NEAR_MAX = 40 -- pièces au plus d'un ciel du ranch courant
SkyKit.MID_MAX = 10 -- d'un voisin
SkyKit.FAR = 3 -- des autres
SkyKit.RADIUS = 12 -- disque de l'emprise (WorldLayout : « sky »)
SkyKit.HEIGHT = 14

local NAMED = Visuals.SkyNamed
local MAX_STARS = Visuals.SkyMaxStars
local MAX_A = Balance.Prestige.MaxA

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTE: { [string]: Color3 } = {
	cloud = rgb(255, 252, 250),
	pink = rgb(255, 182, 214),
	jelly = rgb(255, 120, 180),
	mint = rgb(150, 240, 210),
	mintDeep = rgb(80, 210, 170),
	sky = rgb(140, 210, 255),
	lilac = rgb(200, 168, 255),
	lilacDeep = rgb(160, 120, 240),
	lemon = rgb(255, 236, 140),
	gold = rgb(255, 204, 84),
	goldDeep = rgb(240, 170, 40),
	peach = rgb(255, 200, 160),
	planet = rgb(230, 150, 220),
	star = rgb(255, 248, 200),
	line = rgb(170, 220, 255),
}
local RAINBOW = {
	rgb(255, 110, 120),
	rgb(255, 170, 90),
	rgb(255, 230, 110),
	rgb(140, 230, 140),
	rgb(120, 200, 255),
	rgb(150, 140, 255),
	rgb(210, 140, 255),
}
local PRISM = { rgb(255, 255, 255), rgb(255, 214, 236), rgb(214, 240, 255), rgb(236, 224, 255) }

-- Couleurs des 4 anneaux de couleur (A6 à A9) et de l'anneau prismatique (A5)
local RINGS: { [number]: { colors: { Color3 }, material: string } } = {
	[5] = { colors = PRISM, material = "n" },
	[6] = { colors = { PALETTE.mint, PALETTE.mintDeep }, material = "n" },
	[7] = { colors = { PALETTE.lilac, PALETTE.lilacDeep }, material = "n" },
	[8] = { colors = { PALETTE.gold, PALETTE.goldDeep }, material = "f" },
	[9] = { colors = RAINBOW, material = "n" },
}

-- 20 étoiles de la Constellation (x, y dans le plan du ciel, face à la place) : un chemin qui serpente
local STARS: { { number } } = {
	{ -8.5, 4.0 },
	{ -6.0, 6.5 },
	{ -7.5, 9.5 },
	{ -4.5, 11.5 },
	{ -1.5, 9.0 },
	{ 0.5, 12.0 },
	{ 3.0, 10.0 },
	{ 5.5, 12.0 },
	{ 8.0, 9.5 },
	{ 6.5, 6.5 },
	{ 9.0, 4.5 },
	{ 5.0, 3.5 },
	{ 2.5, 5.5 },
	{ -0.5, 4.0 },
	{ -3.0, 6.0 },
	{ -2.0, 2.0 },
	{ 1.5, 1.5 },
	{ 4.0, 1.0 },
	{ 7.0, 2.0 },
	{ 9.5, 7.5 },
}

local function clampA(A: any): number
	if type(A) ~= "number" or A ~= A or A == math.huge or A == -math.huge then
		return 0
	end
	return math.clamp(math.floor(A), 0, MAX_A)
end

local function levelOf(level: any): Level
	return if level == "near" or level == "mid" then level else "far"
end

-- Dessin montré pour A (1 … 10) et nombre d'étoiles de la Constellation (10 … 20) ; 0, 0 sans Ascension
function SkyKit.design(A: any): (number, number)
	local a = clampA(A)
	local key, extra = RanchLook.sky(a)
	if key == nil then
		return 0, 0
	end
	local n = math.min(a, NAMED)
	local stars = if n >= NAMED then math.clamp(math.max(NAMED, extra), NAMED, MAX_STARS) else 0
	return n, stars
end

-- =============================================================================================
-- Dessins (lignes compactes de RanchKit : { forme, x, y, z, sx, sy, sz, couleur, matériau, rx, ry, rz })
-- =============================================================================================

-- Segments d'un arc de cercle de rayon r autour de (cx, cy), de l'angle a0 à a1 (degrés), en n traits
local function arc(
	out: { RanchKit.Row },
	cx: number,
	cy: number,
	r: number,
	a0: number,
	a1: number,
	n: number,
	t: number,
	colors: { any },
	material: string?
)
	for i = 1, n do
		local u0 = math.rad(a0 + (a1 - a0) * (i - 1) / n)
		local u1 = math.rad(a0 + (a1 - a0) * i / n)
		local color = colors[(i - 1) % #colors + 1]
		table.insert(
			out,
			RanchKit.segment(
				cx + r * math.cos(u0),
				cy + r * math.sin(u0),
				cx + r * math.cos(u1),
				cy + r * math.sin(u1),
				0,
				t,
				t,
				color,
				material,
				t * 0.6
			)
		)
	end
end

local function cloudRows(level: Level): { RanchKit.Row }
	if level == "mid" then
		return {
			{ "s", 0, 6, 0, 6, 0, 0, "cloud" },
			{ "s", -3.6, 5.2, 0, 4.4, 0, 0, "cloud" },
			{ "s", 3.6, 5.2, 0, 4.4, 0, 0, "cloud" },
			{ "b", 0, 9.4, 0, 2.6, 0.8, 2.6, "pink" },
		}
	end
	return {
		{ "s", 0, 6, 0, 6, 0, 0, "cloud" },
		{ "s", -3.5, 5.2, 0, 4.6, 0, 0, "cloud" },
		{ "s", 3.5, 5.2, 0, 4.6, 0, 0, "cloud" },
		{ "s", -6.2, 4.6, 0, 3.2, 0, 0, "cloud" },
		{ "s", 6.2, 4.6, 0, 3.2, 0, 0, "cloud" },
		{ "s", -1.6, 8.0, 0, 4.0, 0, 0, "cloud" },
		{ "s", 1.8, 7.8, 0, 3.6, 0, 0, "cloud" },
		-- coussin rose posé sur le nuage, et ses 4 pompons
		{ "b", 0, 9.9, 0, 3.2, 0.9, 3.2, "pink" },
		{ "s", -1.6, 9.9, -1.6, 0.8, 0, 0, "jelly" },
		{ "s", 1.6, 9.9, -1.6, 0.8, 0, 0, "jelly" },
		{ "s", -1.6, 9.9, 1.6, 0.8, 0, 0, "jelly" },
		{ "s", 1.6, 9.9, 1.6, 0.8, 0, 0, "jelly" },
	}
end

local function arcRows(level: Level): { RanchKit.Row }
	local out: { RanchKit.Row } = {}
	local n = if level == "mid" then 6 else 12
	arc(out, 0, 3, 8, 180, 0, n, 1.3, { "jelly", "pink" }, nil)
	if level == "near" then
		table.insert(out, { "s", -8, 3, 0, 3, 0, 0, "cloud" })
		table.insert(out, { "s", 8, 3, 0, 3, 0, 0, "cloud" })
	end
	return out
end

local function auroraRows(level: Level): { RanchKit.Row }
	local out: { RanchKit.Row } = {}
	local colors = { "mint", "sky", "lilac" }
	local n = if level == "mid" then 3 else 6
	for k = 1, 3 do
		local base = 3 + 3.2 * (k - 1)
		local z = 0.6 * (k - 2)
		local phase = 0.8 * (k - 1)
		for i = 1, n do
			local x0 = -9 + 18 * (i - 1) / n
			local x1 = -9 + 18 * i / n
			local y0 = base + 1.3 * math.sin(x0 / 3 + phase)
			local y1 = base + 1.3 * math.sin(x1 / 3 + phase)
			table.insert(out, RanchKit.segment(x0, y0, x1, y1, z, 0.5, 0.3, colors[k], "n", 0.3))
		end
	end
	return out
end

local function planetRows(level: Level): { RanchKit.Row }
	local out: { RanchKit.Row } = {
		{ "s", 0, 7, 0, 7, 0, 0, "planet" },
	}
	-- anneau incliné : points du cercle de rayon 5,8 dans le plan horizontal, penché de 20° vers la place
	local n = if level == "mid" then 4 else 12
	local tilt = math.rad(20)
	local function point(u: number): (number, number, number)
		local x, z = 5.8 * math.cos(u), 5.8 * math.sin(u)
		return x, 7 + z * math.sin(tilt), z * math.cos(tilt)
	end
	for i = 1, n do
		local xa, ya, za = point(2 * math.pi * (i - 1) / n)
		local xb, yb, zb = point(2 * math.pi * i / n)
		local d = Vector3.new(xb - xa, yb - ya, zb - za)
		local mid = Vector3.new((xa + xb) / 2, (ya + yb) / 2, (za + zb) / 2)
		local yaw = math.deg(math.atan2(-d.Z, d.X))
		local pitch = math.deg(math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z)))
		table.insert(out, {
			"b",
			mid.X,
			mid.Y,
			mid.Z,
			d.Magnitude + 0.4,
			0.4,
			0.9,
			if i % 2 == 0 then "lemon" else "peach",
			nil,
			0,
			yaw,
			pitch,
		})
	end
	if level == "near" then
		table.insert(out, { "s", -2.2, 8.6, -2.6, 1.4, 0, 0, "jelly" })
		table.insert(out, { "s", 1.8, 5.4, -2.9, 1.1, 0, 0, "mint" })
	end
	return out
end

local function ringRows(a: number, level: Level): { RanchKit.Row }
	local def = RINGS[a] or RINGS[5]
	local out: { RanchKit.Row } = {}
	local n = if level == "mid" then 6 else 14
	arc(out, 0, 7, 6, 0, 360, n, 1.0, def.colors, def.material)
	if level == "near" then
		-- gemme au centre de l'anneau, et un second anneau intérieur pour l'arc-en-ciel (A9)
		table.insert(out, { "s", 0, 7, 0, 1.6, 0, 0, def.colors[1], def.material })
		if a == 9 then
			arc(out, 0, 7, 3.8, 0, 360, 10, 0.7, def.colors, def.material)
		end
	else
		table.insert(out, { "s", 0, 7, 0, 1.6, 0, 0, def.colors[1], def.material })
	end
	return out
end

local function constellationRows(stars: number, level: Level): { RanchKit.Row }
	local out: { RanchKit.Row } = {}
	local n = if level == "mid" then 5 else math.clamp(stars, NAMED, MAX_STARS)
	for i = 1, n do
		local p = STARS[i]
		table.insert(out, { "s", p[1], p[2], 0, if i % 3 == 0 then 1.4 else 1.0, 0, 0, "star", "n" })
	end
	for i = 2, n do
		local a, b = STARS[i - 1], STARS[i]
		table.insert(out, RanchKit.segment(a[1], a[2], b[1], b[2], 0.1, 0.18, 0.18, "line", "n", 0))
	end
	return out
end

-- Silhouette lointaine (3 pièces) : trois boules de la couleur principale du dessin
local FAR_COLOR: { [number]: string } =
	{ "cloud", "jelly", "mint", "planet", "cloud", "mint", "lilac", "gold", "jelly", "star" }

local function farRows(n: number): { RanchKit.Row }
	local c = FAR_COLOR[n] or "cloud"
	local m = if n == 10 or n == 3 or (n >= 5 and n ~= 8) then "n" else nil
	return {
		{ "s", -3, 6, 0, 3, 0, 0, c, m },
		{ "s", 3, 6, 0, 3, 0, 0, c, m },
		{ "s", 0, 9, 0, 3.4, 0, 0, c, m },
	}
end

-- Lignes du dessin de l'Ascension A au niveau `level`
local function rowsFor(A: number, level: Level): (number, { RanchKit.Row })
	local n, stars = SkyKit.design(A)
	if n == 0 then
		return 0, {}
	end
	if level == "far" then
		return n, farRows(n)
	elseif n == 1 then
		return n, cloudRows(level)
	elseif n == 2 then
		return n, arcRows(level)
	elseif n == 3 then
		return n, auroraRows(level)
	elseif n == 4 then
		return n, planetRows(level)
	elseif n <= 9 then
		return n, ringRows(n, level)
	end
	return n, constellationRows(stars, level)
end

-- Specs du ciel de l'Ascension A sur ce ranch, au niveau `level` (« near » | « mid » | « far ») ; vide
-- sans Ascension. Les étoiles de la Constellation gardent leur clé d'une Ascension à l'autre.
function SkyKit.specs(slot: number, A: any, level: any): { RanchKit.Spec }
	local lv = levelOf(level)
	local n, rows = rowsFor(clampA(A), lv)
	local out: { RanchKit.Spec } = {}
	if n == 0 then
		return out
	end
	local base = WorldLayout.v2Anchor(slot, "sky")
	local prefix = "sky" .. n .. lv .. "."
	if n >= NAMED and lv ~= "far" then
		-- Constellation : étoiles « s<i> » puis traits « l<i> » (une Ascension de plus = 2 pièces neuves)
		local count = 0
		for _, r in rows do
			if r[1] == "s" then
				count += 1
			end
		end
		for i, r in rows do
			local key = if i <= count then prefix .. "s" .. i else prefix .. "l" .. (i - count + 1)
			table.insert(out, RanchKit.row(base, key, r, PALETTE))
		end
		return out
	end
	return RanchKit.rows(out, base, prefix, rows, PALETTE)
end

-- Nombre de pièces du ciel de l'Ascension A au niveau `level` (budget visuel)
function SkyKit.count(A: any, level: any): number
	local _, rows = rowsFor(clampA(A), levelOf(level))
	return #rows
end

return SkyKit
