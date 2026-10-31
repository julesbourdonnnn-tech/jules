--!strict
-- SeededPath — paquet « logic » (docs/04-architecture.md §12.1).
-- Trajectoires déterministes : serveur et clients calculent la MÊME position à partir d'une graine
-- et de Clock.now() ; rien de physique n'est répliqué.
--   * wander(seed, dt) : décalage XZ (Y = 0) d'un Nebby sauvage autour de son ancre, courbe de
--     Lissajous d'amplitude Balance.Spawn.WanderAmplitude (1,6), fréquences tirées dans
--     [WanderFreqMin ; WanderFreqMax] rad/s, phases tirées (Hash) ; |x|, |z| ≤ 1,6
--   * chordAt(seed, t0, t) : Gloomwisp sur des cordes entre points du cercle r = Wisps.PathRadius
--     (165) à Wisps.Speed (7 studs/s), pause Wisps.Pause (4 s) à l'arrivée, corde suivante partant
--     du point d'arrivée (écart angulaire de la corde k tiré par Hash(seed, sel, k) dans
--     [CHORD_MIN_TURN ; 2π − CHORD_MIN_TURN] : chaque corde traverse l'île) ; retourne
--     (position au sol Y = 0, direction unitaire). Pendant la pause : point d'arrivée, direction
--     de la corde suivante. Avant t0 : point de départ.
--   * newChordCursor : même calcul, incrémental (t croissant) en O(1) amorti
--   * cometSky : courbe de Bézier quadratique de la Comète dans le ciel (alpha 0 → 1 en
--     Comet.SkySeconds), départ haut dans le ciel tiré de Hash(id, Events.Salts.CometSky),
--     arrivée = impact
--   * scatterPoint : point de dispersion à ScatterMin-ScatterMax studs (NON borné à l'île :
--     l'appelant applique WorldLayout.clampToIsland)
-- GDD : §4.3 (flânerie), §4.15.4 (cordes), §9.4 (arc de la Comète), §4.7 (dispersion), §12.9.
-- Dépendances : Config/Balance, Config/Events, Logic/Hash.

local Config = script.Parent.Parent.Config
local Balance = require(Config.Balance)
local Events = require(Config.Events)
local Hash = require(script.Parent.Hash)

local SeededPath = {}

export type ChordCursor = {
	-- position et direction à t (t non décroissant d'un appel à l'autre ; un t plus petit repart
	-- du début, le résultat reste exact)
	at: (self: ChordCursor, t: number) -> (Vector3, Vector3),
	-- `count` points espacés le long du trajet sur les `studs` prochains studs (Beam d'aperçu)
	ahead: (self: ChordCursor, t: number, studs: number, count: number) -> { Vector3 },
}

local TAU = 2 * math.pi
local WISP_SALT = Events.Salts.Wisp
local SCATTER_SALT = Events.Salts.Scatter
local SKY_SALT = Events.Salts.CometSky

-- Géométrie interne (nommée) : chaque corde tourne d'au moins 100° sur le cercle (longueur
-- ≥ 2 R sin 50° ≈ 253 studs), le Gloomwisp traverse toujours l'intérieur de l'île
local CHORD_MIN_TURN = math.rad(100)
-- Arc de la Comète dans le ciel : départ à 260-380 studs (XZ) de l'impact, 220-300 studs de haut,
-- point de contrôle relevé de 35 % de la hauteur
local SKY_DISTANCE_MIN, SKY_DISTANCE_MAX = 260, 380
local SKY_HEIGHT_MIN, SKY_HEIGHT_MAX = 220, 300
local SKY_CONTROL_LIFT = 0.35

local function finiteOr(x: number, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

-- ---------------------------------------------------------------------------------------------
-- Flânerie (§4.3)
-- ---------------------------------------------------------------------------------------------

type WanderParams = { fx: number, fz: number, px: number, pz: number }

-- Petit cache des paramètres (4 hachages par graine) : vidé au-delà de WANDER_CACHE_MAX entrées
local WANDER_CACHE_MAX = 1024
local wanderCache: { [number]: WanderParams } = {}
local wanderCacheSize = 0

local function wanderParams(seed: number): WanderParams
	local cached = wanderCache[seed]
	if cached then
		return cached
	end
	local s = Balance.Spawn
	local params = {
		fx = Hash.range(s.WanderFreqMin, s.WanderFreqMax, seed, 1),
		fz = Hash.range(s.WanderFreqMin, s.WanderFreqMax, seed, 2),
		px = Hash.range(0, TAU, seed, 3),
		pz = Hash.range(0, TAU, seed, 4),
	}
	if wanderCacheSize >= WANDER_CACHE_MAX then
		table.clear(wanderCache)
		wanderCacheSize = 0
	end
	wanderCache[seed] = params
	wanderCacheSize += 1
	return params
end

-- Décalage XZ (Y = 0) d'un sauvage `dt` secondes après son apparition ; |x|, |z| ≤ amplitude
function SeededPath.wander(seed: number, dt: number): Vector3
	local key = math.floor(finiteOr(seed, 0))
	local t = finiteOr(dt, 0)
	local p = wanderParams(key)
	local a = Balance.Spawn.WanderAmplitude
	return Vector3.new(a * math.sin(p.fx * t + p.px), 0, a * math.sin(p.fz * t + p.pz))
end

-- ---------------------------------------------------------------------------------------------
-- Cordes des Gloomwisps (§4.15.4)
-- ---------------------------------------------------------------------------------------------

-- Angle (radians) du k-ième point d'arrivée (k = 0 : point de départ)
local function turnOf(seed: number, k: number): number
	return Hash.range(CHORD_MIN_TURN, TAU - CHORD_MIN_TURN, seed, WISP_SALT, k)
end

local function startAngle(seed: number): number
	return Hash.range(0, TAU, seed, WISP_SALT, 0, 0)
end

local function circlePoint(angle: number): Vector3
	local R = Balance.Wisps.PathRadius
	return Vector3.new(R * math.cos(angle), 0, R * math.sin(angle))
end

-- État d'une corde : corde n° k de `a0` à `a1`, commencée à `start` (secondes absolues)
type ChordState = {
	seed: number,
	t0: number,
	k: number,
	start: number,
	a0: number,
	a1: number,
	p0: Vector3,
	p1: Vector3,
	length: number,
	travel: number, -- durée du trajet (sans la pause)
}

local function makeChord(seed: number, t0: number, k: number, start: number, a0: number): ChordState
	local a1 = a0 + turnOf(seed, k + 1)
	local p0 = circlePoint(a0)
	local p1 = circlePoint(a1)
	local length = (p1 - p0).Magnitude
	return {
		seed = seed,
		t0 = t0,
		k = k,
		start = start,
		a0 = a0,
		a1 = a1,
		p0 = p0,
		p1 = p1,
		length = length,
		travel = length / Balance.Wisps.Speed,
	}
end

local function firstChord(seed: number, t0: number): ChordState
	return makeChord(seed, t0, 0, t0, startAngle(seed))
end

local function nextChord(c: ChordState): ChordState
	return makeChord(c.seed, c.t0, c.k + 1, c.start + c.travel + Balance.Wisps.Pause, c.a1)
end

local function direction(c: ChordState): Vector3
	if c.length <= 1e-9 then
		return Vector3.new(1, 0, 0)
	end
	return (c.p1 - c.p0) / c.length
end

-- Avance `c` jusqu'à la corde qui contient t (trajet + pause) ; borné pour rester sûr
local MAX_ADVANCE = 100000
local function advance(c: ChordState, t: number): ChordState
	local n = 0
	while t >= c.start + c.travel + Balance.Wisps.Pause and n < MAX_ADVANCE do
		c = nextChord(c)
		n += 1
	end
	return c
end

local function sampleChord(c: ChordState, t: number): (Vector3, Vector3)
	if t <= c.start then
		return c.p0, direction(c)
	end
	local elapsed = t - c.start
	if elapsed < c.travel then
		return c.p0 + (c.p1 - c.p0) * (elapsed / c.travel), direction(c)
	end
	-- pause à l'arrivée : on regarde déjà la corde suivante
	return c.p1, direction(nextChord(c))
end

-- Cache des curseurs internes de chordAt (une entrée par (seed, t0)), vidé au-delà de 256
local CHORD_CACHE_MAX = 256
local chordCache: { [string]: ChordState } = {}
local chordCacheSize = 0

function SeededPath.chordAt(seed: number, t0: number, t: number): (Vector3, Vector3)
	local s = math.floor(finiteOr(seed, 0))
	local start = finiteOr(t0, 0)
	local now = finiteOr(t, start)
	local key = `{s}:{start}`
	local c = chordCache[key]
	if c == nil or now < c.start then
		c = firstChord(s, start)
		if chordCache[key] == nil then
			if chordCacheSize >= CHORD_CACHE_MAX then
				table.clear(chordCache)
				chordCacheSize = 0
			end
			chordCacheSize += 1
		end
	end
	c = advance(c, now)
	chordCache[key] = c
	return sampleChord(c, now)
end

local CursorImpl = {}
CursorImpl.__index = CursorImpl

function CursorImpl.at(self: any, t: number): (Vector3, Vector3)
	local now = finiteOr(t, self.t0)
	if now < self.chord.start then
		self.chord = firstChord(self.seed, self.t0)
	end
	self.chord = advance(self.chord, now)
	return sampleChord(self.chord, now)
end

function CursorImpl.ahead(self: any, t: number, studs: number, count: number): { Vector3 }
	local n = math.max(0, math.floor(finiteOr(count, 0)))
	local out = table.create(n)
	if n == 0 then
		return out
	end
	local total = math.max(0, finiteOr(studs, 0))
	local position = self:at(t)
	local now = finiteOr(t, self.t0)
	local c: ChordState = self.chord
	-- distance déjà parcourue sur la corde courante (0 avant le départ, longueur pendant la pause)
	local done = math.clamp((now - c.start) / math.max(c.travel, 1e-9), 0, 1) * c.length
	for i = 1, n do
		local want = if n > 1 then total * (i - 1) / (n - 1) else 0
		if i == 1 then
			out[i] = position
		else
			-- on parcourt les cordes suivantes à partir de la position courante
			local walk = c
			local offset = done + want
			local guard = 0
			while offset > walk.length and guard < 64 do
				offset -= walk.length
				walk = nextChord(walk)
				guard += 1
			end
			local alpha = if walk.length > 1e-9 then offset / walk.length else 0
			out[i] = walk.p0 + (walk.p1 - walk.p0) * alpha
		end
	end
	return out
end

function SeededPath.newChordCursor(seed: number, t0: number): ChordCursor
	local s = math.floor(finiteOr(seed, 0))
	local start = finiteOr(t0, 0)
	return setmetatable({ seed = s, t0 = start, chord = firstChord(s, start) }, CursorImpl) :: any
end

-- ---------------------------------------------------------------------------------------------
-- Arc de la Comète (§9.4)
-- ---------------------------------------------------------------------------------------------

function SeededPath.cometSky(id: number, impact: Vector3, alpha: number): Vector3
	local key = math.floor(finiteOr(id, 0))
	local a = math.clamp(finiteOr(alpha, 0), 0, 1)
	local angle = Hash.range(0, TAU, key, SKY_SALT, 1)
	local distance = Hash.range(SKY_DISTANCE_MIN, SKY_DISTANCE_MAX, key, SKY_SALT, 2)
	local height = Hash.range(SKY_HEIGHT_MIN, SKY_HEIGHT_MAX, key, SKY_SALT, 3)
	local p0 = impact + Vector3.new(distance * math.cos(angle), height, distance * math.sin(angle))
	local p1 = (p0 + impact) / 2 + Vector3.new(0, height * SKY_CONTROL_LIFT, 0)
	local u = 1 - a
	return p0 * (u * u) + p1 * (2 * u * a) + impact * (a * a)
end

-- ---------------------------------------------------------------------------------------------
-- Dispersion (§4.7)
-- ---------------------------------------------------------------------------------------------

-- Point de dispersion du `index`-ième Nebby détaché (graine = id de coupe), même Y que l'origine
function SeededPath.scatterPoint(seed: number, index: number, origin: Vector3): Vector3
	local s = math.floor(finiteOr(seed, 0))
	local i = math.floor(finiteOr(index, 0))
	local snip = Balance.Snip
	local angle = Hash.range(0, TAU, s, SCATTER_SALT, i, 1)
	local distance = Hash.range(snip.ScatterMin, snip.ScatterMax, s, SCATTER_SALT, i, 2)
	return origin + Vector3.new(distance * math.cos(angle), 0, distance * math.sin(angle))
end

return SeededPath
