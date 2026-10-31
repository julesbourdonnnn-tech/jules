--!strict
-- InputController — paquet « client-hud » (docs/04-architecture.md §13.11).
-- Toutes les actions passent par ContextActionService (boutons tactiles créés par notre UI).
-- Responsabilités :
--   * Dash : Maj gauche ou E, bouton X (manette), bouton tactile du HUD → dash() : recharge locale
--     prédite (Formulas.dashCooldown(R)), refus local si porteur de la Comète, remote Dash,
--     VFXController.playDash, son Dash ; synchronisation sur l'attribut Player « DashReadyAt »
--   * roue de pings : Q (puis 1-6 ou clic), croix haut (puis stick + A), bouton tactile 72 px ;
--     6 secteurs de 96 px dessinés en Frames ; remote Ping(kind) au plus 1 / 1,5 s ; emote locale
--     (Humanoid:PlayEmote) : Suis-moi → point, Bravo → cheer, Merci → wave
--   * raccourcis : U, C, J, B, G → panneaux (PanelController) ; Échap / B ferme la roue (panneau
--     ouvert : B / Échap / LB / RB sont liés et absorbés par PanelController à plus haute priorité) ;
--     Y ouvre le rail (signal RailRequested, le HUD sélectionne le premier bouton) ;
--     M / croix bas : minicarte ; F / croix droite : acclamer
--   * type d'entrée (1 tactile, 2 clavier-souris, 3 manette) depuis UserInputService
--     (LastInputTypeChanged) → remote SetInputType au plus 1 / 5 s (seulement s'il change)
--   * StarterPlayer.EnableMouseLockOption = false (projet) : Maj sert au Dash
-- Ouverture des panneaux centralisée (openPanel / togglePanel) : arguments posés par l'accueil
-- (setPanelArgs, ex. { focus = "conga" }) et garde posée par le HUD (setPanelGate : pas de
-- panneau dont l'icône n'est pas encore affichée).
-- Une seule connexion Heartbeat (envoi différé du type d'entrée, stick de la roue).
-- GDD : §6.3, §10.2 (Dash, Ping), §10.4.
-- Dépendances : StateController, AudioController, Util/Prefs, VFXController, WorldStateController,
-- PanelController, ScreenFX, Logic/Formulas, Config/Balance, Shared/Net, Shared/Util/Clock.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Formulas = require(Shared.Logic.Formulas)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local WorldStateController = require(Client.Controllers.WorldStateController)
local VFXController = require(Client.Controllers.VFXController)
local PanelController = require(Client.Controllers.PanelController)
local ScreenFX = require(Client.UI.ScreenFX)
local Widgets = require(Client.UI.Hud.Widgets)

local InputController = {}

-- Dash envoyé (prédiction locale acceptée)
InputController.Dashed = Signal.new() :: Signal.Signal<>
-- (kind 1-3)
InputController.InputTypeChanged = Signal.new() :: Signal.Signal<number>
-- Demande d'acclamation (F / croix droite) — le HUD envoie le remote Cheer
InputController.CheerRequested = Signal.new() :: Signal.Signal<>
-- Bascule de la minicarte (M / croix bas)
InputController.MinimapToggled = Signal.new() :: Signal.Signal<>
-- Ajouts du paquet client-hud : Dash refusé localement (raison), Y (manette) : sélection du rail
InputController.DashRefused = Signal.new() :: Signal.Signal<string>
InputController.RailRequested = Signal.new() :: Signal.Signal<>

-- Constantes (GDD §6.3, §10.4) ------------------------------------------------------------------

local TOUCH, KEYBOARD, GAMEPAD = 1, 2, 3
local INPUT_SEND_INTERVAL = 5 -- remote SetInputType : 1 / 5 s
local PING_COOLDOWN = Balance.Ping.Cooldown
local PING_COUNT = Balance.Ping.Count
local WHEEL_RADIUS = 132 -- px de référence
local SECTOR = 96
local STICK_DEADZONE = 0.45
local REFUSE_TOAST_INTERVAL = 2
local EMOTES: { [number]: string } = { [2] = "point", [4] = "cheer", [6] = "wave" }

-- Icônes des pings (§6.3) : bouée, flèche, Comète, étoile, point d'exclamation, cœur
local PING_ICONS: { { glyph: string, color: Color3 } } = {
	{ glyph = "◎", color = Color3.fromRGB(255, 120, 110) },
	{ glyph = "➜", color = Color3.fromRGB(120, 220, 255) },
	{ glyph = "☄", color = Color3.fromRGB(255, 205, 60) },
	{ glyph = "★", color = Color3.fromRGB(255, 230, 110) },
	{ glyph = "!", color = Color3.fromRGB(255, 150, 60) },
	{ glyph = "♥", color = Color3.fromRGB(255, 120, 190) },
}

local PANEL_KEYS: { [Enum.KeyCode]: Types.PanelName } = {
	[Enum.KeyCode.U] = "Upgrades",
	[Enum.KeyCode.C] = "Collection",
	[Enum.KeyCode.J] = "Goals",
	[Enum.KeyCode.B] = "Shop",
	[Enum.KeyCode.G] = "Crew",
}

local NUMBER_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.KeypadSix] = 6,
}

