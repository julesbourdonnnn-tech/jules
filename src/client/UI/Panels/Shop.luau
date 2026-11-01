--!strict
-- Shop (paquet client-panels) : panneau Boutique (GDD §8, §10.3 ; docs/04 §13.6, contrat v1.2) :
-- onglets Passes / Fête / Tenues ; prix lus à l'exécution (Util/Prices, repli sur la config) ;
-- chaque article dont l'id vaut 0 ou qui est `hidden` (CoinsSmall, CoinsBig, SeasonPass) est caché,
-- et un onglet sans article visible n'existe pas ; aucune règle PolicyService ne cache un article
-- (le jeu ne vend rien d'aléatoire). Boutique cachée pendant les 10 premières minutes de jeu cumulé
-- (Config/Quests.ShopHiddenUntil) et tant qu'aucun article n'est vendu. Bouton Squish Party caché
-- pendant une fête (EventState.boost « squish »), « 2 sur 3 aujourd'hui », case « Montrer mon nom »
-- (SetSetting partyShowName). Tenues : aperçu 3D (Panels/OutfitPreview par le navigateur) avant
-- l'achat. ClientEvent("shopOpened") à CHAQUE ouverture ; UiSeen("shop") à la première. Achat :
-- invite de Roblox sous pcall, sélection tenue pendant la fenêtre de Roblox (FocusGuard.hold).
-- Sélection par défaut : le 1er « Acheter » de l'onglet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Monetization = require(Shared.Config.Monetization)
local Quests = require(Shared.Config.Quests)
local Layout = require(Shared.Config.Layout)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent.Parent
local Prices = require(Client.Util.Prices)
local Prefs = require(Client.Util.Prefs)
local WorldStateController = require(Client.Controllers.WorldStateController)
local FocusGuard = require(Client.UI.FocusGuard)
local Widgets = require(script.Parent.Widgets)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }
type Item = {
	key: string,
	kind: "pass" | "product",
	id: number,
	price: number,
	nameKey: string,
	descKey: string,
	order: number,
	tab: string,
	forever: boolean,
	outfit: string?,
	dailyLimit: number?,
}
type CardUi = {
	item: Item,
	frame: Frame,
	buy: TextButton,
	price: TextLabel,
	state: TextLabel,
	preview: TextButton?,
	extra: TextLabel?,
	showName: Widgets.Toggle?,
}

local Shop = {}

local ALL_TABS = { "passes", "party", "outfits" }

local nav: Nav? = nil
local tabBar: Widgets.TabBar? = nil
local current = "passes"
local isOpen = false
local pages: { [string]: Frame } = {}
local cardsByTab: { [string]: { CardUi } } = {}
local partyShown: boolean? = nil -- état de fête affiché (le bouton Squish Party suit la fête en direct)
local partyWatch: RBXScriptConnection? = nil

-- Articles vendus au lancement : id ≠ 0 et jamais `hidden` (contrat v1.2)
local function sellable(def: any): boolean
	return type(def) == "table" and type(def.id) == "number" and def.id > 0 and def.hidden ~= true
end

local function items(): { Item }
	local out: { Item } = {}
	for key, def in Monetization.Passes do
		if sellable(def) then
			table.insert(out, {
				key = key,
				kind = "pass",
				id = def.id,
				price = def.price,
				nameKey = def.nameKey,
				descKey = def.descKey,
				order = def.order,
				tab = "passes",
				forever = def.forever,
			})
		end
	end
	for key, def in Monetization.Products do
		if sellable(def) then
			table.insert(out, {
				key = key,
				kind = "product",
				id = def.id,
				price = def.price,
				nameKey = def.nameKey,
				descKey = def.descKey,
				order = def.order,
				tab = def.tab,
				forever = false,
				outfit = def.outfit,
				dailyLimit = def.dailyLimit,
			})
		end
	end
	table.sort(out, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.key < b.key
	end)
	return out
end

