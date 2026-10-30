--!nocheck
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local Trail = h:require("ReplicatedStorage.Shared.Logic.Trail")
	local V3 = h.globals.Vector3

	local function walkStraight(trail, from, to, step)
		local dir = (to - from).Unit
		local dist = (to - from).Magnitude
		local d = 0
		while d <= dist do
			trail:push(from + dir * d)
			d += step
		end
	end

	describe("Trail", function()
		it("place les suiveurs à espacement régulier sur une ligne droite", function()
			local trail = Trail.new(100)
			walkStraight(trail, V3.new(0, 0, 0), V3.new(0, 0, 50), 0.25)
			local pos = trail:sample(5, 3, 2)
			expect(#pos).toBe(5)
			local head = trail:head()
			expect((head - pos[1]).Magnitude).toBeNear(2, 0.3)
			for i = 2, 5 do
				expect((pos[i - 1] - pos[i]).Magnitude).toBeNear(3, 0.3)
			end
		end)

		it("suit les virages (les suiveurs restent sur le chemin)", function()
			local trail = Trail.new(200)
			walkStraight(trail, V3.new(0, 0, 0), V3.new(20, 0, 0), 0.5)
			walkStraight(trail, V3.new(20, 0, 0), V3.new(20, 0, 20), 0.5)
			local pos = trail:sample(10, 3, 3)
			-- les 6 premiers sont sur la branche Z (x≈20), les suivants sur la branche X (z≈0)
			expect(pos[1].X).toBeNear(20, 0.01)
			expect(pos[10].Z).toBeNear(0, 0.6)
		end)

		it("borne l'historique à maxLength", function()
			local trail = Trail.new(30)
			walkStraight(trail, V3.new(0, 0, 0), V3.new(0, 0, 500), 0.5)
			expect(trail.length).toBeLessThan(32)
			expect(#trail.points).toBeLessThan(70)
		end)

		it("empile les suiveurs au bout si l'historique est trop court (jamais nil/NaN)", function()
			local trail = Trail.new(100)
			walkStraight(trail, V3.new(0, 0, 0), V3.new(0, 0, 4), 0.5)
			local pos = trail:sample(8, 3, 2)
			expect(#pos).toBe(8)
			for _, p in pos do
				expect(p.X == p.X and p.Z == p.Z).toBe(true)
			end
			expect(pos[8]).toEqual(trail.points[1])
		end)

		it("ignore les NaN et repart de zéro après une téléportation", function()
			local trail = Trail.new(100)
			walkStraight(trail, V3.new(0, 0, 0), V3.new(0, 0, 10), 0.5)
			trail:push(V3.new(0 / 0, 0, 0))
			expect(trail:head().Z).toBeNear(10, 0.6)
			trail:push(V3.new(500, 0, 500))
			expect(#trail.points).toBe(1)
			expect(trail.length).toBe(0)
		end)

		it("historique vide ou un seul point", function()
			local trail = Trail.new(10)
			expect(#trail:sample(3, 2)).toBe(0)
			trail:push(V3.new(1, 2, 3))
			local pos = trail:sample(3, 2)
			expect(pos[3]).toEqual(V3.new(1, 2, 3))
		end)
	end)

	describe("Trail.findCut", function()
		it("trouve le premier suiveur touché au-delà des protégés", function()
			local positions = {}
			for i = 1, 10 do
				positions[i] = V3.new(0, 0, i * 3)
			end
			local idx = Trail.findCut(positions, { V3.new(0.5, 0, 6) }, 2, 1)
			expect(idx).toBe(2)
			-- les 3 premiers sont protégés (trio de tête)
			idx = Trail.findCut(positions, { V3.new(0.5, 0, 6) }, 2, 4)
			expect(idx).toBeNil()
			idx = Trail.findCut(positions, { V3.new(0, 0, 100), V3.new(1, 0, 21) }, 2, 4)
			expect(idx).toBe(7)
		end)

		it("sauter au-dessus de la file ne la coupe pas", function()
			local positions = { V3.new(0, 0, 3), V3.new(0, 0, 6) }
			expect(Trail.findCut(positions, { V3.new(0, 8, 6) }, 2, 1)).toBeNil()
		end)
	end)
end
