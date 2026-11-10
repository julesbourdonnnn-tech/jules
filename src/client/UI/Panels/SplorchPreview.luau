--!strict
-- SplorchPreview (paquet client-panels ; lot B3, étape 2) : aperçu des renaissances (GDD §4.15, §4.27,
-- §10.3 ; docs/04 §13.6, §27.13 N1, N7, N24), fait pour des enfants qui lisent peu.
--
-- Chemin de la v1.3 (aucun instantané du serveur : interrupteurs coupés, jeu de base identique) :
--   1. 3 grandes tuiles « Tu gagnes » : « Croissance ×2 pour toujours », le déblocage de ce niveau
--      (Balance.Splorch.Unlocks ; sinon « Cuve meilleure »), « +5 Fame » ;
--   2. animation avant / après : le squishy redevient petit puis regrandit (fixe en Mouvement réduit) ;
--   3. pièces perdues en rouge (Pot compris) et « Dépenser d'abord » → Ranch › Dalles, avec d'abord
--      les dalles gardées (onglet « padsKept ») ;
--   4. choix du squishy qui s'envole (défaut : le plus gros qui n'est pas Meilleur Ami), flèches
--      DESSINÉES (Hud/Icons arrowRight, celle de gauche tournée de 180° ; règle 18, lot B3, D17) ;
--   5. bouton à maintenir 1,5 s (✕) et case « Filmer » (cachée si l'attribut local ClipsUnavailable).
--   « Détails » ouvre les deux colonnes (Tu gardes / Repart de zéro) et le prochain objectif.
--
-- Chemin de la v2.0 (UpgradeSnapshot.available() ; lot B3, D6 à D9 du plan B3) — construit une fois à
-- la première ouverture v2.0, jamais les parties propres à la v1.3 (et inversement) ; un chemin qui
-- change entre deux ouvertures construit ce qui manque à l'ouverture suivante, jamais écran ouvert :
--   * page du Grand Splorch ou du Petit Splorch : 3 tuiles UpgradeCard « tile » (400 × 300, textes de
--     UI/MetaView.previewTiles), animation avant / après, ligne rouge « Tu vas perdre … » et « Dépenser
--     d'abord » SEULEMENT si une ligne gardée est payable (MetaView.keptPayable, Upgrades par-dessus
--     l'aperçu, ○ y revient), sinon la phrase neutre « Tes pièces deviennent le cadeau du Splorch » ;
--     boîte des refus (600 × 120) ; maintien 1,5 s (Petit Splorch : « Maintiens pour le Petit
--     Splorch ») ; « Détails » : les deux colonnes, le prochain objectif, le choix de l'envol et
--     « Filmer » (caché pour un Petit Splorch : il n'a pas de film) ;
--   * onglet « ascend » (Jelly Ascend ; interrupteur JellyAscend, profil v2, attribut AscendReady de MON
--     ranch) : mêmes 3 tuiles, ligne du départ (40 px) et ligne calculée « 9 fois plus vite » (32 px),
--     6 icônes « gardé », condition, barre et coche dessinée ; ✕ maintenu 3 s (anneau autour d'un glyphe
--     de 64 px), puis la carte « Prêt à monter ? » (fenêtre FocusGuard au-dessus de l'aperçu, focus sur
--     « Oui », boutons grisés 0,6 s APRÈS le relâchement de ✕, confirmation par un InputBegan capté,
--     jamais Activated, 20 s sans réponse : fermée) ; « Oui » : JellyAscend(true) une fois, puis tout
--     se ferme ; « Plus tard », ○ et le délai ferment la carte ET l'aperçu (retour à l'entrée du rail) ;
--   * onglets (L1 / R1) quand le prestige de la boucle et l'Ascension sont prêts tous les deux ; le titre
--     de la fenêtre suit l'onglet (« Grand Splorch », « Petit Splorch », « Jelly Ascend ») ;
--   * l'aperçu se ferme au début de MON spectacle (MetaFlags.myPrestige() == "show") ; MON prestige dans
--     la file : maintien refusé, avec son texte ;
--   * mesures (ClientMetric, au mieux, seau partagé de Widgets.send, jamais mises en file) :
--     ascendPreview 0 (onglet ascend montré), 2 (confirmé) ; aperçu fermé sans Ascension après l'onglet
--     ascend : ascendDeclined <jours> puis ascendPreview 1.
-- Hors du ranch : « Rentre dans ton ranch » ; un squishy en fuite : feedback.waitEscape ; dans les deux
-- cas le maintien est refusé (le serveur revérifie tout une seule fois à l'entrée dans la file). Même
-- calcul que le serveur : Logic/Formulas.splorchPreview sur le profil répliqué ; tuiles et lignes de la
-- v2.0 : Logic/Prestige par UI/MetaView (jamais une formule refaite ici).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Balance = require(Shared.Config.Balance)
local Layout = require(Shared.Config.Layout)
local Formulas = require(Shared.Logic.Formulas)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent.Parent
local Juice = require(Client.UI.Juice)
local Prefs = require(Client.Util.Prefs)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local FocusGuard = require(Client.UI.FocusGuard)
local Text = require(Client.UI.Text)
local Icons = require(Client.UI.Hud.Icons)
local UpgradeCard = require(Client.UI.UpgradeCard)
local UpgradeSnapshot = require(Client.UI.UpgradeSnapshot)
local MetaFlags = require(Client.UI.MetaFlags)
local MetaView = require(Client.UI.MetaView)
local Widgets = require(script.Parent.Widgets)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> (), closeAll: (() -> ())? }

local SplorchPreview = {}

local PROFILE_KEYS = { "R", "growth", "squishies", "coins", "pot" }
local ANIM_PERIOD = 2.4 -- s : rétrécit (0,6 s), regrandit (0,4 s), attend
local ARROW = 48 -- flèches dessinées du choix de l'envol (px TV)

-- v2.0 (lot B3) : disposition dans le corps du panneau (1 440 × 764 px TV)
local U = Layout.Upgrades
local TILE_W, TILE_H = U.Tile.w, U.Tile.h
local TILE_GAP = 40
local TOP = 88 -- haut des tuiles : sous la barre d'onglets (y 4-84) ou le titre « Tu gagnes »
local ROW1 = TOP + TILE_H + 8 -- 396 : ligne du départ / ligne des pièces
local LINE_H = U.PreviewLine.h -- 120 : 2 lignes de 40 px au facteur 1,5
local SPEED_H = 48 -- ligne de 32 px au facteur 1,5
local KEPT_Y = ROW1 + LINE_H + SPEED_H + 8 -- 572 : 6 icônes « gardé »
local KEPT_CELL = 200
local KEPT_ICON = 48
local ASCEND_ROW = KEPT_Y + 56 + 8 -- 636 : condition et maintien de 3 s
local REFUSAL = U.RefusalBox -- 600 × 120
local CONFIRM = U.ConfirmButton -- 360 × 112, texte 40
local HOLD_W, HOLD_H = 560, 112 -- maintien de l'Ascension (anneau autour d'un glyphe de 64)
local HOLD_GLYPH = 64
local RING_DOTS = 12
local RING_RY = 44 -- rayon vertical de l'anneau (px TV) ; l'horizontal suit la largeur du glyphe
local RING_DOT, RING_LIT, RING_DIM = 8, 12, 0.5
local CARD_W, CARD_H = 880, 380
local CARD_WINDOW = "AscendConfirm" -- fenêtre FocusGuard de la carte « Prêt à monter ? »
local CONFIRM_GUARD = Balance.Ascend.ConfirmGuard -- 0,6 s, comptées depuis le relâchement de ✕
local CONFIRM_TIMEOUT = Balance.Ascend.ConfirmTimeout -- 20 s
local DAY = 86400
local CONFIRM_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
}
-- titre de la fenêtre et libellé de l'onglet de la boucle selon la renaissance montrée
local TITLE_KEYS: { [string]: string } = {
	splorch = "panel.splorch.title",
	petit = "menu.petitSplorch",
	ascend = "ascend.title",
}
local LOOP_TAB_KEYS: { [string]: string } = {
	splorch = "panel.splorch.tab.splorch",
	petit = "menu.petitSplorch",
}
-- 6 icônes « Tout le reste est gardé » (GDD §4.27) : dessin de Hud/Icons, couleur, clé du libellé
local KEPT: { { icon: string, color: Color3?, key: string } } = {
	{ icon = "drop", key = "ascend.kept.squishies" },
	{ icon = "confetti", key = "ascend.kept.confetti" },
	{ icon = "gear", key = "ascend.kept.workshop" },
	{ icon = "helper", key = "ascend.kept.helpers" },
	{ icon = "monument", key = "ascend.kept.tiers" },
	{ icon = "star", color = Color3.fromRGB(130, 180, 255), key = "ascend.kept.dex" },
}

local nav: Nav? = nil
local isOpen = false
local detailsOpen = false
local preview: { [string]: any } = {}
local flyers: { string } = {}
local flyerIndex = 1
local filmOn = true
local container: Frame? = nil
local path: "v13" | "v2" = "v13"
local anim: RBXScriptConnection? = nil
local animStart = 0
local lastReason = "" -- raison du refus affichée (le message suit la fuite, le retour au ranch)

