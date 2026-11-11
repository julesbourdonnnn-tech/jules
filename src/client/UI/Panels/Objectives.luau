--!strict
-- Objectives (paquet client-panels) : panneau Objectifs (GDD §7.3, §7.4, §3 ; docs/04 §13.6) :
--   * Aujourd'hui : 3 objectifs (facile, moyen, difficile) avec progression, récompense en minutes de
--     revenu, « Réclamer » (ClaimObjective) quand c'est fait, relance gratuite (RerollObjective,
--     1 par jour, seulement sur un objectif pas encore fait), « Les 3 faits : Goutte chanceuse ! » ;
--   * Plop : jours au total (jamais une série), repas du jour, paliers (Config/Quests.Feed) ;
--   * Accueil : étapes de l'accueil, tant qu'il n'est pas fini.
-- UiSeen("objectives") à la première ouverture (étape 10 de l'accueil, côté serveur). Sélection par
-- défaut : un « Réclamer » disponible, sinon la 1re carte. Un bouton refusé ne part jamais au serveur.
-- Règle 18 (lot B3, D17) : la coche des paliers de Plop et des étapes de l'accueil est DESSINÉE
-- (Hud/Icons « check », bleu nuit sur la case verte) : « ✓ » n'existe pas dans les polices du jeu.
-- v2.0 (lot B3, étape 4 ; plan B3 D15, D24, D25 ; GDD v2.0 §7.5) :
--   * onglet « Cette semaine » [WeeklyTrack, profil v2] : points (track.points), jours restants
--     (track.endsIn), 12 paliers et leur récompense visible d'avance (Confettis, Goutte chanceuse,
--     cosmétique de la semaine), paliers réclamés cochés (le serveur réclame tout seul : aucun
--     bouton), Défis de Splorch (3 au plus, progression, coche quand c'est fait), récompenses de la
--     semaine : celle de la période (« Palier 12 » ou « Possédé ») puis les prochaines pas encore
--     gagnées (« Revient la semaine prochaine », « Revient dans n semaines ») ;
--   * onglet « Carnet » [Carnet, profil v2] : niveaux achetés à vie vers le prochain seuil
--     (carnet.progress), 8 paliers et les 2 objets de Déco perso du Carnet, dans l'ordre des seuils ;
--   * vues pures de UI/MetaView (track, challenges, carnet) ; barre d'onglets et pages construites au
--     premier besoin, à l'ouverture (jamais écran ouvert) ; interrupteurs coupés : rien de la v2.0
--     n'est construit, la barre et les pages sont celles de la v1.3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Quests = require(Shared.Config.Quests)
local Layout = require(Shared.Config.Layout)
local Clock = require(Shared.Util.Clock)
local BigNumber = require(Shared.Logic.BigNumber)

local Client = script.Parent.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local MetaFlags = require(Client.UI.MetaFlags)
local MetaView = require(Client.UI.MetaView)
local Icons = require(Client.UI.Hud.Icons)
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
-- v2.0 : case d'un palier (piste, Carnet), rangée d'un Défi, ligne des récompenses de la semaine
type Cell = { button: TextButton, head: TextLabel, kind: TextLabel?, name: TextLabel, check: Frame }
type ChallengeRow = { button: TextButton, name: TextLabel, progress: TextLabel, check: Frame }
type SoonLine = { name: TextLabel, status: TextLabel }
type TrackParts = {
	points: TextLabel,
	ends: TextLabel,
	fill: Frame,
	tiers: { Cell },
	challengesTitle: TextLabel,
	challenges: { ChallengeRow },
	soon: Frame,
	soonLines: { SoonLine },
}
type CarnetParts = { progress: TextLabel, fill: Frame, cells: { Cell } }

local Objectives = {}

local ALL_TABS = { "today", "plop", "onboarding" }
-- v2.0 : la semaine et le Carnet après « Aujourd'hui » (ordre relatif de la v1.3 gardé)
local V2_TABS = { "today", "track", "carnet", "plop", "onboarding" }
local CHECK = 36 -- px TV : coche dessinée d'une case
local SOON_LINES = 3 -- récompenses de la semaine montrées (celle de la période + 2 prochaines)
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
-- v2.0 : barre d'onglets construite (v1.3, ou celle de la v2.0 dès le premier besoin), cadre du panneau
local barTabs: { string } = ALL_TABS
local buildContainer: Frame? = nil
local buildTop = 0
local track: TrackParts? = nil
local carnet: CarnetParts? = nil

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

-- v2.0 : onglet de la piste / du Carnet voulu (interrupteur annoncé par le serveur ET profil v2)
local function trackOn(): boolean
	return MetaFlags.v2Profile() and MetaFlags.on("WeeklyTrack")
end

local function carnetOn(): boolean
	return MetaFlags.v2Profile() and MetaFlags.on("Carnet")
end

-- Onglets montrés, dans l'ordre de la barre ; un onglet de la v2.0 seulement quand sa page est
-- construite (à l'ouverture) et que son interrupteur est ouvert
local function visibleTabs(): { string }
	local out = {}
	for _, id in barTabs do
		local shown = if id == "onboarding"
			then not onboardingDone()
			elseif id == "track" then track ~= nil and trackOn()
			elseif id == "carnet" then carnet ~= nil and carnetOn()
			else true
		if shown then
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
-- contour. « Jour 1 » or et récompense blanche s'y lisaient à 1,2 et 1,8 de contraste sans le contour
-- (revue des écrans ; la coche est dessinée en bleu nuit depuis le lot B3). Case sombre : couleur
-- d'origine de chaque texte et contour
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
		-- coche dessinée (règle 18), bleu nuit sur le vert du palier atteint
		local status = cell:FindFirstChild("Status") :: Frame
		Icons.draw(status, if reached then "check" else nil, Widgets.Colors.Stroke)
	end
end

local function refreshOnboarding()
	local step = Widgets.n(Widgets.tbl(Widgets.state("onboarding")).step)
	for i, cell in stepCells do
		local s = Quests.Onboarding.Steps[i]
		local done = step >= s.step
		cell.BackgroundColor3 = if done then Widgets.Colors.Success else Widgets.Colors.Card
		paintVivid(cell, done)
		local status = cell:FindFirstChild("Status") :: Frame
		Icons.draw(status, if done then "check" else nil, Widgets.Colors.Stroke)
	end
end

local function showPage(id: string)
	for name, page in pages do
		page.Visible = name == id
	end
	if tabBar then
		local tabs = visibleTabs()
		for _, tabId in barTabs do
			tabBar.setVisible(tabId, table.find(tabs, tabId) ~= nil)
		end
		tabBar.setActive(id)
	end
end

-- =============================================================================================
-- v2.0 (lot B3, D15) : piste de la semaine, Défis de Splorch, Carnet du Ranch
-- =============================================================================================

-- Profil répliqué sur les clés que lisent MetaView.track, .challenges et .carnet
local META_KEYS = { "version", "weeklyTrack", "carnet", "stats" }

-- Sorte d'une récompense du Carnet (« kind.id » de Cosmetics.List since = 2, objet de Déco perso) : clé du
-- petit libellé qui dit ce que c'est (un titre, une selle…)
local CARNET_KIND: { [string]: string } = {
	title = "panel.ranch.style.title",
	saddle = "panel.ranch.style.saddle",
	flag = "panel.ranch.style.flag",
	trail = "panel.ranch.style.trail",
	emote = "carnet.kind.emote",
	outfit = "carnet.kind.outfit",
	deco = "deco.title",
}

local function lang(): string
	local ok, l = pcall(Prefs.language)
	return if ok and l == "fr" then "fr" else "en"
end

local function metaCtx(): MetaView.Ctx
	return { lang = lang(), on = MetaFlags.on }
end

local function tr(key: string, vars: { [string]: any }?): string
	return Widgets.t(key, vars)
end

-- Texte { key, vars } d'une vue (variables-clés traduites, MetaView.resolve) ; illisible : vide
local function setView(label: TextLabel, t: any)
	local r = MetaView.resolve(t, tr)
	if type(r) == "table" and type(r.key) == "string" then
		Widgets.setText(label, r.key, r.vars)
	else
		Widgets.setRaw(label, "")
	end
end

-- État d'une case : "done" (réclamé : vert, coche bleu nuit), "next" (prochain seuil : bleu qui
-- pulse), "reached" (atteint, pas encore réclamé : un palier de Confettis attend leur interrupteur),
-- "locked" (sombre)
local function paintCell(cell: Cell, state: string)
	local b = cell.button
	b.BackgroundColor3 = if state == "done"
		then Widgets.Colors.Success
		elseif state == "next" then Widgets.Colors.Accent
		elseif state == "reached" then Widgets.Colors.CardLight
		else Widgets.Colors.Card
	paintVivid(b, state == "done" or state == "next")
	Widgets.attention(b, state == "next")
	Icons.draw(cell.check, if state == "done" then "check" else nil, Widgets.Colors.Stroke)
end

-- Récompenses de la semaine montrées : celle de la période, puis les prochaines pas encore gagnées
-- (retour le plus proche d'abord), SOON_LINES au plus
local function soonItems(view: MetaView.Track): { MetaView.WeeklyItem }
	local out: { MetaView.WeeklyItem } = {}
	if view.cosmetic then
		table.insert(out, view.cosmetic)
	end
	local rest: { MetaView.WeeklyItem } = {}
	for _, item in view.rotation do
		if not item.current and not item.won then
			table.insert(rest, item)
		end
	end
	table.sort(rest, function(a, b)
		return a.weeks < b.weeks
	end)
	for _, item in rest do
		if #out >= SOON_LINES then
			break
		end
		table.insert(out, item)
	end
	return out
end

local function refreshTrack()
	local parts = track
	if parts == nil or not trackOn() then
		return
	end
	local profile = Widgets.profile(META_KEYS)
	local ctx = metaCtx()
	local view = MetaView.track(profile, Clock.unix(), ctx)
	setView(parts.points, view.pointsText)
	setView(parts.ends, view.endsText)
	parts.fill.Size = UDim2.fromScale(math.clamp(view.points / math.max(1, view.maxPoints), 0, 1), 1)
	local nextShown = false
	for i, cell in parts.tiers do
		local tier = view.tiers[i]
		cell.button.Visible = tier ~= nil
		if tier then
			Widgets.setText(cell.head, "track.tier", { n = tier.n })
			setView(cell.name, tier.reward)
			local state = "locked"
			if tier.claimed then
				state = "done"
			elseif tier.reached then
				state = "reached"
			elseif not nextShown then
				state = "next"
				nextShown = true
			end
			paintCell(cell, state)
		end
	end
	-- Défis de Splorch (aucun tiré : le bloc entier est caché)
	local list = MetaView.challenges(profile, ctx)
	parts.challengesTitle.Visible = #list > 0
	for i, row in parts.challenges do
		local c = list[i]
		row.button.Visible = c ~= nil
		if c then
			Widgets.setText(row.name, c.key)
			setView(row.progress, c.text)
			row.button.BackgroundColor3 = if c.done then Widgets.Colors.Success else Widgets.Colors.Card
			paintVivid(row.button, c.done)
			Icons.draw(row.check, if c.done then "check" else nil, Widgets.Colors.Stroke)
		end
	end
	-- récompenses de la semaine : « Palier 12 » ou « Possédé » pour celle de la période, puis le
	-- retour des prochaines (« Aucune peur de rater », GDD §7.5)
	local items = soonItems(view)
	local last = view.tiers[#view.tiers]
	local lastClaimed = last ~= nil and last.claimed
	parts.soon.Visible = #items > 0
	for i, line in parts.soonLines do
		local item = items[i]
		line.name.Visible = item ~= nil
		line.status.Visible = item ~= nil
		if item then
			setView(line.name, item.name)
			-- gagné (bit du serveur), ou le palier 12 de la période déjà réclamé : « Possédé »
			if item.won or (item.current and lastClaimed) then
				Widgets.setText(line.status, "common.owned")
			elseif item.current then
				Widgets.setText(line.status, "track.tier", { n = #view.tiers })
			else
				setView(line.status, item.returns)
			end
		end
	end
end

type CarnetEntry = { at: number, name: MetaView.Text?, kind: string, done: boolean, reached: boolean }

-- Paliers du Carnet et objets de Déco perso du Carnet, dans l'ordre des seuils
local function carnetEntries(view: MetaView.Carnet): { CarnetEntry }
	local out: { CarnetEntry } = {}
	for _, t in view.tiers do
		local ref = Quests.Carnet.Rewards[t.at]
		local kind = if type(ref) == "string" then string.match(ref, "^(%a+)%.") or "" else ""
		table.insert(out, { at = t.at, name = t.reward, kind = kind, done = t.claimed, reached = t.reached })
	end
	for _, d in view.decos do
		table.insert(out, { at = d.at, name = d.name, kind = "deco", done = d.reached, reached = d.reached })
	end
	table.sort(out, function(a, b)
		return a.at < b.at
	end)
	return out
end

local function refreshCarnet()
	local parts = carnet
	if parts == nil or not carnetOn() then
		return
	end
	local view = MetaView.carnet(Widgets.profile(META_KEYS), metaCtx())
	local entries = carnetEntries(view)
	-- vers la prochaine récompense du Carnet, palier OU objet de Déco perso (750, 7 500) : la case qui
	-- pulse et le compte disent le même seuil ; tout atteint : le dernier
	local l = lang()
	local goal = Quests.Carnet.Tiers[#Quests.Carnet.Tiers]
	for _, e in entries do
		if not e.reached then
			goal = e.at
			break
		end
	end
	Widgets.setText(parts.progress, "carnet.progress", {
		n = BigNumber.full(math.min(view.bought, goal), l),
		m = BigNumber.full(goal, l),
	})
	parts.fill.Size = UDim2.fromScale(math.clamp(view.bought / math.max(1, goal), 0, 1), 1)
	local nextShown = false
	for i, cell in parts.cells do
		local e = entries[i]
		cell.button.Visible = e ~= nil
		if e then
			Widgets.setRaw(cell.head, BigNumber.full(e.at, l))
			local kind = cell.kind
			if kind then
				local key = CARNET_KIND[e.kind]
				if key then
					Widgets.setText(kind, key)
				else
					Widgets.setRaw(kind, "")
				end
			end
			setView(cell.name, e.name)
			local state = "locked"
			if e.done then
				state = "done"
			elseif e.reached then
				state = "reached"
			elseif not nextShown then
				state = "next"
				nextShown = true
			end
			paintCell(cell, state)
		end
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
	refreshTrack()
	refreshCarnet()
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

-- Grille de cases (sélectionnables pour la croix ; ✕ ne fait rien), ancrées au centre : la pulsation
-- du prochain palier (1 → 1,08, GDD §9.2) et le grossissement de la sélection débordent également des
-- deux côtés, jamais sur la case voisine (écart de 16 px)
local function cellGrid(
	page: Frame,
	prefix: string,
	top: number,
	count: number,
	cols: number,
	w: number,
	h: number,
	fill: (cell: TextButton, i: number) -> ()
): { TextButton }
	local gap = Layout.Spacing.Min
	local width = page.Size.X.Offset
	local totalW = cols * w + (cols - 1) * gap
	local left = math.floor((width - totalW) / 2)
	local out: { TextButton } = {}
	for i = 1, count do
		local col = (i - 1) % cols
		local line = (i - 1) // cols
		local b = Widgets.button({
			parent = page,
			name = prefix .. i,
			size = UDim2.fromOffset(w, h),
			position = UDim2.fromOffset(
				left + col * (w + gap) + math.floor(w / 2),
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

-- Grille de cases d'information de la v1.3 (Plop, Accueil) : 6 colonnes de cases du panneau
local function infoGrid(
	page: Frame,
	top: number,
	count: number,
	fill: (cell: TextButton, i: number) -> ()
): { TextButton }
	local cell = Layout.Panel.cell
	return cellGrid(page, "Cell", top, count, Layout.Panel.columns, cell.w, cell.h - 24, fill)
end

-- Coche dessinée d'une case de Plop ou de l'accueil (règle 18 : « ✓ » absent des polices), en bas à
-- gauche, là où était le « ✓ » de la v1.3
local function statusCheck(cell: TextButton)
	local check = Icons.canvas(cell, CHECK, { "check" }, "Status")
	check.AnchorPoint = Vector2.new(0, 1)
	-- hors du cadre de focus dessiné dans la case (8 px)
	check.Position = UDim2.new(0, 16, 1, -12)
	check.ZIndex = cell.ZIndex + 1
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
		statusCheck(cell)
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
		statusCheck(cell)
	end)
end

-- Barre d'onglets : celle de la v1.3, ou celle de la v2.0 (piste et Carnet après « Aujourd'hui »)
local function buildBar(container: Frame, ids: { string })
	local specs = {}
	for _, id in ids do
		table.insert(specs, { id = id, key = "panel.goals.tab." .. id })
	end
	tabBar = Widgets.tabBar(container, specs, function(id: string)
		Objectives.setTab(id)
	end)
	barTabs = ids
end

local function newPage(id: string): Frame?
	local container = buildContainer
	if container == nil then
		return nil
	end
	local page = Widgets.group(
		container,
		"Page_" .. id,
		UDim2.fromOffset(container.Size.X.Offset, container.Size.Y.Offset - buildTop),
		UDim2.fromOffset(0, buildTop)
	)
	page.Visible = false
	pages[id] = page
	return page
end

-- Contenu d'une case de palier : en-tête à gauche (« Palier 3 », seuil du Carnet) et coche dessinée
-- en haut à droite, hors du cadre de focus dessiné dans la case (8 px), puis la sorte (Carnet) et le
-- nom de la récompense sur toute la largeur, centré dans la place qui reste
local INSET = 16 -- px TV : marge des textes et de la coche, au-delà du cadre de focus
local function makeCell(b: TextButton, headSize: number, nameSize: number, withKind: boolean): Cell
	local h = b.Size.Y.Offset
	local z = b.ZIndex + 1
	local head = Widgets.label({
		parent = b,
		name = "Head",
		size = UDim2.new(1, -(2 * INSET + CHECK + 4), 0, headSize + 8),
		position = UDim2.fromOffset(INSET, 10),
		text = "",
		textSize = headSize,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
		zIndex = z,
	})
	local check = Icons.canvas(b, CHECK, { "check" }, "Check")
	check.AnchorPoint = Vector2.new(1, 0)
	check.Position = UDim2.new(1, -(INSET - 2), 0, 12)
	check.ZIndex = z
	local nameTop = headSize + 22
	local kind: TextLabel? = nil
	if withKind then
		kind = Widgets.label({
			parent = b,
			name = "Kind",
			size = UDim2.new(1, -2 * INSET, 0, 34),
			position = UDim2.fromOffset(INSET, nameTop),
			text = "",
			textSize = 28,
			color = Widgets.Colors.TextDim,
			zIndex = z,
		})
		nameTop += 38
	end
	local name = Widgets.label({
		parent = b,
		name = "Reward",
		size = UDim2.new(1, -2 * INSET, 0, h - nameTop - 10),
		position = UDim2.fromOffset(INSET, nameTop),
		text = "",
		textSize = nameSize,
		wrapped = true,
		zIndex = z,
	})
	return { button = b, head = head, kind = kind, name = name, check = check }
end

-- Points de la semaine (ou niveaux du Carnet) et barre de progression, en haut de la page
local function header(page: Frame): (TextLabel, Frame)
	local width = page.Size.X.Offset
	local label = Widgets.label({
		parent = page,
		name = "Points",
		size = UDim2.fromOffset(math.floor(width / 2) + 120, 48),
		position = UDim2.fromOffset(56, 4),
		text = "",
		textSize = 40,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	local bar = Widgets.frame({
		parent = page,
		name = "Bar",
		size = UDim2.fromOffset(width - 112, 20),
		position = UDim2.fromOffset(56, 60),
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
	return label, fill
end

-- Page « Cette semaine » : points et jours restants, 12 paliers (6 × 2), Défis à gauche, récompenses
-- de la semaine à droite
local TIER_W, TIER_H = Layout.Panel.cell.w, 140
local LOWER_TOP = 96 + 2 * TIER_H + Layout.Spacing.Min + 16 -- 412 : sous les paliers
local LOWER_W = 640
local function buildTrack(page: Frame)
	local width = page.Size.X.Offset
	local points, fill = header(page)
	points.Name = "Points"
	local ENDS_W = 560
	-- les points s'arrêtent 16 px avant « Fin dans n j » (les deux cadres se recouvraient de 72 px :
	-- relevé du cas « v2.0 méta » de Layout_panels, lot B3 étape 6, B3-67)
	points.Size = UDim2.fromOffset(width - 56 - ENDS_W - 16 - 56, 48)
	local ends = Widgets.label({
		parent = page,
		name = "Ends",
		size = UDim2.fromOffset(ENDS_W, 40),
		position = UDim2.new(1, -56, 0, 8),
		anchor = Vector2.new(1, 0),
		text = "",
		textSize = 32,
		xAlign = Enum.TextXAlignment.Right,
	})
	local tiers: { Cell } = {}
	local count = #Quests.WeeklyTrack.Tiers
	for i, b in cellGrid(page, "Tier", 96, count, 6, TIER_W, TIER_H, function() end) do
		tiers[i] = makeCell(b, 28, 28, false)
	end
	-- Défis de Splorch
	local challengesTitle = Widgets.label({
		parent = page,
		name = "ChallengesTitle",
		size = UDim2.fromOffset(LOWER_W, 40),
		position = UDim2.fromOffset(56, LOWER_TOP),
		key = "track.challenges",
		textSize = 32,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	local challenges: { ChallengeRow } = {}
	for i = 1, Quests.WeeklyTrack.ChallengesPerWeek do
		local b = Widgets.button({
			parent = page,
			name = "Challenge" .. i,
			size = UDim2.fromOffset(LOWER_W, 64),
			position = UDim2.fromOffset(56, LOWER_TOP + 44 + (i - 1) * 72),
			color = Widgets.Colors.Card,
			sound = "",
		})
		local z = b.ZIndex + 1
		local name = Widgets.label({
			parent = b,
			name = "Label",
			size = UDim2.new(1, -(16 + 128 + CHECK + 24), 1, -8),
			position = UDim2.fromOffset(16, 4),
			text = "",
			textSize = 28,
			xAlign = Enum.TextXAlignment.Left,
			zIndex = z,
		})
		local progress = Widgets.label({
			parent = b,
			name = "Progress",
			size = UDim2.fromOffset(128, 40),
			position = UDim2.new(1, -(CHECK + 24), 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			text = "",
			textSize = 28,
			xAlign = Enum.TextXAlignment.Right,
			zIndex = z,
		})
		local check = Icons.canvas(b, CHECK, { "check" }, "Check")
		check.AnchorPoint = Vector2.new(1, 0.5)
		check.Position = UDim2.new(1, -12, 0.5, 0)
		check.ZIndex = z
		challenges[i] = { button = b, name = name, progress = progress, check = check }
	end
	-- récompenses de la semaine (lecture seule, aucune case à sélectionner)
	local soon = Widgets.frame({
		parent = page,
		name = "Soon",
		size = UDim2.fromOffset(LOWER_W, 252),
		position = UDim2.fromOffset(width - 56 - LOWER_W, LOWER_TOP),
		color = Widgets.Colors.Card,
		transparency = 0.3,
		stroke = false,
	})
	Widgets.label({
		parent = soon,
		name = "Title",
		size = UDim2.new(1, -32, 0, 40),
		position = UDim2.fromOffset(16, 4),
		key = "track.rotation",
		textSize = 32,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	local soonLines: { SoonLine } = {}
	for i = 1, SOON_LINES do
		local y = 48 + (i - 1) * 68
		local name = Widgets.label({
			parent = soon,
			name = "Name" .. i,
			size = UDim2.new(1, -32, 0, 34),
			position = UDim2.fromOffset(16, y),
			text = "",
			textSize = 28,
			xAlign = Enum.TextXAlignment.Left,
		})
		-- sous le nom, sans le recouvrir (y + 32 : 2 px TV de recouvrement, 4 px à 3840 × 2160 ; B3-67)
		local status = Widgets.label({
			parent = soon,
			name = "Status" .. i,
			size = UDim2.new(1, -32, 0, 34),
			position = UDim2.fromOffset(16, y + 34),
			text = "",
			textSize = 28,
			color = Widgets.Colors.TextDim,
			xAlign = Enum.TextXAlignment.Left,
		})
		soonLines[i] = { name = name, status = status }
	end
	track = {
		points = points,
		ends = ends,
		fill = fill,
		tiers = tiers,
		challengesTitle = challengesTitle,
		challenges = challenges,
		soon = soon,
		soonLines = soonLines,
	}
end

-- Page « Carnet » : niveaux achetés vers le prochain seuil, 8 paliers et 2 objets de Déco perso (5 × 2)
local function buildCarnet(page: Frame)
	local width = page.Size.X.Offset
	local progress, fill = header(page)
	progress.Name = "Progress"
	progress.Size = UDim2.fromOffset(width - 112, 48)
	local count = #Quests.Carnet.Tiers
	for _ in Quests.Carnet.DecoAt do
		count += 1
	end
	local cols = 5
	local gap = Layout.Spacing.Min
	local w = math.floor((width - 112 - (cols - 1) * gap) / cols)
	local cells: { Cell } = {}
	for i, b in cellGrid(page, "Cell", 96, count, cols, w, 232, function() end) do
		cells[i] = makeCell(b, 40, 32, true)
	end
	carnet = { progress = progress, fill = fill, cells = cells }
end

local v2Watching = false
-- Parties de la v2.0 construites au premier besoin, À L'OUVERTURE (jamais écran ouvert, D24) : barre
-- de la v2.0 (elle remplace celle de la v1.3, une seule fois), page de la piste, page du Carnet ;
-- interrupteurs coupés : rien n'est construit
local function prepareOpen()
	local container = buildContainer
	if container == nil then
		return
	end
	local wantTrack, wantCarnet = trackOn(), carnetOn()
	if not (wantTrack or wantCarnet) then
		return
	end
	if barTabs ~= V2_TABS then
		local old = tabBar
		if old then
			old.frame:Destroy()
		end
		buildBar(container, V2_TABS)
	end
	if wantTrack and track == nil then
		local page = newPage("track")
		if page then
			buildTrack(page)
		end
	end
	if wantCarnet and carnet == nil then
		local page = newPage("carnet")
		if page then
			buildCarnet(page)
		end
	end
	if not v2Watching then
		v2Watching = true
		Widgets.watch(META_KEYS, function()
			if isOpen then
				refreshTrack()
				refreshCarnet()
			end
		end)
	end
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Objectives.build(container: Frame)
	buildContainer = container
	buildTop = Layout.Panel.tabHeight + 24
	buildBar(container, ALL_TABS)
	local top = buildTop
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
	-- interrupteurs ou profil v2 changés écran ouvert : les onglets suivent (rien n'est construit)
	MetaFlags.Changed:Connect(function()
		if isOpen then
			refresh()
		end
	end)
end

-- Affiche le panneau (onglet demandé ou le dernier)
function Objectives.open(tab: string?)
	isOpen = true
	Widgets.seen("objectives")
	-- parties de la v2.0 manquantes construites ICI, avant l'affichage
	prepareOpen()
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

-- Sélection par défaut : « Réclamer » disponible, sinon la 1re carte ; piste et Carnet : le 1er palier
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
	elseif current == "track" and track then
		return track.tiers[1].button
	elseif current == "carnet" and carnet then
		return carnet.cells[1].button
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
