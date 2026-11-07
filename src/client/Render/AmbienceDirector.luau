--!strict
-- AmbienceDirector (lot B4, étape 2 ; docs/04 §27.7, N12 ; GDD v2.0 §11.3 ; décisions D2, D3, D4 du plan
-- B4). SEUL module du client qui touche le service Lighting (Static_LightingWriter le vérifie), dans les
-- deux états de l'interrupteur Ambience :
--   * v1.3 (Ambience coupé, la version livrée) : le code d'écriture de LightingController déplacé tel
--     quel — effets SquishyAtmosphere, SquishyBloom, SquishyColor, SquishySky créés une fois, un seul
--     tween par instance (le nouveau annule l'ancien), apply(preset, duration) avec ClockTime qui avance
--     toujours (jamais à reculons) ; LightingController garde le choix du préréglage (resolve), la
--     cadence de 0,5 s, la musique, les étiquettes, les lumières et le costume d'hiver, et appelle
--     apply : mêmes valeurs, mêmes durées, même ordre qu'avant (AmbienceDirector.spec, trace de la v1.3) ;
--   * v2.0 (Ambience ouvert, EventState.features.ambience) : setStack(stack, now) résout la pile à
--     priorités (Logic/AmbienceRules : Jelly Moon > BOOP RUSH > alerte et MEGA > fêtes > météo >
--     costume de saison > jour) en un aspect COMPLET (aucun calque) : préréglages de la v1.3 tirés de
--     Render/Palette (jour, Lune, Rush, Rush discret à 30 %, fêtes, hiver), plus « mega » et les 4 météos
--     définis ici ; transitions de 2 s, 4 s vers ou depuis la Lune et une météo, et 4 s en Mouvement
--     réduit, tout interpolé (ciel compris : aucun saut de propriété, aucun flash) ;
--   * éclairage unifié (D2) : setStyle(true) garde LightingStyle et PrioritizeLightingQuality de la
--     place puis pose Soft et false ; setStyle(false) rend les valeurs gardées. Le fichier de la place
--     ne change qu'à l'étape I (même commit que Ambience = true) : interrupteur coupé, ces deux
--     propriétés ne sont jamais écrites.
-- Aucun travail par image : le directeur n'écrit qu'à l'appel (LightingController, toutes les 0,5 s au
-- plus, et seulement quand le préréglage change). Jamais d'erreur : une entrée illisible donne le jour.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Palette = require(Shared.Render.Palette)
local AmbienceRules = require(Shared.Logic.AmbienceRules)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)

local AmbienceDirector = {}

-- Aspect complet d'un préréglage v2.0 : celui de Palette plus la saturation (arc-en-ciel)
export type Look = {
	clockTime: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	brightness: number,
	tint: Color3,
	atmosphereColor: Color3,
	bloom: number,
	starCount: number,
	moonSize: number,
	saturation: number,
}
export type Effects = {
	atmosphere: Atmosphere,
	bloom: BloomEffect,
	color: ColorCorrectionEffect,
	sky: Sky,
}
export type Stats = {
	writes: number, -- écritures directes de propriétés (Lighting et ses effets)
	tweens: number, -- tweens créés
	current: string, -- préréglage affiché
	v2: boolean, -- le préréglage affiché vient de la pile (Ambience ouvert)
	style: boolean, -- éclairage unifié posé par le directeur
	changes: number, -- changements de préréglage de la pile
}

-- Transitions de la pile (s, réglages purement graphiques) : 2 s, 4 s vers ou depuis la Lune ou une
-- météo, 4 s en Mouvement réduit (fondu lent sans flash ; la v1.3 garde son fondu court)
local V2_DEFAULT = Palette.Transitions.default -- 2
local V2_SLOW = Palette.Transitions.moon -- 4
local V2_REDUCED = 4
local WINTER_PREFIX = "winter" -- costumes d'hiver (Events.Costumes) : aspect « winter » de Palette
local WEATHER_PREFIX = "weather."
local COSTUME_PREFIX = "costume."

