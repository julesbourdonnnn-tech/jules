--!nocheck
-- EconomyPacing (paquet logic, docs/04 §16, §17.1 couche f ; GDD §4.24) : PORTE BLOQUANTE du rythme
-- de l'économie. 200 joueurs de référence sur 28 jours (tests/sim/EconomyModel, vraies formules et
-- vraies tables), graine fixe ; la spec échoue si une médiane sort de sa tolérance ou si une part
-- (≥ 90 %, ≥ 95 %) n'est pas tenue.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
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

	local PLAYERS, DAYS, SEED = 200, 28, 20261212

	describe("EconomyPacing (porte de simulation, GDD §4.24)", function()
		local model = EconomyModel.new(L)
		local result = Sim.run({
			players = PLAYERS,
			days = DAYS,
			seed = SEED,
			simulate = model.simulate,
			gates = EconomyModel.GATES,
			reported = EconomyModel.REPORTED,
		})
		print(Sim.report(result))

		it("chaque médiane est dans sa tolérance", function()
			expect(table.concat(Sim.failures(result), ", ")).toBe("")
		end)

		it(
			"les parts : Enclos payable à 5:00 (≥ 90 %), 3 objectifs au jour 1 (≥ 90 %), un Épique+ au jour 7 (≥ 95 %)",
			function()
				local failures = {}
				for _, share in EconomyModel.SHARES do
					local hits = 0
					for _, player in result.players do
						hits += player[share.key] or 0
					end
					local ratio = hits / #result.players
					print(
						string.format(
							"  %-34s %5.1f %%   (au moins %d %%)",
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
			end
		)

		it("déterministe : même graine, même joueur, mêmes jalons", function()
			local a = model.simulate(Sim.newRng(SEED * 1000003 + 1), 1, 2)
			local b = model.simulate(Sim.newRng(SEED * 1000003 + 1), 1, 2)
			expect(a.firstSplorch).toBe(b.firstSplorch)
			expect(a.rDay1).toBe(b.rDay1)
			expect(a.stamps30).toBe(b.stamps30)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
