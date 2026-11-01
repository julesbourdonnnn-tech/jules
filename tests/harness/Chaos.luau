--!nocheck
-- Chaos (paquet ranch, docs/04 §17.1 couche e) : DataStore en désordre pour les specs de données.
-- Un magasin PARTAGÉ par plusieurs serveurs (harnais, JobId distincts : méthode de
-- Fix_final_data_lock), avec :
--   * pannes par type d'appel (shared.fail.UpdateAsync = n : les n prochains UpdateAsync échouent),
--     panne totale (shared.down = true) ;
--   * latence (shared.latency s de vraie attente par appel) ;
--   * quotas (shared.quota = n appels par fenêtre de shared.quotaWindow s : au-delà, erreur « 429 ») ;
--   * refus des valeurs que Roblox perdrait (tableaux à trous, tables mixtes, NaN, infini, clés non
--     chaînes d'un dictionnaire) : l'écriture échoue comme dans Roblox ;
--   * journal de chaque valeur écrite (shared.writes) et crochet shared.onWrite(key, value) appelé
--     après chaque écriture acceptée (ex. Invariants.dense sur les tableaux du profil).
--
--   local Chaos = require("../harness/Chaos")
--   local shared = Chaos.store()
--   local w = Chaos.boot(Harness, Bots, shared, "A", { t0 = T0 })   -- serveur complet branché sur `shared`
--   shared.fail.UpdateAsync = 2
--   Chaos.record(shared, userId)                                    -- profil sauvegardé (ou nil)

local task = require("@lune/task")
local MockInstance = require("./MockInstance")

local Chaos = {}

local STORE_NAME = "PlayerData_v1"

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

local function finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Valeur que Roblox sérialise sans perte (sinon : message d'erreur et chemin)
function Chaos.check(value, path)
	path = path or "valeur"
	local t = type(value)
	if t == "number" then
		if not finite(value) then
			return false, path .. " : nombre non fini"
		end
		return true
	elseif t == "string" or t == "boolean" or t == "nil" then
		return true
	elseif t ~= "table" then
		return false, path .. " : type " .. t
	end
	local numeric, strings, n = 0, 0, 0
	for k in value do
		n += 1
		if type(k) == "number" then
			numeric += 1
			if k < 1 or k % 1 ~= 0 then
				return false, path .. " : clé numérique " .. tostring(k)
			end
		elseif type(k) == "string" then
			strings += 1
		else
			return false, path .. " : clé de type " .. type(k)
		end
	end
	if numeric > 0 and strings > 0 then
		return false, path .. " : table mixte (tableau + dictionnaire)"
	end
	if numeric > 0 then
		for i = 1, numeric do
			if value[i] == nil then
				return false, path .. " : tableau à trous (index " .. i .. ")"
			end
		end
	end
	for k, v in value do
		local ok, why = Chaos.check(v, path .. "." .. tostring(k))
		if not ok then
			return false, why
		end
	end
	return true
end

-- Magasin partagé
function Chaos.store()
	local shared = {
		data = {},
		down = false,
		fail = { GetAsync = 0, UpdateAsync = 0, SetAsync = 0, RemoveAsync = 0 },
		latency = 0,
		quota = nil,
		quotaWindow = 60,
		calls = {},
		writes = {},
		onWrite = nil,
		refused = {},
	}

	local function gate(server, op)
		local now = os.clock()
		table.insert(shared.calls, { server = server, op = op, at = now })
		if shared.latency > 0 then
			task.wait(shared.latency)
		else
			task.wait()
		end
		if shared.down then
			error(`502: API Services rejected request ({op}) [panne simulée]`, 0)
		end
		if (shared.fail[op] or 0) > 0 then
			shared.fail[op] -= 1
			error(`502: API Services rejected request ({op}) [panne simulée]`, 0)
		end
		if shared.quota then
			local recent = 0
			for _, c in shared.calls do
				if c.server == server and now - c.at <= shared.quotaWindow then
					recent += 1
				end
			end
			if recent > shared.quota then
				error(`429: DataStore request was throttled ({op}) [quota simulé]`, 0)
			end
		end
	end

	local function store(key, value)
		local ok, why = Chaos.check(value, key)
		if not ok then
			table.insert(shared.refused, why)
			error("104: Cannot store value in data store [Chaos] " .. why, 0)
		end
		shared.data[key] = deepCopy(value)
		table.insert(shared.writes, { key = key, value = deepCopy(value) })
		if shared.onWrite then
			shared.onWrite(key, deepCopy(value))
		end
	end

	-- Vue d'un serveur (objet compatible DataStore pour DataService)
	function shared.view(server)
		local view = {}
		function view.GetAsync(_self, key)
			gate(server, "GetAsync")
			return deepCopy(shared.data[key]), { Version = "1" }
		end
		function view.SetAsync(_self, key, value)
			gate(server, "SetAsync")
			store(key, value)
			return "1"
		end
		function view.UpdateAsync(_self, key, fn)
			gate(server, "UpdateAsync")
			local new = fn(deepCopy(shared.data[key]), { Version = "1" })
			if new ~= nil then
				store(key, new)
			end
			return deepCopy(shared.data[key])
		end
		function view.RemoveAsync(_self, key)
			gate(server, "RemoveAsync")
			local old = shared.data[key]
			shared.data[key] = nil
			return deepCopy(old)
		end
		return view
	end

	return shared
end

-- Profil sauvegardé d'un joueur (copie), nil s'il n'y en a pas
function Chaos.record(shared, userId)
	local record = shared.data["player_" .. tostring(userId)]
	return if record then deepCopy(record.data) else nil
end

-- Écrit un profil sauvegardé (sans verrou) avant l'arrivée d'un joueur
function Chaos.seed(shared, userId, data)
	shared.data["player_" .. tostring(userId)] = { data = deepCopy(data) }
end

-- Serveur complet (Bots.boot) dont le magasin des profils est la vue `server` de `shared`. Le
-- remplacement de GetDataStore ne dure que le démarrage (DataService.Init) : les autres harnais et les
-- autres magasins (Diagnostics, classements) gardent le DataStore simulé ordinaire.
function Chaos.boot(Harness, Bots, shared, server, opts)
	opts = opts or {}
	-- Harness.new recrée les méthodes simulées des services : on branche la vue APRÈS sa création
	local cm, original = nil, nil
	local userBefore = opts.before
	local w
	local ok, err = pcall(function()
		w = Bots.boot(
			Harness,
			setmetatable({
				before = function(world)
					world.h.game.JobId = server
					cm = MockInstance.classMethods.DataStoreService
					original = cm.GetDataStore
					cm.GetDataStore = function(self, name, scope)
						if name == STORE_NAME then
							return shared.view(server)
						end
						return original(self, name, scope)
					end
					if userBefore then
						userBefore(world)
					end
				end,
			}, { __index = opts })
		)
	end)
	if cm ~= nil then
		cm.GetDataStore = original
	end
	assert(ok, err)
	return w
end

return Chaos
