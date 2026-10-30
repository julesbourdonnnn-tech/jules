--!strict
-- Localisation EN/FR. Les textes sont dans Strings.luau ; une clé manquante en FR
-- retombe sur l'anglais, puis sur la clé elle-même (signalée une fois dans la sortie).
--   local t = Localization.translator(Localization.languageFor(player.LocaleId))
--   t("hud.coins", { amount = "1.2K" })   --> "1.2K coins"

local Strings = require(script.Strings)

export type Language = "en" | "fr"
export type Translator = (key: string, vars: { [string]: any }?) -> string

local Localization = {}

local warned: { [string]: boolean } = {}

function Localization.languageFor(localeId: string?): Language
	if type(localeId) == "string" and string.lower(string.sub(localeId, 1, 2)) == "fr" then
		return "fr"
	end
	return "en"
end

local function interpolate(text: string, vars: { [string]: any }?): string
	if not vars then
		return text
	end
	return (string.gsub(text, "{(%w+)}", function(name: string)
		local v = vars[name]
		return if v ~= nil then tostring(v) else "{" .. name .. "}"
	end))
end

function Localization.get(lang: Language, key: string, vars: { [string]: any }?): string
	local text = (Strings[lang] and Strings[lang][key]) or Strings.en[key]
	if text == nil then
		if not warned[key] then
			warned[key] = true
			warn("[Localization] clé manquante :", key)
		end
		return key
	end
	return interpolate(text, vars)
end

function Localization.translator(lang: Language): Translator
	return function(key: string, vars: { [string]: any }?): string
		return Localization.get(lang, key, vars)
	end
end

-- Toutes les clés anglaises doivent exister en français (vérifié par les tests)
function Localization.missingKeys(lang: Language): { string }
	local missing = {}
	for key in Strings.en do
		if Strings[lang][key] == nil then
			table.insert(missing, key)
		end
	end
	table.sort(missing)
	return missing
end

return Localization
