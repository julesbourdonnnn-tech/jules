--!strict
-- Objectifs (GDD §7.3, §7.4, §7.5, §4.14). Contrat : docs/04-architecture.md §9.
--
-- Types d'objectif (Goal.kind) et signal serveur qui les fait progresser (QuestService) :
--   catch            n            captures (Signals.Caught)
--   catchRarity      minRarity, n captures de rareté ≥ minRarity (Signals.Caught)
--   catchWeather     n            captures d'une forme météo f ≠ 0 (Signals.Caught)
--   catchZone        zone, n      captures dans une zone (Signals.Caught)
--   parades          n            parades (Signals.Parade)
--   paradeSize       n            1 parade d'au moins n Nebbies (Signals.Parade)
--   paradeIdle       seconds      1 parade rapportant ≥ seconds de revenu passif (Signals.Parade)
--   bankCount        n            Nebbies encaissés au total (Signals.Parade)
--   bankRarity       minRarity, n Nebbies de rareté ≥ minRarity encaissés (Signals.Parade)
--   beaconFeed       n            Nebbies encaissés à la Balise (Signals.Parade, atBeacon)
--   beaconWin        n            Nuits de la Balise réussies avec contribution (Signals.BeaconResult)
--   cometParticipate n            participations à une Comète (Signals.CometParticipation)
--   cometHold        seconds      secondes de Comète portée (Signals.CometHeld)
--   weatherOrComet   n            capture météo OU participation à une Comète (Q6)
--   wispPop          n            Gloomwisps éclatés (Signals.WispPopped)
--   dash             n            Dash (Signals.Dashed)
--   upgrades         n            niveaux d'amélioration achetés (Signals.UpgradeBought)
--   upgrade          track, n     niveaux d'une piste (Signals.UpgradeBought)
--   perches          n            nombre de perchoirs ≥ n (Signals.PerchesChanged)
--   snipNebbies      n            Nebbies détachés par ses coupes (Signals.Snipped)
--   escort           seconds      secondes d'escorte (Signals.EscortTime)
--   fusions          n            fusions Starforge (Signals.Fused)
--   idle             seconds      secondes de revenu passif réglées en ligne (Signals.IdleSettled)
--   cheers           n            acclamations données (Signals.Cheered)
--   atlasNew         n            nouvelles entrées d'Atlas (Signals.AtlasEntry)

local Quests = {}

export type Goal = {
	kind: string,
	n: number,
	minRarity: number?,
	zone: string?,
	track: string?,
}

export type Reward = {
	glow: number?, -- Glow fixe
	idleSeconds: number?, -- Glow = idleSeconds × revenu passif actuel
	minGlow: number?, -- minimum pour idleSeconds
	stardust: number?,
	boostSeconds: number?, -- boost personnel ×2
	species: number?, -- un Nebby (★1, forme 0, sans variante)
	rotation: string?, -- un Nebby de la rotation Events.Rotations[rotation] (semaine en cours)
	unlock: string?, -- fonctionnalité d'interface débloquée ("atlas")
}

export type OnboardingQuest = {
	id: string, -- "q1" … "q7" ; texte : "quest.onboarding.<id>"
	goal: Goal,
	reward: Reward,
	funnel: number?, -- étape d'entonnoir envoyée à la complétion (§14.1)
	funnelName: string?,
	hint: string, -- clé de localisation de l'instruction affichée (OnboardingController, ≤ 4 mots)
}

-- Chaîne d'accueil (§7.4) : une quête à la fois, récompense accordée AUTOMATIQUEMENT à la complétion
Quests.Onboarding = {
	{
		id = "q1",
		goal = { kind = "paradeSize", n = 4 },
		reward = { glow = 50 },
		funnel = 5,
		funnelName = "Parade4",
		hint = "onboarding.findNebbies",
	},
	{
		id = "q2",
		goal = { kind = "upgrade", track = "conga", n = 2 },
		reward = { glow = 80 },
		hint = "onboarding.buyConga",
	},
	{
		id = "q3",
		goal = { kind = "paradeSize", n = 6 },
		reward = { glow = 150 },
		funnel = 6,
		funnelName = "Parade6",
		hint = "onboarding.findNebbies",
	},
	{
		id = "q4",
		goal = { kind = "bankRarity", minRarity = 3, n = 1 },
		reward = { stardust = 100, unlock = "atlas" },
		funnel = 7,
		funnelName = "AtlasUnlocked",
		hint = "onboarding.catchRare",
	},
	{
		id = "q5",
		goal = { kind = "upgrade", track = "stride", n = 1 },
		reward = { glow = 200 },
		funnel = 8,
		funnelName = "StrideBought",
		hint = "onboarding.buyStride",
	},
	{
		id = "q6",
		goal = { kind = "weatherOrComet", n = 1 },
		reward = { glow = 300, stardust = 50 },
		funnel = 9,
		funnelName = "FirstEvent",
		hint = "onboarding.weather",
	},
	{
		id = "q7",
		goal = { kind = "perches", n = 10 },
		reward = { boostSeconds = 600 },
		hint = "onboarding.perches",
	},
} :: { OnboardingQuest }

