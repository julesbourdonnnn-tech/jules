--!strict
-- FocusGuard (paquet client-panels) : la sélection de la manette n'est jamais perdue ni piégée
-- (GDD §10.6, règles 1 à 8 ; docs/04 §14.2) :
--   1. une seule source : GuiService.SelectedObject ;
--   2. en jeu (aucune fenêtre), aucune sélection : une sélection posée est effacée en 0,25 s ;
--   3. fenêtre ouverte (menu, panneau, carte bloquante, écran de retour) : la sélection reste dans
--      la fenêtre active ; vide ou dehors (objet détruit, onglet changé, liste rechargée), elle est
--      rendue en 0,25 s au dernier objet affiché, sinon à la sélection par défaut de l'écran ; pendant
--      une fenêtre de Roblox (achat, invitation), elle est tenue (hold) 60 s au plus, puis rendue ;
--   4. fermer une fenêtre rend la sélection à ce qui l'a ouverte, ou au jeu ;
--   5. ○ (et Retour arrière au clavier) remonte d'un niveau partout : FocusGuard lie ButtonB et
--      Backspace tant qu'une fenêtre est ouverte (InputController ne lie que les touches du jeu) ;
--   6. double appui : une fermeture moins de 0,35 s après l'ouverture de la même fenêtre est ignorée ;
--   7. chaque fenêtre est un SelectionGroup aux comportements Stop (la sélection ne s'échappe pas) ;
--   8. chaque sauvetage est compté (rescues) et signalé à ErrorReporter (FocusRescued → Diagnostics) ;
--      un changement voulu du contenu (onglet, liste rechargée) passe par refocus(), qui rend la
--      sélection aussitôt sans rien compter.
-- Une fenêtre dont la racine est détruite sans fermeture est fermée d'office (sauvetage compté) :
-- aucun état sans sortie. L'écran de chargement (ScreenGui « Loading », src/first) gère seul sa
-- sélection (Réessayer) : il est exempté, comme tout ScreenGui portant l'attribut FocusExempt.
-- Temps : Shared/Util/Clock (les specs font voyager le temps) ; une seule connexion Heartbeat.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)

local Client = script.Parent.Parent
local AudioController = require(Client.Controllers.AudioController)
local ErrorReporter = require(Client.Controllers.ErrorReporter)

