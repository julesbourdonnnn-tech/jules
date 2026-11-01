--!nocheck
-- Hash (paquet logic, docs/04 §12.1) : valeurs de référence FIGÉES, reprises de Comet Conga (mêmes
-- constantes). Ces nombres doivent être identiques sous Lune et sous Roblox : ne jamais les
-- « mettre à jour » sans changer de sel, car les tirages de la Cuve, les trajets des créatures, le
-- PERFECT, les objectifs du jour et les alias de tous les serveurs en dépendent.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local Hash = h:require("ReplicatedStorage.Shared.Logic.Hash")

	describe("Hash", function()
		it("u32 : valeurs de référence", function()
			expect(Hash.u32()).toBe(3954623016)
			expect(Hash.u32(0)).toBe(2741404029)
			expect(Hash.u32(1)).toBe(4082427836)
			expect(Hash.u32(1, 2)).toBe(250122830)
			expect(Hash.u32(2, 1)).toBe(2332522349)
			expect(Hash.u32(4782969, 0x57E4)).toBe(3639438243)
			expect(Hash.u32(1793462400, 0xC0DE, 1)).toBe(2934376755)
			expect(Hash.u32(-1)).toBe(1971636267)
			expect(Hash.u32(4294967295)).toBe(2649125627)
			expect(Hash.u32(2 ^ 32 + 5)).toBe(1108857847)
		end)

		it("u32 : l'ordre des clés compte, les réels sont tronqués, NaN/inf valent 0", function()
			expect(Hash.u32(1, 2) ~= Hash.u32(2, 1)).toBe(true)
			expect(Hash.u32(3.9)).toBe(Hash.u32(3))
			expect(Hash.u32(-3.9)).toBe(Hash.u32(-3))
			expect(Hash.u32(0 / 0)).toBe(Hash.u32(0))
			expect(Hash.u32(math.huge)).toBe(Hash.u32(0))
			expect(Hash.u32(-math.huge)).toBe(Hash.u32(0))
			-- une clé de plus change le résultat (la longueur est mélangée)
			expect(Hash.u32(0) ~= Hash.u32(0, 0)).toBe(true)
			expect(Hash.u32() ~= Hash.u32(0)).toBe(true)
		end)

		it("u32 : toujours un entier de [0, 2^32[", function()
			for i = 1, 2000 do
				local v = Hash.u32(i, i * 7919, -i)
				expect(v >= 0 and v < 2 ^ 32 and v % 1 == 0).toBe(true)
			end
		end)

		it("unit, int, range : valeurs de référence et bornes", function()
			expect(Hash.unit(20757, 123456789)).toBeNear(0.72713015996851027, 1e-15)
			expect(Hash.int(1, 25, 20757, 42)).toBe(22)
			expect(Hash.range(10, 40, 7)).toBeNear(36.151871976908296, 1e-12)
			for i = 1, 3000 do
				local u = Hash.unit(i, 99)
				expect(u >= 0 and u < 1).toBe(true)
				local n = Hash.int(-3, 3, i)
				expect(n >= -3 and n <= 3 and n % 1 == 0).toBe(true)
				local r = Hash.range(10, 40, i)
				expect(r >= 10 and r < 40).toBe(true)
			end
			-- bornes inversées ou égales
			expect(Hash.int(5, 5, 1)).toBe(5)
			local swapped = Hash.int(9, 2, 77)
			expect(swapped >= 2 and swapped <= 9).toBe(true)
		end)

		it("int : répartition uniforme (±2 % sur 100 000 tirages)", function()
			local counts = { 0, 0, 0, 0 }
			for i = 1, 100000 do
				local k = Hash.int(1, 4, i, 99)
				counts[k] += 1
			end
			for k = 1, 4 do
				expect(counts[k] / 100000).toBeNear(0.25, 0.005)
			end
		end)

		it(
			"pickWeighted : poids cumulés, poids nuls jamais choisis, entrées dégénérées sûres",
			function()
				local w = { 30, 26, 20, 17, 7 }
				expect(Hash.pickWeighted(w, 0)).toBe(1)
				expect(Hash.pickWeighted(w, 0.2999)).toBe(1)
				expect(Hash.pickWeighted(w, 0.30)).toBe(2)
				expect(Hash.pickWeighted(w, 0.9999)).toBe(5)
				-- somme quelconque (normalisée)
				expect(Hash.pickWeighted({ 1, 1 }, 0.49)).toBe(1)
				expect(Hash.pickWeighted({ 1, 1 }, 0.51)).toBe(2)
				-- poids nuls, négatifs ou NaN : jamais choisis
				for i = 1, 500 do
					local idx = Hash.pickWeighted({ 0, 5, -2, 0 / 0, 5 }, Hash.unit(i))
					expect(idx == 2 or idx == 5).toBe(true)
				end
				-- r hors de [0, 1[ ou NaN : borné
				expect(Hash.pickWeighted(w, -1)).toBe(1)
				expect(Hash.pickWeighted(w, 1)).toBe(5)
				expect(Hash.pickWeighted(w, 0 / 0)).toBe(1)
				-- aucun poids positif
				expect(Hash.pickWeighted({}, 0.5)).toBe(1)
				expect(Hash.pickWeighted({ 0, 0 }, 0.5)).toBe(1)
			end
		)

		it("string : FNV-1a 32 bits (valeurs publiées)", function()
			expect(Hash.string("")).toBe(2166136261) -- 0x811C9DC5
			expect(Hash.string("a")).toBe(3826002220) -- 0xE40C292C
			expect(Hash.string("foobar")).toBe(3214735720) -- 0xBF9CF968
			expect(Hash.string("COMETCONGA")).toBe(2681947373)
		end)

		it("stream : suite de référence, déterministe, bornée", function()
			local s = Hash.stream(20261030)
			local expected = {
				0.44051370210945606,
				0.86878774734213948,
				0.46193426032550633,
				0.87208979204297066,
				0.019479676382616162,
			}
			for i = 1, 5 do
				expect(s:next()).toBeNear(expected[i], 1e-15)
			end
			expect(s:int(1, 100)).toBe(45)
			expect(s:range(0, 10)).toBeNear(7.5131541676819324, 1e-12)
			-- deux flux de même graine donnent la même suite ; graines différentes : suites différentes
			local a, b, c = Hash.stream(7), Hash.stream(7), Hash.stream(8)
			local same, differ = true, false
			for _ = 1, 100 do
				local x, y, z = a:next(), b:next(), c:next()
				same = same and x == y
				differ = differ or x ~= z
				expect(x >= 0 and x < 1).toBe(true)
			end
			expect(same).toBe(true)
			expect(differ).toBe(true)
			-- graine dégénérée : jamais bloqué sur 0
			local z = Hash.stream(0 / 0)
			local nonZero = false
			for _ = 1, 10 do
				nonZero = nonZero or z:next() > 0
			end
			expect(nonZero).toBe(true)
		end)

		it("string : chaîne illisible traitée comme vide, jamais d'erreur", function()
			expect(Hash.string(nil :: any)).toBe(Hash.string(""))
			expect(Hash.string(42 :: any)).toBe(Hash.string(""))
		end)

		it("int / range / stream:int : bornes NaN ou infinies sûres", function()
			expect(Hash.int(0 / 0, 5, 1)).toBe(Hash.int(0, 5, 1))
			expect(Hash.int(1, math.huge, 3)).toBe(Hash.int(1, 0, 3))
			expect(Hash.range(0 / 0, 1, 1) == Hash.range(0 / 0, 1, 1)).toBe(true)
			local s = Hash.stream(1)
			local v = s:int(0 / 0, 0 / 0)
			expect(v).toBe(0)
			local r = s:range(-math.huge, 1)
			expect(r == r).toBe(true)
		end)

		it("pickWeighted : liste illisible → 1", function()
			expect(Hash.pickWeighted(nil :: any, 0.5)).toBe(1)
			expect(Hash.pickWeighted({ "a" :: any, 2 }, 0.1)).toBe(2)
		end)

		it("alias : 4 chiffres, figé, différent d'un joueur à l'autre", function()
			expect(Hash.alias(1)).toBe(2670)
			expect(Hash.alias(156)).toBe(8082)
			local seen = {}
			local distinct = 0
			for id = 1, 5000 do
				local a = Hash.alias(id)
				expect(a >= 1000 and a <= 9999 and a % 1 == 0).toBe(true)
				if not seen[a] then
					seen[a] = true
					distinct += 1
				end
			end
			-- 5 000 joueurs sur 9 000 alias : beaucoup d'alias distincts (pas de valeur dominante)
			expect(distinct > 3000).toBe(true)
			expect(Hash.alias(0 / 0)).toBe(Hash.alias(0))
		end)

		it("zéro trace : aucune erreur ni aucun avertissement du harnais", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
