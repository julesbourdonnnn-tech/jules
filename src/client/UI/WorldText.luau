--!strict
-- WorldText (paquet client-hud, docs/04 §13.5, contrat v1.2) : textes du monde lisibles à 3 m sur une
-- télé (GDD v1.3 §10.2, remarque C2-12).
-- Tout texte du monde que le joueur DOIT lire (prix et niveau d'une dalle, glyphe et mot de la leçon
-- de l'accueil au-dessus de l'objet, « +N », taille d'un squishy ciblé, invites) est un BillboardGui
-- dimensionné en pixels fixes (Offset) multipliés par l'échelle d'interface de UI/Root, jamais en
-- studs ni posé au sol :
--   * plaque « Plate » en px TV, mise à l'échelle par un UIScale (WorldScale = Root.scale()) ; le
--     BillboardGui mesure plaque × échelle en pixels d'écran : la taille vue du canapé est la même en
--     720p, 1080p et 4K, et ne diminue pas avec la distance (Offset) ;
--   * texte Layout.WorldText.Text (32 px TV), « +N » Layout.WorldText.Plus (40), glyphe
--     Layout.WorldText.Glyph (48 ; invite principale Layout.Prompt.MainGlyph 64) ;
--   * LightInfluence = 0, fond foncé translucide (transparence Layout.WorldText.Background) et
--     contour 3 px ; distance maximale fixée par usage (BillboardGui.MaxDistance, dalle : 20 studs) ;
--   * invites bornées à la zone sûre de 5 % : clampToSafe rend le coin haut gauche ramené dans la
--     zone, l'appelant décale la plaque (SizeOffset) ;
--   * réserve d'étiquettes (aucune création en rafale : release rend l'étiquette, 64 au plus en
--     réserve) ; rescale réapplique l'échelle à toutes les étiquettes vivantes (fait tout seul quand
--     la taille de l'écran change).
-- Les BillboardGui vivent dans le dossier local Workspace.WorldText (jamais dans PlayerGui : ce ne
-- sont pas des écrans du HUD) et suivent leur `adornee`.
-- Module-outil sans Init ni Start (comme UI/Juice) : appelé par UI/Prompt (client-hud),
-- RanchRenderer (étiquettes des dalles, leçon de l'accueil) et VFXController (« +N »).
-- Spec (couche d) : WorldText.spec, Console_hud / Layout_hud : taille projetée de chaque texte du monde
-- ≥ Layout.WorldText.MinProjected (28 px TV) à 20 studs, en 1920 × 1080, 3840 × 2160 et 1280 × 720.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Layout = require(Shared.Config.Layout)

local Client = script.Parent.Parent
local Platform = require(Client.Util.Platform)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Glyph = require(Client.UI.Glyph)
local Util = require(Client.UI.Hud.Util)

export type Kind = "text" | "plus" | "glyph"

export type Options = {
	kind: Kind, -- taille en px TV : Layout.WorldText.Text, Plus ou Glyph
	maxDistance: number, -- studs (BillboardGui.MaxDistance)
	studsOffset: Vector3?, -- décalage au-dessus de l'objet (StudsOffsetWorldSpace)
	alwaysOnTop: boolean?,
	name: string?,
}

-- État d'une étiquette vivante (clé : le BillboardGui)
type Entry = {
	gui: BillboardGui,
	plate: Frame,
	label: TextLabel,
	scale: UIScale,
	kind: Kind,
	text: string,
	textSize: number,
	glyph: Glyph.Handle?,
	glyphSize: number,
	w: number, -- px TV de la plaque
	h: number,
	watch: RBXScriptConnection?, -- objet porteur détruit : étiquette rendue à la réserve
}

local WorldText = {}

local PAD_X = 16 -- px TV de marge intérieure
local PAD_Y = 8
local GAP = 12 -- px TV entre le glyphe et le mot
local TEXT_MARGIN = 1.15 -- marge de la largeur estimée d'un texte (voir layoutEntry)
local MIN_WIDTH = 64
local POOL_MAX = 64
local FOLDER_NAME = "WorldText"

local live: { [BillboardGui]: Entry } = {}
local pool: { [Kind]: { Entry } } = { text = {}, plus = {}, glyph = {} }
local folder: Folder? = nil
local watching = false
local serial = 0

-- =============================================================================================
-- Outils
-- =============================================================================================

local function kindOf(kind: any): Kind
	if kind == "plus" or kind == "glyph" then
		return kind
	end
	return "text"
end

-- Taille du texte d'une sorte (la sorte « glyph » porte un mot de taille courante à côté du glyphe)
local function textSizeOf(kind: Kind): number
	if kind == "plus" then
		return Layout.WorldText.Plus
	end
	return Layout.WorldText.Text
end

local function currentScale(): number
	local ok, s = pcall(Root.scale)
	if ok and type(s) == "number" and s == s and s > 0 then
		return s
	end
	return 1
end

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild(FOLDER_NAME)
	if found and found:IsA("Folder") then
		folder = found
		return found
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	folder = f
	return f
end

-- Mesure et applique les tailles de la plaque (px TV) puis du BillboardGui (pixels d'écran)
local function layoutEntry(e: Entry)
	local glyphW = 0
	local g = e.glyph
	if g and g:shown() then
		glyphW = math.max(e.glyphSize, g.frame.Size.X.Offset)
	end
	-- largeur estimée (Util.textEm) avec 15 % de marge : l'estimation par classe de caractère sous-estime
	-- jusqu'à 12 % les mots courts aux lettres larges de FredokaOne (« Off », « Attraper » : 3 px de
	-- débord à 40 px, outil d'écrans) ; le texte est en taille fixe, il ne rétrécit pas
	local textW = if e.text ~= "" then math.ceil(Util.textEm(e.text) * e.textSize * TEXT_MARGIN) else 0
	local gap = if glyphW > 0 and textW > 0 then GAP else 0
	local h = math.max(e.textSize * 1.25, if glyphW > 0 then e.glyphSize else 0) + 2 * PAD_Y
	local w = math.max(MIN_WIDTH, glyphW + gap + textW + 2 * PAD_X)
	e.w, e.h = w, h
	e.plate.Size = UDim2.fromOffset(w, h)
	if g then
		g.frame.Position = UDim2.fromOffset(PAD_X, h / 2)
	end
	e.label.Position = UDim2.fromOffset(PAD_X + glyphW + gap, 0)
	e.label.Size = UDim2.new(0, textW + 4, 1, 0)
	e.label.TextSize = e.textSize
	e.label.Visible = e.text ~= ""
	local s = currentScale()
	e.scale.Scale = s
	e.gui.Size = UDim2.fromOffset(math.ceil(w * s), math.ceil(h * s))
end

local function watchViewport()
	if watching then
		return
	end
	watching = true
	local function hook()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				WorldText.rescale()
			end)
		end
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hook()
		WorldText.rescale()
	end)
	hook()
