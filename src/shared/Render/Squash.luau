--!strict
-- Squash (paquet world, docs/04 §12.2). Profils d'écrasement et d'étirement (GDD §9.1, §9.3, §9.4),
-- purs : press, perfect, land, hatch, fuse, sneeze, hop, mount, et l'animation de repos (rebond de
-- 1,2 s calé sur le PERFECT, écrasement au contact, tremblement amorti à la fréquence de l'espèce).
-- Amplitudes × 0,5 en Mouvement réduit (l'appelant passe amplitude = 0,5, ou wobbleAmp × 0,5).
-- Un profil part de (1 ; 1 ; 1), enchaîne ses étapes (échelle cible, durée, easing) et finit à
-- (1 ; 1 ; 1). Aucune instance, aucun temps lu ici : le renderer passe t (Clock.now() − départ).
-- Toute entrée bizarre (profil inconnu, NaN, ±inf) rend une échelle finie ; jamais d'erreur.

local Balance = require(script.Parent.Parent.Config.Balance)

-- Profils (GDD §9.4) : étapes { échelle (X, Y, Z), durée, style d'easing }
local PROFILES = {
	press = {
		{ 1.35, 0.60, 1.35, 0.06, "QuadOut" },
		{ 0.85, 1.25, 0.85, 0.12, "QuadOut" },
		{ 1, 1, 1, 0.35, "ElasticOut" },
	},
	perfect = {
		{ 1.45, 0.50, 1.45, 0.06, "QuadOut" },
		{ 0.85, 1.25, 0.85, 0.12, "QuadOut" },
		{ 1, 1, 1, 0.35, "ElasticOut" },
	},
	land = { { 1.3, 0.7, 1.3, 0.08, "QuadOut" }, { 1, 1, 1, 0.2, "BackOut" } },
	hatch = {
		{ 1.4, 0.6, 1.4, 0.1, "QuadOut" },
		{ 1.1, 1.1, 1.1, 0.25, "BackOut" },
		{ 1, 1, 1, 0.1, "QuadOut" },
	},
	fuse = {
		{ 0.6, 0.6, 0.6, 0.01, "Linear" },
		{ 1.25, 1.25, 1.25, 0.2, "ElasticOut" },
		{ 1, 1, 1, 0.2, "ElasticOut" },
	},
	sneeze = { { 1.5, 0.6, 1.5, 0.08, "QuadOut" }, { 1, 1, 1, 0.3, "BackOut" } },
	hop = {
		{ 0.85, 1.25, 0.85, 0.08, "QuadOut" },
		{ 1.3, 0.7, 1.3, 0.08, "QuadOut" },
		{ 1, 1, 1, 0.1, "QuadOut" },
	},
	mount = { { 1.25, 0.75, 1.25, 0.12, "QuadOut" }, { 1, 1, 1, 0.2, "BackOut" } },
}

local Squash = {}

Squash.PROFILES = PROFILES

-- Animation de repos (GDD §5.2, §9.3) : rebond de période Balance.Press.Period (celle du PERFECT,
-- sommets à offset + k × période comme Logic/PressTiming), hauteur 0,18 D au sommet ; contact au
-- sol pendant 0,1 s (écrasement (1 + a ; 1 − a ; 1 + a)) au milieu de la période ; puis tremblement
-- amorti à la fréquence de l'espèce
Squash.Idle = table.freeze({
	Period = Balance.Press.Period,
	Height = 0.18, -- × diamètre, au sommet
	Contact = 0.1, -- s au sol
	WobbleShare = 0.5, -- amplitude du tremblement après le contact (× a)
	WobbleDecay = 5, -- amortissement (1 / s)
	MinScale = 0.2, -- jamais d'échelle nulle ni négative
	MaxScale = 3,
})

-- Easings (TweenService) : x dans [0 ; 1] → progression (peut dépasser 1 : Elastic, Back)
local function ease(style: string, x: number): number
	if x <= 0 then
		return 0
	elseif x >= 1 then
		return 1
	end
	if style == "QuadOut" then
		return 1 - (1 - x) * (1 - x)
	elseif style == "QuadIn" then
		return x * x
	elseif style == "ElasticOut" then
		return 2 ^ (-10 * x) * math.sin((x * 10 - 0.75) * (2 * math.pi / 3)) + 1
	elseif style == "BackOut" then
		local c1 = 1.70158
		local c3 = c1 + 1
		local y = x - 1
		return 1 + c3 * y * y * y + c1 * y * y
	elseif style == "SineInOut" then
		return -(math.cos(math.pi * x) - 1) / 2
	end
	return x -- Linear et inconnu
end
Squash.ease = ease

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function clampScale(v: number): number
	if v ~= v then
		return 1
	end
	return math.clamp(v, Squash.Idle.MinScale, Squash.Idle.MaxScale)
end

-- Durées totales mises en cache
local DURATIONS: { [string]: number } = {}
for name, steps in PROFILES do
	local total = 0
	for _, step in steps do
		total += step[4]
	end
	DURATIONS[name] = total
end

-- (sx, sy, sz, fini) du profil à t secondes
function Squash.sample(profile: string, t: number, amplitude: number?): (number, number, number, boolean)
	local steps = if type(profile) == "string" then (PROFILES :: any)[profile] else nil
	if steps == nil or not finite(t) then
		return 1, 1, 1, true
	end
	if t <= 0 then
		return 1, 1, 1, false
	end
	local amp = if finite(amplitude) then math.clamp(amplitude :: number, 0, 2) else 1
	local fromX, fromY, fromZ = 1, 1, 1
	local elapsed = t
	for _, step in steps do
		local duration = step[4]
		if elapsed < duration then
			local k = ease(step[5], elapsed / duration)
			local x = fromX + (step[1] - fromX) * k
			local y = fromY + (step[2] - fromY) * k
			local z = fromZ + (step[3] - fromZ) * k
			return clampScale(1 + (x - 1) * amp),
				clampScale(1 + (y - 1) * amp),
				clampScale(1 + (z - 1) * amp),
				false
		end
		elapsed -= duration
		fromX, fromY, fromZ = step[1], step[2], step[3]
	end
	return 1, 1, 1, true
end

-- (sx, sy, sz, hauteur en × diamètre) de l'animation de repos. offset = décalage du rebond
-- (Logic/PressTiming.offset) : sommet à offset + k × période, contact au sol au milieu de la période.
function Squash.idle(
	t: number,
	offset: number,
	wobbleHz: number,
	wobbleAmp: number
): (number, number, number, number)
	local cfg = Squash.Idle
	local period = cfg.Period
	local tt = if finite(t) then t else 0
	local off = if finite(offset) then offset else 0
	local hz = if finite(wobbleHz) then math.clamp(wobbleHz, 0, 10) else 1
	local a = if finite(wobbleAmp) then math.clamp(wobbleAmp, 0, 0.5) else 0
	local d = (tt - off) % period -- temps depuis le dernier sommet
	if d ~= d or d < 0 or d >= period then
		d = 0
	end
	local half = period / 2
	local fromContact = math.abs(d - half) -- distance (s) au milieu du contact
	local contactHalf = cfg.Contact / 2
	if fromContact < contactHalf then
		-- au sol : écrasement (1 + a ; 1 − a ; 1 + a), maximal au milieu du contact
		local k = math.cos(math.pi * fromContact / cfg.Contact)
		return clampScale(1 + a * k), clampScale(1 - a * k), clampScale(1 + a * k), 0
	end
	-- en l'air : arc jusqu'au sommet (sinus), tremblement amorti depuis la fin du dernier contact
	local air = (fromContact - contactHalf) / (half - contactHalf)
	local height = cfg.Height * math.sin(math.pi / 2 * math.clamp(air, 0, 1))
	local since = if d > half then d - half - contactHalf else d + half - contactHalf
	local w = a * cfg.WobbleShare * math.exp(-cfg.WobbleDecay * since) * math.sin(2 * math.pi * hz * since)
	local sy = clampScale(1 + w)
	local side = clampScale(1 / math.sqrt(sy)) -- volume à peu près gardé
	return side, sy, side, height
end

-- Durée d'un profil (s)
function Squash.duration(profile: string): number
	local d = if type(profile) == "string" then DURATIONS[profile] else nil
	return d or 0
end

return Squash
