--!strict
-- Économie et rythme (GDD §4). Contrat : la STRUCTURE est figée par l'architecte ; seul le paquet
-- logic règle les VALEURS, et seulement pour tenir la porte de simulation (tests/specs/
-- EconomyPacing.spec.luau, GDD §4.24). Chaque réglage est écrit dans docs/04 §21.
-- Règles : aucun service n'écrit un nombre du GDD en dur ; tout passe par ce module (ou Events,
-- Quests, Pads pour les horaires, objectifs et dalles). Les durées sont en secondes, les tailles en
-- unités de taille, les distances en studs. Les récompenses « en secondes de revenu » s'appliquent
-- au revenu du joueur au moment de la récompense (GDD §4.1).

local Balance = {}

-- Version du GDD dont les VALEURS d'économie sont appliquées (docs/04 §16, §25). Contrat v1.2 : la
-- STRUCTURE suit déjà le GDD v1.3 (clés ajoutées ci-dessous avec leur valeur du GDD) ; les valeurs
-- des clés existantes qui changent en v1.3 sont réglées par le paquet logic (notes du contrat v1.2,
-- avec leurs specs et la porte EconomyPacing), qui passe alors cette marque à "1.3". Contract_game
-- vérifie les valeurs témoins de la version annoncée ici ; la publication exige "1.3" (docs/04 §23).
-- Valeurs en attente (logic) : Tiles.cozyBed.Base 25e6 et MinR 3 ; Splorch.Targets (table v1.3),
-- Splorch.BeyondMult 2.6 et Unlocks (« pad.cozyBed » à R = 3) ; Offline.GrowthShare 0.3 ;
-- Babies.MaxOfBiggest 0.5 ; Caps.petSit 100 ; Rewards.PetSitVisitor 2 ; Boosts.ObjectiveMedium et
-- ObjectiveHard 0 ; retrait de Splorch.RecentBuyWindow / RecentBuyShare et de CoinPacks (paquets de
-- pièces retirés du lancement) ; Formulas.tileCost passe de 2^R à Tiles.RScale^R.
Balance.GddValues = "1.2"

-- Nombres géants (GDD §4.2) : toute valeur de pièces, de Pot ou de taille est bornée à [0 ; Max] et
-- jamais NaN ni infinie avant chaque écriture ; sous ExactBelow, les pièces restent des entiers.
Balance.Numbers = {
	Max = 1e300,
	ExactBelow = 1e15,
}

-- Croissance par seconde (GDD §4.3) :
--   g = Base × 2^R × (1 + SnackPerLevel × niveauTapis) × (1 + JellyBonus × familleJelly) × B
Balance.Growth = {
	Base = 1,
	RebirthMult = 2, -- × 2 par Grand Splorch (2^R)
	SnackPerLevel = 1,
	JellyFamilyBonus = 0.10,
	BoostMult = 2, -- B : boosts ×2, jamais cumulés (GDD §4.25)
}

-- Revenu par seconde d'un squishy dans un enclos ou le Bassin (GDD §4.3) :
--   revenu = Coef × rareté × taille × mutation × (1 + StarBonus × étoiles) × A × P × B
--   A = 1 + DecorBonus × décos + FriendBonus × min(FriendMax, amis) + FamePerPoint × min(FameCap, Fame)
--       + bonus de l'Étagère (Trophies) + GoldenPageBonus × pages dorées
Balance.Income = {
	Coef = 0.02,
	StarBonus = 0.5,
	DecorBonus = 0.05,
	FriendBonus = 0.10,
	FriendMax = 4,
	FamePerPoint = 0.01,
	FameCap = 300,
	GoldenPageBonus = 0.01,
	DoubleCoinsMult = 2, -- P : pass ×2 Pièces (pièces seulement, jamais la taille)
}

-- Étagère à trophées (GDD §4.16) : paliers du record d'une espèce, bonus additif dans A
Balance.Trophies = {
	{ min = 1e3, tier = "bronze", bonus = 0.02 },
	{ min = 1e6, tier = "silver", bonus = 0.04 },
	{ min = 1e9, tier = "gold", bonus = 0.06 },
	{ min = 1e12, tier = "crystal", bonus = 0.08 },
}

