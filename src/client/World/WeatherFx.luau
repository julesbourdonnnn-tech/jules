--!strict
-- WeatherFx (lot B5, étape 5 ; GDD v2.0 §5.6 « Météo de Wobbleton », §11.5 budgets ; docs/04 §27.5
-- EventState.weather ; plan B5 W1, D22, D29) : les particules de la météo, PUREMENT visuelles, dessinées
-- par le client depuis EventState.weather = { kind, endsAt } (interrupteur Weather du serveur : la clé
-- est absente interrupteur coupé, pendant une séance de Jelly Moon et hors des fenêtres).
--
--   WeatherFx.start()          -- VFXController.Start : une écoute (WorldStateController.EventChanged)
--   WeatherFx.stop()           -- coupe tout, rend chaque instance (fin, specs)
--   WeatherFx.kind()           -- sorte en cours (« sunny », « sprinkles », « bubbles », « rainbow ») ou nil
--   WeatherFx.stats() / _state() / _configure(sources) / _step(dt) / _refresh()   -- specs, Diagnostics
--
-- Sortes (Events.Weather.Kinds) :
--   * sunny : rien de B5 (le préréglage de lumière est celui du directeur d'ambiance du lot B4) ;
--   * sprinkles : UN ParticleEmitter (vermicelles colorés qui tombent) sur une pièce invisible et
--     ancrée qui suit la caméra ;
--   * bubbles : le même émetteur, bulles pâles qui montent depuis le sol autour de la caméra ;
--   * rainbow : un arc de 7 pièces Neon (rouge → violet) au-dessus de la place, posé une fois.
-- Débit : 60 par seconde au plus × facteur de qualité (× 0,3 en Graphismes légers) ; pendant que les
-- flocons d'hiver de LightingController tombent, le débit baisse pour que les deux restent à 60 par
-- seconde ou moins (B5 ne touche pas aux flocons). Système « weather » de Render/VisualBudget : 84
-- pièces, 60 particules.
-- Fin : à endsAt sur l'horloge (Clock.unix), même si aucun message n'arrive ; clé retirée : fin tout
-- de suite. Son WeatherStart (repli Whoosh) une fois par fenêtre, jamais au chargement.
-- B5 n'écrit JAMAIS Lighting (le directeur d'ambiance du lot B4 en est le seul écrivain).
-- Interrupteurs coupés : aucune instance, aucune boucle par image, une seule écoute de signal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Sounds = require(Shared.Config.Sounds)
local AmbienceRules = require(Shared.Logic.AmbienceRules)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local Util = require(Client.World.Util)
local AudioController = require(Client.Controllers.AudioController)
local QualityController = require(Client.Controllers.QualityController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local LightingController = require(Client.Controllers.LightingController)
local VisualBudget = require(Client.Render.VisualBudget)

local WeatherFx = {}

local SYSTEM = "weather"
local LIMITS = table.freeze({ parts = 84, particles = 60, lights = 0 })
local MAX_RATE = 60 -- particules par seconde, météo + flocons d'hiver (GDD §11.5)
local SNOW_EVERY = 1 -- s entre deux lectures du débit des flocons (LightingController.stats)
local MOVE_MIN = 2 -- studs : la pièce de l'émetteur ne bouge que si la caméra a bougé d'autant
local AREA = Vector3.new(80, 1, 80) -- surface d'émission autour de la caméra
local FALL_HEIGHT = 25 -- studs au-dessus de la caméra (vermicelles)
local RISE_BELOW = 18 -- studs sous la caméra (bulles : à peu près le sol)
local RAINBOW_RADIUS = 62 -- rayon de l'arc (les pieds sortent de la place : r ≈ 61)
local RAINBOW_DROP = 12 -- centre de l'arc sous le sol : les pieds s'enfoncent, le haut à 50 studs
local RAINBOW_ANGLE = 11.25 -- degrés : plan de l'arc entre deux rues et loin des lampadaires
local RAINBOW_WIDTH = 3
local RAINBOW_THICK = 1.2
local RAINBOW: { Color3 } = table.freeze({
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 160, 70),
	Color3.fromRGB(255, 225, 90),
	Color3.fromRGB(120, 220, 130),
	Color3.fromRGB(100, 170, 255),
	Color3.fromRGB(120, 110, 230),
	Color3.fromRGB(200, 130, 240),
})
local SPRINKLE_COLORS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 180)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 90)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(120, 210, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 235, 190)),
})
local BUBBLE_COLOR = ColorSequence.new(Color3.fromRGB(225, 240, 255))

