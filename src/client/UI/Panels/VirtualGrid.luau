--!strict
-- Panels/VirtualGrid — paquet « client-panels » : grille VIRTUALISÉE (GDD §10.3 « seules les
-- cases visibles existent »). Une réserve fixe de cases (rangées visibles, plus une rangée de marge
-- au-dessus et au-dessous, × colonnes) est réaffectée aux index visibles quand on fait défiler ;
-- 600 Nebbies coûtent autant que 20.
--   local grid = VirtualGrid.new({ parent = body, cell = Vector2.new(88, 104), gap = 8,
--       create = function(cell) … end, bind = function(cell, index) … end,
--       selectable = function(cell) return cell.Hit end })
--   grid:setCount(#uids)   grid:refresh()   grid:reveal(index)   grid:destroy()
-- Les tailles sont en pixels de référence (avant UIScale) : l'échelle réelle est mesurée avec une
-- sonde de 100 px (Root applique un UIScale commun à tout l'écran).
-- Manette (docs/07-console-ps5.md §7, A19) :
--   * la sélection suit l'INDEX : quand les cases sont réaffectées (défilement, nouveau nombre),
--     GuiService.SelectedObject passe sur la case qui montre le même index (même Nebby à l'écran) ;
--     index sorti de la réserve (stick droit) : rangée entièrement visible la plus proche, même
--     colonne ; plus de Nebbies : le dernier
--   * une case sélectionnée par la navigation (croix, stick gauche) et pas entièrement visible est
--     amenée à l'écran par le plus petit défilement : la croix ↓ sur la dernière rangée visible
--     sélectionne la rangée de réserve du dessous et fait défiler d'une rangée (idem ↑ en haut) ;
--     tous les Nebbies sont donc atteignables à la croix

local GuiService = game:GetService("GuiService")

local Client = script.Parent.Parent.Parent
local Create = require(Client.UI.Create)

local VirtualGrid = {}
VirtualGrid.__index = VirtualGrid

export type Options = {
	name: string?,
	parent: Instance,
	cell: Vector2, -- taille d'une case (px de référence)
	gap: number?,
	size: UDim2?,
	position: UDim2?,
	create: (cell: Frame) -> (),
	bind: (cell: Frame, index: number) -> (),
	-- objet sélectionnable d'une case (défaut : la case elle-même)
	selectable: ((cell: Frame) -> GuiObject?)?,
}

export type VirtualGrid = typeof(setmetatable(
	{} :: {
		scroll: ScrollingFrame,
		_probe: Frame,
		_cell: Vector2,
		_gap: number,
		_create: (Frame) -> (),
		_bind: (Frame, number) -> (),
		_selectable: ((Frame) -> GuiObject?)?,
		_pool: { Frame },
		_active: number, -- cases de la réserve utilisées (les autres restent masquées)
		_count: number,
		_columns: number,
		_followed: GuiObject?, -- sélection posée par la grille elle-même (pas une navigation)
		_connections: { RBXScriptConnection },
	},
	VirtualGrid
))

local PROBE = 100
-- rangées de réserve gardées au-dessus de la première rangée visible et au-dessous de la dernière :
-- la navigation à la croix y trouve toujours la case suivante
local MARGIN_ROWS = 1

function VirtualGrid.new(o: Options): VirtualGrid
	local scroll = Create("ScrollingFrame", {
		Name = o.name or "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = o.size or UDim2.fromScale(1, 1),
		Position = o.position or UDim2.new(),
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Selectable = false,
		Parent = o.parent,
	}) :: ScrollingFrame
	local probe = Create("Frame", {
		Name = "Probe",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PROBE, PROBE),
		Visible = true,
		Parent = scroll,
	}) :: Frame
	local self = setmetatable({
		scroll = scroll,
		_probe = probe,
		_cell = o.cell,
		_gap = o.gap or 8,
		_create = o.create,
		_bind = o.bind,
		_selectable = o.selectable,
		_pool = {},
		_active = 0,
		_count = 0,
		_columns = 1,
		_followed = nil,
		_connections = {},
	}, VirtualGrid)
	table.insert(
		self._connections,
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self:refresh()
		end)
	)
	table.insert(
		self._connections,
		scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_layout()
		end)
	)
	-- la sonde peut être mesurée après le cadre défilant : échelle (donc colonnes) recalculée
	table.insert(
		self._connections,
		probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_layout()
		end)
	)
	table.insert(
		self._connections,
		GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			self:_onSelection()
		end)
	)
	return self