-- Presser (GDD §4.7) : récompense = floor(max(Min, Seconds × revenu) × (PERFECT ? PerfectMult : 1)
--   × (1 + StreakStep × min(StreakMax, série)) × (familleKitty ? 1 + KittyBonus : 1))
Balance.Press = {
	Cooldown = 8,
	Seconds = 12,
	Min = 10,
	PerfectMult = 2,
	StreakStep = 0.10,
	StreakMax = 5,
	StreakTimeout = 6, -- s sans pression : la série retombe à 0
	KittyBonus = 0.10,
	Range = 10, -- studs (position validée)
	-- Press et PetPress : distance À PLAT (XZ, ZoneRules.distXZ) entre la position validée et le
	-- CENTRE DE LA PLACE du squishy (WorldLayout.penSlot / poolSlot / fencePoint) ≤ Range + RangeTolerance,
	-- et écart vertical depuis les pieds (ZoneRules.feetY) ≤ Catch.MaxDY (GDD §4.7, §12.7)
	RangeTolerance = 2,
	MaxPerSecond = 12, -- au-delà : ignorées sans message
	-- PERFECT : rebond de période Period, calé sur Clock.now() + décalage hash(uid) ; fenêtre de
	-- PerfectBefore avant à PerfectAfter après le sommet (décalée vers le tard : retard des télés)
	Period = 1.2,
	PerfectBefore = 0.08,
	PerfectAfter = 0.20,
	-- tClient accepté dans [maintenant − ClientPast ; maintenant + ClientFuture], sinon maintenant
	ClientPast = 0.35,
	ClientFuture = 0.05,
	RetargetDelay = 0.15, -- s : la cible passe au prochain squishy prêt (client)
	-- points de jauge : uniquement Config/Events.Gauge.Points (press, perfect)
}

-- Pot à Pièces (GDD §4.8, §4.19)
Balance.Pot = {
	Radius = 5, -- studs : encaissement en marchant dessus (position validée, tick)
	AutoInterval = 5, -- s : pass Pot automatique
}

