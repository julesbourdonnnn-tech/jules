--!strict
-- WorldLayout — paquet « logic » (docs/04-architecture.md §12.1).
-- Géométrie PURE de Lumora (aucune Instance) partagée par WorldService (construction),
-- SpawnService (grille), CongaService (portes, ports sûrs, Balise), NestService, EventService et
-- les clients (minicarte, rendu). Toutes les valeurs viennent de Config/Zones et Config/Balance.
--   * Nids : centre du Nid k = slot − 1 en (150 cos 30°k, 0, 150 sin 30°k), orienté vers le centre ;
--     porte à 19 studs côté centre (r = 131) ; boîte de parade 12 × 10 × 4 centrée sur la porte
--   * port sûr : point à < 25 studs (XZ) du centre de N'IMPORTE QUELLE porte
--   * anneau de la Balise 8 ≤ r ≤ 16 ; zone d'un point (anneaux XZ) ; hauteur du sol
--   * grille d'apparition par zone (pas de 6 studs) excluant : r < 16, port sûr élargi (30 studs
--     autour de chaque porte), plateformes de Nid (20 studs), obstacles du décor (decor()), rebord
--     du Cratère (hors ouvertures)
--   * perchoirs : 46 positions dans l'ordre Zones.Perches (arcs de 300° ouverts côté porte ; dans
--     un anneau, le 1er perchoir est au fond, face à la porte, puis alternance gauche / droite)
--   * décor seedé (Zones.Decor.Seed) : mêmes positions pour la construction et l'exclusion
--   * clampToIsland : ramène un point dans l'île (r ≤ Island.Radius − marge) au sol
-- Conventions : Y des positions de décor, de chemin et de lanterne = hauteur du sol (le
-- constructeur ajoute la demi-hauteur de sa pièce) ; les tables renvoyées sont mises en cache et
-- PARTAGÉES : ne pas les modifier. Sud = +Z (convention du projet).
-- GDD : §4.3, §4.7 (port sûr), §4.8 (porte), §11.1-§11.4.
-- Dépendances : Config/Zones, Config/Balance, Logic/Hash.

local Config = script.Parent.Parent.Config
local Balance = require(Config.Balance)
local Zones = require(Config.Zones)
local Hash = require(script.Parent.Hash)

local WorldLayout = {}

export type CrystalSpot = { cframe: CFrame, lit: boolean }
export type LanternSpot = { position: Vector3, lit: boolean }

export type DecorLayout = {
	puffblooms: { Vector3 },
	mushcaps: { Vector3 },
	fences: { CFrame },
	crystals: { CrystalSpot },
	floatingStones: { Vector3 },
	craterRocks: { Vector3 },
	cracks: { CFrame },
	islets: { Vector3 },
	clouds: { Vector3 },
	obstacles: { Vector3 }, -- tous les points à exclure de la grille (rayon Zones.Decor.ObstacleRadius)
}

local Island = Zones.Island
local Nests = Zones.Nests
local Ground = Zones.Ground
local Paths = Zones.Paths
local Decor = Zones.Decor

-- Dimensions internes de mise en page (nommées, purement géométriques)
local WELCOME_SPACING = 3 -- écart latéral entre deux Puffkins de bienvenue
local LANTERN_SIDE_OFFSET = Paths.StoneDiameter / 2 + 1.5 -- lanterne à côté du chemin, pas dessus
local CONSTELLATION_SPREAD = 2.5 -- rayon de la spirale des étoiles (× √(index − 1))
local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
local BEACON_CLAMP_MARGIN = 1 -- un point ramené hors de la colonne de la Balise
local RIM_GRID_MARGIN = 1 -- la grille d'apparition évite le rebord du Cratère (± 1 stud)
local PATH_CLEARANCE = Paths.StoneDiameter / 2 + 2 -- le décor laisse les chemins libres
local FENCE_SIDE_ANGLE = math.rad(110) -- clôtures de part et d'autre de la plateforme
local FENCE_DISTANCE = Nests.PlatformDiameter / 2 + 2
local STONE_FLOAT_HEIGHT = 4 -- pierres flottantes autour des grappes de cristaux
local STONE_FLOAT_DISTANCE = 4.5
local PLACE_ATTEMPTS = 60

