--!strict
-- RanchTiers (lot B4, étape 4 ; GDD v2.0 §4.29, §11.2, §11.5 ; décisions D6, D8, D17, D18, D18b,
-- D23, D26 du plan B4). Dessins PURS (listes de specs de Render/RanchKit) des 6 paliers du ranch et
-- des éléments du Record R, posés depuis les points de WorldLayout (v2Anchor, anchor, helperHouse) :
--   * paliers (Visuals.RanchTiersAt) : Arche à pompons (12 pièces, plaque du chiffre romain),
--     Tour à bonbons (14, drapeau à la couleur du ranch), Balcon de gelée (18, lampions), Phare de
--     gelée (16, lanterne Neon qui tourne, rose quand le Grand Splorch est prêt), Dôme néon (14),
--     Couronne flottante (12, tourne ; 1 à 4 étoiles Neon aux Record R 25, 30, 35, 40 ; arc-en-ciel au
--     50) ; détail réduit (D6) : tour, phare et couronne en 3 pièces chacun (9 au plus) ;
--   * éléments du Record R : Cuve (anneaux 1 à 8, agitateur à 3 pales qui tourne, arc-en-ciel au R4,
--     buses 0 à 5, dorée au R7), Bassin-fontaine (3 jets Neon, R9), 8 lampions de la clôture (R12, Neon
--     pendant la Jelly Moon seulement), portail arc-en-ciel (R13, 7 segments fixes), geyser (R17),
--     maisonnette des Plopettes (R2, 6 pièces) ;
--   * accessoires de la silhouette du meilleur squishy (centre (0, 40, 36), rayon r) : cadre doré
--     (R18, octogone de 8 pièces), anneau rose du signal « prêt » (8 pièces, pulsation), anneau-soleil
--     de GiantTier ≥ 3 (disque + 8 rayons Neon, 9 pièces) ; seuls décors v2 permis dans la colonne du
--     centre au-dessus de Y = 21 (D8, D18b).
-- Règles des décors v2.0 : pièces ancrées, sans collision, ni requête, ni toucher, sans ombre,
-- opaques (RanchKit.create) ; aucune lumière (le phare de MON ranch emprunte une des 4 lumières du
-- ranch, LightingController, D23). Rien n'est créé ici ; jamais d'erreur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local WorldLayout = require(Shared.Logic.WorldLayout)

local RanchKit = require(script.Parent.RanchKit)

local RanchTiers = {}

type Spec = RanchKit.Spec
type Row = RanchKit.Row

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Palette des paliers et des éléments (couleurs de bonbon, Neon pour les accents)
local P: { [string]: Color3 } = {
	white = rgb(255, 250, 245),
	cream = rgb(255, 238, 214),
	pink = rgb(255, 160, 196),
	rose = rgb(255, 110, 155),
	red = rgb(242, 84, 98),
	lemon = rgb(255, 228, 120),
	mint = rgb(150, 232, 200),
	sky = rgb(140, 205, 255),
	lilac = rgb(200, 168, 255),
	gold = rgb(255, 204, 84),
	caramel = rgb(226, 152, 82),
	choco = rgb(124, 78, 56),
	wood = rgb(214, 160, 110),
	cyan = rgb(110, 230, 245),
	aqua = rgb(120, 220, 255),
	jelly = rgb(255, 120, 200),
	lamp = rgb(255, 224, 140),
	paper = rgb(255, 214, 200),
	orange = rgb(255, 168, 80),
	sun = rgb(255, 238, 170),
}
RanchTiers.PALETTE = P

-- Couleurs publiques (specs, LightingController)
RanchTiers.LANTERN = P.lamp -- lanterne du phare, Grand Splorch pas prêt
RanchTiers.READY = rgb(255, 92, 170) -- rose du signal « prêt » (phare, anneau)
RanchTiers.READY_ALT = rgb(255, 170, 214) -- seconde couleur de la pulsation de l'anneau
RanchTiers.LIT = rgb(255, 200, 120) -- lampions allumés pendant la Jelly Moon
RanchTiers.UNLIT = P.paper -- lampions éteints (papier pastel)
local RAINBOW: { Color3 } = {
	rgb(255, 120, 130),
	rgb(255, 180, 110),
	rgb(255, 232, 120),
	rgb(150, 230, 150),
	rgb(130, 190, 255),
	rgb(160, 140, 255),
	rgb(220, 150, 255),
}
RanchTiers.RAINBOW = RAINBOW

