--!strict
-- Formulas (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Formules de l'économie, pures et partagées serveur / client / simulation (GDD §4.1-§4.19, §12.3).
-- Toute valeur rendue est finie, ≥ 0 et bornée (Balance.Numbers.Max) : une entrée NaN, ±inf ou
-- négative donne un résultat sûr, jamais une erreur (propriétés : Props_Formulas.spec).
-- Croissance cumulée du ranch : G(t) = growth.G + growth.g × (t − growth.t) ; taille d'un squishy
-- d'enclos ou du Bassin = z + (G(t) − zg) ; Dodo et Lettres : z figé (docs/04 §8.3).
-- Pot : intégrale exacte du revenu entre deux règlements (GDD §12.3).

local Types = require(script.Parent.Parent.Types)

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

-- NaN, ±inf ou négatif → 0 ; > Max → Max ; entier (floor) sous ExactBelow
function Formulas.clampCoins(x: number): number
	local _ = { x }
	error("TODO(logic): Formulas.clampCoins")
end

-- Taille bornée à [1 ; Max] ; NaN → 1
function Formulas.clampSize(x: number): number
	local _ = { x }
	error("TODO(logic): Formulas.clampSize")
end

-- Croissance cumulée à l'instant t (t antérieur à growth.t → growth.G)
function Formulas.G(growth: Types.Growth, t: number): number
	local _ = { growth, t }
	error("TODO(logic): Formulas.G")
end

-- Taille d'un squishy : z + (G − zg) en enclos ou Bassin, z ailleurs
function Formulas.sizeAt(rec: Types.SquishyRecord, G: number): number
	local _ = { rec, G }
	error("TODO(logic): Formulas.sizeAt")
end

-- g = Base × 2^R × (1 + niveauTapis) × (1 + 0,10 × Jelly) × B
function Formulas.growthRate(ctx: GrowthCtx): number
	local _ = { ctx }
	error("TODO(logic): Formulas.growthRate")
end

-- Multiplicateur additif A (décos, amis, Fame, Étagère, pages dorées)
function Formulas.A(ctx: IncomeCtx): number
	local _ = { ctx }
	error("TODO(logic): Formulas.A")
end

-- Revenu par unité de taille k = Coef × rareté × mutation × (1 + 0,5 × étoiles) × A × P × B
function Formulas.incomeFactor(species: number, mutation: number, stars: number, ctx: IncomeCtx): number
	local _ = { species, mutation, stars, ctx }
	error("TODO(logic): Formulas.incomeFactor")
end

-- Revenu par seconde d'un squishy d'enclos (k × taille)
function Formulas.income(
	size: number,
	species: number,
	mutation: number,
	stars: number,
	ctx: IncomeCtx
): number
	local _ = { size, species, mutation, stars, ctx }
	error("TODO(logic): Formulas.income")
end

-- (K = Σ k, S1 = Σ k × (z − zg)) sur les squishies d'enclos et du Bassin ; revenu(t) = S1 + K × G(t)
function Formulas.ranchIncome(
	squishies: { [string]: Types.SquishyRecord },
	G: number,
	ctx: IncomeCtx
): (number, number)
	local _ = { squishies, G, ctx }
	error("TODO(logic): Formulas.ranchIncome")
end

-- Pièces gagnées entre t0 et t1 (intégrale exacte, g constant sur l'intervalle)
function Formulas.potGain(K: number, S1: number, growth: Types.Growth, t0: number, t1: number): number
	local _ = { K, S1, growth, t0, t1 }
	error("TODO(logic): Formulas.potGain")
end

-- floor(max(Min, Seconds × revenu) × PERFECT × série × Kitty)
function Formulas.pressReward(income: number, perfect: boolean, streak: number, kittyFamily: boolean): number
	local _ = { income, perfect, streak, kittyFamily }
	error("TODO(logic): Formulas.pressReward")
end

-- Prix du prochain niveau (math.huge si niveau maximal ou dalle inconnue)
function Formulas.tileCost(tile: string, level: number, R: number): number
	local _ = { tile, level, R }
	error("TODO(logic): Formulas.tileCost")
end

-- Places d'enclos (Bassin compris) : 4 + niveau (+ 6), 24 au plus
function Formulas.penCapacity(pensLevel: number, bigRanch: boolean): number
	local _ = { pensLevel, bigRanch }
	error("TODO(logic): Formulas.penCapacity")
end

-- Places d'attente du Bassin (5, ou 6 avec la famille Axolo)
function Formulas.poolSlots(axoloFamily: boolean): number
	local _ = { axoloFamily }
	error("TODO(logic): Formulas.poolSlots")
end

-- Qualité, vitesse et buses de la Cuve données par R
function Formulas.vatLevel(R: number): VatLevel
	local _ = { R }
	error("TODO(logic): Formulas.vatLevel")
end

-- Intervalle de la Cuve en secondes (90 × 0,85^vitesse, × 0,9 Bunny)
function Formulas.vatInterval(R: number, bunnyFamily: boolean): number
	local _ = { R, bunnyFamily }
	error("TODO(logic): Formulas.vatInterval")
end

-- (a + b) × 1,25, borné
function Formulas.fusionSize(a: number, b: number): number
	local _ = { a, b }
	error("TODO(logic): Formulas.fusionSize")
end

-- min(5, étoiles + 1)
function Formulas.fusionStars(stars: number): number
	local _ = { stars }
	error("TODO(logic): Formulas.fusionStars")
end

-- Mutation au plus gros multiplicateur (0 si aucune)
function Formulas.bestMutation(m1: number, m2: number): number
	local _ = { m1, m2 }
	error("TODO(logic): Formulas.bestMutation")
end

-- Étape k : ComboSeconds × k × revenu du squishy obtenu
function Formulas.comboReward(step: number, income: number): number
	local _ = { step, income }
	error("TODO(logic): Formulas.comboReward")
end

-- max(Min, floor(Seconds × revenu du squishy))
function Formulas.sellValue(income: number): number
	local _ = { income }
	error("TODO(logic): Formulas.sellValue")
end

-- Récompense « en secondes de revenu » (entier, ≥ minimum)
function Formulas.secondsOfIncome(income: number, seconds: number, minimum: number?): number
	local _ = { income, seconds, minimum }
	error("TODO(logic): Formulas.secondsOfIncome")
end

-- Objectif de taille pour passer de R à R + 1 (table, puis × 2,7 arrondi à 2 chiffres significatifs)
function Formulas.splorchTarget(R: number): number
	local _ = { R }
	error("TODO(logic): Formulas.splorchTarget")
end

-- Absence comptée, bornée à la limite (8 h, 12 h Lit douillet, + 1 h Spiky) ; 0 au premier chargement
function Formulas.offlineSeconds(
	nowUnix: number,
	lastOnline: number,
	cozyBed: boolean,
	spikyFamily: boolean
): number
	local _ = { nowUnix, lastOnline, cozyBed, spikyFamily }
	error("TODO(logic): Formulas.offlineSeconds")
end

-- Croissance cumulée gagnée hors ligne (× GrowthShare)
function Formulas.offlineGrowth(gNoBoost: number, seconds: number): number
	local _ = { gNoBoost, seconds }
	error("TODO(logic): Formulas.offlineGrowth")
end

-- Pièces hors ligne versées au Pot (× PotShare)
function Formulas.offlinePot(incomeNoBoost: number, seconds: number): number
	local _ = { incomeNoBoost, seconds }
	error("TODO(logic): Formulas.offlinePot")
end

-- Taille d'un bébé ou d'un cadeau : part (de l'original, sinon du plus gros du receveur), ≥ minimum, ≤ 2 × plus gros du receveur
function Formulas.babySize(share: number, minimum: number, receiverBiggest: number, original: number?): number
	local _ = { share, minimum, receiverBiggest, original }
	error("TODO(logic): Formulas.babySize")
end

-- Selle gagnée 0 … 3 (record ≥ 1 200, 1e6, 1e12)
function Formulas.saddleLevel(biggestEver: number): number
	local _ = { biggestEver }
	error("TODO(logic): Formulas.saddleLevel")
end

-- WalkSpeed, JumpHeight, HipHeight et échelle affichée de la monture
function Formulas.rideStats(saddle: number): RideStats
	local _ = { saddle }
	error("TODO(logic): Formulas.rideStats")
end

-- Palier de l'Étagère 0 … 4 (bronze, argent, or, cristal)
function Formulas.trophyTier(record: number): number
	local _ = { record }
	error("TODO(logic): Formulas.trophyTier")
end

-- Bonus additif de l'Étagère (somme des paliers, + 208 % au plus)
function Formulas.trophyBonus(trophies: { number }): number
	local _ = { trophies }
	error("TODO(logic): Formulas.trophyBonus")
end

-- Pièces d'un paquet (minutes du revenu actuel, minimum du paquet)
function Formulas.coinPack(income: number, productKey: string): number
	local _ = { income, productKey }
	error("TODO(logic): Formulas.coinPack")
end

-- Aperçu du Grand Splorch à partir d'un profil (même calcul côté serveur et client)
function Formulas.splorchPreview(data: { [string]: any }, ctx: PreviewCtx): Types.SplorchPreview
	local _ = { data, ctx }
	error("TODO(logic): Formulas.splorchPreview")
end

return Formulas
