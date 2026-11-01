--!nocheck
-- Correctifs conga r1 et r2 de Comet Conga, parties MoveCheck (reprises) :
--   * r1 : vol bas (HipHeight relevé, CFrame décalé de 4 à 14 studs) : MoveCheck compte le vol bas
--     prolongé (> sol + RootHeight + ActionReachY pendant > HoverTime) comme infraction, un vrai
--     saut (JumpHeight 7,2) jamais ; le sol fourni compte (marche haute) ; exemption après apparition
--   * r2 : racine sous le sol (passe-muraille) : signalée au-delà de ActionReachY sous la hauteur
--     debout pendant plus de HoverTime, ramenée tout de suite au-delà de MaxBelowGround ; un appui
--     réel (sol fourni plus haut) n'est jamais un vol bas
-- Adaptation : Balance.Snip.MaxDy (portée verticale des coupes) → Tuning.ActionReachY (portée
-- verticale des actions) ; sol analytique de l'île (WorldLayout.groundY) → surface installée par
-- MoveCheck.setSurface. Retirés (gameplay de Comet Conga) : file au sol, coupes, Gloomwisps, sonde
-- de la stèle et de la tête d'un joueur dans CongaService.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 37
	local DT = 0.1
	local JUMP_HEIGHT = 7.2
	local GRAVITY = 196.2

	describe("MoveCheck (conga r1) › vol bas prolongé", function()
		local function mc()
			local h = Harness.new()
			local Tuning = h:require("ServerScriptService.Server.Movement.Tuning")
			return h:require("ServerScriptService.Server.Util.MoveCheck"), Tuning, Tuning, h.globals.Vector3
		end

		-- joueur apparu à `start`, exemption terminée, premier pas normal à T0
		local function newPlayer(MC, B, start)
			local player = { Name = "Hover" }
			MC.noteSpeed(player, 16, T0 - 10)
			MC.reset(player, start, T0 - MC.Config.Exemption)
			local p = { player = player, pos = start, now = T0 }
			assert(MC.step(player, start, DT, T0, 0) == "ok")
			return p
		end

		local function move(MC, p, delta, ground)
			p.now += DT
			p.pos = p.pos + delta
			return MC.step(p.player, p.pos, DT, p.now, ground or 0)
		end

		it("sauts enchaînés en marchant pendant 10 s (JumpHeight 7,2) : aucune infraction", function()
			local MC, B, _, V3 = mc()
			local p = newPlayer(MC, B, V3.new(-80, 3, 0))
			local v0 = math.sqrt(2 * GRAVITY * JUMP_HEIGHT)
			local airtime = 2 * v0 / GRAVITY
			local t = 0
			for _ = 1, 100 do
				t += DT
				-- sauts enchaînés : 0,05 s au sol entre deux sauts
				local phase = t % (airtime + 0.05)
				local y = 3 + math.max(0, v0 * phase - GRAVITY * phase * phase / 2)
				local target = V3.new(p.pos.X + 1.6, y, 0)
				expect(move(MC, p, target - p.pos)).toBe("ok")
			end
			expect(MC.violations(p.player)).toBe(0)
		end)

		it("juste sous le seuil (racine à sol + 6,9) pendant 5 s : jamais une infraction", function()
			local MC, B, Tuning, V3 = mc()
			local top = Tuning.RootHeight + Tuning.ActionReachY
			local p = newPlayer(MC, B, V3.new(60, 3, 0))
			expect(move(MC, p, V3.new(0, top - 0.1 - 3, 0))).toBe("ok")
			for _ = 1, 50 do
				expect(move(MC, p, V3.new(1.5, 0, 0))).toBe("ok")
			end
			expect(MC.violations(p.player)).toBe(0)
		end)

		it(
			"vol bas à sol + 8 : toléré 1 s, puis infraction comptée à chaque tick, retour à la 3e",
			function()
				local MC, B, Tuning, V3 = mc()
				expect(Tuning.HoverTime).toBe(1)
				local p = newPlayer(MC, B, V3.new(60, 3, 0))
				expect(move(MC, p, V3.new(0, 5, 0))).toBe("ok") -- racine à sol + 8
				for _ = 1, 9 do
					expect(move(MC, p, V3.new(1.4, 0, 0))).toBe("ok")
				end
				local lastOk = p.pos
				local verdicts = {}
				for _ = 1, 4 do
					local verdict, back = move(MC, p, V3.new(1.4, 0, 0))
					table.insert(verdicts, verdict)
					if verdict == "ok" then
						lastOk = p.pos
					elseif verdict == "rewind" then
						-- position non acceptée : retour vers la dernière position valide
						expect(back).toEqual(lastOk)
					end
				end
				-- au plus un tick de flottement sur la frontière des 1 s
				local firstFlag = table.find(verdicts, "flag")
				expect(firstFlag ~= nil and firstFlag <= 2).toBe(true)
				local rewindAt = table.find(verdicts, "rewind")
				expect(rewindAt).toBe(firstFlag + 2)
				expect(MC.violations(p.player)).toBe(3)
				expect(MC.recentRewinds(p.player, p.now)).toBe(1)
				expect(MC.isRestricted(p.player, p.now)).toBe(true)
				expect(MC.lastValid(p.player)).toEqual(lastOk)
			end
		)

		it("le sol compte : la même hauteur au-dessus d'une marche haute n'est pas un vol", function()
			local MC, B, _, V3 = mc()
			local p = newPlayer(MC, B, V3.new(60, 3, 0))
			move(MC, p, V3.new(0, 5, 0), 5)
			for _ = 1, 30 do
				expect(move(MC, p, V3.new(1.4, 0, 0), 5)).toBe("ok")
			end
			-- sol inconnu (NaN) : jamais d'infraction de hauteur
			for _ = 1, 30 do
				expect(move(MC, p, V3.new(1.4, 0, 0), 0 / 0)).toBe("ok")
			end
			expect(MC.violations(p.player)).toBe(0)
		end)

		it("exemption après une apparition : un vol bas n'y est jamais compté ni ramené", function()
			local MC, B, _, V3 = mc()
			local player = {}
			MC.noteSpeed(player, 16, T0)
			local pos = V3.new(30, 9, 30)
			MC.reset(player, pos, T0)
			local now = T0
			local verdicts = {}
			while now < T0 + MC.Config.Exemption - DT do
				now += DT
				verdicts[MC.step(player, pos, DT, now, 0)] = true
			end
			expect(verdicts.rewind).toBeNil()
			expect(MC.violations(player)).toBe(0)
			expect(MC.recentRewinds(player, now)).toBe(0)
			-- après l'exemption, le vol bas compte (hoverSince repart du reset)
			local last
			for _ = 1, 3 do
				now += DT
				last = MC.step(player, pos, DT, now, 0)
			end
			expect(last).toBe("rewind")
			-- clear oublie le vol en cours
			MC.clear(player)
			expect(MC.step(player, pos, DT, now + DT, 0)).toBe("ok")
		end)
	end)

	describe("MoveCheck (conga r2) › racine enfouie", function()
		local function mc()
			local h = Harness.new()
			local Tuning = h:require("ServerScriptService.Server.Movement.Tuning")
			return h:require("ServerScriptService.Server.Util.MoveCheck"), Tuning, Tuning, h.globals.Vector3
		end

		local function newPlayer(MC, B, start)
			local player = { Name = "Buried" }
			MC.noteSpeed(player, 16, T0 - 10)
			MC.reset(player, start, T0 - MC.Config.Exemption)
			local p = { player = player, pos = start, now = T0 }
			assert(MC.step(player, start, DT, T0, 0) == "ok")
			return p
		end

		local function move(MC, p, delta, ground)
			p.now += DT
			p.pos = p.pos + delta
			return MC.step(p.player, p.pos, DT, p.now, ground or 0)
		end

		it(
			"racine basse mais à portée (sol − 0,9 : personnage tombé, pente) pendant 5 s : aucune infraction",
			function()
				local MC, B, Tuning, V3 = mc()
				local p = newPlayer(MC, B, V3.new(60, 3, 0))
				local low = Tuning.RootHeight - Tuning.ActionReachY -- −1
				expect(move(MC, p, V3.new(0, low + 0.1 - 3, 0))).toBe("ok")
				for _ = 1, 50 do
					expect(move(MC, p, V3.new(1.4, 0, 0))).toBe("ok")
				end
				expect(MC.violations(p.player)).toBe(0)
			end
		)

		it(
			"racine à sol − 1,5 : tolérée 1 s, puis infraction à chaque tick, retour à la 3e",
			function()
				local MC, B, _, V3 = mc()
				local p = newPlayer(MC, B, V3.new(60, 3, 0))
				expect(move(MC, p, V3.new(0, -4.5, 0))).toBe("ok")
				for _ = 1, 9 do
					expect(move(MC, p, V3.new(1.4, 0, 0))).toBe("ok")
				end
				local verdicts = {}
				for _ = 1, 4 do
					table.insert(verdicts, (move(MC, p, V3.new(1.4, 0, 0))))
				end
				local firstFlag = table.find(verdicts, "flag")
				expect(firstFlag ~= nil and firstFlag <= 2).toBe(true)
				expect(table.find(verdicts, "rewind")).toBe(firstFlag + 2)
				expect(MC.recentRewinds(p.player, p.now)).toBe(1)
				expect(MC.isRestricted(p.player, p.now)).toBe(true)
			end
		)

		it("racine à plus de MaxBelowGround sous le sol : retour immédiat, compté", function()
			local MC, B, Tuning, V3 = mc()
			expect(Tuning.MaxBelowGround).toBe(2)
			local p = newPlayer(MC, B, V3.new(60, 3, 0))
			local start = p.pos
			local verdict, back = move(MC, p, V3.new(1, -5.1, 0))
			expect(verdict).toBe("rewind")
			expect(back).toEqual(start)
			expect(MC.recentRewinds(p.player, p.now)).toBe(1)
			-- surface analytique du jeu (MoveCheck.setSurface) : terrain plat à 0, plateau de 20 × 20
			-- studs dessus à 3,3 autour de l'origine (Comet Conga : étage 1 de la Balise)
			MC.setSurface(function(x, z)
				return if math.abs(x) < 10 and math.abs(z) < 10 then 3.3 else 0
			end)
			local q = newPlayer(MC, B, V3.new(6, 6.3, 0))
			expect((move(MC, q, V3.new(0, -5.5, 0), 3.3))).toBe("rewind")
			-- un sol FOURNI plus haut que le terrain (appui réel) ne rend jamais « enfouie » une racine
			-- debout sur le terrain : la surface est min(sol fourni, surface analytique)
			local s = newPlayer(MC, B, V3.new(-60, 3.1, 0))
			for _ = 1, 30 do
				expect((move(MC, s, V3.new(1, 0, 0), 6))).toBe("ok")
			end
			expect(MC.violations(s.player)).toBe(0)
			MC.setSurface(nil)
			-- juste au-dessus de la limite : pas de retour immédiat
			local r = newPlayer(MC, B, V3.new(0, 3, 60))
			expect((move(MC, r, V3.new(1, -4.9, 0)))).toBe("ok")
		end)

		it(
			"exemption : une racine enfouie y est refusée sans retour ni restriction ; sol inconnu : jamais",
			function()
				local MC, B, _, V3 = mc()
				local player = {}
				MC.noteSpeed(player, 16, T0)
				local start = V3.new(30, 3, 30)
				MC.reset(player, start, T0)
				local now = T0
				while now < T0 + MC.Config.Exemption - DT do
					now += DT
					local verdict, back = MC.step(player, V3.new(30.5, -3, 30), DT, now, 0)
					expect(verdict).toBe("flag")
					expect(back).toBeNil()
				end
				expect(MC.recentRewinds(player, now)).toBe(0)
				expect(MC.isRestricted(player, now)).toBe(false)
				expect(MC.lastValid(player)).toEqual(start)
				-- exemption terminée : hors du monde, retour compté vers la position posée par le serveur
				now += 2 * DT
				local verdict, back = MC.step(player, V3.new(30.5, -3, 30), DT, now, 0)
				expect(verdict).toBe("rewind")
				expect(back).toEqual(start)
				expect(MC.recentRewinds(player, now)).toBe(1)
				-- sol inconnu (NaN) : seule la borne absolue MinY s'applique
				local q = {}
				MC.noteSpeed(q, 16, T0)
				MC.reset(q, V3.new(30, 3, 30), T0 - 10)
				local now = T0
				for _ = 1, 30 do
					now += DT
					expect(MC.step(q, V3.new(30, -4, 30), DT, now, 0 / 0)).toBe("ok")
				end
			end
		)

		it("un plané à sol + 9 au-dessus d'un appui à sol + 6 est 'ok' pendant 60 s", function()
			local MC, B, _, V3 = mc()
			local p = newPlayer(MC, B, V3.new(0, 3, 15))
			-- saut sur l'appui (montée en deux ticks), puis 60 s debout dessus
			expect(move(MC, p, V3.new(0, 4.3, -1.5), 0)).toBe("ok")
			expect(move(MC, p, V3.new(0, 1.7, -1.5), 6)).toBe("ok")
			for _ = 1, 600 do
				expect(move(MC, p, V3.new(0, 0, 0), 6)).toBe("ok")
			end
			expect(MC.violations(p.player)).toBe(0)
			expect(MC.recentRewinds(p.player, p.now)).toBe(0)
		end)
	end)

	describe("MoveCheck › surface analytique (setSurface)", function()
		it("surface en erreur, non finie ou absente : seul le sol fourni compte, jamais d'erreur", function()
			local h = Harness.new()
			local MC = h:require("ServerScriptService.Server.Util.MoveCheck")
			local V3 = h.globals.Vector3
			local function run(fn)
				MC.setSurface(fn)
				local player = { Name = "Surface" }
				MC.noteSpeed(player, 16, T0 - 10)
				MC.reset(player, V3.new(0, 3, 0), T0 - MC.Config.Exemption)
				local now = T0
				local verdicts = {}
				for i = 1, 20 do
					now += DT
					verdicts[i] = MC.step(player, V3.new(1.2 * i, 3, 0), DT, now, 0)
				end
				return verdicts, MC.violations(player)
			end
			for _, fn in
				{
					function()
						error("surface en panne")
					end,
					function()
						return 0 / 0
					end,
					function()
						return math.huge
					end,
					function()
						return "haut"
					end,
					nil,
				}
			do
				local verdicts, violations = run(fn)
				for _, v in verdicts do
					expect(v).toBe("ok")
				end
				expect(violations).toBe(0)
			end
			-- sans surface installée, le sol fourni EST la surface : racine 5,1 sous un appui fourni à 6
			MC.setSurface(nil)
			local player = { Name = "Fourni" }
			MC.noteSpeed(player, 16, T0 - 10)
			MC.reset(player, V3.new(0, 9, 0), T0 - MC.Config.Exemption)
			expect(MC.step(player, V3.new(0, 9, 0), DT, T0, 6)).toBe("ok")
			expect((MC.step(player, V3.new(0.5, 0.9, 0), DT, T0 + DT, 6))).toBe("rewind")
		end)
	end)
end