local SLOT_COUNT = Nests.Count
local ANGLE_STEP = math.rad(Nests.AngleStep)
local GATE_RADIUS = Nests.Ring - Nests.GateDistance -- r = 131

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function validSlot(slot: number): boolean
	return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= SLOT_COUNT
end

local function checkSlot(slot: number, fn: string)
	if not validSlot(slot) then
		error(`WorldLayout.{fn} : slot 1-{SLOT_COUNT} attendu, reçu {tostring(slot)}`, 3)
	end
end

local function finiteOr(x: number, default: number): number
	if x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

local function slotAngle(slot: number): number
	return ANGLE_STEP * (slot - 1)
end

-- Repère horizontal d'un Nid : centre, avant (vers le centre de l'île), droite
type Frame = { center: Vector3, forward: Vector3, right: Vector3, gate: Vector3 }

local frames: { Frame } = {}
for slot = 1, SLOT_COUNT do
	local a = slotAngle(slot)
	local center = Vector3.new(Nests.Ring * math.cos(a), 0, Nests.Ring * math.sin(a))
	local forward = Vector3.new(-math.cos(a), 0, -math.sin(a))
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local gate = center + forward * Nests.GateDistance
	frames[slot] = {
		center = center,
		forward = forward,
		right = right,
		gate = Vector3.new(gate.X, Balance.Parade.GateHeight / 2, gate.Z),
	}
end

local function distXZ(ax: number, az: number, bx: number, bz: number): number
	local dx = ax - bx
	local dz = az - bz
	return math.sqrt(dx * dx + dz * dz)
end

-- Écart angulaire (radians) au chemin radial le plus proche, et l'angle de ce chemin
local function nearestPathAngle(x: number, z: number): (number, number)
	local a = math.atan2(z, x)
	local k = math.floor(a / ANGLE_STEP + 0.5)
	local pathAngle = k * ANGLE_STEP
	return math.abs(a - pathAngle), pathAngle
end

-- Distance latérale (XZ) à la ligne du chemin radial le plus proche, si r est sur le chemin
local function pathLateral(x: number, z: number): number
	local r = math.sqrt(x * x + z * z)
	if r < Paths.To - Paths.StoneDiameter or r > Paths.From + Paths.StoneDiameter then
		return math.huge
	end
	local delta = nearestPathAngle(x, z)
	return r * math.sin(math.min(delta, math.pi / 2))
end

local function inRimGap(x: number, z: number, r: number): boolean
	local delta = nearestPathAngle(x, z)
	return r * delta < Ground.RimGap / 2
end

-- ---------------------------------------------------------------------------------------------
-- Rayons, Nids, portes, ports sûrs
-- ---------------------------------------------------------------------------------------------

function WorldLayout.radiusXZ(pos: Vector3): number
	return math.sqrt(pos.X * pos.X + pos.Z * pos.Z)
end

function WorldLayout.nestCenter(slot: number): Vector3
	checkSlot(slot, "nestCenter")
	return frames[slot].center
end

-- Repère du Nid au sol, LookVector vers le centre de l'île
function WorldLayout.nestCFrame(slot: number): CFrame
	checkSlot(slot, "nestCFrame")
	local f = frames[slot]
	return CFrame.lookAt(f.center, f.center + f.forward)
end

-- Centre de la boîte de porte (Y = GateHeight / 2), LookVector vers le centre de l'île
function WorldLayout.gateCFrame(slot: number): CFrame
	checkSlot(slot, "gateCFrame")
	local f = frames[slot]
	return CFrame.lookAt(f.gate, f.gate + f.forward)
end

-- Boîte de parade 12 × 10 × 4 (largeur × hauteur × profondeur) dans le repère de la porte
function WorldLayout.inGateBox(slot: number, pos: Vector3): boolean
	if not validSlot(slot) then
		return false
	end
	local f = frames[slot]
	local d = pos - f.gate
	local p = Balance.Parade
	return math.abs(d:Dot(f.right)) <= p.GateWidth / 2
		and math.abs(d.Y) <= p.GateHeight / 2
		and math.abs(d:Dot(f.forward)) <= p.GateDepth / 2
