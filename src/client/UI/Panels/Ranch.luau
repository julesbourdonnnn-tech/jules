--!strict
-- Ranch (paquet client-panels) : panneau Ranch (GDD §10.3, §4.10, §4.13, §4.14, §4.6, §5.4 ;
-- docs/04 §13.6, contrat v1.2). Onglets dans l'ordre : Enclos, Dodo, Lettres, Fusionner, Vendre,
-- Dalles, Style.
--   * Enclos : grille virtualisée (tri taille / rareté / revenu), verrou, Meilleur Ami, monture,
--     cœur des jumeaux ; ✕ sur un squishy ouvre sa fiche (Verrou, Meilleur Ami 1-3, Monture, Vers la
--     Boîte à dodo) ; Tout fusionner (FuseAll) ; Ranger : aperçu « Vendre 14 squishies = 3,2K » puis
--     maintien 0,6 s (rien ne part sans cet aperçu) ;
--   * Dodo : ✕ ramène un squishy dans l'enclos (2 gestes : onglet, ✕) ; Lettres : ✕ le prend ;
--   * Fusionner : « Choisir A » puis B (seulement les jumeaux de A), ou Tout fusionner ;
--   * Vendre / Relâcher : sélection multiple ; maintien 0,6 s pour un Rare+ ou un squishy muté (et pour
--     chaque relâche) ; 2e étape avec « 1 sur X » pour un Épique+ ou une mutation ×5+ ; ○ vide d'abord
--     la sélection, puis remonte au menu ;
--   * Dalles : toutes les dalles avec leur prix, achat d'ici (BuyTile) ; depuis l'aperçu du Grand
--     Splorch (onglet « padsKept ») : d'abord les dalles gardées au Grand Splorch ;
--   * Style : sous-listes Selle, Traînée, Titre, Thème, Drapeau, Tenues ; « Équipé », ou cadenas et
--     source ; ✕ sur un objet débloqué → EquipCosmetic(kind, id) (« Aucun » pour retirer) ; ✕ sur une
--     tenue possédée → OutfitPreview ; verrouillé : refusé sans envoi (son Error, vibration refuse).
-- v2.0 (lot B3, étape 3 ; plan B3 D10, D11, D12, D17, D24, D25) :
--   * N8 : l'onglet Dalles n'existe pas tant que l'écran Améliorations est disponible (instantané du
--     serveur, UpgradeSnapshot.available) ; sa page n'est alors pas construite (elle l'est à
--     l'ouverture suivante si le chemin de la v1.3 revient) ; open("padsKept") garde son sens v1.3 ;
--   * Mon style (profil v2 et au moins un interrupteur v2.0 annoncé, UI/MetaFlags) : l'onglet Style
--     s'appelle « Mon style » ; sortes habillage (14), Déco perso (plan vu du dessus, seulement si MON
--     ranch porte l'attribut DecoPerso), selle, traînée, titre (jusqu'à 66), drapeau, tenues (8),
--     palette et coussins (Owned.kindOpen) ; liste des sortes et grille virtualisée (Widgets.rows,
--     5 colonnes) communes à toutes les sortes ; possession : v1.3 par cosmeticUnlocked, v2.0 par
--     Logic/Owned, tenues par outfits.owned ; plan : 12 emplacements de WorldLayout.decoPersoSlots(),
--     contenu de RanchLook.decoPerso(attribut DecoPerso), ✕ → choix dans la grille (« Aucun », objets
--     possédés de la taille, puis verrouillés) → PlaceDeco(n, emplacement) ; ○ : choix → son
--     emplacement, plan ou grille → liste des sortes, liste → menu. Rien n'est construit, envoyé ni
--     montré de la v2.0 interrupteurs coupés : l'onglet Style de la v1.3 reste identique ;
--   * glyphes de la règle 18 (D17) : cœur des jumeaux, cœur de la pastille du Meilleur Ami et coche de
--     la case choisie DESSINÉS (Hud/Icons), dans les deux chemins.
-- Un bouton refusé (enclos pleins, pas assez de pièces, verrouillé) ne part jamais au serveur ; le
-- serveur revalide tout. Sélection par défaut (GDD §10.6) : 1re case ; Fusionner : « Choisir A » ;
-- Dalles : la moins chère achetable ; Style : l'objet équipé de la 1re sous-liste ; Mon style :
-- l'objet équipé de la 1re sorte (habillage), plan : l'emplacement 1.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Layout = require(Shared.Config.Layout)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Formulas = require(Shared.Logic.Formulas)
local FusionRules = require(Shared.Logic.FusionRules)
local Odds = require(Shared.Logic.Odds)
local QuestRules = require(Shared.Logic.QuestRules)
local Owned = require(Shared.Logic.Owned)
local Bitset = require(Shared.Logic.Bitset)
local RanchLook = require(Shared.Logic.RanchLook)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Clock = require(Shared.Util.Clock)
local Net = require(Shared.Net)

local Client = script.Parent.Parent.Parent
local Toast = require(Client.UI.Toast)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Prefs = require(Client.Util.Prefs)
local Widgets = require(script.Parent.Widgets)
local Format = require(Client.UI.Format)
local Icons = require(Client.UI.Hud.Icons)
local MetaFlags = require(Client.UI.MetaFlags)
local MetaView = require(Client.UI.MetaView)
local UpgradeSnapshot = require(Client.UI.UpgradeSnapshot)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }
type Item = { uid: string, rec: { [string]: any }, size: number, income: number }
type Cell = {
	button: TextButton,
	blob: Frame,
	name: TextLabel,
	size: TextLabel,
	line: TextLabel,
	bf: TextLabel,
	bfHeart: Frame,
	-- une seule toile (Hud/Icons) : coche de la case choisie, sinon cœur des jumeaux (règle 18, D17)
	mark: Frame,
	lock: Frame,
	mount: Frame,
	uid: string,
}
-- Mon style (v2.0) : case de la grille commune, liste des sortes, entrée liée à une case
type V2Cell = {
	button: TextButton,
	swatch: Frame,
	lock: Frame,
	name: TextLabel,
	status: TextLabel,
	index: number, -- entrée liée (0 : aucune)
}
type V2Row = { cells: { V2Cell } }
type KindRow = { button: TextButton, kind: string }
type V2Entry = {
	kind: string, -- sorte du profil (EquipCosmetic) ; « deco » : choix d'un objet de Déco perso
	id: string, -- "" : « Aucun »
	n: number, -- Déco perso : numéro de l'objet (0 : « Aucun »)
	name: MetaView.Text,
	source: MetaView.Text?,
	color: Color3?,
	unlocked: boolean,
	equipped: boolean,
}
type Row = { cells: { Cell } }
type StyleCell = {
	button: TextButton,
	name: TextLabel,
	status: TextLabel,
	swatch: Frame,
	kind: string,
	id: string,
}

local Ranch = {}

local TABS = { "pens", "dodo", "mail", "fuse", "sell", "pads", "style" }
local GRID_TABS = { pens = true, dodo = true, mail = true, fuse = true, sell = true }
local SORTS = { "size", "rarity", "income" }
local TILE_ORDER = { "snack", "decor", "pens", "cozyBed" }
local STYLE_KINDS = { "saddle", "trail", "title", "theme", "flag", "outfits" }
local NONE_KINDS = { trail = true, title = true, flag = true } -- « Aucun » pour retirer
local COLS = Layout.Panel.columns
local CELL = Layout.Panel.cell
local GAP = Layout.Spacing.Min
local BAR_H = Layout.Button.MinHeight
local BAR_GAP = Layout.Spacing.Normal -- 24 : le bouton sélectionné grossit sans toucher son voisin
local HOLD = Balance.Sell.Hold
-- glyphes dessinés (D17) : pastille du Meilleur Ami (cœur + nombre), cœur des jumeaux, coche
local BF_W, BF_HEART = 64, 22
local MARK_HEART = { x = 8, y = 8, size = 32 }
local MARK_CHECK = { x = 10, y = 56, size = 52 }
-- Mon style (v2.0, D10, D11, D24) : liste des sortes, grille de 5 colonnes, plan vu du dessus
local V2_KIND_W = 260
local V2_COLS = 5
local V2_CELL_H = 200
-- px : marge des textes d'une case de Mon style (nom, source) : le cadre de focus couvre les 8 px du bord
-- de la case choisie (liseré 2 + trait blanc 6) et le contour du texte déborde de 2 px ; à 6 px, les
-- noms longs (« Dragon de gelée ») avaient leur 1re et leur dernière lettre sous le trait blanc
-- (relecture des écrans du lot B3, B3-79)
local V2_TEXT_INSET = Layout.Focus.Frame + Layout.Focus.Border + 2
local PLAN_TOP = 56 -- titre du plan au-dessus du rectangle

