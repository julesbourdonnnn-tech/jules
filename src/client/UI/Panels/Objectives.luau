--!strict
-- Objectives (paquet client-panels) : panneau Objectifs (GDD §7.3, §7.4, §3 ; docs/04 §13.6) :
--   * Aujourd'hui : 3 objectifs (facile, moyen, difficile) avec progression, récompense en minutes de
--     revenu, « Réclamer » (ClaimObjective) quand c'est fait, relance gratuite (RerollObjective,
--     1 par jour, seulement sur un objectif pas encore fait), « Les 3 faits : Goutte chanceuse ! » ;
--   * Plop : jours au total (jamais une série), repas du jour, paliers (Config/Quests.Feed) ;
--   * Accueil : étapes de l'accueil, tant qu'il n'est pas fini.
-- UiSeen("objectives") à la première ouverture (étape 10 de l'accueil, côté serveur). Sélection par
-- défaut : un « Réclamer » disponible, sinon la 1re carte. Un bouton refusé ne part jamais au serveur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Quests = require(Shared.Config.Quests)
local Layout = require(Shared.Config.Layout)
local Clock = require(Shared.Util.Clock)

local Widgets = require(script.Parent.Widgets)
local Format = require(script.Parent.Parent.Format)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }
type Card = {
	frame: Frame,
	tier: TextLabel,
	text: TextLabel,
	bar: Frame,
	fill: Frame,
	progress: TextLabel,
	reward: TextLabel,
	action: TextButton,
	mode: string, -- "claim" | "reroll" | "claimed" | "noReroll" | "empty"
}

local Objectives = {}

local ALL_TABS = { "today", "plop", "onboarding" }
local TIER_COLORS = {
	easy = Color3.fromRGB(120, 220, 160),
	medium = Color3.fromRGB(255, 200, 90),
	hard = Color3.fromRGB(255, 120, 150),
}

local nav: Nav? = nil
local tabBar: Widgets.TabBar? = nil
local current = "today"
local isOpen = false
local pages: { [string]: Frame } = {}
local cards: { Card } = {}
local allDone: TextLabel? = nil
local plopTotal: TextLabel? = nil
local plopToday: TextLabel? = nil
local plopCells: { TextButton } = {}
local stepCells: { TextButton } = {}

local DEFS: { [number]: Quests.ObjectiveDef } = {}
for _, def in Quests.Objectives do
	DEFS[def.id] = def
end

local function objectivesState(): { [string]: any }
	return Widgets.tbl(Widgets.state("objectives"))
end

local function onboardingDone(): boolean
	local o = Widgets.tbl(Widgets.state("onboarding"))
	return o.done == true
end

local function visibleTabs(): { string }
	local out = {}
	for _, id in ALL_TABS do
		if id ~= "onboarding" or not onboardingDone() then
			table.insert(out, id)
		end
	end
	return out
end

local function rerollsLeft(): number
	local o = objectivesState()
	return math.max(0, Quests.ObjectiveRules.RerollsPerDay - Widgets.n(o.rerolls))
end

local function refreshToday()
	local o = objectivesState()
	local list = Widgets.tbl(o.list)
	local claimedAll = true
	for slot, card in cards do
		local e = list[slot]
		local def = if type(e) == "table" and type(e.id) == "number" then DEFS[e.id] else nil
		if def == nil then
			card.mode = "empty"
			card.frame.Visible = false
			claimedAll = false
		else
			card.frame.Visible = true
			local entry = e :: any
			local goal = def.goal
			local p = math.clamp(Widgets.n(entry.p), 0, goal)
			local done = entry.done == true
			local claimed = entry.claimed == true
			if not claimed then
				claimedAll = false
			end
			Widgets.setText(card.tier, "panel.goals." .. def.tier)
			card.tier.TextColor3 = TIER_COLORS[def.tier] or Widgets.Colors.Text
			Widgets.setText(card.text, "objective." .. Format.id(def.id), { goal = goal })
			Widgets.setText(card.progress, "panel.goals.progress", { p = math.floor(p), goal = goal })
			card.fill.Size = UDim2.fromScale(if goal > 0 then p / goal else 1, 1)
			local reward = Quests.ObjectiveRules.Rewards[def.tier]
			Widgets.setText(card.reward, "panel.goals.reward.coins", {
				n = math.floor((if reward then reward.incomeSeconds else 0) / 60),
			})
			local label = Widgets.buttonLabel(card.action) :: TextLabel
			if claimed then
				card.mode = "claimed"
				Widgets.setText(label, "panel.goals.claimed")
				Widgets.setDisabled(card.action, true)
			elseif done then
				card.mode = "claim"
				Widgets.setText(label, "common.claim")
				Widgets.setDisabled(card.action, false)
			elseif rerollsLeft() > 0 then
				card.mode = "reroll"
				Widgets.setText(label, "panel.goals.reroll")
				Widgets.setDisabled(card.action, false)
			else
				card.mode = "noReroll"
				Widgets.setText(label, "panel.goals.rerollUsed")
				Widgets.setDisabled(card.action, true)
			end
			card.action.BackgroundColor3 = if card.mode == "claim"
				then Widgets.Colors.Success
				else Widgets.Colors.CardLight
			Widgets.attention(card.action, card.mode == "claim")
		end
	end
	if allDone then
		allDone.Visible = claimedAll and #list > 0
	end