type Sources = {
	play: ((string) -> ())?,
	snowRate: (() -> number)?,
	quality: (() -> number)?,
}

local sources: Sources = {}
local started = false
local connections: { RBXScriptConnection } = {}
local stepConn: RBXScriptConnection? = nil
local folder: Folder? = nil
local emitterPart: BasePart? = nil
local emitter: ParticleEmitter? = nil
local arcParts: { BasePart } = {}
local takenParts = 0
local takenParticles = 0
local current: string? = nil -- sorte dessinée
local windowEnd = 0 -- endsAt (unix) de la fenêtre en cours
local soundFor = 0 -- endsAt de la dernière fenêtre annoncée par le son
local armed = false -- première évaluation faite (aucun son au chargement)
local snowT = 0
local snowRate = 0
local lastAt: Vector3? = nil
local counters = { windows = 0, sounds = 0, ended = 0, rateChanges = 0 }

-- =============================================================================================
-- Outils
-- =============================================================================================

local function playSound(name: string, fallback: string)
	local def: any = (Sounds :: any)[name]
	local key = if type(def) == "table" and type(def.id) == "string" and def.id ~= "" then name else fallback
	local fn = sources.play
	if fn then
		pcall(fn, key)
		return
	end
	Util.safe("AudioController.play", nil, AudioController.play, key)
end

local function quality(): number
	local fn = sources.quality
	if fn then
		local ok, v = pcall(fn)
		return if ok then Util.num(v, 1, 0, 1) else 1
	end
	local b: any = Util.safe("QualityController.budgets", nil, QualityController.budgets)
	return Util.num(if type(b) == "table" then b.particles else nil, 1, 0, 1)
end

local function readSnowRate(): number
	local fn = sources.snowRate
	if fn then
		local ok, v = pcall(fn)
		return if ok then Util.num(v, 0, 0, MAX_RATE) else 0
	end
	local s: any = Util.safe("LightingController.stats", nil, LightingController.stats)
	if type(s) ~= "table" or s.snow ~= true then
		return 0
	end
	return Util.num(s.snowRate, 0, 0, MAX_RATE)
end

-- Débit voulu : 60 × qualité, moins les flocons d'hiver (les deux ≤ 60 par seconde)
local function wantedRate(): number
	return math.max(0, math.min(MAX_RATE * quality(), MAX_RATE - snowRate))
end

local function clientWorld(): Instance
	local root = workspace:FindFirstChild("ClientWorld")
	if root == nil then
		local created = Instance.new("Folder")
		created.Name = "ClientWorld"
		created.Parent = workspace
		root = created
	end
	return root :: Instance
end

