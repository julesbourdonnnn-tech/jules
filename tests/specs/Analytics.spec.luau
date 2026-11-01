--!nocheck
-- Server/Util/Analytics (repris de Comet Conga) : jamais bloquant, jamais d'erreur remontée ;
-- entonnoir envoyé une fois par étape et par session ; montants économiques arrondis, nuls,
-- négatifs ou NaN ignorés.
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function setup()
		local h = Harness.new()
		local A = h:require("ServerScriptService.Server.Util.Analytics")
		local p = h:addPlayer({ userId = 1, spawn = false })
		return h, A, p
	end

	local function calls(h, method)
		local out = {}
		for _, c in h.log.analytics do
			if c.method == method then
				table.insert(out, c.args)
			end
		end
		return out
	end

	describe("Analytics", function()
		it("entonnoir : chaque étape une seule fois par session", function()
			local h, A, p = setup()
			A.funnel(p, 1, "Joined")
			A.funnel(p, 1, "Joined")
			A.funnel(p, 2, "FirstPress")
			h:settle(2)
			local funnel = calls(h, "LogOnboardingFunnelStepEvent")
			expect(#funnel).toBe(2)
			expect(funnel[1][2]).toBe(1)
			expect(funnel[2][3]).toBe("FirstPress")
		end)

		it("économie : montants arrondis ; nuls, négatifs ou NaN ignorés", function()
			local h, A, p = setup()
			A.earn(p, "Coins", 10.7, 100.2, "Gameplay", "press")
			A.spend(p, "Coins", 5, 95, "Shop", "pen")
			A.earn(p, "Coins", 0, 95, "Gameplay")
			A.earn(p, "Coins", -3, 95, "Gameplay")
			A.earn(p, "Coins", 0 / 0, 95, "Gameplay")
			h:settle(2)
			local eco = calls(h, "LogEconomyEvent")
			expect(#eco).toBe(2)
			expect(eco[1][4]).toBe(10)
			expect(eco[1][5]).toBe(100)
			expect(eco[2][2]).toBe(h.globals.Enum.AnalyticsEconomyFlowType.Sink)
		end)

		it("service en panne : un avertissement, jamais d'erreur ni de blocage", function()
			local h, A, p = setup()
			MockInstance.classMethods.AnalyticsService = {
				LogCustomEvent = function()
					error("HTTP 500 (simulé)")
				end,
			}
			A.event(p, "RareHatch", 1)
			h:settle(2)
			expect(#h.errors).toBe(0)
			local warned = false
			for _, line in h:warnings() do
				if string.find(line, "[Analytics]", 1, true) then
					warned = true
				end
			end
			expect(warned).toBe(true)
		end)
	end)
end
