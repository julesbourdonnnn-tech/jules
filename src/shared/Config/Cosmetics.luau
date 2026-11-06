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

-- =================================================================================================
-- Contrat v2.0 (GDD v2.0 Annexe B, §4.29, §5.4, §7.5, §11.5 ; docs/04 §27.6) : contenu nommé du jeu
-- complet. À PART de Cosmetics.List (que le jeu de base parcourt) tant que les interrupteurs sont
-- coupés ; fusionné dans List à l'étape d'intégration I (mêmes identifiants, ajout seulement).
-- Sources v2.0 (`source.kind`) : recordR n (premier passage du Record R n), ascend n (A ≥ n),
-- atelier i (ligne « Pour le plaisir » : bit i de atelierCosmetics, ou objet i de la ligne decoShop),
-- carnet n (Carnet du Ranch : n niveaux achetés), season n (costume de saison), track (palier 12 de
-- la piste), play s (secondes de jeu), dex n, plopDay n, objectives n (objectifs du jour réclamés),
-- moon n (Jelly Moon jouées), track n (pistes de la semaine finies), size n (jalon géant : plus
-- grande taille jamais atteinte biggestEver ≥ n, GDD §4.17, §5.4 ; lot A4). Contract_unlocks.spec.
-- =================================================================================================

