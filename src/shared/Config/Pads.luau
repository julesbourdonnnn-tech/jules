--!strict
-- Dalles d'achat du ranch et ordre de construction (GDD §4.6, §3, §11.2). Contrat (architecte).
-- Les PRIX vivent dans Config/Balance.Tiles (leviers de la simulation) ; ce module donne l'ordre
-- d'apparition, les règles de découverte, les 18 décorations et les constructions gratuites.
-- Les POSITIONS (prises de dalles, emplacements de décoration) viennent du module pur
-- Logic/WorldLayout (padSocket, decorSlot), jamais d'une recherche dans le workspace.
--
-- Une dalle est « sur » le joueur quand sa position validée est à Balance.Tiles.EnterRadius de son
-- centre ; « sortie » au-delà de ExitRadius (ZoneRules) ; un achat par entrée (RanchService.step).
-- Une dalle trop chère ne refuse jamais : anneau qui se remplit (« 1,2K / 3K »), son Bump.

export type TileKey = "snack" | "decor" | "pens" | "cozyBed"

export type PadDef = {
	key: TileKey,
	socket: number, -- prise de dalle (1 … 4, de gauche à droite vue du portail) : WorldLayout.padSocket
	icon: string, -- icône dessinée en formes simples (Render) : "mat" | "decor" | "pen" | "bed"
	seenBit: number, -- bit de profile.tiles.seen (dalle déjà découverte : reste visible après un Grand Splorch)
	-- Découverte (première apparition) :
	revealStep: number, -- étape d'accueil atteinte (ou accueil fini) à partir de laquelle la dalle peut apparaître
	rule: "always" | "snackBought" | "pensFull" | "rMin", -- condition de découverte
	relightStep: number?, -- pendant l'accueil, une dalle déjà achetée une fois ne se rallume qu'à cette étape
}

local Pads = {}

Pads.Defs = {
	snack = {
		key = "snack",
		socket = 1,
		icon = "mat",
		seenBit = 1,
		revealStep = 2,
		rule = "always",
		relightStep = 6,
	},
	decor = { key = "decor", socket = 2, icon = "decor", seenBit = 2, revealStep = 6, rule = "snackBought" },
	pens = { key = "pens", socket = 3, icon = "pen", seenBit = 4, revealStep = 6, rule = "pensFull" },
	cozyBed = { key = "cozyBed", socket = 4, icon = "bed", seenBit = 8, revealStep = 6, rule = "rMin" },
} :: { [TileKey]: PadDef }

-- Ordre des prises (gauche → droite)
Pads.Order = { "snack", "decor", "pens", "cozyBed" } :: { TileKey }

-- Constructions gratuites (GDD §4.6 : jamais achetées, jamais remises à zéro), liées à l'accueil.
-- Un joueur dont l'accueil est fini (ou a dépassé l'étape) les a toujours.
Pads.FreeBuilds = {
	vat = { atStep = 4 }, -- la Cuve se construit toute seule (≈ 0:40)
	pool = { atStep = 5 }, -- le Bassin est là pour la leçon de fusion (≈ 1:00)
	fountain = { atStep = 1 }, -- Fontaine de Gelée (devant le portail)
	pot = { atStep = 1 },
	bowl = { atStep = 1 },
	shelf = { atStep = 1 }, -- Étagère à trophées
}

-- Les 18 décorations, dans l'ordre d'apparition (une fois chacune, +5 % de revenu chacune ;
-- Balance.Income.DecorBonus). Le niveau `tiles.decor` = nombre de décorations construites : la
-- décoration n° k est construite quand tiles.decor ≥ k. Texte « decor.<key> » (EN/FR).
Pads.Decor = {
	"bouncy_fence",
	"candy_lamp",
	"jelly_flowers",
	"gumdrop_path",
	"cloud_bench",
	"lollipop_trees",
	"marshmallow_rocks",
	"bubble_pond",
	"sprinkle_arch",
	"pudding_hut",
	"rainbow_kite",
	"star_windmill",
	"jellybean_swing",
	"cupcake_fountain",
	"gummy_bridge",
	"cotton_candy_tree",
	"donut_carousel",
	"moon_telescope",
} :: { string }

-- Tapis à Goûter : le tapis change de couleur et de motif à chaque niveau (rendu, GDD §11.2)
Pads.SnackLooks = 13 -- niveaux 0 à 12

-- Emplacement réservé (janvier) : Gelée lente à côté de la Cuve (GDD §17.2)
Pads.ReservedSlowJellySocket = 5

return Pads
