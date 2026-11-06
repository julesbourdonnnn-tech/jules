--!nocheck
-- Robot de longue durée (intégration, docs/04 §17.1 c, §17.2, §18.3) : serveur complet avec les vrais
-- services du paquet meta, 16 robots (joueurs complets, cavaliers, tricheurs bornés ; gigue et gels
-- réseau ; départs, retours et réapparitions), SOAK_HOURS heures de temps simulé (0,5 h par défaut,
-- 6 h dans scripts/soak.sh). Tous les invariants du §17.2 sont vérifiés À CHAQUE TICK par
-- tests/harness/Soak.luau (profils, uids, capacités, états minutés, plafonds, fuites du Rush, sieste de
-- Big Plop, clôture pendant l'attente du Grand Splorch ; instances, connexions, threads et handlers
-- stables), puis ici : temps du tick du serveur < 10 ms en moyenne sous Lune, fermeture (BindToClose)
-- à pleine charge, DiagnosticsService.counts() à zéro (invariant 9), zéro trace. v2.0 (lot A3) : les
-- mêmes robots avec 6 Plopettes chacun (interrupteur Helpers ouvert, serveur v2).
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

	-- v2.0 (lot A3) : les mêmes 16 robots avec 6 Plopettes chacun (Record R 12 + Plume), serveur v2
	-- (SchemaV2 ouvert dans le harnais avant le premier require du schéma, recette de DataChaos),
	-- interrupteur Helpers ouvert ; la moitié de la durée du Soak (0,25 h par défaut)
	describe("Soak › 16 robots × 6 Plopettes (lot A3)", function()
		it(
			`{Soak.hours() / 2} h : invariants, sauts ≤ 3 s, aucune fuite d'état, zéro trace, coût du tick`,
			function()
				local L = "ReplicatedStorage.Shared."
				local HarnessV2 = setmetatable({
					new = function(options)
						local hh = Harness.new(options)
						hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
						return hh
					end,
				}, { __index = Harness })
				local hours = Soak.hours() / 2
				local helperStep = { spent = 0, n = 0 }
				local MaxTravel = nil
				local report = Soak.run(HarnessV2, {
					players = 16,
					hours = hours,
					seed = 7,
					flags = { "Helpers" },
					edit = function(d, _i)
						d.bestR = 12
						d.atelier[8] = 1 -- Plume (Config/Upgrades.WorkshopIndex.plume)
					end,
					check = function(w, now)
						local out = {}
						local Helper = w.h:require("ServerScriptService.Server.Services.HelperService")
						if MaxTravel == nil then
							MaxTravel = w.Balance.Helpers.MaxTravel
							-- coût du step des Plopettes (os.clock réel), mesuré dans le tick
							local step = Helper.step
							Helper.step = function(t, acting)
								local t0 = os.clock()
								step(t, acting)
								helperStep.spent += os.clock() - t0
								helperStep.n += 1
							end
						end
						local present = 0
						for _, p in w.players do
							if p.Parent ~= nil then
								present += 1
								for _, h in Helper.helpers(p) do
									if h.moving then
										if h.tPress - now > MaxTravel + 1e-6 then
											table.insert(out, "saut de plus de 3 s : " .. p.UserId)
										end
										if now - h.tPress > 0.11 + 1e-6 then
											table.insert(out, "saut non résolu à tPress : " .. p.UserId)
										end
									end
								end
							end
						end
						if Helper.counters().Owners > present then
							table.insert(out, "état d'un propriétaire parti gardé")
						end
						return out
					end,
				})
				local w = report.world
				expect(report.ticks).toBe(math.floor(hours * 3600 / 0.1))
				expect(table.concat(report.problems, "\n")).toBe("")
				expect(report.msPerTick < 10).toBe(true)
				local D = w.h:require("ServerScriptService.Server.Services.DiagnosticsService")
				local counts = D.counts()
				expect({ errors = counts.errors, warnings = counts.warnings }).toEqual({
					errors = 0,
					warnings = 0,
				})
				expect(#D.caught()).toBe(0)
				local Helper = w.h:require("ServerScriptService.Server.Services.HelperService")
				local c = Helper.counters()
				expect(c.Pressed > 100).toBe(true)
				expect(c.Owners <= report.players).toBe(true) -- aucun état d'un joueur parti
				local ms = helperStep.spent / math.max(1, helperStep.n) * 1000
				expect(ms < 0.5).toBe(true)
				print(
					string.format(
						"  Soak Plopettes : %.2f h, %.2f ms par tick du serveur, %.3f ms par step des Plopettes, %d pressions d'aide, %d abandons, instances %d → %d",
						hours,
						report.msPerTick,
						ms,
						c.Pressed,
						c.Abandoned,
						report.counts.start.instances,
						report.counts.finish.instances
					)
				)
			end
		)
	end)
end
