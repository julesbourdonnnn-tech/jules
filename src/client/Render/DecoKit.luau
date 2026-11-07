--!strict
-- DecoKit (lot B4, étape 4 ; GDD v2.0 §11.5 « Déco perso », Annexe B.1 ; décision D15 du plan B4).
-- Dessins PURS des 40 objets de Déco perso (Cosmetics.DecoPerso, n = numéro définitif) en lignes
-- compactes de Render/RanchKit, posés sur WorldLayout.decoPersoSlot(slot, i) (tournés vers le milieu
-- des enclos) : 10 pièces au plus par objet ; un petit objet « P » tient dans un cylindre de 2,5 studs
-- de diamètre et 2,5 de haut, un grand « G » dans 4,5 × 4,5 (emprises WorldLayout DecoSmallRadius,
-- DecoLargeRadius ; DecoKit.spec le vérifie pour les 40). Détail réduit : seuls les grands objets, en
-- une silhouette d'une pièce. Le Fanion à ton nom ne montre aucun texte (le panneau nomme déjà le
-- ranch) ; aucun objet ne dessine de lettres (règle des textes : tout texte passe par Strings).
-- Repère d'un dessin : origine au sol au centre de l'emplacement, Y vers le haut, −Z vers l'avant.
-- Rien n'est créé ici ; jamais d'erreur (numéro inconnu : aucune pièce).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Cosmetics = require(Shared.Config.Cosmetics)
local WorldLayout = require(Shared.Logic.WorldLayout)

local RanchKit = require(script.Parent.RanchKit)

local DecoKit = {}

type Row = RanchKit.Row
type Spec = RanchKit.Spec
type Design = { rows: { Row }, far: Row? }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local P: { [string]: Color3 } = {
	white = rgb(255, 250, 245),
	cream = rgb(255, 238, 214),
	pink = rgb(255, 160, 196),
	rose = rgb(255, 110, 155),
	blush = rgb(255, 205, 222),
	red = rgb(236, 78, 92),
	jelly = rgb(255, 120, 200),
	lemon = rgb(255, 228, 120),
	mint = rgb(150, 232, 200),
	sky = rgb(140, 205, 255),
	lilac = rgb(200, 168, 255),
	peach = rgb(255, 196, 160),
	gold = rgb(255, 204, 84),
	caramel = rgb(226, 152, 82),
	choco = rgb(124, 78, 56),
	wood = rgb(214, 160, 110),
	grey = rgb(192, 192, 208),
	stone = rgb(222, 206, 218),
	dark = rgb(70, 55, 75),
	leaf = rgb(92, 180, 104),
	aqua = rgb(120, 220, 255),
	sand = rgb(245, 225, 182),
	orange = rgb(255, 168, 80),
	syrup = rgb(255, 170, 60),
}
DecoKit.PALETTE = P

DecoKit.MAX_PARTS = 10
DecoKit.SMALL = 2.5 -- diamètre et hauteur d'un objet « P »
DecoKit.LARGE = 4.5 -- diamètre et hauteur d'un objet « G »

local seg = RanchKit.segment

-- Dessins par identifiant (Cosmetics.DecoPerso[n].id)
local BY_ID: { [string]: Design } = {}

-- ============================ petits objets « P » (≤ 2,5 × 2,5) ============================

