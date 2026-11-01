--!strict
-- FusionRules (paquet logic, docs/04 §12.1). Jumeaux, fusion, chaîne de combo et « Tout
-- fusionner » (GDD §4.10). Pur : le service applique.
--   * Jumeaux = même espèce ET même nombre d'étoiles (la mutation peut différer).
--   * Fusion : taille (a + b) × 1,25, étoiles + 1 (5 au plus), meilleure mutation ; Meilleur Ami,
--     tenue et verrou gardés si l'un des deux les avait ; la ligne gardée est celle de keepUid
--     (Meilleur Ami d'abord, puis le plus ancien) : le résultat garde sa naissance `b` et son `gd` (jour
--     du dernier bonus de croissance du Rush, contrat v1.2). Lieu du résultat : Bassin si l'un des deux
--     y est (combo), sinon l'enclos si l'un des deux y est (sa place est libérée), sinon celui de la
--     ligne gardée (Dodo) ; le service le met ensuite dans l'enclos s'il y a de la place (GDD §4.10).
--   * Combo : après chaque fusion, un jumeau du résultat qui attend dans le Bassin fusionne à son
--     tour (nextInChain).
--   * Tout fusionner : plan déterministe (planMergeAll) qui fait les plus longues chaînes possibles
--     dans les places du Bassin, verrouillés et Lettres exclus. Une paire dont le premier uid est
--     l'uid gardé de l'étape précédente CONTINUE le combo (étape k + 1) ; sinon un nouveau combo
--     commence (étape 1).
-- Invariant (propriétés) : une fusion retire exactement un squishy (2 → 1), jamais de taille NaN.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, table = type, math, table

