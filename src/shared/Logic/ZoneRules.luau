--!strict
-- ZoneRules (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Zones vérifiées par le serveur sur la position VALIDÉE (GDD §4.6, §4.8, §6.3, §4.22) : dalles
-- (entrée ≤ 2,5 studs, sortie > 3,5, un achat par entrée), Pot (5), bol (8), Bassin (12), MEGA (20),
-- clôture côté rue (boop 8, pet-sitting 10, propriétaire proche 25), intrus, Autel de la Lune.
-- Jamais d'événement physique Touched.

local ZoneRules = {}

-- (dedans, vient d'entrer) avec l'hystérésis 2,5 / 3,5
function ZoneRules.padStep(wasInside: boolean, distance: number): (boolean, boolean)
	local _ = { wasInside, distance }
	error("TODO(logic): ZoneRules.padStep")
end

-- Position à radius studs d'un objet du ranch (WorldLayout.anchor)
function ZoneRules.near(slot: number, anchor: string, pos: Vector3, radius: number): boolean
	local _ = { slot, anchor, pos, radius }
	error("TODO(logic): ZoneRules.near")
end

-- À 20 studs du centre du MEGA pad
function ZoneRules.inMegaZone(pos: Vector3): boolean
	local _ = { pos }
	error("TODO(logic): ZoneRules.inMegaZone")
end

-- Côté rue de la clôture du ranch, à radius studs d'une place de clôture
function ZoneRules.streetSideOfFence(slot: number, pos: Vector3, radius: number): boolean
	local _ = { slot, pos, radius }
	error("TODO(logic): ZoneRules.streetSideOfFence")
end

-- Propriétaire à 25 studs de sa clôture (boop plus long)
function ZoneRules.ownerNearFence(slot: number, pos: Vector3): boolean
	local _ = { slot, pos }
	error("TODO(logic): ZoneRules.ownerNearFence")
end

-- Ranch d'un autre où se trouve cette position (0 = aucun)
function ZoneRules.intruder(ownerSlot: number, pos: Vector3): number
	local _ = { ownerSlot, pos }
	error("TODO(logic): ZoneRules.intruder")
end

-- Présence à l'Autel de la Lune
function ZoneRules.atAltar(pos: Vector3): boolean
	local _ = { pos }
	error("TODO(logic): ZoneRules.atAltar")
end

return ZoneRules
