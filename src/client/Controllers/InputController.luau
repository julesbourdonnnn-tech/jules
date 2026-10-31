--!strict
-- InputController — paquet « client-hud » (STUB du contrat : docs/04-architecture.md §13.11).
-- Toutes les actions passent par ContextActionService (boutons tactiles créés par notre UI).
-- Responsabilités :
--   * Dash : Maj gauche ou E, bouton X (manette), bouton tactile du HUD → dash() : recharge locale
--     prédite (Formulas.dashCooldown(R)), refus local si porteur de la Comète, remote Dash,
--     VFXController.playDash, son Dash ; synchronisation sur l'attribut Player « DashReadyAt »
--   * roue de pings : Q (puis 1-6 ou clic), croix haut (puis stick + A), bouton tactile 72 px ;
--     6 secteurs de 96 px dessinés en Frames ; remote Ping(kind) au plus 1 / 1,5 s ; emote locale
--     (Humanoid:PlayEmote) : Suis-moi → point, Bravo → cheer, Merci → wave
--   * raccourcis : U, C, J, B, G → PanelController.toggle ; Échap / B ferme ; Y ouvre le rail ;
--     LB/RB changent d'onglet ; M / croix bas : minicarte ; F / croix droite : acclamer
--   * type d'entrée (1 tactile, 2 clavier-souris, 3 manette) depuis UserInputService
--     (LastInputTypeChanged) → remote SetInputType au plus 1 / 5 s (seulement s'il change)
--   * StarterPlayer.EnableMouseLockOption = false (projet) : Maj sert au Dash
-- GDD : §6.3, §10.2 (Dash, Ping), §10.4.
-- Dépendances : StateController, AudioController, Util/Prefs, VFXController, WorldStateController,
-- PanelController, Logic/Formulas, Config/Balance, Shared/Net, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local InputController = {}

-- Dash envoyé (prédiction locale acceptée)
InputController.Dashed = Signal.new() :: Signal.Signal<>
-- (kind 1-3)
InputController.InputTypeChanged = Signal.new() :: Signal.Signal<number>
-- Demande d'acclamation (F / croix droite) — le HUD envoie le remote Cheer
InputController.CheerRequested = Signal.new() :: Signal.Signal<>
-- Bascule de la minicarte (M / croix bas)
InputController.MinimapToggled = Signal.new() :: Signal.Signal<>

function InputController.Init() end

function InputController.Start() end

-- Tente un Dash ; false si recharge ou porteur de la Comète
function InputController.dash(): boolean
	error("TODO(client-hud): InputController.dash")
end

-- Clock.now() à partir duquel le Dash est prêt
function InputController.dashReadyAt(): number
	error("TODO(client-hud): InputController.dashReadyAt")
end

function InputController.inputType(): number
	error("TODO(client-hud): InputController.inputType")
end

function InputController.openPingWheel()
	error("TODO(client-hud): InputController.openPingWheel")
end

function InputController.closePingWheel()
	error("TODO(client-hud): InputController.closePingWheel")
end

-- Envoie un ping (kind 1-6) ; false si limité
function InputController.ping(_kind: number): boolean
	error("TODO(client-hud): InputController.ping")
end

return InputController
