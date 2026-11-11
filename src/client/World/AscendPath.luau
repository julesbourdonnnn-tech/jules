--!strict
-- Trajet du Meilleur Ami de la Jelly Ascend (lot B5, étape 4 ; GDD v2.0 §4.27 étape 5, §9.4 ligne
-- « Jelly Ascend » ; plan B5 V2, D27) : pur, calé sur l'heure envoyée par le serveur (Celebrate
-- "ascend" : startedAt, burstAt, endsAt). Partagé par World/ShowsV2 (la copie qui vole) et
-- CameraController (la caméra du héros) : la caméra suit exactement ce que le spectacle dessine.
--   startedAt → burstAt          : monte dans le faisceau, du centre du ranch jusqu'à l'élément de
--                                  ciel (WorldLayout.v2Anchor(slot, "sky")), Sine InOut, à la taille
--                                  copiée au départ (grow = 0) ;
--   burstAt → burstAt + HOVER    : reste au ciel dans l'éclat de lumière ; prend sa NOUVELLE taille
--                                  (grow = 1) ;
--   burstAt + HOVER → endsAt     : redescend (Quad Out vers le sol) et se pose au centre du ranch
--                                  EXACTEMENT à endsAt ;
--   après endsAt                 : posé (phase « done »).
-- Aucune instance, aucun service : testable sans monde.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local WorldLayout = require(Shared.Logic.WorldLayout)

export type Sample = {
	pos: Vector3,
	grow: number, -- 0 = taille copiée au départ, 1 = nouvelle taille
	phase: "rise" | "hover" | "descend" | "done",
}

local AscendPath = {}

AscendPath.HOVER = 1.2 -- s au ciel après l'éclat
AscendPath.FOOT = 2 -- studs au-dessus du sol du centre du ranch

local CENTER = Vector3.new(0, 0, 36) -- centre du ranch (repère local, même place que la silhouette)

local function sineInOut(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

local function quadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Départ (centre du ranch, au sol) et sommet (élément de ciel) du ranch `slot`
function AscendPath.endpoints(slot: number): (Vector3, Vector3)
	local c = WorldLayout.toWorld(slot, CENTER)
	local ground = WorldLayout.groundY(c.X, c.Z)
	local start = Vector3.new(c.X, ground + AscendPath.FOOT, c.Z)
	local sky = WorldLayout.v2Anchor(slot, "sky").Position
	return start, sky
end

-- Échantillon à l'instant `now` (heures du serveur) ; heures illisibles : posé au départ
function AscendPath.sample(
	slot: number,
	startedAt: number,
	burstAt: number,
	endsAt: number,
	now: number
): Sample
	local start, sky = AscendPath.endpoints(slot)
	if not (finite(startedAt) and finite(burstAt) and finite(endsAt) and finite(now)) then
		return { pos = start, grow = 0, phase = "done" }
	end
	local burst = math.max(startedAt + 0.1, math.min(burstAt, endsAt))
	local hoverEnd = math.min(burst + AscendPath.HOVER, endsAt)
	if now < startedAt then
		return { pos = start, grow = 0, phase = "rise" }
	elseif now < burst then
		local a = sineInOut((now - startedAt) / (burst - startedAt))
		return { pos = start:Lerp(sky, a), grow = 0, phase = "rise" }
	elseif now < hoverEnd then
		return { pos = sky, grow = 1, phase = "hover" }
	elseif now < endsAt then
		local a = quadOut((now - hoverEnd) / math.max(1e-3, endsAt - hoverEnd))
		return { pos = sky:Lerp(start, a), grow = 1, phase = "descend" }
	end
	return { pos = start, grow = 1, phase = "done" }
end

return AscendPath