BY_ID.namePennant = {
	rows = {
		{ "c", 0, 0.1, 0, 1.2, 0.2, 1.2, "cream" },
		{ "c", 0, 1.2, 0, 0.12, 2.2, 0.12, "white" },
		{ "b", 0.45, 1.95, 0, 0.9, 0.6, 0.06, "jelly" },
		{ "s", 0, 2.35, 0, 0.25, 0.25, 0.25, "gold", "n" },
	},
}
BY_ID.plopBench = {
	rows = {
		{ "b", 0, 0.75, 0, 2, 0.2, 0.7, "wood" },
		{ "b", -0.85, 0.325, -0.25, 0.15, 0.65, 0.15, "choco" },
		{ "b", 0.85, 0.325, -0.25, 0.15, 0.65, 0.15, "choco" },
		{ "b", -0.85, 0.325, 0.25, 0.15, 0.65, 0.15, "choco" },
		{ "b", 0.85, 0.325, 0.25, 0.15, 0.65, 0.15, "choco" },
		{ "b", 0, 1.25, 0.3, 2, 0.6, 0.12, "pink" },
		{ "b", -0.94, 1, 0, 0.12, 0.3, 0.6, "wood" },
		{ "b", 0.94, 1, 0, 0.12, 0.3, 0.6, "wood" },
		{ "b", 0, 0.9, -0.05, 0.8, 0.1, 0.5, "jelly" },
	},
}
BY_ID.pinkLantern = {
	rows = {
		{ "c", 0, 0.1, 0, 0.8, 0.2, 0.8, "cream" },
		{ "c", 0, 0.85, 0, 0.18, 1.5, 0.18, "white" },
		{ "s", 0, 1.95, 0, 0.9, 0.9, 0.9, "pink", "n" },
		{ "c", 0, 2.43, 0, 0.5, 0.1, 0.5, "gold", "f" },
	},
}
BY_ID.wateringCan = {
	rows = {
		{ "c", 0, 0.5, 0, 1, 1, 1, "mint" },
		{ "c", 0, 1.05, 0, 0.8, 0.1, 0.8, "white" },
		{ "b", -0.7, 0.75, 0, 0.7, 0.15, 0.15, "mint", nil, 0, 0, -35 },
		{ "c", -1.0, 0.95, 0, 0.25, 0.1, 0.25, "white" },
		{ "b", 0.55, 0.8, 0, 0.12, 0.7, 0.12, "mint" },
		{ "b", 0.32, 1.15, 0, 0.5, 0.12, 0.12, "mint" },
	},
}
BY_ID.mochiStatue = {
	rows = {
		{ "b", 0, 0.3, 0, 1.4, 0.6, 1.4, "white" },
		{ "s", 0, 1.3, 0, 1.4, 1.4, 1.4, "blush" },
		{ "s", -0.25, 1.45, -0.62, 0.15, 0.15, 0.15, "dark" },
		{ "s", 0.25, 1.45, -0.62, 0.15, 0.15, 0.15, "dark" },
		{ "s", -0.4, 1.25, -0.52, 0.18, 0.18, 0.18, "rose" },
		{ "s", 0.4, 1.25, -0.52, 0.18, 0.18, 0.18, "rose" },
		{ "b", 0, 2.05, 0, 0.4, 0.08, 0.25, "leaf", nil, 0, 0, 20 },
	},
}
BY_ID.plopBowl = {
	rows = {
		{ "c", 0, 0.25, 0, 1.6, 0.5, 1.6, "pink" },
		{ "c", 0, 0.27, 0, 1.3, 0.5, 1.3, "cream" },
		{ "s", -0.3, 0.55, 0, 0.35, 0.35, 0.35, "caramel" },
		{ "s", 0.3, 0.55, 0.1, 0.35, 0.35, 0.35, "caramel" },
		{ "s", 0, 0.6, -0.25, 0.35, 0.35, 0.35, "choco" },
	},
}
BY_ID.morningBell = {
	rows = {
		{ "b", 0, 0.05, 0, 1.8, 0.1, 0.5, "cream" },
		{ "b", -0.7, 1.15, 0, 0.15, 2.2, 0.15, "wood" },
		{ "b", 0.7, 1.15, 0, 0.15, 2.2, 0.15, "wood" },
		{ "b", 0, 2.2, 0, 1.6, 0.15, 0.15, "wood" },
		{ "c", 0, 1.7, 0, 0.8, 0.8, 0.8, "gold", "f" },
		{ "c", 0, 1.28, 0, 1, 0.12, 1, "gold", "f" },
		{ "s", 0, 1.12, 0, 0.25, 0.25, 0.25, "gold" },
	},
}
BY_ID.toyBox = {
	rows = {
		{ "b", 0, 0.45, 0, 1.6, 0.9, 1.1, "sky" },
		{ "b", 0, 0.95, 0.1, 1.7, 0.12, 1.2, "lilac", nil, -15, 0, 0 },
		{ "s", 0.35, 1.15, -0.15, 0.45, 0.45, 0.45, "red" },
		{ "b", -0.3, 1.1, -0.2, 0.35, 0.35, 0.1, "lemon", "n", 0, 0, 45 },
		{ "b", 0, 0.45, -0.56, 0.2, 0.9, 0.02, "pink" },
	},
}
BY_ID.plushMoon = {
	rows = {
		{ "b", 0, 0.1, 0, 1.6, 0.2, 1.2, "lilac" },
		{ "s", 0, 0.9, 0, 1.6, 1.6, 1.6, "lemon" },
		{ "c", 0, 1.85, 0, 0.9, 0.5, 0.9, "sky" },
		{ "s", 0, 2.25, 0, 0.3, 0.3, 0.3, "white" },
		{ "b", -0.3, 1, -0.76, 0.3, 0.06, 0.05, "dark" },
		{ "b", 0.3, 1, -0.76, 0.3, 0.06, 0.05, "dark" },
	},
}
BY_ID.ribbonChest = {
	rows = {
		{ "b", 0, 0.4, 0, 1.6, 0.8, 1, "wood" },
		{ "b", 0, 0.92, 0, 1.65, 0.25, 1.05, "caramel" },
		{ "b", 0, 0.55, 0, 0.2, 1.1, 1.07, "jelly" },
		{ "s", -0.18, 1.12, 0, 0.3, 0.3, 0.3, "jelly" },
		{ "s", 0.18, 1.12, 0, 0.3, 0.3, 0.3, "jelly" },
		{ "b", 0, 0.75, -0.53, 0.2, 0.2, 0.05, "gold", "f" },
	},
}
BY_ID.workbench = {
	rows = {
		{ "b", 0, 0.9, 0, 1.9, 0.15, 0.8, "wood" },
		{ "b", -0.8, 0.41, -0.3, 0.15, 0.83, 0.15, "choco" },
		{ "b", 0.8, 0.41, -0.3, 0.15, 0.83, 0.15, "choco" },
		{ "b", -0.8, 0.41, 0.3, 0.15, 0.83, 0.15, "choco" },
		{ "b", 0.8, 0.41, 0.3, 0.15, 0.83, 0.15, "choco" },
		{ "b", 0.3, 1.05, -0.1, 0.4, 0.15, 0.15, "grey" },
		{ "b", 0.3, 1.02, 0.12, 0.08, 0.08, 0.4, "wood" },
		{ "c", -0.5, 1.12, 0, 0.3, 0.3, 0.3, "jelly", "n" },
	},
}
BY_ID.mushroom = {
	rows = {
		{ "c", 0, 0.5, 0, 0.6, 1, 0.6, "cream" },
		{ "c", 0, 1.2, 0, 1.8, 0.4, 1.8, "red" },
		{ "s", 0, 1.45, 0, 1.4, 1.4, 1.4, "red" },
		{ "s", -0.35, 2.0, -0.3, 0.25, 0.25, 0.25, "white" },
		{ "s", 0.4, 1.95, -0.2, 0.25, 0.25, 0.25, "white" },
		{ "s", 0, 2.1, 0.3, 0.25, 0.25, 0.25, "white" },
	},
}
BY_ID.candyBucket = {
	rows = {
		{ "c", 0, 0.45, 0, 1.2, 0.9, 1.2, "sky" },
		{ "c", 0, 0.92, 0, 1.3, 0.08, 1.3, "white" },
		{ "b", -0.6, 1.1, 0, 0.08, 0.4, 0.08, "grey" },
		{ "b", 0.6, 1.1, 0, 0.08, 0.4, 0.08, "grey" },
		{ "b", 0, 1.3, 0, 1.2, 0.08, 0.08, "grey" },
		{ "s", -0.25, 1.0, 0, 0.35, 0.35, 0.35, "jelly" },
		{ "s", 0.25, 1.0, 0.1, 0.35, 0.35, 0.35, "mint" },
		{ "s", 0, 1.05, -0.25, 0.35, 0.35, 0.35, "lemon" },
	},
}
BY_ID.birdhouse = {
	rows = {
		{ "c", 0, 0.05, 0, 0.6, 0.1, 0.6, "cream" },
		{ "c", 0, 0.8, 0, 0.15, 1.6, 0.15, "wood" },
		{ "b", 0, 1.75, 0, 0.8, 0.7, 0.8, "peach" },
		{ "b", 0, 2.2, -0.2, 0.95, 0.08, 0.55, "rose", nil, -35, 0, 0 },
		{ "b", 0, 2.2, 0.2, 0.95, 0.08, 0.55, "rose", nil, 35, 0, 0 },
		{ "s", 0, 1.8, -0.4, 0.22, 0.22, 0.22, "dark" },
		{ "b", 0, 1.6, -0.5, 0.05, 0.05, 0.25, "wood" },
	},
}
BY_ID.hiSign = {
	rows = {
		{ "c", 0, 0.05, 0, 0.7, 0.1, 0.7, "cream" },
		{ "b", 0, 0.7, 0, 0.15, 1.4, 0.15, "wood" },
		{ "b", 0, 1.65, -0.05, 1.8, 0.8, 0.1, "cream" },
		{ "s", -0.12, 1.75, -0.12, 0.3, 0.3, 0.3, "rose" },
		{ "s", 0.12, 1.75, -0.12, 0.3, 0.3, 0.3, "rose" },
		{ "b", 0, 1.58, -0.12, 0.3, 0.3, 0.05, "rose", nil, 0, 0, 45 },
	},
}
BY_ID.puddingStool = {
	rows = {
		{ "c", 0, 0.35, 0, 1.4, 0.7, 1.4, "cream" },
		{ "c", 0, 0.78, 0, 1.3, 0.16, 1.3, "caramel" },
		{ "b", 0.55, 0.62, -0.3, 0.12, 0.3, 0.1, "caramel" },
		{ "s", 0, 1, 0, 0.35, 0.35, 0.35, "red" },
		{ "b", 0.05, 1.25, 0, 0.04, 0.25, 0.04, "leaf", nil, 0, 0, -15 },
	},
}
BY_ID.mintLantern = {
	rows = {
		{ "c", 0, 0.1, 0, 0.8, 0.2, 0.8, "cream" },
		{ "c", 0, 0.85, 0, 0.18, 1.5, 0.18, "white" },
		{ "s", 0, 1.95, 0, 0.9, 0.9, 0.9, "mint", "n" },
		{ "c", 0, 2.43, 0, 0.5, 0.1, 0.5, "white" },
	},
}
BY_ID.wishingWell = {
	rows = {
		{ "c", 0, 0.4, 0, 1.6, 0.8, 1.6, "stone" },
		{ "c", 0, 0.81, 0, 1.3, 0.04, 1.3, "aqua", "n" },
		{ "b", -0.7, 1.25, 0, 0.12, 0.9, 0.12, "wood" },
		{ "b", 0.7, 1.25, 0, 0.12, 0.9, 0.12, "wood" },
		{ "b", 0, 1.95, -0.3, 1.7, 0.08, 0.7, "rose", nil, -30, 0, 0 },
		{ "b", 0, 1.95, 0.3, 1.7, 0.08, 0.7, "rose", nil, 30, 0, 0 },
		{ "c", 0, 1.3, 0, 0.3, 0.3, 0.3, "wood" },
		{ "b", 0, 1.62, 0, 0.03, 0.35, 0.03, "cream" },
	},
}
do
	local rows: { Row } = {
		{ "c", 0, 0.8, 0, 0.9, 1.6, 0.9, "cream" },
		{ "c", 0, 1.75, 0, 0.7, 0.3, 0.7, "caramel" },
		{ "s", 0, 1.4, -0.5, 0.25, 0.25, 0.25, "jelly" },
	}
	for _, deg in { 45, 135, 225, 315 } do
		local a = math.rad(deg)
		table.insert(rows, {
			"b",
			0.5 * math.cos(a),
			1.4 + 0.5 * math.sin(a),
			-0.55,
			0.18,
			0.9,
			0.04,
			"white",
			nil,
			0,
			0,
			deg - 90,
		})
	end
	BY_ID.miniWindmill = { rows = rows }
