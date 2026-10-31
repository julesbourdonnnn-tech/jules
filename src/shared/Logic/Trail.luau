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
	reset: (self: Trail, position: Vector3, seq: number?) -> (),
	setMaxLength: (self: Trail, maxLength: number) -> (),
	sample: (self: Trail, count: number, spacing: number, firstGap: number?) -> { Vector3 },
	head: (self: Trail) -> Vector3?,
	-- Extension du contrat (paquet « logic », docs/04-architecture.md §12.1) :
	-- numérotation des points pour le réseau (PathStream). firstSeq = numéro de points[1] ;
	-- push incrémente, la coupe des vieux points avance firstSeq, reset continue la numérotation.
	firstSeq: number,
	lastSeq: (self: Trail) -> number,
	since: (self: Trail, seq: number, maxCount: number?) -> (number, { Vector3 }),
}

local Trail = {}
Trail.__index = Trail

local DEFAULT_MIN_STEP = 0.5
local TELEPORT_DISTANCE = 40 -- un saut plus grand = téléportation : l'historique repart de zéro

-- firstSeq (extension logic, défaut 1) : numéro attribué au premier point poussé
function Trail.new(maxLength: number, minStep: number?, firstSeq: number?): Trail
	assert(maxLength > 0, "Trail.new : maxLength > 0 attendu")
	local seq = firstSeq or 1
	if seq ~= seq or seq == math.huge or seq == -math.huge then
		seq = 1
	end
	local self = setmetatable({
		points = {},
		maxLength = maxLength,
		minStep = minStep or DEFAULT_MIN_STEP,
		length = 0,
		firstSeq = math.floor(seq),
	}, Trail)
	return self :: any
end

-- `seq` (extension logic, optionnel) : numéro du point de départ ; par défaut la numérotation
-- continue (lastSeq + 1), un client qui reconstruit un PathSnapshot passe le numéro reçu
function Trail.reset(self: Trail, position: Vector3, seq: number?)
	local nextSeq = self.firstSeq + #self.points
	if seq ~= nil and seq == seq and seq ~= math.huge and seq ~= -math.huge then
		nextSeq = math.floor(seq)
	end
	self.points = { position }
	self.length = 0
	self.firstSeq = nextSeq
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
			self.firstSeq += 1
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

-- ---------------------------------------------------------------------------------------------
-- Extension du contrat — paquet « logic » (docs/04-architecture.md §12.1, GDD §4.7, §12.4)
--  * Trail.new(maxLength, minStep?, firstSeq?) : firstSeq (défaut 1) = numéro du premier point
--  * trail:lastSeq() = firstSeq + #points − 1 (firstSeq − 1 si vide)
--  * trail:since(seq, maxCount?) → (numéro du 1er point rendu, points de numéro ≥ seq), borné
--    aux points encore présents ; maxCount garde les PLUS RÉCENTS
--  * Trail.segmentDistanceXZ(a0, a1, b0, b1) → (distance, s, t) : distance minimale dans le plan
--    XZ entre les segments [a0, a1] et [b0, b1], s et t ∈ [0, 1] les paramètres des points proches
--  * Trail.findCutSwept(nodes, from, to, radius, firstSegment, maxDy?, skip?) → (k, point) :
--    premier segment k ≥ max(2, firstSegment) (segment k = [nodes[k−1], nodes[k]]) dont la
--    distance XZ au balayage [from, to] ≤ radius et |Δy| ≤ maxDy (défaut 4) ;
--    skip(k, point) = true ignore ce segment (escorte, port sûr). Test continu (segment contre
--    segment) : aucun trou, quelle que soit la vitesse (3,6 studs/tick au Dash).
-- ---------------------------------------------------------------------------------------------

local SEGMENT_EPSILON = 1e-12
local DEFAULT_MAX_DY = 4

