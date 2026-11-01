--!strict
-- PromptController (paquet client-world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Cible choisie par le jeu (GDD §10.4) avec Logic/TargetRules : squishies de son ranch à ≤ 10 studs
-- (prêts d'abord pour □), 4 squishies d'une clôture (boop, pet-sitting), dalle sous les pieds, bol,
-- Bassin quand on porte, Pot, comptoir de la Boutique, MEGA ; créature visée par le bond (position
-- future, LeapRules.aim) ; cycle L1 / R1 ; clic souris par projection (4 s) ; cible verrouillée
-- pendant un maintien. Actions de chaque cible (□ principale, ○ secondaire) pour UI/Prompt et
-- InputController. Aucune action si une fenêtre est ouverte.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

export type Target = {
	kind: "squishy" | "fence" | "pad" | "bowl" | "pool" | "pot" | "shop" | "mega" | "creature",
	slot: number,
	uid: string,
	id: number,
	tile: string,
	ready: boolean,
	primary: string, -- action de □ : "press" | "throw" | "fusion" | "putInPool" | "buy" | "boop" | "feed" | "catch" | "sell" | "shop" | "petsit" | ""
	secondary: string, -- action de ○ : "pickup" | "putdown" | ""
	position: Vector3,
}

local PromptController = {}

-- (nouvelle cible)
PromptController.Changed = Signal.new() :: Signal.Signal<Target?>

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function PromptController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function PromptController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Cible de l'action principale
function PromptController.current(): Target?
	error("TODO(client-world): PromptController.current")
end

-- L1 (−1) / R1 (+1)
function PromptController.cycle(dir: number)
	local _ = { dir }
	error("TODO(client-world): PromptController.cycle")
end

-- Clic souris : fixe la cible 4 s si un candidat est désigné
function PromptController.clickAt(screen: Vector2): boolean
	local _ = { screen }
	error("TODO(client-world): PromptController.clickAt")
end

-- Verrouille la cible pendant un maintien (boop, bol)
function PromptController.lock(kind: string)
	local _ = { kind }
	error("TODO(client-world): PromptController.lock")
end

-- Fin du maintien
function PromptController.unlock()
	error("TODO(client-world): PromptController.unlock")
end

-- Après une pression : passe au prochain prêt en 0,15 s
function PromptController.afterPress()
	error("TODO(client-world): PromptController.afterPress")
end

-- Créature visée par le prochain bond
function PromptController.leapTarget(): number?
	error("TODO(client-world): PromptController.leapTarget")
end

return PromptController
