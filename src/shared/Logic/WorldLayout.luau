--!strict
-- WorldLayout (paquet logic, docs/04 §3, §12.1). Plan de Wobbleton, pur (GDD §11.1, §11.2) :
-- ranchs 1-16 (repère local : X de −32 à +32, Z du portail 0 au fond 72 ; ranch k centré sur
-- 22,5° × (k − 1) + 11,25°, portail à r = 178, tourné vers la place), place, graphe des rues,
-- solides (boîtes) et surface du sol. Toute position dont le jeu a besoin vient d'ici, jamais d'une
-- recherche dans le workspace (règle zéro bug).
-- Conventions : origine au centre de la place, Y vers le haut, dessus du plateau à Y = 0 ; un angle
-- a se lit (r cos a, 0, r sin a) ; le nord est −Z (statue en (0, 0, −38)). Repère d'un ranch : axe Z
-- local = direction vers l'extérieur (le fond), axe X local = (sin a, 0, −cos a) ; LookVector du
-- CFrame = vers la place.
-- Solides (WorldLayout.solids()) : [1] le plateau (boîte 644 × 4 × 644, dessus à Y = 0, seule boîte
-- sous Const.SolidMinHeight) ; puis 5 murs par ranch (clôture et mur invisible confondus, 30 studs,
-- posés À L'INTÉRIEUR du rectangle : l'écart entre deux ranchs voisins reste ≥ 6,68 studs) ; puis
-- 24 maisons-bonbons (une boîte de 30 studs chacune, coiffe comprise) ; puis 64 segments du mur du
-- bord (r = 322, faces intérieures sur le cercle, bouts qui se chevauchent : aucune fente). Deux
-- solides sont collés ou à ≥ 6 studs. Aucune arête du graphe n'entre dans un ranch ni dans une maison.

-- Constantes du plan (GDD §11.1), publiques
-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, typeof, math, table = type, typeof, math, table

