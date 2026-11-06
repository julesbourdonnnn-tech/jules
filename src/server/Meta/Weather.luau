--!strict
-- Weather (lot A4, étape 3 ; GDD v2.0 §5.6, §7.5 ; docs/04 §27.5, §27.7 ; décision D25 du plan) : météo
-- de Wobbleton, PUREMENT VISUELLE (décision par défaut n° 4 : aucun bonus de mutation, aucun effet sur le
-- jeu). Module pur : fonction de l'heure UTC seulement, la même sur tous les serveurs au même instant, sans
-- message entre serveurs.
--   * Fenêtres : Events.Weather.Windows, en minutes de l'heure UTC, début compris, fin exclue (:08:00 →
--     :12:59,999…, :38:00 → :42:59,999…) ;
--   * sorte : Hash.int(1, #Events.Weather.Kinds, index global de la fenêtre, SALT), index = heure UTC ×
--     nombre de fenêtres + rang de la fenêtre dans l'heure (une sorte par fenêtre, tirée pareil partout) ;
--   * aucune météo pendant une séance de Jelly Moon (moonActive).
-- Seul EventService la lit (EventState.weather, interrupteur Weather) ; jamais une récompense, une chance,
-- un prix ni une durée (Contract : rien d'autre ne requiert ce module).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Hash = require(Shared.Logic.Hash)

local Weather = {}

local HOUR = 3600
local MINUTE = 60
-- sel fixe du tirage de la sorte (« WTHR ») : changer cette valeur change la météo de tous les serveurs
local SALT = 0x57544852
local WINDOWS = Events.Weather.Windows
local KINDS = #Events.Weather.Kinds

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Fenêtre lisible : début et fin en minutes, 0 ≤ début < fin ≤ 60
local function valid(window: { number }): boolean
	local a, b = window[1], window[2]
	return finite(a) and finite(b) and a >= 0 and a < b and b <= 60
end

-- Météo en cours à l'instant `unix` (secondes UTC, Clock.now() ou Clock.unix()) : { kind = index de
-- Events.Weather.Kinds, endsAt = fin de la fenêtre (secondes UTC) }, nil hors des fenêtres, pendant une
-- séance de Jelly Moon (moonActive) ou pour un instant illisible
function Weather.at(unix: number, moonActive: boolean): { kind: number, endsAt: number }?
	if not finite(unix) or moonActive == true or KINDS < 1 then
		return nil
	end
	local hour = math.floor(unix / HOUR)
	local base = hour * HOUR
	local second = unix - base
	for i, window in WINDOWS do
		if valid(window) and second >= window[1] * MINUTE and second < window[2] * MINUTE then
			return {
				kind = Hash.int(1, KINDS, hour * #WINDOWS + i, SALT),
				endsAt = base + window[2] * MINUTE,
			}
		end
	end
	return nil
end

-- Prochaine borne de fenêtre (début ou fin) strictement après `unix` : EventService renvoie EventState à
-- chaque borne. Aucune allocation (vérifiée au tick) ; math.huge pour un instant illisible ou sans fenêtre
function Weather.nextChange(unix: number): number
	if not finite(unix) then
		return math.huge
	end
	local base = math.floor(unix / HOUR) * HOUR
	local best = math.huge
	for k = 0, 1 do
		local hourStart = base + k * HOUR
		for _, window in WINDOWS do
			if valid(window) then
				local a = hourStart + window[1] * MINUTE
				local b = hourStart + window[2] * MINUTE
				if a > unix and a < best then
					best = a
				end
				if b > unix and b < best then
					best = b
				end
			end
		end
	end
	return best
end

-- Sel du tirage (specs : même sorte sur deux serveurs, valeur figée)
Weather.SALT = SALT

return Weather
