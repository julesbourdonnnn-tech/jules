--!strict
-- Accueil, objectifs du jour, Nourrir Plop, jalons du Squishydex, carte « Plop a sommeil »
-- (GDD §3, §4.17, §4.20, §7.3, §7.4, §16.1). Contrat (architecte) : données figées.
-- Lu par QuestService (serveur), Logic/QuestRules (pur : « Proposé si », tirage, remise à zéro),
-- OnboardingController et les panneaux (client). Textes : « objective.<id> », « onboarding.<key> »,
-- « plop.reward.<key> », « dex.milestone.<n> » (EN/FR).

local Quests = {}

-- =============================================================================================
-- Accueil (GDD §3) : étapes numérotées de l'entonnoir (AnalyticsService) et script de l'horloge
-- =============================================================================================

export type OnboardingStep = {
	step: number, -- numéro de l'entonnoir (1-11)
	key: string, -- nom de l'étape (analytics) et suffixe des textes « onboarding.<key> »
	hint: string?, -- consigne affichée (glyphe + mot) ; nil = aucune
	glyph: string?, -- action dont le glyphe est montré : "action" | "pickup" | "leap" | "ride" | "menu" | "move" | "target"
	scriptedAt: number?, -- s de jeu cumulé où le serveur déclenche l'événement scripté (sinon : geste du joueur)
}

Quests.Onboarding = {
	-- s de jeu : la Cuve et les fuites suivent le script jusqu'à ScriptUntil, puis leurs règles normales
	ScriptUntil = 300,
	StepTimeout = 90, -- s : sans le geste demandé, la consigne se range ; l'accueil continue
	DemoAt = 180, -- démonstration de Big Plop (toujours jouée)
	RunawayAt = 120, -- première créature en fuite (Mochi Mew, Commun)
	FirstRunawaySpecies = 5,
	TwinAt = 40, -- jumeau de Plop (naissance scriptée : Plop, 0 étoile, taille 1)
	FirstPullAt = 165, -- premier vrai tirage (2:45)
	VatPauseFrom = 165, -- fuites personnelles en pause entre 2:45 et 5:00
	VatPauseUntil = 300,
	ObjectivesAt = 300, -- carte des objectifs du jour (non bloquante)
	PlopGiftDistance = 5, -- studs devant le joueur
	TargetChooseHint = 4, -- s : glyphes L1 R1 « Choisir », une seule fois
	WalkHintAfter = 4, -- s sans bouger le stick : glyphe du stick gauche « Marcher »
	MenuLessonStep = 10, -- avant cette étape, △ et croix ↓ ne font qu'un son Bump
	EventsQuietUntilStep = 9, -- événements de serveur discrets pour le nouveau jusqu'à l'étape 9
	QuietSkyTint = 0.3, -- teinte du ciel du Rush à 30 %
	QuietMusicDb = -12,
	Steps = {
		{ step = 1, key = "loaded" },
		{ step = 2, key = "firstPress", hint = "press", glyph = "action" },
		{ step = 3, key = "firstTile", hint = "walk", glyph = "move" },
		{ step = 4, key = "vatBuilt", scriptedAt = 40 },
		{ step = 5, key = "firstFusion", hint = "pickup", glyph = "pickup" },
		{ step = 6, key = "firstPot", hint = "walk", glyph = "move" },
		{ step = 7, key = "firstCatch", hint = "leap", glyph = "leap", scriptedAt = 120 },
		{ step = 8, key = "firstPull", scriptedAt = 165 },
		{ step = 9, key = "firstRide", hint = "ride", glyph = "ride" },
		{ step = 10, key = "objectives", hint = "menu", glyph = "menu", scriptedAt = 300 },
		{ step = 11, key = "firstSplorch" },
	} :: { OnboardingStep },
}

-- =============================================================================================
-- Objectifs du jour (GDD §7.4)
-- =============================================================================================

export type ObjectiveDef = {
	id: number,
	tier: "easy" | "medium" | "hard",
	stat: string, -- compteur suivi (événement du serveur, voir QuestService)
	goal: number,
	condition: string, -- règle « Proposé si » (Logic/QuestRules) : "always" | "tilesLeft3" |
	-- "megaSoon" | "friendOnServer" | "rMin1" | "rMin3" | "splorchSoon" | "stampsUnder120"
	streak: boolean?, -- « 5 PERFECT de suite » : compteur remis à 0 par une pression non PERFECT
}

