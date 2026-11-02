--!nocheck
-- ZeroLog (paquet meta, docs/04 §17.1 h) : un test enveloppé échoue sur toute erreur d'un handler lancé,
-- tout avertissement imprévu ou toute erreur attrapée comptée par Diagnostics ; expectWarning permet une
-- trace attendue et échoue si elle n'arrive pas ; wrap est idempotent ; forSpec garde les specs du socle.
local ZeroLog = require("../harness/ZeroLog")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local ROOT = "tests/fixtures/miniproject"

	-- T témoin : enregistre l'issue de chaque test sans toucher au bilan de la suite
	local function probe()
		local results = {}
		local base = {
			describe = function(_, fn)
				fn()
			end,
			it = function(name, fn)
				local ok, err = pcall(fn)
				table.insert(results, { name = name, ok = ok, err = tostring(err) })
			end,
			expect = T.expect,
			Harness = T.Harness,
		}
		return ZeroLog.wrap(base), results
	end

	describe("ZeroLog", function()
		it(
			"une erreur dans un handler lancé (task.spawn du code monté) fait échouer le test enveloppé",
			function()
				T.expectWarning("panne du handler") -- trace voulue, vue aussi par le test qui l'enveloppe
				local W, results = probe()
				W.it("handler en panne", function()
					local h = Harness.new({ root = ROOT })
					h.globals.task.spawn(function()
						error("panne du handler")
					end)
					h:settle(1)
				end)
				expect(#results).toBe(1)
				expect(results[1].ok).toBe(false)
				expect(results[1].err).toContain("panne du handler")
			end
		)

		it("un avertissement imprévu fait échouer ; un avertissement attendu passe", function()
			T.expectWarning("trace imprévue")
			T.expectWarning("trace prévue")
			local W, results = probe()
			W.it("warn imprévu", function()
				local h = Harness.new({ root = ROOT })
				h.globals.warn("trace imprévue")
			end)
			W.it("warn attendu", function()
				local h = Harness.new({ root = ROOT })
				W.expectWarning("trace prévue")
				h.globals.warn("une trace prévue ici")
			end)
			expect(results[1].ok).toBe(false)
			expect(results[1].err).toContain("trace imprévue")
			expect(results[2].ok).toBe(true)
		end)

		it("un avertissement attendu qui n'arrive jamais fait échouer le test", function()
			local W, results = probe()
			W.it("jamais vu", function()
				Harness.new({ root = ROOT })
				W.expectWarning("motif absent")
			end)
			expect(results[1].ok).toBe(false)
			expect(results[1].err).toContain("motif absent")
		end)

		it("un harnais créé avant le test n'est vérifié que sur ce qui arrive pendant le test", function()
			T.expectWarning("avant le test")
			T.expectWarning("pendant le test")
			local W, results = probe()
			local h = Harness.new({ root = ROOT })
			h.globals.warn("avant le test")
			W.it("propre", function()
				local _ = h
			end)
			W.it("trace pendant", function()
				h.globals.warn("pendant le test")
			end)
			expect(results[1].ok).toBe(true)
			expect(results[2].ok).toBe(false)
			expect(results[2].err).toContain("pendant le test")
			expect(results[2].err:find("avant le test", 1, true) == nil).toBe(true)
		end)

		it("une erreur attrapée comptée par le vrai DiagnosticsService fait échouer le test", function()
			T.expectWarning("tick:test")
			local W, results = probe()
			W.it("erreur attrapée", function()
				local h = Harness.new()
				local D = h:require("ServerScriptService.Server.Services.DiagnosticsService")
				D.reportCaught("tick:test", "nil index")
			end)
			W.it("attrapée mais déclarée", function()
				local h = Harness.new()
				local D = h:require("ServerScriptService.Server.Services.DiagnosticsService")
				W.expectWarning("tick:test")
				D.reportCaught("tick:test", "nil index")
			end)
			expect(results[1].ok).toBe(false)
			expect(results[1].err).toContain("[caught] tick:test")
			expect(results[2].ok).toBe(true)
		end)

		it("une erreur du test lui-même reste l'erreur rapportée ; un test propre passe", function()
			local W, results = probe()
			W.it("échec normal", function()
				error("attendu 1, obtenu 2")
			end)
			W.it("propre", function()
				local h = Harness.new({ root = ROOT })
				h:settle(1)
			end)
			expect(results[1].ok).toBe(false)
			expect(results[1].err).toContain("attendu 1, obtenu 2")
			expect(results[2].ok).toBe(true)
		end)

		it(
			"une panne injectée par le harnais est permise ; une vraie faute détectée par lui ne l'est pas",
			function()
				T.expectWarning("[DataStore simulé] valeur non sérialisable")
				local W, results = probe()
				W.it("panne injectée", function()
					local h = Harness.new({ root = ROOT })
					h.globals.warn(
						"[DataService] échec : 502: API Services rejected request (GetAsync) [panne simulée]"
					)
					h.globals.warn("HTTP 503 (UserService simulé)")
				end)
				W.it("vraie faute", function()
					local h = Harness.new({ root = ROOT })
					h.globals.warn("[DataStore simulé] valeur non sérialisable : {}")
				end)
				expect(results[1].ok).toBe(true)
				expect(results[2].ok).toBe(false)
			end
		)

		it("wrap est idempotent ; forSpec garde les specs du socle telles quelles", function()
			local W = ZeroLog.wrap(T)
			expect(ZeroLog.wrap(W)).toBe(W)
			local base = { it = T.it, describe = T.describe, expect = T.expect, Harness = T.Harness }
			expect(ZeroLog.forSpec("tests/specs/DataService.spec.luau", base)).toBe(base)
			expect(ZeroLog.forSpec("tests/specs/harness/Harness.spec.luau", base)).toBe(base)
			expect(ZeroLog.forSpec("tests/specs/QuestService.spec.luau", base) ~= base).toBe(true)
			expect(ZeroLog.forSpec("tests/specs/QuestService.spec.luau", base).__zeroLog).toBe(true)
			-- cette spec elle-même est enveloppée par tests/run.luau
			expect(T.__zeroLog).toBe(true)
			expect(type(T.expectWarning)).toBe("function")
		end)
	end)
end
