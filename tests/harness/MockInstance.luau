--!nocheck
-- Instances Roblox simulées pour les tests sous Lune.
-- Volontairement permissives (propriétés libres) mais strictes sur ce qui cause
-- de vrais bugs : enfant inexistant dans un dossier de scripts, Parent d'une
-- instance détruite, WaitForChild infini.

local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Signal = require("./Signal")

local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local UDim2 = roblox.UDim2
local Enum = roblox.Enum

local MockInstance = {}

-- État de chaque instance rangé DANS l'instance, sous une clé privée. Une table à clés faibles
-- (instance → état) ne libérait jamais rien : Luau n'a pas d'éphémérons et l'état référence
-- Parent et enfants, donc chaque arbre d'instances restait vivant jusqu'à la fin de la suite
-- (plusieurs Go). Rangé dans l'instance, l'état disparaît avec elle.
local STATE = table.freeze({})

-- état d'une valeur quelconque (nil si ce n'est pas une instance simulée)
local function stateOf(value: any)
	return if type(value) == "table" then rawget(value, STATE) else nil
end
local MT = {}

MockInstance.warnings = {} :: { string }
MockInstance.waitTimeout = 2
-- Taille de l'écran simulé (px) : ViewportSize des caméras et AbsoluteSize des LayerCollector créés
-- ensuite. Posée par Harness.new (1280 × 720, ou 1920 × 1080 pour une console).
MockInstance.screenSize = Vector2.new(1280, 720)

-- Styles récents du moteur (lot B1 ; GDD v2.0 §10.1, critique m21 ; docs/04 §27.14 « Harnais ») :
-- `UIShadow` (en ligne depuis le 23/06/2026) et le dégradé radial de `UIGradient` (fin octobre 2026,
-- docs/08 [92][93]) manquent à la base de réflexion de Lune, et un appareil peut ne pas les avoir.
-- false (défaut, style des captures de référence : le repli à plat) : Instance.new("UIShadow") lève et
-- UIGradient.Type refuse toute écriture, comme un moteur qui ne les connaît pas ; true : présents
-- (propriétés supposées : UIShadow.Color, Transparency, Offset, BlurRadius ; UIGradient.Type « Radial »),
-- une écriture d'une autre propriété de UIShadow lève (nom faux sur l'appareil → repli, jamais une
-- erreur visible : UI/Theme).
MockInstance.styleFeatures = { UIShadow = false, RadialGradient = false }
local SHADOW_PROPS = { Color = true, Transparency = true, Offset = true, BlurRadius = true }

local function warnOnce(msg: string)
	table.insert(MockInstance.warnings, msg)
end

-- Hiérarchie de classes (suffisante pour IsA)
local SUPER: { [string]: string } = {
	Part = "FormFactorPart",
	WedgePart = "FormFactorPart",
	CornerWedgePart = "BasePart",
	TrussPart = "BasePart",
	SpawnLocation = "Part",
	Seat = "Part",
	MeshPart = "BasePart",
	UnionOperation = "BasePart",
	FormFactorPart = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	Tool = "BackpackItem",
	BackpackItem = "Model",
	Workspace = "Model",
	PVInstance = "Instance",
	Frame = "GuiObject",
	ScrollingFrame = "GuiObject",
	CanvasGroup = "GuiObject",
	TextLabel = "GuiLabel",
	ImageLabel = "GuiLabel",
	GuiLabel = "GuiObject",
	TextButton = "GuiButton",
	ImageButton = "GuiButton",
	GuiButton = "GuiObject",
	TextBox = "GuiObject",
	ViewportFrame = "GuiObject",
	GuiObject = "GuiBase2d",
	ScreenGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	LayerCollector = "GuiBase2d",
	GuiBase2d = "GuiBase",
	GuiBase = "Instance",
	IntValue = "ValueBase",
	NumberValue = "ValueBase",
	StringValue = "ValueBase",
	BoolValue = "ValueBase",
	ObjectValue = "ValueBase",
	Vector3Value = "ValueBase",
	CFrameValue = "ValueBase",
	Color3Value = "ValueBase",
	ValueBase = "Instance",
	PointLight = "Light",
	SpotLight = "Light",
	SurfaceLight = "Light",
	Light = "Instance",
	Script = "BaseScript",
	LocalScript = "Script",
	BaseScript = "LuaSourceContainer",
	ModuleScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	UICorner = "UIComponent",
	UIStroke = "UIComponent",
	UIGradient = "UIComponent",
	UIShadow = "UIComponent",
	UIScale = "UIComponent",
	UIPadding = "UIComponent",
	UIListLayout = "UIGridStyleLayout",
	UIGridLayout = "UIGridStyleLayout",
	UIGridStyleLayout = "UILayout",
	UILayout = "UIComponent",
	UIAspectRatioConstraint = "UIConstraint",
	UISizeConstraint = "UIConstraint",
	UITextSizeConstraint = "UIConstraint",
	UIConstraint = "UIComponent",
	UIComponent = "UIBase",
	UIBase = "Instance",
	ParticleEmitter = "Instance",
	Beam = "Instance",
	Trail = "Instance",
	Highlight = "Instance",
	Attachment = "Instance",
	Humanoid = "Instance",
	Player = "Instance",
	RemoteEvent = "BaseRemoteEvent",
	UnreliableRemoteEvent = "BaseRemoteEvent",
	BaseRemoteEvent = "Instance",
	Folder = "Instance",
}

