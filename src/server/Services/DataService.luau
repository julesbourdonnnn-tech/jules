--!strict
-- DataService : sauvegarde joueur sans perte (reprise de Comet Conga avec tous ses correctifs).
--  * verrou de session (un seul serveur écrit les données d'un joueur). Verrou frais d'un autre
--    serveur : repris seulement après LOAD_ATTEMPTS - 1 lectures RÉUSSIES qui l'ont vu (≥ 30 s
--    d'observation, DataStore en marche), jamais parce que des erreurs ont épuisé les essais :
--    sinon renvoi poli sans rien écrire (son serveur réessaie peut-être encore sa sauvegarde de
--    départ après une panne, toutes les RELEASE_RETRY_MAX = 16 s au plus) — correctif final de
--    Comet Conga (Fix_final_data_lock)
--  * UpdateAsync partout, retries avec backoff, autosave, BindToClose
--  * sauvegarde de départ en échec sur une panne DataStore (verrou toujours à nous) : le serveur
--    continue avec les autres joueurs, il réessaie donc en arrière-plan (même instantané, crochets
--    onBeforeSave jamais rejoués, même jeton de session) avec un backoff plafonné pendant
--    RELEASE_RETRY_WINDOW s ; arrêt au premier succès ou verrou perdu. Une reconnexion sur ce
--    serveur attend (REJOIN_WAIT, essais rapprochés) puis est renvoyée poliment : jamais de données
--    périmées. BindToClose attend ces essais (dernier essai complet, dans CLOSE_TIMEOUT)
--  * schéma versionné (Data/Schema.luau) : defaults + migrations + reconcile
--  * réplication vers le client : instantané au chargement, puis patchs groupés par frame
--    (clés entières, ou entrées d'une grande table : DataPatch(patch, removed, entries?))
--  * arrivée sous le budget réseau : une grande table (Schema.STREAMED_KEYS, ex. la collection de
--    créatures) ne part dans l'instantané qu'avec ses SNAPSHOT_INLINE premières entrées (ordre
--    setStreamOrder : les plus utiles d'abord) ; le reste suit en entrées DataPatch de STREAM_CHUNK
--    toutes les STREAM_INTERVAL s, après STREAM_DELAY s (horloge partagée Clock) : le client
--    (StateController) les applique comme n'importe quel patch. Aucune connexion Heartbeat : une
--    boucle task.spawn ne vit que tant qu'un flux est en cours (lancée par l'instantané, finie à vide)
--  * une écriture n'a lieu que si CETTE session détient encore le verrou (même JobId ET même jeton) :
--    verrou absent, étranger ou d'une autre session = session terminée, jamais d'écrasement
--  * profil écrit par un schéma PLUS RÉCENT (serveur déjà mis à jour) : jamais réparé, jamais
--    réécrit, aucun verrou pris ; le joueur est renvoyé vers un serveur à jour
--  * verrou de session marqué d'un jeton par chargement (reconnexion sur le même serveur)
--  * attribut répliqué Player « ProfileLoading » = numéro d'essai (> 0) tant que le chargement
--    attend (sauvegarde de départ d'une reconnexion, verrou d'un autre serveur, backoff) ; nil dès
--    que loadRecord a rendu sa réponse (avant l'instantané ou le renvoi) : l'écran de chargement
--    (src/first/Loading.client) retient « Réessayer » tant qu'il est posé
--  * repli en mémoire dans Studio SEULEMENT, quand l'accès API est désactivé. Serveur en ligne :
--    GetDataStore en échec = DataStore indisponible, jamais de repli en mémoire (une session jamais
--    sauvegardée, des achats Robux acquittés puis perdus) ; nouvel essai en arrière-plan avec
--    backoff, et d'ici là chaque chargement échoue (renvoi LOAD_FAILED_MESSAGE) : aucun profil créé
--  * chaque écriture UpdateAsync d'un profil passe { UserId } (clé liée au joueur pour les demandes
--    d'effacement de données personnelles de Roblox)
--
-- API :
--   DataService.get(player) -> données vivantes ou nil (pas encore chargées)
--   DataService.isLoaded(player) -> boolean
--   DataService.waitFor(player, timeout?) -> données ou nil
--   DataService.Loaded:Connect(function(player, data) end)
--   DataService.set(player, key, value)          -- clé de 1er niveau + réplication
--   DataService.increment(player, key, delta)    -- nombres (delta fini)
--   DataService.markDirty(player, key)           -- après mutation d'une table imbriquée (clé entière)
--   DataService.markDirtyEntry(player, key, sub) -- une seule entrée data[key][sub] a changé (ou a
--                                                   été supprimée) : seule l'entrée est envoyée
--   DataService.saveNow(player) -> boolean       -- sauvegarde immédiate (achats) ; false après la
--                                                   sauvegarde de libération (départ, BindToClose)
--   DataService.onBeforeSave(fn)                 -- fn(player, data, release) juste avant chaque
--                                                   écriture ; release = true pour la sauvegarde de
--                                                   départ / BindToClose (règlement d'un revenu
--                                                   passif, travail « de départ »)
--   DataService.onPrepare(fn)                    -- fn(player, data) au chargement, sans yield, APRÈS
--                                                   migrate + reconcile (+ réparation) et AVANT
--                                                   l'instantané et Loaded (rebase hors ligne)
--   DataService.setStreamOrder(key, fn)          -- fn(data) -> sous-clés de data[key] par priorité
--                                                   d'envoi (instantané puis flux) ; sans crochet :
--                                                   ordre quelconque
--   DataService.setPatchExtra(name, fn)          -- (lot A2, v2.0) valeur DÉRIVÉE ajoutée sous `name`
--                                                   à l'instantané et aux patchs : fn(player, data,
--                                                   clés du patch ou nil pour l'instantané) -> valeur
--                                                   ou nil (rien n'est ajouté, aucun patch de plus)
--   DataService.isClosing(player) -> boolean     -- (lot A2) sauvegarde de libération commencée ou
--                                                   faite (départ, BindToClose) : toute mutation
--                                                   serait perdue, un achat est refusé
--   DataService.Settings                         -- délais (modifiables par les tests avant Start)
--   DataService.usingMemoryStore                 -- vrai seulement dans Studio sans accès API

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Signal = require(Shared.Util.Signal)
local Tables = require(Shared.Util.Tables)
local Types = require(Shared.Types)
local Schema = require(script.Parent.Parent.Data.Schema)
local ProfileRepair = require(script.Parent.Parent.Data.ProfileRepair)
local Signals = require(script.Parent.Parent.Signals)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)

-- Réglages (modifiables par les tests avant le démarrage)
local Settings = {
	LOCK_EXPIRY = 30 * 60, -- un verrou plus vieux que 30 min est considéré abandonné
	LOAD_ATTEMPTS = 6,
	-- s entre deux lectures du verrou frais d'un autre serveur : 5 lectures × 6 s = 30 s
	-- d'observation ≥ RELEASE_RETRY_MAX + 10 (invariant ci-dessous). Comet Conga : 5 s pour 12
	-- joueurs ; 6 s ici car RELEASE_RETRY_MAX passe à 16 (serveur de 16 joueurs, voir plus bas)
	LOCKED_RETRY_DELAY = 6,
	RETRY_BASE_DELAY = 1, -- backoff : 2, 4, 8… × base
	SAVE_ATTEMPTS = 4,
	AUTOSAVE_INTERVAL = 90,
	CLOSE_TIMEOUT = 25,
	-- reconnexion sur le même serveur : attente max de la sauvegarde de départ de l'ancienne session
	REJOIN_WAIT = 25,
	-- sauvegarde de départ en échec (panne DataStore, verrou toujours à nous) : nouveaux essais en
	-- arrière-plan tant que le serveur vit, après 5 s, puis 10, 16, 16… pendant au plus
	-- RELEASE_RETRY_WINDOW s (une panne DataStore dure souvent de 1 à 5 min). RELEASE_RETRY_MAX + 10
	-- ≤ LOCKED_RETRY_DELAY × (LOAD_ATTEMPTS - 1) : après la panne, ce serveur écrit et libère le
	-- verrou bien avant qu'un autre serveur (reconnexion ailleurs) l'ait observé assez pour le
	-- reprendre. 60 / 16 = 3,75 essais par minute et par joueur parti : un serveur PLEIN de 16
	-- joueurs tous partis pendant la panne reste sous le budget de base d'UpdateAsync (60 par minute)
	RELEASE_RETRY_DELAY = 5,
	RELEASE_RETRY_MAX = 16,
	RELEASE_RETRY_WINDOW = 300,
	-- s entre deux réveils pendant l'attente (arrêt du serveur ou reconnexion : essai aussitôt)
	RELEASE_RETRY_POLL = 0.25,
	-- grandes tables (Schema.STREAMED_KEYS) : entrées dans l'instantané, puis flux d'entrées
	-- DataPatch (≈ 65 o par entrée : 24 entrées ≈ 1,6 Ko, 13 Ko/s pendant le flux). 24 = les squishies
	-- visibles au plus (enclos et Bassin, premiers de l'ordre de SquishyService) : lot I (journal I-8),
	-- le profil v2 (≈ 1,25 Ko de plus) dépassait sinon les 8 Ko de la seconde d'arrivée d'un vétéran
	SNAPSHOT_INLINE = 24,
	STREAM_CHUNK = 50,
	STREAM_INTERVAL = 0.25, -- s entre deux morceaux
	STREAM_DELAY = 1, -- s avant le premier morceau (la seconde d'arrivée est celle de l'état du monde)
	-- s entre deux passages de la boucle du flux (0 = chaque image) ; les échéances des morceaux
	-- viennent de Clock (STREAM_DELAY, STREAM_INTERVAL), la boucle s'arrête dès que plus rien n'est dû
	STREAM_POLL = 0,
	-- serveur en ligne, GetDataStore en échec : nouvel essai après 5 s, puis 10, 20, 40, 60, 60…
	STORE_RETRY_DELAY = 5,
	STORE_RETRY_MAX = 60,
}

local LOAD_FAILED_MESSAGE =
	"Your data could not be loaded. Please rejoin in a moment. / Tes données n'ont pas pu être chargées, reviens dans un instant."
-- profil sauvegardé par une version plus récente du jeu (serveur pas encore mis à jour)
local OUTDATED_MESSAGE =
	"This server is out of date. Please rejoin to play on an updated server. / Ce serveur n'est pas à jour, reviens pour jouer sur un serveur à jour."

-- Attribut répliqué lu par l'écran de chargement (contrat : nombre > 0 pendant l'attente, toute
-- autre valeur = pas en chargement)
local LOADING_ATTRIBUTE = "ProfileLoading"

type Record = {
	data: { [string]: any }?,
	-- session : jeton du chargement qui a pris le verrou (deux sessions du même UserId sur ce serveur)
	lock: { jobId: string, time: number, session: string? }?,
	meta: { created: number?, lastSave: number?, saves: number? }?,
}

-- Transformation d'UpdateAsync : (nouvelle valeur ou nil = rien n'est écrit, userIds de la clé)
type Transform = (any, any?) -> (any, { number }?)

type Store = {
	GetAsync: (self: any, key: string) -> any,
	UpdateAsync: (self: any, key: string, fn: Transform) -> any,
}

local DataService = {}
DataService.Loaded = Signal.new() :: Signal.Signal<Player, { [string]: any }>
DataService.usingMemoryStore = false
DataService.Settings = Settings

-- Réplication en attente de la fin de la frame : clés entières et entrées (clé → sous-clés)
type Pending = { keys: { [string]: boolean }, entries: { [string]: { [string]: boolean } } }

-- nil = DataStore indisponible (serveur en ligne, GetDataStore en échec) : aucun profil créé
local store: Store? = nil
local profiles: { [Player]: { [string]: any } } = {}
local saving: { [Player]: boolean } = {}
local pending: { [Player]: Pending } = {}
local flushScheduled = false
-- sauvegarde de libération faite (départ ou BindToClose) : résultat de son écriture. Présent =
-- session terminée, plus aucune écriture (une écriture reposerait le verrou)
local releasedOk: { [Player]: boolean } = {}
local releasing: { [Player]: boolean } = {}
-- jeton du chargement de la session (posé dans record.lock.session)
local sessions: { [Player]: string } = {}
-- sauvegardes de départ en cours, par UserId (l'instance Player change à la reconnexion)
local pendingRelease: { [number]: number } = {}
-- sauvegarde de libération en échec sur des ERREURS DataStore (verrou toujours à nous) : instantané
-- déjà écrit par les crochets onBeforeSave et jeton de session, repris par les nouveaux essais
type Unsaved = { snapshot: { [string]: any }, session: string? }
local unsaved: { [Player]: Unsaved } = {}
-- nouveaux essais en arrière-plan d'une sauvegarde de départ (le serveur continue avec les autres
-- joueurs) : pendingRelease[userId] reste posé jusqu'à leur fin (succès, verrou perdu, fenêtre
-- écoulée ou arrêt du serveur) ; poke = essayer tout de suite (reconnexion, arrêt du serveur)
type ReleaseJob = {
	player: Player,
	userId: number,
	snapshot: { [string]: any },
	session: string?,
	poke: boolean,
}
local releaseJobs: { [ReleaseJob]: boolean } = {}
-- reconnexion sur ce serveur qui attend la sauvegarde de départ de ce UserId : fin de son attente
-- (os.clock) ; pendant ce temps, les nouveaux essais sont rapprochés
local rejoinWaits: { [number]: number } = {}
-- BindToClose a commencé : plus de nouvel essai en arrière-plan, ceux en cours essaient une
-- dernière fois tout de suite (attendus par la boucle de fermeture, dans CLOSE_TIMEOUT)
local closing = false
local beforeSave: { (Player, { [string]: any }, boolean?) -> () } = {}
-- valeurs dérivées ajoutées à l'instantané et aux patchs (DataService.setPatchExtra), dans l'ordre
-- d'enregistrement ; aucune tant qu'aucun service ne s'enregistre (jeu de base : rien de changé)
type PatchExtra = {
	name: string,
	fn: (Player, { [string]: any }, { [string]: boolean }?) -> any,
}
local patchExtras: { PatchExtra } = {}
-- crochets de préparation d'un profil chargé (DataService.onPrepare), avant l'instantané et Loaded
local prepareHooks: { (Player, { [string]: any }) -> () } = {}

local snapshotRemote: RemoteEvent
local patchRemote: RemoteEvent

-- Flux d'arrivée : sous-clés de data[key] restant à envoyer (dans l'ordre), par joueur
type StreamPart = { key: string, order: { string }, index: number }
type Stream = { data: { [string]: any }, parts: { StreamPart }, nextAt: number }
local streams: { [Player]: Stream } = {}
local streamOrder: { [string]: ({ [string]: any }) -> { string } } = {}
-- boucle du flux en cours (une seule, vivante tant que `streams` n'est pas vide)
local streamLoopRunning = false

-- Stockage mémoire (Studio sans accès API)
local function memoryStore(): Store
	local data: { [string]: any } = {}
	local mem = {}
	function mem.GetAsync(_self, key: string)
		return Tables.deepCopy(data[key])
	end
	function mem.UpdateAsync(_self, key: string, fn: Transform)
		-- valeurs suivantes de la transformation (userIds) acceptées : sans objet en mémoire
		local new = fn(Tables.deepCopy(data[key]), nil)
		if new ~= nil then
			data[key] = Tables.deepCopy(new)
		end
		return Tables.deepCopy(data[key])
	end
	return mem :: any
end

-- Magasin courant ; lève (dans le pcall de l'appelant) si le DataStore est indisponible
local function currentStore(): Store
	local s = store
	if s == nil then
		error("DataStore indisponible (GetDataStore en échec, nouvel essai en cours)", 0)
	end
	return s
end

local function openStore(): (boolean, any)
	return pcall(function()
		return DataStoreService:GetDataStore(Schema.STORE_NAME)
	end)
end

-- Serveur en ligne sans DataStore : nouvel essai de GetDataStore en arrière-plan avec backoff ;
-- les chargements reprennent dès qu'il répond (jamais de repli en mémoire hors de Studio)
local function retryStore()
	local delay = Settings.STORE_RETRY_DELAY
	while store == nil do
		task.wait(delay)
		local ok, result = openStore()
		if ok and result ~= nil then
			store = result :: any
			warn("[DataService] DataStore de nouveau disponible : chargements rétablis")
			return
		end
		warn("[DataService] GetDataStore toujours en échec :", result)
		delay = math.min(delay * 2, Settings.STORE_RETRY_MAX)
	end
end

local function keyFor(player: Player): string
	return "player_" .. tostring(player.UserId)
end

local function publicView(data: { [string]: any }): { [string]: any }
	local out = {}
	for k, v in data do
		if not Schema.PRIVATE_KEYS[k] then
			out[k] = v
		end
	end
	return out
end

-- Sous-clés de data[key] dans l'ordre d'envoi : celui du crochet (protégé), puis toutes celles
-- qu'il n'a pas citées (jamais une entrée oubliée)
local function orderedSubKeys(key: string, data: { [string]: any }, container: { [any]: any }): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local hook = streamOrder[key]
	if hook then
		local ok, order = pcall(hook, data)
		if ok and type(order) == "table" then
			for _, sub in order :: { any } do
				if type(sub) == "string" and not seen[sub] and container[sub] ~= nil then
					seen[sub] = true
					table.insert(out, sub)
				end
			end
		elseif not ok then
			warn(`[DataService] ordre d'envoi de « {key} » en échec :`, order)
		end
	end
	for sub in container do
		if type(sub) == "string" and not seen[sub] then
			seen[sub] = true
			table.insert(out, sub)
		end
	end
	return out
end

-- Envoie le morceau suivant d'un flux d'arrivée ; vrai quand le flux est terminé. Les valeurs sont
-- lues à l'instant de l'envoi (état vivant) : une entrée supprimée entre-temps est sautée (sa
-- suppression est déjà partie), une entrée modifiée part à jour.
local function sendStreamChunk(player: Player, stream: Stream): boolean
	local budget = math.max(1, math.floor(Settings.STREAM_CHUNK))
	local entries: Types.DataPatchEntries = {}
	local any = false
	for _, part in stream.parts do
		if budget <= 0 then
			break
		end
		local container = stream.data[part.key]
		local set: { [string]: any } = {}
		local sent = false
		if type(container) == "table" then
			while budget > 0 and part.index <= #part.order do
				local sub = part.order[part.index]
				part.index += 1
				local value = container[sub]
				if value ~= nil then
					set[sub] = value
					sent = true
					budget -= 1
				end
			end
		else
			part.index = #part.order + 1 -- table remplacée : sa nouvelle valeur part en clé entière
		end
		if sent then
			entries[part.key] = { set = set, del = {} }
			any = true
		end
	end
	if any then
		patchRemote:FireClient(player, {}, {}, entries)
	end
	for _, part in stream.parts do
		if part.index <= #part.order then
			return false
		end
	end
	return true
end

-- Avance les flux d'arrivée (horloge partagée Clock). Un morceau en erreur (charge refusée par
-- le remote…) abandonne seulement le flux de ce joueur, jamais la boucle des autres.
local function stepStreams()
	if next(streams) == nil then
		return
	end
	local now = Clock.now()
	for player, stream in streams do
		if profiles[player] ~= stream.data or player.Parent == nil then
			streams[player] = nil
		elseif now >= stream.nextAt then
			local ok, done = pcall(sendStreamChunk, player, stream)
			if not ok then
				warn(`[DataService] flux d'arrivée de {player.Name} abandonné :`, done)
				streams[player] = nil
			elseif done then
				streams[player] = nil
			else
				stream.nextAt = now + Settings.STREAM_INTERVAL
			end
		end
	end
end

-- Boucle du flux (aucune connexion Heartbeat permanente) : lancée par l'instantané qui ouvre un
-- flux, elle s'arrête dès que plus aucun flux n'est en cours
local function runStreams()
	repeat
		task.wait(Settings.STREAM_POLL)
		stepStreams()
	until next(streams) == nil
	streamLoopRunning = false
end

local function ensureStreamLoop()
	if not streamLoopRunning and next(streams) ~= nil then
		streamLoopRunning = true
		task.spawn(runStreams)
	end
end

-- Valeur dérivée `extra` pour ce joueur (nil : rien à ajouter) ; une erreur du crochet est signalée
-- (warn : un défaut du service qui s'est enregistré) et rien n'est ajouté
local function extraValue(
	extra: PatchExtra,
	player: Player,
	data: { [string]: any },
	keys: { [string]: boolean }?
): any
	local ok, value = pcall(extra.fn, player, data, keys)
	if not ok then
		warn(`[DataService] valeur dérivée « {extra.name} » en échec :`, value)
		return nil
	end
	return value
end

-- Instantané (arrivée, RequestSnapshot) : les grandes tables n'y portent que leurs SNAPSHOT_INLINE
-- premières entrées, le reste part ensuite en flux (DataPatch, entrées) ; un nouvel instantané
-- remplace le flux en cours
local function sendSnapshot(player: Player, data: { [string]: any })
	local view = publicView(data)
	local parts: { StreamPart } = {}
	local inlineCount = math.max(0, math.floor(Settings.SNAPSHOT_INLINE))
	-- tables envoyées par morceaux (Schema.STREAMED_KEYS, lu à chaque instantané)
	for _, key in Schema.STREAMED_KEYS do
		local container = view[key]
		if type(container) == "table" and not Schema.PRIVATE_KEYS[key] then
			local order = orderedSubKeys(key, data, container)
			if #order > inlineCount then
				local inline: { [string]: any } = {}
				for i = 1, inlineCount do
					local sub = order[i]
					inline[sub] = container[sub]
				end
				view[key] = inline
				table.insert(parts, { key = key, order = order, index = inlineCount + 1 })
			end
		end
	end
	for _, extra in patchExtras do
		local value = extraValue(extra, player, data, nil)
		if value ~= nil then
			view[extra.name] = value
		end
	end
	snapshotRemote:FireClient(player, view)
	if #parts > 0 then
		streams[player] = { data = data, parts = parts, nextAt = Clock.now() + Settings.STREAM_DELAY }
		ensureStreamLoop()
	else
		streams[player] = nil
	end
end

local function flushPatches()
	flushScheduled = false
	for player, queued in pending do
		local data = profiles[player]
		if data and player.Parent then
			local patch: { [string]: any } = {}
			-- une valeur nil est transmise via la liste `removed`
			local removed: { string } = {}
			local any = false
			for key in queued.keys do
				if not Schema.PRIVATE_KEYS[key] then
					local value = data[key]
					patch[key] = value
					if value == nil then
						table.insert(removed, key)
					end
					any = true
				end
			end
			-- entrées : seules les sous-clés touchées, résolues sur l'état de fin de frame ; la clé
			-- entière, si elle part aussi, les rend inutiles
			local entries: Types.DataPatchEntries = {}
			local anyEntries = false
			for key, subKeys in queued.entries do
				if not Schema.PRIVATE_KEYS[key] and not queued.keys[key] then
					local container = data[key]
					if type(container) == "table" then
						local set: { [string]: any } = {}
						local del: { string } = {}
						for subKey in subKeys do
							local value = container[subKey]
							if value == nil then
								table.insert(del, subKey)
							else
								set[subKey] = value
							end
						end
						entries[key] = { set = set, del = del }
						anyEntries = true
					else
						-- plus une table (remplacée) : la clé entière part
						patch[key] = container
						if container == nil then
							table.insert(removed, key)
						end
						any = true
					end
				end
			end
			-- valeurs dérivées (setPatchExtra) : seulement si le patch part déjà, ou si le crochet le
			-- demande pour les clés touchées ; jamais de patch vide
			if #patchExtras > 0 and (any or anyEntries) then
				local touched: { [string]: boolean } = table.clone(queued.keys)
				for key in queued.entries do
					touched[key] = true
				end
				for _, extra in patchExtras do
					local value = extraValue(extra, player, data, touched)
					if value ~= nil then
						patch[extra.name] = value
						any = true
					end
				end
			end
			if anyEntries then
				patchRemote:FireClient(player, patch, removed, entries)
			elseif any then
				patchRemote:FireClient(player, patch, removed)
			end
		end
	end
	table.clear(pending)
end

local function pendingFor(player: Player): Pending
	local queued = pending[player]
	if not queued then
		queued = { keys = {}, entries = {} }
		pending[player] = queued
	end
	if not flushScheduled then
		flushScheduled = true
		task.defer(flushPatches)
	end
	return queued
end

local function queuePatch(player: Player, key: string)
	pendingFor(player).keys[key] = true
end

local function queueEntry(player: Player, key: string, subKey: string)
	local entries = pendingFor(player).entries
	local subKeys = entries[key]
	if not subKeys then
		subKeys = {}
		entries[key] = subKeys
	end
	subKeys[subKey] = true
end

-- Profil écrit par une version plus récente du schéma : ce serveur ne sait ni le lire ni le réparer
local function isNewer(data: any): boolean
	return type(data) == "table" and type(data.version) == "number" and data.version > Schema.VERSION
end

local function prepare(raw: { [string]: any }?): { [string]: any }
	local data: { [string]: any } = if raw then raw else Schema.defaults()
	-- version absente ou illisible (sauvegarde abîmée) : traitée comme la plus ancienne
	local version = if type(data.version) == "number" and data.version == data.version
		then data.version
		else 0
	if version < Schema.VERSION then
		data = Schema.migrate(data, version)
		data.version = Schema.VERSION
	end
	Tables.reconcile(data, Schema.defaults())
	return data
end

-- Chargement en cours (numéro d'essai > 0) ou terminé (nil) ; rien pour un joueur déjà parti
local function setLoading(player: Player, attempt: number?)
	if player.Parent ~= nil then
		player:SetAttribute(LOADING_ATTRIBUTE, attempt)
	end
end

-- (chargé, données, schéma plus récent) ; `session` : jeton posé dans le verrou.
-- Verrou frais d'un autre serveur : repris seulement après LOAD_ATTEMPTS - 1 lectures RÉUSSIES qui
-- l'ont vu, chacune suivie de LOCKED_RETRY_DELAY (≥ 30 s d'observation, DataStore en marche).
-- Jamais parce que des ERREURS ont épuisé les essais : après une panne, le serveur qui détient le
-- verrou réessaie sa sauvegarde de départ toutes les RELEASE_RETRY_MAX s au plus (invariant :
-- LOCKED_RETRY_DELAY × (LOAD_ATTEMPTS - 1) ≥ RELEASE_RETRY_MAX + 10) ; le lui prendre plus tôt
-- effacerait tout ce que l'enfant a gagné pendant la panne. Essais épuisés sans assez de lectures :
-- rien n'est écrit, échec (renvoi poli LOAD_FAILED_MESSAGE), aucune attente après le dernier essai.
local function loadRecord(player: Player, session: string): (boolean, { [string]: any }?, boolean)
	local key = keyFor(player)
	-- clé liée au joueur (demandes d'effacement Roblox) : passée à chaque écriture
	local userIds = { player.UserId }
	-- lectures réussies qui ont vu le verrou frais d'un autre serveur ; comptées HORS de la
	-- transformation (UpdateAsync peut la rejouer plusieurs fois pour un seul appel)
	local sightings = 0
	for attempt = 1, Settings.LOAD_ATTEMPTS do
		if player.Parent == nil then
			return false, nil, false
		end
		setLoading(player, attempt)
		local lockedByOther = false
		local newer = false
		-- DataStore indisponible (currentStore lève) : essai en échec comme une panne, avec backoff ;
		-- toujours indisponible au dernier essai = renvoi, jamais de profil vide
		local ok, result = pcall(function()
			return currentStore():UpdateAsync(key, function(old: Record?): (Record?, { number }?)
				local record: Record = old or {}
				-- schéma plus récent : rien n'est écrit, pas même le verrou (celui d'un serveur à jour
				-- reste intact) ; inutile d'attendre l'expiration d'un verrou
				if isNewer(record.data) then
					newer = true
					return nil
				end
				newer = false
				local lock = record.lock
				if
					lock
					and lock.jobId ~= game.JobId
					and os.time() - lock.time < Settings.LOCK_EXPIRY
					and sightings < Settings.LOAD_ATTEMPTS - 1
				then
					lockedByOther = true
					return nil -- n'écrit rien : on réessaie plus tard (ou renvoi au dernier essai)
				end
				lockedByOther = false
				record.lock = { jobId = game.JobId, time = os.time(), session = session }
				record.meta = record.meta or { created = os.time(), saves = 0 }
				return record, userIds
			end)
		end)
		if ok and newer then
			return false, nil, true
		elseif ok and not lockedByOther then
			local record = result :: Record?
			return true, if record then record.data else nil, false
		elseif ok then
			sightings += 1
			warn(
				`[DataService] données de {player.Name} verrouillées par un autre serveur, essai {attempt}/{Settings.LOAD_ATTEMPTS} (lecture {sightings})`
			)
			if attempt < Settings.LOAD_ATTEMPTS then
				task.wait(Settings.LOCKED_RETRY_DELAY)
			else
				-- des erreurs ont pris des essais : verrou pas assez observé pour le reprendre
				-- (son serveur réessaie peut-être encore sa sauvegarde de départ) ; renvoi poli
				warn(
					`[DataService] verrou de {player.Name} vu {sightings} fois seulement : chargement refusé, rien d'écrit`
				)
			end
		else
			warn(`[DataService] échec de chargement pour {player.Name} (essai {attempt}) :`, result)
			-- après le dernier essai : renvoi aussitôt (attendre ne ferait que retarder l'enfant sur
			-- l'écran de chargement). Pire cas : 2 + 4 + 8 + 16 + 16 = 46 s d'attente (× base) ;
			-- lectures du verrou aux essais 1 et 2 (6 s chacune) puis erreurs : 52 s, sous les 60 s
			-- (RETRY_MAX_WAIT) de l'écran de chargement
			if attempt < Settings.LOAD_ATTEMPTS then
				task.wait(math.min(2 ^ attempt, 16) * Settings.RETRY_BASE_DELAY)
			end
		end
	end
	return false, nil, false
end

-- Libère le verrou pris par CE chargement sans toucher aux données (session partie pendant son
-- chargement). Le jeton évite d'effacer le verrou d'une reconnexion du même UserId sur ce serveur
-- (même JobId), chargée entre-temps.
local function releaseLoadLock(player: Player, session: string)
	local userIds = { player.UserId }
	local ok, err = pcall(function()
		currentStore():UpdateAsync(keyFor(player), function(old: Record?): (Record?, { number }?)
			local lock = if old then old.lock else nil
			if old and lock and lock.jobId == game.JobId and lock.session == session then
				old.lock = nil
				return old, userIds
			end
			return nil
		end)
	end)
	if not ok then
		warn(`[DataService] libération du verrou de {player.Name} en échec :`, err)
	end
end

-- Écrit `snapshot` (copie profonde, plus jamais modifiée) si la session `session` détient encore
-- le verrou ; jusqu'à `attempts` essais avec backoff. Rend (écrit, verrou perdu) : (false, false) =
-- échec sur des erreurs DataStore (le verrou est toujours à nous, un nouvel essai peut écrire).
-- Le jeton est passé par l'appelant : sessions[player] est effacé au départ, avant les nouveaux
-- essais en arrière-plan.
local function writeRecord(
	player: Player,
	snapshot: { [string]: any },
	release: boolean,
	session: string?,
	attempts: number
): (boolean, boolean)
	local key = keyFor(player)
	local userIds = { player.UserId }
	for attempt = 1, attempts do
		local lostLock = false
		local ok, err = pcall(function()
			currentStore():UpdateAsync(key, function(old: Record?): (Record?, { number }?)
				local record: Record = old or {}
				local lock = record.lock
				-- n'écrit que si CETTE session détient encore le verrou. Après un chargement réussi, le
				-- verrou porte toujours notre JobId et notre jeton : absent (un autre serveur l'a repris
				-- puis libéré : une sauvegarde de départ retardée écraserait toute sa session, achats
				-- acquittés compris), d'un autre serveur, ou d'une autre session de ce serveur (même
				-- JobId, autre jeton) = notre session est terminée, ses données sont périmées. Un
				-- schéma plus récent n'est jamais écrasé non plus.
				if
					lock == nil
					or lock.jobId ~= game.JobId
					or lock.session ~= session
					or isNewer(record.data)
				then
					lostLock = true
					return nil
				end
				lostLock = false
				record.data = snapshot
				record.lock = if release
					then nil
					else { jobId = game.JobId, time = os.time(), session = session }
				local meta = record.meta or { created = os.time(), saves = 0 }
				meta.lastSave = os.time()
				meta.saves = (meta.saves or 0) + 1
				record.meta = meta
				return record, userIds
			end)
		end)
		if ok then
			if lostLock then
				if release then
					-- perte de données de cette session (jamais écrite) : à suivre dans les journaux
					warn(
						`[DataService] PERTE : sauvegarde de départ de {player.Name} refusée (verrou absent ou repris par une autre session)`
					)
				else
					warn(
						`[DataService] session de {player.Name} reprise par un autre serveur : sauvegarde ignorée`
					)
				end
				return false, true
			end
			return true, false
		end
		warn(`[DataService] échec de sauvegarde pour {player.Name} (essai {attempt}) :`, err)
		if attempt < attempts then
			task.wait(math.min(2 ^ attempt, 8) * Settings.RETRY_BASE_DELAY)
		end
	end
	return false, false
end

local function save(player: Player, release: boolean): boolean
	local data = profiles[player]
	if not data then
		return false
	end
	if release then
		-- toute autosave arrivant après ce point est ignorée (elle reposerait le verrou)
		releasing[player] = true
	end
	-- une seule écriture à la fois par joueur
	while saving[player] do
		task.wait(0.1)
	end
	-- session déjà libérée : plus aucune écriture. Une sauvegarde ordinaire répond false (rien
	-- d'écrit : un achat n'est pas acquitté) ; une 2e libération répond le résultat de la 1re.
	local done = releasedOk[player]
	if done ~= nil then
		return release and done
	end
	-- session terminée pendant l'attente (départ sauvegardé, état nettoyé) : une sauvegarde mise en
	-- file derrière celle du départ ne doit ni écrire ni reprendre le verrou de session
	if profiles[player] ~= data then
		return false
	end
	if not release and releasing[player] then
		return false
	end
	-- crochets synchrones (ex. règlement d'un revenu passif) avant l'instantané écrit
	for _, fn in beforeSave do
		local ok, err = pcall(fn, player, data, release)
		if not ok then
			warn("[DataService] crochet onBeforeSave en échec :", err)
		end
	end
	local snapshot = Tables.deepCopy(data)
	local session = sessions[player]
	saving[player] = true
	local ok, lostLock = writeRecord(player, snapshot, release, session, Settings.SAVE_ATTEMPTS)
	saving[player] = nil
	if release then
		releasedOk[player] = ok
		if not ok and not lostLock then
			-- panne DataStore : instantané gardé pour les nouveaux essais de départ (onPlayerRemoving)
			unsaved[player] = { snapshot = snapshot, session = session }
		end
	end
	return ok
end

-- Fin d'une sauvegarde de départ (réussie, abandonnée ou en erreur) : une reconnexion sur ce
-- serveur peut charger
local function endRelease(userId: number)
	local left = (pendingRelease[userId] or 1) - 1
	pendingRelease[userId] = if left > 0 then left else nil
end

-- Attend `seconds` (temps réel) ; réveillé plus tôt par une reconnexion ou l'arrêt du serveur
local function releaseSleep(job: ReleaseJob, seconds: number)
	local start = os.clock()
	while not job.poke and not closing do
		local left = seconds - (os.clock() - start)
		if left <= 0 then
			return
		end
		task.wait(math.min(left, Settings.RELEASE_RETRY_POLL))
	end
end

-- Nouveaux essais en arrière-plan d'une sauvegarde de départ en panne : le même instantané (les
-- crochets onBeforeSave ont déjà tourné, jamais rejoués : pas de double règlement), le même jeton
-- de session (la transformation refuse d'écraser un serveur qui a repris le verrou entre-temps).
-- Backoff plafonné pendant RELEASE_RETRY_WINDOW s ; arrêt au premier succès ou verrou perdu.
-- Reconnexion sur ce serveur : un essai aussitôt, puis le backoff court des sauvegardes (2, 4, 8,
-- 8… × RETRY_BASE_DELAY) tant qu'elle attend (REJOIN_WAIT, puis renvoi poli : jamais de données
-- périmées). Arrêt du serveur : un dernier essai complet (SAVE_ATTEMPTS), attendu par la boucle
-- de fermeture.
local function retryRelease(job: ReleaseJob)
	local start = os.clock()
	local delay = Settings.RELEASE_RETRY_DELAY
	local tries = 0
	local urgent = 0
	local pause = delay
	while true do
		releaseSleep(job, pause)
		job.poke = false
		local final = closing
		tries += 1
		local ok, written, lostLock = pcall(
			writeRecord,
			job.player,
			job.snapshot,
			true,
			job.session,
			if final then Settings.SAVE_ATTEMPTS else 1
		)
		if ok and written then
			warn(`[DataService] sauvegarde de départ de {job.player.Name} écrite au nouvel essai {tries}`)
			break
		end
		if ok and lostLock then
			break -- writeRecord a journalisé la perte
		end
		if not ok then
			warn(`[DataService] nouvel essai de départ de {job.player.Name} en erreur :`, written)
		end
		if final or os.clock() - start >= Settings.RELEASE_RETRY_WINDOW then
			warn(
				`[DataService] PERTE : sauvegarde de départ de {job.player.Name} abandonnée après {tries} nouveaux essais (DataStore indisponible)`
			)
			break
		end
		if os.clock() < (rejoinWaits[job.userId] or -math.huge) then
			-- le joueur attend sur ce serveur : essais rapprochés (backoff normal mis en pause)
			urgent += 1
			pause = math.min(math.min(2 ^ urgent, 8) * Settings.RETRY_BASE_DELAY, delay)
		else
			urgent = 0
			delay = math.min(delay * 2, Settings.RELEASE_RETRY_MAX)
			pause = delay
		end
	end
	releaseJobs[job] = nil
	endRelease(job.userId)
end

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	-- l'écran de chargement attend (Réessayer retenu), y compris pendant REJOIN_WAIT ci-dessous
	setLoading(player, 1)
	-- Reconnexion sur le MÊME serveur : la sauvegarde de départ de l'ancienne session (même UserId,
	-- autre instance Player) est peut-être encore en cours (attente d'une autosave, retries). Charger
	-- maintenant lirait des données périmées (notre propre JobId ne compte pas comme verrou) que
	-- cette session réécrirait ensuite : on attend qu'elle se termine.
	local userId = player.UserId
	if pendingRelease[userId] then
		-- sauvegarde de départ en panne, nouveaux essais en arrière-plan : un essai tout de suite,
		-- puis rapprochés tant que ce joueur attend
		local start = os.clock()
		rejoinWaits[userId] = start + Settings.REJOIN_WAIT
		for job in releaseJobs do
			if job.userId == userId then
				job.poke = true
			end
		end
		while pendingRelease[userId] and player.Parent ~= nil and os.clock() - start < Settings.REJOIN_WAIT do
			task.wait(0.1)
		end
		rejoinWaits[userId] = nil
		if player.Parent == nil then
			return
		end
		if pendingRelease[userId] then
			-- toujours en cours : jamais de données périmées, le joueur reviendra dans un instant
			warn(
				`[DataService] sauvegarde de départ de {player.Name} toujours en cours : chargement refusé`
			)
			setLoading(player, nil)
			player:Kick(LOAD_FAILED_MESSAGE)
			return
		end
	end
	local session = HttpService:GenerateGUID(false)
	local ok, raw, newer = loadRecord(player, session)
	-- réponse connue (chargé, plus récent ou échec) : l'attente est finie, avant l'instantané ou le
	-- renvoi
	setLoading(player, nil)
	if player.Parent == nil then
		-- parti pendant le chargement : libérer le verrou sans toucher aux données
		if ok then
			releaseLoadLock(player, session)
		end
		return
	end
	if newer then
		-- jamais réparé ni réécrit ici : un serveur plus ancien effacerait les données qu'il ne
		-- connaît pas. Aucun verrou n'a été pris ; le joueur revient sur un serveur à jour.
		warn(
			`[DataService] profil de {player.Name} écrit par un schéma plus récent que v{Schema.VERSION} : chargement refusé`
		)
		player:Kick(OUTDATED_MESSAGE)
		return
	end
	if not ok then
		player:Kick(LOAD_FAILED_MESSAGE)
		return
	end
	-- préparation protégée (lot A2) : une erreur de migration ou de reconcile (bug d'une étape,
	-- enregistrement illisible) ne laisse jamais le joueur sur l'écran de chargement avec notre verrou
	-- posé ; rien n'est écrit (la sauvegarde reste telle quelle), le verrou est rendu, renvoi poli
	local prepOk, prepared = pcall(prepare, raw)
	if not prepOk then
		warn(`[DataService] préparation du profil de {player.Name} en échec :`, prepared)
		releaseLoadLock(player, session)
		player:Kick(LOAD_FAILED_MESSAGE)
		return
	end
	local data: { [string]: any } = prepared
	-- réparation du profil (note INT-REPAIR, docs/04 §8.5, §22.2) : après migrate + reconcile, AVANT
	-- les crochets onPrepare ; une réparation en échec est signalée (warn) et le chargement continue
	local repairOk, fixes = pcall(ProfileRepair.repair, data)
	if not repairOk then
		warn("[DataService] réparation du profil en échec :", fixes)
	end
	-- crochets de préparation (synchrones, protégés) : personne d'autre n'a encore vu ce profil
	for _, fn in prepareHooks do
		local hookOk, err = pcall(fn, player, data)
		if not hookOk then
			warn("[DataService] crochet onPrepare en échec :", err)
		end
	end
	sessions[player] = session
	profiles[player] = data
	releasedOk[player] = nil
	releasing[player] = nil
	sendSnapshot(player, data)
	DataService.Loaded:Fire(player, data)
	-- réparations comptées par DiagnosticsService (« ProfileRepaired:<champ> »)
	if repairOk and type(fixes) == "table" and #fixes > 0 then
		Signals.ProfileRepaired:Fire(player, fixes)
	end
end

local function onPlayerRemoving(player: Player)
	local job: ReleaseJob? = nil
	if profiles[player] then
		local userId = player.UserId
		pendingRelease[userId] = (pendingRelease[userId] or 0) + 1
		-- protégé : une erreur ne doit jamais laisser ce UserId « en cours de départ » pour toujours
		local ok, err = pcall(save, player, true)
		if not ok then
			warn(`[DataService] sauvegarde de départ de {player.Name} en erreur :`, err)
		end
		local failed = unsaved[player]
		if ok and failed ~= nil and not closing then
			-- panne DataStore au départ : le serveur continue avec les autres joueurs, il a le temps
			-- de réessayer (sinon tout ce qui a été gagné depuis le début de la panne serait perdu, et
			-- notre verrou resterait dans l'enregistrement) ; pendingRelease reste posé jusqu'à la fin
			job = {
				player = player,
				userId = userId,
				snapshot = failed.snapshot,
				session = failed.session,
				-- une reconnexion attend déjà (pendant les essais de départ) : nouvel essai aussitôt
				poke = rejoinWaits[userId] ~= nil,
			}
		else
			endRelease(userId)
		end
	end
	profiles[player] = nil
	pending[player] = nil
	saving[player] = nil
	releasedOk[player] = nil
	releasing[player] = nil
	sessions[player] = nil
	streams[player] = nil
	unsaved[player] = nil
	if job ~= nil then
		warn(
			`[DataService] sauvegarde de départ de {player.Name} en échec : nouveaux essais en arrière-plan`
		)
		releaseJobs[job] = true
		task.spawn(retryRelease, job)
	end
end

function DataService.Init()
	snapshotRemote = Net.event("DataSnapshot")
	patchRemote = Net.event("DataPatch")

	local ok, result = openStore()
	if ok and result ~= nil then
		local opened = result :: Store
		store = opened
		if RunService:IsStudio() then
			local probeOk, probeErr = pcall(function()
				opened:GetAsync("__studio_probe")
			end)
			if not probeOk then
				warn(
					"[DataService] DataStore indisponible dans Studio (",
					probeErr,
					") : sauvegarde EN MÉMOIRE uniquement."
				)
				store = memoryStore()
				DataService.usingMemoryStore = true
			end
		end
	elseif RunService:IsStudio() then
		warn(
			"[DataService] GetDataStore a échoué dans Studio :",
			result,
			"— sauvegarde EN MÉMOIRE uniquement."
		)
		store = memoryStore()
		DataService.usingMemoryStore = true
	else
		-- serveur en ligne : jamais de repli en mémoire (session jamais sauvegardée, achats Robux
		-- acquittés puis perdus). Aucun profil n'est créé tant que le DataStore manque : chaque
		-- chargement échoue (renvoi LOAD_FAILED_MESSAGE) ; nouvel essai en arrière-plan.
		warn(
			"[DataService] GetDataStore a échoué :",
			result,
			"— DataStore indisponible : chargements refusés, nouvel essai en arrière-plan."
		)
		store = nil
		task.spawn(retryStore)
	end

	-- le client redemande un instantané s'il a raté le premier (chargement lent)
	Net.event("RequestSnapshot").OnServerEvent:Connect(function(player: Player)
		if not RateLimit.allow(player, "RequestSnapshot", 2, 10) then
			return
		end
		local data = profiles[player]
		if data then
			sendSnapshot(player, data)
		end
	end)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- flux d'arrivée : boucle lancée à la demande par sendSnapshot (aucune connexion Heartbeat)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Settings.AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		-- plus de nouvel essai de départ en arrière-plan ; ceux en cours essaient tout de suite une
		-- dernière fois et sont attendus ci-dessous
		closing = true
		for job in releaseJobs do
			job.poke = true
		end
		local remaining = 0
		for player in profiles do
			remaining += 1
			task.spawn(function()
				save(player, true)
				remaining -= 1
			end)
		end
		local start = os.clock()
		while (remaining > 0 or next(releaseJobs) ~= nil) and os.clock() - start < Settings.CLOSE_TIMEOUT do
			task.wait(0.1)
		end
	end)
end

function DataService.get(player: Player): { [string]: any }?
	return profiles[player]
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.waitFor(player: Player, timeout: number?): { [string]: any }?
	local limit = timeout or 30
	local start = os.clock()
	while not profiles[player] and player.Parent ~= nil and os.clock() - start < limit do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.set(player: Player, key: string, value: any)
	local data = profiles[player]
	if not data then
		return
	end
	data[key] = value
	queuePatch(player, key)
end

function DataService.increment(player: Player, key: string, delta: number): number?
	local data = profiles[player]
	if not data then
		return nil
	end
	local current = data[key]
	assert(type(current) == "number", `DataService.increment : « {key} » n'est pas un nombre`)
	assert(delta == delta and math.abs(delta) ~= math.huge, "DataService.increment : delta invalide")
	local new = current + delta
	data[key] = new
	queuePatch(player, key)
	return new
end

function DataService.markDirty(player: Player, key: string)
	if profiles[player] then
		queuePatch(player, key)
	end
end

-- Une entrée de la table data[key] a changé (ou a été supprimée) : seule data[key][subKey] part,
-- dans le patch de la frame (DataPatch, 3e argument). L'instantané (chargement, RequestSnapshot)
-- envoie la table entière, sauf une grande table (Schema.STREAMED_KEYS) : ses SNAPSHOT_INLINE
-- premières entrées, le reste en flux d'entrées DataPatch juste après.
function DataService.markDirtyEntry(player: Player, key: string, subKey: string)
	if profiles[player] then
		queueEntry(player, key, subKey)
	end
end

function DataService.saveNow(player: Player): boolean
	return save(player, false)
end

-- Sauvegarde de libération commencée ou faite (départ, BindToClose) : l'instantané écrit est déjà
-- copié ou va l'être, une mutation de plus serait perdue (lot A2 : un achat est refusé). Une
-- autosave en cours ne compte pas : son instantané est copié d'un bloc AVANT l'écriture, la mutation
-- part à la suivante.
function DataService.isClosing(player: Player): boolean
	return releasing[player] == true or releasedOk[player] ~= nil or closing
end

-- Valeur dérivée ajoutée sous `name` à l'instantané et à chaque patch du joueur (lot A2 : instantané
-- versionné de l'écran Améliorations, docs/04 §27.5) ; fn(player, data, clés) rend nil pour ne rien
-- ajouter. Un nom de clé du profil est refusé (jamais une donnée sauvegardée écrasée côté client).
function DataService.setPatchExtra(
	name: string,
	fn: (Player, { [string]: any }, { [string]: boolean }?) -> any
)
	assert(type(name) == "string" and name ~= "", "DataService.setPatchExtra : nom invalide")
	assert(type(fn) == "function", "DataService.setPatchExtra : crochet invalide")
	assert(Schema.defaults()[name] == nil, `DataService.setPatchExtra : « {name} » est une clé du profil`)
	for _, extra in patchExtras do
		if extra.name == name then
			extra.fn = fn
			return
		end
	end
	table.insert(patchExtras, { name = name, fn = fn })
end

-- Enregistre un crochet appelé (sans yield) juste avant chaque sauvegarde du joueur :
-- autosave, saveNow, départ et BindToClose. `release` vaut true pour la sauvegarde de libération
-- (départ, BindToClose) : le travail « de départ » doit être fait là, le Player peut encore être
-- dans l'arbre (BindToClose) et aucune sauvegarde ne suivra.
function DataService.onBeforeSave(fn: (Player, { [string]: any }, boolean?) -> ())
	table.insert(beforeSave, fn)
end

-- Enregistre un crochet appelé une fois par chargement, SANS yield, après migrate + reconcile (et la
-- réparation du profil) et AVANT l'instantané envoyé au client et le signal Loaded : aucun autre code
-- n'a encore vu le profil (ex. rebase hors ligne de l'économie : jamais de règlement sur un horodatage
-- d'une session précédente). Une erreur est attrapée et signalée (warn) ; le chargement continue.
function DataService.onPrepare(fn: (Player, { [string]: any }) -> ())
	table.insert(prepareHooks, fn)
end

-- Ordre d'envoi des entrées d'une grande table à l'arrivée (instantané puis flux) : fn(data)
-- retourne les sous-clés de data[key] par priorité (ex. les créatures affichées au ranch d'abord)
function DataService.setStreamOrder(key: string, fn: ({ [string]: any }) -> { string })
	streamOrder[key] = fn
end

return DataService
