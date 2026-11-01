--!strict
-- Parts (paquet world, aide de WorldService). Fabrique des pièces du monde, toutes construites
-- selon la règle robuste du GDD §11.1 et de docs/04 §3.1 :
--   * toutes ANCRÉES, CanTouch = false (le jeu n'écoute jamais Touched) ;
--   * décor : CanCollide = CanQuery = false, ombres coupées sur les petites pièces ;
--   * solides : seulement les boîtes de Logic/WorldLayout.solids(), invisibles, tag « Solid ».
-- Les « boules » non uniformes (corps, collines, coussins) sont des blocs + SpecialMesh Sphere : une
-- Part Ball reste toujours ronde dans Roblox. Les cylindres sont verticaux (axe X tourné vers Y).
-- Montrer / cacher : Transparency 0 ou 1 seulement (GDD §9.1), la transparence propre d'une pièce
-- (verre, gelée) est gardée dans l'attribut « BaseTransparency ».

local CollectionService = game:GetService("CollectionService")

local Parts = {}

Parts.SOLID_TAG = "Solid"
Parts.BASE_TRANSPARENCY = "BaseTransparency"

-- Orientation d'un cylindre vertical (l'axe d'un cylindre Roblox est X)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
Parts.UPRIGHT = UPRIGHT

export type Options = {
	name: string?,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	shadow: boolean?,
	reflectance: number?,
}

local function base(
	className: string,
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	opts: Options?
): BasePart
	local o: Options = opts or {}
	local part = Instance.new(className) :: BasePart
	part.Name = o.name or className
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = o.shadow == true
	part.Material = o.material or Enum.Material.SmoothPlastic
	part.Color = o.color or Color3.new(1, 1, 1)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if o.reflectance then
		part.Reflectance = o.reflectance
	end
	if o.transparency and o.transparency > 0 then
		part.Transparency = o.transparency
		part:SetAttribute(Parts.BASE_TRANSPARENCY, o.transparency)
	end
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- Bloc de décor
function Parts.block(parent: Instance, cframe: CFrame, size: Vector3, opts: Options?): BasePart
	return base("Part", parent, cframe, size, opts)
end

-- Coin (toit des maisons) : pente de l'arrière-haut (+Z) vers l'avant-bas (−Z)
function Parts.wedge(parent: Instance, cframe: CFrame, size: Vector3, opts: Options?): BasePart
	return base("WedgePart", parent, cframe, size, opts)
end

-- Boule ronde (diamètre unique)
function Parts.ball(parent: Instance, position: Vector3, diameter: number, opts: Options?): BasePart
	local part = base("Part", parent, CFrame.new(position), Vector3.new(diameter, diameter, diameter), opts);
	(part :: Part).Shape = Enum.PartType.Ball
	return part
end

-- Ellipsoïde (bloc + SpecialMesh Sphere) : boules aplaties, gouttes, coussins
function Parts.ellipsoid(parent: Instance, cframe: CFrame, size: Vector3, opts: Options?): BasePart
	local part = base("Part", parent, cframe, size, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Cylindre vertical : centre de la base en `baseCFrame` (Y vers le haut), diamètre, hauteur
function Parts.cylinder(
	parent: Instance,
	baseCFrame: CFrame,
	diameter: number,
	height: number,
	opts: Options?
): BasePart
	local cframe = baseCFrame * CFrame.new(0, height / 2, 0) * UPRIGHT
	local part = base("Part", parent, cframe, Vector3.new(height, diameter, diameter), opts);
	(part :: Part).Shape = Enum.PartType.Cylinder
	return part
end

-- Disque dont l'axe est l'axe Z de `cframe` (sucette, panneau rond)
function Parts.disc(
	parent: Instance,
	cframe: CFrame,
	diameter: number,
	thickness: number,
	opts: Options?
): BasePart
	local part = base(
		"Part",
		parent,
		cframe * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(thickness, diameter, diameter),
		opts
	);
	(part :: Part).Shape = Enum.PartType.Cylinder
	return part
end

-- Pièce solide exactement égale à une boîte de WorldLayout.solids() (invisible, collision, tag)
function Parts.solid(parent: Instance, name: string, cframe: CFrame, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	CollectionService:AddTag(part, Parts.SOLID_TAG)
	part.Parent = parent
	return part
end

-- Dossier (Folder) nommé
function Parts.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Modèle nommé (pivot à `pivot`)
function Parts.model(parent: Instance, name: string, pivot: CFrame?): Model
	local m = Instance.new("Model")
	m.Name = name
	if pivot then
		m.WorldPivot = pivot
	end
	m.Parent = parent
	return m
end

-- Montre ou cache une pièce (Transparency 0 / 1, transparence propre gardée) ; n'écrit que si besoin
function Parts.setVisible(part: BasePart, visible: boolean)
	local target = 1
	if visible then
		local own = part:GetAttribute(Parts.BASE_TRANSPARENCY)
		target = if type(own) == "number" then own else 0
	end
	if part.Transparency ~= target then
		part.Transparency = target
	end
end

-- Toutes les pièces (BasePart) d'une instance et de ses descendants
function Parts.collect(root: Instance): { BasePart }
	local out: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(out, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- Lumière ponctuelle (éteinte par défaut ; le client allume celles de son budget)
function Parts.light(
	parent: BasePart,
	color: Color3,
	range: number,
	brightness: number,
	enabled: boolean,
	tag: string?
)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Enabled = enabled
	if tag then
		CollectionService:AddTag(light, tag)
	end
	light.Parent = parent
	return light
end

return Parts
