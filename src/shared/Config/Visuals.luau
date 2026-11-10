--!strict
-- Ce qui se VOIT dans le jeu complet (GDD v2.0 §4.29, §4.27, §5.6, §11.5) : une table par Record R
-- (déblocage nommé de l'aperçu + éléments du ranch), paliers d'aspect des familles, visages, yeux,
-- palettes du spectacle, ciel des Ascensions, halo. Contrat v2.0 (architecte, docs/04 §27.6).
-- Données seulement : RanchRenderer, l'aperçu du Grand Splorch et QuestService lisent cette table,
-- jamais une copie. Lu seulement quand l'interrupteur correspondant est ouvert (RecordR, RanchTiers,
-- Personalities, JellyAscend), sauf Eyes / EyeChoice que Render/SquishyBuilder lit toujours (la
-- version A donne exactement les recettes de la v1.3). Identifiants définitifs (ajout seulement).
-- Contract_unlocks.spec : chaque Record R de 1 à 20 a au moins un déblocage nommé ET un changement
-- visible dans le ranch ; chaque clé de texte existe en EN et en FR.

-- vars.name (quand il existe) est une CLÉ de texte, traduite avant d'être posée dans key
export type UnlockTile = { key: string, vars: { [string]: any }? }
export type RecordRow = {
	unlocks: { UnlockTile }, -- tuiles « Tu gagnes » de l'aperçu (clés de texte)
	ranch: { string }, -- éléments du ranch qui changent (identifiants de RanchRenderer)
}

local Visuals = {}

