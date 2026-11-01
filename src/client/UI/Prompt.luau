--!strict
-- Prompt (paquet client-hud) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Invites dans le monde dessinées par le jeu, sans ProximityPrompt (GDD §10.2, §10.4) : « □ Presser »
-- (glyphe 64 + mot 40 px TV, plaque 300 × 88) au-dessus de la cible de PromptController, deuxième ligne
-- « ○ Prendre » après la leçon de fusion, anneau des maintiens calé sur l'heure de fin du serveur
-- (BoopState.endsAt, HoldState.endsAt). Jamais deux invites sur la même touche, 2 au plus ; cachées
-- dès qu'une fenêtre est ouverte. Glyphes de l'appareil (UI/Glyph), touches clavier sur PC.

local Prompt = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function Prompt.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function Prompt.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Anneau de maintien (nil : retiré)
function Prompt.setHold(kind: string, endsAt: number?)
	local _ = { kind, endsAt }
	error("TODO(client-hud): Prompt.setHold")
end

-- Plaques affichées (specs)
function Prompt.plates(): { GuiObject }
	error("TODO(client-hud): Prompt.plates")
end

return Prompt
