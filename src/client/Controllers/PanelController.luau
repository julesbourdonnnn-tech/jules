--!strict
-- PanelController — paquet « client-panels » (docs/04-architecture.md §13.15).
-- API de navigation des panneaux utilisée par le HUD, InputController et l'accueil.
-- Responsabilités :
--   * un seul panneau ouvert à la fois ; open(name) ferme le précédent ; back() revient au panneau
--     parent (Supernova → Upgrades) ; close() ; ouvrir un panneau ne met jamais le jeu en pause
--   * construction paresseuse : chaque module de UI/Panels/* est construit à la première ouverture
--     dans un ScreenGui « Panels » (Root.safe) : Size = UDim2.fromScale(0,72 ; 0,86), UISizeConstraint
--     (min 480 × 320, max 900 × 600), onglets de 56 px, bouton Fermer 64 × 64 ; ouverture UIScale
--     0,85 → 1 (0,22 s Back Out) + CanvasGroup 1 → 0 (0,15 s) + BlurEffect 0 → 8 (sauf Graphismes
--     légers) ; fermeture 0,12 s Quad In ; son Whoosh ; Mouvement réduit : fondus seulement
--   * manette : GuiService.SelectedObject sur le premier bouton (si la dernière entrée est une
--     manette), fenêtre en SelectionGroup ; tant qu'un panneau est ouvert, B / Échap = retour,
--     LB / RB = onglets, liés via ContextActionService à haute priorité et « absorbés » (Sink) pour
--     ne jamais être traités deux fois
--   * pastilles « ! » : hasAction() de chaque panneau (sans le construire), réévalué à chaque
--     changement du profil et chaque seconde (Glow prédit, minuit UTC) → BadgeChanged
--   * contour rose de l'écran quand un panneau est ouvert hors du port sûr et qu'un non-équipier
--     capable de couper (pas en Mode Zen) approche à ≤ Balance.Render.TailWarnDistance de la file
--     (§13.2)
--   * flou d'arrière-plan : suit « Graphismes légers » en direct, même panneau ouvert
--   * propriétaire côté client du remote CrewInvitePrompt (→ Panels/Crew.showInvite, carte non
--     bloquante) et de l'ouverture de ReturnScreen sur Celebrate "offline" (ScreenFX.Celebrated
--     → Panels/ReturnScreen.present) ; ScreenFX.Celebrated est écouté dès Init : ScreenFX démarre
--     avant ce module et un signal (contrairement à un remote) n'est jamais mis en file
-- GDD : §10.3, §9.2 (ouverture/fermeture), §10.4, §13.2.
-- Dépendances : StateController, AudioController, Util/Prefs, UI/Root, UI/Theme, UI/Create, UI/Juice,
-- WorldStateController, CongaRenderer, ScreenFX, UI/Panels/*, Shared/Net, Shared/Util/Signal.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local WorldState = require(Client.Controllers.WorldStateController)
local CongaRenderer = require(Client.Controllers.CongaRenderer)
local ScreenFX = require(Client.UI.ScreenFX)
local Widgets = require(Client.UI.Panels.Widgets)

local PanelController = {}

-- Interface de chaque module de UI/Panels/*
export type Panel = {
	name: Types.PanelName,
	tabs: { string }?, -- clés de localisation des onglets
	build: (parent: Frame) -> (), -- construit une fois le contenu dans `parent`
	onOpen: (args: any?) -> (), -- à chaque ouverture (args : ex. { tab = "atlas", focus = "conga" })
	onClose: () -> (),
	hasAction: () -> boolean, -- pastille « ! » sur le rail
	selectTab: ((tab: string) -> ())?,
	-- Ajouts optionnels du paquet (le contrat permet d'ajouter, jamais de retirer)
	parent: Types.PanelName?, -- back() y revient (Supernova → Upgrades)
	compact: boolean?, -- fenêtre réduite (écran de retour)
	tabVisible: ((tab: string) -> boolean)?, -- onglet masqué (Accueil une fois la chaîne finie)
	step: ((dt: number) -> ())?, -- chaque image tant que le panneau est ouvert
	defaultSelection: (() -> GuiObject?)?, -- premier objet sélectionné à la manette
}

PanelController.Opened = Signal.new() :: Signal.Signal<Types.PanelName>
PanelController.Closed = Signal.new() :: Signal.Signal<Types.PanelName>
-- (panneau, a une action possible)
PanelController.BadgeChanged = Signal.new() :: Signal.Signal<Types.PanelName, boolean>

PanelController.NAMES = {
	"Upgrades",
	"Supernova",
	"Collection",
	"Goals",
	"Shop",
	"Crew",
	"Settings",
	"ReturnScreen",
} :: { Types.PanelName }

local VALID: { [string]: boolean } = {}
for _, name in PanelController.NAMES do
	VALID[name] = true
end

-- Mise en page et animations (GDD §10.3, §9.2)
local WINDOW_SCALE = Vector2.new(0.72, 0.86)
local WINDOW_MIN, WINDOW_MAX = Vector2.new(480, 320), Vector2.new(900, 600)
local COMPACT_SCALE = Vector2.new(0.5, 0.62)
local COMPACT_MIN, COMPACT_MAX = Vector2.new(420, 300), Vector2.new(620, 440)
local HEADER_HEIGHT, TAB_HEIGHT, CLOSE_SIZE, GAP = 64, 56, 64, 8
local OPEN_SCALE_FROM, OPEN_SCALE_TIME, OPEN_FADE_TIME = 0.85, 0.22, 0.15
local CLOSE_SCALE, CLOSE_TIME = 0.9, 0.12
local BLUR_SIZE, BLUR_TIME = 8, 0.2
local DIM_TRANSPARENCY = 0.6
local DISPLAY_ORDER = 30
local BADGE_INTERVAL = 1
local WARN_INTERVAL = 0.2
local WARN_ALPHA = 0.45 -- transparence la plus forte du contour rose
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 50
local ACTION_BACK, ACTION_PREV, ACTION_NEXT = "PanelBack", "PanelTabPrev", "PanelTabNext"
local STEP_WARN_EVERY = 10 -- s entre deux avertissements d'erreur d'un même panneau

type TabRef = { id: string, key: string, button: TextButton, label: TextLabel }

type Page = {
	name: string,
	panel: Panel,
	frame: Frame,
	title: TextLabel,
	back: TextButton,
	close: TextButton,
	tabs: { TabRef },
	body: Frame,
}

local window: CanvasGroup? = nil
local windowConstraint: UISizeConstraint? = nil
local dim: Frame? = nil
local blur: BlurEffect? = nil
local warnFrame: Frame? = nil
local warnEdges: { Frame } = {}
local panels: { [string]: Panel } = {}
local pages: { [string]: Page } = {}
local currentName: string? = nil
local currentTab: { [string]: string } = {}
local badges: { [string]: boolean } = {}
local badgesDirty = true
local tabsDirty = false
local closeToken = 0
local actionsBound = false
local warnOn = false
local warnClock = 0
local stepWarnedAt: { [string]: number } = {}
local started = false
local modulesLoaded = false -- Start a chargé les modules des panneaux (un seul fil)
local pendingReturn: { [string]: any }? = nil -- Celebrate "offline" reçu avant ce chargement

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function tabId(key: string): string
	return string.match(key, "([^%.]+)$") or key
end

-- Appel protégé d'une fonction de panneau (une erreur de panneau ne casse jamais la navigation)
local function safeCall(name: string, what: string, fn: any, ...: any): (boolean, any)
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(`[PanelController] {name}.{what} :`, result)
	end
	return ok, result
end

local function load(name: string): Panel?
	if not VALID[name] then
		return nil
	end
	local cached = panels[name]
	if cached then
		return cached
	end
	local folder = Client.UI:FindFirstChild("Panels")
	local moduleScript = folder and folder:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn("[PanelController] module de panneau introuvable :", name)
		return nil
	end
	local panel = (require :: any)(moduleScript) :: Panel
	panels[name] = panel
	return panel
end

local function lastInputIsGamepad(): boolean
	local ok, kind = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	return ok and typeof(kind) == "EnumItem" and string.sub(kind.Name, 1, 7) == "Gamepad"
end

-- ---------------------------------------------------------------------------------------------
-- Fenêtre et pages
-- ---------------------------------------------------------------------------------------------

local function buildWarning(parent: Instance): Frame
	local frame = Create("Frame", {
		Name = "TailWarning",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 50,
		Parent = parent,
	}) :: Frame
	local color = Cosmetics.Readability.Snippable
	-- 4 bords en dégradé (opaque au bord, transparent vers le centre)
	local edges = {
		{ "Top", UDim2.new(1, 0, 0.12, 0), UDim2.fromScale(0, 0), 90 },
		{ "Bottom", UDim2.new(1, 0, 0.12, 0), UDim2.fromScale(0, 0.88), 270 },
		{ "Left", UDim2.new(0.08, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ "Right", UDim2.new(0.08, 0, 1, 0), UDim2.fromScale(0.92, 0), 180 },
	}
	warnEdges = {}
	for _, e in edges do
		local edge = Create("Frame", {
			Name = e[1],
			Size = e[2],
			Position = e[3],
			BackgroundColor3 = color,
			BackgroundTransparency = WARN_ALPHA,
			BorderSizePixel = 0,
			ZIndex = 50,
			Parent = frame,
		}, {
			Create("UIGradient", {
				Rotation = e[4],
				Transparency = NumberSequence.new(0, 1),
			}),
		}) :: Frame
		table.insert(warnEdges, edge)
	end
	return frame
end

local function ensureWindow(): CanvasGroup
	if window and window.Parent then
		return window
	end
	local screen = Root.screen("Panels", DISPLAY_ORDER)
	local safe = Root.safe("Panels", DISPLAY_ORDER)
	dim = Create("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Visible = false,
		ZIndex = 0,
		Parent = screen,
	})
	warnFrame = buildWarning(screen)
	windowConstraint = Create("UISizeConstraint", { MinSize = WINDOW_MIN, MaxSize = WINDOW_MAX })
	local w = Create("CanvasGroup", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(WINDOW_SCALE.X, WINDOW_SCALE.Y),
		BackgroundColor3 = Theme.Colors.Panel,
		GroupTransparency = 0,
		Visible = false,
		SelectionGroup = true,
		ZIndex = 5,
		Parent = safe,
	}, {
		windowConstraint,
		Widgets.corner(UDim.new(0, 16)),
		Widgets.stroke(Theme.Colors.Stroke, 3),
		Widgets.gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 184, 220)),
		Widgets.padding(12),
	}) :: CanvasGroup
	Juice.scaleOf(w)
	window = w
	local existing = Lighting:FindFirstChild("PanelBlur")
	if existing and existing:IsA("BlurEffect") then
		blur = existing
	else
		blur = Create("BlurEffect", { Name = "PanelBlur", Size = 0, Enabled = true, Parent = Lighting })
	end
	return w
end

local function applyChrome(page: Page)
	page.title.Text = Prefs.t(`panel.{page.name}.title`)
	for _, tab in page.tabs do
		tab.label.Text = Prefs.t(tab.key)
	end
end

local function visibleTabs(page: Page): { TabRef }
	local out = {}
	for _, tab in page.tabs do
		local visible = true
		local fn = page.panel.tabVisible
		if fn then
			local ok, result = safeCall(page.name, "tabVisible", fn, tab.id)
			visible = not ok or result ~= false
		end
		if visible then
			table.insert(out, tab)
		end
	end
	return out
end

local function layoutTabs(page: Page)
	local shown = visibleTabs(page)
	local n = math.max(1, #shown)
	for _, tab in page.tabs do
		tab.button.Visible = false
	end
	for i, tab in shown do
		tab.button.Visible = true
		tab.button.LayoutOrder = i
		tab.button.Size = UDim2.new(1 / n, -GAP, 1, 0)
	end
end

local function paintTabs(page: Page)
	local selected = currentTab[page.name]
	for _, tab in page.tabs do
		local on = tab.id == selected
		Widgets.setColor(tab.button, if on then Theme.Colors.Primary else Widgets.CARD)
		Widgets.highlight(tab.button, on, Theme.Colors.Gold)
	end
end

local function selectTabInternal(name: string, id: string, userInitiated: boolean)
	local page = pages[name]
	if not page then
		return
	end
	local found = false
	for _, tab in visibleTabs(page) do
		if tab.id == id then
			found = true
		end
	end
	if not found then
		return
	end
	currentTab[name] = id
	paintTabs(page)
	if userInitiated then
		AudioController.play("Click")
	end
	safeCall(name, "selectTab", page.panel.selectTab, id)
end

local function ensurePage(name: string, panel: Panel): Page
	local existing = pages[name]
	if existing then
		return existing
	end
	local w = ensureWindow()
	local frame = Create("Frame", {
		Name = "Page_" .. name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = w,
	}) :: Frame
	local header = Create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		Parent = frame,
	})
	local back = Widgets.button({
		name = "Back",
		text = "‹",
		size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE),
		color = Widgets.CARD,
		maxText = 40,
		parent = header,
		onClick = function()
			PanelController.back()
		end,
	})
	back.Visible = panel.parent ~= nil
	local titleX = if panel.parent ~= nil then CLOSE_SIZE + GAP else 0
	local title = Widgets.label({
		name = "Title",
		size = UDim2.new(1, -(titleX + CLOSE_SIZE + GAP), 1, -8),
		position = UDim2.new(0, titleX, 0, 4),
		font = Widgets.STAMP_FONT,
		maxSize = 40,
		xAlign = Enum.TextXAlignment.Left,
		parent = header,
	})
	local close = Widgets.button({
		name = "Close",
		text = "✕",
		size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.Danger,
		maxText = 32,
		parent = header,
		onClick = function()
			PanelController.close()
		end,
	})
	local tabs: { TabRef } = {}
	local bodyTop = HEADER_HEIGHT + GAP
	if panel.tabs and #panel.tabs > 0 then
		local bar = Create("Frame", {
			Name = "Tabs",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, bodyTop),
			Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
			Parent = frame,
		}, {
			Widgets.listLayout(Enum.FillDirection.Horizontal, GAP, Enum.HorizontalAlignment.Center),
		})
		for i, key in panel.tabs do
			local id = tabId(key)
			local button, label = Widgets.button({
				name = "Tab_" .. id,
				size = UDim2.new(1 / #panel.tabs, -GAP, 1, 0),
				color = Widgets.CARD,
				order = i,
				maxText = 22,
				parent = bar,
				sound = "",
				onClick = function()
					selectTabInternal(name, id, true)
				end,
			})
			table.insert(tabs, { id = id, key = key, button = button, label = label })
		end
		bodyTop += TAB_HEIGHT + GAP
	end
	local body = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, bodyTop),
		Size = UDim2.new(1, 0, 1, -bodyTop),
		Parent = frame,
	}) :: Frame
	local page: Page = {
		name = name,
		panel = panel,
		frame = frame,
		title = title,
		back = back,
		close = close,
		tabs = tabs,
		body = body,
	}
	pages[name] = page
	applyChrome(page)
	layoutTabs(page)
	safeCall(name, "build", panel.build, body)
	return page
end

-- Onglet à montrer à l'ouverture : args.tab s'il est visible, sinon le dernier, sinon le premier
local function chooseTab(page: Page, args: any?): string?
	local shown = visibleTabs(page)
	if #shown == 0 then
		return nil
	end
	local wanted: string? = nil
	if type(args) == "table" and type(args.tab) == "string" then
		wanted = tabId(args.tab)
	end
	for _, candidate in { wanted, currentTab[page.name] } do
		for _, tab in shown do
			if tab.id == candidate then
				return tab.id
			end
		end
	end
	return shown[1].id
end

local function defaultSelection(page: Page): GuiObject?
	local fn = page.panel.defaultSelection
	if fn then
		local ok, result = safeCall(page.name, "defaultSelection", fn)
		if ok and typeof(result) == "Instance" and (result :: Instance):IsA("GuiObject") then
			return result :: GuiObject
		end
	end
	for _, tab in visibleTabs(page) do
		return tab.button
	end
	return page.close
end

local function selectDefault(page: Page)
	if lastInputIsGamepad() then
		GuiService.SelectedObject = defaultSelection(page)
	end
end

local function clearSelection()
	local w = window
	local selected = GuiService.SelectedObject
	if w and selected and selected:IsDescendantOf(w) then
		GuiService.SelectedObject = nil
	end
end

-- ---------------------------------------------------------------------------------------------
-- Animations
-- ---------------------------------------------------------------------------------------------

local function setWindowSize(compact: boolean)
	local w = window
	local constraint = windowConstraint
	if not w or not constraint then
		return
	end
	local scale = if compact then COMPACT_SCALE else WINDOW_SCALE
	w.Size = UDim2.fromScale(scale.X, scale.Y)
	constraint.MinSize = if compact then COMPACT_MIN else WINDOW_MIN
	constraint.MaxSize = if compact then COMPACT_MAX else WINDOW_MAX
end

local function animateOpen(fresh: boolean)
	local w = window
	if not w then
		return
	end
	w.Visible = true
	local scale = Juice.scaleOf(w)
	if Juice.reducedMotion() then
		-- Mouvement réduit : fondu seulement
		scale.Scale = 1
		if fresh then
			w.GroupTransparency = 1
			Juice.tween(w, OPEN_FADE_TIME, { GroupTransparency = 0 })
		else
			w.GroupTransparency = 0
		end
	else
		scale.Scale = OPEN_SCALE_FROM
		Juice.tween(scale, OPEN_SCALE_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if fresh then
			w.GroupTransparency = 1
		end
		Juice.tween(w, OPEN_FADE_TIME, { GroupTransparency = 0 })
	end
	local d = dim
	if d then
		d.Visible = true
		Juice.tween(d, OPEN_FADE_TIME, { BackgroundTransparency = DIM_TRANSPARENCY })
	end
	local b = blur
	if b then
		local target = if Prefs.lowGraphics() then 0 else BLUR_SIZE
		Juice.tween(b, BLUR_TIME, { Size = target })
	end
	AudioController.play("Whoosh")
end

local function animateClose(name: string)
	local w = window
	if not w then
		return
	end
	closeToken += 1
	local token = closeToken
	local scale = Juice.scaleOf(w)
	if not Juice.reducedMotion() then
		Juice.tween(
			scale,
			CLOSE_TIME,
			{ Scale = CLOSE_SCALE },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
	end
	Juice.tween(w, CLOSE_TIME, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local d = dim
	if d then
		Juice.tween(d, CLOSE_TIME, { BackgroundTransparency = 1 })
	end
	local b = blur
	if b then
		Juice.tween(b, CLOSE_TIME, { Size = 0 })
	end
	task.delay(CLOSE_TIME, function()
		if token ~= closeToken or currentName ~= nil then
			return
		end
		w.Visible = false
		scale.Scale = 1
		if d then
			d.Visible = false
		end
		local page = pages[name]
		if page then
			page.frame.Visible = false
		end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Manette / clavier (actions liées seulement quand un panneau est ouvert)
-- ---------------------------------------------------------------------------------------------

local function onAction(
	actionName: string,
	inputState: Enum.UserInputState,
	_input: any
): Enum.ContextActionResult
	if currentName == nil then
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		if actionName == ACTION_BACK then
			PanelController.back()
		elseif actionName == ACTION_PREV then
			PanelController.nextTab(-1)
		elseif actionName == ACTION_NEXT then
			PanelController.nextTab(1)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function bindActions()
	if actionsBound then
		return
	end
	actionsBound = true
	ContextActionService:BindActionAtPriority(
		ACTION_BACK,
		onAction,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Escape
	)
	ContextActionService:BindActionAtPriority(
		ACTION_PREV,
		onAction,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.ButtonL1
	)
	ContextActionService:BindActionAtPriority(
		ACTION_NEXT,
		onAction,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.ButtonR1
	)
end

local function unbindActions()
	if not actionsBound then
		return
	end
	actionsBound = false
	ContextActionService:UnbindAction(ACTION_BACK)
	ContextActionService:UnbindAction(ACTION_PREV)
	ContextActionService:UnbindAction(ACTION_NEXT)
end

-- ---------------------------------------------------------------------------------------------
-- API publique
-- ---------------------------------------------------------------------------------------------

local function hidePage(name: string)
	local page = pages[name]
	if page then
		page.frame.Visible = false
		safeCall(name, "onClose", page.panel.onClose)
	end
	PanelController.Closed:Fire(name :: Types.PanelName)
end

function PanelController.open(name: Types.PanelName, args: any?)
	if type(name) ~= "string" or not VALID[name] then
		warn("[PanelController] panneau inconnu :", name)
		return
	end
	local panel = load(name)
	if not panel then
		return
	end
	local page = ensurePage(name, panel)
	local previous = currentName
	if previous == name then
		-- déjà ouvert : ré-applique les arguments (onglet, focus d'accueil)
		safeCall(name, "onOpen", panel.onOpen, args)
		local tab = chooseTab(page, args)
		if tab then
			selectTabInternal(name, tab, false)
		end
		return
	end
	if previous then
		hidePage(previous)
	end
	closeToken += 1 -- annule une fermeture en cours
	currentName = name
	for other, otherPage in pages do
		if other ~= name then
			otherPage.frame.Visible = false
		end
	end
	setWindowSize(panel.compact == true)
	layoutTabs(page)
	page.frame.Visible = true
	safeCall(name, "onOpen", panel.onOpen, args)
	local tab = chooseTab(page, args)
	if tab then
		selectTabInternal(name, tab, false)
	end
	animateOpen(previous == nil)
	bindActions()
	selectDefault(page)
	PanelController.Opened:Fire(name)
end

function PanelController.close()
	local name = currentName
	if name == nil then
		return
	end
	currentName = nil
	unbindActions()
	clearSelection()
	local page = pages[name]
	if page then
		safeCall(name, "onClose", page.panel.onClose)
	end
	animateClose(name)
	if warnOn then
		warnOn = false
		if warnFrame then
			warnFrame.Visible = false
		end
	end
	PanelController.Closed:Fire(name :: Types.PanelName)
end

function PanelController.back()
	local name = currentName
	if name == nil then
		return
	end
	local panel = panels[name]
	local parent = panel and panel.parent
	if parent and VALID[parent] then
		PanelController.open(parent)
	else
		PanelController.close()
	end
end

function PanelController.toggle(name: Types.PanelName)
	if currentName == name then
		PanelController.close()
	else
		PanelController.open(name)
	end
end

function PanelController.current(): Types.PanelName?
	return currentName :: Types.PanelName?
end

function PanelController.hasAction(name: Types.PanelName): boolean
	if type(name) ~= "string" or not VALID[name] then
		return false
	end
	local panel = load(name)
	if not panel then
		return false
	end
	local ok, result = safeCall(name, "hasAction", panel.hasAction)
	return ok and result == true
end

-- Onglet suivant / précédent du panneau ouvert (LB/RB)
function PanelController.nextTab(direction: number)
	local name = currentName
	if name == nil or type(direction) ~= "number" or direction ~= direction or direction == 0 then
		return
	end
	local page = pages[name]
	if not page then
		return
	end
	local shown = visibleTabs(page)
	if #shown < 2 then
		return
	end
	local index = 1
	for i, tab in shown do
		if tab.id == currentTab[name] then
			index = i
		end
	end
	local step = if direction > 0 then 1 else -1
	local nextIndex = (index - 1 + step) % #shown + 1
	selectTabInternal(name, shown[nextIndex].id, true)
	if lastInputIsGamepad() then
		GuiService.SelectedObject = shown[nextIndex].button
	end
end

-- Onglet affiché d'un panneau (nil si le panneau n'a pas d'onglets ou n'a jamais été ouvert)
function PanelController.currentTab(name: Types.PanelName): string?
	return currentTab[name]
end

-- Contenu construit d'un panneau (tests, ancrage de l'accueil) ; nil s'il n'est pas construit
function PanelController.page(name: Types.PanelName): Frame?
	local page = pages[name]
	return if page then page.frame else nil
end

-- Demande de réévaluer les onglets visibles et les pastilles (appelé par les panneaux)
function PanelController.invalidate()
	tabsDirty = true
	badgesDirty = true
end

-- ---------------------------------------------------------------------------------------------
-- Pastilles, contour rose, pas des panneaux
-- ---------------------------------------------------------------------------------------------

local function refreshBadges()
	badgesDirty = false
	if not State.ready then
		return
	end
	for _, name in PanelController.NAMES do
		local value = PanelController.hasAction(name)
		if badges[name] ~= value then
			badges[name] = value
			PanelController.BadgeChanged:Fire(name, value)
		end
	end
end

-- Un non-équipier approche-t-il de la file locale hors du port sûr ? (§13.2)
local function tailThreatened(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local slot = player:GetAttribute("Slot")
	if type(slot) ~= "number" or slot < 1 then
		return false
	end
	-- ni Zen, ni bouclier débutant : personne ne peut couper la file
	if player:GetAttribute("Zen") == true or player:GetAttribute("Rookie") == true then
		return false
	end
	local events = WorldState.events()
	if events and (events.snipsDisabled or (events.beacon and events.beacon.phase == "active")) then
		return false
	end
	local pos = root.Position
	if WorldLayout.inOwnHarbor(slot, pos) or WorldState.lineLength(slot) <= 0 then
		return false
	end
	local okNodes, nodes = pcall(CongaRenderer.nodePositions, slot)
	local points: { Vector3 } = if okNodes and type(nodes) == "table" and #nodes > 0 then nodes else { pos }
	local range = Balance.Render.TailWarnDistance
	for _, other in Players:GetPlayers() do
		-- un équipier ou un joueur en Mode Zen ne peut pas couper (§4.16, §6.1)
		if
			other ~= player
			and other:GetAttribute("Zen") ~= true
			and not WorldState.isCrewmate(other.UserId)
		then
			local otherChar = other.Character
			local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				local op = otherRoot.Position
				for _, point in points do
					local dx, dz = point.X - op.X, point.Z - op.Z
					if dx * dx + dz * dz <= range * range then
						return true
					end
				end
			end
		end
	end
	return false
end

local function setWarning(on: boolean)
	local frame = warnFrame
	if not frame or warnOn == on then
		return
	end
	warnOn = on
	frame.Visible = on
	warnClock = 0
end

local function pulseWarning(dt: number)
	local frame = warnFrame
	if not frame or not warnOn then
		return
	end
	warnClock += dt
	-- pulsation douce à 1 Hz (aucun flash > 3 Hz, §13.2) ; fixe en Mouvement réduit
	local alpha = if Juice.reducedMotion()
		then WARN_ALPHA
		else WARN_ALPHA + (1 - WARN_ALPHA) * 0.5 * (1 - math.cos(warnClock * math.pi * 2))
	for _, edge in warnEdges do
		edge.BackgroundTransparency = alpha
	end
end

local badgeAcc, warnAcc = 0, 0
local function onHeartbeat(dt: number)
	badgeAcc += dt
	if badgesDirty or badgeAcc >= BADGE_INTERVAL then
		badgeAcc = 0
		refreshBadges()
	end
	local name = currentName
	if name == nil then
		return
	end
	local page = pages[name]
	if page and tabsDirty then
		tabsDirty = false
		layoutTabs(page)
		local shown = visibleTabs(page)
		local still = false
		for _, tab in shown do
			if tab.id == currentTab[name] then
				still = true
			end
		end
		if not still and shown[1] then
			selectTabInternal(name, shown[1].id, false)
		end
	end
	local panel = panels[name]
	if panel and panel.step then
		local ok, err = pcall(panel.step, dt)
		if not ok then
			local now = os.clock()
			if now - (stepWarnedAt[name] or -math.huge) >= STEP_WARN_EVERY then
				stepWarnedAt[name] = now
				warn(`[PanelController] {name}.step :`, err)
			end
		end
	end
	warnAcc += dt
	if warnAcc >= WARN_INTERVAL then
		warnAcc = 0
		local ok, threatened = pcall(tailThreatened)
		setWarning(ok and threatened == true)
	end
	pulseWarning(dt)
end

-- ---------------------------------------------------------------------------------------------
-- Remotes et signaux possédés
-- ---------------------------------------------------------------------------------------------

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function onInvitePrompt(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local inviterId, expiresAt = payload.inviterId, payload.expiresAt
	if not isFinite(inviterId) or inviterId % 1 ~= 0 or inviterId <= 0 or not isFinite(expiresAt) then
		return
	end
	if Prefs.get("refuseInvites") == true then
		return
	end
	local crew = load("Crew") :: any
	if crew and type(crew.showInvite) == "function" then
		safeCall("Crew", "showInvite", crew.showInvite, { inviterId = inviterId, expiresAt = expiresAt })
	end
end

local function onCelebrated(payload: any)
	if type(payload) ~= "table" or payload.kind ~= "offline" or type(payload.data) ~= "table" then
		return
	end
	if not modulesLoaded then
		-- pas de require depuis le fil d'un signal : Start présentera l'écran après le chargement
		pendingReturn = payload.data
		return
	end
	local screen = load("ReturnScreen") :: any
	if screen and type(screen.present) == "function" then
		safeCall("ReturnScreen", "present", screen.present, payload.data)
	end
end

local celebratedConn: Signal.Connection? = nil

function PanelController.Init()
	badges = {}
	badgesDirty = true
	-- ScreenFX (démarré avant) peut émettre Celebrate "offline" avant notre Start
	if celebratedConn == nil then
		celebratedConn = ScreenFX.Celebrated:Connect(onCelebrated)
	end
end

-- Graphismes légers changé : le flou suit tout de suite (panneau ouvert ou non)
local function onPrefChanged(key: string)
	if key ~= "lowGraphics" then
		return
	end
	local b = blur
	if b == nil then
		return
	end
	local target = if currentName ~= nil and not Prefs.lowGraphics() then BLUR_SIZE else 0
	Juice.tween(b, BLUR_TIME, { Size = target })
end

function PanelController.Start()
	if started then
		return
	end
	started = true
	-- les modules (pas leur interface) sont chargés ici, depuis un seul fil : hasAction, les
	-- remotes et les signaux n'ont jamais à faire un require concurrent
	for _, name in PanelController.NAMES do
		load(name)
	end
	modulesLoaded = true
	ensureWindow()
	State.Changed:Connect(function()
		badgesDirty = true
		tabsDirty = true
	end)
	State.ReadySignal:Connect(function()
		badgesDirty = true
	end)
	Prefs.LanguageChanged:Connect(function()
		for _, page in pages do
			applyChrome(page)
		end
	end)
	if celebratedConn == nil then
		celebratedConn = ScreenFX.Celebrated:Connect(onCelebrated)
	end
	Prefs.Changed:Connect(onPrefChanged)
	Net.event("CrewInvitePrompt").OnClientEvent:Connect(onInvitePrompt)
	pcall(function()
		UserInputService.LastInputTypeChanged:Connect(function()
			local name = currentName
			local page = name and pages[name]
			if page and lastInputIsGamepad() and GuiService.SelectedObject == nil then
				GuiService.SelectedObject = defaultSelection(page)
			end
		end)
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	local early = pendingReturn
	if early then
		pendingReturn = nil
		onCelebrated({ kind = "offline", data = early })
	end
end

-- Exposé pour les tests
PanelController._tailThreatened = tailThreatened
PanelController._refreshBadges = refreshBadges
PanelController._onInvitePrompt = onInvitePrompt
PanelController._onCelebrated = onCelebrated

return PanelController
