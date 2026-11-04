--!nocheck
-- Format (lot B1, docs/04 §27.7 ; GDD v2.0 §10.7.6, §10.7.7, §10.8 règle 8) : UN formateur par sorte de
-- nombre de l'interface, valeurs exactes du GDD dans les deux langues, valeurs hostiles (NaN, ±inf,
-- négatifs, énormes, autre type) sans erreur ni « nan » / « inf » / « ∞ » à l'écran, deux niveaux
-- voisins toujours deux textes différents, chaque caractère de chaque sortie dans la table cmap des
-- deux polices (règle 18 : aucune espace insécable U+00A0 / U+202F, absentes de FredokaOne), et
-- même texte que les anciens formateurs du jeu de base qu'il remplace (horloge du HUD, heure du
-- panneau Diagnostics, durée d'absence, chiffres romains du titre du spectacle).
local Props = require("../harness/Props")
local FontCmap = require("../harness/FontCmap")
local Format = require("../../src/client/UI/Format")

local NAN = 0 / 0
local INF = math.huge

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function eq(got, want, what)
		if got ~= want then
			error(string.format("%s : « %s » au lieu de « %s »", what, tostring(got), tostring(want)), 2)
		end
	end

	describe("Format › valeurs exactes du GDD v2.0 (§10.7.7), EN et FR", function()
		it("multiplier : « ×1,175 » (3 décimales), « ×14 » (entier), virgule en français", function()
			eq(Format.multiplier(1.175, "fr"), "×1,175", "Gants FR")
			eq(Format.multiplier(1.175, "en"), "×1.175", "Gants EN")
			eq(Format.multiplier(1.15, "fr", 3), "×1,150", "Gants niveau 6, zéro final gardé")
			eq(Format.multiplier(1.975, "fr", 3), "×1,975", "Pressions ×1,975")
			eq(Format.multiplier(2, "fr", 3), "×2,000", "Pressions → ×2,000")
			eq(Format.multiplier(14, "fr"), "×14", "Croissance ×14")
			eq(Format.multiplier(13, "en"), "×13", "Growth ×13")
			eq(Format.multiplier(1.5, "fr", 1), "×1,5", "une décimale")
			eq(Format.multiplier(123.456, "fr"), "×123,46", "5 chiffres en tout")
			eq(Format.multiplier(1234.5, "en"), "×1234.5", "5 chiffres en tout (EN)")
			eq(Format.multiplier(math.huge, "fr"), "×99999", "plafond affiché")
			eq(
				Format.multiplier(500, "fr", 3),
				"×99,999",
				"décimales imposées : plafond de la place réservée"
			)
		end)

		it(
			"percent : « +5 % » (FR, espace ordinaire), « +5% » (EN), entier ; décimales sur demande",
			function()
				eq(Format.percent(5, "fr"), "+5 %", "FR")
				eq(Format.percent(5, "en"), "+5%", "EN")
				eq(Format.percent(3, "fr"), "+3 %", "Monuments 3")
				eq(Format.percent(4, "fr"), "+4 %", "Monuments 4")
				eq(Format.percent(0, "fr"), "0 %", "zéro sans signe")
				eq(Format.percent(0, "en"), "0%", "zéro sans signe EN")
				eq(Format.percent(-3, "en"), "-3%", "négatif, « - » ASCII (C10)")
				eq(Format.percent(1.2, "fr", 1), "+1,2 %", "Revenu total +1,2 %")
				eq(Format.percent(12.5, "fr", 1), "+12,5 %", "Revenu total +12,5 %")
				eq(Format.percent(12.5, "en", 1), "+12.5%", "Total income +12.5%")
				eq(Format.percent(4.6, "fr"), "+5 %", "arrondi au plus proche")
				eq(Format.percent(-0.0001, "fr", 1), "0,0 %", "jamais « -0,0 % »")
				eq(Format.percent(math.huge, "fr"), "+9999 %", "plafond entier")
				eq(Format.percent(math.huge, "fr", 1), "+999,9 %", "plafond à 1 décimale")
			end
		)

		it("seconds : « 9,0 s » / « 9.0 s » (1 décimale), jamais négatif", function()
			eq(Format.seconds(9, "fr"), "9,0 s", "Aide 9,0 s")
			eq(Format.seconds(9.3, "fr"), "9,3 s", "Aide 9,3 s")
			eq(Format.seconds(9.3, "en"), "9.3 s", "Helper 9.3 s")
			eq(Format.seconds(9.25, "fr"), "9,3 s", "arrondi au plus proche (moitié vers le haut)")
			eq(Format.seconds(0.04, "en"), "0.0 s", "presque zéro")
			eq(Format.seconds(-1, "fr"), "0,0 s", "négatif → 0")
		end)

		it("level : « 12/20 », « 40/40 » ; deux entiers de 0 à 99", function()
			eq(Format.level(12, 20), "12/20", "Tapis")
			eq(Format.level(40, 40), "40/40", "Gants au maximum")
			eq(Format.level(1, 1), "1/1", "Lit douillet")
			eq(Format.level(0, 18), "0/18", "Décorations à 0")
			eq(Format.level(12.9, 20.2), "12/20", "parties entières")
			eq(Format.level(-1, 5), "0/5", "négatif → 0")
			eq(Format.level(150, 400), "99/99", "plafond affiché")
		end)

		it(
			"confetti : entier brut groupé jusqu'à « 99 999 », puis BigNumber.abbreviate (GDD §4.2)",
			function()
				eq(Format.confetti(0, "fr"), "0", "zéro")
				eq(Format.confetti(139, "fr"), "139", "témoin de migration")
				eq(Format.confetti(999, "en"), "999", "999")
				eq(Format.confetti(1000, "en"), "1,000", "EN : virgule des milliers")
				eq(Format.confetti(1000, "fr"), "1 000", "FR : espace ordinaire des milliers")
				eq(Format.confetti(99999, "fr"), "99 999", "plus grand entier brut (FR)")
				eq(Format.confetti(99999, "en"), "99,999", "plus grand entier brut (EN)")
				-- relecture B1 (B1-18) : au-delà de 99 999, le formateur des montants (suffixe collé en
				-- français, A1-18) ; plus de plafond « 999 K » faux de 1 000 000 à 1e9 (borne du schéma)
				eq(Format.confetti(100000, "fr"), "100K", "100 000 → 100K (BigNumber, suffixe collé)")
				eq(Format.confetti(100000, "en"), "100K", "100 000 → 100K")
				eq(Format.confetti(123456.7, "en"), "123K", "milliers tronqués")
				eq(Format.confetti(999999, "fr"), "999K", "999 999 → 999K (tronqué)")
				eq(Format.confetti(1500000, "fr"), "1,50M", "1 500 000 → 1,50M (jamais « 999 K »)")
				eq(Format.confetti(1e9, "en"), "1.00B", "borne du schéma")
				eq(Format.confetti(1e12, "en"), "1.00B", "au-delà : plafond de la borne du schéma")
				eq(Format.confetti(12.9, "fr"), "12", "partie entière")
			end
		)

		it("roman : décor seulement (I à MMMCMXCIX), « » sous 1", function()
			local cases = {
				{ 1, "I" },
				{ 4, "IV" },
				{ 9, "IX" },
				{ 12, "XII" },
				{ 14, "XIV" },
				{ 28, "XXVIII" },
				{ 40, "XL" },
				{ 49, "XLIX" },
				{ 99, "XCIX" },
				{ 400, "CD" },
				{ 1994, "MCMXCIV" },
				{ 3999, "MMMCMXCIX" },
				{ 0, "" },
				{ -5, "" },
				{ 12.7, "XII" },
				{ 5000, "MMMCMXCIX" },
			}
			for _, c in cases do
				eq(Format.roman(c[1]), c[2], "roman(" .. tostring(c[1]) .. ")")
			end
		end)

		it("count, decimal, id, key : petits compteurs, variables des clés, identifiants", function()
			eq(Format.count(3), "3", "count")
			eq(Format.count(12.7), "12", "count : partie entière")
			eq(Format.count(-2), "0", "count : jamais négatif")
			eq(Format.decimal(1.25, "fr", 1), "1,3", "decimal 1 décimale")
			eq(Format.decimal(1.5, "fr"), "1,5", "decimal sans décimales imposées")
			eq(Format.decimal(2, "fr"), "2", "decimal entier")
			eq(Format.decimal(1.25, "en"), "1.25", "decimal EN")
			eq(Format.decimal(52, "fr", 1), "52,0", "chance du Guide « 52,0 »")
			eq(Format.decimal(0.0001, "fr", 4), "0,0001", "4 décimales")
			eq(Format.decimal(-1.5, "en"), "-1.5", "négatif")
			eq(Format.decimal(-0.0004, "en"), "0", "jamais « -0 »")
			eq(Format.id(42), "42", "id")
			eq(Format.id(-3), "-3", "id négatif")
			eq(Format.id(2.7), "2", "id : partie entière")
			eq(Format.key("a", 3, true, nil, 1.5), "a|3|true|nil|1500m", "clé de cache")
		end)

		it("clock, timeOfDay, hoursMinutes : horloges et durées", function()
			eq(Format.clock(75), "1:15", "m:ss")
			eq(Format.clock(3725), "1:02:05", "h:mm:ss")
			eq(Format.clock(0), "0:00", "zéro")
			eq(Format.clock(59.2), "1:00", "arrondi à la seconde supérieure")
			eq(Format.clock(1e9), "99:59:59", "plafond")
			eq(Format.timeOfDay(0), "00:00:00", "minuit")
			eq(Format.timeOfDay(3661), "01:01:01", "01:01:01")
			eq(Format.timeOfDay(86399), "23:59:59", "23:59:59")
			eq(Format.timeOfDay(86400 * 20000 + 45296), "12:34:56", "un instant Unix")
			eq(Format.hoursMinutes(18720, "fr"), "5 h 12", "5 h 12 (GDD §7.2)")
			eq(Format.hoursMinutes(3600, "en"), "1 h 00", "1 h 00")
		end)
	end)

	describe(
		"Format › valeurs hostiles : jamais d'erreur ni « nan », « inf », « ∞ » à l'écran",
		function()
			local FORMATTERS = {
				multiplier = function(x, lang)
					return Format.multiplier(x, lang)
				end,
				multiplier3 = function(x, lang)
					return Format.multiplier(x, lang, 3)
				end,
				percent = function(x, lang)
					return Format.percent(x, lang)
				end,
				percent1 = function(x, lang)
					return Format.percent(x, lang, 1)
				end,
				seconds = function(x, lang)
					return Format.seconds(x, lang)
				end,
				level = function(x)
					return Format.level(x, x)
				end,
				confetti = function(x, lang)
					return Format.confetti(x, lang)
				end,
				roman = function(x)
					return Format.roman(x)
				end,
				count = function(x)
					return Format.count(x)
				end,
				decimal = function(x, lang)
					return Format.decimal(x, lang)
				end,
				decimal2 = function(x, lang)
					return Format.decimal(x, lang, 2)
				end,
				clock = function(x)
					return Format.clock(x)
				end,
				timeOfDay = function(x)
					return Format.timeOfDay(x)
				end,
				hoursMinutes = function(x, lang)
					return Format.hoursMinutes(x, lang)
				end,
				id = function(x)
					return Format.id(x)
				end,
			}

			it("NaN, ±inf, −0, énormes, chaînes et nil : un texte court, sûr, sans erreur", function()
				local hostile =
					{ NAN, INF, -INF, -0, 1e308, -1e308, 2 ^ 63, -(2 ^ 63), 1e-320, "12", {}, true }
				for name, fn in FORMATTERS do
					for _, lang in { "en", "fr", "de" } do
						for i = 0, #hostile do
							local v = hostile[i] -- hostile[0] : nil
							local ok, s = pcall(fn, v, lang)
							if not ok then
								error(
									string.format("%s(%s) a levé : %s", name, Props.format(v), tostring(s))
								)
							end
							expect(type(s)).toBe("string")
							local low = string.lower(s)
							if string.find(low, "nan", 1, true) or string.find(low, "inf", 1, true) then
								error(string.format("%s(%s) → « %s »", name, Props.format(v), s))
							end
							expect(string.find(s, "∞", 1, true)).toBe(nil)
							expect(#s <= 24).toBe(true)
							expect(s ~= "-0").toBe(true)
						end
					end
				end
			end)

			it(
				"6 000 nombres quelconques par formateur : jamais d'erreur, toujours de l'UTF-8 valide",
				function()
					for name, fn in FORMATTERS do
						local ok, err = pcall(
							Props.check,
							6000,
							Props.tuple(Props.anyNumber(), Props.oneOf({ "en", "fr" })),
							function(v)
								local s = fn(v[1], v[2])
								return type(s) == "string" and utf8.len(s) ~= nil and #s <= 24
							end
						)
						if not ok then
							error(name .. " : " .. tostring(err), 0)
						end
					end
				end
			)
		end
	)

	describe("Format › règle 8 : un niveau de plus = un texte différent (GDD §10.8)", function()
		it("Gants 0 à 40 : ×1,000 … ×2,000, 41 textes tous différents, dans l'ordre", function()
			local seen = {}
			for lang in { en = true, fr = true } do
				table.clear(seen)
				local prev = nil
				for k = 0, 40 do
					local s = Format.multiplier(1 + 0.025 * k, lang, 3)
					expect(seen[s]).toBe(nil)
					seen[s] = true
					if prev then
						expect(s ~= prev).toBe(true)
					end
					prev = s
				end
				eq(
					Format.multiplier(1 + 0.025 * 40, lang, 3),
					if lang == "fr" then "×2,000" else "×2.000",
					"Gants 40"
				)
				eq(
					Format.multiplier(1 + 0.025 * 39, lang, 3),
					if lang == "fr" then "×1,975" else "×1.975",
					"Gants 39"
				)
			end
		end)

		it(
			"croissance ×1 à ×99, monuments +0 à +10 %, niveaux 0 à 40, Confettis 0 à 99 999 : voisins distincts",
			function()
				for _, lang in { "en", "fr" } do
					for g = 1, 98 do
						expect(Format.multiplier(g, lang) ~= Format.multiplier(g + 1, lang)).toBe(true)
					end
					for m = 0, 9 do
						expect(Format.percent(m, lang) ~= Format.percent(m + 1, lang)).toBe(true)
					end
					for n = 0, 99998, 7 do
						expect(Format.confetti(n, lang) ~= Format.confetti(n + 1, lang)).toBe(true)
					end
					-- école des Plopettes : intervalles au dixième de seconde
					for t = 0, 199 do
						expect(Format.seconds(t / 10, lang) ~= Format.seconds((t + 1) / 10, lang)).toBe(true)
					end
				end
				for a = 0, 39 do
					expect(Format.level(a, 40) ~= Format.level(a + 1, 40)).toBe(true)
				end
				local romans = {}
				for n = 1, 3999 do
					local r = Format.roman(n)
					expect(romans[r]).toBe(nil)
					romans[r] = true
				end
			end
		)

		it("pur et déterministe : même entrée, même texte (carte, ligne et bandeau)", function()
			local rng = Props.rng(20261103)
			for _ = 1, 2000 do
				local x = rng.range(-10, 1e6)
				local lang = if rng.chance(0.5) then "fr" else "en"
				expect(Format.multiplier(x, lang, 3)).toBe(Format.multiplier(x, lang, 3))
				expect(Format.percent(x, lang)).toBe(Format.percent(x, lang))
				expect(Format.confetti(x, lang)).toBe(Format.confetti(x, lang))
			end
		end)
	end)

	describe(
		"Format › règle 18 : chaque caractère dans la cmap de FredokaOne et de LuckiestGuy",
		function()
			it(
				"toutes les sorties, EN et FR, de 0 à 1e12 et valeurs hostiles : aucun caractère hors police",
				function()
					local cmaps = FontCmap.load()
					local values = { NAN, INF, -INF, -1, -0.5, 0, 0.0001, 0.5, 1, 1.175, 9.25, 99.999 }
					local x = 1
					while x < 1e12 do
						table.insert(values, x)
						table.insert(values, x * 1.234567)
						x *= 7
					end
					local bad = {}
					local function check(name, s)
						local missing = FontCmap.missing(cmaps, s)
						if #missing > 0 and #bad < 10 then
							table.insert(bad, name .. " « " .. s .. " » : " .. table.concat(missing, ", "))
						end
					end
					for _, lang in { "en", "fr" } do
						for _, v in values do
							check("multiplier", Format.multiplier(v, lang))
							check("multiplier3", Format.multiplier(v, lang, 3))
							check("percent", Format.percent(v, lang, 1))
							check("seconds", Format.seconds(v, lang))
							check("level", Format.level(v, v))
							check("confetti", Format.confetti(v, lang))
							check("roman", Format.roman(v))
							check("count", Format.count(v))
							check("decimal", Format.decimal(v, lang))
							check("clock", Format.clock(v))
							check("timeOfDay", Format.timeOfDay(v))
							check("hoursMinutes", Format.hoursMinutes(v, lang))
						end
					end
					if #bad > 0 then
						error(table.concat(bad, "\n"), 0)
					end
					-- jamais d'espace insécable : la seule espace des deux polices est U+0020
					expect(string.find(Format.confetti(12345, "fr"), "\194\160", 1, true)).toBe(nil)
					expect(string.find(Format.percent(5, "fr"), "\226\128\175", 1, true)).toBe(nil)
				end
			)
		end
	)

	describe("Format › même texte que les formateurs du jeu de base qu'il remplace", function()
		-- anciennes implémentations (HUD : Util.clock ; Diagnostics : hhmm ; écran de retour : « %d h
		-- %02d » ; titre du spectacle : chiffres romains de VFXController, 1 à 99)
		local function oldClock(seconds)
			local s = math.max(0, math.ceil(math.clamp(seconds, 0, 359999)))
			local h = s // 3600
			local m = (s % 3600) // 60
			local r = s % 60
			if h > 0 then
				return string.format("%d:%02d:%02d", h, m, r)
			end
			return string.format("%d:%02d", m, r)
		end
		local function oldTime(unix)
			local s = math.floor(unix) % 86400
			return string.format("%02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
		end
		local function oldAway(seconds)
			local s = math.floor(seconds)
			return string.format("%d h %02d", s // 3600, (s % 3600) // 60)
		end
		local function oldRoman(n)
			local values = { 10, 9, 5, 4, 1 }
			local symbols = { "X", "IX", "V", "IV", "I" }
			local out = ""
			local v = math.clamp(math.floor(n), 1, 99)
			for i, value in values do
				while v >= value do
					out ..= symbols[i]
					v -= value
				end
			end
			return out
		end

		it("horloge du HUD, heure de Diagnostics, durée d'absence : 5 000 valeurs identiques", function()
			local rng = Props.rng(20261104)
			for _ = 1, 5000 do
				local s = rng.range(0, 400000)
				eq(Format.clock(s), oldClock(s), "clock(" .. s .. ")")
				local unix = rng.range(0, 2e9)
				eq(Format.timeOfDay(unix), oldTime(unix), "timeOfDay(" .. unix .. ")")
				local away = rng.range(3600, 9999 * 3600)
				eq(Format.hoursMinutes(away, "fr"), oldAway(away), "hoursMinutes(" .. away .. ")")
			end
		end)

		it("chiffres romains du titre du spectacle : identiques de I à XXXIX, corrigés au-delà", function()
			for n = 1, 39 do
				eq(Format.roman(n), oldRoman(n), "roman(" .. n .. ")")
			end
			-- l'ancien titre n'avait ni L, ni XL, ni XC : « GRAND SPLORCH XXXX » au 40e (défaut du jeu
			-- de base trouvé par cette spec) ; jamais 4 fois le même chiffre
			eq(oldRoman(40), "XXXX", "ancien titre du 40e Grand Splorch")
			eq(Format.roman(40), "XL", "40e")
			eq(Format.roman(50), "L", "50e")
			eq(Format.roman(90), "XC", "90e")
			for n = 1, 3999 do
				local r = Format.roman(n)
				for _, four in { "IIII", "XXXX", "CCCC", "MMMM", "VV", "LL", "DD" } do
					if string.find(r, four, 1, true) then
						error(string.format("roman(%d) = « %s »", n, r))
					end
				end
			end
		end)

		it(
			"identifiants : Format.id = tostring pour tout entier de ±1e12 (clés « objective.12 »)",
			function()
				local rng = Props.rng(20261105)
				for _ = 1, 5000 do
					local n = rng.int(-1e12, 1e12)
					eq(Format.id(n), tostring(n), "id(" .. n .. ")")
				end
			end
		)
	end)
end
