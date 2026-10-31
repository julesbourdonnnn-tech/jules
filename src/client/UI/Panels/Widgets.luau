--!strict
-- Panels/Widgets — paquet « client-panels » : briques d'interface des panneaux, construites en
-- code (GDD §10.1 : aucune image importée, formes en Frames et grands glyphes).
--   * boutons (§9.2) : appui UIScale 1 → 0,92 en 0,06 s Quad Out, relâchement 0,92 → 1,05 → 1 en
--     0,18 s Back Out, +10 % de luminosité pendant l'appui, survol 1,05 en 0,12 s, son Click,
--     Selectable (manette) ; bouton désactivé : refus (secousse ±6 px × 3 en 0,25 s, contour rouge
--     0,25 s, son Error)
--   * libellés TextScaled + UITextSizeConstraint (le français est ≈ 25 % plus long)
--   * cartes, barres de progression (remplissage 0,3 s Quad Out), anneaux de points, interrupteurs
--     80 × 48, pièce et étoile dessinées, icônes de Nebbies en Frames (corps à la couleur de rareté
--     ou de forme, yeux, accent d'espèce, étoiles, verrou, variantes)
-- Mouvement réduit : Juice remplace les mouvements par des fondus / valeurs directes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Nebbies = require(Shared.Config.Nebbies)

local Client = script.Parent.Parent.Parent
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local AudioController = require(Client.Controllers.AudioController)

local Widgets = {}

Widgets.STAMP_FONT = Font.fromEnum(Enum.Font.LuckiestGuy)
Widgets.STROKE = Theme.Colors.Stroke
Widgets.TOP = Color3.fromRGB(70, 60, 116)
Widgets.BOTTOM = Color3.fromRGB(40, 34, 70)
Widgets.CARD = Color3.fromRGB(58, 50, 96)
Widgets.DIM = Color3.fromRGB(84, 78, 120)
Widgets.CYAN = Color3.fromRGB(110, 220, 255)

-- Durées du §9.2
local PRESS_SCALE, PRESS_TIME = 0.92, 0.06
local OVERSHOOT, RELEASE_TIME = 1.05, 0.18
local HOVER_SCALE, HOVER_TIME = 1.05, 0.12
local LIGHTEN = 0.1
local REFUSE_TIME = 0.25

local function lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end
Widgets.lighten = lighten

local function darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end
Widgets.darken = darken

-- ---------------------------------------------------------------------------------------------
-- Décor
-- ---------------------------------------------------------------------------------------------

function Widgets.corner(radius: UDim?): UICorner
	return Create("UICorner", { CornerRadius = radius or Theme.Corner })
end

function Widgets.round(): UICorner
	return Create("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Widgets.stroke(color: Color3?, thickness: number?): UIStroke
	return Create("UIStroke", {
		Name = "Stroke",
		Color = color or Widgets.STROKE,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Dégradé vertical léger (haut clair → bas sombre)
function Widgets.gradient(top: Color3?, bottom: Color3?): UIGradient
	return Create("UIGradient", {
		Name = "Gradient",
		Color = ColorSequence.new(top or Color3.new(1, 1, 1), bottom or Color3.fromRGB(205, 200, 225)),
		Rotation = 90,
	})
end

function Widgets.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return Create("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Widgets.listLayout(
	direction: Enum.FillDirection?,
	gap: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return Create("UIListLayout", {
		Name = "Layout",
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	})
end

-- ---------------------------------------------------------------------------------------------
-- Textes
-- ---------------------------------------------------------------------------------------------

export type LabelProps = {
	name: string,
	text: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	font: Font?,
	maxSize: number?,
	xAlign: Enum.TextXAlignment?,
	yAlign: Enum.TextYAlignment?,
	zIndex: number?,
	order: number?,
	parent: Instance?,
}

-- Libellé TextScaled + UITextSizeConstraint ; AutoLocalize pour les autres langues (GDD §13.1)
function Widgets.label(p: LabelProps): TextLabel
	return Create("TextLabel", {
		Name = p.name,
		BackgroundTransparency = 1,
		Size = p.size,
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.zero,
		FontFace = p.font or Theme.Fonts.Title,
		Text = p.text or "",
		TextColor3 = p.color or Theme.Colors.Text,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = p.xAlign or Enum.TextXAlignment.Center,
		TextYAlignment = p.yAlign or Enum.TextYAlignment.Center,
		ZIndex = p.zIndex or 2,
		LayoutOrder = p.order or 0,
		AutoLocalize = true,
		Parent = p.parent,
	}, {
		Create("UITextSizeConstraint", { MaxTextSize = p.maxSize or 24, MinTextSize = 8 }),
		Create("UIStroke", {
			Color = Widgets.STROKE,
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	})
end

-- ---------------------------------------------------------------------------------------------
-- Cartes et boutons
-- ---------------------------------------------------------------------------------------------

export type CardProps = {
	name: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	order: number?,
	parent: Instance?,
}

function Widgets.card(p: CardProps): Frame
	return Create("Frame", {
		Name = p.name,
		Size = p.size,
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.zero,
		BackgroundColor3 = p.color or Widgets.CARD,
		LayoutOrder = p.order or 0,
		Parent = p.parent,
	}, {
		Widgets.corner(Theme.CornerSmall),
		Widgets.stroke(),
		Widgets.gradient(),
	})
end

export type ButtonProps = {
	name: string,
	text: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	textColor: Color3?,
	maxText: number?,
	order: number?,
	parent: Instance?,
	sound: string?, -- "" = aucun son
	onClick: (() -> ())?,
	onRefused: (() -> ())?, -- appui sur un bouton désactivé (après la secousse)
}

type ButtonState = {
	base: Color3,
	enabled: boolean,
	pressed: boolean,
	hovered: boolean,
	label: TextLabel,
}

local buttonStates: { [GuiButton]: ButtonState } = setmetatable({}, { __mode = "k" }) :: any

local function scaleTo(button: GuiButton, value: number, duration: number, style: Enum.EasingStyle?)
	Juice.tween(Juice.scaleOf(button), duration, { Scale = value }, style or Enum.EasingStyle.Quad)
end

local function paint(button: GuiButton)
	local st = buttonStates[button]
	if not st then
		return
	end
	local color = if st.enabled then st.base else Widgets.DIM
	if st.pressed and st.enabled then
		color = lighten(color, LIGHTEN)
	end
	button.BackgroundColor3 = color
	st.label.TextTransparency = if st.enabled then 0 else 0.25
end

-- Bouton du jeu : retourne (bouton, libellé)
function Widgets.button(p: ButtonProps): (TextButton, TextLabel)
	local button = Create("TextButton", {
		Name = p.name,
		Text = "",
		AutoButtonColor = false,
		Size = p.size,
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.zero,
		BackgroundColor3 = p.color or Theme.Colors.Primary,
		LayoutOrder = p.order or 0,
		Selectable = true,
		Parent = p.parent,
	}, {
		Widgets.corner(Theme.CornerSmall),
		Widgets.stroke(),
		Widgets.gradient(),
	}) :: TextButton
	local label = Widgets.label({
		name = "Label",
		text = p.text,
		size = UDim2.new(1, -12, 1, -8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = p.textColor,
		maxSize = p.maxText or 26,
		zIndex = 3,
		parent = button,
	})
	local st: ButtonState = {
		base = p.color or Theme.Colors.Primary,
		enabled = true,
		pressed = false,
		hovered = false,
		label = label,
	}
	buttonStates[button] = st
	Juice.scaleOf(button)

	button.MouseButton1Down:Connect(function()
		st.pressed = true
		paint(button)
		scaleTo(button, PRESS_SCALE, PRESS_TIME)
	end)
	local function release()
		if not st.pressed then
			return
		end
		st.pressed = false
		paint(button)
		local scale = Juice.scaleOf(button)
		if Juice.reducedMotion() then
			scale.Scale = 1
			return
		end
		local up = Juice.tween(scale, RELEASE_TIME * 0.4, { Scale = OVERSHOOT }, Enum.EasingStyle.Quad)
		up.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and not st.pressed then
				Juice.tween(scale, RELEASE_TIME * 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(function()
		st.hovered = false
		release()
		if not st.pressed then
			scaleTo(button, 1, HOVER_TIME)
		end
	end)
	button.MouseEnter:Connect(function()
		st.hovered = true
		if not st.pressed and not Juice.reducedMotion() then
			scaleTo(button, HOVER_SCALE, HOVER_TIME)
		end
	end)
	button.SelectionGained:Connect(function()
		if not Juice.reducedMotion() then
			scaleTo(button, HOVER_SCALE, HOVER_TIME)
		end
	end)
	button.SelectionLost:Connect(function()
		scaleTo(button, 1, HOVER_TIME)
	end)
	button.Activated:Connect(function()
		if not st.enabled then
			Widgets.refuse(button)
			if p.onRefused then
				p.onRefused()
			end
			return
		end
		local sound = p.sound or "Click"
		if sound ~= "" then
			AudioController.play(sound, 0.04)
		end
		if p.onClick then
			p.onClick()
		end
	end)
	return button, label
end

function Widgets.setEnabled(button: GuiButton, enabled: boolean)
	local st = buttonStates[button]
	if not st or st.enabled == enabled then
		return
	end
	st.enabled = enabled
	button:SetAttribute("Disabled", not enabled)
	paint(button)
end

function Widgets.isEnabled(button: GuiButton): boolean
	local st = buttonStates[button]
	return st == nil or st.enabled
end

-- Change la couleur de base d'un bouton (état « possédé », onglet choisi…)
function Widgets.setColor(button: GuiButton, color: Color3)
	local st = buttonStates[button]
	if st then
		st.base = color
		paint(button)
	else
		button.BackgroundColor3 = color
	end
end

function Widgets.setText(button: GuiButton, text: string)
	local st = buttonStates[button]
	if st then
		st.label.Text = text
	end
end

-- Refus (§9.2) : secousse horizontale ±6 px × 3 en 0,25 s + contour rouge 0,25 s + son Error
local refuseTokens: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
function Widgets.refuse(gui: GuiObject)
	AudioController.play("Error")
	Juice.shake(gui)
	local stroke = gui:FindFirstChild("Stroke")
	if stroke and stroke:IsA("UIStroke") then
		local token = (refuseTokens[gui] or 0) + 1
		refuseTokens[gui] = token
		stroke.Color = Theme.Colors.Danger
		stroke.Thickness = 3
		task.delay(REFUSE_TIME, function()
			if refuseTokens[gui] == token and stroke.Parent then
				stroke.Color = Widgets.STROKE
				stroke.Thickness = 2
			end
		end)
	end
end

-- Mise en avant durable (contour doré, carte d'accueil, onglet actif…)
function Widgets.highlight(gui: GuiObject, on: boolean, color: Color3?)
	local stroke = gui:FindFirstChild("Stroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = if on then color or Theme.Colors.Gold else Widgets.STROKE
		stroke.Thickness = if on then 3 else 2
	end
end

-- ---------------------------------------------------------------------------------------------
-- Barres, anneaux, interrupteurs
-- ---------------------------------------------------------------------------------------------

export type BarProps = {
	name: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	order: number?,
	parent: Instance?,
}

function Widgets.bar(p: BarProps): Frame
	local bar = Create("Frame", {
		Name = p.name,
		Size = p.size,
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.zero,
		BackgroundColor3 = Widgets.BOTTOM,
		LayoutOrder = p.order or 0,
		ClipsDescendants = true,
		Parent = p.parent,
	}, {
		Widgets.round(),
		Widgets.stroke(nil, 1.5),
	})
	Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = p.color or Theme.Colors.Success,
		BorderSizePixel = 0,
		Parent = bar,
	}, {
		Widgets.round(),
		Widgets.gradient(),
	})
	return bar
end

-- Remplissage (0-1) ; animé : 0,3 s Quad Out (§9.4 « barre remplie en 0,3 s »)
function Widgets.setBar(bar: Frame, ratio: number, animate: boolean?)
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if not fill then
		return
	end
	local r = if ratio ~= ratio then 0 else math.clamp(ratio, 0, 1)
	local size = UDim2.fromScale(r, 1)
	if animate and not Juice.reducedMotion() then
		Juice.tween(fill, 0.3, { Size = size }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	else
		fill.Size = size
	end
end

export type Ring = {
	frame: Frame,
	dots: { Frame },
	on: Color3,
	off: Color3,
	value: number,
}

-- Anneau de points (progression de la Supernova, maintien de confirmation)
function Widgets.ring(
	name: string,
	size: number,
	dotCount: number,
	on: Color3,
	off: Color3?,
	parent: Instance?
): Ring
	local frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	local dots: { Frame } = {}
	local dot = math.max(4, math.floor(size * 0.11))
	local radius = size / 2 - dot / 2
	for i = 1, dotCount do
		local angle = (i - 1) / dotCount * math.pi * 2 - math.pi / 2
		dots[i] = Create("Frame", {
			Name = "Dot" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius),
			Size = UDim2.fromOffset(dot, dot),
			BackgroundColor3 = off or Widgets.BOTTOM,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = frame,
		}, { Widgets.round() })
	end
	return { frame = frame, dots = dots, on = on, off = off or Widgets.BOTTOM, value = 0 }
end

function Widgets.setRing(ring: Ring, ratio: number)
	local r = if ratio ~= ratio then 0 else math.clamp(ratio, 0, 1)
	ring.value = r
	local lit = math.floor(r * #ring.dots + 1e-6)
	for i, dot in ring.dots do
		dot.BackgroundColor3 = if i <= lit then ring.on else ring.off
	end
end

-- Interrupteur 80 × 48 (§10.3) : retourne le bouton ; Widgets.setToggle pour l'état
function Widgets.toggle(name: string, parent: Instance?, onChanged: (boolean) -> ()): TextButton
	local button = Create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(80, 48),
		BackgroundColor3 = Widgets.DIM,
		Selectable = true,
		Parent = parent,
	}, {
		Widgets.round(),
		Widgets.stroke(),
	}) :: TextButton
	Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = button,
	}, { Widgets.round(), Widgets.gradient() })
	button:SetAttribute("On", false)
	Juice.press(button)
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") == true then
			Widgets.refuse(button)
			return
		end
		AudioController.play("Click")
		onChanged(button:GetAttribute("On") ~= true)
	end)
	return button
end

function Widgets.setToggle(button: GuiButton, on: boolean, animate: boolean?)
	local was = button:GetAttribute("On")
	button:SetAttribute("On", on)
	local knob = button:FindFirstChild("Knob") :: Frame?
	local color = if on then Theme.Colors.Success else Widgets.DIM
	if button:GetAttribute("Disabled") == true then
		color = darken(color, 0.35)
	end
	button.BackgroundColor3 = color
	if knob then
		local pos = if on then UDim2.new(1, -44, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
		if animate and was ~= on and not Juice.reducedMotion() then
			Juice.tween(knob, 0.15, { Position = pos }, Enum.EasingStyle.Back)
		elseif not animate or was ~= on then
			-- même état et rendu périodique : rien à rejouer (pas de tween toutes les 0,5 s)
			knob.Position = pos
		end
	end
end

function Widgets.setToggleEnabled(button: GuiButton, enabled: boolean)
	button:SetAttribute("Disabled", not enabled)
	Widgets.setToggle(button, button:GetAttribute("On") == true, false)
end

-- ---------------------------------------------------------------------------------------------
-- Glyphes dessinés : pièce de Glow, étoile de Stardust
-- ---------------------------------------------------------------------------------------------

function Widgets.coin(size: number, parent: Instance?): Frame
	return Create("Frame", {
		Name = "Coin",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.Gold,
		Parent = parent,
	}, {
		Widgets.round(),
		Widgets.stroke(Color3.fromRGB(150, 100, 20), 2),
		Create("Frame", {
			Name = "Inner",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 240, 160),
		}, { Widgets.round() }),
	})
end

-- ---------------------------------------------------------------------------------------------
-- Icône de Nebby en Frames (pas de ViewportFrame : léger sur mobile)
-- ---------------------------------------------------------------------------------------------

local SILHOUETTE = Color3.fromRGB(70, 66, 96)

-- Construit une icône vide (à remplir avec setNebby) de `size` × `size`
function Widgets.nebbyIcon(name: string, size: UDim2, parent: Instance?): Frame
	local icon = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = size,
		Parent = parent,
	})
	local body = Create("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.68, 0.68),
		BackgroundColor3 = SILHOUETTE,
		ZIndex = 3,
		Parent = icon,
	}, {
		Widgets.round(),
		Widgets.stroke(nil, 2),
		Create("UIAspectRatioConstraint", { AspectRatio = 1 }),
		Create("UIGradient", {
			Name = "Shine",
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 220)),
			Rotation = 90,
		}),
	})
	for i, x in { 0.34, 0.66 } do
		Create("Frame", {
			Name = if i == 1 then "EyeL" else "EyeR",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.45),
			Size = UDim2.fromScale(0.13, 0.2),
			BackgroundColor3 = Color3.fromRGB(30, 24, 48),
			ZIndex = 4,
			Parent = body,
		}, { Widgets.round() })
	end
	Create("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.78, 0.14),
		Size = UDim2.fromScale(0.24, 0.24),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = icon,
	}, { Widgets.round(), Widgets.stroke(nil, 1.5) })
	Widgets.label({
		name = "Mark",
		text = "",
		size = UDim2.fromScale(0.6, 0.6),
		position = UDim2.fromScale(0.5, 0.52),
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.Colors.TextDim,
		maxSize = 40,
		zIndex = 5,
		parent = icon,
	})
	Widgets.label({
		name = "Stars",
		text = "",
		size = UDim2.fromScale(1, 0.26),
		position = UDim2.fromScale(0.5, 1),
		anchor = Vector2.new(0.5, 1),
		color = Theme.Colors.Gold,
		maxSize = 16,
		zIndex = 6,
		parent = icon,
	})
	Widgets.label({
		name = "Lock",
		text = "🔒",
		size = UDim2.fromScale(0.32, 0.32),
		position = UDim2.fromScale(0, 0),
		maxSize = 18,
		zIndex = 6,
		parent = icon,
	}).Visible =
		false
	Widgets.label({
		name = "Sparkle",
		text = "✦",
		size = UDim2.fromScale(0.3, 0.3),
		position = UDim2.fromScale(0.02, 0.62),
		color = Color3.fromRGB(255, 225, 90),
		maxSize = 18,
		zIndex = 6,
		parent = icon,
	}).Visible =
		false
	return icon