-- stylua: ignore start
-- Table du GDD §4.29 : RecordTable[R] (premier passage du Record R)
Visuals.RecordTable = {
	[1] = { unlocks = { { key = "unlock.workshop" }, { key = "unlock.gloves" }, { key = "panel.splorch.unlock.family.axolo" }, { key = "unlock.splorchGift" }, { key = "unlock.skin", vars = { name = "skin.marshmallow" } } },
		ranch = { "tier1.pompomArch", "vat.ring2", "vat.nozzle1" } },
	[2] = { unlocks = { { key = "unlock.offeredPen" }, { key = "unlock.helper", vars = { name = "helper.name.pip" } }, { key = "unlock.school" }, { key = "unlock.item", vars = { name = "v2cosmetic.saddle.confetti" } } },
		ranch = { "pot.silver", "pen.cushion", "vat.ring3", "vat.nozzle2", "helper.house" } },
	[3] = { unlocks = { { key = "panel.splorch.unlock.family.bunny" }, { key = "panel.splorch.unlock.bestFriend.2" }, { key = "panel.splorch.unlock.pad.cozyBed" }, { key = "unlock.skin", vars = { name = "skin.caramel" } } },
		ranch = { "tier2.candyTower", "vat.ring4", "vat.nozzle3" } },
	[4] = { unlocks = { { key = "unlock.helper", vars = { name = "helper.name.pop" } }, { key = "unlock.item", vars = { name = "v2cosmetic.emote.splorch" } } },
		ranch = { "vat.rainbowStirrer", "vat.ring5", "vat.nozzle4" } },
	[5] = { unlocks = { { key = "panel.splorch.unlock.family.spiky" }, { key = "panel.splorch.unlock.title.splorch_star" }, { key = "unlock.skin", vars = { name = "skin.icedMint" } } },
		ranch = { "tier3.jellyBalcony", "vat.nozzle5", "vat.ring6" } },
	[6] = { unlocks = { { key = "unlock.offeredPen" }, { key = "unlock.helper", vars = { name = "helper.name.pim" } }, { key = "unlock.monument", vars = { n = 1 } }, { key = "unlock.starMat", vars = { n = 13 } }, { key = "unlock.item", vars = { name = "v2cosmetic.trail.confetti" } } },
		ranch = { "pot.gold", "pen.cushion", "vat.ring7" } },
	[7] = { unlocks = { { key = "unlock.goldenVat" }, { key = "unlock.starMat", vars = { n = 14 } }, { key = "unlock.item", vars = { name = "v2cosmetic.outfit.partyHat" } } },
		ranch = { "vat.golden" } },
	[8] = { unlocks = { { key = "unlock.keptDecor", vars = { n = 3 } }, { key = "unlock.helper", vars = { name = "helper.name.pom" } }, { key = "unlock.monument", vars = { n = 2 } }, { key = "unlock.starMat", vars = { n = 15 } } },
		ranch = { "decor.pennants3" } },
	[9] = { unlocks = { { key = "unlock.starMat", vars = { n = 16 } }, { key = "unlock.item", vars = { name = "palette.fireworks" } }, { key = "unlock.item", vars = { name = "v2cosmetic.flag.nine" } } },
		ranch = { "pool.fountain" } },
	[10] = { unlocks = { { key = "panel.splorch.unlock.bestFriend.3" }, { key = "panel.splorch.unlock.title.splorch_legend" }, { key = "unlock.starMat", vars = { n = 17 } }, { key = "unlock.monument", vars = { n = 3 } }, { key = "unlock.skin", vars = { name = "skin.lighthouse" } } },
		ranch = { "tier4.jellyLighthouse" } },
	[11] = { unlocks = { { key = "unlock.offeredPen" }, { key = "unlock.item", vars = { name = "v2cosmetic.saddle.goldenJelly" } } },
		ranch = { "pen.starCushions", "pen.cushion" } },
	[12] = { unlocks = { { key = "unlock.helper", vars = { name = "helper.name.puff" } }, { key = "unlock.monument", vars = { n = 4 } }, { key = "unlock.plumeRow" }, { key = "unlock.skin", vars = { name = "skin.sugarGlacier" } } },
		ranch = { "fence.lanterns8" } },
	[13] = { unlocks = { { key = "unlock.item", vars = { name = "v2cosmetic.emote.wave" } }, { key = "unlock.item", vars = { name = "v2cosmetic.trail.jellyArc" } } },
		ranch = { "gate.rainbow" } },
	[14] = { unlocks = { { key = "unlock.keptDecor", vars = { n = 6 } }, { key = "unlock.monument", vars = { n = 5 } } },
		ranch = { "decor.pennants6" } },
	[15] = { unlocks = { { key = "panel.splorch.unlock.title.splorch_hero" }, { key = "unlock.jellyAscend" }, { key = "unlock.skin", vars = { name = "skin.neon" } } },
		ranch = { "tier5.neonDome", "observatory.beam" } },
	[16] = { unlocks = { { key = "unlock.offeredPen" }, { key = "unlock.monument", vars = { n = 6 } }, { key = "unlock.item", vars = { name = "v2cosmetic.outfit.starGlasses" } } },
		ranch = { "pot.crystal", "pen.cushion" } },
	[17] = { unlocks = { { key = "unlock.item", vars = { name = "v2cosmetic.saddle.cosmos" } }, { key = "unlock.skin", vars = { name = "skin.sugarCosmos" } } },
		ranch = { "geyser" } },
	[18] = { unlocks = { { key = "unlock.monument", vars = { n = 7 } } },
		ranch = { "frame.golden" } },
	[19] = { unlocks = { { key = "unlock.item", vars = { name = "v2cosmetic.emote.confettiCrown" } }, { key = "unlock.item", vars = { name = "v2cosmetic.flag.splorchRoyal" } } },
		ranch = { "shelf.golden" } },
	[20] = { unlocks = { { key = "panel.splorch.unlock.title.jelly_titan" }, { key = "unlock.monument", vars = { n = 8 } }, { key = "unlock.item", vars = { name = "v2cosmetic.saddle.titan" } }, { key = "unlock.skin", vars = { name = "skin.royal" } } },
		ranch = { "tier6.floatingCrown" } },
} :: { [number]: RecordRow }
-- stylua: ignore end

-- Au-delà de 20 : prime de record (+10 Confettis au premier passage), Monuments 9 et 10 (22, 24),
-- titres (Cosmetics.ListV2), étoiles de la couronne (25, 30, 35, 40), couronne arc-en-ciel (50)
Visuals.CrownStarsAt = { 25, 30, 35, 40 }
Visuals.RainbowCrownAt = 50

