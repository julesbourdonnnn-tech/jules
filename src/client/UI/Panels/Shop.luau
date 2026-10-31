--!strict
-- Panels/Shop — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * Passes : 6 cartes (Config/Monetization.Passes, id 0 = masqué), prix lus à l'exécution via
--     Client/Util/Prices (repli : prix de la config), « Possédé » (profile.passes),
--     MarketplaceService:PromptGamePassPurchase
--   * Boosts & Glow : produits avec montant « ≈ » calculé côté client (idleRate × idleSeconds,
--     minGlow) ; Glow Party masquée si EventState.serverBoost glowParty a plus de
--     Balance.GlowParty.HideAbove s restantes ; Starter Kit visible tant que profile.starterKit est
--     faux, sans compte à rebours ; MarketplaceService:PromptProductPurchase
--   * Codes : champ + Valider → RedeemCode (RemoteFunction) ; statut → "code.<status>"
--   * aucun faux minuteur, prix en Robux toujours visible
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Juice.press + Selectable ; intentions seulement (le serveur valide tout)
-- GDD : §8, §4.17 (Glow Party), §10.3.
-- Dépendances : StateController, Util/Prefs, UI/Theme, UI/Create, UI/Juice, Shared/Net, Logic/Formulas,
-- Config/*, WorldStateController, ScreenFX, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local Panel = {}

Panel.name = "Shop" :: Types.PanelName
Panel.tabs = { "shop.tab.passes", "shop.tab.boosts", "shop.tab.codes" } :: { string }?

function Panel.build(_parent: Frame)
	error("TODO(client-panels): Shop.build")
end

function Panel.onOpen(_args: any?)
	error("TODO(client-panels): Shop.onOpen")
end

function Panel.onClose()
	error("TODO(client-panels): Shop.onClose")
end

function Panel.hasAction(): boolean
	error("TODO(client-panels): Shop.hasAction")
end

function Panel.selectTab(_tab: string)
	error("TODO(client-panels): Shop.selectTab")
end

return Panel
