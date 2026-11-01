--!strict
-- Palette (paquet world, docs/04 §12.2). Palette du monde et préréglages d'éclairage (GDD §11.3,
-- §5.4, §9.4), purs : couleurs pastel du plateau, de la place, des rues, des collines, des maisons
-- et des ranchs libres ; préréglages « day » (jour pastel, ClockTime 14,5), « rush » (ciel rose du
-- BOOP RUSH), « moon » (nuit de la Jelly Moon), « party » (lueur dorée des fêtes) et « winter »
-- (costume « Frost & Sprinkles ») ; mélange de deux préréglages (version discrète du Rush pour un
-- nouveau : 30 %). Données lues par WorldService (couleurs) et LightingController (préréglages) ;
-- couleurs des ranchs occupés : Config/Cosmetics.RanchColors.
-- Chaque appel rend une COPIE neuve (un appelant ne peut pas abîmer la palette). Nom inconnu : « day ».
-- Aucun nombre de jeu ici : seulement des couleurs et des réglages purement graphiques, nommés.

local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)
local Quests = require(script.Parent.Parent.Config.Quests)

export type Preset = {
	clockTime: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	brightness: number,
	tint: Color3,
	atmosphereColor: Color3,
	bloom: number,
	starCount: number,
	moonSize: number,
}

-- Calque d'événement : seules les propriétés qu'un événement change (GDD §11.3)
export type Overlay = { tint: Color3?, atmosphereColor: Color3?, bloom: number? }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Palette = {}

Palette.NAMES = { "day", "rush", "moon", "party", "winter" } :: { string }

-- =============================================================================================
-- Préréglages (GDD §11.3)
-- =============================================================================================

-- Jour pastel : ClockTime 14,5 fixe, Ambient (150, 140, 170), OutdoorAmbient (190, 180, 210),
-- Brightness 2,5, Atmosphere (255, 220, 240), Bloom 0,6
local DAY: Preset = {
	clockTime = 14.5,
	ambient = rgb(150, 140, 170),
	outdoorAmbient = rgb(190, 180, 210),
	brightness = 2.5,
	tint = rgb(255, 255, 255),
	atmosphereColor = rgb(255, 220, 240),
	bloom = 0.6,
	starCount = 3000,
	moonSize = 11,
}

