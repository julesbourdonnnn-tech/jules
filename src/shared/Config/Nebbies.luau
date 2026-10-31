--!strict
-- Nebbies : raretés (GDD §4.2), formes et variantes (§4.4), étoiles de fusion (§4.13),
-- et les 36 espèces (§5.1). Contrat : docs/04-architecture.md §9.
--
-- RÈGLES
--  * L'identifiant numérique d'une espèce est DÉFINITIF (sauvegardé) : on ne réordonne jamais
--    la table, on ajoute à la fin.
--  * Un Nebby sur le réseau ou dans une file est un « code » de 12 bits :
--      code = s | (f << 6) | (v << 9)     s = espèce 1-36, f = forme 0-5, v = bits de variantes
--    (Nebbies.pack / Nebbies.unpack). Les étoiles n'existent qu'en collection (★1 en file).
--  * Bits de l'Atlas : index = (s − 1) × 6 + f (Nebbies.atlasIndex), 7 mots de 32 bits.

local Nebbies = {}

-- Versions de contenu activées. Passer « v1.1 » à true active Eclipse et les 6 espèces réservées.
Nebbies.ENABLED_VERSIONS = {
	mvp = true,
	["v1.1"] = false,
} :: { [string]: boolean }

export type RarityDef = {
	id: number,
	key: string, -- clé de localisation : "rarity.<key>"
	passive: number, -- Glow/s (§4.2)
	parade: number, -- valeur de parade = 20 × passif
	dust: number?, -- Stardust à la libération (nil = non libérable)
	size: number, -- taille du corps T (studs)
	color: Color3, -- couleur du corps
	aura: string, -- "none" | "antenna" | "sparkles" | "orbit" | "lightTrail" | "highlightCrown" | "forceFieldHsv"
	hsvCycle: boolean?, -- teinte qui cycle (client)
	neonFar: boolean?, -- LOD « boule » en Néon (Mythique+)
	banner: boolean?, -- capture annoncée à tout le serveur (Légendaire+)
	pillar: boolean?, -- colonne Néon à la capture (Rare+)
}

Nebbies.Rarities = {
	[1] = {
		id = 1,
		key = "common",
		passive = 1,
		parade = 20,
		dust = 1,
		size = 1.6,
		color = Color3.fromRGB(255, 236, 200),
		aura = "none",
	},
	[2] = {
		id = 2,
		key = "uncommon",
		passive = 4,
		parade = 80,
		dust = 4,
		size = 1.8,
		color = Color3.fromRGB(140, 235, 190),
		aura = "antenna",
	},
	[3] = {
		id = 3,
		key = "rare",
		passive = 15,
		parade = 300,
		dust = 15,
		size = 2.0,
		color = Color3.fromRGB(110, 190, 255),
		aura = "sparkles",
		pillar = true,
	},
	[4] = {
		id = 4,
		key = "epic",
		passive = 60,
		parade = 1200,
		dust = 60,
		size = 2.3,
		color = Color3.fromRGB(180, 120, 255),
		aura = "orbit",
		pillar = true,
	},
	[5] = {
		id = 5,
		key = "legendary",
		passive = 300,
		parade = 6000,
		dust = 300,
		size = 2.6,
		color = Color3.fromRGB(255, 200, 70),
		aura = "lightTrail",
		pillar = true,
		banner = true,
	},
	[6] = {
		id = 6,
		key = "mythic",
		passive = 1500,
		parade = 30000,
		dust = 1500,
		size = 2.8,
		color = Color3.fromRGB(255, 120, 190),
		aura = "highlightCrown",
		pillar = true,
		banner = true,
		neonFar = true,
	},
	[7] = {
		id = 7,
		key = "cosmic",
		passive = 10000,
		parade = 200000,
		dust = nil,
		size = 3.0,
		color = Color3.fromRGB(255, 255, 255),
		aura = "forceFieldHsv",
		hsvCycle = true,
		pillar = true,
		banner = true,
		neonFar = true,
	},
} :: { [number]: RarityDef }

Nebbies.RARITY_COUNT = 7

export type FormDef = {
	id: number, -- 0-5 (sauvegardé)
	key: string, -- "form.<key>"
	mult: number,
	version: string,
	material: Enum.Material,
	bodyColor: Color3?, -- remplace la couleur de rareté (Blazing, Eclipse)
	bodyTint: Color3?, -- teinte mélangée à la couleur de rareté
	tintAlpha: number?, -- 0-1
	accentNeon: boolean?, -- accents en Néon
	accentColors: { Color3 }?, -- remplace la couleur d'accent (alternance)
	eyeColor: Color3?, -- yeux (Eclipse : Néon violet)
	eyeNeon: boolean?,
	fire: number?, -- taille de l'instance Fire (Blazing)
	hsvCycle: boolean?, -- teinte qui cycle (Prismatic)
}

