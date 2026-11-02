--!nocheck
-- Couche i : démarrage de Main.server (zéro erreur ni avertissement), monde construit, aller-retour
-- DataStore sur un magasin de test dédié (EngineTest_v1), Diagnostics.
return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	describe("Moteur › serveur", function()
		it("démarrage : aucune erreur ni aucun avertissement dans le journal du moteur", function()
			local lines = T.logErrors()
			expect(#lines).toBe(0)
			local Diagnostics = T.require("ServerScriptService.Server.Services.DiagnosticsService")
			expect(Diagnostics.counts().errors).toBe(0)
		end)

		it("monde construit : chaque pièce ancrée et sans contact (CanTouch faux)", function()
			local world = T.service("Workspace"):FindFirstChild("Wobbleton")
			expect(world ~= nil).toBe(true)
			local bad = 0
			local parts = 0
			for _, d in world:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					if not d.Anchored or d.CanTouch then
						bad += 1
					end
				end
			end
			expect(parts).toBeGreaterThan(0)
			expect(bad).toBe(0)
		end)

		it("DataStore : aller-retour d'une table sur EngineTest_v1", function()
			local store = T.service("DataStoreService"):GetDataStore("EngineTest_v1")
			local key = "roundtrip_" .. tostring(math.floor(os.clock() * 1000) % 100000)
			local value = { n = 42, list = { 1, 2, 3 }, s = "Plop" }
			local okSet, errSet = pcall(function()
				store:SetAsync(key, value)
			end)
			expect(okSet).toBe(true)
			local _ = errSet
			local ok, got = pcall(function()
				return store:GetAsync(key)
			end)
			expect(ok).toBe(true)
			expect(got.n).toBe(42)
			expect(#got.list).toBe(3)
			expect(got.s).toBe("Plop")
		end)

		it("LeaderboardService : valeur codée exacte dans le vrai moteur", function()
			local L = T.require("ServerScriptService.Server.Services.LeaderboardService")
			local score, s, hidden = L.decode(L.encode(500000, 604799, true))
			expect(score).toBe(500000)
			expect(s).toBe(604799)
			expect(hidden).toBe(true)
		end)
	end)
end
