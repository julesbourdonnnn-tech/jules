--!strict
-- LightingController (paquet world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Éclairage client (GDD §11.3, §9.4) : jour pastel (ClockTime 14,5), ciel rose pendant le BOOP RUSH
-- (Tint (255, 200, 225), 2 s), nuit de la Jelly Moon (4 s), lueur des fêtes ×2, costume d'hiver
-- (flocons qui suivent la caméra, budget §12.9). Version discrète du Rush pour un nouveau avant
-- l'étape 9 (30 %). Phases lues dans WorldStateController (EventClock) ; un seul tween par propriété.
-- Mouvement réduit : transitions en fondu court. Graphismes légers : pas de flou ni de flocons.

local LightingController = {}

-- Préréglage en vigueur
function LightingController.current(): string
	error("TODO(world): LightingController.current")
end

-- Version discrète des événements pour un nouveau (OnboardingController)
function LightingController.setQuiet(quiet: boolean)
	local _ = { quiet }
	error("TODO(world): LightingController.setQuiet")
end

return LightingController
