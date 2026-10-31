--!strict
-- WorldService — paquet « world » (docs/04-architecture.md §11.3).
-- Construit Lumora en primitives au démarrage (Init, synchrone, aucun yield) avec World/Build et
-- Logic/WorldLayout, pose l'éclairage de base, puis expose les points d'accroche aux autres services.
--
--   workspace.Lumora (Folder)
--     Island   (Model persistant) : Ground, Glade, CraterFloor, CraterRim, Cracks, Cliff, Walls
--     Beacon   (Model persistant, tag Beacon) : Base, Shaft, Top, Rings (tag BeaconRing), Star,
--              SkyBeam (Bottom, Top, Beam), Deposit (tag BeaconDeposit, éteint), Board
--     Nests    : Nest_01 … Nest_12 (Model persistant, tag Nest, attribut Slot fixe) : Platform,
--              Gate { PostL, PostR, Arch (tag NestArch) }, Observatory, BillboardAnchor, Spawn,
--              Perches (Perch_01 … Perch_NN, setPerchCount)
--     Paths, Lanterns (tag Lantern), Decor (Meadow, Glade (tag Crystal), Crater), Islets, Clouds
--
-- Toutes les dimensions viennent de Config/Zones (+ détails visuels nommés de World/Palette), les
-- positions de Logic/WorldLayout, l'éclairage de base de Config/Events.Lighting.Base. Les accès
-- (root, nest…) construisent le monde à la demande si Init n'a pas encore tourné (tests).
-- GDD : §11.1-§11.4, §11.7, §11.5 (base), §12.2.
-- Dépendances : World/{Build, Lighting, Island, Beacon, Nests, Decor, Palette}, Logic/WorldLayout,
-- Config/Zones, Config/Cosmetics, Config/Events.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Events = require(Shared.Config.Events)

local World = script.Parent.Parent.World
local LightingSetup = require(World.Lighting)
local Island = require(World.Island)
local Beacon = require(World.Beacon)
local Nests = require(World.Nests)
local Decor = require(World.Decor)

local WorldService = {}

local rootFolder: Folder? = nil
local beaconModel: Model? = nil
local building = false

-- Éclairage de base (GDD §11.5) : socle World/Lighting puis les valeurs cibles de Events.Lighting.Base.
-- Le client anime ensuite le cycle et les préréglages (LightingController), sans réplication.
local function applyBaseLighting()
	LightingSetup.applyTwilight()
	local base = Events.Lighting.Base
	Lighting.ClockTime = Events.Lighting.Cycle.Min
	Lighting.Ambient = base.Ambient
	Lighting.OutdoorAmbient = base.OutdoorAmbient
	Lighting.Brightness = base.Brightness
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.StarCount = base.StarCount
		sky.MoonAngularSize = base.MoonAngularSize
		sky.SunAngularSize = base.SunAngularSize
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = base.AtmosphereDensity
		atmosphere.Offset = base.AtmosphereOffset
		atmosphere.Color = base.AtmosphereColor
		atmosphere.Decay = base.AtmosphereDecay
		atmosphere.Glare = base.AtmosphereGlare
		atmosphere.Haze = base.AtmosphereHaze
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = base.BloomIntensity
		bloom.Size = base.BloomSize
		bloom.Threshold = base.BloomThreshold
	end
	local color = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if color then
		color.Saturation = base.Saturation
		color.Contrast = base.Contrast
		color.TintColor = Color3.new(1, 1, 1)
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Intensity = base.SunRays
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds: Clouds
		local found = terrain:FindFirstChildOfClass("Clouds")
		if found then
			clouds = found
		else
			clouds = Instance.new("Clouds")
			clouds.Name = "Clouds"
			clouds.Parent = terrain
		end
		clouds.Cover = base.CloudCover
		clouds.Color = base.CloudColor
	end
end

