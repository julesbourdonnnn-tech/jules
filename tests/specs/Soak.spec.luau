--!nocheck
-- Robot de longue durée (intégration, docs/04 §17.1 c, §17.2, §18.3) : serveur complet avec les vrais
-- services du paquet meta, 16 robots (joueurs complets, cavaliers, tricheurs bornés ; gigue et gels
-- réseau ; départs, retours et réapparitions), SOAK_HOURS heures de temps simulé (0,5 h par défaut,
-- 6 h dans scripts/soak.sh). Tous les invariants du §17.2 sont vérifiés À CHAQUE TICK par
-- tests/harness/Soak.luau (profils, uids, capacités, états minutés, plafonds, fuites du Rush, sieste de
-- Big Plop, clôture pendant l'attente du Grand Splorch ; instances, connexions, threads et handlers
-- stables), puis ici : temps du tick du serveur < 10 ms en moyenne sous Lune, fermeture (BindToClose)
-- à pleine charge, DiagnosticsService.counts() à zéro (invariant 9), zéro trace.
local Soak = require("../harness/Soak")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	describe("Soak › 16 robots, invariants à chaque tick", function()
		it(`{Soak.hours()} h de temps simulé : aucun invariant violé, tick < 10 ms, zéro trace`, function()
			local hours = Soak.hours()
			local report = Soak.run(Harness, { players = 16, hours = hours, seed = 42 })
			local w = report.world
			-- toute la durée a été jouée (aucun arrêt anticipé sur 50 problèmes)
			expect(report.ticks).toBe(math.floor(hours * 3600 / 0.1))
			expect(report.serverTicks >= report.ticks).toBe(true)
			expect(table.concat(report.problems, "\n")).toBe("")
			expect(report.msPerTick < 10).toBe(true)
			-- invariant 9 (docs/04 §17.2) : aucune erreur attrapée ni avertissement compté en ligne
			local D = w.h:require("ServerScriptService.Server.Services.DiagnosticsService")
			local counts = D.counts()
			expect({ errors = counts.errors, warnings = counts.warnings }).toEqual({
				errors = 0,
				warnings = 0,
			})
			expect(#D.caught()).toBe(0)
			local chaseGuard = w.h:require("ServerScriptService.Server.Chase.Guard")
			local metaGuard = w.h:require("ServerScriptService.Server.Meta.Guard")
			local stubs = {}
			for where, err in chaseGuard.stubbed do
				table.insert(stubs, where .. " : " .. err)
			end
			for where, err in metaGuard.stubbed do
				table.insert(stubs, where .. " : " .. err)
			end
			expect(table.concat(stubs, "\n")).toBe("")
			print(
				string.format(
					"  Soak : %.2f h, %d ticks, %.2f ms par tick du serveur, %d joueurs à la fin, instances %d → %d",
					hours,
					report.ticks,
					report.msPerTick,
					report.players,
					report.counts.start.instances,
					report.counts.finish.instances
				)
			)
		end)
	end)
end
