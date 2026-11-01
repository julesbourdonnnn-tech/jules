--!strict
-- Les 26 espèces (GDD §5.1) et les 6 familles (GDD §4.17). Contrat (architecte) : données figées.
-- L'identifiant numérique est DÉFINITIF (sauvegardé, champ `s` des squishies, index des tableaux
-- denses `dex.mut`, `dex.stars`, `trophies`) : on n'en change jamais l'ordre, on ajoute à la fin.
-- Une nouvelle espèce par semaine = une nouvelle ligne avec son horodatage `release`, sans nouveau
-- code (GDD §7.6) : chaque module lit Species.isReleased(def, Clock.unix()).
-- Les noms restent en anglais dans les deux langues (propriété intellectuelle, GDD §15) ; ils ont
-- quand même leur clé « species.<key> » (EN = FR) et une description « species.<key>.desc ».
--
-- Ligne d'espèce (données de Render/SquishyBuilder, GDD §5.2) :
--   body     proportions du corps X / Y / Z (× diamètre D)
--   top      haut de tête : "dropAntenna" | "caramelCap" | "leaf" | "tinyCrown" | "catEars" |
--            "catEarsWhiskers" | "catEarsFlowers" | "bugEyes" | "bugEyesLily" | "bugEyesSpring" |
--            "frill" | "bubbleFrill" | "coralCrown" | "floppyEars" | "oddEars" | "earsClover" |
--            "crescentEars" | "softBumps" | "softSpikes" | "wingsHorns" | "flameCrest" |
--            "crownCape" | "crescentAntenna"
--   eyes     "bigShiny" | "sleepy" | "dots" | "stars" | "happyClosed" | "hearts" | "bulgy" |
--            "bulgyWink" | "shiny" | "wink" | "sparkle" | "threeEyes"
--   colors   main / second (RGB du GDD)
--   pattern  "lightBelly" | "cap" | "seeds" | "layers" | "innerEars" | "tigerStripes" |
--            "spiralTail" | "petals" | "pondSpots" | "orangeSpots" | "starSpots" | "none" |
--            "bubbles" | "lollipopSpiral" | "reefBumps" | "pinkNose" | "whiteSocks" | "cloverBelly" |
--            "starSpeckles" | "creamBelly" | "lightScales" | "goldBelly" | "goldDrop" | "floatDrops"
--   patternCount  nombre d'éléments du motif quand il en a (pépins 8, bosses 5, gouttes 2…)
--   wobble   hz = fréquence du tremblement, amp = amplitude d'écrasement (0,08 = 8 %)
-- Champs réservés pour plus tard (GDD §5.1, §17.2) : release (Clock.unix() d'arrivée, 0 = dès le
-- lancement), duo (janvier), recipe ("" = aucune ; janvier), limitedUntil et encore (février).

export type FamilyKey = "jelly" | "kitty" | "froggy" | "axolo" | "bunny" | "spiky" | "secret"

export type SpeciesDef = {
	id: number,
	key: string,
	name: string,
	family: FamilyKey,
	rarity: number, -- Config/Rarities (1 … 7)
	body: { x: number, y: number, z: number },
	top: string,
	eyes: string,
	colors: { main: Color3, second: Color3 },
	pattern: string,
	patternCount: number,
	wobble: { hz: number, amp: number },
	release: number,
	duo: boolean,
	recipe: string,
	limitedUntil: number,
	encore: { number },
}

export type FamilyBonus = {
	kind: "growth" | "press" | "runaway" | "poolSlot" | "vatInterval" | "offlineHours",
	value: number,
}

