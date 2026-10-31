--!strict
-- DataService : sauvegarde joueur sans perte.
--  * verrou de session (un seul serveur écrit les données d'un joueur)
--  * UpdateAsync partout, retries avec backoff, autosave, BindToClose
--  * schéma versionné (Data/Schema.luau) : defaults + migrations + reconcile
--  * réplication vers le client : instantané au chargement, puis patchs groupés par frame
--    (clés entières, ou entrées d'une grande table : DataPatch(patch, removed, entries?))
--  * arrivée sous le budget réseau (GDD §12.8, 30 Ko/s en pointe) : une grande table (nebbies,
--    ≈ 65 o par entrée, 40 Ko pour 640 Nebbies) ne part dans l'instantané qu'avec ses
--    SNAPSHOT_INLINE premières entrées (ordre setStreamOrder : les perchés d'abord) ; le reste suit
--    en entrées DataPatch de STREAM_CHUNK toutes les STREAM_INTERVAL s, après STREAM_DELAY s
--    (horloge partagée Clock) : le client (StateController) les applique comme n'importe quel patch
--  * une écriture n'a lieu que si CETTE session détient encore le verrou (même JobId ET même jeton) :
--    verrou absent, étranger ou d'une autre session = session terminée, jamais d'écrasement
--  * profil écrit par un schéma PLUS RÉCENT (serveur déjà mis à jour) : jamais réparé, jamais
--    réécrit, aucun verrou pris ; le joueur est renvoyé vers un serveur à jour
--  * verrou de session marqué d'un jeton par chargement (reconnexion sur le même serveur)
--  * attribut répliqué Player « ProfileLoading » = numéro d'essai (> 0) tant que le chargement
--    attend (sauvegarde de départ d'une reconnexion, verrou d'un autre serveur, backoff) ; nil dès
--    que loadRecord a rendu sa réponse (avant l'instantané ou le renvoi) : l'écran de chargement
--    (src/first/Loading.client) retient « Réessayer » tant qu'il est posé
--  * repli en mémoire dans Studio quand l'accès API est désactivé
--
-- API :
--   DataService.get(player) -> données vivantes ou nil (pas encore chargées)
--   DataService.waitFor(player, timeout?) -> données ou nil
--   DataService.Loaded:Connect(function(player, data) end)
--   DataService.set(player, key, value)          -- clé de 1er niveau + réplication
--   DataService.increment(player, key, delta)    -- nombres
--   DataService.markDirty(player, key)           -- après mutation d'une table imbriquée (clé entière)
--   DataService.markDirtyEntry(player, key, sub) -- une seule entrée data[key][sub] a changé (ou a
--                                                   été supprimée) : seule l'entrée est envoyée
--   DataService.saveNow(player) -> boolean       -- sauvegarde immédiate (achats) ; false après la
--                                                   sauvegarde de libération (départ, BindToClose)
--   DataService.onBeforeSave(fn)                 -- fn(player, data, release) juste avant chaque
--                                                   écriture ; release = true pour la sauvegarde de
--                                                   départ / BindToClose (EconomyService y règle le
--                                                   revenu passif, EventService le travail de départ)
--   DataService.setStreamOrder(key, fn)          -- fn(data) -> sous-clés de data[key] par priorité
--                                                   d'envoi (instantané puis flux) ; sans crochet :
--                                                   ordre quelconque

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
local RateLimit = require(script.Parent.Parent.Util.RateLimit)

-- Réglages (modifiables par les tests avant le démarrage)
local Settings = {
	LOCK_EXPIRY = 30 * 60, -- un verrou plus vieux que 30 min est considéré abandonné
	LOAD_ATTEMPTS = 6,
	LOCKED_RETRY_DELAY = 5,
	RETRY_BASE_DELAY = 1, -- backoff : 2, 4, 8… × base
	SAVE_ATTEMPTS = 4,
	AUTOSAVE_INTERVAL = 90,
	CLOSE_TIMEOUT = 25,
	-- reconnexion sur le même serveur : attente max de la sauvegarde de départ de l'ancienne session
	REJOIN_WAIT = 25,
	-- grandes tables (STREAMED_KEYS) : entrées dans l'instantané, puis flux d'entrées DataPatch
	-- (≈ 65 o par entrée : 50 entrées ≈ 3,3 Ko, 13 Ko/s pendant le flux)
	SNAPSHOT_INLINE = 50,
	STREAM_CHUNK = 50,
	STREAM_INTERVAL = 0.25, -- s entre deux morceaux
	STREAM_DELAY = 1, -- s avant le premier morceau (la seconde d'arrivée est celle du WorldSnapshot)
}

-- Tables envoyées par morceaux après l'instantané (au-delà de SNAPSHOT_INLINE entrées)
local STREAMED_KEYS: { string } = { "nebbies" }

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

type Store = {
	GetAsync: (self: any, key: string) -> any,
	UpdateAsync: (self: any, key: string, fn: (any) -> any) -> any,
}

local DataService = {}
DataService.Loaded = Signal.new() :: Signal.Signal<Player, { [string]: any }>
DataService.usingMemoryStore = false
DataService.Settings = Settings

-- Réplication en attente de la fin de la frame : clés entières et entrées (clé → sous-clés)
type Pending = { keys: { [string]: boolean }, entries: { [string]: { [string]: boolean } } }

local store: Store
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
local beforeSave: { (Player, { [string]: any }, boolean?) -> () } = {}

local snapshotRemote: RemoteEvent
local patchRemote: RemoteEvent

-- Flux d'arrivée : sous-clés de data[key] restant à envoyer (dans l'ordre), par joueur
type StreamPart = { key: string, order: { string }, index: number }
type Stream = { data: { [string]: any }, parts: { StreamPart }, nextAt: number }
local streams: { [Player]: Stream } = {}
local streamOrder: { [string]: ({ [string]: any }) -> { string } } = {}

-- Stockage mémoire (Studio sans accès API)
local function memoryStore(): Store
	local data: { [string]: any } = {}
	local mem = {}
	function mem.GetAsync(_self, key: string)
		return Tables.deepCopy(data[key])
	end
	function mem.UpdateAsync(_self, key: string, fn: (any) -> any)
		local new = fn(Tables.deepCopy(data[key]))
		if new ~= nil then
			data[key] = Tables.deepCopy(new)
		end
		return Tables.deepCopy(data[key])
	end
	return mem :: any
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

-- Instantané (arrivée, RequestSnapshot) : les grandes tables n'y portent que leurs SNAPSHOT_INLINE
-- premières entrées, le reste part ensuite en flux (DataPatch, entrées) ; un nouvel instantané
-- remplace le flux en cours
local function sendSnapshot(player: Player, data: { [string]: any })
	local view = publicView(data)
	local parts: { StreamPart } = {}
	local inlineCount = math.max(0, math.floor(Settings.SNAPSHOT_INLINE))
	for _, key in STREAMED_KEYS do
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
	snapshotRemote:FireClient(player, view)
	if #parts > 0 then
		streams[player] = { data = data, parts = parts, nextAt = Clock.now() + Settings.STREAM_DELAY }
	else
		streams[player] = nil
	end
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

-- Avance les flux d'arrivée (Heartbeat, horloge partagée)
local function stepStreams()
	if next(streams) == nil then
		return
	end
	local now = Clock.now()
	for player, stream in streams do
		if profiles[player] ~= stream.data or player.Parent == nil then
			streams[player] = nil
		elseif now >= stream.nextAt then
			if sendStreamChunk(player, stream) then
				streams[player] = nil
			else
				stream.nextAt = now + Settings.STREAM_INTERVAL
			end
		end
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

-- (chargé, données, schéma plus récent) ; `session` : jeton posé dans le verrou
local function loadRecord(player: Player, session: string): (boolean, { [string]: any }?, boolean)
	local key = keyFor(player)
	for attempt = 1, Settings.LOAD_ATTEMPTS do
		if player.Parent == nil then
			return false, nil, false
		end
		setLoading(player, attempt)
		local lockedByOther = false
		local newer = false
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old: Record?)
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
					and attempt < Settings.LOAD_ATTEMPTS
				then
					lockedByOther = true
					return nil -- n'écrit rien : on réessaie plus tard
				end
				lockedByOther = false
				record.lock = { jobId = game.JobId, time = os.time(), session = session }
				record.meta = record.meta or { created = os.time(), saves = 0 }
				return record
			end)
		end)
		if ok and newer then
			return false, nil, true
		elseif ok and not lockedByOther then
			local record = result :: Record?
			return true, if record then record.data else nil, false
		elseif ok then
			warn(
				`[DataService] données de {player.Name} verrouillées par un autre serveur, essai {attempt}/{Settings.LOAD_ATTEMPTS}`
			)
			task.wait(Settings.LOCKED_RETRY_DELAY)
		else
			warn(`[DataService] échec de chargement pour {player.Name} (essai {attempt}) :`, result)
			task.wait(math.min(2 ^ attempt, 16) * Settings.RETRY_BASE_DELAY)
		end
	end
	return false, nil, false
end

-- Libère le verrou pris par CE chargement sans toucher aux données (session partie pendant son
-- chargement). Le jeton évite d'effacer le verrou d'une reconnexion du même UserId sur ce serveur
-- (même JobId), chargée entre-temps.
local function releaseLoadLock(player: Player, session: string)
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old: Record?)
			local lock = if old then old.lock else nil
			if old and lock and lock.jobId == game.JobId and lock.session == session then
				old.lock = nil
				return old
			end
			return nil
		end)
	end)
	if not ok then
		warn(`[DataService] libération du verrou de {player.Name} en échec :`, err)
	end