-- Pièces de chaque palier en détail complet (GDD §11.5 : 12, 14, 18, 16, 14, 12) et réduit (D6)
RanchTiers.TIER_PARTS = table.freeze({ 12, 14, 18, 16, 14, 12 }) :: { number }
RanchTiers.REDUCED_PARTS = table.freeze({ 0, 3, 0, 3, 0, 3 }) :: { number }
RanchTiers.STAR_PARTS = 1 -- une pièce par étoile de couronne
RanchTiers.CROWN_PERIOD = 20 -- s par tour de la couronne (« tourne lentement »)
RanchTiers.LANTERN_PERIOD = 8 -- s par tour de la lanterne du phare
RanchTiers.PLATE_KEY = "archPlate" -- plaque du chiffre romain (SurfaceGui posé par Render/RanchV2)
RanchTiers.LANTERN_KEY = "lhLantern" -- lanterne du phare (lumière empruntée, D23)
RanchTiers.PLATE_SIZE = Vector3.new(3.2, 1.2, 0.3)

local segment = RanchKit.segment

local function anchorCF(slot: number, name: WorldLayout.V2Anchor): CFrame
	return WorldLayout.v2Anchor(slot, name)
end

-- Repère d'un point local du ranch (tourné comme le ranch)
local function localCF(slot: number, p: Vector3): CFrame
	return WorldLayout.ranchCFrame(slot) * CFrame.new(p.X, p.Y, p.Z)
end

-- =============================================================================================
-- Les 6 paliers
-- =============================================================================================

-- Arche à pompons (Z = 0, Y 9 à 13) : arche de guimauve en 5 segments, plaque du chiffre romain et
-- son cadre doré, 2 pompons, 2 bonbons Neon ; 12 pièces
local function arch(slot: number): { Spec }
	local rows: { Row } = {}
	local pts: { { number } } = {}
	for i = 0, 5 do
		local t = math.pi * i / 5
		table.insert(pts, { 5 * math.cos(t), 2.3 + 1.4 * math.sin(t) })
	end
	for i = 1, 5 do
		local a, b = pts[i], pts[i + 1]
		table.insert(
			rows,
			segment(a[1], a[2], b[1], b[2], 0, 0.6, 1, if i % 2 == 1 then "white" else "pink", nil, 0.3)
		)
	end
	local out: { Spec } = {}
	local base = anchorCF(slot, "arch")
	RanchKit.rows(out, base, "archSeg", rows, P)
	table.insert(
		out,
		RanchKit.row(base, RanchTiers.PLATE_KEY, { "b", 0, 2.85, -0.65, 3.2, 1.2, 0.3, "cream" }, P)
	)
	RanchKit.rows(out, base, "archTrim", {
		{ "b", 0, 3.53, -0.66, 3.4, 0.15, 0.32, "gold", "f" },
		{ "b", 0, 2.17, -0.66, 3.4, 0.15, 0.32, "gold", "f" },
	}, P)
	RanchKit.rows(out, base, "archPompom", {
		{ "s", -4.85, 3.2, 0, 1.3, 1.3, 1.3, "rose" },
		{ "s", 4.85, 3.2, 0, 1.3, 1.3, 1.3, "rose" },
	}, P)
	RanchKit.rows(out, base, "archCandy", {
		{ "s", -3.2, 3.45, -0.55, 0.6, 0.6, 0.6, "mint", "n" },
		{ "s", 3.2, 3.45, -0.55, 0.6, 0.6, 0.6, "lemon", "n" },
	}, P)
	return out
end

