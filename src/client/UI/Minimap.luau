--!strict
-- Minimap — paquet « client-hud » (docs/04-architecture.md §13.13).
-- Minicarte circulaire en Frames, haut droite (−16, 16), 150 × 150 ; M / appui / croix bas →
-- 300 × 300. Calculée depuis les données serveur (miettes et événements), indépendante du streaming.
-- Contenu : un point par joueur (taille selon la longueur de file, couleur du Nid ; le local
-- distingué par un contour blanc et une pointe qui suit la caméra), Comète clignotante 2 Hz (porteur
-- ou au sol ; point d'impact pendant l'alerte), Balise, Gloomwisps en violet, Nids (couleur du
-- propriétaire, gris si libre), anneaux des zones.
-- Mise à jour à 10 Hz (pas chaque image) ; réserve de Frames (aucune création en rafale).
-- Affichage progressif : le conteneur est confié au HUD (HUD.registerElement("minimap")).
-- GDD : §6.4, §10.2, §9.4 (porteur).
-- Dépendances : Util/Prefs, UI/Root, UI/Theme, UI/Create, WorldStateController, InputController,
-- Logic/WorldLayout, Config/Cosmetics, Config/Zones, Shared/Util/Clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Util.Clock)
local Zones = require(Shared.Config.Zones)
local Cosmetics = require(Shared.Config.Cosmetics)
local Balance = require(Shared.Config.Balance)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local WorldStateController = require(Client.Controllers.WorldStateController)
local InputController = require(Client.Controllers.InputController)
local HUD = require(Client.UI.HUD)
local Widgets = require(Client.UI.Hud.Widgets)

local Minimap = {}

-- Constantes (GDD §6.4, §10.2) ------------------------------------------------------------------

local DISPLAY_ORDER = 11
local MARGIN = 16
local SMALL, LARGE = 150, 300
local EXPAND_TIME = 0.2
local UPDATE_INTERVAL = 0.1 -- 10 Hz
local WORLD_RADIUS = Zones.Island.Radius + 6 -- marge : les Nids (r ≈ 150 + 17) restent dedans
local DOT_MIN, DOT_MAX = 7, 15 -- px (référence, carte réduite) selon la longueur de file
local LOCAL_EXTRA = 3
local NEST_DOT = 9
local WISP_DOT = 8
local COMET_DOT = 13
local HEADING_WIDTH, HEADING_LENGTH = 4, 10
local BLINK_HZ = 2
local WISP_COLOR = Color3.fromRGB(170, 90, 230)
local COMET_COLOR = Color3.fromRGB(255, 205, 60)
local BEACON_COLOR = Zones.Beacon.Color
local SLOTS = Zones.Nests.Count

-- État ------------------------------------------------------------------------------------------

type Dot = { frame: Frame, used: boolean }

local started = false
local holder: Frame? = nil
local disc: Frame? = nil
local content: Frame? = nil
local expanded = false
local lastUpdate = -math.huge
local blinkTime = 0
local playerDots: { [number]: Frame } = {} -- par slot
local nestDots: { [number]: Frame } = {}
local wispPool: { Dot } = {}
local cometDot: Frame? = nil
local heading: Frame? = nil

-- Projection ------------------------------------------------------------------------------------

-- Position 2D (0-1, 0-1) d'un point du monde sur la carte (pur) : nord (−Z) en haut, bornée au cercle
function Minimap.project(worldPos: Vector3): Vector2
	if typeof(worldPos) ~= "Vector3" then
		return Vector2.new(0.5, 0.5)
	end
	local x, z = worldPos.X, worldPos.Z
	if x ~= x or z ~= z or math.abs(x) == math.huge or math.abs(z) == math.huge then
		return Vector2.new(0.5, 0.5)
	end
	local v = Vector2.new(x, z) / WORLD_RADIUS
	if v.Magnitude > 1 then
		v = v.Unit
	end
	return Vector2.new(0.5 + v.X * 0.5, 0.5 + v.Y * 0.5)
end

-- Construction ----------------------------------------------------------------------------------

local function dot(name: string, size: number, color: Color3, z: number, parent: Instance): Frame
	return Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
		Visible = false,
		Parent = parent,
	}, { Widgets.round() })
end

local function ring(name: string, radius: number, color: Color3, transparency: number, parent: Instance)
	local scale = radius / WORLD_RADIUS
	Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scale, scale),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = parent,
	}, { Widgets.round() })
