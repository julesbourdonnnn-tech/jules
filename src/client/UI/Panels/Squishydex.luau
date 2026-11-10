--!strict
-- Squishydex (paquet client-panels) : panneau du Squishydex (GDD §4.17, §10.3 v1.3 ; docs/04 §13.6,
-- contrat v1.2) :
--   * Espèces : une rangée par famille de 4 (Species.FamilyOrder ; les Secrets en dernier), silhouettes
--     grises pour ce qui manque ; ✕ sur une espèce ouvre sa FICHE : ses 9 mutations en 3 × 3
--     (silhouettes grises pour les autres, croissant de lune pour la Lunaire), ses badges d'étoiles
--     ★1 à ★5, sa taille record et son palier de l'Étagère (panel.dex.sheet.*) ; ○ revient à la case ;
--     jalons de tampons à réclamer (ClaimDexReward) ;
--   * Familles : bonus gagnés POUR TOUJOURS (dex.fam, QuestRules.familyEarned), sinon le R qui débloque
--     la famille dans la Cuve ;
--   * Guide : toutes les probabilités (Cuve de mon niveau, mutations), la protection contre la
--     malchance, le Golden, le MEGA, les Wild Wobblers, les cadeaux et les règles du BOOP RUSH ;
--     liste en lecture seule : ↑ / ↓ font défiler de 70 %.
-- Plus d'onglets Mutations (26 × 9) ni Étoiles (v1.2). Grille virtualisée (Widgets.rows). Nombres
-- géants par BigNumber. UiSeen("dex") à la première ouverture. Sélection par défaut : la 1re espèce ;
-- Guide : la 1re ligne. Ouvert sans onglet (menu, L2 / R2) : les Espèces, jamais le dernier onglet vu
-- (GDD §10.6 « 1re espèce » ; lot B3, B2-63 : rouvert sur les Familles, un chemin menu → case d'espèce
-- posait la sélection sur une case de la page cachée et FocusGuard la rattrapait).
-- v2.0 (lot B3, étape 4 ; plan B3 D13, D14, D24, D25 ; GDD v2.0 §4.17, §17.1) :
--   * onglet « Records » [RecordR, profil v2] : le Livre des records (UI/MetaView.records, lu dans le
--     profil SEUL), liste en lecture seule qui défile de 70 % comme le Guide (même code) ;
--   * maîtrise [Mastery, profil v2] : colonne de la fiche d'une espèce, à droite des mutations : le
--     compte « Maîtrises : n / m » puis les 3 cases (★5, page dorée, Trophée Cristal ; Owned.mastery par
--     MetaView.mastery), coche dessinée par case faite, les 3 dorées quand l'espèce est maîtrisée ;
--   * barre d'onglets de la v2.0, page Records et colonne de la maîtrise construites au premier besoin,
--     à l'ouverture (jamais écran ouvert) ; interrupteurs coupés : rien de la v2.0 n'est construit.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Layout = require(Shared.Config.Layout)
local Formulas = require(Shared.Logic.Formulas)
local Odds = require(Shared.Logic.Odds)
local QuestRules = require(Shared.Logic.QuestRules)
local Clock = require(Shared.Util.Clock)

local BigNumber = require(Shared.Logic.BigNumber)

local Client = script.Parent.Parent.Parent
local Juice = require(Client.UI.Juice)
local Prefs = require(Client.Util.Prefs)
local Format = require(Client.UI.Format)
local MetaFlags = require(Client.UI.MetaFlags)
local MetaView = require(Client.UI.MetaView)
local Icons = require(Client.UI.Hud.Icons)
local Widgets = require(script.Parent.Widgets)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }
type Family = { key: string, species: { number } }
type SpeciesCell = { button: TextButton, blob: Frame, name: TextLabel, info: TextLabel, species: number }
type SpeciesRow = { label: TextLabel, cells: { SpeciesCell } }
type FamilyRow =
	{ button: TextButton, name: TextLabel, bonus: TextLabel, status: TextLabel, blobs: { Frame } }
-- liste en lecture seule qui défile (Guide, Records) : un seul objet sélectionnable, ↑ / ↓ de 70 %
type ReadList = {
	tab: string,
	scroller: TextButton,
	holder: Frame,
	lines: { TextLabel },
	scroll: number,
	viewH: number,
	totalH: number,
}
type MasteryBox = { frame: Frame, label: TextLabel, check: Frame }
type MasteryParts = { holder: Frame, title: TextLabel, boxes: { MasteryBox } }

local Squishydex = {}

local TABS = { "species", "families", "guide" }
local V2_TABS = { "species", "families", "guide", "records" } -- v2.0 : le Livre des records en dernier
local RECORD_LINES = 10 -- lignes du Livre des records (MetaView.records en rend 10 au plus)
-- Profil répliqué sur les clés que lisent MetaView.records et la maîtrise (Owned.mastery)
local META_KEYS = {
	"version",
	"R",
	"bestR",
	"ascend",
	"biggestEver",
	"stats",
	"confettiTotal",
	"mastery",
	"plopDays",
	"hearts",
	"dex",
	"trophies",
}
local CELL = Layout.Panel.cell
local LABEL_W = 260
local PER_ROW = 4
local GUIDE_STEP = 0.7 -- ↑ / ↓ : 70 % de la hauteur visible (arrondi à des lignes entières)
local GUIDE_LINE = 48 -- px TV : pas des lignes du Guide

local nav: Nav? = nil
local tabBar: Widgets.TabBar? = nil
local current = "species"
local isOpen = false
local pages: { [string]: Frame } = {}
local families: { Family } = {}
local speciesRows: Widgets.Rows? = nil
local familyRows: Widgets.Rows? = nil
local header: { [string]: any } = {}
local sheet: Frame? = nil
local sheetSpecies = 0
local sheetFrom: TextButton? = nil
local sheetCells: { TextButton } = {}
local sheetStars: { TextLabel } = {}
local sheetLabels: { [string]: TextLabel } = {}
local sheetBlob: Frame? = nil
local guide: ReadList? = nil
-- v2.0 : barre construite (v1.3, ou celle de la v2.0 au premier besoin), Records, maîtrise
local barTabs: { string } = TABS
local buildContainer: Frame? = nil
local buildTop = 0
local records: ReadList? = nil
local mastery: MasteryParts? = nil

