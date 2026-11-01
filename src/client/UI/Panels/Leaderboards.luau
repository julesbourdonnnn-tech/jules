--!strict
-- Leaderboards (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Panneau Classements (GDD §6.9) : 5 onglets ; d'abord ma place sur ce serveur et mon record contre
-- la semaine dernière, puis le top 10 mondial (LeaderboardState).

local Leaderboards = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function Leaderboards.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): Leaderboards.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Leaderboards.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): Leaderboards.open")
end

-- Cache le panneau
function Leaderboards.close()
	error("TODO(client-panels): Leaderboards.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function Leaderboards.tabs(): { string }
	error("TODO(client-panels): Leaderboards.tabs")
end

-- Change d'onglet
function Leaderboards.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): Leaderboards.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function Leaderboards.defaultSelection(): GuiObject?
	error("TODO(client-panels): Leaderboards.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function Leaderboards.onBack(): boolean
	error("TODO(client-panels): Leaderboards.onBack")
end

-- Entrée du menu visible pour ce joueur
function Leaderboards.visible(): boolean
	error("TODO(client-panels): Leaderboards.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function Leaderboards.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): Leaderboards.setNavigator")
end

return Leaderboards
