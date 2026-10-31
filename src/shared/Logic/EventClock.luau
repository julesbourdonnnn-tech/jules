--!strict
-- EventClock — paquet « logic » (docs/04-architecture.md §12.1).
-- Phase de chaque événement à l'instant t (secondes UTC, Clock.now()) : fonction PURE du temps,
-- même résultat sur tous les serveurs et clients. Aucune lecture d'horloge ici : t est un paramètre.
--   * météo : créneau floor(t / 360), fenêtre [début + 120, début + 270[, type tiré par
--     Hash.unit(créneau, Events.Salts.Weather) contre les poids cumulés des météos ACTIVÉES ;
--     pendant Starfall Saturday : Rainbow continu (fenêtre = celle du show), les fenêtres normales
--     qui touchent le show sont supprimées
--   * Comète : impact à chaque multiple de 600 s (id = impactAt), alerte −8 s, explosion +75 s ;
--     pendant Starfall : toutes les 180 s de 16:00 à 16:18 (7 comètes) au lieu du planning normal
--   * point d'impact (rayon 10-40 du Cratère, angle 0-360°) et contenu (Légendaire 80 /
--     Mythique 18 / Cosmique 2, espèce uniforme activée) dérivés de Hash(id, sels)
--   * Nuit de la Balise : [k × 1800 + 1500, + 180[, alerte −15 s ; aucune qui touche Starfall
--   * Starfall Saturday : samedi 16:00-16:20 UTC
--   * prochain événement (pastille du HUD), rotations hebdomadaires (§5.1)
-- Conventions : toutes les fenêtres sont semi-ouvertes [début, fin[ ; les instants sont des
-- entiers (multiples de la seconde) dès que la configuration l'est.
-- GDD : §2.4, §4.15.1, §4.15.2, §4.15.3, §4.15.5, §5.1, §12.9.
-- Dépendances : Config/Events, Config/Balance, Config/Nebbies, Config/Zones, Logic/Hash.

local Config = script.Parent.Parent.Config
local Balance = require(Config.Balance)
local Events = require(Config.Events)
local Nebbies = require(Config.Nebbies)
local Zones = require(Config.Zones)
local Hash = require(script.Parent.Hash)

local EventClock = {}

export type WeatherWindow = {
	slot: number,
	key: string,
	form: number?,
	startsAt: number,
	endsAt: number,
	starfall: boolean,
}

export type CometSlot = {
	id: number, -- = impactAt (entier)
	warnAt: number,
	impactAt: number,
	burstAt: number,
	starfall: boolean,
}

export type BeaconWindow = {
	id: number, -- = startsAt
	warnAt: number,
	startsAt: number,
	endsAt: number,
}

export type StarfallWindow = {
	startsAt: number,
	endsAt: number,
	week: number,
	featured: number, -- espèce vedette (Events.Rotations.FeaturedSpecies[w mod 12])
}

export type NextEvent = {
	kind: "comet" | "weather" | "beacon" | "starfall",
	at: number,
	key: string?, -- clé de météo
}

local Cal = Events.Calendar
local W = Events.Weather
local SF = Events.Starfall

-- Entrée non finie → 0 (jamais de boucle infinie ni d'erreur)
local function sane(t: number): number
	if type(t) ~= "number" or t ~= t or t == math.huge or t == -math.huge then
		return 0
	end
	return t
end

-- ---------------------------------------------------------------------------------------------
-- Calendrier
-- ---------------------------------------------------------------------------------------------

function EventClock.day(t: number): number
	return math.floor(sane(t) / Cal.Day)
end

function EventClock.week(t: number): number
	return math.floor((sane(t) - Cal.WeekEpoch) / Cal.Week)
end

-- 0 = dimanche … 6 = samedi
function EventClock.weekday(t: number): number
	return (EventClock.day(t) + Cal.WeekdayOffset) % 7
end

local function weekdayOfDay(day: number): number
	return (day + Cal.WeekdayOffset) % 7
end

-- ---------------------------------------------------------------------------------------------
-- Starfall Saturday
-- ---------------------------------------------------------------------------------------------

-- Espèce d'une rotation nommée (Events.Rotations[name]) pour la semaine `week`
function EventClock.rotation(name: string, week: number): number
	local list = (Events.Rotations :: any)[name] :: { number }?
	if list and #list > 0 then
		local w = math.floor(sane(week))
		return list[(w % #list) + 1]
	end
	error(`EventClock.rotation : rotation inconnue « {tostring(name)} »`)
end

function EventClock.featuredSpecies(week: number): number
	return EventClock.rotation("FeaturedSpecies", week)
end

function EventClock.weeklyWanderer(week: number): number
	return EventClock.rotation("WeeklyWanderer", week)
end

function EventClock.grandParadeLegendary(week: number): number
	return EventClock.rotation("GrandParadeLegendary", week)
end

-- Fenêtre du show d'un jour UTC (nil si ce jour n'est pas le bon jour de la semaine)
local function starfallOfDay(day: number): StarfallWindow?
	if weekdayOfDay(day) ~= SF.Weekday then
		return nil
	end
	local startsAt = day * Cal.Day + SF.StartSecond
	local week = EventClock.week(startsAt)
	return {
		startsAt = startsAt,
		endsAt = startsAt + SF.Duration,
		week = week,
		featured = EventClock.featuredSpecies(week),
	}
end

-- Shows dont la fenêtre peut toucher [a, b[ (au plus quelques jours examinés)
local function starfallOverlapping(a: number, b: number): StarfallWindow?
	local first = math.floor((a - SF.StartSecond - SF.Duration) / Cal.Day)
	local last = math.floor((b - SF.StartSecond) / Cal.Day)
	for day = first, last do
		local sf = starfallOfDay(day)
		if sf and sf.startsAt < b and a < sf.endsAt then
			return sf
		end
	end
	return nil
end

-- Show en cours à t (le show d'un jour peut déborder sur le lendemain si la configuration le
-- place tard : on examine les jours qui peuvent le contenir)
function EventClock.starfall(t: number): StarfallWindow?
	local x = sane(t)
	local first = math.floor((x - SF.StartSecond - SF.Duration) / Cal.Day)
	local last = math.floor((x - SF.StartSecond) / Cal.Day)
	for day = first, last do
		local sf = starfallOfDay(day)
		if sf and x >= sf.startsAt and x < sf.endsAt then
			return sf
		end
	end
	return nil
end

-- Premier show qui commence strictement après t
function EventClock.nextStarfall(t: number): StarfallWindow
	local x = sane(t)
	local day = EventClock.day(x)
	for k = -1, 8 do
		local sf = starfallOfDay(day + k)
		if sf and sf.startsAt > x then
			return sf
		end
	end
	error("EventClock.nextStarfall : configuration Events.Starfall invalide") -- inatteignable (7 jours)
end

-- ---------------------------------------------------------------------------------------------
-- Météo
-- ---------------------------------------------------------------------------------------------

-- Clé de météo d'un créneau (hors Starfall), tirée parmi les météos activées
function EventClock.weatherKeyForSlot(slot: number): string
	local weights = {}
	local keys = {}
	for _, def in W.Kinds do
		if Nebbies.isVersionEnabled(def.version) then
			table.insert(weights, def.weight)
			table.insert(keys, def.key)
		end
	end
	if #keys == 0 then
		return W.Kinds[1].key
	end
	local r = Hash.unit(math.floor(sane(slot)), Events.Salts.Weather)
	return keys[Hash.pickWeighted(weights, r)]
end

local function formOfWeather(key: string): number?
	local def = Events.WeatherByKey[key]
	if def == nil or def.form == nil then
		return nil
	end
	if not Nebbies.isFormEnabled(def.form) then
		return nil
	end
	return def.form
end

-- Fenêtre normale d'un créneau, nil si elle touche un Starfall (remplacée par le Rainbow du show)
local function regularWeather(slot: number): WeatherWindow?
	local startsAt = slot * W.Period + W.Offset
	local endsAt = startsAt + W.Duration
	if starfallOverlapping(startsAt, endsAt) then
		return nil
	end
	local key = EventClock.weatherKeyForSlot(slot)
	return {
		slot = slot,
		key = key,
		form = formOfWeather(key),
		startsAt = startsAt,
		endsAt = endsAt,
		starfall = false,
	}
end

local function starfallWeather(sf: StarfallWindow): WeatherWindow
	local key = SF.Weather
	return {
		slot = math.floor(sf.startsAt / W.Period),
		key = key,
		form = formOfWeather(key),
		startsAt = sf.startsAt,
		endsAt = sf.endsAt,
		starfall = true,
	}
end

-- Fenêtre météo ACTIVE à t, sinon nil
function EventClock.weather(t: number): WeatherWindow?
	local x = sane(t)
	local sf = EventClock.starfall(x)
	if sf then
		return starfallWeather(sf)
	end
	local slot = math.floor(x / W.Period)
	-- la fenêtre d'un créneau peut déborder sur le suivant si Offset + Duration > Period
	for s = slot, slot - math.ceil((W.Offset + W.Duration) / W.Period), -1 do
		local w = regularWeather(s)
		if w and x >= w.startsAt and x < w.endsAt then
			return w
		end
	end
	return nil
end

-- Prochaine fenêtre météo qui commence strictement après t
function EventClock.nextWeather(t: number): WeatherWindow
	local x = sane(t)
	local best: WeatherWindow? = nil
	local slot = math.floor((x - W.Offset) / W.Period)
	-- un show supprime au plus ceil(Duration / Period) + 1 créneaux : 64 suffit largement
	for s = slot, slot + 64 do
		local w = regularWeather(s)
		if w and w.startsAt > x then
			best = w
			break
		end
	end
	local sf = EventClock.nextStarfall(x)
	if best == nil or sf.startsAt < best.startsAt then
		return starfallWeather(sf)
	end
	return best
end

-- ---------------------------------------------------------------------------------------------
-- Grande Comète
-- ---------------------------------------------------------------------------------------------

local CP = Events.Comet.Period
local WARN = Balance.Comet.WarnSeconds
local BURST = Balance.Comet.BurstAfter

local function cometAt(impactAt: number, starfall: boolean): CometSlot
	return {
		id = impactAt,
		warnAt = impactAt - WARN,
		impactAt = impactAt,
		burstAt = impactAt + BURST,
		starfall = starfall,
	}
end

-- Impacts du show (16:00, 16:03 … dans [début, fin[)
local function starfallImpacts(sf: StarfallWindow): { number }
	local out = {}
	local i = sf.startsAt
	while i < sf.endsAt do
		table.insert(out, i)
		i += SF.CometEvery
	end
	return out
end

-- Toutes les Comètes dont l'impact est dans [a, b] (planning normal + shows), triées
local function cometsBetween(a: number, b: number): { CometSlot }
	local out: { CometSlot } = {}
	for i = math.ceil(a / CP) * CP, b, CP do
		if EventClock.starfall(i) == nil then -- impact normal remplacé pendant le show
			table.insert(out, cometAt(i, false))
		end
	end
	local firstDay = math.floor((a - SF.StartSecond - SF.Duration) / Cal.Day)
	local lastDay = math.floor((b - SF.StartSecond) / Cal.Day)
	for day = firstDay, lastDay do
		local sf = starfallOfDay(day)
		if sf then
			for _, i in starfallImpacts(sf) do
				if i >= a and i <= b then
					table.insert(out, cometAt(i, true))
				end
			end
		end
	end
	table.sort(out, function(x, y)
		return x.impactAt < y.impactAt
	end)
	return out
end

-- Comète dont l'intervalle [warnAt, burstAt[ contient t, sinon nil
function EventClock.comet(t: number): CometSlot?
	local x = sane(t)
	for _, c in cometsBetween(x - BURST, x + WARN) do
		if x >= c.warnAt and x < c.burstAt then
			return c
		end
	end
	return nil
end

-- Première Comète dont warnAt > t
function EventClock.nextComet(t: number): CometSlot
	local x = sane(t)
	local from = x + WARN
	-- au plus une période normale sépare deux impacts : quelques tours suffisent toujours
	for _ = 1, 64 do
		for _, c in cometsBetween(from, from + CP) do
			if c.warnAt > x then
				return c
			end
		end
		from += CP
	end
	error("EventClock.nextComet : configuration Events.Comet invalide") -- inatteignable
end

-- Point d'impact (Y = sol du Cratère) : rayon et angle tirés de Hash(id, sel)
function EventClock.cometImpact(id: number): Vector3
	local key = math.floor(sane(id))
	local c = Balance.Comet
	local angle = Hash.range(0, 2 * math.pi, key, Events.Salts.CometPoint, 1)
	local radius = Hash.range(c.ImpactRadiusMin, c.ImpactRadiusMax, key, Events.Salts.CometPoint, 2)
	local crater = Zones.byKey.crater
	local y = if crater then crater.groundY else Zones.Island.TopY
	return Vector3.new(radius * math.cos(angle), y, radius * math.sin(angle))
end

-- (rareté, espèce) du Nebby de la Comète ; la forme vient de la météo active à l'impact
function EventClock.cometContent(id: number): (number, number)
	local key = math.floor(sane(id))
	local weights = {}
	local rarities = {}
	for _, entry in Balance.Comet.Content do
		if #Nebbies.speciesOfRarity(entry.rarity) > 0 then
			table.insert(weights, entry.weight)
			table.insert(rarities, entry.rarity)
		end
	end
	if #rarities == 0 then
		return Nebbies.rarityOf(Nebbies.Named.Cosmic), Nebbies.Named.Cosmic
	end
	local rarity = rarities[Hash.pickWeighted(weights, Hash.unit(key, Events.Salts.CometRarity))]
	local species = Nebbies.speciesOfRarity(rarity)
	local s = species[Hash.int(1, #species, key, Events.Salts.CometSpecies)]
	return rarity, s
end

-- ---------------------------------------------------------------------------------------------
-- Nuit de la Balise
-- ---------------------------------------------------------------------------------------------

local BP = Events.Beacon.Period
local BO = Events.Beacon.Offset
local BWARN = Balance.Beacon.WarnSeconds
local BDUR = Balance.Beacon.Duration

-- Nuit d'indice k (nil si elle touche un Starfall)
local function beaconOf(k: number): BeaconWindow?
	local startsAt = k * BP + BO
	local w: BeaconWindow = {
		id = startsAt,
		warnAt = startsAt - BWARN,
		startsAt = startsAt,
		endsAt = startsAt + BDUR,
	}
	if starfallOverlapping(w.warnAt, w.endsAt) then
		return nil
	end
	return w
end

-- Nuit de la Balise dont [warnAt, endsAt[ contient t, sinon nil
function EventClock.beacon(t: number): BeaconWindow?
	local x = sane(t)
	local k = math.floor((x + BWARN - BO) / BP)
	for kk = k, k - math.ceil((BWARN + BDUR) / BP), -1 do
		local b = beaconOf(kk)
		if b and x >= b.warnAt and x < b.endsAt then
			return b
		end
	end
	return nil
end

-- Première Nuit dont warnAt > t
function EventClock.nextBeacon(t: number): BeaconWindow
	local x = sane(t)
	local k = math.floor((x + BWARN - BO) / BP)
	for kk = k, k + 64 do
		local b = beaconOf(kk)
		if b and b.warnAt > x then
			return b
		end
	end
	error("EventClock.nextBeacon : configuration Events.Beacon invalide") -- inatteignable
end

-- ---------------------------------------------------------------------------------------------
-- Pastille du HUD
-- ---------------------------------------------------------------------------------------------

-- Prochain événement à afficher (le plus proche dans le temps, instant de DÉBUT strictement
-- après t : impact de Comète, début de météo, de Nuit de la Balise ou de Starfall).
-- Égalité : Starfall > Comète > Balise > météo.
function EventClock.nextEvent(t: number): NextEvent
	local x = sane(t)
	local sf = EventClock.nextStarfall(x)
	local best: NextEvent = { kind = "starfall", at = sf.startsAt }
	local comet = EventClock.nextComet(x - WARN) -- impactAt > t
	if comet.impactAt < best.at then
		best = { kind = "comet", at = comet.impactAt }
	end
	local beacon = EventClock.nextBeacon(x - BWARN) -- startsAt > t
	if beacon.startsAt < best.at then
		best = { kind = "beacon", at = beacon.startsAt }
	end
	local weather = EventClock.nextWeather(x)
	if weather.startsAt < best.at then
		best = { kind = "weather", at = weather.startsAt, key = weather.key }
	end
	return best
end

return EventClock