-- Tour à bonbons (X −30, Z 76, Ø 4, hauteur 16) : socle, 6 rayures sucre d'orge, toit en 3 étages,
-- mât et drapeau à la couleur du ranch, 2 fenêtres Neon ; 14 pièces
local function tower(slot: number, color: Color3): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "tower")
	local rows: { Row } = { { "c", 0, 0.3, 0, 4.8, 0.6, 4.8, "white" } }
	for i = 1, 6 do
		table.insert(
			rows,
			{ "c", 0, 0.6 + 2.5 * (i - 0.5), 0, 4, 2.5, 4, if i % 2 == 1 then "red" else "white" }
		)
	end
	table.insert(rows, { "c", 0, 16.0, 0, 4.6, 0.8, 4.6, "pink" })
	table.insert(rows, { "c", 0, 16.8, 0, 3.4, 0.8, 3.4, "rose" })
	table.insert(rows, { "c", 0, 17.6, 0, 2.2, 0.8, 2.2, "pink" })
	table.insert(rows, { "b", 0, 18.5, 0, 0.15, 1, 0.15, "white" })
	RanchKit.rows(out, base, "tower", rows, P)
	table.insert(out, RanchKit.row(base, "towerFlag", { "b", 0.5, 18.65, 0, 0.9, 0.55, 0.08, color }, P))
	RanchKit.rows(out, base, "towerWindow", {
		{ "b", 0, 9.5, -2.02, 0.8, 1, 0.1, "lemon", "n" },
		{ "b", 0, 4.5, -2.02, 0.8, 1, 0.1, "lemon", "n" },
	}, P)
	return out
end

local function towerReduced(slot: number, color: Color3): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "tower")
	RanchKit.rows(out, base, "farTower", {
		{ "c", 0, 7.8, 0, 4, 15.6, 4, "red" },
		{ "c", 0, 16.8, 0, 3.6, 2.4, 3.6, "pink" },
		{ "b", 0.5, 18.65, 0, 0.9, 0.55, 0.08, color },
	}, P)
	return out
end

-- Balcon de gelée (Z 76, Y 10 à 14, jamais accessible) : plancher, 4 poteaux (les 2 du bout portent
-- la guirlande), liseré Neon, main courante, 5 balustres, guirlande et 5 lampions Neon ; 18 pièces
local function balcony(slot: number): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "balcony")
	local rows: { Row } = {
		{ "b", 0, 10.3, 0, 20, 0.6, 2, "pink" },
		{ "b", -9.2, 7, 0, 0.6, 14, 0.6, "white" },
		{ "b", 9.2, 7, 0, 0.6, 14, 0.6, "white" },
		{ "b", -3.2, 5, 0, 0.6, 10, 0.6, "white" },
		{ "b", 3.2, 5, 0, 0.6, 10, 0.6, "white" },
		{ "b", 0, 10.2, -0.9, 20, 0.25, 0.2, "jelly", "n" },
		{ "b", 0, 12.1, -0.8, 19.6, 0.3, 0.3, "cream" },
	}
	for _, x in { -8, -4, 0, 4, 8 } do
		table.insert(rows, { "b", x, 11.3, -0.8, 0.25, 1.4, 0.25, "cream" })
	end
	table.insert(rows, { "b", 0, 13.75, -0.6, 19.2, 0.08, 0.08, "white" })
	local lampions = { "pink", "lemon", "mint", "sky", "lilac" }
	for i, x in { -7.2, -3.6, 0, 3.6, 7.2 } do
		table.insert(rows, { "s", x, 13.3, -0.6, 0.7, 0.7, 0.7, lampions[i], "n" })
	end
	return RanchKit.rows(out, base, "balcony", rows, P)
end

