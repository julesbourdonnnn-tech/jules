--!nocheck
-- Props_PressTiming (paquet logic, docs/04 §17.1 couche a) : phase et décalage bornés, PERFECT ⇔
-- distance au sommet dans la fenêtre, tClient toujours dans la fenêtre acceptée.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local PT = h:require("ReplicatedStorage.Shared.Logic.PressTiming")
	local any = Props.anyNumber()

	describe("Props › PressTiming", function()
		it("offset ∈ [0 ; 1,2[, phase ∈ [0 ; 1[, pour toute entrée", function()
			Props.check(5000, Props.tuple(any, Props.string(12), any), function(v)
				local off = PT.offset(v[1], v[2])
				local p = PT.phase(v[3], off)
				return off >= 0 and off < 1.2 and p >= 0 and p < 1
			end)
		end)

		it("isPerfect ⇔ phase dans la fenêtre (hors bornes à 1e-6 près)", function()
			Props.check(6000, Props.tuple(Props.number(0, 1e7), Props.number(0, 1.2)), function(v)
				local t, off = v[1], v[2]
				local d = PT.phase(t, off) * 1.2
				if math.abs(d - 0.2) < 1e-6 or math.abs(d - 1.12) < 1e-6 then
					return true
				end
				return PT.isPerfect(t, off) == (d <= 0.2 or d >= 1.12)
			end)
		end)

		it("nextApex ≥ t et à moins d'une période, phase 0 au sommet", function()
			Props.check(5000, Props.tuple(Props.number(0, 1e7), Props.number(0, 1.2)), function(v)
				local a = PT.nextApex(v[1], v[2])
				return a >= v[1] - 1e-9 and a - v[1] < 1.2 + 1e-9 and PT.isPerfect(a, v[2])
			end)
		end)

		it("clampClientTime : toujours dans [now − 0,35 ; now + 0,05]", function()
			Props.check(6000, Props.tuple(any, Props.number(-1e9, 1e9)), function(v)
				local t = PT.clampClientTime(v[1], v[2])
				return t >= v[2] - 0.35 - 1e-6 and t <= v[2] + 0.05 + 1e-6
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
