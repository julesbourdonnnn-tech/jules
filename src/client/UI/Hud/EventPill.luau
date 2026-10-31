--!strict
-- Hud/EventPill — contenu de la pastille d'événement du HUD (GDD §10.2, §2.4, §9.4), fonction PURE.
-- Priorité de l'affichage : Comète (alerte, au sol, portée : « ☄ COMÈTE 0:45 — Mira ») > Nuit de la
-- Balise (alerte puis trêve, avec la barre de serveur points / objectif) > Starfall Frenzy > Starfall
-- Saturday > boost de serveur (Nuit d'Or, Glow Party) > météo en cours > PROCHAIN événement
-- (EventClock.nextEvent : « ☄ 3:12 », en gris).
-- L'état vient du serveur (EventState via WorldStateController) ; le prochain événement de
-- l'horloge commune, identique sur tous les serveurs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Types = require(Shared.Types)
local EventClock = require(Shared.Logic.EventClock)
local Format = require(Shared.Util.Format)

local EventPill = {}

export type PillState = {
	kind: string, -- "comet" | "beacon" | "frenzy" | "starfall" | "boost" | "weather" | "next"
	key: string, -- clé de localisation "hud.event.*"
	vars: { [string]: any },
	color: Color3,
	active: boolean, -- événement en cours (couleur vive) ; false = prochain événement (gris)
	blink: boolean, -- clignotement (alerte de Comète)
	bar: { points: number, goal: number }?, -- barre de la Balise
}

EventPill.Colors = {
	comet = Color3.fromRGB(255, 205, 60),
	beacon = Color3.fromRGB(90, 230, 255),
	frenzy = Color3.fromRGB(255, 120, 190),
	starfall = Color3.fromRGB(255, 170, 240),
	boost = Color3.fromRGB(255, 208, 72),
	next = Color3.fromRGB(190, 184, 220),
	weather = {
		aurora = Color3.fromRGB(150, 255, 200),
		frost = Color3.fromRGB(170, 220, 255),
		solar = Color3.fromRGB(255, 170, 80),
		meteor = Color3.fromRGB(255, 140, 100),
		rainbow = Color3.fromRGB(255, 150, 255),
		eclipse = Color3.fromRGB(170, 130, 230),
	} :: { [string]: Color3 },
}

local BOOST_KEYS: { [string]: string } = {
	goldenNight = "hud.event.goldenNight",
	glowParty = "hud.event.glowParty",
	liveOps = "hud.event.goldenNight",
	starfall = "hud.event.starfall",
}

local NEXT_KEYS: { [string]: string } = {
	comet = "hud.event.nextComet",
	weather = "hud.event.nextWeather",
	beacon = "hud.event.nextBeacon",
	starfall = "hud.event.nextStarfall",
}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function clock(seconds: number): string
	return Format.clock(math.max(0, math.ceil(seconds)))
end

local function weatherColor(key: string): Color3
	return EventPill.Colors.weather[key] or EventPill.Colors.next
end

-- `t` traduit les noms (météo) ; `nameOf` donne le nom affiché d'un joueur (porteur de la Comète)
function EventPill.compute(
	ev: Types.EventStatePayload?,
	now: number,
	t: (string, { [string]: any }?) -> string,
	nameOf: (number) -> string?
): PillState
	if ev ~= nil then
		local c = ev.comet
		if c ~= nil then
			if c.phase == "warn" and now < c.impactAt + 1 then
				return {
					kind = "comet",
					key = "hud.event.cometWarn",
					vars = {},
					color = EventPill.Colors.comet,
					active = true,
					blink = true,
				}
			elseif c.phase == "ground" and now < c.burstAt then
				return {
					kind = "comet",
					key = "hud.event.cometGround",
					vars = { time = clock(c.burstAt - now) },
					color = EventPill.Colors.comet,
					active = true,
					blink = false,
				}
			elseif c.phase == "carried" and now < c.burstAt then
				local carrier = c.carrierId
				local name = if finite(carrier) then nameOf(carrier :: number) else nil
				return {
					kind = "comet",
					key = "hud.event.cometCarried",
					vars = { time = clock(c.burstAt - now), name = name or "?" },
					color = EventPill.Colors.comet,
					active = true,
					blink = false,
				}
			end
		end
		local b = ev.beacon
		if b ~= nil and (b.phase == "warn" or b.phase == "active") then
			local untilAt = if b.phase == "warn" then b.startsAt else b.endsAt
			if now < untilAt then
				return {
					kind = "beacon",
					key = "hud.event.beacon",
					vars = { time = clock(untilAt - now) },
					color = EventPill.Colors.beacon,
					active = true,
					blink = b.phase == "warn",
					bar = {
						points = math.max(0, math.floor(b.points)),
						goal = math.max(1, math.floor(b.goal)),
					},
				}
			end
		end
		local frenzy = ev.frenzy
		if frenzy ~= nil and now < frenzy.endsAt then
			return {
				kind = "frenzy",
				key = "hud.event.frenzy",
				vars = { time = clock(frenzy.endsAt - now) },
				color = EventPill.Colors.frenzy,
				active = true,
				blink = false,
			}
		end
		local sf = ev.starfall
		if sf ~= nil and now >= sf.startsAt and now < sf.endsAt then
			return {
				kind = "starfall",
				key = "hud.event.starfall",
				vars = { time = clock(sf.endsAt - now) },
				color = EventPill.Colors.starfall,
				active = true,
				blink = false,
			}
		end
		local boost = ev.serverBoost
		if boost ~= nil and now < boost.endsAt then
			return {
				kind = "boost",
				key = BOOST_KEYS[boost.source] or "hud.event.goldenNight",
				vars = { time = clock(boost.endsAt - now) },
				color = EventPill.Colors.boost,
				active = true,
				blink = false,
			}
		end
		local w = ev.weather
		if w ~= nil and now >= w.startsAt and now < w.endsAt and Events.WeatherByKey[w.key] ~= nil then
			return {
				kind = "weather",
				key = "hud.event.weather",
				vars = { weather = t("weather." .. w.key), time = clock(w.endsAt - now) },
				color = weatherColor(w.key),
				active = true,
				blink = false,
			}
		end
	end
	local nextEvent = EventClock.nextEvent(now)
	return {
		kind = "next",
		key = NEXT_KEYS[nextEvent.kind] or "hud.event.nextComet",
		vars = { time = clock(nextEvent.at - now) },
		color = if nextEvent.kind == "weather" and nextEvent.key
			then weatherColor(nextEvent.key)
			else EventPill.Colors.next,
		active = false,
		blink = false,
	}
end

return EventPill
