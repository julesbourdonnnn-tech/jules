--!strict
-- Panels/Upgrades (lot B2, étape 2 ; docs/04 §27.7, §27.8 ; GDD v2.0 §10.7, §10.8) : l'écran
-- Améliorations, panneau de PanelController (fenêtre NUE, décision D5 : l'en-tête est celui du §27.8).
--
--   Upgrades.build(body)          -- une seule fois, au premier instantané valide (D2)
--   Upgrades.open(tab?)           -- « suggested » (défaut), « ranch », « helpers », « workshop »,
--                                 -- « spendFirst » (onglet Ranch, sélection sur la première ligne
--                                 -- gardée payable, sinon la première gardée)
--   Upgrades.close() / Upgrades.isOpen()
--   + l'interface des panneaux (setNavigator, tabs, currentTab, setTab, defaultSelection, onBack,
--     visible, refresh, scroll)
--
-- Règles (plan du lot B2, décisions D1, D2, D4, D5, D7, D8, D22 ; GDD §10.7.3 à §10.7.5, §10.8) :
--  * construit UNE fois (30 lignes fixes du composant unique UI/UpgradeCard, 3 cartes, aucune liste
--    recyclée : chaque ligne montre UN identifiant toute la session, FocusId = identifiant) ; rouvrir
--    ne crée aucune instance ; budget de l'écran : Layout.Upgrades.MaxInstances (règle 20) ;
--  * disposition tirée de Config/Layout.Upgrades seulement (zones 12 + 88 + 64 + 560 + 120 + 16) ;
--  * gel à l'ouverture (D7, D8) : l'ensemble des lignes montrées, l'état cadenas / boucle de chaque
--    ligne (plafonds, r, Record R et A de l'instantané d'ouverture), les familles du Conseillé et les
--    lignes « Conseillé » de l'Atelier ; écran ouvert, un instantané plus récent ne change que les
--    pièces, les Confettis et les niveaux (donc Prêt / Il manque / MAX) ; une ligne coupée par un
--    interrupteur est cachée (D8), positions recalculées à l'ouverture seulement ;
--  * seul l'instantané versionné est lu (UI/UpgradeSnapshot, règle 6) ; chiffres arabes ; aucun Robux ;
--  * compteurs de l'en-tête : jamais depuis 0, valeur finale toujours posée (règles 3, 4 : petit
--    compteur sur Clock, aucune connexion par image quand rien ne bouge) ;
--  * console d'abord : croix, ✕ et ○ suffisent ; L1 / R1 changent d'onglet (PanelController) ; □ (E au
--    clavier) change le mode ×1 → ×10 → Max → ×1 ; ↑ depuis les onglets atteint le bouton de mode ;
--    lignes en lecture seule sélectionnables, ✕ y joue Bump sans vibration ; le mode revient à ×1 à
--    chaque ouverture.
-- Achats (lot B2, étape 3 ; décisions D9, D10, D11, D28 ; GDD §10.7.6, §10.7.8, §10.7.9 ; règles 12 à
-- 15 et 17 du §10.8) :
--  * tout achat, ×1 compris, par un maintien de Balance.Upgrades.HoldSeconds (0,6 s) de Widgets.holdOn
--    sur la carte ou la ligne (InputBegan capté, jamais Activated ; jamais sur un bouton caché, grisé
--    ou remplacé ; garde d'entrée de FocusGuard) ; anneau de 12 points autour du glyphe (carte) ou du
--    dessin de l'état (ligne) ; relâché trop tôt : l'anneau se vide, son Bump, le bandeau dit
--    « Maintiens pour acheter » avec le glyphe de l'appareil ;
--  * maintien permis seulement sur une ligne Prête ou « Réessaie » (le même geste renvoie, D9) ;
--    « Il manque » : refus doux (Bump, vibration refuse, aucune secousse) ; lecture seule, cadenas,
--    MAX, plafond de la boucle : Bump ; « En cours » : appuis ignorés ;
--  * BuyUpgrade(identifiant canonique, mode 1 | 10 | 0, niveau attendu = niveau montré) par
--    Hud/UpgradeBuys (jamais une intention invalide) ; « en cours » 3 s puis « Réessaie » ; réponse
--    tardive appliquée avec un seul retour ; refus périmé muet ; réponse d'un BuyTile ou de l'achat au
--    sol : son instantané seulement ;
--  * un retour par réponse, dans la ligne ou la carte même, 1,5 s : « +n niveaux · -prix » (niveaux et
--    montant du serveur), « n sur m » d'un ×10 en partie, ou la raison du refus du serveur ; son
--    TileBuild et vibration tileBuy (refus : Bump et refuse) ; aucun toast ; la carte garde sa famille,
--    le focus reste sur la ligne achetée (même à MAX), rien ne reste appuyé ;
--  * mode changé par le joueur : ClientMetric("upgradeMode") ; délai dépassé : ClientMetric
--    ("upgradeTimeout", 0) (limiteur unique de Hud/UpgradeBuys, D10) ; mode et achat comptent comme
--    navigation pour MenuActivity (navigateur, D11) ;
--  * début de SON Grand Splorch ou de SA Jelly Ascend (Celebrate, ou EventState.spectacle.current) :
--    l'écran se ferme (PanelController.closeAll) ; la réouverture est neuve (D28).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local Balance = require(Shared.Config.Balance)
local UpgradeAdvisor = require(Shared.Logic.UpgradeAdvisor)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local Formulas = require(Shared.Logic.Formulas)
local QuestRules = require(Shared.Logic.QuestRules)
local BigNumber = require(Shared.Logic.BigNumber)
local Localization = require(Shared.Localization)
local Net = require(Shared.Net)

local Client = script.Parent.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Haptics = require(Client.Util.Haptics)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Widgets = require(script.Parent.Widgets)
local Text = require(Client.UI.Text)
local Format = require(Client.UI.Format)
local Juice = require(Client.UI.Juice)
local Theme = require(Client.UI.Theme)
local FocusGuard = require(Client.UI.FocusGuard)
local UpgradeSnapshot = require(Client.UI.UpgradeSnapshot)
local UpgradeCard = require(Client.UI.UpgradeCard)
local Icons = require(Client.UI.Hud.Icons)
local UpgradeView = require(Client.UI.Hud.UpgradeView)
local UpgradeBuys = require(Client.UI.Hud.UpgradeBuys)
local Friends = require(Client.UI.Hud.Friends)

type Nav = {
	open: (panel: string, tab: string?) -> (),
	back: () -> (),
	closeAll: (() -> ())?,
	activity: (() -> ())?, -- navigation dans le panneau (MenuActivity de PanelController, D11)
}
type Card = UpgradeCard.Card
type View = UpgradeView.View
type Snapshot = Types.UpgradeSnapshot

local Upgrades = {}

local U = Layout.Upgrades
local COL = U.Columns
local W = Layout.Panel.rect.w -- 1 440
local MARGIN = U.Margin -- 32
local INNER = W - 2 * MARGIN -- 1 376
local ROW_X = (INNER - U.Row.w) / 2 -- 24 : marges des lignes dans le cadre de défilement
local ROW_GAP = U.Row.step - U.Row.h -- 16
local SECTION_H = U.Row.h -- un titre de section compte comme un élément de 112 non sélectionnable
local TAB_H = 56 -- boutons d'onglet dans la zone de 64
-- onglet Plopettes avant Pip (GDD §10.7.5 : « un cadenas « Record 2 » ») : cadenas dessiné de 28 et
-- son mot à 28 px (taille minimale d'un texte à lire), après le libellé
local TAB_LOCK = 28
local TAB_WORD = Layout.Text.Min
local CLOSE = 56 -- bouton Fermer (souris ; ○ à la manette)
local COUNT_TIME = 0.4 -- s : compteur de l'en-tête (pièces, Confettis)
local MODE_ACTION = "UpgradesMode"
local FEEDBACK_SECONDS = 1.5 -- retour dans la ligne même (GDD §10.7.8)
local HINT_SECONDS = 2 -- consigne « Maintiens pour acheter » après un relâchement trop tôt
-- anneau du maintien : 12 points sur un cercle de 26 px de rayon autour d'un dessin de 48 ; un point
-- atteint grossit de 6 à 10 px et devient opaque (rien ne déborde sur le mot de l'état, à 8 px du dessin)
local RING_DOTS = 12
local RING_RADIUS = 26
local RING_DOT = 6
local RING_LIT = 10
local RING_DIM = 0.5 -- transparence d'un point pas encore atteint
local HOLD_GLYPH = 40 -- glyphe de l'appareil devant la consigne du bandeau
local SPIN_PERIOD = 1.2 -- s : un tour du sablier « En cours »
local SNACK_MAX = UpgradeMath.maxLevel("snack") -- 12 : le Tapis Étoilé continue la même ligne

Upgrades.TABS = table.freeze({ "suggested", "ranch", "helpers", "workshop" })
Upgrades.LIST_TABS = table.freeze({ "ranch", "helpers", "workshop" })
Upgrades.SPEND_FIRST = "spendFirst"
local TAB_KEYS: { [string]: string } = {
	suggested = "upgrades.tab.suggested",
	ranch = "upgrades.tab.ranch",
	helpers = "upgrades.tab.helpers",
	workshop = "upgrades.tab.workshop",
}
local MODE_KEYS: { [number]: string } = {
	[1] = "upgrades.mode.x1",
	[10] = "upgrades.mode.x10",
	[0] = "upgrades.mode.max",
}
local NEXT_MODE: { [number]: number } = { [1] = 10, [10] = 0, [0] = 1 }

local COLORS = {
	banner = Color3.fromRGB(40, 34, 72),
	pill = Color3.fromRGB(48, 40, 88),
	section = Widgets.Colors.Gold,
	text = Widgets.Colors.Text,
	dim = Widgets.Colors.TextDim,
}

-- =============================================================================================
-- État
-- =============================================================================================

type Counter = {
	label: TextLabel,
	kind: string, -- "coins" | "confetti"
	shown: number?,
	from: number,
	to: number,
	t0: number,
}

local nav: Nav? = nil
local built = false
local opened = false
local root: Frame? = nil
local current = "suggested"
local mode = 1
local frozen: Snapshot? = nil -- instantané de l'ouverture (plafonds, r, Record R, A : figés, D7)
local display: Snapshot? = nil -- figé + pièces, Confettis et niveaux du dernier instantané
local spendTarget: string? = nil -- « Dépenser d'abord » : ligne sélectionnée à l'ouverture

local cards: { Card } = {}
local cardIds: { string } = {}
local rows: { [string]: Card } = {}
local rowTab: { [string]: string } = {}
local rowY: { [string]: number } = {}
local shownRows: { [string]: { string } } = {} -- lignes montrées de chaque onglet (figées à l'ouverture)
local views: { [Instance]: View } = {} -- dernière vue de chaque carte ou ligne (bandeau)
local advised: { [string]: boolean } = {}
local stars: { Frame } = {}
local scrolls: { [string]: ScrollingFrame } = {}
local suggestedFrame: Frame? = nil
local sectionLabel: TextLabel? = nil
local tabButtons: { [string]: TextButton } = {}
local tabLock: Frame? = nil
local tabLockWord: TextLabel? = nil
local tabWidths: { [string]: number } = {} -- largeur de chaque onglet sans cadenas
local tabLockRoom = 0 -- place du cadenas et de son mot dans l'onglet Plopettes
local tabsLocked: boolean? = nil -- disposition courante de la rangée (cadenas montré ou non)
local lockOnAccent: boolean? = nil -- cadenas recoloré pour le fond de l'onglet actif
local r1Glyph: any = nil
local modeButton: TextButton? = nil
local modeLabel: TextLabel? = nil
local memoryPill: Frame? = nil
local memoryLabel: TextLabel? = nil
local bannerLabel: TextLabel? = nil
local counters: { [string]: Counter } = {}
local counterConn: RBXScriptConnection? = nil
local actionBound = false
local lastPayableAt: number? = nil -- D29 : dernier instantané où une famille de pièces était payable
local firstSeenAt: number? = nil

-- achats (étape 3)
local buys: UpgradeBuys.Buys? = nil
local cardOf: { [Instance]: Card } = {} -- racine → composant (cartes et lignes)
local holdOf: { [Instance]: Widgets.Hold } = {} -- maintien de 0,6 s de chaque carte et ligne à acheter
local holdable: { [Instance]: boolean } = {}
local origins: { [string]: Instance } = {} -- identifiant canonique → élément dont le maintien a acheté
local feedbackUntil: { [Instance]: number } = {}
local feedbackLog: { { id: string, key: string } } = {} -- retours montrés (specs ; 64 derniers)
local hintObj: Instance? = nil -- consigne du maintien (relâché trop tôt) sur cet élément…
local hintUntil = 0 -- … jusqu'à cette heure
local ring: Frame? = nil
local ringDots: { Frame } = {}
local ringOwner: Instance? = nil
local bannerGlyph: Frame? = nil
local loopConn: RBXScriptConnection? = nil
local showKind: string? = nil -- D28 : dernier spectacle de prestige du joueur déjà vu (sorte, début)
local showStart: number? = nil

-- =============================================================================================
-- Outils
-- =============================================================================================

local function lang(): string
	local ok, l = pcall(Prefs.language)
	return if ok and type(l) == "string" then l else "en"
end

-- Modèle de MON ranch (Ranches/<k>, répliqué) : attributs v2.0 posés par le serveur (HelperMode,
-- AscendReady) ; nil sans monde construit
local function myRanch(): Instance?
	local ok, slot = pcall(WorldStateController.mySlot)
	if not ok or type(slot) ~= "number" or slot <= 0 then
		return nil
	end
	local world = workspace:FindFirstChild("Wobbleton")
	local list = world and world:FindFirstChild("Ranches")
	return list and list:FindFirstChild(Format.id(slot))
end

local function ranchAttribute(name: string): any
	local model = myRanch()
	if model == nil then
		return nil
	end
	local ok, value = pcall(function()
		return model:GetAttribute(name)
	end)
	return if ok then value else nil
end

-- Contexte des vues (D30, D31, note A3) : mêmes valeurs que le revenu du HUD (amis présents compris :
-- liste de Hud/Friends ; relecture du lot B2, B2-67)
local function viewCtx(): UpgradeView.Ctx
	local tiles = Widgets.tbl(Widgets.state("tiles"))
	local passes = Widgets.tbl(Widgets.state("passes"))
	local dex = Widgets.tbl(Widgets.state("dex"))
	local aBonus = Widgets.safe("Formulas.A", 1, Formulas.A, {
		decor = Widgets.n(tiles.decor),
		friends = Widgets.safe("Friends.count", 0, Friends.count),
		fame = Widgets.n(Widgets.state("fame")),
		trophyBonus = Widgets.safe(
			"Formulas.trophyBonus",
			0,
			Formulas.trophyBonus,
			Widgets.tbl(Widgets.state("trophies"))
		),
		goldenPages = Widgets.safe("QuestRules.goldenPages", 0, QuestRules.goldenPages, dex),
		doubleCoins = passes.DoubleCoins == true,
		boost = false,
	})
	local helperMode = ranchAttribute("HelperMode")
	local regain = Widgets.state("regainBonusA")
	local memoryR = Widgets.state("memoryR")
	return {
		lang = lang(),
		aBonus = aBonus,
		bigRanch = passes.BigRanch == true,
		spikyFamily = Widgets.safe("QuestRules.familyEarned", false, QuestRules.familyEarned, dex, "spiky")
			== true,
		helperMode = if type(helperMode) == "string" then helperMode else nil,
		advised = advised,
		regainBonusA = if type(regain) == "number" then regain else nil,
		memoryR = if type(memoryR) == "number" then memoryR else nil,
	}
end

-- Instantané montré : structure figée à l'ouverture (plafonds, r, Record R, A ; D7) + pièces,
-- Confettis et niveaux du dernier instantané accepté. Le Tapis Étoilé n'a de plafond qu'APRÈS le
-- Tapis 12 (UpgradeMath.cap) : ouvert avant, l'écran n'a figé ni son interrupteur ni son plafond de
-- boucle, seulement « pas encore » ; le Tapis 12 acheté écran ouvert, la même ligne continue avec le
-- plafond de l'Étoilé du serveur (même boucle, r figé = r du serveur). Sans cela, l'Étoilé passait
-- pour coupé par son interrupteur : « 12/12 », MAX, jusqu'à la réouverture (relecture du lot B2, B2-65)
local function merge(live: Snapshot, base: Snapshot): Snapshot
	local caps = base.caps
	local baseSnack = base.levels.snack or 0
	if baseSnack < SNACK_MAX and (live.levels.snack or 0) >= SNACK_MAX and live.r == base.r then
		local withStar = table.clone(caps)
		withStar.star = live.caps.star
		caps = table.freeze(withStar)
	end
	return table.freeze({
		coins = live.coins,
		confetti = live.confetti,
		levels = live.levels,
		caps = caps,
		r = base.r,
		bestR = base.bestR,
		ascend = base.ascend,
		version = live.version,
	}) :: any
end

-- Secondes sans famille de pièces payable dans les instantanés montrés (D29)
local function unpayableSeconds(): number
	local now = Clock.now()
	local since = lastPayableAt or firstSeenAt
	if since == nil or now < since then
		return 0
	end
	return now - since
end

local function noteSnapshot(snap: Snapshot)
	local now = Clock.now()
	firstSeenAt = firstSeenAt or now
	if UpgradeView.anyPayable(snap) then
		lastPayableAt = now
	end
end

-- =============================================================================================
-- Compteurs de l'en-tête (règles 3 et 4)
-- =============================================================================================

local function counterText(c: Counter, value: number): string
	if c.kind == "confetti" then
		return Format.confetti(value, lang())
	end
	return BigNumber.abbreviate(value, lang())
end

local function stepCounters()
	local now = Clock.now()
	local busy = false
	for _, c in counters do
		local shown = c.shown
		if shown ~= nil and shown ~= c.to then
			local k = (now - c.t0) / COUNT_TIME
			local value = c.to
			if k >= 0 and k < 1 then
				local eased = 1 - (1 - k) * (1 - k)
				value = c.from + (c.to - c.from) * eased
				busy = true
			end
			c.shown = value
			Text.raw(c.label, counterText(c, value))
		end
	end
	if not busy and counterConn then
		counterConn:Disconnect()
		counterConn = nil
	end
end

-- Pose la valeur d'un compteur : tout de suite (première fois, écran fermé, mouvement réduit), sinon
-- en 0,4 s depuis la valeur montrée (jamais depuis 0) ; la valeur finale est toujours écrite
local function setCounter(name: string, value: number, animate: boolean)
	local c = counters[name]
	if c == nil then
		return
	end
	if c.shown == nil or not animate or not opened or Juice.reducedMotion() then
		c.shown, c.from, c.to = value, value, value
		Text.raw(c.label, counterText(c, value))
		return
	end
	if value == c.to then
		return
	end
	c.from = c.shown :: number
	c.to = value
	c.t0 = Clock.now()
	if counterConn == nil then
		counterConn = RunService.Heartbeat:Connect(stepCounters)
	end
end

-- Fin de tous les compteurs : valeur finale exacte (fermeture, changement de langue)
local function settleCounters()
	for _, c in counters do
		c.shown, c.from = c.to, c.to
		Text.raw(c.label, counterText(c, c.to))
	end
	if counterConn then
		counterConn:Disconnect()
		counterConn = nil
	end
end

-- =============================================================================================
-- Construction (une seule fois)
-- =============================================================================================

local function label(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	size: number,
	align: Enum.TextXAlignment,
	color: Color3?
): TextLabel
	return Widgets.label({
		parent = parent,
		name = name,
		size = UDim2.fromOffset(w, h),
		position = UDim2.fromOffset(x, y),
		textSize = size,
		xAlign = align,
		color = color,
		zIndex = 4,
	})
end

-- Dessins tirés de Config/Upgrades pour une ligne (icône, coins, monnaie, états atteignables)
local function rowOptions(id: string, view: View): UpgradeCard.Options
	local icons = { view.icon }
	if id == "snack" then
		table.insert(icons, "starMat")
	end
	local badges: { string } = {}
	if view.kind == "family" then
		table.insert(badges, if view.kept then "kept" else "loop")
	end
	local states: { string } = { "check", "hourglass", "star", "lock", "retry" }
	if id == "snack" then
		table.insert(states, "loop")
	end
	if view.readOnly then
		states = if view.kind == "helper" then { "lock" } else {}
	end
	return {
		icons = icons,
		badges = badges,
		currencies = if view.currency == "confetti" then { "confetti" } else { "coin" },
		readOnly = view.readOnly,
		effect = view.kind ~= "fun" and not (view.kind == "workshop" and view.effect == nil),
		states = states,
	}
end

local function buildHeader(body: Frame)
	local H = U.Header
	local title =
		label(body, "Title", MARGIN, H.y, U.Memory.x - 16 - MARGIN, H.h, H.title, Enum.TextXAlignment.Left)
	Widgets.setText(title, "upgrades.title")
	-- pastille Souvenir (D31) : place fixe x 320-680, jamais sélectionnable, réservée même cachée
	local M = U.Memory
	local pill = Widgets.frame({
		parent = body,
		name = "Memory",
		size = UDim2.fromOffset(M.w, M.h),
		position = UDim2.fromOffset(M.x, H.y + (H.h - M.h) / 2),
		color = COLORS.pill,
		corner = UDim.new(0.5, 0),
		stroke = false,
		zIndex = 3,
	})
	pill.Visible = false
	local drop = Icons.canvas(pill, M.icon, { "drop" }, "Drop")
	drop.Position = UDim2.fromOffset(16, (M.h - M.icon) / 2)
	drop.ZIndex = 4
	Icons.draw(drop, "drop")
	memoryLabel = label(
		pill,
		"Label",
		16 + M.icon + 8,
		0,
		M.w - (16 + M.icon + 8) - 16,
		M.h,
		M.text,
		Enum.TextXAlignment.Left
	)
	memoryPill = pill
	-- groupe de droite : pièces 280, Confettis 200, bouton de mode 200 (écarts de 16)
	local right = W - MARGIN
	local modeX = right - U.Mode.w
	local confettiX = modeX - U.HeaderGap - U.Confetti.w
	local coinsX = confettiX - U.HeaderGap - U.Coins.w
	local function amount(name: string, x: number, w: number, kind: string)
		local spec = if kind == "coin" then U.Coins else U.Confetti
		local icon = Icons.canvas(body, spec.icon, { kind }, name .. "Icon")
		icon.Position = UDim2.fromOffset(x, H.y + (H.h - spec.icon) / 2)
		icon.ZIndex = 4
		Icons.draw(icon, kind)
		local l = label(
			body,
			name,
			x + spec.icon + 8,
			H.y + 16,
			w - spec.icon - 8,
			H.h - 32,
			spec.text,
			Enum.TextXAlignment.Left
		)
		counters[if kind == "coin" then "coins" else "confetti"] = {
			label = l,
			kind = if kind == "coin" then "coins" else "confetti",
			shown = nil,
			from = 0,
			to = 0,
			t0 = 0,
		}
	end
	amount("Coins", coinsX, U.Coins.w, "coin")
	amount("Confetti", confettiX, U.Confetti.w, "confetti")
	-- bouton de mode : glyphe □ dessiné (E au clavier) + « ×1 » / « ×10 » / « Max », sélectionnable
	local b = Widgets.button({
		parent = body,
		name = "Mode",
		size = UDim2.fromOffset(U.Mode.w, 72),
		position = UDim2.fromOffset(modeX, H.y + (H.h - 72) / 2),
		color = Widgets.Colors.CardLight,
		zIndex = 4,
		onActivate = function()
			Upgrades._playerMode()
		end,
	})
	Widgets.glyph(
		b,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.E,
		U.Mode.glyph,
		UDim2.new(0, 12, 0.5, 0),
		Vector2.new(0, 0.5)
	)
	modeLabel = label(
		b,
		"Label",
		12 + U.Mode.glyph + 8,
		8,
		U.Mode.w - (12 + U.Mode.glyph + 8) - 12,
		56,
		U.Mode.text,
		Enum.TextXAlignment.Center
	)
	modeLabel.ZIndex = b.ZIndex + 1
	modeButton = b
end

local function buildTabs(body: Frame)
	local T = U.Tabs
	local y = T.y + (T.h - TAB_H) / 2
	local glyph = Layout.Glyph.Min
	local gy = T.y + (T.h - glyph) / 2
	Widgets.glyph(body, Enum.KeyCode.ButtonL1, nil, glyph, UDim2.fromOffset(MARGIN, gy), Vector2.zero)
	-- mot du cadenas : sa plus longue forme (anglais, français), avec 10 % de marge sur l'estimation
	local recordR = Balance.Helpers.ByRecordR[1] or 0
	local wordEm = 0
	for _, l in { "en", "fr" } do
		local word = Localization.get(l :: any, "upgrades.state.locked", { r = Format.count(recordR) })
		wordEm = math.max(wordEm, Widgets.textEm(word))
	end
	local wordW = math.ceil(wordEm * TAB_WORD * 1.1) + 4
	-- libellé, 8, cadenas, 8, mot, 16 (le libellé garde ses 12 px de marge à droite)
	tabLockRoom = 8 + TAB_LOCK + 8 + wordW + 4
	local x = MARGIN + glyph + 16
	for i, id in Upgrades.TABS do
		local width = math.max(160, math.floor(Widgets.keyEm(TAB_KEYS[id]) * T.text + 48))
		tabWidths[id] = width
		local b = Widgets.button({
			parent = body,
			name = "Tab_" .. id,
			size = UDim2.fromOffset(width, TAB_H),
			position = UDim2.fromOffset(x, y),
			key = TAB_KEYS[id],
			textSize = T.text,
			color = Widgets.Colors.Card,
			order = i,
			tab = true,
			sound = "Tab",
			zIndex = 4,
			onActivate = function()
				Upgrades.setTab(id)
				FocusGuard.refocus()
			end,
		})
		if id == "helpers" then
			-- cadenas dessiné ET mot « Record 2 » (un état = un dessin et un mot, §10.7.6), montrés
			-- avant Pip seulement ; la rangée s'élargit alors (layoutTabs, décidé à l'ouverture)
			local word = Widgets.label({
				parent = b,
				name = "LockWord",
				key = "upgrades.state.locked",
				vars = { r = recordR },
				textSize = TAB_WORD,
				xAlign = Enum.TextXAlignment.Left,
				size = UDim2.fromOffset(wordW, 40),
				position = UDim2.new(1, -16, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				zIndex = b.ZIndex + 2,
			})
			word.Visible = false
			tabLockWord = word
			local lock = Icons.canvas(b, TAB_LOCK, { "lock" }, "Lock")
			lock.AnchorPoint = Vector2.new(1, 0.5)
			lock.Position = UDim2.new(1, -(16 + wordW + 8), 0.5, 0)
			lock.ZIndex = b.ZIndex + 2
			Icons.draw(lock, "lock")
			lock.Visible = false
			tabLock = lock
		end
		local underline = Instance.new("Frame")
		underline.Name = "Underline"
		underline.BackgroundColor3 = Widgets.Colors.Accent
		underline.BorderSizePixel = 0
		underline.AnchorPoint = Vector2.new(0.5, 1)
		underline.Position = UDim2.new(0.5, 0, 1, -4)
		underline.Size = UDim2.new(0, 0, 0, 6)
		underline.ZIndex = b.ZIndex + 2
		Widgets.corner(underline, UDim.new(0.5, 0))
		underline.Parent = b
		tabButtons[id] = b
		x += width + Layout.Spacing.Min
	end
	r1Glyph = Widgets.glyph(body, Enum.KeyCode.ButtonR1, nil, glyph, UDim2.fromOffset(x, gy), Vector2.zero)
	-- au bout de la rangée (D5) : L2 / R2 (panneaux en boucle) et le bouton Fermer de la souris (○)
	local closeX = W - MARGIN - CLOSE
	local close = Widgets.button({
		parent = body,
		name = "Close",
		size = UDim2.fromOffset(CLOSE, CLOSE),
		position = UDim2.fromOffset(closeX, T.y + (T.h - CLOSE) / 2),
		color = Widgets.Colors.Card,
		selectable = false, -- ○ suffit à la manette ; le bouton sert à la souris
		sound = "",
		zIndex = 4,
		onActivate = function()
			FocusGuard.back()
		end,
	})
	Widgets.glyph(
		close,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Backspace,
		40,
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	local r2X = closeX - 16 - glyph
	Widgets.glyph(body, Enum.KeyCode.ButtonR2, nil, glyph, UDim2.fromOffset(r2X, gy), Vector2.zero)
	Widgets.glyph(
		body,
		Enum.KeyCode.ButtonL2,
		nil,
		glyph,
		UDim2.fromOffset(r2X - 8 - glyph, gy),
		Vector2.zero
	)
end

local function contentFrame(body: Frame, name: string): Frame
	local f =
		Widgets.group(body, name, UDim2.fromOffset(INNER, U.Content.h), UDim2.fromOffset(MARGIN, U.Content.y))
	f.ZIndex = 2
	return f
end

local function buildCards(body: Frame)
	local frame = contentFrame(body, "Suggested")
	local opts: UpgradeCard.Options = {
		icons = table.clone(UpgradeCard.COIN_ICONS),
		badges = {},
		currencies = { "coin" },
	}
	table.insert(opts.icons :: { string }, "star")
	for i = 1, UpgradeAdvisor.Cards do
		local card = UpgradeCard.new("card", frame, opts)
		card.root.Name = "Card" .. i
		card.root.Position = UDim2.fromOffset((i - 1) * (U.Card.w + U.Card.gap), (U.Content.h - U.Card.h) / 2)
		card.root.Activated:Connect(function()
			Upgrades._activate(card.root)
		end)
		cards[i] = card
		cardOf[card.root] = card
		cardIds[i] = UpgradeAdvisor.NEUTRAL
	end
	suggestedFrame = frame
end

local function buildList(body: Frame, tab: string, snap: Snapshot)
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "List_" .. tab
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Position = UDim2.fromOffset(MARGIN, U.Content.y)
	sf.Size = UDim2.fromOffset(INNER, U.Content.h)
	sf.CanvasSize = UDim2.fromOffset(0, 0)
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.ScrollBarThickness = 8
	sf.ScrollBarImageColor3 = Widgets.Colors.TextDim
	sf.ElasticBehavior = Enum.ElasticBehavior.Never
	sf.Selectable = false
	sf.ZIndex = 2
	-- rangée entrouverte voulue (48 px de la 5e en bas, ou de la ligne d'au-dessus une fois la liste
	-- défilée : elle annonce la suite, GDD §10.6 règle 7, §10.7.5) : même marque que les listes de
	-- Widgets, l'outil d'écrans la classe « peek » au lieu d'un texte coupé (lot B2, étape 5)
	sf:SetAttribute("PeekRows", true)
	sf.Visible = false
	sf.Parent = body
	scrolls[tab] = sf
	local ctx = viewCtx()
	for _, id in UpgradeView.lines(tab) do
		local section = UpgradeView.sectionBefore(id)
		if section ~= nil and sectionLabel == nil then
			local l = Widgets.label({
				parent = sf,
				name = "Section",
				size = UDim2.fromOffset(U.Row.w - 32, SECTION_H),
				position = UDim2.fromOffset(ROW_X + 16, 0),
				key = section,
				textSize = U.Card.title,
				color = COLORS.section,
				xAlign = Enum.TextXAlignment.Left,
				zIndex = 3,
			})
			sectionLabel = l
		end
		local view = UpgradeView.view(id, snap, 1, ctx)
		local row = UpgradeCard.new("row", sf, rowOptions(id, view))
		row.root.Name = "Row_" .. id
		row.root.Activated:Connect(function()
			Upgrades._activate(row.root)
		end)
		row.root:SetAttribute("ReadOnly", view.readOnly)
		rows[id] = row
		rowTab[id] = tab
		cardOf[row.root] = row
	end
	if tab == "workshop" then
		-- coin « Conseillé » de l'Atelier : 3 étoiles dessinées posées à l'ouverture de l'onglet sur les
		-- lignes choisies (jamais une étoile par ligne : budget, règle 20)
		for i = 1, 3 do
			local star = Icons.canvas(sf, 32, { "star" }, "Advised" .. i)
			star.ZIndex = 9
			star.Visible = false
			Icons.draw(star, "star")
			stars[i] = star
		end
	end
end

local function buildBanner(body: Frame)
	local D = U.Detail
	local frame = Widgets.frame({
		parent = body,
		name = "Detail",
		size = UDim2.fromOffset(INNER, D.h),
		position = UDim2.fromOffset(MARGIN, D.y),
		color = COLORS.banner,
		stroke = false,
		zIndex = 3,
	})
	local l = Instance.new("TextLabel")
	l.Name = "Sentence"
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Position = UDim2.fromOffset(24, 12)
	l.Size = UDim2.fromOffset(INNER - 48, D.h - 24)
	l.FontFace = Theme.Fonts.Title
	l.TextColor3 = COLORS.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.AutoLocalize = false
	l.ZIndex = 4
	Text.style(l, "sentence", D.text, { min = D.text, wrapped = true })
	Text.raw(l, "—")
	l.Parent = frame
	bannerLabel = l
	-- glyphe de l'appareil devant la consigne « Maintiens pour acheter » (GDD §10.7.8) : caché sinon
	local g = Instance.new("Frame")
	g.Name = "HoldGlyph"
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	g.Size = UDim2.fromOffset(HOLD_GLYPH, HOLD_GLYPH)
	g.Position = UDim2.fromOffset(24, (D.h - HOLD_GLYPH) / 2)
	g.ZIndex = 4
	g.Visible = false
	g.Parent = frame
	Widgets.glyph(
		g,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.Return,
		HOLD_GLYPH,
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	bannerGlyph = g
end

-- Anneau du maintien de 0,6 s (un seul pour l'écran : un seul maintien à la fois) : 12 points posés
-- dans la carte ou la ligne maintenue, allumés au fil du maintien ; aucune instance créée ensuite
local function buildRing(body: Frame)
	local size = 2 * (RING_RADIUS + RING_LIT / 2)
	local f = Instance.new("Frame")
	f.Name = "HoldRing"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.ZIndex = 9
	f.Active = false
	f.Selectable = false
	f.Visible = false
	for i = 1, RING_DOTS do
		local a = (i - 1) * 2 * math.pi / RING_DOTS
		local d = Instance.new("Frame")
		d.Name = "Dot" .. i
		d.BorderSizePixel = 0
		d.BackgroundColor3 = COLORS.text
		d.BackgroundTransparency = RING_DIM
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(RING_DOT, RING_DOT)
		d.Position = UDim2.new(
			0.5,
			math.floor(math.sin(a) * RING_RADIUS + 0.5),
			0.5,
			-math.floor(math.cos(a) * RING_RADIUS + 0.5)
		)
		d.ZIndex = 9
		d.Active = false
		d.Selectable = false
		Widgets.corner(d, UDim.new(0.5, 0))
		d.Parent = f
		ringDots[i] = d
	end
	f.Parent = body
	ring = f
end

-- =============================================================================================
-- Rendu
-- =============================================================================================

local function setBanner(t: UpgradeView.Text?)
	local l = bannerLabel
	if l == nil then
		return
	end
	-- consigne du maintien : glyphe de l'appareil devant la phrase (la phrase se pousse à droite)
	local glyph = t ~= nil and t.key == UpgradeView.HOLD.key
	local g = bannerGlyph
	if g ~= nil and g.Visible ~= glyph then
		g.Visible = glyph
		local x = if glyph then 24 + HOLD_GLYPH + 12 else 24
		l.Position = UDim2.fromOffset(x, 12)
		l.Size = UDim2.fromOffset(INNER - x - 24, U.Detail.h - 24)
	end
	if t == nil then
		Text.raw(l, "—")
	else
		Text.set(l, t.key, t.vars)
	end
end

-- Phrase du bandeau pour l'objet sélectionné : la consigne du maintien juste après un relâchement trop
-- tôt, sinon celle de son état et du mode, sinon ce que devient la ligne au Grand Splorch ; « — » pour
-- un onglet ou le bouton de mode
local function bannerFor(obj: Instance?)
	if hintObj ~= nil and (obj == hintObj or obj == nil) and Clock.now() < hintUntil then
		setBanner(UpgradeView.HOLD)
		return
	end
	local view = if obj then views[obj] else nil
	if view == nil then
		setBanner(nil)
		return
	end
	setBanner(view.banner or view.fate)
end

local function renderHeader(snap: Snapshot, animate: boolean)
	setCounter("coins", snap.coins, animate)
	setCounter("confetti", snap.confetti, animate)
	local memory = UpgradeView.memory(snap, viewCtx())
	local pill, ml = memoryPill, memoryLabel
	if pill and ml then
		pill.Visible = memory.active
		if memory.active then
			Widgets.setText(ml, "hud.memory", { f = memory.f })
		end
	end
	local l = modeLabel
	if l then
		Widgets.setText(l, MODE_KEYS[mode] or MODE_KEYS[1])
	end
end

-- Vue d'une ligne ou d'une carte de famille avec son achat en cours (« En cours » / « Réessaie » de
-- l'identifiant canonique qu'elle enverrait)
local function viewOf(id: string, snap: Snapshot, ctx: UpgradeView.Ctx): View
	local view = UpgradeView.view(id, snap, mode, ctx)
	local b = buys
	local sendId = view.sendId
	if b ~= nil and sendId ~= nil then
		local pending = b:state(sendId)
		if pending ~= nil then
			view = UpgradeView.view(id, snap, mode, ctx, pending)
		end
	end
	return view
end

-- Maintien permis seulement sur une ligne Prête ou « Réessaie » ; ailleurs l'appui suit _activate
-- (refus doux, Bump, ou rien). Widgets : setEnabled(false) grise aussi le bouton ; une ligne « Il
-- manque », MAX ou « En cours » garde son aspect, seul le maintien est coupé
local function setHoldable(root: Instance, on: boolean)
	local hold = holdOf[root]
	if hold == nil or holdable[root] == on then
		return
	end
	holdable[root] = on
	hold.setEnabled(on)
	if not on then
		Widgets.setDisabled(root :: any, false)
	end
end

local function renderRow(id: string, snap: Snapshot, ctx: UpgradeView.Ctx)
	local row = rows[id]
	if row == nil then
		return
	end
	local view = viewOf(id, snap, ctx)
	views[row.root] = view
	row:set(view.state, view)
	setHoldable(row.root, not view.readOnly and (view.state == "ready" or view.state == "retry"))
end

local function renderCards(snap: Snapshot, ctx: UpgradeView.Ctx)
	for i, card in cards do
		local id = cardIds[i]
		local note = id == UpgradeAdvisor.NEUTRAL or id == UpgradeAdvisor.ASCEND
		local view = if note then UpgradeView.note(id, mode) else viewOf(id, snap, ctx)
		views[card.root] = view
		card:set(view.state, view)
		setHoldable(card.root, not note and (view.state == "ready" or view.state == "retry"))
	end
end

-- Lignes « Conseillé » de l'Atelier (≤ 3, choisies à l'ouverture de l'onglet) : étoiles posées
local function placeStars()
	local list: { string } = {}
	for id in advised do
		if rowTab[id] == "workshop" and rowY[id] ~= nil then
			table.insert(list, id)
		end
	end
	table.sort(list, function(a: string, b: string): boolean
		return (rowY[a] or 0) < (rowY[b] or 0)
	end)
	for i, star in stars do
		local id = list[i]
		star.Visible = id ~= nil
		if id ~= nil then
			star.Position = UDim2.fromOffset(ROW_X + COL.icon.x + COL.icon.w - 24, (rowY[id] :: number) + 8)
		end
	end
end

local function chooseAdvised(snap: Snapshot)
	table.clear(advised)
	for _, id in UpgradeView.advised(snap) do
		advised[id] = true
	end
	placeStars()
end

local function chooseCards(snap: Snapshot)
	local readyAttr = ranchAttribute("AscendReady")
	local list = UpgradeAdvisor.cards(snap, UpgradeView.advisorCtx(readyAttr == true, unpayableSeconds()))
	for i = 1, UpgradeAdvisor.Cards do
		cardIds[i] = list[i] or UpgradeAdvisor.NEUTRAL
	end
end

-- Graphe de la croix : onglets ↔ bouton de mode, onglets ↔ contenu, lignes ↑ ↓ (bouts : rebond)
local function linkNavigation()
	local mb = modeButton
	local active = tabButtons[current]
	if mb == nil or active == nil then
		return
	end
	mb.NextSelectionDown = active
	mb.NextSelectionUp = mb
	mb.NextSelectionRight = mb
	mb.NextSelectionLeft = mb
	local first: GuiObject? = nil
	if current == "suggested" then
		first = if cards[1] then cards[1].root else nil
		for i, card in cards do
			local r = card.root
			r.NextSelectionUp = active
			r.NextSelectionDown = r
			r.NextSelectionLeft = if i > 1 then cards[i - 1].root else r
			r.NextSelectionRight = if i < #cards then cards[i + 1].root else r
		end
	else
		local list = shownRows[current] or {}
		for i, id in list do
			local r = rows[id].root
			if i == 1 then
				first = r
			end
			r.NextSelectionUp = if i > 1 then rows[list[i - 1]].root else active
			r.NextSelectionDown = if i < #list then rows[list[i + 1]].root else r
			r.NextSelectionLeft = r
			r.NextSelectionRight = r
		end
	end
	for i, id in Upgrades.TABS do
		local b = tabButtons[id]
		b.NextSelectionUp = mb
		b.NextSelectionDown = first or b
		b.NextSelectionLeft = if i > 1 then tabButtons[Upgrades.TABS[i - 1]] else b
		b.NextSelectionRight = if i < #Upgrades.TABS then tabButtons[Upgrades.TABS[i + 1]] else b
	end
end

-- Lignes montrées d'un onglet, positions, hauteur de défilement (fonction pure : somme des hauteurs
-- + (n − 1) × 16, un titre de section comptant pour 112) ; à l'ouverture seulement (D8)
local function layoutList(tab: string, snap: Snapshot, ctx: UpgradeView.Ctx)
	local sf = scrolls[tab]
	if sf == nil then
		return
	end
	local list: { string } = {}
	local heights: { number } = {}
	local y = 0
	for _, id in UpgradeView.lines(tab) do
		local row = rows[id]
		local view = UpgradeView.view(id, snap, mode, ctx)
		local section = UpgradeView.sectionBefore(id)
		if section ~= nil and sectionLabel ~= nil then
			if #heights > 0 then
				y += ROW_GAP
			end
			sectionLabel.Position = UDim2.fromOffset(ROW_X + 16, y)
			table.insert(heights, SECTION_H)
			y += SECTION_H
		end
		row.root.Visible = not view.hidden
		if view.hidden then
			rowY[id] = nil
		else
			if #heights > 0 then
				y += ROW_GAP
			end
			row.root.Position = UDim2.fromOffset(ROW_X, y)
			rowY[id] = y
			table.insert(heights, U.Row.h)
			y += U.Row.h
			table.insert(list, id)
		end
	end
	shownRows[tab] = list
	sf.CanvasSize = UDim2.fromOffset(0, Upgrades.canvasHeight(heights))
end

-- Hauteur de défilement d'une liste (règle du GDD §10.7.5, fonction pure)
function Upgrades.canvasHeight(heights: { number }): number
	local total = 0
	for _, h in heights do
		total += h
	end
	if #heights > 1 then
		total += (#heights - 1) * ROW_GAP
	end
	return total
end

local function renderTab(tab: string, snap: Snapshot)
	local ctx = viewCtx()
	if tab == "suggested" then
		renderCards(snap, ctx)
	else
		for _, id in UpgradeView.lines(tab) do
			renderRow(id, snap, ctx)
		end
	end
end

-- Rangée des onglets : largeurs et positions (aucune instance créée). L'onglet Plopettes s'élargit
-- de la place de son cadenas et de son mot tant que Pip n'est pas là ; L1 reste à gauche, R1 suit
-- le dernier onglet, L2 / R2 et Fermer restent au bout droit (D5)
local function layoutTabs(locked: boolean)
	if tabsLocked == locked then
		return
	end
	tabsLocked = locked
	local T = U.Tabs
	local glyph = Layout.Glyph.Min
	local x = MARGIN + glyph + 16
	for _, id in Upgrades.TABS do
		local b = tabButtons[id]
		if b == nil then
			continue
		end
		local room = if id == "helpers" and locked then tabLockRoom else 0
		local width = (tabWidths[id] or 160) + room
		b.Size = UDim2.fromOffset(width, TAB_H)
		b.Position = UDim2.fromOffset(x, T.y + (T.h - TAB_H) / 2)
		local text = Widgets.buttonLabel(b)
		if text then
			text.Size = UDim2.new(1, -(24 + room), 1, -12)
			text.Position = UDim2.new(0.5, -room / 2, 0.5, 0)
		end
		x += width + Layout.Spacing.Min
	end
	if r1Glyph and r1Glyph.frame then
		r1Glyph.frame.Position = UDim2.fromOffset(x, T.y + (T.h - glyph) / 2)
	end
	if tabLock then
		tabLock.Visible = locked
	end
	if tabLockWord then
		tabLockWord.Visible = locked
	end
end

local function showTab(tab: string)
	if suggestedFrame then
		suggestedFrame.Visible = tab == "suggested"
	end
	for id, sf in scrolls do
		sf.Visible = id == tab
	end
	for id, b in tabButtons do
		local active = id == tab
		b.BackgroundColor3 = if active then Widgets.Colors.Accent else Widgets.Colors.Card
		b:SetAttribute("Active", active)
		local underline = b:FindFirstChild("Underline")
		if underline and underline:IsA("Frame") then
			underline.Size = if active then UDim2.new(0.7, 0, 0, 6) else UDim2.new(0, 0, 0, 6)
		end
	end
	local lock = tabLock
	local snap = display
	if lock and snap then
		-- Plopettes avant Pip (Record R 2) : cadenas ET mot « Record 2 » sur l'onglet (GDD §10.7.5),
		-- Record R figé à l'ouverture (D7) : la rangée ne change de disposition qu'à l'ouverture
		layoutTabs(snap.bestR < (Balance.Helpers.ByRecordR[1] or 0))
		-- sur le fond clair de l'onglet actif, le cadenas lavande disparaît (contraste 1,2) : bleu nuit
		local onAccent = tab == "helpers"
		if lockOnAccent ~= onAccent then
			lockOnAccent = onAccent
			Icons.draw(lock, "lock", if onAccent then Widgets.Colors.Stroke else nil)
		end
	end
end

-- Ligne sélectionnée gardée visible avec une ligne de marge (GDD §10.6, §10.7.5)
local function keepVisible(obj: GuiObject)
	local view = views[obj]
	if view == nil then
		return
	end
	local id = view.id
	local tab = rowTab[id]
	local y = rowY[id]
	local sf = if tab then scrolls[tab] else nil
	if sf == nil or y == nil or tab ~= current then
		return
	end
	local scale = if sf.Size.Y.Offset > 0 and sf.AbsoluteSize.Y > 0
		then sf.AbsoluteSize.Y / sf.Size.Y.Offset
		else 1
	local viewH = U.Content.h
	local top = sf.CanvasPosition.Y / scale
	local maxTop = math.max(0, sf.CanvasSize.Y.Offset - viewH)
	local goal = top
	if y - U.Row.step < top then
		goal = math.max(0, y - U.Row.step)
	elseif y + U.Row.h + U.Row.step > top + viewH then
		goal = math.min(maxTop, y + U.Row.h + U.Row.step - viewH)
	end
	goal = math.clamp(goal, 0, maxTop)
	if math.abs(goal - top) > 0.5 then
		sf.CanvasPosition = Vector2.new(0, goal * scale)
	end
end

-- Tout l'écran depuis l'instantané montré
local function renderAll(animate: boolean)
	local snap = display
	if snap == nil then
		return
	end
	renderHeader(snap, animate)
	renderTab(current, snap)
	showTab(current)
	bannerFor(GuiService.SelectedObject)
end

-- Instantané accepté (UI/UpgradeSnapshot.Changed)
local function onSnapshot(snap: Snapshot)
	noteSnapshot(snap)
	if not opened then
		return
	end
	local base = frozen
	if base == nil then
		return
	end
	-- prestige appliqué écran ouvert (rouvert pendant SON spectacle, avant l'éclatement ; D28 ne ferme
	-- qu'au début) : r, Record R ou A changent et la boucle repart de zéro. Mêler r, A et plafonds figés
	-- de l'ancienne boucle aux niveaux de la nouvelle montrait les prix de l'ancienne boucle : l'écran se
	-- ferme, la réouverture est neuve (relecture du lot B2, B2-66)
	if snap.r ~= base.r or snap.bestR ~= base.bestR or snap.ascend ~= base.ascend then
		local n = nav
		if n ~= nil and n.closeAll ~= nil then
			n.closeAll()
			return
		end
	end
	display = merge(snap, base)
	renderAll(true)
end

-- =============================================================================================
-- Achats (étape 3) : maintien de 0,6 s, « En cours » / « Réessaie », retours, prestige
-- =============================================================================================

-- Navigation dans le panneau (mode, achat) : MenuActivity de PanelController (D11)
local function activity()
	local n = nav
	local fn = if n then n.activity else nil
	if fn then
		fn()
	end
end

-- Anneau : `alpha` de 0 à 1 sur l'élément maintenu ; 0 : caché (relâché, fini, annulé)
local function showRing(root: GuiObject, alpha: number)
	local r = ring
	if r == nil then
		return
	end
	if alpha <= 0 then
		if ringOwner == root or ringOwner == nil then
			r.Visible = false
			ringOwner = nil
		end
		return
	end
	if ringOwner ~= root then
		local card = cardOf[root]
		local center = UpgradeCard.RING_CENTER[if card and card.template == "row" then "row" else "card"]
		r.Parent = root
		r.Position = UDim2.fromOffset(center.X, center.Y)
		ringOwner = root
	end
	local lit = math.clamp(math.ceil(alpha * RING_DOTS - 1e-6), 0, RING_DOTS)
	for i, d in ringDots do
		local on = i <= lit
		local t = if on then 0 else RING_DIM
		if d.BackgroundTransparency ~= t then
			d.BackgroundTransparency = t
			local px = if on then RING_LIT else RING_DOT
			d.Size = UDim2.fromOffset(px, px)
		end
	end
	if not r.Visible then
		r.Visible = true
	end
end

local function hideRing()
	local r = ring
	if r ~= nil then
		r.Visible = false
	end
	ringOwner = nil
end

-- Élément d'un identifiant canonique (ligne qui l'envoie ; Tapis Étoilé : la ligne Tapis)
local function rootFor(id: string): Instance?
	local root = origins[id]
	if root ~= nil then
		return root
	end
	local row = rows[id] or (if id == "star" then rows.snack else nil)
	return if row then row.root else nil
end

local step: () -> ()

local function ensureLoop()
	if loopConn == nil then
		loopConn = RunService.Heartbeat:Connect(function()
			step()
		end)
	end
end

-- Un tour de la boucle des achats (seulement tant qu'il y a un achat, un retour, une consigne ou une
-- métrique à suivre : aucune connexion par image sinon)
step = function()
	local now = Clock.now()
	local b = buys
	if b ~= nil then
		local changed = b:step()
		local snap = display
		if #changed > 0 and opened and snap ~= nil then
			renderTab(current, snap)
			bannerFor(GuiService.SelectedObject)
		end
	end
	-- retours de 1,5 s (horloge recalée en arrière : fini aussi)
	for root, untilT in feedbackUntil do
		if now >= untilT or untilT - now > FEEDBACK_SECONDS + 1 then
			feedbackUntil[root] = nil
			local card = cardOf[root]
			if card ~= nil then
				card:feedback(nil)
			end
		end
	end
	-- consigne du maintien
	if hintObj ~= nil and (now >= hintUntil or hintUntil - now > HINT_SECONDS + 1) then
		hintObj = nil
		if opened then
			bannerFor(GuiService.SelectedObject)
		end
	end
	-- sablier « En cours » qui tourne (Mouvement réduit : immobile)
	local spinning = false
	if opened then
		local angle = if Juice.reducedMotion() then 0 else (now % SPIN_PERIOD) / SPIN_PERIOD * 360
		for _, card in cardOf do
			if card.state == "busy" and card.root.Visible then
				card:spin(angle)
				spinning = true
			end
		end
	end
	local more = (b ~= nil and b:busy()) or next(feedbackUntil) ~= nil or hintObj ~= nil or spinning
	if not more and loopConn ~= nil then
		loopConn:Disconnect()
		loopConn = nil
	end
end

-- Maintien fini (0,6 s) sur une carte ou une ligne : BuyUpgrade exact de sa vue, ligne « En cours »
local function onHoldDone(root: GuiObject)
	local b = buys
	local view = views[root]
	local snap = display
	if not opened or b == nil or view == nil or snap == nil then
		return
	end
	local sendId = view.sendId
	local expected = view.expectedLevel
	if (view.state ~= "ready" and view.state ~= "retry") or sendId == nil or expected == nil then
		AudioController.play("Bump")
		return
	end
	if not b:buy(sendId, view.sendMode, expected) then
		AudioController.play("Bump")
		return
	end
	origins[sendId] = root
	hintObj = nil
	activity()
	renderTab(current, snap)
	bannerFor(GuiService.SelectedObject)
	ensureLoop()
end

-- Relâché avant la fin (l'anneau s'est vidé) : son Bump et la consigne du bandeau, sauf si la croix a
-- déjà emmené la sélection ailleurs
local function onHoldEarly(root: GuiObject)
	if not opened then
		return
	end
	local selected = GuiService.SelectedObject
	if selected ~= nil and selected ~= root then
		return
	end
	AudioController.play("Bump")
	hintObj = root
	hintUntil = Clock.now() + HINT_SECONDS
	bannerFor(selected)
	ensureLoop()
end

-- Maintien de 0,6 s posé sur une carte ou une ligne à acheter (une fois, à la construction)
local function attachHold(card: Card)
	local root = card.root
	holdOf[root] = Widgets.holdOn(root :: any, {
		duration = Balance.Upgrades.HoldSeconds,
		onComplete = function()
			onHoldDone(root)
		end,
		onProgress = function(alpha: number)
			showRing(root, alpha)
		end,
		onEarly = function()
			onHoldEarly(root)
		end,
	})
	holdable[root] = true
	setHoldable(root, false)
end

-- Un retour dans la carte ou la ligne même (1,5 s), son et vibration ; aucun toast
local function showFeedback(root: Instance?, fb: UpgradeBuys.Feedback)
	local main, note = UpgradeView.feedback(fb, lang())
	if main == nil then
		return
	end
	local card = if root then cardOf[root] else nil
	if card ~= nil then
		card:feedback(main, note)
		feedbackUntil[card.root] = Clock.now() + FEEDBACK_SECONDS
	end
	table.insert(feedbackLog, { id = fb.id, key = main.key })
	if #feedbackLog > 64 then
		table.remove(feedbackLog, 1)
	end
	if fb.kind == "bought" then
		AudioController.play("TileBuild")
		Haptics.play("tileBuy")
	else
		AudioController.play("Bump")
		Haptics.play("refuse")
	end
	ensureLoop()
end

-- Réponse du serveur (UI/UpgradeSnapshot.Result : son instantané est déjà appliqué) : un retour pour
-- une ligne en attente, rien pour un refus périmé ou une réponse sans ligne en attente
local function onResult(payload: Types.UpgradeResultPayload)
	local b = buys
	if b == nil then
		return
	end
	local fb = b:result(payload)
	if not opened then
		return
	end
	local root = rootFor(payload.id)
	if b:state(payload.id) == nil then
		origins[payload.id] = nil
	end
	if fb.kind ~= "none" then
		showFeedback(root, fb)
	end
	local snap = display
	if snap ~= nil then
		renderTab(current, snap)
	end
	bannerFor(GuiService.SelectedObject)
end

-- D28 : début de SON Grand Splorch ou de SA Jelly Ascend → l'écran se ferme (une fois par spectacle)
local function closeForShow(kind: string, startedAt: number)
	if showKind == kind and showStart == startedAt then
		return
	end
	showKind, showStart = kind, startedAt
	local n = nav
	if opened and n ~= nil and n.closeAll ~= nil then
		n.closeAll()
	end
end

local function myUserId(): number?
	local p = Players.LocalPlayer
	return if p then p.UserId else nil
end

local function isMyShow(kind: any, userId: any, startedAt: any): boolean
	return (kind == "splorch" or kind == "ascend")
		and type(userId) == "number"
		and userId == myUserId()
		and type(startedAt) == "number"
		and startedAt == startedAt
end

local function onCelebrate(payload: any)
	if type(payload) ~= "table" or type(payload.data) ~= "table" then
		return
	end
	local d = payload.data
	if isMyShow(payload.kind, d.userId, d.startedAt) then
		closeForShow(payload.kind, d.startedAt)
	end
end

local function onEventState(ev: any)
	local spectacle = if type(ev) == "table" then ev.spectacle else nil
	local cur = if type(spectacle) == "table" then spectacle.current else nil
	if type(cur) == "table" and isMyShow(cur.kind, cur.userId, cur.startedAt) then
		closeForShow(cur.kind, cur.startedAt)
	end
end

-- =============================================================================================
-- Mode ×1 / ×10 / Max (□ ; E au clavier)
-- =============================================================================================

local function bindMode()
	if actionBound then
		return
	end
	actionBound = true
	pcall(function()
		ContextActionService:BindActionAtPriority(MODE_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				local top = FocusGuard.top()
				if opened and top ~= nil and top.name == "panel:Upgrades" then
					AudioController.play("Click")
					Upgrades._playerMode()
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, Widgets.BIND_PRIORITY, Enum.KeyCode.ButtonX, Enum.KeyCode.E)
	end)
end

local function unbindMode()
	if not actionBound then
		return
	end
	actionBound = false
	pcall(function()
		ContextActionService:UnbindAction(MODE_ACTION)
	end)
end

-- Mode suivant : ×1 → ×10 → Max → ×1 (aperçus recalculés, aucune instance créée)
function Upgrades.cycleMode()
	if not opened then
		return
	end
	mode = NEXT_MODE[mode] or 1
	renderAll(false)
end

-- Mode changé PAR LE JOUEUR (□, E, bouton de mode à ✕ ou au clic) : ClientMetric("upgradeMode") par
-- le limiteur (D10) et navigation (MenuActivity, D11) ; le retour à ×1 de l'ouverture n'en est pas un
local function playerCycleMode()
	if not opened then
		return
	end
	Upgrades.cycleMode()
	local b = buys
	if b ~= nil then
		b:metric("upgradeMode", mode)
		ensureLoop()
	end
	activity()
end

function Upgrades.mode(): number
	return mode
end

-- Changement de mode du joueur (bouton de mode, □, E)
function Upgrades._playerMode()
	playerCycleMode()
end

-- =============================================================================================
-- Interface des panneaux (PanelController)
-- =============================================================================================

function Upgrades.setNavigator(n: Nav)
	nav = n
end

-- Construit l'écran (une seule fois) dans le corps NU du panneau (1 440 × 860)
function Upgrades.build(body: Frame)
	if built then
		return
	end
	local snap = UpgradeSnapshot.current()
	if snap == nil then
		error("Upgrades.build : aucun instantané valide (l'écran ne se construit qu'au premier)")
	end
	built = true
	root = body
	noteSnapshot(snap)
	buildHeader(body)
	buildTabs(body)
	buildCards(body)
	for _, tab in Upgrades.LIST_TABS do
		buildList(body, tab, snap)
	end
	buildBanner(body)
	buildRing(body)
	buys = UpgradeBuys.new({
		now = Clock.now,
		send = function(name: string, ...: any): boolean
			return Widgets.send(name, ...)
		end,
	})
	for _, card in cards do
		attachHold(card)
	end
	for _, row in rows do
		if row.root:GetAttribute("ReadOnly") ~= true then
			attachHold(row)
		end
	end
	frozen = snap
	display = snap
	for _, tab in Upgrades.LIST_TABS do
		layoutList(tab, snap, viewCtx())
	end
	UpgradeSnapshot.Changed:Connect(onSnapshot)
	UpgradeSnapshot.Result:Connect(onResult)
	Net.event("Celebrate").OnClientEvent:Connect(onCelebrate)
	WorldStateController.EventChanged:Connect(onEventState)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		if not opened then
			return
		end
		local sel = GuiService.SelectedObject
		if sel then
			keepVisible(sel)
		end
		bannerFor(sel)
	end)
end

-- Ouvre l'écran (onglet demandé ; « spendFirst » : onglet Ranch, première ligne gardée payable)
function Upgrades.open(tab: string?)
	local snap = UpgradeSnapshot.current()
	if not built or snap == nil then
		return
	end
	opened = true
	mode = 1 -- le mode revient à ×1 à chaque ouverture
	frozen = snap
	display = snap
	spendTarget = nil
	local t = if type(tab) == "string" and TAB_KEYS[tab] ~= nil then tab else "suggested"
	if tab == Upgrades.SPEND_FIRST then
		t = "ranch"
	end
	current = t
	local ctx = viewCtx()
	for _, list in Upgrades.LIST_TABS do
		layoutList(list, snap, ctx)
		local sf = scrolls[list]
		if sf then
			sf.CanvasPosition = Vector2.zero
		end
	end
	chooseCards(snap)
	chooseAdvised(snap)
	if tab == Upgrades.SPEND_FIRST then
		-- première ligne GARDÉE et payable (Enclos, Lit douillet, Monuments), sinon la première gardée
		local firstKept: string? = nil
		for _, id in shownRows.ranch or {} do
			local view = UpgradeView.view(id, snap, 1, ctx)
			if view.kept then
				firstKept = firstKept or id
				if view.state == "ready" then
					spendTarget = id
					break
				end
			end
		end
		spendTarget = spendTarget or firstKept
	end
	for _, list in Upgrades.TABS do
		renderTab(list, snap)
	end
	renderHeader(snap, false)
	showTab(current)
	linkNavigation()
	bindMode()
	bannerFor(GuiService.SelectedObject)
end

-- Ferme l'écran : compteurs à leur valeur finale, raccourci □ délié ; achats en cours oubliés (une
-- réponse qui arrive écran fermé n'applique que son instantané : la réouverture est neuve), retours,
-- consigne et anneau effacés (rien ne reste appuyé)
function Upgrades.close()
	opened = false
	unbindMode()
	settleCounters()
	spendTarget = nil
	local b = buys
	if b ~= nil then
		b:clear()
	end
	table.clear(origins)
	for root in feedbackUntil do
		local card = cardOf[root]
		if card ~= nil then
			card:feedback(nil)
		end
	end
	table.clear(feedbackUntil)
	hintObj = nil
	hideRing()
end

function Upgrades.isOpen(): boolean
	return opened
end

function Upgrades.tabs(): { string }
	return table.clone(Upgrades.TABS :: any)
end

function Upgrades.currentTab(): string
	return current
end

-- Change d'onglet : Conseillé recalculé au retour sur son onglet, étoiles de l'Atelier à son ouverture
function Upgrades.setTab(tab: string)
	if type(tab) ~= "string" then
		return
	end
	if tab == Upgrades.SPEND_FIRST then
		tab = "ranch"
	end
	if TAB_KEYS[tab] == nil or not opened then
		if TAB_KEYS[tab] ~= nil then
			current = tab
		end
		return
	end
	if tab == current then
		return
	end
	current = tab
	spendTarget = nil
	local snap = display
	if snap ~= nil then
		if tab == "suggested" then
			chooseCards(snap)
		elseif tab == "workshop" then
			chooseAdvised(snap)
		end
		renderTab(tab, snap)
	end
	local sf = scrolls[tab]
	if sf then
		sf.CanvasPosition = Vector2.zero
	end
	showTab(tab)
	linkNavigation()
	bannerFor(GuiService.SelectedObject)
end

-- Sélection d'office : la ligne de « Dépenser d'abord », sinon la première carte ou la première ligne
-- montrée de l'onglet
function Upgrades.defaultSelection(): GuiObject?
	local target = spendTarget
	if target ~= nil and rows[target] ~= nil and rows[target].root.Visible then
		return rows[target].root
	end
	if current == "suggested" then
		return if cards[1] then cards[1].root else nil
	end
	local list = shownRows[current]
	if list ~= nil and list[1] ~= nil then
		return rows[list[1]].root
	end
	return tabButtons[current]
end

-- ○ : revient toujours à ce qui a ouvert l'écran (GDD §10.7.1)
function Upgrades.onBack(): boolean
	return false
end

-- L'écran existe pour ce joueur (interrupteur UpgradesScreen du serveur, D1)
function Upgrades.visible(): boolean
	return UpgradeSnapshot.available()
end

-- Textes recalculés (langue changée)
function Upgrades.refresh()
	if not opened then
		return
	end
	settleCounters()
	renderAll(false)
end

-- Stick droit : une page de lignes (la sélection suit, jamais hors de la vue)
function Upgrades.scroll(dir: number)
	if not opened or current == "suggested" then
		return
	end
	local list = shownRows[current] or {}
	local selected = GuiService.SelectedObject
	local view = if selected then views[selected] else nil
	local index = 1
	if view ~= nil then
		index = table.find(list, view.id) or 1
	end
	local step = math.max(1, math.floor(U.Content.h / U.Row.step))
	local nextIndex = math.clamp(index + (if dir > 0 then step else -step), 1, math.max(1, #list))
	local id = list[nextIndex]
	if id ~= nil and nextIndex ~= index then
		GuiService.SelectedObject = rows[id].root
	end
end

-- ✕ relâché (Activated) sur une carte ou une ligne : jamais un achat (le maintien de 0,6 s seul
-- achète). Lecture seule, cadenas, MAX, plafond de la boucle → Bump sans vibration ; « Il manque » →
-- refus doux (Bump, vibration refuse, aucune secousse) ; « En cours » → rien ; Prête / « Réessaie » →
-- rien (relâché trop tôt : la consigne vient du maintien) ; carte « Jelly Ascend » → son aperçu (N24)
function Upgrades._activate(obj: GuiObject)
	if not opened or not Widgets.confirmed() then
		return
	end
	local view = views[obj]
	if view == nil then
		return
	end
	if view.kind == "note" then
		if view.id == UpgradeAdvisor.ASCEND and nav ~= nil then
			AudioController.play("Click")
			nav.open("SplorchPreview", "ascend")
		else
			AudioController.play("Bump")
		end
		return
	end
	if view.readOnly then
		AudioController.play("Bump")
		return
	end
	local st = view.state
	if st == "need" then
		AudioController.play("Bump")
		Haptics.play("refuse")
	elseif st == "max" or st == "locked" or st == "loopCap" then
		AudioController.play("Bump")
	end
end

-- =============================================================================================
-- Specs
-- =============================================================================================

function Upgrades._root(): Frame?
	return root
end

function Upgrades._row(id: string): GuiObject?
	local row = rows[id]
	return if row then row.root else nil
end

function Upgrades._card(i: number): GuiObject?
	local card = cards[i]
	return if card then card.root else nil
end

function Upgrades._cards(): { string }
	return table.clone(cardIds)
end

function Upgrades._shown(tab: string): { string }
	return table.clone(shownRows[tab] or {})
end

function Upgrades._list(tab: string): ScrollingFrame?
	return scrolls[tab]
end

function Upgrades._tab(tab: string): TextButton?
	return tabButtons[tab]
end

function Upgrades._modeButton(): TextButton?
	return modeButton
end

function Upgrades._banner(): TextLabel?
	return bannerLabel
end

function Upgrades._advised(): { string }
	local out: { string } = {}
	for id in advised do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

function Upgrades._view(obj: Instance): View?
	return views[obj]
end

-- Achats en attente (identifiants canoniques), retours montrés, anneau (specs)
function Upgrades._pending(): { string }
	local b = buys
	return if b then b:pendingIds() else {}
end

function Upgrades._feedbacks(): { { id: string, key: string } }
	return table.clone(feedbackLog)
end

function Upgrades._ring(): Frame?
	return ring
end

function Upgrades._hold(obj: Instance): Widgets.Hold?
	return holdOf[obj]
end

function Upgrades._holdGlyph(): Frame?
	return bannerGlyph
end

-- Valeur montrée d'un compteur de l'en-tête (« coins », « confetti ») et sa cible
function Upgrades._counter(name: string): (number?, number?)
	local c = counters[name]
	if c == nil then
		return nil, nil
	end
	return c.shown, c.to
end

return Upgrades
