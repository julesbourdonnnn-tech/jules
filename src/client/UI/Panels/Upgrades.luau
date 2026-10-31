--!strict
-- Panels/Upgrades — paquet « client-panels » (docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * 5 cartes (Conga, Foulée, Attrait, Perchoirs, Guard Links) : icône, niveau, effet actuel →
--     suivant, prix (Formulas.upgradeCost), bouton Acheter 96 px → remote BuyUpgrade(track) ;
--     la carte achetable la moins chère pulse (UIScale 1 → 1,08, sinus 0,8 s) ; MAX au plafond
--     (Formulas.upgradeMaxLevel)
--   * prix et disponibilité calculés sur le Glow PRÉDIT ; refus : secousse ±6 px + contour rouge
--     + toast « Il manque … Glow » (le serveur reste seul juge : Feedback notEnoughGlow)
--   * barre de stat remplie en 0,3 s et niveau qui défile à la confirmation (profil répliqué)
--   * accueil : args.focus = "conga" → une seule carte en surbrillance, fermeture auto 0,6 s après
--     l'achat
--   * quêtes d'accueil d'achat (Q2/Q5 « upgrade » → goal.track, Q7 « perches ») lues dans le profil
--     répliqué (onboarding.step) : la carte de la quête a le contour doré et elle seule pulse (quand
--     elle est payable) — jamais une autre carte moins chère qui ferait dépenser le Glow de la quête
--   * bouton Supernova en bas avec anneau de progression (Glow prédit / Formulas.supernovaCost(R))
--     → PanelController.open("Supernova")
--   * hasAction : une amélioration est achetable, ou la Supernova (son bouton vit dans ce panneau)
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Widgets (press, Selectable) ; intentions seulement (le serveur valide tout)
-- GDD : §4.11, §3 (18-22 s), §9.2, §9.4 (Amélioration), §10.3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Formulas = require(Shared.Logic.Formulas)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Quests = require(Shared.Config.Quests)
local Types = require(Shared.Types)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)
local Prefs = require(Client.Util.Prefs)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local Toast = require(Client.UI.Toast)
local PanelController = require(Client.Controllers.PanelController)
local Model = require(script.Parent.Model)
local Widgets = require(script.Parent.Widgets)

local Panel = {}

Panel.name = "Upgrades" :: Types.PanelName
Panel.tabs = nil :: { string }?

-- Icônes (grands glyphes, §10.1) et couleurs d'accent par piste
local ICONS: { [string]: string } = {
	conga = "🐾",
	stride = "👟",
	lure = "🧲",
	perches = "🏡",
	guard = "🛡",
}
local ACCENTS: { [string]: Color3 } = {
	conga = Theme.Colors.Primary,
	stride = Theme.Colors.Success,
	lure = Theme.Colors.Premium,
	perches = Theme.Colors.Gold,
	guard = Widgets.CYAN,
}

local CARD_HEIGHT = 112
local BUY_SIZE = Vector2.new(184, 96) -- bouton principal 96 px (§10.1)
local SUPERNOVA_HEIGHT = 100
local PULSE_PERIOD, PULSE_AMOUNT = 0.8, 0.08
local FOCUS_CLOSE_DELAY = 0.6
local REFRESH_INTERVAL = 0.25
-- Objectifs d'accueil liés à une piste sans `goal.track` (Q7 « Atteins 10 perchoirs »)
local QUEST_KIND_TRACK: { [string]: string } = { perches = "perches" }

type CardRefs = {
	holder: Frame,
	pulse: UIScale,
	visual: Frame,
	name: TextLabel,
	desc: TextLabel,
	effect: TextLabel,
	level: TextLabel,
	bar: Frame,
	buy: TextButton,
	buyLabel: TextLabel,
	coin: Frame,
}

local view = Model.view(State.get)
local built = false
local isOpen = false
local cards: { [string]: CardRefs } = {}
local supernovaButton: TextButton? = nil
local supernovaTitle: TextLabel? = nil
local supernovaProgress: TextLabel? = nil
local supernovaRing: Widgets.Ring? = nil
local list: ScrollingFrame? = nil
local levels: { [string]: number } = {}
local focus: string? = nil
local focusLevel = 0
local focusToken = 0
local pulsing: string? = nil
local questMark: string? = nil -- carte de la quête d'accueil en cours (contour doré)
local pulseClock = 0
local reducedMark: string? = nil -- carte au contour doré fixe (Mouvement réduit)
local refreshAcc = 0

local function levelText(level: number): string
	return Prefs.t("common.level", { level = math.floor(level) })
end