local ACTION = {
	dash = "CC_Dash",
	wheel = "CC_PingWheel",
	pingKey = "CC_PingKey",
	pingStick = "CC_PingStick",
	pingConfirm = "CC_PingConfirm",
	close = "CC_Close",
	panels = "CC_Panels",
	rail = "CC_Rail",
	minimap = "CC_Minimap",
	cheer = "CC_Cheer",
}

-- État ------------------------------------------------------------------------------------------

type Remotes = { Dash: RemoteEvent, Ping: RemoteEvent, SetInputType: RemoteEvent }

local started = false
local remotes: Remotes? = nil
local inputKind = KEYBOARD
local sentKind = 0
local lastSent = -math.huge
local readyAt = 0 -- Clock.now() de fin de recharge (prédite puis confirmée par DashReadyAt)
local cooldownLength = Balance.Dash.CooldownBase
local lastPing = -math.huge
local lastRefuseToast = -math.huge
local cheerAvailable = false
local panelArgs: { [string]: any } = {}
local panelGate: ((Types.PanelName) -> boolean)? = nil
local wheelGui: Frame? = nil
local wheelSectors: { TextButton } = {}
local wheelOpen = false
local wheelSelected = 0

-- Outils ----------------------------------------------------------------------------------------

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function getRemotes(): Remotes
	local r = remotes
	if r then
		return r
	end
	local made: Remotes = {
		Dash = Net.event("Dash"),
		Ping = Net.event("Ping"),
		SetInputType = Net.event("SetInputType"),
	}
	remotes = made
	return made
end