end

-- Case vive (palier atteint : vert ; prochain palier : bleu) : ses textes passent en bleu nuit sans
-- contour. « Jour 1 » or, récompense blanche et ✓ vert s'y lisaient à 1,2, 1,8 et 1,0 de contraste
-- sans le contour (le ✓ vert sur vert n'était qu'un contour ; revue des écrans). Case sombre :
-- couleur d'origine de chaque texte et contour
local baseColors: { [TextLabel]: Color3 } = setmetatable({}, { __mode = "k" }) :: any
local function paintVivid(cell: GuiObject, vivid: boolean)
	for _, child in cell:GetChildren() do
		if child:IsA("TextLabel") then
			local base = baseColors[child]
			if base == nil then
				base = child.TextColor3
				baseColors[child] = base
			end
			child.TextColor3 = if vivid then Widgets.Colors.Stroke else base
			local stroke = child:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = not vivid
			end
		end
	end
end

local function refreshPlop()
	local days = math.max(0, math.floor(Widgets.n(Widgets.state("plopDays"))))
	if plopTotal then
		Widgets.setText(plopTotal, "panel.goals.plop.total", { n = days })
	end
	if plopToday then
		local fed = Widgets.n(Widgets.state("lastFeedDay")) == Clock.day()
		Widgets.setText(
			plopToday,
			if fed then "panel.goals.plop.fedToday" else "panel.goals.plop.feedToday",
			{
				name = Widgets.speciesName(1),
			}
		)
	end
	local nextShown = false
	for i, cell in plopCells do
		local m = Quests.Feed.Milestones[i]
		local reached = days >= m.day
		local isNext = not reached and not nextShown
		if isNext then
			nextShown = true
		end
		-- palier atteint : vert et ✓ ; prochain palier : couleur d'accent qui pulse doucement
		cell.BackgroundColor3 = if reached
			then Widgets.Colors.Success
			elseif isNext then Widgets.Colors.Accent
			else Widgets.Colors.Card
		paintVivid(cell, reached or isNext)
		Widgets.attention(cell, isNext)
		local status = cell:FindFirstChild("Status") :: TextLabel
		Widgets.setRaw(status, if reached then "✓" else "")
	end
end

local function refreshOnboarding()
	local step = Widgets.n(Widgets.tbl(Widgets.state("onboarding")).step)
	for i, cell in stepCells do
		local s = Quests.Onboarding.Steps[i]
		local done = step >= s.step
		cell.BackgroundColor3 = if done then Widgets.Colors.Success else Widgets.Colors.Card
		paintVivid(cell, done)
		local status = cell:FindFirstChild("Status") :: TextLabel
		Widgets.setRaw(status, if done then "✓" else "")
	end
end

local function showPage(id: string)
	for name, page in pages do
		page.Visible = name == id
	end
	if tabBar then
		local tabs = visibleTabs()
		for _, tabId in ALL_TABS do
			tabBar.setVisible(tabId, table.find(tabs, tabId) ~= nil)
		end
		tabBar.setActive(id)
	end
end

local function refresh()
	if not table.find(visibleTabs(), current) then
		current = "today"
	end
	showPage(current)
	refreshToday()
	refreshPlop()
	refreshOnboarding()
end

local function onAction(slot: number)
	local card = cards[slot]
	if card == nil then
		return
	end
	if card.mode == "claim" then
		Widgets.send("ClaimObjective", slot)
	elseif card.mode == "reroll" then
		Widgets.send("RerollObjective", slot)
	end
end

