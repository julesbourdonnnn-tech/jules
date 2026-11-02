--!nocheck
-- Tests du vrai moteur Roblox (couche i, docs/04 §17.1) : `lune run tools/opencloud/run-server-tests`
-- depuis la racine du dépôt. Variables : ROBLOX_API_KEY, UNIVERSE_ID, PLACE_ID (place de test PRIVÉE,
-- jamais la place du jeu). Code de sortie : 0 vert, 1 échec, 2 non lancé (pas de clé). Voir README.md.
local process = require("@lune/process")
local net = require("@lune/net")
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local task = require("@lune/task")
local OpenCloud = require("./OpenCloud")

local deps = {
	print = print,
	request = function(req)
		local ok, res = pcall(net.request, req)
		if not ok then
			return { ok = false, statusCode = 0, body = tostring(res) }
		end
		return res
	end,
	build = function()
		local result = process.exec("rojo", { "build", OpenCloud.PROJECT, "-o", OpenCloud.PLACE_FILE })
		return result.ok, result.stderr
	end,
	readFile = function(path)
		return fs.readFile(path)
	end,
	encode = function(t)
		return serde.encode("json", t)
	end,
	decode = function(s)
		return serde.decode("json", s)
	end,
	wait = function(s)
		task.wait(s)
	end,
}

process.exit(OpenCloud.main(process.env, deps))
