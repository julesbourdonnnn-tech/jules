--!nocheck
-- MoveCheck : note INT-MOVE du contrat v1.2 (paquet chase, docs/04 §22.2) appliquée au module du socle.
--   1. Bornes de Wobbleton et réglages (MaxRadius 330, GrantRetro 0,3, GrantMinGap 4, historique 0,5 s,
--      hauteur de racine partagée avec ZoneRules.feetY).
--   2. Monture (setRootOffset à 3 arguments, rootOffset) : un cavalier à chaque selle (saut 8,6 / 10,8 /
--      13) court et saute 60 s sans infraction ; monter et descendre en boucle ne permet aucun vol.
--   3. Bond accordé (grant) : bond puis action au tick suivant acceptés (même message reçu en retard,
--      crédit rétroactif) ; deux bonds à 2 s d'écart : le second est une rafale ; rafale de faux bonds :
--      jamais plus de 12 studs par 4 s.
--   4. positionAt : interpolée dans l'anneau de 0,5 s, nil hors de l'anneau, effacée par clear.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local DT = 0.1
	local T0 = 1800000000 + 41
	local G = 196.2

	local function setup()
		local h = Harness.new()
		local MC = h:require("ServerScriptService.Server.Util.MoveCheck")
		local Tuning = h:require("ServerScriptService.Server.Movement.Tuning")
		local Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas")
		local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
		return MC, h.globals.Vector3, Tuning, Formulas, Balance, h
	end

	-- Joueur simulé (clé de table) : apparu, exemption terminée, premier pas normal à T0
	local function newPlayer(MC, V3, start, speed)
		local player = { Name = "Rider", Parent = true }
		MC.noteSpeed(player, speed or 16, T0 - 10)
		MC.reset(player, start, T0 - MC.Config.Exemption)
		local p = {
			player = player,
			pos = start,
			now = T0,
			ground = 0,
			stats = { ok = 0, flag = 0, rewind = 0, burst = 0 },
		}
		assert(MC.step(player, start, DT, T0, 0) == "ok")
		return p
	end

	local function tick(MC, p, pos)
		p.now += DT
		if pos then
			p.pos = pos
		end
		local verdict, back, burst = MC.step(p.player, p.pos, DT, p.now, p.ground)
		p.stats[verdict] += 1
		if burst then
			p.stats.burst += 1
		end
		if verdict == "rewind" and back then
			p.pos = back
		end
		return verdict, back, burst
	end

	-- =========================================================================================
	describe("MoveCheck › INT-MOVE : réglages et bornes", function()
		it(
			"bornes de Wobbleton, réglages du bond et de l'historique, hauteur de racine partagée",
			function()
				local MC, _, Tuning, _, _, h = setup()
				expect(MC.Config.CenterX).toBe(0)
				expect(MC.Config.CenterZ).toBe(0)
				expect(MC.Config.MaxRadius).toBe(330)
				expect(MC.Config.MaxClimbSpeed).toBe(12)
				expect(Tuning.GrantRetro).toBe(0.3)
				expect(Tuning.GrantMinGap).toBe(4)
				expect(Tuning.PositionHistory).toBe(0.5)
				local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
				expect(WorldLayout.Const.RootHeight).toBe(Tuning.RootHeight)
				expect(type(MC.setRootOffset)).toBe("function")
				expect(type(MC.rootOffset)).toBe("function")
				expect(type(MC.grant)).toBe("function")
				expect(type(MC.positionAt)).toBe("function")
			end
		)

		it("au-delà de r = 330 : retour ; à r = 320 (murs à 322) : accepté", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(318, 3, 0), 16)
			expect((tick(MC, p, V3.new(320, 3, 0)))).toBe("ok")
			local q = newPlayer(MC, V3, V3.new(329, 3, 0), 16)
			local verdict = tick(MC, q, V3.new(331, 3, 0))
			expect(verdict).toBe("rewind")
		end)
	end)

	-- =========================================================================================
	describe("MoveCheck › INT-MOVE : monture", function()
		it(
			"rootOffset : 0 à pied, hausse bornée [0 ; MaxRootOffset], valeurs non finies ignorées",
			function()
				local MC, _, Tuning = setup()
				local player = { Name = "R" }
				expect(MC.rootOffset(player)).toBe(0)
				MC.setRootOffset(player, 6, 13, T0)
				expect(MC.rootOffset(player)).toBe(6)
				MC.setRootOffset(player, 0 / 0, 13, T0)
				expect(MC.rootOffset(player)).toBe(6)
				MC.setRootOffset(player, 1e9, 1e9, T0)
				expect(MC.rootOffset(player)).toBe(Tuning.MaxRootOffset)
				MC.setRootOffset(player, -4, 7.2, T0)
				expect(MC.rootOffset(player)).toBe(0)
				MC.clear(player)
				expect(MC.rootOffset(player)).toBe(0)
			end
		)

		it(
			"cavalier à chaque selle (8,6 / 10,8 / 13) : court et saute 60 s, aucune infraction ni rafale",
			function()
				for saddle = 1, 3 do
					for _, group in { 1, 2 } do
						local MC, V3, _, Formulas, Balance = setup()
						local stats = Formulas.rideStats(saddle)
						local offset = stats.hipHeight - Balance.Ride.BaseHipHeight
						local center = V3.new(100, 0, 40)
						local radius = 60
						local p = newPlayer(MC, V3, center + V3.new(radius, 3, 0), Balance.Ride.BaseWalkSpeed)
						-- montée : WalkSpeed relevé, racine relevée par le client un ping plus tard
						MC.noteSpeed(p.player, stats.walkSpeed, p.now)
						MC.setRootOffset(p.player, offset, stats.jumpHeight, p.now)
						local v0 = math.sqrt(2 * G * stats.jumpHeight)
						local air = 2 * v0 / G
						local angle = 0
						local jumpAt = p.now + 0.5
						local pending = nil
						for i = 1, 600 do
							local t = p.now + DT
							angle += stats.walkSpeed * DT / radius
							local y = 3 + (if i >= 3 then offset else 0)
							local dtj = t - jumpAt
							if dtj >= 0 and dtj <= air then
								y += v0 * dtj - G * dtj * dtj / 2
							elseif dtj > air then
								jumpAt = t + 0.3
							end
							local truePos = center
								+ V3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
							-- paquets groupés par `group` : la position vue ne change qu'un tick sur `group`
							if i % group == 0 then
								pending = truePos
							else
								pending = nil
							end
							tick(MC, p, pending)
						end
						expect({
							saddle = saddle,
							group = group,
							flags = p.stats.flag,
							rewinds = p.stats.rewind,
						}).toEqual({
							saddle = saddle,
							group = group,
							flags = 0,
							rewinds = 0,
						})
						expect(p.stats.burst).toBe(0)
						expect(MC.violations(p.player)).toBe(0)
					end
				end
			end
		)

		it("descente forcée : racine qui retombe de la selle géante, aucune infraction", function()
			local MC, V3, _, Formulas, Balance = setup()
			local stats = Formulas.rideStats(3)
			local offset = stats.hipHeight - Balance.Ride.BaseHipHeight
			local p = newPlayer(MC, V3, V3.new(0, 3, 50), 16)
			MC.setRootOffset(p.player, offset, stats.jumpHeight, p.now)
			tick(MC, p, V3.new(0, 3 + offset, 50))
			for _ = 1, 10 do
				tick(MC, p)
			end
			MC.setRootOffset(p.player, 0, Balance.Ride.BaseJumpHeight, p.now)
			-- la racine reste en haut un ping (0,3 s), puis retombe
			tick(MC, p)
			tick(MC, p)
			tick(MC, p)
			tick(MC, p, V3.new(0, 3, 50))
			for _ = 1, 30 do
				tick(MC, p)
			end
			expect(p.stats.flag + p.stats.rewind).toBe(0)
		end)

		it(
			"monter et descendre en boucle ne permet aucun vol (planer haut reste signalé puis ramené)",
			function()
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(-80, 3, 20), 16)
				local on = false
				local maxAcceptedY = 0
				-- le tricheur monte de 1,5 stud par tick et bascule la monture toutes les 0,5 s (débit de Ride)
				local maxAfterFirstRewind = 0
				local rewound = false
				local firstRewindY = math.huge
				for i = 1, 300 do
					if i % 5 == 0 then
						on = not on
						MC.setRootOffset(p.player, if on then 6 else 0, if on then 13 else 7.2, p.now)
					end
					local target = V3.new(p.pos.X, math.min(p.pos.Y + 1.5, 60), p.pos.Z)
					local verdict, back = tick(MC, p, target)
					if verdict == "ok" then
						maxAcceptedY = math.max(maxAcceptedY, MC.lastValid(p.player).Y)
						if rewound then
							maxAfterFirstRewind = math.max(maxAfterFirstRewind, MC.lastValid(p.player).Y)
						end
					elseif verdict == "rewind" then
						if not rewound then
							firstRewindY = back.Y
						end
						rewound = true
					end
				end
				expect(p.stats.rewind > 0).toBe(true)
				-- jamais acceptée plus haut que la racine debout relevée + portée verticale + 1 s de montée
				expect(maxAcceptedY <= 3 + 6 + 4 + 1.5 * 11).toBe(true)
				-- après le premier retour, aucune position plus haute n'est acceptée (aucune échelle)
				expect(maxAfterFirstRewind <= firstRewindY).toBe(true)
				expect(MC.lastValid(p.player).Y <= maxAcceptedY).toBe(true)
				expect(MC.canAct(p.player, p.now)).toBe(false)
			end
		)

		it("cavalier honnête qui monte et descend sur place en boucle : aucune infraction", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(30, 3, -30), 16)
			local on = false
			local offsetNow = 0
			for i = 1, 300 do
				if i % 10 == 0 then
					on = not on
					MC.setRootOffset(p.player, if on then 6 else 0, if on then 13 else 7.2, p.now)
				end
				-- la racine suit avec 2 ticks de retard (ping)
				if i % 10 == 2 then
					offsetNow = if on then 6 else 0
				end
				tick(MC, p, V3.new(30, 3 + offsetNow, -30))
			end
			expect(p.stats.flag + p.stats.rewind).toBe(0)
		end)
	end)

	-- =========================================================================================
	describe("MoveCheck › INT-MOVE : bond accordé", function()
		-- Bond de 12 studs en 0,35 s le long de X en marchant à 16 ; `grantAt` : décalage (ticks) de
		-- la réception du message Leap par rapport au début du bond (0 = même tick)
		local function leap(MC, V3, p, granted, grantDelayTicks)
			local start = p.pos
			local t0 = p.now
			local results = {}
			for k = 1, 6 do
				if granted and k - 1 == grantDelayTicks then
					results.grant = MC.grant(p.player, 12, 0.35, t0, p.now)
				end
				local t = math.min(k * DT, 0.35)
				local x = 12 * t / 0.35 + 1.6 * k
				local _, _, burst = tick(MC, p, V3.new(start.X + x, start.Y, start.Z))
				results[k] = burst
			end
			return results
		end

		it("bond puis action au tick suivant : acceptés (aucune rafale, canAct vrai)", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(0, 3, 100), 16)
			for _ = 1, 10 do
				tick(MC, p, p.pos + V3.new(1.6, 0, 0))
			end
			local r = leap(MC, V3, p, true, 0)
			expect(r.grant).toBe(true)
			expect(p.stats.burst).toBe(0)
			expect(p.stats.flag).toBe(0)
			expect(MC.canAct(p.player, p.now)).toBe(true)
			-- tick suivant l'atterrissage : toujours agissant
			local _, _, burst = tick(MC, p, p.pos + V3.new(1.6, 0, 0))
			expect(burst).toBe(false)
			expect(MC.canAct(p.player, p.now)).toBe(true)
		end)

		it(
			"message Leap reçu 0,2 s après le début du bond (ping) : crédit rétroactif, dette remboursée",
			function()
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(0, 3, 120), 16)
				for _ = 1, 10 do
					tick(MC, p, p.pos + V3.new(1.6, 0, 0))
				end
				local r = leap(MC, V3, p, true, 2)
				expect(r.grant).toBe(true)
				expect(p.stats.flag).toBe(0)
				expect(MC.canAct(p.player, p.now)).toBe(true)
				local _, _, burst = tick(MC, p, p.pos + V3.new(1.6, 0, 0))
				expect(burst).toBe(false)
			end
		)

		it("contrôle : le même bond SANS crédit laisse une dette (rafale)", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(0, 3, 140), 16)
			for _ = 1, 10 do
				tick(MC, p, p.pos + V3.new(1.6, 0, 0))
			end
			leap(MC, V3, p, false)
			expect(p.stats.burst > 0).toBe(true)
		end)

		it(
			"deux bonds à 2 s d'écart : le second crédit est refusé et le second bond est une rafale",
			function()
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(0, 3, 160), 16)
				for _ = 1, 10 do
					tick(MC, p, p.pos + V3.new(1.6, 0, 0))
				end
				local first = leap(MC, V3, p, true, 0)
				expect(first.grant).toBe(true)
				expect(p.stats.burst).toBe(0)
				for _ = 1, 14 do
					tick(MC, p, p.pos + V3.new(1.6, 0, 0))
				end
				local second = leap(MC, V3, p, true, 0)
				expect(second.grant).toBe(false)
				expect(p.stats.burst > 0).toBe(true)
				-- après 4 s, un nouveau crédit est accordé
				for _ = 1, 20 do
					tick(MC, p, p.pos + V3.new(1.6, 0, 0))
				end
				expect(MC.grant(p.player, 12, 0.35, p.now, p.now)).toBe(true)
			end
		)

		it("rafale de faux bonds : un crédit par 4 s, jamais plus de 12 studs gagnés par 4 s", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(-100, 3, -100), 16)
			local accepted = 0
			local gained = 0
			-- 12 s : Leap envoyé au débit maximal (3 / s) ; à chaque message, le tricheur se téléporte de
			-- 12 studs en plus de la marche
			for i = 1, 120 do
				local spam = i % 3 == 0
				if spam and MC.grant(p.player, 12, 0.35, p.now, p.now) then
					accepted += 1
				end
				local before = MC.lastValid(p.player)
				local jumpBy = if spam then 12 else 0
				local _, _, burst = tick(MC, p, p.pos + V3.new(1.6 + jumpBy, 0, 0))
				local after = MC.lastValid(p.player)
				if not burst and spam and (after - before).Magnitude > 6.4 then
					gained += 12
				end
			end
			expect(accepted).toBe(3)
			expect(gained <= 12 * 3).toBe(true)
		end)

		it("joueur inconnu : crédit refusé ; tStart non fini : instant de réception", function()
			local MC, V3 = setup()
			expect(MC.grant({ Name = "X" }, 12, 0.35, T0, T0)).toBe(false)
			local p = newPlayer(MC, V3, V3.new(10, 3, 10), 16)
			expect(MC.grant(p.player, 12, 0.35, 0 / 0, p.now)).toBe(true)
		end)
	end)

	-- =========================================================================================
	describe("MoveCheck › INT-MOVE : positionAt", function()
		it(
			"interpolée entre deux positions acceptées, nil hors de l'anneau de 0,5 s, effacée par clear",
			function()
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(0, 3, 0), 16)
				for _ = 1, 10 do
					tick(MC, p, p.pos + V3.new(1, 0, 0))
				end
				local now = p.now
				local at = MC.positionAt(p.player, now)
				expect(at.X).toBeNear(10, 6)
				local mid = MC.positionAt(p.player, now - 0.05)
				expect(mid.X).toBeNear(9.5, 6)
				local back = MC.positionAt(p.player, now - 0.35)
				expect(back.X).toBeNear(6.5, 6)
				expect(MC.positionAt(p.player, now - 0.5) ~= nil).toBe(true)
				expect(MC.positionAt(p.player, now - 0.7)).toBeNil()
				expect(MC.positionAt(p.player, now + 0.2)).toBeNil()
				expect(MC.positionAt(p.player, 0 / 0)).toBeNil()
				MC.clear(p.player)
				expect(MC.positionAt(p.player, now)).toBeNil()
			end
		)

		it("position refusée (téléportation signalée) : jamais dans l'anneau", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(0, 3, 0), 16)
			tick(MC, p, V3.new(1, 3, 0))
			local verdict = tick(MC, p, V3.new(80, 3, 0))
			expect(verdict).toBe("flag")
			local at = MC.positionAt(p.player, p.now - DT)
			expect(at.X).toBeNear(1, 6)
			expect(MC.positionAt(p.player, p.now)).toBeNil()
		end)
	end)
end
