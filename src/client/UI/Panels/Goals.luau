--!strict
-- Panels/Goals — paquet « client-panels » (docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * Aujourd'hui : 3 quêtes (profile.quests), barres (remplies en 0,3 s Quad Out quand la
--     progression monte, §9.4), Réclamer → ClaimQuest("daily", slot),
--     relance → RerollQuest(slot) (1 / jour, +1 VIP), « Étoile du jour » ; minuteur jusqu'à
--     00:00 UTC (Clock)
--   * Calendrier : 7 cartes (Config/Quests.Calendar), carte qui se retourne (0,15 s + 0,15 s) sur
--     Celebrate "dailyClaimed", points de série, Réclamer → ClaimDaily ; « en pause » expliqué (un
--     jour manqué ne fait rien perdre)
--   * Semaine : Grand Défilé (profile.weekly, Légendaire de la semaine via EventClock.rotation)
--     → ClaimQuest("weekly", 1)
--   * Accueil : quêtes Q1-Q7 (en cours, faites, à venir), onglet masqué une fois la chaîne finie
--   * hasAction : une récompense est réclamable
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number ;
--     intentions seulement (le serveur valide tout)
-- GDD : §7.3, §7.4, §7.5, §9.4 (Calendrier, Quête), §10.3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Nebbies = require(Shared.Config.Nebbies)
local Quests = require(Shared.Config.Quests)
local EventClock = require(Shared.Logic.EventClock)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)
local Prefs = require(Client.Util.Prefs)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local ScreenFX = require(Client.UI.ScreenFX)
local PanelController = require(Client.Controllers.PanelController)
local Model = require(script.Parent.Model)
local Widgets = require(script.Parent.Widgets)

local Panel = {}

Panel.name = "Goals" :: Types.PanelName
Panel.tabs = { "goals.tab.today", "goals.tab.calendar", "goals.tab.week", "goals.tab.welcome" } :: { string }?

local TAB_IDS = { "today", "calendar", "week", "welcome" }
local TIER_COLORS: { [string]: Color3 } = {
	easy = Theme.Colors.Success,
	medium = Theme.Colors.Warning,
	hard = Theme.Colors.Danger,
}
local QUEST_HEIGHT = 120
local CLAIM_GUARD = 0.6 -- s : un appui par récompense (le serveur est idempotent de toute façon)
local FLIP_TIME = 0.15
local PULSE_EVERY = 1.2
local TICK = 1

local view = Model.view(State.get)
local built = false
local isOpen = false
local currentTab = "today"
local dirty = false
local tabFrames: { [string]: Frame } = {}
local lastPress: { [string]: number } = {}
local tickAcc = 0
local pulseAcc = 0
local lastDay = -1
local flipping: { [number]: boolean } = {}
-- dernière progression affichée par emplacement (même quête) : la barre se remplit en 0,3 s
local questRatio: { [number]: { id: number, ratio: number } } = {}
local weekRatio: { week: number, ratio: number }? = nil

type QuestCard = {
	frame: Frame,
	tier: Frame,
	tierLabel: TextLabel,
	title: TextLabel,
	desc: TextLabel,
	bar: Frame,
	progress: TextLabel,
	reward: TextLabel,
	claim: TextButton,
	reroll: TextButton,
	check: TextLabel,
}
local questCards: { QuestCard } = {}
local todayHeader: TextLabel? = nil
local todayRerolls: TextLabel? = nil
local todayEmpty: TextLabel? = nil
local starDots: { Frame } = {}
local starTitle: TextLabel? = nil
local starHint: TextLabel? = nil

type DayCard = {
	holder: Frame,
	face: Frame,
	day: TextLabel,
	glyph: TextLabel,
	icon: Frame,
	reward: TextLabel,
	check: TextLabel,
}
local dayCards: { DayCard } = {}
local streakDots: { Frame } = {}
local calendarClaim: TextButton? = nil
local calendarTomorrow: TextLabel? = nil
local calendarPaused: TextLabel? = nil

local week: {
	title: TextLabel?,
	desc: TextLabel?,
	bar: Frame?,
	progress: TextLabel?,
	icon: Frame?,
	reward: TextLabel?,
	claim: TextButton?,
	resets: TextLabel?,
} =
	{}

