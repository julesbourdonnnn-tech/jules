--!nocheck
-- Correctifs r6 « serveur 2 » — EventService : encaissement de la Comète après un rattrapage
-- honnête. Un tick en rafale (rattrapage après un gel réseau, budget d'action de MoveCheck en dette)
-- qui traverse la porte de SON Nid n'encaissait pas la Comète (actor.valid exigé), et rien ne
-- l'encaissait ensuite tant que le porteur ne retraversait pas la boîte de porte (le Nid n'a pas de
-- murs). La traversée en rafale est maintenant « en attente » : encaissée au premier tick valide si
-- le porteur est toujours côté Nid (port sûr de son Nid), oubliée sinon. K5 (bond puis traversée,
-- puis ressortie) reste refusé (Fix_r5_serveur_anticheat), comme une traversée après un retour.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local TC = 1800000000 + 3600 -- impact de Comète (heure pile)
	local CARRY_STRIDE = 1.36 -- 16 × CarrierSpeedMult (0,85) studs par tick

	local function cometWorld()
		local w = Bots.boot(Harness, {
			t0 = TC - 45,
			before = function(w)
				for _, id in { 901, 902, 903 } do
					Bots.saveProfile(w, id, Bots.veteranProfile(w, TC - 45))
				end
			end,
		})
		local MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
		local A = w.h:addPlayer({ userId = 901, name = "Ana" })
		local B = w.h:addPlayer({ userId = 902, name = "Bo" })
		local C = w.h:addPlayer({ userId = 903, name = "Cy" })
		w.h:settle(3)
		Bots.frames(10)
		local slot = w.EC.nextComet(Bots.now())
		local impact = w.EC.cometImpact(slot.id)
		local function around(angle, r)
			return Bots.ground(impact.X + math.cos(angle) * r, impact.Z + math.sin(angle) * r)
		end
		return w, MoveCheck, A, B, C, impact, around
	end

	local function waitImpact(w)
		while Bots.now() < TC + 0.05 do
			Bots.frame()
		end
	end

	-- A ramasse la Comète à pied, puis rejoint `spot` (devant sa porte) en la portant et s'y arrête
	local function carryTo(w, A, impact, spot)
		for _ = 1, 40 do
			Bots.stepToward(A, Bots.ground(impact.X, impact.Z))
			Bots.frame()
			if w.Event.carrier() == A then
				break
			end
		end
		expect(w.Event.carrier()).toBe(A)
		for _ = 1, 800 do
			if Bots.stepToward(A, Bots.ground(spot.X, spot.Z), CARRY_STRIDE) then
				break
			end
			Bots.frame()
		end
		Bots.frames(12) -- à l'arrêt : budget d'action plein
		expect(w.Event.carrier()).toBe(A)
	end

	-- marche (à la vitesse du porteur) vers son Nid ; rend la phase de la Comète après chaque tick
	local function walkIn(w, A, ticks)
		local nest = w.WL.nestCenter(w.Nest.slotOf(A))
		local phases = {}
		for i = 1, ticks do
			Bots.stepToward(A, Bots.ground(nest.X, nest.Z), CARRY_STRIDE)
			Bots.frame()
			phases[i] = w.Event.snapshot().comet.phase
		end
		return phases
	end

	-- A porte la Comète jusqu'à 14 studs devant sa porte et s'y arrête, marche 5 ticks vers elle, gel
	-- réseau de `freeze` ticks, puis le rattrapage (`freeze` + 1 pas d'un coup) traverse la porte
	local function crossAfterFreeze(w, MoveCheck, A, B, C, impact, around, freeze)
		local gate = w.WL.gateCFrame(w.Nest.slotOf(A))
		local look = gate.LookVector -- vers le centre de l'île (hors du Nid)
		local g = w.V3.new(gate.Position.X, 0, gate.Position.Z)
		expect(Bots.walkAll({
			[A] = around(math.pi, 20),
			[B] = around(math.pi * 0.6, 40),
			[C] = around(math.pi * 1.4, 40),
		}, 400)).toBe(true)
		waitImpact(w)
		carryTo(w, A, impact, g + look * 14)
		for _ = 1, 5 do
			Bots.stepToward(A, Bots.ground(g.X, g.Z), CARRY_STRIDE)
			Bots.frame()
		end
		Bots.frames(freeze)
		local pos = Bots.rootOf(A).Position
		local catchUp = pos - look * (CARRY_STRIDE * (freeze + 1))
		w.h:moveTo(A, Bots.ground(catchUp.X, catchUp.Z))
		Bots.frame()
		-- arrivé derrière la boîte de porte (profonde de 4 studs), côté Nid : seul le balayage la voit
		local depth = (Bots.rootOf(A).Position - gate.Position):Dot(look)
		expect(depth).toBeLessThan(-2)
		expect(MoveCheck.lastWasBurst(A)).toBe(true)
		expect(w.Event.carrier()).toBe(A)
		expect(w.Event.snapshot().comet.phase).toBe("carried")
		return gate, look, g
	end

	describe("Fix r6 serveur 2 › Comète : rattrapage honnête à travers SA porte", function()
		it(
			"porteur à 13,6 studs/s, gel de 0,6 s, le rattrapage traverse sa porte puis il entre dans son Nid : encaissée",
			function()
				local w, MoveCheck, A, B, C, impact, around = cometWorld()
				local v0 = MoveCheck.violations(A)
				crossAfterFreeze(w, MoveCheck, A, B, C, impact, around, 6)
				-- il continue de marcher 2 s vers son Nid, sans repasser par la porte
				local phases = walkIn(w, A, 20)
				expect(table.find(phases, "banked") ~= nil).toBe(true)
				expect(w.Event.carrier()).toBeNil()
				expect(MoveCheck.violations(A) - v0).toBe(0)
			end
		)

		it(
			"contrôle : traversée en rafale puis sortie par le côté avant le premier tick valide : la traversée est oubliée",
			function()
				local w, MoveCheck, A, B, C, impact, around = cometWorld()
				local gate, look, g = crossAfterFreeze(w, MoveCheck, A, B, C, impact, around, 12)
				-- encore en dette, il ressort par le côté du Nid (jamais dans la boîte de porte, large
				-- de 12 studs) et se retrouve hors du Nid au premier tick valide
				local right = gate.RightVector
				local depth = (Bots.rootOf(A).Position - gate.Position):Dot(look)
				local side = g + right * 8 + look * depth
				for _ = 1, 20 do
					if Bots.stepToward(A, Bots.ground(side.X, side.Z), CARRY_STRIDE) then
						break
					end
					Bots.frame()
				end
				local out = g + right * 8 + look * 8
				local firstValidDepth = nil
				for _ = 1, 30 do
					local arrived = Bots.stepToward(A, Bots.ground(out.X, out.Z), CARRY_STRIDE)
					Bots.frame()
					if firstValidDepth == nil and MoveCheck.canAct(A, Bots.now()) then
						firstValidDepth = (Bots.rootOf(A).Position - gate.Position):Dot(look)
					end
					if arrived then
						break
					end
				end
				Bots.frames(5)
				expect(firstValidDepth ~= nil and firstValidDepth > 0).toBe(true)
				expect(w.Event.snapshot().comet.phase).toBe("carried")
				expect(w.Event.carrier()).toBe(A)
				-- puis il rentre côté Nid par le côté, à pied : pas d'encaissement sans traverser la porte
				local inside = g + right * 8 - look * 6
				for _ = 1, 30 do
					if Bots.stepToward(A, Bots.ground(inside.X, inside.Z), CARRY_STRIDE) then
						break
					end
					Bots.frame()
				end
				Bots.frames(5)
				expect(w.Event.snapshot().comet.phase).toBe("carried")
				expect(w.Event.carrier()).toBe(A)
			end
		)
	end)
end
