--!strict
-- Panels/ReturnScreen — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * écran de retour (Celebrate "offline" : data = { glow, seconds, nightShift }) :
--     « Pendant ton absence (5 h 12) : +1,24 M Glow », compteur qui défile 0,8 s Quint Out, fontaine
--     de pièces, bouton « Super ! » 96 px ; ligne discrète « Night Shift : 75 % pendant 12 h » si
--     le pass n'est pas possédé (jamais insistante)
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Juice.press + Selectable ; intentions seulement (le serveur valide tout)
-- GDD : §7.2, §9.4 (Retour hors ligne), §10.3.
-- Dépendances : StateController, Util/Prefs, UI/Theme, UI/Create, UI/Juice, Shared/Net, Logic/Formulas,
-- Config/*, WorldStateController, ScreenFX, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local Panel = {}

Panel.name = "ReturnScreen" :: Types.PanelName
Panel.tabs = nil :: { string }?

function Panel.build(_parent: Frame)
	error("TODO(client-panels): ReturnScreen.build")
end

function Panel.onOpen(_args: any?)
	error("TODO(client-panels): ReturnScreen.onOpen")
end

function Panel.onClose()
	error("TODO(client-panels): ReturnScreen.onClose")
end

function Panel.hasAction(): boolean
	error("TODO(client-panels): ReturnScreen.hasAction")
end

-- Ouvre l'écran avec les données de Celebrate "offline"
function Panel.present(_data: { [string]: any })
	error("TODO(client-panels): ReturnScreen.present")
end

return Panel
