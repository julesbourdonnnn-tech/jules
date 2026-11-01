--!strict
-- TargetRules (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Choix de la cible par le jeu (GDD §10.4), pur et testable : score = distance + 6 × (angle ÷ 90°),
-- prêts avant ceux en recharge pour □, hystérésis (1,5 stud ou 0,25 s), passage au prochain prêt
-- après une pression (0,15 s), cycle L1 / R1 par angle, clic souris par projection à l'écran
-- (rayon max(32 px TV, rayon projeté × 1,2)), cible fixée 4 s par un clic.

export type Candidate = { id: string, pos: Vector3, ready: boolean }
export type Projected = { id: string, screen: Vector2, radius: number, depth: number }

local TargetRules = {}

-- Score d'un candidat (plus petit = meilleur)
function TargetRules.score(origin: Vector3, look: Vector3, pos: Vector3): number
	local _ = { origin, look, pos }
	error("TODO(logic): TargetRules.score")
end

-- Cible retenue (id)
function TargetRules.pick(
	origin: Vector3,
	look: Vector3,
	candidates: { Candidate },
	current: string?,
	now: number,
	since: number
): string?
	local _ = { origin, look, candidates, current, now, since }
	error("TODO(logic): TargetRules.pick")
end

-- Cible suivante (dir = 1) ou précédente (−1) par angle, de gauche à droite
function TargetRules.cycle(
	origin: Vector3,
	look: Vector3,
	candidates: { Candidate },
	current: string?,
	dir: number
): string?
	local _ = { origin, look, candidates, current, dir }
	error("TODO(logic): TargetRules.cycle")
end

-- Prochain squishy prêt après une pression
function TargetRules.afterPress(
	origin: Vector3,
	look: Vector3,
	candidates: { Candidate },
	pressed: string
): string?
	local _ = { origin, look, candidates, pressed }
	error("TODO(logic): TargetRules.afterPress")
end

-- Candidat désigné par la souris (projection écran, jamais un rayon)
function TargetRules.screenPick(pointer: Vector2, projected: { Projected }, scale: number): string?
	local _ = { pointer, projected, scale }
	error("TODO(logic): TargetRules.screenPick")
end

return TargetRules
