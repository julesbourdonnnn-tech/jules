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
-- Lot B1 (v2.0, GDD §10.1, §10.6 règle 6, §10.7.9 ; docs/04 §27.8 règles 14, 15, 17 ; N11, N14) :
--   9. cadre de focus DESSINÉ À L'INTÉRIEUR de l'élément (FocusGuard.selectionImage : trait blanc de
--      Layout.Focus.Frame px et liseré sombre de Layout.Focus.Border px, sans débord) : il ne dépasse
--      jamais de l'élément, donc d'aucun ancêtre qui découpe tant que l'élément y est entier ; un
--      élément sélectionné qui dépasse d'un ScrollingFrame est ramené dedans (CanvasPosition) ;
--  10. InputGuard générique : à l'ouverture de TOUTE fenêtre, ✕ (et Entrée, et le clic) est ignoré tant
--      qu'on n'a pas vu son relâchement et que Balance.Upgrades.GuardOpen (0,3 s) n'est pas passée ;
--      même règle avec GuardFocus (0,4 s) quand l'élément sous le focus change d'identifiant (onglet
--      ou panneau changé par L1 / R1 / L2 / R2, sélection rendue par le code, attribut FocusId de
--      l'élément sélectionné changé). Un appui commencé pendant la garde est ignoré JUSQU'À SON
--      RELÂCHEMENT (« △ puis ✕ tenu 2 s : rien ») ; chaque nouvel appui est jugé seul, sur l'horloge :
--      rien ne bloque l'entrée pour toujours (FocusGuard.confirmReady, lu par Widgets et Hud/Util).
-- Une fenêtre dont la racine est détruite sans fermeture est fermée d'office (sauvetage compté) :
-- aucun état sans sortie. L'écran de chargement (ScreenGui « Loading », src/first) gère seul sa
-- sélection (Réessayer) : il est exempté, comme tout ScreenGui portant l'attribut FocusExempt.
-- Temps : Shared/Util/Clock (les specs font voyager le temps) ; une seule connexion Heartbeat.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local AudioController = require(Client.Controllers.AudioController)
local ErrorReporter = require(Client.Controllers.ErrorReporter)
local Juice = require(Client.UI.Juice)

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

-- InputGuard (règle 10) : fin de la garde en cours (Clock.now()) et appuis de confirmation suivis
local GUARD_OPEN = Balance.Upgrades.GuardOpen -- 0,3 s
local GUARD_FOCUS = Balance.Upgrades.GuardFocus -- 0,4 s
local GUARD_MAX = math.max(GUARD_OPEN, GUARD_FOCUS) + 0.05 -- horloge recalée : garde expirée
-- s : un Activated qui suit le relâchement (le moteur active un bouton au relâchement de ✕ ou du
-- clic) est jugé sur l'appui qui vient de finir
local RELEASE_GRACE = 0.25
local CONFIRM_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
}
-- L1 / R1 (onglets) et L2 / R2 (panneaux) : le contenu sous le focus change d'identifiant
local CHANGE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonL1] = true,
	[Enum.KeyCode.ButtonR1] = true,
	[Enum.KeyCode.ButtonL2] = true,
	[Enum.KeyCode.ButtonR2] = true,
}
type Press = { input: any, down: boolean, clean: boolean, began: number, ended: number }
local guardUntil = -math.huge
-- gardes posées parce que le CONTENU sous le focus a changé (fenêtre ouverte ou refermée au-dessus,
-- L1 / R1 / L2 / R2, FocusId, FocusGuard.guard) : un maintien en cours s'arrête (Widgets ; relecture
-- B1, B1-19) ; une sélection simplement rendue par le code (sauvetage) n'en est pas une
local contentChanges = 0
local presses: { [string]: Press } = {}
local lastPress: Press? = nil
local watchedSelection: GuiObject? = nil
local focusIdConn: RBXScriptConnection? = nil

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

-- =============================================================================================
-- InputGuard (règle 10)
-- =============================================================================================

-- La garde laisse-t-elle passer un appui qui commence maintenant ? (horloge recalée en arrière de
-- plus que la plus longue garde : expirée, jamais une garde sans fin)
local function guardOpenAt(now: number): boolean
	return not (now < guardUntil and guardUntil - now <= GUARD_MAX)
end

-- Pose (ou prolonge) une garde de `seconds` ; un appui déjà enfoncé ne compte plus : son relâchement
-- doit être vu avant qu'un appui soit accepté ; `content` : le contenu sous le focus a changé
local function arm(seconds: number, content: boolean?)
	if content then
		contentChanges += 1
	end
	local now = Clock.now()
	local s = math.clamp(if seconds == seconds then seconds else GUARD_OPEN, 0, GUARD_MAX)
	if not guardOpenAt(now) then
		guardUntil = math.max(guardUntil, now + s)
	else
		guardUntil = now + s
	end
	for _, press in presses do
		if press.down then
			press.clean = false
		end
	end
