--!strict
-- FocusGuard (paquet client-panels) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- La sélection de la manette n'est jamais perdue ni piégée (GDD §10.6, règles 1 à 8) : une seule
-- source (GuiService.SelectedObject) ; en jeu, aucune sélection (effacée en 0,25 s) ; fenêtre ouverte
-- (menu, panneau, carte bloquante, écran de retour) : sélection toujours dans la fenêtre active,
-- rendue en 0,25 s au dernier objet affiché sinon à la sélection par défaut ; fenêtre de Roblox
-- (achat, invitation, menu système) : sélection tenue 60 s au plus ; fermer rend la sélection à
-- l'ouvreur ; ○ remonte partout ; double appui ignoré (0,35 s) ; chaque sauvetage compté (FocusRescued).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

export type Window = {
	name: string,
	root: GuiObject,
	blocking: boolean,
	default: () -> GuiObject?, -- sélection par défaut (règle de l'écran, GDD §10.6)
	onBack: () -> boolean, -- sous-niveau géré (vrai) ou fermer (faux)
	opener: GuiObject?,
}

local FocusGuard = {}

-- (nom)
FocusGuard.WindowOpened = Signal.new() :: Signal.Signal<string>
-- (nom)
FocusGuard.WindowClosed = Signal.new() :: Signal.Signal<string>

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function FocusGuard.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function FocusGuard.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Ouvre une fenêtre (devient la fenêtre active ; SelectionGroup, comportement Stop)
function FocusGuard.open(window: Window)
	local _ = { window }
	error("TODO(client-panels): FocusGuard.open")
end

-- Ferme une fenêtre et rend la sélection à son ouvreur
function FocusGuard.close(name: string)
	local _ = { name }
	error("TODO(client-panels): FocusGuard.close")
end

-- Fenêtre active
function FocusGuard.top(): Window?
	error("TODO(client-panels): FocusGuard.top")
end

-- Au moins une fenêtre ouverte (touches du jeu déliées)
function FocusGuard.anyOpen(): boolean
	error("TODO(client-panels): FocusGuard.anyOpen")
end

-- ○ / Retour arrière : remonte d'un niveau (vrai si géré)
function FocusGuard.back(): boolean
	error("TODO(client-panels): FocusGuard.back")
end

-- Tient la sélection pendant une fenêtre de Roblox (60 s au plus)
function FocusGuard.hold(seconds: number?)
	local _ = { seconds }
	error("TODO(client-panels): FocusGuard.hold")
end

-- Fin de la fenêtre de Roblox
function FocusGuard.release()
	error("TODO(client-panels): FocusGuard.release")
end

-- Sauvetages comptés dans la session (specs)
function FocusGuard.rescues(): number
	error("TODO(client-panels): FocusGuard.rescues")
end

return FocusGuard
