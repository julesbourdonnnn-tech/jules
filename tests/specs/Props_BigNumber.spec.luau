--!nocheck
-- Props_BigNumber (paquet logic, docs/04 §17.1 couche a) : propriétés de l'affichage des nombres.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local BN = h:require("ReplicatedStorage.Shared.Logic.BigNumber")
	local DiagRules = h:require("ReplicatedStorage.Shared.Logic.DiagRules")

	local langs = Props.oneOf({ "en", "fr", "auto", nil })

	-- valeur numérique de l'affichage EN (« 12.3K » → 12300) pour la monotonie
	local SUFFIX =
		{ K = 3, M = 6, B = 9, T = 12, Qa = 15, Qi = 18, Sx = 21, Sp = 24, Oc = 27, No = 30, Dc = 33 }
	local function value(text: string): number
		text = string.gsub(text, ",", "")
		local mant, exp = string.match(text, "^([%d%.]+)e(%d+)$")
		if mant then
			return tonumber(mant) * 10 ^ tonumber(exp)
		end
		local num, suf = string.match(text, "^([%d%.]+)(%a*)$")
		return tonumber(num) * 10 ^ (SUFFIX[suf] or 0)
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

		it("abbreviate : monotone (x ≤ y ⇒ affiché(x) ≤ affiché(y))", function()
			Props.check(5000, Props.tuple(Props.number(0, 1e40), Props.number(0, 1e40)), function(v)
				local a, b = math.min(v[1], v[2]), math.max(v[1], v[2])
				return value(BN.abbreviate(a, "en")) <= value(BN.abbreviate(b, "en"))
			end)
		end)

		it("EN et FR donnent les mêmes chiffres", function()
			Props.check(3000, Props.number(0, 1e40), function(x)
				local en = BN.abbreviate(x, "en")
				local fr = BN.abbreviate(x, "fr")
				local digitsEn = string.gsub(string.match(en, "^[%d%.,]+") or "", "[%.,]", "")
				local digitsFr = string.gsub(string.match(fr, "^[%d,]+") or "", ",", "")
				digitsFr = string.gsub(digitsFr, "\226\128\175", "")
				return digitsEn == digitsFr or x < 10000
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