local function buildToday(page: Frame)
	local width = page.Size.X.Offset
	local gap = Layout.Spacing.Normal
	local cardW = math.floor((width - 96 - 2 * gap) / 3)
	local cardH = 480
	for slot = 1, 3 do
		local f = Widgets.frame({
			parent = page,
			name = "Card" .. slot,
			size = UDim2.fromOffset(cardW, cardH),
			position = UDim2.fromOffset(48 + (slot - 1) * (cardW + gap), 16),
			color = Widgets.Colors.Card,
			gradient = true,
		})
		local tier = Widgets.label({
			parent = f,
			name = "Tier",
			size = UDim2.new(1, -32, 0, 44),
			position = UDim2.fromOffset(16, 12),
			textSize = 36,
		})
		local text = Widgets.label({
			parent = f,
			name = "Text",
			size = UDim2.new(1, -32, 0, 140),
			position = UDim2.fromOffset(16, 64),
			textSize = 36,
			wrapped = true,
		})
		local bar = Widgets.frame({
			parent = f,
			name = "Bar",
			size = UDim2.new(1, -48, 0, 28),
			position = UDim2.fromOffset(24, 220),
			color = Widgets.Colors.Locked,
			corner = UDim.new(0.5, 0),
		})
		local fill = Widgets.frame({
			parent = bar,
			name = "Fill",
			size = UDim2.fromScale(0, 1),
			color = Widgets.Colors.Success,
			corner = UDim.new(0.5, 0),
			stroke = false,
		})
		local progress = Widgets.label({
			parent = f,
			name = "Progress",
			size = UDim2.new(1, -32, 0, 40),
			position = UDim2.fromOffset(16, 256),
			textSize = 32,
		})
		local reward = Widgets.label({
			parent = f,
			name = "Reward",
			size = UDim2.new(1, -32, 0, 40),
			position = UDim2.fromOffset(16, 304),
			textSize = 32,
			color = Widgets.Colors.Gold,
		})
		local action = Widgets.button({
			parent = f,
			name = "Action",
			size = UDim2.new(1, -48, 0, Layout.Button.MainHeight),
			position = UDim2.new(0.5, 0, 1, -24),
			anchor = Vector2.new(0.5, 1),
			text = "",
			textSize = 40,
			onActivate = function()
				onAction(slot)
			end,
		})
		cards[slot] = {
			frame = f,
			tier = tier,
			text = text,
			bar = bar,
			fill = fill,
			progress = progress,
			reward = reward,
			action = action,
			mode = "empty",
		}
	end
	allDone = Widgets.label({
		parent = page,
		name = "AllDone",
		size = UDim2.new(1, -96, 0, 56),
		position = UDim2.fromOffset(48, 16 + cardH + 24),
		key = "panel.goals.allDone",
		textSize = 40,
		color = Widgets.Colors.Gold,
	})
end

-- Grille de cases d'information (sélectionnables pour la croix ; ✕ ne fait rien)
local function infoGrid(
	page: Frame,
	top: number,
	count: number,
	fill: (cell: TextButton, i: number) -> ()
): { TextButton }
	local cols = Layout.Panel.columns
	local cell = Layout.Panel.cell
	local gap = Layout.Spacing.Min
	local width = page.Size.X.Offset
	local totalW = cols * cell.w + (cols - 1) * gap
	local left = math.floor((width - totalW) / 2)
	local out: { TextButton } = {}
	for i = 1, count do
		local col = (i - 1) % cols
		local line = (i - 1) // cols
		-- ancrée au centre : la pulsation du prochain palier (1 → 1,08, GDD §9.2) et le grossissement de la
		-- sélection débordent également des deux côtés, jamais sur la case voisine (écart de 16 px)
		local h = cell.h - 24
		local b = Widgets.button({
			parent = page,
			name = "Cell" .. i,
			size = UDim2.fromOffset(cell.w, h),
			position = UDim2.fromOffset(
				left + col * (cell.w + gap) + math.floor(cell.w / 2),
				top + line * (h + gap) + math.floor(h / 2)
			),
			anchor = Vector2.new(0.5, 0.5),
			color = Widgets.Colors.Card,
			sound = "",
		})
		fill(b, i)
		out[i] = b
	end
	return out
end

local function buildPlop(page: Frame)
	local width = page.Size.X.Offset
	plopTotal = Widgets.label({
		parent = page,
		name = "Total",
		size = UDim2.fromOffset(width - 96, 48),
		position = UDim2.fromOffset(48, 8),
		textSize = 40,
		color = Widgets.Colors.Gold,
	})
	plopToday = Widgets.label({
		parent = page,
		name = "Today",
		size = UDim2.fromOffset(width - 96, 40),
		position = UDim2.fromOffset(48, 60),
		textSize = 32,
	})
	plopCells = infoGrid(page, 112, #Quests.Feed.Milestones, function(cell: TextButton, i: number)
		local m = Quests.Feed.Milestones[i]
		Widgets.label({
			parent = cell,
			name = "Day",
			size = UDim2.new(1, -16, 0, 40),
			position = UDim2.fromOffset(8, 8),
			key = "panel.goals.plop.day",
			vars = { n = m.day },
			textSize = 32,
			color = Widgets.Colors.Gold,
			zIndex = cell.ZIndex + 1,
		})
		Widgets.label({
			parent = cell,
			name = "Reward",
			size = UDim2.new(1, -16, 0, 96),
			position = UDim2.fromOffset(8, 52),
			key = "plop.reward." .. m.key,
			textSize = 28,
			wrapped = true,
			zIndex = cell.ZIndex + 1,
		})
		Widgets.label({
			parent = cell,
			name = "Status",
			size = UDim2.new(1, -16, 0, 36),
			position = UDim2.new(0, 8, 1, -8),
			anchor = Vector2.new(0, 1),
			text = "",
			textSize = 28,
			color = Widgets.Colors.Success,
			zIndex = cell.ZIndex + 1,
		})
	end)
