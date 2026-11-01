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

return Quests