end

local function writeRecord(player: Player, data: { [string]: any }, release: boolean): boolean
	local key = keyFor(player)
	local snapshot = Tables.deepCopy(data)
	local session = sessions[player]
	for attempt = 1, Settings.SAVE_ATTEMPTS do
		local lostLock = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old: Record?)
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
				return record
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
				return false
			end
			return true
		end
		warn(`[DataService] échec de sauvegarde pour {player.Name} (essai {attempt}) :`, err)
		if attempt < Settings.SAVE_ATTEMPTS then
			task.wait(math.min(2 ^ attempt, 8) * Settings.RETRY_BASE_DELAY)
		end
	end
	return false
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
	-- crochets synchrones (ex. règlement du revenu passif) avant l'instantané écrit
	for _, fn in beforeSave do
		local ok, err = pcall(fn, player, data, release)
		if not ok then
			warn("[DataService] crochet onBeforeSave en échec :", err)
		end
	end
	saving[player] = true
	local ok = writeRecord(player, data, release)
	saving[player] = nil
	if release then
		releasedOk[player] = ok
	end
	return ok
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
		local start = os.clock()
		while pendingRelease[userId] and player.Parent ~= nil and os.clock() - start < Settings.REJOIN_WAIT do
			task.wait(0.1)
		end
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
	local data = prepare(raw)
	sessions[player] = session
	profiles[player] = data
	releasedOk[player] = nil
	releasing[player] = nil
	sendSnapshot(player, data)
	DataService.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	if profiles[player] then
		local userId = player.UserId
		pendingRelease[userId] = (pendingRelease[userId] or 0) + 1
		-- protégé : une erreur ne doit jamais laisser ce UserId « en cours de départ » pour toujours
		local ok, err = pcall(save, player, true)
		if not ok then
			warn(`[DataService] sauvegarde de départ de {player.Name} en erreur :`, err)
		end
		local left = (pendingRelease[userId] or 1) - 1
		pendingRelease[userId] = if left > 0 then left else nil
	end
	profiles[player] = nil
	pending[player] = nil
	saving[player] = nil
	releasedOk[player] = nil
	releasing[player] = nil
	sessions[player] = nil
	streams[player] = nil