-- Phare de gelée (X +30, Z 76, hauteur 22) : 4 étages rayés, galerie, 4 montants, lanterne Neon qui
-- tourne (rose quand le Grand Splorch est prêt), toit en 3 étages, épi Neon, porte, fenêtre ; 16 pièces
local function lighthouse(slot: number, ready: boolean): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "lighthouse")
	local rows: { Row } = {
		{ "c", 0, 2, 0, 4, 4, 4, "white" },
		{ "c", 0, 6, 0, 3.7, 4, 3.7, "pink" },
		{ "c", 0, 10, 0, 3.4, 4, 3.4, "white" },
		{ "c", 0, 14, 0, 3.1, 4, 3.1, "pink" },
		{ "c", 0, 16.2, 0, 4.4, 0.4, 4.4, "cream" },
	}
	for _, p in { { -1.1, -1.1 }, { 1.1, -1.1 }, { -1.1, 1.1 }, { 1.1, 1.1 } } do
		table.insert(rows, { "b", p[1], 17.9, p[2], 0.25, 3, 0.25, "white" })
	end
	table.insert(rows, { "c", 0, 19.7, 0, 3.2, 0.6, 3.2, "rose" })
	table.insert(rows, { "c", 0, 20.3, 0, 2.2, 0.6, 2.2, "pink" })
	table.insert(rows, { "c", 0, 20.9, 0, 1.2, 0.6, 1.2, "rose" })
	table.insert(rows, { "s", 0, 21.6, 0, 0.8, 0.8, 0.8, "lemon", "n" })
	table.insert(rows, { "b", 0, 1, -2.02, 1.2, 2, 0.1, "choco" })
	table.insert(rows, { "b", 0, 9.5, -1.72, 0.6, 0.9, 0.1, "lemon", "n" })
	RanchKit.rows(out, base, "lh", rows, P)
	local lantern = RanchKit.row(base, RanchTiers.LANTERN_KEY, {
		"b",
		0,
		17.9,
		0,
		1.4,
		1.6,
		1.4,
		if ready then RanchTiers.READY else RanchTiers.LANTERN,
		"n",
		0,
		45,
		0,
	}, P)
	lantern.anim = "spin"
	lantern.pivot = base.Position
	lantern.period = RanchTiers.LANTERN_PERIOD
	lantern.phase = 0
	table.insert(out, lantern)
	return out
end

local function lighthouseReduced(slot: number, ready: boolean): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "lighthouse")
	RanchKit.rows(out, base, "farLh", {
		{ "c", 0, 8, 0, 3.6, 16, 3.6, "white" },
		{ "c", 0, 17.6, 0, 1.6, 1.6, 1.6, if ready then RanchTiers.READY else RanchTiers.LANTERN, "n" },
		{ "c", 0, 19.2, 0, 2.4, 1.6, 2.4, "rose" },
	}, P)
	return out
end

-- Dôme néon (Z 70, Y 16, au-dessus de l'étagère) : 3 arches filaires Neon de 4 segments, épi et
-- joyau Neon ; 14 pièces
local function dome(slot: number): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "dome")
	local radius = 5.5
	local colors = { "cyan", "jelly", "lilac" }
	for k = 0, 2 do
		local theta = math.rad(60 * k)
		local plane = base * CFrame.Angles(0, -theta, 0)
		local rows: { Row } = {}
		for j = 0, 3 do
			local a1, a2 = math.pi * j / 4, math.pi * (j + 1) / 4
			table.insert(
				rows,
				segment(
					radius * math.cos(a1),
					0.2 + radius * math.sin(a1),
					radius * math.cos(a2),
					0.2 + radius * math.sin(a2),
					0,
					0.25,
					0.25,
					colors[k + 1],
					"n",
					0.15
				)
			)
		end
		RanchKit.rows(out, plane, "dome" .. (k + 1) .. "_", rows, P)
	end
	RanchKit.rows(out, base, "domeTop", {
		{ "s", 0, 5.55, 0, 0.9, 0.9, 0.9, "lemon", "n" },
		{ "s", 0, 1.6, 0, 1.2, 1.2, 1.2, "jelly", "n" },
	}, P)
	return out
end

