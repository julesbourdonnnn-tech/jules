--!nocheck
-- Instantané d'un écran pour le rendu hors moteur (tools/screens/render.mjs) : chaque GuiObject
-- VISIBLE de PlayerGui (après une mise en page fidèle, Screens.layout), et les BillboardGui du monde
-- (panneaux des Nids, étiquettes) mis en page à leur propre taille en pixels.
-- Par objet : classe, nom complet, rectangle d'écran, ZIndex, ordre parmi ses frères, écran
-- (DisplayOrder, ZIndexBehavior), rectangle de découpe hérité des ancêtres (ClipsDescendants,
-- ScrollingFrame, CanvasGroup), fond, bordure, coins (UICorner), contour (UIStroke), dégradé
-- (UIGradient), transparence de groupe, texte (police, taille, TextScaled, retours, troncature,
-- alignements, RichText, LineHeight, UITextSizeConstraint, contour du texte) avec la mesure Luau
-- (tests/harness/TextFit), image (id, teinte, transparence, ScaleType), barre de défilement ;
-- et pour l'écran : objet sélectionné (GuiService.SelectedObject et son cadre de sélection), zone
-- sûre TV, échelle de Root.
-- Les propriétés jamais écrites par le jeu prennent la valeur par défaut du VRAI moteur
-- (tests/harness/Props).

local roblox = require("@lune/roblox")
local Layout = require("./Layout")
local TextFit = require("./TextFit")
local Props = require("./Props")

local Vector2 = roblox.Vector2

local ScreenDump = {}

ScreenDump.TV_SAFE_MARGIN = 0.05 -- docs/07-console-ps5.md §4
-- Billboards : px par stud pour un panneau vu à BILLBOARD_DISTANCE studs (champ de vision 70°)
ScreenDump.BILLBOARD_DISTANCE = 24

local function rgb(c)
	if c == nil then
		return nil
	end
	return {
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5),
	}
end

local function round(x, d)
	local m = 10 ^ (d or 2)
	return math.floor(x * m + 0.5) / m
end

local function enumName(e)
	if e == nil then
		return nil
	end
	return e.Name
end

local function childOf(obj, className)
	for _, ch in obj:GetChildren() do
		if ch.ClassName == className then
			return ch
		end
	end
	return nil
end

local function enabled(inst)
	local e = Props.get(inst, "Enabled")
	return e ~= false
end

local function fontOf(face)
	if face == nil then
		return nil
	end
	return { family = face.Family, weight = enumName(face.Weight), style = enumName(face.Style) }
end

local function strokeOf(obj, k)
	local s = childOf(obj, "UIStroke")
	if s == nil or not enabled(s) then
		return nil
	end
	return {
		color = rgb(Props.get(s, "Color")),
		t = round(Props.get(s, "Transparency") or 0, 3),
		thick = round((Props.get(s, "Thickness") or 1) * k, 2),
		mode = enumName(Props.get(s, "ApplyStrokeMode")) or "Contextual",
		join = enumName(Props.get(s, "LineJoinMode")),
		pos = enumName(Props.get(s, "BorderStrokePosition")),
	}
end

local function cornerOf(obj, k)
	local cr = childOf(obj, "UICorner")
	if cr == nil then
		return nil
	end
	local r = Props.get(cr, "CornerRadius") or roblox.UDim.new(0, 8)
	return { s = r.Scale, o = r.Offset * k }
end

local function gradientOf(obj)
	local g = childOf(obj, "UIGradient")
	if g == nil or not enabled(g) then
		return nil
	end
	local colors, trans = {}, {}
	local cs = Props.get(g, "Color")
	if cs then
		for _, kp in cs.Keypoints do
			table.insert(colors, { round(kp.Time, 4), table.unpack(rgb(kp.Value)) })
		end
	end
	local ts = Props.get(g, "Transparency")
	if ts then
		for _, kp in ts.Keypoints do
			table.insert(trans, { round(kp.Time, 4), round(kp.Value, 4) })
		end
	end
	local off = Props.get(g, "Offset") or Vector2.zero
	return { colors = colors, trans = trans, rot = Props.get(g, "Rotation") or 0, off = { off.X, off.Y } }
