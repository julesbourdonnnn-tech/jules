--!strict
-- ReturnScreen (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Écran de retour (GDD §7.2) sur Celebrate "return" : « Pendant ton absence (5 h 12) : Mochi Mew a
-- grossi de +X », le squishy qui gonfle (0,8 s), « +Y pièces dans ton Pot », « Grand Splorch prêt ! »
-- si l'objectif est atteint ; bouton « Super ! » (360 × 112 px TV) sélectionné d'office ; ✕ ou ○
-- ferment. Fenêtre bloquante de FocusGuard, avant toute carte. Aucune offre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)

local ReturnScreen = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function ReturnScreen.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function ReturnScreen.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Affiche l'écran
function ReturnScreen.show(data: Types.ReturnScreenData)
	local _ = { data }
	error("TODO(client-panels): ReturnScreen.show")
end

-- Écran ouvert
function ReturnScreen.isOpen(): boolean
	error("TODO(client-panels): ReturnScreen.isOpen")
end

return ReturnScreen