end

local function build(kind: Kind): Entry
	serial += 1
	local gui = Instance.new("BillboardGui")
	gui.Name = "WorldText" .. serial
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.zero
	plate.Position = UDim2.fromOffset(0, 0)
	plate.BackgroundColor3 = Theme.Colors.Stroke
	plate.BackgroundTransparency = Layout.WorldText.Background
	plate.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Layout.Corner.Min)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(30, 25, 60)
	stroke.Thickness = Layout.Stroke
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = plate
	local scale = Instance.new("UIScale")
	scale.Name = "WorldScale"
	scale.Scale = 1
	scale.Parent = plate
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Title
	label.TextColor3 = Theme.Colors.Text
	label.TextScaled = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AutoLocalize = false
	label.Text = ""
	label.ZIndex = 3
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Theme.Colors.Stroke
	textStroke.Thickness = Layout.Stroke
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = label
	label.Parent = plate
	plate.Parent = gui
	local e: Entry = {
		gui = gui,
		plate = plate,
		label = label,
		scale = scale,
		kind = kind,
		text = "",
		textSize = textSizeOf(kind),
		glyph = nil,
		glyphSize = Layout.WorldText.Glyph,
		w = MIN_WIDTH,
		h = 0,
		watch = nil,
	}
	gui.Destroying:Connect(function()
		-- détruite au lieu d'être rendue (ou dossier vidé) : ni vivante ni réutilisée
		live[gui] = nil
		local w = e.watch
		e.watch = nil
		if w then
			w:Disconnect()
		end
		local list = pool[kind]
		for i = #list, 1, -1 do
			if list[i] == e then
				table.remove(list, i)
			end
		end
	end)
	return e
