--!strict
-- InputController (paquet client-hud, docs/04 §3.4, §13.5, §14.2, §14.6) : commandes (GDD §10.4) par
-- ContextActionService:BindActionAtPriority, manette d'abord puis clavier-souris, aucune commande
-- tactile.
--   * Touches du jeu, liées SEULEMENT quand aucune fenêtre n'est ouverte (FocusGuard.anyOpen,
--     signaux WindowOpened / WindowClosed, plus un contrôle à 4 Hz en filet) :
--     □ / E = action principale de la cible de PromptController (presser, lancer, acheter, attraper,
--     pet-sitting, MEGA ; maintiens Begin / End pour le boop et le bol : BoopHold / FeedPlop true puis
--     false, l'anneau suit l'heure du serveur) ; un clic gauche sur un squishy fixe la cible 4 s
--     (PromptController.clickAt) puis agit ; ○ / Q = Prendre / Poser ; R2 / Maj = Bondir ; L2 / R =
--     Monter ; L1 / R1 = changer de cible ; croix ↑ → ← et 1 2 3 = emotes (débit client 1 / 1,5 s) ;
--     croix → devient Applaudir (Clap) tant que HUD.clapHero() rend un héros ; F = Applaudir.
--     Pendant un portage, R2 et L2 jouent Bump et ne font rien (pas de vibration).
--   * △ / croix ↓ / M = Menu (PanelController.toggleMenu) : InputController est le SEUL module qui
--     les lie. M est lié par KeyCode.M ET KeyCode.Semicolon (la touche marquée « M » en AZERTY),
--     JAMAIS Tab (liste des joueurs de Roblox). Fenêtre non bloquante ouverte : △ et M restent liés
--     (△ ferme tout), croix ↓ est rendue à la navigation ; fenêtre bloquante (carte du choix, écran
--     de retour) : rien n'est lié. Avant la leçon du menu (étape 10 de l'accueil), △ / croix ↓ / M
--     et les raccourcis ne jouent qu'un petit son Bump.
--   * Raccourcis directs du clavier G C J L B P → PanelController.open(Ranch, Squishydex, Objectives,
--     Leaderboards, Shop, Settings) (Config/Layout.Keyboard.Panels).
--   * Sac à objets de Roblox coupé (StarterGui:SetCoreGuiEnabled(Backpack, false) sous pcall, nouveaux
--     essais pendant Layout.Keyboard.BackpackRetry s) pour que 1, 2, 3 ne servent qu'aux emotes.
--   * ○ en portant : un menu ouvert se ferme d'abord (FocusGuard lie ○ dans les fenêtres), puis ○ pose.
--   * Échap, Options, ButtonSelect, L3 et R3 ne sont JAMAIS liés.
-- Vibrations holdStart (début d'un maintien) et holdDone (maintien réussi). Temps : Clock.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)

local Client = script.Parent.Parent
local Haptics = require(Client.Util.Haptics)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local PromptController = require(Client.Controllers.PromptController)
local ChaseController = require(Client.Controllers.ChaseController)
local FocusGuard = require(Client.UI.FocusGuard)
local PanelController = require(Client.UI.PanelController)
local HUD = require(Client.UI.HUD)
local Prompt = require(Client.UI.Prompt)
local Util = require(Client.UI.Hud.Util)
local Lesson = require(Client.UI.Hud.Lesson)

local InputController = {}

-- (action jouée : "press", "pickup", "leap"…)
InputController.Action = Signal.new() :: Signal.Signal<string>

local GAME_PRIORITY = Enum.ContextActionPriority.High.Value
local MENU_PRIORITY = Enum.ContextActionPriority.High.Value + 50
local CHECK_EVERY = 0.25 -- s : contrôle des liaisons en filet des signaux de FocusGuard
local BACKPACK_GAP = 1 -- s entre deux essais de SetCoreGuiEnabled(Backpack, false)

local A_PRIMARY = "HudPrimary"
local A_SECONDARY = "HudSecondary"
local A_LEAP = "HudLeap"
local A_RIDE = "HudRide"
local A_CYCLE = "HudCycle"
local A_EMOTE = "HudEmote"
local A_MENU = "HudMenu"
local A_PANELS = "HudPanels"

local GAME_ACTIONS = { A_PRIMARY, A_SECONDARY, A_LEAP, A_RIDE, A_CYCLE, A_EMOTE }

type Hold = { kind: string, ownerId: number, uid: string, byMouse: boolean }

local started = false
local gameIsBound = false
local menuMode = "" -- "" | "full" | "window" | "none"
local panelsBound = false
local hold: Hold? = nil
local checkAcc = 0
local backpackDone = false
local backpackOk = false
local backpackTries = 0
local backpackNextTry = -math.huge
local panelKeys: { [Enum.KeyCode]: string } = {}
local menuKeys: { Enum.KeyCode } = {}

for name, letter in Layout.Keyboard.Panels do
	local ok, key = pcall(function()
		return (Enum.KeyCode :: any)[letter]
	end)
	if ok and typeof(key) == "EnumItem" then
		panelKeys[key :: Enum.KeyCode] = name
	end
end
for _, name in Layout.Keyboard.Menu do
	local ok, key = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and typeof(key) == "EnumItem" then
		table.insert(menuKeys, key :: Enum.KeyCode)
	end
end

-- =============================================================================================
-- Outils
-- =============================================================================================

local function keyOf(input: any): Enum.KeyCode?
	if type(input) == "table" or typeof(input) == "InputObject" then
		local ok, key = pcall(function()
			return input.KeyCode
		end)
		if ok and typeof(key) == "EnumItem" then
			return key
		end
	end
	return nil
end

local function myRanch(): { [string]: any }?
	local slot = Util.num(Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot), 0, 0, 64)
	if slot <= 0 then
		return nil
	end
	local ranch = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
	return if type(ranch) == "table" then ranch else nil
