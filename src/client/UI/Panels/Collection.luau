--!strict
-- Panels/Collection — paquet « client-panels » (docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * onglets Perchoirs (perchés + revenu de chacun, places libres), Réserve (grille VIRTUALISÉE :
--     seules les cases visibles existent ; tri revenu / rareté / récent ; verrou → SetLock ;
--     libération en lot → Release(uids) avec confirmation en deux appuis et total de Stardust),
--     Forge (fusions possibles en haut → Fuse(uid), « Tout fusionner » → FuseAll ; animation
--     Starforge sur Celebrate "starforge"), Atlas (grille espèces × formes, silhouettes grises,
--     fiche par espèce : rareté, zones, meilleur exemplaire possédé ; jalons, badges, « NOUVEAU ! »
--     sur Celebrate "atlasNew"), Guide (probabilités par zone, météo, Comète, variantes : lues dans
--     Config, rien en dur ; reconstruit seulement quand la langue change)
--   * libération : l'icône rétrécit (0,2 s) ; une case recyclée par la grille pour un autre Nebby
--     annule ce rétrécissement
--   * icônes de Nebbies : pastilles en Frames (Widgets.nebbyIcon), légères sur mobile
--   * Atlas débloqué après Q4 (profil onboarding) ; hasAction : une fusion est possible
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number ;
--     intentions seulement (le serveur valide tout)
-- GDD : §4.9, §4.13, §4.14, §4.3 (probabilités affichées), §9.4 (Starforge, Atlas, Libération), §10.3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Nebbies = require(Shared.Config.Nebbies)
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Logic.Formulas)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local Toast = require(Client.UI.Toast)
local ScreenFX = require(Client.UI.ScreenFX)
local Model = require(script.Parent.Model)
local Widgets = require(script.Parent.Widgets)
local VirtualGrid = require(script.Parent.VirtualGrid)

local Panel = {}

Panel.name = "Collection" :: Types.PanelName
Panel.tabs = {
	"collection.tab.perches",
	"collection.tab.stash",
	"collection.tab.forge",
	"collection.tab.atlas",
	"collection.tab.guide",
} :: { string }?

local TAB_IDS = { "perches", "stash", "forge", "atlas", "guide" }
local RELEASE_MAX = 50 -- remote Release : 1-50 uids (§10.1)
local CONFIRM_WINDOW = 4 -- s pour confirmer une libération (second appui)
local FORGE_ROWS = 40 -- lignes de fusion affichées au plus
local PERCH_CELL = Vector2.new(92, 116)
local STASH_CELL = Vector2.new(88, 108)
local ATLAS_CELL = 52
local ATLAS_ROW = 64
local SHRINK_TIME = 0.2
-- Animation Starforge (§9.4) : orbite 1,2 s, flash 0,15 s, résultat 0,3 s, étoiles 0,1 s
local ORBIT_TIME, FLASH_TIME, RESULT_TIME, STAR_EVERY, ANIM_HOLD = 1.2, 0.15, 0.3, 0.1, 1.4

local view = Model.view(State.get)
local built = false
local isOpen = false
local currentTab = "perches"
local dirty = false
local tabFrames: { [string]: Frame } = {}

-- Perchoirs
local perchHeader: TextLabel? = nil
local perchTotal: TextLabel? = nil
local perchGrid: ScrollingFrame? = nil
local perchCells: { Frame } = {}
local perchEmpty: TextLabel? = nil

-- Réserve
type SortMode = Model.SortMode
local sortMode: SortMode = "income"
local sortedUids: { string } = {}
local stashGrid: VirtualGrid.VirtualGrid? = nil
local stashCount: TextLabel? = nil
local sortButtons: { [string]: TextButton } = {}
local selectButton: TextButton? = nil
local actionLabel: TextLabel? = nil
local lockButton: TextButton? = nil
local releaseButton: TextButton? = nil
local cancelButton: TextButton? = nil
local stashEmpty: TextLabel? = nil
local focusUid: string? = nil
local selectMode = false
local selected: { [string]: boolean } = {}
local selectedCount = 0
local armedAt: number? = nil
local armedClock = 0

-- Forge
type ForgeRow = {
	frame: Frame,
	materials: { Frame },
	result: Frame,
	count: TextLabel,
	cost: TextLabel,
	fuse: TextButton,
	group: Model.FuseGroup?,
}
local forgeRows: { ForgeRow } = {}
local forgeList: ScrollingFrame? = nil
local forgeHint: TextLabel? = nil
local fuseAllButton: TextButton? = nil
local forgeEmpty: TextLabel? = nil
type ForgeAnim =
	{ t: number, s: number, f: number, v: number, stars: number, flashed: boolean, shown: number }
local anim: ForgeAnim? = nil
local fx: {
	root: Frame?,
	flash: Frame?,
	orbit: { Frame },
	result: Frame?,
	resultScale: UIScale?,
	stars: TextLabel?,
	stamp: TextLabel?,
} =
	{ orbit = {} }

-- Atlas
-- fiche d'espèce (§4.14) : nom, rareté, zones, formes trouvées, meilleur exemplaire possédé
type AtlasRow = { name: TextLabel, detail: TextLabel, cells: { [number]: Frame }, complete: TextLabel }
local atlasRows: { [number]: AtlasRow } = {}
local atlasHeader: TextLabel? = nil
local atlasBar: Frame? = nil
local atlasNext: TextLabel? = nil
local atlasBadges: TextLabel? = nil
local atlasList: ScrollingFrame? = nil
local atlasLocked: TextLabel? = nil
local fresh: { [number]: boolean } = {}
local atlasSeen = false

-- Guide (reconstruit seulement quand la langue change : son contenu ne vient que de Config)
local guideList: ScrollingFrame? = nil
local guideLang: string? = nil

-- Libération : rétrécissement en cours par case (uid libéré, tween) ; une case recyclée par la
-- grille virtualisée pour un AUTRE Nebby annule le tween, sinon il continuerait d'écrire Scale
type Shrink = { uid: string, tween: any }
local shrinking: { [Instance]: Shrink } = setmetatable({}, { __mode = "k" }) :: any

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function nebbies(): { [string]: any }
	local n = view.nebbies
	return if type(n) == "table" then n else {}
end

local function scroll(name: string, parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	return Create("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Selectable = false,
		Parent = parent,
	}) :: ScrollingFrame