Quests.Objectives = {
	{ id = 1, tier = "easy", stat = "press", goal = 30, condition = "always" },
	{ id = 2, tier = "easy", stat = "perfect", goal = 10, condition = "always" },
	{ id = 3, tier = "easy", stat = "runawayCatch", goal = 2, condition = "always" },
	{ id = 4, tier = "easy", stat = "tileBuy", goal = 3, condition = "tilesLeft3" },
	{ id = 5, tier = "easy", stat = "potCollect", goal = 5, condition = "always" },
	{ id = 6, tier = "easy", stat = "emote", goal = 3, condition = "always" },
	{ id = 7, tier = "medium", stat = "fusion", goal = 2, condition = "always" },
	{ id = 8, tier = "medium", stat = "vatHatch", goal = 5, condition = "always" },
	{ id = 9, tier = "medium", stat = "perfectStreak", goal = 5, condition = "always", streak = true },
	{ id = 10, tier = "medium", stat = "megaJoin", goal = 1, condition = "megaSoon" },
	{ id = 11, tier = "medium", stat = "goldenRace", goal = 1, condition = "always" },
	{ id = 12, tier = "medium", stat = "petSitPress", goal = 10, condition = "friendOnServer" },
	{ id = 13, tier = "medium", stat = "rushCatchOrBoop", goal = 1, condition = "always" },
	{ id = 14, tier = "hard", stat = "combo2", goal = 1, condition = "rMin1" },
	{ id = 15, tier = "hard", stat = "rareGet", goal = 1, condition = "rMin3" },
	{ id = 16, tier = "hard", stat = "splorch", goal = 1, condition = "splorchSoon" },
	{ id = 17, tier = "hard", stat = "wildCatch", goal = 1, condition = "always" },
	{ id = 18, tier = "hard", stat = "stamps", goal = 3, condition = "stampsUnder120" },
} :: { ObjectiveDef }

Quests.ObjectiveRules = {
	PerDay = 3, -- un facile, un moyen, un difficile
	Day1 = { 1, 3, 7 }, -- jour 1 (accueil) : fixes, « Presse 30 », « Attrape 2 », « Fais 1 fusion »
	RerollsPerDay = 1,
	FeasibleWithin = 1200, -- s : un objectif n'est proposé que s'il est faisable en 20 min
	MegaSoonWithin = 1200, -- « Un MEGA commence dans les 20 min »
	StampsUnder = 120,
	-- Récompenses : minutes de revenu ; plus aucun boost ×2 dans les objectifs (GDD v1.3, §7.4 : les
	-- sources de ×2 du joueur sont le bol de Plop et la Wobble Party)
	Rewards = {
		easy = { incomeSeconds = 180, boost = 0 },
		medium = { incomeSeconds = 360, boost = 0 },
		hard = { incomeSeconds = 600, boost = 0 },
	},
	-- Les 3 terminés : une Goutte chanceuse (naissance de qualité + 1, mutations × 2 ; Balance.Babies)
	AllDoneReward = "luckyDrop",
}

-- =============================================================================================
-- Nourrir Plop (GDD §4.20, §7.3) : jours au total, jamais une série
-- =============================================================================================

export type PlopReward = {
	day: number,
	key: string, -- texte « plop.reward.<key> »
	kind: "sticker" | "coins" | "saddle" | "trail" | "outfit" | "emote" | "flag" | "title" | "theme" | "bowl",
	id: string, -- identifiant du cosmétique (Config/Cosmetics) ; "" pour les pièces
}

Quests.Feed = {
	Hold = 2, -- s de maintien de □ devant le bol (mesuré par le serveur ; GDD v1.3, §4.20)
	HoldGrace = 0.5,
	Radius = 8, -- studs du bol, à plat (ZoneRules.distXZ), écart vertical depuis les pieds ≤ Balance.Catch.MaxDY
	Milestones = {
		{ day = 1, key = "day1", kind = "sticker", id = "day1" },
		{ day = 2, key = "day2", kind = "coins", id = "" },
		{ day = 3, key = "day3", kind = "saddle", id = "peach" },
		{ day = 5, key = "day5", kind = "trail", id = "pinkBubbles" },
		{ day = 7, key = "day7", kind = "outfit", id = "plopBib" },
		{ day = 10, key = "day10", kind = "emote", id = "bellyFlop" },
		{ day = 14, key = "day14", kind = "flag", id = "day14" },
		{ day = 21, key = "day21", kind = "saddle", id = "strawberry" },
		{ day = 30, key = "day30", kind = "title", id = "plops_best_friend" },
		{ day = 50, key = "day50", kind = "trail", id = "sprinkles" },
		{ day = 75, key = "day75", kind = "theme", id = "candyNight" },
		{ day = 100, key = "day100", kind = "bowl", id = "goldenBowl" },
	} :: { PlopReward },
}

