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
-- GDD v2.0 §7.5 (lot A1, docs/04 §27.7) : semaine UTC unique (weekIndex), période de la piste (la
-- première va de la 1re connexion v2 au 2e lundi qui suit), Défis de Splorch faisables dans la
-- situation du joueur (challengeFeasible, drawChallenges), paliers de la piste et du Carnet. Lus
-- seulement quand WeeklyTrack, Carnet sont ouverts (QuestService, A4) ; purs, jamais d'erreur.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, table, bit32 = type, math, table, bit32

local Types = require(script.Parent.Parent.Types)
local Quests = require(script.Parent.Parent.Config.Quests)
local Species = require(script.Parent.Parent.Config.Species)
local Mutations = require(script.Parent.Parent.Config.Mutations)
local Hash = require(script.Parent.Hash)
local Features = require(script.Parent.Parent.Config.Features)

export type QuestCtx = {
	R: number,
	tilesLeft: number, -- achats de dalle encore possibles dans la boucle
	megaIn: number, -- s avant le prochain MEGA
	friendOnServer: boolean,
	splorchEta: number, -- s estimées jusqu'à l'objectif (taille qui manque ÷ croissance)
	stamps: number,
}

-- Période de la piste de la semaine (QuestRules.trackPeriod)
export type TrackPeriod = {
	period: number, -- numéro de période : weekIndex de sa DERNIÈRE semaine (jamais une semaine de l'année)
	startsAt: number, -- lundi 00:00 UTC de sa première semaine
	endsAt: number, -- fin exclue : lundi 00:00 UTC
	first: boolean, -- 1re période du compte (de la 1re connexion v2 au 2e lundi qui suit)
	firstPeriodEnd: number, -- valeur de weeklyTrack.firstPeriodEnd à garder (fixée si elle valait 0)
}

-- Situation du joueur pour les Défis de Splorch (QuestRules.challengeFeasible) ; tout est facultatif
export type ChallengeCtx = {
	playMedian: number?, -- s : temps de jeu médian des 7 derniers jours (borné à 30 min … 2 h)
	daysPlayed: number?, -- jours joués la semaine précédente (minDays : « Nourris Plop 3 jours »)
	workshopDone: boolean?, -- Atelier et « Pour le plaisir » complets (« Gagne 20 Confettis » retiré)
	-- s estimées par l'appelant pour finir le Défi, par statistique (Quests.Challenges[].stat) ;
	-- OBLIGATOIRE pour les Défis qui dépendent de la situation (ETA_REQUIRED) : absente = non faisable
	eta: { [string]: number }?,
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

-- Bonus de la famille gagné pour toujours (contrat v1.2, GDD §4.17) : dex.fam[f] == 1, f = index de la
-- famille dans Species.FamilyOrder (liste en ajout seul). QuestService pose la case quand
-- familyComplete devient vrai ; une espèce ajoutée plus tard ne retire jamais le bonus. Lu par les
-- bonus de famille de l'économie (EconomyService, SquishyService, EconomyModel). Une famille sans
-- bonus (Secrets) ou inconnue : jamais.
function QuestRules.familyEarned(dex: { [string]: any }, family: string): boolean
	if type(family) ~= "string" then
		return false
	end
	local def = (Species.Families :: any)[family]
	if type(def) ~= "table" or def.bonus == nil or family == "secret" then
		return false
	end
	local index = table.find(Species.FamilyOrder, family :: any)
	if index == nil then
		return false
	end
	return dexArray(dex, "fam")[index] == 1
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

-- =============================================================================================
-- GDD v2.0 §7.5 : semaine UTC, piste de la semaine, Défis de Splorch, Carnet du Ranch
-- =============================================================================================

local TRACK = Quests.WeeklyTrack
local EPOCH = TRACK.EpochOffset -- lundi 5 janvier 1970 00:00 UTC
local WEEK = TRACK.Week
local DAY = 86400
local MAX_UNIX = 2 ^ 53 -- au-delà, un horodatage n'est plus un entier exact
local TRACK_TIERS = #TRACK.Tiers
-- Temps de jeu d'un Défi (GDD §7.5, critique M15) : médiane des 7 derniers jours, au plus 2 h, au
-- moins 30 min ; un nouveau compte prend 30 min (constantes du GDD sans clé dans Config/Quests :
-- note INT-A1-BALANCE)
local PLAY_MIN = 1800
local PLAY_MAX = 7200
-- Défis qui dépendent de la situation du joueur : faisables seulement avec une estimation (eta) de
-- l'appelant ≤ temps de jeu (2 Grands Splorch qui battent le record, record battu, Ascension, 2 MEGA
-- SQUISH : le calendrier du serveur). Les autres se font en jouant normalement (achats, combo, Cuve,
-- tampons, créatures, PERFECT), sous leurs conditions (minDays, dropWhenWorkshopDone).
local ETA_REQUIRED = { splorches = true, recordBeaten = true, ascends = true, megas = true }
local CHALLENGE_SALT = 0x5D3F1 -- sel figé : changer = changer les Défis de tout le monde

-- Horodatage UTC sûr (NaN, ±inf, autre type → l'époque de la piste ; borné à [EPOCH ; 2^53])
local function unixOf(x: any): number
	local v = finite(x, EPOCH)
	return math.floor(math.clamp(v, EPOCH, MAX_UNIX))
end

-- Numéro de semaine UTC : floor((unix − 345 600) / 604 800), comptée depuis le lundi 5 janvier 1970
-- 00:00 UTC ; une seule définition pour la piste, les Défis et les classements (GDD §7.5). Entrée
-- illisible ou antérieure : 0
function QuestRules.weekIndex(unix: number): number
	return (unixOf(unix) - EPOCH) // WEEK
end

-- Lundi 00:00 UTC qui commence la semaine `index`
function QuestRules.weekStart(index: number): number
	return EPOCH + math.max(0, math.floor(finite(index, 0))) * WEEK
end

-- Période de la piste à l'instant `unix` (GDD §7.5). Première période d'un compte : de sa 1re
-- connexion v2 au 2e lundi qui suit (8 à 14 jours de calendrier) ; weeklyTrack.firstPeriodEnd = 0
-- (migration, nouveau compte) la fixe ici (QuestService garde la valeur rendue). Une fin abîmée
-- (pas un lundi 00:00, ou plus de 2 semaines plus tard) compte comme une première période finie :
-- jamais une période qui recule ni une piste remise à zéro en pleine semaine.
function QuestRules.trackPeriod(profile: { [string]: any }, unix: number): TrackPeriod
	local now = unixOf(unix)
	local week = QuestRules.weekIndex(now)
	local track = if type(profile) == "table" and type(profile.weeklyTrack) == "table"
		then profile.weeklyTrack
		else nil
	-- absente (profil v1, piste neuve) : 0, à fixer ; illisible (NaN, ±inf, autre type) : abîmée
	local raw = if track then track.firstPeriodEnd else nil
	local stored = if raw == nil then 0 else finite(raw, -1)
	local fpe: number
	if stored == 0 then
		fpe = QuestRules.weekStart(week + 2)
	elseif stored > 0 and stored % 1 == 0 and (stored - EPOCH) % WEEK == 0 then
		fpe = stored
	else
		fpe = QuestRules.weekStart(week) -- abîmée : première période finie
	end
	local ahead = (fpe - EPOCH) // WEEK - week
	if ahead > 2 then
		fpe = QuestRules.weekStart(week) -- plus de 2 semaines plus tard : abîmée
		ahead = 0
	end
	if now < fpe and ahead >= 1 then
		local last = (fpe - EPOCH) // WEEK - 1
		return {
			period = last,
			startsAt = fpe - 2 * WEEK,
			endsAt = fpe,
			first = true,
			firstPeriodEnd = fpe,
		}
	end
	return {
		period = week,
		startsAt = QuestRules.weekStart(week),
		endsAt = QuestRules.weekStart(week + 1),
		first = false,
		firstPeriodEnd = fpe,
	}
end

-- Paliers de la piste atteints avec `points` (1 palier = PointsPerTier points ; 12 au plus)
function QuestRules.trackTier(points: number): number
	local p = math.max(0, math.floor(finite(points, 0)))
	return math.min(TRACK_TIERS, p // TRACK.PointsPerTier)
end

-- Points de piste qu'un joueur PEUT gagner entre fromUnix et toUnix (bornes de la période, ou sa 1re
-- connexion) : jours UTC ENTIERS de l'intervalle (seulement ceux de `weekdays`, 0 = lundi … 6 =
-- dimanche, si donné) × objectifs du jour × 2, + les Défis d'une semaine × 5 (borne basse : GDD §7.5,
-- « chaque période permet d'atteindre 24 points », 27 pour le joueur du week-end)
function QuestRules.trackMaxPoints(fromUnix: number, toUnix: number, weekdays: { [number]: boolean }?): number
	local a = unixOf(fromUnix)
	local b = unixOf(toUnix)
	local firstDay = (a + DAY - 1) // DAY -- premier jour entier
	local lastDay = b // DAY - 1 -- dernier jour entier
	local days = 0
	for d = firstDay, math.min(lastDay, firstDay + 400) do
		if weekdays == nil or weekdays[(d + 3) % 7] == true then
			days += 1
		end
	end
	return days * Quests.ObjectiveRules.PerDay * TRACK.PointsPerObjective
		+ TRACK.ChallengesPerWeek * TRACK.PointsPerChallenge
end

-- Ligne de Config/Quests.Challenges (identifiant définitif = position)
type ChallengeDef = {
	id: number,
	key: string,
	stat: string,
	target: number,
	minDays: number?,
	dropWhenWorkshopDone: boolean?,
}

local function challengeDef(id: any): ChallengeDef?
	if type(id) ~= "number" then
		return nil
	end
	local def = (Quests.Challenges :: { any })[id]
	if type(def) == "table" and def.id == id then
		return def :: ChallengeDef
	end
	return nil
end

-- Temps de jeu d'un Défi : médiane des 7 derniers jours bornée à [30 min ; 2 h] (absente : 30 min)
function QuestRules.challengePlaySeconds(ctx: ChallengeCtx?): number
	local c: any = if type(ctx) == "table" then ctx else {}
	return math.clamp(finite(c.playMedian, PLAY_MIN), PLAY_MIN, PLAY_MAX)
end

-- Le Défi `id` est faisable dans la situation du joueur (GDD §7.5, critique M15) : jamais dépendant
-- des autres joueurs ; « Gagne 20 Confettis » retiré quand l'Atelier est complet ; « Nourris Plop
-- 3 jours » seulement après 3 jours joués la semaine précédente ; « Fais une Jelly Ascend »
-- seulement si l'interrupteur JellyAscend est ouvert ; un Défi de situation (ETA_REQUIRED) seulement
-- si son estimation tient dans le temps de jeu ; une estimation donnée pour un autre Défi aussi.
function QuestRules.challengeFeasible(id: number, ctx: ChallengeCtx?): boolean
	local def = challengeDef(id)
	if def == nil then
		return false
	end
	local c: any = if type(ctx) == "table" then ctx else {}
	if def.dropWhenWorkshopDone == true and c.workshopDone == true then
		return false
	end
	if def.minDays ~= nil and finite(c.daysPlayed, 0) < def.minDays then
		return false
	end
	if def.stat == "ascends" and Features.get("JellyAscend") ~= true then
		return false
	end
	local etas = if type(c.eta) == "table" then c.eta else {}
	local eta = etas[def.stat]
	if eta == nil then
		return not ETA_REQUIRED[def.stat]
	end
	local seconds = finite(eta, math.huge)
	return seconds >= 0 and seconds <= QuestRules.challengePlaySeconds(c)
end

-- Les 3 Défis d'une période (Quests.WeeklyTrack.ChallengesPerWeek), tirés parmi les faisables,
-- jamais deux fois le même, déterministes par (joueur, période) ; s'il en manque, complétés par les
-- Défis qui se font toujours en jouant (ni estimation, ni condition), dans l'ordre des identifiants
function QuestRules.drawChallenges(userId: number, period: number, ctx: ChallengeCtx?): { number }
	local n = TRACK.ChallengesPerWeek
	local pool = {}
	local defs = Quests.Challenges :: { any }
	for _, def in defs do
		if QuestRules.challengeFeasible(def.id, ctx) then
			table.insert(pool, def.id)
		end
	end
	local out = {}
	local user = finite(userId, 0)
	local p = finite(period, 0)
	for slot = 1, n do
		if #pool == 0 then
			break
		end
		local i = Hash.int(1, #pool, user, p, slot, CHALLENGE_SALT)
		table.insert(out, table.remove(pool, i))
	end
	for _, def in defs do
		if #out >= n then
			break
		end
		local basic = not ETA_REQUIRED[def.stat] and def.minDays == nil and def.dropWhenWorkshopDone ~= true
		if basic and table.find(out, def.id) == nil then
			table.insert(out, def.id)
		end
	end
	return out
end

-- Paliers du Carnet du Ranch atteints avec n niveaux achetés à vie (0 … 8 ; GDD §7.5)
function QuestRules.carnetTier(n: number): number
	local bought = math.max(0, math.floor(finite(n, 0)))
	local tier = 0
	for i, at in Quests.Carnet.Tiers do
		if bought >= at then
			tier = i
		end
	end
	return tier
end

-- Prochain seuil du Carnet (nil : tous atteints)
function QuestRules.carnetNext(n: number): number?
	local tier = QuestRules.carnetTier(n)
	return Quests.Carnet.Tiers[tier + 1]
end

return QuestRules