local function itemsOf(tab: string): { Item }
	local out = {}
	for _, item in items() do
		if item.tab == tab then
			table.insert(out, item)
		end
	end
	return out
end

local function visibleTabs(): { string }
	local out = {}
	for _, tab in ALL_TABS do
		if #itemsOf(tab) > 0 then
			table.insert(out, tab)
		end
	end
	return out
end

-- Une Squish Party est en cours sur ce serveur (EventState.boost, WorldStateController)
local function partyActive(): boolean
	local event = Widgets.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(event) ~= "table" or type(event.boost) ~= "table" then
		return false
	end
	return event.boost.kind == "squish" and Widgets.n(event.boost.untilT) > Clock.now()
end

local function partyBuysToday(): number
	local caps = Widgets.tbl(Widgets.state("caps"))
	if Widgets.n(caps.day) ~= Clock.day() then
		return 0
	end
	return math.max(0, math.floor(Widgets.n(caps.partyBuys)))
end

local function owned(item: Item): boolean
	if item.kind == "pass" then
		return Widgets.tbl(Widgets.state("passes"))[item.key] == true
	end
	return false
end

local function outfitCount(id: string?): number
	if id == nil then
		return 0
	end
	local outfits = Widgets.tbl(Widgets.state("outfits"))
	return math.max(0, math.floor(Widgets.n(Widgets.tbl(outfits.owned)[id])))
end

local function refreshCards()
	local active = partyActive()
	partyShown = active
	for _, list in cardsByTab do
		for _, ui in list do
			local item = ui.item
			local label = Widgets.buttonLabel(ui.buy) :: TextLabel
			if item.kind == "pass" and owned(item) then
				ui.buy.Visible = true
				Widgets.setText(label, "common.owned")
				Widgets.setDisabled(ui.buy, true)
				Widgets.setText(ui.state, "panel.shop.forever")
			elseif item.dailyLimit then
				-- Squish Party : vendue seulement si elle peut commencer aussitôt
				ui.buy.Visible = not active
				local left = math.max(0, item.dailyLimit - partyBuysToday())
				Widgets.setText(label, "common.buy")
				Widgets.setDisabled(ui.buy, left <= 0)
				if active then
					Widgets.setText(ui.state, "panel.shop.partyActive")
				else
					Widgets.setText(ui.state, "panel.shop.partyLeft", { n = left })
				end
				if ui.showName then
					ui.showName.set(Prefs.get("partyShowName") == true)
				end
			else
				ui.buy.Visible = true
				Widgets.setText(label, "common.buy")
				Widgets.setDisabled(ui.buy, false)
				if item.outfit then
					Widgets.setText(ui.state, "panel.shop.outfitOwned", { n = outfitCount(item.outfit) })
				elseif item.forever then
					Widgets.setText(ui.state, "panel.shop.forever")
				else
					Widgets.setRaw(ui.state, "")
				end
			end
		end
	end
end

local function showPage(tab: string)
	local tabs = visibleTabs()
	for id, page in pages do
		page.Visible = id == tab
	end
	if tabBar then
		for _, id in ALL_TABS do
			tabBar.setVisible(id, table.find(tabs, id) ~= nil)
		end
		tabBar.setActive(tab)
	end
end

local function refresh()
	local tabs = visibleTabs()
	if not table.find(tabs, current) then
		current = tabs[1] or "passes"
	end
	showPage(current)
	refreshCards()
end

