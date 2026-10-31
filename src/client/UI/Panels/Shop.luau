--!strict
-- Panels/Shop — paquet « client-panels » (docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * Passes : cartes de Config/Monetization.Passes (id 0 = masqué), prix lus à l'exécution via
--     Client/Util/Prices (repli : prix de la config), « Possédé » (profile.passes),
--     MarketplaceService:PromptGamePassPurchase
--   * Boosts & Glow : produits avec montant « ≈ » calculé côté client (idleRate × idleSeconds,
--     minGlow) ; Glow Party masquée si le boost ×2 de serveur en cours (quelle que soit sa source,
--     comme la file du serveur) a plus de Balance.GlowParty.HideAbove s restantes (sinon « Fête en
--     file : 12 min », ou « Commence après le ×2 en cours » pour la Nuit d'Or, Starfall…) ; Starter Kit
--     visible tant que profile.starterKit est faux, sans compte à rebours ;
--     MarketplaceService:PromptProductPurchase
--   * Codes : champ + Valider → RedeemCode (RemoteFunction, appelée hors du fil d'interface) ;
--     statut → "code.<status>"
--   * aucun faux minuteur, prix en Robux toujours visible, aucune pastille « ! » (§8.1)
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number ;
--     intentions seulement (le serveur valide tout)
-- GDD : §8, §4.17 (Glow Party), §10.3.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Prices = require(Client.Util.Prices)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local WorldState = require(Client.Controllers.WorldStateController)
local Model = require(script.Parent.Model)
local Widgets = require(script.Parent.Widgets)

local Panel = {}

Panel.name = "Shop" :: Types.PanelName
Panel.tabs = { "shop.tab.passes", "shop.tab.boosts", "shop.tab.codes" } :: { string }?

local TAB_IDS = { "passes", "boosts", "codes" }
local ROW_HEIGHT = 112
local REFRESH_INTERVAL = 1
local PROMPT_GUARD = 1 -- s entre deux fenêtres d'achat

-- Grands glyphes (§10.1 : aucune image importée)
local PASS_GLYPHS: { [string]: string } = {
	VIPStar = "⭐",
	DoubleGlow = "✨",
	NightShift = "🌙",
	ExtraPerches = "🏡",
	StashPlus = "📦",
	CongaStyles = "🎨",
}
local PRODUCT_GLYPHS: { [string]: string } = {
	GlowPouch = "🪙",
	GlowSack = "💰",
	GlowCrate = "🎁",
	GlowParty = "🎉",
	StardustJar = "✦",
	StarterKit = "🚀",
}

type Row = {
	key: string,
	kind: "pass" | "product",
	frame: Frame,
	name: TextLabel,
	desc: TextLabel,
	detail: TextLabel,
	buy: TextButton,
	price: number,
}

local view = Model.view(State.get)
local built = false
local isOpen = false
local currentTab = "passes"
local tabFrames: { [string]: Frame } = {}
local passRows: { Row } = {}
local productRows: { Row } = {}
local passesEmpty: TextLabel? = nil
local productsEmpty: TextLabel? = nil
local codeBox: TextBox? = nil
local redeemButton: TextButton? = nil
local codeStatus: TextLabel? = nil
local redeeming = false
local lastPrompt = -math.huge
local refreshAcc = 0

local VALID_STATUS: { [string]: boolean } =
	{ ok = true, invalid = true, expired = true, used = true, busy = true }

-- ---------------------------------------------------------------------------------------------
-- Achats (le serveur crédite : ProcessReceipt / PromptGamePassPurchaseFinished)
-- ---------------------------------------------------------------------------------------------

local function prompt(row: Row)
	local now = Clock.now()
	if now - lastPrompt < PROMPT_GUARD then
		return
	end
	local player = Players.LocalPlayer
	if row.kind == "pass" then
		local def = Monetization.Passes[row.key]
		if not def or def.id <= 0 or Model.ownsPass(view, row.key) then
			Widgets.refuse(row.buy)
			return
		end
		lastPrompt = now
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, def.id)
		end)
		if not ok then
			warn("[Shop] PromptGamePassPurchase :", err)
		end
	else
		local def = Monetization.Products[row.key]
		if not def or def.id <= 0 then
			Widgets.refuse(row.buy)
			return
		end
		lastPrompt = now
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(player, def.id)
		end)
		if not ok then
			warn("[Shop] PromptProductPurchase :", err)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Construction des lignes