end

-- =============================================================================================
-- API
-- =============================================================================================

-- BillboardGui en Offset × UIScale, LightInfluence 0, fond foncé translucide, accroché à `adornee`
function WorldText.create(adornee: Instance, options: Options): BillboardGui
	local opts: any = if type(options) == "table" then options else {}
	local kind = kindOf(opts.kind)
	watchViewport()
	local list = pool[kind]
	local e: Entry
	if #list > 0 then
		e = table.remove(list) :: Entry
	else
		e = build(kind)
	end
	local gui = e.gui
	if type(opts.name) == "string" and opts.name ~= "" then
		gui.Name = opts.name
	end
	gui.Adornee = if typeof(adornee) == "Instance" then adornee else nil
	if e.watch then
		(e.watch :: RBXScriptConnection):Disconnect()
		e.watch = nil
	end
	if typeof(adornee) == "Instance" then
		-- l'appelant détruit l'objet sans release (dalle retirée, « +N » fini, ranch remis à zéro) :
		-- l'étiquette revient quand même à la réserve (aucune fuite sur une longue session)
		local owner = adornee
		e.watch = owner.Destroying:Connect(function()
			if live[gui] == e and gui.Adornee == owner then
				WorldText.release(gui)
			end
		end)
	end
	gui.MaxDistance = Util.num(opts.maxDistance, Layout.WorldText.TestDistance, 1, 10000)
	gui.StudsOffsetWorldSpace = if typeof(opts.studsOffset) == "Vector3"
		then opts.studsOffset
		else Vector3.zero
	gui.SizeOffset = Vector2.zero
	gui.AlwaysOnTop = opts.alwaysOnTop == true
	gui.Enabled = true
	e.text = ""
	e.label.Text = ""
	e.label.TextTransparency = 0
	e.plate.BackgroundTransparency = Layout.WorldText.Background
	e.textSize = textSizeOf(kind)
	if e.glyph then
		e.glyph:destroy()
		e.glyph = nil
	end
	e.glyphSize = Layout.WorldText.Glyph
	live[gui] = e
	layoutEntry(e)
	gui.Parent = getFolder()
	return gui
end

-- Texte affiché (déjà traduit par Prefs.t ; nombres par Logic/BigNumber)
function WorldText.setText(gui: BillboardGui, text: string)
	local e = live[gui]
	if e == nil then
		return
	end
	local value = if type(text) == "string" then text else ""
	if #value > 200 then
		value = string.sub(value, 1, 200)
	end
	if value == e.text then
		return
	end
	e.text = value
	e.label.Text = value
	layoutEntry(e)
end

