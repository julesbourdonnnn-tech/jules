--!strict
-- UpgradeMath (paquet A1, docs/04 §27.7, GDD v2.0 §4.6, §4.26, §10.7, §10.8 règle 5). LE SEUL calcul
-- des prix, des achats groupés, des plafonds et des effets de l'écran Améliorations ; même module
-- sur le client (aperçu, puce « Prochain achat ») et sur le serveur (débit de BuyUpgrade).
--  * Prix d'une famille de pièces au niveau actuel L (le premier achat coûte la base) :
--      max(1, floor((base × g^L) × RScale^r × F(A)))
--    chaque facteur construit UNE fois au chargement par multiplications successives dans un ordre
--    fixe (aucun ^, math.pow ni math.exp : Static_NoPow.spec), puis multipliés dans cet ordre.
--    Tapis Étoilé : base = prix du Tapis 12 AVANT floor (20 × 4,5^11), × 1,25^(L + 1).
--    Monuments : 3 × T12 × RScale^(ouverture du n-ième) × RScale^(r − bestR), sans F(A).
--    Enclos et Lit douillet : prix fixes (ni r ni A). Atelier et « Pour le plaisir » : coûts en
--    Confettis listés dans Config/Upgrades.
--  * Un niveau qui n'existe pas (au-delà du maximum, négatif, illisible) coûte math.huge : jamais
--    achetable. Un niveau qui existe coûte un entier fini ≥ 1, jusqu'à MaxR et MaxA.
--  * Identifiants : familles (Upgrades.Families.id), lignes de l'Atelier (WorkshopRows.id, decoShop
--    compris), lignes « bits » de « Pour le plaisir » sous "fun.<id>" (l'id nu est accepté aussi).
--  * Pur, déterministe, jamais d'erreur ; r, Record R et A lus par Logic/Prestige seulement.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table = type, math, string, table

local Types = require(script.Parent.Parent.Types)
local Balance = require(script.Parent.Parent.Config.Balance)
local Upgrades = require(script.Parent.Parent.Config.Upgrades)
local Species = require(script.Parent.Parent.Config.Species)
local Prestige = require(script.Parent.Prestige)
local TierRules = require(script.Parent.TierRules)
local Bitset = require(script.Parent.Bitset)

export type Effect = { a: number, b: number, key: string }

-- Contexte des effets (tout est facultatif ; valeur absente = cas sans bonus)
export type EffectCtx = {
	aBonus: number?, -- A_bonus actuel du revenu (Formulas.A) : effet réel d'une décoration
	bigRanch: boolean?, -- pass Grand Ranch (places)
	cozyBed: boolean?, -- Lit douillet (limite hors ligne)
	spikyFamily: boolean?, -- famille Spiky complète (+1 h hors ligne)
	nightBag: number?, -- niveau du Sac de nuit de l'Atelier (0-3) : heures de la ligne du Lit douillet
	bestR: number?, -- Record R (décorations gardées, Plopettes)
	monuments: number?, -- Monuments construits (lecture)
}

-- Interrupteurs : table de valeurs (copie figée à l'ouverture de l'écran, règle 19) ou le module
-- Config/Features lui-même (fonction get)
export type Flags = { [string]: any }

type Kind = "family" | "workshop" | "fun"
type Entry = {
	id: string,
	kind: Kind,
	levels: number, -- niveau maximal
	currency: Types.UpgradeCurrency,
	family: Upgrades.FamilyDef?,
	row: Upgrades.WorkshopRowDef?,
	fun: Upgrades.FunLineDef?,
	costs: { number }?, -- Confettis par niveau (Atelier, « Pour le plaisir »)
	base: { number }?, -- base × g^L par niveau (familles de pièces)
}

local UpgradeMath = {}

local MAX_R = Balance.Prestige.MaxR
local MAX_A = Balance.Prestige.MaxA
local MAX = Balance.Numbers.Max
local RSCALE = Balance.Tiles.RScale

-- =============================================================================================
-- Nombres sûrs
-- =============================================================================================

-- Entier de [lo ; hi] (NaN, nil, mauvais type → lo)
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

-- Réel fini ≥ 0 borné à Max (NaN, −inf, négatif → 0 ; +inf → Max)
local function money(x: any): number
	if type(x) ~= "number" or x ~= x or x <= 0 then
		return 0
	end
	return math.min(x, MAX)
end

-- Niveau demandé : entier ≥ 0, sinon nil (illisible, négatif, non entier)
local function levelArg(x: any): number?
	if type(x) ~= "number" or x ~= x or x < 0 or x == math.huge or x % 1 ~= 0 then
		return nil
	end
	return x
end

-- =============================================================================================
-- Tables construites une fois au chargement (multiplications successives, ordre fixe)
-- =============================================================================================

-- SCALE[r] = RScale^r ; UNSCALE[d] = RScale^(−d) (divisions successives) ; r, d = 0 … MaxR
local SCALE: { [number]: number } = { [0] = 1 }
local UNSCALE: { [number]: number } = { [0] = 1 }
for r = 1, MAX_R do
	SCALE[r] = SCALE[r - 1] * RSCALE
	UNSCALE[r] = UNSCALE[r - 1] / RSCALE
end

-- base × g^L pour L = 0 … n − 1
local function powers(base: number, growth: number, n: number): { number }
	local out = table.create(n, 0)
	local p = base
	for L = 1, n do
		out[L] = p
		p *= growth
	end
	return out
end

-- Prix du Tapis 12 avant floor (20 × 4,5^11) : base du Tapis Étoilé et des Monuments
local T12_RAW: number
do
	local snack = Balance.Tiles.snack
	local p = snack.Base
	for _ = 1, snack.Levels - 1 do
		p *= snack.Growth
	end
	T12_RAW = p
end

-- Bases par niveau d'une famille de pièces, selon sa source de prix ("tile:<clé>" ou "price:<clé>")
local function familyBases(def: Upgrades.FamilyDef): { number }
	local src, key = string.match(def.price, "^(%w+):(%w+)$")
	if src == "tile" then
		local t = (Balance.Tiles :: any)[key]
		return powers(t.Base, t.Growth, def.levels)
	elseif key == "star" then
		local star = Balance.UpgradePrices.star
		return powers(T12_RAW * star.Growth, star.Growth, def.levels)
	elseif key == "monument" then
		local out = table.create(def.levels, 0)
		for n = 1, def.levels do
			local p = T12_RAW * Balance.UpgradePrices.monument.PriceT12
			for _ = 1, Balance.Monuments.OpenAt[n] or 0 do
				p *= RSCALE
			end
			out[n] = p
		end
		return out
	end
	local u = (Balance.UpgradePrices :: any)[key]
	return powers(u.Base, u.Growth, def.levels)
end

-- Toutes les lignes achetables, dans l'ordre fixe de l'écran (familles, Atelier, « Pour le plaisir »)
local ENTRIES: { [string]: Entry } = {}
local IDS: { string } = {}
for _, def in Upgrades.Families do
	ENTRIES[def.id] = {
		id = def.id,
		kind = "family",
		levels = def.levels,
		currency = def.currency,
		family = def,
		base = familyBases(def),
	}
	table.insert(IDS, def.id)
end
for _, row in Upgrades.WorkshopRows do
	ENTRIES[row.id] = {
		id = row.id,
		kind = "workshop",
		levels = #row.costs,
		currency = "confetti",
		row = row,
		costs = row.costs,
	}
	table.insert(IDS, row.id)
end
for _, line in Upgrades.Fun do
	if line.store == "bits" then
		local id = "fun." .. line.id
		ENTRIES[id] = {
			id = id,
			kind = "fun",
			levels = #line.costs,
			currency = "confetti",
			fun = line,
			costs = line.costs,
		}
		table.insert(IDS, id)
	end
end

-- Identifiants de toutes les lignes achetables, dans l'ordre fixe (lecture seule : copie)
function UpgradeMath.ids(): { string }
	return table.clone(IDS)
end

-- Ligne d'un identifiant (l'id nu d'une ligne de « Pour le plaisir » est accepté)
local function entryOf(id: any): Entry?
	if type(id) ~= "string" then
		return nil
	end
	return ENTRIES[id] or ENTRIES["fun." .. id]
end

-- Identifiant canonique (nil : inconnu)
function UpgradeMath.canonical(id: string): string?
	local e = entryOf(id)
	return if e then e.id else nil
end

-- Niveau maximal d'une ligne (0 : inconnue)
function UpgradeMath.maxLevel(id: string): number
	local e = entryOf(id)
	return if e then e.levels else 0
end

-- Monnaie d'une ligne (nil : inconnue)
function UpgradeMath.currency(id: string): Types.UpgradeCurrency?
	local e = entryOf(id)
	return if e then e.currency else nil
end

-- =============================================================================================
-- Prix
-- =============================================================================================

-- Prix du prochain niveau quand le niveau actuel est `level` (0 = premier achat) ; math.huge si ce
-- niveau n'existe pas. R = r de la boucle, A = Ascensions, bestR = Record R (Monuments)
function UpgradeMath.price(id: string, level: number, R: number, A: number, bestR: number): number
	local e = entryOf(id)
	local L = levelArg(level)
	if e == nil or L == nil or L >= e.levels then
		return math.huge
	end
	if e.costs then
		return e.costs[L + 1]
	end
	local def = e.family :: Upgrades.FamilyDef
	local p = (e.base :: { number })[L + 1]
	local r = int(R, 0, MAX_R)
	if def.scaleR then
		p *= SCALE[r]
	elseif def.id == "monument" then
		-- après une Ascension, le prix suit la boucle en cours : × RScale^(r − Record R)
		p *= UNSCALE[math.max(r, int(bestR, 0, MAX_R)) - r]
	end
	if def.scaleA then
		p *= Prestige.priceFactor(int(A, 0, MAX_A))
	end
	return math.max(1, math.floor(math.min(p, MAX)))
end

-- Somme exacte, niveau par niveau, de n achats à partir du niveau `from` (n borné par les niveaux
-- qui existent) : (niveaux comptés, total)
function UpgradeMath.bulk(
	id: string,
	from: number,
	n: number,
	R: number,
	A: number,
	bestR: number
): (number, number)
	local e = entryOf(id)
	local L = levelArg(from)
	if e == nil or L == nil or L >= e.levels then
		return 0, 0
	end
	local count = int(n, 0, e.levels - L)
	local total = 0
	for k = 0, count - 1 do
		total += UpgradeMath.price(e.id, L + k, R, A, bestR)
	end
	return count, total
end

-- Plus grand nombre de niveaux payables avec `money` à partir de `from` (somme niveau par niveau,
-- jusqu'au maximum de la ligne) : (niveaux, total)
function UpgradeMath.maxAffordable(
	id: string,
	from: number,
	cash: number,
	R: number,
	A: number,
	bestR: number
): (number, number)
	local e = entryOf(id)
	local L = levelArg(from)
	if e == nil or L == nil then
		return 0, 0
	end
	local have = money(cash)
	local count, total = 0, 0
	while L + count < e.levels do
		local p = UpgradeMath.price(e.id, L + count, R, A, bestR)
		if total + p > have then
			break
		end
		total += p
		count += 1
	end
	return count, total
end

-- Achat d'un message BuyUpgrade, exactement comme le serveur le débite (aperçu du client = débit) :
-- n = min(mode (0 = Max), payable, cap − from, Balance.Upgrades.BulkMax) et total = bulk(n)
function UpgradeMath.plan(
	id: string,
	from: number,
	mode: number,
	cash: number,
	cap: number,
	R: number,
	A: number,
	bestR: number
): (number, number)
	local e = entryOf(id)
	local L = levelArg(from)
	if e == nil or L == nil then
		return 0, 0
	end
	-- mode illisible, négatif, non entier ou trop grand : rien (jamais pris pour « Max »)
	local m = levelArg(mode)
	if m == nil or m > Balance.Upgrades.BulkMax then
		return 0, 0
	end
	local want = if m == 0 then Balance.Upgrades.BulkMax else m
	local room = int(cap, 0, e.levels) - L
	local payable = UpgradeMath.maxAffordable(e.id, L, cash, R, A, bestR)
	local n = math.max(0, math.min(want, room, payable, Balance.Upgrades.BulkMax))
	return UpgradeMath.bulk(e.id, L, n, R, A, bestR)
end

-- =============================================================================================
-- Ouverture, niveaux, plafonds
-- =============================================================================================

-- Valeur d'un interrupteur ("" : toujours ouvert)
local function flag(features: any, key: string): boolean
	if key == "" then
		return true
	end
	if type(features) ~= "table" then
		return false
	end
	local get = (features :: any).get
	if type(get) == "function" then
		return get(key) == true
	end
	return features[key] == true
end

-- Condition d'ouverture (Record R, Ascensions)
local function opened(rule: Upgrades.OpenRule, bestR: number, A: number): boolean
	if rule.recordR ~= nil and bestR < rule.recordR then
		return false
	end
	if rule.ascend ~= nil and A < rule.ascend then
		return false
	end
	return true
end

-- Niveau actuel d'une ligne dans le profil (0 … maximum)
function UpgradeMath.level(id: string, profile: { [string]: any }): number
	local e = entryOf(id)
	if e == nil or type(profile) ~= "table" then
		return 0
	end
	if e.kind == "family" then
		local def = e.family :: Upgrades.FamilyDef
		local a, b = string.match(def.profileKey, "^(%w+)%.(%w+)$")
		local t = if a then profile[a] else nil
		local v = if type(t) == "table" and b then t[b] else nil
		if v == true then
			return 1
		end
		return int(v, 0, e.levels)
	elseif e.kind == "workshop" then
		local atelier = profile.atelier
		if type(atelier) ~= "table" then
			return 0
		end
		return int(atelier[Upgrades.WorkshopIndex[e.id]], 0, e.levels)
	end
	local line = e.fun :: Upgrades.FunLineDef
	local bits = profile.atelierCosmetics
	if type(bits) ~= "table" then
		return 0
	end
	return Bitset.countRange(bits, line.firstBit or 1, e.levels)
end

-- Niveau maximal achetable MAINTENANT (ouverture par le Record R ou A, plafond de la boucle,
-- interrupteurs) ; 0 = fermé. Ne dépasse jamais le maximum de la ligne
function UpgradeMath.cap(id: string, profile: { [string]: any }, features: Flags): number
	local e = entryOf(id)
	if e == nil or type(profile) ~= "table" then
		return 0
	end
	local r, best, A = Prestige.r(profile), Prestige.bestR(profile), Prestige.ascend(profile)
	if e.kind == "family" then
		local def = e.family :: Upgrades.FamilyDef
		if not flag(features, def.feature) or not opened(def.open, best, A) then
			return 0
		end
		if def.id == "star" then
			-- même ligne que le Tapis : seulement après le Tapis 12 ; plafond par r de la boucle
			if UpgradeMath.level("snack", profile) < UpgradeMath.maxLevel("snack") then
				return 0
			end
			return math.min(e.levels, Prestige.starCap(r))
		end
		local byLevel = def.open.recordRByLevel
		if byLevel ~= nil then
			local n = 0
			for _, at in byLevel do
				if best >= at then
					n += 1
				end
			end
			return math.min(e.levels, n)
		end
		return e.levels
	end
	-- Atelier et « Pour le plaisir » : Confettis gagnés au premier Grand Splorch (Record R ≥ 1)
	if not flag(features, "Workshop") or not flag(features, "Confetti") then
		return 0
	end
	if e.kind == "workshop" then
		local row = e.row :: Upgrades.WorkshopRowDef
		if not flag(features, row.feature) or not opened(row.open, best, A) then
			return 0
		end
		return e.levels
	end
	if best < 1 then
		return 0
	end
	return e.levels
end

-- Palier nommé d'une famille à un niveau (Logic/TierRules)
function UpgradeMath.tier(id: string, level: number): number
	return TierRules.of(id, level)
end

-- =============================================================================================
-- Effets « avant → après » (GDD §10.7.7) : a = valeur actuelle, b = après le prochain niveau
-- (b = a au maximum), key = libellé court. Unités : croissance et pressions en multiplicateur (×13,
-- ×1,175), pourcentages en FRACTION (0,012 pour +1,2 %), durées en secondes, nuit en heures.
-- =============================================================================================

local function bonusOf(ctx: any, key: string): any
	return if type(ctx) == "table" then ctx[key] else nil
end

-- Limite hors ligne en heures (8 h, 12 h avec le Lit, + 1 h Spiky, + Sac de nuit ; 16 h au plus) :
-- mêmes termes et même ordre que Formulas.offlineSeconds (qui requiert ce module : pas d'appel)
local NIGHT_BAG_MAX = #Upgrades.WorkshopRows[Upgrades.WorkshopIndex.nightBag].costs
local function nightHours(cozyBed: boolean, ctx: any, bag: number): number
	local h = if cozyBed then Balance.Offline.CozyBedHours else Balance.Offline.CapHours
	if bonusOf(ctx, "spikyFamily") == true then
		local bonus = Species.Families.spiky.bonus
		h += if bonus then bonus.value else 0
	end
	return math.min(Balance.OfflineV2.MaxHours, h + Balance.OfflineV2.NightBagHours * bag)
end

-- Plopettes arrivées par le Record R (Pip, Pop, Pim, Pom, Puff)
local function helpersAt(bestR: number): number
	local n = 0
	for _, at in Balance.Helpers.ByRecordR do
		if bestR >= at then
			n += 1
		end
	end
	return n
end

function UpgradeMath.effect(id: string, level: number, ctx: EffectCtx): Effect
	local e = entryOf(id)
	if e == nil then
		return { a = 0, b = 0, key = "" }
	end
	local L = int(level, 0, e.levels)
	local nextL = math.min(L + 1, e.levels)
	local c: any = ctx
	local best = int(bonusOf(c, "bestR"), 0, MAX_R)
	if e.kind == "family" then
		local def = e.family :: Upgrades.FamilyDef
		local key = def.effectKey
		local id0 = def.id
		if id0 == "snack" or id0 == "star" then
			local offset = Balance.Growth.SnackPerLevel
			local base = 1 + def.levelOffset * offset
			return { a = base + L * offset, b = base + nextL * offset, key = key }
		elseif id0 == "decor" then
			-- effet RÉEL du prochain niveau sur le revenu total : DecorBonus ÷ A_bonus (critique M8)
			local aBonus = bonusOf(c, "aBonus")
			local A = if type(aBonus) == "number"
					and aBonus == aBonus
					and aBonus >= 1
					and aBonus < math.huge
				then aBonus
				else 1 + Balance.Income.DecorBonus * L
			local gain = if L < e.levels then Balance.Income.DecorBonus / A else 0
			return { a = gain, b = gain, key = key }
		elseif id0 == "pens" then
			local spots = Balance.Pens.Base
				+ (if bonusOf(c, "bigRanch") == true then Balance.Pens.BigRanchBonus else 0)
			return {
				a = math.min(Balance.Pens.Max, spots + L),
				b = math.min(Balance.Pens.Max, spots + nextL),
				key = key,
			}
		elseif id0 == "cozyBed" then
			-- les vraies heures du joueur, famille Spiky et Sac de nuit compris (relecture A1, A1-38 :
			-- « Nuit : 8 h → 12 h » était écrit à tous, quand la ligne du Sac de nuit les comptait)
			local bag = int(bonusOf(c, "nightBag"), 0, NIGHT_BAG_MAX)
			return { a = nightHours(L >= 1, c, bag), b = nightHours(true, c, bag), key = key }
		elseif id0 == "gloves" then
			local step = Balance.Gloves.StepPerLevel
			return { a = 1 + step * L, b = 1 + step * nextL, key = key }
		elseif id0 == "monument" then
			local step = Balance.Monuments.IncomeStep
			return { a = step * L, b = step * nextL, key = key }
		elseif id0 == "school" then
			local h = Balance.Helpers
			return {
				a = h.IntervalBase - h.IntervalStep * L,
				b = h.IntervalBase - h.IntervalStep * nextL,
				key = key,
			}
		end
		return { a = L, b = nextL, key = key }
	elseif e.kind == "workshop" then
		local row = e.row :: Upgrades.WorkshopRowDef
		local key = row.effectKey
		local fx = row.effect
		if fx == "giftLevels" then
			local base = Balance.SplorchV2.GiftLevelsBase
			return { a = base + L, b = base + nextL, key = key }
		elseif fx == "magnetRadius" then
			local radii = Balance.PotV2.MagnetRadii
			return { a = radii[L + 1] or radii[#radii], b = radii[nextL + 1] or radii[#radii], key = key }
		elseif fx == "superStreak" then
			local base = Balance.Press.StreakMax
			return { a = base + L, b = base + nextL, key = key }
		elseif fx == "keptDecor" then
			return { a = Prestige.keptDecor(best, L), b = Prestige.keptDecor(best, nextL), key = key }
		elseif fx == "nightBagHours" then
			local bed = bonusOf(c, "cozyBed") == true
			return { a = nightHours(bed, c, L), b = nightHours(bed, c, nextL), key = key }
		elseif fx == "nightPotShare" then
			local shares = Balance.OfflineV2.NightPotShares
			return {
				a = shares[L + 1] or shares[#shares],
				b = shares[nextL + 1] or shares[#shares],
				key = key,
			}
		elseif fx == "extraHelper" then
			local n = helpersAt(best)
			return { a = n + L, b = n + nextL, key = key }
		end
		-- startMat, springboard, decoShop : niveaux (Tapis de départ, Grands Splorch sautés, objets)
		return { a = L, b = nextL, key = key }
	end
	local line = e.fun :: Upgrades.FunLineDef
	return { a = L, b = nextL, key = line.nameKey }
end

-- =============================================================================================
-- Instantané versionné de l'écran (règle 6 du GDD §10.8) et cadeau du Splorch
-- =============================================================================================

-- État de l'écran Améliorations pour ce profil : niveaux et plafonds de chaque ligne, pièces et
-- Confettis, r, Record R, A ; version fournie par le serveur (croît à chaque mutation)
function UpgradeMath.snapshot(
	profile: { [string]: any },
	features: Flags,
	version: number
): Types.UpgradeSnapshot
	local p: { [string]: any } = if type(profile) == "table" then profile else {}
	local levels: { [string]: number } = {}
	local caps: { [string]: number } = {}
	for _, id in IDS do
		levels[id] = UpgradeMath.level(id, p)
		caps[id] = UpgradeMath.cap(id, p, features)
	end
	return {
		coins = math.floor(money(p.coins)),
		confetti = int(p.confetti, 0, Balance.Confetti.Max),
		levels = levels,
		caps = caps,
		r = Prestige.r(p),
		bestR = Prestige.bestR(p),
		ascend = Prestige.ascend(p),
		version = int(version, 0, 9007199254740992), -- 2^53 : entier exact
	}
end

-- Pièces du cadeau du Splorch d'une boucle neuve (GDD §4.15) : prix des `levels` prochains niveaux du
-- Tapis, à partir de son niveau actuel (Tapis de départ), dans la boucle en cours (Prestige.apply
-- rend giftLevels)
function UpgradeMath.giftCoins(profile: { [string]: any }, levels: number): number
	if type(profile) ~= "table" then
		return 0
	end
	local _, total = UpgradeMath.bulk(
		"snack",
		UpgradeMath.level("snack", profile),
		levels,
		Prestige.r(profile),
		Prestige.ascend(profile),
		Prestige.bestR(profile)
	)
	return total
end

return UpgradeMath
