--!strict
-- BigNumber (paquet logic, docs/04 §12.1 ; lot A1, docs/04 §27.7). Affichage des nombres géants
-- (GDD v2.0 §4.2), anglais et français. Remplace Format.abbreviate du socle pour tout nombre du jeu
-- (note INT-FORMAT) :
--   * moins de 10 000 : entier avec séparateur des milliers (EN « 9,876 ») ; en français, aucun
--     séparateur à 4 chiffres (« 9876 », espace facultative en français) ;
--   * ensuite 3 chiffres significatifs TRONQUÉS, jamais arrondis vers le haut (999 999 → « 999K »),
--     zéro final gardé (« 7.80T ») et suffixe : MÊMES suffixes internationaux dans les deux langues,
--     de K (1e3) à Tg (1e93) (GDD v2.0 §4.2, critique M11) ; en français, virgule décimale et le
--     suffixe COLLÉ au nombre (« 12,3K », « 4,56B », « 7,80T ») ;
--   * à partir de 1e96 : « 1.23e96 » / « 1,23e96 » (aucun profil simulé n'y arrive avant le jour 140).
-- Note INT-V2-GLYPHS (d), docs/04 §27.11 : les deux polices du texte (FredokaOne, LuckiestGuy)
-- n'ont AUCUNE espace insécable (ni U+00A0, ni U+202F, ni U+2007…) : la seule espace commune est
-- U+0020, où un libellé à retours à la ligne (défaut de UI/Text) peut couper. Un montant abrégé ne
-- contient donc jamais d'espace (« 12,3K » tient toujours sur une ligne) ; full() et words() (fiche,
-- au-delà de 4 chiffres en français) groupent par U+0020 : à poser dans un libellé SANS retour à la
-- ligne. Chaque caractère écrit est dans les deux polices (Contract_glyphs › formateurs).
-- NaN → « 0 », −0 → « 0 », ±inf (valeur hostile) → le plafond affiché « 1.00e300 » (jamais « inf »,
-- « nan » ni « ∞ », absent des deux polices) : jamais d'erreur (propriétés : Props_BigNumber.spec).
-- Les chiffres viennent de string.format("%.14e") (15 chiffres significatifs : exact pour tout
-- entier < 1e15, et une petite erreur d'arrondi flottant — 4,5599999999999995e9 — s'affiche 4.56B).
-- Les mots entiers viennent des clés num.name.<p> de Localization/Strings (table du GDD §4.2) : EN
-- « 7.80 trillion » ; FR « 7800 milliards » (un mot « mille X » s'écrit en milliers de X), « 7,80
-- millions de milliards » (pluriel du premier mot d'un mot composé « X de Y »), « 2,50 trilliards ».
-- Un palier sans clé (au-delà de Dc tant que les clés num.name.36 … 93 n'existent pas, note
-- INT-A1-WORDS) rend la forme courte comme mot : jamais un mot vide.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table = type, math, string, table

local Strings = require(script.Parent.Parent.Localization.Strings)

local BigNumber = {}

local SPACE = " " -- U+0020 : la seule espace des deux polices (groupes de full() et words() en français)
local SCIENTIFIC_EXP = 96 -- à partir de 1e96 : notation « 1.23e96 »
local EXACT_BELOW = 1e15 -- full() : entier exact en dessous
local SHORT_FROM = 10000 -- abbreviate() : abrégé à partir de 10 000
local SHOWN_MAX = 1e300 -- plafond affiché (Balance.Numbers.Max) : ±inf, valeur hostile

-- GDD v2.0 §4.2 : 31 suffixes, 1e3 … 1e93 (Config/Visuals.SuffixColors en donne les couleurs)
-- stylua: ignore start
local SUFFIXES_EN = {
	"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nvd",
	"Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg", "Nvvg", "Tg",
}
-- stylua: ignore end
local SUFFIXES_FR = SUFFIXES_EN -- GDD §4.2 : mêmes suffixes internationaux (virgule décimale en FR)

-- Jalons des bannières (Events.Banners.RecordThresholds) : puissance → clé de texte
local MILESTONES = { 6, 9, 12, 15 }

local function isFr(lang: string?): boolean
	return lang == "fr"
end

-- Nombre sûr : NaN → 0, −0 → 0 ; ±inf → ±plafond affiché (valeur hostile : jamais « ∞ »)
local function sane(n: any): number
	if type(n) ~= "number" or n ~= n then
		return 0
	end
	if n == 0 then
		return 0 -- efface −0
	end
	if n > SHOWN_MAX then
		return if n == math.huge then SHOWN_MAX else n
	end
	if n == -math.huge then
		return -SHOWN_MAX
	end
	return n
end

-- Entier positif (déjà tronqué, < 1e15) avec séparateur des milliers ; français : aucun séparateur
-- à 4 chiffres, U+0020 au-delà (seule espace des deux polices)
local function groupDigits(int: number, fr: boolean): string
	local s = string.format("%d", int)
	if fr and #s <= 4 then
		return s
	end
	local sep = if fr then SPACE else ","
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

-- Forme abrégée d'une valeur absolue finie ≥ 10 000 : (texte du nombre, palier de mille 1 … 31, ou
-- 0 en notation scientifique, puis les 3 chiffres tronqués en entier (« 780 ») et le nombre de chiffres
-- avant la virgule, 1 … 3)
local function shortParts(x: number, fr: boolean): (string, number, number, number)
	local digits, e = digitsOf(x)
	if e >= SCIENTIFIC_EXP then
		local mark = if fr then "," else "."
		return string.sub(digits, 1, 1) .. mark .. string.sub(digits, 2, 3) .. "e" .. tostring(e), 0, 0, 0
	end
	if e < 4 then
		e = 4 -- 9999,99… arrondi par le format : reste au palier des milliers
		digits = "100000000000000"
	end
	local tier = e // 3
	local intDigits = e - tier * 3 + 1
	local three = tonumber(string.sub(digits, 1, 3)) or 100
	return threeDigits(digits, intDigits, fr), tier, three, intDigits
end

-- Pluriel français d'un mot de grand nombre : « millions », « millions de milliards » (le premier mot
-- d'un mot composé « X de Y »), jamais « mille »
local function frPlural(word: string): string
	if word == "mille" or word == "" then
		return word
	end
	local head, tail = string.match(word, "^(%S+)( de .+)$")
	if head and tail then
		return head .. "s" .. tail
	end
	return word .. "s"
end

-- Forme courte du HUD, des étiquettes et des « +N » (jamais d'espace : une seule ligne)
function BigNumber.abbreviate(n: number, lang: string?): string
	local x = sane(n)
	local fr = isFr(lang)
	local negative = x < 0
	local a = math.abs(x)
	local text
	if a < SHORT_FROM then
		text = groupDigits(math.floor(a), fr)
	else
		local num, tier = shortParts(a, fr)
		if tier == 0 then
			text = num
		else
			text = num .. (if fr then SUFFIXES_FR[tier] else SUFFIXES_EN[tier])
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
	local fr = isFr(lang)
	local a = math.abs(x)
	if a < SHORT_FROM then
		return short, BigNumber.full(x, lang)
	end
	local num, tier, three, intDigits = shortParts(a, fr)
	if tier == 0 then
		return short, short
	end
	local key = "num.name." .. tostring(tier * 3)
	local texts = Strings[if fr then "fr" else "en"] or Strings.en
	local word = texts[key] or Strings.en[key]
	if type(word) ~= "string" or word == "" then
		return short, short -- palier sans clé de mot (note INT-A1-WORDS) : jamais un mot vide
	end
	local text
	local thousandsOf = if fr then string.match(word, "^mille (.+)$") else nil
	if thousandsOf then
		-- GDD §4.2 : « 7,80T = 7800 milliards » (« mille milliards » : le second mot est déjà au pluriel)
		text = groupDigits(three * 10 ^ intDigits, true) .. " " .. thousandsOf
	else
		-- français : pluriel dès 2 (« 4,56 milliards »), « mille » est invariable
		if fr and tier >= 2 and a >= 2 * 10 ^ (tier * 3) then
			word = frPlural(word)
		end
		text = num .. " " .. word
	end
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
