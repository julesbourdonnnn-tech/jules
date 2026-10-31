--!strict
-- Beacon — paquet « world » : la Balise au centre de Lumora (GDD §11.2, docs §3.1).
-- Pile de Cylinders Marble (socle, fût, sommet) avec un anneau Néon tagué « BeaconRing » à chaque
-- jonction, étoile Néon (2 bras + cœur), faisceau vers le ciel (SkyBeam : Attachments « Bottom » et
-- « Top » à Y = BeamTopY, Beam « Beam »), anneau de dépôt « BeaconDeposit » (éteint : Transparency 1,
-- allumé côté client pendant la Nuit de la Balise) et stèle « Board » du tableau des congas.
-- Deux lumières (budget §12.8) : le cœur de l'étoile et le premier anneau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Build = require(script.Parent.Build)
local Palette = require(script.Parent.Palette)

local Beacon = {}

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)
local TIER_NAMES = { "Base", "Shaft", "Top" }

function Beacon.build(root: Instance): Model
	local B = Zones.Beacon
	local model = Build.model("Beacon", root)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	Build.tag(model, "Beacon")

	-- Étages et anneaux : chaque anneau est centré sur la jonction (la hauteur totale reste la
	-- somme des étages, comme WorldLayout.groundY)
	local rings = Build.folder("Rings", model)
	local y = Zones.Ground.CraterTopY
	for i, tier in B.Tiers do
		local part = Build.solid({
			Name = TIER_NAMES[i] or ("Tier" .. i),
			Size = Vector3.new(tier.height, tier.diameter, tier.diameter),
			CFrame = CFrame.new(0, y + tier.height / 2, 0) * VERTICAL,
			Color = B.Color,
			Material = Enum.Material.Marble,
			Parent = model,
		})
		part.Shape = Enum.PartType.Cylinder
		y += tier.height
		local upper = B.Tiers[i + 1]
		local ringDiameter = (if upper then upper.diameter else tier.diameter) + Palette.BeaconRingOverhang
		local ring = Build.cylinder({
			Name = "Ring" .. i,
			Size = Vector3.new(Palette.BeaconRingThickness, ringDiameter, ringDiameter),
			CFrame = CFrame.new(0, y, 0) * VERTICAL,
			Color = B.RingColor,
			Material = Enum.Material.Neon,
			Parent = rings,
		})
		Build.tag(ring, "BeaconRing", { index = i })
		if i == 1 then
			local light = Instance.new("PointLight")
			light.Name = "RingLight"
			light.Range = Palette.RingLightRange
			light.Brightness = Palette.RingLightBrightness
			light.Color = B.RingColor
			light.Shadows = false
			light.Parent = ring
		end
	end

	-- Étoile au sommet : un bras horizontal qui tourne, un bras vertical, un cœur qui pulse
	local star = Build.model("Star", model)
	local starPos = Vector3.new(0, B.StarY, 0)
	local armH = Build.part({
		Name = "ArmH",
		Size = Palette.StarArm,
		CFrame = CFrame.new(starPos),
		Color = B.StarColor,
		Material = Enum.Material.Neon,
		Parent = star,
	})
	Build.tag(armH, "Spin", { speed = Palette.StarSpinSpeed, axis = "Y" })
	Build.part({
		Name = "ArmV",
		Size = Palette.StarArm,
		CFrame = CFrame.new(starPos) * CFrame.Angles(0, 0, math.pi / 2),
		Color = B.StarColor,
		Material = Enum.Material.Neon,
		Parent = star,
	})
	local core = Build.ball({
		Name = "Core",
		Size = Vector3.one * Palette.StarCore,
		CFrame = CFrame.new(starPos),
		Color = B.StarColor,
		Material = Enum.Material.Neon,
		Parent = star,
	})
	Build.tag(core, "Pulse", { amount = Palette.StarPulseAmount, period = Palette.StarPulsePeriod })
	local starLight = Instance.new("PointLight")
	starLight.Name = "StarLight"
	starLight.Range = Palette.StarLightRange
	starLight.Brightness = Palette.StarLightBrightness
	starLight.Color = B.StarColor
	starLight.Shadows = false
	starLight.Parent = core

	-- Faisceau vers le ciel (largeur animée côté client : ×3 pendant la Nuit de la Balise)
	local carrier = Build.part({
		Name = "SkyBeam",
		Size = Vector3.one,
		CFrame = CFrame.new(starPos),
		Transparency = 1,
		Parent = model,
	})
	local bottom = Instance.new("Attachment")
	bottom.Name = "Bottom"
	bottom.Parent = carrier
	local top = Instance.new("Attachment")
	top.Name = "Top"
	top.Position = Vector3.new(0, B.BeamTopY - B.StarY, 0)
	top.Parent = carrier
	local beam = Instance.new("Beam")
	beam.Name = "Beam"
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Width0 = B.BeamWidth
	beam.Width1 = B.BeamWidth
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Color = ColorSequence.new(B.RingColor, Color3.new(1, 1, 1))
	beam.Transparency = NumberSequence.new(0.1, Palette.BeamTransparencyTop)
	beam.Parent = carrier

	-- Anneau de dépôt (zone de parade 8 ≤ r ≤ 16), éteint hors Nuit de la Balise
	local deposit = Build.cylinder({
		Name = "Deposit",
		Size = Vector3.new(Palette.DepositThickness, B.DepositDiameter, B.DepositDiameter),
		CFrame = CFrame.new(0, Zones.Ground.CraterTopY + Palette.DepositLift, 0) * VERTICAL,
		Color = B.RingColor,
		Material = Enum.Material.Neon,
		Transparency = 1,
		Parent = model,
	})
	Build.tag(deposit, "BeaconDeposit")

	-- Stèle du tableau des congas (r = 12, face au sud ; SurfaceGui posé côté client)
	local boardCF = WorldLayout.boardCFrame()
	local boardPos = boardCF.Position + Vector3.new(0, Palette.BoardSize.Y / 2, 0)
	local board = Build.solid({
		Name = "Board",
		Size = Palette.BoardSize,
		CFrame = (boardCF - boardCF.Position) + boardPos,
		Color = Palette.BoardColor,
		Material = Enum.Material.Marble,
		Parent = model,
	})
	board:SetAttribute("Live", "")
	board:SetAttribute("Record", "")
	board:SetAttribute("Weekly", "")

	model.PrimaryPart = model:FindFirstChild(TIER_NAMES[1]) :: BasePart?
	return model
end

return Beacon