type WelcomeRow = {
	frame: Frame,
	status: TextLabel,
	title: TextLabel,
	reward: TextLabel,
	bar: Frame,
	progress: TextLabel,
}
local welcomeRows: { WelcomeRow } = {}
local welcomeDone: TextLabel? = nil

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function guarded(key: string): boolean
	local now = Clock.now()
	local last = lastPress[key]
	if last and now - last < CLAIM_GUARD then
		return false
	end
	lastPress[key] = now
	return true
end

local function speciesName(s: number?): string
	local def = if s then Nebbies.Species[s] else nil
	return if def then def.name else "?"
end

-- Texte d'une récompense de Config/Quests (Glow « ≈ » calculé sur le revenu passif répliqué)
local function rewardText(reward: Quests.Reward, weekIndex: number): string
	local parts = {}
	if reward.glow then
		table.insert(parts, Prefs.t("calendar.reward.glow", { amount = Prefs.number(reward.glow) }))
	end
	if reward.idleSeconds then
		local amount = Model.idleGlow(view, reward.idleSeconds, reward.minGlow)
		table.insert(
			parts,
			Prefs.t(
				"calendar.reward.glow",
				{ amount = Prefs.t("common.approx", { amount = Prefs.number(amount) }) }
			)
		)
	end
	if reward.species then
		table.insert(parts, Prefs.t("calendar.reward.species", { species = speciesName(reward.species) }))
	end
	if reward.rotation then
		local ok, s = pcall(EventClock.rotation, reward.rotation, weekIndex)
		table.insert(
			parts,
			Prefs.t("calendar.reward.species", { species = speciesName(if ok then s else nil) })
		)
	end
	if reward.stardust then
		table.insert(parts, Prefs.t("calendar.reward.stardust", { amount = Prefs.number(reward.stardust) }))
	end
	if reward.boostSeconds then
		table.insert(
			parts,
			Prefs.t("calendar.reward.boost", { minutes = math.floor(reward.boostSeconds / 60) })
		)
	end
	if reward.unlock == "atlas" then
		table.insert(parts, Prefs.t("supernova.item.atlas"))
	end
	return table.concat(parts, " + ")
end

-- Espèce affichée pour une récompense (icône), sinon nil
local function rewardSpecies(reward: Quests.Reward, weekIndex: number): number?
	if reward.species then
		return reward.species
	end
	if reward.rotation then
		local ok, s = pcall(EventClock.rotation, reward.rotation, weekIndex)
		return if ok then s else nil
	end
	return nil
end

local function rewardGlyph(reward: Quests.Reward): string
	if reward.boostSeconds then
		return "×2"
	elseif reward.stardust and not (reward.glow or reward.idleSeconds) then
		return "✦"
	end
	return "✨"
end

-- Progression affichée (secondes de revenu passif en minutes)
local function progressPair(goal: Quests.Goal, p: number): (number, number)
	local n = goal.n
	local value = math.clamp(math.floor(p), 0, n)
	if goal.kind == "idle" or goal.kind == "paradeIdle" then
		return math.floor(value / 60), math.floor(n / 60)
	end
	return value, n
end

local function questDesc(q: Quests.DailyQuest): string
	return Prefs.t(`quest.daily.{q.id}.desc`, { n = q.goal.n, minutes = math.floor(q.goal.n / 60) })
end

-- ---------------------------------------------------------------------------------------------
-- Aujourd'hui
-- ---------------------------------------------------------------------------------------------