end

local function decorative(obj)
	return TextFit.decorative(obj)
end

local function textOf(obj, k, rootScale)
	local text, placeholder = TextFit.displayText(obj)
	local raw = Props.get(obj, "Text") or ""
	local c = childOf(obj, "UITextSizeConstraint")
	local ok, d = TextFit.fits(obj, { rootScale = rootScale })
	local issues = {}
	for _, i in (d and d.issues) or {} do
		table.insert(issues, { kind = i.kind, message = i.message })
	end
	return {
		s = raw,
		shown = text,
		placeholder = placeholder,
		color = rgb(
			if placeholder then Props.get(obj, "PlaceholderColor3") or Props.get(obj, "TextColor3")
				else Props.get(obj, "TextColor3")
		),
		t = round(Props.get(obj, "TextTransparency") or 0, 3),
		font = fontOf(Props.get(obj, "FontFace")),
		key = TextFit.fontKey(Props.get(obj, "FontFace")),
		size = Props.get(obj, "TextSize"),
		scaled = Props.get(obj, "TextScaled") == true,
		wrapped = Props.get(obj, "TextWrapped") == true,
		trunc = enumName(Props.get(obj, "TextTruncate")) or "None",
		xa = enumName(Props.get(obj, "TextXAlignment")) or "Center",
		ya = enumName(Props.get(obj, "TextYAlignment")) or "Center",
		rich = Props.get(obj, "RichText") == true,
		lh = Props.get(obj, "LineHeight") or 1,
		minS = if c then Props.get(c, "MinTextSize") else nil,
		maxS = if c then Props.get(c, "MaxTextSize") else nil,
		strokeT = Props.get(obj, "TextStrokeTransparency") or 1,
		strokeColor = rgb(Props.get(obj, "TextStrokeColor3")),
		k = k,
		fit = if d
			then {
				ok = ok,
				size = d.size,
				real = round(d.realSize, 2),
				lines = d.lines,
				boxW = round(d.boxW, 2),
				boxH = round(d.boxH, 2),
				issues = issues,
			}
			else nil,
	}
end

local function imageOf(obj)
	local rectSize = Props.get(obj, "ImageRectSize")
	local rectOffset = Props.get(obj, "ImageRectOffset")
	return {
		id = tostring(Props.get(obj, "Image") or ""),
		color = rgb(Props.get(obj, "ImageColor3")),
		t = round(Props.get(obj, "ImageTransparency") or 0, 3),
		scale = enumName(Props.get(obj, "ScaleType")) or "Stretch",
		rectSize = if rectSize then { rectSize.X, rectSize.Y } else nil,
		rectOffset = if rectOffset then { rectOffset.X, rectOffset.Y } else nil,
	}
end

-- Étendue du contenu d'une liste défilante (px d'écran, depuis son coin haut gauche)
local function contentExtent(scroll, r)
	local right, bottom = r.x + r.w, r.y + r.h
	local left, top = r.x, r.y
	for _, d in scroll:GetDescendants() do
		local dr = Layout.rect(d)
		if dr ~= nil and d:IsA("GuiObject") and d.Visible ~= false then
			right = math.max(right, dr.x + dr.w)
			bottom = math.max(bottom, dr.y + dr.h)
			left = math.min(left, dr.x)
			top = math.min(top, dr.y)
		end
	end
	return right - left, bottom - top, r.x - left, r.y - top
end

local function visibleIn(obj, rootGui)
	local cur = obj
	while cur ~= nil and cur ~= rootGui do
		if cur:IsA("GuiObject") then
			if cur.Visible == false then
				return false
			end
			if cur.ClassName == "CanvasGroup" and (Props.get(cur, "GroupTransparency") or 0) >= 0.99 then
				return false
			end
		end
		cur = cur.Parent
	end
	return cur == rootGui
end

