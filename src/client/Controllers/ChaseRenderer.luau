--!strict
-- ChaseRenderer (paquet client-world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Rendu des créatures (GDD §9.4, §12.9) : fuites personnelles, fuites du Rush (anneau à la couleur du
-- propriétaire, Highlight des 6 plus proches, traînée, anneau de temps), Wild Wobblers, Golden
-- Wobbler, démonstration de Big Plop ; bonds (profil hop) le long de SeededPath, sons 3D, bulle-bébé
-- à la capture (l'attrapeur ne touche jamais l'original), retour au ranch avec des cœurs. Réserve
-- de modèles ; une créature finie (ou dont l'heure de fin est passée) disparaît en rétrécissant.

local ChaseRenderer = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function ChaseRenderer.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function ChaseRenderer.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Position dessinée d'une créature
function ChaseRenderer.positionOf(id: number): Vector3?
	local _ = { id }
	error("TODO(client-world): ChaseRenderer.positionOf")
end

-- Compteurs de budget (créatures, Highlight, particules)
function ChaseRenderer.stats(): { [string]: number }
	error("TODO(client-world): ChaseRenderer.stats")
end

return ChaseRenderer
