--!nocheck
-- RedTeam_Purchase (paquet ranch, docs/04 §15, §17.1 couche g, §18.2) : achats et pièces écrits comme
-- des attaques. Produit inconnu, joueur absent, reçu rejoué, 4e Squish Party du jour, paquet de pièces
-- caché, faux signal d'achat de pass, BuyTile en rafale ou sur une dalle éteinte, vente en double, vente
-- pendant une fusion : jamais de pièce, de tenue, de boost ou de fête en trop, jamais de pièces
-- négatives.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."

	local function rec(extra)
		local r =
			{ s = 2, m = 0, st = 0, z = 100, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 1, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	local function boot()
		local caught = {}
		local parties = {}
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Monetization = w.h:require("ReplicatedStorage.Shared.Config.Monetization")
				Monetization.Products.SquishParty.id = 801
				Monetization.Products.OutfitSweater.id = 802
				Monetization.Products.CoinsSmall.id = 803
				Monetization.Passes.DoubleCoins.id = 901
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				local Event = w.h:require(S .. "EventService")
				Event.startSquishParty = function(buyer)
					table.insert(parties, buyer)
					return true
				end
				Event.partyUnplayed = function()
					return 0
				end
				local d = Bots.profile(w, {
					onboarding = { step = 11, done = true, demoDone = true },
					squishies = {
						["1"] = rec({ s = 1, bf = 1 }),
						["2"] = rec(),
						["3"] = rec(),
						["4"] = rec({ at = "pool" }),
					},
					nextUid = 5,
					coins = 15,
				})
				Bots.saveProfile(w, 1, d)
			end,
		})
		w.caught, w.parties = caught, parties
		w.Economy = w.h:require(S .. "EconomyService")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		return w
	end

	local function clean(w, allowed)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		local warnings = {}
		for _, line in w.h:warnings() do
			if not (allowed and string.find(line, allowed, 1, true)) then
				table.insert(warnings, line)
			end
		end
		expect(table.concat(warnings, "\n")).toBe("")
	end

	describe("RedTeam_Purchase › reçus", function()
		it("produit inconnu, joueur absent : rien d'accordé", function()
			if T.expectWarning then
				T.expectWarning("[Monetization] produit sans handler")
			end
			local w = boot()
			local p = Bots.join(1)
			expect(w.h:purchaseProduct(p, 999999, "u1").Name).toBe("NotProcessedYet")
			local ghost = { UserId = 424242 }
			expect(w.h:purchaseProduct(ghost, 801, "u2").Name).toBe("NotProcessedYet")
			expect(#w.parties).toBe(0)
			clean(w, "produit sans handler")
		end)

		it(
			"reçu rejoué 20 fois : une seule tenue ; 4e Squish Party du jour refusée, jamais plus de 3",
			function()
				local w = boot()
				local p = Bots.join(1)
				for _ = 1, 20 do
					w.h:purchaseProduct(p, 802, "same")
				end
				w.h:settle(3)
				expect(w.DS.get(p).outfits.owned.sweater).toBe(1)
				for i = 1, 6 do
					w.h:purchaseProduct(p, 801, "party" .. i)
					w.h:settle(1)
				end
				expect(#w.parties).toBe(3)
				expect(w.DS.get(p).caps.partyBuys).toBe(3)
				clean(w)
			end
		)

		it(
			"paquet de pièces caché : aucune pièce ; faux signal d'achat du pass ×2 Pièces : rien",
			function()
				if T.expectWarning then
					T.expectWarning("[Monetization] produit sans handler")
				end
				local w = boot()
				local p = Bots.join(1)
				expect(w.h:purchaseProduct(p, 803, "c1").Name).toBe("NotProcessedYet")
				expect(w.DS.get(p).coins).toBe(15)
				-- l'exploit émet PromptGamePassPurchaseFinished(wasPurchased = true) sans posséder le pass
				w.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, 901, true)
				w.h:settle(5)
				expect(w.Economy.incomeCtx(p).doubleCoins).toBe(false)
				clean(w, "produit sans handler")
			end
		)
	end)

	describe("RedTeam_Purchase › pièces", function()
		it(
			"BuyTile en rafale, dalle éteinte, dalle inconnue : jamais de pièces négatives ni de niveau gratuit",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				for _ = 1, 50 do
					w.RateLimit.clear(p)
					w.h:fireServer("ReplicatedStorage.Remotes.BuyTile", p, "snack") -- 20 > 15 pièces
				end
				for _, tile in { "cozyBed", "decor", "rocket", "coins" } do
					w.RateLimit.clear(p)
					w.h:fireServer("ReplicatedStorage.Remotes.BuyTile", p, tile)
				end
				expect(data.coins).toBe(15)
				expect(data.tiles.snack).toBe(0)
				expect(data.tiles.cozyBed).toBe(false)
				expect(data.tiles.decor).toBe(0)
				-- dépenses hostiles directes : refusées
				expect(w.Economy.trySpend(p, -100, "Hack")).toBe(false)
				expect(w.Economy.trySpend(p, 0 / 0, "Hack")).toBe(false)
				expect(w.Economy.addCoins(p, -50, "Hack")).toBe(0)
				expect(w.Economy.addCoins(p, 0 / 0, "Hack")).toBe(0)
				expect(data.coins).toBe(15)
				clean(w)
			end
		)

		it(
			"vente en double (même message, messages répétés) et vente pendant une fusion : une seule fois",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.RateLimit.clear(p)
				w.h:fireServer("ReplicatedStorage.Remotes.Sell", p, { "2", "2" }, true)
				expect(data.squishies["2"] ~= nil).toBe(true)
				w.RateLimit.clear(p)
				w.h:fireServer("ReplicatedStorage.Remotes.Sell", p, { "2" }, true)
				local after = data.coins
				expect(after > 15).toBe(true)
				for _ = 1, 5 do
					w.RateLimit.clear(p)
					w.h:fireServer("ReplicatedStorage.Remotes.Sell", p, { "2" }, true)
				end
				expect(data.coins).toBe(after)
				-- « 3 » et « 4 » en fusion (Bassin) : ni vendus ni relâchés pendant les 0,4 s
				w.RateLimit.clear(p)
				w.h:fireServer("ReplicatedStorage.Remotes.FuseMenu", p, "3", "4")
				w.RateLimit.clear(p)
				w.h:fireServer("ReplicatedStorage.Remotes.Sell", p, { "3" }, true)
				w.RateLimit.clear(p)
				w.h:fireServer("ReplicatedStorage.Remotes.Release", p, { "4" }, true)
				expect(data.squishies["3"] ~= nil and data.squishies["4"] ~= nil).toBe(true)
				expect(data.coins).toBe(after)
				clean(w)
			end
		)
	end)
end