local MUTATION_BITS = 0
local GOLDEN_NEED = 0 -- page dorée : les 8 mutations hors Lunaire (GDD §4.17)
for _, def in Mutations.List do
	MUTATION_BITS = bit32.bor(MUTATION_BITS, bit32.lshift(1, def.id))
	if not Mutations.GoldenPageExcludes[def.id] then
		GOLDEN_NEED = bit32.bor(GOLDEN_NEED, bit32.lshift(1, def.id))
	end
end

-- Familles dans l'ordre (liste en ajout seul), puis toute espèce sans famille connue avec les Secrets
local function buildFamilies(): { Family }
	local out: { Family } = {}
	local placed: { [number]: boolean } = {}
	local secrets: Family? = nil
	for _, key in Species.FamilyOrder do
		local def = (Species.Families :: any)[key]
		if type(def) == "table" then
			local list = {}
			for _, s in def.species do
				if Species.ById[s] and Species.isReleased(Species.ById[s], Clock.unix()) then
					table.insert(list, s)
					placed[s] = true
				end
			end
			local fam = { key = key, species = list }
			if key == "secret" then
				secrets = fam
			else
				table.insert(out, fam)
			end
		end
	end
	local rest = if secrets then secrets else { key = "secret", species = {} }
	for _, def in Species.List do
		if not placed[def.id] and Species.isReleased(def, Clock.unix()) then
			table.insert(rest.species, def.id)
		end
	end
	if #rest.species > 0 then
		table.insert(out, rest)
	end
	return out
end

local function dex(): { [string]: any }
	return Widgets.tbl(Widgets.state("dex"))
end

local function maskOf(field: string, s: number): number
	local arr = Widgets.tbl(dex()[field])
	local v = arr[s]
	return if type(v) == "number" and v == v and v >= 0 then math.floor(v) else 0
end

local function hasBit(m: number, b: number): boolean
	return bit32.band(m, bit32.lshift(1, b)) ~= 0
end

local function popcount(m: number): number
	local n = 0
	local v = m
	while v ~= 0 do
		n += bit32.band(v, 1)
		v = bit32.rshift(v, 1)
	end
	return n
end

local function stamped(s: number): boolean
	return hasBit(maskOf("mut", s), 0)
end

local function totalStamps(): number
	return #Species.List * (Mutations.Count + 1)
end

-- =============================================================================================
-- Espèces
-- =============================================================================================

local function bindSpeciesRow(row: SpeciesRow, _frame: Frame, index: number)
	local fam = families[index]
	if fam == nil then
		return
	end
	Widgets.setText(row.label, "family." .. fam.key)
	for i, cell in row.cells do
		local s = fam.species[i]
		cell.species = s or 0
		cell.button.Visible = s ~= nil
		if s then
			local known = stamped(s)
			Widgets.paintBlob(cell.blob, s, known)
			if known then
				Widgets.setRaw(cell.name, Widgets.speciesName(s))
			else
				Widgets.setText(cell.name, "panel.dex.unknown")
			end
			local found = popcount(bit32.band(maskOf("mut", s), bit32.band(MUTATION_BITS, bit32.bnot(1))))
			Widgets.setText(cell.info, "panel.dex.found", { n = found, max = Mutations.Count })
			local golden = bit32.band(maskOf("mut", s), GOLDEN_NEED) == GOLDEN_NEED
			cell.button.BackgroundColor3 = if golden
				then Widgets.Colors.Gold
				elseif known then Widgets.rarityColor(Widgets.rarityOf(s))
					:Lerp(Widgets.Colors.Card, 0.65)
				else Widgets.Colors.Card
			-- case dorée (espèce complète) : nom et « 9 / 9 » bleu nuit sans contour. Blanc et lavande
			-- n'y étaient plus qu'un contour (1,46 et 1,3 sans le contour ; revue des écrans)
			local function ink(label: TextLabel, color: Color3)
				label.TextColor3 = if golden then Widgets.Colors.Stroke else color
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Enabled = not golden
				end
			end
			ink(cell.name, Widgets.Colors.Text)
			ink(cell.info, Widgets.Colors.TextDim)
		end
	end
end

local renderMastery: (s: number) -> () -- v2.0 (D14), défini plus bas

-- Contenu de la fiche d'une espèce (rappelé à chaque changement du profil tant qu'elle est ouverte)
local function renderSheet(s: number)
	local known = stamped(s)
	local def = Species.ById[s]
	Widgets.paintBlob(sheetBlob :: Frame, s, known)
	if known then
		Widgets.setRaw(sheetLabels.name, Widgets.speciesName(s))
	else
		Widgets.setText(sheetLabels.name, "panel.dex.unknown")
	end
	Widgets.setRaw(sheetLabels.family, Prefs.t("family." .. (if def then def.family else "secret")))
	local rarity = Rarities.List[if def then def.rarity else 1]
	Widgets.setText(sheetLabels.rarity, "rarity." .. (if rarity then rarity.key else "common"))
	sheetLabels.rarity.TextColor3 = Widgets.rarityColor(if def then def.rarity else 1)
	local m = maskOf("mut", s)
	local found = 0
	for i, mcell in sheetCells do
		local mdef = Mutations.List[i]
		local has = mdef ~= nil and hasBit(m, mdef.id)
		if has then
			found += 1
		end
		local label = Widgets.buttonLabel(mcell) :: TextLabel
		if has and mdef then
			Widgets.setText(label, "mutation." .. mdef.key)
			mcell.BackgroundColor3 = mdef.color:Lerp(Widgets.Colors.Card, 0.4)
		else
			Widgets.setText(label, "panel.dex.unknown")
			mcell.BackgroundColor3 = Widgets.Colors.Silhouette
		end
		local moon = mcell:FindFirstChild("Moon")
		if moon and moon:IsA("GuiObject") then
			moon.Visible = mdef ~= nil and mdef.id == Mutations.LUNAR and has
		end
	end
	Widgets.setText(sheetLabels.found, "panel.dex.sheet.found", { n = found, max = Mutations.Count })
	local stars = maskOf("stars", s)
	for k, label in sheetStars do
		local lit = hasBit(stars, k - 1)
		label.TextColor3 = if lit then Widgets.Colors.Gold else Widgets.Colors.LockedText
	end
	local trophies = Widgets.tbl(Widgets.state("trophies"))
	local record = math.max(0, Widgets.n(trophies[s]))
	Widgets.setText(sheetLabels.record, "panel.dex.record", { size = Widgets.num(record) })
	local tier = Widgets.safe("Formulas.trophyTier", 0, Formulas.trophyTier, record)
	local tierDef = Balance.Trophies[tier]
	if tierDef then
		sheetLabels.trophy.Visible = true
		Widgets.setText(sheetLabels.trophy, "panel.dex.trophy." .. tierDef.tier)
	else
		sheetLabels.trophy.Visible = false
	end
	renderMastery(s)
