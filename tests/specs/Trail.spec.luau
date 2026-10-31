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

	-- -----------------------------------------------------------------------------------------
	-- Extension « logic » (docs/04-architecture.md §12.1, GDD §4.7, §12.4, §12.9)
	-- -----------------------------------------------------------------------------------------

	describe("Trail — numérotation des miettes (PathStream)", function()
		it("push numérote les points de façon contiguë à partir de firstSeq", function()
			local trail = Trail.new(170, 1.0, 5)
			expect(trail.firstSeq).toBe(5)
			expect(trail:lastSeq()).toBe(4) -- vide
			trail:push(V3.new(0, 3, 0))
			expect(trail:lastSeq()).toBe(5)
			trail:push(V3.new(0, 3, 0.4)) -- sous le pas minimal : ignoré, pas de numéro
			expect(trail:lastSeq()).toBe(5)
			trail:push(V3.new(0, 3, 1))
			trail:push(V3.new(0, 3, 2))
			expect(trail:lastSeq()).toBe(7)
			expect(trail.firstSeq).toBe(5)
			local first, pts = trail:since(6)
			expect(first).toBe(6)
			expect(#pts).toBe(2)
			expect(pts[2]).toEqual(V3.new(0, 3, 2))
			-- défaut : firstSeq = 1
			expect(Trail.new(10).firstSeq).toBe(1)
		end)

		it("le retrait des vieux points avance firstSeq ; la numérotation ne recule jamais", function()
			local trail = Trail.new(20, 1.0)
			local lastSeen = trail:lastSeq()
			for i = 0, 200 do
				trail:push(V3.new(0, 3, i))
				local last = trail:lastSeq()
				expect(last >= lastSeen).toBe(true)
				lastSeen = last
				expect(trail.firstSeq + #trail.points - 1).toBe(last)
			end
			expect(trail:lastSeq()).toBe(201)
			expect(trail.firstSeq > 150).toBe(true)
			-- les points rendus correspondent bien à leur numéro
			local first, pts = trail:since(0)
			expect(first).toBe(trail.firstSeq)
			for i, p in pts do
				expect(p.Z).toBe(first + i - 2) -- point n° s poussé à Z = s − 1
			end
		end)

		it("un saut ≥ 40 studs remet l'historique à zéro sans casser la numérotation", function()
			local trail = Trail.new(170, 1.0, 100)
			for i = 0, 10 do
				trail:push(V3.new(i, 3, 0))
			end
			expect(trail:lastSeq()).toBe(110)
			trail:push(V3.new(500, 3, 500))
			expect(#trail.points).toBe(1)
			expect(trail.firstSeq).toBe(111)
			expect(trail:lastSeq()).toBe(111)
			-- reset explicite : continue par défaut, ou reprend au numéro fourni (PathSnapshot)
			trail:reset(V3.new(0, 3, 0))
			expect(trail.firstSeq).toBe(112)
			trail:reset(V3.new(0, 3, 0), 9000)
			expect(trail.firstSeq).toBe(9000)
			expect(trail:lastSeq()).toBe(9000)
			trail:reset(V3.new(0, 3, 0), 0 / 0)
			expect(trail.firstSeq).toBe(9001)
		end)

		it("since : borné aux points présents, maxCount garde les plus récents", function()
			local trail = Trail.new(170, 1.0, 1)
			for i = 0, 9 do
				trail:push(V3.new(0, 3, i)) -- numéros 1 … 10
			end
			local first, pts = trail:since(8)
			expect(first).toBe(8)
			expect(#pts).toBe(3)
			first, pts = trail:since(-50)
			expect(first).toBe(1)
			expect(#pts).toBe(10)
			first, pts = trail:since(1, 4)
			expect(first).toBe(7)
			expect(#pts).toBe(4)
			expect(pts[4].Z).toBe(9)
			first, pts = trail:since(11)
			expect(first).toBe(11)
			expect(#pts).toBe(0)
			first, pts = trail:since(1, 0)
			expect(#pts).toBe(0)
			first, pts = trail:since(0 / 0)
			expect(first).toBe(1)
			expect(#pts).toBe(10)
			-- copie : modifier le résultat ne touche pas l'historique
			pts[1] = V3.new(99, 99, 99)
			expect(trail.points[1]).toEqual(V3.new(0, 3, 0))
		end)

		it("miettes réseau : un point par stud parcouru (sous-échantillonnage à 1 stud)", function()
			local net = Trail.new(170, 1.0)
			local server = Trail.new(170, 0.5)
			for i = 0, 400 do
				local p = V3.new(i * 0.25, 3, 0) -- 100 studs à 0,25 stud par tick
				net:push(p)
				server:push(p)
			end
			expect(#net.points).toBe(101)
			expect(#server.points).toBe(201)
			for i = 2, #net.points do
				expect((net.points[i] - net.points[i - 1]).Magnitude).toBeNear(1, 1e-6)
			end
		end)
	end)

	-- Distance XZ d'un point à un segment (référence scalaire, sans allocation)
	local function pointSegmentXZ(px, pz, ax, az, bx, bz)
		local dx, dz = bx - ax, bz - az
		local len2 = dx * dx + dz * dz
		local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
		local cx, cz = ax + dx * t - px, az + dz * t - pz
		return math.sqrt(cx * cx + cz * cz)
	end

	describe("Trail.segmentDistanceXZ", function()
		it("segments qui se croisent : distance 0 au point d'intersection", function()
			local d, s, t =
				Trail.segmentDistanceXZ(V3.new(-1, 0, 0), V3.new(1, 0, 0), V3.new(0, 0, -1), V3.new(0, 0, 3))
			expect(d).toBeNear(0, 1e-9)
			expect(s).toBeNear(0.5, 1e-9)
			expect(t).toBeNear(0.25, 1e-9)
		end)

		it("parallèles, extrémités, segments dégénérés ; Y ignoré", function()
			local d = Trail.segmentDistanceXZ(
				V3.new(0, 0, 0),
				V3.new(10, 0, 0),
				V3.new(2, 50, 3),
				V3.new(8, -50, 3)
			)
			expect(d).toBeNear(3, 1e-9)
			local s, t
			d, s, t =
				Trail.segmentDistanceXZ(V3.new(0, 0, 0), V3.new(1, 0, 0), V3.new(4, 0, 4), V3.new(4, 0, 8))
			expect(d).toBeNear(5, 1e-9)
			expect(s).toBe(1)
			expect(t).toBe(0)
			d, s, t =
				Trail.segmentDistanceXZ(V3.new(1, 0, 1), V3.new(1, 0, 1), V3.new(4, 0, 5), V3.new(4, 0, 5))
			expect(d).toBeNear(5, 1e-9)
			d = Trail.segmentDistanceXZ(V3.new(0, 0, 0), V3.new(0, 0, 0), V3.new(-5, 0, 2), V3.new(5, 0, 2))
			expect(d).toBeNear(2, 1e-9)
			d = Trail.segmentDistanceXZ(V3.new(-5, 0, 2), V3.new(5, 0, 2), V3.new(0, 0, 0), V3.new(0, 0, 0))
			expect(d).toBeNear(2, 1e-9)
			-- colinéaires qui se recouvrent
			d = Trail.segmentDistanceXZ(V3.new(0, 0, 0), V3.new(10, 0, 0), V3.new(5, 0, 0), V3.new(15, 0, 0))
			expect(d).toBeNear(0, 1e-9)
		end)

		it("concorde avec un échantillonnage dense sur 400 paires aléatoires", function()
			local rng = h.globals.Random.new(11)
			local function rv()
				return V3.new(rng:NextNumber() * 20 - 10, 0, rng:NextNumber() * 20 - 10)
			end
			for _ = 1, 400 do
				local a0, a1, b0, b1 = rv(), rv(), rv(), rv()
				local d, s, t = Trail.segmentDistanceXZ(a0, a1, b0, b1)
				expect(s >= 0 and s <= 1 and t >= 0 and t <= 1).toBe(true)
				local pa = a0 + (a1 - a0) * s
				local pb = b0 + (b1 - b0) * t
				expect((pa - pb).Magnitude).toBeNear(d, 1e-4)
				-- référence : points d'un segment contre l'autre segment (distance exacte), 200 pas
				local best = math.huge
				for i = 0, 200 do
					local u = i / 200
					local ax, az = a0.X + (a1.X - a0.X) * u, a0.Z + (a1.Z - a0.Z) * u
					local bx, bz = b0.X + (b1.X - b0.X) * u, b0.Z + (b1.Z - b0.Z) * u
					best = math.min(best, pointSegmentXZ(ax, az, b0.X, b0.Z, b1.X, b1.Z))
					best = math.min(best, pointSegmentXZ(bx, bz, a0.X, a0.Z, a1.X, a1.Z))
				end
				expect(d <= best + 1e-4).toBe(true)
				expect(best - d < 0.15).toBe(true)
			end
		end)
	end)

	describe("Trail.findCutSwept", function()
		local function straightLine(n)
			local nodes = {}
			for i = 1, n do
				nodes[i] = V3.new(0, 3, -(3 + (i - 1) * 2.6))
			end
			return nodes
		end

		it("premier segment k ≥ max(2, firstSegment) dans le rayon, point touché sur la file", function()
			local nodes = straightLine(10)
			local k, p = Trail.findCutSwept(nodes, V3.new(-5, 3, -14), V3.new(5, 3, -14), 2.8, 1)
			-- nœud 5 à −13,4 : segment 5 = [nœud 4, nœud 5] à 0,6 stud
			expect(k).toBe(5)
			expect(p.Z).toBeNear(-13.4, 1e-4)
			expect((Trail.findCutSwept(nodes, V3.new(-5, 3, -14), V3.new(5, 3, -14), 2.8, 7))).toBe(7)
			expect((Trail.findCutSwept(nodes, V3.new(-5, 3, -14), V3.new(5, 3, -14), 2.8, 11))).toBeNil()
			expect((Trail.findCutSwept(nodes, V3.new(-5, 3, -14), V3.new(5, 3, -14), 0 / 0, 1))).toBeNil()
			expect((Trail.findCutSwept(nodes, V3.new(0 / 0, 3, -14), V3.new(5, 3, -14), 2.8, 1))).toBeNil()
			expect((Trail.findCutSwept({}, V3.zero, V3.one, 2.8, 1))).toBeNil()
		end)

		it("|Δy| > maxDy (4 par défaut) : pas de coupe ; skip ignore un segment", function()
			local nodes = straightLine(10)
			expect((Trail.findCutSwept(nodes, V3.new(-5, 7.5, -14), V3.new(5, 7.5, -14), 2.8, 2))).toBeNil()
			expect((Trail.findCutSwept(nodes, V3.new(-5, 6.9, -14), V3.new(5, 6.9, -14), 2.8, 2))).toBe(5)
			expect((Trail.findCutSwept(nodes, V3.new(-5, 7.5, -14), V3.new(5, 7.5, -14), 2.8, 2, 10))).toBe(5)
			local skipped = {}
			local k = Trail.findCutSwept(
				nodes,
				V3.new(-5, 3, -14),
				V3.new(5, 3, -14),
				2.8,
				2,
				nil,
				function(seg, point)
					table.insert(skipped, seg)
					expect(typeof(point)).toBe("Vector3")
					return seg == 5
				end
			)
			expect(k).toBe(6)
			expect(skipped).toEqual({ 5, 6 })
		end)

		it("à 3,6 studs par tick (Dash), aucun segment n'est raté (comparaison au test continu)", function()
			local rng = h.globals.Random.new(3)
			local missedByPoints = 0
			for _ = 1, 200 do
				-- file sinueuse
				local nodes = {}
				local p = V3.new(0, 3, 0)
				local heading = rng:NextNumber() * math.pi * 2
				for i = 1, 20 do
					heading += (rng:NextNumber() - 0.5) * 0.6
					p += V3.new(math.cos(heading), 0, math.sin(heading)) * 2.6
					nodes[i] = p
				end
				-- trajectoire du coupeur : 6 ticks de 3,6 studs dans une direction aléatoire
				local a = rng:NextNumber() * math.pi * 2
				local dir = V3.new(math.cos(a), 0, math.sin(a))
				local start = nodes[10]
					- dir * 10.8
					+ V3.new(rng:NextNumber() * 6 - 3, 0, rng:NextNumber() * 6 - 3)
				local prev = start
				for tick = 1, 6 do
					local cur = start + dir * (3.6 * tick)
					local k = Trail.findCutSwept(nodes, prev, cur, 2.8, 4)
					-- référence continue : 100 échantillons sur le balayage (distance point-segment exacte)
					local hit = false
					for seg = 4, 20 do
						local s0, s1 = nodes[seg - 1], nodes[seg]
						for j = 0, 100 do
							local u = j / 100
							local qx = prev.X + (cur.X - prev.X) * u
							local qz = prev.Z + (cur.Z - prev.Z) * u
							if pointSegmentXZ(qx, qz, s0.X, s0.Z, s1.X, s1.Z) <= 2.8 - 1e-3 then
								hit = true
								break
							end
						end
						if hit then
							break
						end
					end
					if hit then
						expect(k).toBeTruthy()
						-- le test par points de l'ancien findCut aurait pu rater ce passage
						local pointHit = Trail.findCut(nodes, { cur }, 2.8, 4)
						if pointHit == nil then
							missedByPoints += 1
						end
					end
					prev = cur
				end
			end
			-- le test balayé rattrape des passages que le seul point d'arrivée ne voit pas
			expect(missedByPoints > 0).toBe(true)
		end)
	end)
end