export type Window = {
	name: string,
	root: GuiObject,
	blocking: boolean,
	default: () -> GuiObject?, -- sélection par défaut (règle de l'écran, GDD §10.6)
	onBack: () -> boolean, -- sous-niveau géré (vrai) ou fermer (faux)
	opener: GuiObject?,
}

type Entry = {
	window: Window,
	openedAt: number,
	lastShown: GuiObject?,
	opener: GuiObject?,
}

local FocusGuard = {}

-- (nom)
FocusGuard.WindowOpened = Signal.new() :: Signal.Signal<string>
-- (nom)
FocusGuard.WindowClosed = Signal.new() :: Signal.Signal<string>

local RESCUE_AFTER = Layout.Focus.RescueAfter -- 0,25 s
local HOLD_MAX = Layout.Focus.HoldMax -- 60 s
local DOUBLE_GUARD = Layout.Focus.DoubleCloseGuard -- 0,35 s
local BACK_ACTION = "FocusGuardBack"
local BACK_PRIORITY = Enum.ContextActionPriority.High.Value + 100

local stack: { Entry } = {}
local heldUntil: number? = nil
local rescueCount = 0
local badSince: number? = nil
local backBound = false
local started = false

-- =============================================================================================
-- Outils
-- =============================================================================================

local function report(text: string)
	pcall(ErrorReporter.report, 2, text, nil)
end

local function noteWindow()
	local top = stack[#stack]
	pcall(ErrorReporter.noteContext, "window", if top then top.window.name else "")
end

-- Affiché : lui et ses ancêtres visibles, jusqu'à un ScreenGui activé
local function shown(obj: Instance): boolean
	local cur: Instance? = obj
	while cur ~= nil do
		if cur:IsA("GuiObject") then
			if not cur.Visible then
				return false
			end
		elseif cur:IsA("LayerCollector") then
			return cur.Enabled and cur.Parent ~= nil
		end
		cur = cur.Parent
	end
	return false
end

-- Objet sélectionnable, affiché, dans la racine
local function validIn(obj: Instance?, root: GuiObject): boolean
	if obj == nil or obj.Parent == nil or not obj:IsA("GuiObject") then
		return false
	end
	local gui = obj :: GuiObject
	if not gui.Selectable or gui.Interactable == false then
		return false
	end
	if gui ~= root and not gui:IsDescendantOf(root) then
		return false
	end
	return shown(gui)
end

-- Sélection gérée par un autre écran (chargement) : jamais touchée
local function exempt(obj: Instance): boolean
	local cur: Instance? = obj
	while cur ~= nil do
		if cur:IsA("LayerCollector") then
			return cur.Name == "Loading" or cur:GetAttribute("FocusExempt") == true
		end
		cur = cur.Parent
	end
	return false
end

local function setSelection(obj: GuiObject?)
	if GuiService.SelectedObject ~= obj then
		pcall(function()
			GuiService.SelectedObject = obj
		end)
	end
end

local function firstSelectable(root: GuiObject): GuiObject?
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and validIn(d, root) then
			return d
		end
	end
	return nil
end

-- Sélection par défaut d'une fenêtre (sa règle, sinon le premier objet sélectionnable affiché)
local function defaultOf(window: Window): GuiObject?
	local ok, d = pcall(window.default)
	if ok and d ~= nil and validIn(d, window.root) then
		return d
	end
	return firstSelectable(window.root)
end

local function find(name: string): number?
	for i = #stack, 1, -1 do
		if stack[i].window.name == name then
			return i
		end
	end
	return nil
end

local function isHeld(): boolean
	return heldUntil ~= nil
end

-- Rend la sélection à la fenêtre active : dernier objet affiché, sinon défaut ; vrai si posée
local function restoreTop(): boolean
	local top = stack[#stack]
	if top == nil then
		return false
	end
	local root = top.window.root
	local target: GuiObject? = nil
	if top.lastShown and validIn(top.lastShown, root) then
		target = top.lastShown
	else
		target = defaultOf(top.window)
	end
	if target == nil then
		return false
	end
	setSelection(target)
	top.lastShown = target
	return true
end

-- ○ et Retour arrière liés tant qu'une fenêtre est ouverte
local function onBackAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		FocusGuard.back()
	end
	return Enum.ContextActionResult.Sink
end

local function updateBinding()
	local want = #stack > 0
	if want and not backBound then
		backBound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(
				BACK_ACTION,
				onBackAction,
				false,
				BACK_PRIORITY,
				Enum.KeyCode.ButtonB,
				Enum.KeyCode.Backspace
			)
		end)
	elseif not want and backBound then
		backBound = false
		pcall(function()
			ContextActionService:UnbindAction(BACK_ACTION)
		end)
	end
end

local function lockRoot(root: GuiObject)
	pcall(function()
		root.SelectionGroup = true
		root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
		root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
		root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
		root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	end)
end

-- =============================================================================================
-- Boucle de surveillance (une connexion Heartbeat)
-- =============================================================================================

local function step()
	local now = Clock.now()
	-- fenêtre dont la racine a disparu sans fermeture : fermée d'office
	for i = #stack, 1, -1 do
		local entry = stack[i]
		if entry and entry.window.root.Parent == nil then
			rescueCount += 1
			report("FocusRescued:lost:" .. entry.window.name)
			FocusGuard.closeNow(entry.window.name)
		end
	end
	if heldUntil ~= nil then
		if now < (heldUntil :: number) and now >= (heldUntil :: number) - HOLD_MAX - 1 then
			return
		end
		-- fenêtre de Roblox jamais relâchée (ou horloge recalée) : sélection rendue de force
		heldUntil = nil
		badSince = nil
		rescueCount += 1
		report("FocusRescued:holdTimeout")
		restoreTop()
		return
	end
	local selected = GuiService.SelectedObject
	local top = stack[#stack]
	if top == nil then
		if selected ~= nil and not exempt(selected) then
			if badSince == nil then
				badSince = now
			elseif now - (badSince :: number) >= RESCUE_AFTER or now < (badSince :: number) then
				badSince = nil
				setSelection(nil)
				rescueCount += 1
				report("FocusRescued:inGame")
			end
		else
			badSince = nil
		end
		return
	end
	if selected ~= nil and validIn(selected, top.window.root) then
		top.lastShown = selected
		badSince = nil
		return
	end
	if selected ~= nil and exempt(selected) then
		badSince = nil
		return
	end
	if badSince == nil then
		badSince = now
		return
	end
	if now - (badSince :: number) >= RESCUE_AFTER or now < (badSince :: number) then
		badSince = nil
		if restoreTop() then
			rescueCount += 1
			report("FocusRescued:" .. top.window.name)
		end
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function FocusGuard.Init()
	table.clear(stack)
	heldUntil = nil
	badSince = nil
end

-- Connexions et boucles
function FocusGuard.Start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(step)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local top = stack[#stack]
		local selected = GuiService.SelectedObject
		if top and selected and validIn(selected, top.window.root) then
			top.lastShown = selected
		end
	end)
end

-- Ouvre une fenêtre (devient la fenêtre active ; SelectionGroup, comportement Stop)
function FocusGuard.open(window: Window)
	if type(window) ~= "table" or type(window.name) ~= "string" or typeof(window.root) ~= "Instance" then
		return
	end
	local opener = window.opener
	if opener == nil then
		local top = stack[#stack]
		local selected = GuiService.SelectedObject
		if top and selected and validIn(selected, top.window.root) then
			opener = selected
		end
	end
	local existing = find(window.name)
	if existing then
		table.remove(stack, existing)
	end
	lockRoot(window.root)
	table.insert(stack, { window = window, openedAt = Clock.now(), lastShown = nil, opener = opener })
	badSince = nil
	updateBinding()
	if not isHeld() then
		local target = defaultOf(window)
		if target then
			setSelection(target)
		end
	end
	FocusGuard.WindowOpened:Fire(window.name)
	noteWindow()
end

-- La fenêtre peut-elle être fermée maintenant (garde contre le double appui, 0,35 s) ?
function FocusGuard.canClose(name: string): boolean
	local i = find(name)
	if i == nil then
		return false
	end
	local opened = stack[i].openedAt
	local now = Clock.now()
	return now - opened >= DOUBLE_GUARD or now < opened
end

-- Ferme une fenêtre sans la garde du double appui (transitions voulues par le code)
function FocusGuard.closeNow(name: string)
	local i = find(name)
	if i == nil then
		return
	end
	local wasTop = i == #stack
	local entry = table.remove(stack, i) :: Entry
	badSince = nil
	updateBinding()
	FocusGuard.WindowClosed:Fire(name)
	if wasTop and not isHeld() then
		local top = stack[#stack]
		if top == nil then
			setSelection(nil)
		else
			local root = top.window.root
			if entry.opener and validIn(entry.opener, root) then
				setSelection(entry.opener)
				top.lastShown = entry.opener
			elseif top.lastShown and validIn(top.lastShown, root) then
				setSelection(top.lastShown)
			else
				local d = defaultOf(top.window)
				if d then
					setSelection(d)
				end
			end
		end
	end
	noteWindow()
end

-- Ferme une fenêtre et rend la sélection à son ouvreur (ignoré moins de 0,35 s après l'ouverture)
function FocusGuard.close(name: string)
	if not FocusGuard.canClose(name) then
		return
	end
	FocusGuard.closeNow(name)
end

-- Fenêtre active
function FocusGuard.top(): Window?
	local top = stack[#stack]
	return if top then top.window else nil
end

-- Au moins une fenêtre ouverte (touches du jeu déliées)
function FocusGuard.anyOpen(): boolean
	return #stack > 0
end

-- La fenêtre est-elle ouverte ?
function FocusGuard.isOpen(name: string): boolean
	return find(name) ~= nil
end

-- Noms des fenêtres ouvertes, de la plus ancienne à l'active (specs, diagnostics)
function FocusGuard.names(): { string }
	local out = {}
	for _, entry in stack do
		table.insert(out, entry.window.name)
	end
	return out
end

-- ○ / Retour arrière : remonte d'un niveau (vrai si géré)
function FocusGuard.back(): boolean
	local top = stack[#stack]
	if top == nil then
		return false
	end
	local now = Clock.now()
	if now - top.openedAt < DOUBLE_GUARD and now >= top.openedAt then
		return true -- double appui : ignoré
	end
	AudioController.play("Back")
	local ok, handled = pcall(top.window.onBack)
	if ok and handled == true then
		return true
	end
	-- sous-niveau non géré (ou erreur) : la fenêtre se ferme, il y a toujours une sortie
	FocusGuard.closeNow(top.window.name)
	return true
end

-- Tient la sélection pendant une fenêtre de Roblox (60 s au plus)
function FocusGuard.hold(seconds: number?)
	local s = if type(seconds) == "number" and seconds == seconds then seconds else HOLD_MAX
	heldUntil = Clock.now() + math.clamp(s, 0, HOLD_MAX)
	badSince = nil
end

-- Fin de la fenêtre de Roblox
function FocusGuard.release()
	if heldUntil == nil then
		return
	end
	heldUntil = nil
	badSince = nil
	local top = stack[#stack]
	if top == nil then
		setSelection(nil)
	elseif not validIn(GuiService.SelectedObject, top.window.root) then
		restoreTop()
	end
end

-- Le contenu de la fenêtre active vient de changer par une action voulue (onglet changé par L1 / R1,
-- liste rechargée, entrée du rail cachée) : si la sélection n'y est plus valide, elle est rendue TOUT
-- DE SUITE (dernier objet affiché, sinon défaut de l'écran). Ce n'est pas un sauvetage (rien n'est
-- compté ni signalé : FocusRescued reste le signe d'un vrai bug) ; vrai si la sélection a été posée.
function FocusGuard.refocus(): boolean
	if isHeld() then
		return false
	end
	local top = stack[#stack]
	if top == nil then
		return false
	end
	local selected = GuiService.SelectedObject
	if selected ~= nil and (validIn(selected, top.window.root) or exempt(selected)) then
		return false
	end
	badSince = nil
	return restoreTop()
end

-- La sélection est-elle tenue (fenêtre de Roblox) ?
function FocusGuard.held(): boolean
	return heldUntil ~= nil
end

-- Sauvetages comptés dans la session (specs)
function FocusGuard.rescues(): number
	return rescueCount
end

-- Un tour de surveillance tout de suite (specs ; la boucle Heartbeat fait de même)
function FocusGuard._step()
	step()
end

return FocusGuard
