--!strict
-- QuestRules (paquet logic, docs/04 §12.1). Objectifs du jour faisables (« Proposé si », GDD §7.4),
-- tirage déterministe Hash(jour, UserId), relance, progression, remise à zéro de minuit en pleine
-- session (terminés réclamés seuls, en cours gardés jusqu'à la fin de la session), paliers de
-- Nourrir Plop et du Squishydex, bonus de famille et pages dorées (lus aussi par EconomyService et
-- SquishyService, qui précèdent QuestService).
-- Squishydex (Schema) : dex.mut[s] = masque (bit 0 = page de l'espèce, bit m = mutation m) ;
-- dex.stars[s] = masque de 5 bits (bit k − 1 = badge ★k). Atteindre ★k remplit les badges ★1 … ★k.
-- Progression (apply) : un objectif avance sur l'événement de sa statistique ; l'objectif « série
-- PERFECT » (streak) écoute aussi chaque pression ("press") : PERFECT → +1, pression ratée → 0.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, table, bit32 = type, math, table, bit32

local Types = require(script.Parent.Parent.Types)
local Quests = require(script.Parent.Parent.Config.Quests)
local Species = require(script.Parent.Parent.Config.Species)
local Mutations = require(script.Parent.Parent.Config.Mutations)
local Hash = require(script.Parent.Hash)

export type QuestCtx = {
	R: number,
	tilesLeft: number, -- achats de dalle encore possibles dans la boucle
	megaIn: number, -- s avant le prochain MEGA
	friendOnServer: boolean,
	splorchEta: number, -- s estimées jusqu'à l'objectif (taille qui manque ÷ croissance)
	stamps: number,
}

local QuestRules = {}

local RULES = Quests.ObjectiveRules
local TIERS = { "easy", "medium", "hard" }
local DRAW_SALT = 0x0B1E -- sels figés : changer = changer les objectifs de tout le monde
local REROLL_SALT = 0x2E2011
local MUTATION_BITS = 0x3FF -- bit 0 (page) + bits 1 … 9 (mutations)
local STAR_BITS = 0x1F

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- Masque entier sûr dans [0 ; 2^32[
local function mask(x: any): number
	local v = finite(x, 0)
	if v < 0 then
		return 0
	end
	return math.floor(v) % 4294967296
end

local function popcount(x: number): number
	local n = 0
	while x ~= 0 do
		x = bit32.band(x, x - 1)
		n += 1
	end
	return n
end

local function hasBit(m: number, bit: number): boolean
	return bit32.btest(m, bit32.lshift(1, bit))
end

local function dexArray(dex: any, key: string): { any }
	if type(dex) == "table" and type(dex[key]) == "table" then
		return dex[key]
	end
	return {}
end

local function defOf(id: any): Quests.ObjectiveDef?
	if type(id) ~= "number" then
		return nil
	end
	local def = Quests.Objectives[id]
	if def and def.id == id then
		return def
	end
	return nil
end

-- Règle « Proposé si » de l'objectif dans la situation du joueur
function QuestRules.eligible(def: Quests.ObjectiveDef, ctx: QuestCtx): boolean
	if type(def) ~= "table" then
		return false
	end
	local c: any = if type(ctx) == "table" then ctx else {}
	local cond = def.condition
	if cond == "always" then
		return true
	elseif cond == "tilesLeft3" then
		return finite(c.tilesLeft, 0) >= 3
	elseif cond == "megaSoon" then
		local megaIn = finite(c.megaIn, math.huge)
		return megaIn >= 0 and megaIn <= RULES.MegaSoonWithin
	elseif cond == "friendOnServer" then
		return c.friendOnServer == true
	elseif cond == "rMin1" then
		return finite(c.R, 0) >= 1
	elseif cond == "rMin3" then
		return finite(c.R, 0) >= 3
	elseif cond == "splorchSoon" then
		local eta = finite(c.splorchEta, math.huge)
		return eta >= 0 and eta <= RULES.FeasibleWithin
	elseif cond == "stampsUnder120" then
		return finite(c.stamps, math.huge) < RULES.StampsUnder
	end
	return false
end

-- Objectifs d'un niveau proposables (ordre des identifiants)
local function pool(tier: string, ctx: QuestCtx, exclude: { [number]: boolean }?): { number }
	local out = {}
	for _, def in Quests.Objectives do
		if def.tier == tier and QuestRules.eligible(def, ctx) and not (exclude and exclude[def.id]) then
			table.insert(out, def.id)
		end
	end
	return out
end

-- Premier objectif d'un niveau (repli : chaque niveau a des objectifs « always »)
local function firstOfTier(tier: string): number
	for _, def in Quests.Objectives do
		if def.tier == tier then
			return def.id
		end
	end
	return 1
end

-- 3 objectifs (facile, moyen, difficile) ; jour 1 : Quests.ObjectiveRules.Day1
function QuestRules.draw(userId: number, day: number, ctx: QuestCtx, firstDay: boolean): { number }
	if firstDay == true then
		return table.clone(RULES.Day1)
	end
	local out = {}
	for i, tier in TIERS do
		local list = pool(tier, ctx, nil)
		if #list == 0 then
			table.insert(out, firstOfTier(tier))
		else
			table.insert(out, list[Hash.int(1, #list, userId, day, i, DRAW_SALT)])
		end
	end
	return out
end

-- Nouvel objectif du même niveau pour cette case, différent des 3 actuels (l'actuel s'il n'y en a pas)
function QuestRules.reroll(
	userId: number,
	day: number,
	current: { number },
	slot: number,
	ctx: QuestCtx,
	salt: number
): number
	local list: { number } = if type(current) == "table" then current else {}
	local s = math.clamp(math.floor(finite(slot, 1)), 1, #TIERS)
	local currentId = list[s]
	local def = defOf(currentId)
	local tier = if def then def.tier else TIERS[s]
	local exclude: { [number]: boolean } = {}
	for _, id in list do
		if type(id) == "number" then
			exclude[id] = true
		end
	end
	local candidates = pool(tier, ctx, exclude)
	if #candidates == 0 then
		return if def then currentId else firstOfTier(tier)
	end
	return candidates[Hash.int(1, #candidates, userId, day, s, salt, REROLL_SALT)]
end

-- Progression d'un objectif par un événement (série PERFECT remise à 0 par une pression ratée)
function QuestRules.apply(
	entry: Types.ObjectiveEntry,
	stat: string,
	amount: number,
	perfect: boolean?
): Types.ObjectiveEntry
	if type(entry) ~= "table" then
		return { id = 0, p = 0, done = false, claimed = false }
	end
	local out: Types.ObjectiveEntry = {
		id = entry.id,
		p = math.max(0, finite(entry.p, 0)),
		done = entry.done == true,
		claimed = entry.claimed == true,
	}
	local def = defOf(entry.id)
	if def == nil then
		return out
	end
	-- valeurs sûres : 0 ≤ p ≤ but (entier), terminé dès que le but est atteint
	out.p = math.min(def.goal, math.floor(out.p))
	if out.done then
		out.p = def.goal
		return out
	end
	local add = math.max(0, math.floor(finite(amount, 0)))
	if def.streak then
		if stat == def.stat or stat == "press" then
			local isPerfect = perfect == true or (perfect == nil and stat == def.stat)
			if isPerfect then
				out.p += add
			else
				out.p = 0
			end
		end
	elseif stat == def.stat then
		out.p += add
	end
	if out.p >= def.goal then
		out.p = def.goal
		out.done = true
	end
	return out
end

-- Minuit en session : (liste gardée, ids terminés à réclamer d'office). Avec autoClaim, les
-- terminés non réclamés sont rendus pour être réclamés tout de suite et ne restent pas dans la
-- liste ; ceux en cours restent jusqu'à la fin de la session. Sans autoClaim, rien n'est réclamé.
function QuestRules.rollover(
	list: { Types.ObjectiveEntry },
	autoClaim: boolean
): ({ Types.ObjectiveEntry }, { number })
	local kept: { Types.ObjectiveEntry } = {}
	local claim: { number } = {}
	if type(list) ~= "table" then
		return kept, claim
	end
	for _, entry in ipairs(list) do
		if type(entry) == "table" and entry.claimed ~= true then
			local copy = { id = entry.id, p = finite(entry.p, 0), done = entry.done == true, claimed = false }
			if copy.done and autoClaim == true then
				table.insert(claim, copy.id)
			else
				table.insert(kept, copy)
			end
		end
	end
	return kept, claim
end

-- Palier de Nourrir Plop atteint à ce total de jours
function QuestRules.plopReward(days: number): Quests.PlopReward?
	local d = finite(days, -1)
	for _, reward in Quests.Feed.Milestones do
		if reward.day == d then
			return reward
		end
	end
	return nil
end

-- Jalons atteints et non réclamés
function QuestRules.dexMilestones(stamps: number, lastClaimed: number): { Quests.DexMilestone }
	local have = finite(stamps, 0)
	local last = finite(lastClaimed, 0)
	local out = {}
	for _, milestone in Quests.Dex.Milestones do
		if milestone.stamps <= have and milestone.stamps > last then
			table.insert(out, milestone)
		end
	end
	return out
end

-- Tampons d'espèces + de mutations
function QuestRules.stampCount(dex: { [string]: any }): number
	local mut = dexArray(dex, "mut")
	local total = 0
	for s = 1, #Species.List do
		total += popcount(bit32.band(mask(mut[s]), MUTATION_BITS))
	end
	return total
end

-- Badges d'étoiles (★1 à ★5 par espèce)
function QuestRules.starBadges(dex: { [string]: any }): number
	local stars = dexArray(dex, "stars")
	local total = 0
	for s = 1, #Species.List do
		total += popcount(bit32.band(mask(stars[s]), STAR_BITS))
	end
	return total
end

-- Les 4 espèces de la famille tamponnées (Secrets : jamais)
function QuestRules.familyComplete(dex: { [string]: any }, family: string): boolean
	local def = (Species.Families :: any)[family]
	if type(def) ~= "table" or def.bonus == nil or family == "secret" then
		return false
	end
	local mut = dexArray(dex, "mut")
	for _, s in def.species do
		if not hasBit(mask(mut[s]), 0) then
			return false
		end
	end
	return #def.species > 0
end

-- Espèces dont les 8 mutations hors Lunaire sont trouvées
function QuestRules.goldenPages(dex: { [string]: any }): number
	local mut = dexArray(dex, "mut")
	local need = 0
	for _, def in Mutations.List do
		if not Mutations.GoldenPageExcludes[def.id] then
			need = bit32.bor(need, bit32.lshift(1, def.id))
		end
	end
	local pages = 0
	for s = 1, #Species.List do
		if bit32.band(mask(mut[s]), need) == need then
			pages += 1
		end
	end
	return pages
end

-- La naissance remplit une entrée encore vide (espèce, mutation ou badge d'étoiles)
function QuestRules.isNewStamp(
	dex: { [string]: any },
	species: number,
	mutation: number,
	stars: number
): boolean
	if Species.ById[species] == nil then
		return false
	end
	local m = mask(dexArray(dex, "mut")[species])
	if not hasBit(m, 0) then
		return true
	end
	local mu = math.floor(finite(mutation, 0))
	if Mutations.ById[mu] and not hasBit(m, mu) then
		return true
	end
	local st = math.clamp(math.floor(finite(stars, 0)), 0, Quests.Dex.StarBadges)
	local badges = mask(dexArray(dex, "stars")[species])
	for k = 1, st do
		if not hasBit(badges, k - 1) then
			return true
		end
	end
	return false
end

return QuestRules
