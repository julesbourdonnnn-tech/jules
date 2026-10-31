--!strict
-- Decor — paquet « world » : décor par zone, îlots flottants et mer de nuages (GDD §11.1, §11.4).
-- Les positions viennent de WorldLayout.decor() (seed fixe, mêmes points que l'exclusion de la
-- grille d'apparition) ; ici seulement la construction en primitives, ancrée et sans collision.
--   Decor/Meadow : Puffblooms (tige + bulbe Néon pastel), Mushcaps (pied + chapeau enfoncé +
--                  3 points blancs), clôtures Wood près des Nids
--   Decor/Glade  : grappes de 3-5 WedgeParts Glass cyan (≤ CrystalMaxParts), dont LitCrystals avec
--                  PointLight et tag « Crystal » ; pierres flottantes (tags Spin + Float)
--   Decor/Crater : rochers Basalt (Build.rock)
--   Islets       : Ball Slate + disque Grass, tag Float (amplitude 2, période 6 s)
--   Clouds       : Build.cloud (tag Float)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Build = require(script.Parent.Build)
local Palette = require(script.Parent.Palette)

local Decor = {}

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)
local TAU = 2 * math.pi

local function buildPuffbloom(parent: Instance, pos: Vector3, index: number)
	local model = Build.model("Puffbloom", parent)
	local stem = Palette.PuffStemSize
	Build.cylinder({
		Name = "Stem",
		Size = stem,
		CFrame = CFrame.new(pos + Vector3.new(0, stem.X / 2, 0)) * VERTICAL,
		Color = Palette.PuffStem,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	Build.ball({
		Name = "Bloom",
		Size = Vector3.one * Palette.PuffBloomDiameter,
		CFrame = CFrame.new(pos + Vector3.new(0, stem.X + Palette.PuffBloomDiameter * 0.35, 0)),
		Color = Palette.PuffPastels[(index - 1) % #Palette.PuffPastels + 1],
		Material = Enum.Material.Neon,
		Parent = model,
	})
end

local DOT_DIRECTIONS = {
	Vector3.new(0.5, 0.8, 0.3).Unit,
	Vector3.new(-0.6, 0.7, -0.2).Unit,
	Vector3.new(0.1, 0.85, -0.6).Unit,
}

local function buildMushcap(parent: Instance, pos: Vector3, index: number, rng: Random)
	local model = Build.model("Mushcap", parent)
	local stem = Palette.MushStemSize
	Build.cylinder({
		Name = "Stem",
		Size = stem,
		CFrame = CFrame.new(pos + Vector3.new(0, stem.X / 2, 0)) * VERTICAL,
		Color = Palette.MushStem,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local radius = Palette.MushCapDiameter / 2
	local capCenter = pos + Vector3.new(0, stem.X + radius - Palette.MushCapSink, 0)
	Build.ball({
		Name = "Cap",
		Size = Vector3.one * Palette.MushCapDiameter,
		CFrame = CFrame.new(capCenter),
		Color = Palette.MushCaps[(index - 1) % #Palette.MushCaps + 1],
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local yaw = CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	for i, dir in DOT_DIRECTIONS do
		Build.ball({
			Name = "Dot" .. i,
			Size = Vector3.one * Palette.MushDotDiameter,
			CFrame = CFrame.new(
				capCenter + yaw:VectorToWorldSpace(dir) * (radius - Palette.MushDotDiameter * 0.25)
			),
			Color = Palette.MushDot,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
end

local function buildFence(parent: Instance, cf: CFrame)
	local model = Build.model("Fence", parent)
	local post = Palette.FencePost
	for _, side in { -1, 1 } do
		Build.part({
			Name = if side < 0 then "PostA" else "PostB",
			Size = post,
			CFrame = cf * CFrame.new(0, post.Y / 2, side * Palette.FenceSpan),
			Color = Palette.Wood,
			Material = Enum.Material.Wood,
			Parent = model,
		})
	end
	Build.part({
		Name = "Rail",
		Size = Palette.FenceRail,
		CFrame = cf * CFrame.new(0, post.Y * 0.7, 0),
		Color = Palette.Wood,
		Material = Enum.Material.Wood,
		Parent = model,
	})
end

local function buildMeadow(parent: Instance, layout: WorldLayout.DecorLayout, rng: Random)
	local meadow = Build.folder("Meadow", parent)
	for i, pos in layout.puffblooms do
		buildPuffbloom(meadow, pos, i)
	end
	for i, pos in layout.mushcaps do
		buildMushcap(meadow, pos, i, rng)
	end
	for _, cf in layout.fences do
		buildFence(meadow, cf)
	end
end

local function buildGlade(parent: Instance, layout: WorldLayout.DecorLayout, rng: Random)
	local G = Zones.Decor
	local glade = Build.folder("Glade", parent)
	local budget = G.Glade.CrystalMaxParts
	local clusters = #layout.crystals
	for i, spot in layout.crystals do
		-- au moins Palette.CrystalMin pièces pour les grappes restantes : jamais au-delà du budget
		local reserve = (clusters - i) * Palette.CrystalMin
		local count = math.min(rng:NextInteger(Palette.CrystalMin, Palette.CrystalMax), budget - reserve)
		if count <= 0 then
			break
		end
		budget -= count
		local cluster = Build.model("Crystals", glade)
		for k = 1, count do
			local height = rng:NextNumber(3, 6)
			local width = rng:NextNumber(0.8, 1.4)
			local offset = Vector3.new(rng:NextNumber(-1.2, 1.2), height / 2 - 0.3, rng:NextNumber(-1.2, 1.2))
			local tilt = CFrame.Angles(
				rng:NextNumber(-0.45, 0.45),
				rng:NextNumber(0, TAU),
				rng:NextNumber(-0.45, 0.45)
			)
			local crystal = Build.wedge({
				Name = "Crystal",
				Size = Vector3.new(width, height, width),
				CFrame = spot.cframe * CFrame.new(offset) * tilt,
				Color = G.CrystalColor,
				Material = Enum.Material.Glass,
				Transparency = G.CrystalTransparency,
				Parent = cluster,
			})
			if k == 1 and spot.lit then
				local light = Instance.new("PointLight")
				light.Range = Palette.CrystalLightRange
				light.Brightness = Palette.CrystalLightBrightness
				light.Color = G.CrystalColor
				light.Shadows = false
				light.Parent = crystal
				Build.tag(crystal, "Crystal", { Lit = true })
			end
		end
	end
	for _, pos in layout.floatingStones do
		local stone = Build.part({
			Name = "FloatingStone",
			Size = Palette.FloatingStoneSize,
			CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), 0),
			Color = Palette.FloatingStoneColor,
			Material = Enum.Material.Slate,
			Parent = glade,
		})
		Build.tag(stone, "Spin", { speed = rng:NextNumber(0.4, 0.9), axis = "Y" })
		Build.tag(
			stone,
			"Float",
			{ amplitude = 0.5, period = rng:NextNumber(4, 6), phase = rng:NextNumber(0, TAU) }
		)
	end
end

local function buildCrater(parent: Instance, layout: WorldLayout.DecorLayout, rng: Random)
	local crater = Build.folder("Crater", parent)
	for _, pos in layout.craterRocks do
		local rock = Build.rock(crater, pos, 1, rng, Zones.Ground.CraterColor)
		for _, part in rock:GetChildren() do
			if part:IsA("BasePart") then
				part.Material = Enum.Material.Basalt
			end
		end
	end
end

-- Decor (Folder) : Meadow, Glade, Crater
function Decor.build(root: Instance, rng: Random): Folder
	local layout = WorldLayout.decor()
	local folder = Build.folder("Decor", root)
	buildMeadow(folder, layout, rng)
	buildGlade(folder, layout, rng)
	buildCrater(folder, layout, rng)
	return folder
end

-- Islets (Folder) : îlots flottants (Ball Slate + disque Grass, flottement commun)
function Decor.buildIslets(root: Instance, rng: Random): Folder
	local I = Zones.Islets
	local folder = Build.folder("Islets", root)
	for i, pos in WorldLayout.decor().islets do
		local islet = Build.model(string.format("Islet_%d", i), folder)
		local float = { amplitude = I.FloatAmplitude, period = I.FloatPeriod, phase = rng:NextNumber(0, TAU) }
		local rock = Build.ball({
			Name = "Rock",
			Size = Vector3.one * Palette.IsletRockDiameter,
			CFrame = CFrame.new(pos),
			Color = Build.vary(Palette.Slate, rng, 0.04),
			Material = Enum.Material.Slate,
			Parent = islet,
		})
		local top = Build.cylinder({
			Name = "Top",
			Size = Palette.IsletTopSize,
			CFrame = CFrame.new(pos + Vector3.new(0, Palette.IsletTopLift, 0)) * VERTICAL,
			Color = Zones.Island.Color,
			Material = Enum.Material.Grass,
			Parent = islet,
		})
		Build.tag(rock, "Float", float)
		Build.tag(top, "Float", float)
	end
	return folder
end

-- Clouds (Folder) : mer de nuages sous l'île (Build.cloud, tag Float)
function Decor.buildClouds(root: Instance, rng: Random): Folder
	local folder = Build.folder("Clouds", root)
	for _, pos in WorldLayout.decor().clouds do
		Build.cloud(folder, pos, rng:NextNumber(Palette.CloudScaleMin, Palette.CloudScaleMax), rng)
	end
	return folder
end

return Decor