local state = {
	effects = nil :: Effects?,
	tweens = {} :: { [Instance]: Tween },
	current = "day",
	v2 = false,
	style = false,
	savedStyle = nil :: EnumItem?,
	savedQuality = nil :: boolean?,
	writes = 0,
	tweensMade = 0,
	changes = 0,
	changedAt = 0,
}

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- =============================================================================================
-- Aspects de la pile (v2.0)
-- =============================================================================================

local function look(p: Palette.Preset, over: { [string]: any }?): Look
	local out: Look = {
		clockTime = p.clockTime,
		ambient = p.ambient,
		outdoorAmbient = p.outdoorAmbient,
		brightness = p.brightness,
		tint = p.tint,
		atmosphereColor = p.atmosphereColor,
		bloom = p.bloom,
		starCount = p.starCount,
		moonSize = p.moonSize,
		saturation = Palette.Effects.saturation,
	}
	if over then
		for key, value in over do
			(out :: any)[key] = value
		end
	end
	return table.freeze(out)
end

local DAY = Palette.preset("day")

-- Préréglages complets (D4) : la v1.3 de Palette garde ses valeurs ; alerte et MEGA et les météos sont
-- des touches légères sur le jour (valeurs réglables, journal B4)
local LOOKS: { [string]: Look } = table.freeze({
	day = look(DAY),
	moon = look(Palette.preset("moon")),
	rush = look(Palette.preset("rush")),
	-- Rush d'un nouveau venu avant l'étape 9 : le calque du Rush à 30 % (Palette.QuietRush) sur le jour
	["rush.quiet"] = look(Palette.overlay(Palette.preset("day"), "rush", Palette.QuietRush)),
	party = look(Palette.preset("party")),
	winter = look(Palette.preset("winter")),
	-- alerte et MEGA : lumière plus chaude, un peu plus de halo
	mega = look(DAY, { tint = Color3.fromRGB(255, 235, 220), bloom = 0.7 }),
	-- météos (purement visuelles, EventState.weather)
	["weather.sunny"] = look(DAY, { brightness = DAY.brightness + 0.3, bloom = 0.7 }),
	["weather.sprinkles"] = look(DAY, { tint = Color3.fromRGB(255, 240, 250) }),
	["weather.bubbles"] = look(DAY, { atmosphereColor = Color3.fromRGB(220, 240, 255) }),
	["weather.rainbow"] = look(DAY, { saturation = 0.3 }),
})

