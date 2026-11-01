--!strict
-- Squishydex (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Panneau Squishydex (GDD §4.17) : Espèces (26 pages, silhouettes grises), Mutations (grille 26 ×
-- 9), Familles (bonus), Étoiles, Guide (toutes les probabilités, protection contre la malchance,
-- règles du BOOP RUSH) ; jalons à réclamer ; nombres géants avec le mot entier.

local Squishydex = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function Squishydex.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): Squishydex.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Squishydex.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): Squishydex.open")
end

-- Cache le panneau
function Squishydex.close()
	error("TODO(client-panels): Squishydex.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function Squishydex.tabs(): { string }
	error("TODO(client-panels): Squishydex.tabs")
end

-- Change d'onglet
function Squishydex.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): Squishydex.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function Squishydex.defaultSelection(): GuiObject?
	error("TODO(client-panels): Squishydex.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function Squishydex.onBack(): boolean
	error("TODO(client-panels): Squishydex.onBack")
end

-- Entrée du menu visible pour ce joueur
function Squishydex.visible(): boolean
	error("TODO(client-panels): Squishydex.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function Squishydex.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): Squishydex.setNavigator")
end

return Squishydex
