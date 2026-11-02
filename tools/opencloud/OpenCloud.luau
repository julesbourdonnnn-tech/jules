--!nocheck
-- OpenCloud (paquet meta, docs/04 §17.1 i) : suite des tests serveur PORTABLES dans de vrais serveurs
-- Roblox. Fonctions pures (testées par tests/specs/OpenCloud.spec.luau) et `main(env, deps)` : les
-- appels réseau, Rojo et l'horloge sont injectés (deps), jamais appelés au chargement du module.
--   1. construit la place de test (rojo build tests/engine.project.json -o build/EngineTests.rbxl) ;
--   2. la publie comme nouvelle version d'une PLACE DE TEST PRIVÉE :
--      POST /universes/v1/{universeId}/places/{placeId}/versions?versionType=Saved (x-api-key) ;
--   3. crée une tâche d'exécution Luau sur cette version :
--      POST /cloud/v2/universes/{u}/places/{p}/versions/{v}/luau-execution-session-tasks
--      (script : le lanceur ServerStorage.EngineTests.Runner, qui rend le bilan en JSON ; timeout 300 s) ;
--   4. attend l'état COMPLETE ou FAILED, lit les journaux ({tâche}/logs) ;
--   5. échoue (code 1) si un test échoue ou si une ligne Error / Warning apparaît ; 0 si tout est vert.
-- Clé et identifiants par variables d'environnement (ROBLOX_API_KEY, UNIVERSE_ID, PLACE_ID), jamais dans
-- le dépôt ; sans clé : message clair et code 2 (« non lancé »).

local OpenCloud = {}

OpenCloud.BASE = "https://apis.roblox.com"
OpenCloud.PLACE_FILE = "build/EngineTests.rbxl"
OpenCloud.PROJECT = "tests/engine.project.json"
OpenCloud.TIMEOUT = 300 -- s : durée maximale de la tâche (Open Cloud)
OpenCloud.POLL_EVERY = 3 -- s entre deux lectures de l'état de la tâche
OpenCloud.POLL_MAX = 140 -- lectures au plus (≈ 7 min)
OpenCloud.EXIT_OK = 0
OpenCloud.EXIT_FAILED = 1
OpenCloud.EXIT_NOT_RUN = 2

-- Script exécuté dans le serveur : le lanceur rend le bilan (JSON) comme résultat de la tâche
OpenCloud.SCRIPT = table.concat({
	'local Runner = require(game:GetService("ServerStorage"):WaitForChild("EngineTests", 30):WaitForChild("Runner", 30))',
	"return Runner.runJson()",
}, "\n")

-- Configuration depuis l'environnement ; (config, nil) ou (nil, message)
function OpenCloud.config(env)
	env = env or {}
	local key, universe, place = env.ROBLOX_API_KEY, env.UNIVERSE_ID, env.PLACE_ID
	local missing = {}
	if type(key) ~= "string" or key == "" then
		table.insert(missing, "ROBLOX_API_KEY")
	end
	if type(universe) ~= "string" or not string.match(universe, "^%d+$") then
		table.insert(missing, "UNIVERSE_ID")
	end
	if type(place) ~= "string" or not string.match(place, "^%d+$") then
		table.insert(missing, "PLACE_ID")
	end
	if #missing > 0 then
		return nil,
			"Tests du vrai moteur NON LANCÉS : variable(s) manquante(s) "
				.. table.concat(missing, ", ")
				.. ". Voir tools/opencloud/README.md (clé Open Cloud d'une place de test privée)."
	end
	return { apiKey = key, universeId = universe, placeId = place }, nil
end

-- Requête de publication d'une version (corps : la place binaire .rbxl)
function OpenCloud.publishRequest(cfg, placeBytes)
	return {
		method = "POST",
		url = string.format(
			"%s/universes/v1/%s/places/%s/versions?versionType=Saved",
			OpenCloud.BASE,
			cfg.universeId,
			cfg.placeId
		),
		headers = { ["x-api-key"] = cfg.apiKey, ["Content-Type"] = "application/octet-stream" },
		body = placeBytes,
	}
end

-- Requête de création de la tâche d'exécution Luau sur la version publiée
function OpenCloud.taskRequest(cfg, version, encodeJson)
	return {
		method = "POST",
		url = string.format(
			"%s/cloud/v2/universes/%s/places/%s/versions/%s/luau-execution-session-tasks",
			OpenCloud.BASE,
			cfg.universeId,
			cfg.placeId,
			tostring(version)
		),
		headers = { ["x-api-key"] = cfg.apiKey, ["Content-Type"] = "application/json" },
		body = encodeJson({ script = OpenCloud.SCRIPT, timeout = tostring(OpenCloud.TIMEOUT) .. "s" }),
	}
end

-- Lecture d'une ressource (état de la tâche, journaux) ; `path` = chemin rendu par l'API (« universes/… »)
function OpenCloud.getRequest(cfg, path)
	return {
		method = "GET",
		url = OpenCloud.BASE .. "/cloud/v2/" .. string.gsub(path, "^/", ""),
		headers = { ["x-api-key"] = cfg.apiKey },
	}
