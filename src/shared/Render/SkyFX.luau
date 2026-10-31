--!strict
-- SkyFX — paquet « world » : effets de ciel des préréglages météo (GDD §11.5), utilisés par
-- LightingController CÔTÉ CLIENT dans workspace.ClientSky. Constructeurs purs : Instance.new
-- seulement, aucun service (la position de la caméra et l'aléa sont passés en paramètres).
--
--   local fx = SkyFX.create("snow", workspace.ClientSky, { lowGraphics = false, rng = Random.new() })
--   fx:setIntensity(w)                 -- 0 … 1 (poids du préréglage, déjà adouci)
--   fx:step(dt, now, cameraPosition)   -- une fois par image
--   fx:destroy()
--
-- Effets : "auroraCurtains" (6 rideaux Beam vert-violet très haut), "snow" (ParticleEmitter sur une
-- pièce qui suit la caméra : 60 / s, vitesse 4-6, durée 6 s), "meteorStreaks" (réserve de 10 traits
-- Néon, un toutes les 0,4 s), "rainbowArcs" (5 arcs Beam). Graphismes légers : effets réduits.
-- Toutes les pièces : ancrées, sans collision ni requête, sans ombre ; fondus en rétrécissant.

local SkyFX = {}

export type Options = { lowGraphics: boolean, rng: Random }

export type Effect = {
	key: string,
	folder: Folder,
	setIntensity: (self: Effect, w: number) -> (),
	step: (self: Effect, dt: number, now: number, focus: Vector3) -> (),
	destroy: (self: Effect) -> (),
}

local TAU = 2 * math.pi

-- Constantes graphiques (GDD §11.5)
local AURORA_COUNT = 6
local AURORA_COUNT_LOW = 3
local AURORA_RADIUS = 380
local AURORA_HEIGHT = 240
local AURORA_SPAN = 110
local AURORA_WIDTH = 90
local AURORA_CURVE = 40
local AURORA_GREEN = Color3.fromRGB(120, 255, 190)
local AURORA_VIOLET = Color3.fromRGB(190, 120, 255)

local SNOW_RATE = 60
local SNOW_LOW_MULT = 0.3
local SNOW_HEIGHT = 30
local SNOW_AREA = 120

local METEOR_POOL = 10
local METEOR_INTERVAL = 0.4
local METEOR_INTERVAL_LOW = 1.2
local METEOR_DURATION = 0.9
local METEOR_TRAVEL = 150
local METEOR_LENGTH = 14
local METEOR_THICKNESS = 0.35
local METEOR_MIN_INTENSITY = 0.5
local METEOR_COLOR = Color3.fromRGB(255, 240, 200)

local RAINBOW_COLORS = {
	Color3.fromRGB(255, 95, 95),
	Color3.fromRGB(255, 170, 80),
	Color3.fromRGB(255, 235, 110),
	Color3.fromRGB(120, 230, 140),
	Color3.fromRGB(110, 160, 255),
}
local RAINBOW_DISTANCE = 520
local RAINBOW_SPAN = 330
local RAINBOW_HEIGHT = 300
local RAINBOW_STEP = 9
local RAINBOW_WIDTH = 10
local RAINBOW_BASE_Y = -10
local RAINBOW_TRANSPARENCY = 0.45

local function anchorPart(folder: Folder, name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = CFrame.identity
	p.Parent = folder
	return p
end

local function attachment(parent: Instance, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function changed(last: number?, w: number): boolean
	return last == nil or math.abs(last - w) > 0.02 or (w == 0 and last ~= 0) or (w == 1 and last ~= 1)
end

local function newEffect(key: string, parent: Instance): Effect
	local folder = Instance.new("Folder")
	folder.Name = key
	folder.Parent = parent
	local fx = {
		key = key,
		folder = folder,
		setIntensity = function(_self: Effect, _w: number) end,
		step = function(_self: Effect, _dt: number, _now: number, _focus: Vector3) end,
		destroy = function(self: Effect)
			self.folder:Destroy()
		end,
	}
	return fx :: Effect
end

-- Rideaux d'aurore : Beams FaceCamera, ondulation des courbes, transparence selon l'intensité
local function aurora(parent: Instance, options: Options): Effect
	local fx = newEffect("auroraCurtains", parent)
	local anchor = anchorPart(fx.folder, "Anchor", Vector3.one)
	local count = if options.lowGraphics then AURORA_COUNT_LOW else AURORA_COUNT
	local beams: { Beam } = {}
	for i = 1, count do
		local a = (i - 1) / count * TAU + 0.4
		local center = Vector3.new(
			math.cos(a) * AURORA_RADIUS,
			AURORA_HEIGHT + 20 * math.sin(i * 1.7),
			math.sin(a) * AURORA_RADIUS
		)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local a0 = attachment(anchor, "A" .. i, CFrame.new(center + tangent * AURORA_SPAN))
		local a1 = attachment(anchor, "B" .. i, CFrame.new(center - tangent * AURORA_SPAN))
		local beam = Instance.new("Beam")
		beam.Name = "Curtain" .. i
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = AURORA_WIDTH
		beam.Width1 = AURORA_WIDTH * 0.75
		beam.FaceCamera = true
		beam.Segments = if options.lowGraphics then 10 else 24
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, AURORA_GREEN),
			ColorSequenceKeypoint.new(0.5, AURORA_VIOLET),
			ColorSequenceKeypoint.new(1, AURORA_GREEN),
		})
		beam.Transparency = NumberSequence.new(1)
		beam.Parent = anchor
		beams[i] = beam
	end
	local last: number? = nil
	fx.setIntensity = function(_self, w)
		if not changed(last, w) then
			return
		end
		last = w
		local seq = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, lerp(1, 0.45, w)),
			NumberSequenceKeypoint.new(0.8, lerp(1, 0.55, w)),
			NumberSequenceKeypoint.new(1, 1),
		})
		for _, beam in beams do
			beam.Transparency = seq
		end
	end
	fx.step = function(_self, _dt, now, _focus)
		for i, beam in beams do
			beam.CurveSize0 = AURORA_CURVE * math.sin(0.3 * now + i)
			beam.CurveSize1 = -AURORA_CURVE * math.cos(0.25 * now + i * 1.3)
		end
	end
	return fx
