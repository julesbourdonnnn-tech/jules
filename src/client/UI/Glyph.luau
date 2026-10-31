--!strict
-- Glyph : icône de touche qui suit le périphérique du joueur (docs/07-console-ps5.md §5).
--   local g = Glyph.new(button, { keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonR2 })
--   g.frame.Position = UDim2.new(1, -4, 0, -4)
--   g:set({ gamepad = Enum.KeyCode.ButtonB })      -- autre liaison
--   g:destroy()
-- Affichage selon Platform.inputKind() : manette → icône Roblox de la touche
-- (UserInputService:GetImageForKeyCode : PlayStation sur PlayStation ; repli : losange des boutons
-- de façade ou texte neutre L1/R2/↑…, jamais une lettre Xbox) ; clavier-souris → touche selon la
-- disposition du clavier (texte) ; tactile, ou aucune touche pour ce périphérique → masquée.
-- Toutes les icônes se mettent à jour sur Platform.Changed (une seule connexion pour le module).
-- Attributs posés sur le cadre (specs, audit console) : « GlyphKey » (nom de la KeyCode affichée,
-- "" si masquée) et « GlyphMode » ("image" | "text" | "diamond" | "hidden").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Console = require(Shared.Config.Console)

local Client = script.Parent.Parent
local Platform = require(Client.Util.Platform)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)

local Glyph = {}
Glyph.__index = Glyph

export type Binding = {
	keyboard: Enum.KeyCode?,
	gamepad: Enum.KeyCode?,
}

export type Props = {
	name: string?,
	size: number?, -- px de référence (défaut Config/Console.GlyphSize)
	position: UDim2?,
	anchor: Vector2?,
	zIndex: number?,
}

export type Handle = typeof(setmetatable(
	{} :: {
		frame: Frame,
		_binding: Binding,
		_image: ImageLabel,
		_text: TextLabel,
		_diamond: Frame,
		_dots: { [string]: Frame },
		_size: number,
		_alive: boolean,
	},
	Glyph
))

local DOT = 0.34 -- taille d'un point du losange (fraction du cadre)
local DOT_POSITIONS: { [string]: UDim2 } = {
	top = UDim2.fromScale(0.5, 0.2),
	bottom = UDim2.fromScale(0.5, 0.8),
	left = UDim2.fromScale(0.2, 0.5),
	right = UDim2.fromScale(0.8, 0.5),
}

local live: { [Frame]: Handle } = {}
local connected = false

local function refreshAll()
	for _, handle in live do
		handle:refresh()
	end
end

local function ensureConnected()
	if connected then
		return
	end
	connected = true
	Platform.Changed:Connect(refreshAll)
end

-- Crée l'icône dans `parent` ; masquée tant que le périphérique courant n'a pas de touche
function Glyph.new(parent: Instance, binding: Binding, props: Props?): Handle
	ensureConnected()
	local p: Props = props or {}
	local size = p.size or Console.GlyphSize
	local frame = Create("Frame", {
		Name = p.name or "Glyph",
		Size = UDim2.fromOffset(size, size),
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.zero,
		BackgroundColor3 = Theme.Colors.Stroke,
		BackgroundTransparency = 0.15,
		ZIndex = p.zIndex or 8,
		Active = false,
		Selectable = false,
		Visible = false,
		Parent = parent,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	}) :: Frame
	local image = Create("ImageLabel", {
		Name = "Image",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = frame.ZIndex + 1,
		Visible = false,
		Parent = frame,
	}) :: ImageLabel
	local text = Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(0.86, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.Title,
		AutoLocalize = false,
		ZIndex = frame.ZIndex + 1,
		Visible = false,
		Parent = frame,
	}, {
		Create(
			"UITextSizeConstraint",
			{ MaxTextSize = math.max(Console.MinTextSize, math.floor(size * 0.6)) }
		),
	}) :: TextLabel
	local diamond = Create("Frame", {
		Name = "Diamond",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = frame.ZIndex + 1,
		Visible = false,
		Parent = frame,
	}) :: Frame
	local dots: { [string]: Frame } = {}
	for slot, position in DOT_POSITIONS do
		dots[slot] = Create("Frame", {
			Name = slot,
			Size = UDim2.fromScale(DOT, DOT),
			Position = position,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Colors.Text,
			BackgroundTransparency = 0.7,
			ZIndex = frame.ZIndex + 2,
			Parent = diamond,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Create("UIStroke", { Color = Theme.Colors.Text, Thickness = 1.5 }),
		}) :: Frame
	end
	local handle = setmetatable({
		frame = frame,
		_binding = binding,
		_image = image,
		_text = text,
		_diamond = diamond,
		_dots = dots,
		_size = size,
		_alive = true,
	}, Glyph) :: Handle
	live[frame] = handle
	frame.Destroying:Connect(function()
		handle._alive = false
		live[frame] = nil
	end)
	handle:refresh()
	return handle
end

-- Touche à montrer pour le périphérique courant (nil : masquée)
function Glyph.keyFor(binding: Binding): Enum.KeyCode?
	local kind = Platform.inputKind()
	if kind == Platform.GAMEPAD then
		return binding.gamepad
	elseif kind == Platform.KEYBOARD then
		return binding.keyboard
	end
	return nil
end

function Glyph.refresh(self: Handle)
	if not self._alive then
		return
	end
	local frame = self.frame
	local key = Glyph.keyFor(self._binding)
	if key == nil then
		frame.Visible = false
		frame:SetAttribute("GlyphKey", "")
		frame:SetAttribute("GlyphMode", "hidden")
		return
	end
	local info = Platform.glyph(key)
	local mode
	if info.image ~= nil then
		mode = "image"
		self._image.Image = info.image :: string
	elseif info.slot ~= nil then
		mode = "diamond"
		for slot, dot in self._dots do
			dot.BackgroundTransparency = if slot == info.slot then 0 else 0.7
		end
	else
		mode = "text"
		self._text.Text = info.text
	end
	self._image.Visible = mode == "image"
	self._diamond.Visible = mode == "diamond"
	self._text.Visible = mode == "text"
	-- l'icône Roblox a son propre fond ; le repli garde la pastille sombre
	frame.BackgroundTransparency = if mode == "image" then 1 else 0.15
	-- touche longue du clavier (« Shift », « Enter ») : pastille élargie, texte toujours ≥ 18 px
	local length = if mode == "text" then (utf8.len(info.text) or 1) else 1
	local width = if length > 2 then math.ceil(self._size * (0.5 + 0.4 * length)) else self._size
	if frame.Size.X.Offset ~= width then
		frame.Size = UDim2.fromOffset(width, self._size)
	end
	frame.Visible = true
	frame:SetAttribute("GlyphKey", key.Name)
	frame:SetAttribute("GlyphMode", mode)
end

-- Change la liaison affichée
function Glyph.set(self: Handle, binding: Binding)
	self._binding = binding
	self:refresh()
end

-- L'icône est-elle affichée pour le périphérique courant ?
function Glyph.shown(self: Handle): boolean
	return self._alive and self.frame.Visible
end

function Glyph.destroy(self: Handle)
	if not self._alive then
		return
	end
	self._alive = false
	live[self.frame] = nil
	self.frame:Destroy()
end

return Glyph