-- Aspect d'un nom de préréglage (AmbienceRules.preset) : costume d'hiver → « winter » ; nom inconnu →
-- jour. L'aspect rendu est figé (ne pas le modifier).
function AmbienceDirector.look(name: string): Look
	if type(name) ~= "string" then
		return LOOKS.day
	end
	local found = LOOKS[name]
	if found then
		return found
	end
	if string.sub(name, 1, #COSTUME_PREFIX) == COSTUME_PREFIX then
		local id = string.sub(name, #COSTUME_PREFIX + 1)
		if string.sub(id, 1, #WINTER_PREFIX) == WINTER_PREFIX then
			return LOOKS.winter
		end
	end
	return LOOKS.day
end

local function slow(name: string): boolean
	return name == "moon" or string.sub(name, 1, #WEATHER_PREFIX) == WEATHER_PREFIX
end

-- Durée d'une transition de la pile (pure) : 2 s ; 4 s vers ou depuis la Lune ou une météo ; 4 s en
-- Mouvement réduit
function AmbienceDirector.transition(from: string, to: string, reduced: boolean?): number
	if reduced == true then
		return V2_REDUCED
	end
	if (type(from) == "string" and slow(from)) or (type(to) == "string" and slow(to)) then
		return V2_SLOW
	end
	return V2_DEFAULT
end

local function reducedMotion(): boolean
	local ok, value = pcall(Prefs.reducedMotion)
	return ok and value == true
end

-- =============================================================================================
-- Effets d'éclairage (code de la v1.3, déplacé tel quel de LightingController)
-- =============================================================================================

local function findOrCreate(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

local function ensureEffects()
	if state.effects then
		return state.effects
	end
	local fx = Palette.Effects
	local atmosphere = findOrCreate("Atmosphere", "SquishyAtmosphere") :: Atmosphere
	atmosphere.Density = fx.atmosphereDensity
	atmosphere.Haze = fx.atmosphereHaze
	atmosphere.Decay = fx.atmosphereDecay
	local bloom = findOrCreate("BloomEffect", "SquishyBloom") :: BloomEffect
	bloom.Size = fx.bloomSize
	bloom.Threshold = fx.bloomThreshold
	local color = findOrCreate("ColorCorrectionEffect", "SquishyColor") :: ColorCorrectionEffect
	color.Saturation = fx.saturation
	color.Contrast = fx.contrast
	local sky = findOrCreate("Sky", "SquishySky") :: Sky
	local effects = { atmosphere = atmosphere, bloom = bloom, color = color, sky = sky }
	state.effects = effects
	state.writes += 7
	return effects
end

local function tweenTo(inst: Instance, duration: number, goals: { [string]: any })
	local previous = state.tweens[inst]
	if previous then
		previous:Cancel()
	end
	if duration <= 0 then
		for key, value in goals do
			(inst :: any)[key] = value
			state.writes += 1
		end
		state.tweens[inst] = nil
		return
	end
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		goals
	)
	state.tweens[inst] = tween
	state.tweensMade += 1
	tween:Play()
end

-- Sortie de la pile (Ambience coupé) : le tween du ciel est arrêté (la v1.3 écrit le ciel directement ;
-- un tween encore en cours écraserait ses valeurs) et la saturation reprend son réglage fixe
local function leaveStack()
	local fx = ensureEffects()
	local skyTween = state.tweens[fx.sky]
	if skyTween then
		skyTween:Cancel()
		state.tweens[fx.sky] = nil
	end
	tweenTo(fx.color, 0, { Saturation = Palette.Effects.saturation })
	state.v2 = false
end

-- Applique un préréglage de la v1.3 (duration 0 : immédiat)
local function apply(preset: Palette.Preset, duration: number)
	local fx = ensureEffects()
	-- ClockTime avance toujours (coucher puis lever du soleil), jamais à reculons
	local current = finite(Lighting.ClockTime, preset.clockTime) % 24
	local target = preset.clockTime
	if duration > 0 and target < current - 1e-6 then
		target += 24
	end
	tweenTo(Lighting, duration, {
		ClockTime = target,
		Ambient = preset.ambient,
		OutdoorAmbient = preset.outdoorAmbient,
		Brightness = preset.brightness,
	})
	tweenTo(fx.atmosphere, duration, { Color = preset.atmosphereColor })
	tweenTo(fx.color, duration, { TintColor = preset.tint })
	tweenTo(fx.bloom, duration, { Intensity = preset.bloom })
	fx.sky.StarCount = preset.starCount
	fx.sky.MoonAngularSize = preset.moonSize
	state.writes += 2
end

-- Applique un aspect de la pile : tout interpolé, ciel compris (aucun saut de propriété)
local function applyLook(l: Look, duration: number)
	local fx = ensureEffects()
	local current = finite(Lighting.ClockTime, l.clockTime) % 24
	local target = l.clockTime
	if duration > 0 and target < current - 1e-6 then
		target += 24
	end
	tweenTo(Lighting, duration, {
		ClockTime = target,
		Ambient = l.ambient,
		OutdoorAmbient = l.outdoorAmbient,
		Brightness = l.brightness,
	})
	tweenTo(fx.atmosphere, duration, { Color = l.atmosphereColor })
	tweenTo(fx.color, duration, { TintColor = l.tint, Saturation = l.saturation })
	tweenTo(fx.bloom, duration, { Intensity = l.bloom })
	tweenTo(fx.sky, duration, { StarCount = l.starCount, MoonAngularSize = l.moonSize })
end

-- Écrit une propriété de Lighting seulement si elle change ; un moteur qui ne la connaît pas : rien
-- (jamais d'erreur ni d'avertissement)
local function writeLighting(key: string, value: any)
	local ok, wrote = pcall(function(): boolean
		if (Lighting :: any)[key] == value then
			return false
		end
		(Lighting :: any)[key] = value
		return true
	end)
	if ok and wrote then
		state.writes += 1
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Effets d'éclairage (créés une fois, mêmes noms qu'en v1.3)
function AmbienceDirector.effects(): Effects
	return ensureEffects()
end

-- Préréglage de la v1.3 (LightingController.resolve) : chemin livré, Ambience coupé. `name` : nom
-- du préréglage affiché (stats). Si la pile était affichée, elle est quittée d'abord.
function AmbienceDirector.apply(preset: Palette.Preset, duration: number, name: string?)
	if state.v2 then
		leaveStack()
	end
	apply(preset, duration)
	if type(name) == "string" then
		state.current = name
	end
end

-- Pile v2.0 (Ambience ouvert) : préréglage de la couche la plus haute, appliqué seulement s'il change
-- (même pile : aucune écriture). `instant` : première évaluation (comme la v1.3 : sans transition).
-- stack = nil : la pile est quittée (Ambience coupé en direct). Rend le nom affiché.
function AmbienceDirector.setStack(stack: AmbienceRules.Stack?, now: number, instant: boolean?): string
	if stack == nil then
		if state.v2 then
			leaveStack()
		end
		return state.current
	end
	local name = AmbienceRules.preset(stack)
	if state.v2 and name == state.current then
		return name
	end
	local duration = if instant == true
		then 0
		else AmbienceDirector.transition(state.current, name, reducedMotion())
	applyLook(AmbienceDirector.look(name), duration)
	state.current = name
	state.v2 = true
	state.changes += 1
	state.changedAt = finite(now, 0)
	return name
end

-- Éclairage unifié (D2) : true garde LightingStyle et PrioritizeLightingQuality de la place puis pose
-- Soft et false ; false rend les valeurs gardées. Même état : aucune écriture.
function AmbienceDirector.setStyle(on: boolean)
	local want = on == true
	if want == state.style then
		return
	end
	if want then
		local ok, style, quality = pcall(function(): (any, any)
			return (Lighting :: any).LightingStyle, (Lighting :: any).PrioritizeLightingQuality
		end)
		state.savedStyle = if ok and typeof(style) == "EnumItem" then style else nil
		state.savedQuality = if ok and type(quality) == "boolean" then quality else nil
		writeLighting("LightingStyle", Enum.LightingStyle.Soft)
		writeLighting("PrioritizeLightingQuality", false)
	else
		-- valeur illisible à la prise (moteur sans la propriété) : rien à rendre
		if state.savedStyle ~= nil then
			writeLighting("LightingStyle", state.savedStyle)
		end
		if state.savedQuality ~= nil then
			writeLighting("PrioritizeLightingQuality", state.savedQuality)
		end
		state.savedStyle = nil
		state.savedQuality = nil
	end
	state.style = want
end

-- Préréglage affiché
function AmbienceDirector.current(): string
	return state.current
end

-- Compteurs (specs : aucune écriture à pile égale, aucun travail par image)
function AmbienceDirector.stats(): Stats
	return {
		writes = state.writes,
		tweens = state.tweensMade,
		current = state.current,
		v2 = state.v2,
		style = state.style,
		changes = state.changes,
	}
end

return AmbienceDirector
