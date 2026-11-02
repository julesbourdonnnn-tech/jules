--!nocheck
-- Couche i : modules purs de Shared/Logic dans le vrai moteur (cas exacts du GDD, propriétés en petit N).
return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	describe("Moteur › Shared/Logic", function()
		it("Formulas : objectif du premier Grand Splorch (15 000), revenu jamais NaN", function()
			local Formulas = T.require("ReplicatedStorage.Shared.Logic.Formulas")
			expect(Formulas.splorchTarget(0)).toBe(15000)
			for r = 0, 40 do
				local target = Formulas.splorchTarget(r)
				expect(target == target).toBe(true)
				expect(target).toBeGreaterThan(0)
			end
		end)

		it("Hash : déterministe et borné", function()
			local Hash = T.require("ReplicatedStorage.Shared.Logic.Hash")
			expect(Hash.u32(1, 2, 3)).toBe(Hash.u32(1, 2, 3))
			for i = 1, 200 do
				local v = Hash.int(1, 6, i, 7)
				expect(v >= 1 and v <= 6).toBe(true)
			end
		end)

		it("StateTimeouts : chaque état a un délai positif", function()
			local StateTimeouts = T.require("ReplicatedStorage.Shared.Logic.StateTimeouts")
			for _, name in StateTimeouts.names() do
				expect(StateTimeouts.seconds(name)).toBeGreaterThan(0)
			end
		end)

		it("QuestRules et DiagRules : Squishydex vide, noms effacés", function()
			local QuestRules = T.require("ReplicatedStorage.Shared.Logic.QuestRules")
			expect(QuestRules.stampCount({ mut = {}, stars = {} })).toBe(0)
			local DiagRules = T.require("ReplicatedStorage.Shared.Logic.DiagRules")
			local text = DiagRules.normalize("Mira a 42 pièces", { "Mira" })
			expect(string.find(text, "Mira", 1, true)).toBeNil()
			expect(text).toContain("#")
		end)
	end)
end
