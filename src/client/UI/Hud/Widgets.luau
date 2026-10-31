--!strict
-- Hud/Widgets — briques d'interface du paquet client-hud, construites en code (GDD §10.1) :
-- pastilles, boutons (appui 0,92 → rebond, survol 1,05, +10 % de luminosité, son Click,
-- Selectable), libellés TextScaled bornés, pièce et étoile dessinées en Frames, pastille « ! »,
-- reflet UIGradient, balayage radial (recharge du Dash, anneau d'acclamation), main d'accueil.
-- Aucune image importée : formes en Frames et grands glyphes.

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
Widgets.HOVER_SCALE = 1.05
Widgets.HOVER_TIME = 0.12
Widgets.PRESS_LIGHTEN = 0.1

export type Radial = {
	frame: Frame,
	set: (progress: number) -> (),
}

local function lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end
Widgets.lighten = lighten

function Widgets.corner(radius: UDim?): UICorner
	return Create("UICorner", { CornerRadius = radius or Theme.Corner })
end

function Widgets.round(): UICorner
	return Create("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Widgets.stroke(color: Color3?, thickness: number?, border: boolean?): UIStroke
	return Create("UIStroke", {
		Color = color or Widgets.STROKE,
		Thickness = thickness or 2,
		ApplyStrokeMode = if border == false
			then Enum.ApplyStrokeMode.Contextual
			else Enum.ApplyStrokeMode.Border,
	})
end

-- Dégradé vertical léger (haut clair → bas sombre)
function Widgets.gradient(top: Color3?, bottom: Color3?): UIGradient
	return Create("UIGradient", {
		Color = ColorSequence.new(top or Color3.new(1, 1, 1), bottom or Color3.fromRGB(205, 200, 225)),
		Rotation = 90,
	})
end

export type LabelProps = {
	name: string,
	text: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	font: Font?,
	maxSize: number?,
	minSize: number?,
	xAlign: Enum.TextXAlignment?,
	zIndex: number?,
	strokeThickness: number?,
	parent: Instance?,
}

-- Libellé TextScaled + UITextSizeConstraint (+25 % de texte en français : jamais de débordement)
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
		ZIndex = p.zIndex or 2,
		AutoLocalize = true,
		Parent = p.parent,
	}, {
		Create("UITextSizeConstraint", { MaxTextSize = p.maxSize or 24, MinTextSize = p.minSize or 8 }),
		Create("UIStroke", {
			Color = Widgets.STROKE,
			Thickness = p.strokeThickness or 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	})
end

-- Conteneur transparent positionné, porteur de l'UIScale « HudScale » (apparition, pulsation)
-- ; le visuel est un enfant (le bouton garde son propre UIScale « JuiceScale »)
function Widgets.holder(
	name: string,
	size: UDim2,
	position: UDim2,
	anchor: Vector2?,
	parent: Instance?
): (Frame, UIScale)
	local scale = Create("UIScale", { Name = "HudScale", Scale = 1 })
	local frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = size,
		Position = position,
		AnchorPoint = anchor or Vector2.zero,
		Visible = false,
		Parent = parent,
	}, { scale })
	return frame, scale
end

-- Pastille arrondie qui remplit son conteneur
function Widgets.pill(name: string, parent: Instance?, accent: Color3?): Frame
	return Create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.08,
		Parent = parent,
	}, {
		Widgets.corner(Theme.Corner),
		Widgets.stroke(accent or Widgets.STROKE, 2.5),
		Widgets.gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 185, 215)),
	})
end

-- Bouton principal : appui, survol, luminosité, son Click, Selectable (navigation manette)
function Widgets.button(name: string, parent: Instance?, color: Color3, round: boolean?): TextButton
	local button = Create("TextButton", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		Active = true,
		ZIndex = 2,
		Parent = parent,
	}, {
		if round then Widgets.round() else Widgets.corner(Theme.Corner),
		Widgets.stroke(Widgets.STROKE, 3),
		Widgets.gradient(),
	})
	Juice.press(button)
	local scale = Juice.scaleOf(button)
	button.MouseEnter:Connect(function()
		Juice.tween(scale, Widgets.HOVER_TIME, { Scale = Widgets.HOVER_SCALE })
	end)
	button.MouseButton1Down:Connect(function()
		button.BackgroundColor3 = lighten(color, Widgets.PRESS_LIGHTEN)
	end)
	local function restore()
		button.BackgroundColor3 = color
	end
	button.MouseButton1Up:Connect(restore)
	button.MouseLeave:Connect(restore)
	button.Activated:Connect(function()
		AudioController.play("Click", 0.04)
	end)
	return button
end

