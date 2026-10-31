--!nocheck
-- QA ronde 2, paquet « divers » (socle serveur) :
--   * MonetizationService : un reçu rejoué (PurchaseId déjà en mémoire) n'est acquitté
--     (PurchaseGranted) qu'après une sauvegarde réussie (GDD §8.1.4). Pendant une panne DataStore,
--     chaque nouvel essai de Roblox reçoit NotProcessedYet, sans double crédit ; la panne finie,
--     le reçu est acquitté avec un enregistrement réellement persisté.
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local STORE = "PlayerData_v1"
	local PRODUCT_ID = 1301
	local AMOUNT = 400

	local function boot()
		local h = Harness.new()
		local cfg = h:require("ReplicatedStorage.Shared.Config.Monetization")
		cfg.Products.TestJar = { id = PRODUCT_ID, price = 99, nameKey = "x", descKey = "x", order = 1 }
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local M = h:require("ServerScriptService.Server.Services.MonetizationService")
		h:boot()
		local ctx = { h = h, DS = DS, M = M, Enum = h.globals.Enum, handlerCalls = 0, grantedSignals = 0 }
		M.registerProduct("TestJar", function(player, _data)
			ctx.handlerCalls += 1
			DS.increment(player, "stardust", AMOUNT)
			return true
		end)
		M.ProductGranted:Connect(function()
			ctx.grantedSignals += 1
		end)
		return ctx
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		local data = ctx.DS.waitFor(p, 3)
		ctx.h:settle(3)
		return p, data
	end

	-- lecture directe de l'enregistrement (à appeler quand le DataStore ne simule plus de panne)
	local function stored(ctx, userId)
		return ctx.h.game.DataStoreService:GetDataStore(STORE):GetAsync("player_" .. userId)
	end

	local function storedReceipts(record)
		if record and record.data and type(record.data.receipts) == "table" then
			return record.data.receipts
		end
		return {}
	end

	describe("Fix divers r2 › MonetizationService : reçu rejoué pendant une panne DataStore", function()
		it(
			"panne : chaque nouvel essai renvoie NotProcessedYet ; panne finie : acquitté et persisté",
			function()
				local ctx = boot()
				local h, DS, Enum = ctx.h, ctx.DS, ctx.Enum
				local p = join(ctx, 70)
				local before = DS.get(p).stardust
				h.dataStoreFailures = 1000
				expect(h:purchaseProduct(p, PRODUCT_ID, "jar-70")).toBe(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				-- crédit appliqué en mémoire une seule fois, reçu mémorisé contre le double crédit
				expect(DS.get(p).stardust).toBe(before + AMOUNT)
				expect(table.find(DS.get(p).receipts, "jar-70") ~= nil).toBe(true)
				-- Roblox réessaie pendant la panne : rien n'est sauvegardé, donc jamais d'acquittement
				expect(h:purchaseProduct(p, PRODUCT_ID, "jar-70")).toBe(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				expect(h:purchaseProduct(p, PRODUCT_ID, "jar-70")).toBe(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				expect(DS.get(p).stardust).toBe(before + AMOUNT)
				expect(ctx.handlerCalls).toBe(1)
				expect(ctx.grantedSignals).toBe(1)
				-- fin de panne : l'enregistrement ne contient pas encore le reçu
				h.dataStoreFailures = 0
				expect(table.find(storedReceipts(stored(ctx, 70)), "jar-70")).toBe(nil)
				-- nouvel essai : sauvegardé PUIS acquitté, sans second crédit
				expect(h:purchaseProduct(p, PRODUCT_ID, "jar-70")).toBe(
					Enum.ProductPurchaseDecision.PurchaseGranted
				)
				local record = stored(ctx, 70)
				expect(table.find(storedReceipts(record), "jar-70") ~= nil).toBe(true)
				expect(record.data.stardust).toBe(before + AMOUNT)
				expect(DS.get(p).stardust).toBe(before + AMOUNT)
				expect(ctx.handlerCalls).toBe(1)
				expect(ctx.grantedSignals).toBe(1)
			end
		)

		it(
			"reçu déjà persisté : un rejeu reste acquitté (PurchaseGranted), sans double crédit",
			function()
				local ctx = boot()
				local h, DS, Enum = ctx.h, ctx.DS, ctx.Enum
				local p = join(ctx, 71)
				local before = DS.get(p).stardust
				expect(h:purchaseProduct(p, PRODUCT_ID, "jar-71")).toBe(
					Enum.ProductPurchaseDecision.PurchaseGranted
				)
				expect(h:purchaseProduct(p, PRODUCT_ID, "jar-71")).toBe(
					Enum.ProductPurchaseDecision.PurchaseGranted
				)
				expect(DS.get(p).stardust).toBe(before + AMOUNT)
				expect(ctx.handlerCalls).toBe(1)
				expect(table.find(storedReceipts(stored(ctx, 71)), "jar-71") ~= nil).toBe(true)
			end
		)

		it("départ pendant la panne : jamais acquitté ; session suivante crédite et acquitte", function()
			local ctx = boot()
			local h, DS, Enum = ctx.h, ctx.DS, ctx.Enum
			local p = join(ctx, 72)
			local before = DS.get(p).stardust
			h.dataStoreFailures = 1000
			expect(h:purchaseProduct(p, PRODUCT_ID, "jar-72")).toBe(
				Enum.ProductPurchaseDecision.NotProcessedYet
			)
			-- la sauvegarde de départ échoue aussi (tous ses essais) : le crédit en mémoire est perdu
			h:removePlayer(p)
			task.wait(0.3)
			expect(DS.get(p)).toBe(nil)
			expect(h:purchaseProduct(p, PRODUCT_ID, "jar-72")).toBe(
				Enum.ProductPurchaseDecision.NotProcessedYet
			)
			h.dataStoreFailures = 0
			expect(table.find(storedReceipts(stored(ctx, 72)), "jar-72")).toBe(nil)
			-- retour du joueur : Roblox redélivre le reçu, crédité puis acquitté (l'achat n'est pas perdu)
			local q = join(ctx, 72)
			expect(DS.get(q).stardust).toBe(before)
			expect(h:purchaseProduct(q, PRODUCT_ID, "jar-72")).toBe(
				Enum.ProductPurchaseDecision.PurchaseGranted
			)
			expect(DS.get(q).stardust).toBe(before + AMOUNT)
			local record = stored(ctx, 72)
			expect(table.find(storedReceipts(record), "jar-72") ~= nil).toBe(true)
			expect(record.data.stardust).toBe(before + AMOUNT)
		end)

		it(
			"reçu non acquitté mais sauvé au départ : la session suivante acquitte sans recréditer",
			function()
				local ctx = boot()
				local h, DS, Enum = ctx.h, ctx.DS, ctx.Enum
				local p = join(ctx, 73)
				local before = DS.get(p).stardust
				h.dataStoreFailures = 1000
				expect(h:purchaseProduct(p, PRODUCT_ID, "jar-73")).toBe(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				-- fin de panne juste avant le départ : la sauvegarde de départ emporte crédit et reçu
				h.dataStoreFailures = 0
				h:removePlayer(p)
				task.wait(0.3)
				local record = stored(ctx, 73)
				expect(table.find(storedReceipts(record), "jar-73") ~= nil).toBe(true)
				expect(record.data.stardust).toBe(before + AMOUNT)
				-- Roblox redélivre le reçu à la session suivante : acquitté, jamais recrédité
				local q = join(ctx, 73)
				expect(DS.get(q).stardust).toBe(before + AMOUNT)
				expect(h:purchaseProduct(q, PRODUCT_ID, "jar-73")).toBe(
					Enum.ProductPurchaseDecision.PurchaseGranted
				)
				expect(DS.get(q).stardust).toBe(before + AMOUNT)
				expect(ctx.handlerCalls).toBe(1)
			end
		)

		it("rejeu pendant la sauvegarde de départ (joueur encore présent) : NotProcessedYet", function()
			local ctx = boot()
			local h, DS, Enum = ctx.h, ctx.DS, ctx.Enum
			local p = join(ctx, 74)
			h.dataStoreFailures = 1000
			expect(h:purchaseProduct(p, PRODUCT_ID, "jar-74")).toBe(
				Enum.ProductPurchaseDecision.NotProcessedYet
			)
			-- PlayerRemoving déclenché, Player encore dans Players : profil en cours de libération
			h.game.Players.PlayerRemoving:Fire(p)
			task.wait()
			expect(h:purchaseProduct(p, PRODUCT_ID, "jar-74")).toBe(
				Enum.ProductPurchaseDecision.NotProcessedYet
			)
			expect(ctx.handlerCalls).toBe(1)
			p.Parent = nil
			h.dataStoreFailures = 0
			h:settle(3)
			expect(DS.get(p)).toBe(nil)
		end)
	end)

	describe("Fix divers r2 › MonetizationService : arrêt du serveur (BindToClose)", function()
		it("sauvegarde de fermeture en échec : rejeu jamais acquitté, rien de persisté", function()
			local ctx = boot()
			local h, DS, Enum = ctx.h, ctx.DS, ctx.Enum
			local p = join(ctx, 75)
			local before = DS.get(p).stardust
			h.dataStoreFailures = 1000
			expect(h:purchaseProduct(p, PRODUCT_ID, "jar-75")).toBe(
				Enum.ProductPurchaseDecision.NotProcessedYet
			)
			-- la panne dure jusqu'à la fermeture : la sauvegarde de fermeture échoue aussi
			h:close()
			-- Roblox réessaie pendant l'arrêt : le profil est « libéré » mais rien n'a été écrit
			expect(h:purchaseProduct(p, PRODUCT_ID, "jar-75")).toBe(
				Enum.ProductPurchaseDecision.NotProcessedYet
			)
			h.dataStoreFailures = 0
			expect(h:purchaseProduct(p, PRODUCT_ID, "jar-75")).toBe(
				Enum.ProductPurchaseDecision.NotProcessedYet
			)
			expect(table.find(storedReceipts(stored(ctx, 75)), "jar-75")).toBe(nil)
			expect(DS.get(p).stardust).toBe(before + AMOUNT)
			expect(ctx.handlerCalls).toBe(1)
		end)

		it(
			"nouveau reçu après le début de l'arrêt : ni crédité ni acquitté (crédité à la session suivante)",
			function()
				local ctx = boot()
				local h, DS, Enum = ctx.h, ctx.DS, ctx.Enum
				local p = join(ctx, 76)
				local before = DS.get(p).stardust
				h:close() -- sauvegarde de fermeture réussie, instantané pris avant l'achat
				expect(h:purchaseProduct(p, PRODUCT_ID, "jar-76")).toBe(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				expect(ctx.handlerCalls).toBe(0)
				expect(DS.get(p).stardust).toBe(before)
				local record = stored(ctx, 76)
				expect(record.lock).toBeNil()
				expect(table.find(storedReceipts(record), "jar-76")).toBe(nil)
			end
		)

		it("reçu acquitté avant l'arrêt : la fermeture le garde persisté", function()
			local ctx = boot()
			local h, DS, Enum = ctx.h, ctx.DS, ctx.Enum
			local p = join(ctx, 77)
			local before = DS.get(p).stardust
			expect(h:purchaseProduct(p, PRODUCT_ID, "jar-77")).toBe(
				Enum.ProductPurchaseDecision.PurchaseGranted
			)
			h:close()
			local record = stored(ctx, 77)
			expect(table.find(storedReceipts(record), "jar-77") ~= nil).toBe(true)
			expect(record.data.stardust).toBe(before + AMOUNT)
		end)
	end)
end
