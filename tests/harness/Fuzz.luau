--!nocheck
-- Fuzz (paquet meta, docs/04 §17.1 b) : chaque remote attaqué, d'après le catalogue Config/Intents.
--   Fuzz.hostile(kind?)                      -- valeurs hostiles (génériques + propres à la sorte)
--   Fuzz.valid(spec, opts?)                  -- une charge utile valide (tableau des arguments)
--   Fuzz.payloads(spec, opts?)               -- charges hostiles : chaque argument remplacé tour à tour
--                                               par chaque valeur hostile, plus aucun argument, des
--                                               arguments en trop et tout à nil
--   Fuzz.attack(h, player, name, n?, opts?)  -- envoie les charges hostiles de l'intention `name`
--                                               (n au plus) au nom de `player` ; rend le nombre envoyé ;
--                                               opts.tick() après chaque charge (os.clock simulé) ;
--                                               opts.typeHostileOnly : seulement les charges refusées
--                                               par la couche des types (aucune mutation permise)
--   Fuzz.profileUnchanged(h, player, fn)     -- (ok, chemin du premier écart) : profil de `player`
--                                               identique avant et après fn
--   Fuzz.rate(h, player, name, n?, opts?)    -- rafale de n (1 000) charges VALIDES : rend le nombre de
--                                               messages passés par RateLimit pour cette intention
--                                               (horloge os.clock figée par la spec : Bots.fakeOsClock)
-- opts : { uid = "1" (uid possédé), otherUid = "x" (uid d'un autre), userId = 2, set = { … } }.
-- Une charge hostile ne doit produire AUCUNE mutation du profil, aucune erreur (ZeroLog) et au plus un
-- Feedback neutre ; la spec qui appelle vérifie ces règles.
local roblox = require("@lune/roblox")
local Intents = require("../../src/shared/Config/Intents")

local Fuzz = {}

local NAN = 0 / 0

local function deep(depth)
	local t = {}
	local cur = t
	for _ = 1, depth do
		local nxt = {}
		cur.x = nxt
		cur = nxt
	end
	return t
end

-- Valeurs hostiles communes à toutes les sortes d'arguments
function Fuzz.generic()
	return {
		{ label = "nil", value = nil },
		{ label = "NaN", value = NAN },
		{ label = "+inf", value = math.huge },
		{ label = "-inf", value = -math.huge },
		{ label = "1e308", value = 1e308 },
		{ label = "-1e308", value = -1e308 },
		{ label = "-0", value = -0 },
		{ label = "0.5", value = 0.5 },
		{ label = "-1", value = -1 },
		{ label = "2^53+2", value = 2 ^ 53 + 2 },
		{ label = "true", value = true },
		{ label = "false", value = false },
		{ label = "chaîne vide", value = "" },
		{ label = "100 000 caractères", value = string.rep("A", 100000) },
		{ label = "UTF-8 invalide", value = "\xff\xfe\xc0\x80" },
		{ label = "octets nuls", value = "a\0b" },
		{ label = "table vide", value = {} },
		{ label = "table profonde", value = deep(60) },
		{ label = "table mixte", value = { 1, 2, x = 3 } },
		{ label = "table à trous", value = { [1] = "1", [3] = "3" } },
		{ label = "clés négatives", value = { [-1] = "1" } },
		{ label = "Vector3", value = roblox.Vector3.new(1, 2, 3) },
		{ label = "CFrame", value = roblox.CFrame.new() },
	}
end

-- Valeurs hostiles propres à une sorte (en plus des génériques)
function Fuzz.hostile(kind, opts)
	opts = opts or {}
	local list = Fuzz.generic()
	local function add(label, value)
		table.insert(list, { label = label, value = value })
	end
	if kind == "uid" or kind == "uidOpt" then
		add("uid trop long", "123456789")
		add("uid majuscules", "ABC")
		add("uid avec espace", "1 2")
		add("uid avec motif", "%d+")
		add("uid nombre", 1)
		if opts.otherUid then
			add("uid d'un autre joueur", opts.otherUid)
		end
		add("uid inconnu", "zzzzzzzz")
	elseif kind == "uids" then
		add("uids doublons", { "1", "1" })
		add("uids 1 000", table.create(1000, "1"))
		add("uids nombres", { 1, 2 })
		add("uids vide", {})
		if opts.otherUid then
			add("uids d'un autre", { opts.otherUid })
		end
	elseif kind == "int" then
		add("int très grand", 1e9)
		add("int min − 1", -100)
		add("int chaîne", "1")
	elseif kind == "userId" then
		add("userId 0", 0)
		add("userId négatif", -5)
		add("userId chaîne", "1")
		add("userId inconnu", 987654321)
	elseif kind == "userIds" then
		add("userIds 201", table.create(201, 5))
		add("userIds chaînes", { "1" })
		add("userIds négatifs", { -1 })
		add("userIds NaN", { NAN })
	elseif kind == "key" then
		add("clé inconnue", "__index")
		add("clé majuscules", "OBJECTIVES")
		add("clé nombre", 1)
	elseif kind == "str" then
		add("str 10 000", string.rep("é", 5000))
		add("str UTF-8 coupée", string.rep("a", 63) .. "\xc3")
	elseif kind == "setting" then
		add("setting nombre", 1)
		add("setting chaîne longue", string.rep("x", 200))
	elseif kind == "time" or kind == "dir" then
		add("temps futur", 1e12)
		add("temps chaîne", "0")
	elseif kind == "bool" then
		add("bool nombre", 1)
		add("bool chaîne", "true")
	end
	return list
end

-- Valeur valide d'une sorte
local function validFor(arg, opts)
	local kind = arg.kind
	if kind == "uid" then
		return opts.uid or "1"
	elseif kind == "uidOpt" then
		return nil
	elseif kind == "uids" then
		return { opts.uid or "1" }
	elseif kind == "time" then
		return opts.time or 0
	elseif kind == "dir" then
		return 1
	elseif kind == "bool" then
		return true
	elseif kind == "int" then
		return arg.min or 1
	elseif kind == "userId" then
		return opts.userId or 1
	elseif kind == "userIds" then
		return {}
	elseif kind == "key" then
		return (opts.set and opts.set[arg.name]) or (arg.set and arg.set[1]) or ""
	elseif kind == "str" then
		return (opts.str and opts.str[arg.name]) or "a"
	elseif kind == "setting" then
		return true
	end
	return nil
end

local function specOf(spec)
	if type(spec) == "string" then
		local s = Intents[spec]
		assert(s, "Fuzz : intention inconnue " .. spec)
		return s
	end
	return spec
end

function Fuzz.valid(spec, opts)
	spec = specOf(spec)
	opts = opts or {}
	local out = { n = #spec.args }
	for i, arg in spec.args do
		out[i] = validFor(arg, opts)
	end
	return out
end

local function finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function sequence(t, min, max)
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for k in t do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 or k > max then
			return false
		end
		n += 1
	end
	if n < min or n > max then
		return false
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

local function uidOk(x)
	return type(x) == "string" and #x >= 1 and #x <= 8 and string.match(x, "^[0-9a-z]+$") ~= nil
end

local function userIdOk(x)
	return finite(x) and x % 1 == 0 and x > 0 and x <= 2 ^ 53
end

-- La valeur passe-t-elle la couche des TYPES de Config/Intents (même règles que les gardes des
-- services) ? Une charge dont chaque argument passe n'est pas « hostile par les types » : seules les
-- règles métier la refusent (ou l'acceptent : arguments en trop, liste vide…)
function Fuzz.typeValid(arg, value)
	local kind = arg.kind
	if kind == "uid" then
		return uidOk(value)
	elseif kind == "uidOpt" then
		return value == nil or uidOk(value)
	elseif kind == "uids" then
		if not sequence(value, 1, arg.max or 1) then
			return false
		end
		local seen = {}
		for _, u in value do
			if not uidOk(u) or seen[u] then
				return false
			end
			seen[u] = true
		end
		return true
	elseif kind == "time" or kind == "dir" then
		return finite(value)
	elseif kind == "bool" then
		return type(value) == "boolean"
	elseif kind == "int" then
		return finite(value)
			and value % 1 == 0
			and value >= (arg.min or -math.huge)
			and value <= (arg.max or math.huge)
	elseif kind == "userId" then
		return userIdOk(value)
	elseif kind == "userIds" then
		if not sequence(value, 0, arg.max or 0) then
			return false
		end
		for _, id in value do
			if not userIdOk(id) then
				return false
			end
		end
		return true
	elseif kind == "key" then
		return type(value) == "string" and arg.set ~= nil and table.find(arg.set, value) ~= nil
	elseif kind == "str" then
		if type(value) ~= "string" then
			return false
		end
		if #value > (arg.max or 64) then
			return arg.truncate == true
		end
		return utf8.len(value) ~= nil
	elseif kind == "setting" then
		return type(value) == "boolean"
			or (type(value) == "string" and #value <= 64 and utf8.len(value) ~= nil)
	end
	return false
end

-- Charges hostiles : { label, args (table.pack), valid } ; valid = chaque argument passe la couche des
-- types (seules les règles métier décident : une telle charge peut être acceptée)
function Fuzz.payloads(spec, opts)
	spec = specOf(spec)
	opts = opts or {}
	local out = {}
	local base = Fuzz.valid(spec, opts)
	for i, arg in spec.args do
		for _, h in Fuzz.hostile(arg.kind, opts) do
			local args = table.clone(base)
			args[i] = h.value
			args.n = #spec.args
			table.insert(out, { label = arg.name .. " = " .. h.label, args = args })
		end
	end
	table.insert(out, { label = "aucun argument", args = { n = 0 } })
	local all = { n = #spec.args }
	table.insert(out, { label = "tout à nil", args = all })
	local extra = table.clone(base)
	extra.n = #spec.args + 3
	extra[#spec.args + 1] = string.rep("B", 1000)
	extra[#spec.args + 2] = deep(30)
	extra[#spec.args + 3] = NAN
	table.insert(out, { label = "arguments en trop", args = extra })
	for _, entry in out do
		local valid = true
		for i, arg in spec.args do
			if not Fuzz.typeValid(arg, entry.args[i]) then
				valid = false
				break
			end
		end
		entry.valid = valid
	end
	return out
end

local function remotePath(name)
	return "ReplicatedStorage.Remotes." .. name
end

function Fuzz.attack(h, player, name, n, opts)
	local list = Fuzz.payloads(name, opts)
	local limit = math.min(#list, n or #list)
	local sent = 0
	for i = 1, limit do
		local args = list[i].args
		if not (opts and opts.typeHostileOnly and list[i].valid) then
			sent += 1
			h:fireServer(remotePath(name), player, table.unpack(args, 1, args.n))
		end
		-- opts.tick() : la spec fait avancer son os.clock simulé (chaque charge passe le débit et
		-- atteint vraiment la validation du handler)
		if opts and type(opts.tick) == "function" then
			opts.tick(list[i])
		end
	end
	return sent
end

-- Copie profonde comparable (les types Roblox comparés par tostring)
local function snapshotOf(v, depth, seen)
	depth = depth or 0
	if type(v) ~= "table" then
		if type(v) == "number" and v ~= v then
			return "NaN"
		end
		if typeof(v) ~= type(v) then
			return typeof(v) .. ":" .. tostring(v)
		end
		return v
	end
	seen = seen or {}
	if seen[v] or depth > 40 then
		return "<cycle>"
	end
	seen[v] = true
	local out = {}
	for k, x in v do
		out[k] = snapshotOf(x, depth + 1, seen)
	end
	seen[v] = nil
	return out
end

local function diff(a, b, path)
	if type(a) ~= type(b) then
		return path
	end
	if type(a) ~= "table" then
		return if a == b then nil else path
	end
	for k, v in a do
		local d = diff(v, b[k], path .. "." .. tostring(k))
		if d then
			return d
		end
	end
	for k in b do
		if a[k] == nil then
			return path .. "." .. tostring(k)
		end
	end
	return nil
end

function Fuzz.profileUnchanged(h, player, fn, ignore)
	local DS = h:require("ServerScriptService.Server.Services.DataService")
	local before = snapshotOf(DS.get(player))
	fn()
	local after = snapshotOf(DS.get(player))
	if type(ignore) == "table" and type(before) == "table" and type(after) == "table" then
		for _, key in ignore do
			before[key] = nil
			after[key] = nil
		end
	end
	local d = diff(before, after, "profil")
	return d == nil, d
end

function Fuzz.rate(h, player, name, n, opts)
	local RateLimit = h:require("ServerScriptService.Server.Util.RateLimit")
	local original = RateLimit.allow
	local passed = 0
	RateLimit.allow = function(p, action, ...)
		local ok = original(p, action, ...)
		if ok and p == player and action == name then
			passed += 1
		end
		return ok
	end
	local args = Fuzz.valid(name, opts)
	local ok, err = pcall(function()
		for _ = 1, n or 1000 do
			local remote = h:find(remotePath(name))
			remote.OnServerEvent:Fire(player, table.unpack(args, 1, args.n))
		end
		h:settle(2)
	end)
	RateLimit.allow = original
	if not ok then
		error(err, 0)
	end
	return passed
end

return Fuzz
