--!strict
-- Binoculars (lot B3, étape 5, D22 ; docs/04 §27.11 INT-B3-BINOCULARS ; GDD v2.0 §7.5, §13) : les
-- jumelles et les cœurs. Depuis la rue, devant le portail du ranch d'un voisin (invite □ « Regarder » de
-- PromptController, routée par InputController comme le kiosque), une petite fenêtre de FocusGuard
-- (« binoculars », ouverte depuis le jeu : ○ y ramène) porte UN bouton, « Donner un cœur » :
--   * ✕ (InputBegan capté, jugé par l'InputGuard de FocusGuard : un ✕ tenu depuis le saut, ou appuyé
--     pendant la garde d'ouverture, n'envoie jamais rien ; jamais Activated) ou le clic → GiveHeart(ownerId),
--     une intention par appui, puis plus rien pendant PENDING s (la réponse arrive par DataPatch) ;
--   * « Cœur donné ! » (grisé) quand mon profil porte déjà ce propriétaire aujourd'hui
--     (hearts.givenTo, hearts.givenDay == Clock.day()) ; « Plus de cœurs aujourd'hui » (grisé) à
--     Balance.Hearts.PerDay ; le bouton suit le profil répliqué (aucune prédiction) ;
--   * aucun nom du propriétaire, aucun compteur (GDD §13 : jumelles en lecture seule, sans texte) ;
--     le zoom de la caméra est au lot B5.
-- Seulement interrupteur Hearts ouvert et profil v2 (UI/MetaFlags) : sinon open() ne fait rien (aucune
-- fenêtre, aucune intention). Construite une fois, à la première ouverture ; jamais un objet créé ou
-- détruit pendant qu'elle est ouverte. Le serveur revérifie tout (CommunityService, refus muets).
--
--   Binoculars.open(ownerId) : boolean   -- ouvre sur le ranch de ce joueur (faux : rien d'ouvert)
--   Binoculars.close()                   -- referme (○ fait de même)
--   Binoculars.isOpen() : boolean
--   Binoculars.state() : "give" | "given" | "limit" | nil  -- état du bouton (specs)
--   Binoculars.button() : TextButton?    -- le bouton du cœur (specs)

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Layout = require(Shared.Config.Layout)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Juice = require(Client.UI.Juice)
local FocusGuard = require(Client.UI.FocusGuard)
local AudioController = require(Client.Controllers.AudioController)
local State = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Widgets = require(Client.UI.Panels.Widgets)
local Icons = require(Client.UI.Hud.Icons)
local MetaFlags = require(Client.UI.MetaFlags)

local Binoculars = {}

Binoculars.WINDOW = "binoculars"

export type State = "give" | "given" | "limit"

local DISPLAY_ORDER = 42 -- au-dessus des cartes (40), sous l'écran de retour (45)
local CARD = { w = 720, h = 152 } -- px TV
local BUTTON = { w = 656, h = 112, text = 40 }
local BOTTOM = 216 -- px TV entre le bas de la zone sûre et la carte (au-dessus des puces du bas)
local HEART = 56 -- px TV : cœur dessiné du bouton
local PER_DAY = Balance.Hearts.PerDay
local PENDING = 3 -- s : un seul GiveHeart en vol (la réponse du serveur arrive par DataPatch)
local MAX_GIVEN = 64 -- entrées lues de hearts.givenTo au plus (le serveur en garde PerDay)
local CONFIRM_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
}

local gui: ScreenGui? = nil
local card: Frame? = nil
local button: TextButton? = nil
local label: TextLabel? = nil
local heart: Frame? = nil
local opened = false
local owner = 0 -- userId du propriétaire regardé
local current: State? = nil
local pendingUntil = -math.huge
local hooked = false

-- =============================================================================================
-- État
-- =============================================================================================

local function localUserId(): number
	local player = Players.LocalPlayer
	return if player then player.UserId else 0
end

