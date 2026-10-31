--!strict
-- LightingController — paquet « world » (docs/04-architecture.md §13.4).
-- Ambiance animée CÔTÉ CLIENT à partir de l'horloge commune, sans réplication (GDD §11.5, §9.4).
--   * cycle crépuscule ↔ nuit de 12 min : ClockTime = 17,6 + 2,9 × (0,5 − 0,5 cos(2π t / 720)),
--     t = Clock.now() (Events.Lighting.Cycle) ; une seule connexion RenderStepped
--   * préréglages Events.Lighting.Presets, chacun avec un poids 0 → 1 adouci en Sine InOut
--     (Events.Lighting.TweenSeconds = 3 s à l'aller comme au retour ; Nuit de la Balise 4 s,
--     alerte Comète 2 s) ; plusieurs préréglages se superposent (météo + Nuit d'Or + alerte…)
--   * effets clients dans workspace.ClientSky (Render/SkyFX) : rideaux d'aurore, neige qui suit la
--     caméra, traits de météores, arcs-en-ciel ; teinte HSV de la Rainbow Comet
--   * Nuit de la Balise : ClockTime 21,5, StarCount 5000, anneaux « BeaconRing » allumés un à un
--     (0,1 s chacun), faisceau ×3, anneau « BeaconDeposit » qui pousse ; réussite : flash des
--     anneaux (sauf Mouvement réduit) ; échec : bouffée bleue puis extinction (1 s)
--   * alerte Comète : OutdoorAmbient −30 % en 2 s ; Nuit d'Or : éclairage doré
--   * sources : EventClock (météo, Balise, Comète : déterministes) et le signal EventChanged de
--     WorldStateController (météo forcée par LiveOps, Balise, Nuit d'Or, Comète supplémentaire) ;
--     l'instantané d'arrivée pose les préréglages en cours sans fondu ; un appel défaillant est
--     signalé au plus une fois toutes les 10 s et ne bloque jamais l'image
--   * Graphismes légers : effets réduits, lumières des lanternes et cristaux coupées au-delà de
--     60 studs ; Mouvement réduit : pas de flash, apparitions sans animation
-- GDD : §11.5, §9.4 (Météo, Balise, Comète), §9.1 (réglages), §12.8 (lumières).
-- Dépendances : Util/Prefs, WorldStateController, UI/Juice, Logic/EventClock, Config/Events,
-- Config/Zones, Config/Balance, Render/SkyFX, Shared/Util/Clock.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Zones = require(Shared.Config.Zones)
local Types = require(Shared.Types)
local EventClock = require(Shared.Logic.EventClock)
local SkyFX = require(Shared.Render.SkyFX)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Juice = require(Client.UI.Juice)
local WorldStateController = require(Client.Controllers.WorldStateController)

local LightingController = {}

-- Constantes (GDD §9.4, §11.5) -------------------------------------------------------------------

local EVAL_INTERVAL = 0.25 -- s : réévaluation des préréglages actifs
local LIGHTS_INTERVAL = 0.5 -- s : lumières des lanternes / cristaux (Graphismes légers)
local WARN_INTERVAL = 10 -- s : un avertissement au plus par étape
local BLEND_SECONDS: { [string]: number } = {
	beacon = 4, -- « ClockTime → 21,5 en 4 s »
	cometWarn = 2, -- « lumière ambiante −30 % en 2 s »
}
local RING_STEP = 0.1 -- s : anneaux de la Balise allumés un à un
local RING_DIM = 0.45 -- anneau éteint : couleur × 0,45, sans Néon
local RING_FLASH = Color3.new(1, 1, 1)
local RING_FAIL = Color3.fromRGB(90, 140, 255)
local FAIL_SECONDS = 1
local FLASH_SECONDS = 0.15
local DEPOSIT_GROW = 0.4
local DEPOSIT_SHRINK = 0.3
local STAR_QUANTUM = 100 -- StarCount écrit par paliers (régénération du ciel)
local EPSILON = 1e-3
local COLOR_EPSILON = 1 / 512
local GOLDEN_SOURCES = { goldenNight = true, liveOps = true }

-- Ordre de superposition (le dernier l'emporte) et priorité de currentPreset()
local LAYER_ORDER =
	{ "aurora", "frost", "solar", "meteor", "rainbow", "eclipse", "goldenNight", "beacon", "cometWarn" }
local PRIORITY = { "beacon", "cometWarn", "goldenNight" }

-- État ----------------------------------------------------------------------------------------------

type Values = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	StarCount: number,
	MoonAngularSize: number,
	SunAngularSize: number,
	AtmosphereColor: Color3,
	AtmosphereDecay: Color3,
	Density: number,
	Offset: number,
	Glare: number,
	Haze: number,
	Bloom: number,
	BloomSize: number,
	BloomThreshold: number,
	Saturation: number,
	Contrast: number,
	SunRays: number,
	Tint: Color3,
	BeamWidth: number,
}

local order: { string } = {}
local desired: { [string]: boolean } = {}
local weights: { [string]: number } = {}
local effects: { [string]: SkyFX.Effect } = {}
local forced: string? = nil
local started = false
local connection: RBXScriptConnection? = nil
local evalTimer = 0
local lightsTimer = 0
local lastWarn: { [string]: number } = {}
local written: { [string]: any } = {}
local writtenTo: { [string]: Instance } = {}
local values: Values = nil :: any
local rng = Random.new()
local skyFolder: Folder? = nil

local rings: { BasePart } = {}
local ringLit = 0
local ringTimer = 0
local puffTimer = 0 -- bouffée bleue d'échec en cours : les anneaux ne sont pas repeints
local beaconOn = false
local deposit: BasePart? = nil
local depositSize: Vector3? = nil
local beam: Beam? = nil
local lights: { [BasePart]: boolean } = {}

-- Aides -----------------------------------------------------------------------------------------

local function warnThrottled(stage: string, err: any)
	local t = os.clock() -- mesure purement technique (fréquence des avertissements)
	local last = lastWarn[stage]
	if last == nil or t - last >= WARN_INTERVAL then
		lastWarn[stage] = t
		warn(`[LightingController] {stage} :`, err)
	end
end

local function ease(w: number): number
	return 0.5 - 0.5 * math.cos(math.pi * w)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function scaleColor(c: Color3, k: number): Color3
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local function blendSeconds(key: string): number
	return BLEND_SECONDS[key] or Events.Lighting.TweenSeconds
end

local function finite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

local function buildOrder()
	table.clear(order)
	local seen = {}
	for _, key in LAYER_ORDER do
		if Events.Lighting.Presets[key] then
			table.insert(order, key)
			seen[key] = true
		end
	end
	local extra = {}
	for key in Events.Lighting.Presets do
		if not seen[key] then
			table.insert(extra, key)
		end
	end
	table.sort(extra)
	for _, key in extra do
		table.insert(order, key)
	end
end

-- Sources d'événements ------------------------------------------------------------------------

-- Dernier état d'événements reçu de WorldStateController.EventChanged (seul abonné du remote
-- EventState) ; nil tant que l'instantané d'arrivée n'est pas là
local lastEvents: Types.EventStatePayload? = nil
local arrived = false

local function clockCall<T>(stage: string, fn: (number) -> T, now: number): T?
	local ok, result = pcall(fn, now)
	if not ok then
		warnThrottled(stage, result)
		return nil
	end
	return result
end

-- Fenêtre [from, to[ bien formée et contenant now (charge incomplète → faux, jamais d'erreur)
local function within(now: number, from: any, to: any): boolean
	return type(from) == "number" and type(to) == "number" and now >= from and now < to
end

local function weatherKey(ev: Types.EventStatePayload?, now: number): string?
	local w = if ev then ev.weather else nil
	if type(w) == "table" and type(w.key) == "string" and within(now, w.startsAt, w.endsAt) then
		return w.key
	end
	local window = clockCall("EventClock.weather", EventClock.weather, now)
	return if window then window.key else nil
end

local function beaconNight(ev: Types.EventStatePayload?, now: number): boolean
	local b = if ev then ev.beacon else nil
	if type(b) == "table" and within(now, b.startsAt, b.endsAt) then
		return true
	end
	local window = clockCall("EventClock.beacon", EventClock.beacon, now)
	return window ~= nil and within(now, window.startsAt, window.endsAt)
end

local function goldenNight(ev: Types.EventStatePayload?, now: number): boolean
	local boost = if ev then ev.serverBoost else nil
	return type(boost) == "table"
		and GOLDEN_SOURCES[boost.source] == true
		and type(boost.endsAt) == "number"
		and now < boost.endsAt
end

local function cometWarning(ev: Types.EventStatePayload?, now: number): boolean
	local c = if ev then ev.comet else nil
	if type(c) == "table" and c.phase == "warn" and within(now, c.warnAt, c.impactAt) then
		return true
	end
	local slot = clockCall("EventClock.comet", EventClock.comet, now)
	return slot ~= nil and within(now, slot.warnAt, slot.impactAt)
end

local function evaluate(now: number)
	table.clear(desired)
	local f = forced
	if f then
		desired[f] = true
		return
	end
	local ev = lastEvents
	local key = weatherKey(ev, now)
	if key then
		local def = Events.WeatherByKey[key]
		if def and Events.Lighting.Presets[def.lighting] then
			desired[def.lighting] = true
		end
	end
	if beaconNight(ev, now) then
		desired.beacon = true
	end
	if goldenNight(ev, now) then
		desired.goldenNight = true
	end
	if cometWarning(ev, now) then
		desired.cometWarn = true
	end
end

-- Cibles Roblox ------------------------------------------------------------------------------------

local function lightingChild(className: string): Instance?
	return Lighting:FindFirstChildOfClass(className)
end

local function resolveBeacon()
	local b = beam
	if b == nil or b.Parent == nil then
		beam = nil
		for _, model in CollectionService:GetTagged("Beacon") do
			local carrier = model:FindFirstChild("SkyBeam")
			local found = carrier and carrier:FindFirstChild("Beam")
			if found and found:IsA("Beam") then
				beam = found
				break
			end
		end
	end
	local d = deposit
	if d == nil or d.Parent == nil then
		deposit = nil
		depositSize = nil
		for _, inst in CollectionService:GetTagged("BeaconDeposit") do
			if inst:IsA("BasePart") then
				deposit = inst
				depositSize = inst.Size
				break
			end
		end
	end
end

local function sortRings()
	table.sort(rings, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
end

local function trackRing(inst: Instance)
	if inst:IsA("BasePart") and not table.find(rings, inst) then
		table.insert(rings, inst)
		sortRings()
		ringLit = -1 -- réappliquer l'état des anneaux
	end
end

local function untrackRing(inst: Instance)
	local i = table.find(rings, inst :: any)
	if i then
		table.remove(rings, i)
	end
end

local function trackLight(inst: Instance)
	if inst:IsA("BasePart") then
		lights[inst] = true
	end
end

local function untrackLight(inst: Instance)
	if inst:IsA("BasePart") then
		lights[inst] = nil
	end
end

-- Calcul et écriture des propriétés -----------------------------------------------------------------

local function baseValues(now: number): Values
	local base = Events.Lighting.Base
	local v = values
	if v == nil then
		v = {} :: any
		values = v
	end
	v.ClockTime = LightingController.cycleClockTime(now)
	v.Brightness = base.Brightness
	v.Ambient = base.Ambient
	v.OutdoorAmbient = base.OutdoorAmbient
	v.StarCount = base.StarCount
	v.MoonAngularSize = base.MoonAngularSize
	v.SunAngularSize = base.SunAngularSize
	v.AtmosphereColor = base.AtmosphereColor
	v.AtmosphereDecay = base.AtmosphereDecay
	v.Density = base.AtmosphereDensity
	v.Offset = base.AtmosphereOffset
	v.Glare = base.AtmosphereGlare
	v.Haze = base.AtmosphereHaze
	v.Bloom = base.BloomIntensity
	v.BloomSize = base.BloomSize
	v.BloomThreshold = base.BloomThreshold
	v.Saturation = base.Saturation
	v.Contrast = base.Contrast
	v.SunRays = base.SunRays
	v.Tint = Color3.new(1, 1, 1)
	v.BeamWidth = Zones.Beacon.BeamWidth
	return v
end

local function computeValues(now: number): Values
	local v = baseValues(now)
	for _, key in order do
		local w = weights[key]
		if w == nil or w <= 0 then
			continue
		end
		local e = ease(w)
		local p = Events.Lighting.Presets[key]
		if p.Tint then
			v.Tint = v.Tint:Lerp(p.Tint, e)
		end
		if p.HsvTintCycle then
			local hue = (now / p.HsvTintCycle) % 1
			v.Tint = v.Tint:Lerp(Color3.fromHSV(hue, p.HsvTintSaturation or 0.12, 1), e)
		end
		if p.AtmosphereColor then
			v.AtmosphereColor = v.AtmosphereColor:Lerp(p.AtmosphereColor, e)
		end
		if p.AtmosphereDecay then
			v.AtmosphereDecay = v.AtmosphereDecay:Lerp(p.AtmosphereDecay, e)
		end
		if p.Haze then
			v.Haze = lerp(v.Haze, p.Haze, e)
		end
		if p.Bloom then
			v.Bloom = lerp(v.Bloom, p.Bloom, e)
		end
		if p.Brightness then
			v.Brightness = lerp(v.Brightness, p.Brightness, e)
		end
		if p.MoonAngularSize then
			v.MoonAngularSize = lerp(v.MoonAngularSize, p.MoonAngularSize, e)
		end
		if p.ClockTime then
			v.ClockTime = lerp(v.ClockTime, p.ClockTime, e)
		end
		if p.StarCount then
			v.StarCount = lerp(v.StarCount, p.StarCount, e)
		end
		if p.OutdoorAmbientMult then
			v.OutdoorAmbient = scaleColor(v.OutdoorAmbient, lerp(1, p.OutdoorAmbientMult, e))
		end
		if p.BeaconBeamMult then
			v.BeamWidth *= lerp(1, p.BeaconBeamMult, e)
		end
	end
	return v
end

local function sameValue(a: any, b: any): boolean
	if a == nil or b == nil then
		return false
	end
	if typeof(a) == "Color3" then
		return math.abs(a.R - b.R) < COLOR_EPSILON
			and math.abs(a.G - b.G) < COLOR_EPSILON
			and math.abs(a.B - b.B) < COLOR_EPSILON
	end
	if type(a) == "number" then
		return math.abs(a - b) < EPSILON
	end
	return a == b
end

-- Écrit `value` dans inst[prop] seulement s'il a changé (clé de cache unique par cible ; une
-- nouvelle instance, par exemple un Sky remplacé, est toujours réécrite)
local function write(cacheKey: string, inst: Instance?, prop: string, value: any)
	if inst == nil then
		return
	end
	if writtenTo[cacheKey] == inst and sameValue(written[cacheKey], value) then
		return
	end
	written[cacheKey] = value
	writtenTo[cacheKey] = inst
	local target: any = inst
	target[prop] = value
end

local function apply(v: Values)
	write("ClockTime", Lighting, "ClockTime", v.ClockTime)
	write("Brightness", Lighting, "Brightness", v.Brightness)
	write("Ambient", Lighting, "Ambient", v.Ambient)
	write("OutdoorAmbient", Lighting, "OutdoorAmbient", v.OutdoorAmbient)
	local sky = lightingChild("Sky") :: Sky?
	write("StarCount", sky, "StarCount", math.floor(v.StarCount / STAR_QUANTUM + 0.5) * STAR_QUANTUM)
	write("MoonAngularSize", sky, "MoonAngularSize", v.MoonAngularSize)
	write("SunAngularSize", sky, "SunAngularSize", v.SunAngularSize)
	local atmosphere = lightingChild("Atmosphere") :: Atmosphere?
	write("AtmosphereColor", atmosphere, "Color", v.AtmosphereColor)
	write("AtmosphereDecay", atmosphere, "Decay", v.AtmosphereDecay)
	write("Density", atmosphere, "Density", v.Density)
	write("Offset", atmosphere, "Offset", v.Offset)
	write("Glare", atmosphere, "Glare", v.Glare)
	write("Haze", atmosphere, "Haze", v.Haze)
	local bloom = lightingChild("BloomEffect") :: BloomEffect?
	write("Bloom", bloom, "Intensity", v.Bloom)
	write("BloomSize", bloom, "Size", v.BloomSize)
	write("BloomThreshold", bloom, "Threshold", v.BloomThreshold)
	local color = lightingChild("ColorCorrectionEffect") :: ColorCorrectionEffect?
	write("Saturation", color, "Saturation", v.Saturation)
	write("Contrast", color, "Contrast", v.Contrast)
	write("Tint", color, "TintColor", v.Tint)
	local rays = lightingChild("SunRaysEffect") :: SunRaysEffect?
	write("SunRays", rays, "Intensity", v.SunRays)
	local b = beam
	if b then
		write("BeamWidth0", b, "Width0", v.BeamWidth)
		write("BeamWidth1", b, "Width1", v.BeamWidth)
	end
end

-- Effets de ciel ------------------------------------------------------------------------------------

local function focusPoint(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

local function ensureSkyFolder(): Folder
	local folder = skyFolder
	if folder and folder.Parent then
		return folder
	end
	local existing = workspace:FindFirstChild("ClientSky")
	if existing and existing:IsA("Folder") then
		skyFolder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "ClientSky"
	created.Parent = workspace
	skyFolder = created
	return created
end

local function clearEffects()
	for key, fx in effects do
		fx:destroy()
		effects[key] = nil
	end
end

local function updateEffects(dt: number, now: number)
	local focus = focusPoint()
	for _, key in order do
		local p = Events.Lighting.Presets[key]
		local effectKey = p.Effect
		if effectKey == nil or not SkyFX.has(effectKey) then
			continue
		end
		local w = weights[key] or 0
		local fx = effects[key]
		if w > 0 then
			if fx == nil then
				fx = SkyFX.create(
					effectKey,
					ensureSkyFolder(),
					{ lowGraphics = Prefs.lowGraphics(), rng = rng }
				)
				if fx == nil then
					continue
				end
				effects[key] = fx
			end
			fx:setIntensity(ease(w))
			fx:step(dt, now, focus)
		elseif fx then
			fx:destroy()
			effects[key] = nil
		end
	end
end

-- Balise : anneaux, anneau de dépôt -------------------------------------------------------------------

local function paintRing(ring: BasePart, lit: boolean)
	local color = Zones.Beacon.RingColor
	if lit then
		ring.Material = Enum.Material.Neon
		ring.Color = color
	else
		ring.Material = Enum.Material.SmoothPlastic
		ring.Color = scaleColor(color, RING_DIM)
	end
end

local function showDeposit(on: boolean)
	local d = deposit
	local full = depositSize
	if d == nil or full == nil then
		return
	end
	local tiny = Vector3.new(full.X, full.Y * 0.1, full.Z * 0.1)
	if Prefs.reducedMotion() then
		d.Size = full
		d.Transparency = if on then 0 else 1
		return
	end
	if on then
		d.Size = tiny
		d.Transparency = 0
		Juice.tween(d, DEPOSIT_GROW, { Size = full }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		local tween =
			Juice.tween(d, DEPOSIT_SHRINK, { Size = tiny }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and not beaconOn and d.Parent then
				d.Transparency = 1
				d.Size = full
			end
		end)
	end
end

local function updateBeacon(dt: number)
	local on = desired.beacon == true
	if on ~= beaconOn then
		beaconOn = on
		ringTimer = 0
		ringLit = -1
		showDeposit(on)
	end
	local target = 0
	if on then
		ringTimer += dt
		target = math.min(#rings, math.floor(ringTimer / RING_STEP) + 1)
	end
	if puffTimer > 0 then
		puffTimer -= dt
		if puffTimer > 0 then
			return
		end
		ringLit = -1 -- fin de la bouffée : repeindre
	end
	if target ~= ringLit then
		ringLit = target
		for i, ring in rings do
			paintRing(ring, i <= target)
		end
	end
end

-- Réussite : flash blanc des anneaux ; échec : bouffée bleue puis extinction
local function beaconPhaseOf(ev: any): string?
	if type(ev) == "table" and type(ev.beacon) == "table" then
		return ev.beacon.phase
	end
	return nil
end

-- Transitions vues en direct seulement (rien à l'arrivée : old == nil)
local function onBeaconPhase(new: Types.EventStatePayload?, old: Types.EventStatePayload?)
	if old == nil then
		return
	end
	local phase = beaconPhaseOf(new)
	if phase == beaconPhaseOf(old) then
		return
	end
	if phase == "success" and not Prefs.reducedMotion() then
		for _, ring in rings do
			ring.Color = RING_FLASH
			Juice.tween(
				ring,
				FLASH_SECONDS,
				{ Color = Zones.Beacon.RingColor },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
		end
	elseif phase == "fail" then
		puffTimer = FAIL_SECONDS
		for _, ring in rings do
			ring.Material = Enum.Material.Neon
			ring.Color = RING_FAIL
			Juice.tween(
				ring,
				FAIL_SECONDS,
				{ Color = scaleColor(Zones.Beacon.RingColor, RING_DIM) },
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out
			)
		end
	end
end

-- Graphismes légers : lumières des lanternes et cristaux coupées au-delà de 60 studs
local function updateLights()
	local low = Prefs.lowGraphics()
	local focus = focusPoint()
	local maxDistance = Balance.Render.LowGraphicsLightDistance
	for part in lights do
		if part.Parent == nil then
			lights[part] = nil
			continue
		end
		local light = part:FindFirstChildOfClass("PointLight")
		if light then
			local enabled = not low or (part.Position - focus).Magnitude <= maxDistance
			if light.Enabled ~= enabled then
				light.Enabled = enabled
			end
		end
	end
end

-- Image ---------------------------------------------------------------------------------------------

local function update(dt: number)
	if not finite(dt) or dt < 0 then
		dt = 0
	end
	local now = Clock.now()
	evalTimer -= dt
	if evalTimer <= 0 then
		evalTimer = EVAL_INTERVAL
		resolveBeacon()
		evaluate(now)
	end
	for _, key in order do
		local target = if desired[key] then 1 else 0
		local w = weights[key] or 0
		if w ~= target then
			local step = dt / blendSeconds(key)
			w = if target > w then math.min(target, w + step) else math.max(target, w - step)
			weights[key] = w
		end
	end
	apply(computeValues(now))
	updateEffects(dt, now)
	updateBeacon(dt)
	lightsTimer -= dt
	if lightsTimer <= 0 then
		lightsTimer = LIGHTS_INTERVAL
		updateLights()
	end
end

-- API -------------------------------------------------------------------------------------------------

function LightingController.Init()
	buildOrder()
	table.clear(desired)
	table.clear(weights)
	table.clear(written)
	table.clear(writtenTo)
	for _, key in order do
		weights[key] = 0
	end
end

function LightingController.Start()
	if started then
		return
	end
	started = true
	if #order == 0 then
		buildOrder()
	end
	ensureSkyFolder()
	for _, inst in CollectionService:GetTagged("BeaconRing") do
		trackRing(inst)
	end
	CollectionService:GetInstanceAddedSignal("BeaconRing"):Connect(trackRing)
	CollectionService:GetInstanceRemovedSignal("BeaconRing"):Connect(untrackRing)
	for _, tag in { "Lantern", "Crystal" } do
		for _, inst in CollectionService:GetTagged(tag) do
			trackLight(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(trackLight)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(untrackLight)
	end
	WorldStateController.EventChanged:Connect(function(new, old)
		lastEvents = if type(new) == "table" then new else nil
		evaluate(Clock.now())
		if not arrived then
			-- instantané d'arrivée : les préréglages déjà en cours sont posés sans fondu
			arrived = true
			for key in desired do
				weights[key] = 1
			end
			update(0)
		end
		onBeaconPhase(new, old)
	end)
	Prefs.Changed:Connect(function(key)
		if key == "lowGraphics" then
			clearEffects() -- recréés à l'image suivante avec le bon niveau de détail
			lightsTimer = 0
		end
	end)
	resolveBeacon()
	evaluate(Clock.now())
	-- état immédiat (pas de fondu à l'arrivée) : les préréglages déjà actifs sont posés d'emblée
	for key in desired do
		weights[key] = 1
	end
	update(0)
	connection = RunService.RenderStepped:Connect(update)
end

-- ClockTime du cycle à l'instant t (pur)
function LightingController.cycleClockTime(t: number): number
	local cycle = Events.Lighting.Cycle
	if type(t) ~= "number" or not finite(t) then
		return cycle.Min
	end
	return cycle.Min + cycle.Amplitude * (0.5 - 0.5 * math.cos(2 * math.pi * t / cycle.Period))
end

-- Préréglage actif le plus visible ("beacon", "aurora", … ou nil)
function LightingController.currentPreset(): string?
	if forced then
		return forced
	end
	for _, key in PRIORITY do
		if desired[key] then
			return key
		end
	end
	for _, key in order do
		if desired[key] then
			return key
		end
	end
	return nil
end

-- Force un préréglage (tests, LiveOps) ; nil = retour au cycle et aux événements
function LightingController.setPreset(key: string?)
	if key ~= nil and (type(key) ~= "string" or Events.Lighting.Presets[key] == nil) then
		warn("[LightingController] préréglage inconnu :", key)
		return
	end
	forced = key
	if started then
		evaluate(Clock.now())
	end
end

-- Exposé pour les tests
LightingController._update = update
LightingController._weights = weights
LightingController._effects = effects
function LightingController._stop()
	local c = connection
	if c then
		c:Disconnect()
		connection = nil
	end
	clearEffects()
	started = false
end

return LightingController
