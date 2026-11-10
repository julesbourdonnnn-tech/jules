--!strict
-- Flags (lot B5, étape 1 ; décision D2 du plan B5 ; docs/04 §27.3 règles (1)-(2), §27.5 EventState,
-- §27.11 INT-B3-FEATURES et INT-B5-FEATURES) : le portail du RENDU vers les interrupteurs de la v2.0.
-- Le client ne lit JAMAIS Config/Features : il lit ce que le serveur lui dit dans
-- EventState.features.v2 (l'ensemble des interrupteurs OUVERTS d'une liste fixe, chacun = true ; clé
-- absente quand aucun n'est ouvert, la configuration livrée).
--
--   Flags.on(name)   -- vrai si l'interrupteur `name` est ouvert sur le serveur
--   Flags.Changed    -- fn() quand l'ensemble ouvert a changé (déjà à jour quand il part)
--   Flags.FLAGS      -- la liste fixe (la même que UI/MetaFlags.FLAGS et qu'EventService)
--   Flags._reset()   -- specs : relit le dernier EventState du miroir
--
-- Pourquoi un second lecteur à côté de UI/MetaFlags : MetaFlags charge Theme, Text, Widgets et
-- UpgradeSnapshot, qui ne doivent pas se charger depuis la chaîne de RanchRenderer (10e module du
-- client) ; ce module ne dépend que du miroir (WorldStateController) et de Shared, et ne charge
-- jamais un module d'écran. Les écrans du lot B5 lisent UI/MetaFlags ; les deux lecteurs donnent la
-- même réponse pour chaque interrupteur et chaque charge (spec WorldFlags).
--
-- Règles :
--  * charge vérifiée comme dans UI/MetaFlags : `v2` doit être une table (au plus 64 entrées) dont
--    chaque clé est une chaîne et chaque valeur un booléen ; autre chose = TOUT coupé, sans aucune
--    trace ; une clé hors de la liste est ignorée ;
--  * aucun travail par image : l'ensemble est recalculé seulement quand EventState arrive
--    (WorldStateController.EventChanged, écouté dès le chargement du module, donc avant ceux qui le
--    requièrent) ; on() est une lecture de table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

local Client = script.Parent.Parent
local WorldStateController = require(Client.Controllers.WorldStateController)

local Flags = {}

Flags.Changed = Signal.new() :: Signal.Signal<>

-- Interrupteurs v2.0 que le serveur peut annoncer (EventService.V2_CLIENT_FLAGS, UI/MetaFlags.FLAGS)
Flags.FLAGS = table.freeze({
	"RecordR",
	"JellyAscend",
	"PetitSplorch",
	"Confetti",
	"Workshop",
	"Carnet",
	"WeeklyTrack",
	"Mastery",
	"RanchSkins",
	"DecoPerso",
	"Hearts",
	"Personalities",
	"PhotoMode",
})
local KNOWN: { [string]: boolean } = {}
for _, key in Flags.FLAGS do
	KNOWN[key] = true
end

local MAX_ENTRIES = 64 -- au-delà : charge hostile, tout coupé

local EMPTY: { [string]: boolean } = table.freeze({})

local openSet: { [string]: boolean } = EMPTY
local openSig = ""

-- Ensemble ouvert tiré d'une valeur `features.v2` (autre chose qu'une table de booléens : tout coupé)
local function parse(raw: any): { [string]: boolean }
	if type(raw) ~= "table" then
		return EMPTY
	end
	local out: { [string]: boolean } = {}
	local n = 0
	for key, value in raw do
		n += 1
		if n > MAX_ENTRIES or type(key) ~= "string" or type(value) ~= "boolean" then
			return EMPTY
		end
		if value == true and KNOWN[key] then
			out[key] = true
		end
	end
	if next(out) == nil then
		return EMPTY
	end
	return table.freeze(out)
end

-- Valeur `features.v2` du dernier EventState du miroir (nil sans état, sans features ou sans la clé)
local function rawV2(): any
	local ok, ev = pcall(WorldStateController.event)
	if not ok or type(ev) ~= "table" then
		return nil
	end
	local features = rawget(ev :: any, "features")
	if type(features) ~= "table" then
		return nil
	end
	return rawget(features, "v2")
end

-- Signature stable d'un ensemble ouvert (ordre de la liste)
local function signature(set: { [string]: boolean }): string
	local parts = {}
	for _, key in Flags.FLAGS do
		if set[key] then
			table.insert(parts, key)
		end
	end
	return table.concat(parts, ",")
end

-- Relit l'ensemble ; Changed quand il a changé
local function refresh()
	local fresh = parse(rawV2())
	local sig = signature(fresh)
	if sig ~= openSig then
		openSet = fresh
		openSig = sig
		Flags.Changed:Fire()
	end
end

-- Vrai si l'interrupteur `name` est ouvert sur le serveur
function Flags.on(name: string): boolean
	if type(name) ~= "string" then
		return false
	end
	return openSet[name] == true
end

-- Specs : oublie l'ensemble lu puis relit le dernier EventState du miroir
function Flags._reset()
	openSet = EMPTY
	openSig = ""
	refresh()
end

-- Une seule connexion pour la séance, posée au chargement (les modules qui requièrent celui-ci
-- branchent leurs propres écoutes plus tard : ils voient toujours l'ensemble à jour)
WorldStateController.EventChanged:Connect(refresh)
refresh()

return Flags
