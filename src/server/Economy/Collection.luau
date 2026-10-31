--!strict
-- Collection — aides PURES du paquet « economy » (aucun service Roblox, aucune horloge).
-- Utilisées par AtlasService (tri des perchoirs, Atlas, Starforge) et NestService (déblocages
-- d'Atlas). Testées par tests/specs/AtlasService.spec.luau.
--
-- Règle de tri des perchoirs (GDD §4.9, docs/04-architecture.md §11.6) — à reproduire à
-- l'identique côté client pour afficher les perchés :
--   1. revenu passif décroissant (Formulas.passiveIncome, étoiles comprises)
--   2. à égalité : rareté décroissante
--   3. puis numéro d'uid croissant (le plus ancien d'abord)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Nebbies = require(Shared.Config.Nebbies)
local Formulas = require(Shared.Logic.Formulas)
local Types = require(Shared.Types)

local Collection = {}

-- Bits d'Atlas réservés : 36 espèces × 6 formes
local ATLAS_BITS = Nebbies.SPECIES_COUNT * Nebbies.FORM_COUNT

-- Numéro d'un uid "u<n>" (math.huge si l'uid est mal formé : classé en dernier)
function Collection.uidNumber(uid: string): number
	local n = tonumber(string.sub(uid, 2))
	if string.sub(uid, 1, 1) ~= "u" or n == nil or n ~= n then
		return math.huge
	end
	return n
end

-- Enregistrement exploitable : espèce, forme, variantes et étoiles entiers dans leurs bornes
function Collection.isValidRecord(rec: any): boolean
	if type(rec) ~= "table" then
		return false
	end
	local s, f, v, st = rec.s, rec.f, rec.v, rec.st
	return type(s) == "number"
		and s % 1 == 0
		and s >= 1
		and s <= Nebbies.SPECIES_COUNT
		and type(f) == "number"
		and f % 1 == 0
		and f >= 0
		and f < Nebbies.FORM_COUNT
		and type(v) == "number"
		and v % 1 == 0
		and v >= 0
		and v < 8
		and type(st) == "number"
		and st % 1 == 0
		and st >= 1
		and st <= Nebbies.MAX_STARS
end

-- Code réseau (12 bits) d'un enregistrement
function Collection.codeOf(rec: Types.NebbyRecord): number
	return Nebbies.pack(rec.s, rec.f, rec.v)
end

-- Clé de groupe Starforge : mêmes espèce, forme, variantes ET étoiles
function Collection.groupKey(rec: Types.NebbyRecord): number
	return Collection.codeOf(rec) * 8 + rec.st
end

