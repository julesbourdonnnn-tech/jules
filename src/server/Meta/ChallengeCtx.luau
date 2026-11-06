--!strict
-- ChallengeCtx (lot A4, étape 4 ; GDD v2.0 §7.5, critique M15 ; docs/04 §27.7 ; décision D11 du plan) :
-- situation du joueur pour le tirage des Défis de Splorch (QuestRules.ChallengeCtx), calculée depuis le
-- profil et quelques mesures données par QuestService (instant, plus gros squishy d'enclos ou du Bassin,
-- interrupteurs). Module PUR : aucune horloge lue, aucun service, jamais d'erreur (entrée illisible :
-- valeur sûre).
--   * playMedian : médiane des 7 cases de weeklyTrack.play (secondes de jeu par jour UTC) ; nil si aucune
--     case n'atteint une minute (nouveau compte : QuestRules prend alors 30 min) ;
--   * daysPlayed : cases d'au moins une minute (« Nourris Plop 3 jours » : minDays) ;
--   * workshopDone : chaque ligne de l'Atelier à son maximum (Déco perso de l'Atelier comprise : 24 objets)
--     et chaque cosmétique de « Pour le plaisir » acheté (« Gagne 20 Confettis » retiré) ;
--   * eta (secondes) des Défis de situation : 2 Grands Splorch et nouveau Record R seulement sur une
--     boucle record (r = Record R ; une remontée après une Ascension n'en propose pas), Jelly Ascend prête
--     maintenant ou à la fin de la boucle en cours, 2 MEGA SQUISH d'après le calendrier (EventClock).
--     Une estimation absente = Défi non faisable (QuestRules.challengeFeasible).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Upgrades = require(Shared.Config.Upgrades)
local Prestige = require(Shared.Logic.Prestige)
local Bitset = require(Shared.Logic.Bitset)
local EventClock = require(Shared.Logic.EventClock)
local QuestRules = require(Shared.Logic.QuestRules)

local ChallengeCtx = {}

-- Mesures du serveur (QuestService) : tout est lu ici, rien n'est appelé
export type Input = {
	now: number, -- Clock.now() du tirage
	biggest: number, -- taille du plus gros squishy d'enclos ou du Bassin (SquishyService.biggest)
	recordR: boolean, -- interrupteur RecordR (Défi « Atteins un nouveau Record R » : RecordReached)
	mega: boolean, -- interrupteur MegaSquish (Défi « Participe à 2 MEGA SQUISH »)
	confetti: boolean, -- interrupteur Confetti (Défi « Gagne 20 Confettis »)
}

ChallengeCtx.DAY_PLAYED = 60 -- s : un jour compte comme joué à partir d'une minute de jeu
ChallengeCtx.DAYS = 7 -- cases de weeklyTrack.play

local MEGA = Events.Mega
local MAX_R = Balance.Prestige.MaxR
local MAX_A = Balance.Prestige.MaxA

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Case de jeu lisible (0 … 86 400) ; illisible : 0
local function seconds(x: any): number
	if not finite(x) then
		return 0
	end
	return math.clamp(x, 0, 86400)
end

-- Cases de jeu des 7 derniers jours (tableau de 7 nombres sûrs, jamais le tableau du profil)
local function buckets(play: any): { number }
	local out = table.create(ChallengeCtx.DAYS, 0)
	if type(play) == "table" then
		for i = 1, ChallengeCtx.DAYS do
			out[i] = seconds(play[i])
		end
	end
	return out
end

-- Médiane des 7 cases (4e valeur triée) ; nil si aucune case n'atteint DAY_PLAYED
function ChallengeCtx.playMedian(play: any): number?
	local list = buckets(play)
	local any = false
	for _, v in list do
		if v >= ChallengeCtx.DAY_PLAYED then
			any = true
			break
		end
	end
	if not any then
		return nil
	end
	table.sort(list)
	return list[(ChallengeCtx.DAYS + 1) // 2]
end

-- Jours joués parmi les 7 derniers (cases ≥ DAY_PLAYED)
function ChallengeCtx.daysPlayed(play: any): number
	local n = 0
	for _, v in buckets(play) do
		if v >= ChallengeCtx.DAY_PLAYED then
			n += 1
		end
	end
	return n
end

-- Atelier et « Pour le plaisir » complets : chaque ligne de Upgrades.WorkshopRows à #costs (Déco perso de
-- l'Atelier, decoShop : 24) et chaque bit de atelierCosmetics (Upgrades.CosmeticBits)
function ChallengeCtx.workshopDone(profile: { [string]: any }): boolean
	if type(profile) ~= "table" or type(profile.atelier) ~= "table" then
		return false
	end
	local atelier = profile.atelier
	for i, row in Upgrades.WorkshopRows do
		local level = atelier[i]
		if not finite(level) or level < #row.costs then
			return false
		end
	end
	local bits = profile.atelierCosmetics
	if type(bits) ~= "table" then
		return false
	end
	for i = 1, Upgrades.CosmeticBits do
		if not Bitset.has(bits, i) then
			return false
		end
	end
	return true
end

-- Croissance du ranch (taille par seconde, profile.growth.g) ; illisible : 0
local function growthOf(profile: { [string]: any }): number
	local growth = profile.growth
	if type(growth) ~= "table" or not finite(growth.g) then
		return 0
	end
	return math.max(0, growth.g)
end

-- Secondes pour finir la boucle en cours (plus gros → objectif de r) ; nil si la croissance est nulle
local function loopEta(profile: { [string]: any }, biggest: number): number?
	local target = Prestige.target(Prestige.r(profile))
	if biggest >= target then
		return 0
	end
	local g = growthOf(profile)
	if g <= 0 then
		return nil
	end
	return (target - biggest) / g
end

-- Estimations (secondes) des Défis de situation (QuestRules : ETA_REQUIRED), et la marque « jamais »
-- (math.huge) du Défi des Confettis quand l'interrupteur Confetti est coupé
function ChallengeCtx.etas(profile: { [string]: any }, input: Input): { [string]: number }
	local out: { [string]: number } = {}
	if type(profile) ~= "table" or type(input) ~= "table" then
		return out
	end
	local now = if finite(input.now) then input.now else 0
	local biggest = if finite(input.biggest) then math.max(0, input.biggest) else 0
	local r = Prestige.r(profile)
	local best = Prestige.bestR(profile)
	local loop = loopEta(profile, biggest)
	-- boucle record : le prochain prestige est un Grand Splorch qui bat le Record R
	local record = r == best and r < MAX_R
	if record and loop ~= nil then
		if input.recordR == true then
			out.recordBeaten = loop
		end
		-- 2 Grands Splorch : la boucle en cours, puis la suivante estimée sans son × 2 de croissance
		-- (les dalles de la boucle repartent de zéro : estimation prudente)
		local g = growthOf(profile)
		if r + 1 < MAX_R and g > 0 then
			out.splorches = loop + Prestige.target(r + 1) / g
		end
	end
	-- Jelly Ascend : prête maintenant, ou à la fin de la boucle en cours (Grand ou Petit Splorch)
	local A = Prestige.ascend(profile)
	if Prestige.ascendReady(profile) then
		out.ascends = 0
	elseif loop ~= nil and A < MAX_A and r < MAX_R and r + 1 >= Prestige.reqR(A + 1) then
		out.ascends = loop
	end
	-- 2 MEGA SQUISH : atterrissage du 2e MEGA à venir, plus son temps de pression et l'éclatement
	if input.mega == true then
		local phase = EventClock.mega(now)
		local first = if phase.landsAt > now then phase.landsAt else phase.landsAt + MEGA.Period
		out.megas = math.max(0, first + MEGA.Period + MEGA.PressTime + MEGA.BurstTime - now)
	end
	if input.confetti ~= true then
		out.confettiEarned = math.huge -- aucun Confetti à gagner : jamais tiré
	end
	return out
end

-- Situation complète pour QuestRules.drawChallenges
function ChallengeCtx.build(profile: { [string]: any }, input: Input): QuestRules.ChallengeCtx
	local track = if type(profile) == "table" and type(profile.weeklyTrack) == "table"
		then profile.weeklyTrack
		else nil
	local play = if track then track.play else nil
	return {
		playMedian = ChallengeCtx.playMedian(play),
		daysPlayed = ChallengeCtx.daysPlayed(play),
		workshopDone = ChallengeCtx.workshopDone(profile),
		eta = ChallengeCtx.etas(profile, input),
	}
end

return ChallengeCtx