end

local function pressKey(input: any): string?
	local ok, key, kind = pcall(function()
		return input.KeyCode, input.UserInputType
	end)
	if not ok then
		return nil
	end
	if typeof(key) == "EnumItem" and CONFIRM_KEYS[key :: Enum.KeyCode] then
		return (key :: Enum.KeyCode).Name
	end
	if kind == Enum.UserInputType.MouseButton1 then
		return "MouseButton1"
	end
	return nil
end

-- Note le début d'un appui de confirmation et le juge (idempotent pour un même InputObject : Widgets
-- et FocusGuard écoutent tous deux InputBegan, dans un ordre que le moteur ne garantit pas) ; vrai si
-- l'appui est accepté
local function began(input: any): boolean
	local key = pressKey(input)
	if key == nil then
		return true
	end
	local press = presses[key]
	if press and press.input == input and press.down then
		return press.clean
	end
	local now = Clock.now()
	local entry: Press =
		{ input = input, down = true, clean = guardOpenAt(now), began = now, ended = -math.huge }
	presses[key] = entry
	lastPress = entry
	return entry.clean
end

local function ended(input: any)
	local key = pressKey(input)
	local press = if key then presses[key] else nil
	if press and press.down then
		press.down = false
		press.ended = Clock.now()
	end
end

-- Toute fin d'appui perdue (fenêtre du jeu quittée, menu de Roblox) : les appuis sont relâchés
local function releaseAll()
	local now = Clock.now()
	for _, press in presses do
		if press.down then
			press.down = false
			press.ended = now
		end
	end
end

-- L'attribut FocusId de l'élément sélectionné change (Conseillé recalculé, carte qui change de
-- famille) : garde de GuardFocus
local function watchSelection(selected: GuiObject?)
	if selected == watchedSelection then
		return
	end
	watchedSelection = selected
	local conn = focusIdConn
	if conn then
		conn:Disconnect()
		focusIdConn = nil
	end
	if selected ~= nil then
		local ok, signal = pcall(function()
			return selected:GetAttributeChangedSignal("FocusId")
		end)
		if ok and signal then
			focusIdConn = signal:Connect(function()
				arm(GUARD_FOCUS, true)
			end)
		end
	end
end

-- =============================================================================================
-- Cadre de focus (règle 9) : dessiné à l'intérieur de l'élément
-- =============================================================================================

-- Trait BLANC de Layout.Focus.Frame px (6) et liseré sombre de Layout.Focus.Border px (2), tous deux
-- DANS le rectangle de l'élément (le liseré au bord, le trait blanc juste dedans) : rien ne dépasse,
-- aucun ancêtre qui découpe ne le tranche, aucun voisin n'est touché (GDD v2.0 §10.1, N11). Couleur
-- propre au curseur (jamais l'or des états « choisi ») ; respire doucement (transparence 0 ↔ 0,35 en
-- Layout.Focus.Breath s ; fixe en Mouvement réduit). Une seule instance, jamais parentée (le moteur
-- la dessine sur GuiService.SelectedObject) ; à affecter à GuiObject.SelectionImageObject.
local CURSOR_COLOR = Color3.fromRGB(255, 255, 255)
local CURSOR_EDGE_COLOR = Color3.fromRGB(16, 12, 30) -- Theme.Colors.Stroke
local CURSOR_THICKNESS = Layout.Focus.Frame -- 6
local CURSOR_EDGE = Layout.Focus.Border -- 2
local CURSOR_INSET = CURSOR_THICKNESS + CURSOR_EDGE -- px du bord de l'élément au bord intérieur du trait
local CURSOR_RADIUS = Layout.Corner.Min -- coins de l'élément (UICorner 14-18 px)
local CURSOR_PULSE_PERIOD = Layout.Focus.Breath -- 1,2 s
local CURSOR_PULSE_DEPTH = 0.35

local cursorImage: Frame? = nil
local cursorStroke: UIStroke? = nil
local pulseTime = 0

local function stepCursor(dt: number)
	local stroke = cursorStroke
	if stroke == nil then
		return
	end
	local selected = GuiService.SelectedObject
	if selected == nil or Juice.reducedMotion() then
		pulseTime = 0
		if stroke.Transparency ~= 0 then
			stroke.Transparency = 0
		end
		return
	end
	local step = if type(dt) == "number" and dt == dt and dt > 0 then math.min(dt, 1) else 0
	pulseTime = (pulseTime + step) % CURSOR_PULSE_PERIOD
	local phase = 2 * math.pi * pulseTime / CURSOR_PULSE_PERIOD
	stroke.Transparency = CURSOR_PULSE_DEPTH * (1 - math.cos(phase)) / 2