end

local function carrying(): boolean
	local ranch = myRanch()
	return ranch ~= nil and type(ranch.carry) == "string" and ranch.carry ~= ""
end

local function ownerOf(slot: any): number
	local s = Util.num(slot, 0, 0, 64)
	if s <= 0 then
		return 0
	end
	local ranch = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, s)
	return if type(ranch) == "table" then Util.num(ranch.userId, 0, 0, 2 ^ 53) else 0
end

local function target(): { [string]: any }?
	local t = Util.safe("PromptController.current", nil, PromptController.current)
	return if type(t) == "table" then t else nil
end

-- Leçon du menu commencée ou passée (Hud/Lesson : étape de l'accueil, filet de temps)
local function menuUnlocked(): boolean
	return Lesson.menuUnlocked(Clock.now())
end

local function fire(action: string)
	InputController.Action:Fire(action)
end

local function bump()
	AudioController.play("Bump")
end

-- =============================================================================================
-- Actions du jeu
-- =============================================================================================

local function endHold()
	local h = hold
	if h == nil then
		return
	end
	hold = nil
	if h.kind == "boop" then
		Util.send("BoopHold", h.ownerId, h.uid, false)
	elseif h.kind == "feed" then
		Util.send("FeedPlop", false)
	end
	Util.safe("PromptController.unlock", nil, PromptController.unlock)
end

local function startHold(kind: string, ownerId: number, uid: string, byMouse: boolean)
	endHold()
	local sent = if kind == "boop"
		then Util.send("BoopHold", ownerId, uid, true)
		else Util.send("FeedPlop", true)
	if not sent then
		return
	end
	hold = { kind = kind, ownerId = ownerId, uid = uid, byMouse = byMouse }
	Util.safe("PromptController.lock", nil, PromptController.lock, if kind == "boop" then "boop" else "bowl")
	Haptics.play("holdStart")
	fire(kind)
end

-- Action principale (□ / E / clic) sur la cible de PromptController
local function primaryBegin(byMouse: boolean)
	local t = target()
	if t == nil or t.primary == "" or t.primary == nil then
		-- poursuite : un appui juste avant d'arriver à portée est gardé 0,25 s (ChaseController)
		if Util.safe("ChaseController.tryCatch", false, ChaseController.tryCatch) then
			fire("catch")
		end
		return
	end
	local p = t.primary
	local now = Clock.now()
	local uid = Util.str(t.uid, "", 16)
	if p == "press" then
		if t.kind == "mega" then
			if Util.send("MegaPress", now) then
				fire("press")
			end
			return
		end
		if t.ready == false or uid == "" then
			bump()
			return
		end
		if Util.send("Press", uid, now) then
			Util.safe("PromptController.afterPress", nil, PromptController.afterPress)
			fire("press")
		end
	elseif p == "petsit" then
		local owner = ownerOf(t.slot)
		if owner > 0 and uid ~= "" and Util.send("PetPress", owner, uid, now) then
			Util.safe("PromptController.afterPress", nil, PromptController.afterPress)
			fire("press")
		end
	elseif p == "throw" or p == "fusion" or p == "putInPool" then
		if Util.send("Throw") then
			fire("throw")
		end
	elseif p == "buy" then
		local tile = Util.str(t.tile, "", 16)
		if tile ~= "" and Util.send("BuyTile", tile) then
			fire("buy")
		end
	elseif p == "boop" then
		local owner = ownerOf(t.slot)
		if owner > 0 and uid ~= "" then
			startHold("boop", owner, uid, byMouse)
		end
	elseif p == "feed" then
		startHold("feed", 0, "", byMouse)
	elseif p == "catch" then
		if Util.safe("ChaseController.tryCatch", false, ChaseController.tryCatch) then
			fire("catch")
		end
	elseif p == "sell" then
		Util.safe("PanelController.open", nil, PanelController.open, "Ranch", "sell")
		fire("sell")
	elseif p == "shop" then
		Util.safe("PanelController.open", nil, PanelController.open, "Shop")
		fire("shop")
	end
end

-- ○ / Q : Prendre / Poser
local function secondary()
	local t = target()
	local s = if t then t.secondary else nil
	if s == "pickup" and t then
		local uid = Util.str(t.uid, "", 16)
		if uid ~= "" and Util.send("PickUp", uid) then
			fire("pickup")
		end
	elseif s == "putdown" or carrying() then
		if Util.send("PutDown") then
			fire("putdown")
		end
	end
end

local function emote(kind: number)
	if Util.send("Emote", kind) then
		fire("emote")
	end
end

local function onGameAction(name: string, state: Enum.UserInputState, input: any): Enum.ContextActionResult
	local key = keyOf(input)
	if name == A_PRIMARY then
		if state == Enum.UserInputState.Begin then
			primaryBegin(false)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			local h = hold
			if h and not h.byMouse then
				endHold()
			end
		end
		return Enum.ContextActionResult.Sink
	end
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if name == A_SECONDARY then
		secondary()
	elseif name == A_LEAP then
		if carrying() then
			bump()
		elseif Util.safe("ChaseController.leap", false, ChaseController.leap) then
			fire("leap")
		end
	elseif name == A_RIDE then
		if carrying() then
			bump()
		else
			local ranch = myRanch()
			local riding = ranch ~= nil and type(ranch.ride) == "string" and ranch.ride ~= ""
			if Util.send("Ride", not riding) then
				fire("ride")
			end
		end
	elseif name == A_CYCLE then
		local dir = if key == Enum.KeyCode.ButtonL1 then -1 else 1
		Util.safe("PromptController.cycle", nil, PromptController.cycle, dir)
		fire("cycle")
	elseif name == A_EMOTE then
		if key == Enum.KeyCode.F then
			if Util.safe("HUD._clap", false, HUD._clap) then
				fire("clap")
			end
		elseif key == Enum.KeyCode.DPadRight then
			-- croix → : Applaudir pendant la fenêtre du Grand Splorch d'un autre (8 s), sinon « merci »
			if Util.safe("HUD.clapHero", nil, HUD.clapHero) ~= nil then
				if Util.safe("HUD._clap", false, HUD._clap) then
					fire("clap")
				end
			else
				emote(2)
			end
		elseif key == Enum.KeyCode.Two then
			emote(2)
		elseif key == Enum.KeyCode.DPadUp or key == Enum.KeyCode.One then
			emote(1)
		elseif key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.Three then
			emote(3)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onMenu(_name: string, state: Enum.UserInputState, _input: any): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if not menuUnlocked() then
		bump() -- avant la leçon du menu
		return Enum.ContextActionResult.Sink
	end
	endHold()
	Util.safe("PanelController.toggleMenu", nil, PanelController.toggleMenu)
	fire("menu")
	return Enum.ContextActionResult.Sink
end

local function onPanels(_name: string, state: Enum.UserInputState, input: any): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local key = keyOf(input)
	local panel = if key then panelKeys[key] else nil
	if panel == nil then
		return Enum.ContextActionResult.Pass
	end
	if not menuUnlocked() then
		bump()
		return Enum.ContextActionResult.Sink
	end
	endHold()
	Util.safe("PanelController.open", nil, PanelController.open, panel)
	fire("panel")
	return Enum.ContextActionResult.Sink
end

-- =============================================================================================
-- Liaisons
-- =============================================================================================

local function bindGame()
	if gameIsBound then
		return
	end
	gameIsBound = true
	ContextActionService:BindActionAtPriority(
		A_PRIMARY,
		onGameAction,
		false,
		GAME_PRIORITY,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.E
	)
	ContextActionService:BindActionAtPriority(
		A_SECONDARY,
		onGameAction,
		false,
		GAME_PRIORITY,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Q
	)
	ContextActionService:BindActionAtPriority(
		A_LEAP,
		onGameAction,
		false,
		GAME_PRIORITY,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.LeftShift
	)
	ContextActionService:BindActionAtPriority(
		A_RIDE,
		onGameAction,
		false,
		GAME_PRIORITY,
		Enum.KeyCode.ButtonL2,
		Enum.KeyCode.R
	)
	ContextActionService:BindActionAtPriority(
		A_CYCLE,
		onGameAction,
		false,
		GAME_PRIORITY,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1
	)
	ContextActionService:BindActionAtPriority(
		A_EMOTE,
		onGameAction,
		false,
		GAME_PRIORITY,
		Enum.KeyCode.DPadUp,
		Enum.KeyCode.DPadRight,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.F
	)
end

local function unbindGame()
	if not gameIsBound then
		return
	end
	gameIsBound = false
	for _, name in GAME_ACTIONS do
		ContextActionService:UnbindAction(name)
	end
	-- un maintien ne survit jamais à une fenêtre : le serveur reçoit la fin tout de suite
	endHold()
end

local function bindMenu(mode: string)
	if mode == menuMode then
		return
	end
	menuMode = mode
	ContextActionService:UnbindAction(A_MENU)
	if mode == "full" then
		local keys = { Enum.KeyCode.ButtonY, Enum.KeyCode.DPadDown }
		for _, k in menuKeys do
			table.insert(keys, k)
		end
		ContextActionService:BindActionAtPriority(A_MENU, onMenu, false, MENU_PRIORITY, table.unpack(keys))
	elseif mode == "window" then
		-- fenêtre non bloquante : croix ↓ est rendue à la navigation ; △ et M ferment tout
		local keys = { Enum.KeyCode.ButtonY }
		for _, k in menuKeys do
			table.insert(keys, k)
		end
		ContextActionService:BindActionAtPriority(A_MENU, onMenu, false, MENU_PRIORITY, table.unpack(keys))
	end
end

local function bindPanels(on: boolean)
	if on == panelsBound then
		return
	end
	panelsBound = on
	if on then
		local keys = {}
		for key in panelKeys do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return a.Name < b.Name
		end)
		ContextActionService:BindActionAtPriority(
			A_PANELS,
			onPanels,
			false,
			MENU_PRIORITY,
			table.unpack(keys)
		)
	else
		ContextActionService:UnbindAction(A_PANELS)
	end
