--!strict
-- Équilibrage et règles chiffrées du jeu (GDD §4, §6, §9, §12). Contrat : docs/04-architecture.md §9.
-- Chaque table reprend la clé du GDD ([Balance.Snip.Radius] → Balance.Snip.Radius).
-- La STRUCTURE est figée par le contrat ; seules les VALEURS peuvent être réglées par le paquet
-- « logic » (simulation §4.18), chaque changement étant tracé dans docs/04-architecture.md
-- section « Réglages d'économie ».

local Balance = {}

-- Tick serveur (§12.3)
Balance.Tick = {
	Rate = 10, -- Hz
	Step = 0.1, -- s (pas fixe)
	MaxCatchUp = 3, -- pas rattrapés au plus par image
	GridCell = 16, -- taille de cellule de la grille spatiale des sauvages (studs)
}

-- File (§4.6, §12.4)
Balance.Conga = {
	Spacing = 2.6,
	HeadGap = 3.0,
	BaseCapacity = 3, -- 3 + niveau Conga
	AbsoluteMax = 60,
	BonusStep = 0.08, -- Conga Bonus = min(BonusMax, 1 + BonusStep × (n − 1))
	BonusMax = 5,
	ZenBonusMax = 2.5, -- plafond en Mode Zen (§4.16)
	SlowPerNebby = 0.004, -- au-delà des Guard Links
	SlowMax = 0.15,
	TrailLength = 170, -- historique serveur (studs)
	TrailMinStep = 0.5, -- miettes d'autorité
	NetMinStep = 1.0, -- miettes réseau (PathStream)
	TeleportDistance = 40, -- (miroir de la constante de Logic/Trail)
	DanceDelay = 1, -- s à l'arrêt avant la danse (client)
}

-- Vitesse (§4.6)
Balance.Speed = {
	Base = 16,
	PerStride = 0.5, -- 16 → 26
	CarrierMult = 0.85, -- porteur de la Comète
	SecondWindBoost = 4, -- victime d'une coupe
	SecondWindDuration = 3,
}

Balance.Dash = {
	Boost = 10,
	Duration = 1.0,
	CooldownBase = 7, -- max(CooldownMin, CooldownBase − CooldownPerSupernova × R)
	CooldownPerSupernova = 0.25,
	CooldownMin = 5,
}

-- Capture (§4.5, §4.17)
Balance.Catch = {
	LureBase = 5,
	LurePerLevel = 0.5, -- 5 → 11
	LatencyTolerance = 0.75, -- ajouté au rayon
	MaxDy = 6,
	FullWarnInterval = 5, -- « PLEINE » au plus toutes les 5 s
	MaxPerHour = 1500,
	SuspendSeconds = 300, -- captures suspendues au-delà
}

-- Coupe (§4.7)
Balance.Snip = {
	Radius = 2.8,
	TouchAssist = 0.3,
	MaxDy = 4,
	SnipperCooldown = 1.5,
	PairCooldown = 20,
	VictimImmunity = 8,
	MaxPerMinute = 2,
	MinuteWindow = 60,
	LossCapMin = 6, -- plafond = max(LossCapMin, floor(LossCapRatio × n))
	LossCapRatio = 0.35,
	HarborRadius = 25,
	ScatterMin = 4,
	ScatterMax = 9,
	ScatterTime = 0.55, -- arc de dispersion (client)
	ScatterHeight = 3,
	Dizzy = 1.2, -- 0 pour la victime
	LooseLifetime = 20, -- Nebbies libres
	RushLureMult = 1.5, -- Snip Rush
	RushDuration = 3,
	RushDustPerNebby = 5, -- plafonné par Balance.DailyCaps.snipDust
	WispRadius = 2.5, -- coupe par Gloomwisp
}

Balance.Guard = {
	Base = 3, -- Lead Trio
	PerLevel = 1,
	Max = 8,
}

