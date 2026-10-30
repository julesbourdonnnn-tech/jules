--!strict
-- Effets de « juice » côté client : tweens sûrs, boutons qui réagissent, popups,
-- compteurs qui défilent, secousses, flashs, textes flottants.
-- Respecte GuiService.ReducedMotionEnabled (mouvements remplacés par des fondus).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Juice = {}

Juice.cameraShakeEnabled = true

-- Un seul tween actif par (instance, propriété)
local active: { [Instance]: { [string]: Tween } } = setmetatable({}, { __mode = "k" }) :: any

function Juice.reducedMotion(): boolean
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

function Juice.tween(
	inst: Instance,
	duration: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delayTime: number?
): Tween
	local info = TweenInfo.new(
		duration,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out,
		0,
		false,
		delayTime or 0
	)
	local perInst = active[inst]
	if not perInst then
		perInst = {}
		active[inst] = perInst
	end
	for prop in props do
		local previous = perInst[prop]
		if previous then
			previous:Cancel()
		end
	end
	local tween = TweenService:Create(inst, info, props)
	for prop in props do
		perInst[prop] = tween
	end
	tween.Completed:Once(function()
		local current = active[inst]
		if current then
			for prop in props do
				if current[prop] == tween then
					current[prop] = nil
				end
			end
		end
	end)
	tween:Play()
	return tween
end

-- UIScale dédié aux animations (n'interfère pas avec Size/Position du layout)
function Juice.scaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("JuiceScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "JuiceScale"
	scale.Parent = gui
	return scale
end

-- Petit « pop » : 1 → amount → 1
function Juice.pulse(gui: GuiObject, amount: number?)
	local scale = Juice.scaleOf(gui)
	local peak = amount or 1.15
	local up = Juice.tween(scale, 0.08, { Scale = peak }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	up.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			Juice.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end)
end

-- Bouton qui s'enfonce au toucher et rebondit au relâchement
function Juice.press(button: GuiButton)
	local scale = Juice.scaleOf(button)
	button.MouseButton1Down:Connect(function()
		Juice.tween(scale, 0.08, { Scale = 0.9 })
	end)
	local function release()
		Juice.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.SelectionGained:Connect(function()
		Juice.tween(scale, 0.12, { Scale = 1.06 })
	end)
	button.SelectionLost:Connect(release)
end

-- Ouverture d'un panneau : échelle 0.85 → 1, fondu (via CanvasGroup si dispo)
function Juice.popIn(gui: GuiObject)
	local scale = Juice.scaleOf(gui)
	gui.Visible = true
	if Juice.reducedMotion() then
		scale.Scale = 1
		return
	end
	scale.Scale = 0.85
	Juice.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Fermeture d'un panneau ; onDone appelé quand il est caché
function Juice.popOut(gui: GuiObject, onDone: (() -> ())?)
	local scale = Juice.scaleOf(gui)
	if Juice.reducedMotion() then
		gui.Visible = false
		if onDone then
			onDone()
		end
		return
	end
	local tween = Juice.tween(scale, 0.15, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			gui.Visible = false
			scale.Scale = 1
			if onDone then
				onDone()
			end
		end
	end)
end

-- Refus : secousse horizontale (×3) puis retour à la position d'origine
local shaking: { [GuiObject]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any
function Juice.shake(gui: GuiObject)
	local origin = shaking[gui] or gui.Position
	shaking[gui] = origin
	if Juice.reducedMotion() then
		return
	end
	task.spawn(function()
		for i = 1, 6 do
			local dir = if i % 2 == 0 then -1 else 1
			Juice.tween(gui, 0.04, { Position = origin + UDim2.fromOffset(6 * dir, 0) })
			task.wait(0.04)
		end
		Juice.tween(gui, 0.05, { Position = origin })
		task.wait(0.05)
		if shaking[gui] == origin then
			shaking[gui] = nil
		end
	end)
end

-- Compteur qui défile de `from` à `to` ; une nouvelle valeur annule la précédente
local counting: { [TextLabel]: number } = setmetatable({}, { __mode = "k" }) :: any
function Juice.countTo(label: TextLabel, from: number, to: number, duration: number?, format: ((number) -> string)?)
	local fmt = format or function(n: number): string
		return tostring(math.floor(n))
	end
	local token = (counting[label] or 0) + 1
	counting[label] = token
	local total = duration or 0.4
	if from == to or Juice.reducedMotion() then
		label.Text = fmt(to)
		return
	end
	task.spawn(function()
		local start = os.clock()
		while counting[label] == token do
			local alpha = math.min(1, (os.clock() - start) / total)
			local eased = 1 - (1 - alpha) ^ 3
			label.Text = fmt(from + (to - from) * eased)
			if alpha >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
	if to > from then
		Juice.pulse(label, 1.12)
	end
end

-- Flash plein écran (gros gain, montée de niveau)
local flashGui: ScreenGui? = nil
function Juice.flash(color: Color3?, alpha: number?, duration: number?)
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	if not flashGui or not flashGui.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "JuiceFlash"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 100
		local frame = Instance.new("Frame")
		frame.Name = "Flash"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.Active = false
		frame.Parent = gui
		gui.Parent = playerGui
		flashGui = gui
	end
	local frame = (flashGui :: ScreenGui):FindFirstChild("Flash") :: Frame
	frame.BackgroundColor3 = color or Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1 - (alpha or 0.15)
	Juice.tween(frame, duration or 0.35, { BackgroundTransparency = 1 })
end

-- Secousse caméra via Humanoid.CameraOffset (n'entre pas en conflit avec la caméra Custom)
local shakeToken = 0
function Juice.cameraShake(intensity: number?, duration: number?)
	if not Juice.cameraShakeEnabled or Juice.reducedMotion() then
		return
	end
	local player = Players.LocalPlayer
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	shakeToken += 1
	local token = shakeToken
	local power = math.min(intensity or 0.25, 0.4)
	local total = math.min(duration or 0.25, 0.3)
	task.spawn(function()
		local start = os.clock()
		while token == shakeToken and humanoid.Parent do
			local t = os.clock() - start
			if t >= total then
				break
			end
			local falloff = 1 - t / total
			local seed = t * 40
			humanoid.CameraOffset = Vector3.new(
				math.noise(seed, 0.3) * power * falloff,
				math.noise(0.7, seed) * power * falloff,
				0
			)
			RunService.RenderStepped:Wait()
		end
		if token == shakeToken and humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
		end
	end)
end

return Juice
