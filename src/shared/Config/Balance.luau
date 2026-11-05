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
-- Notes logic du contrat v1.2 appliquées (revue logic du 01/11/2026, docs/04 §21) : Tiles.cozyBed
-- 25e6 dès R = 3 ; Splorch.Targets v1.3, BeyondMult 2.6, Unlocks (« pad.cozyBed » à R = 3) ;
-- Offline.GrowthShare 0.3 ; Babies.MaxOfBiggest 0.5 ; Caps.petSit 100 ; Rewards.PetSitVisitor 2 ;
-- Boosts.Objective* 0 ; Splorch.RecentBuy* et CoinPacks retirés ; Formulas.tileCost × Tiles.RScale^R.
Balance.GddValues = "1.3"

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
	-- 22 s (GDD v1.3 aligné le 02/11/2026, avant : 12) : réglage logic du 01/11/2026 pour la porte EconomyPacing v1.2 (docs/04 §21) :
	-- avec 12, les pressions ne faisaient que 40 % des pièces gagnées en jeu au jour 7 (porte ≥ 50 %)
	Seconds = 22,
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
	-- Growth 4,5 (GDD §4.6 aligné le 02/11/2026, avant : 4,0) : réglage logic du 01/11/2026 pour la porte EconomyPacing v1.2 (docs/04
	-- §21) : avec 4,0, les pièces perdues au Grand Splorch valaient 13 à 17 fois le prix du Tapis 12 (santé
	-- ≤ 10) ; le GDD ne retrouve « 3 fois, Tapis 12 à 93 % de la boucle » qu'avec A = 1 (sans décorations,
	-- Fame ni trophées). Niveaux 0 à 3 presque inchangés (20, 90, 405, 1 822). Témoin de Contract_game à
	-- mettre à jour par l'architecte (note INT-LR1 de la revue logic).
	snack = { Base = 20, Growth = 4.5, Levels = 12, ScaleWithR = true, ResetOnSplorch = true, MinR = 0 },
	decor = { Base = 80, Growth = 2.2, Levels = 18, ScaleWithR = true, ResetOnSplorch = true, MinR = 0 },
	pens = { Base = 1200, Growth = 2.2, Levels = 14, ScaleWithR = false, ResetOnSplorch = false, MinR = 0 },
	cozyBed = { Base = 25e6, Growth = 1, Levels = 1, ScaleWithR = false, ResetOnSplorch = false, MinR = 3 },
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
	-- délai de sûreté (consigne du propriétaire : chaque état a un délai, note INT-LR10) : après 300 s
	-- de portage, le squishy retourne à sa place, comme un « Poser » (GDD §4.10 : sorties par événement)
	SafetySeconds = 300,
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
		15000, 39000, 100000, 260000, 690000,
		1.8e6, 4.6e6, 12e6, 31e6, 81e6,
		210e6, 550e6, 1.4e9, 3.7e9, 9.7e9,
		25e9, 65e9, 170e9, 440e9, 1.1e12,
	} :: { number }, -- Targets[R + 1] = objectif pour passer de R à R + 1 (≈ 15 000 × 2,6^R, GDD v1.3)
	-- stylua: ignore end
	BeyondMult = 2.6, -- R ≥ 20 : objectif précédent × BeyondMult, arrondi à 2 chiffres significatifs
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
	-- Emplacements de Meilleur Ami débloqués : 1 dès le départ, 2 à R = 3, 3 à R = 10
	BestFriendSlotsAt = { 0, 3, 10 },
	-- Déblocages par R (aperçu : tuiles « Tu gagnes »)
	Unlocks = {
		[1] = { "family.axolo" },
		[3] = { "family.bunny", "bestFriend.2", "pad.cozyBed" },
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
	GrowthShare = 0.3, -- croissance sans boost × GrowthShare × durée
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
	petSit = 100, -- pressions de pet-sitting RÉCOMPENSÉES comme visiteur
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
	MaxOfBiggest = 0.5, -- chaque bébé et chaque cadeau (GDD v1.3, §4.25)
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
	PetSitVisitor = 2, -- ×2 si PERFECT
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
	ObjectiveMedium = 0, -- plus de boost dans les objectifs (GDD v1.3, §7.4)
	ObjectiveHard = 0,
	FeedDay = 300, -- jour de Nourrir Plop sans palier
	-- jour de palier : 5 min comme les autres jours (GDD §7.3 et §4.25, révision 1.3 ; réglage logic
	-- pour tenir la porte EconomyPacing : avec 900, premier Grand Splorch trop tôt)
	FeedMilestone = 300,
}

