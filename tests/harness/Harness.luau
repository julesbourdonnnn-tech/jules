--!nocheck
-- Harnais : monte l'arborescence Rojo (src/) dans un DataModel simulé et exécute
-- les modules avec un `require(script.Parent.X)` fidèle à Roblox.
--
--   local h = Harness.new({ mode = "server" })
--   local Config = h:require("ReplicatedStorage.Shared.Config")
--   h:boot()                                   -- lance Main.server.luau
--   local alice = h:addPlayer({ userId = 1, name = "Alice" })
--   h:fireServer("ReplicatedStorage.Remotes.Buy", alice, "item")
--   h:step(1/60, 30)                           -- 30 frames de Heartbeat

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local MockInstance = require("./MockInstance")
local Services = require("./Services")
local Signal = require("./Signal")

local Harness = {}
Harness.__index = Harness

local ROOT = "."

-- Types de données Roblox fournis par Lune (+ compléments simulés)
local function datatypes()
	local t = {}
	for _, name in
		{
			"Vector2",
			"Vector3",
			"Vector2int16",
			"Vector3int16",
			"CFrame",
			"Color3",
			"ColorSequence",
			"ColorSequenceKeypoint",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"NumberRange",
			"UDim",
			"UDim2",
			"Rect",
			"Ray",
			"Region3",
			"Region3int16",
			"BrickColor",
			"PhysicalProperties",
			"Font",
			"Faces",
			"Axes",
			"Content",
		}
	do
		t[name] = roblox[name]
	end
	t.Enum = roblox.Enum

	t.TweenInfo = {
		new = function(time, style, direction, repeatCount, reverses, delayTime)
			return table.freeze({
				Time = time or 1,
				EasingStyle = style or roblox.Enum.EasingStyle.Quad,
				EasingDirection = direction or roblox.Enum.EasingDirection.Out,
				RepeatCount = repeatCount or 0,
				Reverses = reverses or false,
				DelayTime = delayTime or 0,
			})
		end,
	}

	local RandomMT = {}
	RandomMT.__index = RandomMT
	function RandomMT:NextNumber(a, b)
		a = a or 0
		b = b or 1
		return a + (b - a) * self._r()
	end
	function RandomMT:NextInteger(a, b)
		return math.floor(a + (b - a + 1) * self._r())
	end
	function RandomMT:Shuffle(tbl)
		for i = #tbl, 2, -1 do
			local j = self:NextInteger(1, i)
			tbl[i], tbl[j] = tbl[j], tbl[i]
		end
	end
	function RandomMT:Clone()
		return setmetatable({ _r = self._r }, RandomMT)
	end
	function RandomMT:NextUnitVector()
		return roblox.Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1)).Unit
	end
	t.Random = {
		new = function(seed)
			-- générateur déterministe (LCG) pour des tests reproductibles
			local state = math.floor(seed or 12345) % 2147483647
			if state <= 0 then
				state += 2147483646
			end
			return setmetatable({
				_r = function()
					state = (state * 16807) % 2147483647
					return (state - 1) / 2147483646
				end,
			}, RandomMT)
		end,
	}

	t.RaycastParams = {
		new = function()
			return {
				FilterType = roblox.Enum.RaycastFilterType.Exclude,
				FilterDescendantsInstances = {},
				IgnoreWater = false,
				CollisionGroup = "Default",
				AddToFilter = function() end,
			}
		end,
	}
	t.OverlapParams = t.RaycastParams
	t.DateTime = {
		now = function()
			local ms = math.floor(os.time() * 1000)
			return { UnixTimestamp = os.time(), UnixTimestampMillis = ms }
		end,
		fromUnixTimestamp = function(s)
			return { UnixTimestamp = s, UnixTimestampMillis = s * 1000 }
		end,
	}
	return t
end

