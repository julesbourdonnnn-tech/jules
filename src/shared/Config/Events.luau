--!strict
-- Horloge commune et événements (GDD §2.4, §4.15, §5.1, §7.6, §11.5). Contrat : docs/04-architecture.md §9.
-- Toutes les phases sont des fonctions pures du temps UTC (Logic/EventClock) : même résultat
-- sur tous les serveurs et tous les clients.

local Events = {}

-- Calendrier UTC (le 01/01/1970 était un jeudi ; les semaines commencent le lundi 00:00 UTC)
Events.Calendar = {
	Day = 86400,
	Week = 604800,
	WeekEpoch = 345600, -- w = floor((t − WeekEpoch) / Week)
	WeekdayOffset = 4, -- weekday = (floor(t / Day) + 4) % 7 ; 0 = dimanche … 6 = samedi
}

-- Sels du hachage déterministe (Logic/Hash) : un sel par tirage, jamais réutilisé
Events.Salts = {
	Weather = 0x57E4,
	CometPoint = 0xC0DE,
	CometRarity = 0xC0FF,
	CometSpecies = 0xC0F1,
	CometSky = 0xC05C,
	DailyQuest = 0xDA17,
	Reroll = 0x2E21,
	Wisp = 0x3159,
	Scatter = 0x5CA7,
	Spawn = 0x5A3E,
	Decor = 0xDEC0,
}

export type WeatherDef = {
	key: string, -- "weather.<key>"
	weight: number,
	form: number?, -- forme donnée à 40 % des apparitions (nil = Meteor Shower)
	intervalDiv: number?, -- intervalles d'apparition ÷
	capMult: number?, -- plafonds ×
	lighting: string, -- préréglage Events.Lighting.Presets
	version: string,
}

