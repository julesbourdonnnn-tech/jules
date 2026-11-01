--!nocheck
-- Correctif r3 « serveur 4 » de Comet Conga, partie MoveCheck (reprise telle quelle) : 1 s
-- d'immobilité, bond, puis 42 studs en UN tick étaient acceptés et AGISSAIENT ; la position reste
-- acceptée (gels réseau tolérés), mais le tick est signalé « rafale » (règle d'un tick :
-- vmax × dt × 1,5 + 4). Contrat de la finition (plus strict) : la rafale vient d'un budget d'action
-- à mémoire ; le tick qui suit le bond reste une rafale jusqu'au remboursement de la dette
-- (MoveCheck_budget.spec). Retirés (gameplay de Comet Conga) : Zen, quêtes, Atlas.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local DT = 0.1
	local T0 = 1000

	local function moveCheck()
		local h = Harness.new()
		local MoveCheck = h:require("ServerScriptService.Server.Util.MoveCheck")
		return MoveCheck, h.globals.Vector3
	end

	-- Joueur simulé (clé seulement) : apparu, exemption terminée à T0, un premier pas normal à T0
	local function newPlayer(MC, V3, pos, speed)
		local player = { Name = "Blinker" }
		MC.noteSpeed(player, speed or 16, T0 - 10)
		MC.reset(player, pos, T0 - MC.Config.Exemption)
		local p = { player = player, pos = pos + V3.new(0, 0, 0.5), now = T0 }
		assert(MC.step(player, p.pos, DT, T0, 0) == "ok")
		return p
	end

	local function move(MC, p, delta)
		p.now += DT
		p.pos = p.pos + delta
		return MC.step(p.player, p.pos, DT, p.now, 0)
	end

	describe("Fix r3 serveur 4 › MoveCheck : bond après immobilité", function()
		it("immobile 1,2 s, bond (+10), 42 studs en un tick : accepté, 0 infraction, mais rafale", function()
			local MC, V3 = moveCheck()
			local p = newPlayer(MC, V3, V3.new(100, 3, 0), 16)
			for _ = 1, 12 do
				local verdict, _, burst = move(MC, p, V3.new(0, 0, 0))
				expect(verdict).toBe("ok")
				expect(burst).toBe(false)
			end
			MC.noteSpeed(p.player, 26, p.now) -- bond (+10)
			local verdict, back, burst = move(MC, p, V3.new(42, 0, 0))
			-- tolérance inchangée : la position est acceptée, aucune infraction, aucun retour
			expect(verdict).toBe("ok")
			expect(back).toBe(nil)
			expect(MC.violations(p.player)).toBe(0)
			expect((MC.lastValid(p.player) - p.pos).Magnitude < 1e-6).toBe(true)
			-- … mais ce tick ne doit agir sur rien
			expect(burst).toBe(true)
			expect(MC.lastWasBurst(p.player)).toBe(true)
			expect(MC.canAct(p.player, p.now)).toBe(false)
			-- contrat r5 (plus strict) : le tick SUIVANT reste une rafale — le bond a laissé une
			-- dette de budget d'action, il ne se « ré-utilise » pas un tick plus tard
			local v2, _, b2 = move(MC, p, V3.new(0, 0, 0))
			expect(v2).toBe("ok")
			expect(b2).toBe(true)
			expect(MC.lastWasBurst(p.player)).toBe(true)
			expect(MC.canAct(p.player, p.now)).toBe(false)
			-- à l'arrêt, la dette se rembourse à vmax × 1,5 studs/s : de nouveau « agissant » en
			-- moins d'une seconde (34 studs de dette, 3,9 studs par tick à 26)
			local stillTicks = 1
			while MC.lastWasBurst(p.player) and stillTicks < 30 do
				local v, _, _ = move(MC, p, V3.new(0, 0, 0))
				expect(v).toBe("ok")
				stillTicks += 1
			end
			expect(MC.lastWasBurst(p.player)).toBe(false)
			expect(MC.canAct(p.player, p.now)).toBe(true)
			expect(stillTicks >= 5).toBe(true)
			expect(stillTicks <= 10).toBe(true)
			expect(MC.violations(p.player)).toBe(0)
		end)

		it(
			"la règle d'un tick : 7,9 studs à 26 passent, 8,5 sont une rafale ; à 16, 6,4 passent",
			function()
				local MC, V3 = moveCheck()
				local p = newPlayer(MC, V3, V3.new(100, 3, 0), 26)
				for _ = 1, 12 do
					move(MC, p, V3.new(0, 0, 0))
				end
				local _, _, ok79 = move(MC, p, V3.new(7.8, 0, 0))
				expect(ok79).toBe(false)
				for _ = 1, 12 do
					move(MC, p, V3.new(0, 0, 0))
				end
				local verdict, _, b85 = move(MC, p, V3.new(8.5, 0, 0))
				expect(verdict).toBe("ok")
				expect(b85).toBe(true)
				local q = newPlayer(MC, V3, V3.new(-100, 3, 0), 16)
				for _ = 1, 12 do
					move(MC, q, V3.new(0, 0, 0))
				end
				local _, _, b64 = move(MC, q, V3.new(6.3, 0, 0))
				expect(b64).toBe(false)
				expect(MC.violations(p.player) + MC.violations(q.player)).toBe(0)
			end
		)

		it("marche honnête (16, 26, bond, paquets groupés par deux) : jamais de rafale", function()
			local MC, V3 = moveCheck()
			for _, speed in { 16, 26 } do
				local radius = 120
				local p = newPlayer(MC, V3, V3.new(radius, 3, -0.5), speed)
				local angle = 0
				for i = 1, 300 do
					-- un tick sur deux sans nouvelle position, puis deux pas d'un coup (gigue réseau)
					local ticks = if i % 2 == 0 then 2 else 0
					if i % 50 == 0 then
						MC.noteSpeed(p.player, speed + 10, p.now) -- bond
					end
					angle += ticks * DT * speed / radius
					local target = V3.new(radius * math.cos(angle), 3, radius * math.sin(angle))
					local verdict, _, burst = move(MC, p, target - p.pos)
					expect(verdict).toBe("ok")
					expect(burst).toBe(false)
				end
				expect(MC.violations(p.player)).toBe(0)
			end
		end)

		it(
			"rattrapage du serveur (3 pas au même instant après un accroc de 0,3 s) : pas de rafale",
			function()
				local MC, V3 = moveCheck()
				local p = newPlayer(MC, V3, V3.new(100, 3, 0), 26)
				for _ = 1, 5 do
					move(MC, p, V3.new(2.6, 0, 0))
				end
				-- image de 0,3 s : le joueur a parcouru 7,8 studs ; le serveur joue 3 pas au même instant
				p.now += 0.3
				p.pos = p.pos + V3.new(7.8, 0, 0)
				for _ = 1, 3 do
					local verdict, _, burst = MC.step(p.player, p.pos, DT, p.now, 0)
					expect(verdict).toBe("ok")
					expect(burst).toBe(false)
				end
				-- un trou plus long sans appel (personnage absent, sans réinitialisation) n'est jamais un
				-- crédit de bond : borné à MaxCatchUp pas (20 studs : dans la fenêtre soutenue)
				p.now += 1.2
				p.pos = p.pos + V3.new(20, 0, 0)
				local verdict, _, burst = MC.step(p.player, p.pos, DT, p.now, 0)
				expect(verdict).toBe("ok")
				expect(burst).toBe(true)
				expect(MC.violations(p.player)).toBe(0)
			end
		)

		it("signalé, réinitialisé ou inconnu : jamais « rafale » ; clear oublie tout", function()
			local MC, V3 = moveCheck()
			local p = newPlayer(MC, V3, V3.new(100, 3, 0), 16)
			for _ = 1, 12 do
				move(MC, p, V3.new(0, 0, 0))
			end
			MC.noteSpeed(p.player, 26, p.now)
			local _, _, burst = move(MC, p, V3.new(42, 0, 0))
			expect(burst).toBe(true)
			-- téléportation (dans le monde) : signalée, pas une rafale
			local verdict, _, b2 = move(MC, p, V3.new(0, 0, 50))
			expect(verdict).toBe("flag")
			expect(b2).toBe(false)
			expect(MC.lastWasBurst(p.player)).toBe(false)
			-- position invalide
			local v3, _, b3 = MC.step(p.player, V3.new(0 / 0, 3, 0), DT, p.now + DT, 0)
			expect(v3).toBe("flag")
			expect(b3).toBe(false)
			-- nouvelle référence (apparition)
			move(MC, p, V3.new(0, 0, -50))
			MC.reset(p.player, p.pos, p.now)
			expect(MC.lastWasBurst(p.player)).toBe(false)
			expect(MC.lastWasBurst({ Name = "Nobody" })).toBe(false)
			MC.clear(p.player)
			expect(MC.lastWasBurst(p.player)).toBe(false)
		end)
	end)
end
