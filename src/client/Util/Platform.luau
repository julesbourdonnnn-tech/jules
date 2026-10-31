--!strict
-- Platform : plateforme, écran et périphérique d'entrée du joueur local (docs/07-console-ps5.md §2-§6).
--   * console : GuiService:IsTenFootInterface() (seule détection garantie, appelée sous pcall)
--   * écran : GuiService.ViewportDisplaySize (Large = téléviseur) ; écran « 10 pieds » = console
--     ou écran Large
--   * entrée préférée (1 tactile, 2 clavier-souris, 3 manette ; même codage que InputController et
--     l'analytique SnipByInput) : la plus récente de UserInputService.PreferredInput et
--     LastInputTypeChanged ; console sans autre indice : manette
--   * glyphes : Platform.glyph(keyCode) → image Roblox de la touche
--     (UserInputService:GetImageForKeyCode : icônes PlayStation sur PlayStation) et texte de repli
--     neutre (jamais les lettres Xbox : ButtonX est le Carré d'une DualSense)
--   * échelle et zone sûre : Platform.uiScale / Platform.safePadding (Config/Console)
--   * règle « pas de fenêtre de chat sur console » (Start) : fenêtre de chat du CoreGui coupée
--     (StarterGui:SetCoreGuiEnabled(Chat, false) : ancien chat comme TextChatService, nouveaux
--     essais bornés si le CoreGui n'est pas prêt), ChatWindowConfiguration et
--     ChatInputBarConfiguration désactivées ; les bulles restent
--   * Platform.Changed(raison) : "input" (entrée préférée), "display" (taille d'écran), "gamepad"
--     (manette branchée / débranchée)
-- Sans dépendance vers les autres modules du client : Root (1er de Main.client) l'utilise. Les
-- lectures fonctionnent avant Init (valeurs lues à la demande).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Console = require(Shared.Config.Console)

local Platform = {}

Platform.TOUCH = 1
Platform.KEYBOARD = 2
Platform.GAMEPAD = 3

-- raison : "input" | "display" | "gamepad"
Platform.Changed = Signal.new() :: Signal.Signal<string>

-- Position d'un bouton de façade (repli dessiné en losange, docs/07 §5)
export type Slot = "top" | "bottom" | "left" | "right"

export type Glyph = {
	keyCode: Enum.KeyCode,
	gamepad: boolean, -- touche de manette (sinon clavier / souris)
	image: string?, -- icône Roblox (GetImageForKeyCode), nil si indisponible
	text: string, -- texte de repli ("" pour un bouton de façade : losange)
	slot: Slot?, -- bouton de façade : position dans le losange
}

-- Repli neutre des touches de manette : positions et numéros, jamais de lettre Xbox
local FACE: { [string]: Slot } = {
	ButtonA = "bottom",
	ButtonB = "right",
	ButtonX = "left",
	ButtonY = "top",
}
local PAD_TEXT: { [string]: string } = {
	ButtonL1 = "L1",
	ButtonR1 = "R1",
	ButtonL2 = "L2",
	ButtonR2 = "R2",
	ButtonL3 = "L3",
	ButtonR3 = "R3",
	ButtonSelect = "▭",
	ButtonStart = "≡",
	DPadUp = "↑",
	DPadDown = "↓",
	DPadLeft = "←",
	DPadRight = "→",
	Thumbstick1 = "L",
	Thumbstick2 = "R",
}
-- Noms courts des touches spéciales du clavier
local KEY_TEXT: { [string]: string } = {
	LeftShift = "Shift",
	RightShift = "Shift",
	LeftControl = "Ctrl",
	RightControl = "Ctrl",
	LeftAlt = "Alt",
	RightAlt = "Alt",
	Escape = "Esc",
	Return = "Enter",
	KeypadEnter = "Enter",
	Space = "Space",
	Tab = "Tab",
	Backspace = "⌫",
	Up = "↑",
	Down = "↓",
	Left = "←",
	Right = "→",
}

local initialized = false
local started = false
local kind: number? = nil -- nil : pas encore déterminée (lecture à la demande)

-- Plateforme -----------------------------------------------------------------------------------

-- Console (Xbox, PlayStation) : seule détection garantie par Roblox ; false si l'appel échoue
function Platform.isTenFoot(): boolean
	local ok, result = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and result == true
end

function Platform.displaySize(): Enum.DisplaySize
	local ok, result = pcall(function()
		return GuiService.ViewportDisplaySize
	end)
	if ok and typeof(result) == "EnumItem" then
		return result :: Enum.DisplaySize
	end
	return Enum.DisplaySize.Medium
end

-- Écran « 10 pieds » : console, ou écran Large (la plupart des téléviseurs)
function Platform.isLargeDisplay(): boolean
	return Platform.isTenFoot() or Platform.displaySize() == Enum.DisplaySize.Large
end

-- La fenêtre de chat est-elle permise ? (non sur console, docs/07 §7)
function Platform.chatWindowAllowed(): boolean
	return not Platform.isTenFoot()
end

-- Entrée ----------------------------------------------------------------------------------------

-- Type d'entrée Roblox → 1 tactile, 2 clavier-souris, 3 manette (nil : sans effet, ex. Focus)
function Platform.kindFor(inputType: Enum.UserInputType): number?
	if inputType == Enum.UserInputType.Touch then
		return Platform.TOUCH
	end
	if
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return Platform.KEYBOARD
	end
	if string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return Platform.GAMEPAD
	end
	return nil
end

local function kindForPreferred(value: any): number?
	if typeof(value) ~= "EnumItem" then
		return nil
	end
	local name = (value :: EnumItem).Name
	if name == "Gamepad" or name == "MicroGamepad" then
		return Platform.GAMEPAD
	elseif name == "Touch" then
		return Platform.TOUCH
	elseif name == "KeyboardAndMouse" then
		return Platform.KEYBOARD
	end
	return nil
end

local function readPreferred(): number?
	local ok, value = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	return if ok then kindForPreferred(value) else nil
end

local function detect(): number
	if Platform.isTenFoot() then
		return Platform.GAMEPAD
	end
	local preferred = readPreferred()
	if preferred then
		return preferred
	end
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and typeof(last) == "EnumItem" then
		local k = Platform.kindFor(last :: Enum.UserInputType)
		if k then
			return k
		end
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return Platform.GAMEPAD
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return Platform.TOUCH
	end
	return Platform.KEYBOARD
end

-- Entrée préférée du joueur : 1 tactile, 2 clavier-souris, 3 manette
function Platform.inputKind(): number
	local k = kind
	if k == nil then
		k = detect()
		if initialized then
			kind = k
		end
	end
	return k
end

function Platform.usingGamepad(): boolean
	return Platform.inputKind() == Platform.GAMEPAD
end

-- Une manette est-elle branchée ?
function Platform.gamepadConnected(): boolean
	local ok, result = pcall(function()
		return UserInputService.GamepadEnabled
	end)
	return ok and result == true
end

local function setKind(k: number?)
	if k == nil then
		return
	end
	local previous = Platform.inputKind()
	kind = k
	if k ~= previous then
		Platform.Changed:Fire("input")
	end
end

-- Glyphes ---------------------------------------------------------------------------------------

function Platform.isGamepadKey(keyCode: Enum.KeyCode): boolean
	local name = keyCode.Name
	return string.sub(name, 1, 6) == "Button"
		or string.sub(name, 1, 4) == "DPad"
		or string.sub(name, 1, 10) == "Thumbstick"
end

local function imageFor(keyCode: Enum.KeyCode): string?
	local ok, result = pcall(function()
		return UserInputService:GetImageForKeyCode(keyCode)
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end
	return nil
end

local function keyText(keyCode: Enum.KeyCode): string
	local special = KEY_TEXT[keyCode.Name]
	if special then
		return special
	end
	-- disposition du clavier du joueur (AZERTY : KeyCode.Q s'écrit « A »)
	local ok, result = pcall(function()
		return UserInputService:GetStringForKeyCode(keyCode)
	end)
	if
		ok
		and type(result) == "string"
		and result ~= ""
		and utf8.len(result) ~= nil
		and (utf8.len(result) :: number) <= 3
	then
		return string.upper(result)
	end
	return keyCode.Name
end

-- Glyphe d'une touche : image Roblox pour la manette (PlayStation sur PlayStation), sinon repli
-- texte neutre ; clavier : texte de la touche selon la disposition du joueur
function Platform.glyph(keyCode: Enum.KeyCode): Glyph
	if Platform.isGamepadKey(keyCode) then
		local name = keyCode.Name
		return {
			keyCode = keyCode,
			gamepad = true,
			image = imageFor(keyCode),
			text = PAD_TEXT[name] or "",
			slot = FACE[name],
		}
	end
	return { keyCode = keyCode, gamepad = false, image = nil, text = keyText(keyCode), slot = nil }
end

-- Échelle et zone sûre --------------------------------------------------------------------------

local function viewportOr(viewport: Vector2?): Vector2?
	if viewport then
		return viewport
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else nil
end

-- UIScale commun des écrans (docs/07 §3) : écran ordinaire clamp(min(L/1280, H/720), 0,6, 1,25) ;
-- écran Large ou console max(0,6, min(L/1280, H/720)) (1,5 en 1920 × 1080)
function Platform.uiScale(viewport: Vector2?, large: boolean?): number
	local size = viewportOr(viewport)
	if size == nil or size.X <= 1 or size.Y <= 1 then
		return 1
	end
	local s = math.min(size.X / Console.Reference.X, size.Y / Console.Reference.Y)
	local isLarge = if large == nil then Platform.isLargeDisplay() else large
	if isLarge then
		return math.max(s, Console.TvScale.Min)
	end
	return math.clamp(s, Console.Scale.Min, Console.Scale.Max)
end

-- Marges intérieures de Root.safe (px de référence, horizontale et verticale) : marges ordinaires,
-- ou zone sûre TV (5 % de l'écran de chaque côté) sur écran Large / console (docs/07 §4)
function Platform.safePadding(viewport: Vector2?, large: boolean?): Vector2
	local base = Vector2.new(Console.BasePadding.X, Console.BasePadding.Y)
	local isLarge = if large == nil then Platform.isLargeDisplay() else large
	local size = viewportOr(viewport)
	if not isLarge or size == nil or size.X <= 1 or size.Y <= 1 then
		return base
	end
	local s = Platform.uiScale(size, true)
	local x = math.ceil(size.X * Console.TvSafeMargin / s)
	local y = math.ceil(size.Y * Console.TvSafeMargin / s)
	return Vector2.new(math.max(base.X, x), math.max(base.Y, y))
end

-- Chat (docs/07 §7) ---------------------------------------------------------------------------

local CHAT_CONFIGS = { "ChatWindowConfiguration", "ChatInputBarConfiguration" }
local CHAT_CORE_RETRY = Console.ChatCoreRetry -- s entre deux essais de SetCoreGuiEnabled

-- Fenêtre de chat du CoreGui coupée : vaut pour l'ancien chat comme pour TextChatService, que le
-- moteur ait créé ou non les configurations ; nouveaux essais pendant Console.ChatWaitTimeout si le
-- CoreGui n'est pas encore prêt (avertissement seulement si tous échouent)
local function disableCoreChat()
	task.spawn(function()
		local waited = 0
		while true do
			local ok, err = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
			end)
			if ok then
				return
			end
			if waited >= Console.ChatWaitTimeout then
				warn("[Platform] chat (CoreGui) :", err)
				return
			end
			task.wait(CHAT_CORE_RETRY)
			waited += CHAT_CORE_RETRY
		end
	end)
end

-- Sur console : fenêtre de chat du CoreGui coupée, fenêtre et barre de saisie de TextChatService
-- désactivées (attente bornée des configurations créées par le moteur) ; ailleurs : rien n'est
-- changé
function Platform.applyChatRule()
	if Platform.chatWindowAllowed() then
		return
	end
	disableCoreChat()
	for _, className in CHAT_CONFIGS do
		task.spawn(function()
			local config = TextChatService:FindFirstChildOfClass(className)
				or TextChatService:WaitForChild(className, Console.ChatWaitTimeout)
			if config == nil then
				return -- ancien chat ou configuration absente : rien à désactiver ici
			end
			local ok, err = pcall(function()
				(config :: any).Enabled = false
			end)
			if not ok then
				warn("[Platform] chat :", err)
			end
		end)
	end
end

-- Cycle de vie ----------------------------------------------------------------------------------

function Platform.Init()
	if initialized then
		return
	end
	initialized = true
	kind = detect()
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		setKind(Platform.kindFor(inputType))
	end)
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			setKind(readPreferred())
		end)
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("ViewportDisplaySize"):Connect(function()
			Platform.Changed:Fire("display")
		end)
	end)
	pcall(function()
		UserInputService.GamepadConnected:Connect(function()
			Platform.Changed:Fire("gamepad")
		end)
		UserInputService.GamepadDisconnected:Connect(function()
			Platform.Changed:Fire("gamepad")
		end)
	end)
end

function Platform.Start()
	if started then
		return
	end
	started = true
	Platform.Init()
	Platform.applyChatRule()
end

return Platform
