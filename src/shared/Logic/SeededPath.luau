--!strict
-- SeededPath (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Trajets des créatures, déterministes (GDD §4.11, §4.21.2, §12.5) : le serveur ne diffuse que la
-- graine, l'instant de départ et le point de départ ; serveur et clients calculent la même pos(t).
-- escape : premier bond de 20 studs à l'opposé du boopeur, puis marche au hasard sur le graphe des
-- rues sans demi-tour immédiat, v(t) = 16 − 0,32 × (t − t0) bornée à 8, bonds de 0,45 s ; jamais dans
-- un ranch (propriétés : 10 000 trajets, aucun point hors graphe ni dans un rectangle de ranch).
-- hopAround : fuite personnelle (bonds de 4,5 studs toutes les 0,5 s, pause 0,6 s tous les 3, à 35
-- studs au plus de la Fontaine). golden : 14 → 10 studs/s. demo : Big Plop, 8 studs/s.

local Types = require(script.Parent.Parent.Types)

-- pos(t) : position au sol et vrai si la créature est en l'air (bond, visuel seulement)
export type PathFn = (t: number) -> (Vector3, boolean)

local SeededPath = {}

-- Fuite du Rush, Wild Wobbler
function SeededPath.escape(
	seed: number,
	t0: number,
	startNode: number,
	awayAngle: number,
	speed: number?
): PathFn
	local _ = { seed, t0, startNode, awayAngle, speed }
	error("TODO(logic): SeededPath.escape")
end

-- Créature en fuite personnelle autour de sa Fontaine
function SeededPath.hopAround(seed: number, t0: number, center: Vector3, radius: number): PathFn
	local _ = { seed, t0, center, radius }
	error("TODO(logic): SeededPath.hopAround")
end

-- Golden Wobbler (30 s)
function SeededPath.golden(seed: number, t0: number, startNode: number): PathFn
	local _ = { seed, t0, startNode }
	error("TODO(logic): SeededPath.golden")
end

-- Démonstration de Big Plop (20 s)
function SeededPath.demo(seed: number, t0: number, start: Vector3): PathFn
	local _ = { seed, t0, start }
	error("TODO(logic): SeededPath.demo")
end

-- Trajet d'une créature diffusée (dispatch selon kind et path)
function SeededPath.fromSpawn(spawn: Types.ChaseSpawn): PathFn
	local _ = { spawn }
	error("TODO(logic): SeededPath.fromSpawn")
end

return SeededPath