-- Couronne flottante (Y 18 au-dessus du portail, tourne lentement) : bandeau hexagonal de 6 pièces,
-- 3 pointes, 3 joyaux Neon ; étoiles Neon (1 à 4) ; arc-en-ciel : bandeau et pointes en Neon de 7
-- couleurs ; 12 pièces + étoiles
local function crown(slot: number, stars: number, rainbow: boolean): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "crown")
	local hex = 1.8
	local apothem = hex * math.cos(math.pi / 6)
	for k = 0, 5 do
		local a = math.rad(60 * k + 30)
		local plane = base * CFrame.Angles(0, -a, 0)
		local color: any = if rainbow then RAINBOW[k + 1] else "gold"
		table.insert(
			out,
			RanchKit.row(
				plane,
				"crownBand" .. (k + 1),
				{ "b", apothem, 0.5, 0, 0.3, 1, hex + 0.1, color, if rainbow then "n" else "f" },
				P
			)
		)
	end
	local gems = { "jelly", "mint", "sky" }
	for i, k in { 0, 2, 4 } do
		local a = math.rad(60 * k)
		local x, z = hex * math.cos(a), hex * math.sin(a)
		local color: any = if rainbow then RAINBOW[i + 3] else "gold"
		table.insert(
			out,
			RanchKit.row(
				base,
				"crownPoint" .. i,
				{ "b", x, 1.6, z, 0.35, 1.2, 0.35, color, if rainbow then "n" else "f" },
				P
			)
		)
		table.insert(
			out,
			RanchKit.row(base, "crownGem" .. i, { "s", x, 2.45, z, 0.5, 0.5, 0.5, gems[i], "n" }, P)
		)
	end
	local n = math.clamp(math.floor(stars), 0, 4)
	local xs = { -1.2, -0.4, 0.4, 1.2 }
	for i = 1, n do
		table.insert(
			out,
			RanchKit.row(
				base,
				"crownStar" .. i,
				{ "b", xs[i], 3.4, 0, 0.6, 0.6, 0.2, "lemon", "n", 0, 0, 45 },
				P
			)
		)
	end
	for _, spec in out do
		spec.anim = "spin"
		spec.pivot = base.Position
		spec.period = RanchTiers.CROWN_PERIOD
		spec.phase = 0
	end
	return out
end

local function crownReduced(slot: number, rainbow: boolean): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "crown")
	local band: any = if rainbow then RAINBOW[5] else "gold"
	RanchKit.rows(out, base, "farCrown", {
		{ "c", 0, 0.5, 0, 3.6, 1, 3.6, band, if rainbow then "n" else "f" },
		{ "b", 1.8, 1.6, 0, 0.35, 1.2, 0.35, band, if rainbow then "n" else "f" },
		{ "s", 1.8, 2.45, 0, 0.5, 0.5, 0.5, "jelly", "n" },
	}, P)
	return out
end

export type TierState = {
	color: Color3, -- couleur du ranch (drapeau de la tour)
	ready: boolean, -- Grand Splorch prêt (lanterne rose)
	stars: number, -- étoiles de couronne (0 … 4)
	rainbow: boolean, -- couronne arc-en-ciel (Record R 50)
}

-- Pièces du palier n (1 … 6) en détail complet ; liste vide sinon
function RanchTiers.tier(slot: number, n: number, s: TierState): { Spec }
	if n == 1 then
		return arch(slot)
	elseif n == 2 then
		return tower(slot, s.color)
	elseif n == 3 then
		return balcony(slot)
	elseif n == 4 then
		return lighthouse(slot, s.ready)
	elseif n == 5 then
		return dome(slot)
	elseif n == 6 then
		return crown(slot, s.stars, s.rainbow)
	end
	return {}
end

-- Pièces du palier n en détail réduit (D6 : tour, phare, couronne, 3 chacun) ; liste vide sinon
function RanchTiers.tierReduced(slot: number, n: number, s: TierState): { Spec }
	if n == 2 then
		return towerReduced(slot, s.color)
	elseif n == 4 then
		return lighthouseReduced(slot, s.ready)
	elseif n == 6 then
		return crownReduced(slot, s.rainbow)
	end
	return {}
end

-- =============================================================================================
-- Éléments du Record R
-- =============================================================================================

