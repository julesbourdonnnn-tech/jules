--!strict
-- Prestige (paquet A1, docs/04 §27.7) : SEULE source de r (niveau de la boucle), du Record R
-- (bestR) et de A (nombre de Jelly Ascend) — GDD v2.0 §4.15, §4.26, §4.27, §4.29.
--  * r règle l'économie de la boucle (objectif, prix × 3,5^r, croissance × 2^r, plafond du Tapis
--    Étoilé, Confettis du Grand Splorch) ; le Record R règle tout ce qu'on voit ou possède ; A
--    multiplie la croissance (× 3^A) et les prix de la boucle (× F(A)).
--  * Aucun ^, math.pow ni math.exp (Static_NoPow.spec) : chaque table (3^A, F(A), objectifs,
--    plafond du Tapis Étoilé, plancher de StartR) est construite UNE fois au chargement, par
--    multiplications successives dans un ordre fixe, de la même façon sur le client et le serveur.
--  * Pur et déterministe ; toute entrée illisible (NaN, ±inf, nil, mauvais type) donne un résultat
--    sûr et fini, jamais une erreur. Bornes : Balance.Prestige.MaxR (400), MaxA (60).
--  * Static_PrestigeOnly.spec : aucune lecture de profile.R hors de ce module et de Data/Schema ;
--    les autres modules passent par Prestige.r(profile), Prestige.bestR(profile),
--    Prestige.ascend(profile).
--  * apply(profile, kind, now) applique un prestige D'UN SEUL BLOC (aucun yield), seulement s'il est
--    possible (Grand ou Petit Splorch : plus gros squishy ≥ objectif(r) ; Ascension : ascendReady) :
--    après lui la condition est fausse (toutes les tailles à 1, ou r = StartR < condition), donc un
--    second appel ne fait rien (« apply deux fois = apply une fois »). Il ne touche que les champs
--    qui repartent de zéro (pièces, Pot, dalles de la boucle, croissance cumulée, TOUTES les
--    tailles : enclos, Bassin, Dodo, Lettres, porté) et les compteurs de la progression (R, bestR,
--    ascend, regainBonusA, place d'enclos offerte) ; il ne baisse jamais bestR, ascend, les
--    Confettis ni l'Atelier, ne perd jamais un squishy. Les gains (Confettis, Fame, cadeau du
--    Splorch) sont RENDUS dans le rapport : l'appelant les verse (EconomyService.addConfetti, seul
--    point d'entrée des Confettis, GDD §4.26 critique m2 ; plafond de Fame du jour ; Pot) dans le
--    même bloc.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table, tonumber = type, math, string, table, tonumber

local Types = require(script.Parent.Parent.Types)
local Balance = require(script.Parent.Parent.Config.Balance)
local Upgrades = require(script.Parent.Parent.Config.Upgrades)
local Visuals = require(script.Parent.Parent.Config.Visuals)
local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)

export type UnlockTile = { key: string, vars: { [string]: any }? }