export type Ranked = {
	uids: { string }, -- ordre des perchoirs (meilleur d'abord)
	income: { [string]: number }, -- revenu passif (sans M) de chaque uid
}

-- Classe toute la collection selon la règle des perchoirs
function Collection.rank(nebbies: { [string]: any }): Ranked
	local uids: { string } = {}
	local income: { [string]: number } = {}
	local rarity: { [string]: number } = {}
	local number: { [string]: number } = {}
	for uid, rec in nebbies do
		if type(uid) == "string" and Collection.isValidRecord(rec) then
			table.insert(uids, uid)
			income[uid] = Formulas.passiveIncome(rec)
			rarity[uid] = Nebbies.rarityOf(rec.s)
			number[uid] = Collection.uidNumber(uid)
		end
	end
	table.sort(uids, function(a: string, b: string): boolean
		local ia, ib = income[a], income[b]
		if ia ~= ib then
			return ia > ib
		end
		local ra, rb = rarity[a], rarity[b]
		if ra ~= rb then
			return ra > rb
		end
		local na, nb = number[a], number[b]
		if na ~= nb then
			return na < nb
		end
		return a < b
	end)
	return { uids = uids, income = income }
end

-- Nombre d'entrées d'Atlas posées (bits 0 … 215 ; les bits au-delà sont ignorés)
function Collection.atlasCount(words: { number }?): number
	if type(words) ~= "table" then
		return 0
	end
	local count = 0
	for index = 0, ATLAS_BITS - 1 do
		local word = words[index // 32 + 1]
		if type(word) == "number" and bit32.btest(word, bit32.lshift(1, index % 32)) then
			count += 1
		end
	end
	return count
end

-- Toutes les formes ACTIVÉES de l'espèce `s` sont-elles dans l'Atlas ?
function Collection.isSpeciesComplete(words: { number }, s: number): boolean
	if not Nebbies.isSpeciesEnabled(s) then
		return false
	end
	for _, f in Nebbies.enabledForms() do
		if not Nebbies.testBit(words, Nebbies.atlasIndex(s, f)) then
			return false
		end
	end
	return true
end

-- Somme des `perches` plus grandes valeurs de `values` (triées par ordre décroissant)
function Collection.topSum(values: { number }, perches: number): number
	local sum = 0
	for i = 1, math.min(perches, #values) do
		sum += values[i]
	end
	return sum
end

-- Somme des `perches` meilleures valeurs APRÈS une fusion : `consumed` occurrences de `a` retirées
-- et une valeur `b` ajoutée. `values` est trié par ordre décroissant et n'est pas modifié.
-- Coût O(perches + consumed) : évalue chaque fusion candidate sans retrier la collection.
function Collection.topSumAfter(
	values: { number },
	perches: number,
	a: number,
	consumed: number,
	b: number
): number
	local sum = 0
	local taken = 0
	local skipped = 0
	local inserted = false
	local i = 1
	while taken < perches do
		local v = values[i]
		if not inserted and (v == nil or b >= v) then
			sum += b
			taken += 1
			inserted = true
		elseif v == nil then
			break
		else
			if skipped < consumed and v == a then
				skipped += 1
			else
				sum += v
				taken += 1
			end
			i += 1
		end
	end
	return sum
end

-- Sommes préfixes des `count` premières valeurs : prefix[k] = values[1] + … + values[k]
function Collection.prefixSums(values: { number }, count: number): { number }
	local prefix: { number } = {}
	local sum = 0
	for i = 1, math.min(count, #values) do
		sum += values[i]
		prefix[i] = sum
	end
	return prefix
end

-- Même résultat que topSumAfter, en O(log n) : `prefix` = Collection.prefixSums(values, perches +
-- consumed) ; `values` (trié décroissant) contient au moins `consumed` fois la valeur `a`.
-- Retirer `consumed` occurrences de `a` revient à retirer le bloc qui commence au premier `a`.
function Collection.fusionTopSum(
	values: { number },
	prefix: { number },
	perches: number,
	a: number,
	consumed: number,
	b: number
): number
	local n = #values
	if perches <= 0 then
		return 0
	end
	local function sumTo(k: number): number
		k = math.min(k, n)
		return if k <= 0 then 0 else prefix[k]
	end
	-- premier indice dont la valeur ne dépasse pas `a`
	local lo, hi = 1, n
	while lo <= hi do
		local mid = (lo + hi) // 2
		if values[mid] > a then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	local first = lo
	-- somme des `perches` meilleures après le retrait, et la plus petite d'entre elles (`kth`)
	local rest: number
	local kth: number?
	if perches < first then
		rest = sumTo(perches)
		kth = values[perches]
	else
		rest = sumTo(perches + consumed) - consumed * a
		kth = values[perches + consumed]
	end
	if kth == nil then
		return rest + b -- un perchoir libre accueille le résultat
	elseif b > kth then
		return rest - kth + b
	end
	return rest
end

-- Ordre d'âge des uids (le plus ancien d'abord), total : numéro puis chaîne
function Collection.olderFirst(a: string, b: string): boolean
	local na, nb = Collection.uidNumber(a), Collection.uidNumber(b)
	if na ~= nb then
		return na < nb
	end
	return a < b
end

-- Insère `uid` dans `list` (triée par Collection.olderFirst) sans retrier
function Collection.insertByAge(list: { string }, uid: string)
	local lo, hi = 1, #list
	while lo <= hi do
		local mid = (lo + hi) // 2
		if Collection.olderFirst(list[mid], uid) then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	table.insert(list, lo, uid)
end

-- Retire `count` occurrences de `a` puis insère `b` dans `values` (trié décroissant), en place
function Collection.applyFusion(values: { number }, a: number, count: number, b: number)
	local removed = 0
	local i = #values
	while i >= 1 and removed < count do
		if values[i] == a then
			table.remove(values, i)
			removed += 1
		end
		i -= 1
	end
	local at = #values + 1
	for j, v in values do
		if b >= v then
			at = j
			break
		end
	end
	table.insert(values, at, b)
end

-- Liste d'uids venant d'un client : table séquentielle (#t = nombre de clés) de 1 à `maxCount`
-- chaînes non vides de `maxLength` caractères au plus, toutes différentes. nil si invalide.
function Collection.validUidList(t: unknown, maxCount: number, maxLength: number): { string }?
	if type(t) ~= "table" then
		return nil
	end
	local list = t :: { [any]: any }
	local keys = 0
	for _ in list do
		keys += 1
		if keys > maxCount then
			return nil
		end
	end
	local n = #list
	if n < 1 or n ~= keys then
		return nil
	end
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for i = 1, n do
		local uid = list[i]
		if type(uid) ~= "string" or #uid == 0 or #uid > maxLength or seen[uid] then
			return nil
		end
		seen[uid] = true
		out[i] = uid
	end
	return out
end

return Collection
