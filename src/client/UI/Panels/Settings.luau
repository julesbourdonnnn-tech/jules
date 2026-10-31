--!strict
-- Panels/Settings — paquet « client-panels » (docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * réglages GÉNÉRÉS depuis Config/Settings (ordre `order`) : interrupteurs 80 × 48 pour les
--     booléens (Mode Zen, Mouvement réduit, Graphismes légers, Musique, Effets sonores, Équipage
--     auto, Refuser les invitations), choix segmenté pour les chaînes (Langue : Auto / English /
--     Français) → SetSetting(key, value) ; Mode Zen seulement dans son port sûr (harborOnly) avec
--     la recharge (cooldown) affichée ; Coupes désactivées (ownerOnly) seulement pour le
--     propriétaire d'un serveur privé (état lu dans EventState.snipsDisabled)
--   * section Style : styles de file, titres, thèmes de Nid possédés (Config/Cosmetics, sources,
--     miroir de NestService.hasUnlock) → EquipCosmetic(kind, id) ; titre « Aucun » = ""
--   * section LiveOps visible seulement si l'attribut Player « Admin » est vrai → AdminCommand
--     (Events.LiveOps.Commands, « weather:<clé> » pour chaque météo activée)
--   * le changement est montré tout de suite (optimiste) puis aligné sur le profil répliqué ;
--     un refus serveur (hors du port sûr, recharge…) ramène l'affichage après 2,5 s
--   * recharge du Mode Zen comptée depuis le changement CONFIRMÉ (profil répliqué, comme
--     NestService) : un refus serveur ne bloque jamais 60 s ; un seul changement de Zen en attente
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged) ; intentions seulement
-- GDD : §4.16 (Zen), §5.3, §7.6, §9.1 (réglages), §10.3, §13.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Nebbies = require(Shared.Config.Nebbies)
local SettingsConfig = require(Shared.Config.Settings)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)
local Prefs = require(Client.Util.Prefs)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local WorldState = require(Client.Controllers.WorldStateController)
local Model = require(script.Parent.Model)
local Widgets = require(script.Parent.Widgets)

local Panel = {}

Panel.name = "Settings" :: Types.PanelName
Panel.tabs = nil :: { string }?

local ROW_HEIGHT = 80
local PENDING_TIMEOUT = 2.5
local REFRESH_INTERVAL = 0.5
local ADMIN_GUARD = 2

type SettingRow = {
	key: string,
	frame: Frame,
	name: TextLabel,
	desc: TextLabel,
	status: TextLabel?,
	toggle: TextButton?,
	choices: { [string]: TextButton }?,
}

type StyleRow = {
	kind: string,
	plural: string,
	frame: Frame,
	title: TextLabel,
	list: ScrollingFrame,
	signature: string?, -- nil = jamais construit
	chips: { [string]: TextButton },
}

local view = Model.view(State.get)
local built = false
local isOpen = false
local settingRows: { [string]: SettingRow } = {}
local styleRows: { StyleRow } = {}
local sectionLabels: { [string]: TextLabel } = {}
local liveOpsFrame: Frame? = nil
local liveOpsButtons: { [string]: TextButton } = {}
local pendingValues: { [string]: { value: any, at: number } } = {}
local pendingCosmetic: { [string]: { id: string, at: number } } = {}
local zenChangedAt = -math.huge -- Clock.now() du dernier changement de Zen confirmé
local adminSentAt = -math.huge
local refreshAcc = 0

-- ---------------------------------------------------------------------------------------------
-- Valeurs (profil répliqué + affichage optimiste)
-- ---------------------------------------------------------------------------------------------

local function isPrivateOwner(): boolean
	local player = Players.LocalPlayer
	local ok, owner = pcall(function()
		return (game :: any).PrivateServerOwnerId
	end)
	return ok and type(owner) == "number" and owner ~= 0 and player ~= nil and owner == player.UserId
end

local function actual(key: string): any
	if key == "privateNoSnip" then
		local events = WorldState.events()
		return events ~= nil and events.snipsDisabled == true
	end
	return Prefs.get(key)
end

local function displayed(key: string): any
	local value = actual(key)
	local p = pendingValues[key]
	if p then
		if value == p.value or Clock.now() - p.at > PENDING_TIMEOUT then
			pendingValues[key] = nil
		else
			return p.value
		end
	end
	return value
end

local function inOwnHarbor(): boolean
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local slot = player and player:GetAttribute("Slot")
	if not root or not root:IsA("BasePart") or type(slot) ~= "number" or slot < 1 then
		return false
	end
	return WorldLayout.inOwnHarbor(slot, root.Position)
end