end

-- Slot dont la porte est à moins de HarborRadius (XZ), sinon nil
function WorldLayout.harborSlot(pos: Vector3): number?
	local radius = Balance.Snip.HarborRadius
	local r = WorldLayout.radiusXZ(pos)
	if not (math.abs(r - GATE_RADIUS) < radius) then -- rejette aussi NaN
		return nil
	end
	-- les portes sont toutes sur le même cercle : la plus proche est celle du chemin le plus proche
	local _, pathAngle = nearestPathAngle(pos.X, pos.Z)
	local slot = (math.floor(pathAngle / ANGLE_STEP + 0.5) % SLOT_COUNT) + 1
	local g = frames[slot].gate
	if distXZ(pos.X, pos.Z, g.X, g.Z) < radius then
		return slot
	end
	return nil
end

function WorldLayout.inHarbor(pos: Vector3): boolean
	return WorldLayout.harborSlot(pos) ~= nil
end

function WorldLayout.inOwnHarbor(slot: number, pos: Vector3): boolean
	if not validSlot(slot) then
		return false
	end
	local g = frames[slot].gate
	return distXZ(pos.X, pos.Z, g.X, g.Z) < Balance.Snip.HarborRadius
end

function WorldLayout.inBeaconRing(pos: Vector3): boolean
	local r = WorldLayout.radiusXZ(pos)
	return r >= Balance.Beacon.RingInner and r <= Balance.Beacon.RingOuter
end

-- "meadow" | "glade" | "crater" | nil (Balise r < 16, hors des anneaux, hors île)
function WorldLayout.zoneAt(pos: Vector3): string?
	local r = WorldLayout.radiusXZ(pos)
	for _, def in Zones.List do
		if r >= def.inner and r < def.outer then
			return def.key
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- Sol
-- ---------------------------------------------------------------------------------------------

-- Hauteur de la surface praticable en (x, z) : île, Clairière, Cratère, rebord du Cratère (pente),
-- socle de la Balise, plateformes des Nids
function WorldLayout.groundY(x: number, z: number): number
	x = finiteOr(x, 0)
	z = finiteOr(z, 0)
	local r = math.sqrt(x * x + z * z)
	local y = Island.TopY
	if r < Ground.GladeDiameter / 2 then
		y = Ground.GladeTopY
	end
	if r < Ground.CraterDiameter / 2 then
		y = Ground.CraterTopY
		-- étages de la Balise (du socle au sommet)
		local top = y
		for _, tier in Zones.Beacon.Tiers do
			if r < tier.diameter / 2 then
				top += tier.height
			else
				break
			end
		end
		y = top
	end
	if r > Ground.RimInner and r < Ground.RimOuter and not inRimGap(x, z, r) then
		local mid = (Ground.RimInner + Ground.RimOuter) / 2
		local half = (Ground.RimOuter - Ground.RimInner) / 2
		y += Ground.RimHeight * (1 - math.abs(r - mid) / half)
	end
	if math.abs(r - Nests.Ring) < Nests.PlatformDiameter / 2 then
		local a = math.atan2(z, x)
		local slot = (math.floor(a / ANGLE_STEP + 0.5) % SLOT_COUNT) + 1
		local c = frames[slot].center
		if distXZ(x, z, c.X, c.Z) < Nests.PlatformDiameter / 2 then
			y = math.max(y, Nests.PlatformTopY)
		end
	end
	return y
end

