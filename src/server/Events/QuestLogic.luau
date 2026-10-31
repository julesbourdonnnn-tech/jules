--!strict
-- QuestLogic — aides PURES de QuestService (paquet « events ») : tirage déterministe des quêtes
-- du jour, relances, filtres JcJ / Équipage, correspondance objectif ↔ mesure.
-- Aucun service Roblox ni lecture d'horloge : tout est paramètre (testable sous Lune).
-- GDD : §7.5 (Hash(jour, UserId), 1 facile + 1 moyenne + 1 difficile, JcJ exclues en Zen,
-- Équipage seulement si équipage dans les 7 derniers jours, relance dans le même niveau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Quests = require(Shared.Config.Quests)
local Hash = require(Shared.Logic.Hash)

local QuestLogic = {}

-- Clé de tirage des remplacements imposés par le passage en Zen (≠ des relances du joueur)
local ZEN_REPLACE_KEY = 0x2E4E

QuestLogic.dailyById = {} :: { [number]: Quests.DailyQuest }
for _, q in Quests.Daily do
	QuestLogic.dailyById[q.id] = q
end

-- Mesure d'un signal pour un objectif : ("add", n) incrément, ("best", v) meilleure valeur d'un
-- coup (1 parade d'au moins n), ("set", v) valeur courante (perchoirs) ; nil = sans effet
export type Measure = (goal: Quests.Goal) -> (string?, number?)

-- Nouvelle progression d'un objectif après une mesure
function QuestLogic.apply(goal: Quests.Goal, p: number, mode: string?, value: number?): number
	if mode == nil or type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return p
	end
	if mode == "add" then
		if value <= 0 then
			return p
		end
		return p + value
	elseif mode == "best" then
		return math.max(p, math.min(value, goal.n))
	elseif mode == "set" then
		return math.max(p, math.min(value, goal.n))
	end
	return p
end

-- Quête proposable à ce joueur ?
function QuestLogic.eligible(q: Quests.DailyQuest, zen: boolean, crewRecent: boolean): boolean
	if zen and q.pvp then
		return false
	end
	if q.crew and not crewRecent then
		return false
	end
	return true
end

-- Équipage dans les CrewQuestDays derniers jours ?
function QuestLogic.crewRecent(lastCrewDay: number, day: number): boolean
	return type(lastCrewDay) == "number" and lastCrewDay > 0 and lastCrewDay >= day - Quests.CrewQuestDays
end

local function pool(
	tier: string,
	zen: boolean,
	crewRecent: boolean,
	exclude: { [number]: boolean }
): { number }
	local out: { number } = {}
	for _, q in Quests.Daily do
		if q.tier == tier and not exclude[q.id] and QuestLogic.eligible(q, zen, crewRecent) then
			table.insert(out, q.id)
		end
	end
	return out
end

-- Ids des quêtes du jour (un par niveau de DailyTierOrder, sans doublon), avant relances
function QuestLogic.drawDaily(userId: number, day: number, zen: boolean, crewRecent: boolean): { number }
	local ids: { number } = {}
	local used: { [number]: boolean } = {}
	for index, tier in Quests.DailyTierOrder do
		local candidates = pool(tier, zen == true, crewRecent == true, used)
		if #candidates > 0 then
			local id = candidates[Hash.int(1, #candidates, day, userId, Events.Salts.DailyQuest, index)]
			table.insert(ids, id)
			used[id] = true
		end
	end
	return ids
end

-- Relance du créneau `slot` (niveau `tier`) : Hash(jour, UserId, relances, créneau) parmi les quêtes
-- du même niveau absentes de `exclude` ; nil si aucune
function QuestLogic.reroll(
	userId: number,
	day: number,
	rerolls: number,
	slot: number,
	tier: string,
	exclude: { [number]: boolean },
	zen: boolean,
	crewRecent: boolean
): number?
	local candidates = pool(tier, zen, crewRecent, exclude)
	if #candidates == 0 then
		return nil
	end
	return candidates[Hash.int(1, #candidates, day, userId, Events.Salts.Reroll, rerolls, slot)]
end

-- Remplacement d'une quête JcJ quand le joueur passe en Zen (ne consomme pas de relance)
function QuestLogic.zenReplacement(
	userId: number,
	day: number,
	slot: number,
	tier: string,
	exclude: { [number]: boolean },
	crewRecent: boolean
): number?
	local candidates = pool(tier, true, crewRecent, exclude)
	if #candidates == 0 then
		return nil
	end
	return candidates[Hash.int(1, #candidates, day, userId, Events.Salts.Reroll, ZEN_REPLACE_KEY, slot)]
end

return QuestLogic
