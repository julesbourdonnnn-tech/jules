--!strict
-- Loading : écran de chargement (LocalScript de ReplicatedFirst), construit en code, AUTONOME
-- (n'exige rien de ReplicatedStorage : il s'affiche avant la réplication). Repris de Comet Conga
-- avec tous ses correctifs (Réessayer retenu pendant le chargement, Réessayer à la manette, échelle
-- TV), habillage neutre : ciel pastel, une petite gelée qui rebondit. Propriété du paquet world.
--   * ReplicatedFirst:RemoveDefaultLoadingScreen() puis ScreenGui « Loading » plein écran dans
--     PlayerGui (IgnoreGuiInset, DisplayOrder élevé, ResetOnSpawn = false) : ciel pastel, étoiles
--     qui scintillent, une gelée en Frames (« Blob ») qui rebondit (écrasement à l'atterrissage,
--     clignement) et 3 points animés ; AUCUN texte pendant le chargement (un enfant qui ne lit pas
--     comprend) ; Mouvement réduit respecté (GuiService.ReducedMotionEnabled : ni rebond ni
--     écrasement, seulement des fondus)
--   * disparition (fondu 0,3 s) quand game:IsLoaded() ET que l'attribut LOCAL
--     Players.LocalPlayer « ClientReady » vaut true (posé par le HUD du jeu, ou par Main.client dès
--     l'instantané du profil) ; toutes les attentes sont bornées
--   * après 20 s : message neutre « Almost ready… » / « Presque prêt… » (textes embarqués FR/EN
--     selon LocaleId, identiques aux clés loading.wake / loading.retry de Strings.luau, car
--     Localization n'est pas encore répliqué) + bouton Réessayer (TeleportService:Teleport(PlaceId))
--   * « Réessayer » attend tant que le chargement AVANCE encore (une téléportation le recommencerait
--     de zéro : boucle sans fin sur un profil verrouillé) : attribut répliqué Player
--     « ProfileLoading » (numéro d'essai, posé par DataService pendant ses essais : verrou d'un autre
--     serveur jusqu'à 30 s, backoff) ou réplication initiale pas finie (game:IsLoaded() faux) ;
--     message rassurant seul pendant ce temps, Réessayer RETRY_GRACE s après la fin de ces attentes,
--     et au plus tard RETRY_MAX_WAIT s après l'ouverture de l'écran (attribut resté posé)
--   * console d'abord (note INT-TV, partie Loading, paquet world) : tout est dessiné en px TV
--     (référence 1920 × 1080) et mis à l'échelle par LA règle télé de tous les écrans, recopiée de
--     Config/Console (= Platform.uiScale) : max(0,5 ; min(L / 1920 ; H / 1080)), sans plafond (1 en
--     1080p, 2 en 4K, 0,667 en 720p ; égalité vérifiée par une spec). Une seule disposition : scène
--     centrée, bloc d'échec à 68 % de la hauteur, dans la zone sûre de 5 % (aucune mise en page de
--     téléphone). Textes ≥ 28 px TV (UITextSizeConstraint), « Réessayer » de 96 px TV de haut
--   * à la manette (IsTenFootInterface sous pcall, ou GamepadEnabled), « Réessayer » est sélectionné
--     d'office (pas de curseur virtuel) avec l'icône ✕ de Roblox (GetImageForKeyCode(ButtonA)) à
--     côté ; tant que l'écran est là, une sélection perdue (bouton retour du jeu, objet derrière
--     l'écran) lui est rendue si la manette est en main (console, ou dernière entrée = manette)
-- Une seule connexion RenderStepped, coupée à la fermeture. Le temps de l'écran est la somme des dt
-- des images (mesure purement technique, sans Shared/Util/Clock qui n'est pas encore répliqué).
-- Dépendances : aucune (services Roblox uniquement).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Textes embarqués (mêmes valeurs que Strings.luau : loading.wake, loading.retry)
local TEXTS = {
	en = { wake = "Almost ready…", retry = "Retry" },
	fr = { wake = "Presque prêt…", retry = "Réessayer" },
}

local FAIL_AFTER = 20 -- s avant « Presque prêt… » (et « Réessayer » si plus rien n'avance)
-- attribut Player répliqué posé par DataService pendant ses essais de chargement (numéro d'essai)
local PROFILE_LOADING = "ProfileLoading"
local RETRY_GRACE = 10 -- s après la fin du chargement serveur / de la réplication avant « Réessayer »
-- au-delà du pire cas de DataService, attribut ProfileLoading posé (6 essais au plus) : verrou d'un
-- autre serveur 5 × 6 s = 30 s ; pannes : backoff 2 + 4 + 8 + 16 + 16 = 46 s, aucune attente après
-- le 6e et dernier essai (renvoi aussitôt), soit ≈ 46 s + la latence des 6 UpdateAsync ; mélange de
-- lectures du verrou et de pannes : 52 s au plus ; DataStore indisponible (GetDataStore en échec) :
-- même chemin, 46 s puis renvoi. Seul cas plus long, rare : reconnexion sur le MÊME serveur pendant
-- une panne (REJOIN_WAIT ≤ 25 s avant le chargement)
local RETRY_MAX_WAIT = 60
local MAX_RESELECTS_PER_FRAME = 4 -- garde-fou contre une sélection disputée image après image
local FADE_TIME = 0.3
local RETRY_COOLDOWN = 5 -- s entre deux tentatives de téléportation
local PLAYER_WAIT = 10 -- s au plus pour LocalPlayer / PlayerGui
local REFERENCE = Vector2.new(1920, 1080) -- = Config/Console.Reference (px TV, note INT-TV)
-- TOUS les écrans : UIScale = max(TV_SCALE_MIN ; min(L / 1920 ; H / 1080)), sans plafond ; recopie
-- de Config/Console.TvScale (non répliqué ici), même règle que Platform.uiScale
local TV_SCALE_MIN = 0.5 -- = Config/Console.TvScale.Min
-- Toutes les dimensions ci-dessous sont en px TV (écran de référence 1920 × 1080)
local GLYPH_SIZE = 72 -- icône ✕ à côté de « Réessayer » (≥ Config/Console.GlyphSize)
local GLYPH_GAP = 12 -- entre l'icône et le bouton
local MIN_TEXT = 28 -- = Config/Console.MinTextSize : texte lisible à 3 m
local MAX_TEXT = 72
-- curseur de sélection (recopie de UI/Root.selectionImage) : trait blanc de 6 px, liseré sombre de 2 px
local SELECTION_COLOR = Color3.fromRGB(255, 255, 255)
local SELECTION_EDGE_COLOR = Color3.fromRGB(16, 12, 30)
local SELECTION_THICKNESS = 6
local SELECTION_EDGE = 2
local SELECTION_OUTSET = 4 -- px de débord autour du bouton (de chaque côté)
local SELECTION_RADIUS = 16
local TAU = 2 * math.pi

-- Écran d'échec (px TV) : message, puis « Réessayer » (bouton principal, 96 de haut) et son curseur
local FAIL_WIDTH = 630
local MESSAGE_HEIGHT = 66
local RETRY_TOP = 93 -- haut de « Réessayer » dans le bloc
local RETRY_SIZE = Vector2.new(300, 96)
local RETRY_PADDING = 15
-- hauteur du bloc : jusqu'au bas du curseur de sélection (débord + trait blanc + liseré sombre)
local FAIL_HEIGHT = RETRY_TOP + RETRY_SIZE.Y + SELECTION_OUTSET + SELECTION_THICKNESS + SELECTION_EDGE
local FAIL_TOP = 0.68 -- haut du bloc (fraction de la hauteur de l'écran) : sous la gelée, dans la zone sûre

-- Constantes graphiques (habillage neutre : ciel pastel lavande → rose → pêche, gelée menthe)
local SKY_TOP = Color3.fromRGB(92, 72, 168)
local SKY_MID = Color3.fromRGB(196, 132, 214)
local SKY_BOTTOM = Color3.fromRGB(255, 186, 160)
local BODY_COLOR = Color3.fromRGB(150, 236, 196)
local PUFF_COLOR = Color3.fromRGB(196, 250, 222)
local OUTLINE = Color3.fromRGB(58, 38, 92)
local EYE_COLOR = Color3.fromRGB(28, 22, 40)
local CHEEK_COLOR = Color3.fromRGB(255, 160, 190)
local DOT_COLOR = Color3.fromRGB(255, 226, 150)
local BUTTON_COLOR = Color3.fromRGB(255, 200, 70)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local STAR_COUNT = 16
local STAR_MIN, STAR_MAX = 5, 9 -- px TV
local STROKE = 4.5 -- contour bleu nuit (px TV)
local STAGE_SIZE = Vector2.new(390, 450)
local STAGE_CENTER_X = 195
local GROUND_Y = 285 -- sol de la gelée dans la scène
local SHADOW_SIZE = Vector2.new(144, 27)
local SHADOW_DROP = 12
local DOTS_TOP = 54 -- sous le sol
local DOTS_SIZE = Vector2.new(135, 36)
local DOT_SIZE = 21
local DOT_GROW = 9
local BODY = 180
local BOUNCE_HEIGHT = 90
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

-- Console (seule détection garantie, sous pcall) ou écran Large (téléviseur)
local function isTenFoot(): boolean
	local ok, value = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and value == true
end

-- Manette : console, ou manette branchée (sans curseur virtuel, seule la sélection l'atteint)
local function gamepadLikely(): boolean
	if isTenFoot() then
		return true
	end
	local ok, value = pcall(function()
		return UserInputService.GamepadEnabled
	end)
	return ok and value == true
end

-- Manette EN MAIN : console, ou dernière entrée venue d'une manette (une souris garde la main sur PC)
local function padInUse(): boolean
	if isTenFoot() then
		return true
	end
	local ok, value = pcall(function()
		return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
	end)
	return ok and value == true
end

-- Échelle de l'écran (Config/Console : Reference, TvScale) : la règle télé, sur tous les écrans
local function screenScale(viewport: Vector2): number
	if viewport.X <= 1 or viewport.Y <= 1 then
		return 1
	end
	local s = math.min(viewport.X / REFERENCE.X, viewport.Y / REFERENCE.Y)
	return math.max(s, TV_SCALE_MIN)
end

-- Icône Roblox de la touche (PlayStation sur PlayStation) ; nil si indisponible
local function keyImage(keyCode: Enum.KeyCode): string?
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(keyCode)
	end)
	if ok and type(image) == "string" and image ~= "" then
		return image
	end
	return nil
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

-- Texte télé : TextScaled borné à MIN_TEXT … MAX_TEXT px TV
local function textSize(label: TextLabel | TextButton)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = MIN_TEXT
	constraint.MaxTextSize = MAX_TEXT
	constraint.Parent = label
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
	stars:SetAttribute("Decorative", true) -- fond plein écran, hors zone sûre TV (audit console)
	stars.Parent = root
	local rng = Random.new(20261031)
	local starSizes: { [Frame]: number } = {} -- px TV de chaque étoile (remises à l'échelle de l'écran)
	for i = 1, STAR_COUNT do
		local size = rng:NextInteger(STAR_MIN, STAR_MAX)
		local star = frame(
			"Star" .. i,
			stars,
			UDim2.fromOffset(size, size),
			UDim2.fromScale(rng:NextNumber(0.04, 0.96), rng:NextNumber(0.05, 0.95)),
			TEXT_COLOR
		)
		star.BackgroundTransparency = rng:NextNumber(0.1, 0.5)
		starSizes[star] = size
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
	stage.Size = UDim2.fromOffset(STAGE_SIZE.X, STAGE_SIZE.Y)
	stage.BackgroundTransparency = 1
	stage.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = stage

	-- Gelée en Frames : ombre, corps, 2 petites oreilles, yeux (reflets), joues, sourire
	local groundY = GROUND_Y
	local shadow = frame(
		"Shadow",
		stage,
		UDim2.fromOffset(SHADOW_SIZE.X, SHADOW_SIZE.Y),
		UDim2.fromOffset(STAGE_CENTER_X, groundY + SHADOW_DROP),
		Color3.new(0, 0, 0)
	)
	shadow.BackgroundTransparency = 0.65
	round(shadow)

	local blob = Instance.new("Frame")
	blob.Name = "Blob"
	blob.AnchorPoint = Vector2.new(0.5, 1)
	blob.Size = UDim2.fromOffset(BODY, BODY)
	blob.Position = UDim2.fromOffset(STAGE_CENTER_X, groundY)
	blob.BackgroundTransparency = 1
	blob.ZIndex = 2
	blob.Parent = stage

	for i, pos in { Vector2.new(0.26, 0.06), Vector2.new(0.74, 0.06) } do
		local ear =
			frame("Ear" .. i, blob, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(pos.X, pos.Y), PUFF_COLOR, 2)
		round(ear)
		outline(ear, STROKE)
	end
	local body = frame("Body", blob, UDim2.fromScale(1, 0.9), UDim2.fromScale(0.5, 0.55), BODY_COLOR, 3)
	round(body)
	outline(body, STROKE)

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
	dotsFrame.Position = UDim2.fromOffset(STAGE_CENTER_X, groundY + DOTS_TOP)
	dotsFrame.Size = UDim2.fromOffset(DOTS_SIZE.X, DOTS_SIZE.Y)
	dotsFrame.BackgroundTransparency = 1
	dotsFrame.Parent = stage
	local dots: { Frame } = {}
	for i = 1, 3 do
		local dot = frame(
			"Dot" .. i,
			dotsFrame,
			UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
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
	fail.Position = UDim2.fromScale(0.5, FAIL_TOP)
	fail.Size = UDim2.fromOffset(FAIL_WIDTH, FAIL_HEIGHT)
	fail.BackgroundTransparency = 1
	fail.Visible = false
	fail.Parent = root
	local failUIScale = Instance.new("UIScale")
	failUIScale.Name = "FailScale"
	failUIScale.Parent = fail

	-- Échelle : une seule règle télé (px TV × échelle de l'écran) pour la scène, le bloc d'échec (que
	-- failUIScale anime à l'entrée autour de son ancre) et les étoiles ; scène centrée, bloc à 68 %
	-- de la hauteur (dans la zone sûre de 5 % aux résolutions télé : 720p, 1080p, 4K, 16:10, 21:9)
	local failBase = 1
	local function rescale()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else REFERENCE
		local s = screenScale(viewport)
		scale.Scale = s
		failBase = s
		failUIScale.Scale = failBase
		for star, size in starSizes do
			star.Size = UDim2.fromOffset(size * s, size * s)
		end
	end
	rescale()

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.Size = UDim2.new(1, 0, 0, MESSAGE_HEIGHT)
	message.BackgroundTransparency = 1
	message.Text = texts.wake
	message.TextScaled = true
	message.TextColor3 = TEXT_COLOR
	message.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	textSize(message)
	message.Parent = fail
	local messageStroke = Instance.new("UIStroke")
	messageStroke.Thickness = 3
	messageStroke.Color = OUTLINE
	messageStroke.Parent = message
	local button = Instance.new("TextButton")
	button.Name = "RetryButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, RETRY_TOP)
	button.Size = UDim2.fromOffset(RETRY_SIZE.X, RETRY_SIZE.Y)
	button.BackgroundColor3 = BUTTON_COLOR
	button.AutoButtonColor = true
	button.Text = texts.retry
	button.TextScaled = true
	button.TextColor3 = OUTLINE
	button.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	button.Visible = false -- montré par showRetry (chargement qui n'avance plus)
	textSize(button)
	button.Parent = fail
	round(button, UDim.new(0, 24))
	outline(button, STROKE)
	local buttonPadding = Instance.new("UIPadding")
	buttonPadding.PaddingTop = UDim.new(0, RETRY_PADDING)
	buttonPadding.PaddingBottom = UDim.new(0, RETRY_PADDING)
	buttonPadding.Parent = button
	local buttonScale = Instance.new("UIScale")
	buttonScale.Parent = button
	-- curseur de sélection bien visible à 3 m, sur fond clair comme sombre (même dessin que
	-- UI/Root.selectionImage, sans respiration : écran de quelques secondes)
	local selection = Instance.new("Frame")
	selection.Name = "SelectionHighlight"
	selection.BackgroundTransparency = 1
	selection.AnchorPoint = Vector2.new(0.5, 0.5)
	selection.Position = UDim2.fromScale(0.5, 0.5)
	selection.Size = UDim2.new(1, 2 * SELECTION_OUTSET, 1, 2 * SELECTION_OUTSET)
	round(selection, UDim.new(0, SELECTION_RADIUS))
	local selectionStroke = Instance.new("UIStroke")
	selectionStroke.Name = "Cursor"
	selectionStroke.Color = SELECTION_COLOR
	selectionStroke.Thickness = SELECTION_THICKNESS
	selectionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	selectionStroke.Parent = selection
	-- liseré sombre à l'extérieur du trait blanc (cadre imbriqué : un seul UIStroke par objet)
	local selectionEdge = Instance.new("Frame")
	selectionEdge.Name = "Edge"
	selectionEdge.BackgroundTransparency = 1
	selectionEdge.AnchorPoint = Vector2.new(0.5, 0.5)
	selectionEdge.Position = UDim2.fromScale(0.5, 0.5)
	selectionEdge.Size = UDim2.new(1, 2 * SELECTION_THICKNESS, 1, 2 * SELECTION_THICKNESS)
	round(selectionEdge, UDim.new(0, SELECTION_RADIUS + SELECTION_THICKNESS))
	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Name = "Edge"
	edgeStroke.Color = SELECTION_EDGE_COLOR
	edgeStroke.Thickness = SELECTION_EDGE
	edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edgeStroke.Parent = selectionEdge
	selectionEdge.Parent = selection
	button.SelectionImageObject = selection

	gui.Parent = playerGui
	removeDefaultScreen()

	-- Boucle -------------------------------------------------------------------------------------
	local elapsed = 0
	local closing = false
	local failShown = false -- message « Presque prêt… »
	local retryShown = false -- bouton « Réessayer »
	local lastBusy = -math.huge -- dernier instant (elapsed) où le chargement avançait encore
	local reselects = 0 -- sélections rendues à « Réessayer » pendant l'image en cours
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
		-- manette : la sélection quitte « Réessayer » (le stick fait de nouveau marcher)
		pcall(function()
			if GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(gui) then
				GuiService.SelectedObject = nil
			end
		end)
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

	-- Le chargement avance encore : DataService réessaie (attribut répliqué ProfileLoading = numéro
	-- d'essai > 0 ; toute autre valeur est ignorée) ou la réplication initiale n'est pas finie
	-- (appelé à chaque image : aucune fermeture créée ici)
	local function gameLoaded(): boolean
		return game:IsLoaded()
	end
	local function stillLoading(): boolean
		local attempt = player:GetAttribute(PROFILE_LOADING)
		if type(attempt) == "number" and attempt > 0 and attempt < math.huge then
			return true
		end
		local ok, loaded = pcall(gameLoaded)
		return ok and loaded == false
	end

	-- Manette : icône ✕ (image Roblox de ButtonA) à gauche de « Réessayer » ; rien si indisponible
	local function addConfirmGlyph()
		if fail:FindFirstChild("PadGlyph") then
			return
		end
		local image = keyImage(Enum.KeyCode.ButtonA)
		if image == nil then
			return
		end
		local holder = Instance.new("Frame")
		holder.Name = "PadGlyph"
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position =
			UDim2.new(0.5, -button.Size.X.Offset / 2 - GLYPH_GAP, 0, RETRY_TOP + button.Size.Y.Offset / 2)
		holder.Size = UDim2.fromOffset(GLYPH_SIZE, GLYPH_SIZE)
		holder.BackgroundTransparency = 1
		holder:SetAttribute("GlyphKey", Enum.KeyCode.ButtonA.Name)
		holder:SetAttribute("GlyphMode", "image")
		holder.Parent = fail
		local icon = Instance.new("ImageLabel")
		icon.Name = "Image"
		icon.Size = UDim2.fromScale(1, 1)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = image
		icon.Parent = holder
	end

	local function selectRetry()
		addConfirmGlyph()
		pcall(function()
			GuiService.SelectedObject = button
		end)
	end

	-- Sélection hors de l'écran de chargement (rien, ou un objet caché derrière lui)
	local function selectionLost(): boolean
		local ok, lost = pcall(function()
			local selected = GuiService.SelectedObject
			return selected == nil or not selected:IsDescendantOf(gui)
		end)
		return ok and lost == true
	end

	-- Manette en main et « Réessayer » affiché : une sélection perdue (bouton retour du jeu qui
	-- l'efface, bouton de menu qui sélectionne un objet caché derrière, moteur) lui est rendue juste
	-- après, sinon l'enfant reste bloqué devant un écran figé
	local function keepRetrySelected()
		if not retryShown or closing or not selectionLost() or not padInUse() then
			return
		end
		if reselects >= MAX_RESELECTS_PER_FRAME then
			return
		end
		reselects += 1
		task.defer(function()
			if retryShown and not closing and gui.Parent ~= nil and selectionLost() then
				selectRetry()
			end
		end)
	end

	local function showFail()
		failShown = true
		fail.Visible = true
		local fs = failUIScale
		if not calm then
			fs.Scale = 0.6 * failBase
			TweenService:Create(fs, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = failBase,
			}):Play()
		end
	end

	local function showRetry()
		retryShown = true
		button.Visible = true
		if not calm then
			buttonScale.Scale = 0.6
			TweenService
				:Create(buttonScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				})
				:Play()
		end
		-- manette : sans curseur virtuel, seule la sélection atteint « Réessayer » ; ✕ l'active
		if gamepadLikely() then
			selectRetry()
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
			blob.Position = UDim2.fromOffset(STAGE_CENTER_X, groundY - h * BOUNCE_HEIGHT)
			blob.Size = UDim2.fromOffset(BODY * (1 + SQUASH * s), BODY * (1 - SQUASH * s))
			shadow.Size = UDim2.fromOffset(SHADOW_SIZE.X * (1 - 0.4 * h), SHADOW_SIZE.Y * (1 - 0.4 * h))
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
				local size = DOT_SIZE - DOT_GROW / 2 + DOT_GROW * k
				dot.Size = UDim2.fromOffset(size, size)
			end
		end
		reselects = 0
		if stillLoading() then
			lastBusy = elapsed
		end
		if not failShown and elapsed >= FAIL_AFTER then
			showFail()
		end
		if
			failShown
			and not retryShown
			and (elapsed - lastBusy >= RETRY_GRACE or elapsed >= RETRY_MAX_WAIT)
		then
			showRetry()
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
	-- manette prise en main pendant l'écran d'échec (PC) : « Réessayer » sélectionné à ce moment-là
	table.insert(
		connections,
		UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
			if retryShown and not closing and string.sub(inputType.Name, 1, 7) == "Gamepad" then
				if selectionLost() then
					selectRetry()
				end
			end
		end)
	)
	-- sélection perdue pendant l'écran d'échec, manette en main : rendue à « Réessayer »
	pcall(function()
		table.insert(
			connections,
			GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(keepRetrySelected)
		)
	end)
	if not game:IsLoaded() then
		table.insert(connections, game.Loaded:Connect(check))
	end
	check()
end

main()