export type VatState = {
	rings: number, -- 1 … 8
	nozzles: number, -- 0 … 5
	period: number, -- s par tour de l'agitateur
	rainbow: boolean,
	golden: boolean,
}

RanchTiers.VAT_RING_STEP = 1.1 -- anneau k à Y = 1 + 1,1 k (sous le couvercle à Y 10)
RanchTiers.NOZZLE_RADIUS = 4 -- buses autour du socle de la Cuve (Ø 7)

-- Cuve à Gelée : anneaux lumineux (qualité), agitateur à 3 pales sous le couvercle (vitesse, arc-en-
-- ciel au Record R 4), buses (0 … 5) sur l'avant du socle ; dorée au Record R 7 (anneaux dorés)
function RanchTiers.vat(slot: number, v: VatState): { Spec }
	local out: { Spec } = {}
	local base = localCF(slot, WorldLayout.toLocal(slot, WorldLayout.anchor(slot, "vat")))
	local ringColor = if v.golden then P.gold else P.jelly
	for k = 1, math.clamp(math.floor(v.rings), 0, 8) do
		table.insert(
			out,
			RanchKit.row(
				base,
				"vatRing" .. k,
				{ "c", 0, 1 + RanchTiers.VAT_RING_STEP * k, 0, 6.3, 0.2, 6.3, ringColor, "n" },
				P
			)
		)
	end
	local stirrer: { Spec } = {}
	table.insert(stirrer, RanchKit.row(base, "vatShaft", { "c", 0, 8.2, 0, 0.35, 3.6, 0.35, "white" }, P))
	local bladeColors = { "jelly", "lemon", "cyan" }
	for i = 1, 3 do
		local plane = base * CFrame.Angles(0, math.rad(120 * (i - 1)), 0)
		local color: any = if v.rainbow then bladeColors[i] else "white"
		table.insert(
			stirrer,
			RanchKit.row(
				plane,
				"vatBlade" .. i,
				{ "b", 1.3, 6.8, 0, 2.2, 0.18, 0.6, color, if v.rainbow then "n" else nil },
				P
			)
		)
	end
	for _, spec in stirrer do
		spec.anim = "spin"
		spec.pivot = base.Position
		spec.period = math.max(0.5, v.period)
		spec.phase = 0
		table.insert(out, spec)
	end
	for i = 1, math.clamp(math.floor(v.nozzles), 0, 5) do
		-- avant droit du socle (vers le portail et les enclos), de −90° à 0° : à 8 studs au moins du
		-- centre de la prise réservée (Z 52, X −28) et de toute dalle
		local a = math.rad(-90 + 22.5 * (i - 1))
		local plane = base * CFrame.Angles(0, -a, 0)
		table.insert(
			out,
			RanchKit.row(
				plane,
				"vatNozzle" .. i,
				{ "x", RanchTiers.NOZZLE_RADIUS, 0.7, 0, 1, 0.45, 0.45, "mint", "n" },
				P
			)
		)
	end
	return out
end

-- Pièces de la Cuve
function RanchTiers.vatCount(v: VatState): number
	return math.clamp(math.floor(v.rings), 0, 8) + 4 + math.clamp(math.floor(v.nozzles), 0, 5)
end

-- Bassin-fontaine (Record R 9) : 3 jets Neon au milieu du Bassin (loin des places flottantes)
function RanchTiers.fountain(slot: number): { Spec }
	local out: { Spec } = {}
	local base = localCF(slot, WorldLayout.toLocal(slot, WorldLayout.anchor(slot, "pool")))
	local heights = { 2.6, 3.4, 2.6 }
	for i = 1, 3 do
		local a = math.rad(90 + 120 * (i - 1))
		local h = heights[i]
		table.insert(
			out,
			RanchKit.row(
				base,
				"fountainJet" .. i,
				{ "c", math.cos(a), 0.85 + h / 2, math.sin(a), 0.6, h, 0.6, "aqua", "n" },
				P
			)
		)
	end
	return out
end

