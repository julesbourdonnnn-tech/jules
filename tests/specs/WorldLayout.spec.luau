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
			"dalles : 4 prises sur la rangée Z = 67 (+ la 5e réservée), dans le ranch, espacées",
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
						expect(W.toLocal(slot, W.padSocket(slot, def.socket)).Z).toBeNear(67, 1e-3)
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

		it("règle de plan du GDD v1.3 §11.2 (contrat v1.2) : 8 studs autour de chaque dalle", function()
			local PAD_RADIUS = 2 -- disques Ø 4
			local POOL_RADIUS = 6
			for slot = 1, 16 do
				-- prises exactes : X = −18, −6, +6, +18 à Z = 67 ; la 5e réservée à (−28, 52)
				local xs = { -18, -6, 6, 18 }
				for socket = 1, 4 do
					local l = W.toLocal(slot, W.padSocket(slot, socket))
					expect(l.X).toBeNear(xs[socket], 1e-3)
					expect(l.Z).toBeNear(67, 1e-3)
				end
				local reserved = W.toLocal(slot, W.padSocket(slot, 5))
				expect(reserved.X).toBeNear(-28, 1e-3)
				expect(reserved.Z).toBeNear(52, 1e-3)
				for socket = 1, 4 do
					local p = W.padSocket(slot, socket)
					for _, name in { "bowl", "vat", "pot", "cushion" } do
						expect({
							socket = socket,
							near = name,
							ok = flat(p, W.anchor(slot, name)) >= 8 - 1e-3,
						}).toEqual({ socket = socket, near = name, ok = true })
					end
					expect(flat(p, W.padSocket(slot, 5)) >= 8 - 1e-3).toBe(true)
					-- bord du Bassin (rayon 6)
					expect(flat(p, W.anchor(slot, "pool")) - POOL_RADIUS >= 8 - 1e-3).toBe(true)
					-- deux dalles voisines à 12 studs
					if socket < 4 then
						expect(flat(p, W.padSocket(slot, socket + 1))).toBeNear(12, 1e-3)
					end
					-- aucune décoration à moins de 6 studs d'une dalle (bord du disque)
					for i = 1, 18 do
						local d = flat(W.decorSlot(slot, i).Position, p) - PAD_RADIUS
						expect({ socket = socket, decor = i, ok = d >= 6 - 1e-3 }).toEqual({
							socket = socket,
							decor = i,
							ok = true,
						})
					end
				end
			end
			-- GDD §11.2 : la dalle la plus proche du Bassin est à 9 studs de son bord, celle du bol à 9,8
			local nearestPool, nearestBowl = math.huge, math.huge
			for socket = 1, 4 do
				local p = W.padSocket(1, socket)
				nearestPool = math.min(nearestPool, flat(p, W.anchor(1, "pool")) - POOL_RADIUS)
				nearestBowl = math.min(nearestBowl, flat(p, W.anchor(1, "bowl")))
			end
			expect(nearestPool).toBeNear(9, 1e-3)
			expect(nearestBowl).toBeNear(math.sqrt(16 + 81), 1e-3)
		end)

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

	-- =========================================================================================
	-- Monde v2.0 (lot B4, étape 1 ; décisions D8, D9, D10, D21 du plan B4 ; GDD v2.0 §11.1, §11.2,
	-- §11.5 ; docs/04 §27.14) : ajouts seulement, règle de placement vérifiée pour les 16 ranchs
	-- =========================================================================================
	describe("WorldLayout › monde v2.0 (lot B4)", function()
		local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
		local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
		local WorldDecor = h:require("ReplicatedStorage.Shared.Render.WorldDecor")
		local Rules = h:require("ServerScriptService.Server.Helpers.Rules")
		local footprints = W.v2Footprints()
		local column = W.centerColumn()

		-- distance (XZ) d'un point à une boîte locale alignée
		local function boxDist(x, z, x0, x1, z0, z1)
			local dx = math.max(x0 - x, 0, x - x1)
			local dz = math.max(z0 - z, 0, z - z1)
			return math.sqrt(dx * dx + dz * dz)
		end
		-- marge (bord à bord) entre une emprise et un disque (x, z, r) ; négative = chevauchement
		local function gapDisc(f, x, z, r)
			if f.kind == "disc" then
				return math.sqrt((f.x - x) ^ 2 + (f.z - z) ^ 2) - f.r - r
			end
			return boxDist(x, z, f.x0, f.x1, f.z0, f.z1) - r
		end
		-- marge entre une emprise et une boîte alignée
		local function gapBox(f, x0, x1, z0, z1)
			if f.kind == "disc" then
				return boxDist(f.x, f.z, x0, x1, z0, z1) - f.r
			end
			local dx = math.max(x0 - f.x1, 0, f.x0 - x1)
			local dz = math.max(z0 - f.z1, 0, f.z0 - z1)
			return math.sqrt(dx * dx + dz * dz)
		end
		local function gap(f, g)
			if g.kind == "disc" then
				return gapDisc(f, g.x, g.z, g.r)
			end
			return gapBox(f, g.x0, g.x1, g.z0, g.z1)
		end
		-- disque englobant d'une emprise (rayon de son coin le plus loin)
		local function bound(f)
			if f.kind == "disc" then
				return f.x, f.z, f.r
			end
			local cx, cz = (f.x0 + f.x1) / 2, (f.z0 + f.z1) / 2
			return cx, cz, math.sqrt(((f.x1 - f.x0) / 2) ^ 2 + ((f.z1 - f.z0) / 2) ^ 2)
		end
		local function ground(f)
			return f.bottom < C.V2Elevated
		end
		local function byName(name)
			for _, f in footprints do
				if f.name == name then
					return f
				end
			end
			return nil
		end

		-- Obstacles de la v1.3 d'un ranch, lus par l'API (repère local du ranch `slot`)
		local function obstacles(slot)
			local out = {}
			local function disc(name, world, r)
				local l = W.toLocal(slot, world)
				table.insert(out, { name = name, x = l.X, z = l.Z, r = r })
			end
			for i = 1, 18 do
				disc("decor" .. i, W.decorSlot(slot, i).Position, 2.5)
			end
			disc("pot", W.anchor(slot, "pot"), 2.5)
			disc("vat", W.anchor(slot, "vat"), 3.5)
			disc("pool", W.anchor(slot, "pool"), 6)
			disc("bowl", W.anchor(slot, "bowl"), 2)
			disc("cushion", W.anchor(slot, "cushion"), 2)
			disc("fountain", W.anchor(slot, "fountain"), 2.5)
			disc("socket5", W.padSocket(slot, 5), 2)
			for i = 1, 4 do
				disc("fencePoint" .. i, W.fencePoint(slot, i), 4) -- squishy à la clôture (Ø 8)
			end
			disc("flag", W.toWorld(slot, Vector3.new(6, 0, 0)), 0.5) -- mât du drapeau (RanchRenderer)
			return out
		end

		it("colonne du centre : rayon de la silhouette + 2 autour de (0, 36), plancher Y = 21", function()
			local cfg = Balance.SizeScale
			expect(C.SilhouetteRadius).toBe(cfg.BaseDiameter * cfg.SilhouetteCap / 2)
			local sil = W.toLocal(1, W.anchor(1, "silhouette"))
			expect(column.center.X).toBeNear(0, 1e-9)
			expect(column.center.Z).toBeNear(36, 1e-9)
			expect(column.radius).toBe(C.SilhouetteRadius + 2)
			expect(column.floor).toBeNear(sil.Y - C.SilhouetteRadius, 1e-6)
			expect(column.floor).toBeNear(21, 1e-6)
		end)

		it(
			"16 ranchs : chaque emprise v2 au sol à ≥ 8 studs du centre des dalles, hors des enclos et du chemin du portail",
			function()
				local grounds = 0
				for slot = 1, 16 do
					local pads = {}
					for s = 1, 4 do
						table.insert(pads, W.toLocal(slot, W.padSocket(slot, s)))
					end
					for _, f in footprints do
						if ground(f) then
							grounds += 1
							for s, p in pads do
								local d = gapDisc(f, p.X, p.Z, 0)
								expect({ slot = slot, f = f.name, pad = s, ok = d >= C.PadClearance - 1e-3 }).toEqual({
									slot = slot,
									f = f.name,
									pad = s,
									ok = true,
								})
							end
							expect({ f = f.name, pens = gapBox(f, -27, 27, 12, 44) > 0 }).toEqual({
								f = f.name,
								pens = true,
							})
							expect({ f = f.name, path = gapBox(f, -5, 5, -6, 12) > 0 }).toEqual({
								f = f.name,
								path = true,
							})
						end
					end
				end
				-- 8 lampions, geyser, maisonnette, 10 Monuments, 12 Déco perso, tour, balcon, phare
				expect(grounds).toBe(16 * 35)
			end
		)

		it(
			"16 ranchs : aucune emprise v2 au sol ne chevauche les décorations, les objets de la v1.3 ni une autre emprise",
			function()
				for slot = 1, 16 do
					local obs = obstacles(slot)
					for i, f in footprints do
						if ground(f) then
							for _, o in obs do
								local d = gapDisc(f, o.x, o.z, o.r)
								expect({ slot = slot, f = f.name, o = o.name, ok = d > 0 }).toEqual({
									slot = slot,
									f = f.name,
									o = o.name,
									ok = true,
								})
							end
							expect({ f = f.name, shelf = gapBox(f, -10.15, 10.15, 69.4, 70.6) > 0 }).toEqual({
								f = f.name,
								shelf = true,
							})
							for j, g in footprints do
								if j ~= i and ground(g) then
									expect({ f = f.name, g = g.name, ok = gap(f, g) > 0 }).toEqual({
										f = f.name,
										g = g.name,
										ok = true,
									})
								end
							end
						end
					end
				end
			end
		)

		it(
			"dans la clôture, sur la clôture (lampions sur les poteaux) ou derrière le fond (hors clôture)",
			function()
				local hw, depth = C.RanchWidth / 2 - C.FenceThickness, C.RanchDepth - C.FenceThickness
				for _, f in footprints do
					local cx, cz, r = bound(f)
					if f.fence then
						local onSide = math.abs(math.abs(cx) - (hw + 0.5)) < 1e-3
						local onFront = math.abs(cz - 0.5) < 1e-3
						expect({ f = f.name, onFence = onSide or onFront }).toEqual({
							f = f.name,
							onFence = true,
						})
						expect(f.bottom).toBeNear(4.4, 1e-6) -- dessus des poteaux (4,4 studs)
					elseif f.outside and ground(f) then
						-- au sol derrière le fond (le ciel, en hauteur, peut déborder au-dessus de la clôture)
						local back = if f.kind == "disc" then f.z - f.r else f.z0
						expect({ f = f.name, behind = back >= C.RanchDepth + 1 }).toEqual({
							f = f.name,
							behind = true,
						})
					elseif ground(f) then
						local inside = if f.kind == "disc"
							then math.abs(f.x) + f.r <= hw and f.z - f.r >= C.FenceThickness and f.z + f.r <= depth
							else f.x0 >= -hw and f.x1 <= hw and f.z0 >= C.FenceThickness and f.z1 <= depth
						expect({ f = f.name, inside = inside }).toEqual({ f = f.name, inside = true })
					end
					expect(r > 0).toBe(true)
				end
			end
		)

		it(
			"rien de la v2 au-dessus de Y = 21 dans la colonne du centre, sauf les accessoires de la silhouette",
			function()
				local accessories = 0
				for _, f in footprints do
					local inColumn = gapDisc(f, column.center.X, column.center.Z, column.radius) < 0
					if inColumn and f.top > column.floor then
						expect({ f = f.name, accessory = f.accessory }).toEqual({
							f = f.name,
							accessory = true,
						})
					end
					if f.accessory then
						accessories += 1
						-- autour de la silhouette, à son rayon + 1 au moins
						expect(f.r >= C.SilhouetteRadius + 1).toBe(true)
						expect(inColumn).toBe(true)
					end
				end
				expect(accessories).toBe(1) -- cadre doré (Record R 18)
				-- le ciel flotte au-dessus des Monuments, hors de la colonne
				local sky = byName("sky")
				expect(sky.bottom > C.MonumentTop).toBe(true)
				expect(gapDisc(sky, column.center.X, column.center.Z, column.radius) > 0).toBe(true)
			end
		)

		it(
			"Monuments : 10 emplacements derrière le fond, loin de ceux des voisins et du mur du bord",
			function()
				local xs = { -36, -18, 0, 18, 36 }
				for slot = 1, 16 do
					for n = 1, 10 do
						local cf = W.monumentSlot(slot, n)
						local l = W.toLocal(slot, cf.Position)
						expect(l.X).toBeNear(xs[(n - 1) % 5 + 1], 1e-3)
						expect(l.Z).toBeNear(if n <= 5 then 88 else 116, 1e-3)
						-- tourné comme le ranch : vers la place
						expect(cf.LookVector:Dot(W.ranchCFrame(slot).LookVector)).toBeNear(1, 1e-4)
						-- mur du bord (r = 322) : tout le disque en deçà, 1 stud de marge
						expect(radius(cf.Position) + C.MonumentRadius <= C.WallRadius - 1).toBe(true)
						expect(W.ranchAt(cf.Position)).toBe(0)
						-- ni dans un rectangle de ranch voisin
						expect(W.ranchNear(cf.Position, C.MonumentRadius + 1)).toBe(0)
						-- Monuments des deux voisins : jamais à moins de 2 rayons + 6 studs
						for _, other in { slot % 16 + 1, (slot - 2) % 16 + 1 } do
							for m = 1, 10 do
								local d = flat(cf.Position, W.monumentSlot(other, m).Position)
								expect(d >= 2 * C.MonumentRadius + 6).toBe(true)
							end
						end
					end
				end
				-- hors bornes : premier / dernier emplacement
				expect(W.monumentSlot(3, 0)).toEqual(W.monumentSlot(3, 1))
				expect(W.monumentSlot(3, 99)).toEqual(W.monumentSlot(3, 10))
			end
		)

		it(
			"décors hors clôture (tour, balcon, phare, ciel, Monuments) : jamais sur un voisin ni au-delà du mur",
			function()
				for slot = 1, 16 do
					for _, f in footprints do
						if f.outside then
							local cx, cz, r = bound(f)
							local p = W.toWorld(slot, Vector3.new(cx, 0, cz))
							expect(radius(p) + r <= C.WallRadius - 1).toBe(true)
							for _, other in { slot % 16 + 1, (slot - 2) % 16 + 1 } do
								local l = W.toLocal(other, p)
								local d =
									boxDist(l.X, l.Z, -C.RanchWidth / 2, C.RanchWidth / 2, 0, C.RanchDepth)
								expect({ slot = slot, f = f.name, other = other, ok = d >= r + 1 }).toEqual({
									slot = slot,
									f = f.name,
									other = other,
									ok = true,
								})
								for _, g in footprints do
									if g.outside then
										local gx, gz, gr = bound(g)
										local q = W.toWorld(other, Vector3.new(gx, 0, gz))
										expect(flat(p, q) >= r + gr + 1).toBe(true)
									end
								end
							end
						end
					end
				end
			end
		)

		it("décors v2 : repères tournés comme le ranch ; nom inconnu → le portail", function()
			local names =
				{ "arch", "tower", "balcony", "lighthouse", "dome", "crown", "geyser", "frame", "sky" }
			for i = 1, 8 do
				table.insert(names, "lantern" .. i)
			end
			for slot = 1, 16 do
				for _, name in names do
					expect(W.hasV2Anchor(name)).toBe(true)
					local cf = W.v2Anchor(slot, name)
					expect(cf.LookVector:Dot(W.ranchCFrame(slot).LookVector)).toBeNear(1, 1e-4)
					local f = byName(name)
					local l = W.toLocal(slot, cf.Position)
					local cx, cz = bound(f)
					if name ~= "arch" and name ~= "balcony" then
						expect(l.X).toBeNear(cx, 1e-3)
						expect(l.Z).toBeNear(cz, 1e-3)
					end
				end
				expect(W.v2Anchor(slot, "???").Position).toEqual(W.ranchCFrame(slot).Position)
			end
			expect(W.hasV2Anchor("pot")).toBe(false)
			expect(W.hasV2Anchor(nil)).toBe(false)
			-- geyser : Z 4 à 10, X = −24 (GDD §11.2) ; lampions sur les poteaux de la clôture
			local geyser = W.toLocal(5, W.v2Anchor(5, "geyser").Position)
			expect(geyser.X).toBeNear(-24, 1e-3)
			expect(geyser.Z >= 4 and geyser.Z <= 10).toBe(true)
		end)

		it(
			"maisonnette : W.helperHouse = le repli de HelperService (Helpers/Rules.houseLocal) pour chaque ranch",
			function()
				local lx, lz = Rules.houseLocal()
				expect({ lx, lz }).toEqual({ -28, 60 })
				for slot = 1, 16 do
					local p = W.helperHouse(slot)
					expect(p).toEqual(W.toWorld(slot, Vector3.new(lx, 0, lz)))
					expect(W.ranchAt(p)).toBe(slot)
					-- la cabane se tient juste derrière son point, à ≥ 8 studs des dalles (règle ci-dessus)
					local house = byName("house")
					expect(gapDisc(house, lx, lz, 0) <= 1.5).toBe(true)
				end
			end
		)

		it(
			"Déco perso : 12 emplacements (8 « P », 4 « G », Cosmetics.DecoSlots), copie en lecture",
			function()
				local slots = W.decoPersoSlots()
				expect(#slots).toBe(#Cosmetics.DecoSlots)
				for i, def in slots do
					expect(def.size).toBe(Cosmetics.DecoSlots[i])
					local f = byName("deco" .. i)
					expect(f.r).toBe(if def.size == "G" then C.DecoLargeRadius else C.DecoSmallRadius)
					expect(f.x).toBe(def.position.X)
					expect(f.z).toBe(def.position.Z)
					for slot = 1, 16 do
						local cf = W.decoPersoSlot(slot, i)
						local l = W.toLocal(slot, cf.Position)
						expect((l - def.position).Magnitude < 1e-3).toBe(true)
						expect(W.ranchAt(cf.Position)).toBe(slot)
					end
				end
				slots[1].size = "G"
				expect(W.decoPersoSlots()[1].size).toBe("P")
				expect(W.decoPersoSlot(2, 0)).toEqual(W.decoPersoSlot(2, 1))
				expect(W.decoPersoSlot(2, 99)).toEqual(W.decoPersoSlot(2, 12))
			end
		)

		it(
			"kiosque de Big Plop (−32, 0, 24) : dans la place, loin de l'autel, de la boutique, de la jarre, de la scène et du MEGA pad",
			function()
				local k = W.plaza("kiosk")
				-- (−32, 0, 24) depuis la relecture du lot B4 (R-B4-2 : emprise réelle du kiosque 4,25 ; à (−30, 0, 24)
				-- son comptoir mordait sur le point d'apparition neutre)
				expect(k).toEqual(Vector3.new(-32, 0, 24))
				expect(radius(k) + C.KioskRadius < C.PlazaRadius).toBe(true)
				local function clear(name, pos, r, margin)
					local d = flat(k, pos) - C.KioskRadius - r
					expect({ name = name, ok = d >= margin }).toEqual({ name = name, ok = true })
				end
				clear("megaPad", W.plaza("megaPad"), 15.75, 6) -- anneau Neon Ø 31,5
				clear("altar", W.plaza("altar"), 6.5, 6) -- socle 12 × 5
				clear("shop", W.plaza("shop"), 5, 6)
				clear("gauge", W.plaza("gauge"), 4.5, 6) -- socle Ø 9
				clear("stage", W.plaza("stage"), 5.5, 6) -- bord Ø 11
				clear("statue", W.plaza("statue"), 5, 6)
				clear("goldenFountain", W.plaza("goldenFountain"), 4, 6)
				clear("boards", W.plaza("boards"), 18, 6)
				for i = 0, 3 do
					local a = math.rad(45 + 90 * i)
					clear("planter" .. i, Vector3.new(47 * math.cos(a), 0, 47 * math.sin(a)), 1.5, 1)
				end
				-- point d'apparition neutre (6 × 6 en (−24, 0, 24)) : jamais sous le kiosque
				expect(math.max(-27 - k.X, 0, k.X - -21) - C.KioskRadius > 0).toBe(true)
				-- aucune arête du graphe des rues (créatures) à moins de 2 studs de son bord
				local g = W.graph()
				for i, list in g.neighbors do
					for _, j in list do
						local a, b = g.nodes[i], g.nodes[j]
						local vx, vz = b.X - a.X, b.Z - a.Z
						local t =
							math.clamp(((k.X - a.X) * vx + (k.Z - a.Z) * vz) / (vx * vx + vz * vz), 0, 1)
						local d = math.sqrt((a.X + t * vx - k.X) ^ 2 + (a.Z + t * vz - k.Z) ^ 2)
						expect(d >= C.KioskRadius + 2).toBe(true)
					end
				end
			end
		)

		it(
			"Prairie v2 (D9) : jardin du quartier nord, r ∈ [120 ; 150], disque libre de maisons, rues, sucettes, buissons, lampadaires et sucre glace",
			function()
				local c = W.meadowCenter(true)
				local R = C.MeadowV2Radius
				local r = radius(c)
				expect(r >= 120 and r <= 150).toBe(true)
				local angle = math.deg(math.atan2(c.Z, c.X)) % 360
				expect(angle >= 225 and angle <= 315).toBe(true) -- quart nord (−Z)
				-- maisons + 2 et plaques de sucre glace (maison + 3)
				for _, house in WorldDecor.houses() do
					local l = house.cframe:PointToObjectSpace(c)
					local d = boxDist(
						l.X,
						l.Z,
						-house.size.X / 2,
						house.size.X / 2,
						-house.size.Z / 2,
						house.size.Z / 2
					)
					expect(d - R >= 2).toBe(true)
				end
				for _, plate in WorldDecor.icing() do
					local l = plate.cframe:PointToObjectSpace(c)
					local d = boxDist(
						l.X,
						l.Z,
						-plate.size.X / 2,
						plate.size.X / 2,
						-plate.size.Z / 2,
						plate.size.Z / 2
					)
					expect(d - R > 0).toBe(true)
				end
				-- rues + 1 : anneau intérieur (10 de large), boulevard (12), 8 radiales (10, de r = 50 à 160)
				expect(math.abs(r - C.InnerRing) - 5 - R >= 1).toBe(true)
				expect(math.abs(r - C.Boulevard) - 6 - R >= 1).toBe(true)
				for k = 0, 7 do
					local a = math.rad(45 * k)
					local ux, uz = math.cos(a), math.sin(a)
					local along = c.X * ux + c.Z * uz
					local across = math.abs(-c.X * uz + c.Z * ux)
					local t = math.clamp(along, C.PlazaRadius, C.Boulevard - 6)
					local d = math.sqrt((along - t) ^ 2 + across ^ 2)
					expect(d - 5 - R >= 1).toBe(true)
				end
				-- sucettes, buissons, lampadaires (boule Ø 1,6)
				for _, prop in WorldDecor.lollipops() do
					expect(flat(c, prop.position) - prop.size / 2 - R > 0).toBe(true)
				end
				for _, prop in WorldDecor.bushes() do
					expect(flat(c, prop.position) - prop.size / 2 - R > 0).toBe(true)
				end
				for _, lamp in WorldDecor.lamps() do
					expect(flat(c, lamp.position) - 0.8 - R > 0).toBe(true)
				end
				expect(W.ranchNear(c, R + 1)).toBe(0)
				expect(W.blocked(c.X, c.Z, R)).toBe(false)
				-- 12 places dans le disque, distinctes
				local seen = {}
				for i = 1, 12 do
					local p = W.meadowPoint(i, true)
					expect(flat(p, c) <= R - 1).toBe(true)
					expect(W.blocked(p.X, p.Z, 1)).toBe(false)
					for _, q in seen do
						expect(flat(p, q) >= 3).toBe(true)
					end
					table.insert(seen, p)
				end
			end
		)

		it(
			"Prairie de la v1.3 inchangée sans second argument ; Observatoire au-delà du mur du bord",
			function()
				expect(W.meadowCenter()).toEqual(Vector3.new(0, 0, -284))
				expect(W.meadowCenter(false)).toEqual(Vector3.new(0, 0, -284))
				for i = 1, 12 do
					local a = math.rad(30 * (i - 1))
					local spread = C.MeadowSpread * (if i % 2 == 0 then 1 else 0.55)
					local expected = Vector3.new(0, 0, -284)
						+ Vector3.new(spread * math.cos(a), 0, spread * math.sin(a))
					expect(W.meadowPoint(i)).toEqual(expected)
					expect(W.meadowPoint(i, false)).toEqual(expected)
					expect(W.meadowPoint(i, nil)).toEqual(expected)
				end
				local o = W.observatory()
				local p = o.Position
				expect(radius(p) - C.ObservatoryFootprint >= C.WallRadius + C.EdgeThickness).toBe(true)
				expect(radius(p)).toBeNear(340, 1e-3)
				expect(p.Z < 0 and math.abs(p.X) < 1e-3).toBe(true) -- colline nord
				expect(p.Y).toBeNear(W.groundY(p.X, p.Z), 1e-3)
				-- tourné vers la place
				local toCenter = (Vector3.new(0, p.Y, 0) - p).Unit
				expect(o.LookVector:Dot(toCenter)).toBeNear(1, 1e-4)
			end
		)
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
