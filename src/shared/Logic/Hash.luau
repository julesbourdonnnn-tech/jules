--!strict
-- Hash (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Hachage déterministe et hasard contrôlé (repris de Comet Conga, GDD §12.2). Même résultat sur le
-- serveur, le client et sous Lune : graines des tirages (Odds), trajets (SeededPath), décalage du
-- PERFECT (PressTiming), alias « Squishy Fan #NNNN » (nom caché, GDD §6.9).

export type Stream = {
	next: (self: any) -> number,
	int: (self: any, min: number, max: number) -> number,
	range: (self: any, min: number, max: number) -> number,
}

local Hash = {}

-- Hachage 32 bits (murmur3) de nombres entiers ou réels finis
function Hash.u32(...: number): number
	local _ = { ... }
	error("TODO(logic): Hash.u32")
end

-- Réel déterministe dans [0 ; 1[
function Hash.unit(...: number): number
	local _ = { ... }
	error("TODO(logic): Hash.unit")
end

-- Entier déterministe dans [min ; max]
function Hash.int(min: number, max: number, ...: number): number
	local _ = { min, max, ... }
	error("TODO(logic): Hash.int")
end

-- Réel déterministe dans [min ; max[
function Hash.range(min: number, max: number, ...: number): number
	local _ = { min, max, ... }
	error("TODO(logic): Hash.range")
end

-- Index tiré dans des poids positifs avec r dans [0 ; 1[
function Hash.pickWeighted(weights: { number }, r: number): number
	local _ = { weights, r }
	error("TODO(logic): Hash.pickWeighted")
end

-- Hachage 32 bits d'une chaîne (FNV-1a)
function Hash.string(s: string): number
	local _ = { s }
	error("TODO(logic): Hash.string")
end

-- Flux pseudo-aléatoire déterministe (:next() dans [0 ; 1[, :int, :range)
function Hash.stream(seed: number): Stream
	local _ = { seed }
	error("TODO(logic): Hash.stream")
end

-- Numéro d'alias à 4 chiffres [1000 ; 9999] d'un joueur au nom caché
function Hash.alias(userId: number): number
	local _ = { userId }
	error("TODO(logic): Hash.alias")
end

return Hash
