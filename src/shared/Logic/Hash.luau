--!strict
-- Hash — paquet « logic » (docs/04-architecture.md §12.1).
-- PRNG entier DÉTERMINISTE, identique sous Lune et sous Roblox (arithmétique entière exacte en
-- double + bit32, jamais math.random ni Random.new) : météo, Comète, quêtes du jour, flânerie,
-- dispersion, décor.
--   * u32(...)          mélange d'une suite de nombres (MurmurHash3 32 bits sur des mots) → [0, 2^32[
--   * unit(...)         u32 / 2^32 ∈ [0, 1[
--   * int / range       tirages bornés dérivés de unit
--   * pickWeighted      index tiré selon des poids cumulés (somme quelconque > 0)
--   * string(s)         FNV-1a 32 bits (codes, clés)
--   * stream(seed)      générateur séquentiel (xorshift32) pour les tirages en série
-- GDD : §4.15.1 (Hash.u32(créneau, SEL) / 2³²), §5.1 (rotations), §7.5 (Hash(jour, UserId)),
-- §12.9 (Hash.spec : valeurs de référence figées dans la spec).
-- Dépendances : aucune.
--
-- Conversion des clés : un réel est tronqué vers zéro ; le mot bas est la valeur modulo 2^32 ; une
-- valeur négative ou ≥ 2^32 ajoute un second mot (partie haute modulo 2^32, donc -1 ≠ 2^32 − 1) ;
-- NaN et ±inf valent 0. Jamais d'erreur.

local Hash = {}

export type Stream = {
	next: (self: Stream) -> number, -- [0, 1[
	int: (self: Stream, min: number, max: number) -> number, -- entier dans [min, max]
	range: (self: Stream, min: number, max: number) -> number, -- réel dans [min, max[
}

local TWO32 = 4294967296
local TWO16 = 65536
local SEED = 0x9747B28C -- graine initiale de Murmur (constante figée : changer = changer TOUS les tirages)
local C1 = 0xCC9E2D51
local C2 = 0x1B873593
local FNV_OFFSET = 0x811C9DC5
local FNV_PRIME = 0x01000193

-- Produit modulo 2^32 exact (les doubles ne gardent que 53 bits : on découpe en 16 bits)
local function mul32(a: number, b: number): number
	local aLo = a % TWO16
	local aHi = (a - aLo) / TWO16
	local bLo = b % TWO16
	local bHi = (b - bLo) / TWO16
	local cross = (aHi * bLo + aLo * bHi) % TWO16
	return (aLo * bLo + cross * TWO16) % TWO32
end

-- Mélange final de Murmur3 (avalanche complète)
local function fmix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

local function mixWord(h: number, k: number): number
	k = mul32(k, C1)
	k = bit32.lrotate(k, 15)
	k = mul32(k, C2)
	h = bit32.bxor(h, k)
	h = bit32.lrotate(h, 13)
	return (mul32(h, 5) + 0xE6546B64) % TWO32
end

-- Mélange d'une clé numérique ; retourne (h, nombre de mots mélangés)
local function mixKey(h: number, x: any): (number, number)
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return mixWord(h, 0), 1
	end
	local n = if x >= 0 then math.floor(x) else -math.floor(-x) -- troncature vers zéro
	local lo = n % TWO32
	local hi = math.floor(n / TWO32)
	if hi == 0 then
		return mixWord(h, lo), 1
	end
	-- valeur hors de [0, 2^32[ : on ajoute la partie haute (modulo 2^32) comme second mot
	return mixWord(mixWord(h, lo), hi % TWO32), 2
end

-- Mélange déterministe d'entiers (les réels sont tronqués) → entier dans [0, 2^32[
function Hash.u32(...: number): number
	local h = SEED
	local words = 0
	for i = 1, select("#", ...) do
		local used
		h, used = mixKey(h, (select(i, ...)))
		words += used
	end
	h = bit32.bxor(h, (words * 4) % TWO32)
	return fmix(h)
end

-- Réel dans [0, 1[
function Hash.unit(...: number): number
	return Hash.u32(...) / TWO32
end

-- Entier dans [min, max] tiré des clés (bornes arrondies vers l'intérieur, ordre indifférent)
function Hash.int(min: number, max: number, ...: number): number
	local lo = math.ceil(math.min(min, max))
	local hi = math.floor(math.max(min, max))
	if hi <= lo then
		return lo
	end
	local v = lo + math.floor(Hash.unit(...) * (hi - lo + 1))
	return if v > hi then hi else v
end

-- Réel dans [min, max[ tiré des clés
function Hash.range(min: number, max: number, ...: number): number
	return min + (max - min) * Hash.unit(...)
end

-- Index (1-based) choisi selon des poids cumulés, r ∈ [0, 1[. Les poids nuls, négatifs ou non
-- finis ne sont jamais choisis ; sans aucun poids positif, retourne 1.
function Hash.pickWeighted(weights: { number }, r: number): number
	local total = 0
	for _, w in weights do
		if w == w and w > 0 and w ~= math.huge then
			total += w
		end
	end
	if total <= 0 then
		return 1
	end
	if r ~= r or r < 0 then
		r = 0
	elseif r >= 1 then
		r = 1 - 1e-12
	end
	local target = r * total
	local acc = 0
	local last = 1
	for i, w in weights do
		if w == w and w > 0 and w ~= math.huge then
			acc += w
			last = i
			if target < acc then
				return i
			end
		end
	end
	return last -- arrondi flottant : dernier poids positif
end

-- FNV-1a 32 bits d'une chaîne
function Hash.string(s: string): number
	local h = FNV_OFFSET
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, FNV_PRIME)
	end
	return h
end

-- Générateur séquentiel xorshift32 (graine mélangée par u32, jamais nulle)
local StreamImpl = {}
StreamImpl.__index = StreamImpl

function StreamImpl.next(self: any): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x / TWO32
end

function StreamImpl.int(self: any, min: number, max: number): number
	local lo = math.ceil(math.min(min, max))
	local hi = math.floor(math.max(min, max))
	if hi <= lo then
		self:next() -- la suite avance toujours d'un pas par tirage
		return lo
	end
	local v = lo + math.floor(self:next() * (hi - lo + 1))
	return if v > hi then hi else v
end

function StreamImpl.range(self: any, min: number, max: number): number
	return min + (max - min) * self:next()
end

function Hash.stream(seed: number): Stream
	local state = Hash.u32(seed)
	if state == 0 then
		state = 0x6D2B79F5
	end
	return setmetatable({ state = state }, StreamImpl) :: any
end

return Hash
