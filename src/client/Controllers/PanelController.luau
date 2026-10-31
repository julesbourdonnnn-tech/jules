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
--   * console PS5 (docs/07-console-ps5.md §6.3, §7, §9) :
--       - fenêtre en SelectionGroup fermé (SelectionBehavior* = Stop) : la sélection ne s'échappe
--         jamais vers le HUD derrière ; après un changement d'onglet ou de contenu (achat, fusion,
--         liste reconstruite), une sélection masquée ou détruite revient à la sélection par défaut
--       - sélection effacée (pavé tactile / Créer, menu du système refermé) : rendue à l'image
--         suivante ; vide seulement tant qu'une fenêtre Roblox tient la manette (achat ouvert par ✕,
--         PanelController.holdSelection, menu du système) ; croix ↑ / ↓ / → sans sélection
--         absorbées (PanelNavGuard) : ni roue de pings, ni minicarte, ni ACCLAMER derrière la fenêtre
--       - ○ (Retour) recule d'un niveau (Supernova → Améliorer → bouton d'origine hors fenêtre,
--         ex. le bouton du rail, rendu à la manette s'il est encore affiché) avec le son « Back »
--       - L1 / R1 : onglets en boucle (son « Tab ») ; L2 / R2 : panneau précédent / suivant en boucle
--         (Améliorer, Collection, Objectifs, Boutique, Équipage, Réglages ; Supernova compte comme
--         Améliorer ; garde du HUD : PanelController.allowed), absorbés : R2 ne Dash pas
--       - stick droit (Thumbstick2, absorbé, zone morte 0,2) : fait défiler la liste qui contient la
--         sélection, sinon la liste principale du panneau (la caméra ne tourne pas derrière)
--       - croix ↑ / ↓ sans changement de sélection (rien de sélectionnable de ce côté : lignes en
--         lecture seule de l'Atlas, du Guide, aperçu de la Supernova) : la liste défile de 70 % de sa
--         hauteur visible ; au vrai bout de liste ou au bord de la fenêtre (← / →) : son « Bump » et
--         vibration « listEnd »
--       - repères (UI/Glyph, icônes PlayStation sur PS5) : ○ « PadGlyph » sur Retour, ou sur Fermer
--         sans Retour (△, tout fermer, sur Fermer de la Supernova) à la place des « ‹ » / « ✕ »
--         dessinés ; L1 / R1 aux bouts de la barre d'onglets (≥ 2 onglets) ; L2 / R2 aux coins de
--         l'en-tête ; focusTarget() : bouton Accepter de la carte d'invitation d'équipage
--   * pastilles « ! » : hasAction() de chaque panneau (sans le construire), réévalué à chaque
--     changement du profil et chaque seconde (Glow prédit, minuit UTC) → BadgeChanged
--   * contour rose de l'écran quand un panneau est ouvert hors du port sûr et qu'un non-équipier
--     capable de couper (pas en Mode Zen) approche à ≤ Balance.Render.TailWarnDistance de la queue
--     coupable (nœuds au-delà des Guard Links) ; jamais pendant la trêve de la Balise (« active » et
--     « success »), les coupes désactivées ni l'immunité de la victime (ImmuneUntil) : mêmes règles
--     que le serveur et que CongaRenderer (§13.2, GDD §4.7, §6.4)
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
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Console = require(Shared.Config.Console)
local Cosmetics = require(Shared.Config.Cosmetics)
local Formulas = require(Shared.Logic.Formulas)
local Clock = require(Shared.Util.Clock)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Haptics = require(Client.Util.Haptics)
local Platform = require(Client.Util.Platform)
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Glyph = require(Client.UI.Glyph)
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
local ACTION_CYCLE_PREV, ACTION_CYCLE_NEXT = "PanelPrev", "PanelNext" -- L2 / R2
local ACTION_SCROLL = "PanelScroll" -- stick droit
-- croix ↑ / ↓ / → sans sélection : jamais la roue de pings, la minicarte ni ACCLAMER derrière la
-- fenêtre (← : le suivi de quête d'InputController s'efface déjà, panneau ouvert)
local ACTION_NAV_GUARD = "PanelNavGuard"
-- s : sélection effacée au plus tant après ✕ sur un objet de la fenêtre = fenêtre Roblox ouverte
-- par ce bouton (achat : les infos du produit arrivent avant que la fenêtre prenne la manette)
local PROMPT_HOLD_WINDOW = 3
-- Panneaux parcourus par L2 / R2 (docs/07 §6.3) ; Supernova compte comme Améliorer
local CYCLE: { Types.PanelName } = { "Upgrades", "Collection", "Goals", "Shop", "Crew", "Settings" }
local CYCLE_ALIAS: { [string]: Types.PanelName } = { Supernova = "Upgrades" }
local STICK_DEADZONE = 0.2
local SCROLL_SPEED = 1.6 -- hauteurs de liste par seconde, stick au fond
local SCROLL_MIN_SPEED = 240 -- px / s au moins (petites listes)
local CLOSE_GLYPH = 44 -- ○ / △ dans les boutons Fermer / Retour (px de référence)
local EDGE_GLYPH = Console.GlyphSize -- L1 / R1 / L2 / R2
local BUMP_FRAMES = 2 -- images sans changement de sélection après une croix : bout de liste
local NUDGE_FRACTION = 0.7 -- ↑ / ↓ sans rien à sélectionner : défilement (part de la hauteur visible)
local NAV_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.DPadUp] = true,
	[Enum.KeyCode.DPadDown] = true,
	[Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.DPadRight] = true,
}
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
	-- manette (docs/07 §7)
	backLabel: TextLabel,
	closeLabel: TextLabel,
	tabBar: Frame?,
	tabTop: number,
	l1: Glyph.Handle?,
	r1: Glyph.Handle?,
	l2: Glyph.Handle,
	r2: Glyph.Handle,
	chrome: string?, -- signature de la dernière mise en page de l'en-tête
}