-- Indexées de 0 à 5 : f = 0 Normale … 5 Prismatic (§4.4, ordre de l'Atlas)
Nebbies.Forms = {
	[0] = {
		id = 0,
		key = "normal",
		mult = 1,
		version = "mvp",
		material = Enum.Material.SmoothPlastic,
	},
	[1] = {
		id = 1,
		key = "aurora",
		mult = 2,
		version = "mvp",
		material = Enum.Material.SmoothPlastic,
		bodyTint = Color3.fromRGB(170, 200, 255),
		tintAlpha = 0.25,
		accentNeon = true,
		accentColors = { Color3.fromRGB(120, 255, 190), Color3.fromRGB(190, 120, 255) },
	},
	[2] = {
		id = 2,
		key = "frozen",
		mult = 2.5,
		version = "mvp",
		material = Enum.Material.Ice,
		bodyTint = Color3.fromRGB(205, 235, 255),
		tintAlpha = 0.35,
	},
	[3] = {
		id = 3,
		key = "blazing",
		mult = 3,
		version = "mvp",
		material = Enum.Material.SmoothPlastic,
		bodyColor = Color3.fromRGB(255, 110, 60),
		fire = 2,
	},
	[4] = {
		id = 4,
		key = "eclipse",
		mult = 4,
		version = "v1.1",
		material = Enum.Material.SmoothPlastic,
		bodyColor = Color3.fromRGB(20, 16, 30),
		eyeColor = Color3.fromRGB(190, 120, 255),
		eyeNeon = true,
	},
	[5] = {
		id = 5,
		key = "prismatic",
		mult = 6,
		version = "mvp",
		material = Enum.Material.Glass,
		hsvCycle = true,
	},
} :: { [number]: FormDef }

Nebbies.FORM_COUNT = 6 -- formes 0 à 5 (bits d'Atlas réservés pour les 6)

export type VariantDef = {
	bit: number,
	key: string, -- "variant.<key>"
	mult: number,
	chance: number?, -- probabilité sur toute apparition (nil = événementiel)
	color: Color3?,
	material: Enum.Material?,
	scale: number?,
}

Nebbies.Variants = {
	golden = {
		bit = 1,
		key = "golden",
		mult = 4,
		chance = 0.01,
		color = Color3.fromRGB(255, 205, 60),
		material = Enum.Material.Foil,
	},
	huge = {
		bit = 2,
		key = "huge",
		mult = 3,
		chance = 0.005,
		scale = 2,
	},
	starborn = {
		bit = 4,
		key = "starborn",
		mult = 2,
		chance = nil, -- uniquement pendant Starfall Saturday (Events.Starfall)
		color = Color3.fromRGB(255, 240, 160),
	},
} :: { [string]: VariantDef }

Nebbies.VARIANT_ORDER = { "golden", "huge", "starborn" }

-- Multiplicateur de revenu par nombre d'étoiles (§4.13)
Nebbies.Stars = { 1, 3.5, 12, 43, 150 } :: { number }
Nebbies.MAX_STARS = 5

export type SpeciesDef = {
	id: number,
	key: string,
	name: string, -- nom propre (identique en EN et FR)
	rarity: number,
	archetypes: { string }, -- "Puff" | "Sprout" | "Horn" | "Wing" | "Ring" | "Twin" | "Spike" | "Moon" | "Crown" | "Comet"
	accent: Color3,
	hsvAccent: boolean?, -- accent qui cycle en HSV (Grand Nebula)
	version: string, -- "mvp" | "v1.1"
	note: string?,
}

local function species(
	id: number,
	key: string,
	name: string,
	rarity: number,
	archetypes: { string },
	r: number,
	g: number,
	b: number,
	version: string,
	note: string?
): SpeciesDef
	return {
		id = id,
		key = key,
		name = name,
		rarity = rarity,
		archetypes = archetypes,
		accent = Color3.fromRGB(r, g, b),
		version = version,
		note = note,
	}
end

-- §5.1 : ne JAMAIS réordonner.
Nebbies.Species = {
	species(1, "puffkin", "Puffkin", 1, { "Puff" }, 255, 255, 255, "mvp", "welcome"),
	species(2, "pebblit", "Pebblit", 1, { "Moon" }, 170, 160, 150, "mvp"),
	species(3, "dewdrop", "Dewdrop", 1, { "Twin" }, 150, 220, 255, "mvp"),
	species(4, "mossmop", "Mossmop", 1, { "Sprout" }, 120, 190, 90, "mvp"),
	species(5, "sprigglet", "Sprigglet", 1, { "Sprout" }, 190, 230, 110, "mvp"),
	species(6, "bumblume", "Bumblume", 1, { "Wing" }, 255, 215, 90, "mvp"),
	species(7, "nibbit", "Nibbit", 1, { "Horn" }, 255, 170, 140, "mvp"),
	species(8, "fluffle", "Fluffle", 1, { "Puff" }, 215, 190, 245, "v1.1"),
	species(9, "bluebell_puff", "Bluebell Puff", 2, { "Puff" }, 90, 140, 255, "mvp"),
	species(10, "ringlet", "Ringlet", 2, { "Ring" }, 255, 240, 150, "mvp"),
	species(11, "twinkleaf", "Twinkleaf", 2, { "Sprout" }, 120, 255, 200, "mvp"),
	species(12, "glimbug", "Glimbug", 2, { "Wing" }, 255, 160, 220, "mvp"),
	species(13, "mintwhisk", "Mintwhisk", 2, { "Spike" }, 90, 210, 170, "mvp"),
	species(14, "pebblepop", "Pebblepop", 2, { "Moon" }, 200, 170, 255, "mvp"),
	species(15, "cloudlet", "Cloudlet", 2, { "Twin" }, 240, 245, 255, "v1.1"),
	species(16, "cometcub", "Cometcub", 3, { "Comet" }, 255, 180, 90, "mvp", "starterKit"),
	species(17, "prismpaw", "Prismpaw", 3, { "Horn" }, 180, 255, 255, "mvp"),
	species(18, "frostfinch", "Frostfinch", 3, { "Wing" }, 200, 240, 255, "mvp", "starterKit"),
	species(19, "lanternling", "Lanternling", 3, { "Ring" }, 255, 210, 120, "mvp"),
	species(
		20,
		"daybreak_puff",
		"Daybreak Puff",
		3,
		{ "Puff" },
		255,
		190,
		150,
		"mvp",
		"calendarDay5,starterKit"
	),
	species(21, "mooncap", "Mooncap", 3, { "Moon" }, 230, 230, 255, "mvp"),
	species(22, "spinnaroo", "Spinnaroo", 3, { "Spike" }, 255, 130, 130, "v1.1"),
	species(23, "glimmerwhale", "Glimmerwhale", 4, { "Twin" }, 120, 200, 255, "mvp"),
	species(24, "starhorn", "Starhorn", 4, { "Horn" }, 255, 235, 120, "mvp"),
	species(25, "aurorabbit", "Aurorabbit", 4, { "Crown" }, 170, 255, 200, "mvp"),
	species(26, "nebulynx", "Nebulynx", 4, { "Spike" }, 210, 140, 255, "mvp"),
	species(27, "orbitoad", "Orbitoad", 4, { "Ring" }, 140, 255, 170, "mvp"),
	species(28, "galaxifox", "Galaxifox", 4, { "Spike" }, 255, 150, 210, "v1.1"),
	species(29, "nova_nimbus", "Nova Nimbus", 5, { "Puff", "Ring" }, 255, 255, 220, "mvp"),
	species(30, "eclipse_owlet", "Eclipse Owlet", 5, { "Wing", "Moon" }, 120, 100, 200, "mvp"),
	species(31, "sunwyrm", "Sunwyrm", 5, { "Spike", "Crown" }, 255, 150, 60, "mvp"),
	species(32, "celestikoi", "Celestikoi", 5, { "Comet" }, 255, 120, 120, "v1.1"),
	species(33, "prismara", "Prismara", 6, { "Crown" }, 255, 200, 255, "mvp"),
	species(34, "chronomoth", "Chronomoth", 6, { "Wing" }, 160, 255, 240, "mvp"),
	species(35, "astralope", "Astralope", 6, { "Horn" }, 255, 230, 180, "v1.1"),
	species(36, "grand_nebula", "Grand Nebula", 7, { "Comet", "Ring" }, 255, 255, 255, "mvp", "comet"),
} :: { SpeciesDef }
Nebbies.Species[36].hsvAccent = true

Nebbies.SPECIES_COUNT = 36 -- identifiants réservés (bits de l'Atlas)

Nebbies.byKey = {} :: { [string]: number }
for _, def in Nebbies.Species do
	Nebbies.byKey[def.key] = def.id
end

-- Espèces fixes citées par le GDD (clés, pas de nombres magiques dans les services)
Nebbies.Named = {
	Welcome = Nebbies.byKey.puffkin, -- Puffkins de bienvenue (§3)
	CalendarDay5 = Nebbies.byKey.daybreak_puff, -- §7.3
	StarterKit = { Nebbies.byKey.cometcub, Nebbies.byKey.frostfinch, Nebbies.byKey.daybreak_puff }, -- §8.3
	Cosmic = Nebbies.byKey.grand_nebula,
}

-- ---------------------------------------------------------------------------------------------
-- Aides pures (contrat, implémentées ici ; testées par tests/specs/Contract.spec.luau)
-- ---------------------------------------------------------------------------------------------

function Nebbies.isVersionEnabled(version: string): boolean
	return Nebbies.ENABLED_VERSIONS[version] == true
end

function Nebbies.isSpeciesEnabled(s: number): boolean
	local def = Nebbies.Species[s]
	return def ~= nil and Nebbies.isVersionEnabled(def.version)
end

function Nebbies.isFormEnabled(f: number): boolean
	local def = Nebbies.Forms[f]
	return def ~= nil and Nebbies.isVersionEnabled(def.version)
end

-- Espèces activées d'une rareté, triées par id (tirage uniforme dans SpawnService/EventService)
local byRarityCache: { [number]: { number } } = {}
function Nebbies.speciesOfRarity(rarity: number): { number }
	local cached = byRarityCache[rarity]
	if cached then
		return cached
	end
	local out = {}
	for _, def in Nebbies.Species do
		if def.rarity == rarity and Nebbies.isVersionEnabled(def.version) then
			table.insert(out, def.id)
		end
	end
	byRarityCache[rarity] = out
	return out
end

-- Formes activées (Atlas : 5 au MVP, 6 en v1.1)
function Nebbies.enabledForms(): { number }
	local out = {}
	for f = 0, Nebbies.FORM_COUNT - 1 do
		if Nebbies.isFormEnabled(f) then
			table.insert(out, f)
		end
	end
	return out
end

-- Nombre d'entrées d'Atlas possibles (150 au MVP, 216 en v1.1)
function Nebbies.atlasTotal(): number
	local species = 0
	for _, def in Nebbies.Species do
		if Nebbies.isVersionEnabled(def.version) then
			species += 1
		end
	end
	return species * #Nebbies.enabledForms()
end

function Nebbies.pack(s: number, f: number, v: number): number
	return bit32.bor(s, bit32.lshift(f, 6), bit32.lshift(v, 9))
end

function Nebbies.unpack(code: number): (number, number, number)
	return bit32.band(code, 63), bit32.band(bit32.rshift(code, 6), 7), bit32.band(bit32.rshift(code, 9), 7)
end

-- Code valide = espèce 1-36, forme 0-5, variantes ⊂ {1, 2, 4}
function Nebbies.isValidCode(code: unknown): boolean
	if type(code) ~= "number" or code ~= code or code % 1 ~= 0 or code < 0 or code >= 4096 then
		return false
	end
	local s, f = Nebbies.unpack(code)
	return s >= 1 and s <= Nebbies.SPECIES_COUNT and f <= Nebbies.FORM_COUNT - 1
end

function Nebbies.rarityOf(s: number): number
	local def = Nebbies.Species[s]
	return if def then def.rarity else 1
end

-- Index de bit (0-based) d'une entrée d'Atlas (espèce × forme)
function Nebbies.atlasIndex(s: number, f: number): number
	return (s - 1) * Nebbies.FORM_COUNT + f
end

-- Index de bit (0-based) d'un badge : Golden s − 1, Huge 36 + s − 1, Starborn 72 + s − 1
function Nebbies.badgeIndex(variantKey: string, s: number): number
	local base = if variantKey == "golden" then 0 elseif variantKey == "huge" then 36 else 72
	return base + s - 1
end

-- Lecture / écriture d'un bit dans un tableau de mots de 32 bits (Atlas, badges)
function Nebbies.testBit(words: { number }, index: number): boolean
	local word = words[index // 32 + 1] or 0
	return bit32.btest(word, bit32.lshift(1, index % 32))
end

-- Retourne true si le bit vient d'être posé (il ne l'était pas)
function Nebbies.setBit(words: { number }, index: number): boolean
	local i = index // 32 + 1
	local mask = bit32.lshift(1, index % 32)
	local word = words[i] or 0
	if bit32.btest(word, mask) then
		return false
	end
	words[i] = bit32.bor(word, mask)
	return true
end

return Nebbies