end

function FocusGuard.selectionImage(): Frame
	local existing = cursorImage
	if existing then
		return existing
	end
	-- cadre du trait blanc : bord à CURSOR_INSET px dedans, trait de CURSOR_THICKNESS px vers
	-- l'extérieur (ApplyStrokeMode Border : le trait part du bord vers l'extérieur) → de 2 à 8 px dedans
	local frame = Instance.new("Frame")
	frame.Name = "FocusFrame"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, -2 * CURSOR_INSET, 1, -2 * CURSOR_INSET)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.max(0, CURSOR_RADIUS - CURSOR_INSET))
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Cursor"
	stroke.Color = CURSOR_COLOR
	stroke.Thickness = CURSOR_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	-- liseré sombre au bord de l'élément : cadre de CURSOR_THICKNESS px de plus par côté, trait de
	-- CURSOR_EDGE px vers l'extérieur → de 0 à 2 px dedans
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.BackgroundTransparency = 1
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.new(1, 2 * CURSOR_THICKNESS, 1, 2 * CURSOR_THICKNESS)
	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(0, math.max(0, CURSOR_RADIUS - CURSOR_EDGE))
	edgeCorner.Parent = edge
	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Name = "Edge"
	edgeStroke.Color = CURSOR_EDGE_COLOR
	edgeStroke.Thickness = CURSOR_EDGE
	edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edgeStroke.Parent = edge
	edge.Parent = frame
	cursorImage = frame
	cursorStroke = stroke
	RunService.Heartbeat:Connect(stepCursor)
	return frame
end

