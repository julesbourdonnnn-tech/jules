--!strict
-- Bitset (paquet A1, docs/04 §27.2, §27.7). Ensembles de bits sauvegardés dans le profil v2 :
-- tableau DENSE de mots de 32 bits ({number}, longueur ceil(n / 32), au moins 1), lu et écrit
-- SEULEMENT par ce module (jamais un number de 64 bits : bit32 travaille sur 32 bits).
-- Bits numérotés à partir de 1 : le bit i est dans le mot ceil(i / 32), à la position (i − 1) % 32.
-- Pur, déterministe, même module sur le client et le serveur. Robuste par construction : un indice
-- illisible (NaN, ±inf, non entier, ≤ 0, > MaxBits) n'est jamais un bit ; un mot abîmé (NaN,
-- négatif, non entier, ≥ 2^32, autre type, trou) vaut 0 à la lecture et est remis à un entier sûr
-- à l'écriture. Jamais d'erreur.
-- Utilisé par : atelierCosmetics (11), carnet (8), weeklyTrack.claimed (12), mastery (une par
-- espèce, agrandi par grow), decoPerso.owned (64). Bitset.spec : bords des mots 31/32/33, 64,
-- 200 espèces et 64 objets à travers JSON et reconcile.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, bit32, table = type, math, bit32, table

local Bitset = {}

-- Bits par mot et plus grand ensemble accepté (le plus grand du jeu : une maîtrise par espèce, une
-- centaine à long terme ; 4 096 bits = 128 mots laisse une marge sans laisser un indice hostile
-- créer des millions de mots)
Bitset.WordBits = 32
Bitset.MaxBits = 4096

local WORD = 4294967296 -- 2^32
local MAX_WORDS = Bitset.MaxBits // Bitset.WordBits

local band, bor, bnot, lshift = bit32.band, bit32.bor, bit32.bnot, bit32.lshift
local floor, ceil = math.floor, math.ceil

-- Mot sûr : entier de [0 ; 2^32[, sinon 0
local function word(x: any): number
	if type(x) ~= "number" or x ~= x or x < 0 or x >= WORD or x % 1 ~= 0 then
		return 0
	end
	return x
end

-- Indice de bit valide (entier de [1 ; MaxBits]) ou nil
local function index(i: any): number?
	if type(i) ~= "number" or i ~= i or i % 1 ~= 0 or i < 1 or i > Bitset.MaxBits then
		return nil
	end
	return i
end

-- Nombre de mots pour n bits (au moins 1, au plus MAX_WORDS) ; n illisible → 1
local function wordsFor(n: any): number
	if type(n) ~= "number" or n ~= n or n < 1 then
		return 1
	end
	if n > Bitset.MaxBits then
		return MAX_WORDS
	end
	return math.max(1, ceil(n / Bitset.WordBits))
end

-- Masque du bit i dans son mot
local function maskOf(i: number): (number, number)
	local w = (i - 1) // Bitset.WordBits + 1
	return w, lshift(1, (i - 1) % Bitset.WordBits)
end

-- Nombre de mots d'un ensemble de n bits (lecture : schéma, réparation)
function Bitset.words(n: number): number
	return wordsFor(n)
end

-- Ensemble vide de n bits : ceil(n / 32) mots à 0 (au moins 1)
function Bitset.new(n: number): { number }
	return table.create(wordsFor(n), 0)
end

-- Vrai si le bit i est posé (indice illisible ou hors de l'ensemble : faux)
function Bitset.has(set: { number }, i: number): boolean
	local k = index(i)
	if k == nil or type(set) ~= "table" then
		return false
	end
	local w, m = maskOf(k)
	return band(word(set[w]), m) ~= 0
end

-- Allonge l'ensemble à n bits au moins (mots ajoutés à 0, trous et mots abîmés remis à un entier
-- sûr) ; ne raccourcit jamais (un bit posé n'est jamais perdu)
function Bitset.grow(set: { number }, n: number)
	if type(set) ~= "table" then
		return
	end
	local want = math.max(wordsFor(n), #set)
	want = math.min(want, MAX_WORDS)
	for w = 1, want do
		set[w] = word(set[w])
	end
end

-- Pose le bit i (allonge l'ensemble au besoin, sans trou) ; indice illisible : rien
function Bitset.set(set: { number }, i: number)
	local k = index(i)
	if k == nil or type(set) ~= "table" then
		return
	end
	Bitset.grow(set, k)
	local w, m = maskOf(k)
	set[w] = bor(word(set[w]), m)
end

-- Enlève le bit i ; indice illisible ou hors de l'ensemble : rien
function Bitset.clear(set: { number }, i: number)
	local k = index(i)
	if k == nil or type(set) ~= "table" then
		return
	end
	local w, m = maskOf(k)
	if set[w] == nil then
		return
	end
	set[w] = band(word(set[w]), bnot(m))
end

-- Nombre de bits posés (mots abîmés comptés pour 0)
function Bitset.count(set: { number }): number
	if type(set) ~= "table" then
		return 0
	end
	local total = 0
	for w = 1, math.min(#set, MAX_WORDS) do
		local x = word(set[w])
		-- comptage de Kernighan : une itération par bit posé
		while x ~= 0 do
			x = band(x, x - 1)
			total += 1
		end
	end
	return total
end

-- Nombre de bits posés parmi first … first + n − 1 (lignes de « Pour le plaisir »)
function Bitset.countRange(set: { number }, first: number, n: number): number
	local a = index(first)
	if a == nil or type(n) ~= "number" or n ~= n or n < 1 then
		return 0
	end
	local total = 0
	for i = a, math.min(Bitset.MaxBits, a + floor(math.min(n, Bitset.MaxBits)) - 1) do
		if Bitset.has(set, i) then
			total += 1
		end
	end
	return total
end

return Bitset
