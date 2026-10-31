--!nocheck
-- ProductService : effets de chaque produit (montants Glow à l'attribution, Stardust, Glow Party
-- jamais refusée, Starter Kit même en double), reçus rejoués, passes (VIP, Double Glow, Extra
-- Perches, Stash Plus, Conga Styles), « Merci ! » seulement pour un achat en jeu, cycle de vie.

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000

	local PRODUCT_IDS = {
		GlowPouch = 501,
		GlowSack = 502,
		GlowCrate = 503,
		GlowParty = 504,
		StardustJar = 505,
		StarterKit = 506,
	}
	local PASS_IDS = {
		VIPStar = 601,
		DoubleGlow = 602,
		NightShift = 603,
		ExtraPerches = 604,
		StashPlus = 605,
		CongaStyles = 606,
	}

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local M = h:require("ReplicatedStorage.Shared.Config.Monetization")
		for key, id in PRODUCT_IDS do
			M.Products[key].id = id
		end
		for key, id in PASS_IDS do
			M.Passes[key].id = id
		end
		-- EventService (paquet events) isolé : file de Glow Party simulée
		local Ev = h:require("ServerScriptService.Server.Services.EventService")
		local party = { calls = {}, endsAt = 0 }
		Ev.queueGlowParty = function(buyer, seconds)
			if opts.partyFails then
				error("EventService indisponible")
			end
			table.insert(party.calls, { buyer = buyer, seconds = seconds })
			party.endsAt = math.max(Clock.now(), party.endsAt) + seconds
			return party.endsAt
		end
		h:boot()
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			M = M,
			party = party,
			Enum = h.globals.Enum,
			P = h:require("ServerScriptService.Server.Services.ProductService"),
			E = h:require("ServerScriptService.Server.Services.EconomyService"),
			A = h:require("ServerScriptService.Server.Services.AtlasService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			Mon = h:require("ServerScriptService.Server.Services.MonetizationService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
		}
		return ctx
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, data
	end

	local function buy(ctx, p, key, purchaseId)
		return ctx.h:purchaseProduct(p, PRODUCT_IDS[key], purchaseId)
	end

	local function celebrations(h, p, kind)
		local out = {}
		for _, args in h:sentTo(p, "Celebrate") do
			if args[1].kind == kind then
				table.insert(out, args[1])
			end
		end
		return out
	end

	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	describe("ProductService › produits", function()
		it("chaque produit à effet est enregistré et honoré via ProcessReceipt", function()
			local ctx = boot()
			local p = join(ctx, 1)
			for key in PRODUCT_IDS do
				expect({ key = key, decision = buy(ctx, p, key) }).toEqual({
					key = key,
					decision = ctx.Enum.ProductPurchaseDecision.PurchaseGranted,
				})
			end
			-- un produit sans effet connu n'est pas pris en charge (handler libre pour un autre)
			expect(ctx.P.grant(p, "Nope")).toBe(false)
		end)

		it("Glow : montant calculé au moment de l'attribution (minimum garanti)", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			expect(ctx.P.glowAmount(p, "GlowPouch")).toBe(1000)
			expect(buy(ctx, p, "GlowPouch", "r1")).toBe(ctx.Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(data.glow).toBe(1000)
			-- un Rare perché : 15 Glow/s
			ctx.A.addNebbies(p, { ctx.Nebbies.pack(16, 0, 0) }, "parade")
			expect(data.idleRate).toBe(15)
			expect(ctx.P.glowAmount(p, "GlowPouch")).toBe(9000)
			expect(ctx.P.glowAmount(p, "GlowSack")).toBe(36000)
			expect(ctx.P.glowAmount(p, "GlowCrate")).toBe(108000)
			expect(ctx.P.glowAmount(p, "StardustJar")).toBe(0)
			buy(ctx, p, "GlowCrate", "r2")
			expect(data.glow).toBe(1000 + 108000)
			local iap = {}
			for _, e in ctx.h.log.analytics do
				if e.method == "LogEconomyEvent" and e.args[7] == "Product_GlowCrate" then
					table.insert(iap, e.args)
				end
			end
			expect(#iap).toBe(1)
			expect(iap[1][4]).toBe(108000)
			expect(iap[1][6]).toBe("IAP")
			expect(#celebrations(ctx.h, p, "purchase")).toBe(2)
		end)

		it("un reçu rejoué n'est crédité qu'une fois", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			buy(ctx, p, "StardustJar", "same")
			buy(ctx, p, "StardustJar", "same")
			expect(data.stardust).toBe(400)
			buy(ctx, p, "StardustJar", "other")
			expect(data.stardust).toBe(800)
		end)

		it(
			"Glow Party : file de serveur, bannière, Feedback ; jamais refusée au-delà de 60 min",
			function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				local banners = {}
				ctx.Signals.BannerRequested:Connect(function(kind, args, source)
					table.insert(
						banners,
						{ kind = kind, name = args.name, userId = args.userId, source = source }
					)
				end)
				for i = 1, 7 do
					expect(buy(ctx, p, "GlowParty", "party" .. i)).toBe(
						ctx.Enum.ProductPurchaseDecision.PurchaseGranted
					)
				end
				expect(#ctx.party.calls).toBe(7)
				expect(ctx.party.calls[1].seconds).toBe(600)
				expect(ctx.party.calls[1].buyer).toBe(p)
				expect(ctx.party.endsAt).toBe(T0 + 7 * 600)
				ctx.h:settle(1)
				expect(#banners).toBe(7)
				expect(banners[1]).toEqual({ kind = "glowParty", name = "P1", userId = 1, source = p })
				local fb = ctx.h:sentTo(p, "Feedback")
				expect(fb[1][1]).toEqual({
					key = "feedback.glowPartyQueued",
					vars = { minutes = 10 },
					tone = "reward",
				})
				expect(fb[7][1].vars.minutes).toBe(70)
				expect(data.glow).toBe(0)
			end
		)

		it(
			"Glow Party : si EventService échoue, rien n'est accordé et Roblox représentera le reçu",
			function()
				local ctx = boot({ partyFails = true })
				local p = join(ctx, 1)
				expect(buy(ctx, p, "GlowParty", "x")).toBe(ctx.Enum.ProductPurchaseDecision.NotProcessedYet)
				expect(#celebrations(ctx.h, p, "purchase")).toBe(0)
				expect(#ctx.h:sentTo(p, "Feedback")).toBe(0)
			end
		)

		it(
			"Starter Kit : 3 Rares, style Comet Tail, boost 20 min ; une seconde vente est honorée",
			function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				expect(data.starterKit).toBe(false)
				expect(buy(ctx, p, "StarterKit", "kit1")).toBe(
					ctx.Enum.ProductPurchaseDecision.PurchaseGranted
				)
				expect(data.starterKit).toBe(true)
				local species = {}
				for _, rec in data.nebbies do
					table.insert(species, rec.s)
					expect(rec.f).toBe(0)
					expect(rec.st).toBe(1)
				end
				table.sort(species)
				expect(species).toEqual(ctx.M.Products.StarterKit.species)
				expect(data.unlocks.styles.comet_tail).toBe(true)
				expect(ctx.N.hasUnlock(p, "styles", "comet_tail")).toBe(true)
				expect(data.boosts.personalUntil).toBe(T0 + 1200)
				expect(ctx.E.hasBoost(p)).toBe(true)
				-- 3 Rares perchés × boost ×2
				expect(data.idleRate).toBe(45 * 2)
				expect(buy(ctx, p, "StarterKit", "kit2")).toBe(
					ctx.Enum.ProductPurchaseDecision.PurchaseGranted
				)
				expect(count(data.nebbies)).toBe(6)
				expect(data.boosts.personalUntil).toBe(T0 + 2400)
				expect(celebrations(ctx.h, p, "purchase")[1].data).toEqual({ product = "StarterKit" })
			end
		)

		it("profil absent ou joueur parti : rien n'est accordé", function()
			local ctx = boot()
			local p = join(ctx, 1)
			ctx.h:removePlayer(p)
			ctx.h:settle(3)
			expect(buy(ctx, p, "GlowPouch", "late")).toBe(ctx.Enum.ProductPurchaseDecision.NotProcessedYet)
			expect(ctx.P.grant(p, "GlowPouch")).toBe(false)
			expect(ctx.P.glowAmount(p, "GlowPouch")).toBe(1000)
			expect(#ctx.party.calls).toBe(0)
		end)
	end)

	describe("ProductService › passes", function()
		it(
			"VIP Star acheté en jeu : réglé à l'ancien taux, puis +25 %, badge et « Merci ! »",
			function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				ctx.A.addNebbies(p, { ctx.Nebbies.pack(16, 0, 0) }, "parade")
				ctx.Clock.advance(10)
				ctx.h:grantPass(p, PASS_IDS.VIPStar)
				ctx.h:settle(2)
				expect(data.glow).toBe(150)
				expect(data.idleRate).toBeNear(15 * 1.25)
				expect(p:GetAttribute("VIP")).toBe(true)
				expect(ctx.N.hasUnlock(p, "themes", "royal_gold")).toBe(true)
				expect(celebrations(ctx.h, p, "purchase")[1].data).toEqual({ pass = "VIPStar" })
			end
		)

		it("Double Glow, Extra Perches, Stash Plus, Conga Styles, Night Shift", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, { ctx.Nebbies.pack(16, 0, 0) }, "parade")
			ctx.h:grantPass(p, PASS_IDS.DoubleGlow)
			ctx.h:grantPass(p, PASS_IDS.ExtraPerches)
			ctx.h:grantPass(p, PASS_IDS.StashPlus)
			ctx.h:grantPass(p, PASS_IDS.CongaStyles)
			ctx.h:grantPass(p, PASS_IDS.NightShift)
			ctx.h:settle(2)
			expect(data.idleRate).toBe(30)
			expect(ctx.A.perchCount(p)).toBe(9)
			expect(ctx.A.stashCap(p)).toBe(600)
			expect(ctx.N.hasUnlock(p, "styles", "rainbow_ripple")).toBe(true)
			expect(#celebrations(ctx.h, p, "purchase")).toBe(5)
		end)

		it("passes possédés à l'arrivée : effets appliqués, sans « Merci ! »", function()
			local ctx = boot()
			ctx.h.ownedPasses[1] = { [PASS_IDS.DoubleGlow] = true, [PASS_IDS.ExtraPerches] = true }
			local p, data = join(ctx, 1)
			ctx.h:settle(3)
			expect(ctx.Mon.ownsPass(p, "DoubleGlow")).toBe(true)
			expect(ctx.A.perchCount(p)).toBe(9)
			ctx.A.addNebbies(p, { ctx.Nebbies.pack(16, 0, 0) }, "parade")
			expect(data.idleRate).toBe(30)
			expect(#celebrations(ctx.h, p, "purchase")).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("un pass refusé ou inconnu ne déclenche rien", function()
			local ctx = boot()
			local p = join(ctx, 1)
			ctx.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, PASS_IDS.VIPStar, false)
			ctx.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, 999999, true)
			ctx.h:settle(2)
			expect(#celebrations(ctx.h, p, "purchase")).toBe(0)
			expect(ctx.Mon.ownsPass(p, "VIPStar")).toBe(false)
		end)
	end)
end
