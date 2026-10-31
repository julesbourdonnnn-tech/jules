--!strict
-- HUD — paquet « client-hud » (STUB du contrat : docs/04-architecture.md §13.12).
-- Interface de jeu permanente (§10.2), construite en code dans Root.safe("HUD"), affichage
-- progressif piloté par OnboardingController.
-- Responsabilités :
--   * pastille Glow (16, 16 ; 260 × 64) : valeur PRÉDITE glow + idleRate × (Clock.now() − lastSettle)
--     + glowCarry, défilement countTo 0,5 s Quint Out + pop sur gain, défilement continu sans pop pour
--     le revenu passif, « +1,2K/s » ; pastille Stardust (16, 88 ; apparaît à Q4)
--   * compteur de file (bas centre, 360 × 56) : « 7/15 », barre, « ×1,48 » (Formulas.congaBonus),
--     vide « Attrape des Nebbies ! », pop 1,15 à la capture, 2 clignotements rouges + « PLEINE » +
--     flèche vers le Nid (Feedback lineFull), icône bouclier débutant
--   * bouton Dash (112 × 112, au-dessus à gauche du bouton de saut tactile lu dans
--     TouchGui.TouchControlFrame.JumpButton avec WaitForChild borné, décalage −16 px ; PC/manette :
--     bas droite) avec balayage radial de recharge et pop au retour ; bouton Ping (72 × 72)
--   * pastille d'événement (haut centre, 320 × 48) : prochain événement (EventClock.nextEvent) avec
--     compte à rebours, événement en cours en couleur, « ☄ COMÈTE 0:45 — Mira », barre de la Balise
--     (420 × 28) ; indicateurs d'état (bouclier, Zen, boost ×2 avec minuteur) ; suivi de quête
--     (260 × 72, repliable) ; icônes Équipage et Réglages
--   * rail de menus (gauche, y 150-470, 4 boutons 80 × 80) : Améliorer, Collection, Objectifs,
--     Boutique → PanelController.open ; pastille « ! » (PanelController.hasAction)
--   * bouton ACCLAMER (200 × 88, 10 s, anneau de temps) : propriétaire du remote CheerPrompt,
--     envoie Cheer(heroId)
--   * icône « connexion instable » (attribut Player « Unstable »)
--   * pose l'attribut LOCAL Players.LocalPlayer « ClientReady » = true quand l'instantané est reçu et
--     le HUD construit (fin de l'écran de chargement)
--   * tous les boutons : Juice.press, Selectable, navigation manette explicite ; textes via Prefs.t,
--     ré-appliqués sur Prefs.LanguageChanged
-- GDD : §3 (HUD progressif), §6.6 (acclamer), §9.2, §10.1, §10.2.
-- Dépendances : StateController, AudioController, Util/Prefs, UI/Root, UI/Theme, UI/Create, UI/Juice,
-- WorldStateController, ScreenFX, Banners, PanelController, InputController, Logic/Formulas,
-- Logic/EventClock, Config/*, Shared/Net, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local HUD = {}

function HUD.Init() end

function HUD.Start() end

-- Affiche un élément (animé : pop + pulsation) ; idempotent
function HUD.reveal(_element: Types.HudElement, _animate: boolean?)
	error("TODO(client-hud): HUD.reveal")
end

function HUD.isRevealed(_element: Types.HudElement): boolean
	error("TODO(client-hud): HUD.isRevealed")
end

-- Tout afficher (joueur ayant fini l'accueil)
function HUD.revealAll()
	error("TODO(client-hud): HUD.revealAll")
end

-- Élément d'interface d'ancrage (cible des pièces volantes, des flèches d'accueil)
function HUD.anchor(_element: Types.HudElement): GuiObject?
	error("TODO(client-hud): HUD.anchor")
end

-- Fait pulser un élément pour attirer l'attention (accueil) ; false arrête
function HUD.attention(_element: Types.HudElement, _on: boolean)
	error("TODO(client-hud): HUD.attention")
end

return HUD
