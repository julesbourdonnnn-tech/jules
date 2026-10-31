--!strict
-- ScreenFX — paquet « client-hud » (STUB du contrat : docs/04-architecture.md §13.9).
-- Juice d'ÉCRAN et propriétaire côté client des remotes Feedback et Celebrate (ré-exposés en
-- signaux pour les panneaux et l'accueil).
-- Responsabilités :
--   * Feedback → Toast (UI/Toast, ton → couleur) + son Error pour "error" ; secousse ±6 px du bouton
--     concerné si fourni par l'appelant (panneaux)
--   * Celebrate → réactions d'écran : "supernova" (titre qui s'écrit en 0,6 s, flash), "atlasNew"
--     (carte qui glisse, « NOUVEAU ! »), "atlasMilestone" (confettis), "questDone"/"questClaimed"/
--     "dailyClaimed" (récompense qui vole vers son compteur), "starforge", "purchase" (pluie de
--     30 pièces, « Merci ! »), "cometBanked", "rookieEnd", "release", "upgrade" (+ appelle
--     VFXController.playUpgrade), "offline" (ouvre ReturnScreen via les abonnés de Celebrated)
--   * tampons centraux (police LuckiestGuy, UIStroke 3 px) : « PARADE ×2,36 ! » (échelle 2 → 1,
--     rotation −8° → 0 en 0,25 s Back Out, tenu 0,8 s), « PLEINE », « COMÈTE VOLÉE ! »,
--     « Récupère-les ! », « Récupéré ! » ; réactions aux signaux de WorldStateController pour le
--     joueur local (parade : 8-16 pièces volent de la porte au compteur de Glow en 0,5 s, décalées de
--     0,03 s ; coupe subie : vignette rose 0,4 s + secousse)
--   * floaters d'écran (« +35 ✦ »), confettis d'écran ; Mouvement réduit : fondus seulement
-- GDD : §9.1 (stamp, flyCoins), §9.2, §9.4, §7.2.
-- Dépendances : StateController, AudioController, Util/Prefs, UI/Root, UI/Theme, UI/Create, UI/Juice,
-- UI/Toast, WorldStateController, VFXController, Shared/Net, Shared/Util/Signal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local ScreenFX = {}

-- Chaque Feedback reçu (après affichage du toast)
ScreenFX.FeedbackReceived = Signal.new() :: Signal.Signal<Types.FeedbackPayload>
-- Chaque Celebrate reçu (les panneaux y branchent leurs animations internes)
ScreenFX.Celebrated = Signal.new() :: Signal.Signal<Types.CelebratePayload>

export type StampStyle = "parade" | "snip" | "small" | "comet"

function ScreenFX.Init() end

function ScreenFX.Start() end

function ScreenFX.stamp(_text: string, _color: Color3, _style: StampStyle?)
	error("TODO(client-hud): ScreenFX.stamp")
end

-- Pièces (Frames dorées) sur courbe de Bézier d'un point écran vers un élément d'interface
function ScreenFX.flyCoins(_fromScreen: Vector2, _target: GuiObject, _count: number)
	error("TODO(client-hud): ScreenFX.flyCoins")
end

function ScreenFX.floater(_text: string, _screenPos: Vector2, _color: Color3)
	error("TODO(client-hud): ScreenFX.floater")
end

-- Vignette sur les bords (4 Frames à UIGradient) qui pulse
function ScreenFX.vignette(_color: Color3, _duration: number)
	error("TODO(client-hud): ScreenFX.vignette")
end

function ScreenFX.confetti(_count: number)
	error("TODO(client-hud): ScreenFX.confetti")
end

return ScreenFX
