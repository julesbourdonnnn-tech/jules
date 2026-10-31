--!strict
-- ScreenFX — paquet « client-hud » (docs/04-architecture.md §13.9).
-- Juice d'ÉCRAN et propriétaire côté client des remotes Feedback et Celebrate (ré-exposés en
-- signaux pour les panneaux et l'accueil).
-- Responsabilités :
--   * Feedback → Toast (UI/Toast, ton → couleur) + son Error pour "error" ; certains retours sont
--     des tampons (« PLEINE », « Récupère-les ! », « Récupéré ! ») ou des « +N » flottants (coupe,
--     Gloomwisp, acclamation) ; FeedbackReceived permet aux panneaux de secouer leur bouton
--   * Celebrate → réactions d'écran : "supernova" (titre qui s'écrit en 0,6 s), "atlasNew" /
--     "speciesComplete" (carte qui glisse de la droite, reflet), "atlasMilestone" (confettis),
--     "questDone" / "questClaimed" / "dailyClaimed" (récompense qui vole vers son compteur),
--     "starforge", "purchase" (pluie de 30 pièces, « Merci ! »), "cometBanked", "release",
--     "unlock", "upgrade" (+ VFXController.playUpgrade), "offline" (ReturnScreen ouvert par les
--     abonnés de Celebrated)
--   * tampons centraux (police LuckiestGuy, UIStroke 3 px) : « PARADE ×2,36 ! » (échelle 2 → 1,
--     rotation −8° → 0 en 0,25 s Back Out, tenu 0,8 s), « SNIP ! » (Elastic Out), « COMÈTE VOLÉE ! »,
--     « Conga ×N ! » quand la file locale se remplit ; parade locale : 8-16 pièces volent de la porte
--     au compteur de Glow (HUD.anchor("glow")) en 0,5 s, décalées de 0,03 s (Quad In) ; coupe subie :
--     vignette rose 0,4 s + secousse 0,25 s
--   * floaters d'écran (« +35 ✦ »), confettis ; Mouvement réduit : fondus seulement (ni pièces
--     volantes, ni confettis, ni rotation, ni secousse)
-- Une seule connexion RenderStepped (pièces, confettis, floaters, tampons, vignette, cartes), temps
-- d'animation = somme des dt des images (mesure purement graphique).
-- GDD : §9.1 (stamp, flyCoins), §9.2, §9.4, §7.2.
-- Dépendances : StateController, AudioController, Util/Prefs, UI/Root, UI/Theme, UI/Create, UI/Juice,
-- UI/Toast, WorldStateController, VFXController, Shared/Net, Shared/Util/Signal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Nebbies = require(Shared.Config.Nebbies)
local Balance = require(Shared.Config.Balance)
local Formulas = require(Shared.Logic.Formulas)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local Toast = require(Client.UI.Toast)
local WorldStateController = require(Client.Controllers.WorldStateController)
local VFXController = require(Client.Controllers.VFXController)
local Text = require(Client.UI.Hud.Text)
local Widgets = require(Client.UI.Hud.Widgets)

local ScreenFX = {}

-- Chaque Feedback reçu (après affichage du toast)
ScreenFX.FeedbackReceived = Signal.new() :: Signal.Signal<Types.FeedbackPayload>
-- Chaque Celebrate reçu (les panneaux y branchent leurs animations internes)
ScreenFX.Celebrated = Signal.new() :: Signal.Signal<Types.CelebratePayload>

export type StampStyle = "parade" | "snip" | "small" | "comet"

-- Constantes (GDD §9.2, §9.4) ------------------------------------------------------------------

local DISPLAY_ORDER = 45
local COIN_SIZE = 26 -- px de référence
local COIN_TIME = 0.5
local COIN_STAGGER = 0.03
local COIN_MAX = 40
local COIN_SOUND_INTERVAL = 1 / 8 -- son Coin au plus 8 / s
local PARADE_COINS_MIN, PARADE_COINS_MAX = 8, 16
local RAIN_COINS, RAIN_TIME, RAIN_FLIGHT = 30, 1, 0.7
local FLOATER_POOL = 12
local FLOATER_TIME = 0.7
local FLOATER_RISE = 60
local CONFETTI_MAX = 80
local CONFETTI_LIFE = 1.6
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 110, 150),
	Color3.fromRGB(120, 220, 255),
	Color3.fromRGB(255, 230, 110),
	Color3.fromRGB(150, 255, 170),
	Color3.fromRGB(200, 150, 255),
}
local VIGNETTE_ALPHA = 0.8
local VIGNETTE_DEPTH = 0.22 -- fraction de l'écran couverte par chaque bord
local SNIP_PINK = Color3.fromRGB(255, 110, 180)
local SNIP_SHAKE, SNIP_SHAKE_TIME = 0.35, 0.25
local SNIP_VIGNETTE_TIME = 0.4
local GOLD = Color3.fromRGB(255, 208, 72)
local CARD_TIME_IN, CARD_HOLD, CARD_TIME_OUT = 0.3, 2.4, 0.25
local CARD_MAX_VISIBLE = 3
local CARD_QUEUE_MAX = 8
local TITLE_TYPE_TIME, TITLE_HOLD, TITLE_FADE = 0.6, 1.6, 0.3
local STAMP_FADE = 0.2
local STAMP_FADE_IN = 0.12 -- Mouvement réduit : fondu d'entrée au lieu de l'échelle
local DUPLICATE_WINDOW = 0.5 -- même toast ignoré pendant 0,5 s
local TOAST_MEMORY = 32 -- textes récents mémorisés pour l'anti-doublon (au-delà : purge)
local MAX_LEVEL = 1e6 -- niveau d'amélioration ou nombre d'étoiles absurde : ignoré
local MAX_STARS = 5

