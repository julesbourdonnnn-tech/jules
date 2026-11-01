--!strict
-- Diagnostics (paquet client-panels) : panneau des administrateurs (GDD §12.11 ; docs/04 §11.2,
-- §13.6). visible() devient vrai à la réception du DiagnosticsSnapshot « bonjour » (tab = 0) que le
-- serveur n'envoie qu'aux administrateurs (Data/Admins reste sur le serveur) : l'entrée apparaît dans
-- les Réglages, jamais chez un autre joueur. Onglets :
--   * Ce serveur : version, heure UTC, durée de vie, joueurs, tick moyen / max, mémoire, délais, puis
--     les erreurs triées par nombre ; ✕ sur une ligne ouvre ses 3 exemples (texte, pile, contexte) ;
--   * Mon client : ErrorReporter.stats() (images par seconde, mémoire, ping, instances, connexions,
--     qualité) et ErrorReporter.entries() ;
--   * Aujourd'hui : totaux de tous les serveurs depuis 00:00 UTC ;
--   * Outils : AdminCommand (BOOP RUSH, MEGA, horloge ±10 min et remise à zéro — grisés « Studio
--     seulement » hors Studio —, erreurs de test serveur et client, mode photo, fête).
-- Texte de 32 px TV, heure et version en haut de chaque onglet : fait pour être photographié.
-- RequestDiagnostics (1 / 2 s) à l'ouverture d'un onglet et par « Actualiser ». Lecture seule : les
-- messages sont montrés tels qu'écrits par le moteur (déjà nettoyés par DiagRules). Sélection par
-- défaut : l'onglet en cours ; Outils : le 1er bouton actif ; ○ ferme les exemples, puis revient aux
-- Réglages (panneau d'origine).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Layout = require(Shared.Config.Layout)
local Clock = require(Shared.Util.Clock)
local Net = require(Shared.Net)

local Client = script.Parent.Parent.Parent
local ErrorReporter = require(Client.Controllers.ErrorReporter)
local Prefs = require(Client.Util.Prefs)
local Widgets = require(script.Parent.Widgets)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }
type Line = { key: string, text: string, count: number, players: number, last: number, kind: number }
type RowUi = { button: TextButton, text: TextLabel, count: TextLabel, line: Line? }

local Diagnostics = {}

local TABS = { "server", "client", "today", "tools" }
local TAB_NUMBER = { server = 1, client = 2, today = 3 }
local CLOCK_STEP = 600 -- s : horloge ±10 min (Studio seulement)
local TOOLS: { { id: string, command: string, arg: (() -> string)?, studio: boolean? } } = {
	{ id = "forceRush", command = "forceRush" },
	{ id = "forceMega", command = "forceMega" },
	{
		id = "clockPlus",
		command = "clock",
		studio = true,
		arg = function(): string
			return tostring(math.floor(Clock.getOffset() + CLOCK_STEP))
		end,
	},
	{
		id = "clockMinus",
		command = "clock",
		studio = true,
		arg = function(): string
			return tostring(math.floor(Clock.getOffset() - CLOCK_STEP))
		end,
	},
	{
		id = "clockReset",
		command = "clock",
		studio = true,
		arg = function(): string
			return "0"
		end,
	},
	{
		id = "testServer",
		command = "testError",
		arg = function(): string
			return "server"
		end,
	},
	{
		id = "testClient",
		command = "testError",
		arg = function(): string
			return "client"
		end,
	},
	{ id = "photo", command = "photo" },
	{ id = "party", command = "party" },
}

local nav: Nav? = nil
local hello = false
local isOpen = false
local current = "server"
local tabBar: Widgets.TabBar? = nil
local pages: { [string]: Frame } = {}
local snapshots: { [number]: { [string]: any } } = {}
local stampLabels: { TextLabel } = {}
local statLabels: { [string]: { TextLabel } } = {}
local lists: { [string]: Widgets.Rows } = {}
local listLines: { [string]: { Line } } = {}
local emptyLabels: { [string]: TextLabel } = {}
local refreshButtons: { [string]: TextButton } = {}
local toolButtons: { TextButton } = {}
local samplesFrame: Frame? = nil
local sampleLabels: { TextLabel } = {}
local samplesFor: TextButton? = nil

