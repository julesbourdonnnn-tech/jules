--!strict
-- Hash — paquet « logic » (STUB du contrat : docs/04-architecture.md §12.1).
-- PRNG entier DÉTERMINISTE, identique sous Lune et sous Roblox (arithmétique entière + bit32,
-- jamais math.random ni Random.new) : météo, Comète, quêtes du jour, flânerie, dispersion.
-- Responsabilités :
--   * u32(...)          mélange d'une suite d'entiers (splitmix/xorshift32) → [0, 2^32[
--   * unit(...)         u32 / 2^32 ∈ [0, 1[
--   * int / range       tirages bornés dérivés de unit
--   * pickWeighted      index tiré selon des poids cumulés (somme quelconque > 0)
--   * string(s)         FNV-1a 32 bits (codes, clés)
--   * stream(seed)      générateur séquentiel (xorshift32) pour les tirages en série
-- GDD : §4.15.1 (Hash.u32(créneau, SEL) / 2³²), §5.1 (rotations), §7.5 (Hash(jour, UserId)), §12.9 (Hash.spec :
-- valeurs de référence figées dans la spec).
-- Dépendances : aucune.

local Hash = {}

export type Stream = {
	next: (self: Stream) -> number, -- [0, 1[
	int: (self: Stream, min: number, max: number) -> number, -- entier dans [min, max]
	range: (self: Stream, min: number, max: number) -> number, -- réel dans [min, max[
}

-- Mélange déterministe d'entiers (les réels sont tronqués) → entier dans [0, 2^32[
function Hash.u32(...: number): number
	local _ = select("#", ...)
	error("TODO(logic): Hash.u32")
end

-- Réel dans [0, 1[
function Hash.unit(...: number): number
	local _ = select("#", ...)
	error("TODO(logic): Hash.unit")
end

-- Entier dans [min, max] tiré des clés
function Hash.int(_min: number, _max: number, ...: number): number
	local _ = select("#", ...)
	error("TODO(logic): Hash.int")
end

-- Réel dans [min, max[ tiré des clés
function Hash.range(_min: number, _max: number, ...: number): number
	local _ = select("#", ...)
	error("TODO(logic): Hash.range")
end

-- Index (1-based) choisi selon des poids cumulés, r ∈ [0, 1[
function Hash.pickWeighted(_weights: { number }, _r: number): number
	error("TODO(logic): Hash.pickWeighted")
end

-- FNV-1a 32 bits d'une chaîne
function Hash.string(_s: string): number
	error("TODO(logic): Hash.string")
end

function Hash.stream(_seed: number): Stream
	error("TODO(logic): Hash.stream")
end

return Hash
