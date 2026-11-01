--!nocheck
-- Mise en page et navigation manette SIMULÉES (approximation du moteur Roblox) pour les specs
-- console (docs/07-console-ps5.md §10). Le harnais ne calcule aucune géométrie : AbsoluteSize vaut
-- 100 × 100 partout. Layout.apply(h) calcule les rectangles de toutes les interfaces visibles de
-- PlayerGui à partir de Size / Position / AnchorPoint, UIPadding, UIScale (cumulés),
-- UISizeConstraint, UIAspectRatioConstraint, UIListLayout, UIGridLayout, ScrollingFrame
-- (CanvasPosition, CanvasSize) et AutomaticSize des conteneurs à liste, puis écrit
-- AbsolutePosition / AbsoluteSize (les connexions du jeu sont donc prévenues, comme dans Roblox).
-- Convention de Roblox : AbsolutePosition est dans UN SEUL espace pour tous les écrans, dont
-- l'origine est sous la barre Roblox (GUI_INSET) : un cadre en haut d'un écran IgnoreGuiInset lit
-- Y = −GUI_INSET (ScreenFX.guiCenter et les écarts entre écrans s'appuient dessus).
--
-- Navigation : Layout.step reproduit la sélection directionnelle de Roblox — NextSelection* explicite
-- d'abord, sinon l'objet sélectionnable le plus proche dans la direction (distance le long de l'axe
-- + 2 × écart latéral), d'abord dans le SelectionGroup le plus proche, puis au-dehors si son
-- SelectionBehavior<Direction> vaut Escape (défaut), jamais s'il vaut Stop.
--
--   Layout.apply(h)
--   Layout.reachable(h, start)          → { [GuiObject]: true }
--   Layout.unreachable(h, root, start)  → objets sélectionnables de root jamais atteints
--   Layout.escapes(h, root, start)      → objets atteints HORS de root (fuite de la sélection)
--
-- Approximations assumées : pas de mesure du texte (AutomaticSize des textes, TextScaled), pas de
-- UIFlexItem, pas de rotation ; la fonction de score n'est pas celle, non documentée, de Roblox.
--
-- Mode fidèle (outils d'écrans, tools/screens et tests/harness/TextFit) :
--   Layout.apply(h, { fidelity = true, measureText = TextFit.measureAuto })
-- ajoute les tailles automatiques IMBRIQUÉES (un cadre AutomaticSize dans une liste pousse les
-- suivants, un cadre AutomaticSize grandit avec ses enfants AutomaticSize) et l'AutomaticSize des
-- textes (mesurés par measureText(obj, largeurMax) → largeur, hauteur). Sans options, rien ne
-- change pour les specs existantes.
--   Layout.applyRoot(root, w, h, opts) : même calcul pour une interface hors de PlayerGui
-- (BillboardGui à sa taille en pixels), origine (0, 0).

local roblox = require("@lune/roblox")

local Vector2 = roblox.Vector2
local Enum = roblox.Enum

local Layout = {}

Layout.GUI_INSET = 58 -- px : barre Roblox (GuiService:GetGuiInset simulé)

-- rects[obj] = { x, y, w, h (px d'écran), k (px d'écran par px de mise en page), clip, gui }
local rects = setmetatable({}, { __mode = "k" })

-- options du mode fidèle pendant un Layout.apply (nil : comportement historique)
local fidelity = nil

local DIRECTIONS = {
	Up = Vector2.new(0, -1),
	Down = Vector2.new(0, 1),
	Left = Vector2.new(-1, 0),
	Right = Vector2.new(1, 0),
}
Layout.DIRECTIONS = DIRECTIONS

-- Outils ----------------------------------------------------------------------------------------

local function udim2(size, pw, ph)
	if size == nil then
		return pw, ph
	end
	return pw * size.X.Scale + size.X.Offset, ph * size.Y.Scale + size.Y.Offset
end

local function udim(value, dim)
	if value == nil then
		return 0
	end
	return dim * value.Scale + value.Offset
end

local function childOfClass(obj, className)
	for _, c in obj:GetChildren() do
		if c.ClassName == className then
			return c
		end
	end
	return nil
end

local function constrain(obj, w, h)
	local sc = childOfClass(obj, "UISizeConstraint")
	if sc then
		local mn = sc.MinSize or Vector2.zero
		local mx = sc.MaxSize or Vector2.new(math.huge, math.huge)
		w = math.clamp(w, mn.X, math.max(mn.X, mx.X))
		h = math.clamp(h, mn.Y, math.max(mn.Y, mx.Y))
	end
	local ar = childOfClass(obj, "UIAspectRatioConstraint")
	if ar then
		local ratio = ar.AspectRatio or 1
		if ratio > 0 then
			if ar.AspectType == Enum.AspectType.ScaleWithParentSize then
				if ar.DominantAxis == Enum.DominantAxis.Height then
					w = h * ratio
				else
					h = w / ratio
				end
			elseif w / math.max(h, 1e-6) > ratio then
				w = h * ratio
			else
				h = w / ratio
			end
		end
	end
	return math.max(w, 0), math.max(h, 0)
end

local function paddingOf(obj, w, h)
	local p = childOfClass(obj, "UIPadding")
	if p == nil then
		return 0, 0, 0, 0
	end
	return udim(p.PaddingLeft, w), udim(p.PaddingTop, h), udim(p.PaddingRight, w), udim(p.PaddingBottom, h)
end

local function guiChildren(obj)
	local out = {}
	for _, c in obj:GetChildren() do
		if c:IsA("GuiObject") and c.Visible ~= false then
			table.insert(out, c)
		end
	end
	return out
end

local function sorted(kids, layout)
	local indexed = {}
	for i, k in kids do
		indexed[i] = { kid = k, i = i }
	end
	local byName = layout.SortOrder == Enum.SortOrder.Name
	table.sort(indexed, function(a, b)
		if byName then
			if a.kid.Name ~= b.kid.Name then
				return a.kid.Name < b.kid.Name
			end
		else
			local la, lb = a.kid.LayoutOrder or 0, b.kid.LayoutOrder or 0
			if la ~= lb then
				return la < lb
			end
		end
		return a.i < b.i
	end)
	local out = {}
	for i, e in indexed do
		out[i] = e.kid
	end
	return out
end

local function intersect(a, b)
	if a == nil then
		return b
	end
	if b == nil then
		return a
	end
	local x0, y0 = math.max(a.x, b.x), math.max(a.y, b.y)
	local x1, y1 = math.min(a.x + a.w, b.x + b.w), math.min(a.y + a.h, b.y + b.h)
	return { x = x0, y = y0, w = math.max(0, x1 - x0), h = math.max(0, y1 - y0) }
end

-- Dispositions -----------------------------------------------------------------------------------

local autoSizeOf -- (obj, w, h) → w, h : taille automatique (mode fidèle), définie plus bas

local function listSlots(layout, kids, cx, cy, cw, ch)
	local slots = {}
	local vertical = layout.FillDirection ~= Enum.FillDirection.Horizontal
	local gap = udim(layout.Padding, if vertical then ch else cw)
	local list = sorted(kids, layout)
	local total = 0
	for i, kid in list do
		local w, h = constrain(kid, udim2(kid.Size, cw, ch))
		if fidelity then
			w, h = autoSizeOf(kid, w, h)
		end
		slots[kid] = { w = w, h = h }
		total += (if vertical then h else w) + (if i > 1 then gap else 0)
	end
	local along
	if vertical then
		local a = layout.VerticalAlignment
		along = if a == Enum.VerticalAlignment.Center
			then cy + (ch - total) / 2
			elseif a == Enum.VerticalAlignment.Bottom then cy + ch - total
			else cy
	else
		local a = layout.HorizontalAlignment
		along = if a == Enum.HorizontalAlignment.Center
			then cx + (cw - total) / 2
			elseif a == Enum.HorizontalAlignment.Right then cx + cw - total
			else cx
	end
	for _, kid in list do
		local s = slots[kid]
		if vertical then
			local a = layout.HorizontalAlignment
			s.x = if a == Enum.HorizontalAlignment.Center
				then cx + (cw - s.w) / 2
				elseif a == Enum.HorizontalAlignment.Right then cx + cw - s.w
				else cx
			s.y = along
			along += s.h + gap
		else
			local a = layout.VerticalAlignment
			s.y = if a == Enum.VerticalAlignment.Center
				then cy + (ch - s.h) / 2
				elseif a == Enum.VerticalAlignment.Bottom then cy + ch - s.h
				else cy
			s.x = along
			along += s.w + gap
		end
	end
	return slots, total
end

local function gridSlots(layout, kids, cx, cy, cw, ch)
	local slots = {}
	local cellW, cellH = udim2(layout.CellSize or roblox.UDim2.fromOffset(100, 100), cw, ch)
	local padX, padY = udim2(layout.CellPadding or roblox.UDim2.fromOffset(5, 5), cw, ch)
	local list = sorted(kids, layout)
	local horizontal = layout.FillDirection ~= Enum.FillDirection.Vertical
	local maxCells = layout.FillDirectionMaxCells or 0
	local per
	if horizontal then
		per = math.max(1, math.floor((cw + padX) / math.max(cellW + padX, 1e-6)))
	else
		per = math.max(1, math.floor((ch + padY) / math.max(cellH + padY, 1e-6)))
	end
	if maxCells > 0 then
		per = math.min(per, maxCells)
	end
	local used = math.min(per, #list)
	local offsetX = 0
	if horizontal and layout.HorizontalAlignment == Enum.HorizontalAlignment.Center then
		offsetX = (cw - (used * cellW + math.max(0, used - 1) * padX)) / 2
	elseif horizontal and layout.HorizontalAlignment == Enum.HorizontalAlignment.Right then
		offsetX = cw - (used * cellW + math.max(0, used - 1) * padX)
	end
	local lines = 0
	for i, kid in list do
		local a, b = (i - 1) % per, (i - 1) // per
		local col, row = if horizontal then a else b, if horizontal then b else a
		slots[kid] =
			{ x = cx + offsetX + col * (cellW + padX), y = cy + row * (cellH + padY), w = cellW, h = cellH }
		lines = math.max(lines, b + 1)
	end
	local extent = if horizontal then lines * cellH + math.max(0, lines - 1) * padY else lines * cellW
	return slots, extent
end

local isTextClass = { TextLabel = true, TextButton = true, TextBox = true }

-- Taille automatique d'un conteneur à liste ou grille (le texte n'est pas mesuré)
local function autoSize(obj, w, h)
	local auto = obj.AutomaticSize
	if auto == nil or auto == Enum.AutomaticSize.None then
		return w, h
	end
	if fidelity then
		return autoSizeOf(obj, w, h)
	end
	local list = childOfClass(obj, "UIListLayout")
	local grid = childOfClass(obj, "UIGridLayout")
	local kids = guiChildren(obj)
	local pl, pt, pr, pb = paddingOf(obj, w, h)
	local extentW, extentH = 0, 0
	if list then
		local _, total = listSlots(list, kids, 0, 0, w - pl - pr, h - pt - pb)
		if list.FillDirection == Enum.FillDirection.Horizontal then
			extentW = total
		else
			extentH = total
		end
	elseif grid then
		local _, extent = gridSlots(grid, kids, 0, 0, w - pl - pr, h - pt - pb)
		extentH = extent
	else
		for _, kid in kids do
			local kw, kh = constrain(kid, udim2(kid.Size, w, h))
			extentW = math.max(extentW, (kid.Position and kid.Position.X.Offset or 0) + kw)
			extentH = math.max(extentH, (kid.Position and kid.Position.Y.Offset or 0) + kh)
		end
	end
	if auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY then
		w = math.max(w, extentW + pl + pr)
	end
	if auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY then
		h = math.max(h, extentH + pt + pb)
	end
	return w, h
end

-- Mode fidèle : tailles automatiques imbriquées et textes mesurés (Roblox les résout de bas en haut)
autoSizeOf = function(obj, w, h)
	local auto = obj.AutomaticSize
	if auto == nil or auto == Enum.AutomaticSize.None then
		return w, h
	end
	local growX = auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY
	local growY = auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY
	local pl, pt, pr, pb = paddingOf(obj, w, h)
	local innerW, innerH = w - pl - pr, h - pt - pb
	local extentW, extentH = 0, 0
	if isTextClass[obj.ClassName] and fidelity.measureText then
		local tw, th = fidelity.measureText(obj, if growX then nil else math.max(0, innerW))
		extentW, extentH = tw, th
	end
	local list = childOfClass(obj, "UIListLayout")
	local grid = childOfClass(obj, "UIGridLayout")
	local kids = guiChildren(obj)
	if list then
		local slots, total = listSlots(list, kids, 0, 0, innerW, innerH)
		local cross = 0
		for _, slot in slots do
			cross = math.max(cross, if list.FillDirection == Enum.FillDirection.Horizontal then slot.h else slot.w)
		end
		if list.FillDirection == Enum.FillDirection.Horizontal then
			extentW, extentH = math.max(extentW, total), math.max(extentH, cross)
		else
			extentW, extentH = math.max(extentW, cross), math.max(extentH, total)
		end
	elseif grid then
		local _, extent = gridSlots(grid, kids, 0, 0, innerW, innerH)
		extentH = math.max(extentH, extent)
	else
		for _, kid in kids do
			local kw, kh = constrain(kid, udim2(kid.Size, innerW, innerH))
			kw, kh = autoSizeOf(kid, kw, kh)
			local pos = kid.Position
			local anchor = kid.AnchorPoint or Vector2.zero
			local x0 = (if pos then pos.X.Offset + innerW * pos.X.Scale else 0) - anchor.X * kw
			local y0 = (if pos then pos.Y.Offset + innerH * pos.Y.Scale else 0) - anchor.Y * kh
			extentW = math.max(extentW, x0 + kw)
			extentH = math.max(extentH, y0 + kh)
		end
	end
	if growX then
		w = math.max(w, extentW + pl + pr)
	end
	if growY then
		h = math.max(h, extentH + pt + pb)
	end
	-- UISizeConstraint borne aussi la taille automatique
	local sc = childOfClass(obj, "UISizeConstraint")
	if sc then
		local mn = sc.MinSize or Vector2.zero
		local mx = sc.MaxSize or Vector2.new(math.huge, math.huge)
		w = math.clamp(w, mn.X, math.max(mn.X, mx.X))
		h = math.clamp(h, mn.Y, math.max(mn.Y, mx.Y))
	end
	return w, h
end

-- Placement récursif -----------------------------------------------------------------------------

local function setAbsolute(obj, key, value)
	local current = obj[key]
	if current ~= value then
		obj[key] = value
	end
end

local layoutChildren

-- (x, y, w, h) : rectangle de obj dans l'espace de mise en page de son parent ; T : espace de mise
-- en page → écran (sx = ox + k × x)
local function place(obj, x, y, w, h, T, gui, clip)
	local T2 = T
	local s = childOfClass(obj, "UIScale")
	if s and type(s.Scale) == "number" and s.Scale ~= 1 then
		local anchor = obj.AnchorPoint or Vector2.zero
		local ax, ay = x + anchor.X * w, y + anchor.Y * h
		T2 = {
			ox = T.ox + T.k * ax * (1 - s.Scale),
			oy = T.oy + T.k * ay * (1 - s.Scale),
			k = T.k * s.Scale,
		}
	end
	local rect = { x = T2.ox + T2.k * x, y = T2.oy + T2.k * y, w = T2.k * w, h = T2.k * h }
	rects[obj] = { x = rect.x, y = rect.y, w = rect.w, h = rect.h, k = T2.k, clip = clip, gui = gui }
	-- espace commun sous la barre Roblox, quel que soit IgnoreGuiInset de l'écran (comme Roblox)
	setAbsolute(obj, "AbsolutePosition", Vector2.new(rect.x, rect.y - Layout.GUI_INSET))
	setAbsolute(obj, "AbsoluteSize", Vector2.new(rect.w, rect.h))
	local childClip = clip
	if obj.ClassName == "ScrollingFrame" or obj.ClipsDescendants == true then
		childClip = intersect(clip, rect)
	end
	layoutChildren(obj, x, y, w, h, T2, gui, childClip)
end

layoutChildren = function(obj, x, y, w, h, T, gui, clip)
	local pl, pt, pr, pb = paddingOf(obj, w, h)
	local cx, cy, cw, ch = x + pl, y + pt, w - pl - pr, h - pt - pb
	if obj.ClassName == "ScrollingFrame" then
		local cp = obj.CanvasPosition or Vector2.zero
		local canvasW, canvasH = udim2(obj.CanvasSize, cw, ch)
		cx -= cp.X / T.k
		cy -= cp.Y / T.k
		cw, ch = math.max(cw, canvasW), math.max(ch, canvasH)
	end
	local kids = guiChildren(obj)
	local slots = nil
	local grid = childOfClass(obj, "UIGridLayout")
	local list = childOfClass(obj, "UIListLayout")
	if grid then
		slots = gridSlots(grid, kids, cx, cy, cw, ch)
	elseif list then
		slots = listSlots(list, kids, cx, cy, cw, ch)
	end
	for _, kid in kids do
		local kx, ky, kw, kh
		local slot = slots and slots[kid]
		if slot then
			kx, ky, kw, kh = slot.x, slot.y, slot.w, slot.h
			kw, kh = autoSize(kid, kw, kh)
		else
			kw, kh = constrain(kid, udim2(kid.Size, cw, ch))
			kw, kh = autoSize(kid, kw, kh)
			local pos = kid.Position
			local anchor = kid.AnchorPoint or Vector2.zero
			kx = cx + (if pos then cw * pos.X.Scale + pos.X.Offset else 0) - anchor.X * kw
			ky = cy + (if pos then ch * pos.Y.Scale + pos.Y.Offset else 0) - anchor.Y * kh
		end
		place(kid, kx, ky, kw, kh, T, gui, clip)
	end
end

-- Calcule la mise en page de toutes les interfaces activées de PlayerGui (écran h.viewport)
-- opts (facultatif) : { fidelity = true, measureText = function(obj, maxWidth) → w, h } (mode fidèle)
function Layout.apply(h, opts)
	local player = h.localPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	fidelity = if opts and opts.fidelity then opts else nil
	local camera = h.game.Workspace.CurrentCamera
	local size = (camera and camera.ViewportSize) or h.viewport
	for _, gui in playerGui:GetChildren() do
		if gui.ClassName == "ScreenGui" and gui.Enabled ~= false then
			local top = if gui.IgnoreGuiInset == true or gui.ScreenInsets == Enum.ScreenInsets.None
				then 0
				else Layout.GUI_INSET
			local info = { top = top, gui = gui }
			setAbsolute(gui, "AbsoluteSize", Vector2.new(size.X, size.Y - top))
			layoutChildren(gui, 0, top, size.X, size.Y - top, { ox = 0, oy = 0, k = 1 }, info, nil)
		end
	end
	fidelity = nil
end

-- Mise en page d'une interface quelconque (BillboardGui, SurfaceGui…) de w × h px, origine (0, 0) ;
-- mêmes options que Layout.apply. AbsolutePosition / AbsoluteSize ne sont pas écrits (interfaces du
-- monde : seul Layout.rect sert).
function Layout.applyRoot(root, w, h, opts)
	fidelity = if opts and opts.fidelity then opts else nil
	local saved = setAbsolute
	setAbsolute = function() end
	local ok, err = pcall(layoutChildren, root, 0, 0, w, h, { ox = 0, oy = 0, k = 1 }, { top = 0, gui = root }, nil)
	setAbsolute = saved
	fidelity = nil
	if not ok then
		error(err, 2)
	end
end

-- Rectangle d'écran (px) calculé par le dernier Layout.apply, ou nil
function Layout.rect(obj)
	return rects[obj]
end

-- Visible : lui et ses ancêtres GuiObject visibles, CanvasGroup non transparent, ScreenGui activé
-- dans PlayerGui
function Layout.visible(obj): boolean
	local cur = obj
	while cur ~= nil do
		if cur:IsA("GuiObject") then
			if cur.Visible == false then
				return false
			end
			if cur.ClassName == "CanvasGroup" and (cur.GroupTransparency or 0) >= 0.99 then
				return false
			end
		elseif cur:IsA("LayerCollector") then
			return cur.Enabled ~= false and cur.Parent ~= nil and cur.Parent.ClassName == "PlayerGui"
		end
		cur = cur.Parent
	end
	return false
end

function Layout.selectable(obj): boolean
	if obj == nil or not obj:IsA("GuiObject") or obj.Selectable ~= true or obj.Interactable == false then
		return false
	end
	local r = rects[obj]
	return r ~= nil and r.w > 1 and r.h > 1 and Layout.visible(obj)
end

local function descendantsOf(root)
	if root:IsA("GuiObject") or root:IsA("LayerCollector") then
		local out = root:GetDescendants()
		table.insert(out, 1, root)
		return out
	end
	return root:GetDescendants()
end

-- Objets sélectionnables sous root (défaut : tout PlayerGui)
function Layout.selectables(h, root)
	root = root or h.localPlayer:FindFirstChildOfClass("PlayerGui")
	local out = {}
	for _, d in descendantsOf(root) do
		if Layout.selectable(d) then
			table.insert(out, d)
		end
	end
	return out
end

local function center(r)
	return Vector2.new(r.x + r.w / 2, r.y + r.h / 2)
end

local function best(candidates, from, dir)
	local origin = center(rects[from])
	local winner, score = nil, math.huge
	for _, c in candidates do
		if c ~= from then
			local v = center(rects[c]) - origin
			local along = v.X * dir.X + v.Y * dir.Y
			if along > 0.5 then
				local perp = math.abs(v.X * dir.Y - v.Y * dir.X)
				local s = along + 2 * perp
				if s < score then
					winner, score = c, s
				end
			end
		end
	end
	return winner
end

-- Objet sélectionné après un appui dans la direction dir ("Up" | "Down" | "Left" | "Right"), ou nil
function Layout.step(h, from, dir: string)
	local vector = assert(DIRECTIONS[dir], "direction inconnue : " .. tostring(dir))
	local explicit = from["NextSelection" .. dir]
	if explicit ~= nil and Layout.selectable(explicit) then
		return explicit
	end
	if rects[from] == nil then
		return nil
	end
	local all = Layout.selectables(h)
	local cur = from.Parent
	while cur ~= nil and (cur:IsA("GuiObject") or cur:IsA("LayerCollector")) do
		if cur.SelectionGroup == true then
			local inside = {}
			for _, c in all do
				if c:IsDescendantOf(cur) then
					table.insert(inside, c)
				end
			end
			local found = best(inside, from, vector)
			if found then
				return found
			end
			if cur["SelectionBehavior" .. dir] == Enum.SelectionBehavior.Stop then
				return nil
			end
		end
		cur = cur.Parent
	end
	return best(all, from, vector)
end

-- Ensemble des objets atteints depuis start avec les quatre directions
function Layout.reachable(h, start)
	local seen = { [start] = true }
	local queue = { start }
	local i = 1
	while queue[i] do
		local cur = queue[i]
		i += 1
		for dir in DIRECTIONS do
			local nxt = Layout.step(h, cur, dir)
			if nxt and not seen[nxt] then
				seen[nxt] = true
				table.insert(queue, nxt)
			end
		end
	end
	return seen
end

-- Objets sélectionnables de root jamais atteints depuis start
function Layout.unreachable(h, root, start)
	local seen = Layout.reachable(h, start)
	local out = {}
	for _, obj in Layout.selectables(h, root) do
		if not seen[obj] then
			table.insert(out, obj)
		end
	end
	return out
end

-- Objets atteints depuis start qui ne sont pas dans root (la sélection « s'échappe »)
function Layout.escapes(h, root, start)
	local out = {}
	for obj in Layout.reachable(h, start) do
		if obj ~= root and not obj:IsDescendantOf(root) then
			table.insert(out, obj)
		end
	end
	return out
end

-- Nom lisible pour les messages d'échec
function Layout.name(obj): string
	local ok, full = pcall(function()
		return obj:GetFullName()
	end)
	return if ok then (string.gsub(full, "^.-PlayerGui%.", "")) else tostring(obj)
end

function Layout.names(list): string
	local out = {}
	for _, obj in list do
		table.insert(out, Layout.name(obj))
	end
	table.sort(out)
	return table.concat(out, ", ")
end

return Layout
