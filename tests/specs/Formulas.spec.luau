--!nocheck
-- Formulas (paquet logic) : tables de coûts du GDD §4.11 au Glow près, bonus, M, valeurs, revenu,
-- hors ligne, règlement paresseux, Supernova, perchoirs, Starforge, population, protections ;
-- invariants (jamais négatif, jamais NaN, monnaies entières) sur des entrées hostiles.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local F = h:require("ReplicatedStorage.Shared.Logic.Formulas")
	local Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies")

	local NAN = 0 / 0
	local INF = math.huge

	local function code(s, f, v)
		return Nebbies.pack(s, f or 0, v or 0)
	end

	local function isMoney(x)
		return type(x) == "number" and x == x and x >= 0 and x ~= INF and x % 1 == 0
	end

	describe("Formulas — améliorations (§4.11)", function()
		it("retrouve la table des coûts du GDD au Glow près", function()
			local gdd = {
				conga = { 50, 77, 120, 186, 288, 447, 693, 1074, 1665, 2581, 4002, 6203 },
				stride = { 80, 113, 161, 229, 325, 461, 655, 931, 1322, 1877, 2666, 3786 },
				lure = { 70, 105, 157, 236, 354, 531, 797, 1196, 1794, 2691, 4036, 6054 },
				perches = { 200, 350, 612, 1071, 1875, 3282, 5744, 10053, 17592, 30787, 53877, 94286 },
				guard = { 5000, 20000, 80000, 320000, 1280000 },
			}
			for track, costs in gdd do
				for L, cost in costs do
					expect(F.upgradeCost(track, L - 1)).toBe(cost)
				end
			end
		end)

		it("retrouve les totaux du GDD (Foulée, Attrait, Conga 0-11, Perchoirs ≈ 9,7e8)", function()
			local function total(track, levels)
				local sum = 0
				for L = 0, levels - 1 do
					sum += F.upgradeCost(track, L)
				end
				return sum
			end
			expect(total("stride", 20)).toBe(211445)
			expect(total("lure", 12)).toBe(18021)
			expect(total("conga", 12)).toBe(17386)
			local perches = total("perches", 27)
			expect(perches > 9.65e8 and perches < 9.75e8).toBe(true)
		end)

		it("Conga : 1,55 jusqu'au niveau 12 puis 1,20", function()
			expect(F.upgradeCost("conga", 12)).toBe(math.floor(50 * 1.55 ^ 12))
			expect(F.upgradeCost("conga", 13)).toBe(math.floor(50 * 1.55 ^ 12 * 1.2))
			expect(F.upgradeCost("conga", 20)).toBe(math.floor(50 * 1.55 ^ 12 * 1.2 ^ 8))
		end)

		it("niveaux max : Conga min(12 + 5 R, 57), autres fixes", function()
			expect(F.upgradeMaxLevel("conga", 0)).toBe(12)
			expect(F.upgradeMaxLevel("conga", 1)).toBe(17)
			expect(F.upgradeMaxLevel("conga", 9)).toBe(57)
			expect(F.upgradeMaxLevel("conga", 40)).toBe(57)
			expect(F.upgradeMaxLevel("stride", 5)).toBe(20)
			expect(F.upgradeMaxLevel("lure", 5)).toBe(12)
			expect(F.upgradeMaxLevel("perches", 5)).toBe(27)
			expect(F.upgradeMaxLevel("guard", 5)).toBe(5)
		end)

		it("piste inconnue ou niveau hostile : achat impossible, jamais NaN", function()
			expect(F.upgradeCost("hack", 0)).toBe(math.huge)
			expect(F.upgradeMaxLevel("hack", 3)).toBe(0)
			expect(F.upgradeCost("conga", NAN)).toBe(50)
			expect(F.upgradeCost("conga", -5)).toBe(50)
			expect(F.upgradeCost("stride", 2.7)).toBe(161)
			expect(F.upgradeMaxLevel("conga", NAN)).toBe(12)
			expect(F.upgradeMaxLevel("conga", -3)).toBe(12)
		end)
	end)

	describe("Formulas — file, capture, vitesse (§4.5-§4.7)", function()
		it("capacité 3 + niveau, plafond absolu 60", function()
			expect(F.congaCapacity(0)).toBe(3)
			expect(F.congaCapacity(12)).toBe(15)
			expect(F.congaCapacity(57)).toBe(60)
			expect(F.congaCapacity(500)).toBe(60)
			expect(F.congaCapacity(NAN)).toBe(3)
		end)

		it("Conga Bonus min(5, 1 + 0,08 (n − 1)) ; ×2,5 en Zen", function()
			expect(F.congaBonus(0)).toBe(1)
			expect(F.congaBonus(1)).toBe(1)
			expect(F.congaBonus(3)).toBeNear(1.16, 1e-12)
			expect(F.congaBonus(20)).toBeNear(2.52, 1e-12)
			expect(F.congaBonus(51)).toBeNear(5, 1e-12)
			expect(F.congaBonus(60)).toBe(5)
			expect(F.congaBonus(51, true)).toBe(2.5)
			expect(F.congaBonus(10, true)).toBeNear(1.72, 1e-12)
			expect(F.congaBonus(NAN)).toBe(1)
		end)

		it("Guard Links 3 + niveau (≤ 8), Attrait 5 + 0,5 niveau (× 1,5 en Snip Rush)", function()
			expect(F.guardLinks(0)).toBe(3)
			expect(F.guardLinks(5)).toBe(8)
			expect(F.guardLinks(9)).toBe(8)
			expect(F.lureRadius(0)).toBe(5)
			expect(F.lureRadius(12)).toBe(11)
			expect(F.lureRadius(99)).toBe(11)
			expect(F.lureRadius(12, true)).toBeNear(16.5, 1e-12)
			expect(F.lureRadius(NAN, true)).toBeNear(7.5, 1e-12)
		end)

		it("WalkSpeed = base × ralenti × comète + Dash + Second Souffle", function()
			expect(F.baseWalkSpeed(0)).toBe(16)
			expect(F.baseWalkSpeed(20)).toBe(26)
			expect(F.baseWalkSpeed(40)).toBe(26)
			local p = { stride = 20, n = 10, guard = 3, carrier = false, dashing = false, secondWind = false }
			expect(F.walkSpeed(p)).toBeNear(26 * (1 - 0.004 * 7), 1e-9)
			-- ralenti plafonné à −15 %
			p.n = 60
			expect(F.walkSpeed(p)).toBeNear(26 * 0.85, 1e-9)
			-- pas de ralenti sous les Guard Links
			p.n = 3
			expect(F.walkSpeed(p)).toBe(26)
			-- Dash +10, Second Souffle +4
			p.dashing = true
			expect(F.walkSpeed(p)).toBe(36)
			p.secondWind = true
			expect(F.walkSpeed(p)).toBe(40)
			-- porteur : ×0,85 et jamais de Dash
			p.carrier = true
			expect(F.walkSpeed(p)).toBeNear(26 * 0.85 + 4, 1e-9)
			-- entrées hostiles : vitesse finie
			local v = F.walkSpeed({
				stride = NAN,
				n = INF,
				guard = -2,
				carrier = false,
				dashing = false,
				secondWind = false,
			})
			expect(v == v and v > 0 and v < 100).toBe(true)
		end)

		it("recharge du Dash max(5, 7 − 0,25 R)", function()
			expect(F.dashCooldown(0)).toBe(7)
			expect(F.dashCooldown(4)).toBe(6)
			expect(F.dashCooldown(8)).toBe(5)
			expect(F.dashCooldown(30)).toBe(5)
			expect(F.dashCooldown(NAN)).toBe(7)
		end)
	end)

	describe("Formulas — valeurs des Nebbies (§4.2, §4.4, §4.13)", function()
		it("formes × variantes (un Prismatic Golden Huge vaut ×72)", function()
			expect(F.nebbyMultiplier(0, 0)).toBe(1)
			expect(F.nebbyMultiplier(1, 0)).toBe(2)
			expect(F.nebbyMultiplier(2, 0)).toBe(2.5)
			expect(F.nebbyMultiplier(3, 0)).toBe(3)
			expect(F.nebbyMultiplier(4, 0)).toBe(4)
			expect(F.nebbyMultiplier(5, 1 + 2)).toBe(72)
			expect(F.nebbyMultiplier(2, 4)).toBe(5)
			expect(F.nebbyMultiplier(0, 7)).toBe(24)
			-- forme inconnue → ×1 ; bits inconnus ignorés
			expect(F.nebbyMultiplier(9, 0)).toBe(1)
			expect(F.nebbyMultiplier(0, 8)).toBe(1)
		end)

		it("valeur de parade = valeurParade × forme × variantes ; code invalide → 0", function()
			expect(F.paradeValue(code(1))).toBe(20)
			expect(F.paradeValue(code(16, 1, 1))).toBe(300 * 2 * 4)
			expect(F.paradeValue(code(36))).toBe(200000)
			expect(F.paradeValue(0)).toBe(0)
			expect(F.paradeValue(NAN)).toBe(0)
			expect(F.paradeValue(-1)).toBe(0)
			expect(F.paradeValue(5000)).toBe(0)
		end)

		it("revenu passif = passif × forme × variantes × ★ ; parade = 20 × passif", function()
			expect(F.passiveIncome({ s = 1, f = 0, v = 0, st = 1 })).toBe(1)
			expect(F.passiveIncome({ s = 29, f = 2, v = 0, st = 3 })).toBe(300 * 2.5 * 12)
			expect(F.passiveIncome({ s = 33, f = 5, v = 3, st = 5 })).toBe(1500 * 72 * 150)
			for s = 1, 36 do
				local rec = { s = s, f = 0, v = 0, st = 1 }
				expect(F.paradeValue(code(s))).toBe(20 * F.passiveIncome(rec))
			end
			-- enregistrements hostiles
			expect(F.passiveIncome({ s = 99, f = 0, v = 0, st = 1 })).toBe(0)
			expect(F.passiveIncome({ s = 1, f = 0, v = 0, st = 9 })).toBe(150)
			expect(F.passiveIncome({ s = 1, f = 0, v = 0, st = NAN })).toBe(1)
			expect(F.passiveIncome(nil)).toBe(0)
		end)
	end)

	describe("Formulas — M, parades, hors ligne, règlement (§4.8-§4.10)", function()
		it("M = (1 + 0,4 R + 0,25 VIP + 0,1 min(3, équipiers)) × Double Glow × boost", function()
			local function M(R, vip, crew, dg, boost)
				return F.multiplier({
					supernovas = R,
					vip = vip,
					crewPresent = crew,
					doubleGlow = dg,
					boost = boost,
				})
			end
			expect(M(0, false, 0, false, false)).toBe(1)
			expect(M(1, false, 1, false, false)).toBeNear(1.5, 1e-12) -- exemple du §4.8
			expect(M(2, true, 5, true, true)).toBeNear((1 + 0.8 + 0.25 + 0.3) * 4, 1e-12)
			expect(M(0, false, NAN, false, false)).toBe(1)
			expect(F.offlineMultiplier(1, true, true)).toBeNear((1 + 0.4 + 0.25) * 2, 1e-12)
		end)

		it("exemples du GDD : première parade 69 Glow, file du Cratère 57 002 Glow", function()
			expect(F.paradeGlow({ code(1), code(1), code(1) }, 1, false, false)).toBe(69)
			local codes = {}
			for _ = 1, 4 do
				table.insert(codes, code(17)) -- Rare 300
			end
			for _ = 1, 8 do
				table.insert(codes, code(9)) -- Peu commun 80
			end
			for _ = 1, 6 do
				table.insert(codes, code(23)) -- Épique 1 200
			end
			table.insert(codes, code(29)) -- Légendaire 6 000
			table.insert(codes, code(2, 1)) -- Commun Aurora 40
			expect(#codes).toBe(20)
			expect(F.paradeGlow(codes, 1.5, false, false)).toBe(57002)
			-- à la Balise : × 1,5
			expect(F.paradeGlow(codes, 1.5, false, true)).toBe(math.floor(15080 * 2.52 * 1.5 * 1.5))
		end)

		it("parade : Zen plafonne le bonus à 2,5 ; entrées vides ou hostiles → 0", function()
			local line = {}
			for _ = 1, 51 do
				table.insert(line, code(1))
			end
			expect(F.paradeGlow(line, 1, false, false)).toBe(51 * 20 * 5)
			expect(F.paradeGlow(line, 1, true, false)).toBe(51 * 20 * 2.5)
			expect(F.paradeGlow({}, 3, false, false)).toBe(0)
			expect(F.paradeGlow({ code(1) }, NAN, false, false)).toBe(0)
			expect(F.paradeGlow({ code(1) }, -2, false, false)).toBe(0)
			expect(F.paradeGlow({ NAN, 0, -5 }, 1, false, false)).toBe(0)
			expect(isMoney(F.paradeGlow(line, INF, false, false))).toBe(true)
		end)

		it("hors ligne : 50 % plafonné à 8 h ; Night Shift 75 % plafonné à 12 h", function()
			local glow, secs = F.offlineGlow(10, 10 * 3600, false)
			expect(secs).toBe(8 * 3600)
			expect(glow).toBe(10 * 8 * 3600 * 0.5)
			glow, secs = F.offlineGlow(10, 10 * 3600, true)
			expect(secs).toBe(10 * 3600)
			expect(glow).toBe(10 * 10 * 3600 * 0.75)
			glow, secs = F.offlineGlow(10, 20 * 3600, true)
			expect(secs).toBe(12 * 3600)
			glow, secs = F.offlineGlow(3, -50, false)
			expect(glow).toBe(0)
			expect(secs).toBe(0)
			glow, secs = F.offlineGlow(NAN, NAN, false)
			expect(glow).toBe(0)
			expect(secs).toBe(0)
			glow = F.offlineGlow(0.3, 7, false)
			expect(glow).toBe(1) -- floor(1,05)
		end)

		it("règlement paresseux : floor(rate × dt + carry), la fraction est conservée", function()
			local r = F.settle(100, 0.5, 3.3, 1)
			expect(r.credited).toBe(3)
			expect(r.glow).toBe(103)
			expect(r.carry).toBeNear(0.8, 1e-9)
			-- 1 000 petits règlements = un grand (aucune perte de fraction)
			local glow, carry = 0, 0
			for _ = 1, 1000 do
				local s = F.settle(glow, carry, 0.37, 0.1)
				glow, carry = s.glow, s.carry
			end
			expect(glow).toBe(math.floor(0.37 * 100 + 1e-6))
			-- entrées hostiles : rien de crédité, rien de négatif, fraction valide
			for _, args in
				{
					{ 10, 0, -5, 10 },
					{ 10, 0, 5, -10 },
					{ 10, NAN, NAN, NAN },
					{ NAN, 2, 1, 1 },
					{ 10, -1, 1, 1 },
				}
			do
				local s = F.settle(args[1], args[2], args[3], args[4])
				expect(isMoney(s.glow) and isMoney(s.credited)).toBe(true)
				expect(s.carry >= 0 and s.carry < 1).toBe(true)
			end
		end)

		it("secondes de revenu passif avec minimum", function()
			expect(F.glowForSeconds(3, 300)).toBe(900)
			expect(F.glowForSeconds(3, 300, 500)).toBe(900)
			expect(F.glowForSeconds(1, 300, 500)).toBe(500)
			expect(F.glowForSeconds(2.5, 3)).toBe(7)
			expect(F.glowForSeconds(NAN, 300, 1000)).toBe(1000)
			expect(F.glowForSeconds(-4, 300)).toBe(0)
		end)
	end)

	describe("Formulas — Supernova et auras (§4.12)", function()
		it(
			"table de coûts de la configuration puis BeyondBase × 1,5^(R − 11), continue et croissante",
			function()
				local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
				local sn = Balance.Supernova
				expect(F.supernovaCost(0)).toBe(400000) -- objectif affiché dès l'accueil (GDD §3, §7.4)
				for R = 0, #sn.Costs - 1 do
					expect(F.supernovaCost(R)).toBe(sn.Costs[R + 1])
				end
				expect(sn.BeyondBase).toBe(sn.Costs[#sn.Costs]) -- raccord sans saut à R = 11
				expect(F.supernovaCost(12)).toBe(math.floor(sn.BeyondBase * 1.5))
				expect(F.supernovaCost(13)).toBe(math.floor(sn.BeyondBase * 1.5 ^ 2))
				for R = 1, 40 do
					expect(F.supernovaCost(R) > F.supernovaCost(R - 1)).toBe(true)
				end
				expect(F.supernovaCost(NAN)).toBe(400000)
				expect(isMoney(F.supernovaCost(200))).toBe(true)
			end
		)

		it("aura tous les 3 R : Argent, Or, Nova, Galaxie", function()
			expect(F.auraFor(0)).toBeNil()
			expect(F.auraFor(2)).toBeNil()
			expect(F.auraFor(3)).toBe("silver")
			expect(F.auraFor(5)).toBe("silver")
			expect(F.auraFor(6)).toBe("gold")
			expect(F.auraFor(9)).toBe("nova")
			expect(F.auraFor(12)).toBe("galaxy")
			expect(F.auraFor(40)).toBe("galaxy")
			expect(F.auraFor(NAN)).toBeNil()
		end)
	end)

	describe("Formulas — perchoirs, réserve, Starforge, libération (§4.9, §4.13, §4.14)", function()
		it("jalons d'Atlas : +1 perchoir toutes les 12 entrées, 10 au plus", function()
			expect(F.atlasPerchMilestones(0)).toBe(0)
			expect(F.atlasPerchMilestones(11)).toBe(0)
			expect(F.atlasPerchMilestones(12)).toBe(1)
			expect(F.atlasPerchMilestones(119)).toBe(9)
			expect(F.atlasPerchMilestones(120)).toBe(10)
			expect(F.atlasPerchMilestones(216)).toBe(10)
		end)

		it("perchoirs 3 + niveau + jalons + 6 (pass), maximum 46", function()
			expect(F.perchCount(0, 0, false)).toBe(3)
			expect(F.perchCount(27, 0, false)).toBe(30)
			expect(F.perchCount(27, 120, false)).toBe(40)
			expect(F.perchCount(27, 150, true)).toBe(46)
			expect(F.perchCount(99, 999, true)).toBe(46)
			expect(F.perchCount(NAN, NAN, false)).toBe(3)
		end)

		it("réserve 300 / 600 (Stash Plus)", function()
			expect(F.stashCap(false)).toBe(300)
			expect(F.stashCap(true)).toBe(600)
		end)

		it("Starforge : 25 / 120 / 600 / 3 000, rien au-delà de ★5", function()
			expect(F.fuseCost(1)).toBe(25)
			expect(F.fuseCost(2)).toBe(120)
			expect(F.fuseCost(3)).toBe(600)
			expect(F.fuseCost(4)).toBe(3000)
			expect(F.fuseCost(5)).toBeNil()
			expect(F.fuseCost(0)).toBeNil()
			expect(F.fuseCost(2.5)).toBeNil()
			expect(F.fuseCost(NAN)).toBeNil()
		end)

		it("libération : Stardust × 3^(★ − 1), Cosmique non libérable", function()
			expect(F.releaseDust(1, 1)).toBe(1)
			expect(F.releaseDust(2, 1)).toBe(4)
			expect(F.releaseDust(3, 2)).toBe(45)
			expect(F.releaseDust(5, 1)).toBe(300)
			expect(F.releaseDust(6, 5)).toBe(1500 * 81)
			expect(F.releaseDust(7, 1)).toBeNil()
			expect(F.releaseDust(0, 1)).toBeNil()
			expect(F.releaseDust(NAN, 1)).toBeNil()
			expect(F.releaseDust(1, NAN)).toBe(1)
		end)
	end)

	describe("Formulas — population, événements, protections (§4.3, §4.15, §4.16)", function()
		it("capScale = clamp((actifs + 4) / 16, 0,5, 1) et plafonds effectifs arrondis", function()
			expect(F.capScale(0)).toBe(0.5)
			expect(F.capScale(4)).toBe(0.5)
			expect(F.capScale(8)).toBe(0.75)
			expect(F.capScale(12)).toBe(1)
			expect(F.capScale(50)).toBe(1)
			expect(F.capScale(NAN)).toBe(0.5)
			expect(F.effectiveCap(40, 8, 1)).toBe(30)
			expect(F.effectiveCap(10, 8, 1)).toBe(8) -- round(7,5)
			expect(F.effectiveCap(40, 12, 1.5)).toBe(60) -- Meteor Shower
			expect(F.effectiveCap(24, 12, 2)).toBe(48) -- Starfall Frenzy
			expect(F.effectiveCap(-4, 12, 1)).toBe(0)
			expect(F.effectiveCap(10, 12, NAN)).toBe(10)
		end)

		it("objectif de la Balise : max(20, 10 × actifs) × miséricorde", function()
			expect(F.beaconGoal(1, 0)).toBe(20)
			expect(F.beaconGoal(5, 0)).toBe(50)
			expect(F.beaconGoal(5, 1)).toBe(50)
			expect(F.beaconGoal(5, 2)).toBe(37)
			expect(F.beaconGoal(5, 3)).toBe(25)
			expect(F.beaconGoal(12, 7)).toBe(60)
			expect(F.beaconGoal(0, 0)).toBe(20)
			expect(F.beaconGoal(NAN, NAN)).toBe(20)
		end)

		it(
			"Gloomwisps : 1-2 → 5 ; 3-5 → 4 ; 6-8 → 3 ; 9-11 → 2 ; 12 → 1 ; supprimés → 0",
			function()
				local expected = { [0] = 5, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 1 }
				for n = 0, 12 do
					expect(F.wispCount(n, false)).toBe(expected[n])
				end
				expect(F.wispCount(30, false)).toBe(0)
				expect(F.wispCount(2, true)).toBe(0)
			end
		)

		it("bouclier débutant : session 1, ou < 30 min cumulées et R = 0", function()
			expect(F.rookieEligible(1, 99999, 4)).toBe(true)
			expect(F.rookieEligible(0, 0, 0)).toBe(true)
			expect(F.rookieEligible(2, 1799, 0)).toBe(true)
			expect(F.rookieEligible(2, 1800, 0)).toBe(false)
			expect(F.rookieEligible(3, 100, 1)).toBe(false)
			expect(F.rookieEligible(3, NAN, 0)).toBe(false)
		end)
	end)

	describe("Formulas — invariants sur entrées hostiles", function()
		it("aucune erreur, aucun NaN, monnaies entières non négatives", function()
			local hostile = { NAN, INF, -INF, -1, 0, 0.5, 1e300, -1e300, 7 }
			for _, x in hostile do
				for _, y in hostile do
					for _, track in { "conga", "stride", "lure", "perches", "guard" } do
						local c = F.upgradeCost(track, x)
						expect(isMoney(c)).toBe(true)
					end
					expect(isMoney(F.supernovaCost(x))).toBe(true)
					expect(isMoney(F.glowForSeconds(x, y, x))).toBe(true)
					local g, s = F.offlineGlow(x, y, false)
					expect(isMoney(g)).toBe(true)
					expect(s == s and s >= 0).toBe(true)
					local settled = F.settle(x, y, x, y)
					expect(isMoney(settled.glow)).toBe(true)
					expect(settled.carry >= 0 and settled.carry < 1).toBe(true)
					local cap = F.effectiveCap(x, y, x)
					expect(cap == cap and cap >= 0).toBe(true)
					expect(F.beaconGoal(x, y) >= 1).toBe(true)
					expect(F.wispCount(x, false) >= 0).toBe(true)
					local bonus = F.congaBonus(x, y == 7)
					expect(bonus == bonus and bonus >= 1 and bonus <= 5).toBe(true)
					local m = F.multiplier({
						supernovas = x,
						vip = true,
						crewPresent = y,
						doubleGlow = false,
						boost = true,
					})
					expect(m == m and m >= 1).toBe(true)
				end
			end
		end)
	end)
end
