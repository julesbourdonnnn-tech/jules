--!strict
-- RanchLook (lot B4, docs/04 §27.7, GDD v2.0 §4.27, §4.29, §11.2, §11.5 ; décisions D6, D7, D11, D14,
-- D18 du plan B4). Règles PURES de l'aspect du ranch qui évolue, lues par le client (RanchRenderer et ses
-- modules de rendu) : rien n'est dessiné ici, rien n'est lu dans le workspace, jamais d'erreur. Toute
-- entrée est validée (type, fini, bornes, identifiant connu) ; une valeur illisible donne l'aspect sûr
-- par défaut.
--   * elements(bestR, A) : identifiants des éléments visibles (Visuals.RecordTable[1 … min(bestR, 20)]
--     .ranch sans doublon, dans l'ordre de la table, puis étoiles et couronne arc-en-ciel, puis ciel) ;
--   * tier, vat, potMaterial, potState, tapisTier, tapisShade, decorState, pennants, cushions, halo, sky :
--     un axe chacun ;
--   * skin(id) : ligne d'aspect d'un des 14 habillages (cosmetics.theme) ; les 3 de la v1.3 rendent
--     exactement l'aspect d'aujourd'hui (teinte de la clôture seulement pour moonlit et candyNight) ;
--   * decoPerso(attr) : les 12 numéros sûrs de l'attribut DecoPerso ;
--   * currentRanch, detail : niveau de détail par ranch, jamais par distance (D6) ;
--   * padLabel : copie client de Server/Ranch/PadRules (visible / target / progress) pour la dalle du
--     Tapis au-delà du Tapis 12 (Tapis Étoilé, D11), comparée à PadRules par RanchLook.spec.
-- r, Record R et A passent par Logic/Prestige (jamais une lecture directe du champ du profil).

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, typeof, math, string, table, tonumber = type, typeof, math, string, table, tonumber

local Balance = require(script.Parent.Parent.Config.Balance)
local Visuals = require(script.Parent.Parent.Config.Visuals)
local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)
local Prestige = require(script.Parent.Prestige)
local UpgradeMath = require(script.Parent.UpgradeMath)
local WorldLayout = require(script.Parent.WorldLayout)

export type VatLook = {
	rings: number, -- anneaux lumineux 1 … 8 (qualité de la Cuve)
	nozzles: number, -- buses 0 … 5
	stirrerPeriod: number, -- secondes par tour de l'agitateur (4, 2, puis 1)
	rainbow: boolean, -- agitateur arc-en-ciel (Record R 4)
	golden: boolean, -- Cuve dorée (Record R 7, 8e anneau)
}
-- Ligne d'aspect d'un habillage : champs absents = aspect d'origine de la pièce ; matériaux par nom
-- (Enum.Material.<nom>, résolu par le client)
export type SkinLook = {
	fence: Color3?,
	fenceMaterial: string?,
	floor: Color3?,
	floorMaterial: string?,
	gate: Color3?,
}
-- Étiquette de la dalle du Tapis au-delà du Tapis 12 (Tapis Étoilé)
export type PadLabel = {
	star: boolean, -- la dalle achète le Tapis Étoilé (Tapis 12 acheté, StarMat, profil v2) : PadRules.target
	lit: boolean, -- dalle allumée (un niveau du Tapis Étoilé est ouvert dans cette boucle) : PadRules.visible
	level: number, -- niveau affiché 13 … 20 (PadRules.progress + 1) ; 0 si éteinte ou pas le Tapis Étoilé
	price: number, -- prix du prochain niveau (UpgradeMath.price("star", …)) ; math.huge si éteinte
}

local RanchLook = {}

local MAX_R = Balance.Prestige.MaxR
local MAX_A = Balance.Prestige.MaxA
local RANCHES = WorldLayout.Const.Ranches
local SNACK_MAX = Balance.Tiles.snack.Levels
local DECOR_MAX = Balance.Tiles.decor.Levels
local PEN_PLACES = 24 -- places d'enclos (WorldLayout.penSlot : 4 rangées de 6)
local TAPIS_MAX = SNACK_MAX + UpgradeMath.maxLevel("star") -- Tapis 12 + Tapis Étoilé 8 = 20