local function renderToday()
	local now = Clock.now()
	local today = Clock.day(now)
	local list = Model.dailyQuests(view, today)
	local rerolls = Model.rerollsLeft(view, today)
	if todayHeader then
		todayHeader.Text = Prefs.t("goals.resetsIn", { time = Prefs.duration(Clock.untilNextDay(now)) })
	end
	if todayRerolls then
		todayRerolls.Text = Prefs.t("goals.rerollsLeft", { n = rerolls })
	end
	local any = false
	local claimedCount = 0
	for slot, card in questCards do
		local entry = list[slot]
		local q = if entry then Model.questDef(entry.id) else nil
		if entry == nil or q == nil then
			card.frame.Visible = false
		else
			any = true
			card.frame.Visible = true
			card.tier.BackgroundColor3 = TIER_COLORS[q.tier] or Theme.Colors.Primary
			card.tierLabel.Text = Prefs.t("goals.tier." .. q.tier)
			card.title.Text = Prefs.t(`quest.daily.{q.id}`)
			card.desc.Text = questDesc(q)
			local p = if entry.done == true then q.goal.n else Model.num(entry.p, 0)
			local value, total = progressPair(q.goal, p)
			local ratio = if total > 0 then value / total else 1
			local last = questRatio[slot]
			local grows = isOpen and last ~= nil and last.id == entry.id and ratio > last.ratio
			questRatio[slot] = { id = entry.id, ratio = ratio }
			Widgets.setBar(card.bar, ratio, grows)
			card.progress.Text = Prefs.t("goals.progress", { p = value, n = total })
			local reward = Quests.DailyTiers[q.tier]
			card.reward.Text = if reward then rewardText(reward, Clock.week(now)) else ""
			local claimable = Model.questClaimable(entry)
			local claimed = entry.claimed == true
			if claimed then
				claimedCount += 1
			end
			card.claim.Visible = claimable
			Widgets.setText(card.claim, Prefs.t("goals.claim"))
			card.reroll.Visible = not claimable and not claimed and entry.done ~= true and rerolls > 0
			Widgets.setText(card.reroll, Prefs.t("goals.reroll"))
			card.check.Visible = claimed
			Widgets.highlight(card.frame, claimable, Theme.Colors.Gold)
		end
	end
	if todayEmpty then
		todayEmpty.Text = Prefs.t("goals.noQuests")
		todayEmpty.Visible = not any
	end
	local quests = view.quests
	local starClaimed = type(quests) == "table" and quests.starClaimed == true and quests.day == today
	for i, dot in starDots do
		dot.BackgroundColor3 = if i <= claimedCount or starClaimed then Theme.Colors.Gold else Widgets.DIM
	end
	if starTitle then
		starTitle.Text = (if starClaimed then "★ " else "☆ ") .. Prefs.t("goals.dailyStar")
		starTitle.TextColor3 = if starClaimed then Theme.Colors.Gold else Theme.Colors.Text
	end
	if starHint then
		starHint.Text =
			Prefs.t("goals.starHint", { minutes = math.floor((Quests.DailyStar.boostSeconds or 0) / 60) })
	end
end

