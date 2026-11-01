--!nocheck
-- BigNumber (paquet logic, docs/04 §12.1, GDD §4.2) : cas exacts du GDD en anglais et en français.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local BN = h:require("ReplicatedStorage.Shared.Logic.BigNumber")
	local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
	local NNBSP = "\226\128\175" -- U+202F

	describe("BigNumber", function()
		it("exemples du GDD §4.2 et de docs/04 (EN)", function()
			expect(BN.abbreviate(9876, "en")).toBe("9,876")
			expect(BN.abbreviate(12345, "en")).toBe("12.3K")
			expect(BN.abbreviate(999999, "en")).toBe("999K")
			expect(BN.abbreviate(4560000000, "en")).toBe("4.56B")
			expect(BN.abbreviate(7.8e12, "en")).toBe("7.80T")
			expect(BN.abbreviate(1e36, "en")).toBe("1.00e36")
		end)

		it("exemples du GDD §4.2 et de docs/04 (FR : virgule, espace fine insécable)", function()
			expect(BN.abbreviate(9876, "fr")).toBe("9" .. NNBSP .. "876")
			expect(BN.abbreviate(12345, "fr")).toBe("12,3" .. NNBSP .. "k")
			expect(BN.abbreviate(999999, "fr")).toBe("999" .. NNBSP .. "k")
			expect(BN.abbreviate(4560000000, "fr")).toBe("4,56" .. NNBSP .. "Md")
			expect(BN.abbreviate(7.8e12, "fr")).toBe("7,80" .. NNBSP .. "Bn")
			expect(BN.abbreviate(1e36, "fr")).toBe("1,00e36")
		end)

		it("3 chiffres significatifs tronqués, jamais arrondis vers le haut, zéro final gardé", function()
			expect(BN.abbreviate(10000, "en")).toBe("10.0K")
			expect(BN.abbreviate(99999, "en")).toBe("99.9K")
			expect(BN.abbreviate(100000, "en")).toBe("100K")
			expect(BN.abbreviate(1e6, "en")).toBe("1.00M")
			expect(BN.abbreviate(1999999, "en")).toBe("1.99M")
			expect(BN.abbreviate(99999999999, "en")).toBe("99.9B")
			expect(BN.abbreviate(999999999999999, "en")).toBe("999T")
			-- petite erreur flottante (4,5599999999999995e9) : affichée comme la valeur voulue
			expect(BN.abbreviate(4.56 * 1e9, "en")).toBe("4.56B")
			expect(BN.abbreviate(0.1 + 0.2, "en")).toBe("0")
		end)

		it("chaque suffixe du GDD, du plus petit au plus grand", function()
			local en = BN.suffixes("en")
			local fr = BN.suffixes("fr")
			expect(en).toEqual({ "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" })
			expect(fr).toEqual({ "k", "M", "Md", "Bn", "Bd", "Tn", "Td", "Qn", "Qd", "Qt", "Qtd" })
			for i, suffix in en do
				-- 12,3 × 10^(3i) : au-dessus de 10 000 dès le premier palier
				expect(BN.abbreviate(12.3 * 10 ^ (3 * i), "en")).toBe("12.3" .. suffix)
				expect(BN.abbreviate(12.3 * 10 ^ (3 * i), "fr")).toBe("12,3" .. NNBSP .. fr[i])
			end
			-- la liste rendue est une copie
			en[1] = "x"
			expect(BN.suffixes("en")[1]).toBe("K")
			expect(BN.suffixes(nil)[1]).toBe("K")
		end)

		it("au-delà de Dc : notation scientifique jusqu'à 1e300 et au-delà", function()
			expect(BN.abbreviate(9.99e35, "en")).toBe("999Dc")
			expect(BN.abbreviate(1.234e45, "en")).toBe("1.23e45")
			expect(BN.abbreviate(1e300, "fr")).toBe("1,00e300")
			expect(BN.abbreviate(1.7e308, "en")).toBe("1.70e308")
		end)

		it("entrées bizarres : NaN → 0, ±inf → ∞, −0 → 0, négatifs signés", function()
			expect(BN.abbreviate(0 / 0, "en")).toBe("0")
			expect(BN.abbreviate(math.huge, "en")).toBe("∞")
			expect(BN.abbreviate(-math.huge, "fr")).toBe("∞")
			expect(BN.abbreviate(-0.0, "en")).toBe("0")
			expect(BN.abbreviate(-12345, "en")).toBe("-12.3K")
			expect(BN.abbreviate(-0.5, "en")).toBe("0")
			expect(BN.abbreviate(nil, "en")).toBe("0")
			expect(BN.abbreviate("12" :: any, "en")).toBe("0")
		end)

		it("full : entier exact avec séparateurs sous 1e15, sinon abrégé", function()
			expect(BN.full(123456789012345, "en")).toBe("123,456,789,012,345")
			expect(BN.full(1234567, "fr")).toBe("1" .. NNBSP .. "234" .. NNBSP .. "567")
			expect(BN.full(999.9, "en")).toBe("999")
			expect(BN.full(1e15, "en")).toBe("1.00Qa")
			expect(BN.full(0 / 0, "en")).toBe("0")
			expect(BN.full(math.huge, "en")).toBe("∞")
			expect(BN.full(-1234, "en")).toBe("-1,234")
		end)

		it("words : forme courte et mot entier (pluriel français dès 2)", function()
			local short, words = BN.words(7.8e12, "fr")
			expect(short).toBe("7,80" .. NNBSP .. "Bn")
			expect(words).toBe("7,80 billions")
			local s2, w2 = BN.words(7.8e12, "en")
			expect(s2).toBe("7.80T")
			expect(w2).toBe("7.80 trillion")
			expect(select(2, BN.words(1.5e9, "fr"))).toBe("1,50 milliard")
			expect(select(2, BN.words(12345, "fr"))).toBe("12,3 mille")
			expect(select(2, BN.words(9876, "en"))).toBe("9,876")
			expect(select(2, BN.words(1e40, "en"))).toBe("1.00e40")
			expect(select(2, BN.words(0 / 0, "en"))).toBe("0")
		end)

		it("words : chaque mot vient des clés num.name.<p> (EN et FR)", function()
			for p = 3, 33, 3 do
				expect(Strings.en["num.name." .. p] ~= nil).toBe(true)
				expect(Strings.fr["num.name." .. p] ~= nil).toBe(true)
				local _, en = BN.words(30 * 10 ^ p, "en")
				expect(string.find(en, Strings.en["num.name." .. p], 1, true) ~= nil).toBe(true)
			end
		end)

		it("milestoneKey : jalons des bannières seulement", function()
			expect(BN.milestoneKey(1e6)).toBe("num.word.6")
			expect(BN.milestoneKey(1e9)).toBe("num.word.9")
			expect(BN.milestoneKey(1e12)).toBe("num.word.12")
			expect(BN.milestoneKey(1e15)).toBe("num.word.15")
			expect(BN.milestoneKey(2e6)).toBeNil()
			expect(BN.milestoneKey(1e18)).toBeNil()
			expect(BN.milestoneKey(0 / 0)).toBeNil()
			expect(BN.milestoneKey(-1e6)).toBeNil()
			for _, p in { 6, 9, 12, 15 } do
				expect(Strings.en["num.word." .. p] ~= nil and Strings.fr["num.word." .. p] ~= nil).toBe(true)
			end
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
