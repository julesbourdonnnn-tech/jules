--!nocheck
-- SeededPath (paquet logic) : déterminisme, amplitude de flânerie ≤ 1,6, cordes des Gloomwisps
-- dans l'île (vitesse, pause, continuité), curseur incrémental, arc de la Comète, dispersion.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local SP = h:require("ReplicatedStorage.Shared.Logic.SeededPath")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local V3 = h.globals.Vector3

	local AMP = Balance.Spawn.WanderAmplitude
	local R = Balance.Wisps.PathRadius
	local SPEED = Balance.Wisps.Speed
	local PAUSE = Balance.Wisps.Pause
	local EPS = 1e-3

	local function rXZ(p)
		return math.sqrt(p.X * p.X + p.Z * p.Z)
	end

	describe("SeededPath.wander (§4.3)", function()
		it("amplitude ≤ 1,6 sur chaque axe, Y = 0, déterministe", function()
			local h2 = Harness.new()
			local SP2 = h2:require("ReplicatedStorage.Shared.Logic.SeededPath")
			for seed = 1, 200 do
				for k = 0, 60 do
					local t = k * 1.37
					local p = SP.wander(seed, t)
					expect(math.abs(p.X) <= AMP + EPS and math.abs(p.Z) <= AMP + EPS).toBe(true)
					expect(p.Y).toBe(0)
					expect(SP2.wander(seed, t)).toEqual(p)
				end
			end
		end)

		it("bouge lentement (fréquences 0,35-0,60 rad/s) et diffère d'une graine à l'autre", function()
			local maxStep = 0
			for seed = 1, 100 do
				for k = 0, 100 do
					local a = SP.wander(seed, k * 0.1)
					local b = SP.wander(seed, k * 0.1 + 0.1)
					maxStep = math.max(maxStep, (b - a).Magnitude)
				end
			end
			-- vitesse ≤ A × ω_max × √2 : déplacement par tick ≤ 1,6 × 0,6 × √2 × 0,1
			expect(maxStep <= AMP * Balance.Spawn.WanderFreqMax * math.sqrt(2) * 0.1 + EPS).toBe(true)
			expect(maxStep > 0).toBe(true)
			expect(SP.wander(1, 5) ~= SP.wander(2, 5)).toBe(true)
			-- entrées non finies : décalage fini
			local p = SP.wander(0 / 0, math.huge)
			expect(p.X == p.X and p.Z == p.Z).toBe(true)
		end)
	end)

	describe("SeededPath.chordAt (§4.15.4)", function()
		it("toujours dans l'île (r ≤ 165), à 7 studs/s au plus, sans saut entre deux cordes", function()
			for seed = 1, 12 do
				local t0 = 1000 + seed * 13.7
				local prev = SP.chordAt(seed, t0, t0)
				for k = 1, 3000 do
					local t = t0 + k * 0.1
					local p, dir = SP.chordAt(seed, t0, t)
					expect(rXZ(p) <= R + EPS).toBe(true)
					expect((p - prev).Magnitude <= SPEED * 0.1 + EPS).toBe(true)
					expect(dir.Magnitude).toBeNear(1, 1e-4)
					prev = p
				end
			end
		end)

		it("part d'un point du cercle, s'arrête 4 s au point d'arrivée, puis repart de là", function()
			local seed, t0 = 42, 5000
			local start = SP.chordAt(seed, t0, t0)
			expect(rXZ(start)).toBeNear(R, 1e-3)
			-- trouver la fin de la 1re corde : la position cesse de bouger pendant 4 s
			local t = t0
			local p = start
			local still = 0
			local arrivedAt = nil
			while t < t0 + 200 do
				t += 0.05
				local q = SP.chordAt(seed, t0, t)
				if (q - p).Magnitude < 1e-6 then
					still += 0.05
					if not arrivedAt then
						arrivedAt = t - 0.05
					end
				else
					if arrivedAt then
						break
					end
				end
				p = q
			end
			expect(arrivedAt).toBeTruthy()
			expect(still).toBeNear(PAUSE, 0.11)
			local arrival = SP.chordAt(seed, t0, arrivedAt + 1)
			expect(rXZ(arrival)).toBeNear(R, 1e-3)
			-- corde longue (≥ 2 R sin 50°) parcourue à 7 studs/s
			local length = (arrival - start).Magnitude
			expect(length >= 2 * R * math.sin(math.rad(50)) - 1e-3).toBe(true)
			expect(arrivedAt - t0).toBeNear(length / SPEED, 0.06)
			-- la corde suivante part du point d'arrivée, à la fin exacte de la pause
			local exactArrival = t0 + length / SPEED
			local after = SP.chordAt(seed, t0, exactArrival + PAUSE + 0.5)
			expect((after - arrival).Magnitude).toBeNear(0.5 * SPEED, 1e-3)
			-- avant t0 : point de départ
			expect(SP.chordAt(seed, t0, t0 - 50)).toEqual(start)
		end)

		it("déterministe et indépendant de l'ordre des appels (cache interne)", function()
			local h2 = Harness.new()
			local SP2 = h2:require("ReplicatedStorage.Shared.Logic.SeededPath")
			local times = {}
			for i = 1, 200 do
				times[i] = 777 + ((i * 7919) % 2000) * 0.37 -- ordre désordonné
			end
			for _, t in times do
				local a = SP.chordAt(9, 777, t)
				local b = SP2.chordAt(9, 777, t)
				expect(a).toEqual(b)
			end
			-- même graine, t0 différent : trajectoire décalée dans le temps
			expect(SP.chordAt(9, 777, 900)).toEqual(SP.chordAt(9, 1777, 1900))
		end)

		it("curseur incrémental : mêmes positions que chordAt, aperçu le long du trajet", function()
			local cursor = SP.newChordCursor(17, 100)
			for k = 0, 2000 do
				local t = 100 + k * 0.25
				local a, da = cursor:at(t)
				local b, db = SP.chordAt(17, 100, t)
				expect((a - b).Magnitude < 1e-6).toBe(true)
				expect((da - db).Magnitude < 1e-6).toBe(true)
			end
			-- revenir en arrière reste exact
			local back = cursor:at(150)
			expect((back - SP.chordAt(17, 100, 150)).Magnitude < 1e-6).toBe(true)
			-- aperçu : 6 points sur 15 studs, le premier à la position courante
			local pts = cursor:ahead(160, 15, 6)
			expect(#pts).toBe(6)
			expect((pts[1] - SP.chordAt(17, 100, 160)).Magnitude < 1e-6).toBe(true)
			local walked = 0
			for i = 2, 6 do
				walked += (pts[i] - pts[i - 1]).Magnitude
				expect(rXZ(pts[i]) <= R + EPS).toBe(true)
			end
			expect(walked <= 15 + EPS).toBe(true)
			expect(walked > 10).toBe(true)
			expect(#cursor:ahead(160, 15, 0)).toBe(0)
			expect(#cursor:ahead(160, 0 / 0, 1)).toBe(1)
		end)
	end)

	describe("SeededPath.cometSky et scatterPoint (§9.4, §4.7)", function()
		it("arc de la Comète : part haut dans le ciel, finit à l'impact, déterministe", function()
			local impact = V3.new(20, 0.3, -12)
			for id = 600, 60000, 600 do
				local top = SP.cometSky(id, impact, 0)
				expect(top.Y >= 200).toBe(true)
				expect((SP.cometSky(id, impact, 1) - impact).Magnitude < 1e-3).toBe(true)
				local prevY = math.huge
				for k = 0, 10 do
					local p = SP.cometSky(id, impact, k / 10)
					expect(p.Y <= prevY + 60).toBe(true) -- descend globalement (point de contrôle relevé)
					prevY = p.Y
				end
				expect(SP.cometSky(id, impact, 0.5)).toEqual(SP.cometSky(id, impact, 0.5))
			end
			-- alpha borné
			expect(SP.cometSky(600, impact, -3)).toEqual(SP.cometSky(600, impact, 0))
			expect(SP.cometSky(600, impact, 9)).toEqual(SP.cometSky(600, impact, 1))
		end)

		it("dispersion à 4-9 studs de l'origine, même Y, différente pour chaque Nebby", function()
			local origin = V3.new(100, 3, -40)
			local seen = {}
			for index = 1, 60 do
				local p = SP.scatterPoint(1234, index, origin)
				local d = (p - origin).Magnitude
				expect(d >= Balance.Snip.ScatterMin - EPS and d <= Balance.Snip.ScatterMax + EPS).toBe(true)
				expect(p.Y).toBe(origin.Y)
				expect(SP.scatterPoint(1234, index, origin)).toEqual(p)
				local key = string.format("%.3f:%.3f", p.X, p.Z)
				expect(seen[key]).toBeNil()
				seen[key] = true
			end
			expect(SP.scatterPoint(1, 1, origin) ~= SP.scatterPoint(2, 1, origin)).toBe(true)
		end)
	end)
end
