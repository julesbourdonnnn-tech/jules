--!strict
-- AmbienceRules (lot B4, docs/04 §27.7, GDD v2.0 §11.3 ; décisions D4 et D5 du plan B4). Règles pures
-- du directeur d'ambiance (Render/AmbienceDirector, seul écrivain de Lighting, interrupteur Ambience) :
--   * preset(stack) : UN nom de préréglage, la couche la plus haute gagne : Jelly Moon (« moon ») >
--     BOOP RUSH (« rush », « rush.quiet » pour un nouveau venu) > alerte et MEGA (« mega ») > Wobble ou
--     Squish Party (« party ») > météo (« weather.<sorte> ») > costume de saison (« costume.<id> ») >
--     jour (« day ») ;
--   * weather(unix) : copie EXACTE de Server/Meta/Weather.at(unix, false) (le module du serveur n'est
--     pas répliqué) : mêmes fenêtres (Events.Weather.Windows, début compris, fin exclue), même tirage
--     (Hash.int), même sel ; AmbienceRules.spec la compare au module du serveur ;
--   * fromEvent(weather, unix) : la sorte d'EventState.weather tant que la fenêtre dure (le directeur ne
--     montre une météo QUE depuis EventState : le serveur décide, interrupteur Weather, séance de Lune ;
--     un `endsAt` périmé ou trop lointain ne montre rien).
-- Jamais d'erreur : une entrée illisible donne « day » ou nil.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table = type, math, string, table

local Events = require(script.Parent.Parent.Config.Events)
local Hash = require(script.Parent.Hash)

export type Stack = {
	moon: boolean?, -- séance de Jelly Moon
	rush: boolean?, -- BOOP RUSH en cours
	quietRush: boolean?, -- Rush adouci d'un nouveau venu (avant l'étape 9 de l'accueil)
	mega: boolean?, -- alerte, appui ou éclat du MEGA
	party: boolean?, -- Wobble Party ou Squish Party
	weather: (string | number)?, -- sorte de météo (nom de Events.Weather.Kinds ou son rang)
	costume: string?, -- costume de saison actif (identifiant)
}
export type Weather = { kind: number, endsAt: number }

local AmbienceRules = {}

local HOUR = 3600
local MINUTE = 60
-- Sel du tirage de la sorte : COPIE de Server/Meta/Weather.SALT (« WTHR »), le module du serveur n'étant
-- pas répliqué ; AmbienceRules.spec vérifie l'égalité des deux valeurs et des deux résultats
local SALT = 0x57544852
local WINDOWS = Events.Weather.Windows
local KINDS = Events.Weather.Kinds
local KIND_COUNT = #KINDS
-- Fenêtre la plus longue (secondes) : un `endsAt` plus loin que cela dans le futur est illisible
local LONGEST = 0

-- Ordre des couches, de la plus haute à la plus basse (specs, directeur)
AmbienceRules.ORDER =
	table.freeze({ "moon", "rush", "mega", "party", "weather", "costume", "day" }) :: { string }

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Fenêtre lisible : début et fin en minutes, 0 ≤ début < fin ≤ 60 (même règle que Meta/Weather)
local function valid(window: { number }): boolean
	local a, b = window[1], window[2]
	return finite(a) and finite(b) and a >= 0 and a < b and b <= 60
end

for _, window in WINDOWS do
	if valid(window) then
		LONGEST = math.max(LONGEST, (window[2] - window[1]) * MINUTE)
	end
end

-- Noms des préréglages de météo, construits une fois (aucune concaténation à chaque appel)
local WEATHER_PRESET: { [string]: string } = {}
for _, kind in KINDS do
	WEATHER_PRESET[kind] = "weather." .. kind
end

-- Nom de sorte d'une valeur de la pile : nom connu, ou rang 1 … #Kinds ; sinon nil
local function kindName(value: any): string?
	if type(value) == "string" then
		return if WEATHER_PRESET[value] ~= nil then value else nil
	end
	if finite(value) and value % 1 == 0 and value >= 1 and value <= KIND_COUNT then
		return KINDS[value]
	end
	return nil
end

-- Identifiant de costume lisible : lettres, chiffres et « _ », commence par une lettre, 1 … 32 caractères
local function costumeId(value: any): string?
	if type(value) ~= "string" or #value < 1 or #value > 32 then
		return nil
	end
	if string.match(value, "^%a[%w_]*$") == nil then
		return nil
	end
	return value
end

-- Préréglage de la pile : la couche la plus haute gagne (GDD §11.3)
function AmbienceRules.preset(stack: any): string
	if type(stack) ~= "table" then
		return "day"
	end
	if stack.moon == true then
		return "moon"
	end
	if stack.rush == true then
		return if stack.quietRush == true then "rush.quiet" else "rush"
	end
	if stack.mega == true then
		return "mega"
	end
	if stack.party == true then
		return "party"
	end
	local kind = kindName(stack.weather)
	if kind ~= nil then
		return WEATHER_PRESET[kind]
	end
	local costume = costumeId(stack.costume)
	if costume ~= nil then
		return "costume." .. costume
	end
	return "day"
end

-- Météo en cours à l'instant `unix` (secondes UTC) : exactement Meta/Weather.at(unix, false)
function AmbienceRules.weather(unix: any): Weather?
	if not finite(unix) or KIND_COUNT < 1 then
		return nil
	end
	local hour = math.floor(unix / HOUR)
	local base = hour * HOUR
	local second = unix - base
	for i, window in WINDOWS do
		if valid(window) and second >= window[1] * MINUTE and second < window[2] * MINUTE then
			return {
				kind = Hash.int(1, KIND_COUNT, hour * #WINDOWS + i, SALT),
				endsAt = base + window[2] * MINUTE,
			}
		end
	end
	return nil
end

-- Sorte (nom) d'EventState.weather = { kind, endsAt } à l'instant `unix`, tant que la fenêtre dure :
-- nil pour une charge illisible, une sorte inconnue, une fenêtre finie (unix ≥ endsAt) ou un endsAt
-- plus loin que la plus longue fenêtre
function AmbienceRules.fromEvent(weather: any, unix: any): string?
	if type(weather) ~= "table" or not finite(unix) then
		return nil
	end
	local endsAt = weather.endsAt
	if not finite(endsAt) or unix >= endsAt or endsAt - unix > LONGEST then
		return nil
	end
	return kindName(weather.kind)
end

-- Sel du tirage (specs : égal à Server/Meta/Weather.SALT)
AmbienceRules.SALT = SALT

return AmbienceRules
