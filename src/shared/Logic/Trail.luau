--!strict
-- Trail : historique de trajectoire d'un meneur, pour placer des suiveurs « en file »
-- exactement sur le chemin parcouru (comme un serpent / une conga).
--
-- Partagé : le serveur l'utilise pour l'autorité (positions des suiveurs → coupures),
-- le client pour l'affichage fluide. Logique pure, sans Instance : testable sous Lune.
--
--   local trail = Trail.new(maxLength)
--   trail:push(rootPosition)                         -- à chaque frame/tick
--   local positions = trail:sample(count, spacing, firstGap)

export type Trail = {
	points: { Vector3 }, -- du plus ancien (1) au plus récent (#points)
	maxLength: number, -- longueur d'historique conservée (studs)
	minStep: number, -- distance minimale entre deux points enregistrés
	length: number, -- longueur totale actuelle de l'historique
	push: (self: Trail, position: Vector3) -> (),
	reset: (self: Trail, position: Vector3) -> (),
	setMaxLength: (self: Trail, maxLength: number) -> (),
	sample: (self: Trail, count: number, spacing: number, firstGap: number?) -> { Vector3 },
	head: (self: Trail) -> Vector3?,
}

local Trail = {}
Trail.__index = Trail

local DEFAULT_MIN_STEP = 0.5
local TELEPORT_DISTANCE = 40 -- un saut plus grand = téléportation : l'historique repart de zéro

function Trail.new(maxLength: number, minStep: number?): Trail
	assert(maxLength > 0, "Trail.new : maxLength > 0 attendu")
	local self = setmetatable({
		points = {},
		maxLength = maxLength,
		minStep = minStep or DEFAULT_MIN_STEP,
		length = 0,
	}, Trail)
	return self :: any
end

function Trail.reset(self: Trail, position: Vector3)
	self.points = { position }
	self.length = 0
end

function Trail.setMaxLength(self: Trail, maxLength: number)
	self.maxLength = math.max(1, maxLength)
end

function Trail.head(self: Trail): Vector3?
	return self.points[#self.points]
end

-- Retire les points les plus anciens au-delà de maxLength (+ une marge d'un segment)
local function trim(self: Trail)
	local points = self.points
	while #points > 2 do
		local first = points[1]
		local second = points[2]
		local segment = (second - first).Magnitude
		if self.length - segment >= self.maxLength then
			table.remove(points, 1)
			self.length -= segment
		else
			break
		end
	end
end

function Trail.push(self: Trail, position: Vector3)
	if position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z then
		return -- NaN : ignorer
	end
	local points = self.points
	local last = points[#points]
	if not last then
		points[1] = position
		return
	end
	local distance = (position - last).Magnitude
	if distance >= TELEPORT_DISTANCE then
		self:reset(position)
		return
	end
	if distance < self.minStep then
		return
	end
	table.insert(points, position)
	self.length += distance
	trim(self)
end

-- Positions de `count` suiveurs : le 1er à `firstGap` derrière la tête, puis tous les `spacing`.
-- La « tête » est le point le plus récent. Si l'historique est trop court, les suiveurs
-- restants s'empilent au bout le plus ancien (jamais de nil, jamais de NaN).
function Trail.sample(self: Trail, count: number, spacing: number, firstGap: number?): { Vector3 }
	local out: { Vector3 } = table.create(count)
	local points = self.points
	local n = #points
	if count <= 0 or n == 0 then
		return out
	end
	if n == 1 then
		for i = 1, count do
			out[i] = points[1]
		end
		return out
	end
	local target = firstGap or spacing
	local walked = 0
	local index = n
	local i = 1
	while i <= count and index > 1 do
		local a = points[index]
		local b = points[index - 1]
		local segment = (a - b).Magnitude
		if walked + segment >= target then
			local t = if segment > 0 then (target - walked) / segment else 0
			out[i] = a + (b - a) * t
			i += 1
			target += spacing
		else
			walked += segment
			index -= 1
		end
	end
	local tail = points[1]
	while i <= count do
		out[i] = tail
		i += 1
	end
	return out
end

-- Première position (index ≥ fromIndex) à moins de `radius` de l'un des `intruders`.
-- Retourne l'index du suiveur touché et l'intrus, ou nil. Comparaison en 2D (XZ) avec
-- tolérance verticale, pour que sauter au-dessus d'une file ne la coupe pas.
function Trail.findCut(
	positions: { Vector3 },
	intruders: { Vector3 },
	radius: number,
	fromIndex: number,
	maxHeightDifference: number?
): (number?, number?)
	local r2 = radius * radius
	local maxDy = maxHeightDifference or 4
	for i = math.max(1, fromIndex), #positions do
		local p = positions[i]
		for j, q in intruders do
			local dx = p.X - q.X
			local dz = p.Z - q.Z
			if dx * dx + dz * dz <= r2 and math.abs(p.Y - q.Y) <= maxDy then
				return i, j
			end
		end
	end
	return nil, nil
end

return Trail
