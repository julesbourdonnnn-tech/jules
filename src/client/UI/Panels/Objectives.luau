--!strict
-- Objectives (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Panneau Objectifs (GDD §7.3, §7.4) : Aujourd'hui (3 objectifs, réclamer, relance), Plop (jours au
-- total, paliers), Accueil (tant qu'il n'est pas fini).

local Objectives = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function Objectives.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): Objectives.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Objectives.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): Objectives.open")
end

-- Cache le panneau
function Objectives.close()
	error("TODO(client-panels): Objectives.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function Objectives.tabs(): { string }
	error("TODO(client-panels): Objectives.tabs")
end

-- Change d'onglet
function Objectives.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): Objectives.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function Objectives.defaultSelection(): GuiObject?
	error("TODO(client-panels): Objectives.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function Objectives.onBack(): boolean
	error("TODO(client-panels): Objectives.onBack")
end

-- Entrée du menu visible pour ce joueur
function Objectives.visible(): boolean
	error("TODO(client-panels): Objectives.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function Objectives.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): Objectives.setNavigator")
end

return Objectives
