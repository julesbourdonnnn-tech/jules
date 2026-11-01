--!strict
-- Raretés des squishies (GDD §4.4). Contrat (architecte) : données figées, lues par Logic/Formulas,
-- Logic/Odds, Render/SquishyBuilder, l'interface et les bannières.
-- L'identifiant numérique est DÉFINITIF (il est sauvegardé dans les lignes d'espèces) : on n'en
-- change jamais l'ordre. La rareté se lit à l'aura : couleur ET forme (daltonisme, GDD §14).
--   id        1 (Commun) … 7 (Secret)
--   key       clé courte ; texte « rarity.<key> » (EN/FR) dans Localization/Strings
--   mult      multiplicateur de revenu (GDD §4.3, facteur « rareté »)
--   color     couleur de l'aura et de l'étiquette
--   aura      forme de l'aura (Render/SquishyBuilder) : "none" | "circle" | "dots3" | "diamonds4" |
--             "starCrown" | "doubleRing" | "floatingDiamond"
--   light     PointLight sur l'aura (Légendaire)
--   highlight contour Highlight (Mythique ; budget du GDD §12.9)
--   rainbow   aura arc-en-ciel sur fond noir (Secret)
--   hatchFx   effet de naissance (GDD §9.4) : "basic" | "rare" | "legend" | "mythic"
--   banner    une naissance de cette rareté lance une bannière de serveur
--   autoLock  verrou automatique à la naissance (GDD §4.13 : Légendaire ou mieux)
--   sellConfirm  vente / relâche en 2 étapes (GDD §4.13 : Épique ou mieux)
--   sellHold     maintien de 0,6 s pour vendre (GDD §4.13 : Rare ou mieux)

export type RarityDef = {
	id: number,
	key: string,
	mult: number,
	color: Color3,
	aura: string,
	light: boolean,
	highlight: boolean,
	rainbow: boolean,
	hatchFx: string,
	banner: boolean,
	autoLock: boolean,
	sellConfirm: boolean,
	sellHold: boolean,
}

local List: { RarityDef } = {
	{
		id = 1,
		key = "common",
		mult = 1,
		color = Color3.fromRGB(220, 220, 225),
		aura = "none",
		light = false,
		highlight = false,
		rainbow = false,
		hatchFx = "basic",
		banner = false,
		autoLock = false,
		sellConfirm = false,
		sellHold = false,
	},
	{
		id = 2,
		key = "uncommon",
		mult = 3,
		color = Color3.fromRGB(120, 220, 130),
		aura = "circle",
		light = false,
		highlight = false,
		rainbow = false,
		hatchFx = "basic",
		banner = false,
		autoLock = false,
		sellConfirm = false,
		sellHold = false,
	},
	{
		id = 3,
		key = "rare",
		mult = 10,
		color = Color3.fromRGB(90, 170, 255),
		aura = "dots3",
		light = false,
		highlight = false,
		rainbow = false,
		hatchFx = "rare",
		banner = false,
		autoLock = false,
		sellConfirm = false,
		sellHold = true,
	},
	{
		id = 4,
		key = "epic",
		mult = 40,
		color = Color3.fromRGB(180, 110, 255),
		aura = "diamonds4",
		light = false,
		highlight = false,
		rainbow = false,
		hatchFx = "rare",
		banner = false,
		autoLock = false,
		sellConfirm = true,
		sellHold = true,
	},
	{
		id = 5,
		key = "legendary",
		mult = 200,
		color = Color3.fromRGB(255, 200, 60),
		aura = "starCrown",
		light = true,
		highlight = false,
		rainbow = false,
		hatchFx = "legend",
		banner = true,
		autoLock = true,
		sellConfirm = true,
		sellHold = true,
	},
	{
		id = 6,
		key = "mythic",
		mult = 1000,
		color = Color3.fromRGB(255, 110, 190),
		aura = "doubleRing",
		light = false,
		highlight = true,
		rainbow = false,
		hatchFx = "mythic",
		banner = true,
		autoLock = true,
		sellConfirm = true,
		sellHold = true,
	},
	{
		id = 7,
		key = "secret",
		mult = 5000,
		color = Color3.fromRGB(20, 20, 30),
		aura = "floatingDiamond",
		light = false,
		highlight = false,
		rainbow = true,
		hatchFx = "mythic",
		banner = true,
		autoLock = true,
		sellConfirm = true,
		sellHold = true,
	},
}

local ByKey: { [string]: RarityDef } = {}
for _, def in List do
	ByKey[def.key] = def
end

local Rarities = {
	List = List,
	ByKey = ByKey,
	-- identifiants nommés (lisibilité du code ; jamais un nombre en dur dans un service)
	COMMON = 1,
	UNCOMMON = 2,
	RARE = 3,
	EPIC = 4,
	LEGENDARY = 5,
	MYTHIC = 6,
	SECRET = 7,
	Count = #List,
}

return Rarities
