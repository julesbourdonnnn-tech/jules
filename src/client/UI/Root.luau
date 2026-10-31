--!strict
-- Fournit les ScreenGui du jeu, avec une mise à l'échelle responsive commune
-- (référence 1280×720, bornée 0,6–1,25) et ResetOnSpawn désactivé.
--   local gui = Root.screen("HUD", 10)
--
-- Le conteneur « Safe » porte l'UIScale. Un UIScale agrandit ou réduit son parent autour de son
-- point d'ancrage (ici le coin haut gauche) : Safe mesure donc 1/s de l'écran pour couvrir
-- exactement tout l'écran une fois mis à l'échelle (sinon, à 0,6, tout le HUD tiendrait dans les
-- 60 % haut gauche de l'écran, et à 1,4 il déborderait à droite et en bas).

local Players = game:GetService("Players")

local REFERENCE = Vector2.new(1280, 720)
-- GDD §10.1 : UIScale = clamp(hauteur / 720 ; 0,6 ; 1,25). Écart assumé : on prend le plus petit
-- des rapports hauteur ET largeur pour que le cadre de référence 1280 × 720 tienne aussi sur les
-- écrans étroits (4:3, 16:10, fenêtres) ; identique au GDD sur les écrans larges (téléphones, 16:9).
local MIN_SCALE, MAX_SCALE = 0.6, 1.25

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

-- Applique l'échelle et garde Safe plein écran après mise à l'échelle
local function apply(scale: UIScale, s: number)
	scale.Scale = s
	local safe = scale.Parent
	if safe and safe:IsA("GuiObject") then
		safe.Size = UDim2.fromScale(1 / s, 1 / s)
	end
end

local function refresh()
	local s = computeScale()
	for i = #scales, 1, -1 do
		local scale = scales[i]
		if scale.Parent == nil then
			table.remove(scales, i) -- écran détruit
		else
			apply(scale, s)
		end
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
	safe.AnchorPoint = Vector2.zero
	safe.Position = UDim2.fromScale(0, 0)
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
	scale.Parent = safe
	apply(scale, computeScale())
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