-- Les 40 objets de Déco perso (Annexe B.1) : n = numéro définitif (bit n de decoPerso.owned) ;
-- size « P » (8 petits emplacements) ou « G » (4 grands) ; les 24 derniers s'achètent à l'Atelier
-- dans cet ordre fixe (ligne decoShop : source.value = position dans la ligne)
-- stylua: ignore start
Cosmetics.DecoPerso = {
	{ n = 1, id = "namePennant", key = "deco.namePennant", size = "P", source = { kind = "play", value = 300 } },
	{ n = 2, id = "plopBench", key = "deco.plopBench", size = "P", source = { kind = "dex", value = 25 } },
	{ n = 3, id = "pinkLantern", key = "deco.pinkLantern", size = "P", source = { kind = "dex", value = 50 } },
	{ n = 4, id = "wateringCan", key = "deco.wateringCan", size = "P", source = { kind = "dex", value = 100 } },
	{ n = 5, id = "mochiStatue", key = "deco.mochiStatue", size = "P", source = { kind = "dex", value = 150 } },
	{ n = 6, id = "goldFountain", key = "deco.goldFountain", size = "G", source = { kind = "dex", value = 260 } },
	{ n = 7, id = "plopBowl", key = "deco.plopBowl", size = "P", source = { kind = "plopDay", value = 7 } },
	{ n = 8, id = "cloudHammock", key = "deco.cloudHammock", size = "G", source = { kind = "plopDay", value = 30 } },
	{ n = 9, id = "morningBell", key = "deco.morningBell", size = "P", source = { kind = "objectives", value = 25 } },
	{ n = 10, id = "toyBox", key = "deco.toyBox", size = "P", source = { kind = "objectives", value = 100 } },
	{ n = 11, id = "plushMoon", key = "deco.plushMoon", size = "P", source = { kind = "moon", value = 1 } },
	{ n = 12, id = "moonKite", key = "deco.moonKite", size = "G", source = { kind = "moon", value = 4 } },
	{ n = 13, id = "ribbonChest", key = "deco.ribbonChest", size = "P", source = { kind = "track", value = 1 } },
	{ n = 14, id = "miniCarousel", key = "deco.miniCarousel", size = "G", source = { kind = "track", value = 4 } },
	{ n = 15, id = "workbench", key = "deco.workbench", size = "P", source = { kind = "carnet", value = 750 } },
	{ n = 16, id = "sugarCrane", key = "deco.sugarCrane", size = "G", source = { kind = "carnet", value = 7500 } },
	{ n = 17, id = "mushroom", key = "deco.mushroom", size = "P", source = { kind = "atelier", value = 1 } },
	{ n = 18, id = "candyBucket", key = "deco.candyBucket", size = "P", source = { kind = "atelier", value = 2 } },
	{ n = 19, id = "birdhouse", key = "deco.birdhouse", size = "P", source = { kind = "atelier", value = 3 } },
	{ n = 20, id = "hiSign", key = "deco.hiSign", size = "P", source = { kind = "atelier", value = 4 } },
	{ n = 21, id = "puddingStool", key = "deco.puddingStool", size = "P", source = { kind = "atelier", value = 5 } },
	{ n = 22, id = "mintLantern", key = "deco.mintLantern", size = "P", source = { kind = "atelier", value = 6 } },
	{ n = 23, id = "wishingWell", key = "deco.wishingWell", size = "P", source = { kind = "atelier", value = 7 } },
	{ n = 24, id = "miniWindmill", key = "deco.miniWindmill", size = "P", source = { kind = "atelier", value = 8 } },
	{ n = 25, id = "lollipopSwing", key = "deco.lollipopSwing", size = "G", source = { kind = "atelier", value = 9 } },
	{ n = 26, id = "syrupBarrel", key = "deco.syrupBarrel", size = "P", source = { kind = "atelier", value = 10 } },
	{ n = 27, id = "sugarSandbox", key = "deco.sugarSandbox", size = "G", source = { kind = "atelier", value = 11 } },
	{ n = 28, id = "musicBox", key = "deco.musicBox", size = "P", source = { kind = "atelier", value = 12 } },
	{ n = 29, id = "iceCreamStand", key = "deco.iceCreamStand", size = "G", source = { kind = "atelier", value = 13 } },
	{ n = 30, id = "rainbowBridge", key = "deco.rainbowBridge", size = "G", source = { kind = "atelier", value = 14 } },
	{ n = 31, id = "rockingBoat", key = "deco.rockingBoat", size = "P", source = { kind = "atelier", value = 15 } },
	{ n = 32, id = "flowerArch", key = "deco.flowerArch", size = "G", source = { kind = "atelier", value = 16 } },
	{ n = 33, id = "pipStatue", key = "deco.pipStatue", size = "P", source = { kind = "atelier", value = 17 } },
	{ n = 34, id = "cuckooClock", key = "deco.cuckooClock", size = "P", source = { kind = "atelier", value = 18 } },
	{ n = 35, id = "cakeTower", key = "deco.cakeTower", size = "G", source = { kind = "atelier", value = 19 } },
	{ n = 36, id = "hotAirBalloon", key = "deco.hotAirBalloon", size = "G", source = { kind = "atelier", value = 20 } },
	{ n = 37, id = "bouncyCastle", key = "deco.bouncyCastle", size = "G", source = { kind = "atelier", value = 21 } },
	{ n = 38, id = "giantSlide", key = "deco.giantSlide", size = "G", source = { kind = "atelier", value = 22 } },
	{ n = 39, id = "sugarRocket", key = "deco.sugarRocket", size = "G", source = { kind = "atelier", value = 23 } },
	{ n = 40, id = "jellyDragon", key = "deco.jellyDragon", size = "G", source = { kind = "atelier", value = 24 } },
}

-- Taille de chaque emplacement de decoPerso.slots (lot A4, D18) : 1 à 8 petits « P », 9 à 12 grands
-- « G » ; un objet ne se pose que sur un emplacement de SA taille (PlaceDeco, ProfileRepair, Invariants)
Cosmetics.DecoSlots = { "P", "P", "P", "P", "P", "P", "P", "P", "G", "G", "G", "G" }

