--!strict
-- Panels/Supernova — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * aperçu obligatoire : deux colonnes « Tu gardes » / « Remis à zéro », gains de la prochaine
--     Supernova (+40 % de revenu, +5 au plafond Conga, Dash −0,25 s, aura), coût et Glow prédit —
--     calculés côté client avec Logic/Formulas et Config (mêmes règles que
--     EconomyService.supernovaPreview)
--   * bouton à MAINTENIR Balance.Supernova.HoldSeconds (1 s) avec anneau → remote Supernova()
--   * hors du port sûr de son Nid : message « Rentre au Nid » (bouton désactivé)
--   * back() → Upgrades
--   * hasAction : Glow ≥ coût
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Juice.press + Selectable ; intentions seulement (le serveur valide tout)
-- GDD : §4.12, §10.3, §9.4 (Supernova).
-- Dépendances : StateController, Util/Prefs, UI/Theme, UI/Create, UI/Juice, Shared/Net, Logic/Formulas,
-- Config/*, WorldStateController, ScreenFX, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local Panel = {}

Panel.name = "Supernova" :: Types.PanelName
Panel.tabs = nil :: { string }?

function Panel.build(_parent: Frame)
	error("TODO(client-panels): Supernova.build")
end

function Panel.onOpen(_args: any?)
	error("TODO(client-panels): Supernova.onOpen")
end

function Panel.onClose()
	error("TODO(client-panels): Supernova.onClose")
end

function Panel.hasAction(): boolean
	error("TODO(client-panels): Supernova.hasAction")
end

return Panel
