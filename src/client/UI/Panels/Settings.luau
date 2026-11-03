--!strict
-- Settings (paquet client-panels) : panneau Réglages (GDD §10.3, §7.1 ; docs/04 §13.6) : mode Rush /
-- Cozy (SetMode), Cacher mon nom, Recevoir les cadeaux, Clips (caché si l'attribut local
-- ClipsUnavailable est posé par VFXController : appareil sans capture), Mouvement réduit,
-- Graphismes légers, Musique, Effets sonores, Vibrations, Emote de la croix ← (seulement les
-- emotes débloquées), Langue (Auto / English / Français) ; « BOOP RUSH autorisé » pour le
-- propriétaire d'un serveur privé ; Diagnostics pour les administrateurs (visible après le
-- « bonjour » du serveur, Panels/Diagnostics) ; message « Tes squishies grandissent même quand tu
-- dors » en bas. Interrupteurs de 120 × 64 px TV ; ✕ envoie SetSetting / SetMode (le serveur valide
-- et le profil répliqué fait foi : l'interrupteur suit le DataPatch). Aucun onglet.
-- Sélection par défaut : le 1er interrupteur ; ○ → menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local SettingsConfig = require(Shared.Config.Settings)
local Cosmetics = require(Shared.Config.Cosmetics)
local Layout = require(Shared.Config.Layout)

local Client = script.Parent.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Widgets = require(script.Parent.Widgets)
local Diagnostics = require(script.Parent.Diagnostics)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }
type Item = { kind: "mode" | "toggle" | "choice", key: string, values: { string }? }
type Row = {
	title: TextLabel,
	desc: TextLabel,
	toggle: Widgets.Toggle,
	choice: TextButton,
	item: Item?,
}

local Settings = {}

local ROW_H = 96
local ROW_GAP = 16
local LIST_TOP = 16
local NOTE_H = 56
-- px : haut de la vue de la liste 12 px sous la fin d'une rangée (dans l'écart de 16 px), et
-- hauteur de la liste = rangées entières + 12 (Widgets.rows snapOffset) : rien de tranché
local SNAP = 12

local nav: Nav? = nil
local rows: Widgets.Rows? = nil
local items: { Item } = {}
local diagButton: TextButton? = nil -- administrateurs : bouton fixe sous la liste (toujours atteignable)
local isOpen = false
local allowRushLocal = false -- réglage de serveur en mémoire (jamais dans le profil)

-- Réglages booléens affichés, dans l'ordre du GDD (le mode est à part)
local TOGGLES =
	{ "hideName", "receiveGifts", "clips", "reducedMotion", "lowGraphics", "music", "sfx", "vibration" }