end
BY_ID.syrupBarrel = {
	rows = {
		{ "c", 0, 0.6, 0, 1.2, 1.2, 1.2, "wood" },
		{ "c", 0, 0.25, 0, 1.25, 0.08, 1.25, "grey" },
		{ "c", 0, 0.95, 0, 1.25, 0.08, 1.25, "grey" },
		{ "c", 0, 1.22, 0, 1.1, 0.04, 1.1, "caramel" },
		{ "b", 0, 0.4, -0.66, 0.12, 0.12, 0.2, "grey" },
		{ "s", 0, 0.25, -0.7, 0.18, 0.18, 0.18, "syrup", "n" },
	},
}
BY_ID.musicBox = {
	rows = {
		{ "b", 0, 0.35, 0, 1.2, 0.7, 0.9, "lilac" },
		{ "b", 0, 0.95, 0.42, 1.2, 0.6, 0.06, "pink", nil, -10, 0, 0 },
		{ "c", 0, 0.85, 0, 0.12, 0.3, 0.12, "white" },
		{ "s", 0, 1.1, 0, 0.25, 0.25, 0.25, "blush" },
		{ "b", 0.65, 0.4, 0, 0.1, 0.1, 0.1, "gold", "f" },
		{ "s", -0.3, 1.5, -0.2, 0.15, 0.15, 0.15, "lemon", "n" },
		{ "s", 0.3, 1.65, -0.2, 0.15, 0.15, 0.15, "lemon", "n" },
	},
}
BY_ID.rockingBoat = {
	rows = {
		{ "b", 0, 0.5, 0, 1.8, 0.5, 0.7, "sky" },
		{ "b", 0, 0.12, -0.25, 1.8, 0.12, 0.1, "wood" },
		{ "b", 0, 0.12, 0.25, 1.8, 0.12, 0.1, "wood" },
		{ "b", 0, 0.8, 0, 0.5, 0.1, 0.6, "white" },
		{ "c", 0, 1.4, 0, 0.08, 1.4, 0.08, "wood" },
		{ "b", 0.3, 1.45, 0, 0.55, 0.9, 0.03, "pink" },
		{ "b", 0.15, 2.15, 0, 0.3, 0.15, 0.02, "jelly" },
	},
}
BY_ID.pipStatue = {
	rows = {
		{ "c", 0, 0.25, 0, 1.2, 0.5, 1.2, "white" },
		{ "s", 0, 1.05, 0, 1.1, 1.1, 1.1, "mint" },
		{ "c", 0, 1.75, 0, 0.6, 0.3, 0.6, "lemon" },
		{ "s", -0.2, 1.2, -0.48, 0.14, 0.14, 0.14, "dark" },
		{ "s", 0.2, 1.2, -0.48, 0.14, 0.14, 0.14, "dark" },
		{ "b", 0, 0.9, -0.5, 0.5, 0.4, 0.05, "white" },
	},
}
BY_ID.cuckooClock = {
	rows = {
		{ "b", 0, 0.6, 0, 0.15, 1.2, 0.15, "wood" },
		{ "b", 0, 1.6, 0, 1, 0.9, 0.6, "wood" },
		{ "b", -0.28, 2.18, 0, 0.65, 0.08, 0.7, "rose", nil, 0, 0, 35 },
		{ "b", 0.28, 2.18, 0, 0.65, 0.08, 0.7, "rose", nil, 0, 0, -35 },
		{ "x", 0, 1.65, -0.32, 0.04, 0.6, 0, "white", nil, 0, 90, 0 },
		{ "b", 0, 1.72, -0.35, 0.04, 0.2, 0.02, "dark" },
		{ "b", 0, 0.95, -0.32, 0.04, 0.4, 0.02, "gold" },
		{ "s", 0, 0.75, -0.33, 0.15, 0.15, 0.15, "gold", "f" },
	},
}

