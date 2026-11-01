--!strict
-- Cards (paquet client-hud) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Cartes en jeu (GDD §10.3) et leur file unique (ordre Config/Layout.Cards.Order) : non bloquantes
-- (objectifs à 5:00, nouveaux objectifs, nouvelle entrée du Squishydex, « Garder ton clip ? »,
-- « Wibble revient toujours ! », « Plop a sommeil ») : 8 s à droite, jamais la sélection, puis rangées
-- dans la pastille « ! » ; bloquante : carte du choix Rush / Cozy (ModePrompt, au calme, garde de 0,6
-- s, 20 s → Cozy, FocusGuard). L'écran de retour (client-panels) passe avant tout le monde.
-- « booped » (un de mes squishies s'enfuit) : carte non bloquante avec « Continuer » et « Pas ce
-- joueur » (RefuseBooper). Cards ne lie JAMAIS de touche : la carte en attente se rouvre par le menu
-- (△ / croix ↓ → PanelController, entrée « ! » sélectionnée). Pour ouvrir un panneau (carte
-- d'objectifs, du Squishydex…), Cards émet Requested ; PanelController (plus tardif) l'écoute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

export type Card = {
	id: string,
	kind: string, -- Config/Layout.Cards.Order
	blocking: boolean,
	data: { [string]: any },
}

local Cards = {}

Cards.Changed = Signal.new() :: Signal.Signal<>
-- (sorte de carte, action) : un bouton de carte demande un panneau, ex. ("objectives", "open"),
-- ("dex", "open") ; écouté par PanelController (jamais d'appel direct vers un module plus tardif)
Cards.Requested = Signal.new() :: Signal.Signal<string, string>

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function Cards.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function Cards.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Ajoute une carte ; rend son id
function Cards.push(card: Card): string
	local _ = { card }
	error("TODO(client-hud): Cards.push")
end

-- Retire une carte
function Cards.dismiss(id: string)
	local _ = { id }
	error("TODO(client-hud): Cards.dismiss")
end

-- Cartes rangées (pastille « ! », entrée du menu)
function Cards.pending(): { Card }
	error("TODO(client-hud): Cards.pending")
end

-- Rouvre une carte rangée (depuis le menu)
function Cards.open(id: string)
	local _ = { id }
	error("TODO(client-hud): Cards.open")
end

-- Carte affichée
function Cards.current(): Card?
	error("TODO(client-hud): Cards.current")
end

return Cards