end

local function buildOnboarding(page: Frame)
	stepCells = infoGrid(page, 16, #Quests.Onboarding.Steps, function(cell: TextButton, i: number)
		local s = Quests.Onboarding.Steps[i]
		Widgets.label({
			parent = cell,
			name = "Step",
			size = UDim2.new(1, -16, 0, 40),
			position = UDim2.fromOffset(8, 8),
			text = Format.count(s.step),
			textSize = 32,
			color = Widgets.Colors.Gold,
			zIndex = cell.ZIndex + 1,
		})
		Widgets.label({
			parent = cell,
			name = "Name",
			size = UDim2.new(1, -16, 0, 96),
			position = UDim2.fromOffset(8, 52),
			key = "onboarding.step." .. s.key,
			textSize = 28,
			wrapped = true,
			zIndex = cell.ZIndex + 1,
		})
		Widgets.label({
			parent = cell,
			name = "Status",
			size = UDim2.new(1, -16, 0, 36),
			position = UDim2.new(0, 8, 1, -8),
			anchor = Vector2.new(0, 1),
			text = "",
			textSize = 28,
			color = Widgets.Colors.Success,
			zIndex = cell.ZIndex + 1,
		})
	end)
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Objectives.build(container: Frame)
	local specs = {}
	for _, id in ALL_TABS do
		table.insert(specs, { id = id, key = "panel.goals.tab." .. id })
	end
	tabBar = Widgets.tabBar(container, specs, function(id: string)
		Objectives.setTab(id)
	end)
	local top = Layout.Panel.tabHeight + 24
	for _, id in ALL_TABS do
		local page = Widgets.group(
			container,
			"Page_" .. id,
			UDim2.fromOffset(container.Size.X.Offset, container.Size.Y.Offset - top),
			UDim2.fromOffset(0, top)
		)
		page.Visible = false
		pages[id] = page
	end
	buildToday(pages.today)
	buildPlop(pages.plop)
	buildOnboarding(pages.onboarding)
	Widgets.watch({ "objectives", "plopDays", "lastFeedDay", "onboarding" }, function()
		if isOpen then
			refresh()
		end
	end)
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Objectives.open(tab: string?)
	isOpen = true
	Widgets.seen("objectives")
	if type(tab) == "string" and table.find(visibleTabs(), tab) then
		current = tab
	end
	refresh()
end

-- Cache le panneau
function Objectives.close()
	isOpen = false
end

-- Onglets, dans l'ordre (L1 / R1)
function Objectives.tabs(): { string }
	return visibleTabs()
end

-- Change d'onglet
function Objectives.setTab(tab: string)
	if type(tab) ~= "string" or not table.find(visibleTabs(), tab) then
		return
	end
	current = tab
	refresh()
end

function Objectives.currentTab(): string
	return current
end

-- Sélection par défaut : « Réclamer » disponible, sinon la 1re carte
function Objectives.defaultSelection(): GuiObject?
	if current == "today" then
		for _, card in cards do
			if card.mode == "claim" and card.frame.Visible then
				return card.action
			end
		end
		for _, card in cards do
			if card.frame.Visible then
				return card.action
			end
		end
	elseif current == "plop" then
		return plopCells[1]
	elseif current == "onboarding" then
		return stepCells[1]
	end
	return if tabBar then tabBar.buttons[current] else nil
end

-- ○ : retour au menu
function Objectives.onBack(): boolean
	return false
end

-- Entrée du menu visible pour ce joueur
function Objectives.visible(): boolean
	return true
end

-- Navigateur fourni par PanelController AVANT build
function Objectives.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function Objectives.refresh()
	refresh()
end

-- Mode du bouton d'une carte (specs)
function Objectives._cardMode(slot: number): string?
	local _ = nav
	local card = cards[slot]
	return if card then card.mode else nil
end

return Objectives
