--!nocheck
-- MoveCheck : budget d'action (passe de finition de Comet Conga, Fix_r5_serveur_anticheat), repris
-- au niveau de MoveCheck lui-même. Dans Comet Conga, ces scènes passaient par CongaService (coupes,
-- captures, Comète) ; ici, la garantie générique est vérifiée directement : un tick en rafale ou en
-- dette (lastWasBurst, canAct faux) ne doit agir sur rien, et le service du tick de jeu s'y fiera.
--   1. Exploits reproduits par le contre-audit : bond seul (27 / 42 / 57 studs), bond puis action
--      (V1), chaînes de pas trop longs (V2, V3), action au tick qui suit un bond : BLOQUÉS (rafales),
--      0 infraction, jamais de retour (la tolérance des gels réseau est inchangée).
--   2. Joueurs honnêtes (Hn1, Hn2, Hn4) : paquets groupés par deux ou trois, bond, sauts sur une
--      pente, réapparition : jamais de rafale.
--   3. Gel réseau honnête de 0,7 / 1,0 / 1,5 s en courant : ni infraction, ni retour, ni
--      restriction ; coût borné (ticks sans action) ; la téléportation reste détectée.
-- Vitesses neutres : 16 (marche), 26 (marche + bond de +10), 36 (plus rapide encore).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local DT = 0.1
	local T0 = 1800000000 + 41

	local function setup()
		local h = Harness.new()
		local MC = h:require("ServerScriptService.Server.Util.MoveCheck")
		return MC, h.globals.Vector3
	end

	-- Joueur simulé (clé de table) : apparu, exemption terminée, premier pas normal à T0
	local function newPlayer(MC, V3, start, speed)
		local player = { Name = "Budget" }
		MC.noteSpeed(player, speed or 16, T0 - 10)
		MC.reset(player, start, T0 - MC.Config.Exemption)
		local p = { player = player, pos = start, now = T0, ground = 0 }
		assert(MC.step(player, start, DT, T0, 0) == "ok")
		return p
	end

	-- Un tick serveur : position vue `pos` (nil : inchangée) ; rend verdict, retour, rafale
	local function tick(MC, p, pos)
		p.now += DT
		if pos then
			p.pos = pos
		end
		return MC.step(p.player, p.pos, DT, p.now, p.ground)
	end

	local function still(MC, p, n)
		for _ = 1, n do
			tick(MC, p)
		end
	end

	-- Chaîne de pas de `len` studs vers `target` ; rend (rafales, ticks agissants pendant la chaîne)
	local function chain(MC, V3, p, target, len, maxTicks)
		local bursts, acting = 0, 0
		for _ = 1, maxTicks do
			local d = V3.new(target.X - p.pos.X, 0, target.Z - p.pos.Z)
			if d.Magnitude < 1e-6 then
				break
			end
			local stepLen = math.min(len, d.Magnitude)
			local verdict, _, burst = tick(MC, p, p.pos + d.Unit * stepLen)
			if burst then
				bursts += 1
			elseif verdict == "ok" then
				acting += 1
			end
		end
		return bursts, acting
	end

	-- =========================================================================================
	describe("MoveCheck › budget d'action : exploits bloqués", function()
		it("bond seul (27 studs à 16 ; 42 à 26 ; 57 à 36) : rafale, et encore au tick suivant", function()
			for _, case in
				{
					{ from = 46, to = 73, speed = 16 },
					{ from = 39, to = 81, speed = 26 },
					{ from = 30, to = 87, speed = 36 },
				}
			do
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(66, 3, case.from), 16)
				still(MC, p, 12)
				MC.noteSpeed(p.player, case.speed, p.now)
				local v0 = MC.violations(p.player)
				local verdict, back, burst = tick(MC, p, V3.new(66, 3, case.to))
				expect({ case = case.to, verdict = verdict, back = back, burst = burst }).toEqual({
					case = case.to,
					verdict = "ok",
					back = nil,
					burst = true,
				})
				-- le tick suivant, un petit pas sur place : toujours en dette
				local _, _, burst2 = tick(MC, p, V3.new(66, 3, case.to - 1))
				expect(burst2).toBe(true)
				expect(MC.lastWasBurst(p.player)).toBe(true)
				expect(MC.canAct(p.player, p.now)).toBe(false)
				expect(MC.violations(p.player)).toBe(v0)
			end
		end)

		it("V1 bond puis action : 19 studs, puis 6 studs au tick suivant : jamais agissant", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(66, 3, 37), 16)
			still(MC, p, 12)
			local _, _, b1 = tick(MC, p, V3.new(66, 3, 56))
			expect(b1).toBe(true)
			local verdict, _, b2 = tick(MC, p, V3.new(66, 3, 62))
			expect(verdict).toBe("ok")
			expect(b2).toBe(true)
			expect(MC.canAct(p.player, p.now)).toBe(false)
			expect(MC.violations(p.player)).toBe(0)
		end)

		it(
			"V2 chaîne : pas de 6,25 studs (62 studs/s) après 1,2 s d'arrêt : rafales, 0 infraction",
			function()
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(66, 3, 37), 16)
				still(MC, p, 12)
				local bursts, acting = chain(MC, V3, p, V3.new(66, 3, 62), 6.25, 10)
				-- seul le premier pas tient dans la règle d'un tick
				expect(bursts >= 3).toBe(true)
				expect(acting <= 1).toBe(true)
				expect(MC.violations(p.player)).toBe(0)
			end
		)

		it("V3 chaîne à 36 studs/s : pas de 9,2 studs sur ≈ 55 studs : rafales, 0 infraction", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(66, 3, 7), 16)
			still(MC, p, 12)
			MC.noteSpeed(p.player, 36, p.now)
			local bursts, acting = chain(MC, V3, p, V3.new(66, 3, 62), 9.2, 10)
			expect(bursts >= 3).toBe(true)
			expect(acting <= 1).toBe(true)
			expect(MC.violations(p.player)).toBe(0)
		end)

		it(
			"action au tick qui suit un bond, puis immobile : agissant après 4 à 15 ticks, jamais avant",
			function()
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(-60, 3, 40), 16)
				still(MC, p, 40)
				still(MC, p, 12)
				local target = V3.new(-60, 3, 67)
				-- 21 studs : arrivé à 6 studs de la cible
				local _, _, b1 = tick(MC, p, target - V3.new(0, 0, 6))
				expect(b1).toBe(true)
				-- 6 studs de plus (règle d'un tick) : sur la cible, toujours en dette
				local _, _, b2 = tick(MC, p, target)
				expect(b2).toBe(true)
				expect(MC.violations(p.player)).toBe(0)
				local waited = 0
				while MC.lastWasBurst(p.player) and waited < 30 do
					tick(MC, p)
					waited += 1
				end
				expect(MC.canAct(p.player, p.now)).toBe(true)
				expect(waited >= 4 and waited <= 15).toBe(true)
			end
		)

		it(
			"canAct : faux en dette ou restreint, vrai après remboursement ; joueur inconnu : vrai",
			function()
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(-60, 3, 40), 16)
				still(MC, p, 40)
				expect(MC.canAct(p.player, p.now)).toBe(true)
				still(MC, p, 12)
				tick(MC, p, V3.new(-60, 3, 67))
				expect(MC.canAct(p.player, p.now)).toBe(false)
				still(MC, p, 12)
				expect(MC.canAct(p.player, p.now)).toBe(true)
				-- restreint après un retour (téléportations répétées)
				for _ = 1, 3 do
					tick(MC, p, V3.new(60, 3, -60))
				end
				expect(MC.isRestricted(p.player, p.now)).toBe(true)
				expect(MC.canAct(p.player, p.now)).toBe(false)
				expect(MC.canAct({ Name = "Nobody" }, p.now)).toBe(true)
			end
		)
	end)

	-- =========================================================================================
	describe("MoveCheck › budget d'action : joueurs honnêtes", function()
		-- `ticks` ticks ; `move(i)` rend la nouvelle position vue (nil : inchangée). Rend rafales +
		-- infractions + verdicts non « ok »
		local function honestRun(MC, p, ticks, move)
			local v0 = MC.violations(p.player)
			local bursts, invalid = 0, 0
			for i = 1, ticks do
				local verdict, _, burst = tick(MC, p, move(i))
				if burst then
					bursts += 1
				end
				if verdict ~= "ok" then
					invalid += 1
				end
			end
			return bursts + invalid + (MC.violations(p.player) - v0)
		end

		it("Hn1 paquets groupés par deux : 16 (0 ; 3,2), 26 (0 ; 5,2), 36 (0 ; 7,2)", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(-100, 3, -20), 16)
			still(MC, p, 40)
			expect(honestRun(MC, p, 40, function(i)
				return if i % 2 == 0 then p.pos + V3.new(3.2, 0, 0) else nil
			end)).toBe(0)
			still(MC, p, 15)
			MC.noteSpeed(p.player, 26, p.now)
			expect(honestRun(MC, p, 10, function(i)
				return if i % 2 == 0 then p.pos + V3.new(5.2, 0, 0) else nil
			end)).toBe(0)
			still(MC, p, 80)
			MC.noteSpeed(p.player, 36, p.now)
			expect(honestRun(MC, p, 10, function(i)
				return if i % 2 == 0 then p.pos + V3.new(-7.2, 0, 0) else nil
			end)).toBe(0)
		end)

		it("Hn2 paquets groupés par trois (0 ; 0 ; 4,8 à 16 : gigue de 0,3 s)", function()
			local MC, V3 = setup()
			local p = newPlayer(MC, V3, V3.new(-100, 3, -20), 16)
			still(MC, p, 40)
			expect(honestRun(MC, p, 30, function(i)
				return if i % 3 == 0 then p.pos + V3.new(4.8, 0, 0) else nil
			end)).toBe(0)
		end)

		it("Hn4 sauts (JumpPower 50) en marchant à 16 en montant une pente", function()
			local MC, V3 = setup()
			-- pente : le sol monte de 0,08 stud par stud vers +X
			local function groundY(x)
				return math.max(0, 0.08 * (x + 150))
			end
			local x, z = -150, 0
			local p = newPlayer(MC, V3, V3.new(x, groundY(x) + 3, z), 16)
			still(MC, p, 40)
			local tAir = 0
			expect(honestRun(MC, p, 60, function()
				x += 1.6
				tAir += 0.1
				local h = 50 * tAir - 0.5 * 196.2 * tAir * tAir
				if h < 0 then
					h = 0
					tAir = 0
				end
				p.ground = groundY(x)
				return V3.new(x, groundY(x) + 3 + h, z)
			end)).toBe(0)
		end)

		it("réapparition : de nouveau à pied, aucune dette héritée", function()
			local MC, V3 = setup()
			local home = V3.new(-60, 3, 40)
			local p = newPlayer(MC, V3, home, 16)
			still(MC, p, 52)
			-- rattrapage (gel réseau) juste avant de mourir : budget en dette
			local _, _, burst = tick(MC, p, home + V3.new(0, 0, 25))
			expect(burst).toBe(true)
			-- nouveau personnage posé par le serveur (PivotTo + reset)
			MC.reset(p.player, home, p.now)
			p.pos = home
			expect(MC.lastWasBurst(p.player)).toBe(false)
			expect(honestRun(MC, p, 6, function()
				return p.pos + V3.new(0, 0, 1.4)
			end)).toBe(0)
		end)
	end)

	-- =========================================================================================
	describe("MoveCheck › gel réseau honnête en courant", function()
		-- marche à 16 studs/s, gel de `freeze` ticks (position figée), rattrapage d'un coup, puis
		-- 40 ticks à 16 (ou à l'arrêt) ; rend les mesures
		local function freezeRun(freeze, walkOn)
			local MC, V3 = setup()
			local x, z = -160, 30
			local p = newPlayer(MC, V3, V3.new(x, 3, z), 16)
			still(MC, p, 40)
			for _ = 1, 10 do
				x += 1.6
				tick(MC, p, V3.new(x, 3, z))
			end
			local v0 = MC.violations(p.player)
			still(MC, p, freeze)
			x += 1.6 * (freeze + 1)
			local pulledBack = false
			local noAction = 0
			local pos = V3.new(x, 3, z)
			for i = 0, 40 do
				if i > 0 and walkOn then
					x += 1.6
				end
				pos = V3.new(x, 3, z)
				local verdict, _, burst = tick(MC, p, pos)
				if verdict == "rewind" then
					pulledBack = true
				end
				if verdict ~= "ok" or burst then
					noAction += 1
				end
			end
			return {
				violations = MC.violations(p.player) - v0,
				rewinds = MC.recentRewinds(p.player, p.now),
				restricted = MC.isRestricted(p.player, p.now),
				pulledBack = pulledBack,
				noAction = noAction,
			}
		end

		it(
			"gels de 0,7 / 1,0 / 1,5 s : 0 infraction, aucun retour, aucune restriction, coût borné",
			function()
				-- dette ≈ 16 × (gel + 0,1) − 6,4 studs, remboursée à 0,8 stud par tick en courant à 16
				for _, case in
					{
						{ freeze = 7, maxNoAction = 10 },
						{ freeze = 10, maxNoAction = 16 },
						{ freeze = 15, maxNoAction = 26 },
					}
				do
					local r = freezeRun(case.freeze, true)
					expect({ freeze = case.freeze, violations = r.violations }).toEqual({
						freeze = case.freeze,
						violations = 0,
					})
					expect(r.rewinds).toBe(0)
					expect(r.restricted).toBe(false)
					expect(r.pulledBack).toBe(false)
					expect(r.noAction <= case.maxNoAction).toBe(true)
				end
			end
		)

		it("arrêté après le rattrapage : de nouveau « agissant » en moins d'une seconde", function()
			for _, freeze in { 7, 10, 15 } do
				local r = freezeRun(freeze, false)
				expect(r.violations).toBe(0)
				expect(r.rewinds).toBe(0)
				expect(r.noAction <= 10).toBe(true)
			end
		end)

		it(
			"la téléportation reste détectée : 2 s d'arrêt puis 40 studs ; 28 studs puis 2 × vmax → retour",
			function()
				local MC, V3 = setup()
				local p = newPlayer(MC, V3, V3.new(-100, 3, -20), 16)
				still(MC, p, 60)
				local v0 = MC.violations(p.player)
				local verdict = tick(MC, p, p.pos + V3.new(40, 0, 0))
				expect(verdict).toBe("flag")
				expect(MC.violations(p.player)).toBe(v0 + 1)
				-- départ d'un arrêt avec tout le crédit (28 studs, accepté mais en rafale), puis course à
				-- 32 studs/s : la fenêtre allongée depuis le départ reste bornée à 1,5 × vmax
				local MC2, V3b = setup()
				local q = newPlayer(MC2, V3b, V3b.new(-100, 3, -20), 16)
				still(MC2, q, 60)
				local v, _, burst = tick(MC2, q, q.pos + V3b.new(28, 0, 0))
				expect(v).toBe("ok")
				expect(burst).toBe(true)
				expect(MC2.violations(q.player)).toBe(0)
				for _ = 1, 3 do
					tick(MC2, q, q.pos + V3b.new(3.2, 0, 0))
				end
				expect(MC2.violations(q.player)).toBe(3)
				expect(MC2.recentRewinds(q.player, q.now)).toBe(1)
			end
		)
	end)
end
