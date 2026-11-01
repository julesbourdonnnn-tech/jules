--!strict
-- WorldLayout (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Plan de Wobbleton, pur (GDD §11.1, §11.2) : ranchs 1-16 (repère local : X de −32 à +32, Z du
-- portail 0 au fond 72 ; ranch k centré sur 22,5° × (k − 1) + 11,25°, portail à r = 178), place,
-- graphe des rues, solides (boîtes) et surface du sol. Toute position dont le jeu a besoin vient
-- d'ici, jamais d'une recherche dans le workspace (règle zéro bug). Aucun solide à moins de 6 studs
-- d'un autre sans être collé (pas de recoin) ; aucune arête du graphe n'entre dans un ranch.

-- Constantes du plan (GDD §11.1), publiques
local CONST = {
	PlateRadius = 320,
	WallRadius = 322,
	HillsRadius = 420,
	PlazaRadius = 50,
	InnerRing = 95,
	Boulevard = 166,
	GateRadius = 178,
	BackRadius = 250,
	RanchWidth = 64,
	RanchDepth = 72,
	Ranches = 16,
	MeadowRadius = 280,
	-- Hauteurs des solides (docs/04 §3.1, §20 n° 21) : AU-DESSUS de la plus haute hauteur atteignable
	-- (selle géante : saut 13 + HipHeight jusqu'à 6 + marge), pour que personne n'enjambe un mur ni
	-- ne monte sur un toit, même en monture. WorldBuild.spec vérifie chaque boîte de solids().
	MaxReach = 22, -- studs au-dessus du sol : saut le plus haut (13) + décalage de racine max (6) + 3
	SolidMinHeight = 30, -- hauteur minimale de toute boîte de solids() (≥ MaxReach + 8)
	FenceWallHeight = 30, -- mur invisible au-dessus de la clôture d'un ranch (GDD §11.2 : 12, relevé)
	EdgeWallHeight = 30, -- murs invisibles du bord (r = 322)
	HouseCapHeight = 30, -- boîte invisible au-dessus de chaque maison-bonbon (toit inaccessible)
}

export type Anchor =
	"pot"
	| "vat"
	| "pool"
	| "bowl"
	| "cushion"
	| "shelf"
	| "fountain"
	| "sign"
	| "silhouette"
	| "gate"
export type PlazaName =
	"center"
	| "megaPad"
	| "statue"
	| "shop"
	| "altar"
	| "gauge"
	| "stage"
	| "goldenFountain"
	| "boards"
export type Graph = { nodes: { Vector3 }, neighbors: { { number } } }
export type Box = { cframe: CFrame, size: Vector3 }

local WorldLayout = {}

WorldLayout.Const = CONST

-- Repère local du ranch (origine au portail, Z vers le fond, tourné vers la place)
function WorldLayout.ranchCFrame(slot: number): CFrame
	local _ = { slot }
	error("TODO(logic): WorldLayout.ranchCFrame")
end

-- Point local → monde
function WorldLayout.toWorld(slot: number, localPos: Vector3): Vector3
	local _ = { slot, localPos }
	error("TODO(logic): WorldLayout.toWorld")
end

-- Point monde → local
function WorldLayout.toLocal(slot: number, worldPos: Vector3): Vector3
	local _ = { slot, worldPos }
	error("TODO(logic): WorldLayout.toLocal")
end

-- Ranch dont le rectangle contient la position (0 = aucun)
function WorldLayout.ranchAt(pos: Vector3): number
	local _ = { pos }
	error("TODO(logic): WorldLayout.ranchAt")
end

-- Position dans le rectangle de ce ranch
function WorldLayout.inRanch(slot: number, pos: Vector3): boolean
	local _ = { slot, pos }
	error("TODO(logic): WorldLayout.inRanch")
end

-- Point de poussée d'un intrus : 6 studs devant le portail, côté rue
function WorldLayout.gateOutside(slot: number): Vector3
	local _ = { slot }
	error("TODO(logic): WorldLayout.gateOutside")
end

-- Point d'apparition (Z = 30, X = 0) face au Pot
function WorldLayout.spawnCFrame(slot: number): CFrame
	local _ = { slot }
	error("TODO(logic): WorldLayout.spawnCFrame")
end

-- Position monde d'un objet du ranch (Pot, Cuve, Bassin, bol, coussin, étagère, Fontaine, panneau, silhouette)
function WorldLayout.anchor(slot: number, name: Anchor): Vector3
	local _ = { slot, name }
	error("TODO(logic): WorldLayout.anchor")
end

-- Centre monde d'une prise de dalle (1 … 4, Config/Pads)
function WorldLayout.padSocket(slot: number, socket: number): Vector3
	local _ = { slot, socket }
	error("TODO(logic): WorldLayout.padSocket")
end

-- Emplacement de la décoration n° index (1 … 18)
function WorldLayout.decorSlot(slot: number, index: number): CFrame
	local _ = { slot, index }
	error("TODO(logic): WorldLayout.decorSlot")
end

-- Place n° index (1 … 24) dans la zone d'enclos
function WorldLayout.penSlot(slot: number, index: number): Vector3
	local _ = { slot, index }
	error("TODO(logic): WorldLayout.penSlot")
end

-- Place flottante n° index (1 … 6) du Bassin
function WorldLayout.poolSlot(slot: number, index: number): Vector3
	local _ = { slot, index }
	error("TODO(logic): WorldLayout.poolSlot")
end

-- Place n° index (1 … 4) à la clôture, côté rue (Rush, pet-sitting)
function WorldLayout.fencePoint(slot: number, index: number): Vector3
	local _ = { slot, index }
	error("TODO(logic): WorldLayout.fencePoint")
end

-- Position d'un objet de la place (MEGA pad, statue, boutique, autel, jarre, scène, fontaine dorée, tableaux)
function WorldLayout.plaza(name: PlazaName): Vector3
	local _ = { name }
	error("TODO(logic): WorldLayout.plaza")
end

-- Graphe des rues (nœuds et voisins) utilisé par SeededPath
function WorldLayout.graph(): Graph
	error("TODO(logic): WorldLayout.graph")
end

-- Nœud du graphe le plus proche
function WorldLayout.nearestNode(pos: Vector3): number
	local _ = { pos }
	error("TODO(logic): WorldLayout.nearestNode")
end

-- Nœud du boulevard devant le portail du ranch (départ des fuites du Rush)
function WorldLayout.fountainNode(slot: number): number
	local _ = { slot }
	error("TODO(logic): WorldLayout.fountainNode")
end

-- Points de départ des Wild Wobblers (fontaine de la place, bouts des rues radiales)
function WorldLayout.wildSpawnNodes(): { number }
	error("TODO(logic): WorldLayout.wildSpawnNodes")
end

-- Boîtes solides (maisons avec leur coiffe invisible, clôtures et leurs murs invisibles, bord du
-- plateau) ; chaque boîte mesure au moins Const.SolidMinHeight de haut
function WorldLayout.solids(): { Box }
	error("TODO(logic): WorldLayout.solids")
end

-- Hauteur du support sous une position (règles du serveur, MoveCheck) : max(groundY(x, z), haut de
-- chaque boîte de solids() dont l'emprise XZ contient la position). Pur : jamais de Blockcast ni de
-- Raycast pour une règle.
function WorldLayout.supportY(pos: Vector3): number
	local _ = { pos }
	error("TODO(logic): WorldLayout.supportY")
end

-- Surface analytique du sol (MoveCheck.setSurface)
function WorldLayout.groundY(x: number, z: number): number
	local _ = { x, z }
	error("TODO(logic): WorldLayout.groundY")
end

-- Place n° index (1 … 12) dans la Prairie des copains
function WorldLayout.meadowPoint(index: number): Vector3
	local _ = { index }
	error("TODO(logic): WorldLayout.meadowPoint")
end

return WorldLayout
