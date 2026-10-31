--!nocheck
-- Fil réseau simulé entre un serveur complet et un client complet (tests d'intégration).
--
-- Le harnais n'admet qu'un DataModel « actif » à la fois (crochets globaux de MockInstance :
-- FireClient, méthodes de classe des services, personnages…). On ne fait donc pas tourner serveur
-- et client en même temps : on ENREGISTRE ce que le vrai serveur envoie à un joueur (remotes
-- FireClient / FireAllClients, attributs répliqués des joueurs et du monde, perchoirs, position de
-- son personnage), puis on le REJOUE dans le vrai client, au même instant de l'horloge partagée.
-- Chaque charge utile est copiée avec les règles de sérialisation des remotes Roblox ; toute
-- violation (table mixte ou à trous, clés non chaînes d'un dictionnaire, NaN/±inf, fonction,
-- Instance, métatable, buffer non fiable > 900 octets) est consignée dans `rec.problems`.
--
--   local rec = Wire.record(serverH, { userId = 1, Clock = ServerClock })
--   … partie serveur (Bots) avec w.onFrame = function() rec:frame() end …
--   rec:stop()
--   local server = Wire.saveContext()           -- avant Harness.new du client
--   local c = Harness.new({ mode = "client" }) ; c:createRemotes()
--   Wire.installWorld(rec, c) ; c:boot()
--   Wire.replay(rec, c, { Clock = ClientClock })
--   Wire.restoreContext(server)                 -- pour reparler au serveur (intentions du client)

local MockInstance = require("./MockInstance")

local Wire = {}

local UNRELIABLE_LIMIT = 900 -- octets (UnreliableRemoteEvent)
local IMMUTABLE = {
	Vector3 = true,
	Vector2 = true,
	CFrame = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	EnumItem = true,
	BrickColor = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	Rect = true,
}

-- -------------------------------------------------------------------------------------------
-- Sérialisation (règles des remotes Roblox)
-- -------------------------------------------------------------------------------------------

local function copyValue(value, path, problems, seen)
	local t = typeof(value)
	if t == "nil" or t == "boolean" or t == "string" then
		return value
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			table.insert(problems, `{path} : nombre non fini ({value})`)
		end
		return value
	elseif t == "buffer" then
		local copy = buffer.create(buffer.len(value))
		buffer.copy(copy, 0, value)
		return copy
	elseif IMMUTABLE[t] then
		return value
	elseif MockInstance.is(value) then
		table.insert(problems, `{path} : Instance dans une charge utile ({value:GetFullName()})`)
		return value
	elseif t ~= "table" then
		table.insert(problems, `{path} : type {t} non transmissible`)
		return nil
	end
	if seen[value] then
		table.insert(problems, `{path} : table cyclique ou partagée`)
		return nil
	end
	seen[value] = true
	if getmetatable(value) ~= nil then
		table.insert(problems, `{path} : métatable (perdue par le réseau)`)
	end
	local n = #value
	local count, strings, others = 0, 0, 0
	for k in value do
		count += 1
		if type(k) == "string" then
			strings += 1
		elseif not (type(k) == "number" and k % 1 == 0 and k >= 1 and k <= n) then
			others += 1
		end
	end
	local out = {}
	if count == n then
		for i = 1, n do
			out[i] = copyValue(value[i], `{path}[{i}]`, problems, seen)
		end
	elseif strings == count then
		for k, v in value do
			out[k] = copyValue(v, `{path}.{k}`, problems, seen)
		end
	else
		local keys = {}
		for k in value do
			table.insert(keys, tostring(k))
			if #keys >= 6 then
				break
			end
		end
		table.insert(
			problems,
			`{path} : table mixte, à trous ou à clés non chaînes (clés : {table.concat(keys, ", ")}…) — altérée par le réseau`
		)
		for k, v in value do
			out[k] = copyValue(v, `{path}.{tostring(k)}`, problems, seen)
		end
	end
	seen[value] = nil
	return out
end

-- Copie des arguments d'un envoi ; les violations vont dans `problems` (préfixées par `label`)
function Wire.copyArgs(label, problems, ...)
	local args = table.pack(...)
	local out = { n = args.n }
	for i = 1, args.n do
		out[i] = copyValue(args[i], `{label}#{i}`, problems, {})
	end
	return out
end

-- -------------------------------------------------------------------------------------------
-- Contextes du harnais (un DataModel actif à la fois)
-- -------------------------------------------------------------------------------------------

local HOOKS = {
	"onFireClient",
	"onFireAllClients",
	"onFireServer",
	"onInvokeServer",
	"localPlayer",
	"onLoadCharacter",
	"onKick",
	"serviceFactory",
	"areFriends",
	"warnings",
}

function Wire.saveContext()
	local ctx = { classMethods = table.clone(MockInstance.classMethods), hooks = {} }
	for _, key in HOOKS do
		ctx.hooks[key] = MockInstance[key]
	end
	return ctx
end

function Wire.restoreContext(ctx)
	local cm = MockInstance.classMethods
	table.clear(cm)
	for k, v in ctx.classMethods do
		cm[k] = v
	end
	for _, key in HOOKS do
		MockInstance[key] = ctx.hooks[key]
	end
end

-- -------------------------------------------------------------------------------------------
-- Enregistrement (côté serveur)
-- -------------------------------------------------------------------------------------------

local Recorder = {}
Recorder.__index = Recorder

local function relativePath(inst, root)
	local parts = {}
	local cur = inst
	while cur and cur ~= root do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	if cur ~= root then
		return nil
	end
	return table.concat(parts, ".")
end

-- h : harnais serveur DÉJÀ démarré (h:boot) ; opts.userId : joueur observé (nil = vérifier la
-- sérialisation de tous les envois sans rien enregistrer pour un client) ; opts.Clock : horloge
-- partagée du serveur ; opts.remotes : noms de remotes dont on garde aussi TOUS les envois
-- (`rec.sent[nom]`, pour vérifier les textes par exemple)
function Wire.record(h, opts)
	local rec = setmetatable({
		h = h,
		userId = opts.userId,
		Clock = opts.Clock,
		events = {},
		problems = {},
		counts = {},
		sent = {},
		keep = {},
		perchCounts = {},
		lastPos = nil,
		active = true,
	}, Recorder)
	for _, name in opts.remotes or {} do
		rec.keep[name] = true
		rec.sent[name] = {}
	end
	local lumora = h.workspace:FindFirstChild("Lumora")
	rec.lumora = lumora
	if lumora and rec.userId then
		rec.world = lumora:Clone()
		for _, nest in lumora.Nests:GetChildren() do
			local perches = nest:FindFirstChild("Perches")
			rec.perchCounts[nest.Name] = if perches then #perches:GetChildren() else 0
		end
	end

	local function observed()
		return rec.userId and h.game.Players:GetPlayerByUserId(rec.userId)
	end

	local function push(e)
		e.t = rec.Clock.now()
		table.insert(rec.events, e)
	end

	local function onSend(remote, kind, player, ...)
		if not rec.active then
			return
		end
		local name = remote.Name
		rec.counts[name] = (rec.counts[name] or 0) + 1
		local args = Wire.copyArgs(name, rec.problems, ...)
		if remote.ClassName == "UnreliableRemoteEvent" then
			for i = 1, args.n do
				if typeof(args[i]) == "buffer" and buffer.len(args[i]) > UNRELIABLE_LIMIT then
					table.insert(rec.problems, `{name} : buffer de {buffer.len(args[i])} octets (> 900)`)
				end
			end
		end
		if rec.keep[name] then
			table.insert(rec.sent[name], { player = player, args = args })
		end
		local target = observed()
		if target and (kind == "all" or player == target) then
			push({ kind = "remote", remote = name, args = args })
		end
	end

	rec.prevClient = MockInstance.onFireClient
	rec.prevAll = MockInstance.onFireAllClients
	MockInstance.onFireClient = function(remote, player, ...)
		rec.prevClient(remote, player, ...)
		onSend(remote, "client", player, ...)
	end
	MockInstance.onFireAllClients = function(remote, ...)
		rec.prevAll(remote, ...)
		onSend(remote, "all", nil, ...)
	end

	if rec.userId then
		rec.prevSetAttribute = MockInstance.Methods.SetAttribute
		MockInstance.Methods.SetAttribute = function(self, name, value)
			rec.prevSetAttribute(self, name, value)
			if not rec.active then
				return
			end
			if self.ClassName == "Player" and self.Parent == h.game.Players then
				push({ kind = "attr", userId = self.UserId, name = name, value = value })
			elseif lumora and self:IsDescendantOf(lumora) then
				local path = relativePath(self, lumora)
				if path then
					push({ kind = "attr", path = path, name = name, value = value })
				end
			end
		end
		rec.connections = {
			h.game.Players.PlayerAdded:Connect(function(p)
				if rec.active then
					push({ kind = "join", userId = p.UserId, name = p.Name, displayName = p.DisplayName })
				end
			end),
			h.game.Players.PlayerRemoving:Connect(function(p)
				if rec.active then
					push({ kind = "leave", userId = p.UserId })
				end
			end),
		}
		local function watch(p)
			table.insert(
				rec.connections,
				p.CharacterAdded:Connect(function()
					if rec.active then
						push({ kind = "spawn" })
					end
				end)
			)
		end
		local current = observed()
		if current then
			watch(current)
		end
		-- joueurs déjà présents : un client qui arrive reçoit leurs attributs actuels
		for _, p in h.game.Players:GetPlayers() do
			push({ kind = "join", userId = p.UserId, name = p.Name, displayName = p.DisplayName })
			for name, value in p:GetAttributes() do
				push({ kind = "attr", userId = p.UserId, name = name, value = value })
			end
		end
		table.insert(
			rec.connections,
			h.game.Players.PlayerAdded:Connect(function(p)
				if p.UserId == rec.userId then
					watch(p)
				end
			end)
		)
	end
	return rec
end

-- À appeler à chaque tick serveur (Bots : w.onFrame) : position du personnage observé, perchoirs
function Recorder:frame()
	if not self.active or not self.userId then
		return
	end
	local p = self.h.game.Players:GetPlayerByUserId(self.userId)
	local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local pos = root.Position
		if self.lastPos == nil or (pos - self.lastPos).Magnitude > 0.01 then
			self.lastPos = pos
			table.insert(self.events, { kind = "pos", t = self.Clock.now(), pos = pos })
		end
	end
	if self.lumora then
		for _, nest in self.lumora.Nests:GetChildren() do
			local perches = nest:FindFirstChild("Perches")
			local n = if perches then #perches:GetChildren() else 0
			if n ~= self.perchCounts[nest.Name] then
				self.perchCounts[nest.Name] = n
				table.insert(self.events, {
					kind = "perches",
					t = self.Clock.now(),
					nest = nest.Name,
					folder = if perches then perches:Clone() else nil,
				})
			end
		end
	end
end

function Recorder:stop()
	if not self.active then
		return
	end
	self.active = false
	MockInstance.onFireClient = self.prevClient
	MockInstance.onFireAllClients = self.prevAll
	if self.prevSetAttribute then
		MockInstance.Methods.SetAttribute = self.prevSetAttribute
	end
	for _, conn in self.connections or {} do
		conn:Disconnect()
	end
end

-- Nombre d'événements enregistrés d'un type ou d'un remote
function Recorder:count(remote)
	local n = 0
	for _, e in self.events do
		if e.kind == "remote" and e.remote == remote then
			n += 1
		end
	end
	return n
end

-- -------------------------------------------------------------------------------------------
-- Rejeu (côté client)
-- -------------------------------------------------------------------------------------------

-- Monde construit par le serveur (copie prise au début de l'enregistrement) : à poser AVANT le
-- démarrage du client (les contrôleurs lisent les tags au Start)
function Wire.installWorld(rec, c)
	if rec.world then
		rec.world:Clone().Parent = c.workspace
	end
end

local function clientPlayer(c, userId, name, displayName)
	local p = c.game.Players:GetPlayerByUserId(userId)
	if p then
		return p
	end
	return c:addPlayer({
		userId = userId,
		name = name or ("P" .. userId),
		displayName = displayName,
		spawn = false,
	})
end

local function resolve(root, path)
	local cur = root
	for part in string.gmatch(path, "[^%.]+") do
		cur = cur and cur:FindFirstChild(part)
	end
	return cur
end

-- Rejoue les événements [from, to] dans le client `c` (démarré). opts.Clock : horloge du client ;
-- opts.frameDt : pas des images (0,1 par défaut) ; opts.maxGap : au-delà, saut dans le temps ;
-- opts.onFrame(t) : appelé après chaque image ; opts.onEvent(e) : événements d'un autre type
-- (points de contrôle ajoutés par la spec). Retourne l'index du dernier événement rejoué.
function Wire.replay(rec, c, opts)
	local Clock = opts.Clock
	local dt = opts.frameDt or 0.1
	local maxGap = opts.maxGap or 3
	local from = opts.from or 1
	local to = opts.to or #rec.events
	local lumora = c.workspace:FindFirstChild("Lumora")
	local localPlayer = c.localPlayer
	local function frame()
		c:step(dt)
		if opts.onFrame then
			opts.onFrame(Clock.now())
		end
	end
	for i = from, to do
		local e = rec.events[i]
		local now = Clock.now()
		if e.t - now > maxGap then
			Clock.freeze(e.t - dt)
			frame()
		end
		while Clock.now() + dt <= e.t + 1e-6 do
			Clock.advance(dt)
			frame()
		end
		if e.kind == "remote" then
			c:fireClient("ReplicatedStorage.Remotes." .. e.remote, table.unpack(e.args, 1, e.args.n))
		elseif e.kind == "attr" then
			local target
			if e.userId then
				target = if e.userId == localPlayer.UserId then localPlayer else clientPlayer(c, e.userId)
			elseif lumora then
				target = resolve(lumora, e.path)
			end
			if target then
				target:SetAttribute(e.name, e.value)
			end
		elseif e.kind == "join" then
			if e.userId ~= localPlayer.UserId then
				clientPlayer(c, e.userId, e.name, e.displayName)
			end
		elseif e.kind == "leave" then
			local p = c.game.Players:GetPlayerByUserId(e.userId)
			if p and p ~= localPlayer then
				c:removePlayer(p)
			end
		elseif e.kind == "spawn" then
			c:respawn(localPlayer)
		elseif e.kind == "pos" then
			local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = c.globals.CFrame.new(e.pos)
			end
		elseif e.kind == "perches" and lumora then
			local nest = lumora.Nests:FindFirstChild(e.nest)
			if nest then
				local old = nest:FindFirstChild("Perches")
				if old then
					old:Destroy()
				end
				if e.folder then
					e.folder:Clone().Parent = nest
				end
			end
		elseif opts.onEvent then
			opts.onEvent(e)
		end
	end
	return to
end

return Wire
