--!strict
-- Glyph : icône de touche qui suit le périphérique du joueur (couche console de Comet Conga).
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
local Text = require(Client.UI.Text)

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
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.Title,
		AutoLocalize = false,
		ZIndex = frame.ZIndex + 1,
		Visible = false,
		Parent = frame,
	}) :: TextLabel
	-- nom de touche du clavier (« E », « Shift », « ⌫ ») à 0,6 × la taille de l'icône, 28 px TV au moins
	-- (UI/Text, libellé à sa taille dessinée) : la pastille s'élargit avec la longueur du nom
	-- (Glyph.refresh : 0,4 × la taille par caractère au-delà de 2), le texte n'a jamais à rétrécir
	Text.style(text, "label", math.max(Console.MinTextSize, math.floor(size * 0.6)), { wrapped = false })
	Text.raw(text, "")
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
		Text.raw(self._text, info.text)
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

-- =============================================================================================
-- Étoile DESSINÉE (lot B1, règle 18 du GDD v2.0 §10.8 « aucun symbole hors police », INT-V2-GLYPHS a) :
-- « ★ » n'est dans aucune des deux polices du jeu (FredokaOne, LuckiestGuy) ; l'étoile est un
-- pentagramme de 5 traits arrondis et un disque central (aucune image téléversée), dessiné deux fois :
-- liseré sombre dessous (trait plus épais), couleur dessus. Les étoiles des clés common.stars et
-- celebrate.star viennent du repère « {*} » (UI/Text.STAR).
-- =============================================================================================

local STAR_THICKNESS = 0.2 -- épaisseur d'un trait (fraction de la taille)
local STAR_CORE = 0.4 -- rayon du disque central (fraction du rayon de l'étoile)

-- Une couche du pentagramme (traits de `thick` px) dans `holder` (taille `size` px)
local function starLayer(
	holder: Frame,
	name: string,
	size: number,
	thick: number,
	core: number,
	color: Color3,
	z: number
)
	local layer = Instance.new("Frame")
	layer.Name = name
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = z
	layer.Parent = holder
	local r = size / 2 - thick / 2
	local cx, cy = size / 2, size / 2 + size * 0.04 -- le centre visuel d'une étoile est un peu bas
	local points = {}
	for k = 0, 4 do
		local a = math.rad(-90 + 72 * k)
		points[k] = Vector2.new(cx + r * math.cos(a), cy + r * math.sin(a))
	end
	for k = 0, 4 do
		local a, b = points[k], points[(k + 2) % 5]
		local d = b - a
		local seg = Instance.new("Frame")
		seg.Name = "Ray" .. (k + 1)
		seg.BorderSizePixel = 0
		seg.BackgroundColor3 = color
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		-- en fractions du cadre (carré) : l'étoile suit la taille de son cadre (texte agrandi, autre
		-- taille dessinée) sans être reconstruite, et sans l'arrondi au pixel des Offset (relecture B1)
		seg.Position = UDim2.fromScale((a.X + b.X) / 2 / size, (a.Y + b.Y) / 2 / size)
		seg.Size = UDim2.fromScale((d.Magnitude + thick) / size, thick / size)
		seg.Rotation = math.deg(math.atan2(d.Y, d.X))
		seg.ZIndex = z
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = seg
		seg.Parent = layer
	end
	local disc = Instance.new("Frame")
	disc.Name = "Core"
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = color
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(cx / size, cy / size)
	disc.Size = UDim2.fromScale(2 * core / size, 2 * core / size)
	disc.ZIndex = z
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = disc
	disc.Parent = layer
	return layer
end

-- Étoile de `size` px (taille dessinée, avant UIScale) : couleur `color`, liseré `edge` de `edgePx` px
-- (défaut : bleu nuit du contour des textes, 3 px à 28 px et plus). Rend le cadre (Name « Star »).
function Glyph.star(parent: Instance?, size: number, color: Color3?, edge: Color3?, edgePx: number?): Frame
	local s = if type(size) == "number" and size == size then math.clamp(size, 8, 512) else 32
	local e = if type(edgePx) == "number" and edgePx == edgePx
		then math.clamp(edgePx, 0, s / 4)
		else math.max(1, s / 12)
	local holder = Instance.new("Frame")
	holder.Name = "Star"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(s, s)
	holder.Active = false
	holder.Selectable = false
	holder:SetAttribute("Icon", "star")
	local thick = s * STAR_THICKNESS
	local core = (s / 2) * STAR_CORE
	if e > 0 then
		starLayer(holder, "Edge", s, thick + 2 * e, core + e, edge or Theme.Colors.Stroke, 1)
	end
	starLayer(holder, "Fill", s, thick, core, color or Theme.Colors.Gold, 2)
	if parent then
		holder.Parent = parent
	end
	return holder
end