-- ============================ grands objets « G » (≤ 4,5 × 4,5) ============================

BY_ID.goldFountain = {
	rows = {
		{ "c", 0, 0.3, 0, 4.2, 0.6, 4.2, "gold", "f" },
		{ "c", 0, 0.62, 0, 3.6, 0.06, 3.6, "aqua", "n" },
		{ "c", 0, 1.4, 0, 0.6, 1.6, 0.6, "gold", "f" },
		{ "c", 0, 2.3, 0, 1.8, 0.3, 1.8, "gold", "f" },
		{ "c", 0, 2.47, 0, 1.5, 0.04, 1.5, "aqua", "n" },
		{ "c", 0, 3.1, 0, 0.3, 1.2, 0.3, "aqua", "n" },
		{ "s", 0, 3.85, 0, 0.5, 0.5, 0.5, "gold", "f" },
	},
	far = { "c", 0, 0.3, 0, 4.2, 0.6, 4.2, "gold", "f" },
}
BY_ID.cloudHammock = {
	rows = {
		{ "c", -1.8, 1.4, 0, 0.25, 2.8, 0.25, "wood" },
		{ "c", 1.8, 1.4, 0, 0.25, 2.8, 0.25, "wood" },
		{ "b", -1.05, 1.15, 0, 1.3, 0.12, 1, "sky", nil, 0, 0, -18 },
		{ "b", 0, 0.95, 0, 0.9, 0.12, 1, "sky" },
		{ "b", 1.05, 1.15, 0, 1.3, 0.12, 1, "sky", nil, 0, 0, 18 },
		{ "s", -1.75, 3, 0, 0.9, 0.9, 0.9, "white" },
		{ "s", 1.75, 3, 0, 0.9, 0.9, 0.9, "white" },
		{ "s", -0.6, 1.25, 0, 0.6, 0.6, 0.6, "white" },
	},
	far = { "b", 0, 1, 0, 3.6, 0.3, 1, "sky" },
}
BY_ID.moonKite = {
	rows = {
		{ "c", 0, 0.3, 0, 0.3, 0.6, 0.3, "wood" },
		{ "b", 0.4, 1.9, 0, 0.04, 3, 0.04, "white", nil, 0, 0, -15 },
		{ "s", 0.9, 3.6, 0, 1.4, 1.4, 1.4, "lemon", "n" },
		{ "b", 0.75, 2.6, 0, 0.25, 0.12, 0.05, "pink" },
		{ "b", 0.6, 2.2, 0, 0.25, 0.12, 0.05, "sky" },
		{ "b", 0.45, 1.8, 0, 0.25, 0.12, 0.05, "pink" },
		{ "b", 1.6, 3.9, 0, 0.3, 0.3, 0.05, "white", "n", 0, 0, 45 },
	},
	far = { "s", 0.9, 3.6, 0, 1.4, 1.4, 1.4, "lemon" },
}
do
	local rows: { Row } = {
		{ "c", 0, 0.2, 0, 4.2, 0.4, 4.2, "pink" },
		{ "c", 0, 2, 0, 0.3, 3.2, 0.3, "gold", "f" },
		{ "c", 0, 3.75, 0, 4.2, 0.3, 4.2, "pink" },
		{ "s", 0, 4.1, 0, 0.6, 0.6, 0.6, "lemon", "n" },
	}
	local horses = { "white", "mint", "sky" }
	for i, deg in { 30, 150, 270 } do
		local a = math.rad(deg)
		local x, z = 1.4 * math.cos(a), 1.4 * math.sin(a)
		table.insert(rows, { "b", x, 1.3, z, 0.4, 0.5, 0.9, horses[i], nil, 0, -deg, 0 })
		table.insert(rows, { "c", x, 2, z, 0.08, 3.2, 0.08, "gold", "f" })
	end
	BY_ID.miniCarousel = { rows = rows, far = { "c", 0, 2, 0, 4.2, 4, 4.2, "pink" } }
