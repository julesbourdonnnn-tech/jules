--!strict
-- HUD — paquet « client-hud » (docs/04-architecture.md §13.12).
-- Interface de jeu permanente (§10.2), construite en code dans Root.safe("HUD"), affichage
-- progressif piloté par OnboardingController.
-- Responsabilités :
--   * pastille Glow (16, 16 ; 260 × 64) : valeur PRÉDITE glow + idleRate × (Clock.now() − lastSettle)
--     + glowCarry (Hud/Glow), défilement countTo 0,5 s Quint Out + pop sur gain, défilement continu
--     sans pop pour le revenu passif, « +1,2K/s » ; pastille Stardust (16, 88 ; apparaît à Q4)
--   * compteur de file (bas centre, 360 × 56) : « 7/15 », barre, « ×1,48 » (Formulas.congaBonus),
--     vide « Attrape des Nebbies ! », pop 1,15 à la capture, 2 clignotements rouges + flèche vers le
--     Nid (Feedback lineFull ; le tampon « PLEINE » est joué par ScreenFX), icône bouclier débutant
--   * bouton Dash (112 × 112, au-dessus à gauche du bouton de saut tactile lu dans
--     TouchGui.TouchControlFrame.JumpButton — recherche bornée et non bloquante, décalage −16 px ;
--     PC/manette : bas droite) avec balayage radial de recharge et pop + éclair au retour ; bouton
--     Ping (72 × 72) à sa gauche ; sur les écrans bas (téléphones de 360-390 dp), la colonne de
--     droite (état, suivi de quête) passe à gauche de la minicarte si le Dash la recouvrirait
--   * pastille d'événement (haut centre, 320 × 48 ; Hud/EventPill) : prochain événement avec compte à
--     rebours, événement en cours en couleur, « ☄ COMÈTE 0:45 — Mira », barre de la Balise (420 × 28) ;
--     sur les écrans étroits (640 × 360, 667 × 375) elle glisse à droite d'Équipage / Réglages sans
--     toucher la minicarte (pillGeometry)
--     ; indicateurs d'état (Zen, boost ×2 avec minuteur, connexion instable) ; suivi de quête
--     (260 × 72, repliable : icône + titre de 200 px jamais sous 18 px, barre + bouton de repli
--     dessous ; coût de la Supernova abrégé s'il ne tient pas) ; icônes Équipage et Réglages
--   * crochets de ScreenFX : cibles des pièces (HUD.anchor), panneau ouvert, place libre des cartes
--     « NOUVEAU ! » (cardPlacement : colonne de droite sous la minicarte, l'état et le suivi, jamais
--     sur le Dash, le Ping ni le bouton de saut ; zone sûre de l'appareil comprise)
--   * rail de menus (gauche, y 150-470, 4 boutons 80 × 80) : Améliorer, Collection, Objectifs,
--     Boutique → InputController.togglePanel (PanelController) ; pastille « ! » (hasAction /
--     BadgeChanged) ; sur les écrans bas (téléphones de 360-390 dp) où la colonne descendrait dans
--     le quart inférieur (joystick dynamique, GDD §10.1), grille 2 × 2 (168 × 168 dès y = 144),
--     navigation manette recâblée sur les boutons affichés
--   * bouton ACCLAMER (200 × 88, 10 s, anneau de temps) : propriétaire du remote CheerPrompt,
--     envoie Cheer(heroId) (appui, F ou croix droite : InputController.CheerRequested)
--   * icône « connexion instable » (attribut Player « Unstable »)
--   * pose l'attribut LOCAL Players.LocalPlayer « ClientReady » = true quand l'instantané est reçu et
--     le HUD construit (fin de l'écran de chargement)
--   * tous les boutons : Juice.press, Selectable, cadre de sélection Root.selectionImage, navigation
--     manette explicite ; textes via Prefs.t, ré-appliqués sur Prefs.LanguageChanged
--   * console / manette (docs/07-console-ps5.md §5-§7) : icônes de touches UI/Glyph « PadGlyph »
--     (R2 Dash, croix ↑ Ping, croix ↓ minicarte, croix → ACCLAMER, croix ← suivi de quête, △ au-dessus
--     du rail), touches clavier « KeyCap » masquées à la manette ; △ (HUD.selectRail) sélectionne la
--     carte d'invitation d'équipage (PanelController.focusTarget(), passagère), sinon la cible de
--     l'accueil, sinon le bouton du rail à pastille « ! », sinon le dernier panneau du rail ouvert,
--     sinon le premier bouton affiché ; graphe
--     NextSelection* complet (rail, Équipage, Réglages, minicarte, suivi de quête, Ping, Dash,
--     ACCLAMER) posé à la manette ; croix ← (InputController.QuestToggled) replie le suivi ; main
--     d'accueil remplacée par l'icône de la touche (△, puis ✕ une fois le bouton sélectionné ; R2 sur
--     le Dash) ; rail en colonne sur console (pas de joystick tactile) ; mode menu (sélection dans
--     le HUD ou la minicarte, le stick ne fait plus marcher) : l'icône au-dessus du rail devient ○
--     avec « Jouer » / « Play » à côté (RailHint, manette seulement) : ○ rend la main au jeu
--     (InputController) ; sélection effacée ou partie ailleurs → △ revient, libellé masqué
--   * écran de chargement encore là (ScreenGui « Loading ») : HUD.selectRail ne sélectionne rien
-- Une seule connexion RenderStepped ; le temps d'animation est la somme des dt des images (mesure
-- purement graphique), le temps de jeu vient de Shared/Util/Clock.
-- GDD : §3 (HUD progressif), §6.6 (acclamer), §9.2, §10.1, §10.2.
-- Dépendances : StateController, AudioController, Util/Prefs, Util/Platform, UI/Root, UI/Theme,
-- UI/Create, UI/Juice, UI/Glyph, WorldStateController, ScreenFX, Banners, PanelController,
-- InputController, Logic/Formulas, Logic/EventClock, Config/*, Shared/Net, Shared/Util/Clock.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Format = require(Shared.Util.Format)
local Balance = require(Shared.Config.Balance)
local Quests = require(Shared.Config.Quests)
local Cosmetics = require(Shared.Config.Cosmetics)
local Console = require(Shared.Config.Console)
local Formulas = require(Shared.Logic.Formulas)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Platform = require(Client.Util.Platform)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local Glyph = require(Client.UI.Glyph)
local WorldStateController = require(Client.Controllers.WorldStateController)
local ScreenFX = require(Client.UI.ScreenFX)
local PanelController = require(Client.Controllers.PanelController)
local InputController = require(Client.Controllers.InputController)
local Widgets = require(Client.UI.Hud.Widgets)
local Counter = require(Client.UI.Hud.Counter)
local Glow = require(Client.UI.Hud.Glow)
local Text = require(Client.UI.Hud.Text)
local EventPill = require(Client.UI.Hud.EventPill)

local HUD = {}

-- Constantes (GDD §10.2, §9.2) -----------------------------------------------------------------

local DISPLAY_ORDER = 10
local MARGIN = 16
local GLOW_SIZE = Vector2.new(260, 64)
local DUST_SIZE = Vector2.new(200, 48)
local ICON = 56
local EVENT_SIZE = Vector2.new(320, 48)
local BEACON_BAR = Vector2.new(420, 28)
local BEACON_BAR_POS = UDim2.new(0.5, 0, 1, 6) -- sous la pastille d'événement
local MINIMAP = 150
local STATUS = 48
local TRACKER_SIZE = Vector2.new(260, 72)
-- Intérieur du suivi de quête : rangée du haut icône + titre (le titre prend toute la largeur
-- restante : 200 px, « Atteins 10 perchoirs » tient à 18 px), rangée du bas barre + bouton de repli
local TRACKER_ICON = 32
local TRACKER_TITLE_X = 54
local TRACKER_TITLE_W = TRACKER_SIZE.X - TRACKER_TITLE_X - 6
local TRACKER_TOGGLE = Vector2.new(52, 32)
-- Caractères qui tiennent sur une ligne du titre à 18 px (0,55 em par caractère, estimation
-- prudente pour FredokaOne) ; au-delà, le coût de la Supernova est abrégé (« 10M »)
local TRACKER_TITLE_CHARS = math.floor(TRACKER_TITLE_W / (0.55 * 18))
local RAIL_Y = 150
local RAIL_BUTTON = 80
local RAIL_GAP = 8
local RAIL_GRID_Y = 144 -- grille 2 × 2 des écrans bas : sous la pastille Stardust (88 + 48 + 8)
local RAIL_GRID_COLUMNS = 2
local JOYSTICK_TOP = 0.75 -- GDD §10.1 : le quart inférieur gauche (joystick dynamique) reste libre
local MIN_TEXT = 18 -- px de référence : plus petite taille de texte lisible (GDD §10.1)
local RAIL_LABEL_HEIGHT = 22
local RAIL_LABEL_BOTTOM = 5 -- marge sous le ruban, dans le bouton
local RAIL_LABEL_OVERHANG = 6 -- débord du ruban de chaque côté du bouton (marge d'écran ≥ 10 px)
local RAIL_LABEL_BACK = 0.25 -- transparence du fond sombre du ruban
local RAIL_HINT_SIZE = Vector2.new(96, 32) -- « Jouer » / « Play » à droite de l'icône ○ (≥ 18 px)
local STATUS_GAP = 8 -- écart entre les indicateurs d'état (UIListLayout)
local STATUS_TIME = Vector2.new(64, 22) -- minuteur du boost sous son icône
local CAPTION_SIZE = Vector2.new(210, 24) -- « Connexion instable », à gauche des indicateurs
local LINE_SIZE = Vector2.new(360, 56)
local LINE_Y = 24
local DASH = 112
local PING = 72
local CHEER_SIZE = Vector2.new(200, 88)
local PING_GAP = 12 -- écart Ping ↔ Dash
local STATUS_Y = MARGIN + MINIMAP + 8 -- indicateurs d'état sous la minicarte
local STATUS_WIDTH = STATUS * 4 + STATUS_GAP * 3
local STATUS_HEIGHT = STATUS + 2 + STATUS_TIME.Y
local TRACKER_Y = STATUS_Y + STATUS + 30 -- suivi de quête sous les indicateurs
local STATUS_HOME = UDim2.new(1, -MARGIN, 0, STATUS_Y)
local TRACKER_HOME = UDim2.new(1, -MARGIN, 0, TRACKER_Y)
local SIDE_RIGHT = MARGIN + MINIMAP + 8 -- colonne de repli : bord droit à gauche de la minicarte
local CLEARANCE = 8 -- écart minimal entre deux blocs du HUD (px de référence)
local COLUMN_MOVE = 0.25
-- instruction d'accueil (écran Onboarding, placée par OnboardingController avec HUD.hintTop) : sous
-- la pile COMPLÈTE de toasts (UI/Toast : y = 180, 3 × 48 + 2 × 6 → 336) ; sur les écrans très bas,
-- remontée juste ce qu'il faut pour ne jamais recouvrir le compteur de file
local TOAST_TOP = 180
local TOAST_WIDTH = 420 -- pile de UI/Toast (toasts de 400 px)
local TOAST_BOTTOM = TOAST_TOP + 3 * 48 + 2 * 6
local HINT_GAP = 6
local HINT_Y = TOAST_BOTTOM + HINT_GAP
local HINT_MIN_Y = 180 -- jamais dans la zone des bannières
local HINT_SIZE = Vector2.new(400, 56)
local TOUCH_FALLBACK = Vector2.new(-170, -130) -- coin bas droit sans bouton de saut trouvé
local REVEAL_TIME = 0.35
local REVEAL_PULSE = 1.4
local ATTENTION_PERIOD = 0.8
local ATTENTION_AMPLITUDE = 0.08
local SHINE_EVERY, SHINE_TIME = 4, 0.6
local SLOW_UPDATE = 0.2
local TOUCH_CHECK = 1
local FULL_FLASH_TIME = 0.3
local FULL_ARROW_TIME = 2
local COIN_SOUND_INTERVAL = 1 / 8
local BLINK_HZ = 2
local CHEER_SLIDE = 0.3
local CHEER_EMOTE = "cheer"
local MIN_TOUCH = 56 -- px RÉELS : cible tactile absolue de Dash et Ping (GDD §10.1, §13.2)
local TRACKER_SLIDE = 0.3
local PRESS_ACTIVATED_WINDOW = 1.5 -- s : Activated qui suit un appui déjà traité (même geste)
local LINE_BAR = Theme.Colors.Primary
local LINE_BAR_FULL = Theme.Colors.Gold
-- Manette (docs/07-console-ps5.md §3, §5) : icônes de touches de 36 px de référence
local GLYPH = Console.GlyphSize
local GLYPH_GAP = 8
-- △ au-dessus du rail, sous la pastille Stardust (16 + 64 + 8 + 48 + 8 = 144) ; à la manette le rail
-- descend d'autant (y = 144 + 36 + 8 = 188 : bas de la colonne à 532)
local RAIL_GLYPH_Y = MARGIN + GLOW_SIZE.Y + 8 + DUST_SIZE.Y + 8
local RAIL_PAD_Y = RAIL_GLYPH_Y + GLYPH + GLYPH_GAP
-- bord droit de Réglages (288 + 56 + 8 + 56 = 408) : la barre de la Balise, centrée sous la pastille
-- d'événement, se rétrécit pour ne pas le toucher sur les écrans étroits (zone sûre TV : 1152 px)
local TOP_ROW_RIGHT = MARGIN + GLOW_SIZE.X + 12 + ICON + 8 + ICON
-- largeur minimale de la pastille d'événement quand même décalée elle ne tient pas entre Réglages et
-- la minicarte (zone intérieure < 910 px de référence)
local EVENT_MIN_WIDTH = 220

type RailDef = {
	element: Types.HudElement,
	panel: Types.PanelName,
	glyph: string,
	label: string,
	key: Enum.KeyCode,
}

local RAIL: { RailDef } = {
	{
		element = "rail.Upgrades",
		panel = "Upgrades",
		glyph = "▲",
		label = "hud.rail.upgrades",
		key = Enum.KeyCode.U,
	},
	{
		element = "rail.Collection",
		panel = "Collection",
		glyph = "❖",
		label = "hud.rail.collection",
		key = Enum.KeyCode.C,
	},
	{
		element = "rail.Goals",
		panel = "Goals",
		glyph = "◎",
		label = "hud.rail.goals",
		key = Enum.KeyCode.J,
	},
	{ element = "rail.Shop", panel = "Shop", glyph = "✚", label = "hud.rail.shop", key = Enum.KeyCode.B },
}

-- Panneau ouvert → bouton du rail qui y mène (dernier panneau du rail ouvert : sélection de △)
local RAIL_PANEL: { [string]: Types.PanelName } = {
	Upgrades = "Upgrades",
	Supernova = "Upgrades",
	Collection = "Collection",
	Goals = "Goals",
	Shop = "Shop",
}

-- Éléments donnant accès à un panneau (garde des raccourcis clavier pendant l'accueil)
local PANEL_ELEMENT: { [string]: Types.HudElement } = {
	Upgrades = "rail.Upgrades",
	Collection = "rail.Collection",
	Goals = "rail.Goals",
	Shop = "rail.Shop",
	Crew = "crew",
	Settings = "settings",
	Supernova = "rail.Upgrades",
	ReturnScreen = "glow",
}

-- Éléments que la main d'accueil peut désigner, par priorité
local HAND_ELEMENTS: { Types.HudElement } =
	{ "rail.Upgrades", "rail.Collection", "rail.Goals", "rail.Shop", "dash" }

local GOAL_GLYPHS: { [string]: string } = {
	paradeSize = "⌂",
	upgrade = "▲",
	bankRarity = "◆",
	weatherOrComet = "☁",
	perches = "▣",
}

-- État ------------------------------------------------------------------------------------------

type Element = {
	holder: GuiObject,
	visual: GuiObject,
	scale: UIScale?,
	revealed: boolean,
	attention: boolean,
	revealEnd: number,
	pulseUntil: number,
}

type Cheer = { heroId: number, level: number, expiresAt: number, total: number }

-- Rectangle en px de référence du HUD (zone intérieure de Safe)
type Rect = { x0: number, y0: number, x1: number, y1: number }

local started = false
local built = false
local uiTime = 0
local lastSlow = -math.huge
local lastTouchCheck = -math.huge
local lastShine = 0
local lastCoinSound = -math.huge
local safe: Frame? = nil
local elements: { [string]: Element } = {}
local earlyReveals: { [string]: boolean } = {}
local texts: { { label: TextLabel, key: string } } = {}
local shines: { UIGradient } = {}
local railButtons: { [string]: TextButton } = {}
local railHolder: Frame? = nil
local railLayout: UIGridLayout? = nil
local railColumns = 1 -- 1 : colonne du GDD ; RAIL_GRID_COLUMNS : grille des écrans bas
local badges: { [string]: Frame } = {}
-- touches du clavier (KeyCap) : affichées au clavier seulement, texte selon la disposition du joueur
local keyCaps: { { cap: TextLabel, key: Enum.KeyCode } } = {}
-- icônes de touches de la manette (UI/Glyph « PadGlyph »), par élément
local padGlyphs: { [string]: Glyph.Handle } = {}
local hand: Frame? = nil
local handTarget: Element? = nil
-- manette : la main d'accueil devient l'icône de la touche à presser (△, ✕ ou R2)
local handGlyph: Glyph.Handle? = nil
local handKey: Enum.KeyCode? = nil
local navButtons: { crew: TextButton?, settings: TextButton?, ping: TextButton? } = {}
local lastRailPanel: Types.PanelName? = nil
local railPadMode = false -- rail descendu sous le △ (manette)
local railGlyphHolder: Frame? = nil
local railHint: TextLabel? = nil -- « Jouer » à droite de l'icône du rail en mode menu (manette)
local railMenuMode = false -- icône du rail sur ○ (sélection dans le HUD ou la minicarte)

local glowCounter: Counter.Counter? = nil
local dustCounter: Counter.Counter? = nil
local glowDirty = false
local lastGlowTarget = 0
local rateLabel: TextLabel? = nil

local lineParts: {
	frame: Frame?,
	stroke: UIStroke?,
	count: TextLabel?,
	bonus: TextLabel?,
	empty: TextLabel?,
	fill: Frame?,
	shield: TextLabel?,
	arrow: TextLabel?,
} =
	{}
local lineCount = 0
local fullFlashAt = -math.huge
local arrowUntil = -math.huge

local dashParts: { holder: Frame?, button: TextButton?, radial: Widgets.Radial?, flash: Frame? } = {}
local pingHolder: Frame? = nil
local dashWasReady = true
local lastPressDash = -math.huge
local jumpButton: GuiObject? = nil
-- place courante de la colonne de droite (positions du GDD, ou colonne de repli sur écran bas)
local columnHome: { [string]: UDim2 } = { status = STATUS_HOME, questTracker = TRACKER_HOME }

local eventParts: { label: TextLabel?, stroke: UIStroke?, bar: Frame?, fill: Frame?, barLabel: TextLabel? } =
	{}
local lastPill: EventPill.PillState? = nil
local lastBarRatio = -1

local statusParts: {
	rookie: Frame?,
	zen: Frame?,
	boost: Frame?,
	boostTime: TextLabel?,
	unstable: Frame?,
	caption: TextLabel?,
} =
	{}
local trackerParts: {
	pill: Frame?,
	icon: TextLabel?,
	title: TextLabel?,
	fill: Frame?,
	toggle: TextButton?,
	collapsed: boolean,
	progress: number,
	key: string,
} =
	{ collapsed = false, progress = -1, key = "" }

local cheer: Cheer? = nil
local cheerParts: { holder: Frame?, button: TextButton?, ring: Widgets.Radial?, name: TextLabel?, shownAt: number } =
	{ shownAt = 0 }
local cheerRemote: RemoteEvent? = nil

-- Outils ----------------------------------------------------------------------------------------

local toLocal: (Vector2) -> Vector2

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x: any, default: number): number
	return if isFinite(x) then x :: number else default
end

local function reduced(): boolean
	return Prefs.reducedMotion()
end

-- Entrée préférée (Util/Platform, docs/07-console-ps5.md §2) : manette / clavier-souris
local function usingGamepad(): boolean
	return Platform.usingGamepad()
end

-- Icône de touche de manette « PadGlyph » posée dans `parent` (masquée hors manette)
local function padGlyph(
	element: string,
	parent: Instance,
	key: Enum.KeyCode,
	position: UDim2,
	anchor: Vector2
)
	padGlyphs[element] = Glyph.new(parent, { gamepad = key }, {
		name = "PadGlyph",
		size = GLYPH,
		position = position,
		anchor = anchor,
		zIndex = 8,
	})
end

local function localPlayer(): Player?
	return Players.LocalPlayer
end

local function localSlot(): number
	return WorldStateController.localSlot()
end

local function upgradeLevel(track: string): number
	local upgrades = State.get("upgrades")
	return if type(upgrades) == "table" then math.max(0, math.floor(num(upgrades[track], 0))) else 0
end

local function zen(): boolean
	local player = localPlayer()
	return Prefs.get("zen") == true or (player ~= nil and player:GetAttribute("Zen") == true)
end

local function nameOf(userId: number): string?
	local player = Players:GetPlayerByUserId(userId)
	return if player then Text.cleanName(player.DisplayName) else nil
end

-- Compteurs : séparateurs de milliers jusqu'au million, puis abréviation (« 1,24 M »)
local function money(n: number): string
	return if n < 1e6 then Prefs.commas(n) else Prefs.number(n)
end

local function bindText(label: TextLabel, key: string)
	table.insert(texts, { label = label, key = key })
	label.Text = Prefs.t(key)
end

local function register(name: Types.HudElement, holder: GuiObject, visual: GuiObject?)
	local scale = holder:FindFirstChild("HudScale")
	elements[name] = {
		holder = holder,
		visual = visual or holder,
		scale = if scale and scale:IsA("UIScale") then scale else nil,
		revealed = false,
		attention = false,
		revealEnd = 0,
		pulseUntil = 0,
	}
	holder.Visible = false
	if earlyReveals[name] then
		earlyReveals[name] = nil
		HUD.reveal(name, false)
	end
end

-- Construction ----------------------------------------------------------------------------------

local function buildGlow(parent: Frame)
	local holder = Widgets.holder(
		"Glow",
		UDim2.fromOffset(GLOW_SIZE.X, GLOW_SIZE.Y),
		UDim2.fromOffset(MARGIN, MARGIN),
		nil,
		parent
	)
	local pill = Widgets.pill("Pill", holder, Color3.fromRGB(150, 105, 25))
	Widgets.coin("Coin", UDim2.fromOffset(46, 46), UDim2.new(0, 10, 0.5, 0), pill)
	local value = Widgets.label({
		name = "Value",
		size = UDim2.new(1, -72, 0, 38),
		position = UDim2.fromOffset(64, 4),
		maxSize = 34,
		xAlign = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(255, 236, 170),
		strokeThickness = 2,
		parent = pill,
	})
	rateLabel = Widgets.label({
		name = "Rate",
		size = UDim2.new(1, -72, 0, 20),
		position = UDim2.fromOffset(64, 40),
		maxSize = 18,
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.TextDim,
		parent = pill,
	})
	local counter = Counter.new(value, money, 0)
	counter.onPop = function()
		Juice.pulse(pill, 1.15)
		if uiTime - lastCoinSound >= COIN_SOUND_INTERVAL then
			lastCoinSound = uiTime
			AudioController.play("Coin", 0.05)
		end
	end
	glowCounter = counter
	register("glow", holder, pill)
end

local function buildStardust(parent: Frame)
	local holder = Widgets.holder(
		"Stardust",
		UDim2.fromOffset(DUST_SIZE.X, DUST_SIZE.Y),
		UDim2.fromOffset(MARGIN, MARGIN + GLOW_SIZE.Y + 8),
		nil,
		parent
	)
	local pill = Widgets.pill("Pill", holder, Color3.fromRGB(120, 80, 190))
	Widgets.glyph("Star", "✦", pill, Color3.fromRGB(220, 180, 255), 34).Size = UDim2.fromOffset(40, 40)
	local star = pill:FindFirstChild("Star") :: TextLabel
	star.Position = UDim2.new(0, 28, 0.5, 0)
	star.AutoLocalize = false
	local value = Widgets.label({
		name = "Value",
		size = UDim2.new(1, -64, 1, -10),
		position = UDim2.fromOffset(54, 5),
		maxSize = 28,
		xAlign = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(235, 215, 255),
		strokeThickness = 2,
		parent = pill,
	})
	local counter = Counter.new(value, money, 0)
	counter.onPop = function()
		Juice.pulse(pill, 1.15)
	end
	dustCounter = counter
	register("stardust", holder, pill)
end

local function iconButton(
	name: Types.HudElement,
	glyph: string,
	position: UDim2,
	parent: Frame,
	onClick: () -> (),
	key: Enum.KeyCode?
): TextButton
	local holder = Widgets.holder(name, UDim2.fromOffset(ICON, ICON), position, nil, parent)
	local button = Widgets.button("Button", holder, Theme.Colors.Panel, false)
	Widgets.glyph("Icon", glyph, button, Theme.Colors.Text, 32).AutoLocalize = false
	button.Activated:Connect(onClick)
	if key then
		table.insert(keyCaps, { cap = Widgets.keyCap(button, Platform.glyph(key).text), key = key })
	end
	register(name, holder, button)
	return button
end

local function buildSecondary(parent: Frame)
	local x = MARGIN + GLOW_SIZE.X + 12
	local crew = iconButton("crew", "☺", UDim2.fromOffset(x, MARGIN + 4), parent, function()
		InputController.togglePanel("Crew")
	end, Enum.KeyCode.G)
	local settings = iconButton(
		"settings",
		"⚙",
		UDim2.fromOffset(x + ICON + 8, MARGIN + 4),
		parent,
		function()
			InputController.togglePanel("Settings")
		end
	)
	crew.NextSelectionRight = settings
	settings.NextSelectionLeft = crew
	navButtons.crew = crew
	navButtons.settings = settings
end

local function buildEventPill(parent: Frame)
	local holder = Widgets.holder(
		"EventPill",
		UDim2.fromOffset(EVENT_SIZE.X, EVENT_SIZE.Y),
		UDim2.new(0.5, 0, 0, MARGIN),
		Vector2.new(0.5, 0),
		parent
	)
	local pill = Widgets.pill("Pill", holder)
	local label = Widgets.label({
		name = "Text",
		size = UDim2.new(1, -24, 1, -10),
		position = UDim2.fromOffset(12, 5),
		maxSize = 26,
		parent = pill,
	})
	eventParts.label = label
	eventParts.stroke = pill:FindFirstChildOfClass("UIStroke")
	-- barre de serveur de la Balise (420 × 28) sous la pastille
	local bar = Create("Frame", {
		Name = "BeaconBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = BEACON_BAR_POS,
		Size = UDim2.fromOffset(BEACON_BAR.X, BEACON_BAR.Y),
		BackgroundColor3 = Theme.Colors.Background,
		Visible = false,
		Parent = holder,
	}, { Widgets.round(), Widgets.stroke(EventPill.Colors.beacon, 2) })
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = EventPill.Colors.beacon,
		ZIndex = 2,
		Parent = bar,
	}, { Widgets.round(), Widgets.gradient() })
	eventParts.bar = bar
	eventParts.fill = fill
	eventParts.barLabel = Widgets.label({
		name = "Text",
		size = UDim2.fromScale(1, 1),
		maxSize = 20,
		zIndex = 3,
		parent = bar,
	})
	register("eventPill", holder, pill)
end

local function statusIcon(name: string, glyph: string, color: Color3, parent: Instance, order: number): Frame
	local frame = Create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(STATUS, STATUS),
		BackgroundColor3 = Theme.Colors.Panel,
		LayoutOrder = order,
		Visible = false,
		Parent = parent,
	}, { Widgets.round(), Widgets.stroke(color, 2.5) })
	Widgets.glyph("Icon", glyph, frame, color, 30).AutoLocalize = false
	return frame
end

local function buildStatus(parent: Frame)
	local holder = Widgets.holder(
		"Status",
		UDim2.fromOffset(STATUS_WIDTH, STATUS_HEIGHT),
		STATUS_HOME,
		Vector2.new(1, 0),
		parent
	)
	local row = Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, STATUS),
		Parent = holder,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, STATUS_GAP),
		}),
	})
	statusParts.rookie = statusIcon("Rookie", "◈", Cosmetics.Readability.Rookie, row, 0)
	statusParts.zen = statusIcon("Zen", "☯", Cosmetics.Readability.Zen, row, 1)
	local boost = statusIcon("Boost", "×2", Theme.Colors.Gold, row, 2)
	statusParts.boost = boost
	-- minuteur ≥ 18 px de référence (GDD §10.1), assez large pour « 20:00 »
	statusParts.boostTime = Widgets.label({
		name = "Time",
		size = UDim2.fromOffset(STATUS_TIME.X, STATUS_TIME.Y),
		position = UDim2.new(0.5, 0, 1, 2),
		anchor = Vector2.new(0.5, 0),
		maxSize = MIN_TEXT,
		zIndex = 4,
		parent = boost,
	})
	statusParts.unstable = statusIcon("Unstable", "⚠", Theme.Colors.Warning, row, 3)
	-- légende à GAUCHE des indicateurs visibles, centrée sur la rangée (placée par updateStatus) :
	-- jamais sur le minuteur du boost ni sur le suivi de quête
	local caption = Widgets.label({
		name = "Caption",
		size = UDim2.fromOffset(CAPTION_SIZE.X, CAPTION_SIZE.Y),
		position = UDim2.new(0, -STATUS_GAP, 0, STATUS / 2),
		anchor = Vector2.new(1, 0.5),
		maxSize = MIN_TEXT,
		xAlign = Enum.TextXAlignment.Right,
		color = Theme.Colors.Warning,
		parent = holder,
	})
	caption.Visible = false
	bindText(caption, "hud.unstable")
	statusParts.caption = caption
	register("status", holder, row)
end

local function setTrackerCollapsed(collapsed: boolean)
	trackerParts.collapsed = collapsed
	local pill = trackerParts.pill
	if pill == nil then
		return
	end
	local width = if collapsed then TRACKER_SIZE.Y else TRACKER_SIZE.X
	if reduced() then
		pill.Size = UDim2.fromOffset(width, TRACKER_SIZE.Y)
	else
		Juice.tween(pill, 0.2, { Size = UDim2.fromOffset(width, TRACKER_SIZE.Y) })
	end
	local title = trackerParts.title
	if title then
		title.Visible = not collapsed
	end
	local fill = trackerParts.fill
	if fill and fill.Parent then
		(fill.Parent :: GuiObject).Visible = not collapsed
	end
	local toggle = trackerParts.toggle
	if toggle then
		local glyph = toggle:FindFirstChild("Icon")
		if glyph and glyph:IsA("TextLabel") then
			glyph.Text = if collapsed then "◂" else "▸"
		end
	end
	-- icône croix ← (manette) : toujours à gauche de la pastille, repliée ou non
	local pad = padGlyphs.questTracker
	if pad then
		local position = UDim2.new(1, -width - GLYPH_GAP, 0.5, 0)
		if reduced() then
			pad.frame.Position = position
		else
			Juice.tween(pad.frame, 0.2, { Position = position })
		end
	end
end

local function buildTracker(parent: Frame)
	local holder = Widgets.holder(
		"QuestTracker",
		UDim2.fromOffset(TRACKER_SIZE.X, TRACKER_SIZE.Y),
		TRACKER_HOME,
		Vector2.new(1, 0),
		parent
	)
	local pill = Widgets.pill("Pill", holder)
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.fromScale(1, 0)
	pill.Size = UDim2.fromOffset(TRACKER_SIZE.X, TRACKER_SIZE.Y)
	pill.ClipsDescendants = true
	-- rangée du haut : icône (coin haut gauche, jamais sous le bouton de repli, même replié) et
	-- titre sur toute la largeur restante, jamais sous 18 px de référence (GDD §10.1)
	local icon = Widgets.label({
		name = "Icon",
		size = UDim2.fromOffset(TRACKER_ICON, TRACKER_ICON),
		position = UDim2.fromOffset(12, 4),
		maxSize = 32,
		color = Theme.Colors.Gold,
		strokeThickness = 2,
		parent = pill,
	})
	icon.AutoLocalize = false
	local title = Widgets.label({
		name = "Title",
		size = UDim2.new(1, -(TRACKER_TITLE_X + 6), 0, 30),
		position = UDim2.fromOffset(TRACKER_TITLE_X, 6),
		maxSize = 22,
		minSize = MIN_TEXT,
		xAlign = Enum.TextXAlignment.Left,
		parent = pill,
	})
	-- rangée du bas : barre de progression puis bouton de repli
	local barBack = Create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 1, -(4 + TRACKER_TOGGLE.Y / 2)),
		Size = UDim2.new(1, -(12 + 6 + TRACKER_TOGGLE.X + 6), 0, 14),
		BackgroundColor3 = Theme.Colors.Background,
		Parent = pill,
	}, { Widgets.round() })
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Gold,
		ZIndex = 2,
		Parent = barBack,
	}, { Widgets.round(), Widgets.gradient() })
	-- bouton de repli dans la rangée de la barre (coin bas droit) : il ne mange plus la largeur du
	-- titre ; replié (pastille carrée), il reste sous l'icône
	local toggleHolder = Create("Frame", {
		Name = "Toggle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -6, 1, -4),
		Size = UDim2.fromOffset(TRACKER_TOGGLE.X, TRACKER_TOGGLE.Y),
		ZIndex = 5,
		Parent = pill,
	})
	local toggle = Widgets.button("Button", toggleHolder, Theme.Colors.PanelLight, false)
	Widgets.glyph("Icon", "▸", toggle, Theme.Colors.TextDim, 20).AutoLocalize = false
	toggle.Activated:Connect(function()
		setTrackerCollapsed(not trackerParts.collapsed)
	end)
	trackerParts.pill = pill
	trackerParts.icon = icon
	trackerParts.title = title
	trackerParts.fill = fill
	trackerParts.toggle = toggle
	-- croix ← replie / déplie (docs/07 §6.1) : icône à gauche de la pastille (qui coupe ses enfants)
	padGlyph(
		"questTracker",
		holder,
		Enum.KeyCode.DPadLeft,
		UDim2.new(1, -TRACKER_SIZE.X - GLYPH_GAP, 0.5, 0),
		Vector2.new(1, 0.5)
	)
	register("questTracker", holder, pill)
end

local function buildRail(parent: Frame)
	local height = #RAIL * RAIL_BUTTON + (#RAIL - 1) * RAIL_GAP
	local rail = Widgets.holder(
		"Rail",
		UDim2.fromOffset(RAIL_BUTTON, height),
		UDim2.fromOffset(MARGIN, RAIL_Y),
		nil,
		parent
	)
	-- grille d'une colonne (GDD) ou de RAIL_GRID_COLUMNS sur écran bas (layoutRail) ; comme une
	-- liste, elle tasse les boutons affichés (révélés au fil de l'accueil, pas dans l'ordre du rail)
	railLayout = Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(RAIL_BUTTON, RAIL_BUTTON),
		CellPadding = UDim2.fromOffset(RAIL_GAP, RAIL_GAP),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = 1,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rail,
	}) :: UIGridLayout
	railHolder = rail
	-- △ (manette) au-dessus du rail : la touche des menus (docs/07 §6.2) ; le rail descend sous elle.
	-- Conteneur frère du rail (la grille placerait l'icône comme une case), placé par layoutRail
	local glyphHolder = Create("Frame", {
		Name = "RailGlyph",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(MARGIN + RAIL_BUTTON / 2, RAIL_Y - GLYPH_GAP),
		Size = UDim2.fromOffset(GLYPH, GLYPH),
		Visible = false,
		Parent = parent,
	})
	railGlyphHolder = glyphHolder
	padGlyph("rail", glyphHolder, Enum.KeyCode.ButtonY, UDim2.new(), Vector2.zero)
	-- mode menu (manette) : « Jouer » à droite de l'icône ○ (refreshRailHint), texte ≥ 18 px
	local hint = Widgets.label({
		name = "RailHint",
		size = UDim2.fromOffset(RAIL_HINT_SIZE.X, RAIL_HINT_SIZE.Y),
		position = UDim2.new(1, GLYPH_GAP, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		maxSize = MIN_TEXT + 4,
		minSize = MIN_TEXT,
		zIndex = 8,
		parent = glyphHolder,
	})
	hint.BackgroundColor3 = Widgets.STROKE
	hint.BackgroundTransparency = RAIL_LABEL_BACK
	hint.Visible = false
	Widgets.corner(UDim.new(0, 8)).Parent = hint
	bindText(hint, "hud.backToGame")
	railHint = hint
	register("rail", rail)
	for i, def in RAIL do
		local holder =
			Widgets.holder(def.panel, UDim2.fromOffset(RAIL_BUTTON, RAIL_BUTTON), UDim2.new(), nil, rail)
		holder.LayoutOrder = i
		local button = Widgets.button("Button", holder, Theme.Colors.Panel, false)
		local glyph = Widgets.glyph("Icon", def.glyph, button, Theme.Colors.Gold, 40)
		glyph.Size = UDim2.fromScale(0.7, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.36)
		glyph.AutoLocalize = false
		-- ruban de libellé : texte ≥ 18 px de référence (GDD §10.1) ; il déborde un peu du bouton
		-- (RAIL_LABEL_OVERHANG de chaque côté) pour que « Collection » / « Améliorer » tiennent à 18 px
		local label = Widgets.label({
			name = "Label",
			size = UDim2.new(1, RAIL_LABEL_OVERHANG * 2, 0, RAIL_LABEL_HEIGHT),
			position = UDim2.new(0.5, 0, 1, -RAIL_LABEL_BOTTOM),
			anchor = Vector2.new(0.5, 1),
			maxSize = MIN_TEXT,
			zIndex = 4,
			parent = button,
		})
		label.BackgroundColor3 = Widgets.STROKE
		label.BackgroundTransparency = RAIL_LABEL_BACK
		Widgets.corner(UDim.new(0, 8)).Parent = label
		bindText(label, def.label)
		badges[def.panel] = Widgets.badge(button)
		-- touche de raccourci dans le coin haut gauche : elle ne masque plus le début du libellé
		local cap = Widgets.keyCap(button, Platform.glyph(def.key).text)
		cap.AnchorPoint = Vector2.zero
		cap.Position = UDim2.fromOffset(-4, -4)
		table.insert(keyCaps, { cap = cap, key = def.key })
		table.insert(shines, Widgets.shine(button))
		button.Activated:Connect(function()
			InputController.togglePanel(def.panel)
		end)
		railButtons[def.panel] = button
		register(def.element, holder, button)
	end
end

local function buildLine(parent: Frame)
	local holder = Widgets.holder(
		"LineCounter",
		UDim2.fromOffset(LINE_SIZE.X, LINE_SIZE.Y),
		UDim2.new(0.5, 0, 1, -LINE_Y),
		Vector2.new(0.5, 1),
		parent
	)
	local pill = Widgets.pill("Pill", holder)
	local count = Widgets.label({
		name = "Count",
		size = UDim2.new(0, 96, 1, -12),
		position = UDim2.fromOffset(12, 6),
		maxSize = 30,
		xAlign = Enum.TextXAlignment.Left,
		strokeThickness = 2,
		parent = pill,
	})
	local barBack = Create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 112, 0.5, 0),
		Size = UDim2.new(1, -216, 0, 16),
		BackgroundColor3 = Theme.Colors.Background,
		Parent = pill,
	}, { Widgets.round() })
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = LINE_BAR,
		ZIndex = 2,
		Parent = barBack,
	}, { Widgets.round(), Widgets.gradient() })
	local bonus = Widgets.label({
		name = "Bonus",
		size = UDim2.new(0, 92, 1, -12),
		position = UDim2.new(1, -12, 0, 6),
		anchor = Vector2.new(1, 0),
		maxSize = 28,
		xAlign = Enum.TextXAlignment.Right,
		color = Theme.Colors.Gold,
		strokeThickness = 2,
		parent = pill,
	})
	local empty = Widgets.label({
		name = "Empty",
		size = UDim2.new(1, -24, 1, -14),
		position = UDim2.fromOffset(12, 7),
		maxSize = 26,
		color = Theme.Colors.TextDim,
		parent = pill,
	})
	bindText(empty, "hud.line.empty")
	-- bouclier débutant près du compteur (FTUE, 1-2 min)
	local shield = Widgets.label({
		name = "Shield",
		text = "◈",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(0, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		maxSize = 38,
		color = Cosmetics.Readability.Rookie,
		strokeThickness = 2,
		parent = holder,
	})
	shield.AutoLocalize = false
	shield.Visible = false
	-- flèche vers le Nid (file pleine, 2 s)
	local arrow = Widgets.label({
		name = "NestArrow",
		text = "▲",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(0.5, 0, 0, -10),
		anchor = Vector2.new(0.5, 1),
		maxSize = 40,
		color = Theme.Colors.Gold,
		strokeThickness = 2,
		parent = holder,
	})
	arrow.AutoLocalize = false
	arrow.Visible = false
	lineParts = {
		frame = pill,
		stroke = pill:FindFirstChildOfClass("UIStroke"),
		count = count,
		bonus = bonus,
		empty = empty,
		fill = fill,
		shield = shield,
		arrow = arrow,
	}
	register("line", holder, pill)
end

local function buildDash(parent: Frame)
	local holder = Widgets.holder(
		"Dash",
		UDim2.fromOffset(DASH, DASH),
		UDim2.new(1, -MARGIN, 1, -MARGIN),
		Vector2.new(1, 1),
		parent
	)
	local button = Widgets.button("Button", holder, Color3.fromRGB(70, 170, 255), true)
	Widgets.glyph("Icon", "⚡", button, Color3.fromRGB(255, 240, 150), 64).AutoLocalize = false
	local radial = Widgets.radial("Cooldown", button, Color3.fromRGB(10, 8, 25), 0.35, 6)
	local flash = Create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 7,
		Parent = button,
	}, { Widgets.round() })
	table.insert(shines, Widgets.shine(button))
	table.insert(
		keyCaps,
		{ cap = Widgets.keyCap(button, Platform.glyph(Enum.KeyCode.E).text), key = Enum.KeyCode.E }
	)
	-- R2 (manette, docs/07 §6.1) dans le coin haut gauche, hors du disque
	padGlyph("dash", button, Enum.KeyCode.ButtonR2, UDim2.fromOffset(-4, -4), Vector2.zero)
	-- Dash dès l'appui (tactile, souris) : Activated n'arrive qu'au relâchement du doigt ;
	-- Activated reste la voie de la manette (bouton sélectionné + A) et ignore l'appui déjà traité
	button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			lastPressDash = uiTime
			InputController.dash()
		end
	end)
	button.Activated:Connect(function()
		if uiTime - lastPressDash < PRESS_ACTIVATED_WINDOW and uiTime >= lastPressDash then
			return
		end
		InputController.dash()
	end)
	dashParts = { holder = holder, button = button, radial = radial, flash = flash }
	register("dash", holder, button)

	local ping = Widgets.holder(
		"Ping",
		UDim2.fromOffset(PING, PING),
		UDim2.new(1, -MARGIN - DASH - PING_GAP, 1, -MARGIN),
		Vector2.new(1, 1),
		parent
	)
	local pingButton = Widgets.button("Button", ping, Theme.Colors.PanelLight, true)
	Widgets.glyph("Icon", "⚑", pingButton, Color3.fromRGB(255, 205, 60), 40).AutoLocalize = false
	table.insert(
		keyCaps,
		{ cap = Widgets.keyCap(pingButton, Platform.glyph(Enum.KeyCode.Q).text), key = Enum.KeyCode.Q }
	)
	padGlyph("ping", pingButton, Enum.KeyCode.DPadUp, UDim2.fromOffset(-4, -4), Vector2.zero)
	pingButton.Activated:Connect(function()
		if InputController.isPingWheelOpen() then
			InputController.closePingWheel()
		else
			InputController.openPingWheel()
		end
	end)
	pingButton.NextSelectionRight = button
	button.NextSelectionLeft = pingButton
	navButtons.ping = pingButton
	pingHolder = ping
	register("ping", ping, pingButton)
end

local function buildCheer(parent: Frame)
	local holder = Create("Frame", {
		Name = "Cheer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -LINE_Y - LINE_SIZE.Y - 16),
		Size = UDim2.fromOffset(CHEER_SIZE.X, CHEER_SIZE.Y),
		Visible = false,
		Parent = parent,
	})
	local button = Widgets.button("Button", holder, Theme.Colors.Gold, false)
	local label = Widgets.label({
		name = "Title",
		size = UDim2.new(1, -86, 0, 46),
		position = UDim2.fromOffset(78, 8),
		maxSize = 34,
		color = Color3.fromRGB(60, 30, 10),
		zIndex = 4,
		parent = button,
	})
	bindText(label, "hud.cheer")
	local name = Widgets.label({
		name = "Hero",
		size = UDim2.new(1, -86, 0, 24),
		position = UDim2.fromOffset(78, 54),
		maxSize = 18,
		color = Color3.fromRGB(90, 50, 20),
		zIndex = 4,
		parent = button,
	})
	name.AutoLocalize = false
	-- nom du héros (jusqu'à 20 caractères) : toujours 18 px, coupé par « … » plutôt que rétréci
	-- sous la taille lisible (GDD §10.1)
	name.TextScaled = false
	name.TextWrapped = false
	name.TextSize = MIN_TEXT
	name.TextTruncate = Enum.TextTruncate.AtEnd
	-- anneau de temps (10 s)
	local ringHolder = Create("Frame", {
		Name = "Ring",
		BackgroundColor3 = Color3.fromRGB(120, 70, 20),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		ZIndex = 4,
		Parent = button,
	}, { Widgets.round() })
	local ring = Widgets.radial("Time", ringHolder, Color3.fromRGB(255, 250, 220), 0, 5)
	Widgets.glyph("Icon", "✺", ringHolder, Color3.fromRGB(255, 120, 60), 30).ZIndex = 6
	button.Activated:Connect(function()
		InputController.requestCheer()
	end)
	-- croix → (manette) à droite du bouton
	padGlyph("cheer", holder, Enum.KeyCode.DPadRight, UDim2.new(1, GLYPH_GAP, 0.5, 0), Vector2.new(0, 0.5))
	cheerParts.holder = holder
	cheerParts.button = button
	cheerParts.ring = ring
	cheerParts.name = name
end

local function buildHand(parent: Frame)
	hand = Widgets.hand(parent)
	-- manette : la main (geste tactile) est remplacée par l'icône de la touche à presser
	handGlyph = Glyph.new(parent, {}, { name = "HandGlyph", size = GLYPH, zIndex = 10 })
end

local function build()
	if built then
		return
	end
	built = true
	local s = Root.safe("HUD", DISPLAY_ORDER)
	safe = s
	buildRail(s)
	buildGlow(s)
	buildStardust(s)
	buildSecondary(s)
	buildEventPill(s)
	buildStatus(s)
	buildTracker(s)
	buildLine(s)
	buildDash(s)
	buildCheer(s)
	buildHand(s)
end

-- Mises à jour ----------------------------------------------------------------------------------

local function updateLine(animate: boolean)
	local parts = lineParts
	local count, bonus, empty, fill = parts.count, parts.bonus, parts.empty, parts.fill
	if count == nil or bonus == nil or empty == nil or fill == nil then
		return
	end
	local slot = localSlot()
	local n = if slot ~= 0 then WorldStateController.lineLength(slot) else 0
	local cap = Formulas.congaCapacity(upgradeLevel("conga"))
	local isEmpty = n <= 0
	local barBack = fill.Parent :: GuiObject
	empty.Visible = isEmpty
	count.Visible = not isEmpty
	bonus.Visible = not isEmpty
	barBack.Visible = not isEmpty
	count.Text = Prefs.t("hud.line.count", { n = n, max = cap })
	bonus.Text =
		Prefs.t("hud.line.bonus", { bonus = Text.bonus(Formulas.congaBonus(n, zen()), Prefs.language()) })
	local ratio = if cap > 0 then math.clamp(n / cap, 0, 1) else 0
	fill.BackgroundColor3 = if n >= cap then LINE_BAR_FULL else LINE_BAR
	if reduced() then
		fill.Size = UDim2.fromScale(ratio, 1)
	else
		Juice.tween(fill, 0.15, { Size = UDim2.fromScale(ratio, 1) })
	end
	if animate and n > lineCount and parts.frame then
		-- capture : pop 1,15 en 0,15 s ; « ×1,24 » pulse
		Juice.pulse(parts.frame :: Frame, 1.15)
		Juice.pulse(bonus, 1.2)
	end
	lineCount = n
end

local function updateShield()
	local shield = lineParts.shield
	local player = localPlayer()
	if shield then
		shield.Visible = HUD.isRevealed("status") and player ~= nil and player:GetAttribute("Rookie") == true
	end
end

local function shownCount(icon: GuiObject?): number
	return if icon and icon.Visible then 1 else 0
end

local function updateStatus(now: number)
	local player = localPlayer()
	local zenIcon, boostIcon, boostTime, unstable, caption =
		statusParts.zen, statusParts.boost, statusParts.boostTime, statusParts.unstable, statusParts.caption
	if zenIcon then
		zenIcon.Visible = zen()
	end
	local rookieIcon = statusParts.rookie
	if rookieIcon then
		rookieIcon.Visible = player ~= nil and player:GetAttribute("Rookie") == true
	end
	-- boost ×2 : personnel (boosts.personalUntil, Clock.unix) ou de serveur (EventState)
	local untilAt = 0
	local boosts = State.get("boosts")
	if type(boosts) == "table" then
		untilAt = num(boosts.personalUntil, 0)
	end
	local ev = WorldStateController.events()
	if ev and ev.serverBoost then
		untilAt = math.max(untilAt, num(ev.serverBoost.endsAt, 0))
	end
	if boostIcon and boostTime then
		local remaining = untilAt - now
		boostIcon.Visible = remaining > 0
		if remaining > 0 then
			boostTime.Text = Format.clock(math.ceil(remaining))
		end
	end
	local isUnstable = player ~= nil and player:GetAttribute("Unstable") == true
	if unstable then
		unstable.Visible = isUnstable
	end
	if caption then
		caption.Visible = isUnstable
		if isUnstable then
			-- largeur des indicateurs visibles (alignés à droite) → la légende se cale à leur gauche
			local shown = shownCount(statusParts.rookie)
				+ shownCount(zenIcon)
				+ shownCount(boostIcon)
				+ shownCount(unstable)
			local width = shown * STATUS + math.max(0, shown - 1) * STATUS_GAP
			local position = UDim2.new(1, -(width + STATUS_GAP), 0, STATUS / 2)
			if caption.Position ~= position then
				caption.Position = position
			end
		end
	end
	updateShield()
end

local function questGoal(step: number): (Quests.OnboardingQuest?, number, number)
	local def = Quests.Onboarding[step]
	if def == nil then
		return nil, 0, 1
	end
	local ob = State.get("onboarding")
	local p = if type(ob) == "table" then num(ob.p, 0) else 0
	return def, p, math.max(1, def.goal.n)
end

local function updateTracker(now: number)
	local icon, title, fill, pill =
		trackerParts.icon, trackerParts.title, trackerParts.fill, trackerParts.pill
	if icon == nil or title == nil or fill == nil or pill == nil then
		return
	end
	local ob = State.get("onboarding")
	local step = if type(ob) == "table" then math.floor(num(ob.step, 0)) else 0
	local def, p, n = questGoal(step)
	local key: string
	local progress: number
	if def then
		key = "quest.onboarding." .. def.id
		title.Text = Prefs.t(key)
		icon.Text = GOAL_GLYPHS[def.goal.kind] or "★"
		progress = math.clamp(p / n, 0, 1)
	else
		-- objectif long permanent : « Supernova · 400 000 » ; coût abrégé (« Supernova · 10 M ») dès
		-- que le nombre complet ne tient plus sur une ligne à 18 px
		local cost = Formulas.supernovaCost(math.max(0, math.floor(num(State.get("supernovas"), 0))))
		key = "hud.quest.supernova"
		local text = Prefs.t(key, { cost = Prefs.commas(cost) })
		if (utf8.len(text) or #text) > TRACKER_TITLE_CHARS then
			text = Prefs.t(key, { cost = Prefs.number(cost) })
		end
		title.Text = text
		icon.Text = "✺"
		progress = if cost > 0 then math.clamp(Glow.predicted(now) / cost, 0, 1) else 1
	end
	if math.abs(progress - trackerParts.progress) > 1e-4 then
		local grew = progress > trackerParts.progress
			and trackerParts.progress >= 0
			and key == trackerParts.key
		trackerParts.progress = progress
		if reduced() or not grew then
			fill.Size = UDim2.fromScale(progress, 1)
		else
			Juice.tween(fill, 0.3, { Size = UDim2.fromScale(progress, 1) })
		end
		if grew and def then
			Juice.pulse(pill, 1.08)
		end
	end
	if key ~= trackerParts.key then
		local changed = trackerParts.key ~= ""
		trackerParts.key = key
		if changed and not reduced() then
			Juice.pulse(pill, 1.1)
		end
	end
end

local function updateEventPill(now: number)
	local label, stroke, bar, fill, barLabel =
		eventParts.label, eventParts.stroke, eventParts.bar, eventParts.fill, eventParts.barLabel
	if label == nil or bar == nil or fill == nil or barLabel == nil then
		return
	end
	local state = EventPill.compute(WorldStateController.events(), now, Prefs.t, nameOf)
	lastPill = state
	label.Text = Prefs.t(state.key, state.vars)
	label.TextColor3 = if state.active then Widgets.lighten(state.color, 0.25) else state.color
	if stroke then
		stroke.Color = if state.active then state.color else Widgets.STROKE
	end
	local barState = state.bar
	if barState ~= nil and not bar.Visible and not reduced() then
		-- la barre de serveur glisse en place sous la pastille (GDD §9.4, début de la Balise)
		bar.Position = BEACON_BAR_POS - UDim2.fromOffset(0, BEACON_BAR.Y)
		Juice.tween(bar, 0.3, { Position = BEACON_BAR_POS }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	elseif barState ~= nil and not bar.Visible then
		bar.Position = BEACON_BAR_POS
	end
	bar.Visible = barState ~= nil
	if barState then
		local ratio = math.clamp(barState.points / barState.goal, 0, 1)
		barLabel.Text = Prefs.t("hud.event.beaconBar", { points = barState.points, goal = barState.goal })
		if math.abs(ratio - lastBarRatio) > 1e-4 then
			lastBarRatio = ratio
			if reduced() then
				fill.Size = UDim2.fromScale(ratio, 1)
			else
				-- la barre se remplit (Back Out, 0,3 s)
				Juice.tween(
					fill,
					0.3,
					{ Size = UDim2.fromScale(ratio, 1) },
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				)
			end
		end
	else
		lastBarRatio = -1
	end
end

local function updateRate()
	local label = rateLabel
	if label == nil then
		return
	end
	local rate = Glow.rate()
	label.Visible = rate > 0
	if rate > 0 then
		label.Text = Prefs.t("hud.glow.rate", { rate = Prefs.number(rate) })
	end
end

-- Touches du clavier : au clavier-souris seulement (la manette a ses icônes PadGlyph, le tactile
-- rien) ; texte selon la disposition du joueur (AZERTY : la touche Q s'écrit « A »)
local function updateKeyCaps()
	local keyboard = Platform.inputKind() == Platform.KEYBOARD
	for _, entry in keyCaps do
		if keyboard then
			entry.cap.Text = Platform.glyph(entry.key).text
		end
		entry.cap.Visible = keyboard
	end
end

-- Point écran (AbsolutePosition) → position dans le conteneur du HUD : origine, marge intérieure
-- (UIPadding de Root.safe) et mise à l'échelle (UIScale) prises en compte
toLocal = function(abs: Vector2): Vector2
	local s = safe
	if s == nil then
		return abs
	end
	local k = math.max(Root.scale(), 0.01)
	local padding = s:FindFirstChildOfClass("UIPadding")
	local inset = if padding
		then Vector2.new(padding.PaddingLeft.Offset, padding.PaddingTop.Offset)
		else Vector2.zero
	return (abs - s.AbsolutePosition) / k - inset
end

-- Bouton de saut tactile : recherche non bloquante (PlayerGui.TouchGui.TouchControlFrame.JumpButton)
local function findJump(): GuiObject?
	local player = localPlayer()
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	local touchGui = if playerGui then playerGui:FindFirstChild("TouchGui") else nil
	local frame = if touchGui then touchGui:FindFirstChild("TouchControlFrame") else nil
	local jump = if frame then frame:FindFirstChild("JumpButton") else nil
	return if jump and jump:IsA("GuiObject") then jump else nil
end

-- Taille de la zone intérieure du HUD en px de référence (zone sûre ÷ échelle − marges de
-- Root.safe) ; nil tant que le moteur ne l'a pas mesurée
local function contentSize(): Vector2?
	local s = safe
	local gui = if s then s.Parent else nil
	if s == nil or gui == nil or not gui:IsA("ScreenGui") then
		return nil
	end
	local abs = (gui :: ScreenGui).AbsoluteSize
	if not (isFinite(abs.X) and isFinite(abs.Y)) or abs.X <= 1 or abs.Y <= 1 then
		return nil
	end
	local k = math.max(Root.scale(), 0.01)
	local padding = s:FindFirstChildOfClass("UIPadding")
	local pad = if padding
		then Vector2.new(
			padding.PaddingLeft.Offset + padding.PaddingRight.Offset,
			padding.PaddingTop.Offset + padding.PaddingBottom.Offset
		)
		else Vector2.zero
	return abs / k - pad
end

local function box(x: number, y: number, w: number, h: number): Rect
	return { x0 = x, y0 = y, x1 = x + w, y1 = y + h }
end

-- Pastille d'événement pour une zone intérieure de largeur W (px de référence) : décalage du centre
-- par rapport au milieu de l'écran, largeur de la pastille, largeur de la barre de la Balise.
-- Centrée tant qu'elle laisse libres Équipage / Réglages (bord droit TOP_ROW_RIGHT) ; sur les
-- écrans étroits (640 × 360, 667 × 375 : zone intérieure < 1136 px) elle glisse vers la droite
-- sans toucher la minicarte, et ne rétrécit qu'en dernier recours. La barre de la Balise, centrée
-- sous elle (y 70-98, à hauteur de Réglages et de la minicarte), tient dans le même couloir.
local function pillGeometry(W: number): (number, number, number)
	local minLeft = TOP_ROW_RIGHT + CLEARANCE
	local maxRight = W - MARGIN - MINIMAP - CLEARANCE
	local width = math.floor(math.clamp(maxRight - minLeft, EVENT_MIN_WIDTH, EVENT_SIZE.X))
	local shift = math.max(0, math.ceil(minLeft - (W - width) / 2))
	shift = math.min(shift, math.max(0, math.floor(maxRight - (W + width) / 2)))
	local center = W / 2 + shift
	local half = math.min(center - minLeft, maxRight - center)
	local bar = math.clamp(math.floor(2 * half), width, BEACON_BAR.X)
	return shift, width, bar
end

-- Rectangle de la pastille d'événement (avec la barre de la Balise si `withBar`)
local function pillBox(W: number, withBar: boolean): Rect
	local shift, width, bar = pillGeometry(W)
	local w = if withBar then math.max(width, bar) else width
	local h = if withBar then EVENT_SIZE.Y + BEACON_BAR_POS.Y.Offset + BEACON_BAR.Y else EVENT_SIZE.Y
	return box(W / 2 + shift - w / 2, MARGIN, w, h)
end

-- Haut de l'instruction d'accueil (px de référence) pour une zone intérieure de hauteur `height` :
-- sous la pile complète de toasts ; plus haut seulement si le compteur de file l'exige (zone
-- intérieure < 486 px : écrans de moins de ~340 dp de haut) — le compteur de file reste lisible
local function hintTop(height: number?): number
	if height == nil or not isFinite(height) then
		return HINT_Y
	end
	local lineTop = height - LINE_Y - LINE_SIZE.Y
	return math.max(HINT_MIN_Y, math.min(HINT_Y, lineTop - CLEARANCE - HINT_SIZE.Y))
end

-- Bouton d'un élément affiché (révélé), nil sinon
local function shownButton(name: Types.HudElement, button: GuiObject?): GuiObject?
	local e = elements[name]
	return if e and e.revealed and button then button else nil
end

local function clearNav(button: GuiObject?)
	if button then
		button.NextSelectionUp = nil
		button.NextSelectionDown = nil
		button.NextSelectionLeft = nil
		button.NextSelectionRight = nil
	end
end

-- Navigation manette. Rail : voisins dans la grille des boutons AFFICHÉS (la grille les tasse) ;
-- Équipage ↔ Réglages, Ping ↔ Dash. À la manette (docs/07-console-ps5.md §6.2, §7), graphe complet
-- entre les boutons affichés, pour que tout le HUD et la minicarte soient atteignables depuis la
-- sélection de △ : rangée du haut (Équipage, Réglages, minicarte) ; ↑ depuis la 1re rangée du rail
-- → Équipage ; → depuis le rail → ACCLAMER, sinon suivi de quête, sinon Ping / Dash ; colonne de
-- droite minicarte → suivi de quête → Dash ; le rail s'arrête en bas (sauf ACCLAMER affiché : ↓ y
-- mène). Un lien ne vise jamais un bouton caché (recalculé à chaque révélation, à l'apparition et à
-- la disparition d'ACCLAMER, au changement d'entrée) ; hors manette, seuls les liens d'origine.
local function linkNav()
	local shown: { GuiObject } = {}
	for _, def in RAIL do
		local button = railButtons[def.panel]
		if button then
			clearNav(button)
			local e = elements[def.element]
			if e and e.revealed then
				table.insert(shown, button)
			end
		end
	end
	local columns = railColumns
	for i, button in shown do
		local column = (i - 1) % columns
		button.NextSelectionUp = shown[i - columns]
		button.NextSelectionDown = shown[i + columns]
		if column > 0 then
			button.NextSelectionLeft = shown[i - 1]
		end
		if column < columns - 1 then
			button.NextSelectionRight = shown[i + 1]
		end
	end
	local minimap = elements.minimap
	local disc: GuiObject? = if minimap and minimap.visual:IsA("GuiButton") then minimap.visual else nil
	local crew, settings, ping, dash = navButtons.crew, navButtons.settings, navButtons.ping, dashParts.button
	local toggle, cheerButton = trackerParts.toggle, cheerParts.button
	for _, button in { crew, settings, ping, dash, toggle, cheerButton, disc } :: { GuiObject? } do
		clearNav(button)
	end
	-- liens d'origine (valables partout)
	if crew and settings then
		crew.NextSelectionRight = settings
		settings.NextSelectionLeft = crew
	end
	if ping and dash then
		ping.NextSelectionRight = dash
		dash.NextSelectionLeft = ping
	end
	if not usingGamepad() then
		return
	end
	local C = if cheer ~= nil then cheerButton else nil
	local T = shownButton("questTracker", toggle)
	local M = shownButton("minimap", disc)
	local P = shownButton("ping", ping)
	local D = shownButton("dash", dash)
	local first, last = shown[1], shown[#shown]
	local top: { GuiObject } = {}
	for _, b in { shownButton("crew", crew), shownButton("settings", settings), M } :: { GuiObject? } do
		if b then
			table.insert(top, b)
		end
	end
	local topLast = top[#top]
	-- rangée du haut : gauche ↔ droite, ↓ vers le rail (la minicarte : vers le suivi de quête)
	for i, b in top do
		b.NextSelectionLeft = top[i - 1]
		b.NextSelectionRight = top[i + 1]
		b.NextSelectionDown = if b == M then T or D or P else first or T or P or D or C
	end
	-- rail : ↑ depuis la 1re rangée → Équipage ; → depuis la dernière colonne
	local railRight = C or T or P or D or M
	for i, b in shown do
		local column = (i - 1) % columns
		if i <= columns then
			b.NextSelectionUp = top[1]
		end
		if column == columns - 1 or i == #shown then
			b.NextSelectionRight = railRight
		end
	end
	if T then
		T.NextSelectionUp = M or topLast
		T.NextSelectionDown = D or P or C
		T.NextSelectionLeft = first or C or P
	end
	if D then
		D.NextSelectionLeft = P or C or last
		D.NextSelectionUp = T or M or topLast
	end
	if P then
		P.NextSelectionRight = D
		P.NextSelectionLeft = C or last
		P.NextSelectionUp = T or M or topLast
	end
	if C then
		C.NextSelectionRight = P or D
		C.NextSelectionLeft = last
		if last then
			last.NextSelectionDown = C
		end
	end
end

-- Rail : colonne du GDD (y = 150, 4 × 80 + 3 × 8 → y = 494), ou grille 2 × 2 dès y = 144 quand la
-- colonne descendrait dans le quart inférieur de la zone intérieure (joystick dynamique, GDD §10.1)
-- : téléphones de 360-390 dp de haut (zone intérieure ≈ 490-575 px de référence)
local function layoutRail()
	local rail, layout = railHolder, railLayout
	if rail == nil or layout == nil then
		return
	end
	local size = contentSize()
	local columnBottom = RAIL_Y + #RAIL * RAIL_BUTTON + (#RAIL - 1) * RAIL_GAP
	-- console : pas de joystick tactile, colonne du GDD (navigation ↑ / ↓, docs/07 §7)
	local columns = if size
			and columnBottom > JOYSTICK_TOP * size.Y
			and not Platform.isTenFoot()
		then RAIL_GRID_COLUMNS
		else 1
	local rows = math.ceil(#RAIL / columns)
	local dims = UDim2.fromOffset(
		columns * RAIL_BUTTON + (columns - 1) * RAIL_GAP,
		rows * RAIL_BUTTON + (rows - 1) * RAIL_GAP
	)
	-- manette : le rail descend sous son icône △ (elle-même sous la pastille Stardust)
	local pad = usingGamepad()
	local top = if columns > 1 then RAIL_GRID_Y else RAIL_Y
	if pad then
		top = math.max(top, RAIL_PAD_Y)
	end
	local position = UDim2.fromOffset(MARGIN, top)
	if rail.Size ~= dims then
		rail.Size = dims
	end
	if rail.Position ~= position then
		rail.Position = position
	end
	local glyphHolder = railGlyphHolder
	if glyphHolder then
		local at = UDim2.fromOffset(MARGIN + dims.X.Offset / 2, top - GLYPH_GAP)
		if glyphHolder.Position ~= at then
			glyphHolder.Position = at
		end
	end
	if layout.FillDirectionMaxCells ~= columns then
		layout.FillDirectionMaxCells = columns
	end
	if columns ~= railColumns or pad ~= railPadMode then
		railColumns = columns
		railPadMode = pad
		linkNav()
	end
end

-- Deux blocs plus proches que CLEARANCE
local function hits(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 + CLEARANCE
		and b.x0 < a.x1 + CLEARANCE
		and a.y0 < b.y1 + CLEARANCE
		and b.y0 < a.y1 + CLEARANCE
end

local function hitsAny(r: Rect, list: { Rect }): boolean
	for _, other in list do
		if hits(r, other) then
			return true
		end
	end
	return false
end

-- Plus haute place libre d'un bloc de bord droit `right`, entre `from` et `bottom` ; nil si aucune.
-- Les seules hauteurs à essayer : `from` et juste sous chaque obstacle.
local function firstFree(
	right: number,
	size: Vector2,
	from: number,
	bottom: number,
	obstacles: { Rect }
): number?
	local candidates = { from }
	for _, r in obstacles do
		local y = r.y1 + CLEARANCE
		if y > from then
			table.insert(candidates, y)
		end
	end
	table.sort(candidates)
	for _, y in candidates do
		if y + size.Y > bottom then
			return nil
		end
		if not hitsAny(box(right - size.X, y, size.X, size.Y), obstacles) then
			return y
		end
	end
	return nil
end

-- Déplace un élément de la colonne de droite (glissement s'il est déjà affiché)
local function placeColumn(name: Types.HudElement, position: UDim2)
	local e = elements[name]
	if e == nil or columnHome[name] == position then
		return
	end
	columnHome[name] = position
	if e.revealed and e.holder.Visible and not reduced() then
		Juice.tween(e.holder, COLUMN_MOVE, { Position = position })
	else
		e.holder.Position = position
	end
end

-- Colonne de droite (indicateurs d'état, suivi de quête) : positions du GDD sous la minicarte, sauf
-- si le Dash ou le Ping les recouvrent (téléphones de 360-390 dp de haut : le bouton de saut remonte
-- le Dash jusqu'à y ≈ 217-304). Elles passent alors dans une colonne à gauche de la minicarte, au
-- plus haut sans toucher la pastille d'événement (et sa barre de Balise si la largeur le permet),
-- l'instruction d'accueil, le compteur de file ni ACCLAMER (GDD §10.1, §10.2).
local function layoutColumn(dashPos: UDim2, dashSize: number, pingSize: number)
	local size = contentSize()
	local statusAt, trackerAt = STATUS_HOME, TRACKER_HOME
	if size then
		local W, H = size.X, size.Y
		local cx = dashPos.X.Scale * W + dashPos.X.Offset
		local cy = dashPos.Y.Scale * H + dashPos.Y.Offset
		local dash = box(cx - dashSize, cy - dashSize, dashSize, dashSize)
		local ping = box(cx - dashSize - PING_GAP - pingSize, cy - pingSize, pingSize, pingSize)
		local lineTop = H - LINE_Y - LINE_SIZE.Y
		local fixed: { Rect } = {
			dash,
			ping,
			box(W - MARGIN - MINIMAP, MARGIN, MINIMAP, MINIMAP),
			box((W - HINT_SIZE.X) / 2, hintTop(H), HINT_SIZE.X, HINT_SIZE.Y),
			box((W - LINE_SIZE.X) / 2, lineTop, LINE_SIZE.X, LINE_SIZE.Y),
			box((W - CHEER_SIZE.X) / 2, lineTop - 16 - CHEER_SIZE.Y, CHEER_SIZE.X, CHEER_SIZE.Y),
		}
		local statusHome = box(W - MARGIN - STATUS_WIDTH, STATUS_Y, STATUS_WIDTH, STATUS_HEIGHT)
		local trackerHome = box(W - MARGIN - TRACKER_SIZE.X, TRACKER_Y, TRACKER_SIZE.X, TRACKER_SIZE.Y)
		if hitsAny(statusHome, fixed) or hitsAny(trackerHome, fixed) then
			local pill = pillBox(W, false)
			local withBar = pillBox(W, true)
			local right = W - SIDE_RIGHT
			local cluster = math.min(dash.y0, ping.y0) - CLEARANCE
			local statusSize = Vector2.new(STATUS_WIDTH, STATUS_HEIGHT)
			-- d'abord au-dessus du Dash (colonne compacte), barre de Balise comprise puis non ;
			-- en dernier recours n'importe où dans l'écran
			local passes: { { top: Rect, bottom: number } } = {
				{ top = withBar, bottom = cluster },
				{ top = pill, bottom = cluster },
				{ top = withBar, bottom = H },
				{ top = pill, bottom = H },
			}
			for _, pass in passes do
				local obstacles = table.clone(fixed)
				table.insert(obstacles, pass.top)
				local bottom = pass.bottom
				local ty = firstFree(right, TRACKER_SIZE, MARGIN, bottom, obstacles)
				if ty ~= nil then
					table.insert(obstacles, box(right - TRACKER_SIZE.X, ty, TRACKER_SIZE.X, TRACKER_SIZE.Y))
					-- état : à sa place du GDD si elle reste libre, sinon sous le suivi
					local sy: number? = nil
					if hitsAny(statusHome, obstacles) then
						sy = firstFree(right, statusSize, ty + TRACKER_SIZE.Y + CLEARANCE, bottom, obstacles)
					end
					if sy ~= nil or not hitsAny(statusHome, obstacles) then
						trackerAt = UDim2.new(1, -SIDE_RIGHT, 0, ty)
						statusAt = if sy ~= nil then UDim2.new(1, -SIDE_RIGHT, 0, sy) else STATUS_HOME
						break
					end
				end
			end
		end
	end
	placeColumn("status", statusAt)
	placeColumn("questTracker", trackerAt)
end

-- Rectangle (px de référence de la zone intérieure W × H) d'un conteneur placé dans Safe
local function placedBox(position: UDim2, size: Vector2, anchor: Vector2, W: number, H: number): Rect
	local x = position.X.Scale * W + position.X.Offset - anchor.X * size.X
	local y = position.Y.Scale * H + position.Y.Offset - anchor.Y * size.Y
	return box(x, y, size.X, size.Y)
end

-- Point de la zone intérieure du HUD (px de référence) → px de la fenêtre, l'espace de la couche
-- plein écran de ScreenFX : AbsolutePosition se mesure sous la barre Roblox, GetGuiInset la rend
local function toViewport(x: number, y: number): Vector2
	local s = safe
	local k = math.max(Root.scale(), 0.01)
	local origin = if s then s.AbsolutePosition else Vector2.zero
	local padding = if s then s:FindFirstChildOfClass("UIPadding") else nil
	local inset = if padding
		then Vector2.new(padding.PaddingLeft.Offset, padding.PaddingTop.Offset)
		else Vector2.zero
	local bar = Vector2.zero
	pcall(function()
		local topLeft = GuiService:GetGuiInset()
		bar = topLeft
	end)
	return origin + (Vector2.new(x, y) + inset) * k + bar
end

-- Place de la pile des cartes « NOUVEAU ! » de ScreenFX (GDD §9.4, cartes de size × n, écart gap) :
-- le plus haut possible dans la colonne de droite (bord droit de la zone sûre − 16), sinon dans la
-- colonne à gauche de la minicarte, sans toucher la minicarte, l'état, le suivi de quête, la
-- pastille d'événement, les toasts, l'instruction d'accueil, le compteur de file, ACCLAMER ni le
-- coin des actions (Dash, Ping et le bouton de saut dessous, GDD §10.1) ; autant de cartes que la
-- place en permet (au moins 1). Repli (écran trop bas) : une carte juste au-dessus du Dash et du
-- Ping, quitte à couvrir l'état ou la minicarte. nil tant que le HUD n'est pas mesuré.
local function cardPlacement(size: Vector2, gap: number, wanted: number): ScreenFX.CardPlacement?
	local content = contentSize()
	local dash, ping = dashParts.holder, pingHolder
	if content == nil or dash == nil or ping == nil then
		return nil
	end
	if not (isFinite(size.X) and isFinite(size.Y) and isFinite(gap) and isFinite(wanted)) then
		return nil
	end
	local W, H = content.X, content.Y
	local dashBox =
		placedBox(dash.Position, Vector2.new(dash.Size.X.Offset, dash.Size.Y.Offset), dash.AnchorPoint, W, H)
	local pingBox =
		placedBox(ping.Position, Vector2.new(ping.Size.X.Offset, ping.Size.Y.Offset), ping.AnchorPoint, W, H)
	local cx0 = math.min(dashBox.x0, pingBox.x0)
	local cy0 = math.min(dashBox.y0, pingBox.y0)
	local lineTop = H - LINE_Y - LINE_SIZE.Y
	-- pastille d'événement (décalée sur écran étroit), avec la barre de la Balise quand elle est
	-- affichée
	local bar = eventParts.bar
	local pill = pillBox(W, bar ~= nil and bar.Visible)
	local obstacles: { Rect } = {
		-- coin des actions jusqu'au bas de l'écran : Dash, Ping et bouton de saut tactile
		box(cx0, cy0, W - cx0, H - cy0),
		box(W - MARGIN - MINIMAP, MARGIN, MINIMAP, MINIMAP),
		pill,
		box((W - TOAST_WIDTH) / 2, TOAST_TOP, TOAST_WIDTH, TOAST_BOTTOM - TOAST_TOP),
		box((W - HINT_SIZE.X) / 2, hintTop(H), HINT_SIZE.X, HINT_SIZE.Y),
		box((W - LINE_SIZE.X) / 2, lineTop, LINE_SIZE.X, LINE_SIZE.Y),
		box((W - CHEER_SIZE.X) / 2, lineTop - 16 - CHEER_SIZE.Y, CHEER_SIZE.X, CHEER_SIZE.Y),
	}
	-- état et suivi de quête affichés, à leur place cible (layoutColumn)
	local column: { [string]: Vector2 } = {
		status = Vector2.new(STATUS_WIDTH, STATUS_HEIGHT),
		questTracker = TRACKER_SIZE,
	}
	for name, blockSize in column do
		local e = elements[name :: Types.HudElement]
		local home = columnHome[name]
		if e and e.revealed and home then
			table.insert(obstacles, placedBox(home, blockSize, Vector2.new(1, 0), W, H))
		end
	end
	local function placement(right: number, y: number, count: number): ScreenFX.CardPlacement
		local at = toViewport(right, y)
		return { right = at.X, top = at.Y, count = count }
	end
	for n = math.max(1, math.floor(wanted)), 1, -1 do
		local stack = Vector2.new(size.X, n * size.Y + (n - 1) * gap)
		for _, right in { W - MARGIN, W - SIDE_RIGHT } do
			local y = firstFree(right, stack, MARGIN, H, obstacles)
			if y ~= nil then
				return placement(right, y, n)
			end
		end
	end
	return placement(W - MARGIN, math.max(0, cy0 - CLEARANCE - size.Y), 1)
end

local function layoutActions()
	layoutRail()
	local dash, ping, s = dashParts.holder, pingHolder, safe
	if dash == nil or ping == nil or s == nil then
		return
	end
	-- cible tactile ≥ 56 px réels même à l'échelle minimale (Ping 72 × 0,6 = 43 px sinon)
	local k = math.max(Root.scale(), 0.01)
	local dashSize = math.max(DASH, math.ceil(MIN_TOUCH / k))
	local pingSize = math.max(PING, math.ceil(MIN_TOUCH / k))
	if dash.Size.X.Offset ~= dashSize then
		dash.Size = UDim2.fromOffset(dashSize, dashSize)
	end
	if ping.Size.X.Offset ~= pingSize then
		ping.Size = UDim2.fromOffset(pingSize, pingSize)
	end
	if InputController.inputType() == 1 then
		local jump = jumpButton
		if jump == nil or jump.Parent == nil then
			jump = findJump()
			jumpButton = jump
		end
		if jump and jump.AbsoluteSize.X > 0 then
			-- coin bas droit du Dash = coin haut gauche du saut − 16 px (coordonnées du HUD)
			local corner = toLocal(jump.AbsolutePosition) - Vector2.new(MARGIN, MARGIN)
			dash.Position = UDim2.fromOffset(corner.X, corner.Y)
		else
			dash.Position = UDim2.new(1, TOUCH_FALLBACK.X, 1, TOUCH_FALLBACK.Y)
		end
	else
		dash.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
	end
	-- Ping à gauche du Dash, bas alignés
	ping.Position = dash.Position + UDim2.fromOffset(-dashSize - PING_GAP, 0)
	-- pastille d'événement et barre de la Balise : jamais sur Équipage / Réglages ni la minicarte
	-- (téléphones 16:9 étroits, zone sûre TV) — pillGeometry
	local size = contentSize()
	local bar = eventParts.bar
	local pillHolder = if elements.eventPill then elements.eventPill.holder else nil
	if size and bar then
		local shift, width, barWidth = pillGeometry(size.X)
		if bar.Size.X.Offset ~= barWidth then
			bar.Size = UDim2.fromOffset(barWidth, BEACON_BAR.Y)
		end
		if pillHolder then
			local position = UDim2.new(0.5, shift, 0, MARGIN)
			if pillHolder.Position ~= position then
				pillHolder.Position = position
			end
			if pillHolder.Size.X.Offset ~= width then
				pillHolder.Size = UDim2.fromOffset(width, EVENT_SIZE.Y)
			end
		end
	end
	layoutColumn(dash.Position, dashSize, pingSize)
end

-- Acclamation -----------------------------------------------------------------------------------

local function hideCheer()
	local current = cheer
	cheer = nil
	InputController.setCheerAvailable(false)
	local holder = cheerParts.holder
	if holder == nil or current == nil then
		return
	end
	linkNav()
	-- manette : la sélection ne reste jamais sur un bouton qui disparaît
	local button = cheerParts.button
	if button and GuiService.SelectedObject == button then
		if not HUD.selectRail() then
			pcall(function()
				GuiService.SelectedObject = nil
			end)
		end
	end
	if reduced() then
		holder.Visible = false
		return
	end
	local target = UDim2.new(0.5, 0, 1, -LINE_Y - LINE_SIZE.Y - 16 + 140)
	local tween =
		Juice.tween(holder, 0.2, { Position = target }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween.Completed:Once(function()
		if cheer == nil then
			holder.Visible = false
		end
	end)
end

local function onCheerPrompt(payload: any)
	local player = localPlayer()
	if type(payload) ~= "table" or player == nil then
		return
	end
	local heroId, level, expiresAt = payload.heroId, payload.level, payload.expiresAt
	if not isFinite(heroId) or heroId % 1 ~= 0 or heroId <= 0 or heroId == player.UserId then
		return
	end
	if not isFinite(level) or level < 1 or level > 1e6 then
		return
	end
	local now = Clock.now()
	if not isFinite(expiresAt) or expiresAt <= now or expiresAt > now + Balance.Cheer.Window * 3 then
		return
	end
	cheer = {
		heroId = heroId,
		level = math.floor(level),
		expiresAt = expiresAt,
		total = math.max(expiresAt - now, 0.1),
	}
	InputController.setCheerAvailable(true)
	local holder, name = cheerParts.holder, cheerParts.name
	if holder == nil or name == nil then
		return
	end
	local title = Prefs.t("celebrate.supernova", { level = Text.roman(level) })
	local heroName = nameOf(heroId)
	name.Text = if heroName then heroName .. " · " .. title else title
	holder.Visible = true
	linkNav()
	local target = UDim2.new(0.5, 0, 1, -LINE_Y - LINE_SIZE.Y - 16)
	if reduced() then
		holder.Position = target
	else
		-- le bouton monte du bas en 0,3 s (Back Out)
		holder.Position = target + UDim2.fromOffset(0, 140)
		Juice.tween(
			holder,
			CHEER_SLIDE,
			{ Position = target },
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
	end
	cheerParts.shownAt = uiTime
end

local function onCheerRequested()
	local current = cheer
	if current == nil or Clock.now() >= current.expiresAt then
		return
	end
	local remote = cheerRemote
	if remote then
		remote:FireServer(current.heroId)
	end
	-- « Appuyer joue l'emote cheer » (GDD §6.6) ; l'arc de confettis et le son : VFXController
	InputController.playEmote(CHEER_EMOTE)
	local button = cheerParts.button
	if button then
		Juice.pulse(button, 1.2)
	end
	hideCheer()
end

-- Le héros quitte le serveur : plus personne à acclamer
local function onPlayerRemoving(player: Player)
	local current = cheer
	if current ~= nil and player.UserId == current.heroId then
		hideCheer()
	end
end

-- Image -----------------------------------------------------------------------------------------

local function stepGlow(now: number)
	local counter = glowCounter
	if counter == nil then
		return
	end
	local predicted = Glow.predicted(now)
	if glowDirty then
		glowDirty = false
		local jump = predicted - lastGlowTarget
		-- gain ou dépense discrets (parade, quête, achat) ≠ dérive du revenu passif
		local threshold = Glow.rate() + 1
		if math.abs(jump) > threshold then
			counter:set(predicted, uiTime, true)
		else
			counter:set(predicted, uiTime, false)
		end
	else
		counter:set(predicted, uiTime, false)
	end
	lastGlowTarget = predicted
	counter:step(uiTime)
end

-- Objet réellement affiché : lui et ses ancêtres visibles, dans un écran activé
local function onScreen(obj: Instance): boolean
	local cur: Instance? = obj
	while cur ~= nil and cur:IsA("GuiObject") do
		if not (cur :: GuiObject).Visible then
			return false
		end
		cur = cur.Parent
	end
	return cur ~= nil and cur:IsA("LayerCollector") and (cur :: LayerCollector).Enabled
end

-- Bouton Accepter de la carte d'invitation d'équipage tant qu'elle est affichée
-- (PanelController.focusTarget, docs/07 §6.7), nil sinon
local function invitationTarget(): GuiObject?
	local ok, focus = pcall(PanelController.focusTarget)
	local target: any = if ok then focus else nil
	if typeof(target) == "Instance" and target:IsA("GuiObject") and onScreen(target) then
		return target :: GuiObject
	end
	return nil
end

local function stepAttention()
	local reducedMotion = reduced()
	local pulse = 1
		+ ATTENTION_AMPLITUDE / 2
		+ ATTENTION_AMPLITUDE / 2 * math.sin(2 * math.pi * uiTime / ATTENTION_PERIOD)
	for _, e in elements do
		local s = e.scale
		if s and e.revealed and uiTime >= e.revealEnd then
			local active = e.attention or uiTime < e.pulseUntil
			if active and not reducedMotion then
				s.Scale = pulse
			elseif s.Scale ~= 1 and not active then
				s.Scale = 1
			end
		end
	end
	local h = hand
	local target = handTarget
	local active = target ~= nil and target.attention and target.revealed and target.holder.Visible
	local pad = usingGamepad()
	local bob = if reducedMotion then 0 else math.sin(2 * math.pi * uiTime / 1.2) * 6
	if h then
		if active and not pad and target then
			h.Visible = true
			local corner = toLocal(target.visual.AbsolutePosition + target.visual.AbsoluteSize * 0.6)
			h.Position = UDim2.fromOffset(corner.X, corner.Y + bob)
		else
			h.Visible = false
		end
	end
	-- manette : icône de la touche à presser à la place de la main (docs/07 §6.2) : R2 pour le Dash,
	-- △ pour un bouton du rail, puis ✕ une fois ce bouton sélectionné ; à droite de la cible (moitié
	-- gauche de l'écran) ou au-dessus (moitié droite). Carte d'invitation d'équipage affichée : △ la
	-- sélectionne d'abord (HUD.selectRail) et l'annonce sur Accepter — pas de second △ au rail
	local g = handGlyph
	if g then
		local key: Enum.KeyCode? = nil
		if active and pad and target then
			if target == elements.dash then
				key = Enum.KeyCode.ButtonR2
			elseif GuiService.SelectedObject == target.visual then
				key = Enum.KeyCode.ButtonA
			elseif invitationTarget() == nil then
				key = Enum.KeyCode.ButtonY
			end
			local visual = target.visual
			local topLeft = toLocal(visual.AbsolutePosition)
			local size = visual.AbsoluteSize / math.max(Root.scale(), 0.01)
			local area = contentSize()
			local half = if area then area.X / 2 else math.huge
			local nudge = math.abs(bob)
			if topLeft.X + size.X / 2 < half then
				g.frame.AnchorPoint = Vector2.new(0, 0.5)
				g.frame.Position =
					UDim2.fromOffset(topLeft.X + size.X + GLYPH_GAP + nudge, topLeft.Y + size.Y / 2)
			else
				g.frame.AnchorPoint = Vector2.new(0.5, 1)
				g.frame.Position = UDim2.fromOffset(topLeft.X + size.X / 2, topLeft.Y - GLYPH_GAP - nudge)
			end
		end
		if handKey ~= key then
			handKey = key
			g:set({ gamepad = key })
		end
	end
end

local function stepDash(now: number)
	local radial, button, flash = dashParts.radial, dashParts.button, dashParts.flash
	if radial == nil or button == nil or flash == nil then
		return
	end
	local progress = InputController.dashProgress(now)
	radial.set(1 - progress)
	local ready = progress >= 1
	if ready and not dashWasReady then
		-- prêt : pop 1,15 + éclair
		Juice.pulse(button, 1.15)
		if not reduced() then
			flash.BackgroundTransparency = 0.35
			Juice.tween(flash, 0.25, { BackgroundTransparency = 1 })
		end
	end
	dashWasReady = ready
end

local function stepCheer(now: number)
	local current = cheer
	if current == nil then
		return
	end
	if now >= current.expiresAt then
		hideCheer()
		return
	end
	local ring = cheerParts.ring
	if ring then
		ring.set(math.clamp((current.expiresAt - now) / current.total, 0, 1))
	end
end

local function stepLineFx()
	local stroke, arrow = lineParts.stroke, lineParts.arrow
	if stroke then
		local age = uiTime - fullFlashAt
		if age >= 0 and age < FULL_FLASH_TIME then
			-- 2 clignotements rouges en 0,3 s ; Mouvement réduit : contour rouge fixe (pas de flash
			-- répété, GDD §9.1, §13.2)
			local blinkOn = reduced() or math.floor(age / (FULL_FLASH_TIME / 4)) % 2 == 0
			stroke.Color = if blinkOn then Theme.Colors.Danger else Widgets.STROKE
		elseif stroke.Color ~= Widgets.STROKE then
			stroke.Color = Widgets.STROKE
		end
	end
	if arrow then
		local visible = uiTime < arrowUntil
		arrow.Visible = visible
		if visible then
			local slot = localSlot()
			local camera = workspace.CurrentCamera
			if slot ~= 0 and camera then
				local rel = camera.CFrame:PointToObjectSpace(WorldLayout.gateCFrame(slot).Position)
				arrow.Rotation = math.deg(math.atan2(rel.X, -rel.Z))
			end
		end
	end
end

local function stepShine()
	if reduced() or uiTime - lastShine < SHINE_EVERY then
		return
	end
	lastShine = uiTime
	for _, gradient in shines do
		gradient.Offset = Vector2.new(-1, 0)
		Juice.tween(gradient, SHINE_TIME, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Linear)
	end
end

local function stepEventBlink()
	local label = eventParts.label
	local state = lastPill
	if label == nil or state == nil then
		return
	end
	local transparency = if state.blink
			and not reduced()
			and math.floor(uiTime * BLINK_HZ * 2) % 2 == 1
		then 0.45
		else 0
	if label.TextTransparency ~= transparency then
		label.TextTransparency = transparency
	end
end

local function onFrame(dt: number)
	uiTime += if isFinite(dt) then math.clamp(dt, 0, 0.25) else 0
	local now = Clock.now()
	stepGlow(now)
	local dust = dustCounter
	if dust then
		dust:step(uiTime)
	end
	stepDash(now)
	stepCheer(now)
	stepAttention()
	stepLineFx()
	stepShine()
	stepEventBlink()
	if uiTime - lastSlow >= SLOW_UPDATE or uiTime < lastSlow then
		lastSlow = uiTime
		updateEventPill(now)
		updateStatus(now)
		updateTracker(now)
		updateRate()
	end
	-- bouton de saut tactile (apparu, déplacé) et taille d'écran (rotation, fenêtre PC)
	if uiTime - lastTouchCheck >= TOUCH_CHECK then
		lastTouchCheck = uiTime
		layoutActions()
	end
end

-- Badges des panneaux -----------------------------------------------------------------------------

local function setBadge(name: string, on: boolean)
	local badge = badges[name]
	if badge then
		badge.Visible = on == true
	end
end

-- Textes ----------------------------------------------------------------------------------------

local function applyTexts()
	for _, entry in texts do
		entry.label.Text = Prefs.t(entry.key)
	end
	local glow, dust = glowCounter, dustCounter
	if glow then
		glow:refresh()
	end
	if dust then
		dust:refresh()
	end
	updateLine(false)
	trackerParts.key = ""
	lastSlow = -math.huge
end

-- API publique ----------------------------------------------------------------------------------

-- Affiche un élément (animé : pop + pulsation) ; idempotent
function HUD.reveal(element: Types.HudElement, animate: boolean?)
	local e = elements[element]
	if e == nil then
		earlyReveals[element] = true
		return
	end
	if e.revealed then
		return
	end
	if string.sub(element, 1, 5) == "rail." then
		HUD.reveal("rail", false)
	end
	e.revealed = true
	e.holder.Visible = true
	local s = e.scale
	if animate and s and not reduced() and element == "questTracker" then
		-- « le suivi de quête glisse à droite » (GDD §3, ~25 s) : entrée par le bord droit, jusqu'à
		-- sa place courante (colonne du GDD ou de repli)
		local target = columnHome.questTracker or e.holder.Position
		s.Scale = 1
		e.holder.Position = target + UDim2.fromOffset(TRACKER_SIZE.X + 2 * MARGIN, 0)
		e.revealEnd = uiTime + TRACKER_SLIDE
		e.pulseUntil = uiTime + REVEAL_PULSE
		Juice.tween(
			e.holder,
			TRACKER_SLIDE,
			{ Position = target },
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
		AudioController.play("Whoosh", 0.05)
	elseif animate and s and not reduced() then
		s.Scale = 0
		e.revealEnd = uiTime + REVEAL_TIME
		e.pulseUntil = uiTime + REVEAL_PULSE
		Juice.tween(s, REVEAL_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		AudioController.play("Pop", 0.05)
	elseif s then
		s.Scale = 1
	end
	if element == "status" then
		updateShield()
	elseif element == "rail" and railGlyphHolder then
		(railGlyphHolder :: Frame).Visible = true
	elseif element == "dash" or element == "ping" then
		layoutActions()
	end
	-- graphe de navigation : le nouveau bouton devient atteignable
	linkNav()
end

function HUD.isRevealed(element: Types.HudElement): boolean
	local e = elements[element]
	if e then
		return e.revealed
	end
	return earlyReveals[element] == true
end

-- Tout afficher (joueur ayant fini l'accueil)
function HUD.revealAll()
	for name in elements do
		HUD.reveal(name :: Types.HudElement, false)
	end
	for _, name in
		{
			"glow",
			"stardust",
			"line",
			"dash",
			"ping",
			"rail",
			"rail.Upgrades",
			"rail.Collection",
			"rail.Goals",
			"rail.Shop",
			"eventPill",
			"minimap",
			"status",
			"questTracker",
			"crew",
			"settings",
		} :: { Types.HudElement }
	do
		HUD.reveal(name, false)
	end
end

-- Élément d'interface d'ancrage (cible des pièces volantes, des flèches d'accueil)
function HUD.anchor(element: Types.HudElement): GuiObject?
	local e = elements[element]
	return if e then e.visual else nil
end

-- Fait pulser un élément pour attirer l'attention (accueil) ; false arrête
function HUD.attention(element: Types.HudElement, on: boolean)
	local e = elements[element]
	if e == nil then
		return
	end
	e.attention = on == true
	if e.attention then
		-- la main d'accueil désigne les boutons du rail
		if string.sub(element, 1, 5) == "rail." or element == "dash" then
			handTarget = e
		end
	else
		if handTarget == e then
			-- la main revient sur un autre élément qui attire encore l'attention (ex. Améliorer
			-- pendant Q5 « Achète Foulée » après la pulsation du Dash)
			handTarget = nil
			for _, name in HAND_ELEMENTS do
				local other = elements[name]
				if other and other ~= e and other.attention then
					handTarget = other
					break
				end
			end
		end
		local s = e.scale
		if s and e.revealed and uiTime >= e.revealEnd then
			s.Scale = 1
		end
	end
end

-- Ajouts du paquet client-hud ---------------------------------------------------------------------

-- Un module plus tardif (Minimap) confie son conteneur au système d'affichage progressif
function HUD.registerElement(element: Types.HudElement, holder: GuiObject, visual: GuiObject?)
	if elements[element] ~= nil then
		return
	end
	register(element, holder, visual)
end

local function selectObject(target: GuiObject): boolean
	local ok = pcall(function()
		GuiService.SelectedObject = target
	end)
	return ok
end

-- Bouton affiché du rail pour ce panneau, nil sinon
local function railButton(panel: Types.PanelName): GuiObject?
	for _, def in RAIL do
		if def.panel == panel then
			local e = elements[def.element]
			local button = railButtons[panel]
			if e and e.revealed and button and onScreen(button) then
				return button
			end
		end
	end
	return nil
end

-- △ (manette, docs/07-console-ps5.md §6.2, §6.7) : sélection de départ du menu du HUD, par
-- priorité : la cible hors fenêtre de PanelController.focusTarget() (carte d'invitation d'équipage,
-- passagère), la cible de l'accueil (main / pulsation), le bouton du rail à pastille « ! », le
-- dernier panneau du rail ouvert, le premier bouton affiché du rail. false : rien à sélectionner.
-- Mode menu : la sélection manette est dans le HUD ou la minicarte (le stick la déplace au lieu de
-- faire marcher) ; ○ rend la main au jeu (InputController efface la sélection)
local function hudMenuMode(): boolean
	local ok, selected = pcall(function()
		return GuiService.SelectedObject
	end)
	if not ok or typeof(selected) ~= "Instance" then
		return false
	end
	local gui = (selected :: Instance):FindFirstAncestorWhichIsA("ScreenGui")
	return gui ~= nil and (gui.Name == "HUD" or gui.Name == "Minimap")
end

-- Icône au-dessus du rail : △ (entrer dans le menu) en jeu, ○ + « Jouer » en mode menu ; le
-- libellé n'est montré qu'à la manette (l'icône se masque seule ailleurs, UI/Glyph)
local function refreshRailHint()
	local menu = hudMenuMode()
	local glyph = padGlyphs.rail
	if glyph and menu ~= railMenuMode then
		railMenuMode = menu
		glyph:set({ gamepad = if menu then Enum.KeyCode.ButtonB else Enum.KeyCode.ButtonY })
	end
	local hint = railHint
	if hint then
		local show = menu and usingGamepad()
		if hint.Visible ~= show then
			hint.Visible = show
		end
	end
end

function HUD.selectRail(): boolean
	-- écran de chargement encore là (src/first/Loading.client) : le rail est caché derrière lui,
	-- jamais un bouton invisible sélectionné (✕ l'activerait à l'aveugle)
	local player = localPlayer()
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui ~= nil and playerGui:FindFirstChild("Loading") ~= nil then
		return false
	end
	-- carte d'invitation d'équipage d'abord (docs/07 §6.7) : elle est passagère (20 s) et n'est
	-- reliée à aucun bouton du HUD (autre ScreenGui), alors que la cible de l'accueil sera toujours
	-- là après ; sa propre icône annonce △ sur Accepter
	local target = invitationTarget()
	if target then
		return selectObject(target)
	end
	for _, name in HAND_ELEMENTS do
		local e = elements[name]
		if e and e.attention and e.revealed and e.visual:IsA("GuiButton") and onScreen(e.visual) then
			return selectObject(e.visual)
		end
	end
	for _, def in RAIL do
		local badge = badges[def.panel]
		local button = railButton(def.panel)
		if button and badge and badge.Visible then
			return selectObject(button)
		end
	end
	local last = if lastRailPanel then railButton(lastRailPanel) else nil
	if last then
		return selectObject(last)
	end
	for _, def in RAIL do
		local button = railButton(def.panel)
		if button then
			return selectObject(button)
		end
	end
	return false
end

-- Haut de l'instruction d'accueil (écran Onboarding) pour la hauteur courante de l'écran : une seule
-- règle pour l'accueil qui la place et pour la colonne de droite qui l'évite (layoutColumn)
function HUD.hintTop(): number
	local size = contentSize()
	return hintTop(if size then size.Y else nil)
end

-- Le bouton ACCLAMER (10 s, au-dessus du compteur de file) occupe la place de l'instruction d'accueil
-- (téléphones de 360-390 dp : zone intérieure < 590 px de référence) : l'accueil efface son
-- instruction le temps de l'acclamation. Écran pas encore mesuré : on suppose qu'il l'occupe.
function HUD.cheerOverHint(): boolean
	if cheer == nil then
		return false
	end
	local size = contentSize()
	if size == nil then
		return true
	end
	local cheerTop = size.Y - LINE_Y - LINE_SIZE.Y - 16 - CHEER_SIZE.Y
	return hintTop(size.Y) + HINT_SIZE.Y + CLEARANCE > cheerTop
end

-- Exposé pour les tests
HUD._state = function()
	return {
		elements = elements,
		lineParts = lineParts,
		dashParts = dashParts,
		eventParts = eventParts,
		cheer = cheer,
		cheerParts = cheerParts,
		trackerParts = trackerParts,
		statusParts = statusParts,
		badges = badges,
		glowCounter = glowCounter,
		dustCounter = dustCounter,
		hand = hand,
		handTarget = handTarget,
		handGlyph = handGlyph,
		padGlyphs = padGlyphs,
		lastRailPanel = lastRailPanel,
		safe = safe,
		railColumns = railColumns,
	}
end
HUD._onCheerPrompt = onCheerPrompt
HUD._layoutActions = layoutActions

-- Cycle de vie ----------------------------------------------------------------------------------

local function markReady()
	local player = localPlayer()
	if player then
		-- attribut LOCAL (non répliqué) : l'écran de chargement se ferme
		player:SetAttribute("ClientReady", true)
	end
end

-- Entrée préférée changée (manette ↔ clavier ↔ tactile) : touches, place du rail, navigation
local function onInputChanged()
	updateKeyCaps()
	layoutActions()
	linkNav()
end

function HUD.Init()
	-- entrée préférée suivie avant toute construction (idempotent ; déjà fait par Main.client)
	Platform.Init()
	build()
	cheerRemote = Net.event("Cheer")
	-- crochet : ScreenFX (plus précoce) fait voler les récompenses vers nos compteurs
	ScreenFX.setAnchorResolver(HUD.anchor)
	-- crochet : cartes « NOUVEAU ! » de l'Atlas rangées dans la place libre de la colonne de droite
	ScreenFX.setCardPlacer(cardPlacement)
	-- crochet : ScreenFX laisse au panneau Collection ouvert sa propre révélation de Starforge
	ScreenFX.setPanelResolver(function(): string?
		return PanelController.current()
	end)
	-- garde des raccourcis : pas de panneau dont l'icône n'est pas encore affichée
	InputController.setPanelGate(function(name: Types.PanelName): boolean
		local element = PANEL_ELEMENT[name]
		return element == nil or HUD.isRevealed(element)
	end)
end

function HUD.Start()
	if started then
		return
	end
	started = true
	Platform.Init()
	build()
	-- monnaies : gains discrets détectés à l'image suivante (patchs appliqués clé par clé)
	for _, key in { "glow", "glowCarry", "lastSettle", "idleRate" } do
		State.observe(key, function()
			glowDirty = true
		end)
	end
	State.observe("stardust", function(value: any)
		local counter = dustCounter
		if counter and isFinite(value) then
			local amount = math.max(0, math.floor(value))
			-- instantané initial : valeur posée sans défilement ni pop
			if State.ready then
				counter:set(amount, uiTime, true)
			else
				counter:snap(amount)
			end
		end
	end)
	State.observe("upgrades", function()
		updateLine(false)
	end)
	State.observe("settings", function()
		updateLine(false)
	end)
	local function onReady()
		local glow, dust = glowCounter, dustCounter
		if glow then
			lastGlowTarget = Glow.predicted()
			glow:snap(lastGlowTarget)
		end
		if dust then
			dust:snap(math.max(0, math.floor(num(State.get("stardust"), 0))))
		end
		updateLine(false)
		markReady()
	end
	if State.ready then
		onReady()
	else
		State.ReadySignal:Once(onReady)
	end
	WorldStateController.LineOp:Connect(function(slot: number)
		if slot ~= 0 and slot == localSlot() then
			updateLine(true)
		end
	end)
	WorldStateController.Snipped:Connect(function(payload: Types.SnipEventPayload)
		if type(payload) == "table" and payload.victimSlot == localSlot() then
			updateLine(false)
		end
	end)
	WorldStateController.OwnerChanged:Connect(function()
		updateLine(false)
	end)
	WorldStateController.Ready:Connect(function()
		updateLine(false)
	end)
	ScreenFX.FeedbackReceived:Connect(function(payload: Types.FeedbackPayload)
		if payload.key == "feedback.lineFull" then
			fullFlashAt = uiTime
			arrowUntil = uiTime + FULL_ARROW_TIME
		end
	end)
	-- pastilles « ! » : PanelController réévalue hasAction() et signale chaque changement
	PanelController.BadgeChanged:Connect(setBadge)
	InputController.CheerRequested:Connect(onCheerRequested)
	InputController.RailRequested:Connect(HUD.selectRail)
	-- croix ← (manette) : replier / déplier le suivi de quête (docs/07 §6.1)
	InputController.QuestToggled:Connect(function()
		if HUD.isRevealed("questTracker") then
			setTrackerCollapsed(not trackerParts.collapsed)
		end
	end)
	-- dernier panneau du rail ouvert : sélection de départ de △ (docs/07 §6.2)
	PanelController.Opened:Connect(function(name: Types.PanelName)
		local panel = RAIL_PANEL[name]
		if panel then
			lastRailPanel = panel
		end
	end)
	InputController.InputTypeChanged:Connect(onInputChanged)
	Platform.Changed:Connect(function(reason: string)
		if reason == "input" then
			onInputChanged()
		end
		refreshRailHint()
	end)
	-- mode menu (sélection dans le HUD ou la minicarte) : ○ + « Jouer » au-dessus du rail
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(refreshRailHint)
	Prefs.LanguageChanged:Connect(refreshRailHint)
	refreshRailHint()
	InputController.DashRefused:Connect(function(reason: string)
		local button = dashParts.button
		if button and reason ~= "character" then
			Juice.shake(button)
		end
	end)
	Net.event("CheerPrompt").OnClientEvent:Connect(onCheerPrompt)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	local player = localPlayer()
	if player then
		for _, attribute in { "Rookie", "Unstable", "Zen" } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				updateStatus(Clock.now())
				if attribute == "Zen" then
					updateLine(false)
				end
			end)
		end
	end
	Prefs.LanguageChanged:Connect(applyTexts)
	updateKeyCaps()
	layoutActions()
	updateLine(false)
	RunService.RenderStepped:Connect(onFrame)
end

return HUD
