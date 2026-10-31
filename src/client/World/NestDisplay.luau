--!strict
-- NestDisplay — aide de CongaRenderer (paquet « client-world ») : tout ce que le client dessine
-- autour des 12 Nids à partir de leurs ATTRIBUTS (docs §3.2) et de la stèle de la Balise.
--   * perchés (PerchData « code.étoiles,… », dans l'ordre des perchoirs) : un rig par perché posé
--     sur le dessus de son perchoir (attribut TopY du perchoir, sinon WorldLayout), rebond lent,
--     tourné vers le centre ; niveaux de détail décidés par le planificateur de CongaRenderer
--   * « +N » toutes les 2,5 s au-dessus des Balance.Render.PerchFloaters (8) perchés les plus
--     rentables du Nid LOCAL seulement (N = revenu passif × M sur 2,5 s, GDD §9.3)
--   * perchoir qui pousse du sol (Y 0 → hauteur en 0,35 s Back Out) quand un perchoir apparaît
--   * panneau BillboardGui (nom, badge doré « ★ VIP » du pass VIP Star, « ★ R », titre traduit ;
--     Y = 16, distance max 120)
--   * constellation (Balls Néon de 1,2 reliées par des Beams, Y = 45) ; étoile exposée pour la
--     séquence de Supernova de VFXController
--   * liens d'équipage la nuit (Beam entre les Nids des équipiers, tracé en 0,6 s, visible aussi de
--     jour quelques secondes à la formation, GDD §9.4)
--   * SpotLight sur le meilleur perchoir du Nid local ; stèle « Plus longues congas » (SurfaceGui,
--     attributs Live / Record / Weekly « userId:nom:n;… »)
-- GDD : §6.4, §6.6, §9.3, §11.3, §12.8.
-- Dépendances : WorldStateController, StateController, Util/Prefs, UI/Juice, Render/NebbyBuilder,
-- Logic/WorldLayout, Logic/Formulas, Config/*, Shared/Util/Clock, World/{Fx,RigPool,FloatText}.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Nebbies = require(Shared.Config.Nebbies)
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Logic.Formulas)
local WorldLayout = require(Shared.Logic.WorldLayout)
local NebbyBuilder = require(Shared.Render.NebbyBuilder)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local Prefs = require(Client.Util.Prefs)
local Juice = require(Client.UI.Juice)
local WorldStateController = require(Client.Controllers.WorldStateController)

local Fx = require(script.Parent.Fx)
local RigPool = require(script.Parent.RigPool)
local FloatText = require(script.Parent.FloatText)

local NestDisplay = {}

-- Constantes graphiques (GDD §6.6, §9.3, §11.3) ---------------------------------------------------

local SLOT_COUNT = Zones.Nests.Count
local MAX_PERCHES = 46
local PERCH_BOUNCE = 0.12
local PERCH_BOUNCE_SPEED = 1.6
local FLOATER_PERIOD = 2.5
local FLOATER_RANGE = 80 -- studs : « +N » seulement si le point de vue est près du Nid local
local FLOATER_COLOR = Color3.fromRGB(255, 220, 110)
local FLOATER_SCALE = 0.55
local GROW_SECONDS = 0.35
local GROW_RANGE = 120
local PANEL_WIDTH, PANEL_HEIGHT = 12, 4.2
local STAR_SIZE = 1.2
local STAR_COLOR = Color3.fromRGB(255, 240, 190)
local STAR_BEAM_WIDTH = 0.25
local MAX_STARS = 30
local CREW_LINK_HEIGHT = 8
local CREW_LINK_WIDTH = 0.6
local CREW_DRAW_SECONDS = 0.6
-- GDD §9.4 « Équipage formé : Beam tracé en 0,6 s » : visible aussi de jour pendant le tracé et un
-- court instant après, puis seulement la nuit (§6.1)
local CREW_SHOW_SECONDS = 4
local VIP_COLOR = Color3.fromRGB(255, 205, 60)
local NIGHT_FROM, NIGHT_UNTIL = 19, 5 -- ClockTime : liens d'équipage visibles la nuit
local SPOT_HEIGHT = 9
local SPOT_RANGE = 16
local SPOT_ANGLE = 45
local SPOT_COLOR = Color3.fromRGB(255, 225, 160)
local BOARD_PIXELS_PER_STUD = 40
local BOARD_LIVE, BOARD_WEEKLY = Balance.Leaderboard.TopLive, Balance.Leaderboard.TopWeekly

type PerchView = RigPool.View & {
	slot: number,
	index: number,
	top: Vector3,
	look: Vector3,
	phase: number,
}

type NestState = {
	slot: number,
	model: Model,
	perched: { PerchView },
	perchCount: number,
	supernovas: number,
	panel: BillboardGui,
	nameLabel: TextLabel,
	vipLabel: TextLabel,
	rankLabel: TextLabel,
	titleLabel: TextLabel,
	vip: boolean,
	stars: { BasePart },
	conns: { RBXScriptConnection },
	tops: { [number]: Vector3 },
	floaterAt: { number },
}

type CrewLink = {
	key: string,
	a: Attachment,
	b: Attachment,
	beam: Beam,
	from: Vector3,
	to: Vector3,
	start: number,
}

local root: Folder? = nil
local nestFolder: Folder? = nil
local anchorPart: BasePart? = nil
local nests: { [number]: NestState } = {}
local links: { [string]: CrewLink } = {}
local spot: BasePart? = nil
local spotLight: SpotLight? = nil
local board: BasePart? = nil
local boardGui: SurfaceGui? = nil
local boardConn: RBXScriptConnection? = nil
local started = false

-- Outils -------------------------------------------------------------------------------------------

local function validSlot(x: any): boolean
	return type(x) == "number" and x % 1 == 0 and x >= 1 and x <= SLOT_COUNT
end

local function perchFolder(state: NestState): Instance?
	return state.model:FindFirstChild("Perches")
end

-- Dessus du perchoir `index` du Nid (attribut TopY posé par le serveur, sinon géométrie partagée)
local function perchTop(state: NestState, index: number): Vector3
	local cached = state.tops[index]
	if cached then
		return cached
	end
	local cf = WorldLayout.perchCFrame(state.slot, index)
	local y = cf.Position.Y + Zones.Perches.Height
	local folder = perchFolder(state)
	local part = if folder then folder:FindFirstChild(string.format("Perch_%02d", index)) else nil
	if part then
		local top = part:GetAttribute("TopY")
		if type(top) == "number" and top == top then
			y = top
		end
	end
	local p = Vector3.new(cf.Position.X, y, cf.Position.Z)
	state.tops[index] = p
	return p
end

local function parsePerchData(raw: any): { { code: number, stars: number } }
	local out = {}
	if type(raw) ~= "string" or #raw > MAX_PERCHES * 8 then
		return out
	end
	for entry in string.gmatch(raw, "[^,]+") do
		local code, stars = string.match(entry, "^(%d+)%.(%d+)$")
		local c, s = tonumber(code), tonumber(stars)
		if c and s and Nebbies.isValidCode(c) and s >= 1 and s <= Nebbies.MAX_STARS then
			table.insert(out, { code = c, stars = s })
			if #out >= MAX_PERCHES then
				break
			end
		end
	end
	return out
end

local function releaseView(view: PerchView)
	local rig = view.rig
	if rig then
		view.rig = nil
		RigPool.release(rig)
	end
end

-- Perchés -------------------------------------------------------------------------------------------

local function refreshPerched(state: NestState)
	local entries = parsePerchData(state.model:GetAttribute("PerchData"))
	local perched = state.perched
	for i, e in entries do
		local view = perched[i]
		if view and (view.code ~= e.code or view.stars ~= e.stars) then
			releaseView(view)
			view = nil
		end
		if view == nil then
			local cf = WorldLayout.perchCFrame(state.slot, i)
			local rarity = Nebbies.rarityOf((Nebbies.unpack(e.code)))
			perched[i] = {
				code = e.code,
				stars = e.stars,
				rig = nil,
				want = "hidden",
				dist = math.huge,
				bubble = false,
				pinned = nil,
				mythic = rarity >= 6,
				bright = rarity >= 5,
				slot = state.slot,
				index = i,
				top = perchTop(state, i),
				look = cf.LookVector,
				phase = i * 0.9,
			}
		end
	end
	for i = #perched, #entries + 1, -1 do
		releaseView(perched[i])
		perched[i] = nil
	end
end

-- Perchoir qui pousse du sol (pièce répliquée du serveur, animation purement locale)
local function growPerch(part: Instance, focus: Vector3?)
	if not part:IsA("BasePart") or Juice.reducedMotion() then
		return
	end
	if focus and (part.Position - focus).Magnitude > GROW_RANGE then
		return
	end
	local final = part.CFrame
	local size = part.Size
	-- perchoir couché (Cylinder vertical) : la hauteur est l'axe X de la pièce
	local height = size.X
	part.Size = Vector3.new(0.05, size.Y, size.Z)
	part.CFrame = final - Vector3.new(0, height / 2, 0)
	Juice.tween(
		part,
		GROW_SECONDS,
		{ Size = size, CFrame = final },
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	for _, child in part:GetChildren() do
		if child:IsA("BasePart") then
			local childFinal = child.CFrame
			child.CFrame = childFinal - Vector3.new(0, height, 0)
			Juice.tween(
				child,
				GROW_SECONDS,
				{ CFrame = childFinal },
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
		end
	end
end

-- Panneau ------------------------------------------------------------------------------------------

local function panelLabel(name: string, order: number, height: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, height)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(30, 22, 50)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function buildPanel(slot: number): (BillboardGui, TextLabel, TextLabel, TextLabel, TextLabel)
	local anchor = anchorPart :: BasePart
	local attachment = Instance.new("Attachment")
	attachment.Name = string.format("Panel_%02d", slot)
	attachment.Position = WorldLayout.nestCenter(slot) + Vector3.new(0, Zones.Nests.BillboardY, 0)
	attachment.Parent = anchor
	local gui = Instance.new("BillboardGui")
	gui.Name = "NestPanel"
	gui.Size = UDim2.fromScale(PANEL_WIDTH, PANEL_HEIGHT)
	gui.MaxDistance = Zones.Nests.BillboardMaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Adornee = attachment
	local frame = Instance.new("Frame")
	frame.Name = "Content"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = frame
	local name = panelLabel("Owner", 1, 0.4, frame)
	-- badge doré « ★ VIP » sous le nom (pass VIP Star, GDD §8.2), masqué sinon
	local vip = panelLabel("Vip", 2, 0.18, frame)
	vip.TextColor3 = VIP_COLOR
	vip.Visible = false
	local rank = panelLabel("Rank", 3, 0.22, frame)
	local title = panelLabel("Title", 4, 0.2, frame)
	gui.Parent = attachment
	return gui, name, vip, rank, title
end

-- Le propriétaire du Nid a-t-il le pass VIP Star (attribut VIP de son Player) ?
local function ownerVip(state: NestState): boolean
	local owner = state.model:GetAttribute("OwnerUserId")
	if type(owner) ~= "number" or owner == 0 then
		return false
	end
	local player = Players:GetPlayerByUserId(owner)
	return player ~= nil and player:GetAttribute("VIP") == true
end

local function refreshVip(state: NestState)
	local vip = ownerVip(state)
	if state.vip ~= vip then
		state.vip = vip
		state.vipLabel.Visible = vip
	end
end

local function refreshPanel(state: NestState)
	local model = state.model
	local owner = model:GetAttribute("OwnerUserId")
	local free = type(owner) ~= "number" or owner == 0
	local color = model:GetAttribute("Color")
	local supernovas = model:GetAttribute("Supernovas")
	local title = model:GetAttribute("Title")
	state.vipLabel.Text = Prefs.t("nest.vip")
	refreshVip(state)
	if free then
		state.nameLabel.Text = Prefs.t("nest.free")
		state.nameLabel.TextColor3 = Cosmetics.FreeNestColor
		state.rankLabel.Text = ""
		state.titleLabel.Text = ""
		return
	end
	local ownerName = model:GetAttribute("OwnerName")
	state.nameLabel.Text = if type(ownerName) == "string" then ownerName else ""
	state.nameLabel.TextColor3 = if typeof(color) == "Color3" then color else Cosmetics.NestColors[state.slot]
	local r = if type(supernovas) == "number" then math.max(0, math.floor(supernovas)) else 0
	state.rankLabel.Text = if r > 0 then Prefs.t("nest.rank", { n = r }) else ""
	if type(title) == "string" and Cosmetics.Titles[title] then
		state.titleLabel.Text = Prefs.t("title." .. title)
	else
		state.titleLabel.Text = ""
	end
end

-- Constellation -------------------------------------------------------------------------------------

local function refreshStars(state: NestState)
	local raw = state.model:GetAttribute("Supernovas")
	local owner = state.model:GetAttribute("OwnerUserId")
	local r = if type(raw) == "number"
			and raw == raw
			and type(owner) == "number"
			and owner ~= 0
		then math.clamp(math.floor(raw), 0, MAX_STARS)
		else 0
	state.supernovas = r
	local stars = state.stars
	local folder = nestFolder :: Folder
	for i = #stars + 1, r do
		local star = Fx.part(
			string.format("Star_%02d_%02d", state.slot, i),
			"Ball",
			Vector3.one * STAR_SIZE,
			STAR_COLOR
		)
		star.CFrame = CFrame.new(WorldLayout.constellationPoint(state.slot, i))
		local attachment = Instance.new("Attachment")
		attachment.Name = "Link"
		attachment.Parent = star
		local prev = stars[i - 1]
		if prev then
			local beam = Instance.new("Beam")
			beam.Name = "Beam"
			beam.Attachment0 = prev:FindFirstChild("Link") :: Attachment
			beam.Attachment1 = attachment
			beam.Width0 = STAR_BEAM_WIDTH
			beam.Width1 = STAR_BEAM_WIDTH
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Color = ColorSequence.new(STAR_COLOR)
			beam.Transparency = NumberSequence.new(0.3)
			beam.Parent = star
		end
		star.Parent = folder
		stars[i] = star
	end
	for i = #stars, r + 1, -1 do
		stars[i]:Destroy()
		stars[i] = nil
	end
end

-- Nids : découverte et attributs ------------------------------------------------------------------------

local function onAttribute(state: NestState, name: string)
	if name == "PerchData" then
		refreshPerched(state)
	elseif name == "PerchCount" then
		local count = state.model:GetAttribute("PerchCount")
		state.perchCount = if type(count) == "number"
			then math.clamp(math.floor(count), 0, MAX_PERCHES)
			else 0
		table.clear(state.tops)
		for _, view in state.perched do
			view.top = perchTop(state, view.index)
		end
	elseif name == "Supernovas" or name == "OwnerUserId" then
		refreshStars(state)
		refreshPanel(state)
	elseif name == "OwnerName" or name == "Color" or name == "Title" then
		refreshPanel(state)
	end
end

local function untrackNest(slot: number)
	local state = nests[slot]
	if state == nil then
		return
	end
	nests[slot] = nil
	for _, c in state.conns do
		c:Disconnect()
	end
	for _, view in state.perched do
		releaseView(view)
	end
	for _, star in state.stars do
		star:Destroy()
	end
	local attachment = state.panel.Parent
	state.panel:Destroy()
	if attachment then
		attachment:Destroy()
	end
end

local function trackNest(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local slot = model:GetAttribute("Slot")
	if not validSlot(slot) then
		return
	end
	local s = slot :: number
	if nests[s] and nests[s].model == model then
		return
	end
	untrackNest(s)
	local panel, nameLabel, vipLabel, rankLabel, titleLabel = buildPanel(s)
	local count = model:GetAttribute("PerchCount")
	local state: NestState = {
		slot = s,
		model = model,
		perched = {},
		perchCount = if type(count) == "number" then math.clamp(math.floor(count), 0, MAX_PERCHES) else 0,
		supernovas = 0,
		panel = panel,
		nameLabel = nameLabel,
		vipLabel = vipLabel,
		rankLabel = rankLabel,
		titleLabel = titleLabel,
		vip = false,
		stars = {},
		conns = {},
		tops = {},
		floaterAt = {},
	}
	nests[s] = state
	table.insert(
		state.conns,
		model.AttributeChanged:Connect(function(name: string)
			if nests[s] == state then
				onAttribute(state, name)
			end
		end)
	)
	local function watchPerches(folder: Instance)
		table.insert(
			state.conns,
			folder.ChildAdded:Connect(function(child: Instance)
				table.clear(state.tops)
				for _, view in state.perched do
					view.top = perchTop(state, view.index)
				end
				-- seul le perchoir le plus récent pousse (pas ceux répliqués à l'arrivée)
				local index = child:GetAttribute("Index")
				if type(index) == "number" and index >= state.perchCount then
					growPerch(child, NestDisplay.focus)
				end
			end)
		)
	end
	local folder = model:FindFirstChild("Perches")
	if folder then
		watchPerches(folder)
	else
		local conn: RBXScriptConnection? = nil
		conn = model.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Perches" and nests[s] == state then
				if conn then
					conn:Disconnect()
				end
				table.clear(state.tops)
				watchPerches(child)
			end
		end)
		table.insert(state.conns, conn :: RBXScriptConnection)
	end
	table.insert(
		state.conns,
		model.AncestryChanged:Connect(function()
			if model.Parent == nil and nests[s] == state then
				untrackNest(s)
			end
		end)
	)
	refreshPanel(state)
	refreshStars(state)
	refreshPerched(state)
end

-- Liens d'équipage ---------------------------------------------------------------------------------------

local function isNight(): boolean
	local clock = Lighting.ClockTime
	return clock >= NIGHT_FROM or clock < NIGHT_UNTIL
end

local function linkPoint(slot: number): Vector3
	return WorldLayout.nestCenter(slot) + Vector3.new(0, CREW_LINK_HEIGHT, 0)
end

local function refreshLinks(now: number)
	local wanted: { [string]: { number } } = {}
	for _, crew in WorldStateController.crews().crews do
		local slots: { number } = {}
		for _, userId in crew.userIds do
			local slot = WorldStateController.slotOf(userId)
			if slot ~= 0 then
				table.insert(slots, slot)
			end
		end
		table.sort(slots)
		for i = 2, #slots do
			local a, b = slots[i - 1], slots[i]
			wanted[a .. ":" .. b] = { a, b }
		end
	end
	for key, link in links do
		if wanted[key] == nil then
			link.beam:Destroy()
			link.a:Destroy()
			link.b:Destroy()
			links[key] = nil
		end
	end
	local anchor = anchorPart :: BasePart
	for key, pair in wanted do
		if links[key] == nil then
			local from, to = linkPoint(pair[1]), linkPoint(pair[2])
			local a = Instance.new("Attachment")
			a.Name = "CrewA_" .. key
			a.Position = from
			a.Parent = anchor
			local b = Instance.new("Attachment")
			b.Name = "CrewB_" .. key
			b.Position = if Juice.reducedMotion() then to else from
			b.Parent = anchor
			local beam = Instance.new("Beam")
			beam.Name = "CrewLink_" .. key
			beam.Attachment0 = a
			beam.Attachment1 = b
			beam.Width0 = CREW_LINK_WIDTH
			beam.Width1 = CREW_LINK_WIDTH
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Segments = 16
			beam.CurveSize0 = 12
			beam.CurveSize1 = -12
			beam.Color = ColorSequence.new(Cosmetics.CrewBeam[1], Cosmetics.CrewBeam[2])
			beam.Transparency = NumberSequence.new(0.15)
			beam.Enabled = true -- tracé visible (§9.4), puis règle de la nuit (NestDisplay.step)
			beam.Parent = anchor
			links[key] = { key = key, a = a, b = b, beam = beam, from = from, to = to, start = now }
		end
	end
end

-- Stèle ------------------------------------------------------------------------------------------------

type BoardEntry = { userId: number, name: string, n: number }

local function parseBoard(raw: any, limit: number): { BoardEntry }
	local out: { BoardEntry } = {}
	if type(raw) ~= "string" or #raw > 4000 then
		return out
	end
	for item in string.gmatch(raw, "[^;]+") do
		local userId, name, n = string.match(item, "^(%d+):(.*):(%d+)$")
		local u, count = tonumber(userId), tonumber(n)
		if u and count and name then
			table.insert(out, { userId = u, name = name, n = count })
			if #out >= limit then
				break
			end
		end
	end
	return out
end

-- Lignes de la stèle réutilisées (LeaderboardService rafraîchit Live chaque seconde : aucune
-- création d'instances à chaque mise à jour)
local boardLabels: { TextLabel } = {}
local HEADER_COLOR = Color3.fromRGB(255, 220, 120)
local HEADER_FONT = Font.fromEnum(Enum.Font.FredokaOne)
local ENTRY_FONT = Font.fromEnum(Enum.Font.GothamBold)

local function boardLine(parent: Instance, order: number, text: string, header: boolean)
	local label = boardLabels[order]
	if label == nil or label.Parent ~= parent then
		local created = Instance.new("TextLabel")
		created.Name = "Line" .. order
		created.LayoutOrder = order
		created.BackgroundTransparency = 1
		created.TextScaled = true
		created.Parent = parent
		boardLabels[order] = created
		label = created
	end
	local l = label :: TextLabel
	l.Visible = true
	l.Size = UDim2.new(1, 0, 0, if header then 44 else 34)
	l.TextXAlignment = if header then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	l.FontFace = if header then HEADER_FONT else ENTRY_FONT
	l.TextColor3 = if header then HEADER_COLOR else Color3.new(1, 1, 1)
	l.Text = text
end

local function refreshBoard()
	local part = board
	local gui = boardGui
	if part == nil or gui == nil then
		return
	end
	local list = gui:FindFirstChild("List")
	if list == nil then
		return
	end
	local order = 0
	local function add(text: string, header: boolean)
		order += 1
		boardLine(list, order, text, header)
	end
	local function section(titleKey: string, entries: { BoardEntry })
		add(Prefs.t(titleKey), true)
		if #entries == 0 then
			add(Prefs.t("world.empty"), false)
		end
		for rank, e in entries do
			add(Prefs.t("board.entry", { rank = rank, name = e.name, n = e.n }), false)
		end
	end
	add(Prefs.t("board.title"), true)
	section("board.live", parseBoard(part:GetAttribute("Live"), BOARD_LIVE))
	section("board.record", parseBoard(part:GetAttribute("Record"), 1))
	section("board.weekly", parseBoard(part:GetAttribute("Weekly"), BOARD_WEEKLY))
	for i = order + 1, #boardLabels do
		boardLabels[i].Visible = false
	end
end

local function trackBoard(beacon: Instance)
	local part = beacon:FindFirstChild("Board")
	if part == nil then
		-- stèle pas encore répliquée : on l'attend sans bloquer
		local conn: RBXScriptConnection? = nil
		conn = beacon.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Board" then
				if conn then
					conn:Disconnect()
				end
				trackBoard(beacon)
			end
		end)
		return
	end
	if not part:IsA("BasePart") or part == board then
		return
	end
	if boardConn then
		boardConn:Disconnect()
	end
	if boardGui then
		boardGui:Destroy()
	end
	table.clear(boardLabels)
	board = part
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CongaBoard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BOARD_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 12)
	padding.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	gui.Parent = part
	boardGui = gui
	boardConn = part.AttributeChanged:Connect(refreshBoard)
	refreshBoard()
end

-- SpotLight du Nid local --------------------------------------------------------------------------------

local function refreshSpot(focus: Vector3?)
	local slot = WorldStateController.localSlot()
	local state = if slot ~= 0 then nests[slot] else nil
	local part = spot
	if part == nil then
		local p = Fx.part("NestSpot", "Block", Vector3.one * 0.2, SPOT_COLOR, Enum.Material.SmoothPlastic)
		p.Transparency = 1
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = SPOT_RANGE
		light.Angle = SPOT_ANGLE
		light.Brightness = 2
		light.Color = SPOT_COLOR
		light.Shadows = false
		light.Enabled = false
		light.Parent = p
		p.Parent = root
		spot = p
		spotLight = light
		part = p
	end
	local light = spotLight :: SpotLight
	if state == nil or state.perchCount < 1 or #state.perched < 1 then
		light.Enabled = false
		return
	end
	local top = perchTop(state, 1)
	local target = CFrame.new(top + Vector3.new(0, SPOT_HEIGHT, 0))
	if (part :: BasePart).CFrame ~= target then
		(part :: BasePart).CFrame = target
	end
	local enabled = true
	if
		RigPool.lowGraphics()
		and focus
		and (top - focus).Magnitude > Balance.Render.LowGraphicsLightDistance
	then
		enabled = false
	end
	light.Enabled = enabled
end

-- « +N » des perchés du Nid local -------------------------------------------------------------------------

local function idleMultiplier(): number
	local rate = State.get("idleRate")
	local income = State.get("perchIncome")
	if type(rate) == "number" and type(income) == "number" and income > 0 and rate > 0 then
		return rate / income
	end
	return 1
end

local function stepFloaters(now: number, focus: Vector3?)
	local slot = WorldStateController.localSlot()
	local state = if slot ~= 0 then nests[slot] else nil
	if state == nil or focus == nil then
		return
	end
	if (WorldLayout.nestCenter(slot) - focus).Magnitude > FLOATER_RANGE then
		return
	end
	local count = math.min(Balance.Render.PerchFloaters, #state.perched)
	local m = idleMultiplier()
	for k = 1, count do
		local at = state.floaterAt[k]
		if at == nil or at > now + FLOATER_PERIOD * 2 then
			state.floaterAt[k] = now + (k - 1) * FLOATER_PERIOD / count
		elseif now >= at then
			state.floaterAt[k] = now + FLOATER_PERIOD
			local view = state.perched[k]
			local s, f, v = Nebbies.unpack(view.code)
			local value = Formulas.passiveIncome({ s = s, f = f, v = v, st = view.stars })
				* m
				* FLOATER_PERIOD
			local size = NebbyBuilder.bodySize(view.code)
			FloatText.show(
				view.top + Vector3.new(0, size + 1, 0),
				Prefs.t("world.plus", { amount = Prefs.number(math.max(1, math.floor(value))) }),
				FLOATER_COLOR,
				FLOATER_SCALE
			)
		end
	end
end

-- API ----------------------------------------------------------------------------------------------------

-- Point de vue courant (posé par CongaRenderer à chaque image)
NestDisplay.focus = nil :: Vector3?

function NestDisplay.init(parent: Folder)
	root = parent
	nestFolder = Fx.folder(parent, "Nests")
	anchorPart = Fx.anchor("NestAnchor", nestFolder :: Folder)
end

function NestDisplay.start()
	if started then
		return
	end
	started = true
	for _, model in CollectionService:GetTagged("Nest") do
		trackNest(model)
	end
	CollectionService:GetInstanceAddedSignal("Nest"):Connect(trackNest)
	CollectionService:GetInstanceRemovedSignal("Nest"):Connect(function(model: Instance)
		for slot, state in nests do
			if state.model == model then
				untrackNest(slot)
			end
		end
	end)
	for _, beacon in CollectionService:GetTagged("Beacon") do
		trackBoard(beacon)
	end
	CollectionService:GetInstanceAddedSignal("Beacon"):Connect(trackBoard)
	WorldStateController.CrewsChanged:Connect(function()
		refreshLinks(Clock.now())
	end)
	WorldStateController.OwnerChanged:Connect(function()
		refreshLinks(Clock.now())
	end)
	Prefs.LanguageChanged:Connect(function()
		for _, state in nests do
			refreshPanel(state)
		end
		refreshBoard()
	end)
end

-- Perchés candidats au planificateur de niveaux de détail
function NestDisplay.views(out: { RigPool.View }, focus: Vector3)
	for _, state in nests do
		for _, view in state.perched do
			view.dist = (view.top - focus).Magnitude
			table.insert(out, view :: any)
		end
	end
end

-- Déplacement des perchés rendus (une fois par image, dans le BulkMoveTo de CongaRenderer) ;
-- `ensure` fournit le rig au LOD voulu (réserve et limite de reconstructions de CongaRenderer)
function NestDisplay.collect(
	t: number,
	parts: { BasePart },
	cframes: { CFrame },
	ensure: (RigPool.View) -> RigPool.Rig?
)
	for _, state in nests do
		for _, view in state.perched do
			local rig = ensure(view :: any)
			if rig ~= nil and rig.lod ~= "hidden" then
				local r = rig :: RigPool.Rig
				local size = r.size
				local bounce = math.sin(PERCH_BOUNCE_SPEED * t + view.phase) * PERCH_BOUNCE
				local pos = view.top + Vector3.new(0, size / 2 + bounce, 0)
				local cf = CFrame.lookAt(pos, pos + view.look)
				if r.lod == "full" then
					NebbyBuilder.animate(r, { t = t, phase = view.phase, blink = false, speed = 0 })
				end
				NebbyBuilder.appendCFrames(r, cf, parts, cframes)
			end
		end
	end
end

-- Minuteries lentes (10 Hz) : « +N », liens d'équipage, SpotLight
function NestDisplay.step(now: number, focus: Vector3?)
	stepFloaters(now, focus)
	refreshSpot(focus)
	local night = isNight()
	for _, link in links do
		local show = night or now - link.start < CREW_SHOW_SECONDS
		if link.beam.Enabled ~= show then
			link.beam.Enabled = show
		end
	end
	-- badge VIP : l'attribut du Player arrive au chargement de son profil (après OwnerUserId)
	for _, state in nests do
		refreshVip(state)
	end
end

-- Tracé des liens d'équipage (à chaque image, seulement pendant les 0,6 s de tracé)
function NestDisplay.animateLinks(now: number)
	for _, link in links do
		local a = (now - link.start) / CREW_DRAW_SECONDS
		if a < 1 then
			link.b.Position = link.from:Lerp(link.to, Fx.quadOut(a))
		elseif link.b.Position ~= link.to then
			link.b.Position = link.to
		end
	end
end

-- Dessus du perchoir `index` du Nid `slot` (nil si le Nid n'est pas connu du client)
function NestDisplay.perchTop(slot: number, index: number): Vector3?
	local state = nests[slot]
	if state == nil or not validSlot(slot) or index < 1 or index > MAX_PERCHES then
		return nil
	end
	return perchTop(state, index)
end

function NestDisplay.perchCount(slot: number): number
	local state = nests[slot]
	return if state then state.perchCount else 0
end

function NestDisplay.perchedCount(slot: number): number
	local state = nests[slot]
	return if state then #state.perched else 0
end

-- Rig rendu du perché `index` (nil s'il est masqué)
function NestDisplay.perchedRig(slot: number, index: number): RigPool.Rig?
	local state = nests[slot]
	local view = if state then state.perched[index] else nil
	return if view then view.rig else nil
end

function NestDisplay.constellationStar(slot: number, index: number): BasePart?
	local state = nests[slot]
	return if state then state.stars[index] else nil
end

-- Couleur du Nid (attribut Color, sinon palette)
function NestDisplay.nestColor(slot: number): Color3
	local state = nests[slot]
	local color = if state then state.model:GetAttribute("Color") else nil
	if typeof(color) == "Color3" then
		return color
	end
	return Cosmetics.NestColors[slot] or Cosmetics.FreeNestColor
end

-- Style de file du Nid (attribut LineStyle)
function NestDisplay.lineStyle(slot: number): string
	local state = nests[slot]
	local style = if state then state.model:GetAttribute("LineStyle") else nil
	if type(style) == "string" and Cosmetics.Styles[style] then
		return style
	end
	return "default"
end

-- Modèle du Nid (nil s'il n'est pas répliqué)
function NestDisplay.model(slot: number): Model?
	local state = nests[slot]
	return if state then state.model else nil
end

function NestDisplay.panel(slot: number): BillboardGui?
	local state = nests[slot]
	return if state then state.panel else nil
end

function NestDisplay.boardGui(): SurfaceGui?
	return boardGui
end

function NestDisplay.crewLinkCount(): number
	local n = 0
	for _ in links do
		n += 1
	end
	return n
end

return NestDisplay
