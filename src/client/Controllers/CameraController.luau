--!strict
-- CameraController (paquet client-world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Caméra (GDD §10.4, §9.4) : elle ne bouge JAMAIS toute seule, sauf le travelling du Grand Splorch du
-- héros (suit le vol puis le retour du petit squishy), coupé en Mouvement réduit (une flèche montre la
-- place). Coups de focale (fovPunch) et secousses par Humanoid.CameraOffset (≤ 0,4, ≤ 0,3 s).

local CameraController = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function CameraController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function CameraController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Travelling du héros calé sur l'heure envoyée
function CameraController.splorch(startedAt: number, burstAt: number, endsAt: number)
	local _ = { startedAt, burstAt, endsAt }
	error("TODO(client-world): CameraController.splorch")
end

-- Coup de focale (pas en Mouvement réduit)
function CameraController.fovPunch(degrees: number, duration: number)
	local _ = { degrees, duration }
	error("TODO(client-world): CameraController.fovPunch")
end

-- Secousse bornée (pas en Mouvement réduit)
function CameraController.shake(amplitude: number, duration: number)
	local _ = { amplitude, duration }
	error("TODO(client-world): CameraController.shake")
end

-- Travelling en cours
function CameraController.busy(): boolean
	error("TODO(client-world): CameraController.busy")
end

return CameraController
