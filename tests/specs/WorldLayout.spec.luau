--!nocheck
-- WorldLayout (paquet logic, docs/04 §3, §12.1, GDD §11) : plan de Wobbleton. Repères des ranchs,
-- positions des objets, graphe des rues (jamais dans un ranch ni dans une maison), solides (plateau,
-- murs de 30 studs, collés ou à ≥ 6 studs), sol des règles (supportY).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local roblox = require("@lune/roblox")
	local Vector3 = roblox.Vector3

	local h = Harness.new()
	local W = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	local Pads = h:require("ReplicatedStorage.Shared.Config.Pads")
	local C = W.Const

	local function flat(a, b)
		local dx, dz = a.X - b.X, a.Z - b.Z
		return math.sqrt(dx * dx + dz * dz)
	end
	local function radius(p)
		return math.sqrt(p.X * p.X + p.Z * p.Z)
	end

	-- les Vector3 de Roblox (et de Lune) sont en flottants 32 bits : tolérance de 1e-3 stud
	describe("WorldLayout › ranchs", function()
		it(
			"16 ranchs : portail à r = 178, centré sur 22,5° × (k − 1) + 11,25°, tourné vers la place",
			function()
				for slot = 1, 16 do
					local gate = W.anchor(slot, "gate")
					expect(radius(gate)).toBeNear(178, 1e-3)
					local angle = math.deg(math.atan2(gate.Z, gate.X)) % 360
					expect(angle).toBeNear((22.5 * (slot - 1) + 11.25) % 360, 1e-3)
					local cf = W.ranchCFrame(slot)
					-- LookVector vers la place : le centre est devant
					local toCenter = (Vector3.zero - cf.Position).Unit
					expect(cf.LookVector:Dot(toCenter)).toBeNear(1, 1e-3)
					expect(cf.UpVector.Y).toBeNear(1, 1e-9)
				end
			end
		)

		it("toWorld / toLocal : aller-retour exact, Z local vers le fond", function()
			for slot = 1, 16 do
				for _, p in
					{
						Vector3.new(0, 0, 0),
						Vector3.new(-32, 5, 72),
						Vector3.new(12.5, 0, -6),
						Vector3.new(31, 2, 1),
					}
				do
					local back = W.toLocal(slot, W.toWorld(slot, p))
					expect((back - p).Magnitude < 1e-3).toBe(true)
				end
				local deep = W.toWorld(slot, Vector3.new(0, 0, 72))
				expect(radius(deep)).toBeNear(250, 1e-3)
			end
		end)

		it("ranchAt / inRanch : intérieur, bords, rue, place, entre deux ranchs", function()
			for slot = 1, 16 do
				for _, p in
					{
						Vector3.new(0, 0, 30),
						Vector3.new(-31.9, 0, 0.1),
						Vector3.new(31.9, 0, 71.9),
						Vector3.new(0, 0, 0.1),
					}
				do
					local world = W.toWorld(slot, p)
					expect(W.ranchAt(world)).toBe(slot)
					expect(W.inRanch(slot, world)).toBe(true)
					expect(W.inRanch(slot % 16 + 1, world)).toBe(false)
				end
				expect(W.ranchAt(W.toWorld(slot, Vector3.new(0, 0, -0.1)))).toBe(0)
				expect(W.ranchAt(W.toWorld(slot, Vector3.new(32.5, 0, 10)))).toBe(0) -- dans la fente entre deux ranchs
				expect(W.ranchAt(W.toWorld(slot, Vector3.new(0, 0, 73)))).toBe(0)
			end
			expect(W.ranchAt(Vector3.zero)).toBe(0)
			expect(W.ranchAt(Vector3.new(0, 0, -284))).toBe(0) -- Prairie
			expect(W.ranchAt(Vector3.new(0 / 0, 0, 0))).toBe(0)
			expect(W.inRanch(17, Vector3.zero)).toBe(false)
		end)

		it("poussée d'un intrus : 6 studs devant le portail, hors de tout ranch", function()
			for slot = 1, 16 do
				local out = W.gateOutside(slot)
				expect(W.ranchAt(out)).toBe(0)
				expect(flat(out, W.anchor(slot, "gate"))).toBeNear(6, 1e-3)
				expect(W.toLocal(slot, out).Z).toBeNear(-6, 1e-3)
				expect(W.blocked(out.X, out.Z, 1)).toBe(false)
			end
		end)

		it("apparition : Z = 30, X = 0, dans le ranch, face au Pot", function()
			for slot = 1, 16 do
				local cf = W.spawnCFrame(slot)
				local l = W.toLocal(slot, cf.Position)
				expect(l.X).toBeNear(0, 1e-3)
				expect(l.Z).toBeNear(30, 1e-3)
				expect(cf.Position.Y).toBe(C.SpawnHeight)
				expect(W.ranchAt(cf.Position)).toBe(slot)
				local pot = W.anchor(slot, "pot")
				local dir = Vector3.new(pot.X - cf.Position.X, 0, pot.Z - cf.Position.Z).Unit
				expect(cf.LookVector:Dot(dir)).toBeNear(1, 1e-3)
			end
		end)

		it("objets du ranch aux positions du GDD §11.2 ; Fontaine côté rue", function()
			local expected = {
				pot = { -20, 6 },
				vat = { -20, 52 },
				pool = { 6, 52 },
				bowl = { 22, 58 },
				cushion = { 22, 10 },
				shelf = { 0, 70 },
				fountain = { 12, -6 },
				gate = { 0, 0 },
			}
			for slot = 1, 16 do
				for name, xz in expected do
					local l = W.toLocal(slot, W.anchor(slot, name))
					expect({
						name = name,
						x = math.floor(l.X * 100 + 0.5) / 100,
						z = math.floor(l.Z * 100 + 0.5) / 100,
					}).toEqual({ name = name, x = xz[1], z = xz[2] })
				end
				expect(W.ranchAt(W.anchor(slot, "fountain"))).toBe(0)
				expect(W.anchor(slot, "sign").Y).toBe(14)
				expect(W.anchor(slot, "silhouette").Y).toBe(40)
			end
		end)

		it(
			"dalles : 4 prises sur la rangée Z = 62 (+ la 5e réservée), dans le ranch, espacées",
			function()
				for slot = 1, 16 do
					local seen = {}
					for socket = 1, 5 do
						local p = W.padSocket(slot, socket)
						expect(W.ranchAt(p)).toBe(slot)
						for _, q in seen do
							expect(flat(p, q) >= 8).toBe(true)
						end
						table.insert(seen, p)
					end
					for _, def in Pads.Defs do
						expect(W.toLocal(slot, W.padSocket(slot, def.socket)).Z).toBeNear(62, 1e-3)
					end
					-- une dalle n'est jamais à portée d'achat du bol, du Pot ni du point d'apparition
					for socket = 1, 4 do
						local p = W.padSocket(slot, socket)
						expect(flat(p, W.anchor(slot, "bowl")) > 3.5 + 2).toBe(true)
						expect(flat(p, W.spawnCFrame(slot).Position) > 3.5).toBe(true)
					end
				end
			end
		)

		it(
			"enclos : 24 places dans la zone Z 8 … 44, à ≥ 8 studs l'une de l'autre, loin du Pot et du coussin",
			function()
				local slot = 7
				local places = {}
				for i = 1, 24 do
					local p = W.penSlot(slot, i)
					local l = W.toLocal(slot, p)
					expect(l.Z >= 8 + 4 - 1e-3 and l.Z <= 44 - 4 + 1e-3).toBe(true)
					expect(math.abs(l.X) <= 27 + 1e-3).toBe(true)
					for _, q in places do
						expect(flat(p, q) >= 8 - 1e-3).toBe(true)
					end
					expect(flat(p, W.anchor(slot, "pot")) >= 4 + 2.5).toBe(true)
					expect(flat(p, W.anchor(slot, "cushion")) >= 4 + 2).toBe(true)
					table.insert(places, p)
				end
				expect(W.penSlot(slot, 0)).toEqual(W.penSlot(slot, 1))
				expect(W.penSlot(slot, 99)).toEqual(W.penSlot(slot, 24))
			end
		)

		it("Bassin : 6 places flottantes dans le Bassin (Ø 12)", function()
			for i = 1, 6 do
				local p = W.poolSlot(3, i)
				expect(flat(p, W.anchor(3, "pool")) <= 6).toBe(true)
			end
		end)

		it("clôture : 4 places dans le ranch, contre le mur de devant, hors du portail", function()
			for slot = 1, 16 do
				for i = 1, 4 do
					local p = W.fencePoint(slot, i)
					local l = W.toLocal(slot, p)
					expect(W.ranchAt(p)).toBe(slot)
					expect(l.Z > 0 and l.Z < 8).toBe(true)
					expect(math.abs(l.X) > C.GateHalfWidth + 4).toBe(true)
					expect(flat(p, W.anchor(slot, "pot")) >= 4 + 2.5).toBe(true)
				end
			end
		end)

		it(
			"décorations : 18 emplacements dans le ranch, hors des enclos, du Bassin, de la Cuve et des dalles",
			function()
				local slot = 11
				for i = 1, 18 do
					local cf = W.decorSlot(slot, i)
					local p = cf.Position
					expect(W.ranchAt(p)).toBe(slot)
					for k = 1, 24 do
						expect(flat(p, W.penSlot(slot, k)) >= 4 + 1.5).toBe(true)
					end
					expect(flat(p, W.anchor(slot, "pool")) >= 6 + 1.5).toBe(true)
					expect(flat(p, W.anchor(slot, "vat")) >= 3 + 1.5).toBe(true)
					expect(flat(p, W.anchor(slot, "bowl")) >= 2 + 1.5).toBe(true)
					for socket = 1, 5 do
						expect(flat(p, W.padSocket(slot, socket)) >= 3.5).toBe(true)
					end
					expect(W.blocked(p.X, p.Z, 0)).toBe(false)
				end
			end
		)

		it("place et Prairie", function()
			expect(W.plaza("statue")).toEqual(Vector3.new(0, 0, -38))
			expect(W.plaza("shop")).toEqual(Vector3.new(38, 0, 0))
			expect(W.plaza("altar")).toEqual(Vector3.new(-38, 0, 0))
			expect(W.plaza("gauge")).toEqual(Vector3.new(0, 0, 38))
			for _, name in
				{
					"center",
					"megaPad",
					"statue",
					"shop",
					"altar",
					"gauge",
					"stage",
					"goldenFountain",
					"boards",
				}
			do
				expect(radius(W.plaza(name)) < C.PlazaRadius).toBe(true)
			end
			expect(W.plaza("???")).toEqual(Vector3.zero)
			local seen = {}
			for i = 1, 12 do
				local p = W.meadowPoint(i)
				expect(W.ranchNear(p, 4)).toBe(0)
				expect(W.blocked(p.X, p.Z, 1)).toBe(false)
				expect(radius(p) < C.PlateRadius).toBe(true)
				expect(p.Z < 0).toBe(true) -- au nord
				for _, q in seen do
					expect(flat(p, q) >= 3).toBe(true)
				end
				table.insert(seen, p)
			end
		end)
	end)

	describe("WorldLayout › graphe des rues", function()
		local g = W.graph()

		it(
			"57 nœuds (place 8, anneau 16, boulevard 32, fontaine dorée), voisins symétriques, connexe",
			function()
				expect(#g.nodes).toBe(57)
				for i, list in g.neighbors do
					expect(#list >= 2).toBe(true)
					for _, j in list do
						expect(table.find(g.neighbors[j], i) ~= nil).toBe(true)
					end
				end
				local seen, stack, count = { [1] = true }, { 1 }, 1
				while #stack > 0 do
					local n = table.remove(stack)
					for _, j in g.neighbors[n] do
						if not seen[j] then
							seen[j] = true
							count += 1
							table.insert(stack, j)
						end
					end
				end
				expect(count).toBe(57)
			end
		)

		it("aucune arête n'entre dans un ranch (marge 2) ni dans un solide (marge 1)", function()
			for i, list in g.neighbors do
				for _, j in list do
					if j > i then
						local a, b = g.nodes[i], g.nodes[j]
						for k = 0, 40 do
							local p = a:Lerp(b, k / 40)
							expect(W.ranchNear(p, 2)).toBe(0)
							expect(W.blocked(p.X, p.Z, 1)).toBe(false)
						end
					end
				end
			end
		end)

		it("nœud devant chaque portail, départs des Wild Wobblers, nœud le plus proche", function()
			for slot = 1, 16 do
				local node = W.fountainNode(slot)
				local p = g.nodes[node]
				expect(radius(p)).toBeNear(166, 1e-3)
				expect(flat(p, W.anchor(slot, "gate"))).toBeNear(12, 1e-3)
				expect(W.nearestNode(W.gateOutside(slot))).toBe(node)
			end
			local spawns = W.wildSpawnNodes()
			expect(#spawns).toBe(9)
			expect(g.nodes[spawns[1]]).toEqual(W.plaza("goldenFountain"))
			for _, n in spawns do
				expect(g.nodes[n] ~= nil).toBe(true)
			end
			-- la copie rendue ne touche pas le plan
			g.nodes[1] = Vector3.new(999, 0, 999)
			expect(W.graph().nodes[1] ~= g.nodes[1]).toBe(true)
		end)
	end)

	describe("WorldLayout › solides et sol", function()
		local solids = W.solids()

		-- coins d'une boîte verticale à plat
		local function corners(box)
			local cf, s = box.cframe, box.size
			local out = {}
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = cf:PointToWorldSpace(Vector3.new(sx * s.X / 2, 0, sz * s.Z / 2))
					table.insert(out, { p.X, p.Z })
				end
			end
			-- ordre du contour
			return { out[1], out[2], out[4], out[3] }
		end
		local function segDist(px, pz, ax, az, bx, bz)
			local vx, vz = bx - ax, bz - az
			local len2 = vx * vx + vz * vz
			local t = if len2 > 0 then math.clamp(((px - ax) * vx + (pz - az) * vz) / len2, 0, 1) else 0
			local cx, cz = ax + vx * t - px, az + vz * t - pz
			return math.sqrt(cx * cx + cz * cz)
		end
		local function inside(px, pz, poly)
			local sign = 0
			for i = 1, 4 do
				local a, b = poly[i], poly[i % 4 + 1]
				local cross = (b[1] - a[1]) * (pz - a[2]) - (b[2] - a[2]) * (px - a[1])
				if math.abs(cross) > 1e-9 then
					local s = if cross > 0 then 1 else -1
					if sign == 0 then
						sign = s
					elseif s ~= sign then
						return false
					end
				end
			end
			return true
		end
		-- distance à plat entre deux rectangles (0 s'ils se touchent ou se chevauchent)
		local function boxDistance(a, b)
			local pa, pb = corners(a), corners(b)
			for _, p in pa do
				if inside(p[1], p[2], pb) then
					return 0
				end
			end
			for _, p in pb do
				if inside(p[1], p[2], pa) then
					return 0
				end
			end
			local best = math.huge
			for _, pair in { { pa, pb }, { pb, pa } } do
				for _, p in pair[1] do
					for i = 1, 4 do
						local s, e = pair[2][i], pair[2][i % 4 + 1]
						best = math.min(best, segDist(p[1], p[2], s[1], s[2], e[1], e[2]))
					end
				end
			end
			return best
		end

		it("le plateau d'abord (dessus à Y = 0), puis des boîtes verticales d'au moins 30 studs", function()
			expect(#solids).toBe(1 + 16 * 5 + 24 + C.EdgeSegments)
			local plate = solids[1]
			expect(plate.cframe.Position.Y + plate.size.Y / 2).toBeNear(0, 1e-9)
			for i = 2, #solids do
				local box = solids[i]
				local bottom = box.cframe.Position.Y - box.size.Y / 2
				expect(bottom).toBeNear(0, 1e-9)
				expect(box.size.Y >= C.SolidMinHeight).toBe(true)
				expect(box.cframe.UpVector.Y).toBeNear(1, 1e-9)
			end
			-- la liste rendue est une copie
			solids[2] = nil
			expect(W.solids()[2] ~= nil).toBe(true)
			solids = W.solids()
		end)

		it("deux solides sont collés ou à au moins 6 studs l'un de l'autre (aucun recoin)", function()
			local worst = math.huge
			for i = 2, #solids do
				for j = i + 1, #solids do
					local a, b = solids[i], solids[j]
					local ca, cb = a.cframe.Position, b.cframe.Position
					local reach = (
						math.sqrt(a.size.X ^ 2 + a.size.Z ^ 2) + math.sqrt(b.size.X ^ 2 + b.size.Z ^ 2)
					)
							/ 2
						+ 6
					if flat(ca, cb) <= reach then
						local d = boxDistance(a, b)
						if d > 1e-6 then
							worst = math.min(worst, d)
						end
					end
				end
			end
			expect(worst >= 6).toBe(true)
		end)

		it(
			"aucun solide dans l'intérieur d'un ranch (hors murs), sur la place ou sur un objet du ranch",
			function()
				for slot = 1, 16 do
					for _, name in { "pot", "vat", "pool", "bowl", "cushion", "shelf", "fountain" } do
						local p = W.anchor(slot, name)
						expect({ slot = slot, name = name, blocked = W.blocked(p.X, p.Z, 0.5) }).toEqual({
							slot = slot,
							name = name,
							blocked = false,
						})
					end
					local s = W.spawnCFrame(slot).Position
					expect(W.blocked(s.X, s.Z, 2)).toBe(false)
				end
				for _, name in
					{ "center", "statue", "shop", "altar", "gauge", "stage", "goldenFountain", "boards" }
				do
					local p = W.plaza(name)
					expect(W.blocked(p.X, p.Z, 2)).toBe(false)
				end
			end
		)

		it("sol : 0 jusqu'au mur du bord ; supportY = haut d'un mur dans son emprise", function()
			expect(W.groundY(0, 0)).toBe(0)
			expect(W.groundY(321, 0)).toBe(0)
			expect(W.groundY(420, 0) > 0).toBe(true)
			expect(W.groundY(0 / 0, 0)).toBe(0)
			expect(W.supportY(Vector3.new(0, 3, 0))).toBe(0)
			local wall = W.toWorld(4, Vector3.new(-31.5, 3, 30))
			expect(W.supportY(wall)).toBe(30)
			local street = W.gateOutside(4)
			expect(W.supportY(street)).toBe(0)
			expect(W.supportY(Vector3.new(0 / 0, 0, 0))).toBe(0)
			-- rien n'est plus bas que le sol, rien n'est plus haut que 30 studs
			for i = 1, 2000 do
				local p = Vector3.new(math.sin(i) * 330, 0, math.cos(i * 1.7) * 330)
				local y = W.supportY(p)
				expect(y >= W.groundY(p.X, p.Z) and y <= 30).toBe(true)
			end
		end)

		it("hauteurs : chaque mur dépasse la plus haute portée (Contract_game, §20 n° 21)", function()
			expect(C.SolidMinHeight >= C.MaxReach + 8).toBe(true)
			expect(C.FenceWallHeight >= C.SolidMinHeight).toBe(true)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
