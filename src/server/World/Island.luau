--!strict
-- Island — paquet « world » : le disque de Lumora, ses sols, le rebord et les fissures du Cratère,
-- la falaise, les murs invisibles, les pas japonais et les lanternes (GDD §11.1).
-- Appelé une fois par WorldService.Init (synchrone, aucun yield). Positions : Logic/WorldLayout ;
-- dimensions : Config/Zones (+ détails visuels nommés de World/Palette).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Build = require(script.Parent.Build)
local Palette = require(script.Parent.Palette)

local Island = {}

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- l'axe X d'un Cylinder devient vertical
local TAU = 2 * math.pi

-- Disque solide (Cylinder vertical) dont le dessus est à `topY`
local function disc(
	name: string,
	diameter: number,
	thickness: number,
	topY: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Build.solid({
		Name = name,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(0, topY - thickness / 2, 0) * VERTICAL,
		Color = color,
		Material = material,
		Parent = parent,
	})
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Rebord du Cratère : RimSegments segments de 2 WedgeParts dos à dos (pente vers l'intérieur et
-- vers l'extérieur), interrompus par des ouvertures de RimGap studs alignées sur les chemins
local function buildRim(parent: Instance, rng: Random)
	local G = Zones.Ground
	local rim = Build.model("CraterRim", parent)
	local mid = (G.RimInner + G.RimOuter) / 2
	local depth = (G.RimOuter - G.RimInner) / 2
	local step = TAU / G.RimSegments
	local length = math.max(1, mid * step - G.RimGap)
	local baseY = G.GladeTopY
	for k = 0, G.RimSegments - 1 do
		local a = (k + 0.5) * step -- les ouvertures sont centrées sur les chemins (k × 30°)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local color = Build.vary(G.CraterColor, rng, 0.03)
		for _, side in { -1, 1 } do
			-- côté intérieur : la pente (avant du WedgePart) regarde le centre ; extérieur : le bord
			local r = mid + side * depth / 2
			local pos = out * r + Vector3.new(0, baseY + G.RimHeight / 2, 0)
			local facing = out * side
			local wedge = Build.wedge({
				Name = if side < 0 then "RimInner" else "RimOuter",
				Size = Vector3.new(length, G.RimHeight, depth),
				CFrame = CFrame.lookAt(pos, pos + facing),
				Color = color,
				Material = Enum.Material.Basalt,
				Parent = rim,
			})
			wedge.CanCollide = true
			wedge.CanQuery = true
		end
	end
	return rim
end

local function buildCracks(parent: Instance, rng: Random)
	local G = Zones.Ground
	local folder = Build.folder("Cracks", parent)
	for i, cf in WorldLayout.decor().cracks do
		local length = rng:NextNumber(G.CrackLengthMin, G.CrackLengthMax)
		local rotation = cf - cf.Position
		local pos = Vector3.new(cf.Position.X, G.CraterTopY + Palette.CrackHeight / 2, cf.Position.Z)
		Build.part({
			Name = string.format("Crack_%02d", i),
			Size = Vector3.new(Palette.CrackWidth, Palette.CrackHeight, length),
			CFrame = rotation + pos,
			Color = G.CrackColor,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
	end
	return folder
end

-- Falaise : CliffCount WedgeParts sous le bord, pleine largeur en haut (r CliffInner → CliffOuter),
-- qui se resserrent vers l'intérieur jusqu'à CliffBottomY
local function buildCliff(parent: Instance, rng: Random)
	local I = Zones.Island
	local cliff = Build.model("Cliff", parent)
	local mid = (I.CliffInner + I.CliffOuter) / 2
	local depth = I.CliffOuter - I.CliffInner
	local top = I.TopY - Palette.CliffTopGap
	local height = top - I.CliffBottomY
	local length = TAU * mid / I.CliffCount * Palette.CliffOverlap
	for k = 0, I.CliffCount - 1 do
		local a = k * TAU / I.CliffCount
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = out * mid + Vector3.new(0, (top + I.CliffBottomY) / 2, 0)
		-- repère : Y local vers le bas, Z local vers le centre → le pied du WedgePart (pleine
		-- largeur) est en haut et l'arête haute du WedgePart forme le bas, côté intérieur
		local down = Vector3.new(0, -1, 0)
		local inward = -out
		local right = down:Cross(inward)
		Build.wedge({
			Name = "Cliff",
			Size = Vector3.new(length, height, depth),
			CFrame = CFrame.fromMatrix(pos, right, down, inward),
			Color = Build.vary(I.CliffColor, rng, 0.03),
			Material = Enum.Material.Slate,
			Parent = cliff,
		})
	end
	return cliff
end

local function buildWalls(parent: Instance)
	local I = Zones.Island
	local walls = Build.folder("Walls", parent)
	local centerY = Palette.WallBottomY + I.WallSize.Y / 2
	for k = 0, I.WallCount - 1 do
		local a = k * TAU / I.WallCount
		local pos = Vector3.new(I.WallRadius * math.cos(a), centerY, I.WallRadius * math.sin(a))
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local wall = Build.part({
			Name = string.format("Wall_%02d", k + 1),
			Size = I.WallSize,
			CFrame = CFrame.lookAt(pos, pos + tangent),
			Transparency = 1,
			Parent = walls,
		})
		wall.CanCollide = true
		wall.CanQuery = false -- la caméra ne bute pas sur les murs invisibles
		wall.CanTouch = false
	end
	return walls
end

-- Island (Model persistant) : Ground, Glade, CraterFloor, CraterRim, Cracks, Cliff, Walls
function Island.build(root: Instance, rng: Random): Model
	local I = Zones.Island
	local G = Zones.Ground
	local model = Build.model("Island", root)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	disc("Ground", I.Radius * 2, I.Thickness, I.TopY, I.Color, I.Material, model)
	disc(
		"Glade",
		G.GladeDiameter,
		Palette.GladeThickness,
		G.GladeTopY,
		G.GladeColor,
		Enum.Material.Grass,
		model
	)
	disc(
		"CraterFloor",
		G.CraterDiameter,
		Palette.CraterThickness,
		G.CraterTopY,
		G.CraterColor,
		Enum.Material.Basalt,
		model
	)
	buildRim(model, rng)
	buildCracks(model, rng)
	buildCliff(model, rng)
	buildWalls(model)
	return model
end

-- Paths (Folder) : pas japonais, Cylinders plats tous les StoneEvery studs (Y = sol + 0,05)
function Island.buildPaths(root: Instance): Folder
	local P = Zones.Paths
	local folder = Build.folder("Paths", root)
	for i, pos in WorldLayout.pathStones() do
		local top = pos.Y + Palette.StoneTopLift
		local stone = Build.part({
			Name = string.format("Stone_%03d", i),
			Size = Vector3.new(P.StoneThickness, P.StoneDiameter, P.StoneDiameter),
			CFrame = CFrame.new(pos.X, top - P.StoneThickness / 2, pos.Z) * VERTICAL,
			Color = P.StoneColor,
			Material = Enum.Material.Slate,
			Parent = folder,
		})
		stone.Shape = Enum.PartType.Cylinder
	end
	return folder
end

-- Lanterns (Folder) : poteau Wood + bulbe Néon tagué « Lantern » ; PointLight seulement si `lit`
-- (r 90 et 60 : 24 lumières, budget §12.8)
function Island.buildLanterns(root: Instance): Folder
	local P = Zones.Paths
	local folder = Build.folder("Lanterns", root)
	for i, spot in WorldLayout.lanterns() do
		local lantern = Build.model(string.format("Lantern_%02d", i), folder)
		local base = spot.position
		Build.cylinder({
			Name = "Pole",
			Size = Vector3.new(P.LanternPoleHeight, Palette.LanternPoleDiameter, Palette.LanternPoleDiameter),
			CFrame = CFrame.new(base + Vector3.new(0, P.LanternPoleHeight / 2, 0)) * VERTICAL,
			Color = Palette.Wood,
			Material = Enum.Material.Wood,
			Parent = lantern,
		})
		local bulb = Build.ball({
			Name = "Bulb",
			Size = Vector3.one * Palette.LanternBulbDiameter,
			CFrame = CFrame.new(
				base + Vector3.new(0, P.LanternPoleHeight + Palette.LanternBulbDiameter / 2 - 0.2, 0)
			),
			Color = P.LanternColor,
			Material = Enum.Material.Neon,
			Parent = lantern,
		})
		if spot.lit then
			local light = Instance.new("PointLight")
			light.Range = P.LightRange
			light.Brightness = P.LightBrightness
			light.Color = P.LanternColor
			light.Shadows = false
			light.Parent = bulb
		end
		Build.tag(bulb, "Lantern", { Lit = spot.lit })
	end
	return folder
end

return Island
