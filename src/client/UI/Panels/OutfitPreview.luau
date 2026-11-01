--!strict
-- OutfitPreview (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Aperçu 3D d'une tenue (GDD §8.3) avant l'achat et dans la garde-robe : ViewportFrame qui tourne,
-- mettre / retirer sur le squishy choisi (EquipOutfit).

local OutfitPreview = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function OutfitPreview.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): OutfitPreview.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function OutfitPreview.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): OutfitPreview.open")
end

-- Cache le panneau
function OutfitPreview.close()
	error("TODO(client-panels): OutfitPreview.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function OutfitPreview.tabs(): { string }
	error("TODO(client-panels): OutfitPreview.tabs")
end

-- Change d'onglet
function OutfitPreview.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): OutfitPreview.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function OutfitPreview.defaultSelection(): GuiObject?
	error("TODO(client-panels): OutfitPreview.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function OutfitPreview.onBack(): boolean
	error("TODO(client-panels): OutfitPreview.onBack")
end

-- Entrée du menu visible pour ce joueur
function OutfitPreview.visible(): boolean
	error("TODO(client-panels): OutfitPreview.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function OutfitPreview.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): OutfitPreview.setNavigator")
end

return OutfitPreview