-- 8 lampions de la clôture (Record R 12) sur les poteaux : Neon pendant la Jelly Moon seulement
function RanchTiers.lanterns(slot: number, lit: boolean): { Spec }
	local out: { Spec } = {}
	for i = 1, 8 do
		local base = anchorCF(slot, ("lantern" .. i) :: any)
		table.insert(
			out,
			RanchKit.row(base, "lantern" .. i, {
				"s",
				0,
				0.6,
				0,
				1,
				1,
				1,
				if lit then RanchTiers.LIT else RanchTiers.UNLIT,
				if lit then "n" else nil,
			}, P)
		)
	end
	return out
end

-- Portail arc-en-ciel (Record R 13) : 7 segments fixes qui habillent les poteaux et l'arche du
-- portail du serveur (rouge, orange, jaune à gauche de bas en haut ; vert en haut ; bleu, indigo,
-- violet à droite de haut en bas) ; aucun clignotement
function RanchTiers.rainbowGate(slot: number): { Spec }
	local out: { Spec } = {}
	local base = WorldLayout.ranchCFrame(slot)
	local x = WorldLayout.Const.GateHalfWidth + WorldLayout.Const.FenceThickness / 2
	local z = WorldLayout.Const.FenceThickness / 2
	local h = 10 / 3
	local rows: { Row } = {
		{ "b", -x, h * 0.5, z, 1.12, h + 0.02, 1.12, RAINBOW[1] },
		{ "b", -x, h * 1.5, z, 1.12, h + 0.02, 1.12, RAINBOW[2] },
		{ "b", -x, h * 2.5, z, 1.12, h + 0.02, 1.12, RAINBOW[3] },
		{ "b", 0, 10.5, z, 2 * x + 1.12, 1.12, 1.12, RAINBOW[4] },
		{ "b", x, h * 2.5, z, 1.12, h + 0.02, 1.12, RAINBOW[5] },
		{ "b", x, h * 1.5, z, 1.12, h + 0.02, 1.12, RAINBOW[6] },
		{ "b", x, h * 0.5, z, 1.12, h + 0.02, 1.12, RAINBOW[7] },
	}
	return RanchKit.rows(out, base, "gateBand", rows, P)
end

-- Geyser de gelée (Record R 17, X −24, Z 4 à 10) : monticule, jet Neon, goutte qui monte et descend
function RanchTiers.geyser(slot: number): { Spec }
	local out: { Spec } = {}
	local base = anchorCF(slot, "geyser")
	RanchKit.rows(out, base, "geyser", {
		{ "c", 0, 0.2, 0, 2, 0.4, 2, "caramel" },
		{ "c", 0, 3.4, 0, 0.9, 6, 0.9, "jelly", "n" },
	}, P)
	local blob = RanchKit.row(base, "geyserBlob", { "s", 0, 6.9, 0, 1.4, 1.4, 1.4, "jelly", "n" }, P)
	blob.anim = "bob"
	blob.amp = 0.3
	blob.period = 1.6
	blob.phase = 0
	table.insert(out, blob)
	return out
end

-- Maisonnette des Plopettes (Record R 2) : socle, murs, toit à deux pans, porte, fenêtre Neon ;
-- 6 pièces non solides, juste derrière le point de WorldLayout.helperHouse (porte vers le portail)
function RanchTiers.house(slot: number): { Spec }
	local out: { Spec } = {}
	local door = WorldLayout.toLocal(slot, WorldLayout.helperHouse(slot))
	local base = localCF(slot, Vector3.new(door.X, 0, door.Z + 2.5))
	return RanchKit.rows(out, base, "house", {
		{ "b", 0, 0.15, 0, 3.5, 0.3, 3, "wood" },
		{ "b", 0, 1.6, 0, 3, 2.6, 2.6, "mint" },
		{ "b", 0, 3.55, -0.65, 3.4, 0.3, 1.9, "rose", nil, -38, 0, 0 },
		{ "b", 0, 3.55, 0.65, 3.4, 0.3, 1.9, "rose", nil, 38, 0, 0 },
		{ "b", 0, 1.05, -1.35, 0.9, 1.5, 0.1, "choco" },
		{ "s", 0, 2.3, -1.2, 0.6, 0.6, 0.6, "lemon", "n" },
	}, P)