local function buildQuestCard(slot: number, parent: Instance): QuestCard
	local frame = Widgets.card({
		name = "Quest" .. slot,
		size = UDim2.new(1, -12, 0, QUEST_HEIGHT),
		order = slot + 1,
		parent = parent,
	})
	local tier = Create("Frame", {
		Name = "Tier",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(96, 28),
		BackgroundColor3 = Theme.Colors.Success,
		Parent = frame,
	}, { Widgets.round(), Widgets.stroke(nil, 1.5) }) :: Frame
	local tierLabel = Widgets.label({
		name = "Label",
		size = UDim2.new(1, -8, 1, -4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxSize = 16,
		parent = tier,
	})
	local textW = -(116 + 170)
	local title = Widgets.label({
		name = "Title",
		size = UDim2.new(1, textW, 0, 30),
		position = UDim2.fromOffset(116, 8),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 24,
		parent = frame,
	})
	local desc = Widgets.label({
		name = "Desc",
		size = UDim2.new(1, -(10 + 170), 0, 24),
		position = UDim2.fromOffset(10, 44),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 18,
		parent = frame,
	})
	local bar = Widgets.bar({
		name = "Bar",
		size = UDim2.new(0.4, -10, 0, 14),
		position = UDim2.fromOffset(10, 82),
		color = Theme.Colors.Primary,
		parent = frame,
	})
	local progress = Widgets.label({
		name = "Progress",
		size = UDim2.fromOffset(80, 24),
		position = UDim2.new(0.4, 6, 0, 77),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 18,
		parent = frame,
	})
	local reward = Widgets.label({
		name = "Reward",
		size = UDim2.new(0.6, -(96 + 170), 0, 26),
		position = UDim2.new(0.4, 90, 0, 76),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 18,
		parent = frame,
	})
	local claim = Widgets.button({
		name = "Claim",
		size = UDim2.fromOffset(150, 64),
		position = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.Gold,
		textColor = Theme.Colors.Text,
		maxText = 24,
		parent = frame,
		sound = "",
		onClick = function()
			if guarded("quest" .. slot) then
				Net.event("ClaimQuest"):FireServer("daily", slot)
			end
		end,
	})
	local reroll = Widgets.button({
		name = "Reroll",
		size = UDim2.fromOffset(150, 52),
		position = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Widgets.CARD,
		maxText = 20,
		parent = frame,
		onClick = function()
			if guarded("reroll" .. slot) then
				Net.event("RerollQuest"):FireServer(slot)
			end
		end,
	})
	local check = Widgets.label({
		name = "Check",
		text = "✓",
		size = UDim2.fromOffset(64, 64),
		position = UDim2.new(1, -40, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.Success,
		maxSize = 52,
		parent = frame,
	})
	return {
		frame = frame,
		tier = tier,
		tierLabel = tierLabel,
		title = title,
		desc = desc,
		bar = bar,
		progress = progress,
		reward = reward,
		claim = claim,
		reroll = reroll,
		check = check,
	}
end

local function buildToday(parent: Frame)
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
	local header = Create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 32),
		LayoutOrder = 1,
		Parent = scroll,
	})
	todayHeader = Widgets.label({
		name = "ResetsIn",
		size = UDim2.fromScale(0.6, 1),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.TextDim,
		maxSize = 20,
		parent = header,
	})
	todayRerolls = Widgets.label({
		name = "Rerolls",
		size = UDim2.fromScale(0.4, 1),
		position = UDim2.fromScale(0.6, 0),
		xAlign = Enum.TextXAlignment.Right,
		maxSize = 20,
		parent = header,
	})
	for slot = 1, #Quests.DailyTierOrder do
		questCards[slot] = buildQuestCard(slot, scroll)
	end
	todayEmpty = Widgets.label({
		name = "Empty",
		size = UDim2.new(1, -12, 0, 40),
		color = Theme.Colors.TextDim,
		maxSize = 22,
		order = 9,
		parent = scroll,
	})
	local star = Widgets.card({
		name = "Star",
		size = UDim2.new(1, -12, 0, 64),
		color = Color3.fromRGB(78, 64, 40),
		order = 10,
		parent = scroll,
	})
	for i = 1, #Quests.DailyTierOrder do
		starDots[i] = Create("Frame", {
			Name = "Dot" .. i,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12 + (i - 1) * 30, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Widgets.DIM,
			Parent = star,
		}, { Widgets.round(), Widgets.stroke(nil, 1.5) }) :: Frame
	end
	local textX = 12 + #Quests.DailyTierOrder * 30 + 8
	starTitle = Widgets.label({
		name = "Title",
		size = UDim2.new(0.4, 0, 1, -12),
		position = UDim2.fromOffset(textX, 6),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 24,
		parent = star,
	})
	starHint = Widgets.label({
		name = "Hint",
		size = UDim2.new(0.6, -(textX + 12), 1, -12),
		position = UDim2.new(0.4, textX, 0, 6),
		xAlign = Enum.TextXAlignment.Right,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 18,
		parent = star,
	})
end

-- ---------------------------------------------------------------------------------------------
-- Calendrier
-- ---------------------------------------------------------------------------------------------

local function renderDay(card: DayCard, index: number, state: string, weekIndex: number)
	local reward = Quests.Calendar[index]
	card.day.Text = if state == "today"
		then Prefs.t("calendar.today")
		else Prefs.t("calendar.day", { n = index })
	local species = rewardSpecies(reward, weekIndex)
	card.icon.Visible = species ~= nil
	card.glyph.Visible = species == nil
	if species then
		Widgets.setNebby(card.icon, { s = species, f = 0, v = 0 })
	else
		card.glyph.Text = rewardGlyph(reward)
	end
	card.reward.Text = rewardText(reward, weekIndex)
	card.check.Visible = state == "claimed"
	card.face.BackgroundColor3 = if state == "claimed"
		then Color3.fromRGB(52, 70, 60)
		elseif state == "today" then Color3.fromRGB(96, 80, 40)
		else Widgets.CARD
	Widgets.highlight(card.face, state == "today", Theme.Colors.Gold)
end

