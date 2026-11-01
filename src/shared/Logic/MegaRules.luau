--!strict
-- MegaRules (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- MEGA SQUISH (GDD §4.22) : objectif adapté au nombre de joueurs et indulgence après échec, paliers
-- de bébés, fenêtre PERFECT du géant (décalée vers le tard), espèce de la semaine en rotation.

local MegaRules = {}

-- ceil((30 + 50 × N) × indulgence)
function MegaRules.target(players: number, failStreak: number): number
	local _ = { players, failStreak }
	error("TODO(logic): MegaRules.target")
end

-- 1 ; 0,8 après un échec ; 0,65 après 2 échecs de suite
function MegaRules.leniency(failStreak: number): number
	local _ = { failStreak }
	error("TODO(logic): MegaRules.leniency")
end

-- Paliers : ≥ 10 → 1 ; ≥ 40 → 2 ; ≥ 80 → 3
function MegaRules.babiesFor(points: number): number
	local _ = { points }
	error("TODO(logic): MegaRules.babiesFor")
end

-- Fenêtre [−0,12 ; +0,28] s autour du sommet (période 2 s)
function MegaRules.isPerfect(landsAt: number, t: number): boolean
	local _ = { landsAt, t }
	error("TODO(logic): MegaRules.isPerfect")
end

-- ((semaine + n) mod 24) + 1, Secrets exclus
function MegaRules.species(week: number, indexInWeek: number): number
	local _ = { week, indexInWeek }
	error("TODO(logic): MegaRules.species")
end

return MegaRules
