--!strict
-- PhotoHud (lot B5, étape 5 ; GDD v2.0 §7.5 « Mode photo Cheese ! », §10.4, §10.6 ; docs/04 §27.13 N22 ;
-- plan B5 W3, D25, D26, D27) : l'écran du mode photo, SON ScreenGui à lui. Ouvert et fermé par
-- CameraController.photo (qui tient la caméra, les sticks et l'intention SetPhotoMode) :
--   * fenêtre BLOQUANTE « photo » de FocusGuard dont la racine est ce ScreenGui : InputController
--     n'a plus aucune touche du jeu liée (aucun achat, aucune vente, aucun boop, aucun prestige
--     possible), FocusGuard tient ○ et Retour arrière : ○ ferme la fenêtre, donc le mode photo, en UN
--     appui ; le ✕ qui a ouvert le mode photo est gardé par l'InputGuard (relâchement vu + 0,3 s) ;
--   * UN bouton sélectionnable « ○ Quitter le mode photo » (photo.exit, glyphe de la plateforme par
--     UI/Glyph : ○ sur PS5, B sur Xbox, Retour arrière au clavier) : ✕ ou un clic dessus = sortie ;
--   * une aide de 4 lignes aux glyphes dessinés (stick gauche : bouger, stick droit : tourner,
--     L2 / R2 : zoom, □ : filtre ; au clavier WASD, flèches, Page préc. / suiv., F) qui s'efface après
--     3 s sans appui et revient au suivant (photos propres avec le bouton Create) ;
--   * le filtre : un voile plein écran teinté (aucun, chaud, rose, rêve ; aucune écriture de
--     Lighting) et son nom 2 s (photo.filter.*).
-- Le HUD est caché LOCALEMENT, sans le serveur (D26) : à l'ouverture, chaque ScreenGui ACTIF de
-- PlayerGui (sauf celui-ci et ceux qui portent l'attribut FocusExempt) est retenu puis coupé ; un
-- ScreenGui qui s'allume pendant le mode photo est coupé et retenu aussi ; un ScreenGui que son
-- module coupe lui-même pendant ce temps est oublié. À la sortie, EXACTEMENT les retenus se
-- rallument. Une autre fenêtre de FocusGuard qui s'ouvre (panneau ouvert par une carte…) termine le
-- mode photo : rien ne s'affiche jamais par-dessus un écran caché.
-- Construit une fois, à la première ouverture ; aucune instance créée ni détruite ensuite.
--
--   PhotoHud.open(onExit) : boolean   -- ouvre (onExit appelé UNE fois quand la fenêtre se ferme)
--   PhotoHud.close()                  -- ferme (sans appeler onExit) et rallume les ScreenGuis
--   PhotoHud.isOpen() : boolean
--   PhotoHud.noteInput()              -- un appui du mode photo : l'aide revient
--   PhotoHud.cycleFilter() : string   -- filtre suivant (nom)
--   PhotoHud.tick()                   -- effacement de l'aide et du nom du filtre (sur l'horloge)
--   PhotoHud.filter() / hidden() / gui() / exitButton() / hintShown() / nameShown()   -- specs

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local FocusGuard = require(Client.UI.FocusGuard)
local Widgets = require(Client.UI.Panels.Widgets)

local PhotoHud = {}

PhotoHud.WINDOW = "photo"
PhotoHud.FILTERS = table.freeze({ "none", "warm", "pink", "dream" })

local DISPLAY_ORDER = 48 -- au-dessus des cartes (40) et des jumelles (42), sous rien d'autre en photo
local HINT_FADE = 3 -- s sans appui : l'aide s'efface
local NAME_TIME = 2 -- s : nom du filtre
local EXIT = { w = 600, h = 96, text = 36, bottom = 24 } -- px TV
local HINT = { w = 460, row = 64, pad = 16, text = 32, glyphGap = 12 }
local NAME = { w = 520, h = 80, text = 44, top = 24 }
-- teinte et opacité de chaque filtre (voile plein écran ; « none » : voile caché)
local TINTS: { [string]: { color: Color3, transparency: number } } = {
	warm = { color = Color3.fromRGB(255, 170, 90), transparency = 0.84 },
	pink = { color = Color3.fromRGB(255, 120, 190), transparency = 0.84 },
	dream = { color = Color3.fromRGB(160, 140, 255), transparency = 0.8 },
}
-- lignes de l'aide : clé, touches de la manette, touches du clavier
type HintRow = { key: string, pad: { Enum.KeyCode }, keys: { Enum.KeyCode } }
local HINTS: { HintRow } = {
	{ key = "photo.hint.move", pad = { Enum.KeyCode.Thumbstick1 }, keys = { Enum.KeyCode.W } },
	{ key = "photo.hint.turn", pad = { Enum.KeyCode.Thumbstick2 }, keys = { Enum.KeyCode.Left } },
	{
		key = "photo.hint.zoom",
		pad = { Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2 },
		keys = { Enum.KeyCode.PageUp, Enum.KeyCode.PageDown },
	},
	{ key = "photo.hint.filter", pad = { Enum.KeyCode.ButtonX }, keys = { Enum.KeyCode.F } },
}

