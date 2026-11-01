--!strict
-- Odds (paquet logic, docs/04 §12.1). Tirages des naissances, déterministes et à graine contrôlée
-- (GDD §4.5, §4.9, §4.11, §4.21.5, §4.22). Tables affichées = tables tirées :
--   * rareté : table de qualité Balance.Vat.Quality (en %), puis protection contre la malchance
--     (pityRare ≥ 40 → au moins Rare ; pityEpic ≥ 150 → au moins Épique), puis plafond éventuel ;
--   * espèce : à chances égales parmi les espèces PUBLIÉES de la rareté dans les familles débloquées
--     (nil = toutes les familles) ; si aucune, rareté juste en dessous, jusqu'à Commun ; Secret →
--     Royal Plop, pendant la Lune Royal ou Moonplop à chances égales ; nouveauté garantie : parmi
--     les espèces non tamponnées de la rareté s'il en reste ;
--   * mutation : un seul nombre comparé aux chances cumulées depuis la plus rare
--     (Mutations.DrawOrder), Lunaire à part en dernier (3 % pendant la Lune, non multipliée par les
--     buses). Si un multiplicateur pousse le total au-delà de 100 %, les chances sont ramenées
--     proportionnellement à 100 % (jamais plus d'une mutation par naissance).
-- Aucun achat ne change une probabilité (GDD §8.1) : seul R (qualité, buses) et la Lune comptent.
-- Odds.roll consomme toujours exactement 3 nombres du flux (rareté, espèce, mutation), même quand
-- la mutation est imposée : la suite d'un tirage ne dépend que de sa graine.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table = type, math, string, table

local Hash = require(script.Parent.Hash)
local Balance = require(script.Parent.Parent.Config.Balance)
local Species = require(script.Parent.Parent.Config.Species)
local Rarities = require(script.Parent.Parent.Config.Rarities)
local Mutations = require(script.Parent.Parent.Config.Mutations)

export type RollCtx = {
	quality: number,
	nozzles: number,
	moon: boolean,
	unix: number, -- espèces publiées (Species.isReleased)
	families: { [string]: boolean }?, -- nil = toutes les familles (bébés, cadeaux)
	owned: { [number]: boolean }?, -- espèces tamponnées (nouveauté garantie)
	newPull: boolean?, -- ce tirage est « nouveauté garantie »
	pityRare: number?,
	pityEpic: number?,
	mutationMult: number?, -- MEGA, Goutte chanceuse : × 2
	forceMutation: number?, -- Golden Wobbler (Doré), Goutte de Lune (Lunaire)
	maxRarity: number?, -- plafond de rareté (cadeaux du Grand Splorch : Peu commun pour une espèce Épique+)
}

export type RollResult = {
	species: number,
	rarity: number,
	mutation: number,
	oneIn: number,
	pityRare: number, -- compteurs après ce tirage
	pityEpic: number,
	usedNewPull: boolean, -- ce tirage était « nouveauté garantie » (le service décompte vat.newPulls)
}

local Odds = {}

-- Fonctions de base gardées en local (appels rapides, même dans un environnement de test injecté)
local floor, min, max, clamp = math.floor, math.min, math.max, math.clamp

local SEED_SALT = 0x0DD5 -- sel des graines de tirage (figé)
local QUALITY_MAX = 8

-- =============================================================================================
-- Aides
-- =============================================================================================

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- r sûr dans [0 ; 1[
local function unitR(r: any): number
	local v = finite(r, 0)
	if v < 0 then
		return 0
	end
	if v >= 1 then
		return 1 - 1e-12
	end
	return v
end

local function clampInt(x: any, lo: number, hi: number): number
	return clamp(floor(finite(x, lo)), lo, hi)
end

-- Plus haute qualité présente dans la table (8 au lancement)
local MAX_QUALITY = 0
for k in Balance.Vat.Quality do
	MAX_QUALITY = max(MAX_QUALITY, k)
end
MAX_QUALITY = min(QUALITY_MAX, MAX_QUALITY)

local function qualityOf(q: any): number
	return clampInt(q, 0, MAX_QUALITY)
end

local function nozzlesOf(n: any): number
	return clampInt(n, 0, Mutations.NozzleMax)
end

-- Multiplicateur de mutation sûr dans ]0 ; MULT_MAX] (au-delà, le total est de toute façon ramené à
-- 100 % ; une valeur énorme ne peut jamais rendre une chance infinie ou NaN)
local MULT_MAX = 1000
local function multOf(m: any): number
	local v = finite(m, 1)
	if v <= 0 then
		return 1
	end
	return if v > MULT_MAX then MULT_MAX else v
end

-- =============================================================================================
-- Familles et raretés
-- =============================================================================================

-- Familles de la Cuve débloquées à ce R (Jelly, Kitty, Froggy ; Axolo R ≥ 1 ; Bunny R ≥ 3 ; Spiky R ≥ 5)
function Odds.unlockedFamilies(R: number): { [string]: boolean }
	local r = max(0, floor(finite(R, 0)))
	local out = {}
	for key, def in Species.Families do
		if def.unlockR >= 0 and def.unlockR <= r then
			out[key] = true
		end
	end
	return out
end

-- Pourcentages par rareté (1 … 7) de la table de qualité
function Odds.rarityTable(quality: number): { number }
	return table.clone(Balance.Vat.Quality[qualityOf(quality)])
end

-- Poids cumulés de chaque table de qualité (même arithmétique que Hash.pickWeighted : r × total
-- comparé aux sommes partielles ; un poids nul n'est jamais choisi)
type Cumulative = { acc: { number }, total: number, last: number }
local CUMULATIVE: { [number]: Cumulative } = {}
for q, row in Balance.Vat.Quality do
	local acc, total, last = {}, 0, 1
	for i, w in ipairs(row) do
		if w > 0 then
			total += w
			last = i
		end
		acc[i] = total
	end
	CUMULATIVE[q] = { acc = acc, total = total, last = last }
end

-- Rareté tirée avec r dans [0 ; 1[ et la protection contre la malchance
function Odds.rollRarity(quality: number, r: number, pityRare: number, pityEpic: number): number
	local cum = CUMULATIVE[qualityOf(quality)]
	local target = unitR(r) * cum.total
	local rarity = cum.last
	for i, acc in cum.acc do
		if target < acc then
			rarity = i
			break
		end
	end
	if finite(pityEpic, 0) >= Balance.Vat.PityEpic then
		rarity = max(rarity, Rarities.EPIC)
	end
	if finite(pityRare, 0) >= Balance.Vat.PityRare then
		rarity = max(rarity, Rarities.RARE)
	end
	return rarity
end

-- =============================================================================================
-- Mutations
-- =============================================================================================

-- Chances effectives calculées une fois par réglage (cache pur, jamais modifié par un appelant)
local chanceCache: { [string]: { [number]: number } } = {}
local chanceCacheSize = 0
local CHANCE_CACHE_MAX = 64 -- quelques réglages en jeu ; vidé s'il grossit (entrées bizarres)

local fastChances: { [number]: { [number]: number } } = {}

local function chancesFor(nozzles: any, moon: any, mult: any): { [number]: number }
	local n = nozzlesOf(nozzles)
	local isMoon = moon == true
	local m = multOf(mult)
	-- clé numérique pour les réglages du jeu (multiplicateur 1 ou 2), chaîne sinon
	local fastKey = if m == 1 or m == 2
		then n * 4 + (if isMoon then 2 else 0) + (if m == 2 then 1 else 0)
		else nil
	if fastKey ~= nil and fastChances[fastKey] then
		return fastChances[fastKey]
	end
	local key = if fastKey == nil then string.format("%d|%s|%.17g", n, if isMoon then "1" else "0", m) else ""
	if fastKey == nil and chanceCache[key] then
		return chanceCache[key]
	end
	local factor = (1 + Mutations.NozzleStep * n) * m
	if isMoon then
		factor *= Mutations.MoonMult
	end
	local out: { [number]: number } = {}
	local total = 0
	for _, def in Mutations.List do
		local chance
		if def.moonOnly then
			chance = if isMoon then Mutations.MoonChance else 0
		else
			chance = def.chance * factor
		end
		out[def.id] = chance
		total += chance
	end
	if total > 1 then
		for id, chance in out do
			out[id] = chance / total
		end
	end
	if fastKey ~= nil then
		fastChances[fastKey] = out
		return out
	end
	if chanceCacheSize >= CHANCE_CACHE_MAX then
		table.clear(chanceCache)
		chanceCacheSize = 0
	end
	chanceCache[key] = out
	chanceCacheSize += 1
	return out
end

-- Chances effectives par mutation (fraction) : buses, Lune (× 2, Lunaire 3 %), multiplicateur (MEGA, Goutte chanceuse)
function Odds.mutationChances(nozzles: number, moon: boolean, mult: number?): { [number]: number }
	return table.clone(chancesFor(nozzles, moon, mult))
end

-- Ordre du tirage : de la plus rare à la plus commune, puis les mutations « à part » (Lunaire)
local DRAW: { number } = table.clone(Mutations.DrawOrder)
for _, def in Mutations.List do
	if not table.find(DRAW, def.id) then
		table.insert(DRAW, def.id)
	end
end

-- Mutation tirée (0 = aucune) : comparée aux chances cumulées depuis la plus rare
function Odds.rollMutation(r: number, nozzles: number, moon: boolean, mult: number?): number
	local chances = chancesFor(nozzles, moon, mult)
	local x = unitR(r)
	local acc = 0
	for _, id in DRAW do
		acc += chances[id] or 0
		if x < acc then
			return id
		end
	end
	return Mutations.NONE
end

-- =============================================================================================
-- Espèces
-- =============================================================================================

-- Espèces de chaque rareté hors Secrets, dans l'ordre des identifiants (cache pur)
local BY_RARITY: { [number]: { any } } = {}
for _, def in Species.List do
	if def.family ~= "secret" then
		BY_RARITY[def.rarity] = BY_RARITY[def.rarity] or {}
		table.insert(BY_RARITY[def.rarity], def)
	end
end

-- Espèces candidates d'une rareté (ordre des identifiants : déterministe)
local function candidates(
	rarity: number,
	families: { [string]: boolean }?,
	unix: number,
	moon: boolean
): { number }
	local out = {}
	if rarity == Rarities.SECRET then
		local royal = Species.ById[Species.ROYAL]
		if royal and Species.isReleased(royal, unix) then
			table.insert(out, royal.id)
		end
		local moonDef = Species.ById[Species.MOON]
		if moon and moonDef and Species.isReleased(moonDef, unix) then
			table.insert(out, moonDef.id)
		end
		return out
	end
	for _, def in BY_RARITY[rarity] or {} do
		if Species.isReleased(def, unix) and (families == nil or families[def.family] == true) then
			table.insert(out, def.id)
		end
	end
	return out
end

-- Espèce de la rareté (nil = toutes les familles) ; nouveauté garantie si preferNew et une espèce non possédée existe
function Odds.speciesFor(
	rarity: number,
	families: { [string]: boolean }?,
	owned: { [number]: boolean }?,
	preferNew: boolean,
	r: number,
	unix: number,
	moon: boolean
): number
	local fam = if type(families) == "table" then families else nil
	local t = finite(unix, 0)
	local isMoon = moon == true
	local own = if preferNew == true and type(owned) == "table" then owned else nil
	local start = clampInt(rarity, Rarities.COMMON, Rarities.Count)
	for rr = start, Rarities.COMMON, -1 do
		local list = candidates(rr, fam, t, isMoon)
		if #list > 0 then
			if own ~= nil then
				local fresh = {}
				for _, id in list do
					if own[id] ~= true then
						table.insert(fresh, id)
					end
				end
				if #fresh > 0 then
					list = fresh
				end
			end
			local index = min(#list, floor(unitR(r) * #list) + 1)
			return list[index]
		end
	end
	return Species.PLOP -- aucune famille utilisable : repli sûr
end

-- =============================================================================================
-- Naissance complète
-- =============================================================================================

-- Arrondi à 2 chiffres significatifs (réel fini > 0)
local function twoSignificant(x: number): number
	local v = tonumber(string.format("%.1e", x))
	return if v then v else x
end

-- Étiquette « 1 sur X » d'une naissance, calculée aux réglages du moment (2 chiffres significatifs).
-- 0 si la naissance est impossible à ces réglages (aucune étiquette inventée).
local oneInCache: { [number]: number } = {}

function Odds.oneIn(rarity: number, mutation: number, quality: number, nozzles: number, moon: boolean): number
	local q = qualityOf(quality)
	local n = nozzlesOf(nozzles)
	local isMoon = moon == true
	local row = Balance.Vat.Quality[q]
	local ri = clampInt(rarity, 1, #row)
	local m = finite(mutation, 0)
	if m ~= Mutations.NONE and Mutations.ById[m] == nil then
		m = Mutations.NONE
	end
	local key = (((ri * 16 + m) * 16 + q) * 8 + n) * 2 + (if isMoon then 1 else 0)
	local cached = oneInCache[key]
	if cached ~= nil then
		return cached
	end
	local pr = (row[ri] or 0) / 100
	local chances = chancesFor(n, isMoon, nil)
	local pm
	if m == Mutations.NONE then
		local total = 0
		for _, c in chances do
			total += c
		end
		pm = max(0, 1 - total)
	else
		pm = chances[m] or 0
	end
	local p = pr * pm
	local value = if p > 0 then twoSignificant(1 / p) else 0
	oneInCache[key] = value
	return value
end

-- Naissance complète (rareté, espèce, mutation, « 1 sur X », compteurs de protection)
function Odds.roll(rng: Hash.Stream, ctx: RollCtx): RollResult
	local c: any = if type(ctx) == "table" then ctx else {}
	local quality = qualityOf(c.quality)
	local nozzles = nozzlesOf(c.nozzles)
	local moon = c.moon == true
	local pityRare = max(0, floor(finite(c.pityRare, 0)))
	local pityEpic = max(0, floor(finite(c.pityEpic, 0)))
	local stream: any = rng
	if type(stream) ~= "table" or type(stream.next) ~= "function" then
		stream = Hash.stream(0)
	end

	local r1, r2, r3 = stream:next(), stream:next(), stream:next()

	local rarity = Odds.rollRarity(quality, r1, pityRare, pityEpic)
	if c.maxRarity ~= nil then
		rarity = min(rarity, clampInt(c.maxRarity, Rarities.COMMON, Rarities.Count))
	end
	local newPull = c.newPull == true
	local species = Odds.speciesFor(rarity, c.families, c.owned, newPull, r2, finite(c.unix, 0), moon)
	local def = Species.ById[species]
	local actual = if def then def.rarity else Rarities.COMMON

	local mutation
	if c.forceMutation ~= nil and Mutations.ById[c.forceMutation] then
		mutation = c.forceMutation
	else
		mutation = Odds.rollMutation(r3, nozzles, moon, c.mutationMult)
	end

	return {
		species = species,
		rarity = actual,
		mutation = mutation,
		oneIn = Odds.oneIn(actual, mutation, quality, nozzles, moon),
		pityRare = if actual >= Rarities.RARE then 0 else pityRare + 1,
		pityEpic = if actual >= Rarities.EPIC then 0 else pityEpic + 1,
		usedNewPull = newPull,
	}
end

-- Graine déterministe du tirage n° counter d'un joueur
function Odds.seed(userId: number, counter: number): number
	return Hash.u32(userId, counter, SEED_SALT)
end

return Odds
