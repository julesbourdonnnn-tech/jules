--!strict
-- TargetRules (paquet logic, docs/04 §12.1). Choix de la cible par le jeu (GDD §10.4), pur et
-- testable : score = distance + 6 × (angle ÷ 90°) à plat, prêts avant ceux en recharge pour □,
-- hystérésis (la cible change si une autre est meilleure de 1,5 stud, ou 0,25 s après le dernier
-- changement), passage au prochain prêt après une pression, cycle L1 / R1 par angle de gauche à
-- droite, clic souris par projection à l'écran (rayon max(32 px TV × échelle, rayon projeté × 1,2)).
-- Toute entrée bizarre (NaN, position manquante) écarte le candidat : jamais d'erreur.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, typeof, math, table = type, typeof, math, table

local Layout = require(script.Parent.Parent.Config.Layout)

export type Candidate = { id: string, pos: Vector3, ready: boolean }
export type Projected = { id: string, screen: Vector2, radius: number, depth: number }

local TargetRules = {}

local ANGLE_WEIGHT = 6 -- studs ajoutés pour 90° d'écart (GDD §10.4)
local SWITCH_MARGIN = 1.5 -- studs
local SWITCH_DELAY = 0.25 -- s
-- Clic souris (Config/Layout.ClickTarget) : rayon minimal en px TV et facteur du rayon projeté
local CLICK_MIN_RADIUS = Layout.ClickTarget.MinRadius
local CLICK_RADIUS_MULT = Layout.ClickTarget.RadiusFactor

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function usable(v: any): boolean
	return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function validCandidate(c: any): boolean
	return type(c) == "table" and type(c.id) == "string" and usable(c.pos)
end

-- Direction du regard à plat (unitaire) ou nil
local function flatLook(look: any): (number?, number?)
	if not usable(look) then
		return nil, nil
	end
	local len = math.sqrt(look.X * look.X + look.Z * look.Z)
	if len < 1e-9 then
		return nil, nil
	end
	return look.X / len, look.Z / len
end

-- Score d'un candidat (plus petit = meilleur)
function TargetRules.score(origin: Vector3, look: Vector3, pos: Vector3): number
	if not usable(origin) or not usable(pos) then
		return math.huge
	end
	local vx, vz = pos.X - origin.X, pos.Z - origin.Z
	local dist = math.sqrt(vx * vx + vz * vz)
	local lx, lz = flatLook(look)
	local angle = 0
	if lx ~= nil and lz ~= nil and dist > 1e-9 then
		local cos = math.clamp((vx * lx + vz * lz) / dist, -1, 1)
		angle = math.deg(math.acos(cos))
	end
	return dist + ANGLE_WEIGHT * (angle / 90)
end

-- Meilleur candidat d'une liste (score puis id : déterministe)
local function best(
	origin: Vector3,
	look: Vector3,
	list: { Candidate },
	exclude: string?
): (Candidate?, number)
	local bestC, bestS = nil :: Candidate?, math.huge
	for _, c in list do
		if c.id ~= exclude then
			local s = TargetRules.score(origin, look, c.pos)
			if s < bestS or (s == bestS and bestC ~= nil and c.id < bestC.id) then
				bestC, bestS = c, s
			end
		end
	end
	return bestC, bestS
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
	if type(candidates) ~= "table" or not usable(origin) then
		return nil
	end
	local valid, ready = {}, {}
	for _, c in candidates do
		if validCandidate(c) then
			table.insert(valid, c)
			if c.ready == true then
				table.insert(ready, c)
			end
		end
	end
	if #valid == 0 then
		return nil
	end
	-- les squishies prêts passent toujours avant ceux en recharge
	local pool = if #ready > 0 then ready else valid
	local top, topScore = best(origin, look, pool, nil)
	if top == nil then
		return nil
	end
	local currentC = nil
	for _, c in pool do
		if c.id == current then
			currentC = c
			break
		end
	end
	if currentC == nil or currentC.id == top.id then
		return top.id
	end
	local currentScore = TargetRules.score(origin, look, currentC.pos)
	local elapsed = if finite(now) and finite(since) then now - since else math.huge
	if topScore < currentScore - SWITCH_MARGIN or elapsed >= SWITCH_DELAY then
		return top.id
	end
	return currentC.id
