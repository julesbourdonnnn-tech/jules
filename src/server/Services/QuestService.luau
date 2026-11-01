--!strict
-- QuestService (paquet meta) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Accueil, objectifs, Nourrir Plop, Squishydex, statistiques (GDD §3, §4.17, §4.20, §7.3, §7.4,
-- §16.1) : étapes de l'accueil (entonnoir AnalyticsService, délais de 90 s, naissances scriptées,
-- démonstration), temps de jeu cumulé, 3 objectifs du jour (QuestRules, relance, remise à zéro de
-- minuit, Goutte chanceuse), Nourrir Plop (maintien de 5 s mesuré par le serveur, jours au total,
-- paliers), tampons et jalons du Squishydex, carte « Plop a sommeil » (60 et 120 min). Pas de codes
-- au lancement. Écoute FriendsChanged (ami présent : objectif 12, stats.lastFriendDay). Émet Fed,
-- OnboardingStep, Stamped, UiSeen. Remotes : FeedPlop, ClaimObjective, RerollObjective,
-- ClaimDexReward, UiSeen (étape 10 : objectifs vus) ; HoldState. Clés : firstJoin, codes, dex,
-- plopDays, lastFeedDay, onboarding, objectives, stats.

export type OnboardingScript = {
	active: boolean, -- accueil en cours (avant Quests.Onboarding.ScriptUntil)
	runawayAt: number?, -- s de jeu de la première créature en fuite (Mochi Mew)
	demoAt: number?, -- s de jeu de la démonstration de Big Plop
	runawayPaused: boolean, -- fuites en pause (2:45 → 5:00)
	vatScripted: boolean, -- la Cuve suit le script (une goutte toutes les 90 s)
}

local QuestService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function QuestService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function QuestService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : temps de jeu, délais de l'accueil, script (jumeau, premier tirage), minuit, carte sommeil, maintien du bol
function QuestService.step(now: number)
	local _ = { now }
	error("TODO(meta): QuestService.step")
end

-- Étape d'accueil atteinte (0 … 11)
function QuestService.stage(player: Player): number
	local _ = { player }
	error("TODO(meta): QuestService.stage")
end

-- Événements discrets pour ce nouveau (avant l'étape 9)
function QuestService.isNewcomerQuiet(player: Player): boolean
	local _ = { player }
	error("TODO(meta): QuestService.isNewcomerQuiet")
end

-- Jeu cumulé
function QuestService.playSeconds(player: Player): number
	local _ = { player }
	error("TODO(meta): QuestService.playSeconds")
end

-- Horaires scriptés de l'accueil pour ChaseService et SquishyService
function QuestService.script(player: Player): OnboardingScript
	local _ = { player }
	error("TODO(meta): QuestService.script")
end

-- Tamponne le Squishydex (vrai si nouvelle entrée) ; Celebrate "dexNew"
function QuestService.stamp(player: Player, species: number, mutation: number, stars: number): boolean
	local _ = { player, species, mutation, stars }
	error("TODO(meta): QuestService.stamp")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « feedHold » (maintien du bol), « onboardingStep » (consigne en cours) ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function QuestService.openStates(): { { name: string, startedAt: number, player: Player? } }
	error("TODO(meta): QuestService.openStates")
end

return QuestService