end

-- Neige : émetteur sur une pièce invisible qui suit la caméra
local function snow(parent: Instance, options: Options): Effect
	local fx = newEffect("snow", parent)
	local carrier = anchorPart(fx.folder, "SnowEmitter", Vector3.new(SNOW_AREA, 1, SNOW_AREA))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Snow"
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(4, 6)
	emitter.Lifetime = NumberRange.new(6)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Acceleration = Vector3.new(0.6, 0, 0.3)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.LightEmission = 0.4
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0.22),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = carrier
	local mult = if options.lowGraphics then SNOW_LOW_MULT else 1
	local last: number? = nil
	fx.setIntensity = function(_self, w)
		if not changed(last, w) then
			return
		end
		last = w
		emitter.Rate = SNOW_RATE * mult * w
	end
	fx.step = function(_self, _dt, _now, focus)
		carrier.CFrame = CFrame.new(focus + Vector3.new(0, SNOW_HEIGHT, 0))
	end
	return fx
end

type Meteor = { part: Part, from: Vector3, dir: Vector3, t: number }

-- Pluie de météores : réserve de 10 traits Néon qui traversent le ciel puis rétrécissent
local function meteors(parent: Instance, options: Options): Effect
	local fx = newEffect("meteorStreaks", parent)
	local pool: { Part } = {}
	local active: { Meteor } = {}
	for i = 1, METEOR_POOL do
		local p = anchorPart(
			fx.folder,
			"Meteor" .. i,
			Vector3.new(METEOR_THICKNESS, METEOR_THICKNESS, METEOR_LENGTH)
		)
		p.Material = Enum.Material.Neon
		p.Color = METEOR_COLOR
		table.insert(pool, p)
	end
	local interval = if options.lowGraphics then METEOR_INTERVAL_LOW else METEOR_INTERVAL
	local timer = 0
	local intensity = 0
	local rng = options.rng
	local function launch(focus: Vector3)
		local part = table.remove(pool)
		if part == nil then
			return
		end
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(200, 400)
		local from =
			Vector3.new(focus.X + math.cos(a) * r, rng:NextNumber(200, 280), focus.Z + math.sin(a) * r)
		local side = Vector3.new(-math.sin(a), 0, math.cos(a))
			* (if rng:NextNumber(0, 1) < 0.5 then -1 else 1)
		local dir = (side + Vector3.new(0, -0.6, 0)).Unit
		part.Size = Vector3.new(METEOR_THICKNESS, METEOR_THICKNESS, METEOR_LENGTH)
		part.CFrame = CFrame.lookAt(from, from + dir)
		part.Transparency = 0
		table.insert(active, { part = part, from = from, dir = dir, t = 0 })
	end
	fx.setIntensity = function(_self, w)
		intensity = w
	end
	fx.step = function(_self, dt, _now, focus)
		if intensity >= METEOR_MIN_INTENSITY then
			timer -= dt
			if timer <= 0 then
				timer = interval
				launch(focus)
			end
		end
		for i = #active, 1, -1 do
			local m = active[i]
			m.t += dt
			local alpha = m.t / METEOR_DURATION
			if alpha >= 1 then
				m.part.Transparency = 1
				table.insert(pool, m.part)
				table.remove(active, i)
			else
				local pos = m.from + m.dir * (alpha * METEOR_TRAVEL)
				m.part.CFrame = CFrame.lookAt(pos, pos + m.dir)
				if alpha > 0.7 then
					local k = 1 - (alpha - 0.7) / 0.3
					m.part.Size = Vector3.new(METEOR_THICKNESS * k, METEOR_THICKNESS * k, METEOR_LENGTH * k)
				end
			end
		end
	end
	return fx
