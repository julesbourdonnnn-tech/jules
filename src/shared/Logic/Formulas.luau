--!strict
-- Formulas (paquet logic, docs/04 §12.1). Formules de l'économie, pures et partagées serveur /
-- client / simulation (GDD §4.1-§4.19, §12.3). Toute valeur rendue est finie, ≥ 0 et bornée
-- (Balance.Numbers.Max) : une entrée NaN, ±inf, négative ou nil donne un résultat sûr, jamais une
-- erreur (propriétés : Props_Formulas.spec).
-- Croissance cumulée du ranch : G(t) = growth.G + growth.g × (t − growth.t) ; taille d'un squishy
-- d'enclos ou du Bassin = z + (G(t) − zg) ; Dodo et Lettres : z figé (docs/04 §8.3).
-- Pot : intégrale exacte du revenu entre deux règlements (GDD §12.3) :
--   revenu(t) = S1 + K × G(t) ; ∫ revenu = S1 × Δ + K × (G(t0) × Δ + ½ × g × Δ²).
-- Aucun nombre du GDD en dur : tout vient de Config/Balance (et Species, Rarities, Mutations).

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table = type, math, string, table

local Types = require(script.Parent.Parent.Types)
local Balance = require(script.Parent.Parent.Config.Balance)
local Species = require(script.Parent.Parent.Config.Species)
local Rarities = require(script.Parent.Parent.Config.Rarities)
local Mutations = require(script.Parent.Parent.Config.Mutations)

export type GrowthCtx = {
	R: number,
	snack: number, -- niveau du Tapis à Goûter
	jellyFamily: boolean,
	boost: boolean, -- B = 2 (un seul ×2, jamais cumulé)
}

export type IncomeCtx = {
	decor: number, -- décorations construites
	friends: number, -- amis Roblox présents
	fame: number,
	trophyBonus: number, -- Formulas.trophyBonus
	goldenPages: number, -- pages dorées du Squishydex
	doubleCoins: boolean, -- P = 2
	boost: boolean, -- B = 2
}

export type VatLevel = { quality: number, speed: number, nozzles: number }

export type RideStats = { walkSpeed: number, jumpHeight: number, hipHeight: number, scale: number }

export type PreviewCtx = {
	now: number, -- Clock.now()
	unix: number, -- Clock.unix()
}

local Formulas = {}

local MAX = Balance.Numbers.Max
local EXACT_BELOW = Balance.Numbers.ExactBelow
local HOUR = 3600
local MAX_R = 1000 -- au-delà, 2^R n'a plus de sens (borné à Max de toute façon)

-- =============================================================================================
-- Nombres sûrs
-- =============================================================================================

