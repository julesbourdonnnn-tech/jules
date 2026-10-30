--!strict
-- Ambiance « crépuscule magique » sans aucune texture : Lighting + Atmosphere + ciel
-- par défaut étoilé + Bloom/ColorCorrection/SunRays. Appelé une fois au démarrage.

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function LightingSetup.applyTwilight()
	Lighting.ClockTime = 18.4
	Lighting.GeographicLatitude = 23
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 56, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 96, 170)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 196, 160)
	Lighting.ColorShift_Bottom = Color3.fromRGB(90, 70, 160)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000

	local atmosphere = ensure("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(198, 156, 230)
	atmosphere.Decay = Color3.fromRGB(255, 140, 170)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.6

	local sky = ensure("Sky", "Sky") :: Sky
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9

	local bloom = ensure("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.9
	bloom.Size = 28
	bloom.Threshold = 1.6

	local color = ensure("ColorCorrectionEffect", "ColorCorrection") :: ColorCorrectionEffect
	color.Brightness = 0.02
	color.Contrast = 0.08
	color.Saturation = 0.18
	color.TintColor = Color3.fromRGB(255, 244, 255)

	local rays = ensure("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.6
end

return LightingSetup