-- ---------------------------------------------------------------------------------------------

local function buildRow(key: string, kind: "pass" | "product", order: number, parent: Instance): Row
	local defs: { [string]: any } = if kind == "pass" then Monetization.Passes else Monetization.Products
	local def = defs[key]
	local frame = Widgets.card({
		name = key,
		size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		order = order,
		color = if kind == "pass" then Color3.fromRGB(70, 54, 104) else Widgets.CARD,
		parent = parent,
	})
	local icon = Create("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(80, 80),
		BackgroundColor3 = if kind == "pass" then Theme.Colors.Premium else Theme.Colors.Gold,
		Parent = frame,
	}, { Widgets.round(), Widgets.stroke(), Widgets.gradient() })
	Widgets.label({
		name = "Glyph",
		text = (if kind == "pass" then PASS_GLYPHS[key] else PRODUCT_GLYPHS[key]) or "★",
		size = UDim2.fromScale(0.7, 0.7),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxSize = 46,
		parent = icon,
	})
	local textW = -(104 + 196)
	local name = Widgets.label({
		name = "Name",
		size = UDim2.new(1, textW, 0, 32),
		position = UDim2.fromOffset(104, 6),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 26,
		parent = frame,
	})
	local desc = Widgets.label({
		name = "Desc",
		size = UDim2.new(1, textW, 0, 44),
		position = UDim2.fromOffset(104, 38),
		xAlign = Enum.TextXAlignment.Left,
		yAlign = Enum.TextYAlignment.Top,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 17,
		parent = frame,
	})
	local detail = Widgets.label({
		name = "Detail",
		size = UDim2.new(1, textW, 0, 24),
		position = UDim2.fromOffset(104, 84),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 19,
		parent = frame,
	})
	local row: Row
	local buy = Widgets.button({
		name = "Buy",
		size = UDim2.fromOffset(176, 80),
		position = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.Success,
		maxText = 28,
		parent = frame,
		onClick = function()
			prompt(row)
		end,
	})
	row = {
		key = key,
		kind = kind,
		frame = frame,
		name = name,
		desc = desc,
		detail = detail,
		buy = buy,
		price = def.price,
	}
	-- prix réel lu à l'exécution (tarification gérée) ; repli : prix de la config (§8.1.3)
	if def.id > 0 then
		Prices.observe(kind, def.id, def.price, function(price: number)
			row.price = price
			if built then
				local owned = kind == "pass" and Model.ownsPass(view, key)
				if not owned then
					Widgets.setText(buy, Prefs.t("common.robux", { price = Prefs.commas(price) }))
				end
			end
		end)
	end
	return row
end

local function renderPasses()
	local any = false
	for _, row in passRows do
		local def = Monetization.Passes[row.key]
		local visible = def ~= nil and Model.passVisible(def)
		row.frame.Visible = visible
		if visible then
			any = true
			local owned = Model.ownsPass(view, row.key)
			row.name.Text = Prefs.t(def.nameKey)
			row.desc.Text = Prefs.t(def.descKey)
			row.detail.Text = ""
			if owned then
				Widgets.setText(row.buy, "✓ " .. Prefs.t("common.owned"))
				Widgets.setColor(row.buy, Widgets.DIM)
				Widgets.setEnabled(row.buy, false)
			else
				Widgets.setText(row.buy, Prefs.t("common.robux", { price = Prefs.commas(row.price) }))
				Widgets.setColor(row.buy, Theme.Colors.Success)
				Widgets.setEnabled(row.buy, true)
			end
		end
	end
	if passesEmpty then
		passesEmpty.Text = Prefs.t("shop.empty")
		passesEmpty.Visible = not any
	end