-- Numéro du point le plus récent (firstSeq − 1 si l'historique est vide)
function Trail.lastSeq(self: Trail): number
	return self.firstSeq + #self.points - 1
end

-- Points de numéro ≥ seq encore présents (copie), au plus `maxCount` (les plus récents) ;
-- retourne aussi le numéro du premier point rendu (lastSeq + 1 si aucun)
function Trail.since(self: Trail, seq: number, maxCount: number?): (number, { Vector3 })
	local points = self.points
	local last = self.firstSeq + #points - 1
	local from = if seq == seq then math.max(self.firstSeq, math.ceil(seq)) else self.firstSeq
	if maxCount ~= nil then
		local limit = if maxCount == maxCount then math.floor(maxCount) else 0
		if limit <= 0 then
			return last + 1, {}
		end
		from = math.max(from, last - limit + 1)
	end
	if from > last then
		return last + 1, {}
	end
	local out = table.create(last - from + 1)
	for s = from, last do
		out[s - from + 1] = points[s - self.firstSeq + 1]
	end
	return from, out
end

-- Distance minimale dans le plan XZ entre les segments [a0, a1] et [b0, b1] (algorithme des
-- points les plus proches d'Ericson, segments dégénérés et parallèles compris).
-- Retourne (distance, s, t) : points proches a0 + s (a1 − a0) et b0 + t (b1 − b0).
function Trail.segmentDistanceXZ(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3): (number, number, number)
	local d1x, d1z = a1.X - a0.X, a1.Z - a0.Z
	local d2x, d2z = b1.X - b0.X, b1.Z - b0.Z
	local rx, rz = a0.X - b0.X, a0.Z - b0.Z
	local a = d1x * d1x + d1z * d1z
	local e = d2x * d2x + d2z * d2z
	local f = d2x * rx + d2z * rz
	local s, t
	if a <= SEGMENT_EPSILON and e <= SEGMENT_EPSILON then
		s, t = 0, 0
	elseif a <= SEGMENT_EPSILON then
		s = 0
		t = math.clamp(f / e, 0, 1)
	else
		local c = d1x * rx + d1z * rz
		if e <= SEGMENT_EPSILON then
			t = 0
			s = math.clamp(-c / a, 0, 1)
		else
			local b = d1x * d2x + d1z * d2z
			local denom = a * e - b * b
			s = if denom > SEGMENT_EPSILON * a * e then math.clamp((b * f - c * e) / denom, 0, 1) else 0
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t = 1
				s = math.clamp((b - c) / a, 0, 1)
			end
		end
	end
	local px, pz = a0.X + d1x * s, a0.Z + d1z * s
	local qx, qz = b0.X + d2x * t, b0.Z + d2z * t
	local dx, dz = px - qx, pz - qz
	return math.sqrt(dx * dx + dz * dz), s, t
end

-- Premier segment de file coupé par le balayage [from, to] (le plus près de la tête), ou nil.
-- Retourne (k, point touché sur le segment de la file).
function Trail.findCutSwept(
	nodes: { Vector3 },
	from: Vector3,
	to: Vector3,
	radius: number,
	firstSegment: number,
	maxDy: number?,
	skip: ((k: number, point: Vector3) -> boolean)?
): (number?, Vector3?)
	if not (radius >= 0) then -- rejette NaN et négatif
		return nil, nil
	end
	local dyMax = maxDy or DEFAULT_MAX_DY
	-- boîte XZ du balayage élargie du rayon (élagage segment par segment)
	local minX = math.min(from.X, to.X) - radius
	local maxX = math.max(from.X, to.X) + radius
	local minZ = math.min(from.Z, to.Z) - radius
	local maxZ = math.max(from.Z, to.Z) + radius
	if not (minX <= maxX and minZ <= maxZ) then -- NaN dans le balayage
		return nil, nil
	end
	local first = if firstSegment == firstSegment then math.max(2, math.ceil(firstSegment)) else 2
	for k = first, #nodes do
		local a = nodes[k - 1]
		local b = nodes[k]
		if
			math.max(a.X, b.X) >= minX
			and math.min(a.X, b.X) <= maxX
			and math.max(a.Z, b.Z) >= minZ
			and math.min(a.Z, b.Z) <= maxZ
		then
			local d, s, t = Trail.segmentDistanceXZ(a, b, from, to)
			if d <= radius then
				local hit = a + (b - a) * s
				local sweepY = from.Y + (to.Y - from.Y) * t
				if math.abs(hit.Y - sweepY) <= dyMax and not (skip and skip(k, hit)) then
					return k, hit
				end
			end
		end
	end
	return nil, nil
end

return Trail
