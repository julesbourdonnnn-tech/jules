--!strict
-- HUD (paquet client-hud, docs/04 §13.5, §14.1) : HUD télé (GDD §10.2) aux rectangles de
-- Config/Layout.Hud, dans Root.safe (px TV, zone sûre de 5 %, colonnes accrochées aux bords) :
--   * pièces (pièce dessinée de 80, montant 56 px qui défile, revenu « +1,2K/s » 32 px, pop 1,15 et son
--     Coin au plus 8 fois par seconde quand elles montent) ; Fame et amis présents (32 px) ;
--   * puce Menu (glyphe △ 48, ou la touche « M » du clavier selon sa disposition, + « Menu » 40 px ;
--     un clic l'ouvre) avec les pastilles « ! » (carte en attente, objectif à réclamer) et « ♥ N »
--     (paires de jumeaux) ; cachée tant que le rail du menu est ouvert (il prend sa place) ;
--   * pastille d'événement (prochain événement « BOOP RUSH 3:12 », événement en cours en couleur :
--     Rush rose, MEGA jaune, Lune violet, fêtes orange ; seulement les événements dont l'interrupteur
--     du serveur est vrai, WorldStateController.event().features) ;
--   * barre du MEGA (pression : points / objectif, temps restant) ; sinon jauge du serveur, GRISE avec
--     « Big Plop se repose mm:ss » (hud.gauge.rest) tant que gauge.restUntil > maintenant ;
--   * suivi d'objectif : Grand Splorch « 12K / 15K », « Prêt ! », ou place et attente dans la file
--     (spectacle.queue : hud.queue.next / hud.queue.place, attente qui décompte) ;
--   * indicateurs d'état (bouclier débutant, ×2, mon mode Rush / Cozy ; minutes dessous) ;
--   * puce d'action spéciale : « GRAND SPLORCH ! » avec △ quand l'objectif est atteint ; « APPLAUDIR »
--     avec croix → et anneau de 8 s pendant une fenêtre ClapPrompt, cachée pendant une poursuite
--     (créature attrapable à ≤ 30 studs), un maintien (boop, bol, dalle) ou une fenêtre ouverte ;
--     pendant l'accueil, consigne du moment (setHint : glyphe 64 + mot 40 px) ;
--   * carte de la cible (squishy visé : nom 36 px, rareté par la couleur ET la forme, taille, revenu,
--     étoiles, mutation 28 px) ; indicateur Bondir (R2 64 + balayage de recharge ; visible pendant la
--     recharge, pendant la leçon, et en ville pendant un Rush ou un Golden).
-- Les flèches de bord d'écran (2 au plus, Golden puis la créature attrapable la plus proche par
-- priorité, ≤ 120 studs) sont dessinées par UI/ScreenFX à partir des mêmes règles (Hud/Chase).
-- Messages : Feedback et célébrations à message passent par la file unique de l'emplacement de message
-- (Hud/Messages, UI/Toast) ; une bannière passe d'abord. Vibration squishyBack au retour de mon
-- squishy boopé (Celebrate ownerReturn / returnedBigger) ; aucune quand il s'enfuit.
-- Aucun chevauchement, texte ≥ 28 px TV, glyphes de l'appareil ; affichage progressif pendant
-- l'accueil (reveal, OnboardingController). Pose ClientReady une fois construit. Une boucle par image.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local Events = require(Shared.Config.Events)
local Balance = require(Shared.Config.Balance)
local Species = require(Shared.Config.Species)
local Rarities = require(Shared.Config.Rarities)
local Formulas = require(Shared.Logic.Formulas)
local FusionRules = require(Shared.Logic.FusionRules)
local QuestRules = require(Shared.Logic.QuestRules)
local EventClock = require(Shared.Logic.EventClock)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Juice = require(Client.UI.Juice)
local Glyph = require(Client.UI.Glyph)
local Platform = require(Client.Util.Platform)
local Prefs = require(Client.Util.Prefs)
local Haptics = require(Client.Util.Haptics)
local AudioController = require(Client.Controllers.AudioController)
local State = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local PromptController = require(Client.Controllers.PromptController)
local ChaseController = require(Client.Controllers.ChaseController)
local FocusGuard = require(Client.UI.FocusGuard)
local Text = require(Client.UI.Text)
local Format = require(Client.UI.Format)
local Cards = require(Client.UI.Cards)
local PanelController = require(Client.UI.PanelController)
local Util = require(Client.UI.Hud.Util)
local Messages = require(Client.UI.Hud.Messages)
local Chase = require(Client.UI.Hud.Chase)

local HUD = {}

local SLOTS = Layout.Hud
local C = Layout.HudContent
local DISPLAY_ORDER = 10
local REFRESH = 0.1 -- s entre deux mises à jour des textes minutés (comptes à rebours)
local COIN_SOUND_GAP = 1 / 8 -- s : son Coin 8 fois par seconde au plus
local CLAP_SECONDS = C.specialChip.clapRing -- 8 s
local HOLD_GRACE = Events.Rush.HoldGrace -- s : un maintien dont endsAt + grâce est passé est retiré
local EVENT_COLORS: { [string]: Color3 } = {
	rush = Color3.fromRGB(255, 120, 180),
	mega = Color3.fromRGB(255, 200, 60),
	moon = Color3.fromRGB(150, 110, 240),
	party = Color3.fromRGB(255, 160, 70),
	next = Color3.fromRGB(44, 38, 74),
}
local GREY = Color3.fromRGB(120, 120, 135)

-- Liaisons des glyphes des consignes de l'accueil (Config/Quests.Onboarding.Steps[].glyph)
local HINT_BINDINGS: { [string]: Glyph.Binding } = {
	action = { gamepad = Enum.KeyCode.ButtonX, keyboard = Enum.KeyCode.E },
	pickup = { gamepad = Enum.KeyCode.ButtonB, keyboard = Enum.KeyCode.Q },
	leap = { gamepad = Enum.KeyCode.ButtonR2, keyboard = Enum.KeyCode.LeftShift },
	ride = { gamepad = Enum.KeyCode.ButtonL2, keyboard = Enum.KeyCode.R },
	menu = { gamepad = Enum.KeyCode.ButtonY, keyboard = Enum.KeyCode.M },
	move = { gamepad = Enum.KeyCode.Thumbstick1, keyboard = Enum.KeyCode.W },
	target = { gamepad = Enum.KeyCode.ButtonL1 },
	clap = { gamepad = Enum.KeyCode.DPadRight, keyboard = Enum.KeyCode.F },
}

local initialized = false
local started = false
local screen: ScreenGui? = nil
local safeFrame: Frame? = nil
local elements: { [string]: GuiObject } = {}
local refs: { [string]: any } = {}
local revealed: { [string]: boolean } = {}
local photo = false

-- état
local coinsShown = 0
local lastCoinSoundAt = -math.huge
local clap: { heroId: number, endsAt: number }? = nil
local hint: { action: string?, key: string }? = nil
local badgeBang = false
local badgeTwins = 0
local holds: { [string]: number } = {} -- maintien en cours (bol, dalle) → endsAt
local friendsHere: { [number]: boolean } = {}
local lastEventAt = 0 -- Clock.now() du dernier EventState reçu (attente de la file qui décompte)
local refreshAcc = math.huge
local leapWasCooling = false
local unstableShown = false
local touchShown = false
local texts: { [string]: string } = {} -- dernier texte posé par label (aucune écriture inutile)
local specialMode = "" -- "" | "splorch" | "clap" | "hint"

-- =============================================================================================
-- Outils
-- =============================================================================================

local function setText(name: string, label: TextLabel?, text: string)
	if label == nil then
		return
	end
	if texts[name] ~= text then
		texts[name] = text
		Text.raw(label, text)
	end
end