-- chemin de la v1.3 (construit seulement quand il sert)
local v13Built = false
local labels: { [string]: TextLabel } = {}
local tiles: { TextLabel } = {}
local main: Frame? = nil
local details: Frame? = nil
local detailsOk: TextButton? = nil
local detailsButton: TextButton? = nil
local spendButton: TextButton? = nil
local prevButton: TextButton? = nil
local nextButton: TextButton? = nil
local filmToggle: Widgets.Toggle? = nil
local filmRow: Frame? = nil
local hold: Widgets.Hold? = nil
local blob: Frame? = nil

-- chemin de la v2.0 (lot B3)
type V2Parts = {
	root: Frame,
	win: TextLabel,
	tiles: { UpgradeCard.Card },
	tilesFrame: Frame,
	splorch: Frame,
	stage: Frame,
	blob: Frame,
	line: TextLabel,
	spend: TextButton,
	refusalBox: Frame,
	refusal: TextLabel,
	hold: Widgets.Hold,
	holdLabel: TextLabel?,
	details: TextButton,
	page: Frame, -- page « Détails »
	next: TextLabel,
	flyerName: TextLabel,
	prev: TextButton,
	nextFlyer: TextButton,
	filmRow: Frame,
	filmToggle: Widgets.Toggle,
	ok: TextButton,
}
type AscendParts = {
	page: Frame,
	restart: TextLabel,
	speed: TextLabel,
	condBox: Frame,
	cond: TextLabel,
	check: Frame,
	bar: Frame,
	fill: Frame,
	refusal: TextLabel,
	button: TextButton,
	hold: Widgets.Hold,
	dots: { Frame },
}
type CardParts = {
	root: Frame,
	panel: Frame,
	title: TextLabel,
	later: TextButton,
	yes: TextButton,
}
local v2: V2Parts? = nil
local asc: AscendParts? = nil
local card: CardParts? = nil
local tabBar: Widgets.TabBar? = nil
local currentTab = "splorch"
local shownTabs: { string } = {}
local titleKey = TITLE_KEYS.splorch -- titre posé par PanelController à la construction de la fenêtre
local lastSig = ""
local lines: MetaView.AscendLines? = nil
-- carte « Prêt à monter ? »
local cardOpen = false
local cardOpenedAt = 0
local cardReleasedAt: number? = nil
local cardActive = false
local hovered: TextButton? = nil
-- mesures de l'Ascension (une fois par ouverture)
local ascendShown = false
local ascendSent = false
local declineNoted = false
local readySince: number? = nil -- premier AscendReady vu dans la séance (Clock.now())

local function computePreview(): { [string]: any }
	local data = Widgets.profile(PROFILE_KEYS)
	local p = Widgets.safe("Formulas.splorchPreview", nil, Formulas.splorchPreview, data, {
		now = Clock.now(),
		unix = Clock.unix(),
	})
	return if type(p) == "table" then p else {}
end

local function squishies(): { [string]: any }
	return Widgets.tbl(Widgets.state("squishies"))
end

-- Squishies de l'enclos qui peuvent s'envoler, défaut du serveur en premier puis du plus gros
local function collectFlyers(defaultUid: string?): { string }
	local G = Widgets.safe("Formulas.G", 0, Formulas.G, Widgets.state("growth"), Clock.now())
	local list: { { uid: string, size: number } } = {}
	for uid, rec in squishies() do
		if type(uid) == "string" and type(rec) == "table" and rec.at == "pen" then
			table.insert(
				list,
				{ uid = uid, size = Widgets.safe("Formulas.sizeAt", 1, Formulas.sizeAt, rec, G) }
			)
		end
	end
	table.sort(list, function(a, b)
		if a.uid == defaultUid then
			return true
		elseif b.uid == defaultUid then
			return false
		end
		if a.size ~= b.size then
			return a.size > b.size
		end
		return a.uid < b.uid
	end)
	local out = {}
	for _, e in list do
		table.insert(out, e.uid)
	end
	return out
end

local function mySlot(): number
	local slot = Widgets.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
	return if type(slot) == "number" then slot else 0
end

-- Dans son ranch ? (nil : inconnu, le serveur décide)
local function inRanch(): boolean?
	local slot = mySlot()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if slot <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local ok, inside = pcall(WorldLayout.inRanch, slot, root.Position)
	return if ok then inside == true else nil
end

-- Espèce d'un de mes squishies en fuite (créature « escape » de mon ranch encore vivante), sinon nil
local function escaping(): number?
	local slot = mySlot()
	if slot <= 0 then
		return nil
	end
	local creatures = Widgets.safe("WorldStateController.creatures", {}, WorldStateController.creatures)
	if type(creatures) ~= "table" then
		return nil
	end
	local now = Clock.now()
	for _, c in creatures do
		if
			type(c) == "table"
			and c.kind == "escape"
			and c.ownerSlot == slot
			and Widgets.n(c.t0) + Widgets.n(c.duration) > now
		then
			return if type(c.species) == "number" then c.species else 0
		end
	end
	return nil
end

local function clipsUnavailable(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("ClipsUnavailable") == true
end

-- Raison du refus du maintien ("" : prêt)
local function blocker(): string
	if preview.ready ~= true then
		return "notReady"
	end
	if flyers[flyerIndex] == nil then
		return "noFlyer"
	end
	if escaping() ~= nil then
		return "escape"
	end
	if inRanch() == false then
		return "goHome"
	end
	return ""
end

local function closeAllPanels()
	local n = nav
	if n then
		if n.closeAll then
			n.closeAll()
		else
			n.back()
		end
	end
end

-- Envol choisi : liste refaite (défaut du serveur en tête), le choix du joueur gardé s'il est encore là
local function updateFlyers()
	local keep = flyers[flyerIndex]
	flyers = collectFlyers(if type(preview.defaultFlyer) == "string" then preview.defaultFlyer else nil)
	flyerIndex = math.max(1, table.find(flyers, keep or "") or 1)
end

-- Flèche dessinée d'un bouton du choix de l'envol (règle 18 : « ◀ » « ▶ » absents des polices)
local function arrow(button: GuiButton, left: boolean)
	local c = Icons.canvas(button, ARROW, { "arrowRight" }, "Arrow")
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.5)
	c.ZIndex = button.ZIndex + 1
	if left then
		c.Rotation = 180
	end
	Icons.draw(c, "arrowRight", Widgets.Colors.Text)
end

-- =============================================================================================
-- Chemin de la v1.3
-- =============================================================================================

local function setDetails(open: boolean)
	detailsOpen = open
	if details then
		details.Visible = open
	end
	if main then
		main.Visible = not open
	end
	if open and detailsOk then
		GuiService.SelectedObject = detailsOk
	elseif not open and detailsButton and detailsButton.Parent then
		GuiService.SelectedObject = detailsButton
	end
end