-- Les 8 cosmétiques de la semaine (Annexe B.2, palier 12 de la piste), dans l'ordre de rotation
Cosmetics.WeeklyRotation = {
	{ id = "cookieSaddle", key = "weekly.cookieSaddle", kind = "saddle" },
	{ id = "bubbleTrail", key = "weekly.bubbleTrail", kind = "trail" },
	{ id = "strawberryFlag", key = "weekly.strawberryFlag", kind = "flag" },
	{ id = "polkaBow", key = "weekly.polkaBow", kind = "outfit" },
	{ id = "hugEmote", key = "weekly.hugEmote", kind = "emote" },
	{ id = "loyalBuddy", key = "weekly.loyalBuddy", kind = "title" },
	{ id = "peachPalette", key = "weekly.peachPalette", kind = "palette" },
	{ id = "pinkCushions", key = "weekly.pinkCushions", kind = "cushions" },
}

-- Selles, traînées, drapeaux, tenues, emotes, titres et habillages (thèmes) de la v2.0 (Annexe B.3,
-- B.5, B.6) ; key = clé de texte (EN/FR)
Cosmetics.ListV2 = {
	{ id = "confetti", kind = "saddle", key = "v2cosmetic.saddle.confetti", source = { kind = "recordR", value = 2 } },
	{ id = "goldenJelly", kind = "saddle", key = "v2cosmetic.saddle.goldenJelly", source = { kind = "recordR", value = 11 } },
	{ id = "cosmos", kind = "saddle", key = "v2cosmetic.saddle.cosmos", source = { kind = "recordR", value = 17 } },
	{ id = "titan", kind = "saddle", key = "v2cosmetic.saddle.titan", source = { kind = "recordR", value = 20 } },
	{ id = "partyPopper", kind = "saddle", key = "v2cosmetic.saddle.partyPopper", source = { kind = "atelier", value = 7 } },
	{ id = "brick", kind = "saddle", key = "v2cosmetic.saddle.brick", source = { kind = "carnet", value = 100 } },
	{ id = "icingSugar", kind = "saddle", key = "v2cosmetic.saddle.icingSugar", source = { kind = "season", value = 1 } },
	{ id = "cosmic", kind = "saddle", key = "v2cosmetic.saddle.cosmic", source = { kind = "size", value = 1e15 } },
	{ id = "confetti", kind = "trail", key = "v2cosmetic.trail.confetti", source = { kind = "recordR", value = 6 } },
	{ id = "jellyArc", kind = "trail", key = "v2cosmetic.trail.jellyArc", source = { kind = "recordR", value = 13 } },
	{ id = "streamers", kind = "trail", key = "v2cosmetic.trail.streamers", source = { kind = "atelier", value = 8 } },
	{ id = "littleHammers", kind = "trail", key = "v2cosmetic.trail.littleHammers", source = { kind = "carnet", value = 1000 } },
	{ id = "colour", kind = "trail", key = "v2cosmetic.trail.colour", source = { kind = "recordR", value = 25 } },
	{ id = "shootingStars", kind = "trail", key = "v2cosmetic.trail.shootingStars", source = { kind = "size", value = 1e18 } },
	{ id = "nine", kind = "flag", key = "v2cosmetic.flag.nine", source = { kind = "recordR", value = 9 } },
	{ id = "splorchRoyal", kind = "flag", key = "v2cosmetic.flag.splorchRoyal", source = { kind = "recordR", value = 19 } },
	{ id = "buildingSite", kind = "flag", key = "v2cosmetic.flag.buildingSite", source = { kind = "carnet", value = 250 } },
	{ id = "partyHat", kind = "outfit", key = "v2cosmetic.outfit.partyHat", source = { kind = "recordR", value = 7 } },
	{ id = "starGlasses", kind = "outfit", key = "v2cosmetic.outfit.starGlasses", source = { kind = "recordR", value = 16 } },
	{ id = "buildersCrown", kind = "outfit", key = "v2cosmetic.outfit.buildersCrown", source = { kind = "carnet", value = 10000 } },
	{ id = "splorch", kind = "emote", key = "v2cosmetic.emote.splorch", source = { kind = "recordR", value = 4 } },
	{ id = "wave", kind = "emote", key = "v2cosmetic.emote.wave", source = { kind = "recordR", value = 13 } },
	{ id = "confettiCrown", kind = "emote", key = "v2cosmetic.emote.confettiCrown", source = { kind = "recordR", value = 19 } },
	{ id = "bigPlopDance", kind = "emote", key = "v2cosmetic.emote.bigPlopDance", source = { kind = "atelier", value = 9 } },
	{ id = "hammerTap", kind = "emote", key = "v2cosmetic.emote.hammerTap", source = { kind = "carnet", value = 2500 } },
	{ id = "splorchMyth", kind = "title", key = "title.splorchMyth", source = { kind = "recordR", value = 25 } },
	{ id = "jellyMonarch", kind = "title", key = "title.jellyMonarch", source = { kind = "recordR", value = 30 } },
	{ id = "wobbleLegend", kind = "title", key = "title.wobbleLegend", source = { kind = "recordR", value = 35 } },
	{ id = "cosmicSplorcher", kind = "title", key = "title.cosmicSplorcher", source = { kind = "recordR", value = 40 } },
	{ id = "ascended", kind = "title", key = "title.ascended", source = { kind = "ascend", value = 1 } },
	{ id = "skyKeeper", kind = "title", key = "title.skyKeeper", source = { kind = "ascend", value = 3 } },
	{ id = "skyWobbler", kind = "title", key = "title.skyWobbler", source = { kind = "ascend", value = 5 } },
	{ id = "starJelly", kind = "title", key = "title.starJelly", source = { kind = "ascend", value = 10 } },
	{ id = "jellyGalaxy", kind = "title", key = "title.jellyGalaxy", source = { kind = "ascend", value = 20 } },
	{ id = "cosmicJelly", kind = "title", key = "title.cosmicJelly", source = { kind = "ascend", value = 40 } },
	{ id = "jellyForever", kind = "title", key = "title.jellyForever", source = { kind = "ascend", value = 60 } },
	{ id = "confettiStar", kind = "title", key = "title.confettiStar", source = { kind = "atelier", value = 11 } },
	{ id = "builder", kind = "title", key = "title.builder", source = { kind = "carnet", value = 50 } },
	{ id = "architect", kind = "title", key = "title.architect", source = { kind = "carnet", value = 500 } },
	{ id = "masterArchitect", kind = "title", key = "title.masterArchitect", source = { kind = "carnet", value = 5000 } },
	{ id = "sunKeeper", kind = "title", key = "title.sunKeeper", source = { kind = "size", value = 1e24 } },
	{ id = "r50", kind = "title", key = "title.r50", source = { kind = "recordR", value = 50 } },
	{ id = "r60", kind = "title", key = "title.r60", source = { kind = "recordR", value = 60 } },
	{ id = "r70", kind = "title", key = "title.r70", source = { kind = "recordR", value = 70 } },
	{ id = "r80", kind = "title", key = "title.r80", source = { kind = "recordR", value = 80 } },
	{ id = "r90", kind = "title", key = "title.r90", source = { kind = "recordR", value = 90 } },
	{ id = "r100", kind = "title", key = "title.r100", source = { kind = "recordR", value = 100 } },
	{ id = "r110", kind = "title", key = "title.r110", source = { kind = "recordR", value = 110 } },
	{ id = "r120", kind = "title", key = "title.r120", source = { kind = "recordR", value = 120 } },
	{ id = "r130", kind = "title", key = "title.r130", source = { kind = "recordR", value = 130 } },
	{ id = "r140", kind = "title", key = "title.r140", source = { kind = "recordR", value = 140 } },
	{ id = "r150", kind = "title", key = "title.r150", source = { kind = "recordR", value = 150 } },
	{ id = "r160", kind = "title", key = "title.r160", source = { kind = "recordR", value = 160 } },
	{ id = "r170", kind = "title", key = "title.r170", source = { kind = "recordR", value = 170 } },
	{ id = "r180", kind = "title", key = "title.r180", source = { kind = "recordR", value = 180 } },
	{ id = "r190", kind = "title", key = "title.r190", source = { kind = "recordR", value = 190 } },
	{ id = "r200", kind = "title", key = "title.r200", source = { kind = "recordR", value = 200 } },
	{ id = "r210", kind = "title", key = "title.r210", source = { kind = "recordR", value = 210 } },
	{ id = "r220", kind = "title", key = "title.r220", source = { kind = "recordR", value = 220 } },
	{ id = "r230", kind = "title", key = "title.r230", source = { kind = "recordR", value = 230 } },
	{ id = "r240", kind = "title", key = "title.r240", source = { kind = "recordR", value = 240 } },
	{ id = "r250", kind = "title", key = "title.r250", source = { kind = "recordR", value = 250 } },
	{ id = "r260", kind = "title", key = "title.r260", source = { kind = "recordR", value = 260 } },
	{ id = "r270", kind = "title", key = "title.r270", source = { kind = "recordR", value = 270 } },
	{ id = "r280", kind = "title", key = "title.r280", source = { kind = "recordR", value = 280 } },
	{ id = "r290", kind = "title", key = "title.r290", source = { kind = "recordR", value = 290 } },
	{ id = "r300", kind = "title", key = "title.r300", source = { kind = "recordR", value = 300 } },
	{ id = "r310", kind = "title", key = "title.r310", source = { kind = "recordR", value = 310 } },
	{ id = "r320", kind = "title", key = "title.r320", source = { kind = "recordR", value = 320 } },
	{ id = "r330", kind = "title", key = "title.r330", source = { kind = "recordR", value = 330 } },
	{ id = "r340", kind = "title", key = "title.r340", source = { kind = "recordR", value = 340 } },
	{ id = "r350", kind = "title", key = "title.r350", source = { kind = "recordR", value = 350 } },
	{ id = "r360", kind = "title", key = "title.r360", source = { kind = "recordR", value = 360 } },
	{ id = "r370", kind = "title", key = "title.r370", source = { kind = "recordR", value = 370 } },
	{ id = "r380", kind = "title", key = "title.r380", source = { kind = "recordR", value = 380 } },
	{ id = "r390", kind = "title", key = "title.r390", source = { kind = "recordR", value = 390 } },
	{ id = "r400", kind = "title", key = "title.r400", source = { kind = "recordR", value = 400 } },
	{ id = "marshmallow", kind = "theme", key = "skin.marshmallow", source = { kind = "recordR", value = 1 } },
	{ id = "caramel", kind = "theme", key = "skin.caramel", source = { kind = "recordR", value = 3 } },
	{ id = "icedMint", kind = "theme", key = "skin.icedMint", source = { kind = "recordR", value = 5 } },
	{ id = "lighthouse", kind = "theme", key = "skin.lighthouse", source = { kind = "recordR", value = 10 } },
	{ id = "sugarGlacier", kind = "theme", key = "skin.sugarGlacier", source = { kind = "recordR", value = 12 } },
	{ id = "neon", kind = "theme", key = "skin.neon", source = { kind = "recordR", value = 15 } },
	{ id = "sugarCosmos", kind = "theme", key = "skin.sugarCosmos", source = { kind = "recordR", value = 17 } },
	{ id = "royal", kind = "theme", key = "skin.royal", source = { kind = "recordR", value = 20 } },
	{ id = "cloud", kind = "theme", key = "skin.cloud", source = { kind = "ascend", value = 1 } },
	{ id = "aurora", kind = "theme", key = "skin.aurora", source = { kind = "ascend", value = 3 } },
	{ id = "celestial", kind = "theme", key = "skin.celestial", source = { kind = "ascend", value = 5 } },
}
-- stylua: ignore end

return Cosmetics
