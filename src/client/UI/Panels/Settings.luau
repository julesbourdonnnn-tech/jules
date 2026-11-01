--!strict
-- Settings (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Panneau Réglages (GDD §10.3) : mode Rush / Cozy (SetMode), Cacher mon nom, Recevoir les cadeaux,
-- Clips (caché si la capture vidéo est indisponible), Mouvement réduit, Graphismes légers, Musique,
-- Effets sonores, Vibrations, Emote de la croix
-- ←, Langue ; « BOOP RUSH autorisé » (propriétaire d'un serveur privé) ; Diagnostics
-- (administrateurs) ; message « Tes squishies grandissent même quand tu dors ».

local Settings = {}

-- Construit le contenu une seule fois dans le cadre du panneau
function Settings.build(container: Frame)
	local _ = { container }
	error("TODO(client-panels): Settings.build")
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Settings.open(tab: string?)
	local _ = { tab }
	error("TODO(client-panels): Settings.open")
end

-- Cache le panneau
function Settings.close()
	error("TODO(client-panels): Settings.close")
end

-- Onglets, dans l'ordre (L1 / R1)
function Settings.tabs(): { string }
	error("TODO(client-panels): Settings.tabs")
end

-- Change d'onglet
function Settings.setTab(tab: string)
	local _ = { tab }
	error("TODO(client-panels): Settings.setTab")
end

-- Sélection par défaut (table du GDD §10.6)
function Settings.defaultSelection(): GuiObject?
	error("TODO(client-panels): Settings.defaultSelection")
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function Settings.onBack(): boolean
	error("TODO(client-panels): Settings.onBack")
end

-- Entrée du menu visible pour ce joueur
function Settings.visible(): boolean
	error("TODO(client-panels): Settings.visible")
end

-- Navigateur fourni par PanelController AVANT build (aller vers un autre panneau sans le requérir :
-- pas de require circulaire) ; nav.open(panneau, onglet?), nav.back()
function Settings.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })
	local _ = { nav }
	error("TODO(client-panels): Settings.setNavigator")
end

return Settings
