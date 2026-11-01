--!strict
-- BigNumber (paquet logic, docs/04 §12.1). Affichage des nombres géants (GDD §4.2), anglais et
-- français. Remplace Format.abbreviate du socle pour tout nombre du jeu (note INT-FORMAT) :
--   * moins de 10 000 : entier avec séparateur des milliers (EN « , », FR espace fine insécable
--     U+202F) ;
--   * ensuite 3 chiffres significatifs TRONQUÉS, jamais arrondis vers le haut (999 999 → « 999K »),
--     zéro final gardé (« 7.80T ») et suffixe (EN K M B T Qa Qi Sx Sp Oc No Dc ; FR k M Md Bn Bd Tn
--     Td Qn Qd Qt Qtd, virgule décimale, espace fine insécable avant le suffixe) ;
--   * à partir de 1e36 : « 1.23e36 » / « 1,23e36 ».
-- NaN → « 0 », ±inf → « ∞ », −0 → « 0 » : jamais d'erreur (propriétés : Props_BigNumber.spec).
-- Les chiffres viennent de string.format("%.14e") (15 chiffres significatifs : exact pour tout
-- entier < 1e15, et une petite erreur d'arrondi flottant — 4,5599999999999995e9 — s'affiche 4.56B).
-- Les mots entiers (« 7,80 billions ») viennent des clés num.name.<p> de Localization/Strings.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table = type, math, string, table

local Strings = require(script.Parent.Parent.Localization.Strings)

local BigNumber = {}

local NNBSP = "\226\128\175" -- U+202F, espace fine insécable (UTF-8)
local SCIENTIFIC_EXP = 36 -- à partir de 1e36 : notation « 1.23e36 »
local EXACT_BELOW = 1e15 -- full() : entier exact en dessous
local SHORT_FROM = 10000 -- abbreviate() : abrégé à partir de 10 000

local SUFFIXES_EN = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local SUFFIXES_FR = { "k", "M", "Md", "Bn", "Bd", "Tn", "Td", "Qn", "Qd", "Qt", "Qtd" }

-- Jalons des bannières (Events.Banners.RecordThresholds) : puissance → clé de texte
local MILESTONES = { 6, 9, 12, 15 }

local function isFr(lang: string?): boolean
	return lang == "fr"
end

-- Nombre sûr : NaN → 0, −0 → 0 ; ±inf gardés (affichés « ∞ »)
local function sane(n: any): number
	if type(n) ~= "number" or n ~= n then
		return 0
	end
	if n == 0 then
		return 0 -- efface −0
	end
	return n
end

-- Entier positif (déjà tronqué, < 1e15) avec séparateur des milliers
local function groupDigits(int: number, fr: boolean): string
	local s = string.format("%d", int)
	local sep = if fr then NNBSP else ","
	local first = #s % 3
	local parts = {}
	if first > 0 then
		table.insert(parts, string.sub(s, 1, first))
	end
	for i = first + 1, #s, 3 do
		table.insert(parts, string.sub(s, i, i + 2))
	end
	return table.concat(parts, sep)
end

-- Chiffres significatifs et exposant décimal d'un réel fini > 0 : ("456000…", 9)
local function digitsOf(x: number): (string, number)
	local text = string.format("%.14e", x)
	local lead, frac, exponent = string.match(text, "^(%d)%.(%d+)e([%+%-]%d+)$")
	local e = if exponent then tonumber(exponent) else nil
	if lead == nil or frac == nil or e == nil then
		-- format inattendu (ne devrait jamais arriver) : repli sûr
		return "100000000000000", 0
	end
	return lead .. frac, e
end

-- Les 3 premiers chiffres significatifs, avec la virgule après `intDigits` chiffres (1, 2 ou 3)
local function threeDigits(digits: string, intDigits: number, fr: boolean): string
	local d = string.sub(digits, 1, 3)
	if intDigits >= 3 then
		return d
	end
	local mark = if fr then "," else "."
	return string.sub(d, 1, intDigits) .. mark .. string.sub(d, intDigits + 1)