end

-- Arcs-en-ciel : 5 Beams concentriques au nord, courbés vers le haut
local function rainbow(parent: Instance, options: Options): Effect
	local fx = newEffect("rainbowArcs", parent)
	local anchor = anchorPart(fx.folder, "Anchor", Vector3.one)
	local beams: { Beam } = {}
	for i, color in RAINBOW_COLORS do
		local span = RAINBOW_SPAN - (i - 1) * RAINBOW_STEP
		local height = RAINBOW_HEIGHT - (i - 1) * RAINBOW_STEP
		-- l'axe X d'un Attachment porte la courbe : vers le haut au départ, vers le bas à l'arrivée
		local a0 = attachment(
			anchor,
			"A" .. i,
			CFrame.fromMatrix(
				Vector3.new(-span, RAINBOW_BASE_Y, -RAINBOW_DISTANCE),
				Vector3.yAxis,
				Vector3.zAxis
			)
		)
		local a1 = attachment(
			anchor,
			"B" .. i,
			CFrame.fromMatrix(
				Vector3.new(span, RAINBOW_BASE_Y, -RAINBOW_DISTANCE),
				-Vector3.yAxis,
				Vector3.zAxis
			)
		)
		local beam = Instance.new("Beam")
		beam.Name = "Arc" .. i
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.CurveSize0 = height
		beam.CurveSize1 = height
		beam.Width0 = RAINBOW_WIDTH
		beam.Width1 = RAINBOW_WIDTH
		beam.FaceCamera = true
		beam.Segments = if options.lowGraphics then 16 else 32
		beam.LightEmission = 0.8
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new(1)
		beam.Parent = anchor
		beams[i] = beam
	end
	local last: number? = nil
	fx.setIntensity = function(_self, w)
		if not changed(last, w) then
			return
		end
		last = w
		local seq = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, lerp(1, RAINBOW_TRANSPARENCY, w)),
			NumberSequenceKeypoint.new(0.85, lerp(1, RAINBOW_TRANSPARENCY, w)),
			NumberSequenceKeypoint.new(1, 1),
		})
		for _, beam in beams do
			beam.Transparency = seq
		end
	end
	return fx
end

local BUILDERS: { [string]: (Instance, Options) -> Effect } = {
	auroraCurtains = aurora,
	snow = snow,
	meteorStreaks = meteors,
	rainbowArcs = rainbow,
}

-- Effets connus (clés de Events.Lighting.Presets[*].Effect)
function SkyFX.has(key: string): boolean
	return BUILDERS[key] ~= nil
end

-- Crée l'effet `key` sous `parent` (nil si l'effet est inconnu)
function SkyFX.create(key: string, parent: Instance, options: Options): Effect?
	local builder = BUILDERS[key]
	if builder == nil then
		return nil
	end
	local fx = builder(parent, options)
	fx:setIntensity(0)
	return fx
end

return SkyFX