end
BY_ID.sugarCrane = {
	rows = {
		{ "b", 0, 0.25, 0, 1.6, 0.5, 1.6, "lemon" },
		{ "b", 0, 2.2, 0, 0.4, 3.4, 0.4, "lemon" },
		{ "b", 0.6, 3.95, 0, 2.6, 0.3, 0.3, "lemon" },
		{ "b", -0.85, 3.7, 0, 0.6, 0.5, 0.5, "grey" },
		{ "b", 0.35, 3.4, -0.1, 0.5, 0.5, 0.5, "sky" },
		{ "b", 1.6, 3.05, 0, 0.04, 1.5, 0.04, "grey" },
		{ "b", 1.6, 2.1, 0, 0.6, 0.4, 0.6, "jelly" },
		{ "s", 0, 4.25, 0, 0.3, 0.3, 0.3, "red", "n" },
	},
	far = { "b", 0, 2.2, 0, 0.6, 4.4, 0.6, "lemon" },
}
BY_ID.lollipopSwing = {
	rows = {
		{ "b", 0, 0.05, 0, 4, 0.1, 0.6, "cream" },
		{ "c", -1.8, 1.7, 0, 0.25, 3.4, 0.25, "white" },
		{ "c", 1.8, 1.7, 0, 0.25, 3.4, 0.25, "white" },
		{ "b", 0, 3.45, 0, 3.9, 0.25, 0.25, "red" },
		{ "b", -0.4, 2.55, 0, 0.04, 1.6, 0.04, "cream" },
		{ "b", 0.4, 2.55, 0, 0.04, 1.6, 0.04, "cream" },
		{ "b", 0, 1.7, 0, 1.1, 0.12, 0.5, "pink" },
		{ "s", -1.8, 3.85, 0, 0.7, 0.7, 0.7, "jelly" },
		{ "s", 1.8, 3.85, 0, 0.7, 0.7, 0.7, "mint" },
	},
	far = { "b", 0, 1.8, 0, 3.8, 3.6, 0.3, "pink" },
}
BY_ID.sugarSandbox = {
	rows = {
		{ "b", 0, 0.25, -1.4, 3, 0.5, 0.2, "wood" },
		{ "b", 0, 0.25, 1.4, 3, 0.5, 0.2, "wood" },
		{ "b", -1.4, 0.25, 0, 0.2, 0.5, 2.6, "wood" },
		{ "b", 1.4, 0.25, 0, 0.2, 0.5, 2.6, "wood" },
		{ "b", 0, 0.3, 0, 2.6, 0.2, 2.6, "sand" },
		{ "b", 0.4, 0.6, 0.2, 0.6, 0.6, 0.6, "sand" },
		{ "c", 0.4, 1.1, 0.2, 0.3, 0.4, 0.3, "sand" },
		{ "c", -0.6, 0.55, -0.4, 0.4, 0.5, 0.4, "red" },
		{ "b", -0.2, 0.7, -0.6, 0.08, 0.6, 0.25, "sky", nil, 20, 0, 0 },
	},
	far = { "b", 0, 0.25, 0, 3, 0.5, 3, "wood" },
}
BY_ID.iceCreamStand = {
	rows = {
		{ "b", 0, 0.6, 0, 3.2, 1.2, 1.2, "white" },
		{ "b", 0, 0.6, -0.61, 3.2, 0.4, 0.02, "pink" },
		{ "c", -1.4, 2.1, 0.4, 0.15, 1.8, 0.15, "white" },
		{ "c", 1.4, 2.1, 0.4, 0.15, 1.8, 0.15, "white" },
		{ "b", 0, 3.1, 0.1, 3.4, 0.2, 1.6, "pink", nil, -10, 0, 0 },
		{ "b", 0, 3.22, 0.1, 1.1, 0.02, 1.6, "white", nil, -10, 0, 0 },
		{ "b", 0, 3.75, 0.3, 0.5, 0.6, 0.5, "caramel", nil, 0, 45, 0 },
		{ "s", 0, 4.15, 0.3, 0.7, 0.7, 0.7, "blush" },
	},
	far = { "b", 0, 1.6, 0, 3.2, 3.2, 1.2, "pink" },
}
do
	local rows: { Row } = {}
	local colors = { "red", "orange", "lemon", "mint", "sky" }
	local pts: { { number } } = {}
	for i = 0, 5 do
		local t = math.pi * i / 5
		table.insert(pts, { -1.75 * math.cos(t), 0.4 + 1.8 * math.sin(t) })
	end
	for i = 1, 5 do
		local a, b = pts[i], pts[i + 1]
		table.insert(rows, seg(a[1], a[2], b[1], b[2], 0, 0.35, 1.4, colors[i], nil, 0.2))
	end
	table.insert(rows, { "s", -1.75, 0.4, 0, 0.8, 0.8, 0.8, "white" })
	table.insert(rows, { "s", 1.75, 0.4, 0, 0.8, 0.8, 0.8, "white" })
	BY_ID.rainbowBridge = { rows = rows, far = { "b", 0, 1.1, 0, 3.6, 2.2, 0.4, "pink" } }