-- Agitateur de la Cuve (GDD §11.5 : 4 s à la vitesse 3, 1 s à la vitesse 10) : la table du §4.29 ne le
-- change qu'au Record R 2 (« plus rapide ») et au Record R 4 (arc-en-ciel, vitesse maximale)
local STIRRER_SLOW, STIRRER_FAST, STIRRER_RAINBOW = 4, 2, 1
local STIRRER_FAST_AT = 2
-- Tapis : chaque niveau éclaircit la couleur de 8 % dans son palier (GDD §11.5)
local SHADE_STEP = 0.08
-- Pot : secondes de revenu contenues → 4 tas (GDD §11.5)
local POT_SMALL, POT_BIG, POT_FULL = 30, 120, 600
-- Ranch courant : il ne change qu'à 10 studs au moins à l'intérieur d'un autre ranch (GDD §11.5)
local DETAIL_DEPTH = 10

-- Entier de [lo ; hi] (NaN, ±inf, mauvais type → lo)
local function int(x: any, lo: number, hi: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return lo
	end
	return math.clamp(math.floor(x), lo, hi)
end

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function validSlot(slot: any): boolean
	return type(slot) == "number" and slot == slot and slot % 1 == 0 and slot >= 1 and slot <= RANCHES
end

-- =============================================================================================
-- Table du Record R (Visuals.RecordTable, lue une fois)
-- =============================================================================================

-- Premier Record R de chaque identifiant, et identifiants dans l'ordre de la table, sans doublon
local FIRST_R: { [string]: number } = {}
local ORDERED: { string } = {}
for R = 1, #Visuals.RecordTable do
	local row = Visuals.RecordTable[R]
	for _, id in (if row then row.ranch else {}) :: { string } do
		if FIRST_R[id] == nil then
			FIRST_R[id] = R
			table.insert(ORDERED, id)
		end
	end
end

-- Record R d'un identifiant (math.huge : jamais dans la table)
local function firstR(id: string): number
	return FIRST_R[id] or math.huge
end

local RING_AT: { [number]: number } = {}
local NOZZLE_AT: { [number]: number } = {}
for id, R in FIRST_R do
	local ring = string.match(id, "^vat%.ring(%d+)$")
	if ring then
		RING_AT[tonumber(ring) :: number] = R
	end
	local nozzle = string.match(id, "^vat%.nozzle(%d+)$")
	if nozzle then
		NOZZLE_AT[tonumber(nozzle) :: number] = R
	end
end

-- Identifiants construits une fois (aucune concaténation à chaque appel)
local CROWN_STARS: { string } = {}
for k in Visuals.CrownStarsAt do
	CROWN_STARS[k] = "crown.star" .. k
end
local SKY_IDS: { string } = {}
for n = 1, Visuals.SkyNamed do
	SKY_IDS[n] = "sky." .. n
end

-- Éléments visibles d'un ranch au Record R `bestR` et à A Ascensions (GDD §4.29, §11.5, §4.27)
function RanchLook.elements(bestR: any, A: any): { string }
	local r = int(bestR, 0, MAX_R)
	local a = int(A, 0, MAX_A)
	local out: { string } = {}
	for _, id in ORDERED do
		if FIRST_R[id] <= r then
			table.insert(out, id)
		end
	end
	for k, at in Visuals.CrownStarsAt do
		if r >= at then
			table.insert(out, CROWN_STARS[k])
		end
	end
	if r >= Visuals.RainbowCrownAt then
		table.insert(out, "crown.rainbow")
	end
	if a >= 1 then
		table.insert(out, SKY_IDS[math.min(a, Visuals.SkyNamed)])
		if a > Visuals.SkyNamed then
			table.insert(out, "sky.stars")
		end
	end
	return out
end

-- Palier du ranch 0 … 6 (Visuals.RanchTiersAt : arche, tour, balcon, phare, dôme, couronne)
function RanchLook.tier(bestR: any): number
	local r = int(bestR, 0, MAX_R)
	local n = 0
	for _, at in Visuals.RanchTiersAt do
		if r >= at then
			n += 1
		end
	end
	return n
end

-- Les 3 axes de la Cuve (anneaux, buses, agitateur) et sa forme dorée (GDD §11.5, §4.29)
function RanchLook.vat(bestR: any): VatLook
	local r = int(bestR, 0, MAX_R)
	local rings, nozzles = 1, 0
	for n, at in RING_AT do
		if at <= r and n > rings then
			rings = n
		end
	end
	for n, at in NOZZLE_AT do
		if at <= r and n > nozzles then
			nozzles = n
		end
	end
	local golden = r >= firstR("vat.golden")
	if golden then
		rings = 8
	end
	local rainbow = r >= firstR("vat.rainbowStirrer")
	local period = if rainbow
		then STIRRER_RAINBOW
		elseif r >= STIRRER_FAST_AT then STIRRER_FAST
		else STIRRER_SLOW
	return {
		rings = math.clamp(rings, 1, 8),
		nozzles = math.clamp(nozzles, 0, 5),
		stirrerPeriod = period,
		rainbow = rainbow,
		golden = golden,
	}
end

-- Matériau du Pot : cuivre, argent (R2), doré (R6), cristal (R16)
function RanchLook.potMaterial(bestR: any): string
	local r = int(bestR, 0, MAX_R)
	if r >= firstR("pot.crystal") then
		return "crystal"
	elseif r >= firstR("pot.gold") then
		return "gold"
	elseif r >= firstR("pot.silver") then
		return "silver"
	end
	return "copper"
end

-- Tas de pièces du Pot selon les secondes de revenu qu'il contient : 0 vide (< 30 s), 1 petit
-- (30 s à 2 min), 2 gros (2 à 10 min), 3 déborde (> 10 min) ; illisible → vide
function RanchLook.potState(seconds: any): number
	if not finite(seconds) or seconds < POT_SMALL then
		return 0
	elseif seconds < POT_BIG then
		return 1
	elseif seconds <= POT_FULL then
		return 2
	end
	return 3
end

-- Palier du Tapis 0 … 6 pour un niveau 0 … 20 (Visuals.Tiers.snack : 1, 4, 7, 10, 13, 17)
function RanchLook.tapisTier(level: any): number
	local l = int(level, 0, TAPIS_MAX)
	local n = 0
	for _, at in Visuals.Tiers.snack do
		if l >= at then
			n += 1
		end
	end
	return n
end

-- Éclaircissement de la couleur du Tapis dans son palier : 0,08 par niveau au-dessus du premier
-- niveau du palier (0 … 0,24) ; 0 sans Tapis
function RanchLook.tapisShade(level: any): number
	local l = int(level, 0, TAPIS_MAX)
	local tier = RanchLook.tapisTier(l)
	if tier == 0 then
		return 0
	end
	return SHADE_STEP * (l - Visuals.Tiers.snack[tier])
end

-- Décoration n° k : « built » si tiles.decor ≥ k (construite par le serveur), sinon « plinth » (socle
-- de souvenir) dès que le ranch a fait un Grand Splorch (Record R ≥ 1), sinon « none » (un ranch qui
-- n'a jamais fait de Grand Splorch n'a pas de souvenir, D18) ; jamais deux états à la fois
function RanchLook.decorState(k: any, decorLevel: any, bestR: any): string
	if not finite(k) or k < 1 or k >= DECOR_MAX + 1 then
		return "none" -- pas une décoration (1 … 18)
	end
	local index = math.floor(k)
	if int(decorLevel, 0, DECOR_MAX) >= index then
		return "built"
	end
	if int(bestR, 0, MAX_R) >= 1 then
		return "plinth"
	end
	return "none"
end

-- Fanions ★ sur les décorations gardées : 0, 3 (Record R 8), 6 (Record R 14)
function RanchLook.pennants(bestR: any): number
	local r = int(bestR, 0, MAX_R)
	if r >= firstR("decor.pennants6") then
		return 6
	elseif r >= firstR("decor.pennants3") then
		return 3
	end
	return 0
end

-- Coussins ronds de l'enclos : un par place achetée (`pens`) et par place offerte (`offered`), au plus
-- une par place d'enclos (24)
function RanchLook.cushions(pens: any, offered: any): number
	return math.min(PEN_PLACES, int(pens, 0, PEN_PLACES) + int(offered, 0, PEN_PLACES))
end

-- Gouttes du halo : min(A, 5) quand le joueur l'a gardé allumé (HaloOn), sinon 0
function RanchLook.halo(A: any, haloOn: any): number
	if haloOn ~= true then
		return 0
	end
	return math.min(int(A, 0, MAX_A), #Visuals.Halo)
end

-- Ciel des Ascensions : (clé de l'élément, nombre d'étoiles) ; A1 … A10 nommés (sky.1 … sky.10), puis
-- une étoile par Ascension de A11 à A20 sur la Constellation ; (nil, 0) sans Ascension
function RanchLook.sky(A: any): (string?, number)
	local a = int(A, 0, MAX_A)
	if a < 1 then
		return nil, 0
	end
	local stars = if a > Visuals.SkyNamed then math.min(a, Visuals.SkyMaxStars) else 0
	return SKY_IDS[math.min(a, Visuals.SkyNamed)], stars
end

-- =============================================================================================
-- Habillages (14 valeurs de cosmetics.theme, GDD §11.5, Annexe B.3)
-- =============================================================================================

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Matériaux permis sur les pièces habillées (aucune transparence nouvelle, jamais Glass)
RanchLook.SKIN_MATERIALS = table.freeze({ "SmoothPlastic", "Neon", "Foil", "Ice", "Sand" }) :: { string }

local SKIN_ROWS: { [string]: SkinLook } = {
	-- v1.3, inchangés : la couleur du ranch ne change rien ; Moonlit et Candy Night teintent la clôture
	-- (exactement THEME_COLORS de RanchRenderer, RanchLook.spec)
	color = table.freeze({}),
	moonlit = table.freeze({ fence = rgb(90, 100, 170) }),
	candyNight = table.freeze({ fence = rgb(150, 90, 170) }),
	-- v2.0 (11) : pastels lisibles sur une télé, la clôture contraste avec le sol
	marshmallow = table.freeze({
		fence = rgb(255, 222, 234),
		fenceMaterial = "SmoothPlastic",
		floor = rgb(255, 242, 247),
		floorMaterial = "Sand",
		gate = rgb(255, 186, 214),
	}),
	caramel = table.freeze({
		fence = rgb(210, 140, 80),
		fenceMaterial = "SmoothPlastic",
		floor = rgb(246, 220, 180),
		floorMaterial = "SmoothPlastic",
		gate = rgb(235, 165, 85),
	}),
	icedMint = table.freeze({
		fence = rgb(150, 228, 205),
		fenceMaterial = "Ice",
		floor = rgb(220, 250, 238),
		floorMaterial = "SmoothPlastic",
		gate = rgb(120, 220, 195),
	}),
	lighthouse = table.freeze({
		fence = rgb(245, 110, 110),
		fenceMaterial = "SmoothPlastic",
		floor = rgb(238, 246, 255),
		floorMaterial = "SmoothPlastic",
		gate = rgb(255, 215, 110),
	}),
	sugarGlacier = table.freeze({
		fence = rgb(185, 220, 255),
		fenceMaterial = "Ice",
		floor = rgb(232, 244, 255),
		floorMaterial = "Sand",
		gate = rgb(150, 200, 255),
	}),
	neon = table.freeze({
		fence = rgb(255, 120, 215),
		fenceMaterial = "Neon",
		floor = rgb(236, 226, 255),
		floorMaterial = "SmoothPlastic",
		gate = rgb(110, 235, 255),
	}),
	sugarCosmos = table.freeze({
		fence = rgb(150, 130, 230),
		fenceMaterial = "SmoothPlastic",
		floor = rgb(80, 80, 140),
		floorMaterial = "SmoothPlastic",
		gate = rgb(205, 175, 255),
	}),
	royal = table.freeze({
		fence = rgb(255, 205, 90),
		fenceMaterial = "Foil",
		floor = rgb(225, 100, 130),
		floorMaterial = "SmoothPlastic",
		gate = rgb(255, 225, 130),
	}),
	cloud = table.freeze({
		fence = rgb(250, 250, 255),
		fenceMaterial = "SmoothPlastic",
		floor = rgb(225, 238, 255),
		floorMaterial = "Sand",
		gate = rgb(185, 215, 255),
	}),
	aurora = table.freeze({
		fence = rgb(130, 225, 185),
		fenceMaterial = "SmoothPlastic",
		floor = rgb(228, 216, 250),
		floorMaterial = "SmoothPlastic",
		gate = rgb(255, 165, 215),
	}),
	celestial = table.freeze({
		fence = rgb(255, 228, 150),
		fenceMaterial = "Foil",
		floor = rgb(214, 224, 255),
		floorMaterial = "SmoothPlastic",
		gate = rgb(255, 248, 205),
	}),
}

-- Les 14 identifiants, dans l'ordre de l'Annexe B.3
RanchLook.SKINS = table.freeze({
	"color",
	"moonlit",
	"candyNight",
	"marshmallow",
	"caramel",
	"icedMint",
	"lighthouse",
	"sugarGlacier",
	"neon",
	"sugarCosmos",
	"royal",
	"cloud",
	"aurora",
	"celestial",
}) :: { string }

-- Ligne d'aspect d'un habillage (lecture seule) ; identifiant inconnu → nil (aspect par défaut)
function RanchLook.skin(id: any): SkinLook?
	if type(id) ~= "string" then
		return nil
	end
	return SKIN_ROWS[id]
end

-- =============================================================================================
-- Déco perso (attribut DecoPerso : 12 numéros séparés par des virgules, 0 = vide)
-- =============================================================================================

local DECO_SLOTS = #Cosmetics.DecoSlots
local DECO_ITEMS = #Cosmetics.DecoPerso
local DECO_ATTR_MAX = 64 -- caractères au plus (12 × 2 chiffres + 11 virgules = 35)

-- Les 12 numéros d'objet sûrs : un numéro inconnu, illisible, posé sur un emplacement d'une autre
-- taille ou déjà posé ailleurs (un objet n'occupe qu'un emplacement) vaut 0 ; une chaîne illisible
-- donne 12 zéros
function RanchLook.decoPerso(attr: any): { number }
	local out = table.create(DECO_SLOTS, 0)
	if type(attr) ~= "string" or #attr > DECO_ATTR_MAX then
		return out
	end
	local used: { [number]: boolean } = {}
	local i = 0
	for token in string.gmatch(attr .. ",", "([^,]*),") do
		i += 1
		if i > DECO_SLOTS then
			break
		end
		local n = if string.match(token, "^%d%d?$") then tonumber(token) else nil
		local def = if n then Cosmetics.DecoPerso[n] else nil
		if
			n
			and n >= 1
			and n <= DECO_ITEMS
			and def
			and def.size == Cosmetics.DecoSlots[i]
			and not used[n]
		then
			out[i] = n
			used[n] = true
		end
	end
	return out
end

-- =============================================================================================
-- Niveau de détail par ranch (D6) : jamais par distance
-- =============================================================================================

-- Ranch courant : celui où se tient le personnage, seulement quand il est à 10 studs au moins à
-- l'intérieur ; plus près du bord d'un ranch, le précédent reste ; sur la place, dans les rues ou sans
-- personnage, son propre ranch (0 s'il n'en a pas)
function RanchLook.currentRanch(prev: any, mySlot: any, position: any): number
	local own = if validSlot(mySlot) then mySlot :: number else 0
	if typeof(position) ~= "Vector3" then
		return own
	end
	local slot = WorldLayout.ranchAt(position)
	if slot == 0 then
		return own
	end
	local l = WorldLayout.toLocal(slot, position)
	local half = WorldLayout.Const.RanchWidth / 2
	local depth = math.min(l.X + half, half - l.X, l.Z, WorldLayout.Const.RanchDepth - l.Z)
	if depth >= DETAIL_DEPTH then
		return slot
	end
	if validSlot(prev) then
		return prev :: number
	end
	return own
end

-- Détail d'un ranch : « full » pour le ranch courant et ses 2 voisins (mod 16), sinon « reduced »
function RanchLook.detail(slot: any, current: any): string
	if not validSlot(slot) or not validSlot(current) then
		return "reduced"
	end
	local d = ((slot :: number) - (current :: number)) % RANCHES
	return if d == 0 or d == 1 or d == RANCHES - 1 then "full" else "reduced"
end

-- =============================================================================================
-- Dalle du Tapis au-delà du Tapis 12 (Tapis Étoilé, D11) : copie client de Server/Ranch/PadRules
-- =============================================================================================

-- Valeur d'un interrupteur dans `flags` (table de valeurs ou module avec get, comme UpgradeMath)
local function flag(flags: any, key: string): boolean
	if type(flags) ~= "table" then
		return false
	end
	local get = flags.get
	if type(get) == "function" then
		return get(key) == true
	end
	return flags[key] == true
end

-- Niveau d'une dalle comme PadRules.level (booléen : 0 ou 1 ; entier ≥ 0 sans borne haute)
local function tileLevel(profile: { [string]: any }, tile: string): number
	local tiles = profile.tiles
	if type(tiles) ~= "table" then
		return 0
	end
	local v = tiles[tile]
	if type(v) == "boolean" then
		return if v then 1 else 0
	end
	if not finite(v) then
		return 0
	end
	return math.max(0, math.floor(v))
end

local NOT_STAR: PadLabel = table.freeze({ star = false, lit = false, level = 0, price = math.huge })

-- Étiquette de la dalle `tile` pour ce profil (MON profil, StateController) : pour le Tapis au-delà du
-- Tapis 12 avec StarMat (`flags`) et un profil v2, la dalle achète le Tapis Étoilé ; elle est allumée
-- tant qu'un niveau est ouvert dans la boucle (UpgradeMath.cap), affiche le niveau 13 … 20 et le prix
-- UpgradeMath.price("star", niveau, r, A, Record R). Sinon : pas le Tapis Étoilé (l'étiquette de la
-- v1.3 s'applique)
function RanchLook.padLabel(profile: any, tile: any, flags: any): PadLabel
	if type(profile) ~= "table" or tile ~= "snack" then
		return NOT_STAR
	end
	local v2 = type(profile.version) == "number" and profile.version >= 2
	if not (flag(flags, "StarMat") and v2 and tileLevel(profile, "snack") >= SNACK_MAX) then
		return NOT_STAR
	end
	local star = UpgradeMath.level("star", profile)
	local lit = star < UpgradeMath.cap("star", profile, flags)
	if not lit then
		return { star = true, lit = false, level = 0, price = math.huge }
	end
	return {
		star = true,
		lit = true,
		level = tileLevel(profile, "snack") + star + 1,
		price = UpgradeMath.price(
			"star",
			star,
			Prestige.r(profile),
			Prestige.ascend(profile),
			Prestige.bestR(profile)
		),
	}
end

return RanchLook
