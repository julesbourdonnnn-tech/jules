--!strict
-- StateTimeouts (paquet logic, docs/04 §12.1, §17.2).
-- Délai de sortie de chaque état (table du GDD §12.10) : aucun état ne peut rester bloqué. Chaque
-- service ferme ses états échus dans son step et appelle DiagnosticsService.stateTimedOut quand un
-- état a dû être fermé par son délai alors qu'il aurait dû finir seul.

-- Délais (s) des états du GDD §12.10 ; math.huge = fermé par un événement (mort, départ…)
-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, table = type, math, table

local Balance = require(script.Parent.Parent.Config.Balance)
local Events = require(script.Parent.Parent.Config.Events)
local Quests = require(script.Parent.Parent.Config.Quests)

-- grâce d'une attente sur une dalle (même marge que les maintiens du boop et du bol)
local TILE_GRACE = 0.5

local TABLE: { [string]: number } = {
	profileLoad = 60,
	characterPlace = 10,
	playerReady = 15, -- profil chargé + ranch attribué : PlayerReady émis au plus tard 15 s après (placement réessayé à part)
	serverFull = 30, -- serveur plein : renvoi après 30 s (annulé si un ranch se libère)
	worldResync = 3, -- client : trou de suite → RequestWorld renvoyé toutes les 3 s jusqu'à l'instantané
	unstable = 3, -- attribut Unstable après un retour forcé
	-- portage : fermé par un événement (GDD §12.10) ou par le délai de sûreté de SquishyService (+ 1 s de
	-- grâce pour le contrôle du robot de longue durée, note INT-LR10)
	carry = Balance.Carry.SafetySeconds + 1,
	boopHold = 5.5, -- 5 s + 0,5 s de grâce (2,5 s + 0,5 s sans propriétaire proche) ; extendHold une seule fois
	feedHold = Quests.Feed.Hold + Quests.Feed.HoldGrace, -- bol : 2 s + 0,5 s (contrat v1.2)
	-- attente de 0,6 s sur une dalle avant l'achat (contrat v1.2, HoldState « tile » de RanchService)
	tileDwell = Balance.Tiles.DwellSeconds + TILE_GRACE,
	leap = 0.35,
	runaway = 20,
	escape = 25,
	wild = 25,
	golden = 30,
	demo = 20,
	rush = 115, -- 90 s + 25 s pour les fuites en cours
	mega = 65,
	-- file des Grands Splorch : place × 20 s + reste du spectacle, recalculé ; coupure dure à 8 min
	splorchQueue = Events.SplorchQueueHardCut,
	spectacle = 10,
	squishParty = 600,
	wobbleParty = 300,
	gaugeRest = Events.Gauge.RestSeconds, -- sieste de Big Plop après une Wobble Party (contrat v1.2)
	modeCard = 20,
	card = 8,
	robloxPrompt = 60,
	onboardingStep = 90,
	clickTarget = 4,
	clapWindow = 8,
	fusion = 0.4,
	combo = 0.6,
	hatch = 2,
	splorchBurst = 3.2,
	clip = 8, -- client : capture vidéo automatique arrêtée au plus tard 8 s après son début
}

local StateTimeouts = {}

StateTimeouts.Table = TABLE

-- Délai de l'état (s) ; erreur claire pour un état inconnu (faute de programmation, vue par les specs)
function StateTimeouts.seconds(state: string): number
	local value = if type(state) == "string" then TABLE[state] else nil
	if value == nil then
		error(`StateTimeouts : état inconnu « {tostring(state)} »`, 2)
	end
	return value
end

-- Échéance = début + délai (+ extra). Un début illisible (NaN, ±inf) donne une échéance déjà
-- passée (−inf) : l'état est fermé au lieu de rester bloqué.
function StateTimeouts.deadline(state: string, startedAt: number, extra: number?): number
	local seconds = StateTimeouts.seconds(state)
	if type(startedAt) ~= "number" or startedAt ~= startedAt or math.abs(startedAt) == math.huge then
		return -math.huge
	end
	local more = 0
	if type(extra) == "number" and extra == extra and math.abs(extra) ~= math.huge then
		more = extra
	end
	return startedAt + seconds + more
end

-- L'état a dépassé son délai (strictement après l'échéance) ; un début illisible compte comme
-- échu, un « maintenant » illisible jamais
function StateTimeouts.expired(state: string, startedAt: number, now: number, extra: number?): boolean
	local deadline = StateTimeouts.deadline(state, startedAt, extra)
	if type(now) ~= "number" or now ~= now or math.abs(now) == math.huge then
		return false
	end
	return now > deadline
end

-- Liste des états connus, triée (tests : chaque état a un test de délai)
function StateTimeouts.names(): { string }
	local out = {}
	for name in TABLE do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

return StateTimeouts
