--!nocheck
-- Analytics du jeu (note INT-ANALYTICS, paquet meta, GDD §16) : économie cumulée par joueur, tranche de
-- 5 min et itemSku, en secondes de revenu ; débit commun ≤ 10 requêtes par joueur et par minute sur un
-- serveur simulé de 16 joueurs (30 min de jeu intense) ; départ et fermeture ; événements du catalogue.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000

	local function setup(n)
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local A = h:require("ServerScriptService.Server.Util.Analytics")
		local players = {}
		for i = 1, n or 1 do
			table.insert(players, h:addPlayer({ userId = i, spawn = false }))
		end
		return h, A, Clock, players
	end

	local function calls(h, method)
		local out = {}
		for _, c in h.log.analytics do
			if method == nil or c.method == method then
				table.insert(out, c)
			end
		end
		return out
	end

	describe("Analytics du jeu › cumul de l'économie", function()
		it("un événement par itemSku et par tranche de 5 min, montants en secondes de revenu", function()
			local h, A, Clock, ps = setup(1)
			local p = ps[1]
			for _ = 1, 120 do
				A.earnIncome(p, "Press", 20, 10, "Gameplay") -- 2 s de revenu chacune
				Clock.advance(1)
			end
			A.spendIncome(p, "Tile_snack", 300, 10, "Shop")
			h:settle(2)
			expect(#calls(h, "LogEconomyEvent")).toBe(0) -- rien avant la fin de la tranche
			Clock.advance(300)
			A.step(Clock.now())
			h:settle(2)
			local eco = calls(h, "LogEconomyEvent")
			expect(#eco).toBe(2)
			local bySku = {}
			for _, c in eco do
				bySku[c.args[7]] = c.args
			end
			expect(bySku.Press[4]).toBe(240)
			expect(bySku.Press[2]).toBe(h.globals.Enum.AnalyticsEconomyFlowType.Source)
			expect(bySku.Tile_snack[4]).toBe(30)
			expect(bySku.Tile_snack[2]).toBe(h.globals.Enum.AnalyticsEconomyFlowType.Sink)
			expect(bySku.Tile_snack[6]).toBe("Shop")
		end)

		it(
			"chaque montant est converti au revenu de son instant ; solde en secondes du dernier revenu",
			function()
				local h, A, Clock, ps = setup(1)
				local p = ps[1]
				A.earnIncome(p, "Pot", 100, 10, "Gameplay", 1000) -- 10 s
				A.earnIncome(p, "Pot", 100, 50, "Gameplay", 5000) -- 2 s ; solde 5000 / 50 = 100 s
				Clock.advance(301)
				A.step(Clock.now())
				h:settle(2)
				local eco = calls(h, "LogEconomyEvent")
				expect(#eco).toBe(1)
				expect(eco[1].args[4]).toBe(12)
				expect(eco[1].args[5]).toBe(100)
			end
		)

		it(
			"montants nuls, négatifs, NaN ou sku vide ignorés ; revenu nul compté 1 pièce = 1 s",
			function()
				local h, A, Clock, ps = setup(1)
				local p = ps[1]
				A.earnIncome(p, "Press", 0, 10, "Gameplay")
				A.earnIncome(p, "Press", -5, 10, "Gameplay")
				A.earnIncome(p, "Press", 0 / 0, 10, "Gameplay")
				A.earnIncome(p, "", 50, 10, "Gameplay")
				A.earnIncome(p, "Offline", 7, 0, "TimedReward")
				Clock.advance(301)
				A.step(Clock.now())
				h:settle(2)
				local eco = calls(h, "LogEconomyEvent")
				expect(#eco).toBe(1)
				expect(eco[1].args[7]).toBe("Offline")
				expect(eco[1].args[4]).toBe(7)
			end
		)

		it(
			"départ : la tranche en cours part aussitôt (flush), rien n'est gardé pour ce joueur",
			function()
				local h, A, _, ps = setup(1)
				local p = ps[1]
				A.earnIncome(p, "Press", 30, 10, "Gameplay")
				A.earnIncome(p, "Combo", 60, 10, "Gameplay")
				h:removePlayer(p)
				h:settle(2)
				expect(#calls(h, "LogEconomyEvent")).toBe(2)
				expect(A.stats(p).pending).toBe(0)
			end
		)

		it("fermeture (BindToClose) : la tranche en cours de chaque joueur part", function()
			local h, A, _, ps = setup(3)
			for _, p in ps do
				A.earnIncome(p, "Press", 30, 10, "Gameplay")
			end
			h:close()
			h:settle(2)
			expect(#calls(h, "LogEconomyEvent")).toBe(3)
		end)
	end)

	describe("Analytics du jeu › débit", function()
		it(
			"16 joueurs, 30 min de jeu intense : jamais plus de 10 requêtes par joueur sur 60 s glissantes",
			function()
				local h, A, Clock, ps = setup(16)
				local perSecond = {} -- [userId] = { [seconde] = n }
				local seen = 0
				local function harvest(second)
					local log = h.log.analytics
					for i = seen + 1, #log do
						local player = log[i].args[1]
						local id = player.UserId
						perSecond[id] = perSecond[id] or {}
						perSecond[id][second] = (perSecond[id][second] or 0) + 1
					end
					seen = #log
				end
				for _, p in ps do
					for step = 1, 11 do
						A.funnel(p, step, "Step" .. step)
					end
				end
				local skus = {
					"Press",
					"Pot",
					"Combo",
					"Sell",
					"Tile_snack",
					"Tile_decor",
					"Golden",
					"PetSit",
					"Clap",
				}
				local events = {
					"PetSitPress",
					"BoopDone",
					"HatchRarity",
					"ComboLength",
					"RushCatchByInput",
					"MegaResult",
				}
				for second = 1, 1800 do
					for i, p in ps do
						A.earnIncome(p, skus[(second + i) % #skus + 1], 50, 10, "Gameplay")
						if second % 7 == i % 7 then
							A.spendIncome(p, "Tile_snack", 100, 10, "Shop")
						end
						if second % 5 == 0 then
							-- 12 événements personnalisés par minute et par joueur : au-delà du budget
							A.custom(p, events[(second // 5 + i) % #events + 1], 1)
						end
						if second == 900 then
							A.custom(p, "PostBoopQuit", 30)
						end
					end
					A.step(Clock.now())
					h:settle(1)
					harvest(second)
					Clock.advance(1)
				end
				for _, p in ps do
					A.flush(p)
				end
				h:settle(2)
				harvest(1801)
				local worst = 0
				for _, bySecond in perSecond do
					for start = 1, 1801 do
						local n = 0
						for s = start, math.min(1801, start + 59) do
							n += bySecond[s] or 0
						end
						worst = math.max(worst, n)
					end
				end
				expect(worst).toBeLessThanOrEqual(10)
				expect(worst).toBeGreaterThan(0)
				-- l'indicateur n° 1 passe malgré le débordement
				local quits = 0
				for _, c in calls(h, "LogCustomEvent") do
					if c.args[2] == "PostBoopQuit" then
						quits += 1
					end
				end
				expect(quits).toBe(16)
				-- l'entonnoir complet de chaque joueur passe
				expect(#calls(h, "LogOnboardingFunnelStepEvent")).toBe(16 * 11)
			end
		)

		it(
			"au-delà du débit, la requête attend sa place (Analytics.step) au lieu d'être perdue",
			function()
				local h, A, Clock, ps = setup(1)
				local p = ps[1]
				for i = 1, 15 do
					A.custom(p, "BoopDone", i)
				end
				h:settle(2)
				expect(#calls(h, "LogCustomEvent")).toBe(10)
				expect(A.stats(p).pending).toBe(5)
				Clock.advance(61)
				A.step(Clock.now())
				h:settle(2)
				expect(#calls(h, "LogCustomEvent")).toBe(15)
				expect(A.stats(p).pending).toBe(0)
			end
		)

		it("joueur parti : une requête « au départ » passe au débit restant, jamais au-delà", function()
			local h, A, _, ps = setup(1)
			local p = ps[1]
			for i = 1, 9 do
				A.custom(p, "BoopDone", i)
			end
			h:removePlayer(p)
			A.custom(p, "SessionLength", 12)
			A.custom(p, "BoostShare", 30)
			h:settle(2)
			local sent = calls(h, "LogCustomEvent")
			expect(#sent).toBe(10)
			expect(sent[10].args[2]).toBe("SessionLength")
			expect(A.stats(p).dropped).toBeGreaterThanOrEqual(1)
		end)
	end)

	describe("Analytics du jeu › événements personnalisés", function()
		it(
			"catalogue du GDD §16.3 : TileLevelAtSplorch, BoostShare, PolicyPaidRandomRestricted ; plus de ShopHiddenByPolicy",
			function()
				local _, A = setup(0)
				expect(A.isKnown("TileLevelAtSplorch")).toBe(true)
				expect(A.isKnown("BoostShare")).toBe(true)
				expect(A.isKnown("PolicyPaidRandomRestricted")).toBe(true)
				expect(A.isKnown("ShopHiddenByPolicy")).toBe(false)
			end
		)

		it(
			"champs : ceux de l'appelant (3 au plus, par clé), sinon device / serverBand / sessionBand",
			function()
				local h, A, _, ps = setup(1)
				local p = ps[1]
				A.setSegment(p, "device", "console")
				A.setSegment(p, "sessionBand", "first")
				A.custom(p, "MegaResult", 1, { participants = 8, n = 12, points = 900, target = 800 })
				A.custom(p, "ShopOpened", 1)
				h:settle(2)
				local sent = calls(h, "LogCustomEvent")
				expect(#sent).toBe(2)
				local Keys = h.globals.Enum.AnalyticsCustomFieldKeys
				local f1 = sent[1].args[4]
				expect(f1[Keys.CustomField01]).toBe("n:12")
				expect(f1[Keys.CustomField02]).toBe("participants:8")
				expect(f1[Keys.CustomField03]).toBe("points:900")
				local f2 = sent[2].args[4]
				expect(f2[Keys.CustomField01]).toBe("device:console")
				expect(f2[Keys.CustomField02]).toBe("serverBand:1-5")
				expect(f2[Keys.CustomField03]).toBe("sessionBand:first")
			end
		)

		it("nom hors catalogue : envoyé mais compté ; valeur NaN remplacée par 1", function()
			local h, A, _, ps = setup(1)
			local p = ps[1]
			local before = A.stats().unknown
			A.custom(p, "Typo_Event", 0 / 0)
			h:settle(2)
			expect(A.stats().unknown).toBe(before + 1)
			expect(calls(h, "LogCustomEvent")[1].args[3]).toBe(1)
		end)
	end)

	describe("Analytics du jeu › revue", function()
		it(
			"montants extrêmes (revenu minuscule, pièces énormes) : jamais un montant infini envoyé",
			function()
				local h, A, Clock, ps = setup(1)
				local p = ps[1]
				A.earnIncome(p, "Press", 1e300, 1e-300, "Gameplay", 1e308)
				A.earnIncome(p, "Press", 1e300, 1e-300, "Gameplay")
				A.spendIncome(p, "Tile_snack", 1e308, 1e-300, "Shop", 1e308)
				Clock.advance(300)
				A.step(Clock.now())
				h:settle(2)
				local eco = calls(h, "LogEconomyEvent")
				expect(#eco).toBe(2)
				for _, c in eco do
					local amount, balance = c.args[4], c.args[5]
					expect(amount == amount and amount ~= math.huge and amount >= 1).toBe(true)
					expect(balance == balance and balance ~= math.huge and balance >= 0).toBe(true)
				end
			end
		)
	end)
end
