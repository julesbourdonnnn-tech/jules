--!strict
-- ZoneRules (paquet logic, docs/04 §12.1). Zones vérifiées par le serveur sur la position VALIDÉE
-- (GDD §4.6, §4.8, §6.3, §4.22) : dalles (entrée ≤ 2,5 studs, sortie > 3,5, un achat par entrée),
-- Pot (5), bol (8), Bassin (12), MEGA (20), clôture côté rue (boop 8, pet-sitting 10, propriétaire
-- proche 25), intrus, Autel de la Lune. Jamais d'événement physique Touched. Les distances sont
-- mesurées à plat (XZ) : aucun toit n'existe (solides de 30 studs).
-- Toute position bizarre (NaN, nil) est lue comme hors zone : jamais d'erreur, jamais d'effet.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, typeof, math = type, typeof, math

local Balance = require(script.Parent.Parent.Config.Balance)
local Events = require(script.Parent.Parent.Config.Events)
local WorldLayout = require(script.Parent.WorldLayout)

local ZoneRules = {}

local FENCE_POINTS = WorldLayout.fencePointsLocal()
local HALF_WIDTH = WorldLayout.Const.RanchWidth / 2

-- Position utilisable (Vector3 aux composantes finies)
local function usable(pos: any): boolean
	if typeof(pos) ~= "Vector3" then
		return false
	end
	local x, z = pos.X, pos.Z
	return x == x and z == z and math.abs(x) ~= math.huge and math.abs(z) ~= math.huge
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- (dedans, vient d'entrer) avec l'hystérésis 2,5 / 3,5
function ZoneRules.padStep(wasInside: boolean, distance: number): (boolean, boolean)
	local tiles = Balance.Tiles
	if type(distance) ~= "number" or distance ~= distance or distance < 0 then
		return false, false
	end
	local was = wasInside == true
	local inside = distance <= tiles.EnterRadius or (was and distance <= tiles.ExitRadius)
	return inside, inside and not was
end

-- Position à radius studs d'un objet du ranch (WorldLayout.anchor)
function ZoneRules.near(slot: number, anchor: string, pos: Vector3, radius: number): boolean
	if not usable(pos) or type(radius) ~= "number" or radius ~= radius or radius < 0 then
		return false
	end
	if type(slot) ~= "number" or slot < 1 or slot > WorldLayout.Const.Ranches or slot % 1 ~= 0 then
		return false
	end
	local target = WorldLayout.anchor(slot, anchor :: any)
	return flatDistance(pos, target) <= radius
end

-- À 20 studs du centre du MEGA pad
function ZoneRules.inMegaZone(pos: Vector3): boolean
	if not usable(pos) then
		return false
	end
	return flatDistance(pos, WorldLayout.plaza("megaPad")) <= Events.Mega.Radius
end

-- Côté rue de la clôture du ranch, à radius studs d'une place de clôture
function ZoneRules.streetSideOfFence(slot: number, pos: Vector3, radius: number): boolean
	if not usable(pos) or type(radius) ~= "number" or radius ~= radius or radius < 0 then
		return false
	end
	if type(slot) ~= "number" or slot < 1 or slot > WorldLayout.Const.Ranches or slot % 1 ~= 0 then
		return false
	end
	local p = WorldLayout.toLocal(slot, pos)
	if p.Z > 0 then
		return false -- dans le ranch (ou derrière la clôture) : jamais côté rue
	end
	for _, point in FENCE_POINTS do
		local dx, dz = p.X - point.X, p.Z - point.Z
		if dx * dx + dz * dz <= radius * radius then
			return true
		end
	end
	return false
end

-- Propriétaire à 25 studs de sa clôture (boop plus long) : distance au segment de la clôture de
-- devant (Z = 0, X de −32 à +32), dedans comme dehors
function ZoneRules.ownerNearFence(slot: number, pos: Vector3): boolean
	if not usable(pos) then
		return false
	end
	if type(slot) ~= "number" or slot < 1 or slot > WorldLayout.Const.Ranches or slot % 1 ~= 0 then
		return false
	end
	local p = WorldLayout.toLocal(slot, pos)
	local dx = math.max(math.abs(p.X) - HALF_WIDTH, 0)
	local d = math.sqrt(dx * dx + p.Z * p.Z)
	return d <= Events.Rush.OwnerNearRadius
end

-- Ranch d'un autre où se trouve cette position (0 = aucun)
function ZoneRules.intruder(ownerSlot: number, pos: Vector3): number
	if not usable(pos) then
		return 0
	end
	local slot = WorldLayout.ranchAt(pos)
	if slot ~= 0 and slot ~= ownerSlot then
		return slot
	end
	return 0
end

-- Présence à l'Autel de la Lune
function ZoneRules.atAltar(pos: Vector3): boolean
	if not usable(pos) then
		return false
	end
	return flatDistance(pos, WorldLayout.plaza("altar")) <= WorldLayout.Const.AltarRadius
end

return ZoneRules
