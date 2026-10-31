--!strict
-- Cosmétiques (GDD §5.3, §4.12) et palette des Nids. Contrat : docs/04-architecture.md §9.
-- Propriétaire serveur : NestService (clés de profil « cosmetics » et « unlocks »).
--
-- Source d'un cosmétique (Source.kind) :
--   free                       toujours possédé
--   atlas    { entries }       jalon d'Atlas (AtlasService débloque via NestService.unlock)
--   pass     { pass }          pass possédé (vérifié dynamiquement, jamais stocké)
--   product  { product }       produit acheté (débloqué par ProductService)
--   supernova{ supernovas }    R atteint (automatique, jamais stocké)
--   stat     { stat, n }       statistique du profil ≥ n (QuestService débloque)
--   weeklyTop{ n }             top n hebdomadaire de la semaine précédente (temporaire, LeaderboardService)

local Cosmetics = {}

export type Source = {
	kind: string,
	entries: number?,
	pass: string?,
	product: string?,
	supernovas: number?,
	stat: string?,
	n: number?,
}

export type StyleDef = {
	order: number,
	source: Source,
	ringColor: Color3?, -- nil = couleur du Nid
	trailColors: { Color3 }?, -- nil = couleur du Nid
	animated: string?, -- "hsv" | "ripple" | "flicker" | "bubbles" | "twinkle" | "wave"
}

-- Styles de file : anneau Néon sous chaque Nebby + Trail sur le dernier
Cosmetics.Styles = {
	default = { order = 1, source = { kind = "free" } },
	constellation = {
		order = 2,
		source = { kind = "atlas", entries = 132 },
		ringColor = Color3.fromRGB(200, 220, 255),
		trailColors = { Color3.fromRGB(150, 180, 255), Color3.fromRGB(255, 255, 255) },
		animated = "twinkle",
	},
	royal_star = {
		order = 3,
		source = { kind = "pass", pass = "VIPStar" },
		ringColor = Color3.fromRGB(255, 205, 60),
		trailColors = { Color3.fromRGB(255, 220, 100), Color3.fromRGB(255, 250, 220) },
	},
	comet_tail = {
		order = 4,
		source = { kind = "product", product = "StarterKit" },
		ringColor = Color3.fromRGB(255, 180, 90),
		trailColors = { Color3.fromRGB(255, 230, 180), Color3.fromRGB(255, 120, 60) },
		animated = "flicker",
	},
	rainbow_ripple = { order = 5, source = { kind = "pass", pass = "CongaStyles" }, animated = "hsv" },
	ember = {
		order = 6,
		source = { kind = "pass", pass = "CongaStyles" },
		ringColor = Color3.fromRGB(255, 110, 50),
		trailColors = { Color3.fromRGB(255, 200, 80), Color3.fromRGB(200, 40, 20) },
		animated = "flicker",
	},
	bubbles = {
		order = 7,
		source = { kind = "pass", pass = "CongaStyles" },
		ringColor = Color3.fromRGB(150, 220, 255),
		animated = "bubbles",
	},
	starlight = {
		order = 8,
		source = { kind = "pass", pass = "CongaStyles" },
		ringColor = Color3.fromRGB(255, 250, 200),
		animated = "twinkle",
	},
	frost = {
		order = 9,
		source = { kind = "pass", pass = "CongaStyles" },
		ringColor = Color3.fromRGB(200, 240, 255),
		trailColors = { Color3.fromRGB(230, 250, 255), Color3.fromRGB(140, 200, 255) },
	},
	neon_wave = {
		order = 10,
		source = { kind = "pass", pass = "CongaStyles" },
		ringColor = Color3.fromRGB(120, 255, 200),
		animated = "wave",
	},
} :: { [string]: StyleDef }

export type AuraDef = { supernovas: number, color: Color3, order: number }

