--!strict
-- Fournit les ScreenGui du jeu, avec une mise à l'échelle commune à TOUS les écrans (console d'abord,
-- note INT-TV : référence 1920 × 1080 px TV, proportionnelle, sans plafond, au moins 0,5) et
-- ResetOnSpawn désactivé.
--   local gui = Root.screen("HUD", 10)
--
-- Le conteneur « Safe » porte l'UIScale. Un UIScale agrandit ou réduit son parent autour de son
-- point d'ancrage (ici le coin haut gauche) : Safe mesure donc 1/s de l'écran pour couvrir
-- exactement tout l'écran une fois mis à l'échelle (sinon, à 0,6, tout le HUD tiendrait dans les
-- 60 % haut gauche de l'écran, et à 1,4 il déborderait à droite et en bas).
-- Règles d'échelle et de zone sûre : Client/Util/Platform. Sur tous les écrans, la marge intérieure
-- de Safe est la zone sûre TV (5 % de l'écran de chaque côté) : tout ce qui est placé dans Safe
-- reste visible sur un téléviseur. En 1920 × 1080, le contenu de Safe commence donc à (96, 54) px TV :
-- un rectangle de Config/Layout (coordonnées d'écran) se place à (x − 96, y − 54) dans Safe.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Platform = require(script.Parent.Parent.Util.Platform)
local Juice = require(script.Parent.Juice)

-- UIScale = max(0,5 ; min(L / 1920 ; H / 1080)) : le plus petit des rapports hauteur ET largeur,
-- pour que le cadre de référence 1920 × 1080 tienne aussi sur les écrans étroits (4:3, 16:10,
-- fenêtres) ; 1 en 1080p, 2 en 4K, 0,667 en 720p.

local Root = {}

local screens: { [string]: ScreenGui } = {}
local scales: { UIScale } = {}

-- s : attente bornée de PlayerGui (jamais de WaitForChild sans délai côté client) ; même borne que
-- PLAYER_WAIT de src/first/Loading.client.luau. Champ du module pour que les specs puissent la
-- raccourcir.
Root.PlayerGuiWait = 10

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
	local player = Players.LocalPlayer
	local playerGui = if player
		then player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", Root.PlayerGuiWait)
		else nil
	if playerGui == nil then
		-- jamais d'attente infinie : l'erreur nomme Root et l'écran (Main.client l'isole et la signale,
		-- les autres contrôleurs démarrent quand même)
		error(
			`[Root] PlayerGui introuvable après {Root.PlayerGuiWait} s : impossible de créer l'écran « {name} »`,
			2
		)
	end
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

-- px : un voile plein écran remonte d'autant au-dessus de l'écran. Les écrans commencent sous la
-- barre de Roblox (IgnoreGuiInset = false, GuiInset 58 px) et un ScreenGui ne coupe pas ses
-- enfants : sans ce débord, une bande claire non voilée restait en haut de chaque panneau et de
-- chaque carte bloquante (revue des écrans)
Root.VEIL_OVERSCAN = 160

-- Voile (décoratif) qui couvre tout l'écran, bande de la barre de Roblox comprise
function Root.coverScreen(frame: GuiObject)
	frame.Position = UDim2.fromOffset(0, -Root.VEIL_OVERSCAN)
	frame.Size = UDim2.new(1, 0, 1, Root.VEIL_OVERSCAN)
end

-- Conteneur sûr d'un écran (là où placer les éléments)
function Root.safe(name: string, displayOrder: number?): Frame
	return Root.screen(name, displayOrder):FindFirstChild("Safe") :: Frame
end

-- Marge intérieure courante de Root.safe (px de référence ; zone sûre TV sur console)
function Root.padding(): Vector2
	return Platform.safePadding(viewport())
end

-- Cadre de sélection manette commun (le curseur), bien visible à 3 m :
-- trait BLANC de 6 px bordé d'un liseré sombre de 2 px (lisible aussi sur une carte claire), qui
-- déborde de 4 px autour de l'objet sélectionné, et respire doucement (transparence 0 ↔ 0,35 en
-- 1,2 s ; fixe en Mouvement réduit). Sa couleur et sa forme ne servent à rien d'autre (leçon de
-- Comet Conga : un curseur doré à côté d'un contour doré de « choix actif » ne se repérait plus) :
-- les états persistants (choix, objet équipé, élément réclamable) gardent leurs propres couleurs.
-- À affecter à GuiObject.SelectionImageObject ; jamais parenté (le moteur le dessine sur l'objet
-- sélectionné). Copie du dessin dans src/first/Loading.client.luau (bouton Réessayer).
local CURSOR_COLOR = Color3.fromRGB(255, 255, 255)
local CURSOR_EDGE_COLOR = Color3.fromRGB(16, 12, 30) -- Theme.Colors.Stroke
local CURSOR_THICKNESS = 6
local CURSOR_EDGE = 2
local CURSOR_OUTSET = 4 -- px de débord autour de l'objet (de chaque côté)
local CURSOR_RADIUS = 16
local CURSOR_PULSE_PERIOD = 1.2
local CURSOR_PULSE_DEPTH = 0.35 -- transparence du trait blanc au creux de la respiration

local selectionImage: Frame? = nil
local cursorStroke: UIStroke? = nil
local pulseTime = 0

-- Respiration du curseur : seulement quand une sélection existe (sinon rien à dessiner) et hors
-- Mouvement réduit ; trait plein sinon
local function stepCursor(dt: number)
	local stroke = cursorStroke
	if stroke == nil then
		return
	end
	local ok, selected = pcall(function()
		return GuiService.SelectedObject
	end)
	if not ok or selected == nil or Juice.reducedMotion() then
		pulseTime = 0
		if stroke.Transparency ~= 0 then
			stroke.Transparency = 0
		end
		return
	end
	pulseTime = (pulseTime + dt) % CURSOR_PULSE_PERIOD
	local phase = 2 * math.pi * pulseTime / CURSOR_PULSE_PERIOD
	stroke.Transparency = CURSOR_PULSE_DEPTH * (1 - math.cos(phase)) / 2
end

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
	frame.Size = UDim2.new(1, 2 * CURSOR_OUTSET, 1, 2 * CURSOR_OUTSET)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CURSOR_RADIUS)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Cursor"
	stroke.Color = CURSOR_COLOR
	stroke.Thickness = CURSOR_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	-- liseré sombre à l'extérieur du trait blanc (cadre imbriqué : un seul UIStroke par objet)
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.BackgroundTransparency = 1
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.new(1, 2 * CURSOR_THICKNESS, 1, 2 * CURSOR_THICKNESS)
	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(0, CURSOR_RADIUS + CURSOR_THICKNESS)
	edgeCorner.Parent = edge
	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Name = "Edge"
	edgeStroke.Color = CURSOR_EDGE_COLOR
	edgeStroke.Thickness = CURSOR_EDGE
	edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edgeStroke.Parent = edge
	edge.Parent = frame
	selectionImage = frame
	cursorStroke = stroke
	RunService.Heartbeat:Connect(stepCursor)
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
