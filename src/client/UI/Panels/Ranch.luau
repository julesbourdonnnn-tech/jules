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
-- Un bouton refusé (enclos pleins, pas assez de pièces, verrouillé) ne part jamais au serveur ; le
-- serveur revalide tout. Sélection par défaut (GDD §10.6) : 1re case ; Fusionner : « Choisir A » ;
-- Dalles : la moins chère achetable ; Style : l'objet équipé de la 1re sous-liste.

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
local Clock = require(Shared.Util.Clock)
local Net = require(Shared.Net)

local Client = script.Parent.Parent.Parent
local Toast = require(Client.UI.Toast)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Prefs = require(Client.Util.Prefs)
local Widgets = require(script.Parent.Widgets)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }
type Item = { uid: string, rec: { [string]: any }, size: number, income: number }
type Cell = {
	button: TextButton,
	blob: Frame,
	name: TextLabel,
	size: TextLabel,
	line: TextLabel,
	bf: TextLabel,
	twin: TextLabel,
	lock: Frame,
	mount: Frame,
	check: TextLabel,
	uid: string,
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
	local mdef = mutationDef(rec)
	if mdef then
		Widgets.setText(cell.line, "mutation." .. mdef.key)
		cell.line.TextColor3 = mdef.color
	elseif Widgets.n(rec.st) > 0 then
		Widgets.setText(cell.line, "common.stars", { n = math.floor(Widgets.n(rec.st)) })
		cell.line.TextColor3 = Widgets.Colors.Gold
	else
		Widgets.setRaw(cell.line, "")
	end
	local bf = math.floor(Widgets.n(rec.bf))
	cell.bf.Visible = bf > 0
	Widgets.setRaw(cell.bf, "♥" .. tostring(bf))
	cell.twin.Visible = hasTwin(item.uid, rec)
	cell.lock.Visible = rec.lk == true
	cell.mount.Visible = Widgets.state("mount") == item.uid
	local isSelected = (current == "sell" and selected[item.uid] == true)
		or (current == "fuse" and fuseA == item.uid)
	cell.check.Visible = isSelected
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
	local bf = Widgets.label({
		parent = b,
		name = "BestFriend",
		size = UDim2.fromOffset(60, 36),
		position = UDim2.fromOffset(6, 6),
		text = "",
		textSize = 28,
		color = Widgets.Colors.Stroke,
		background = Widgets.Colors.Gold,
		backgroundTransparency = 0,
		zIndex = b.ZIndex + 3,
	})
	Widgets.corner(bf, UDim.new(0.5, 0))
	local twin = Widgets.label({
		parent = b,
		name = "Twin",
		size = UDim2.fromOffset(40, 36),
		position = UDim2.new(1, -6, 0, 6),
		anchor = Vector2.new(1, 0),
		text = "♥",
		textSize = 32,
		color = Widgets.Colors.Pink,
		zIndex = b.ZIndex + 3,
	})
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
	local check = Widgets.label({
		parent = b,
		name = "Check",
		size = UDim2.fromOffset(64, 56),
		position = UDim2.fromOffset(6, 54),
		text = "✓",
		textSize = 48,
		color = Widgets.Colors.Text,
		zIndex = b.ZIndex + 4,
	})
	cell = {
		button = b,
		blob = blob,
		name = name,
		size = size,
		line = line,
		bf = bf,
		twin = twin,
		lock = lock,
		mount = mount,
		check = check,
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
		b.BackgroundColor3 = if Widgets.n(rec.bf) == n then Widgets.Colors.Gold else Widgets.Colors.CardLight
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

local function refreshStyle()
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
-- Rafraîchissement
-- =============================================================================================

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
		refreshPads()
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

local function buildStyle(container: Frame, top: number)
	local width = container.Size.X.Offset
	local page = Widgets.group(
		container,
		"Page_style",
		UDim2.fromOffset(width, container.Size.Y.Offset - top),
		UDim2.fromOffset(0, top)
	)
	page.Visible = false
	-- deux niveaux : liste des sous-listes (« Kinds »), puis objets (« Items ») ; ○ remonte de l'un à l'autre
	page:SetAttribute("TvLevels", true)
	pages.style = page
	local listW = 300
	local pageH = page.Size.Y.Offset
	local kinds = Widgets.group(page, "Kinds", UDim2.fromOffset(listW, pageH), UDim2.fromOffset(48, 0))
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
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Ranch.build(container: Frame)
	local specs = {}
	for _, id in TABS do
		table.insert(specs, { id = id, key = "panel.ranch.tab." .. id })
	end
	tabBar = Widgets.tabBar(container, specs, function(id: string)
		Ranch.setTab(id)
	end)
	local top = Layout.Panel.tabHeight + 24
	buildGridPage(container, top)
	buildDetail(container, top)
	buildOverlay(container, top)
	buildPads(container, top)
	buildStyle(container, top)
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
	if tab == "padsKept" then
		current = "pads"
		keptFirst = true
	elseif type(tab) == "string" and table.find(TABS, tab) then
		current = tab
		keptFirst = false
	else
		keptFirst = false
	end
	fuseA = ""
	table.clear(selected)
	-- Style s'ouvre toujours sur la 1re sous-liste (Selle) : sélection par défaut = son objet équipé
	styleKind = STYLE_KINDS[1]
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
end

-- Onglets, dans l'ordre (L1 / R1)
function Ranch.tabs(): { string }
	return table.clone(TABS)
end

-- Change d'onglet
function Ranch.setTab(tab: string)
	if type(tab) ~= "string" then
		return
	end
	if tab == "padsKept" then
		current = "pads"
		keptFirst = true
	elseif table.find(TABS, tab) then
		if tab == "style" and current ~= "style" then
			styleKind = STYLE_KINDS[1] -- entrée dans Style : 1re sous-liste (Selle)
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
	}
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
	for _, cell in styleCells do
		if cell.button.Visible and cell.kind == kind and cell.id == id then
			return cell.button
		end
	end
	return nil
end

function Ranch._styleKindButton(kind: string): TextButton?
	return styleKindButtons[kind]
end

function Ranch._button(name: string): GuiObject?
	return buttons[name] or (if holds[name] then holds[name].button else nil) or detailButtons[name]
end

return Ranch
