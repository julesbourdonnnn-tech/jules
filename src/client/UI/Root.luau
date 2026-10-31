--!strict
-- Fournit les ScreenGui du jeu, avec une mise à l'échelle responsive commune
-- (référence 1280×720, bornée 0,6–1,25 ; écran « 10 pieds » : proportionnelle, sans plafond) et
-- ResetOnSpawn désactivé.
--   local gui = Root.screen("HUD", 10)
--
-- Le conteneur « Safe » porte l'UIScale. Un UIScale agrandit ou réduit son parent autour de son
-- point d'ancrage (ici le coin haut gauche) : Safe mesure donc 1/s de l'écran pour couvrir
-- exactement tout l'écran une fois mis à l'échelle (sinon, à 0,6, tout le HUD tiendrait dans les
-- 60 % haut gauche de l'écran, et à 1,4 il déborderait à droite et en bas).
-- Règles d'échelle et de zone sûre : Client/Util/Platform (docs/07-console-ps5.md §3-§4). Sur
-- console ou écran Large, la marge intérieure de Safe devient la zone sûre TV (5 % de l'écran de
-- chaque côté) : tout ce qui est placé dans Safe reste visible sur un téléviseur.

local Players = game:GetService("Players")

local Platform = require(script.Parent.Parent.Util.Platform)

-- GDD §10.1 : UIScale = clamp(hauteur / 720 ; 0,6 ; 1,25). Écart assumé : on prend le plus petit
-- des rapports hauteur ET largeur pour que le cadre de référence 1280 × 720 tienne aussi sur les
-- écrans étroits (4:3, 16:10, fenêtres) ; identique au GDD sur les écrans larges (téléphones, 16:9).
-- Console / écran Large : max(0,6 ; min(L / 1280 ; H / 720)), soit 1,5 en 1920 × 1080 (docs/07 §3).

local Root = {}

local screens: { [string]: ScreenGui } = {}
local scales: { UIScale } = {}

local function viewport(): Vector2?
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else nil
end

local function computeScale(): number
	return Platform.uiScale(viewport())
end

-- Applique l'échelle et la marge intérieure ; garde Safe plein écran après mise à l'échelle
local function apply(scale: UIScale, s: number, pad: Vector2)
	scale.Scale = s
	local safe = scale.Parent
	if safe and safe:IsA("GuiObject") then
		safe.Size = UDim2.fromScale(1 / s, 1 / s)
		local padding = safe:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingTop = UDim.new(0, pad.Y)
			padding.PaddingBottom = UDim.new(0, pad.Y)
			padding.PaddingLeft = UDim.new(0, pad.X)
			padding.PaddingRight = UDim.new(0, pad.X)
		end
	end
end

local function refresh()
	local s = computeScale()
	local pad = Platform.safePadding(viewport())
	for i = #scales, 1, -1 do
		local scale = scales[i]
		if scale.Parent == nil then
			table.remove(scales, i) -- écran détruit
		else
			apply(scale, s, pad)
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
	padding.Parent = safe

	local scale = Instance.new("UIScale")
	scale.Name = "RootScale"
	scale.Parent = safe
	apply(scale, computeScale(), Platform.safePadding(viewport()))
	table.insert(scales, scale)

	gui.Parent = playerGui
	screens[name] = gui
	return gui
end

-- Conteneur sûr d'un écran (là où placer les éléments)
function Root.safe(name: string, displayOrder: number?): Frame
	return Root.screen(name, displayOrder):FindFirstChild("Safe") :: Frame
end

-- Marge intérieure courante de Root.safe (px de référence ; zone sûre TV sur console)
function Root.padding(): Vector2
	return Platform.safePadding(viewport())
end

-- Cadre de sélection manette commun, bien visible à 3 m (docs/07-console-ps5.md §7) : contour
-- doré de 4 px qui déborde de 4 px autour de l'objet sélectionné. À affecter à
-- GuiObject.SelectionImageObject ; jamais parenté (le moteur le dessine sur l'objet sélectionné).
local selectionImage: Frame? = nil
local SELECTION_COLOR = Color3.fromRGB(255, 208, 72) -- Theme.Colors.Gold

function Root.selectionImage(): Frame
	local existing = selectionImage
	if existing then
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = "SelectionHighlight"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, 8, 1, 8)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = SELECTION_COLOR
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	selectionImage = frame
	return frame
end

function Root.Init()
	-- taille d'écran (ViewportDisplaySize) changée : échelle et zone sûre recalculées
	Platform.Changed:Connect(function(reason: string)
		if reason == "display" then
			refresh()
		end
	end)
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
