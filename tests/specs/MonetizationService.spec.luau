--!nocheck
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function boot()
		local h = Harness.new()
		local cfg = h:require("ReplicatedStorage.Shared.Config.Monetization")
		cfg.Products.TestCoins = { id = 1001, price = 99, nameKey = "x", descKey = "x", order = 1 }
		cfg.Passes.TestVIP = { id = 2001, price = 199, nameKey = "x", descKey = "x", order = 1 }
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		local M = h:require("ServerScriptService.Server.Services.MonetizationService")
		h:boot()
		M.registerProduct("TestCoins", function(player, data)
			DS.increment(player, "coins", 1000)
			return true
		end)
		return h, DS, M
	end

	describe("MonetizationService", function()
		it("crédite un produit une seule fois pour un même PurchaseId", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 30 })
			DS.waitFor(p, 2)
			local Enum = h.globals.Enum
			expect(h:purchaseProduct(p, 1001, "achat-1")).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(h:purchaseProduct(p, 1001, "achat-1")).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(DS.get(p).coins).toBe(1000)
			expect(h:purchaseProduct(p, 1001, "achat-2")).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(DS.get(p).coins).toBe(2000)
		end)

		it("ne crédite pas un joueur absent ou un produit inconnu", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 31 })
			DS.waitFor(p, 2)
			local Enum = h.globals.Enum
			expect(h:purchaseProduct(p, 9999, "x")).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
			h:removePlayer(p)
			expect(h:purchaseProduct(p, 1001, "y")).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
		end)

		it("pas de double crédit si la sauvegarde échoue puis Roblox réessaie", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 32 })
			DS.waitFor(p, 2)
			local Enum = h.globals.Enum
			h.dataStoreFailures = 10
			expect(h:purchaseProduct(p, 1001, "z")).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
			h.dataStoreFailures = 0
			expect(h:purchaseProduct(p, 1001, "z")).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(DS.get(p).coins).toBe(1000)
		end)

		it("accorde un gamepass possédé à l'arrivée et acheté en jeu", function()
			local h, DS, M = boot()
			h.ownedPasses[33] = { [2001] = true }
			local fired = 0
			M.PassGranted:Connect(function()
				fired += 1
			end)
			local p = h:addPlayer({ userId = 33 })
			DS.waitFor(p, 2)
			h:settle(3)
			expect(M.ownsPass(p, "TestVIP")).toBe(true)
			expect(fired).toBe(1)
			local q = h:addPlayer({ userId = 34 })
			DS.waitFor(q, 2)
			h:settle(3)
			expect(M.ownsPass(q, "TestVIP")).toBe(false)
			local granted = {}
			M.PassGranted:Connect(function(pl, key)
				table.insert(granted, key)
			end)
			h:grantPass(q, 2001)
			h:settle(2)
			expect(M.ownsPass(q, "TestVIP")).toBe(true)
			expect(granted[1]).toBe("TestVIP")
		end)
	end)
end