local function refreshV13()
	if hold == nil then
		return
	end
	preview = computePreview()
	-- tuiles « Tu gagnes »
	Widgets.setText(tiles[1], "panel.splorch.win.growth")
	local unlocks = if type(preview.unlocks) == "table" then preview.unlocks else {}
	local first = unlocks[1]
	if type(first) == "string" then
		Widgets.setText(tiles[2], "panel.splorch.unlock." .. first)
	else
		Widgets.setText(tiles[2], "panel.splorch.unlock.vat")
	end
	Widgets.setText(tiles[3], "panel.splorch.win.fame")
	-- pièces perdues (rouge) et « Dépenser d'abord »
	local lost = Widgets.n(preview.coinsLost)
	labels.lose.Visible = lost > 0
	Widgets.setText(labels.lose, "panel.splorch.lose", { coins = Widgets.num(lost) })
	local spend = spendButton :: TextButton
	spend.Visible = lost > 0
	-- squishy qui s'envole
	updateFlyers()
	local uid = flyers[flyerIndex]
	local rec = if uid then squishies()[uid] else nil
	if type(rec) == "table" then
		Widgets.setRaw(labels.flyerName, Widgets.speciesName(rec.s))
		Widgets.paintBlob(blob :: Frame, rec.s, true)
	else
		Widgets.setText(labels.flyerName, "common.empty")
		Widgets.paintBlob(blob :: Frame, nil, false)
	end
	Widgets.setDisabled(prevButton :: TextButton, #flyers < 2)
	Widgets.setDisabled(nextButton :: TextButton, #flyers < 2)
	-- case « Filmer » (cachée sans capture vidéo)
	local row = filmRow :: Frame
	row.Visible = not clipsUnavailable()
	-- état du maintien et message
	local reason = blocker()
	lastReason = reason
	local status = labels.status
	if reason == "notReady" then
		status.Visible = true
		Widgets.setText(status, "panel.splorch.notReady", {
			have = Widgets.num(Widgets.n(preview.biggest)),
			need = Widgets.num(Widgets.n(preview.target)),
		})
	elseif reason == "escape" then
		status.Visible = true
		Widgets.setText(status, "feedback.waitEscape", { species = Widgets.speciesName(escaping()) })
	elseif reason == "goHome" then
		status.Visible = true
		Widgets.setText(status, "panel.splorch.goHome")
	else
		status.Visible = false
	end
	local h = hold :: Widgets.Hold
	Widgets.setDisabled(h.button, reason ~= "")
	-- détails
	Widgets.setText(
		labels.next,
		"panel.splorch.next",
		{ target = Widgets.num(Widgets.n(preview.nextTarget)) }
	)
end

local function onHoldDone()
	if blocker() ~= "" then
		Widgets.refuse((hold :: Widgets.Hold).button)
		return
	end
	local film = filmOn and not clipsUnavailable()
	if Widgets.send("GrandSplorch", film, flyers[flyerIndex]) then
		-- choix « Filmer » lu par VFXController au Celebrate "splorch" (note INT-CW-2) : il ne voyage pas
		local me = Players.LocalPlayer
		if me then
			pcall(me.SetAttribute, me, "SplorchFilm", film)
		end
		closeAllPanels()
	end
end

local function tile(parent: Frame, i: number, width: number): TextLabel
	local f = Widgets.frame({
		parent = parent,
		name = "Tile" .. i,
		size = UDim2.fromOffset(width, 150),
		position = UDim2.fromOffset(48 + (i - 1) * (width + Layout.Spacing.Normal), 60),
		color = Widgets.Colors.CardLight,
		gradient = true,
	})
	return Widgets.label({
		parent = f,
		name = "Text",
		size = UDim2.new(1, -32, 1, -24),
		position = UDim2.fromOffset(16, 12),
		text = "",
		textSize = 40,
		wrapped = true,
		color = Widgets.Colors.Gold,
	})
end

-- Construit la page de la v1.3 une seule fois dans le cadre du panneau
local function buildV13(c: Frame)
	v13Built = true
	local width = c.Size.X.Offset
	local height = c.Size.Y.Offset
	local m = Widgets.group(c, "Main", UDim2.fromOffset(width, height), UDim2.new())
	main = m
	Widgets.label({
		parent = m,
		name = "Win",
		size = UDim2.fromOffset(width - 96, 48),
		position = UDim2.fromOffset(48, 4),
		key = "panel.splorch.win",
		textSize = 40,
	})
	local tileW = math.floor((width - 96 - 2 * Layout.Spacing.Normal) / 3)
	for i = 1, 3 do
		tiles[i] = tile(m, i, tileW)
	end
	-- avant / après
	local stage = Widgets.frame({
		parent = m,
		name = "Stage",
		size = UDim2.fromOffset(300, 220),
		position = UDim2.fromOffset(48, 230),
		color = Widgets.Colors.Card,
	})
	local b = Widgets.blob(stage, "Flyer")
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -12)
	b.Size = UDim2.fromOffset(170, 150)
	blob = b
	-- squishy qui s'envole
	local col = 48 + 300 + Layout.Spacing.Normal
	Widgets.label({
		parent = m,
		name = "FlyerTitle",
		size = UDim2.fromOffset(560, 44),
		position = UDim2.fromOffset(col, 230),
		key = "panel.splorch.flyer",
		textSize = 36,
		xAlign = Enum.TextXAlignment.Left,
	})
	local prev = Widgets.button({
		parent = m,
		name = "PrevFlyer",
		size = UDim2.fromOffset(100, Layout.Button.MinHeight),
		position = UDim2.fromOffset(col, 284),
		onActivate = function()
			if #flyers > 1 then
				flyerIndex = ((flyerIndex - 2) % #flyers) + 1
				refreshV13()
			end
		end,
	})
	arrow(prev, true)
	prevButton = prev
	labels.flyerName = Widgets.label({
		parent = m,
		name = "FlyerName",
		size = UDim2.fromOffset(340, Layout.Button.MinHeight),
		position = UDim2.fromOffset(col + 116, 284),
		text = "",
		textSize = 40,
	})
	local nextB = Widgets.button({
		parent = m,
		name = "NextFlyer",
		size = UDim2.fromOffset(100, Layout.Button.MinHeight),
		position = UDim2.fromOffset(col + 472, 284),
		onActivate = function()
			if #flyers > 1 then
				flyerIndex = (flyerIndex % #flyers) + 1
				refreshV13()
			end
		end,
	})
	arrow(nextB, false)
	nextButton = nextB
	-- pièces perdues et « Dépenser d'abord »
	local right = col + 600
	labels.lose = Widgets.label({
		parent = m,
		name = "Lose",
		size = UDim2.fromOffset(width - right - 48, 56),
		position = UDim2.fromOffset(right, 230),
		text = "",
		textSize = 36,
		wrapped = true,
		color = Widgets.Colors.Danger,
	})
	spendButton = Widgets.button({
		parent = m,
		name = "SpendFirst",
		size = UDim2.fromOffset(width - right - 48, Layout.Button.MinHeight),
		position = UDim2.fromOffset(right, 296),
		key = "panel.splorch.spendFirst",
		nav = true,
		onActivate = function()
			if nav then
				nav.open("Ranch", "padsKept")
			end
		end,
	})
	-- Filmer
	local fr = Widgets.group(
		m,
		"Film",
		UDim2.fromOffset(width - col - 48, Layout.Panel.toggle.h),
		UDim2.fromOffset(col, 384)
	)
	filmRow = fr
	filmToggle = Widgets.toggle(
		fr,
		"Toggle",
		UDim2.fromScale(0, 0.5),
		Vector2.new(0, 0.5),
		function(v: boolean)
			filmOn = v
		end
	)
	Widgets.label({
		parent = fr,
		name = "Label",
		size = UDim2.new(1, -(Layout.Panel.toggle.w + 24), 1, 0),
		position = UDim2.fromOffset(Layout.Panel.toggle.w + 24, 0),
		key = "panel.splorch.film",
		textSize = 32,
		xAlign = Enum.TextXAlignment.Left,
	})
	-- message (hors du ranch, fuite, pas prêt)
	labels.status = Widgets.label({
		parent = m,
		name = "Status",
		size = UDim2.fromOffset(width - 96, 48),
		position = UDim2.fromOffset(48, 470),
		text = "",
		textSize = 36,
		color = Widgets.Colors.Warning,
	})
	-- maintenir 1,5 s (✕) et Détails
	hold = Widgets.hold({
		parent = m,
		name = "Hold",
		size = UDim2.fromOffset(640, Layout.Button.MainHeight),
		position = UDim2.new(0.5, -170, 1, -40),
		anchor = Vector2.new(0.5, 1),
		key = "panel.splorch.hold",
		duration = Balance.Splorch.HoldConfirm,
		textSize = 40,
		onComplete = onHoldDone,
		canStart = function(): boolean
			return blocker() == ""
		end,
	})
	detailsButton = Widgets.button({
		parent = m,
		name = "Details",
		size = UDim2.fromOffset(300, Layout.Button.MainHeight),
		position = UDim2.new(0.5, 330, 1, -40),
		anchor = Vector2.new(0.5, 1),
		key = "panel.splorch.details",
		nav = true,
		onActivate = function()
			setDetails(true)
		end,
	})
	-- Détails : Tu gardes / Repart de zéro, prochain objectif
	local d = Widgets.group(c, "DetailsPage", UDim2.fromOffset(width, height), UDim2.new())
	d.Visible = false
	details = d
	local colW = math.floor((width - 96 - Layout.Spacing.Normal) / 2)
	for i, spec in
		{
			{ "panel.splorch.keep", "panel.splorch.keep.list", Widgets.Colors.Success },
			{ "panel.splorch.reset", "panel.splorch.reset.list", Widgets.Colors.Danger },
		}
	do
		local f = Widgets.frame({
			parent = d,
			name = "Column" .. i,
			size = UDim2.fromOffset(colW, 400),
			position = UDim2.fromOffset(48 + (i - 1) * (colW + Layout.Spacing.Normal), 24),
			color = Widgets.Colors.Card,
		})
		Widgets.label({
			parent = f,
			name = "Title",
			size = UDim2.new(1, -32, 0, 56),
			position = UDim2.fromOffset(16, 12),
			key = spec[1],
			textSize = 44,
			color = spec[3],
		})
		Widgets.label({
			parent = f,
			name = "List",
			size = UDim2.new(1, -32, 1, -96),
			position = UDim2.fromOffset(16, 80),
			key = spec[2],
			textSize = 36,
			wrapped = true,
		})
	end
	labels.next = Widgets.label({
		parent = d,
		name = "Next",
		size = UDim2.fromOffset(width - 96, 56),
		position = UDim2.fromOffset(48, 448),
		text = "",
		textSize = 40,
		color = Widgets.Colors.Gold,
	})
	detailsOk = Widgets.button({
		parent = d,
		name = "Ok",
		size = UDim2.fromOffset(360, Layout.Button.MainHeight),
		position = UDim2.new(0.5, 0, 1, -40),
		anchor = Vector2.new(0.5, 1),
		key = "common.back",
		onActivate = function()
			setDetails(false)
		end,
	})
end

-- =============================================================================================
-- Chemin de la v2.0 (lot B3) : outils
-- =============================================================================================

local function lang(): string
	local ok, l = pcall(Prefs.language)
	return if ok and l == "fr" then "fr" else "en"
end

local function tr(key: string, vars: { [string]: any }?): string
	return Widgets.t(key, vars)
end

-- Contexte des vues pures (UI/MetaView) : langue, interrupteurs ouverts, instantané du serveur
local function metaCtx(): MetaView.Ctx
	return {
		lang = lang(),
		on = MetaFlags.on,
		snap = UpgradeSnapshot.current(),
	}
end

-- Texte d'une vue avec ses variables-clés traduites (MetaView.resolve) ; nil : rien
local function resolve(t: any): any
	return MetaView.resolve(t, tr)
end

-- Pose un texte { key, vars } (variables-clés traduites) sur un libellé
local function setView(label: TextLabel, t: any)
	local r = resolve(t)
	if type(r) == "table" and type(r.key) == "string" then
		Widgets.setText(label, r.key, r.vars)
	else
		Widgets.setRaw(label, "")
	end
end

-- La Jelly Ascend est-elle proposée ? (interrupteur, profil v2, attribut AscendReady de MON ranch ; une
-- valeur abîmée = non, sans trace)
local function ascendAvailable(): boolean
	return asc ~= nil
		and MetaFlags.on("JellyAscend")
		and MetaFlags.v2Profile()
		and MetaFlags.attr("AscendReady") == true
end

-- Prestige de la boucle prêt : "petit" (remontée, interrupteur PetitSplorch ouvert), "splorch", ou nil
local function loopKind(): string?
	if preview.ready ~= true then
		return nil
	end
	local ok, kind = pcall(UpgradeSnapshot.rebirth, true)
	if ok and kind == "petit" and MetaFlags.on("PetitSplorch") then
		return "petit"
	end
	return "splorch"
end

-- Onglets disponibles : la boucle d'abord, puis l'Ascension (L1 / R1 quand il y en a deux)
local function tabsNow(): { string }
	local list = {}
	if preview.ready == true then
		table.insert(list, "splorch")
	end
	if ascendAvailable() then
		table.insert(list, "ascend")
	end
	return list
end

-- Refus de la page de la boucle (v2.0) : MON prestige dans la file ou en cours, puis les règles de la v1.3
local function blockerV2(): string
	if MetaFlags.myPrestige() ~= nil then
		return "queued"
	end
	return blocker()
end

-- Refus de l'onglet ascend : MON prestige déjà là (sa sorte change le texte), condition, fuite, ranch
local function ascendBlocker(): string
	local state, kind = MetaFlags.myPrestige()
	if state ~= nil then
		return if kind == "splorch" then "queuedSplorch" else "queued"
	end
	local l = lines
	if not ascendAvailable() or l == nil or not l.met then
		return "notReady"
	end
	if escaping() ~= nil then
		return "escape"
	end
	if inRanch() == false then
		return "goHome"
	end
	return ""
end

-- Texte d'un refus (boîte des refus) ; nil : aucun texte (maintien grisé seulement, ou rien)
local function refusalText(reason: string): (string?, { [string]: any }?)
	if reason == "queued" then
		return "feedback.waitingSplorch", nil
	elseif reason == "queuedSplorch" then
		return "ascend.queued", nil
	elseif reason == "escape" then
		return "feedback.waitEscape", { species = Widgets.speciesName(escaping()) }
	elseif reason == "goHome" then
		return "panel.splorch.goHome", nil
	elseif reason == "notReady" and currentTab ~= "ascend" then
		return "panel.splorch.notReady",
			{
				have = Widgets.num(Widgets.n(preview.biggest)),
				need = Widgets.num(Widgets.n(preview.target)),
			}
	end
	return nil, nil
end

-- Titre de la fenêtre (en-tête de PanelController) : il suit la renaissance montrée (chemin v2.0)
local function setTitle(key: string)
	if titleKey == key then
		return
	end
	local c = container
	local win = c and c.Parent
	local header = win and win:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		Widgets.setText(title, key)
		titleKey = key
	end
end

-- Mesure du client (au mieux : seau partagé de Widgets.send, jamais en file)
local function metric(kind: string, value: number)
	local v = if value == value then math.clamp(math.floor(value), 0, 1000) else 0
	Widgets.send("ClientMetric", kind, v)
end

local function noteAscendShown()
	if ascendShown then
		return
	end
	ascendShown = true
	metric("ascendPreview", 0)
end

-- Aperçu fermé (Plus tard, ○, délai, ou fermé autrement) sans Ascension après l'onglet ascend : refus
-- compté une fois par ouverture (jours depuis le premier AscendReady vu dans la séance)
local function noteDeclined()
	if not ascendShown or ascendSent or declineNoted then
		return
	end
	declineNoted = true
	local since = readySince
	local days = if since then math.floor(math.max(0, Clock.now() - since) / DAY) else 0
	metric("ascendDeclined", days)
	metric("ascendPreview", 1)
end

-- =============================================================================================
-- Chemin de la v2.0 : rendu
-- =============================================================================================

-- Tuiles « Tu gagnes » de la renaissance montrée (mêmes 3 tuiles pour les deux onglets)
local function renderTiles(kind: string)
	local parts = v2
	if parts == nil then
		return
	end
	local list = MetaView.previewTiles(kind, metaCtx())
	for i, cardObj in parts.tiles do
		local t = list[i]
		if type(t) == "table" then
			local view = table.clone(t) :: any
			view.name = resolve(t.name) or { key = "common.empty" }
			view.value = if t.value ~= nil then resolve(t.value) else nil
			cardObj:set("ready", view)
			cardObj.root.Visible = true
		else
			cardObj.root.Visible = false
		end
	end
end

-- Barre d'onglets (construite à la première ouverture qui en montre deux) et titre « Tu gagnes »
local function renderTabs(kind: string)
	local parts = v2
	if parts == nil then
		return
	end
	local bar = tabBar
	local two = bar ~= nil and #shownTabs >= 2
	if bar then
		bar.frame.Visible = two
		if two then
			bar.setActive(currentTab)
			local b = bar.buttons.splorch
			local label = if b then Widgets.buttonLabel(b) else nil
			if label then
				Widgets.setText(label, LOOP_TAB_KEYS[if kind == "petit" then "petit" else "splorch"])
			end
		end
	end
	parts.win.Visible = not two and not detailsOpen
end

local function refreshSplorchPage(kind: string)
	local parts = v2 :: V2Parts
	-- pièces perdues et « Dépenser d'abord » seulement si une ligne gardée est payable (GDD §4.15, N7)
	local lost = Widgets.n(preview.coinsLost)
	local kept: string? = nil
	if lost > 0 then
		local passes = Widgets.tbl(Widgets.state("passes"))
		kept = MetaView.keptPayable(
			UpgradeSnapshot.current(),
			{ lang = lang(), bigRanch = passes.BigRanch == true }
		)
	end
	if kept ~= nil then
		Widgets.setText(parts.line, "panel.splorch.lose", { coins = Widgets.num(lost) })
		parts.line.TextColor3 = Widgets.Colors.Danger
	else
		Widgets.setText(parts.line, "preview.splorch.neutral")
		parts.line.TextColor3 = Widgets.Colors.Text
	end
	parts.spend.Visible = kept ~= nil
	-- maintien : Grand Splorch ou Petit Splorch
	if parts.holdLabel then
		Widgets.setText(
			parts.holdLabel :: TextLabel,
			if kind == "petit" then "petit.hold" else "panel.splorch.hold"
		)
	end
	-- refus (boîte de 600 × 120, centrée quand « Dépenser d'abord » n'est pas là)
	local reason = blockerV2()
	lastReason = reason
	local key, vars = refusalText(reason)
	parts.refusalBox.Visible = key ~= nil
	if key then
		Widgets.setText(parts.refusal, key, vars)
	end
	local x = if parts.spend.Visible then 312 + 420 + 24 else 312 + math.floor((1080 - REFUSAL.w) / 2)
	if parts.refusalBox.Position.X.Offset ~= x then
		parts.refusalBox.Position = UDim2.fromOffset(x, parts.refusalBox.Position.Y.Offset)
	end
	Widgets.setDisabled(parts.hold.button, reason ~= "")
end

local function refreshDetails(kind: string)
	local parts = v2 :: V2Parts
	Widgets.setText(parts.next, "panel.splorch.next", { target = Widgets.num(Widgets.n(preview.nextTarget)) })
	local uid = flyers[flyerIndex]
	local rec = if uid then squishies()[uid] else nil
	if type(rec) == "table" then
		Widgets.setRaw(parts.flyerName, Widgets.speciesName(rec.s))
		Widgets.paintBlob(parts.blob, rec.s, true)
	else
		Widgets.setText(parts.flyerName, "common.empty")
		Widgets.paintBlob(parts.blob, nil, false)
	end
	Widgets.setDisabled(parts.prev, #flyers < 2)
	Widgets.setDisabled(parts.nextFlyer, #flyers < 2)
	-- « Filmer » : caché pour un Petit Splorch (aucun film) et sans capture vidéo
	parts.filmRow.Visible = kind ~= "petit" and not clipsUnavailable()
end

local function lightRing(alpha: number)
	local a = asc
	if a == nil then
		return
	end
	local lit = math.clamp(math.ceil(alpha * RING_DOTS - 1e-6), 0, RING_DOTS)
	for i, d in a.dots do
		local on = i <= lit
		local t = if on then 0 else RING_DIM
		if d.BackgroundTransparency ~= t then
			d.BackgroundTransparency = t
			local px = if on then RING_LIT else RING_DOT
			d.Size = UDim2.fromOffset(px, px)
		end
	end
end

local function refreshAscendPage()
	local a = asc
	if a == nil then
		return
	end
	local l = MetaView.ascendLines(UpgradeSnapshot.current(), metaCtx())
	lines = l
	setView(a.restart, l.restart)
	setView(a.speed, l.speed)
	local reason = ascendBlocker()
	lastReason = reason
	local key, vars = refusalText(reason)
	a.refusal.Visible = key ~= nil
	a.cond.Visible = key == nil
	a.bar.Visible = key == nil
	if key then
		Widgets.setText(a.refusal, key, vars)
		a.check.Visible = false
	else
		setView(a.cond, l.condition)
		local f = math.clamp(if l.fill == l.fill then l.fill else 0, 0, 1)
		a.fill.Size = UDim2.new(f, 0, 1, 0)
		a.check.Visible = l.met
	end
	a.hold.setEnabled(reason == "")
end

-- Une signature de ce qui change sans signal (fuite, retour au ranch, attribut AscendReady, file) : la
-- boucle de l'aperçu ouvert refait l'écran quand elle change (comme la v1.3 avec sa raison de refus)
local function signature(): string
	local reason = if currentTab == "ascend" then ascendBlocker() else blockerV2()
	return currentTab
		.. "|"
		.. reason
		.. "|"
		.. tostring(ascendAvailable())
		.. "|"
		.. tostring(preview.ready == true)
end

local function applyTab()
	local parts = v2
	if parts == nil then
		return
	end
	local onAscend = currentTab == "ascend"
	parts.tilesFrame.Visible = not detailsOpen
	parts.splorch.Visible = not onAscend and not detailsOpen
	parts.page.Visible = not onAscend and detailsOpen
	local a = asc
	if a then
		a.page.Visible = onAscend
	end
end

local function refreshV2()
	local parts = v2
	if parts == nil then
		return
	end
	preview = computePreview()
	updateFlyers()
	if ascendAvailable() and readySince == nil then
		readySince = Clock.now()
	end
	-- onglets : celui qui n'est plus prêt laisse la place à l'autre (aucun changement sans eux)
	local list = tabsNow()
	if tabBar == nil and #list >= 2 then
		-- barre pas encore construite (jamais écran ouvert) : l'onglet montré reste, l'autre attend
		-- l'ouverture suivante
		list = { if table.find(list, currentTab) then currentTab else list[1] }
	end
	shownTabs = list
	if #list > 0 and not table.find(list, currentTab) then
		currentTab = list[1]
		if detailsOpen and currentTab == "ascend" then
			detailsOpen = false
		end
		applyTab()
		if currentTab == "ascend" then
			noteAscendShown()
		end
	end
	local kind = if currentTab == "ascend" then "ascend" else (loopKind() or "splorch")
	setTitle(TITLE_KEYS[kind] or TITLE_KEYS.splorch)
	renderTabs(kind)
	renderTiles(kind)
	if currentTab == "ascend" then
		refreshAscendPage()
	else
		refreshSplorchPage(kind)
	end
	refreshDetails(kind)
	lastSig = signature()
end

-- =============================================================================================
-- Chemin de la v2.0 : maintiens et carte « Prêt à monter ? »
-- =============================================================================================

local function setDetailsV2(open: boolean)
	local parts = v2
	if parts == nil then
		return
	end
	detailsOpen = open and currentTab ~= "ascend"
	applyTab()
	renderTabs(if currentTab == "ascend" then "ascend" else (loopKind() or "splorch"))
	if detailsOpen then
		GuiService.SelectedObject = parts.ok
	elseif parts.details.Parent and currentTab ~= "ascend" and open == false and isOpen then
		GuiService.SelectedObject = parts.details
	end
end

local function onHoldDoneV2()
	local parts = v2
	if parts == nil then
		return
	end
	if blockerV2() ~= "" then
		Widgets.refuse(parts.hold.button)
		return
	end
	-- Petit Splorch : pas de film (aucune bannière, aucun clip ; GDD §4.27)
	local petit = loopKind() == "petit"
	local film = not petit and filmOn and not clipsUnavailable()
	if Widgets.send("GrandSplorch", film, flyers[flyerIndex]) then
		local me = Players.LocalPlayer
		if me then
			pcall(me.SetAttribute, me, "SplorchFilm", film)
		end
		closeAllPanels()
	end
end

-- Boutons de la carte grisés (garde) ou actifs
local function paintCard(active: boolean)
	local c = card
	if c == nil then
		return
	end
	cardActive = active
	for _, b in { c.later, c.yes } do
		b.BackgroundTransparency = if active then 0 else 0.55
		b:SetAttribute("Disabled", not active)
		local label = Widgets.buttonLabel(b)
		if label then
			label.TextTransparency = if active then 0 else 0.4
		end
	end
end

-- Garde de la carte : relâchement de ✕ vu, puis Balance.Ascend.ConfirmGuard s (comptées depuis le plus
-- tard de l'ouverture et du relâchement : un ✕ relâché puis rappuyé tout de suite ne confirme rien)
local function cardReady(now: number): boolean
	local released = cardReleasedAt
	return cardOpen and released ~= nil and now - math.max(cardOpenedAt, released) >= CONFIRM_GUARD
end

local function closeCard()
	if not cardOpen then
		return
	end
	cardOpen = false
	cardReleasedAt = nil
	local c = card
	if c then
		c.root.Visible = false
	end
	if FocusGuard.isOpen(CARD_WINDOW) then
		FocusGuard.closeNow(CARD_WINDOW)
	end
end

-- « Plus tard », ○ ou 20 s sans réponse : la carte ET l'aperçu se ferment (retour à l'entrée du rail)
local function decline()
	if not cardOpen then
		return
	end
	closeCard()
	noteDeclined()
	local n = nav
	if n and isOpen then
		n.back()
	end
end

-- « Oui » : JellyAscend(true) une seule fois, puis tout se ferme (aucun Feedback à l'entrée : la place et
-- l'attente viennent d'EventState, le HUD les montre)
local function confirm()
	local c = card
	if not cardOpen or ascendSent or c == nil then
		return
	end
	if ascendBlocker() ~= "" then
		-- état changé pendant la carte (fuite, sortie du ranch, file) : rien n'est envoyé, l'aperçu le dit
		Widgets.refuse(c.yes)
		closeCard()
		refreshV2()
		return
	end
	if Widgets.send("JellyAscend", true) then
		ascendSent = true
		AudioController.play("Click")
		closeCard()
		metric("ascendPreview", 2)
		closeAllPanels()
	else
		Widgets.refuse(c.yes)
	end
end

local function openCard()
	local c = card
	local a = asc
	if c == nil or a == nil or cardOpen or not isOpen then
		return
	end
	if ascendBlocker() ~= "" then
		Widgets.refuse(a.button)
		return
	end
	cardOpen = true
	cardOpenedAt = Clock.now()
	cardReleasedAt = nil
	paintCard(false)
	c.root.Visible = true
	if not Juice.reducedMotion() then
		Juice.popIn(c.panel)
	end
	AudioController.play("Whoosh")
	FocusGuard.open({
		name = CARD_WINDOW,
		root = c.root,
		blocking = true,
		default = function(): GuiObject?
			return c.yes -- critique M1 : focus d'office sur « Oui » (garde et relâchement gardés)
		end,
		onBack = function(): boolean
			decline()
			return true
		end,
		opener = a.button,
	})
end

-- Appui capté (✕, Entrée) sur la carte : jamais Activated ; jugé par l'InputGuard de FocusGuard puis par
-- la garde de la carte ; un appui commencé pendant la garde ne confirme jamais (même tenu ensuite)
local function onCardInput(input: InputObject)
	local c = card
	if not cardOpen or c == nil or not CONFIRM_KEYS[input.KeyCode] then
		return
	end
	local okGuard, clean = pcall(FocusGuard.notePress, input)
	if okGuard and clean ~= true then
		return
	end
	if not cardReady(Clock.now()) then
		return
	end
	local target: GuiObject? = GuiService.SelectedObject
	if target == nil and input.KeyCode ~= Enum.KeyCode.ButtonA then
		target = hovered
	end
	if target == c.yes then
		confirm()
	elseif target == c.later then
		AudioController.play("Back")
		decline()
	end
end

-- =============================================================================================
-- Chemin de la v2.0 : construction (une fois ; parties de l'Ascension et onglets à leur premier besoin)
-- =============================================================================================

-- Libellé « phrase » (UI/Text : agrandi par le moteur jusqu'à ×1,5, boîte prévue pour Largest)
local function sentence(props: Widgets.LabelProps): TextLabel
	local l = Widgets.label(props)
	Text.style(l, "sentence", props.textSize or Layout.Text.Body, { min = props.textSize, wrapped = true })
	return l
end

local function buildV2(c: Frame)
	local width = c.Size.X.Offset
	local height = c.Size.Y.Offset
	local root = Widgets.group(c, "V2", UDim2.fromOffset(width, height), UDim2.new())
	-- pages à deux niveaux pour le robot TvAudit (Splorch, Details, Ascend : un écran chacune)
	root:SetAttribute("TvLevels", true)
	local win = Widgets.label({
		parent = root,
		name = "Win",
		size = UDim2.fromOffset(width - 96, 56),
		position = UDim2.fromOffset(48, 20),
		key = "panel.splorch.win",
		textSize = 40,
	})
	-- 3 tuiles « Tu gagnes » (gabarit tuile de UI/UpgradeCard, dessins taillés pour les aperçus)
	local tilesFrame = Widgets.group(root, "Tiles", UDim2.fromOffset(width, TILE_H), UDim2.fromOffset(0, TOP))
	local x0 = math.floor((width - (3 * TILE_W + 2 * TILE_GAP)) / 2)
	local cards: { UpgradeCard.Card } = {}
	for i = 1, 3 do
		local t = UpgradeCard.new("tile", tilesFrame, { icons = MetaView.TILE_ICONS :: any })
		t.root.Name = "Tile" .. i
		t.root.Position = UDim2.fromOffset(x0 + (i - 1) * (TILE_W + TILE_GAP), 0)
		cards[i] = t
	end
	-- page du Grand Splorch / du Petit Splorch
	local sp = Widgets.group(root, "Splorch", UDim2.fromOffset(width, height), UDim2.new())
	local stage = Widgets.frame({
		parent = sp,
		name = "Stage",
		size = UDim2.fromOffset(240, 248),
		position = UDim2.fromOffset(48, ROW1),
		color = Widgets.Colors.Card,
	})
	local b = Widgets.blob(stage, "Flyer")
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -16)
	b.Size = UDim2.fromOffset(150, 132)
	local line = sentence({
		parent = sp,
		name = "Line",
		size = UDim2.fromOffset(width - 312 - 48, LINE_H),
		position = UDim2.fromOffset(312, ROW1),
		text = "",
		textSize = U.PreviewLine.text,
		xAlign = Enum.TextXAlignment.Left,
	})
	local spend = Widgets.button({
		parent = sp,
		name = "SpendFirst",
		size = UDim2.fromOffset(420, Layout.Button.MinHeight),
		position = UDim2.fromOffset(312, ROW1 + LINE_H + 8),
		key = "panel.splorch.spendFirst",
		nav = true,
		onActivate = function()
			-- écran Améliorations PAR-DESSUS l'aperçu, onglet Ranch, première ligne gardée payable ; ○ revient
			if nav then
				nav.open("Upgrades", "spendFirst")
			end
		end,
	})
	local box = Widgets.frame({
		parent = sp,
		name = "Refusal",
		size = UDim2.fromOffset(REFUSAL.w, REFUSAL.h),
		position = UDim2.fromOffset(312 + 420 + 24, ROW1 + LINE_H + 8),
		color = Widgets.Colors.Card,
	})
	box.Visible = false
	local refusal = sentence({
		parent = box,
		name = "Text",
		size = UDim2.new(1, -32, 1, -12),
		position = UDim2.fromOffset(16, 6),
		text = "",
		textSize = 36,
		color = Widgets.Colors.Warning,
	})
	local h = Widgets.hold({
		parent = sp,
		name = "Hold",
		size = UDim2.fromOffset(640, Layout.Button.MainHeight),
		position = UDim2.new(0.5, -170, 1, -16),
		anchor = Vector2.new(0.5, 1),
		key = "panel.splorch.hold",
		duration = Balance.Splorch.HoldConfirm,
		textSize = 40,
		onComplete = onHoldDoneV2,
		canStart = function(): boolean
			return blockerV2() == ""
		end,
	})
	local detailsB = Widgets.button({
		parent = sp,
		name = "Details",
		size = UDim2.fromOffset(300, Layout.Button.MainHeight),
		position = UDim2.new(0.5, 330, 1, -16),
		anchor = Vector2.new(0.5, 1),
		key = "panel.splorch.details",
		nav = true,
		onActivate = function()
			setDetailsV2(true)
		end,
	})
	-- page « Détails » : deux colonnes, prochain objectif, envol (flèches dessinées), « Filmer »
	local d = Widgets.group(root, "Details", UDim2.fromOffset(width, height), UDim2.new())
	d.Visible = false
	local colW = math.floor((width - 96 - Layout.Spacing.Normal) / 2)
	for i, spec in
		{
			{ "panel.splorch.keep", "panel.splorch.keep.list", Widgets.Colors.Success },
			{ "panel.splorch.reset", "panel.splorch.reset.list", Widgets.Colors.Danger },
		}
	do
		local f = Widgets.frame({
			parent = d,
			name = "Column" .. i,
			size = UDim2.fromOffset(colW, 232),
			position = UDim2.fromOffset(48 + (i - 1) * (colW + Layout.Spacing.Normal), TOP),
			color = Widgets.Colors.Card,
		})
		Widgets.label({
			parent = f,
			name = "Title",
			size = UDim2.new(1, -32, 0, 56),
			position = UDim2.fromOffset(16, 12),
			key = spec[1],
			textSize = 44,
			color = spec[3],
		})
		Widgets.label({
			parent = f,
			name = "List",
			size = UDim2.new(1, -32, 1, -88),
			position = UDim2.fromOffset(16, 76),
			key = spec[2],
			textSize = 36,
			wrapped = true,
		})
	end
	local nextLabel = Widgets.label({
		parent = d,
		name = "Next",
		size = UDim2.fromOffset(width - 96, 56),
		position = UDim2.fromOffset(48, TOP + 232 + 12),
		text = "",
		textSize = 40,
		color = Widgets.Colors.Gold,
	})
	local rowW = 100 + 16 + 340 + 16 + 100
	local fx = math.floor((width - rowW) / 2)
	Widgets.label({
		parent = d,
		name = "FlyerTitle",
		size = UDim2.fromOffset(rowW, 44),
		position = UDim2.fromOffset(fx, TOP + 232 + 76),
		key = "panel.splorch.flyer",
		textSize = 36,
	})
	local flyerY = TOP + 232 + 128
	local prev = Widgets.button({
		parent = d,
		name = "PrevFlyer",
		size = UDim2.fromOffset(100, Layout.Button.MinHeight),
		position = UDim2.fromOffset(fx, flyerY),
		onActivate = function()
			if #flyers > 1 then
				flyerIndex = ((flyerIndex - 2) % #flyers) + 1
				refreshV2()
			end
		end,
	})
	arrow(prev, true)
	local flyerName = Widgets.label({
		parent = d,
		name = "FlyerName",
		size = UDim2.fromOffset(340, Layout.Button.MinHeight),
		position = UDim2.fromOffset(fx + 116, flyerY),
		text = "",
		textSize = 40,
	})
	local nextFlyer = Widgets.button({
		parent = d,
		name = "NextFlyer",
		size = UDim2.fromOffset(100, Layout.Button.MinHeight),
		position = UDim2.fromOffset(fx + 472, flyerY),
		onActivate = function()
			if #flyers > 1 then
				flyerIndex = (flyerIndex % #flyers) + 1
				refreshV2()
			end
		end,
	})
	arrow(nextFlyer, false)
	local filmW = 720
	local fr = Widgets.group(
		d,
		"Film",
		UDim2.fromOffset(filmW, Layout.Panel.toggle.h),
		UDim2.fromOffset(math.floor((width - filmW) / 2), flyerY + Layout.Button.MinHeight + 16)
	)
	local toggle = Widgets.toggle(
		fr,
		"Toggle",
		UDim2.fromScale(0, 0.5),
		Vector2.new(0, 0.5),
		function(v: boolean)
			filmOn = v
		end
	)
	Widgets.label({
		parent = fr,
		name = "Label",
		size = UDim2.new(1, -(Layout.Panel.toggle.w + 24), 1, 0),
		position = UDim2.fromOffset(Layout.Panel.toggle.w + 24, 0),
		key = "panel.splorch.film",
		textSize = 32,
		xAlign = Enum.TextXAlignment.Left,
	})
	local ok = Widgets.button({
		parent = d,
		name = "Ok",
		size = UDim2.fromOffset(360, Layout.Button.MainHeight),
		position = UDim2.new(0.5, 0, 1, -16),
		anchor = Vector2.new(0.5, 1),
		key = "common.back",
		onActivate = function()
			setDetailsV2(false)
		end,
	})
	v2 = {
		root = root,
		win = win,
		tiles = cards,
		tilesFrame = tilesFrame,
		splorch = sp,
		stage = stage,
		blob = b,
		line = line,
		spend = spend,
		refusalBox = box,
		refusal = refusal,
		hold = h,
		holdLabel = Widgets.buttonLabel(h.button),
		details = detailsB,
		page = d,
		next = nextLabel,
		flyerName = flyerName,
		prev = prev,
		nextFlyer = nextFlyer,
		filmRow = fr,
		filmToggle = toggle,
		ok = ok,
	}
	-- signaux (réseau seulement, aucun travail par image) : instantané, interrupteurs, EventState
	UpgradeSnapshot.Changed:Connect(function()
		if isOpen and path == "v2" then
			refreshV2()
		end
	end)
	MetaFlags.Changed:Connect(function()
		if isOpen and path == "v2" then
			refreshV2()
		end
	end)
	WorldStateController.EventChanged:Connect(function()
		if not isOpen or path ~= "v2" then
			return
		end
		-- début de MON spectacle (Grand Splorch ou Jelly Ascend) : l'aperçu se ferme
		if MetaFlags.myPrestige() == "show" then
			closeAllPanels()
			return
		end
		refreshV2()
	end)
end

-- Onglet ascend : lignes, 6 icônes « gardé », condition, maintien de 3 s (construit à son premier besoin)
local function buildAscend(c: Frame)
	local parts = v2 :: V2Parts
	local width = c.Size.X.Offset
	local page = Widgets.group(parts.root, "Ascend", UDim2.fromOffset(width, c.Size.Y.Offset), UDim2.new())
	page.Visible = false
	local lineW = U.PreviewLine.w
	local lx = math.floor((width - lineW) / 2)
	local restart = sentence({
		parent = page,
		name = "Restart",
		size = UDim2.fromOffset(lineW, LINE_H),
		position = UDim2.fromOffset(lx, ROW1),
		text = "",
		textSize = U.PreviewLine.text,
	})
	local speed = sentence({
		parent = page,
		name = "Speed",
		size = UDim2.fromOffset(lineW, SPEED_H),
		position = UDim2.fromOffset(lx, ROW1 + LINE_H),
		text = "",
		textSize = 32,
		color = Widgets.Colors.Gold,
	})
	-- « Tout le reste est gardé » : 6 icônes dessinées et leur nom
	local kept = Widgets.group(page, "Kept", UDim2.fromOffset(width, 56), UDim2.fromOffset(0, KEPT_Y))
	local kx = math.floor((width - (#KEPT * KEPT_CELL + (#KEPT - 1) * 16)) / 2)
	for i, k in KEPT do
		local cell = Widgets.group(
			kept,
			"Kept" .. i,
			UDim2.fromOffset(KEPT_CELL, 56),
			UDim2.fromOffset(kx + (i - 1) * (KEPT_CELL + 16), 0)
		)
		local icon = Icons.canvas(cell, KEPT_ICON, { k.icon }, "Icon")
		icon.Position = UDim2.fromOffset(0, 4)
		Icons.draw(icon, k.icon, k.color)
		Widgets.label({
			parent = cell,
			name = "Label",
			size = UDim2.fromOffset(KEPT_CELL - KEPT_ICON - 8, 56),
			position = UDim2.fromOffset(KEPT_ICON + 8, 0),
			key = k.key,
			textSize = Layout.Text.Min,
			xAlign = Enum.TextXAlignment.Left,
		})
	end
	-- condition (texte, barre, coche) ou refus, dans la même boîte de 600 × 112
	local rowW = REFUSAL.w + 24 + HOLD_W
	local rx = math.floor((width - rowW) / 2)
	local condBox = Widgets.frame({
		parent = page,
		name = "Condition",
		size = UDim2.fromOffset(REFUSAL.w, HOLD_H),
		position = UDim2.fromOffset(rx, ASCEND_ROW),
		color = Widgets.Colors.Card,
	})
	local cond = Widgets.label({
		parent = condBox,
		name = "Text",
		size = UDim2.fromOffset(REFUSAL.w - 32 - 56, 48),
		position = UDim2.fromOffset(16, 14),
		text = "",
		textSize = 36,
		xAlign = Enum.TextXAlignment.Left,
	})
	local check = Icons.canvas(condBox, 48, { "check" }, "Check")
	check.AnchorPoint = Vector2.new(1, 0)
	check.Position = UDim2.new(1, -16, 0, 14)
	Icons.draw(check, "check")
	local bar = Widgets.frame({
		parent = condBox,
		name = "Bar",
		size = UDim2.fromOffset(REFUSAL.w - 32, 16),
		position = UDim2.fromOffset(16, 76),
		color = Widgets.Colors.Locked,
		stroke = false,
		corner = UDim.new(0.5, 0),
	})
	local fill = Widgets.frame({
		parent = bar,
		name = "Fill",
		size = UDim2.fromScale(0, 1),
		color = Widgets.Colors.Success,
		stroke = false,
		corner = UDim.new(0.5, 0),
	})
	local refusal = sentence({
		parent = condBox,
		name = "Refusal",
		size = UDim2.new(1, -32, 1, -8),
		position = UDim2.fromOffset(16, 4),
		text = "",
		textSize = 36,
		color = Widgets.Colors.Warning,
	})
	refusal.Visible = false
	-- maintien de ✕ 3 s : anneau de 12 points autour du glyphe de 64 px de l'appareil
	local button = Widgets.button({
		parent = page,
		name = "Hold",
		size = UDim2.fromOffset(HOLD_W, HOLD_H),
		position = UDim2.fromOffset(rx + REFUSAL.w + 24, ASCEND_ROW),
		color = Widgets.Colors.Pink,
		sound = "",
	})
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Active = false
	ring.Selectable = false
	ring.ZIndex = button.ZIndex + 1
	ring.Parent = button
	local dots: { Frame } = {}
	for i = 1, RING_DOTS do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = Widgets.Colors.Text
		dot.BackgroundTransparency = RING_DIM
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(RING_DOT, RING_DOT)
		dot.ZIndex = button.ZIndex + 1
		dot.Active = false
		dot.Selectable = false
		Widgets.corner(dot, UDim.new(0.5, 0))
		dot.Parent = ring
		dots[i] = dot
	end
	local glyph = Widgets.glyph(
		button,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.Return,
		HOLD_GLYPH,
		UDim2.fromOffset(16 + RING_RY, HOLD_H / 2),
		Vector2.new(0.5, 0.5)
	)
	local label = Widgets.label({
		parent = button,
		name = "Label",
		size = UDim2.fromOffset(HOLD_W - 140, HOLD_H - 16),
		position = UDim2.fromOffset(124, 8),
		key = "ascend.hold",
		textSize = Layout.Text.Button,
		xAlign = Enum.TextXAlignment.Left,
		zIndex = button.ZIndex + 2,
	})
	-- l'anneau suit la largeur RÉELLE du glyphe (touche « Entrée » plus large qu'un rond de manette)
	local gframe = glyph.frame :: GuiObject
	local function place()
		local rxRing = math.max(RING_RY, math.floor(gframe.Size.X.Offset / 2) + 12)
		local cx = 16 + rxRing
		gframe.Position = UDim2.fromOffset(cx, HOLD_H / 2)
		ring.Position = UDim2.fromOffset(cx, HOLD_H / 2)
		ring.Size = UDim2.fromOffset(2 * rxRing + RING_LIT, 2 * RING_RY + RING_LIT)
		for i, dot in dots do
			local t = (i - 1) * 2 * math.pi / RING_DOTS
			dot.Position = UDim2.new(
				0.5,
				math.floor(math.sin(t) * rxRing + 0.5),
				0.5,
				-math.floor(math.cos(t) * RING_RY + 0.5)
			)
		end
		local lx2 = cx + rxRing + 20
		label.Position = UDim2.fromOffset(lx2, 8)
		label.Size = UDim2.fromOffset(HOLD_W - lx2 - 16, HOLD_H - 16)
	end
	place()
	gframe:GetPropertyChangedSignal("Size"):Connect(place)
	local holdObj = Widgets.holdOn(button, {
		duration = Balance.Ascend.HoldSeconds,
		onComplete = openCard,
		onProgress = lightRing,
		onEarly = function()
			AudioController.play("Bump")
		end,
		canStart = function(): boolean
			return ascendBlocker() == ""
		end,
	})
	asc = {
		page = page,
		restart = restart,
		speed = speed,
		condBox = condBox,
		cond = cond,
		check = check,
		bar = bar,
		fill = fill,
		refusal = refusal,
		button = button,
		hold = holdObj,
		dots = dots,
	}
	-- carte « Prêt à monter ? » : fenêtre FocusGuard au-dessus de l'aperçu (voile, titre, 2 boutons)
	local win = c.Parent
	local cardParent: Instance = if win and win:IsA("GuiObject") then win else c
	local cardRoot = Instance.new("Frame")
	cardRoot.Name = CARD_WINDOW
	cardRoot.Size = UDim2.fromScale(1, 1)
	cardRoot.BackgroundColor3 = Color3.new(0, 0, 0)
	cardRoot.BackgroundTransparency = 0.45
	cardRoot.BorderSizePixel = 0
	cardRoot.ZIndex = 30
	cardRoot.Visible = false
	cardRoot.Parent = cardParent
	local panel = Widgets.frame({
		parent = cardRoot,
		name = "Card",
		size = UDim2.fromOffset(CARD_W, CARD_H),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Widgets.Colors.Panel,
		corner = Widgets.CORNER_LARGE,
		gradient = true,
		zIndex = 31,
	})
	local title = Widgets.label({
		parent = panel,
		name = "Title",
		size = UDim2.fromOffset(CARD_W - 64, 80),
		position = UDim2.fromOffset(32, 48),
		key = "ascend.confirm",
		textSize = Layout.Text.Title,
		zIndex = 32,
	})
	local bx = math.floor((CARD_W - (2 * CONFIRM.w + 40)) / 2)
	local by = CARD_H - 48 - CONFIRM.h
	local later = Widgets.button({
		parent = panel,
		name = "Later",
		size = UDim2.fromOffset(CONFIRM.w, CONFIRM.h),
		position = UDim2.fromOffset(bx, by),
		key = "ascend.later",
		textSize = CONFIRM.text,
		color = Widgets.Colors.CardLight,
		sound = "",
		zIndex = 32,
	})
	local yes = Widgets.button({
		parent = panel,
		name = "Yes",
		size = UDim2.fromOffset(CONFIRM.w, CONFIRM.h),
		position = UDim2.fromOffset(bx + CONFIRM.w + 40, by),
		key = "ascend.yes",
		textSize = CONFIRM.text,
		color = Widgets.Colors.Pink,
		sound = "",
		zIndex = 32,
	})
	card = { root = cardRoot, panel = panel, title = title, later = later, yes = yes }
	-- souris : clic sur un bouton actif ; clavier-souris : Entrée sur le bouton survolé
	for _, btn in { later, yes } do
		btn.MouseEnter:Connect(function()
			hovered = btn
		end)
		btn.MouseLeave:Connect(function()
			if hovered == btn then
				hovered = nil
			end
		end)
		btn.MouseButton1Down:Connect(function()
			if not cardOpen or not cardReady(Clock.now()) or not Widgets.confirmed() then
				return
			end
			if btn == yes then
				confirm()
			else
				decline()
			end
		end)
	end
	UserInputService.InputBegan:Connect(onCardInput)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			cardOpen
			and cardReleasedAt == nil
			and (CONFIRM_KEYS[input.KeyCode] or input.UserInputType == Enum.UserInputType.MouseButton1)
		then
			cardReleasedAt = Clock.now()
		end
	end)
end

-- Barre d'onglets « Grand Splorch » / « Jelly Ascend » (L1 / R1), construite à sa première utilité
local function buildTabs()
	local parts = v2 :: V2Parts
	tabBar = Widgets.tabBar(parts.root, {
		{ id = "splorch", key = "panel.splorch.tab.splorch" },
		{ id = "ascend", key = "panel.splorch.tab.ascend" },
	}, function(id: string)
		SplorchPreview.setTab(id)
	end)
end

-- =============================================================================================
-- Animation, boucle de l'aperçu ouvert
-- =============================================================================================

local function stepAnimation()
	local b = if path == "v2" and v2 then (v2 :: V2Parts).blob else blob
	if b == nil then
		return
	end
	local scale = Juice.scaleOf(b)
	if Juice.reducedMotion() then
		scale.Scale = 1
		return
	end
	local t = (Clock.now() - animStart) % ANIM_PERIOD
	local s
	if t < 0.6 then
		s = 1 - 0.65 * (t / 0.6) -- redevient petit
	elseif t < 1.0 then
		local a = (t - 0.6) / 0.4
		s = 0.35 + 0.65 * (1 - (1 - a) ^ 3) -- regrandit très vite
	else
		s = 1
	end
	scale.Scale = s
end

local function stepV2()
	local now = Clock.now()
	if cardOpen then
		if now - cardOpenedAt >= CONFIRM_TIMEOUT or now < cardOpenedAt then
			decline()
			return
		end
		local ready = cardReady(now)
		if ready ~= cardActive then
			paintCard(ready)
		end
		return
	end
	local parts = v2
	local a = asc
	local holding = (parts ~= nil and parts.hold.holding()) or (a ~= nil and a.hold.holding())
	if not holding and signature() ~= lastSig then
		refreshV2()
	end
end

local function step()
	stepAnimation()
	if not isOpen then
		return
	end
	if path == "v2" then
		stepV2()
		return
	end
	-- fuite qui finit, joueur qui rentre au ranch : l'état du bouton suit (une fois par image,
	-- seulement panneau ouvert)
	local h = hold
	if h and not h.holding() and blocker() ~= lastReason then
		refreshV13()
	end
end

local function refresh()
	if path == "v2" then
		refreshV2()
	else
		refreshV13()
	end
end

-- Montre les parties du chemin choisi, cache celles de l'autre (construites lors d'un passage précédent)
local function showPath()
	local parts = v2
	if parts then
		parts.root.Visible = path == "v2"
	end
	if path == "v13" then
		if titleKey ~= TITLE_KEYS.splorch then
			setTitle(TITLE_KEYS.splorch)
		end
	else
		if main then
			main.Visible = false
		end
		if details then
			details.Visible = false
		end
	end
end

-- =============================================================================================
-- Interface du panneau (PanelController)
-- =============================================================================================

-- Construit le contenu une seule fois dans le cadre du panneau (chemin du moment : l'autre se construit
-- à l'ouverture qui en a besoin)
function SplorchPreview.build(c: Frame)
	container = c
	if UpgradeSnapshot.available() then
		buildV2(c)
	else
		buildV13(c)
	end
	Widgets.watch({ "R", "growth", "squishies", "coins", "pot", "settings" }, function()
		if isOpen then
			refresh()
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("ClipsUnavailable"):Connect(function()
			if isOpen then
				refresh()
			end
		end)
	end
end

-- Affiche le panneau (v2.0 : onglet demandé, « ascend » seulement quand la Jelly Ascend est prête)
function SplorchPreview.open(tab: string?)
	local c = container
	if c == nil then
		return
	end
	local v2Path = UpgradeSnapshot.available()
	-- chemin changé depuis la construction : ce qui manque est construit maintenant (panneau pas encore
	-- montré), jamais écran ouvert
	if v2Path and v2 == nil then
		buildV2(c)
	elseif not v2Path and not v13Built then
		buildV13(c)
	end
	path = if v2Path then "v2" else "v13"
	isOpen = true
	flyerIndex = 1
	flyers = {}
	filmOn = Prefs.get("clips") ~= false
	showPath()
	if path == "v13" then
		if filmToggle then
			filmToggle.set(filmOn)
		end
		setDetails(false)
		refresh()
	else
		local parts = v2 :: V2Parts
		parts.filmToggle.set(filmOn)
		ascendShown = false
		ascendSent = false
		declineNoted = false
		detailsOpen = false
		preview = computePreview()
		-- parties de l'Ascension et onglets : à leur premier besoin, avant de montrer le panneau
		if
			asc == nil
			and MetaFlags.on("JellyAscend")
			and MetaFlags.v2Profile()
			and MetaFlags.attr("AscendReady") == true
		then
			buildAscend(c)
		end
		local list = tabsNow()
		if #list >= 2 and tabBar == nil then
			buildTabs()
		end
		-- « ascend » demandé (rail, puce du HUD, carte Conseillé) et prête, ou seule prête ; sinon la boucle
		local hasAscend = table.find(list, "ascend") ~= nil
		local wantsAscend = hasAscend and (tab == "ascend" or table.find(list, "splorch") == nil)
		currentTab = if wantsAscend then "ascend" else "splorch"
		applyTab()
		refresh()
		if currentTab == "ascend" then
			noteAscendShown()
		end
	end
	animStart = Clock.now()
	if anim == nil then
		anim = RunService.Heartbeat:Connect(step)
	end
end

-- Cache le panneau
function SplorchPreview.close()
	isOpen = false
	local c = anim
	anim = nil
	if c then
		c:Disconnect()
	end
	if hold then
		hold.cancel()
	end
	local parts = v2
	if parts then
		parts.hold.cancel()
	end
	local a = asc
	if a then
		a.hold.cancel()
		lightRing(0)
	end
	closeCard()
	noteDeclined()
	detailsOpen = false
end

-- Onglets : aucun (v1.3) ; v2.0 : « splorch » et « ascend » quand les deux sont prêts, sinon le seul
function SplorchPreview.tabs(): { string }
	if path ~= "v2" or v2 == nil then
		return {}
	end
	return table.clone(shownTabs)
end

function SplorchPreview.setTab(tab: string)
	if path ~= "v2" or v2 == nil or not isOpen or type(tab) ~= "string" then
		return
	end
	if not table.find(shownTabs, tab) or tab == currentTab then
		return
	end
	if cardOpen then
		return
	end
	currentTab = tab
	detailsOpen = false
	applyTab()
	refreshV2()
	if tab == "ascend" then
		noteAscendShown()
	end
end

function SplorchPreview.currentTab(): string
	if path ~= "v2" then
		return ""
	end
	return currentTab
end

-- Sélection par défaut : le bouton « Maintenir » (glyphe ✕) de l'onglet montré
function SplorchPreview.defaultSelection(): GuiObject?
	if path == "v2" then
		local parts = v2
		if parts == nil then
			return nil
		end
		if detailsOpen then
			return parts.ok
		end
		local a = asc
		if currentTab == "ascend" and a then
			return a.button
		end
		return parts.hold.button
	end
	if detailsOpen then
		return detailsOk
	end
	return if hold then hold.button else nil
end

-- ○ : ferme les Détails (vrai), sinon retour au menu (faux)
function SplorchPreview.onBack(): boolean
	if detailsOpen then
		if path == "v2" then
			setDetailsV2(false)
		else
			setDetails(false)
		end
		return true
	end
	return false
end

-- Entrée du menu : seulement quand le Grand Splorch est prêt (plus gros ≥ objectif)
function SplorchPreview.visible(): boolean
	return computePreview().ready == true
end

-- Navigateur fourni par PanelController AVANT build
function SplorchPreview.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function SplorchPreview.refresh()
	refresh()
end

-- État affiché (specs)
function SplorchPreview._state(): {
	flyer: string?,
	film: boolean,
	blocker: string,
	details: boolean,
	path: string,
	tab: string,
	tabs: { string },
	card: boolean,
	cardActive: boolean,
	ascend: string,
}
	return {
		flyer = flyers[flyerIndex],
		film = filmOn,
		blocker = if path == "v2" then blockerV2() else blocker(),
		details = detailsOpen,
		path = path,
		tab = currentTab,
		tabs = table.clone(shownTabs),
		card = cardOpen,
		cardActive = cardActive,
		ascend = if asc ~= nil then ascendBlocker() else "",
	}
end

-- Parties du chemin v2.0 (specs, outil d'écrans) ; nil avant leur construction
function SplorchPreview._v2(): { [string]: any }?
	local parts = v2
	if parts == nil then
		return nil
	end
	local a = asc
	local c = card
	return {
		root = parts.root,
		tiles = { parts.tiles[1].root, parts.tiles[2].root, parts.tiles[3].root },
		line = parts.line,
		spend = parts.spend,
		refusal = parts.refusal,
		refusalBox = parts.refusalBox,
		hold = parts.hold.button,
		details = parts.details,
		page = parts.page,
		film = parts.filmRow,
		prev = parts.prev,
		nextFlyer = parts.nextFlyer,
		ok = parts.ok,
		ascend = if a then a.page else nil,
		ascendHold = if a then a.button else nil,
		restart = if a then a.restart else nil,
		speed = if a then a.speed else nil,
		condition = if a then a.cond else nil,
		check = if a then a.check else nil,
		ascendRefusal = if a then a.refusal else nil,
		card = if c then c.root else nil,
		yes = if c then c.yes else nil,
		later = if c then c.later else nil,
		tabs = if tabBar then (tabBar :: Widgets.TabBar).frame else nil,
	}
end

return SplorchPreview
