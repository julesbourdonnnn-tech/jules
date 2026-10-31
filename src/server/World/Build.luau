--!strict
-- Construction du monde en primitives (aucun asset externe).
-- Tout le décor est ancré, sans collision ni requêtes, et sans ombre pour les petites pièces.
--   local p = Build.part({ Size = Vector3.new(8, 1, 8), CFrame = CFrame.new(0, 0, 0), Color = ..., Parent = model })
--   Build.tree(model, Vector3.new(10, 0, 4), 1.2, Random.new(1))
--   Build.tag(part, "Spin", { speed = 1 })   -- animé côté client par WorldFXController

local CollectionService = game:GetService("CollectionService")

local Build = {}

type Props = { [string]: any }

local DECOR_DEFAULTS: Props = {
	Anchored = true,
	CanCollide = false,
	CanTouch = false,
	CanQuery = false,
	CastShadow = false,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
	Material = Enum.Material.SmoothPlastic,
}

local function apply(inst: Instance, defaults: Props, props: Props?)
	local parent = nil
	for k, v in defaults do
		(inst :: any)[k] = v
	end
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
end

-- Pièce décorative (pas de collision) ; passer CanCollide = true pour un sol/mur
function Build.part(props: Props?): Part
	local p = Instance.new("Part")
	apply(p, DECOR_DEFAULTS, props)
	return p
end

-- Sol / plateforme solide
function Build.solid(props: Props?): Part
	local p = Instance.new("Part")
	apply(p, DECOR_DEFAULTS, props)
	p.CanCollide = true
	p.CanQuery = true
	p.CastShadow = true
	return p
end

function Build.wedge(props: Props?): WedgePart
	local p = Instance.new("WedgePart")
	apply(p, DECOR_DEFAULTS, props)
	return p
end