local function clipsUnavailable(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("ClipsUnavailable") == true
end

-- Propriétaire d'un serveur privé (le serveur revalide : allowRush ownerOnly)
local function privateOwner(): boolean
	local player = Players.LocalPlayer
	local ok, owner = pcall(function()
		return game.PrivateServerOwnerId
	end)
	return player ~= nil and ok and type(owner) == "number" and owner ~= 0 and owner == player.UserId
end

-- Emotes de la croix ← débloquées (source free, plopDay, dex : jalon réclamé)
local function emoteUnlocked(id: string): boolean
	local def = Cosmetics.ByKindId["emote:" .. id]
	if def == nil then
		return false
	end
	local source = def.source
	if source.kind == "free" then
		return true
	elseif source.kind == "plopDay" then
		return Widgets.n(Widgets.state("plopDays")) >= (source.value or math.huge)
	elseif source.kind == "dex" then
		return Widgets.n(Widgets.tbl(Widgets.state("dex")).rewards) >= (source.value or math.huge)
	end
	return false
end

local function buildItems(): { Item }
	local list: { Item } = { { kind = "mode", key = "mode" } }
	for _, key in TOGGLES do
		if SettingsConfig[key] and not (key == "clips" and clipsUnavailable()) then
			table.insert(list, { kind = "toggle", key = key })
		end
	end
	local emotes: { string } = {}
	for _, id in { "bravo", "bellyFlop", "crown" } do
		if emoteUnlocked(id) then
			table.insert(emotes, id)
		end
	end
	table.insert(list, { kind = "choice", key = "emoteLeft", values = emotes })
	table.insert(list, { kind = "choice", key = "lang", values = { "auto", "en", "fr" } })
	if privateOwner() then
		table.insert(list, { kind = "toggle", key = "allowRush" })
	end
	return list
end

local function settingValue(key: string): any
	if key == "allowRush" then
		return allowRushLocal
	end
	return Prefs.get(key)
end

local function choiceText(item: Item): string
	if item.key == "lang" then
		local v = Prefs.get("lang")
		return Prefs.t("settings.lang." .. (if v == "en" or v == "fr" then v else "auto"))
	elseif item.key == "emoteLeft" then
		local v = Prefs.get("emoteLeft")
		return Prefs.t(
			"settings.emoteLeft." .. (if type(v) == "string" and emoteUnlocked(v) then v else "bravo")
		)
	elseif item.key == "mode" then
		local mode = Widgets.tbl(Widgets.state("mode"))
		return Prefs.t(if mode.rush == true then "settings.mode.rush" else "settings.mode.cozy")
	end
	return ""
end

-- Le profil répliqué fait foi : un réglage refusé par le serveur (débit, valeur) ne change rien au
-- profil, donc aucun DataPatch ; l'écran se recale tout seul peu après chaque envoi
local refresh: () -> () -- défini plus bas (lignes reliées après le profil)

local function resyncSoon()
	task.delay(1.5, function()
		if isOpen then
			refresh()
		end
	end)
end

local function activateChoice(item: Item)
	if item.kind == "mode" then
		local mode = Widgets.tbl(Widgets.state("mode"))
		Widgets.send("SetMode", not (mode.rush == true))
		resyncSoon()
	elseif item.kind == "choice" then
		local values = item.values or {}
		if #values < 2 then
			Widgets.refuse(nil)
			return
		end
		local current = Prefs.get(item.key)
		local i = table.find(values, current) or 0
		local nextValue = values[(i % #values) + 1]
		Widgets.send("SetSetting", item.key, nextValue)
		resyncSoon()
	end
end

local function bindRow(row: Row, _frame: Frame, index: number)
	local item = items[index]
	row.item = item
	if item == nil then
		return
	end
	Widgets.setText(row.title, "settings." .. item.key)
	Widgets.setText(row.desc, "settings." .. item.key .. ".desc")
	local isToggle = item.kind == "toggle"
	row.toggle.button.Visible = isToggle
	row.choice.Visible = not isToggle
	if isToggle then
		row.toggle.set(settingValue(item.key) == true)
	else
		local label = Widgets.buttonLabel(row.choice)
		if label then
			Widgets.setRaw(label, choiceText(item))
		end
		local values = item.values
		Widgets.setDisabled(row.choice, item.kind == "choice" and values ~= nil and #values < 2)
	end
end

local function makeRow(frame: Frame, _slot: number): Row
	local bg = Widgets.frame({
		parent = frame,
		name = "Back",
		color = Widgets.Colors.Card,
		transparency = 0.3,
		stroke = false,
		corner = Widgets.CORNER,
	})
	bg.ZIndex = 1
	local row: Row
	local title = Widgets.label({
		parent = frame,
		name = "Title",
		size = UDim2.new(1, -420, 0, 48),
		position = UDim2.fromOffset(24, 4),
		textSize = 36,
		xAlign = Enum.TextXAlignment.Left,
	})
	local desc = Widgets.label({
		parent = frame,
		name = "Desc",
		size = UDim2.new(1, -420, 0, 36),
		position = UDim2.fromOffset(24, 54),
		textSize = 28,
		color = Widgets.Colors.TextDim,
		xAlign = Enum.TextXAlignment.Left,
	})
	local toggle = Widgets.toggle(
		frame,
		"Toggle",
		UDim2.new(1, -24, 0.5, 0),
		Vector2.new(1, 0.5),
		function(value: boolean)
			local item = row.item
			if item == nil then
				return
			end
			if not Widgets.send("SetSetting", item.key, value) then
				-- retenu par le débit du client (interrupteur martelé) : rien n'est parti, donc aucun
				-- DataPatch ne viendra le recaler ; il revient tout de suite, avec le refus
				row.toggle.set(not value)
				Widgets.refuse(row.toggle.button)
				return
			end
			if item.key == "allowRush" then
				allowRushLocal = value
			end
			-- refusé par le serveur (valeur, recharge) : aucun DataPatch, l'écran se recale peu après
			resyncSoon()
		end
	)
	local choice = Widgets.button({
		parent = frame,
		name = "Choice",
		size = UDim2.fromOffset(320, Layout.Button.MinHeight),
		position = UDim2.new(1, -24, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		text = "",
		textSize = 36,
		color = Widgets.Colors.CardLight,
		onActivate = function()
			local item = row.item
			if item then
				activateChoice(item)
			end
		end,
	})
	row = { title = title, desc = desc, toggle = toggle, choice = choice, item = nil }
	return row
end

refresh = function()
	local list = rows
	if list == nil then
		return
	end
	items = buildItems()
	list.setCount(#items)
	list.refresh()
	local diag = diagButton
	if diag then
		diag.Visible = Widgets.safe("Diagnostics.visible", false, Diagnostics.visible) == true
	end
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Settings.build(container: Frame)
	local width = container.Size.X.Offset - 96
	-- hauteur = k rangées entières + SNAP : avec la marge de 24 px de Widgets.rows en haut et en bas
	-- et le défilement calé sur les écarts (snapOffset), chaque bord de la liste tombe dans un écart
	-- entre deux rangées, au départ, en descendant et en bout de liste. Avant : 660 px,
	-- la 6e rangée entrouverte avait sa description tranchée à mi-hauteur (et son titre en fin de
	-- liste) : du texte coupé, le défaut le plus visible pour le joueur (revue de l'outil d'écrans)
	local available = container.Size.Y.Offset - LIST_TOP - NOTE_H - 32
	local stride = ROW_H + ROW_GAP
	local height = math.max(stride, math.floor((available - SNAP) / stride) * stride + SNAP)
	rows = Widgets.rows({
		parent = container,
		name = "List",
		size = Vector2.new(width, height),
		position = UDim2.fromOffset(48, LIST_TOP),
		rowHeight = ROW_H,
		gap = ROW_GAP,
		snapOffset = SNAP,
		makeRow = makeRow,
		bindRow = bindRow,
		selectables = function(row: Row): { GuiObject }
			return { row.toggle.button, row.choice }
		end,
	})
	diagButton = Widgets.button({
		parent = container,
		name = "Diagnostics",
		size = UDim2.fromOffset(340, NOTE_H + 16),
		position = UDim2.new(1, -48, 1, -12),
		anchor = Vector2.new(1, 1),
		key = "settings.diagnostics",
		textSize = 36,
		color = Widgets.Colors.CardLight,
		nav = true,
		onActivate = function()
			if nav then
				nav.open("Diagnostics")
			end
		end,
	})
	Widgets.label({
		parent = container,
		name = "SleepNote",
		size = UDim2.new(1, -96 - 340 - 24, 0, NOTE_H),
		position = UDim2.new(0, 48, 1, -16),
		anchor = Vector2.new(0, 1),
		key = "settings.sleepNote",
		textSize = Layout.Text.Body,
		color = Widgets.Colors.TextDim,
	})
	Widgets.watch({ "settings", "mode", "plopDays", "dex" }, function()
		if isOpen then
			refresh()
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("ClipsUnavailable"):Connect(function()
			if isOpen then
				refresh()
			end
		end)
	end
end

-- Affiche le panneau (aucun onglet)
function Settings.open(_tab: string?)
	isOpen = true
	refresh()
end

-- Cache le panneau
function Settings.close()
	isOpen = false
end

-- Onglets, dans l'ordre (L1 / R1) : aucun
function Settings.tabs(): { string }
	return {}
end

-- Change d'onglet (aucun onglet)
function Settings.setTab(_tab: string) end

function Settings.currentTab(): string
	return ""
end

-- Sélection par défaut : le 1er interrupteur (ou le 1er contrôle)
function Settings.defaultSelection(): GuiObject?
	local list = rows
	if list == nil then
		return nil
	end
	for i = 1, list.count() do
		local item = items[i]
		if item and item.kind == "toggle" then
			return list.selectableAt(i, 1)
		end
	end
	return list.selectableAt(1, 2)
end

-- ○ : aucun sous-niveau, retour au menu
function Settings.onBack(): boolean
	return false
end

-- Entrée du menu visible pour ce joueur
function Settings.visible(): boolean
	return true
end

-- Navigateur fourni par PanelController AVANT build
function Settings.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function Settings.refresh()
	refresh()
end

-- Stick droit : une page
function Settings.scroll(dir: number)
	if rows then
		rows.page(dir)
	end
end

-- Lignes affichées (specs)
function Settings._items(): { Item }
	return items
end

-- Contrôle de la ligne d'un réglage, amené à l'écran (specs) : interrupteur, sinon bouton de choix
function Settings._controlFor(key: string): GuiObject?
	local list = rows
	if key == "diagnostics" then
		return if diagButton and diagButton.Visible then diagButton else nil
	end
	if list == nil then
		return nil
	end
	for i, item in items do
		if item.key == key then
			return list.selectableAt(i, if item.kind == "toggle" then 1 else 2)
		end
	end
	return nil
end

return Settings