end

-- Échelle réelle (UIScale des ancêtres)
function VirtualGrid._scale(self: VirtualGrid): number
	local measured = self._probe.AbsoluteSize.X
	if type(measured) ~= "number" or measured <= 0 then
		return 1
	end
	return measured / PROBE
end

function VirtualGrid._viewport(self: VirtualGrid): Vector2
	local scale = self:_scale()
	local size = self.scroll.AbsoluteSize
	return Vector2.new(math.max(size.X / scale, self._cell.X), math.max(size.Y / scale, self._cell.Y))
end

-- Défilement vertical courant (px de référence)
function VirtualGrid._offset(self: VirtualGrid): number
	local canvas = self.scroll.CanvasPosition
	return if canvas then canvas.Y / self:_scale() else 0
end

function VirtualGrid._layout(self: VirtualGrid)
	local view = self:_viewport()
	local stepX = self._cell.X + self._gap
	local stepY = self._cell.Y + self._gap
	self._columns = math.max(1, math.floor((view.X - 6 + self._gap) / stepX))
	local rows = math.ceil(self._count / self._columns)
	self.scroll.CanvasSize = UDim2.fromOffset(0, math.max(0, rows * stepY - self._gap))
	-- réserve : rangées visibles au plus (même partiellement) + les rangées de marge, × colonnes,
	-- jamais plus que nécessaire
	local visibleRows = math.floor((view.Y + self._cell.Y) / stepY) + 1
	local wanted = math.min(self._count, (visibleRows + 2 * MARGIN_ROWS) * self._columns)
	self._active = wanted
	while #self._pool < wanted do
		local cell = Create("Frame", {
			Name = "Cell",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(self._cell.X, self._cell.Y),
			Visible = false,
			Parent = self.scroll,
		}) :: Frame
		self._create(cell)
		table.insert(self._pool, cell)
	end
	self:refresh()
end

function VirtualGrid.setCount(self: VirtualGrid, n: number)
	self._count = math.max(0, math.floor(n))
	self:_layout()
end