local screen: ScreenGui? = nil
local safeFrame: Frame? = nil
local tint: Frame? = nil
local hint: Frame? = nil
local nameBox: Frame? = nil
local nameLabel: TextLabel? = nil
local exitButton: TextButton? = nil
local opened = false
local exitCb: (() -> ())? = nil
local filterIndex = 1
local lastInput = 0
local nameUntil = 0
local hooked = false
-- ScreenGuis coupés par le mode photo (rallumés à la sortie) et écoutes posées pendant
local hidden: { ScreenGui } = {}
local watchers: { RBXScriptConnection } = {}
local writing = false

-- =============================================================================================
-- HUD caché localement (D26)
-- =============================================================================================

local function playerGui(): Instance?
	local player = Players.LocalPlayer
	return if player then player:FindFirstChildOfClass("PlayerGui") else nil
end

local function exempt(gui: ScreenGui): boolean
	return gui == screen or gui:GetAttribute("FocusExempt") == true
end

local function hide(gui: ScreenGui)
	if exempt(gui) or table.find(hidden, gui) ~= nil then
		return
	end
	table.insert(hidden, gui)
	writing = true
	gui.Enabled = false
	writing = false
end

local function watch(gui: Instance)
	if not gui:IsA("ScreenGui") then
		return
	end
	local g = gui :: ScreenGui
	if exempt(g) then
		return
	end
	if g.Enabled then
		hide(g)
	end
	table.insert(
		watchers,
		g:GetPropertyChangedSignal("Enabled"):Connect(function()
			if writing or not opened then
				return
			end
			if g.Enabled then
				-- allumé par son module pendant le mode photo : coupé et retenu
				hide(g)
			else
				-- coupé par son module : il ne sera pas rallumé
				local i = table.find(hidden, g)
				if i then
					table.remove(hidden, i)
				end
			end
		end)
	)
end

local function hideAll()
	local pg = playerGui()
	if pg == nil then
		return
	end
	for _, child in pg:GetChildren() do
		watch(child)
	end
	table.insert(
		watchers,
		pg.ChildAdded:Connect(function(child: Instance)
			if opened then
				watch(child)
			end
		end)
	)
end

local function showAll()
	for _, c in watchers do
		c:Disconnect()
	end
	table.clear(watchers)
	writing = true
	for _, g in hidden do
		if g.Parent ~= nil then
			g.Enabled = true
		end
	end
	writing = false
	table.clear(hidden)
end

-- =============================================================================================
-- Construction (une fois)
-- =============================================================================================

local function applyFilter()
	local t = tint
	if t == nil then
		return
	end
	local def = TINTS[PhotoHud.FILTERS[filterIndex]]
	t.Visible = def ~= nil
	if def then
		t.BackgroundColor3 = def.color
		t.BackgroundTransparency = def.transparency
	end
end