type StampDef = { slot: string, enter: number, hold: number }
local STAMPS: { [string]: StampDef } = {
	parade = { slot = "big", enter = 0.25, hold = 0.8 },
	snip = { slot = "big", enter = 0.35, hold = 0.8 },
	comet = { slot = "big", enter = 0.25, hold = 1.2 },
	small = { slot = "small", enter = 0.2, hold = 1.5 },
}

-- Retours affichés en tampon plutôt qu'en toast
local FEEDBACK_STAMPS: { [string]: { key: string, hold: number, color: Color3 } } = {
	["feedback.lineFull"] = { key = "stamp.full", hold = 2, color = Theme.Colors.Danger },
	["feedback.snipped"] = { key = "stamp.getThemBack", hold = 1.5, color = SNIP_PINK },
	["feedback.recovered"] = { key = "stamp.recovered", hold = 1.2, color = Theme.Colors.Success },
}
-- Retours affichés en « +N » flottants
local FEEDBACK_FLOATERS: { [string]: boolean } = {
	["feedback.snipDealt"] = true,
	["feedback.wispPop"] = true,
	["feedback.cheerReward"] = true,
}

local TONES: { [string]: boolean } =
	{ info = true, success = true, warning = true, error = true, reward = true }

local CELEBRATE_KINDS: { [string]: boolean } = {
	supernova = true,
	atlasNew = true,
	atlasMilestone = true,
	speciesComplete = true,
	questDone = true,
	questClaimed = true,
	dailyClaimed = true,
	starforge = true,
	upgrade = true,
	offline = true,
	purchase = true,
	cometBanked = true,
	rookieEnd = true,
	release = true,
	unlock = true,
}

local UNLOCK_PREFIX: { [string]: string } = {
	styles = "style.",
	style = "style.",
	titles = "title.",
	title = "title.",
	themes = "theme.",
	theme = "theme.",
}

-- État ------------------------------------------------------------------------------------------

type Flight = {
	frame: Frame,
	t0: number,
	duration: number,
	p0: Vector2,
	p1: Vector2,
	p2: Vector2,
	target: GuiObject?,
	sound: boolean,
}

type Floater = { label: TextLabel, t0: number, origin: Vector2, busy: boolean }

type Confetto = {
	frame: Frame,
	t0: number,
	pos: Vector2,
	vel: Vector2,
	spin: number,
	busy: boolean,
}

-- La transparence d'un tampon est calculée à chaque image (fondu d'entrée en Mouvement réduit,
-- fondu de sortie) : aucun tween de transparence ne survit à un nouveau tampon sur la même place
type StampSlot = {
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	shownAt: number,
	fadeIn: number,
	hideAt: number,
	goneAt: number,
	active: boolean,
}

type Card = { frame: CanvasGroup, t0: number, outAt: number, goneAt: number, index: number }

local started = false
local fxTime = 0
local gui: ScreenGui? = nil
local layer: Frame? = nil -- plein écran, en pixels (pièces, floaters, confettis, vignette)
local center: Frame? = nil -- conteneur mis à l'échelle (tampons, titre, cartes)
local anchorResolver: ((Types.HudElement) -> GuiObject?)? = nil

local coinPool: { Frame } = {}
local flights: { Flight } = {}
local floaters: { Floater } = {}
local floaterCursor = 0
local confetti: { Confetto } = {}
local stamps: { [string]: StampSlot } = {}
local vignetteFrames: { Frame } = {}
local vignette = { t0 = -math.huge, duration = 0, color = SNIP_PINK }
local title: { label: TextLabel?, t0: number, graphemes: number, active: boolean } =
	{ label = nil, t0 = 0, graphemes = 0, active = false }
local cards: { Card } = {}
local cardQueue: { string } = {}
local lastCoinSound = -math.huge
local lastToast: { [string]: number } = {}
local rng = Random.new()
local lastLineCount = 0
local lastCarrier: { id: number, userId: number? } = { id = 0, userId = nil }

-- Outils ----------------------------------------------------------------------------------------

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function localUserId(): number
	local player = Players.LocalPlayer
	return if player then player.UserId else 0
end

local function reduced(): boolean
	return Prefs.reducedMotion()
end

local function scale(): number
	return Root.scale()
end

local function ensureGui(): (Frame, Frame)
	if layer and layer.Parent and center and center.Parent then
		return layer :: Frame, center :: Frame
	end
	local screen = Root.screen("ScreenFX", DISPLAY_ORDER)
	-- couche plein écran (coordonnées de la fenêtre) : insets ignorés
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	gui = screen
	local full = Create("Frame", {
		Name = "Layer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 1,
		Parent = screen,
	})
	layer = full
	center = screen:FindFirstChild("Safe") :: Frame
	return full, center :: Frame
end

local function viewportSize(): Vector2
	local l = layer
	if l and l.AbsoluteSize.X > 1 then
		return l.AbsoluteSize
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- Centre d'un élément d'interface dans les coordonnées de la couche plein écran
local function guiCenter(target: GuiObject): Vector2
	local l = layer
	local origin = if l then l.AbsolutePosition else Vector2.zero
	return target.AbsolutePosition + target.AbsoluteSize / 2 - origin
end

local function isShown(target: GuiObject?): boolean
	if target == nil or target.Parent == nil or not target.Visible then
		return false
	end
	local parent = target.Parent
	while parent and parent:IsA("GuiObject") do
		if not (parent :: GuiObject).Visible then
			return false
		end
		parent = parent.Parent
	end
	return true
end

