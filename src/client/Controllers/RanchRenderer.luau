--!strict
-- RanchRenderer (paquet client-world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Rendu des ranchs et de la place (GDD §5.2, §6.6, §9.3, §11.2, §12.9) : squishies des enclos et du
-- Bassin (SquishyBuilder, niveaux de détail < 60 / 60-140 / > 140 studs, ranchs à > 220 studs en
-- silhouette « ×N », un BulkMoveTo par image, 80 animés au plus), animations de repos, prêt, recharge,
-- jumeaux (cœurs), Bassin, clôture, monture et squishy porté (dessinés sur le personnage), Meilleur
-- Ami qui suit en ville, silhouettes à Y = 40, statue de la place, Étagère à trophées, Prairie des
-- copains (propriétaire seulement), dalles et anneaux de prix (ranch local), panneau du ranch, portails
-- solides sur ce client pour les ranchs des autres, tableaux et compte à rebours de l'Autel ;
-- cosmétiques publics (RanchPublic) : couleur de selle et traînée sur la monture, thème et drapeau du
-- ranch, titre au-dessus de la tête de chaque joueur (BillboardGui ≤ 150 studs, texte ≥ 28 px TV,
-- alias si le nom est caché).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local TargetRules = require(Shared.Logic.TargetRules)

local RanchRenderer = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function RanchRenderer.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function RanchRenderer.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Position dessinée d'un squishy (cible, effets)
function RanchRenderer.positionOf(slot: number, uid: string): Vector3?
	local _ = { slot, uid }
	error("TODO(client-world): RanchRenderer.positionOf")
end

-- Joue un profil d'écrasement (Render/Squash) sur un squishy
function RanchRenderer.play(slot: number, uid: string, profile: string)
	local _ = { slot, uid, profile }
	error("TODO(client-world): RanchRenderer.play")
end

-- Fait pulser 1 s les cœurs des jumeaux d'un squishy du ranch local
function RanchRenderer.pulseTwins(uid: string)
	local _ = { uid }
	error("TODO(client-world): RanchRenderer.pulseTwins")
end

-- Squishies candidats projetés à l'écran (clic souris)
function RanchRenderer.projected(camera: Camera): { TargetRules.Projected }
	local _ = { camera }
	error("TODO(client-world): RanchRenderer.projected")
end

-- Compteurs de budget (modèles, pièces, animés) pour les specs
function RanchRenderer.stats(): { [string]: number }
	error("TODO(client-world): RanchRenderer.stats")
end

return RanchRenderer
