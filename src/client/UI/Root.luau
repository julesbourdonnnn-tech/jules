--!strict
-- Fournit les ScreenGui du jeu, avec une mise à l'échelle responsive commune
-- (référence 1280×720, bornée 0.6–1.4) et ResetOnSpawn désactivé.
--   local gui = Root.screen("HUD", 10)

local Players = game:GetService("Players")

local REFERENCE = Vector2.new(1280, 720)
local MIN_SCALE, MAX_SCALE = 0.6, 1.4

local Root = {}

local screens: { [string]: ScreenGui } = {}
local scales: { UIScale } = {}

local function computeScale(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local size = camera.ViewportSize
	if size.X <= 1 or size.Y <= 1 then
		return 1
	end
	local s = math.min(size.X / REFERENCE.X, size.Y / REFERENCE.Y)
	return math.clamp(s, MIN_SCALE, MAX_SCALE)
end

local function refresh()
	local s = computeScale()
	for _, scale in scales do
		scale.Scale = s
	end
end

function Root.scale(): number
	return computeScale()
end

-- Écran plein, avec un conteneur « Safe » qui respecte l'encoche et la barre Roblox
function Root.screen(name: string, displayOrder: number?): ScreenGui
	local existing = screens[name]
	if existing and existing.Parent then
		return existing
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 0
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local safe = Instance.new("Frame")
	safe.Name = "Safe"
	safe.BackgroundTransparency = 1
	safe.Size = UDim2.fromScale(1, 1)
	safe.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = safe

	local scale = Instance.new("UIScale")
	scale.Name = "RootScale"
	scale.Scale = computeScale()
	scale.Parent = safe
	table.insert(scales, scale)

	gui.Parent = playerGui
	screens[name] = gui
	return gui
end

-- Conteneur sûr d'un écran (là où placer les éléments)
function Root.safe(name: string, displayOrder: number?): Frame
	return Root.screen(name, displayOrder):FindFirstChild("Safe") :: Frame
end

function Root.Init()
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end
		refresh()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
end

return Root
