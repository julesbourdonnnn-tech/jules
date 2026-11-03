--!strict
-- PanelController (paquet client-panels) : menu (le rail) et panneaux (GDD §10.3, §10.4, §10.6 ;
-- docs/04 §13.6, §14.2).
--   * Le rail (à la place de la puce Menu, 96 × 246 px TV, 7 boutons de 340 × 96 au plus) : Grand
--     Splorch (seulement quand il est prêt), « ! » (une carte attend : ✕ la rouvre par Cards.open),
--     Ranch, Squishydex, Objectifs, Classements, Boutique (après 10 min de jeu et si un article est
--     vendu), Réglages. Sélection par défaut : Grand Splorch s'il est prêt, sinon « ! », sinon la
--     dernière entrée, sinon Ranch. Pastilles : ♥ N (jumeaux) sur Ranch, « ! » sur un panneau qui
--     a quelque chose à réclamer.
--   * toggleMenu (△, croix ↓, M : liés par InputController seul, jamais Tab) ouvre le rail ou ferme
--     tout ; open(panneau, onglet?) ouvre un panneau (raccourcis G C J L B P d'InputController,
--     cartes par Cards.Requested, navigateur des panneaux) ; un seul panneau à la fois, 1440 × 860 px
--     TV centré, voile et flou (sauf Graphismes légers) ; le jeu continue derrière.
--   * Fenêtres de FocusGuard : le rail (« menu ») reste ouvert sous le panneau, si bien que ○ depuis
--     le premier niveau d'un panneau revient au bouton du rail, puis au jeu ; △ ferme tout.
--   * Touches des panneaux (liées seulement quand un panneau est actif) : L1 / R1 onglets en boucle,
--     L2 / R2 panneaux en boucle (Ranch → Squishydex → Objectifs → Classements → Boutique →
--     Réglages), stick droit qui fait défiler. La croix, ✕ et ○ suffisent pour tout atteindre.
--   * Sons (Whoosh, Back, Tab, Bump, Error) et vibration listEnd au bout d'une liste.
--   * Ouvrir un panneau termine le portage (PutDown) ; ouvrir le rail, non.
-- Les panneaux ne requièrent jamais PanelController : chacun reçoit un navigateur (setNavigator)
-- avant build. Cards (plus précoce) n'appelle jamais PanelController : il émet Cards.Requested.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local FusionRules = require(Shared.Logic.FusionRules)
local QuestRules = require(Shared.Logic.QuestRules)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Juice = require(Client.UI.Juice)
local FocusGuard = require(Client.UI.FocusGuard)
local Cards = require(Client.UI.Cards)
local Toast = require(Client.UI.Toast)
local Prefs = require(Client.Util.Prefs)
local AudioController = require(Client.Controllers.AudioController)
local State = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local QualityController = require(Client.Controllers.QualityController)
local Widgets = require(Client.UI.Panels.Widgets)

local Panels = {
	Ranch = require(Client.UI.Panels.Ranch),
	Squishydex = require(Client.UI.Panels.Squishydex),
	Objectives = require(Client.UI.Panels.Objectives),
	Leaderboards = require(Client.UI.Panels.Leaderboards),
	Shop = require(Client.UI.Panels.Shop),
	Settings = require(Client.UI.Panels.Settings),
	SplorchPreview = require(Client.UI.Panels.SplorchPreview),
	OutfitPreview = require(Client.UI.Panels.OutfitPreview),
	Diagnostics = require(Client.UI.Panels.Diagnostics),
} :: { [string]: any }

local PanelController = {}

-- (panneau ouvert ou nil)
PanelController.Changed = Signal.new() :: Signal.Signal<string?>

local MENU = "menu"
local PANEL_PREFIX = "panel:"
local PENDING = "Pending"
-- Ordre du rail (GDD §10.2) ; « ! » juste sous le Grand Splorch
local RAIL =
	{ "SplorchPreview", PENDING, "Ranch", "Squishydex", "Objectives", "Leaderboards", "Shop", "Settings" }