-- Réel fini, sinon `default`
local function num(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- Réel fini dans [lo ; hi] (NaN → lo ; +inf → hi ; −inf → lo)
local function clampNum(x: any, lo: number, hi: number): number
	if type(x) ~= "number" or x ~= x then
		return lo
	end
	if x < lo then
		return lo
	end
	if x > hi then
		return hi
	end
	return x
end

-- Entier ≥ 0 borné (NaN → 0)
local function level(x: any, hi: number): number
	return math.floor(clampNum(x, 0, hi))
end

-- Montant réel (Pot, intégrales) : fini, ≥ 0, ≤ Max, jamais arrondi
local function amount(x: number): number
	if x ~= x or x <= 0 then
		return 0
	end
	if x > MAX then
		return MAX
	end
	return x
end

local function bool(x: any): boolean
	return x == true
end

-- Multiplicateur de rareté d'une espèce (espèce inconnue : 0, aucun revenu)
local function rarityMult(species: any): number
	local def = Species.ById[species]
	if not def then
		return 0
	end
	local rarity = Rarities.List[def.rarity]
	return if rarity then rarity.mult else 0
end

-- Multiplicateur d'une mutation (0 ou inconnue : 1)
local function mutationMult(mutation: any): number
	local def = Mutations.ById[mutation]
	return if def then def.mult else 1
end

-- =============================================================================================
-- Bornes
-- =============================================================================================

-- NaN, ±inf ou négatif → 0 ; > Max → Max ; entier (floor) sous ExactBelow
function Formulas.clampCoins(x: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge or x <= 0 then
		return 0
	end
	if x > MAX then
		return MAX
	end
	if x < EXACT_BELOW then
		return math.floor(x)
	end
	return x
end

-- Taille bornée à [1 ; Max] ; NaN → 1
function Formulas.clampSize(x: number): number
	return clampNum(x, 1, MAX)
end

-- =============================================================================================
-- Croissance et tailles
-- =============================================================================================

-- Champs sûrs d'une croissance cumulée
local function saneGrowth(growth: any): (number, number, number)
	if type(growth) ~= "table" then
		return 0, 0, 0
	end
	local G = clampNum(growth.G, 0, MAX)
	local g = clampNum(growth.g, 0, MAX)
	local t = num(growth.t, 0)
	return G, g, t
end

-- Croissance cumulée à l'instant t (t antérieur à growth.t → growth.G)
function Formulas.G(growth: Types.Growth, t: number): number
	local G, g, t0 = saneGrowth(growth)
	local tt = num(t, t0)
	if tt <= t0 then
		return G
	end
	return clampNum(G + g * (tt - t0), 0, MAX)
end

-- Taille d'un squishy : z + (G − zg) en enclos ou Bassin, z ailleurs
function Formulas.sizeAt(rec: Types.SquishyRecord, G: number): number
	if type(rec) ~= "table" then
		return 1
	end
	local z = Formulas.clampSize(rec.z)
	if rec.at == "pen" or rec.at == "pool" then
		local zg = clampNum(rec.zg, 0, MAX)
		local g = clampNum(G, 0, MAX)
		return Formulas.clampSize(z + (g - zg))
	end
	return z
end

-- g = Base × 2^R × (1 + niveauTapis) × (1 + 0,10 × Jelly) × B
function Formulas.growthRate(ctx: GrowthCtx): number
	local c: any = if type(ctx) == "table" then ctx else {}
	local cfg = Balance.Growth
	local R = level(c.R, MAX_R)
	local snack = level(c.snack, Balance.Tiles.snack.Levels)
	local g = cfg.Base * cfg.RebirthMult ^ R * (1 + cfg.SnackPerLevel * snack)
	if bool(c.jellyFamily) then
		g *= 1 + cfg.JellyFamilyBonus
	end
	if bool(c.boost) then
		g *= cfg.BoostMult
	end
	return clampNum(g, 0, MAX)
end

-- =============================================================================================
-- Revenu
-- =============================================================================================

-- Plafond du bonus de l'Étagère : meilleur palier × nombre d'espèces (+ 208 % au lancement)
local MAX_TROPHY_BONUS = 0
for _, tier in Balance.Trophies do
	MAX_TROPHY_BONUS = math.max(MAX_TROPHY_BONUS, tier.bonus * #Species.List)
end

-- Multiplicateur additif A (décos, amis, Fame, Étagère, pages dorées)
function Formulas.A(ctx: IncomeCtx): number
	local c: any = if type(ctx) == "table" then ctx else {}
	local cfg = Balance.Income
	local decor = level(c.decor, Balance.Tiles.decor.Levels)
	local friends = level(c.friends, cfg.FriendMax)
	local fame = clampNum(c.fame, 0, cfg.FameCap)
	local trophy = clampNum(c.trophyBonus, 0, MAX_TROPHY_BONUS)
	local pages = level(c.goldenPages, #Species.List)
	return 1
		+ cfg.DecorBonus * decor
		+ cfg.FriendBonus * friends
		+ cfg.FamePerPoint * fame
		+ trophy
		+ cfg.GoldenPageBonus * pages
end

-- Produit A × P × B du contexte (commun à tous les squishies du ranch)
local function ctxMult(ctx: any): number
	local c: any = if type(ctx) == "table" then ctx else {}
	local m = Formulas.A(c)
	if bool(c.doubleCoins) then
		m *= Balance.Income.DoubleCoinsMult
	end
	if bool(c.boost) then
		m *= Balance.Growth.BoostMult
	end
	return m
end

-- k pour un produit A × P × B déjà calculé
local function factor(species: any, mutation: any, stars: any, mult: number): number
	local cfg = Balance.Income
	local st = level(stars, Balance.Fusion.MaxStars)
	return clampNum(
		cfg.Coef * rarityMult(species) * mutationMult(mutation) * (1 + cfg.StarBonus * st) * mult,
		0,
		MAX
	)
end

-- Revenu par unité de taille k = Coef × rareté × mutation × (1 + 0,5 × étoiles) × A × P × B
function Formulas.incomeFactor(species: number, mutation: number, stars: number, ctx: IncomeCtx): number
	return factor(species, mutation, stars, ctxMult(ctx))
end

-- Revenu par seconde d'un squishy d'enclos (k × taille)
function Formulas.income(
	size: number,
	species: number,
	mutation: number,
	stars: number,
	ctx: IncomeCtx
): number
	return clampNum(Formulas.incomeFactor(species, mutation, stars, ctx) * Formulas.clampSize(size), 0, MAX)
end

-- (K = Σ k, S1 = Σ k × (z − zg)) sur les squishies d'enclos et du Bassin ; revenu(t) = S1 + K × G(t).
-- G (croissance cumulée à l'instant du calcul) sert de garde : une ligne dont la taille à G serait
-- sous 1 (donnée abîmée) compte comme une taille 1 à G, puis grandit normalement.
function Formulas.ranchIncome(
	squishies: { [string]: Types.SquishyRecord },
	G: number,
	ctx: IncomeCtx
): (number, number)
	if type(squishies) ~= "table" then
		return 0, 0
	end
	local g = clampNum(G, 0, MAX)
	local mult = ctxMult(ctx)
	local K, S1 = 0, 0
	for _, rec in squishies do
		if type(rec) == "table" and (rec.at == "pen" or rec.at == "pool") then
			local k = factor(rec.s, rec.m, rec.st, mult)
			if k > 0 then
				local offset = Formulas.clampSize(rec.z) - clampNum(rec.zg, 0, MAX)
				if offset + g < 1 then
					offset = 1 - g
				end
				K += k
				S1 += k * offset
			end
		end
	end
	return clampNum(K, 0, MAX), clampNum(S1, -MAX, MAX)
end

-- Pièces gagnées entre t0 et t1 (intégrale exacte, g constant sur l'intervalle). Montant réel (non
-- arrondi : N règlements successifs donnent la même somme qu'un seul), borné à [0 ; Max].
function Formulas.potGain(K: number, S1: number, growth: Types.Growth, t0: number, t1: number): number
	local k = clampNum(K, 0, MAX)
	local s1 = clampNum(S1, -MAX, MAX)
	local a = num(t0, 0)
	local b = num(t1, a)
	if b <= a or (k == 0 and s1 <= 0) then
		return 0
	end
	local G0, g, tg = saneGrowth(growth)
	local dt = b - a
	-- ∫ G(t) dt : constant avant growth.t, linéaire après
	local before = math.max(0, math.min(b, tg) - a)
	local startAfter = math.max(a, tg)
	local after = math.max(0, b - startAfter)
	local gAtStart = G0 + g * (startAfter - tg)
	local integralG = G0 * before + gAtStart * after + 0.5 * g * after * after
	return amount(s1 * dt + k * integralG)
end

-- floor(max(Min, Seconds × revenu) × PERFECT × série × Kitty)
function Formulas.pressReward(income: number, perfect: boolean, streak: number, kittyFamily: boolean): number
	local cfg = Balance.Press
	local base = math.max(cfg.Min, cfg.Seconds * clampNum(income, 0, MAX))
	local mult = (if bool(perfect) then cfg.PerfectMult else 1)
		* (1 + cfg.StreakStep * level(streak, cfg.StreakMax))
	if bool(kittyFamily) then
		local kitty = Species.Families.kitty.bonus
		mult *= 1 + (if kitty then kitty.value else cfg.KittyBonus)
	end
	return Formulas.clampCoins(base * mult)
end

-- =============================================================================================
-- Dalles, places, Cuve
-- =============================================================================================

-- Prix du prochain niveau : floor(Base × Growth^L × (ScaleWithR ? Tiles.RScale^R : 1)) (contrat v1.2,
-- GDD v1.3 §4.6 : × 3,5^R pour les dalles de la boucle) ; math.huge si niveau maximal ou dalle inconnue.
-- Balance.Tiles porte aussi des nombres (EnterRadius, DwellSeconds, RScale…) : seule une TABLE est une
-- dalle.
function Formulas.tileCost(tile: string, lvl: number, R: number): number
	if type(tile) ~= "string" then
		return math.huge
	end
	local def = (Balance.Tiles :: any)[tile]
	if type(def) ~= "table" or type(def.Base) ~= "number" or type(def.Levels) ~= "number" then
		return math.huge
	end
	local L = level(lvl, math.huge)
	if L >= def.Levels then
		return math.huge
	end
	local price = def.Base * def.Growth ^ L
	if def.ScaleWithR then
		price *= Balance.Tiles.RScale ^ level(R, MAX_R)
	end
	return Formulas.clampCoins(price)
end

-- Places d'enclos (Bassin compris) : 4 + niveau (+ 6), 24 au plus
function Formulas.penCapacity(pensLevel: number, bigRanch: boolean): number
	local cfg = Balance.Pens
	local cap = cfg.Base + level(pensLevel, Balance.Tiles.pens.Levels)
	if bool(bigRanch) then
		cap += cfg.BigRanchBonus
	end
	return math.min(cfg.Max, cap)
end

-- Places d'attente du Bassin (5, ou 6 avec la famille Axolo)
function Formulas.poolSlots(axoloFamily: boolean): number
	local slots = Balance.Fusion.PoolSlots
	if bool(axoloFamily) then
		local bonus = Species.Families.axolo.bonus
		slots += if bonus then bonus.value else 1
	end
	return slots
end

-- Qualité, vitesse et buses de la Cuve données par R
function Formulas.vatLevel(R: number): VatLevel
	local cfg = Balance.Vat
	local r = level(R, MAX_R)
	return {
		quality = math.min(cfg.QualityMax, cfg.QualityBase + r),
		speed = math.min(cfg.SpeedMax, cfg.SpeedBase + cfg.SpeedPerR * r),
		nozzles = math.min(Mutations.NozzleMax, r),
	}
end

-- Intervalle de la Cuve en secondes (90 × 0,85^vitesse, × 0,9 Bunny)
function Formulas.vatInterval(R: number, bunnyFamily: boolean): number
	local cfg = Balance.Vat
	local interval = cfg.Interval * cfg.SpeedFactor ^ Formulas.vatLevel(R).speed
	if bool(bunnyFamily) then
		local bonus = Species.Families.bunny.bonus
		interval *= if bonus then bonus.value else 1
	end
	return interval
end

-- =============================================================================================
-- Fusion, vente, récompenses
-- =============================================================================================

-- (a + b) × 1,25, borné
function Formulas.fusionSize(a: number, b: number): number
	return Formulas.clampSize((Formulas.clampSize(a) + Formulas.clampSize(b)) * Balance.Fusion.SizeMult)
end

-- min(5, étoiles + 1)
function Formulas.fusionStars(stars: number): number
	local maxStars = Balance.Fusion.MaxStars
	return math.min(maxStars, level(stars, maxStars) + 1)
end

-- Mutation au plus gros multiplicateur (0 si aucune)
function Formulas.bestMutation(m1: number, m2: number): number
	local a = if Mutations.ById[m1] then m1 else 0
	local b = if Mutations.ById[m2] then m2 else 0
	if a == 0 then
		return b
	end
	if b == 0 then
		return a
	end
	local ma, mb = Mutations.ById[a].mult, Mutations.ById[b].mult
	if mb > ma or (mb == ma and b > a) then
		return b
	end
	return a
end

-- Étape k : ComboSeconds × k × revenu du squishy obtenu
function Formulas.comboReward(step: number, income: number): number
	return Formulas.clampCoins(Balance.Fusion.ComboSeconds * level(step, MAX) * clampNum(income, 0, MAX))
end

-- max(Min, floor(Seconds × revenu du squishy))
function Formulas.sellValue(income: number): number
	local cfg = Balance.Sell
	return math.max(cfg.Min, Formulas.clampCoins(cfg.Seconds * clampNum(income, 0, MAX)))
end

-- Récompense « en secondes de revenu » (entier, ≥ minimum)
function Formulas.secondsOfIncome(income: number, seconds: number, minimum: number?): number
	local value = Formulas.clampCoins(clampNum(income, 0, MAX) * clampNum(seconds, 0, MAX))
	return math.max(Formulas.clampCoins(minimum or 0), value)
end

-- =============================================================================================
-- Grand Splorch
-- =============================================================================================

-- Arrondi à 2 chiffres significatifs (réel fini > 0)
local function twoSignificant(x: number): number
	local rounded = tonumber(string.format("%.1e", x))
	return if rounded then rounded else x
end

-- Objectifs au-delà de la table (R ≥ 20), calculés une fois (cache pur) jusqu'à Max
local beyond: { number } = {}
do
	local cfg = Balance.Splorch
	local last = cfg.Targets[#cfg.Targets]
	while last < MAX do
		last = math.min(MAX, twoSignificant(last * cfg.BeyondMult))
		table.insert(beyond, last)
	end
end

-- Objectif de taille pour passer de R à R + 1 (table, puis × 2,7 arrondi à 2 chiffres significatifs)
function Formulas.splorchTarget(R: number): number
	local targets = Balance.Splorch.Targets
	local r = level(R, math.huge)
	if r < #targets then
		return targets[r + 1]
	end
	return beyond[r - #targets + 1] or MAX
end

-- =============================================================================================
-- Hors ligne
-- =============================================================================================

-- Absence comptée, bornée à la limite (8 h, 12 h Lit douillet, + 1 h Spiky) ; 0 au premier chargement
function Formulas.offlineSeconds(
	nowUnix: number,
	lastOnline: number,
	cozyBed: boolean,
	spikyFamily: boolean
): number
	local now = num(nowUnix, 0)
	local last = num(lastOnline, 0)
	if last <= 0 or now <= last then
		return 0
	end
	local cfg = Balance.Offline
	local hours = if bool(cozyBed) then cfg.CozyBedHours else cfg.CapHours
	if bool(spikyFamily) then
		local bonus = Species.Families.spiky.bonus
		hours += if bonus then bonus.value else 0
	end
	return math.min(now - last, hours * HOUR)
end

-- Croissance cumulée gagnée hors ligne (contrat v1.2, GDD v1.3 §4.19) :
--   clamp(g sans boost × GrowthShare × durée, 0, max(0, StopAt × splorchTarget(R) − plus gros))
-- Le plus gros squishy d'enclos ou du Bassin s'arrête à StopAt (90 %) de l'objectif en cours : le
-- Grand Splorch se fait en jeu. Sans R ou sans plus gros (nil), pas d'arrêt. Un R illisible vaut 0 ;
-- un plus gros illisible (NaN) vaut 0, +inf arrête tout.
function Formulas.offlineGrowth(gNoBoost: number, seconds: number, R: number?, biggest: number?): number
	local cfg = Balance.Offline
	local grown = clampNum(clampNum(gNoBoost, 0, MAX) * cfg.GrowthShare * clampNum(seconds, 0, MAX), 0, MAX)
	if R == nil or biggest == nil then
		return grown
	end
	local stopAt = cfg.StopAt * Formulas.splorchTarget(R :: number)
	local room = math.max(0, stopAt - clampNum(biggest, 0, MAX))
	return math.min(grown, room)
end

-- Pièces hors ligne versées au Pot (× PotShare) ; montant réel, borné
function Formulas.offlinePot(incomeNoBoost: number, seconds: number): number
	return amount(clampNum(incomeNoBoost, 0, MAX) * Balance.Offline.PotShare * clampNum(seconds, 0, MAX))
end

-- =============================================================================================
-- Bébés, selles, trophées, paquets
-- =============================================================================================

-- Taille d'un bébé ou d'un cadeau : part (de l'original, sinon du plus gros du receveur), ≥ minimum,
-- ≤ MaxOfBiggest (0,5, GDD v1.3 §4.25) × plus gros du receveur. Le minimum passe en dernier (un bébé
-- n'est jamais plus petit que son minimum, même chez un nouveau).
function Formulas.babySize(share: number, minimum: number, receiverBiggest: number, original: number?): number
	local biggest = Formulas.clampSize(receiverBiggest)
	local base = if original ~= nil then Formulas.clampSize(original) else biggest
	local size = clampNum(share, 0, MAX) * base
	size = math.min(size, Balance.Babies.MaxOfBiggest * biggest)
	size = math.max(clampNum(minimum, 1, MAX), size)
	return Formulas.clampSize(size)
end

-- Selle gagnée 0 … 3 (record ≥ 1 200, 1e6, 1e12)
function Formulas.saddleLevel(biggestEver: number): number
	local record = clampNum(biggestEver, 0, MAX)
	local lvl = 0
	for i, saddle in Balance.Ride.Saddles do
		if record >= saddle.minSize then
			lvl = i
		end
	end
	return lvl
end

-- WalkSpeed, JumpHeight, HipHeight et échelle affichée de la monture
function Formulas.rideStats(saddle: number): RideStats
	local cfg = Balance.Ride
	local def = cfg.Saddles[level(saddle, #cfg.Saddles)]
	if not def then
		return {
			walkSpeed = cfg.BaseWalkSpeed,
			jumpHeight = cfg.BaseJumpHeight,
			hipHeight = cfg.BaseHipHeight,
			scale = 1,
		}
	end
	return {
		walkSpeed = cfg.BaseWalkSpeed * cfg.SpeedMult,
		jumpHeight = def.jumpHeight,
		hipHeight = cfg.BaseHipHeight + cfg.HipFactor * Balance.SizeScale.BaseDiameter * def.scale,
		scale = def.scale,
	}
end

-- Palier de l'Étagère 0 … 4 (bronze, argent, or, cristal)
function Formulas.trophyTier(record: number): number
	local r = clampNum(record, 0, MAX)
	local tier = 0
	for i, def in Balance.Trophies do
		if r >= def.min then
			tier = i
		end
	end
	return tier
end

-- Bonus additif de l'Étagère (somme des paliers, + 208 % au plus)
function Formulas.trophyBonus(trophies: { number }): number
	if type(trophies) ~= "table" then
		return 0
	end
	local total = 0
	for s = 1, #Species.List do
		local tier = Formulas.trophyTier(trophies[s])
		if tier > 0 then
			total += Balance.Trophies[tier].bonus
		end
	end
	return total
end

-- OBSOLÈTE (contrat v1.2, GDD v1.3 §8.3 : paquets de pièces retirés du lancement, Balance.CoinPacks
-- supprimé) : rend toujours 0. Gardée seulement parce que Contract_game.spec liste encore la fonction ;
-- à supprimer quand l'architecte la retire de sa liste (note d'intégration de la revue logic).
function Formulas.coinPack(_income: number, _productKey: string): number
	return 0
end

-- =============================================================================================
-- Aperçu du Grand Splorch (GDD §4.15)
-- =============================================================================================

-- uid d'ordre : plus court puis alphabétique (base 36 : ordre de création)
local function uidBefore(a: string, b: string): boolean
	if #a ~= #b then
		return #a < #b
	end
	return a < b
end

-- Aperçu du Grand Splorch à partir d'un profil (même calcul côté serveur et client)
function Formulas.splorchPreview(data: { [string]: any }, ctx: PreviewCtx): Types.SplorchPreview
	local d: any = if type(data) == "table" then data else {}
	local c: any = if type(ctx) == "table" then ctx else {}
	local cfg = Balance.Splorch
	local R = level(d.R, MAX_R)
	local G = Formulas.G(d.growth, num(c.now, 0))

	-- plus gros squishy (enclos et Bassin) ; envol par défaut : le plus gros de l'enclos qui n'est pas
	-- un Meilleur Ami (s'ils le sont tous, le plus gros)
	local biggest = 0
	local bestFree, bestFreeSize = "", -1
	local bestAny, bestAnySize = "", -1
	if type(d.squishies) == "table" then
		for uid, rec in d.squishies do
			if type(uid) == "string" and type(rec) == "table" and (rec.at == "pen" or rec.at == "pool") then
				local size = Formulas.sizeAt(rec, G)
				biggest = math.max(biggest, size)
				if rec.at == "pen" then
					if size > bestAnySize or (size == bestAnySize and uidBefore(uid, bestAny)) then
						bestAny, bestAnySize = uid, size
					end
					local free = num(rec.bf, 0) <= 0
					if
						free and (size > bestFreeSize or (size == bestFreeSize and uidBefore(uid, bestFree)))
					then
						bestFree, bestFreeSize = uid, size
					end
				end
			end
		end
	end

	local target = Formulas.splorchTarget(R)
	local coins = Formulas.clampCoins(d.coins)
	local pot = amount(num(d.pot, 0))
	local coinsLost = Formulas.clampCoins(coins + pot)
	-- contrat v1.2 : plus de 2e confirmation (paquets de pièces retirés) ; recentBuy n'est plus rendu

	local unlocks = {}
	for _, key in cfg.Unlocks[R + 1] or {} do
		table.insert(unlocks, key)
	end

	return {
		ready = biggest >= target,
		target = target,
		biggest = biggest,
		level = R + 1,
		unlocks = unlocks,
		coinsLost = coinsLost,
		nextTarget = Formulas.splorchTarget(R + 1),
		defaultFlyer = if bestFree ~= "" then bestFree else bestAny,
	}
end

return Formulas