local function buildCard(page: Frame, item: Item, index: number, count: number): CardUi
	local width = page.Size.X.Offset - 96
	local gap = Layout.Spacing.Normal
	local cols = math.max(1, math.min(4, count))
	local cardW = math.floor((width - (cols - 1) * gap) / cols)
	local cardH = 600
	local f = Widgets.frame({
		parent = page,
		name = "Item_" .. item.key,
		size = UDim2.fromOffset(cardW, cardH),
		position = UDim2.fromOffset(48 + ((index - 1) % cols) * (cardW + gap), 16),
		color = Widgets.Colors.Card,
		gradient = true,
	})
	Widgets.label({
		parent = f,
		name = "Name",
		size = UDim2.new(1, -32, 0, 56),
		position = UDim2.fromOffset(16, 16),
		key = item.nameKey,
		textSize = 40,
		color = Widgets.Colors.Gold,
	})
	Widgets.label({
		parent = f,
		name = "Desc",
		size = UDim2.new(1, -32, 0, 150),
		position = UDim2.fromOffset(16, 80),
		key = item.descKey,
		textSize = 32,
		wrapped = true,
	})
	local state = Widgets.label({
		parent = f,
		name = "State",
		size = UDim2.new(1, -32, 0, 40),
		position = UDim2.fromOffset(16, 240),
		text = "",
		textSize = 32,
		color = Widgets.Colors.Success,
	})
	local price = Widgets.label({
		parent = f,
		name = "Price",
		size = UDim2.new(1, -32, 0, 56),
		position = UDim2.fromOffset(16, 288),
		key = "common.robux",
		vars = { price = item.price },
		textSize = 48,
	})
	local buy = Widgets.button({
		parent = f,
		name = "Buy",
		size = UDim2.new(1, -48, 0, Layout.Button.MainHeight),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		key = "common.buy",
		color = Widgets.Colors.Success,
		onActivate = function()
			Widgets.promptPurchase(item.kind, item.id)
		end,
	})
	buy:SetAttribute("BuyButton", true)
	local ui: CardUi = { item = item, frame = f, buy = buy, price = price, state = state }
	if item.outfit then
		ui.preview = Widgets.button({
			parent = f,
			name = "Preview",
			size = UDim2.new(1, -48, 0, Layout.Button.MinHeight),
			position = UDim2.new(0.5, 0, 1, -(24 + Layout.Button.MainHeight + Layout.Spacing.Min)),
			anchor = Vector2.new(0.5, 1),
			key = "panel.shop.preview",
			nav = true,
			onActivate = function()
				if nav then
					nav.open("OutfitPreview", item.outfit)
				end
			end,
		})
	end
	if item.dailyLimit then
		local holder = Widgets.group(
			f,
			"ShowName",
			UDim2.new(1, -48, 0, Layout.Panel.toggle.h),
			UDim2.new(
				0,
				24,
				1,
				-(24 + Layout.Button.MainHeight + Layout.Spacing.Normal + Layout.Panel.toggle.h)
			)
		)
		Widgets.label({
			parent = holder,
			name = "Label",
			size = UDim2.new(1, -(Layout.Panel.toggle.w + 16), 1, 0),
			key = "panel.shop.showName",
			textSize = 32,
			xAlign = Enum.TextXAlignment.Left,
		})
		ui.showName = Widgets.toggle(
			holder,
			"Toggle",
			UDim2.fromScale(1, 0.5),
			Vector2.new(1, 0.5),
			function(v: boolean)
				Widgets.send("SetSetting", "partyShowName", v)
			end
		)
	end
	-- prix réel (tarification régionale) dès qu'il est connu ; repli : prix de la config
	Prices.observe(item.kind, item.id, item.price, function(p: number)
		if price.Parent ~= nil then
			Widgets.setText(price, "common.robux", { price = p })
		end
	end)
	return ui
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Shop.build(container: Frame)
	local specs = {}
	for _, id in ALL_TABS do
		table.insert(specs, { id = id, key = "panel.shop.tab." .. id })
	end
	tabBar = Widgets.tabBar(container, specs, function(id: string)
		Shop.setTab(id)
	end)
	local top = Layout.Panel.tabHeight + 24
	for _, tab in ALL_TABS do
		local page = Widgets.group(
			container,
			"Page_" .. tab,
			UDim2.fromOffset(container.Size.X.Offset, container.Size.Y.Offset - top),
			UDim2.fromOffset(0, top)
		)
		page.Visible = false
		pages[tab] = page
		local list = itemsOf(tab)
		local cards: { CardUi } = {}
		for i, item in list do
			table.insert(cards, buildCard(page, item, i, #list))
		end
		cardsByTab[tab] = cards
	end
	Widgets.watch({ "passes", "caps", "outfits", "settings", "stats" }, function()
		if isOpen then
			refresh()
		end
	end)
end

-- La fête a commencé ou fini pendant que la Boutique est ouverte : le bouton Squish Party suit
-- (EventState par WorldStateController.EventChanged, et fin à l'heure même sans nouveau message) ; la
-- sélection posée sur le bouton caché revient aussitôt (FocusGuard.refocus, pas un sauvetage)
local function onPartyMaybeChanged()
	if isOpen and partyActive() ~= partyShown then
		refresh()
		FocusGuard.refocus()
	end
end

-- Connexions faites au démarrage du client (PanelController.Start)
local startedListening = false
function Shop.start()
	if startedListening then
		return
	end
	startedListening = true
	local changed = (WorldStateController :: any).EventChanged
	if type(changed) == "table" then
		pcall(function()
			changed:Connect(onPartyMaybeChanged)
		end)
	end
end

-- Affiche le panneau (onglet demandé ou le dernier) ; ClientEvent("shopOpened") à chaque ouverture
function Shop.open(tab: string?)
	isOpen = true
	Widgets.send("ClientEvent", "shopOpened")
	Widgets.seen("shop")
	if type(tab) == "string" and table.find(visibleTabs(), tab) then
		current = tab
	end
	refresh()
	-- fin de la fête à son heure : vérifiée à chaque image tant que la Boutique est ouverte (deux lectures)
	if partyWatch == nil then
		partyWatch = RunService.Heartbeat:Connect(onPartyMaybeChanged)
	end
end

-- Cache le panneau
function Shop.close()
	isOpen = false
	local c = partyWatch
	partyWatch = nil
	if c then
		c:Disconnect()
	end
end

-- Onglets, dans l'ordre (L1 / R1) : seulement ceux qui ont un article
function Shop.tabs(): { string }
	return visibleTabs()
end

-- Change d'onglet
function Shop.setTab(tab: string)
	if type(tab) ~= "string" or not table.find(visibleTabs(), tab) then
		return
	end
	current = tab
	refresh()
end

function Shop.currentTab(): string
	return current
end

-- Sélection par défaut : le 1er « Acheter » de l'onglet
function Shop.defaultSelection(): GuiObject?
	for _, ui in cardsByTab[current] or {} do
		if ui.buy.Visible and not Widgets.isDisabled(ui.buy) then
			return ui.buy
		end
	end
	for _, ui in cardsByTab[current] or {} do
		if ui.buy.Visible then
			return ui.buy
		end
		if ui.preview then
			return ui.preview
		end
	end
	return if tabBar then tabBar.buttons[current] else nil
end

-- ○ : retour au menu
function Shop.onBack(): boolean
	return false
end

-- Entrée du menu : après 10 min de jeu cumulé et si au moins un article est vendu
function Shop.visible(): boolean
	local stats = Widgets.tbl(Widgets.state("stats"))
	if Widgets.n(stats.playSeconds) < Quests.ShopHiddenUntil then
		return false
	end
	return #visibleTabs() > 0
end

-- Navigateur fourni par PanelController AVANT build
function Shop.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function Shop.refresh()
	refresh()
end

-- Clés des articles affichés dans un onglet (specs)
function Shop._itemKeys(tab: string): { string }
	local out = {}
	for _, item in itemsOf(tab) do
		table.insert(out, item.key)
	end
	return out
end

-- Bouton « Acheter » d'un article (specs)
function Shop._buyButton(key: string): TextButton?
	for _, list in cardsByTab do
		for _, ui in list do
			if ui.item.key == key then
				return ui.buy
			end
		end
	end
	return nil
end

return Shop
