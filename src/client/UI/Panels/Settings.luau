--!strict
-- Panels/Settings — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * interrupteurs 80 × 48 générés depuis Config/Settings (ordre `order`) : Mode Zen (seulement dans
--     son port sûr, recharge 60 s affichée), Mouvement réduit, Graphismes légers, Musique, Effets
--     sonores, Équipage auto, Refuser les invitations, Langue (Auto / English / Français) ;
--     Coupes désactivées seulement pour le propriétaire d'un serveur privé → SetSetting(key, value)
--   * section Style : styles de file, titres, thèmes de Nid possédés (Config/Cosmetics, sources) →
--     EquipCosmetic(kind, id)
--   * section LiveOps visible seulement si l'attribut Player « Admin » est vrai → AdminCommand
--   * le changement est montré tout de suite (optimiste) puis aligné sur le profil répliqué
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Juice.press + Selectable ; intentions seulement (le serveur valide tout)
-- GDD : §4.16 (Zen), §5.3, §7.6, §9.1 (réglages), §10.3, §13.
-- Dépendances : StateController, Util/Prefs, UI/Theme, UI/Create, UI/Juice, Shared/Net, Logic/Formulas,
-- Config/*, WorldStateController, ScreenFX, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local Panel = {}

Panel.name = "Settings" :: Types.PanelName
Panel.tabs = nil :: { string }?

function Panel.build(_parent: Frame)
	error("TODO(client-panels): Settings.build")
end

function Panel.onOpen(_args: any?)
	error("TODO(client-panels): Settings.onOpen")
end

function Panel.onClose()
	error("TODO(client-panels): Settings.onClose")
end

function Panel.hasAction(): boolean
	error("TODO(client-panels): Settings.hasAction")
end

return Panel
