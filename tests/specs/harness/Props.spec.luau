--!nocheck
-- tests/harness/Props (paquet logic, docs/04 §17.1 couche a) : l'outil des tests de propriétés est
-- lui-même testé (déterminisme, générateurs, réduction du contre-exemple, message lisible).
return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local Props = require("../../harness/Props")

	describe("Props (outil)", function()
		it("même graine, mêmes valeurs ; graines différentes, valeurs différentes", function()
			local a, b, c = Props.rng(7), Props.rng(7), Props.rng(8)
			local same, differ = true, false
			for _ = 1, 100 do
				local x, y, z = a.next(), b.next(), c.next()
				same = same and x == y
				differ = differ or x ~= z
				expect(x >= 0 and x < 1).toBe(true)
			end
			expect(same).toBe(true)
			expect(differ).toBe(true)
		end)

		it("check : une propriété vraie passe", function()
			expect(Props.check(500, Props.int(0, 10), function(x)
				return x >= 0 and x <= 10
			end)).toBe(true)
		end)

		it(
			"check : une propriété fausse lève une erreur avec la graine, le cas et un contre-exemple réduit",
			function()
				local ok, err = pcall(Props.check, 500, Props.int(0, 100000), function(x)
					return x < 1000
				end, { seed = 3 })
				expect(ok).toBe(false)
				expect(string.find(tostring(err), "propriété fausse (graine 3", 1, true) ~= nil).toBe(true)
				local value = tonumber(string.match(tostring(err), ": (%d+)"))
				expect(value ~= nil and value >= 1000).toBe(true)
				-- réduit : bien plus petit qu'un tirage typique dans [0 ; 100 000]
				expect(value < 4000).toBe(true)
			end
		)

		it(
			"check : une erreur dans le prédicat est un échec, avec son message ; la raison est affichée",
			function()
				local ok, err = pcall(Props.check, 10, Props.constant(1), function()
					error("boum")
				end)
				expect(ok).toBe(false)
				expect(string.find(tostring(err), "boum", 1, true) ~= nil).toBe(true)
				local ok2, err2 = pcall(Props.check, 10, Props.constant(1), function()
					return false, "parce que"
				end)
				expect(ok2).toBe(false)
				expect(string.find(tostring(err2), "parce que", 1, true) ~= nil).toBe(true)
			end
		)

		it(
			"générateurs : limites (NaN, ±inf, −0), chaînes valides et invalides, tables hostiles",
			function()
				local rng = Props.rng(1)
				local seenNaN, seenInf, seenNegZero = false, false, false
				for _ = 1, 2000 do
					local x = Props.weird().gen(rng)
					seenNaN = seenNaN or x ~= x
					seenInf = seenInf or x == math.huge
					seenNegZero = seenNegZero or (x == 0 and 1 / x < 0)
				end
				expect(seenNaN and seenInf and seenNegZero).toBe(true)
				local invalid = false
				for _ = 1, 200 do
					local s = Props.bytes(20).gen(rng)
					if utf8.len(s) == nil then
						invalid = true
					end
					local v = Props.utf8(20).gen(rng)
					expect(utf8.len(v) ~= nil).toBe(true)
				end
				expect(invalid).toBe(true)
				local holey = false
				for _ = 1, 200 do
					local t = Props.weirdTable().gen(rng)
					if t[1] == 1 and t[3] == nil and t[4] == 4 then
						holey = true
					end
				end
				expect(holey).toBe(true)
				expect(Props.format(0 / 0)).toBe("NaN")
				expect(Props.format(-0.0)).toBe("-0")
				local cyclic = {}
				cyclic.self = cyclic
				expect(string.find(Props.format(cyclic), "<cycle>", 1, true) ~= nil).toBe(true)
			end
		)

		it("tuple : réduit chaque élément à son tour", function()
			local ok, err = pcall(
				Props.check,
				300,
				Props.tuple(Props.int(0, 1000), Props.int(0, 1000)),
				function(v)
					return v[1] + v[2] < 500
				end
			)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "propriété fausse", 1, true) ~= nil).toBe(true)
		end)
	end)
end