-- Ramène un point dans l'île (r ≤ Island.Radius − marge, hors de la colonne de la Balise) au sol.
-- Marge par défaut : jusqu'au bord extérieur de la Prairie (r ≤ 170).
function WorldLayout.clampToIsland(pos: Vector3, margin: number?): Vector3
	local outermost = 0
	for _, def in Zones.List do
		outermost = math.max(outermost, def.outer)
	end
	local m = finiteOr(margin or (Island.Radius - outermost), 0)
	local maxR = math.max(0, Island.Radius - math.max(0, m))
	local minR = math.min(maxR, Zones.Beacon.CollisionRadius + BEACON_CLAMP_MARGIN)
	local x = finiteOr(pos.X, 0)
	local z = finiteOr(pos.Z, 0)
	local r = math.sqrt(x * x + z * z)
	if r > maxR then
		x, z = x * maxR / r, z * maxR / r
	elseif r < minR then
		if r < 1e-6 then
			x, z = minR, 0
		else
			x, z = x * minR / r, z * minR / r
		end
	end
	return Vector3.new(x, WorldLayout.groundY(x, z), z)
end

-- ---------------------------------------------------------------------------------------------
-- Perchoirs, accueil, observatoire, constellation, tableau
-- ---------------------------------------------------------------------------------------------

-- Angles (radians, mesurés depuis la direction de la porte) d'un anneau de perchoirs, triés :
-- fond (face à la porte) d'abord, puis alternance de part et d'autre
local function ringAngles(count: number): { number }
	local arc = math.rad(Zones.Perches.ArcDegrees)
	local gap = 2 * math.pi - arc
	local list = {}
	for j = 0, count - 1 do
		local t = if count > 1 then j / (count - 1) else 0.5
		table.insert(list, gap / 2 + arc * t)
	end
	table.sort(list, function(a, b)
		local da = math.abs(a - math.pi)
		local db = math.abs(b - math.pi)
		if math.abs(da - db) > 1e-9 then
			return da < db
		end
		return a > b
	end)
	return list
end

type PerchSpot = { radius: number, angle: number, y: number }
local perchSpots: { PerchSpot } = {}
for _, ring in Zones.Perches.Rings do
	for _, angle in ringAngles(ring.count) do
		table.insert(perchSpots, { radius = ring.radius, angle = angle, y = ring.y })
	end
end