end
do
	local rows: { Row } = {
		{ "c", -1.6, 1.5, 0, 0.35, 3, 0.35, "white" },
		{ "c", 1.6, 1.5, 0, 0.35, 3, 0.35, "white" },
	}
	local pts: { { number } } = {}
	for i = 0, 3 do
		local t = math.pi * i / 3
		table.insert(pts, { 1.6 * math.cos(t), 3 + 1.1 * math.sin(t) })
	end
	for i = 1, 3 do
		local a, b = pts[i], pts[i + 1]
		table.insert(rows, seg(a[1], a[2], b[1], b[2], 0, 0.3, 0.3, "leaf", nil, 0.15))
	end
	local flowers = { "jelly", "lemon", "lilac", "mint" }
	for i, t in { 0.15, 0.4, 0.6, 0.85 } do
		local a = math.pi * t
		table.insert(
			rows,
			{ "s", 1.6 * math.cos(a), 3 + 1.1 * math.sin(a), -0.2, 0.35, 0.35, 0.35, flowers[i], "n" }
		)
	end
	BY_ID.flowerArch = { rows = rows, far = { "b", 0, 2, 0, 3.4, 4, 0.4, "leaf" } }
end
do
	local rows: { Row } = {
		{ "c", 0, 0.6, 0, 3.6, 1.2, 3.6, "cream" },
		{ "c", 0, 1.75, 0, 2.6, 1.1, 2.6, "pink" },
		{ "c", 0, 2.8, 0, 1.6, 1, 1.6, "cream" },
		{ "c", 0, 1.2, 0, 3.7, 0.12, 3.7, "white" },
		{ "c", 0, 2.3, 0, 2.7, 0.12, 2.7, "white" },
		{ "c", 0, 3.6, 0, 0.2, 0.6, 0.2, "sky" },
		{ "s", 0, 4.05, 0, 0.25, 0.25, 0.25, "lemon", "n" },
	}
	for _, deg in { 210, 270, 330 } do
		local a = math.rad(deg)
		table.insert(rows, { "s", 1.5 * math.cos(a), 1.35, 1.5 * math.sin(a), 0.3, 0.3, 0.3, "red" })
	end
	BY_ID.cakeTower = { rows = rows, far = { "c", 0, 1.6, 0, 3.6, 3.2, 3.6, "cream" } }
