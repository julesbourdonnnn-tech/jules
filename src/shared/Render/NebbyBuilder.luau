--!strict
-- NebbyBuilder — paquet « world » (docs/04-architecture.md §12.2).
-- Recettes de modèles en primitives, construites CÔTÉ CLIENT à partir de 4 nombres (espèce, forme,
-- variantes, étoiles). Constructeur pur : Instance.new seulement, aucun service, aucun parentage
-- dans le Workspace (l'appelant parente le modèle et le met en réserve). Toutes les pièces :
-- Anchored, CanCollide = CanQuery = CanTouch = false, CastShadow = false.
--
--   local rig = NebbyBuilder.build(code, stars, "full", { highlight = false, light = false })
--   rig.model.Parent = workspace.ClientWorld.Lines
--   -- chaque image :
--   NebbyBuilder.animate(rig, { t = now, phase = phi, blink = false, speed = 12 })
--   NebbyBuilder.appendCFrames(rig, rootCFrame, parts, cframes)   -- puis UN workspace:BulkMoveTo
--   rig = NebbyBuilder.setLod(rig, "ball")                          -- même table, même modèle
--
-- Recette (GDD §5.2, détail dans Render/Recipes) : corps Ball de taille T (rareté, ×2 si Huge),
-- 2 yeux, accents d'archétype (≤ 3 pièces ; Légendaires : 2 archétypes), auras de rareté
-- (antenne Néon, Sparkles, ParticleEmitter en orbite, PointLight + Trail, Highlight + couronne de
-- boules Néon, coque ForceField + HSV), joues s'il reste de la place, bulle dorée du bouclier
-- débutant en option : AU PLUS 8 pièces en détail complet. Formes (Config/Nebbies.Forms),
-- variantes (Golden Foil, Huge ×2, halo Starborn en 5 Beams), étoiles ★2+ (BillboardGui proche).
-- Niveaux de détail : "full", "ball" (une Ball couleur du corps, Néon si Mythique+), "hidden".
-- GDD : §4.2, §4.4, §5.2, §9.3, §11.6, §12.8, §13.2 (rareté lisible sans couleur : chaque aura a
-- une forme distincte).
-- Dépendances : Config/Nebbies, Render/Recipes.

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local Nebbies = require(Shared.Config.Nebbies)
local Recipes = require(script.Parent.Recipes)

local NebbyBuilder = {}

export type Lod = "full" | "ball" | "hidden"

export type BuildOptions = {
	aura: boolean?, -- instances d'aura de rareté (défaut true en "full")
	highlight: boolean?, -- Highlight (Mythique+ ou tête de file ≥ 20), budget de l'appelant
	trail: boolean?, -- Trail (Légendaire, Comet) ; false en Graphismes légers
	light: boolean?, -- PointLight (Légendaire+), budget de l'appelant
	rookieBubble: boolean?, -- bulle dorée du bouclier débutant
	particleMult: number?, -- 0,3 en Graphismes légers
}

export type AnimState = {
	t: number, -- temps (s) pour les oscillations
	phase: number, -- décalage propre au Nebby
	blink: boolean, -- yeux fermés cette image
	speed: number, -- vitesse de déplacement (0 = immobile)
}

type Anim = {
	mode: Recipes.AnimMode,
	pivot: CFrame?, -- repère du pivot (sway, flap)
	pivotInvOffset: CFrame?, -- pivot⁻¹ × décalage de repos (précalculé)
	amp: number,
	freq: number,
	sign: number,
	phase: number,
}

type HsvEntry = {
	part: BasePart,
	role: "body" | "accent" | "shell",
	offset: number, -- décalage de teinte
}

export type RigKind = "nebby" | "wisp" | "cometOrb"

export type Rig = {
	model: Model, -- non parenté
	body: BasePart,
	parts: { BasePart }, -- toutes les pièces à déplacer (body en premier)
	offsets: { CFrame }, -- pose de repos relative au corps
	pose: { CFrame }, -- pose animée courante (mise à jour par animate)
	code: Types.NebbyCode,
	stars: number,
	lod: Lod,
	size: number, -- taille du corps T (avec Huge)
	-- Ajouts du paquet world (lecture seule pour les appelants)
	kind: RigKind,
	opts: BuildOptions,
	anims: { Anim },
	eyes: { SpecialMesh },
	blinking: boolean,
	hsv: { HsvEntry },
	orbit: Attachment?,
	destroyed: boolean,
}

-- Constantes graphiques internes (GDD §4.2, §4.4, §9.3, §11.6) -------------------------------

local TAU = 2 * math.pi
local PRISM_PERIOD = 6 -- s : un tour de teinte (Prismatic)
local PRISM_SATURATION = 0.45
local COSMIC_PERIOD = 4 -- s : cycle HSV des Cosmiques (corps, coque, accent du Grand Nebula)
local COSMIC_SATURATION = 0.55
local GOLDEN_HSV_BLEND = 0.5 -- Prismatic Golden : moitié or, moitié arc-en-ciel
local SPECIES_HUE_STEP = 0.137 -- décalage de teinte propre à l'espèce (les arcs-en-ciel ne sont pas synchrones)
local BLINK_SCALE = Vector3.new(1, 0.1, 1) -- yeux fermés : Y × 0,1 (GDD §9.3)
local OPEN_SCALE = Vector3.one
local ORBIT_PERIOD = 2 -- s : un tour des particules d'orbite (Épique)
local ORBIT_RADIUS = 0.75 -- × T
local ORBIT_RATE = 2.5 -- particules / s (≈ 3 visibles)
local ORBIT_LIFETIME = 1.2
local LIGHT_RANGE_BASE = 6
local LIGHT_RANGE_PER_T = 2
local LIGHT_BRIGHTNESS = 1.2
local TRAIL_LIFETIME = 0.35
local FIRE_HEAT = 4
local FIRE_COLOR = Color3.fromRGB(255, 140, 50)
local FIRE_SECONDARY = Color3.fromRGB(255, 220, 110)
local HIGHLIGHT_FILL_TRANSPARENCY = 0.8
local STAR_HALO_RADIUS = 0.75 -- × T, 5 branches dans le plan du dos
local STAR_HALO_DEPTH = 0.3 -- × T derrière le centre
local STAR_HALO_WIDTH = 0.22 -- × T à la base d'une branche
local STARS_MAX_DISTANCE = 40 -- studs : indicateur ★ seulement de près
local STARS_COLOR = Color3.fromRGB(255, 220, 90)
local STARS_STROKE = Color3.fromRGB(40, 28, 60)
local FAR_TAIL_SPEED = 16 -- studs/s : la queue de Comète ondule deux fois plus vite au-delà

-- Gloomwisp (GDD §11.6)
local WISP_SIZE = 2.4
local WISP_COLOR = Color3.fromRGB(45, 35, 80)
local WISP_PUFF_COLOR = Color3.fromRGB(62, 50, 108)
local WISP_EYE_COLOR = Color3.fromRGB(255, 255, 255)
local WISP_TRAIL_COLOR = Color3.fromRGB(150, 90, 220)
local WISP_TREMBLE = 0.08 -- ±8 %
local WISP_TREMBLE_HZ = 2

-- Grande Comète (GDD §11.6)
local COMET_ORB_SIZE = 3
local COMET_COLOR = Color3.fromRGB(255, 230, 180)
local COMET_RING_COLOR = Color3.fromRGB(255, 205, 60)
local COMET_RING2_COLOR = Color3.fromRGB(255, 240, 190)
local COMET_LIGHT_RANGE = 16
local COMET_LIGHT_BRIGHTNESS = 2
local COMET_SKY_SIZE = 6
local COMET_FIRE_SIZE = 10
local COMET_FIRE_HEAT = 15
local COMET_FIRE_COLOR = Color3.fromRGB(255, 150, 50)
local COMET_FIRE_SECONDARY = Color3.fromRGB(255, 215, 110)
local COMET_TRAIL_LIFETIME = 1.2

local DEFAULT_OPTS: BuildOptions = table.freeze({
	aura = true,
	highlight = false,
	trail = true,
	light = false,
	rookieBubble = false,
	particleMult = 1,
}) :: any

-- Décodage d'un code (repli sûr : un code invalide devient un Puffkin normal) ------------------

type Look = {
	code: number,
	s: number,
	species: Nebbies.SpeciesDef,
	rarity: Nebbies.RarityDef,
	form: Nebbies.FormDef,
	golden: boolean,
	huge: boolean,
	starborn: boolean,
	size: number,
}

local FALLBACK_CODE = Nebbies.pack(Nebbies.Named.Welcome, 0, 0)

local function normalizeCode(code: any): number
	if Nebbies.isValidCode(code) then
		return code
	end
	return FALLBACK_CODE
end

-- Décodage mis en cache : au plus 4096 codes, données partagées en lecture seule (animate en a
-- besoin chaque image pour les teintes HSV)
local lookCache: { [number]: Look } = {}

local function lookOf(rawCode: any): Look
	local code = normalizeCode(rawCode)
	local cached = lookCache[code]
	if cached then
		return cached
	end
	local s, f, v = Nebbies.unpack(code)
	local species = Nebbies.Species[s]
	local rarity = Nebbies.Rarities[species.rarity] or Nebbies.Rarities[1]
	local form = Nebbies.Forms[f] or Nebbies.Forms[0]
	local huge = bit32.btest(v, Nebbies.Variants.huge.bit)
	local look: Look = {
		code = code,
		s = s,
		species = species,
		rarity = rarity,
		form = form,
		golden = bit32.btest(v, Nebbies.Variants.golden.bit),
		huge = huge,
		starborn = bit32.btest(v, Nebbies.Variants.starborn.bit),
		size = rarity.size * (if huge then Nebbies.Variants.huge.scale or 2 else 1),
	}
	lookCache[code] = look
	return look
end

local function normalizeStars(stars: any): number
	if type(stars) ~= "number" or stars ~= stars then
		return 1
	end
	return math.clamp(math.floor(stars), 1, Nebbies.MAX_STARS)
end

local function normalizeLod(lod: any): Lod
	if lod == "ball" or lod == "hidden" then
		return lod
	end
	return "full"
end

local function hsvColor(t: number, period: number, saturation: number, offset: number): Color3
	return Color3.fromHSV(((t / period) + offset) % 1, saturation, 1)
end

local function bodyColorOf(look: Look, t: number): Color3
	local cosmic = look.rarity.hsvCycle == true
	if cosmic or look.form.hsvCycle then
		local period = if cosmic then COSMIC_PERIOD else PRISM_PERIOD
		local saturation = if cosmic then COSMIC_SATURATION else PRISM_SATURATION
		local c = hsvColor(t, period, saturation, look.s * SPECIES_HUE_STEP)
		if look.golden then
			c = c:Lerp(Nebbies.Variants.golden.color or c, GOLDEN_HSV_BLEND)
		end
		return c
	end
	if look.golden then
		return Nebbies.Variants.golden.color or look.rarity.color
	end
	if look.form.bodyColor then
		return look.form.bodyColor
	end
	if look.form.bodyTint then
		return look.rarity.color:Lerp(look.form.bodyTint, look.form.tintAlpha or 0)
	end
	return look.rarity.color
end

local function bodyMaterialOf(look: Look): Enum.Material
	if look.golden then
		return Nebbies.Variants.golden.material or Enum.Material.Foil
	end
	return look.form.material
end

local function isHsvBody(look: Look): boolean
	return look.rarity.hsvCycle == true or look.form.hsvCycle == true
end

-- Construction des pièces ----------------------------------------------------------------------

local function newPart(shape: Recipes.Shape): BasePart
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		local p = Instance.new("Part")
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	return part
end

local function scaled(cf: CFrame, t: number): CFrame
	return (cf - cf.Position) + cf.Position * t
end

local function makeAnim(spec: Recipes.PartSpec, offset: CFrame, t: number): Anim
	local mode = spec.anim
	local anim: Anim = {
		mode = mode,
		amp = spec.amp or 0,
		freq = spec.freq or 0,
		sign = spec.sign or 1,
		phase = spec.phase or 0,
	}
	if mode == "sway" or mode == "flap" then
		local pivot = CFrame.new((spec.pivot or Vector3.zero) * t)
		anim.pivot = pivot
		anim.pivotInvOffset = pivot:Inverse() * offset
	elseif mode == "bounce" or mode == "tail" then
		anim.amp = (spec.amp or 0) * t
	end
	return anim
end

local function addTrail(part: BasePart, halfHeight: number, color0: Color3, color1: Color3, lifetime: number)
	local a0 = Instance.new("Attachment")
	a0.Name = "Trail0"
	a0.Position = Vector3.new(0, halfHeight, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "Trail1"
	a1.Position = Vector3.new(0, -halfHeight, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = lifetime
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.8
	trail.Color = ColorSequence.new(color0, color1)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = part
end

-- Halo Starborn : 5 branches en Beams (aucune pièce de plus) dans le plan du dos
local function addStarHalo(body: BasePart, t: number, color: Color3)
	local center = Instance.new("Attachment")
	center.Name = "HaloCenter"
	center.Position = Vector3.new(0, 0.15 * t, STAR_HALO_DEPTH * t)
	center.Parent = body
	for k = 0, 4 do
		local angle = math.pi / 2 + k * (TAU / 5)
		local tip = Instance.new("Attachment")
		tip.Name = "HaloTip" .. (k + 1)
		tip.Position = center.Position
			+ Vector3.new(math.cos(angle) * STAR_HALO_RADIUS * t, math.sin(angle) * STAR_HALO_RADIUS * t, 0)
		tip.Parent = body
		local beam = Instance.new("Beam")
		beam.Name = "HaloRay" .. (k + 1)
		beam.Attachment0 = center
		beam.Attachment1 = tip
		beam.Width0 = STAR_HALO_WIDTH * t
		beam.Width1 = 0.02 * t
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = 1
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new(0.05, 0.3)
		beam.Parent = body
	end
end

local function addStars(body: BasePart, t: number, stars: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Stars"
	gui.Size = UDim2.fromScale(0.5 * t * stars, 0.5 * t)
	gui.StudsOffset = Vector3.new(0, 0.95 * t, 0)
	gui.MaxDistance = STARS_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = body
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = string.rep("★", stars)
	label.TextColor3 = STARS_COLOR
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = STARS_STROKE
	stroke.Parent = label
	gui.Parent = body
end

-- Plan des pièces en détail complet (≤ Recipes.MaxParts) ----------------------------------------

local function plan(look: Look, opts: BuildOptions): { Recipes.PartSpec }
	local max = Recipes.MaxParts
	local list: { Recipes.PartSpec } = { Recipes.body() }
	for _, e in Recipes.eyes() do
		table.insert(list, e)
	end
	for _, a in Recipes.accents(look.species.archetypes) do
		table.insert(list, a)
	end
	if opts.aura ~= false then
		local aura = look.rarity.aura
		if aura == "antenna" and #list < max then
			table.insert(list, Recipes.antenna())
		elseif aura == "highlightCrown" then
			for _, orb in Recipes.crownBalls(math.min(3, max - #list)) do
				table.insert(list, orb)
			end
		elseif aura == "forceFieldHsv" and #list < max then
			table.insert(list, Recipes.shell())
		end
	end
	if opts.rookieBubble and #list < max then
		table.insert(list, Recipes.bubble())
	end
	if #list + 2 <= max then
		for _, c in Recipes.cheeks() do
			table.insert(list, c)
		end
	end
	return list
end

type Resolved = {
	color: Color3,
	material: Enum.Material,
	reflectance: number?,
	hsv: ("body" | "accent" | "shell")?,
}

local function resolveNebby(look: Look, spec: Recipes.PartSpec, accentIndex: number): Resolved
	local role = spec.color
	if role == "body" then
		return {
			color = bodyColorOf(look, 0),
			material = bodyMaterialOf(look),
			hsv = if isHsvBody(look) then "body" else nil,
		}
	elseif role == "eye" then
		local neon = look.form.eyeNeon == true
		return {
			color = look.form.eyeColor or Recipes.EyeColor,
			material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			reflectance = if neon then nil else Recipes.EyeReflectance,
		}
	elseif role == "cheek" then
		return { color = Recipes.CheekColor, material = Enum.Material.SmoothPlastic }
	elseif role == "crater" then
		local c = bodyColorOf(look, 0)
		local k = Recipes.CraterShade
		return { color = Color3.new(c.R * k, c.G * k, c.B * k), material = bodyMaterialOf(look) }
	elseif role == "rarity" then
		return { color = look.rarity.color, material = Enum.Material.Neon }
	elseif role == "shell" then
		return {
			color = hsvColor(0, COSMIC_PERIOD, COSMIC_SATURATION, 0.5),
			material = Enum.Material.ForceField,
			hsv = "shell",
		}
	elseif role == "bubble" then
		return { color = Recipes.BubbleColor, material = Enum.Material.ForceField }
	end
	-- accent / crown
	local accent = look.species.accent
	local colors = look.form.accentColors
	if colors and #colors > 0 then
		accent = colors[(accentIndex - 1) % #colors + 1]
	end
	if role == "crown" then
		accent = accent:Lerp(Recipes.CrownGold, Recipes.CrownGoldBlend)
	end
	local neon = spec.neon == true or look.form.accentNeon == true
	return {
		color = accent,
		material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		hsv = if look.species.hsvAccent then "accent" else nil,
	}
end

local function emptyRig(
	model: Model,
	kind: RigKind,
	code: number,
	stars: number,
	lod: Lod,
	size: number,
	opts: BuildOptions
): Rig
	return {
		model = model,
		body = nil :: any, -- posé par fill / assemble
		parts = {},
		offsets = {},
		pose = {},
		code = code,
		stars = stars,
		lod = lod,
		size = size,
		kind = kind,
		opts = opts,
		anims = {},
		eyes = {},
		blinking = false,
		hsv = {},
		orbit = nil,
		destroyed = false,
	}
end

-- Corps placeholder des rigs masqués : jamais parenté, jamais détruit, partagé
local hiddenBody: BasePart? = nil
local function placeholder(): BasePart
	local p = hiddenBody
	if p == nil then
		p = newPart("Ball")
		p.Name = "HiddenNebby"
		p.Transparency = 1
		hiddenBody = p
	end
	return p :: BasePart
end

-- Ajoute les pièces décrites par `specs` (dimensions × t) au rig
local function assemble(
	rig: Rig,
	specs: { Recipes.PartSpec },
	t: number,
	resolve: (Recipes.PartSpec, number) -> Resolved
)
	local accentIndex = 0
	for i, spec in specs do
		if spec.color == "accent" or spec.color == "crown" then
			accentIndex += 1
		end
		local look = resolve(spec, accentIndex)
		local part = newPart(spec.shape)
		part.Name = spec.name
		part.Size = spec.size * t
		part.Color = look.color
		part.Material = spec.material or look.material
		if look.reflectance then
			part.Reflectance = look.reflectance
		end
		local offset = scaled(spec.cframe, t)
		part.CFrame = offset
		if spec.shape == "Eye" then
			local mesh = Instance.new("SpecialMesh")
			mesh.Name = "EyeMesh"
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = OPEN_SCALE
			mesh.Parent = part
			table.insert(rig.eyes, mesh)
		end
		if look.hsv then
			table.insert(rig.hsv, { part = part, role = look.hsv, offset = (i - 1) * 0.11 })
		end
		part.Parent = rig.model
		rig.parts[i] = part
		rig.offsets[i] = offset
		rig.pose[i] = offset
		rig.anims[i] = makeAnim(spec, offset, t)
	end
	rig.body = rig.parts[1]
	rig.model.PrimaryPart = rig.body
end

-- Remplit un rig de Nebby au niveau de détail demandé
local function fill(rig: Rig, lod: Lod)
	local look = lookOf(rig.code)
	local t = look.size
	rig.lod = lod
	rig.size = t
	if lod == "hidden" then
		rig.body = placeholder()
		return
	end
	if lod == "ball" then
		local part = newPart("Ball")
		part.Name = "Body"
		part.Size = Vector3.one * t
		part.Color = bodyColorOf(look, 0)
		part.Material = if look.rarity.neonFar then Enum.Material.Neon else bodyMaterialOf(look)
		part.CFrame = CFrame.identity
		part.Parent = rig.model
		rig.parts[1] = part
		rig.offsets[1] = CFrame.identity
		rig.pose[1] = CFrame.identity
		rig.anims[1] = { mode = "static", amp = 0, freq = 0, sign = 1, phase = 0 }
		if isHsvBody(look) then
			table.insert(rig.hsv, { part = part, role = "body", offset = 0 })
		end
		rig.body = part
		rig.model.PrimaryPart = part
		return
	end

	local opts = rig.opts
	local specs = plan(look, opts)
	assemble(rig, specs, t, function(spec, accentIndex)
		return resolveNebby(look, spec, accentIndex)
	end)
	local body = rig.body

	-- Forme : petite flamme (Blazing)
	if look.form.fire then
		local fire = Instance.new("Fire")
		fire.Size = look.form.fire * math.max(1, t / 2)
		fire.Heat = FIRE_HEAT
		fire.Color = FIRE_COLOR
		fire.SecondaryColor = FIRE_SECONDARY
		fire.Parent = body
	end

	-- Auras de rareté sans pièce
	local aura = look.rarity.aura
	local rarityId = look.rarity.id
	if opts.aura ~= false then
		if aura == "sparkles" then
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = look.rarity.color
			sparkles.Parent = body
		elseif aura == "orbit" then
			local orbit = Instance.new("Attachment")
			orbit.Name = "Orbit"
			orbit.Position = Vector3.new(ORBIT_RADIUS * t, 0.1 * t, 0)
			orbit.Parent = body
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "OrbitSparks"
			emitter.Rate = ORBIT_RATE * math.clamp(opts.particleMult or 1, 0, 1)
			emitter.Lifetime = NumberRange.new(ORBIT_LIFETIME)
			emitter.Speed = NumberRange.new(0)
			emitter.LightEmission = 1
			emitter.LockedToPart = false
			emitter.Color = ColorSequence.new(look.rarity.color)
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.22 * t),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Transparency = NumberSequence.new(0, 1)
			emitter.Parent = orbit
			rig.orbit = orbit
		elseif aura == "lightTrail" and opts.trail ~= false then
			addTrail(body, 0.3 * t, look.rarity.color, Color3.new(1, 1, 1), TRAIL_LIFETIME)
		end
		if (aura == "highlightCrown" or aura == "forceFieldHsv") and opts.highlight then
			local highlight = Instance.new("Highlight")
			highlight.Name = "Aura"
			highlight.Adornee = rig.model
			highlight.FillColor = look.rarity.color
			highlight.OutlineColor = look.rarity.color
			highlight.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
			highlight.OutlineTransparency = 0
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Parent = rig.model
		end
	end
	if opts.light and rarityId >= 5 then
		local light = Instance.new("PointLight")
		light.Range = LIGHT_RANGE_BASE + LIGHT_RANGE_PER_T * t
		light.Brightness = LIGHT_BRIGHTNESS
		light.Color = look.rarity.color
		light.Shadows = false
		light.Parent = body
	end

	-- Queue de Comète : Trail (détail complet uniquement)
	if opts.trail ~= false then
		for i, spec in specs do
			if spec.trail then
				addTrail(rig.parts[i], 0.2 * t, look.species.accent, look.rarity.color, TRAIL_LIFETIME)
			end
		end
	end

	if look.starborn then
		addStarHalo(body, t, Nebbies.Variants.starborn.color or STARS_COLOR)
	end
	if rig.stars >= 2 then
		addStars(body, t, rig.stars)
	end
end

local function clear(rig: Rig)
	for _, child in rig.model:GetChildren() do
		child:Destroy()
	end
	rig.model.PrimaryPart = nil
	table.clear(rig.parts)
	table.clear(rig.offsets)
	table.clear(rig.pose)
	table.clear(rig.anims)
	table.clear(rig.eyes)
	table.clear(rig.hsv)
	rig.orbit = nil
	rig.blinking = false
end

-- API -------------------------------------------------------------------------------------------

function NebbyBuilder.build(code: Types.NebbyCode, stars: number, lod: Lod, opts: BuildOptions?): Rig
	local look = lookOf(code)
	local merged: BuildOptions = table.clone(DEFAULT_OPTS) :: any
	if opts then
		for k, v in opts :: any do
			(merged :: any)[k] = v
		end
	end
	local model = Instance.new("Model")
	model.Name = "Nebby"
	model:SetAttribute("Code", look.code)
	local rig =
		emptyRig(model, "nebby", look.code, normalizeStars(stars), normalizeLod(lod), look.size, merged)
	fill(rig, rig.lod)
	return rig
end

-- Reconstruit ou réduit le rig au nouveau niveau de détail (même code, même table, même modèle)
function NebbyBuilder.setLod(rig: Rig, lod: Lod): Rig
	local target = normalizeLod(lod)
	if rig.kind ~= "nebby" or rig.destroyed or rig.lod == target then
		return rig
	end
	clear(rig)
	fill(rig, target)
	return rig
end

-- Met à jour rig.pose (oscillations d'archétype), le clignement, les teintes HSV et l'orbite
function NebbyBuilder.animate(rig: Rig, state: AnimState)
	if rig.lod == "hidden" or #rig.parts == 0 then
		return
	end
	local t = state.t
	local ph = state.phase
	local pose = rig.pose
	local offsets = rig.offsets
	local anims = rig.anims
	for i = 2, #offsets do
		local a = anims[i]
		local mode = a.mode
		if mode == "puff" then
			local k = 1 + a.amp * math.sin(TAU * a.freq * t + ph + a.phase)
			local off = offsets[i]
			pose[i] = (off - off.Position) + off.Position * k
		elseif mode == "sway" or mode == "flap" then
			local angle = a.sign * a.amp * math.sin(TAU * a.freq * t + ph + a.phase)
			pose[i] = (a.pivot :: CFrame) * CFrame.Angles(0, 0, angle) * (a.pivotInvOffset :: CFrame)
		elseif mode == "spin" then
			pose[i] = CFrame.Angles(0, TAU * a.freq * t + ph, 0) * offsets[i]
		elseif mode == "bounce" then
			pose[i] = offsets[i] + Vector3.new(0, a.amp * math.sin(TAU * a.freq * t + ph + a.phase), 0)
		elseif mode == "tail" then
			local boost = 1 + math.min(math.max(state.speed, 0) / FAR_TAIL_SPEED, 1)
			pose[i] = offsets[i]
				+ Vector3.new(a.amp * boost * math.sin(TAU * a.freq * t + ph + a.phase), 0, 0)
		end
	end
	local blink = state.blink == true
	if blink ~= rig.blinking and #rig.eyes > 0 then
		rig.blinking = blink
		local scale = if blink then BLINK_SCALE else OPEN_SCALE
		for _, mesh in rig.eyes do
			mesh.Scale = scale
		end
	end
	if #rig.hsv > 0 then
		local look = lookOf(rig.code)
		for _, entry in rig.hsv do
			if entry.role == "body" then
				entry.part.Color = bodyColorOf(look, t)
			else
				entry.part.Color = hsvColor(t, COSMIC_PERIOD, COSMIC_SATURATION, entry.offset)
			end
		end
	end
	local orbit = rig.orbit
	if orbit then
		orbit.CFrame = CFrame.Angles(0, TAU * t / ORBIT_PERIOD + ph, 0)
			* CFrame.new(ORBIT_RADIUS * rig.size, 0.1 * rig.size, 0)
	end
end

-- Ajoute les pièces du rig et leurs CFrame monde (root × pose) aux listes de BulkMoveTo
function NebbyBuilder.appendCFrames(rig: Rig, root: CFrame, parts: { BasePart }, cframes: { CFrame })
	local n = #parts
	local pose = rig.pose
	for i, part in rig.parts do
		parts[n + i] = part
		cframes[n + i] = root * pose[i]
	end
end

-- Taille du corps (studs), Huge compris
function NebbyBuilder.bodySize(code: Types.NebbyCode): number
	return lookOf(code).size
end

-- Couleur du corps à l'instant t (cycle HSV pour Prismatic / Cosmique)
function NebbyBuilder.bodyColor(code: Types.NebbyCode, t: number?): Color3
	return bodyColorOf(lookOf(code), t or 0)
end

-- Nombre de pièces du rig pour ce code et ce niveau de détail, options par défaut (budget §12.8)
function NebbyBuilder.partCount(code: Types.NebbyCode, lod: Lod): number
	local level = normalizeLod(lod)
	if level == "hidden" then
		return 0
	elseif level == "ball" then
		return 1
	end
	return #plan(lookOf(code), DEFAULT_OPTS)
end

-- Gloomwisp (GDD §11.6) : Ball indigo 2,4 + 3 bouffées + 2 yeux Néon ovales + Trail violet
local WISP_SPECS: { Recipes.PartSpec } = {
	{
		name = "Body",
		shape = "Ball",
		size = Vector3.one,
		cframe = CFrame.identity,
		color = "body",
		anim = "static",
	},
	{
		name = "Puff1",
		shape = "Ball",
		size = Vector3.new(0.42, 0.42, 0.42),
		cframe = CFrame.new(-0.38, 0.28, 0.18),
		color = "accent",
		anim = "puff",
		amp = WISP_TREMBLE,
		freq = WISP_TREMBLE_HZ,
	},
	{
		name = "Puff2",
		shape = "Ball",
		size = Vector3.new(0.38, 0.38, 0.38),
		cframe = CFrame.new(0.4, 0.24, 0.2),
		color = "accent",
		anim = "puff",
		amp = WISP_TREMBLE,
		freq = WISP_TREMBLE_HZ,
		phase = 2,
	},
	{
		name = "Puff3",
		shape = "Ball",
		size = Vector3.new(0.4, 0.4, 0.4),
		cframe = CFrame.new(0, 0.46, 0.26),
		color = "accent",
		anim = "puff",
		amp = WISP_TREMBLE,
		freq = WISP_TREMBLE_HZ,
		phase = 4,
	},
	{
		name = "EyeL",
		shape = "Eye",
		size = Vector3.new(0.15, 0.24, 0.1),
		cframe = CFrame.new(-0.17, 0.1, -0.45),
		color = "eye",
		anim = "puff",
		amp = WISP_TREMBLE * 0.5,
		freq = WISP_TREMBLE_HZ,
	},
	{
		name = "EyeR",
		shape = "Eye",
		size = Vector3.new(0.15, 0.24, 0.1),
		cframe = CFrame.new(0.17, 0.1, -0.45),
		color = "eye",
		anim = "puff",
		amp = WISP_TREMBLE * 0.5,
		freq = WISP_TREMBLE_HZ,
	},
}

function NebbyBuilder.buildWisp(): Rig
	local model = Instance.new("Model")
	model.Name = "Gloomwisp"
	local rig = emptyRig(model, "wisp", 0, 0, "full", WISP_SIZE, DEFAULT_OPTS)
	assemble(rig, WISP_SPECS, WISP_SIZE, function(spec)
		if spec.color == "eye" then
			return { color = WISP_EYE_COLOR, material = Enum.Material.Neon }
		elseif spec.color == "accent" then
			return { color = WISP_PUFF_COLOR, material = Enum.Material.SmoothPlastic }
		end
		return { color = WISP_COLOR, material = Enum.Material.SmoothPlastic }
	end)
	addTrail(rig.body, 0.35 * WISP_SIZE, WISP_TRAIL_COLOR, WISP_COLOR, TRAIL_LIFETIME * 2)
	return rig
end

-- Orbe de la Comète au sol (3 studs + anneau Néon doré qui tourne)
local ORB_SPECS: { Recipes.PartSpec } = {
	{
		name = "Orb",
		shape = "Ball",
		size = Vector3.one,
		cframe = CFrame.identity,
		color = "body",
		anim = "static",
	},
	{
		name = "Ring",
		shape = "Cylinder",
		size = Vector3.new(0.07, 1.7, 1.7),
		cframe = CFrame.Angles(0, 0, math.pi / 2),
		color = "accent",
		anim = "spin",
		freq = 0.5,
	},
	{
		name = "Ring2",
		shape = "Cylinder",
		size = Vector3.new(0.05, 1.4, 1.4),
		cframe = CFrame.Angles(math.rad(60), 0, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = "crown",
		anim = "spin",
		freq = -0.35,
	},
}

function NebbyBuilder.buildCometOrb(): Rig
	local model = Instance.new("Model")
	model.Name = "CometOrb"
	local rig = emptyRig(model, "cometOrb", 0, 0, "full", COMET_ORB_SIZE, DEFAULT_OPTS)
	assemble(rig, ORB_SPECS, COMET_ORB_SIZE, function(spec)
		if spec.color == "accent" then
			return { color = COMET_RING_COLOR, material = Enum.Material.Neon }
		elseif spec.color == "crown" then
			return { color = COMET_RING2_COLOR, material = Enum.Material.Neon }
		end
		return { color = COMET_COLOR, material = Enum.Material.Neon }
	end)
	local light = Instance.new("PointLight")
	light.Range = COMET_LIGHT_RANGE
	light.Brightness = COMET_LIGHT_BRIGHTNESS
	light.Color = COMET_COLOR
	light.Shadows = false
	light.Parent = rig.body
	return rig
end

-- Comète dans le ciel (Ball Néon 6 + Fire + Trail + Sparkles) ; PrimaryPart = Core
function NebbyBuilder.buildCometSky(): Model
	local model = Instance.new("Model")
	model.Name = "CometSky"
	local core = newPart("Ball")
	core.Name = "Core"
	core.Size = Vector3.one * COMET_SKY_SIZE
	core.Color = COMET_COLOR
	core.Material = Enum.Material.Neon
	core.Parent = model
	local fire = Instance.new("Fire")
	fire.Size = COMET_FIRE_SIZE
	fire.Heat = COMET_FIRE_HEAT
	fire.Color = COMET_FIRE_COLOR
	fire.SecondaryColor = COMET_FIRE_SECONDARY
	fire.Parent = core
	addTrail(core, COMET_SKY_SIZE * 0.4, COMET_COLOR, COMET_FIRE_COLOR, COMET_TRAIL_LIFETIME)
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = COMET_RING_COLOR
	sparkles.Parent = core
	model.PrimaryPart = core
	return model
end

function NebbyBuilder.destroy(rig: Rig)
	if rig.destroyed then
		return
	end
	rig.destroyed = true
	clear(rig)
	rig.model:Destroy()
	rig.lod = "hidden"
	rig.body = placeholder()
end

return NebbyBuilder