local function setVisible(obj: GuiObject?, visible: boolean)
	if obj and obj.Visible ~= visible then
		obj.Visible = visible
	end
end

local function localUserId(): number
	local player = Players.LocalPlayer
	return if player then player.UserId else 0
end

local function mySlot(): number
	return Util.num(Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot), 0, 0, 64)
end

local function myRanch(): { [string]: any }?
	local slot = mySlot()
	if slot <= 0 then
		return nil
	end
	local ranch = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
	return if type(ranch) == "table" then ranch else nil
end

local function eventState(): { [string]: any }?
	local ev = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	return if type(ev) == "table" then ev else nil
end

local function features(): { [string]: any }?
	local ev = eventState()
	if ev and type(ev.features) == "table" then
		return ev.features
	end
	return nil
end

local function frame(name: string, parent: Instance, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color or Theme.Colors.Panel
	f.BackgroundTransparency = transparency or 0.12
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 2
	f.Parent = parent
	return f
end

-- Masque arrondi : ClipsDescendants de Roblox coupe au RECTANGLE, jamais à l'arrondi d'un UICorner ;
-- seul un CanvasGroup arrondi coupe ses enfants à sa forme. Un remplissage (jauge du Grand Splorch,
-- balayage de Bondir) posé dedans reste donc dans le cercle au lieu de dessiner un carré
local function roundMask(parent: Instance, zIndex: number): CanvasGroup
	local mask = Instance.new("CanvasGroup")
	mask.Name = "Mask"
	mask.BackgroundTransparency = 1
	mask.BorderSizePixel = 0
	mask.Size = UDim2.fromScale(1, 1)
	mask.ZIndex = zIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = mask
	mask.Parent = parent
	return mask
end

local function circle(
	name: string,
	parent: Instance,
	size: number,
	color: Color3,
	pos: UDim2,
	anchor: Vector2?
): Frame
	local f = frame(name, parent, color, 0)
	f.Size = UDim2.fromOffset(size, size)
	f.Position = pos
	f.AnchorPoint = anchor or Vector2.zero
	f.ZIndex = 3
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	return f
end

-- =============================================================================================
-- Construction
-- =============================================================================================

local function slotFrame(name: string, button: boolean?): GuiObject
	local parent = safeFrame :: Frame
	local obj: GuiObject
	if button then
		local b = Instance.new("TextButton")
		Text.raw(b, "")
		b.AutoButtonColor = false
		b.Selectable = false -- jamais la sélection de la manette (le stick fait marcher)
		b.BackgroundColor3 = Theme.Colors.Panel
		b.BackgroundTransparency = 0.12
		b.BorderSizePixel = 0
		b.ZIndex = 2
		obj = b
	else
		obj = frame(name, parent)
	end
	obj.Name = name
	Util.place(obj, SLOTS[name])
	if button then
		obj.Parent = parent
	end
	elements[name] = obj
	return obj
end

local function buildCoins()
	local f = slotFrame("coins")
	Util.chrome(f)
	local coin = circle("Coin", f, C.coins.icon, Theme.Colors.Gold, UDim2.fromOffset(16, 16))
	Util.chrome(coin, C.coins.icon // 2, Color3.fromRGB(200, 140, 30))
	circle("Shine", coin, 28, Color3.fromRGB(255, 240, 170), UDim2.fromScale(0.3, 0.3), Vector2.new(0.5, 0.5))
	refs.coinIcon = coin
	refs.coinAmount = Util.label({
		name = "Amount",
		parent = f,
		size = UDim2.fromOffset(316, 60),
		position = UDim2.fromOffset(112, 4),
		text = "0",
		textSize = C.coins.amount,
		font = Theme.Fonts.Number,
		align = Enum.TextXAlignment.Left,
	})
	refs.coinRate = Util.label({
		name = "Rate",
		parent = f,
		size = UDim2.fromOffset(316, 38),
		position = UDim2.fromOffset(112, 68),
		text = "",
		textSize = C.coins.rate,
		color = Theme.Colors.Gold,
		align = Enum.TextXAlignment.Left,
	})
end

local function buildFame()
	local f = slotFrame("fame")
	Util.chrome(f)
	refs.fameText = Util.label({
		name = "Fame",
		parent = f,
		size = UDim2.fromOffset(178, 44),
		position = UDim2.fromOffset(14, 6),
		text = "★ 0",
		textSize = C.fame.text,
		color = Theme.Colors.Gold,
		align = Enum.TextXAlignment.Left,
	})
	refs.friendsText = Util.label({
		name = "Friends",
		parent = f,
		size = UDim2.fromOffset(110, 44),
		position = UDim2.fromOffset(198, 6),
		text = "♥ 0",
		textSize = C.fame.text,
		color = Color3.fromRGB(255, 150, 190),
		align = Enum.TextXAlignment.Left,
	})
end

-- Mot de la puce Menu, en capitales : « Menu » seul est aussi le nom d'un bouton de la manette Xbox
-- (interdit sur console à côté d'un glyphe, tests/harness/Gamepad.audit) ; « MENU » se lit pareil
local function menuWord(): string
	return string.upper(Util.t("hud.menu"))
end

local function buildMenuChip()
	local b = slotFrame("menuChip", true) :: TextButton
	Util.chrome(b)
	refs.menuGlyph = Glyph.new(b, { gamepad = Enum.KeyCode.ButtonY, keyboard = Util.menuKey() }, {
		name = "Glyph",
		size = C.menuChip.glyph,
		position = UDim2.new(0, 16, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		zIndex = 4,
	})
	refs.menuLabel = Util.label({
		name = "Label",
		parent = b,
		size = UDim2.fromOffset(96, 64),
		position = UDim2.new(0, 74, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		text = menuWord(),
		textSize = C.menuChip.text,
		align = Enum.TextXAlignment.Left,
		-- « MENU » à 40 px mesure 97 px pour une boîte de 96 : l'ancien TextScaled le dessinait à 39
		-- (UI/Text, sorte "fit" : même image ; libellé redessiné par le lot B2, N18)
		fit = true,
	})
	local bang = circle("Bang", b, 36, Theme.Colors.Danger, UDim2.new(0, 174, 0.5, 0), Vector2.new(0, 0.5))
	bang.Visible = false
	Util.label({ name = "Text", parent = bang, text = "!", textSize = Layout.Text.Min, zIndex = 4 })
	refs.bang = bang
	local twins = frame("Twins", b, Color3.fromRGB(255, 120, 170), 0)
	twins.Size = UDim2.fromOffset(46, 40)
	twins.AnchorPoint = Vector2.new(0, 0.5)
	twins.Position = UDim2.new(0, 210, 0.5, 0)
	twins.ZIndex = 3
	twins.Visible = false
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 12)
	tc.Parent = twins
	refs.twinsText =
		Util.label({ name = "Text", parent = twins, text = "", textSize = Layout.Text.Min, zIndex = 4 })
	refs.twins = twins
	b.Activated:Connect(function()
		AudioController.play("Click")
		Util.safe("PanelController.toggleMenu", nil, PanelController.toggleMenu)
	end)
end

local function buildEventPill()
	local f = slotFrame("eventPill")
	Util.chrome(f, C.eventPill.text)
	refs.eventText = Util.label({
		name = "Text",
		parent = f,
		size = UDim2.new(1, -32, 1, -12),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		textSize = C.eventPill.text,
	})
	f.Visible = false
end

local function buildMegaBar()
	local f = slotFrame("megaBar")
	Util.chrome(f, 12)
	local fill = frame("Fill", f, Color3.fromRGB(255, 200, 60), 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 3
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 12)
	fc.Parent = fill
	refs.megaFill = fill
	refs.megaText = Util.label({
		name = "Text",
		parent = f,
		size = UDim2.new(1, -24, 1, -8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		textSize = C.megaBar.text,
		zIndex = 4,
	})
	f.Visible = false
end

local function buildGauge()
	local f = slotFrame("gauge")
	f.BackgroundTransparency = 1
	local icon = circle("Plop", f, C.gauge.icon, Color3.fromRGB(255, 170, 200), UDim2.fromOffset(0, 0))
	circle("Eye", icon, 8, Theme.Colors.Stroke, UDim2.fromScale(0.36, 0.42), Vector2.new(0.5, 0.5))
	circle("Eye2", icon, 8, Theme.Colors.Stroke, UDim2.fromScale(0.64, 0.42), Vector2.new(0.5, 0.5))
	refs.gaugeIcon = icon
	local bar = frame("Bar", f, Theme.Colors.Background, 0.15)
	bar.Size = UDim2.fromOffset(C.gauge.bar.w, C.gauge.bar.h)
	bar.Position = UDim2.new(1, 0, 0.5, 0)
	bar.AnchorPoint = Vector2.new(1, 0.5)
	Util.chrome(bar, C.gauge.bar.h // 2)
	local fill = frame("Fill", bar, Color3.fromRGB(255, 170, 90), 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 3
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.5, 0)
	fc.Parent = fill
	refs.gaugeFill = fill
	refs.gaugeBar = bar
	refs.gaugeText = Util.label({
		name = "Rest",
		parent = f,
		size = UDim2.new(0, C.gauge.bar.w, 1, 0),
		position = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		textSize = Layout.Text.Min,
		zIndex = 4,
	})
	refs.gaugeText.Visible = false
	f.Visible = false
end

local function buildGoalTracker()
	local f = slotFrame("goalTracker")
	Util.chrome(f)
	local jar = frame("Ring", f, Theme.Colors.Background, 0.1)
	jar.Size = UDim2.fromOffset(C.goalTracker.ring, C.goalTracker.ring)
	jar.Position = UDim2.fromOffset(16, 16)
	jar.ClipsDescendants = true
	jar.ZIndex = 3
	Util.chrome(jar, C.goalTracker.ring // 2, Color3.fromRGB(255, 120, 180))
	local fill = frame("Fill", roundMask(jar, 3), Color3.fromRGB(255, 120, 180), 0)
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.ZIndex = 3
	refs.goalFill = fill
	refs.goalRing = jar
	refs.goalTitle = Util.label({
		name = "Title",
		parent = f,
		size = UDim2.fromOffset(320, 42),
		position = UDim2.fromOffset(104, 8),
		text = Util.t("hud.goal.splorch"),
		textSize = C.goalTracker.title,
		align = Enum.TextXAlignment.Left,
	})
	refs.goalValue = Util.label({
		name = "Value",
		parent = f,
		size = UDim2.fromOffset(320, 40),
		position = UDim2.fromOffset(104, 56),
		textSize = C.goalTracker.value,
		color = Theme.Colors.TextDim,
		align = Enum.TextXAlignment.Left,
	})
end

local function statusIcon(parent: Instance, name: string, color: Color3): Frame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(C.status.icon, C.status.icon + 32)
	holder.Visible = false
	holder.ZIndex = 2
	local icon = circle("Icon", holder, C.status.icon, color, UDim2.fromOffset(0, 0))
	Util.chrome(icon, C.status.icon // 2)
	refs["status_" .. name] = icon
	refs["statusMin_" .. name] = Util.label({
		name = "Minutes",
		parent = holder,
		size = UDim2.fromOffset(C.status.icon, 32),
		position = UDim2.fromOffset(0, C.status.icon),
		textSize = C.status.minutes,
	})
	holder.Parent = parent
	return holder
end

local function buildStatus()
	local f = slotFrame("status")
	f.BackgroundTransparency = 1
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Padding = UDim.new(0, C.status.gap)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	local shield = statusIcon(f, "shield", Color3.fromRGB(110, 170, 255))
	shield.LayoutOrder = 1
	-- bouclier : losange (forme, pas seulement la couleur)
	local d = frame("Diamond", refs.status_shield, Color3.new(1, 1, 1), 0)
	d.Size = UDim2.fromOffset(28, 28)
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale(0.5, 0.5)
	d.Rotation = 45
	d.ZIndex = 4
	local boost = statusIcon(f, "boost", Theme.Colors.Gold)
	boost.LayoutOrder = 2
	-- « ×2 » bleu nuit sur l'or, sans contour : le contour bleu nuit d'Util.label (même couleur que
	-- les lettres) les fondait en une tache illisible (revue des écrans)
	local boostText = Util.label({
		name = "Text",
		parent = refs.status_boost,
		text = Util.t("hud.status.boost"),
		textSize = 36,
		color = Theme.Colors.Stroke,
		zIndex = 4,
	})
	local boostStroke = boostText:FindFirstChildOfClass("UIStroke")
	if boostStroke then
		boostStroke.Enabled = false
	end
	local mode = statusIcon(f, "mode", Color3.fromRGB(255, 120, 180))
	mode.LayoutOrder = 3
	-- Rush : un nez boopé (point) ; Cozy : un croissant de lune (forme différente)
	local nose = circle(
		"Nose",
		refs.status_mode,
		20,
		Color3.new(1, 1, 1),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	nose.ZIndex = 4
	local moon = circle(
		"Moon",
		refs.status_mode,
		30,
		Color3.new(1, 1, 1),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	moon.ZIndex = 4
	circle(
		"Bite",
		moon,
		26,
		Color3.fromRGB(120, 200, 160),
		UDim2.fromScale(0.72, 0.38),
		Vector2.new(0.5, 0.5)
	).ZIndex =
		5
	refs.statusNose = nose
	refs.statusMoon = moon
	refs.statusHolders = { shield = shield, boost = boost, mode = mode }
end

local function buildSpecialChip()
	local b = slotFrame("specialChip", true) :: TextButton
	Util.chrome(b)
	refs.specialGlyph = Glyph.new(b, HINT_BINDINGS.menu, {
		name = "Glyph",
		size = C.specialChip.glyph,
		position = UDim2.new(0, 20, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		zIndex = 4,
	})
	refs.specialGlyph2 = Glyph.new(b, { gamepad = Enum.KeyCode.ButtonR1 }, {
		name = "Glyph2",
		size = C.specialChip.glyph,
		position = UDim2.new(0, 84, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		zIndex = 4,
	})
	refs.specialGlyph2.frame.Visible = false
	refs.specialText = Util.label({
		name = "Text",
		parent = b,
		size = UDim2.new(1, -112, 0, 64),
		position = UDim2.new(0, 92, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		textSize = C.specialChip.text,
		font = Font.fromEnum(Enum.Font.LuckiestGuy),
		align = Enum.TextXAlignment.Left,
	})
	local ring = frame("ClapRing", b, Color3.fromRGB(255, 208, 72), 0)
	ring.AnchorPoint = Vector2.new(0, 1)
	ring.Position = UDim2.new(0, 16, 1, -6)
	ring.Size = UDim2.new(1, -32, 0, 6)
	ring.ZIndex = 4
	ring.Visible = false
	refs.clapRing = ring
	b.Activated:Connect(function()
		if specialMode == "clap" then
			HUD._clap()
		elseif specialMode == "splorch" then
			AudioController.play("Click")
			Util.safe("PanelController.openMenu", nil, PanelController.openMenu, "SplorchPreview")
		end
	end)
	b:SetAttribute("Mode", "")
	b.Visible = false
end

local function buildTargetCard()
	local f = slotFrame("targetCard")
	Util.chrome(f)
	local shape = frame("Rarity", f, Theme.Colors.Text, 0)
	shape.Size = UDim2.fromOffset(36, 36)
	shape.AnchorPoint = Vector2.new(0.5, 0.5)
	shape.Position = UDim2.fromOffset(40, 48)
	shape.ZIndex = 3
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.5, 0)
	sc.Parent = shape
	refs.targetShape = shape
	refs.targetCorner = sc
	refs.targetName = Util.label({
		name = "Name",
		parent = f,
		size = UDim2.fromOffset(596, 44),
		position = UDim2.fromOffset(72, 4),
		textSize = C.targetCard.name,
		align = Enum.TextXAlignment.Left,
	})
	refs.targetDetails = Util.label({
		name = "Details",
		parent = f,
		size = UDim2.fromOffset(596, 40),
		position = UDim2.fromOffset(72, 50),
		textSize = C.targetCard.details,
		color = Theme.Colors.TextDim,
		align = Enum.TextXAlignment.Left,
	})
	f.Visible = false
end

local function buildLeap()
	local f = slotFrame("leap")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local sweep = frame("Sweep", roundMask(f, 5), Theme.Colors.Stroke, 0.35)
	sweep.AnchorPoint = Vector2.new(0, 1)
	sweep.Position = UDim2.fromScale(0, 1)
	sweep.Size = UDim2.fromScale(1, 0)
	sweep.ZIndex = 5
	refs.leapSweep = sweep
	refs.leapGlyph = Glyph.new(f, HINT_BINDINGS.leap, {
		name = "Glyph",
		size = C.leap.glyph,
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		zIndex = 4,
	})
	f.Visible = false
end

local function buildMessage()
	local f = slotFrame("message")
	f.BackgroundTransparency = 1
end

local function build()
	local ok, safe = pcall(Root.safe, "HUD", DISPLAY_ORDER)
	if not ok then
		return
	end
	safeFrame = safe
	screen = safe.Parent :: ScreenGui
	buildCoins()
	buildFame()
	buildMenuChip()
	buildEventPill()
	buildMegaBar()
	buildGauge()
	buildMessage()
	buildGoalTracker()
	buildStatus()
	buildSpecialChip()
	buildTargetCard()
	buildLeap()
end

-- =============================================================================================
-- Données du profil
-- =============================================================================================

local function profile(keys: { string }): { [string]: any }
	local out = {}
	for _, key in keys do
		out[key] = State.get(key)
	end
	return out
end

local function boostActive(now: number): (boolean, number)
	local ev = eventState()
	if ev and type(ev.boost) == "table" and ev.boost.kind ~= "" then
		local untilT = Util.num(ev.boost.untilT, 0)
		if untilT > now then
			return true, untilT - now
		end
	end
	local boosts = Util.tbl(State.get("boosts"))
	local left = Util.num(boosts.personalLeft, 0, 0, 1e7)
	if left > 0 then
		return true, left
	end
	return false, 0
end

local function friendsCount(): number
	local n = 0
	for userId in friendsHere do
		local p = Players:GetPlayerByUserId(userId)
		if p and p.Parent then
			n += 1
		end
	end
	return n
end

local function incomeRate(now: number): number
	local tiles = Util.tbl(State.get("tiles"))
	local passes = Util.tbl(State.get("passes"))
	local dex = Util.tbl(State.get("dex"))
	local boost = boostActive(now)
	local ctx = {
		decor = Util.num(tiles.decor, 0, 0),
		friends = friendsCount(),
		fame = Util.num(State.get("fame"), 0, 0),
		trophyBonus = Util.safe(
			"Formulas.trophyBonus",
			0,
			Formulas.trophyBonus,
			Util.tbl(State.get("trophies"))
		),
		goldenPages = Util.safe("QuestRules.goldenPages", 0, QuestRules.goldenPages, dex),
		doubleCoins = passes.DoubleCoins == true,
		boost = boost,
	}
	local G = Util.safe("Formulas.G", 0, Formulas.G, State.get("growth"), now)
	local K, S1 = Formulas.ranchIncome(Util.tbl(State.get("squishies")), G, ctx :: any)
	return math.max(0, S1 + K * G)
end

-- =============================================================================================
-- Mises à jour
-- =============================================================================================

-- Défilement du compteur de pièces (0,5 s, Quint Out) calé sur Clock : jamais sur une horloge réelle
-- (les specs voyagent dans le temps), une seule animation à la fois (la nouvelle part de la valeur
-- affichée)
local coinRoll: { from: number, to: number, start: number }? = nil
local COIN_ROLL = 0.5

local function stepCoins(now: number)
	local roll = coinRoll
	local label = refs.coinAmount :: TextLabel?
	if roll == nil or label == nil then
		return
	end
	local alpha = math.clamp((now - roll.start) / COIN_ROLL, 0, 1)
	if now < roll.start then
		alpha = 1
	end
	local eased = 1 - (1 - alpha) ^ 5
	setText("coins", label, Util.big(roll.from + (roll.to - roll.from) * eased))
	if alpha >= 1 then
		coinRoll = nil
	end
end

local function updateCoins(value: any, old: any)
	local label = refs.coinAmount :: TextLabel?
	if label == nil then
		return
	end
	local to = Util.num(value, 0, 0)
	local from = coinsShown
	local roll = coinRoll
	if roll ~= nil then
		-- la nouvelle animation part de la valeur affichée maintenant
		local alpha = math.clamp((Clock.now() - roll.start) / COIN_ROLL, 0, 1)
		from = roll.from + (roll.to - roll.from) * (1 - (1 - alpha) ^ 5)
	end
	coinsShown = to
	local now = Clock.now()
	if to > from then
		if now - lastCoinSoundAt >= COIN_SOUND_GAP or now < lastCoinSoundAt then
			lastCoinSoundAt = now
			AudioController.play("Coin")
		end
	end
	if old == nil or Prefs.reducedMotion() or from == to then
		coinRoll = nil
		setText("coins", label, Util.big(to))
		return
	end
	-- défilement 0,5 s (Quint Out) + pop 1,15 quand elles montent
	coinRoll = { from = from, to = to, start = now }
	if to > from then
		-- pop du compteur 1,15 → 1 (GDD §9.2) ; la pièce dessinée rebondit aussi
		Juice.pulse(label, 1.15)
		if refs.coinIcon then
			Juice.pulse(refs.coinIcon, 1.1)
		end
	end
end

local function updateFame()
	setText("fame", refs.fameText, "★ " .. Util.big(Util.num(State.get("fame"), 0, 0)))
	setText("friends", refs.friendsText, "♥ " .. Format.count(friendsCount()))
end

local function computeBadges()
	local pending = Util.safe("Cards.pending", {}, Cards.pending)
	local bang = type(pending) == "table" and #pending > 0
	if not bang then
		-- objectif terminé et non réclamé : quelque chose à faire dans le menu
		local objectives = Util.tbl(State.get("objectives"))
		for _, o in Util.tbl(objectives.list) do
			if type(o) == "table" and o.done == true and o.claimed ~= true then
				bang = true
				break
			end
		end
	end
	local twins =
		Util.safe("FusionRules.twinPairs", 0, FusionRules.twinPairs, Util.tbl(State.get("squishies")))
	HUD.setMenuBadges(bang, Util.num(twins, 0, 0, 999))
end

local function eventPill(now: number): (string, Color3?)
	local f = features()
	if f == nil then
		return "", nil
	end
	local ev = eventState() or {}
	local rushOn = f.boopRush == "on"
	-- événement en cours (couleur)
	if rushOn then
		local rush = EventClock.rush(now)
		if rush.active then
			return Util.t("hud.now.rush", { time = Util.clock(rush.endsAt - now) }), EVENT_COLORS.rush
		end
	end
	if f.megaSquish == true then
		local mega = EventClock.mega(now)
		if mega.active then
			local endsAt = if now < mega.endsAt then mega.endsAt else mega.burstEndsAt
			return Util.t("hud.now.mega", { time = Util.clock(endsAt - now) }), EVENT_COLORS.mega
		end
	end
	if f.jellyMoon == true then
		local moon = EventClock.moon(now)
		if moon.active then
			return Util.t("hud.now.moon", { time = Util.clock(moon.endsAt - now) }), EVENT_COLORS.moon
		end
	end
	local boost = Util.tbl(ev.boost)
	local untilT = Util.num(boost.untilT, 0)
	if untilT > now then
		local key = if boost.kind == "wobble"
			then "hud.now.wobble"
			elseif boost.kind == "squish" then "hud.now.squish"
			elseif boost.kind == "admin" then "hud.now.admin"
			else nil
		if key then
			return Util.t(key, { time = Util.clock(untilT - now) }), EVENT_COLORS.party
		end
	end
	-- prochain événement
	local kinds =
		{ rush = rushOn, mega = f.megaSquish == true, golden = f.golden == true, moon = f.jellyMoon == true }
	local nxt = Util.safe("EventClock.nextEventOf", nil, EventClock.nextEventOf, now, kinds)
	if type(nxt) == "table" and type(nxt.kind) == "string" then
		return Util.t("hud.next." .. nxt.kind, { time = Util.clock(Util.num(nxt.at, now) - now) }),
			EVENT_COLORS.next
	end
	return "", nil
end

-- Un panneau est ouvert : sa fenêtre (1440 × 860 px TV, y 110-970) tranche le haut du HUD (pièces,
-- suivi du Grand Splorch, pastille d'événement : « 1,2… M » coupé à mi-hauteur). Ces éléments se
-- cachent entiers pendant le panneau ; le solde est déjà écrit dans le panneau là où il sert
-- (Ranch › Dalles) (revue des écrans)
local function panelCovering(): boolean
	return Util.safe("PanelController.isOpen", false, PanelController.isOpen) == true
end

-- Une carte bloquante (choix Rush / Cozy, « booped ») est au centre : la puce d'action dessous
-- serait tranchée par son bord bas ; elle se cache le temps de la carte (revue des écrans)
local function modalCovering(): boolean
	if panelCovering() then
		return true
	end
	local card = Util.safe("Cards.current", nil, Cards.current)
	return type(card) == "table" and card.blocking == true
end

local function updateEvents(now: number)
	local pill = elements.eventPill
	local text, color = eventPill(now)
	setText("event", refs.eventText, text)
	if pill and color then
		pill.BackgroundColor3 = color
	end
	setVisible(pill, text ~= "" and revealed.eventPill ~= false and not photo and not panelCovering())

	local f = features()
	local ev = eventState()
	-- barre du MEGA : pendant la pression
	local megaOn = false
	if f and f.megaSquish == true then
		local mega = EventClock.mega(now)
		if mega.active and now < mega.endsAt then
			megaOn = true
			local m = if ev then Util.tbl(ev.mega) else {}
			local points = Util.num(refs.megaPoints or m.points, 0, 0)
			local target = math.max(1, Util.num(refs.megaTarget or m.target, 1, 1))
			local fill = refs.megaFill :: Frame
			local k = math.clamp(points / target, 0, 1)
			if math.abs(fill.Size.X.Scale - k) > 0.001 then
				Juice.tween(
					fill,
					0.3,
					{ Size = UDim2.fromScale(k, 1) },
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				)
			end
			setText(
				"mega",
				refs.megaText,
				Util.t("hud.mega.bar", { points = Util.big(points), target = Util.big(target) })
					.. " · "
					.. Util.clock(mega.endsAt - now)
			)
		else
			refs.megaPoints, refs.megaTarget = nil, nil
		end
	end
	setVisible(elements.megaBar, megaOn and revealed.megaBar ~= false and not photo)

	-- jauge du serveur (hors MEGA) ; grise pendant la sieste de Big Plop
	local gaugeOn = f ~= nil and f.gauge == true and not megaOn and ev ~= nil
	if gaugeOn and ev then
		local g = Util.tbl(ev.gauge)
		local points = Util.num(g.points, 0, 0)
		local target = math.max(1, Util.num(g.target, 1, 1))
		local restUntil = Util.num(g.restUntil, 0)
		local partyUntil = Util.num(g.partyUntil, 0)
		local resting = restUntil > now
		local fill = refs.gaugeFill :: Frame
		local k = if partyUntil > now then 1 else math.clamp(points / target, 0, 1)
		fill.Size = UDim2.fromScale(k, 1)
		fill.BackgroundColor3 = if resting then GREY else Color3.fromRGB(255, 170, 90);
		(refs.gaugeIcon :: Frame).BackgroundColor3 = if resting then GREY else Color3.fromRGB(255, 170, 200)
		local label = refs.gaugeText :: TextLabel
		if resting then
			setText("gauge", label, Util.t("hud.gauge.rest", { time = Util.clock(restUntil - now) }))
		end
		setVisible(label, resting)
		setVisible(refs.gaugeFill, not resting)
		elements.gauge:SetAttribute("Resting", resting)
	end
	setVisible(elements.gauge, gaugeOn and revealed.gauge ~= false and not photo)
end

local function queueEntry(): { [string]: any }?
	local ev = eventState()
	if ev == nil then
		return nil
	end
	local spectacle = Util.tbl(ev.spectacle)
	local me = localUserId()
	for _, entry in Util.tbl(spectacle.queue) do
		if type(entry) == "table" and entry.kind == "splorch" and entry.userId == me then
			return entry
		end
	end
	return nil
end

local function updateGoal(now: number): boolean
	local preview = Util.safe(
		"Formulas.splorchPreview",
		nil,
		Formulas.splorchPreview,
		profile({ "R", "growth", "squishies", "coins", "pot" }),
		{ now = now, unix = Clock.unix() }
	)
	local ready = false
	local value = ""
	local k = 0
	local entry = queueEntry()
	if entry then
		local position = math.floor(Util.num(entry.position, 1, 1, 99))
		local eta = Util.num(entry.eta, 0, 0, 3600) - math.max(0, now - lastEventAt)
		local time = Util.clock(eta)
		value = if position <= 1
			then Util.t("hud.queue.next", { time = time })
			else Util.t("hud.queue.place", { n = position, time = time })
		k = 1
	elseif type(preview) == "table" then
		local target = math.max(1, Util.num(preview.target, 1, 1))
		local biggest = Util.num(preview.biggest, 0, 0)
		ready = preview.ready == true
		k = math.clamp(biggest / target, 0, 1)
		value = if ready
			then Util.t("hud.goal.ready")
			else Util.t("common.ratio", { have = Util.big(biggest), need = Util.big(target) })
	end
	setText("goal", refs.goalValue, value)
	local fill = refs.goalFill :: Frame?
	if fill and math.abs(fill.Size.Y.Scale - k) > 0.002 then
		fill.Size = UDim2.fromScale(1, k)
	end
	local tracker = elements.goalTracker
	if tracker then
		tracker:SetAttribute("Ready", ready)
		tracker:SetAttribute("Queued", entry ~= nil)
	end
	return ready and entry == nil
end

local function updateStatus(now: number)
	local holders = refs.statusHolders
	if holders == nil then
		return
	end
	local ranch = myRanch()
	local stats = Util.tbl(State.get("stats"))
	local shield = type(ranch) == "table" and ranch.shield == true
	local shieldLeft = math.max(0, Events.Rush.ShieldPlaySeconds - Util.num(stats.playSeconds, 0, 0))
	setVisible(holders.shield, shield)
	setText(
		"statusMin_shield",
		refs.statusMin_shield,
		-- au moins « 1′ » tant que le serveur dit le bouclier actif (le temps de jeu local peut déjà
		-- dépasser la limite avant que le ranch suivant arrive : jamais « 0′ » sous un indicateur visible)
		if shield then Format.count(math.max(1, math.ceil(shieldLeft / 60))) .. "′" else ""
	)
	local boost, left = boostActive(now)
	setVisible(holders.boost, boost)
	setText(
		"statusMin_boost",
		refs.statusMin_boost,
		if boost then Format.count(math.ceil(left / 60)) .. "′" else ""
	)
	local rush = if type(ranch) == "table"
		then ranch.mode == "rush"
		else Util.tbl(State.get("mode")).rush == true
	setVisible(refs.statusNose, rush)
	setVisible(refs.statusMoon, not rush);
	(refs.status_mode :: Frame).BackgroundColor3 = if rush
		then Color3.fromRGB(255, 120, 180)
		else Color3.fromRGB(120, 200, 160)
	setText("statusMin_mode", refs.statusMin_mode, "")
	setVisible(holders.mode, true)
	elements.status:SetAttribute("Mode", if rush then "rush" else "cozy")
	setVisible(elements.status, revealed.status ~= false and not photo)
end

-- Maintien en cours (boop, bol, dalle) : la puce APPLAUDIR se cache
local function holding(now: number): boolean
	for _, endsAt in holds do
		if now <= endsAt + HOLD_GRACE then
			return true
		end
	end
	local me = localUserId()
	local boops = Util.safe("WorldStateController.boops", nil, WorldStateController.boops)
	if type(boops) == "table" then
		for _, b in boops do
			if
				type(b) == "table"
				and b.booperId == me
				and b.state == "hold"
				and now <= Util.num(b.endsAt, 0) + HOLD_GRACE
			then
				return true
			end
		end
	end
	return false
end

-- La puce APPLAUDIR est-elle cachée (poursuite, maintien, fenêtre ouverte) ?
local function clapHidden(now: number): boolean
	if Util.safe("FocusGuard.anyOpen", false, FocusGuard.anyOpen) then
		return true
	end
	if holding(now) then
		return true
	end
	return Chase.inChase(now)
end

local function updateSpecial(now: number, splorchReady: boolean)
	local chip = elements.specialChip :: TextButton?
	if chip == nil then
		return
	end
	local c = clap
	if c and now >= c.endsAt then
		clap = nil
		c = nil
	end
	local mode = ""
	if c and not clapHidden(now) then
		mode = "clap"
	elseif hint ~= nil and hint.action ~= "menu" then
		-- la leçon du menu est portée par la puce Menu elle-même (attention), pas par cette puce
		mode = "hint"
	elseif splorchReady and revealed.menuChip ~= false then
		mode = "splorch"
	end
	if mode ~= specialMode then
		specialMode = mode
		local g = refs.specialGlyph :: Glyph.Handle
		local g2 = refs.specialGlyph2 :: Glyph.Handle
		local size = if mode == "hint" then Layout.Glyph.Prompt else C.specialChip.glyph
		g.frame.Size = UDim2.fromOffset(size, size)
		g2.frame.Visible = false
		if mode == "clap" then
			g:set(HINT_BINDINGS.clap)
			setText("special", refs.specialText, Util.t("hud.special.clap"))
		elseif mode == "splorch" then
			g:set({ gamepad = Enum.KeyCode.ButtonY, keyboard = Util.menuKey() })
			setText("special", refs.specialText, Util.t("hud.special.splorch"))
		elseif mode == "hint" and hint then
			local binding = HINT_BINDINGS[hint.action or ""] or HINT_BINDINGS.action
			if hint.action == "menu" then
				binding = { gamepad = Enum.KeyCode.ButtonY, keyboard = Util.menuKey() }
			end
			g:set(binding)
			if hint.action == "target" then
				g2:set({ gamepad = Enum.KeyCode.ButtonR1 })
			end
			setText("special", refs.specialText, Util.t(hint.key))
		end
		chip:SetAttribute("Mode", mode)
	end
	if mode == "hint" and hint and hint.action == "target" then
		local g2 = refs.specialGlyph2 :: Glyph.Handle
		g2.frame.Visible = (refs.specialGlyph :: Glyph.Handle):shown()
	end
	-- anneau de 8 s de la fenêtre APPLAUDIR
	local ring = refs.clapRing :: Frame
	if mode == "clap" and c then
		local k = math.clamp((c.endsAt - now) / CLAP_SECONDS, 0, 1)
		ring.Size = UDim2.new(k, -32 * k, 0, 6)
		setVisible(ring, true)
	else
		setVisible(ring, false)
	end
	-- le texte se décale quand le glyphe est plus large (consigne 64 px, glyphe double L1 R1)
	local g = refs.specialGlyph :: Glyph.Handle
	local left = 20 + math.max(g.frame.Size.X.Offset, C.specialChip.glyph) + 16
	if mode == "hint" and hint and hint.action == "target" then
		local g2 = refs.specialGlyph2 :: Glyph.Handle
		g2.frame.Position = UDim2.new(0, left - 8, 0.5, 0)
		left += g2.frame.Size.X.Offset + 8
	end
	local text = refs.specialText :: TextLabel
	text.Position = UDim2.new(0, left, 0.5, 0)
	text.Size = UDim2.new(1, -(left + 20), 0, 64)
	setVisible(chip, mode ~= "" and revealed.specialChip ~= false and not photo and not modalCovering())
end

local function updateTarget(now: number)
	local card = elements.targetCard
	if card == nil then
		return
	end
	local target = Util.safe("PromptController.current", nil, PromptController.current)
	local shown = false
	if type(target) == "table" and target.kind == "squishy" then
		local slot = Util.num(target.slot, 0, 0, 64)
		local uid = Util.str(target.uid, "", 16)
		local list = Util.safe("WorldStateController.squishies", nil, WorldStateController.squishies, slot)
		local rec = if type(list) == "table" and uid ~= "" then list[uid] else nil
		if type(rec) == "table" then
			shown = true
			local def = Species.ById[Util.num(rec.s, 0)]
			local rarity = Rarities.List[if def then def.rarity else 1] or Rarities.List[1]
			setText("targetName", refs.targetName, Util.speciesName(rec.s))
			local size = Util.num(
				Util.safe("WorldStateController.sizeOf", nil, WorldStateController.sizeOf, slot, uid, now),
				Util.num(rec.z, 1, 1)
			)
			local parts = {}
			local mutation = Util.mutationName(rec.m)
			if Util.num(rec.m, 0) > 0 and mutation ~= "" then
				table.insert(parts, mutation)
			end
			local stars = math.floor(Util.num(rec.st, 0, 0, 5))
			if stars > 0 then
				table.insert(parts, Util.t("common.stars", { n = stars }))
			end
			table.insert(parts, Util.t("common.size", { size = Util.big(size) }))
			if slot == mySlot() then
				local G = Util.safe("Formulas.G", 0, Formulas.G, State.get("growth"), now)
				local own = Util.tbl(State.get("squishies"))[uid]
				if type(own) == "table" then
					local income = Util.safe(
						"Formulas.income",
						0,
						Formulas.income,
						Formulas.sizeAt(own, G),
						own.s,
						own.m,
						own.st,
						{
							decor = 0,
							friends = 0,
							fame = 0,
							trophyBonus = 0,
							goldenPages = 0,
							doubleCoins = false,
							boost = false,
						}
					)
					table.insert(parts, Util.t("common.perSecond", { rate = Util.big(income) }))
				end
			end
			setText("targetDetails", refs.targetDetails, table.concat(parts, " · "))
			local shape = refs.targetShape :: Frame
			shape.BackgroundColor3 = rarity.color
			-- forme par rareté (daltoniens) : rond, losange, carré arrondi
			local r = rarity.id
			shape.Rotation = if r == 2 or r == 5 then 45 else 0
			(refs.targetCorner :: UICorner).CornerRadius = if r == 1
					or r == 4
					or r == 7
				then UDim.new(0.5, 0)
				else UDim.new(0, 8)
			card:SetAttribute("Uid", uid)
		end
	end
	-- bas du panneau (y 970) sur la carte de la cible (y 930-1026) : cachée entière pendant un panneau
	setVisible(card, shown and revealed.targetCard ~= false and not photo and not panelCovering())
end

local function updateLeap(now: number)
	local f = elements.leap
	if f == nil then
		return
	end
	local left =
		Util.num(Util.safe("ChaseController.cooldownLeft", 0, ChaseController.cooldownLeft), 0, 0, 60)
	local cooling = left > 0
	local sweep = refs.leapSweep :: Frame
	local cooldown = math.max(0.1, Util.num(Balance.Leap.Cooldown, 4, 0.1, 60))
	sweep.Size = UDim2.fromScale(1, math.clamp(left / cooldown, 0, 1))
	if leapWasCooling and not cooling and f.Visible and not Prefs.reducedMotion() then
		Juice.pulse(f, 1.15) -- prêt
	end
	leapWasCooling = cooling
	local inTown = false
	local pos = Util.rootPos()
	local slot = mySlot()
	if pos and slot > 0 then
		inTown = not WorldLayout.inRanch(slot, pos :: Vector3)
	end
	local feats = features() or {}
	local eventOn = (feats.boopRush == "on" and EventClock.rush(now).active)
		or (feats.golden == true and EventClock.golden(now).active)
	local lesson = hint ~= nil and hint.action == "leap"
	local visible = cooling or lesson or (inTown and eventOn)
	setVisible(f, visible and revealed.leap ~= false and not photo)
end

local function updateMenuChip()
	local menuOpen = Util.safe("PanelController.menuOpen", false, PanelController.menuOpen) == true
	setVisible(elements.menuChip, revealed.menuChip ~= false and not menuOpen and not photo)
	-- le rail peut remonter jusqu'à la pastille Fame en 720p (8 entrées) : elle s'efface pendant le menu
	setVisible(elements.fame, revealed.fame ~= false and not menuOpen and not photo)
	local covered = panelCovering()
	setVisible(elements.coins, revealed.coins ~= false and not photo and not covered)
	setVisible(elements.goalTracker, revealed.goalTracker ~= false and not photo and not covered)
end

-- Bouton qui attire l'attention (GDD §9.2) : pulsation UIScale 1 → 1,08 en sinus de 0,8 s sur la puce
-- GRAND SPLORCH ! / consigne et sur la puce Menu pendant sa leçon ; rien en Mouvement réduit
local ATTENTION_PERIOD = 0.8
local ATTENTION_AMOUNT = 0.08
local attentionOn: { [GuiObject]: boolean } = {}

local function stepAttention(now: number)
	local reduced = Prefs.reducedMotion()
	local wanted: { [GuiObject]: boolean } = {}
	local chip = elements.specialChip
	if chip and chip.Visible and (specialMode == "splorch" or specialMode == "hint") then
		wanted[chip] = true
	end
	local menu = elements.menuChip
	if menu and menu.Visible and hint ~= nil and hint.action == "menu" then
		wanted[menu] = true
	end
	local phase = (now % ATTENTION_PERIOD) / ATTENTION_PERIOD
	local scale = 1 + ATTENTION_AMOUNT * (0.5 - 0.5 * math.cos(2 * math.pi * phase))
	for obj in wanted do
		if not reduced then
			Juice.scaleOf(obj).Scale = scale
			attentionOn[obj] = true
		end
	end
	for obj in attentionOn do
		if not wanted[obj] or reduced then
			attentionOn[obj] = nil
			Juice.scaleOf(obj).Scale = 1
		end
	end
end

local function refreshTexts()
	table.clear(texts)
	setText("menu", refs.menuLabel, menuWord())
	setText("goalTitle", refs.goalTitle, Util.t("hud.goal.splorch"))
	specialMode = "?" -- force la réécriture de la puce spéciale
	updateFame()
	coinRoll = nil
	setText("coins", refs.coinAmount, Util.big(coinsShown))
end

local function refresh(now: number)
	stepCoins(now)
	updateMenuChip()
	updateFame()
	updateEvents(now)
	local ready = updateGoal(now)
	updateStatus(now)
	updateSpecial(now, ready)
	updateTarget(now)
	updateLeap(now)
	setText("rate", refs.coinRate, Util.t("common.perSecond", { rate = Util.big(incomeRate(now)) }))
	Messages.step(now)
end

-- =============================================================================================
-- Remotes et signaux
-- =============================================================================================

local function catcherName(d: { [string]: any }): string
	local name = Util.str(d.catcherName, "", 100)
	if name ~= "" then
		return name
	end
	local id = Util.num(d.catcherId, 0, 0, 2 ^ 53)
	-- nom caché : « au Ranch 7 » si son ranch est connu, sinon l'alias
	for slot = 1, 16 do
		local ranch = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
		if type(ranch) == "table" and ranch.userId == id and id > 0 then
			return Util.t("name.ranch", { n = slot })
		end
	end
	return Util.displayName(id, "")
end

local COIN_KINDS: { [string]: boolean } = {
	press = true,
	pot = true,
	tile = true,
	fusion = true,
	catch = true,
	megaResult = true,
}

local function onCelebrate(payload: any)
	if type(payload) ~= "table" or type(payload.data) ~= "table" then
		return
	end
	local kind = payload.kind
	local d = payload.data
	if kind == "ownerReturn" then
		-- le retour d'abord ; vibration douce et positive
		Haptics.play("squishyBack")
		Messages.push(
			Util.t("feedback.ownerReturn", {
				name = Util.speciesName(d.species),
				coins = Util.big(Util.num(d.coins, 0, 0)),
				catcher = catcherName(d),
			}),
			"reward"
		)
	elseif kind == "returnedBigger" then
		Haptics.play("squishyBack")
		Messages.push(Util.t("feedback.returnedHome", { name = Util.speciesName(d.species) }), "reward")
	elseif kind == "saddle" then
		Messages.push(Util.t("celebrate.saddle"), "reward")
	elseif kind == "unlock" then
		local key = "cosmetic." .. Util.str(d.kind, "", 20) .. "." .. Util.str(d.id, "", 40)
		if Util.has(key) then
			Messages.push(Util.t("celebrate.unlock", { name = Prefs.t(key) }), "reward")
		end
	elseif kind == "purchase" then
		Messages.push(Util.t("celebrate.thanks"), "reward")
	elseif kind == "clapCount" then
		Messages.push(Util.t("celebrate.clapCount", { n = math.floor(Util.num(d.n, 0, 0, 99)) }), "reward")
	elseif kind == "objectiveDone" then
		AudioController.play("ObjectiveDone")
		if elements.goalTracker and not Prefs.reducedMotion() then
			Juice.pulse(elements.goalTracker, 1.1)
		end
	elseif kind == "photo" then
		photo = d.on == true
		local gui = screen
		if gui then
			gui.Enabled = not photo
		end
		-- vignettes : aucun message à l'écran pendant le mode photo (ils attendent, puis s'affichent)
		Messages.hold("photo", photo)
	elseif COIN_KINDS[kind] then
		refreshAcc = math.huge -- revenu et suivi recalculés à l'image suivante
	end
end

local function onFeedback(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local key = payload.key
	if not Util.has(key) then
		return
	end
	local tone = payload.tone
	if
		tone ~= "info"
		and tone ~= "success"
		and tone ~= "warning"
		and tone ~= "error"
		and tone ~= "reward"
	then
		tone = "info"
	end
	Messages.push(Prefs.t(key, Util.vars(payload.vars)), tone)
end

local function onClapPrompt(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local heroId = Util.num(payload.heroId, 0, 0, 2 ^ 53)
	local endsAt = Util.num(payload.endsAt, 0)
	local now = Clock.now()
	if heroId <= 0 or heroId == localUserId() or endsAt <= now then
		return
	end
	-- jamais plus long que la fenêtre de 8 s, même avec une heure de fin abîmée
	clap = { heroId = math.floor(heroId), endsAt = math.min(endsAt, now + CLAP_SECONDS) }
	refreshAcc = math.huge
end

local function onHoldState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	if kind ~= "feed" and kind ~= "tile" then
		return
	end
	if payload.active == true then
		local now = Clock.now()
		holds[kind] = math.min(Util.num(payload.endsAt, now), now + 10)
	else
		holds[kind] = nil
	end
end

local function watchFriends()
	local me = Players.LocalPlayer
	if me == nil then
		return
	end
	local function check(p: Player)
		if p == me then
			return
		end
		task.spawn(function()
			local ok, friend = pcall(function()
				return me:IsFriendsWith(p.UserId)
			end)
			if ok and friend == true and p.Parent ~= nil then
				friendsHere[p.UserId] = true
				updateFame()
			end
		end)
	end
	Players.PlayerAdded:Connect(check)
	Players.PlayerRemoving:Connect(function(p: Player)
		friendsHere[p.UserId] = nil
		task.defer(updateFame)
	end)
	for _, p in Players:GetPlayers() do
		check(p)
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function HUD.Init()
	if initialized then
		return
	end
	initialized = true
	build()
	Messages.TopY = SLOTS.message.rect.y - Layout.Safe.y
end

-- L'écran de chargement se ferme (attribut local ClientReady) quand le HUD est construit ET que le
-- profil est arrivé : un chargement qui traîne garde l'écran de chargement et son « Réessayer »
-- (Main.client pose aussi l'attribut en filet dès l'instantané)
local function markReady()
	local player = Players.LocalPlayer
	if player and player:GetAttribute("ClientReady") ~= true then
		player:SetAttribute("ClientReady", true)
	end
end

-- Connexions et boucles
function HUD.Start()
	if started then
		return
	end
	started = true
	HUD.Init()
	if screen ~= nil then
		if State.ready then
			markReady()
		else
			State.ReadySignal:Once(markReady)
		end
	end
	State.observe("coins", updateCoins)
	for _, key in { "squishies", "objectives" } do
		State.observe(key, function()
			computeBadges()
		end)
	end
	State.observe("fame", function()
		updateFame()
	end)
	Cards.Changed:Connect(computeBadges)
	Net.event("Celebrate").OnClientEvent:Connect(onCelebrate)
	Net.event("Feedback").OnClientEvent:Connect(onFeedback)
	Net.event("ClapPrompt").OnClientEvent:Connect(onClapPrompt)
	Net.event("HoldState").OnClientEvent:Connect(onHoldState)
	WorldStateController.EventChanged:Connect(function()
		lastEventAt = Clock.now()
		refreshAcc = math.huge
	end)
	WorldStateController.MegaBeat:Connect(function(beat: any)
		if type(beat) == "table" then
			refs.megaPoints = Util.num(beat.points, 0, 0)
			refs.megaTarget = Util.num(beat.target, 1, 1)
		end
	end)
	Prefs.LanguageChanged:Connect(refreshTexts)
	Platform.Changed:Connect(function()
		if refs.menuGlyph then
			(refs.menuGlyph :: Glyph.Handle):set({ gamepad = Enum.KeyCode.ButtonY, keyboard = Util.menuKey() })
		end
		specialMode = "?"
	end)
	watchFriends()
	local player = Players.LocalPlayer
	if player then
		local function onUnstable()
			local unstable = player:GetAttribute("Unstable") == true
			if unstable and not unstableShown then
				Messages.push(Util.t("hud.unstable"), "warning")
			end
			unstableShown = unstable
		end
		player:GetAttributeChangedSignal("Unstable"):Connect(onUnstable)
	end
	-- appareil tactile inattendu : aucun contrôle ajouté, un message une fois (docs/04 §14.7)
	if Platform.inputKind() == Platform.TOUCH and not touchShown then
		touchShown = true
		Messages.push(Util.t("device.touch"), "info")
	end
	computeBadges()
	RunService.Heartbeat:Connect(function(dt: number)
		stepCoins(Clock.now())
		stepAttention(Clock.now())
		refreshAcc += Util.num(dt, 0, 0, 1)
		if refreshAcc >= REFRESH then
			refreshAcc = 0
			refresh(Clock.now())
		end
	end)
	refresh(Clock.now())
end

-- Montre ou cache un élément (accueil) ; "all" pour tous
function HUD.reveal(element: string, visible: boolean)
	if type(element) ~= "string" then
		return
	end
	local v = visible == true
	local changedAny = false
	if element == "all" then
		for name in SLOTS do
			if revealed[name] ~= v then
				revealed[name] = v
				changedAny = true
			end
		end
	elseif SLOTS[element] ~= nil and revealed[element] ~= v then
		revealed[element] = v
		changedAny = true
	end
	if changedAny then
		refreshAcc = math.huge
	end
end

-- Consigne du moment dans la place de la puce spéciale (accueil) : action = glyphe montré ("action",
-- "pickup", "leap", "ride", "menu", "move", "target"), textKey = mot court ; nil : consigne retirée
function HUD.setHint(action: string?, textKey: string?)
	if type(textKey) ~= "string" or not Util.has(textKey) then
		if hint ~= nil then
			hint = nil
			specialMode = "?"
		end
		refreshAcc = math.huge
		return
	end
	local a = if type(action) == "string" and HINT_BINDINGS[action] ~= nil then action else nil
	if hint == nil or hint.action ~= a or hint.key ~= textKey then
		hint = { action = a, key = textKey :: string }
		specialMode = "?"
	end
	refreshAcc = math.huge
end

-- Pastilles de la puce Menu : « ! » (action possible, carte en attente) et « ♥ N » (paires de jumeaux)
function HUD.setMenuBadges(bang: boolean, twins: number)
	badgeBang = bang == true
	badgeTwins = math.floor(Util.num(twins, 0, 0, 999))
	setVisible(refs.bang, badgeBang)
	setVisible(refs.twins, badgeTwins > 0)
	setText("twins", refs.twinsText, Util.t("hud.twins", { n = badgeTwins }))
	local chip = elements.menuChip
	if chip then
		chip:SetAttribute("Bang", badgeBang)
		chip:SetAttribute("Twins", badgeTwins)
	end
end

-- Élément du HUD (specs de disposition) : noms de Config/Layout.Hud ("card" : carte de UI/Cards)
function HUD.element(name: string): GuiObject?
	if name == "card" then
		return Util.safe("Cards.frame", nil, Cards.frame, "side")
	end
	return elements[name]
end

-- Héros de la fenêtre APPLAUDIR ouverte (ClapPrompt, 8 s) ou nil : InputController transforme alors
-- croix → en Clap(heroId). nil aussi quand la puce est cachée (poursuite, maintien, fenêtre ouverte)
function HUD.clapHero(): number?
	local c = clap
	local now = Clock.now()
	if c == nil or now >= c.endsAt then
		return nil
	end
	if clapHidden(now) then
		return nil
	end
	return c.heroId
end

-- Applaudir (croix → , F, clic sur la puce) : une fois par fenêtre
function HUD._clap(): boolean
	local hero = HUD.clapHero()
	if hero == nil then
		return false
	end
	if Util.send("Clap", hero) then
		AudioController.play("Click")
		clap = nil
		refreshAcc = math.huge
		return true
	end
	return false
end

-- Un tour de mise à jour tout de suite (specs ; la boucle par image fait de même)
function HUD._refresh()
	refresh(Clock.now())
end

-- Élément visible (specs)
function HUD.visible(name: string): boolean
	local e = elements[name]
	return e ~= nil and e.Visible
end

return HUD
