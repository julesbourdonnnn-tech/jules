--!strict
-- QualityController (paquet client-world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Qualité adaptative (GDD §12.9) : durée moyenne des images > 36 ms pendant 10 s → qualité réduite
-- (détail × 0,6, 40 squishies animés, particules × 0,3, lumières coupées au-delà de 60 studs,
-- Highlight sur la cible et les fuites seulement, pas de BlurEffect) ; remonte après 60 s sous 25
-- ms ; au plus un changement par minute. Graphismes légers force la qualité réduite. Analytique
-- QualityReduced : intention ClientEvent("qualityReduced") envoyée à chaque descente (contrat v1.2).
-- Budgets PARTAGÉS (remarque A23) : chaque ressource a un quota par module ; la spec de chaque module
-- vérifie que son stats() reste dans son quota (jamais « tout le budget pour moi »).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

export type Budgets = {
	lodScale: number, -- distances de détail × 1 ou × 0,6
	animated: number, -- squishies animés à pleine cadence (80 ou 40)
	particles: number, -- facteur de particules (1 ou 0,3)
	highlights: number, -- Highlight au plus (12, ou 7 : cible + 6 fuites)
	lightRange: number, -- studs au-delà desquels les lumières sont coupées (math.huge ou 60)
	blur: boolean,
	-- quotas par module (déjà multipliés par le facteur de qualité) : particules ≤ 200 au total
	-- (vfx 120, chase 50, lighting 30 dont les flocons d'hiver ; × 0,3 en qualité réduite)
	particleQuota: { vfx: number, chase: number, lighting: number },
	-- Highlight ≤ 12 : target 1 (cible, RanchRenderer), chase 7 (6 fuites du Rush + Golden, ChaseRenderer),
	-- ranch 3 (Mythiques et Secrets les plus proches, RanchRenderer), réserve 1 (qualité réduite : 1 / 6 / 0)
	highlightQuota: { target: number, chase: number, ranch: number },
	-- lumières ≤ 24 : world 16 (lampadaires, LightingController / WorldService), ranch 4 (ranch local),
	-- squishies 4 (Légendaires+ les plus proches, RanchRenderer)
	lightQuota: { world: number, ranch: number, squishies: number },
}

local QualityController = {}

-- (reduced)
QualityController.Changed = Signal.new() :: Signal.Signal<boolean>

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function QualityController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function QualityController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Qualité réduite en vigueur
function QualityController.reduced(): boolean
	error("TODO(client-world): QualityController.reduced")
end

-- Budgets du moment pour les rendus et les effets
function QualityController.budgets(): Budgets
	error("TODO(client-world): QualityController.budgets")
end

return QualityController
