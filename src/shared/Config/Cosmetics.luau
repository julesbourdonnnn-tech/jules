--!strict
-- Cosmétiques et palette des ranchs (GDD §5.4). Contrat (architecte) : données figées.
-- Tout est gratuit ou décoratif : aucun cosmétique ne change la vitesse, la capture ou le revenu.
-- Source d'un cosmétique (`source`) :
--   free             gratuit
--   plopDay n        Nourrir Plop, n jours au total (Config/Quests.Feed)
--   dex n            n tampons du Squishydex (Config/Quests.Dex)
--   pass key         pass « Pour toujours » (Config/Monetization.Passes)
--   product key      produit Robux (tenues)
--   rebirth n        R ≥ n
--   weekly key       top 10 d'un classement de la semaine (titre porté la semaine suivante, session)
-- Textes : « cosmetic.<kind>.<id> » (EN/FR).

export type CosmeticSource = {
	kind: "free" | "plopDay" | "dex" | "pass" | "product" | "rebirth" | "weekly",
	value: number?, -- jours, tampons ou R
	key: string?, -- pass, produit ou classement
}

export type CosmeticDef = {
	id: string,
	kind: "saddle" | "trail" | "outfit" | "title" | "theme" | "flag" | "emote" | "sticker" | "bowl",
	order: number,
	source: CosmeticSource,
	color: Color3?, -- selles, traînées
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Cosmetics = {}

-- stylua: ignore start
Cosmetics.List = {
	-- Selles (couleur)
	{ id = "classic", kind = "saddle", order = 1, source = { kind = "free" } }, -- couleur du ranch
	{ id = "peach", kind = "saddle", order = 2, source = { kind = "plopDay", value = 3 }, color = rgb(255, 190, 150) },
	{ id = "strawberry", kind = "saddle", order = 3, source = { kind = "plopDay", value = 21 }, color = rgb(240, 90, 120) },
	{ id = "mint", kind = "saddle", order = 4, source = { kind = "dex", value = 25 }, color = rgb(150, 235, 200) },
	{ id = "lavender", kind = "saddle", order = 5, source = { kind = "dex", value = 130 }, color = rgb(190, 160, 250) },
	{ id = "cloud", kind = "saddle", order = 6, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(240, 245, 255) },
	{ id = "candyStripes", kind = "saddle", order = 7, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(255, 120, 150) },
	{ id = "starry", kind = "saddle", order = 8, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(70, 80, 160) },
	{ id = "cookie", kind = "saddle", order = 9, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(200, 150, 100) },
	{ id = "bubble", kind = "saddle", order = 10, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(160, 220, 255) },
	{ id = "royal", kind = "saddle", order = 11, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(200, 40, 60) },
	-- Traînées (derrière la monture)
	{ id = "bubbles", kind = "trail", order = 1, source = { kind = "dex", value = 50 }, color = rgb(190, 230, 255) },
	{ id = "sprinkles", kind = "trail", order = 2, source = { kind = "plopDay", value = 50 }, color = rgb(255, 180, 210) },
	{ id = "pinkBubbles", kind = "trail", order = 3, source = { kind = "plopDay", value = 5 }, color = rgb(255, 170, 210) },
	{ id = "rainbowRibbon", kind = "trail", order = 4, source = { kind = "pass", key = "SaddlesTrails" } },
	{ id = "glitter", kind = "trail", order = 5, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(255, 230, 150) },
	{ id = "jellyDrops", kind = "trail", order = 6, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(140, 220, 255) },
	{ id = "stars", kind = "trail", order = 7, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(255, 220, 90) },
	{ id = "snowflakes", kind = "trail", order = 8, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(230, 245, 255) },
	{ id = "musicNotes", kind = "trail", order = 9, source = { kind = "pass", key = "SaddlesTrails" }, color = rgb(200, 170, 255) },
	-- Tenues (sur un squishy choisi ; une tenue achetée appartient au compte)
	{ id = "plopBib", kind = "outfit", order = 1, source = { kind = "plopDay", value = 7 } },
	{ id = "sweater", kind = "outfit", order = 2, source = { kind = "product", key = "OutfitSweater" } },
	{ id = "jellyCrown", kind = "outfit", order = 3, source = { kind = "product", key = "OutfitCrown" } },
	{ id = "winterScarf", kind = "outfit", order = 4, source = { kind = "product", key = "OutfitWinter" } },
	-- Titres (sous le nom)
	{ id = "little_collector", kind = "title", order = 1, source = { kind = "dex", value = 10 } },
	{ id = "squishologist", kind = "title", order = 2, source = { kind = "dex", value = 75 } },
	{ id = "dex_master", kind = "title", order = 3, source = { kind = "dex", value = 200 } },
	{ id = "splorch_star", kind = "title", order = 4, source = { kind = "rebirth", value = 5 } },
	{ id = "splorch_legend", kind = "title", order = 5, source = { kind = "rebirth", value = 10 } },
	{ id = "splorch_hero", kind = "title", order = 6, source = { kind = "rebirth", value = 15 } },
	{ id = "jelly_titan", kind = "title", order = 7, source = { kind = "rebirth", value = 20 } },
	{ id = "plops_best_friend", kind = "title", order = 8, source = { kind = "plopDay", value = 30 } },
	{ id = "stamp_hunter", kind = "title", order = 9, source = { kind = "weekly", key = "stamps" } },
	{ id = "combo_star", kind = "title", order = 10, source = { kind = "weekly", key = "combo" } },
	{ id = "top_catcher", kind = "title", order = 11, source = { kind = "weekly", key = "catchScore" } },
	{ id = "super_helper", kind = "title", order = 12, source = { kind = "weekly", key = "helpful" } },
	{ id = "big_heart", kind = "title", order = 13, source = { kind = "weekly", key = "generous" } },
	-- Thèmes de ranch
	{ id = "color", kind = "theme", order = 1, source = { kind = "free" } }, -- couleur du ranch
	{ id = "moonlit", kind = "theme", order = 2, source = { kind = "dex", value = 160 } },
	{ id = "candyNight", kind = "theme", order = 3, source = { kind = "plopDay", value = 75 } },
	-- Drapeaux de ranch
	{ id = "squishydex", kind = "flag", order = 1, source = { kind = "dex", value = 100 } },
	{ id = "day14", kind = "flag", order = 2, source = { kind = "plopDay", value = 14 } },
	-- Emotes de la croix ← (au choix dans les Réglages, à la place de Bravo)
	{ id = "bravo", kind = "emote", order = 1, source = { kind = "free" } },
	{ id = "bellyFlop", kind = "emote", order = 2, source = { kind = "plopDay", value = 10 } },
	{ id = "crown", kind = "emote", order = 3, source = { kind = "dex", value = 260 } },
	-- Autocollant et bol (Nourrir Plop)
	{ id = "day1", kind = "sticker", order = 1, source = { kind = "plopDay", value = 1 } },
	{ id = "goldenBowl", kind = "bowl", order = 1, source = { kind = "plopDay", value = 100 } },
} :: { CosmeticDef }
-- stylua: ignore end

-- Palette des 16 ranchs (couleur du propriétaire), index = numéro du ranch (1 … 16)
Cosmetics.RanchColors = {
	rgb(255, 130, 120), -- 1 Corail
	rgb(255, 180, 130), -- 2 Pêche
	rgb(250, 225, 100), -- 3 Citron
	rgb(170, 225, 100), -- 4 Citron vert
	rgb(110, 225, 170), -- 5 Menthe
	rgb(70, 205, 205), -- 6 Sarcelle
	rgb(110, 180, 255), -- 7 Ciel
	rgb(140, 150, 250), -- 8 Pervenche
	rgb(185, 140, 250), -- 9 Lilas
	rgb(225, 130, 225), -- 10 Orchidée
	rgb(255, 130, 180), -- 11 Rose
	rgb(230, 90, 130), -- 12 Framboise
	rgb(215, 160, 100), -- 13 Caramel
	rgb(225, 205, 160), -- 14 Sable
	rgb(150, 235, 215), -- 15 Écume
	rgb(180, 195, 215), -- 16 Nuage
} :: { Color3 }

Cosmetics.FreeRanchColor = rgb(130, 130, 140) -- ranch libre : gris, sans lumière

-- Emotes jouées (Humanoid:PlayEmote, sous pcall) par signal de la croix (GDD §6.5)
Cosmetics.EmoteSignals = {
	{ kind = 1, key = "hello", dpad = "Up", keyboard = "One", emote = "wave", icon = "hand" },
	{ kind = 2, key = "thanks", dpad = "Right", keyboard = "Two", emote = "wave", icon = "heart" },
	{ kind = 3, key = "bravo", dpad = "Left", keyboard = "Three", emote = "cheer", icon = "star" },
}

local ById: { [string]: CosmeticDef } = {}
for _, def in Cosmetics.List do
	ById[def.kind .. ":" .. def.id] = def
end
Cosmetics.ByKindId = ById -- clé « <kind>:<id> »

return Cosmetics