local function isA(className: string, target: string): boolean
	local c: string? = className
	while c do
		if c == target then
			return true
		end
		c = SUPER[c]
	end
	return target == "Instance"
end
MockInstance.isA = isA

-- Classes dont l'accès à un enfant inexistant doit échouer comme dans Roblox
local STRICT_CONTAINERS = {
	Folder = true,
	ModuleScript = true,
	Script = true,
	LocalScript = true,
	ReplicatedStorage = true,
	ServerScriptService = true,
	ServerStorage = true,
	StarterPlayerScripts = true,
	StarterPlayer = true,
	DataModel = true,
}

local EVENTS = {
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	AncestryChanged = true,
	Destroying = true,
	AttributeChanged = true,
	Touched = true,
	TouchEnded = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Event = true,
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseButton2Click = true,
	Activated = true,
	MouseEnter = true,
	MouseLeave = true,
	InputBegan = true,
	InputEnded = true,
	InputChanged = true,
	FocusLost = true,
	Focused = true,
	Triggered = true,
	TriggerEnded = true,
	PromptButtonHoldBegan = true,
	PromptButtonHoldEnded = true,
	PromptShown = true,
	PromptHidden = true,
	Died = true,
	HealthChanged = true,
	Running = true,
	Jumping = true,
	StateChanged = true,
	MoveToFinished = true,
	CharacterAdded = true,
	CharacterAppearanceLoaded = true,
	CharacterRemoving = true,
	Chatted = true,
	Idled = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	RenderStepped = true,
	Stepped = true,
	PreSimulation = true,
	PostSimulation = true,
	PreRender = true,
	Completed = true,
	Ended = true,
	Played = true,
	Stopped = true,
	DidLoop = true,
	Equipped = true,
	Unequipped = true,
	PromptGamePassPurchaseFinished = true,
	PromptProductPurchaseFinished = true,
	-- ScriptContext.Error, LogService.MessageOut, CaptureService (couche « zéro trace », docs/04 §17)
	Error = true,
	MessageOut = true,
	CaptureBegan = true,
	CaptureEnded = true,
	UserCaptureSaved = true,
	PromptPurchaseFinished = true,
	GameInvitePromptClosed = true,
	TouchTap = true,
	JumpRequest = true,
	LastInputTypeChanged = true,
	WindowFocused = true,
	WindowFocusReleased = true,
	MenuOpened = true,
	MenuClosed = true,
	SelectionGained = true,
	SelectionLost = true,
	SelectionChanged = true,
	GamepadConnected = true,
	GamepadDisconnected = true,
	ReturnPressedFromOnScreenKeyboard = true,
}

-- Méthodes sans effet (retournent nil) : ce qui compte en test, c'est que l'appel existe.
local NOOP = {
	"ApplyImpulse",
	"ApplyAngularImpulse",
	"SetNetworkOwner",
	"SetNetworkOwnershipAuto",
	"BreakJoints",
	"MakeJoints",
	"Emit",
	"Clear",
	"Pause",
	"Resume",
	"CaptureFocus",
	"ReleaseFocus",
	"ChangeState",
	"SetStateEnabled",
	"UnequipTools",
	"EquipTool",
	"ApplyDescription",
	"ApplyDescriptionAsync",
	"BuildRigFromAttachments",
	"ScaleTo",
	"InputHoldBegin",
	"InputHoldEnd",
	"SetPrimaryPartCFrame",
	"TranslateBy",
	"SetCore",
	"SetCoreGuiEnabled",
	"BindAction",
	"UnbindAction",
	"BindActionAtPriority",
	"SetTitle",
	"SetDescription",
	"SetImage",
	"SetPosition",
	"AdjustAsync",
}