end

function DataService.Init()
	snapshotRemote = Net.event("DataSnapshot")
	patchRemote = Net.event("DataPatch")

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Schema.STORE_NAME)
	end)
	if ok then
		store = result :: any
		if RunService:IsStudio() then
			local probeOk, probeErr = pcall(function()
				store:GetAsync("__studio_probe")
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
	else
		warn("[DataService] GetDataStore a échoué :", result, "— sauvegarde en mémoire.")
		store = memoryStore()
		DataService.usingMemoryStore = true
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
	RunService.Heartbeat:Connect(stepStreams)
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
		local remaining = 0
		for player in profiles do
			remaining += 1
			task.spawn(function()
				save(player, true)
				remaining -= 1
			end)
		end
		local start = os.clock()
		while remaining > 0 and os.clock() - start < Settings.CLOSE_TIMEOUT do
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
-- envoie la table entière, sauf une grande table (STREAMED_KEYS) : ses SNAPSHOT_INLINE premières
-- entrées, le reste en flux d'entrées DataPatch juste après.
function DataService.markDirtyEntry(player: Player, key: string, subKey: string)
	if profiles[player] then
		queueEntry(player, key, subKey)
	end
end

function DataService.saveNow(player: Player): boolean
	return save(player, false)
end

-- Enregistre un crochet appelé (sans yield) juste avant chaque sauvegarde du joueur :
-- autosave, saveNow, départ et BindToClose. `release` vaut true pour la sauvegarde de libération
-- (départ, BindToClose) : le travail « de départ » doit être fait là, le Player peut encore être
-- dans l'arbre (BindToClose) et aucune sauvegarde ne suivra.
function DataService.onBeforeSave(fn: (Player, { [string]: any }, boolean?) -> ())
	table.insert(beforeSave, fn)
end

-- Ordre d'envoi des entrées d'une grande table à l'arrivée (instantané puis flux) : fn(data)
-- retourne les sous-clés de data[key] par priorité (ex. AtlasService : les perchés d'abord)
function DataService.setStreamOrder(key: string, fn: ({ [string]: any }) -> { string })
	streamOrder[key] = fn
end

return DataService
