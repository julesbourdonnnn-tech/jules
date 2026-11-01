--!strict
-- SeededPath (paquet logic, docs/04 §12.1). Trajets des créatures, déterministes (GDD §4.11,
-- §4.21.2, §12.5) : le serveur ne diffuse que la graine, l'instant de départ et le point de départ ;
-- serveur et clients calculent la même pos(t).
--   * escape (fuite du Rush, Wild Wobbler) : premier bond de 20 studs le long de la rue la plus
--     opposée au boopeur, puis marche au hasard sur le graphe des rues sans demi-tour immédiat ;
--     v(t) = 16 − 0,32 × (t − t0), bornée à 8 ; bonds de 0,45 s (visuels) ; 25 s.
--   * hopAround (fuite personnelle) : bonds de 4,5 studs toutes les 0,5 s, pause de 0,6 s tous les
--     3 bonds, à 35 studs au plus de la Fontaine, jamais dans un ranch ni dans un solide ; 20 s.
--   * golden : marche au hasard sur le graphe, 14 → 10 studs/s en 30 s.
--   * demo (Big Plop) : du point de départ au nœud le plus proche, puis marche au hasard, 8 studs/s.
-- Jamais dans un ranch : le graphe des rues n'entre dans aucun ranch (WorldLayout), et les bonds
-- personnels gardent une marge (propriétés : 10 000 trajets, aucun point hors graphe ni dans un
-- rectangle de ranch). Les décisions n'utilisent que + − × ÷ √ et des directions écrites en
-- littéraux : même résultat sur toutes les plateformes.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, typeof, math, table = type, typeof, math, table

local Types = require(script.Parent.Parent.Types)
local Hash = require(script.Parent.Hash)
local WorldLayout = require(script.Parent.WorldLayout)
local Balance = require(script.Parent.Parent.Config.Balance)
local Events = require(script.Parent.Parent.Config.Events)

-- pos(t) : position au sol et vrai si la créature est en l'air (bond, visuel seulement)
export type PathFn = (t: number) -> (Vector3, boolean)

local SeededPath = {}

local RUSH = Events.Rush
local RUNAWAY = Balance.Runaway
local GOLDEN_SPEED_START = Balance.Golden.SpeedStart
local GOLDEN_SPEED_END = Balance.Golden.SpeedEnd
local GOLDEN_DURATION = Events.Golden.Duration
local DEMO_SPEED = Events.Demo.Speed
local EXTRA_TIME = 5 -- s de trajet calculés au-delà de la durée (créature en retard chez un client)
local AIR_SHARE = 0.8 -- part de chaque bond passée en l'air (visuel)
local HOP_RANCH_MARGIN = 2 -- studs entre un bond personnel et le rectangle d'un ranch
local HOP_SOLID_MARGIN = 1.5 -- studs entre un bond personnel et un solide
local HOP_PLATE_LIMIT = WorldLayout.Const.PlateRadius - 2

-- 16 directions unitaires écrites en littéraux (identiques sur toutes les plateformes)
-- stylua: ignore start
local DIRECTIONS: { { number } } = {
	{ 1, 0 }, { 0.9238795325112867, 0.3826834323650898 }, { 0.7071067811865476, 0.7071067811865476 },
	{ 0.3826834323650898, 0.9238795325112867 }, { 0, 1 }, { -0.3826834323650898, 0.9238795325112867 },
	{ -0.7071067811865476, 0.7071067811865476 }, { -0.9238795325112867, 0.3826834323650898 }, { -1, 0 },
	{ -0.9238795325112867, -0.3826834323650898 }, { -0.7071067811865476, -0.7071067811865476 },
	{ -0.3826834323650898, -0.9238795325112867 }, { 0, -1 }, { 0.3826834323650898, -0.9238795325112867 },
	{ 0.7071067811865476, -0.7071067811865476 }, { 0.9238795325112867, -0.3826834323650898 },
}
-- stylua: ignore end

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- =============================================================================================
-- Polylignes
-- =============================================================================================

type Polyline = { xs: { number }, zs: { number }, dist: { number } }

local function newPolyline(x: number, z: number): Polyline
	return { xs = { x }, zs = { z }, dist = { 0 } }
end

