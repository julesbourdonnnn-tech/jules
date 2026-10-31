--!strict
-- PathCodec — paquet « conga » (docs/04-architecture.md §10.4).
-- Codec binaire du flux de miettes PathStream (UnreliableRemoteEvent, 10 Hz), aussi utilisé par
-- PathSnapshot et WorldSnapshot.paths. Pur (buffer + Vector3), testé aller-retour sous Lune.
--
-- FORMAT (little-endian, module `buffer`) :
--   u16 tick                      compteur de ticks serveur modulo 65536 (ordre des paquets)
--   u8  runCount                  nombre de runs (≤ 255)
--   puis pour chaque run :
--     u8  slot                    index du Nid 1-12
--     u32 firstSeq                numéro de séquence du premier point du run
--     u8  n                       nombre de points (1-255)
--     i16 x×8, i16 y×8, i16 z×8   premier point absolu (arrondi au 1/8 de stud)
--     (n − 1) × [i8 dx×16, i8 dy×16, i8 dz×16]   deltas depuis le point QUANTIFIÉ précédent
-- Un même slot peut apparaître dans plusieurs runs consécutifs (seq contigus) : un delta hors de
-- [−127, 127] (déplacement > 7,9 studs sur un axe entre deux miettes) ouvre un nouveau run absolu.
-- Les positions décodées sont les positions quantifiées (pas de dérive : chaque delta est calculé
-- contre la reconstruction du point précédent, pas contre le point exact).
-- Responsabilités : encode/decode, split (découpe en runs encodables), taille estimée.
--   * encode et split partagent EXACTEMENT la même quantification (arrondi au plus proche,
--     reconstruction en double précision) : un run produit par split est toujours encodable
--   * decode vérifie chaque lecture : buffer tronqué, slot 0, run vide ou octets en trop → erreur
--     (l'appelant protège par pcall)
-- GDD : §12.4 (≈ 25 octets par joueur en mouvement), §12.9.
-- Dépendances : Shared/Types.

local Types = require(script.Parent.Parent.Types)

local PathCodec = {}

PathCodec.MAX_POINTS = 255
PathCodec.MAX_RUNS = 255
PathCodec.ABS_SCALE = 8
PathCodec.DELTA_SCALE = 16
PathCodec.HEADER_BYTES = 3 -- u16 tick + u8 runCount
PathCodec.RUN_HEADER_BYTES = 12 -- u8 slot + u32 firstSeq + u8 n + 3 × i16
PathCodec.DELTA_BYTES = 3

-- Bornes des entiers du format
local I16_MIN, I16_MAX = -32768, 32767
local DELTA_LIMIT = 127 -- deltas symétriques dans [−127 ; 127]
local U8_MAX = 255
local U32_MAX = 4294967295
local TICK_MODULO = 65536

-- ---------------------------------------------------------------------------------------------
-- Quantification (partagée par split et encode)
-- ---------------------------------------------------------------------------------------------

-- Nombre fini, sinon 0 (une position illisible ne fait jamais échouer le flux)
local function finite(x: number): number
	if x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return x
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

-- Coordonnée absolue quantifiée (i16, 1/8 de stud)
local function quantAbs(x: number): number
	return math.clamp(round(finite(x) * PathCodec.ABS_SCALE), I16_MIN, I16_MAX)
end

-- Delta quantifié (1/16 de stud) de `x` depuis la reconstruction `prev` ; peut déborder d'un i8
local function quantDelta(x: number, prev: number): number
	return round((finite(x) - prev) * PathCodec.DELTA_SCALE)
end

local function fits(d: number): boolean
	return d >= -DELTA_LIMIT and d <= DELTA_LIMIT
end

-- Taille en octets d'un run de `count` points
local function runBytes(count: number): number
	return PathCodec.RUN_HEADER_BYTES + PathCodec.DELTA_BYTES * math.max(0, count - 1)
end

-- ---------------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------------

-- Taille en octets du buffer qu'encode() produirait
function PathCodec.size(runs: { Types.PathEntry }): number
	local total = PathCodec.HEADER_BYTES
	for _, run in runs do
		total += runBytes(#run.points)
	end
	return total
end

-- Découpe une suite de points (numérotés à partir de firstSeq) en runs encodables
-- (≤ MAX_POINTS points, deltas dans [−127, 127] après quantification)
function PathCodec.split(slot: number, firstSeq: number, points: { Vector3 }): { Types.PathEntry }
	local runs: { Types.PathEntry } = {}
	local current: { Vector3 }? = nil
	local px, py, pz = 0, 0, 0
	for i, p in points do
		local open = true
		local dx, dy, dz = 0, 0, 0
		if current ~= nil and #current < PathCodec.MAX_POINTS then
			dx = quantDelta(p.X, px)
			dy = quantDelta(p.Y, py)
			dz = quantDelta(p.Z, pz)
			open = not (fits(dx) and fits(dy) and fits(dz))
		end
		if open or current == nil then
			local list = { p }
			current = list
			table.insert(runs, { slot = slot, firstSeq = firstSeq + i - 1, points = list })
			px = quantAbs(p.X) / PathCodec.ABS_SCALE
			py = quantAbs(p.Y) / PathCodec.ABS_SCALE
			pz = quantAbs(p.Z) / PathCodec.ABS_SCALE
		else
			table.insert(current, p)
			px += dx / PathCodec.DELTA_SCALE
			py += dy / PathCodec.DELTA_SCALE
			pz += dz / PathCodec.DELTA_SCALE
		end
	end
	return runs
end

-- Encode des runs (déjà découpés par split) dans un buffer. Des runs invalides (vides, trop
-- longs, delta hors i8, slot ou seq hors bornes) sont une erreur de programmation : erreur.
function PathCodec.encode(tick: number, runs: { Types.PathEntry }): buffer
	if #runs > PathCodec.MAX_RUNS then
		error(`PathCodec.encode : au plus {PathCodec.MAX_RUNS} runs (reçu {#runs})`, 2)
	end
	local buf = buffer.create(PathCodec.size(runs))
	buffer.writeu16(buf, 0, math.floor(finite(tick)) % TICK_MODULO)
	buffer.writeu8(buf, 2, #runs)
	local o = PathCodec.HEADER_BYTES
	for _, run in runs do
		local points = run.points
		local n = #points
		local slot = run.slot
		local seq = run.firstSeq
		if n < 1 or n > PathCodec.MAX_POINTS then
			error(`PathCodec.encode : run de 1 à {PathCodec.MAX_POINTS} points attendu (reçu {n})`, 2)
		end
		if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > U8_MAX then
			error(`PathCodec.encode : slot invalide ({tostring(slot)})`, 2)
		end
		if type(seq) ~= "number" or seq % 1 ~= 0 or seq < 0 or seq > U32_MAX then
			error(`PathCodec.encode : firstSeq invalide ({tostring(seq)})`, 2)
		end
		buffer.writeu8(buf, o, slot)
		buffer.writeu32(buf, o + 1, seq)
		buffer.writeu8(buf, o + 5, n)
		local first = points[1]
		local qx, qy, qz = quantAbs(first.X), quantAbs(first.Y), quantAbs(first.Z)
		buffer.writei16(buf, o + 6, qx)
		buffer.writei16(buf, o + 8, qy)
		buffer.writei16(buf, o + 10, qz)
		o += PathCodec.RUN_HEADER_BYTES
		local px = qx / PathCodec.ABS_SCALE
		local py = qy / PathCodec.ABS_SCALE
		local pz = qz / PathCodec.ABS_SCALE
		for i = 2, n do
			local p = points[i]
			local dx, dy, dz = quantDelta(p.X, px), quantDelta(p.Y, py), quantDelta(p.Z, pz)
			if not (fits(dx) and fits(dy) and fits(dz)) then
				error("PathCodec.encode : delta hors de [−127, 127] (découper avec PathCodec.split)", 2)
			end
			buffer.writei8(buf, o, dx)
			buffer.writei8(buf, o + 1, dy)
			buffer.writei8(buf, o + 2, dz)
			o += PathCodec.DELTA_BYTES
			px += dx / PathCodec.DELTA_SCALE
			py += dy / PathCodec.DELTA_SCALE
			pz += dz / PathCodec.DELTA_SCALE
		end
	end
	return buf
end

-- Décode un buffer → (tick, runs). Un buffer tronqué ou incohérent lève une erreur
-- (l'appelant protège par pcall : les données client/serveur ne sont jamais crues aveuglément).
function PathCodec.decode(buf: buffer): (number, { Types.PathEntry })
	if typeof(buf) ~= "buffer" then
		error("PathCodec.decode : buffer attendu", 2)
	end
	local len = buffer.len(buf)
	local o = 0
	local function need(bytes: number)
		if o + bytes > len then
			error(`PathCodec.decode : buffer tronqué ({len} octets, {o + bytes} attendus)`, 3)
		end
	end
	need(PathCodec.HEADER_BYTES)
	local tick = buffer.readu16(buf, 0)
	local runCount = buffer.readu8(buf, 2)
	o = PathCodec.HEADER_BYTES
	local runs: { Types.PathEntry } = table.create(runCount)
	for _ = 1, runCount do
		need(PathCodec.RUN_HEADER_BYTES)
		local slot = buffer.readu8(buf, o)
		local firstSeq = buffer.readu32(buf, o + 1)
		local n = buffer.readu8(buf, o + 5)
		if slot == 0 then
			error("PathCodec.decode : slot 0 (incohérent)", 2)
		end
		if n == 0 then
			error("PathCodec.decode : run vide (incohérent)", 2)
		end
		local px = buffer.readi16(buf, o + 6) / PathCodec.ABS_SCALE
		local py = buffer.readi16(buf, o + 8) / PathCodec.ABS_SCALE
		local pz = buffer.readi16(buf, o + 10) / PathCodec.ABS_SCALE
		o += PathCodec.RUN_HEADER_BYTES
		need(PathCodec.DELTA_BYTES * (n - 1))
		local points: { Vector3 } = table.create(n)
		points[1] = Vector3.new(px, py, pz)
		for i = 2, n do
			px += buffer.readi8(buf, o) / PathCodec.DELTA_SCALE
			py += buffer.readi8(buf, o + 1) / PathCodec.DELTA_SCALE
			pz += buffer.readi8(buf, o + 2) / PathCodec.DELTA_SCALE
			o += PathCodec.DELTA_BYTES
			points[i] = Vector3.new(px, py, pz)
		end
		table.insert(runs, { slot = slot, firstSeq = firstSeq, points = points })
	end
	if o ~= len then
		error(`PathCodec.decode : {len - o} octet(s) en trop (incohérent)`, 2)
	end
	return tick, runs
end

return PathCodec