end

export type NebbyLook = {
	s: number,
	f: number,
	v: number,
	stars: number?,
	locked: boolean?,
	known: boolean?, -- false : silhouette grise (« ? »)
}

-- Couleur principale d'un Nebby (rareté, forme, Golden)
function Widgets.nebbyColor(s: number, f: number, v: number): Color3
	local rarity = Nebbies.Rarities[Nebbies.rarityOf(s)]
	local color = if rarity then rarity.color else Color3.new(1, 1, 1)
	local form = Nebbies.Forms[f]
	if form then
		if form.bodyColor then
			color = form.bodyColor
		elseif form.bodyTint then
			color = color:Lerp(form.bodyTint, form.tintAlpha or 0.3)
		end
	end
	local golden = Nebbies.Variants.golden
	if golden.color and bit32.btest(v, golden.bit) then
		color = golden.color
	end
	return color
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 150)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 120)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(120, 230, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 140, 255)),
})

function Widgets.setNebby(icon: Frame, look: NebbyLook)
	local body = icon:FindFirstChild("Body") :: Frame?
	if not body then
		return
	end
	local known = look.known ~= false
	local species = Nebbies.Species[look.s]
	local form = Nebbies.Forms[look.f]
	local shine = body:FindFirstChild("Shine") :: UIGradient?
	local accent = icon:FindFirstChild("Accent") :: Frame?
	local mark = icon:FindFirstChild("Mark") :: TextLabel?
	local stars = icon:FindFirstChild("Stars") :: TextLabel?
	local lock = icon:FindFirstChild("Lock") :: TextLabel?
	local sparkle = icon:FindFirstChild("Sparkle") :: TextLabel?
	local huge = bit32.btest(look.v, Nebbies.Variants.huge.bit)
	body.Size = if huge and known then UDim2.fromScale(0.84, 0.84) else UDim2.fromScale(0.68, 0.68)
	for _, eyeName in { "EyeL", "EyeR" } do
		local eye = body:FindFirstChild(eyeName) :: Frame?
		if eye then
			eye.Visible = known
			eye.BackgroundColor3 = if form and form.eyeColor
				then form.eyeColor
				else Color3.fromRGB(30, 24, 48)
		end
	end
	if not known or species == nil then
		body.BackgroundColor3 = SILHOUETTE
		if shine then
			shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 220))
		end
		if accent then
			accent.Visible = false
		end
		if mark then
			mark.Text = "?"
			mark.Visible = true
		end
		if stars then
			stars.Text = ""
		end
		if lock then
			lock.Visible = false
		end
		if sparkle then
			sparkle.Visible = false
		end
		return
	end
	body.BackgroundColor3 = Widgets.nebbyColor(look.s, look.f, look.v)
	if shine then
		if form and form.hsvCycle then
			shine.Color = RAINBOW
		elseif form and form.accentColors and #form.accentColors >= 2 then
			shine.Color =
				ColorSequence.new(lighten(form.accentColors[1], 0.4), lighten(form.accentColors[2], 0.4))
		else
			shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 220))
		end
	end
	if accent then
		accent.Visible = true
		local color = species.accent
		if form and form.accentColors and #form.accentColors > 0 then
			color = form.accentColors[1]
		elseif form and form.fire then
			color = Color3.fromRGB(255, 170, 60)
		end
		accent.BackgroundColor3 = color
	end
	if mark then
		mark.Visible = false
	end
	if stars then
		local n = math.clamp(math.floor(look.stars or 1), 1, Nebbies.MAX_STARS)
		stars.Text = if n >= 2 then string.rep("★", n) else ""
	end
	if lock then
		lock.Visible = look.locked == true
	end
	if sparkle then
		sparkle.Visible = bit32.btest(look.v, Nebbies.Variants.golden.bit)
			or bit32.btest(look.v, Nebbies.Variants.starborn.bit)
	end
end

return Widgets