-- Point du monde → coordonnées de la couche (nil derrière la caméra ou caméra indisponible)
local function worldToScreen(pos: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local ok, point = pcall(function()
		return (camera :: any):WorldToViewportPoint(pos)
	end)
	if not ok or typeof(point) ~= "Vector3" or point.Z <= 0 then
		return nil
	end
	return Vector2.new(point.X, point.Y)
end

local function anchor(element: Types.HudElement): GuiObject?
	local resolve = anchorResolver
	if resolve == nil then
		return nil
	end
	local ok, result = pcall(resolve, element)
	if ok and typeof(result) == "Instance" and (result :: Instance):IsA("GuiObject") then
		return result :: GuiObject
	end
	return nil
end

local function coinSound()
	if fxTime - lastCoinSound >= COIN_SOUND_INTERVAL then
		lastCoinSound = fxTime
		AudioController.play("Coin", 0.06)
	end
end

local function bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: number): Vector2
	local u = 1 - t
	return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
end

-- Pièces volantes -------------------------------------------------------------------------------

local function takeCoin(kind: string): Frame
	local full = ensureGui()
	local coin = table.remove(coinPool)
	if coin == nil then
		local made = Widgets.coin(
			"Coin",
			UDim2.fromOffset(COIN_SIZE, COIN_SIZE),
			UDim2.new(),
			full,
			Vector2.new(0.5, 0.5)
		)
		made.ZIndex = 20
		coin = made
	end
	local c = coin :: Frame
	local px = math.floor(COIN_SIZE * scale())
	c.Size = UDim2.fromOffset(px, px)
	-- étoile de Stardust : même forme, teinte violette
	c.BackgroundColor3 = if kind == "dust" then Theme.Colors.Premium else Theme.Colors.Gold
	local inner = c:FindFirstChild("Inner")
	if inner and inner:IsA("Frame") then
		inner.BackgroundColor3 = if kind == "dust"
			then Color3.fromRGB(230, 200, 255)
			else Color3.fromRGB(255, 186, 40)
	end
	c.Visible = true
	return c
end

local function releaseCoin(coin: Frame)
	coin.Visible = false
	table.insert(coinPool, coin)
end

-- Lance jusqu'à `count` pièces ; renvoie le nombre de pièces réellement lancées (réserve pleine : moins)
local function launch(
	from: Vector2,
	target: GuiObject,
	count: number,
	kind: string,
	duration: number,
	stagger: number
): number
	if reduced() then
		Juice.pulse(target, 1.15)
		coinSound()
		return 0
	end
	local to = guiCenter(target)
	local n = math.clamp(math.floor(count), 1, COIN_MAX)
	local s = scale()
	local launched = 0
	for i = 1, n do
		if #flights >= COIN_MAX then
			break
		end
		launched += 1
		local jitter = Vector2.new(rng:NextNumber(-18, 18), rng:NextNumber(-18, 18)) * s
		local p0 = from + jitter
		local mid = (p0 + to) / 2
		local lift = Vector2.new(rng:NextNumber(-90, 90), -rng:NextNumber(60, 140)) * s
		local coin = takeCoin(kind)
		coin.Position = UDim2.fromOffset(p0.X, p0.Y)
		table.insert(flights, {
			frame = coin,
			t0 = fxTime + (i - 1) * stagger,
			duration = duration,
			p0 = p0,
			p1 = mid + lift,
			p2 = to,
			target = target,
			sound = i == 1 or i % 3 == 0 or i == n,
		})
	end
	return launched
end

local function stepFlights()
	for i = #flights, 1, -1 do
		local f = flights[i]
		local a = (fxTime - f.t0) / f.duration
		if a < 0 then
			f.frame.Visible = false
		elseif a >= 1 then
			releaseCoin(f.frame)
			table.remove(flights, i)
			local target = f.target
			if target and target.Parent then
				if f.sound then
					Juice.pulse(target, 1.15)
					coinSound()
				end
			end
		else
			f.frame.Visible = true
			local eased = a * a -- Quad In
			local p = bezier(f.p0, f.p1, f.p2, eased)
			f.frame.Position = UDim2.fromOffset(p.X, p.Y)
		end
	end
end

-- Floaters --------------------------------------------------------------------------------------

local function takeFloater(): Floater
	local full = ensureGui()
	if #floaters < FLOATER_POOL then
		local label = Widgets.label({
			name = "Floater",
			size = UDim2.fromOffset(260, 44),
			anchor = Vector2.new(0.5, 0.5),
			maxSize = 34,
			zIndex = 22,
			strokeThickness = 2.5,
			parent = full,
		})
		label.Visible = false
		local f: Floater = { label = label, t0 = 0, origin = Vector2.zero, busy = false }
		table.insert(floaters, f)
		return f
	end
	floaterCursor = floaterCursor % FLOATER_POOL + 1
	return floaters[floaterCursor]
end

local function stepFloaters()
	for _, f in floaters do
		if f.busy then
			local a = (fxTime - f.t0) / FLOATER_TIME
			if a >= 1 then
				f.busy = false
				f.label.Visible = false
			else
				local rise = if reduced() then 0 else FLOATER_RISE * scale() * (1 - (1 - a) ^ 2)
				f.label.Position = UDim2.fromOffset(f.origin.X, f.origin.Y - rise)
				local fade = math.clamp((a - 0.6) / 0.4, 0, 1)
				f.label.TextTransparency = fade
				local stroke = f.label:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Transparency = fade
				end
			end
		end
	end
end

-- Confettis -------------------------------------------------------------------------------------

