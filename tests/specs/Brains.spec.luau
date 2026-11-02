--!nocheck
-- Robot de longue durée du paquet chase (tests/harness/Soak, Brains ; docs/04 §17.1 c) en version courte :
-- 16 robots (joueurs complets, cavaliers, tricheurs bornés), départs et retours, réapparitions, gels
-- réseau ; contrôles à chaque tick (invariants des profils, uids, états expirés, plafonds, fuites,
-- sieste, clôtures pendant l'attente, instances et connexions stables) ; budget du tick ; fermeture
-- à pleine charge ; zéro trace. Le robot complet (SOAK_HOURS, 0,5 h / 6 h) est Soak.spec (intégration).
local Soak = require("../harness/Soak")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	describe("Brains › robot de longue durée (version courte)", function()
		it(
			"16 robots, 4 min de jeu autour d'un Rush : aucun problème, tick < 10 ms en moyenne sous Lune",
			function()
				-- 4 min à partir de :03:20 : sirène, Rush de :05, Wild Wobblers, fuites, Golden de :10:30 non
				local report =
					Soak.run(Harness, { players = 16, hours = 4 / 60, t0 = 1800000000 + 200, seed = 7 })
				print(string.format("Soak court : %d ticks, %.2f ms/tick", report.ticks, report.msPerTick))
				expect(table.concat(report.problems, "\n")).toBe("")
				expect(report.ticks).toBe(2400)
				expect(report.msPerTick < 10).toBe(true)
			end
		)
	end)
end
