--!strict
-- ReturnScreen (paquet client-panels) : écran de retour (GDD §7.2, §4.19 ; docs/04 §13.6) sur
-- Celebrate "return" (EconomyService, absence d'au moins 10 min) : « Pendant ton absence (5 h 12) :
-- Mochi Mew a grossi de +X », le squishy qui gonfle (0,8 s, Quint Out), « +Y pièces dans ton Pot »,
-- « Grand Splorch prêt ! » ou « Presque prêt pour le Grand Splorch ! » ; bouton « Super ! »
-- (360 × 112 px TV, texte 40, glyphe ✕) sélectionné d'office ; ✕ ou ○ ferment. Fenêtre bloquante
-- de FocusGuard (« return ») : les touches du jeu restent déliées tant qu'elle est ouverte. Aucune
-- offre, aucune publicité. Charge utile revalidée (nombres finis, bornes) : une donnée abîmée
-- donne un écran sobre, jamais une erreur.
-- v2.0 (lot B3, étape 5, D21 ; GDD v2.0 §4.27 « Des textes vrais ») : pendant une remontée vers le
-- record (UpgradeSnapshot.regain(), interrupteur PetitSplorch ouvert), le prestige de la boucle est un
-- Petit Splorch : « Petit Splorch prêt ! » / « Presque prêt pour le Petit Splorch ! » remplacent les
-- textes du Grand Splorch ; la ligne suit l'instantané et les interrupteurs tant que l'écran est ouvert.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Layout = require(Shared.Config.Layout)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local Root = require(Client.UI.Root)
local Juice = require(Client.UI.Juice)
local FocusGuard = require(Client.UI.FocusGuard)
local Prefs = require(Client.Util.Prefs)
local AudioController = require(Client.Controllers.AudioController)
local Widgets = require(Client.UI.Panels.Widgets)
local Format = require(Client.UI.Format)
local MetaFlags = require(Client.UI.MetaFlags)
local UpgradeSnapshot = require(Client.UI.UpgradeSnapshot)

local ReturnScreen = {}

local WINDOW = "return"
local DISPLAY_ORDER = 45
local CARD = { w = 960, h = 700 }
local BUTTON = Layout.Cards.ReturnButton

local started = false
local gui: ScreenGui? = nil
local card: Frame? = nil
local okButton: TextButton? = nil
local blob: Frame? = nil
local labels: { [string]: TextLabel } = {}
local opened = false
-- ligne du prestige de la boucle reçue avec l'écran : "ready" | "nearly" | "" (aucune)
local splorchState = ""

local function num(v: any, maxValue: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.clamp(v, 0, maxValue)
end

-- Durée d'absence lisible (« 5 h 12 », « 12 min »)
local function awayText(seconds: number): string
	local s = math.floor(seconds)
	local h = s // 3600
	local m = (s % 3600) // 60
	if h > 0 then
		return Format.hoursMinutes(s, Prefs.language())
	end
	return Prefs.t("common.minutes", { n = math.max(1, m) })
end

local function build()
	if card ~= nil then
		return
	end
	local safeFrame = Root.safe("Return", DISPLAY_ORDER)
	local screen = safeFrame.Parent :: ScreenGui
	gui = screen
	screen.Enabled = false
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.BackgroundColor3 = Color3.fromRGB(10, 8, 24)
	veil.BackgroundTransparency = 0.35
	veil.BorderSizePixel = 0
	Root.coverScreen(veil)
	veil.Active = true
	veil.ZIndex = 0
	veil:SetAttribute("Decorative", true)
	veil.Parent = screen
	safeFrame.ZIndex = 1
	local f = Widgets.frame({
		parent = safeFrame,
		name = "Card",
		size = UDim2.fromOffset(CARD.w, CARD.h),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Widgets.Colors.Panel,
		corner = Widgets.CORNER_LARGE,
		gradient = true,
		zIndex = 2,
	})
	card = f
	labels.title = Widgets.label({
		parent = f,
		name = "Title",
		size = UDim2.new(1, -64, 0, 64),
		position = UDim2.new(0.5, 0, 0, 24),
		anchor = Vector2.new(0.5, 0),
		key = "return.title",
		textSize = Layout.Text.Title,
		zIndex = 3,
	})
	labels.away = Widgets.label({
		parent = f,
		name = "Away",
		size = UDim2.new(1, -64, 0, 48),
		position = UDim2.new(0.5, 0, 0, 100),
		anchor = Vector2.new(0.5, 0),
		textSize = Layout.Text.Body,
		color = Widgets.Colors.TextDim,
		zIndex = 3,
	})
	local stage = Widgets.group(f, "Stage", UDim2.fromOffset(220, 190), UDim2.new(0.5, 0, 0, 160))
	stage.AnchorPoint = Vector2.new(0.5, 0)
	local b = Widgets.blob(stage, "Squishy")
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.fromScale(0.5, 1)
	b.Size = UDim2.fromOffset(200, 170)
	blob = b
	labels.grew = Widgets.label({
		parent = f,
		name = "Grew",
		size = UDim2.new(1, -64, 0, 56),
		position = UDim2.new(0.5, 0, 0, 366),
		anchor = Vector2.new(0.5, 0),
		textSize = 40,
		color = Widgets.Colors.Success,
		zIndex = 3,
	})
	labels.pot = Widgets.label({
		parent = f,
		name = "Pot",
		size = UDim2.new(1, -64, 0, 48),
		position = UDim2.new(0.5, 0, 0, 430),
		anchor = Vector2.new(0.5, 0),
		textSize = Layout.Text.Body,
		color = Widgets.Colors.Gold,
		zIndex = 3,
	})
	labels.splorch = Widgets.label({
		parent = f,
		name = "Splorch",
		size = UDim2.new(1, -64, 0, 48),
		position = UDim2.new(0.5, 0, 0, 486),
		anchor = Vector2.new(0.5, 0),
		textSize = Layout.Text.Body,
		color = Widgets.Colors.Pink,
		zIndex = 3,
	})
	local ok = Widgets.button({
		parent = f,
		name = "Super",
		size = UDim2.fromOffset(BUTTON.w, BUTTON.h),
		position = UDim2.new(0.5, 0, 1, -32),
		anchor = Vector2.new(0.5, 1),
		color = Widgets.Colors.Pink,
		sound = "",
		onActivate = function()
			ReturnScreen._close()
		end,
	})
	local glyph = Layout.Glyph.Min
	local okGlyph = Widgets.glyph(
		ok,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.Return,
		glyph,
		UDim2.new(0, 20, 0.5, 0),
		Vector2.new(0, 0.5)
	)
	local okLabel = Widgets.label({
		parent = ok,
		name = "Label",
		size = UDim2.new(1, -(glyph + 56), 1, -16),
		position = UDim2.new(0, glyph + 36, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		key = "return.ok",
		textSize = BUTTON.text,
		zIndex = ok.ZIndex + 1,
	})
	-- « Enter » au clavier : le texte se pousse à droite de la pastille élargie
	Widgets.followGlyph(okLabel, okGlyph.frame, 20, 16, 20)
	okButton = ok
end

-- Ligne du prestige de la boucle (« prêt » / « presque prêt ») : Petit Splorch pendant une remontée
-- (v2.0, D21), Grand Splorch sinon (v1.3)
local function refreshSplorch()
	local label = labels.splorch
	if label == nil then
		return
	end
	if splorchState == "" then
		label.Visible = false
		return
	end
	local okRegain, regain = pcall(UpgradeSnapshot.regain)
	local petit = okRegain and regain == true and MetaFlags.on("PetitSplorch")
	local key = if splorchState == "ready"
		then (if petit then "return.petit" else "return.splorch")
		else (if petit then "return.petitNearly" else "return.nearly")
	Widgets.setText(label, key)
	label.Visible = true
end

local function onWindowClosed(name: string)
	if name ~= WINDOW then
		return
	end
	opened = false
	local screen = gui
	if screen then
		screen.Enabled = false
	end
end

-- Création des remotes et des états ; aucun yield long
function ReturnScreen.Init() end

-- Connexions et boucles
function ReturnScreen.Start()
	if started then
		return
	end
	started = true
	FocusGuard.WindowClosed:Connect(onWindowClosed)
	-- v2.0 (D21) : instantané ou interrupteurs arrivés après l'écran : la ligne suit (écran ouvert)
	local function follow()
		if opened then
			refreshSplorch()
		end
	end
	UpgradeSnapshot.Changed:Connect(follow)
	MetaFlags.Changed:Connect(follow)
	pcall(function()
		Net.event("Celebrate").OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" and payload.kind == "return" and type(payload.data) == "table" then
				ReturnScreen.show(payload.data)
			end
		end)
	end)
end

-- Affiche l'écran
function ReturnScreen.show(data: Types.ReturnScreenData)
	local d: any = if type(data) == "table" then data else {}
	build()
	local seconds = num(d.seconds, 7 * 24 * 3600)
	local grew = num(d.grew, 1e300)
	local pot = num(d.pot, 1e300)
	local species = if type(d.species) == "number" then d.species else 0
	Widgets.setText(labels.away, "return.away", { time = awayText(seconds) })
	Widgets.setText(
		labels.grew,
		"return.grew",
		{ name = Widgets.speciesName(species), size = Widgets.num(grew) }
	)
	labels.grew.Visible = grew > 0
	Widgets.setText(labels.pot, "return.pot", { coins = Widgets.num(pot) })
	labels.pot.Visible = pot > 0
	splorchState = if d.splorchReady == true then "ready" elseif d.nearlyReady == true then "nearly" else ""
	refreshSplorch()
	local b = blob :: Frame
	Widgets.paintBlob(b, species, species > 0)
	local screen = gui :: ScreenGui
	screen.Enabled = true
	-- le squishy qui gonfle (0,8 s, Quint Out ; fondu seul en Mouvement réduit)
	local scale = Juice.scaleOf(b)
	if Juice.reducedMotion() then
		scale.Scale = 1
	else
		scale.Scale = 0.55
		Juice.tween(scale, 0.8, { Scale = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Juice.popIn(card :: Frame)
	end
	if not opened then
		opened = true
		AudioController.play("Whoosh")
		FocusGuard.open({
			name = WINDOW,
			root = card :: Frame,
			blocking = true,
			default = function(): GuiObject?
				return okButton
			end,
			onBack = function(): boolean
				return false -- ○ ferme l'écran
			end,
			opener = nil,
		})
	end
end

-- Ferme l'écran (✕ sur « Super ! » ; ignoré moins de 0,35 s après l'ouverture : un ✕ martelé pendant
-- le chargement ne le saute pas)
function ReturnScreen._close()
	if opened then
		FocusGuard.close(WINDOW)
	end
end

-- Écran ouvert
function ReturnScreen.isOpen(): boolean
	return opened
end

return ReturnScreen
