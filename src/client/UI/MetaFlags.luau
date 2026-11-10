--!strict
-- MetaFlags (lot B3, décision D2 du plan B3 ; docs/04 §27.3 règles (1)-(2), §27.5 EventState, §27.7
-- « Fait au lot B3 », §27.11 INT-B3-FEATURES) : le SEUL portail du client vers les interrupteurs de la
-- v2.0. Le client ne lit JAMAIS Config/Features : il lit ce que le serveur lui dit.
--
--   MetaFlags.start()          -- idempotent : écoute EventState (WorldStateController) et la version du profil
--   MetaFlags.on(flag)         -- vrai si l'interrupteur `flag` est ouvert sur le serveur (EventState.features.v2)
--   MetaFlags.v2Profile()      -- vrai si le profil répliqué est un profil v2 (clé `version` ≥ 2)
--   MetaFlags.owned()          -- table gelée des interrupteurs lus par Logic/Owned (Owned.flags), refaite
--                              -- seulement quand l'ensemble ouvert change
--   MetaFlags.attr(name)       -- attribut de MON ranch (= UpgradeSnapshot.ranchAttribute) ou nil
--   MetaFlags.myPrestige()     -- "show" (MON Grand Splorch ou MA Jelly Ascend en cours), "queued" (dans la
--                              -- file) ou nil : même lecture que le HUD (queueEntry, myShowNow) ; 2e valeur :
--                              -- la sorte ("splorch" | "ascend"), pour le texte du refus de l'aperçu
--   MetaFlags.Changed          -- fn() quand l'ensemble ouvert ou v2Profile() change
--   MetaFlags._reset()         -- specs : oublie l'état lu (les connexions de start() restent)
--
-- Règles :
--  * EventState.features.v2 (INT-B3-FEATURES) = ensemble des interrupteurs OUVERTS parmi la liste fixe
--    ci-dessous, chacun = true ; clé absente quand aucun n'est ouvert (la configuration livrée) ;
--  * charge vérifiée : `v2` doit être une table (au plus 64 entrées) dont chaque clé est une chaîne et
--    chaque valeur un booléen ; autre chose (nombre, chaîne, valeur non booléenne, clé non chaîne) =
--    TOUT coupé, sans aucune trace ; une clé inconnue de la liste est ignorée ;
--  * une partie v2.0 d'un écran n'existe que si son interrupteur est ouvert ET que le profil est v2 ;
--  * aucun travail par image : lecture paresseuse (l'ensemble est relu seulement quand la table
--    EventState change), signaux du réseau seulement.
--  * mesures de diagnostic de la v2.0 (lot B3, étape 5, D23 ; docs/04 §27.5 ClientMetric) :
--    textScale = arrondi(Text.factor() × 100) (une fois par séance, puis à chaque nouvelle valeur
--    mesurée, 3 envois au plus) et styleFallback = 1 (ombre UIShadow absente) | 2 (dégradé radial
--    absent), une fois par sorte (crochet Theme.onStyleFallback posé dès le chargement : les replis du
--    démarrage comptent). Envoyées par le seau partagé de Widgets.send, au mieux, SEULEMENT tant que
--    EventState.features.v2 est présent (interrupteurs coupés : aucun envoi, trafic de la v1.3) et pas
--    avant METRIC_DELAY s après le premier features.v2 vu (jamais dans la rafale de l'arrivée, où le
--    seau sert à ascendPreview et upgradeMode) : au premier EventState, changement de version ou
--    nouvelle mesure de Text qui suit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Owned = require(Shared.Logic.Owned)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local UpgradeSnapshot = require(Client.UI.UpgradeSnapshot)
local Theme = require(Client.UI.Theme)
local Text = require(Client.UI.Text)
local Widgets = require(Client.UI.Panels.Widgets)

local MetaFlags = {}

MetaFlags.Changed = Signal.new() :: Signal.Signal<>

