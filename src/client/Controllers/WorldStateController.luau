--!strict
-- WorldStateController — paquet « client-world » (STUB du contrat : docs/04-architecture.md §13.6).
-- Miroir client du monde, SEUL abonné des remotes de monde ; les autres modules lisent son API et
-- écoutent ses signaux (jamais les remotes directement).
-- Remotes possédés côté client : WorldSnapshot, PathStream, PathSnapshot, LineEvent, SnipEvent,
-- WildEvent, EventState, CrewState, PingShow ; émis : RequestWorld, RequestPath.
-- Responsabilités :
--   * WorldSnapshot à l'arrivée (et sur demande) : files, miettes, sauvages, événements, équipages
--   * miettes : un Trail miroir par slot (Trail.new(170, 0,5)), PathStream décodé par PathCodec
--     (pcall), points de seq ≤ dernier connu ignorés, trou de séquence → RequestPath(slot)
--     (au plus 1 / s par slot), PathSnapshot → reset du miroir ; paquets plus vieux (tick u16) ignorés
--   * files : ops LineEvent et SnipEvent appliquées dans l'ordre STRICT de `ver` par slot (tampon de
--     Balance.Net.VersionBufferSeconds pour les ops en avance, puis RequestWorld) ; op "owner" remet
--     la file et le miroir de miettes du slot à zéro
--   * sauvages : WildEvent (apparitions / disparitions), Nebbies libres portés par SnipEvent et
--     LineEvent "clear" ; ids capturés retirés via LineEvent "add" ; ids retirés gardés 5 s pour
--     ignorer une apparition tardive ; expiration locale à expiresAt
--   * événements (EventState) et équipages (CrewState) ; pings (PingShow)
--   * positions : sauvages (ancre + SeededPath.wander, arc de dispersion), Gloomwisps
--     (SeededPath.newChordCursor), Comète (au sol ou sur le porteur)
-- GDD : §12.4, §12.5, §6.3, §6.4.
-- Dépendances : StateController, Shared/Net, Logic/Trail, Logic/PathCodec, Logic/SeededPath,
-- Logic/WorldLayout, Config/*, Shared/Util/Clock, Shared/Util/Signal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local Trail = require(Shared.Logic.Trail)

local WorldStateController = {}

-- Premier WorldSnapshot appliqué
WorldStateController.Ready = Signal.new() :: Signal.Signal<>
-- Chaque op de file appliquée, dans l'ordre (slot, op)
WorldStateController.LineOp = Signal.new() :: Signal.Signal<number, Types.LineOp>
-- Capture : (slot, code, id du sauvage ou 0, position du sauvage au moment de la capture)
WorldStateController.Caught = Signal.new() :: Signal.Signal<number, Types.NebbyCode, number, Vector3?>
-- Parade : (slot, op bank)
WorldStateController.Banked = Signal.new() :: Signal.Signal<number, Types.LineBankOp>
-- Coupe confirmée par le serveur (effets joués SEULEMENT à ce moment)
WorldStateController.Snipped = Signal.new() :: Signal.Signal<Types.SnipEventPayload>
-- File vidée hors parade : (slot, raison)
WorldStateController.Cleared = Signal.new() :: Signal.Signal<number, string>
-- Nouveau propriétaire d'un slot : (slot, userId ; 0 = libre)
WorldStateController.OwnerChanged = Signal.new() :: Signal.Signal<number, number>
WorldStateController.WildAdded = Signal.new() :: Signal.Signal<Types.WildMirror>
-- (id, raison "expired" | "caught" | "cleared", slot du capteur ou 0)
WorldStateController.WildRemoved = Signal.new() :: Signal.Signal<number, string, number>
-- (nouvel état, ancien état ou nil)
WorldStateController.EventChanged = Signal.new() :: Signal.Signal<Types.EventStatePayload, Types.EventStatePayload?>
WorldStateController.CrewsChanged = Signal.new() :: Signal.Signal<Types.CrewStatePayload>
-- (userId, kind 1-6)
WorldStateController.PingShown = Signal.new() :: Signal.Signal<number, number>

function WorldStateController.Init() end

function WorldStateController.Start() end

function WorldStateController.isReady(): boolean
	error("TODO(client-world): WorldStateController.isReady")
end

-- Slot du joueur local (0 tant qu'inconnu)
function WorldStateController.localSlot(): number
	error("TODO(client-world): WorldStateController.localSlot")
end

function WorldStateController.slotOf(_userId: number): number
	error("TODO(client-world): WorldStateController.slotOf")
end

function WorldStateController.userAt(_slot: number): number
	error("TODO(client-world): WorldStateController.userAt")
end

function WorldStateController.line(_slot: number): Types.LineMirror?
	error("TODO(client-world): WorldStateController.line")
end

function WorldStateController.lineLength(_slot: number): number
	error("TODO(client-world): WorldStateController.lineLength")
end

-- Miroir des miettes serveur du slot (nil si inconnu)
function WorldStateController.trail(_slot: number): Trail.Trail?
	error("TODO(client-world): WorldStateController.trail")
end

function WorldStateController.wilds(): { [number]: Types.WildMirror }
	error("TODO(client-world): WorldStateController.wilds")
end

function WorldStateController.wildPosition(_wild: Types.WildMirror, _t: number): Vector3
	error("TODO(client-world): WorldStateController.wildPosition")
end

function WorldStateController.events(): Types.EventStatePayload?
	error("TODO(client-world): WorldStateController.events")
end

function WorldStateController.wispPosition(_id: number, _t: number): Vector3?
	error("TODO(client-world): WorldStateController.wispPosition")
end

-- Position de la Comète (au sol ou au-dessus du porteur), nil si aucune
function WorldStateController.cometPosition(_t: number): Vector3?
	error("TODO(client-world): WorldStateController.cometPosition")
end

function WorldStateController.crews(): Types.CrewStatePayload
	error("TODO(client-world): WorldStateController.crews")
end

function WorldStateController.crewOf(_userId: number): number
	error("TODO(client-world): WorldStateController.crewOf")
end

-- Équipier du joueur local ?
function WorldStateController.isCrewmate(_userId: number): boolean
	error("TODO(client-world): WorldStateController.isCrewmate")
end

function WorldStateController.requestWorld()
	error("TODO(client-world): WorldStateController.requestWorld")
end

return WorldStateController