local function mount(h, parent, dirPath: string)
	for _, entry in fs.readDir(dirPath) do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			local initPath = nil
			for _, candidate in { "init.luau", "init.lua", "init.server.luau", "init.client.luau" } do
				if fs.isFile(full .. "/" .. candidate) then
					initPath = full .. "/" .. candidate
				end
			end
			local node
			if initPath then
				local class = if initPath:match("%.server%.luau$")
					then "Script"
					elseif initPath:match("%.client%.luau$") then "LocalScript"
					else "ModuleScript"
				node = MockInstance.new(class)
				h.sources[node] = initPath
			else
				node = MockInstance.new("Folder")
			end
			node.Name = entry
			node.Parent = parent
			mount(h, node, full)
		elseif not entry:match("^init%.") then
			local name, class
			name = entry:match("^(.+)%.server%.luau$")
			if name then
				class = "Script"
			else
				name = entry:match("^(.+)%.client%.luau$")
				if name then
					class = "LocalScript"
				else
					name = entry:match("^(.+)%.luau$") or entry:match("^(.+)%.lua$")
					class = "ModuleScript"
				end
			end
			if name then
				local node = MockInstance.new(class)
				node.Name = name
				node.Parent = parent
				h.sources[node] = full
			end
		end
	end
end

function Harness.new(options: { mode: string?, touch: boolean?, isStudio: boolean?, root: string? }?)
	options = options or {}
	local h = setmetatable({}, Harness)
	h.mode = options.mode or "server"
	h.touch = options.touch == true
	h.isStudio = options.isStudio == true
	h.root = options.root or ROOT
	h.sources = {}
	h.cache = {}
	h.loading = {}
	h.renderSteps = {}
	h.actions = {}
	h.errors = {}
	h.log = {
		kicks = {},
		prompts = {},
		badges = {},
		messages = {},
		invites = {},
		analytics = {},
		output = {},
		clientEvents = {},
		allClientEvents = {},
		serverEvents = {},
	}
	h.stats = { tweens = 0, dataStoreCalls = 0 }
	MockInstance.warnings = {}

	-- remise à zéro des crochets globaux (un harnais à la fois)
	MockInstance.onFireClient = function(remote, player, ...)
		table.insert(h.log.clientEvents, { remote = remote.Name, player = player, args = table.pack(...) })
	end
	MockInstance.onFireAllClients = function(remote, ...)
		table.insert(h.log.allClientEvents, { remote = remote.Name, args = table.pack(...) })
	end
	MockInstance.onFireServer = function(remote, ...)
		table.insert(h.log.serverEvents, { remote = remote.Name, args = table.pack(...) })
	end
	MockInstance.localPlayer = nil

	local game = MockInstance.new("DataModel")
	game.Name = "Game"
	game.PlaceId = 0
	game.GameId = 0
	game.JobId = "test-job-" .. tostring(math.random(1, 1e6))
	game.PlaceVersion = 1
	game.CreatorId = 0
	h.game = game
	MockInstance.classMethods.DataModel = {
		BindToClose = function(_, fn)
			h.closeCallbacks = h.closeCallbacks or {}
			table.insert(h.closeCallbacks, fn)
		end,
		IsLoaded = function()
			return true
		end,
	}
	game.Loaded = Signal.new()

	Services.install(h)

	-- Montage Rojo
	local shared = MockInstance.new("Folder")
	shared.Name = "Shared"
	shared.Parent = game.ReplicatedStorage
	mount(h, shared, h.root .. "/src/shared")
	local server = MockInstance.new("Folder")
	server.Name = "Server"
	server.Parent = game.ServerScriptService
	if h.mode == "server" then
		mount(h, server, h.root .. "/src/server")
	end
	local client = MockInstance.new("Folder")
	client.Name = "Client"
	client.Parent = game.StarterPlayer.StarterPlayerScripts
	mount(h, client, h.root .. "/src/client")

	h.globals = h:_makeGlobals()

	if h.mode == "client" then
		local lp = h:_newPlayer({ userId = 1, name = "LocalTester" })
		lp.Parent = game.Players
		game.Players.LocalPlayer = lp
		MockInstance.localPlayer = lp
		h.localPlayer = lp
		local playerGui = MockInstance.new("PlayerGui")
		playerGui.Name = "PlayerGui"
		playerGui.Parent = lp
		local ps = MockInstance.new("PlayerScripts")
		ps.Name = "PlayerScripts"
		ps.Parent = lp
		MockInstance.onLoadCharacter(lp)
	end
	return h
end

