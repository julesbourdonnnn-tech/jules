--!strict
-- UI/Format (lot B1, docs/04 §27.7 ; GDD v2.0 §10.7.7, §10.8 règles 7 et 8) : UN formateur par sorte
-- de nombre de l'interface, dans la langue du joueur. Les montants du jeu (pièces, prix) restent à
-- Logic/BigNumber (GDD §4.2) ; tout le reste passe ici, et nulle part ailleurs dans UI/* (aucun
-- tostring, « .. » ni string.format d'un nombre hors de UI/Text et UI/Format : Static_TextSet.spec).
--
--   Format.multiplier(1.175, "fr")     → « ×1,175 » (3 décimales ; entier → « ×14 »)
--   Format.percent(5, "fr")            → « +5 % »   (points de pourcentage, entier par défaut)
--   Format.seconds(9, "fr")            → « 9,0 s »  (1 décimale)
--   Format.level(12, 20)               → « 12/20 »
--   Format.confetti(99999, "fr")       → « 99 999 », puis « 100 K » … « 999 K » (plafond)
--   Format.roman(28)                   → « XXVIII » (décor seulement : arche, titre du spectacle)
--   Format.count(3)                    → « 3 »      (petit compteur : cœurs, rang, ×n, étape)
--   Format.decimal(1.25, "fr", 1)      → « 1,3 »    (valeur d'une variable {x} d'une clé ; sans
--                                         décimales : jusqu'à 3, zéros de fin retirés, « 1,5 »)
--   Format.clock(75)                   → « 1:15 »   (compte à rebours ; « 1:02:05 »)
--   Format.timeOfDay(unix)             → « 14:05:09 » (heure UTC du panneau Diagnostics)
--   Format.hoursMinutes(18720, "fr")   → « 5 h 12 » (durée d'absence)
--   Format.id(42)                      → « 42 »     (identifiant ou clé : jamais montré au joueur)
--   Format.key("a", 3, true)           → « a|3|true » (clé de cache : jamais montrée au joueur)
--
-- Règles communes (valeurs hostiles comprises) : NaN → 0 ; ±inf et valeurs énormes → le plafond
-- affiché du formateur (jamais « inf », « nan » ni « ∞ ») ; « - » ASCII pour un négatif (C10) ;
-- français : virgule décimale et espace ORDINAIRE U+0020 (FredokaOne n'a ni U+00A0 ni U+202F :
-- docs/04 §27.11, INT-V2-GLYPHS d ; Format.spec vérifie chaque sortie dans la table cmap des deux
-- polices). Chaque formateur a une largeur réservée (Format.Reserved : sa sortie la plus large, à sa
-- taille dessinée, tient dans sa place ; Format_Widths.spec, 10 000 nombres tirés au hasard).

local Format = {}

-- Plafonds affichés (le plus grand nombre que chaque formateur écrit) : en chiffres significatifs
-- pour les décimaux (« ×99,999 » à 3 décimales, « ×99999 » entier : la place réservée de 120 px à
-- 32 px tient 5 chiffres et le signe « × » ; « +999,9 % » / « +9999 % » : 4 chiffres)
Format.MultiplierDigits = 5
Format.PercentDigits = 4
Format.MaxSeconds = 9999.9
Format.MaxLevel = 99
Format.MaxConfettiRaw = 99999 -- entier brut jusqu'ici (GDD §10.7.7)
Format.MaxConfetti = 999999 -- puis « 100 K » … « 999 K »
Format.MaxCount = 9999999
Format.MaxRoman = 3999

-- Largeurs réservées en px TV (FredokaOne, taille dessinée `size`), Config/Layout.Upgrades :
--   confetti : place des Confettis de l'en-tête (200) moins l'icône (48) ;
--   level : colonne Niveau d'une ligne (140) ;
--   multiplier, percent, seconds : une valeur de l'« avant → après » de la colonne texte (540, ligne
--   2 en 32 px) : 540 − le plus long libellé d'effet (« Croissance », 139 px) − écart − flèche
--   dessinée (48) laisse 345 px pour deux valeurs : 120 chacune.
Format.Reserved = {
	confetti = { size = 40, width = 152 },
	level = { size = 40, width = 140 },
	multiplier = { size = 32, width = 120 },
	percent = { size = 32, width = 120 },
	seconds = { size = 32, width = 120 },
}

local SPACE = " " -- U+0020 : seule espace des deux polices

local function isFr(lang: string?): boolean
	return lang == "fr"
end

-- Nombre sûr dans [lo, hi] : NaN (et tout ce qui n'est pas un nombre) → 0, ±inf → la borne
local function sane(x: any, lo: number, hi: number): number
	if type(x) ~= "number" or x ~= x then
		return math.clamp(0, lo, hi)
	end
	return math.clamp(x, lo, hi)
end

-- Entier ≥ 0 écrit en chiffres (sans « %d » de string.format, qui déborde au-delà de 2^63)
local function digits(n: number): string
	local v = math.floor(n)
	if v == 0 then
		return "0"
	end
	local parts = {}
	while v > 0 do
		local d = v % 10
		table.insert(parts, 1, string.char(48 + d))
		v = v // 10
	end
	return table.concat(parts)
end

-- Groupes de 3 chiffres : « 99,999 » (EN) / « 99 999 » (FR, espace ordinaire)
local function grouped(n: number, lang: string?): string
	local s = digits(n)
	local sep = if isFr(lang) then SPACE else ","
	local first = #s % 3
	local out = {}
	if first > 0 then
		table.insert(out, string.sub(s, 1, first))
	end
	for i = first + 1, #s, 3 do
		table.insert(out, string.sub(s, i, i + 2))
	end
	return table.concat(out, sep)
end

-- Nombre à `decimals` décimales (0 à 4), arrondi au plus proche sur la valeur entière à l'échelle
-- (1,175 → 1175 millièmes : jamais l'arrondi binaire de string.format) ; signe « - » ASCII
local function fixed(x: number, decimals: number, lang: string?): string
	local d = math.clamp(math.floor(decimals), 0, 4)
	local scale = 10 ^ d
	local negative = x < 0
	local m = math.floor(math.abs(x) * scale + 0.5)
	local int = m // scale
	local text = digits(int)
	if d > 0 then
		local frac = digits(m % scale)
		frac = string.rep("0", d - #frac) .. frac
		text ..= (if isFr(lang) then "," else ".") .. frac
	end
	if negative and m > 0 then
		text = "-" .. text
	end
	return text
end

-- Plus grande valeur écrite avec `digits` chiffres dont `decimals` après la virgule (au moins un
-- chiffre entier) : 5 et 3 → 99,999
local function capFor(digits: number, decimals: number): number
	local d = math.clamp(math.floor(decimals), 0, 4)
	local intDigits = math.max(1, digits - d)
	return 10 ^ intDigits - 10 ^ -d
end

local function isInteger(x: number): boolean
	return math.abs(x - math.floor(x + 0.5)) < 1e-9
end

-- « ×1,175 » : `decimals` (0 à 3) ; nil → entier si x est entier (« ×14 »), sinon 3 décimales (moins
-- au-delà de ×99 : 5 chiffres en tout, « ×123,46 »).
-- Une même ligne passe toujours `decimals` (« ×1,975 → ×2,000 » des Gants : 3 décimales)
function Format.multiplier(x: number, lang: string?, decimals: number?): string
	local v = sane(x, 0, capFor(Format.MultiplierDigits, 0))
	local d = decimals
	if d == nil then
		-- entier : « ×14 » ; sinon 3 décimales, moins si la partie entière est longue (5 chiffres en tout)
		d = if isInteger(v) then 0 else math.clamp(Format.MultiplierDigits - #digits(v), 0, 3)
	end
	v = math.min(v, capFor(Format.MultiplierDigits, d))
	return "×" .. fixed(v, d, lang)
end

-- « +5 % » (FR) / « +5% » (EN) : x en points de pourcentage (5 = 5 %), entier par défaut ; « - »
-- pour un négatif, rien devant 0
function Format.percent(x: number, lang: string?, decimals: number?): string
	local cap = capFor(Format.PercentDigits, decimals or 0)
	local v = sane(x, -cap, cap)
	local text = fixed(v, decimals or 0, lang)
	local zero = string.match(text, "^%-?[0%.,]+$") ~= nil
	if zero then
		text = string.gsub(text, "^%-", "")
	elseif v > 0 then
		text = "+" .. text
	end
	return text .. (if isFr(lang) then SPACE .. "%" else "%")
end

-- « 9,0 s » (FR) / « 9.0 s » (EN) : 1 décimale, jamais négatif
function Format.seconds(x: number, lang: string?): string
	local v = sane(x, 0, Format.MaxSeconds)
	return fixed(v, 1, lang) .. SPACE .. "s"
end

-- « 12/20 » : deux entiers de 0 à 99 (« 40/40 » des Gants tient dans la colonne Niveau)
function Format.level(a: number, b: number): string
	local x = math.floor(sane(a, 0, Format.MaxLevel))
	local y = math.floor(sane(b, 0, Format.MaxLevel))
	return digits(x) .. "/" .. digits(y)
end

-- Confettis : entier brut groupé jusqu'à 99 999 (« 99 999 »), puis milliers tronqués « 100 K » …
-- « 999 K » (plafond : la place de 200 couvre les deux, GDD §10.7.7)
function Format.confetti(n: number, lang: string?): string
	local v = math.floor(sane(n, 0, Format.MaxConfetti))
	if v <= Format.MaxConfettiRaw then
		return grouped(v, lang)
	end
	local k = math.min(999, v // 1000)
	return digits(k) .. (if isFr(lang) then SPACE .. "K" else "K")
end

-- Chiffres romains (décor seulement : arche du ranch, titre du spectacle, drapeaux ; jamais un
-- état ni un cadenas, GDD §10.7.6, N20) ; 1 à 3999, « » sous 1
local ROMAN_VALUES = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 }
local ROMAN_SYMBOLS = { "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" }
function Format.roman(n: number): string
	local v = math.floor(sane(n, 0, Format.MaxRoman))
	local out = {}
	for i, value in ROMAN_VALUES do
		while v >= value do
			table.insert(out, ROMAN_SYMBOLS[i])
			v -= value
		end
	end
	return table.concat(out)
end

-- Petit compteur entier ≥ 0 sans séparateur (« 3 » cœurs, rang « 12 », « ×4 », étape « 5 »)
function Format.count(n: number): string
	return digits(sane(n, 0, Format.MaxCount))
end

-- Valeur d'une variable {x} d'une clé (« Revenu total +{a} % » → « 1,2 ») : `decimals` (0 à 4),
-- virgule en français ; nil → jusqu'à 3 décimales, zéros de fin retirés (1,5 ; 2 ; 1,25) ;
-- ±999 999 999 au plus
function Format.decimal(x: number, lang: string?, decimals: number?): string
	local v = sane(x, -999999999, 999999999)
	if decimals ~= nil then
		return fixed(v, decimals, lang)
	end
	local text = fixed(v, 3, lang)
	if string.find(text, "[,%.]") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "[,%.]$", "")
	end
	if text == "-0" then
		text = "0"
	end
	return text
end

local function pad2(n: number): string
	return if n < 10 then "0" .. digits(n) else digits(n)
end

-- Compte à rebours « m:ss » (« h:mm:ss » au-delà d'une heure), arrondi à la seconde supérieure,
-- jamais négatif, 99:59:59 au plus
function Format.clock(seconds: number): string
	local s = math.ceil(sane(seconds, 0, 359999))
	local h = s // 3600
	local m = (s % 3600) // 60
	local r = s % 60
	if h > 0 then
		return digits(h) .. ":" .. pad2(m) .. ":" .. pad2(r)
	end
	return digits(m) .. ":" .. pad2(r)
end

-- Heure du jour « hh:mm:ss » (UTC) d'un instant Unix
function Format.timeOfDay(unix: number): string
	local s = math.floor(sane(unix, 0, 1e12)) % 86400
	return pad2(s // 3600) .. ":" .. pad2((s % 3600) // 60) .. ":" .. pad2(s % 60)
end

-- Durée en heures et minutes « 5 h 12 » (les deux langues : GDD §7.2), 9 999 h au plus
function Format.hoursMinutes(seconds: number, _lang: string?): string
	local s = math.floor(sane(seconds, 0, 9999 * 3600 + 3599))
	return digits(s // 3600) .. SPACE .. "h" .. SPACE .. pad2((s % 3600) // 60)
end

-- Identifiant ou morceau de clé (« objective.12 », nom d'instance, argument d'une commande) : jamais
-- montré au joueur ; entier signé, sans séparateur
function Format.id(n: number): string
	local v = sane(n, -1e15, 1e15)
	local text = digits(math.abs(v))
	return if v < 0 and math.floor(math.abs(v)) > 0 then "-" .. text else text
end

-- Clé de cache faite de plusieurs parties (jamais montrée au joueur) : chaînes telles quelles,
-- nombres entiers par Format.id (autres nombres : millièmes), booléens, énumérations par leur nom,
-- nil → « nil » ; parties séparées par « | »
function Format.key(...: any): string
	local parts = table.pack(...)
	local out = table.create(parts.n)
	for i = 1, parts.n do
		local v = parts[i]
		local t = typeof(v)
		if t == "string" then
			out[i] = v
		elseif t == "number" then
			out[i] = if isInteger(v) then Format.id(v) else Format.id(math.floor(v * 1000 + 0.5)) .. "m"
		elseif t == "boolean" then
			out[i] = if v then "true" else "false"
		elseif t == "EnumItem" then
			out[i] = (v :: EnumItem).Name
		elseif v == nil then
			out[i] = "nil"
		else
			out[i] = t
		end
	end
	return table.concat(out, "|")
end

return Format
