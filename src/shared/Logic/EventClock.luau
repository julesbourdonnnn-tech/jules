--!strict
-- EventClock — paquet « logic » (STUB du contrat : docs/04-architecture.md §12.1).
-- Phase de chaque événement à l'instant t (secondes UTC, Clock.now()) : fonction PURE du temps,
-- même résultat sur tous les serveurs et clients. Aucune lecture d'horloge ici : t est un paramètre.
-- Responsabilités :
--   * météo : créneau floor(t / 360), fenêtre [début + 120, début + 270[, type tiré par
--     Hash.unit(créneau, Events.Salts.Weather) contre les poids cumulés des météos ACTIVÉES ;
--     pendant Starfall Saturday : Rainbow continu (fenêtre = celle du show)
--   * Comète : impact à chaque multiple de 600 s (id = impactAt), alerte −8 s, explosion +75 s ;
--     pendant Starfall : toutes les 180 s de 16:00 à 16:18 (7 comètes) au lieu du planning normal
--   * point d'impact (rayon 10-40 du Cratère, angle 0-360°) et contenu (Légendaire 80 /
--     Mythique 18 / Cosmique 2, espèce uniforme activée) dérivés de Hash(id, sels)
--   * Nuit de la Balise : [k × 1800 + 1500, + 180[, alerte −15 s ; aucune pendant Starfall
--   * Starfall Saturday : samedi 16:00-16:20 UTC
--   * prochain événement (pastille du HUD), rotations hebdomadaires (§5.1)
-- GDD : §2.4, §4.15.1, §4.15.2, §4.15.3, §4.15.5, §5.1, §12.9 (EventClock.spec : minuit, :25, :55,
-- samedi 16:00 et 16:20 ; répartition des météos sur 100 000 créneaux à ±1 % des poids).
-- Dépendances : Config/Events, Config/Balance, Config/Nebbies, Config/Zones, Logic/Hash.

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

function EventClock.day(_t: number): number
	error("TODO(logic): EventClock.day")
end

function EventClock.week(_t: number): number
	error("TODO(logic): EventClock.week")
end

-- 0 = dimanche … 6 = samedi
function EventClock.weekday(_t: number): number
	error("TODO(logic): EventClock.weekday")
end

-- Clé de météo d'un créneau (hors Starfall)
function EventClock.weatherKeyForSlot(_slot: number): string
	error("TODO(logic): EventClock.weatherKeyForSlot")
end

-- Fenêtre météo ACTIVE à t, sinon nil
function EventClock.weather(_t: number): WeatherWindow?
	error("TODO(logic): EventClock.weather")
end

-- Prochaine fenêtre météo qui commence strictement après t
function EventClock.nextWeather(_t: number): WeatherWindow
	error("TODO(logic): EventClock.nextWeather")
end

-- Comète dont l'intervalle [warnAt, burstAt[ contient t, sinon nil
function EventClock.comet(_t: number): CometSlot?
	error("TODO(logic): EventClock.comet")
end

-- Première Comète dont warnAt > t
function EventClock.nextComet(_t: number): CometSlot
	error("TODO(logic): EventClock.nextComet")
end

-- Point d'impact (Y = sol du Cratère)
function EventClock.cometImpact(_id: number): Vector3
	error("TODO(logic): EventClock.cometImpact")
end

-- (rareté, espèce) du Nebby de la Comète ; la forme vient de la météo active à l'impact
function EventClock.cometContent(_id: number): (number, number)
	error("TODO(logic): EventClock.cometContent")
end

-- Nuit de la Balise dont [warnAt, endsAt[ contient t, sinon nil
function EventClock.beacon(_t: number): BeaconWindow?
	error("TODO(logic): EventClock.beacon")
end

function EventClock.nextBeacon(_t: number): BeaconWindow
	error("TODO(logic): EventClock.nextBeacon")
end

function EventClock.starfall(_t: number): StarfallWindow?
	error("TODO(logic): EventClock.starfall")
end

function EventClock.nextStarfall(_t: number): StarfallWindow
	error("TODO(logic): EventClock.nextStarfall")
end

-- Prochain événement à afficher dans la pastille du HUD (le plus proche dans le temps)
function EventClock.nextEvent(_t: number): NextEvent
	error("TODO(logic): EventClock.nextEvent")
end

-- Rotations (§5.1) : indice = w mod #table
function EventClock.featuredSpecies(_week: number): number
	error("TODO(logic): EventClock.featuredSpecies")
end

function EventClock.weeklyWanderer(_week: number): number
	error("TODO(logic): EventClock.weeklyWanderer")
end

function EventClock.grandParadeLegendary(_week: number): number
	error("TODO(logic): EventClock.grandParadeLegendary")
end

-- Espèce d'une rotation nommée (Events.Rotations[name]) pour la semaine `week`
function EventClock.rotation(_name: string, _week: number): number
	error("TODO(logic): EventClock.rotation")
end

return EventClock