local nav: Nav? = nil
local isOpen = false
local current = "pens"
local keptFirst = false
local sortMode = 1
local tabBar: Widgets.TabBar? = nil
local pages: { [string]: Frame } = {}
local gridPage: Frame? = nil
local bars: { [string]: Frame } = {}
local grid: Widgets.Rows? = nil
local items: { Item } = {}
local labels: { [string]: TextLabel } = {}
local buttons: { [string]: TextButton } = {}
local holds: { [string]: Widgets.Hold } = {}
-- sous-niveaux
local detail: Frame? = nil
local detailUid = ""
local detailFrom: TextButton? = nil
local detailButtons: { [string]: TextButton } = {}
local overlay: Frame? = nil
local overlayMode = "" -- "tidy" | "confirm"
local overlayAction = "" -- "Sell" | "Release"
local overlayUids: { string } = {}
-- fusion, vente
local fuseA = ""
local selected: { [string]: boolean } = {}
-- dalles
local tileButtons: { [string]: TextButton } = {}
-- style
local styleKind = "saddle"
local styleKindButtons: { [string]: TextButton } = {}
local styleCells: { StyleCell } = {}
local sessionUnlocks: { [string]: boolean } = {} -- titres de la semaine (Celebrate "unlock")
-- construction paresseuse (D12, D24) : dalles et parties de Style construites sur leur premier besoin
local buildContainer: Frame? = nil
local buildTop = 0
local padsBuilt = false
local stylePage: Frame? = nil
local styleMode = "" -- "v13" | "v2" : chemin de Style montré (choisi à l'ouverture, jamais écran ouvert)
local v13Built = false
local v2Built = false
local v13Kinds: Frame? = nil
local v13Items: Frame? = nil
-- Mon style
local kindsV2: { string } = {}
local kindRows: Widgets.Rows? = nil
local itemRows: Widgets.Rows? = nil
local v2Entries: { V2Entry } = {}
local planFrame: Frame? = nil
local slotButtons: { TextButton } = {}
local pickerSlot = 0 -- Déco perso : emplacement dont le choix est ouvert (0 : le plan)
local decoContents: { number } = table.create(#Cosmetics.DecoSlots, 0)
local decoModel: Instance? = nil
local decoConn: RBXScriptConnection? = nil

-- =============================================================================================
-- Données
-- =============================================================================================

local function squishies(): { [string]: any }
	return Widgets.tbl(Widgets.state("squishies"))
end

local function incomeCtx(): { [string]: any }
	local tiles = Widgets.tbl(Widgets.state("tiles"))
	local passes = Widgets.tbl(Widgets.state("passes"))
	local dex = Widgets.tbl(Widgets.state("dex"))
	return {
		decor = Widgets.n(tiles.decor),
		friends = 0,
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
	}
end

local function penCapacity(): number
	local tiles = Widgets.tbl(Widgets.state("tiles"))
	local passes = Widgets.tbl(Widgets.state("passes"))
	return Widgets.safe(
		"Formulas.penCapacity",
		Balance.Pens.Base,
		Formulas.penCapacity,
		Widgets.n(tiles.pens),
		passes.BigRanch == true
	)
end

local function counts(): { pen: number, dodo: number, mail: number }
	local c = { pen = 0, dodo = 0, mail = 0 }
	for _, rec in squishies() do
		if type(rec) == "table" then
			if rec.at == "pen" or rec.at == "pool" then
				c.pen += 1
			elseif rec.at == "dodo" then
				c.dodo += 1
			elseif rec.at == "mail" then
				c.mail += 1
			end
		end
	end
	return c
end

local function waitingUid(): string
	-- squishy en attente de Grand Splorch : état public du ranch (WorldStateController), sinon inconnu
	local slot = Widgets.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
	if type(slot) ~= "number" or slot <= 0 then
		return ""
	end
	local ranch = Widgets.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
	return if type(ranch) == "table" and type(ranch.waiting) == "string" then ranch.waiting else ""
end

local function rarityOf(rec: { [string]: any }): number
	return Widgets.rarityOf(rec.s)
end

local function mutationDef(rec: { [string]: any }): Mutations.MutationDef?
	return if type(rec.m) == "number" then Mutations.ById[rec.m] else nil
end

-- Vente / relâche : maintien (Rare+ ou muté) et confirmation en 2 étapes (Épique+ ou mutation ×5+)
local function needsHold(rec: { [string]: any }): boolean
	local rdef = Rarities.List[rarityOf(rec)]
	return (rdef ~= nil and rdef.sellHold) or (Widgets.n(rec.m) > 0)
end

local function needsConfirm(rec: { [string]: any }): boolean
	local rdef = Rarities.List[rarityOf(rec)]
	local mdef = mutationDef(rec)
	return (rdef ~= nil and rdef.sellConfirm) or (mdef ~= nil and mdef.sellConfirm)
end

local function collect(filter: (rec: { [string]: any }, uid: string) -> boolean): { Item }
	local G = Widgets.safe("Formulas.G", 0, Formulas.G, Widgets.state("growth"), Clock.now())
	local ctx = incomeCtx()
	local out: { Item } = {}
	for uid, rec in squishies() do
		if type(uid) == "string" and type(rec) == "table" and filter(rec, uid) then
			local size = Widgets.safe("Formulas.sizeAt", 1, Formulas.sizeAt, rec, G)
			local income = if rec.at == "pen" or rec.at == "pool"
				then Widgets.safe("Formulas.income", 0, Formulas.income, size, rec.s, rec.m, rec.st, ctx)
				else 0
			table.insert(out, { uid = uid, rec = rec, size = size, income = income })
		end
	end
	local mode = if current == "pens" then SORTS[sortMode] else "size"
	table.sort(out, function(a, b)
		if mode == "rarity" then
			local ra, rb = rarityOf(a.rec), rarityOf(b.rec)
			if ra ~= rb then
				return ra > rb
			end
		elseif mode == "income" then
			if a.income ~= b.income then
				return a.income > b.income
			end
		end
		if a.size ~= b.size then
			return a.size > b.size
		end
		return a.uid < b.uid
	end)
	return out
end

local function itemsFor(tab: string): { Item }
	local waiting = waitingUid()
	if tab == "pens" then
		return collect(function(rec)
			return rec.at == "pen" or rec.at == "pool"
		end)
	elseif tab == "dodo" then
		return collect(function(rec)
			return rec.at == "dodo"
		end)
	elseif tab == "mail" then
		return collect(function(rec)
			return rec.at == "mail"
		end)
	elseif tab == "fuse" then
		return collect(function(rec, uid)
			return (rec.at == "pen" or rec.at == "pool" or rec.at == "dodo") and uid ~= waiting
		end)
	elseif tab == "sell" then
		return collect(function(rec)
			return rec.at == "pen" or rec.at == "pool" or rec.at == "dodo"
		end)
	end
	return {}
end

local function itemOf(uid: string): Item?
	for _, item in items do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

-- Le squishy a-t-il un jumeau (même espèce, mêmes étoiles) hors Lettres, aucun des deux verrouillé ?
local function hasTwin(uid: string, rec: { [string]: any }): boolean
	if rec.at == "mail" or rec.lk == true then
		return false
	end
	for other, r in squishies() do
		if other ~= uid and type(r) == "table" and r.at ~= "mail" and r.lk ~= true then
			local ok, twins = pcall(FusionRules.areTwins, rec :: any, r :: any)
			if ok and twins then
				return true
			end
		end
	end
	return false
end

-- =============================================================================================
-- Cases de la grille
-- =============================================================================================

local function cellDisabled(item: Item): boolean
	local rec = item.rec
	if current == "fuse" and fuseA ~= "" and item.uid ~= fuseA then
		local a = squishies()[fuseA]
		local ok, twins = pcall(FusionRules.areTwins, a :: any, rec :: any)
		return not (type(a) == "table" and ok and twins)
	end
	if current == "sell" then
		return Widgets.n(rec.bf) > 0 or rec.lk == true or item.uid == waitingUid()
	end
	return false
end

-- Texte posé sur un fond vif (vert de la case choisie, or d'un bouton) : bleu nuit sans contour.
-- Le blanc, la lavande et l'or n'y étaient plus qu'un contour (contraste de la couleur seule 1,1 à
-- 1,8 ; revue des écrans). Sur un fond sombre : couleur `color` et contour d'origine
local function inkOn(label: TextLabel?, bright: boolean, color: Color3)
	if label == nil then
		return
	end
	label.TextColor3 = if bright then Widgets.Colors.Stroke else color
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = not bright
	end
end

local function bindCell(cell: Cell, item: Item?)
	cell.button.Visible = item ~= nil
	if item == nil then
		cell.uid = ""
		return
	end
	local rec = item.rec
	cell.uid = item.uid
	Widgets.paintBlob(cell.blob, rec.s, true)
	Widgets.setRaw(cell.name, Widgets.speciesName(rec.s))
	Widgets.setText(cell.size, "common.size", { size = Widgets.num(item.size) })
	local isSelected = (current == "sell" and selected[item.uid] == true)
		or (current == "fuse" and fuseA == item.uid)
	local lineColor = Widgets.Colors.Gold
	local mdef = mutationDef(rec)
	if mdef then
		Widgets.setText(cell.line, "mutation." .. mdef.key)
		lineColor = mdef.color
	elseif Widgets.n(rec.st) > 0 then
		Widgets.setText(cell.line, "common.stars", { n = math.floor(Widgets.n(rec.st)) })
	else
		Widgets.setRaw(cell.line, "")
	end
	-- case choisie (fond vert vif) : nom, taille et ligne en bleu nuit sans contour. Blanc, lavande
	-- et or s'y lisaient à 1,8, 1,1 et 1,2 de contraste sans le contour (« Taille 437 K » presque
	-- invisible à 3 m ; revue des écrans). Hors choix : couleurs et contour d'origine
	inkOn(cell.name, isSelected, Widgets.Colors.Text)
	inkOn(cell.size, isSelected, Widgets.Colors.TextDim)
	inkOn(cell.line, isSelected, lineColor)
	local bf = math.floor(Widgets.n(rec.bf))
	cell.bf.Visible = bf > 0
	-- « ♥n » : cœur DESSINÉ devant le nombre (« ♥ » absent des polices, règle 18 ; lot B3, D17)
	Widgets.setRaw(cell.bf, Format.count(bf))
	-- une seule toile : la coche de la case choisie (grande, à gauche, bleu nuit sur le vert), sinon le
	-- cœur des jumeaux (en haut à droite) ; à Fusionner, la case choisie est un jumeau (budget, D24)
	local mark = cell.mark
	if isSelected then
		mark.AnchorPoint = Vector2.zero
		mark.Position = UDim2.fromOffset(MARK_CHECK.x, MARK_CHECK.y)
		mark.Size = UDim2.fromOffset(MARK_CHECK.size, MARK_CHECK.size)
		Icons.draw(mark, "check", Widgets.Colors.Stroke)
	elseif hasTwin(item.uid, rec) then
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, -MARK_HEART.x, 0, MARK_HEART.y)
		mark.Size = UDim2.fromOffset(MARK_HEART.size, MARK_HEART.size)
		Icons.draw(mark, "heart")
	else
		Icons.draw(mark, nil)
	end
	cell.lock.Visible = rec.lk == true
	cell.mount.Visible = Widgets.state("mount") == item.uid
	local base = Widgets.rarityColor(rarityOf(rec)):Lerp(Widgets.Colors.Card, 0.6)
	cell.button.BackgroundColor3 = if isSelected then Widgets.Colors.Success else base
	Widgets.setDisabled(cell.button, cellDisabled(item))
	-- seule la case de l'Enclos ouvre un autre écran (sa fiche) ; ailleurs ✕ agit (robot TvAudit)
	cell.button:SetAttribute("TvNav", current == "pens")
end

local function bindRow(row: Row, _frame: Frame, index: number)
	for c, cell in row.cells do
		bindCell(cell, items[(index - 1) * COLS + c])
	end
end

local function makeCell(frame: Frame, c: number): Cell
	local cell: Cell
	local b = Widgets.button({
		parent = frame,
		name = "Cell" .. c,
		size = UDim2.fromOffset(CELL.w, CELL.h),
		position = UDim2.fromOffset((c - 1) * (CELL.w + GAP), 0),
		color = Widgets.Colors.Card,
		nav = false,
		onActivate = function()
			Ranch._activateCell(cell.uid, cell.button)
		end,
	})
	local blob = Widgets.blob(b, "Blob")
	blob.AnchorPoint = Vector2.new(0.5, 0)
	blob.Position = UDim2.new(0.5, 0, 0, 14)
	blob.Size = UDim2.fromOffset(110, 92)
	blob.ZIndex = b.ZIndex + 1
	local function text(name: string, y: number, h: number, size: number, color: Color3?): TextLabel
		return Widgets.label({
			parent = b,
			name = name,
			size = UDim2.new(1, -16, 0, h),
			position = UDim2.fromOffset(8, y),
			text = "",
			textSize = size,
			color = color,
			zIndex = b.ZIndex + 2,
		})
	end
	local name = text("Name", 112, 40, 32)
	local size = text("Size", 154, 34, 28, Widgets.Colors.TextDim)
	local line = text("Line", 192, 34, 28)
	-- « ♥1 » bleu nuit sur l'or, sans contour (un contour bleu nuit fondait les lettres en une tache ;
	-- revue des écrans) ; le cœur est DESSINÉ devant le nombre (règle 18, D17), place gardée par un
	-- retrait, comme la pastille des jumeaux du rail (lot B2)
	local bf = Widgets.label({
		parent = b,
		name = "BestFriend",
		size = UDim2.fromOffset(BF_W, 36),
		position = UDim2.fromOffset(6, 6),
		text = "",
		textSize = 28,
		color = Widgets.Colors.Stroke,
		stroke = false,
		background = Widgets.Colors.Gold,
		backgroundTransparency = 0,
		zIndex = b.ZIndex + 3,
	})
	Widgets.corner(bf, UDim.new(0.5, 0))
	-- les enfants d'un libellé à UIPadding sont posés dans la zone du texte : le cœur recule du retrait
	-- pour rester à 8 px du bord de la pastille, devant le nombre (spec Panels_Ranch, captures)
	local bfHeart = Icons.canvas(bf, BF_HEART, { "heart" }, "Heart")
	bfHeart.AnchorPoint = Vector2.new(0, 0.5)
	bfHeart.Position = UDim2.new(0, 8 - (BF_HEART + 12), 0.5, 0)
	bfHeart.ZIndex = bf.ZIndex + 1
	Icons.draw(bfHeart, "heart", Widgets.Colors.Stroke)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, BF_HEART + 12)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 0)
	pad.PaddingBottom = UDim.new(0, 0)
	pad.Parent = bf
	-- coche (case choisie) ou cœur des jumeaux : une toile, placée par bindCell
	local mark = Icons.canvas(b, MARK_HEART.size, { "check", "heart" }, "Mark")
	mark.ZIndex = b.ZIndex + 4
	local lock = Widgets.frame({
		parent = b,
		name = "Lock",
		size = UDim2.fromOffset(26, 22),
		position = UDim2.new(1, -52, 0, 18),
		anchor = Vector2.new(1, 0),
		color = Widgets.Colors.Gold,
		corner = UDim.new(0, 4),
		zIndex = b.ZIndex + 3,
	})
	Widgets.frame({
		parent = lock,
		name = "Ring",
		size = UDim2.fromOffset(16, 14),
		position = UDim2.new(0.5, 0, 0, -10),
		anchor = Vector2.new(0.5, 0),
		color = Widgets.Colors.Gold,
		transparency = 1,
		corner = UDim.new(0.5, 0),
		zIndex = lock.ZIndex,
	})
	local mount = Widgets.frame({
		parent = b,
		name = "Mount",
		size = UDim2.fromOffset(34, 18),
		position = UDim2.new(1, -8, 0, 92),
		anchor = Vector2.new(1, 0),
		color = Color3.fromRGB(170, 110, 70),
		corner = UDim.new(0, 8),
		zIndex = b.ZIndex + 3,
	})
	cell = {
		button = b,
		blob = blob,
		name = name,
		size = size,
		line = line,
		bf = bf,
		bfHeart = bfHeart,
		mark = mark,
		lock = lock,
		mount = mount,
		uid = "",
	}
	return cell
end

-- =============================================================================================
-- Barres d'actions
-- =============================================================================================

local function selectedUids(): { string }
	local out = {}
	for _, item in items do
		if selected[item.uid] then
			table.insert(out, item.uid)
		end
	end
	return out
end