end

local function renderProducts()
	local now = Clock.now()
	local events = WorldState.events()
	local any = false
	for _, row in productRows do
		local def = Monetization.Products[row.key]
		local visible = def ~= nil and Model.productVisible(row.key, def, view, events, now)
		row.frame.Visible = visible
		if visible then
			any = true
			row.name.Text = Prefs.t(def.nameKey)
			row.desc.Text = Prefs.t(def.descKey)
			local glow = Model.productGlow(view, def)
			local party = if def.serverBoostSeconds then Model.glowPartyRemaining(events, now) else 0
			if glow then
				row.detail.Text = Prefs.t("shop.glowAmount", { amount = Prefs.number(glow) })
			elseif def.stardust then
				row.detail.Text = Prefs.t("calendar.reward.stardust", { amount = Prefs.number(def.stardust) })
			elseif party > 0 then
				local source = Model.serverBoostSource(events, now)
				row.detail.Text = Prefs.t(
					if source == "glowParty" then "shop.partyQueued" else "shop.boostQueued",
					{ time = Prefs.duration(party) }
				)
			elseif def.oncePerAccount then
				row.detail.Text = Prefs.t("shop.oncePerAccount")
			else
				row.detail.Text = ""
			end
			Widgets.setText(row.buy, Prefs.t("common.robux", { price = Prefs.commas(row.price) }))
		end
	end
	if productsEmpty then
		productsEmpty.Text = Prefs.t("shop.empty")
		productsEmpty.Visible = not any
	end
end

-- ---------------------------------------------------------------------------------------------
-- Codes promo
-- ---------------------------------------------------------------------------------------------

local function showStatus(status: string)
	local label = codeStatus
	if not label then
		return
	end
	label.Text = Prefs.t("code." .. status)
	label.TextColor3 = if status == "ok"
		then Theme.Colors.Success
		elseif status == "busy" then Theme.Colors.Warning
		else Theme.Colors.Danger
end

local function redeem()
	local box, button = codeBox, redeemButton
	if not box or not button or redeeming then
		return
	end
	local code = Model.normalizeCode(box.Text)
	if code == nil then
		Widgets.refuse(button)
		showStatus("invalid")
		return
	end
	redeeming = true
	Widgets.setEnabled(button, false)
	Widgets.setText(button, Prefs.t("shop.code.checking"))
	task.spawn(function()
		local ok, result = pcall(function()
			return Net.func("RedeemCode"):InvokeServer(code)
		end)
		redeeming = false
		local status = if ok and type(result) == "string" and VALID_STATUS[result] then result else "busy"
		if not ok then
			warn("[Shop] RedeemCode :", result)
		end
		Widgets.setEnabled(button, true)
		Widgets.setText(button, Prefs.t("shop.code.redeem"))
		showStatus(status)
		if status == "ok" then
			box.Text = ""
			AudioController.play("Reward")
		else
			Widgets.refuse(button)
		end
	end)
end

local function renderCodes()
	if codeBox then
		codeBox.PlaceholderText = Prefs.t("shop.code.placeholder")
	end
	if redeemButton and not redeeming then
		Widgets.setText(redeemButton, Prefs.t("shop.code.redeem"))
	end
end

-- ---------------------------------------------------------------------------------------------
-- Interface du panneau
-- ---------------------------------------------------------------------------------------------

local function renderTab(id: string)
	if id == "passes" then
		renderPasses()
	elseif id == "boosts" then
		renderProducts()
	elseif id == "codes" then
		renderCodes()
	end
end

local function listFrame(id: string, parent: Instance): ScrollingFrame
	local frame = Create("ScrollingFrame", {
		Name = "Tab_" .. id,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Selectable = false,
		Visible = false,
		Parent = parent,
	}, { Widgets.listLayout(Enum.FillDirection.Vertical, 8) }) :: ScrollingFrame
	tabFrames[id] = frame
	return frame
end