end

-- Angle signé (degrés) du candidat : négatif à gauche, positif à droite du regard
local function signedAngle(origin: Vector3, lx: number, lz: number, pos: Vector3): number
	local vx, vz = pos.X - origin.X, pos.Z - origin.Z
	-- droite = regard × haut = (−lz, 0, lx)
	local right = vx * -lz + vz * lx
	local forward = vx * lx + vz * lz
	return math.deg(math.atan2(right, forward))
end

-- Cible suivante (dir = 1) ou précédente (−1) par angle, de gauche à droite
function TargetRules.cycle(
	origin: Vector3,
	look: Vector3,
	candidates: { Candidate },
	current: string?,
	dir: number
): string?
	if type(candidates) ~= "table" or not usable(origin) then
		return nil
	end
	local lx, lz = flatLook(look)
	if lx == nil or lz == nil then
		lx, lz = 0, -1
	end
	local list = {}
	for _, c in candidates do
		if validCandidate(c) then
			table.insert(list, { id = c.id, angle = signedAngle(origin, lx :: number, lz :: number, c.pos) })
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		if a.angle ~= b.angle then
			return a.angle < b.angle
		end
		return a.id < b.id
	end)
	local index = nil
	for i, item in list do
		if item.id == current then
			index = i
			break
		end
	end
	if index == nil then
		-- aucune cible : la plus proche du centre du regard
		local pick, pickAbs = list[1], math.huge
		for _, item in list do
			if math.abs(item.angle) < pickAbs then
				pick, pickAbs = item, math.abs(item.angle)
			end
		end
		return pick.id
	end
	local step = if finite(dir) and dir < 0 then -1 else 1
	return list[(index - 1 + step) % #list + 1].id
end

-- Prochain squishy prêt après une pression (nil si aucun autre n'est prêt)
function TargetRules.afterPress(
	origin: Vector3,
	look: Vector3,
	candidates: { Candidate },
	pressed: string
): string?
	if type(candidates) ~= "table" or not usable(origin) then
		return nil
	end
	local ready = {}
	for _, c in candidates do
		if validCandidate(c) and c.ready == true and c.id ~= pressed then
			table.insert(ready, c)
		end
	end
	local top = best(origin, look, ready, pressed)
	return if top then top.id else nil
end

-- Candidat désigné par la souris (projection écran, jamais un rayon)
function TargetRules.screenPick(pointer: Vector2, projected: { Projected }, scale: number): string?
	if typeof(pointer) ~= "Vector2" or not finite(pointer.X) or not finite(pointer.Y) then
		return nil
	end
	if type(projected) ~= "table" then
		return nil
	end
	local k = if finite(scale) and scale > 0 then scale else 1
	local bestId, bestD, bestDepth = nil :: string?, math.huge, math.huge
	for _, p in projected do
		if
			type(p) == "table"
			and type(p.id) == "string"
			and typeof(p.screen) == "Vector2"
			and finite(p.depth)
			and p.depth > 0
		then
			local sx, sy = p.screen.X, p.screen.Y
			if finite(sx) and finite(sy) then
				local r = if finite(p.radius) and p.radius > 0 then p.radius else 0
				local hit = math.max(CLICK_MIN_RADIUS * k, r * CLICK_RADIUS_MULT)
				local dx, dy = sx - pointer.X, sy - pointer.Y
				local d = math.sqrt(dx * dx + dy * dy)
				if d <= hit and (d < bestD or (d == bestD and p.depth < bestDepth)) then
					bestId, bestD, bestDepth = p.id, d, p.depth
				end
			end
		end
	end
	return bestId
end

return TargetRules
