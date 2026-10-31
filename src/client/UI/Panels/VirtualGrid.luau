--!strict
-- Panels/VirtualGrid — paquet « client-panels » : grille VIRTUALISÉE (GDD §10.3 « seules les
-- cases visibles existent »). Une réserve fixe de cases (lignes visibles + 1, × colonnes) est
-- réaffectée aux index visibles quand on fait défiler ; 600 Nebbies coûtent autant que 20.
--   local grid = VirtualGrid.new({ parent = body, cell = Vector2.new(88, 104), gap = 8,
--       create = function(cell) … end, bind = function(cell, index) … end })
--   grid:setCount(#uids)   grid:refresh()   grid:destroy()
-- Les tailles sont en pixels de référence (avant UIScale) : l'échelle réelle est mesurée avec une
-- sonde de 100 px (Root applique un UIScale commun à tout l'écran).

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
}

export type VirtualGrid = typeof(setmetatable(
	{} :: {
		scroll: ScrollingFrame,
		_probe: Frame,
		_cell: Vector2,
		_gap: number,
		_create: (Frame) -> (),
		_bind: (Frame, number) -> (),
		_pool: { Frame },
		_count: number,
		_columns: number,
		_connections: { RBXScriptConnection },
	},
	VirtualGrid
))

local PROBE = 100

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
		_pool = {},
		_count = 0,
		_columns = 1,
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

function VirtualGrid._layout(self: VirtualGrid)
	local view = self:_viewport()
	local stepX = self._cell.X + self._gap
	local stepY = self._cell.Y + self._gap
	self._columns = math.max(1, math.floor((view.X - 6 + self._gap) / stepX))
	local rows = math.ceil(self._count / self._columns)
	self.scroll.CanvasSize = UDim2.fromOffset(0, math.max(0, rows * stepY - self._gap))
	-- réserve : lignes visibles + 1 (défilement partiel) × colonnes, jamais plus que nécessaire
	local visibleRows = math.ceil(view.Y / stepY) + 1
	local wanted = math.min(self._count, visibleRows * self._columns)
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

-- Réaffecte les cases aux index visibles et les remplit (bind)
function VirtualGrid.refresh(self: VirtualGrid)
	local stepX = self._cell.X + self._gap
	local stepY = self._cell.Y + self._gap
	local canvas = self.scroll.CanvasPosition
	local offsetY = if canvas then canvas.Y / self:_scale() else 0
	local firstRow = math.max(0, math.floor(offsetY / stepY))
	local first = firstRow * self._columns + 1
	for i, cell in self._pool do
		local index = first + i - 1
		if index <= self._count then
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
end

-- Cases existantes (tests, sélection manette)
function VirtualGrid.cells(self: VirtualGrid): { Frame }
	return self._pool
end

function VirtualGrid.count(self: VirtualGrid): number
	return self._count
end

-- Fait défiler pour montrer l'index (manette)
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