end
BY_ID.hotAirBalloon = {
	rows = {
		{ "b", 0, 0.4, 0, 1, 0.8, 1, "wood" },
		{ "b", -0.45, 1.3, -0.45, 0.05, 1, 0.05, "cream" },
		{ "b", 0.45, 1.3, -0.45, 0.05, 1, 0.05, "cream" },
		{ "b", -0.45, 1.3, 0.45, 0.05, 1, 0.05, "cream" },
		{ "b", 0.45, 1.3, 0.45, 0.05, 1, 0.05, "cream" },
		{ "s", 0, 3, 0, 2.6, 2.6, 2.6, "jelly" },
		{ "c", 0, 3, 0, 2.7, 0.3, 2.7, "lemon" },
		{ "c", 0, 4.25, 0, 0.8, 0.12, 0.8, "lemon" },
		{ "s", 0, 1.6, 0, 0.3, 0.3, 0.3, "orange", "n" },
	},
	far = { "s", 0, 3, 0, 2.6, 2.6, 2.6, "jelly" },
}
do
	local rows: { Row } = { { "b", 0, 0.5, 0, 3, 1, 3, "sky" } }
	local towers = { "pink", "lemon", "lemon", "pink" }
	for i, p in { { -1.3, -1.3 }, { 1.3, -1.3 }, { -1.3, 1.3 }, { 1.3, 1.3 } } do
		table.insert(rows, { "c", p[1], 1.3, p[2], 0.8, 2.6, 0.8, towers[i] })
		table.insert(rows, { "s", p[1], 2.85, p[2], 0.8, 0.8, 0.8, towers[5 - i] })
	end
	table.insert(rows, { "b", 0, 1.4, -1.45, 1.4, 0.8, 0.12, "jelly" })
	BY_ID.bouncyCastle = { rows = rows, far = { "b", 0, 1.4, 0, 3, 2.8, 3, "sky" } }
