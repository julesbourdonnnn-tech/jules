--!nocheck
-- SizeScale (paquet logic, docs/04 §12.1, GDD §4.2, §4.12) : table d'échelle du GDD et plafonds.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local SizeScale = h:require("ReplicatedStorage.Shared.Logic.SizeScale")

	describe("SizeScale", function()
		it("table du GDD §4.2 : échelle et diamètre", function()
			local rows = {
				{ 1, 1, 2 },
				{ 100, 2.2, 4.4 },
				{ 1e6, 4.6, 9.2 },
				{ 1e9, 6.4, 12.8 },
				{ 1e12, 8.2, 16.4 },
				{ 1e15, 10, 20 },
				{ 1e30, 19, 38 },
			}
			for _, row in rows do
				expect(SizeScale.scale(row[1])).toBeNear(row[2], 1e-9)
				expect(SizeScale.diameter(row[1])).toBeNear(row[3], 1e-9)
			end
			-- selle à 1 200 : 2,85× (arrondi du GDD)
			expect(SizeScale.scale(1200)).toBeNear(2.85, 0.01)
		end)

		it("1× pour S ≤ 1, NaN et valeurs bizarres → 1", function()
			expect(SizeScale.scale(0.5)).toBe(1)
			expect(SizeScale.scale(-5)).toBe(1)
			expect(SizeScale.scale(0 / 0)).toBe(1)
			expect(SizeScale.scale(nil)).toBe(1)
			expect(SizeScale.scale(-math.huge)).toBe(1)
			-- +inf est borné à 1e300 : échelle finie
			expect(SizeScale.scale(math.huge)).toBeNear(1 + 0.6 * 300, 1e-9)
		end)

		it("display : enclos et Bassin plafonnés à 4×", function()
			expect(SizeScale.display(1e6, "pen")).toBe(4)
			expect(SizeScale.display(1e6, "pool")).toBe(4)
			expect(SizeScale.display(100, "pen")).toBeNear(2.2, 1e-9)
		end)

		it("display : monture fixée par la selle (2,85 / 3,5 / 4), jamais par la taille", function()
			expect(SizeScale.display(1, "ride", 1)).toBe(2.85)
			expect(SizeScale.display(1e30, "ride", 1)).toBe(2.85)
			expect(SizeScale.display(1, "ride", 2)).toBe(3.5)
			expect(SizeScale.display(1, "ride", 3)).toBe(4)
			-- sans selle valide : jamais plus que l'enclos
			expect(SizeScale.display(1e30, "ride", 0)).toBe(4)
			expect(SizeScale.display(1e30, "ride", 0 / 0)).toBe(4)
		end)

		it("display : silhouette et statue plafonnées à 19×, « free » sans plafond", function()
			expect(SizeScale.display(1e40, "silhouette")).toBe(19)
			expect(SizeScale.display(1e40, "statue")).toBe(19)
			expect(SizeScale.display(1e40, "free")).toBeNear(1 + 0.6 * 40, 1e-9)
		end)

		it("overCap : couronne de taille au-delà du plafond de l'enclos", function()
			expect(SizeScale.overCap(1e5, "pen")).toBe(false) -- 4×
			expect(SizeScale.overCap(1.1e5, "pen")).toBe(true)
			expect(SizeScale.overCap(1e30, "statue")).toBe(false)
			expect(SizeScale.overCap(1e31, "statue")).toBe(true)
			expect(SizeScale.overCap(1e300, "free")).toBe(false)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
