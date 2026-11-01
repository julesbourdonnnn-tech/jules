--!nocheck
-- ProductService (paquet ranch, docs/04 §11.12, §18.2) : Squish Party (refusée seulement au plafond
-- du jour ; reçu pendant une fête → EventService la prolonge, jamais refusé ; reçu rejoué crédité une
-- fois), acheteur parti pendant sa fête → boosts.personalLeft = secondes non jouées dans la sauvegarde
-- de départ ; reçu, fermeture du serveur, nouveau serveur → boost présent EXACTEMENT une fois ; tenues ;
-- paquets de pièces cachés sans handler ; PolicyService pour l'analytique seulement ; zéro trace.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local IDS = {
		SquishParty = 501,
		OutfitSweater = 502,
		OutfitCrown = 503,
		OutfitWinter = 504,
		CoinsSmall = 505,
		CoinsBig = 506,
	}

	-- Serveur complet ; produits numérotés ; EventService simulé (paquet chase) : chaque achat note un
	-- segment de 600 s pour l'acheteur ; `played` secondes déjà jouées
	local function boot(before)
		local caught = {}
		local party = { calls = {}, segments = {}, played = {} }
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Monetization = w.h:require("ReplicatedStorage.Shared.Config.Monetization")
				for key, id in IDS do
					Monetization.Products[key].id = id
				end
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				local Event = w.h:require(S .. "EventService")
				Event.startSquishParty = function(buyer, showName)
					table.insert(party.calls, { buyer = buyer, showName = showName })
					party.segments[buyer.UserId] = (party.segments[buyer.UserId] or 0) + 600
					return true
				end
				Event.partyUnplayed = function(userId)
					return math.max(0, (party.segments[userId] or 0) - (party.played[userId] or 0))
				end
				if before then
					before(w)
				end
			end,
		})
		w.caught, w.party = caught, party
		w.Product = w.h:require(S .. "ProductService")
		w.Economy = w.h:require(S .. "EconomyService")
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

	local function storeOf(w)
		return w.h.game.DataStoreService:GetDataStore(w.Schema.STORE_NAME)
	end

	local GRANTED = "PurchaseGranted"

	describe("ProductService › Squish Party", function()
		it(
			"achat : fête démarrée, plafond compté, Celebrate « purchase » ; reçu rejoué crédité une seule fois",
			function()
				local w = boot()
				local p = Bots.join(1)
				local decision = w.h:purchaseProduct(p, IDS.SquishParty, "r1")
				w.h:settle(3)
				expect(decision.Name).toBe(GRANTED)
				expect(#w.party.calls).toBe(1)
				expect(w.party.calls[1].showName).toBe(false)
				expect(w.Product.partyBuysToday(p)).toBe(1)
				local again = w.h:purchaseProduct(p, IDS.SquishParty, "r1")
				w.h:settle(3)
				expect(again.Name).toBe(GRANTED)
				expect(#w.party.calls).toBe(1)
				expect(w.Product.partyBuysToday(p)).toBe(1)
				local found = false
				for _, args in w.h:sentTo(p, "Celebrate") do
					if args[1].kind == "purchase" and args[1].data.key == "SquishParty" then
						found = true
					end
				end
				expect(found).toBe(true)
				clean(w)
			end
		)

		it(
			"reçu pendant une fête : jamais refusé (EventService la prolonge) ; refus seulement au plafond du jour (3)",
			function()
				local w = boot()
				local p = Bots.join(1)
				for i = 1, 3 do
					expect(w.h:purchaseProduct(p, IDS.SquishParty, "p" .. i).Name).toBe(GRANTED)
					w.h:settle(2)
				end
				expect(#w.party.calls).toBe(3)
				local refused = w.h:purchaseProduct(p, IDS.SquishParty, "p4")
				expect(refused.Name).toBe("NotProcessedYet")
				expect(#w.party.calls).toBe(3)
				-- nouveau jour : de nouveau possible
				w.Clock.advance(86400)
				expect(w.Product.partyBuysToday(p)).toBe(0)
				expect(w.h:purchaseProduct(p, IDS.SquishParty, "p5").Name).toBe(GRANTED)
				w.h:settle(2)
				clean(w)
			end
		)

		it("EventService en panne : rien n'est compté ni accordé (le reçu sera réessayé)", function()
			local w = boot()
			local Event = w.h:require(S .. "EventService")
			Event.startSquishParty = function()
				error("panne simulée")
			end
			local p = Bots.join(1)
			expect(w.h:purchaseProduct(p, IDS.SquishParty, "x1").Name).toBe("NotProcessedYet")
			expect(w.Product.partyBuysToday(p)).toBe(0)
			expect(#w.caught).toBe(1)
			table.clear(w.caught)
			clean(w)
		end)

		it(
			"l'acheteur part pendant sa fête : personalLeft = secondes non jouées dans la sauvegarde de départ",
			function()
				local w = boot()
				local p = Bots.join(1)
				w.h:purchaseProduct(p, IDS.SquishParty, "q1")
				w.h:settle(2)
				w.party.played[1] = 200
				Bots.leave(p)
				w.h:settle(5)
				local saved = storeOf(w):GetAsync("player_1").data
				expect(saved.boosts.personalLeft).toBe(400)
				-- un joueur qui n'a rien acheté : aucun boost
				local q = Bots.join(2)
				w.party.segments[2] = 600 -- même si EventService répondait quelque chose
				Bots.leave(q)
				w.h:settle(5)
				expect(storeOf(w):GetAsync("player_2").data.boosts.personalLeft).toBe(0)
				clean(w)
			end
		)

		it("reçu, fermeture du serveur, nouveau serveur : boost présent exactement une fois", function()
			local w = boot()
			local p = Bots.join(1)
			expect(w.h:purchaseProduct(p, IDS.SquishParty, "z1").Name).toBe(GRANTED)
			w.h:settle(2)
			w.h:close() -- BindToClose : sauvegarde de départ de chaque joueur présent
			w.h:settle(10)
			local record = storeOf(w):GetAsync("player_1")
			expect(record.data.boosts.personalLeft).toBe(600)
			expect(table.find(record.data.receipts, "z1") ~= nil).toBe(true)
			-- nouveau serveur, même magasin (verrou libéré par la sauvegarde de départ)
			local w2 = boot(function(w2)
				storeOf(w2):SetAsync("player_1", { data = record.data })
			end)
			local p2 = Bots.join(1)
			local data = w2.DS.get(p2)
			expect(data.boosts.personalLeft).toBe(600)
			expect(w2.Economy.boostActive(p2)).toBe(true)
			-- Roblox redélivre le même reçu : déjà crédité, aucune fête ni aucun boost de plus
			expect(w2.h:purchaseProduct(p2, IDS.SquishParty, "z1").Name).toBe(GRANTED)
			w2.h:settle(3)
			expect(#w2.party.calls).toBe(0)
			Bots.use(w2)
			Bots.leave(p2)
			w2.h:settle(5)
			local after = storeOf(w2):GetAsync("player_1").data
			expect(after.boosts.personalLeft <= 600).toBe(true)
			clean(w)
			clean(w2)
		end)
	end)

	describe("ProductService › tenues, paquets cachés, passes, PolicyService", function()
		it("tenue achetée : un exemplaire de plus dans la garde-robe", function()
			local w = boot()
			local p = Bots.join(1)
			expect(w.h:purchaseProduct(p, IDS.OutfitSweater, "o1").Name).toBe(GRANTED)
			expect(w.h:purchaseProduct(p, IDS.OutfitSweater, "o2").Name).toBe(GRANTED)
			w.h:settle(3)
			local data = w.DS.get(p)
			expect(data.outfits.owned.sweater).toBe(2)
			expect(data.outfits.worn).toEqual({})
			clean(w)
		end)

		it("paquets de pièces cachés : aucun handler, aucune pièce (même avec un id)", function()
			local w = boot()
			local p = Bots.join(1)
			expect(w.h:purchaseProduct(p, IDS.CoinsSmall, "c1").Name).toBe("NotProcessedYet")
			expect(w.h:purchaseProduct(p, IDS.CoinsBig, "c2").Name).toBe("NotProcessedYet")
			expect(w.DS.get(p).coins).toBe(0)
			clean(w, "produit sans handler")
		end)

		it("pass ×2 Pièces accordé : refresh, P appliqué une seule fois", function()
			local w = boot(function(w)
				local Monetization = w.h:require("ReplicatedStorage.Shared.Config.Monetization")
				Monetization.Passes.DoubleCoins.id = 601
			end)
			local p = Bots.join(1)
			w.h:grantPass(p, 601)
			w.h:settle(5)
			expect(w.Economy.incomeCtx(p).doubleCoins).toBe(true)
			clean(w)
		end)

		it(
			"PolicyService : analytique PolicyPaidRandomRestricted seulement, aucun attribut PolicyNoCoins",
			function()
				local w = boot()
				local p = Bots.join(1)
				w.h:settle(3)
				local seen = false
				for _, e in w.h.log.analytics do
					if e.method == "LogCustomEvent" and e.args[2] == "PolicyPaidRandomRestricted" then
						seen = true
					end
				end
				expect(seen).toBe(true)
				expect(p:GetAttribute("PolicyNoCoins")).toBeNil()
				clean(w)
			end
		)
	end)
end