function Harness:_makeGlobals()
	local h = self
	local g = datatypes()
	g.game = self.game
	g.workspace = self.game.Workspace
	g.Workspace = self.game.Workspace
	g.task = task
	g.Instance = {
		new = function(className: string, parent: any?)
			assert(type(className) == "string", "Instance.new : nom de classe attendu")
			local inst = MockInstance.new(className)
			if parent then
				inst.Parent = parent
			end
			return inst
		end,
		fromExisting = function(inst)
			return inst:Clone()
		end,
	}
	g.typeof = function(v)
		if MockInstance.is(v) then
			return "Instance"
		end
		if type(v) == "table" and getmetatable(v) == Signal then
			return "RBXScriptSignal"
		end
		return typeof(v)
	end
	g.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		table.insert(h.log.output, table.concat(parts, " "))
	end
	g.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		table.insert(h.log.output, "WARN " .. table.concat(parts, " "))
	end
	g.tick = os.clock
	local t0 = os.clock()
	g.time = function()
		return os.clock() - t0
	end
	g.elapsedTime = g.time
	g.wait = function()
		error("wait() est interdit : utiliser task.wait()", 2)
	end
	g.spawn = function()
		error("spawn() est interdit : utiliser task.spawn()", 2)
	end
	g.delay = function()
		error("delay() est interdit : utiliser task.delay()", 2)
	end
	g.settings = function()
		return { Rendering = { QualityLevel = 10 } }
	end
	g.UserSettings = function()
		return {
			GetService = function()
				return { SavedQualityLevel = roblox.Enum.SavedQualitySetting.Automatic }
			end,
		}
	end
	g.shared = {}
	g.require = function(target)
		return h:_require(target)
	end
	return g
end

function Harness:_envFor(node)
	local env = table.clone(self.globals)
	env.script = node
	return env
end

function Harness:_require(target)
	if not MockInstance.is(target) then
		error(`require : ModuleScript attendu, reçu {typeof(target)} ({tostring(target)})`, 3)
	end
	if target.ClassName ~= "ModuleScript" then
		error(`require : {target:GetFullName()} n'est pas un ModuleScript`, 3)
	end
	if self.cache[target] ~= nil then
		return self.cache[target].value
	end
	if self.loading[target] then
		error(`require circulaire détecté sur {target:GetFullName()}`, 3)
	end
	local path = self.sources[target]
	assert(path, `ModuleScript sans source : {target:GetFullName()}`)
	self.loading[target] = true
	local source = fs.readFile(path)
	local chunk = luau.load(source, { debugName = path, environment = self:_envFor(target) })
	local results = table.pack(chunk())
	self.loading[target] = nil
	if results.n ~= 1 then
		error(`Le module {path} doit retourner exactement une valeur (reçu {results.n})`, 3)
	end
	self.cache[target] = { value = results[1] }
	return results[1]
end

-- Résout "ReplicatedStorage.Shared.Config" en instance
function Harness:find(path: string)
	local cur = self.game
	for part in string.gmatch(path, "[^%.]+") do
		local nxt = cur:FindFirstChild(part)
		if not nxt then
			error(`[harness] introuvable : {path} (bloqué à {part})`, 2)
		end
		cur = nxt
	end
	return cur
end

function Harness:require(path: string)
	return self:_require(self:find(path))
end

-- Exécute un Script/LocalScript ; les erreurs sont collectées dans h.errors
function Harness:run(path: string)
	local node = self:find(path)
	local src = self.sources[node]
	assert(src, `pas de source pour {path}`)
	local chunk = luau.load(fs.readFile(src), { debugName = src, environment = self:_envFor(node) })
	local ok, err = pcall(chunk)
	if not ok then
		table.insert(self.errors, `{src}: {err}`)
		error(err, 0)
	end
end

function Harness:boot()
	if self.mode == "server" then
		self:run("ServerScriptService.Server.Main")
	else
		self:run("StarterPlayer.StarterPlayerScripts.Client.Main")
	end
	task.wait()
end

function Harness:_newPlayer(opts)
	local p = MockInstance.new("Player")
	p.Name = opts.name or ("Player" .. tostring(opts.userId))
	p.DisplayName = opts.displayName or p.Name
	p.UserId = opts.userId
	p.LocaleId = opts.locale or "en-us"
	p.AccountAge = opts.accountAge or 100
	p.MembershipType = roblox.Enum.MembershipType.None
	p.Character = nil
	p.Team = nil
	p.Neutral = true
	p.FollowUserId = 0
	p.CameraMaxZoomDistance = 128
	p.CameraMinZoomDistance = 0.5
	return p
end

