--!nocheck
-- SeededPath (paquet logic, docs/04 §12.1, GDD §4.11, §4.21.2, §12.5) : trajets déterministes ;
-- 10 000 fuites jamais hors du graphe ni dans un ranch ; vitesses du GDD ; fuites personnelles dans
-- leur rayon, hors des ranchs et des solides.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Vector3 = require("@lune/roblox").Vector3

	local h = Harness.new()
	local SP = h:require("ReplicatedStorage.Shared.Logic.SeededPath")
	local W = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	local Hash = h:require("ReplicatedStorage.Shared.Logic.Hash")
	local Events = h:require("ReplicatedStorage.Shared.Config.Events")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")

	local graph = W.graph()

	local function segDist(p, a, b)
		local vx, vz = b.X - a.X, b.Z - a.Z
		local len2 = vx * vx + vz * vz
		local t = if len2 > 0 then math.clamp(((p.X - a.X) * vx + (p.Z - a.Z) * vz) / len2, 0, 1) else 0
		local cx, cz = a.X + vx * t - p.X, a.Z + vz * t - p.Z
		return math.sqrt(cx * cx + cz * cz)
	end
	-- distance au graphe : arêtes autour du nœud le plus proche (et de ses voisins)
	local function graphDistance(p)
		local n = W.nearestNode(p)
		local best = math.huge
		local around = { n }
		for _, m in graph.neighbors[n] do
			table.insert(around, m)
		end
		for _, a in around do
			for _, b in graph.neighbors[a] do
				best = math.min(best, segDist(p, graph.nodes[a], graph.nodes[b]))
			end
		end
		return best
	end
	local function flat(a, b)
		return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
	end

	describe("SeededPath › fuites du Rush", function()
		it(
			"10 000 trajets : jamais hors du graphe ni dans un ranch, de t0 à t0 + 30 s (7 instants chacun)",
			function()
				local worstGraph, inRanch = 0, 0
				for i = 1, 10000 do
					local slot = (i - 1) % 16 + 1
					local path =
						SP.escape(Hash.u32(i, 77), 1000, W.fountainNode(slot), (i % 360) * math.pi / 180)
					for k = 0, 6 do
						local p = path(1000 + k * 5)
						worstGraph = math.max(worstGraph, graphDistance(p))
						if W.ranchNear(p, 1) ~= 0 then
							inRanch += 1
						end
					end
				end
				expect(worstGraph < 1e-2).toBe(true)
				expect(inRanch).toBe(0)
			end
		)

		it(
			"départ au nœud devant le portail, premier bond de 20 studs le long de la rue la plus opposée",
			function()
				local slot = 5
				local node = W.fountainNode(slot)
				local start = graph.nodes[node]
				local path = SP.escape(1, 0, node, 0)
				expect(flat(path(0), start) < 1e-3).toBe(true)
				-- angle vers le voisin « gauche » ou « droit » : le premier bond part vers le plus aligné
				for _, other in graph.neighbors[node] do
					local target = graph.nodes[other]
					local angle = math.atan2(target.Z - start.Z, target.X - start.X)
					local p = SP.escape(9, 0, node, angle)
					-- quand la distance parcourue atteint 20 studs, on est sur cette arête, à 20 studs du départ
					local t20 = 0
					while true do
						local q = p(t20)
						if flat(q, start) >= 20 - 1e-3 then
							break
						end
						t20 += 0.01
					end
					expect(segDist(p(t20), start, target) < 1e-2).toBe(true)
					local air = select(2, p(t20 / 2))
					expect(air).toBe(true) -- en l'air pendant le premier bond
				end
			end
		)

		it("vitesse : 16 − 0,32 × t bornée à 8 ; ≈ 300 studs en 25 s", function()
			local path = SP.escape(3, 0, W.fountainNode(1), 1)
			local function travelled(tEnd)
				local d, last = 0, path(0)
				for k = 1, math.floor(tEnd * 100) do
					local p = path(k / 100)
					d += flat(p, last)
					last = p
				end
				return d
			end
			expect(math.abs(travelled(1) - (16 - 0.16)) < 0.2).toBe(true)
			expect(math.abs(travelled(25) - 300) < 2).toBe(true)
			-- au-delà de la durée calculée : posée au bout, jamais d'erreur
			local p = path(1e9)
			expect(p.X == p.X).toBe(true)
		end)

		it(
			"déterministe : même graine, mêmes positions ; graines différentes, trajets différents",
			function()
				local a = SP.escape(42, 10, 30, 2)
				local b = SP.escape(42, 10, 30, 2)
				local c = SP.escape(43, 10, 30, 2)
				local differ = false
				for k = 0, 30 do
					local t = 10 + k
					expect(a(t)).toEqual(b(t))
					if flat(a(t), c(t)) > 1 then
						differ = true
					end
				end
				expect(differ).toBe(true)
			end
		)

		it("vitesse imposée (Wild Wobbler) et entrées bizarres", function()
			local wild = SP.escape(5, 0, W.wildSpawnNodes()[2], 0, Events.Rush.SpeedStart)
			expect(wild(0) ~= nil).toBe(true)
			local weird = SP.escape(0 / 0, 0 / 0, 999, 0 / 0, -5)
			local p, air = weird(0 / 0)
			expect(p.X == p.X and type(air) == "boolean").toBe(true)
		end)
	end)

	describe("SeededPath › fuite personnelle (hopAround)", function()
		it("bonds de 4,5 studs toutes les 0,5 s, pause de 0,6 s tous les 3 bonds", function()
			local center = W.anchor(6, "fountain")
			local path = SP.hopAround(11, 100, center, Balance.Runaway.Radius)
			expect(flat(path(100), center) < 1e-3).toBe(true)
			local p1 = path(100.5)
			expect(flat(p1, path(100))).toBeNear(4.5, 1e-2)
			-- pause après le 3e bond (1,5 s → 2,1 s) : immobile, posé au sol
			local a, airA = path(101.6)
			local b, airB = path(102.0)
			expect(flat(a, b) < 1e-3).toBe(true)
			expect(airA).toBe(false)
			expect(airB).toBe(false)
			local _, airHop = path(100.25)
			expect(airHop).toBe(true)
		end)

		it("1 000 trajets : dans le rayon de 35 studs, jamais dans un ranch ni dans un solide", function()
			local outside, inRanch, blocked = 0, 0, 0
			for i = 1, 1000 do
				local slot = (i - 1) % 16 + 1
				local center = W.anchor(slot, "fountain")
				local path = SP.hopAround(Hash.u32(i, 3), 0, center, Balance.Runaway.Radius)
				for k = 0, 25 do
					local p = path(k * 0.8 + 0.25)
					if flat(p, center) > Balance.Runaway.Radius + 1e-3 then
						outside += 1
					end
					if W.ranchNear(p, 1) ~= 0 then
						inRanch += 1
					end
					if W.blocked(p.X, p.Z, 0.5) then
						blocked += 1
					end
				end
			end
			expect(outside).toBe(0)
			expect(inRanch).toBe(0)
			expect(blocked).toBe(0)
		end)
	end)

	describe("SeededPath › Golden, démonstration, diffusion", function()
		it("Golden : 14 → 10 studs/s en 30 s, sur le graphe, depuis la fontaine dorée", function()
			local node = W.wildSpawnNodes()[1]
			local path = SP.golden(8, 0, node)
			expect(flat(path(0), W.plaza("goldenFountain")) < 1e-3).toBe(true)
			local d, last = 0, path(0)
			for k = 1, 3000 do
				local p = path(k / 100)
				d += flat(p, last)
				last = p
				expect(graphDistance(p) < 1e-2).toBe(true)
			end
			-- 14 × 30 − (4 / 30) × 30² / 2 = 360 studs
			expect(math.abs(d - 360) < 2).toBe(true)
		end)

		it("démonstration : 8 studs/s, du point de départ au boulevard, jamais dans un ranch", function()
			for slot = 1, 16 do
				local start = W.gateOutside(slot)
				local path = SP.demo(slot, 50, start)
				expect(flat(path(50), start) < 1e-3).toBe(true)
				-- distance parcourue en 1 s (le trajet tourne au boulevard) : 8 studs
				local d, last = 0, path(50)
				for k = 1, 100 do
					local q = path(50 + k / 100)
					d += flat(q, last)
					last = q
				end
				expect(d).toBeNear(8, 0.05)
				for k = 0, 40 do
					expect(W.ranchNear(path(50 + k * 0.5), 1)).toBe(0)
				end
			end
		end)

		it("fromSpawn : même trajet que la fonction de sa sorte (serveur = client)", function()
			local center = W.anchor(2, "fountain")
			local hop = SP.fromSpawn({
				kind = "runaway",
				path = "hop",
				seed = 4,
				t0 = 10,
				startNode = 0,
				awayAngle = 0,
				center = { x = center.X, z = center.Z },
				speed = 0,
			})
			local direct = SP.hopAround(4, 10, Vector3.new(center.X, 0, center.Z), Balance.Runaway.Radius)
			local esc = SP.fromSpawn({
				kind = "escape",
				path = "escape",
				seed = 4,
				t0 = 10,
				startNode = 30,
				awayAngle = 1,
				center = { x = 0, z = 0 },
				speed = 16,
			})
			local escDirect = SP.escape(4, 10, 30, 1, 16)
			local gold = SP.fromSpawn({
				kind = "golden",
				path = "escape",
				seed = 4,
				t0 = 10,
				startNode = 57,
				awayAngle = 0,
				center = { x = 0, z = 0 },
				speed = 14,
			})
			local goldDirect = SP.golden(4, 10, 57)
			for k = 0, 20 do
				local t = 10 + k
				expect(hop(t)).toEqual(direct(t))
				expect(esc(t)).toEqual(escDirect(t))
				expect(gold(t)).toEqual(goldDirect(t))
			end
			local none = SP.fromSpawn(nil)
			expect(none(5)).toEqual(Vector3.zero)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