function Build.cylinder(props: Props?): Part
	local p = Build.part(props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function Build.ball(props: Props?): Part
	local p = Build.part(props)
	p.Shape = Enum.PartType.Ball
	return p
end

function Build.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

function Build.folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Tag + attributs lus par les effets client (Spin, Float, Pulse, Bob…)
function Build.tag(inst: Instance, tag: string, attributes: { [string]: any }?)
	if attributes then
		for k, v in attributes do
			inst:SetAttribute(k, v)
		end
	end
	CollectionService:AddTag(inst, tag)
end

-- Variation de teinte (±amount) pour éviter l'aspect « copier-coller »
function Build.vary(color: Color3, rng: Random, amount: number?): Color3
	local h, s, v = color:ToHSV()
	local a = amount or 0.04
	return Color3.fromHSV(
		(h + rng:NextNumber(-a, a) * 0.5) % 1,
		math.clamp(s + rng:NextNumber(-a, a), 0, 1),
		math.clamp(v + rng:NextNumber(-a, a), 0, 1)
	)
end

-- Arbre stylisé : tronc cylindrique + 2-3 boules de feuillage
function Build.tree(parent: Instance, base: Vector3, scale: number, rng: Random, leafColor: Color3?): Model
	local m = Build.model("Tree", parent)
	local trunkHeight = 6 * scale
	Build.cylinder({
		Name = "Trunk",
		Size = Vector3.new(trunkHeight, 1.4 * scale, 1.4 * scale),
		CFrame = CFrame.new(base + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(122, 84, 56),
		Material = Enum.Material.Wood,
		Parent = m,
	})
	local leaves = leafColor or Color3.fromRGB(96, 186, 92)
	local clusters = rng:NextInteger(2, 3)
	for i = 1, clusters do
		local size = (4.5 - i * 0.6) * scale * rng:NextNumber(0.9, 1.15)
		local offset = Vector3.new(
			rng:NextNumber(-1, 1) * scale,
			trunkHeight + (i - 1) * 1.8 * scale,
			rng:NextNumber(-1, 1) * scale
		)
		Build.ball({
			Name = "Leaves",
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(base + offset),
			Color = Build.vary(leaves, rng),
			Material = Enum.Material.Grass,
			Parent = m,
		})
	end
	return m
end

-- Rocher : 1-3 blocs inclinés
function Build.rock(parent: Instance, base: Vector3, scale: number, rng: Random, color: Color3?): Model
	local m = Build.model("Rock", parent)
	local tint = color or Color3.fromRGB(140, 140, 150)
	for _ = 1, rng:NextInteger(1, 3) do
		local s = scale * rng:NextNumber(1.5, 3)
		Build.part({
			Name = "Stone",
			Size = Vector3.new(s, s * 0.7, s * 0.9),
			CFrame = CFrame.new(
				base + Vector3.new(rng:NextNumber(-1, 1) * scale, s * 0.25, rng:NextNumber(-1, 1) * scale)
			) * CFrame.Angles(
				rng:NextNumber(-0.4, 0.4),
				rng:NextNumber(0, math.pi * 2),
				rng:NextNumber(-0.4, 0.4)
			),
			Color = Build.vary(tint, rng),
			Material = Enum.Material.Slate,
			Parent = m,
		})
	end
	return m
end

-- Nuage flottant (animé côté client)
function Build.cloud(parent: Instance, center: Vector3, scale: number, rng: Random): Model
	local m = Build.model("Cloud", parent)
	for i = 1, rng:NextInteger(3, 5) do
		local s = scale * rng:NextNumber(3, 6)
		local p = Build.ball({
			Name = "Puff",
			Size = Vector3.new(s, s * 0.8, s),
			CFrame = CFrame.new(
				center
					+ Vector3.new(
						(i - 3) * scale * 2.2,
						rng:NextNumber(-1, 1) * scale,
						rng:NextNumber(-1.5, 1.5) * scale
					)
			),
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0,
			Parent = m,
		})
		Build.tag(
			p,
			"Float",
			{ amplitude = 0.6 * scale, period = rng:NextNumber(5, 8), phase = rng:NextNumber(0, 6.28) }
		)
	end
	return m
end

-- Lampadaire avec lumière douce
function Build.lamp(parent: Instance, base: Vector3, color: Color3?): Model
	local m = Build.model("Lamp", parent)
	Build.cylinder({
		Name = "Pole",
		Size = Vector3.new(8, 0.5, 0.5),
		CFrame = CFrame.new(base + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 56, 70),
		Material = Enum.Material.Metal,
		Parent = m,
	})
	local bulb = Build.ball({
		Name = "Bulb",
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = CFrame.new(base + Vector3.new(0, 8.4, 0)),
		Color = color or Color3.fromRGB(255, 226, 150),
		Material = Enum.Material.Neon,
		Parent = m,
	})
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Brightness = 1.2
	light.Color = color or Color3.fromRGB(255, 226, 150)
	light.Shadows = false
	light.Parent = bulb
	return m
end

-- Panneau avec texte (SurfaceGui), lisible des deux côtés
function Build.sign(parent: Instance, cframe: CFrame, size: Vector2, text: string, color: Color3?): Part
	local board = Build.part({
		Name = "Sign",
		Size = Vector3.new(size.X, size.Y, 0.4),
		CFrame = cframe,
		Color = color or Color3.fromRGB(70, 60, 110),
		Parent = parent,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(20, 16, 36)
		stroke.Parent = label
	end
	return board
end

-- Étiquette flottante au-dessus d'un objet (BillboardGui)
function Build.billboard(adornee: BasePart, text: string, offsetY: number, maxDistance: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 80
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 16, 36)
	stroke.Parent = label
	gui.Parent = adornee
	return gui
end

-- Émetteur de particules avec la texture par défaut de Roblox
function Build.particles(parent: Instance, props: Props?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(6, 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 0.6
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(e :: any)[k] = v
			end
		end
	end
	e.Parent = parent
	return e
end

return Build