-- Étapes d'entonnoir hors quêtes (§14.1), envoyées par QuestService sur signaux
Quests.Funnel = {
	{ step = 1, name = "Loaded" },
	{ step = 2, name = "FirstCatch" },
	{ step = 3, name = "FirstParade" },
	{ step = 4, name = "FirstUpgrade" },
	{ step = 5, name = "Parade4" },
	{ step = 6, name = "Parade6" },
	{ step = 7, name = "AtlasUnlocked" },
	{ step = 8, name = "StrideBought" },
	{ step = 9, name = "FirstEvent" },
	{ step = 10, name = "FirstSupernova" },
}

-- Récompenses des quêtes du jour par niveau (§7.5)
Quests.DailyTiers = {
	easy = { stardust = 40, idleSeconds = 180 },
	medium = { stardust = 60, idleSeconds = 360 },
	hard = { stardust = 100, idleSeconds = 600 },
} :: { [string]: Reward }

Quests.DailyTierOrder = { "easy", "medium", "hard" } -- slot 1, 2, 3

-- Les 3 quêtes terminées : « Étoile du jour »
Quests.DailyStar = { boostSeconds = 900 } :: Reward

Quests.Rerolls = {
	Free = 1,
	VIP = 1, -- +1 avec le pass VIP Star
}

Quests.CrewQuestDays = 7 -- quêtes « Équipage » seulement si équipage dans les 7 derniers jours

export type DailyQuest = {
	id: number, -- 1-25 (sauvegardé) ; texte : "quest.daily.<id>"
	tier: string,
	goal: Goal,
	pvp: boolean?, -- jamais proposée en Mode Zen
	crew: boolean?, -- seulement si équipage récent
}

local function daily(
	id: number,
	tier: string,
	kind: string,
	n: number,
	extra: { minRarity: number?, zone: string?, pvp: boolean?, crew: boolean? }?
): DailyQuest
	local e = extra or {}
	return {
		id = id,
		tier = tier,
		goal = { kind = kind, n = n, minRarity = e.minRarity, zone = e.zone },
		pvp = e.pvp,
		crew = e.crew,
	}
end

-- Pool des 25 quêtes du jour (§7.5) : ne jamais réordonner (l'id est sauvegardé)
Quests.Daily = {
	daily(1, "easy", "catch", 40),
	daily(2, "easy", "parades", 5),
	daily(3, "easy", "paradeSize", 8),
	daily(4, "easy", "cometParticipate", 1),
	daily(5, "easy", "wispPop", 3),
	daily(6, "easy", "dash", 15),
	daily(7, "easy", "upgrades", 5),
	daily(8, "easy", "beaconFeed", 5),
	daily(9, "medium", "paradeSize", 15),
	daily(10, "medium", "catchRarity", 5, { minRarity = 3 }),
	daily(11, "medium", "catchWeather", 3),
	daily(12, "medium", "snipNebbies", 5, { pvp = true }),
	daily(13, "medium", "catchZone", 10, { zone = "crater" }),
	daily(14, "medium", "escort", 30, { crew = true }),
	daily(15, "medium", "fusions", 2),
	daily(16, "medium", "idle", 1800),
	daily(17, "medium", "cheers", 2),
	daily(18, "hard", "paradeSize", 25),
	daily(19, "hard", "catchRarity", 3, { minRarity = 4 }),
	daily(20, "hard", "catchRarity", 1, { minRarity = 5 }),
	daily(21, "hard", "cometHold", 10),
	daily(22, "hard", "beaconWin", 1),
	daily(23, "hard", "snipNebbies", 15, { pvp = true }),
	daily(24, "hard", "atlasNew", 3),
	daily(25, "hard", "paradeIdle", 600),
} :: { DailyQuest }

-- Quête hebdomadaire « Grand Défilé » (§7.5) : remise à zéro lundi 00:00 UTC
Quests.Weekly = {
	id = "grandParade",
	goal = { kind = "bankCount", n = 300 } :: Goal,
	reward = { stardust = 300, rotation = "GrandParadeLegendary" } :: Reward,
}

-- Calendrier de connexion indulgent (§7.3) : un jour manqué met la série en pause
Quests.Calendar = {
	{ idleSeconds = 300, minGlow = 500 },
	{ stardust = 50 },
	{ boostSeconds = 900 },
	{ stardust = 150 },
	{ species = 20 }, -- Daybreak Puff
	{ boostSeconds = 1800 },
	{ rotation = "WeeklyWanderer", stardust = 100 },
} :: { Reward }

export type AtlasMilestone = {
	entries: number,
	perch: number?, -- perchoirs supplémentaires
	title: string?, -- Cosmetics.Titles
	style: string?, -- Cosmetics.Styles
	theme: string?, -- Cosmetics.Themes
}

-- Jalons de l'Atlas (§4.14) : réclamés automatiquement par AtlasService
Quests.Atlas = {
	Every = 12,
	Milestones = {
		{ entries = 12, perch = 1 },
		{ entries = 24, perch = 1 },
		{ entries = 36, perch = 1 },
		{ entries = 48, perch = 1 },
		{ entries = 60, perch = 1 },
		{ entries = 72, perch = 1 },
		{ entries = 84, perch = 1 },
		{ entries = 96, perch = 1 },
		{ entries = 108, perch = 1 },
		{ entries = 120, perch = 1 },
		{ entries = 132, title = "cartographer", style = "constellation" },
		{ entries = 144, theme = "atlas" },
	} :: { AtlasMilestone },
	SpeciesComplete = { stardust = 100 } :: Reward,
}

-- Objectif long affiché après la chaîne d'accueil (§7.4)
Quests.LongGoal = "supernova"

return Quests
