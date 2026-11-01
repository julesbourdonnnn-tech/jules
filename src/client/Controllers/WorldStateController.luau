--!strict
-- WorldStateController (paquet client-world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Miroir client de l'état du monde (GDD §12.5) : ranchs (RanchSnapshot, RanchPatch numérotés : un
-- trou → RequestWorld), clôtures (Fence), créatures (ChaseEvent : pos(t) par SeededPath ; une
-- créature dont l'heure de fin est passée disparaît même sans « finish »), événements (EventState,
-- MegaBeat ; phases recalculées par EventClock entre deux messages), boops (BoopState), emotes
-- (EmoteShow). Applique EventState.offset à Clock. Jamais d'état faux durable : après un trou, les
-- patchs sont ignorés et RequestWorld est renvoyé toutes les 3 s (StateTimeouts worldResync, jamais
-- plus vite que le débit d'Intents) jusqu'à l'instantané suivant. RanchPublic.best toujours présent
-- (s = 0 : aucune silhouette). Start envoie UNE fois ReportBlocked avec
-- StarterGui:GetCore("GetBlockedUserIds") sous pcall (liste vide en cas d'échec ; contrat v1.2, A21).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local WorldStateController = {}

-- (slot, champs changés)
WorldStateController.RanchChanged = Signal.new() :: Signal.Signal<number, { string }>
-- (slot, uid, op)
WorldStateController.SquishyChanged = Signal.new() :: Signal.Signal<number, string, string>
-- (slot)
WorldStateController.FenceChanged = Signal.new() :: Signal.Signal<number>
WorldStateController.CreatureSpawned = Signal.new() :: Signal.Signal<Types.ChaseSpawn>
WorldStateController.CreatureFinished = Signal.new() :: Signal.Signal<Types.ChaseFinish>
WorldStateController.EventChanged = Signal.new() :: Signal.Signal<Types.EventStatePayload>
WorldStateController.MegaBeat = Signal.new() :: Signal.Signal<Types.MegaBeatPayload>
WorldStateController.BoopChanged = Signal.new() :: Signal.Signal<Types.BoopStatePayload>
WorldStateController.EmoteShown = Signal.new() :: Signal.Signal<Types.EmoteShowPayload>

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function WorldStateController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function WorldStateController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Premier RanchSnapshot reçu
function WorldStateController.ready(): boolean
	error("TODO(client-world): WorldStateController.ready")
end

-- Ranch du joueur local
function WorldStateController.mySlot(): number
	error("TODO(client-world): WorldStateController.mySlot")
end

-- État public d'un ranch
function WorldStateController.ranch(slot: number): Types.RanchPublic?
	local _ = { slot }
	error("TODO(client-world): WorldStateController.ranch")
end

-- Squishies visibles d'un ranch
function WorldStateController.squishies(slot: number): { [string]: Types.PublicSquishy }
	local _ = { slot }
	error("TODO(client-world): WorldStateController.squishies")
end

-- Taille prédite (z + G(t) − zg)
function WorldStateController.sizeOf(slot: number, uid: string, t: number?): number
	local _ = { slot, uid, t }
	error("TODO(client-world): WorldStateController.sizeOf")
end

-- Clôture d'un ranch (uids, raison)
function WorldStateController.fence(slot: number): ({ string }, string)
	local _ = { slot }
	error("TODO(client-world): WorldStateController.fence")
end

-- Créatures actives visibles par ce joueur
function WorldStateController.creatures(): { [number]: Types.ChaseSpawn }
	error("TODO(client-world): WorldStateController.creatures")
end

-- Position d'une créature (SeededPath)
function WorldStateController.creaturePos(id: number, t: number?): Vector3?
	local _ = { id, t }
	error("TODO(client-world): WorldStateController.creaturePos")
end

-- Dernier EventState
function WorldStateController.event(): Types.EventStatePayload?
	error("TODO(client-world): WorldStateController.event")
end

-- Maintiens de boop en cours (clé « booperId:ownerId:uid »)
function WorldStateController.boops(): { [string]: Types.BoopStatePayload }
	error("TODO(client-world): WorldStateController.boops")
end

return WorldStateController
