--!strict
-- Cards (paquet client-hud, docs/04 §10.3, §13.5, §14.2) : cartes en jeu (GDD §10.3, §4.21.1) et leur
-- file unique (ordre Config/Layout.Cards.Order ; l'écran de retour de client-panels passe avant tout).
--   * Non bloquantes (objectifs à 5:00, nouveaux objectifs, nouvelle entrée du Squishydex, « Garder ton
--     clip ? », « Wibble revient toujours ! », « Plop a sommeil », « booped ») : glissent à droite
--     (Layout.Hud.card) pendant Layout.Cards.NonBlockingSeconds (8 s), ne prennent JAMAIS la sélection
--     (le stick continue de faire marcher), puis se rangent dans la pastille « ! » (pending). On y va par
--     le menu : △ / croix ↓ (liés par InputController seul) → PanelController (entrée « ! ») → ✕ →
--     Cards.open(id) : la carte rouverte devient une fenêtre non bloquante de FocusGuard
--     (« card:<id> ») avec ses boutons (« booped » : « Continuer » par défaut, « Pas ce joueur » →
--     RefuseBooper) ; ○ la referme et la range ; △ (le menu se ferme) la range aussi. Un clic de souris
--     sur la carte affichée la rouvre.
--   * Bloquante : la carte du choix Rush / Cozy (ModePrompt), montrée seulement au calme (dans son
--     ranch, immobile depuis Events.Rush.CardStillFor, ni Rush ni MEGA, prochain Rush à plus de
--     CardMinToNextRush, ni portage ni poursuite, aucune autre fenêtre) ; garde d'entrée de 0,6 s
--     (boutons grisés, aucun appui accepté) ; « Je reste tranquille » sélectionné d'office ; ○ = Cozy ;
--     sans réponse en 20 s, la carte se ferme (le serveur garde Cozy, délai lancé par UiSeen).
--   * Une seule carte à l'écran ; les autres attendent leur tour ; rien ne s'affiche derrière une
--     fenêtre (panneau, écran de retour, carte bloquante).
--   * Cards ne lie AUCUNE touche. Pour ouvrir un panneau (objectifs, Squishydex), Cards émet
--     Requested(sorte, "open") ; PanelController (plus tardif) l'écoute. UiSeen part quand une carte
--     modeCard, postBoop ou booped est montrée. Vibration cardIn à l'ouverture de la carte du choix.
-- Chaque état a sa sortie : 8 s pour une carte affichée, 20 s pour la carte du choix, ○ et les
-- boutons pour une carte rouverte ; file et rangement bornés. Temps : Clock (specs : voyage dans le
-- temps) ; une seule connexion par image.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local Events = require(Shared.Config.Events)
local EventClock = require(Shared.Logic.EventClock)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Juice = require(Client.UI.Juice)
local Glyph = require(Client.UI.Glyph)
local FocusGuard = require(Client.UI.FocusGuard)
local Text = require(Client.UI.Text)
local Format = require(Client.UI.Format)
local Prefs = require(Client.Util.Prefs)
local Haptics = require(Client.Util.Haptics)
local AudioController = require(Client.Controllers.AudioController)
local State = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Util = require(Client.UI.Hud.Util)
local Chase = require(Client.UI.Hud.Chase)

export type Card = {
	id: string,
	kind: string, -- Config/Layout.Cards.Order
	blocking: boolean,
	data: { [string]: any },
}

local Cards = {}

Cards.Changed = Signal.new() :: Signal.Signal<>
-- (sorte de carte, action) : un bouton de carte demande un panneau, ex. ("objectives", "open"),
-- ("dex", "open") ; écouté par PanelController (jamais d'appel direct vers un module plus tardif)
Cards.Requested = Signal.new() :: Signal.Signal<string, string>

local ORDER: { [string]: number } = {}
for i, kind in Layout.Cards.Order do
	ORDER[kind] = i
end
local UNIQUE: { [string]: boolean } = { mode = true, objectives = true, newObjectives = true, sleepy = true }
local SEEN_SCREEN: { [string]: string } = { mode = "modeCard", postBoop = "postBoop", booped = "booped" }

local DISPLAY_ORDER = 40
local SIDE = Layout.Hud.card
local SIDE_CONTENT = Layout.HudContent.card
local SHOW_SECONDS = Layout.Cards.NonBlockingSeconds
local QUEUE_MAX = 12
local PENDING_MAX = 10
local DIALOG_W = 800
local MODE_GUARD = Events.Rush.CardEntryGuard
local MODE_TIMEOUT = Events.Rush.CardTimeout
local STILL_FOR = Events.Rush.CardStillFor
local STILL_EPS = 0.5 -- studs : en dessous, le joueur est immobile
local SLIDE = 0.3
local CALM_EVERY = 0.25 -- s entre deux vérifications du calme (créatures proches, événements)
-- ✕ de la carte du choix : montré seulement sur le bouton sélectionné (✕ active la sélection ; « Je
-- reste tranquille » l'est d'office). ○ reste toujours sur « Je reste tranquille » (○ = Cozy).
local RUSH_GLYPH = { gamepad = Enum.KeyCode.ButtonA, keyboard = Enum.KeyCode.Return }
local NO_GLYPH = {}

type Entry = { card: Card, seq: number }

local initialized = false
local started = false
local seq = 0
local queue: { Entry } = {} -- en attente d'affichage
local stowed: { Entry } = {} -- rangées (pastille « ! »)
local displayed: Entry? = nil -- carte non bloquante à l'écran (8 s)
local displayedUntil = 0
local windowEntry: Entry? = nil -- carte rouverte, ou carte du choix, en fenêtre
local windowOpenedAt = 0
local modeWaiting: Entry? = nil -- carte du choix reçue, en attente du calme
local stillSince: number? = nil
local lastPos: Vector3? = nil
local lastBooper: { [string]: number } = {} -- uid → boopeur (« Pas ce joueur » de la carte postBoop)
local seenSent: { [string]: boolean } = {}
local lastCalmCheck = -math.huge

-- Interface
local screen: ScreenGui? = nil
local side: TextButton? = nil -- carte non bloquante (cliquable à la souris, jamais sélectionnable)
local sideTitle: TextLabel? = nil
local sideLine: TextLabel? = nil
local sideGlyph: Glyph.Handle? = nil
local dialog: Frame? = nil -- carte rouverte (fenêtre non bloquante)
local dialogButtons: { TextButton } = {}
local modeFrame: Frame? = nil -- carte du choix (fenêtre bloquante)
local modeRush: TextButton? = nil
local modeCozy: TextButton? = nil
local modeBlob: Frame? = nil
local modeGifts: TextLabel? = nil
local veil: Frame? = nil

-- =============================================================================================
-- Outils
-- =============================================================================================

local function windowName(entry: Entry): string
	return "card:" .. entry.card.id
end

local function orderOf(entry: Entry): number
	return ORDER[entry.card.kind] or #Layout.Cards.Order + 1
end

local function sortEntries(list: { Entry })
	table.sort(list, function(a, b)
		local oa, ob = orderOf(a), orderOf(b)
		if oa ~= ob then
			return oa < ob
		end
		return a.seq < b.seq
	end)
end

local function changed()
	Cards.Changed:Fire()
end

local function seen(entry: Entry)
	local screenKey = SEEN_SCREEN[entry.card.kind]
	if screenKey == nil or seenSent[screenKey] then
		return
	end
	if Util.send("UiSeen", screenKey) then
		seenSent[screenKey] = true
	end
end

-- Nom du Meilleur Ami n° 1 (« Plop ne s'enfuit jamais », « Nourris Plop ») ; espèce sinon "Plop"
local function bestFriendName(): string
	local squishies = Util.tbl(State.get("squishies"))
	for _, rec in squishies do
		if type(rec) == "table" and rec.bf == 1 then
			local name = Util.speciesName(rec.s)
			if name ~= "" then
				return name
			end
		end
	end
	return Util.speciesName(1)
end

-- Fenêtre au premier plan qui empêche toute carte (panneau, écran de retour, carte bloquante) ; le
-- rail du menu seul n'en empêche pas l'affichage (il est à gauche, la carte à droite)
local function blockedByWindow(): boolean
	local names = Util.safe("FocusGuard.names", {}, FocusGuard.names)
	for _, name in names do
		if name ~= "menu" and not (windowEntry and name == windowName(windowEntry)) then
			return true
		end
	end
	return false
end

-- =============================================================================================
-- Textes et boutons de chaque sorte
-- =============================================================================================

type Action = { key: string, run: (Entry) -> () }

local function texts(card: Card): (string, string)
	local d = card.data
	local kind = card.kind
	if kind == "booped" then
		return Util.t("card.booped.title", { species = Util.speciesName(d.species) }),
			Util.t("card.booped.line")
	elseif kind == "postBoop" then
		return Util.t("card.postBoop.title", { name = Util.speciesName(d.species) }),
			Util.t("card.postBoop.line", { coins = Util.big(Util.num(d.coins, 0, 0)) })
	elseif kind == "objectives" then
		local days = math.floor(Util.num(State.get("plopDays"), 0, 0, 1e9))
		local fed = Util.num(State.get("lastFeedDay"), -1) == Clock.day()
		return Util.t("card.objectives.title"),
			Util.t("card.objectives.feed", { name = bestFriendName(), n = if fed then days else days + 1 })
	elseif kind == "newObjectives" then
		return Util.t("card.newObjectives"), ""
	elseif kind == "dex" then
		local mutation = Util.num(d.mutation, 0)
		if mutation > 0 then
			return Util.t(
				"card.dex.newMutation",
				{ species = Util.speciesName(d.species), mutation = Util.mutationName(mutation) }
			),
				""
		end
		return Util.t("card.dex.new", { species = Util.speciesName(d.species) }), ""
	elseif kind == "clip" then
		return Util.t("card.clip.title"), ""
	elseif kind == "sleepy" then
		return Util.t("card.sleepy.title"), Util.t("card.sleepy.line")
	elseif kind == "mode" then
		return Util.t("card.mode.title"), Util.t("card.mode.safe", { name = bestFriendName() })
	end
	return "", ""
end

local function request(entry: Entry, action: string)
	Cards.Requested:Fire(entry.card.kind, action)
end

local function callData(entry: Entry, field: string)
	local fn = entry.card.data[field]
	if type(fn) == "function" then
		Util.safe("Cards.data." .. field, nil, fn)
	end
end

local function actions(card: Card): { Action }
	local kind = card.kind
	local cont: Action = {
		key = "common.continue",
		run = function(e: Entry)
			Cards.dismiss(e.card.id)
		end,
	}
	if kind == "booped" then
		local list = { { key = "card.booped.continue", run = cont.run } }
		local booper = Util.num(card.data.booperId, 0, 0, 2 ^ 53)
		if booper > 0 then
			table.insert(list, {
				key = "card.booped.refuse",
				run = function(e: Entry)
					Util.send("RefuseBooper", booper)
					Cards.dismiss(e.card.id)
				end,
			})
		end
		return list
	elseif kind == "postBoop" then
		local list = {
			{ key = "card.postBoop.continue", run = cont.run },
			{
				key = "card.postBoop.cozy",
				run = function(e: Entry)
					Util.send("SetMode", false)
					Cards.dismiss(e.card.id)
				end,
			},
		}
		local booper = Util.num(card.data.booperId, 0, 0, 2 ^ 53)
		if booper > 0 then
			table.insert(list, {
				key = "card.postBoop.refuse",
				run = function(e: Entry)
					Util.send("RefuseBooper", booper)
					Cards.dismiss(e.card.id)
				end,
			})
		end
		return list
	elseif kind == "objectives" or kind == "newObjectives" or kind == "dex" then
		return {
			{
				key = "card.see",
				run = function(e: Entry)
					Cards.dismiss(e.card.id)
					request(e, "open")
				end,
			},
			cont,
		}
	elseif kind == "clip" then
		return {
			{
				key = "card.clip.save",
				run = function(e: Entry)
					callData(e, "save")
					request(e, "save")
					Cards.dismiss(e.card.id)
				end,
			},
			{
				key = "card.clip.share",
				run = function(e: Entry)
					callData(e, "share")
					request(e, "share")
					Cards.dismiss(e.card.id)
				end,
			},
			{ key = "common.close", run = cont.run },
		}
	end
	return { { key = "common.ok", run = cont.run } }
end

-- =============================================================================================
-- Construction
-- =============================================================================================

-- Chaque glyphe montré dit vrai : ✕ sur « Je joue au BOOP RUSH » seulement quand ✕ le choisit
local function refreshModeGlyphs()
	local rush = modeRush
	local handle = if rush then Util.buttonGlyph(rush) else nil
	if handle == nil then
		return
	end
	local wanted = if GuiService.SelectedObject == rush then RUSH_GLYPH else NO_GLYPH
	if handle._binding ~= wanted then
		handle:set(wanted)
	end
end

local function build()
	if screen ~= nil and screen.Parent ~= nil then
		return
	end
	local ok, safe = pcall(Root.safe, "Cards", DISPLAY_ORDER)
	if not ok then
		return
	end
	local gui = safe.Parent :: ScreenGui
	screen = gui

	-- voile de la carte du choix (hors de la zone sûre : décoratif)
	local v = Instance.new("Frame")
	v.Name = "Veil"
	v.BackgroundColor3 = Color3.fromRGB(10, 8, 24)
	v.BackgroundTransparency = 0.4
	v.BorderSizePixel = 0
	Root.coverScreen(v)
	v.Visible = false
	v.Active = true
	v.ZIndex = 0
	v:SetAttribute("Decorative", true)
	v.Parent = gui
	veil = v
	safe.ZIndex = 1

	-- carte non bloquante (à droite, cliquable, jamais sélectionnable)
	local s = Instance.new("TextButton")
	s.Name = "Side"
	Text.raw(s, "")
	s.AutoButtonColor = false
	s.Selectable = false
	s.BackgroundColor3 = Theme.Colors.Panel
	s.BackgroundTransparency = 0.05
	s.Visible = false
	s.ZIndex = 5
	Util.place(s, SIDE)
	Util.chrome(s, Layout.Corner.Max)
	local sheen = Instance.new("UIGradient")
	sheen.Name = "Sheen"
	sheen.Rotation = 20
	sheen.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(0.55, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	sheen.Offset = Vector2.new(-1, 0)
	sheen.Parent = s
	sideTitle = Util.label({
		name = "Title",
		parent = s,
		size = UDim2.new(1, -40, 0, 56),
		position = UDim2.fromOffset(20, 14),
		textSize = SIDE_CONTENT.title,
		align = Enum.TextXAlignment.Left,
		zIndex = 6,
		-- titre de longueur libre (« NOUVEAU ! Prickle Puff · Arc-en-ciel ») : plus grande taille qui
		-- tient sur la ligne, comme l'ancien TextScaled (UI/Text, sorte "fit")
		fit = true,
	})
	sideLine = Util.label({
		name = "Line",
		parent = s,
		size = UDim2.new(1, -40, 0, 76),
		position = UDim2.fromOffset(20, 72),
		textSize = SIDE_CONTENT.text,
		color = Theme.Colors.TextDim,
		align = Enum.TextXAlignment.Left,
		wrapped = true,
		font = Theme.Fonts.Body,
		zIndex = 6,
	})
	-- « △ Voir » : la carte se rouvre par le menu (△ / croix ↓ ; M au clavier)
	local hint = Instance.new("Frame")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.new(1, -20, 1, -12)
	hint.Size = UDim2.fromOffset(220, SIDE_CONTENT.glyph)
	hint.ZIndex = 6
	sideGlyph = Glyph.new(hint, { gamepad = Enum.KeyCode.ButtonY, keyboard = Util.menuKey() }, {
		name = "Glyph",
		size = SIDE_CONTENT.glyph,
		position = UDim2.fromOffset(0, 0),
		zIndex = 7,
	})
	Util.label({
		name = "See",
		parent = hint,
		size = UDim2.new(1, -(SIDE_CONTENT.glyph + 12), 1, 0),
		position = UDim2.fromOffset(SIDE_CONTENT.glyph + 12, 0),
		text = Util.t("card.see"),
		textSize = SIDE_CONTENT.text,
		align = Enum.TextXAlignment.Left,
		zIndex = 7,
	})
	hint.Parent = s
	s.Activated:Connect(function()
		local d = displayed
		if d then
			Cards.open(d.card.id)
		end
	end)
	s.Parent = safe
	side = s

	-- carte rouverte (fenêtre non bloquante, au milieu de l'écran, à droite du rail)
	local dlg = Instance.new("Frame")
	dlg.Name = "Dialog"
	dlg.AnchorPoint = Vector2.new(0.5, 0.5)
	dlg.Position = UDim2.fromScale(0.5, 0.5)
	dlg.Size = UDim2.fromOffset(DIALOG_W, 300)
	dlg.BackgroundColor3 = Theme.Colors.Panel
	dlg.Visible = false
	dlg.ZIndex = 10
	Util.chrome(dlg, Layout.Corner.Max)
	Util.label({
		name = "Title",
		parent = dlg,
		size = UDim2.new(1, -64, 0, 60),
		position = UDim2.fromOffset(32, 24),
		textSize = Layout.Text.Title,
		zIndex = 11,
	})
	Util.label({
		name = "Line",
		parent = dlg,
		size = UDim2.new(1, -64, 0, 48),
		position = UDim2.fromOffset(32, 92),
		textSize = Layout.Text.Body,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		wrapped = true,
		zIndex = 11,
	})
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -28)
	row.Size = UDim2.new(1, -64, 0, Layout.Button.MinHeight)
	row.ZIndex = 11
	row.Parent = dlg
	dlg.Parent = safe
	dialog = dlg

	-- carte du choix Rush / Cozy (bloquante)
	local mf = Instance.new("Frame")
	mf.Name = "ModeCard"
	mf.AnchorPoint = Vector2.new(0.5, 0.5)
	mf.Position = UDim2.fromScale(0.5, 0.5)
	local bw, bh = Layout.Cards.ModeButton.w, Layout.Cards.ModeButton.h
	mf.Size = UDim2.fromOffset(2 * bw + 24 + 80, 600)
	mf.BackgroundColor3 = Theme.Colors.Panel
	mf.Visible = false
	mf.ZIndex = 20
	Util.chrome(mf, Layout.Corner.Max)
	Util.label({
		name = "Title",
		parent = mf,
		size = UDim2.new(1, -80, 0, 64),
		position = UDim2.fromOffset(40, 28),
		textSize = Layout.Text.Banner,
		font = Font.fromEnum(Enum.Font.LuckiestGuy),
		zIndex = 21,
	})
	-- petite animation de 6 s en boucle : nez boopé, ATCHOUM, poursuite, retour avec cadeaux
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundColor3 = Theme.Colors.Background
	stage.BackgroundTransparency = 0.3
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Position = UDim2.new(0.5, 0, 0, 104)
	stage.Size = UDim2.new(1, -80, 0, 220)
	stage.ClipsDescendants = true
	stage.ZIndex = 21
	Util.chrome(stage, Layout.Corner.Min)
	local blob = Instance.new("Frame")
	blob.Name = "Blob"
	blob.AnchorPoint = Vector2.new(0.5, 1)
	blob.Position = UDim2.new(0.5, 0, 1, -24)
	blob.Size = UDim2.fromOffset(120, 100)
	blob.BackgroundColor3 = Color3.fromRGB(255, 170, 200)
	blob.ZIndex = 22
	local bcorner = Instance.new("UICorner")
	bcorner.CornerRadius = UDim.new(0.5, 0)
	bcorner.Parent = blob
	local nose = Instance.new("Frame")
	nose.Name = "Nose"
	nose.AnchorPoint = Vector2.new(0.5, 0.5)
	nose.Position = UDim2.fromScale(0.5, 0.55)
	nose.Size = UDim2.fromOffset(18, 14)
	nose.BackgroundColor3 = Color3.fromRGB(255, 110, 150)
	nose.ZIndex = 23
	local ncorner = Instance.new("UICorner")
	ncorner.CornerRadius = UDim.new(0.5, 0)
	ncorner.Parent = nose
	nose.Parent = blob
	blob.Parent = stage
	modeBlob = blob
	modeGifts = Util.label({
		name = "Gifts",
		parent = stage,
		size = UDim2.new(1, -40, 0, 44),
		position = UDim2.fromOffset(20, 12),
		text = Util.t("card.mode.gifts"),
		textSize = Layout.Text.Body,
		color = Theme.Colors.Gold,
		zIndex = 23,
	})
	stage.Parent = mf
	Util.label({
		name = "Safe",
		parent = mf,
		size = UDim2.new(1, -80, 0, 44),
		position = UDim2.fromOffset(40, 340),
		textSize = Layout.Text.Body,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		zIndex = 21,
	})
	modeRush = Util.button({
		name = "Rush",
		parent = mf,
		size = UDim2.fromOffset(bw, bh),
		position = UDim2.new(0.5, -12, 1, -40),
		anchor = Vector2.new(1, 1),
		text = Util.t("card.mode.rush"),
		textSize = Layout.Cards.ModeButton.text,
		color = Color3.fromRGB(255, 120, 180),
		glyph = { gamepad = Enum.KeyCode.ButtonA, keyboard = Enum.KeyCode.Return },
		zIndex = 22,
		onActivate = function()
			Cards._chooseMode(true)
		end,
	})
	modeCozy = Util.button({
		name = "Cozy",
		parent = mf,
		size = UDim2.fromOffset(bw, bh),
		position = UDim2.new(0.5, 12, 1, -40),
		anchor = Vector2.new(0, 1),
		text = Util.t("card.mode.cozy"),
		textSize = Layout.Cards.ModeButton.text,
		color = Color3.fromRGB(120, 200, 160),
		glyph = { gamepad = Enum.KeyCode.ButtonB, keyboard = Enum.KeyCode.Backspace },
		zIndex = 22,
		onActivate = function()
			Cards._chooseMode(false)
		end,
	})
	local rush = modeRush :: TextButton
	local cozy = modeCozy :: TextButton
	rush.NextSelectionRight = cozy
	cozy.NextSelectionLeft = rush
	rush.SelectionGained:Connect(refreshModeGlyphs)
	rush.SelectionLost:Connect(refreshModeGlyphs)
	mf.Parent = safe
	modeFrame = mf
	refreshModeGlyphs()
end

local function setLabel(parent: Instance, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		Text.raw(label, text)
		label.Visible = text ~= ""
	end
end

-- =============================================================================================
-- Carte non bloquante affichée (8 s)
-- =============================================================================================

local function hideSide(animate: boolean)
	local s = side
	if s == nil or not s.Visible then
		return
	end
	if animate and not Prefs.reducedMotion() then
		local home = s.Position
		local tween = Juice.tween(
			s,
			0.2,
			{ Position = home + UDim2.fromOffset(SIDE.rect.w + 120, 0) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and displayed == nil then
				s.Visible = false
				s.Position = home
			end
		end)
	else
		s.Visible = false
	end
end

local function stow(entry: Entry)
	for _, e in stowed do
		if e == entry then
			return
		end
	end
	table.insert(stowed, entry)
	sortEntries(stowed)
	while #stowed > PENDING_MAX do
		table.remove(stowed) -- la moins prioritaire (la plus récente à égalité)
	end
end

local function endDisplay(animate: boolean)
	local d = displayed
	if d == nil then
		return
	end
	displayed = nil
	stow(d)
	hideSide(animate)
	changed()
end

local function showSide(entry: Entry, now: number)
	build()
	local s = side
	if s == nil then
		return
	end
	displayed = entry
	displayedUntil = now + SHOW_SECONDS
	local title, line = texts(entry.card)
	Text.raw(sideTitle :: TextLabel, title)
	Text.raw(sideLine :: TextLabel, line);
	(sideLine :: TextLabel).Visible = line ~= ""
	if sideGlyph then
		sideGlyph:set({ gamepad = Enum.KeyCode.ButtonY, keyboard = Util.menuKey() })
	end
	s:SetAttribute("CardKind", entry.card.kind)
	s:SetAttribute("CardId", entry.card.id)
	Util.place(s, SIDE)
	s.Visible = true
	if not Prefs.reducedMotion() then
		-- glisse de la droite (0,3 s, Back Out) ; reflet qui passe (0,6 s)
		local home = s.Position
		s.Position = home + UDim2.fromOffset(SIDE.rect.w + 120, 0)
		Juice.tween(s, SLIDE, { Position = home }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local sheen = s:FindFirstChild("Sheen")
		if sheen and sheen:IsA("UIGradient") then
			sheen.Offset = Vector2.new(-1, 0)
			Juice.tween(
				sheen,
				0.6,
				{ Offset = Vector2.new(1, 0) },
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out
			)
		end
	end
	AudioController.play(if entry.card.kind == "dex" then "DexNew" else "Pop")
	seen(entry)
	changed()
end

-- =============================================================================================
-- Carte rouverte (fenêtre non bloquante)
-- =============================================================================================

local function clearDialogButtons()
	for _, b in dialogButtons do
		b:Destroy()
	end
	table.clear(dialogButtons)
end

local function closeWindow(restow: boolean)
	local entry = windowEntry
	if entry == nil then
		return
	end
	windowEntry = nil
	if entry.card.kind == "mode" then
		if modeFrame then
			modeFrame.Visible = false
		end
		if veil then
			veil.Visible = false
		end
	else
		if dialog then
			dialog.Visible = false
		end
		clearDialogButtons()
		if restow then
			stow(entry)
		end
	end
	local name = windowName(entry)
	if Util.safe("FocusGuard.isOpen", false, FocusGuard.isOpen, name) then
		Util.safe("FocusGuard.closeNow", nil, FocusGuard.closeNow, name)
	end
	changed()
end

local function openDialog(entry: Entry)
	build()
	local dlg = dialog
	if dlg == nil then
		return
	end
	local title, line = texts(entry.card)
	setLabel(dlg, "Title", title)
	setLabel(dlg, "Line", line)
	clearDialogButtons()
	local row = dlg:FindFirstChild("Buttons") :: Frame
	local list = actions(entry.card)
	local n = #list
	local gap = Layout.Spacing.Normal
	local innerW = DIALOG_W - 64
	local bw = math.floor((innerW - gap * (n - 1)) / n)
	for i, action in list do
		local b = Util.button({
			name = "Action" .. i,
			parent = row,
			size = UDim2.fromOffset(bw, Layout.Button.MinHeight),
			position = UDim2.fromOffset((i - 1) * (bw + gap), 0),
			text = Util.t(action.key),
			textSize = Layout.Text.Button,
			color = if i == 1 then Color3.fromRGB(255, 120, 180) else Theme.Colors.PanelLight,
			zIndex = 12,
			onActivate = function()
				if windowEntry ~= entry then
					return
				end
				AudioController.play("Click")
				action.run(entry)
			end,
		})
		table.insert(dialogButtons, b)
	end
	for i, b in dialogButtons do
		b.NextSelectionLeft = dialogButtons[i - 1]
		b.NextSelectionRight = dialogButtons[i + 1]
	end
	local hasLine = line ~= ""
	dlg.Size = UDim2.fromOffset(DIALOG_W, if hasLine then 280 else 230)
	dlg.Visible = true
	dlg:SetAttribute("CardKind", entry.card.kind)
	if not Prefs.reducedMotion() then
		Juice.popIn(dlg)
	end
	windowEntry = entry
	windowOpenedAt = Clock.now()
	AudioController.play("Whoosh")
	FocusGuard.open({
		name = windowName(entry),
		root = dlg,
		blocking = false,
		default = function(): GuiObject?
			return dialogButtons[1]
		end,
		onBack = function(): boolean
			-- ○ : la carte se referme et reste rangée ; FocusGuard ferme la fenêtre
			if windowEntry == entry then
				windowEntry = nil
				dlg.Visible = false
				clearDialogButtons()
				stow(entry)
				changed()
			end
			return false
		end,
		opener = nil,
	})
	seen(entry)
	changed()
end

-- =============================================================================================
-- Carte du choix (bloquante)
-- =============================================================================================

local function modeGuardActive(now: number): boolean
	return now - windowOpenedAt < MODE_GUARD and now >= windowOpenedAt
end

local function setModeButtonsEnabled(enabled: boolean)
	for _, b in { modeRush, modeCozy } do
		if b then
			b.BackgroundTransparency = if enabled then 0 else 0.55
			b:SetAttribute("Disabled", not enabled)
		end
	end
end

local function openMode(entry: Entry)
	build()
	local mf = modeFrame
	if mf == nil then
		return
	end
	local title, line = texts(entry.card)
	setLabel(mf, "Title", title)
	setLabel(mf, "Safe", line)
	if modeGifts then
		Text.raw(modeGifts, Util.t("card.mode.gifts"))
	end
	local rushLabel = Util.buttonLabel(modeRush :: TextButton)
	if rushLabel then
		Text.raw(rushLabel, Util.t("card.mode.rush"))
	end
	local cozyLabel = Util.buttonLabel(modeCozy :: TextButton)
	if cozyLabel then
		Text.raw(cozyLabel, Util.t("card.mode.cozy"))
	end
	windowEntry = entry
	windowOpenedAt = Clock.now()
	setModeButtonsEnabled(false)
	if veil then
		veil.Visible = true
	end
	mf.Visible = true
	if not Prefs.reducedMotion() then
		Juice.popIn(mf)
	end
	AudioController.play("Whoosh")
	Haptics.play("cardIn")
	FocusGuard.open({
		name = windowName(entry),
		root = mf,
		blocking = true,
		default = function(): GuiObject?
			return modeCozy -- le choix le plus sûr (GDD §4.21.1)
		end,
		onBack = function(): boolean
			if windowEntry ~= entry then
				return false
			end
			if modeGuardActive(Clock.now()) then
				return true -- garde d'entrée : aucun appui accepté
			end
			Cards._chooseMode(false)
			return true
		end,
		opener = nil,
	})
	refreshModeGlyphs()
	seen(entry)
	changed()
end

local function animateMode(now: number)
	local blob = modeBlob
	if blob == nil or windowEntry == nil or windowEntry.card.kind ~= "mode" then
		return
	end
	if Prefs.reducedMotion() then
		blob.Position = UDim2.new(0.5, 0, 1, -24)
		blob.Size = UDim2.fromOffset(120, 100)
		if modeGifts then
			modeGifts.Visible = true
		end
		return
	end
	local t = (now - windowOpenedAt) % Events.Rush.CardAnimLoop
	local x, w, h = 0.5, 120, 100
	if t < 1.5 then
		-- le nez remue, le squishy inspire
		h = 100 + 15 * (t / 1.5)
	elseif t < 2 then
		-- ATCHOUM : écrasé (1,5 ; 0,6)
		w, h = 180, 60
	elseif t < 4 then
		-- la poursuite : il file vers la droite en bondissant
		local k = (t - 2) / 2
		x = 0.5 + 0.35 * k
		h = 100 - 20 * math.abs(math.sin(k * math.pi * 4))
	else
		-- il revient avec des cadeaux
		local k = (t - 4) / 2
		x = 0.85 - 0.35 * k
	end
	blob.Position = UDim2.new(x, 0, 1, -24)
	blob.Size = UDim2.fromOffset(w, h)
	if modeGifts then
		modeGifts.Visible = t >= 4
	end
end

-- Calme pour la carte du choix (GDD §4.21.1) : dans son ranch, immobile, ni Rush ni MEGA, prochain
-- Rush loin, ni portage ni poursuite, aucune fenêtre ni carte à l'écran
local function calm(now: number): boolean
	if displayed ~= nil or windowEntry ~= nil then
		return false
	end
	if Util.safe("FocusGuard.anyOpen", false, FocusGuard.anyOpen) then
		return false
	end
	local pos = Util.rootPos()
	if pos == nil or stillSince == nil or now - (stillSince :: number) < STILL_FOR then
		return false
	end
	local slot = Util.num(Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot), 0)
	if slot <= 0 or not WorldLayout.inRanch(slot, pos :: Vector3) then
		return false
	end
	local ranch = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
	if type(ranch) == "table" and type(ranch.carry) == "string" and ranch.carry ~= "" then
		return false
	end
	local rush = EventClock.rush(now)
	if rush.active or now >= rush.sirenAt or rush.startsAt - now <= Events.Rush.CardMinToNextRush then
		return false
	end
	if EventClock.mega(now).active then
		return false
	end
	return not Chase.inChase(now)
end

local function trackStill(now: number)
	local pos = Util.rootPos()
	if pos == nil then
		stillSince = nil
		lastPos = nil
		return
	end
	local prev = lastPos
	if prev == nil or (pos - prev).Magnitude > STILL_EPS then
		stillSince = now
		lastPos = pos
	elseif stillSince == nil then
		stillSince = now
	end
end

-- =============================================================================================
-- Boucle
-- =============================================================================================

local function step(now: number)
	trackStill(now)
	local win = windowEntry
	if win ~= nil and win.card.kind == "mode" then
		setModeButtonsEnabled(not modeGuardActive(now))
		refreshModeGlyphs()
		animateMode(now)
		if now - windowOpenedAt >= MODE_TIMEOUT or now < windowOpenedAt - 1 then
			-- sans réponse : la carte se ferme ; le serveur garde Cozy (délai lancé par UiSeen)
			closeWindow(false)
		end
		return
	end
	-- carte affichée : 8 s, ou rangée dès qu'une fenêtre passe devant
	local d = displayed
	if d ~= nil then
		if now >= displayedUntil or now < displayedUntil - SHOW_SECONDS - 1 then
			endDisplay(true)
		elseif blockedByWindow() then
			endDisplay(false)
		end
	end
	-- carte du choix au calme (bloquante, avant les autres)
	local m = modeWaiting
	local checkCalm = m ~= nil and win == nil and (now - lastCalmCheck >= CALM_EVERY or now < lastCalmCheck)
	if checkCalm then
		lastCalmCheck = now
	end
	if m ~= nil and checkCalm and calm(now) then
		modeWaiting = nil
		openMode(m)
		return
	end
	if displayed ~= nil or win ~= nil or #queue == 0 or blockedByWindow() then
		return
	end
	local entry = table.remove(queue, 1) :: Entry
	showSide(entry, now)
end

local function remove(list: { Entry }, id: string): Entry?
	for i, e in list do
		if e.card.id == id then
			table.remove(list, i)
			return e
		end
	end
	return nil
end

-- =============================================================================================
-- Remotes
-- =============================================================================================

local function onCelebrate(payload: any)
	if type(payload) ~= "table" or type(payload.data) ~= "table" then
		return
	end
	local d = payload.data
	local kind = payload.kind
	if kind == "photo" then
		-- mode photo (administrateurs, vignettes) : les cartes se cachent avec le HUD
		local gui = screen
		if gui then
			gui.Enabled = d.on ~= true
		end
	elseif kind == "booped" then
		local uid = Util.str(d.uid, "", 16)
		local booper = Util.num(d.booperId, 0, 0, 2 ^ 53)
		if uid ~= "" and booper > 0 then
			local n = 0
			for _ in lastBooper do
				n += 1
			end
			if n >= 64 then
				table.clear(lastBooper) -- borne mémoire (quelques boops par heure au plus)
			end
			lastBooper[uid] = booper
		end
		Cards.push({
			id = "",
			kind = "booped",
			blocking = false,
			data = { uid = uid, species = Util.num(d.species, 0), booperId = booper },
		})
	elseif kind == "ownerReturn" then
		if d.firstBoop == true then
			local uid = Util.str(d.uid, "", 16)
			Cards.push({
				id = "",
				kind = "postBoop",
				blocking = false,
				data = {
					uid = uid,
					species = Util.num(d.species, 0),
					coins = Util.num(d.coins, 0, 0),
					booperId = lastBooper[uid] or 0,
				},
			})
		end
	elseif kind == "objectivesCard" then
		Cards.push({ id = "", kind = "objectives", blocking = false, data = { day = Util.num(d.day, 0) } })
	elseif kind == "newObjectives" then
		Cards.push({ id = "", kind = "newObjectives", blocking = false, data = { day = Util.num(d.day, 0) } })
	elseif kind == "dexNew" then
		Cards.push({
			id = "",
			kind = "dex",
			blocking = false,
			data = {
				species = Util.num(d.species, 0),
				mutation = Util.num(d.mutation, 0),
				star = Util.num(d.star, 0),
			},
		})
	elseif kind == "sleepy" then
		Cards.push({ id = "", kind = "sleepy", blocking = false, data = { minutes = Util.num(d.minutes, 0) } })
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function Cards.Init()
	if initialized then
		return
	end
	initialized = true
	build()
end

-- Connexions et boucles
function Cards.Start()
	if started then
		return
	end
	started = true
	Cards.Init()
	Net.event("Celebrate").OnClientEvent:Connect(onCelebrate)
	Net.event("ModePrompt").OnClientEvent:Connect(function()
		Cards.push({ id = "", kind = "mode", blocking = true, data = {} })
	end)
	FocusGuard.WindowClosed:Connect(function(name: string)
		local win = windowEntry
		if win == nil then
			return
		end
		if name == windowName(win) then
			-- fermée par FocusGuard (racine perdue…) : état remis d'aplomb, carte rangée
			closeWindow(win.card.kind ~= "mode")
		elseif name == "menu" and win.card.kind ~= "mode" then
			-- △ ferme le menu : la carte rouverte au-dessus se range aussi (remarque R2 de client-panels)
			closeWindow(true)
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player.CharacterAdded:Connect(function()
			stillSince = nil
			lastPos = nil
		end)
	end
	RunService.Heartbeat:Connect(function()
		step(Clock.now())
	end)
end

-- Ajoute une carte ; rend son id (sorte inconnue : refusée, id "")
function Cards.push(card: Card): string
	if type(card) ~= "table" then
		return ""
	end
	local kind = card.kind
	if type(kind) ~= "string" or ORDER[kind] == nil or kind == "return" then
		return ""
	end
	seq += 1
	local id = Util.str(card.id, "", 40)
	if id == "" or Cards._find(id) ~= nil then
		id = "c" .. Format.id(seq)
	end
	local data: { [string]: any } = if type(card.data) == "table" then card.data else {}
	local entry: Entry = {
		card = { id = id, kind = kind, blocking = kind == "mode", data = data },
		seq = seq,
	}
	if kind == "mode" then
		local win = windowEntry
		if (win ~= nil and win.card.kind == "mode") or modeWaiting ~= nil then
			return if modeWaiting then modeWaiting.card.id else (win :: Entry).card.id
		end
		modeWaiting = entry
		changed()
		return id
	end
	if UNIQUE[kind] then
		-- une seule carte de cette sorte : la nouvelle remplace l'ancienne (en file ou rangée)
		for _, list in { queue, stowed } do
			for i = #list, 1, -1 do
				if list[i].card.kind == kind then
					table.remove(list, i)
				end
			end
		end
	end
	table.insert(queue, entry)
	sortEntries(queue)
	while #queue > QUEUE_MAX do
		table.remove(queue)
	end
	changed()
	step(Clock.now())
	return id
end

-- Retire une carte (où qu'elle soit)
function Cards.dismiss(id: string)
	if type(id) ~= "string" then
		return
	end
	local win = windowEntry
	if win ~= nil and win.card.id == id then
		closeWindow(false)
		return
	end
	local d = displayed
	if d ~= nil and d.card.id == id then
		displayed = nil
		hideSide(true)
		changed()
		return
	end
	if modeWaiting ~= nil and modeWaiting.card.id == id then
		modeWaiting = nil
		changed()
		return
	end
	if remove(queue, id) or remove(stowed, id) then
		changed()
	end
end

-- Cartes qui attendent une action (pastille « ! », entrée du menu) : la carte affichée puis les cartes
-- rangées, dans l'ordre de la file
function Cards.pending(): { Card }
	local out: { Card } = {}
	local d = displayed
	if d ~= nil then
		table.insert(out, d.card)
	end
	for _, e in stowed do
		table.insert(out, e.card)
	end
	return out
end

-- Rouvre une carte rangée (ou affichée) en fenêtre (depuis le menu)
function Cards.open(id: string)
	if type(id) ~= "string" then
		return
	end
	local win = windowEntry
	if win ~= nil then
		if win.card.id == id or win.card.kind == "mode" then
			return
		end
		closeWindow(true)
	end
	local entry: Entry? = nil
	local d = displayed
	if d ~= nil and d.card.id == id then
		entry = d
		displayed = nil
		hideSide(false)
	else
		entry = remove(stowed, id)
	end
	if entry == nil then
		return
	end
	openDialog(entry :: Entry)
end

-- Carte affichée (fenêtre ouverte, sinon carte non bloquante à l'écran)
function Cards.current(): Card?
	local win = windowEntry
	if win ~= nil then
		return win.card
	end
	local d = displayed
	return if d then d.card else nil
end

-- Choix de la carte du choix (boutons, ○) ; ignoré pendant la garde d'entrée de 0,6 s
function Cards._chooseMode(rush: boolean)
	local win = windowEntry
	if win == nil or win.card.kind ~= "mode" then
		return
	end
	if modeGuardActive(Clock.now()) then
		return
	end
	AudioController.play("Click")
	Util.send("SetMode", rush == true)
	closeWindow(false)
end

-- Carte par id (où qu'elle soit)
function Cards._find(id: string): Card?
	if windowEntry and windowEntry.card.id == id then
		return windowEntry.card
	end
	if displayed and displayed.card.id == id then
		return displayed.card
	end
	if modeWaiting and modeWaiting.card.id == id then
		return modeWaiting.card
	end
	for _, list in { queue, stowed } do
		for _, e in list do
			if e.card.id == id then
				return e.card
			end
		end
	end
	return nil
end

-- La carte du choix attend-elle le calme ? (specs)
function Cards.modeWaiting(): boolean
	return modeWaiting ~= nil
end

-- Cartes en file d'affichage (specs)
function Cards.queued(): number
	return #queue
end

-- Cadres de l'interface (specs de disposition) : "side", "dialog", "mode"
function Cards.frame(name: string): GuiObject?
	if name == "side" then
		return side
	elseif name == "dialog" then
		return dialog
	elseif name == "mode" then
		return modeFrame
	end
	return nil
end

-- Boutons de la fenêtre ouverte (specs)
function Cards.buttons(): { GuiButton }
	local win = windowEntry
	if win == nil then
		return {}
	end
	if win.card.kind == "mode" then
		return { modeRush :: GuiButton, modeCozy :: GuiButton }
	end
	return table.clone(dialogButtons) :: { GuiButton }
end

-- Un tour tout de suite (specs ; la boucle par image fait de même)
function Cards._step()
	step(Clock.now())
end

return Cards
