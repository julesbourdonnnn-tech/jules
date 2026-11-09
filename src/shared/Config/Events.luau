--!strict
-- Horloge commune et événements (GDD §2.4, §4.11, §4.21-§4.23, §6.6, §7.5). Contrat (architecte).
-- Tous les horaires sont en UTC et lus par le module pur Logic/EventClock à partir de Clock.now() :
-- serveur et clients calculent les mêmes phases, sans message. Une durée est en secondes.
-- Les interrupteurs (couper un événement en ligne) sont dans Config/Features.

local Events = {}

-- =============================================================================================
-- Calendrier (GDD §2.4)
-- =============================================================================================

-- Golden Wobbler : lâché à :00:30, :10:30, :30:30 et :40:30 (secondes dans l'heure)
Events.Golden = {
	Offsets = { 30, 630, 1830, 2430 },
	Duration = 30,
	-- points de jauge : uniquement Events.Gauge.Points (« de près » = NearCatch "golden" → catch)
}

-- BOOP RUSH : toutes les 10 min à :05, :15… ; sirène 10 s avant ; 90 s
Events.Rush = {
	Period = 600,
	Offset = 300,
	Duration = 90,
	Siren = 10,
	-- Clôture (GDD §4.21.2)
	FenceMax = 4, -- squishies curieux à la clôture par ranch boopable
	FenceAfterBooped = 2, -- ranch boopé au Rush précédent
	FenceRenew = 20, -- s : renouvellement des squishies à la clôture
	FenceNewbornMin = 60, -- s : un squishy né il y a moins de 60 s ne vient pas
	-- Maintien du boop (mesuré par le serveur)
	HoldTime = 2.5,
	HoldTimeOwnerNear = 5, -- propriétaire à OwnerNearRadius de sa clôture (arrivée en cours : le reste double)
	HoldGrace = 0.5, -- s : le maintien finit ou s'annule au plus tard 0,5 s après sa fin prévue
	BoopRadius = 8, -- studs entre le boopeur (rue) et le squishy à la clôture
	OwnerNearRadius = 25,
	-- Fuite (GDD §4.21.2, §12.5)
	EscapeDuration = 25,
	SpeedStart = 16,
	SpeedDecay = 0.32, -- studs/s perdus chaque seconde
	SpeedMin = 8,
	HopTime = 0.45,
	FirstHop = 20, -- premier bond à l'opposé du boopeur
	BooperLock = 6, -- le boopeur ne peut pas attraper sa fuite pendant 6 s
	-- Protections (GDD §4.21.4)
	PerRanchPerRush = 2,
	PerRanchPerHour = 4, -- fenêtre glissante
	BooperCooldown = 20, -- 1 boop réussi toutes les 20 s par joueur
	PairCooldown = 1800, -- même paire boopeur → ranch au plus 1 fois toutes les 30 min
	ServerMax = 10, -- fuites en même temps sur le serveur
	ShieldPlaySeconds = 900, -- bouclier débutant : 15 min de jeu cumulé
	MoonOnlyRarities = { [6] = true, [7] = true }, -- Mythique et Secret : seulement pendant la Lune
	BlockedListMax = 200, -- identifiants de la liste de blocage (ReportBlocked)
	-- Changer de mode (GDD §4.21.1)
	RushSwitchCooldown = 60, -- s depuis le dernier changement pour passer en Rush
	-- Carte du choix : au calme, dès 15:00 de jeu
	CardPlaySeconds = 900,
	CardStillFor = 1.5, -- s sans bouger
	CardMinToNextRush = 60, -- s avant le prochain Rush
	CardEntryGuard = 0.6, -- s : boutons grisés
	CardTimeout = 20, -- s : sans réponse, Cozy
	CardAnimLoop = 6,
}

-- Wild Wobblers (GDD §4.21.5)
Events.Wild = {
	PersonalDelay = 15, -- s après le début du Rush
	SharedBase = 3, -- 3 + 2 × max(0, 6 − N)
	SharedPerMissing = 2,
	SharedFullServer = 6,
	SharedWave = 15, -- s entre deux vagues (un tiers au début)
	SharedPerPlayerPerRush = 2,
	Quality = 3,
	Nozzles = 0,
	Duration = 25,
	-- points de jauge : uniquement Events.Gauge.Points (capture = Caught → catch)
}

-- MEGA SQUISH : :20 et :50 ; alerte 15 s avant ; 60 s de pression + 5 s d'éclatement (GDD §4.22)
Events.Mega = {
	Period = 1800,
	Offset = 1200,
	Warn = 15,
	PressTime = 60,
	BurstTime = 5,
	Diameter = 24,
	Radius = 20, -- studs du centre pour presser
	Points = 1,
	PerfectPoints = 3,
	BouncePeriod = 2, -- s : période du rebond du géant
	PerfectBefore = 0.12,
	PerfectAfter = 0.28,
	Cooldown = 0.4, -- s par joueur
	-- objectif = ceil((Base + PerPlayer × N) × indulgence), N = joueurs ACTIFS à l'atterrissage (Cozy
	-- compris, au moins Events.Activity.MinPlayers ; Server/Util/Activity et Events.Activity)
	TargetBase = 30,
	TargetPerPlayer = 50,
	Leniency = { 1, 0.8, 0.65 }, -- après 0, 1, 2+ échecs de suite
	MinPoints = 10, -- participation (Fame, objectif, récompense d'échec)
	Tiers = { { points = 10, babies = 1 }, { points = 40, babies = 2 }, { points = 80, babies = 3 } },
	QualityBonus = 2, -- bébé : qualité min(8, qualité du joueur + 2)
	MutationMult = 2,
	MoonLunarChance = 0.25, -- MEGA MOON SQUISH : chaque bébé a 25 % de chance d'être Lunaire
	Beat = 0.25, -- s entre deux MegaBeat
	-- points de jauge : uniquement Events.Gauge.Points.mega (réussite, comptée par EventService)
}

-- Jelly Moon : samedi 16:00, 18:00, 20:00, 22:00 UTC ; rattrapage dimanche 16:00 ; 20 min (GDD §4.23)
Events.Moon = {
	Saturday = { 16, 18, 20, 22 }, -- heures UTC (Clock.weekday : 6 = samedi)
	Sunday = { 16 }, -- 0 = dimanche
	Duration = 1200,
	AltarPresence = 300, -- s de présence pendant une séance : 1 Goutte de Lune à la fin
	DropQualityBonus = 1,
	BoopableRushes = { 5, 15 }, -- Rush de :05 et :15 pendant une séance : Mythiques et Secrets boopables
}

-- Un seul grand spectacle à la fois (GDD §2.4) : file du serveur, au plus un toutes les SpectacleGap.
-- Attente affichée d'une entrée de la file (EventState.spectacle.queue[i].eta) : position × SpectacleGap
-- + reste du grand spectacle en cours (Rush, MEGA, Grand Splorch, danse), recalculée à chaque
-- changement ; coupure dure de l'attente à SplorchQueueHardCut (StateTimeouts « splorchQueue »).
Events.SpectacleGap = 20
Events.SplorchQueueHardCut = 480
Events.Spectacles = {
	splorch = { duration = 7.5, hardCut = 10 },
	dance = { duration = 8, hardCut = 10 }, -- danse de Big Plop (jauge pleine)
	-- v2.0 (lot A4, D4) : Jelly Ascend dans la MÊME file que le Grand Splorch, jamais tant que
	-- JellyAscend est coupé ; égal à Balance.Ascend.Duration / HardCut (Contract_v2 le vérifie)
	ascend = { duration = 10, hardCut = 12 },
}

-- Remises à zéro (GDD §2.4)
Events.DailyReset = 0 -- seconde du jour UTC
Events.WeeklyReset = "monday" -- Clock.week()

-- =============================================================================================
-- Jauge du serveur (GDD §4.23)
-- =============================================================================================

-- SOURCE UNIQUE des points de jauge (docs/04 §11.10) : seul EventService convertit les faits du jeu
-- en points, à partir des signaux (Pressed, Hatched, Fused, Caught, NearCatch, Fed, Splorched) et de
-- la réussite du MEGA qu'il calcule lui-même. Aucun autre service n'appelle EventService.addGauge
-- (réservé aux commandes d'administrateur et aux specs) ; aucune autre configuration ne porte de
-- points de jauge (Contract_game le vérifie).
-- GDD v1.3 : seules les pressions PERFECT comptent ; N = joueurs ACTIFS (Events.Activity) ; après
-- chaque WOBBLE PARTY, sieste de Big Plop de RestSeconds : les points continuent de compter, mais
-- aucune fête ne commence avant la fin de la sieste (EventState.gauge.restUntil) : au plus 5 min de
-- ×2 toutes les 25 min.
Events.Gauge = {
	TargetPerPlayer = 600, -- objectif = 600 × max(MinPlayers, N actifs)
	MinPlayers = 2,
	PartyDuration = 300, -- WOBBLE PARTY ×2 pièces et croissance
	RestSeconds = 1200, -- sieste de Big Plop après la fête (jarre grise, « Big Plop se repose mm:ss »)
	Points = {
		press = 0, -- Pressed chez soi (PressInfo.visitor == nil) : une pression ordinaire ne compte pas
		perfect = 1, -- en plus de press si PressInfo.perfect (seule une pression PERFECT compte)
		petSit = 2, -- Pressed avec PressInfo.visitor (au visiteur)
		hatch = 2, -- Hatched
		fuseStep = 3, -- Fused, par étape du combo
		catch = 4, -- Caught (fuite personnelle, Wild Wobbler, Golden, démonstration) ; NearCatch "golden"
		rushCatch = 6, -- Caught de sorte "escape" (fuite du Rush)
		rushNear = 2, -- NearCatch "rush"
		mega = 5, -- réussite du MEGA, à chaque participant (≥ Events.Mega.MinPoints)
		feed = 10, -- Fed
		splorch = 25, -- Splorched (une fois par Grand Splorch)
		-- v2.0 (lot A4, D3, GDD m9) : Petit Splorch (PrestigeApplied « petit », jamais Splorched) ; une
		-- Jelly Ascend ne donne aucun point (sa Pluie d'étoiles est son cadeau)
		petitSplorch = 5,
	},
}

-- Joueurs ACTIFS (GDD v1.3, §4.22, §4.23) : N du MEGA et de la jauge. Un joueur est actif s'il a eu
-- une intention de jeu acceptée (Config/Intents, activity = true) ou un déplacement validé d'au moins
-- MoveStuds dans les Window dernières secondes (Server/Util/Activity), ou s'il est à MegaAlertRadius
-- studs au plus du centre de la place pendant l'alerte du MEGA (EventService) ; N vaut au moins
-- MinPlayers. Analytique MegaResult : N et participants.
Events.Activity = {
	Window = 120,
	MoveStuds = 4,
	MegaAlertRadius = 60,
	MinPlayers = 1,
}

-- =============================================================================================
-- Démonstration de Big Plop, bouclier, LiveOps, fêtes
-- =============================================================================================

-- Démonstration de Big Plop pendant l'accueil (GDD §4.21.6)
Events.Demo = {
	Duration = 20,
	Speed = 8,
}

-- Squish Party (produit, GDD §8.3) et fête d'administrateur (GDD §7.5). Vendue seulement si elle peut
-- commencer aussitôt (bouton caché pendant une fête) ; un reçu qui arrive pendant une fête la PROLONGE
-- de SquishPartyDuration (aucune file en mémoire) ; segments suivis par acheteur : à la fermeture du
-- serveur (BindToClose), les secondes non jouées de chaque achat (≤ SquishPartyDuration) passent en
-- boost personnel de l'acheteur (boosts.personalLeft), sauvegardé avant la fermeture.
Events.Party = {
	SquishPartyDuration = 600,
	MaxQueued = 1, -- OBSOLÈTE (contrat v1.2) : plus aucune fête en attente (un achat croisé prolonge)
	AdminGoldens = 5, -- 5 Golden Wobblers en 5 min
	AdminGoldenWindow = 300,
	AdminBoostDuration = 600,
	LiveOpsTopic = "LiveOps", -- sujet MessagingService
	WorldFirstTopic = "WorldFirst", -- réservé (janvier)
}

-- =============================================================================================
-- Bannières de serveur (GDD §6.6) : file de 3 au plus, 3 s chacune, une seule à l'écran
-- =============================================================================================

Events.Banners = {
	QueueMax = 3,
	Duration = 3,
	PerSourceCooldown = 10, -- un même joueur déclenche au plus une bannière toutes les 10 s
	NewcomerHideUntilStep = 9, -- un nouveau ne voit pas celles des autres avant l'étape 9 de l'accueil
	StaleAfter = 30, -- bannières mises en attente pour un nouveau : jetées après 30 s
	-- Priorités (1 = plus haute), recopiées dans Server/Util/Notify.BANNER_PRIORITY par
	-- CommunityService.Init ; chaque sorte a son texte « banner.<sorte> » (EN/FR)
	Priority = {
		splorch = 1,
		secretHatch = 2,
		mythicHatch = 2,
		rareMutation = 2, -- Flop, Glitch, Arc-en-ciel
		combo5 = 3,
		combo4 = 3,
		legendHatch = 4,
		record = 5, -- fanfare du premier à 1M, 1B, 1e12, 1e15 sur ce serveur
		goldenCaught = 6,
		squishParty = 7,
		squishPartyBy = 7,
		wobbleParty = 7,
		adminParty = 7,
	} :: { [string]: number },
	-- v2.0 (lot A4, D5) : priorités des bannières v2.0, recopiées aussi dans Notify.BANNER_PRIORITY par
	-- CommunityService.Init ; texte « banner.<sorte> » depuis le lot B3 (« banner.ascend », renommé de
	-- « ascend.banner », D18, journal B3-7) : fusionnées dans Priority à l'étape I
	PriorityV2 = {
		ascend = 1,
	} :: { [string]: number },
	RecordThresholds = { 1e6, 1e9, 1e12, 1e15 },
}

-- =============================================================================================
-- Costumes de saison (GDD §7.6, §17.2) : calendrier en Clock.unix()
-- =============================================================================================

Events.Costumes = {
	{ key = "winter2026", from = 1797033600, to = 1799452800 }, -- 12/12/2026 → 09/01/2027 (UTC)
	{ key = "kings2027", from = 1799452800, to = 1801440000 }, -- galette des rois (janvier)
	{ key = "valentine2027", from = 1802217600, to = 1802822400 }, -- Saint-Valentin (février)
}

-- =============================================================================================
-- Contrat v2.0 (GDD v2.0 §2.4, §4.25, §7.5 ; docs/04 §27.6) : lus seulement quand Weather, Fete,
-- JellyAscend sont ouverts
-- =============================================================================================

-- Météo de Wobbleton : PUREMENT VISUELLE (décision par défaut n° 4 : aucun bonus de mutation ni de
-- jeu) ; fenêtres en minutes de l'heure UTC, 4 sortes (weather.sunny, sprinkles, bubbles, rainbow)
Events.Weather = {
	Windows = { { 8, 13 }, { 38, 43 } },
	Kinds = { "sunny", "sprinkles", "bubbles", "rainbow" },
	visualOnly = true,
}

-- Place en fête : seuils de points du serveur pour chaque niveau (décor seulement) ; points en mémoire
-- (EventService, lot A4, D26), remis à zéro avec le serveur : Grand Splorch (Splorched), Jelly Ascend
-- (PrestigeApplied « ascend »), réussite du MEGA (une fois par MEGA), début d'une Wobble Party ; un
-- Petit Splorch ne compte pas
Events.Fete = {
	Levels = { 5, 15, 30, 50, 80 },
	Points = { splorch = 1, ascend = 1, mega = 3, party = 2 },
}

-- Pluie d'étoiles d'une Jelly Ascend : revenu des autres joueurs (Balance.Ascend.StarRainSeconds),
-- plafonnée par Balance.CapsV2.starRain par jour
Events.StarRain = { Duration = 10 }

return Events
