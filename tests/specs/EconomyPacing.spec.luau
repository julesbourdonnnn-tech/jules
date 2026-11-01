--!nocheck
-- EconomyPacing (paquet logic, docs/04 §16 v1.2, §17.1 couche f ; GDD §4.24) : PORTE BLOQUANTE du rythme
-- de l'économie. Joueurs de référence sur 28 jours (tests/sim/EconomyModel : vraies formules, vraies
-- tables, boosts calculés d'après les règles, moteur par événements), graine fixe, aux 3 tailles de
-- serveur (4, 8, 16 joueurs) : 50 joueurs par taille dans check.sh, 200 en lancement manuel
-- (ECON_PLAYERS=200 lune run tests/run -- EconomyPacing). La spec échoue si une médiane (rythme ou
-- santé) sort de sa tolérance à une taille, si une part n'est pas tenue, ou si le gros acheteur a plus
-- de 2 R d'avance au jour 28.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local process = require("@lune/process")
	local Sim = require("../sim/Sim")
	local EconomyModel = require("../sim/EconomyModel")

	local h = Harness.new()
	local function logic(name)
		return h:require("ReplicatedStorage.Shared.Logic." .. name)
	end
	local function config(name)
		return h:require("ReplicatedStorage.Shared.Config." .. name)
	end
	local L = {
		Formulas = logic("Formulas"),
		Odds = logic("Odds"),
		FusionRules = logic("FusionRules"),
		QuestRules = logic("QuestRules"),
		RushRules = logic("RushRules"),
		EventClock = logic("EventClock"),
		Hash = logic("Hash"),
		Balance = config("Balance"),
		Species = config("Species"),
		Rarities = config("Rarities"),
		Mutations = config("Mutations"),
		Quests = config("Quests"),
		Events = config("Events"),
	}

	local PLAYERS = math.max(1, math.floor(tonumber(process.env.ECON_PLAYERS) or 50))
	local SPENDERS = math.min(PLAYERS, 20)
	local DAYS, SEED = 28, 20261212

	describe("EconomyPacing (porte de simulation, GDD §4.24, docs/04 §16 v1.2)", function()
		local model = EconomyModel.new(L)
		local results = {}
		for _, size in EconomyModel.SIZES do
			local result = Sim.run({
				players = PLAYERS,
				days = DAYS,
				seed = SEED,
				simulate = model.simulateFor({ players = size }),
				gates = EconomyModel.GATES,
				reported = EconomyModel.REPORTED,
			})
			results[size] = result
			print(
				string.format(
					"\n  — Serveur de %d joueurs (%d joueurs de référence, %d jours) —",
					size,
					PLAYERS,
					DAYS
				)
			)
			print(Sim.report(result))
		end

		for _, size in EconomyModel.SIZES do
			it(`serveur de {size} : chaque médiane (rythme et santé) est dans sa tolérance`, function()
				expect(table.concat(Sim.failures(results[size]), ", ")).toBe("")
			end)

			it(`serveur de {size} : les parts de joueurs sont tenues`, function()
				local failures = {}
				for _, share in EconomyModel.SHARES do
					local hits = 0
					for _, player in results[size].players do
						hits += player[share.key] or 0
					end
					local ratio = hits / #results[size].players
					print(
						string.format(
							"  [%2d] %-36s %5.1f %%   (au moins %d %%)",
							size,
							share.label,
							ratio * 100,
							share.min * 100
						)
					)
					if ratio < share.min then
						table.insert(failures, share.label)
					end
				end
				expect(table.concat(failures, ", ")).toBe("")
			end)
		end

		it(
			"gros acheteur (×2 Pièces, Grand Ranch, Squish Party la moitié du temps) : ≤ 2 R d'avance au jour 28",
			function()
				local spender = Sim.run({
					players = SPENDERS,
					days = DAYS,
					seed = SEED,
					simulate = model.simulateFor({ players = 16, spender = true }),
					gates = {},
					reported = {
						{ key = "rDay28", label = "R en fin de jour 28" },
						{ key = "firstSplorch", label = "x" },
					},
				})
				local reference = {}
				for i = 1, SPENDERS do
					table.insert(reference, results[16].players[i].rDay28)
				end
				local lead = spender.medians.rDay28 - Sim.median(reference)
				print(
					string.format(
						"  Gros acheteur : R jour 28 médiane %.1f (référence %.1f, avance %.1f R) ; premier Grand Splorch %.1f min",
						spender.medians.rDay28,
						Sim.median(reference),
						lead,
						spender.medians.firstSplorch
					)
				)
				expect(lead <= EconomyModel.SPENDER_MAX_LEAD).toBe(true)
				expect(lead >= 0).toBe(true) -- « plus tôt, pas plus haut », mais jamais moins
			end
		)

		it("déterministe : même graine, même joueur, mêmes jalons", function()
			local simulate = model.simulateFor({ players = 8 })
			local a = simulate(Sim.newRng(SEED * 1000003 + 1), 1, 3)
			local b = simulate(Sim.newRng(SEED * 1000003 + 1), 1, 3)
			expect(a.firstSplorch).toBe(b.firstSplorch)
			expect(a.rDay1).toBe(b.rDay1)
			expect(a.stamps30).toBe(b.stamps30)
			expect(a.boostShare).toBe(b.boostShare)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