-- L2 / R2 (seulement quand un de ces panneaux est actif)
local CYCLE = { "Ranch", "Squishydex", "Objectives", "Leaderboards", "Shop", "Settings" }
-- Panneaux ouverts PAR-DESSUS un autre (○ revient au panneau d'origine : nav.back)
local STACKED = { OutfitPreview = true, Diagnostics = true }
local ENTRY_KEYS = {
	SplorchPreview = "menu.splorch",
	Pending = "menu.pending",
	Ranch = "menu.ranch",
	Squishydex = "menu.dex",
	Objectives = "menu.goals",
	Leaderboards = "menu.leaderboards",
	Shop = "menu.shop",
	Settings = "menu.settings",
}
local TITLE_KEYS = {
	Ranch = "panel.ranch.title",
	Squishydex = "panel.dex.title",
	Objectives = "panel.goals.title",
	Leaderboards = "panel.lb.title",
	Shop = "panel.shop.title",
	Settings = "settings.title",
	SplorchPreview = "panel.splorch.title",
	OutfitPreview = "panel.shop.preview",
	Diagnostics = "panel.diag.title",
}
-- Icônes du rail : pastille de couleur et symbole (formes seulement, aucune image téléversée)
local ENTRY_ICONS: { [string]: { color: Color3, symbol: string } } = {
	SplorchPreview = { color = Color3.fromRGB(255, 120, 180), symbol = "✦" },
	Pending = { color = Color3.fromRGB(255, 200, 80), symbol = "!" },
	Ranch = { color = Color3.fromRGB(120, 220, 160), symbol = "♥" },
	Squishydex = { color = Color3.fromRGB(130, 180, 255), symbol = "★" },
	Objectives = { color = Color3.fromRGB(255, 170, 110), symbol = "✓" },
	Leaderboards = { color = Color3.fromRGB(255, 215, 90), symbol = "#" },
	Shop = { color = Color3.fromRGB(200, 140, 255), symbol = "$" },
	Settings = { color = Color3.fromRGB(180, 190, 210), symbol = "⚙" },
}

local DISPLAY_MENU = 30
local DISPLAY_PANELS = 35
local PANEL_RECT = Layout.Panel.rect
local SAFE = Layout.Safe
local RAIL_RECT = Layout.Hud.menuRail.rect
local RAIL_CONTENT = Layout.HudContent.menuRail
local BLUR_SIZE = 8
local BADGE_W = 60

local initialized = false
local started = false

local railFrame: Frame? = nil
local railButtons: { [string]: TextButton } = {}
local railBadges: { [string]: TextLabel } = {}
local panelsScreen: ScreenGui? = nil
local panelsSafe: Frame? = nil
local veil: Frame? = nil
local blur: BlurEffect? = nil
local windows: { [string]: Frame } = {}
local bodies: { [string]: Frame } = {}
local built: { [string]: boolean } = {}
local broken: { [string]: boolean } = {} -- build a échoué : jamais ouvert à moitié
local openOrder: { string } = {} -- panneaux ouverts, du plus ancien à l'actif
local lastEntry: string? = nil
local preferredEntry: string? = nil
local boundPanelKeys = false
local lastScrollAt = -math.huge
local railTop = RAIL_RECT.y - SAFE.y
local selectionChanges = 0
local selectionFrame = 0
local frameNo = 0
-- un panneau en remplace un autre (L2 / R2, raccourci, carte) : le voile, le flou et l'écran des
-- panneaux restent affichés et Changed ne passe pas par nil entre les deux
local switching = false

-- =============================================================================================
-- Outils
-- =============================================================================================

local function safe<T>(where: string, fallback: T, fn: any, ...: any): T
	return Widgets.safe(where, fallback, fn, ...)
end

local function topPanel(): string?
	return openOrder[#openOrder]
end

local function panelOpen(name: string): boolean
	return table.find(openOrder, name) ~= nil
end

-- Fenêtre bloquante d'un autre écran (écran de retour, carte du choix) au premier plan
local function blockedByWindow(): boolean
	local top = FocusGuard.top()
	if top == nil then
		return false
	end
	if top.name == MENU or string.sub(top.name, 1, #PANEL_PREFIX) == PANEL_PREFIX then
		return false
	end
	return top.blocking == true
end

local function entryVisible(entry: string): boolean
	if entry == PENDING then
		local list = safe("Cards.pending", {}, Cards.pending)
		return type(list) == "table" and #list > 0
	end
	local mod = Panels[entry]
	if mod == nil then
		return false
	end
	return safe(entry .. ".visible", false, mod.visible) == true
end

local function lowGraphics(): boolean
	if Prefs.lowGraphics() then
		return true
	end
	local budgets = safe("QualityController.budgets", nil, QualityController.budgets)
	if type(budgets) == "table" and budgets.blur == false then
		return true
	end
	return false
end

-- Le joueur porte-t-il un squishy ? (état public de son ranch ; inconnu → non)
local function carrying(): boolean
	local slot = safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
	if type(slot) ~= "number" or slot <= 0 then
		return false
	end
	local ranch = safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
	return type(ranch) == "table" and type(ranch.carry) == "string" and ranch.carry ~= ""
end

-- =============================================================================================
-- Construction
-- =============================================================================================

local function buildRail()
	local safeFrame = Root.safe("Menu", DISPLAY_MENU)
	local frame = Widgets.group(
		safeFrame,
		"Rail",
		UDim2.fromOffset(RAIL_RECT.w, RAIL_RECT.h),
		UDim2.fromOffset(RAIL_RECT.x - SAFE.x, RAIL_RECT.y - SAFE.y)
	)
	frame.Visible = false
	-- bout du rail (↑ sur la 1re entrée, ↓ sur la dernière) : c'est le rail entier qui rebondit (ses
	-- boutons sont placés par l'UIListLayout)
	frame:SetAttribute("BumpTarget", true)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, RAIL_CONTENT.gap)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame
	for i, entry in RAIL do
		local icon = ENTRY_ICONS[entry]
		local b = Widgets.button({
			parent = frame,
			name = "Entry_" .. entry,
			size = UDim2.fromOffset(RAIL_CONTENT.button.w, RAIL_CONTENT.button.h),
			color = Widgets.Colors.Panel,
			order = i,
			nav = true,
			sound = "",
			onActivate = function()
				PanelController._activateEntry(entry)
			end,
		})
		local dot = Widgets.frame({
			parent = b,
			name = "Icon",
			size = UDim2.fromOffset(RAIL_CONTENT.icon, RAIL_CONTENT.icon),
			position = UDim2.new(0, 16, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			color = icon.color,
			corner = UDim.new(0.5, 0),
			zIndex = b.ZIndex + 1,
		})
		-- symbole bleu nuit sans contour : un contour de la même couleur épaississait « # » et « $ »
		-- en taches (revue des écrans)
		Widgets.label({
			parent = dot,
			name = "Symbol",
			text = icon.symbol,
			textSize = 36,
			zIndex = dot.ZIndex + 1,
			color = Widgets.Colors.Stroke,
			stroke = false,
		})
		local labelX = 16 + RAIL_CONTENT.icon + 16
		Widgets.label({
			parent = b,
			name = "Label",
			size = UDim2.new(1, -(labelX + 16), 1, -16),
			position = UDim2.new(0, labelX, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			key = ENTRY_KEYS[entry],
			textSize = RAIL_CONTENT.text,
			xAlign = Enum.TextXAlignment.Left,
			zIndex = b.ZIndex + 1,
		})
		local badge = Widgets.label({
			parent = b,
			name = "Badge",
			size = UDim2.fromOffset(BADGE_W, 40),
			position = UDim2.new(1, -8, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			text = "",
			textSize = 28,
			background = Widgets.Colors.Pink,
			backgroundTransparency = 0,
			zIndex = b.ZIndex + 3,
		})
		Widgets.corner(badge, UDim.new(0.5, 0))
		badge.Visible = false
		railButtons[entry] = b
		railBadges[entry] = badge
	end
	railFrame = frame
end

local function buildPanelsScreen()
	local safeFrame = Root.safe("Panels", DISPLAY_PANELS)
	panelsSafe = safeFrame
	local gui = safeFrame.Parent :: ScreenGui
	panelsScreen = gui
	gui.Enabled = false
	-- voile plein écran (décoratif, hors zone sûre) qui arrête aussi les clics vers le jeu
	local v = Instance.new("Frame")
	v.Name = "Veil"
	v.BackgroundColor3 = Color3.fromRGB(10, 8, 24)
	v.BackgroundTransparency = 1
	v.BorderSizePixel = 0
	Root.coverScreen(v)
	v.Active = true
	v.ZIndex = 0
	v:SetAttribute("Decorative", true)
	v.Parent = gui
	veil = v
	safeFrame.ZIndex = 1
end

-- Cadre 1440 × 860 px TV d'un panneau : en-tête (titre 48, Fermer ○ 80 × 80, L2 / R2) et corps
local function buildWindow(name: string): (Frame, Frame)
	local parent = panelsSafe :: Frame
	local win = Widgets.frame({
		parent = parent,
		name = "Panel_" .. name,
		size = UDim2.fromOffset(PANEL_RECT.w, PANEL_RECT.h),
		-- centré dans la zone sûre (1440 × 860 px TV, x 240-1680 en 1080p) : reste dedans même quand la
		-- barre de Roblox réduit la hauteur utile (1280 × 720)
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Widgets.Colors.Panel,
		corner = Widgets.CORNER_LARGE,
		gradient = true,
		zIndex = if STACKED[name] then 10 else 5,
	})
	win.Visible = false
	local header = Widgets.group(win, "Header", UDim2.new(1, 0, 0, Layout.Panel.header), UDim2.new())
	Widgets.label({
		parent = header,
		name = "Title",
		size = UDim2.new(1, -2 * (Layout.Panel.close.w + 96), 0, Layout.Panel.title + 16),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		key = TITLE_KEYS[name],
		textSize = Layout.Panel.title,
		zIndex = win.ZIndex + 2,
	})
	local close = Widgets.button({
		parent = header,
		name = "Close",
		size = UDim2.fromOffset(Layout.Panel.close.w, Layout.Panel.close.h),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Widgets.Colors.Card,
		selectable = false, -- ○ suffit à la manette ; le bouton sert à la souris
		sound = "",
		onActivate = function()
			FocusGuard.back()
		end,
	})
	close.ZIndex = win.ZIndex + 2
	Widgets.glyph(
		close,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Backspace,
		Layout.Glyph.Min,
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	if table.find(CYCLE, name) then
		Widgets.glyph(
			header,
			Enum.KeyCode.ButtonL2,
			nil,
			Layout.Glyph.Min,
			UDim2.new(0, 24, 0.5, 0),
			Vector2.new(0, 0.5)
		)
		Widgets.glyph(
			header,
			Enum.KeyCode.ButtonR2,
			nil,
			Layout.Glyph.Min,
			UDim2.new(1, -(Layout.Panel.close.w + 32), 0.5, 0),
			Vector2.new(1, 0.5)
		)
	end
	local body = Widgets.group(
		win,
		"Body",
		UDim2.fromOffset(PANEL_RECT.w, PANEL_RECT.h - Layout.Panel.header),
		UDim2.fromOffset(0, Layout.Panel.header)
	)
	body.ZIndex = win.ZIndex + 1
	return win, body
end

local function navigatorFor(_name: string)
	return {
		open = function(panel: string, tab: string?)
			PanelController.open(panel, tab)
		end,
		back = function()
			local top = topPanel()
			if top then
				FocusGuard.closeNow(PANEL_PREFIX .. top)
			end
		end,
		-- ferme tout et rend la main au jeu (Aperçu du Grand Splorch : entré dans la file)
		closeAll = function()
			PanelController.closeAll()
		end,
	}
end

-- Construit un panneau une seule fois (setNavigator AVANT build)
local function ensureBuilt(name: string): boolean
	if built[name] then
		return not broken[name]
	end
	local mod = Panels[name]
	if mod == nil or panelsSafe == nil then
		return false
	end
	local win, body = buildWindow(name)
	windows[name] = win
	bodies[name] = body
	local ok, err = pcall(function()
		mod.setNavigator(navigatorFor(name))
		mod.build(body)
	end)
	built[name] = true
	if not ok then
		-- un panneau à moitié construit ne s'ouvre jamais ; l'erreur est relancée dans un fil à part
		-- (ScriptContext.Error → ErrorReporter → Diagnostics), jamais avalée
		broken[name] = true
		Widgets.raise(name .. ".build", tostring(err))
	end
	return ok
end

-- =============================================================================================
-- Rail
-- =============================================================================================

local function railBadge(entry: string): string
	if entry == "Ranch" then
		local pairs =
			safe("FusionRules.twinPairs", 0, FusionRules.twinPairs, Widgets.tbl(State.get("squishies")))
		return if type(pairs) == "number" and pairs > 0 then "♥" .. tostring(pairs) else ""
	elseif entry == "Objectives" then
		local objectives = Widgets.tbl(State.get("objectives"))
		for _, e in Widgets.tbl(objectives.list) do
			if type(e) == "table" and e.done == true and e.claimed ~= true then
				return "!"
			end
		end
	elseif entry == "Squishydex" then
		local dex = Widgets.tbl(State.get("dex"))
		local stamps = safe("QuestRules.stampCount", 0, QuestRules.stampCount, dex)
		local list =
			safe("QuestRules.dexMilestones", {}, QuestRules.dexMilestones, stamps, Widgets.n(dex.rewards))
		if type(list) == "table" and #list > 0 then
			return "!"
		end
	elseif entry == PENDING then
		local list = safe("Cards.pending", {}, Cards.pending)
		return if type(list) == "table" and #list > 0 then tostring(#list) else ""
	end
	return ""
end

-- Panneau ouvert : sa fenêtre (x 240) recouvre le rail (x 96-436) et tranchait ses libellés
-- (« Gra », « Ran », « Squ ») et ses pastilles. Pendant un panneau, le rail ne montre que ses
-- pastilles de couleur (icônes entières, x 112-176) ; libellés et pastilles reviennent à la
-- fermeture (revue des écrans)
local function coverRail()
	local covered = panelsScreen ~= nil and (panelsScreen :: ScreenGui).Enabled
	for _, entry in RAIL do
		local b = railButtons[entry]
		local badge = railBadges[entry]
		if b and badge then
			local label = b:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.Visible = not covered
			end
			badge.Visible = badge.Text ~= "" and not covered
		end
	end
end

local function refreshRail()
	local frame = railFrame
	if frame == nil then
		return
	end
	local visibleList: { string } = {}
	for _, entry in RAIL do
		local v = entryVisible(entry)
		railButtons[entry].Visible = v
		if v then
			table.insert(visibleList, entry)
		end
	end
	-- 7 boutons de 96 au plus sous la puce Menu (y 246) ; boutons réduits (jamais sous 80) quand la
	-- hauteur utile manque (carte en attente en plus, 1280 × 720 avec la barre de Roblox), puis le rail
	-- remonte : il ne sort jamais de la zone sûre
	local n = math.max(1, #visibleList)
	local gap = RAIL_CONTENT.gap
	local top = RAIL_RECT.y - SAFE.y
	local available = math.min(RAIL_RECT.h, Widgets.safeHeight() - top)
	local h = math.floor((available - (n - 1) * gap) / n)
	h = math.clamp(h, Layout.Button.MinHeight, RAIL_CONTENT.button.h)
	local needed = n * h + (n - 1) * gap
	if needed > available then
		top = math.max(0, Widgets.safeHeight() - needed)
	end
	railTop = top
	frame.Position = UDim2.fromOffset(RAIL_RECT.x - SAFE.x, top)
	frame:SetAttribute("RestPosition", frame.Position)
	frame.Size = UDim2.fromOffset(RAIL_RECT.w, needed)
	local labelX = 16 + RAIL_CONTENT.icon + 16
	for _, entry in RAIL do
		local b = railButtons[entry]
		b.Size = UDim2.fromOffset(RAIL_CONTENT.button.w, h)
		local text = railBadge(entry)
		local badge = railBadges[entry]
		Widgets.setRaw(badge, text)
		-- la pastille a sa place à droite : le libellé se resserre (jamais de chevauchement)
		local label = b:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			local room = if text ~= "" then BADGE_W + 16 else 0
			label.Size = UDim2.new(1, -(labelX + 16 + room), 1, -16)
		end
	end
	coverRail()
	Widgets.attention(railButtons.SplorchPreview, railButtons.SplorchPreview.Visible)
	-- entrée sélectionnée qui vient d'être cachée (carte « ! » rangée, Grand Splorch plus prêt) : la
	-- sélection passe aussitôt à l'entrée par défaut, sans sauvetage compté
	local top = FocusGuard.top()
	if top and top.name == MENU then
		FocusGuard.refocus()
	end
end

local function menuDefault(): GuiObject?
	local preferred = preferredEntry
	preferredEntry = nil
	if preferred and railButtons[preferred] and railButtons[preferred].Visible then
		return railButtons[preferred]
	end
	for _, entry in { "SplorchPreview", PENDING } do
		if railButtons[entry] and railButtons[entry].Visible then
			return railButtons[entry]
		end
	end
	if lastEntry and railButtons[lastEntry] and railButtons[lastEntry].Visible then
		return railButtons[lastEntry]
	end
	return railButtons.Ranch
end

local function showRail()
	local frame = railFrame
	if frame == nil then
		return
	end
	refreshRail()
	frame.Visible = true
	if not Juice.reducedMotion() then
		local target = UDim2.fromOffset(RAIL_RECT.x - SAFE.x, railTop)
		frame.Position = target - UDim2.fromOffset(40, 0)
		Juice.tween(frame, 0.2, { Position = target }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
end

local function openMenuWindow()
	if FocusGuard.isOpen(MENU) then
		return
	end
	showRail()
	FocusGuard.open({
		name = MENU,
		root = railFrame :: Frame,
		blocking = false,
		default = menuDefault,
		onBack = function(): boolean
			return false
		end,
		opener = nil,
	})
end

-- =============================================================================================
-- Panneaux
-- =============================================================================================

-- Haut de la pile des toasts quand un panneau est ouvert (px de Root.safe) : centrée dans la barre
-- de titre du panneau (fenêtre centrée dans la zone utile de Root.safe), jamais sur ses onglets
local TOAST_H = 88 -- UI/Toast : hauteur d'un toast
local function toastAnchor(): number?
	local gui, safeFrame = panelsScreen, panelsSafe
	if gui == nil or safeFrame == nil or not gui.Enabled then
		return nil
	end
	local s = Root.scale()
	local h = safeFrame.AbsoluteSize.Y
	if s <= 0 or h <= 0 then
		return nil
	end
	local inner = h / s - 2 * Root.padding().Y
	local top = (inner - PANEL_RECT.h) / 2
	if top < 0 then
		return nil
	end
	return top + math.max(0, (Layout.Panel.header - TOAST_H) / 2)
end

local function setOverlay(on: boolean)
	local gui = panelsScreen
	local v = veil
	if gui == nil or v == nil then
		return
	end
	Toast.anchor = toastAnchor
	if on then
		gui.Enabled = true
		if Juice.reducedMotion() then
			v.BackgroundTransparency = 0.45
		else
			Juice.tween(v, 0.15, { BackgroundTransparency = 0.45 })
		end
		if not lowGraphics() then
			local camera = workspace.CurrentCamera
			local b = blur
			-- caméra remplacée (ou flou détruit avec l'ancienne) : un nouveau flou sur la caméra courante
			if b and (b.Parent == nil or b.Parent ~= camera) then
				if b.Parent ~= nil then
					b:Destroy()
				end
				b = nil
				blur = nil
			end
			if b == nil and camera then
				local created = Instance.new("BlurEffect")
				created.Name = "PanelBlur"
				created.Size = 0
				created.Parent = camera
				blur = created
				b = created
			end
			if b then
				Juice.tween(b, 0.2, { Size = BLUR_SIZE })
			end
		end
	else
		v.BackgroundTransparency = 1
		gui.Enabled = false
		if blur then
			Juice.tween(blur, 0.12, { Size = 0 })
		end
	end
	coverRail()
	-- un toast déjà affiché monte dans la barre de titre (ou redescend à la fermeture)
	pcall(Toast.relayout)
end

local function unbindPanelKeys()
	if not boundPanelKeys then
		return
	end
	boundPanelKeys = false
	pcall(function()
		ContextActionService:UnbindAction("PanelTabs")
		ContextActionService:UnbindAction("PanelCycle")
		ContextActionService:UnbindAction("PanelScroll")
	end)
end

-- Le panneau actif est-il la fenêtre active ? (une carte bloquante par-dessus : L1 / R1 / L2 / R2
-- ne font rien derrière elle)
local function panelOnTop(name: string?): boolean
	local top = FocusGuard.top()
	return name ~= nil and top ~= nil and top.name == PANEL_PREFIX .. name
end

local function cycleTab(dir: number)
	local name = topPanel()
	if name == nil or not panelOnTop(name) then
		return
	end
	local mod = Panels[name]
	local tabs = safe(name .. ".tabs", {}, mod.tabs)
	if type(tabs) ~= "table" or #tabs < 2 then
		return
	end
	local current = safe(name .. ".currentTab", tabs[1], mod.currentTab)
	local i = table.find(tabs, current) or 1
	local nextTab = tabs[((i - 1 + dir) % #tabs) + 1]
	AudioController.play("Tab")
	safe(name .. ".setTab", nil, mod.setTab, nextTab)
	-- la sélection restée sur la page cachée revient tout de suite (onglet changé : pas un sauvetage)
	FocusGuard.refocus()
end

local function cyclePanel(dir: number)
	local name = topPanel()
	if name == nil or not table.find(CYCLE, name) or not panelOnTop(name) then
		return
	end
	if not FocusGuard.canClose(PANEL_PREFIX .. name) then
		return -- double appui
	end
	local i = table.find(CYCLE, name) :: number
	for step = 1, #CYCLE - 1 do
		local candidate = CYCLE[((i - 1 + dir * step) % #CYCLE) + 1]
		if entryVisible(candidate) then
			AudioController.play("Tab")
			PanelController.open(candidate)
			return
		end
	end
end

local function bindPanelKeys()
	local name = topPanel()
	if name == nil then
		unbindPanelKeys()
		return
	end
	if boundPanelKeys then
		return
	end
	boundPanelKeys = true
	pcall(function()
		ContextActionService:BindActionAtPriority("PanelTabs", function(_, state, input)
			if state == Enum.UserInputState.Begin then
				cycleTab(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
			end
			return Enum.ContextActionResult.Sink
		end, false, Widgets.BIND_PRIORITY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
		ContextActionService:BindActionAtPriority("PanelCycle", function(_, state, input)
			if state == Enum.UserInputState.Begin then
				cyclePanel(if input.KeyCode == Enum.KeyCode.ButtonL2 then -1 else 1)
			end
			return Enum.ContextActionResult.Sink
		end, false, Widgets.BIND_PRIORITY, Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2)
		ContextActionService:BindActionAtPriority("PanelScroll", function(_, state, input)
			if state == Enum.UserInputState.Change then
				local y = input.Position.Y
				local now = Clock.now()
				if math.abs(y) >= 0.6 and (now - lastScrollAt >= 0.3 or now < lastScrollAt) then
					lastScrollAt = now
					local top = topPanel()
					local mod = if top and panelOnTop(top) then Panels[top] else nil
					if mod and type(mod.scroll) == "function" then
						safe((top :: string) .. ".scroll", nil, mod.scroll, if y > 0 then -1 else 1)
					end
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, Widgets.BIND_PRIORITY, Enum.KeyCode.Thumbstick2)
	end)
end

-- Fermeture / retour (GDD §9.2) : UIScale 1 → 0,9 en 0,12 s (Quad In), puis caché
local function hidePanelFrame(name: string)
	local win = windows[name]
	if win == nil then
		return
	end
	if Juice.reducedMotion() then
		win.Visible = false
	else
		local scale = Juice.scaleOf(win)
		local tween =
			Juice.tween(scale, 0.12, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and not panelOpen(name) then
				win.Visible = false
				scale.Scale = 1
			end
		end)
		-- filet : jamais un cadre fantôme si la fin du tween n'arrive pas
		task.delay(0.5, function()
			if not panelOpen(name) then
				win.Visible = false
			end
		end)
	end
end

local function onWindowClosed(windowName: string)
	if windowName == MENU then
		local frame = railFrame
		if frame then
			frame.Visible = false
		end
		-- le rail fermé ferme aussi les panneaux encore ouverts (aucun panneau sans menu)
		for i = #openOrder, 1, -1 do
			FocusGuard.closeNow(PANEL_PREFIX .. openOrder[i])
		end
		return
	end
	if string.sub(windowName, 1, #PANEL_PREFIX) ~= PANEL_PREFIX then
		return
	end
	local name = string.sub(windowName, #PANEL_PREFIX + 1)
	local i = table.find(openOrder, name)
	if i == nil then
		return
	end
	table.remove(openOrder, i)
	Widgets.cancelHolds()
	local mod = Panels[name]
	if mod then
		safe(name .. ".close", nil, mod.close)
	end
	hidePanelFrame(name)
	if #openOrder == 0 then
		unbindPanelKeys()
		if not switching then
			setOverlay(false)
			refreshRail()
		end
	else
		unbindPanelKeys()
		bindPanelKeys()
	end
	if not switching then
		PanelController.Changed:Fire(topPanel())
	end
end

local function showPanel(name: string, tab: string?)
	local mod = Panels[name]
	local win = windows[name]
	setOverlay(true)
	-- ouverture (GDD §9.2) : UIScale 0,85 → 1 en 0,22 s (Back Out) ; le voile fond en 0,15 s
	win.Visible = true
	local scale = Juice.scaleOf(win)
	if Juice.reducedMotion() then
		scale.Scale = 1
	else
		scale.Scale = 0.85
		Juice.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	table.insert(openOrder, name)
	safe(name .. ".open", nil, mod.open, tab)
	-- ouvrir un panneau termine le portage (le rail, non)
	if carrying() then
		Widgets.send("PutDown")
	end
	local opener: GuiObject? = nil
	local railButton = railButtons[name]
	if railButton and railButton.Visible and not STACKED[name] then
		opener = railButton
	end
	FocusGuard.open({
		name = PANEL_PREFIX .. name,
		root = win,
		blocking = false,
		default = function(): GuiObject?
			return safe(name .. ".defaultSelection", nil, mod.defaultSelection)
		end,
		onBack = function(): boolean
			return safe(name .. ".onBack", false, mod.onBack) == true
		end,
		opener = opener,
	})
	unbindPanelKeys()
	bindPanelKeys()
	AudioController.play("Whoosh")
	if table.find(RAIL, name) then
		lastEntry = name
	end
	PanelController.Changed:Fire(name)
end

-- =============================================================================================
-- Détection du bout de liste (rebond 8 px, son Bump, vibration listEnd)
-- =============================================================================================

local NAV_DIR: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.DPadUp] = "Up",
	[Enum.KeyCode.DPadDown] = "Down",
	[Enum.KeyCode.DPadLeft] = "Left",
	[Enum.KeyCode.DPadRight] = "Right",
}

local function ourWindowOnTop(): boolean
	local top = FocusGuard.top()
	return top ~= nil and (top.name == MENU or string.sub(top.name, 1, #PANEL_PREFIX) == PANEL_PREFIX)
end

local function onNavInput(input: InputObject)
	local dir = NAV_DIR[input.KeyCode]
	if dir == nil or not ourWindowOnTop() then
		return
	end
	local before = GuiService.SelectedObject
	if before == nil then
		return
	end
	-- objet qui fait défiler lui-même sa liste à la croix (Guide du Squishydex) : il joue seul son bout
	-- de liste, au vrai bout (sinon chaque ↓ qui défile rebondirait)
	if before:GetAttribute("SelfScroll") == true then
		return
	end
	local count = selectionChanges
	local frame = frameNo
	task.defer(function()
		-- la sélection n'a pas bougé (ni après l'appui, ni juste avant dans la même image)
		if selectionChanges ~= count or selectionFrame == frame then
			return
		end
		local selected = GuiService.SelectedObject
		if selected == nil or not ourWindowOnTop() then
			return
		end
		Widgets.listEnd(selected, dir)
	end)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function PanelController.Init()
	if initialized then
		return
	end
	initialized = true
	buildRail()
	buildPanelsScreen()
end

-- Connexions et boucles
function PanelController.Start()
	if started then
		return
	end
	started = true
	PanelController.Init()
	for name, mod in Panels do
		if type(mod.start) == "function" then
			safe(name .. ".start", nil, mod.start)
		end
	end
	FocusGuard.WindowClosed:Connect(onWindowClosed)
	Cards.Requested:Connect(function(kind: string, action: string)
		PanelController._onCardRequest(kind, action)
	end)
	if type(Cards.Changed) == "table" then
		Cards.Changed:Connect(function()
			if FocusGuard.isOpen(MENU) then
				refreshRail()
			end
		end)
	end
	Widgets.watch(
		{ "squishies", "R", "growth", "objectives", "dex", "stats", "coins", "pot", "passes" },
		function()
			if FocusGuard.isOpen(MENU) then
				refreshRail()
			end
		end
	)
	Prefs.LanguageChanged:Connect(function()
		local top = topPanel()
		for name in built do
			local mod = Panels[name]
			if type(mod.refresh) == "function" and name == top then
				safe(name .. ".refresh", nil, mod.refresh)
			end
		end
		refreshRail()
	end)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		selectionChanges += 1
		selectionFrame = frameNo
	end)
	RunService.Heartbeat:Connect(function()
		frameNo += 1
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			onNavInput(input)
		end
	end)
end

-- △ / croix ↓ / M (KeyCode.M et Semicolon ; jamais Tab, laissé à Roblox) : ouvre le rail ou ferme tout
function PanelController.toggleMenu()
	if blockedByWindow() then
		return
	end
	if FocusGuard.isOpen(MENU) or #openOrder > 0 then
		local top = FocusGuard.top()
		if top and not FocusGuard.canClose(top.name) then
			return -- double appui (0,35 s)
		end
		AudioController.play("Back")
		PanelController.closeAll()
		return
	end
	PanelController.openMenu(nil)
end

-- Ouvre le rail (entrée sélectionnée)
function PanelController.openMenu(entry: string?)
	if not initialized or blockedByWindow() then
		return
	end
	for i = #openOrder, 1, -1 do
		FocusGuard.closeNow(PANEL_PREFIX .. openOrder[i])
	end
	if FocusGuard.isOpen(MENU) then
		refreshRail()
		local b = if entry then railButtons[entry] else nil
		if b and b.Visible then
			GuiService.SelectedObject = b
		end
		return
	end
	preferredEntry = entry
	AudioController.play("Whoosh")
	openMenuWindow()
end

-- Ouvre un panneau (onglet demandé ou le dernier) ; le rail reste ouvert dessous
function PanelController.open(panel: string, tab: string?)
	if not initialized or type(panel) ~= "string" or Panels[panel] == nil then
		return
	end
	if blockedByWindow() then
		return
	end
	if not entryVisible(panel) then
		Widgets.refuse(nil)
		return
	end
	if topPanel() == panel then
		if type(tab) == "string" then
			safe(panel .. ".setTab", nil, Panels[panel].setTab, tab)
			FocusGuard.refocus()
		end
		return
	end
	if not ensureBuilt(panel) then
		return
	end
	if not FocusGuard.isOpen(MENU) then
		preferredEntry = if railButtons[panel] then panel else nil
		openMenuWindow()
	end
	if not STACKED[panel] then
		-- le panneau remplacé se ferme sans retirer le voile ni signaler « aucun panneau »
		switching = #openOrder > 0
		for i = #openOrder, 1, -1 do
			FocusGuard.closeNow(PANEL_PREFIX .. openOrder[i])
		end
		switching = false
		-- la sélection revient au bouton du rail de ce panneau (ouvreur de la fenêtre)
		local b = railButtons[panel]
		if b and b.Visible then
			GuiService.SelectedObject = b
		end
	end
	showPanel(panel, tab)
end

-- Ferme tout et rend la main au jeu
function PanelController.closeAll()
	for i = #openOrder, 1, -1 do
		FocusGuard.closeNow(PANEL_PREFIX .. openOrder[i])
	end
	if FocusGuard.isOpen(MENU) then
		FocusGuard.closeNow(MENU)
	end
end

-- Un panneau (ou celui-ci) est ouvert
function PanelController.isOpen(panel: string?): boolean
	if panel == nil then
		return #openOrder > 0
	end
	return panelOpen(panel)
end

-- Panneau ouvert (le plus haut)
function PanelController.current(): string?
	return topPanel()
end

-- Le rail est-il ouvert ?
function PanelController.menuOpen(): boolean
	return FocusGuard.isOpen(MENU)
end

-- Entrées visibles du rail, dans l'ordre
function PanelController.entries(): { string }
	local out = {}
	for _, entry in RAIL do
		if entryVisible(entry) then
			table.insert(out, entry)
		end
	end
	return out
end

-- Bouton du rail d'une entrée (specs, robot TvAudit)
function PanelController.entryButton(entry: string): TextButton?
	return railButtons[entry]
end

-- Cadre d'un panneau construit (specs)
function PanelController.window(panel: string): Frame?
	return windows[panel]
end

-- ✕ sur une entrée du rail
function PanelController._activateEntry(entry: string)
	if entry == PENDING then
		local list = safe("Cards.pending", {}, Cards.pending)
		local card = if type(list) == "table" then list[1] else nil
		if type(card) == "table" and type(card.id) == "string" then
			AudioController.play("Click")
			safe("Cards.open", nil, Cards.open, card.id)
		else
			Widgets.refuse(railButtons[PENDING])
			refreshRail()
		end
		return
	end
	if not entryVisible(entry) then
		Widgets.refuse(railButtons[entry])
		refreshRail()
		return
	end
	AudioController.play("Click")
	lastEntry = entry
	PanelController.open(entry)
end

-- Carte qui demande un panneau (Cards.Requested : sorte de carte, action)
local CARD_PANELS: { [string]: { panel: string, tab: string? } } = {
	objectives = { panel = "Objectives", tab = "today" },
	newObjectives = { panel = "Objectives", tab = "today" },
	dex = { panel = "Squishydex", tab = "species" },
	mode = { panel = "Settings" },
	postBoop = { panel = "Settings" },
	booped = { panel = "Settings" },
}

function PanelController._onCardRequest(kind: string, action: string)
	if action ~= "open" or type(kind) ~= "string" then
		return
	end
	local target = CARD_PANELS[kind]
	if target then
		PanelController.open(target.panel, target.tab)
	end
end

return PanelController
