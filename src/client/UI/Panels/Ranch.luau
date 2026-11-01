--!strict
-- Ranch (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Panneau Ranch (GDD §10.3, §4.10, §4.13, §4.14) : Enclos (grille virtualisée, tri, verrou, Meilleur
-- Ami, monture, cœurs des jumeaux, Tout fusionner, Ranger avec aperçu), Dodo, Lettres, Fusionner
-- (choisir A puis B), Vendre / Relâcher (maintien 0,6 s, confirmation en 2 étapes avec « 1 sur X »),
-- Dalles (acheter d'ici), Style (selle, traînée, titre, thème du ranch, drapeau, tenues possédées →
-- OutfitPreview ; EquipCosmetic / EquipOutfit ; verrouillés avec leur source).

local Ranch = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function Ranch.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): Ranch.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Ranch.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): Ranch.open")
end

-- Cache le panneau
function Ranch.close()
	error("TODO(client-panels): Ranch.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function Ranch.tabs(): { string }
	error("TODO(client-panels): Ranch.tabs")
end

-- Change d'onglet
function Ranch.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): Ranch.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function Ranch.defaultSelection(): GuiObject?
	error("TODO(client-panels): Ranch.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function Ranch.onBack(): boolean
	error("TODO(client-panels): Ranch.onBack")
end

-- Entrée du menu visible pour ce joueur
function Ranch.visible(): boolean
	error("TODO(client-panels): Ranch.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function Ranch.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): Ranch.setNavigator")
end

return Ranch