-- Grand glyphe centré (icône)
function Widgets.glyph(
	name: string,
	text: string,
	parent: Instance?,
	color: Color3?,
	maxSize: number?
): TextLabel
	return Widgets.label({
		name = name,
		text = text,
		size = UDim2.fromScale(0.8, 0.8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = color,
		maxSize = maxSize or 48,
		zIndex = 3,
		strokeThickness = 2,
		parent = parent,
	})
end

-- Pièce de Glow dessinée (disque doré, anneau intérieur, reflet)
function Widgets.coin(name: string, size: UDim2, position: UDim2, parent: Instance?, anchor: Vector2?): Frame
	return Create("Frame", {
		Name = name,
		Size = size,
		Position = position,
		AnchorPoint = anchor or Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Colors.Gold,
		ZIndex = 3,
		Parent = parent,
	}, {
		Widgets.round(),
		Widgets.stroke(Color3.fromRGB(150, 95, 20), 2),
		Create("Frame", {
			Name = "Inner",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			BackgroundColor3 = Color3.fromRGB(255, 186, 40),
			ZIndex = 3,
		}, { Widgets.round() }),
		Create("Frame", {
			Name = "Glint",
			Position = UDim2.fromScale(0.22, 0.18),
			Size = UDim2.fromScale(0.22, 0.22),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.2,
			ZIndex = 4,
		}, { Widgets.round() }),
	})
end

-- Pastille rouge « ! » (action possible dans le panneau)
function Widgets.badge(parent: Instance?): Frame
	return Create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.92, 0.1),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.Colors.Danger,
		Visible = false,
		ZIndex = 6,
		Parent = parent,
	}, {
		Widgets.round(),
		Widgets.stroke(Color3.new(1, 1, 1), 2),
		Widgets.label({
			name = "Mark",
			text = "!",
			size = UDim2.fromScale(1, 1),
			maxSize = 20,
			zIndex = 7,
		}),
	})
end

-- Reflet des boutons principaux : UIGradient.Offset −1 → 1 (piloté par le HUD toutes les 4 s) ;
-- le calque reprend l'arrondi du parent (bouton rond : pas de coins carrés qui dépassent du disque)
function Widgets.shine(parent: GuiObject): UIGradient
	local parentCorner = parent:FindFirstChildOfClass("UICorner")
	local radius = if parentCorner then parentCorner.CornerRadius else Theme.Corner
	local gradient = Create("UIGradient", {
		Name = "ShineGradient",
		Rotation = 25,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	Create("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		Active = false,
		ZIndex = 5,
		Parent = parent,
	}, { Widgets.corner(radius), gradient })
	return gradient
end

-- Balayage radial en Frames (deux demi-disques masqués, UIGradient en marche d'escalier) :
-- set(p) remplit p ∈ [0 ; 1] du disque, dans le sens horaire depuis midi
function Widgets.radial(
	name: string,
	parent: Instance?,
	color: Color3,
	transparency: number,
	zIndex: number?
): Radial
	local z = zIndex or 4
	local frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = parent,
	})
	local function half(side: string, keys: { NumberSequenceKeypoint }): (Frame, UIGradient)
		local gradient = Create("UIGradient", { Transparency = NumberSequence.new(keys), Rotation = 0 })
		local clip = Create("Frame", {
			Name = side,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Size = UDim2.fromScale(0.5, 1),
			Position = if side == "Right" then UDim2.fromScale(0.5, 0) else UDim2.fromScale(0, 0),
			ZIndex = z,
			Parent = frame,
		}, {
			Create("Frame", {
				Name = "Disc",
				Size = UDim2.fromScale(2, 1),
				Position = if side == "Right" then UDim2.fromScale(-1, 0) else UDim2.fromScale(0, 0),
				BackgroundColor3 = color,
				BackgroundTransparency = transparency,
				ZIndex = z,
			}, { Widgets.round(), gradient }),
		})
		return clip, gradient
	end
	local right, rightGradient = half("Right", {
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	local left, leftGradient = half("Left", {
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(0.501, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	local last = -1
	local function set(progress: number)
		local p = if progress == progress then math.clamp(progress, 0, 1) else 0
		if math.abs(p - last) < 1e-4 then
			return
		end
		last = p
		right.Visible = p > 0
		left.Visible = p > 0.5
		rightGradient.Rotation = 180 * math.min(p, 0.5) / 0.5
		leftGradient.Rotation = 180 * math.clamp((p - 0.5) / 0.5, 0, 1)
	end
	set(0)
	return { frame = frame, set = set }
end

-- Main d'accueil dessinée en Frames (index tendu), animée par le HUD
function Widgets.hand(parent: Instance?): Frame
	local skin = Color3.fromRGB(255, 236, 214)
	return Create("Frame", {
		Name = "Hand",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.6, 0, 0.6, 0),
		Size = UDim2.fromOffset(40, 56),
		Visible = false,
		ZIndex = 9,
		Parent = parent,
	}, {
		Create("Frame", {
			Name = "Finger",
			Position = UDim2.fromOffset(4, 0),
			Size = UDim2.fromOffset(13, 30),
			BackgroundColor3 = skin,
			ZIndex = 10,
		}, { Widgets.round(), Widgets.stroke(Widgets.STROKE, 2) }),
		Create("Frame", {
			Name = "Palm",
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.fromOffset(34, 30),
			BackgroundColor3 = skin,
			ZIndex = 9,
		}, { Widgets.corner(UDim.new(0, 10)), Widgets.stroke(Widgets.STROKE, 2) }),
	})
end

-- Petite touche de raccourci (PC / manette), cachée sur tactile
function Widgets.keyCap(parent: Instance?, text: string): TextLabel
	local cap = Widgets.label({
		name = "KeyCap",
		text = text,
		size = UDim2.fromOffset(26, 22),
		position = UDim2.new(0, -4, 1, 4),
		anchor = Vector2.new(0, 1),
		maxSize = 16,
		zIndex = 8,
		parent = parent,
	})
	cap.BackgroundTransparency = 0.15
	cap.BackgroundColor3 = Widgets.STROKE
	Widgets.corner(UDim.new(0, 6)).Parent = cap
	cap.AutoLocalize = false
	cap.Visible = false
	return cap
end

return Widgets
