--!strict
-- Shop (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Panneau Boutique (GDD §8) : onglets Passes / Fête / Tenues (aperçu 3D) ; prix lus à l'exécution
-- (Prices.observe) ; articles à id 0 ou hidden cachés (paquets de pièces retirés du lancement,
-- contrat v1.2), onglet absent si tous cachés ; caché les 10 premières minutes ; bouton Squish Party
-- caché pendant une fête ; aucun article caché par PolicyService ; ClientEvent("shopOpened") à chaque
-- ouverture ; sélection tenue pendant la fenêtre d'achat (FocusGuard.hold).

local Shop = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function Shop.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): Shop.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Shop.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): Shop.open")
end

-- Cache le panneau
function Shop.close()
	error("TODO(client-panels): Shop.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function Shop.tabs(): { string }
	error("TODO(client-panels): Shop.tabs")
end

-- Change d'onglet
function Shop.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): Shop.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function Shop.defaultSelection(): GuiObject?
	error("TODO(client-panels): Shop.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function Shop.onBack(): boolean
	error("TODO(client-panels): Shop.onBack")
end

-- Entrée du menu visible pour ce joueur
function Shop.visible(): boolean
	error("TODO(client-panels): Shop.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function Shop.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): Shop.setNavigator")
end

return Shop
