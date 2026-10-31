--!strict
-- Panels/Supernova — paquet « client-panels » (docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * aperçu obligatoire : deux colonnes « Tu gardes » / « Remis à zéro », gains de la prochaine
--     Supernova (+40 % de revenu, +5 au plafond Conga, Dash −0,25 s, aura), coût et Glow prédit —
--     calculés côté client avec Logic/Formulas et Config (Panels/Model.supernovaPreview : mêmes
--     règles que EconomyService.supernovaPreview)
--   * bouton à MAINTENIR Balance.Supernova.HoldSeconds (1 s) avec anneau → remote Supernova() ;
--     relâcher avant la fin annule ; un seul envoi (le serveur limite aussi à 1 / 2 s). La fin du
--     maintien est lue sur UserInputService.InputEnded (le doigt relevé HORS du bouton ne déclenche
--     ni MouseButton1Up ni, sur mobile, MouseLeave) ; manette : A sur le bouton sélectionné
--   * hors du port sûr de son Nid : message « Rentre au Nid » (refus si on maintient)
--   * back() → Upgrades (Panel.parent)
--   * hasAction : Glow prédit ≥ coût
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number ;
--     intentions seulement (le serveur valide tout : port sûr, coût, encaissement de la file)
-- GDD : §4.12, §10.3, §9.4 (Supernova), §13.2 (seul appui maintenu du jeu).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local PanelController = require(Client.Controllers.PanelController)
local Model = require(script.Parent.Model)
local Widgets = require(script.Parent.Widgets)

local Panel = {}

Panel.name = "Supernova" :: Types.PanelName
Panel.tabs = nil :: { string }?
Panel.parent = "Upgrades" :: Types.PanelName

local HOLD_SECONDS = Balance.Supernova.HoldSeconds
local RESEND_GUARD = 2 -- s : pas de second envoi (débit serveur 1 / 2 s)
local CLOSE_AFTER = 0.25
local REFRESH_INTERVAL = 0.25
local ITEM_HEIGHT = 30

local view = Model.view(State.get)
local built = false
local isOpen = false
local holding = false
local holdTime = 0
-- entrée qui a commencé le maintien (un toucher précis, une touche) : seule sa fin l'arrête,
-- un autre doigt (joystick) relevé ne l'annule pas ; nil = appui souris
local holdInput: InputObject? = nil
local sentAt = -math.huge
local refreshAcc = 0
local preview: Types.SupernovaPreview? = nil

local refs: {
	cost: TextLabel?,
	missing: TextLabel?,
	bar: Frame?,
	keepTitle: TextLabel?,
	resetTitle: TextLabel?,
	keepList: Frame?,
	resetList: Frame?,
	gainTitle: TextLabel?,
	gains: { TextLabel },
	status: TextLabel?,
	hold: TextButton?,
	holdLabel: TextLabel?,
	ring: Widgets.Ring?,
} =
	{ gains = {} }

-- Le joueur est-il dans le port sûr de SON Nid ? (même règle que NestService.inOwnHarbor)
local function inOwnHarbor(): boolean
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local slot = player:GetAttribute("Slot")
	if type(slot) ~= "number" or slot < 1 then
		return false
	end
	return WorldLayout.inOwnHarbor(slot, root.Position)
end

local function itemList(parent: Frame, keys: { string }, glyph: string, color: Color3)
	for _, child in parent:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, key in keys do
		Widgets.label({
			name = "Item_" .. key,
			text = `{glyph} {Prefs.t("supernova.item." .. key)}`,
			size = UDim2.new(1, -8, 0, ITEM_HEIGHT),
			xAlign = Enum.TextXAlignment.Left,
			color = color,
			font = Theme.Fonts.Body,
			maxSize = 20,
			order = i,
			parent = parent,
		})
	end
end

local function decimal(x: number): string
	local s = if x % 1 == 0
		then tostring(math.floor(x))
		else (string.gsub(string.format("%.2f", x), "0+$", ""))
	if Prefs.language() == "fr" then
		s = string.gsub(s, "%.", ",")
	end
	return s
end

local function canConfirm(p: Types.SupernovaPreview): boolean
	return p.inHarbor and p.canAfford and Clock.now() - sentAt >= RESEND_GUARD
end

local function render()
	if not built then
		return
	end
	local p = Model.supernovaPreview(view, Clock.now(), inOwnHarbor())
	local previous = preview
	preview = p
	if refs.cost then
		refs.cost.Text = Prefs.t("supernova.cost", { cost = Prefs.number(p.cost) })
	end
	if refs.bar then
		Widgets.setBar(refs.bar, if p.cost > 0 then p.glow / p.cost else 0, false)
	end
	if refs.missing then
		refs.missing.Text = if p.canAfford
			then Prefs.t("supernova.ready")
			else Prefs.t("supernova.missing", { missing = Prefs.number(p.cost - p.glow) })
		refs.missing.TextColor3 = if p.canAfford then Theme.Colors.Success else Theme.Colors.TextDim
	end
	if refs.keepTitle then
		refs.keepTitle.Text = Prefs.t("supernova.keep")
	end
	if refs.resetTitle then
		refs.resetTitle.Text = Prefs.t("supernova.reset")
	end
	-- les listes ne changent qu'avec la configuration ou la langue
	if
		previous == nil
		or previous.level ~= p.level
		or refs.keepList and #refs.keepList:GetChildren() <= 1
	then
		if refs.keepList then
			itemList(refs.keepList, p.keeps, "✓", Theme.Colors.Success)
		end
		if refs.resetList then
			itemList(refs.resetList, p.resets, "↺", Theme.Colors.Warning)
		end
	end
	if refs.gainTitle then
		refs.gainTitle.Text = Prefs.t("supernova.gain")
	end
	local lines = {
		Prefs.t("supernova.income", {
			from = math.floor(p.incomeNow * 100 + 0.5),
			to = math.floor(p.incomeNext * 100 + 0.5),
		}),
		Prefs.t("supernova.congaCap", {
			from = Model.effect(view, "conga", p.congaCapNow),
			to = Model.effect(view, "conga", p.congaCapNext),
		}),
		Prefs.t("supernova.dash", { from = decimal(p.dashNow), to = decimal(p.dashNext) }),
		if p.auraNext then Prefs.t("supernova.aura", { aura = Prefs.t("aura." .. p.auraNext) }) else "",
	}
	for i, label in refs.gains do
		label.Text = lines[i] or ""
		label.Visible = (lines[i] or "") ~= ""
	end
	if refs.status then
		refs.status.Text = if not p.inHarbor then Prefs.t("supernova.goHome") else ""
		refs.status.Visible = not p.inHarbor
	end
	if refs.holdLabel then
		refs.holdLabel.Text = Prefs.t("supernova.hold")
	end
	if refs.hold then
		Widgets.setColor(refs.hold, if canConfirm(p) then Theme.Colors.Premium else Widgets.DIM)
	end
end

local function resetHold()
	holding = false
	holdTime = 0
	holdInput = nil
	if refs.ring then
		Widgets.setRing(refs.ring, 0)
	end
end

local function isConfirmKey(input: InputObject): boolean
	local key = input.KeyCode
	return key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter
end

local function isPointer(input: InputObject): boolean
	local kind = input.UserInputType
	return kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1
end

-- `source` : l'entrée qui commence le maintien (nil = MouseButton1Down sans InputObject)
local function beginHold(source: InputObject?)
	if holding then
		-- MouseButton1Down et InputBegan arrivent tous deux : on garde l'entrée précise
		if holdInput == nil and source ~= nil then
			holdInput = source
		end
		return
	end
	if not isOpen then
		return
	end
	render()
	local p = preview
	if p == nil or not canConfirm(p) then
		if refs.hold then
			Widgets.refuse(refs.hold)
		end
		if refs.status and p and not p.inHarbor then
			Juice.pulse(refs.status, 1.15)
		end
		return
	end
	holding = true
	holdTime = 0
	holdInput = source
end

local function endHold()
	if holding then
		resetHold()
	end
end

-- Fin d'une entrée n'importe où sur l'écran : arrête-t-elle le maintien ?
local function endsHold(input: InputObject): boolean
	local source = holdInput
	if source == nil then
		return isPointer(input) or isConfirmKey(input)
	end
	if source.UserInputType == Enum.UserInputType.Touch then
		return input == source
	end
	if isConfirmKey(source) then
		return input.KeyCode == source.KeyCode
	end
	return input.UserInputType == source.UserInputType
end

local function confirm()
	resetHold()
	local p = preview
	if p == nil or not canConfirm(p) then
		return
	end
	sentAt = Clock.now()
	Net.event("Supernova"):FireServer()
	AudioController.play("Reward")
	Juice.flash(Theme.Colors.Gold, 0.2, 0.25)
	task.delay(CLOSE_AFTER, function()
		if PanelController.current() == "Supernova" then
			PanelController.close()
		end
	end)
end

function Panel.build(parent: Frame)
	if built then
		return
	end
	built = true
	-- haut : coût et progression
	refs.cost = Widgets.label({
		name = "Cost",
		size = UDim2.new(0.6, 0, 0, 34),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 28,
		parent = parent,
	})
	refs.missing = Widgets.label({
		name = "Missing",
		size = UDim2.new(0.4, 0, 0, 34),
		position = UDim2.fromScale(0.6, 0),
		xAlign = Enum.TextXAlignment.Right,
		maxSize = 22,
		parent = parent,
	})
	refs.bar = Widgets.bar({
		name = "GlowBar",
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 40),
		color = Theme.Colors.Gold,
		parent = parent,
	})
	-- milieu : colonnes et gains (défilant sur petit écran)
	local scroll = Create("ScrollingFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -(64 + 124)),
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Selectable = false,
		Parent = parent,
	}, { Widgets.listLayout(Enum.FillDirection.Vertical, 8) })
	local columns = Create("Frame", {
		Name = "Columns",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = scroll,
	})
	local function column(name: string, x: number, titleColor: Color3): (TextLabel, Frame)
		local card = Widgets.card({
			name = name,
			size = UDim2.new(0.5, -4, 0, 0),
			position = UDim2.fromScale(x, 0),
			parent = columns,
		})
		card.AutomaticSize = Enum.AutomaticSize.Y
		Widgets.padding(8).Parent = card
		Widgets.listLayout(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left).Parent = card
		local title = Widgets.label({
			name = "Title",
			size = UDim2.new(1, 0, 0, 32),
			xAlign = Enum.TextXAlignment.Left,
			color = titleColor,
			maxSize = 26,
			order = 0,
			parent = card,
		})
		local items = Create("Frame", {
			Name = "Items",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = card,
		}, { Widgets.listLayout(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left) }) :: Frame
		return title, items
	end
	refs.keepTitle, refs.keepList = column("Keep", 0, Theme.Colors.Success)
	refs.resetTitle, refs.resetList = column("Reset", 0.5, Theme.Colors.Warning)
	local gains = Widgets.card({
		name = "Gains",
		size = UDim2.new(1, -8, 0, 0),
		color = Color3.fromRGB(76, 56, 120),
		order = 2,
		parent = scroll,
	})
	gains.AutomaticSize = Enum.AutomaticSize.Y
	Widgets.padding(8).Parent = gains
	Widgets.listLayout(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left).Parent = gains
	refs.gainTitle = Widgets.label({
		name = "Title",
		size = UDim2.new(1, 0, 0, 32),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 26,
		parent = gains,
	})
	for i = 1, 4 do
		refs.gains[i] = Widgets.label({
			name = "Gain" .. i,
			size = UDim2.new(1, 0, 0, ITEM_HEIGHT),
			xAlign = Enum.TextXAlignment.Left,
			font = Theme.Fonts.Body,
			maxSize = 20,
			order = i,
			parent = gains,
		})
	end
	-- bas : message « Rentre au Nid » et bouton maintenu 1 s
	refs.status = Widgets.label({
		name = "Status",
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.new(0, 0, 1, -120),
		color = Theme.Colors.Warning,
		maxSize = 22,
		parent = parent,
	})
	local hold, holdLabel = Widgets.button({
		name = "Hold",
		size = UDim2.new(0.7, 0, 0, 96),
		position = UDim2.new(0.5, 0, 1, 0),
		anchor = Vector2.new(0.5, 1),
		color = Theme.Colors.Premium,
		maxText = 30,
		parent = parent,
		sound = "",
	})
	holdLabel.Size = UDim2.new(1, -110, 1, -10)
	holdLabel.Position = UDim2.new(0.5, 44, 0.5, 0)
	holdLabel.FontFace = Widgets.STAMP_FONT
	refs.hold = hold
	refs.holdLabel = holdLabel
	local ring = Widgets.ring("HoldRing", 76, 20, Theme.Colors.Gold, nil, hold)
	ring.frame.AnchorPoint = Vector2.new(0, 0.5)
	ring.frame.Position = UDim2.new(0, 12, 0.5, 0)
	refs.ring = ring
	hold.MouseButton1Down:Connect(function()
		beginHold(nil)
	end)
	hold.MouseButton1Up:Connect(endHold)
	-- quitter le bouton annule (prudence : action irréversible) ; sur mobile MouseLeave n'est pas
	-- garanti, la fin du toucher est donc aussi suivie plus bas (InputEnded global)
	hold.MouseLeave:Connect(endHold)
	hold.SelectionLost:Connect(function()
		local source = holdInput
		if source ~= nil and isConfirmKey(source) then
			endHold()
		end
	end)
	hold.InputBegan:Connect(function(input: InputObject)
		if isPointer(input) then
			beginHold(input)
		end
	end)
	-- manette / clavier : A ou Entrée sur le bouton sélectionné (GuiService.SelectedObject)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if isOpen and isConfirmKey(input) and GuiService.SelectedObject == hold then
			beginHold(input)
		end
	end)
	-- fin du maintien lue partout : doigt relevé hors du bouton, A relâché…
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if holding and endsHold(input) then
			endHold()
		end
	end)

	State.Changed:Connect(function(key: string)
		if isOpen and (key == "glow" or key == "supernovas" or key == "idleRate") then
			render()
		end
	end)
	Prefs.LanguageChanged:Connect(function()
		preview = nil
		render()
	end)
	render()
end

function Panel.onOpen(_args: any?)
	isOpen = true
	resetHold()
	preview = nil
	render()
end

function Panel.onClose()
	isOpen = false
	resetHold()
end

function Panel.hasAction(): boolean
	local p = Model.supernovaPreview(view, Clock.now(), false)
	return p.canAfford
end

function Panel.step(dt: number)
	if not built then
		return
	end
	if holding then
		holdTime += dt
		if refs.ring then
			Widgets.setRing(refs.ring, holdTime / HOLD_SECONDS)
		end
		if holdTime >= HOLD_SECONDS then
			confirm()
		end
	end
	refreshAcc += dt
	if refreshAcc >= REFRESH_INTERVAL then
		refreshAcc = 0
		render()
		-- sortie du port sûr pendant le maintien : on annule
		local p = preview
		if holding and p and not p.inHarbor then
			resetHold()
		end
	end
end

function Panel.defaultSelection(): GuiObject?
	return refs.hold
end

-- Exposé pour les tests
Panel._refs = refs
Panel._holding = function(): boolean
	return holding
end
Panel._inOwnHarbor = inOwnHarbor

return Panel