local CONST = {
	PlateRadius = 320,
	WallRadius = 322,
	HillsRadius = 420,
	PlazaRadius = 50,
	InnerRing = 95,
	Boulevard = 166,
	GateRadius = 178,
	BackRadius = 250,
	RanchWidth = 64,
	RanchDepth = 72,
	Ranches = 16,
	MeadowRadius = 280,
	-- Hauteurs des solides (docs/04 §3.1, §20 n° 21) : AU-DESSUS de la plus haute hauteur atteignable
	-- (selle géante : saut 13 + HipHeight jusqu'à 6 + marge), pour que personne n'enjambe un mur ni
	-- ne monte sur un toit, même en monture. WorldBuild.spec vérifie chaque boîte de solids().
	MaxReach = 22, -- studs au-dessus du sol : saut le plus haut (13) + décalage de racine max (6) + 3
	SolidMinHeight = 30, -- hauteur minimale de toute boîte de solids() (≥ MaxReach + 8)
	FenceWallHeight = 30, -- mur invisible au-dessus de la clôture d'un ranch (GDD §11.2 : 12, relevé)
	EdgeWallHeight = 30, -- murs invisibles du bord (r = 322)
	HouseCapHeight = 30, -- boîte invisible au-dessus de chaque maison-bonbon (toit inaccessible)
	-- Géométrie fixée par logic (docs/04 §12.1)
	FenceThickness = 1, -- murs de clôture, posés à l'intérieur du rectangle du ranch
	GateHalfWidth = 4, -- portail de 8 studs (X de −4 à +4)
	EdgeSegments = 64, -- segments du mur du bord
	EdgeThickness = 2,
	PlateThickness = 4,
	SpawnHeight = 3, -- hauteur de la racine (HumanoidRootPart) au point d'apparition
	-- hauteur de la racine d'un personnage DEBOUT au-dessus de ses pieds (HipHeight 2 + demi-racine 1) :
	-- doit rester égale à Server/Movement/Tuning.RootHeight (MoveCheck), vérifié par ZoneRules.spec ;
	-- ZoneRules.feetY la retire de la racine (contrat v1.2, portées mesurées depuis les pieds)
	RootHeight = 3,
	GateOutsideDistance = 6, -- point de poussée d'un intrus devant le portail
	AltarRadius = 12, -- présence à l'Autel de la Lune
	PoolSlotRadius = 3.5, -- places flottantes du Bassin autour de son centre
	MeadowSpread = 12, -- places de la Prairie autour de son centre
	-- v2.0 (lot B4, GDD v2.0 §11.1, §11.2, §11.5 ; docs/04 §27.14) : ajouts seulement, aucune
	-- position de la v1.3 ne change
	SilhouetteRadius = 19, -- = Balance.SizeScale.BaseDiameter × SilhouetteCap / 2 (WorldLayout.spec)
	CenterColumnMargin = 2, -- colonne du centre : rayon de la silhouette + 2
	V2Elevated = 8, -- un décor v2 dont le bas est à ≥ 8 studs est « en hauteur » (règle de la colonne seule)
	PadClearance = 8, -- centre d'une dalle → bord d'une emprise v2 au sol (6 studs du bord de la dalle)
	MonumentRadius = 6, -- emprise d'un Monument (≤ 20 pièces, 12 × 12 studs)
	MonumentTop = 18, -- hauteur maximale d'un Monument
	DecoSmallRadius = 1.25, -- emplacement « P » de Déco perso (objet ≤ 2,5 studs)
	DecoLargeRadius = 2.25, -- emplacement « G » (objet ≤ 4,5 studs)
	-- kiosque de Big Plop (échoppe de 15 pièces) : emprise RÉELLE du dessin (auvent et comptoir ≤ 4,21 studs
	-- du centre, RanchRenderer_v2 › relecture B4 ; 2,75 avant la relecture, R-B4-2)
	KioskRadius = 4.25,
	MeadowV2Radius = 12, -- Prairie v2 : disque fleuri Ø 24
	MeadowV2Spread = 9, -- places de la Prairie v2 autour de son centre
	ObservatoryRadius = 340, -- Observatoire, colline nord, au-delà du mur du bord (inaccessible)
	-- Observatoire (tour ronde + coupole, 24 pièces) : emprise réelle du dessin (marches ≤ 8,25 studs du centre ;
	-- 6 avant la relecture du lot B4, R-B4-2)
	ObservatoryFootprint = 8.5,
}

export type Anchor =
	"pot"
	| "vat"
	| "pool"
	| "bowl"
	| "cushion"
	| "shelf"
	| "fountain"
	| "sign"
	| "silhouette"
	| "gate"
export type PlazaName =
	"center"
	| "megaPad"
	| "statue"
	| "shop"
	| "altar"
	| "gauge"
	| "stage"
	| "goldenFountain"
	| "boards"
	| "kiosk"
-- Décors v2.0 du ranch (lot B4) : paliers, geyser, cadre doré, 8 lampions, ciel
export type V2Anchor =
	"arch"
	| "tower"
	| "balcony"
	| "lighthouse"
	| "dome"
	| "crown"
	| "geyser"
	| "frame"
	| "lantern1"
	| "lantern2"
	| "lantern3"
	| "lantern4"
	| "lantern5"
	| "lantern6"
	| "lantern7"
	| "lantern8"
	| "sky"
-- Emprise d'un décor v2 dans le repère local d'un ranch (disque x, z, r ou boîte x0 … x1, z0 … z1),
-- de bottom à top (studs) : la règle de placement de WorldLayout.spec la vérifie pour les 16 ranchs
export type Footprint = {
	name: string,
	kind: "disc" | "box",
	x: number,
	z: number,
	r: number,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	bottom: number,
	top: number,
	accessory: boolean, -- accessoire de la silhouette : seul décor v2 permis dans la colonne au-dessus de Y = 21
	fence: boolean, -- posé sur la clôture (lampions sur les poteaux)
	outside: boolean, -- derrière le fond, hors clôture (tour, balcon, phare, ciel, Monuments)
}
export type DecoSlotDef = { position: Vector3, size: "P" | "G" }
export type Column = { center: Vector3, radius: number, floor: number }
export type Graph = { nodes: { Vector3 }, neighbors: { { number } } }
export type Box = { cframe: CFrame, size: Vector3 }

local WorldLayout = {}

WorldLayout.Const = CONST

-- =============================================================================================
-- Données du plan (positions locales d'un ranch, GDD §11.2)
-- =============================================================================================

-- Objets d'un ranch (repère local)
local ANCHORS: { [string]: Vector3 } = {
	pot = Vector3.new(-20, 0, 6),
	vat = Vector3.new(-20, 0, 52),
	pool = Vector3.new(6, 0, 52),
	bowl = Vector3.new(22, 0, 58),
	cushion = Vector3.new(22, 0, 10),
	shelf = Vector3.new(0, 0, 70),
	fountain = Vector3.new(12, 0, -6),
	sign = Vector3.new(0, 14, 0),
	silhouette = Vector3.new(0, 40, 36),
	gate = Vector3.new(0, 0, 0),
}

-- Prises de dalles (Config/Pads.Defs[].socket) : rangée Z = 67 (contrat v1.2, GDD v1.3 §11.2 : à Z = 62
-- la rangée était à 2 studs du bord du Bassin et la dalle de droite à 4,5 studs du bol, on achetait sans
-- le vouloir) ; la 5e (réservée, Gelée lente de janvier) à côté de la Cuve. Règle de plan
-- (WorldLayout.spec) : centre d'une dalle à ≥ 8 studs du bol, de la Cuve, du Pot, du coussin, de la prise
-- réservée et du bord du Bassin ; dalles à 12 studs ; décorations à ≥ 6 studs du bord d'une dalle.
local PAD_SOCKETS: { Vector3 } = {
	Vector3.new(-18, 0, 67),
	Vector3.new(-6, 0, 67),
	Vector3.new(6, 0, 67),
	Vector3.new(18, 0, 67),
	Vector3.new(-28, 0, 52),
}

-- Places d'enclos : 4 rangées de 6 (colonnes tous les 9 studs, rangées tous les 8), loin du Pot et
-- du coussin (affichage plafonné à 4× : Ø 8)
local PEN_COLUMNS = { -22.5, -13.5, -4.5, 4.5, 13.5, 22.5 }
local PEN_ROWS = { 16, 24, 32, 40 }

-- Places à la clôture (côté intérieur du mur de devant, hors du portail, du Pot et du coussin)
local FENCE_POINTS: { Vector3 } = {
	Vector3.new(-27, 0, 5),
	Vector3.new(-12, 0, 5),
	Vector3.new(12, 0, 5),
	Vector3.new(27, 0, 5),
}

-- 18 emplacements de décoration (ordre d'apparition de Config/Pads.Decor) : bandes le long des
-- murs, entre la Cuve et le Bassin, aux coins du fond. Contrat v1.2 : les n° 9, 10, 13 et 14 (à moins
-- de 6 studs des dalles de la rangée Z = 67) sont déplacés aux coins du fond et entre la Cuve, le
-- Bassin et les dalles.
local DECOR_SLOTS: { Vector3 } = {
	Vector3.new(29, 0, 16),
	Vector3.new(-29, 0, 16),
	Vector3.new(29, 0, 24),
	Vector3.new(-29, 0, 24),
	Vector3.new(-9, 0, 50),
	Vector3.new(17, 0, 50),
	Vector3.new(29, 0, 32),
	Vector3.new(-29, 0, 32),
	Vector3.new(-28, 0, 67),
	Vector3.new(28, 0, 67),
	Vector3.new(29, 0, 40),
	Vector3.new(-29, 0, 40),
	Vector3.new(-12, 0, 59),
	Vector3.new(13, 0, 60),
	Vector3.new(29, 0, 48),
	Vector3.new(-29, 0, 48),
	Vector3.new(29, 0, 56),
	Vector3.new(-29, 0, 58),
}
local DECOR_FACE = Vector3.new(0, 0, 30) -- les décorations regardent le milieu des enclos

-- Objets de la place (monde)
local PLAZA: { [string]: Vector3 } = {
	center = Vector3.new(0, 0, 0),
	megaPad = Vector3.new(0, 0, 0),
	statue = Vector3.new(0, 0, -38),
	shop = Vector3.new(38, 0, 0),
	altar = Vector3.new(-38, 0, 0),
	gauge = Vector3.new(0, 0, 38),
	stage = Vector3.new(27, 0, 27),
	goldenFountain = Vector3.new(20, 0, -20),
	boards = Vector3.new(0, 0, -46),
	-- v2.0 (lot B4) : kiosque de Big Plop, ouest-sud-ouest de la place (GDD §11.1) ; (−32, 0, 24) depuis la
	-- relecture du lot B4 (R-B4-2) : avec son emprise réelle (4,25), jamais sur le point d'apparition neutre
	-- (6 × 6 en (−24, 0, 24)) où chaque personnage apparaît avant d'être placé dans son ranch
	kiosk = Vector3.new(-32, 0, 24),
}

-- Centre de la Prairie des copains : au nord (−Z), entre le fond des ranchs (r ≤ 252) et le bord
local MEADOW_CENTER = Vector3.new(0, 0, -(CONST.MeadowRadius + 4))
-- v2.0 (lot B4, D9) : la Prairie déménage dans un jardin du quartier nord (r ≈ 145, 291°) ; r = 280 est
-- la bande des Monuments. Point le plus dégagé du quart nord pour un disque de rayon MeadowV2Radius
-- (recherche du plan, marge ≥ 1 stud prouvée par WorldLayout.spec)
local MEADOW_V2_CENTER = Vector3.new(52, 0, -135.5)

-- =============================================================================================
-- Repères des ranchs (cache pur)
-- =============================================================================================

type Frame = { ox: number, oz: number, xx: number, xz: number, zx: number, zz: number, cframe: CFrame }

local FRAMES: { Frame } = {}
for slot = 1, CONST.Ranches do
	local angle = math.rad(22.5 * (slot - 1) + 11.25)
	local c, s = math.cos(angle), math.sin(angle)
	local ox, oz = CONST.GateRadius * c, CONST.GateRadius * s
	-- axe X local = (sin a, 0, −cos a), axe Z local = (cos a, 0, sin a) : X × Y = Z (main droite)
	local cframe = CFrame.fromMatrix(
		Vector3.new(ox, 0, oz),
		Vector3.new(s, 0, -c),
		Vector3.new(0, 1, 0),
		Vector3.new(c, 0, s)
	)
	FRAMES[slot] = { ox = ox, oz = oz, xx = s, xz = -c, zx = c, zz = s, cframe = cframe }
end

local function validSlot(slot: any): boolean
	return type(slot) == "number" and FRAMES[slot] ~= nil
end

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- Vector3 sûr (composantes non finies → 0)
local function saneVec(v: any): Vector3
	if typeof(v) ~= "Vector3" then
		return Vector3.zero
	end
	local x, y, z = finite(v.X, 0), finite(v.Y, 0), finite(v.Z, 0)
	if x == v.X and y == v.Y and z == v.Z then
		return v
	end
	return Vector3.new(x, y, z)
end

local function localToWorld(f: Frame, lx: number, ly: number, lz: number): Vector3
	return Vector3.new(f.ox + lx * f.xx + lz * f.zx, ly, f.oz + lx * f.xz + lz * f.zz)
end

local function worldToLocalXZ(f: Frame, x: number, z: number): (number, number)
	local dx, dz = x - f.ox, z - f.oz
	return dx * f.xx + dz * f.xz, dx * f.zx + dz * f.zz
end

-- =============================================================================================
-- Ranchs
-- =============================================================================================

-- Repère local du ranch (origine au portail, Z vers le fond, tourné vers la place)
function WorldLayout.ranchCFrame(slot: number): CFrame
	if not validSlot(slot) then
		return CFrame.new()
	end
	return FRAMES[slot].cframe
end

-- Point local → monde
function WorldLayout.toWorld(slot: number, localPos: Vector3): Vector3
	local p = saneVec(localPos)
	if not validSlot(slot) then
		return p
	end
	return localToWorld(FRAMES[slot], p.X, p.Y, p.Z)
end

-- Point monde → local
function WorldLayout.toLocal(slot: number, worldPos: Vector3): Vector3
	local p = saneVec(worldPos)
	if not validSlot(slot) then
		return p
	end
	local lx, lz = worldToLocalXZ(FRAMES[slot], p.X, p.Z)
	return Vector3.new(lx, p.Y, lz)
end

local HALF_WIDTH = CONST.RanchWidth / 2

local function insideRect(f: Frame, x: number, z: number): boolean
	local lx, lz = worldToLocalXZ(f, x, z)
	return lx >= -HALF_WIDTH and lx <= HALF_WIDTH and lz >= 0 and lz <= CONST.RanchDepth
end

-- Distance (XZ) d'un point au rectangle d'un ranch (0 dedans)
local function rectDistance(f: Frame, x: number, z: number): number
	local lx, lz = worldToLocalXZ(f, x, z)
	local dx = math.max(math.abs(lx) - HALF_WIDTH, 0)
	local dz = math.max(-lz, lz - CONST.RanchDepth, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Ranchs proches d'une position : le secteur le plus proche et ses deux voisins
local function nearbySlots(x: number, z: number): (number, number, number)
	local angle = math.deg(math.atan2(z, x)) % 360
	local guess = math.floor((angle - 11.25) / 22.5 + 0.5) % CONST.Ranches + 1
	return guess, (guess - 2) % CONST.Ranches + 1, guess % CONST.Ranches + 1
end

-- Ranch dont le rectangle contient la position (0 = aucun)
function WorldLayout.ranchAt(pos: Vector3): number
	local p = saneVec(pos)
	local r2 = p.X * p.X + p.Z * p.Z
	local inner = CONST.GateRadius - 1
	local outer = CONST.BackRadius + HALF_WIDTH
	if r2 < inner * inner or r2 > outer * outer then
		return 0 -- en dehors de l'anneau des ranchs
	end
	-- secteur le plus proche, puis ses deux voisins (les rectangles débordent un peu du secteur)
	local a, b, c = nearbySlots(p.X, p.Z)
	for _, slot in { a, b, c } do
		if insideRect(FRAMES[slot], p.X, p.Z) then
			return slot
		end
	end
	return 0
end

-- Ranch dont le rectangle est à `margin` studs ou moins de la position (0 = aucun). Fonction
-- ajoutée : les trajets des créatures (SeededPath) gardent une marge avec chaque ranch.
function WorldLayout.ranchNear(pos: Vector3, margin: number): number
	local p = saneVec(pos)
	local m = math.max(0, finite(margin, 0))
	local r = math.sqrt(p.X * p.X + p.Z * p.Z)
	if r < CONST.GateRadius - m - 1 or r > CONST.BackRadius + HALF_WIDTH + m + 1 then
		return 0
	end
	local a, b, c = nearbySlots(p.X, p.Z)
	for _, slot in { a, b, c } do
		if rectDistance(FRAMES[slot], p.X, p.Z) <= m then
			return slot
		end
	end
	return 0
end

-- Position dans le rectangle de ce ranch
function WorldLayout.inRanch(slot: number, pos: Vector3): boolean
	if not validSlot(slot) then
		return false
	end
	local p = saneVec(pos)
	return insideRect(FRAMES[slot], p.X, p.Z)
end

-- Point de poussée d'un intrus : 6 studs devant le portail, côté rue
function WorldLayout.gateOutside(slot: number): Vector3
	if not validSlot(slot) then
		return Vector3.new(0, CONST.SpawnHeight, 0)
	end
	return localToWorld(FRAMES[slot], 0, CONST.SpawnHeight, -CONST.GateOutsideDistance)
end

-- Point d'apparition (Z = 30, X = 0) face au Pot
function WorldLayout.spawnCFrame(slot: number): CFrame
	if not validSlot(slot) then
		return CFrame.new(0, CONST.SpawnHeight, 0)
	end
	local f = FRAMES[slot]
	local pos = localToWorld(f, 0, CONST.SpawnHeight, 30)
	local pot = ANCHORS.pot
	local target = localToWorld(f, pot.X, CONST.SpawnHeight, pot.Z)
	return CFrame.lookAt(pos, target)
end

-- Position monde d'un objet du ranch (Pot, Cuve, Bassin, bol, coussin, étagère, Fontaine, panneau, silhouette)
function WorldLayout.anchor(slot: number, name: Anchor): Vector3
	local p = ANCHORS[name] or ANCHORS.gate
	if not validSlot(slot) then
		return p
	end
	return localToWorld(FRAMES[slot], p.X, p.Y, p.Z)
end

-- Le nom désigne un objet du ranch (fonction ajoutée : anchor rend le portail pour un nom inconnu,
-- ZoneRules.near refuse un nom inconnu au lieu de mesurer le portail)
function WorldLayout.hasAnchor(name: string): boolean
	return type(name) == "string" and ANCHORS[name] ~= nil
end

-- Centre monde d'une prise de dalle (1 … 4, Config/Pads ; 5 = réservée)
function WorldLayout.padSocket(slot: number, socket: number): Vector3
	local p = PAD_SOCKETS[socket] or PAD_SOCKETS[1]
	if not validSlot(slot) then
		return p
	end
	return localToWorld(FRAMES[slot], p.X, p.Y, p.Z)
end

-- Emplacement de la décoration n° index (1 … 18)
function WorldLayout.decorSlot(slot: number, index: number): CFrame
	local p = DECOR_SLOTS[index] or DECOR_SLOTS[1]
	if not validSlot(slot) then
		return CFrame.new(p)
	end
	local f = FRAMES[slot]
	local pos = localToWorld(f, p.X, p.Y, p.Z)
	local face = localToWorld(f, DECOR_FACE.X, p.Y, DECOR_FACE.Z)
	return CFrame.lookAt(pos, face)
end

-- Place n° index (1 … 24) dans la zone d'enclos
function WorldLayout.penSlot(slot: number, index: number): Vector3
	local i = math.clamp(math.floor(finite(index, 1)), 1, #PEN_COLUMNS * #PEN_ROWS)
	local row = (i - 1) // #PEN_COLUMNS + 1
	local col = (i - 1) % #PEN_COLUMNS + 1
	local lx, lz = PEN_COLUMNS[col], PEN_ROWS[row]
	if not validSlot(slot) then
		return Vector3.new(lx, 0, lz)
	end
	return localToWorld(FRAMES[slot], lx, 0, lz)
end

-- Place flottante n° index (1 … 6) du Bassin
function WorldLayout.poolSlot(slot: number, index: number): Vector3
	local i = math.clamp(math.floor(finite(index, 1)), 1, 6)
	local angle = math.rad(90 + (i - 1) * 60)
	local center = ANCHORS.pool
	local lx = center.X + CONST.PoolSlotRadius * math.cos(angle)
	local lz = center.Z + CONST.PoolSlotRadius * math.sin(angle)
	if not validSlot(slot) then
		return Vector3.new(lx, 0, lz)
	end
	return localToWorld(FRAMES[slot], lx, 0, lz)
end

-- Place n° index (1 … 4) à la clôture, côté rue (Rush, pet-sitting)
function WorldLayout.fencePoint(slot: number, index: number): Vector3
	local p = FENCE_POINTS[math.clamp(math.floor(finite(index, 1)), 1, #FENCE_POINTS)]
	if not validSlot(slot) then
		return p
	end
	return localToWorld(FRAMES[slot], p.X, p.Y, p.Z)
end

-- Places à la clôture en repère local (ZoneRules)
function WorldLayout.fencePointsLocal(): { Vector3 }
	return table.clone(FENCE_POINTS)
end

-- Position d'un objet de la place (MEGA pad, statue, boutique, autel, jarre, scène, fontaine dorée, tableaux)
function WorldLayout.plaza(name: PlazaName): Vector3
	return PLAZA[name] or PLAZA.center
end

-- =============================================================================================
-- Graphe des rues (GDD §11.1) : anneau de la place (r = 50, tous les 45°), anneau intérieur
-- (r = 95, tous les 22,5°), boulevard (r = 166, tous les 11,25° : un nœud devant chaque portail),
-- 8 rues radiales (angles multiples de 45°) et la fontaine dorée de la place.
-- =============================================================================================

local NODES: { Vector3 } = {}
local NEIGHBORS: { { number } } = {}
local PLAZA_FIRST, INNER_FIRST, BOULEVARD_FIRST = 1, 9, 25
local FOUNTAIN_NODE = 57

local function polar(r: number, deg: number): Vector3
	local a = math.rad(deg)
	return Vector3.new(r * math.cos(a), 0, r * math.sin(a))
end

local function link(a: number, b: number)
	if not table.find(NEIGHBORS[a], b) then
		table.insert(NEIGHBORS[a], b)
	end
	if not table.find(NEIGHBORS[b], a) then
		table.insert(NEIGHBORS[b], a)
	end
end

do
	for i = 0, 7 do
		NODES[PLAZA_FIRST + i] = polar(CONST.PlazaRadius, 45 * i)
	end
	for i = 0, 15 do
		NODES[INNER_FIRST + i] = polar(CONST.InnerRing, 22.5 * i)
	end
	for i = 0, 31 do
		NODES[BOULEVARD_FIRST + i] = polar(CONST.Boulevard, 11.25 * i)
	end
	NODES[FOUNTAIN_NODE] = PLAZA.goldenFountain
	for i = 1, #NODES do
		NEIGHBORS[i] = {}
	end
	for i = 0, 7 do
		link(PLAZA_FIRST + i, PLAZA_FIRST + (i + 1) % 8)
		-- rue radiale : place → anneau intérieur → boulevard (même angle)
		link(PLAZA_FIRST + i, INNER_FIRST + 2 * i)
		link(INNER_FIRST + 2 * i, BOULEVARD_FIRST + 4 * i)
	end
	for i = 0, 15 do
		link(INNER_FIRST + i, INNER_FIRST + (i + 1) % 16)
	end
	for i = 0, 31 do
		link(BOULEVARD_FIRST + i, BOULEVARD_FIRST + (i + 1) % 32)
	end
	-- la fontaine dorée rejoint les trois nœuds les plus proches de l'anneau de la place
	link(FOUNTAIN_NODE, PLAZA_FIRST + 0) -- 0°
	link(FOUNTAIN_NODE, PLAZA_FIRST + 6) -- 270° (nord)
	link(FOUNTAIN_NODE, PLAZA_FIRST + 7) -- 315°
	for _, list in NEIGHBORS do
		table.sort(list)
	end
end

-- Coordonnées des nœuds en nombres simples (recherches rapides)
local NODE_X: { number } = {}
local NODE_Z: { number } = {}
for i, node in NODES do
	NODE_X[i] = node.X
	NODE_Z[i] = node.Z
end

-- Graphe des rues (nœuds et voisins) utilisé par SeededPath
function WorldLayout.graph(): Graph
	local neighbors = {}
	for i, list in NEIGHBORS do
		neighbors[i] = table.clone(list)
	end
	return { nodes = table.clone(NODES), neighbors = neighbors }
end

-- Lecture directe du graphe (sans copie) pour les modules purs du paquet (SeededPath) ; à ne jamais
-- modifier
function WorldLayout.graphView(): ({ Vector3 }, { { number } })
	return NODES, NEIGHBORS
end

-- Nœud du graphe le plus proche
function WorldLayout.nearestNode(pos: Vector3): number
	local p = saneVec(pos)
	local px, pz = p.X, p.Z
	local best, bestD = 1, math.huge
	for i = 1, #NODE_X do
		local dx, dz = NODE_X[i] - px, NODE_Z[i] - pz
		local d = dx * dx + dz * dz
		if d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- Nœud du boulevard devant le portail du ranch (départ des fuites du Rush)
function WorldLayout.fountainNode(slot: number): number
	if not validSlot(slot) then
		return BOULEVARD_FIRST + 1
	end
	-- ranch k à 11,25° + 22,5° × (k − 1) = nœud n° 2k − 1 du boulevard (pas de 11,25°)
	return BOULEVARD_FIRST + 2 * (slot - 1) + 1
end

-- Points de départ des Wild Wobblers (fontaine de la place, bouts des rues radiales)
function WorldLayout.wildSpawnNodes(): { number }
	local out = { FOUNTAIN_NODE }
	for i = 0, 7 do
		table.insert(out, BOULEVARD_FIRST + 4 * i)
	end
	return out
end

-- =============================================================================================
-- Solides et sol
-- =============================================================================================

-- Boîte verticale (rotation autour de Y seulement) précalculée pour les tests rapides
type Solid = {
	box: Box,
	cx: number,
	cz: number,
	ux: number, -- axe X de la boîte (monde)
	uz: number,
	hx: number, -- demi-tailles
	hz: number,
	bottom: number,
	top: number,
	reach: number, -- rayon englobant (XZ)
}

local SOLIDS: { Solid } = {}
local BOXES: { Box } = {}

-- Ajoute une boîte : centre (cx, cz), axe X (ux, uz), tailles, base y0 et hauteur h
local function addBox(
	cx: number,
	cz: number,
	ux: number,
	uz: number,
	sx: number,
	sz: number,
	y0: number,
	h: number
)
	local center = Vector3.new(cx, y0 + h / 2, cz)
	-- axes : X = (ux, 0, uz), Y = haut, Z = X × Y
	local xAxis = Vector3.new(ux, 0, uz)
	local zAxis = Vector3.new(-uz, 0, ux) -- (ux, 0, uz) × (0, 1, 0) = (−uz, 0, ux)
	local box: Box = table.freeze({
		cframe = CFrame.fromMatrix(center, xAxis, Vector3.new(0, 1, 0), zAxis),
		size = Vector3.new(sx, h, sz),
	})
	table.insert(BOXES, box)
	table.insert(SOLIDS, {
		box = box,
		cx = cx,
		cz = cz,
		ux = ux,
		uz = uz,
		hx = sx / 2,
		hz = sz / 2,
		bottom = y0,
		top = y0 + h,
		reach = math.sqrt(sx * sx + sz * sz) / 2,
	})
end

-- Boîte d'un ranch donnée par ses bornes locales (X de x0 à x1, Z de z0 à z1)
local function addRanchBox(f: Frame, x0: number, x1: number, z0: number, z1: number, h: number)
	local lx, lz = (x0 + x1) / 2, (z0 + z1) / 2
	local c = localToWorld(f, lx, 0, lz)
	addBox(c.X, c.Z, f.xx, f.xz, x1 - x0, z1 - z0, 0, h)
end

do
	local plate = CONST.WallRadius * 2
	addBox(0, 0, 1, 0, plate, plate, -CONST.PlateThickness, CONST.PlateThickness)

	-- murs des ranchs (à l'intérieur du rectangle)
	local t = CONST.FenceThickness
	local hw, depth, gate = HALF_WIDTH, CONST.RanchDepth, CONST.GateHalfWidth
	local h = CONST.FenceWallHeight
	for slot = 1, CONST.Ranches do
		local f = FRAMES[slot]
		addRanchBox(f, -hw, -hw + t, 0, depth, h) -- côté gauche (X −32)
		addRanchBox(f, hw - t, hw, 0, depth, h) -- côté droit (X +32)
		addRanchBox(f, -hw, hw, depth - t, depth, h) -- fond
		addRanchBox(f, -hw, -gate, 0, t, h) -- devant, à gauche du portail
		addRanchBox(f, gate, hw, 0, t, h) -- devant, à droite du portail
	end

	-- 24 maisons-bonbons : une par secteur intérieur (r ≈ 72,5) et deux par secteur extérieur
	-- (r ≈ 130), toujours entre les rues (au moins 10 studs de chaque rue)
	for i = 0, 7 do
		local a = math.rad(45 * i + 22.5)
		addBox(
			72.5 * math.cos(a),
			72.5 * math.sin(a),
			-math.sin(a),
			math.cos(a),
			14,
			14,
			0,
			CONST.HouseCapHeight
		)
		for _, offset in { 11.25, 33.75 } do
			local b = math.rad(45 * i + offset)
			addBox(
				130 * math.cos(b),
				130 * math.sin(b),
				-math.sin(b),
				math.cos(b),
				16,
				16,
				0,
				CONST.HouseCapHeight
			)
		end
	end

	-- mur du bord : segments tangents dont la face intérieure est sur le cercle r = 322
	local n = CONST.EdgeSegments
	local thick = CONST.EdgeThickness
	local length = 2 * CONST.WallRadius * math.tan(math.pi / n) + 2 * thick
	for i = 0, n - 1 do
		local a = 2 * math.pi * i / n
		local r = CONST.WallRadius + thick / 2
		-- axe X de la boîte = tangente (−sin a, cos a)
		addBox(
			r * math.cos(a),
			r * math.sin(a),
			-math.sin(a),
			math.cos(a),
			length,
			thick,
			0,
			CONST.EdgeWallHeight
		)
	end
end

-- Boîtes solides (maisons avec leur coiffe invisible, clôtures et leurs murs invisibles, bord du
-- plateau) ; chaque boîte mesure au moins Const.SolidMinHeight de haut, sauf la première (le plateau)
function WorldLayout.solids(): { Box }
	return table.clone(BOXES)
end

-- Lecture directe des solides précalculés pour les modules purs du paquet (LeapRules, SeededPath) ;
-- à ne jamais modifier
function WorldLayout.solidsView(): { any }
	return SOLIDS
end

-- Le point (x, z) est dans l'emprise de la boîte, agrandie de `margin`
local function footprintContains(s: Solid, x: number, z: number, margin: number): boolean
	local dx, dz = x - s.cx, z - s.cz
	if dx * dx + dz * dz > (s.reach + margin) * (s.reach + margin) then
		return false
	end
	local lx = dx * s.ux + dz * s.uz
	local lz = dx * -s.uz + dz * s.ux
	return math.abs(lx) <= s.hx + margin and math.abs(lz) <= s.hz + margin
end

-- Point (x, z) dans l'emprise d'un solide qui dépasse du sol (plateau exclu), agrandie de `margin`
function WorldLayout.blocked(x: number, z: number, margin: number?): boolean
	local m = finite(margin, 0)
	local px, pz = finite(x, 0), finite(z, 0)
	for i = 2, #SOLIDS do
		if footprintContains(SOLIDS[i], px, pz, m) then
			return true
		end
	end
	return false
end

-- Surface analytique du sol (MoveCheck.setSurface) : plat (Y = 0) jusqu'au mur du bord, collines
-- douces au-delà (jamais atteintes par un joueur)
function WorldLayout.groundY(x: number, z: number): number
	local px, pz = finite(x, 0), finite(z, 0)
	local r = math.sqrt(px * px + pz * pz)
	if r <= CONST.WallRadius then
		return 0
	end
	local hill = (r - CONST.WallRadius) / (CONST.HillsRadius - CONST.WallRadius)
	return 30 * math.clamp(hill, 0, 1)
end

-- Hauteur du support sous une position (règles du serveur, MoveCheck) : max(groundY(x, z), haut de
-- chaque boîte de solids() dont l'emprise XZ contient la position). Pur : jamais de Blockcast ni de
-- Raycast pour une règle.
function WorldLayout.supportY(pos: Vector3): number
	local p = saneVec(pos)
	local y = WorldLayout.groundY(p.X, p.Z)
	for _, s in SOLIDS do
		if s.top > y and footprintContains(s, p.X, p.Z, 0) then
			y = s.top
		end
	end
	return y
end

-- =============================================================================================
-- Monde v2.0 (lot B4, GDD v2.0 §11.1, §11.2, §11.5 ; docs/04 §27.14 ; décisions D8, D9 du plan B4).
-- Ajouts seulement : aucune position de la v1.3 ne change. Rien ici n'est construit par le serveur ;
-- le client dessine ces décors derrière leurs interrupteurs (RanchTiers, Monuments, DecoPerso,
-- Workshop). Règle de placement (WorldLayout.spec, Props_WorldLayout.spec, pour les 16 ranchs) :
-- une emprise v2 au sol (bas < V2Elevated) est à ≥ 8 studs du centre de chaque dalle, hors des
-- enclos (X −27 … 27, Z 12 … 44) et du chemin du portail (|X| ≤ 5, Z −6 … 12), sans chevaucher les 18
-- décorations, les objets de la v1.3 ni une autre emprise v2 ; rien de la v2 au-dessus de Y = 21 dans
-- la colonne du centre (silhouette du meilleur squishy), sauf ses accessoires (cadre doré).
-- =============================================================================================

-- Place n° index (1 … 12) dans la Prairie des copains ; v2 = true : la Prairie v2 (jardin du quartier
-- nord, D9) ; sans second argument, la Prairie de la v1.3, inchangée
function WorldLayout.meadowPoint(index: number, v2: boolean?): Vector3
	local i = math.clamp(math.floor(finite(index, 1)), 1, 12)
	local a = math.rad(30 * (i - 1))
	if v2 == true then
		local spread = CONST.MeadowV2Spread * (if i % 2 == 0 then 1 else 0.55)
		return MEADOW_V2_CENTER + Vector3.new(spread * math.cos(a), 0, spread * math.sin(a))
	end
	local spread = CONST.MeadowSpread * (if i % 2 == 0 then 1 else 0.55)
	return MEADOW_CENTER + Vector3.new(spread * math.cos(a), 0, spread * math.sin(a))
end

-- Centre de la Prairie des copains : v1.3 (0, 0, −284) sans argument ; v2 = true : le jardin du
-- quartier nord (r ≈ 145, 291°), libre de toute maison, rue, sucette, buisson, lampadaire et plaque
-- de sucre glace (WorldLayout.spec)
function WorldLayout.meadowCenter(v2: boolean?): Vector3
	return if v2 == true then MEADOW_V2_CENTER else MEADOW_CENTER
end

-- Monuments : 10 emplacements fixes derrière le fond, hors clôture (GDD §11.5) : n° 1 … 5 à Z = 88,
-- n° 6 … 10 à Z = 116, X = −36, −18, 0, +18, +36 ; tournés comme le ranch (LookVector vers la place)
local MONUMENT_X = { -36, -18, 0, 18, 36 }
local MONUMENT_Z = { 88, 116 }

local function monumentLocal(n: number): Vector3
	local i = math.clamp(math.floor(finite(n, 1)), 1, 2 * #MONUMENT_X)
	local row = (i - 1) // #MONUMENT_X + 1
	local col = (i - 1) % #MONUMENT_X + 1
	return Vector3.new(MONUMENT_X[col], 0, MONUMENT_Z[row])
end

-- Repère monde de l'emplacement du Monument n° n (1 … 10)
function WorldLayout.monumentSlot(slot: number, n: number): CFrame
	local p = monumentLocal(n)
	if not validSlot(slot) then
		return CFrame.new(p)
	end
	return FRAMES[slot].cframe * CFrame.new(p.X, p.Y, p.Z)
end

-- 12 emplacements de Déco perso (repère local) : 1 … 8 petits « P », 9 … 12 grands « G »
-- (Cosmetics.DecoSlots), le long du chemin du portail, autour des enclos et devant la rangée des
-- dalles ; chacun respecte la règle de placement (marges calculées par WorldLayout.spec)
local DECO_PERSO: { DecoSlotDef } = {
	{ position = Vector3.new(-7, 0, 9.5), size = "P" },
	{ position = Vector3.new(7, 0, 9.5), size = "P" },
	{ position = Vector3.new(0, 0, 58.75), size = "P" },
	{ position = Vector3.new(17.25, 0, 55.75), size = "P" },
	{ position = Vector3.new(27, 0, 61.25), size = "P" },
	{ position = Vector3.new(-23.25, 0, 57.75), size = "P" },
	{ position = Vector3.new(-23.75, 0, 46.75), size = "P" },
	{ position = Vector3.new(21.25, 0, 46.75), size = "P" },
	{ position = Vector3.new(19.5, 0, 5), size = "G" },
	{ position = Vector3.new(23.5, 0, 52), size = "G" },
	{ position = Vector3.new(-4, 0, 55), size = "G" },
	{ position = Vector3.new(-14, 0, 47.5), size = "G" },
}

-- Emplacements de Déco perso en repère local, avec leur taille (plan vu du dessus de Mon style) : copie
function WorldLayout.decoPersoSlots(): { DecoSlotDef }
	local out: { DecoSlotDef } = {}
	for i, def in DECO_PERSO do
		out[i] = { position = def.position, size = def.size }
	end
	return out
end

-- Repère monde de l'emplacement de Déco perso n° i (1 … 12), tourné vers le milieu des enclos
function WorldLayout.decoPersoSlot(slot: number, index: number): CFrame
	local def = DECO_PERSO[math.clamp(math.floor(finite(index, 1)), 1, #DECO_PERSO)]
	local p = def.position
	if not validSlot(slot) then
		return CFrame.new(p)
	end
	local f = FRAMES[slot]
	local pos = localToWorld(f, p.X, p.Y, p.Z)
	local face = localToWorld(f, DECOR_FACE.X, p.Y, DECOR_FACE.Z)
	return CFrame.lookAt(pos, face)
end

-- Points des décors v2 du ranch (repère local ; GDD §11.5) : base de chaque palier, du geyser, des
-- lampions (dessus des poteaux de la clôture), centre du cadre doré (silhouette) et bas du ciel
local V2_ANCHORS: { [string]: Vector3 } = {
	arch = Vector3.new(0, 9, 0.5), -- Arche à pompons, Y 9 à 13, posée sur les poteaux du portail
	tower = Vector3.new(-30, 0, 76), -- Tour à bonbons, coin arrière gauche, hors clôture
	balcony = Vector3.new(0, 0, 76), -- Balcon de gelée (plancher à Y 10 à 14), derrière l'étagère
	lighthouse = Vector3.new(30, 0, 76), -- Phare de gelée, coin arrière droit, hors clôture
	dome = Vector3.new(0, 16, 70), -- Dôme néon au-dessus de l'étagère
	crown = Vector3.new(0, 18, 0), -- Couronne flottante au-dessus du panneau du portail
	geyser = Vector3.new(-24, 0, 9.5), -- Geyser de gelée (Record R 17), Z 4 à 10, X −24
	frame = Vector3.new(0, 40, 36), -- cadre doré (Record R 18) autour de la silhouette
	lantern1 = Vector3.new(-24.75, 4.4, 0.5), -- 8 lampions (Record R 12) sur les poteaux
	lantern2 = Vector3.new(-18, 4.4, 0.5),
	lantern3 = Vector3.new(18, 4.4, 0.5),
	lantern4 = Vector3.new(24.75, 4.4, 0.5),
	lantern5 = Vector3.new(-31.5, 4.4, 71 / 9 + 0.5),
	lantern6 = Vector3.new(31.5, 4.4, 71 / 9 + 0.5),
	lantern7 = Vector3.new(-31.5, 4.4, 71 * 8 / 9 + 0.5),
	lantern8 = Vector3.new(31.5, 4.4, 71 * 8 / 9 + 0.5),
	sky = Vector3.new(0, 34, 84), -- élément de ciel (Ascensions) au-dessus du fond, au-dessus des Monuments
}

-- Le nom désigne un décor v2 du ranch
function WorldLayout.hasV2Anchor(name: string): boolean
	return type(name) == "string" and V2_ANCHORS[name] ~= nil
end

-- Repère monde d'un décor v2 du ranch (tourné comme le ranch : LookVector vers la place) ; nom
-- inconnu : le portail
function WorldLayout.v2Anchor(slot: number, name: V2Anchor): CFrame
	local p = if type(name) == "string" then V2_ANCHORS[name] else nil
	local q = p or Vector3.zero
	if not validSlot(slot) then
		return CFrame.new(q)
	end
	return FRAMES[slot].cframe * CFrame.new(q.X, q.Y, q.Z)
end

-- Maisonnette des Plopettes (Record R 2) : son point devant la porte, en monde (GDD §11.2 : Z = 60,
-- X = −28), exactement le repli de HelperService (A3) ; la cabane (6 pièces) se tient juste derrière
function WorldLayout.helperHouse(slot: number): Vector3
	return WorldLayout.toWorld(slot, Vector3.new(-28, 0, 60))
end

-- Observatoire (colline nord, r ≈ 340, au-delà du mur du bord : inaccessible) : repère au sol de la
-- colline, tourné vers la place
function WorldLayout.observatory(): CFrame
	local r = CONST.ObservatoryRadius
	local y = WorldLayout.groundY(0, -r)
	return CFrame.lookAt(Vector3.new(0, y, -r), Vector3.new(0, y, 0))
end

-- Colonne du centre d'un ranch (repère local) : la silhouette du meilleur squishy (centre (0, 40, 36),
-- rayon d'affichage ≤ SilhouetteRadius) ne traverse rien ; aucun décor v2 au-dessus de `floor` dans
-- le cylindre de rayon `radius` autour de `center`, sauf les accessoires de la silhouette
local COLUMN: Column = table.freeze({
	center = Vector3.new(ANCHORS.silhouette.X, 0, ANCHORS.silhouette.Z),
	radius = CONST.SilhouetteRadius + CONST.CenterColumnMargin,
	floor = ANCHORS.silhouette.Y - CONST.SilhouetteRadius,
})

function WorldLayout.centerColumn(): Column
	return COLUMN
end

-- Emprises v2 du ranch (repère local), construites une fois
local FOOTPRINTS: { Footprint } = {}

local function addFootprint(f: { [string]: any })
	table.insert(
		FOOTPRINTS,
		table.freeze({
			name = f.name,
			kind = f.kind,
			x = f.x or 0,
			z = f.z or 0,
			r = f.r or 0,
			x0 = f.x0 or 0,
			x1 = f.x1 or 0,
			z0 = f.z0 or 0,
			z1 = f.z1 or 0,
			bottom = f.bottom or 0,
			top = f.top or 0,
			accessory = f.accessory == true,
			fence = f.fence == true,
			outside = f.outside == true,
		}) :: any
	)
end

local function discAt(
	name: string,
	p: Vector3,
	r: number,
	bottom: number,
	top: number,
	extra: { [string]: any }?
)
	local f: { [string]: any } =
		{ name = name, kind = "disc", x = p.X, z = p.Z, r = r, bottom = bottom, top = top }
	if extra then
		for k, v in extra do
			f[k] = v
		end
	end
	addFootprint(f)
end

do
	local A = V2_ANCHORS
	addFootprint({
		name = "arch",
		kind = "box",
		x0 = -5.5,
		x1 = 5.5,
		z0 = -0.5,
		z1 = 1.5,
		bottom = 9,
		top = 13,
	})
	discAt("tower", A.tower, 2.5, 0, 19, { outside = true })
	addFootprint({
		name = "balcony",
		kind = "box",
		x0 = -10,
		x1 = 10,
		z0 = 75,
		z1 = 77,
		bottom = 0,
		top = 14,
		outside = true,
	})
	discAt("lighthouse", A.lighthouse, 2.5, 0, 24, { outside = true })
	discAt("dome", A.dome, 6, 16, 22)
	discAt("crown", A.crown, 2.5, 17, 22)
	discAt("geyser", A.geyser, 1, 0, 8)
	discAt(
		"frame",
		A.frame,
		CONST.SilhouetteRadius + 2,
		A.frame.Y - CONST.SilhouetteRadius - 2,
		A.frame.Y + 21,
		{
			accessory = true,
		}
	)
	for i = 1, 8 do
		local p = A["lantern" .. i]
		discAt("lantern" .. i, p, 0.7, p.Y, p.Y + 1.4, { fence = true })
	end
	discAt("sky", A.sky, 12, A.sky.Y, A.sky.Y + 14, { outside = true })
	addFootprint({
		name = "house",
		kind = "box",
		x0 = -29.75,
		x1 = -26.25,
		z0 = 61,
		z1 = 64,
		bottom = 0,
		top = 5,
	})
	for n = 1, 2 * #MONUMENT_X do
		discAt(
			"monument" .. n,
			monumentLocal(n),
			CONST.MonumentRadius,
			0,
			CONST.MonumentTop,
			{ outside = true }
		)
	end
	for i, def in DECO_PERSO do
		local large = def.size == "G"
		discAt(
			"deco" .. i,
			def.position,
			if large then CONST.DecoLargeRadius else CONST.DecoSmallRadius,
			0,
			if large then 4.5 else 2.5
		)
	end
end

-- Emprises de tous les décors v2 d'un ranch (repère local, lecture seule)
function WorldLayout.v2Footprints(): { Footprint }
	return table.clone(FOOTPRINTS)
end

return WorldLayout