end

local function openSheet(cell: SpeciesCell)
	local s = cell.species
	local f = sheet
	if s <= 0 or f == nil then
		return
	end
	sheetSpecies = s
	sheetFrom = cell.button
	renderSheet(s)
	pages.species.Visible = false
	f.Visible = true
	GuiService.SelectedObject = sheetCells[1]
end

local function closeSheet()
	local f = sheet
	if f == nil or not f.Visible then
		return
	end
	f.Visible = false
	pages.species.Visible = current == "species"
	local back = sheetFrom
	sheetFrom = nil
	if back and back.Parent and back.Visible then
		GuiService.SelectedObject = back
	end
end

local function refreshHeader()
	local d = dex()
	local stamps = Widgets.safe("QuestRules.stampCount", 0, QuestRules.stampCount, d)
	Widgets.setText(header.count, "panel.dex.found", { n = stamps, max = totalStamps() })
	local pending =
		Widgets.safe("QuestRules.dexMilestones", {}, QuestRules.dexMilestones, stamps, Widgets.n(d.rewards))
	local claim = header.claim :: TextButton
	local has = type(pending) == "table" and #pending > 0
	claim.Visible = has
	Widgets.attention(claim, has)
	if has then
		Widgets.setText(header.milestone, "panel.dex.milestone", { n = pending[1].stamps })
	else
		Widgets.setRaw(header.milestone, "")
	end
end

-- =============================================================================================
-- Familles
-- =============================================================================================

local function bindFamilyRow(row: FamilyRow, _frame: Frame, index: number)
	local fam = families[index]
	if fam == nil then
		return
	end
	Widgets.setText(row.name, "family." .. fam.key)
	local def = (Species.Families :: any)[fam.key]
	local bonus = if type(def) == "table" then def.bonus else nil
	if bonus then
		Widgets.setText(row.bonus, "panel.dex.bonus." .. bonus.kind)
	else
		Widgets.setRaw(row.bonus, "")
	end
	for i, b in row.blobs do
		local s = fam.species[i]
		b.Visible = s ~= nil
		if s then
			Widgets.paintBlob(b, s, stamped(s))
		end
	end
	local earned = Widgets.safe("QuestRules.familyEarned", false, QuestRules.familyEarned, dex(), fam.key)
	local R = Widgets.n(Widgets.state("R"))
	local unlockR = if type(def) == "table" then def.unlockR else -1
	if earned then
		Widgets.setText(row.status, "panel.dex.familyComplete")
		-- blanc sur la rangée verte (vert sur vert : contraste 2,94 ; revue de l'outil d'écrans)
		row.status.TextColor3 = Widgets.Colors.Text
	elseif unlockR > 0 and R < unlockR then
		Widgets.setText(row.status, "panel.dex.familyLocked", { n = unlockR })
		row.status.TextColor3 = Widgets.Colors.TextDim
	else
		Widgets.setRaw(row.status, "")
	end
	row.button.BackgroundColor3 = if earned
		then Widgets.Colors.Success:Lerp(Widgets.Colors.Card, 0.6)
		else Widgets.Colors.Card
end

-- =============================================================================================
-- Guide (lecture seule, ↑ / ↓ font défiler de 70 %)
-- =============================================================================================

-- Chance en % avec `digits` décimales (UI/Format : virgule en français, « 52,0 ») ; une chance non nulle n'est jamais écrite « 0,0 % » (un
-- enfant y lirait « impossible ») : décimales ajoutées jusqu'au premier chiffre utile (4 au plus),
-- puis « < 0,0001 »
local function chanceText(p: number, digits: number): string
	local lang = Prefs.language()
	local function roundsToZero(d: number): boolean
		return math.floor(math.abs(p) * 10 ^ d + 0.5) == 0
	end
	local d = digits
	while p > 0 and roundsToZero(d) and d < 4 do
		d += 1
	end
	if p > 0 and roundsToZero(d) then
		return "< " .. Format.decimal(0.0001, lang, 4)
	end
	return Format.decimal(p, lang, d)
end

