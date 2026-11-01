--!nocheck
-- Props_LeapRules (paquet logic, docs/04 §17.1 couche a) : un bond ne fait jamais plus de 12 studs,
-- ne traverse jamais un solide, la direction acceptée est unitaire, entrées bizarres sûres.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")
	local Vector3 = require("@lune/roblox").Vector3

	local h = Harness.new()
	local L = h:require("ReplicatedStorage.Shared.Logic.LeapRules")
	local W = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	local any = Props.anyNumber()

	describe("Props › LeapRules", function()
		it("validDir : nil ou unitaire à plat", function()
			Props.check(5000, Props.tuple(any, any), function(v)
				local d = L.validDir(v[1], v[2])
				return d == nil or (math.abs(d.Magnitude - 1) < 1e-5 and d.Y == 0)
			end)
		end)

		it(
			"landing : ≤ 12 studs, aucun solide traversé (le long du trajet) depuis un point libre",
			function()
				Props.check(
					4000,
					Props.tuple(Props.vector3(-300, 300, true), Props.number(-math.pi, math.pi)),
					function(v)
						local from = Vector3.new(v[1].X, 3, v[1].Z)
						if W.blocked(from.X, from.Z, 0) or math.sqrt(from.X ^ 2 + from.Z ^ 2) > 318 then
							return true
						end
						local dir = Vector3.new(math.cos(v[2]), 0, math.sin(v[2]))
						local land = L.landing(from, dir)
						local d = math.sqrt((land.X - from.X) ^ 2 + (land.Z - from.Z) ^ 2)
						if d > 12 + 1e-3 then
							return false
						end
						for k = 1, 24 do
							local p = from:Lerp(land, k / 24)
							if W.blocked(p.X, p.Z, 0) then
								return false
							end
						end
						return true
					end
				)
			end
		)

		it("arc : hauteur dans [0 ; 2,5] au-dessus de la corde", function()
			Props.check(
				4000,
				Props.tuple(Props.vector3(-100, 100), Props.vector3(-100, 100), any),
				function(v)
					local p = L.arc(v[1], v[2], v[3])
					local a = if v[3] == v[3] then math.clamp(v[3], 0, 1) else 0
					local base = v[1]:Lerp(v[2], a)
					local lift = p.Y - base.Y
					return lift >= -1e-4 and lift <= 2.5 + 1e-4
				end
			)
		end)

		it(
			"catchesOnLanding : vrai ⇒ dans le rayon (+ tolérance) et pieds à 8 studs de haut (règle 17)",
			function()
				local Z = h:require("ReplicatedStorage.Shared.Logic.ZoneRules")
				Props.check(
					5000,
					Props.tuple(
						Props.vector3(-20, 20),
						Props.vector3(-20, 20),
						Props.bool(),
						Props.maybe(Props.number(0, 3)),
						Props.maybe(Props.number(0, 6))
					),
					function(v)
						local ok = L.catchesOnLanding(v[1], v[2], v[3], v[4], v[5])
						if not ok then
							return true
						end
						local r = (if v[3] then 8 else 5) + (v[4] or 0)
						local d = math.sqrt((v[1].X - v[2].X) ^ 2 + (v[1].Z - v[2].Z) ^ 2)
						return d <= r + 1e-4 and math.abs(Z.feetY(v[1].Y, v[5] or 0) - v[2].Y) <= 8 + 1e-4
					end
				)
			end
		)

		it("entrées bizarres : jamais d'erreur", function()
			Props.check(3000, Props.tuple(Props.any(), Props.any(), Props.any(), Props.any()), function(v)
				local land = L.landing(v[1], v[2])
				local arc = L.arc(v[1], v[2], v[3])
				local aim = L.aim(v[1], v[2], v[3], v[4], nil)
				local c = L.catchesOnLanding(v[1], v[2], v[3], v[4])
				return typeof(land) == "Vector3"
					and typeof(arc) == "Vector3"
					and (aim == nil or type(aim) == "number")
					and type(c) == "boolean"
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
