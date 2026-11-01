--!strict
-- HUD (paquet client-hud) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- HUD télé (GDD §10.2) aux rectangles de Config/Layout.Hud : pièces (prédiction + défilement),
-- Fame et amis, puce Menu (△, pastilles « ! » et « ♥ N »), pastille d'événement (comptes à rebours
-- Rush / MEGA / Lune / fêtes), barre du MEGA, jauge, suivi d'objectif (Grand Splorch), indicateurs
-- d'état (bouclier, ×2, mode), puce d'action spéciale (GRAND SPLORCH ! / APPLAUDIR), carte de la
-- cible, indicateur Bondir, flèches de bord d'écran. Affichage progressif pendant l'accueil. Aucun
-- chevauchement, texte ≥ 28 px TV, glyphes de l'appareil. Pose ClientReady une fois construit.

local HUD = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function HUD.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function HUD.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Montre ou cache un élément (accueil)
function HUD.reveal(element: string, visible: boolean)
	local _ = { element, visible }
	error("TODO(client-hud): HUD.reveal")
end

-- Consigne du moment dans la place de la puce spéciale (accueil)
function HUD.setHint(action: string?, textKey: string?)
	local _ = { action, textKey }
	error("TODO(client-hud): HUD.setHint")
end

-- Pastilles de la puce Menu
function HUD.setMenuBadges(bang: boolean, twins: number)
	local _ = { bang, twins }
	error("TODO(client-hud): HUD.setMenuBadges")
end

-- Élément du HUD (specs de disposition)
function HUD.element(name: string): GuiObject?
	local _ = { name }
	error("TODO(client-hud): HUD.element")
end

-- Héros de la fenêtre APPLAUDIR ouverte (ClapPrompt, 8 s) ou nil : InputController transforme alors
-- croix → en Clap(heroId)
function HUD.clapHero(): number?
	error("TODO(client-hud): HUD.clapHero")
end

return HUD
