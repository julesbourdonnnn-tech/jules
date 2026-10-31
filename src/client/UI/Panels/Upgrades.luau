--!strict
-- Panels/Upgrades — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * 5 cartes (Conga, Foulée, Attrait, Perchoirs, Guard Links) : icône, niveau, effet actuel →
--     suivant, prix (Formulas.upgradeCost), bouton Acheter 96 px → remote BuyUpgrade(track) ;
--     la carte achetable la moins chère pulse ; MAX au plafond (Formulas.upgradeMaxLevel)
--   * prix et disponibilité calculés sur le Glow PRÉDIT ; refus : secousse ±6 px + contour rouge
--     (le serveur reste seul juge : Feedback notEnoughGlow)
--   * barre de stat remplie en 0,3 s et niveau qui défile à la confirmation (profil répliqué)
--   * accueil : args.focus = "conga" → une seule carte en surbrillance, fermeture auto 0,6 s après
--     l'achat
--   * bouton Supernova en bas avec anneau de progression (glow / Formulas.supernovaCost(R)) →
--     PanelController.open("Supernova")
--   * hasAction : une amélioration est achetable
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Juice.press + Selectable ; intentions seulement (le serveur valide tout)
-- GDD : §4.11, §3 (18-22 s), §9.2, §9.4 (Amélioration), §10.3.
-- Dépendances : StateController, Util/Prefs, UI/Theme, UI/Create, UI/Juice, Shared/Net, Logic/Formulas,
-- Config/*, WorldStateController, ScreenFX, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local Panel = {}

Panel.name = "Upgrades" :: Types.PanelName
Panel.tabs = nil :: { string }?

function Panel.build(_parent: Frame)
	error("TODO(client-panels): Upgrades.build")
end

function Panel.onOpen(_args: any?)
	error("TODO(client-panels): Upgrades.onOpen")
end

function Panel.onClose()
	error("TODO(client-panels): Upgrades.onClose")
end

function Panel.hasAction(): boolean
	error("TODO(client-panels): Upgrades.hasAction")
end

return Panel