end

function OpenCloud.logsRequest(cfg, taskPath)
	return OpenCloud.getRequest(cfg, taskPath .. "/logs?view=STRUCTURED")
end

-- Bilan du lanceur (résultat de la tâche) : { passed, failed, failures, errors }
function OpenCloud.parseSummary(task, decodeJson)
	if type(task) ~= "table" then
		return nil
	end
	local output = task.output
	local results = type(output) == "table" and output.results or nil
	local raw = type(results) == "table" and results[1] or nil
	if type(raw) == "string" then
		local ok, decoded = pcall(decodeJson, raw)
		raw = if ok then decoded else nil
	end
	if type(raw) ~= "table" or type(raw.passed) ~= "number" or type(raw.failed) ~= "number" then
		return nil
	end
	return raw
end

-- Lignes d'erreur ou d'avertissement des journaux (structurés ou texte)
function OpenCloud.badLogLines(logs)
	local out = {}
	if type(logs) ~= "table" then
		return out
	end
	for _, page in logs.luauExecutionSessionTaskLogs or {} do
		for _, entry in page.structuredMessages or {} do
			local kind = tostring(entry.messageType or "")
			if string.find(kind, "ERROR", 1, true) or string.find(kind, "WARNING", 1, true) then
				table.insert(out, kind .. " " .. tostring(entry.message))
			end
		end
		for _, line in page.messages or {} do
			if string.find(line, "Error", 1, true) or string.find(line, "Warning", 1, true) then
				table.insert(out, line)
			end
		end
	end
	return out
end

-- Verdict final : code de sortie et lignes à imprimer
function OpenCloud.verdict(state, summary, badLines)
	local lines = {}
	if state ~= "COMPLETE" then
		table.insert(lines, "Tâche terminée dans l'état " .. tostring(state))
		return OpenCloud.EXIT_FAILED, lines
	end
	if summary == nil then
		table.insert(lines, "Bilan du lanceur illisible")
		return OpenCloud.EXIT_FAILED, lines
	end
	table.insert(
		lines,
		string.format("%d réussis, %d échoués (vrai moteur)", summary.passed, summary.failed)
	)
	for _, f in summary.failures or {} do
		table.insert(lines, "✗ " .. tostring(f))
	end
	for _, e in summary.errors or {} do
		table.insert(lines, "erreur du moteur : " .. tostring(e))
	end
	for _, l in badLines do
		table.insert(lines, "journal : " .. l)
	end
	local ok = summary.failed == 0 and #(summary.errors or {}) == 0 and #badLines == 0
	return if ok then OpenCloud.EXIT_OK else OpenCloud.EXIT_FAILED, lines
end

-- Programme complet ; deps = { print, request(req) → { ok, statusCode, body }, build() → (ok, msg),
-- readFile(path), encode(t), decode(s), wait(s) } ; rend le code de sortie
function OpenCloud.main(env, deps)
	local say = deps.print or print
	local cfg, message = OpenCloud.config(env)
	if cfg == nil then
		say(message)
		return OpenCloud.EXIT_NOT_RUN
	end
	local built, why = deps.build()
	if not built then
		say("Construction de la place de test impossible : " .. tostring(why))
		return OpenCloud.EXIT_FAILED
	end
	local published = deps.request(OpenCloud.publishRequest(cfg, deps.readFile(OpenCloud.PLACE_FILE)))
	if not published.ok then
		say("Publication refusée (" .. tostring(published.statusCode) .. ") : " .. tostring(published.body))
		return OpenCloud.EXIT_FAILED
	end
	local version = deps.decode(published.body).versionNumber
	say("Version publiée : " .. tostring(version))
	local created = deps.request(OpenCloud.taskRequest(cfg, version, deps.encode))
	if not created.ok then
		say("Tâche refusée (" .. tostring(created.statusCode) .. ") : " .. tostring(created.body))
		return OpenCloud.EXIT_FAILED
	end
	local task = deps.decode(created.body)
	local path = task.path
	local state = task.state
	for _ = 1, OpenCloud.POLL_MAX do
		if state == "COMPLETE" or state == "FAILED" or state == "CANCELLED" then
			break
		end
		deps.wait(OpenCloud.POLL_EVERY)
		local polled = deps.request(OpenCloud.getRequest(cfg, path))
		if polled.ok then
			task = deps.decode(polled.body)
			state = task.state
		end
	end
	local logs = deps.request(OpenCloud.logsRequest(cfg, path))
	local bad = if logs.ok then OpenCloud.badLogLines(deps.decode(logs.body)) else {}
	local code, lines = OpenCloud.verdict(state, OpenCloud.parseSummary(task, deps.decode), bad)
	for _, line in lines do
		say(line)
	end
	return code
end

return OpenCloud
