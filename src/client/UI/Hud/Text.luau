--!strict
-- Hud/Text — aides de texte du paquet client-hud (modules d'aide de UI/HUD, Banners, ScreenFX).
-- Fonctions PURES (aucun service Roblox) : chiffres romains (Supernova III), décimales localisées
-- (« ×1,16 » en français), noms d'espèces depuis un code de Nebby, nettoyage des variables reçues
-- du réseau (Feedback, bannières) avant interpolation dans Prefs.t.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Nebbies = require(Shared.Config.Nebbies)

local Text = {}

local MAX_NAME = 32 -- caractères ; DisplayName Roblox : 20 caractères (marge)
local MAX_VAR_STRING = 48
local MAX_VARS = 16
local MAX_VAR_KEY = 24
local ROMAN_MAX = 3999

local ROMAN: { { number | string } } = {
	{ 1000, "M" },
	{ 900, "CM" },
	{ 500, "D" },
	{ 400, "CD" },
	{ 100, "C" },
	{ 90, "XC" },
	{ 50, "L" },
	{ 40, "XL" },
	{ 10, "X" },
	{ 9, "IX" },
	{ 5, "V" },
	{ 4, "IV" },
	{ 1, "I" },
}

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Text.isFinite = isFinite

-- 3 → "III" ; hors de 1-3999 (ou non entier) → chiffres arabes
function Text.roman(n: number): string
	if not isFinite(n) then
		return "0"
	end
	local value = math.floor(n)
	if value < 1 or value > ROMAN_MAX then
		return tostring(value)
	end
	local parts: { string } = {}
	for _, pair in ROMAN do
		local unit = pair[1] :: number
		local glyph = pair[2] :: string
		while value >= unit do
			table.insert(parts, glyph)
			value -= unit
		end
	end
	return table.concat(parts)
end

-- 1.16 → "1.16" (en) / "1,16" (fr) ; `digits` décimales fixes
function Text.decimal(x: number, digits: number, lang: string?): string
	local value = if isFinite(x) then x else 0
	local text = string.format(`%.{math.clamp(math.floor(digits), 0, 4)}f`, value)
	if lang == "fr" then
		text = string.gsub(text, "%.", ",")
	end
	return text
end

-- Conga Bonus et multiplicateurs : toujours deux décimales (« ×1,48 »)
function Text.bonus(x: number, lang: string?): string
	return Text.decimal(x, 2, lang)
end

-- Multiplicateur de forme (×2, ×1,5) : entier sans décimales, sinon une décimale
function Text.mult(x: number, lang: string?): string
	if not isFinite(x) then
		return "1"
	end
	if x % 1 == 0 then
		return tostring(math.floor(x))
	end
	return Text.decimal(x, 1, lang)
end

-- Nom propre d'une espèce depuis un code de Nebby (nil si le code est invalide)
function Text.speciesName(code: any): string?
	if not Nebbies.isValidCode(code) then
		return nil
	end
	local s = Nebbies.unpack(code :: number)
	local def = Nebbies.Species[s]
	return if def then def.name else nil
end

-- Tronque à `maxChars` caractères UTF-8 (jamais au milieu d'un caractère multi-octets : un nom
-- cyrillique ou japonais coupé à l'octet s'afficherait avec un caractère de remplacement) ;
-- une chaîne UTF-8 invalide est réduite à ses caractères ASCII
function Text.truncate(value: string, maxChars: number): string
	local s = value
	local length = utf8.len(s)
	if length == nil then
		s = string.gsub(s, "[\128-\255]", "")
		length = #s
	end
	if (length :: number) <= maxChars then
		return s
	end
	local cut = utf8.offset(s, maxChars + 1)
	return if cut then string.sub(s, 1, cut - 1) else s
end

-- Nom de joueur reçu du réseau : chaîne non vide, sans caractères de contrôle, tronquée
function Text.cleanName(value: any): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	local cleaned = Text.truncate(string.gsub(value, "%c", ""), MAX_NAME)
	if cleaned == "" then
		return nil
	end
	return cleaned
end

-- Variables d'un Feedback / d'une bannière : clés alphanumériques, nombres finis formatés par
-- `numberFn`, chaînes nettoyées ; tout le reste est ignoré (charge malveillante sans effet)
function Text.formatVars(vars: any, numberFn: (number) -> string): { [string]: any }
	local out: { [string]: any } = {}
	if type(vars) ~= "table" then
		return out
	end
	local count = 0
	for key, value in vars do
		if count >= MAX_VARS then
			break
		end
		if type(key) == "string" and #key <= MAX_VAR_KEY and string.match(key, "^%w+$") then
			if isFinite(value) then
				out[key] = numberFn(value :: number)
				count += 1
			elseif type(value) == "string" then
				out[key] = Text.truncate(string.gsub(value :: string, "%c", ""), MAX_VAR_STRING)
				count += 1
			elseif type(value) == "boolean" then
				out[key] = tostring(value)
				count += 1
			end
		end
	end
	return out
end

-- Clé de localisation acceptable venant du réseau (« domaine.nom », ids de cosmétiques « comet_tail »)
function Text.isKey(value: any, maxLength: number?): boolean
	return type(value) == "string"
		and #value > 0
		and #value <= (maxLength or 64)
		and string.match(value, "^[%w_%.]+$") ~= nil
end

return Text