-- Appel protégé de PanelController (paquet client-panels) : une erreur ne casse pas l'entrée
local function panels(fnName: string, ...: any): (boolean, any)
	local fn = (PanelController :: any)[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[InputController] PanelController." .. fnName .. " :", result)
	end
	return ok, result
end

local function currentPanel(): Types.PanelName?
	local ok, result = panels("current")
	return if ok and type(result) == "string" then result :: Types.PanelName else nil
end

local function kindFor(inputType: Enum.UserInputType): number?
	if inputType == Enum.UserInputType.Touch then
		return TOUCH
	end
	if
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return KEYBOARD
	end
	if string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return GAMEPAD
	end
	return nil
end

local function character(): (Humanoid?, BasePart?)
	local player = Players.LocalPlayer
	local char = if player then player.Character else nil
	if char == nil then
		return nil, nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return humanoid, if root and root:IsA("BasePart") then root else nil
end

local function isCarrier(): boolean
	local player = Players.LocalPlayer
	local ev = WorldStateController.events()
	local c = if ev then ev.comet else nil
	return player ~= nil and c ~= nil and c.phase == "carried" and c.carrierId == player.UserId
end

local function supernovas(): number
	local r = State.get("supernovas")
	return if isFinite(r) then math.max(0, math.floor(r)) else 0
end

local function typing(): boolean
	local ok, box = pcall(function()
		return UserInputService:GetFocusedTextBox()
	end)
	return ok and box ~= nil
end

-- Type d'entrée -----------------------------------------------------------------------------------

-- Type d'entrée confirmé par le serveur (attribut Player « InputType », docs §3.3), nil si inconnu
local function confirmedKind(): number?
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute("InputType") else nil
	return if isFinite(value) then value :: number else nil
end

-- Envoi au plus 1 / 5 s. Le serveur limite par seau à jetons (1 / 5 s) : un envoi qui arrive un
-- peu trop tôt (gigue réseau) est ignoré en silence. Tant que l'attribut confirmé diffère du type
-- courant, on renvoie donc à l'intervalle suivant (sans attribut : on se fie au dernier envoi).
local function flushInputType(now: number)
	if now - lastSent < INPUT_SEND_INTERVAL and now >= lastSent then
		return
	end
	local confirmed = confirmedKind()
	local pending = if confirmed ~= nil then confirmed ~= inputKind else sentKind ~= inputKind
	if not pending then
		return
	end
	lastSent = now
	sentKind = inputKind
	getRemotes().SetInputType:FireServer(inputKind)
end

local function setInputKind(kind: number)
	if kind == inputKind then
		return
	end
	inputKind = kind
	InputController.InputTypeChanged:Fire(kind)
	flushInputType(Clock.now())
end

-- Roue de pings --------------------------------------------------------------------------------------

local function highlight(index: number)
	wheelSelected = index
	for i, button in wheelSectors do
		local holder = button.Parent :: GuiObject
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if i == index then Theme.Colors.Gold else Widgets.STROKE
			stroke.Thickness = if i == index then 4 else 3
		end
		local s = holder:FindFirstChild("HudScale")
		if s and s:IsA("UIScale") then
			Juice.tween(s, 0.1, { Scale = if i == index then 1.15 else 1 })
		end
	end
end

local function buildWheel(): Frame
	if wheelGui and wheelGui.Parent then
		return wheelGui :: Frame
	end
	local safe = Root.safe("PingWheel", 30)
	local wheel = Create("Frame", {
		Name = "Wheel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset((WHEEL_RADIUS + SECTOR) * 2, (WHEEL_RADIUS + SECTOR) * 2),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = safe,
	})
	-- disque de fond discret
	Create("Frame", {
		Name = "Backdrop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WHEEL_RADIUS * 2 + SECTOR, WHEEL_RADIUS * 2 + SECTOR),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0.45,
		Parent = wheel,
	}, { Widgets.round() })
	table.clear(wheelSectors)
	for i = 1, PING_COUNT do
		local angle = math.rad(-90 + (i - 1) * 360 / PING_COUNT)
		local holder = Widgets.holder(
			"Sector" .. i,
			UDim2.fromOffset(SECTOR, SECTOR),
			UDim2.new(0.5, math.cos(angle) * WHEEL_RADIUS, 0.5, math.sin(angle) * WHEEL_RADIUS),
			Vector2.new(0.5, 0.5),
			wheel
		)
		holder.Visible = true
		local icon = PING_ICONS[i]
		local button = Widgets.button("Button", holder, Theme.Colors.PanelLight, true)
		local glyph = Widgets.glyph("Icon", icon.glyph, button, icon.color, 46)
		glyph.Size = UDim2.fromScale(0.62, 0.62)
		glyph.Position = UDim2.fromScale(0.5, 0.42)
		glyph.AutoLocalize = false
		Widgets.label({
			name = "Label",
			text = Prefs.t("ping." .. i),
			size = UDim2.new(1.3, 0, 0.3, 0),
			position = UDim2.fromScale(0.5, 0.86),
			anchor = Vector2.new(0.5, 0.5),
			maxSize = 16,
			zIndex = 4,
			parent = button,
		})
		Widgets.keyCap(button, tostring(i))
		button.Activated:Connect(function()
			InputController.ping(i)
		end)
		button.MouseEnter:Connect(function()
			highlight(i)
		end)
		wheelSectors[i] = button
	end
	-- centre : fermer
	local closeHolder = Widgets.holder(
		"Close",
		UDim2.fromOffset(64, 64),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5),
		wheel
	)
	closeHolder.Visible = true
	local close = Widgets.button("Button", closeHolder, Theme.Colors.Panel, true)
	Widgets.glyph("Icon", "✕", close, Theme.Colors.TextDim, 30).AutoLocalize = false
	close.Activated:Connect(function()
		InputController.closePingWheel()
	end)
	-- navigation manette explicite autour de la roue
	for i, button in wheelSectors do
		button.NextSelectionRight = wheelSectors[i % PING_COUNT + 1]
		button.NextSelectionLeft = wheelSectors[(i - 2) % PING_COUNT + 1]
	end
	wheelGui = wheel
	return wheel
end