-- Noeuds d'une interface (ScreenGui ou BillboardGui) : objets visibles, parents avant enfants
local function dumpTree(gui, guiIndex, nodes, index, rootScale, isVisible, prefix)
	local function walk(parent, parentIndex)
		local kids = parent:GetChildren()
		for order, obj in kids do
			if obj:IsA("GuiObject") and isVisible(obj) then
				local r = Layout.rect(obj)
				if r ~= nil then
					local k = r.k or 1
					local node = {
						i = #nodes + 1,
						p = parentIndex,
						g = guiIndex,
						n = obj.Name,
						path = prefix .. Layout.name(obj),
						c = obj.ClassName,
						x = round(r.x, 2),
						y = round(r.y, 2),
						w = round(r.w, 2),
						h = round(r.h, 2),
						k = round(k, 4),
						z = Props.get(obj, "ZIndex") or 1,
						o = order,
						clip = if r.clip
							then { round(r.clip.x, 2), round(r.clip.y, 2), round(r.clip.w, 2), round(r.clip.h, 2) }
							else nil,
						bg = rgb(Props.get(obj, "BackgroundColor3")),
						bgt = round(Props.get(obj, "BackgroundTransparency") or 0, 3),
						bs = Props.get(obj, "BorderSizePixel") or 0,
						bc = rgb(Props.get(obj, "BorderColor3")),
						bm = enumName(Props.get(obj, "BorderMode")),
						cd = Props.get(obj, "ClipsDescendants") == true,
						rot = Props.get(obj, "Rotation") or 0,
						corner = cornerOf(obj, k),
						stroke = strokeOf(obj, k),
						grad = gradientOf(obj),
						sel = Layout.selectable(obj),
						deco = decorative(obj),
						auto = obj:GetAttribute("Decorative") == true,
					}
					if obj.ClassName == "CanvasGroup" then
						node.gt = round(Props.get(obj, "GroupTransparency") or 0, 3)
					end
					if TextFit.isText(obj) then
						node.text = textOf(obj, k, rootScale)
					end
					if obj.ClassName == "ImageLabel" or obj.ClassName == "ImageButton" then
						node.img = imageOf(obj)
					end
					if obj.ClassName == "ScrollingFrame" then
						local cw, ch, ox, oy = contentExtent(obj, r)
						local cp = Props.get(obj, "CanvasPosition") or Vector2.zero
						node.scroll = {
							thick = (Props.get(obj, "ScrollBarThickness") or 12) * k,
							color = rgb(Props.get(obj, "ScrollBarImageColor3")),
							t = Props.get(obj, "ScrollBarImageTransparency") or 0,
							contentW = round(cw, 2),
							contentH = round(ch, 2),
							offX = round(ox, 2),
							offY = round(oy, 2),
							pos = { cp.X, cp.Y },
						}
					end
					table.insert(nodes, node)
					index[obj] = node.i
					walk(obj, node.i)
				end
			end
		end
	end
	walk(gui, 0)
end

-- Cadre de sélection dessiné par le moteur sur GuiService.SelectedObject
local function selectionOf(c, index)
	local ok, selected = pcall(function()
		return c.h.game.GuiService.SelectedObject
	end)
	if not ok or selected == nil then
		return nil
	end
	local r = Layout.rect(selected)
	if r == nil or not Layout.visible(selected) then
		return { path = Layout.name(selected), hidden = true }
	end
	local out = {
		path = Layout.name(selected),
		node = index[selected],
		rect = { round(r.x, 2), round(r.y, 2), round(r.w, 2), round(r.h, 2) },
		k = r.k,
	}
	local image = selected.SelectionImageObject
	if image ~= nil then
		local size = image.Size
		out.outset = { (size.X.Offset / 2) * r.k, (size.Y.Offset / 2) * r.k }
		local stroke = image:FindFirstChildOfClass("UIStroke")
		if stroke then
			out.color = rgb(stroke.Color)
			out.thick = (stroke.Thickness or 1) * r.k
		end
		local corner = image:FindFirstChildOfClass("UICorner")
		if corner then
			out.radius = corner.CornerRadius.Offset * r.k
		end
		local edge = image:FindFirstChild("Edge")
		local edgeStroke = edge and edge:FindFirstChildOfClass("UIStroke")
		if edgeStroke then
			out.edgeColor = rgb(edgeStroke.Color)
			out.edge = (edgeStroke.Thickness or 1) * r.k
		end
	else
		out.default = true -- cadre de sélection par défaut du moteur
	end
	return out
