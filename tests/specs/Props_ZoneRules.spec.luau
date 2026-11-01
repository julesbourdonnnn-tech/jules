--!nocheck
-- Props_ZoneRules (paquet logic, docs/04 §17.1 couche a) : hystérésis (jamais deux entrées sans
-- sortie au-delà de 3,5), zones cohérentes avec WorldLayout, entrées bizarres sans effet.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local Z = h:require("ReplicatedStorage.Shared.Logic.ZoneRules")
	local W = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	local any = Props.anyNumber()
	local point = Props.vector3(-340, 340, true)

	describe("Props › ZoneRules", function()
		it("padStep : entre deux « vient d'entrer », la distance a dépassé 3,5", function()
			Props.check(3000, Props.array(Props.number(0, 6), 60), function(list)
				local inside, wentOut = false, true
				for _, d in list do
					local entered
					inside, entered = Z.padStep(inside, d)
					if entered then
						if not wentOut then
							return false
						end
						wentOut = false
					end
					if d > 3.5 then
						wentOut = true
					end
				end
				return true
			end)
		end)

		it("padStep : dedans ⇒ distance ≤ 3,5 ; jamais d'erreur", function()
			Props.check(4000, Props.tuple(Props.any(), any), function(v)
				local inside, entered = Z.padStep(v[1], v[2])
				if entered and not inside then
					return false
				end
				return not inside or v[2] <= 3.5
			end)
		end)

		it("intruder : un ranch d'un autre exactement quand ranchAt le dit", function()
			Props.check(4000, Props.tuple(Props.int(0, 16), point), function(v)
				local slot = W.ranchAt(v[2])
				local who = Z.intruder(v[1], v[2])
				if slot == 0 or slot == v[1] then
					return who == 0
				end
				return who == slot
			end)
		end)

		it("streetSideOfFence : jamais vrai dans un ranch", function()
			Props.check(4000, Props.tuple(Props.int(1, 16), point, Props.number(0, 12)), function(v)
				if Z.streetSideOfFence(v[1], v[2], v[3]) then
					return not W.inRanch(v[1], v[2]) or W.toLocal(v[1], v[2]).Z <= 1e-3
				end
				return true
			end)
		end)

		it("entrées bizarres : jamais vrai, jamais d'erreur", function()
			Props.check(3000, Props.tuple(Props.any(), Props.any(), Props.any()), function(v)
				local pos = if typeof(v[2]) == "Vector3" then nil else v[2]
				return not Z.near(v[1], "pot", pos, v[3])
					and not Z.inMegaZone(pos)
					and not Z.streetSideOfFence(v[1], pos, v[3])
					and not Z.ownerNearFence(v[1], pos)
					and Z.intruder(v[1], pos) == 0
					and not Z.atAltar(pos)
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