-- Interrupteur Hearts ouvert et profil v2 (sinon : jamais de fenêtre, jamais d'intention)
local function allowed(): boolean
	return MetaFlags.on("Hearts") and MetaFlags.v2Profile()
end

-- Le propriétaire est-il toujours sur ce serveur, à son ranch ?
local function ownerPresent(userId: number): boolean
	for slot = 1, WorldLayout.Const.Ranches do
		local ok, r = pcall(WorldStateController.ranch, slot)
		if ok and type(r) == "table" and r.userId == userId then
			return true
		end
	end
	return false
end

-- État du bouton d'après MON profil répliqué (hearts.givenDay, hearts.givenTo) ; valeur abîmée : « give »
local function stateFor(userId: number): State
	local ok, hearts = pcall(State.get, "hearts")
	if not ok or type(hearts) ~= "table" or rawget(hearts, "givenDay") ~= Clock.day() then
		return "give"
	end
	local list = rawget(hearts, "givenTo")
	if type(list) ~= "table" then
		return "give"
	end
	local n = 0
	for i = 1, MAX_GIVEN do
		local id = rawget(list, i)
		if id == nil then
			break
		end
		n += 1
		if id == userId then
			return "given"
		end
	end
	return if n >= PER_DAY then "limit" else "give"
end

local KEYS: { [State]: string } = {
	give = "hearts.give",
	given = "hearts.given",
	limit = "hearts.limit",
}

local function refresh()
	local b, l, h = button, label, heart
	if not opened or b == nil or l == nil or h == nil then
		return
	end
	local s = stateFor(owner)
	if s == current then
		return
	end
	current = s
	Widgets.setText(l, KEYS[s])
	Widgets.setDisabled(b, s ~= "give")
	Icons.paint(h, if s == "limit" then Widgets.Colors.Locked else Widgets.Colors.Pink)
	b:SetAttribute("HeartState", s)
end

-- =============================================================================================
-- Construction (une fois)
-- =============================================================================================

local function send()
	if not opened or current ~= "give" then
		return
	end
	local now = Clock.now()
	if now < pendingUntil and now >= pendingUntil - PENDING then
		return -- un cœur déjà en route : la réponse arrive par le profil
	end
	if not allowed() or owner <= 0 or owner == localUserId() or not ownerPresent(owner) then
		Binoculars.close()
		return
	end
	if Widgets.send("GiveHeart", owner) then
		pendingUntil = now + PENDING
		AudioController.play("Click")
		local b = button
		if b and not Juice.reducedMotion() then
			Juice.pulse(b, 1.06)
		end
	end
end

-- Appui capté (✕, Entrée) sur le bouton sélectionné : jamais Activated ; jugé par l'InputGuard
local function onInput(input: InputObject)
	if not opened or not CONFIRM_KEYS[input.KeyCode] then
		return
	end
	local okGuard, clean = pcall(FocusGuard.notePress, input)
	if okGuard and clean ~= true then
		return
	end
	local b = button
	if b == nil or GuiService.SelectedObject ~= b then
		return
	end
	-- bouton grisé (cœur donné, plafond) : la réaction de refus vient de Widgets.button (Activated)
	send()
end

local function build()
	if card ~= nil then
		return
	end
	local safeFrame = Root.safe("Binoculars", DISPLAY_ORDER)
	local screen = safeFrame.Parent :: ScreenGui
	gui = screen
	screen.Enabled = false
	local f = Widgets.frame({
		parent = safeFrame,
		name = "Card",
		size = UDim2.fromOffset(CARD.w, CARD.h),
		position = UDim2.new(0.5, 0, 1, -BOTTOM),
		anchor = Vector2.new(0.5, 1),
		color = Widgets.Colors.Panel,
		corner = Widgets.CORNER_LARGE,
		gradient = true,
		zIndex = 2,
	})
	card = f
	local b = Widgets.button({
		parent = f,
		name = "Heart",
		size = UDim2.fromOffset(BUTTON.w, BUTTON.h),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Widgets.Colors.CardLight,
		sound = "",
		zIndex = 3,
	})
	button = b
	local glyphSize = Layout.Glyph.Min
	local glyph = Widgets.glyph(
		b,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.Return,
		glyphSize,
		UDim2.new(0, 20, 0.5, 0),
		Vector2.new(0, 0.5)
	)
	local h = Icons.new("heart", HEART, Widgets.Colors.Pink, b)
	h.Name = "HeartIcon"
	h.AnchorPoint = Vector2.new(0, 0.5)
	h.ZIndex = b.ZIndex + 1
	heart = h
	local l = Widgets.label({
		parent = b,
		name = "Label",
		size = UDim2.new(1, -(glyphSize + HEART + 72), 1, -16),
		position = UDim2.new(0, glyphSize + HEART + 52, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		key = "hearts.give",
		textSize = BUTTON.text,
		zIndex = b.ZIndex + 1,
	})
	label = l
	-- le cœur et le texte suivent la largeur RÉELLE du glyphe (« Enter » au clavier élargit la pastille)
	local function place()
		local x = 20 + glyph.frame.Size.X.Offset + 16
		h.Position = UDim2.new(0, x, 0.5, 0)
		l.Position = UDim2.new(0, x + HEART + 16, 0.5, 0)
		l.Size = UDim2.new(1, -(x + HEART + 16 + 20), 1, -16)
	end
	place()
	glyph.frame:GetPropertyChangedSignal("Size"):Connect(place)
	-- souris : clic sur le bouton (InputGuard de FocusGuard)
	b.MouseButton1Down:Connect(function()
		if opened and Widgets.confirmed() then
			send()
		end
	end)
end

local function onWindowClosed(name: string)
	if name ~= Binoculars.WINDOW then
		return
	end
	opened = false
	owner = 0
	current = nil
	local screen = gui
	if screen then
		screen.Enabled = false
	end
end

local function hook()
	if hooked then
		return
	end
	hooked = true
	FocusGuard.WindowClosed:Connect(onWindowClosed)
	UserInputService.InputBegan:Connect(onInput)
	-- le bouton suit le profil répliqué (cœur donné, plafond du jour)
	State.observe("hearts", function()
		refresh()
	end)
	-- interrupteur coupé en direct : la fenêtre se referme
	MetaFlags.Changed:Connect(function()
		if opened and not allowed() then
			Binoculars.close()
		end
	end)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Ouvre les jumelles sur le ranch de `ownerId` (un autre joueur, présent) ; faux : rien d'ouvert
function Binoculars.open(ownerId: number): boolean
	if type(ownerId) ~= "number" or ownerId ~= ownerId or ownerId <= 0 or ownerId % 1 ~= 0 then
		return false
	end
	if ownerId == localUserId() or not allowed() or not ownerPresent(ownerId) then
		return false
	end
	if opened then
		return owner == ownerId
	end
	hook()
	build()
	local f, b = card, button
	if f == nil or b == nil then
		return false
	end
	owner = ownerId
	current = nil
	opened = true
	refresh()
	local screen = gui :: ScreenGui
	screen.Enabled = true
	if not Juice.reducedMotion() then
		Juice.popIn(f)
	end
	AudioController.play("Whoosh")
	FocusGuard.open({
		name = Binoculars.WINDOW,
		root = f,
		blocking = false,
		default = function(): GuiObject?
			return button
		end,
		onBack = function(): boolean
			return false -- ○ referme : retour au jeu
		end,
		opener = nil,
	})
	return true
end

function Binoculars.close()
	if opened then
		FocusGuard.close(Binoculars.WINDOW)
	end
end

function Binoculars.isOpen(): boolean
	return opened
end

function Binoculars.state(): State?
	return if opened then current else nil
end

function Binoculars.button(): TextButton?
	return button
end

return Binoculars
