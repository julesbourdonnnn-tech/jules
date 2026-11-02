--!strict
-- Garde du paquet meta (docs/04 §1 règles 3, 13, 18 ; §10.1 ; §17.3).
--   * Guard.connect(nom, handler) : ordre de chaque handler d'intention — débit (RateLimit, valeurs de
--     Config/Intents) → types (sortes d'arguments de Config/Intents) → handler protégé par pcall
--     (existence, état, règles, mutation) → si le handler rend true (intention ACCEPTÉE) et que
--     l'intention est marquée activity = true : Activity.note(player, Clock.now()).
--   * Guard.try / Guard.caught : une erreur est comptée par DiagnosticsService.reportCaught, jamais
--     propagée ; si Diagnostics lui-même échoue, un warn la rend visible (zéro trace : la spec échoue),
--     sauf pour l'erreur « TODO(<paquet>) » d'un stub d'un autre paquet (connu, compté dans stubbed).
--   * Guard.call(où, fn, repli, ...) : appel vers un service d'un autre paquet ; repli si erreur ou nil.
--   * Guard.arg / Guard.args : validation des sortes d'arguments (aussi utilisée par les specs).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Intents = require(Shared.Config.Intents)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Activity = require(script.Parent.Parent.Util.Activity)

local Guard = {}

local MAX_USER_ID = 2 ^ 53

Guard.stubbed = {} :: { [string]: string }

-- Compteur d'erreurs : branché par DiagnosticsService (Init) pour éviter un require circulaire
local reporter: ((string, any) -> ())? = nil

function Guard.setReporter(fn: (string, any) -> ())
	reporter = fn
end

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Guard.finite = finite

local function isStub(err: any): boolean
	return string.find(tostring(err), "TODO(", 1, true) ~= nil
end

function Guard.caught(where: string, err: any)
	if isStub(err) then
		Guard.stubbed[where] = tostring(err)
		return
	end
	local fn = reporter
	local ok, failure = false, "Diagnostics absent"
	if fn ~= nil then
		ok, failure = pcall(fn, where, err)
	end
	if not ok then
		warn(`[meta] {where} : {tostring(err)} ({tostring(failure)})`)
	end
end

function Guard.try(where: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		Guard.caught(where, results[2])
		return false
	end
	return true, table.unpack(results, 2, results.n)
end

function Guard.call(where: string, fn: any, fallback: any, ...: any): any
	if type(fn) ~= "function" then
		return fallback
	end
	local ok, value = pcall(fn, ...)
	if not ok then
		Guard.caught(where, value)
		return fallback
	end
	if value == nil then
		return fallback
	end
	return value
end

function Guard.uid(x: any): boolean
	return type(x) == "string" and #x >= 1 and #x <= 8 and string.match(x, "^[0-9a-z]+$") ~= nil
end

-- Table séquentielle sans trou ni clé étrangère, de min à max éléments
local function sequence(t: any, min: number, max: number): boolean
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for k in t do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 or k > max then
			return false
		end
		n += 1
		if n > max then
			return false
		end
	end
	if n < min then
		return false
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

local function userId(x: any): boolean
	return finite(x) and x % 1 == 0 and x > 0 and x <= MAX_USER_ID
end

-- Valide un argument selon sa sorte (Config/Intents) ; rend (ok, valeur normalisée)
function Guard.arg(spec: Intents.ArgSpec, value: any): (boolean, any)
	local kind = spec.kind
	if kind == "uid" then
		return Guard.uid(value), value
	elseif kind == "uidOpt" then
		return value == nil or Guard.uid(value), value
	elseif kind == "uids" then
		if not sequence(value, 1, spec.max or 1) then
			return false, nil
		end
		local seen: { [string]: boolean } = {}
		for _, uid in value do
			if not Guard.uid(uid) or seen[uid] then
				return false, nil
			end
			seen[uid] = true
		end
		return true, table.clone(value)
	elseif kind == "time" or kind == "dir" then
		return finite(value), value
	elseif kind == "bool" then
		return type(value) == "boolean", value
	elseif kind == "int" then
		return finite(value)
			and value % 1 == 0
			and value >= (spec.min or -math.huge)
			and value <= (spec.max or math.huge),
			value
	elseif kind == "userId" then
		return userId(value), value
	elseif kind == "userIds" then
		if not sequence(value, 0, spec.max or 0) then
			return false, nil
		end
		for _, id in value do
			if not userId(id) then
				return false, nil
			end
		end
		return true, table.clone(value)
	elseif kind == "key" then
		return type(value) == "string" and spec.set ~= nil and table.find(spec.set, value) ~= nil, value
	elseif kind == "str" then
		if type(value) ~= "string" then
			return false, nil
		end
		local max = spec.max or 64
		if #value > max then
			if not spec.truncate then
				return false, nil
			end
			-- coupe puis valide : jamais une séquence UTF-8 cassée au bord
			local cut = string.sub(value, 1, max)
			while #cut > 0 and utf8.len(cut) == nil do
				cut = string.sub(cut, 1, #cut - 1)
			end
			return true, cut
		end
		if utf8.len(value) == nil then
			return false, nil
		end
		return true, value
	elseif kind == "setting" then
		return type(value) == "boolean" or (type(value) == "string" and #value <= 64 and utf8.len(value) ~= nil),
			value
	end
	return false, nil
end

-- Valide tous les arguments d'une intention ; rend (ok, arguments normalisés)
function Guard.args(name: string, ...: any): (boolean, { any })
	local spec = Intents[name]
	if spec == nil then
		return false, {}
	end
	local raw = table.pack(...)
	local out = {}
	for i, argSpec in spec.args do
		local ok, value = Guard.arg(argSpec, raw[i])
		if not ok then
			return false, {}
		end
		out[i] = value
	end
	return true, out
end

-- Branche le handler d'une intention : handler(player, ...) rend true si l'intention est acceptée
function Guard.connect(name: string, handler: (Player, ...any) -> boolean?)
	local spec = Intents[name]
	assert(spec ~= nil, `Guard.connect : intention inconnue « {name} »`)
	local count = #spec.args
	Net.event(name).OnServerEvent:Connect(function(player: Player, ...: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		if not RateLimit.allow(player, name, spec.rate[1], spec.rate[2]) then
			return
		end
		local ok, args = Guard.args(name, ...)
		if not ok then
			return
		end
		local done, accepted = Guard.try("intent:" .. name, handler, player, table.unpack(args, 1, count))
		if done and accepted == true and spec.activity == true then
			Activity.note(player, Clock.now())
		end
	end)
end

return Guard
