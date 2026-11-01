--!strict
-- InputController (paquet client-hud) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Commandes (GDD §10.4) par ContextActionService:BindActionAtPriority, manette d'abord puis clavier-
-- souris, aucune commande tactile : □ / E / clic = action principale de la cible (maintiens Begin /
-- End pour boop et bol), ○ / Q = Prendre / Poser, R2 / Maj = Bondir, L2 / R = Monter, L1 / R1 =
-- changer de cible, △ / croix ↓ / M = Menu (M lié par KeyCode.M ET KeyCode.Semicolon, AZERTY ; JAMAIS
-- Tab, laissé à la liste des joueurs de Roblox ; son Bump avant la leçon du menu), G C J L B P =
-- panneaux directs (Config/Layout.Keyboard), sac à objets coupé (SetCoreGuiEnabled(Backpack, false)
-- sous pcall, nouveaux essais 10 s ; contrat v1.2), croix ↑ → ← / 1 2 3
-- = emotes (→ = Applaudir pendant 8 s ; F au clavier), Échap jamais lié. Touches du jeu déliées dès
-- qu'une fenêtre est ouverte (FocusGuard). Débit client des emotes (1 / 1,5 s). SetInputType.
-- SEUL module qui lie △ / croix ↓ / M (→ PanelController.toggleMenu) ; croix → devient Clap
-- pendant HUD.clapHero(). En portant : ○ ferme d'abord le menu ouvert, puis pose (ouvrir le menu ne
-- termine pas le portage ; ouvrir un panneau, si).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

local InputController = {}

-- (action jouée : "press", "pickup", "leap"…)
InputController.Action = Signal.new() :: Signal.Signal<string>

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function InputController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function InputController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Les touches du jeu sont liées (aucune fenêtre ouverte)
function InputController.gameBound(): boolean
	error("TODO(client-hud): InputController.gameBound")
end

return InputController