local function guideTexts(): { { text: string, title: boolean } }
	local out: { { text: string, title: boolean } } = {}
	local function title(key: string, vars: { [string]: any }?)
		table.insert(out, { text = Prefs.t(key, vars), title = true })
	end
	local function line(text: string)
		table.insert(out, { text = text, title = false })
	end
	local R = Widgets.n(Widgets.state("R"))
	local level: any =
		Widgets.safe("Formulas.vatLevel", { quality = 1, speed = 0, nozzles = 0 }, Formulas.vatLevel, R)
	local quality = Widgets.n(level.quality, 1)
	title("panel.dex.guide.vat", { q = quality })
	local table_: any = Widgets.safe("Odds.rarityTable", {}, Odds.rarityTable, quality)
	for i, rdef in Rarities.List do
		local p = Widgets.n(table_[i])
		line(Prefs.t("rarity." .. rdef.key) .. "  " .. Prefs.t("common.percent", { p = chanceText(p, 1) }))
	end
	local vat = Widgets.tbl(Widgets.state("vat"))
	line(
		Prefs.t(
			"panel.dex.guide.pityRare",
			{ n = math.max(0, Balance.Vat.PityRare - Widgets.n(vat.pityRare)) }
		)
	)
	line(
		Prefs.t(
			"panel.dex.guide.pityEpic",
			{ n = math.max(0, Balance.Vat.PityEpic - Widgets.n(vat.pityEpic)) }
		)
	)
	title("panel.dex.guide.mutations")
	local chances: any =
		Widgets.safe("Odds.mutationChances", {}, Odds.mutationChances, Widgets.n(level.nozzles), false, nil)
	for _, mdef in Mutations.List do
		local c = Widgets.n(chances[mdef.id])
		line(
			Prefs.t("mutation." .. mdef.key)
				.. " ×"
				.. Format.decimal(mdef.mult, Prefs.language())
				.. "  "
				.. Prefs.t("common.percent", {
					p = chanceText(c * 100, 2),
				})
		)
	end
	title("panel.dex.guide.golden")
	line(Prefs.t("panel.dex.guide.goldenLine"))
	title("panel.dex.guide.mega")
	local tiers = Events.Mega.Tiers
	line(Prefs.t("panel.dex.guide.megaLine", { n = tiers[#tiers].babies, m = Events.Mega.MutationMult }))
	title("panel.dex.guide.wild")
	line(Prefs.t("panel.dex.guide.wildLine", { q = Events.Wild.Quality }))
	title("panel.dex.guide.gifts")
	line(Prefs.t("panel.dex.guide.giftsLine", { n = Balance.Splorch.GiftSeconds }))
	title("panel.dex.guide.rush")
	for i = 1, 5 do
		line("• " .. Prefs.t("panel.dex.guide.rush." .. i))
	end
	return out
end

-- Défilement d'une liste en lecture seule (Guide, Records)
local function applyListScroll(list: ReadList, animate: boolean)
	-- défilement par lignes entières (GUIDE_LINE) et cadre d'un nombre entier de lignes : aucune
	-- ligne coupée en deux en haut ni en bas (outil d'écrans : « Givré ×3 » à moitié caché)
	local maxScroll = math.max(0, list.totalH - list.viewH)
	list.scroll = math.clamp(math.floor(list.scroll / GUIDE_LINE + 0.5) * GUIDE_LINE, 0, maxScroll)
	local goal = UDim2.fromOffset(0, -list.scroll)
	if animate and not Juice.reducedMotion() then
		Juice.tween(list.holder, 0.15, { Position = goal })
	else
		list.holder.Position = goal
	end
	-- en haut : ↑ remonte aux onglets ; ailleurs ↑ fait défiler (la sélection reste sur la liste)
	local scroller = list.scroller
	if tabBar then
		scroller.NextSelectionUp = if list.scroll <= 0 then tabBar.buttons[list.tab] else scroller
		scroller.NextSelectionDown = scroller
	end
end

local function refreshGuide()
	local list = guide
	if list == nil then
		return
	end
	local texts = guideTexts()
	local y = 0
	for i, label in list.lines do
		local entry = texts[i]
		label.Visible = entry ~= nil
		if entry then
			Widgets.setRaw(label, entry.text)
			label.TextColor3 = if entry.title then Widgets.Colors.Gold else Widgets.Colors.Text
			label.Position = UDim2.fromOffset(if entry.title then 0 else 32, y)
			y += GUIDE_LINE
		end
	end
	list.totalH = y
	applyListScroll(list, false)
end

local function onListInput(list: ReadList?, input: InputObject)
	if list == nil or not isOpen or current ~= list.tab or GuiService.SelectedObject ~= list.scroller then
		return
	end
	local step = math.max(GUIDE_LINE, math.floor(list.viewH * GUIDE_STEP / GUIDE_LINE) * GUIDE_LINE)
	if input.KeyCode == Enum.KeyCode.DPadDown then
		local before = list.scroll
		list.scroll += step
		applyListScroll(list, true)
		if list.scroll <= before then
			-- déjà en bas : le seul ↓ qui rebondit (son Bump, vibration listEnd)
			Widgets.listEnd(list.scroller, "Down")
		end
	elseif input.KeyCode == Enum.KeyCode.DPadUp and list.scroll > 0 then
		list.scroll -= step
		applyListScroll(list, true)
	end
end

-- =============================================================================================
-- v2.0 (lot B3, D13, D14) : Livre des records, maîtrise
-- =============================================================================================

local function recordsOn(): boolean
	return MetaFlags.v2Profile() and MetaFlags.on("RecordR")
end

local function masteryOn(): boolean
	return MetaFlags.v2Profile() and MetaFlags.on("Mastery")
end

local function lang(): string
	local ok, l = pcall(Prefs.language)
	return if ok and l == "fr" then "fr" else "en"
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

local function refreshRecords()
	local list = records
	if list == nil or not recordsOn() then
		return
	end
	local rows = MetaView.records(Widgets.profile(META_KEYS), { lang = lang(), on = MetaFlags.on })
	local y = 0
	for i, label in list.lines do
		local rec = rows[i]
		label.Visible = rec ~= nil
		if rec then
			setView(label, rec.text)
			label.Position = UDim2.fromOffset(0, y)
			y += GUIDE_LINE
		end
	end
	list.totalH = y
	applyListScroll(list, false)
end

-- Texte bleu nuit sans contour sur une case vive (faite, dorée), sinon la couleur donnée et le contour
local function ink(label: TextLabel, vivid: boolean, color: Color3)
	label.TextColor3 = if vivid then Widgets.Colors.Stroke else color
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = not vivid
	end
end

-- Colonne de la maîtrise de l'espèce s sur la fiche (cachée tant que Mastery est coupé)
renderMastery = function(s: number)
	local parts = mastery
	if parts == nil then
		return
	end
	local on = masteryOn()
	parts.holder.Visible = on
	if not on then
		return
	end
	local profile = Widgets.profile(META_KEYS)
	local l = lang()
	local n, m = MetaView.masteryCount(profile)
	Widgets.setText(parts.title, "records.mastery", { n = BigNumber.full(n, l), m = BigNumber.full(m, l) })
	local view = MetaView.mastery(profile, s)
	local done = { view.star5, view.golden, view.crystal }
	for i, box in parts.boxes do
		local ok = done[i] == true
		box.frame.BackgroundColor3 = if view.done
			then Widgets.Colors.Gold
			elseif ok then Widgets.Colors.Success
			else Widgets.Colors.Card
		ink(box.label, ok, Widgets.Colors.LockedText)
		Icons.draw(box.check, if ok then "check" else nil, Widgets.Colors.Stroke)
	end
end

-- =============================================================================================
-- Pages
-- =============================================================================================

local function showPage(tab: string)
	if sheet and sheet.Visible then
		sheet.Visible = false
		sheetFrom = nil
	end
	for id, page in pages do
		page.Visible = id == tab
	end
	if tabBar then
		-- onglet Records (v2.0) : seulement avec sa page et son interrupteur
		tabBar.setVisible("records", records ~= nil and recordsOn())
		tabBar.setActive(tab)
	end
end

local function refresh()
	families = buildFamilies()
	-- fiche ouverte : elle suit le profil (mutation trouvée, record battu pendant qu'on la regarde)
	if sheet and sheet.Visible and sheetSpecies > 0 then
		renderSheet(sheetSpecies)
	end
	refreshHeader()
	if speciesRows then
		speciesRows.setCount(#families)
	end
	if familyRows then
		familyRows.setCount(#families)
	end
	refreshGuide()
	refreshRecords()
end

local function buildSpecies(page: Frame)
	local width = page.Size.X.Offset
	header.count = Widgets.label({
		parent = page,
		name = "Count",
		size = UDim2.fromOffset(420, 48),
		position = UDim2.fromOffset(48, 0),
		text = "",
		textSize = 36,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	-- 40 px d'écart avec « Réclamer » : le bouton pulse jusqu'à 1,08 (GDD §9.2) vers la gauche (ancré à
	-- droite), soit 24 px, sans jamais toucher le texte
	header.milestone = Widgets.label({
		parent = page,
		name = "Milestone",
		size = UDim2.fromOffset(340, 48),
		position = UDim2.new(1, -48 - 300 - 40, 0, 0),
		anchor = Vector2.new(1, 0),
		text = "",
		textSize = 32,
		xAlign = Enum.TextXAlignment.Right,
	})
	header.claim = Widgets.button({
		parent = page,
		name = "Claim",
		size = UDim2.fromOffset(300, Layout.Button.MinHeight),
		position = UDim2.new(1, -48, 0, -16),
		anchor = Vector2.new(1, 0),
		key = "panel.dex.claim",
		color = Widgets.Colors.Success,
		onActivate = function()
			Widgets.send("ClaimDexReward")
		end,
	})
	local top = 72
	local gridW = LABEL_W + PER_ROW * (CELL.w + Layout.Spacing.Min)
	local left = math.floor((width - gridW) / 2)
	speciesRows = Widgets.rows({
		parent = page,
		name = "Species",
		size = Vector2.new(gridW, page.Size.Y.Offset - top - 8),
		position = UDim2.fromOffset(left, top),
		rowHeight = CELL.h,
		gap = Layout.Spacing.Min,
		makeRow = function(frame: Frame, _slot: number): SpeciesRow
			local label = Widgets.label({
				parent = frame,
				name = "Family",
				size = UDim2.fromOffset(LABEL_W - 16, 56),
				position = UDim2.new(0, 0, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				text = "",
				textSize = 40,
				color = Widgets.Colors.Gold,
				xAlign = Enum.TextXAlignment.Left,
			})
			local cells: { SpeciesCell } = {}
			for i = 1, PER_ROW do
				local cellRef: SpeciesCell
				local b = Widgets.button({
					parent = frame,
					name = "Cell" .. i,
					size = UDim2.fromOffset(CELL.w, CELL.h),
					position = UDim2.fromOffset(LABEL_W + (i - 1) * (CELL.w + Layout.Spacing.Min), 0),
					color = Widgets.Colors.Card,
					nav = i == 1,
					onActivate = function()
						openSheet(cellRef)
					end,
				})
				local blob = Widgets.blob(b, "Blob")
				blob.AnchorPoint = Vector2.new(0.5, 0)
				blob.Position = UDim2.new(0.5, 0, 0, 16)
				blob.Size = UDim2.fromOffset(110, 96)
				blob.ZIndex = b.ZIndex + 1
				local name = Widgets.label({
					parent = b,
					name = "Name",
					size = UDim2.new(1, -16, 0, 44),
					position = UDim2.fromOffset(8, 120),
					text = "",
					textSize = 32,
					zIndex = b.ZIndex + 2,
				})
				local info = Widgets.label({
					parent = b,
					name = "Info",
					size = UDim2.new(1, -16, 0, 36),
					position = UDim2.fromOffset(8, 172),
					text = "",
					textSize = 28,
					color = Widgets.Colors.TextDim,
					zIndex = b.ZIndex + 2,
				})
				cellRef = { button = b, blob = blob, name = name, info = info, species = 0 }
				cells[i] = cellRef
			end
			return { label = label, cells = cells }
		end,
		bindRow = bindSpeciesRow,
		selectables = function(row: SpeciesRow): { GuiObject }
			local out = {}
			for _, c in row.cells do
				table.insert(out, c.button)
			end
			return out
		end,
	})
end

local function buildSheet(container: Frame, top: number)
	local width = container.Size.X.Offset
	local f = Widgets.group(
		container,
		"Sheet",
		UDim2.fromOffset(width, container.Size.Y.Offset - top),
		UDim2.fromOffset(0, top)
	)
	f.Visible = false
	sheet = f
	local card = Widgets.frame({
		parent = f,
		name = "Card",
		size = UDim2.fromOffset(360, 520),
		position = UDim2.fromOffset(48, 8),
		color = Widgets.Colors.Card,
		gradient = true,
	})
	local blob = Widgets.blob(card, "Blob")
	blob.AnchorPoint = Vector2.new(0.5, 0)
	blob.Position = UDim2.new(0.5, 0, 0, 24)
	blob.Size = UDim2.fromOffset(200, 170)
	sheetBlob = blob
	sheetLabels.name = Widgets.label({
		parent = card,
		name = "Name",
		size = UDim2.new(1, -24, 0, 56),
		position = UDim2.fromOffset(12, 210),
		text = "",
		textSize = 44,
	})
	sheetLabels.family = Widgets.label({
		parent = card,
		name = "Family",
		size = UDim2.new(1, -24, 0, 40),
		position = UDim2.fromOffset(12, 270),
		text = "",
		textSize = 32,
		color = Widgets.Colors.TextDim,
	})
	sheetLabels.rarity = Widgets.label({
		parent = card,
		name = "Rarity",
		size = UDim2.new(1, -24, 0, 40),
		position = UDim2.fromOffset(12, 314),
		text = "",
		textSize = 32,
	})
	sheetLabels.record = Widgets.label({
		parent = card,
		name = "Record",
		size = UDim2.new(1, -24, 0, 40),
		position = UDim2.fromOffset(12, 370),
		text = "",
		textSize = 32,
		color = Widgets.Colors.Gold,
	})
	sheetLabels.trophy = Widgets.label({
		parent = card,
		name = "Trophy",
		size = UDim2.new(1, -24, 0, 40),
		position = UDim2.fromOffset(12, 414),
		text = "",
		textSize = 32,
	})
	-- 9 mutations en 3 × 3
	local gridLeft = 48 + 360 + 32
	Widgets.label({
		parent = f,
		name = "MutationsTitle",
		size = UDim2.fromOffset(320, 44),
		position = UDim2.fromOffset(gridLeft, 8),
		key = "panel.dex.sheet.mutations",
		textSize = 36,
		xAlign = Enum.TextXAlignment.Left,
	})
	sheetLabels.found = Widgets.label({
		parent = f,
		name = "Found",
		size = UDim2.fromOffset(300, 44),
		position = UDim2.fromOffset(gridLeft + 340, 8),
		text = "",
		textSize = 32,
		color = Widgets.Colors.TextDim,
		xAlign = Enum.TextXAlignment.Right,
	})
	local mw, mh = 200, 112
	for i = 1, 9 do
		local col = (i - 1) % 3
		local line = (i - 1) // 3
		local b = Widgets.button({
			parent = f,
			name = "Mutation" .. i,
			size = UDim2.fromOffset(mw, mh),
			position = UDim2.fromOffset(
				gridLeft + col * (mw + Layout.Spacing.Min),
				64 + line * (mh + Layout.Spacing.Min)
			),
			text = "",
			textSize = 32,
			color = Widgets.Colors.Silhouette,
			sound = "",
		})
		local moon = Widgets.frame({
			parent = b,
			name = "Moon",
			size = UDim2.fromOffset(24, 24),
			position = UDim2.new(1, -10, 0, 10),
			anchor = Vector2.new(1, 0),
			color = Color3.fromRGB(220, 225, 255),
			corner = UDim.new(0.5, 0),
			stroke = false,
			zIndex = b.ZIndex + 3,
		})
		moon.Visible = false
		sheetCells[i] = b
	end
	-- badges d'étoiles ★1 à ★5
	local starsTop = 64 + 3 * (mh + Layout.Spacing.Min) + 16
	Widgets.label({
		parent = f,
		name = "StarsTitle",
		size = UDim2.fromOffset(600, 44),
		position = UDim2.fromOffset(gridLeft, starsTop),
		key = "panel.dex.sheet.stars",
		textSize = 36,
		xAlign = Enum.TextXAlignment.Left,
	})
	for k = 1, 5 do
		sheetStars[k] = Widgets.label({
			parent = f,
			name = "Star" .. k,
			size = UDim2.fromOffset(112, 56),
			position = UDim2.fromOffset(gridLeft + (k - 1) * 124, starsTop + 52),
			key = "panel.dex.starBadge",
			vars = { n = k },
			textSize = 40,
			color = Widgets.Colors.LockedText,
		})
	end
end

local function buildFamiliesPage(page: Frame)
	local width = page.Size.X.Offset - 96
	familyRows = Widgets.rows({
		parent = page,
		name = "Families",
		size = Vector2.new(width, page.Size.Y.Offset - 8),
		position = UDim2.fromOffset(48, 0),
		rowHeight = 120,
		gap = Layout.Spacing.Min,
		makeRow = function(frame: Frame, _slot: number): FamilyRow
			local b = Widgets.button({
				parent = frame,
				name = "Family",
				size = UDim2.fromScale(1, 1),
				color = Widgets.Colors.Card,
				sound = "",
			})
			local name = Widgets.label({
				parent = b,
				name = "Name",
				size = UDim2.fromOffset(240, 56),
				position = UDim2.new(0, 24, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				text = "",
				textSize = 40,
				color = Widgets.Colors.Gold,
				xAlign = Enum.TextXAlignment.Left,
				zIndex = b.ZIndex + 1,
			})
			local blobs: { Frame } = {}
			for i = 1, PER_ROW do
				local blob = Widgets.blob(b, "Blob" .. i)
				blob.AnchorPoint = Vector2.new(0, 0.5)
				blob.Position = UDim2.new(0, 280 + (i - 1) * 96, 0.5, 0)
				blob.Size = UDim2.fromOffset(80, 70)
				blob.ZIndex = b.ZIndex + 1
				blobs[i] = blob
			end
			local bonus = Widgets.label({
				parent = b,
				name = "Bonus",
				size = UDim2.fromOffset(420, 48),
				position = UDim2.new(0, 280 + PER_ROW * 96 + 16, 0, 12),
				text = "",
				textSize = 32,
				xAlign = Enum.TextXAlignment.Left,
				zIndex = b.ZIndex + 1,
			})
			local status = Widgets.label({
				parent = b,
				name = "Status",
				size = UDim2.fromOffset(420, 44),
				position = UDim2.new(0, 280 + PER_ROW * 96 + 16, 0, 64),
				text = "",
				textSize = 28,
				xAlign = Enum.TextXAlignment.Left,
				zIndex = b.ZIndex + 1,
			})
			return { button = b, name = name, bonus = bonus, status = status, blobs = blobs }
		end,
		bindRow = bindFamilyRow,
		selectables = function(row: FamilyRow): { GuiObject }
			return { row.button }
		end,
	})
end

-- Liste en lecture seule qui défile (Guide, Records) : un seul bouton qui coupe ce qui dépasse, ses
-- lignes de 44 px dans un pas de 48 ; ↑ / ↓ la font défiler (onListInput)
local function buildReadList(page: Frame, name: string, count: number, tab: string, top: number?): ReadList
	local width = page.Size.X.Offset - 96
	-- hauteur visible : un nombre entier de lignes (voir applyListScroll)
	local viewH = math.max(GUIDE_LINE, math.floor((page.Size.Y.Offset - 16) / GUIDE_LINE) * GUIDE_LINE)
	local scroller = Widgets.button({
		parent = page,
		name = name,
		size = UDim2.fromOffset(width, viewH),
		position = UDim2.fromOffset(48, 0),
		color = Widgets.Colors.Card,
		sound = "",
	})
	scroller.BackgroundTransparency = 0.4
	scroller.ClipsDescendants = true
	-- ↑ / ↓ font défiler la liste (onListInput) : PanelController ne joue pas le bout de liste pour elle
	scroller:SetAttribute("SelfScroll", true)
	local holder = Widgets.group(scroller, "Holder", UDim2.fromOffset(width, viewH), UDim2.new())
	local lines: { TextLabel } = {}
	for i = 1, count do
		lines[i] = Widgets.label({
			parent = holder,
			name = "Line" .. i,
			size = UDim2.fromOffset(width - 64, 44),
			position = UDim2.fromOffset(0, 0),
			text = "",
			textSize = 32,
			xAlign = Enum.TextXAlignment.Left,
			zIndex = scroller.ZIndex + 1,
		})
		lines[i].Visible = false
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 24)
	-- ligne de 44 px dans un pas de 48 : 2 px au-dessus et au-dessous de chaque ligne (Records : la 1re
	-- ligne descend sous le cadre de focus dessiné dans la liste)
	pad.PaddingTop = UDim.new(0, top or (GUIDE_LINE - 44) / 2)
	pad.Parent = holder
	local list: ReadList = {
		tab = tab,
		scroller = scroller,
		holder = holder,
		lines = lines,
		scroll = 0,
		viewH = viewH,
		totalH = 0,
	}
	UserInputService.InputBegan:Connect(function(input: InputObject)
		onListInput(list, input)
	end)
	return list
end

-- Barre d'onglets : celle de la v1.3, ou celle de la v2.0 (Records en dernier)
local function buildBar(container: Frame, ids: { string })
	local specs = {}
	for _, id in ids do
		table.insert(specs, { id = id, key = "panel.dex.tab." .. id })
	end
	tabBar = Widgets.tabBar(container, specs, function(id: string)
		Squishydex.setTab(id)
	end)
	barTabs = ids
end

-- Colonne de la maîtrise sur la fiche, à droite des mutations (alignée sur leurs 3 rangées)
local MASTERY_KEYS: { { key: string, vars: { [string]: any }? } } = {
	{ key = "common.stars", vars = { n = 5 } },
	{ key = "panel.dex.goldenPage" },
	{ key = "panel.dex.trophy.crystal" },
}
local function buildMastery(f: Frame)
	local mw, mh = 200, 112
	local x = 48 + 360 + 32 + 3 * (mw + Layout.Spacing.Min) + Layout.Spacing.Min
	local w = f.Size.X.Offset - 48 - x
	local holder = Widgets.group(
		f,
		"Mastery",
		UDim2.fromOffset(w, 64 + 3 * (mh + Layout.Spacing.Min)),
		UDim2.fromOffset(x, 0)
	)
	local title = Widgets.label({
		parent = holder,
		name = "Title",
		size = UDim2.fromOffset(w, 52),
		position = UDim2.fromOffset(0, 4),
		text = "",
		textSize = 28,
		color = Widgets.Colors.Gold,
		xAlign = Enum.TextXAlignment.Left,
	})
	local boxes: { MasteryBox } = {}
	for i, spec in MASTERY_KEYS do
		local box = Widgets.frame({
			parent = holder,
			name = "Box" .. i,
			size = UDim2.fromOffset(w, mh),
			position = UDim2.fromOffset(0, 64 + (i - 1) * (mh + Layout.Spacing.Min)),
			color = Widgets.Colors.Card,
		})
		local check = Icons.canvas(box, 40, { "check" }, "Check")
		check.AnchorPoint = Vector2.new(0, 0.5)
		check.Position = UDim2.new(0, 14, 0.5, 0)
		check.ZIndex = box.ZIndex + 1
		local label = Widgets.label({
			parent = box,
			name = "Label",
			size = UDim2.new(1, -(14 + 40 + 12 + 12), 1, -16),
			position = UDim2.fromOffset(14 + 40 + 12, 8),
			key = spec.key,
			vars = spec.vars,
			textSize = 32,
			color = Widgets.Colors.LockedText,
			xAlign = Enum.TextXAlignment.Left,
			zIndex = box.ZIndex + 1,
		})
		boxes[i] = { frame = box, label = label, check = check }
	end
	holder.Visible = false
	mastery = { holder = holder, title = title, boxes = boxes }
end

local v2Watching = false
-- Parties de la v2.0 construites au premier besoin, À L'OUVERTURE (jamais écran ouvert, D24) : barre
-- de la v2.0 et page Records [RecordR], colonne de la maîtrise de la fiche [Mastery] ; interrupteurs
-- coupés : rien n'est construit
local function prepareOpen()
	local container = buildContainer
	if container == nil then
		return
	end
	local wantRecords, wantMastery = recordsOn(), masteryOn()
	if wantRecords then
		if barTabs ~= V2_TABS then
			local old = tabBar
			if old then
				old.frame:Destroy()
			end
			buildBar(container, V2_TABS)
		end
		if records == nil then
			local page = Widgets.group(
				container,
				"Page_records",
				UDim2.fromOffset(container.Size.X.Offset, container.Size.Y.Offset - buildTop),
				UDim2.fromOffset(0, buildTop)
			)
			page.Visible = false
			pages.records = page
			records = buildReadList(page, "Records", RECORD_LINES, "records", 18)
		end
	end
	local f = sheet
	if wantMastery and mastery == nil and f then
		buildMastery(f)
	end
	if (wantRecords or wantMastery) and not v2Watching then
		v2Watching = true
		Widgets.watch(META_KEYS, function()
			if isOpen then
				refresh()
			end
		end)
	end
end

-- Onglets montrés, dans l'ordre (Records seulement avec sa page et son interrupteur)
local function shownTabs(): { string }
	local out = {}
	for _, id in barTabs do
		if id ~= "records" or (records ~= nil and recordsOn()) then
			table.insert(out, id)
		end
	end
	return out
end

-- Construit le contenu une seule fois dans le cadre du panneau
function Squishydex.build(container: Frame)
	buildContainer = container
	buildTop = Layout.Panel.tabHeight + 24
	buildBar(container, TABS)
	local top = buildTop
	for _, id in TABS do
		local page = Widgets.group(
			container,
			"Page_" .. id,
			UDim2.fromOffset(container.Size.X.Offset, container.Size.Y.Offset - top),
			UDim2.fromOffset(0, top)
		)
		page.Visible = false
		pages[id] = page
	end
	families = buildFamilies()
	buildSpecies(pages.species)
	buildSheet(container, top)
	buildFamiliesPage(pages.families)
	guide = buildReadList(pages.guide, "Guide", 48, "guide")
	Widgets.watch({ "dex", "trophies", "R", "vat" }, function()
		if isOpen then
			refresh()
		end
	end)
	-- interrupteurs ou profil v2 changés écran ouvert : les onglets suivent (rien n'est construit)
	MetaFlags.Changed:Connect(function()
		if isOpen then
			if not table.find(shownTabs(), current) then
				current = "species"
			end
			showPage(current)
			refresh()
		end
	end)
end

-- Affiche le panneau : l'onglet demandé, sinon les Espèces (GDD §10.6 « 1re espèce » ; B2-63)
function Squishydex.open(tab: string?)
	isOpen = true
	Widgets.seen("dex")
	-- parties de la v2.0 manquantes construites ICI, avant l'affichage
	prepareOpen()
	if type(tab) == "string" and table.find(shownTabs(), tab) then
		current = tab
	else
		current = "species"
	end
	showPage(current)
	refresh()
end

-- Cache le panneau
function Squishydex.close()
	isOpen = false
	if sheet then
		sheet.Visible = false
	end
	sheetFrom = nil
end

-- Onglets, dans l'ordre (L1 / R1) : Espèces, Familles, Guide (et Records en v2.0)
function Squishydex.tabs(): { string }
	return shownTabs()
end

-- Change d'onglet
function Squishydex.setTab(tab: string)
	if type(tab) ~= "string" or not table.find(shownTabs(), tab) then
		return
	end
	current = tab
	showPage(tab)
	refresh()
end

function Squishydex.currentTab(): string
	return current
end

-- Sélection par défaut : la 1re espèce ; fiche : la 1re mutation ; Guide et Records : la liste
function Squishydex.defaultSelection(): GuiObject?
	if sheet and sheet.Visible then
		return sheetCells[1]
	end
	if current == "species" and speciesRows then
		return speciesRows.firstSelectable()
	elseif current == "families" and familyRows then
		return familyRows.firstSelectable()
	elseif current == "guide" and guide then
		return guide.scroller
	elseif current == "records" and records then
		return records.scroller
	end
	return if tabBar then tabBar.buttons[current] else nil
end

-- ○ : ferme la fiche (vrai, retour à la case de l'espèce), sinon retour au menu
function Squishydex.onBack(): boolean
	if sheet and sheet.Visible then
		closeSheet()
		return true
	end
	return false
end

-- Entrée du menu visible pour ce joueur
function Squishydex.visible(): boolean
	return true
end

-- Navigateur fourni par PanelController AVANT build
function Squishydex.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function Squishydex.refresh()
	refresh()
end

-- Stick droit : un écran
function Squishydex.scroll(dir: number)
	if current == "species" and speciesRows then
		speciesRows.page(dir)
	elseif current == "families" and familyRows then
		familyRows.page(dir)
	else
		local list = if current == "guide" then guide elseif current == "records" then records else nil
		if list then
			list.scroll += dir * list.viewH * GUIDE_STEP
			applyListScroll(list, true)
		end
	end
end

-- Fiche ouverte (specs) : espèce, mutations trouvées
function Squishydex._sheet(): { open: boolean, species: number }
	local _ = nav
	return { open = sheet ~= nil and sheet.Visible, species = sheetSpecies }
end

return Squishydex