local function stepConfetti(dt: number)
	local size = viewportSize()
	for _, c in confetti do
		if c.busy then
			local age = fxTime - c.t0
			if age >= CONFETTI_LIFE or c.pos.Y > size.Y + 40 then
				c.busy = false
				c.frame.Visible = false
			else
				c.vel += Vector2.new(0, 420 * dt)
				c.pos += c.vel * dt
				c.frame.Position = UDim2.fromOffset(c.pos.X, c.pos.Y)
				c.frame.Rotation += c.spin * dt
				c.frame.BackgroundTransparency =
					math.clamp((age - CONFETTI_LIFE * 0.7) / (CONFETTI_LIFE * 0.3), 0, 1)
			end
		end
	end
end

-- Tampons ---------------------------------------------------------------------------------------

local function stampSlot(name: string): StampSlot
	local existing = stamps[name]
	if existing and existing.label.Parent then
		return existing
	end
	local _, c = ensureGui()
	local big = name == "big"
	local label = Widgets.label({
		name = if big then "Stamp" else "SmallStamp",
		size = if big then UDim2.fromOffset(760, 130) else UDim2.fromOffset(520, 64),
		position = if big then UDim2.fromScale(0.5, 0.36) else UDim2.fromScale(0.5, 0.6),
		anchor = Vector2.new(0.5, 0.5),
		font = Widgets.STAMP_FONT,
		maxSize = if big then 96 else 44,
		zIndex = if big then 30 else 28,
		strokeThickness = 3,
		parent = c,
	})
	label.Visible = false
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 3
	local s = Create("UIScale", { Name = "StampScale", Scale = 1, Parent = label })
	local slot: StampSlot = {
		label = label,
		stroke = stroke,
		scale = s,
		shownAt = 0,
		fadeIn = 0,
		hideAt = 0,
		goneAt = 0,
		active = false,
	}
	stamps[name] = slot
	return slot
end

local function setStampAlpha(slot: StampSlot, transparency: number)
	if slot.label.TextTransparency ~= transparency then
		slot.label.TextTransparency = transparency
	end
	if slot.stroke.Transparency ~= transparency then
		slot.stroke.Transparency = transparency
	end
end