end

-- Forme abrégée d'une valeur absolue finie ≥ 10 000 : (texte du nombre, palier de mille 1 … 11, ou
-- 0 en notation scientifique)
local function shortParts(x: number, fr: boolean): (string, number)
	local digits, e = digitsOf(x)
	if e >= SCIENTIFIC_EXP then
		local mark = if fr then "," else "."
		return string.sub(digits, 1, 1) .. mark .. string.sub(digits, 2, 3) .. "e" .. tostring(e), 0
	end
	if e < 4 then
		e = 4 -- 9999,99… arrondi par le format : reste au palier des milliers
		digits = "100000000000000"
	end
	local tier = e // 3
	local intDigits = e - tier * 3 + 1
	return threeDigits(digits, intDigits, fr), tier
end

-- Forme courte du HUD, des étiquettes et des « +N »
function BigNumber.abbreviate(n: number, lang: string?): string
	local x = sane(n)
	local fr = isFr(lang)
	if x == math.huge or x == -math.huge then
		return "∞"
	end
	local negative = x < 0
	local a = math.abs(x)
	local text
	if a < SHORT_FROM then
		text = groupDigits(math.floor(a), fr)
	else
		local num, tier = shortParts(a, fr)
		if tier == 0 then
			text = num
		elseif fr then
			text = num .. NNBSP .. SUFFIXES_FR[tier]
		else
			text = num .. SUFFIXES_EN[tier]
		end
	end
	if negative and text ~= "0" then
		return "-" .. text
	end
	return text
end

-- Entier exact avec séparateurs sous 1e15, sinon abbreviate
function BigNumber.full(n: number, lang: string?): string
	local x = sane(n)
	if x == math.huge or x == -math.huge then
		return "∞"
	end
	local a = math.abs(x)
	if a >= EXACT_BELOW then
		return BigNumber.abbreviate(x, lang)
	end
	local text = groupDigits(math.floor(a), isFr(lang))
	if x < 0 and text ~= "0" then
		return "-" .. text
	end
	return text
end

-- (forme courte, mot entier « 7,80 billions ») pour la fiche
function BigNumber.words(n: number, lang: string?): (string, string)
	local short = BigNumber.abbreviate(n, lang)
	local x = sane(n)
	if x == math.huge or x == -math.huge then
		return short, short
	end
	local fr = isFr(lang)
	local a = math.abs(x)
	if a < SHORT_FROM then
		return short, BigNumber.full(x, lang)
	end
	local num, tier = shortParts(a, fr)
	if tier == 0 then
		return short, short
	end
	local key = "num.name." .. tostring(tier * 3)
	local texts = Strings[if fr then "fr" else "en"] or Strings.en
	local word = texts[key] or Strings.en[key] or ""
	-- français : pluriel dès 2 (« 7,80 billions »), « mille » est invariable
	if fr and tier >= 2 and a >= 2 * 10 ^ (tier * 3) then
		word ..= "s"
	end
	local text = num .. " " .. word
	if x < 0 then
		text = "-" .. text
	end
	return short, text
end

-- Clé « num.word.<p> » si n est un jalon de bannière (1e6, 1e9, 1e12, 1e15)
function BigNumber.milestoneKey(n: number): string?
	local x = sane(n)
	if x <= 0 or x == math.huge then
		return nil
	end
	for _, p in MILESTONES do
		local v = 10 ^ p
		if math.abs(x - v) <= v * 1e-9 then
			return "num.word." .. tostring(p)
		end
	end
	return nil
end

-- Suffixes de la langue, du plus petit au plus grand
function BigNumber.suffixes(lang: string?): { string }
	return table.clone(if isFr(lang) then SUFFIXES_FR else SUFFIXES_EN)
end

return BigNumber
