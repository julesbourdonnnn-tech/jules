--!nocheck
-- Props_StateTimeouts (paquet logic, docs/04 §17.1 couche a) : expired est monotone en temps,
-- cohérent avec deadline, et ne bloque jamais un état au début illisible.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local ST = h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")
	local names = Props.oneOf(ST.names())

	describe("Props › StateTimeouts", function()
		it("expired(t) ⇔ t > deadline, monotone (une fois échu, toujours échu)", function()
			Props.check(
				5000,
				Props.tuple(
					names,
					Props.number(-1e9, 1e9),
					Props.number(0, 2000),
					Props.number(0, 100),
					Props.maybe(Props.number(-5, 5))
				),
				function(v)
					local name, start, dt, more, extra = v[1], v[2], v[3], v[4], v[5]
					local t1, t2 = start + dt, start + dt + more
					local deadline = ST.deadline(name, start, extra)
					local e1, e2 = ST.expired(name, start, t1, extra), ST.expired(name, start, t2, extra)
					return e1 == (t1 > deadline) and (not e1 or e2)
				end
			)
		end)

		it("début bizarre : toujours échu ; jamais d'erreur pour un état connu", function()
			Props.check(
				4000,
				Props.tuple(names, Props.anyNumber(), Props.anyNumber(), Props.any()),
				function(v)
					local ok = ST.expired(v[1], v[2], v[3], v[4])
					local finiteStart = type(v[2]) == "number"
						and v[2] == v[2]
						and math.abs(v[2]) ~= math.huge
					local finiteNow = type(v[3]) == "number" and v[3] == v[3] and math.abs(v[3]) ~= math.huge
					if not finiteStart and finiteNow then
						return ok == true
					end
					return type(ok) == "boolean"
				end
			)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
