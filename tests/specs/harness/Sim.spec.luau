--!nocheck
-- Auto-test du socle de simulation (tests/sim/Sim) avec un modèle jouet neutre : déterminisme par
-- graine, quantiles, « jamais atteint », portes et rapport.
local Sim = require("../../sim/Sim")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	-- Modèle jouet : revenu de 10 pièces/s + aléa ; un objectif à 3 000 pièces ; certains joueurs
	-- (1 sur 10) ne jouent jamais assez pour l'atteindre
	local function toy(rng, index, days)
		local perSecond = 10 * rng.range(0.8, 1.2)
		local seconds = 1800 * days
		local goal = if index % 10 == 0 then math.huge else 3000 / perSecond / 60
		return { goalMinutes = goal, finalCoins = perSecond * seconds }
	end

	describe("Sim (socle de simulation)", function()
		it("déterministe : même graine, mêmes résultats ; autre graine, autres résultats", function()
			local a = Sim.run({
				players = 50,
				days = 3,
				seed = 7,
				simulate = toy,
				reported = { { key = "finalCoins", label = "x" } },
			})
			local b = Sim.run({
				players = 50,
				days = 3,
				seed = 7,
				simulate = toy,
				reported = { { key = "finalCoins", label = "x" } },
			})
			local c = Sim.run({
				players = 50,
				days = 3,
				seed = 8,
				simulate = toy,
				reported = { { key = "finalCoins", label = "x" } },
			})
			expect(a.medians.finalCoins).toBe(b.medians.finalCoins)
			expect(a.medians.finalCoins ~= c.medians.finalCoins).toBe(true)
		end)

		it("générateur : bornes de range, int et chance", function()
			local rng = Sim.newRng(42)
			local seen = {}
			for _ = 1, 2000 do
				local x = rng()
				expect(x >= 0 and x < 1).toBe(true)
				local r = rng.range(5, 6)
				expect(r >= 5 and r < 6).toBe(true)
				local k = rng.int(1, 3)
				seen[k] = true
				expect(k >= 1 and k <= 3 and k % 1 == 0).toBe(true)
			end
			expect(seen[1] and seen[2] and seen[3]).toBe(true)
			local hits = 0
			for _ = 1, 10000 do
				if rng.chance(0.25) then
					hits += 1
				end
			end
			expect(hits > 2200 and hits < 2800).toBe(true)
		end)

		it(
			"quantiles et « jamais » : médiane infinie seulement si plus de la moitié ne l'atteint pas",
			function()
				expect(Sim.median({ 3, 1, 2 })).toBe(2)
				expect(Sim.median({ 1, 2, 3, 4 })).toBe(2.5)
				expect(Sim.median({})).toBe(math.huge)
				expect(Sim.median({ 1, 2, math.huge })).toBe(2)
				expect(Sim.median({ 1, math.huge, math.huge })).toBe(math.huge)
				expect(Sim.quantile({ 0, 10 }, 0.1)).toBeNear(1, 1e-9)
			end
		)

		it("portes : OK dans la tolérance, HORS sinon ; rapport lisible", function()
			local result = Sim.run({
				players = 100,
				days = 1,
				simulate = toy,
				gates = {
					{ key = "goalMinutes", label = "Objectif (min)", min = 4, max = 6 },
					{ key = "goalMinutes", label = "Objectif trop strict (min)", max = 1 },
				},
				reported = { { key = "finalCoins", label = "Pièces au jour final" } },
			})
			expect(result.medians.goalMinutes).toBeNear(5, 0.5)
			expect(Sim.failures(result)).toEqual({ "Objectif trop strict (min)" })
			local text = Sim.report(result)
			expect(string.find(text, "OK", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "HORS", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "Pièces au jour final", 1, true) ~= nil).toBe(true)
			-- p90 : 1 joueur sur 10 n'atteint jamais l'objectif
			expect(result.p90.goalMinutes >= result.medians.goalMinutes).toBe(true)
		end)
	end)
end
