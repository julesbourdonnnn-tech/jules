--!nocheck
-- Props_Invariants (paquet logic, docs/04 §17.1 couche a) : jamais d'erreur sur un profil abîmé ;
-- les profils valides construits au hasard sont sains ; number / dense / uid cohérents.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local I = h:require("ReplicatedStorage.Shared.Logic.Invariants")

	-- uid = base 36 de nextUid (minuscules)
	local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
	local function base36(n)
		local out = ""
		repeat
			local d = n % 36
			out = string.sub(DIGITS, d + 1, d + 1) .. out
			n = n // 36
		until n == 0
		return out
	end
	local Schema = h:require("ServerScriptService.Server.Data.Schema")

	describe("Props › Invariants", function()
		it("profil valide au hasard (≤ 24 en enclos, ≤ 6 au Bassin…) : aucune violation", function()
			local recGen = Props.map(
				Props.tuple(
					Props.int(1, 26),
					Props.int(0, 9),
					Props.int(0, 5),
					Props.number(1, 1e30),
					Props.number(0, 1e6),
					Props.oneOf({ "pen", "pool", "dodo", "mail" })
				),
				function(v)
					return {
						s = v[1],
						m = v[2],
						st = v[3],
						z = v[4],
						zg = v[5],
						bf = 0,
						lk = false,
						o = "",
						at = v[6],
						b = 1,
					}
				end
			)
			Props.check(
				1500,
				Props.tuple(Props.array(recGen, 40), Props.number(0, 1e14), Props.int(0, 50)),
				function(v)
					local d = Schema.defaults()
					d.coins = math.floor(v[2])
					d.R = v[3]
					local counts = { pen = 0, pool = 0, dodo = 0, mail = 0 }
					local caps = { pen = 18, pool = 6, dodo = 60, mail = 20 }
					local n = 0
					for _, r in v[1] do
						if counts[r.at] < caps[r.at] and counts.pen + counts.pool < 24 then
							counts[r.at] += 1
							n += 1
							d.squishies[base36(n)] = r
						end
					end
					d.nextUid = n + 1
					local violations = I.profile(d)
					return #violations == 0, table.concat(violations, ", ")
				end
			)
		end)

		it("profil abîmé : liste de chaînes, jamais d'erreur", function()
			local profileGen = Props.map(
				Props.tuple(Props.any(), Props.any(), Props.any(), Props.any(), Props.any(), Props.any()),
				function(v)
					local d = Schema.defaults()
					d.coins = v[1]
					d.squishies = if type(v[2]) == "table" then v[2] else { ["1"] = v[2] }
					d.outfits = { owned = v[3], worn = v[4] }
					d.dex.mut = v[5]
					d.tiles = v[6]
					return d
				end
			)
			Props.check(3000, profileGen, function(d)
				local list = I.profile(d)
				for _, path in list do
					if type(path) ~= "string" then
						return false
					end
				end
				return type(list) == "table"
			end)
		end)

		it("number : vrai ⇔ nombre fini dans [min ; max]", function()
			Props.check(
				5000,
				Props.tuple(Props.any(), Props.number(-1e6, 1e6), Props.number(-1e6, 1e6)),
				function(v)
					local lo, hi = math.min(v[2], v[3]), math.max(v[2], v[3])
					local x = v[1]
					local expected = type(x) == "number"
						and x == x
						and math.abs(x) ~= math.huge
						and x >= lo
						and x <= hi
					return I.number(x, lo, hi) == expected
				end
			)
		end)

		it("uid : base 36 minuscule, 1 à 8 caractères", function()
			Props.check(4000, Props.any(), function(x)
				local ok = I.uid(x)
				if not ok then
					return true
				end
				return type(x) == "string"
					and #x >= 1
					and #x <= 8
					and tonumber(x, 36) ~= nil
					and string.lower(x) == x
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