local function refreshWheelTexts()
	for i, button in wheelSectors do
		local label = button:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = Prefs.t("ping." .. i)
		end
		local cap = button:FindFirstChild("KeyCap")
		if cap and cap:IsA("TextLabel") then
			cap.Visible = inputKind == KEYBOARD
		end
	end
end

local function onPingKey(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not wheelOpen then
		return Enum.ContextActionResult.Pass
	end
	local kind = NUMBER_KEYS[input.KeyCode]
	if kind == nil then
		return Enum.ContextActionResult.Pass
	end
	InputController.ping(kind)
	return Enum.ContextActionResult.Sink
end

local function onPingStick(
	_: string,
	_state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if not wheelOpen then
		return Enum.ContextActionResult.Pass
	end
	local p = input.Position
	if typeof(p) ~= "Vector3" then
		return Enum.ContextActionResult.Pass
	end
	local v = Vector2.new(p.X, -p.Y) -- stick : Y vers le haut ; écran : Y vers le bas
	if v.Magnitude < STICK_DEADZONE then
		-- stick relâché : laissé au module de contrôle, sinon il garde le dernier vecteur de
		-- marche vu avant l'ouverture de la roue et le personnage marche tout seul ensuite
		return Enum.ContextActionResult.Pass
	end
	local angle = math.deg(math.atan2(v.Y, v.X)) + 90 -- 0 = haut, sens horaire
	local index = math.floor(((angle % 360) + 360 / PING_COUNT / 2) / (360 / PING_COUNT)) % PING_COUNT + 1
	if index ~= wheelSelected then
		highlight(index)
	end
	return Enum.ContextActionResult.Sink
end

local function onPingConfirm(
	_: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not wheelOpen then
		return Enum.ContextActionResult.Pass
	end
	if wheelSelected >= 1 then
		InputController.ping(wheelSelected)
	else
		InputController.closePingWheel()
	end
	return Enum.ContextActionResult.Sink
end

-- Panneaux --------------------------------------------------------------------------------------

local function allowed(name: Types.PanelName): boolean
	local gate = panelGate
	if gate == nil then
		return true
	end
	local ok, result = pcall(gate, name)
	return ok and result == true
end

-- Ouvre un panneau avec les arguments posés par l'accueil (ex. { focus = "conga" })
function InputController.openPanel(name: Types.PanelName): boolean
	if not allowed(name) then
		return false
	end
	local ok = panels("open", name, panelArgs[name])
	return ok
end

-- Bascule : ferme le panneau s'il est déjà ouvert, sinon l'ouvre
function InputController.togglePanel(name: Types.PanelName): boolean
	if currentPanel() == name then
		local ok = panels("close")
		return ok
	end
	return InputController.openPanel(name)
end

function InputController.setPanelArgs(name: Types.PanelName, args: any?)
	panelArgs[name] = args
end

function InputController.setPanelGate(fn: ((Types.PanelName) -> boolean)?)
	panelGate = fn
end

-- Acclamation : le HUD signale qu'une fenêtre est ouverte
function InputController.setCheerAvailable(available: boolean)
	cheerAvailable = available == true
end

function InputController.requestCheer(): boolean
	if not cheerAvailable then
		return false
	end
	cheerAvailable = false -- une acclamation par Supernova
	InputController.CheerRequested:Fire()
	return true
end

-- Actions ---------------------------------------------------------------------------------------

local function began(state: Enum.UserInputState): boolean
	return state == Enum.UserInputState.Begin and not typing()
end

local function onDashAction(
	_: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if not began(state) then
		return Enum.ContextActionResult.Pass
	end
	InputController.dash()
	return Enum.ContextActionResult.Sink
end

local function onWheelAction(
	_: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if not began(state) then
		return Enum.ContextActionResult.Pass
	end
	if wheelOpen then
		InputController.closePingWheel()
	else
		InputController.openPingWheel()
	end
	return Enum.ContextActionResult.Sink
end

local function onCloseAction(
	_: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if not began(state) then
		return Enum.ContextActionResult.Pass
	end
	-- (panneau ouvert : PanelController lie B / Échap à plus haute priorité et les absorbe)
	if wheelOpen then
		InputController.closePingWheel()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function onPanelAction(
	_: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if not began(state) then
		return Enum.ContextActionResult.Pass
	end
	local name = PANEL_KEYS[input.KeyCode]
	if name == nil then
		return Enum.ContextActionResult.Pass
	end
	InputController.togglePanel(name)
	return Enum.ContextActionResult.Sink
end

local function onRailAction(
	_: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if not began(state) then
		return Enum.ContextActionResult.Pass
	end
	InputController.RailRequested:Fire()
	return Enum.ContextActionResult.Sink
end

local function onMinimapAction(
	_: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if not began(state) then
		return Enum.ContextActionResult.Pass
	end
	InputController.MinimapToggled:Fire()
	return Enum.ContextActionResult.Sink
end

local function onCheerAction(
	_: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if not began(state) then
		return Enum.ContextActionResult.Pass
	end
	return if InputController.requestCheer()
		then Enum.ContextActionResult.Sink
		else Enum.ContextActionResult.Pass
end

local function bindAll()
	ContextActionService:BindAction(
		ACTION.dash,
		onDashAction,
		false,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:BindAction(ACTION.wheel, onWheelAction, false, Enum.KeyCode.Q, Enum.KeyCode.DPadUp)
	ContextActionService:BindAction(
		ACTION.close,
		onCloseAction,
		false,
		Enum.KeyCode.Escape,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:BindAction(
		ACTION.panels,
		onPanelAction,
		false,
		Enum.KeyCode.U,
		Enum.KeyCode.C,
		Enum.KeyCode.J,
		Enum.KeyCode.B,
		Enum.KeyCode.G
	)
	ContextActionService:BindAction(ACTION.rail, onRailAction, false, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction(
		ACTION.minimap,
		onMinimapAction,
		false,
		Enum.KeyCode.M,
		Enum.KeyCode.DPadDown
	)
	ContextActionService:BindAction(
		ACTION.cheer,
		onCheerAction,
		false,
		Enum.KeyCode.F,
		Enum.KeyCode.DPadRight
	)
end

-- Dash ------------------------------------------------------------------------------------------

local function refuse(reason: string)
	InputController.DashRefused:Fire(reason)
	if reason == "comet" then
		local now = Clock.now()
		if now - lastRefuseToast >= REFUSE_TOAST_INTERVAL or now < lastRefuseToast then
			lastRefuseToast = now
			ScreenFX.notify("feedback.cometNoDash", nil, "warning")
		end
	end
end

-- Tente un Dash ; false si recharge ou porteur de la Comète
function InputController.dash(): boolean
	local now = Clock.now()
	if now < readyAt then
		refuse("cooldown")
		return false
	end
	local humanoid = character()
	if humanoid == nil or humanoid.Health <= 0 then
		refuse("character")
		return false
	end
	if isCarrier() then
		refuse("comet")
		return false
	end
	cooldownLength = Formulas.dashCooldown(supernovas())
	readyAt = now + cooldownLength
	getRemotes().Dash:FireServer()
	AudioController.play("Dash", 0.04)
	local ok, err = pcall(VFXController.playDash)
	if not ok then
		warn("[InputController] playDash :", err)
	end
	InputController.Dashed:Fire()
	return true
end

-- Clock.now() à partir duquel le Dash est prêt
function InputController.dashReadyAt(): number
	return readyAt
end

-- Progression de la recharge (0 = vient d'être lancé, 1 = prêt) ; ajout du paquet client-hud
function InputController.dashProgress(now: number?): number
	local t = now or Clock.now()
	if t >= readyAt then
		return 1
	end
	return math.clamp(1 - (readyAt - t) / math.max(cooldownLength, 0.1), 0, 1)
end

function InputController.inputType(): number
	return inputKind
end

-- Roue de pings ---------------------------------------------------------------------------------

function InputController.openPingWheel()
	if wheelOpen then
		return
	end
	local wheel = buildWheel()
	wheelOpen = true
	wheelSelected = 0
	refreshWheelTexts()
	wheel.Visible = true
	for i, button in wheelSectors do
		local holder = button.Parent :: GuiObject
		local s = holder:FindFirstChild("HudScale") :: UIScale
		if Prefs.reducedMotion() then
			s.Scale = 1
		else
			s.Scale = 0
			-- 0 → 1 en 0,2 s (Back Out), décalés de 0,02 s
			Juice.tween(
				s,
				0.2,
				{ Scale = 1 },
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out,
				(i - 1) * 0.02
			)
		end
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Widgets.STROKE
			stroke.Thickness = 3
		end
	end
	ContextActionService:BindActionAtPriority(
		ACTION.pingKey,
		onPingKey,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
		Enum.KeyCode.KeypadOne,
		Enum.KeyCode.KeypadTwo,
		Enum.KeyCode.KeypadThree,
		Enum.KeyCode.KeypadFour,
		Enum.KeyCode.KeypadFive,
		Enum.KeyCode.KeypadSix
	)
	ContextActionService:BindActionAtPriority(
		ACTION.pingStick,
		onPingStick,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.Thumbstick1
	)
	ContextActionService:BindActionAtPriority(
		ACTION.pingConfirm,
		onPingConfirm,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.ButtonA
	)
	if inputKind == GAMEPAD then
		pcall(function()
			GuiService.SelectedObject = wheelSectors[1]
		end)
	end
	AudioController.play("Whoosh", 0.05)
end

function InputController.closePingWheel()
	if not wheelOpen then
		return
	end
	wheelOpen = false
	wheelSelected = 0
	ContextActionService:UnbindAction(ACTION.pingKey)
	ContextActionService:UnbindAction(ACTION.pingStick)
	ContextActionService:UnbindAction(ACTION.pingConfirm)
	local wheel = wheelGui
	if wheel then
		wheel.Visible = false
	end
	pcall(function()
		local selected = GuiService.SelectedObject
		if selected and wheel and selected:IsDescendantOf(wheel) then
			GuiService.SelectedObject = nil
		end
	end)
end

function InputController.isPingWheelOpen(): boolean
	return wheelOpen
end

-- Envoie un ping (kind 1-6) ; false si limité
function InputController.ping(kind: number): boolean
	if not isFinite(kind) or kind % 1 ~= 0 or kind < 1 or kind > PING_COUNT then
		return false
	end
	local now = Clock.now()
	if now - lastPing < PING_COOLDOWN and now >= lastPing then
		return false
	end
	lastPing = now
	getRemotes().Ping:FireServer(kind)
	InputController.closePingWheel()
	AudioController.play("Click", 0.04)
	local emote = EMOTES[kind]
	if emote then
		InputController.playEmote(emote)
	end
	return true
end

-- Emote locale sur son propre personnage (pings, acclamation « cheer », GDD §6.3, §6.6) ; sans
-- effet si le personnage est absent ou mort, ou si l'emote n'est pas équipée (PlayEmote yield)
function InputController.playEmote(name: string)
	local humanoid = character()
	if humanoid == nil or humanoid.Health <= 0 or type(name) ~= "string" then
		return
	end
	task.spawn(function()
		pcall(function()
			(humanoid :: any):PlayEmote(name)
		end)
	end)
end

-- Cycle de vie ----------------------------------------------------------------------------------

local function syncDashAttribute()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	local value = player:GetAttribute("DashReadyAt")
	if isFinite(value) then
		-- le serveur fait foi : sa fin de recharge remplace la prédiction
		local now = Clock.now()
		local serverReady = value :: number
		if serverReady > now then
			cooldownLength = math.max(serverReady - now, Formulas.dashCooldown(supernovas()))
		end
		readyAt = serverReady
	end
end

local function initialKind(): number
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and typeof(last) == "EnumItem" then
		local kind = kindFor(last :: Enum.UserInputType)
		if kind then
			return kind
		end
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return GAMEPAD
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return TOUCH
	end
	return KEYBOARD
end

function InputController.Init()
	getRemotes()
	inputKind = initialKind()
end

function InputController.Start()
	if started then
		return
	end
	started = true
	bindAll()
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("DashReadyAt"):Connect(syncDashAttribute)
		syncDashAttribute()
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local kind = kindFor(inputType)
		if kind then
			setInputKind(kind)
			refreshWheelTexts()
		end
	end)
	-- le serveur a refusé le Dash : la recharge affichée revient à la valeur serveur
	ScreenFX.FeedbackReceived:Connect(function(payload: Types.FeedbackPayload)
		if payload.key == "feedback.cometNoDash" or payload.key == "feedback.dashCooldown" then
			syncDashAttribute()
		end
	end)
	Prefs.LanguageChanged:Connect(refreshWheelTexts)
	RunService.Heartbeat:Connect(function()
		flushInputType(Clock.now())
	end)
	-- type d'entrée initial (le serveur suppose clavier-souris)
	flushInputType(Clock.now())
end

-- Exposé pour les tests
InputController._actions = ACTION

return InputController