-- Case de la réserve qui contient la sélection manette (et l'objet sélectionné), sinon nil
function VirtualGrid._selected(self: VirtualGrid): (Frame?, GuiObject?)
	local ok, selected = pcall(function()
		return GuiService.SelectedObject
	end)
	if not ok or selected == nil then
		return nil, nil
	end
	for _, cell in self._pool do
		if selected == cell or selected:IsDescendantOf(cell) then
			return cell, selected
		end
	end
	return nil, nil
end

-- Objet à sélectionner dans une case (l'équivalent de `previous` dans son ancienne case)
function VirtualGrid._targetIn(self: VirtualGrid, cell: Frame, previous: GuiObject?): GuiObject?
	local fn = self._selectable
	if fn then
		return fn(cell)
	end
	if previous ~= nil and previous ~= cell then
		local same = cell:FindFirstChild(previous.Name, true)
		if same and same:IsA("GuiObject") then
			return same
		end
	end
	return cell
end

function VirtualGrid._cellFor(self: VirtualGrid, index: number): Frame?
	for _, cell in self._pool do
		if cell.Visible and cell:GetAttribute("Index") == index then
			return cell
		end
	end
	return nil
end

-- Rangées au moins en partie visibles (1 px de référence au moins) : première, dernière
function VirtualGrid._shownRows(self: VirtualGrid): (number, number)
	local stepY = self._cell.Y + self._gap
	local offset = self:_offset()
	local view = self:_viewport()
	local lo = math.max(0, math.floor((offset - self._cell.Y + 1) / stepY) + 1)
	local hi = math.ceil((offset + view.Y - 1) / stepY) - 1
	return lo, math.max(lo, hi)
end

-- Rangées entièrement visibles (première, dernière)
function VirtualGrid._visibleRows(self: VirtualGrid): (number, number)
	local stepY = self._cell.Y + self._gap
	local offset = self:_offset()
	local view = self:_viewport()
	local lo = math.ceil(offset / stepY - 1e-3)
	local hi = math.floor((offset + view.Y + self._gap) / stepY + 1e-3) - 1
	if hi < lo then
		lo = math.max(0, math.floor(offset / stepY))
		hi = lo
	end
	return lo, hi
end

-- Après réaffectation : la sélection reste sur le même index (A19)
function VirtualGrid._follow(self: VirtualGrid, index: number, previous: GuiObject?)
	local count = self._count
	if count <= 0 then
		return
	end
	local target = math.clamp(index, 1, count)
	local columns = self._columns
	local row = (target - 1) // columns
	local shownLo, shownHi = self:_shownRows()
	if row < shownLo or row > shownHi then
		-- index sorti de l'écran (stick droit, liste raccourcie) : rangée entièrement visible la
		-- plus proche, même colonne (jamais une rangée de marge cachée)
		local lo, hi = self:_visibleRows()
		row = math.clamp(row, lo, hi)
		target = math.clamp(row * columns + (target - 1) % columns + 1, 1, count)
	end
	local cell = self:_cellFor(target)
	if cell == nil then
		return
	end
	local object = self:_targetIn(cell, previous)
	if object ~= nil and object ~= previous then
		self._followed = object
		GuiService.SelectedObject = object
	end
end

-- Réaffecte les cases aux index visibles et les remplit (bind)
function VirtualGrid.refresh(self: VirtualGrid)
	local stepX = self._cell.X + self._gap
	local stepY = self._cell.Y + self._gap
	-- première rangée visible (même partiellement), moins la marge
	local firstVisible = math.floor((self:_offset() - self._cell.Y) / stepY) + 1
	local firstRow = math.max(0, firstVisible - MARGIN_ROWS)
	local first = firstRow * self._columns + 1
	local selectedCell, selectedObject = self:_selected()
	local selectedIndex = if selectedCell then selectedCell:GetAttribute("Index") else nil
	for i, cell in self._pool do
		local index = first + i - 1
		if i <= self._active and index <= self._count then
			local col = (index - 1) % self._columns
			local row = (index - 1) // self._columns
			cell.Position = UDim2.fromOffset(col * stepX, row * stepY)
			cell.Visible = true
			cell:SetAttribute("Index", index)
			self._bind(cell, index)
		else
			cell.Visible = false
			cell:SetAttribute("Index", 0)
		end
	end
	if type(selectedIndex) == "number" and selectedIndex > 0 then
		self:_follow(selectedIndex, selectedObject)
	end
end

-- Fait défiler le moins possible pour montrer entièrement la rangée de l'index (manette)
function VirtualGrid.reveal(self: VirtualGrid, index: number)
	local stepY = self._cell.Y + self._gap
	local row = (math.max(1, index) - 1) // self._columns
	local top = row * stepY
	local bottom = top + self._cell.Y
	local view = self:_viewport()
	local offset = self:_offset()
	local wanted = offset
	if top < offset then
		wanted = top
	elseif bottom > offset + view.Y then
		wanted = bottom - view.Y
	end
	local rows = math.ceil(self._count / self._columns)
	wanted = math.clamp(wanted, 0, math.max(0, rows * stepY - self._gap - view.Y))
	if math.abs(wanted - offset) > 0.5 then
		local canvas = self.scroll.CanvasPosition
		self.scroll.CanvasPosition = Vector2.new(if canvas then canvas.X else 0, wanted * self:_scale())
		-- réaffectation tout de suite (le signal CanvasPosition peut être différé)
		self:refresh()
	end
end

-- Sélection déplacée par la navigation (croix, stick gauche) sur une case pas entièrement visible
function VirtualGrid._onSelection(self: VirtualGrid)
	local cell, object = self:_selected()
	local followed = self._followed
	self._followed = nil
	if cell == nil or object == followed then
		return
	end
	local index = cell:GetAttribute("Index")
	if type(index) == "number" and index > 0 then
		self:reveal(index)
	end
end

-- Cases existantes (tests, sélection manette)
function VirtualGrid.cells(self: VirtualGrid): { Frame }
	return self._pool
end

function VirtualGrid.count(self: VirtualGrid): number
	return self._count
end

-- Fait défiler pour montrer l'index en haut (manette)
function VirtualGrid.scrollTo(self: VirtualGrid, index: number)
	local row = (math.max(1, index) - 1) // self._columns
	local stepY = self._cell.Y + self._gap
	self.scroll.CanvasPosition = Vector2.new(0, row * stepY * self:_scale())
end

function VirtualGrid.destroy(self: VirtualGrid)
	for _, c in self._connections do
		c:Disconnect()
	end
	self.scroll:Destroy()
end

return VirtualGrid
