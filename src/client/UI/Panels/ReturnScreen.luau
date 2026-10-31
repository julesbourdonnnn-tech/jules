--!strict
-- Panels/ReturnScreen — paquet « client-panels » (docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * écran de retour (Celebrate "offline" : data = { glow, seconds, nightShift }) :
--     « Pendant ton absence (5 h 12) : +1,24 M Glow », compteur qui défile 0,8 s Quint Out, fontaine
--     de pièces (réserve de Frames réutilisées, aucune en Mouvement réduit), bouton « Super ! »
--     96 px ; ligne discrète « Night Shift : 75 % pendant 12 h » si le pass n'est pas possédé et
--     qu'il est en vente (id ≠ 0) — jamais insistante
--   * fenêtre réduite (Panel.compact) ; textes via Prefs.t (ré-appliqués sur
--     Prefs.LanguageChanged), nombres via Prefs.number ; aucun remote (le serveur a déjà crédité)
-- GDD : §7.2, §9.4 (Retour hors ligne), §10.3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
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

Panel.name = "ReturnScreen" :: Types.PanelName
Panel.tabs = nil :: { string }?
Panel.compact = true

local COUNT_TIME = 0.8 -- compteur 0,8 s Quint Out (§7.2)
local COIN_COUNT = 24
local COIN_LIFE = 1.3
local GRAVITY = 2.4 -- en fractions de hauteur par s²

type Coin = { frame: Frame, x: number, y: number, vx: number, vy: number, age: number, delay: number }

local view = Model.view(State.get)
local built = false
local isOpen = false
local data = { glow = 0, seconds = 0, nightShift = false }
local countTime = math.huge
local coins: { Coin } = {}
local rng = Random.new()

local title: TextLabel? = nil
local amount: TextLabel? = nil
local nightShift: TextLabel? = nil
local okButton: TextButton? = nil
local fountain: Frame? = nil

local function finite(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge or x < 0 then
		return 0
	end
	return x
end

local function amountText(value: number): string
	return Prefs.t("return.glow", { amount = Prefs.number(math.floor(value)) })
end

local function render()
	if not built then
		return
	end
	if title then
		title.Text = Prefs.t("return.title", { time = Prefs.duration(data.seconds) })
	end
	if amount and countTime >= COUNT_TIME then
		amount.Text = amountText(data.glow)
	end
	if nightShift then
		local pass = Monetization.Passes.NightShift
		nightShift.Text = Prefs.t("return.nightShift")
		nightShift.Visible = pass ~= nil and pass.id > 0 and not Model.ownsPass(view, "NightShift")
	end
	if okButton then
		Widgets.setText(okButton, Prefs.t("return.ok"))
	end
end

local function launchCoins()
	local root = fountain
	if not root or Juice.reducedMotion() then
		for _, coin in coins do
			coin.frame.Visible = false
		end
		return
	end
	for i = 1, COIN_COUNT do
		local coin = coins[i]
		if not coin then
			local frame = Widgets.coin(26, root)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Visible = false
			coin = { frame = frame, x = 0.5, y = 0.8, vx = 0, vy = 0, age = 0, delay = 0 }
			coins[i] = coin
		end
		coin.x, coin.y = 0.5, 0.78
		coin.vx = rng:NextNumber(-0.45, 0.45)
		coin.vy = rng:NextNumber(-1.55, -1.05)
		coin.age = 0
		coin.delay = (i - 1) * 0.025
		coin.frame.Visible = false
		coin.frame.Position = UDim2.fromScale(coin.x, coin.y)
	end
end

local function stepCoins(dt: number)
	for _, coin in coins do
		if coin.delay > 0 then
			coin.delay -= dt
			continue
		end
		if coin.age >= COIN_LIFE then
			coin.frame.Visible = false
			continue
		end
		coin.age += dt
		coin.vy += GRAVITY * dt
		coin.x += coin.vx * dt
		coin.y += coin.vy * dt
		coin.frame.Visible = coin.age < COIN_LIFE
		coin.frame.Position = UDim2.fromScale(coin.x, coin.y)
		coin.frame.Rotation = coin.age * 360
	end
end

function Panel.build(parent: Frame)
	if built then
		return
	end
	built = true
	fountain = Create("Frame", {
		Name = "Fountain",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = parent,
	}) :: Frame
	title = Widgets.label({
		name = "Title",
		size = UDim2.new(1, -16, 0.2, 0),
		position = UDim2.fromScale(0.5, 0.04),
		anchor = Vector2.new(0.5, 0),
		maxSize = 30,
		parent = parent,
	})
	amount = Widgets.label({
		name = "Amount",
		size = UDim2.new(1, -16, 0.3, 0),
		position = UDim2.fromScale(0.5, 0.26),
		anchor = Vector2.new(0.5, 0),
		color = Theme.Colors.Gold,
		font = Widgets.STAMP_FONT,
		maxSize = 64,
		parent = parent,
	})
	nightShift = Widgets.label({
		name = "NightShift",
		size = UDim2.new(1, -16, 0, 26),
		position = UDim2.new(0.5, 0, 1, -112),
		anchor = Vector2.new(0.5, 0),
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 16,
		parent = parent,
	})
	okButton = Widgets.button({
		name = "Ok",
		size = UDim2.fromOffset(260, 96), -- bouton principal 96 px (§7.2)
		position = UDim2.new(0.5, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		color = Theme.Colors.Success,
		maxText = 34,
		parent = parent,
		onClick = function()
			PanelController.close()
		end,
	})
	Prefs.LanguageChanged:Connect(render)
	State.Changed:Connect(function(key: string)
		if key == "passes" and isOpen then
			render()
		end
	end)
	render()
end

function Panel.onOpen(args: any?)
	isOpen = true
	local payload = if type(args) == "table" and type(args.data) == "table" then args.data else nil
	if payload then
		data = {
			glow = math.floor(finite(payload.glow)),
			seconds = math.floor(finite(payload.seconds)),
			nightShift = payload.nightShift == true,
		}
	end
	render()
	if Juice.reducedMotion() then
		countTime = COUNT_TIME
		render()
	else
		countTime = 0
		if amount then
			amount.Text = amountText(0)
		end
	end
	launchCoins()
	AudioController.play("Coin")
end

function Panel.onClose()
	isOpen = false
	countTime = math.huge
	for _, coin in coins do
		coin.frame.Visible = false
		coin.age = COIN_LIFE
	end
end

function Panel.hasAction(): boolean
	return false
end

-- Compteur Quint Out et fontaine de pièces
function Panel.step(dt: number)
	if not built or not isOpen then
		return
	end
	if countTime < COUNT_TIME then
		countTime += dt
		local alpha = math.min(1, countTime / COUNT_TIME)
		local eased = 1 - (1 - alpha) ^ 5
		if amount then
			amount.Text = amountText(data.glow * eased)
		end
		if alpha >= 1 then
			if amount then
				Juice.pulse(amount, 1.12)
			end
			AudioController.play("Reward")
		end
	end
	stepCoins(dt)
end

function Panel.defaultSelection(): GuiObject?
	return okButton
end

-- Ouvre l'écran avec les données de Celebrate "offline"
function Panel.present(payload: { [string]: any })
	if type(payload) ~= "table" then
		return
	end
	PanelController.open("ReturnScreen", { data = payload })
end

-- Exposé pour les tests
Panel._data = function()
	return data
end
Panel._amount = function(): TextLabel?
	return amount
end
Panel._nightShift = function(): TextLabel?
	return nightShift
end

return Panel
