--!strict
-- SnipRules — paquet « logic » (docs/04-architecture.md §12.1).
-- Ordre d'évaluation UNIQUE des règles de coupe (GDD §4.7), testé règle par règle. Pur : l'état
-- (recharges, immunités, équipages…) est fourni par CongaService à chaque appel.
--   * blockReason(input) : première règle qui bloque la paire coupeur → victime, dans cet ordre :
--       "truce" (Balise) · "disabled" (serveur privé sans coupe) · "self" · "crew" · "zen" ·
--       "rookie" (victime sous bouclier) · "immune" (8 s) · "perMinute" (2 coupes / 60 s glissantes :
--       immunité jusqu'à 60 s après la 1re) · "snipperCooldown" (1,5 s, pas pour un Gloomwisp) ·
--       "pairCooldown" (20 s) · "flagged" (coupeur en infraction de mouvement ce tick) → nil = autorisé
--     Gloomwisp (isWisp, snipper = nil) : ni "self", ni "crew", ni "snipperCooldown", ni "flagged" ;
--     Zen (de la victime), bouclier, immunité, plafond par minute et pairCooldown (si fourni)
--     s'appliquent. Une coupe de joueur sans `snipper` est refusée ("self").
--   * findCut(input) : test BALAYÉ — pour k = G+1 … n, segment k = [nœud k−1, nœud k] (nœud 0 =
--     tête), ignore les nœuds escortés (nœud k) et les points touchés dans un port sûr, distance
--     segment-segment XZ (Trail.segmentDistanceXZ) ≤ rayon et |Δy| ≤ MaxDy → premier k (le plus
--     près de la tête) et le point touché ; élagage préalable par boîtes englobantes
--   * lossCap(n) = max(6, floor(0,35 n)) ; cutFrom(k, n) = max(k, n − lossCap(n) + 1)
--   * applyCut : nouvelles immunités de la victime (8 s ; plafond par minute)
--   * radius(touch, isWisp) : 2,8 (+0,3 tactile) ; 2,5 pour un Gloomwisp
-- GDD : §4.7 (constantes, pseudo-code), §4.15.4 (Gloomwisps), §4.16, §6.1 (escorte), §12.4, §12.9.
-- Dépendances : Config/Balance, Logic/Trail.

local Balance = require(script.Parent.Parent.Config.Balance)
local Trail = require(script.Parent.Trail)

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

local Snip = Balance.Snip

-- Nombre de coupes subies dans la fenêtre glissante ]now − MinuteWindow ; now]
local function recentCount(now: number, recent: { number }): number
	local n = 0
	if type(recent) ~= "table" then
		return 0
	end
	for _, t in ipairs(recent) do
		if type(t) == "number" and t > now - Snip.MinuteWindow and t <= now then
			n += 1
		end
	end
	return n
end

-- Instant (ou nil) où l'immunité du plafond par minute prend fin : 60 s après la plus ancienne
-- coupe de la fenêtre, si le plafond est atteint
local function perMinuteUntil(now: number, recent: { number }): number?
	if recentCount(now, recent) < Snip.MaxPerMinute then
		return nil
	end
	local oldest = math.huge
	for _, t in ipairs(recent) do
		if type(t) == "number" and t > now - Snip.MinuteWindow and t <= now and t < oldest then
			oldest = t
		end
	end
	return oldest + Snip.MinuteWindow
end

-- Raison du blocage ou nil si la coupe est possible
function SnipRules.blockReason(input: PairInput): string?
	local now = input.now
	if input.truce then
		return "truce"
	end
	if input.snipsDisabled then
		return "disabled"
	end
	local snipper = input.snipper
	local victim = input.victim
	if not input.isWisp then
		if snipper == nil or victim == nil or snipper.userId == victim.userId then
			return "self"
		end
		if snipper.crewId ~= 0 and snipper.crewId == victim.crewId then
			return "crew"
		end
	end
	if victim == nil then
		return "self" -- entrée malformée : jamais de coupe
	end
	if victim.zen or (not input.isWisp and snipper ~= nil and snipper.zen) then
		return "zen"
	end
	if victim.rookie then
		return "rookie"
	end
	if now < input.victimImmuneUntil then
		return "immune"
	end
	if recentCount(now, input.victimRecent) >= Snip.MaxPerMinute then
		return "perMinute"
	end
	if not input.isWisp and now < input.snipperCooldownUntil then
		return "snipperCooldown"
	end
	if now < input.pairCooldownUntil then
		return "pairCooldown"
	end
	if not input.isWisp and input.snipperFlagged then
		return "flagged"
	end
	return nil
end