-- Rapport d'un prestige (2e valeur rendue par apply)
export type ApplyReport = {
	applied: boolean, -- faux : rien n'a changé (condition fausse, déjà appliqué, entrée illisible)
	kind: Types.PrestigeKind, -- sorte EFFECTIVE (un Grand Splorch qui ne bat pas le record est un Petit)
	fromR: number, -- r avant
	toR: number, -- r après
	bestR: number, -- Record R après
	ascend: number, -- A après
	record: boolean, -- nouveau Record R (premier passage)
	regain: boolean, -- retour au record après une Ascension (bonus donné maintenant)
	offeredPen: boolean, -- place d'enclos offerte posée
	fullPen: boolean, -- place offerte sur un enclos plein : FullPenBonus Confettis à la place
	skipped: number, -- Grands Splorch sautés grâce au Tremplin (Ascension)
	confetti: number, -- TOTAL à verser par EconomyService.addConfetti (gain + retour + enclos plein)
	confettiBase: number, -- part du prestige (confettiGain)
	lost: number, -- pièces + Pot repartis de zéro (aperçu « Tu vas perdre … », analytique)
	fame: number, -- Fame du prestige AVANT plafond du jour (Grand Splorch 5, Petit 0, Ascension 20)
	keptDecor: number, -- décorations gardées (niveau de la dalle après)
	decorBefore: number, -- niveau des décorations avant (decorBuilds, analytique)
	snackStart: number, -- niveau du Tapis au début de la boucle (Tapis de départ de l'Atelier)
	giftLevels: number, -- niveaux du Tapis payés par le cadeau du Splorch (6 offerts au plus)
	unlocks: { string }, -- déblocages du Record R atteint (premier passage seulement)
}

local Prestige = {}

local cfg = Balance.Prestige
local asc = Balance.Ascend
local conf = Balance.Confetti
local v2 = Balance.SplorchV2

local MAX_R = cfg.MaxR
local MAX_A = cfg.MaxA
local MAX = Balance.Numbers.Max

-- Constantes du GDD qui n'ont pas (encore) de clé dans Config/Balance (note INT-A1-BALANCE,
-- scratchpad a1-decisions.md) : écart du départ sous la condition suivante (« ReqR[A+1] − 10 »,
-- GDD §4.27), décorations gardées par niveau de « Déco qui reste » (+3, GDD §4.26), invariant de
-- stabilité (0,95 et objectifs × 2,5 dès r = 16, GDD §4.27, critique M13)
local START_GAP = 10
local KEPT_PER_LEVEL = 3
local STABILITY_SHARE = 0.95
local TARGET_RATIO_MIN = 2.5
local TARGET_RATIO_FROM = 16

-- Lignes de l'Atelier lues par la progression (positions définitives de profile.atelier)
local ROW_START_MAT = Upgrades.WorkshopIndex.startMat
local ROW_GIFT = Upgrades.WorkshopIndex.gift
local ROW_KEPT = Upgrades.WorkshopIndex.keptDecor
local ROW_SPRING = Upgrades.WorkshopIndex.springboard
local SPRING_MAX = #Upgrades.WorkshopRows[ROW_SPRING].costs
local START_MAT_MAX = #Upgrades.WorkshopRows[ROW_START_MAT].costs
local GIFT_MAX = #Upgrades.WorkshopRows[ROW_GIFT].costs
local KEPT_MAX_LEVEL = #Upgrades.WorkshopRows[ROW_KEPT].costs
local SNACK_LEVELS = Balance.Tiles.snack.Levels
local PENS_LEVELS = Balance.Tiles.pens.Levels

-- =============================================================================================
-- Nombres sûrs
-- =============================================================================================

-- Réel fini, sinon nil
local function finite(x: any): number?
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return nil
	end
	return x
end

-- Entier de [lo ; hi] (NaN, nil, mauvais type → lo ; +inf → hi ; −inf → lo)
local function int(x: any, lo: number, hi: number): number
	if type(x) ~= "number" or x ~= x then
		return lo
	end
	if x >= hi then
		return hi
	end
	if x <= lo then
		return lo
	end
	return math.floor(x)
end

-- Réel de [lo ; hi] (NaN → lo)
local function clampReal(x: any, lo: number, hi: number): number
	if type(x) ~= "number" or x ~= x then
		return lo
	end
	return math.clamp(x, lo, hi)
end

-- Arrondi à 2 chiffres significatifs (même calcul que Formulas.splorchTarget : mêmes objectifs)
local function twoSignificant(x: number): number
	local rounded = tonumber(string.format("%.1e", x))
	return if rounded then rounded else x
end

-- =============================================================================================
-- Tables construites une fois au chargement (multiplications successives, ordre fixe)
-- =============================================================================================