-- Dalles (GDD §4.6) : prix = floor(Base × Growth^L × (ScaleWithR ? RScale^R : 1)), L = niveau actuel.
-- ScaleWithR : la dalle suit R (Tapis, décorations) ; Enclos et Lit douillet ne sont jamais multipliés.
-- Achat sur la dalle (RanchService.step, ZoneRules, positions validées) : entrée à EnterRadius, sortie
-- au-delà de ExitRadius, puis DwellSeconds sur la dalle sans porter ni être dans un autre maintien
-- (boop, bol, Grand Splorch) = UN achat par entrée (HoldState kind "tile" pour l'anneau du client).
-- □ « Acheter » (BuyTile) sur la dalle ou depuis le panneau achète tout de suite.
Balance.Tiles = {
	EnterRadius = 2.5, -- studs : « sur » la dalle
	ExitRadius = 3.5, -- studs : « sortie » (écart contre les achats en rafale)
	DwellSeconds = 0.6, -- s sur la dalle avant l'achat automatique (GDD v1.3)
	RScale = 3.5, -- prix des dalles de la boucle × RScale^R (GDD v1.3 ; remplace 2^R)
	snack = { Base = 20, Growth = 4.0, Levels = 12, ScaleWithR = true, ResetOnSplorch = true, MinR = 0 },
	decor = { Base = 80, Growth = 2.2, Levels = 18, ScaleWithR = true, ResetOnSplorch = true, MinR = 0 },
	pens = { Base = 1200, Growth = 2.2, Levels = 14, ScaleWithR = false, ResetOnSplorch = false, MinR = 0 },
	cozyBed = { Base = 250000, Growth = 1, Levels = 1, ScaleWithR = false, ResetOnSplorch = false, MinR = 1 },
}

-- Enclos, Boîte à dodo, Boîte aux lettres (GDD §4.14)
Balance.Pens = {
	Base = 4, -- places au départ (+1 par niveau de la dalle Enclos)
	BigRanchBonus = 6, -- pass Grand Ranch
	Max = 24, -- jamais plus
	Dodo = 60,
	Mail = 20,
	ShownPerRanch = 24, -- squishies affichés au plus par ranch
}

-- Cuve à Gelée (GDD §4.9). Niveau donné par R, jamais acheté :
--   qualité = min(QualityMax, QualityBase + R) ; vitesse = min(SpeedMax, SpeedBase + SpeedPerR × R) ;
--   buses = min(Mutations.NozzleMax, R) ; intervalle = Interval × SpeedFactor^vitesse (× Bunny)
Balance.Vat = {
	Interval = 90,
	SpeedFactor = 0.85,
	QualityBase = 1,
	QualityMax = 8,
	SpeedBase = 3,
	SpeedPerR = 2,
	SpeedMax = 10,
	HatchTime = 2, -- s : la goutte éclot
	PityRare = 40, -- naissances de suite sans Rare+ : la suivante est au moins Rare
	PityEpic = 150, -- sans Épique+ : au moins Épique
	NewPulls = 3, -- « Nouveauté garantie » : les 3 premiers tirages naturels du compte
	-- Tables de rareté par qualité (en %, GDD §4.9) : Commun, Peu commun, Rare, Épique, Légendaire,
	-- Mythique, Secret. Chaque ligne somme à 100.
	-- stylua: ignore start
	Quality = {
		[0] = { 80, 17, 2.6, 0.4, 0, 0, 0 },
		[1] = { 74, 21, 4, 0.9, 0.1, 0, 0 },
		[2] = { 67, 25, 6, 1.7, 0.28, 0.02, 0 },
		[3] = { 60, 28, 8.5, 2.9, 0.55, 0.05, 0 },
		[4] = { 52, 31, 11.5, 4.5, 0.9, 0.1, 0 },
		[5] = { 45, 32, 15, 6.5, 1.3, 0.19, 0.01 },
		[6] = { 38, 33, 18, 8.7, 1.95, 0.33, 0.02 },
		[7] = { 31.5, 33, 21, 11, 2.9, 0.57, 0.03 },
		[8] = { 25, 32, 24, 14, 4, 0.96, 0.04 },
	} :: { [number]: { number } },
	-- stylua: ignore end
}

-- Bassin de Fusion et combos (GDD §4.10)
Balance.Fusion = {
	PoolSlots = 5, -- + 1 avec la famille Axolo
	SizeMult = 1.25, -- taille = (a + b) × 1,25
	MaxStars = 5,
	FuseDelay = 0.4, -- s (minuteur du serveur)
	ComboDelay = 0.6, -- s entre deux étapes de la chaîne
	ComboSeconds = 20, -- étape k : ComboSeconds × k × revenu du squishy obtenu
	ThrowRange = 12, -- studs du Bassin pour « Lancer »
	PersonalFrom = 3, -- combo ≥ 3 : message personnel
	BannerFrom = 4, -- combo ≥ 4 : bannière de serveur
	StampFrom = 5, -- combo ≥ 5 : grand tampon « COMBO x5 ! »
	-- points de jauge : uniquement Config/Events.Gauge.Points.fuseStep
}

-- Portage (GDD §4.10) et cible (GDD §10.4)
Balance.Carry = {
	PickRange = 10, -- studs
}

-- Vendre, ranger, relâcher, verrou (GDD §4.13)
Balance.Sell = {
	Seconds = 60, -- 60 s du revenu actuel du squishy
	Min = 10,
	Hold = 0.6, -- s : maintien pour un Rare+ ou un squishy muté, pour chaque relâche et pour « Ranger »
	MaxBatch = 84, -- uids par message (enclos + Dodo, pour « Ranger »)
}

Balance.Release = {
	MeadowKeep = 12, -- squishies relâchés visibles dans la Prairie des copains
}

-- Créature en fuite personnelle (GDD §4.11)
Balance.Runaway = {
	Interval = 60, -- s après la fin de la précédente (Froggy : Species.Families.froggy.bonus)
	Duration = 20,
	HopDistance = 4.5,
	HopTime = 0.5,
	PauseEvery = 3, -- bonds
	Pause = 0.6,
	Radius = 35, -- studs autour de la Fontaine de Gelée
	SizeShare = 0.05, -- 5 % du plus gros squishy
	MinSize = 1,
}

-- Capture (GDD §4.11, §4.12, §4.21) : rayon + tolérance de latence côté serveur
Balance.Catch = {
	Radius = 5,
	OwnerRadius = 8, -- propriétaire de sa fuite du Rush
	Tolerance = 1.5,
	MaxDY = 8, -- écart vertical maximal
	NearRadius = 30, -- « de près » (Golden, captures du Rush)
	InputBuffer = 0.25, -- s : appui □ juste avant d'entrer à portée (client)
	-- Catch(id, tClient) et Leap(dirX, dirZ, tClient) : tClient ramené dans [maintenant − ClientPast ;
	-- maintenant] ; la capture compare SeededPath.pos(tClient) à MoveCheck.positionAt(joueur, tClient),
	-- distance À PLAT ≤ rayon + Tolerance, écart vertical depuis les PIEDS ≤ MaxDY (GDD §12.5)
	ClientPast = 0.35,
}

-- Golden Wobbler (GDD §4.11) ; horaires dans Events.Golden
Balance.Golden = {
	Quality = 4,
	SizeShare = 0.25,
	MinSize = 10,
	WinCooldown = 1200, -- s : le gagnant ne peut pas regagner pendant 20 min
	SpeedStart = 14,
	SpeedEnd = 10,
}

-- Monture et bond (GDD §4.12)
Balance.Ride = {
	SpeedMult = 1.4, -- WalkSpeed 16 → 22,4
	BaseWalkSpeed = 16,
	BaseJumpHeight = 7.2,
	BaseHipHeight = 2, -- HipHeight du personnage R15 par défaut
	HipFactor = 0.75, -- HipHeight = base + 0,75 × diamètre affiché
	-- Selles gagnées pour toujours par le record (biggestEver) ; taille affichée fixée par la selle
	Saddles = {
		{ key = "small", minSize = 1200, jumpHeight = 8.6, scale = 2.85 },
		{ key = "big", minSize = 1e6, jumpHeight = 10.8, scale = 3.5 },
		{ key = "giant", minSize = 1e12, jumpHeight = 13, scale = 4 },
	},
}

Balance.Leap = {
	Distance = 12, -- studs au sol
	Duration = 0.35, -- s
	Apex = 2.5, -- studs (visuel)
	Cooldown = 4,
	AimRange = 16, -- studs : position future de la créature à l'atterrissage
	AimCone = 40, -- ± degrés autour de la direction du stick
	SwitchRatio = 0.8, -- le marqueur change si une autre créature est 20 % plus proche
	DirMin = 0.5, -- norme de (dirX, dirZ) acceptée
	DirMax = 1.5,
	-- Bond accordé (contrat v1.2, note INT-MOVE) : ChaseService appelle MoveCheck.grant(player,
	-- Distance, Duration, tStart) ; crédit rétroactif et écart minimal entre deux crédits dans
	-- Server/Movement/Tuning (GrantRetro 0,3 s, GrantMinGap 4 s). Plus de GrantSpeed (noteSpeed).
}

-- Échelle de taille visuelle (GDD §4.2) : échelle = 1 + LogFactor × log10(max(1, S)) ; Ø = 2 × échelle
Balance.SizeScale = {
	LogFactor = 0.6,
	BaseDiameter = 2,
	PenCap = 4, -- plafond d'affichage dans un enclos
	SilhouetteCap = 19, -- silhouette du ranch et statue de la place
}

-- Grand Splorch (GDD §4.15) : objectif = taille du plus gros squishy
Balance.Splorch = {
	-- stylua: ignore start
	Targets = {
		15000, 40000, 110000, 300000, 800000,
		2.2e6, 5.8e6, 16e6, 42e6, 110e6,
		310e6, 830e6, 2.3e9, 6.1e9, 16e9,
		44e9, 120e9, 320e9, 870e9, 2.4e12,
	} :: { number }, -- Targets[R + 1] = objectif pour passer de R à R + 1
	-- stylua: ignore end
	BeyondMult = 2.7, -- R ≥ 20 : objectif précédent × BeyondMult, arrondi à 2 chiffres significatifs (v1.3 : 2,6, logic)
	Fame = 5,
	HoldConfirm = 1.5, -- s (geste client)
	BurstAt = 3.2, -- s après le début du spectacle : application au profil d'un seul bloc
	Duration = 7.5, -- s de spectacle
	-- Cadeaux aux autres joueurs (payés par le jeu)
	GiftSeconds = 60,
	GiftSizeShare = 0.05,
	GiftMinSize = 1,
	GiftMutationCopyChance = 0.10, -- copie une mutation de multiplicateur ≤ GiftMutationMaxMult
	GiftMutationMaxMult = 5, -- Doré
	-- Spectateurs (GDD §4.15) : spectacle complet (capsule, secousse, vibration, APPLAUDIR) au plus une
	-- fois toutes les FullShowGap s par spectateur (mémoire de session de SplorchService) ; sinon
	-- version courte (Celebrate "splorch" avec short = true : cadeau compté directement)
	FullShowGap = 180,
	-- OBSOLÈTE (contrat v1.2 : paquets de pièces retirés du lancement, plus de 2e confirmation) : lu
	-- seulement par Formulas.splorchPreview (recentBuy) ; logic l'en retire puis supprime ces deux clés
	RecentBuyWindow = 1800,
	RecentBuyShare = 0.5,
	-- Emplacements de Meilleur Ami débloqués : 1 dès le départ, 2 à R = 3, 3 à R = 10
	BestFriendSlotsAt = { 0, 3, 10 },
	-- Déblocages par R (aperçu : tuiles « Tu gagnes »)
	Unlocks = {
		[1] = { "family.axolo", "pad.cozyBed" },
		[3] = { "family.bunny", "bestFriend.2" },
		[5] = { "family.spiky", "title.splorch_star" },
		[10] = { "bestFriend.3", "title.splorch_legend" },
		[15] = { "title.splorch_hero" },
		[20] = { "title.jelly_titan" },
	} :: { [number]: { string } },
}

-- Hors ligne (GDD §4.19)
Balance.Offline = {
	CapHours = 8,
	CozyBedHours = 12,
	GrowthShare = 0.5, -- croissance sans boost × GrowthShare × durée (v1.3 : 0,3, logic)
	-- La croissance hors ligne du ranch s'arrête quand le plus gros squishy d'enclos ou du Bassin atteint
	-- StopAt × objectif(R) : ΔG = clamp(g sans boost × GrowthShare × durée, 0, max(0, StopAt × objectif(R)
	-- − plus gros)) (GDD v1.3, §4.19 ; Formulas.offlineGrowth, rebase de DataService.onPrepare)
	StopAt = 0.9,
	PotShare = 0.25, -- revenu de départ sans boost × 25 % × durée
	ReturnScreenMin = 600, -- s d'absence : écran de retour (GDD §7.2)
}

-- Fame (GDD §4.18)
Balance.Fame = {
	Booped = 1, -- squishy boopé puis rendu
	Hero = 2, -- capture Héros
	Wild = 1, -- Wild Wobbler attrapé
	Release = 1,
	Splorch = 5,
	Mega = 1, -- MEGA avec au moins Events.Mega.MinPoints points
}

-- Plafonds journaliers (GDD §4.25), remis à zéro à 00:00 UTC (clé de profil `caps`)
Balance.Caps = {
	rushBabies = 10,
	splorchGifts = 10,
	fameRush = 30, -- Fame du Rush (boopé, Wild Wobblers, Héros), Rush ou Cozy
	fameRelease = 20,
	petSit = 300, -- pressions de pet-sitting RÉCOMPENSÉES comme visiteur (v1.3 : 100, logic)
	petSitIn = 100, -- pressions de pet-sitting reçues comme propriétaire (GDD v1.3, §6.4)
	splorchCoins = 10, -- cadeaux en pièces des Grands Splorch des autres (60 s), ensuite Rewards.GiftSecondsAfterCap
	claps = 10,
	partyBuys = 3,
}

-- Plafonds journaliers PAR AMI (clé de profil caps.petSitBy[tostring(UserId du propriétaire)]) : hors de
-- Balance.Caps, dont chaque clé est un compteur scalaire de `caps` (Logic/Invariants les vérifie un par un)
Balance.CapsPerFriend = {
	petSit = 20, -- pressions comptées pour « Plus serviable » par ami et par jour (GDD v1.3, §6.4, §6.9)
}

-- Bébés et cadeaux : taille = part du plus gros squishy du RECEVEUR (min), et jamais plus de
-- MaxOfBiggest × ce plus gros (GDD §4.25)
Balance.Babies = {
	MaxOfBiggest = 2, -- (v1.3 : 0,5 pour chaque bébé et chaque cadeau, logic)
	RushShare = 0.10, -- de l'ORIGINAL (bébé du Rush), borné par MaxOfBiggest
	RushMin = 1,
	-- Bébé du Rush : mutation de l'original copiée si son multiplicateur ≤ RushMutationMaxMult (Doré),
	-- sinon tirée avec des chances × LuckyMutationMult (GDD v1.3, §4.21.3)
	RushMutationMaxMult = 5,
	WildShare = 0.15,
	WildMin = 5,
	MegaShare = 0.20,
	MegaMin = 10,
	DemoShare = 0.10, -- démonstration de Big Plop : 10 % de la taille du Plop
	DemoMin = 10,
	LuckyQualityBonus = 1, -- Goutte chanceuse (3 objectifs) et Goutte de Lune : qualité + 1
	LuckyMutationMult = 2,
	FallbackSeconds = 60, -- enclos, Dodo et Lettres pleins : le bébé devient 60 s de revenu
}

-- Récompenses en secondes de revenu du joueur (GDD §4.1)
Balance.Rewards = {
	GoldenNear = 60,
	GoldenMiss = 30, -- personne ne l'attrape : joueurs à NearRadius
	MegaSuccess = 60,
	MegaFail = 60,
	Hero = 120, -- capture Héros de son propre squishy en fuite
	OwnerReturn = 60, -- squishy boopé rendu au propriétaire
	RushNear = 20, -- joueur Rush à NearRadius d'une capture du Rush
	PetSitVisitor = 10, -- ×2 si PERFECT (v1.3 : 2, logic)
	Clap = 10,
	GiftSecondsAfterCap = 10, -- cadeau en pièces d'un Grand Splorch au-delà de Caps.splorchCoins (GDD v1.3)
	PlopDay2 = 600, -- palier « Jour 2 » de Nourrir Plop
}

-- Effets de taille sur le squishy en fuite du Rush (GDD v1.3, §4.21.3) : z += g sans boost × secondes,
-- au plus une fois par squishy et par jour UTC (SquishyRecord.gd = Clock.day() du dernier bonus ;
-- SquishyService.growFor). Remplace les pourcentages de la v1.2 (cumulables à deux comptes).
Balance.RushSize = {
	HeroGrowthSeconds = 3600, -- capture Héros : + 1 h de croissance du ranch pour ce squishy
	ReturnGrowthSeconds = 1800, -- personne ne l'attrape : + 30 min
}

-- Boosts (GDD §4.25, §7.3, §7.4, §8.3) : ×2 jamais cumulés ; un boost personnel est en pause pendant
-- un boost de serveur
Balance.Boosts = {
	WobbleParty = 300,
	SquishParty = 600,
	AdminParty = 600,
	SquishPartyLeaver = 600, -- l'acheteur part avant la fin : boost personnel gardé
	ObjectiveMedium = 300, -- (v1.3 : 0, plus de boost dans les objectifs, logic)
	ObjectiveHard = 600, -- (v1.3 : 0, logic)
	FeedDay = 300, -- jour de Nourrir Plop sans palier
	-- jour de palier : 5 min comme les autres jours (GDD §7.3 et §4.25, révision 1.3 ; réglage logic
	-- pour tenir la porte EconomyPacing : avec 900, premier Grand Splorch trop tôt)
	FeedMilestone = 300,
}

-- OBSOLÈTE (contrat v1.2 : paquets de pièces retirés du lancement, GDD §8.3) : lu seulement par
-- Formulas.coinPack ; logic retire coinPack puis supprime cette table (autorisé par le contrat)
Balance.CoinPacks = {
	CoinsSmall = { minutes = 30, min = 5000 },
	CoinsBig = { minutes = 120, min = 20000 },
}

return Balance