local function showStamp(text: string, color: Color3, style: StampStyle, hold: number?)
	local def = STAMPS[style] or STAMPS.parade
	local slot = stampSlot(def.slot)
	local label = slot.label
	label.Text = text
	label.TextColor3 = color
	label.Visible = true
	label.Rotation = 0
	slot.active = true
	slot.shownAt = fxTime
	slot.hideAt = fxTime + def.enter + (hold or def.hold)
	slot.goneAt = slot.hideAt + STAMP_FADE
	if reduced() then
		-- fondu d'entrée de 0,12 s (piloté par stepStamps), sans mouvement
		slot.fadeIn = STAMP_FADE_IN
		setStampAlpha(slot, 1)
		Juice.tween(slot.scale, 0.01, { Scale = 1 })
		Juice.tween(label, 0.01, { Rotation = 0 })
		return
	end
	slot.fadeIn = 0
	setStampAlpha(slot, 0)
	if style == "parade" then
		-- échelle 2 → 1 et rotation −8° → 0 en 0,25 s (Back Out)
		slot.scale.Scale = 2
		label.Rotation = -8
		Juice.tween(slot.scale, def.enter, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		Juice.tween(label, def.enter, { Rotation = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	elseif style == "snip" then
		-- 0 → 1,4 → 1 en 0,35 s (Elastic Out)
		slot.scale.Scale = 0
		Juice.tween(slot.scale, def.enter, { Scale = 1 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
	elseif style == "comet" then
		slot.scale.Scale = 1.6
		Juice.tween(slot.scale, def.enter, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		slot.scale.Scale = 0.6
		Juice.tween(slot.scale, def.enter, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
end

local function stepStamps()
	for _, slot in stamps do
		if slot.active then
			if fxTime >= slot.goneAt then
				slot.active = false
				slot.label.Visible = false
				setStampAlpha(slot, 1)
			elseif fxTime >= slot.hideAt then
				setStampAlpha(slot, math.clamp((fxTime - slot.hideAt) / STAMP_FADE, 0, 1))
			elseif slot.fadeIn > 0 then
				setStampAlpha(slot, 1 - math.clamp((fxTime - slot.shownAt) / slot.fadeIn, 0, 1))
			else
				setStampAlpha(slot, 0)
			end
		end
	end
end

-- Titre de Supernova (s'écrit en 0,6 s : MaxVisibleGraphemes) ----------------------------------------

local function showTitle(text: string)
	local _, c = ensureGui()
	local label = title.label
	if label == nil or label.Parent == nil then
		local made = Widgets.label({
			name = "SupernovaTitle",
			size = UDim2.fromOffset(820, 140),
			position = UDim2.fromScale(0.5, 0.3),
			anchor = Vector2.new(0.5, 0.5),
			font = Widgets.STAMP_FONT,
			color = Color3.fromRGB(255, 245, 220),
			maxSize = 110,
			zIndex = 32,
			strokeThickness = 3,
			parent = c,
		})
		Create("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 205, 120)),
			Rotation = 90,
			Parent = made,
		})
		title.label = made
		label = made
	end
	local l = label :: TextLabel
	l.Text = text
	l.TextTransparency = 0
	l.Visible = true
	l.MaxVisibleGraphemes = 0
	title.graphemes = utf8.len(text) or #text
	title.t0 = fxTime
	title.active = true
end

local function stepTitle()
	if not title.active then
		return
	end
	local l = title.label
	if l == nil or l.Parent == nil then
		title.active = false
		return
	end
	local age = fxTime - title.t0
	if age < TITLE_TYPE_TIME then
		l.MaxVisibleGraphemes = math.floor(title.graphemes * age / TITLE_TYPE_TIME)
	elseif age < TITLE_TYPE_TIME + TITLE_HOLD then
		l.MaxVisibleGraphemes = -1
	elseif age < TITLE_TYPE_TIME + TITLE_HOLD + TITLE_FADE then
		l.TextTransparency = (age - TITLE_TYPE_TIME - TITLE_HOLD) / TITLE_FADE
	else
		l.Visible = false
		title.active = false
	end
end

-- Cartes « NOUVEAU ! » (droite de l'écran) -----------------------------------------------------------

local function cardY(index: number): UDim2
	return UDim2.new(1, -8, 0.42, (index - 1) * 74)
end

local function openCard(text: string)
	local _, c = ensureGui()
	local index = #cards + 1
	local frame = Create("CanvasGroup", {
		Name = "AtlasCard",
		AnchorPoint = Vector2.new(1, 0),
		Position = cardY(index) + UDim2.fromOffset(if reduced() then 0 else 360, 0),
		Size = UDim2.fromOffset(340, 64),
		BackgroundColor3 = Theme.Colors.Panel,
		GroupTransparency = if reduced() then 1 else 0,
		ZIndex = 26,
		Parent = c,
	}, {
		Widgets.corner(Theme.Corner),
		Widgets.stroke(Theme.Colors.Gold, 2.5),
		Widgets.label({
			name = "Text",
			text = text,
			size = UDim2.new(1, -24, 1, -12),
			position = UDim2.fromOffset(12, 6),
			maxSize = 26,
			color = Color3.fromRGB(255, 236, 170),
			zIndex = 27,
		}),
	})
	-- reflet : bande blanche (calque Widgets.shine sous le texte) qui traverse la carte ; un
	-- UIGradient posé sur le CanvasGroup lui-même rendrait la bande TRANSPARENTE (trou qui glisse)
	local gradient = Widgets.shine(frame)
	local card: Card = {
		frame = frame,
		t0 = fxTime,
		outAt = fxTime + CARD_TIME_IN + CARD_HOLD,
		goneAt = fxTime + CARD_TIME_IN + CARD_HOLD + CARD_TIME_OUT,
		index = index,
	}
	table.insert(cards, card)
	if reduced() then
		Juice.tween(frame, CARD_TIME_IN, { GroupTransparency = 0 })
	else
		Juice.tween(
			frame,
			CARD_TIME_IN,
			{ Position = cardY(index) },
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
		Juice.tween(
			gradient,
			0.6,
			{ Offset = Vector2.new(1, 0) },
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out,
			0.2
		)
	end
	AudioController.play("Pop", 0.05)
end

local function queueCard(text: string)
	if #cards < CARD_MAX_VISIBLE then
		openCard(text)
	elseif #cardQueue < CARD_QUEUE_MAX then
		table.insert(cardQueue, text)
	end
end

local function stepCards()
	local changed = false
	for i = #cards, 1, -1 do
		local card = cards[i]
		if fxTime >= card.goneAt or card.frame.Parent == nil then
			card.frame:Destroy()
			table.remove(cards, i)
			changed = true
		elseif fxTime >= card.outAt and card.frame.GroupTransparency == 0 then
			Juice.tween(card.frame, CARD_TIME_OUT, { GroupTransparency = 1 })
		end
	end
	if changed then
		for i, card in cards do
			if card.index ~= i then
				card.index = i
				Juice.tween(card.frame, 0.2, { Position = cardY(i) })
			end
		end
	end
	while #cards < CARD_MAX_VISIBLE and #cardQueue > 0 do
		openCard(table.remove(cardQueue, 1) :: string)
	end
end

-- Vignette --------------------------------------------------------------------------------------

local function ensureVignette()
	if #vignetteFrames > 0 and vignetteFrames[1].Parent then
		return
	end
	local full = ensureGui()
	table.clear(vignetteFrames)
	-- 4 bords : dégradé de transparence du bord (opaque) vers l'intérieur (transparent)
	local edges = {
		{ "Top", UDim2.fromScale(1, VIGNETTE_DEPTH), UDim2.fromScale(0, 0), 90 },
		{ "Bottom", UDim2.fromScale(1, VIGNETTE_DEPTH), UDim2.fromScale(0, 1 - VIGNETTE_DEPTH), -90 },
		{ "Left", UDim2.fromScale(VIGNETTE_DEPTH, 1), UDim2.fromScale(0, 0), 0 },
		{ "Right", UDim2.fromScale(VIGNETTE_DEPTH, 1), UDim2.fromScale(1 - VIGNETTE_DEPTH, 0), 180 },
	}
	for _, e in edges do
		local frame = Create("Frame", {
			Name = "Vignette" .. (e[1] :: string),
			Size = e[2] :: UDim2,
			Position = e[3] :: UDim2,
			BackgroundColor3 = SNIP_PINK,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 15,
			Visible = false,
			Parent = full,
		}, {
			Create("UIGradient", {
				Rotation = e[4] :: number,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		table.insert(vignetteFrames, frame)
	end
end

local function stepVignette()
	if #vignetteFrames == 0 then
		return
	end
	local age = fxTime - vignette.t0
	local visible = age >= 0 and age < vignette.duration
	for _, frame in vignetteFrames do
		frame.Visible = visible
		if visible then
			-- une seule pulsation (≤ 3 Hz, GDD §13.2)
			local alpha = math.sin(math.pi * age / vignette.duration)
			frame.BackgroundColor3 = vignette.color
			frame.BackgroundTransparency = 1 - VIGNETTE_ALPHA * alpha
		end
	end
end

-- Image -----------------------------------------------------------------------------------------

local function onFrame(dt: number)
	local step = if isFinite(dt) then math.clamp(dt, 0, 0.25) else 0
	fxTime += step
	stepFlights()
	stepFloaters()
	stepConfetti(step)
	stepStamps()
	stepTitle()
	stepCards()
	stepVignette()
end

-- API publique ----------------------------------------------------------------------------------

function ScreenFX.stamp(text: string, color: Color3, style: StampStyle?)
	if type(text) ~= "string" or typeof(color) ~= "Color3" then
		return
	end
	showStamp(text, color, style or "parade", nil)
end

-- Pièces (Frames dorées) sur courbe de Bézier d'un point écran vers un élément d'interface
function ScreenFX.flyCoins(fromScreen: Vector2, target: GuiObject, count: number)
	if typeof(fromScreen) ~= "Vector2" or not isFinite(count) or count < 1 then
		return
	end
	if typeof(target) ~= "Instance" or not target:IsA("GuiObject") or target.Parent == nil then
		return
	end
	launch(fromScreen, target, count, "coin", COIN_TIME, COIN_STAGGER)
end

function ScreenFX.floater(text: string, screenPos: Vector2, color: Color3)
	if type(text) ~= "string" or typeof(screenPos) ~= "Vector2" or typeof(color) ~= "Color3" then
		return
	end
	local f = takeFloater()
	f.busy = true
	f.t0 = fxTime
	f.origin = screenPos
	f.label.Text = text
	f.label.TextColor3 = color
	f.label.TextTransparency = 0
	f.label.Size = UDim2.fromOffset(260 * scale(), 44 * scale())
	f.label.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	f.label.Visible = true
end

-- Vignette sur les bords (4 Frames à UIGradient) qui pulse
function ScreenFX.vignette(color: Color3, duration: number)
	if typeof(color) ~= "Color3" or not isFinite(duration) or duration <= 0 then
		return
	end
	ensureVignette()
	vignette.t0 = fxTime
	vignette.duration = math.clamp(duration, 0.1, 3)
	vignette.color = color
	stepVignette()
end

function ScreenFX.confetti(count: number)
	if not isFinite(count) or count < 1 or reduced() then
		return
	end
	local full = ensureGui()
	local size = viewportSize()
	local n = math.clamp(math.floor(count), 1, CONFETTI_MAX)
	local s = scale()
	for i = 1, n do
		local piece: Confetto? = nil
		for _, c in confetti do
			if not c.busy then
				piece = c
				break
			end
		end
		if piece == nil then
			if #confetti >= CONFETTI_MAX then
				break
			end
			local frame = Create("Frame", {
				Name = "Confetto",
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Visible = false,
				ZIndex = 24,
				Parent = full,
			})
			local made: Confetto =
				{ frame = frame, t0 = 0, pos = Vector2.zero, vel = Vector2.zero, spin = 0, busy = false }
			table.insert(confetti, made)
			piece = made
		end
		local p = piece :: Confetto
		p.busy = true
		p.t0 = fxTime - rng:NextNumber(0, 0.25)
		p.pos = Vector2.new(rng:NextNumber(0, size.X), rng:NextNumber(-60, -10))
		p.vel = Vector2.new(rng:NextNumber(-120, 120), rng:NextNumber(120, 320)) * s
		p.spin = rng:NextNumber(-540, 540)
		p.frame.Size = UDim2.fromOffset(math.floor(8 * s) + 1, math.floor(14 * s) + 1)
		p.frame.BackgroundColor3 = CONFETTI_COLORS[(i - 1) % #CONFETTI_COLORS + 1]
		p.frame.BackgroundTransparency = 0
		p.frame.Rotation = rng:NextNumber(0, 360)
		p.frame.Position = UDim2.fromOffset(p.pos.X, p.pos.Y)
		p.frame.Visible = true
	end
end

-- Ajouts du paquet client-hud ---------------------------------------------------------------------

-- Crochet posé par le HUD (plus tardif dans l'ordre §13.1) : élément cible des récompenses volantes
function ScreenFX.setAnchorResolver(fn: ((Types.HudElement) -> GuiObject?)?)
	anchorResolver = fn
end

-- Retour local (même chemin qu'un Feedback serveur : toast/tampon + FeedbackReceived)
function ScreenFX.notify(key: string, vars: { [string]: any }?, tone: Types.FeedbackTone?)
	ScreenFX._onFeedback({ key = key, vars = vars or {}, tone = tone or "info" })
end

-- Centre de l'écran (coordonnées de la couche) : origine des récompenses sans position monde
function ScreenFX.screenCenter(): Vector2
	return viewportSize() / 2
end

-- Récompense qui vole vers son compteur (Glow, Stardust) avec un « +N »
local function reward(element: Types.HudElement, from: Vector2, amount: number, count: number)
	local target = anchor(element)
	local text = if element == "stardust"
		then Prefs.t("celebrate.release", { dust = Prefs.number(amount) })
		else Prefs.t("world.plus", { amount = Prefs.number(amount) })
	local color = if element == "stardust" then Color3.fromRGB(220, 180, 255) else GOLD
	ScreenFX.floater(text, from + Vector2.new(0, -40 * scale()), color)
	if target and isShown(target) then
		launch(from, target, count, if element == "stardust" then "dust" else "coin", COIN_TIME, COIN_STAGGER)
	end
end

-- Feedback --------------------------------------------------------------------------------------

-- Anti-doublon des toasts : chaque texte (souvent unique : « Il manque 1,2K Glow ») est mémorisé
-- avec son instant ; les entrées plus vieilles que la fenêtre sont purgées au-delà de TOAST_MEMORY
-- (la table ne grossit pas pendant une longue session)
local toastCount = 0
local function rememberToast(text: string)
	if lastToast[text] == nil then
		toastCount += 1
	end
	lastToast[text] = fxTime
	if toastCount > TOAST_MEMORY then
		for key, at in lastToast do
			if fxTime - at >= DUPLICATE_WINDOW or fxTime < at then
				lastToast[key] = nil
				toastCount -= 1
			end
		end
	end
end

local function onFeedback(payload: any)
	if type(payload) ~= "table" or not Text.isKey(payload.key) then
		return
	end
	local key = payload.key :: string
	local tone = if type(payload.tone) == "string" and TONES[payload.tone] then payload.tone else "info"
	local vars = Text.formatVars(payload.vars, Prefs.number)
	local clean: Types.FeedbackPayload = { key = key, vars = vars, tone = tone :: Types.FeedbackTone }
	local stampDef = FEEDBACK_STAMPS[key]
	if stampDef then
		showStamp(Prefs.t(stampDef.key, vars), stampDef.color, "small", stampDef.hold)
		if key == "feedback.lineFull" then
			AudioController.play("Error", 0.02)
		end
	elseif FEEDBACK_FLOATERS[key] then
		local c = ScreenFX.screenCenter()
		ScreenFX.floater(
			Prefs.t(key, vars),
			c + Vector2.new(0, -120 * scale()),
			Color3.fromRGB(220, 180, 255)
		)
	else
		local text = Prefs.t(key, vars)
		local last = lastToast[text]
		if last == nil or fxTime - last >= DUPLICATE_WINDOW or fxTime < last then
			rememberToast(text)
			Toast.show(text, tone)
		end
		if tone == "error" then
			AudioController.play("Error", 0.02)
		end
	end
	ScreenFX.FeedbackReceived:Fire(clean)
end
ScreenFX._onFeedback = onFeedback

-- Celebrate -------------------------------------------------------------------------------------

local function num(x: any): number?
	return if isFinite(x) then x :: number else nil
end

local function celebrateSupernova(data: { [string]: any })
	local level = num(data.level)
	if level == nil then
		return
	end
	showTitle(Prefs.t("celebrate.supernova", { level = Text.roman(level) }))
end

local function celebrateAtlas(data: { [string]: any })
	local entries = data.entries
	if type(entries) ~= "table" then
		return
	end
	local shown = 0
	for _, entry in entries do
		if shown >= CARD_QUEUE_MAX then
			break
		end
		if type(entry) == "table" then
			local s, f = num(entry.s), num(entry.f)
			local species = if s then Nebbies.Species[s] else nil
			local form = if f then Nebbies.Forms[f] else nil
			if species and form then
				shown += 1
				queueCard(Prefs.t("celebrate.atlasNew", {
					species = species.name,
					form = Prefs.t("form." .. form.key),
				}))
			end
		end
	end
end

local function onCelebrate(payload: any)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" or not CELEBRATE_KINDS[payload.kind] then
		return
	end
	local kind = payload.kind :: Types.CelebrateKind
	local data: { [string]: any } = if type(payload.data) == "table" then payload.data else {}
	local middle = ScreenFX.screenCenter()
	if kind == "supernova" then
		celebrateSupernova(data)
	elseif kind == "atlasNew" then
		celebrateAtlas(data)
	elseif kind == "speciesComplete" then
		local s, dust = num(data.s), num(data.dust)
		local species = if s then Nebbies.Species[s] else nil
		if species then
			queueCard(
				Prefs.t(
					"celebrate.speciesComplete",
					{ species = species.name, dust = Prefs.number(dust or 0) }
				)
			)
		end
	elseif kind == "atlasMilestone" then
		ScreenFX.confetti(60)
		AudioController.play("LevelUp")
	elseif kind == "questDone" then
		Toast.show(Prefs.t("celebrate.questDone"), "reward")
		AudioController.play("Reward")
	elseif kind == "questClaimed" or kind == "dailyClaimed" then
		local glow, dust = num(data.glow), num(data.stardust)
		if glow and glow > 0 then
			reward("glow", middle, glow, 8)
		end
		if dust and dust > 0 then
			reward("stardust", middle + Vector2.new(0, 50 * scale()), dust, 6)
		end
		local boost = num(data.boostSeconds)
		if boost and boost > 0 then
			Toast.show(Prefs.t("feedback.boostOn", { minutes = math.ceil(boost / 60) }), "reward")
		end
		if kind == "dailyClaimed" then
			AudioController.play("Reward")
		end
	elseif kind == "starforge" then
		local stars = num(data.stars)
		if stars and stars >= 1 and stars <= MAX_STARS then
			showStamp(Prefs.t("celebrate.starforge", { stars = math.floor(stars) }), GOLD, "small", 1.2)
		end
	elseif kind == "upgrade" then
		local level = num(data.level)
		-- piste connue (Balance.Upgrades) et niveau entier raisonnable, sinon rien n'est joué
		if
			type(data.track) == "string"
			and Balance.Upgrades[data.track] ~= nil
			and level
			and level >= 0
			and level <= MAX_LEVEL
		then
			local ok, err = pcall(VFXController.playUpgrade, data.track, level)
			if not ok then
				warn("[ScreenFX] playUpgrade :", err)
			end
			ScreenFX.floater(
				Prefs.t("celebrate.upgrade", { level = math.floor(level) }),
				Vector2.new(middle.X, viewportSize().Y * 0.72),
				Color3.fromRGB(150, 235, 255)
			)
		end
	elseif kind == "purchase" then
		showStamp(Prefs.t("stamp.thanks"), GOLD, "comet", nil)
		AudioController.play("Reward")
		local target = anchor("glow")
		if target and isShown(target) and not reduced() then
			local size = viewportSize()
			for i = 1, RAIN_COINS do
				-- pluie de 30 pièces sur 1 s, du haut de l'écran vers le compteur ; réserve pleine :
				-- on s'arrête (jamais retarder une pièce déjà en vol)
				local from = Vector2.new(size.X * (i - 0.5) / RAIN_COINS, -20)
				if launch(from, target, 1, "coin", RAIN_FLIGHT, 0) == 0 then
					break
				end
				flights[#flights].t0 = fxTime + (i - 1) * (RAIN_TIME - RAIN_FLIGHT) / (RAIN_COINS - 1)
			end
		end
	elseif kind == "cometBanked" then
		local glow = num(data.glow) or 0
		showStamp(Prefs.t("celebrate.cometBanked", { amount = Prefs.number(glow) }), GOLD, "small", 2)
		if glow > 0 then
			reward("glow", middle, glow, 12)
		end
	elseif kind == "release" then
		local dust = num(data.dust)
		if dust and dust > 0 then
			reward("stardust", middle, dust, 6)
		end
	elseif kind == "unlock" then
		local prefix = if type(data.kind) == "string" then UNLOCK_PREFIX[data.kind] else nil
		if prefix and Text.isKey(data.id, 32) then
			Toast.show(Prefs.t("celebrate.unlock", { item = Prefs.t(prefix .. data.id) }), "reward")
		end
	end
	ScreenFX.Celebrated:Fire({ kind = kind, data = data })
end
ScreenFX._onCelebrate = onCelebrate

-- Réactions aux signaux du monde (joueur local) ------------------------------------------------------

local function localSlot(): number
	return WorldStateController.localSlot()
end

local function capacity(): number
	local upgrades = State.get("upgrades")
	local level = if type(upgrades) == "table" and isFinite(upgrades.conga) then upgrades.conga else 0
	return Formulas.congaCapacity(level)
end

local function onBanked(slot: number, op: Types.LineBankOp)
	if slot == 0 or slot ~= localSlot() or type(op) ~= "table" then
		return
	end
	lastLineCount = 0
	local bonus = if isFinite(op.bonus) then op.bonus else 1
	showStamp(Prefs.t("stamp.parade", { bonus = Text.bonus(bonus, Prefs.language()) }), GOLD, "parade", nil)
	local target = anchor("glow")
	if target == nil or not isShown(target) or not isFinite(op.count) then
		return
	end
	local from: Vector2? = nil
	if op.atBeacon then
		local player = Players.LocalPlayer
		local character = if player then player.Character else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			from = worldToScreen(root.Position)
		end
	else
		from = worldToScreen(WorldLayout.gateCFrame(slot).Position)
	end
	local size = viewportSize()
	local origin = from or Vector2.new(size.X / 2, size.Y * 0.7)
	local count = math.clamp(PARADE_COINS_MIN + math.floor(op.count / 3), PARADE_COINS_MIN, PARADE_COINS_MAX)
	launch(origin, target, count, "coin", COIN_TIME, COIN_STAGGER)
end

local function onSnipped(payload: Types.SnipEventPayload)
	if type(payload) ~= "table" or payload.victimSlot ~= localSlot() or payload.victimSlot == 0 then
		return
	end
	ScreenFX.vignette(SNIP_PINK, SNIP_VIGNETTE_TIME)
	Juice.cameraShake(SNIP_SHAKE, SNIP_SHAKE_TIME)
	lastLineCount = WorldStateController.lineLength(payload.victimSlot)
end

local function onLineOp(slot: number, op: Types.LineOp)
	if slot == 0 or slot ~= localSlot() or type(op) ~= "table" then
		return
	end
	local n = WorldStateController.lineLength(slot)
	if op.op == "add" then
		local cap = capacity()
		-- la file vient de se remplir : « Conga ×N ! »
		if n >= cap and lastLineCount < cap and n >= 2 then
			showStamp(Prefs.t("stamp.congaTimes", { n = n }), GOLD, "small", 1.2)
		end
	end
	lastLineCount = n
end

local function onEventChanged(ev: Types.EventStatePayload, _old: Types.EventStatePayload?)
	local c = if type(ev) == "table" then ev.comet else nil
	if c == nil then
		lastCarrier = { id = 0, userId = nil }
		return
	end
	local me = localUserId()
	local carrier = if c.phase == "carried" then c.carrierId else nil
	-- vol : la Comète passe d'un autre porteur au joueur local
	if
		carrier == me
		and me ~= 0
		and lastCarrier.id == c.id
		and lastCarrier.userId ~= nil
		and lastCarrier.userId ~= me
	then
		showStamp(Prefs.t("stamp.cometStolen"), Color3.fromRGB(255, 205, 60), "comet", nil)
	end
	lastCarrier = { id = c.id, userId = carrier }
end

-- Cycle de vie ----------------------------------------------------------------------------------

function ScreenFX.Init()
	ensureGui()
end

function ScreenFX.Start()
	if started then
		return
	end
	started = true
	Net.event("Feedback").OnClientEvent:Connect(onFeedback)
	Net.event("Celebrate").OnClientEvent:Connect(onCelebrate)
	WorldStateController.Banked:Connect(onBanked)
	WorldStateController.Snipped:Connect(onSnipped)
	WorldStateController.LineOp:Connect(onLineOp)
	WorldStateController.EventChanged:Connect(onEventChanged)
	RunService.RenderStepped:Connect(onFrame)
end

-- Exposé pour les tests
ScreenFX._state = function()
	return {
		flights = #flights,
		cards = #cards,
		queuedCards = #cardQueue,
		stamps = stamps,
		title = title,
		confetti = confetti,
		floaters = floaters,
		vignette = vignetteFrames,
		gui = gui,
		toastMemory = toastCount,
		cardList = cards,
		flightList = flights,
	}
end

return ScreenFX