-- Changement de Zen confirmé par le serveur (profil répliqué) : la recharge part de là. Le
-- premier instantané (old = nil) n'est pas un changement. Branché dès le chargement du module
-- (PanelController.Start le charge) pour connaître la recharge même si le panneau n'a jamais été
-- ouvert.
State.Changed:Connect(function(key: string, value: any, old: any)
	if key ~= "settings" or type(value) ~= "table" or type(old) ~= "table" then
		return
	end
	if (value.zen == true) ~= (old.zen == true) then
		zenChangedAt = Clock.now()
	end
end)

-- Un changement de ce réglage attend-il encore la confirmation du serveur ?
local function isPending(key: string): boolean
	local p = pendingValues[key]
	return p ~= nil and Clock.now() - p.at <= PENDING_TIMEOUT and actual(key) ~= p.value
end

-- Secondes avant de pouvoir rebasculer un réglage à recharge (0 = libre)
local function cooldownLeft(key: string): number
	local def = SettingsConfig[key]
	if not def or not def.cooldown or key ~= "zen" then
		return 0
	end
	return math.max(0, def.cooldown - (Clock.now() - zenChangedAt))
end

-- Raison d'un refus local (nil = le changement peut partir)
local function blockedReason(key: string): string?
	local def = SettingsConfig[key]
	if not def then
		return "invalid"
	end
	if def.harborOnly and not inOwnHarbor() then
		return "harbor"
	end
	if cooldownLeft(key) > 0 then
		return "cooldown"
	end
	if def.cooldown and isPending(key) then
		-- réglage à recharge : un seul changement en vol (le second serait refusé par le serveur)
		return "pending"
	end
	if def.ownerOnly and not isPrivateOwner() then
		return "owner"
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------------------------

local function renderSettings()
	for key, row in settingRows do
		local def = SettingsConfig[key]
		row.name.Text = Prefs.t("settings." .. key)
		row.desc.Text = Prefs.t("settings." .. key .. ".desc")
		if def.ownerOnly then
			row.frame.Visible = isPrivateOwner()
		end
		local value = displayed(key)
		local reason = blockedReason(key)
		if row.toggle then
			Widgets.setToggleEnabled(row.toggle, reason == nil)
			Widgets.setToggle(row.toggle, value == true, true)
		end
		if row.choices then
			for choice, button in row.choices do
				Widgets.setText(button, Prefs.t("settings." .. key .. "." .. choice))
				Widgets.setColor(button, if value == choice then Theme.Colors.Primary else Widgets.CARD)
				Widgets.highlight(button, value == choice, Theme.Colors.Gold)
			end
		end
		if row.status then
			if reason == "harbor" then
				row.status.Text = Prefs.t("settings.zenHarbor")
			elseif reason == "cooldown" then
				row.status.Text = Prefs.t("settings.cooldown", { seconds = math.ceil(cooldownLeft(key)) })
			else
				row.status.Text = ""
			end
		end
	end
end

local function equipped(field: string): string
	local cosmetics = view.cosmetics
	local value = if type(cosmetics) == "table" then cosmetics[field] else nil
	return if type(value) == "string" then value else ""
end

local function sendCosmetic(kind: string, id: string, button: TextButton)
	local p = pendingCosmetic[kind]
	if p and p.id == id and Clock.now() - p.at < PENDING_TIMEOUT then
		return
	end
	pendingCosmetic[kind] = { id = id, at = Clock.now() }
	Net.event("EquipCosmetic"):FireServer(kind, id)
	Widgets.highlight(button, true, Theme.Colors.Gold)
end

