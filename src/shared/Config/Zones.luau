--!strict
-- Géographie de Lumora (GDD §4.3, §11). Contrat : docs/04-architecture.md §9.
-- Tout ce qui est position, rayon, nombre de pièces du monde vit ici : WorldService (construction),
-- Logic/WorldLayout (calculs purs) et SpawnService lisent ces valeurs, jamais des nombres en dur.

local Zones = {}

-- Île (§11.1) : disque centré en (0, 0, 0), dessus à Y = 0
Zones.Island = {
	Radius = 180,
	WallRadius = 181,
	Thickness = 20,
	TopY = 0,
	Color = Color3.fromRGB(82, 170, 160),
	Material = Enum.Material.Grass,
	CliffInner = 176,
	CliffOuter = 182,
	CliffBottomY = -30,
	CliffCount = 48,
	CliffColor = Color3.fromRGB(90, 95, 120),
	WallCount = 36,
	WallSize = Vector3.new(2, 40, 32),
	CloudSeaY = -60,
	CloudCount = 40,
	CloudRadiusMin = 200,
	CloudRadiusMax = 420,
}

export type Odds = { rarity: number, weight: number }

export type ZoneDef = {
	key: string, -- "zone.<key>"
	inner: number, -- rayon XZ intérieur (inclus)
	outer: number, -- rayon XZ extérieur (exclu)
	odds: { Odds }, -- probabilités en % (somme 100)
	cap: number, -- plafond vivant à 12 joueurs
	interval: number, -- s entre deux tentatives d'apparition
	lifetime: number, -- s
	groundY: number, -- hauteur du sol de la zone
}

-- Zones (§4.3), de l'extérieur vers le centre
Zones.List = {
	{
		key = "meadow",
		inner = 110,
		outer = 170,
		odds = {
			{ rarity = 1, weight = 78 },
			{ rarity = 2, weight = 19 },
			{ rarity = 3, weight = 3 },
		},
		cap = 40,
		interval = 0.4,
		lifetime = 90,
		groundY = 0,
	},
	{
		key = "glade",
		inner = 55,
		outer = 110,
		odds = {
			{ rarity = 1, weight = 35 },
			{ rarity = 2, weight = 40 },
			{ rarity = 3, weight = 20 },
			{ rarity = 4, weight = 5 },
		},
		cap = 24,
		interval = 0.8,
		lifetime = 75,
		groundY = 0.1,
	},
	{
		key = "crater",
		inner = 16,
		outer = 55,
		odds = {
			{ rarity = 2, weight = 25 },
			{ rarity = 3, weight = 45 },
			{ rarity = 4, weight = 23 },
			{ rarity = 5, weight = 6.5 },
			{ rarity = 6, weight = 0.5 },
		},
		cap = 10,
		interval = 2.5,
		lifetime = 60,
		groundY = 0.3,
	},
} :: { ZoneDef }

Zones.byKey = {} :: { [string]: ZoneDef }
for _, def in Zones.List do
	Zones.byKey[def.key] = def
end

-- Sols (§11.1)
Zones.Ground = {
	GladeDiameter = 220,
	GladeColor = Color3.fromRGB(140, 150, 205),
	GladeTopY = 0.1,
	CraterDiameter = 110,
	CraterColor = Color3.fromRGB(60, 58, 80),
	CraterTopY = 0.3,
	RimInner = 52,
	RimOuter = 58,
	RimHeight = 2.5,
	RimSegments = 12,
	RimGap = 8, -- ouvertures alignées sur les chemins
	CrackCount = 18,
	CrackColor = Color3.fromRGB(90, 230, 255),
	CrackLengthMin = 6,
	CrackLengthMax = 12,
	CraterRocks = 6,
}

