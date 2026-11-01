--!nocheck
-- Props_Formulas (paquet logic, docs/04 §17.1 couche a, §16) : jamais NaN ni négatif, bornes,
-- monotonie, additivité du Pot, entrées bizarres sûres.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local F = h:require("ReplicatedStorage.Shared.Logic.Formulas")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local MAX = 1e300

	local function ok(x)
		return type(x) == "number" and x == x and x >= 0 and x <= MAX
	end
	local function okSize(x)
		return type(x) == "number" and x == x and x >= 1 and x <= MAX
	end

	local any = Props.anyNumber()
	local anyBool = Props.oneOf({ true, false, nil, 1, "x" })
	local ctxGen = Props.map(Props.tuple(any, any, any, any, any, anyBool, anyBool), function(v)
		return {
			decor = v[1],
			friends = v[2],
			fame = v[3],
			trophyBonus = v[4],
			goldenPages = v[5],
			doubleCoins = v[6],
			boost = v[7],
		}
	end)
	local recGen = Props.map(
		Props.tuple(
			Props.int(-1, 30),
			Props.int(-1, 12),
			any,
			any,
			any,
			Props.oneOf({ "pen", "pool", "dodo", "mail", "??" })
		),
		function(v)
			return {
				s = v[1],
				m = v[2],
				st = v[3],
				z = v[4],
				zg = v[5],
				bf = 0,
				lk = false,
				o = "",
				at = v[6],
				b = 0,
			}
		end
	)

	describe("Props › Formulas", function()
		it("clampCoins : fini, dans [0 ; Max], entier sous 1e15, idempotent", function()
			Props.check(6000, Props.any(), function(x)
				local c = F.clampCoins(x)
				return ok(c) and (c >= 1e15 or c % 1 == 0) and F.clampCoins(c) == c
			end)
		end)

		it("clampSize : dans [1 ; Max], idempotent", function()
			Props.check(6000, Props.any(), function(x)
				local s = F.clampSize(x)
				return okSize(s) and F.clampSize(s) == s
			end)
		end)

		it("G(t) : fini, ≥ 0, croissant en t", function()
			Props.check(5000, Props.tuple(any, any, any, any, any), function(v)
				local growth = { G = v[1], g = v[2], t = v[3] }
				local a, b = v[4], v[5]
				local ga, gb = F.G(growth, a), F.G(growth, b)
				if not (ok(ga) and ok(gb)) then
					return false
				end
				if a == a and b == b and math.abs(a) ~= math.huge and math.abs(b) ~= math.huge and a <= b then
					return ga <= gb
				end
				return true
			end)
		end)

		it("sizeAt, income, incomeFactor, A : finis et ≥ 0 pour toute entrée", function()
			Props.check(6000, Props.tuple(recGen, any, ctxGen), function(v)
				local size = F.sizeAt(v[1], v[2])
				local k = F.incomeFactor(v[1].s, v[1].m, v[1].st, v[3])
				local inc = F.income(size, v[1].s, v[1].m, v[1].st, v[3])
				local a = F.A(v[3])
				return okSize(size) and ok(k) and ok(inc) and ok(a) and a >= 1
			end)
		end)

		it("growthRate : fini, ≥ 0, et croissant en R et en niveau du Tapis", function()
			Props.check(
				5000,
				Props.tuple(Props.int(0, 40), Props.int(0, 12), Props.bool(), Props.bool()),
				function(v)
					local base = F.growthRate({ R = v[1], snack = v[2], jellyFamily = v[3], boost = v[4] })
					local moreR =
						F.growthRate({ R = v[1] + 1, snack = v[2], jellyFamily = v[3], boost = v[4] })
					local moreSnack = F.growthRate({
						R = v[1],
						snack = math.min(12, v[2] + 1),
						jellyFamily = v[3],
						boost = v[4],
					})
					return ok(base) and base > 0 and moreR > base and moreSnack >= base
				end
			)
			Props.check(2000, Props.tuple(any, any, anyBool, anyBool), function(v)
				return ok(F.growthRate({ R = v[1], snack = v[2], jellyFamily = v[3], boost = v[4] }))
			end)
		end)

		it("ranchIncome : revenu(G) = Σ revenus des squishies d'enclos et du Bassin", function()
			local small = Props.map(
				Props.tuple(
					Props.int(1, 26),
					Props.int(0, 9),
					Props.int(0, 5),
					Props.number(1, 1e6),
					Props.number(0, 1e5),
					Props.oneOf({ "pen", "pool", "dodo" })
				),
				function(v)
					return {
						s = v[1],
						m = v[2],
						st = v[3],
						z = v[4],
						zg = v[5],
						bf = 0,
						lk = false,
						o = "",
						at = v[6],
						b = 0,
					}
				end
			)
			Props.check(3000, Props.tuple(Props.array(small, 8), Props.number(0, 1e6)), function(v)
				local list, G = v[1], v[2]
				local map = {}
				local expected = 0
				for i, r in list do
					map["u" .. i] = r
					if r.at ~= "dodo" then
						local size = r.z - r.zg + G
						if size >= 1 then
							expected += F.incomeFactor(r.s, r.m, r.st, {}) * size
						else
							expected += F.incomeFactor(r.s, r.m, r.st, {}) * 1
						end
					end
				end
				local K, S1 = F.ranchIncome(map, G, {})
				local got = S1 + K * G
				return math.abs(got - expected) <= 1e-9 * math.max(1, math.abs(expected))
			end)
		end)

		it("potGain : ≥ 0, fini, et additif ([t0 ; t2] = [t0 ; t1] + [t1 ; t2], 1e-9 relatif)", function()
			Props.check(
				5000,
				Props.tuple(
					Props.number(0, 1e4),
					Props.number(0, 1e6),
					Props.number(0, 1e6),
					Props.number(0, 1e4),
					Props.number(0, 1e5),
					Props.number(0, 1e5),
					Props.number(0, 1e5)
				),
				function(v)
					local K, S1 = v[1], v[2]
					local growth = { G = v[3], g = v[4], t = v[5] }
					local ts = { v[5], v[6], v[7] }
					table.sort(ts)
					local t0, t1, t2 = ts[1], ts[2], ts[3]
					local whole = F.potGain(K, S1, growth, t0, t2)
					local parts = F.potGain(K, S1, growth, t0, t1) + F.potGain(K, S1, growth, t1, t2)
					return ok(whole) and math.abs(whole - parts) <= 1e-9 * math.max(1, whole)
				end
			)
		end)

		it("potGain : N règlements avec rebase de growth = 1 règlement (EconomyService.settle)", function()
			Props.check(
				1500,
				Props.tuple(Props.number(0, 100), Props.number(0, 1e4), Props.number(0, 50), Props.int(1, 40)),
				function(v)
					local K, S1, g, n = v[1], v[2], v[3], v[4]
					local start = { G = 5, g = g, t = 1000 }
					local whole = F.potGain(K, S1, start, 1000, 1000 + 3600)
					-- règlements successifs : chaque fois growth.G = G(now), growth.t = now
					local growth = table.clone(start)
					local pot = 0
					local t = 1000
					for i = 1, n do
						local now = 1000 + 3600 * i / n
						pot += F.potGain(K, S1, growth, t, now)
						growth = { G = F.G(growth, now), g = g, t = now }
						t = now
					end
					return math.abs(pot - whole) <= 1e-9 * math.max(1, whole)
				end
			)
		end)

		it("potGain : entrées bizarres → 0 ou montant fini", function()
			Props.check(4000, Props.tuple(any, any, any, any, any, any), function(v)
				return ok(F.potGain(v[1], v[2], { G = v[3], g = v[4], t = 0 }, v[5], v[6]))
			end)
		end)

		it("pressReward : ≥ 10, entier sous 1e15, croissant en revenu, PERFECT ≥ normal", function()
			Props.check(5000, Props.tuple(any, Props.bool(), any, Props.bool()), function(v)
				local r = F.pressReward(v[1], v[2], v[3], v[4])
				local p = F.pressReward(v[1], true, v[3], v[4])
				local n = F.pressReward(v[1], false, v[3], v[4])
				return ok(r) and r >= 10 and (r >= 1e15 or r % 1 == 0) and p >= n
			end)
			Props.check(3000, Props.tuple(Props.number(0, 1e9), Props.number(0, 1e9)), function(v)
				local a, b = math.min(v[1], v[2]), math.max(v[1], v[2])
				return F.pressReward(a, false, 0, false) <= F.pressReward(b, false, 0, false)
			end)
		end)

		it("tileCost : croissant en niveau et en R, entier sous 1e15, ou math.huge", function()
			local tiles = Props.oneOf({ "snack", "decor", "pens", "cozyBed" })
			Props.check(5000, Props.tuple(tiles, Props.int(0, 20), Props.int(0, 30)), function(v)
				local c = F.tileCost(v[1], v[2], v[3])
				local nextLevel = F.tileCost(v[1], v[2] + 1, v[3])
				local nextR = F.tileCost(v[1], v[2], v[3] + 1)
				if c == math.huge then
					return nextLevel == math.huge
				end
				return ok(c) and (c >= 1e15 or c % 1 == 0) and nextLevel >= c and nextR >= c
			end)
			Props.check(3000, Props.tuple(Props.any(), any, any), function(v)
				local c = F.tileCost(v[1], v[2], v[3])
				return c == math.huge or ok(c)
			end)
		end)

		it("places, Cuve, fusion, vente, récompenses : bornées pour toute entrée", function()
			Props.check(5000, Props.tuple(any, any, anyBool), function(v)
				local cap = F.penCapacity(v[1], v[3])
				local slots = F.poolSlots(v[3])
				local lvl = F.vatLevel(v[1])
				local interval = F.vatInterval(v[1], v[3])
				local fs = F.fusionSize(v[1], v[2])
				local st = F.fusionStars(v[1])
				return cap >= 4
					and cap <= 24
					and cap % 1 == 0
					and (slots == 5 or slots == 6)
					and lvl.quality >= 1
					and lvl.quality <= 8
					and lvl.speed >= 3
					and lvl.speed <= 10
					and lvl.nozzles >= 0
					and lvl.nozzles <= 5
					and interval >= 15
					and interval <= 90
					and okSize(fs)
					and st >= 1
					and st <= 5
			end)
			Props.check(5000, Props.tuple(any, any, any), function(v)
				return ok(F.comboReward(v[1], v[2]))
					and F.sellValue(v[1]) >= 10
					and ok(F.sellValue(v[1]))
					and ok(F.secondsOfIncome(v[1], v[2], v[3]))
					and ok(F.offlineGrowth(v[1], v[2]))
					and ok(F.offlineGrowth(v[1], v[2], v[3], v[1]))
					and ok(F.offlinePot(v[1], v[2]))
					and okSize(F.babySize(v[1], v[2], v[3]))
					and okSize(F.babySize(v[1], v[2], v[3], v[1]))
					and F.coinPack(v[1], "CoinsSmall") == 0
			end)
		end)

		it(
			"offlineGrowth (contrat v1.2) : jamais au-delà de StopAt × objectif − plus gros, croissant en durée",
			function()
				Props.check(
					5000,
					Props.tuple(
						Props.number(0, 1e12),
						Props.number(0, 13 * 3600),
						Props.int(0, 40),
						Props.number(0, 1e14)
					),
					function(v)
						local grown = F.offlineGrowth(v[1], v[2], v[3], v[4])
						local stopAt = Balance.Offline.StopAt * F.splorchTarget(v[3])
						local longer = F.offlineGrowth(v[1], v[2] + 60, v[3], v[4])
						return ok(grown)
							and grown <= math.max(0, stopAt - v[4]) * (1 + 1e-12)
							and grown <= F.offlineGrowth(v[1], v[2]) * (1 + 1e-12)
							and longer >= grown
					end
				)
			end
		)

		it("fusionSize : la fusion grossit toujours (≥ chacun des deux, Max mis à part)", function()
			Props.check(5000, Props.tuple(Props.number(1, 1e299), Props.number(1, 1e299)), function(v)
				local fs = F.fusionSize(v[1], v[2])
				return fs >= math.min(MAX, math.max(v[1], v[2]))
			end)
		end)

		it(
			"bébés : ≥ minimum (borné à [1 ; Max]) et ≤ max(minimum, 0,5 × plus gros du receveur)",
			function()
				Props.check(
					5000,
					Props.tuple(
						Props.number(0, 1),
						Props.number(1, 100),
						Props.number(1, 1e12),
						Props.maybe(Props.number(1, 1e15))
					),
					function(v)
						local size = F.babySize(v[1], v[2], v[3], v[4])
						return size >= v[2]
							and size <= math.max(v[2], Balance.Babies.MaxOfBiggest * v[3]) + 1e-6
					end
				)
			end
		)

		it("offlineSeconds : dans [0 ; 13 h], 0 sans dernière présence", function()
			Props.check(5000, Props.tuple(any, any, anyBool, anyBool), function(v)
				local s = F.offlineSeconds(v[1], v[2], v[3], v[4])
				if not (ok(s) and s <= 13 * 3600) then
					return false
				end
				if not (type(v[2]) == "number" and v[2] > 0) then
					return s == 0
				end
				return true
			end)
		end)

		it("splorchTarget : croissant en R, toujours fini", function()
			Props.check(3000, Props.int(0, 800), function(R)
				local a, b = F.splorchTarget(R), F.splorchTarget(R + 1)
				return ok(a) and b >= a
			end)
			Props.check(2000, Props.any(), function(R)
				return ok(F.splorchTarget(R))
			end)
		end)

		it("selles, monture, trophées : bornés et croissants", function()
			Props.check(5000, Props.tuple(Props.number(0, 1e15), Props.number(0, 1e15)), function(v)
				local a, b = math.min(v[1], v[2]), math.max(v[1], v[2])
				local sa, sb = F.saddleLevel(a), F.saddleLevel(b)
				local ta, tb = F.trophyTier(a), F.trophyTier(b)
				local ride = F.rideStats(sb)
				return sa <= sb
					and sb <= 3
					and ta <= tb
					and tb <= 4
					and ride.walkSpeed >= 16
					and ride.hipHeight >= 2
			end)
			Props.check(2000, Props.array(any, 30), function(list)
				local bonus = F.trophyBonus(list)
				return ok(bonus) and bonus <= 2.08 + 1e-9
			end)
		end)

		it("splorchPreview : jamais d'erreur, champs sûrs, pour des profils abîmés", function()
			local profile = Props.map(
				Props.tuple(Props.any(), Props.any(), Props.any(), Props.array(recGen, 6), Props.any()),
				function(v)
					local squishies = {}
					for i, r in v[4] do
						squishies[tostring(i)] = r
					end
					return {
						R = v[1],
						coins = v[2],
						pot = v[3],
						squishies = squishies,
						growth = { G = v[5], g = 1, t = 0 },
						coinBuy = { at = v[1], amount = v[2] },
					}
				end
			)
			Props.check(3000, Props.tuple(profile, any, any), function(v)
				local p = F.splorchPreview(v[1], { now = v[2], unix = v[3] })
				return type(p.ready) == "boolean"
					and p.recentBuy == nil
					and ok(p.target)
					and ok(p.biggest)
					and ok(p.coinsLost)
					and type(p.defaultFlyer) == "string"
					and type(p.unlocks) == "table"
					and p.level >= 1
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