local function countParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- Construit workspace.Lumora une seule fois (synchrone : aucun yield)
local function ensureBuilt(): Folder
	local existing = rootFolder
	if existing then
		return existing
	end
	assert(not building, "WorldService : construction réentrante")
	building = true
	local old = workspace:FindFirstChild("Lumora")
	if old then
		old:Destroy() -- place sauvegardée avec un ancien monde : on repart de zéro
	end
	local root = Instance.new("Folder")
	root.Name = "Lumora"
	-- Hasard purement visuel (teintes, tailles) : seed fixe, même île à chaque démarrage
	local rng = Random.new(Zones.Decor.Seed)
	Island.build(root, rng)
	beaconModel = Beacon.build(root)
	Nests.build(root)
	Island.buildPaths(root)
	Island.buildLanterns(root)
	Decor.build(root, rng)
	Decor.buildIslets(root, rng)
	Decor.buildClouds(root, rng)
	root.Parent = workspace -- un seul parentage : une seule réplication du monde
	rootFolder = root
	building = false
	local parts = countParts(root)
	if parts > Zones.PartBudget then
		warn(`[WorldService] budget de pièces dépassé : {parts} > {Zones.PartBudget}`)
	end
	return root
end

local function checkSlot(slot: number, fn: string)
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Zones.Nests.Count then
		error(`WorldService.{fn} : slot 1-{Zones.Nests.Count} attendu, reçu {tostring(slot)}`, 3)
	end
end

local function nestState(slot: number, fn: string): Nests.NestState
	checkSlot(slot, fn)
	ensureBuilt()
	local state = Nests.get(slot)
	assert(state, `WorldService.{fn} : Nid {slot} absent`)
	return state
end

function WorldService.Init()
	ensureBuilt()
	applyBaseLighting()
end

function WorldService.Start() end

function WorldService.root(): Folder
	return ensureBuilt()
end

function WorldService.nest(slot: number): Model
	return nestState(slot, "nest").model
end

function WorldService.spawnLocation(slot: number): SpawnLocation
	return nestState(slot, "spawnLocation").spawn
end

-- Couleurs de la plateforme et de l'arche (nil = Nid libre : gris, sans lumière)
function WorldService.setNestAppearance(slot: number, platform: Color3?, arch: Color3?)
	nestState(slot, "setNestAppearance")
	if platform ~= nil and typeof(platform) ~= "Color3" then
		error("WorldService.setNestAppearance : Color3 ou nil attendu pour la plateforme", 2)
	end
	if arch ~= nil and typeof(arch) ~= "Color3" then
		error("WorldService.setNestAppearance : Color3 ou nil attendu pour l'arche", 2)
	end
	Nests.setAppearance(slot, platform, arch)
end

-- Crée ou détruit les pièces de perchoir pour qu'il en existe exactement `count` (0-46)
function WorldService.setPerchCount(slot: number, count: number)
	nestState(slot, "setPerchCount")
	if type(count) ~= "number" or count ~= count or count == math.huge or count == -math.huge then
		error(`WorldService.setPerchCount : nombre fini attendu, reçu {tostring(count)}`, 2)
	end
	Nests.setPerchCount(slot, count)
end

function WorldService.beacon(): Model
	ensureBuilt()
	return beaconModel :: Model
end

-- Stèle du tableau des congas (attributs Live / Record / Weekly posés par LeaderboardService)
function WorldService.board(): BasePart
	local board = WorldService.beacon():FindFirstChild("Board")
	assert(board and board:IsA("BasePart"), "WorldService.board : stèle absente")
	return board
end

-- Nombre de BasePart construites, perchoirs compris (budget §11.7)
function WorldService.partCount(): number
	return countParts(ensureBuilt())
end

-- Nombre de perchoirs construits pour un Nid (tests, diagnostic)
function WorldService.perchCount(slot: number): number
	checkSlot(slot, "perchCount")
	ensureBuilt()
	return Nests.perchCount(slot)
end

return WorldService