-- Auras de file (lueur des anneaux + couronne de tête) : automatiques selon R
Cosmetics.Auras = {
	silver = { supernovas = 3, color = Color3.fromRGB(220, 225, 235), order = 1 },
	gold = { supernovas = 6, color = Color3.fromRGB(255, 205, 60), order = 2 },
	nova = { supernovas = 9, color = Color3.fromRGB(255, 140, 220), order = 3 },
	galaxy = { supernovas = 12, color = Color3.fromRGB(150, 110, 255), order = 4 },
} :: { [string]: AuraDef }

export type TitleDef = { order: number, source: Source }

-- Titres (sous le nom)
Cosmetics.Titles = {
	cartographer = { order = 1, source = { kind = "atlas", entries = 132 } },
	comet_hunter = { order = 2, source = { kind = "stat", stat = "cometsBanked", n = 10 } },
	beacon_keeper = { order = 3, source = { kind = "stat", stat = "beaconWins", n = 20 } },
	conga_royal = { order = 4, source = { kind = "weeklyTop", n = 10 } },
	guardian_angel = { order = 5, source = { kind = "stat", stat = "escortSeconds", n = 6000 } },
} :: { [string]: TitleDef }

export type ThemeDef = { order: number, source: Source, platform: Color3?, arch: Color3? }

-- Thèmes de Nid (plateforme + arche) ; nil = couleur du propriétaire
Cosmetics.Themes = {
	default = { order = 1, source = { kind = "free" } },
	atlas = {
		order = 2,
		source = { kind = "atlas", entries = 144 },
		platform = Color3.fromRGB(70, 80, 140),
		arch = Color3.fromRGB(150, 200, 255),
	},
	royal_gold = {
		order = 3,
		source = { kind = "pass", pass = "VIPStar" },
		platform = Color3.fromRGB(230, 200, 120),
		arch = Color3.fromRGB(255, 215, 80),
	},
} :: { [string]: ThemeDef }

-- Palette des 12 Nids (§5.3) : couleur du propriétaire = NestColors[slot]
Cosmetics.NestColors = {
	Color3.fromRGB(255, 120, 110), -- 1 Corail
	Color3.fromRGB(255, 165, 80), -- 2 Mandarine
	Color3.fromRGB(250, 220, 90), -- 3 Citron
	Color3.fromRGB(160, 220, 90), -- 4 Citron vert
	Color3.fromRGB(90, 220, 170), -- 5 Menthe
	Color3.fromRGB(60, 200, 210), -- 6 Sarcelle
	Color3.fromRGB(90, 170, 255), -- 7 Ciel
	Color3.fromRGB(120, 120, 240), -- 8 Indigo
	Color3.fromRGB(170, 110, 240), -- 9 Violet
	Color3.fromRGB(220, 110, 220), -- 10 Orchidée
	Color3.fromRGB(255, 110, 170), -- 11 Rose
	Color3.fromRGB(220, 190, 150), -- 12 Sable
} :: { Color3 }

Cosmetics.FreeNestColor = Color3.fromRGB(120, 120, 130)

-- Équipiers : lien entre Nids la nuit (cyan → or) et étoile au-dessus de la tête
Cosmetics.CrewBeam = { Color3.fromRGB(90, 230, 255), Color3.fromRGB(255, 210, 90) }
Cosmetics.CrewStar = Color3.fromRGB(110, 170, 255)

-- Couleurs de lisibilité des files (§6.4, §4.16)
Cosmetics.Readability = {
	Snippable = Color3.fromRGB(255, 120, 190), -- anneau rose
	Guard = Color3.fromRGB(255, 205, 60), -- anneau doré (Guard Links)
	Escort = Color3.fromRGB(110, 170, 255), -- bulles bleues
	Immune = Color3.fromRGB(255, 150, 210), -- étincelles roses (immunité)
	Rookie = Color3.fromRGB(255, 215, 90), -- bulle dorée
	Zen = Color3.fromRGB(80, 230, 210), -- halo turquoise
}

return Cosmetics
