--!strict
-- Nests — paquet « world » : les 12 Nids de Lumora (GDD §11.3, docs §3.1-§3.2).
-- Nest_XX (Model persistant, tag « Nest », attribut Slot fixe) : Platform, Gate { PostL, PostR,
-- Arch (7 pièces tag « NestArch ») }, Observatory, BillboardAnchor (Y = 16), Spawn
-- (SpawnLocation neutre, Duration 0, invisible, sans collision), Perches (Perch_01 … Perch_NN).
-- Un Nid libre est gris, arche sans Néon ; un Nid occupé prend la couleur de son propriétaire
-- (setAppearance, appelé par WorldService.setNestAppearance ← NestService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Cosmetics = require(Shared.Config.Cosmetics)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Build = require(script.Parent.Build)
local Palette = require(script.Parent.Palette)

local Nests = {}

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)

export type NestState = {
	slot: number,
	model: Model,
	platform: BasePart,
	arch: { BasePart },
	spawn: SpawnLocation,
	perches: Folder,
	perchParts: { BasePart }, -- index → perchoir construit
	platformColor: Color3?, -- nil = Nid libre
	archColor: Color3?,
}

local states: { [number]: NestState } = {}

-- Nombre total de perchoirs possibles (46 : somme des anneaux de Zones.Perches)
type PerchRing = { radius: number, count: number, y: number }
local TOTAL_PERCHES = 0
local perchRing: { PerchRing } = {}
do
	for _, ring in Zones.Perches.Rings do
		for _ = 1, ring.count do
			TOTAL_PERCHES += 1
			perchRing[TOTAL_PERCHES] = ring
		end
	end
end

function Nests.totalPerches(): number
	return TOTAL_PERCHES
end

local function nestName(slot: number): string
	return string.format("Nest_%02d", slot)
end

local function initialAttributes(model: Model, slot: number)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Color", Cosmetics.FreeNestColor)
	model:SetAttribute("Supernovas", 0)
	model:SetAttribute("PerchCount", 0)
	model:SetAttribute("PerchData", "")
	model:SetAttribute("Title", "")
	model:SetAttribute("NestTheme", "default")
	model:SetAttribute("LineStyle", "default")
end

-- Porte : 2 poteaux Marble + arche de ArchPieces pièces en demi-ellipse de ArchBottomY à ArchTopY
local function buildGate(model: Model, slot: number): { BasePart }
	local N = Zones.Nests
	local gate = Build.model("Gate", model)
	local gateCF = WorldLayout.gateCFrame(slot)
	local groundY = WorldLayout.groundY(gateCF.Position.X, gateCF.Position.Z)
	local base = (gateCF - gateCF.Position) + Vector3.new(gateCF.Position.X, groundY, gateCF.Position.Z)
	for _, side in { -1, 1 } do
		local post = Build.solid({
			Name = if side < 0 then "PostL" else "PostR",
			Size = Vector3.new(N.GatePostHeight, N.GatePostDiameter, N.GatePostDiameter),
			CFrame = base * CFrame.new(side * N.GatePostOffset, N.GatePostHeight / 2, 0) * VERTICAL,
			Color = Palette.Marble,
			Material = Enum.Material.Marble,
			Parent = gate,
		})
		post.Shape = Enum.PartType.Cylinder
	end
	local archFolder = Build.folder("Arch", gate)
	local pieces: { BasePart } = {}
	local rise = N.ArchTopY - N.ArchBottomY
	local function point(i: number): Vector3
		local theta = math.pi * i / N.ArchPieces
		return (base * CFrame.new(
			N.GatePostOffset * math.cos(theta),
			N.ArchBottomY + rise * math.sin(theta),
			0
		)).Position
	end
	for i = 1, N.ArchPieces do
		local p0 = point(i - 1)
		local p1 = point(i)
		local mid = (p0 + p1) / 2
		local length = (p1 - p0).Magnitude + Palette.ArchThickness * 0.5
		local piece = Build.part({
			Name = string.format("Arch_%d", i),
			Size = Vector3.new(Palette.ArchThickness, Palette.ArchThickness, length),
			CFrame = CFrame.lookAt(mid, p1),
			Color = Palette.FreeArch,
			Material = Enum.Material.SmoothPlastic,
			Parent = archFolder,
		})
		Build.tag(piece, "NestArch", { index = i, slot = slot })
		pieces[i] = piece
	end
	return pieces
