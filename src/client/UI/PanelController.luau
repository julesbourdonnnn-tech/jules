--!strict
-- PanelController (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Menu (rail) et panneaux (GDD §10.3, §10.4, §10.6) : △ / croix ↓ ouvre le rail (Grand Splorch s'il
-- est prêt, sinon l'entrée à pastille « ! », sinon la dernière, sinon Ranch), un seul panneau ouvert,
-- 1440 × 860 px TV, ○ recule d'un niveau puis rend la main au jeu, △ ferme tout, L1 / R1 onglets en
-- boucle, L2 / R2 panneaux en boucle (seulement quand un panneau est ouvert), règle des 3 touches
-- (croix, ✕, ○), sons de navigation, vibrations listEnd. Boutique cachée < 10 min de jeu ou sans
-- identifiant ; Diagnostics pour les administrateurs seulement. Charge les modules UI/Panels/*,
-- leur passe un navigateur (setNavigator) avant build et écoute Cards.Requested (ouvrir un panneau
-- demandé par une carte).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

local PanelController = {}

-- (panneau ouvert ou nil)
PanelController.Changed = Signal.new() :: Signal.Signal<string?>

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function PanelController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function PanelController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- △ / croix ↓ / M (KeyCode.M et Semicolon ; jamais Tab, laissé à Roblox)
function PanelController.toggleMenu()
	error("TODO(client-panels): PanelController.toggleMenu")
end

-- Ouvre le rail (entrée sélectionnée)
function PanelController.openMenu(entry: string?)
	local _ = { entry }
	error("TODO(client-panels): PanelController.openMenu")
end

-- Ouvre un panneau
function PanelController.open(panel: string, tab: string?)
	local _ = { panel, tab }
	error("TODO(client-panels): PanelController.open")
end

-- Ferme tout et rend la main au jeu
function PanelController.closeAll()
	error("TODO(client-panels): PanelController.closeAll")
end

-- Un panneau (ou celui-ci) est ouvert
function PanelController.isOpen(panel: string?): boolean
	local _ = { panel }
	error("TODO(client-panels): PanelController.isOpen")
end

-- Panneau ouvert
function PanelController.current(): string?
	error("TODO(client-panels): PanelController.current")
end

-- Entrées visibles du rail, dans l'ordre
function PanelController.entries(): { string }
	error("TODO(client-panels): PanelController.entries")
end

return PanelController