end
BY_ID.giantSlide = {
	rows = {
		{ "b", -0.45, 1.5, 1.6, 0.12, 3, 0.12, "grey" },
		{ "b", 0.45, 1.5, 1.6, 0.12, 3, 0.12, "grey" },
		{ "b", 0, 1, 1.6, 0.8, 0.08, 0.12, "grey" },
		{ "b", 0, 2, 1.6, 0.8, 0.08, 0.12, "grey" },
		{ "b", 0, 3, 1.2, 1.2, 0.15, 0.9, "sky" },
		{ "b", 0, 1.55, -0.62, 1, 0.15, 4, "pink", nil, -46.5, 0, 0 },
		{ "b", -0.55, 1.7, -0.62, 0.1, 0.3, 4, "white", nil, -46.5, 0, 0 },
		{ "b", 0.55, 1.7, -0.62, 0.1, 0.3, 4, "white", nil, -46.5, 0, 0 },
		{ "b", 0.5, 3.6, 1.5, 0.05, 1, 0.05, "white" },
		{ "b", 0.7, 3.95, 1.5, 0.4, 0.25, 0.02, "jelly" },
	},
	far = { "b", 0, 1.5, 0, 1.2, 3, 3, "pink" },
}
do
	local rows: { Row } = {
		{ "c", 0, 0.15, 0, 2.6, 0.3, 2.6, "grey" },
		{ "c", 0, 1.8, 0, 1.2, 3, 1.2, "white" },
		{ "c", 0, 2.2, 0, 1.25, 0.4, 1.25, "pink" },
		{ "s", 0, 3.6, 0, 1.1, 1.1, 1.1, "rose" },
		{ "s", 0, 4.2, 0, 0.3, 0.3, 0.3, "lemon", "n" },
		{ "s", 0, 2.6, -0.56, 0.35, 0.35, 0.35, "sky", "n" },
	}
	for k = 0, 2 do
		local deg = 120 * k + 90
		local a = math.rad(deg)
		table.insert(
			rows,
			{ "b", 0.8 * math.cos(a), 0.8, 0.8 * math.sin(a), 0.5, 1, 0.12, "rose", nil, 0, -deg, 0 }
		)
	end
	BY_ID.sugarRocket = { rows = rows, far = { "c", 0, 2.2, 0, 1.2, 4, 1.2, "white" } }
end
BY_ID.jellyDragon = {
	rows = {
		{ "s", 0, 1.2, 0, 2, 2, 2, "mint" },
		{ "c", 0, 2.2, -0.5, 0.7, 1, 0.7, "mint", nil, -25, 0, 0 },
		{ "s", 0, 3, -0.9, 1.2, 1.2, 1.2, "mint" },
		{ "s", -0.25, 3.15, -1.45, 0.2, 0.2, 0.2, "dark" },
		{ "s", 0.25, 3.15, -1.45, 0.2, 0.2, 0.2, "dark" },
		{ "b", -1.2, 2, 0.2, 1.2, 0.1, 0.8, "jelly", "n", 0, 0, 25 },
		{ "b", 1.2, 2, 0.2, 1.2, 0.1, 0.8, "jelly", "n", 0, 0, -25 },
		{ "b", 0, 0.6, 1.4, 0.4, 0.3, 1.2, "mint", nil, 20, 0, 0 },
		{ "b", -0.3, 3.7, -0.8, 0.1, 0.4, 0.1, "lemon" },
		{ "b", 0.3, 3.7, -0.8, 0.1, 0.4, 0.1, "lemon" },
	},
	far = { "s", 0, 1.5, 0, 2.6, 2.6, 2.6, "mint" },
}

-- Dessin de l'objet n (1 … 40 de Cosmetics.DecoPerso) et sa taille « P » | « G »
local function designOf(n: number): (Design?, string?)
	local def = if type(n) == "number" then Cosmetics.DecoPerso[n] else nil
	if def == nil then
		return nil, nil
	end
	return BY_ID[def.id], def.size
end

-- Pièces de l'objet n posé sur l'emplacement i (1 … 12) du ranch `slot` ; level « full » : le dessin,
-- « reduced » : la silhouette d'un grand objet (aucune pour un petit) ; clés « deco<i>_<n>_<j> »
-- (un autre objet sur le même emplacement recrée ses pièces)
function DecoKit.specs(slot: number, i: number, n: number, level: string): { Spec }
	local design, size = designOf(n)
	if design == nil then
		return {}
	end
	local base = WorldLayout.decoPersoSlot(slot, i)
	local prefix = "deco" .. i .. "_" .. n .. "_"
	if level == "full" then
		return RanchKit.rows({}, base, prefix, design.rows, P)
	elseif level == "reduced" and size == "G" and design.far then
		return { RanchKit.row(base, prefix .. "far", design.far :: Row, P) }
	end
	return {}
end

-- Nombre de pièces de l'objet n à ce niveau
function DecoKit.count(n: number, level: string): number
	local design, size = designOf(n)
	if design == nil then
		return 0
	end
	if level == "full" then
		return #design.rows
	elseif level == "reduced" and size == "G" and design.far then
		return 1
	end
	return 0
end

-- Lignes d'un dessin (specs : emprise, hauteur, nombre de pièces) ; far = silhouette d'un grand objet
function DecoKit.rows(n: number): ({ Row }, Row?, string?)
	local design, size = designOf(n)
	if design == nil then
		return {}, nil, nil
	end
	return design.rows, design.far, size
end

return DecoKit