end

local function rate(x: number): string
	return Prefs.t("collection.income", { rate = Prefs.number(math.floor(x * 10 + 0.5) / 10) })
end

local function lookOf(rec: any, known: boolean?): Widgets.NebbyLook
	return { s = rec.s, f = rec.f, v = rec.v, stars = rec.st, locked = rec.lk == true, known = known }
end

-- « Prismpaw · Rare · Aurora · Golden »
local function describe(rec: any): string
	local species = Nebbies.Species[rec.s]
	local rarity = Nebbies.Rarities[Nebbies.rarityOf(rec.s)]
	local form = Nebbies.Forms[rec.f]
	local parts = {
		if species then species.name else "?",
		Prefs.t("collection.detail", {
			rarity = Prefs.t("rarity." .. (if rarity then rarity.key else "common")),
			form = Prefs.t("form." .. (if form then form.key else "normal")),
		}),
	}
	for _, key in Nebbies.VARIANT_ORDER do
		local def = Nebbies.Variants[key]
		if def and bit32.btest(rec.v, def.bit) then
			table.insert(parts, Prefs.t("variant." .. key))
		end
	end
	local stars = math.clamp(rec.st, 1, Nebbies.MAX_STARS)
	return table.concat(parts, " · ") .. " " .. string.rep("★", stars)
end

-- Nombre de pourcentage lisible (« 0.5 », « 23 » ; « 0,5 » en français)
local function pctNumber(x: number): string
	local rounded = math.floor(x * 10 + 0.5) / 10
	local s = if rounded % 1 == 0 then tostring(math.floor(rounded)) else string.format("%.1f", rounded)
	if Prefs.language() == "fr" then
		s = string.gsub(s, "%.", ",")
	end
	return s
end

-- Pourcentage avec son signe (« 23% », « 23 % »)
local function pct(x: number): string
	return Prefs.t("guide.chance", { chance = pctNumber(x) })
end

-- ---------------------------------------------------------------------------------------------
-- Perchoirs
-- ---------------------------------------------------------------------------------------------