local function plainPart(name: string, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function cameraPosition(): Vector3?
	local cam = workspace.CurrentCamera
	if cam == nil then
		return nil
	end
	return cam.CFrame.Position
end

-- =============================================================================================
-- Construction et démontage
-- =============================================================================================

local function teardown()
	local f = folder
	folder = nil
	emitterPart = nil
	emitter = nil
	table.clear(arcParts)
	if f then
		f:Destroy()
	end
	if takenParts > 0 then
		VisualBudget.release(SYSTEM, takenParts)
		takenParts = 0
	end
	if takenParticles > 0 then
		VisualBudget.release(SYSTEM, takenParticles, "particles")
		takenParticles = 0
	end
	current = nil
	lastAt = nil
	local c = stepConn
	stepConn = nil
	if c then
		c:Disconnect()
	end
end

local function place(at: Vector3)
	local part = emitterPart
	if part == nil then
		return
	end
	local y = if current == "bubbles" then math.max(0.5, at.Y - RISE_BELOW) else at.Y + FALL_HEIGHT
	part.CFrame = CFrame.new(at.X, y, at.Z)
	lastAt = at
end

local function applyRate()
	local e = emitter
	if e == nil then
		return
	end
	local rate = wantedRate()
	if e.Rate ~= rate then
		e.Rate = rate
		counters.rateChanges += 1
	end
	local on = rate > 0
	if e.Enabled ~= on then
		e.Enabled = on
	end
end

local function buildEmitter(kind: string, parent: Folder)
	if not VisualBudget.take(SYSTEM, 1) then
		return
	end
	takenParts += 1
	if VisualBudget.take(SYSTEM, LIMITS.particles, "particles") then
		takenParticles = LIMITS.particles
	end
	local part = plainPart("WeatherEmitter", parent)
	part.Transparency = 1
	part.Size = AREA
	local e = Instance.new("ParticleEmitter")
	e.Name = if kind == "bubbles" then "Bubbles" else "Sprinkles"
	e.Rate = 0
	e.Enabled = false
	e.LightEmission = 0.2
	if kind == "bubbles" then
		e.Color = BUBBLE_COLOR
		e.Transparency = NumberSequence.new(0.45)
		e.Size = NumberSequence.new(0.6)
		e.Lifetime = NumberRange.new(4, 6)
		e.Speed = NumberRange.new(2, 4)
		e.EmissionDirection = Enum.NormalId.Top
	else
		e.Color = SPRINKLE_COLORS
		e.Size = NumberSequence.new(0.3)
		e.Lifetime = NumberRange.new(2.5, 3.5)
		e.Speed = NumberRange.new(8, 11)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.RotSpeed = NumberRange.new(-180, 180)
	end
	e.SpreadAngle = Vector2.new(15, 15)
	e.Parent = part
	emitterPart = part
	emitter = e
end

-- Arc-en-ciel : 7 segments Neon tangents à un demi-cercle vertical au-dessus de la place
local function buildRainbow(parent: Folder)
	local n = #RAINBOW
	if not VisualBudget.take(SYSTEM, n) then
		return
	end
	takenParts += n
	local center = WorldLayout.plaza("center") - Vector3.new(0, RAINBOW_DROP, 0)
	local a = math.rad(RAINBOW_ANGLE)
	local along = Vector3.new(math.cos(a), 0, math.sin(a)) -- axe horizontal du plan de l'arc
	local normal = Vector3.new(-math.sin(a), 0, math.cos(a))
	local start = math.asin(math.clamp(RAINBOW_DROP / RAINBOW_RADIUS, 0, 1))
	local span = (math.pi - 2 * start) / n
	for i = 1, n do
		local t0 = start + (i - 1) * span
		local t1 = t0 + span
		local p0 = center
			+ along * (RAINBOW_RADIUS * math.cos(t0))
			+ Vector3.new(0, RAINBOW_RADIUS * math.sin(t0), 0)
		local p1 = center
			+ along * (RAINBOW_RADIUS * math.cos(t1))
			+ Vector3.new(0, RAINBOW_RADIUS * math.sin(t1), 0)
		local mid = (p0 + p1) / 2
		local length = (p1 - p0).Magnitude * 1.04
		local part = plainPart("Rainbow" .. i, parent)
		part.Material = Enum.Material.Neon
		part.Color = RAINBOW[i]
		part.Size = Vector3.new(length, RAINBOW_THICK, RAINBOW_WIDTH)
		-- X le long du segment, Z selon la normale du plan (largeur de la bande vue de face)
		local x = (p1 - p0).Unit
		local y = normal:Cross(x)
		part.CFrame = CFrame.fromMatrix(mid, x, y, normal)
		table.insert(arcParts, part)
	end
end

local function build(kind: string)
	current = kind
	if kind ~= "sprinkles" and kind ~= "bubbles" and kind ~= "rainbow" then
		return -- sunny : rien de B5
	end
	VisualBudget.declare(SYSTEM, LIMITS)
	local f = Instance.new("Folder")
	f.Name = "Weather"
	f.Parent = clientWorld()
	folder = f
	if kind == "sprinkles" or kind == "bubbles" then
		buildEmitter(kind, f)
		snowRate = readSnowRate()
		snowT = 0
		applyRate()
		local at = cameraPosition()
		if at then
			place(at)
		end
	elseif kind == "rainbow" then
		buildRainbow(f)
	end
end

-- =============================================================================================
-- Évaluation (EventState) et image
-- =============================================================================================

local function readWeather(): (string?, number)
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	local w = if type(ev) == "table" then ev.weather else nil
	local unix = Clock.unix()
	local kind = AmbienceRules.fromEvent(w, unix)
	if kind == nil or type(w) ~= "table" then
		return nil, 0
	end
	return kind, Util.num(w.endsAt, 0)
end

local function ensureLoop()
	if stepConn ~= nil then
		return
	end
	stepConn = RunService.RenderStepped:Connect(function(dt: number)
		Util.guard("WeatherFx.step", WeatherFx._step, dt)
	end)
end

local function evaluate()
	local kind, endsAt = readWeather()
	local first = not armed
	armed = true
	if kind == nil then
		if current ~= nil then
			counters.ended += 1
		end
		teardown()
		windowEnd = 0
		return
	end
	if kind ~= current or endsAt ~= windowEnd then
		if kind ~= current then
			teardown()
		end
		if endsAt ~= windowEnd then
			counters.windows += 1
		end
		windowEnd = endsAt
		if current == nil then
			build(kind)
		end
		-- son une fois par fenêtre (jamais au chargement)
		if soundFor ~= endsAt then
			soundFor = endsAt
			if not first then
				counters.sounds += 1
				playSound("WeatherStart", "Whoosh")
			end
		end
	end
	-- boucle par image seulement si quelque chose vit (sunny : rien ; fin à endsAt sans message : la
	-- boucle de l'émetteur ou de l'arc s'en charge)
	if folder ~= nil and (emitterPart ~= nil or #arcParts > 0) then
		ensureLoop()
	end
end

-- Une image : fin à endsAt sans message, débit selon les flocons, pièce qui suit la caméra
function WeatherFx._step(dt: number)
	if current == nil then
		teardown()
		return
	end
	if Clock.unix() >= windowEnd then
		counters.ended += 1
		teardown()
		windowEnd = 0
		return
	end
	if emitter == nil then
		return
	end
	snowT += Util.num(dt, 0, 0, 1)
	if snowT >= SNOW_EVERY then
		snowT = 0
		snowRate = readSnowRate()
		applyRate()
	end
	local at = cameraPosition()
	local last = lastAt
	if at and (last == nil or (at - last).Magnitude >= MOVE_MIN) then
		place(at)
	end
end

-- =============================================================================================
-- Cycle de vie
-- =============================================================================================

function WeatherFx.start()
	if started then
		return
	end
	started = true
	armed = false
	table.insert(
		connections,
		WorldStateController.EventChanged:Connect(function()
			Util.guard("WeatherFx.event", evaluate)
		end) :: any
	)
	evaluate()
end

function WeatherFx.stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	teardown()
	windowEnd = 0
	started = false
end

-- Sorte dessinée (ou annoncée pour sunny) en ce moment
function WeatherFx.kind(): string?
	return if current ~= nil and Clock.unix() < windowEnd then current else nil
end

-- Évaluation tout de suite (specs)
function WeatherFx._refresh()
	evaluate()
end

function WeatherFx.stats(): { [string]: number }
	local e = emitter
	return {
		parts = (if emitterPart then 1 else 0) + #arcParts,
		rate = if e and e.Enabled then e.Rate else 0,
		snowRate = snowRate,
		looping = if stepConn then 1 else 0,
		connections = #connections + (if stepConn then 1 else 0),
		windows = counters.windows,
		sounds = counters.sounds,
		ended = counters.ended,
		rateChanges = counters.rateChanges,
	}
end

function WeatherFx._state(): { [string]: any }
	return {
		kind = current,
		endsAt = windowEnd,
		folder = folder,
		emitter = emitter,
		emitterPart = emitterPart,
		arc = table.clone(arcParts),
	}
end

function WeatherFx._configure(options: any?)
	local o: any = if type(options) == "table" then options else {}
	sources.play = if type(o.play) == "function" then o.play else nil
	sources.snowRate = if type(o.snowRate) == "function" then o.snowRate else nil
	sources.quality = if type(o.quality) == "function" then o.quality else nil
end

return WeatherFx
