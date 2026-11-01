--!strict
-- Diagnostics (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Panneau Diagnostics (GDD §12.11), administrateurs seulement : Ce serveur, Mon client (images par
-- seconde, mémoire, ping, instances, connexions, qualité, erreurs du client), Aujourd'hui ; ✕ sur
-- une ligne ouvre ses 3 exemples ; texte 32 px TV, heure et version en haut, fait pour être
-- photographié ; RequestDiagnostics (1 / 2 s) ; Outils (AdminCommand : forcer un Rush ou un MEGA,
-- horloge en Studio, erreurs de test serveur et client, mode photo, fête). Visible seulement après
-- le DiagnosticsSnapshot « bonjour » (tab 0) que le serveur envoie aux administrateurs.

local Diagnostics = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function Diagnostics.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): Diagnostics.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Diagnostics.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): Diagnostics.open")
end

-- Cache le panneau
function Diagnostics.close()
	error("TODO(client-panels): Diagnostics.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function Diagnostics.tabs(): { string }
	error("TODO(client-panels): Diagnostics.tabs")
end

-- Change d'onglet
function Diagnostics.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): Diagnostics.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function Diagnostics.defaultSelection(): GuiObject?
	error("TODO(client-panels): Diagnostics.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function Diagnostics.onBack(): boolean
	error("TODO(client-panels): Diagnostics.onBack")
end

-- Entrée du menu visible pour ce joueur
function Diagnostics.visible(): boolean
	error("TODO(client-panels): Diagnostics.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function Diagnostics.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): Diagnostics.setNavigator")
end

return Diagnostics
