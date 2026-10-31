--!strict
-- OnboardingController — paquet « client-hud » (STUB du contrat : docs/04-architecture.md §13.14).
-- Les 5 premières minutes (§3), pilotées par profile.onboarding (StateController) — le serveur
-- (QuestService) décide de la progression, ce module ne fait que montrer.
-- Responsabilités :
--   * travelling caméra d'arrivée de 1,5 s (Scriptable, Sine InOut : ciel au-dessus du Nid → Cratère
--     → derrière le joueur), sauté en Mouvement réduit et pour les joueurs ayant fini l'accueil
--   * affichage progressif du HUD (HUD.reveal) : Glow, file, Dash à 1,5 s ; rail Améliorer après la
--     1re parade ; Collection + Stardust à Q4 ; tout pour un joueur revenant (step 8)
--   * guidage : 6 empreintes Néon de la porte vers les Puffkins puis inversées vers la porte, arche
--     qui pulse, Beam joueur → porte ; flèche au sol vers le groupe de Nebbies le plus proche ;
--     pilier bleu sur le Rare de Q4 ; main animée sur l'icône Améliorer (HUD.attention) ; carte
--     unique en surbrillance dans Améliorer (PanelController.open("Upgrades", { focus = "conga" }))
--   * jamais plus d'une instruction à l'écran (≤ 4 mots, "onboarding.*"), aucune fenêtre modale
--     dans les 60 premières secondes
--   * message « Ton Nid travaille même quand tu dors » à 10 min de jeu
-- GDD : §3, §7.1, §7.4, §10.1 (affichage progressif).
-- Dépendances : StateController, Util/Prefs, UI/Juice, WorldStateController, CongaRenderer,
-- PanelController, HUD, Logic/WorldLayout, Config/Quests, Shared/Util/Clock.

local OnboardingController = {}

function OnboardingController.Init() end

function OnboardingController.Start() end

-- Étape d'accueil affichée (miroir de profile.onboarding.step)
function OnboardingController.step(): number
	error("TODO(client-hud): OnboardingController.step")
end

-- Instruction courante (clé "onboarding.*") ou nil
function OnboardingController.currentHint(): string?
	error("TODO(client-hud): OnboardingController.currentHint")
end

return OnboardingController
