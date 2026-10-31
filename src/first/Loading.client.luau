--!strict
-- Loading — paquet « world » (docs/04-architecture.md §13.5).
-- LocalScript de ReplicatedFirst : écran de chargement construit en code, AUTONOME (n'exige rien
-- de ReplicatedStorage : il s'affiche avant la réplication).
--   * ReplicatedFirst:RemoveDefaultLoadingScreen() puis ScreenGui « Loading » plein écran dans
--     PlayerGui (IgnoreGuiInset, DisplayOrder élevé, ResetOnSpawn = false) : ciel du crépuscule,
--     étoiles qui scintillent, un Puffkin en Frames qui rebondit (écrasement à l'atterrissage,
--     clignement) et 3 points animés ; aucun texte long ; Mouvement réduit respecté
--     (GuiService.ReducedMotionEnabled : ni rebond ni écrasement, seulement des fondus)
--   * disparition (fondu 0,3 s) quand game:IsLoaded() ET que l'attribut LOCAL
--     Players.LocalPlayer « ClientReady » vaut true (posé par UI/HUD une fois l'instantané de
--     profil reçu et le HUD construit) ; toutes les attentes sont bornées
--   * après 20 s : « Ton Nid se réveille… » / « Your Nest is waking up… » (textes embarqués FR/EN
--     selon LocaleId, identiques aux clés loading.wake / loading.retry de Strings.luau, car
--     Localization n'est pas encore répliqué) + bouton Réessayer (TeleportService:Teleport(PlaceId))
-- Une seule connexion RenderStepped, coupée à la fermeture. Le temps de l'écran est la somme des dt
-- des images (mesure purement technique, sans Shared/Util/Clock qui n'est pas encore répliqué).
-- GDD : §3 (chargement), §9.2, §10.3 (écrans Chargement / Échec), §12.2.
-- Dépendances : aucune (services Roblox uniquement).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

-- Textes embarqués (mêmes valeurs que Strings.luau : loading.wake, loading.retry)
local TEXTS = {
	en = { wake = "Your Nest is waking up…", retry = "Retry" },
	fr = { wake = "Ton Nid se réveille…", retry = "Réessayer" },
}

local FAIL_AFTER = 20 -- s avant l'écran « Réessayer »
local FADE_TIME = 0.3
local RETRY_COOLDOWN = 5 -- s entre deux tentatives de téléportation
local PLAYER_WAIT = 10 -- s au plus pour LocalPlayer / PlayerGui
local REFERENCE = Vector2.new(1280, 720)
local TAU = 2 * math.pi

-- Constantes graphiques (charte du jeu : crépuscule violet → orangé, Puffkin crème)
local SKY_TOP = Color3.fromRGB(34, 22, 70)
local SKY_MID = Color3.fromRGB(96, 52, 140)
local SKY_BOTTOM = Color3.fromRGB(255, 150, 120)
local BODY_COLOR = Color3.fromRGB(255, 236, 200)
local PUFF_COLOR = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(58, 38, 92)
local EYE_COLOR = Color3.fromRGB(28, 22, 40)
local CHEEK_COLOR = Color3.fromRGB(255, 160, 190)
local DOT_COLOR = Color3.fromRGB(255, 226, 150)
local BUTTON_COLOR = Color3.fromRGB(255, 200, 70)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local STAR_COUNT = 16
local BODY = 120 -- px (avant mise à l'échelle)
local BOUNCE_HEIGHT = 60
local BOUNCE_PERIOD = 0.9
local SQUASH = 0.2
local BLINK_EVERY = 3.2
local BLINK_TIME = 0.1
local DOT_PERIOD = 1.2

local function reducedMotion(): boolean
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

-- L'écran par défaut de Roblox est retiré dès que le nôtre existe (API absente : rien à retirer)
local function removeDefaultScreen()
	pcall(function()
		ReplicatedFirst:RemoveDefaultLoadingScreen()
	end)
end

local function waitLocalPlayer(): Player?
	local player = Players.LocalPlayer
	local waited = 0
	while player == nil and waited < PLAYER_WAIT do
		waited += task.wait()
		player = Players.LocalPlayer
	end
	return player
end

local function round(gui: GuiObject, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0.5, 0)
	corner.Parent = gui
end

local function frame(
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	color: Color3,
	z: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function outline(gui: GuiObject, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = OUTLINE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui
end

local function languageOf(player: Player): "en" | "fr"
	local ok, locale = pcall(function()
		return player.LocaleId
	end)
	if ok and type(locale) == "string" and string.sub(string.lower(locale), 1, 2) == "fr" then
		return "fr"
	end
	return "en"
end

local function main()
	local player = waitLocalPlayer()
	if player == nil then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
		or player:WaitForChild("PlayerGui", PLAYER_WAIT)
	if playerGui == nil then
		return
	end
	local texts = TEXTS[languageOf(player)]
	local calm = reducedMotion()

	-- Écran ------------------------------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = "Loading"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("CanvasGroup")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.new(1, 1, 1)
	root.BorderSizePixel = 0
	root.GroupTransparency = 0
	root.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, SKY_TOP),
		ColorSequenceKeypoint.new(0.6, SKY_MID),
		ColorSequenceKeypoint.new(1, SKY_BOTTOM),
	})
	gradient.Parent = root

	-- Étoiles qui scintillent (tweens en boucle gérés par le moteur)
	local stars = Instance.new("Frame")
	stars.Name = "Stars"
	stars.Size = UDim2.fromScale(1, 0.6)
	stars.BackgroundTransparency = 1
	stars.Parent = root
	local rng = Random.new(20261031)
	for i = 1, STAR_COUNT do
		local size = rng:NextInteger(3, 6)
		local star = frame(
			"Star" .. i,
			stars,
			UDim2.fromOffset(size, size),
			UDim2.fromScale(rng:NextNumber(0.04, 0.96), rng:NextNumber(0.05, 0.95)),
			TEXT_COLOR
		)
		star.BackgroundTransparency = rng:NextNumber(0.1, 0.5)
		round(star)
		if not calm then
			TweenService:Create(
				star,
				TweenInfo.new(
					rng:NextNumber(0.8, 1.8),
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true,
					rng:NextNumber(0, 1)
				),
				{ BackgroundTransparency = 0.85 }
			):Play()
		end
	end

	-- Scène centrale mise à l'échelle de l'écran
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(260, 300)
	stage.BackgroundTransparency = 1
	stage.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = stage
	local function rescale()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else REFERENCE
		scale.Scale = math.clamp(math.min(viewport.X / REFERENCE.X, viewport.Y / REFERENCE.Y) * 1.2, 0.6, 1.4)
	end
	rescale()

	-- Puffkin en Frames : ombre, corps, 3 bouffées, yeux (reflets), joues, sourire
	local groundY = 190
	local shadow = frame(
		"Shadow",
		stage,
		UDim2.fromOffset(96, 18),
		UDim2.fromOffset(130, groundY + 8),
		Color3.new(0, 0, 0)
	)
	shadow.BackgroundTransparency = 0.65
	round(shadow)

	local nebby = Instance.new("Frame")
	nebby.Name = "Nebby"
	nebby.AnchorPoint = Vector2.new(0.5, 1)
	nebby.Size = UDim2.fromOffset(BODY, BODY)
	nebby.Position = UDim2.fromOffset(130, groundY)
	nebby.BackgroundTransparency = 1
	nebby.ZIndex = 2
	nebby.Parent = stage

	for i, pos in { Vector2.new(0.5, 0.02), Vector2.new(0.3, 0.1), Vector2.new(0.7, 0.1) } do
		local puff = frame(
			"Puff" .. i,
			nebby,
			UDim2.fromScale(0.42, 0.42),
			UDim2.fromScale(pos.X, pos.Y),
			PUFF_COLOR,
			2
		)
		round(puff)
		outline(puff, 3)
	end
	local body = frame("Body", nebby, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), BODY_COLOR, 3)
	round(body)
	outline(body, 3)

	local eyes: { Frame } = {}
	for i, x in { 0.33, 0.67 } do
		local eye = frame("Eye" .. i, body, UDim2.fromScale(0.2, 0.2), UDim2.fromScale(x, 0.44), EYE_COLOR, 4)
		round(eye)
		local glint =
			frame("Glint", eye, UDim2.fromScale(0.36, 0.36), UDim2.fromScale(0.66, 0.32), TEXT_COLOR, 5)
		round(glint)
		eyes[i] = eye
	end
	for i, x in { 0.2, 0.8 } do
		local cheek =
			frame("Cheek" .. i, body, UDim2.fromScale(0.18, 0.11), UDim2.fromScale(x, 0.6), CHEEK_COLOR, 4)
		cheek.BackgroundTransparency = 0.15
		round(cheek)
	end
	local smile = frame("Smile", body, UDim2.fromScale(0.14, 0.06), UDim2.fromScale(0.5, 0.62), EYE_COLOR, 4)
	round(smile)

	-- 3 points animés
	local dotsFrame = Instance.new("Frame")
	dotsFrame.Name = "Dots"
	dotsFrame.AnchorPoint = Vector2.new(0.5, 0)
	dotsFrame.Position = UDim2.fromOffset(130, groundY + 36)
	dotsFrame.Size = UDim2.fromOffset(90, 24)
	dotsFrame.BackgroundTransparency = 1
	dotsFrame.Parent = stage
	local dots: { Frame } = {}
	for i = 1, 3 do
		local dot = frame(
			"Dot" .. i,
			dotsFrame,
			UDim2.fromOffset(14, 14),
			UDim2.fromScale((i - 0.5) / 3, 0.5),
			DOT_COLOR
		)
		round(dot)
		dots[i] = dot
	end

	-- Écran d'échec (caché) : message + Réessayer
	local fail = Instance.new("Frame")
	fail.Name = "Fail"
	fail.AnchorPoint = Vector2.new(0.5, 0)
	fail.Position = UDim2.fromScale(0.5, 0.68)
	fail.Size = UDim2.fromOffset(420, 150)
	fail.BackgroundTransparency = 1
	fail.Visible = false
	fail.Parent = root
	local failScale = Instance.new("UIScale")
	failScale.Parent = fail
	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.Size = UDim2.new(1, 0, 0, 44)
	message.BackgroundTransparency = 1
	message.Text = texts.wake
	message.TextScaled = true
	message.TextColor3 = TEXT_COLOR
	message.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	message.Parent = fail
	local messageStroke = Instance.new("UIStroke")
	messageStroke.Thickness = 2
	messageStroke.Color = OUTLINE
	messageStroke.Parent = message
	local button = Instance.new("TextButton")
	button.Name = "RetryButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 62)
	button.Size = UDim2.fromOffset(200, 64)
	button.BackgroundColor3 = BUTTON_COLOR
	button.AutoButtonColor = true
	button.Text = texts.retry
	button.TextScaled = true
	button.TextColor3 = OUTLINE
	button.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	button.Parent = fail
	round(button, UDim.new(0, 16))
	outline(button, 3)
	local buttonPadding = Instance.new("UIPadding")
	buttonPadding.PaddingTop = UDim.new(0, 10)
	buttonPadding.PaddingBottom = UDim.new(0, 10)
	buttonPadding.Parent = button
	local buttonScale = Instance.new("UIScale")
	buttonScale.Parent = button

	gui.Parent = playerGui
	removeDefaultScreen()

	-- Boucle -------------------------------------------------------------------------------------
	local elapsed = 0
	local closing = false
	local failShown = false
	local lastRetry = -math.huge
	local connections: { RBXScriptConnection } = {}

	local function disconnectAll()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end

	local function close()
		if closing then
			return
		end
		closing = true
		local tween = TweenService:Create(
			root,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				GroupTransparency = 1,
			}
		)
		tween.Completed:Once(function()
			disconnectAll()
			gui:Destroy()
		end)
		tween:Play()
	end

	local function isReady(): boolean
		local ok, loaded = pcall(function()
			return game:IsLoaded()
		end)
		return ok and loaded == true and player:GetAttribute("ClientReady") == true
	end

	local function check()
		if not closing and isReady() then
			close()
		end
	end

	local function showFail()
		failShown = true
		fail.Visible = true
		if not calm then
			failScale.Scale = 0.6
			TweenService
				:Create(failScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				})
				:Play()
		end
	end

	local function retry()
		if elapsed - lastRetry < RETRY_COOLDOWN then
			return
		end
		lastRetry = elapsed
		if not calm then
			buttonScale.Scale = 0.92
			TweenService
				:Create(buttonScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				})
				:Play()
		end
		local ok, err = pcall(function()
			TeleportService:Teleport(game.PlaceId, player)
		end)
		if not ok then
			warn("[Loading] téléportation impossible :", err)
		end
	end

	local function step(dt: number)
		if closing then
			return
		end
		if type(dt) == "number" and dt == dt and dt > 0 and dt < 1e6 then
			elapsed += dt
		end
		if not calm then
			-- rebond : sinus de la hauteur, écrasement près du sol, ombre qui rétrécit en l'air
			local p = (elapsed % BOUNCE_PERIOD) / BOUNCE_PERIOD
			local h = math.sin(math.pi * p)
			local s = (1 - h) ^ 6
			nebby.Position = UDim2.fromOffset(130, groundY - h * BOUNCE_HEIGHT)
			nebby.Size = UDim2.fromOffset(BODY * (1 + SQUASH * s), BODY * (1 - SQUASH * s))
			shadow.Size = UDim2.fromOffset(96 * (1 - 0.4 * h), 18 * (1 - 0.4 * h))
			shadow.BackgroundTransparency = 0.65 + 0.25 * h
			local blink = (elapsed % BLINK_EVERY) < BLINK_TIME
			for _, eye in eyes do
				eye.Size = if blink then UDim2.fromScale(0.2, 0.03) else UDim2.fromScale(0.2, 0.2)
			end
		end
		for i, dot in dots do
			local k = 0.5 + 0.5 * math.sin(TAU * elapsed / DOT_PERIOD - (i - 1) * 0.9)
			dot.BackgroundTransparency = 0.6 - 0.6 * k
			if not calm then
				local size = 10 + 6 * k
				dot.Size = UDim2.fromOffset(size, size)
			end
		end
		if not failShown and elapsed >= FAIL_AFTER then
			showFail()
		end
		check()
	end

	table.insert(connections, RunService.RenderStepped:Connect(step))
	table.insert(connections, player:GetAttributeChangedSignal("ClientReady"):Connect(check))
	table.insert(connections, button.Activated:Connect(retry))
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
	end
	if not game:IsLoaded() then
		table.insert(connections, game.Loaded:Connect(check))
	end
	check()
end

main()