-- Débord du cadre de focus autour de l'élément (px de l'élément ; ≤ 0 : dessiné à l'intérieur).
-- Lu par les specs (règle 14) : bord extérieur de chaque trait (cadre centré, taille 1 + Offset, trait
-- Border vers l'extérieur), le plus grand des deux ; sans cadre, celui du moteur (débord inconnu : 4)
function FocusGuard.cursorOutset(obj: GuiObject?): number
	local image = if obj then obj.SelectionImageObject else nil
	if image == nil then
		return 4
	end
	local function outer(frame: Instance, base: number): number
		local half = 0
		if frame:IsA("GuiObject") then
			half = (frame :: GuiObject).Size.X.Offset / 2
		end
		local edgeAt = base + half
		local best = edgeAt
		for _, child in frame:GetChildren() do
			if child:IsA("UIStroke") then
				best = math.max(best, edgeAt + (child :: UIStroke).Thickness)
			elseif child:IsA("GuiObject") then
				best = math.max(best, outer(child, edgeAt))
			end
		end
		return best
	end
	return outer(image, 0)
end

-- Ancêtres qui découpent (ClipsDescendants, ScrollingFrame, CanvasGroup) jusqu'à l'écran
local function clippers(obj: GuiObject): { GuiObject }
	local out = {}
	local cur: Instance? = obj.Parent
	while cur ~= nil and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") then
			local g = cur :: GuiObject
			if g.ClipsDescendants or g:IsA("ScrollingFrame") or g:IsA("CanvasGroup") then
				table.insert(out, g)
			end
		end
		cur = cur.Parent
	end
	return out
end
FocusGuard.clippers = clippers

-- Élément sélectionné qui dépasse d'un ScrollingFrame : défilement minimal pour l'y ramener entier
-- (avec la marge Layout.Spacing.Normal quand elle tient) ; les listes virtuelles de Widgets gardent la
-- leur (rangée de marge). Vrai si un défilement a été posé.
local function keepInside(obj: GuiObject): boolean
	local moved = false
	for _, clip in clippers(obj) do
		if clip:IsA("ScrollingFrame") then
			local sf = clip :: ScrollingFrame
			local p, sz = obj.AbsolutePosition, obj.AbsoluteSize
			local cp, cs = sf.AbsolutePosition, sf.AbsoluteSize
			local scale = if sf.AbsoluteSize.Y > 0 and sf.Size.Y.Offset > 0
				then sf.AbsoluteSize.Y / sf.Size.Y.Offset
				else 1
			local margin = Layout.Spacing.Normal * scale
			local dx, dy = 0, 0
			for axis = 1, 2 do
				local lo = if axis == 1 then p.X - cp.X else p.Y - cp.Y
				local size = if axis == 1 then sz.X else sz.Y
				local room = if axis == 1 then cs.X else cs.Y
				local m = math.min(margin, math.max(0, (room - size) / 2))
				local d = 0
				if lo < m then
					d = lo - m
				elseif lo + size > room - m then
					d = math.min(lo - m, lo + size - (room - m))
				end
				if axis == 1 then
					dx = d
				else
					dy = d
				end
			end
			if math.abs(dx) > 0.5 or math.abs(dy) > 0.5 then
				-- CanvasPosition en px d'écran, comme les écarts mesurés (AbsolutePosition)
				local goal = sf.CanvasPosition + Vector2.new(dx, dy)
				pcall(function()
					sf.CanvasPosition = Vector2.new(math.max(0, goal.X), math.max(0, goal.Y))
				end)
				moved = true
			end
		end
	end
	return moved
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
	if GuiService.SelectedObject ~= target then
		-- sélection rendue par le code : l'élément sous le focus change d'identifiant (règle 10)
		arm(GUARD_FOCUS)
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
	guardUntil = -math.huge
	table.clear(presses)
	lastPress = nil
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
		watchSelection(selected)
		if selected ~= nil then
			pcall(keepInside, selected)
		end
	end)
	-- InputGuard : appuis de confirmation (✕, Entrée, clic) suivis, captés même quand l'interface les
	-- traite (gameProcessed) ; L1 / R1 / L2 / R2 dans une fenêtre : contenu changé sous le focus
	UserInputService.InputBegan:Connect(function(input: InputObject)
		began(input)
		local ok, key = pcall(function()
			return input.KeyCode
		end)
		if ok and typeof(key) == "EnumItem" and CHANGE_KEYS[key :: Enum.KeyCode] and #stack > 0 then
			arm(GUARD_FOCUS, true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		ended(input)
	end)
	pcall(function()
		UserInputService.WindowFocusReleased:Connect(releaseAll)
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
	-- InputGuard : ✕ ignoré tant que son relâchement n'est pas vu et que GuardOpen n'est pas passée
	arm(GUARD_OPEN, true)
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
			-- la sélection revient à la fenêtre de dessous : nouvel élément sous le focus (règle 10)
			arm(GUARD_FOCUS, true)
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

-- InputGuard : un appui de confirmation (✕, Entrée, clic) peut-il agir maintenant ? Vrai si l'appui
-- en cours (ou celui qui vient d'être relâché : Activated part au relâchement) a commencé hors de toute
-- garde ; sans appui connu (activation par le code), vrai hors de toute garde. Jamais faux pour
-- toujours : chaque nouvel appui est jugé sur l'horloge seule.
function FocusGuard.confirmReady(): boolean
	local now = Clock.now()
	local press = lastPress
	if press then
		if press.down then
			return press.clean
		end
		if now >= press.ended and now - press.ended <= RELEASE_GRACE then
			return press.clean
		end
	end
	return guardOpenAt(now)
end

-- InputGuard : début d'un appui vu par un autre module (Widgets, maintiens) avant FocusGuard : jugé
-- une seule fois par InputObject ; vrai si l'appui est accepté
function FocusGuard.notePress(input: any): boolean
	return began(input)
end

-- InputGuard : l'appui en cours (ou celui qui vient d'être relâché) a déjà agi — maintien fini
-- (Widgets.holdOn) : son relâchement n'est plus un clic (Activated ignoré : ni double action, ni son
-- Error d'un bouton que l'achat vient de griser ; relecture B1, B1-19) ; le suivant est jugé seul
function FocusGuard.consumePress()
	local press = lastPress
	if press then
		press.clean = false
	end
end

-- InputGuard : pose une garde (GuardFocus par défaut) ; pour un contenu changé sous le focus
-- (onglet, liste rechargée, Conseillé recalculé)
function FocusGuard.guard(seconds: number?)
	arm(if type(seconds) == "number" then seconds else GUARD_FOCUS, true)
end

-- InputGuard : nombre de gardes posées pour un contenu changé sous le focus (Widgets : un maintien
-- commencé avant s'arrête sans rien acheter)
function FocusGuard.contentChanges(): number
	return contentChanges
end

-- InputGuard : état (specs, Diagnostics)
function FocusGuard.guardInfo(): { active: boolean, remaining: number, down: boolean, clean: boolean }
	local now = Clock.now()
	local press = lastPress
	local active = not guardOpenAt(now)
	return {
		active = active,
		remaining = if active then guardUntil - now else 0,
		down = press ~= nil and press.down,
		clean = press == nil or press.clean,
	}
end

-- Règle 9 : ramène l'élément sélectionné entier dans ses ScrollingFrame (specs ; le changement de
-- sélection le fait aussi)
function FocusGuard.keepInside(obj: GuiObject?): boolean
	if obj == nil then
		return false
	end
	local ok, moved = pcall(keepInside, obj)
	return ok and moved == true
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