end

-- Observatoire : tour Marble, dôme Glass, télescope incliné vers le ciel, côté extérieur
local function buildObservatory(model: Model, slot: number)
	local N = Zones.Nests
	local obs = Build.model("Observatory", model)
	local cf = WorldLayout.observatoryCFrame(slot)
	local groundY = WorldLayout.groundY(cf.Position.X, cf.Position.Z)
	local foot = Vector3.new(cf.Position.X, groundY, cf.Position.Z)
	local tower = Build.solid({
		Name = "Tower",
		Size = Vector3.new(N.ObservatoryHeight, N.ObservatoryDiameter, N.ObservatoryDiameter),
		CFrame = CFrame.new(foot + Vector3.new(0, N.ObservatoryHeight / 2, 0)) * VERTICAL,
		Color = Palette.Marble,
		Material = Enum.Material.Marble,
		Parent = obs,
	})
	tower.Shape = Enum.PartType.Cylinder
	local domeCenter = foot + Vector3.new(0, N.ObservatoryHeight, 0)
	Build.ball({
		Name = "Dome",
		Size = Vector3.one * Palette.DomeDiameter,
		CFrame = CFrame.new(domeCenter),
		Color = Palette.DomeColor,
		Material = Enum.Material.Glass,
		Parent = obs,
	})
	-- télescope : vers l'extérieur de l'île, incliné de TelescopeTilt degrés
	local outward = -cf.LookVector
	local tilt = math.rad(Palette.TelescopeTilt)
	local dir = (outward * math.cos(tilt) + Vector3.yAxis * math.sin(tilt)).Unit
	local center = domeCenter + dir * (Palette.TelescopeLength / 2)
	Build.cylinder({
		Name = "Telescope",
		Size = Vector3.new(Palette.TelescopeLength, Palette.TelescopeDiameter, Palette.TelescopeDiameter),
		CFrame = CFrame.lookAt(center, center + dir) * CFrame.Angles(0, math.pi / 2, 0),
		Color = Palette.TelescopeColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = obs,
	})
end

