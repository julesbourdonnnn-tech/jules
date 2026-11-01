--!strict
-- StateTimeouts (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Délai de sortie de chaque état (table du GDD §12.10) : aucun état ne peut rester bloqué. Chaque
-- service ferme ses états échus dans son step et appelle DiagnosticsService.stateTimedOut quand un
-- état a dû être fermé par son délai alors qu'il aurait dû finir seul.

-- Délais (s) des états du GDD §12.10 ; math.huge = fermé par un événement (mort, départ…)
local TABLE: { [string]: number } = {
	profileLoad = 60,
	characterPlace = 10,
	playerReady = 15, -- profil chargé + ranch attribué : PlayerReady émis au plus tard 15 s après (placement réessayé à part)
	serverFull = 30, -- serveur plein : renvoi après 30 s (annulé si un ranch se libère)
	worldResync = 3, -- client : trou de suite → RequestWorld renvoyé toutes les 3 s jusqu'à l'instantané
	unstable = 3, -- attribut Unstable après un retour forcé
	carry = math.huge,
	boopHold = 5.5, -- 5 s + 0,5 s de grâce (2,5 s + 0,5 s sans propriétaire proche) ; extendHold une seule fois
	feedHold = 5.5,
	leap = 0.35,
	runaway = 20,
	escape = 25,
	wild = 25,
	golden = 30,
	demo = 20,
	rush = 115, -- 90 s + 25 s pour les fuites en cours
	mega = 65,
	splorchQueue = 110,
	spectacle = 10,
	squishParty = 600,
	wobbleParty = 300,
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

-- Délai de l'état (s) ; erreur claire pour un état inconnu
function StateTimeouts.seconds(state: string): number
	local _ = { state }
	error("TODO(logic): StateTimeouts.seconds")
end

-- Échéance = début + délai (+ extra)
function StateTimeouts.deadline(state: string, startedAt: number, extra: number?): number
	local _ = { state, startedAt, extra }
	error("TODO(logic): StateTimeouts.deadline")
end

-- L'état a dépassé son délai
function StateTimeouts.expired(state: string, startedAt: number, now: number, extra: number?): boolean
	local _ = { state, startedAt, now, extra }
	error("TODO(logic): StateTimeouts.expired")
end

-- Liste des états connus (tests : chaque état a un test de délai)
function StateTimeouts.names(): { string }
	error("TODO(logic): StateTimeouts.names")
end

return StateTimeouts