local function perchCell(i: number, parent: Instance): Frame
	local cell =
		Widgets.card({ name = "Perch" .. i, size = UDim2.fromOffset(PERCH_CELL.X, PERCH_CELL.Y), order = i })
	local icon = Widgets.nebbyIcon("Icon", UDim2.new(1, -12, 0, PERCH_CELL.X - 12), cell)
	icon.Position = UDim2.fromOffset(6, 4)
	Widgets.label({
		name = "Income",
		size = UDim2.new(1, -6, 0, 20),
		position = UDim2.new(0.5, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		color = Theme.Colors.Gold,
		maxSize = 16,
		zIndex = 4,
		parent = cell,
	})
	Widgets.label({
		name = "Empty",
		text = "+",
		size = UDim2.fromScale(0.6, 0.6),
		position = UDim2.fromScale(0.5, 0.45),
		anchor = Vector2.new(0.5, 0.5),
		color = Widgets.DIM,
		maxSize = 40,
		zIndex = 4,
		parent = cell,
	})
	cell.Parent = parent
	return cell
end

local function renderPerches()
	local p = view
	local count = Model.perchCount(p)
	local ranked = Model.rank(p.nebbies)
	local perched = math.min(count, #ranked.uids)
	local mult = Model.multiplier(p)
	if perchHeader then
		perchHeader.Text = Prefs.t("collection.perchesCount", { n = perched, max = count })
	end
	if perchTotal then
		perchTotal.Text = rate(Model.num(p.idleRate, 0))
	end
	if perchEmpty then
		perchEmpty.Text = Prefs.t("collection.empty")
		perchEmpty.Visible = #ranked.uids == 0
	end
	local grid = perchGrid
	if not grid then
		return
	end
	local shown = math.min(count, Balance.Perches.Max)
	for i = #perchCells + 1, shown do
		perchCells[i] = perchCell(i, grid)
	end
	local all = nebbies()
	for i, cell in perchCells do
		local icon = cell:FindFirstChild("Icon") :: Frame
		local income = cell:FindFirstChild("Income") :: TextLabel
		local empty = cell:FindFirstChild("Empty") :: TextLabel
		if i > shown then
			cell.Visible = false
		else
			cell.Visible = true
			local uid = ranked.uids[i]
			local rec = if i <= perched and uid then all[uid] else nil
			if rec then
				icon.Visible = true
				empty.Visible = false
				Widgets.setNebby(icon, lookOf(rec))
				income.Text = rate(ranked.income[uid] * mult)
			else
				icon.Visible = false
				empty.Visible = true
				income.Text = ""
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Réserve
-- ---------------------------------------------------------------------------------------------

local function releaseTotal(): number
	local all = nebbies()
	local dust = 0
	for uid in selected do
		dust += Model.releaseDust(all[uid]) or 0
	end
	return dust
end

local function disarm()
	armedAt = nil
end

local function renderAction()
	local all = nebbies()
	local label, lock, release, cancel = actionLabel, lockButton, releaseButton, cancelButton
	if not label or not lock or not release or not cancel then
		return
	end
	local armed = armedAt ~= nil and armedClock - (armedAt :: number) <= CONFIRM_WINDOW
	if not armed then
		armedAt = nil
	end
	if selectButton then
		Widgets.setText(selectButton, Prefs.t(if selectMode then "common.cancel" else "collection.select"))
		Widgets.setColor(selectButton, if selectMode then Theme.Colors.Warning else Widgets.CARD)
	end
	if selectMode then
		label.Text = if selectedCount > 0
			then Prefs.t("collection.selected", { count = selectedCount })
			else Prefs.t("collection.releaseHint")
		lock.Visible = false
		cancel.Visible = false
		release.Visible = true
		Widgets.setEnabled(release, selectedCount > 0)
		Widgets.setText(
			release,
			if armed
				then Prefs.t(
					"collection.releaseConfirm",
					{ count = selectedCount, dust = Prefs.number(releaseTotal()) }
				)
				else Prefs.t("collection.release")
		)
		Widgets.setColor(release, if armed then Theme.Colors.Danger else Theme.Colors.Warning)
		return
	end
	local rec = if focusUid then all[focusUid] else nil
	if not Model.validRecord(rec) then
		focusUid = nil
		label.Text = Prefs.t("collection.selectHint")
		lock.Visible = false
		release.Visible = false
		cancel.Visible = false
		return
	end
	label.Text = describe(rec)
	lock.Visible = true
	Widgets.setText(lock, Prefs.t(if rec.lk == true then "collection.unlock" else "collection.lock"))
	release.Visible = true
	cancel.Visible = false
	Widgets.setEnabled(release, Model.canRelease(rec))
	local dust = Model.releaseDust(rec) or 0
	Widgets.setText(
		release,
		if armed
			then Prefs.t("collection.releaseConfirm", { count = 1, dust = Prefs.number(dust) })
			else Prefs.t("collection.release")
	)
	Widgets.setColor(release, if armed then Theme.Colors.Danger else Theme.Colors.Warning)
end

-- Arrête le rétrécissement d'une case (et lui rend sa taille)
local function stopShrink(hit: Instance)
	local shrink = shrinking[hit]
	if shrink then
		shrinking[hit] = nil
		local tween = shrink.tween
		if tween ~= nil and type(tween.Cancel) == "function" then
			tween:Cancel()
		end
	end
end

local function bindStashCell(cell: Frame, index: number)
	local uid = sortedUids[index]
	local rec = if uid then nebbies()[uid] else nil
	local hit = cell:FindFirstChild("Hit") :: TextButton
	local icon = hit:FindFirstChild("Icon") :: Frame
	local income = hit:FindFirstChild("Income") :: TextLabel
	local shrink = shrinking[hit]
	if shrink == nil or shrink.uid ~= uid or not Model.validRecord(rec) then
		-- case réaffectée (ou vidée) : le Nebby qui rétrécissait n'est plus là
		stopShrink(hit)
		Juice.scaleOf(hit).Scale = 1
	end
	if not uid or not Model.validRecord(rec) then
		cell:SetAttribute("Uid", "")
		cell.Visible = false
		return
	end
	cell:SetAttribute("Uid", uid)
	Widgets.setNebby(icon, lookOf(rec))
	income.Text = rate(Formulas.passiveIncome(rec))
	local on = selected[uid] == true
	local focused = not selectMode and focusUid == uid
	Widgets.highlight(hit, on or focused, if on then Theme.Colors.Gold else Widgets.CYAN)
	hit.BackgroundColor3 = if on then Color3.fromRGB(96, 80, 40) else Widgets.CARD
end

local function refreshStashCells()
	local grid = stashGrid
	if grid then
		grid:refresh()
	end
end

local function onStashTap(cell: Frame)
	local uid = cell:GetAttribute("Uid")
	if type(uid) ~= "string" or uid == "" then
		return
	end
	local rec = nebbies()[uid]
	if not Model.validRecord(rec) then
		return
	end
	disarm()
	local hit = cell:FindFirstChild("Hit") :: TextButton
	if selectMode then
		if selected[uid] then
			selected[uid] = nil
			selectedCount -= 1
		elseif not Model.canRelease(rec) then
			Widgets.refuse(hit)
			Toast.show(
				Prefs.t(if rec.lk == true then "feedback.nebbyLocked" else "feedback.cannotRelease"),
				"warning"
			)
			return
		elseif selectedCount >= RELEASE_MAX then
			Widgets.refuse(hit)
			return
		else
			selected[uid] = true
			selectedCount += 1
		end
		AudioController.play("Click")
	else
		focusUid = if focusUid == uid then nil else uid
		AudioController.play("Click")
	end
	refreshStashCells()
	renderAction()
end

local function createStashCell(cell: Frame)
	local hit = Create("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Widgets.CARD,
		Selectable = true,
		Parent = cell,
	}, { Widgets.corner(Theme.CornerSmall), Widgets.stroke() }) :: TextButton
	local icon = Widgets.nebbyIcon("Icon", UDim2.new(1, -10, 0, STASH_CELL.X - 12), hit)
	icon.Position = UDim2.fromOffset(5, 3)
	Widgets.label({
		name = "Income",
		size = UDim2.new(1, -6, 0, 18),
		position = UDim2.new(0.5, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		color = Theme.Colors.Gold,
		maxSize = 15,
		zIndex = 4,
		parent = hit,
	})
	Juice.press(hit)
	hit.Activated:Connect(function()
		onStashTap(cell)
	end)
end

local function setSelectMode(on: boolean)
	selectMode = on
	selected = {}
	selectedCount = 0
	disarm()
	if on then
		focusUid = nil
	end
	refreshStashCells()
	renderAction()
end

local function renderStash()
	local all = nebbies()
	sortedUids = Model.sorted(all, sortMode)
	-- sélection : on retire ce qui n'existe plus ou n'est plus libérable
	for uid in selected do
		if not Model.canRelease(all[uid]) then
			selected[uid] = nil
			selectedCount -= 1
		end
	end
	if stashCount then
		stashCount.Text = Prefs.t("collection.stashCount", { n = #sortedUids, max = Model.stashCap(view) })
	end
	for mode, button in sortButtons do
		Widgets.setText(button, Prefs.t("collection.sort." .. mode))
		Widgets.setColor(button, if mode == sortMode then Theme.Colors.Primary else Widgets.CARD)
	end
	if stashEmpty then
		stashEmpty.Text = Prefs.t("collection.empty")
		stashEmpty.Visible = #sortedUids == 0
	end
	local grid = stashGrid
	if grid then
		grid:setCount(#sortedUids)
	end
	renderAction()
end

local function doRelease()
	local all = nebbies()
	local uids: { string } = {}
	if selectMode then
		for uid in selected do
			if Model.canRelease(all[uid]) then
				table.insert(uids, uid)
			end
		end
	elseif focusUid and Model.canRelease(all[focusUid]) then
		table.insert(uids, focusUid)
	end
	if #uids == 0 or #uids > RELEASE_MAX then
		if releaseButton then
			Widgets.refuse(releaseButton)
		end
		return
	end
	table.sort(uids, function(a: string, b: string): boolean
		return Model.uidNumber(a) < Model.uidNumber(b)
	end)
	Net.event("Release"):FireServer(uids)
	AudioController.play("Pop")
	-- l'icône rétrécit en 0,2 s (Quad In) ; le profil répliqué retire ensuite la case
	local gone: { [string]: boolean } = {}
	for _, uid in uids do
		gone[uid] = true
	end
	local grid = stashGrid
	if grid then
		for _, cell in grid:cells() do
			local uid = cell:GetAttribute("Uid")
			if type(uid) == "string" and gone[uid] and cell.Visible then
				local hit = cell:FindFirstChild("Hit") :: TextButton
				stopShrink(hit)
				local tween = Juice.tween(
					Juice.scaleOf(hit),
					SHRINK_TIME,
					{ Scale = 0 },
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
				shrinking[hit] = { uid = uid, tween = tween }
			end
		end
	end
	-- si le serveur refuse (verrou posé entre-temps…), les cases reviennent
	task.delay(1, function()
		for hit, shrink in table.clone(shrinking) do
			if gone[shrink.uid] then
				stopShrink(hit)
			end
		end
		if built then
			refreshStashCells()
		end
	end)
	focusUid = nil
	setSelectMode(false)
end

local function onReleasePressed()
	if armedAt ~= nil and armedClock - armedAt <= CONFIRM_WINDOW then
		disarm()
		doRelease()
		return
	end
	armedAt = armedClock
	renderAction()
end

local function onLockPressed()
	local uid = focusUid
	local rec = if uid then nebbies()[uid] else nil
	if not uid or not Model.validRecord(rec) then
		return
	end
	disarm()
	Net.event("SetLock"):FireServer(uid, rec.lk ~= true)
end

-- ---------------------------------------------------------------------------------------------
-- Forge
-- ---------------------------------------------------------------------------------------------

local function forgeRow(i: number, parent: Instance): ForgeRow
	local frame =
		Widgets.card({ name = "Fusion" .. i, size = UDim2.new(1, -12, 0, 96), order = i, parent = parent })
	local materials: { Frame } = {}
	for k = 1, Balance.Starforge.Copies do
		local icon = Widgets.nebbyIcon("Material" .. k, UDim2.fromOffset(60, 60), frame)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8 + (k - 1) * 50, 0.5, 0)
		materials[k] = icon
	end
	local arrowX = 8 + Balance.Starforge.Copies * 50 + 16
	Widgets.label({
		name = "Arrow",
		text = "→",
		size = UDim2.fromOffset(32, 40),
		position = UDim2.new(0, arrowX, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Theme.Colors.Gold,
		maxSize = 32,
		parent = frame,
	})
	local result = Widgets.nebbyIcon("Result", UDim2.fromOffset(76, 76), frame)
	result.AnchorPoint = Vector2.new(0, 0.5)
	result.Position = UDim2.new(0, arrowX + 36, 0.5, 0)
	local textX = arrowX + 120
	local count = Widgets.label({
		name = "Count",
		size = UDim2.new(1, -(textX + 160), 0, 30),
		position = UDim2.fromOffset(textX, 14),
		xAlign = Enum.TextXAlignment.Left,
		font = Theme.Fonts.Body,
		color = Theme.Colors.TextDim,
		maxSize = 18,
		parent = frame,
	})
	local cost = Widgets.label({
		name = "Cost",
		size = UDim2.new(1, -(textX + 160), 0, 32),
		position = UDim2.fromOffset(textX, 48),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Premium,
		maxSize = 24,
		parent = frame,
	})
	local row: ForgeRow
	local fuse = Widgets.button({
		name = "Fuse",
		size = UDim2.fromOffset(144, 72),
		position = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.Premium,
		maxText = 26,
		parent = frame,
		onClick = function()
			local group = row.group
			if group and group.affordable then
				Net.event("Fuse"):FireServer(group.chosen)
			end
		end,
		onRefused = function()
			local group = row.group
			if group and not group.fusable then
				Toast.show(Prefs.t("feedback.nebbyLocked"), "warning")
			elseif group then
				local missing = group.cost - Model.count(view.stardust)
				Toast.show(
					Prefs.t("feedback.notEnoughStardust", { missing = Prefs.number(missing) }),
					"error"
				)
			end
		end,
	})
	row = {
		frame = frame,
		materials = materials,
		result = result,
		count = count,
		cost = cost,
		fuse = fuse,
		group = nil,
	}
	return row
end

local function renderForge()
	local groups = Model.fuseGroups(view)
	if forgeHint then
		forgeHint.Text = Prefs.t("collection.forgeHint")
	end
	if fuseAllButton then
		Widgets.setText(fuseAllButton, Prefs.t("collection.fuseAll"))
		Widgets.setEnabled(fuseAllButton, Model.canFuseAny(view))
	end
	if forgeEmpty then
		forgeEmpty.Text = Prefs.t("collection.noFusion")
		forgeEmpty.Visible = #groups == 0
	end
	local list = forgeList
	if not list then
		return
	end
	local shown = math.min(#groups, FORGE_ROWS)
	for i = #forgeRows + 1, shown do
		forgeRows[i] = forgeRow(i, list)
	end
	for i, row in forgeRows do
		local group = groups[i]
		if i > shown or group == nil then
			row.frame.Visible = false
			row.group = nil
		else
			row.frame.Visible = true
			row.group = group
			local look: Widgets.NebbyLook = { s = group.s, f = group.f, v = group.v, stars = group.stars }
			for _, icon in row.materials do
				Widgets.setNebby(icon, look)
			end
			Widgets.setNebby(row.result, { s = group.s, f = group.f, v = group.v, stars = group.stars + 1 })
			local species = Nebbies.Species[group.s]
			row.count.Text = `{if species then species.name else "?"} ×{#group.uids}`
			row.cost.Text = Prefs.t("collection.fuseCost", { cost = Prefs.number(group.cost) })
			Widgets.setText(row.fuse, Prefs.t("collection.fuse"))
			Widgets.setEnabled(row.fuse, group.affordable)
		end
	end
end

local function buildForgeFx(parent: Instance)
	local root = Create("Frame", {
		Name = "ForgeFx",
		BackgroundColor3 = Color3.fromRGB(20, 16, 36),
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	}, { Widgets.corner(Theme.CornerSmall) }) :: Frame
	fx.root = root
	for k = 1, Balance.Starforge.Copies do
		local icon = Widgets.nebbyIcon("Orbit" .. k, UDim2.fromOffset(64, 64), root)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		fx.orbit[k] = icon
	end
	local resultScale = Create("UIScale", { Scale = 0 })
	local result = Widgets.nebbyIcon("Result", UDim2.fromOffset(140, 140), root)
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.fromScale(0.5, 0.45)
	resultScale.Parent = result
	fx.result = result
	fx.resultScale = resultScale
	fx.stars = Widgets.label({
		name = "Stars",
		size = UDim2.fromOffset(240, 40),
		position = UDim2.fromScale(0.5, 0.68),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.Gold,
		maxSize = 36,
		zIndex = 22,
		parent = root,
	})
	fx.stamp = Widgets.label({
		name = "Stamp",
		size = UDim2.fromOffset(300, 64),
		position = UDim2.fromScale(0.5, 0.82),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.Gold,
		font = Widgets.STAMP_FONT,
		maxSize = 56,
		zIndex = 22,
		parent = root,
	})
	fx.flash = Create("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 25,
		Parent = root,
	}, { Widgets.corner(Theme.CornerSmall) }) :: Frame
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.ZIndex < 21 then
			d.ZIndex = 21
		end
	end
	if fx.flash then
		fx.flash.ZIndex = 25
	end
end

-- Lance l'animation Starforge (Celebrate "starforge" : uid, s, f, v, stars)
local function playForge(data: { [string]: any })
	local s, f, v, stars = data.s, data.f, data.v, data.stars
	if type(s) ~= "number" or Nebbies.Species[s] == nil or type(stars) ~= "number" then
		return
	end
	local root = fx.root
	if not root then
		return
	end
	local a: ForgeAnim = {
		t = 0,
		s = s,
		f = if type(f) == "number" then f else 0,
		v = if type(v) == "number" then v else 0,
		stars = math.clamp(math.floor(stars), 1, Nebbies.MAX_STARS),
		flashed = false,
		shown = 0,
	}
	anim = a
	root.Visible = true
	for _, icon in fx.orbit do
		icon.Visible = true
		Widgets.setNebby(icon, { s = a.s, f = a.f, v = a.v, stars = a.stars - 1 })
	end
	if fx.result then
		Widgets.setNebby(fx.result, { s = a.s, f = a.f, v = a.v, stars = a.stars })
		fx.result.Visible = false
	end
	if fx.stars then
		fx.stars.Text = ""
	end
	if fx.stamp then
		fx.stamp.Text = ""
	end
	if Juice.reducedMotion() then
		-- Mouvement réduit : le résultat apparaît directement
		a.t = ORBIT_TIME
	end
end

local function stepForge(dt: number)
	local a = anim
	local root = fx.root
	if not a or not root then
		return
	end
	a.t += dt
	local t = a.t
	if t < ORBIT_TIME then
		-- 3 icônes tournent autour du centre en accélérant
		local alpha = t / ORBIT_TIME
		local angle = alpha * alpha * math.pi * 6
		local radius = 110 * (1 - 0.8 * alpha)
		for k, icon in fx.orbit do
			local theta = angle + (k - 1) * math.pi * 2 / #fx.orbit
			icon.Position = UDim2.new(0.5, math.cos(theta) * radius, 0.45, math.sin(theta) * radius)
		end
		return
	end
	if not a.flashed then
		a.flashed = true
		for _, icon in fx.orbit do
			icon.Visible = false
		end
		local flash = fx.flash
		if flash and not Juice.reducedMotion() then
			flash.BackgroundTransparency = 0.1
			Juice.tween(flash, FLASH_TIME, { BackgroundTransparency = 1 })
		end
		local result, scale = fx.result, fx.resultScale
		if result and scale then
			result.Visible = true
			if Juice.reducedMotion() then
				scale.Scale = 1
			else
				scale.Scale = 0
				Juice.tween(
					scale,
					RESULT_TIME,
					{ Scale = 1 },
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				)
			end
		end
		if fx.stamp then
			fx.stamp.Text = Prefs.t("collection.forged", { stars = a.stars })
			Juice.pulse(fx.stamp, 1.3)
		end
		AudioController.play("LevelUp")
	end
	-- les étoiles apparaissent une à une (0,1 s)
	local wanted = math.clamp(math.floor((t - ORBIT_TIME - RESULT_TIME) / STAR_EVERY) + 1, 0, a.stars)
	if wanted ~= a.shown and fx.stars then
		a.shown = wanted
		fx.stars.Text = string.rep("★", wanted)
	end
	if t >= ORBIT_TIME + RESULT_TIME + STAR_EVERY * a.stars + ANIM_HOLD then
		anim = nil
		root.Visible = false
	end
end

-- ---------------------------------------------------------------------------------------------
-- Atlas
-- ---------------------------------------------------------------------------------------------

-- « Rare · Mid Glade, Crater · ★★★ » : rareté, zones où elle apparaît (Config/Zones), meilleur
-- exemplaire possédé (rien s'il n'en possède aucun)
local function speciesDetail(s: number, bestStars: number?): string
	local rarityId = Nebbies.rarityOf(s)
	local rarity = Nebbies.Rarities[rarityId]
	local parts = { Prefs.t("rarity." .. (if rarity then rarity.key else "common")) }
	local zones = {}
	for _, zone in Zones.List do
		for _, odd in zone.odds do
			if odd.rarity == rarityId and odd.weight > 0 then
				table.insert(zones, Prefs.t("zone." .. zone.key))
				break
			end
		end
	end
	if #zones > 0 then
		table.insert(parts, table.concat(zones, ", "))
	end
	if bestStars ~= nil and bestStars >= 1 then
		table.insert(parts, string.rep("★", math.clamp(math.floor(bestStars), 1, Nebbies.MAX_STARS)))
	end
	return table.concat(parts, " · ")
end

local function atlasCell(name: string, parent: Instance): Frame
	local cell = Create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(ATLAS_CELL, ATLAS_CELL),
		BackgroundColor3 = Widgets.DIM,
		Parent = parent,
	}, { Widgets.round(), Widgets.stroke(nil, 2) }) :: Frame
	Create("TextLabel", {
		Name = "Q",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.Fonts.Title,
		Text = "?",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 22,
		Parent = cell,
	})
	Create("TextLabel", {
		Name = "New",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -6),
		Size = UDim2.fromOffset(22, 22),
		FontFace = Theme.Fonts.Title,
		Text = "✦",
		TextColor3 = Theme.Colors.Gold,
		TextSize = 20,
		Visible = false,
		ZIndex = 3,
		Parent = cell,
	})
	return cell
end

local function buildAtlasRows(list: ScrollingFrame)
	local forms = Nebbies.enabledForms()
	for i, s in Model.atlasSpecies() do
		local row = Widgets.card({
			name = "Species" .. s,
			size = UDim2.new(1, -12, 0, ATLAS_ROW),
			order = i,
			parent = list,
		})
		local name = Widgets.label({
			name = "Name",
			size = UDim2.new(0.3, -8, 0.55, -4),
			position = UDim2.fromOffset(10, 4),
			xAlign = Enum.TextXAlignment.Left,
			maxSize = 20,
			parent = row,
		})
		local detail = Widgets.label({
			name = "Detail",
			size = UDim2.new(0.3, -8, 0.45, -4),
			position = UDim2.new(0, 10, 0.55, 0),
			xAlign = Enum.TextXAlignment.Left,
			color = Theme.Colors.TextDim,
			font = Theme.Fonts.Body,
			maxSize = 14,
			parent = row,
		})
		local cells: { [number]: Frame } = {}
		for k, f in forms do
			local cell = atlasCell("Form" .. f, row)
			cell.AnchorPoint = Vector2.new(0, 0.5)
			cell.Position = UDim2.new(0.3, (k - 1) * (ATLAS_CELL + 8), 0.5, 0)
			cells[f] = cell
		end
		local complete = Widgets.label({
			name = "Complete",
			text = "★",
			size = UDim2.fromOffset(36, 36),
			position = UDim2.new(1, -8, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			color = Theme.Colors.Gold,
			maxSize = 30,
			parent = row,
		})
		atlasRows[s] = { name = name, detail = detail, cells = cells, complete = complete }
	end
end

local function renderAtlas()
	local p = view
	local locked = Model.atlasLocked(p)
	if atlasLocked then
		atlasLocked.Text = "🔒 " .. Prefs.t("atlas.locked")
		atlasLocked.Visible = locked
	end
	if atlasList then
		atlasList.Visible = not locked
	end
	local total = Nebbies.atlasTotal()
	local count = Model.atlasCount(p)
	if atlasHeader then
		atlasHeader.Text = Prefs.t("atlas.progress", { n = count, total = total })
	end
	if atlasBar then
		Widgets.setBar(atlasBar, if total > 0 then count / total else 0, false)
	end
	if atlasNext then
		local nextMilestone = Model.nextAtlasMilestone(count)
		atlasNext.Text = if nextMilestone
			then Prefs.t("atlas.nextMilestone", { n = nextMilestone.entries })
			else Prefs.t("atlas.allMilestones")
	end
	local species = Model.atlasSpecies()
	if atlasBadges then
		local parts = {}
		for _, key in { "golden", "huge" } do
			local n = 0
			for _, s in species do
				if Model.hasBadge(p, key, s) then
					n += 1
				end
			end
			table.insert(
				parts,
				Prefs.t("atlas.badgeLine", { name = Prefs.t("variant." .. key), n = n, total = #species })
			)
		end
		atlasBadges.Text = Prefs.t("atlas.badges") .. " — " .. table.concat(parts, " · ")
	end
	-- meilleur exemplaire possédé de chaque espèce (étoiles)
	local best: { [number]: number } = {}
	for _, rec in nebbies() do
		if Model.validRecord(rec) and rec.st > (best[rec.s] or 0) then
			best[rec.s] = rec.st
		end
	end
	for s, row in atlasRows do
		local def = Nebbies.Species[s]
		local complete = Model.speciesComplete(p, s)
		row.name.Text = def.name
		row.detail.Text = speciesDetail(s, best[s])
		row.name.TextColor3 = if complete then Theme.Colors.Gold else Theme.Colors.Text
		row.complete.Visible = complete
		for f, cell in row.cells do
			local known = Model.hasAtlasEntry(p, s, f)
			local q = cell:FindFirstChild("Q") :: TextLabel
			local new = cell:FindFirstChild("New") :: TextLabel
			cell.BackgroundColor3 = if known then Widgets.nebbyColor(s, f, 0) else Widgets.DIM
			q.Visible = not known
			new.Visible = known and fresh[Nebbies.atlasIndex(s, f)] == true
			Widgets.highlight(cell, new.Visible, Theme.Colors.Gold)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Guide (probabilités lues dans la configuration)
-- ---------------------------------------------------------------------------------------------

local function renderGuide()
	local list = guideList
	if not list then
		return
	end
	-- contenu figé (Config) : une reconstruction par langue, jamais à chaque patch du profil
	local lang = Prefs.language()
	if guideLang == lang then
		return
	end
	guideLang = lang
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local order = 0
	local function line(text: string, header: boolean?, color: Color3?)
		order += 1
		Widgets.label({
			name = if header then "Header" .. order else "Line" .. order,
			text = text,
			size = UDim2.new(1, -16, 0, if header then 36 else 28),
			xAlign = Enum.TextXAlignment.Left,
			color = color or (if header then Theme.Colors.Gold else Theme.Colors.Text),
			font = if header then Theme.Fonts.Title else Theme.Fonts.Body,
			maxSize = if header then 26 else 19,
			order = order,
			parent = list,
		})
	end
	local function rarityName(id: number): string
		local def = Nebbies.Rarities[id]
		return Prefs.t("rarity." .. (if def then def.key else "common"))
	end
	line(Prefs.t("guide.free"), false, Theme.Colors.TextDim)
	-- zones (§4.3)
	line(Prefs.t("guide.zones"), true)
	for _, zone in Zones.List do
		local sum = 0
		for _, odd in zone.odds do
			sum += odd.weight
		end
		local parts = {}
		for _, odd in zone.odds do
			table.insert(
				parts,
				Prefs.t(
					"guide.oddsLine",
					{ name = rarityName(odd.rarity), chance = pct(odd.weight / sum * 100) }
				)
			)
		end
		line(Prefs.t("zone." .. zone.key) .. " — " .. table.concat(parts, " · "))
	end
	-- météo (§4.4, §4.15.1)
	line(Prefs.t("guide.weather"), true)
	line(
		Prefs.t("guide.weatherChancePct", { chance = pctNumber(Balance.Spawn.WeatherFormChance * 100) }),
		false,
		Theme.Colors.TextDim
	)
	local weatherSum = 0
	for _, kind in Events.Weather.Kinds do
		if Nebbies.isVersionEnabled(kind.version) then
			weatherSum += kind.weight
		end
	end
	for _, kind in Events.Weather.Kinds do
		if Nebbies.isVersionEnabled(kind.version) then
			local freq = pct(kind.weight / weatherSum * 100)
			local form = if kind.form ~= nil then Nebbies.Forms[kind.form] else nil
			if form then
				line(Prefs.t("guide.formLine", {
					weather = Prefs.t("weather." .. kind.key),
					form = Prefs.t("form." .. form.key),
					mult = form.mult,
					chance = freq,
				}))
			else
				line(Prefs.t("guide.spawnsLine", {
					weather = Prefs.t("weather." .. kind.key),
					div = kind.intervalDiv or 1,
					chance = freq,
				}))
			end
		end
	end
	-- Comète (§4.15.2)
	line(Prefs.t("guide.comet"), true)
	local cometSum = 0
	for _, entry in Balance.Comet.Content do
		cometSum += entry.weight
	end
	local cometParts = {}
	for _, entry in Balance.Comet.Content do
		table.insert(
			cometParts,
			Prefs.t(
				"guide.oddsLine",
				{ name = rarityName(entry.rarity), chance = pct(entry.weight / cometSum * 100) }
			)
		)
	end
	line(table.concat(cometParts, " · "))
	-- variantes (§4.4)
	line(Prefs.t("guide.variants"), true)
	for _, key in Nebbies.VARIANT_ORDER do
		local def = Nebbies.Variants[key]
		if def then
			line(Prefs.t("guide.variantLine", {
				name = Prefs.t("variant." .. key),
				mult = def.mult,
				chance = if def.chance then pct(def.chance * 100) else Prefs.t("guide.eventOnly"),
			}))
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------------

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

local function buildPerches(parent: Frame)
	perchHeader = Widgets.label({
		name = "Header",
		size = UDim2.new(0.6, 0, 0, 36),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 26,
		parent = parent,
	})
	perchTotal = Widgets.label({
		name = "Total",
		size = UDim2.new(0.4, 0, 0, 36),
		position = UDim2.fromScale(0.6, 0),
		xAlign = Enum.TextXAlignment.Right,
		color = Theme.Colors.Gold,
		maxSize = 26,
		parent = parent,
	})
	local grid = scroll("Grid", parent, UDim2.fromOffset(0, 44), UDim2.new(1, 0, 1, -44))
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(PERCH_CELL.X, PERCH_CELL.Y),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = grid,
	})
	perchGrid = grid
	perchEmpty = Widgets.label({
		name = "Empty",
		size = UDim2.new(1, -40, 0, 40),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.TextDim,
		maxSize = 22,
		parent = parent,
	})
end

local function buildStash(parent: Frame)
	local toolbar = Create("Frame", {
		Name = "Toolbar",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		Parent = parent,
	}, { Widgets.listLayout(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })
	stashCount = Widgets.label({
		name = "Count",
		size = UDim2.new(0.2, 0, 1, 0),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 22,
		order = 1,
		parent = toolbar,
	})
	for i, mode in { "income", "rarity", "recent" } do
		sortButtons[mode] = Widgets.button({
			name = "Sort_" .. mode,
			size = UDim2.new(0.18, 0, 1, 0),
			color = Widgets.CARD,
			maxText = 18,
			order = 1 + i,
			parent = toolbar,
			onClick = function()
				sortMode = mode :: SortMode
				renderStash()
			end,
		})
	end
	selectButton = Widgets.button({
		name = "Select",
		size = UDim2.new(0.22, -8, 1, 0),
		color = Widgets.CARD,
		maxText = 18,
		order = 9,
		parent = toolbar,
		onClick = function()
			setSelectMode(not selectMode)
		end,
	})
	local grid = VirtualGrid.new({
		name = "Grid",
		parent = parent,
		cell = STASH_CELL,
		gap = 8,
		position = UDim2.fromOffset(0, 56),
		size = UDim2.new(1, 0, 1, -(56 + 76)),
		create = createStashCell,
		bind = bindStashCell,
	})
	stashGrid = grid
	stashEmpty = Widgets.label({
		name = "Empty",
		size = UDim2.new(1, -40, 0, 40),
		position = UDim2.fromScale(0.5, 0.45),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.TextDim,
		maxSize = 22,
		parent = parent,
	})
	local bar = Widgets.card({
		name = "Actions",
		size = UDim2.new(1, 0, 0, 68),
		position = UDim2.new(0, 0, 1, 0),
		anchor = Vector2.new(0, 1),
		parent = parent,
	})
	actionLabel = Widgets.label({
		name = "Detail",
		size = UDim2.new(1, -330, 1, -12),
		position = UDim2.fromOffset(10, 6),
		xAlign = Enum.TextXAlignment.Left,
		font = Theme.Fonts.Body,
		maxSize = 20,
		parent = bar,
	})
	lockButton = Widgets.button({
		name = "Lock",
		size = UDim2.fromOffset(120, 56),
		position = UDim2.new(1, -184, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Widgets.CARD,
		maxText = 20,
		parent = bar,
		onClick = onLockPressed,
	})
	releaseButton = Widgets.button({
		name = "Release",
		size = UDim2.fromOffset(170, 56),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.Warning,
		maxText = 18,
		parent = bar,
		onClick = onReleasePressed,
		onRefused = function()
			-- Nebby choisi verrouillé ou Cosmique (en sélection vide : la secousse suffit)
			local rec = if focusUid and not selectMode then nebbies()[focusUid] else nil
			if Model.validRecord(rec) then
				Toast.show(
					Prefs.t(if rec.lk == true then "feedback.nebbyLocked" else "feedback.cannotRelease"),
					"warning"
				)
			end
		end,
	})
	cancelButton = Widgets.button({
		name = "Cancel",
		size = UDim2.fromOffset(120, 56),
		position = UDim2.new(1, -184, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Widgets.CARD,
		maxText = 20,
		parent = bar,
		onClick = function()
			setSelectMode(false)
		end,
	})
	cancelButton.Visible = false
end

local function buildForge(parent: Frame)
	forgeHint = Widgets.label({
		name = "Hint",
		size = UDim2.new(1, -200, 0, 56),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 20,
		parent = parent,
	})
	fuseAllButton = Widgets.button({
		name = "FuseAll",
		size = UDim2.fromOffset(188, 56),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.Premium,
		maxText = 22,
		parent = parent,
		onClick = function()
			Net.event("FuseAll"):FireServer()
		end,
	})
	local list = scroll("List", parent, UDim2.fromOffset(0, 64), UDim2.new(1, 0, 1, -64))
	Widgets.listLayout(Enum.FillDirection.Vertical, 8).Parent = list
	forgeList = list
	forgeEmpty = Widgets.label({
		name = "Empty",
		size = UDim2.new(1, -40, 0, 40),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.TextDim,
		maxSize = 22,
		parent = parent,
	})
end

local function buildAtlas(parent: Frame)
	atlasHeader = Widgets.label({
		name = "Progress",
		size = UDim2.new(0.25, 0, 0, 36),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 28,
		parent = parent,
	})
	atlasBar = Widgets.bar({
		name = "Bar",
		size = UDim2.new(0.4, 0, 0, 14),
		position = UDim2.new(0.25, 0, 0, 11),
		color = Theme.Colors.Gold,
		parent = parent,
	})
	atlasNext = Widgets.label({
		name = "Next",
		size = UDim2.new(0.33, 0, 0, 36),
		position = UDim2.fromScale(0.67, 0),
		xAlign = Enum.TextXAlignment.Right,
		maxSize = 20,
		parent = parent,
	})
	atlasBadges = Widgets.label({
		name = "Badges",
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 40),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 18,
		parent = parent,
	})
	local list = scroll("List", parent, UDim2.fromOffset(0, 72), UDim2.new(1, 0, 1, -72))
	Widgets.listLayout(Enum.FillDirection.Vertical, 6).Parent = list
	atlasList = list
	buildAtlasRows(list)
	atlasLocked = Widgets.label({
		name = "Locked",
		size = UDim2.new(1, -60, 0, 60),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.TextDim,
		maxSize = 28,
		parent = parent,
	})
end

local function buildGuide(parent: Frame)
	local list = scroll("List", parent, UDim2.new(), UDim2.fromScale(1, 1))
	Widgets.listLayout(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left).Parent = list
	Create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = list })
	guideList = list
end

local function renderTab(id: string)
	if id == "perches" then
		renderPerches()
	elseif id == "stash" then
		renderStash()
	elseif id == "forge" then
		renderForge()
	elseif id == "atlas" then
		renderAtlas()
	elseif id == "guide" then
		renderGuide()
	end
end

local function leaveAtlas()
	if atlasSeen then
		atlasSeen = false
		fresh = {}
	end
end

function Panel.build(parent: Frame)
	if built then
		return
	end
	built = true
	buildPerches(tabFrame("perches", parent))
	buildStash(tabFrame("stash", parent))
	buildForge(tabFrame("forge", parent))
	buildAtlas(tabFrame("atlas", parent))
	buildGuide(tabFrame("guide", parent))
	buildForgeFx(parent)

	State.Changed:Connect(function(key: string)
		if
			key == "nebbies"
			or key == "upgrades"
			or key == "atlas"
			or key == "badges"
			or key == "passes"
			or key == "stardust"
			or key == "idleRate"
			or key == "perchIncome"
			or key == "onboarding"
		then
			dirty = true
		end
	end)
	Prefs.LanguageChanged:Connect(function()
		if isOpen then
			renderTab(currentTab)
		else
			dirty = true
		end
	end)
	ScreenFX.Celebrated:Connect(function(payload: Types.CelebratePayload)
		if type(payload) ~= "table" or type(payload.data) ~= "table" then
			return
		end
		if payload.kind == "starforge" and isOpen then
			playForge(payload.data)
		elseif payload.kind == "atlasNew" and type(payload.data.entries) == "table" then
			for _, entry in payload.data.entries do
				if type(entry) == "table" and type(entry.s) == "number" and type(entry.f) == "number" then
					fresh[Nebbies.atlasIndex(entry.s, entry.f)] = true
				end
			end
			dirty = true
		end
	end)
end

function Panel.onOpen(_args: any?)
	isOpen = true
	dirty = false
	renderTab(currentTab)
end

function Panel.onClose()
	isOpen = false
	if selectMode then
		setSelectMode(false)
	end
	focusUid = nil
	disarm()
	if currentTab == "atlas" then
		leaveAtlas()
	end
	anim = nil
	if fx.root then
		fx.root.Visible = false
	end
end

function Panel.hasAction(): boolean
	return Model.canFuseAny(view)
end

function Panel.selectTab(tab: string)
	local id = string.match(tab, "([^%.]+)$") or tab
	if not table.find(TAB_IDS, id) then
		return
	end
	if currentTab == "atlas" and id ~= "atlas" then
		leaveAtlas()
	end
	if currentTab == "stash" and id ~= "stash" and selectMode then
		setSelectMode(false)
	end
	currentTab = id
	for key, frame in tabFrames do
		frame.Visible = key == id
	end
	if id == "atlas" then
		atlasSeen = true
	end
	renderTab(id)
end

function Panel.step(dt: number)
	if not built then
		return
	end
	armedClock += dt
	if armedAt ~= nil and armedClock - armedAt > CONFIRM_WINDOW then
		armedAt = nil
		renderAction()
	end
	if dirty and isOpen then
		dirty = false
		renderTab(currentTab)
	end
	stepForge(dt)
end

function Panel.defaultSelection(): GuiObject?
	if currentTab == "forge" then
		return fuseAllButton
	elseif currentTab == "stash" then
		return selectButton
	end
	return nil
end

-- Exposé pour les tests
Panel._state = function()
	return {
		tab = currentTab,
		sortMode = sortMode,
		sorted = sortedUids,
		selectMode = selectMode,
		selected = selected,
		selectedCount = selectedCount,
		focusUid = focusUid,
		armed = armedAt ~= nil,
		anim = anim,
		fresh = fresh,
		grid = stashGrid,
		forgeRows = forgeRows,
		atlasRows = atlasRows,
	}
end
Panel._tap = onStashTap
Panel._release = onReleasePressed
Panel._lock = onLockPressed
Panel._setSelectMode = setSelectMode
Panel._setSort = function(mode: SortMode)
	sortMode = mode
	renderStash()
end

return Panel