local Types = require(script.Parent.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local Balance = require(script.Parent.Parent.Config.Balance)

local FusionRules = {}

type Record = Types.SquishyRecord

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

local function isRecord(r: any): boolean
	return type(r) == "table" and type(r.s) == "number" and type(r.st) == "number"
end

-- Étoiles entières bornées
local function starsOf(r: any): number
	return math.clamp(math.floor(finite(r.st, 0)), 0, Balance.Fusion.MaxStars)
end

-- Emplacement de Meilleur Ami (0 = aucun)
local function bfOf(r: any): number
	local bf = math.floor(finite(r.bf, 0))
	return if bf > 0 then bf else 0
end

-- Ordre des uid : plus court puis alphabétique (base 36 : ordre de création)
local function uidBefore(a: string, b: string): boolean
	if #a ~= #b then
		return #a < #b
	end
	return a < b
end

-- Uids d'une table triés (déterministe, jamais l'ordre de parcours d'une table)
local function sortedUids(records: { [string]: Record }): { string }
	local list = {}
	for uid in records do
		if type(uid) == "string" then
			table.insert(list, uid)
		end
	end
	table.sort(list, uidBefore)
	return list
end

-- Même espèce et mêmes étoiles
function FusionRules.areTwins(a: Types.SquishyRecord, b: Types.SquishyRecord): boolean
	if not isRecord(a) or not isRecord(b) then
		return false
	end
	return a.s == b.s and starsOf(a) == starsOf(b)
end

-- uid gardé par le résultat (Meilleur Ami d'abord, puis le plus ancien)
function FusionRules.keepUid(
	uidA: string,
	uidB: string,
	a: Types.SquishyRecord,
	b: Types.SquishyRecord
): string
	local ra: any = if type(a) == "table" then a else {}
	local rb: any = if type(b) == "table" then b else {}
	local bfA, bfB = bfOf(ra), bfOf(rb)
	if bfA > 0 and bfB == 0 then
		return uidA
	elseif bfB > 0 and bfA == 0 then
		return uidB
	elseif bfA > 0 and bfB > 0 and bfA ~= bfB then
		-- deux Meilleurs Amis : le plus petit emplacement (n° 1 d'abord) garde sa place
		return if bfA < bfB then uidA else uidB
	end
	local birthA, birthB = finite(ra.b, math.huge), finite(rb.b, math.huge)
	if birthA ~= birthB then
		return if birthA < birthB then uidA else uidB
	end
	if type(uidA) ~= "string" then
		return uidB
	end
	if type(uidB) ~= "string" then
		return uidA
	end
	return if uidBefore(uidB, uidA) then uidB else uidA
end

-- Résultat de la fusion (nouvelle ligne, marque zg = G). La naissance est celle de la ligne gardée
-- (keepUid) ; `unix` ne sert que de repli quand aucune naissance n'est lisible.
function FusionRules.fuse(
	a: Types.SquishyRecord,
	b: Types.SquishyRecord,
	G: number,
	unix: number
): Types.SquishyRecord
	local ra: any = if type(a) == "table" then a else {}
	local rb: any = if type(b) == "table" then b else {}
	local g = math.max(0, finite(G, 0))
	local kept = if FusionRules.keepUid("a", "b", ra, rb) == "a" then ra else rb
	local other = if kept == ra then rb else ra

	local bf = bfOf(kept)
	if bf == 0 then
		bf = bfOf(other)
	end
	local outfit = if type(kept.o) == "string" and kept.o ~= "" then kept.o else nil
	if outfit == nil then
		outfit = if type(other.o) == "string" then other.o else ""
	end
	local birth = finite(kept.b, 0)
	if birth <= 0 then
		birth = finite(other.b, 0)
	end
	if birth <= 0 then
		birth = math.max(0, math.floor(finite(unix, 0)))
	end
	local at = if ra.at == "pool" or rb.at == "pool"
		then "pool"
		elseif ra.at == "pen" or rb.at == "pen" then "pen"
		else (kept.at or "pen")
	-- jour du dernier bonus du Rush de la ligne gardée : entier ≥ 0 (illisible : 0)
	local gd = math.max(0, math.floor(finite(kept.gd, 0)))

	return {
		s = if type(kept.s) == "number" then kept.s else (other.s or 1),
		m = Formulas.bestMutation(finite(ra.m, 0), finite(rb.m, 0)),
		st = Formulas.fusionStars(math.max(starsOf(ra), starsOf(rb))),
		z = Formulas.fusionSize(Formulas.sizeAt(ra, g), Formulas.sizeAt(rb, g)),
		zg = g,
		bf = bf,
		lk = ra.lk == true or rb.lk == true,
		o = outfit :: string,
		at = at,
		b = birth,
		gd = gd,
	}
end

-- Jumeau du résultat qui attend dans le Bassin (étape suivante du combo)
function FusionRules.nextInChain(pool: { [string]: Types.SquishyRecord }, resultUid: string): string?
	if type(pool) ~= "table" or type(resultUid) ~= "string" then
		return nil
	end
	local result = pool[resultUid]
	if not isRecord(result) then
		return nil
	end
	for _, uid in sortedUids(pool) do
		local rec: any = pool[uid]
		if uid ~= resultUid and isRecord(rec) and rec.at == "pool" and FusionRules.areTwins(result, rec) then
			return uid
		end
	end
	return nil
end

-- Effet d'un lancer dans le Bassin
function FusionRules.throwOutcome(
	pool: { [string]: Types.SquishyRecord },
	rec: Types.SquishyRecord,
	slots: number
): "fuse" | "place" | "full"
	local waiting = 0
	if type(pool) == "table" then
		for _, other: any in pool do
			if isRecord(other) and other.at == "pool" and other ~= rec then
				if isRecord(rec) and FusionRules.areTwins(rec, other) then
					return "fuse"
				end
				waiting += 1
			end
		end
	end
	if waiting < math.floor(finite(slots, 0)) then
		return "place"
	end
	return "full"
end

-- Ligne qui peut entrer dans « Tout fusionner » ou compter dans la pastille ♥ N
local function mergeable(rec: any): boolean
	return isRecord(rec) and rec.lk ~= true and (rec.at == "pen" or rec.at == "pool" or rec.at == "dodo")
end

-- Nombre de paires de jumeaux (pastille « ♥ N »), hors Lettres et hors verrouillés
function FusionRules.twinPairs(records: { [string]: Types.SquishyRecord }): number
	if type(records) ~= "table" then
		return 0
	end
	local counts: { [string]: number } = {}
	for _, rec: any in records do
		if mergeable(rec) then
			local key = tostring(rec.s) .. ":" .. tostring(starsOf(rec))
			counts[key] = (counts[key] or 0) + 1
		end
	end
	local pairs_ = 0
	for _, n in counts do
		pairs_ += n // 2
	end
	return pairs_
end

-- Plan déterministe de « Tout fusionner » : liste ordonnée de paires { uidA, uidB } pour les plus
-- longs combos, verrouillés exclus. Une chaîne fait au plus `slots` fusions (les jumeaux qui
-- attendent occupent les places du Bassin).
function FusionRules.planMergeAll(records: { [string]: Types.SquishyRecord }, slots: number): { { string } }
	local plan: { { string } } = {}
	if type(records) ~= "table" then
		return plan
	end
	local maxChain = math.max(1, math.floor(finite(slots, Balance.Fusion.PoolSlots)))
	local maxStars = Balance.Fusion.MaxStars

	-- copie légère des lignes utiles, regroupées par espèce puis par étoiles
	local bySpecies: { [number]: { [number]: { string } } } = {}
	local speciesList: { number } = {}
	local work: { [string]: any } = {}
	for _, uid in sortedUids(records) do
		local rec: any = records[uid]
		if mergeable(rec) then
			work[uid] = { s = rec.s, st = starsOf(rec), bf = bfOf(rec), b = rec.b }
			local groups = bySpecies[rec.s]
			if groups == nil then
				groups = {}
				for k = 0, maxStars do
					groups[k] = {}
				end
				bySpecies[rec.s] = groups
				table.insert(speciesList, rec.s)
			end
			table.insert(groups[starsOf(rec)], uid)
		end
	end
	table.sort(speciesList)

	-- retire et rend le premier uid (le plus ancien créé) d'une liste
	local function take(list: { string }): string
		return table.remove(list, 1) :: string
	end
	-- insère en gardant l'ordre des uid
	local function put(list: { string }, uid: string)
		local i = #list + 1
		for j, other in list do
			if uidBefore(uid, other) then
				i = j
				break
			end
		end
		table.insert(list, i, uid)
	end

	local lastKept: string? = nil
	for _, s in speciesList do
		local groups = bySpecies[s]
		while true do
			-- chaîne la plus longue possible depuis chaque niveau d'étoiles (comptage seulement)
			local bestStart, bestLen = -1, 0
			for k = 0, maxStars do
				if #groups[k] >= 2 then
					local used: { [number]: number } = { [k] = 2 }
					local result = math.min(maxStars, k + 1)
					local len = 1
					while len < maxChain do
						local available = #groups[result] - (used[result] or 0)
						if available < 1 then
							break
						end
						used[result] = (used[result] or 0) + 1
						result = math.min(maxStars, result + 1)
						len += 1
					end
					if len > bestLen then
						bestStart, bestLen = k, len
					end
				end
			end
			if bestStart < 0 then
				break
			end

			-- joue la chaîne choisie : chaque paire part de l'uid gardé de l'étape précédente ; la
			-- première paire d'une nouvelle chaîne ne commence jamais par cet uid (sinon elle se lirait
			-- comme une suite du combo précédent)
			local a = take(groups[bestStart])
			local b = take(groups[bestStart])
			local previous = if #plan > 0 then lastKept else nil
			if a == previous then
				a, b = b, a
			end
			local current = FusionRules.keepUid(a, b, work[a], work[b])
			local currentRec = FusionRules.fuse(work[a], work[b], 0, 0) :: any
			table.insert(plan, { a, b })
			for _ = 2, bestLen do
				local partner = take(groups[currentRec.st])
				local next_ = FusionRules.keepUid(current, partner, currentRec, work[partner])
				local merged = FusionRules.fuse(currentRec, work[partner], 0, 0) :: any
				table.insert(plan, { current, partner })
				current, currentRec = next_, merged
			end
			-- le résultat redevient disponible pour une chaîne suivante
			work[current] = { s = s, st = currentRec.st, bf = currentRec.bf, b = currentRec.b }
			put(groups[currentRec.st], current)
			lastKept = current
		end
	end
	return plan
end

-- Étape du combo de chaque paire d'un plan (1 = début d'une chaîne) : une paire dont le premier uid
-- est l'uid gardé de la paire précédente continue le combo. Fonction ajoutée pour le service
-- (récompenses de combo, bannières, classement).
function FusionRules.comboSteps(plan: { { string } }, records: { [string]: Types.SquishyRecord }): { number }
	local steps: { number } = {}
	if type(plan) ~= "table" then
		return steps
	end
	local work: { [string]: any } = {}
	if type(records) == "table" then
		for uid, rec in records do
			if type(rec) == "table" then
				work[uid] = rec
			end
		end
	end
	local kept: string? = nil
	local step = 0
	for i, pair in ipairs(plan) do
		local a, b = pair[1], pair[2]
		step = if kept ~= nil and a == kept then step + 1 else 1
		steps[i] = step
		local ra, rb = work[a] or {}, work[b] or {}
		kept = FusionRules.keepUid(a, b, ra, rb)
		work[kept] = FusionRules.fuse(ra, rb, 0, 0)
	end
	return steps
end

return FusionRules
