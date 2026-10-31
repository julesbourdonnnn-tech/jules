--!nocheck
-- MoveCheck (paquet conga) : contrôle de déplacement du GDD §12.7 — marche, Dash, sauts, gels réseau
-- tolérés ; vitesse, téléportation, vol, sortie de l'île signalés puis ramenés ; exemptions,
-- restriction, récidives (exclusion des classements), jamais d'erreur sur une entrée invalide.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local DT = 0.1
	local T0 = 1000

	local function setup()
		local h = Harness.new()
		local MoveCheck = h:require("ServerScriptService.Server.Util.MoveCheck")
		local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
		return MoveCheck, Balance, h.globals.Vector3
	end

	-- Joueur simulé (MoveCheck n'utilise le joueur que comme clé) : apparu, exemption terminée à T0,
	-- puis un premier pas normal à T0 (référence fraîche)
	local function newPlayer(MoveCheck, V3, pos, speed)
		local player = { Name = "Tester" }
		local start = pos or V3.new(100, 3, 0)
		local B = Harness.new():require("ReplicatedStorage.Shared.Config.Balance")
		MoveCheck.noteSpeed(player, speed or 16, T0 - 10)
		MoveCheck.reset(player, start, T0 - B.MoveCheck.Exemption)
		local p = { player = player, pos = start + V3.new(0, 0, 0.5), now = T0 }
		assert(MoveCheck.step(player, p.pos, DT, T0, 0) == "ok")
		return p
	end

	-- Avance d'un tick en déplaçant le joueur de `delta`
	local function move(MoveCheck, p, delta, ground)
		p.now += DT
		p.pos = p.pos + delta
		return MoveCheck.step(p.player, p.pos, DT, p.now, ground or 0)
	end

	describe("MoveCheck › joueurs honnêtes", function()
		it("marche à 16 et à 26 (Foulée max) pendant 30 s sans aucune infraction", function()
			local MC, _, V3 = setup()
			for _, speed in { 16, 26 } do
				-- tour de l'île sur le cercle r = 120 (vitesse tangentielle = WalkSpeed)
				local radius = 120
				local p = newPlayer(MC, V3, V3.new(radius, 3, -0.5), speed)
				for i = 1, 300 do
					local angle = i * DT * speed / radius
					local target = V3.new(radius * math.cos(angle), 3, radius * math.sin(angle))
					local verdict = move(MC, p, target - p.pos)
					expect(verdict).toBe("ok")
				end
				expect(MC.violations(p.player)).toBe(0)
			end
		end)

		it(
			"Dash (+10) puis retour à la normale : la vitesse max des 0,5 s précédentes reste tolérée",
			function()
				local MC, _, V3 = setup()
				local p = newPlayer(MC, V3)
				MC.noteSpeed(p.player, 26, T0)
				for _ = 1, 10 do
					expect(move(MC, p, V3.new(2.6, 0, 0))).toBe("ok")
				end
				MC.noteSpeed(p.player, 16, p.now)
				-- le client applique la baisse avec un peu de retard
				for _ = 1, 4 do
					expect(move(MC, p, V3.new(2.6, 0, 0))).toBe("ok")
				end
			end
		)

		it(
			"un saut (≈ 4,3 studs de montée sur un tick) et une chute libre ne sont pas des infractions",
			function()
				local MC, _, V3 = setup()
				local p = newPlayer(MC, V3)
				expect(move(MC, p, V3.new(1.6, 4.3, 0))).toBe("ok")
				expect(move(MC, p, V3.new(1.6, 2.4, 0))).toBe("ok")
				expect(move(MC, p, V3.new(1.6, -6.7, 0))).toBe("ok")
				-- chute d'un rebord : descente libre de 7 studs en un tick (sol plus bas)
				p.pos = p.pos + V3.new(0, 7, 0)
				MC.reset(p.player, p.pos, p.now - 10)
				expect(move(MC, p, V3.new(0, -7, 0), -2)).toBe("ok")
				expect(MC.violations(p.player)).toBe(0)
			end
		)

		it("gel réseau de 1 s puis rafale : toléré (crédit de temps à l'arrêt)", function()
			local MC, _, V3 = setup()
			local p = newPlayer(MC, V3)
			for _ = 1, 10 do
				expect(move(MC, p, V3.new(0, 0, 0))).toBe("ok") -- positions figées
			end
			expect(move(MC, p, V3.new(17.6, 0, 0))).toBe("ok") -- 1,1 s de marche d'un coup
		end)

		it("pas de serveur en retard (3 pas rattrapés au même instant) : toléré au Dash", function()
			local MC, _, V3 = setup()
			local p = newPlayer(MC, V3)
			MC.noteSpeed(p.player, 36, T0)
			p.now += 0.3
			p.pos = p.pos + V3.new(10.8, 0, 0)
			expect(MC.step(p.player, p.pos, DT, p.now, 0)).toBe("ok")
			expect(MC.step(p.player, p.pos, DT, p.now, 0)).toBe("ok")
		end)

		it("exemption de 3 s après reset (apparition, PivotTo serveur)", function()
			local MC, B, V3 = setup()
			local player = {}
			MC.noteSpeed(player, 16, T0)
			MC.reset(player, V3.new(150, 3, 0), T0)
			-- paquets « en vol » d'avant le déplacement serveur : signalés, jamais comptés, jamais
			-- acceptés comme référence (sinon : 3 s de téléportation libre après chaque réapparition)
			local now = T0
			for _ = 1, 10 do
				now += DT
				expect(MC.step(player, V3.new(20, 3, 20), DT, now, 0)).toBe("flag")
			end
			expect(MC.lastValid(player)).toEqual(V3.new(150, 3, 0))
			expect(MC.violations(player)).toBe(0)
			expect(MC.recentRewinds(player, now)).toBe(0)
			expect(MC.isRestricted(player, now)).toBe(false)
			-- le client a appliqué le déplacement : accepté normalement
			now += DT
			expect(MC.step(player, V3.new(150.5, 3, 0), DT, now, 0)).toBe("ok")
			-- immobile jusqu'à la fin de l'exemption, puis un bond de 60 studs : signalé
			while now < T0 + B.MoveCheck.Exemption do
				now += DT
				expect(MC.step(player, V3.new(150.5, 3, 0), DT, now, 0)).toBe("ok")
			end
			expect(MC.step(player, V3.new(90, 3, 0), DT, now + DT, 0)).toBe("flag")
			expect(MC.violations(player)).toBe(1)
		end)

		it(
			"sans position acceptée depuis la référence, le crédit de temps reste borné (pas de bond de 100 studs)",
			function()
				local MC, B, V3 = setup()
				-- après une apparition : positions incohérentes pendant ~3 s, puis bond depuis la référence
				local player = {}
				MC.noteSpeed(player, 26, T0)
				MC.reset(player, V3.new(150, 3, 0), T0)
				local now = T0
				while now < T0 + B.MoveCheck.Exemption - 0.15 do
					now += DT
					expect(MC.step(player, V3.new(-150, 3, 0), DT, now, 0)).toBe("flag")
				end
				now += DT
				expect(MC.step(player, V3.new(50, 3, 0), DT, now, 0)).toBe("flag")
				expect(MC.lastValid(player)).toEqual(V3.new(150, 3, 0))
				-- après un retour : 3 s de restriction, puis bond de 100 studs depuis le point de retour
				local p = newPlayer(MC, V3, V3.new(100, 3, 0), 26)
				local start = p.pos
				for _ = 1, 3 do
					p.now += DT
					MC.step(p.player, start + V3.new(-60, 0, 0), DT, p.now, 0)
				end
				expect(MC.isRestricted(p.player, p.now)).toBe(true)
				p.now += B.MoveCheck.RewindLockout
				expect(MC.step(p.player, start + V3.new(-100, 0, 0), DT, p.now, 0)).toBe("flag")
			end
		)

		it("après l'exemption, un client resté loin de la référence est ramené (retour)", function()
			local MC, B, V3 = setup()
			local player = {}
			MC.noteSpeed(player, 16, T0)
			MC.reset(player, V3.new(150, 3, 0), T0)
			local now = T0
			local verdict, back
			while now < T0 + B.MoveCheck.Exemption + 1 do
				now += DT
				verdict, back = MC.step(player, V3.new(20, 3, 20), DT, now, 0)
				if verdict == "rewind" then
					break
				end
			end
			expect(verdict).toBe("rewind")
			expect(back).toEqual(V3.new(150, 3, 0))
			expect(now > T0 + B.MoveCheck.Exemption).toBe(true)
		end)
	end)

	describe("MoveCheck › tricheurs", function()
		it(
			"vitesse ×3 soutenue (4,8 studs par tick, sous la marge d'un seul tick) : détectée sur la fenêtre",
			function()
				local MC, B, V3 = setup()
				local p = newPlayer(MC, V3)
				local step = V3.new(16 * 3 * DT, 0, 0)
				expect(move(MC, p, step)).toBe("ok")
				local valid = p.pos
				expect(move(MC, p, step)).toBe("flag")
				expect(move(MC, p, step)).toBe("flag")
				local verdict, back = move(MC, p, step)
				expect(verdict).toBe("rewind")
				expect(back).toEqual(valid)
				expect(MC.isRestricted(p.player, p.now)).toBe(true)
				expect(MC.isRestricted(p.player, p.now + B.MoveCheck.RewindLockout + 0.01)).toBe(false)
				expect(MC.recentRewinds(p.player, p.now)).toBe(1)
				expect(MC.violations(p.player)).toBe(3)
			end
		)

		it("immobile puis bond : le crédit d'arrêt reste borné par la fenêtre soutenue", function()
			local MC, _, V3 = setup()
			local p = newPlayer(MC, V3)
			for _ = 1, 20 do
				expect(move(MC, p, V3.new(0, 0, 0))).toBe("ok")
			end
			-- 40 studs d'un coup après 2 s d'arrêt : plus que 1,1 s de marche à 16 × 1,5 + 4
			expect(move(MC, p, V3.new(40, 0, 0))).toBe("flag")
		end)

		it("vitesse ×9 : signalée dès le premier tick", function()
			local MC, _, V3 = setup()
			local p = newPlayer(MC, V3)
			expect(move(MC, p, V3.new(14.4, 0, 0))).toBe("flag")
		end)

		it(
			"téléportation : signalée tick après tick (jamais acceptée au tick suivant), retour au 3e",
			function()
				local MC, _, V3 = setup()
				local p = newPlayer(MC, V3)
				local start = p.pos
				p.now += DT
				expect(MC.step(p.player, start + V3.new(-40, 0, 0), DT, p.now, 0)).toBe("flag")
				p.now += DT
				expect(MC.step(p.player, start + V3.new(-40, 0, 1), DT, p.now, 0)).toBe("flag")
				p.now += DT
				local verdict, back = MC.step(p.player, start + V3.new(-40, 0, 2), DT, p.now, 0)
				expect(verdict).toBe("rewind")
				expect(back).toEqual(start)
			end
		)

		it("une infraction isolée ne déclenche rien et la fenêtre de 5 s s'oublie", function()
			local MC, B, V3 = setup()
			local p = newPlayer(MC, V3)
			for _ = 1, 2 do
				p.now += DT
				expect(MC.step(p.player, p.pos + V3.new(30, 0, 0), DT, p.now, 0)).toBe("flag")
			end
			-- retour à la normale, puis 2 nouvelles infractions plus de 5 s après
			p.now += B.MoveCheck.FlagWindow + 0.5
			expect(MC.step(p.player, p.pos, DT, p.now, 0)).toBe("ok")
			for _ = 1, 2 do
				p.now += DT
				expect(MC.step(p.player, p.pos + V3.new(30, 0, 0), DT, p.now, 0)).toBe("flag")
			end
			expect(MC.recentRewinds(p.player, p.now)).toBe(0)
		end)

		it("vol vertical (montée > 12 studs/s) signalé", function()
			local MC, _, V3 = setup()
			local p = newPlayer(MC, V3)
			expect(move(MC, p, V3.new(0, 10, 0))).toBe("flag")
		end)

		it("altitude > sol + 14 pendant plus de 1,5 s → retour immédiat", function()
			local MC, _, V3 = setup()
			local p = newPlayer(MC, V3)
			-- montée progressive (autorisée tick par tick) jusqu'à 18 studs au-dessus du sol
			for _ = 1, 6 do
				move(MC, p, V3.new(0, 3, 0))
			end
			local verdict
			for _ = 1, 16 do
				verdict = move(MC, p, V3.new(0, 0, 0))
				if verdict == "rewind" then
					break
				end
			end
			expect(verdict).toBe("rewind")
		end)

		it("hors de l'île (r > 182) ou sous le monde (Y < −5) → retour immédiat", function()
			local MC, _, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(178, 3, 0))
			local valid = MC.lastValid(p.player)
			local verdict, back = move(MC, p, V3.new(5, 0, 0))
			expect(verdict).toBe("rewind")
			expect(back).toEqual(valid)
			local q = newPlayer(MC, V3, V3.new(50, 3, 50))
			q.now += 10
			local v2 = MC.step(q.player, V3.new(50, -6, 50), DT, q.now, 0)
			expect(v2).toBe("rewind")
		end)

		it("grâce après un retour : les positions « en vol » ne déclenchent pas un 2e retour", function()
			local MC, B, V3 = setup()
			local p = newPlayer(MC, V3)
			local far = p.pos + V3.new(60, 0, 0)
			local verdict
			for _ = 1, 3 do
				p.now += DT
				verdict = MC.step(p.player, far, DT, p.now, 0)
			end
			expect(verdict).toBe("rewind")
			-- le client met 3 ticks à appliquer le PivotTo : signalés, sans nouveau retour
			for _ = 1, 3 do
				p.now += DT
				expect(MC.step(p.player, far, DT, p.now, 0)).toBe("flag")
			end
			p.now += DT
			expect(MC.step(p.player, MC.lastValid(p.player), DT, p.now, 0)).toBe("ok")
			expect(MC.recentRewinds(p.player, p.now)).toBe(1)
			-- mais un tricheur qui reste loin est ramené dès la fin de la grâce
			p.now += B.MoveCheck.RewindLockout
			local last
			for _ = 1, 3 do
				p.now += DT
				last = MC.step(p.player, far + V3.new(80, 0, 0), DT, p.now, 0)
			end
			expect(last).toBe("rewind")
			expect(MC.recentRewinds(p.player, p.now)).toBe(2)
		end)

		it("récidives comptées sur 10 min (exclusion des classements à 10)", function()
			local MC, B, V3 = setup()
			local p = newPlayer(MC, V3)
			for _ = 1, B.MoveCheck.StrikesForBan do
				for _ = 1, 3 do
					p.now += DT
					MC.step(p.player, p.pos + V3.new(70, 0, 0), DT, p.now, 0)
				end
				p.now += B.MoveCheck.RewindLockout + 0.1 -- grâce terminée
				MC.step(p.player, MC.lastValid(p.player), DT, p.now, 0)
			end
			expect(MC.recentRewinds(p.player, p.now)).toBe(B.MoveCheck.StrikesForBan)
			expect(MC.recentRewinds(p.player, p.now + B.MoveCheck.StrikeWindow + 1)).toBe(0)
		end)
	end)

	describe("MoveCheck › robustesse", function()
		it("positions, temps et vitesses invalides : jamais d'erreur", function()
			local MC, _, V3 = setup()
			local player = {}
			expect(MC.step(player, V3.new(0 / 0, 0, 0), DT, T0, 0)).toBe("flag")
			expect(MC.step(player, V3.new(1, 3, 1), DT, 0 / 0, 0)).toBe("flag")
			MC.noteSpeed(player, 0 / 0, T0)
			MC.noteSpeed(player, -5, T0)
			MC.noteSpeed(player, math.huge, T0)
			MC.reset(player, V3.new(math.huge, 0, 0), T0)
			-- première vraie position sans reset : devient la référence
			expect(MC.step(player, V3.new(10, 3, 10), DT, T0, 0 / 0)).toBe("ok")
			expect(MC.isRestricted(player, T0)).toBe(false)
			expect(MC.lastValid(player)).toEqual(V3.new(10, 3, 10))
		end)

		it("clear oublie tout ; un joueur inconnu n'a ni restriction ni infraction", function()
			local MC, _, V3 = setup()
			local p = newPlayer(MC, V3)
			move(MC, p, V3.new(50, 0, 0))
			expect(MC.violations(p.player)).toBe(1)
			MC.clear(p.player)
			expect(MC.violations(p.player)).toBe(0)
			expect(MC.lastValid(p.player)).toBeNil()
			expect(MC.recentRewinds(p.player, T0)).toBe(0)
			expect(MC.isRestricted(p.player, T0)).toBe(false)
		end)
	end)
end
