--!nocheck
-- EconomyService (paquet ranch, docs/04 §11.5, §16, §18.2) : règlement exact sur [growth.t ; now]
-- (N règlements = 1 ; 100 refus de BuyTile = aucune pièce de plus), rebase hors ligne avant tout
-- règlement (30 %, arrêt à 90 % de l'objectif, 8 h), écran de retour (nearlyReady), boosts jamais
-- cumulés (personnel en pause pendant un boost de serveur), Grand Splorch d'un bloc, déclencheurs de
-- refresh (palier de trophée, page dorée, bonus de famille, Fame), récompense en secondes de revenu avec
-- P et B appliqués UNE seule fois, plafonds (consumeCap, consumeFriendCap, remise à zéro du jour),
-- BuyTile (source pad / panel), lastOnline au départ, zéro trace.
local Bots = require("../harness/Bots")
local Flags = require("../harness/Flags")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."

	-- harness : Harness (configuration livrée) par défaut ; un préréglage pour un cas qui prouve la v1.3
	local function boot(before, harness)
		local caught = {}
		local w = Bots.boot(harness or Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				if before then
					before(w)
				end
			end,
		})
		w.caught = caught
		w.Ranch = w.h:require(S .. "RanchService")
		w.Economy = w.h:require(S .. "EconomyService")
		w.Squishy = w.h:require(S .. "SquishyService")
		w.Formulas = w.h:require("ReplicatedStorage.Shared.Logic.Formulas")
		w.Balance = w.h:require("ReplicatedStorage.Shared.Config.Balance")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	local function rec(extra)
		local r = {
			s = 1,
			m = 0,
			st = 1,
			z = 1000,
			zg = 0,
			bf = 0,
			lk = false,
			o = "",
			at = "pen",
			b = 100,
			gd = 0,
		}
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	local function near(a, b, rel)
		local scale = math.max(1, math.abs(a), math.abs(b))
		return math.abs(a - b) <= (rel or 1e-9) * scale
	end

	-- Profil de jeu : accueil fini, quelques squishies d'enclos
	local function profile(w, overrides)
		local d = Bots.profile(w, {
			onboarding = { step = 11, done = true, demoDone = true },
			squishies = {
				["1"] = rec({ bf = 1 }),
				["2"] = rec({ s = 5, z = 400 }),
				["3"] = rec({ s = 9, z = 50 }),
			},
			nextUid = 4,
		})
		-- dalles déjà découvertes (bits seen) ; records de l'Étagère au-dessus des tailles du test (aucun
		-- palier franchi pendant un test de règlement)
		d.tiles.seen = 15
		for _, s in { 1, 5, 9 } do
			d.trophies[s] = 1e5
		end
		for k, v in overrides or {} do
			d[k] = v
		end
		return d
	end

	local function celebrations(w, p, kind)
		local out = {}
		for _, args in w.h:sentTo(p, "Celebrate") do
			if args[1].kind == kind then
				table.insert(out, args[1].data)
			end
		end
		return out
	end

	describe("EconomyService › règlement exact", function()
		it(
			"N règlements sur [t0, t1] = 1 règlement (à 1e-9 relatif près) ; pièces jamais touchées",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, profile(w))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.Economy.refresh(p)
				local growth0 = table.clone(data.growth)
				local pot0 = data.pot
				local ctx = w.Economy.incomeCtx(p)
				local K, S1 = w.Formulas.ranchIncome(data.squishies, growth0.G, ctx)
				local steps = { 0.013, 0.7, 1.31, 0.001, 2.5, 0.29, 5, 0.17, 3.333, 0.05 }
				local total = 0
				for i = 1, 60 do
					local dt = steps[(i % #steps) + 1]
					total += dt
					w.Clock.advance(dt)
					w.Economy.settle(p)
				end
				-- instant final réel (l'horloge figée arrondit chaque pas à la précision de 1,8e9)
				local t1 = w.Clock.now()
				expect(near(t1 - growth0.t, total, 1e-6)).toBe(true)
				local expected = pot0 + w.Formulas.potGain(K, S1, growth0, growth0.t, t1)
				expect(near(data.pot, expected)).toBe(true)
				expect(near(data.growth.G, w.Formulas.G(growth0, t1))).toBe(true)
				expect(data.coins).toBe(0)
				-- un règlement sans temps écoulé n'ajoute rien
				local pot1 = data.pot
				w.Economy.settle(p)
				w.Economy.settle(p)
				expect(data.pot).toBe(pot1)
				clean(w)
			end
		)

		it(
			"100 refus de BuyTile en 10 s n'ajoutent aucune pièce au-delà de l'intégrale de base",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, profile(w))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.Economy.refresh(p)
				local growth0 = table.clone(data.growth)
				local pot0 = data.pot
				local K, S1 = w.Formulas.ranchIncome(data.squishies, growth0.G, w.Economy.incomeCtx(p))
				for _ = 1, 100 do
					w.Clock.advance(0.1)
					w.RateLimit.clear(p)
					w.h:fireServer("ReplicatedStorage.Remotes.BuyTile", p, "pens") -- 1 200 pièces : refusé
				end
				local expected = pot0 + w.Formulas.potGain(K, S1, growth0, growth0.t, w.Clock.now())
				expect(near(data.pot, expected, 1e-9)).toBe(true)
				expect(data.coins).toBe(0)
				expect(data.tiles.pens).toBe(0)
				clean(w)
			end
		)
	end)

	describe("EconomyService › hors ligne (rebase avant tout règlement)", function()
		it("Pot 25 % et croissance 30 % de l'absence ; l'ancien growth.t n'est jamais intégré", function()
			local w = boot(function(w)
				local d = profile(w, { lastOnline = T0 - 3600 })
				d.growth = { G = 100, g = 1, t = T0 - 7200 }
				d.pot = 10
				Bots.saveProfile(w, 1, d)
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local Formulas = w.Formulas
			local squishies = data.squishies
			-- revenu de départ sans boost (G de la sauvegarde) et croissance sans boost
			local ctx0 = {
				decor = 0,
				friends = 0,
				fame = 0,
				trophyBonus = Formulas.trophyBonus(data.trophies),
				goldenPages = 0,
				doubleCoins = false,
				boost = false,
			}
			local K, S1 = Formulas.ranchIncome(squishies, 100, ctx0)
			local potExpected = 10 + Formulas.offlinePot(S1 + K * 100, 3600)
			local g0 = Formulas.growthRate({ R = 0, snack = 0, jellyFamily = false, boost = false })
			local biggest = 1000 + 100
			local grew = Formulas.offlineGrowth(g0, 3600, 0, biggest)
			expect(grew > 0).toBe(true)
			expect(near(data.growth.G, 100 + grew, 1e-12)).toBe(true)
			expect(near(data.pot, potExpected, 1e-9)).toBe(true)
			expect(data.growth.t).toBe(T0)
			-- un règlement juste après le chargement n'ajoute rien de l'absence
			local pot1 = data.pot
			w.Economy.settle(p)
			expect(data.pot).toBe(pot1)
			-- écran de retour (absence ≥ 10 min)
			local ret = celebrations(w, p, "return")
			expect(#ret).toBe(1)
			expect(ret[1].seconds).toBe(3600)
			expect(ret[1].uid).toBe("1") -- Meilleur Ami n° 1
			expect(near(ret[1].grew, grew, 1e-12)).toBe(true)
			expect(ret[1].nearlyReady).toBe(false)
			clean(w)
		end)

		-- règle hors ligne de la v1.3 (arrêt à 90 %, 8 h) : serveur de la v1.3 (préréglage « v13 », lot I
		-- D2 a, journal I-19 ; elle reste le chemin d'un interrupteur coupé en direct). Le chemin du
		-- lancement (N6 : arrêt à MinPlaySeconds de croissance maximale, Sac de nuit) est prouvé par
		-- Formulas › N6 et EconomyService_upgrades › « hors ligne : Sac de nuit »
		it("arrêt à 90 % de l'objectif (nearlyReady) ; 8 h au plus ; premier chargement : rien", function()
			local w = boot(function(w)
				local d = profile(w, { lastOnline = T0 - 100000 })
				d.squishies["1"].z = 13000 -- objectif R0 = 15 000 : arrêt à 13 500
				d.growth = { G = 0, g = 1, t = 0 }
				Bots.saveProfile(w, 1, d)
			end, Flags.harness(Harness, "v13"))
			local p = Bots.join(1)
			local data = w.DS.get(p)
			expect(near(data.growth.G, 500, 1e-12)).toBe(true)
			local ret = celebrations(w, p, "return")
			expect(ret[1].seconds).toBe(8 * 3600)
			expect(ret[1].nearlyReady).toBe(true)
			expect(ret[1].splorchReady).toBe(false)
			-- premier chargement (lastOnline = 0) : aucun gain, aucun écran de retour
			local q = Bots.join(2)
			local dq = w.DS.get(q)
			expect(dq.pot).toBe(0)
			expect(dq.growth.G).toBe(0)
			expect(dq.growth.t).toBe(T0)
			expect(#celebrations(w, q, "return")).toBe(0)
			clean(w)
		end)

		it(
			"départ : règlement et lastOnline dans la sauvegarde de départ (onBeforeSave release)",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, profile(w))
				end)
				local p = Bots.join(1)
				w.Clock.advance(500)
				Bots.leave(p)
				w.h:settle(5)
				local store = w.h.game.DataStoreService:GetDataStore(w.Schema.STORE_NAME)
				local saved = store:GetAsync("player_1").data
				expect(saved.lastOnline).toBe(T0 + 500)
				expect(saved.growth.t).toBe(T0 + 500)
				expect(saved.pot > 0).toBe(true)
				clean(w)
			end
		)
	end)

	describe("EconomyService › boosts, contexte, refresh", function()
		it("boosts jamais cumulés ; le personnel est en pause pendant un boost de serveur", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local g1 = data.growth.g
			w.Economy.grantPersonalBoost(p, 100)
			expect(w.Economy.boostActive(p)).toBe(true)
			expect(data.growth.g).toBe(g1 * 2)
			w.Clock.advance(10)
			w.Economy.step(w.Clock.now())
			w.Economy.setServerBoost("wobble", w.Clock.now() + 50)
			expect(data.growth.g).toBe(g1 * 2) -- jamais × 4
			expect(near(data.boosts.personalLeft, 90, 1e-9)).toBe(true)
			for _ = 1, 40 do
				w.Clock.advance(1)
				w.Economy.step(w.Clock.now())
			end
			expect(near(data.boosts.personalLeft, 90, 1e-9)).toBe(true) -- en pause
			for _ = 1, 15 do
				w.Clock.advance(1)
				w.Economy.step(w.Clock.now())
			end
			expect(w.Economy.boostActive(p)).toBe(true) -- le personnel a repris
			for _ = 1, 100 do
				w.Clock.advance(1)
				w.Economy.step(w.Clock.now())
			end
			expect(w.Economy.boostActive(p)).toBe(false)
			expect(data.boosts.personalLeft).toBe(0)
			expect(data.growth.g).toBe(g1)
			expect(w.Economy.gNoBoost(p)).toBe(g1)
			clean(w)
		end)

		it(
			"récompense en secondes de revenu : P (×2 Pièces) et B (boost) appliqués une seule fois",
			function()
				local w = boot(function(w)
					local d = profile(w)
					d.passes = { DoubleCoins = true }
					Bots.saveProfile(w, 1, d)
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.Economy.setServerBoost("squish", w.Clock.now() + 600)
				local ctx = w.Economy.incomeCtx(p)
				expect(ctx.doubleCoins).toBe(true)
				expect(ctx.boost).toBe(true)
				local plain = table.clone(ctx)
				plain.doubleCoins = false
				plain.boost = false
				local G = w.Economy.G(p)
				local K, S1 = w.Formulas.ranchIncome(data.squishies, G, plain)
				local base = S1 + K * G
				expect(near(w.Economy.income(p), base * 4, 1e-12)).toBe(true)
				local got = w.Economy.addIncomeSeconds(p, 60, "Test")
				expect(got).toBe(math.floor(60 * base * 4))
				expect(data.coins).toBe(got)
				-- minimum fixe jamais multiplié
				local q = Bots.join(2)
				expect(w.Economy.addIncomeSeconds(q, 60, "Test", 10)).toBe(10)
				clean(w)
			end
		)

		it("refresh rattrapé au tick : palier de trophée, page dorée, bonus de famille, Fame", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local function tick()
				w.Clock.advance(0.1)
				w.Economy.step(w.Clock.now())
			end
			tick()
			local trophy0 = w.Economy.incomeCtx(p).trophyBonus
			data.trophies[7] = 2e6 -- palier argent franchi pour l'espèce 7
			tick()
			expect(w.Economy.incomeCtx(p).trophyBonus > trophy0).toBe(true)
			-- page dorée : les 8 mutations hors Lunaire de l'espèce 3
			local mask = 1
			for m = 1, 9 do
				if m ~= 7 then
					mask = bit32.bor(mask, bit32.lshift(1, m))
				end
			end
			data.dex.mut[3] = mask
			tick()
			expect(w.Economy.incomeCtx(p).goldenPages).toBe(1)
			-- bonus de famille Jelly gagné pour toujours (dex.fam) : croissance + 10 %
			local g0 = data.growth.g
			data.dex.fam[1] = 1
			tick()
			expect(near(data.growth.g, g0 * 1.1, 1e-12)).toBe(true)
			-- Fame : refresh immédiat (A)
			expect(w.Economy.addFame(p, 5, "splorch")).toBe(5)
			expect(w.Economy.incomeCtx(p).fame).toBe(5)
			expect(w.Ranch.publicOf(1).fame).toBe(5)
			clean(w)
		end)

		it("amis présents (setFriendsPresent) : refresh, A plafonné à 4 amis", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w))
			end)
			local p = Bots.join(1)
			local before = w.Economy.income(p)
			w.Economy.setFriendsPresent(p, 2)
			expect(w.Economy.incomeCtx(p).friends).toBe(2)
			expect(w.Economy.income(p) > before).toBe(true)
			w.Economy.setFriendsPresent(p, 0 / 0)
			expect(w.Economy.incomeCtx(p).friends).toBe(0)
			clean(w)
		end)
	end)

	describe("EconomyService › Fame, plafonds", function()
		it(
			"Fame du Rush plafonnée à 30, relâche à 20 ; Grand Splorch et MEGA sans plafond ; entrées hostiles",
			function()
				local w = boot()
				local p = Bots.join(1)
				expect(w.Economy.addFame(p, 25, "rush")).toBe(25)
				expect(w.Economy.addFame(p, 25, "rush")).toBe(5)
				expect(w.Economy.addFame(p, 1, "rush")).toBe(0)
				expect(w.Economy.addFame(p, 30, "release")).toBe(20)
				expect(w.Economy.addFame(p, 100, "mega")).toBe(100)
				expect(w.Economy.addFame(p, 0 / 0, "mega")).toBe(0)
				expect(w.Economy.addFame(p, -5, "mega")).toBe(0)
				expect(w.Economy.addFame(p, 5, "cheat")).toBe(0)
				expect(w.DS.get(p).fame).toBe(150)
				clean(w)
			end
		)

		it(
			"consumeCap et consumeFriendCap (20 par ami) ; le changement de jour remet tout à zéro, petSitBy compris",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				expect(w.Economy.consumeCap(p, "petSit", 99)).toBe(99)
				expect(w.Economy.consumeCap(p, "petSit", 5)).toBe(1)
				expect(w.Economy.consumeCap(p, "petSit", 1)).toBe(0)
				expect(w.Economy.consumeCap(p, "unknown", 1)).toBe(0)
				expect(w.Economy.consumeCap(p, "claps", 0 / 0)).toBe(0)
				for _ = 1, 20 do
					expect(w.Economy.consumeFriendCap(p, "petSit", 42, 1)).toBe(1)
				end
				expect(w.Economy.consumeFriendCap(p, "petSit", 42, 1)).toBe(0)
				expect(w.Economy.consumeFriendCap(p, "petSit", 43, 1)).toBe(1)
				expect(w.Economy.consumeFriendCap(p, "claps", 43, 1)).toBe(0)
				expect(w.Economy.consumeFriendCap(p, "petSit", 1.5, 1)).toBe(0)
				expect(data.caps.petSitBy).toEqual({ ["42"] = 20, ["43"] = 1 })
				w.Clock.advance(86400)
				expect(w.Economy.consumeCap(p, "petSit", 1)).toBe(1)
				expect(data.caps.petSitBy).toEqual({})
				expect(data.caps.day).toBe(w.Clock.day())
				clean(w)
			end
		)
	end)

	describe("EconomyService › dalles, Pot, Grand Splorch", function()
		it(
			"BuyTile : depuis le panneau, pièces manquantes → Feedback ; sur la dalle, refus doux",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, profile(w, { coins = 50 }))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.h:fireServer("ReplicatedStorage.Remotes.BuyTile", p, "decor") -- 80 : manque 30
				local fb = w.h:sentTo(p, "Feedback")
				expect(fb[#fb][1].key).toBe("feedback.notEnoughCoins")
				expect(fb[#fb][1].vars.missing).toBe(30)
				-- sur la dalle : même achat refusé sans Feedback
				local n = #w.h:sentTo(p, "Feedback")
				expect(w.Economy.buyTile(p, "decor", "pad")).toBe(false)
				expect(#w.h:sentTo(p, "Feedback")).toBe(n)
				-- succès : niveau, bit seen, prix × 3,5^R pour la boucle, Celebrate « tile », TileBought
				local bought = {}
				w.Signals.TileBought:Connect(function(_, tile, level)
					table.insert(bought, { tile, level })
				end)
				expect(w.Economy.buyTile(p, "snack", "panel")).toBe(true)
				w.h:settle(1)
				expect(data.tiles.snack).toBe(1)
				expect(data.coins).toBe(30)
				expect(bit32.band(data.tiles.seen, 1)).toBe(1)
				expect(bought[1]).toEqual({ "snack", 1 })
				expect(celebrations(w, p, "tile")[1]).toEqual({ tile = "snack", level = 1 })
				expect(w.Ranch.publicOf(1).tiles.snack).toBe(1)
				-- dalle inconnue, Lit douillet avant R = 3 : refus
				expect(w.Economy.buyTile(p, "rocket", "panel")).toBe(false)
				data.coins = 1e9
				expect(w.Economy.buyTile(p, "cozyBed", "panel")).toBe(false)
				clean(w)
			end
		)

		it("prix des dalles de la boucle × 3,5^R ; Enclos jamais multiplié", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w, { coins = 1e6, R = 2 }))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			w.Economy.buyTile(p, "snack", "panel")
			expect(data.coins).toBe(1e6 - math.floor(20 * 3.5 ^ 2))
			local c = data.coins
			w.Economy.buyTile(p, "pens", "panel")
			expect(data.coins).toBe(c - 1200)
			clean(w)
		end)

		it("Pot : encaissé entier (la fraction reste), PotCollected et Celebrate « pot »", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			w.Clock.advance(30)
			local got = {}
			w.Signals.PotCollected:Connect(function(_, amount, auto)
				table.insert(got, { amount, auto })
			end)
			w.Economy.settle(p)
			local pot = data.pot
			local amount = w.Economy.collectPot(p, false)
			w.h:settle(1)
			expect(amount).toBe(math.floor(pot))
			expect(data.coins).toBe(amount)
			expect(near(data.pot, pot - amount, 1e-9)).toBe(true)
			expect(got[1]).toEqual({ amount, false })
			expect(celebrations(w, p, "pot")[1]).toEqual({ coins = amount, auto = false })
			-- Pot vide : rien
			expect(w.Economy.collectPot(p, false)).toBe(0)
			clean(w)
		end)

		it("Pot automatique (pass) toutes les 5 s dans step", function()
			local w = boot(function(w)
				local d = profile(w)
				d.passes = { AutoPot = true }
				Bots.saveProfile(w, 1, d)
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			for _ = 1, 60 do
				w.Clock.advance(0.1)
				w.Economy.step(w.Clock.now())
			end
			expect(data.coins > 0).toBe(true)
			expect(data.pot < 1e9).toBe(true)
			clean(w)
		end)

		it(
			"Grand Splorch d'un bloc : pièces + Pot perdus, Tapis et décorations à 0, R + 1, Fame + 5, G = 0",
			function()
				local w = boot(function(w)
					local d = profile(w, { coins = 500, pot = 20.5, R = 1, fame = 3 })
					d.tiles = { snack = 4, decor = 2, pens = 3, cozyBed = false, seen = 15 }
					d.growth = { G = 50, g = 1, t = 0 }
					Bots.saveProfile(w, 1, d)
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local pot = data.pot
				local lost = w.Economy.applySplorch(p)
				expect(lost).toBe(math.floor(500 + pot))
				expect(data.coins).toBe(0)
				expect(data.pot).toBe(0)
				expect(data.tiles.snack).toBe(0)
				expect(data.tiles.decor).toBe(0)
				expect(data.tiles.pens).toBe(3)
				expect(data.R).toBe(2)
				expect(data.fame).toBe(8)
				expect(data.growth.G).toBe(0)
				expect(data.growth.t).toBe(T0)
				expect(data.growth.g).toBe(4) -- 2^R, Tapis 0
				expect(w.Ranch.publicOf(1).R).toBe(2)
				clean(w)
			end
		)

		it("joueur non chargé : toutes les fonctions sûres (aucune erreur)", function()
			local w = boot()
			local p = Bots.join(1, { wait = false })
			local ghost = w.h:addPlayer({ userId = 999, spawn = false })
			w.DS.get = function()
				return nil
			end
			expect(w.Economy.coins(ghost)).toBe(0)
			expect(w.Economy.addCoins(ghost, 10, "Test")).toBe(0)
			expect(w.Economy.trySpend(ghost, 10, "Test")).toBe(false)
			expect(w.Economy.income(ghost)).toBe(0)
			expect(w.Economy.buyTile(ghost, "snack", "panel")).toBe(false)
			expect(w.Economy.collectPot(ghost, true)).toBe(0)
			expect(w.Economy.applySplorch(ghost)).toBe(0)
			expect(w.Economy.consumeCap(ghost, "petSit", 1)).toBe(0)
			expect(w.Economy.gNoBoost(ghost)).toBe(0)
			w.Economy.settle(ghost)
			w.Economy.refresh(ghost)
			w.Economy.grantPersonalBoost(ghost, 10)
			local _ = p
			clean(w)
		end)
	end)
end