-- Perchoir `index` (1-46) du Nid `slot`, dans l'ordre Zones.Perches : repère au PIED du perchoir
-- (dessus de la plateforme + hauteur de l'anneau), LookVector vers le centre de l'île
function WorldLayout.perchCFrame(slot: number, index: number): CFrame
	checkSlot(slot, "perchCFrame")
	local spot = perchSpots[index]
	if spot == nil then
		error(`WorldLayout.perchCFrame : index 1-{#perchSpots} attendu, reçu {tostring(index)}`, 2)
	end
	local f = frames[slot]
	local dir = f.forward * math.cos(spot.angle) + f.right * math.sin(spot.angle)
	local p = f.center + dir * spot.radius
	local pos = Vector3.new(p.X, Nests.PlatformTopY + spot.y, p.Z)
	return CFrame.lookAt(pos, pos + f.forward)
end

-- `count` points du port sûr à WelcomeDistance (12) devant la porte (Puffkins de bienvenue)
function WorldLayout.welcomePoints(slot: number, count: number): { Vector3 }
	checkSlot(slot, "welcomePoints")
	local f = frames[slot]
	local n = math.max(0, math.floor(finiteOr(count, 0)))
	local out = table.create(n)
	local base = Vector3.new(f.gate.X, 0, f.gate.Z) + f.forward * Balance.Spawn.WelcomeDistance
	for i = 1, n do
		local p = base + f.right * ((i - (n + 1) / 2) * WELCOME_SPACING)
		out[i] = Vector3.new(p.X, WorldLayout.groundY(p.X, p.Z), p.Z)
	end
	return out
end

function WorldLayout.observatoryCFrame(slot: number): CFrame
	checkSlot(slot, "observatoryCFrame")
	local f = frames[slot]
	local a = slotAngle(slot)
	local pos =
		Vector3.new(Nests.ObservatoryRadius * math.cos(a), Island.TopY, Nests.ObservatoryRadius * math.sin(a))
	return CFrame.lookAt(pos, pos + f.forward)
end

-- Étoile `index` (1 = première Supernova) de la constellation au-dessus de l'observatoire (Y = 45) :
-- spirale dorée dans le plan vertical tourné vers le centre de l'île (index 1 au centre)
function WorldLayout.constellationPoint(slot: number, index: number): Vector3
	checkSlot(slot, "constellationPoint")
	local f = frames[slot]
	local i = math.max(1, math.floor(finiteOr(index, 1)))
	local a = slotAngle(slot)
	local base = Vector3.new(
		Nests.ObservatoryRadius * math.cos(a),
		Nests.ConstellationY,
		Nests.ObservatoryRadius * math.sin(a)
	)
	local rho = CONSTELLATION_SPREAD * math.sqrt(i - 1)
	local phi = (i - 1) * GOLDEN_ANGLE
	return base + f.right * (rho * math.cos(phi)) + Vector3.yAxis * (rho * math.sin(phi))
end

-- Stèle du tableau des congas (r = 12, face au sud = +Z), au sol du Cratère
function WorldLayout.boardCFrame(): CFrame
	local r = Zones.Beacon.BoardRadius
	local pos = Vector3.new(0, WorldLayout.groundY(0, r), r)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
end

-- ---------------------------------------------------------------------------------------------
-- Chemins et lanternes
-- ---------------------------------------------------------------------------------------------

local stonesCache: { Vector3 }? = nil

-- Pas japonais : 12 rayons de r = 131 à r = 58, une pierre tous les 6 studs (Y = sol)
function WorldLayout.pathStones(): { Vector3 }
	if stonesCache then
		return stonesCache
	end
	local out = {}
	for k = 0, Paths.Count - 1 do
		local a = k * 2 * math.pi / Paths.Count
		local r = Paths.From
		while r >= Paths.To do
			local x, z = r * math.cos(a), r * math.sin(a)
			table.insert(out, Vector3.new(x, WorldLayout.groundY(x, z), z))
			r -= Paths.StoneEvery
		end
	end
	stonesCache = out
	return out
end

local lanternsCache: { LanternSpot }? = nil

-- Lanternes au bord de chaque chemin à r 120, 90, 60 ; allumées (PointLight) à r 90 et 60
function WorldLayout.lanterns(): { LanternSpot }
	if lanternsCache then
		return lanternsCache
	end
	local out = {}
	for k = 0, Paths.Count - 1 do
		local a = k * 2 * math.pi / Paths.Count
		local radial = Vector3.new(math.cos(a), 0, math.sin(a))
		local side = Vector3.new(-radial.Z, 0, radial.X)
		for _, r in Paths.LanternRadii do
			local p = radial * r + side * LANTERN_SIDE_OFFSET
			table.insert(out, {
				position = Vector3.new(p.X, WorldLayout.groundY(p.X, p.Z), p.Z),
				lit = table.find(Paths.LitRadii, r) ~= nil,
			})
		end
	end
	lanternsCache = out
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Décor seedé (§11.4)
-- ---------------------------------------------------------------------------------------------

local decorCache: DecorLayout? = nil

local function nearAny(x: number, z: number, list: { Vector3 }, minDist: number): boolean
	for _, p in list do
		if distXZ(x, z, p.X, p.Z) < minDist then
			return true
		end
	end
	return false
end

-- Point libre pour du décor de Prairie / Clairière (hors ports sûrs, plateformes, chemins)
local function clearOfStructures(x: number, z: number): boolean
	for slot = 1, SLOT_COUNT do
		local f = frames[slot]
		if distXZ(x, z, f.gate.X, f.gate.Z) < Nests.SpawnExclusion then
			return false
		end
		if distXZ(x, z, f.center.X, f.center.Z) < Nests.NestExclusion then
			return false
		end
	end
	return pathLateral(x, z) >= PATH_CLEARANCE
end

function WorldLayout.decor(): DecorLayout
	if decorCache then
		return decorCache
	end
	local rng = Hash.stream(Decor.Seed)
	local meadow = Zones.byKey.meadow
	local glade = Zones.byKey.glade
	local crater = Zones.byKey.crater
	local lanternPoints = {}
	for _, l in WorldLayout.lanterns() do
		table.insert(lanternPoints, l.position)
	end

	-- Tirage d'un point dans un anneau [rMin, rMax] qui respecte `ok` et l'écart `spacing` avec
	-- `taken` ; après PLACE_ATTEMPTS échecs, le dernier candidat est gardé (nombre d'objets fixe)
	local function place(
		rMin: number,
		rMax: number,
		spacing: number,
		taken: { Vector3 },
		ok: (number, number) -> boolean
	): Vector3
		local x, z = 0, 0
		for _ = 1, PLACE_ATTEMPTS do
			local a = rng:range(0, 2 * math.pi)
			-- tirage uniforme en surface
			local r = math.sqrt(rng:range(rMin * rMin, rMax * rMax))
			x, z = r * math.cos(a), r * math.sin(a)
			if
				ok(x, z)
				and not nearAny(x, z, taken, spacing)
				and not nearAny(x, z, lanternPoints, spacing)
			then
				break
			end
		end
		return Vector3.new(x, WorldLayout.groundY(x, z), z)
	end

	local meadowMin = (if meadow then meadow.inner else 110) + 4
	local meadowMax = (if meadow then meadow.outer else 170) - 2
	local meadowTaken: { Vector3 } = {}

	local puffblooms = {}
	for _ = 1, Decor.Meadow.Puffblooms do
		local p = place(meadowMin, meadowMax, 4, meadowTaken, clearOfStructures)
		table.insert(puffblooms, p)
		table.insert(meadowTaken, p)
	end
	local mushcaps = {}
	for _ = 1, Decor.Meadow.Mushcaps do
		local p = place(meadowMin, meadowMax, 5, meadowTaken, clearOfStructures)
		table.insert(mushcaps, p)
		table.insert(meadowTaken, p)
	end

	-- Clôtures : 2 par Nid, de part et d'autre de la plateforme, orientées tangentiellement
	local fences = {}
	local fencePoints = {}
	local perNest = math.max(1, math.floor(Decor.Meadow.Fences / SLOT_COUNT))
	for slot = 1, SLOT_COUNT do
		local f = frames[slot]
		for j = 1, perNest do
			local side = if j % 2 == 1 then 1 else -1
			local angle = FENCE_SIDE_ANGLE + math.floor((j - 1) / 2) * math.rad(20)
			local dir = f.forward * math.cos(angle) + f.right * (side * math.sin(angle))
			local p = f.center + dir * FENCE_DISTANCE
			local pos = Vector3.new(p.X, WorldLayout.groundY(p.X, p.Z), p.Z)
			local tangent = Vector3.new(-dir.Z, 0, dir.X)
			table.insert(fences, CFrame.lookAt(pos, pos + tangent))
			table.insert(fencePoints, pos)
		end
	end

	-- Clairière : grappes de cristaux (les LitCrystals premières portent une lumière) et pierres
	local gladeMin = (if glade then glade.inner else 55) + 8
	local gladeMax = (if glade then glade.outer else 110) - 6
	local crystals = {}
	local crystalPoints = {}
	for i = 1, Decor.Glade.CrystalClusters do
		local p = place(gladeMin, gladeMax, 12, crystalPoints, clearOfStructures)
		local yaw = rng:range(0, 2 * math.pi)
		table.insert(
			crystals,
			{ cframe = CFrame.new(p) * CFrame.Angles(0, yaw, 0), lit = i <= Decor.Glade.LitCrystals }
		)
		table.insert(crystalPoints, p)
	end
	local floatingStones = {}
	for i = 1, Decor.Glade.FloatingStones do
		local base = crystalPoints[((i - 1) % math.max(1, #crystalPoints)) + 1] or Vector3.new(gladeMin, 0, 0)
		local a = rng:range(0, 2 * math.pi)
		table.insert(
			floatingStones,
			base
				+ Vector3.new(
					STONE_FLOAT_DISTANCE * math.cos(a),
					STONE_FLOAT_HEIGHT,
					STONE_FLOAT_DISTANCE * math.sin(a)
				)
		)
	end

	-- Cratère : rochers et fissures, hors de la zone d'exclusion de la Balise
	local craterMin = (if crater then crater.inner else 16) + 4
	local craterMax = Ground.RimInner - 4
	local craterRocks = {}
	local function anywhere(_x: number, _z: number): boolean
		return true
	end
	for _ = 1, Ground.CraterRocks do
		table.insert(craterRocks, place(craterMin, craterMax, 8, craterRocks, anywhere))
	end
	local cracks = {}
	for _ = 1, Ground.CrackCount do
		local a = rng:range(0, 2 * math.pi)
		local r = rng:range(craterMin - 2, craterMax)
		local yaw = rng:range(0, 2 * math.pi)
		local x, z = r * math.cos(a), r * math.sin(a)
		table.insert(cracks, CFrame.new(x, Ground.CraterTopY, z) * CFrame.Angles(0, yaw, 0))
	end

	-- Îlots flottants (répartis autour de l'île) et mer de nuages
	local islets = {}
	local isl = Zones.Islets
	for i = 1, isl.Count do
		local a = (i - 1) * 2 * math.pi / isl.Count + rng:range(-0.25, 0.25)
		local r = rng:range(isl.RadiusMin, isl.RadiusMax)
		table.insert(islets, Vector3.new(r * math.cos(a), rng:range(isl.YMin, isl.YMax), r * math.sin(a)))
	end
	local clouds = {}
	for _ = 1, Island.CloudCount do
		local a = rng:range(0, 2 * math.pi)
		local r = rng:range(Island.CloudRadiusMin, Island.CloudRadiusMax)
		table.insert(clouds, Vector3.new(r * math.cos(a), Island.CloudSeaY, r * math.sin(a)))
	end

	local obstacles = {}
	for _, list in { puffblooms, mushcaps, fencePoints, crystalPoints, craterRocks, lanternPoints } do
		for _, p in list do
			table.insert(obstacles, p)
		end
	end

	local layout: DecorLayout = {
		puffblooms = puffblooms,
		mushcaps = mushcaps,
		fences = fences,
		crystals = crystals,
		floatingStones = floatingStones,
		craterRocks = craterRocks,
		cracks = cracks,
		islets = islets,
		clouds = clouds,
		obstacles = obstacles,
	}
	decorCache = layout
	return layout
end

-- ---------------------------------------------------------------------------------------------
-- Grille d'apparition (§4.3)
-- ---------------------------------------------------------------------------------------------

local spawnCache: { [string]: { Vector3 } } = {}

-- Points de la grille d'apparition d'une zone (calculés une fois, mis en cache ; zone inconnue →
-- liste vide)
function WorldLayout.spawnPoints(zoneKey: string): { Vector3 }
	local cached = spawnCache[zoneKey]
	if cached then
		return cached
	end
	local def = Zones.byKey[zoneKey]
	local out: { Vector3 } = {}
	if def == nil then
		spawnCache[zoneKey] = out
		return out
	end
	local step = Balance.Spawn.GridStep
	local obstacles = WorldLayout.decor().obstacles
	local obstacleRadius = Decor.ObstacleRadius
	local n = math.ceil(def.outer / step)
	for i = -n, n do
		for j = -n, n do
			local x, z = i * step, j * step
			local r = math.sqrt(x * x + z * z)
			local ok = r >= def.inner and r < def.outer and r >= Zones.Beacon.Radius
			if ok and r > Ground.RimInner - RIM_GRID_MARGIN and r < Ground.RimOuter + RIM_GRID_MARGIN then
				ok = inRimGap(x, z, r)
			end
			if ok then
				for slot = 1, SLOT_COUNT do
					local f = frames[slot]
					if
						distXZ(x, z, f.gate.X, f.gate.Z) < Nests.SpawnExclusion
						or distXZ(x, z, f.center.X, f.center.Z) < Nests.NestExclusion
					then
						ok = false
						break
					end
				end
			end
			if ok and nearAny(x, z, obstacles, obstacleRadius) then
				ok = false
			end
			if ok then
				table.insert(out, Vector3.new(x, WorldLayout.groundY(x, z), z))
			end
		end
	end
	spawnCache[zoneKey] = out
	return out
end

return WorldLayout
