--!strict
-- Odds (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Tirages des naissances, déterministes et graines contrôlées (GDD §4.5, §4.9, §4.11, §4.21.5, §4.22).
-- Tables affichées = tables tirées : rareté (Balance.Vat.Quality), espèce à chances égales parmi les
-- familles débloquées (rareté juste en dessous si vide), mutation (Config/Mutations, buses, Jelly
-- Moon), protection contre la malchance (40 / 150), nouveauté garantie (3 premiers tirages), Secrets
-- (Royal Plop ; pendant la Lune, Royal ou Moonplop). Aucun achat ne change une probabilité (GDD §8.1).

local Hash = require(script.Parent.Hash)

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
	usedNewPull: boolean,
}

local Odds = {}

-- Familles de la Cuve débloquées à ce R (Jelly, Kitty, Froggy ; Axolo R ≥ 1 ; Bunny R ≥ 3 ; Spiky R ≥ 5)
function Odds.unlockedFamilies(R: number): { [string]: boolean }
	local _ = { R }
	error("TODO(logic): Odds.unlockedFamilies")
end

-- Pourcentages par rareté (1 … 7) de la table de qualité
function Odds.rarityTable(quality: number): { number }
	local _ = { quality }
	error("TODO(logic): Odds.rarityTable")
end

-- Rareté tirée avec r dans [0 ; 1[ et la protection contre la malchance
function Odds.rollRarity(quality: number, r: number, pityRare: number, pityEpic: number): number
	local _ = { quality, r, pityRare, pityEpic }
	error("TODO(logic): Odds.rollRarity")
end

-- Chances effectives par mutation (fraction) : buses, Lune (× 2, Lunaire 3 %), multiplicateur (MEGA, Goutte chanceuse)
function Odds.mutationChances(nozzles: number, moon: boolean, mult: number?): { [number]: number }
	local _ = { nozzles, moon, mult }
	error("TODO(logic): Odds.mutationChances")
end

-- Mutation tirée (0 = aucune) : comparée aux chances cumulées depuis la plus rare
function Odds.rollMutation(r: number, nozzles: number, moon: boolean, mult: number?): number
	local _ = { r, nozzles, moon, mult }
	error("TODO(logic): Odds.rollMutation")
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
	local _ = { rarity, families, owned, preferNew, r, unix, moon }
	error("TODO(logic): Odds.speciesFor")
end

-- Naissance complète (rareté, espèce, mutation, « 1 sur X », compteurs de protection)
function Odds.roll(rng: Hash.Stream, ctx: RollCtx): RollResult
	local _ = { rng, ctx }
	error("TODO(logic): Odds.roll")
end

-- Étiquette « 1 sur X » d'une naissance, calculée aux réglages du moment (2 chiffres significatifs)
function Odds.oneIn(rarity: number, mutation: number, quality: number, nozzles: number, moon: boolean): number
	local _ = { rarity, mutation, quality, nozzles, moon }
	error("TODO(logic): Odds.oneIn")
end

-- Graine déterministe du tirage n° counter d'un joueur
function Odds.seed(userId: number, counter: number): number
	local _ = { userId, counter }
	error("TODO(logic): Odds.seed")
end

return Odds
