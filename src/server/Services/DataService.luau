--!strict
-- DataService : sauvegarde joueur sans perte.
--  * verrou de session (un seul serveur écrit les données d'un joueur)
--  * UpdateAsync partout, retries avec backoff, autosave, BindToClose
--  * schéma versionné (Data/Schema.luau) : defaults + migrations + reconcile
--  * réplication vers le client : instantané au chargement, puis patchs groupés par frame
--  * repli en mémoire dans Studio quand l'accès API est désactivé
--
-- API :
--   DataService.get(player) -> données vivantes ou nil (pas encore chargées)
--   DataService.waitFor(player, timeout?) -> données ou nil
--   DataService.Loaded:Connect(function(player, data) end)
--   DataService.set(player, key, value)          -- clé de 1er niveau + réplication
--   DataService.increment(player, key, delta)    -- nombres
--   DataService.markDirty(player, key)           -- après mutation d'une table imbriquée
--   DataService.saveNow(player) -> boolean       -- sauvegarde immédiate (achats)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Tables = require(Shared.Util.Tables)
local Schema = require(script.Parent.Parent.Data.Schema)

-- Réglages (modifiables par les tests avant le démarrage)
local Settings = {
	LOCK_EXPIRY = 30 * 60, -- un verrou plus vieux que 30 min est considéré abandonné
	LOAD_ATTEMPTS = 6,
	LOCKED_RETRY_DELAY = 5,
	RETRY_BASE_DELAY = 1, -- backoff : 2, 4, 8… × base
	SAVE_ATTEMPTS = 4,
	AUTOSAVE_INTERVAL = 90,
	CLOSE_TIMEOUT = 25,
}

type Record = {
	data: { [string]: any }?,
	lock: { jobId: string, time: number }?,
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

local store: Store
local profiles: { [Player]: { [string]: any } } = {}
local saving: { [Player]: boolean } = {}
local pendingPatch: { [Player]: { [string]: boolean } } = {}
local flushScheduled = false
local released: { [Player]: boolean } = {}
local releasing: { [Player]: boolean } = {}

local snapshotRemote: RemoteEvent
local patchRemote: RemoteEvent

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

local function flushPatches()
	flushScheduled = false
	for player, keys in pendingPatch do
		local data = profiles[player]
		if data and player.Parent then
			local patch = {}
			local any = false
			for key in keys do
				if not Schema.PRIVATE_KEYS[key] then
					-- une valeur nil est transmise via la liste `removed`
					patch[key] = data[key]
					any = true
				end
			end
			if any then
				local removed = {}
				for key in keys do
					if data[key] == nil and not Schema.PRIVATE_KEYS[key] then
						table.insert(removed, key)
					end
				end
				patchRemote:FireClient(player, patch, removed)
			end
		end
	end
	table.clear(pendingPatch)
end

local function queuePatch(player: Player, key: string)
	local keys = pendingPatch[player]
	if not keys then
		keys = {}
		pendingPatch[player] = keys
	end
	keys[key] = true
	if not flushScheduled then
		flushScheduled = true
		task.defer(flushPatches)
	end
end

local function prepare(raw: { [string]: any }?): { [string]: any }
	local data: { [string]: any } = if raw then raw else Schema.defaults()
	local version = data.version or 0
	if version < Schema.VERSION then
		data = Schema.migrate(data, version)
		data.version = Schema.VERSION
	end
	Tables.reconcile(data, Schema.defaults())
	return data
end

local function loadRecord(player: Player): (boolean, { [string]: any }?)
	local key = keyFor(player)
	for attempt = 1, Settings.LOAD_ATTEMPTS do
		if player.Parent == nil then
			return false, nil
		end
		local lockedByOther = false
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old: Record?)
				local record: Record = old or {}
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
				record.lock = { jobId = game.JobId, time = os.time() }
				record.meta = record.meta or { created = os.time(), saves = 0 }
				return record
			end)
		end)
		if ok and not lockedByOther then
			local record = result :: Record?
			return true, if record then record.data else nil
		elseif ok then
			warn(`[DataService] données de {player.Name} verrouillées par un autre serveur, essai {attempt}/{Settings.LOAD_ATTEMPTS}`)
			task.wait(Settings.LOCKED_RETRY_DELAY)
		else
			warn(`[DataService] échec de chargement pour {player.Name} (essai {attempt}) :`, result)
			task.wait(math.min(2 ^ attempt, 16) * Settings.RETRY_BASE_DELAY)
		end
	end
	return false, nil
end

local function writeRecord(player: Player, data: { [string]: any }, release: boolean): boolean
	local key = keyFor(player)
	local snapshot = Tables.deepCopy(data)
	for attempt = 1, Settings.SAVE_ATTEMPTS do
		local lostLock = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old: Record?)
				local record: Record = old or {}
				local lock = record.lock
				if lock and lock.jobId ~= game.JobId then
					-- un autre serveur a repris la session : ne jamais écraser ses données
					lostLock = true
					return nil
				end
				lostLock = false
				record.data = snapshot
				record.lock = if release then nil else { jobId = game.JobId, time = os.time() }
				local meta = record.meta or { created = os.time(), saves = 0 }
				meta.lastSave = os.time()
				meta.saves = (meta.saves or 0) + 1
				record.meta = meta
				return record
			end)
		end)
		if ok then
			if lostLock then
				warn(`[DataService] session de {player.Name} reprise par un autre serveur : sauvegarde ignorée`)
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
	if released[player] then
		return true
	end
	if not release and releasing[player] then
		return false
	end
	saving[player] = true
	local ok = writeRecord(player, data, release)
	saving[player] = nil
	if release then
		released[player] = true
	end
	return ok
end

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	local ok, raw = loadRecord(player)
	if player.Parent == nil then
		-- parti pendant le chargement : libérer le verrou sans toucher aux données
		if ok then
			pcall(function()
				store:UpdateAsync(keyFor(player), function(old: Record?)
					if old and old.lock and old.lock.jobId == game.JobId then
						old.lock = nil
						return old
					end
					return nil
				end)
			end)
		end
		return
	end
	if not ok then
		player:Kick("Your data could not be loaded. Please rejoin in a moment. / Tes données n'ont pas pu être chargées, reviens dans un instant.")
		return
	end
	local data = prepare(raw)
	profiles[player] = data
	released[player] = nil
	releasing[player] = nil
	snapshotRemote:FireClient(player, publicView(data))
	DataService.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	if profiles[player] then
		save(player, true)
	end
	profiles[player] = nil
	pendingPatch[player] = nil
	saving[player] = nil
	released[player] = nil
	releasing[player] = nil
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
				warn("[DataService] DataStore indisponible dans Studio (", probeErr, ") : sauvegarde EN MÉMOIRE uniquement.")
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
		local data = profiles[player]
		if data then
			snapshotRemote:FireClient(player, publicView(data))
		end
	end)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
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

function DataService.saveNow(player: Player): boolean
	return save(player, false)
end

return DataService