local function buildNest(parent: Instance, slot: number): NestState
	local N = Zones.Nests
	local model = Build.model(nestName(slot), parent)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	initialAttributes(model, slot)
	local cf = WorldLayout.nestCFrame(slot)
	local center = cf.Position
	local rotation = cf - center

	local platform = Build.solid({
		Name = "Platform",
		Size = Vector3.new(N.PlatformThickness, N.PlatformDiameter, N.PlatformDiameter),
		CFrame = CFrame.new(center.X, N.PlatformTopY - N.PlatformThickness / 2, center.Z) * VERTICAL,
		Color = Cosmetics.FreeNestColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	platform.Shape = Enum.PartType.Cylinder

	local arch = buildGate(model, slot)
	buildObservatory(model, slot)

	Build.part({
		Name = "BillboardAnchor",
		Size = Vector3.one,
		CFrame = CFrame.new(center.X, N.BillboardY, center.Z),
		Transparency = 1,
		Parent = model,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Palette.SpawnSize
	spawn.CFrame = rotation + Vector3.new(center.X, N.PlatformTopY + Palette.SpawnSize.Y / 2, center.Z)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.CanQuery = false
	spawn.CastShadow = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Parent = model

	local perches = Build.folder("Perches", model)
	model.PrimaryPart = platform
	Build.tag(model, "Nest", { Slot = slot })
	return {
		slot = slot,
		model = model,
		platform = platform,
		arch = arch,
		spawn = spawn,
		perches = perches,
		perchParts = {},
		platformColor = nil,
		archColor = nil,
	}
end

function Nests.build(root: Instance): Folder
	table.clear(states)
	local folder = Build.folder("Nests", root)
	for slot = 1, Zones.Nests.Count do
		states[slot] = buildNest(folder, slot)
	end
	return folder
end

function Nests.get(slot: number): NestState?
	return states[slot]
end

-- Habillage (Néon couleur du propriétaire, ou gris sans lumière si libre) d'une pièce d'accent
local function paintAccent(part: BasePart, color: Color3?)
	if color then
		part.Color = color
		part.Material = Enum.Material.Neon
	else
		part.Color = Palette.FreeArch
		part.Material = Enum.Material.SmoothPlastic
	end
end

local function accentOfPerch(perch: BasePart): BasePart
	local ring = perch:FindFirstChild("Ring")
	if ring and ring:IsA("BasePart") then
		return ring
	end
	return perch -- disque flottant : la pièce elle-même est l'accent
end

-- Couleurs de la plateforme et de l'arche ; platform == nil → Nid libre (gris, sans Néon)
function Nests.setAppearance(slot: number, platform: Color3?, arch: Color3?)
	local state = states[slot]
	if state == nil then
		return
	end
	local archColor = if platform then arch or platform else nil
	state.platformColor = platform
	state.archColor = archColor
	state.platform.Color = platform or Cosmetics.FreeNestColor
	for _, piece in state.arch do
		paintAccent(piece, archColor)
	end
	for _, perch in state.perchParts do
		paintAccent(accentOfPerch(perch), archColor)
	end
end

local function buildPerch(state: NestState, index: number): BasePart
	local P = Zones.Perches
	local ring = perchRing[index]
	local cf = WorldLayout.perchCFrame(state.slot, index)
	local foot = cf.Position
	local rotation = cf - foot
	local name = string.format("Perch_%02d", index)
	local perch: BasePart
	if ring and ring.y > 0 then
		-- anneau haut : disque Néon flottant
		perch = Build.cylinder({
			Name = name,
			Size = Vector3.new(Palette.FloatingPerchThickness, P.Diameter, P.Diameter),
			CFrame = (rotation + foot + Vector3.new(0, Palette.FloatingPerchThickness / 2, 0)) * VERTICAL,
			Parent = state.perches,
		})
		paintAccent(perch, state.archColor)
	else
		-- perchoir au sol : Cylinder Wood surmonté d'un anneau Néon fin
		perch = Build.cylinder({
			Name = name,
			Size = Vector3.new(P.Height, P.Diameter, P.Diameter),
			CFrame = (rotation + foot + Vector3.new(0, P.Height / 2, 0)) * VERTICAL,
			Color = Palette.Wood,
			Material = Enum.Material.Wood,
			Parent = state.perches,
		})
		local ringDiameter = P.Diameter + Palette.PerchRingOverhang
		local accent = Build.cylinder({
			Name = "Ring",
			Size = Vector3.new(Palette.PerchRingThickness, ringDiameter, ringDiameter),
			CFrame = (rotation + foot + Vector3.new(0, P.Height - Palette.PerchRingThickness, 0)) * VERTICAL,
			Parent = perch,
		})
		paintAccent(accent, state.archColor)
	end
	-- dessus du perchoir (Y monde) : le client y pose le Nebby perché
	local top = if ring and ring.y > 0 then foot.Y + Palette.FloatingPerchThickness else foot.Y + P.Height
	perch:SetAttribute("Index", index)
	perch:SetAttribute("TopY", top)
	return perch
end

-- Crée ou détruit les perchoirs pour qu'il en existe exactement `count` (0-46)
function Nests.setPerchCount(slot: number, count: number)
	local state = states[slot]
	if state == nil then
		return
	end
	local target = math.clamp(math.floor(count), 0, TOTAL_PERCHES)
	for index = #state.perchParts, target + 1, -1 do
		local perch = state.perchParts[index]
		state.perchParts[index] = nil
		perch:Destroy()
	end
	for index = #state.perchParts + 1, target do
		state.perchParts[index] = buildPerch(state, index)
	end
end

function Nests.perchCount(slot: number): number
	local state = states[slot]
	return if state then #state.perchParts else 0
end

return Nests