local function push(line: Polyline, x: number, z: number)
	local n = #line.xs
	local dx, dz = x - line.xs[n], z - line.zs[n]
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= 0 then
		return
	end
	table.insert(line.xs, x)
	table.insert(line.zs, z)
	table.insert(line.dist, line.dist[n] + d)
end

local function total(line: Polyline): number
	return line.dist[#line.dist]
end

-- Point à la distance s le long de la polyligne (recherche dichotomique ; bornée aux extrémités)
local function pointAt(line: Polyline, s: number): Vector3
	local dist = line.dist
	local n = #dist
	if n == 1 or s <= 0 then
		return Vector3.new(line.xs[1], 0, line.zs[1])
	end
	if s >= dist[n] then
		return Vector3.new(line.xs[n], 0, line.zs[n])
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if dist[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local span = dist[hi] - dist[lo]
	local a = if span > 0 then (s - dist[lo]) / span else 0
	return Vector3.new(
		line.xs[lo] + (line.xs[hi] - line.xs[lo]) * a,
		0,
		line.zs[lo] + (line.zs[hi] - line.zs[lo]) * a
	)
end

-- =============================================================================================
-- Marche au hasard sur le graphe des rues
-- =============================================================================================

local NODES, NEIGHBORS = WorldLayout.graphView()

local function validNode(node: any): boolean
	return type(node) == "number" and NODES[node] ~= nil
end

-- Voisin dont la direction est la plus proche de l'angle donné (radians)
local function bestNeighbor(node: number, angle: number): number
	local dx, dz = math.cos(angle), math.sin(angle)
	local from = NODES[node]
	local best, bestDot = NEIGHBORS[node][1], -math.huge
	for _, other in NEIGHBORS[node] do
		local to = NODES[other]
		local vx, vz = to.X - from.X, to.Z - from.Z
		local len = math.sqrt(vx * vx + vz * vz)
		if len > 0 then
			local dot = (vx * dx + vz * dz) / len
			if dot > bestDot then
				best, bestDot = other, dot
			end
		end
	end
	return best
end

-- Prolonge la marche jusqu'à `length` studs : de `prev` vers `cur`, sans demi-tour immédiat
local function walk(line: Polyline, rng: any, prev: number, cur: number, length: number)
	local guard = 0
	while total(line) < length and guard < 10000 do
		guard += 1
		local node = NODES[cur]
		push(line, node.X, node.Z)
		local choices = {}
		for _, other in NEIGHBORS[cur] do
			if other ~= prev then
				table.insert(choices, other)
			end
		end
		if #choices == 0 then
			choices = { prev } -- cul-de-sac : demi-tour permis
		end
		local nextNode = choices[rng:int(1, #choices)]
		prev, cur = cur, nextNode
	end
end

-- Chemin du graphe à partir d'un nœud ; `firstAngle` choisit la première rue (fuite du Rush)
local function graphPath(seed: number, startNode: number, length: number, firstAngle: number?): Polyline
	local rng = Hash.stream(seed)
	local start = if validNode(startNode) then startNode else 1
	local origin = NODES[start]
	local line = newPolyline(origin.X, origin.Z)
	local first
	if firstAngle ~= nil then
		first = bestNeighbor(start, firstAngle)
	else
		local list = NEIGHBORS[start]
		first = list[rng:int(1, #list)]
	end
	walk(line, rng, start, first, length)
	return line
end

-- =============================================================================================
-- Profils de vitesse (distance parcourue après τ secondes)
-- =============================================================================================

-- v(τ) = max(vMin, v0 − decay × τ)
local function decayDistance(tau: number, v0: number, decay: number, vMin: number): number
	if v0 <= vMin or decay <= 0 then
		return math.max(v0, vMin) * tau
	end
	local knee = (v0 - vMin) / decay
	if tau <= knee then
		return v0 * tau - 0.5 * decay * tau * tau
	end
	return v0 * knee - 0.5 * decay * knee * knee + vMin * (tau - knee)
end

-- v(τ) passe de v0 à v1 en `duration` secondes, puis reste à v1
local function rampDistance(tau: number, v0: number, v1: number, duration: number): number
	if tau <= duration then
		return v0 * tau + (v1 - v0) * tau * tau / (2 * duration)
	end
	return v0 * duration + (v1 - v0) * duration / 2 + v1 * (tau - duration)
end

-- Bonds visuels : en l'air pendant AIR_SHARE de chaque bond
local function airborne(tau: number, hop: number): boolean
	if tau < 0 or hop <= 0 then
		return false
	end
	return (tau % hop) / hop < AIR_SHARE
end

-- =============================================================================================
-- Trajets
-- =============================================================================================

-- Fuite du Rush, Wild Wobbler
function SeededPath.escape(
	seed: number,
	t0: number,
	startNode: number,
	awayAngle: number,
	speed: number?
): PathFn
	local start = finite(t0, 0)
	local v0 = finite(speed, RUSH.SpeedStart)
	if v0 <= 0 then
		v0 = RUSH.SpeedStart
	end
	local horizon = RUSH.EscapeDuration + EXTRA_TIME
	local length = decayDistance(horizon, v0, RUSH.SpeedDecay, RUSH.SpeedMin) + 1
	local line = graphPath(finite(seed, 0), startNode, length, finite(awayAngle, 0))
	return function(t: number): (Vector3, boolean)
		local tau = math.clamp(finite(t, start) - start, 0, horizon)
		local s = decayDistance(tau, v0, RUSH.SpeedDecay, RUSH.SpeedMin)
		-- premier bond : en l'air jusqu'à FirstHop studs, puis petits bonds
		local air = tau > 0 and (s < RUSH.FirstHop or airborne(tau, RUSH.HopTime))
		return pointAt(line, s), air
	end
end

-- Solides proches d'un centre (le plateau exclu) : seuls ceux-là peuvent gêner un bond personnel
local function nearbySolids(cx: number, cz: number, radius: number): { any }
	local out = {}
	local solids = WorldLayout.solidsView()
	for i = 2, #solids do
		local s = solids[i]
		local dx, dz = s.cx - cx, s.cz - cz
		local reach = radius + s.reach + HOP_SOLID_MARGIN + 1
		if dx * dx + dz * dz <= reach * reach then
			table.insert(out, s)
		end
	end
	return out
end

-- Point (x, z) dans l'emprise d'un solide agrandie de la marge
local function insideSolid(s: any, x: number, z: number): boolean
	local dx, dz = x - s.cx, z - s.cz
	local lx = dx * s.ux + dz * s.uz
	local lz = dx * -s.uz + dz * s.ux
	return math.abs(lx) <= s.hx + HOP_SOLID_MARGIN and math.abs(lz) <= s.hz + HOP_SOLID_MARGIN
end

-- Bond personnel valide : dans le rayon, sur le plateau, loin des ranchs et des solides
local function hopValid(
	x: number,
	z: number,
	cx: number,
	cz: number,
	radius: number,
	solids: { any }
): boolean
	local dx, dz = x - cx, z - cz
	if dx * dx + dz * dz > radius * radius then
		return false
	end
	if x * x + z * z > HOP_PLATE_LIMIT * HOP_PLATE_LIMIT then
		return false
	end
	if WorldLayout.ranchNear(Vector3.new(x, 0, z), HOP_RANCH_MARGIN) ~= 0 then
		return false
	end
	for _, s in solids do
		if insideSolid(s, x, z) then
			return false
		end
	end
	return true
end

-- Créature en fuite personnelle autour de sa Fontaine
function SeededPath.hopAround(seed: number, t0: number, center: Vector3, radius: number): PathFn
	local start = finite(t0, 0)
	local c = if typeof(center) == "Vector3" then center else Vector3.zero
	local cx, cz = finite(c.X, 0), finite(c.Z, 0)
	local r = math.max(0, finite(radius, RUNAWAY.Radius))
	local hopTime, hopDist = RUNAWAY.HopTime, RUNAWAY.HopDistance
	local every, pause = RUNAWAY.PauseEvery, RUNAWAY.Pause
	local cycle = every * hopTime + pause
	local horizon = RUNAWAY.Duration + EXTRA_TIME
	local hops = (math.floor(horizon / cycle) + 1) * every

	-- points de départ de chaque bond (le premier : la Fontaine)
	local rng = Hash.stream(finite(seed, 0))
	local solids = nearbySolids(cx, cz, r)
	local xs, zs = { cx }, { cz }
	for i = 1, hops do
		local x, z = xs[i], zs[i]
		local first = rng:int(1, #DIRECTIONS)
		local nx, nz = x, z
		local found = false
		for k = 0, #DIRECTIONS - 1 do
			local dir = DIRECTIONS[(first - 1 + k * 5) % #DIRECTIONS + 1] -- pas de 5 : visite les 16
			local ex, ez = x + dir[1] * hopDist, z + dir[2] * hopDist
			local mx, mz = (x + ex) / 2, (z + ez) / 2
			if hopValid(ex, ez, cx, cz, r, solids) and hopValid(mx, mz, cx, cz, r, solids) then
				nx, nz, found = ex, ez, true
				break
			end
		end
		if not found then
			-- coincé : retour vers la Fontaine (toujours libre)
			local dx, dz = cx - x, cz - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 0 then
				local step = math.min(hopDist, d)
				nx, nz = x + dx / d * step, z + dz / d * step
			end
		end
		table.insert(xs, nx)
		table.insert(zs, nz)
	end

	return function(t: number): (Vector3, boolean)
		local tau = math.clamp(finite(t, start) - start, 0, horizon)
		local k = math.floor(tau / cycle)
		local inCycle = tau - k * cycle
		local j = math.floor(inCycle / hopTime)
		local index, alpha, air
		if j < every then
			index = k * every + j + 1
			alpha = (inCycle - j * hopTime) / hopTime
			air = tau > 0
		else
			index = k * every + every + 1 -- en pause, posé au bout du dernier bond
			alpha = 0
			air = false
		end
		index = math.min(index, #xs)
		local nextIndex = math.min(index + 1, #xs)
		local x = xs[index] + (xs[nextIndex] - xs[index]) * alpha
		local z = zs[index] + (zs[nextIndex] - zs[index]) * alpha
		return Vector3.new(x, 0, z), air
	end
end

-- Golden Wobbler (30 s)
function SeededPath.golden(seed: number, t0: number, startNode: number): PathFn
	local start = finite(t0, 0)
	local horizon = GOLDEN_DURATION + EXTRA_TIME
	local length = rampDistance(horizon, GOLDEN_SPEED_START, GOLDEN_SPEED_END, GOLDEN_DURATION) + 1
	local line = graphPath(finite(seed, 0), startNode, length, nil)
	return function(t: number): (Vector3, boolean)
		local tau = math.clamp(finite(t, start) - start, 0, horizon)
		local s = rampDistance(tau, GOLDEN_SPEED_START, GOLDEN_SPEED_END, GOLDEN_DURATION)
		return pointAt(line, s), airborne(tau, RUSH.HopTime)
	end
end

-- Démonstration de Big Plop (20 s)
function SeededPath.demo(seed: number, t0: number, start: Vector3): PathFn
	local t = finite(t0, 0)
	local p = if typeof(start) == "Vector3" then start else Vector3.zero
	local px, pz = finite(p.X, 0), finite(p.Z, 0)
	local horizon = Events.Demo.Duration + EXTRA_TIME
	local length = DEMO_SPEED * horizon + 1
	local node = WorldLayout.nearestNode(Vector3.new(px, 0, pz))
	local rng = Hash.stream(finite(seed, 0))
	local line = newPolyline(px, pz)
	walk(line, rng, 0, node, length) -- 0 : aucun nœud précédent
	return function(time: number): (Vector3, boolean)
		local tau = math.clamp(finite(time, t) - t, 0, horizon)
		return pointAt(line, DEMO_SPEED * tau), airborne(tau, RUSH.HopTime)
	end
end

-- Trajet d'une créature diffusée (dispatch selon kind et path)
function SeededPath.fromSpawn(spawn: Types.ChaseSpawn): PathFn
	if type(spawn) ~= "table" then
		return function(_t: number): (Vector3, boolean)
			return Vector3.zero, false
		end
	end
	local s: any = spawn
	local center = Vector3.zero
	if type(s.center) == "table" then
		center = Vector3.new(finite(s.center.x, 0), 0, finite(s.center.z, 0))
	end
	if s.path == "hop" or s.kind == "runaway" then
		return SeededPath.hopAround(s.seed, s.t0, center, RUNAWAY.Radius)
	elseif s.kind == "golden" then
		return SeededPath.golden(s.seed, s.t0, s.startNode)
	elseif s.kind == "demo" then
		return SeededPath.demo(s.seed, s.t0, center)
	end
	return SeededPath.escape(s.seed, s.t0, s.startNode, s.awayAngle, s.speed)
end

return SeededPath
