--!strict
-- LeapRules (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Géométrie du bond scripté (GDD §4.12) : 12 studs en 0,35 s sur un arc fixe, raccourci par le
-- premier solide (rayon contre WorldLayout.solids) ; point d'atterrissage identique côté client et
-- serveur (jamais la position que la physique a donnée) ; visée automatique sur la position future
-- de la créature (16 studs, ±40° autour du stick), hystérésis de 20 % ; capture à l'atterrissage.

export type AimCandidate = { id: number, posAt: (t: number) -> Vector3 }

local LeapRules = {}

-- Direction normalisée si les composantes sont finies et la norme dans [0,5 ; 1,5]
function LeapRules.validDir(dirX: number, dirZ: number): Vector3?
	local _ = { dirX, dirZ }
	error("TODO(logic): LeapRules.validDir")
end

-- Point d'atterrissage (raccourci devant le premier solide)
function LeapRules.landing(from: Vector3, dir: Vector3): Vector3
	local _ = { from, dir }
	error("TODO(logic): LeapRules.landing")
end

-- Point de l'arc à alpha dans [0 ; 1] (sommet 2,5 studs)
function LeapRules.arc(from: Vector3, to: Vector3, alpha: number): Vector3
	local _ = { from, to, alpha }
	error("TODO(logic): LeapRules.arc")
end

-- Créature visée (id) ou nil (bond droit devant)
function LeapRules.aim(
	origin: Vector3,
	stick: Vector3,
	candidates: { AimCandidate },
	now: number,
	current: number?
): number?
	local _ = { origin, stick, candidates, now, current }
	error("TODO(logic): LeapRules.aim")
end

-- Capture automatique (5 studs, 8 pour le propriétaire de sa fuite du Rush ; + tolérance côté serveur)
function LeapRules.catchesOnLanding(landing: Vector3, creaturePos: Vector3, isOwner: boolean): boolean
	local _ = { landing, creaturePos, isOwner }
	error("TODO(logic): LeapRules.catchesOnLanding")
end

return LeapRules
