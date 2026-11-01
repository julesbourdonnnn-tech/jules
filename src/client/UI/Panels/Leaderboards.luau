--!strict
-- Leaderboards (paquet client-panels) : panneau Classements (GDD §6.9 ; docs/04 §13.6) : 5 onglets
-- (Plus de tampons, Meilleur combo, Meilleure capture, Plus serviable, Plus généreux). D'abord « Ma
-- place sur ce serveur » et « Mon record contre la semaine dernière » (« Record battu ! » en vert),
-- puis le top 10 mondial. Données : LeaderboardState (LeaderboardService, à PlayerReady puis toutes
-- les 120 s et à chaque record), revalidées (une charge abîmée affiche « Pas encore de scores »).
-- Nom vide (caché, inconnu) : alias « Squishy Fan #NNNN » (Hash.alias). Nombres par BigNumber.
-- UiSeen("leaderboards") à la première ouverture. Sélection par défaut : l'onglet en cours.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Hash = require(Shared.Logic.Hash)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local Net = require(Shared.Net)

local Client = script.Parent.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Widgets = require(script.Parent.Widgets)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }

local Leaderboards = {}

local TABS = { "stamps", "combo", "catchScore", "helpful", "generous" }
local TOP = 10

local nav: Nav? = nil
local tabBar: Widgets.TabBar? = nil
local current = TABS[1]
local isOpen = false
local payload: { [string]: any }? = nil
local labels: { [string]: TextLabel } = {}
local rowFrames: { Frame } = {}

-- Ligne de classement revalidée
local function row(r: any): { rank: number, userId: number, name: string, value: number }?
	if type(r) ~= "table" then
		return nil
	end
	local rank, userId, value = r.rank, r.userId, r.value
	if type(rank) ~= "number" or type(userId) ~= "number" or type(value) ~= "number" then
		return nil
	end
	if rank ~= rank or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	local name = if type(r.name) == "string" then Widgets.clip(r.name, 40) else ""
	return { rank = math.floor(rank), userId = userId, name = name, value = math.max(0, value) }
end

local function displayName(userId: number, name: string): string
	if name ~= "" then
		return name
	end
	local ok, n = pcall(Hash.alias, userId)
	return Prefs.t("name.alias", { n = if ok then n else 0 })
end

local function refresh()
	if tabBar == nil then
		return
	end
	local board: any = nil
	if payload and type(payload.boards) == "table" then
		board = payload.boards[current]
	end
	if type(board) ~= "table" then
		board = nil
	end
	local myRank = if board then Widgets.n(board.myServerRank) else 0
	if myRank > 0 then
		Widgets.setText(labels.place, "panel.lb.myPlace", { rank = math.floor(myRank) })
	else
		Widgets.setText(labels.place, "panel.lb.myPlace", { rank = "—" })
	end
	local mine = if board then math.max(0, Widgets.n(board.mine)) else 0
	local prev = if board then math.max(0, Widgets.n(board.minePrev)) else 0
	Widgets.setText(labels.record, "panel.lb.myRecord", { value = Widgets.num(mine) })
	Widgets.setText(labels.last, "panel.lb.lastWeek", { value = Widgets.num(prev) })
	labels.beaten.Visible = mine > prev and mine > 0
	Widgets.setText(labels.reset, "panel.lb.resetIn", { time = Prefs.duration(Clock.untilNextWeek()) })
	local list: { any } = {}
	if board and type(board.top) == "table" then
		for _, r in board.top do
			local clean = row(r)
			if clean then
				table.insert(list, clean)
			end
			if #list >= TOP then
				break
			end
		end
	end
	table.sort(list, function(a, b)
		return a.rank < b.rank
	end)
	labels.empty.Visible = #list == 0
	local me = Players.LocalPlayer
	for i, frame in rowFrames do
		local r = list[i]
		frame.Visible = r ~= nil
		if r then
			local isMe = me ~= nil and r.userId == me.UserId
			frame.BackgroundColor3 = if isMe then Widgets.Colors.CardLight else Widgets.Colors.Card
			Widgets.setRaw(frame:FindFirstChild("Rank") :: TextLabel, "#" .. tostring(r.rank))
			local nameLabel = frame:FindFirstChild("Name") :: TextLabel
			if isMe then
				Widgets.setText(nameLabel, "panel.lb.you")
			else
				Widgets.setRaw(nameLabel, displayName(r.userId, r.name))
			end
			Widgets.setRaw(frame:FindFirstChild("Value") :: TextLabel, Widgets.num(r.value))
		end
	end
end