-- Météo (§4.15.1) : créneau = floor(t / Period), fenêtre [début + Offset, début + Offset + Duration[
Events.Weather = {
	Period = 360,
	Offset = 120,
	Duration = 150,
	-- Poids MVP (somme 100). Eclipse (v1.1) : poids 10, les autres réduits proportionnellement
	-- (le tirage normalise par la somme des poids activés).
	Kinds = {
		{ key = "aurora", weight = 30, form = 1, lighting = "aurora", version = "mvp" },
		{ key = "frost", weight = 26, form = 2, lighting = "frost", version = "mvp" },
		{ key = "solar", weight = 20, form = 3, lighting = "solar", version = "mvp" },
		{ key = "meteor", weight = 17, intervalDiv = 3, capMult = 1.5, lighting = "meteor", version = "mvp" },
		{ key = "rainbow", weight = 7, form = 5, lighting = "rainbow", version = "mvp" },
		{ key = "eclipse", weight = 10, form = 4, lighting = "eclipse", version = "v1.1" },
	} :: { WeatherDef },
}

Events.WeatherByKey = {} :: { [string]: WeatherDef }
for _, def in Events.Weather.Kinds do
	Events.WeatherByKey[def.key] = def
end

-- Grande Comète (§4.15.2) : impact à chaque multiple de Period (:00, :10, :20…)
Events.Comet = {
	Period = 600,
}

-- Nuit de la Balise (§4.15.3) : :25:00-:28:00 et :55:00-:58:00
Events.Beacon = {
	Period = 1800,
	Offset = 1500,
}

-- Starfall Saturday (§4.15.5) : samedi 16:00-16:20 UTC
Events.Starfall = {
	Weekday = 6,
	StartSecond = 16 * 3600,
	Duration = 1200,
	CometEvery = 180, -- 16:00, 16:03 … 16:18 (7 comètes)
	Weather = "rainbow",
	FeaturedChance = 0.25, -- part des apparitions de l'espèce vedette
	StarbornChance = 0.08, -- parmi elles, variante Starborn
	PresenceSeconds = 300, -- présent ≥ 5 min → 1 vedette Starborn garantie
	BoostSeconds = 1200, -- boost ×2 de serveur
}

-- Rotations déterministes (§5.1) : indice = w mod #table
Events.Rotations = {
	WeeklyWanderer = { 23, 24, 25, 26, 27 },
	GrandParadeLegendary = { 29, 30, 31 },
	FeaturedSpecies = { 1, 9, 16, 23, 4, 12, 19, 25, 6, 14, 21, 27 },
}

-- LiveOps (§7.6) : commandes autorisées depuis Data/Admins (remote AdminCommand + MessagingService)
Events.LiveOps = {
	Topic = "LiveOps",
	Commands = {
		comet = true, -- Comète supplémentaire (impact dans WarnSeconds)
		weather = true, -- "weather:<clé>" : fenêtre météo forcée de Weather.Duration
		frenzy = true, -- Starfall Frenzy immédiat
		goldenNight = true, -- Nuit d'Or immédiate
	} :: { [string]: boolean },
}

export type LightingPreset = {
	Tint: Color3?, -- ColorCorrection.TintColor
	AtmosphereColor: Color3?,
	AtmosphereDecay: Color3?,
	Haze: number?,
	Bloom: number?,
	Brightness: number?,
	MoonAngularSize: number?,
	ClockTime: number?,
	StarCount: number?,
	OutdoorAmbientMult: number?,
	HsvTintCycle: number?, -- s (Rainbow)
	HsvTintSaturation: number?,
	BeaconBeamMult: number?,
	Effect: string?, -- effet client additionnel
}

-- Éclairage (§11.5) : base posée par le serveur (World/Lighting), cycle et préréglages par le client
Events.Lighting = {
	Cycle = {
		Period = 720, -- ClockTime = Min + Amplitude × (0,5 − 0,5 cos(2π t / Period))
		Min = 17.6,
		Amplitude = 2.9,
	},
	Base = {
		Ambient = Color3.fromRGB(110, 95, 140),
		OutdoorAmbient = Color3.fromRGB(150, 130, 190),
		Brightness = 2,
		StarCount = 3000,
		MoonAngularSize = 30,
		SunAngularSize = 15,
		AtmosphereDensity = 0.3,
		AtmosphereOffset = 0.25,
		AtmosphereColor = Color3.fromRGB(199, 170, 255),
		AtmosphereDecay = Color3.fromRGB(106, 112, 255),
		AtmosphereGlare = 0.4,
		AtmosphereHaze = 1.6,
		BloomIntensity = 0.8,
		BloomSize = 24,
		BloomThreshold = 1.2,
		Saturation = 0.15,
		Contrast = 0.05,
		SunRays = 0.05,
		CloudCover = 0.6,
		CloudColor = Color3.fromRGB(220, 200, 255),
	},
	TweenSeconds = 3,
	Presets = {
		aurora = {
			Tint = Color3.fromRGB(215, 255, 235),
			AtmosphereColor = Color3.fromRGB(170, 255, 210),
			AtmosphereDecay = Color3.fromRGB(150, 90, 255),
			Effect = "auroraCurtains", -- 6 rideaux Beam vert-violet
		},
		frost = {
			Haze = 2.4,
			AtmosphereColor = Color3.fromRGB(220, 235, 255),
			Tint = Color3.fromRGB(225, 240, 255),
			Effect = "snow", -- 60 / s, vitesse 4-6, durée 6 s
		},
		solar = {
			Tint = Color3.fromRGB(255, 225, 190),
			AtmosphereColor = Color3.fromRGB(255, 190, 150),
			Bloom = 1.1,
		},
		meteor = {
			Effect = "meteorStreaks", -- réserve de 10, un toutes les 0,4 s
		},
		rainbow = {
			HsvTintCycle = 8,
			HsvTintSaturation = 0.12,
			Effect = "rainbowArcs", -- 5 arcs Beam
		},
		eclipse = {
			Brightness = 1.2,
			Tint = Color3.fromRGB(190, 170, 255),
			MoonAngularSize = 20,
		},
		beacon = {
			ClockTime = 21.5,
			StarCount = 5000,
			BeaconBeamMult = 3,
		},
		cometWarn = {
			OutdoorAmbientMult = 0.7, -- −30 % en 2 s
		},
		goldenNight = {
			Tint = Color3.fromRGB(255, 235, 180),
			Bloom = 1.0,
		},
	} :: { [string]: LightingPreset },
}

return Events