local function refreshBars()
	local c = counts()
	for tab, bar in bars do
		bar.Visible = tab == current
	end
	if current == "pens" then
		Widgets.setText(labels.pensCount, "panel.ranch.count", { n = c.pen, max = penCapacity() })
		Widgets.setText(
			Widgets.buttonLabel(buttons.sort) :: TextLabel,
			"panel.ranch.sort." .. SORTS[sortMode]
		)
	elseif current == "dodo" then
		Widgets.setText(labels.dodoCount, "panel.ranch.count", { n = c.dodo, max = Balance.Pens.Dodo })
	elseif current == "mail" then
		Widgets.setText(labels.mailCount, "panel.ranch.count", { n = c.mail, max = Balance.Pens.Mail })
	elseif current == "fuse" then
		Widgets.setText(
			Widgets.buttonLabel(buttons.chooseA) :: TextLabel,
			if fuseA == "" then "panel.ranch.chooseA" else "panel.ranch.chooseB"
		)
		labels.onlyTwins.Visible = fuseA ~= ""
	elseif current == "sell" then
		local uids = selectedUids()
		Widgets.setText(labels.selected, "panel.ranch.selected", { n = #uids })
		local total = 0
		local hold = false
		for _, uid in uids do
			local item = itemOf(uid)
			if item then
				local income = item.income
				if income <= 0 then
					local ctx = incomeCtx()
					income = Widgets.safe(
						"Formulas.income",
						0,
						Formulas.income,
						item.size,
						item.rec.s,
						item.rec.m,
						item.rec.st,
						ctx
					)
				end
				total += Widgets.safe("Formulas.sellValue", 0, Formulas.sellValue, income)
				hold = hold or needsHold(item.rec)
			end
		end
		Widgets.setText(labels.value, "panel.ranch.sellValue", { coins = Widgets.num(total) })
		-- vente : maintien seulement pour un Rare+ ou un squishy muté ; relâche : toujours
		holds.sell.duration = if hold then HOLD else 0.05
		Widgets.setDisabled(holds.sell.button, #uids == 0)
		-- « Vendre » : bleu nuit sur l'or plein ; grisé (rien de choisi), l'or pâli par le panneau
		-- dessous : blanc cerné (le bleu nuit n'y lisait qu'à 2,65 ; revue des écrans)
		inkOn(Widgets.buttonLabel(holds.sell.button), #uids > 0, Widgets.Colors.Text)
		Widgets.setDisabled(holds.release.button, #uids == 0)
	end
end

-- =============================================================================================
-- Sous-niveaux (fiche d'un squishy, aperçu de Ranger, 2e étape de la vente)
-- =============================================================================================

local function closeDetail(restore: boolean)
	local d = detail
	if d == nil or not d.Visible then
		return
	end
	d.Visible = false
	local gp = gridPage
	if gp then
		gp.Visible = true
	end
	local back = detailFrom
	detailFrom = nil
	if restore and back and back.Parent and back.Visible then
		GuiService.SelectedObject = back
	end
end

local function bestFriendSlots(): number
	local R = Widgets.n(Widgets.state("R"))
	local n = 0
	for _, at in Balance.Splorch.BestFriendSlotsAt do
		if R >= at then
			n += 1
		end
	end
	return n
end

local function refreshDetail()
	local d = detail
	if d == nil or not d.Visible then
		return
	end
	local rec = squishies()[detailUid]
	if type(rec) ~= "table" or not (rec.at == "pen" or rec.at == "pool") then
		closeDetail(false)
		local first = if grid then grid.firstSelectable() else nil
		GuiService.SelectedObject = first or (if tabBar then tabBar.buttons.pens else nil)
		return
	end
	local item = itemOf(detailUid)
	Widgets.paintBlob(d:FindFirstChild("Card"):FindFirstChild("Blob") :: Frame, rec.s, true)
	Widgets.setRaw(labels.detailName, Widgets.speciesName(rec.s))
	local rdef = Rarities.List[rarityOf(rec)]
	Widgets.setText(labels.detailRarity, "rarity." .. (if rdef then rdef.key else "common"))
	labels.detailRarity.TextColor3 = Widgets.rarityColor(rarityOf(rec))
	local mdef = mutationDef(rec)
	Widgets.setText(labels.detailMutation, if mdef then "mutation." .. mdef.key else "mutation.none")
	Widgets.setText(
		labels.detailSize,
		"common.size",
		{ size = Widgets.num(if item then item.size else Widgets.n(rec.z, 1)) }
	)
	Widgets.setText(
		labels.detailIncome,
		"common.perSecond",
		{ rate = Widgets.num(if item then item.income else 0) }
	)
	Widgets.setText(labels.detailStars, "common.stars", { n = math.floor(Widgets.n(rec.st)) })
	Widgets.setText(
		Widgets.buttonLabel(detailButtons.lock) :: TextLabel,
		if rec.lk == true then "panel.ranch.unlock" else "panel.ranch.lock"
	)
	local slots = bestFriendSlots()
	for n = 1, 3 do
		local b = detailButtons["bf" .. n]
		b.Visible = n <= slots
		local isSlot = Widgets.n(rec.bf) == n
		b.BackgroundColor3 = if isSlot then Widgets.Colors.Gold else Widgets.Colors.CardLight
		-- « Meilleur Ami 1 » blanc sur l'or : 1,46 sans le contour
		inkOn(Widgets.buttonLabel(b), isSlot, Widgets.Colors.Text)
	end
	local saddle =
		Widgets.safe("Formulas.saddleLevel", 0, Formulas.saddleLevel, Widgets.n(Widgets.state("biggestEver")))
	local isMount = Widgets.state("mount") == detailUid
	Widgets.setDisabled(detailButtons.mount, saddle <= 0 or isMount, function()
		if saddle <= 0 then
			pcall(Toast.message, Prefs.t("feedback.noMount"), "info")
		end
	end)
	Widgets.setDisabled(detailButtons.toDodo, counts().dodo >= Balance.Pens.Dodo or detailUid == waitingUid())
end

local function openDetail(uid: string, from: TextButton)
	local d = detail
	if d == nil then
		return
	end
	detailUid = uid
	detailFrom = from
	local gp = gridPage
	if gp then
		gp.Visible = false
	end
	d.Visible = true
	refreshDetail()
	GuiService.SelectedObject = detailButtons.lock
end

local function closeOverlay()
	local o = overlay
	if o == nil or not o.Visible then
		return
	end
	o.Visible = false
	overlayMode = ""
	overlayUids = {}
	local gp = gridPage
	if gp then
		gp.Visible = true
	end
	local back = if current == "pens"
		then buttons.tidy
		elseif overlayAction == "Release" then holds.release.button
		else holds.sell.button
	if back and back.Parent and back.Visible then
		GuiService.SelectedObject = back
	end
end

local function openOverlay(mode: string, uids: { string }, action: string)
	local o = overlay
	if o == nil then
		return
	end
	overlayMode = mode
	overlayUids = uids
	overlayAction = action
	local card = o:FindFirstChild("Card") :: Frame
	local blob = card:FindFirstChild("Blob") :: Frame
	if mode == "tidy" then
		local total = 0
		for _, uid in uids do
			local item = itemOf(uid)
			if item then
				total += Widgets.safe("Formulas.sellValue", 0, Formulas.sellValue, item.income)
			end
		end
		Widgets.setText(labels.overlayTitle, "panel.ranch.tidy")
		Widgets.setText(
			labels.overlayLine,
			"panel.ranch.tidyPreview",
			{ n = #uids, coins = Widgets.num(total) }
		)
		Widgets.paintBlob(blob, nil, false)
	else
		-- 2e étape : la carte du squishy le plus rare, avec son « 1 sur X »
		local rarest: Item? = nil
		local best = -1
		for _, uid in uids do
			local item = itemOf(uid)
			if item and needsConfirm(item.rec) then
				local mdef = mutationDef(item.rec)
				local score = rarityOf(item.rec) * 1000 + (if mdef then mdef.mult else 0)
				if score > best then
					best = score
					rarest = item
				end
			end
		end
		Widgets.setText(labels.overlayTitle, "panel.ranch.confirmTitle")
		if rarest then
			local R = Widgets.n(Widgets.state("R"))
			local level: any =
				Widgets.safe("Formulas.vatLevel", { quality = 1, nozzles = 0 }, Formulas.vatLevel, R)
			local odds = Widgets.safe(
				"Odds.oneIn",
				0,
				Odds.oneIn,
				rarityOf(rarest.rec),
				Widgets.n(rarest.rec.m),
				Widgets.n(level.quality, 1),
				Widgets.n(level.nozzles),
				false
			)
			Widgets.setText(labels.overlayLine, "panel.ranch.confirmRare", {
				name = Widgets.speciesName(rarest.rec.s),
				odds = Widgets.num(odds),
			})
			Widgets.paintBlob(blob, rarest.rec.s, true)
		else
			Widgets.setRaw(labels.overlayLine, "")
		end
	end
	labels.overlayRelease.Visible = mode == "confirm" and action == "Release"
	local gp = gridPage
	if gp then
		gp.Visible = false
	end
	o.Visible = true
	GuiService.SelectedObject = holds.overlay.button
end

local function onOverlayHold()
	local uids = overlayUids
	if #uids == 0 then
		closeOverlay()
		return
	end
	if overlayMode == "tidy" then
		Widgets.send("Sell", uids, false)
	else
		Widgets.send(overlayAction, uids, true)
		table.clear(selected)
	end
	closeOverlay()
end

-- Squishies proposés par « Ranger » (GDD §4.13) : Communs et Peu communs, 0 étoile, sans mutation,
-- non verrouillés, ni Meilleur Ami ni monture, espèce déjà tamponnée ; le plus gros de chaque espèce
-- est toujours gardé
local function tidyCandidates(): { string }
	local dex = Widgets.tbl(Widgets.state("dex"))
	local mut = Widgets.tbl(dex.mut)
	local mount = Widgets.state("mount")
	local waiting = waitingUid()
	local G = Widgets.safe("Formulas.G", 0, Formulas.G, Widgets.state("growth"), Clock.now())
	local bySpecies: { [number]: { Item } } = {}
	for uid, rec in squishies() do
		if type(rec) == "table" and (rec.at == "pen" or rec.at == "pool" or rec.at == "dodo") then
			local s = rec.s
			if type(s) == "number" then
				bySpecies[s] = bySpecies[s] or {}
				table.insert(bySpecies[s], {
					uid = uid,
					rec = rec,
					size = Widgets.safe("Formulas.sizeAt", 1, Formulas.sizeAt, rec, G),
					income = 0,
				})
			end
		end
	end
	local out: { string } = {}
	for s, list in bySpecies do
		table.sort(list, function(a, b)
			if a.size ~= b.size then
				return a.size > b.size
			end
			return a.uid < b.uid
		end)
		local stampedSpecies = type(mut[s]) == "number" and bit32.band(mut[s], 1) ~= 0
		for i, item in list do
			local rec = item.rec
			if
				i > 1
				and stampedSpecies
				and rarityOf(rec) <= Rarities.UNCOMMON
				and Widgets.n(rec.st) == 0
				and Widgets.n(rec.m) == 0
				and rec.lk ~= true
				and Widgets.n(rec.bf) == 0
				and item.uid ~= mount
				and item.uid ~= waiting
			then
				table.insert(out, item.uid)
			end
		end
	end
	table.sort(out)
	return out
end

-- =============================================================================================
-- Dalles
-- =============================================================================================

local function tileLevel(tile: string): number
	local tiles = Widgets.tbl(Widgets.state("tiles"))
	local v = tiles[tile]
	if type(v) == "boolean" then
		return if v then 1 else 0
	end
	return math.max(0, math.floor(Widgets.n(v)))
end

local function tileInfo(tile: string): { cost: number, locked: boolean, maxed: boolean, minR: number }
	local def = (Balance.Tiles :: any)[tile]
	local R = Widgets.n(Widgets.state("R"))
	local level = tileLevel(tile)
	local cost = Widgets.safe("Formulas.tileCost", math.huge, Formulas.tileCost, tile, level, R)
	local minR = if type(def) == "table" then def.MinR else 0
	return {
		cost = cost,
		locked = R < minR,
		maxed = cost == math.huge or (type(def) == "table" and level >= def.Levels),
		minR = minR,
	}
end

local function tileOrder(): { string }
	if not keptFirst then
		return TILE_ORDER
	end
	-- dalles gardées au Grand Splorch d'abord (Enclos, Lit douillet)
	local kept, reset = {}, {}
	for _, tile in TILE_ORDER do
		local def = (Balance.Tiles :: any)[tile]
		if type(def) == "table" and def.ResetOnSplorch == false then
			table.insert(kept, tile)
		else
			table.insert(reset, tile)
		end
	end
	for _, tile in reset do
		table.insert(kept, tile)
	end
	return kept
end

local function refreshPads()
	local coins = Widgets.n(Widgets.state("coins"))
	Widgets.setText(labels.coins, "panel.ranch.coins", { coins = Widgets.num(coins) })
	for i, tile in tileOrder() do
		local b = tileButtons[tile]
		b.LayoutOrder = i
		local info = tileInfo(tile)
		local status = b:FindFirstChild("Status") :: TextLabel
		local level = b:FindFirstChild("Level") :: TextLabel
		Widgets.setText(level, "common.level", { n = tileLevel(tile) })
		if info.maxed then
			Widgets.setText(status, "panel.ranch.tileMaxed")
			status.TextColor3 = Widgets.Colors.Success
		elseif info.locked then
			Widgets.setText(status, "panel.ranch.tileLocked", { n = info.minR })
			status.TextColor3 = Widgets.Colors.TextDim
		else
			Widgets.setText(status, "panel.ranch.coins", { coins = Widgets.num(info.cost) })
			status.TextColor3 = if coins >= info.cost then Widgets.Colors.Gold else Widgets.Colors.Danger
		end
		Widgets.setDisabled(b, info.maxed or info.locked or coins < info.cost, function()
			if not info.maxed and not info.locked and coins < info.cost then
				pcall(
					Toast.message,
					Prefs.t("feedback.notEnoughCoins", { missing = Widgets.num(info.cost - coins) }),
					"warning"
				)
			end
		end)
	end
end

local function cheapestTile(): TextButton?
	local coins = Widgets.n(Widgets.state("coins"))
	local best: string? = nil
	local bestCost = math.huge
	local order = tileOrder()
	-- depuis l'aperçu du Grand Splorch : la moins chère des dalles gardées si l'une est payable
	local pools = { order }
	if keptFirst then
		local kept = {}
		for _, tile in order do
			local def = (Balance.Tiles :: any)[tile]
			if type(def) == "table" and def.ResetOnSplorch == false then
				table.insert(kept, tile)
			end
		end
		pools = { kept, order }
	end
	for _, pool in pools do
		for _, tile in pool do
			local info = tileInfo(tile)
			if not info.maxed and not info.locked and info.cost <= coins and info.cost < bestCost then
				best, bestCost = tile, info.cost
			end
		end
		if best then
			break
		end
	end
	return tileButtons[best or order[1]]
end

-- =============================================================================================
-- Style
-- =============================================================================================

local function cosmeticUnlocked(kind: string, id: string): boolean
	if id == "" then
		return true
	end
	local cos = Widgets.tbl(Widgets.state("cosmetics"))
	if cos[kind] == id then
		return true
	end
	local def = Cosmetics.ByKindId[kind .. ":" .. id]
	if def == nil then
		return false
	end
	local source = def.source
	if source.kind == "free" then
		return true
	elseif source.kind == "plopDay" then
		return Widgets.n(Widgets.state("plopDays")) >= (source.value or math.huge)
	elseif source.kind == "dex" then
		return Widgets.n(Widgets.tbl(Widgets.state("dex")).rewards) >= (source.value or math.huge)
	elseif source.kind == "pass" then
		return Widgets.tbl(Widgets.state("passes"))[source.key or ""] == true
	elseif source.kind == "product" then
		local owned = Widgets.tbl(Widgets.tbl(Widgets.state("outfits")).owned)
		return Widgets.n(owned[id]) > 0
	elseif source.kind == "rebirth" then
		return Widgets.n(Widgets.state("R")) >= (source.value or math.huge)
	elseif source.kind == "weekly" then
		return sessionUnlocks[kind .. ":" .. id] == true
	end
	return false
end

local function sourceText(def: Cosmetics.CosmeticDef): string
	local source = def.source
	return Prefs.t("cosmetic.source." .. source.kind, { n = source.value or 0 })
end

local function styleEntries(kind: string): { { kind: string, id: string } }
	local out: { { kind: string, id: string } } = {}
	local realKind = if kind == "outfits" then "outfit" else kind
	if NONE_KINDS[kind] then
		table.insert(out, { kind = kind, id = "" })
	end
	local defs = {}
	for _, def in Cosmetics.List do
		if def.kind == realKind then
			table.insert(defs, def)
		end
	end
	table.sort(defs, function(a, b)
		return a.order < b.order
	end)
	for _, def in defs do
		table.insert(out, { kind = realKind, id = def.id })
	end
	return out
end

local function refreshStyleV13()
	for kind, b in styleKindButtons do
		b.BackgroundColor3 = if kind == styleKind then Widgets.Colors.Accent else Widgets.Colors.Card
	end
	local entries = styleEntries(styleKind)
	local cos = Widgets.tbl(Widgets.state("cosmetics"))
	local owned = Widgets.tbl(Widgets.tbl(Widgets.state("outfits")).owned)
	for i, cell in styleCells do
		local e = entries[i]
		cell.button.Visible = e ~= nil
		if e then
			cell.kind = e.kind
			cell.id = e.id
			if e.id == "" then
				Widgets.setText(cell.name, "panel.ranch.style.none")
			else
				Widgets.setText(cell.name, "cosmetic." .. e.kind .. "." .. e.id)
			end
			local def = Cosmetics.ByKindId[e.kind .. ":" .. e.id]
			cell.swatch.Visible = def ~= nil and def.color ~= nil
			if def and def.color then
				cell.swatch.BackgroundColor3 = def.color
			end
			local unlocked = cosmeticUnlocked(e.kind, e.id)
			local equipped
			if e.kind == "outfit" then
				equipped = false
				unlocked = Widgets.n(owned[e.id]) > 0
			else
				equipped = (cos[e.kind] or "") == e.id
			end
			cell.button:SetAttribute("Locked", not unlocked)
			if equipped then
				Widgets.setText(cell.status, "panel.ranch.style.equipped")
				-- blanc sur la case verte (vert sur vert : contraste 1,98 ; revue de l'outil d'écrans)
				cell.status.TextColor3 = Widgets.Colors.Text
			elseif not unlocked and def then
				Widgets.setRaw(cell.status, sourceText(def))
				cell.status.TextColor3 = Widgets.Colors.TextDim
			elseif e.kind == "outfit" then
				Widgets.setText(
					cell.status,
					"panel.shop.outfitOwned",
					{ n = math.floor(Widgets.n(owned[e.id])) }
				)
				cell.status.TextColor3 = Widgets.Colors.Text
			else
				Widgets.setText(cell.status, "panel.ranch.style.equip")
				cell.status.TextColor3 = Widgets.Colors.Text
			end
			cell.button.BackgroundColor3 = if equipped
				then Widgets.Colors.Success:Lerp(Widgets.Colors.Card, 0.4)
				elseif unlocked then Widgets.Colors.CardLight
				else Widgets.Colors.Locked
			cell.button:SetAttribute("TvNav", e.kind == "outfit" and unlocked)
		end
	end
end

local function equippedStyleCell(): GuiObject?
	local cos = Widgets.tbl(Widgets.state("cosmetics"))
	for _, cell in styleCells do
		if cell.button.Visible and cell.kind ~= "outfit" and (cos[cell.kind] or "") == cell.id then
			return cell.button
		end
	end
	for _, cell in styleCells do
		if cell.button.Visible then
			return cell.button
		end
	end
	return nil
end

local function onStyleCell(cell: StyleCell)
	if cell.button:GetAttribute("Locked") == true then
		Widgets.refuse(cell.button)
		return
	end
	if cell.kind == "outfit" then
		if nav then
			nav.open("OutfitPreview", cell.id)
		end
		return
	end
	local cos = Widgets.tbl(Widgets.state("cosmetics"))
	if (cos[cell.kind] or "") == cell.id then
		return -- déjà équipé
	end
	Widgets.send("EquipCosmetic", cell.kind, cell.id)
end

-- =============================================================================================
-- Mon style (v2.0, lot B3, étape 3 ; plan B3 D10, D11, D24, D25) : parties construites à la première
-- ouverture qui en a besoin, jamais interrupteurs coupés ; sur ce chemin, les parties de la v1.3
-- (6 sous-listes, 15 cases) ne sont pas construites (elles le sont à l'ouverture suivante si le chemin
-- de la v1.3 revient)
-- =============================================================================================

-- Chemin Mon style : profil v2 et au moins un interrupteur v2.0 annoncé par le serveur (D10)
local function styleV2(): boolean
	if not MetaFlags.v2Profile() then
		return false
	end
	for _, flag in MetaFlags.FLAGS do
		if MetaFlags.on(flag) then
			return true
		end
	end
	return false
end

local function lang(): string
	local ok, l = pcall(Prefs.language)
	return if ok and l == "fr" then "fr" else "en"
end

local function metaCtx(): MetaView.Ctx
	return { lang = lang(), on = MetaFlags.on }
end

-- Profil répliqué sur les clés que lisent Logic/Owned et Logic/Prestige (possession, D10, D11)
local OWNED_KEYS = {
	"version",
	"R",
	"bestR",
	"ascend",
	"atelierCosmetics",
	"atelier",
	"stats",
	"weeklyTrack",
	"biggestEver",
	"season",
	"plopDays",
	"dex",
	"moon",
	"decoPerso",
}

-- MON ranch porte l'attribut DecoPerso (interrupteur DecoPerso ouvert sur le serveur, profil v2)
local function decoOpen(): boolean
	return type(MetaFlags.attr("DecoPerso")) == "string"
end

-- Sortes de Mon style montrées (D10) : Déco perso seulement avec l'attribut ; palette et coussins
-- seulement quand une de leurs sources est ouverte (Owned.kindOpen)
local function kindsFor(): { string }
	local flags = MetaFlags.owned()
	local out = {}
	for _, kind in MetaView.STYLE_KINDS do
		if kind == "deco" then
			if decoOpen() then
				table.insert(out, kind)
			end
		elseif kind == "palette" or kind == "cushions" then
			if Owned.kindOpen(kind, flags) then
				table.insert(out, kind)
			end
		else
			table.insert(out, kind)
		end
	end
	return out
end

local function kindKey(kind: string): string
	return if kind == "deco" then "deco.title" else "panel.ranch.style." .. kind
end

local function worn(kind: string): string
	local value = Widgets.tbl(Widgets.state("cosmetics"))[kind]
	return if type(value) == "string" then value else ""
end

-- Entrées d'une sorte (sauf Déco perso) : possession v1.3 par cosmeticUnlocked (inchangée), v2.0 par
-- Logic/Owned avec les interrupteurs annoncés, tenues par outfits.owned (D10)
local function styleEntriesV2(kind: string): { V2Entry }
	local out: { V2Entry } = {}
	local profile = Widgets.profile(OWNED_KEYS)
	local flags = MetaFlags.owned()
	local owned = Widgets.tbl(Widgets.tbl(Widgets.state("outfits")).owned)
	for _, item in MetaView.styleItems(kind, metaCtx()) do
		local unlocked: boolean
		if item.kind == "outfit" then
			unlocked = Widgets.n(owned[item.id]) > 0
		elseif item.id == "" then
			unlocked = true
		elseif item.v2 then
			unlocked = worn(item.kind) == item.id or Owned.cosmetic(profile, item.kind, item.id, flags)
		else
			unlocked = cosmeticUnlocked(item.kind, item.id)
		end
		table.insert(out, {
			kind = item.kind,
			id = item.id,
			n = 0,
			name = item.name,
			source = item.source,
			color = item.color,
			unlocked = unlocked,
			equipped = item.kind ~= "outfit" and worn(item.kind) == item.id,
		})
	end
	return out
end

-- Objet n de Déco perso possédé : même règle que le serveur (bit de decoPerso.owned, ou source
-- gagnée : Owned.deco ; CommunityService.onPlaceDeco)
local function decoOwned(profile: { [string]: any }, n: number, flags: Owned.Flags): boolean
	local deco = profile.decoPerso
	local bits = if type(deco) == "table" then deco.owned else nil
	return Bitset.has(bits, n) or Owned.deco(profile, n, flags)
end

-- Choix d'un objet pour l'emplacement `slot` (D11) : « Aucun », objets possédés de SA taille, puis
-- verrouillés (grisés, avec leur source) ; un objet posé dans un AUTRE emplacement n'est pas proposé
-- (le serveur refuserait : jamais deux fois)
local function pickerEntries(slot: number): { V2Entry }
	local current = decoContents[slot] or 0
	local out: { V2Entry } = {
		{
			kind = "deco",
			id = "",
			n = 0,
			name = { key = "panel.ranch.style.none" },
			unlocked = true,
			equipped = current == 0,
		},
	}
	local size = Cosmetics.DecoSlots[slot]
	if size == nil then
		return out
	end
	local elsewhere: { [number]: boolean } = {}
	for i, n in decoContents do
		if i ~= slot and n > 0 then
			elsewhere[n] = true
		end
	end
	local profile = Widgets.profile(OWNED_KEYS)
	local flags = MetaFlags.owned()
	local locked: { V2Entry } = {}
	for _, item in MetaView.decoItems(size, metaCtx()) do
		if not elsewhere[item.n] then
			local own = item.n == current or decoOwned(profile, item.n, flags)
			table.insert(if own then out else locked, {
				kind = "deco",
				id = item.id,
				n = item.n,
				name = item.name,
				source = item.source,
				unlocked = own,
				equipped = item.n == current,
			})
		end
	end
	for _, e in locked do
		table.insert(out, e)
	end
	return out
end

local function setTextOf(label: TextLabel, t: MetaView.Text?)
	if t == nil then
		Widgets.setRaw(label, "")
		return
	end
	Widgets.setText(label, t.key, t.vars)
end

local function bindV2Cell(cell: V2Cell, index: number)
	local e = v2Entries[index]
	cell.button.Visible = e ~= nil
	if e == nil then
		cell.index = 0
		return
	end
	cell.index = index
	setTextOf(cell.name, e.name)
	cell.swatch.Visible = e.color ~= nil
	if e.color then
		cell.swatch.BackgroundColor3 = e.color
	end
	cell.lock.Visible = not e.unlocked
	cell.button:SetAttribute("Locked", not e.unlocked)
	if e.equipped then
		Widgets.setText(cell.status, "panel.ranch.style.equipped")
		cell.status.TextColor3 = Widgets.Colors.Text
	elseif not e.unlocked then
		setTextOf(cell.status, e.source)
		cell.status.TextColor3 = Widgets.Colors.TextDim
	elseif e.kind == "outfit" then
		local owned = Widgets.tbl(Widgets.tbl(Widgets.state("outfits")).owned)
		Widgets.setText(cell.status, "panel.shop.outfitOwned", { n = math.floor(Widgets.n(owned[e.id])) })
		cell.status.TextColor3 = Widgets.Colors.Text
	else
		Widgets.setText(cell.status, "panel.ranch.style.equip")
		cell.status.TextColor3 = Widgets.Colors.Text
	end
	cell.button.BackgroundColor3 = if e.equipped
		then Widgets.Colors.Success:Lerp(Widgets.Colors.Card, 0.4)
		elseif e.unlocked then Widgets.Colors.CardLight
		else Widgets.Colors.Locked
	-- tenue possédée : ouvre la garde-robe (OutfitPreview) ; emplacement : ouvre son choix
	cell.button:SetAttribute("TvNav", e.kind == "outfit" and e.unlocked)
end

local function bindKindRow(row: KindRow, _frame: Frame, index: number)
	local kind = kindsV2[index]
	row.kind = kind or ""
	if kind then
		local label = Widgets.buttonLabel(row.button)
		if label then
			Widgets.setText(label, kindKey(kind))
		end
		row.button.BackgroundColor3 = if kind == styleKind then Widgets.Colors.Accent else Widgets.Colors.Card
	end
end

-- Plan (D11) : nom de l'objet posé (deco.<id>) ou « Emplacement libre », d'après l'attribut DecoPerso
-- de MON ranch (RanchLook.decoPerso : valeur hostile = emplacements vides) ; aucune instance créée
local function bindPlan()
	for i, b in slotButtons do
		local n = decoContents[i] or 0
		local def = if n > 0 then Cosmetics.DecoPerso[n] else nil
		local label = Widgets.buttonLabel(b)
		if label then
			if def then
				Widgets.setText(label, def.key)
				label.TextColor3 = Widgets.Colors.Text
			else
				Widgets.setText(label, "deco.empty")
				label.TextColor3 = Widgets.Colors.TextDim
			end
		end
		b.BackgroundColor3 = if def
			then Widgets.Colors.Success:Lerp(Widgets.Colors.Card, 0.4)
			else Widgets.Colors.CardLight
		b:SetAttribute("DecoItem", n)
	end
end

-- Modèle de MON ranch (Wobbleton/Ranches/<slot>) : l'attribut DecoPerso y est écrit par le serveur
local function myRanchModel(): Instance?
	local ok, slot = pcall(WorldStateController.mySlot)
	if not ok or type(slot) ~= "number" or slot <= 0 then
		return nil
	end
	local world = workspace:FindFirstChild("Wobbleton")
	local list = world and world:FindFirstChild("Ranches")
	return if list then list:FindFirstChild(Format.id(slot)) else nil
end

local refreshStyle: () -> ()

-- Plan relié quand l'attribut DecoPerso de MON ranch change (connexion refaite si le ranch change ;
-- chemin v2.0 seulement : jamais interrupteurs coupés)
local function watchDeco()
	local model = myRanchModel()
	if model == decoModel then
		return
	end
	local old = decoConn
	decoConn = nil
	if old then
		old:Disconnect()
	end
	decoModel = model
	if model then
		decoConn = model:GetAttributeChangedSignal("DecoPerso"):Connect(function()
			if isOpen and current == "style" and styleMode == "v2" then
				refreshStyle()
			end
		end)
	end
end

local function refreshStyleV2()
	local kRows, iRows, plan = kindRows, itemRows, planFrame
	if kRows == nil or iRows == nil or plan == nil then
		return
	end
	kindsV2 = kindsFor()
	if not table.find(kindsV2, styleKind) then
		styleKind = kindsV2[1]
		pickerSlot = 0
	end
	if styleKind ~= "deco" then
		pickerSlot = 0
	end
	watchDeco()
	decoContents = RanchLook.decoPerso(MetaFlags.attr("DecoPerso"))
	kRows.setCount(#kindsV2)
	kRows.refresh()
	local showPlan = styleKind == "deco" and pickerSlot == 0
	if showPlan then
		v2Entries = {}
		bindPlan()
	elseif styleKind == "deco" then
		v2Entries = pickerEntries(pickerSlot)
	else
		v2Entries = styleEntriesV2(styleKind)
	end
	plan.Visible = showPlan
	iRows.frame.Visible = not showPlan
	iRows.setCount(math.ceil(#v2Entries / V2_COLS))
	iRows.refresh()
end

-- Style : le chemin choisi à l'ouverture (D10)
refreshStyle = function()
	if styleMode == "v2" then
		refreshStyleV2()
	elseif styleMode == "v13" then
		refreshStyleV13()
	end
end

-- Case de l'objet équipé (sinon la 1re case) de la grille de Mon style
local function selectedV2Cell(): GuiObject?
	local rows = itemRows
	if rows == nil or #v2Entries == 0 then
		return nil
	end
	local index = 1
	for i, e in v2Entries do
		if e.equipped then
			index = i
			break
		end
	end
	return rows.selectableAt((index - 1) // V2_COLS + 1, (index - 1) % V2_COLS + 1)
end

local function kindButtonV2(kind: string): GuiObject?
	local rows = kindRows
	local i = table.find(kindsV2, kind)
	if rows == nil or i == nil then
		return nil
	end
	return rows.selectableAt(i, 1)
end

-- ○ sur le choix d'un objet : revient au plan, sélection sur son emplacement
local function closePicker(focus: boolean)
	local slot = pickerSlot
	pickerSlot = 0
	refreshStyle()
	local b = slotButtons[slot]
	if focus and b then
		GuiService.SelectedObject = b
	end
end

-- ✕ sur un emplacement du plan : son choix dans la grille (sélection : l'objet posé, ou « Aucun »)
local function openPicker(slot: number)
	local b = slotButtons[slot]
	if b == nil then
		return
	end
	if not styleV2() or not decoOpen() then
		Widgets.refuse(b)
		return
	end
	pickerSlot = slot
	refreshStyle()
	local target = selectedV2Cell()
	if target then
		GuiService.SelectedObject = target
	end
end

-- ✕ dans le choix : PlaceDeco(n, emplacement), ou PlaceDeco(0, emplacement) pour « Aucun » sur un
-- emplacement occupé ; rien quand l'objet y est déjà (D11 ; le plan suit l'attribut, jamais deviné)
local function pickDeco(e: V2Entry)
	local slot = pickerSlot
	if slot < 1 or slotButtons[slot] == nil then
		return
	end
	local here = decoContents[slot] or 0
	if e.n ~= here then
		Widgets.send("PlaceDeco", e.n, slot)
	end
	closePicker(true)
end

local function onV2Cell(cell: V2Cell)
	local e = v2Entries[cell.index]
	if e == nil then
		return
	end
	-- verrouillé, ou interrupteur coupé pendant l'écran : refusé, rien n'est envoyé
	if not e.unlocked or not styleV2() then
		Widgets.refuse(cell.button)
		return
	end
	if e.kind == "deco" then
		pickDeco(e)
		return
	end
	if e.kind == "outfit" then
		if nav then
			nav.open("OutfitPreview", e.id)
		end
		return
	end
	if worn(e.kind) == e.id then
		return -- déjà équipé
	end
	-- palette et coussins : « Aucun » → "" (couleur du ranch)
	Widgets.send("EquipCosmetic", e.kind, e.id)
end

local function onKindV2(row: KindRow)
	local kind = row.kind
	if kind == "" then
		return
	end
	styleKind = kind
	pickerSlot = 0
	refreshStyle()
	local target = if kind == "deco" then slotButtons[1] else selectedV2Cell()
	if target then
		GuiService.SelectedObject = target
	end
end

-- =============================================================================================
-- Rafraîchissement
-- =============================================================================================

-- Dalles retirées tant que l'écran Améliorations est disponible (N8, D12)
local function padsHidden(): boolean
	return UpgradeSnapshot.available()
end

-- Onglet Dalles caché ou montré selon le chemin ; vrai si l'onglet courant a dû changer
local function syncPads(): boolean
	local hidden = padsHidden()
	if tabBar then
		tabBar.setVisible("pads", not hidden)
	end
	if hidden and current == "pads" then
		current = "pens"
		keptFirst = false
		return true
	end
	return false
end

-- Parties de Style du chemin courant visibles, les autres cachées ; libellé de l'onglet (D10)
local function applyStyleMode()
	local v2 = styleMode == "v2"
	if v13Kinds then
		v13Kinds.Visible = not v2
	end
	if v13Items then
		v13Items.Visible = not v2
	end
	if kindRows then
		kindRows.frame.Visible = v2
	end
	if itemRows then
		itemRows.frame.Visible = v2
	end
	if planFrame and not v2 then
		planFrame.Visible = false
	end
	local styleTab = if tabBar then tabBar.buttons.style else nil
	local label = if styleTab then Widgets.buttonLabel(styleTab) else nil
	if label then
		Widgets.setText(label, if v2 then "panel.ranch.tab.myStyle" else "panel.ranch.tab.style")
	end
end

-- 1re sorte du chemin de Style courant (v1.3 : Selle ; Mon style : habillage)
local function firstStyleKind(): string
	if styleMode == "v2" then
		return kindsFor()[1] or "theme"
	end
	return STYLE_KINDS[1]
end

local function showTab()
	if tabBar then
		tabBar.setActive(current)
	end
	if pages.pads then
		pages.pads.Visible = current == "pads"
	end
	if pages.style then
		pages.style.Visible = current == "style"
	end
	if detail then
		detail.Visible = false
	end
	if overlay then
		overlay.Visible = false
	end
	local gp = gridPage
	if gp then
		gp.Visible = GRID_TABS[current] == true
	end
end

local function refresh()
	if tabBar == nil then
		return
	end
	-- instantané arrivé ou parti écran ouvert : l'onglet Dalles suit (sans rien construire)
	if syncPads() then
		showTab()
	end
	-- chemin de Style changé écran ouvert : bascule seulement si ses parties sont déjà construites
	-- (sinon à l'ouverture suivante ; jamais d'instance créée écran ouvert)
	local wantStyle = if styleV2() then "v2" else "v13"
	if wantStyle ~= styleMode and (if wantStyle == "v2" then v2Built else v13Built) then
		styleMode = wantStyle
		pickerSlot = 0
		applyStyleMode()
		styleKind = firstStyleKind()
	end
	if GRID_TABS[current] then
		items = itemsFor(current)
		-- sélection multiple et choix A : seulement des squishies encore là
		local present: { [string]: boolean } = {}
		for _, item in items do
			present[item.uid] = true
		end
		for uid in selected do
			if not present[uid] then
				selected[uid] = nil
			end
		end
		if fuseA ~= "" and not present[fuseA] then
			fuseA = ""
		end
		local g = grid :: Widgets.Rows
		g.setCount(math.ceil(#items / COLS))
		g.refresh()
		labels.empty.Visible = #items == 0
		refreshBars()
		refreshDetail()
	elseif current == "pads" then
		if padsBuilt then
			refreshPads()
		end
	elseif current == "style" then
		refreshStyle()
	end
end

-- ✕ sur une case de la grille (selon l'onglet)
function Ranch._activateCell(uid: string, button: TextButton)
	local rec = squishies()[uid]
	if type(rec) ~= "table" then
		return
	end
	if current == "pens" then
		openDetail(uid, button)
	elseif current == "dodo" then
		if counts().pen >= penCapacity() then
			Widgets.refuse(button)
			pcall(Toast.message, Prefs.t("feedback.penFull"), "warning")
			return
		end
		Widgets.send("MoveSquishy", uid, "pen")
	elseif current == "mail" then
		local c = counts()
		if c.pen >= penCapacity() and c.dodo >= Balance.Pens.Dodo then
			Widgets.refuse(button)
			pcall(Toast.message, Prefs.t("feedback.dodoFull"), "warning")
			return
		end
		Widgets.send("ClaimMail", uid)
	elseif current == "fuse" then
		if fuseA == "" then
			fuseA = uid
			refresh()
		elseif uid == fuseA then
			fuseA = ""
			refresh()
		else
			Widgets.send("FuseMenu", fuseA, uid)
			fuseA = ""
			refresh()
		end
	elseif current == "sell" then
		selected[uid] = if selected[uid] then nil else true
		refresh()
	end
end

local function onSellHold(action: string)
	local uids = selectedUids()
	if #uids == 0 then
		return
	end
	local confirm = false
	for _, uid in uids do
		local item = itemOf(uid)
		if item and needsConfirm(item.rec) then
			confirm = true
		end
	end
	if confirm then
		openOverlay("confirm", uids, action)
		return
	end
	Widgets.send(action, uids, false)
	table.clear(selected)
	refresh()
end

-- =============================================================================================
-- Construction
-- =============================================================================================

local function bar(page: Frame, tab: string): Frame
	local f = Widgets.group(page, "Bar_" .. tab, UDim2.new(1, -96, 0, BAR_H), UDim2.fromOffset(48, 0))
	bars[tab] = f
	return f
end

local function countLabel(parent: Frame, name: string): TextLabel
	return Widgets.label({
		parent = parent,
		name = name,
		size = UDim2.fromOffset(220, BAR_H),
		position = UDim2.new(),
		text = "",
		textSize = 40,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
end

local function buildGridPage(container: Frame, top: number)
	local width = container.Size.X.Offset
	local page = Widgets.group(
		container,
		"Page_grid",
		UDim2.fromOffset(width, container.Size.Y.Offset - top),
		UDim2.fromOffset(0, top)
	)
	gridPage = page
	pages.grid = page
	-- Enclos : nombre, Trier, Tout fusionner, Ranger
	local pens = bar(page, "pens")
	labels.pensCount = countLabel(pens, "Count")
	buttons.sort = Widgets.button({
		parent = pens,
		name = "Sort",
		size = UDim2.fromOffset(260, BAR_H),
		position = UDim2.new(1, -2 * (300 + BAR_GAP) - 260, 0, 0),
		text = "",
		textSize = 36,
		onActivate = function()
			sortMode = (sortMode % #SORTS) + 1
			refresh()
		end,
	})
	buttons.mergeAll = Widgets.button({
		parent = pens,
		name = "MergeAll",
		size = UDim2.fromOffset(300, BAR_H),
		position = UDim2.new(1, -2 * 300 - BAR_GAP, 0, 0),
		key = "panel.ranch.mergeAll",
		textSize = 36,
		color = Widgets.Colors.Pink,
		onActivate = function()
			Ranch._mergeAll(buttons.mergeAll)
		end,
	})
	buttons.tidy = Widgets.button({
		parent = pens,
		name = "Tidy",
		size = UDim2.fromOffset(300, BAR_H),
		position = UDim2.new(1, -300, 0, 0),
		key = "panel.ranch.tidy",
		textSize = 36,
		nav = true,
		onActivate = function()
			local uids = tidyCandidates()
			if #uids == 0 then
				Widgets.refuse(buttons.tidy)
				pcall(Toast.message, Prefs.t("panel.ranch.tidyNone"), "info")
				return
			end
			openOverlay("tidy", uids, "Sell")
		end,
	})
	-- Dodo, Lettres : nombre
	labels.dodoCount = countLabel(bar(page, "dodo"), "Count")
	labels.mailCount = countLabel(bar(page, "mail"), "Count")
	-- Fusionner : Choisir A / B, Tout fusionner
	local fuse = bar(page, "fuse")
	buttons.chooseA = Widgets.button({
		parent = fuse,
		name = "ChooseA",
		size = UDim2.fromOffset(300, BAR_H),
		position = UDim2.new(),
		key = "panel.ranch.chooseA",
		textSize = 36,
		color = Widgets.Colors.Accent,
		onActivate = function()
			local first = if grid then grid.firstSelectable() else nil
			if first then
				GuiService.SelectedObject = first
			else
				Widgets.refuse(buttons.chooseA)
			end
		end,
	})
	labels.onlyTwins = Widgets.label({
		parent = fuse,
		name = "OnlyTwins",
		size = UDim2.fromOffset(460, BAR_H),
		position = UDim2.fromOffset(300 + BAR_GAP, 0),
		key = "panel.ranch.onlyTwins",
		textSize = 32,
		color = Widgets.Colors.Pink,
		xAlign = Enum.TextXAlignment.Left,
	})
	buttons.fuseAll = Widgets.button({
		parent = fuse,
		name = "MergeAll",
		size = UDim2.fromOffset(300, BAR_H),
		position = UDim2.new(1, -300, 0, 0),
		key = "panel.ranch.mergeAll",
		textSize = 36,
		color = Widgets.Colors.Pink,
		onActivate = function()
			Ranch._mergeAll(buttons.fuseAll)
		end,
	})
	-- Vendre / Relâcher : sélection, valeur, Vendre, Relâcher
	local sell = bar(page, "sell")
	labels.selected = Widgets.label({
		parent = sell,
		name = "Selected",
		size = UDim2.fromOffset(260, BAR_H),
		position = UDim2.new(),
		text = "",
		textSize = 36,
		xAlign = Enum.TextXAlignment.Left,
	})
	labels.value = Widgets.label({
		parent = sell,
		name = "Value",
		size = UDim2.fromOffset(200, BAR_H),
		position = UDim2.fromOffset(270, 0),
		text = "",
		textSize = 36,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	holds.sell = Widgets.hold({
		parent = sell,
		name = "Sell",
		size = UDim2.fromOffset(360, BAR_H),
		position = UDim2.new(1, -2 * 360 - BAR_GAP, 0, 0),
		key = "panel.ranch.sell",
		duration = HOLD,
		textSize = 36,
		color = Widgets.Colors.Gold,
		onComplete = function()
			onSellHold("Sell")
		end,
		canStart = function(): boolean
			return #selectedUids() > 0
		end,
	})
	-- « Vendre » blanc sur l'or : 1,46 sans le contour (revue des écrans)
	inkOn(Widgets.buttonLabel(holds.sell.button), true, Widgets.Colors.Text)
	holds.release = Widgets.hold({
		parent = sell,
		name = "Release",
		size = UDim2.fromOffset(360, BAR_H),
		position = UDim2.new(1, -360, 0, 0),
		key = "panel.ranch.release",
		duration = HOLD,
		textSize = 36,
		color = Widgets.Colors.Accent,
		onComplete = function()
			onSellHold("Release")
		end,
		canStart = function(): boolean
			return #selectedUids() > 0
		end,
	})
	-- grille virtualisée (6 colonnes de 208 × 232, 2,5 rangées visibles)
	local gridW = COLS * CELL.w + (COLS - 1) * GAP
	local gridTop = BAR_H + GAP
	labels.empty = Widgets.label({
		parent = page,
		name = "Empty",
		size = UDim2.fromOffset(gridW, 56),
		position = UDim2.fromOffset(math.floor((width - gridW) / 2), gridTop + 40),
		key = "common.empty",
		textSize = 40,
		color = Widgets.Colors.TextDim,
	})
	grid = Widgets.rows({
		parent = page,
		name = "Grid",
		size = Vector2.new(gridW, page.Size.Y.Offset - gridTop - 8),
		position = UDim2.fromOffset(math.floor((width - gridW) / 2), gridTop),
		rowHeight = CELL.h,
		gap = GAP,
		makeRow = function(frame: Frame, _slot: number): Row
			local cells = {}
			for c = 1, COLS do
				cells[c] = makeCell(frame, c)
			end
			return { cells = cells }
		end,
		bindRow = bindRow,
		selectables = function(row: Row): { GuiObject }
			local out = {}
			for _, cell in row.cells do
				table.insert(out, cell.button)
			end
			return out
		end,
	})
end

local function buildDetail(container: Frame, top: number)
	local width = container.Size.X.Offset
	local d = Widgets.group(
		container,
		"Detail",
		UDim2.fromOffset(width, container.Size.Y.Offset - top),
		UDim2.fromOffset(0, top)
	)
	d.Visible = false
	detail = d
	local card = Widgets.frame({
		parent = d,
		name = "Card",
		size = UDim2.fromOffset(520, 560),
		position = UDim2.fromOffset(48, 0),
		color = Widgets.Colors.Card,
		gradient = true,
	})
	local blob = Widgets.blob(card, "Blob")
	blob.AnchorPoint = Vector2.new(0.5, 0)
	blob.Position = UDim2.new(0.5, 0, 0, 20)
	blob.Size = UDim2.fromOffset(190, 160)
	local y = 196
	for _, spec in
		{
			{ "detailName", 44 },
			{ "detailRarity", 32 },
			{ "detailMutation", 32 },
			{ "detailStars", 32 },
			{ "detailSize", 32 },
			{ "detailIncome", 32 },
		}
	do
		labels[spec[1]] = Widgets.label({
			parent = card,
			name = spec[1],
			size = UDim2.new(1, -32, 0, spec[2] + 12),
			position = UDim2.fromOffset(16, y),
			text = "",
			textSize = spec[2],
		})
		y += spec[2] + 18
	end
	local col = 48 + 520 + 48
	local bw = width - col - 48
	local by = 0
	local function action(name: string, key: string, vars: { [string]: any }?, fn: () -> ()): TextButton
		local b = Widgets.button({
			parent = d,
			name = name,
			size = UDim2.fromOffset(bw, Layout.Button.MinHeight),
			position = UDim2.fromOffset(col, by),
			key = key,
			vars = vars,
			textSize = 36,
			onActivate = fn,
		})
		by += Layout.Button.MinHeight + GAP
		detailButtons[name] = b
		return b
	end
	action("lock", "panel.ranch.lock", nil, function()
		local rec = squishies()[detailUid]
		if type(rec) == "table" then
			Widgets.send("SetLock", detailUid, not (rec.lk == true))
		end
	end)
	for n = 1, 3 do
		action("bf" .. n, "panel.ranch.bestFriendSlot", { n = n }, function()
			Widgets.send("SetBestFriend", detailUid, n)
		end)
	end
	action("mount", "panel.ranch.mount", nil, function()
		Widgets.send("SetMount", detailUid)
	end)
	action("toDodo", "panel.ranch.toDodo", nil, function()
		if Widgets.send("MoveSquishy", detailUid, "dodo") then
			closeDetail(true)
		end
	end)
	Widgets.setDisabled(detailButtons.mount, false, function()
		pcall(Toast.message, Prefs.t("feedback.noMount"), "info")
	end)
end

local function buildOverlay(container: Frame, top: number)
	local width = container.Size.X.Offset
	local o = Widgets.group(
		container,
		"Overlay",
		UDim2.fromOffset(width, container.Size.Y.Offset - top),
		UDim2.fromOffset(0, top)
	)
	o.Visible = false
	overlay = o
	local card = Widgets.frame({
		parent = o,
		name = "Card",
		size = UDim2.fromOffset(820, 580),
		position = UDim2.new(0.5, 0, 0, 0),
		anchor = Vector2.new(0.5, 0),
		color = Widgets.Colors.Card,
		gradient = true,
	})
	labels.overlayTitle = Widgets.label({
		parent = card,
		name = "Title",
		size = UDim2.new(1, -48, 0, 60),
		position = UDim2.fromOffset(24, 16),
		text = "",
		textSize = 48,
	})
	local blob = Widgets.blob(card, "Blob")
	blob.AnchorPoint = Vector2.new(0.5, 0)
	blob.Position = UDim2.new(0.5, 0, 0, 90)
	blob.Size = UDim2.fromOffset(180, 150)
	labels.overlayLine = Widgets.label({
		parent = card,
		name = "Line",
		size = UDim2.new(1, -48, 0, 100),
		position = UDim2.fromOffset(24, 256),
		text = "",
		textSize = 40,
		wrapped = true,
		color = Widgets.Colors.Gold,
	})
	labels.overlayRelease = Widgets.label({
		parent = card,
		name = "Release",
		size = UDim2.new(1, -48, 0, 48),
		position = UDim2.fromOffset(24, 360),
		key = "panel.ranch.releaseLine",
		textSize = 32,
	})
	holds.overlay = Widgets.hold({
		parent = card,
		name = "Confirm",
		size = UDim2.fromOffset(520, Layout.Button.MainHeight),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		key = "panel.ranch.holdToConfirm",
		duration = HOLD,
		textSize = 40,
		onComplete = onOverlayHold,
	})
end

local function buildPads(container: Frame, top: number)
	local width = container.Size.X.Offset
	local page = Widgets.group(
		container,
		"Page_pads",
		UDim2.fromOffset(width, container.Size.Y.Offset - top),
		UDim2.fromOffset(0, top)
	)
	page.Visible = false
	pages.pads = page
	padsBuilt = true
	labels.coins = Widgets.label({
		parent = page,
		name = "Coins",
		size = UDim2.fromOffset(width - 96, 56),
		position = UDim2.fromOffset(48, 0),
		text = "",
		textSize = 44,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	local list = Widgets.group(
		page,
		"List",
		UDim2.fromOffset(width - 96, page.Size.Y.Offset - 72),
		UDim2.fromOffset(48, 72)
	)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for i, tile in TILE_ORDER do
		local b = Widgets.button({
			parent = list,
			name = "Tile_" .. tile,
			size = UDim2.new(1, 0, 0, 120),
			color = Widgets.Colors.CardLight,
			order = i,
			onActivate = function()
				Widgets.send("BuyTile", tile)
			end,
		})
		Widgets.label({
			parent = b,
			name = "Name",
			size = UDim2.fromOffset(520, 56),
			position = UDim2.new(0, 24, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			key = "pad." .. tile,
			textSize = 44,
			xAlign = Enum.TextXAlignment.Left,
			zIndex = b.ZIndex + 1,
		})
		Widgets.label({
			parent = b,
			name = "Level",
			size = UDim2.fromOffset(200, 48),
			position = UDim2.new(0, 560, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			text = "",
			textSize = 36,
			color = Widgets.Colors.TextDim,
			zIndex = b.ZIndex + 1,
		})
		Widgets.label({
			parent = b,
			name = "Status",
			size = UDim2.fromOffset(460, 56),
			position = UDim2.new(1, -24, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			text = "",
			textSize = 40,
			xAlign = Enum.TextXAlignment.Right,
			zIndex = b.ZIndex + 1,
		})
		tileButtons[tile] = b
	end
end

-- Parties de Style de la v1.3 (6 sous-listes, 15 cases fixes) : construites sur le chemin de la v1.3
local function buildStyleV13(page: Frame)
	local width = page.Size.X.Offset
	local listW = 300
	local pageH = page.Size.Y.Offset
	local kinds = Widgets.group(page, "Kinds", UDim2.fromOffset(listW, pageH), UDim2.fromOffset(48, 0))
	v13Kinds = kinds
	for i, kind in STYLE_KINDS do
		styleKindButtons[kind] = Widgets.button({
			parent = kinds,
			name = "Kind_" .. kind,
			size = UDim2.fromOffset(listW, Layout.Button.MinHeight),
			position = UDim2.fromOffset(0, (i - 1) * (Layout.Button.MinHeight + GAP)),
			key = "panel.ranch.style." .. kind,
			textSize = 36,
			color = Widgets.Colors.Card,
			nav = true,
			onActivate = function()
				styleKind = kind
				refreshStyle()
				local target = equippedStyleCell()
				if target then
					GuiService.SelectedObject = target
				end
			end,
		})
	end
	local left = 48 + listW + 32
	local cols = 5
	local areaW = width - left - 48
	local itemsFrame = Widgets.group(page, "Items", UDim2.fromOffset(areaW, pageH), UDim2.fromOffset(left, 0))
	v13Items = itemsFrame
	local cw = math.floor((areaW - (cols - 1) * GAP) / cols)
	local ch = 200
	for i = 1, 15 do
		local col = (i - 1) % cols
		local line = (i - 1) // cols
		local cell: StyleCell
		local b = Widgets.button({
			parent = itemsFrame,
			name = "Item" .. i,
			size = UDim2.fromOffset(cw, ch),
			position = UDim2.fromOffset(col * (cw + GAP), line * (ch + GAP)),
			color = Widgets.Colors.CardLight,
			onActivate = function()
				onStyleCell(cell)
			end,
		})
		local swatch = Widgets.frame({
			parent = b,
			name = "Swatch",
			size = UDim2.fromOffset(44, 44),
			position = UDim2.new(0.5, 0, 0, 10),
			anchor = Vector2.new(0.5, 0),
			color = Color3.new(1, 1, 1),
			corner = UDim.new(0.5, 0),
			zIndex = b.ZIndex + 1,
		})
		local name = Widgets.label({
			parent = b,
			name = "Name",
			size = UDim2.new(1, -12, 0, 68),
			position = UDim2.fromOffset(6, 58),
			text = "",
			textSize = 32,
			wrapped = true,
			zIndex = b.ZIndex + 2,
		})
		local status = Widgets.label({
			parent = b,
			name = "Status",
			size = UDim2.new(1, -12, 0, 68),
			position = UDim2.fromOffset(6, 128),
			text = "",
			textSize = 28,
			wrapped = true,
			zIndex = b.ZIndex + 2,
		})
		cell = { button = b, name = name, status = status, swatch = swatch, kind = "", id = "" }
		styleCells[i] = cell
	end
	v13Built = true
end

-- Case de la grille de Mon style (même dessin que la case de la v1.3 ; cadenas : les 2 cadres de celui
-- de la grille de l'Enclos, D24)
local function makeV2Cell(frame: Frame, c: number, cw: number): V2Cell
	local cell: V2Cell
	local b = Widgets.button({
		parent = frame,
		name = "Item" .. c,
		size = UDim2.fromOffset(cw, V2_CELL_H),
		position = UDim2.fromOffset((c - 1) * (cw + GAP), 0),
		color = Widgets.Colors.CardLight,
		grow = false,
		onActivate = function()
			onV2Cell(cell)
		end,
	})
	local swatch = Widgets.frame({
		parent = b,
		name = "Swatch",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(0.5, 0, 0, 10),
		anchor = Vector2.new(0.5, 0),
		color = Color3.new(1, 1, 1),
		corner = UDim.new(0.5, 0),
		zIndex = b.ZIndex + 1,
	})
	local lock = Widgets.frame({
		parent = b,
		name = "Lock",
		size = UDim2.fromOffset(26, 22),
		position = UDim2.new(1, -12, 0, 24),
		anchor = Vector2.new(1, 0),
		color = Widgets.Colors.LockedText,
		corner = UDim.new(0, 4),
		zIndex = b.ZIndex + 3,
	})
	Widgets.frame({
		parent = lock,
		name = "Ring",
		size = UDim2.fromOffset(16, 14),
		position = UDim2.new(0.5, 0, 0, -10),
		anchor = Vector2.new(0.5, 0),
		color = Widgets.Colors.LockedText,
		transparency = 1,
		corner = UDim.new(0.5, 0),
		zIndex = lock.ZIndex,
	})
	-- nom en 28 px sur 2 lignes au plus (GDD Annexe B, case (a) de Mon style : 66 titres, noms de la
	-- semaine « Titre « Copain fidèle » »)
	local name = Widgets.label({
		parent = b,
		name = "Name",
		size = UDim2.new(1, -2 * V2_TEXT_INSET, 0, 68),
		position = UDim2.fromOffset(V2_TEXT_INSET, 58),
		text = "",
		textSize = 28,
		wrapped = true,
		zIndex = b.ZIndex + 2,
	})
	local status = Widgets.label({
		parent = b,
		name = "Status",
		size = UDim2.new(1, -2 * V2_TEXT_INSET, 0, 68),
		position = UDim2.fromOffset(V2_TEXT_INSET, 128),
		text = "",
		textSize = 28,
		wrapped = true,
		zIndex = b.ZIndex + 2,
	})
	cell = { button = b, swatch = swatch, lock = lock, name = name, status = status, index = 0 }
	return cell
end

-- Plan vu du dessus (D11) : 12 boutons placés par MetaView.planLayout depuis
-- WorldLayout.decoPersoSlots() (P petit, G grand ; une case de la grille 5 × 4 chacun), repères des
-- enclos (milieu) et du portail (en bas) ; la croix va d'un emplacement à l'autre par la géométrie
local function buildPlan(page: Frame, left: number, width: number, height: number)
	local plan = Widgets.group(page, "Plan", UDim2.fromOffset(width, height), UDim2.fromOffset(left, 0))
	plan.Visible = false
	planFrame = plan
	Widgets.label({
		parent = plan,
		name = "Title",
		size = UDim2.fromOffset(width, 48),
		position = UDim2.new(),
		key = "deco.title",
		textSize = 40,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	local groundH = height - PLAN_TOP
	local ground = Widgets.frame({
		parent = plan,
		name = "Ground",
		size = UDim2.fromOffset(width, groundH),
		position = UDim2.fromOffset(0, PLAN_TOP),
		color = Widgets.Colors.Card,
		corner = Widgets.CORNER,
		zIndex = 2,
	})
	local rowH = groundH / MetaView.PLAN_ROWS
	local pens = Widgets.frame({
		parent = ground,
		name = "Pens",
		size = UDim2.fromOffset(width - 96, math.floor(rowH - 32)),
		position = UDim2.fromOffset(48, math.floor(groundH - 2 * rowH + 16)),
		color = Widgets.Colors.PanelLight,
		transparency = 0.5,
		corner = Widgets.CORNER,
		zIndex = 3,
	})
	-- repère lisible : les enclos au milieu du ranch (même mot que l'onglet)
	Widgets.label({
		parent = pens,
		name = "PensLabel",
		size = UDim2.fromScale(1, 1),
		key = "panel.ranch.tab.pens",
		textSize = 32,
		color = Widgets.Colors.TextDim,
		zIndex = 4,
	})
	Widgets.frame({
		parent = ground,
		name = "Gate",
		size = UDim2.fromOffset(160, 12),
		position = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 0.5),
		color = Widgets.Colors.Gold,
		corner = UDim.new(0.5, 0),
		zIndex = 3,
	})
	for i, r in MetaView.planLayout(WorldLayout.decoPersoSlots(), width, groundH) do
		local b = Widgets.button({
			parent = ground,
			name = "Slot" .. i,
			size = UDim2.fromOffset(r.w, r.h),
			position = UDim2.fromOffset(r.x, r.y),
			key = "deco.empty",
			textSize = 28,
			color = Widgets.Colors.CardLight,
			zIndex = 4,
			nav = true,
			grow = false,
			onActivate = function()
				openPicker(i)
			end,
		})
		b:SetAttribute("SlotSize", r.size)
		slotButtons[i] = b
	end
end

-- Parties de Mon style (v2.0) : liste des sortes (lignes de 80 px, défilante : jusqu'à 9 sortes pour
-- 7 visibles), grille commune de 5 colonnes, plan ; écoute des clés v2 du profil
local function buildStyleV2(page: Frame)
	local width = page.Size.X.Offset
	local pageH = page.Size.Y.Offset
	kindRows = Widgets.rows({
		parent = page,
		name = "KindsV2",
		size = Vector2.new(V2_KIND_W, pageH),
		position = UDim2.fromOffset(48, 0),
		rowHeight = Layout.Button.MinHeight,
		gap = GAP,
		makeRow = function(frame: Frame, _slot: number): KindRow
			local row: KindRow
			local b = Widgets.button({
				parent = frame,
				name = "Kind",
				size = UDim2.fromOffset(V2_KIND_W, Layout.Button.MinHeight),
				key = "panel.ranch.style.theme",
				textSize = 36,
				color = Widgets.Colors.Card,
				nav = true,
				grow = false,
				onActivate = function()
					onKindV2(row)
				end,
			})
			row = { button = b, kind = "" }
			return row
		end,
		bindRow = bindKindRow,
		selectables = function(row: KindRow): { GuiObject }
			return { row.button }
		end,
	})
	local left = 48 + V2_KIND_W + 32
	local areaW = width - left - 48
	local cw = math.floor((areaW - (V2_COLS - 1) * GAP) / V2_COLS)
	itemRows = Widgets.rows({
		parent = page,
		name = "ItemsV2",
		size = Vector2.new(V2_COLS * cw + (V2_COLS - 1) * GAP, pageH),
		position = UDim2.fromOffset(left, 0),
		rowHeight = V2_CELL_H,
		gap = GAP,
		makeRow = function(frame: Frame, _slot: number): V2Row
			local cells = {}
			for c = 1, V2_COLS do
				cells[c] = makeV2Cell(frame, c, cw)
			end
			return { cells = cells }
		end,
		bindRow = function(row: V2Row, _frame: Frame, index: number)
			for c, cell in row.cells do
				bindV2Cell(cell, (index - 1) * V2_COLS + c)
			end
		end,
		selectables = function(row: V2Row): { GuiObject }
			local out = {}
			for _, cell in row.cells do
				table.insert(out, cell.button)
			end
			return out
		end,
	})
	buildPlan(page, left, areaW, pageH)
	v2Built = true
	-- clés du profil v2 lues par la possession (jamais construites interrupteurs coupés)
	Widgets.watch({
		"version",
		"bestR",
		"ascend",
		"atelierCosmetics",
		"atelier",
		"stats",
		"weeklyTrack",
		"season",
		"moon",
		"decoPerso",
	}, function()
		if isOpen and current == "style" and styleMode == "v2" then
			refreshStyle()
		end
	end)
end

-- Page Style et les parties du chemin courant (deux niveaux : sous-listes, puis objets ; ○ remonte)
local function buildStyle(container: Frame, top: number)
	local width = container.Size.X.Offset
	local page = Widgets.group(
		container,
		"Page_style",
		UDim2.fromOffset(width, container.Size.Y.Offset - top),
		UDim2.fromOffset(0, top)
	)
	page.Visible = false
	page:SetAttribute("TvLevels", true)
	pages.style = page
	stylePage = page
	if styleV2() then
		buildStyleV2(page)
		styleMode = "v2"
	else
		buildStyleV13(page)
		styleMode = "v13"
	end
end

-- À l'ouverture (jamais écran ouvert) : chemin de Style et parties manquantes construites (D10, D24),
-- page Dalles construite si le chemin de la v1.3 revient (D12)
local function prepareOpen()
	local container = buildContainer
	if container and not padsBuilt and not padsHidden() then
		buildPads(container, buildTop)
	end
	local page = stylePage
	if page then
		local want = if styleV2() then "v2" else "v13"
		if want == "v2" and not v2Built then
			buildStyleV2(page)
		elseif want == "v13" and not v13Built then
			buildStyleV13(page)
		end
		styleMode = want
	end
	pickerSlot = 0
	applyStyleMode()
	-- liste des sortes ramenée en haut à chaque ouverture (la 1re sorte entière à l'écran)
	local rows = kindRows
	if styleMode == "v2" and rows then
		rows.ensureVisible(1)
	end
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Ranch.build(container: Frame)
	local specs = {}
	local myStyle = styleV2()
	for _, id in TABS do
		local key = if id == "style" and myStyle then "panel.ranch.tab.myStyle" else "panel.ranch.tab." .. id
		table.insert(specs, { id = id, key = key })
	end
	tabBar = Widgets.tabBar(container, specs, function(id: string)
		Ranch.setTab(id)
	end)
	local top = Layout.Panel.tabHeight + 24
	buildContainer = container
	buildTop = top
	buildGridPage(container, top)
	buildDetail(container, top)
	buildOverlay(container, top)
	-- N8 : l'écran Améliorations remplace les Dalles ; leur page n'est pas construite (D12)
	if not padsHidden() then
		buildPads(container, top)
	end
	buildStyle(container, top)
	syncPads()
	-- interrupteurs ou profil v2 changés : le chemin suit au rafraîchissement (jamais d'instance créée)
	MetaFlags.Changed:Connect(function()
		if isOpen then
			refresh()
		end
	end)
	Widgets.watch({
		"squishies",
		"mount",
		"tiles",
		"R",
		"coins",
		"passes",
		"cosmetics",
		"outfits",
		"plopDays",
		"dex",
		"growth",
		"biggestEver",
		"fame",
		"trophies",
		"upgradeSnapshot",
	}, function()
		if isOpen then
			refresh()
		end
	end)
	showTab()
end

-- Connexions faites au démarrage du client (PanelController.Start), AVANT toute ouverture : les titres
-- de la semaine arrivent par Celebrate « unlock » dès l'arrivée (CommunityService.unlockSession), bien
-- avant que le panneau soit construit ; le client ne peut pas les déduire du profil
local startedListening = false
function Ranch.start()
	if startedListening then
		return
	end
	startedListening = true
	pcall(function()
		Net.event("Celebrate").OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" and payload.kind == "unlock" and type(payload.data) == "table" then
				local kind, id = payload.data.kind, payload.data.id
				if type(kind) == "string" and type(id) == "string" and #kind <= 16 and #id <= 32 then
					sessionUnlocks[kind .. ":" .. id] = true
					if isOpen and current == "style" and tabBar ~= nil then
						refreshStyle()
					end
				end
			end
		end)
	end)
end

-- Affiche le panneau (onglet demandé ou le dernier) ; « padsKept » : Dalles, gardées d'abord
function Ranch.open(tab: string?)
	isOpen = true
	-- parties manquantes construites ICI, avant l'affichage (D12, D24)
	prepareOpen()
	if tab == "padsKept" then
		current = "pads"
		keptFirst = true
	elseif type(tab) == "string" and table.find(TABS, tab) then
		current = tab
		keptFirst = false
	else
		keptFirst = false
	end
	-- N8 : Dalles absentes tant que l'écran Améliorations est disponible (« padsKept » : chemin v1.3)
	syncPads()
	fuseA = ""
	table.clear(selected)
	-- Style s'ouvre toujours sur la 1re sous-liste (Selle ; Mon style : habillage) : sélection par
	-- défaut = son objet équipé
	styleKind = firstStyleKind()
	showTab()
	refresh()
end

-- Cache le panneau (sous-niveaux fermés, sélection multiple vidée)
function Ranch.close()
	isOpen = false
	if detail then
		detail.Visible = false
	end
	if overlay then
		overlay.Visible = false
	end
	overlayMode = ""
	fuseA = ""
	table.clear(selected)
	pickerSlot = 0
end

-- Onglets, dans l'ordre (L1 / R1) ; sans Dalles tant que l'écran Améliorations est disponible (N8)
function Ranch.tabs(): { string }
	if padsHidden() then
		local out = {}
		for _, id in TABS do
			if id ~= "pads" then
				table.insert(out, id)
			end
		end
		return out
	end
	return table.clone(TABS)
end

-- Change d'onglet
function Ranch.setTab(tab: string)
	if type(tab) ~= "string" then
		return
	end
	if (tab == "pads" or tab == "padsKept") and (padsHidden() or not padsBuilt) then
		return -- N8 : pas d'onglet Dalles sur le chemin de l'écran Améliorations
	end
	if tab == "padsKept" then
		current = "pads"
		keptFirst = true
	elseif table.find(TABS, tab) then
		if tab == "style" and current ~= "style" then
			styleKind = firstStyleKind() -- entrée dans Style : 1re sous-liste (Selle ; habillage)
			pickerSlot = 0
		end
		current = tab
		if tab ~= "pads" then
			keptFirst = false
		end
	else
		return
	end
	fuseA = ""
	table.clear(selected)
	detailFrom = nil
	overlayMode = ""
	showTab()
	refresh()
end

function Ranch.currentTab(): string
	return current
end

-- Sélection par défaut (GDD §10.6)
function Ranch.defaultSelection(): GuiObject?
	if detail and detail.Visible then
		return detailButtons.lock
	end
	if overlay and overlay.Visible then
		return holds.overlay.button
	end
	if current == "fuse" then
		return buttons.chooseA
	elseif current == "pads" then
		return cheapestTile()
	elseif current == "style" then
		if styleMode == "v2" then
			-- Mon style : l'objet équipé de la sorte (ou la 1re case) ; plan : l'emplacement 1 (D25)
			if styleKind == "deco" and pickerSlot == 0 then
				return slotButtons[1] or kindButtonV2("deco")
			end
			return selectedV2Cell() or kindButtonV2(styleKind)
		end
		return equippedStyleCell() or styleKindButtons.saddle
	end
	local first = if grid then grid.firstSelectable() else nil
	if first then
		return first
	end
	if current == "pens" then
		return buttons.sort
	elseif current == "sell" then
		return holds.sell.button
	end
	return if tabBar then tabBar.buttons[current] else nil
end

-- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
function Ranch.onBack(): boolean
	if overlay and overlay.Visible then
		closeOverlay()
		return true
	end
	if detail and detail.Visible then
		closeDetail(true)
		return true
	end
	if current == "sell" and next(selected) ~= nil then
		-- ○ vide d'abord la sélection multiple
		table.clear(selected)
		refresh()
		return true
	end
	if current == "fuse" and fuseA ~= "" then
		fuseA = ""
		refresh()
		return true
	end
	if current == "style" and styleMode == "v2" then
		-- Mon style (D25) : choix d'un objet → son emplacement ; plan ou grille → liste des sortes
		local sel = GuiService.SelectedObject
		local rows, plan = itemRows, planFrame
		local inGrid = sel ~= nil and rows ~= nil and sel:IsDescendantOf(rows.frame)
		local inPlan = sel ~= nil and plan ~= nil and sel:IsDescendantOf(plan)
		if inGrid and pickerSlot > 0 then
			closePicker(true)
			return true
		end
		if inGrid or inPlan then
			local b = kindButtonV2(styleKind)
			if b then
				GuiService.SelectedObject = b
			end
			return true
		end
		return false
	end
	if current == "style" then
		local sel = GuiService.SelectedObject
		for _, cell in styleCells do
			if sel == cell.button then
				local b = styleKindButtons[styleKind]
				if b then
					GuiService.SelectedObject = b
				end
				return true
			end
		end
	end
	return false
end

-- Entrée du menu visible pour ce joueur
function Ranch.visible(): boolean
	return true
end

-- Navigateur fourni par PanelController AVANT build
function Ranch.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function Ranch.refresh()
	refresh()
end

-- Stick droit : une page de la grille
function Ranch.scroll(dir: number)
	if GRID_TABS[current] and grid then
		grid.page(dir)
	end
end

-- Tout fusionner (refusé sans paire de jumeaux : rien n'est envoyé)
function Ranch._mergeAll(button: TextButton)
	local pairs = Widgets.safe("FusionRules.twinPairs", 0, FusionRules.twinPairs, squishies())
	if type(pairs) ~= "number" or pairs <= 0 then
		Widgets.refuse(button)
		pcall(Toast.message, Prefs.t("feedback.nothingToFuse"), "info")
		return
	end
	Widgets.send("FuseAll")
end

-- État pour les specs
function Ranch._state(): { [string]: any }
	return {
		tab = current,
		keptFirst = keptFirst,
		selected = selectedUids(),
		fuseA = fuseA,
		detail = detail ~= nil and detail.Visible,
		overlay = overlayMode,
		styleKind = styleKind,
		items = #items,
		styleMode = styleMode,
		padsBuilt = padsBuilt,
		v13Built = v13Built,
		v2Built = v2Built,
		kinds = table.clone(kindsV2),
		pickerSlot = pickerSlot,
		entries = #v2Entries,
		deco = table.clone(decoContents),
	}
end

-- Mon style (specs) : entrées liées à la grille (sorte, identifiant, possédé, équipé)
function Ranch._styleEntries(): { { kind: string, id: string, n: number, unlocked: boolean, equipped: boolean } }
	local out = {}
	for _, e in v2Entries do
		table.insert(out, { kind = e.kind, id = e.id, n = e.n, unlocked = e.unlocked, equipped = e.equipped })
	end
	return out
end

-- Emplacement n° i du plan de Déco perso (specs)
function Ranch._decoSlot(i: number): TextButton?
	return slotButtons[i]
end

-- Case de la grille qui montre un squishy (specs)
function Ranch._cellFor(uid: string): TextButton?
	local g = grid
	if g == nil then
		return nil
	end
	for i, item in items do
		if item.uid == uid then
			local row = (i - 1) // COLS + 1
			local col = (i - 1) % COLS + 1
			return g.selectableAt(row, col) :: TextButton?
		end
	end
	return nil
end

-- Bouton d'une dalle et case d'un cosmétique (specs)
function Ranch._tileButton(tile: string): TextButton?
	return tileButtons[tile]
end

function Ranch._styleCell(kind: string, id: string): TextButton?
	if styleMode == "v2" then
		-- case de la grille de Mon style (ramenée à l'écran par la liste virtualisée)
		local rows = itemRows
		if rows == nil then
			return nil
		end
		for i, e in v2Entries do
			if e.kind == kind and e.id == id then
				return rows.selectableAt((i - 1) // V2_COLS + 1, (i - 1) % V2_COLS + 1) :: TextButton?
			end
		end
		return nil
	end
	for _, cell in styleCells do
		if cell.button.Visible and cell.kind == kind and cell.id == id then
			return cell.button
		end
	end
	return nil
end

function Ranch._styleKindButton(kind: string): TextButton?
	if styleMode == "v2" then
		return kindButtonV2(kind) :: TextButton?
	end
	return styleKindButtons[kind]
end

function Ranch._button(name: string): GuiObject?
	return buttons[name] or (if holds[name] then holds[name].button else nil) or detailButtons[name]
end

return Ranch