-- Interrupteurs v2.0 que le serveur peut annoncer (même liste qu'EventService, INT-B3-FEATURES)
MetaFlags.FLAGS = table.freeze({
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
})
local KNOWN: { [string]: boolean } = {}
for _, key in MetaFlags.FLAGS do
	KNOWN[key] = true
end

local MAX_ENTRIES = 64 -- au-delà : charge hostile, tout coupé
local MAX_VERSION = 1000 -- version de schéma plausible

local EMPTY: { [string]: boolean } = table.freeze({})

local started = false
-- dernière table `features.v2` lue (identité), ensemble ouvert qui en est tiré et sa signature
local readFrom: any = nil
local openSet: { [string]: boolean } = EMPTY
local openSig = ""
local ownedCache: Owned.Flags? = nil
-- dernier état annoncé par Changed (signature de l'ensemble ouvert, profil v2)
local lastSignature = ""
local lastV2Profile = false

-- Mesures de diagnostic (D23)
local METRIC_DELAY = 60 -- s après le premier features.v2 vu
local TEXT_MAX = 3 -- envois de textScale au plus par séance
local FALLBACKS: { { kind: string, value: number } } = {
	{ kind = "shadow", value = 1 },
	{ kind = "radial", value = 2 },
}
local v2SeenAt: number? = nil
local textSent = 0
local textLast: number? = nil
local fallbackSeen: { [string]: boolean } = {}
local fallbackSent: { [string]: boolean } = {}

-- Ensemble ouvert tiré d'une valeur `features.v2` (vérifiée : autre chose qu'une table de booléens =
-- tout coupé, sans trace)
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

-- Valeur `features.v2` du dernier EventState (nil sans état, sans features ou sans la clé)
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
	for _, key in MetaFlags.FLAGS do
		if set[key] then
			table.insert(parts, key)
		end
	end
	return table.concat(parts, ",")
end

-- Ensemble ouvert à jour (relu seulement quand la table `features.v2` a changé d'identité ; gardé, avec
-- la table de owned(), tant que le même ensemble revient)
local function current(): { [string]: boolean }
	local raw = rawV2()
	if raw ~= readFrom then
		readFrom = raw
		local fresh = parse(raw)
		local sig = signature(fresh)
		if sig ~= openSig then
			openSet = fresh
			openSig = sig
			ownedCache = nil
		end
	end
	return openSet
end

-- Vrai si l'interrupteur `flag` est ouvert sur le serveur
function MetaFlags.on(flag: string): boolean
	if type(flag) ~= "string" then
		return false
	end
	return current()[flag] == true
end

-- Vrai si le profil répliqué est un profil v2 (entier de 2 à MAX_VERSION)
function MetaFlags.v2Profile(): boolean
	local ok, version = pcall(State.get, "version")
	if not ok then
		return false
	end
	return type(version) == "number"
		and version == version
		and version % 1 == 0
		and version >= 2
		and version <= MAX_VERSION
end

-- Interrupteurs lus par Logic/Owned (Owned.flags), table gelée gardée tant que l'ensemble ne change pas
function MetaFlags.owned(): Owned.Flags
	local set = current()
	local cached = ownedCache
	if cached ~= nil then
		return cached
	end
	local flags = Owned.flags(function(key: string): any
		return set[key] == true
	end)
	local frozen = table.freeze(flags)
	ownedCache = frozen
	return frozen
end

-- Attribut de MON ranch (posé par le serveur quand son interrupteur est ouvert) ou nil
function MetaFlags.attr(name: string): any
	local ok, value = pcall(UpgradeSnapshot.ranchAttribute, name)
	return if ok then value else nil
end

-- MON prestige (Grand Splorch ou Jelly Ascend) : "show" en cours, "queued" dans la file, sinon nil ;
-- 2e valeur : sa sorte (lot B3, étape 2 : l'aperçu dit « Ton Grand Splorch passe d'abord ! » seulement
-- quand c'est un Grand Splorch qui attend). Même lecture que le HUD (queueEntry, myShowNow) :
-- EventState.spectacle.current / .queue, sortes "splorch" et "ascend", userId du joueur local
function MetaFlags.myPrestige(): (("show" | "queued")?, string?)
	local ok, ev = pcall(WorldStateController.event)
	if not ok or type(ev) ~= "table" then
		return nil
	end
	local spectacle = rawget(ev :: any, "spectacle")
	if type(spectacle) ~= "table" then
		return nil
	end
	local player = Players.LocalPlayer
	local me = if player then player.UserId else 0
	if type(me) ~= "number" or me <= 0 then
		return nil
	end
	local cur = rawget(spectacle, "current")
	if type(cur) == "table" then
		local kind = rawget(cur, "kind")
		if (kind == "splorch" or kind == "ascend") and rawget(cur, "userId") == me then
			return "show", kind
		end
	end
	local queue = rawget(spectacle, "queue")
	if type(queue) == "table" then
		for _, entry in queue do
			if type(entry) == "table" then
				local kind = rawget(entry, "kind")
				if (kind == "splorch" or kind == "ascend") and rawget(entry, "userId") == me then
					return "queued", kind
				end
			end
		end
	end
	return nil
end

-- Mesures de diagnostic dues (D23) : seulement après start(), features.v2 présent et METRIC_DELAY s
-- passées depuis le premier features.v2 vu ; un envoi refusé par le seau est retenté au déclencheur
-- suivant (EventState, version, mesure de Text)
local function flushMetrics()
	if not started or next(current()) == nil then
		return
	end
	local now = Clock.now()
	local seen = v2SeenAt
	if seen == nil or now < seen then
		v2SeenAt = now
		return
	end
	if now - seen < METRIC_DELAY then
		return
	end
	if textSent < TEXT_MAX then
		local ok, factor = pcall(Text.factor)
		if ok and type(factor) == "number" and factor == factor and factor > 0 and factor < 100 then
			local value = math.clamp(math.floor(factor * 100 + 0.5), 0, 1000)
			if value ~= textLast and Widgets.send("ClientMetric", "textScale", value) then
				textSent += 1
				textLast = value
			end
		end
	end
	for _, f in FALLBACKS do
		if fallbackSeen[f.kind] and not fallbackSent[f.kind] then
			if not Widgets.send("ClientMetric", "styleFallback", f.value) then
				return
			end
			fallbackSent[f.kind] = true
		end
	end
end

-- Replis de style (Theme, dès le chargement : ceux du démarrage comptent) ; un crochet déjà posé est
-- gardé et appelé d'abord
do
	local previous = Theme.onStyleFallback
	Theme.onStyleFallback = function(kind: string)
		if previous then
			pcall(previous, kind)
		end
		if (kind == "shadow" or kind == "radial") and not fallbackSeen[kind] then
			fallbackSeen[kind] = true
			flushMetrics()
		end
	end
end

-- Relit l'ensemble et la version ; Changed quand l'un des deux a changé depuis la dernière annonce
local function refresh()
	current()
	local sig = openSig
	local v2 = MetaFlags.v2Profile()
	if sig ~= lastSignature or v2 ~= lastV2Profile then
		lastSignature = sig
		lastV2Profile = v2
		MetaFlags.Changed:Fire()
	end
	flushMetrics()
end

-- Écoute EventState et la version du profil (une seule fois, quel que soit le nombre d'appels)
function MetaFlags.start()
	if started then
		return
	end
	started = true
	WorldStateController.EventChanged:Connect(function()
		refresh()
	end)
	State.observe("version", function()
		refresh()
	end)
	-- nouvelle mesure du facteur de texte (taille de texte du joueur changée) : textScale à jour
	Text.onMeasured(function()
		flushMetrics()
	end)
end

-- Specs : oublie l'état lu (les connexions de start() restent)
function MetaFlags._reset()
	readFrom = nil
	openSet = EMPTY
	openSig = ""
	ownedCache = nil
	lastSignature = ""
	lastV2Profile = false
	v2SeenAt = nil
	textSent = 0
	textLast = nil
	table.clear(fallbackSent)
end

-- Mesures envoyées (specs) : envois de textScale, sortes de styleFallback envoyées
function MetaFlags._metrics(): { textScale: number, styleFallback: { string } }
	local kinds: { string } = {}
	for _, f in FALLBACKS do
		if fallbackSent[f.kind] then
			table.insert(kinds, f.kind)
		end
	end
	return { textScale = textSent, styleFallback = kinds }
end

return MetaFlags
