--!strict
-- PanelController — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.15).
-- API de navigation des panneaux utilisée par le HUD, InputController et l'accueil.
-- Responsabilités :
--   * un seul panneau ouvert à la fois ; open(name) ferme le précédent ; back() revient au panneau
--     parent (Supernova → Upgrades) ; close() ; ouvrir un panneau ne met jamais le jeu en pause
--   * construction paresseuse : chaque module de UI/Panels/* est construit à la première ouverture
--     dans un ScreenGui « Panels » (Root.safe) : Size = UDim2.fromScale(0,72 ; 0,86), UISizeConstraint
--     (min 480 × 320, max 900 × 600), onglets de 56 px, bouton Fermer 64 × 64 ; ouverture UIScale
--     0,85 → 1 (0,22 s Back Out) + CanvasGroup 1 → 0 (0,15 s) + BlurEffect 0 → 8 (sauf Graphismes
--     légers) ; fermeture 0,12 s Quad In ; son Whoosh
--   * manette : GuiService.SelectedObject sur le premier bouton, LB/RB = onglets, B = fermer ;
--     Échap ferme (PC)
--   * pastilles « ! » : hasAction() de chaque panneau, réévalué sur les changements de profil
--   * contour rose de l'écran quand un panneau est ouvert hors du port sûr et qu'un non-équipier
--     approche de la file (§13.2)
--   * propriétaire côté client du remote CrewInvitePrompt (carte « Mira t'invite » ✓ / ✕ 20 s, non
--     bloquante) et de l'ouverture de ReturnScreen sur Celebrate "offline" (ScreenFX.Celebrated)
-- GDD : §10.3, §9.2 (ouverture/fermeture), §10.4, §13.2.
-- Dépendances : StateController, AudioController, Util/Prefs, UI/Root, UI/Theme, UI/Create, UI/Juice,
-- WorldStateController, ScreenFX, UI/Panels/*, Shared/Net, Shared/Util/Signal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local PanelController = {}

-- Interface de chaque module de UI/Panels/*
export type Panel = {
	name: Types.PanelName,
	tabs: { string }?, -- clés de localisation des onglets
	build: (parent: Frame) -> (), -- construit une fois le contenu dans `parent`
	onOpen: (args: any?) -> (), -- à chaque ouverture (args : ex. { tab = "atlas", focus = "conga" })
	onClose: () -> (),
	hasAction: () -> boolean, -- pastille « ! » sur le rail
	selectTab: ((tab: string) -> ())?,
}

PanelController.Opened = Signal.new() :: Signal.Signal<Types.PanelName>
PanelController.Closed = Signal.new() :: Signal.Signal<Types.PanelName>
-- (panneau, a une action possible)
PanelController.BadgeChanged = Signal.new() :: Signal.Signal<Types.PanelName, boolean>

function PanelController.Init() end

function PanelController.Start() end

function PanelController.open(_name: Types.PanelName, _args: any?)
	error("TODO(client-panels): PanelController.open")
end

function PanelController.close()
	error("TODO(client-panels): PanelController.close")
end

function PanelController.back()
	error("TODO(client-panels): PanelController.back")
end

function PanelController.toggle(_name: Types.PanelName)
	error("TODO(client-panels): PanelController.toggle")
end

function PanelController.current(): Types.PanelName?
	error("TODO(client-panels): PanelController.current")
end

function PanelController.hasAction(_name: Types.PanelName): boolean
	error("TODO(client-panels): PanelController.hasAction")
end

-- Onglet suivant / précédent du panneau ouvert (LB/RB)
function PanelController.nextTab(_direction: number)
	error("TODO(client-panels): PanelController.nextTab")
end

return PanelController