-- =============================================================================================
-- Couronne et goutte DESSINÉES (lot B4, étape 5 ; D16, D20, INT-B1-GLYPHS2, règle 18 du GDD v2.0
-- §10.8) : « ♛ » du panneau des ranchs n'est dans aucune des deux polices du jeu ; la couronne est 5
-- primitives (bandeau, corps et 3 pointes en losange), la goutte du halo 2 (disque et pointe en
-- losange), dessinées deux fois comme l'étoile : liseré sombre dessous, couleur du texte dessus. Elles
-- viennent des repères Text.CROWN (« {^} ») et Text.DROP (« {~} ») de UI/Text.
-- =============================================================================================

-- Primitive d'une icône, en fractions du cadre carré : centre (x, y), taille (w, h), rotation (degrés),
-- arrondi des coins (UICorner, fraction de la plus petite dimension)
type Primitive = { name: string, x: number, y: number, w: number, h: number, rot: number, round: number }

local CROWN: { Primitive } = {
	{ name = "Band", x = 0.5, y = 0.79, w = 0.86, h = 0.17, rot = 0, round = 0.3 },
	{ name = "Body", x = 0.5, y = 0.62, w = 0.74, h = 0.26, rot = 0, round = 0.1 },
	{ name = "TipL", x = 0.2, y = 0.43, w = 0.25, h = 0.25, rot = 45, round = 0.2 },
	{ name = "TipC", x = 0.5, y = 0.33, w = 0.27, h = 0.27, rot = 45, round = 0.2 },
	{ name = "TipR", x = 0.8, y = 0.43, w = 0.25, h = 0.25, rot = 45, round = 0.2 },
}
local DROP: { Primitive } = {
	{ name = "Bulb", x = 0.5, y = 0.63, w = 0.6, h = 0.6, rot = 0, round = 0.5 },
	{ name = "Tip", x = 0.5, y = 0.43, w = 0.42, h = 0.42, rot = 45, round = 0.15 },
}

-- Une couche (Edge ou Fill) des primitives `prims`, agrandies de `grow` (fraction du cadre) chacune
local function primitiveLayer(
	holder: Frame,
	name: string,
	prims: { Primitive },
	grow: number,
	color: Color3,
	z: number
)
	local layer = Instance.new("Frame")
	layer.Name = name
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = z
	layer.Parent = holder
	for _, p in prims do
		local part = Instance.new("Frame")
		part.Name = p.name
		part.BorderSizePixel = 0
		part.BackgroundColor3 = color
		part.AnchorPoint = Vector2.new(0.5, 0.5)
		-- en fractions du cadre : l'icône suit la taille de son cadre sans être reconstruite
		part.Position = UDim2.fromScale(p.x, p.y)
		part.Size = UDim2.fromScale(p.w + grow, p.h + grow)
		part.Rotation = p.rot
		part.ZIndex = z
		if p.round > 0 then
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(p.round, 0)
			round.Parent = part
		end
		part.Parent = layer
	end
end

local function primitiveIcon(
	icon: string,
	prims: { Primitive },
	parent: Instance?,
	size: number,
	color: Color3?,
	edge: Color3?,
	edgePx: number?
): Frame
	local s = if type(size) == "number" and size == size then math.clamp(size, 8, 512) else 32
	local e = if type(edgePx) == "number" and edgePx == edgePx
		then math.clamp(edgePx, 0, s / 4)
		else math.max(1, s / 12)
	local holder = Instance.new("Frame")
	holder.Name = string.upper(string.sub(icon, 1, 1)) .. string.sub(icon, 2)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(s, s)
	holder.Active = false
	holder.Selectable = false
	holder:SetAttribute("Icon", icon)
	if e > 0 then
		primitiveLayer(holder, "Edge", prims, 2 * e / s, edge or Theme.Colors.Stroke, 1)
	end
	primitiveLayer(holder, "Fill", prims, 0, color or Theme.Colors.Gold, 2)
	if parent then
		holder.Parent = parent
	end
	return holder
end

-- Couronne de `size` px (repère Text.CROWN) : Name « Crown », attribut Icon = "crown"
function Glyph.crown(parent: Instance?, size: number, color: Color3?, edge: Color3?, edgePx: number?): Frame
	return primitiveIcon("crown", CROWN, parent, size, color, edge, edgePx)
end

-- Goutte de gelée de `size` px (halo, repère Text.DROP) : Name « Drop », attribut Icon = "drop"
function Glyph.drop(parent: Instance?, size: number, color: Color3?, edge: Color3?, edgePx: number?): Frame
	return primitiveIcon("drop", DROP, parent, size, color, edge, edgePx)
end

-- Recolore une étoile dessinée (texte qui change de couleur : case choisie du Ranch) ; vaut aussi pour la
-- couronne et la goutte (mêmes couches Fill et Edge)
function Glyph.paintStar(star: Instance, color: Color3?, edge: Color3?, transparency: number?)
	for _, layerName in { "Fill", "Edge" } do
		local layer = star:FindFirstChild(layerName)
		if layer then
			for _, part in layer:GetChildren() do
				if part:IsA("Frame") then
					if layerName == "Fill" and color then
						part.BackgroundColor3 = color
					elseif layerName == "Edge" and edge then
						part.BackgroundColor3 = edge
					end
					if transparency then
						part.BackgroundTransparency = transparency
					end
				end
			end
		end
	end
end

return Glyph
