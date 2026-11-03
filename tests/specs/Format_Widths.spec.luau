--!nocheck
-- Format_Widths (lot B1, docs/04 §27.8 ; GDD v2.0 §10.8 règle 7, « largeurs réservées ») : pour chaque
-- formateur de UI/Format, 10 000 nombres tirés au hasard (graine fixe : petits entiers, grands
-- nombres sur toute l'échelle, décimaux, négatifs, valeurs hostiles), EN et FR : la largeur mesurée
-- avec les vraies avances de FredokaOne (tests/harness/TextMetrics) à la taille dessinée est au plus
-- la largeur réservée (Format.Reserved, prise sur Config/Layout.Upgrades). Rien ne change de taille
-- quand un nombre grandit : la place est celle de la plus longue valeur formatée.
local Props = require("../harness/Props")
local TextFit = require("../harness/TextFit")
local Format = require("../../src/client/UI/Format")
local Layout = require("../../src/shared/Config/Layout")

local FONT = "FredokaOne@400"
local N = 10000

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	-- nombre au hasard : petits entiers, échelle logarithmique jusqu'à 1e15, décimaux, négatifs,
	-- valeurs hostiles (NaN, ±inf, 1e308)
	local function draw(rng)
		local r = rng.next()
		if r < 0.3 then
			return rng.int(0, 120)
		elseif r < 0.55 then
			return 10 ^ rng.range(0, 15)
		elseif r < 0.75 then
			return rng.range(0, 100000)
		elseif r < 0.85 then
			return -10 ^ rng.range(-3, 6)
		elseif r < 0.95 then
			return rng.range(0, 3) + rng.int(0, 999) / 1000
		end
		return rng.pick({ 0 / 0, math.huge, -math.huge, 1e308, -1e308, 99999, 100000, 999999, 99.95, 9999.95 })
	end

	local KINDS = {
		{
			name = "confetti",
			fn = function(x, lang)
				return Format.confetti(x, lang)
			end,
		},
		{
			name = "level",
			fn = function(x, _lang, y)
				return Format.level(x, y)
			end,
		},
		{
			name = "multiplier",
			fn = function(x, lang)
				return Format.multiplier(x, lang)
			end,
		},
		{
			name = "multiplier",
			label = "multiplier (3 décimales)",
			fn = function(x, lang)
				return Format.multiplier(x, lang, 3)
			end,
		},
		{
			name = "percent",
			fn = function(x, lang)
				return Format.percent(x, lang)
			end,
		},
		{
			name = "percent",
			label = "percent (1 décimale)",
			fn = function(x, lang)
				return Format.percent(x, lang, 1)
			end,
		},
		{
			name = "seconds",
			fn = function(x, lang)
				return Format.seconds(x, lang)
			end,
		},
	}

	describe("Format_Widths › places réservées de Config/Layout.Upgrades", function()
		it("Confettis : place de l'en-tête (200) moins l'icône (48), à 40 px", function()
			local U = Layout.Upgrades
			expect(Format.Reserved.confetti.size).toBe(U.Confetti.text)
			expect(Format.Reserved.confetti.width).toBe(U.Confetti.w - U.Confetti.icon)
		end)
		it("niveau : colonne Niveau d'une ligne (140), à 40 px", function()
			local U = Layout.Upgrades
			expect(Format.Reserved.level.width).toBe(U.Columns.level.w)
			expect(Format.Reserved.level.size).toBe(40)
		end)
		it(
			"avant → après : deux valeurs, le plus long libellé et la flèche dessinée tiennent dans 540 à 32 px",
			function()
				local U = Layout.Upgrades
				local longest = 0
				for _, label in
					{
						"Croissance",
						"Pressions",
						"Pot la nuit :",
						"Déco gardées :",
						"Growth",
						"Presses",
						"Max streak:",
					}
				do
					longest = math.max(longest, TextFit.width(label, FONT, 32))
				end
				local arrow = 48 -- flèche dessinée de 32 px et deux écarts de 8 (règle 18)
				for _, kind in { "multiplier", "percent", "seconds" } do
					local r = Format.Reserved[kind]
					expect(r.size).toBe(32)
					expect(longest + 8 + 2 * r.width + arrow <= U.Columns.text.w).toBe(true)
				end
			end
		)
	end)

	describe(
		"Format_Widths › 10 000 nombres tirés au hasard : largeur mesurée ≤ largeur réservée",
		function()
			for _, kind in KINDS do
				it((kind.label or kind.name) .. ", EN et FR", function()
					local reserved = Format.Reserved[kind.name]
					local rng = Props.rng(20261103)
					local widest, widestText = 0, ""
					for i = 1, N do
						local lang = if i % 2 == 0 then "fr" else "en"
						local text = kind.fn(draw(rng), lang, draw(rng))
						local w = TextFit.width(text, FONT, reserved.size)
						if w > widest then
							widest, widestText = w, text
						end
						if w > reserved.width + 0.01 then
							error(
								string.format(
									"« %s » (%s) mesure %.1f px à %d px pour %d réservés",
									text,
									lang,
									w,
									reserved.size,
									reserved.width
								),
								0
							)
						end
					end
					print(
						string.format(
							"    %s : plus large « %s » = %.1f px / %d",
							kind.label or kind.name,
							widestText,
							widest,
							reserved.width
						)
					)
				end)
			end

			it(
				"plafonds affichés : la plus longue valeur de chaque formateur tient (cas extrêmes nommés)",
				function()
					local cases = {
						{ "confetti", Format.confetti(99999, "fr") },
						{ "confetti", Format.confetti(99999, "en") },
						{ "confetti", Format.confetti(999999, "fr") },
						{ "level", Format.level(99, 99) },
						{ "level", Format.level(40, 40) },
						{ "multiplier", Format.multiplier(math.huge, "fr", 3) },
						{ "multiplier", Format.multiplier(99999, "fr") },
						{ "percent", Format.percent(-math.huge, "fr", 1) },
						{ "percent", Format.percent(math.huge, "en", 1) },
						{ "seconds", Format.seconds(math.huge, "fr") },
					}
					for _, c in cases do
						local r = Format.Reserved[c[1]]
						local w = TextFit.width(c[2], FONT, r.size)
						if w > r.width then
							error(string.format("%s « %s » : %.1f px pour %d", c[1], c[2], w, r.width), 0)
						end
					end
				end
			)
		end
	)
end
