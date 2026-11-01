--!nocheck
-- FusionRules (paquet logic, docs/04 §12.1, GDD §4.10) : jumeaux, fusion, combo, Tout fusionner.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local FR = h:require("ReplicatedStorage.Shared.Logic.FusionRules")

	local function rec(s, st, z, at, extra)
		local r =
			{ s = s, m = 0, st = st, z = z, zg = 0, bf = 0, lk = false, o = "", at = at or "pen", b = 100 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	describe("FusionRules", function()
		it("jumeaux : même espèce ET mêmes étoiles (mutation libre)", function()
			expect(FR.areTwins(rec(1, 0, 1), rec(1, 0, 5, "pool", { m = 4 }))).toBe(true)
			expect(FR.areTwins(rec(1, 0, 1), rec(1, 1, 1))).toBe(false)
			expect(FR.areTwins(rec(1, 0, 1), rec(2, 0, 1))).toBe(false)
			expect(FR.areTwins(rec(1, 0, 1), nil)).toBe(false)
		end)

		it("fusion de l'accueil : (96 + 41) × 1,25 = 171,25, une étoile, marque zg = G", function()
			local a = rec(1, 0, 96, "pool", { bf = 1, b = 10 })
			local b = rec(1, 0, 41, "pen", { b = 50 })
			local r = FR.fuse(a, b, 0, 999)
			expect(r.z).toBeNear(171.25, 1e-9)
			expect(r.st).toBe(1)
			expect(r.zg).toBe(0)
			expect(r.bf).toBe(1)
			expect(r.at).toBe("pool")
			expect(r.b).toBe(10) -- naissance de la ligne gardée
		end)

		it(
			"fusion : tailles à G, meilleure mutation, verrou et tenue gardés, 5 étoiles au plus",
			function()
				local a = rec(3, 5, 10, "pen", { zg = 100, m = 2, lk = true, b = 5 })
				local b = rec(3, 5, 20, "dodo", { m = 5, o = "sweater", b = 9 })
				local r = FR.fuse(a, b, 300, 1000)
				-- a : 10 + (300 − 100) = 210 ; b au Dodo : 20 → (210 + 20) × 1,25
				expect(r.z).toBeNear(287.5, 1e-9)
				expect(r.zg).toBe(300)
				expect(r.m).toBe(5)
				expect(r.st).toBe(5)
				expect(r.lk).toBe(true)
				expect(r.o).toBe("sweater")
			end
		)

		it("keepUid : Meilleur Ami d'abord, puis le plus ancien, puis le plus petit uid", function()
			expect(
				FR.keepUid("a", "b", rec(1, 0, 1, "pen", { b = 50 }), rec(1, 0, 1, "pen", { bf = 2, b = 99 }))
			).toBe("b")
			expect(FR.keepUid("a", "b", rec(1, 0, 1, "pen", { bf = 2 }), rec(1, 0, 1, "pen", { bf = 1 }))).toBe(
				"b"
			)
			expect(FR.keepUid("a", "b", rec(1, 0, 1, "pen", { b = 50 }), rec(1, 0, 1, "pen", { b = 20 }))).toBe(
				"b"
			)
			expect(FR.keepUid("z", "10", rec(1, 0, 1), rec(1, 0, 1))).toBe("z") -- « z » (35) avant « 10 » (36)
			expect(FR.keepUid("b", "a", rec(1, 0, 1), rec(1, 0, 1))).toBe("a")
		end)

		it("nextInChain : jumeau du résultat qui attend dans le Bassin (plus petit uid d'abord)", function()
			local pool = {
				r = rec(1, 1, 10, "pool"),
				x = rec(1, 1, 5, "pool"),
				c = rec(1, 1, 5, "pool"),
				y = rec(1, 2, 5, "pool"),
				p = rec(1, 1, 5, "pen"),
			}
			expect(FR.nextInChain(pool, "r")).toBe("c")
			expect(FR.nextInChain(pool, "y")).toBeNil()
			expect(FR.nextInChain(pool, "missing")).toBeNil()
		end)

		it("throwOutcome : fusion si un jumeau attend, sinon place libre, sinon plein", function()
			local pool = { a = rec(1, 0, 1, "pool"), b = rec(2, 0, 1, "pool") }
			expect(FR.throwOutcome(pool, rec(1, 0, 1), 5)).toBe("fuse")
			expect(FR.throwOutcome(pool, rec(3, 0, 1), 5)).toBe("place")
			expect(FR.throwOutcome(pool, rec(3, 0, 1), 2)).toBe("full")
			expect(FR.throwOutcome(pool, rec(1, 0, 1), 2)).toBe("fuse") -- plein mais jumeau : fusion
		end)

		it(
			"exemple du GDD : Plop 0★, 1★, 2★ dans le Bassin, on lance un 0★ → combo de 3",
			function()
				local records = {
					a = rec(1, 0, 1, "pool", { b = 1 }),
					b = rec(1, 1, 1, "pool", { b = 2 }),
					c = rec(1, 2, 1, "pool", { b = 3 }),
					d = rec(1, 0, 1, "pen", { b = 4 }),
				}
				local plan = FR.planMergeAll(records, 5)
				expect(#plan).toBe(3)
				expect(plan[1]).toEqual({ "a", "d" })
				-- chaque paire suivante part de l'uid gardé de l'étape précédente
				local kept = FR.keepUid("a", "d", records.a, records.d)
				expect(plan[2][1]).toBe(kept)
				expect(plan[2][2]).toBe("b")
				expect(FR.comboSteps(plan, records)).toEqual({ 1, 2, 3 })
			end
		)

		it("Tout fusionner : verrouillés et Lettres exclus, chaîne limitée par les places", function()
			local records = {
				a = rec(1, 0, 1, "pen", { b = 1 }),
				b = rec(1, 0, 1, "pen", { b = 2, lk = true }),
				c = rec(1, 0, 1, "mail", { b = 3 }),
				d = rec(2, 0, 1, "dodo", { b = 4 }),
				e = rec(2, 0, 1, "pen", { b = 5 }),
				f = rec(2, 1, 1, "pen", { b = 6 }),
				g = rec(2, 2, 1, "pen", { b = 7 }),
			}
			local plan = FR.planMergeAll(records, 5)
			-- espèce 1 : aucun jumeau utilisable ; espèce 2 : d + e → 1★, + f → 2★, + g → 3★
			expect(#plan).toBe(3)
			for _, pair in plan do
				for _, uid in pair do
					expect(uid ~= "b" and uid ~= "c").toBe(true)
				end
			end
			expect(FR.comboSteps(plan, records)).toEqual({ 1, 2, 3 })
			-- une seule place dans le Bassin : même nombre de fusions, mais trois combos de 1
			local short = FR.planMergeAll(records, 1)
			expect(#short).toBe(3)
			expect(FR.comboSteps(short, records)).toEqual({ 1, 1, 1 })
		end)

		it("pastille ♥ N : paires de jumeaux hors Lettres et hors verrouillés", function()
			local records = {
				a = rec(1, 0, 1),
				b = rec(1, 0, 1, "dodo"),
				c = rec(1, 0, 1, "pool"),
				d = rec(1, 0, 1, "mail"),
				e = rec(2, 3, 1),
				f = rec(2, 3, 1, "pen", { lk = true }),
			}
			expect(FR.twinPairs(records)).toBe(1)
			expect(FR.twinPairs(nil)).toBe(0)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