local function renderCalendar()
	local now = Clock.now()
	local today = Clock.day(now)
	local weekIndex = Clock.week(now)
	local cards = Model.calendar(view, today)
	local claimable = Model.dailyClaimable(view, today)
	for i, entry in cards do
		local card = dayCards[i]
		if card and not flipping[i] then
			renderDay(card, i, entry.state, weekIndex)
		end
		local dot = streakDots[i]
		if dot then
			dot.BackgroundColor3 = if entry.state == "claimed" then Theme.Colors.Gold else Widgets.DIM
		end
	end
	if calendarClaim then
		calendarClaim.Visible = claimable
		Widgets.setText(calendarClaim, Prefs.t("calendar.claim"))
	end
	if calendarTomorrow then
		calendarTomorrow.Text = Prefs.t("calendar.tomorrow")
		calendarTomorrow.Visible = not claimable
	end
	if calendarPaused then
		calendarPaused.Text = Prefs.t("calendar.paused")
	end
end

-- Carte qui se retourne (§9.4) : largeur 1 → 0 en 0,15 s, nouveau contenu, 0 → 1 en 0,15 s
local function flipDay(index: number)
	local card = dayCards[index]
	if not card then
		return
	end
	if Juice.reducedMotion() then
		renderCalendar()
		return
	end
	flipping[index] = true
	local first = Juice.tween(card.face, FLIP_TIME, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Quad)
	first.Completed:Once(function()
		flipping[index] = nil
		renderCalendar()
		Juice.tween(card.face, FLIP_TIME, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
	end)
end

local function buildCalendar(parent: Frame)
	local row = Create("Frame", {
		Name = "Days",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.62, 0),
		Parent = parent,
	}, { Widgets.listLayout(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
	for i = 1, #Quests.Calendar do
		local holder = Create("Frame", {
			Name = "Day" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.new(1 / #Quests.Calendar, -6, 1, 0),
			LayoutOrder = i,
			Parent = row,
		}) :: Frame
		local face = Widgets.card({
			name = "Face",
			size = UDim2.fromScale(1, 1),
			position = UDim2.fromScale(0.5, 0),
			anchor = Vector2.new(0.5, 0),
			parent = holder,
		})
		face.ClipsDescendants = true
		local day = Widgets.label({
			name = "DayLabel",
			size = UDim2.new(1, -6, 0.18, 0),
			position = UDim2.new(0.5, 0, 0, 4),
			anchor = Vector2.new(0.5, 0),
			maxSize = 18,
			parent = face,
		})
		local glyph = Widgets.label({
			name = "Glyph",
			size = UDim2.fromScale(0.7, 0.32),
			position = UDim2.fromScale(0.5, 0.4),
			anchor = Vector2.new(0.5, 0.5),
			color = Theme.Colors.Gold,
			maxSize = 40,
			parent = face,
		})
		local icon = Widgets.nebbyIcon("Icon", UDim2.fromScale(0.7, 0.36), face)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.4)
		local reward = Widgets.label({
			name = "Reward",
			size = UDim2.new(1, -8, 0.36, 0),
			position = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
			font = Theme.Fonts.Body,
			maxSize = 15,
			parent = face,
		})
		local check = Widgets.label({
			name = "Check",
			text = "✓",
			size = UDim2.fromScale(0.6, 0.4),
			position = UDim2.fromScale(0.5, 0.4),
			anchor = Vector2.new(0.5, 0.5),
			color = Theme.Colors.Success,
			maxSize = 56,
			zIndex = 8,
			parent = face,
		})
		dayCards[i] = {
			holder = holder,
			face = face,
			day = day,
			glyph = glyph,
			icon = icon,
			reward = reward,
			check = check,
		}
	end
	local dots = Create("Frame", {
		Name = "Streak",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.62, 8),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = parent,
	}, { Widgets.listLayout(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	for i = 1, #Quests.Calendar do
		streakDots[i] = Create("Frame", {
			Name = "Dot" .. i,
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Widgets.DIM,
			LayoutOrder = i,
			Parent = dots,
		}, { Widgets.round() }) :: Frame
	end
	calendarClaim = Widgets.button({
		name = "Claim",
		size = UDim2.fromOffset(240, 80),
		position = UDim2.new(0.5, 0, 0.62, 40),
		anchor = Vector2.new(0.5, 0),
		color = Theme.Colors.Gold,
		maxText = 30,
		parent = parent,
		sound = "",
		onClick = function()
			if guarded("calendar") then
				Net.event("ClaimDaily"):FireServer()
			end
		end,
	})
	calendarTomorrow = Widgets.label({
		name = "Tomorrow",
		size = UDim2.new(0.8, 0, 0, 44),
		position = UDim2.new(0.5, 0, 0.62, 46),
		anchor = Vector2.new(0.5, 0),
		color = Theme.Colors.TextDim,
		maxSize = 24,
		parent = parent,
	})
	calendarPaused = Widgets.label({
		name = "Paused",
		size = UDim2.new(1, -20, 0, 28),
		position = UDim2.new(0.5, 0, 1, 0),
		anchor = Vector2.new(0.5, 1),
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 18,
		parent = parent,
	})
end

-- ---------------------------------------------------------------------------------------------
-- Semaine
-- ---------------------------------------------------------------------------------------------

local function renderWeek()
	local now = Clock.now()
	local weekIndex = Clock.week(now)
	local state = Model.weekly(view, weekIndex)
	if week.title then
		week.title.Text = Prefs.t("weekly.title")
	end
	if week.desc then
		week.desc.Text = Prefs.t("weekly.desc", { n = state.goal })
	end
	if week.bar then
		local ratio = math.min(1, state.banked / math.max(1, state.goal))
		local last = weekRatio
		local grows = isOpen and last ~= nil and last.week == weekIndex and ratio > last.ratio
		weekRatio = { week = weekIndex, ratio = ratio }
		Widgets.setBar(week.bar, ratio, grows)
	end
	if week.progress then
		week.progress.Text =
			Prefs.t("goals.progress", { p = math.min(state.banked, state.goal), n = state.goal })
	end
	if week.icon then
		Widgets.setNebby(week.icon, { s = state.species, f = 0, v = 0 })
	end
	if week.reward then
		week.reward.Text = Prefs.t("weekly.reward", {
			species = speciesName(state.species),
			dust = Prefs.number(Quests.Weekly.reward.stardust or 0),
		})
	end
	if week.claim then
		week.claim.Visible = not state.claimed
		Widgets.setEnabled(week.claim, state.claimable)
		Widgets.setText(week.claim, Prefs.t(if state.claimed then "calendar.claimed" else "goals.claim"))
	end
	if week.resets then
		week.resets.Text = Prefs.t("weekly.resetsIn", { time = Prefs.duration(Clock.untilNextWeek(now)) })
	end
end

local function buildWeek(parent: Frame)
	local card = Widgets.card({
		name = "GrandParade",
		size = UDim2.new(1, -12, 0, 260),
		position = UDim2.fromScale(0.5, 0),
		anchor = Vector2.new(0.5, 0),
		color = Color3.fromRGB(70, 56, 104),
		parent = parent,
	})
	week.title = Widgets.label({
		name = "Title",
		size = UDim2.new(1, -170, 0, 44),
		position = UDim2.fromOffset(16, 10),
		xAlign = Enum.TextXAlignment.Left,
		font = Widgets.STAMP_FONT,
		color = Theme.Colors.Gold,
		maxSize = 36,
		parent = card,
	})
	week.desc = Widgets.label({
		name = "Desc",
		size = UDim2.new(1, -170, 0, 30),
		position = UDim2.fromOffset(16, 58),
		xAlign = Enum.TextXAlignment.Left,
		font = Theme.Fonts.Body,
		maxSize = 22,
		parent = card,
	})
	week.bar = Widgets.bar({
		name = "Bar",
		size = UDim2.new(1, -270, 0, 18),
		position = UDim2.fromOffset(16, 102),
		color = Theme.Colors.Gold,
		parent = card,
	})
	week.progress = Widgets.label({
		name = "Progress",
		size = UDim2.fromOffset(90, 28),
		position = UDim2.new(1, -250, 0, 97),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 22,
		parent = card,
	})
	local icon = Widgets.nebbyIcon("Icon", UDim2.fromOffset(130, 130), card)
	icon.AnchorPoint = Vector2.new(1, 0)
	icon.Position = UDim2.new(1, -16, 0, 10)
	week.icon = icon
	week.reward = Widgets.label({
		name = "Reward",
		size = UDim2.new(1, -200, 0, 30),
		position = UDim2.fromOffset(16, 136),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 22,
		parent = card,
	})
	week.claim = Widgets.button({
		name = "Claim",
		size = UDim2.fromOffset(220, 72),
		position = UDim2.new(0, 16, 1, -12),
		anchor = Vector2.new(0, 1),
		color = Theme.Colors.Gold,
		maxText = 28,
		parent = card,
		sound = "",
		onClick = function()
			if guarded("weekly") then
				Net.event("ClaimQuest"):FireServer("weekly", 1)
			end
		end,
	})
	week.resets = Widgets.label({
		name = "Resets",
		size = UDim2.new(1, -260, 0, 28),
		position = UDim2.new(1, -16, 1, -30),
		anchor = Vector2.new(1, 0),
		xAlign = Enum.TextXAlignment.Right,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 18,
		parent = card,
	})
end

-- ---------------------------------------------------------------------------------------------
-- Accueil
-- ---------------------------------------------------------------------------------------------

local function renderWelcome()
	local step = Model.onboardingStep(view)
	local current = math.max(1, step)
	local onboarding = view.onboarding
	local p = if type(onboarding) == "table" then Model.num(onboarding.p, 0) else 0
	local weekIndex = Clock.week()
	for i, row in welcomeRows do
		local def = Quests.Onboarding[i]
		local done = i < current
		local active = i == current and step <= #Quests.Onboarding
		row.status.Text = if done then "✓" elseif active then "▶" else "·"
		row.status.TextColor3 = if done
			then Theme.Colors.Success
			elseif active then Theme.Colors.Gold
			else Widgets.DIM
		row.title.Text = Prefs.t("quest.onboarding." .. def.id)
		row.title.TextColor3 = if done then Theme.Colors.TextDim else Theme.Colors.Text
		row.reward.Text = rewardText(def.reward, weekIndex)
		row.bar.Visible = active
		row.progress.Visible = active
		if active then
			local value, total = progressPair(def.goal, p)
			Widgets.setBar(row.bar, if total > 0 then value / total else 0, false)
			row.progress.Text = Prefs.t("goals.progress", { p = value, n = total })
		end
		Widgets.highlight(row.frame, active, Theme.Colors.Gold)
	end
	if welcomeDone then
		welcomeDone.Text = Prefs.t("goals.welcomeDone")
		welcomeDone.Visible = Model.onboardingDone(view)
	end
end

local function buildWelcome(parent: Frame)
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
	}, { Widgets.listLayout(Enum.FillDirection.Vertical, 6) })
	for i in Quests.Onboarding do
		local frame =
			Widgets.card({ name = "Q" .. i, size = UDim2.new(1, -12, 0, 68), order = i, parent = scroll })
		local status = Widgets.label({
			name = "Status",
			size = UDim2.fromOffset(48, 48),
			position = UDim2.new(0, 8, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			maxSize = 34,
			parent = frame,
		})
		local title = Widgets.label({
			name = "Title",
			size = UDim2.new(0.5, -64, 0, 30),
			position = UDim2.fromOffset(64, 6),
			xAlign = Enum.TextXAlignment.Left,
			maxSize = 22,
			parent = frame,
		})
		local reward = Widgets.label({
			name = "Reward",
			size = UDim2.new(0.5, -64, 0, 24),
			position = UDim2.fromOffset(64, 38),
			xAlign = Enum.TextXAlignment.Left,
			color = Theme.Colors.Gold,
			font = Theme.Fonts.Body,
			maxSize = 17,
			parent = frame,
		})
		local bar = Widgets.bar({
			name = "Bar",
			size = UDim2.new(0.32, 0, 0, 14),
			position = UDim2.new(0.5, 0, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			color = Theme.Colors.Primary,
			parent = frame,
		})
		local progress = Widgets.label({
			name = "Progress",
			size = UDim2.new(0.18, -12, 0, 26),
			position = UDim2.new(0.82, 6, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			xAlign = Enum.TextXAlignment.Left,
			maxSize = 20,
			parent = frame,
		})
		welcomeRows[i] =
			{ frame = frame, status = status, title = title, reward = reward, bar = bar, progress = progress }
	end
	welcomeDone = Widgets.label({
		name = "Done",
		size = UDim2.new(1, -12, 0, 40),
		color = Theme.Colors.Success,
		maxSize = 24,
		order = 99,
		parent = scroll,
	})
end

-- ---------------------------------------------------------------------------------------------
-- Interface du panneau
-- ---------------------------------------------------------------------------------------------

local function renderTab(id: string)
	if id == "today" then
		renderToday()
	elseif id == "calendar" then
		renderCalendar()
	elseif id == "week" then
		renderWeek()
	elseif id == "welcome" then
		renderWelcome()
	end
end

local function tabFrame(id: string, parent: Instance): Frame
	local frame = Create("Frame", {
		Name = "Tab_" .. id,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	}) :: Frame
	tabFrames[id] = frame
	return frame
end

function Panel.build(parent: Frame)
	if built then
		return
	end
	built = true
	buildToday(tabFrame("today", parent))
	buildCalendar(tabFrame("calendar", parent))
	buildWeek(tabFrame("week", parent))
	buildWelcome(tabFrame("welcome", parent))

	State.Changed:Connect(function(key: string)
		if
			key == "quests"
			or key == "daily"
			or key == "weekly"
			or key == "onboarding"
			or key == "idleRate"
			or key == "passes"
		then
			dirty = true
			if key == "onboarding" then
				PanelController.invalidate()
			end
		end
	end)
	Prefs.LanguageChanged:Connect(function()
		dirty = true
	end)
	ScreenFX.Celebrated:Connect(function(payload: Types.CelebratePayload)
		if type(payload) ~= "table" or type(payload.data) ~= "table" or not isOpen then
			return
		end
		local data = payload.data
		if payload.kind == "dailyClaimed" and type(data.day) == "number" then
			flipDay(math.floor(data.day))
		elseif (payload.kind == "questClaimed" or payload.kind == "questDone") and data.kind == "daily" then
			local card = if type(data.slot) == "number" then questCards[data.slot] else nil
			if card then
				Juice.pulse(card.frame, 1.1)
			end
			dirty = true
		end
	end)
end

function Panel.onOpen(_args: any?)
	isOpen = true
	dirty = false
	lastDay = Clock.day()
	renderTab(currentTab)
end

function Panel.onClose()
	isOpen = false
end

function Panel.hasAction(): boolean
	return Model.goalsHasAction(view, Clock.now())
end

function Panel.tabVisible(tab: string): boolean
	if tab == "welcome" then
		return not Model.onboardingDone(view)
	end
	return true
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
	if not built or not isOpen then
		return
	end
	tickAcc += dt
	if tickAcc >= TICK then
		tickAcc = 0
		local day = Clock.day()
		if day ~= lastDay then
			-- minuit UTC : nouvelles quêtes et nouveau jour de calendrier
			lastDay = day
			dirty = true
		elseif currentTab == "today" or currentTab == "week" then
			dirty = true -- minuteurs
		end
	end
	if dirty then
		dirty = false
		renderTab(currentTab)
	end
	pulseAcc += dt
	if pulseAcc >= PULSE_EVERY then
		pulseAcc = 0
		if not Juice.reducedMotion() then
			-- « Réclamer » pulse (§9.4)
			for _, card in questCards do
				if card.frame.Visible and card.claim.Visible then
					Juice.pulse(card.claim, 1.08)
				end
			end
			if currentTab == "calendar" and calendarClaim and calendarClaim.Visible then
				Juice.pulse(calendarClaim, 1.08)
			end
			if
				currentTab == "week"
				and week.claim
				and week.claim.Visible
				and Widgets.isEnabled(week.claim)
			then
				Juice.pulse(week.claim, 1.08)
			end
		end
	end
end

function Panel.defaultSelection(): GuiObject?
	if currentTab == "calendar" and calendarClaim and calendarClaim.Visible then
		return calendarClaim
	end
	for _, card in questCards do
		if card.frame.Visible and card.claim.Visible then
			return card.claim
		end
	end
	return nil
end

-- Exposé pour les tests
Panel._questCards = questCards
Panel._dayCards = dayCards
Panel._week = week
Panel._welcomeRows = welcomeRows
Panel._calendarClaim = function(): TextButton?
	return calendarClaim
end
Panel._tab = function(): string
	return currentTab
end

return Panel
