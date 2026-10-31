--!strict
-- Fx — aide du paquet « client-world » : briques communes de CongaRenderer et VFXController.
--   * dossiers clients (workspace.ClientWorld et ses sous-dossiers, créés à la demande)
--   * pièces décoratives (ancrées, sans collision ni requête ni ombre) et porteur d'attachements
--   * courbes d'adoucissement (Back, Quad, Elastic, Sine) pour les animations faites à la main
--   * mise à l'échelle d'un rig de NebbyBuilder (écrasement, apparition, fondu en RÉTRÉCISSANT :
--     la Transparency des pièces 3D reste 0 ou 1, GDD §9.1)
-- Aucun état de jeu : fonctions pures ou constructeurs d'Instances.
-- GDD : §9.1 (règles), §12.8 (pièces décoratives ancrées).

local Fx = {}

local CLIENT_WORLD = "ClientWorld"

-- Dossier workspace.ClientWorld (créé s'il manque)
function Fx.clientWorld(): Folder
	local existing = workspace:FindFirstChild(CLIENT_WORLD)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = CLIENT_WORLD
	folder.Parent = workspace
	return folder
end

-- Sous-dossier `name` de `parent` (créé s'il manque)
function Fx.folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

export type Shape = "Ball" | "Block" | "Cylinder"

-- Pièce décorative : ancrée, sans collision, sans requête, sans contact, sans ombre
function Fx.part(name: string, shape: Shape, size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	end
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Anneau plat (Cylinder couché) de diamètre `diameter` et d'épaisseur `thickness`
function Fx.ring(
	name: string,
	diameter: number,
	thickness: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Fx.part(name, "Cylinder", Vector3.new(thickness, diameter, diameter), color, material)
end

-- Orientation d'un Cylinder couché (axe X → vertical)
Fx.FLAT = CFrame.Angles(0, 0, math.pi / 2)

-- Pièce invisible ancrée à l'origine : ses Attachments servent de points monde (Beams, billboards)
function Fx.anchor(name: string, parent: Instance): Part
	local part = Fx.part(name, "Block", Vector3.one, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	part.Transparency = 1
	part.CFrame = CFrame.identity
	part.Parent = parent
	return part
end

-- Courbes d'adoucissement (a ∈ [0 ; 1]) --------------------------------------------------------

function Fx.clamp01(a: number): number
	if a ~= a then
		return 0
	end
	return math.clamp(a, 0, 1)
end

function Fx.quadOut(a: number): number
	local x = Fx.clamp01(a)
	return 1 - (1 - x) * (1 - x)
end

function Fx.quadIn(a: number): number
	local x = Fx.clamp01(a)
	return x * x
end

function Fx.sineInOut(a: number): number
	local x = Fx.clamp01(a)
	return 0.5 - 0.5 * math.cos(math.pi * x)
end

local BACK = 1.70158
function Fx.backOut(a: number): number
	local x = Fx.clamp01(a) - 1
	return 1 + x * x * ((BACK + 1) * x + BACK)
end

function Fx.backIn(a: number): number
	local x = Fx.clamp01(a)
	return x * x * ((BACK + 1) * x - BACK)
end

function Fx.elasticOut(a: number): number
	local x = Fx.clamp01(a)
	if x == 0 or x == 1 then
		return x
	end
	return 2 ^ (-10 * x) * math.sin((x * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

-- Hauteur d'une parabole de sommet `apex` à l'avancement a
function Fx.arc(a: number, apex: number): number
	local x = Fx.clamp01(a)
	return 4 * apex * x * (1 - x)
end

-- Rigs de NebbyBuilder : mise à l'échelle non uniforme -----------------------------------------

-- Tailles de repos des pièces (mémorisées au premier écrasement, clés faibles)
local baseSizes: { [BasePart]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any

type RigLike = { parts: { BasePart }, pose: { CFrame } }

local function scaledCFrame(cf: CFrame, s: Vector3): CFrame
	local p = cf.Position
	return CFrame.new(p.X * s.X, p.Y * s.Y, p.Z * s.Z) * cf.Rotation
end

local function isBall(part: BasePart): boolean
	return part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Ball
end

-- Applique l'échelle `s` aux tailles des pièces (Vector3.one rend les tailles de repos). Une pièce
-- Ball ne peut pas être déformée (taille toujours uniforme dans Roblox) : elle reçoit l'échelle
-- uniforme de même volume, l'écrasement se lit alors sur la pose (yeux, accents)
function Fx.scaleRig(rig: RigLike, s: Vector3)
	local uniform = (s.X * s.Y * s.Z) ^ (1 / 3)
	for _, part in rig.parts do
		local base = baseSizes[part]
		if base == nil then
			if s == Vector3.one then
				continue
			end
			base = part.Size
			baseSizes[part] = base
		end
		part.Size = if isBall(part) then base * uniform else base * s
		if s == Vector3.one then
			baseSizes[part] = nil
		end
	end
end

-- Ajoute les pièces du rig (pose écrasée par `s`) aux listes d'un BulkMoveTo
function Fx.appendScaled(rig: RigLike, root: CFrame, s: Vector3, parts: { BasePart }, cframes: { CFrame })
	local n = #parts
	for i, part in rig.parts do
		parts[n + i] = part
		cframes[n + i] = root * scaledCFrame(rig.pose[i], s)
	end
end

-- Séquence de transparence en pointillés (Beam) : `dashes` traits pleins séparés de vides
function Fx.dashed(dashes: number): NumberSequence
	local keys = {}
	local n = math.clamp(math.floor(dashes), 1, 4) -- 4n points ≤ 16 (limite moteur : 20)
	local step = 1 / (2 * n)
	table.insert(keys, NumberSequenceKeypoint.new(0, 0.1))
	for k = 1, 2 * n - 1 do
		local t = k * step
		local solid = k % 2 == 0
		table.insert(keys, NumberSequenceKeypoint.new(t - 0.001, if solid then 1 else 0.1))
		table.insert(keys, NumberSequenceKeypoint.new(t, if solid then 0.1 else 1))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 1))
	return NumberSequence.new(keys)
end

return Fx
