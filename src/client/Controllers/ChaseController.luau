--!strict
-- ChaseController (paquet client-world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Bond et capture côté client (GDD §4.12) : R2 / Maj → bond scripté tout de suite (arc fixe de 12
-- studs en 0,35 s, image par image, arrêt devant le premier solide : LeapRules), Leap(dirX, dirZ)
-- envoyé au serveur ; □ près d'une créature → Catch(id) avec un tampon d'entrée de 0,25 s ; marqueur
-- blanc sur la créature visée ; indicateur de recharge. Bondir et Monter ignorés pendant un portage
-- (son Bump). Les effets de capture ne se jouent qu'après la réponse du serveur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

local ChaseController = {}

ChaseController.Leaped = Signal.new() :: Signal.Signal<>

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function ChaseController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function ChaseController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Bondit si possible (recharge, pas de portage, pas de fenêtre)
function ChaseController.leap(): boolean
	error("TODO(client-world): ChaseController.leap")
end

-- Tente une capture (□) ; garde l'appui 0,25 s si la créature arrive à portée
function ChaseController.tryCatch(): boolean
	error("TODO(client-world): ChaseController.tryCatch")
end

-- Recharge restante du bond
function ChaseController.cooldownLeft(): number
	error("TODO(client-world): ChaseController.cooldownLeft")
end

return ChaseController
