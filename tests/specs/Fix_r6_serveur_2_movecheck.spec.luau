--!nocheck
-- Correctifs r6 « serveur 2 » de Comet Conga — MoveCheck (Util/MoveCheck.luau), repris tels quels :
--   1. Montée verticale et paquets groupés : la montée autorisée se mesurait depuis la dernière
--      position ACCEPTÉE (acceptedAt, remis à chaque tick même sans nouveau paquet) et ne gagnait
--      donc jamais de crédit pendant une gigue ou un gel (5,8 studs par tick). Un vrai saut
--      (JumpHeight 7,2, v0 ≈ 53,15 studs/s) dont les 0,2 premières secondes arrivent d'un coup monte
--      de 6,71 studs (7,12 sur 0,3 s) : infraction, puis retour compté (« instable », strike vers
--      l'exclusion des classements) au 3e saut. La montée prend maintenant le même crédit d'arrêt
--      que la mesure XZ (validAt, au plus STILL_CREDIT).
--   2. Gel réseau en haut d'un saut : le serveur garde la racine figée en l'air ; le chronomètre de
--      vol bas (HoverTime 1 s) continuait de tourner → infractions puis retour. Les ticks figés
--      (aucun nouveau paquet) décalent maintenant ce chronomètre, au plus STILL_CREDIT (1,5 s) par
--      épisode : un gel de 0,7 à 1,5 s n'est jamais compté, mais planer immobile ou en bougeant
--      reste une infraction.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local DT = 0.1
	local T0 = 1800000000 + 61
	local GRAVITY = 196.2
	local JUMP_HEIGHT = 7.2
	local V0 = math.sqrt(2 * GRAVITY * JUMP_HEIGHT) -- ≈ 53,15 studs/s
	local AIRTIME = 2 * V0 / GRAVITY -- ≈ 0,54 s

	local function setup()
		local h = Harness.new()
		local MC = h:require("ServerScriptService.Server.Util.MoveCheck")
		return MC, h.globals.Vector3
	end

	-- hauteur d'un vrai saut `t` secondes après l'impulsion (0 au sol)
	local function rise(t)
		if t < 0 or t > AIRTIME then
			return 0
		end
		return math.max(0, V0 * t - GRAVITY * t * t / 2)
	end

	-- Joueur simulé (clé de table) : apparu, exemption terminée, premier pas normal à T0
	local function newPlayer(MC, V3, start)
		local player = { Name = "R6" }
		MC.noteSpeed(player, 16, T0 - 10)
		MC.reset(player, start, T0 - MC.Config.Exemption)
		assert(MC.step(player, start, DT, T0, 0) == "ok")
		return player
	end

	-- Joue `ticks` ticks serveur ; `seen(i)` = position reçue au tick i (figée s'il n'y a pas de
	-- nouveau paquet). Rend les verdicts et le nombre de rafales.
	local function run(MC, player, ticks, seen)
		local verdicts, bursts = {}, 0
		for i = 1, ticks do
			local verdict, _, burst = MC.step(player, seen(i), DT, T0 + i * DT, 0)
			verdicts[i] = verdict
			if burst then
				bursts += 1
			end
		end
		return verdicts, bursts
	end

	local function countOf(list, value)
		local n = 0
		for _, v in list do
			if v == value then
				n += 1
			end
		end
		return n
	end

	describe("Fix r6 serveur 2 › MoveCheck : sauts honnêtes et paquets groupés", function()
		it(
			"3 sauts à 16 studs/s, paquets groupés par deux (montée de 6,71 en un tick) : 0 infraction, 0 retour",
			function()
				local MC, V3 = setup()
				expect(rise(0.2)).toBeNear(6.71, 0.01)
				local start = V3.new(-100, 3, 0)
				local player = newPlayer(MC, V3, start)
				-- trajectoire réelle : marche à 16 en +X, saut à 0,6 s, 3,0 s et 5,4 s (≈ 2,4 s d'écart)
				local jumps = { 0.6, 3.0, 5.4 }
				local function truePos(t)
					local y = 3
					for _, tj in jumps do
						y += rise(t - tj)
					end
					return V3.new(start.X + 16 * t, y, 0)
				end
				-- un paquet sur deux ticks : le tick pair reçoit les 0,2 s écoulées d'un coup
				local verdicts, bursts = run(MC, player, 80, function(i)
					return truePos(math.floor(i / 2) * 2 * DT)
				end)
				expect(countOf(verdicts, "flag")).toBe(0)
				expect(countOf(verdicts, "rewind")).toBe(0)
				expect(bursts).toBe(0)
				expect(MC.violations(player)).toBe(0)
				expect(MC.recentRewinds(player, T0 + 8)).toBe(0)
				expect(MC.isRestricted(player, T0 + 8)).toBe(false)
			end
		)

		it(
			"3 sauts à 16 studs/s, paquets groupés par trois (montée de 7,12 en un tick) : 0 infraction",
			function()
				local MC, V3 = setup()
				expect(rise(0.3)).toBeNear(7.12, 0.01)
				local start = V3.new(-100, 3, 10)
				local player = newPlayer(MC, V3, start)
				local jumps = { 0.6, 3.0, 5.4 }
				local function truePos(t)
					local y = 3
					for _, tj in jumps do
						y += rise(t - tj)
					end
					return V3.new(start.X + 16 * t, y, 10)
				end
				local verdicts = run(MC, player, 90, function(i)
					return truePos(math.floor(i / 3) * 3 * DT)
				end)
				expect(countOf(verdicts, "flag")).toBe(0)
				expect(countOf(verdicts, "rewind")).toBe(0)
				expect(MC.violations(player)).toBe(0)
				expect(MC.recentRewinds(player, T0 + 9)).toBe(0)
			end
		)

		it("gel réseau de 0,6 s au sol qui se termine au milieu d'un saut : 0 infraction", function()
			local MC, V3 = setup()
			local start = V3.new(-100, 3, -10)
			local player = newPlayer(MC, V3, start)
			-- marche à 16, gel de 0,6 s à partir de 1,0 s, saut à 1,4 s : le premier paquet après le
			-- gel (1,6 s) arrive 0,2 s après l'impulsion
			local function truePos(t)
				return V3.new(start.X + 16 * t, 3 + rise(t - 1.4), -10)
			end
			local verdicts = run(MC, player, 30, function(i)
				local t = i * DT
				if t > 1.0 + 1e-6 and t < 1.6 - 1e-6 then
					t = 1.0
				end
				return truePos(t)
			end)
			expect(countOf(verdicts, "flag")).toBe(0)
			expect(countOf(verdicts, "rewind")).toBe(0)
			expect(MC.violations(player)).toBe(0)
		end)

		it("contrôle : une montée soutenue de 6 studs par tick en marchant reste signalée", function()
			local MC, V3 = setup()
			local start = V3.new(-60, 3, 0)
			local player = newPlayer(MC, V3, start)
			-- 1 s de marche (aucun crédit d'arrêt), puis 6 studs de montée par tick
			local verdicts = run(MC, player, 13, function(i)
				return V3.new(start.X + 1.6 * i, 3 + 6 * math.max(0, i - 10), 0)
			end)
			for i = 1, 10 do
				expect(verdicts[i]).toBe("ok")
			end
			expect(verdicts[11]).toBe("flag")
			expect(MC.violations(player)).toBeGreaterThan(0)
		end)

		it(
			"contrôle : immobile puis bond vertical de 20 studs : ramené par la règle d'altitude",
			function()
				local MC, V3 = setup()
				local start = V3.new(-60, 3, 20)
				local player = newPlayer(MC, V3, start)
				local up = start + V3.new(0, 20, 0)
				local rewindAt, back = nil, nil
				for i = 1, 40 do
					local verdict, to = MC.step(player, if i <= 15 then start else up, DT, T0 + i * DT, 0)
					if verdict == "rewind" then
						rewindAt, back = i, to
						break
					end
				end
				-- crédit d'altitude : 1,5 s au plus au-dessus de sol + 14 (+ un tick de frontière)
				expect(rewindAt ~= nil and rewindAt <= 15 + 17).toBe(true)
				expect(back ~= nil).toBe(true)
				expect(MC.isRestricted(player, T0 + rewindAt * DT)).toBe(true)
			end
		)
	end)

	describe("Fix r6 serveur 2 › MoveCheck : gel réseau en haut d'un saut", function()
		for _, freeze in { 1.2, 1.5 } do
			it(
				`gel de {freeze} s 0,3 s après l'impulsion : ni infraction, ni retour, ni restriction`,
				function()
					local MC, V3 = setup()
					local start = V3.new(-100, 3, 30)
					local player = newPlayer(MC, V3, start)
					-- marche à 16, saut à 1,0 s ; le serveur garde la racine de 1,3 s (≈ sol + 10,1)
					-- pendant `freeze` s, puis reçoit la position réelle (atterri, plus loin)
					local tj, frozenAt = 1.0, 1.3
					local function truePos(t)
						return V3.new(start.X + 16 * t, 3 + rise(t - tj), 30)
					end
					expect(truePos(frozenAt).Y).toBeGreaterThan(3 + 7)
					local verdicts = run(MC, player, 50, function(i)
						local t = i * DT
						if t > frozenAt + 1e-6 and t < frozenAt + freeze + DT / 2 - 1e-6 then
							t = frozenAt
						end
						return truePos(t)
					end)
					expect(countOf(verdicts, "flag")).toBe(0)
					expect(countOf(verdicts, "rewind")).toBe(0)
					expect(MC.violations(player)).toBe(0)
					expect(MC.recentRewinds(player, T0 + 5)).toBe(0)
					expect(MC.isRestricted(player, T0 + 5)).toBe(false)
				end
			)
		end

		it("contrôle : planer à sol + 8 en bougeant reste une infraction au-delà de 1 s", function()
			local MC, V3 = setup()
			local start = V3.new(60, 3, 0)
			local player = newPlayer(MC, V3, start)
			-- monte à sol + 8, plane en bougeant 0,5 s, se fige 1 s (gel ou triche), repart 0,7 s
			local function seen(i)
				local x
				if i <= 5 then
					x = 60 + 1.4 * i
				elseif i <= 15 then
					x = 60 + 1.4 * 5
				else
					x = 60 + 1.4 * (i - 10)
				end
				return V3.new(x, 8, 0)
			end
			local verdicts = run(MC, player, 30, seen)
			for i = 1, 15 do
				expect(verdicts[i]).toBe("ok")
			end
			-- temps de vol en bougeant cumulé > 1 s (tick 21 ou 22 : frontière des 1 s) : infractions,
			-- retour à la 3e
			local firstFlag = table.find(verdicts, "flag")
			expect(firstFlag ~= nil and firstFlag >= 21 and firstFlag <= 22).toBe(true)
			expect(table.find(verdicts, "rewind")).toBe(firstFlag + 2)
			expect(MC.recentRewinds(player, T0 + 3)).toBe(1)
		end)

		it(
			"contrôle : planer immobile à sol + 8 finit signalé puis ramené (crédit de gel borné)",
			function()
				local MC, V3 = setup()
				local start = V3.new(60, 3, 40)
				local player = newPlayer(MC, V3, start)
				local up = V3.new(60, 8, 40)
				local verdicts = run(MC, player, 40, function()
					return up
				end)
				local firstFlag = table.find(verdicts, "flag")
				-- au plus 1 s de vol + 1,5 s de crédit de gel (+ un tick de frontière)
				expect(firstFlag ~= nil and firstFlag <= 27).toBe(true)
				expect(table.find(verdicts, "rewind") ~= nil).toBe(true)
				expect(MC.recentRewinds(player, T0 + 4)).toBe(1)
			end
		)
	end)
end