function Harness:addPlayer(opts: { userId: number, name: string?, locale: string?, spawn: boolean? })
	local p = self:_newPlayer(opts)
	p.Parent = self.game.Players
	self.game.Players.PlayerAdded:Fire(p)
	if opts.spawn ~= false then
		task.wait()
		MockInstance.onLoadCharacter(p)
	end
	task.wait()
	return p
end

function Harness:removePlayer(p)
	self.game.Players.PlayerRemoving:Fire(p)
	if p.Character then
		p.Character:Destroy()
		p.Character = nil
	end
	p.Parent = nil
	task.wait()
end

function Harness:respawn(p)
	MockInstance.onLoadCharacter(p)
	task.wait()
end

-- (mode client) crée ReplicatedStorage.Remotes comme le ferait Net.setup() côté serveur
function Harness:createRemotes()
	if self.game.ReplicatedStorage:FindFirstChild("Remotes") then
		return
	end
	local classes = { event = "RemoteEvent", unreliable = "UnreliableRemoteEvent", func = "RemoteFunction" }
	local folder = MockInstance.new("Folder")
	folder.Name = "Remotes"
	for name, kind in self:require("ReplicatedStorage.Shared.Remotes") do
		local remote = MockInstance.new(classes[kind])
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = self.game.ReplicatedStorage
end

-- Laisse les threads en attente (DataStore simulé, task.defer…) se terminer
function Harness:settle(frames: number?)
	for _ = 1, frames or 5 do
		task.wait()
	end
end

-- Erreurs survenues dans des connexions de signaux depuis le début du test
function Harness:signalErrors()
	return table.clone(Signal.errors)
end

function Harness:step(dt: number?, frames: number?)
	local rs = self.game.RunService
	for _ = 1, frames or 1 do
		rs.Stepped:Fire(os.clock(), dt or 1 / 60)
		rs.Heartbeat:Fire(dt or 1 / 60)
		rs.PreSimulation:Fire(dt or 1 / 60)
		rs.PostSimulation:Fire(dt or 1 / 60)
		if self.mode == "client" then
			rs.RenderStepped:Fire(dt or 1 / 60)
			rs.PreRender:Fire(dt or 1 / 60)
			for _, fn in self.renderSteps do
				fn(dt or 1 / 60)
			end
		end
		task.wait()
	end
end

-- Simule un client qui déclenche un RemoteEvent
function Harness:fireServer(path: string, player, ...)
	local remote = self:find(path)
	remote.OnServerEvent:Fire(player, ...)
	task.wait()
end

-- Simule un client qui invoque une RemoteFunction
function Harness:invokeServer(path: string, player, ...)
	local remote = self:find(path)
	local cb = remote.OnServerInvoke
	assert(cb, `{path} n'a pas de OnServerInvoke`)
	return cb(player, ...)
end

-- Simule le serveur qui envoie un événement au client (mode client)
function Harness:fireClient(path: string, ...)
	local remote = self:find(path)
	remote.OnClientEvent:Fire(...)
	task.wait()
end

-- Simule un achat de produit développeur et retourne la décision
function Harness:purchaseProduct(player, productId: number, purchaseId: string?)
	local cb = self.game.MarketplaceService.ProcessReceipt
	assert(cb, "ProcessReceipt n'est pas défini")
	return cb({
		PlayerId = player.UserId,
		ProductId = productId,
		PurchaseId = purchaseId or self.game.HttpService:GenerateGUID(false),
		CurrencySpent = 99,
		CurrencyType = roblox.Enum.CurrencyType.Robux,
		PlaceIdWherePurchased = 0,
	})
end

function Harness:grantPass(player, passId: number)
	self.ownedPasses[player.UserId] = self.ownedPasses[player.UserId] or {}
	self.ownedPasses[player.UserId][passId] = true
	self.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, passId, true)
	task.wait()
end

function Harness:close()
	for _, fn in self.closeCallbacks or {} do
		fn()
	end
end

function Harness:warnings()
	local out = table.clone(MockInstance.warnings)
	for _, line in self.log.output do
		if line:sub(1, 5) == "WARN " then
			table.insert(out, line)
		end
	end
	return out
end

-- Événements envoyés à un joueur sur un remote donné
function Harness:sentTo(player, remoteName: string)
	local out = {}
	for _, e in self.log.clientEvents do
		if e.player == player and e.remote == remoteName then
			table.insert(out, e.args)
		end
	end
	return out
end

return Harness