-- Équipages (§6.1, §6.2)
Balance.Crew = {
	MaxSize = 4,
	EscortRadius = 7,
	BonusPerMate = 0.10,
	BonusMaxMates = 3,
	InviteTTL = 20,
	InviteCooldown = 3, -- 1 invitation / 3 s
	InvitesPerMinute = 5,
	LeaveCooldown = 5,
	CometMateDust = 25,
	DuoSeconds = 600, -- 10 min cumulées avec un ami
	DuoDust = 50,
	EscortTitleSeconds = 6000, -- 100 min (titre « Ange gardien »)
}

-- Parade (§4.8)
Balance.Parade = {
	GateWidth = 12, -- boîte 12 × 10 × 4 centrée sur la porte, orientée vers le centre
	GateHeight = 10,
	GateDepth = 4,
	BeaconMult = 1.5,
	MegaParade = 30, -- bannière serveur
	FireworksMin = 15, -- feux d'artifice (client)
}

-- Revenu passif et hors ligne (§4.9)
Balance.Idle = {
	SettleInterval = 30, -- règlement périodique par joueur (décalé)
	AnalyticsEvery = 300, -- un événement « Idle » par tranche de 5 min
}

Balance.Offline = {
	Rate = 0.5,
	Cap = 8 * 3600,
	NightShiftRate = 0.75,
	NightShiftCap = 12 * 3600,
	ReturnMinRatio = 0.01, -- écran de retour si gain ≥ 1 % du coût de la prochaine Supernova
	ReturnMinGlow = 1000, -- … ou ≥ 1 000 Glow
}

-- Multiplicateur global M (§4.10)
Balance.Multiplier = {
	PerSupernova = 0.40,
	VIP = 0.25,
	PerCrewMate = 0.10,
	MaxCrewMates = 3,
	DoubleGlow = 2,
	Boost = 2, -- boost personnel OU de serveur (non cumulables)
}

export type UpgradeDef = {
	Base: number,
	Growth: number,
	GrowthAfter: number?, -- Conga : croissance après le palier Break
	Break: number?,
	Max: number?, -- niveaux max fixes
	MaxBase: number?, -- Conga : 12 + 5 × R …
	MaxPerSupernova: number?,
	MaxAbsolute: number?, -- … plafonné à 57
	ResetOnSupernova: boolean,
}

-- Améliorations (§4.11) : coût(L) = floor(Base × Growth^L) (Conga : voir Break)
Balance.Upgrades = {
	conga = {
		Base = 50,
		Growth = 1.55,
		GrowthAfter = 1.20,
		Break = 12,
		MaxBase = 12,
		MaxPerSupernova = 5,
		MaxAbsolute = 57,
		ResetOnSupernova = true,
	},
	stride = { Base = 80, Growth = 1.42, Max = 20, ResetOnSupernova = true },
	lure = { Base = 70, Growth = 1.50, Max = 12, ResetOnSupernova = true },
	perches = { Base = 200, Growth = 1.75, Max = 27, ResetOnSupernova = false },
	guard = { Base = 5000, Growth = 4.0, Max = 5, ResetOnSupernova = false },
} :: { [string]: UpgradeDef }

Balance.UpgradeOrder = { "conga", "stride", "lure", "perches", "guard" }

-- Perchoirs (§4.9) : 3 + niveau + jalons d'Atlas (≤ 10) + 6 (pass) ≤ 46
Balance.Perches = {
	Base = 3,
	PerLevel = 1,
	AtlasMilestoneMax = 10,
	ExtraPerchesPass = 6,
	Max = 46,
}

-- Réserve (§4.9)
Balance.Stash = {
	Base = 300,
	Plus = 600, -- pass Stash Plus
	AutoReleaseMaxRarity = 3, -- libération automatique : Commun, Peu commun, Rare seulement
}

