--!nocheck
-- Props_MegaRules (paquet logic, docs/04 §17.1 couche a) : objectif croissant en N, indulgence qui ne
-- remonte jamais, paliers monotones, fenêtre PERFECT exacte, espèce dans la rotation.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local MR = h:require("ReplicatedStorage.Shared.Logic.MegaRules")
	local any = Props.anyNumber()

	describe("Props › MegaRules", function()
		it("target : entier ≥ 1, croissant en N, décroissant en échecs", function()
			Props.check(4000, Props.tuple(Props.int(0, 64), Props.int(0, 5)), function(v)
				local t = MR.target(v[1], v[2])
				return t >= 1
					and t % 1 == 0
					and MR.target(v[1] + 1, v[2]) > t
					and MR.target(v[1], v[2] + 1) <= t
			end)
			Props.check(2000, Props.tuple(any, any), function(v)
				local t = MR.target(v[1], v[2])
				return t == t and t >= 1 and math.abs(t) ~= math.huge
			end)
		end)

		it("babiesFor ∈ {0, 1, 2, 3}, croissant en points", function()
			Props.check(4000, Props.tuple(any, any), function(v)
				local a, b = MR.babiesFor(v[1]), MR.babiesFor(v[2])
				if not (a >= 0 and a <= 3 and a % 1 == 0) then
					return false
				end
				if v[1] == v[1] and v[2] == v[2] and v[1] <= v[2] then
					return a <= b
				end
				return true
			end)
		end)

		it("isPerfect ⇔ écart au sommet le plus proche dans [−0,12 ; +0,28]", function()
			Props.check(6000, Props.tuple(Props.number(0, 1e6), Props.number(0, 70)), function(v)
				local landsAt, dt = v[1], v[2]
				local t = landsAt + dt
				local k = math.floor((t - landsAt - 1) / 2 + 0.5)
				local apex = landsAt + 1 + 2 * k
				local delta = t - apex
				local expected = (delta >= -0.12 - 1e-9 and delta <= 0.28 + 1e-9)
					and t >= landsAt + 1 - 0.12 - 1e-9
				local got = MR.isPerfect(landsAt, t)
				-- tolérance d'arrondi : on ne juge pas les instants à 1e-6 s d'une borne
				if math.abs(delta + 0.12) < 1e-6 or math.abs(delta - 0.28) < 1e-6 then
					return true
				end
				return got == expected
			end)
		end)

		it(
			"phase ∈ [0 ; 1[, nextApex ≥ t, species ∈ [1 ; 24] (24 espèces non secrètes au lancement)",
			function()
				Props.check(4000, Props.tuple(any, any), function(v)
					local p = MR.phase(v[1], v[2])
					local s = MR.species(v[1], v[2])
					local a = MR.nextApex(v[1], v[2])
					local ok = p >= 0 and p < 1 and s >= 1 and s <= 24 and s % 1 == 0 and a == a
					local finite = type(v[1]) == "number"
						and type(v[2]) == "number"
						and v[1] == v[1]
						and v[2] == v[2]
						and math.abs(v[1]) < 1e15
						and math.abs(v[2]) < 1e15
					if finite then
						ok = ok and a >= v[2] - 1e-6
					end
					return ok
				end)
			end
		)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
