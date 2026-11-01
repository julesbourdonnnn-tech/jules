--!strict
-- FusionRules (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Jumeaux, fusion, chaîne de combo et « Tout fusionner » (GDD §4.10). Pur : le service applique.
-- Jumeaux = même espèce ET même nombre d'étoiles. Fusion : taille (a + b) × 1,25, étoiles + 1 (5 au
-- plus), meilleure mutation ; Meilleur Ami, tenue et verrou gardés si l'un des deux les avait.
-- Invariant (propriétés) : une fusion retire exactement un squishy (2 → 1), jamais de taille NaN.

local Types = require(script.Parent.Parent.Types)

local FusionRules = {}

-- Même espèce et mêmes étoiles
function FusionRules.areTwins(a: Types.SquishyRecord, b: Types.SquishyRecord): boolean
	local _ = { a, b }
	error("TODO(logic): FusionRules.areTwins")
end

-- Résultat de la fusion (nouvelle ligne, marque zg = G)
function FusionRules.fuse(
	a: Types.SquishyRecord,
	b: Types.SquishyRecord,
	G: number,
	unix: number
): Types.SquishyRecord
	local _ = { a, b, G, unix }
	error("TODO(logic): FusionRules.fuse")
end

-- uid gardé par le résultat (Meilleur Ami d'abord, puis le plus ancien)
function FusionRules.keepUid(
	uidA: string,
	uidB: string,
	a: Types.SquishyRecord,
	b: Types.SquishyRecord
): string
	local _ = { uidA, uidB, a, b }
	error("TODO(logic): FusionRules.keepUid")
end

-- Jumeau du résultat qui attend dans le Bassin (étape suivante du combo)
function FusionRules.nextInChain(pool: { [string]: Types.SquishyRecord }, resultUid: string): string?
	local _ = { pool, resultUid }
	error("TODO(logic): FusionRules.nextInChain")
end

-- Effet d'un lancer dans le Bassin
function FusionRules.throwOutcome(
	pool: { [string]: Types.SquishyRecord },
	rec: Types.SquishyRecord,
	slots: number
): "fuse" | "place" | "full"
	local _ = { pool, rec, slots }
	error("TODO(logic): FusionRules.throwOutcome")
end

-- Nombre de paires de jumeaux (pastille « ♥ N »), hors Lettres et hors verrouillés
function FusionRules.twinPairs(records: { [string]: Types.SquishyRecord }): number
	local _ = { records }
	error("TODO(logic): FusionRules.twinPairs")
end

-- Plan déterministe de « Tout fusionner » : liste ordonnée de paires { uidA, uidB } pour les plus longs combos, verrouillés exclus
function FusionRules.planMergeAll(records: { [string]: Types.SquishyRecord }, slots: number): { { string } }
	local _ = { records, slots }
	error("TODO(logic): FusionRules.planMergeAll")
end

return FusionRules
