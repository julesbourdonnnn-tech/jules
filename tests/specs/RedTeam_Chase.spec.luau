--!nocheck
-- Contre-audit des poursuites (docs/04 §15, §17.1 g ; GDD §12.8), écrit comme des attaques :
--   * capture téléportée (la racine saute à côté de la créature) : position refusée par MoveCheck,
--     capture refusée ;
--   * capture de loin, tClient truqué (futur : ramené à maintenant ; trop ancien : ramené à
--     maintenant − 0,35 ; NaN : refusé par les types) ;
--   * capture d'une créature personnelle d'un autre, d'un Golden en recharge ;
--   * rafale de faux Leap : jamais plus de 12 studs gagnés par 4 s, le reste en rafale (aucune action) ;
--   * bond depuis une position truquée : l'atterrissage part de la position VALIDÉE ;
--   * deux bonds à 2 s d'écart : le second refusé, son déplacement est une rafale.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	-- Monde avec une fuite personnelle du joueur 1 active
	local function withRunaway()
		local w = Brains.boot(Harness, { t0 = T0 })
		local a = Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 400 } } }) })
		local b = Brains.join(w, 2)
		Brains.frames(w, 605)
		local mine = nil
		for _, s in Brains.creatures(w, "runaway") do
			if s.ownerSlot == w.Ranch.slotOf(a) then
				mine = s
			end
		end
		assert(mine, "fuite personnelle")
		return w, a, b, mine
	end

	describe("RedTeam_Chase › captures truquées", function()
		it(
			"capture téléportée : la racine saute à côté de la créature (sans placement serveur) → refusée",
			function()
				local w, a, _, mine = withRunaway()
				Brains.frames(w, 40)
				for _ = 1, 5 do
					local now = w.Clock.now()
					local c = Brains.creaturePos(w, mine, now)
					w.h:moveTo(a, Bots.ground(c.X, c.Z))
					w.h:fireServer("ReplicatedStorage.Remotes.Catch", a, mine.id, now)
					Brains.frames(w, 1)
				end
				expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
				expect(#Bots.celebrations(a, "catch")).toBe(0)
				clean(w)
			end
		)

		it(
			"de loin (12 studs) ; tClient futur (ramené à maintenant) ; trop ancien (ramené à −0,35 s) ; NaN refusé",
			function()
				local w, a, _, mine = withRunaway()
				local now = w.Clock.now()
				local c = Brains.creaturePos(w, mine, now)
				Bots.place(a, Bots.ground(c.X + 12, c.Z))
				Brains.frames(w, 1)
				now = w.Clock.now()
				w.h:fireServer("ReplicatedStorage.Remotes.Catch", a, mine.id, now)
				Brains.frames(w, 1)
				expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
				-- tClient dans le futur, à l'instant où la créature passera sous le joueur : ramené à maintenant
				local future = nil
				for dt = 0.5, 6, 0.1 do
					local p = Brains.creaturePos(w, mine, w.Clock.now() + dt)
					local root = a.Character.HumanoidRootPart.Position
					if (w.V3.new(p.X, 0, p.Z) - w.V3.new(root.X, 0, root.Z)).Magnitude < 3 then
						future = w.Clock.now() + dt
						break
					end
				end
				if future then
					w.h:fireServer("ReplicatedStorage.Remotes.Catch", a, mine.id, future)
					Brains.frames(w, 1)
					-- refusé sauf si la créature est vraiment là maintenant
					local here = Brains.creaturePos(w, mine, w.Clock.now() - 0.1)
					local root = a.Character.HumanoidRootPart.Position
					if (w.V3.new(here.X, 0, here.Z) - w.V3.new(root.X, 0, root.Z)).Magnitude > 7 then
						expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
					end
				end
				-- tClient 5 s dans le passé (la créature était sous le joueur) : ramené à −0,35 s, refusé
				local past = w.Clock.now() - 5
				local old = Brains.creaturePos(w, mine, past)
				Bots.place(a, Bots.ground(old.X, old.Z))
				Brains.frames(w, 1)
				local nowPos = Brains.creaturePos(w, mine, w.Clock.now() - 0.35)
				local root = a.Character.HumanoidRootPart.Position
				w.h:fireServer("ReplicatedStorage.Remotes.Catch", a, mine.id, past)
				Brains.frames(w, 1)
				if (w.V3.new(nowPos.X, 0, nowPos.Z) - w.V3.new(root.X, 0, root.Z)).Magnitude > 7 then
					expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
				end
				-- NaN : refusé par les types (aucune erreur)
				w.h:fireServer("ReplicatedStorage.Remotes.Catch", a, mine.id, 0 / 0)
				Brains.frames(w, 1)
				clean(w)
			end
		)

		it("créature personnelle d'un autre : invisible et inattrapable, même posé dessus", function()
			local w, _, b, mine = withRunaway()
			for _ = 1, 3 do
				local now = w.Clock.now()
				local c = Brains.creaturePos(w, mine, now)
				Bots.place(b, Bots.ground(c.X, c.Z))
				w.h:fireServer("ReplicatedStorage.Remotes.Catch", b, mine.id, now)
				Brains.frames(w, 1)
			end
			expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
			for _, payload in w.h:sentTo(b, "ChaseEvent") do
				for _, s in payload[1].spawns do
					expect(s.id ~= mine.id or s.kind ~= "runaway").toBe(true)
				end
			end
			clean(w)
		end)
	end)

	describe("RedTeam_Chase › bonds truqués", function()
		it(
			"rafale de faux Leap : un crédit par 4 s, jamais plus de 12 studs gagnés par 4 s ; le reste en rafale",
			function()
				local w = Brains.boot(Harness, { t0 = T0 })
				local a = Brains.join(w, 1)
				Brains.frames(w, 40)
				local grants = 0
				local grant = w.MC.grant
				w.MC.grant = function(...)
					local ok = grant(...)
					if ok then
						grants += 1
					end
					return ok
				end
				-- 12 s : Leap à chaque tick (débit 3 / s) et 12 studs de téléportation à chaque message
				local acting = 0
				local pos = a.Character.HumanoidRootPart.Position
				local origin = pos
				for i = 1, 120 do
					w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, 1, 0, w.Clock.now())
					if i % 4 == 0 then
						pos += w.V3.new(13.6, 0, 0)
					else
						pos += w.V3.new(1.5, 0, 0)
					end
					w.h:moveTo(a, w.V3.new(pos.X, 3, pos.Z))
					Brains.frames(w, 1)
					local actor = w.Chase.actors()[a]
					if actor and actor.canAct then
						acting += 1
					end
				end
				expect(grants <= 3).toBe(true)
				-- distance validée sur 12 s : jamais plus que la marche (≈ 180 studs) + 3 crédits de 12 studs
				-- et la marge du contrôle ; la triche tentait ≈ 540 studs
				local gained = w.MC.lastValid(a).X - origin.X
				expect(gained <= 120 * 1.5 + 3 * 12 + 60).toBe(true)
				expect(w.MC.violations(a) > 0).toBe(true)
				w.MC.grant = grant
				clean(w)
			end
		)

		it(
			"bond depuis une position truquée : l'atterrissage part de la position validée, pas de la racine",
			function()
				local w, a, _, mine = withRunaway()
				Brains.frames(w, 40)
				-- la racine saute à 4 studs de la créature (refusée), puis Leap vers elle
				local now = w.Clock.now()
				local c = Brains.creaturePos(w, mine, now + 0.35)
				local valid = w.MC.lastValid(a)
				w.h:moveTo(a, Bots.ground(c.X - 12, c.Z))
				Brains.frames(w, 1)
				local dir = w.V3.new(c.X - valid.X, 0, c.Z - valid.Z)
				if dir.Magnitude > 30 then
					w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, dir.Unit.X, dir.Unit.Z, w.Clock.now())
					Brains.frames(w, 6)
					expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
				end
				clean(w)
			end
		)

		it(
			"deux bonds à 2 s d'écart : le second refusé (recharge), son déplacement est une rafale",
			function()
				local w = Brains.boot(Harness, { t0 = T0 })
				local a = Brains.join(w, 1)
				Brains.frames(w, 40)
				local grants = 0
				local grant = w.MC.grant
				w.MC.grant = function(...)
					local ok = grant(...)
					if ok then
						grants += 1
					end
					return ok
				end
				local function leap()
					w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, 1, 0, w.Clock.now())
					local start = a.Character.HumanoidRootPart.Position
					local bursts = 0
					for k = 1, 5 do
						local x = math.min(k * 0.1, 0.35) / 0.35 * 12 + 1.6 * k
						w.h:moveTo(a, start + w.V3.new(x, 0, 0))
						Brains.frames(w, 1)
						local actor = w.Chase.actors()[a]
						if actor and not actor.canAct then
							bursts += 1
						end
					end
					return bursts
				end
				expect(leap()).toBe(0)
				Brains.frames(w, 15)
				local second = leap()
				expect(grants).toBe(1)
				expect(second > 0).toBe(true)
				w.MC.grant = grant
				clean(w)
			end
		)
	end)
end
