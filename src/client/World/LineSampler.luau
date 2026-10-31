--!strict
-- LineSampler — aide du paquet « client-world » : positions des nœuds d'une file (GDD §4.6, §12.4).
--   * sample : même règle que Trail.sample (nœud i à HeadGap + (i − 1) × Spacing derrière le point
--     le plus récent, abscisse curviligne, nœuds en trop empilés au bout le plus ancien), sans
--     allouer : la liste de sortie est réutilisée d'une image à l'autre
--   * stitch : raccord du premier tronçon à la position AFFICHÉE du personnage (files des autres) :
--     décalage pondéré qui s'annule à `length` studs de la tête ; au-delà (nœuds coupables),
--     les nœuds restent exactement sur le chemin serveur
-- Pur (Vector3 seulement) : testé sous Lune.

local LineSampler = {}

type PointList = { Vector3 }

local EMPTY: PointList = {}

-- Remplit `out` avec `count` positions échantillonnées sur `points` (du plus ancien au plus récent)
function LineSampler.sample(
	points: PointList?,
	count: number,
	spacing: number,
	firstGap: number,
	out: PointList
): PointList
	table.clear(out)
	local list = points or EMPTY
	local n = #list
	if count <= 0 or n == 0 then
		return out
	end
	if n == 1 then
		for i = 1, count do
			out[i] = list[1]
		end
		return out
	end
	local target = firstGap
	local walked = 0
	local index = n
	local i = 1
	while i <= count and index > 1 do
		local a = list[index]
		local b = list[index - 1]
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
	local tail = list[1]
	while i <= count do
		out[i] = tail
		i += 1
	end
	return out
end

-- Décale les nœuds proches de la tête vers la position affichée `shown` (XZ seulement) :
-- poids 1 − s / length, où s = abscisse du nœud (HeadGap + (i − 1) × Spacing)
function LineSampler.stitch(
	positions: PointList,
	head: Vector3,
	shown: Vector3,
	spacing: number,
	firstGap: number,
	length: number
)
	local dx = shown.X - head.X
	local dz = shown.Z - head.Z
	if dx == 0 and dz == 0 then
		return
	end
	for i, p in positions do
		local s = firstGap + (i - 1) * spacing
		if s >= length then
			break
		end
		local w = 1 - s / length
		positions[i] = Vector3.new(p.X + dx * w, p.Y, p.Z + dz * w)
	end
end

return LineSampler