local function build()
	if screen ~= nil then
		return
	end
	local safe = Root.safe("PhotoHud", DISPLAY_ORDER)
	local gui = safe.Parent :: ScreenGui
	gui.Enabled = false
	screen = gui
	safeFrame = safe
	-- voile du filtre, plein écran (décoratif, sous tout le reste)
	local veil = Instance.new("Frame")
	veil.Name = "Tint"
	veil.BorderSizePixel = 0
	veil.ZIndex = 0
	veil.Visible = false
	veil.Active = false
	veil.Selectable = false
	Root.coverScreen(veil)
	veil.Parent = gui
	tint = veil

	-- bouton de sortie (bas, au centre)
	local b = Widgets.button({
		parent = safe,
		name = "Exit",
		size = UDim2.fromOffset(EXIT.w, EXIT.h),
		position = UDim2.new(0.5, 0, 1, -EXIT.bottom),
		anchor = Vector2.new(0.5, 1),
		color = Widgets.Colors.CardLight,
		zIndex = 3,
		onActivate = function()
			PhotoHud._exit()
		end,
	})
	exitButton = b
	local glyph = Widgets.glyph(
		b,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Backspace,
		Layout.Glyph.Min,
		UDim2.new(0, 20, 0.5, 0),
		Vector2.new(0, 0.5)
	)
	local label = Widgets.label({
		parent = b,
		name = "Label",
		size = UDim2.new(1, -(Layout.Glyph.Min + 56), 1, -12),
		position = UDim2.new(0, Layout.Glyph.Min + 36, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		key = "photo.exit",
		textSize = EXIT.text,
		zIndex = b.ZIndex + 1,
	})
	Widgets.followGlyph(label, glyph.frame, 20, 16, 20)

	-- aide (haut, à gauche)
	local rows = #HINTS
	local box = Widgets.frame({
		parent = safe,
		name = "Hint",
		size = UDim2.fromOffset(HINT.w, rows * HINT.row + 2 * HINT.pad),
		position = UDim2.fromOffset(24, 24),
		color = Widgets.Colors.Panel,
		transparency = 0.25,
		corner = Widgets.CORNER,
		zIndex = 2,
	})
	hint = box
	for i, row in HINTS do
		local line = Instance.new("Frame")
		line.Name = "Row" .. i
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, -2 * HINT.pad, 0, HINT.row)
		line.Position = UDim2.fromOffset(HINT.pad, HINT.pad + (i - 1) * HINT.row)
		line.Parent = box
		local x = 0
		local last: GuiObject? = nil
		for k, key in row.pad do
			local g = Widgets.glyph(
				line,
				key,
				row.keys[k],
				Layout.Glyph.Min,
				UDim2.new(0, x, 0.5, 0),
				Vector2.new(0, 0.5)
			)
			g.frame.Name = "Glyph" .. k
			last = g.frame
			x += Layout.Glyph.Min + HINT.glyphGap
		end
		local text = Widgets.label({
			parent = line,
			name = "Label",
			size = UDim2.new(1, -x, 1, 0),
			position = UDim2.new(0, x, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			key = row.key,
			textSize = HINT.text,
			xAlign = Enum.TextXAlignment.Left,
			zIndex = 4,
		})
		-- deux glyphes (L2 / R2, Page préc. / suiv.) : le second suit la largeur réelle du premier
		local first = line:FindFirstChild("Glyph1") :: GuiObject?
		if first and last and last ~= first then
			local second = last
			local function place()
				second.Position = UDim2.new(0, first.Size.X.Offset + HINT.glyphGap, 0.5, 0)
			end
			place()
			first:GetPropertyChangedSignal("Size"):Connect(place)
			Widgets.followGlyph(text, second, first.Size.X.Offset + HINT.glyphGap, HINT.glyphGap, 0)
		elseif first then
			Widgets.followGlyph(text, first, 0, HINT.glyphGap, 0)
		end
	end

	-- nom du filtre (haut, au centre), 2 s
	local nb = Widgets.frame({
		parent = safe,
		name = "FilterName",
		size = UDim2.fromOffset(NAME.w, NAME.h),
		position = UDim2.new(0.5, 0, 0, NAME.top),
		anchor = Vector2.new(0.5, 0),
		color = Widgets.Colors.Panel,
		transparency = 0.2,
		corner = Widgets.CORNER,
		zIndex = 2,
	})
	nb.Visible = false
	nameBox = nb
	nameLabel = Widgets.label({
		parent = nb,
		name = "Label",
		size = UDim2.new(1, -32, 1, -12),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		key = "photo.filter.none",
		textSize = NAME.text,
		zIndex = 3,
	})
end

local function onWindowClosed(name: string)
	if name ~= PhotoHud.WINDOW or not opened then
		return
	end
	local cb = exitCb
	PhotoHud.close()
	if cb then
		cb()
	end
end

local function onWindowOpened(name: string)
	-- une autre fenêtre (panneau ouvert par une carte, écran de retour…) : fin du mode photo
	if name ~= PhotoHud.WINDOW and opened then
		PhotoHud._exit()
	end
end

local function hook()
	if hooked then
		return
	end
	hooked = true
	FocusGuard.WindowClosed:Connect(onWindowClosed)
	FocusGuard.WindowOpened:Connect(onWindowOpened)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Ouvre l'écran du mode photo ; `onExit` est appelé une fois quand la fenêtre se ferme (○, ✕ sur le
-- bouton, clic, fenêtre fermée par FocusGuard ou remplacée par une autre)
function PhotoHud.open(onExit: (() -> ())?): boolean
	if opened then
		return true
	end
	hook()
	build()
	local gui, b, root = screen, exitButton, safeFrame
	if gui == nil or b == nil or root == nil then
		return false
	end
	opened = true
	exitCb = onExit
	filterIndex = 1
	applyFilter()
	lastInput = Clock.now()
	nameUntil = 0
	local nb = nameBox
	if nb then
		nb.Visible = false
	end
	local h = hint
	if h then
		h.Visible = true
	end
	hideAll()
	gui.Enabled = true
	FocusGuard.open({
		name = PhotoHud.WINDOW,
		root = root,
		blocking = true,
		default = function(): GuiObject?
			return exitButton
		end,
		onBack = function(): boolean
			return false -- ○ : la fenêtre se ferme, retour au jeu en un appui
		end,
		opener = nil,
	})
	return true