-- Supernova (§4.12) : Costs[R + 1] = coût de R → R + 1 ; au-delà : BeyondBase × BeyondGrowth^(R − 11)
Balance.Supernova = {
	-- Réglage §17 (simulation §4.18) : coûts de R3 → R4 et au-delà × 2 par rapport au GDD
	Costs = {
		400000,
		10000000,
		40000000,
		240000000,
		600000000,
		1400000000,
		3600000000,
		8000000000,
		16000000000,
		28000000000,
		44000000000,
		68000000000,
	},
	BeyondBase = 68000000000,
	BeyondGrowth = 1.5,
	BeyondFrom = 11,
	HoldSeconds = 1, -- confirmation maintenue (client)
	AuraEvery = 3, -- Argent R3, Or R6, Nova R9, Galaxie R12
}

-- Starforge (§4.13) : Costs[k] = coût de ★k → ★k+1
Balance.Starforge = {
	Copies = 3,
	MaxStars = 5,
	Costs = { 25, 120, 600, 3000 },
}

-- Grande Comète (§4.15.2)
Balance.Comet = {
	WarnSeconds = 8,
	SkySeconds = 6,
	BurstAfter = 75, -- s après l'impact
	ImpactRadiusMin = 10,
	ImpactRadiusMax = 40,
	PickupRadius = 4,
	StealRadius = 4.0,
	NewCarrierImmunity = 2,
	RetakeCooldown = 4,
	CarrierSpeedMult = 0.85,
	Content = {
		{ rarity = 5, weight = 80 },
		{ rarity = 6, weight = 18 },
		{ rarity = 7, weight = 2 },
	},
	BankIdleSeconds = 120, -- Glow = 120 s de revenu passif de l'encaisseur
	BurstCount = 5,
	BurstRarity = 4, -- Épiques
	BurstPerPlayer = 1,
	HoldMinSeconds = 3,
	HoldDust = 50,
	NearRadius = 20,
	NearDust = 15,
	NearIdleSeconds = 30,
	CrewDust = 25,
	TitleBanked = 10, -- titre « Chasseur de Comètes »
}

-- Nuit de la Balise (§4.15.3)
Balance.Beacon = {
	WarnSeconds = 15,
	Duration = 180,
	PerPlayer = 10, -- objectif = max(MinGoal, PerPlayer × actifs) × miséricorde
	MinGoal = 20,
	MercyAfter2 = 0.75,
	MercyAfter3 = 0.5,
	WinDust = 40,
	FailDust = 15,
	FrenzySeconds = 60,
	FrenzyIntervalDiv = 4,
	FrenzyCapMult = 2,
	GoldenNightSeconds = 300,
	RingInner = 8,
	RingOuter = 16,
	TitleWins = 20, -- titre « Gardien de la Balise »
}

-- Gloomwisps (§4.15.4) : nombre = max(0, Base − floor(actifs / PlayersPerStep))
Balance.Wisps = {
	Base = 5,
	PlayersPerStep = 3,
	PathRadius = 165,
	Speed = 7,
	Pause = 4,
	SnipRadius = 2.5,
	PopRadius = 4.5,
	PopDust = 10, -- plafonné par Balance.DailyCaps.wispDust
	PopIdleSeconds = 20,
	RespawnDelay = 10,
	PreviewStuds = 15, -- Beam pointillé (client)
}

-- Plafonds journaliers UTC (§4.1, §4.17) — propriétaire : EconomyService (clé de profil « caps »)
Balance.DailyCaps = {
	snipDust = 200,
	wispDust = 300,
	cheers = 10, -- acclamations récompensées
	-- cadeau Duo : 1 par jour (booléen caps.duo)
}

-- Protections (§4.16)
Balance.Rookie = {
	PlayMinutes = 30, -- bouclier si session == 1 ou (temps cumulé < 30 min et R == 0)
}

Balance.Zen = {
	Cooldown = 60,
}

-- Acclamations (§6.6)
Balance.Cheer = {
	Window = 10,
	Dust = 5,
}

-- Pings (§6.3)
Balance.Ping = {
	Count = 6,
	Cooldown = 1.5,
	Duration = 2.5,
	Range = 200,
}