local function defaultsFor(className: string): { [string]: any }
	local d: { [string]: any } = {}
	if isA(className, "BasePart") then
		d.Size = Vector3.new(4, 1, 2)
		d.CFrame = CFrame.new()
		d.Position = Vector3.zero
		d.Orientation = Vector3.zero
		d.Color = Color3.fromRGB(163, 162, 165)
		d.Transparency = 0
		d.Reflectance = 0
		d.Anchored = false
		d.CanCollide = true
		d.CanTouch = true
		d.CanQuery = true
		d.CastShadow = true
		d.Massless = false
		d.Locked = false
		d.Material = Enum.Material.Plastic
		d.AssemblyLinearVelocity = Vector3.zero
		d.AssemblyAngularVelocity = Vector3.zero
		d.Shape = Enum.PartType.Block
		d.TopSurface = Enum.SurfaceType.Smooth
		d.BottomSurface = Enum.SurfaceType.Smooth
	end
	if isA(className, "GuiObject") then
		d.Size = UDim2.new(0, 100, 0, 100)
		d.Position = UDim2.new(0, 0, 0, 0)
		d.AnchorPoint = Vector2.zero
		d.Visible = true
		d.BackgroundTransparency = 0
		d.BackgroundColor3 = Color3.new(1, 1, 1)
		d.BorderSizePixel = 1
		d.ZIndex = 1
		d.LayoutOrder = 0
		d.Rotation = 0
		d.ClipsDescendants = false
		d.AutomaticSize = Enum.AutomaticSize.None
		d.AbsoluteSize = Vector2.new(100, 100)
		d.AbsolutePosition = Vector2.zero
		d.Active = false
		-- comme Roblox : boutons, champs de texte et cadres défilants sont sélectionnables par défaut
		-- (navigation manette) ; les autres GuiObject ne le sont pas
		d.Selectable = isA(className, "GuiButton") or className == "TextBox" or className == "ScrollingFrame"
		d.Interactable = true
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		d.Text = className
		d.TextColor3 = Color3.new(0, 0, 0)
		d.TextTransparency = 0
		d.TextStrokeTransparency = 1
		d.TextScaled = false
		d.TextSize = 14
		d.TextWrapped = false
		d.RichText = false
		d.Font = Enum.Font.SourceSans
		d.TextXAlignment = Enum.TextXAlignment.Center
		d.TextYAlignment = Enum.TextYAlignment.Center
	end
	if className == "ImageLabel" or className == "ImageButton" then
		d.Image = ""
		d.ImageColor3 = Color3.new(1, 1, 1)
		d.ImageTransparency = 0
	end
	if isA(className, "GuiButton") then
		d.AutoButtonColor = true
	end
	-- ombre d'interface (styles récents, voir MockInstance.styleFeatures) : valeurs supposées
	if className == "UIShadow" then
		d.Color = Color3.new(0, 0, 0)
		d.Transparency = 0.5
		d.Offset = Vector2.new(0, 6)
		d.BlurRadius = 8
	end
	-- cadre défilant (lot B1 : FocusGuard ramène l'élément sélectionné dans la découpe) : valeurs par
	-- défaut du moteur
	if className == "ScrollingFrame" then
		d.CanvasPosition = Vector2.zero
		d.CanvasSize = UDim2.new(0, 0, 2, 0)
		d.ScrollingEnabled = true
		d.ScrollBarThickness = 12
		d.ScrollingDirection = Enum.ScrollingDirection.XY
		d.AutomaticCanvasSize = Enum.AutomaticSize.None
	end
	if isA(className, "LayerCollector") then
		d.Enabled = true
		d.ResetOnSpawn = true
		d.AbsoluteSize = MockInstance.screenSize
	end
	if className == "BillboardGui" then
		d.Size = UDim2.new(0, 100, 0, 50)
		d.StudsOffset = Vector3.zero
		d.AlwaysOnTop = false
		d.MaxDistance = math.huge
		d.LightInfluence = 1
	end
	if className == "Humanoid" then
		d.Health = 100
		d.MaxHealth = 100
		d.WalkSpeed = 16
		d.JumpPower = 50
		d.JumpHeight = 7.2
		d.UseJumpPower = false
		d.HipHeight = 2
		d.MoveDirection = Vector3.zero
		d.CameraOffset = Vector3.zero
		d.DisplayName = ""
		d.FloorMaterial = Enum.Material.Plastic
		d.RigType = Enum.HumanoidRigType.R15
		d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		d.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	end
	if className == "Camera" then
		d.CFrame = CFrame.new(0, 10, 20)
		d.Focus = CFrame.new()
		d.FieldOfView = 70
		d.ViewportSize = MockInstance.screenSize
		d.CameraType = Enum.CameraType.Custom
	end
	if className == "Sound" then
		d.SoundId = ""
		d.Volume = 0.5
		d.PlaybackSpeed = 1
		d.Playing = false
		d.Looped = false
		d.TimePosition = 0
		d.TimeLength = 1
		d.IsLoaded = true
	end
	if className == "ParticleEmitter" then
		d.Enabled = true
		d.Rate = 20
	end
	if className == "Attachment" then
		d.Position = Vector3.zero
		d.CFrame = CFrame.new()
		d.WorldPosition = Vector3.zero
		d.WorldCFrame = CFrame.new()
	end
	if className == "IntValue" or className == "NumberValue" then
		d.Value = 0
	elseif className == "StringValue" then
		d.Value = ""
	elseif className == "BoolValue" then
		d.Value = false
	end
	if className == "ProximityPrompt" then
		d.Enabled = true
		d.ActionText = "Interact"
		d.ObjectText = ""
		d.HoldDuration = 0
		d.MaxActivationDistance = 10
		d.KeyboardKeyCode = Enum.KeyCode.E
		d.RequiresLineOfSight = true
	end
	if className == "Model" then
		d.WorldPivot = CFrame.new()
	end
	if className == "Lighting" then
		d.ClockTime = 14
		d.Brightness = 2
	end
	if className == "Highlight" then
		d.Enabled = true
		d.FillTransparency = 0.5
		d.OutlineTransparency = 0
	end
	if className == "ScreenGui" then
		d.IgnoreGuiInset = false
		d.DisplayOrder = 0
	end
	if className == "UIScale" then
		d.Scale = 1
	end
	if className == "UIStroke" then
		d.Thickness = 1
		d.Transparency = 0
		d.Color = Color3.new(0, 0, 0)
	end
	return d
end

local function signalOf(st, key: string)
	local s = st.signals[key]
	if not s then
		s = Signal.new()
		st.signals[key] = s
	end
	return s
end

local function propSignal(st, prop: string)
	local s = st.propSignals[prop]
	if not s then
		s = Signal.new()
		st.propSignals[prop] = s
	end
	return s
end

-- Compteur d'instances créées depuis le chargement du harnais (lot B1 ; règle 20 du GDD v2.0 §10.8 :
-- budget d'instances par panneau, « réouverture : 0 instance créée ») : MockInstance.created() avant
-- et après une action ; MockInstance.descendantCount(racine) pour le total d'un panneau
local createdCount = 0

function MockInstance.created(): number
	return createdCount
end

function MockInstance.descendantCount(root: any): number
	local st = stateOf(root)
	if st == nil then
		return 0
	end
	local n = 0
	local stack = { st }
	while #stack > 0 do
		local cur = table.remove(stack) :: any
		for _, child in cur.children do
			n += 1
			local cst = stateOf(child)
			if cst then
				table.insert(stack, cst)
			end
		end
	end
	return n
end

function MockInstance.new(className: string, parent: any?)
	if className == "UIShadow" and not MockInstance.styleFeatures.UIShadow then
		error(`Unable to create an Instance of type "{className}"`, 2)
	end
	createdCount += 1
	local self = setmetatable({}, MT)
	rawset(self, STATE, {
		ClassName = className,
		Name = className,
		Parent = nil,
		children = {},
		props = defaultsFor(className),
		attrs = {},
		tags = {},
		signals = {},
		propSignals = {},
		attrSignals = {},
		destroyed = false,
		fired = {},
	})
	if parent ~= nil then
		self.Parent = parent
	end
	return self
end

function MockInstance.is(value: any): boolean
	return stateOf(value) ~= nil
end

function MockInstance.state(inst: any)
	return stateOf(inst)
end

-- Fonctions « méthodes » communes
local Methods = {}

function Methods.IsA(self, className: string): boolean
	return isA(self[STATE].ClassName, className)
end

function Methods.FindFirstChild(self, name: string, recursive: boolean?)
	for _, c in self[STATE].children do
		if c[STATE].Name == name then
			return c
		end
	end
	if recursive then
		for _, c in self[STATE].children do
			local found = Methods.FindFirstChild(c, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function Methods.FindFirstChildOfClass(self, className: string)
	for _, c in self[STATE].children do
		if c[STATE].ClassName == className then
			return c
		end
	end
	return nil
end

function Methods.FindFirstChildWhichIsA(self, className: string, recursive: boolean?)
	for _, c in self[STATE].children do
		if isA(c[STATE].ClassName, className) then
			return c
		end
	end
	if recursive then
		for _, c in self[STATE].children do
			local found = Methods.FindFirstChildWhichIsA(c, className, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function Methods.FindFirstAncestor(self, name: string)
	local p = self[STATE].Parent
	while p do
		if p[STATE].Name == name then
			return p
		end
		p = p[STATE].Parent
	end
	return nil
end

function Methods.FindFirstAncestorOfClass(self, className: string)
	local p = self[STATE].Parent
	while p do
		if p[STATE].ClassName == className then
			return p
		end
		p = p[STATE].Parent
	end
	return nil
end

function Methods.FindFirstAncestorWhichIsA(self, className: string)
	local p = self[STATE].Parent
	while p do
		if isA(p[STATE].ClassName, className) then
			return p
		end
		p = p[STATE].Parent
	end
	return nil
end

function Methods.WaitForChild(self, name: string, timeout: number?)
	local found = Methods.FindFirstChild(self, name)
	if found then
		return found
	end
	local limit = timeout or MockInstance.waitTimeout
	local start = os.clock()
	while os.clock() - start < limit do
		task.wait()
		found = Methods.FindFirstChild(self, name)
		if found then
			return found
		end
	end
	if timeout == nil then
		warnOnce(`Infinite yield possible on '{Methods.GetFullName(self)}:WaitForChild("{name}")'`)
	end
	return nil
end

function Methods.GetChildren(self)
	return table.clone(self[STATE].children)
end

function Methods.GetDescendants(self)
	local out = {}
	local function walk(inst)
		for _, c in inst[STATE].children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function Methods.IsDescendantOf(self, ancestor)
	local p = self[STATE].Parent
	while p do
		if p == ancestor then
			return true
		end
		p = p[STATE].Parent
	end
	return false
end

function Methods.IsAncestorOf(self, descendant)
	return Methods.IsDescendantOf(descendant, self)
end

function Methods.GetFullName(self)
	local parts = {}
	local cur = self
	while cur and cur[STATE].ClassName ~= "DataModel" do
		table.insert(parts, 1, cur[STATE].Name)
		cur = cur[STATE].Parent
	end
	return table.concat(parts, ".")
end

function Methods.Destroy(self)
	local st = self[STATE]
	if st.destroyed then
		return
	end
	signalOf(st, "Destroying"):Fire()
	for _, c in table.clone(st.children) do
		Methods.Destroy(c)
	end
	self.Parent = nil
	st.destroyed = true
	for _, s in st.signals do
		s:DisconnectAll()
	end
	for _, s in st.propSignals do
		s:DisconnectAll()
	end
end

function Methods.ClearAllChildren(self)
	for _, c in table.clone(self[STATE].children) do
		Methods.Destroy(c)
	end
end

function Methods.Clone(self)
	local st = self[STATE]
	local copy = MockInstance.new(st.ClassName)
	local cst = copy[STATE]
	cst.Name = st.Name
	for k, v in st.props do
		cst.props[k] = v
	end
	for k, v in st.attrs do
		cst.attrs[k] = v
	end
	for k, v in st.tags do
		cst.tags[k] = v
	end
	for _, c in st.children do
		local cc = Methods.Clone(c)
		cc.Parent = copy
	end
	return copy
end

local ATTRIBUTE_TYPES = {
	["nil"] = true,
	string = true,
	boolean = true,
	number = true,
	UDim = true,
	UDim2 = true,
	BrickColor = true,
	Color3 = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	NumberSequence = true,
	ColorSequence = true,
	NumberRange = true,
	Rect = true,
	Font = true,
	EnumItem = true,
}

function Methods.SetAttribute(self, name: string, value: any)
	local t = typeof(value)
	if not ATTRIBUTE_TYPES[t] then
		error(`SetAttribute: type {t} non supporté par les attributs Roblox ({name})`, 2)
	end
	local st = self[STATE]
	if st.attrs[name] ~= value then
		st.attrs[name] = value
		signalOf(st, "AttributeChanged"):Fire(name)
		local s = st.attrSignals[name]
		if s then
			s:Fire()
		end
	end
end

function Methods.GetAttribute(self, name: string)
	return self[STATE].attrs[name]
end

function Methods.GetAttributes(self)
	return table.clone(self[STATE].attrs)
end

function Methods.GetAttributeChangedSignal(self, name: string)
	local st = self[STATE]
	local s = st.attrSignals[name]
	if not s then
		s = Signal.new()
		st.attrSignals[name] = s
	end
	return s
end

function Methods.GetPropertyChangedSignal(self, prop: string)
	return propSignal(self[STATE], prop)
end

function Methods.AddTag(self, tag: string)
	self[STATE].tags[tag] = true
end

function Methods.RemoveTag(self, tag: string)
	self[STATE].tags[tag] = nil
end

function Methods.HasTag(self, tag: string)
	return self[STATE].tags[tag] == true
end

function Methods.GetTags(self)
	local out = {}
	for t in self[STATE].tags do
		table.insert(out, t)
	end
	return out
end

function Methods.GetPivot(self)
	local st = self[STATE]
	if isA(st.ClassName, "BasePart") then
		return st.props.CFrame
	end
	local pp = st.props.PrimaryPart
	if pp then
		return pp[STATE].props.CFrame
	end
	return st.props.WorldPivot or CFrame.new()
end

function Methods.PivotTo(self, cf)
	local st = self[STATE]
	if isA(st.ClassName, "BasePart") then
		self.CFrame = cf
		return
	end
	local current = Methods.GetPivot(self)
	local delta = cf * current:Inverse()
	for _, d in Methods.GetDescendants(self) do
		if isA(d[STATE].ClassName, "BasePart") then
			d.CFrame = delta * d[STATE].props.CFrame
		end
	end
	st.props.WorldPivot = cf
end

function Methods.GetBoundingBox(self)
	return Methods.GetPivot(self), Vector3.new(4, 4, 4)
end

function Methods.GetExtentsSize(_self)
	return Vector3.new(4, 4, 4)
end

function Methods.GetMass(_self)
	return 1
end

function Methods.GetNetworkOwner(_self)
	return nil
end

function Methods.GetTouchingParts(_self)
	return {}
end

function Methods.GetConnectedParts(_self)
	return {}
end

-- Remotes et Bindables
function Methods.FireClient(self, player, ...)
	assert(
		MockInstance.is(player) and player[STATE].ClassName == "Player",
		"FireClient : le 1er argument doit être un Player"
	)
	table.insert(self[STATE].fired, { kind = "client", player = player, args = table.pack(...) })
	if MockInstance.onFireClient then
		MockInstance.onFireClient(self, player, ...)
	end
end

function Methods.FireAllClients(self, ...)
	table.insert(self[STATE].fired, { kind = "all", args = table.pack(...) })
	if MockInstance.onFireAllClients then
		MockInstance.onFireAllClients(self, ...)
	end
end

function Methods.FireServer(self, ...)
	table.insert(self[STATE].fired, { kind = "server", args = table.pack(...) })
	if MockInstance.onFireServer then
		MockInstance.onFireServer(self, ...)
	end
end

function Methods.InvokeServer(self, ...)
	local cb = self[STATE].props.OnServerInvoke
	if MockInstance.localPlayer and cb then
		return cb(MockInstance.localPlayer, ...)
	end
	if MockInstance.onInvokeServer then
		return MockInstance.onInvokeServer(self, ...)
	end
	return nil
end

function Methods.InvokeClient(_self)
	error("InvokeClient est interdit dans ce projet (un client peut bloquer le serveur)", 2)
end

function Methods.Fire(self, ...)
	signalOf(self[STATE], "Event"):Fire(...)
end

function Methods.Invoke(self, ...)
	local cb = self[STATE].props.OnInvoke
	assert(cb, "BindableFunction sans OnInvoke")
	return cb(...)
end

-- Sons, animations
function Methods.Play(self)
	local st = self[STATE]
	if st.ClassName == "Sound" then
		st.props.Playing = true
		signalOf(st, "Played"):Fire(st.props.SoundId)
	end
end

function Methods.Stop(self)
	local st = self[STATE]
	st.props.Playing = false
	signalOf(st, "Stopped"):Fire()
end

-- Humanoid
function Methods.TakeDamage(self, amount: number)
	local st = self[STATE]
	if st.ClassName ~= "Humanoid" then
		return
	end
	self.Health = math.max(0, st.props.Health - amount)
end

function Methods.MoveTo(self, _pos, _part)
	local st = self[STATE]
	task.defer(function()
		signalOf(st, "MoveToFinished"):Fire(true)
	end)
end

function Methods.GetState(_self)
	return Enum.HumanoidStateType.Running
end

function Methods.GetAppliedDescription(_self)
	return MockInstance.new("HumanoidDescription")
end

function Methods.LoadAnimation(self, animation)
	local track = MockInstance.new("AnimationTrack")
	track.Animation = animation
	track.IsPlaying = false
	track.Length = 1
	track.Speed = 1
	return track
end

function Methods.GetPlayingAnimationTracks(_self)
	return {}
end

function Methods.AdjustSpeed(_self, _speed) end

-- Player
function Methods.Kick(self, message: string?)
	local st = self[STATE]
	st.props.KickedWith = message or ""
	if MockInstance.onKick then
		MockInstance.onKick(self, message)
	end
end

function Methods.LoadCharacter(self)
	if MockInstance.onLoadCharacter then
		MockInstance.onLoadCharacter(self)
	end
end

function Methods.IsInGroup(_self, _groupId)
	return false
end

function Methods.GetRankInGroup(_self, _groupId)
	return 0
end

function Methods.GetRoleInGroup(_self, _groupId)
	return "Guest"
end

function Methods.IsFriendsWith(self, userId)
	if MockInstance.areFriends then
		return MockInstance.areFriends(self[STATE].props.UserId, userId)
	end
	return false
end

function Methods.GetFriendsOnline(_self)
	return {}
end

function Methods.GetMouse(_self)
	return MockInstance.new("PlayerMouse")
end

function Methods.GetNetworkPing(_self)
	return 0.05
end

function Methods.GetJoinData(_self)
	return {}
end

-- Services génériques
function Methods.GetService(self, name: string)
	local svc = Methods.FindFirstChild(self, name)
	if svc then
		return svc
	end
	if MockInstance.serviceFactory then
		svc = MockInstance.serviceFactory(name)
		if svc then
			return svc
		end
	end
	error(`[harness] Service non simulé : {name} (ajoutez-le dans tests/harness/Services.luau)`, 2)
end
Methods.FindService = Methods.GetService

for _, name in NOOP do
	if Methods[name] == nil then
		Methods[name] = function() end
	end
end

MockInstance.Methods = Methods

-- Méthodes spécifiques injectées par Services.luau (ex. Players:GetPlayers)
MockInstance.classMethods = {} :: { [string]: { [string]: any } }

-- Moteur de texte simulé (lot B1, docs/04 §27.13 N10 ; Text_policy.spec) : TextBounds d'un texte
-- calculé à la lecture depuis TextSize, le facteur de la taille de texte choisie par le joueur
-- (GuiService.PreferredTextSize : `factor`, 1 à Medium) et la contrainte UITextSizeConstraint :
--   * constraint = "respected" : comme la documentation de Roblox, un texte contraint n'est jamais
--     agrandi au-delà de MaxTextSize (ni réduit sous MinTextSize) ;
--   * constraint = "ignored" : le moteur agrandit quand même (comportement jamais mesuré sur la PS5,
--     que UI/Text doit compenser).
-- Un texte TextScaled n'est pas agrandi (documentation de PreferredTextSize). Largeur approchée
-- (0,5 × taille par caractère, comme TextService:GetTextSize du harnais) ; hauteur exacte : lignes
-- (« \n ») × taille rendue. Défaut : facteur 1 (Medium).
MockInstance.textEngine = { factor = 1, constraint = "respected" }

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

function MockInstance.renderedTextSize(inst): number
	local st = inst[STATE]
	local props = st.props
	local size = props.TextSize or 14
	if props.TextScaled == true then
		return size
	end
	local engine = MockInstance.textEngine
	local rendered = size * (engine.factor or 1)
	if engine.constraint ~= "ignored" then
		for _, c in st.children do
			local cst = c[STATE]
			if cst.ClassName == "UITextSizeConstraint" then
				local lo = cst.props.MinTextSize or 1
				local hi = cst.props.MaxTextSize or 100
				rendered = math.clamp(rendered, lo, math.max(lo, hi))
				break
			end
		end
	end
	return rendered
end

local function textBounds(inst)
	local st = inst[STATE]
	local text = st.props.Text or ""
	local size = MockInstance.renderedTextSize(inst)
	local lines = 1
	for _ in string.gmatch(text, "\n") do
		lines += 1
	end
	return Vector2.new((utf8.len(text) or #text) * size * 0.5, if text == "" then 0 else lines * size)
end

MT.__index = function(self, key)
	local st = self[STATE]
	if key == "ClassName" then
		return st.ClassName
	elseif key == "Name" then
		return st.Name
	elseif key == "Parent" then
		return st.Parent
	elseif key == "TextBounds" and TEXT_CLASSES[st.ClassName] then
		return textBounds(self)
	end
	local cm = MockInstance.classMethods[st.ClassName]
	if cm and cm[key] ~= nil then
		return cm[key]
	end
	local m = Methods[key]
	if m then
		return m
	end
	local v = st.props[key]
	if v ~= nil then
		return v
	end
	if EVENTS[key] then
		return signalOf(st, key)
	end
	for _, c in st.children do
		if c[STATE].Name == key then
			return c
		end
	end
	if STRICT_CONTAINERS[st.ClassName] then
		error(`{key} is not a valid member of {st.ClassName} "{Methods.GetFullName(self)}"`, 2)
	end
	return nil
end

local function fireChanged(st, key: string)
	local ps = st.propSignals[key]
	if ps then
		ps:Fire()
	end
	local cs = st.signals.Changed
	if cs then
		cs:Fire(key)
	end
end

MT.__newindex = function(self, key, value)
	local st = self[STATE]
	if key == "Parent" then
		if st.destroyed then
			error(
				`The Parent property of {st.Name} is locked, current parent: NULL, new parent {stateOf(value) and stateOf(
					value
				).Name or "nil"}`,
				2
			)
		end
		if value ~= nil and not MockInstance.is(value) then
			error("Parent doit être une Instance", 2)
		end
		if value == self then
			error("Impossible de se définir soi-même comme parent", 2)
		end
		local old = st.Parent
		if old == value then
			return
		end
		if old then
			local ost = old[STATE]
			local i = table.find(ost.children, self)
			if i then
				table.remove(ost.children, i)
			end
			signalOf(ost, "ChildRemoved"):Fire(self)
		end
		st.Parent = value
		if value then
			table.insert(value[STATE].children, self)
			signalOf(value[STATE], "ChildAdded"):Fire(self)
			local anc = value
			while anc do
				local ast = anc[STATE]
				if ast.signals.DescendantAdded then
					ast.signals.DescendantAdded:Fire(self)
				end
				anc = ast.Parent
			end
		end
		signalOf(st, "AncestryChanged"):Fire(self, value)
		fireChanged(st, "Parent")
		return
	elseif key == "Name" then
		st.Name = tostring(value)
		fireChanged(st, "Name")
		return
	elseif key == "ClassName" then
		error("ClassName est en lecture seule", 2)
	end
	if EVENTS[key] or Methods[key] then
		error(`{key} ne peut pas être assigné sur {st.ClassName}`, 2)
	end
	-- styles récents (MockInstance.styleFeatures) : propriété inconnue d'un moteur qui ne les a pas
	if st.ClassName == "UIGradient" and key == "Type" then
		if not MockInstance.styleFeatures.RadialGradient then
			error(`Type is not a valid member of UIGradient "{st.Name}"`, 2)
		end
		if value ~= "Linear" and value ~= "Radial" then
			error(`Invalid value for enum UIGradientType`, 2)
		end
	elseif st.ClassName == "UIShadow" and not SHADOW_PROPS[key] then
		error(`{key} is not a valid member of UIShadow "{st.Name}"`, 2)
	end
	if isA(st.ClassName, "BasePart") then
		if key == "CFrame" then
			st.props.Position = value.Position
		elseif key == "Position" then
			local cf = st.props.CFrame
			st.props.CFrame = cf - cf.Position + value
		end
	end
	if st.ClassName == "Humanoid" and key == "Health" then
		local old = st.props.Health
		value = math.clamp(value, 0, st.props.MaxHealth)
		st.props.Health = value
		if value ~= old then
			signalOf(st, "HealthChanged"):Fire(value)
			fireChanged(st, "Health")
			if value <= 0 and old > 0 then
				signalOf(st, "Died"):Fire()
			end
		end
		return
	end
	if st.props[key] ~= value then
		st.props[key] = value
		fireChanged(st, key)
	end
end

-- itérer une instance ne montre rien (la clé privée de l'état reste cachée), comme avant
MT.__iter = function()
	return next, {}
end

MT.__tostring = function(self)
	return self[STATE].Name
end

return MockInstance
