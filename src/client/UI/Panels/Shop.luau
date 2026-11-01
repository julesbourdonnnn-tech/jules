--!strict
-- Shop (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Panneau Boutique (GDD §8) : Passes, Fête et pièces, Tenues (aperçu 3D) ; prix lus à l'exécution
-- (Prices.observe) ; articles à id 0 cachés, onglet absent si tous à 0 ; caché les 10 premières
-- minutes ; paquets cachés par PolicyService ou quand « Grand Splorch prêt ! » ; sélection tenue
-- pendant la fenêtre d'achat (FocusGuard.hold).

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