-- Calques des événements (s'appliquent sur le préréglage de base : jour, hiver ou Lune)
local OVERLAYS: { [string]: Overlay } = {
	-- BOOP RUSH : Tint (255, 200, 225), Atmosphere Color (255, 190, 220)
	rush = { tint = rgb(255, 200, 225), atmosphereColor = rgb(255, 190, 220) },
	-- Wobble Party / Squish Party : Tint (255, 240, 210), Bloom 0,8
	party = { tint = rgb(255, 240, 210), bloom = 0.8 },
}

local PRESETS: { [string]: Preset } = {
	day = DAY,
	rush = {
		clockTime = DAY.clockTime,
		ambient = DAY.ambient,
		outdoorAmbient = DAY.outdoorAmbient,
		brightness = DAY.brightness,
		tint = rgb(255, 200, 225),
		atmosphereColor = rgb(255, 190, 220),
		bloom = DAY.bloom,
		starCount = DAY.starCount,
		moonSize = DAY.moonSize,
	},
	-- Jelly Moon : ClockTime 0, MoonAngularSize 30, StarCount 4000, Tint (200, 190, 255),
	-- Atmosphere Color (150, 120, 220) ; ambiances relevées pour rester lisible sur une télé
	moon = {
		clockTime = 0,
		ambient = rgb(120, 110, 175),
		outdoorAmbient = rgb(130, 120, 200),
		brightness = 1.6,
		tint = rgb(200, 190, 255),
		atmosphereColor = rgb(150, 120, 220),
		bloom = 0.7,
		starCount = 4000,
		moonSize = 30,
	},
	party = {
		clockTime = DAY.clockTime,
		ambient = DAY.ambient,
		outdoorAmbient = DAY.outdoorAmbient,
		brightness = DAY.brightness,
		tint = rgb(255, 240, 210),
		atmosphereColor = DAY.atmosphereColor,
		bloom = 0.8,
		starCount = DAY.starCount,
		moonSize = DAY.moonSize,
	},
	-- Hiver « Frost & Sprinkles » : jour un peu plus frais (sucre glace, flocons côté client)
	winter = {
		clockTime = DAY.clockTime,
		ambient = rgb(150, 150, 180),
		outdoorAmbient = rgb(195, 195, 225),
		brightness = 2.6,
		tint = rgb(240, 247, 255),
		atmosphereColor = rgb(230, 235, 255),
		bloom = 0.65,
		starCount = DAY.starCount,
		moonSize = DAY.moonSize,
	},
}

-- Réglages fixes des effets (GDD §11.3), appliqués une fois par LightingController
Palette.Effects = table.freeze({
	atmosphereDensity = 0.25,
	atmosphereHaze = 1.2,
	atmosphereDecay = rgb(170, 200, 255),
	bloomSize = 20,
	bloomThreshold = 1.3,
	saturation = 0.2,
	contrast = 0.05,
})

-- Durées des transitions (s, client) : 2 s (Rush, fêtes, hiver), 4 s (Jelly Moon), fondu court en
-- Mouvement réduit
Palette.Transitions = table.freeze({
	default = 2,
	moon = 4,
	reduced = 0.5,
})

-- Part du calque du Rush pour un nouveau avant l'étape 9 (GDD §3, §9.4 : teinte à 30 %), lue dans
-- Config/Quests (source unique)
Palette.QuietRush = Quests.Onboarding.QuietSkyTint

-- =============================================================================================
-- Couleurs du monde (GDD §11.1, §11.2, §5.4) : lues par WorldService et le décor d'hiver
-- =============================================================================================

Palette.World = table.freeze({
	ground = rgb(200, 240, 210), -- plateau, herbe menthe
	hillBase = rgb(214, 238, 220),
	hills = { rgb(255, 196, 214), rgb(196, 240, 212), rgb(255, 238, 160) } :: { Color3 }, -- rose, menthe, citron
	cloud = rgb(255, 255, 255),
	plaza = rgb(255, 245, 220), -- pavés crème
	plazaBorder = rgb(255, 170, 200), -- bordure rose
	street = rgb(255, 230, 240), -- pavés roses
	sidewalk = rgb(245, 225, 240),
	megaPad = rgb(255, 200, 225),
	megaRing = rgb(255, 120, 190),
	megaRingOff = rgb(245, 190, 215), -- anneau éteint au calme (allumé de l'alerte à la fin, client)
	marble = rgb(240, 236, 245),
	shopCounter = rgb(255, 214, 165),
	shopStripes = { rgb(255, 130, 170), rgb(255, 255, 255) } :: { Color3 },
	altarCrescent = rgb(200, 190, 255),
	jarBase = rgb(170, 120, 210),
	jelly = rgb(255, 120, 200),
	jellyRest = rgb(176, 172, 186), -- jarre grise pendant la sieste de Big Plop (GDD §4.23, client)
	glass = rgb(220, 240, 255),
	stage = rgb(150, 220, 255),
	gold = rgb(255, 205, 60),
	goldWater = rgb(255, 225, 120),
	board = rgb(80, 64, 130),
	wood = rgb(200, 150, 110),
	houseBodies = {
		rgb(255, 200, 215),
		rgb(200, 230, 255),
		rgb(255, 236, 180),
		rgb(210, 245, 210),
		rgb(230, 210, 255),
		rgb(255, 215, 190),
	} :: { Color3 },
	roofs = {
		rgb(240, 110, 150),
		rgb(120, 170, 240),
		rgb(250, 170, 80),
		rgb(110, 200, 140),
		rgb(170, 130, 230),
	} :: { Color3 },
	window = rgb(255, 240, 170),
	door = rgb(170, 110, 90),
	lollipopStick = rgb(255, 255, 255),
	lollipops = { rgb(255, 120, 170), rgb(120, 200, 255), rgb(255, 210, 90) } :: { Color3 },
	bush = rgb(255, 240, 248), -- buissons-guimauves
	lampPole = rgb(255, 255, 255),
	lampBulbs = { rgb(255, 190, 220), rgb(190, 225, 255), rgb(255, 240, 170), rgb(200, 255, 220) } :: { Color3 },
	lampLight = rgb(255, 230, 200),
	meadow = rgb(170, 230, 150),
	flowers = { rgb(255, 150, 190), rgb(255, 235, 120), rgb(190, 160, 255), rgb(255, 255, 255) } :: { Color3 },
	sign = rgb(255, 250, 235),
	-- ranch
	freeRanch = Cosmetics.FreeRanchColor, -- ranch libre : gris (130, 130, 140), sans lumière
	penFloor = rgb(255, 236, 214),
	pot = rgb(255, 205, 60),
	potLid = rgb(255, 225, 120),
	vatBase = rgb(170, 140, 220),
	vatJelly = rgb(150, 235, 200),
	water = rgb(170, 225, 255),
	poolRim = rgb(255, 255, 255),
	bowl = rgb(255, 160, 200),
	bowlInside = rgb(255, 225, 235),
	cushion = rgb(255, 190, 210),
	shelf = rgb(230, 190, 150),
	fountain = rgb(255, 255, 255),
	fountainJelly = rgb(140, 220, 255),
	padIcon = rgb(255, 255, 255),
	-- hiver « Frost & Sprinkles »
	icing = rgb(250, 252, 255), -- plaques de sucre glace (Sand)
	garlands = { rgb(255, 90, 120), rgb(120, 230, 160), rgb(255, 255, 255) } :: { Color3 },
})

-- Tapis à Goûter (Config/Pads.SnackLooks aspects, niveaux 0 … 12) : tapis, motif biscuit, nombre de
-- biscuits visibles. Niveau 0 = tapis nu ; chaque niveau change la couleur et le motif.
local SNACK_LOOKS: { { mat: Color3, dots: Color3, count: number } } = {
	{ mat = rgb(255, 236, 214), dots = rgb(230, 190, 150), count = 0 }, -- 0
	{ mat = rgb(255, 228, 200), dots = rgb(210, 160, 110), count = 2 },
	{ mat = rgb(255, 220, 230), dots = rgb(200, 140, 110), count = 3 },
	{ mat = rgb(230, 240, 255), dots = rgb(190, 140, 100), count = 4 },
	{ mat = rgb(225, 250, 230), dots = rgb(170, 120, 90), count = 4 },
	{ mat = rgb(250, 240, 200), dots = rgb(240, 120, 150), count = 5 },
	{ mat = rgb(240, 225, 255), dots = rgb(120, 180, 240), count = 5 },
	{ mat = rgb(255, 210, 210), dots = rgb(250, 250, 250), count = 6 },
	{ mat = rgb(210, 240, 250), dots = rgb(255, 170, 90), count = 6 },
	{ mat = rgb(255, 235, 180), dots = rgb(150, 100, 70), count = 7 },
	{ mat = rgb(230, 210, 250), dots = rgb(255, 210, 90), count = 7 },
	{ mat = rgb(200, 245, 225), dots = rgb(255, 120, 170), count = 8 },
	{ mat = rgb(255, 215, 120), dots = rgb(255, 255, 255), count = 8 }, -- 12 : tapis doré
}
Palette.SnackDots = 8 -- biscuits au plus sur le tapis

-- Aspect du Tapis à Goûter au niveau `level` (0 … 12, borné ; valeur bizarre → 0)
function Palette.snackLook(level: number): { mat: Color3, dots: Color3, count: number }
	local n = if type(level) == "number" and level == level then math.floor(level) else 0
	local look = SNACK_LOOKS[math.clamp(n, 0, #SNACK_LOOKS - 1) + 1]
	return { mat = look.mat, dots = look.dots, count = look.count }
end

Palette.SnackLooks = #SNACK_LOOKS

-- =============================================================================================
-- API
-- =============================================================================================

local function copy(p: Preset): Preset
	return {
		clockTime = p.clockTime,
		ambient = p.ambient,
		outdoorAmbient = p.outdoorAmbient,
		brightness = p.brightness,
		tint = p.tint,
		atmosphereColor = p.atmosphereColor,
		bloom = p.bloom,
		starCount = p.starCount,
		moonSize = p.moonSize,
	}
end

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- Préréglage d'éclairage ("day", "rush", "moon", "party", "winter")
function Palette.preset(name: string): Preset
	local p = if type(name) == "string" then PRESETS[name] else nil
	return copy(p or DAY)
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Mélange de deux préréglages (teinte à 30 % pour un nouveau)
function Palette.blend(a: Preset, b: Preset, alpha: number): Preset
	local t = math.clamp(finite(alpha, 0), 0, 1)
	return {
		clockTime = lerpNumber(a.clockTime, b.clockTime, t),
		ambient = a.ambient:Lerp(b.ambient, t),
		outdoorAmbient = a.outdoorAmbient:Lerp(b.outdoorAmbient, t),
		brightness = lerpNumber(a.brightness, b.brightness, t),
		tint = a.tint:Lerp(b.tint, t),
		atmosphereColor = a.atmosphereColor:Lerp(b.atmosphereColor, t),
		bloom = lerpNumber(a.bloom, b.bloom, t),
		starCount = math.floor(lerpNumber(a.starCount, b.starCount, t) + 0.5),
		moonSize = lerpNumber(a.moonSize, b.moonSize, t),
	}
end

-- Calque d'un événement ("rush" | "party") appliqué à `alpha` (0 … 1) sur un préréglage de base :
-- seules les propriétés de l'événement changent (le Rush pendant une Jelly Moon garde la nuit).
-- Fonction ajoutée (LightingController).
function Palette.overlay(base: Preset, name: string, alpha: number?): Preset
	local out = copy(base)
	local o = if type(name) == "string" then OVERLAYS[name] else nil
	if o == nil then
		return out
	end
	local t = math.clamp(finite(alpha, 1), 0, 1)
	if o.tint then
		out.tint = base.tint:Lerp(o.tint, t)
	end
	if o.atmosphereColor then
		out.atmosphereColor = base.atmosphereColor:Lerp(o.atmosphereColor, t)
	end
	if o.bloom then
		out.bloom = lerpNumber(base.bloom, math.max(base.bloom, o.bloom), t)
	end
	return out
end

-- Couleur d'un ranch : couleur du propriétaire (Config/Cosmetics.RanchColors) ou gris s'il est libre
-- (fonction ajoutée : WorldService)
function Palette.ranchColor(slot: number, occupied: boolean): Color3
	if not occupied then
		return Cosmetics.FreeRanchColor
	end
	return Cosmetics.RanchColors[slot] or Cosmetics.FreeRanchColor
end

return Palette
