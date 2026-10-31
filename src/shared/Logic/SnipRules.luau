--!strict
-- SnipRules — paquet « logic » (STUB du contrat : docs/04-architecture.md §12.1).
-- Ordre d'évaluation UNIQUE des règles de coupe (GDD §4.7), testé règle par règle. Pur : l'état
-- (recharges, immunités, équipages…) est fourni par CongaService à chaque appel.
-- Responsabilités :
--   * blockReason(input) : première règle qui bloque la paire coupeur → victime, dans cet ordre :
--       "truce" (Balise) · "disabled" (serveur privé sans coupe) · "self" · "crew" · "zen" ·
--       "rookie" (victime sous bouclier) · "immune" (8 s) · "perMinute" (2 coupes / 60 s glissantes :
--       immunité jusqu'à 60 s après la 1re) · "snipperCooldown" (1,5 s, pas pour un Gloomwisp) ·
--       "pairCooldown" (20 s) · "flagged" (coupeur en infraction de mouvement ce tick) → nil = autorisé
--   * findCut(input) : test BALAYÉ — pour k = G+1 … n, segment k = [nœud k−1, nœud k],
--     ignore les nœuds escortés et les points touchés dans un port sûr, distance segment-segment
--     XZ (Trail.segmentDistanceXZ) ≤ rayon et |Δy| ≤ MaxDy → premier k (le plus près de la tête)
--     et le point touché ; élagage préalable par boîtes englobantes
--   * lossCap(n) = max(6, floor(0,35 n)) ; cutFrom(k, n) = max(k, n − lossCap(n) + 1)
--   * applyCut : nouvelles immunités de la victime (8 s ; plafond par minute)
--   * radius(touch, isWisp) : 2,8 (+0,3 tactile) ; 2,5 pour un Gloomwisp
-- GDD : §4.7 (constantes, pseudo-code), §4.15.4 (Gloomwisps), §4.16, §6.1 (escorte), §12.4,
-- §12.9 (SnipRules.spec : chaque règle isolément et combinée).
-- Dépendances : Config/Balance, Logic/Trail.

local SnipRules = {}

export type Party = {
	userId: number,
	crewId: number, -- 0 = aucun
	zen: boolean,
	rookie: boolean,
}

export type PairInput = {
	now: number,
	truce: boolean,
	snipsDisabled: boolean,
	isWisp: boolean,
	snipper: Party?, -- nil pour un Gloomwisp
	victim: Party,
	snipperCooldownUntil: number,
	pairCooldownUntil: number,
	victimImmuneUntil: number,
	victimRecent: { number }, -- instants des coupes subies (fenêtre glissante)
	snipperFlagged: boolean,
}

export type CutInput = {
	nodes: { Vector3 }, -- positions des nœuds 1 … n (nœud 1 à HeadGap de la tête)
	head: Vector3, -- tête de la file (nœud 0)
	from: Vector3, -- position précédente du coupeur
	to: Vector3, -- position actuelle du coupeur
	radius: number,
	maxDy: number,
	guard: number, -- Guard Links (premiers nœuds jamais coupables)
	isEscorted: ((nodeIndex: number, pos: Vector3) -> boolean)?,
	inHarbor: ((pos: Vector3) -> boolean)?,
}

-- Raison du blocage ou nil si la coupe est possible
function SnipRules.blockReason(_input: PairInput): string?
	error("TODO(logic): SnipRules.blockReason")
end

-- Immunité de la victime à `now` (8 s ou plafond par minute)
function SnipRules.isImmune(_now: number, _immuneUntil: number, _recent: { number }): boolean
	error("TODO(logic): SnipRules.isImmune")
end

function SnipRules.radius(_touch: boolean, _isWisp: boolean): number
	error("TODO(logic): SnipRules.radius")
end

function SnipRules.lossCap(_n: number): number
	error("TODO(logic): SnipRules.lossCap")
end

function SnipRules.cutFrom(_k: number, _n: number): number
	error("TODO(logic): SnipRules.cutFrom")
end

-- Élagage : la boîte du balayage (élargie du rayon) touche-t-elle la boîte des nœuds coupables ?
function SnipRules.boundsOverlap(
	_from: Vector3,
	_to: Vector3,
	_radius: number,
	_nodes: { Vector3 },
	_firstIndex: number
): boolean
	error("TODO(logic): SnipRules.boundsOverlap")
end

-- (k, point touché) du premier segment coupé, ou nil
function SnipRules.findCut(_input: CutInput): (number?, Vector3?)
	error("TODO(logic): SnipRules.findCut")
end

-- Après une coupe subie à `now` : (nouvel immuneUntil, nouvelle liste recent purgée)
function SnipRules.applyCut(_now: number, _immuneUntil: number, _recent: { number }): (number, { number })
	error("TODO(logic): SnipRules.applyCut")
end

return SnipRules