-- =================================================================================================
-- Contrat v2.0 (GDD v2.0, docs/04 §27.6) : STRUCTURE figée par l'architecte, valeurs de DÉPART du
-- GDD v2.0 ; seul le paquet A1 (logique de progression) les règle ensuite, pour tenir la porte
-- EconomyPacing v2.0 (docs/04 §27.9), et écrit chaque réglage au journal (docs/04 §21). Aucune de ces
-- tables n'est lue tant que son interrupteur Config/Features est coupé : la marque GddValues reste
-- "1.3" (valeurs des clés de la v1.3) ; GddValuesV2 dit quelle version suivent les tables v2.0.
-- Les tables v2.0 sont À PART des tables existantes quand une boucle du code de base les parcourt
-- (Balance.Tiles par EconomyService.applySplorch, Balance.Caps par Invariants et ProfileRepair) :
-- jamais une clé v2.0 dans Balance.Tiles ni dans Balance.Caps.
-- =================================================================================================
Balance.GddValuesV2 = "2.0"

-- Bornes de la progression (GDD §4.6, §4.27) : r ≤ MaxR, Record R ≤ MaxR, A ≤ MaxA
Balance.Prestige = {
	MaxR = 400,
	MaxA = 60,
}

-- Jelly Ascend (GDD §4.27). Condition de la k-ième : ReqR[k] tant que k ≤ #ReqR, puis + ReqStep ;
-- croissance × GrowthMult^A ; prix de la boucle × produit de PriceByA[min(k, #PriceByA)] pour k = 1 … A
-- (le dernier facteur vaut pour toutes les Ascensions suivantes) ; Souvenir de gelée : × RegainMult
-- tant que r ≤ bestR − 3, puis RegainTaper[1] (bestR − 2), [2] (bestR − 1), [3] (1re boucle record)
-- Réglage de la porte d'économie (docs/04 §21, lot A1 3/4) : 15, 20, puis + 4, et un Grand Splorch de
-- plus toutes les 8 Ascensions à partir de la 11e (57, 90, 123, …) : avec + 4 seul, (2,6 / 2)^4 = 2,86
-- < × 3 et la boucle record raccourcissait à chaque Ascension (une Ascension tous les 3 jours pour le
-- joueur de 2 h par jour après A22, tous les 9 jours pour la référence après A11 ; GDD : 4-8 et 10-16).
-- Prix : 0,5 aux 4 premières, 0,32 jusqu'à A10, puis 0,31 (0,29 aux Ascensions qui demandent un Grand
-- Splorch de plus) : sans eux, le Tapis Étoilé n'était presque plus acheté dans les boucles record
-- tardives (10,4 achats de la ligne Tapis par boucle record, limite 10).
Balance.Ascend = {
	-- stylua: ignore start
	ReqR = {
		15, 20, 24, 28, 32, 36, 40, 44, 48, 52,
		57, 61, 65, 69, 73, 77, 81, 85, 90, 94,
		98, 102, 106, 110, 114, 118, 123, 127, 131, 135,
		139, 143, 147, 151, 156, 160, 164, 168, 172, 176,
		180, 184, 189, 193, 197, 201, 205, 209, 213, 217,
		222, 226, 230, 234, 238, 242, 246, 250, 255, 259,
	} :: { number },
	-- stylua: ignore end
	ReqStep = 4,
	GrowthMult = 3,
	-- stylua: ignore start
	PriceByA = {
		0.5, 0.5, 0.5, 0.5, 0.32, 0.32, 0.32, 0.32, 0.32, 0.32,
		0.29, 0.31, 0.31, 0.31, 0.31, 0.31, 0.31, 0.31, 0.29, 0.31,
		0.31, 0.31, 0.31, 0.31, 0.31, 0.31, 0.29, 0.31, 0.31, 0.31,
		0.31, 0.31, 0.31, 0.31, 0.29, 0.31, 0.31, 0.31, 0.31, 0.31,
		0.31, 0.31, 0.29, 0.31, 0.31, 0.31, 0.31, 0.31, 0.31, 0.31,
		0.29, 0.31, 0.31, 0.31, 0.31, 0.31, 0.31, 0.31, 0.29, 0.31,
	} :: { number },
	-- stylua: ignore end
	RegainMult = 3,
	RegainTaper = { 2, 1.5, 1.25 },
	DeclineCardAfter = 300, -- s sans achat possible : carte Conseillé « Jelly Ascend »
	StartFloorOffset = 4.7, -- plancher de StartR(A) (GDD §4.27)
	StartStepPerA = 2,
	HoldSeconds = 3, -- maintien de ✕ de l'aperçu (client)
	ConfirmGuard = 0.6, -- s : boutons de « Prêt à monter ? » grisés
	ConfirmTimeout = 20, -- s : carte fermée sans rien changer
	BurstAt = 4.0, -- s après le début du spectacle : Prestige.apply(profil, "ascend")
	Duration = 10,
	HardCut = 12,
	Fame = 20, -- hors du plafond CapsV2.fameSplorch (critique m10)
	StarRainSeconds = 120, -- Pluie d'étoiles : secondes de revenu des autres joueurs
}

-- Confettis (GDD §4.26) : entiers de 0 à Max ; gagnés en jouant seulement, jamais vendus
Balance.Confetti = {
	PerGrandSplorchBase = 3, -- + min(r, CapR) au nouveau Record R
	CapR = 20,
	PerPetitSplorch = 1,
	PerSkipped = 1, -- Grand Splorch sauté grâce au Tremplin seulement (3 au plus par Ascension)
	PerAscend = 20,
	RegainBonus = 10, -- retour au record après une Ascension (une fois par Ascension)
	RecordBonus = 10, -- premier passage de chaque Record R ≥ RecordBonusFrom
	RecordBonusFrom = 21,
	FullPenBonus = 25, -- place offerte sur un enclos plein
	Mastery = 25,
	Max = 1e9,
	RawUpTo = 99999, -- affichage en entier brut jusqu'ici, puis BigNumber.abbreviate
}

-- Prix des familles nouvelles (GDD §4.6.1) : prix du niveau L (L = niveau actuel, 0 = premier achat)
-- = floor(Base × Growth^L × RScale^r × F(A)), calculé par MULTIPLICATIONS SUCCESSIVES (UpgradeMath).
-- star : Base = prix du Tapis 12 AVANT floor (BaseFrom = "snack", niveau 11), puis × Growth par
-- niveau au-delà de 12. monument : 3 × T12 × RScale^(OpenAt[n]) × RScale^(r − bestR), sans F(A).
Balance.UpgradePrices = {
	star = { BaseFrom = "snack", Growth = 1.25, Levels = 8 },
	gloves = { Base = 2000, Growth = 1.55, Levels = 40 },
	school = { Base = 20000, Growth = 1.75, Levels = 20 },
	monument = { PriceT12 = 3, Levels = 10 },
}

-- Monuments (GDD §4.6) : revenu × (1 + IncomeStep × monuments), multiplicateur à part
Balance.Monuments = {
	OpenAt = { 6, 8, 10, 12, 14, 16, 18, 20, 22, 24 },
	IncomeStep = 0.01,
}

-- Gants Moelleux (GDD §4.7) : récompense de pression × (1 + StepPerLevel × niveau)
Balance.Gloves = {
	StepPerLevel = 0.025,
}

-- Grand Splorch v2.0 (GDD §4.15, §4.26, §4.27) : ajouts à côté de Balance.Splorch
Balance.SplorchV2 = {
	GiftLevelsBase = 1, -- le cadeau du Splorch paie 1 niveau du Tapis (+ ligne « gift » de l'Atelier)
	FreeSnackMax = 6, -- niveaux du Tapis offerts au plus (Tapis de départ + cadeau)
	OfferedPensAt = { 2, 6, 11, 16 }, -- places d'enclos offertes au premier passage de ces Record R
	KeptDecorAt = { { recordR = 8, n = 3 }, { recordR = 14, n = 3 } }, -- + 3 par niveau d'Atelier
	KeptDecorMax = 12,
	RecordSteps = { 0.25, 0.5, 0.75 }, -- étapes du record (carte et éclat, aucune récompense)
	BannerGap = 180, -- s : une bannière de Grand Splorch par joueur au plus
	PetitShow = { Duration = 2.5, HardCut = 4 },
	Chantier = { Duration = 4, HardCut = 6 },
}

-- Plafonds journaliers v2.0 (compteurs caps.<clé> créés par le schéma v2 ; vérifiés par les
-- invariants v2, jamais par la boucle de Balance.Caps)
Balance.CapsV2 = {
	fameSplorch = 50, -- Fame des Grands Splorch par jour
	starRain = 3, -- Pluies d'étoiles reçues par jour
}

-- Cœurs entre ranchs (GDD §4.25)
Balance.Hearts = {
	PerDay = 20,
	PerRanch = 1,
}

-- Hors ligne v2.0 (GDD §4.19, §4.26)
Balance.OfflineV2 = {
	MinPlaySeconds = 120, -- la croissance hors ligne s'arrête à 120 s de croissance maximale de l'objectif
	NightBagHours = 1, -- + 1 h par niveau du Sac de nuit
	MaxHours = 16,
	-- part du revenu hors ligne dans le Pot (Pot de nuit 0, 1, 2) ; 0,30 / 0,35 au GDD v2.0, réglé par la
	-- porte d'économie (docs/04 §21 : offlinePotShare du joueur de 10 min par jour ≤ 2)
	NightPotShares = { 0.25, 0.28, 0.31 },
}

-- Pot à Pièces v2.0 : rayon d'encaissement par niveau d'Aimant (0 à 3)
Balance.PotV2 = {
	MagnetRadii = { 5, 8, 11, 14 },
}

-- Presser v2.0 : série PERFECT maximale 5 + niveau de Super Série (2 au plus)
Balance.PressV2 = {
	SuperStreakMax = 2,
}

-- Plopettes (GDD §4.28) : une Plopette par Record R de ByRecordR (+ Plume de l'Atelier)
Balance.Helpers = {
	ByRecordR = { 2, 4, 6, 8, 12 },
	IntervalBase = 12, -- s entre deux pressions d'une Plopette
	IntervalStep = 0.3, -- − 0,3 s par niveau de l'École
	RewardShare = 1, -- × pressReward sans PERFECT ni série
	ReadyFor = 3, -- s : squishy prêt depuis au moins ReadyFor
	MinDistance = 12, -- studs à plat de la position validée du joueur
	MaxTravel = 3, -- s de trajet au plus
	NapAfter = 300, -- s sans intention acceptée
	TickHz = 10,
}

-- Écran Améliorations (GDD §10.7) : durées et bornes de l'interface et de l'intention BuyUpgrade
Balance.Upgrades = {
	PendingSeconds = 3, -- état « en cours » d'une ligne
	HoldSeconds = 0.6, -- tout achat de l'écran, ×1 compris (critique m16)
	GuardOpen = 0.3, -- InputGuard : relâchement de ✕ vu + 0,3 s à l'ouverture de tout panneau
	GuardFocus = 0.4,
	BulkMax = 40, -- niveaux au plus par message (mode Max)
	NextChipHz = 2, -- puce « Prochain achat » recalculée 2 fois par seconde au plus
	BuildQueueMax = 10, -- cascade de construction : 10 au plus en file
	BuildQueueSeconds = 10,
	RepeatDelay = 0.4,
	RepeatRate = 8,
}

return Balance