end

RanchTiers.HOUSE_PARTS = 6
RanchTiers.FOUNTAIN_PARTS = 3
RanchTiers.LANTERN_PARTS = 8
RanchTiers.GATE_PARTS = 7
RanchTiers.GEYSER_PARTS = 3

-- =============================================================================================
-- Accessoires de la silhouette (plan vertical du ranch passant par son centre, face à la place)
-- =============================================================================================

RanchTiers.FRAME_PARTS = 8
RanchTiers.READY_PARTS = 8
RanchTiers.SUN_PARTS = 9

local function silhouetteCF(slot: number): CFrame
	return WorldLayout.v2Anchor(slot, "frame")
end

-- Octogone de 8 segments dont le côté le plus proche est à `apothem` du centre de la silhouette
-- (sommets à 22,5° + 45° k) dans le plan de la silhouette
local function octagon(
	slot: number,
	prefix: string,
	apothem: number,
	t: number,
	z: number,
	color: Color3,
	material: string
): { Spec }
	local radius = (apothem + t / 2) / math.cos(math.pi / 8)
	local rows: { Row } = {}
	for k = 0, 7 do
		local a1, a2 = math.rad(22.5 + 45 * k), math.rad(22.5 + 45 * (k + 1))
		table.insert(
			rows,
			segment(
				radius * math.cos(a1),
				radius * math.sin(a1),
				radius * math.cos(a2),
				radius * math.sin(a2),
				z,
				t,
				t,
				color,
				material,
				t
			)
		)
	end
	return RanchKit.rows({}, silhouetteCF(slot), prefix, rows, P)
end

-- Cadre doré (Record R 18) autour de la silhouette de rayon r : octogone Foil au rayon r + 1,5
function RanchTiers.frame(slot: number, r: number): { Spec }
	return octagon(slot, "frame", r + 1.5, 0.7, 0, P.gold, "f")
end

-- Anneau rose du signal « prêt » au rayon r + 3 : pulse (au plus 3 changements de couleur par
-- seconde ; immobile et rose fixe en Mouvement réduit)
function RanchTiers.readyRing(slot: number, r: number): { Spec }
	local out = octagon(slot, "readyRing", r + 3, 0.5, 0, RanchTiers.READY, "n")
	for _, spec in out do
		spec.anim = "pulse"
		spec.alt = RanchTiers.READY_ALT
		spec.phase = 0
	end
	return out
end

-- Anneau-soleil (GiantTier ≥ 3, « Squishy-Soleil ») derrière la silhouette : disque pâle et 8 rayons
-- Neon de r + 1 à r + 5
function RanchTiers.sunRing(slot: number, r: number): { Spec }
	local base = silhouetteCF(slot)
	local out: { Spec } = {}
	table.insert(
		out,
		RanchKit.row(base, "sunDisc", { "x", 0, 0, 2.2, 0.3, 2 * (r + 0.5), 0, "sun", nil, 0, 90, 0 }, P)
	)
	for k = 0, 7 do
		local a = math.rad(45 * k)
		local mid = r + 3
		table.insert(
			out,
			RanchKit.row(base, "sunRay" .. (k + 1), {
				"b",
				mid * math.cos(a),
				mid * math.sin(a),
				2.4,
				4,
				1.2,
				0.3,
				"orange",
				"n",
				0,
				0,
				math.deg(a),
			}, P)
		)
	end
	return out
end

-- Rayon montré d'une silhouette (studs) arrondi au pair supérieur, au plus le plafond du plan
-- (WorldLayout.Const.SilhouetteRadius) : les accessoires ne bougent qu'à chaque palier de 2 studs
function RanchTiers.quantize(radius: number): number
	if type(radius) ~= "number" or radius ~= radius or radius <= 0 then
		return 0
	end
	return math.min(WorldLayout.Const.SilhouetteRadius, 2 * math.ceil(radius / 2))
end

return RanchTiers