-- Paliers d'aspect des familles (niveau à partir duquel le palier s'applique ; GDD §4.6, §11.5)
Visuals.Tiers = {
	snack = { 1, 4, 7, 10, 13, 17 }, -- 6 paliers du Tapis (13 et 17 : Tapis Étoilé)
	gloves = { 1, 5, 10, 15, 20, 25, 30, 35, 40 }, -- 9 paliers des Gants (couleur des éclaboussures)
	school = { 1, 5, 10, 15, 20 }, -- 5 tabliers des Plopettes
	pens = { 0, 6, 14 }, -- 3 aspects de l'Enclos (4-9, 10-17, 18-24 places)
}

-- Paliers du ranch (bestR) : arche, tour, balcon, phare, dôme, couronne
Visuals.RanchTiersAt = { 1, 3, 5, 10, 15, 20 }

-- Visages (GDD §5.6 ; lot B5, D5 : la liste suit le GDD) : Content (défaut), Ravi, Surpris, Endormi,
-- Étoilé, Boudeur. Dessinés par Render/SquishyBuilder.setFace avec les pièces existantes.
Visuals.Faces = { "happy", "delighted", "surprised", "sleepy", "starry", "sulky" }

-- Yeux « bébé » (GDD §5.6, test M14 ; lot B5, D5) : taille des yeux et hauteur de leur centre au-dessus
-- du milieu du corps, en diamètres du corps (× D). Trois versions à comparer sur une télé :
-- A = la v1.3 (recettes inchangées), B et C = yeux plus gros et plus bas. EyeChoice : la version
-- dessinée (une seule constante à changer pour le test ; SquishyBuilder la lit à chaque recette).
export type EyeVersion = { size: number, height: number }
Visuals.Eyes = {
	A = { size = 0.22, height = 0.12 },
	B = { size = 0.26, height = 0.04 },
	C = { size = 0.30, height = 0.00 },
} :: { [string]: EyeVersion }
Visuals.EyeChoice = "A"

-- Palettes du spectacle du Grand Splorch : 6 de l'Atelier, 1 du Record R 9, 1 de la semaine
Visuals.Palettes = { "candy", "mint", "lavender", "rainbow", "softNight", "icing", "fireworks", "peach" }

-- Ciel des Ascensions : A1 à A10 nommés (sky.1 … sky.10), puis une étoile de plus par Ascension
-- jusqu'à A20 (sky.stars)
Visuals.SkyNamed = 10
Visuals.SkyMaxStars = 20

-- Halo : 1 à 5 gouttes (le nombre porte l'information, lisible sans les couleurs)
Visuals.Halo = { "mint", "sky", "lilac", "gold", "rainbow" }

-- Une couleur par famille de suffixes des grands nombres (GDD v2.0 §4.2, critique M11), la même
-- partout (montants du HUD, de l'écran Améliorations, des aperçus) : de l'exposant `from` à
-- l'exposant `to` compris (K = 3 … Tg = 93) ; en dessous de 1e3, la couleur de K-M. Lu par le
-- formateur du client (UI/Format, paquet B1) quand UpgradesScreen est ouvert.
export type SuffixColor = { from: number, to: number, color: Color3 }
Visuals.SuffixColors = {
	{ from = 3, to = 6, color = Color3.fromRGB(255, 255, 255) }, -- K-M : blanc
	{ from = 9, to = 12, color = Color3.fromRGB(255, 215, 90) }, -- B-T : or
	{ from = 15, to = 18, color = Color3.fromRGB(255, 150, 200) }, -- Qa-Qi : rose
	{ from = 21, to = 33, color = Color3.fromRGB(120, 230, 255) }, -- Sx à Dc : cyan
	{ from = 36, to = 60, color = Color3.fromRGB(140, 235, 150) }, -- Ud à Nvd : vert
	{ from = 63, to = 93, color = Color3.fromRGB(205, 175, 255) }, -- Vg à Tg : lilas
} :: { SuffixColor }

return Visuals
