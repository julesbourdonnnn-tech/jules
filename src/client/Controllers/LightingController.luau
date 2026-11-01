--!strict
-- LightingController (paquet world, docs/04 §13.4, GDD §11.3, §9.4). Éclairage et habillage du monde
-- côté client :
--   * préréglages de Render/Palette : jour pastel (ClockTime 14,5), ciel rose du BOOP RUSH dès la
--     sirène (Tint (255, 200, 225), 2 s), nuit de la Jelly Moon (4 s), lueur des fêtes, costume
--     d'hiver « Frost & Sprinkles » (sucre glace, guirlandes sur les lampadaires, flocons qui suivent
--     la caméra, 10 par seconde au plus, dans le quota de particules « lighting » de
--     QualityController.budgets()) ; Rush discret (30 %) et sans vibration pour un nouveau
--     avant l'étape 9 (setQuiet, OnboardingController) ;
--   * les événements ne s'affichent QUE si l'interrupteur du serveur est vrai
--     (WorldStateController.event().features : jellyMoon, boopRush, costume) : un interrupteur coupé
--     en direct = aucun ciel ni costume fantôme ; sans EventState reçu, jour simple. Phases : EventState
--     (actif jusqu'à son heure de fin) et Logic/EventClock entre deux messages ;
--   * un seul tween par instance (le nouveau annule l'ancien) ; Mouvement réduit : fondu court ;
--     Graphismes légers / qualité réduite : pas de flocons (particules × budget) ;
--   * lumières (budget de la console la plus faible, GDD §12.9) : les 4 lumières de MON ranch
--     allumées (tag « RanchLight », éteintes sur le serveur), lampadaires (tag « LampLight ») coupés
--     au-delà de QualityController.budgets().lightRange ; jamais plus que les quotas lightQuota
--     (world 16, ranch 4 : les plus proches de la caméra d'abord) ;
--   * vibration « rushSiren » (une impulsion de 0,3 s, GDD v1.3) au début de la sirène, UN appel par
--     Rush, seulement pour un joueur dont le profil est arrivé et a passé l'étape 9 de l'accueil
--     (Quests.Onboarding.EventsQuietUntilStep, lu dans StateController) : jamais pour un nouveau,
--     même si OnboardingController n'a pas encore appelé setQuiet ; un nouveau voit aussi le Rush
--     discret (30 %) d'après son seul profil ;
--   * étiquettes fixes du monde (attribut « LabelKey » posé par WorldService : boutique, Prairie,
--     jauge, Big Plop) : BillboardGui en px TV × UIScale (Config/Layout.WorldText), traduites (Prefs.t) ;
--     compte à rebours de l'Autel de la Lune (attribut « LabelTimer » = "moon", GDD §11.1) : « Prochaine
--     Jelly Moon 3 h 05 », « Reste 5 min pour une Goutte de Lune » pendant une séance, caché si
--     l'interrupteur jellyMoon est coupé ou inconnu ;
--   * habillage de la place selon les événements : anneau du MEGA pad en Neon de l'alerte à la fin
--     des pressions (interrupteur megaSquish), éteint au calme (GDD §11.1) ; jarre de la jauge grise
--     pendant la sieste de Big Plop (EventState.gauge.restUntil, GDD §4.23) ; tout finit à son heure,
--     sans message ;
-- Une seule connexion par image (RenderStepped) : flocons à chaque image, le reste toutes les 0,5 s. Toute lecture d'un module plus précoce encore en cours d'écriture passe
-- par pcall avec un repli (jamais d'erreur ni d'avertissement). Positions : Render/WorldDecor.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local EventClock = require(Shared.Logic.EventClock)
local Layout = require(Shared.Config.Layout)
local Quests = require(Shared.Config.Quests)
local Palette = require(Shared.Render.Palette)
local WorldDecor = require(Shared.Render.WorldDecor)

local Client = script.Parent.Parent
local StateController = require(script.Parent.StateController)
local WorldStateController = require(script.Parent.WorldStateController)
local QualityController = require(script.Parent.QualityController)
local Prefs = require(Client.Util.Prefs)
local Haptics = require(Client.Util.Haptics)
local Root = require(Client.UI.Root)

local LightingController = {}

-- Réglages purement graphiques, nommés
local TICK = 0.5 -- s entre deux évaluations (phases, lumières, étiquettes)
local SNOW_RATE = 10 -- flocons par seconde au plus (GDD §11.3)
local SNOW_LIFETIME = NumberRange.new(2.5, 3.5) -- s : flocons vivants ≈ débit × 3 ≤ quota « lighting »
local SNOW_SPEED = NumberRange.new(7, 9) -- studs / s : traversent les 25 studs sous la caméra
local DEFAULT_PARTICLE_QUOTA = 30 -- quota « lighting » de QualityController (repli)
local DEFAULT_LIGHT_QUOTA = { world = 16, ranch = 4 } -- lightQuota de QualityController (repli)
local SNOW_HEIGHT = 25 -- studs au-dessus de la caméra
local SNOW_AREA = Vector3.new(80, 1, 80)
local LABEL_DISTANCE = 90 -- studs : étiquettes fixes du monde
local LABEL_HEIGHT_PX = 1.7 -- hauteur de la plaque en × taille du texte
local WORLD_WAIT = 60 -- s : recherche bornée de workspace.Wobbleton (jamais de WaitForChild infini)
local WINTER_PREFIX = "winter" -- costumes d'hiver (Events.Costumes) dessinés au lancement

export type Resolved = {
	name: string,
	preset: Palette.Preset,
	winter: boolean,
	rush: boolean,
	moon: boolean,
	party: boolean,
}
export type Stats = {
	lightsOn: number,
	lampsOn: number,
	ranchLightsOn: number,
	snow: boolean,
	snowRate: number,
	labels: number,
	winterParts: number,
}

type LabelEntry = { gui: BillboardGui, label: TextLabel, key: string, timer: string? }
type Dressed = { part: BasePart, color: Color3, material: Enum.Material }

type Budgets = {
	lightRange: number,
	particles: number,
	particleQuota: number,
	worldLights: number,
	ranchLights: number,
}

local state = {
	current = "day",
	quiet = false,
	payload = nil :: Types.EventStatePayload?,
	resolved = nil :: Resolved?,
	tweens = {} :: { [Instance]: Tween },
	sirenIndex = -1,
	accumulator = 0,
	started = false,
	world = nil :: Folder?,
	worldSearch = 0,
	ranchLights = {} :: { { light: PointLight, model: Model } },
	lampLights = {} :: { PointLight },
	labels = {} :: { LabelEntry },
	labelHolder = nil :: Folder?,
	labelScale = 0,
	ring = nil :: Dressed?, -- anneau du MEGA pad (couleur et matériau du serveur)
	jarJelly = nil :: Dressed?, -- gelée de la jarre de la jauge
	winter = nil :: Folder?,
	snowPart = nil :: BasePart?,
	snowEmitter = nil :: ParticleEmitter?,
	effects = nil :: {
		atmosphere: Atmosphere,
		bloom: BloomEffect,
		color: ColorCorrectionEffect,
		sky: Sky,
	}?,
	connections = {} :: { RBXScriptConnection },
}

-- =============================================================================================
-- Lectures protégées (modules plus précoces : jamais d'erreur, toujours un repli)
-- =============================================================================================

local function isTable(x: any): boolean
	return type(x) == "table"
end

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

local function field(t: any, key: string): any
	return if isTable(t) then t[key] else nil
end

local function readEvent(): Types.EventStatePayload?
	local ok, value = pcall(WorldStateController.event)
	if ok and isTable(value) then
		return value :: Types.EventStatePayload
	end
	return state.payload
end

local function budgets(): Budgets
	local ok, value = pcall(QualityController.budgets)
	local b: Budgets = {
		lightRange = math.huge,
		particles = 1,
		particleQuota = DEFAULT_PARTICLE_QUOTA,
		worldLights = DEFAULT_LIGHT_QUOTA.world,
		ranchLights = DEFAULT_LIGHT_QUOTA.ranch,
	}
	if ok and isTable(value) then
		local v: any = value
		if type(v.lightRange) == "number" and v.lightRange == v.lightRange and v.lightRange > 0 then
			b.lightRange = v.lightRange
		end
		b.particles = math.clamp(finite(v.particles, 1), 0, 1)
		local pq = field(v.particleQuota, "lighting")
		if type(pq) == "number" then
			b.particleQuota = math.clamp(finite(pq, DEFAULT_PARTICLE_QUOTA), 0, 200)
		else
			b.particleQuota = DEFAULT_PARTICLE_QUOTA * b.particles
		end
		local lq: any = v.lightQuota
		b.worldLights = math.clamp(math.floor(finite(field(lq, "world"), DEFAULT_LIGHT_QUOTA.world)), 0, 24)
		b.ranchLights = math.clamp(math.floor(finite(field(lq, "ranch"), DEFAULT_LIGHT_QUOTA.ranch)), 0, 24)
	end
	if Prefs.lowGraphics() then
		b.particles = 0 -- Graphismes légers : aucun flocon (GDD §9.1)
		b.particleQuota = 0
	end
	return b
end

local function uiScale(): number
	local ok, value = pcall(Root.scale)
	if ok and type(value) == "number" and value == value and value > 0 then
		return value
	end
	return 1
end

local function camera(): Camera?
	return workspace.CurrentCamera
end

-- Accueil du joueur local d'après son profil (miroir StateController, socle, rang 4) : « unknown »
-- tant que le profil n'est pas arrivé ; « newcomer » avant l'étape EventsQuietUntilStep (profil abîmé
-- compris : prudence) ; « veteran » ensuite. La vibration de la sirène exige « veteran ».
local function onboardingStatus(): string
	local okReady, ready = pcall(function()
		return StateController.ready
	end)
	if not okReady or ready ~= true then
		return "unknown"
	end
	local ok, value = pcall(StateController.get, "onboarding")
	if not ok or not isTable(value) then
		return "newcomer"
	end
	if value.done == true then
		return "veteran"
	end
	local step = finite(value.step, 0)
	return if step >= Quests.Onboarding.EventsQuietUntilStep then "veteran" else "newcomer"
end

-- =============================================================================================
-- Choix du préréglage (pur)
-- =============================================================================================

-- Préréglage voulu à l'instant `now` (Clock.now()) et `unix` (Clock.unix()) selon le dernier EventState
-- et les interrupteurs du serveur qu'il porte. Fonction ajoutée (pure : specs).
function LightingController.resolve(
	payload: Types.EventStatePayload?,
	now: number,
	quiet: boolean,
	unix: number
): Resolved
	local t = finite(now, 0)
	local features: any = field(payload, "features")
	local hasFeatures = isTable(features)
	-- costume d'hiver : interrupteur du serveur ET calendrier (Events.Costumes)
	local costume = if hasFeatures and type(features.costume) == "string" then features.costume else ""
	local winter = costume ~= ""
		and string.sub(costume, 1, #WINTER_PREFIX) == WINTER_PREFIX
		and EventClock.costume(finite(unix, 0)) == costume
	-- Jelly Moon : interrupteur jellyMoon ; EventState actif jusqu'à son heure de fin, ou l'horloge
	local moonPayload: any = field(payload, "moon")
	local moon = false
	if hasFeatures and features.jellyMoon == true then
		local fromState = field(moonPayload, "active") == true and t < finite(field(moonPayload, "endsAt"), 0)
		moon = fromState or EventClock.moon(t).active
	end
	-- fêtes : boost de serveur (Wobble, Squish, administrateur) ou fête de la jauge en cours
	local boost: any = field(payload, "boost")
	local boostKind = field(boost, "kind")
	local party = type(boostKind) == "string" and boostKind ~= "" and t < finite(field(boost, "untilT"), 0)
	local gauge: any = field(payload, "gauge")
	if hasFeatures and features.gauge == true and t < finite(field(gauge, "partyUntil"), 0) then
		party = true
	end
	-- BOOP RUSH : de la sirène à la fin, si le mode du serveur le permet ; ou Rush forcé en cours
	local rush = false
	if hasFeatures then
		local mode = features.boopRush
		local allowed = mode == "on"
			or (
				mode == "events"
				and (moon or (boostKind == "admin" and t < finite(field(boost, "untilT"), 0)))
			)
		local rushPayload: any = field(payload, "rush")
		local forced = field(rushPayload, "active") == true and t < finite(field(rushPayload, "endsAt"), 0)
		local phase = EventClock.rush(t)
		local scheduled = allowed and t >= phase.sirenAt and t < phase.endsAt
		rush = mode ~= "off" and (forced or scheduled)
	end
	local base = if winter then "winter" else "day"
	local preset = Palette.preset(if moon then "moon" else base)
	if party then
		preset = Palette.overlay(preset, "party", 1)
	end
	if rush then
		preset = Palette.overlay(preset, "rush", if quiet then Palette.QuietRush else 1)
	end
	local name = if moon then "moon" elseif rush then "rush" elseif party then "party" else base
	return { name = name, preset = preset, winter = winter, rush = rush, moon = moon, party = party }
end

-- =============================================================================================
-- Effets d'éclairage
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
	tween:Play()
end

-- Applique un préréglage (duration 0 : immédiat)
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
end

local function transitionTime(fromName: string, toName: string): number
	if Prefs.reducedMotion() then
		return Palette.Transitions.reduced -- fondu court
	end
	if fromName == "moon" or toName == "moon" then
		return Palette.Transitions.moon
	end
	return Palette.Transitions.default
end

-- =============================================================================================
-- Monde client : dossier local, costume d'hiver, flocons
-- =============================================================================================

local function clientWorld(): Folder
	local existing = workspace:FindFirstChild("ClientWorld")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientWorld"
	folder.Parent = workspace
	return folder
end

local function decorPart(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function buildWinter()
	if state.winter then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Winter"
	local colors = Palette.World
	for i, plate in WorldDecor.icing() do
		decorPart(folder, "Icing" .. i, plate.cframe, plate.size, colors.icing, Enum.Material.Sand)
	end
	local lamp = WorldDecor.Lamp
	for i, l in WorldDecor.lamps() do
		local cf = CFrame.new(l.position + Vector3.new(0, lamp.garlandHeight, 0))
			* CFrame.Angles(0, 0, math.pi / 2)
		decorPart(
			folder,
			"Garland" .. i,
			cf,
			Vector3.new(lamp.garlandThickness, lamp.garlandDiameter, lamp.garlandDiameter),
			colors.garlands[(i - 1) % #colors.garlands + 1],
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
	end
	local snow =
		decorPart(folder, "Snow", CFrame.new(0, 60, 0), SNOW_AREA, colors.icing, Enum.Material.SmoothPlastic)
	snow.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Snowflakes"
	emitter.Color = ColorSequence.new(colors.icing)
	emitter.LightEmission = 0.2
	emitter.Rate = 0
	emitter.Lifetime = SNOW_LIFETIME
	emitter.Speed = SNOW_SPEED
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Size = NumberSequence.new(0.25)
	emitter.Enabled = false
	emitter.Parent = snow
	folder.Parent = clientWorld()
	state.winter = folder
	state.snowPart = snow
	state.snowEmitter = emitter
end

local function destroyWinter()
	local folder = state.winter
	if folder then
		folder:Destroy()
	end
	state.winter = nil
	state.snowPart = nil
	state.snowEmitter = nil
end

local function refreshSnow()
	local emitter = state.snowEmitter
	if emitter == nil then
		return
	end
	-- flocons vivants ≈ débit × durée de vie moyenne : jamais plus que le quota « lighting »
	local b = budgets()
	local average = (SNOW_LIFETIME.Min + SNOW_LIFETIME.Max) / 2
	local rate = math.min(SNOW_RATE, b.particleQuota / average)
	if b.particles <= 0 then
		rate = 0
	end
	if emitter.Rate ~= rate then
		emitter.Rate = rate
	end
	local enabled = rate > 0
	if emitter.Enabled ~= enabled then
		emitter.Enabled = enabled
	end
end

local function followCamera()
	local snow = state.snowPart
	local cam = camera()
	if snow == nil or cam == nil then
		return
	end
	local p = cam.CFrame.Position
	snow.CFrame = CFrame.new(p.X, p.Y + SNOW_HEIGHT, p.Z)
end

-- =============================================================================================
-- Monde construit par le serveur : lumières et étiquettes
-- =============================================================================================

local function labelText(key: string): string
	local ok, text = pcall(Prefs.t, key)
	if ok and type(text) == "string" then
		return text
	end
	return ""
end

local function sizeLabel(entry: LabelEntry, scale: number)
	local px = Layout.WorldText.Text * scale
	local text = entry.label.Text
	local chars = utf8.len(text) or #text
	local width = math.max(4, chars) * px * 0.62 + 2 * px
	entry.gui.Size = UDim2.fromOffset(width, px * LABEL_HEIGHT_PX)
	entry.label.TextSize = px
end

local function buildLabels(world: Folder)
	-- monde remplacé : les anciennes étiquettes (accrochées à des pièces disparues) partent toutes
	local previous = state.labelHolder
	if previous then
		previous:Destroy()
	end
	table.clear(state.labels)
	local holder = Instance.new("Folder")
	holder.Name = "Labels"
	holder.Parent = clientWorld()
	state.labelHolder = holder
	local scale = uiScale()
	for _, inst in world:GetDescendants() do
		local key = inst:GetAttribute("LabelKey")
		if type(key) == "string" and inst:IsA("BasePart") then
			local gui = Instance.new("BillboardGui")
			gui.Name = "Label_" .. key
			gui.Adornee = inst
			gui.LightInfluence = 0
			gui.AlwaysOnTop = false
			gui.MaxDistance = LABEL_DISTANCE
			gui.StudsOffsetWorldSpace = Vector3.new(0, finite(inst:GetAttribute("LabelHeight"), 2), 0)
			local label = Instance.new("TextLabel")
			label.Name = "Text"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.fromRGB(30, 25, 60)
			label.BackgroundTransparency = Layout.WorldText.Background
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
			label.TextScaled = false
			label.Text = labelText(key)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.3, 0)
			corner.Parent = label
			label.Parent = gui
			gui.Parent = holder
			local timer = inst:GetAttribute("LabelTimer")
			local entry: LabelEntry = {
				gui = gui,
				label = label,
				key = key,
				timer = if type(timer) == "string" then timer else nil,
			}
			if entry.timer then
				-- texte et visibilité posés par refreshTimers (interrupteur du serveur d'abord)
				gui.Enabled = false
				label.Text = ""
			end
			sizeLabel(entry, scale)
			table.insert(state.labels, entry)
		end
	end
	state.labelScale = scale
end

local function refreshLabels(force: boolean)
	local scale = uiScale()
	if not force and math.abs(scale - state.labelScale) < 1e-6 then
		return
	end
	state.labelScale = scale
	for _, entry in state.labels do
		if entry.timer == nil then
			entry.label.Text = labelText(entry.key)
		end
		sizeLabel(entry, scale)
	end
end

-- Comptes à rebours du monde (Autel de la Lune) : texte, taille et visibilité à l'instant `now`
local function refreshTimers(payload: Types.EventStatePayload?, now: number)
	local features: any = field(payload, "features")
	local moonOn = isTable(features) and features.jellyMoon == true
	for _, entry in state.labels do
		if entry.timer == "moon" then
			local text = ""
			if moonOn then
				local moonPayload: any = field(payload, "moon")
				local phase = EventClock.moon(now)
				local fromState = field(moonPayload, "active") == true
					and now < finite(field(moonPayload, "endsAt"), 0)
				if fromState or phase.active then
					text = labelText("event.altar")
				else
					local ok, value = pcall(function()
						return Prefs.t(
							"event.altarCountdown",
							{ time = Prefs.duration(phase.startsAt - now) }
						)
					end)
					text = if ok and type(value) == "string" then value else ""
				end
			end
			local enabled = text ~= ""
			if entry.gui.Enabled ~= enabled then
				entry.gui.Enabled = enabled
			end
			if entry.label.Text ~= text then
				entry.label.Text = text
				sizeLabel(entry, state.labelScale)
			end
		end
	end
end

-- Pièce de la place à habiller (couleur et matériau du serveur gardés pour les rendre)
local function dressed(world: Folder, model: string, name: string): Dressed?
	local plaza = world:FindFirstChild("Plaza")
	local holder = if plaza then plaza:FindFirstChild(model) else nil
	local part = if holder then holder:FindFirstChild(name) else nil
	if part and part:IsA("BasePart") then
		return { part = part, color = part.Color, material = part.Material }
	end
	return nil
end

local function dress(d: Dressed?, on: boolean, offColor: Color3, offMaterial: Enum.Material)
	if d == nil or d.part.Parent == nil then
		return
	end
	local color = if on then d.color else offColor
	local material = if on then d.material else offMaterial
	if d.part.Color ~= color then
		d.part.Color = color
	end
	if d.part.Material ~= material then
		d.part.Material = material
	end
end

-- Habillage de la place selon les événements (interrupteurs du serveur, heures de fin : rien ne
-- reste allumé ni gris si un message manque)
local function refreshPlaza(payload: Types.EventStatePayload?, now: number)
	local features: any = field(payload, "features")
	local hasFeatures = isTable(features)
	-- anneau du MEGA pad : de l'alerte à la fin des pressions (horaire EventClock, ou MEGA annoncé)
	local ringOn = false
	if hasFeatures and features.megaSquish == true then
		local m = EventClock.mega(now)
		local megaPayload: any = field(payload, "mega")
		local megaPhase = field(megaPayload, "phase")
		local announced = (megaPhase == "warn" or megaPhase == "press")
			and now < finite(field(megaPayload, "endsAt"), 0)
		ringOn = announced or (now >= m.warnAt and now < m.endsAt)
	end
	dress(state.ring, ringOn, Palette.World.megaRingOff, Enum.Material.SmoothPlastic)
	-- jarre grise pendant la sieste de Big Plop
	local resting = hasFeatures
		and features.gauge == true
		and now < finite(field(field(payload, "gauge"), "restUntil"), 0)
	dress(state.jarJelly, not resting, Palette.World.jellyRest, Enum.Material.SmoothPlastic)
	refreshTimers(payload, now)
end

-- Recherche bornée du monde (StreamingEnabled coupé : présent dès la fin du chargement)
local function findWorld(): Folder?
	if state.world and state.world.Parent ~= nil then
		return state.world
	end
	if state.worldSearch > WORLD_WAIT then
		return nil
	end
	local world = workspace:FindFirstChild("Wobbleton")
	if world == nil or not world:IsA("Folder") then
		return nil
	end
	state.world = world
	table.clear(state.ranchLights)
	table.clear(state.lampLights)
	for _, light in CollectionService:GetTagged("RanchLight") do
		if light:IsA("PointLight") and light:IsDescendantOf(world) then
			local model = light:FindFirstAncestorWhichIsA("Model")
			while model and model:GetAttribute("Slot") == nil do
				model = model.Parent and model.Parent:FindFirstAncestorWhichIsA("Model") or nil
			end
			if model then
				table.insert(state.ranchLights, { light = light, model = model })
			end
		end
	end
	for _, light in CollectionService:GetTagged("LampLight") do
		if light:IsA("PointLight") and light:IsDescendantOf(world) then
			table.insert(state.lampLights, light)
		end
	end
	state.ring = dressed(world, "MegaPad", "Ring")
	state.jarJelly = dressed(world, "GaugeJar", "Jelly")
	buildLabels(world)
	return world
end

local function lightPosition(light: PointLight): Vector3?
	local parent = light.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function refreshLights(b: Budgets)
	local player = Players.LocalPlayer
	local mySlot = if player then player:GetAttribute("RanchSlot") else nil
	local cam = camera()
	local camPos = if cam then cam.CFrame.Position else nil
	local function inRange(light: PointLight): boolean
		if b.lightRange == math.huge or camPos == nil then
			return true
		end
		local pos = lightPosition(light)
		return pos == nil or (pos - (camPos :: Vector3)).Magnitude <= b.lightRange
	end
	local function distance(light: PointLight): number
		local pos = lightPosition(light)
		if pos == nil or camPos == nil then
			return 0
		end
		return (pos - (camPos :: Vector3)).Magnitude
	end
	-- candidats dans la portée, puis les plus proches dans la limite du quota
	local function enable(lights: { PointLight }, wanted: { [PointLight]: boolean }, quota: number)
		local list: { PointLight } = {}
		for light in wanted do
			table.insert(list, light)
		end
		if #list > quota then
			table.sort(list, function(a, c)
				return distance(a) < distance(c)
			end)
		end
		local keep: { [PointLight]: boolean } = {}
		for i = 1, math.min(#list, quota) do
			keep[list[i]] = true
		end
		for _, light in lights do
			local on = keep[light] == true
			if light.Enabled ~= on then
				light.Enabled = on
			end
		end
	end
	local ranch: { PointLight } = {}
	local ranchWanted: { [PointLight]: boolean } = {}
	for _, entry in state.ranchLights do
		local model = entry.model
		table.insert(ranch, entry.light)
		local mine = type(mySlot) == "number"
			and model:GetAttribute("Slot") == mySlot
			and player ~= nil
			and model:GetAttribute("OwnerUserId") == player.UserId
		if mine and inRange(entry.light) then
			ranchWanted[entry.light] = true
		end
	end
	enable(ranch, ranchWanted, b.ranchLights)
	local lampWanted: { [PointLight]: boolean } = {}
	for _, light in state.lampLights do
		if inRange(light) then
			lampWanted[light] = true
		end
	end
	enable(state.lampLights, lampWanted, b.worldLights)
end

-- =============================================================================================
-- Boucle
-- =============================================================================================

-- `siren` : la vibration de la sirène peut partir (jamais à la toute première évaluation du Start :
-- OnboardingController, démarré dans la même image, pose d'abord la version discrète d'un nouveau)
local function evaluate(force: boolean, siren: boolean)
	local now = Clock.now()
	local payload = readEvent()
	local status = onboardingStatus()
	local quiet = state.quiet or status == "newcomer"
	local resolved = LightingController.resolve(payload, now, quiet, Clock.unix())
	local previous = state.resolved
	local changed = previous == nil
		or previous.name ~= resolved.name
		or previous.rush ~= resolved.rush
		or previous.party ~= resolved.party
		or previous.winter ~= resolved.winter
		or previous.preset.tint ~= resolved.preset.tint
	if changed or force then
		local duration = if previous == nil then 0 else transitionTime(state.current, resolved.name)
		apply(resolved.preset, duration)
		state.current = resolved.name
		state.resolved = resolved
	end
	if resolved.winter then
		buildWinter()
	else
		destroyWinter()
	end
	refreshSnow()
	refreshPlaza(payload, now)
	-- sirène du BOOP RUSH : une impulsion de 0,3 s (Config/Console), un seul appel par Rush ; jamais
	-- pour un nouveau : une sirène commencée en version discrète reste muette jusqu'au bout (aucune
	-- vibration tardive à l'étape 9) ; profil pas encore arrivé : rien, la sirène reste à jouer
	local phase = EventClock.rush(now)
	if
		resolved.rush
		and now >= phase.sirenAt
		and now < phase.startsAt
		and state.sirenIndex ~= phase.index
	then
		if quiet then
			state.sirenIndex = phase.index
		elseif siren and status == "veteran" then
			state.sirenIndex = phase.index
			pcall(Haptics.play, "rushSiren")
		end
	end
end

local function step(dt: number)
	local d = finite(dt, 0)
	if d < 0 or d > 5 then
		d = 0
	end
	followCamera()
	state.accumulator += d
	if state.accumulator < TICK then
		return
	end
	state.accumulator = 0
	if state.world == nil then
		state.worldSearch += TICK
	end
	findWorld()
	evaluate(false, true)
	refreshLights(budgets())
	refreshLabels(false)
end

-- =============================================================================================
-- API
-- =============================================================================================

function LightingController.Init()
	ensureEffects()
	apply(Palette.preset("day"), 0)
	state.resolved = nil
	state.current = "day"
end

function LightingController.Start()
	if state.started then
		return
	end
	state.started = true
	local okEvent, payload = pcall(WorldStateController.event)
	if okEvent and isTable(payload) then
		state.payload = payload
	end
	table.insert(
		state.connections,
		WorldStateController.EventChanged:Connect(function(p: Types.EventStatePayload)
			if isTable(p) then
				state.payload = p
				evaluate(false, true)
			end
		end)
	)
	-- étape de l'accueil qui change (étape 9 : fin de la version discrète) : tout de suite
	table.insert(
		state.connections,
		StateController.Changed:Connect(function(key: string)
			if key == "onboarding" then
				evaluate(false, true)
			end
		end)
	)
	table.insert(
		state.connections,
		QualityController.Changed:Connect(function()
			refreshSnow()
			refreshLights(budgets())
		end)
	)
	table.insert(
		state.connections,
		Prefs.Changed:Connect(function(key: string)
			if key == "lowGraphics" or key == "reducedMotion" then
				refreshSnow()
			end
		end)
	)
	table.insert(
		state.connections,
		Prefs.LanguageChanged:Connect(function()
			refreshLabels(true)
			refreshTimers(readEvent(), Clock.now())
		end)
	)
	table.insert(state.connections, RunService.RenderStepped:Connect(step))
	-- monde arrivé après la recherche bornée (chargement très lent) : repris dès qu'il apparaît
	table.insert(
		state.connections,
		workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Wobbleton" and state.world == nil then
				state.worldSearch = 0
				findWorld()
			end
		end)
	)
	findWorld()
	evaluate(true, false)
	refreshLights(budgets())
end

-- Préréglage en vigueur
function LightingController.current(): string
	return state.current
end

-- Version discrète des événements pour un nouveau (OnboardingController)
function LightingController.setQuiet(quiet: boolean)
	local q = quiet == true
	if q == state.quiet then
		return
	end
	state.quiet = q
	if state.started then
		evaluate(false, true)
	end
end

-- Compteurs (specs de budget). Fonction ajoutée.
function LightingController.stats(): Stats
	local ranchOn, lampsOn = 0, 0
	for _, entry in state.ranchLights do
		if entry.light.Enabled then
			ranchOn += 1
		end
	end
	for _, light in state.lampLights do
		if light.Enabled then
			lampsOn += 1
		end
	end
	local winterParts = 0
	if state.winter then
		for _, d in state.winter:GetDescendants() do
			if d:IsA("BasePart") then
				winterParts += 1
			end
		end
	end
	local emitter = state.snowEmitter
	return {
		lightsOn = ranchOn + lampsOn,
		lampsOn = lampsOn,
		ranchLightsOn = ranchOn,
		snow = emitter ~= nil and emitter.Enabled,
		snowRate = if emitter then emitter.Rate else 0,
		labels = #state.labels,
		winterParts = winterParts,
	}
end

-- Une évaluation tout de suite (specs : voyage dans le temps). Fonction ajoutée.
function LightingController.refresh()
	findWorld()
	evaluate(false, true)
	refreshLights(budgets())
	refreshLabels(false)
end

return LightingController
