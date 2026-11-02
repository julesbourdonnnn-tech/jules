--!nocheck
-- ChaseService : défauts trouvés par la revue adversariale du lot chase (chaque test reproduit le
-- défaut avant sa correction).
--   1. Bond sous latence : le point d'atterrissage partait de MoveCheck.positionAt(tClient), position
--      que le serveur avait reçue À l'instant tClient, donc celle du client L secondes plus tôt ; un
--      joueur qui poursuit (14 studs/s, 250 ms) atterrissait 3,5 studs trop court côté serveur et ses
--      bonds bien visés étaient refusés. Même modèle que la capture (Chase.spec) : la position reçue à
--      l'ARRIVÉE du message est celle du client à tClient.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 301 -- Rush en cours

	-- d = écart vu par le client entre son atterrissage et la fuite à tClient + 0,35 s
	local function run(L, dmin, dmax, trials)
		local w = Brains.boot(Harness, { t0 = T0 })
		local owner = Brains.join(
			w,
			1,
			{ profile = Brains.profile(w, { rush = true, squishies = { { s = 2, z = 500 } } }) }
		)
		local booper = Brains.join(w, 2, { profile = Brains.profile(w, { rush = true }) })
		local catcher = Brains.join(w, 3, { profile = Brains.profile(w, { rush = true }) })
		Brains.frames(w, 2)
		local rng = Brains.rng(4242 + math.floor(L * 1000) + math.floor(dmin * 10))
		local accepted = 0
		for _ = 1, trials do
			w.Chase.returnEscapes(owner, "cozy")
			w.Signals.Booped:Fire(booper, owner, "1", rng:NextNumber(0, 2 * math.pi))
			local esc = nil
			for _, s in Brains.creatures(w, "escape") do
				esc = s
			end
			assert(esc, "fuite créée")
			local path = w.SeededPath.fromSpawn(esc)
			local s0 = w.Clock.now()
			-- recharge du bond (4 s) et écart minimal des crédits de MoveCheck (4 s) respectés
			local tc = s0 + rng:NextNumber(4.6, 6)
			local d = rng:NextNumber(dmin, dmax)
			local target = path(tc + 0.35)
			local clientStart, dir = nil, nil
			for _ = 1, 60 do
				local angle = rng:NextNumber(0, 2 * math.pi)
				local u = w.V3.new(math.cos(angle), 0, math.sin(angle))
				-- le client poursuit à 14 studs/s dans la direction du bond ; atterrissage à d studs
				-- AVANT la fuite (vu chez lui)
				local press = w.V3.new(target.X, 3, target.Z) - u * (12 + d)
				local clear = true
				for k = -14, 8 do
					local q = press + u * 14 * (k * 0.1)
					if w.WL.ranchAt(q) ~= 0 or w.WL.blocked(q.X, q.Z, 1) then
						clear = false
						break
					end
				end
				if clear then
					clientStart, dir = press, u
					break
				end
			end
			assert(clientStart, "trajectoire dégagée")
			local function clientAt(t)
				local p = clientStart + dir * 14 * (t - tc)
				return w.V3.new(p.X, 3, p.Z)
			end
			while w.Clock.now() < tc - 1.2 - L do
				Bots.frame()
			end
			Bots.place(catcher, clientAt(w.Clock.now() - L))
			local sent = false
			for _ = 1, 200 do
				local now = w.Clock.now()
				local arrival = tc + L
				if not sent and now + 0.1 > arrival then
					w.Clock.freeze(math.max(now, arrival))
					w.h:moveTo(catcher, clientAt(w.Clock.now() - L))
					w.h:fireServer("ReplicatedStorage.Remotes.Leap", catcher, dir.X, dir.Z, tc)
					sent = true
				end
				Bots.frame(function()
					w.h:moveTo(catcher, clientAt(w.Clock.now() + Bots.DT - L))
				end)
				if sent and w.Clock.now() > arrival + 0.5 then
					break
				end
			end
			if w.Chase.active()[esc.id] == nil then
				accepted += 1
			end
		end
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
		return accepted
	end

	describe("ChaseService (revue) › bond sous latence", function()
		it(
			"250 ms, joueur qui poursuit : atterrissage à ≤ 4,5 studs de la fuite (vu chez lui) accepté",
			function()
				local ok = run(0.25, 3, 4.5, 10)
				expect(ok >= 9).toBe(true)
			end
		)
		it(
			"250 ms, joueur qui poursuit : atterrissage à ≥ 7,5 studs (vu chez lui) jamais accepté",
			function()
				expect(run(0.25, 7.5, 9, 6)).toBe(0)
			end
		)
	end)
end