-- Balise (§11.2)
Zones.Beacon = {
	Radius = 16, -- zone d'exclusion des apparitions (r < 16)
	CollisionRadius = 8,
	RingInner = 8, -- anneau de dépôt pendant la Nuit de la Balise
	RingOuter = 16,
	Color = Color3.fromRGB(235, 230, 250),
	RingColor = Color3.fromRGB(90, 230, 255),
	StarColor = Color3.fromRGB(255, 220, 120),
	StarY = 26,
	BeamTopY = 300,
	BeamWidth = 2,
	BeamWidthNight = 6,
	DepositDiameter = 28,
	BoardRadius = 12, -- stèle du tableau, face au sud
	Tiers = {
		{ diameter = 14, height = 3 },
		{ diameter = 10, height = 8 },
		{ diameter = 6, height = 10 },
	},
}

-- Nids (§11.3) : Nid k (slot = k + 1) centré en (Ring cos(AngleStep k), 0, Ring sin(AngleStep k))
Zones.Nests = {
	Count = 12,
	Ring = 150,
	AngleStep = 30, -- degrés
	PlatformDiameter = 34,
	PlatformThickness = 0.4,
	PlatformTopY = 0.2,
	GateDistance = 19, -- porte à 19 studs du centre du Nid, côté centre de l'île (r = 131)
	GatePostOffset = 6,
	GatePostDiameter = 1.6,
	GatePostHeight = 10,
	ArchPieces = 7,
	ArchBottomY = 10,
	ArchTopY = 13,
	HarborRadius = 25, -- port sûr (Balance.Snip.HarborRadius)
	SpawnExclusion = 30, -- port sûr élargi exclu des apparitions
	NestExclusion = 20, -- plateforme du Nid exclue des apparitions
	ObservatoryRadius = 172,
	ObservatoryDiameter = 6,
	ObservatoryHeight = 14,
	BillboardY = 16,
	BillboardMaxDistance = 120,
	ConstellationY = 45,
}

-- Perchoirs (§11.3) : arcs de 300° ouverts côté porte, dans cet ordre (meilleur revenu d'abord)
Zones.Perches = {
	ArcDegrees = 300,
	Diameter = 2.2,
	Height = 1.2,
	Rings = {
		{ radius = 13, count = 15, y = 0 },
		{ radius = 9.5, count = 11, y = 0 },
		{ radius = 6, count = 7, y = 0 },
		{ radius = 11, count = 13, y = 7 }, -- disques Néon flottants
	},
}

-- Chemins et lanternes (§11.1)
Zones.Paths = {
	Count = 12,
	From = 131,
	To = 58,
	StoneEvery = 6,
	StoneDiameter = 4,
	StoneThickness = 0.2,
	StoneColor = Color3.fromRGB(200, 195, 215),
	LanternRadii = { 120, 90, 60 },
	LitRadii = { 90, 60 }, -- PointLight seulement à r 90 et r 60 (budget §12.8)
	LanternPoleHeight = 6,
	LanternColor = Color3.fromRGB(255, 210, 140),
	LightRange = 12,
	LightBrightness = 1.2,
}

-- Décor par zone (§11.4) — positions tirées par seed fixe, hors grille d'apparition
Zones.Decor = {
	Seed = 20261030,
	Meadow = { Puffblooms = 60, Mushcaps = 30, Fences = 24 },
	Glade = { CrystalClusters = 16, LitCrystals = 6, FloatingStones = 8, CrystalMaxParts = 80 },
	CrystalColor = Color3.fromRGB(120, 230, 255),
	CrystalTransparency = 0.25,
	ObstacleRadius = 3, -- rayon d'exclusion autour de chaque décor (grille d'apparition)
}

-- Îlots flottants (§11.1)
Zones.Islets = {
	Count = 6,
	RadiusMin = 230,
	RadiusMax = 260,
	YMin = 10,
	YMax = 30,
	FloatAmplitude = 2,
	FloatPeriod = 6,
}

-- Budget de construction (§11.7)
Zones.PartBudget = 3000

return Zones