end

-- Ferme l'écran sans appeler onExit (CameraController.photo(false)) ; HUD rallumé à l'identique
function PhotoHud.close()
	if not opened then
		return
	end
	opened = false
	exitCb = nil
	local gui = screen
	if gui then
		gui.Enabled = false
	end
	showAll()
	if FocusGuard.isOpen(PhotoHud.WINDOW) then
		FocusGuard.closeNow(PhotoHud.WINDOW)
	end
	filterIndex = 1
	applyFilter()
end

-- Sortie voulue par le joueur (✕ ou clic sur le bouton) ou par une autre fenêtre : la fenêtre se
-- ferme, onExit suit (par WindowClosed)
function PhotoHud._exit()
	if not opened then
		return
	end
	if FocusGuard.isOpen(PhotoHud.WINDOW) then
		FocusGuard.closeNow(PhotoHud.WINDOW)
	else
		onWindowClosed(PhotoHud.WINDOW)
	end
end

function PhotoHud.isOpen(): boolean
	return opened
end

-- Un appui du mode photo : l'aide revient
function PhotoHud.noteInput()
	if not opened then
		return
	end
	lastInput = Clock.now()
	local h = hint
	if h and not h.Visible then
		h.Visible = true
	end
end

-- Filtre suivant ; son nom s'affiche 2 s
function PhotoHud.cycleFilter(): string
	filterIndex = filterIndex % #PhotoHud.FILTERS + 1
	applyFilter()
	local name = PhotoHud.FILTERS[filterIndex]
	local nb, nl = nameBox, nameLabel
	if opened and nb and nl then
		Widgets.setText(nl, "photo.filter." .. name)
		nb.Visible = true
		nameUntil = Clock.now() + NAME_TIME
	end
	return name
end

-- Effacement de l'aide (3 s sans appui) et du nom du filtre (2 s), sur l'horloge du jeu
function PhotoHud.tick()
	if not opened then
		return
	end
	local now = Clock.now()
	local h = hint
	if h and h.Visible and (now - lastInput >= HINT_FADE or now < lastInput - 1) then
		h.Visible = false
	end
	local nb = nameBox
	if nb and nb.Visible and (now >= nameUntil or now < nameUntil - NAME_TIME - 1) then
		nb.Visible = false
	end
end

function PhotoHud.filter(): string
	return PhotoHud.FILTERS[filterIndex]
end

-- ScreenGuis coupés par le mode photo (specs)
function PhotoHud.hidden(): { ScreenGui }
	return table.clone(hidden)
end

function PhotoHud.gui(): ScreenGui?
	return screen
end

function PhotoHud.exitButton(): TextButton?
	return exitButton
end

function PhotoHud.hintShown(): boolean
	local h = hint
	return opened and h ~= nil and h.Visible
end

function PhotoHud.nameShown(): boolean
	local nb = nameBox
	return opened and nb ~= nil and nb.Visible
end

return PhotoHud