local function str(v: any, max: number): string
	return if type(v) == "string" then Widgets.clip(v, max) else ""
end

local function isStudio(): boolean
	local ok, studio = pcall(function()
		return RunService:IsStudio()
	end)
	return ok and studio == true
end

local function hhmm(unix: number): string
	local s = math.floor(unix) % 86400
	return string.format("%02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
end

-- Lignes revalidées d'une liste d'entrées (DiagEntry), triées par nombre
local function linesOf(entries: any): { Line }
	local out: { Line } = {}
	if type(entries) ~= "table" then
		return out
	end
	for _, e in entries do
		if type(e) == "table" and type(e.key) == "string" then
			table.insert(out, {
				key = str(e.key, 16),
				text = str(e.text, 300),
				count = math.max(0, math.floor(Widgets.n(e.count))),
				players = math.max(0, math.floor(Widgets.n(e.players))),
				last = Widgets.n(e.last),
				kind = Widgets.n(e.kind, 1),
			})
		end
		if #out >= 200 then
			break
		end
	end
	table.sort(out, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.key < b.key
	end)
	return out
end

local function setStats(tab: string, lines: { string })
	local labels = statLabels[tab]
	if labels == nil then
		return
	end
	for i, label in labels do
		Widgets.setRaw(label, lines[i] or "")
	end
end

local function refreshStamp()
	local snap = snapshots[1]
	local server = if snap and type(snap.server) == "table" then snap.server else {}
	local version = Widgets.n((server :: any).placeVersion, game.PlaceVersion)
	local text = Prefs.t("panel.diag.version", { v = math.floor(version) })
		.. "  ·  "
		.. Prefs.t("panel.diag.utc", { time = hhmm(Clock.unix()) })
	for _, label in stampLabels do
		Widgets.setRaw(label, text)
	end
end

local function fillList(tab: string, lines: { Line })
	listLines[tab] = lines
	local rows = lists[tab]
	if rows then
		rows.setCount(#lines)
	end
	local empty = emptyLabels[tab]
	if empty then
		empty.Visible = #lines == 0
	end
end

local function refresh()
	refreshStamp()
	local snap = snapshots[1]
	local server: any = if snap and type(snap.server) == "table" then snap.server else {}
	setStats("server", {
		Prefs.t("panel.diag.uptime", { time = Prefs.duration(Widgets.n(server.uptime)) }),
		Prefs.t("panel.diag.players", { n = math.floor(Widgets.n(server.players)) }),
		Prefs.t("panel.diag.tick", {
			avg = string.format("%.1f", Widgets.n(server.tickAvgMs)),
			max = string.format("%.1f", Widgets.n(server.tickMaxMs)),
		}),
		Prefs.t("panel.diag.memory", { mb = math.floor(Widgets.n(server.memoryMb)) }),
		Prefs.t("panel.diag.timedOut", { n = math.floor(Widgets.n(server.timedOut)) }),
	})
	fillList("server", linesOf(if snap then snap.entries else nil))
	-- Mon client : mesures d'ErrorReporter (repli : zéros), erreurs de ce client
	local stats: any = Widgets.safe("ErrorReporter.stats", {}, ErrorReporter.stats)
	if type(stats) ~= "table" then
		stats = {}
	end
	setStats("client", {
		Prefs.t("panel.diag.fps", { fps = math.floor(Widgets.n(stats.fps)) }),
		Prefs.t("panel.diag.memory", { mb = math.floor(Widgets.n(stats.memoryMb)) }),
		Prefs.t("panel.diag.ping", { ms = math.floor(Widgets.n(stats.pingMs)) }),
		Prefs.t("panel.diag.instances", { n = math.floor(Widgets.n(stats.instances)) }),
		Prefs.t("panel.diag.connections", { n = math.floor(Widgets.n(stats.connections)) }),
		Prefs.t("panel.diag.quality", {
			q = Prefs.t(
				if stats.reduced == true then "panel.diag.quality.reduced" else "panel.diag.quality.normal"
			),
		}),
	})
	fillList("client", linesOf(Widgets.safe("ErrorReporter.entries", {}, ErrorReporter.entries)))
	local today = snapshots[3]
	fillList("today", linesOf(if today then today.today else nil))
	local studio = isStudio()
	for i, b in toolButtons do
		local tool = TOOLS[i]
		local disabled = tool.studio == true and not studio
		Widgets.setDisabled(b, disabled)
		local label = Widgets.buttonLabel(b) :: TextLabel
		if disabled then
			Widgets.setText(label, "panel.diag.tools.studioOnly")
		else
			Widgets.setText(label, "panel.diag.tools." .. tool.id)
		end
	end
end

local function request(tab: string)
	local n = TAB_NUMBER[tab]
	if n then
		Widgets.send("RequestDiagnostics", n)
	end
end

local function showPage(tab: string)
	for id, page in pages do
		page.Visible = id == tab
	end
	if tabBar then
		tabBar.setActive(tab)
	end
end

local function closeSamples()
	local f = samplesFrame
	if f then
		f.Visible = false
	end
	samplesFor = nil
	local page = pages[current]
	if page then
		page.Visible = true
	end
end

-- ✕ sur une ligne : ses 3 exemples (Ce serveur : samples du dernier instantané)
local function openSamples(button: TextButton, line: Line)
	local f = samplesFrame
	if f == nil then
		return
	end
	local samples: { any } = {}
	local snap = snapshots[TAB_NUMBER[current] or 1]
	if snap and type(snap.samples) == "table" then
		for _, s in snap.samples do
			if type(s) == "table" and s.key == line.key then
				table.insert(samples, s)
			end
			if #samples >= 3 then
				break
			end
		end
	end
	for i, label in sampleLabels do
		local s = samples[i]
		if s then
			Widgets.setRaw(label, str(s.text, 300) .. "\n" .. str(s.trace, 300) .. "\n" .. str(s.ctx, 120))
		elseif i == 1 then
			Widgets.setRaw(label, line.text)
		else
			Widgets.setRaw(label, "")
		end
	end
	-- la page passe sous les exemples : cachée, rien n'y reste sélectionnable
	local page = pages[current]
	if page then
		page.Visible = false
	end
	f.Visible = true
	samplesFor = button
	local first = f:FindFirstChild("Sample1")
	if first and first:IsA("GuiObject") then
		GuiService.SelectedObject = first
	end
end

local function buildList(page: Frame, tab: string, top: number)
	local width = page.Size.X.Offset - 96
	local height = page.Size.Y.Offset - top - 16
	emptyLabels[tab] = Widgets.label({
		parent = page,
		name = "Empty",
		size = UDim2.fromOffset(width, 48),
		position = UDim2.fromOffset(48, top + 8),
		key = "panel.diag.none",
		textSize = 32,
		color = Widgets.Colors.Success,
	})
	lists[tab] = Widgets.rows({
		parent = page,
		name = "List",
		size = Vector2.new(width, height),
		position = UDim2.fromOffset(48, top),
		rowHeight = 80,
		gap = 12,
		makeRow = function(frame: Frame, _slot: number): RowUi
			local ui: RowUi
			local b = Widgets.button({
				parent = frame,
				name = "Line",
				size = UDim2.fromScale(1, 1),
				color = Widgets.Colors.Card,
				nav = true,
				onActivate = function()
					if ui.line then
						openSamples(ui.button, ui.line)
					end
				end,
			})
			local text = Widgets.label({
				parent = b,
				name = "Text",
				size = UDim2.new(1, -200, 1, -12),
				position = UDim2.fromOffset(16, 6),
				textSize = 32,
				xAlign = Enum.TextXAlignment.Left,
				zIndex = b.ZIndex + 1,
			})
			local count = Widgets.label({
				parent = b,
				name = "Count",
				size = UDim2.fromOffset(168, 52),
				position = UDim2.new(1, -16, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				textSize = 32,
				color = Widgets.Colors.Warning,
				xAlign = Enum.TextXAlignment.Right,
				zIndex = b.ZIndex + 1,
			})
			ui = { button = b, text = text, count = count, line = nil }
			return ui
		end,
		bindRow = function(ui: RowUi, _frame: Frame, index: number)
			local line = (listLines[tab] or {})[index]
			ui.line = line
			if line then
				Widgets.setRaw(ui.text, line.key .. "  " .. line.text)
				Widgets.setRaw(ui.count, Prefs.t("panel.diag.count", { n = line.count }))
				ui.count.TextColor3 = if line.kind == 1 then Widgets.Colors.Danger else Widgets.Colors.Warning
			end
		end,
		selectables = function(ui: RowUi): { GuiObject }
			return { ui.button }
		end,
	})
end

local function buildPage(container: Frame, tab: string, top: number): Frame
	local page = Widgets.group(
		container,
		"Page_" .. tab,
		UDim2.fromOffset(container.Size.X.Offset, container.Size.Y.Offset - top),
		UDim2.fromOffset(0, top)
	)
	page.Visible = false
	pages[tab] = page
	local stamp = Widgets.label({
		parent = page,
		name = "Stamp",
		size = UDim2.fromOffset(page.Size.X.Offset - 96 - 260, 44),
		position = UDim2.fromOffset(48, 4),
		textSize = 32,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	table.insert(stampLabels, stamp)
	return page
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Diagnostics.build(container: Frame)
	local specs = {}
	for _, id in TABS do
		table.insert(specs, { id = id, key = "panel.diag.tab." .. id })
	end
	tabBar = Widgets.tabBar(container, specs, function(id: string)
		Diagnostics.setTab(id)
	end)
	local top = Layout.Panel.tabHeight + 20
	for _, tab in { "server", "client", "today" } do
		local page = buildPage(container, tab, top)
		refreshButtons[tab] = Widgets.button({
			parent = page,
			name = "Refresh",
			size = UDim2.fromOffset(240, Layout.Button.MinHeight),
			position = UDim2.new(1, -48, 0, 0),
			anchor = Vector2.new(1, 0),
			key = "panel.diag.refresh",
			textSize = 32,
			onActivate = function()
				request(tab)
			end,
		})
		local statCount = if tab == "server" then 5 elseif tab == "client" then 6 else 0
		local labels: { TextLabel } = {}
		local colW = math.floor((page.Size.X.Offset - 96) / 3)
		for i = 1, statCount do
			local col = (i - 1) % 3
			local line = (i - 1) // 3
			labels[i] = Widgets.label({
				parent = page,
				name = "Stat" .. i,
				size = UDim2.fromOffset(colW - 16, 40),
				position = UDim2.fromOffset(48 + col * colW, 92 + line * 44),
				textSize = 32,
				xAlign = Enum.TextXAlignment.Left,
			})
		end
		statLabels[tab] = labels
		local listTop = if statCount > 0 then 92 + 2 * 44 + 8 else 92
		buildList(page, tab, listTop)
	end
	-- Outils (administrateurs : chaque commande est revérifiée par le serveur)
	local tools = buildPage(container, "tools", top)
	local cols = 3
	local bw = math.floor((tools.Size.X.Offset - 96 - (cols - 1) * Layout.Spacing.Normal) / cols)
	for i, tool in TOOLS do
		local col = (i - 1) % cols
		local line = (i - 1) // cols
		toolButtons[i] = Widgets.button({
			parent = tools,
			name = "Tool_" .. tool.id,
			size = UDim2.fromOffset(bw, Layout.Button.MainHeight),
			position = UDim2.fromOffset(
				48 + col * (bw + Layout.Spacing.Normal),
				72 + line * (Layout.Button.MainHeight + Layout.Spacing.Normal)
			),
			key = "panel.diag.tools." .. tool.id,
			textSize = 36,
			onActivate = function()
				local arg = if tool.arg then tool.arg() else ""
				Widgets.send("AdminCommand", tool.command, arg)
			end,
		})
	end
	-- exemples d'une ligne (sous-niveau : ○ le ferme)
	local f = Widgets.frame({
		parent = container,
		name = "Samples",
		size = UDim2.fromOffset(container.Size.X.Offset - 96, container.Size.Y.Offset - top - 16),
		position = UDim2.fromOffset(48, top),
		color = Widgets.Colors.Panel,
		zIndex = 20,
	})
	f.Visible = false
	Widgets.label({
		parent = f,
		name = "Title",
		size = UDim2.new(1, -32, 0, 48),
		position = UDim2.fromOffset(16, 8),
		key = "panel.diag.samples",
		textSize = 40,
		zIndex = 21,
	})
	local sampleH = math.floor((f.Size.Y.Offset - 72 - 3 * 16) / 3)
	for i = 1, 3 do
		local holder = Widgets.button({
			parent = f,
			name = "Sample" .. i,
			size = UDim2.new(1, -32, 0, sampleH),
			position = UDim2.fromOffset(16, 64 + (i - 1) * (sampleH + 16)),
			color = Widgets.Colors.Card,
			sound = "",
		})
		holder.ZIndex = 21
		sampleLabels[i] = Widgets.label({
			parent = holder,
			name = "Text",
			size = UDim2.new(1, -24, 1, -12),
			position = UDim2.fromOffset(12, 6),
			textSize = 28,
			wrapped = true,
			xAlign = Enum.TextXAlignment.Left,
			yAlign = Enum.TextYAlignment.Top,
			zIndex = 22,
		})
	end
	samplesFrame = f
	showPage(current)
end

function Diagnostics.start()
	pcall(function()
		Net.event("DiagnosticsSnapshot").OnClientEvent:Connect(function(snap: any)
			if type(snap) ~= "table" or type(snap.tab) ~= "number" then
				return
			end
			local tab = math.floor(snap.tab)
			if tab == 0 then
				hello = true -- « bonjour » : ce joueur est administrateur (vérifié par le serveur)
				return
			end
			if tab >= 1 and tab <= 3 then
				hello = true
				snapshots[tab] = snap
				if isOpen then
					refresh()
				end
			end
		end)
	end)
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Diagnostics.open(tab: string?)
	isOpen = true
	if type(tab) == "string" and table.find(TABS, tab) then
		current = tab
	end
	closeSamples()
	showPage(current)
	request(current)
	refresh()
end

-- Cache le panneau
function Diagnostics.close()
	isOpen = false
	closeSamples()
end

-- Onglets, dans l'ordre (L1 / R1)
function Diagnostics.tabs(): { string }
	return table.clone(TABS)
end

-- Change d'onglet
function Diagnostics.setTab(tab: string)
	if type(tab) ~= "string" or not table.find(TABS, tab) then
		return
	end
	current = tab
	closeSamples()
	showPage(tab)
	request(tab)
	refresh()
end

function Diagnostics.currentTab(): string
	return current
end

-- Sélection par défaut : l'onglet en cours ; Outils : le 1er bouton actif
function Diagnostics.defaultSelection(): GuiObject?
	if samplesFrame and samplesFrame.Visible then
		return samplesFrame:FindFirstChild("Sample1") :: GuiObject?
	end
	if current == "tools" then
		for _, b in toolButtons do
			if not Widgets.isDisabled(b) then
				return b
			end
		end
	end
	return if tabBar then tabBar.buttons[current] else nil
end

-- ○ : ferme les exemples (vrai), sinon revient aux Réglages (faux)
function Diagnostics.onBack(): boolean
	if samplesFrame and samplesFrame.Visible then
		local back = samplesFor
		closeSamples()
		if back and back.Parent then
			GuiService.SelectedObject = back
		end
		return true
	end
	return false
end

-- Entrée visible pour ce joueur : seulement après le « bonjour » des administrateurs
function Diagnostics.visible(): boolean
	return hello
end

-- Navigateur fourni par PanelController AVANT build
function Diagnostics.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function Diagnostics.refresh()
	refresh()
end

-- Exemples affichés (specs)
function Diagnostics._samplesOpen(): boolean
	local _ = nav
	return samplesFrame ~= nil and samplesFrame.Visible
end

return Diagnostics