local function effectText(track: string, from: number, to: number): string
	local function fmt(x: number): string
		-- 16.5 → « 16.5 » (« 16,5 » en français)
		local s = if x % 1 == 0 then tostring(math.floor(x)) else string.format("%.1f", x)
		if Prefs.language() == "fr" then
			s = string.gsub(s, "%.", ",")
		end
		return s
	end
	return Prefs.t(`upgrades.{track}.effect`, { from = fmt(from), to = fmt(to) })
end

-- Piste visée par la quête d'accueil en cours (Q2/Q5 : goal.track ; Q7 : perchoirs), nil hors
-- quête d'achat, objectif déjà atteint (réplication en deux temps) ou piste au plafond
local function questTrack(): string?
	local def = Quests.Onboarding[Model.onboardingStep(view)]
	if def == nil then
		return nil
	end
	local goal = def.goal
	local track = if goal.kind == "upgrade" then goal.track else QUEST_KIND_TRACK[goal.kind]
	if track == nil or Balance.Upgrades[track] == nil then
		return nil
	end
	local reached = if goal.kind == "perches"
		then Model.perchCount(view) >= goal.n
		else Model.upgradeLevel(view, track) >= goal.n
	if reached or Model.upgradeInfo(view, track).maxed then
		return nil
	end
	return track
end

-- ---------------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------------

-- Achat : intention envoyée seulement si le Glow prédit suffit ; sinon refus local et toast
-- « Il manque … Glow ». `refused` : le bouton (désactivé) a déjà joué la secousse.
local function onBuy(track: string, refused: boolean?)
	local info = Model.upgradeInfo(view, track)
	local card = cards[track]
	if info.maxed then
		if card and not refused then
			Widgets.refuse(card.buy)
		end
		return
	end
	local glow = Model.predictedGlow(view, Clock.now())
	if glow < info.cost then
		if card and not refused then
			Widgets.refuse(card.buy)
		end
		Toast.show(Prefs.t("feedback.notEnoughGlow", { missing = Prefs.number(info.cost - glow) }), "error")
		return
	end
	Net.event("BuyUpgrade"):FireServer(track)
end