end

-- BillboardGui du monde (et de PlayerGui) : taille en px = Offset + Scale × px par stud
local function billboards(c, rootScale, layoutOptions)
	local out = {}
	local h = c.h
	local vh = c.profile.h
	local pxPerStud = vh / (2 * ScreenDump.BILLBOARD_DISTANCE * math.tan(math.rad(35)))
	local list = {}
	for _, d in h.game.Workspace:GetDescendants() do
		if d.ClassName == "BillboardGui" then
			table.insert(list, d)
		end
	end
	for _, d in h.localPlayer.PlayerGui:GetDescendants() do
		if d.ClassName == "BillboardGui" then
			table.insert(list, d)
		end
	end
	for _, bb in list do
		if enabled(bb) then
			local size = Props.get(bb, "Size") or roblox.UDim2.new()
			local w = size.X.Offset + size.X.Scale * pxPerStud
			local hh = size.Y.Offset + size.Y.Scale * pxPerStud
			if w >= 2 and hh >= 2 then
				Layout.applyRoot(bb, w, hh, layoutOptions)
				local nodes, index = {}, {}
				dumpTree(bb, 1, nodes, index, 1, function(obj)
					return visibleIn(obj, bb)
				end, "")
				local hasContent = false
				for _, node in nodes do
					if (node.text and node.text.shown ~= "") or node.bgt < 1 or node.img then
						hasContent = true
						break
					end
				end
				if hasContent then
					table.insert(out, {
						name = bb.Name,
						path = bb:GetFullName(),
						w = round(w, 2),
						h = round(hh, 2),
						pxPerStud = round(pxPerStud, 3),
						alwaysOnTop = Props.get(bb, "AlwaysOnTop") == true,
						nodes = nodes,
					})
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.path < b.path
	end)
	return out
end

-- Instantané complet de l'écran courant (Screens.layout déjà appliqué)
-- meta : { id, error }, rootScale, layoutOptions (mode fidèle, pour les billboards)
function ScreenDump.dump(c, meta, rootScale, layoutOptions, extra)
	local h = c.h
	local profile = c.profile
	local playerGui = h.localPlayer:FindFirstChildOfClass("PlayerGui")
	local guis, nodes, index = {}, {}, {}
	local screenGuis = {}
	for order, gui in playerGui:GetChildren() do
		if gui.ClassName == "ScreenGui" and enabled(gui) then
			table.insert(screenGuis, { gui = gui, order = order })
		end
	end
	for _, entry in screenGuis do
		local gui = entry.gui
		local top = if Props.get(gui, "IgnoreGuiInset") == true
				or Props.get(gui, "ScreenInsets") == roblox.Enum.ScreenInsets.None
			then 0
			else Layout.GUI_INSET
		table.insert(guis, {
			name = gui.Name,
			displayOrder = Props.get(gui, "DisplayOrder") or 0,
			zb = enumName(Props.get(gui, "ZIndexBehavior")) or "Sibling",
			inset = top,
			order = entry.order,
		})
		dumpTree(gui, #guis, nodes, index, rootScale, function(obj)
			return Layout.visible(obj)
		end, "")
	end
	local safe = nil
	if profile.console then
		local m = ScreenDump.TV_SAFE_MARGIN
		safe = { profile.w * m, profile.h * m, profile.w * (1 - 2 * m), profile.h * (1 - 2 * m) }
	end
	local out = {
		id = meta.id,
		profile = profile.id,
		profileLabel = profile.label,
		lang = c.lang,
		state = c.state,
		viewport = { profile.w, profile.h },
		console = profile.console == true,
		touch = profile.touch == true,
		rootScale = rootScale,
		minReadable = TextFit.MIN_READABLE,
		guiInset = Layout.GUI_INSET,
		safe = safe,
		guis = guis,
		nodes = nodes,
		selected = selectionOf(c, index),
		billboards = billboards(c, rootScale, layoutOptions),
		error = meta.error,
	}
	for k, v in extra or {} do
		out[k] = v
	end
	return out
end

return ScreenDump
