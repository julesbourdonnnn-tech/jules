--!strict
-- LeapRules (paquet logic, docs/04 §12.1). Géométrie du bond scripté (GDD §4.12) : 12 studs en
-- 0,35 s sur un arc fixe, raccourci par le premier solide (rayon à plat contre WorldLayout.solids,
-- le plateau exclu) ; point d'atterrissage identique côté client et serveur (jamais la position que
-- la physique a donnée) ; visée automatique sur la position future de la créature (16 studs, ±40°
-- autour du stick), hystérésis de 20 % ; capture à l'atterrissage (5 studs, 8 pour le propriétaire
-- de sa fuite du Rush ; le serveur ajoute sa tolérance de latence par le 4e paramètre).
-- Toute entrée bizarre (NaN, ±inf, direction nulle) donne un résultat sûr : aucun bond, aucune
-- capture, jamais d'erreur.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, typeof, math = type, typeof, math

local Balance = require(script.Parent.Parent.Config.Balance)
local WorldLayout = require(script.Parent.WorldLayout)

export type AimCandidate = { id: number, posAt: (t: number) -> Vector3 }

local LeapRules = {}

local LEAP = Balance.Leap
local CATCH = Balance.Catch
local BODY_RADIUS = 1.5 -- studs : l'atterrissage s'arrête à cette distance devant un solide
local STEP_HEIGHT = 1 -- un solide compte s'il dépasse le support du départ de plus d'1 stud

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function usable(v: any): boolean
	return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
end

-- Direction normalisée si les composantes sont finies et la norme dans [0,5 ; 1,5]
function LeapRules.validDir(dirX: number, dirZ: number): Vector3?
	if not finite(dirX) or not finite(dirZ) then
		return nil
	end
	local len = math.sqrt(dirX * dirX + dirZ * dirZ)
	if not (len >= LEAP.DirMin and len <= LEAP.DirMax) then
		return nil
	end
	return Vector3.new(dirX / len, 0, dirZ / len)
end

-- Distance le long du rayon (ox, oz) + t × (dx, dz) jusqu'à l'emprise d'une boîte verticale, ou nil
local function rayBox(s: any, ox: number, oz: number, dx: number, dz: number, maxT: number): number?
	-- passage dans le repère de la boîte
	local rx, rz = ox - s.cx, oz - s.cz
	local lox = rx * s.ux + rz * s.uz
	local loz = rx * -s.uz + rz * s.ux
	local ldx = dx * s.ux + dz * s.uz
	local ldz = dx * -s.uz + dz * s.ux
	local tMin, tMax = 0, maxT
	for axis = 1, 2 do
		local o = if axis == 1 then lox else loz
		local d = if axis == 1 then ldx else ldz
		local h = if axis == 1 then s.hx else s.hz
		if math.abs(d) < 1e-12 then
			if o < -h or o > h then
				return nil
			end
		else
			local t1, t2 = (-h - o) / d, (h - o) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	return tMin
end

-- Point d'atterrissage (raccourci devant le premier solide)
function LeapRules.landing(from: Vector3, dir: Vector3): Vector3
	if not usable(from) then
		return Vector3.zero
	end
	if not usable(dir) then
		return from
	end
	local dlen = math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
	if dlen < 1e-9 then
		return from
	end
	local dx, dz = dir.X / dlen, dir.Z / dlen
	local floor = WorldLayout.supportY(from)
	local reach = LEAP.Distance
	local hit = reach
	local solids = WorldLayout.solidsView()
	for i = 2, #solids do -- [1] = le plateau
		local s = solids[i]
		if s.top > floor + STEP_HEIGHT then
			local cdx, cdz = s.cx - from.X, s.cz - from.Z
			local limit = reach + s.reach + BODY_RADIUS
			if cdx * cdx + cdz * cdz <= limit * limit then
				local t = rayBox(s, from.X, from.Z, dx, dz, reach + BODY_RADIUS)
				if t ~= nil then
					hit = math.min(hit, t - BODY_RADIUS)
				end
			end
		end
	end
	local distance = math.clamp(hit, 0, reach)
	return Vector3.new(from.X + dx * distance, from.Y, from.Z + dz * distance)
