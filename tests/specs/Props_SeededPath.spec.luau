--!nocheck
-- Props_SeededPath (paquet logic, docs/04 §17.1 couche a) : pour toute graine, tout instant et toute
-- diffusion abîmée, une position finie, hors des ranchs, et le même résultat à chaque appel.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local SP = h:require("ReplicatedStorage.Shared.Logic.SeededPath")
	local W = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	local any = Props.anyNumber()

	local function finite(p)
		return typeof(p) == "Vector3"
			and p.X == p.X
			and p.Z == p.Z
			and math.abs(p.X) < 400
			and math.abs(p.Z) < 400
	end

	describe("Props › SeededPath", function()
		it(
			"escape : position finie, hors des ranchs, déterministe, pour toute graine et tout instant",
			function()
				Props.check(
					2000,
					Props.tuple(any, Props.int(1, 16), Props.number(-10, 10), Props.number(-5, 40)),
					function(v)
						local a = SP.escape(v[1], 0, W.fountainNode(v[2]), v[3])
						local b = SP.escape(v[1], 0, W.fountainNode(v[2]), v[3])
						local p, air = a(v[4])
						return finite(p)
							and type(air) == "boolean"
							and W.ranchNear(p, 1) == 0
							and p == b(v[4])
					end
				)
			end
		)

		it("hopAround : dans le rayon, hors des ranchs", function()
			Props.check(1000, Props.tuple(any, Props.int(1, 16), Props.number(-5, 30)), function(v)
				local center = W.anchor(v[2], "fountain")
				local path = SP.hopAround(v[1], 0, center, 35)
				local p = path(v[3])
				local d = math.sqrt((p.X - center.X) ^ 2 + (p.Z - center.Z) ^ 2)
				return finite(p) and d <= 35 + 1e-3 and W.ranchNear(p, 1) == 0
			end)
		end)

		it("golden et demo : positions finies hors des ranchs", function()
			Props.check(
				1500,
				Props.tuple(any, Props.int(1, 57), Props.number(-5, 40), Props.int(1, 16)),
				function(v)
					local g = SP.golden(v[1], 0, v[2])(v[3])
					local d = SP.demo(v[1], 0, W.gateOutside(v[4]))(v[3])
					return finite(g) and finite(d) and W.ranchNear(g, 1) == 0 and W.ranchNear(d, 1) == 0
				end
			)
		end)

		it("fromSpawn : diffusion abîmée → trajet sûr, jamais d'erreur", function()
			local spawnGen = Props.map(
				Props.tuple(
					Props.oneOf({ "runaway", "escape", "wild", "wildPersonal", "golden", "demo", "???", nil }),
					Props.oneOf({ "escape", "hop", nil, 4 }),
					any,
					any,
					any,
					any,
					Props.any(),
					any
				),
				function(v)
					return {
						kind = v[1],
						path = v[2],
						seed = v[3],
						t0 = v[4],
						startNode = v[5],
						awayAngle = v[6],
						center = v[7],
						speed = v[8],
					}
				end
			)
			Props.check(2000, Props.tuple(spawnGen, any), function(v)
				local path = SP.fromSpawn(v[1])
				local p, air = path(v[2])
				return typeof(p) == "Vector3" and p.X == p.X and p.Z == p.Z and type(air) == "boolean"
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