-- Immunité de la victime à `now` (8 s ou plafond par minute)
function SnipRules.isImmune(now: number, immuneUntil: number, recent: { number }): boolean
	return now < immuneUntil or recentCount(now, recent) >= Snip.MaxPerMinute
end

function SnipRules.radius(touch: boolean, isWisp: boolean): number
	if isWisp then
		return Snip.WispRadius
	end
	return Snip.Radius + (if touch then Snip.TouchAssist else 0)
end

function SnipRules.lossCap(n: number): number
	local count = if n == n and n > 0 then math.floor(n) else 0
	return math.max(Snip.LossCapMin, math.floor(Snip.LossCapRatio * count))
end

-- Premier nœud détaché : le point de coupe recule vers la queue si la perte dépasse le plafond
function SnipRules.cutFrom(k: number, n: number): number
	return math.max(k, n - SnipRules.lossCap(n) + 1)
end

-- Élagage : la boîte XZ du balayage (élargie du rayon) touche-t-elle la boîte des nœuds
-- nodes[max(1, firstIndex)] … nodes[#nodes] ?
function SnipRules.boundsOverlap(
	from: Vector3,
	to: Vector3,
	radius: number,
	nodes: { Vector3 },
	firstIndex: number
): boolean
	local first = if firstIndex == firstIndex then math.max(1, math.floor(firstIndex)) else 1
	local count = #nodes
	if first > count then
		return false
	end
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for i = first, count do
		local p = nodes[i]
		if p.X < minX then
			minX = p.X
		end
		if p.X > maxX then
			maxX = p.X
		end
		if p.Z < minZ then
			minZ = p.Z
		end
		if p.Z > maxZ then
			maxZ = p.Z
		end
	end
	local r = if radius == radius then math.max(0, radius) else 0
	local sMinX = math.min(from.X, to.X) - r
	local sMaxX = math.max(from.X, to.X) + r
	local sMinZ = math.min(from.Z, to.Z) - r
	local sMaxZ = math.max(from.Z, to.Z) + r
	return sMaxX >= minX and sMinX <= maxX and sMaxZ >= minZ and sMinZ <= maxZ
end

-- (k, point touché) du premier segment coupé, ou nil
function SnipRules.findCut(input: CutInput): (number?, Vector3?)
	local nodes = input.nodes
	local n = #nodes
	local guard = if input.guard == input.guard then math.max(0, math.floor(input.guard)) else 0
	local firstSegment = guard + 1
	if n < firstSegment then
		return nil, nil
	end
	-- segment k = [nœud k − 1, nœud k] : la boîte commence au nœud G (la tête si G = 0)
	if guard >= 1 then
		if not SnipRules.boundsOverlap(input.from, input.to, input.radius, nodes, guard) then
			return nil, nil
		end
	elseif
		not SnipRules.boundsOverlap(input.from, input.to, input.radius, nodes, 1)
		and not SnipRules.boundsOverlap(input.from, input.to, input.radius, { input.head }, 1)
	then
		return nil, nil
	end
	local isEscorted = input.isEscorted
	local inHarbor = input.inHarbor
	local function skip(k: number, point: Vector3): boolean
		if isEscorted and isEscorted(k, nodes[k]) then
			return true
		end
		if inHarbor and inHarbor(point) then
			return true
		end
		return false
	end
	-- segment 1 = [tête, nœud 1] (seulement sans Guard Links)
	if firstSegment <= 1 then
		local k, point = Trail.findCutSwept(
			{ input.head, nodes[1] },
			input.from,
			input.to,
			input.radius,
			2,
			input.maxDy,
			function(_k, p)
				return skip(1, p)
			end
		)
		if k then
			return 1, point
		end
	end
	return Trail.findCutSwept(
		nodes,
		input.from,
		input.to,
		input.radius,
		math.max(2, firstSegment),
		input.maxDy,
		skip
	)
end

-- Après une coupe subie à `now` : (nouvel immuneUntil, nouvelle liste recent purgée).
-- immuneUntil = max(actuel, now + 8 s) et, si le plafond par minute est atteint, jusqu'à 60 s
-- après la plus ancienne coupe de la fenêtre.
function SnipRules.applyCut(now: number, immuneUntil: number, recent: { number }): (number, { number })
	local kept: { number } = {}
	if type(recent) == "table" then
		for _, t in ipairs(recent) do
			if type(t) == "number" and t > now - Snip.MinuteWindow and t <= now then
				table.insert(kept, t)
			end
		end
	end
	table.insert(kept, now)
	local current = if immuneUntil == immuneUntil then immuneUntil else 0
	local untilTime = math.max(current, now + Snip.VictimImmunity)
	local capUntil = perMinuteUntil(now, kept)
	if capUntil then
		untilTime = math.max(untilTime, capUntil)
	end
	return untilTime, kept
end

return SnipRules
