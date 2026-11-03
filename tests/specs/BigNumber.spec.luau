--!nocheck
-- BigNumber (paquet logic, docs/04 §12.1, GDD §4.2) : cas exacts du GDD en anglais et en français.
-- GDD v2.0 (lot A1, journal docs/04 §27.12) : suffixes jusqu'à Tg (1e93), notation e dès 1e96 ;
-- français sans espace insécable (aucune dans FredokaOne ni LuckiestGuy, note INT-V2-GLYPHS d) :
-- suffixe collé (« 12,3K »), pas de séparateur à 4 chiffres (« 9876 »), U+0020 au-delà dans full()
-- et words() ; ±inf → plafond affiché « 1.00e300 » (« ∞ » est absent des deux polices).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local BN = h:require("ReplicatedStorage.Shared.Logic.BigNumber")
	local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
	local SP = " " -- U+0020 : seule espace des deux polices (groupes de full() et words() en français)

	describe("BigNumber", function()
		it("exemples du GDD §4.2 et de docs/04 (EN)", function()
			expect(BN.abbreviate(9876, "en")).toBe("9,876")
			expect(BN.abbreviate(12345, "en")).toBe("12.3K")
			expect(BN.abbreviate(999999, "en")).toBe("999K")
			expect(BN.abbreviate(4560000000, "en")).toBe("4.56B")
			expect(BN.abbreviate(7.8e12, "en")).toBe("7.80T")
			-- GDD v2.0 §4.2 : suffixes jusqu'à 1e93 (v1.3 : « 1.00e36 »)
			expect(BN.abbreviate(1e36, "en")).toBe("1.00Ud")
		end)

		it(
			"exemples du GDD §4.2 (FR : mêmes suffixes, virgule, suffixe collé : une seule ligne)",
			function()
				-- v1.3 : espace fine insécable U+202F, absente des deux polices (INT-V2-GLYPHS d)
				expect(BN.abbreviate(9876, "fr")).toBe("9876")
				expect(BN.abbreviate(1000, "fr")).toBe("1000")
				expect(BN.abbreviate(12345, "fr")).toBe("12,3K")
				expect(BN.abbreviate(999999, "fr")).toBe("999K")
				expect(BN.abbreviate(1.23e6, "fr")).toBe("1,23M")
				expect(BN.abbreviate(4560000000, "fr")).toBe("4,56B")
				expect(BN.abbreviate(7.8e12, "fr")).toBe("7,80T")
				expect(BN.abbreviate(1e36, "fr")).toBe("1,00Ud")
				-- aucune espace dans une forme courte, de 0 à 1e300 (rien ne coupe un montant en deux lignes)
				for e = 0, 300 do
					for _, lang in { "en", "fr" } do
						local s = BN.abbreviate(1.5 * 10 ^ e, lang)
						expect({ e = e, lang = lang, space = string.find(s, "%s") ~= nil }).toEqual({
							e = e,
							lang = lang,
							space = false,
						})
					end
				end
			end
		)

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

		it("chaque suffixe du GDD v2.0 §4.2, du plus petit (K, 1e3) au plus grand (Tg, 1e93)", function()
			local en = BN.suffixes("en")
			local fr = BN.suffixes("fr")
			-- stylua: ignore start
			local GDD = {
				"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
				"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nvd",
				"Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg", "Nvvg", "Tg",
			}
			-- stylua: ignore end
			expect(#GDD).toBe(31)
			expect(en).toEqual(GDD)
			-- suffixes internationaux dans les deux langues
			expect(fr).toEqual(GDD)
			for i, suffix in en do
				-- 12,3 × 10^(3i) : au-dessus de 10 000 dès le premier palier
				expect(BN.abbreviate(12.3 * 10 ^ (3 * i), "en")).toBe("12.3" .. suffix)
				expect(BN.abbreviate(12.3 * 10 ^ (3 * i), "fr")).toBe("12,3" .. fr[i])
				-- bornes de chaque palier : 1,00 au début, 999 tronqué à la fin (jamais « 1000 » ni le suivant)
				-- (le palier K commence à 10 000 : « 1,000 » reste un entier)
				if i > 1 then
					expect(BN.abbreviate(10 ^ (3 * i), "en")).toBe("1.00" .. suffix)
				end
				expect(BN.abbreviate(999.9 * 10 ^ (3 * i), "en")).toBe("999" .. suffix)
			end
			-- la liste rendue est une copie
			en[1] = "x"
			expect(BN.suffixes("en")[1]).toBe("K")
			expect(BN.suffixes(nil)[1]).toBe("K")
		end)

		it("au-delà de Tg (dès 1e96) : notation scientifique jusqu'à 1e300 et au-delà", function()
			expect(BN.abbreviate(9.99e35, "en")).toBe("999Dc")
			expect(BN.abbreviate(1.234e45, "en")).toBe("1.23Qad")
			expect(BN.abbreviate(1e93, "en")).toBe("1.00Tg")
			expect(BN.abbreviate(1e93, "fr")).toBe("1,00Tg")
			expect(BN.abbreviate(9.99e95, "en")).toBe("999Tg")
			expect(BN.abbreviate(9.999999999999999e95, "en")).toBe("1.00e96") -- arrondi du format : jamais « 1000Tg »
			expect(BN.abbreviate(1e96, "en")).toBe("1.00e96")
			expect(BN.abbreviate(1.234e96, "fr")).toBe("1,23e96")
			expect(BN.abbreviate(1e300, "fr")).toBe("1,00e300")
			expect(BN.abbreviate(1.7e308, "en")).toBe("1.70e308")
		end)

		it(
			"entrées bizarres : NaN → 0, ±inf → plafond affiché (1e300), −0 → 0, négatifs signés",
			function()
				expect(BN.abbreviate(0 / 0, "en")).toBe("0")
				-- v1.3 : « ∞ », absent des deux polices (INT-V2-GLYPHS d) ; le plafond garde l'ordre (inf ≥ 1e300)
				expect(BN.abbreviate(math.huge, "en")).toBe("1.00e300")
				expect(BN.abbreviate(-math.huge, "fr")).toBe("-1,00e300")
				expect(BN.abbreviate(-0.0, "en")).toBe("0")
				expect(BN.abbreviate(-12345, "en")).toBe("-12.3K")
				expect(BN.abbreviate(-0.5, "en")).toBe("0")
				expect(BN.abbreviate(nil, "en")).toBe("0")
				expect(BN.abbreviate("12" :: any, "en")).toBe("0")
			end
		)

		it("full : entier exact avec séparateurs sous 1e15, sinon abrégé", function()
			expect(BN.full(123456789012345, "en")).toBe("123,456,789,012,345")
			expect(BN.full(1234567, "fr")).toBe("1" .. SP .. "234" .. SP .. "567")
			expect(BN.full(9876, "fr")).toBe("9876")
			expect(BN.full(12345, "fr")).toBe("12" .. SP .. "345")
			expect(BN.full(999.9, "en")).toBe("999")
			expect(BN.full(1e15, "en")).toBe("1.00Qa")
			expect(BN.full(0 / 0, "en")).toBe("0")
			expect(BN.full(math.huge, "en")).toBe("1.00e300")
			expect(BN.full(-1234, "en")).toBe("-1,234")
		end)

		it("words : forme courte et mot entier, table FR du GDD §4.2 (pluriel français dès 2)", function()
			local short, words = BN.words(7.8e12, "fr")
			expect(short).toBe("7,80T")
			-- GDD §4.2 : « 7,80 T = 7 800 milliards » (sans espace insécable : « 7,80T = 7800 milliards »)
			expect(words).toBe("7800 milliards")
			local s2, w2 = BN.words(7.8e12, "en")
			expect(s2).toBe("7.80T")
			expect(w2).toBe("7.80 trillion")
			expect(select(2, BN.words(1e12, "fr"))).toBe("1000 milliards")
			expect(select(2, BN.words(12.3e12, "fr"))).toBe("12" .. SP .. "300 milliards")
			expect(select(2, BN.words(456e12, "fr"))).toBe("456" .. SP .. "000 milliards")
			expect(select(2, BN.words(1.5e15, "fr"))).toBe("1,50 million de milliards")
			expect(select(2, BN.words(7.8e15, "fr"))).toBe("7,80 millions de milliards")
			expect(select(2, BN.words(1e18, "fr"))).toBe("1,00 milliard de milliards")
			expect(select(2, BN.words(7.8e18, "fr"))).toBe("7,80 milliards de milliards")
			expect(select(2, BN.words(2.5e21, "fr"))).toBe("2,50 trilliards")
			expect(select(2, BN.words(1.5e9, "fr"))).toBe("1,50 milliard")
			expect(select(2, BN.words(4.56e9, "fr"))).toBe("4,56 milliards")
			expect(select(2, BN.words(2e6, "fr"))).toBe("2,00 millions")
			expect(select(2, BN.words(12345, "fr"))).toBe("12,3 mille")
			expect(select(2, BN.words(-7.8e12, "fr"))).toBe("-7800 milliards")
			expect(select(2, BN.words(9876, "en"))).toBe("9,876")
			-- palier sans clé de mot (au-delà de Dc, note INT-A1-WORDS) : la forme courte, jamais un mot vide
			expect(select(2, BN.words(1e40, "en"))).toBe("10.0Dd")
			expect(select(2, BN.words(4.56e92, "fr"))).toBe("456Nvvg")
			expect(select(2, BN.words(1e97, "en"))).toBe("1.00e97")
			expect(select(2, BN.words(math.huge, "fr"))).toBe("1,00e300")
			expect(select(2, BN.words(0 / 0, "en"))).toBe("0")
		end)

		it("words : chaque mot vient des clés num.name.<p> (EN et FR)", function()
			for p = 3, 33, 3 do
				expect(Strings.en["num.name." .. p] ~= nil).toBe(true)
				expect(Strings.fr["num.name." .. p] ~= nil).toBe(true)
				local _, en = BN.words(30 * 10 ^ p, "en")
				expect(string.find(en, Strings.en["num.name." .. p], 1, true) ~= nil).toBe(true)
				-- FR au singulier (1,50) : le mot de la table, sauf 1e12 dit en milliards (« 1 500 milliards »)
				local _, fr = BN.words((if p == 3 then 15 else 1.5) * 10 ^ p, "fr")
				local word = if p == 12 then Strings.fr["num.name.9"] else Strings.fr["num.name." .. p]
				expect({ p = p, found = string.find(fr, word, 1, true) ~= nil }).toEqual({
					p = p,
					found = true,
				})
			end
			-- table du GDD §4.2
			expect(Strings.fr["num.name.12"]).toBe("mille milliards")
			expect(Strings.fr["num.name.15"]).toBe("million de milliards")
			expect(Strings.fr["num.name.18"]).toBe("milliard de milliards")
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