local function emptyLabel(parent: Instance): TextLabel
	return Widgets.label({
		name = "Empty",
		size = UDim2.new(1, -12, 0, 48),
		color = Theme.Colors.TextDim,
		maxSize = 24,
		order = 999,
		parent = parent,
	})
end

function Panel.build(parent: Frame)
	if built then
		return
	end
	built = true
	local passes = listFrame("passes", parent)
	for i, key in Model.ordered(Monetization.Passes :: any) do
		table.insert(passRows, buildRow(key, "pass", i, passes))
	end
	passesEmpty = emptyLabel(passes)
	local products = listFrame("boosts", parent)
	for i, key in Model.ordered(Monetization.Products :: any) do
		table.insert(productRows, buildRow(key, "product", i, products))
	end
	productsEmpty = emptyLabel(products)

	local codes = Create("Frame", {
		Name = "Tab_codes",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	}) :: Frame
	tabFrames.codes = codes
	codeBox = Create("TextBox", {
		Name = "CodeBox",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.05, 0, 0, 24),
		Size = UDim2.new(0.58, 0, 0, 72),
		BackgroundColor3 = Widgets.BOTTOM,
		ClearTextOnFocus = false,
		Text = "",
		PlaceholderText = "",
		PlaceholderColor3 = Theme.Colors.TextDim,
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.Title,
		TextScaled = true,
		Selectable = true,
		Parent = codes,
	}, {
		Widgets.corner(Theme.CornerSmall),
		Widgets.stroke(),
		Widgets.padding(10),
		Create("UITextSizeConstraint", { MaxTextSize = 30 }),
	}) :: TextBox
	redeemButton = Widgets.button({
		name = "Redeem",
		size = UDim2.new(0.3, 0, 0, 72),
		position = UDim2.new(0.95, 0, 0, 24),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.Primary,
		maxText = 26,
		parent = codes,
		onClick = redeem,
	})
	codeStatus = Widgets.label({
		name = "Status",
		size = UDim2.new(0.9, 0, 0, 40),
		position = UDim2.new(0.5, 0, 0, 112),
		anchor = Vector2.new(0.5, 0),
		maxSize = 26,
		parent = codes,
	})
	if codeBox then
		codeBox.FocusLost:Connect(function(enterPressed: boolean)
			if enterPressed then
				redeem()
			end
		end)
	end

	State.Changed:Connect(function(key: string)
		if isOpen and (key == "passes" or key == "starterKit" or key == "idleRate") then
			renderTab(currentTab)
		end
	end)
	Prefs.LanguageChanged:Connect(function()
		renderTab(currentTab)
	end)
end

function Panel.onOpen(_args: any?)
	isOpen = true
	renderTab(currentTab)
end

function Panel.onClose()
	isOpen = false
	if codeStatus then
		codeStatus.Text = ""
	end
end

-- Jamais de pastille sur la Boutique : aucune pression d'achat (§8.1)
function Panel.hasAction(): boolean
	return false
end

function Panel.selectTab(tab: string)
	local id = string.match(tab, "([^%.]+)$") or tab
	if not table.find(TAB_IDS, id) then
		return
	end
	currentTab = id
	for key, frame in tabFrames do
		frame.Visible = key == id
	end
	renderTab(id)
end

function Panel.step(dt: number)
	if not built then
		return
	end
	refreshAcc += dt
	if refreshAcc >= REFRESH_INTERVAL then
		refreshAcc = 0
		if currentTab == "boosts" then
			renderProducts() -- Glow Party en cours, montants « ≈ »
		end
	end
end

function Panel.defaultSelection(): GuiObject?
	if currentTab == "codes" then
		return codeBox
	end
	local rows = if currentTab == "passes" then passRows else productRows
	for _, row in rows do
		if row.frame.Visible then
			return row.buy
		end
	end
	return nil
end

-- Exposé pour les tests
Panel._rows = function(): ({ Row }, { Row })
	return passRows, productRows
end
Panel._redeem = redeem
Panel._codeBox = function(): TextBox?
	return codeBox
end
Panel._status = function(): TextLabel?
	return codeStatus
end

return Panel