-- GROWTH_A[A] = GrowthMult^A ; PRICE_A[A] = Π PriceByA[min(k, #PriceByA)], k = 1 … A
local GROWTH_A: { [number]: number } = { [0] = 1 }
local PRICE_A: { [number]: number } = { [0] = 1 }
for a = 1, MAX_A do
	GROWTH_A[a] = GROWTH_A[a - 1] * asc.GrowthMult
	PRICE_A[a] = PRICE_A[a - 1] * asc.PriceByA[math.min(a, #asc.PriceByA)]
end

-- TARGET[r] = objectif de taille pour passer de r à r + 1 (table du GDD §4.15, puis × BeyondMult
-- arrondi à 2 chiffres significatifs, borné à Numbers.Max)
local TARGET: { [number]: number } = {}
do
	local targets = Balance.Splorch.Targets
	local last = 0
	for r = 0, MAX_R do
		if r < #targets then
			last = targets[r + 1]
		else
			last = math.min(MAX, twoSignificant(last * Balance.Splorch.BeyondMult))
		end
		TARGET[r] = last
	end
end

-- STAR_CAP[r] = niveaux du Tapis Étoilé ouverts dans une boucle de niveau r (plafond d'économie)
local STAR_CAP: { [number]: number } = {}
do
	local rule = (Upgrades.ById.star and Upgrades.ById.star.open.loopCapByR) or {}
	local cap = 0
	for r = 0, MAX_R do
		local at = rule[r]
		if at ~= nil and at > cap then
			cap = at
		end
		STAR_CAP[r] = cap
	end
end

-- FLOOR_R[A] = ceil(A × ln(GrowthMult) / ln(BeyondMult / 2) − StartFloorOffset) : plancher de
-- StartR (GDD §4.27). Un logarithme (pas une puissance), calculé une fois ; Prestige.spec vérifie
-- que A × q − décalage reste à plus de 1e-6 d'un entier pour A = 1 … MaxA (même plancher partout,
-- au bit près ou non)
local FLOOR_R: { [number]: number } = { [0] = 0 }
do
	local q = math.log(asc.GrowthMult) / math.log(Balance.Splorch.BeyondMult / 2)
	for a = 1, MAX_A do
		FLOOR_R[a] = math.ceil(a * q - asc.StartFloorOffset)
	end
end

-- =============================================================================================
-- Lecture du profil (seul lecteur de profile.R)
-- =============================================================================================

-- r : niveau de Grand Splorch de la boucle en cours (0 … MaxR)
function Prestige.r(profile: { [string]: any }): number
	if type(profile) ~= "table" then
		return 0
	end
	return int(profile.R, 0, MAX_R)
end

-- Record R : le plus haut r jamais atteint (≥ r ; profil v1 sans bestR : r)
function Prestige.bestR(profile: { [string]: any }): number
	if type(profile) ~= "table" then
		return 0
	end
	return math.max(Prestige.r(profile), int(profile.bestR, 0, MAX_R))
end

-- A : nombre de Jelly Ascend (0 … MaxA ; champ réservé de la v1 : 0)
function Prestige.ascend(profile: { [string]: any }): number
	if type(profile) ~= "table" then
		return 0
	end
	return int(profile.ascend, 0, MAX_A)
end

-- Niveau d'une ligne de l'Atelier (0 … #costs ; profil sans Atelier : 0)
local function atelierLevel(atelier: any, row: number, maxLevel: number): number
	if type(atelier) == "number" then
		return int(atelier, 0, maxLevel)
	end
	if type(atelier) ~= "table" then
		return 0
	end
	return int(atelier[row], 0, maxLevel)
end

-- =============================================================================================
-- Croissance, objectifs, condition de l'Ascension
-- =============================================================================================

-- Souvenir de gelée (GDD §4.27) : × RegainMult tant que bestR − r ≥ 3, puis RegainTaper[1]
-- (écart 2), [2] (écart 1), [3] sur la 1re boucle record après le retour au record ; 1 sinon
function Prestige.memoryFactor(R: number, bestR: number, firstRecordLoop: boolean): number
	local gap = int(bestR, 0, MAX_R) - int(R, 0, MAX_R)
	local taper = asc.RegainTaper
	if gap >= 3 then
		return asc.RegainMult
	elseif gap == 2 then
		return taper[1]
	elseif gap == 1 then
		return taper[2]
	elseif gap == 0 and firstRecordLoop == true then
		return taper[3]
	end
	return 1
end

-- Facteur de croissance de la progression : GrowthMult^A × Souvenir (la 1re boucle record ne
-- compte qu'après une Ascension, A ≥ 1)
function Prestige.growthFactor(R: number, A: number, bestR: number, firstRecordLoop: boolean): number
	local a = int(A, 0, MAX_A)
	return GROWTH_A[a] * Prestige.memoryFactor(R, bestR, firstRecordLoop == true and a >= 1)
end

-- Vrai pendant la 1re boucle record qui suit le retour au record (A ≥ 1, r = bestR, bonus de retour
-- donné pour ce A). Le champ memoryR (Record R au moment du retour) n'est pas encore au schéma v2
-- (note INT-A1-MEMORY) : sans lui, faux (jamais un × 1,25 de trop sur les boucles record suivantes)
function Prestige.firstRecordLoop(profile: { [string]: any }): boolean
	if type(profile) ~= "table" then
		return false
	end
	local A, r, best = Prestige.ascend(profile), Prestige.r(profile), Prestige.bestR(profile)
	if A < 1 or r ~= best or int(profile.regainBonusA, 0, MAX_A) ~= A then
		return false
	end
	local memoryR = finite(profile.memoryR)
	return memoryR ~= nil and int(memoryR, 0, MAX_R) == best
end

-- Objectif de taille pour passer de r à r + 1 (r ≥ MaxR : celui de MaxR, jamais inf)
function Prestige.target(R: number): number
	return TARGET[int(R, 0, MAX_R)]
end

-- Atteindre R est un nouveau Record R (premier passage)
function Prestige.isRecord(R: number, bestR: number): boolean
	return int(R, 0, MAX_R) > int(bestR, 0, MAX_R)
end

-- Sorte du prochain prestige de boucle : "splorch" s'il bat le record, "petit" sinon
function Prestige.nextKind(profile: { [string]: any }): Types.PrestigeKind
	local r = Prestige.r(profile)
	return if Prestige.isRecord(r + 1, Prestige.bestR(profile)) then "splorch" else "petit"
end

-- Condition de la k-ième Ascension : ReqR[k] (15, 20), puis + ReqStep à chaque suivante
function Prestige.reqR(k: number): number
	local list = asc.ReqR
	local n = int(k, 1, MAX_A + 1)
	if n <= #list then
		return list[n]
	end
	return list[#list] + asc.ReqStep * (n - #list)
end

-- L'Ascension est possible (A < MaxA et r ≥ condition) ; l'interrupteur JellyAscend est lu par
-- l'appelant
function Prestige.ascendReady(profile: { [string]: any }): boolean
	local A = Prestige.ascend(profile)
	return A < MAX_A and Prestige.r(profile) >= Prestige.reqR(A + 1)
end

-- Grand Splorch de départ après la A-ième Ascension (GDD §4.27) :
-- min(ReqR[A+1] − 10, max(StartStepPerA × (A − 1), plancher(A)) + Tremplin), 0 sans Ascension.
-- Sans Tremplin : 0, 4, 8, 13, 17, 21, 25, 29, 33, 38 pour A = 1 … 10
function Prestige.startR(A: number, springboard: number): number
	local a = int(A, 0, MAX_A)
	if a == 0 then
		return 0
	end
	local sb = int(springboard, 0, SPRING_MAX)
	local base = math.max(asc.StartStepPerA * (a - 1), FLOOR_R[a])
	return int(math.min(Prestige.reqR(a + 1) - START_GAP, base + sb), 0, MAX_R)
end

-- Facteur des prix de la boucle : Π PriceByA (0,5 aux 4 premières Ascensions, 0,32 ensuite)
function Prestige.priceFactor(A: number): number
	return PRICE_A[int(A, 0, MAX_A)]
end

-- Confettis d'un prestige (GDD §4.26) : Grand Splorch (nouveau Record R) 3 + min(r, CapR), + prime
-- de record au-delà de 20 ; Petit Splorch 1 ; Ascension 20 + 1 par Grand Splorch sauté GRÂCE AU
-- Tremplin (3 au plus ; ceux du plancher ne rapportent rien). R = r APRÈS la renaissance ; la sorte
-- effective suit l'état (un « splorch » qui ne bat pas le record paie comme un Petit Splorch). Le
-- retour au record (+10) et l'enclos plein (+25) sont comptés par apply (état du profil)
function Prestige.confettiGain(
	kind: Types.PrestigeKind,
	R: number,
	bestR: number,
	skippedBySpringboard: number
): number
	if kind == "ascend" then
		return conf.PerAscend + conf.PerSkipped * int(skippedBySpringboard, 0, SPRING_MAX)
	elseif kind == "splorch" or kind == "petit" then
		local r = int(R, 0, MAX_R)
		if Prestige.isRecord(r, bestR) then
			local gain = conf.PerGrandSplorchBase + math.min(r, conf.CapR)
			if r >= conf.RecordBonusFrom then
				gain += conf.RecordBonus
			end
			return gain
		end
		return conf.PerPetitSplorch
	end
	return 0
end

-- « Jusqu'à ton record, tes squishies grandissent 9 fois plus vite qu'avant » (aperçu de l'Ascension)
function Prestige.regainSpeedup(): number
	return asc.GrowthMult * asc.RegainMult
end

-- Entier fini ≥ lo (validation d'une configuration)
local function isInt(x: any, lo: number): boolean
	return finite(x) ~= nil and x % 1 == 0 and x >= lo
end

-- Réel fini > 0
local function isPositive(x: any): boolean
	return finite(x) ~= nil and x > 0
end

-- Invariant de stabilité (GDD §4.27, critique M13), vérifié au chargement d'une configuration (et
-- d'une configuration envoyée en direct : refus compté par Diagnostics) :
--  (1) (BeyondMult / 2)^ReqStep ≥ 0,95 × GrowthMult (une boucle record garde sa durée d'une
--      Ascension à l'autre) ;
--  (2) objectif(r + 1) / objectif(r) ≥ 2,5 pour tout r ≥ 16 jusqu'à MaxR (table puis × BeyondMult
--      arrondi à 2 chiffres significatifs, comme Prestige.target) ;
-- plus la forme des tables lues ici (bornes, conditions croissantes, facteurs finis). Jamais
-- d'erreur : une configuration illisible rend (false, raison).
function Prestige.validateConfig(balance: any): (boolean, string?)
	if type(balance) ~= "table" then
		return false, "balance"
	end
	local p, a, s = balance.Prestige, balance.Ascend, balance.Splorch
	if type(p) ~= "table" or type(a) ~= "table" or type(s) ~= "table" then
		return false, "tables"
	end
	if not isInt(p.MaxR, 1) or not isInt(p.MaxA, 1) or p.MaxR > 1000 or p.MaxA > 1000 then
		return false, "Prestige.MaxR/MaxA"
	end
	if not isPositive(a.GrowthMult) or a.GrowthMult <= 1 then
		return false, "Ascend.GrowthMult"
	end
	if not isInt(a.ReqStep, 1) then
		return false, "Ascend.ReqStep"
	end
	if type(a.ReqR) ~= "table" or #a.ReqR < 1 then
		return false, "Ascend.ReqR"
	end
	for i, v in a.ReqR do
		if not isInt(v, 1) or (i > 1 and v <= a.ReqR[i - 1]) then
			return false, "Ascend.ReqR"
		end
	end
	if type(a.PriceByA) ~= "table" or #a.PriceByA < 1 then
		return false, "Ascend.PriceByA"
	end
	for _, v in a.PriceByA do
		if not isPositive(v) then
			return false, "Ascend.PriceByA"
		end
	end
	if not isPositive(a.RegainMult) or a.RegainMult < 1 then
		return false, "Ascend.RegainMult"
	end
	local taper = a.RegainTaper
	if type(taper) ~= "table" or #taper ~= 3 then
		return false, "Ascend.RegainTaper"
	end
	local previous = a.RegainMult
	for _, v in taper do
		-- dégressif : jamais plus que l'étape d'avant, jamais moins que 1
		if not isPositive(v) or v < 1 or v > previous then
			return false, "Ascend.RegainTaper"
		end
		previous = v
	end
	if finite(a.StartFloorOffset) == nil or not isInt(a.StartStepPerA, 0) then
		return false, "Ascend.StartFloorOffset/StartStepPerA"
	end
	local targets, mult = s.Targets, s.BeyondMult
	if type(targets) ~= "table" or #targets < 1 or not isPositive(mult) then
		return false, "Splorch.Targets/BeyondMult"
	end
	for _, v in targets do
		if not isPositive(v) then
			return false, "Splorch.Targets"
		end
	end
	-- (1) (BeyondMult / 2)^ReqStep ≥ 0,95 × GrowthMult, par multiplications successives
	local q = 1
	for _ = 1, a.ReqStep do
		q *= mult / 2
	end
	if q < STABILITY_SHARE * a.GrowthMult then
		return false, "stabilité : (BeyondMult / 2)^ReqStep < 0,95 × GrowthMult"
	end
	-- (2) objectifs × 2,5 au moins dès r = 16, jusqu'à MaxR
	local max = if type(balance.Numbers) == "table" and isPositive(balance.Numbers.Max)
		then balance.Numbers.Max
		else MAX
	local last = 0
	local previousTarget = 0
	for r = 0, p.MaxR do
		if r < #targets then
			last = targets[r + 1]
		else
			last = math.min(max, twoSignificant(last * mult))
		end
		if r > TARGET_RATIO_FROM and last < max and last < TARGET_RATIO_MIN * previousTarget then
			return false, "stabilité : objectif(r + 1) / objectif(r) < 2,5 dès r = 16"
		end
		previousTarget = last
	end
	return true, nil
end

-- Décorations gardées au prestige : 3 au Record R 8, 3 de plus au 14, + 3 par niveau de « Déco qui
-- reste », 12 au plus (GDD §4.6, critique M3). atelier : profile.atelier (ou le niveau de la ligne)
function Prestige.keptDecor(bestR: number, atelier: any): number
	local best = int(bestR, 0, MAX_R)
	local n = 0
	for _, step in v2.KeptDecorAt do
		if best >= step.recordR then
			n += step.n
		end
	end
	n += KEPT_PER_LEVEL * atelierLevel(atelier, ROW_KEPT, KEPT_MAX_LEVEL)
	return math.min(n, v2.KeptDecorMax)
end

-- Plafond du Tapis Étoilé dans une boucle de niveau r (0 avant r = 6 ; 8 dès r = 10)
function Prestige.starCap(R: number): number
	return STAR_CAP[int(R, 0, MAX_R)]
end

-- =============================================================================================
-- Déblocages nommés du Record R (GDD §4.29)
-- =============================================================================================

-- Tuiles « Tu gagnes » du premier passage d'un Record R : table du §4.29 pour 1 … 20 ; au-delà,
-- prime de record, Monuments 9 et 10 (22, 24) et titres (Cosmetics.ListV2, source recordR)
function Prestige.unlockTiles(bestR: number): { UnlockTile }
	local R = int(bestR, 0, MAX_R)
	local out: { UnlockTile } = {}
	if R < 1 then
		return out
	end
	local row = Visuals.RecordTable[R]
	if row ~= nil then
		for _, tile in row.unlocks do
			table.insert(out, { key = tile.key, vars = if tile.vars then table.clone(tile.vars) else nil })
		end
		return out
	end
	if R >= conf.RecordBonusFrom then
		table.insert(out, { key = "unlock.recordBonus", vars = { n = conf.RecordBonus } })
	end
	for n, at in Balance.Monuments.OpenAt do
		if at == R then
			table.insert(out, { key = "unlock.monument", vars = { n = n } })
		end
	end
	for _, item in Cosmetics.ListV2 do
		local source = item.source
		if source and source.kind == "recordR" and source.value == R then
			table.insert(out, { key = "unlock.item", vars = { name = item.key } })
		end
	end
	return out
end

-- Clés de texte des déblocages du Record R (une par tuile)
function Prestige.unlocksFor(bestR: number): { string }
	local out = {}
	for _, tile in Prestige.unlockTiles(bestR) do
		table.insert(out, tile.key)
	end
	return out
end

-- =============================================================================================
-- Application d'un prestige
-- =============================================================================================

-- Croissance cumulée G à l'instant now (même calcul que Formulas.G, sans dépendre de Formulas)
local function growthAt(growth: any, now: number): number
	if type(growth) ~= "table" then
		return 0
	end
	local G = clampReal(growth.G, 0, MAX)
	local g = clampReal(growth.g, 0, MAX)
	local t = finite(growth.t) or 0
	if now <= t then
		return G
	end
	return clampReal(G + g * (now - t), 0, MAX)
end

-- Taille d'un squishy (z + (G − zg) en enclos ou Bassin, z ailleurs ; bornée à [1 ; Max])
local function sizeOf(rec: any, G: number): number
	if type(rec) ~= "table" then
		return 1
	end
	local z = clampReal(rec.z, 1, MAX)
	if rec.at == "pen" or rec.at == "pool" then
		return clampReal(z + (G - clampReal(rec.zg, 0, MAX)), 1, MAX)
	end
	return z
end

-- Plus grosse taille du profil à l'instant now (TOUS les squishies : jamais plus strict que la
-- condition de SplorchService, qui ne compte que l'enclos et le Bassin)
function Prestige.biggest(profile: { [string]: any }, now: number): number
	if type(profile) ~= "table" or type(profile.squishies) ~= "table" then
		return 0
	end
	local t = finite(now) or 0
	local G = growthAt(profile.growth, t)
	local best = 0
	for _, rec in profile.squishies do
		if type(rec) == "table" then
			best = math.max(best, sizeOf(rec, G))
		end
	end
	return best
end

-- Grand ou Petit Splorch possible : plus gros ≥ objectif(r) et r < MaxR (« Record absolu ! »)
function Prestige.splorchReady(profile: { [string]: any }, now: number): boolean
	local r = Prestige.r(profile)
	if r >= MAX_R then
		return false
	end
	return Prestige.biggest(profile, now) >= Prestige.target(r)
end

local function emptyReport(profile: any, kind: Types.PrestigeKind): ApplyReport
	local r = if type(profile) == "table" then Prestige.r(profile) else 0
	return {
		applied = false,
		kind = kind,
		fromR = r,
		toR = r,
		bestR = if type(profile) == "table" then Prestige.bestR(profile) else 0,
		ascend = if type(profile) == "table" then Prestige.ascend(profile) else 0,
		record = false,
		regain = false,
		offeredPen = false,
		fullPen = false,
		skipped = 0,
		confetti = 0,
		confettiBase = 0,
		lost = 0,
		fame = 0,
		keptDecor = 0,
		decorBefore = 0,
		snackStart = 0,
		giftLevels = 0,
		unlocks = {},
	}
end

-- Remise à zéro de la boucle (Grand Splorch, Petit Splorch, Ascension) : pièces, Pot, dalles de la
-- boucle (Tapis de départ et décorations gardées exceptés), croissance cumulée, toutes les tailles
local function resetLoop(profile: { [string]: any }, report: ApplyReport, keptBestR: number, now: number)
	report.lost = clampReal(profile.coins, 0, MAX) + clampReal(profile.pot, 0, MAX)
	profile.coins = 0
	profile.pot = 0
	local tiles = if type(profile.tiles) == "table" then profile.tiles else {}
	profile.tiles = tiles
	local decorBefore = int(tiles.decor, 0, Balance.Tiles.decor.Levels)
	report.decorBefore = decorBefore
	report.keptDecor = math.min(decorBefore, Prestige.keptDecor(keptBestR, profile.atelier))
	local start =
		math.min(SNACK_LEVELS, v2.FreeSnackMax, atelierLevel(profile.atelier, ROW_START_MAT, START_MAT_MAX))
	report.snackStart = start
	report.giftLevels = math.max(
		0,
		math.min(
			v2.GiftLevelsBase + atelierLevel(profile.atelier, ROW_GIFT, GIFT_MAX),
			v2.FreeSnackMax - start,
			SNACK_LEVELS - start
		)
	)
	tiles.snack = start
	tiles.decor = report.keptDecor
	tiles.star = 0
	tiles.gloves = 0
	tiles.school = 0
	local growth = profile.growth
	local g = if type(growth) == "table" then finite(growth.g) else nil
	profile.growth = { G = 0, g = if g and g >= 0 then math.min(g, MAX) else Balance.Growth.Base, t = now }
	if type(profile.squishies) == "table" then
		for _, rec in profile.squishies do
			if type(rec) == "table" then
				rec.z = 1
				rec.zg = 0
			end
		end
	end
end

-- Applique un prestige d'un seul bloc. kind : "splorch" ou "petit" (renaissance de la boucle, la
-- sorte effective suit le record) ou "ascend". now : Clock.now() du serveur (croissance cumulée).
-- Rend (clés de premier niveau changées → true, pour DataService.markDirty ; rapport). Rien ne
-- change si la condition est fausse : un second appel au même instant ne fait rien.
function Prestige.apply(
	profile: { [string]: any },
	kind: Types.PrestigeKind,
	now: number
): ({ [string]: any }, ApplyReport)
	local changed: { [string]: any } = {}
	local report = emptyReport(profile, kind)
	local t = finite(now)
	if type(profile) ~= "table" or t == nil then
		return changed, report
	end
	local r, best, A = Prestige.r(profile), Prestige.bestR(profile), Prestige.ascend(profile)
	if kind == "splorch" or kind == "petit" then
		if not Prestige.splorchReady(profile, t) then
			return changed, report
		end
		local toR = r + 1
		local record = Prestige.isRecord(toR, best)
		report.kind = if record then "splorch" else "petit"
		resetLoop(profile, report, best, t)
		local newBest = math.max(best, toR)
		report.record = record
		report.confettiBase = Prestige.confettiGain(report.kind, toR, best, 0)
		report.confetti = report.confettiBase
		report.fame = if record then Balance.Splorch.Fame else 0
		if record then
			report.unlocks = Prestige.unlocksFor(newBest)
			-- place d'enclos offerte au premier passage (+25 Confettis sur un enclos plein)
			if table.find(v2.OfferedPensAt, newBest) ~= nil then
				local tiles = profile.tiles
				local pens = int(tiles.pens, 0, PENS_LEVELS)
				if pens < PENS_LEVELS then
					tiles.pens = pens + 1
					report.offeredPen = true
				else
					report.fullPen = true
					report.confetti += conf.FullPenBonus
				end
			end
			profile.bestR = newBest
			changed.bestR = true
		elseif toR == best and A >= 1 and int(profile.regainBonusA, 0, MAX_A) < A then
			-- retour au record après une Ascension : +10, une fois par Ascension
			report.regain = true
			report.confetti += conf.RegainBonus
			profile.regainBonusA = A
			changed.regainBonusA = true
			if type(profile.memoryR) == "number" then
				profile.memoryR = best
				changed.memoryR = true
			end
		end
		profile.R = toR
		report.toR = toR
		report.bestR = newBest
	elseif kind == "ascend" then
		if not Prestige.ascendReady(profile) then
			return changed, report
		end
		local newA = A + 1
		local sb = atelierLevel(profile.atelier, ROW_SPRING, SPRING_MAX)
		local toR = Prestige.startR(newA, sb)
		local skipped = toR - Prestige.startR(newA, 0)
		resetLoop(profile, report, best, t)
		report.skipped = skipped
		report.confettiBase = Prestige.confettiGain("ascend", toR, best, skipped)
		report.confetti = report.confettiBase
		report.fame = asc.Fame
		profile.ascend = newA
		profile.R = toR
		changed.ascend = true
		report.toR = toR
		report.ascend = newA
		report.bestR = best
		-- bestR peut manquer (profil v1) : le Record R est gardé, jamais perdu par r qui redescend
		if int(profile.bestR, 0, MAX_R) ~= best then
			profile.bestR = best
			changed.bestR = true
		end
	else
		return changed, report
	end
	report.applied = true
	report.confetti = math.min(report.confetti, conf.Max)
	for _, key in { "coins", "pot", "tiles", "R", "growth", "squishies" } do
		changed[key] = true
	end
	return changed, report
end

return Prestige