-- Glyphe de touche posé à gauche du mot (invites, leçon de l'accueil) ; nil : retiré. `size` en px TV
-- (au moins Layout.WorldText.Glyph = 48 ; 64 pour l'invite principale)
function WorldText.setGlyph(gui: BillboardGui, binding: Glyph.Binding?, size: number?)
	local e = live[gui]
	if e == nil then
		return
	end
	if binding == nil then
		if e.glyph then
			e.glyph:destroy()
			e.glyph = nil
			layoutEntry(e)
		end
		return
	end
	local px = math.max(Layout.WorldText.Glyph, Util.num(size, Layout.WorldText.Glyph, 0, 256))
	if e.glyph and e.glyphSize == px then
		e.glyph:set(binding)
	else
		if e.glyph then
			e.glyph:destroy()
		end
		e.glyphSize = px
		e.glyph = Glyph.new(e.plate, binding, {
			name = "Glyph",
			size = px,
			anchor = Vector2.new(0, 0.5),
			zIndex = 4,
		})
	end
	layoutEntry(e)
end

-- Taille du mot en px TV (au moins la taille de la sorte : jamais sous 32, ni 40 pour « +N »)
function WorldText.setTextSize(gui: BillboardGui, px: number)
	local e = live[gui]
	if e == nil then
		return
	end
	local size = math.max(textSizeOf(e.kind), Util.num(px, e.textSize, 0, 256))
	if size ~= e.textSize then
		e.textSize = size
		layoutEntry(e)
	end
end

-- Atténue l'étiquette (cible en recharge…) sans jamais passer sous le contraste minimal du fond
function WorldText.setDim(gui: BillboardGui, dim: boolean)
	local e = live[gui]
	if e == nil then
		return
	end
	e.label.TextTransparency = if dim then 0.35 else 0
end

-- Taille en px TV d'une sorte de texte (32, 40 ou 48)
function WorldText.pixelSize(kind: Kind): number
	if kind == "plus" then
		return Layout.WorldText.Plus
	elseif kind == "glyph" then
		return Layout.WorldText.Glyph
	end
	return Layout.WorldText.Text
end

-- Taille du texte projetée à l'écran, en px TV (écran de `viewport` pixels) : plus petit élément à
-- lire de l'étiquette (mot, sinon glyphe), en pixels d'écran ramenés à l'unité TV de cet écran. Une
-- étiquette en Offset garde sa taille quelle que soit la distance (dont 20 studs) ; une étiquette
-- dont l'échelle n'a pas suivi un changement d'écran est mesurée à sa vraie taille (specs).
function WorldText.projectedPx(gui: BillboardGui, viewport: Vector2): number
	local e = live[gui]
	if e == nil then
		return 0
	end
	local vp = if typeof(viewport) == "Vector2" then viewport else Vector2.new(1920, 1080)
	local screenScale = Platform.uiScale(vp)
	if screenScale <= 0 then
		return 0
	end
	-- pixels d'écran par px TV de la plaque : taille réelle du BillboardGui / taille de la plaque
	local k = if e.w > 0 then gui.Size.X.Offset / e.w else e.scale.Scale
	local readable = math.huge
	if e.text ~= "" then
		readable = math.min(readable, e.textSize)
	end
	if e.glyph and e.glyph:shown() then
		readable = math.min(readable, e.glyphSize)
	end
	if readable == math.huge then
		readable = e.textSize
	end
	return readable * k / screenScale
end

-- Coin haut gauche d'une plaque de `size` pixels ramené dans la zone sûre de 5 % (invites)
function WorldText.clampToSafe(screen: Vector2, size: Vector2, viewport: Vector2): Vector2
	local vp = if typeof(viewport) == "Vector2" then viewport else Vector2.new(1920, 1080)
	local sz = if typeof(size) == "Vector2" then size else Vector2.zero
	local pos = if typeof(screen) == "Vector2" then screen else Vector2.zero
	local mx = vp.X * Layout.SafeMargin
	local my = vp.Y * Layout.SafeMargin
	local x0, x1 = mx, vp.X - mx - math.max(0, sz.X)
	local y0, y1 = my, vp.Y - my - math.max(0, sz.Y)
	local x = Util.num(pos.X, x0)
	local y = Util.num(pos.Y, y0)
	-- plaque plus grande que la zone : centrée dans la zone
	x = if x1 < x0 then (x0 + x1) / 2 else math.clamp(x, x0, x1)
	y = if y1 < y0 then (y0 + y1) / 2 else math.clamp(y, y0, y1)
	return Vector2.new(x, y)
end

-- Réapplique l'échelle à toutes les étiquettes vivantes (résolution changée)
function WorldText.rescale()
	for gui, e in live do
		if gui.Parent ~= nil then
			layoutEntry(e)
		end
	end
end

-- Rend l'étiquette à la réserve
function WorldText.release(gui: BillboardGui)
	local e = live[gui]
	if e == nil then
		return
	end
	live[gui] = nil
	local w = e.watch
	e.watch = nil
	if w then
		w:Disconnect()
	end
	if e.glyph then
		e.glyph:destroy()
		e.glyph = nil
	end
	gui.Enabled = false
	gui.Adornee = nil
	local list = pool[e.kind]
	if #list >= POOL_MAX then
		gui:Destroy()
		return
	end
	gui.Parent = getFolder()
	table.insert(list, e)
end

-- Taille de la plaque en px TV (specs, bornage des invites)
function WorldText.plateSize(gui: BillboardGui): Vector2
	local e = live[gui]
	if e == nil then
		return Vector2.zero
	end
	return Vector2.new(e.w, e.h)
end

-- Étiquettes vivantes et en réserve (specs de budget)
function WorldText.stats(): { live: number, pooled: number }
	local n = 0
	for _ in live do
		n += 1
	end
	return { live = n, pooled = #pool.text + #pool.plus + #pool.glyph }
end

return WorldText
