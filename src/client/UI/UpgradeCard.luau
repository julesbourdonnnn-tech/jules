--!strict
-- UI/UpgradeCard (lot B2, docs/04 §27.7, §27.8 ; GDD v2.0 §10.7.4 à §10.7.8, §10.8 règles 2, 7, 8, 10, 11,
-- 14, 18, 20) : LE composant unique de l'écran Améliorations, en 3 gabarits.
--
--   local card = UpgradeCard.new("card" | "row" | "tile", parent, opts?)
--   card:set(state, view)       -- état (7) et vue (Hud/UpgradeView) : AUCUNE instance créée
--   card:feedback(text?)        -- retour chiffré dans la ligne même (« +7 niveaux · -1,2 M »), nil : rien
--   card.root                   -- bouton sélectionnable (carte, ligne) ou cadre (tuile)
--
--   * carte 432 × 528 (onglet Conseillé ; pile fixe du GDD §10.7.4 : icône 80, nom 36 px, palier 28 px,
--     niveau 32 px, avant → après sur 2 lignes de 32 px, raison 28 px, prix 48 + 40 px et barre
--     « ce que j'ai / ce qu'il faut » de 400 × 8, dessin du bouton « Acheter » ou état) ; ombre ;
--   * ligne 1 328 × 112 (onglets Ranch, Plopettes, Atelier ; colonnes fixes de Layout.Upgrades.Columns :
--     icône 16/80, texte 112/540, niveau 668/140, prix 824/240, état 1080/232) ; jamais d'ombre ;
--   * tuile 400 × 300 (aperçus des renaissances, lot B3) : icône 120, titre sur 2 lignes de 36 px,
--     valeur 40 px, marges 16.
-- Tailles fixes, toutes lues dans Config/Layout.Upgrades (règle 10) ; places réservées aux pires
-- valeurs : « 1,00e300 » et « 99,9Nvvg » (prix, 40 px), « 40/40 » (niveau, 40 px). Les 7 états sont un
-- dessin (Hud/Icons) ET un mot, jamais la couleur seule (règle 11 et GDD §10.7.6). La flèche entre
-- l'avant et l'après est dessinée (règle 18). Tout texte passe par UI/Text (Text.set d'une clé de la
-- vue, ou Text.raw d'une chaîne de UI/Format / Logic/BigNumber faite par la vue). Le cadre de focus est
-- celui de FocusGuard, dessiné à l'intérieur ; l'attribut FocusId porte l'identifiant de la ligne.
-- Tout est construit par new() ; set() ne fait que poser des textes, des tailles, des couleurs et des
-- visibilités (règles 2 et 20 : aucune instance créée ni détruite écran ouvert). Les dessins d'une
-- carte ou d'une ligne sont des toiles de Hud/Icons, taillées par new() pour les sortes à montrer
-- (opts.icons, opts.badges, opts.currencies : toutes les sortes possibles par défaut).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Layout = require(Shared.Config.Layout)
local Upgrades = require(Shared.Config.Upgrades)

local UI = script.Parent
local Theme = require(UI.Theme)
local Text = require(UI.Text)
local Glyph = require(UI.Glyph)
local FocusGuard = require(UI.FocusGuard)
local Icons = require(UI.Hud.Icons)
local UpgradeView = require(UI.Hud.UpgradeView)

export type Template = "card" | "row" | "tile"
export type Options = {
	icons: { string }?, -- dessins de famille que cette carte montrera (toutes les lignes par défaut)
	badges: { string }?, -- coins de l'icône : "loop", "infinity", "star" (tous par défaut)
	currencies: { string }?, -- "coin", "confetti" (les deux par défaut)
}

type Parts = {
	icon: Frame,
	badge: Frame?,
	name: TextLabel,
	tier: TextLabel?,
	levelA: TextLabel?,
	levelArrow: Frame?,
	levelB: TextLabel?,
	effectLabel: TextLabel?,
	before: TextLabel?,
	effectArrow: Frame?,
	after: TextLabel?,
	reason: TextLabel?,
	levelBar: Frame?,
	levelFill: Frame?,
	levelGrey: Frame?,
	currency: Frame?,
	price: TextLabel?,
	priceBar: Frame?,
	priceFill: Frame?,
	pill: Frame?,
	glyph: Glyph.Handle?,
	stateIcon: Frame?,
	word: TextLabel?,
}

type CardData = {
	template: Template,
	root: GuiObject,
	parts: Parts,
	state: string,
	view: UpgradeView.View?, -- dernière vue posée (retour chiffré : même vue)
	fb: UpgradeView.Text?, -- retour chiffré en cours (nil : aucun)
}

local UpgradeCard = {}
UpgradeCard.__index = UpgradeCard

export type Card = typeof(setmetatable({} :: CardData, UpgradeCard))

local U = Layout.Upgrades
local COL = U.Columns
local CARD_W, CARD_H = U.Card.w, U.Card.h
local ROW_W, ROW_H = U.Row.w, U.Row.h
local TILE_W, TILE_H = U.Tile.w, U.Tile.h
local MARGIN = U.Tile.margin -- 16 : marge intérieure des 3 gabarits
local CARD_IN = CARD_W - 2 * MARGIN -- 400 : largeur utile d'une carte

-- Couleurs (charte des panneaux, GDD §10.1)
local COLORS = {
	card = Color3.fromRGB(58, 50, 96),
	row = Color3.fromRGB(58, 50, 96),
	stroke = Color3.fromRGB(30, 25, 60),
	text = Theme.Colors.Text,
	dim = Theme.Colors.TextDim,
	grey = Color3.fromRGB(140, 134, 170),
	barBack = Color3.fromRGB(34, 29, 60),
	barFill = Theme.Colors.Success,
	barNeed = Theme.Colors.Warning,
	barGrey = Color3.fromRGB(90, 86, 110),
	buy = Color3.fromRGB(64, 160, 96),
}

-- Couleur du mot et du dessin de chaque état (avec le dessin et le mot : jamais la couleur seule)
local STATE_COLORS: { [string]: Color3 } = {
	ready = Theme.Colors.Success,
	need = Theme.Colors.Warning,
	max = Theme.Colors.Gold,
	locked = Color3.fromRGB(200, 196, 225),
	loopCap = Theme.Colors.Primary,
	busy = Theme.Colors.Warning,
	retry = Theme.Colors.Warning,
}

-- Mot de chaque état quand l'écran impose un autre état que celui de la vue (En cours, Réessaie)
local STATE_WORDS: { [string]: string } = {
	ready = "upgrades.state.ready",
	need = "upgrades.state.need",
	max = "upgrades.state.max",
	busy = "upgrades.state.busy",
	retry = "upgrades.state.retry",
}

local STATE_KINDS = { "check", "hourglass", "star", "lock", "loop", "retry" }
local CURRENCY_KIND: { [string]: string } = { coins = "coin", confetti = "confetti" }
local BADGE_KIND: { [string]: string } = { loop = "loop", kept = "infinity", advised = "star" }
local DASH = "—" -- prix d'une ligne au maximum (dans les deux polices, Contract_glyphs)

-- Tous les dessins de ligne de Config/Upgrades (familles, Atelier, « Pour le plaisir », lecture seule)
local LINE_ICONS: { string } = {}
do
	local seen: { [string]: boolean } = {}
	local function add(kind: string)
		if not seen[kind] and Icons.has(kind) then
			seen[kind] = true
			table.insert(LINE_ICONS, kind)
		end
	end
	for _, def in Upgrades.Families do
		add(def.icon)
	end
	for _, row in Upgrades.WorkshopRows do
		add(row.icon)
	end
	for _, line in Upgrades.Fun do
		add(line.icon)
	end
	for _, def in Upgrades.ReadOnly do
		add(def.icon)
	end
end
UpgradeCard.LINE_ICONS = table.freeze(LINE_ICONS)

-- Dessins des familles de pièces (cartes du Conseillé : UpgradeAdvisor ne choisit qu'elles)
local COIN_ICONS: { string } = {}
for _, def in Upgrades.Families do
	if def.currency == "coins" and Icons.has(def.icon) and not table.find(COIN_ICONS, def.icon) then
		table.insert(COIN_ICONS, def.icon)
	end
end
UpgradeCard.COIN_ICONS = table.freeze(COIN_ICONS)

-- =============================================================================================
-- Construction (new() seulement)
-- =============================================================================================

local function frame(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	z: number
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.ZIndex = z
	f.Active = false
	f.Selectable = false
	f.Parent = parent
	return f
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- Texte à sa taille dessinée (UI/Text, sorte "label", borné par son mot le plus long)
local function label(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	size: number,
	align: Enum.TextXAlignment,
	color: Color3,
	z: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.FontFace = Theme.Fonts.Title
	l.TextColor3 = color
	l.TextXAlignment = align
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.AutoLocalize = false
	l.ZIndex = z
	Text.style(l, "label", size, { words = true })
	Text.raw(l, "")
	l.Parent = parent
	return l
end

local function canvas(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	size: number,
	kinds: { string },
	z: number
): Frame
	local c = Icons.canvas(nil, size, kinds, name)
	c.Position = UDim2.fromOffset(x, y)
	c.ZIndex = z
	c.Parent = parent
	return c
end

local function kindsOf(list: { string }?, map: { [string]: string }?, default: { string }): { string }
	if list == nil then
		return default
	end
	local out: { string } = {}
	for _, k in list do
		local kind = if map then map[k] or k else k
		if Icons.has(kind) and not table.find(out, kind) then
			table.insert(out, kind)
		end
	end
	return out
end

-- Racine : bouton sélectionnable (carte, ligne : le maintien de 0,6 s du lot B2 s'y pose) ou cadre
local function rootOf(template: Template, parent: Instance?): GuiObject
	local w, h = CARD_W, CARD_H
	if template == "row" then
		w, h = ROW_W, ROW_H
	elseif template == "tile" then
		w, h = TILE_W, TILE_H
	end
	local root: GuiObject
	if template == "tile" then
		local f = Instance.new("Frame")
		f.Selectable = false
		root = f
	else
		local b = Instance.new("TextButton")
		Text.raw(b, "")
		b.AutoButtonColor = false
		b.AutoLocalize = false
		b.Selectable = true
		b.SelectionImageObject = FocusGuard.selectionImage()
		root = b
	end
	root.Name = if template == "card"
		then "UpgradeCard"
		elseif template == "row" then "UpgradeRow"
		else "UpgradeTile"
	root.BorderSizePixel = 0
	root.BackgroundColor3 = if template == "row" then COLORS.row else COLORS.card
	root.Size = UDim2.fromOffset(w, h)
	root.ZIndex = 3
	root:SetAttribute("Template", template)
	corner(root, Layout.Corner.Max)
	if template ~= "row" then
		local s = Instance.new("UIStroke")
		s.Color = COLORS.stroke
		s.Thickness = Layout.Stroke
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = root
	end
	if parent then
		root.Parent = parent
	end
	return root
end

local function buildCard(root: GuiObject, o: Options): Parts
	local x0 = MARGIN
	local half = (CARD_IN - 64) / 2 -- 168 : valeur avant / après de part et d'autre de la flèche (64)
	local arrowX = x0 + half + (64 - 32) / 2
	local p: Parts = {
		icon = canvas(
			root,
			"Icon",
			(CARD_W - U.Card.icon) / 2,
			16,
			U.Card.icon,
			kindsOf(o.icons, nil, LINE_ICONS),
			5
		),
		name = label(
			root,
			"Name",
			x0,
			104,
			CARD_IN,
			48,
			U.Card.title,
			Enum.TextXAlignment.Center,
			COLORS.text,
			5
		),
		tier = label(root, "Tier", x0, 152, CARD_IN, 36, 28, Enum.TextXAlignment.Center, COLORS.dim, 5),
		levelA = label(root, "LevelA", x0, 192, half, 40, 32, Enum.TextXAlignment.Right, COLORS.text, 5),
		levelArrow = canvas(root, "LevelArrow", arrowX, 196, 32, { "arrowRight" }, 5),
		levelB = label(
			root,
			"LevelB",
			x0 + half + 64,
			192,
			half,
			40,
			32,
			Enum.TextXAlignment.Left,
			COLORS.text,
			5
		),
		effectLabel = label(
			root,
			"EffectLabel",
			x0,
			240,
			CARD_IN,
			40,
			32,
			Enum.TextXAlignment.Center,
			COLORS.dim,
			5
		),
		before = label(root, "Before", x0, 280, half, 40, 32, Enum.TextXAlignment.Right, COLORS.text, 5),
		effectArrow = canvas(root, "EffectArrow", arrowX, 284, 32, { "arrowRight" }, 5),
		after = label(
			root,
			"After",
			x0 + half + 64,
			280,
			half,
			40,
			32,
			Enum.TextXAlignment.Left,
			COLORS.text,
			5
		),
		reason = label(root, "Reason", x0, 328, CARD_IN, 36, 28, Enum.TextXAlignment.Center, COLORS.dim, 5),
		currency = canvas(
			root,
			"Currency",
			128,
			372,
			48,
			kindsOf(o.currencies, CURRENCY_KIND, { "coin", "confetti" }),
			5
		),
		price = label(
			root,
			"Price",
			184,
			372,
			CARD_W - MARGIN - 184,
			48,
			U.Card.value,
			Enum.TextXAlignment.Left,
			COLORS.text,
			5
		),
	}
	p.badge = canvas(
		root,
		"Badge",
		(CARD_W + U.Card.icon) / 2 - 24,
		8,
		32,
		kindsOf(o.badges, BADGE_KIND, { "loop", "infinity", "star" }),
		7
	)
	local bar = frame(root, "PriceBar", x0, 424, CARD_IN, 8, COLORS.barBack, 4)
	p.priceBar = bar
	p.priceFill = frame(bar, "Fill", 0, 0, 0, 8, COLORS.barNeed, 5)
	-- zone du bas (y 432 → 512) : dessin du bouton « Acheter » (glyphe de l'appareil) ou état
	local pill = frame(root, "Buy", x0, 432, CARD_IN, 80, COLORS.buy, 4)
	corner(pill, Layout.Corner.Min)
	p.pill = pill
	-- glyphe de l'appareil DANS le dessin du bouton : caché avec lui (Glyph gère sa propre visibilité)
	p.glyph = Glyph.new(pill, { gamepad = Enum.KeyCode.ButtonA, keyboard = Enum.KeyCode.Return }, {
		size = 48,
		position = UDim2.fromOffset(104 - x0, 16),
		zIndex = 6,
	})
	p.stateIcon = canvas(root, "StateIcon", 104, 448, 48, STATE_KINDS, 6)
	p.word =
		label(root, "Word", 164, 444, CARD_W - MARGIN - 164, 56, 36, Enum.TextXAlignment.Left, COLORS.text, 6)
	return p
end

local function buildRow(root: GuiObject, o: Options): Parts
	local text, level, price, state = COL.text, COL.level, COL.effect, COL.state
	local valueW = 120 -- place réservée d'une valeur (UI/Format.Reserved : ×, %, s)
	local arrowSlot = 40
	local labelW = text.w - 2 * valueW - arrowSlot - 2 * 8
	local beforeX = text.x + labelW + 8
	local arrowX = beforeX + valueW + (arrowSlot - 32) / 2
	local afterX = beforeX + valueW + arrowSlot
	local levelW = (level.w - 36) / 2 -- « 12 », flèche (36), « 22 »
	local p: Parts = {
		icon = canvas(root, "Icon", COL.icon.x, 16, COL.icon.w, kindsOf(o.icons, nil, LINE_ICONS), 5),
		name = label(
			root,
			"Name",
			text.x,
			10,
			text.w,
			44,
			U.Card.title,
			Enum.TextXAlignment.Left,
			COLORS.text,
			5
		),
		effectLabel = label(
			root,
			"EffectLabel",
			text.x,
			58,
			labelW,
			44,
			32,
			Enum.TextXAlignment.Left,
			COLORS.dim,
			5
		),
		before = label(
			root,
			"Before",
			beforeX,
			58,
			valueW,
			44,
			32,
			Enum.TextXAlignment.Right,
			COLORS.text,
			5
		),
		effectArrow = canvas(root, "EffectArrow", arrowX, 64, 32, { "arrowRight" }, 5),
		after = label(root, "After", afterX, 58, valueW, 44, 32, Enum.TextXAlignment.Left, COLORS.text, 5),
		levelA = label(
			root,
			"LevelA",
			level.x,
			14,
			level.w,
			48,
			U.Card.value,
			Enum.TextXAlignment.Center,
			COLORS.text,
			5
		),
		levelArrow = canvas(root, "LevelArrow", level.x + levelW + 4, 24, 28, { "arrowRight" }, 5),
		levelB = label(
			root,
			"LevelB",
			level.x + levelW + 36,
			14,
			levelW,
			48,
			U.Card.value,
			Enum.TextXAlignment.Left,
			COLORS.text,
			5
		),
		currency = canvas(
			root,
			"Currency",
			price.x,
			18,
			40,
			kindsOf(o.currencies, CURRENCY_KIND, { "coin", "confetti" }),
			5
		),
		price = label(
			root,
			"Price",
			price.x + 48,
			14,
			price.w - 48,
			48,
			U.Card.value,
			Enum.TextXAlignment.Left,
			COLORS.text,
			5
		),
		stateIcon = canvas(root, "StateIcon", state.x, (ROW_H - 48) / 2, 48, STATE_KINDS, 5),
		word = label(
			root,
			"Word",
			state.x + 56,
			28,
			state.w - 56,
			56,
			28,
			Enum.TextXAlignment.Left,
			COLORS.text,
			5
		),
	}
	p.badge = canvas(
		root,
		"Badge",
		COL.icon.x + COL.icon.w - 24,
		8,
		32,
		kindsOf(o.badges, BADGE_KIND, { "loop", "infinity", "star" }),
		7
	)
	local lbar = frame(root, "LevelBar", level.x, 72, level.w, 12, COLORS.barBack, 4)
	p.levelBar = lbar
	p.levelFill = frame(lbar, "Fill", 0, 0, 0, 12, COLORS.barFill, 5)
	p.levelGrey = frame(lbar, "Grey", level.w, 0, 0, 12, COLORS.barGrey, 6)
	local pbar = frame(root, "PriceBar", price.x, 76, price.w, 8, COLORS.barBack, 4)
	p.priceBar = pbar
	p.priceFill = frame(pbar, "Fill", 0, 0, 0, 8, COLORS.barFill, 5)
	return p
end

local function buildTile(root: GuiObject, o: Options): Parts
	local inner = TILE_W - 2 * MARGIN
	local p: Parts = {
		icon = canvas(
			root,
			"Icon",
			(TILE_W - U.Tile.icon) / 2,
			MARGIN,
			U.Tile.icon,
			kindsOf(o.icons, nil, LINE_ICONS),
			5
		),
		name = label(
			root,
			"Title",
			MARGIN,
			144,
			inner,
			88,
			U.Tile.title,
			Enum.TextXAlignment.Center,
			COLORS.text,
			5
		),
		stateIcon = canvas(root, "StateIcon", MARGIN, 244, 40, STATE_KINDS, 5),
		word = label(
			root,
			"Value",
			MARGIN,
			240,
			inner,
			48,
			U.Tile.value,
			Enum.TextXAlignment.Center,
			COLORS.text,
			5
		),
	}
	return p
end

-- Carte, ligne ou tuile neuve (vide jusqu'au premier set)
function UpgradeCard.new(template: Template, parent: Instance?, opts: Options?): Card
	local t: Template = if template == "row" or template == "tile" then template else "card"
	local o: Options = table.clone(opts or {})
	if t == "card" then
		-- carte du Conseillé : une famille de pièces (UpgradeAdvisor), sans coin d'icône (GDD §10.7.4)
		o.icons = o.icons or COIN_ICONS
		o.badges = o.badges or {}
		o.currencies = o.currencies or { "coin" }
	end
	local root = rootOf(t, parent)
	local parts: Parts
	if t == "row" then
		parts = buildRow(root, o)
	elseif t == "tile" then
		parts = buildTile(root, o)
	else
		parts = buildCard(root, o)
		-- ombre de 6 px vers le bas (Theme.shadow, comme Widgets.frame({ shadow = true })) : la carte
		-- seulement, jamais une ligne (INT-B1-SHADOW, GDD §10.7.10)
		Theme.shadow(root)
	end
	local self = setmetatable(
		{ template = t, root = root, parts = parts, state = "", view = nil, fb = nil },
		UpgradeCard
	)
	return self
end

-- =============================================================================================
-- Mise à jour (aucune instance créée)
-- =============================================================================================

local function setText(l: TextLabel?, t: UpgradeView.Text?)
	if l == nil then
		return
	end
	if t == nil then
		if l.Visible then
			l.Visible = false
		end
		return
	end
	Text.set(l, t.key, t.vars)
	if not l.Visible then
		l.Visible = true
	end
end

local function setRaw(l: TextLabel?, s: string?)
	if l == nil then
		return
	end
	if s == nil then
		l.Visible = false
		return
	end
	Text.raw(l, s)
	l.Visible = true
end

local function show(g: GuiObject?, on: boolean)
	if g ~= nil and g.Visible ~= on then
		g.Visible = on
	end
end

local function color(l: GuiObject?, c: Color3)
	if l ~= nil and l:IsA("TextLabel") and (l :: TextLabel).TextColor3 ~= c then
		(l :: TextLabel).TextColor3 = c
	end
end

-- Pose l'état et la vue (même vue pour la carte, la ligne et le bandeau : règle 8)
function UpgradeCard.set(self: Card, state: string, view: UpgradeView.View)
	local p = self.parts
	local st = if STATE_COLORS[state] then state else view.state
	self.state = st
	self.view = view
	local root = self.root
	if self.template ~= "tile" and root:GetAttribute("FocusId") ~= view.id then
		root:SetAttribute("FocusId", view.id)
	end
	root:SetAttribute("State", st)
	local stColor = STATE_COLORS[st] or COLORS.text
	local buyable = st == "ready" or st == "need" or st == "busy" or st == "retry"

	-- icône de la famille et coin (boucle, infini, étoile du Conseillé)
	Icons.draw(p.icon, if Icons.has(view.icon) then view.icon else nil)
	if p.badge then
		local badge = if view.badge then BADGE_KIND[view.badge] else nil
		Icons.draw(p.badge, badge)
	end

	-- nom, palier, raison
	setText(p.name, view.name)
	if p.tier then
		setText(p.tier, if self.template == "card" then view.tier else nil)
	end
	if p.reason then
		setText(p.reason, view.reason)
	end

	-- avant → après (flèche dessinée seulement entre deux valeurs)
	local effect = view.effect
	local fb = self.fb
	if self.template ~= "tile" then
		local hasValues = effect ~= nil and effect.before ~= nil and fb == nil
		local hasAfter = effect ~= nil and effect.after ~= nil and effect.before ~= nil
		-- ligne : le retour chiffré prend la place de l'avant → après (« dans la ligne même »)
		local rowFb = fb ~= nil and self.template == "row"
		setText(p.effectLabel, if rowFb then fb elseif effect and not fb then effect.label else nil)
		color(p.effectLabel, if rowFb then COLORS.text else COLORS.dim)
		setText(p.before, if effect and not fb then effect.before else nil)
		setText(p.after, if hasAfter and not fb then (effect :: UpgradeView.Effect).after else nil)
		if p.effectArrow then
			Icons.draw(p.effectArrow, if hasAfter and not fb then "arrowRight" else nil)
		end
		-- ligne : le libellé seul prend toute la colonne Texte (« Revenu total +1,2 % »)
		if self.template == "row" and p.effectLabel then
			local full = COL.text.w
			local short = full - 2 * 120 - 40 - 16
			local w = if hasValues then short else full
			if p.effectLabel.Size.X.Offset ~= w then
				p.effectLabel.Size = UDim2.fromOffset(w, p.effectLabel.Size.Y.Offset)
			end
		end
	end

	-- niveau : « 12/20 » (ligne), « Niv. 7 » → « 8 » (carte) ; ×10 / Max : « 12 » → « 22 »
	if self.template == "row" then
		local bulk = buyable and view.fromText ~= nil and view.toText ~= nil and view.sendMode ~= 1
		if view.readOnly then
			show(p.levelA, false)
			show(p.levelB, false)
			if p.levelArrow then
				Icons.draw(p.levelArrow, nil)
			end
			show(p.levelBar, false)
		else
			local la = p.levelA :: TextLabel
			if bulk then
				la.Size = UDim2.fromOffset((COL.level.w - 36) / 2, la.Size.Y.Offset)
				la.TextXAlignment = Enum.TextXAlignment.Right
				setRaw(la, view.fromText)
				setRaw(p.levelB, view.toText)
				Icons.draw(p.levelArrow :: Frame, "arrowRight")
			else
				la.Size = UDim2.fromOffset(COL.level.w, la.Size.Y.Offset)
				la.TextXAlignment = Enum.TextXAlignment.Center
				setRaw(la, view.levelText)
				show(p.levelB, false)
				Icons.draw(p.levelArrow :: Frame, nil)
			end
			show(p.levelBar, true)
			local fill = p.levelFill :: Frame
			local grey = p.levelGrey :: Frame
			local w = COL.level.w
			fill.Size = UDim2.fromOffset(math.floor(w * math.clamp(view.barFill, 0, 1) + 0.5), 12)
			local capX = math.floor(w * math.clamp(view.barCap, 0, 1) + 0.5)
			grey.Position = UDim2.fromOffset(capX, 0)
			grey.Size = UDim2.fromOffset(w - capX, 12)
			show(grey, capX < w)
		end
	elseif self.template == "card" then
		local cl = view.cardLevel
		setText(p.levelA, cl.before)
		setText(p.levelB, cl.after)
		Icons.draw(p.levelArrow :: Frame, if cl.before and cl.after then "arrowRight" else nil)
	end

	-- prix : icône de la monnaie + montant (« — » au maximum) ; barre « ce que j'ai / ce qu'il faut »
	if p.price then
		local priced = not view.readOnly and view.currency ~= nil
		if priced and st ~= "max" and view.priceText ~= nil then
			setRaw(p.price, view.priceText)
			color(p.price, if st == "ready" then COLORS.text else COLORS.grey)
		elseif priced then
			setRaw(p.price, DASH)
			color(p.price, COLORS.grey)
		else
			setRaw(p.price, nil)
		end
		if p.currency then
			local kind = if priced and view.currency then CURRENCY_KIND[view.currency] else nil
			Icons.draw(p.currency, kind)
		end
		if p.priceBar and p.priceFill then
			-- ligne : barre de tout achat possible ; carte : seulement si ce n'est pas payable (GDD §10.7.4)
			local barOn = buyable and view.price ~= nil and (self.template == "row" or st ~= "ready")
			show(p.priceBar, barOn)
			if barOn then
				local w = p.priceBar.Size.X.Offset
				local f = math.clamp(view.fill, 0, 1)
				p.priceFill.Size = UDim2.fromOffset(math.floor(w * f + 0.5), p.priceFill.Size.Y.Offset)
				p.priceFill.BackgroundColor3 = if f >= 1 then COLORS.barFill else COLORS.barNeed
			end
		end
	end

	-- état : dessin + un mot (carte prête : dessin du bouton « Acheter » avec le glyphe de l'appareil)
	local word: UpgradeView.Text? = nil
	if st == view.state then
		word = view.stateText
	elseif STATE_WORDS[st] then
		word = { key = STATE_WORDS[st] }
	end
	local iconKind = if st == view.state then view.stateIcon else UpgradeView.STATE_ICONS[st]
	if view.readOnly and st ~= "locked" then
		-- ligne en lecture seule : rien à acheter (seul le cadenas d'une Plopette pas encore là)
		word, iconKind = nil, nil
	end
	local buyDrawing = self.template == "card" and st == "ready" and fb == nil
	if self.template == "tile" then
		-- tuile : la valeur (lot B3) ou le mot de l'état, avec son dessin
		local value = view.value
		local text = value or word
		setText(p.word, text)
		local withIcon = value == nil and iconKind ~= nil
		Icons.draw(
			p.stateIcon :: Frame,
			if withIcon then iconKind else nil,
			if withIcon then stColor else nil
		)
		local w = p.word :: TextLabel
		local x = if withIcon then MARGIN + 48 else MARGIN
		w.Position = UDim2.fromOffset(x, w.Position.Y.Offset)
		w.Size = UDim2.fromOffset(TILE_W - MARGIN - x, w.Size.Y.Offset)
		w.TextXAlignment = if withIcon then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
		color(w, if withIcon then stColor else COLORS.text)
	else
		show(p.pill, buyDrawing)
		if buyDrawing then
			Icons.draw(p.stateIcon :: Frame, nil)
			setText(p.word, { key = "common.buy" })
			color(p.word, COLORS.text)
		elseif fb ~= nil and self.template == "card" then
			-- carte : le retour chiffré occupe la zone du bas (mot élargi à toute la carte)
			Icons.draw(p.stateIcon :: Frame, nil)
			setText(p.word, fb)
			color(p.word, COLORS.text)
		else
			Icons.draw(p.stateIcon :: Frame, iconKind, if iconKind then stColor else nil)
			setText(p.word, word)
			color(p.word, stColor)
		end
	end
	-- mot de la zone du bas de la carte : à côté du dessin, ou centré sur toute la carte (retour)
	if self.template == "card" and p.word then
		local wide = fb ~= nil
		local x = if wide then MARGIN else 164
		if p.word.Position.X.Offset ~= x then
			p.word.Position = UDim2.fromOffset(x, p.word.Position.Y.Offset)
			p.word.Size = UDim2.fromOffset(CARD_W - MARGIN - x, p.word.Size.Y.Offset)
			p.word.TextXAlignment = if wide then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
		end
	end
end

-- Retour chiffré dans la ligne même (« +7 niveaux · -1,2 M », clé et variables de l'écran ; GDD
-- §10.7.8) : ligne, à la place de l'avant → après ; carte, dans la zone du bas ; nil : fini. Même vue,
-- aucune instance créée.
function UpgradeCard.feedback(self: Card, t: UpgradeView.Text?)
	if self.template == "tile" then
		return
	end
	self.fb = t
	local view = self.view
	if view ~= nil then
		UpgradeCard.set(self, self.state, view)
	end
end

return UpgradeCard
