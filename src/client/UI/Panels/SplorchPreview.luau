--!strict
-- SplorchPreview (paquet client-panels) : aperçu du Grand Splorch (GDD §4.15, §10.3 ; docs/04 §13.6,
-- contrat v1.2), fait pour des enfants qui lisent peu :
--   1. 3 grandes tuiles « Tu gagnes » : « Croissance ×2 pour toujours », le déblocage de ce niveau
--      (Balance.Splorch.Unlocks ; sinon « Cuve meilleure »), « +5 Fame » ;
--   2. animation avant / après : le squishy redevient petit puis regrandit (fixe en Mouvement réduit) ;
--   3. pièces perdues en rouge (Pot compris) et « Dépenser d'abord » → Ranch › Dalles, avec d'abord
--      les dalles gardées (onglet « padsKept ») ;
--   4. choix du squishy qui s'envole (défaut : le plus gros qui n'est pas Meilleur Ami) ;
--   5. bouton à maintenir 1,5 s (✕) et case « Filmer » (cachée si l'attribut local ClipsUnavailable).
-- « Détails » ouvre les deux colonnes (Tu gardes / Repart de zéro) et le prochain objectif. Hors du
-- ranch : « Rentre dans ton ranch » ; un squishy en fuite : feedback.waitEscape ; dans les deux cas
-- le maintien est refusé (le serveur revérifie tout une seule fois à l'entrée dans la file). Plus de
-- 2e confirmation (contrat v1.2 : recentBuy ignoré). Maintien fini : GrandSplorch(film, flyer), puis
-- l'aperçu se ferme (le HUD montre la place dans la file). Même calcul que le serveur :
-- Logic/Formulas.splorchPreview sur le profil répliqué.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Balance = require(Shared.Config.Balance)
local Layout = require(Shared.Config.Layout)
local Formulas = require(Shared.Logic.Formulas)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent.Parent
local Juice = require(Client.UI.Juice)
local Prefs = require(Client.Util.Prefs)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Widgets = require(script.Parent.Widgets)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> (), closeAll: (() -> ())? }

local SplorchPreview = {}

local PROFILE_KEYS = { "R", "growth", "squishies", "coins", "pot" }
local ANIM_PERIOD = 2.4 -- s : rétrécit (0,6 s), regrandit (0,4 s), attend

local nav: Nav? = nil
local isOpen = false
local detailsOpen = false
local preview: { [string]: any } = {}
local flyers: { string } = {}
local flyerIndex = 1
local filmOn = true
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
local anim: RBXScriptConnection? = nil
local animStart = 0
local lastReason = "" -- raison du refus affichée (le message suit la fuite, le retour au ranch)

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

local function refresh()
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
	local keep = flyers[flyerIndex]
	flyers = collectFlyers(if type(preview.defaultFlyer) == "string" then preview.defaultFlyer else nil)
	flyerIndex = math.max(1, table.find(flyers, keep or "") or 1)
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

local function stepAnimation()
	local b = blob
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
		local n = nav
		if n then
			if n.closeAll then
				n.closeAll()
			else
				n.back()
			end
		end
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

-- Construit le contenu une seule fois dans le cadre du panneau
function SplorchPreview.build(container: Frame)
	local width = container.Size.X.Offset
	local height = container.Size.Y.Offset
	local m = Widgets.group(container, "Main", UDim2.fromOffset(width, height), UDim2.new())
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
	prevButton = Widgets.button({
		parent = m,
		name = "PrevFlyer",
		size = UDim2.fromOffset(100, Layout.Button.MinHeight),
		position = UDim2.fromOffset(col, 284),
		text = "◀",
		textSize = 40,
		onActivate = function()
			if #flyers > 1 then
				flyerIndex = ((flyerIndex - 2) % #flyers) + 1
				refresh()
			end
		end,
	})
	labels.flyerName = Widgets.label({
		parent = m,
		name = "FlyerName",
		size = UDim2.fromOffset(340, Layout.Button.MinHeight),
		position = UDim2.fromOffset(col + 116, 284),
		text = "",
		textSize = 40,
	})
	nextButton = Widgets.button({
		parent = m,
		name = "NextFlyer",
		size = UDim2.fromOffset(100, Layout.Button.MinHeight),
		position = UDim2.fromOffset(col + 472, 284),
		text = "▶",
		textSize = 40,
		onActivate = function()
			if #flyers > 1 then
				flyerIndex = (flyerIndex % #flyers) + 1
				refresh()
			end
		end,
	})
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
	local d = Widgets.group(container, "DetailsPage", UDim2.fromOffset(width, height), UDim2.new())
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

-- Affiche le panneau
function SplorchPreview.open(_tab: string?)
	isOpen = true
	flyerIndex = 1
	flyers = {}
	filmOn = Prefs.get("clips") ~= false
	if filmToggle then
		filmToggle.set(filmOn)
	end
	setDetails(false)
	refresh()
	animStart = Clock.now()
	if anim == nil then
		anim = RunService.Heartbeat:Connect(function()
			stepAnimation()
			-- fuite qui finit, joueur qui rentre au ranch : l'état du bouton suit (une fois par image,
			-- seulement panneau ouvert)
			local h = hold
			if h and isOpen and not h.holding() and blocker() ~= lastReason then
				refresh()
			end
		end)
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
	detailsOpen = false
end

-- Onglets : aucun
function SplorchPreview.tabs(): { string }
	return {}
end

function SplorchPreview.setTab(_tab: string) end

function SplorchPreview.currentTab(): string
	return ""
end

-- Sélection par défaut : le bouton « Maintenir » (glyphe ✕)
function SplorchPreview.defaultSelection(): GuiObject?
	if detailsOpen then
		return detailsOk
	end
	return if hold then hold.button else nil
end

-- ○ : ferme les Détails (vrai), sinon retour au menu (faux)
function SplorchPreview.onBack(): boolean
	if detailsOpen then
		setDetails(false)
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
function SplorchPreview._state(): { flyer: string?, film: boolean, blocker: string, details: boolean }
	return { flyer = flyers[flyerIndex], film = filmOn, blocker = blocker(), details = detailsOpen }
end

return SplorchPreview