-- =============================================================================================
-- Squishydex (GDD §4.17) : jalons (tampons d'espèces + de mutations), tous gratuits et cosmétiques
-- =============================================================================================

export type DexMilestone = {
	stamps: number,
	kind: "title" | "saddle" | "trail" | "flag" | "theme" | "dex",
	id: string,
}

Quests.Dex = {
	MutationEntries = 9, -- 26 × 9 = 234 entrées de mutation au lancement
	StarBadges = 5, -- badges ★1 à ★5 par espèce
	Milestones = {
		{ stamps = 10, kind = "title", id = "little_collector" },
		{ stamps = 25, kind = "saddle", id = "mint" },
		{ stamps = 50, kind = "trail", id = "bubbles" },
		{ stamps = 75, kind = "title", id = "squishologist" },
		{ stamps = 100, kind = "flag", id = "squishydex" },
		{ stamps = 130, kind = "saddle", id = "lavender" },
		{ stamps = 160, kind = "theme", id = "moonlit" },
		{ stamps = 200, kind = "title", id = "dex_master" },
		{ stamps = 260, kind = "dex", id = "goldenDex" }, -- Squishydex doré et emote couronne
	} :: { DexMilestone },
}

-- =============================================================================================
-- Carte « Plop a sommeil » et rappels (GDD §4.20, §7.1)
-- =============================================================================================

Quests.Sleepy = {
	At = { 3600, 7200 }, -- s de jeu dans la session
}

Quests.Reminders = {
	SleepGrowAt = 600, -- s de jeu : « Tes squishies grandissent même quand tu dors »
}

-- Boutique Robux cachée pendant les 10 premières minutes de jeu cumulé (GDD §8.1 n° 4)
Quests.ShopHiddenUntil = 600

-- =============================================================================================
-- Contrat v2.0 (GDD v2.0 §7.5, §4.17 ; docs/04 §27.6) : piste de la semaine, Défis de Splorch,
-- Carnet du Ranch, maîtrise. Lus seulement quand WeeklyTrack, Carnet, Mastery sont ouverts.
-- =============================================================================================

-- Piste de la semaine : 12 paliers (points à gagner pour chacun ; "drop" = Goutte chanceuse,
-- "cosmetic" = cosmétique de la semaine, Cosmetics.WeeklyRotation ; sinon des Confettis), 2 points
-- par objectif du jour, 5 par Défi ; période = semaine UTC du lundi (EpochOffset : lundi 5 janvier
-- 1970 00:00 UTC), la première va de la 1re connexion v2 au 2e lundi suivant
Quests.WeeklyTrack = {
	Tiers = { 2, 2, 3, "drop", 3, 4, 4, "drop", 5, 5, 6, "cosmetic" } :: { any },
	PointsPerObjective = 2,
	PointsPerChallenge = 5,
	PointsPerTier = 2,
	EpochOffset = 345600,
	Week = 604800,
	ChallengesPerWeek = 3,
}

-- Défis de Splorch (Annexe B.7) : id définitif = position ; target = objectif ; stat = compteur lu ;
-- minDays = jours joués avant de pouvoir le tirer ; dropWhenWorkshopDone = retiré quand l'Atelier
-- et « Pour le plaisir » sont complets. Un Défi n'est tiré que s'il est faisable dans le temps de jeu
-- médian des 7 derniers jours (entre 30 min et 2 h, QuestRules.challengeFeasible)
-- stylua: ignore start
Quests.Challenges = {
	{ id = 1, key = "challenge.1", stat = "splorches", target = 2 },
	{ id = 2, key = "challenge.2", stat = "confettiEarned", target = 20, dropWhenWorkshopDone = true },
	{ id = 3, key = "challenge.3", stat = "upgradesBought", target = 10 },
	{ id = 4, key = "challenge.4", stat = "recordBeaten", target = 1 },
	{ id = 5, key = "challenge.5", stat = "ascends", target = 1 },
	{ id = 6, key = "challenge.6", stat = "combo3", target = 1 },
	{ id = 7, key = "challenge.7", stat = "rareHatches", target = 2 },
	{ id = 8, key = "challenge.8", stat = "newStamps", target = 5 },
	{ id = 9, key = "challenge.9", stat = "megas", target = 2 },
	{ id = 10, key = "challenge.10", stat = "feedDays", target = 3, minDays = 3 },
	{ id = 11, key = "challenge.11", stat = "catches", target = 5 },
	{ id = 12, key = "challenge.12", stat = "perfects", target = 30 },
}
-- stylua: ignore end

-- Carnet du Ranch : paliers de niveaux achetés (stats.upgradesBought) et leur récompense
-- (Cosmetics.List since = 2 ou Cosmetics.DecoPerso, source carnet)
Quests.Carnet = {
	Tiers = { 50, 100, 250, 500, 1000, 2500, 5000, 10000 },
	Rewards = {
		[50] = "title.builder",
		[100] = "saddle.brick",
		[250] = "flag.buildingSite",
		[500] = "title.architect",
		[1000] = "trail.littleHammers",
		[2500] = "emote.hammerTap",
		[5000] = "title.masterArchitect",
		[10000] = "outfit.buildersCrown",
	} :: { [number]: string },
	DecoAt = { [750] = "workbench", [7500] = "sugarCrane" } :: { [number]: string },
}

-- Maîtrise d'une espèce (+ Balance.Confetti.Mastery) et jalons de taille géante (tours appris)
Quests.Mastery = {
	Tricks = {
		{ size = 100, key = "trick.peekaboo" },
		{ size = 1200, key = "trick.spin" },
		{ size = 1e6, key = "trick.flip" },
		{ size = 1e9, key = "trick.dance" },
		{ size = 1e12, key = "trick.fireworks" },
	},
}

return Quests
