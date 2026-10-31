--!nocheck
-- WorldLayout (paquet logic) : géométrie de Lumora (GDD §4.3, §4.7, §4.8, §11) — Nids, portes,
-- boîtes de parade, ports sûrs, anneau de la Balise, zones, sol, grille d'apparition, perchoirs,
-- accueil, observatoire, constellation, tableau, chemins, lanternes et décor seedé.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	local Zones = h:require("ReplicatedStorage.Shared.Config.Zones")
	local V3 = h.globals.Vector3

	local function rXZ(p)
		return math.sqrt(p.X * p.X + p.Z * p.Z)
	end
	local function distXZ(a, b)
		local dx, dz = a.X - b.X, a.Z - b.Z
		return math.sqrt(dx * dx + dz * dz)
	end
	local function gatePos(slot)
		return WL.gateCFrame(slot).Position
	end

	describe("WorldLayout — Nids et portes (§11.3, §4.8)", function()
		it("Nid k = slot − 1 sur l'anneau r = 150 tous les 30°, tourné vers le centre", function()
			for slot = 1, 12 do
				local a = math.rad(30 * (slot - 1))
				local c = WL.nestCenter(slot)
				expect(c.X).toBeNear(150 * math.cos(a), 1e-3)
				expect(c.Z).toBeNear(150 * math.sin(a), 1e-3)
				expect(c.Y).toBe(0)
				local cf = WL.nestCFrame(slot)
				local look = cf.LookVector
				expect(look.X).toBeNear(-math.cos(a), 1e-4)
				expect(look.Z).toBeNear(-math.sin(a), 1e-4)
				expect(look.Y).toBeNear(0, 1e-6)
			end
		end)

		it("porte à 19 studs côté centre (r = 131), boîte centrée à Y = 5", function()
			for slot = 1, 12 do
				local g = gatePos(slot)
				expect(rXZ(g)).toBeNear(131, 1e-3)
				expect(g.Y).toBeNear(5, 1e-6)
				expect(distXZ(g, WL.nestCenter(slot))).toBeNear(19, 1e-3)
				expect(WL.gateCFrame(slot).LookVector:Dot(WL.nestCFrame(slot).LookVector)).toBeNear(1, 1e-5)
			end
			-- distance entre deux portes voisines : 67,8 studs (§11.3)
			expect(distXZ(gatePos(1), gatePos(2))).toBeNear(67.8, 0.05)
		end)

		it("boîte de parade 12 × 10 × 4 dans le repère de la porte", function()
			for slot = 1, 12 do
				local cf = WL.gateCFrame(slot)
				local function at(x, y, z)
					return cf.Position + cf.RightVector * x + V3.new(0, y, 0) + cf.LookVector * z
				end
				expect(WL.inGateBox(slot, at(0, 0, 0))).toBe(true)
				expect(WL.inGateBox(slot, at(5.9, -2, 1.9))).toBe(true)
				expect(WL.inGateBox(slot, at(-5.9, 4.9, -1.9))).toBe(true)
				expect(WL.inGateBox(slot, at(6.2, 0, 0))).toBe(false)
				expect(WL.inGateBox(slot, at(0, 0, 2.2))).toBe(false)
				expect(WL.inGateBox(slot, at(0, 0, -2.2))).toBe(false)
				expect(WL.inGateBox(slot, at(0, 5.2, 0))).toBe(false)
				expect(WL.inGateBox(slot, at(0, -5.2, 0))).toBe(false)
				-- personnage debout au sol (HumanoidRootPart à Y ≈ 3) au milieu de la porte
				expect(WL.inGateBox(slot, V3.new(cf.Position.X, 3, cf.Position.Z))).toBe(true)
				-- la porte d'un autre Nid ne compte pas
				local other = slot % 12 + 1
				expect(WL.inGateBox(other, cf.Position)).toBe(false)
			end
			expect(WL.inGateBox(0, gatePos(1))).toBe(false)
			expect(WL.inGateBox(13, gatePos(1))).toBe(false)
			expect(WL.inGateBox(1.5, gatePos(1))).toBe(false)
		end)

		it("slot invalide : erreur explicite pour les repères", function()
			for _, fn in { "nestCenter", "nestCFrame", "gateCFrame", "observatoryCFrame" } do
				local ok, err = pcall(WL[fn], 0)
				expect(ok).toBe(false)
				expect(tostring(err)).toContain("slot")
			end
			expect((pcall(WL.perchCFrame, 1, 47))).toBe(false)
			expect((pcall(WL.perchCFrame, 1, 0))).toBe(false)
		end)
	end)

	describe("WorldLayout — ports sûrs, Balise, zones (§4.3, §4.7)", function()
		it("port sûr : < 25 studs (XZ) d'une porte, quelle qu'elle soit ; jamais deux à la fois", function()
			for slot = 1, 12 do
				local g = gatePos(slot)
				local cf = WL.gateCFrame(slot)
				expect(WL.harborSlot(g)).toBe(slot)
				expect(WL.harborSlot(g + cf.RightVector * 24.9)).toBe(slot)
				expect(WL.harborSlot(g + cf.LookVector * 24.9 + V3.new(0, 40, 0))).toBe(slot) -- Y ignoré
				expect(WL.harborSlot(g + cf.RightVector * 25.1)).toBeNil()
				expect(WL.inHarbor(g + cf.LookVector * -24)).toBe(true)
				expect(WL.inOwnHarbor(slot, g)).toBe(true)
				expect(WL.inOwnHarbor(slot % 12 + 1, g)).toBe(false)
			end
			-- milieu entre deux portes : hors port
			local mid = (gatePos(1) + gatePos(2)) / 2
			expect(WL.inHarbor(mid)).toBe(false)
			expect(WL.inHarbor(V3.new(0, 0, 0))).toBe(false)
			expect(WL.inHarbor(V3.new(0 / 0, 0, 0))).toBe(false)
			expect(WL.inOwnHarbor(0, gatePos(1))).toBe(false)
			-- balayage : harborSlot est d'accord avec une recherche exhaustive
			for i = 0, 3000 do
				local a = i * 0.0021
				local r = 100 + (i % 70)
				local p = V3.new(r * math.cos(a * 3), 0, r * math.sin(a * 3))
				local brute = nil
				for slot = 1, 12 do
					if distXZ(p, gatePos(slot)) < 25 then
						expect(brute).toBeNil()
						brute = slot
					end
				end
				expect(WL.harborSlot(p)).toBe(brute)
			end
		end)

		it("anneau de la Balise 8 ≤ r ≤ 16", function()
			expect(WL.inBeaconRing(V3.new(8, 0, 0))).toBe(true)
			expect(WL.inBeaconRing(V3.new(0, 3, -12))).toBe(true)
			expect(WL.inBeaconRing(V3.new(16, 0, 0))).toBe(true)
			expect(WL.inBeaconRing(V3.new(7.9, 0, 0))).toBe(false)
			expect(WL.inBeaconRing(V3.new(16.1, 0, 0))).toBe(false)
		end)

		it("zones en anneaux XZ : Cratère [16 ; 55[, Clairière [55 ; 110[, Prairie [110 ; 170[", function()
			expect(WL.zoneAt(V3.new(15.9, 0, 0))).toBeNil()
			expect(WL.zoneAt(V3.new(16, 0, 0))).toBe("crater")
			expect(WL.zoneAt(V3.new(0, 0, 54.9))).toBe("crater")
			expect(WL.zoneAt(V3.new(55, 0, 0))).toBe("glade")
			expect(WL.zoneAt(V3.new(-109.9, 0, 0))).toBe("glade")
			expect(WL.zoneAt(V3.new(110, 0, 0))).toBe("meadow")
			expect(WL.zoneAt(V3.new(0, 0, -169.9))).toBe("meadow")
			expect(WL.zoneAt(V3.new(170, 0, 0))).toBeNil()
			expect(WL.zoneAt(V3.new(400, 0, 0))).toBeNil()
			expect(WL.radiusXZ(V3.new(3, 99, 4))).toBe(5)
		end)
	end)

	describe("WorldLayout — sol et île (§11.1, §11.2)", function()
		it("hauteur du sol par zone, plateformes, Balise et rebord du Cratère", function()
			expect(WL.groundY(30, 0)).toBeNear(0.3, 1e-9) -- Cratère
			expect(WL.groundY(80, 0)).toBeNear(0.1, 1e-9) -- Clairière
			expect(WL.groundY(0, -120)).toBe(0) -- Prairie
			expect(WL.groundY(150, 0)).toBeNear(0.2, 1e-9) -- plateforme du Nid 1
			expect(WL.groundY(150 * math.cos(math.rad(15)), 150 * math.sin(math.rad(15)))).toBe(0) -- entre deux Nids
			expect(WL.groundY(6, 0)).toBeNear(3.3, 1e-9) -- socle de la Balise
			expect(WL.groundY(0, 0)).toBeNear(21.3, 1e-9) -- sommet
			-- rebord du Cratère : pente jusqu'à 2,5 au milieu, interrompue sur les chemins
			local a = math.rad(15) -- entre deux chemins
			local peak = WL.groundY(55 * math.cos(a), 55 * math.sin(a))
			expect(peak > 2.4 and peak < 3).toBe(true)
			expect(WL.groundY(55, 0)).toBeNear(0.1, 1e-9) -- ouverture alignée sur le chemin
			expect(WL.groundY(0 / 0, 0 / 0)).toBeNear(21.3, 1e-9)
		end)

		it("clampToIsland ramène dans l'île, au sol, hors de la colonne de la Balise", function()
			local p = WL.clampToIsland(V3.new(500, 9, 0))
			expect(rXZ(p)).toBeNear(170, 1e-3)
			expect(p.Y).toBe(0)
			p = WL.clampToIsland(V3.new(0, 40, 300), 30)
			expect(rXZ(p)).toBeNear(150, 1e-3)
			p = WL.clampToIsland(V3.new(80, 50, 0))
			expect(p.X).toBe(80)
			expect(p.Y).toBeNear(0.1, 1e-6)
			p = WL.clampToIsland(V3.new(1, 0, 1))
			expect(rXZ(p) >= 9 - 1e-3).toBe(true)
			p = WL.clampToIsland(V3.new(0, 0, 0))
			expect(rXZ(p) >= 9 - 1e-3).toBe(true)
			p = WL.clampToIsland(V3.new(0 / 0, 0 / 0, math.huge))
			expect(p.X == p.X and p.Z == p.Z and rXZ(p) <= 180).toBe(true)
		end)
	end)

	describe("WorldLayout — grille d'apparition (§4.3)", function()
		it("chaque point respecte sa zone et toutes les exclusions", function()
			local decor = WL.decor()
			for _, zone in Zones.List do
				local points = WL.spawnPoints(zone.key)
				expect(#points > 100).toBe(true)
				for _, p in points do
					local r = rXZ(p)
					expect(r >= zone.inner and r < zone.outer and r >= 16).toBe(true)
					expect(WL.zoneAt(p)).toBe(zone.key)
					expect(p.X % 6).toBe(0)
					expect(p.Z % 6).toBe(0)
					expect(p.Y).toBeNear(WL.groundY(p.X, p.Z), 1e-5)
					for slot = 1, 12 do
						expect(distXZ(p, gatePos(slot)) >= 30).toBe(true)
						expect(distXZ(p, WL.nestCenter(slot)) >= 20).toBe(true)
					end
					expect(WL.inHarbor(p)).toBe(false)
					for _, o in decor.obstacles do
						expect(distXZ(p, o) >= Zones.Decor.ObstacleRadius).toBe(true)
					end
				end
			end
		end)

		it("mise en cache ; zone inconnue → liste vide", function()
			expect(WL.spawnPoints("crater")).toBe(WL.spawnPoints("crater"))
			expect(#WL.spawnPoints("nope")).toBe(0)
		end)
	end)

	describe("WorldLayout — perchoirs, accueil, observatoire, tableau (§11.2, §11.3)", function()
		it(
			"46 perchoirs par Nid dans l'ordre des anneaux, sur la plateforme, ouverts côté porte",
			function()
				for slot = 1, 12 do
					local center = WL.nestCenter(slot)
					local forward = WL.nestCFrame(slot).LookVector
					local seen = {}
					local index = 0
					for _, ring in Zones.Perches.Rings do
						for _ = 1, ring.count do
							index += 1
							local cf = WL.perchCFrame(slot, index)
							local p = cf.Position
							expect(distXZ(p, center)).toBeNear(ring.radius, 1e-3)
							expect(p.Y).toBeNear(0.2 + ring.y, 1e-5)
							expect(distXZ(p, center) <= 17).toBe(true)
							-- jamais dans l'ouverture de 60° face à la porte
							local dir = (p - center) * V3.new(1, 0, 1)
							local cosA = dir.Unit:Dot(forward)
							expect(cosA <= math.cos(math.rad(30)) + 1e-4).toBe(true)
							local key = string.format("%.2f:%.2f:%.2f", p.X, p.Y, p.Z)
							expect(seen[key]).toBeNil()
							seen[key] = true
							-- tourné vers le centre de l'île
							expect(cf.LookVector:Dot(forward)).toBeNear(1, 1e-4)
						end
					end
					expect(index).toBe(46)
					-- le meilleur perchoir est au fond, face à la porte
					local first = WL.perchCFrame(slot, 1).Position
					expect(((first - center) * V3.new(1, 0, 1)).Unit:Dot(forward)).toBeNear(-1, 1e-4)
				end
			end
		)

		it("Puffkins de bienvenue : dans le port sûr, à 12 studs devant la porte", function()
			for slot = 1, 12 do
				local pts = WL.welcomePoints(slot, 3)
				expect(#pts).toBe(3)
				local g = gatePos(slot)
				for _, p in pts do
					expect(WL.inOwnHarbor(slot, p)).toBe(true)
					expect(WL.harborSlot(p)).toBe(slot)
					expect(rXZ(p) < 131).toBe(true)
					expect(distXZ(p, g)).toBeNear(12, 3.2)
					expect(p.Y).toBeNear(WL.groundY(p.X, p.Z), 1e-5)
				end
			end
			expect(#WL.welcomePoints(1, 0)).toBe(0)
			expect(#WL.welcomePoints(1, 0 / 0)).toBe(0)
		end)

		it(
			"observatoire à r = 172, constellation à Y = 45 au-dessus, tableau à r = 12 face au sud",
			function()
				for slot = 1, 12 do
					local o = WL.observatoryCFrame(slot)
					expect(rXZ(o.Position)).toBeNear(172, 1e-3)
					local seen = {}
					for i = 1, 20 do
						local s = WL.constellationPoint(slot, i)
						expect(distXZ(s, o.Position) < 15).toBe(true)
						expect(math.abs(s.Y - 45) < 15).toBe(true)
						local key = string.format("%.2f:%.2f:%.2f", s.X, s.Y, s.Z)
						expect(seen[key]).toBeNil()
						seen[key] = true
					end
					expect(WL.constellationPoint(slot, 1).Y).toBeNear(45, 1e-5)
				end
				local board = WL.boardCFrame()
				expect(rXZ(board.Position)).toBeNear(12, 1e-4)
				expect(board.Position.Z).toBeNear(12, 1e-4)
				expect(board.LookVector.Z).toBeNear(1, 1e-5)
			end
		)
	end)

	describe("WorldLayout — chemins, lanternes, décor (§11.1, §11.4)", function()
		it("chemins : 12 rayons de r 131 à r 58, une pierre tous les 6 studs", function()
			local stones = WL.pathStones()
			expect(#stones).toBe(12 * 13)
			for _, p in stones do
				local r = rXZ(p)
				expect(r >= 58 - 1e-3 and r <= 131 + 1e-3).toBe(true)
				expect(p.Y).toBeNear(WL.groundY(p.X, p.Z), 1e-5)
			end
			expect(WL.pathStones()).toBe(stones)
		end)

		it("lanternes : 36 au bord des chemins, 24 allumées (r 90 et 60)", function()
			local lanterns = WL.lanterns()
			expect(#lanterns).toBe(36)
			local lit = 0
			for _, l in lanterns do
				local r = rXZ(l.position)
				if l.lit then
					lit += 1
					expect(math.abs(r - 90) < 1 or math.abs(r - 60) < 1).toBe(true)
				end
			end
			expect(lit).toBe(24)
		end)

		it("décor : quantités du GDD, dans les bonnes zones, hors ports sûrs et chemins", function()
			local d = WL.decor()
			expect(#d.puffblooms).toBe(60)
			expect(#d.mushcaps).toBe(30)
			expect(#d.fences).toBe(24)
			expect(#d.crystals).toBe(16)
			expect(#d.floatingStones).toBe(8)
			expect(#d.craterRocks).toBe(6)
			expect(#d.cracks).toBe(18)
			expect(#d.islets).toBe(6)
			expect(#d.clouds).toBe(40)
			local lit = 0
			for _, c in d.crystals do
				if c.lit then
					lit += 1
				end
				expect(WL.zoneAt(c.cframe.Position)).toBe("glade")
				expect(WL.inHarbor(c.cframe.Position)).toBe(false)
			end
			expect(lit).toBe(6)
			for _, list in { d.puffblooms, d.mushcaps } do
				for _, p in list do
					expect(WL.zoneAt(p)).toBe("meadow")
					for slot = 1, 12 do
						expect(distXZ(p, gatePos(slot)) >= 30).toBe(true)
						expect(distXZ(p, WL.nestCenter(slot)) >= 20).toBe(true)
					end
				end
			end
			for _, p in d.craterRocks do
				expect(WL.zoneAt(p)).toBe("crater")
			end
			for _, p in d.islets do
				expect(rXZ(p) >= 225 and rXZ(p) <= 260).toBe(true)
				expect(p.Y >= 10 and p.Y <= 30).toBe(true)
			end
			for _, p in d.clouds do
				expect(p.Y).toBe(-60)
			end
			expect(#d.obstacles).toBe(60 + 30 + 24 + 16 + 6 + 36)
		end)

		it("décor déterministe : identique d'un harnais à l'autre, et mis en cache", function()
			local h2 = Harness.new()
			local WL2 = h2:require("ReplicatedStorage.Shared.Logic.WorldLayout")
			local a, b = WL.decor(), WL2.decor()
			for i, p in a.puffblooms do
				expect(p).toEqual(b.puffblooms[i])
			end
			for i, c in a.crystals do
				expect(c.cframe.Position).toEqual(b.crystals[i].cframe.Position)
			end
			expect(#WL.spawnPoints("meadow")).toBe(#WL2.spawnPoints("meadow"))
			expect(WL.decor()).toBe(a)
		end)
	end)
end