export type FamilyDef = {
	key: FamilyKey,
	order: number,
	unlockR: number, -- naissances de la Cuve possibles à partir de ce R (GDD §4.9) ; -1 = jamais
	species: { number }, -- les 4 espèces (identifiants), dans l'ordre Commun, Peu commun, puis rares
	uncommon: number, -- espèce Peu commune (cadeaux du Grand Splorch d'une espèce Épique+, GDD §4.15)
	bonus: FamilyBonus?, -- bonus quand les 4 espèces sont tamponnées (aucun pour les Secrets)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Ligne complète ; les champs réservés prennent leur valeur de lancement
local function row(
	id: number,
	key: string,
	name: string,
	family: FamilyKey,
	rarity: number,
	body: { number },
	top: string,
	eyes: string,
	main: Color3,
	second: Color3,
	pattern: string,
	patternCount: number,
	hz: number,
	amp: number
): SpeciesDef
	return {
		id = id,
		key = key,
		name = name,
		family = family,
		rarity = rarity,
		body = { x = body[1], y = body[2], z = body[3] },
		top = top,
		eyes = eyes,
		colors = { main = main, second = second },
		pattern = pattern,
		patternCount = patternCount,
		wobble = { hz = hz, amp = amp },
		release = 0,
		duo = false,
		recipe = "",
		limitedUntil = 0,
		encore = {},
	}
end

-- Raretés : 1 Commun, 2 Peu commun, 3 Rare, 4 Épique, 5 Légendaire, 6 Mythique, 7 Secret
-- stylua: ignore start
local List: { SpeciesDef } = {
	-- Jelly
	row(1, "plop", "Plop", "jelly", 1, { 1.0, 1.0, 1.0 }, "dropAntenna", "bigShiny", rgb(140, 220, 255), rgb(255, 255, 255), "lightBelly", 1, 1.0, 0.08),
	row(2, "wibble", "Wibble", "jelly", 2, { 0.9, 1.2, 0.9 }, "caramelCap", "sleepy", rgb(255, 214, 140), rgb(170, 100, 50), "cap", 1, 1.4, 0.12),
	row(3, "jiggleberry", "Jiggleberry", "jelly", 3, { 1.0, 1.05, 1.0 }, "leaf", "dots", rgb(240, 80, 120), rgb(120, 200, 90), "seeds", 8, 1.2, 0.10),
	row(4, "grand_gloop", "Grand Gloop", "jelly", 5, { 1.3, 0.9, 1.3 }, "tinyCrown", "stars", rgb(120, 160, 255), rgb(255, 220, 120), "layers", 3, 0.7, 0.06),
	-- Kitty
	row(5, "mochi_mew", "Mochi Mew", "kitty", 1, { 1.05, 0.95, 1.0 }, "catEars", "dots", rgb(250, 245, 240), rgb(255, 180, 200), "innerEars", 2, 1.1, 0.08),
	row(6, "purrpudding", "Purrpudding", "kitty", 2, { 1.0, 1.0, 1.0 }, "catEars", "happyClosed", rgb(255, 170, 90), rgb(200, 110, 50), "tigerStripes", 3, 1.2, 0.10),
	row(7, "whiskerwob", "Whiskerwob", "kitty", 4, { 0.95, 1.1, 0.95 }, "catEarsWhiskers", "stars", rgb(190, 150, 255), rgb(255, 240, 255), "spiralTail", 1, 1.0, 0.09),
	row(8, "blossompurr", "Blossompurr", "kitty", 6, { 1.0, 1.0, 1.0 }, "catEarsFlowers", "hearts", rgb(255, 170, 210), rgb(255, 255, 255), "petals", 3, 0.9, 0.07),
	-- Froggy
	row(9, "ribbit_drop", "Ribbit Drop", "froggy", 1, { 1.1, 0.9, 1.0 }, "bugEyes", "bulgy", rgb(120, 210, 110), rgb(230, 250, 180), "lightBelly", 1, 1.3, 0.10),
	row(10, "lilypuff", "Lilypuff", "froggy", 2, { 1.1, 0.85, 1.1 }, "bugEyesLily", "bulgy", rgb(90, 200, 190), rgb(140, 230, 120), "pondSpots", 4, 1.1, 0.09),
	row(11, "croakaroo", "Croakaroo", "froggy", 3, { 0.9, 1.15, 0.9 }, "bugEyes", "bulgyWink", rgb(255, 220, 80), rgb(255, 140, 60), "orangeSpots", 4, 1.5, 0.12),
	row(12, "boingtoad", "Boingtoad", "froggy", 4, { 1.0, 1.0, 1.0 }, "bugEyesSpring", "stars", rgb(160, 110, 230), rgb(255, 230, 120), "starSpots", 3, 2.0, 0.18),
	-- Axolo
	row(13, "frillo", "Frillo", "axolo", 1, { 1.1, 0.9, 1.15 }, "frill", "dots", rgb(255, 175, 200), rgb(255, 110, 150), "none", 0, 1.0, 0.08),
	row(14, "gillygum", "Gillygum", "axolo", 2, { 1.1, 0.9, 1.15 }, "bubbleFrill", "shiny", rgb(150, 170, 255), rgb(255, 140, 220), "bubbles", 3, 1.1, 0.09),
	row(15, "lotlolly", "Lotlolly", "axolo", 4, { 1.0, 1.0, 1.1 }, "frill", "wink", rgb(255, 200, 120), rgb(120, 220, 255), "lollipopSpiral", 1, 1.0, 0.09),
	row(16, "coralotl", "Coralotl", "axolo", 5, { 1.15, 1.0, 1.2 }, "coralCrown", "shiny", rgb(255, 120, 100), rgb(255, 230, 200), "reefBumps", 5, 0.8, 0.07),
	-- Bunny
	row(17, "bunbun", "Bunbun", "bunny", 1, { 1.0, 1.0, 1.0 }, "floppyEars", "dots", rgb(255, 240, 210), rgb(255, 190, 200), "pinkNose", 1, 1.2, 0.09),
	row(18, "hopscotch", "Hopscotch", "bunny", 2, { 0.95, 1.05, 0.95 }, "oddEars", "sleepy", rgb(180, 195, 220), rgb(255, 255, 255), "whiteSocks", 2, 1.4, 0.11),
	row(19, "clover_hop", "Clover Hop", "bunny", 3, { 1.0, 1.0, 1.0 }, "earsClover", "shiny", rgb(160, 230, 170), rgb(90, 170, 90), "cloverBelly", 1, 1.3, 0.10),
	row(20, "moonhop", "Moonhop", "bunny", 4, { 1.0, 1.05, 1.0 }, "crescentEars", "stars", rgb(60, 70, 140), rgb(255, 240, 160), "starSpeckles", 6, 1.0, 0.09),
	-- Spiky
	row(21, "nubbin", "Nubbin", "spiky", 1, { 1.05, 0.95, 1.05 }, "softBumps", "dots", rgb(255, 200, 160), rgb(255, 150, 120), "none", 3, 1.1, 0.08),
	row(22, "prickle_puff", "Prickle Puff", "spiky", 2, { 1.0, 1.0, 1.0 }, "softSpikes", "shiny", rgb(200, 150, 110), rgb(255, 230, 200), "creamBelly", 7, 1.2, 0.10),
	row(23, "drago_drop", "Drago Drop", "spiky", 4, { 1.0, 1.0, 1.05 }, "wingsHorns", "stars", rgb(130, 200, 255), rgb(255, 255, 255), "lightScales", 1, 1.0, 0.09),
	row(24, "emberwob", "Emberwob", "spiky", 5, { 1.1, 1.05, 1.1 }, "flameCrest", "shiny", rgb(255, 130, 60), rgb(255, 220, 120), "goldBelly", 1, 0.9, 0.07),
	-- Secrets (sans famille)
	row(25, "royal_plop", "Royal Plop", "secret", 7, { 1.05, 1.05, 1.05 }, "crownCape", "sparkle", rgb(140, 220, 255), rgb(255, 210, 80), "goldDrop", 1, 1.0, 0.08),
	row(26, "moonplop", "Moonplop", "secret", 7, { 1.0, 1.0, 1.0 }, "crescentAntenna", "threeEyes", rgb(210, 220, 255), rgb(150, 130, 255), "floatDrops", 2, 0.8, 0.07),
}
-- stylua: ignore end

local Families: { [FamilyKey]: FamilyDef } = {
	jelly = {
		key = "jelly",
		order = 1,
		unlockR = 0,
		species = { 1, 2, 3, 4 },
		uncommon = 2,
		bonus = { kind = "growth", value = 0.10 }, -- +10 % de croissance
	},
	kitty = {
		key = "kitty",
		order = 2,
		unlockR = 0,
		species = { 5, 6, 7, 8 },
		uncommon = 6,
		bonus = { kind = "press", value = 0.10 }, -- +10 % de pièces par pression
	},
	froggy = {
		key = "froggy",
		order = 3,
		unlockR = 0,
		species = { 9, 10, 11, 12 },
		uncommon = 10,
		bonus = { kind = "runaway", value = 50 }, -- créature en fuite toutes les 50 s
	},
	axolo = {
		key = "axolo",
		order = 4,
		unlockR = 1,
		species = { 13, 14, 15, 16 },
		uncommon = 14,
		bonus = { kind = "poolSlot", value = 1 }, -- +1 place dans le Bassin (6)
	},
	bunny = {
		key = "bunny",
		order = 5,
		unlockR = 3,
		species = { 17, 18, 19, 20 },
		uncommon = 18,
		bonus = { kind = "vatInterval", value = 0.9 }, -- intervalle de la Cuve × 0,9
	},
	spiky = {
		key = "spiky",
		order = 6,
		unlockR = 5,
		species = { 21, 22, 23, 24 },
		uncommon = 22,
		bonus = { kind = "offlineHours", value = 1 }, -- limite hors ligne + 1 h
	},
	secret = {
		key = "secret",
		order = 7,
		unlockR = -1,
		species = { 25, 26 },
		uncommon = 2, -- cadeau d'un Secret qui s'envole : Wibble (GDD §4.15)
		bonus = nil,
	},
}

local ById: { [number]: SpeciesDef } = {}
local ByKey: { [string]: SpeciesDef } = {}
for _, def in List do
	ById[def.id] = def
	ByKey[def.key] = def
end

local Species = {
	List = List,
	ById = ById,
	ByKey = ByKey,
	Families = Families,
	FamilyOrder = { "jelly", "kitty", "froggy", "axolo", "bunny", "spiky", "secret" } :: { FamilyKey },
	-- Secrets : un tirage Secret de la Cuve donne ROYAL ; pendant la Jelly Moon, ROYAL ou MOON à chances
	-- égales (GDD §4.9)
	ROYAL = 25,
	MOON = 26,
	PLOP = 1,
	MOCHI_MEW = 5,
	-- Rotation du MEGA SQUISH : ((semaine + numéro du MEGA dans la semaine) mod MegaRotation) + 1,
	-- Secrets exclus (GDD §5.1)
	MegaRotation = 24,
}

-- Espèce publiée à l'instant `unix` (lignes publiées en avance, actives à leur date, GDD §7.6)
function Species.isReleased(def: SpeciesDef, unix: number): boolean
	return def.release <= unix
end

return Species