-- Glow Party (§8.3, §4.17)
Balance.GlowParty = {
	Seconds = 600,
	QueueMax = 3600,
	HideAbove = 1200, -- bouton masqué si plus de 20 min restantes
}

-- Contrôle de déplacement (§12.7)
Balance.MoveCheck = {
	Margin = 1.5, -- déplacement XZ autorisé = vmax × dt × Margin + Slack
	Slack = 4,
	SpeedWindow = 0.5, -- vmax = WalkSpeed max des 0,5 dernières s
	MaxClimbSpeed = 12,
	FlagsToRewind = 3,
	FlagWindow = 5,
	RewindLockout = 3, -- s sans capture/coupe/parade après un retour
	Exemption = 3, -- après apparition ou PivotTo serveur
	MaxAltitude = 14, -- au-dessus du sol…
	AltitudeTime = 1.5, -- … pendant plus de 1,5 s
	MaxRadius = 182,
	MinY = -5,
	StrikesForBan = 10, -- retours forcés…
	StrikeWindow = 600, -- … en 10 min → exclusion des classements
}

-- Apparitions (§4.3)
Balance.Spawn = {
	GridStep = 6,
	MinSeparation = 6,
	PlaceAttempts = 10,
	WanderAmplitude = 1.6,
	WanderFreqMin = 0.35,
	WanderFreqMax = 0.60,
	ShrinkTime = 0.4, -- fin de vie (client)
	ActiveDistance = 4, -- joueur actif : ≥ 4 studs parcourus…
	ActiveWindow = 60, -- … dans les 60 dernières s
	CapScaleOffset = 4, -- capScale = clamp((actifs + 4) / 16, 0,5, 1)
	CapScaleDiv = 16,
	CapScaleMin = 0.5,
	CapScaleMax = 1.0,
	WeatherFormChance = 0.2, -- réglage §17 (GDD : 0,4) : rythme de l'Atlas
	WelcomeCount = 3,
	WelcomeDistance = 12, -- devant la porte
	DirectedCommons = 6, -- accueil : ≥ 6 Communs…
	DirectedRadius = 40, -- … à moins de 40 studs du Nid
	GuaranteedRareMin = 60, -- Rare personnel de Q4 à 60-90 studs du centre
	GuaranteedRareMax = 90,
	PersonalLifetime = 600,
	WildEventInterval = 0.25, -- 4 Hz
}

-- Réseau des files (§12.4)
Balance.Net = {
	PathRepeat = 2, -- points répétés du message précédent
	StillResendTicks = 5, -- renvoi des 2 derniers points après l'arrêt
	PathStreamMaxPoints = 255,
	SnapshotPoints = 200,
	VersionBufferSeconds = 1, -- client : attente d'une op manquante avant RequestWorld
}

-- Rendu client (§5.2, §9.3, §12.8)
Balance.Render = {
	FullDistance = 50,
	BallDistance = 120,
	LowGraphicsDistanceMult = 0.6,
	MaxFullDetail = 100,
	MaxNebbyParts = 1500,
	FarUpdateHz = 20,
	MaxHighlights = 12,
	HighlightLines = 4,
	HighlightMythics = 6,
	MaxLights = 40,
	LegendaryLights = 6,
	LowGraphicsLightDistance = 60,
	MaxParticles = 300,
	LowGraphicsParticleMult = 0.3,
	CrownLine = 20, -- couronne + Highlight sur la tête de file
	SparkleLine = 40, -- paillettes au sol
	CutWarnDistance = 20, -- anneaux rose/doré sur la file d'un autre joueur proche
	TailWarnDistance = 15, -- contour pointillé de sa propre queue
	PerchFloaters = 8, -- « +N » des 8 meilleurs perchés (Nid local)
	FloatTextPool = 20,
}

-- Classements (§6.7)
Balance.Leaderboard = {
	LiveInterval = 1,
	FlushInterval = 60,
	ReadInterval = 120,
	TopLive = 5,
	TopWeekly = 10,
	CrownTop = 10, -- titre « Roi / Reine de la Conga »
}

return Balance
