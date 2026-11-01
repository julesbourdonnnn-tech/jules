--!nocheck
-- Auto-test de la boîte à outils générique de joueurs simulés (tests/harness/Bots) : serveur complet,
-- 16 joueurs avec personnages et profils chargés, marche, paquets groupés par deux ou trois, gels
-- réseau, départs, réapparitions, cerveaux, et MoveCheck appelé à chaque tick : 16 joueurs honnêtes
-- (gigue, gels de 0,7 à 1,5 s, réapparitions) ne sont jamais signalés ; un tricheur l'est.
local Bots = require("../../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000

	describe("Bots › serveur et joueurs", function()
		it("16 joueurs : personnages, profils chargés, placés en cercle, départs propres", function()
			local w = Bots.boot(Harness, { t0 = T0, schema = { coins = 0 } })
			local players = Bots.spawn(16, { radius = 30 })
			expect(#players).toBe(16)
			expect(#w.players).toBe(16)
			for i, p in players do
				expect(p.UserId).toBe(i)
				expect(w.DS.get(p) ~= nil).toBe(true)
				expect(w.DS.get(p).coins).toBe(0)
				local root = Bots.rootOf(p)
				expect(root ~= nil).toBe(true)
				expect(math.abs(root.Position.Y - Bots.ROOT_HEIGHT) < 1e-6).toBe(true)
				local r = math.sqrt(root.Position.X ^ 2 + root.Position.Z ^ 2)
				expect(math.abs(r - 30) < 1e-3).toBe(true)
			end
			Bots.leave(players[16])
			w.h:settle(5)
			expect(#w.players).toBe(15)
			expect(w.DS.get(players[16])).toBeNil()
			expect(Bots.problems()).toEqual({})
		end)

		it(
			"profil sauvegardé avant l'arrivée ; sol personnalisé ; walkAll arrive à destination",
			function()
				local w = Bots.boot(Harness, {
					t0 = T0,
					schema = { coins = 0 },
					groundY = function(x)
						return 0.1 * x
					end,
					before = function(w)
						Bots.saveProfile(w, 7, Bots.profile(w, { coins = 1234 }))
					end,
				})
				local p = Bots.join(7, { at = Bots.ground(0, 0) })
				expect(w.DS.get(p).coins).toBe(1234)
				expect(Bots.walkAll({ [p] = Bots.ground(30, 0) }, 100)).toBe(true)
				local root = Bots.rootOf(p)
				expect(math.abs(root.Position.X - 30) < 1e-6).toBe(true)
				expect(math.abs(root.Position.Y - (3 + 3)) < 1e-6).toBe(true) -- sol à 3 en x = 30
				-- 30 studs à 1,5 stud par tick : 20 ticks, 2 s d'horloge partagée
				expect(math.abs(Bots.now() - (T0 + 2)) < 0.11).toBe(true)
			end
		)

		it("paquets groupés par deux / trois : la position vue ne change qu'un tick sur n", function()
			Bots.boot(Harness, { t0 = T0 })
			local a = Bots.join(1, { at = Bots.ground(0, 0) })
			local b = Bots.join(2, { at = Bots.ground(0, 10) })
			Bots.jitter(a, 2)
			Bots.jitter(b, 3)
			local movesA, movesB = 0, 0
			local lastA, lastB = Bots.rootOf(a).Position, Bots.rootOf(b).Position
			for _ = 1, 12 do
				Bots.stepToward(a, Bots.ground(100, 0))
				Bots.stepToward(b, Bots.ground(100, 10))
				Bots.frame()
				local pa, pb = Bots.rootOf(a).Position, Bots.rootOf(b).Position
				if (pa - lastA).Magnitude > 1e-6 then
					movesA += 1
				end
				if (pb - lastB).Magnitude > 1e-6 then
					movesB += 1
				end
				lastA, lastB = pa, pb
			end
			expect(movesA).toBe(6)
			expect(movesB).toBe(4)
			-- la vue rattrape la position vraie à chaque mise à jour (aucune perte de distance)
			expect((Bots.rootOf(a).Position - Bots.truePos(a)).Magnitude < 1e-6).toBe(true)
		end)

		it("gel réseau : position figée pendant le gel, puis rattrapage d'un coup", function()
			Bots.boot(Harness, { t0 = T0 })
			local p = Bots.join(1, { at = Bots.ground(0, 0) })
			Bots.freeze(p, 0.7)
			local start = Bots.rootOf(p).Position
			for _ = 1, 6 do
				Bots.stepToward(p, Bots.ground(100, 0))
				Bots.frame()
				expect((Bots.rootOf(p).Position - start).Magnitude < 1e-6).toBe(true)
			end
			for _ = 1, 2 do
				Bots.stepToward(p, Bots.ground(100, 0))
				Bots.frame()
			end
			local x = Bots.rootOf(p).Position.X
			expect(x >= 1.5 * 7 - 1e-6).toBe(true)
			expect(math.abs(x - Bots.truePos(p).X) < 1e-6).toBe(true)
		end)

		it("cerveaux : wander va et vient ; un joueur parti n'a plus de cerveau", function()
			local w = Bots.boot(Harness, { t0 = T0 })
			local p = Bots.join(1, { at = Bots.ground(0, 0) })
			local q = Bots.join(2, { at = Bots.ground(0, 20) })
			Bots.setBrain(p, Bots.wander(Bots.ground(0, 0), Bots.ground(6, 0)))
			Bots.setBrain(q, Bots.wander(Bots.ground(0, 20), Bots.ground(6, 20)))
			local maxX = 0
			-- 1,5 stud par tick : arrivé en 6 au 4e tick, revenu en 0 au 8e…, à 3 au 22e
			for _ = 1, 22 do
				Bots.frame(Bots.brains)
				maxX = math.max(maxX, Bots.rootOf(p).Position.X)
			end
			expect(math.abs(maxX - 6) < 1e-6).toBe(true)
			expect(math.abs(Bots.rootOf(p).Position.X - 3) < 1e-6).toBe(true) -- revenu vers le départ
			Bots.leave(q)
			Bots.frames(5, Bots.brains)
			expect(w.brains[q]).toBeNil()
			expect(Bots.problems()).toEqual({})
		end)
	end)

	describe("Bots › MoveCheck à chaque tick (16 joueurs)", function()
		it(
			"16 joueurs honnêtes : gigue par 2 et 3, gels de 0,7 à 1,5 s, réapparition : 0 infraction, 0 retour",
			function()
				Bots.boot(Harness, { t0 = T0 })
				local players = Bots.spawn(16, { radius = 60 })
				local mc = Bots.moveCheck()
				Bots.frames(35) -- exemption d'apparition écoulée
				local freezes = { [3] = 0.7, [4] = 1.0, [5] = 1.5 }
				for i, p in players do
					if i % 3 == 1 then
						Bots.jitter(p, 2)
					elseif i % 3 == 2 then
						Bots.jitter(p, 3)
					end
					-- chacun fait des allers-retours de 40 studs sur sa propre ligne
					local a = Bots.rootOf(p).Position
					local b = a + (a.Unit * -40)
					Bots.setBrain(p, Bots.wander(Bots.ground(a.X, a.Z), Bots.ground(b.X, b.Z)))
				end
				for tick = 1, 300 do
					if tick == 50 then
						for i, seconds in freezes do
							Bots.freeze(players[i], seconds)
						end
					end
					if tick == 150 then
						local p = players[6]
						local pos = Bots.rootOf(p).Position
						Bots.respawn(p, Bots.ground(pos.X, pos.Z))
					end
					Bots.frame(Bots.brains)
				end
				expect(mc.problems()).toBe(0)
				for _, p in players do
					expect(mc.count(p, "rewind")).toBe(0)
					expect(mc.MoveCheck.recentRewinds(p, Bots.now())).toBe(0)
					expect(mc.count(p, "ok") > 250).toBe(true)
				end
				mc.stop()
				expect(Bots.problems()).toEqual({})
			end
		)

		it(
			"tricheur (téléportations répétées) au milieu de 15 honnêtes : lui seul est ramené",
			function()
				local w = Bots.boot(Harness, { t0 = T0 })
				local players = Bots.spawn(16, { radius = 60 })
				local mc = Bots.moveCheck()
				Bots.frames(35)
				local cheater = players[1]
				for _ = 1, 6 do
					local pos = Bots.rootOf(cheater).Position
					w.h:moveTo(cheater, pos + w.V3.new(30, 0, 0)) -- 30 studs en un tick, sans passer par le réseau simulé
					Bots.frame()
				end
				expect(mc.count(cheater, "flag") >= 2).toBe(true)
				expect(mc.count(cheater, "rewind") >= 1).toBe(true)
				for i = 2, 16 do
					expect(mc.count(players[i], "flag") + mc.count(players[i], "rewind")).toBe(0)
				end
				mc.stop()
			end
		)
	end)

	describe("Bots › horloge technique simulée", function()
		it("fakeOsClock : os.clock des modules montés figé puis avancé par le test", function()
			local h = Harness.new()
			local clock = Bots.fakeOsClock(h)
			local RL = h:require("ServerScriptService.Server.Util.RateLimit")
			clock.freeze()
			local p = h:addPlayer({ userId = 1, spawn = false })
			expect(RL.allow(p, "X", 1, 10)).toBe(true)
			expect(RL.allow(p, "X", 1, 10)).toBe(false)
			clock.advance(10)
			expect(RL.allow(p, "X", 1, 10)).toBe(true)
		end)
	end)
end