end

-- Fenêtre bloquante ouverte (carte du choix, écran de retour, toute fenêtre marquée bloquante)
local function blockingOpen(): boolean
	local top = Util.safe("FocusGuard.top", nil, FocusGuard.top)
	return type(top) == "table" and top.blocking == true
end

local function refreshBindings()
	local anyOpen = Util.safe("FocusGuard.anyOpen", false, FocusGuard.anyOpen) == true
	if anyOpen then
		unbindGame()
	else
		bindGame()
	end
	local blocking = anyOpen and blockingOpen()
	if blocking then
		bindMenu("none")
	elseif anyOpen then
		bindMenu("window")
	else
		bindMenu("full")
	end
	bindPanels(not blocking)
end

-- =============================================================================================
-- Sac à objets (CoreGui) : coupé, nouveaux essais bornés
-- =============================================================================================

local BACKPACK_TRIES = math.max(1, math.floor(Layout.Keyboard.BackpackRetry / BACKPACK_GAP))

-- Un essai par BACKPACK_GAP s, BackpackRetry / BACKPACK_GAP essais au plus (compte d'essais, jamais
-- une durée : un saut de l'horloge du jeu ne fait pas abandonner trop tôt)
local function stepBackpack(now: number)
	if backpackDone then
		return
	end
	if now < backpackNextTry and backpackNextTry - now <= BACKPACK_GAP then
		return
	end
	backpackTries += 1
	backpackNextTry = now + BACKPACK_GAP
	local ok = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	if ok then
		backpackDone = true
		backpackOk = true
	elseif backpackTries >= BACKPACK_TRIES then
		backpackDone = true -- abandon silencieux : le jeu reste jouable (1, 2, 3 restent des emotes)
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function InputController.Init()
	hold = nil
end

-- Connexions et boucles
function InputController.Start()
	if started then
		return
	end
	started = true
	FocusGuard.WindowOpened:Connect(function()
		refreshBindings()
	end)
	FocusGuard.WindowClosed:Connect(function()
		refreshBindings()
	end)
	-- clic gauche sur un squishy : cible fixée 4 s par projection à l'écran, puis action
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not gameIsBound then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local p = input.Position
			if
				Util.safe("PromptController.clickAt", false, PromptController.clickAt, Vector2.new(p.X, p.Y))
			then
				primaryBegin(true)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local h = hold
			if h and h.byMouse then
				endHold()
			end
		end
	end)
	-- maintien réussi (fin mesurée par le serveur) : vibration holdDone
	Prompt.HoldEnded:Connect(function(kind: string, success: boolean)
		if hold and hold.kind == kind then
			hold = nil
			Util.safe("PromptController.unlock", nil, PromptController.unlock)
		end
		if success and (kind == "feed" or kind == "boop") then
			Haptics.play("holdDone")
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player.CharacterAdded:Connect(function()
			endHold()
		end)
	end
	RunService.Heartbeat:Connect(function(dt: number)
		local now = Clock.now()
		stepBackpack(now)
		checkAcc += Util.num(dt, 0, 0, 1)
		if checkAcc >= CHECK_EVERY then
			checkAcc = 0
			refreshBindings()
		end
	end)
	stepBackpack(Clock.now())
	refreshBindings()
end

-- Les touches du jeu sont liées (aucune fenêtre ouverte)
function InputController.gameBound(): boolean
	return gameIsBound
end

-- Maintien en cours ("boop", "feed") ou nil (specs)
function InputController.holding(): string?
	local h = hold
	return if h then h.kind else nil
end

-- Le sac à objets de Roblox est-il coupé ? (specs)
function InputController.backpackDisabled(): boolean
	return backpackOk
end

return InputController
