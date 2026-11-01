--!strict
-- SplorchPreview (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Aperçu du Grand Splorch (GDD §4.15) : 3 tuiles « Tu gagnes », animation avant / après, pièces
-- perdues en rouge et « Dépenser d'abord », choix du squishy qui s'envole, case « Filmer », bouton à
-- maintenir 1,5 s (✕), 2e confirmation après un achat récent, « Détails » (deux colonnes, prochain
-- objectif), « Rentre dans ton ranch ».

local SplorchPreview = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function SplorchPreview.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): SplorchPreview.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function SplorchPreview.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): SplorchPreview.open")
end

-- Cache le panneau
function SplorchPreview.close()
	error("TODO(client-panels): SplorchPreview.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function SplorchPreview.tabs(): { string }
	error("TODO(client-panels): SplorchPreview.tabs")
end

-- Change d'onglet
function SplorchPreview.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): SplorchPreview.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function SplorchPreview.defaultSelection(): GuiObject?
	error("TODO(client-panels): SplorchPreview.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function SplorchPreview.onBack(): boolean
	error("TODO(client-panels): SplorchPreview.onBack")
end

-- Entrée du menu visible pour ce joueur
function SplorchPreview.visible(): boolean
	error("TODO(client-panels): SplorchPreview.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function SplorchPreview.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): SplorchPreview.setNavigator")
end

return SplorchPreview