local function renderStyles()
	for _, row in styleRows do
		local info
		for _, k in Model.CosmeticKinds do
			if k.kind == row.kind then
				info = k
			end
		end
		if not info then
			continue
		end
		row.title.Text = Prefs.t("settings.style." .. (if row.kind == "style" then "line" else row.kind))
		local current = equipped(info.equipped)
		local p = pendingCosmetic[row.kind]
		if p then
			if p.id == current or Clock.now() - p.at > PENDING_TIMEOUT then
				pendingCosmetic[row.kind] = nil
			else
				current = p.id
			end
		end
		-- possédés (et l'équipé, même s'il vient d'un déblocage temporaire du serveur)
		local ids = {}
		if row.kind == "title" then
			table.insert(ids, "")
		end
		for _, id in Model.ordered(info.defs) do
			if Model.ownsCosmetic(view, info.plural, info.defs, id) or id == current then
				table.insert(ids, id)
			end
		end
		local signature = table.concat(ids, ",")
		if signature ~= row.signature then
			row.signature = signature
			for _, chip in row.chips do
				chip:Destroy()
			end
			row.chips = {}
			for i, id in ids do
				local chip: TextButton
				chip = Widgets.button({
					name = "Chip_" .. (if id == "" then "none" else id),
					size = UDim2.fromOffset(170, 52),
					color = Widgets.CARD,
					order = i,
					maxText = 18,
					parent = row.list,
					onClick = function()
						sendCosmetic(row.kind, id, chip)
						renderStyles()
					end,
				})
				row.chips[id] = chip
			end
		end
		for id, chip in row.chips do
			local text = if id == "" then Prefs.t("settings.style.none") else Prefs.t(row.kind .. "." .. id)
			Widgets.setText(chip, text)
			local on = id == current
			Widgets.setColor(chip, if on then Theme.Colors.Primary else Widgets.CARD)
			Widgets.highlight(chip, on, Theme.Colors.Gold)
		end
	end
end

local function isAdmin(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("Admin") == true
end

local function renderLiveOps()
	local frame = liveOpsFrame
	local header = sectionLabels.liveOps
	local admin = isAdmin()
	if frame then
		frame.Visible = admin
	end
	if header then
		header.Visible = admin
	end
	for command, button in liveOpsButtons do
		local weather = string.match(command, "^weather:(.+)$")
		local text = if weather
			then Prefs.t("settings.liveOps.weather", { weather = Prefs.t("weather." .. weather) })
			else Prefs.t("liveops." .. command)
		Widgets.setText(button, text)
	end
end

local function render()
	if not built then
		return
	end
	for key, label in sectionLabels do
		label.Text = Prefs.t("settings.section." .. key)
	end
	renderSettings()
	renderStyles()
	renderLiveOps()
end

-- ---------------------------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------------------------

function Panel.setSetting(key: string, value: any)
	local def = SettingsConfig[key]
	if not def or type(value) ~= def.kind then
		return
	end
	if def.values and not def.values[value] then
		return
	end
	local row = settingRows[key]
	local reason = blockedReason(key)
	if reason ~= nil then
		if row and row.toggle then
			Widgets.refuse(row.toggle)
		end
		renderSettings()
		return
	end
	if displayed(key) == value then
		return
	end
	pendingValues[key] = { value = value, at = Clock.now() }
	Net.event("SetSetting"):FireServer(key, value)
	renderSettings()
end

local function sendAdmin(command: string)
	if not isAdmin() then
		return
	end
	local now = Clock.now()
	if now - adminSentAt < ADMIN_GUARD then
		local button = liveOpsButtons[command]
		if button then
			Widgets.refuse(button)
		end
		return
	end
	adminSentAt = now
	Net.event("AdminCommand"):FireServer(command)
end

-- ---------------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------------

local function section(key: string, order: number, parent: Instance): TextLabel
	local label = Widgets.label({
		name = "Section_" .. key,
		size = UDim2.new(1, -12, 0, 40),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		font = Widgets.STAMP_FONT,
		maxSize = 30,
		order = order,
		parent = parent,
	})
	sectionLabels[key] = label
	return label
end

local function buildSettingRow(key: string, order: number, parent: Instance): SettingRow
	local def = SettingsConfig[key]
	local height = if def.harborOnly or def.cooldown then ROW_HEIGHT + 24 else ROW_HEIGHT
	local frame = Widgets.card({
		name = "Setting_" .. key,
		size = UDim2.new(1, -12, 0, height),
		order = order,
		parent = parent,
	})
	local controlWidth = if def.kind == "string" then 360 else 96
	local name = Widgets.label({
		name = "Name",
		size = UDim2.new(1, -(controlWidth + 24), 0, 34),
		position = UDim2.fromOffset(14, 6),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 24,
		parent = frame,
	})
	local desc = Widgets.label({
		name = "Desc",
		size = UDim2.new(1, -(controlWidth + 24), 0, 30),
		position = UDim2.fromOffset(14, 42),
		xAlign = Enum.TextXAlignment.Left,
		yAlign = Enum.TextYAlignment.Top,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 16,
		parent = frame,
	})
	local row: SettingRow = { key = key, frame = frame, name = name, desc = desc }
	if def.harborOnly or def.cooldown then
		row.status = Widgets.label({
			name = "Status",
			size = UDim2.new(1, -28, 0, 22),
			position = UDim2.new(0, 14, 1, -26),
			xAlign = Enum.TextXAlignment.Left,
			color = Theme.Colors.Warning,
			font = Theme.Fonts.Body,
			maxSize = 16,
			parent = frame,
		})
	end
	if def.kind == "boolean" then
		local toggle = Widgets.toggle("Toggle", frame, function(on: boolean)
			Panel.setSetting(key, on)
		end)
		toggle.AnchorPoint = Vector2.new(1, 0)
		toggle.Position = UDim2.new(1, -14, 0, 16)
		row.toggle = toggle
	else
		local holder = Create("Frame", {
			Name = "Choices",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 14),
			Size = UDim2.fromOffset(controlWidth, 52),
			Parent = frame,
		}, { Widgets.listLayout(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right) })
		local choices: { [string]: TextButton } = {}
		local values = Model.settingValues(key)
		for i, value in values do
			choices[value] = Widgets.button({
				name = "Choice_" .. value,
				size = UDim2.new(1 / #values, -6, 1, 0),
				color = Widgets.CARD,
				order = i,
				maxText = 18,
				parent = holder,
				onClick = function()
					Panel.setSetting(key, value)
				end,
			})
		end
		row.choices = choices
	end
	return row
end

local function buildStyleRow(
	info: { kind: string, plural: string },
	order: number,
	parent: Instance
): StyleRow
	local frame = Widgets.card({
		name = "Style_" .. info.kind,
		size = UDim2.new(1, -12, 0, 104),
		order = order,
		parent = parent,
	})
	local title = Widgets.label({
		name = "Title",
		size = UDim2.new(1, -24, 0, 30),
		position = UDim2.fromOffset(14, 6),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 22,
		parent = frame,
	})
	local list = Create("ScrollingFrame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 40),
		Size = UDim2.new(1, -20, 0, 60),
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		Selectable = false,
		Parent = frame,
	}, { Widgets.listLayout(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) }) :: ScrollingFrame
	return {
		kind = info.kind,
		plural = info.plural,
		frame = frame,
		title = title,
		list = list,
		signature = nil,
		chips = {},
	}
end

local function liveOpsCommands(): { string }
	local out = {}
	for _, command in { "comet", "frenzy", "goldenNight" } do
		if Events.LiveOps.Commands[command] then
			table.insert(out, command)
		end
	end
	if Events.LiveOps.Commands.weather then
		for _, kind in Events.Weather.Kinds do
			if Nebbies.isVersionEnabled(kind.version) then
				table.insert(out, "weather:" .. kind.key)
			end
		end
	end
	return out
end

function Panel.build(parent: Frame)
	if built then
		return
	end
	built = true
	local scroll = Create("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Selectable = false,
		Parent = parent,
	}, { Widgets.listLayout(Enum.FillDirection.Vertical, 8) })
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	section("game", nextOrder(), scroll)
	for _, key in Model.settingsOrder() do
		settingRows[key] = buildSettingRow(key, nextOrder(), scroll)
	end
	section("style", nextOrder(), scroll)
	for _, info in Model.CosmeticKinds do
		table.insert(styleRows, buildStyleRow(info, nextOrder(), scroll))
	end
	section("liveOps", nextOrder(), scroll)
	local ops = Create("Frame", {
		Name = "LiveOps",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Parent = scroll,
	}, {
		Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(200, 56),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	liveOpsFrame = ops
	for i, command in liveOpsCommands() do
		liveOpsButtons[command] = Widgets.button({
			name = "Op_" .. string.gsub(command, ":", "_"),
			size = UDim2.fromOffset(200, 56),
			color = Theme.Colors.Premium,
			order = i,
			maxText = 18,
			parent = ops,
			onClick = function()
				sendAdmin(command)
			end,
		})
	end

	State.Changed:Connect(function(key: string)
		if
			key == "settings"
			or key == "cosmetics"
			or key == "unlocks"
			or key == "passes"
			or key == "atlas"
			or key == "stats"
			or key == "supernovas"
		then
			render()
		end
	end)
	Prefs.LanguageChanged:Connect(render)
	WorldState.EventChanged:Connect(function()
		if isOpen then
			renderSettings()
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("Admin"):Connect(renderLiveOps)
	end
	render()
end

function Panel.onOpen(_args: any?)
	isOpen = true
	render()
end

function Panel.onClose()
	isOpen = false
end

function Panel.hasAction(): boolean
	return false
end

function Panel.step(dt: number)
	if not built then
		return
	end
	refreshAcc += dt
	if refreshAcc >= REFRESH_INTERVAL then
		refreshAcc = 0
		renderSettings() -- port sûr et recharge du Mode Zen, retour d'un refus serveur
		renderStyles()
	end
end

function Panel.defaultSelection(): GuiObject?
	local first = settingRows[Model.settingsOrder()[1]]
	return if first then first.toggle else nil
end

-- Exposé pour les tests
Panel._rows = settingRows
Panel._styleRows = styleRows
Panel._liveOps = liveOpsButtons
Panel._liveOpsFrame = function(): Frame?
	return liveOpsFrame
end
Panel._displayed = displayed

return Panel