local function buildCard(track: string, order: number, parent: Instance): CardRefs
	local pulse = Create("UIScale", { Name = "PulseScale", Scale = 1 })
	local holder = Create("Frame", {
		Name = "Card_" .. track,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, CARD_HEIGHT),
		LayoutOrder = order,
		Parent = parent,
	}, { pulse }) :: Frame
	local visual = Widgets.card({ name = "Visual", size = UDim2.fromScale(1, 1), parent = holder })
	local icon = Create("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(76, 76),
		BackgroundColor3 = ACCENTS[track] or Theme.Colors.Primary,
		Parent = visual,
	}, { Widgets.round(), Widgets.stroke(), Widgets.gradient() })
	Widgets.label({
		name = "Glyph",
		text = ICONS[track] or "★",
		size = UDim2.fromScale(0.7, 0.7),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxSize = 44,
		zIndex = 3,
		parent = icon,
	})
	local textX = 100
	local textW = -(textX + BUY_SIZE.X + 24)
	local name = Widgets.label({
		name = "Name",
		size = UDim2.new(0.45, textW * 0.45, 0, 34),
		position = UDim2.fromOffset(textX, 8),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 28,
		parent = visual,
	})
	local desc = Widgets.label({
		name = "Desc",
		size = UDim2.new(0.55, textW * 0.55, 0, 26),
		position = UDim2.new(0.45, textX + textW * 0.45 + 6, 0, 12),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 18,
		parent = visual,
	})
	local effect = Widgets.label({
		name = "Effect",
		size = UDim2.new(1, textW, 0, 28),
		position = UDim2.fromOffset(textX, 44),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 22,
		parent = visual,
	})
	local level = Widgets.label({
		name = "Level",
		size = UDim2.fromOffset(84, 26),
		position = UDim2.fromOffset(textX, 76),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 20,
		parent = visual,
	})
	local bar = Widgets.bar({
		name = "LevelBar",
		size = UDim2.new(1, textW - 92, 0, 12),
		position = UDim2.fromOffset(textX + 92, 83),
		color = ACCENTS[track],
		parent = visual,
	})
	local buy, buyLabel = Widgets.button({
		name = "Buy",
		size = UDim2.fromOffset(BUY_SIZE.X, BUY_SIZE.Y),
		position = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.Success,
		maxText = 30,
		parent = visual,
		sound = "",
		onClick = function()
			onBuy(track)
		end,
		onRefused = function()
			onBuy(track, true)
		end,
	})
	buyLabel.Size = UDim2.new(1, -60, 1, -10)
	buyLabel.Position = UDim2.new(0.5, 22, 0.5, 0)
	local coin = Widgets.coin(32, buy)
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 14, 0.5, 0)
	coin.ZIndex = 3
	return {
		holder = holder,
		pulse = pulse,
		visual = visual,
		name = name,
		desc = desc,
		effect = effect,
		level = level,
		bar = bar,
		buy = buy,
		buyLabel = buyLabel,
		coin = coin,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------------------------

local function renderSupernova(glow: number)
	local cost = Formulas.supernovaCost(Model.supernovas(view))
	if supernovaTitle then
		supernovaTitle.Text = Prefs.t("upgrades.supernova")
	end
	if supernovaProgress then
		supernovaProgress.Text = Prefs.t(
			"upgrades.supernovaProgress",
			{ glow = Prefs.number(math.min(glow, cost)), cost = Prefs.number(cost) }
		)
	end
	if supernovaRing then
		Widgets.setRing(supernovaRing, if cost > 0 then glow / cost else 0)
	end
	if supernovaButton then
		Widgets.highlight(supernovaButton, glow >= cost, Theme.Colors.Gold)
		supernovaButton.Visible = focus == nil
	end
end

local function render(animate: boolean?)
	if not built then
		return
	end
	local now = Clock.now()
	local glow = Model.predictedGlow(view, now)
	-- accueil : la carte de la quête d'achat en cours (la carte unique `focus` reste prioritaire)
	local quest = if focus == nil then questTrack() else nil
	questMark = quest
	local questAffordable = false
	for _, track in Balance.UpgradeOrder do
		local card = cards[track]
		if card then
			local info = Model.upgradeInfo(view, track)
			local old = levels[track]
			card.name.Text = Prefs.t(`upgrades.{track}.name`)
			card.desc.Text = Prefs.t(`upgrades.{track}.desc`)
			card.effect.Text = if info.maxed
				then effectText(track, info.from, info.from)
				else effectText(track, info.from, info.to)
			local ratio = if info.max > 0 then info.level / info.max else 1
			if animate and old ~= nil and info.level > old then
				-- confirmation serveur : barre 0,3 s Quad Out, niveau qui défile, pop de la carte
				Widgets.setBar(card.bar, ratio, true)
				Juice.countTo(card.level, old, info.level, 0.3, levelText)
				Juice.pulse(card.visual, 1.06)
			else
				Widgets.setBar(card.bar, ratio, false)
				card.level.Text = levelText(info.level)
			end
			levels[track] = info.level
			if info.maxed then
				card.buyLabel.Text = Prefs.t("common.max")
				card.coin.Visible = false
				Widgets.setColor(card.buy, Widgets.DIM)
				Widgets.setEnabled(card.buy, false)
			else
				card.buyLabel.Text = Prefs.number(info.cost)
				card.coin.Visible = true
				local affordable = glow >= info.cost
				Widgets.setColor(card.buy, if affordable then Theme.Colors.Success else Widgets.DIM)
				Widgets.setEnabled(card.buy, affordable)
				if track == quest then
					questAffordable = affordable
				end
			end
			-- accueil : une seule carte (focus) ou la carte de la quête, en surbrillance
			card.holder.Visible = focus == nil or focus == track
			local marked = focus == track or (focus == nil and (quest == track or reducedMark == track))
			Widgets.highlight(card.visual, marked, Theme.Colors.Gold)
		end
	end
	renderSupernova(glow)
	-- pendant une quête d'achat, seule sa carte pulse (et seulement si elle est payable) : la carte
	-- la moins chère ferait dépenser le Glow prévu pour la quête (§3)
	if focus then
		pulsing = focus
	elseif quest then
		pulsing = if questAffordable then quest else nil
	else
		pulsing = Model.cheapestAffordable(view, now)
	end
end

local function onUpgradesChanged()
	if not built then
		return
	end
	local focused = focus
	if focused and isOpen and Model.upgradeLevel(view, focused) > focusLevel then
		-- accueil : le panneau se ferme seul 0,6 s après l'achat (§3)
		focusToken += 1
		local token = focusToken
		task.delay(FOCUS_CLOSE_DELAY, function()
			if token == focusToken and isOpen and PanelController.current() == "Upgrades" then
				PanelController.close()
			end
		end)
	end
	render(true)
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
		Size = UDim2.new(1, 0, 1, -(SUPERNOVA_HEIGHT + 8)),
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Selectable = false,
		Parent = parent,
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 8),
		Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }),
	}) :: ScrollingFrame
	list = scroll
	for i, track in Balance.UpgradeOrder do
		cards[track] = buildCard(track, i, scroll)
	end
	local button, label = Widgets.button({
		name = "SupernovaButton",
		size = UDim2.new(1, -12, 0, SUPERNOVA_HEIGHT),
		position = UDim2.new(0.5, 0, 1, 0),
		anchor = Vector2.new(0.5, 1),
		color = Theme.Colors.Premium,
		maxText = 34,
		parent = parent,
		onClick = function()
			PanelController.open("Supernova")
		end,
	})
	supernovaButton = button
	label.Size = UDim2.new(1, -120, 0.55, 0)
	label.Position = UDim2.new(0, 110, 0.06, 0)
	label.AnchorPoint = Vector2.zero
	label.FontFace = Widgets.STAMP_FONT
	label.TextXAlignment = Enum.TextXAlignment.Left
	supernovaTitle = label
	supernovaProgress = Widgets.label({
		name = "Progress",
		size = UDim2.new(1, -120, 0.34, 0),
		position = UDim2.new(0, 110, 0.6, 0),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 24,
		zIndex = 3,
		parent = button,
	})
	local ring = Widgets.ring("Ring", 80, 24, Theme.Colors.Gold, nil, button)
	ring.frame.AnchorPoint = Vector2.new(0, 0.5)
	ring.frame.Position = UDim2.new(0, 14, 0.5, 0)
	Widgets.label({
		name = "Star",
		text = "✺",
		size = UDim2.fromScale(0.6, 0.6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.Gold,
		maxSize = 40,
		zIndex = 3,
		parent = ring.frame,
	})
	supernovaRing = ring

	State.Changed:Connect(function(key: string)
		if key == "upgrades" then
			onUpgradesChanged()
		elseif
			isOpen
			and (
				key == "glow"
				or key == "supernovas"
				or key == "atlas"
				or key == "passes"
				or key == "idleRate"
				or key == "onboarding"
			)
		then
			render(false)
		end
	end)
	Prefs.LanguageChanged:Connect(function()
		render(false)
	end)
	render(false)
end

function Panel.onOpen(args: any?)
	isOpen = true
	focusToken += 1
	local wanted = if type(args) == "table" then args.focus else nil
	if type(wanted) == "string" and Balance.Upgrades[wanted] ~= nil then
		focus = wanted
		focusLevel = Model.upgradeLevel(view, wanted)
	else
		focus = nil
	end
	levels = {}
	render(false)
	if list then
		list.CanvasPosition = Vector2.zero
	end
end

function Panel.onClose()
	isOpen = false
	focus = nil
	focusToken += 1
	for _, card in cards do
		card.pulse.Scale = 1
	end
end

function Panel.hasAction(): boolean
	local now = Clock.now()
	if #Model.affordableUpgrades(view, now) > 0 then
		return true
	end
	-- pistes au plafond : la Supernova payable reste une action de ce panneau (§10.2 « ! »)
	return Model.predictedGlow(view, now) >= Formulas.supernovaCost(Model.supernovas(view))
end

-- Chaque image tant que le panneau est ouvert : Glow prédit (achetable ?) et pulsation
function Panel.step(dt: number)
	if not built then
		return
	end
	refreshAcc += dt
	if refreshAcc >= REFRESH_INTERVAL then
		refreshAcc = 0
		render(false)
	end
	pulseClock += dt
	local reduced = Juice.reducedMotion()
	for track, card in cards do
		local on = track == pulsing
		if on and not reduced then
			card.pulse.Scale = 1
				+ PULSE_AMOUNT / 2
				+ PULSE_AMOUNT / 2 * math.sin(pulseClock * 2 * math.pi / PULSE_PERIOD)
		elseif card.pulse.Scale ~= 1 then
			card.pulse.Scale = 1
		end
	end
	-- Mouvement réduit : contour doré fixe au lieu de la pulsation (écrit seulement au changement)
	local mark = if focus == nil and reduced then pulsing else nil
	if mark ~= reducedMark then
		local previous = if reducedMark then cards[reducedMark] else nil
		-- la carte de quête garde son contour doré (posé par render)
		if previous and focus == nil and reducedMark ~= questMark then
			Widgets.highlight(previous.visual, false, Theme.Colors.Gold)
		end
		local card = if mark then cards[mark] else nil
		if card then
			Widgets.highlight(card.visual, true, Theme.Colors.Gold)
		end
		reducedMark = mark
	end
end

function Panel.defaultSelection(): GuiObject?
	local track = pulsing or questMark or Balance.UpgradeOrder[1]
	local card = cards[track]
	return if card then card.buy else nil
end

-- Exposé pour les tests
Panel._cards = cards
Panel._focus = function(): string?
	return focus
end
Panel._pulsing = function(): string?
	return pulsing
end
Panel._quest = function(): string?
	return questMark
end

return Panel
