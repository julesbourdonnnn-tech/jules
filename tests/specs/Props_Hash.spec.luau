--!nocheck
-- Props_Hash (paquet logic, docs/04 §17.1 couche a) : propriétés de Hash sur des milliers d'entrées
-- tirées à graine fixe (tests/harness/Props), entrées bizarres comprises.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local Hash = h:require("ReplicatedStorage.Shared.Logic.Hash")

	describe("Props › Hash", function()
		it(
			"u32 : entier de [0 ; 2^32[ pour toute suite de clés (NaN, ±inf, 1e308, −0 compris)",
			function()
				Props.check(5000, Props.array(Props.anyNumber(), 5), function(keys)
					local v = Hash.u32(table.unpack(keys))
					return v >= 0 and v < 2 ^ 32 and v % 1 == 0
				end)
			end
		)

		it("u32 : déterministe (deux appels identiques donnent la même valeur)", function()
			Props.check(3000, Props.tuple(Props.anyNumber(), Props.anyNumber()), function(v)
				return Hash.u32(v[1], v[2]) == Hash.u32(v[1], v[2])
			end)
		end)

		it("unit ∈ [0 ; 1[, range ∈ [min ; max[, int ∈ [min ; max] entier", function()
			Props.check(
				5000,
				Props.tuple(Props.anyNumber(), Props.int(-1000, 1000), Props.int(-1000, 1000)),
				function(v)
					local u = Hash.unit(v[1])
					if not (u >= 0 and u < 1) then
						return false
					end
					local lo, hi = math.min(v[2], v[3]), math.max(v[2], v[3])
					local n = Hash.int(v[2], v[3], v[1])
					if not (n >= lo and n <= hi and n % 1 == 0) then
						return false
					end
					if lo < hi then
						local r = Hash.range(lo, hi, v[1])
						return r >= lo and r < hi
					end
					return true
				end
			)
		end)

		it("int / range : bornes bizarres → résultat fini, jamais d'erreur", function()
			Props.check(
				3000,
				Props.tuple(Props.anyNumber(), Props.anyNumber(), Props.anyNumber()),
				function(v)
					local n = Hash.int(v[1], v[2], v[3])
					local r = Hash.range(v[1], v[2], v[3])
					return n == n and r == r and math.abs(n) ~= math.huge
				end
			)
		end)

		it("pickWeighted : index d'un poids positif, ou 1 sans poids positif", function()
			Props.check(4000, Props.tuple(Props.array(Props.anyNumber(), 8), Props.anyNumber()), function(v)
				local weights, r = v[1], v[2]
				local i = Hash.pickWeighted(weights, r)
				local anyPositive = false
				for _, w in weights do
					if w == w and w > 0 and w ~= math.huge then
						anyPositive = true
					end
				end
				if not anyPositive then
					return i == 1
				end
				local w = weights[i]
				return w ~= nil and w == w and w > 0 and w ~= math.huge
			end)
		end)

		it("string : entier 32 bits pour toute chaîne (UTF-8 invalide et 100 000 octets compris)", function()
			Props.check(1500, Props.string(64), function(s)
				local v = Hash.string(s)
				return v >= 0 and v < 2 ^ 32 and v % 1 == 0 and v == Hash.string(s)
			end)
		end)

		it("stream : :next ∈ [0 ; 1[, :int borné, même graine = même suite", function()
			Props.check(800, Props.anyNumber(), function(seed)
				local a, b = Hash.stream(seed), Hash.stream(seed)
				for _ = 1, 20 do
					local x = a:next()
					if not (x >= 0 and x < 1) or x ~= b:next() then
						return false
					end
					local n = a:int(1, 6)
					if n ~= b:int(1, 6) or n < 1 or n > 6 then
						return false
					end
				end
				return true
			end)
		end)

		it("alias ∈ [1000 ; 9999] pour tout identifiant, toujours le même", function()
			Props.check(4000, Props.anyNumber(), function(id)
				local a = Hash.alias(id)
				return a >= 1000 and a <= 9999 and a % 1 == 0 and a == Hash.alias(id)
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
