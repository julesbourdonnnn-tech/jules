--!nocheck
-- Props_SizeScale (paquet logic, docs/04 §17.1 couche a) : échelle finie, ≥ 1, monotone, plafonnée.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local SizeScale = h:require("ReplicatedStorage.Shared.Logic.SizeScale")
	local wheres = Props.oneOf({ "pen", "pool", "ride", "silhouette", "statue", "free", "???", nil })

	local function finite(x)
		return type(x) == "number" and x == x and math.abs(x) ~= math.huge
	end

	describe("Props › SizeScale", function()
		it("scale et diameter : finis, ≥ 1 (≥ 2 studs), pour toute entrée", function()
			Props.check(5000, Props.any(), function(v)
				local s, d = SizeScale.scale(v), SizeScale.diameter(v)
				return finite(s) and s >= 1 and finite(d) and d >= 2
			end)
		end)

		it("scale : monotone", function()
			Props.check(5000, Props.tuple(Props.anyNumber(), Props.anyNumber()), function(v)
				local a, b = v[1], v[2]
				if not (a == a and b == b) then
					return true
				end
				local lo, hi = math.min(a, b), math.max(a, b)
				return SizeScale.scale(lo) <= SizeScale.scale(hi)
			end)
		end)

		it("display : finie, ≥ 1, ≤ échelle libre, plafonds respectés", function()
			Props.check(
				5000,
				Props.tuple(Props.anyNumber(), wheres, Props.maybe(Props.anyNumber())),
				function(v)
					local d = SizeScale.display(v[1], v[2], v[3])
					if not (finite(d) and d >= 1) then
						return false
					end
					if v[2] == "pen" or v[2] == "pool" then
						return d <= 4
					elseif v[2] == "silhouette" or v[2] == "statue" then
						return d <= 19
					elseif v[2] == "ride" then
						return d <= 4
					end
					return d <= SizeScale.scale(v[1]) + 1e-9
				end
			)
		end)

		it("overCap : vrai seulement si l'échelle dépasse l'affichage du lieu", function()
			Props.check(
				5000,
				Props.tuple(Props.anyNumber(), Props.oneOf({ "pen", "pool", "silhouette", "statue", "free" })),
				function(v)
					local over = SizeScale.overCap(v[1], v[2])
					local s, d = SizeScale.scale(v[1]), SizeScale.display(v[1], v[2])
					return over == (s > d)
				end
			)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
