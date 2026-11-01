--!nocheck
-- RushRules (paquet logic, docs/04 §12.1, GDD §4.21.4) : chaque règle du boop dans l'ordre exact du
-- GDD, capture d'une fuite, maintien (extendHold une seule fois tient dans StateTimeouts « boopHold »),
-- clôture, Wild Wobblers partagés, bébés.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local RR = h:require("ReplicatedStorage.Shared.Logic.RushRules")
	local ST = h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")

	local function okCtx()
		return {
			feature = "on",
			eventActive = false,
			rushActive = true,
			booperRush = true,
			ownerRush = true,
			sameUser = false,
			ownerShield = false,
			refused = false,
			blocked = false,
			booperCooldownLeft = 0,
			pairCooldownLeft = 0,
			atFence = true,
			eligible = true,
			bestFriend = false,
			rarity = 1,
			moonBoopable = false,
			ranchThisRush = 0,
			ranchThisHour = 0,
			serverEscapes = 0,
			distance = 5,
			canAct = true,
		}
	end
	local function boop(changes)
		local ctx = okCtx()
		for k, v in changes do
			ctx[k] = v
		end
		return RR.checkBoop(ctx)
	end

	describe("RushRules › boop", function()
		it("contexte honnête : accepté", function()
			local ok, code = RR.checkBoop(okCtx())
			expect(ok).toBe(true)
			expect(code).toBeNil()
		end)

		it("chaque refus a son code", function()
			local cases = {
				{ { feature = "off" }, "feature" },
				{ { feature = "events" }, "feature" },
				{ { feature = "???" }, "feature" },
				{ { rushActive = false }, "notRush" },
				{ { booperRush = false }, "notRushMode" },
				{ { ownerRush = false }, "notRushMode" },
				{ { sameUser = true }, "self" },
				{ { ownerShield = true }, "shieldOn" },
				{ { refused = true }, "refused" },
				{ { blocked = true }, "blocked" },
				{ { booperCooldownLeft = 3 }, "cooldown" },
				{ { pairCooldownLeft = 100 }, "cooldown" },
				{ { atFence = false }, "notAtFence" },
				{ { eligible = false }, "notAtFence" },
				{ { bestFriend = true }, "bestFriend" },
				{ { rarity = 6 }, "moonOnly" },
				{ { rarity = 7 }, "moonOnly" },
				{ { ranchThisRush = 2 }, "tooManyEscapes" },
				{ { ranchThisHour = 4 }, "tooManyEscapes" },
				{ { serverEscapes = 10 }, "tooManyEscapes" },
				{ { distance = 8.01 }, "tooFar" },
				{ { canAct = false }, "tooFar" },
			}
			for _, case in cases do
				local ok, code = boop(case[1])
				expect({ ok = ok, code = code, want = case[2] }).toEqual({
					ok = false,
					code = case[2],
					want = case[2],
				})
			end
		end)

		it("ordre exact : le premier refus du GDD l'emporte", function()
			local _, code = boop({ rushActive = false, sameUser = true, distance = 100 })
			expect(code).toBe("notRush")
			_, code = boop({ refused = true, blocked = true, booperCooldownLeft = 5 })
			expect(code).toBe("refused")
			_, code = boop({ atFence = false, bestFriend = true, rarity = 7 })
			expect(code).toBe("notAtFence")
			_, code = boop({ bestFriend = true, rarity = 7, serverEscapes = 99 })
			expect(code).toBe("bestFriend")
		end)

		it(
			"mode « events » pendant une Lune ou une fête ; Mythique pendant la Lune ; 8 studs pile",
			function()
				expect((boop({ feature = "events", eventActive = true }))).toBe(true)
				expect((boop({ rarity = 6, moonBoopable = true }))).toBe(true)
				expect((boop({ distance = 8 }))).toBe(true)
			end
		)

		it("valeurs bizarres : toujours refusées (NaN, nil)", function()
			expect((boop({ distance = 0 / 0 }))).toBe(false)
			expect((boop({ booperCooldownLeft = 0 / 0 }))).toBe(false)
			expect((boop({ serverEscapes = 0 / 0 }))).toBe(false)
			expect((boop({ rarity = 0 / 0 }))).toBe(false)
			for _, key in
				{
					"sameUser",
					"ownerShield",
					"refused",
					"blocked",
					"bestFriend",
					"atFence",
					"eligible",
					"canAct",
					"distance",
					"rarity",
				}
			do
				local ctx = okCtx()
				ctx[key] = nil -- champ oublié par l'appelant : refus
				expect({ key = key, ok = (RR.checkBoop(ctx)) }).toEqual({ key = key, ok = false })
			end
			expect((RR.checkBoop(nil))).toBe(false)
		end)
	end)

	describe("RushRules › maintien", function()
		it("2,5 s, ou 5 s si le propriétaire est proche", function()
			expect(RR.holdTime(false)).toBe(2.5)
			expect(RR.holdTime(true)).toBe(5)
		end)

		it(
			"extendHold : le temps restant double, une fois, et tient dans StateTimeouts « boopHold »",
			function()
				expect(RR.extendHold(102.5, 101)).toBe(104) -- 1,5 s restantes → 3 s
				-- pire cas : prolongé dès le départ → 5 s, sous 5,5 s
				local startedAt = 100
				local endsAt = RR.extendHold(startedAt + RR.holdTime(false), startedAt)
				expect(endsAt - startedAt).toBe(5)
				expect(endsAt - startedAt <= ST.seconds("boopHold")).toBe(true)
				expect(ST.expired("boopHold", startedAt, endsAt + 0.5)).toBe(false)
				-- déjà fini : rien de plus
				expect(RR.extendHold(100, 105)).toBe(105)
				expect(RR.extendHold(0 / 0, 7)).toBe(7)
				expect(RR.extendHold(9, 0 / 0)).toBe(9)
			end
		)
	end)

	describe("RushRules › capture d'une fuite", function()
		local function catch(changes)
			local ctx = {
				catcherRush = true,
				isBooper = false,
				age = 10,
				isOwner = false,
				distance = 3,
				dy = 1,
				canAct = true,
			}
			for k, v in changes do
				ctx[k] = v
			end
			return RR.checkCatch(ctx)
		end

		it(
			"ordre : mode Rush, verrou du boopeur 6 s, rayon (6,5 / 9,5), écart vertical 8, canAct",
			function()
				expect((catch({}))).toBe(true)
				expect(select(2, catch({ catcherRush = false }))).toBe("notRushMode")
				expect(select(2, catch({ isBooper = true, age = 5.9 }))).toBe("booperLock")
				expect((catch({ isBooper = true, age = 6 }))).toBe(true)
				expect((catch({ distance = 6.5 }))).toBe(true)
				expect(select(2, catch({ distance = 6.51 }))).toBe("tooFar")
				expect((catch({ distance = 9.5, isOwner = true }))).toBe(true)
				expect(select(2, catch({ distance = 9.6, isOwner = true }))).toBe("tooFar")
				expect(select(2, catch({ dy = 8.1 }))).toBe("tooFar")
				expect(select(2, catch({ canAct = false }))).toBe("unstable")
				expect((catch({ distance = 0 / 0 }))).toBe(false)
				expect((catch({ age = 0 / 0, isBooper = true }))).toBe(false)
			end
		)

		it("rayons serveur : 5 + 1,5 et 8 + 1,5", function()
			expect(RR.catchRadius(false)).toBe(6.5)
			expect(RR.catchRadius(true)).toBe(9.5)
		end)
	end)

	describe("RushRules › clôture, Wild Wobblers, bébés", function()
		local function rec(extra)
			local r = { s = 1, m = 0, st = 0, z = 5, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 0 }
			for k, v in extra or {} do
				r[k] = v
			end
			return r
		end
		local function fence(extra)
			local c = { now = 1000, carried = "", waiting = "", returnedThisRush = {}, moonBoopable = false }
			for k, v in extra or {} do
				c[k] = v
			end
			return c
		end

		it("4 squishies curieux, 2 si le ranch a été boopé au Rush précédent", function()
			expect(RR.fenceCount(false)).toBe(4)
			expect(RR.fenceCount(true)).toBe(2)
		end)

		it("éligibilité : chaque exclusion du GDD §4.21.4", function()
			expect(RR.fenceEligible(rec(), fence(), "u1")).toBe(true)
			expect(RR.fenceEligible(rec({ bf = 1 }), fence(), "u1")).toBe(false)
			expect(RR.fenceEligible(rec(), fence({ carried = "u1" }), "u1")).toBe(false)
			expect(RR.fenceEligible(rec({ at = "pool" }), fence(), "u1")).toBe(false)
			expect(RR.fenceEligible(rec({ at = "dodo" }), fence(), "u1")).toBe(false)
			expect(RR.fenceEligible(rec({ at = "mail" }), fence(), "u1")).toBe(false)
			expect(RR.fenceEligible(rec(), fence({ waiting = "u1" }), "u1")).toBe(false)
			expect(RR.fenceEligible(rec({ b = 941 }), fence(), "u1")).toBe(false) -- né il y a 59 s
			expect(RR.fenceEligible(rec({ b = 940 }), fence(), "u1")).toBe(true)
			expect(RR.fenceEligible(rec(), fence({ returnedThisRush = { u1 = true } }), "u1")).toBe(false)
			expect(RR.fenceEligible(rec({ s = 8 }), fence(), "u1")).toBe(false) -- Mythique hors Lune
			expect(RR.fenceEligible(rec({ s = 8 }), fence({ moonBoopable = true }), "u1")).toBe(true)
			expect(RR.fenceEligible(rec({ s = 25 }), fence(), "u1")).toBe(false) -- Secret
			-- un autre squishy porté n'empêche rien
			expect(RR.fenceEligible(rec(), fence({ carried = "u2" }), "u1")).toBe(true)
		end)

		it("sans uid : refus dès qu'un squishy est porté, en attente ou rentré (côté sûr)", function()
			expect(RR.fenceEligible(rec(), fence())).toBe(true)
			expect(RR.fenceEligible(rec(), fence({ carried = "u2" }))).toBe(false)
			expect(RR.fenceEligible(rec({ uid = "u1" }), fence({ carried = "u2" }))).toBe(true)
			expect(RR.fenceEligible(nil, fence(), "u1")).toBe(false)
			expect(RR.fenceEligible(rec({ b = 0 / 0 }), fence(), "u1")).toBe(false)
		end)

		it("Wild Wobblers partagés : 3 + 2 × max(0, 6 − N)", function()
			expect(RR.wildShared(16)).toBe(3)
			expect(RR.wildShared(5)).toBe(5)
			expect(RR.wildShared(1)).toBe(13)
			expect(RR.wildShared(0)).toBe(13)
			expect(RR.wildShared(0 / 0)).toBe(13)
		end)

		it("bébé du Rush : min(10 % de l'original, 2 × plus gros du receveur), minimum 1", function()
			expect(RR.babySize(1000, 1e6)).toBe(100)
			expect(RR.babySize(1e12, 50)).toBe(100)
			expect(RR.babySize(3, 1)).toBe(1)
			expect(RR.babySize(0 / 0, 0 / 0)).toBe(1)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