function Leaderboards.start()
	pcall(function()
		Net.event("LeaderboardState").OnClientEvent:Connect(function(data: any)
			if type(data) == "table" and type(data.boards) == "table" then
				payload = data
				if isOpen then
					refresh()
				end
			end
		end)
	end)
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Leaderboards.build(container: Frame)
	local specs = {}
	for _, id in TABS do
		table.insert(specs, { id = id, key = "panel.lb.cat." .. id })
	end
	tabBar = Widgets.tabBar(container, specs, function(id: string)
		Leaderboards.setTab(id)
	end)
	local width = container.Size.X.Offset
	local summary = Widgets.frame({
		parent = container,
		name = "Summary",
		size = UDim2.fromOffset(width - 96, 112),
		position = UDim2.fromOffset(48, Layout.Panel.tabHeight + 24),
		color = Widgets.Colors.Card,
	})
	labels.place = Widgets.label({
		parent = summary,
		name = "Place",
		size = UDim2.new(0.5, -24, 0, 44),
		position = UDim2.fromOffset(24, 8),
		textSize = 36,
		xAlign = Enum.TextXAlignment.Left,
	})
	labels.record = Widgets.label({
		parent = summary,
		name = "Record",
		size = UDim2.new(0.5, -24, 0, 44),
		position = UDim2.new(0.5, 0, 0, 8),
		textSize = 36,
		xAlign = Enum.TextXAlignment.Left,
	})
	labels.last = Widgets.label({
		parent = summary,
		name = "LastWeek",
		size = UDim2.new(0.25, -24, 0, 36),
		position = UDim2.new(0.5, 0, 0, 62),
		textSize = 28,
		color = Widgets.Colors.TextDim,
		xAlign = Enum.TextXAlignment.Left,
	})
	labels.beaten = Widgets.label({
		parent = summary,
		name = "Beaten",
		size = UDim2.new(0.25, -24, 0, 36),
		position = UDim2.new(0.75, 0, 0, 62),
		key = "panel.lb.beaten",
		textSize = 28,
		color = Widgets.Colors.Success,
		xAlign = Enum.TextXAlignment.Left,
	})
	labels.reset = Widgets.label({
		parent = summary,
		name = "Reset",
		size = UDim2.new(0.5, -24, 0, 36),
		position = UDim2.fromOffset(24, 62),
		textSize = 28,
		color = Widgets.Colors.TextDim,
		xAlign = Enum.TextXAlignment.Left,
	})
	local listTop = Layout.Panel.tabHeight + 24 + 112 + 16
	Widgets.label({
		parent = container,
		name = "TopTitle",
		size = UDim2.fromOffset(width - 96, 44),
		position = UDim2.fromOffset(48, listTop),
		key = "panel.lb.top10",
		textSize = 36,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	labels.empty = Widgets.label({
		parent = container,
		name = "Empty",
		size = UDim2.fromOffset(width - 96, 48),
		position = UDim2.fromOffset(48, listTop + 60),
		key = "panel.lb.empty",
		textSize = 32,
		color = Widgets.Colors.TextDim,
	})
	-- top 10 en deux colonnes de 5 lignes
	local colW = math.floor((width - 96 - 24) / 2)
	local rowH = 64
	for i = 1, TOP do
		local col = if i <= 5 then 0 else 1
		local line = (i - 1) % 5
		local f = Widgets.frame({
			parent = container,
			name = "Row" .. i,
			size = UDim2.fromOffset(colW, rowH),
			position = UDim2.fromOffset(48 + col * (colW + 24), listTop + 56 + line * (rowH + 12)),
			color = Widgets.Colors.Card,
		})
		f.Visible = false
		Widgets.label({
			parent = f,
			name = "Rank",
			size = UDim2.fromOffset(72, rowH - 12),
			position = UDim2.fromOffset(12, 6),
			textSize = 32,
			color = Widgets.Colors.Gold,
		})
		Widgets.label({
			parent = f,
			name = "Name",
			size = UDim2.new(1, -260, 0, rowH - 12),
			position = UDim2.fromOffset(92, 6),
			textSize = 32,
			xAlign = Enum.TextXAlignment.Left,
		})
		Widgets.label({
			parent = f,
			name = "Value",
			size = UDim2.fromOffset(152, rowH - 12),
			position = UDim2.new(1, -12, 0, 6),
			anchor = Vector2.new(1, 0),
			textSize = 32,
			xAlign = Enum.TextXAlignment.Right,
		})
		rowFrames[i] = f
	end
	tabBar.setActive(current)
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Leaderboards.open(tab: string?)
	isOpen = true
	Widgets.seen("leaderboards")
	if type(tab) == "string" and table.find(TABS, tab) then
		current = tab
	end
	if tabBar then
		tabBar.setActive(current)
	end
	refresh()
end

-- Cache le panneau
function Leaderboards.close()
	isOpen = false
end

-- Onglets, dans l'ordre (L1 / R1)
function Leaderboards.tabs(): { string }
	return table.clone(TABS)
end

-- Change d'onglet
function Leaderboards.setTab(tab: string)
	if type(tab) ~= "string" or not table.find(TABS, tab) then
		return
	end
	current = tab
	if tabBar then
		tabBar.setActive(tab)
	end
	refresh()
end

function Leaderboards.currentTab(): string
	return current
end

-- Sélection par défaut : l'onglet en cours
function Leaderboards.defaultSelection(): GuiObject?
	return if tabBar then tabBar.buttons[current] else nil
end

-- ○ : retour au menu
function Leaderboards.onBack(): boolean
	return false
end

-- Entrée du menu visible pour ce joueur
function Leaderboards.visible(): boolean
	return true
end

-- Navigateur fourni par PanelController AVANT build
function Leaderboards.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function Leaderboards.refresh()
	refresh()
end

-- Dernier état reçu (specs)
function Leaderboards._payload(): { [string]: any }?
	local _ = nav
	return payload
end

return Leaderboards