end

-- Point de l'arc à alpha dans [0 ; 1] (sommet 2,5 studs)
function LeapRules.arc(from: Vector3, to: Vector3, alpha: number): Vector3
	if not usable(from) then
		return Vector3.zero
	end
	if not usable(to) then
		return from
	end
	-- NaN → 0 ; ±inf bornés comme les autres valeurs (−inf → 0, +inf → 1)
	local a = if type(alpha) == "number" and alpha == alpha then math.clamp(alpha, 0, 1) else 0
	local base = from:Lerp(to, a)
	return base + Vector3.new(0, 4 * LEAP.Apex * a * (1 - a), 0)
end

-- Distance à plat et angle (degrés) entre le stick et la créature
local function aimMeasure(origin: Vector3, sx: number, sz: number, target: Vector3): (number, number)
	local vx, vz = target.X - origin.X, target.Z - origin.Z
	local dist = math.sqrt(vx * vx + vz * vz)
	if dist < 1e-9 then
		return 0, 0
	end
	local cos = math.clamp((vx * sx + vz * sz) / dist, -1, 1)
	return dist, math.deg(math.acos(cos))
end

-- Créature visée (id) ou nil (bond droit devant)
function LeapRules.aim(
	origin: Vector3,
	stick: Vector3,
	candidates: { AimCandidate },
	now: number,
	current: number?
): number?
	if not usable(origin) or not usable(stick) or type(candidates) ~= "table" or not finite(now) then
		return nil
	end
	local slen = math.sqrt(stick.X * stick.X + stick.Z * stick.Z)
	if slen < 1e-9 then
		return nil
	end
	local sx, sz = stick.X / slen, stick.Z / slen
	local at = now + LEAP.Duration
	local bestId, bestDist = nil :: number?, math.huge
	local currentDist = nil :: number?
	for _, candidate in candidates do
		if type(candidate) == "table" and type(candidate.posAt) == "function" then
			local ok, pos = pcall(candidate.posAt, at)
			if ok and usable(pos) then
				local dist, angle = aimMeasure(origin, sx, sz, pos)
				if dist <= LEAP.AimRange and angle <= LEAP.AimCone then
					if candidate.id == current then
						currentDist = dist
					end
					if dist < bestDist or (dist == bestDist and bestId ~= nil and candidate.id < bestId) then
						bestId, bestDist = candidate.id, dist
					end
				end
			end
		end
	end
	-- hystérésis : la cible actuelle reste tant qu'aucune autre n'est 20 % plus proche
	if currentDist ~= nil and bestId ~= current and not (bestDist < LEAP.SwitchRatio * currentDist) then
		return current
	end
	return bestId
end

-- Capture automatique (5 studs, 8 pour le propriétaire de sa fuite du Rush ; + tolérance côté
-- serveur : 4e paramètre facultatif, Balance.Catch.Tolerance) ; écart vertical ≤ MaxDY
function LeapRules.catchesOnLanding(
	landing: Vector3,
	creaturePos: Vector3,
	isOwner: boolean,
	tolerance: number?
): boolean
	if not usable(landing) or not usable(creaturePos) then
		return false
	end
	local extra = if finite(tolerance) and (tolerance :: number) > 0 then tolerance :: number else 0
	local radius = (if isOwner == true then CATCH.OwnerRadius else CATCH.Radius) + extra
	local dx, dz = landing.X - creaturePos.X, landing.Z - creaturePos.Z
	if dx * dx + dz * dz > radius * radius then
		return false
	end
	return math.abs(landing.Y - creaturePos.Y) <= CATCH.MaxDY
end

return LeapRules
