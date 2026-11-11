--!nocheck
-- Formulas (paquet logic, docs/04 §12.1, GDD §4) : valeurs exactes du GDD.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- interrupteurs v2.0 coupés au départ (préréglage « cut » : SchemaV2 seul ; lot I, étape 2, D2 a,
	-- journal I-19) : chaque cas ouvre lui-même ce qu'il prouve (Features.set) ; le chemin du lancement
	-- est couvert par EconomyPacing, Boot et Soak
	local h = Harness.new({ flags = "cut" })
	local F = h:require("ReplicatedStorage.Shared.Logic.Formulas")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")

	local NO_BONUS = {
		decor = 0,
		friends = 0,
		fame = 0,
		trophyBonus = 0,
		goldenPages = 0,
		doubleCoins = false,
		boost = false,
	}
	local function rec(s, m, st, z, zg, at, extra)
		local r =
			{ s = s, m = m, st = st, z = z, zg = zg, bf = 0, lk = false, o = "", at = at or "pen", b = 1000 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	describe("Formulas › bornes", function()
		it("clampCoins : NaN, ±inf, négatif → 0 ; entier sous 1e15 ; Max au-delà", function()
			expect(F.clampCoins(0 / 0)).toBe(0)
			expect(F.clampCoins(math.huge)).toBe(0)
			expect(F.clampCoins(-math.huge)).toBe(0)
			expect(F.clampCoins(-5)).toBe(0)
			expect(F.clampCoins(12.9)).toBe(12)
			expect(F.clampCoins(2e15 + 0.5)).toBe(2e15 + 0.5)
			expect(F.clampCoins(1e305)).toBe(1e300)
			expect(F.clampCoins(nil)).toBe(0)
		end)

		it("clampSize : [1 ; 1e300], NaN → 1", function()
			expect(F.clampSize(0 / 0)).toBe(1)
			expect(F.clampSize(0)).toBe(1)
			expect(F.clampSize(math.huge)).toBe(1e300)
			expect(F.clampSize(171.25)).toBe(171.25)
		end)
	end)

	describe("Formulas › croissance et revenu (GDD §4.3)", function()
		it("Plop Commun de taille 1 000, 1 étoile, sans bonus = 30 pièces/s", function()
			expect(F.income(1000, 1, 0, 1, NO_BONUS)).toBeNear(30, 1e-9)
		end)

		it("multiplicateurs : rareté, mutation, étoiles, A, P, B", function()
			-- Wibble (Peu commun ×3), Doré ×5, 2 étoiles (×2), taille 10
			expect(F.income(10, 2, 4, 2, NO_BONUS)).toBeNear(0.02 * 3 * 10 * 5 * 2, 1e-9)
			local ctx = table.clone(NO_BONUS)
			ctx.decor = 18
			ctx.friends = 10 -- plafonné à 4
			ctx.fame = 500 -- plafonné à 300
			ctx.trophyBonus = 0.5
			ctx.goldenPages = 3
			expect(F.A(ctx)).toBeNear(1 + 0.9 + 0.4 + 3 + 0.5 + 0.03, 1e-9)
			ctx.doubleCoins = true
			ctx.boost = true
			expect(F.incomeFactor(1, 0, 0, ctx)).toBeNear(0.02 * F.A(ctx) * 2 * 2, 1e-9)
			-- espèce inconnue : aucun revenu
			expect(F.income(1000, 999, 0, 0, NO_BONUS)).toBe(0)
		end)

		it("croissance : 1 × 2^R × (1 + Tapis) × (1 + 10 % Jelly) × B", function()
			expect(F.growthRate({ R = 0, snack = 0, jellyFamily = false, boost = false })).toBe(1)
			expect(F.growthRate({ R = 0, snack = 1, jellyFamily = false, boost = false })).toBe(2)
			expect(F.growthRate({ R = 3, snack = 12, jellyFamily = true, boost = true })).toBeNear(
				8 * 13 * 1.1 * 2,
				1e-9
			)
			-- le boost ne se cumule jamais : un seul ×2
			expect(F.growthRate({ R = 0, snack = 0, jellyFamily = false, boost = true })).toBe(2)
		end)

		it("G(t) et taille : z + (G − zg) en enclos ou Bassin, z figé au Dodo et aux Lettres", function()
			local growth = { G = 100, g = 2, t = 50 }
			expect(F.G(growth, 60)).toBe(120)
			expect(F.G(growth, 40)).toBe(100) -- avant growth.t
			expect(F.G(growth, 0 / 0)).toBe(100)
			expect(F.sizeAt(rec(1, 0, 0, 10, 40, "pen"), 120)).toBe(90)
			expect(F.sizeAt(rec(1, 0, 0, 10, 40, "pool"), 120)).toBe(90)
			expect(F.sizeAt(rec(1, 0, 0, 10, 40, "dodo"), 120)).toBe(10)
			expect(F.sizeAt(rec(1, 0, 0, 10, 40, "mail"), 120)).toBe(10)
		end)

		it("ranchIncome : (K, S1) sur l'enclos et le Bassin, revenu(t) = S1 + K × G(t)", function()
			local squishies = {
				a = rec(1, 0, 1, 10, 0, "pen"),
				b = rec(2, 0, 0, 5, 20, "pool"),
				c = rec(1, 0, 0, 1000, 0, "dodo"),
				d = rec(1, 0, 0, 1000, 0, "mail"),
			}
			local K, S1 = F.ranchIncome(squishies, 30, NO_BONUS)
			local ka = 0.02 * 1 * 1.5
			local kb = 0.02 * 3
			expect(K).toBeNear(ka + kb, 1e-12)
			expect(S1).toBeNear(ka * 10 + kb * (5 - 20), 1e-12)
			local G = 30
			local total = F.income(F.sizeAt(squishies.a, G), 1, 0, 1, NO_BONUS)
				+ F.income(F.sizeAt(squishies.b, G), 2, 0, 0, NO_BONUS)
			expect(S1 + K * G).toBeNear(total, 1e-9)
		end)

		it("potGain : intégrale exacte S1 Δ + K (G(t0) Δ + ½ g Δ²)", function()
			local growth = { G = 10, g = 2, t = 0 }
			-- revenu(t) = 1 + 0,5 × G(t) ; ∫₀¹⁰ = 10 + 0,5 × (10 × 10 + ½ × 2 × 100) = 10 + 100 = 110
			expect(F.potGain(0.5, 1, growth, 0, 10)).toBeNear(110, 1e-9)
			-- intervalle vide ou inversé : 0
			expect(F.potGain(0.5, 1, growth, 10, 10)).toBe(0)
			expect(F.potGain(0.5, 1, growth, 10, 5)).toBe(0)
			-- avant growth.t, G reste à growth.G
			expect(F.potGain(1, 0, { G = 5, g = 1, t = 10 }, 0, 10)).toBeNear(50, 1e-9)
		end)

		it("potGain : [t0 ; t2] = [t0 ; t1] + [t1 ; t2] (et N règlements = 1)", function()
			local growth = { G = 3, g = 7, t = 100 }
			local K, S1 = 0.37, 12.5
			local whole = F.potGain(K, S1, growth, 100, 400)
			local sum = 0
			local t = 100
			for _ = 1, 30 do
				sum += F.potGain(K, S1, growth, t, t + 10)
				t += 10
			end
			expect(math.abs(sum - whole) / whole < 1e-9).toBe(true)
		end)
	end)

	describe("Formulas › presser, dalles, places, Cuve", function()
		it("première pression = 10 (minimum) ; PERFECT, série, Kitty", function()
			-- Balance.Press.Seconds = 22 (réglage logic de la porte EconomyPacing v1.2, docs/04 §21)
			expect(Balance.Press.Seconds).toBe(22)
			expect(F.pressReward(0.2, false, 0, false)).toBe(10)
			expect(F.pressReward(10, false, 0, false)).toBe(220)
			expect(F.pressReward(10, true, 0, false)).toBe(440)
			expect(F.pressReward(10, true, 5, false)).toBe(660)
			expect(F.pressReward(10, true, 9, false)).toBe(660) -- série plafonnée à 5
			expect(F.pressReward(10, false, 0, true)).toBe(242)
			expect(F.pressReward(0 / 0, true, 0 / 0, true)).toBe(22) -- minimum × 2 × 1,1
		end)

		it("coûts des dalles du GDD §4.6 (R = 0, puis × 3,5^R pour la boucle)", function()
			-- Tapis : croissance 4,5 (GDD : 4,0), réglage logic de la porte EconomyPacing v1.2 (docs/04 §21)
			expect(Balance.Tiles.snack.Growth).toBe(4.5)
			local snack =
				{ 20, 90, 405, 1822, 8201, 36905, 166075, 747338, 3363025, 15133612, 68101257, 306455660 }
			for level, cost in snack do
				expect(F.tileCost("snack", level - 1, 0)).toBe(cost)
			end
			local decor = { 80, 176, 387, 851, 1874, 4122, 9070, 19954, 43900, 96581, 212479, 467454 }
			for level, cost in decor do
				expect(F.tileCost("decor", level - 1, 0)).toBe(cost)
			end
			local pens = { 1200, 2640, 5808, 12777, 28110, 61843, 136055, 299322, 658510 }
			for level, cost in pens do
				expect(F.tileCost("pens", level - 1, 0)).toBe(cost)
			end
			-- contrat v1.2 (GDD v1.3 §4.6) : × Tiles.RScale^R (3,5) pour les dalles de la boucle
			expect(F.tileCost("snack", 0, 1)).toBe(70)
			expect(F.tileCost("snack", 0, 2)).toBe(245)
			expect(F.tileCost("snack", 1, 1)).toBe(315) -- 20 × 4,5 × 3,5
			expect(F.tileCost("decor", 2, 3)).toBe(math.floor(80 * 2.2 ^ 2 * 3.5 ^ 3))
			expect(F.tileCost("pens", 0, 5)).toBe(1200) -- les places ne suivent pas R
			expect(F.tileCost("cozyBed", 0, 3)).toBe(25e6) -- jamais multiplié
			expect(F.tileCost("cozyBed", 0, 10)).toBe(25e6)
			-- Tiles porte aussi des nombres (DwellSeconds, RScale, rayons) : ce ne sont pas des dalles
			expect(F.tileCost("RScale", 0, 0)).toBe(math.huge)
			expect(F.tileCost("DwellSeconds", 0, 0)).toBe(math.huge)
			expect(F.tileCost("EnterRadius", 0, 0)).toBe(math.huge)
			expect(F.tileCost("snack", 12, 0)).toBe(math.huge)
			expect(F.tileCost("cozyBed", 1, 0)).toBe(math.huge)
			expect(F.tileCost("rocket", 0, 0)).toBe(math.huge)
			expect(F.tileCost(nil, 0, 0)).toBe(math.huge)
		end)

		it("places d'enclos 4 → 18, 24 avec le Grand Ranch ; Bassin 5 ou 6", function()
			expect(F.penCapacity(0, false)).toBe(4)
			expect(F.penCapacity(14, false)).toBe(18)
			expect(F.penCapacity(14, true)).toBe(24)
			expect(F.penCapacity(99, true)).toBe(24)
			expect(F.penCapacity(0 / 0, false)).toBe(4)
			expect(F.poolSlots(false)).toBe(5)
			expect(F.poolSlots(true)).toBe(6)
		end)

		it("Cuve : niveaux et intervalles du GDD §4.9 (55,3 s à R = 0, 17,7 s dès R = 4)", function()
			local intervals = { 55.3, 39.9, 28.9, 20.8, 17.7, 17.7, 17.7, 17.7 }
			for R, interval in intervals do
				expect(math.floor(F.vatInterval(R - 1, false) * 10 + 0.5) / 10).toBe(interval)
			end
			expect(F.vatInterval(0, true)).toBeNear(F.vatInterval(0, false) * 0.9, 1e-9)
			local lvl = F.vatLevel(0)
			expect(lvl).toEqual({ quality = 1, speed = 3, nozzles = 0 })
			expect(F.vatLevel(7)).toEqual({ quality = 8, speed = 10, nozzles = 5 })
			expect(F.vatLevel(100)).toEqual({ quality = 8, speed = 10, nozzles = 5 })
		end)
	end)

	describe("Formulas › fusion, vente, récompenses", function()
		it("fusion : (a + b) × 1,25 ; étoiles + 1 (5 au plus) ; meilleure mutation", function()
			expect(F.fusionSize(96, 41)).toBeNear(171.25, 1e-9)
			expect(F.fusionStars(0)).toBe(1)
			expect(F.fusionStars(5)).toBe(5)
			expect(F.bestMutation(0, 0)).toBe(0)
			expect(F.bestMutation(1, 0)).toBe(1)
			expect(F.bestMutation(4, 9)).toBe(9)
			expect(F.bestMutation(7, 6)).toBe(7) -- Lunaire ×20 > Arc-en-ciel ×12
			expect(F.bestMutation(42, 3)).toBe(3) -- inconnue ignorée
		end)

		it("combo k : 20 × k × revenu ; vente : 60 s (10 au moins)", function()
			expect(F.comboReward(3, 2)).toBe(120)
			expect(F.sellValue(0.01)).toBe(10)
			expect(F.sellValue(5)).toBe(300)
			expect(F.secondsOfIncome(2.5, 60)).toBe(150)
			expect(F.secondsOfIncome(0.001, 60, 10)).toBe(10)
		end)

		it("objectifs du Grand Splorch : table v1.3, puis × 2,6 arrondi à 2 chiffres", function()
			expect(F.splorchTarget(0)).toBe(15000)
			expect(F.splorchTarget(1)).toBe(39000)
			expect(F.splorchTarget(19)).toBe(1.1e12)
			expect(F.splorchTarget(20)).toBe(2.9e12) -- 1,1e12 × 2,6 = 2,86e12 → 2,9e12
			expect(F.splorchTarget(21)).toBe(7.5e12) -- 2,9e12 × 2,6 = 7,54e12 → 7,5e12
			expect(F.splorchTarget(5000)).toBe(1e300)
			expect(F.splorchTarget(0 / 0)).toBe(15000)
			for R = 1, 100 do
				expect(F.splorchTarget(R) > F.splorchTarget(R - 1) or F.splorchTarget(R) == 1e300).toBe(true)
			end
		end)

		it(
			"hors ligne : 0 au premier chargement, plafond 8 h / 12 h (+ 1 h Spiky), parts 30 % et 25 %",
			function()
				expect(F.offlineSeconds(1000, 0, false, false)).toBe(0)
				expect(F.offlineSeconds(1000, 400, false, false)).toBe(600)
				expect(F.offlineSeconds(1e6, 1, false, false)).toBe(8 * 3600)
				expect(F.offlineSeconds(1e6, 1, true, false)).toBe(12 * 3600)
				expect(F.offlineSeconds(1e6, 1, true, true)).toBe(13 * 3600)
				expect(F.offlineSeconds(1000, 2000, false, false)).toBe(0) -- horloge en arrière
				expect(F.offlineGrowth(4, 100)).toBe(120) -- sans R ni plus gros : pas d'arrêt
				expect(F.offlinePot(2, 100)).toBe(50)
			end
		)

		it(
			"hors ligne (contrat v1.2) : la croissance s'arrête à StopAt (90 %) de l'objectif de R",
			function()
				-- R = 0 : objectif 15 000, arrêt à 13 500
				expect(F.offlineGrowth(4, 100, 0, 1000)).toBe(120) -- loin de l'arrêt
				expect(F.offlineGrowth(100, 1000, 0, 13000)).toBe(500) -- 30 000 bornés à 13 500 − 13 000
				expect(F.offlineGrowth(100, 1000, 0, 13500)).toBe(0) -- déjà à 90 %
				expect(F.offlineGrowth(100, 1000, 0, 20000)).toBe(0) -- déjà prêt en jeu : rien ne grandit
				expect(F.offlineGrowth(1e9, 1e6, 19, 0)).toBeNear(0.9 * 1.1e12, 1) -- R = 19
				expect(F.offlineGrowth(100, 1000, 0)).toBe(30000) -- plus gros inconnu : pas d'arrêt
				expect(F.offlineGrowth(100, 1000, nil, 13000)).toBe(30000)
				-- entrées bizarres : jamais NaN ni négatif
				expect(F.offlineGrowth(100, 1000, 0 / 0, 13000)).toBe(500) -- R illisible → 0
				expect(F.offlineGrowth(100, 1000, 0, 0 / 0)).toBe(13500) -- plus gros illisible → 0
				expect(F.offlineGrowth(100, 1000, 0, math.huge)).toBe(0)
				expect(F.offlineGrowth(0 / 0, 1000, 0, 0)).toBe(0)
			end
		)

		it("bébés : part, minimum, et jamais plus de 0,5 × le plus gros du receveur (GDD v1.3)", function()
			-- démonstration : 10 % du Plop, minimum 10
			expect(F.babySize(0.1, 10, 50)).toBe(10)
			expect(F.babySize(0.1, 10, 1000)).toBe(100)
			-- bébé du Rush : 10 % de l'original 1e9, receveur de 100 → 0,5 × 100 = 50
			expect(F.babySize(0.1, 1, 100, 1e9)).toBe(50)
			-- MEGA : 20 % du plus gros, déjà sous 0,5 ×
			expect(F.babySize(0.2, 10, 1e6)).toBe(2e5)
			-- part plus grande que 0,5 : bornée
			expect(F.babySize(0.9, 1, 1000)).toBe(500)
			-- le minimum passe en dernier (un nouveau reçoit quand même son minimum)
			expect(F.babySize(0.2, 10, 1)).toBe(10)
			expect(F.babySize(0.1, 1, 0 / 0, 0 / 0)).toBe(1)
		end)

		it("selles (1 200, 1e6, 1e12) et monture (WalkSpeed 22,4, sauts, HipHeight)", function()
			expect(F.saddleLevel(1199)).toBe(0)
			expect(F.saddleLevel(1200)).toBe(1)
			expect(F.saddleLevel(1e6)).toBe(2)
			expect(F.saddleLevel(1e12)).toBe(3)
			local base = F.rideStats(0)
			expect(base).toEqual({ walkSpeed = 16, jumpHeight = 7.2, hipHeight = 2, scale = 1 })
			local small = F.rideStats(1)
			expect(small.walkSpeed).toBeNear(22.4, 1e-9)
			expect(small.jumpHeight).toBe(8.6)
			expect(small.hipHeight - Balance.Ride.BaseHipHeight).toBeNear(4.275, 1e-9) -- « +4,3 »
			expect(F.rideStats(2).hipHeight - 2).toBeNear(5.25, 1e-9)
			expect(F.rideStats(3).hipHeight - 2).toBeNear(6, 1e-9)
		end)

		it("Étagère : paliers et bonus (+208 % au plus)", function()
			expect(F.trophyTier(999)).toBe(0)
			expect(F.trophyTier(1000)).toBe(1)
			expect(F.trophyTier(1e12)).toBe(4)
			local all = table.create(26, 1e12)
			expect(F.trophyBonus(all)).toBeNear(2.08, 1e-9)
			expect(F.trophyBonus({ 1e3, 1e6, 0 / 0 })).toBeNear(0.06, 1e-9)
			expect(F.trophyBonus(nil)).toBe(0)
		end)

		it("paquets de pièces retirés du lancement (contrat v1.2) : coinPack ne rend plus rien", function()
			-- Balance.CoinPacks est retiré ; la fonction reste seulement tant que Contract_game la liste
			expect(Balance.CoinPacks).toBeNil()
			expect(F.coinPack(0, "CoinsSmall")).toBe(0)
			expect(F.coinPack(10, "CoinsSmall")).toBe(0)
			expect(F.coinPack(10, "CoinsBig")).toBe(0)
			expect(F.coinPack(10, "Nope")).toBe(0)
			expect(F.coinPack(0 / 0, nil)).toBe(0)
		end)
	end)

	describe("Formulas › aperçu du Grand Splorch", function()
		it(
			"prêt, objectif, envol par défaut (pas un Meilleur Ami), pièces perdues, plus de 2e confirmation",
			function()
				local data = {
					R = 0,
					coins = 1200,
					pot = 300.7,
					growth = { G = 20000, g = 1, t = 100 },
					squishies = {
						["1"] = rec(1, 0, 0, 1, 0, "pen", { bf = 1 }),
						["2"] = rec(5, 0, 0, 1, 5000, "pen"),
						["3"] = rec(9, 0, 0, 1, 19000, "pool"),
						["4"] = rec(1, 0, 0, 1e9, 0, "dodo"),
					},
					coinBuy = { at = 1000, amount = 2000 },
				}
				local p = F.splorchPreview(data, { now = 100, unix = 1500 })
				expect(p.ready).toBe(true)
				expect(p.target).toBe(15000)
				expect(p.biggest).toBe(20001) -- le Dodo ne compte pas
				expect(p.level).toBe(1)
				expect(p.unlocks).toEqual({ "family.axolo" }) -- Lit douillet à R = 3 (GDD v1.3)
				expect(p.coinsLost).toBe(1500)
				-- contrat v1.2 : paquets retirés, plus de 2e confirmation ; un vieux coinBuy est ignoré
				expect(p.recentBuy).toBeNil()
				expect(p.nextTarget).toBe(39000)
				expect(p.defaultFlyer).toBe("2") -- le Meilleur Ami n° 1 reste
				data.R = 2
				expect(F.splorchPreview(data, { now = 100, unix = 1500 }).unlocks).toEqual({
					"family.bunny",
					"bestFriend.2",
					"pad.cozyBed",
				})
			end
		)

		it("profil vide ou abîmé : aperçu sûr", function()
			local p = F.splorchPreview({}, { now = 0, unix = 0 })
			expect(p.ready).toBe(false)
			expect(p.biggest).toBe(0)
			expect(p.defaultFlyer).toBe("")
			local q = F.splorchPreview(nil, nil)
			expect(q.target).toBe(15000)
		end)

		it("tous Meilleurs Amis : le plus gros s'envole", function()
			local data = {
				R = 1,
				coins = 0,
				pot = 0,
				growth = { G = 0, g = 1, t = 0 },
				squishies = {
					a = rec(1, 0, 0, 50, 0, "pen", { bf = 1 }),
					b = rec(2, 0, 0, 70, 0, "pen", { bf = 2 }),
				},
			}
			expect(F.splorchPreview(data, { now = 0, unix = 0 }).defaultFlyer).toBe("b")
		end)
	end)

	-- -----------------------------------------------------------------------------------------
	-- GDD v2.0 (paquet A1, docs/04 §27.13 N2-N6) : chaque terme derrière son interrupteur
	-- -----------------------------------------------------------------------------------------
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local UpgradeMath = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local V2_FLAGS =
		{ "JellyAscend", "StarMat", "UpgradesScreen", "Monuments", "Gloves", "Workshop", "RecordR" }

	-- Ouvre des interrupteurs le temps de fn ; remet TOUJOURS les valeurs de lancement (même sur échec)
	local function withFlags(names, fn)
		for _, name in names do
			assert(Features.set(name, true), name)
		end
		local okRun, err = pcall(fn)
		Features.reset()
		if not okRun then
			error(err, 0)
		end
	end

	describe("Formulas › v2.0, interrupteurs coupés : exactement la v1.3", function()
		it("chaque interrupteur v2.0 est coupé au lancement de ces specs", function()
			for _, name in V2_FLAGS do
				expect({ flag = name, on = Features.get(name) }).toEqual({ flag = name, on = false })
			end
		end)

		it(
			"les champs v2.0 du contexte ne changent rien (croissance, revenu, pression, hors ligne, prix)",
			function()
				local base = { R = 3, snack = 12, jellyFamily = true, boost = true }
				local v2 =
					{ R = 3, snack = 12, jellyFamily = true, boost = true, A = 5, bestR = 20, star = 8 }
				v2.firstRecordLoop = true
				expect(F.growthRate(v2)).toBe(F.growthRate(base))
				expect(F.growthRate(v2)).toBe(8 * 13 * 1.1 * 2)
				local ctx = table.clone(NO_BONUS)
				ctx.monuments = 10
				expect(F.income(1000, 1, 0, 1, ctx)).toBe(F.income(1000, 1, 0, 1, NO_BONUS))
				expect(F.pressReward(10, true, 7, false, 40, 2)).toBe(660) -- série 5 au plus, sans Gants
				expect(F.streakMax(2)).toBe(5)
				expect(F.glovesMult(40)).toBe(1)
				expect(F.monumentMult(10)).toBe(1)
				expect(F.offlineSeconds(1e6, 1, true, true, 3)).toBe(13 * 3600)
				expect(F.offlinePot(2, 100, 2)).toBe(50)
				expect(F.offlinePotShare(2)).toBe(0.25)
				expect(F.offlineGrowth(100, 1000, 0, 1000, 50)).toBe(12500) -- 90 % seulement
				-- prix : formule de la v1.3 (le seul cas d'une pièce d'écart avec UpgradeMath, décoration 10 à r = 17)
				expect(F.tileCost("decor", 9, 17, 3)).toBe(171415807285087)
				expect(F.tileCost("snack", 0, 0, 1)).toBe(20)
				-- croissance maximale de la boucle sans Tapis Étoilé ni Ascension : Tapis 12 et ×2
				expect(F.maxGrowthRate({ R = 10, snack = 0, jellyFamily = false, boost = false })).toBe(
					1024 * 13 * 2
				)
			end
		)
	end)

	describe("Formulas › v2.0, interrupteurs ouverts (N2-N6)", function()
		it(
			"N2 croissance × 3^A × Souvenir de gelée (×3, ×2, ×1,5, ×1,25 sur la 1re boucle record) [JellyAscend]",
			function()
				withFlags({ "JellyAscend" }, function()
					local function g(R, A, bestR, first)
						return F.growthRate({
							R = R,
							snack = 0,
							jellyFamily = false,
							boost = false,
							A = A,
							bestR = bestR,
							firstRecordLoop = first,
						})
					end
					expect(g(15, 0, 15, false)).toBe(32768) -- sans Ascension : la v1.3
					expect(g(15, 1, 15, false)).toBe(32768 * 3)
					expect(g(15, 2, 20, false)).toBe(32768 * 9 * 3) -- écart 5 : Souvenir ×3
					-- après la 1re Ascension (record 15) : ×9 jusqu'à r = 12, puis ×6, ×4,5, ×3,75, ×3
					expect(g(0, 1, 15, false)).toBe(9)
					expect(g(0, 1, 15, false) / g(0, 0, 0, false)).toBe(Prestige.regainSpeedup())
					expect(g(12, 1, 15, false)).toBe(4096 * 9)
					expect(g(13, 1, 15, false)).toBe(8192 * 6)
					expect(g(14, 1, 15, false)).toBe(16384 * 4.5)
					expect(g(15, 1, 15, true)).toBe(32768 * 3.75)
					expect(g(16, 1, 16, false)).toBe(65536 * 3)
					-- 1re boucle record sans Ascension : jamais ×1,25 ; Record R absent : aucun Souvenir
					expect(g(15, 0, 15, true)).toBe(32768)
					expect(F.growthRate({ R = 5, snack = 0, jellyFamily = false, boost = false, A = 2 })).toBe(
						32 * 9
					)
					-- A illisible ou hors bornes : 0 … 60 ; Record R sous r (abîmé) : aucun Souvenir
					expect(g(0, 0 / 0, 0, false)).toBe(1)
					expect(g(0, -3, 0, false)).toBe(1)
					expect(g(4, 1, 2, false)).toBe(16 * 3)
					-- A = 60 : 3^60 × 2^r reste fini et borné
					local huge = g(400, 60, 400, false)
					expect(huge == huge and huge <= 1e300 and huge > 0).toBe(true)
				end)
			end
		)

		it(
			"N2 Tapis Étoilé : niveaux 13-20 au-dessus du Tapis 12, plafonnés par r (×14 … ×21) [StarMat]",
			function()
				withFlags({ "StarMat" }, function()
					local function g(R, snack, star)
						return F.growthRate({
							R = R,
							snack = snack,
							jellyFamily = false,
							boost = false,
							star = star,
						})
					end
					expect(g(10, 12, 8)).toBe(1024 * 21) -- croissance ×21 (GDD §4.6.1)
					expect(g(10, 12, 3)).toBe(1024 * 16)
					expect(g(6, 12, 3)).toBe(64 * 14) -- plafond de r = 6 : un niveau
					expect(g(9, 12, 8)).toBe(512 * 17) -- plafond de r = 9 : 4 niveaux
					expect(g(5, 12, 8)).toBe(32 * 13) -- avant r = 6 : rien
					expect(g(10, 11, 8)).toBe(1024 * 12) -- seulement après le Tapis 12
					expect(g(10, 12, 99)).toBe(1024 * 21)
					expect(g(10, 12, 0 / 0)).toBe(1024 * 13)
					-- croissance maximale de la boucle : Tapis et Tapis Étoilé au plafond de r, boost ×2
					local ctx = { R = 10, snack = 0, jellyFamily = true, boost = false }
					expect(F.maxGrowthRate(ctx)).toBeNear(1024 * 21 * 1.1 * 2, 1e-9)
					expect(F.maxGrowthRate({ R = 7, snack = 3, jellyFamily = false, boost = false })).toBe(
						128 * 15 * 2
					)
				end)
			end
		)

		it(
			"N3 prix des dalles = UpgradeMath.price (× F(A) = ×0,5 par Ascension, puis ×0,32) [JellyAscend, UpgradesScreen]",
			function()
				withFlags({ "UpgradesScreen" }, function()
					-- le seul cas d'une pièce d'écart sous 1e15 : la dalle montre le prix de l'écran
					expect(F.tileCost("decor", 9, 17)).toBe(171415807285086)
					expect(F.tileCost("decor", 9, 17)).toBe(UpgradeMath.price("decor", 9, 17, 0, 17))
					-- A ignoré tant que la Jelly Ascend est coupée
					expect(F.tileCost("snack", 11, 0, 3)).toBe(306455660)
					expect(F.tileCost("pens", 0, 5)).toBe(1200)
					expect(F.tileCost("cozyBed", 0, 10)).toBe(25e6)
					expect(F.tileCost("snack", 12, 0)).toBe(math.huge)
					expect(F.tileCost("RScale", 0, 0)).toBe(math.huge)
					expect(F.tileCost("gloves", 0, 0)).toBe(math.huge) -- famille sans dalle
					expect(F.tileCost("snack", -1, 0)).toBe(math.huge) -- niveau qui n'existe pas
				end)
				withFlags({ "JellyAscend" }, function()
					expect(F.tileCost("snack", 0, 0, 1)).toBe(10)
					expect(F.tileCost("snack", 11, 0, 1)).toBe(153227830)
					expect(F.tileCost("snack", 0, 4, 4)).toBe(math.floor(20 * 3.5 ^ 4 * 0.5 ^ 4))
					expect(F.tileCost("snack", 0, 0, 5)).toBe(1) -- au moins 1 pièce (C13)
					expect(F.tileCost("pens", 3, 9, 7)).toBe(12777) -- l'Enclos ne suit ni r ni A
					expect(F.tileCost("cozyBed", 0, 9, 7)).toBe(25e6)
					for _, tile in { "snack", "decor", "pens", "cozyBed" } do
						for _, rA in { { 0, 0 }, { 3, 1 }, { 17, 0 }, { 25, 6 } } do
							expect(F.tileCost(tile, 0, rA[1], rA[2])).toBe(
								UpgradeMath.price(tile, 0, rA[1], rA[2], rA[1])
							)
						end
					end
				end)
			end
		)

		it("N4 revenu × (1 + 0,01 × Monuments), multiplicateur à part de A_bonus [Monuments]", function()
			withFlags({ "Monuments" }, function()
				local ctx = table.clone(NO_BONUS)
				ctx.monuments = 10
				expect(F.income(1000, 1, 0, 1, ctx)).toBeNear(33, 1e-9) -- 30 × 1,10
				expect(F.monumentMult(10)).toBeNear(1.1, 1e-12)
				expect(F.monumentMult(1)).toBeNear(1.01, 1e-12)
				expect(F.monumentMult(99)).toBeNear(1.1, 1e-12) -- 10 au plus
				expect(F.monumentMult(0 / 0)).toBe(1)
				ctx.decor = 18 -- A_bonus 1,9 : × 1,9 × 1,1, jamais 1 + 0,9 + 0,1
				expect(F.income(1000, 1, 0, 1, ctx)).toBeNear(30 * 1.9 * 1.1, 1e-9)
				local squishies = { a = rec(1, 0, 1, 10, 0, "pen") }
				local K = F.ranchIncome(squishies, 0, ctx)
				local K0 = F.ranchIncome(
					squishies,
					0,
					{ decor = 18, friends = 0, fame = 0, trophyBonus = 0, goldenPages = 0 }
				)
				expect(K / K0).toBeNear(1.1, 1e-12)
				-- sans le champ : aucun Monument
				expect(F.income(1000, 1, 0, 1, NO_BONUS)).toBeNear(30, 1e-9)
			end)
		end)

		it(
			"N5 pression × Gants (×1,025 … ×2,000, GDD §4.6.1) et série jusqu'à 5 + Super Série [Gloves, Workshop]",
			function()
				withFlags({ "Gloves", "Workshop" }, function()
					-- table des Gants du GDD §4.6.1 (pressions)
					local GLOVES = {
						[1] = 1.025,
						[5] = 1.125,
						[10] = 1.250,
						[15] = 1.375,
						[20] = 1.500,
						[25] = 1.625,
						[30] = 1.750,
						[31] = 1.775,
						[35] = 1.875,
						[39] = 1.975,
						[40] = 2.000,
					}
					for lvl, mult in GLOVES do
						expect({ lvl = lvl, mult = math.floor(F.glovesMult(lvl) * 1000 + 0.5) / 1000 }).toEqual({
							lvl = lvl,
							mult = mult,
						})
					end
					expect(F.glovesMult(41)).toBe(F.glovesMult(40))
					-- floor(max(10, 22 × 10) × 2 × (1 + 0,1 × 7) × 2) = 1 496 (un seul floor, GDD §4.3)
					expect(F.pressReward(10, true, 7, false, 40, 2)).toBe(1496)
					expect(F.pressReward(10, true, 9, false, 40, 2)).toBe(1496) -- série 7 au plus
					expect(F.pressReward(10, true, 9, false, 40, 1)).toBe(1408) -- Super Série 1 : 6 au plus
					expect(F.pressReward(10, true, 9, false, 0, 0)).toBe(660)
					expect(F.pressReward(10, false, 0, true, 10)).toBe(math.floor(220 * 1.1 * 1.25))
					expect(F.pressReward(0.2, false, 0, false, 40)).toBe(20) -- minimum 10 × Gants
					expect(F.streakMax(2)).toBe(7)
					expect(F.streakMax(9)).toBe(7)
					expect(F.streakMax(nil)).toBe(5)
					expect(F.streakMax(0 / 0)).toBe(5)
				end)
				withFlags({ "Gloves" }, function()
					expect(F.pressReward(10, true, 7, false, 40, 2)).toBe(1320) -- sans l'Atelier : série 5
				end)
			end
		)

		it("N6 hors ligne : Sac de nuit (+1 h, 16 h au plus), Pot 25 / 30 / 35 % [Workshop]", function()
			withFlags({ "Workshop" }, function()
				expect(F.offlineSeconds(1e6, 1, false, false, 3)).toBe(11 * 3600)
				expect(F.offlineSeconds(1e6, 1, true, false, 3)).toBe(15 * 3600)
				expect(F.offlineSeconds(1e6, 1, true, true, 3)).toBe(16 * 3600) -- maximum du GDD
				expect(F.offlineSeconds(1e6, 1, true, true, 9)).toBe(16 * 3600)
				expect(F.offlineSeconds(1e6, 1, true, true, 0)).toBe(13 * 3600)
				expect(F.offlineSeconds(1e6, 1, true, true)).toBe(13 * 3600)
				expect(F.offlineSeconds(1000, 400, true, true, 3)).toBe(600)
				expect(F.offlineSeconds(1000, 0, true, true, 3)).toBe(0)
				expect(F.offlinePot(2, 100, 0)).toBeNear(50, 1e-9)
				expect(F.offlinePot(2, 100, 1)).toBeNear(56, 1e-9)
				expect(F.offlinePot(2, 100, 2)).toBeNear(62, 1e-9)
				expect(F.offlinePot(2, 100, 7)).toBeNear(62, 1e-9)
				expect(F.offlinePot(2, 100, 0 / 0)).toBeNear(50, 1e-9)
				expect(F.offlinePot(2, 100)).toBe(50)
			end)
		end)

		it(
			"N6 arrêt hors ligne à 120 s de croissance maximale de la boucle avant l'objectif [RecordR]",
			function()
				withFlags({ "RecordR" }, function()
					-- r = 0 : objectif 15 000 ; gMax 50/s : réserve 6 000 → arrêt à 9 000 (avant 90 % = 13 500)
					expect(F.offlineGrowth(100, 1000, 0, 1000, 50)).toBe(8000)
					expect(F.offlineGrowth(100, 1000, 0, 9000, 50)).toBe(0)
					expect(F.offlineGrowth(100, 1000, 0, 12000, 50)).toBe(0)
					-- gMax petit : les 90 % arrêtent d'abord
					expect(F.offlineGrowth(100, 1000, 0, 1000, 1)).toBe(12500)
					-- sans gMax : la règle de la v1.3 ; gMax illisible : réserve 0
					expect(F.offlineGrowth(100, 1000, 0, 1000)).toBe(12500)
					expect(F.offlineGrowth(100, 1000, 0, 1000, 0 / 0)).toBe(12500)
					expect(F.offlineGrowth(100, 1000, 0, 1000, math.huge)).toBe(0)
					-- loin de l'arrêt : la croissance hors ligne entière
					expect(F.offlineGrowth(4, 100, 0, 1000, 50)).toBe(120)
				end)
				-- cas du GDD : après plusieurs Ascensions, une boucle commencée la veille laisse toujours au
				-- moins 120 s de jeu à la croissance maximale (sans la règle : 13 à 30 s, GDD §4.19)
				withFlags({ "RecordR", "JellyAscend", "StarMat" }, function()
					for _, R in { 13, 21, 30, 38 } do
						for _, A in { 2, 6, 10 } do
							local ctx =
								{ R = R, snack = 4, jellyFamily = true, boost = false, A = A, bestR = R + 2 }
							local g = F.growthRate(ctx)
							local gMax = F.maxGrowthRate(ctx)
							local target = F.splorchTarget(R)
							local grown = F.offlineGrowth(g, 16 * 3600, R, 1, gMax)
							-- au moins 120 s, ou rien du tout si la boucle entière dure moins (boucle courte)
							local before = (target - 1) / gMax
							local left = (target - (1 + grown)) / gMax
							local okLeft = left >= math.min(120, before) * (1 - 1e-9)
								and (before > 120 or grown == 0)
							expect({ R = R, A = A, left = okLeft }).toEqual({ R = R, A = A, left = true })
						end
					end
				end)
			end
		)
	end)

	describe("Formulas › zéro trace", function()
		it("aucune erreur ni aucun avertissement", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