-- Croix pressée dans la fenêtre : sélection à cet instant (bout de liste si elle ne change pas) ;
-- `dir` : 1 pour ↓, -1 pour ↑, 0 pour ← / →
type BumpProbe = { frame: number, object: GuiObject, canvas: Vector2?, changed: boolean, dir: number }

local window: CanvasGroup? = nil
local windowConstraint: UISizeConstraint? = nil
local dim: Frame? = nil
local blur: BlurEffect? = nil
local warnFrame: Frame? = nil
local warnEdges: { Frame } = {}
local panels: { [string]: Panel } = {}
local pages: { [string]: Page } = {}
local currentName: string? = nil
local panelGate: ((Types.PanelName) -> boolean)? = nil
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
-- manette
local origin: GuiObject? = nil -- sélection hors fenêtre à l'ouverture (bouton du rail), rendue par ○
local opener: GuiObject? = nil -- bouton du panneau parent qui a ouvert le panneau courant
local lastInWindow: GuiObject? = nil -- dernière sélection valide dans la fenêtre
local stick = Vector2.zero -- stick droit (zone morte appliquée)
local scrollCache: { key: string, frame: ScrollingFrame? }? = nil
local frameNo = 0
local selectionChangedAt = -1
local bump: BumpProbe? = nil
-- Sélection laissée vide pendant qu'une fenêtre Roblox tient la manette (docs/07 §6.6, §7) :
-- `heldByPanel` (PanelController.holdSelection, ex. Panels/Shop pendant la fenêtre d'achat),
-- `heldByPrompt` (sélection effacée juste après ✕ sur `confirmTarget`, à `confirmAt`), menu du système
local uiTime = 0 -- s : somme des dt (mesure de l'interface)
local heldByPanel = false
local heldByPrompt = false
local confirmAt = -math.huge
local confirmTarget: GuiObject? = nil

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

-- La manette est-elle l'entrée du joueur ? (entrée préférée, docs/07 §2, ou dernière entrée)
local function gamepadActive(): boolean
	return Platform.usingGamepad() or lastInputIsGamepad()
end

-- Affiché à l'écran : lui et ses ancêtres visibles, dans un ScreenGui activé et parenté
local function shownOnScreen(obj: Instance?): boolean
	local cur = obj
	while cur ~= nil do
		if cur:IsA("GuiObject") then
			if not (cur :: GuiObject).Visible then
				return false
			end
		elseif cur:IsA("LayerCollector") then
			return (cur :: LayerCollector).Enabled and cur.Parent ~= nil
		end
		cur = cur.Parent
	end
	return false
end

-- Objet que la manette peut sélectionner (sélectionnable et affiché)
local function selectable(obj: Instance?): boolean
	return obj ~= nil and obj:IsA("GuiObject") and (obj :: GuiObject).Selectable and shownOnScreen(obj)
end

-- Sélectionnable et dans la fenêtre des panneaux
local function inWindow(obj: Instance?): boolean
	local w = window
	return obj ~= nil and w ~= nil and obj:IsDescendantOf(w) and selectable(obj)
end

-- Menu du système Roblox ouvert (il tient la manette)
local function systemMenuOpen(): boolean
	local ok, open = pcall(function()
		return GuiService.MenuIsOpen
	end)
	return ok and open == true
end

-- Une fenêtre Roblox tient-elle la manette ? (achat, menu du système) : une sélection effacée reste
-- alors vide, la reposer volerait la manette à cette fenêtre
local function selectionHeld(): boolean
	return heldByPanel or heldByPrompt or systemMenuOpen()
end

-- La fenêtre Roblox est refermée (fin d'achat, sélection posée, panneau fermé)
local function releaseHold()
	heldByPanel = false
	heldByPrompt = false
	confirmTarget = nil
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
		-- fenêtre modale : la sélection manette n'en sort jamais (docs/07 §7)
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
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

-- Nom du panneau dans le cycle L2 / R2 (Supernova → Améliorer), nil hors cycle
local function cycleName(name: string?): Types.PanelName?
	if name == nil then
		return nil
	end
	local alias: string = CYCLE_ALIAS[name] or name
	return if table.find(CYCLE, alias :: Types.PanelName) then alias :: Types.PanelName else nil
end

-- L2 / R2 mènent-ils quelque part depuis ce panneau ? (un autre panneau du cycle autorisé)
local function canCycle(name: string): boolean
	local own = cycleName(name)
	if own == nil then
		return false
	end
	for _, other in CYCLE do
		if other ~= own and PanelController.allowed(other) then
			return true
		end
	end
	return false
end

-- En-tête à la manette (docs/07 §7) : ○ (ou △) à la place des « ‹ » / « ✕ » dessinés, L2 / R2 aux
-- coins de l'en-tête, L1 / R1 aux bouts de la barre d'onglets ; refait seulement s'il a changé
local function layoutChrome(page: Page, force: boolean?)
	local pad = Platform.usingGamepad()
	local cycle = pad and canCycle(page.name)
	local edges = pad and page.tabBar ~= nil and #visibleTabs(page) >= 2
	local signature = `{pad}|{cycle}|{edges}|{page.back.Visible}`
	if signature == page.chrome and not force then
		return
	end
	page.chrome = signature
	page.backLabel.Visible = not pad
	page.closeLabel.Visible = not pad
	page.l2:set(if cycle then { gamepad = Enum.KeyCode.ButtonL2 } else {})
	page.r2:set(if cycle then { gamepad = Enum.KeyCode.ButtonR2 } else {})
	local left = if page.back.Visible then CLOSE_SIZE + GAP else 0
	page.l2.frame.Position = UDim2.new(0, left, 0.5, 0)
	if cycle then
		left += EDGE_GLYPH + GAP
	end
	local right = CLOSE_SIZE + GAP + (if cycle then EDGE_GLYPH + GAP else 0)
	page.title.Position = UDim2.new(0, left, 0, 4)
	page.title.Size = UDim2.new(1, -(left + right), 1, -8)
	local bar = page.tabBar
	if bar then
		local l1, r1 = page.l1, page.r1
		if l1 and r1 then
			l1:set(if edges then { gamepad = Enum.KeyCode.ButtonL1 } else {})
			r1:set(if edges then { gamepad = Enum.KeyCode.ButtonR1 } else {})
		end
		local inset = if edges then EDGE_GLYPH + GAP else 0
		bar.Position = UDim2.fromOffset(inset, page.tabTop)
		bar.Size = UDim2.new(1, -2 * inset, 0, TAB_HEIGHT)
	end
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
	layoutChrome(page)
end

local function paintTabs(page: Page)
	local selected = currentTab[page.name]
	for _, tab in page.tabs do
		local on = tab.id == selected
		Widgets.setColor(tab.button, if on then Theme.Colors.Primary else Widgets.CARD)
		Widgets.highlight(tab.button, on, Theme.Colors.Gold)
	end
end

-- (défini plus bas) remet une sélection manette valide dans la fenêtre
local ensureSelection: () -> ()

-- `sound` : son de l'action (« Click » au toucher, « Tab » à L1 / R1), nil à l'ouverture
local function selectTabInternal(name: string, id: string, sound: string?)
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
	if sound then
		AudioController.play(sound)
	end
	safeCall(name, "selectTab", page.panel.selectTab, id)
	-- contenu changé : la liste à faire défiler et la sélection manette sont réévaluées
	scrollCache = nil
	if currentName == name then
		ensureSelection()
	end
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
	local back, backLabel = Widgets.button({
		name = "Back",
		text = "‹",
		size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE),
		color = Widgets.CARD,
		maxText = 40,
		parent = header,
		sound = "", -- back() joue « Back »
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
	local close, closeLabel = Widgets.button({
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
	-- manette : ○ (retour d'un niveau) sur Retour, ou sur Fermer quand il n'y a pas de Retour ;
	-- Fermer d'un sous-panneau (Supernova) : △, qui ferme tout (docs/07 §6.3)
	Glyph.new(back, { gamepad = Enum.KeyCode.ButtonB }, {
		name = "PadGlyph",
		size = CLOSE_GLYPH,
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	Glyph.new(close, {
		gamepad = if panel.parent ~= nil then Enum.KeyCode.ButtonY else Enum.KeyCode.ButtonB,
	}, {
		name = "PadGlyph",
		size = CLOSE_GLYPH,
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	-- L2 / R2 aux coins de l'en-tête (affichés par layoutChrome)
	local l2 = Glyph.new(header, {}, {
		name = "PadL2",
		size = EDGE_GLYPH,
		position = UDim2.new(0, 0, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
	})
	local r2 = Glyph.new(header, {}, {
		name = "PadR2",
		size = EDGE_GLYPH,
		position = UDim2.new(1, -(CLOSE_SIZE + GAP), 0.5, 0),
		anchor = Vector2.new(1, 0.5),
	})
	local tabs: { TabRef } = {}
	local bodyTop = HEADER_HEIGHT + GAP
	local tabBar: Frame? = nil
	local tabTop = bodyTop
	local l1: Glyph.Handle? = nil
	local r1: Glyph.Handle? = nil
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
					selectTabInternal(name, id, "Click")
				end,
			})
			table.insert(tabs, { id = id, key = key, button = button, label = label })
		end
		tabBar = bar
		-- L1 / R1 aux deux bouts de la barre d'onglets (affichés par layoutChrome)
		l1 = Glyph.new(frame, {}, {
			name = "PadL1",
			size = EDGE_GLYPH,
			position = UDim2.fromOffset(0, bodyTop + TAB_HEIGHT / 2),
			anchor = Vector2.new(0, 0.5),
		})
		r1 = Glyph.new(frame, {}, {
			name = "PadR1",
			size = EDGE_GLYPH,
			position = UDim2.new(1, 0, 0, bodyTop + TAB_HEIGHT / 2),
			anchor = Vector2.new(1, 0.5),
		})
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
		backLabel = backLabel,
		closeLabel = closeLabel,
		tabBar = tabBar,
		tabTop = tabTop,
		l1 = l1,
		r1 = r1,
		l2 = l2,
		r2 = r2,
		chrome = nil,
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

-- Bouton de l'onglet affiché du panneau (nil sans onglets ou si l'onglet n'est plus visible)
local function currentTabButton(page: Page, shown: { TabRef }): TextButton?
	local id = currentTab[page.name]
	for _, tab in shown do
		if tab.id == id then
			return tab.button
		end
	end
	return nil
end

-- Sélection par défaut du panneau, seulement si elle est affichée dans la fenêtre (jamais un objet
-- masqué ou d'un autre onglet) ; sinon le bouton de l'onglet AFFICHÉ (pas le premier onglet : un
-- second ✕ basculerait d'onglet par surprise, ex. Calendrier réclamé → Aujourd'hui), puis le premier
-- onglet visible, sinon Fermer
local function defaultSelection(page: Page): GuiObject?
	local fn = page.panel.defaultSelection
	local candidate: GuiObject? = nil
	if fn then
		local ok, result = safeCall(page.name, "defaultSelection", fn)
		if ok and typeof(result) == "Instance" and (result :: Instance):IsA("GuiObject") then
			candidate = result :: GuiObject
		end
	end
	if candidate and inWindow(candidate) then
		return candidate
	end
	local shown = visibleTabs(page)
	local own = currentTabButton(page, shown)
	if own and inWindow(own) then
		return own
	end
	for _, tab in shown do
		if inWindow(tab.button) then
			return tab.button
		end
	end
	if inWindow(page.close) then
		return page.close
	end
	-- fenêtre pas encore affichée
	if candidate then
		return candidate
	end
	if own then
		return own
	end
	for _, tab in shown do
		return tab.button
	end
	return page.close
end

local function selectDefault(page: Page)
	if gamepadActive() then
		local target = defaultSelection(page)
		GuiService.SelectedObject = target
		lastInWindow = target
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

-- `quiet` : pas de « Whoosh » (changement de panneau à L2 / R2 : son « Tab »)
local function animateOpen(fresh: boolean, quiet: boolean?)
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
	if not quiet then
		AudioController.play("Whoosh")
	end
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

-- Stick droit : position après zone morte (0 sous STICK_DEADZONE, puis remise à l'échelle 0-1)
local function readStick(inputState: Enum.UserInputState, input: any): Vector2
	if inputState ~= Enum.UserInputState.Begin and inputState ~= Enum.UserInputState.Change then
		return Vector2.zero
	end
	local position = if input ~= nil then input.Position else nil
	if typeof(position) ~= "Vector3" then
		return Vector2.zero
	end
	local v = Vector2.new(position.X, position.Y)
	local magnitude = v.Magnitude
	if magnitude ~= magnitude or magnitude <= STICK_DEADZONE then
		return Vector2.zero
	end
	local strength = math.min(1, (magnitude - STICK_DEADZONE) / (1 - STICK_DEADZONE))
	return v.Unit * strength
end

local function onAction(
	actionName: string,
	inputState: Enum.UserInputState,
	input: any
): Enum.ContextActionResult
	if currentName == nil then
		return Enum.ContextActionResult.Pass
	end
	if actionName == ACTION_SCROLL then
		stick = readStick(inputState, input)
		return Enum.ContextActionResult.Sink
	end
	if actionName == ACTION_NAV_GUARD then
		-- avec une sélection, la croix navigue dans la fenêtre (le moteur la traite avant)
		if GuiService.SelectedObject ~= nil then
			return Enum.ContextActionResult.Pass
		end
		-- sans sélection, la croix arrive au jeu : aucune fenêtre Roblox ne tient la manette ; la
		-- sélection de la fenêtre est rendue et la croix absorbée (pas de roue de pings, de
		-- minicarte ni d'ACCLAMER derrière le panneau)
		if inputState == Enum.UserInputState.Begin then
			releaseHold()
			ensureSelection()
		end
		return Enum.ContextActionResult.Sink
	end
	if inputState == Enum.UserInputState.Begin then
		if actionName == ACTION_BACK then
			PanelController.back()
		elseif actionName == ACTION_PREV then
			PanelController.nextTab(-1)
		elseif actionName == ACTION_NEXT then
			PanelController.nextTab(1)
		elseif actionName == ACTION_CYCLE_PREV then
			PanelController.cyclePanel(-1)
		elseif actionName == ACTION_CYCLE_NEXT then
			PanelController.cyclePanel(1)
		end
	end
	-- absorbé (appui, relâchement, gâchette analogique) : R2 ne Dash pas, la caméra ne tourne pas
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
	ContextActionService:BindActionAtPriority(
		ACTION_CYCLE_PREV,
		onAction,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.ButtonL2
	)
	ContextActionService:BindActionAtPriority(
		ACTION_CYCLE_NEXT,
		onAction,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:BindActionAtPriority(
		ACTION_SCROLL,
		onAction,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Thumbstick2
	)
	ContextActionService:BindActionAtPriority(
		ACTION_NAV_GUARD,
		onAction,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.DPadUp,
		Enum.KeyCode.DPadDown,
		Enum.KeyCode.DPadRight
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
	ContextActionService:UnbindAction(ACTION_CYCLE_PREV)
	ContextActionService:UnbindAction(ACTION_CYCLE_NEXT)
	ContextActionService:UnbindAction(ACTION_SCROLL)
	ContextActionService:UnbindAction(ACTION_NAV_GUARD)
	stick = Vector2.zero
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

local opening = false -- ouverture en cours : la sélection est posée à la fin (selectDefault)

-- `quiet` : sans « Whoosh » (L2 / R2 jouent « Tab »)
local function openInternal(name: Types.PanelName, args: any?, quiet: boolean)
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
			selectTabInternal(name, tab)
		end
		ensureSelection()
		return
	end
	-- manette : sélection hors fenêtre à l'ouverture (bouton du rail) rendue par ○ à la fermeture ;
	-- bouton du panneau parent qui ouvre ce panneau (Supernova) rendu par ○ au retour
	local selected = GuiService.SelectedObject
	local w = window
	local inside = selected ~= nil and w ~= nil and selected:IsDescendantOf(w)
	if previous == nil then
		origin = if selected ~= nil and not inside then selected else nil
		opener = nil
	else
		opener = if inside then selected else nil
	end
	lastInWindow = nil
	scrollCache = nil
	bump = nil
	if previous then
		hidePage(previous)
	end
	closeToken += 1 -- annule une fermeture en cours
	opening = true
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
		selectTabInternal(name, tab)
	end
	animateOpen(previous == nil, quiet)
	opening = false
	bindActions()
	selectDefault(page)
	PanelController.Opened:Fire(name)
end

function PanelController.open(name: Types.PanelName, args: any?)
	openInternal(name, args, false)
end

-- `restore` : ○ ferme le panneau et rend à la manette la sélection d'origine (bouton du rail)
local function closeInternal(restore: boolean)
	local name = currentName
	if name == nil then
		return
	end
	currentName = nil
	opening = false
	unbindActions()
	releaseHold()
	local back = origin
	origin = nil
	opener = nil
	lastInWindow = nil
	bump = nil
	scrollCache = nil
	local w = window
	if
		restore
		and back ~= nil
		and gamepadActive()
		and not (w ~= nil and back:IsDescendantOf(w))
		and selectable(back)
	then
		GuiService.SelectedObject = back
	else
		clearSelection()
	end
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

function PanelController.close()
	closeInternal(false)
end

-- ○ / Échap / bouton Retour : recule d'un niveau (son « Back ») : Supernova → Améliorer (bouton
-- Supernova resélectionné à la manette) → fermeture (bouton d'origine hors fenêtre resélectionné)
function PanelController.back()
	local name = currentName
	if name == nil then
		return
	end
	AudioController.play("Back")
	local panel = panels[name]
	local parent = panel and panel.parent
	if parent and VALID[parent] then
		local target = opener
		openInternal(parent, nil, true)
		opener = nil
		local page = pages[parent]
		if
			target ~= nil
			and page ~= nil
			and gamepadActive()
			and target:IsDescendantOf(page.frame)
			and inWindow(target)
		then
			GuiService.SelectedObject = target
			lastInWindow = target
		end
	else
		closeInternal(true)
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
	selectTabInternal(name, shown[nextIndex].id, "Tab")
	if gamepadActive() then
		GuiService.SelectedObject = shown[nextIndex].button
		lastInWindow = shown[nextIndex].button
	end
end

-- Panneau précédent / suivant (L2 / R2, docs/07 §6.3), en boucle sur Améliorer, Collection,
-- Objectifs, Boutique, Équipage, Réglages (Supernova compte comme Améliorer), en sautant ceux que la
-- garde du HUD refuse (PanelController.allowed) ; son « Tab ». false : rien d'ouvert
function PanelController.cyclePanel(direction: number): boolean
	local own = cycleName(currentName)
	if own == nil or type(direction) ~= "number" or direction ~= direction or direction == 0 then
		return false
	end
	local index = table.find(CYCLE, own) :: number
	local step = if direction > 0 then 1 else -1
	for k = 1, #CYCLE - 1 do
		local candidate = CYCLE[(index - 1 + step * k) % #CYCLE + 1]
		if PanelController.allowed(candidate) then
			AudioController.play("Tab")
			openInternal(candidate, nil, true)
			return true
		end
	end
	return false
end

-- Sélection manette dans le panneau ouvert (ex. bouton Acheter après la fenêtre d'achat Roblox) :
-- `target` s'il est affiché dans la fenêtre, sinon la sélection par défaut ; rien sans manette ou
-- sans panneau. Retourne true si une sélection a été posée.
function PanelController.select(target: GuiObject?): boolean
	releaseHold()
	local name = currentName
	local page = if name then pages[name] else nil
	if page == nil or not gamepadActive() then
		return false
	end
	local chosen = if target ~= nil and inWindow(target) then target else defaultSelection(page)
	if chosen == nil then
		return false
	end
	GuiService.SelectedObject = chosen
	lastInWindow = chosen
	return true
end

-- Console (docs/07-console-ps5.md §6) ------------------------------------------------------------

-- Garde posée par le HUD (via InputController.setPanelGate) : un panneau dont l'icône n'est pas
-- encore affichée ne s'ouvre pas au changement de panneau à la manette (L2 / R2)
function PanelController.setGate(fn: ((Types.PanelName) -> boolean)?)
	panelGate = fn
end

-- Le panneau peut-il être ouvert d'après la garde du HUD ? (vrai sans garde)
function PanelController.allowed(name: Types.PanelName): boolean
	local gate = panelGate
	if gate == nil then
		return true
	end
	local ok, result = pcall(gate, name)
	return ok and result == true
end

-- Panneau Équipage (carte d'invitation, hors de la fenêtre), s'il est chargé
local function crewPanel(): any
	return panels["Crew"]
end

-- Cible hors fenêtre que △ doit sélectionner avant le rail : bouton Accepter de la carte
-- d'invitation d'équipage tant qu'elle est affichée (docs/07 §6.7) ; nil : aucune
function PanelController.focusTarget(): GuiObject?
	local crew = crewPanel()
	if crew == nil or type(crew.inviteTarget) ~= "function" then
		return nil
	end
	local ok, target = pcall(crew.inviteTarget)
	if ok and typeof(target) == "Instance" and target:IsA("GuiObject") and selectable(target) then
		return target :: GuiObject
	end
	return nil
end

-- La sélection hors fenêtre est-elle légitime pendant qu'un panneau est ouvert ? (carte d'invitation)
local function outsideAllowed(obj: Instance): boolean
	local crew = crewPanel()
	if crew == nil or type(crew.inviteCard) ~= "function" then
		return false
	end
	local ok, card = pcall(crew.inviteCard)
	return ok and typeof(card) == "Instance" and obj:IsDescendantOf(card)
end

-- Sélection manette toujours valide pendant qu'un panneau est ouvert (docs/07 §7) : un objet masqué
-- ou détruit (onglet changé, achat, fusion, liste reconstruite), ou une sélection partie derrière
-- la fenêtre, revient à la sélection par défaut. Une sélection effacée (pavé tactile / Créer de la
-- DualSense, menu du système refermé…) est rendue : dernier objet de la fenêtre s'il est encore
-- affiché, sinon la sélection par défaut. Elle ne reste vide que tant qu'une fenêtre Roblox tient
-- la manette : effacée juste après ✕ sur ce même objet (fenêtre d'achat ouverte par ce bouton,
-- jusqu'à la fin de l'achat), PanelController.holdSelection, menu du système ouvert.
ensureSelection = function()
	local name = currentName
	local page = if name then pages[name] else nil
	local w = window
	if page == nil or w == nil or opening or not gamepadActive() then
		return
	end
	local selected = GuiService.SelectedObject
	if selected ~= nil then
		heldByPrompt = false
		if selected:IsDescendantOf(w) then
			if selectable(selected) then
				lastInWindow = selected
				return
			end
		elseif selected ~= lastInWindow and outsideAllowed(selected) then
			return
		end
	else
		local last = lastInWindow
		local shown = last ~= nil and inWindow(last)
		if shown and confirmTarget == last and uiTime - confirmAt <= PROMPT_HOLD_WINDOW then
			heldByPrompt = true
		end
		confirmTarget = nil
		if selectionHeld() then
			return
		end
		if shown then
			GuiService.SelectedObject = last
			return
		end
	end
	local target = defaultSelection(page)
	if target ~= nil and target ~= selected then
		GuiService.SelectedObject = target
	end
	lastInWindow = target
end

-- Une fenêtre Roblox ouverte depuis le panneau tient la manette (ex. fenêtre d'achat de la
-- Boutique) : true laisse la sélection vide jusqu'à false, PanelController.select, la fin d'un achat
-- (PromptGamePassPurchaseFinished / PromptProductPurchaseFinished), la fermeture du panneau, ou une
-- croix qui arrive au jeu (preuve qu'aucune fenêtre Roblox ne tient plus la manette)
function PanelController.holdSelection(on: boolean)
	if on == true then
		heldByPanel = true
	else
		releaseHold()
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

-- Guard Links de la file locale (premiers nœuds jamais coupables, GDD §4.7) : attribut posé par le
-- serveur (EconomyService), repli sur le niveau Garde du profil (même formule)
local function localGuardLinks(player: Player): number
	local g = player:GetAttribute("GuardLinks")
	if type(g) == "number" and g == g and g ~= math.huge and g ~= -math.huge then
		return math.clamp(math.floor(g), 0, Balance.Guard.Max)
	end
	local upgrades = State.get("upgrades")
	local level = if type(upgrades) == "table" and type(upgrades.guard) == "number" then upgrades.guard else 0
	return Formulas.guardLinks(level)
end

-- Trêve de la Balise (phases « active » et « success » jusqu'à endsAt, comme EventService.isTruce
-- et CongaRenderer) ou coupes désactivées : personne ne coupe
local function snipsOff(now: number): boolean
	local events = WorldState.events()
	if events == nil then
		return false
	end
	if events.snipsDisabled then
		return true
	end
	local b = events.beacon
	return b ~= nil
		and (b.phase == "active" or b.phase == "success")
		and type(b.startsAt) == "number"
		and type(b.endsAt) == "number"
		and now >= b.startsAt
		and now < b.endsAt
end

-- Un non-équipier approche-t-il de la queue COUPABLE de la file locale (nœuds au-delà des Guard
-- Links) hors du port sûr ? Mêmes règles que le serveur et que le contour de sa propre queue
-- (CongaRenderer) : ni trêve de la Balise, ni immunité de la victime (§13.2, GDD §6.4)
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
	local now = Clock.now()
	if snipsOff(now) then
		return false
	end
	-- immunité après une coupe (ou plafond de coupes par minute) : le serveur refuse toute coupe
	local immune = player:GetAttribute("ImmuneUntil")
	if type(immune) == "number" and immune > now then
		return false
	end
	local pos = root.Position
	local guard = localGuardLinks(player)
	-- zone protégée des coupes = port sûr de TOUTES les portes (SnipRules, WorldLayout.inHarbor) ;
	-- pas « chez soi » (inOwnHarbor) : l'arrière de sa plateforme de Nid est hors de cette zone.
	-- Une file entièrement en Guard Links (Lead Trio) n'a rien de coupable.
	if WorldLayout.inHarbor(pos) or WorldState.lineLength(slot) <= guard then
		return false
	end
	local okNodes, nodes = pcall(CongaRenderer.nodePositions, slot)
	local points: { Vector3 } = {}
	if okNodes and type(nodes) == "table" and #nodes > 0 then
		for i = guard + 1, #nodes do
			table.insert(points, nodes[i])
		end
	else
		points = { pos } -- file pas encore rendue : position du joueur
	end
	if #points == 0 then
		return false
	end
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

-- ---------------------------------------------------------------------------------------------
-- Manette : défilement au stick droit, bout de liste
-- ---------------------------------------------------------------------------------------------

local function verticalScroll(obj: Instance): boolean
	return obj:IsA("ScrollingFrame")
		and (obj :: ScrollingFrame).ScrollingDirection ~= Enum.ScrollingDirection.X
end

-- Cadre défilant vertical qui contient la sélection, sinon la liste principale du panneau (le plus
-- grand cadre défilant vertical affiché de la page, mémorisé par onglet)
local function scrollTarget(page: Page): ScrollingFrame?
	local selected = GuiService.SelectedObject
	if selected ~= nil and selected:IsDescendantOf(page.body) then
		local cur = selected.Parent
		while cur ~= nil and cur ~= page.body do
			if verticalScroll(cur) and shownOnScreen(cur) then
				return cur :: ScrollingFrame
			end
			cur = cur.Parent
		end
	end
	local key = `{page.name}/{currentTab[page.name] or ""}`
	local cache = scrollCache
	if cache and cache.key == key and (cache.frame == nil or shownOnScreen(cache.frame)) then
		return cache.frame
	end
	local best: ScrollingFrame? = nil
	local area = 0
	for _, d in page.body:GetDescendants() do
		if verticalScroll(d) and shownOnScreen(d) then
			local size = (d :: ScrollingFrame).AbsoluteSize
			if best == nil or size.X * size.Y > area then
				best = d :: ScrollingFrame
				area = size.X * size.Y
			end
		end
	end
	scrollCache = { key = key, frame = best }
	return best
end

-- Défilement maximal (px) : AbsoluteCanvasSize − AbsoluteWindowSize ; repli (propriétés absentes) :
-- CanvasSize à l'échelle de l'écran, ou contenu mesuré (enfants affichés) pour un canevas
-- automatique
local function maxScroll(frame: ScrollingFrame): number
	local ok, canvas, view = pcall(function(): (any, any)
		return frame.AbsoluteCanvasSize, frame.AbsoluteWindowSize
	end)
	if ok and typeof(canvas) == "Vector2" and typeof(view) == "Vector2" and canvas.Y > 0 then
		return math.max(0, canvas.Y - view.Y)
	end
	local size = frame.AbsoluteSize
	local extent = frame.CanvasSize.Y.Offset * Root.scale() + frame.CanvasSize.Y.Scale * size.Y
	if frame.AutomaticCanvasSize ~= Enum.AutomaticSize.None then
		local top = frame.AbsolutePosition.Y - frame.CanvasPosition.Y
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				extent = math.max(extent, child.AbsolutePosition.Y + child.AbsoluteSize.Y - top)
			end
		end
	end
	return math.max(0, extent - size.Y)
end

-- Stick droit : défile la liste (vers le haut : on remonte), vitesse proportionnelle à sa hauteur
local function stepScroll(page: Page, dt: number)
	local v = stick
	if v.Y == 0 then
		return
	end
	local frame = scrollTarget(page)
	if frame == nil then
		return
	end
	local speed = math.max(SCROLL_MIN_SPEED, frame.AbsoluteSize.Y * SCROLL_SPEED)
	local position = frame.CanvasPosition
	local y = math.clamp(position.Y - v.Y * speed * dt, 0, maxScroll(frame))
	if y ~= position.Y then
		frame.CanvasPosition = Vector2.new(position.X, y)
	end
end

local function nearestScroll(obj: Instance): ScrollingFrame?
	local cur = obj.Parent
	while cur ~= nil and not cur:IsA("LayerCollector") do
		if cur:IsA("ScrollingFrame") then
			return cur :: ScrollingFrame
		end
		cur = cur.Parent
	end
	return nil
end

-- Croix pressée dans la fenêtre : on note la sélection (et le défilement de sa liste : une grille
-- virtualisée garde la même case en défilant)
local function onNavInput(input: InputObject)
	if currentName == nil then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.ButtonA then
		-- ✕ sur un objet de la fenêtre : s'il ouvre une fenêtre Roblox (achat), elle effacera la
		-- sélection dans les PROMPT_HOLD_WINDOW s (ensureSelection la laisse alors vide)
		local target = GuiService.SelectedObject
		local w = window
		if target ~= nil and w ~= nil and target:IsDescendantOf(w) then
			confirmAt = uiTime
			confirmTarget = target
		end
		return
	elseif key == Enum.KeyCode.ButtonSelect then
		-- pavé tactile / Créer : bascule de sélection de Roblox, jamais une fenêtre d'achat
		confirmTarget = nil
		return
	end
	if not NAV_KEYS[key] then
		return
	end
	local selected = GuiService.SelectedObject
	local w = window
	if selected == nil or w == nil or not selected:IsDescendantOf(w) then
		bump = nil
		return
	end
	local scroll = nearestScroll(selected)
	bump = {
		frame = frameNo,
		object = selected,
		canvas = if scroll then scroll.CanvasPosition else nil,
		-- sélection déplacée dans la même image, avant ce signal : la croix a servi
		changed = selectionChangedAt == frameNo,
		dir = if key == Enum.KeyCode.DPadDown then 1 elseif key == Enum.KeyCode.DPadUp then -1 else 0,
	}
end

-- Hauteur visible d'une liste (AbsoluteWindowSize : sans la barre de défilement), repli AbsoluteSize
local function windowHeight(frame: ScrollingFrame): number
	local ok, view = pcall(function(): any
		return frame.AbsoluteWindowSize
	end)
	if ok and typeof(view) == "Vector2" and view.Y > 0 then
		return view.Y
	end
	return frame.AbsoluteSize.Y
end

-- ↑ / ↓ qui ne trouve rien à sélectionner (lignes en lecture seule : Atlas, Guide, Perchoirs, aperçu
-- de la Supernova) : la liste de la sélection, sinon la liste principale du panneau, défile de
-- NUDGE_FRACTION de sa hauteur visible dans ce sens (règle R4 : tout le contenu reste lisible avec
-- les 4 directions). Une sélection DANS cette liste reste entièrement affichée (le défilement
-- s'arrête quand elle atteint le bord). false : rien à défiler de ce côté (vrai bout de liste)
local function nudgeScroll(page: Page, dir: number): boolean
	local frame = scrollTarget(page)
	if frame == nil then
		return false
	end
	local view = windowHeight(frame)
	local position = frame.CanvasPosition
	local y = math.clamp(position.Y + dir * view * NUDGE_FRACTION, 0, maxScroll(frame))
	local selected = GuiService.SelectedObject
	if selected ~= nil and selected:IsDescendantOf(frame) then
		local top = selected.AbsolutePosition.Y - frame.AbsolutePosition.Y
		local room = if dir > 0 then top else view - (top + selected.AbsoluteSize.Y)
		y = position.Y + dir * math.clamp(math.abs(y - position.Y), 0, math.max(0, room))
	end
	if math.abs(y - position.Y) < 1 then
		return false
	end
	frame.CanvasPosition = Vector2.new(position.X, y)
	AudioController.playNav()
	return true
end

-- Aucune sélection déplacée ni liste défilée après la croix : ↑ / ↓ font défiler la liste s'il
-- reste du contenu de ce côté, sinon bout de liste (docs/07 §9)
local function checkBump(page: Page)
	local probe = bump
	if probe == nil or frameNo - probe.frame < BUMP_FRAMES then
		return
	end
	bump = nil
	if probe.changed or GuiService.SelectedObject ~= probe.object then
		return
	end
	local scroll = nearestScroll(probe.object)
	local canvas = if scroll then scroll.CanvasPosition else nil
	if canvas ~= probe.canvas then
		return
	end
	if probe.dir ~= 0 and nudgeScroll(page, probe.dir) then
		return
	end
	AudioController.play("Bump")
	Haptics.play("listEnd")
end

local function onSelectionChanged()
	selectionChangedAt = frameNo
	local probe = bump
	if probe then
		probe.changed = true
	end
end

local badgeAcc, warnAcc = 0, 0
local function onHeartbeat(dt: number)
	frameNo += 1
	if dt == dt and dt > 0 and dt < math.huge then
		uiTime += dt
	end
	badgeAcc += dt
	if badgesDirty or badgeAcc >= BADGE_INTERVAL then
		badgeAcc = 0
		refreshBadges()
	end
	local name = currentName
	if name == nil then
		bump = nil
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
			selectTabInternal(name, shown[1].id)
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
	-- manette : sélection toujours valide, défilement au stick droit, bout de liste
	if page and currentName == name then
		ensureSelection()
		stepScroll(page, dt)
		checkBump(page)
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
	Platform.Init()
	-- périphérique changé : en-têtes refaits (repères ○ / L1 / R1 / L2 / R2), sélection posée
	Platform.Changed:Connect(function(reason: string)
		if reason ~= "input" then
			return
		end
		for _, page in pages do
			layoutChrome(page, true)
		end
		local name = currentName
		local page = if name then pages[name] else nil
		if page and gamepadActive() and GuiService.SelectedObject == nil and not selectionHeld() then
			selectDefault(page)
		end
	end)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(onSelectionChanged)
	-- fenêtre d'achat Roblox refermée (achat ou annulation) : la sélection peut être rendue
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
		releaseHold()
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function()
		releaseHold()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		onNavInput(input)
	end)
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
			if page and lastInputIsGamepad() and GuiService.SelectedObject == nil and not selectionHeld() then
				selectDefault(page)
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
