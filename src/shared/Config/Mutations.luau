--!strict
-- Mutations (GDD §4.5). Contrat (architecte) : données figées. Une mutation au plus par squishy ;
-- 0 = aucune. L'identifiant est DÉFINITIF (sauvegardé, champ `m` des squishies, bits du Squishydex).
-- Tirage (Logic/Odds) : un seul nombre dans [0 ; 1[, comparé aux chances cumulées en partant de la
-- plus rare (ordre DrawOrder) ; au-delà du total : aucune mutation.
--   chance   chance par naissance dans la Cuve à buses 0 (fraction : 0,04 = 4 %)
--   moonOnly seulement pendant la Jelly Moon (Lunaire : chance MoonChance, non multipliée par les buses)
--   look     données de rendu (Render/SquishyBuilder) ; jamais lues par le serveur
--   rareHatch  fêtée comme une naissance Légendaire, quelle que soit l'espèce (GDD §4.5, §9.4)
--   autoLock   verrou automatique à la naissance (GDD §4.13 : multiplicateur ≥ 8, Galaxie ou mieux)
--   sellConfirm vente / relâche en 2 étapes (GDD §4.13 : multiplicateur ≥ 5, Doré ou mieux)

export type MutationLook = {
	material: string?, -- Enum.Material du corps ("Glass", "Ice", "Foil", "SmoothPlastic"…)
	transparency: number?,
	color: Color3?, -- couleur imposée au corps (sinon celle de l'espèce)
	neonFeatures: boolean?, -- yeux, oreilles et motif en Neon
	core: boolean?, -- petit noyau visible dans le corps (Gelée)
	particles: string?, -- "snow" | "sparkles" | "stars" | "petals" | "drops"
	particleRate: number?, -- par seconde
	dots: number?, -- points Neon sur le corps (Galaxie)
	shell: string?, -- coque ("ForceField")
	hueCycle: number?, -- s pour un tour du cercle des couleurs (Arc-en-ciel)
	steps: number?, -- changements de couleur par seconde (Glitch ; jamais plus de 3)
	orbiters: number?, -- petits objets en orbite (Glitch : cubes ; Lunaire : gouttes)
	crescent: boolean?, -- croissant de lune sur le front (Lunaire)
	thirdEye: boolean?, -- petit troisième œil mignon (Lunaire)
	deflate: { y: number, xz: number }?, -- Flop : hauteur × 0,6, largeur × 1,25
	halfEyes: boolean?,
	goldStars: number?, -- étoiles dorées qui tournent au-dessus (Flop)
	badge: string?, -- badge doré sur l'étiquette (Flop : "×100")
	blorp: { min: number, max: number }?, -- s entre deux « blorp » (Flop)
	reducedMotion: string?, -- rendu fixe en Mouvement réduit : "checker" | "gradient"
}

export type MutationDef = {
	id: number,
	key: string,
	mult: number,
	chance: number,
	moonOnly: boolean,
	rareHatch: boolean,
	autoLock: boolean,
	sellConfirm: boolean,
	color: Color3, -- couleur de l'étiquette et des particules de révélation
	look: MutationLook,
}

local List: { MutationDef } = {
	{
		id = 1,
		key = "jelly",
		mult = 1.5,
		chance = 0.04,
		moonOnly = false,
		rareHatch = false,
		autoLock = false,
		sellConfirm = false,
		color = Color3.fromRGB(150, 230, 255),
		look = { material = "Glass", transparency = 0.2, core = true },
	},
	{
		id = 2,
		key = "neon",
		mult = 2,
		chance = 0.02,
		moonOnly = false,
		rareHatch = false,
		autoLock = false,
		sellConfirm = false,
		color = Color3.fromRGB(120, 255, 200),
		look = { neonFeatures = true },
	},
	{
		id = 3,
		key = "frosted",
		mult = 3,
		chance = 0.01,
		moonOnly = false,
		rareHatch = false,
		autoLock = false,
		sellConfirm = false,
		color = Color3.fromRGB(200, 235, 255),
		look = { material = "Ice", particles = "snow", particleRate = 2 },
	},
	{
		id = 4,
		key = "golden",
		mult = 5,
		chance = 0.004,
		moonOnly = false,
		rareHatch = false,
		autoLock = false,
		sellConfirm = true,
		color = Color3.fromRGB(255, 205, 60),
		look = { material = "Foil", color = Color3.fromRGB(255, 205, 60), particles = "sparkles" },
	},
	{
		id = 5,
		key = "galaxy",
		mult = 8,
		chance = 0.0015,
		moonOnly = false,
		rareHatch = false,
		autoLock = true,
		sellConfirm = true,
		color = Color3.fromRGB(110, 90, 220),
		look = { color = Color3.fromRGB(25, 20, 60), dots = 6, shell = "ForceField" },
	},
	{
		id = 6,
		key = "rainbow",
		mult = 12,
		chance = 0.0005,
		moonOnly = false,
		rareHatch = true,
		autoLock = true,
		sellConfirm = true,
		color = Color3.fromRGB(255, 140, 200),
		look = { hueCycle = 6, reducedMotion = "gradient" },
	},
	{
		id = 7,
		key = "lunar",
		mult = 20,
		chance = 0,
		moonOnly = true,
		rareHatch = false,
		autoLock = true,
		sellConfirm = true,
		color = Color3.fromRGB(210, 220, 255),
		look = {
			color = Color3.fromRGB(210, 220, 255),
			crescent = true,
			thirdEye = true,
			orbiters = 2,
			particles = "drops",
		},
	},
	{
		id = 8,
		key = "glitch",
		mult = 40,
		chance = 0.00004,
		moonOnly = false,
		rareHatch = true,
		autoLock = true,
		sellConfirm = true,
		color = Color3.fromRGB(120, 255, 120),
		look = { steps = 2, orbiters = 4, reducedMotion = "checker" },
	},
	{
		id = 9,
		key = "flop",
		mult = 100,
		chance = 0.000005,
		moonOnly = false,
		rareHatch = true,
		autoLock = true,
		sellConfirm = true,
		color = Color3.fromRGB(255, 215, 90),
		look = {
			deflate = { y = 0.6, xz = 1.25 },
			halfEyes = true,
			goldStars = 3,
			badge = "×100",
			blorp = { min = 6, max = 10 },
			particles = "stars",
		},
	},
}

local ById: { [number]: MutationDef } = {}
local ByKey: { [string]: MutationDef } = {}
for _, def in List do
	ById[def.id] = def
	ByKey[def.key] = def
end

-- Ordre du tirage : de la plus rare à la plus commune (Lunaire à part, voir MoonChance)
local DrawOrder = { 9, 8, 6, 5, 4, 3, 2, 1 }

local Mutations = {
	List = List,
	ById = ById,
	ByKey = ByKey,
	DrawOrder = DrawOrder,
	NONE = 0,
	LUNAR = 7,
	GOLDEN = 4,
	Count = #List,
	-- Buses à mutation (pièce de la Cuve, niveau = min(NozzleMax, R)) : chances × (1 + NozzleStep × niveau),
	-- sauf Lunaire
	NozzleStep = 0.5,
	NozzleMax = 5,
	-- Jelly Moon : toutes les chances × MoonMult, plus Lunaire à MoonChance
	MoonMult = 2,
	MoonChance = 0.03,
	-- Page dorée du Squishydex : les 8 mutations hors Lunaire trouvées (GDD §4.17)
	GoldenPageExcludes = { [7] = true },
}

return Mutations
