--!nocheck
-- Props_BigNumber (paquet logic, docs/04 §17.1 couche a) : propriétés de l'affichage des nombres.
-- GDD v2.0 §4.2 (lot A1) : 31 suffixes (K … Tg, 1e93), notation e dès 1e96, jamais « 1000 » devant
-- un suffixe, jamais d'espace insécable ni « ∞ » (absents de FredokaOne et LuckiestGuy), aucune
-- espace dans une forme courte (un montant ne se coupe jamais sur deux lignes).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local BN = h:require("ReplicatedStorage.Shared.Logic.BigNumber")
	local DiagRules = h:require("ReplicatedStorage.Shared.Logic.DiagRules")

	local langs = Props.oneOf({ "en", "fr", "auto", nil })

	-- valeur numérique de l'affichage EN (« 12.3K » → 12300) pour la monotonie
	local SUFFIX = {}
	for i, suffix in BN.suffixes("en") do
		SUFFIX[suffix] = 3 * i
	end
	local function value(text: string): number
		text = string.gsub(text, ",", "")
		local mant, exp = string.match(text, "^([%d%.]+)e(%d+)$")
		if mant then
			return tonumber(mant) * 10 ^ tonumber(exp)
		end
		local num, suf = string.match(text, "^([%d%.]+)(%a*)$")
		assert(suf == "" or SUFFIX[suf], "suffixe inconnu : " .. tostring(suf))
		return tonumber(num) * 10 ^ (SUFFIX[suf] or 0)
	end
	-- forme courte bien formée : entier sous 10 000, sinon 3 chiffres significatifs (jamais « 1000 »)
	-- et un suffixe connu, ou « d.dde<n> » ; signe « - » ASCII seulement
	local function wellFormed(text: string, lang: string?): boolean
		local body = string.gsub(text, "^%-", "")
		local mark = if lang == "fr" then "," else "%."
		if string.match(body, "^%d+$") or (lang ~= "fr" and string.match(body, "^%d,%d%d%d$")) then
			return true
		end
		local mant, exp = string.match(body, "^(%d" .. mark .. "%d%d)e(%d+)$")
		if mant then
			return tonumber(exp) >= 96
		end
		local num, suf = string.match(body, "^([%d%.,]+)(%a+)$")
		if num == nil or SUFFIX[suf] == nil then
			return false
		end
		local digits = string.gsub(num, "[%.,]", "")
		return #digits == 3
			and string.sub(digits, 1, 1) ~= "0"
			and (#num == 3 or string.find(num, mark) ~= nil)
	end

	describe("Props › BigNumber", function()
		it("abbreviate : chaîne UTF-8 courte (≤ 12 octets), jamais d'erreur, pour tout nombre", function()
			Props.check(6000, Props.tuple(Props.anyNumber(), langs), function(v)
				local s = BN.abbreviate(v[1], v[2])
				return type(s) == "string" and #s > 0 and #s <= 12 and DiagRules.validUtf8(s)
			end)
		end)

		it("abbreviate : jamais « nan », « inf » ni « -0 » à l'écran", function()
			Props.check(4000, Props.tuple(Props.anyNumber(), langs), function(v)
				local s = BN.abbreviate(v[1], v[2])
				return not string.find(string.lower(s), "nan", 1, true)
					and not string.find(string.lower(s), "inf", 1, true)
					and s ~= "-0"
			end)
		end)

		it(
			"abbreviate : tronqué (affiché ≤ valeur) et à moins de 1 % sous la valeur dès 10 000",
			function()
				Props.check(5000, Props.number(10000, 1e300), function(x)
					local shown = value(BN.abbreviate(x, "en"))
					return shown <= x * (1 + 1e-12) and shown >= x * 0.99 * (1 - 1e-12)
				end)
			end
		)

		it(
			"abbreviate : monotone (x ≤ y ⇒ affiché(x) ≤ affiché(y)), de 0 à 1e300 et +inf",
			function()
				Props.check(5000, Props.tuple(Props.number(0, 1e300), Props.number(0, 1e300)), function(v)
					local a, b = math.min(v[1], v[2]), math.max(v[1], v[2])
					return value(BN.abbreviate(a, "en")) <= value(BN.abbreviate(b, "en"))
						and value(BN.abbreviate(b, "en")) <= value(BN.abbreviate(math.huge, "en"))
				end)
			end
		)

		it(
			"abbreviate : bien formé, jamais « 1000 » devant un suffixe, palier exact (suffixe ou e dès 1e96)",
			function()
				-- tirages larges, et bords de chaque palier 10^(3k) × (1 ± quelques ulp)
				local values = {}
				for k = 1, 100 do
					local edge = 10 ^ (3 * k)
					for _, f in { 1 - 3e-16, 1 - 1e-15, 1 - 1e-12, 1, 1 + 1e-15, 0.9999 } do
						table.insert(values, edge * f)
					end
				end
				for _, x in values do
					for _, lang in { "en", "fr" } do
						local s = BN.abbreviate(x, lang)
						expect({ x = x, lang = lang, s = s, ok = wellFormed(s, lang) }).toEqual({
							x = x,
							lang = lang,
							s = s,
							ok = true,
						})
					end
				end
				Props.check(6000, Props.tuple(Props.number(0, 1e300), langs), function(v)
					local x = v[1]
					local s = BN.abbreviate(x, v[2])
					if not wellFormed(s, v[2]) then
						return false
					end
					local en = BN.abbreviate(x, "en")
					local suf = string.match(en, "%a+$")
					if x < 10000 or string.match(en, "e%d+$") then
						-- e seulement dès 1e96 (ou un arrondi du format qui y mène)
						return x < 10000 or x >= 1e96 * (1 - 1e-14)
					end
					-- le suffixe est celui du palier de la valeur affichée (1 ≤ mantisse < 1000)
					local mant = value(en) / 10 ^ SUFFIX[suf]
					return mant >= 1 - 1e-12 and mant < 1000 and x < 1e96
				end)
			end
		)

		it("abbreviate : bornes 1e93 (Tg) et 1e96 (notation e), 1e300, ±inf, −0, NaN", function()
			for _, lang in { "en", "fr" } do
				local m = if lang == "fr" then "," else "."
				expect(BN.abbreviate(1e93, lang)).toBe("1" .. m .. "00Tg")
				expect(BN.abbreviate(9.99e95, lang)).toBe("999Tg")
				expect(BN.abbreviate(1e96, lang)).toBe("1" .. m .. "00e96")
				expect(BN.abbreviate(1e300, lang)).toBe("1" .. m .. "00e300")
				expect(BN.abbreviate(math.huge, lang)).toBe("1" .. m .. "00e300")
				expect(BN.abbreviate(-math.huge, lang)).toBe("-1" .. m .. "00e300")
				expect(BN.abbreviate(-0.0, lang)).toBe("0")
				expect(BN.abbreviate(0 / 0, lang)).toBe("0")
				expect(BN.full(math.huge, lang)).toBe(BN.abbreviate(1e300, lang))
				expect(BN.full(-0.0, lang)).toBe("0")
				expect((BN.words(math.huge, lang))).toBe(BN.abbreviate(1e300, lang))
			end
		end)

		it("aucune espace insécable ni « ∞ » ; aucune espace dans une forme courte", function()
			local banned = { "\226\128\175", "\194\160", "∞" }
			Props.check(5000, Props.tuple(Props.anyNumber(), langs), function(v)
				local short = BN.abbreviate(v[1], v[2])
				local a, b = BN.words(v[1], v[2])
				local full = BN.full(v[1], v[2])
				for _, text in { short, a, b, full } do
					for _, ch in banned do
						if string.find(text, ch, 1, true) then
							return false
						end
					end
				end
				return string.find(short, "%s") == nil and string.find(a, "%s") == nil
			end)
		end)

		it("EN et FR donnent les mêmes chiffres", function()
			Props.check(3000, Props.number(0, 1e40), function(x)
				local en = BN.abbreviate(x, "en")
				local fr = BN.abbreviate(x, "fr")
				local digitsEn = string.gsub(string.match(en, "^[%d%.,]+") or "", "[%.,]", "")
				local digitsFr = string.gsub(string.match(fr, "^[%d,]+") or "", ",", "")
				-- même suffixe dans les deux langues
				local sameSuffix = string.match(en, "%a*$") == string.match(fr, "%a*$")
				return (digitsEn == digitsFr and sameSuffix) or x < 10000
			end)
		end)

		it("full : entier exact (relu = floor(x)) sous 1e15", function()
			Props.check(4000, Props.number(0, 999999999999999), function(x)
				local s = string.gsub(BN.full(x, "en"), ",", "")
				return tonumber(s) == math.floor(x)
			end)
		end)

		it("words et milestoneKey : jamais d'erreur", function()
			Props.check(4000, Props.tuple(Props.anyNumber(), langs), function(v)
				local a, b = BN.words(v[1], v[2])
				local key = BN.milestoneKey(v[1])
				return type(a) == "string" and type(b) == "string" and (key == nil or type(key) == "string")
			end)
		end)

		it("entrées qui ne sont pas des nombres : « 0 »", function()
			Props.check(1000, Props.any(), function(v)
				if type(v) == "number" then
					return true
				end
				return BN.abbreviate(v, "en") == "0" and BN.full(v, "fr") == "0"
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