end

local function build()
	if holder and holder.Parent then
		return
	end
	local safe = Root.safe("Minimap", DISPLAY_ORDER)
	local frame = Widgets.holder(
		"Minimap",
		UDim2.fromOffset(SMALL, SMALL),
		UDim2.new(1, -MARGIN, 0, MARGIN),
		Vector2.new(1, 0),
		safe
	)
	local button = Create("TextButton", {
		Name = "Disc",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(22, 18, 40),
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		ClipsDescendants = true,
		Parent = frame,
	}, { Widgets.round(), Widgets.stroke(Widgets.STROKE, 3) })
	button.Activated:Connect(function()
		Minimap.toggle()
	end)
	Juice.press(button)
	local inner = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = button,
	})
	-- zones : Prairie, Clairière, Cratère (anneaux concentriques)
	for _, zone in Zones.List do
		local tint = if zone.key == "meadow"
			then Color3.fromRGB(70, 110, 80)
			elseif zone.key == "glade" then Zones.Ground.GladeColor
			else Zones.Ground.CraterColor
		ring("Zone_" .. zone.key, zone.outer, tint, 0.55, inner)
	end
	-- Balise au centre
	local beacon = dot("Beacon", 10, BEACON_COLOR, 4, inner)
	beacon.Position = UDim2.fromScale(0.5, 0.5)
	beacon.Visible = true
	Widgets.stroke(Zones.Beacon.RingColor, 2).Parent = beacon
	-- Nids
	for slot = 1, SLOTS do
		local p = Minimap.project(WorldLayout.nestCenter(slot))
		local nest = dot("Nest" .. slot, NEST_DOT, Cosmetics.FreeNestColor, 3, inner)
		nest.Position = UDim2.fromScale(p.X, p.Y)
		nest.Visible = true
		local corner = nest:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, 3)
		end
		nestDots[slot] = nest
	end
	-- un point par joueur (slot)
	for slot = 1, SLOTS do
		local color = Cosmetics.NestColors[slot] or Theme.Colors.Text
		local p = dot("Player" .. slot, DOT_MIN, color, 6, inner)
		Widgets.stroke(Widgets.STROKE, 1.5).Parent = p
		playerDots[slot] = p
	end
	local comet = dot("Comet", COMET_DOT, COMET_COLOR, 8, inner)
	Widgets.stroke(Color3.new(1, 1, 1), 2).Parent = comet
	cometDot = comet
	-- pointe du joueur local (direction de la caméra). Un GuiObject tourne autour de SON centre
	-- (pas de son AnchorPoint) : le conteneur est centré sur le point du joueur et la pointe occupe
	-- sa moitié haute, si bien qu'en tournant elle orbite autour du point
	local pivot = Create("Frame", {
		Name = "Heading",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(HEADING_WIDTH, HEADING_LENGTH * 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 7,
		Visible = false,
		Parent = inner,
	})
	Create("Frame", {
		Name = "Tip",
		Size = UDim2.fromOffset(HEADING_WIDTH, HEADING_LENGTH),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = pivot,
	}, { Widgets.round() })
	heading = pivot
	holder = frame
	disc = button
	content = inner
end

-- Mise à jour (10 Hz) ---------------------------------------------------------------------------

local function wispDot(index: number): Frame
	local entry = wispPool[index]
	if entry == nil then
		local frame = dot("Wisp", WISP_DOT, WISP_COLOR, 5, content :: Frame)
		entry = { frame = frame, used = false }
		wispPool[index] = entry
	end
	entry.used = true
	return entry.frame
end

local function place(frame: Frame, pos: Vector3)
	local p = Minimap.project(pos)
	frame.Position = UDim2.fromScale(p.X, p.Y)
end

local function localPosition(): Vector3?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function update(now: number)
	if content == nil then
		return
	end
	local mySlot = WorldStateController.localSlot()
	local cap = Balance.Conga.AbsoluteMax
	-- Nids : couleur du propriétaire, gris si libre
	for slot, nest in nestDots do
		local owner = WorldStateController.userAt(slot)
		nest.BackgroundColor3 = if owner ~= 0 then Cosmetics.NestColors[slot] else Cosmetics.FreeNestColor
	end
	-- joueurs : tête des miettes serveur (le local : son personnage)
	for slot, frame in playerDots do
		local owner = WorldStateController.userAt(slot)
		local pos: Vector3? = nil
		if slot == mySlot then
			pos = localPosition()
		end
		if pos == nil and owner ~= 0 then
			local trail = WorldStateController.trail(slot)
			pos = if trail then trail:head() else nil
		end
		if pos == nil or (owner == 0 and slot ~= mySlot) then
			frame.Visible = false
		else
			local n = WorldStateController.lineLength(slot)
			local size = DOT_MIN + (DOT_MAX - DOT_MIN) * math.clamp(n / cap, 0, 1) * 3
			size = math.min(size, DOT_MAX)
			if slot == mySlot then
				size += LOCAL_EXTRA
			end
			frame.Size = UDim2.fromOffset(size, size)
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if slot == mySlot then Color3.new(1, 1, 1) else Widgets.STROKE
				stroke.Thickness = if slot == mySlot then 2.5 else 1.5
			end
			frame.ZIndex = if slot == mySlot then 7 else 6
			place(frame, pos :: Vector3)
			frame.Visible = true
		end
	end
	-- pointe du joueur local : direction de la caméra (nord en haut)
	local h = heading
	local mine = playerDots[mySlot]
	if h then
		local camera = workspace.CurrentCamera
		if mine and mine.Visible and camera then
			local look = camera.CFrame.LookVector
			h.Visible = true
			h.Position = mine.Position
			h.Rotation = math.deg(math.atan2(look.X, -look.Z))
		else
			h.Visible = false
		end
	end
	-- Gloomwisps (violet)
	for _, entry in wispPool do
		entry.used = false
	end
	local ev = WorldStateController.events()
	local used = 0
	if ev and type(ev.wisps) == "table" then
		for _, w in ev.wisps do
			local pos = WorldStateController.wispPosition(w.id, now)
			if pos then
				used += 1
				local frame = wispDot(used)
				place(frame, pos)
				frame.Visible = true
			end
		end
	end
	for _, entry in wispPool do
		if not entry.used then
			entry.frame.Visible = false
		end
	end
	-- Comète : au sol ou portée (position), point d'impact pendant l'alerte
	local comet = cometDot
	if comet then
		local c = if ev then ev.comet else nil
		local pos: Vector3? = nil
		if c then
			if c.phase == "warn" then
				pos = Vector3.new(c.x, 0, c.z)
			elseif c.phase == "ground" or c.phase == "carried" then
				pos = WorldStateController.cometPosition(now)
			end
		end
		if pos then
			place(comet, pos)
			comet.Visible = true
		else
			comet.Visible = false
		end
	end
end

local function blink()
	local comet = cometDot
	if comet and comet.Visible then
		-- clignotement à 2 Hz (≤ 3 Hz, GDD §13.2)
		local on = math.floor(blinkTime * BLINK_HZ * 2) % 2 == 0
		comet.BackgroundTransparency = if on or Prefs.reducedMotion() then 0 else 0.7
	end
end

-- API -------------------------------------------------------------------------------------------

function Minimap.setExpanded(value: boolean)
	build()
	local frame = holder :: Frame
	expanded = value == true
	local size = if expanded then LARGE else SMALL
	local target = UDim2.fromOffset(size, size)
	if Prefs.reducedMotion() then
		frame.Size = target
	else
		Juice.tween(frame, EXPAND_TIME, { Size = target }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
end

function Minimap.toggle()
	if not HUD.isRevealed("minimap") then
		return
	end
	Minimap.setExpanded(not expanded)
end

function Minimap.isExpanded(): boolean
	return expanded
end

function Minimap.Init()
	build()
	HUD.registerElement("minimap", holder :: Frame, disc)
end

function Minimap.Start()
	if started then
		return
	end
	started = true
	InputController.MinimapToggled:Connect(Minimap.toggle)
	RunService.Heartbeat:Connect(function(dt: number)
		blinkTime += if dt == dt then math.clamp(dt, 0, 0.25) else 0
		blink()
		if blinkTime - lastUpdate >= UPDATE_INTERVAL or blinkTime < lastUpdate then
			lastUpdate = blinkTime
			update(Clock.now())
		end
	end)
end

-- Exposé pour les tests
Minimap._state = function()
	return {
		holder = holder,
		playerDots = playerDots,
		nestDots = nestDots,
		wispPool = wispPool,
		comet = cometDot,
		heading = heading,
	}
end
Minimap._update = update

return Minimap
