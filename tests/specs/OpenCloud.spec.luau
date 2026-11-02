--!nocheck
-- Outil Open Cloud et specs du vrai moteur (paquet meta, docs/04 §17.1 i) : le script se charge, sans
-- clé il rend 2 (« non lancé ») avec un message clair, il construit les bonnes requêtes (publication
-- d'une version, tâche d'exécution Luau, état, journaux), le verdict suit le bilan et les journaux, et
-- chaque spec de tests/engine se charge et passe aussi sous Lune avec un T minimal (Runner.makeT).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local OpenCloud = require("../../tools/opencloud/OpenCloud")
local Runner = require("../engine/Runner")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local ENV = { ROBLOX_API_KEY = "cle-de-test", UNIVERSE_ID = "123", PLACE_ID = "456" }

	local function json(t)
		return serde.encode("json", t)
	end

	local function unjson(s)
		return serde.decode("json", s)
	end

	-- Réseau simulé : chaque requête est notée ; réponses selon l'URL
	local function fakeDeps(opts)
		opts = opts or {}
		local log = { requests = {}, printed = {} }
		local polls = 0
		local deps = {
			print = function(line)
				table.insert(log.printed, line)
			end,
			build = function()
				return opts.buildOk ~= false, "rojo absent"
			end,
			readFile = function()
				return "PLACE-BINAIRE"
			end,
			encode = json,
			decode = unjson,
			wait = function() end,
			request = function(req)
				table.insert(log.requests, req)
				if string.find(req.url, "/versions?versionType=Saved", 1, true) then
					return { ok = true, statusCode = 200, body = json({ versionNumber = 7 }) }
				elseif
					string.find(req.url, "luau-execution-session-tasks", 1, true) and req.method == "POST"
				then
					return {
						ok = true,
						statusCode = 200,
						body = json({
							path = "universes/123/places/456/versions/7/luau-execution-session-tasks/abc",
							state = "PROCESSING",
						}),
					}
				elseif string.find(req.url, "/logs", 1, true) then
					return {
						ok = true,
						statusCode = 200,
						body = json(opts.logs or { luauExecutionSessionTaskLogs = {} }),
					}
				else
					polls += 1
					local done = polls >= 2
					local summary = opts.summary or { passed = 12, failed = 0, failures = {}, errors = {} }
					return {
						ok = true,
						statusCode = 200,
						body = json({
							path = "universes/123/places/456/versions/7/luau-execution-session-tasks/abc",
							state = if done then (opts.state or "COMPLETE") else "PROCESSING",
							output = if done then { results = { json(summary) } } else nil,
						}),
					}
				end
			end,
		}
		return deps, log
	end

	describe("OpenCloud › outil", function()
		it(
			"le script se charge (module pur), sans clé : code 2 et message clair, aucune requête",
			function()
				expect(fs.isFile("tools/opencloud/run-server-tests.luau")).toBe(true)
				expect(fs.readFile("tools/opencloud/run-server-tests.luau")).toContain(
					'require("./OpenCloud")'
				)
				expect(fs.isFile("tools/opencloud/README.md")).toBe(true)
				local deps, log = fakeDeps()
				expect(OpenCloud.main({}, deps)).toBe(2)
				expect(#log.requests).toBe(0)
				expect(log.printed[1]).toContain("ROBLOX_API_KEY")
				expect(OpenCloud.main({ ROBLOX_API_KEY = "k", UNIVERSE_ID = "abc", PLACE_ID = "1" }, deps)).toBe(
					2
				)
			end
		)

		it(
			"requêtes : publication d'une version (x-api-key, octets), tâche Luau (script, 300 s), état, journaux",
			function()
				local cfg = OpenCloud.config(ENV)
				local pub = OpenCloud.publishRequest(cfg, "BYTES")
				expect(pub.method).toBe("POST")
				expect(pub.url).toBe(
					"https://apis.roblox.com/universes/v1/123/places/456/versions?versionType=Saved"
				)
				expect(pub.headers["x-api-key"]).toBe("cle-de-test")
				expect(pub.headers["Content-Type"]).toBe("application/octet-stream")
				expect(pub.body).toBe("BYTES")
				local task = OpenCloud.taskRequest(cfg, 7, json)
				expect(task.url).toBe(
					"https://apis.roblox.com/cloud/v2/universes/123/places/456/versions/7/luau-execution-session-tasks"
				)
				local body = unjson(task.body)
				expect(body.timeout).toBe("300s")
				expect(body.script).toContain("EngineTests")
				expect(body.script).toContain("runJson")
				local get = OpenCloud.getRequest(
					cfg,
					"universes/123/places/456/versions/7/luau-execution-session-tasks/abc"
				)
				expect(get.method).toBe("GET")
				expect(get.url).toBe(
					"https://apis.roblox.com/cloud/v2/universes/123/places/456/versions/7/luau-execution-session-tasks/abc"
				)
				expect(OpenCloud.logsRequest(cfg, "x/y").url).toContain("/x/y/logs")
			end
		)

		it(
			"déroulé complet : vert → 0 ; un test échoué → 1 ; une ligne Error ou Warning → 1 ; FAILED → 1",
			function()
				local deps, log = fakeDeps()
				expect(OpenCloud.main(ENV, deps)).toBe(0)
				expect(#log.requests).toBe(5) -- publication, tâche, 2 lectures d'état, journaux
				local bad = fakeDeps({
					summary = { passed = 3, failed = 1, failures = { "x › y : boom" }, errors = {} },
				})
				expect(OpenCloud.main(ENV, bad)).toBe(1)
				local noisy = fakeDeps({
					logs = {
						luauExecutionSessionTaskLogs = {
							{
								structuredMessages = {
									{ message = "Infinite yield possible", messageType = "WARNING" },
								},
							},
						},
					},
				})
				expect(OpenCloud.main(ENV, noisy)).toBe(1)
				expect(OpenCloud.main(ENV, fakeDeps({ state = "FAILED" }))).toBe(1)
				expect(OpenCloud.main(ENV, fakeDeps({ buildOk = false }))).toBe(1)
			end
		)
	end)

	describe("OpenCloud › specs du vrai moteur sous Lune", function()
		it(
			"chaque spec de tests/engine se charge et passe avec un T minimal (serveur du harnais démarré)",
			function()
				local h = Harness.new()
				h:boot()
				h:settle(3)
				local results = { passed = 0, failed = 0, failures = {}, errors = {} }
				local ET = Runner.makeT(results, function(path)
					return h:require(path)
				end, function(name)
					return h.game:GetService(name)
				end, function()
					local out = {}
					for _, e in h.errors do
						table.insert(out, e)
					end
					for _, w in h:warnings() do
						table.insert(out, w)
					end
					return out
				end)
				local count = 0
				for _, entry in fs.readDir("tests/engine") do
					if string.match(entry, "%.spec%.luau$") then
						count += 1
						local spec = require("../engine/" .. string.gsub(entry, "%.luau$", ""))
						spec(ET)
					end
				end
				expect(count >= 3).toBe(true)
				expect(table.concat(results.failures, "\n")).toBe("")
				expect(results.passed >= 10).toBe(true)
			end
		)
	end)
end
