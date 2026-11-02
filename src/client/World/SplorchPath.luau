--!strict
-- Trajet du petit squishy du Grand Splorch (paquet client-world, GDD §9.4 « Grand Splorch (7,5 s) ») :
-- pur, calé sur l'heure envoyée par le serveur (Celebrate "splorch" : startedAt, burstAt, endsAt).
-- Partagé par VFXController (le modèle qui vole) et CameraController (le travelling du héros) : la
-- caméra suit exactement ce que l'effet dessine.
--   0,0 → 0,6 : s'élève de 8 studs (Quad Out) au-dessus de son ranch ;
--   0,6 → 2,0 : vole vers la place sur une courbe (Sine InOut) jusqu'à 40 studs au-dessus du MEGA pad ;
--   2,0 → burstAt : gonfle de ×1 à ×2,5 (Quad In) en tremblant ;
--   burstAt → +2,0 : caché dans le nuage de confettis ;
--   +2,0 → +2,6 : ressort tout petit (0 → 1, Back Out) et fait coucou ;
--   +2,6 → endsAt − 0,2 : rejoint le héros en 3 grands bonds magiques ; puis repos à ses pieds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local WorldLayout = require(Shared.Logic.WorldLayout)

export type Sample = {
	pos: Vector3,
	scale: number, -- échelle relative (1 = taille affichée normale)
	visible: boolean,
	phase: "rise" | "fly" | "charge" | "cloud" | "pop" | "hops" | "done",
}

local SplorchPath = {}

local RISE_END = 0.6
local FLY_END = 2.0
local APEX_HEIGHT = 40
local RISE = 8
local CHARGE_SCALE = 2.5
local CLOUD = 2.0 -- s caché après l'éclatement
local POP = 0.6
local HOPS = 3
local HOP_HEIGHT = 10
local LAND_EARLY = 0.2 -- s : atterrit 0,2 s avant la fin (7,3 sur 7,5)

local function lerp(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

local function quadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function sineInOut(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

local function backOut(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- Point de départ (au-dessus du ranch du héros) et sommet (au-dessus du MEGA pad)
function SplorchPath.endpoints(slot: number): (Vector3, Vector3)
	local s = WorldLayout.anchor(slot, "silhouette")
	local start = Vector3.new(s.X, 3, s.Z)
	local pad = WorldLayout.plaza("megaPad")
	return start, Vector3.new(pad.X, APEX_HEIGHT, pad.Z)
end

-- Échantillon du trajet à l'instant `now` ; `target` = pieds du héros (repli : départ)
function SplorchPath.sample(
	slot: number,
	startedAt: number,
	burstAt: number,
	endsAt: number,
	now: number,
	target: Vector3?
): Sample
	local start, apex = SplorchPath.endpoints(slot)
	local feet = target or start
	local t = now - startedAt
	local burst = math.max(FLY_END + 0.1, burstAt - startedAt)
	local total = math.max(burst + CLOUD + POP + 0.5, endsAt - startedAt)
	if t < 0 then
		return { pos = start, scale = 1, visible = true, phase = "rise" }
	elseif t < RISE_END then
		local a = quadOut(t / RISE_END)
		return { pos = start + Vector3.new(0, RISE * a, 0), scale = 1, visible = true, phase = "rise" }
	elseif t < FLY_END then
		local a = sineInOut((t - RISE_END) / (FLY_END - RISE_END))
		local from = start + Vector3.new(0, RISE, 0)
		local p = lerp(from, apex, a) + Vector3.new(0, math.sin(math.pi * a) * 12, 0)
		return { pos = p, scale = 1, visible = true, phase = "fly" }
	elseif t < burst then
		local a = (t - FLY_END) / (burst - FLY_END)
		return { pos = apex, scale = 1 + (CHARGE_SCALE - 1) * a * a, visible = true, phase = "charge" }
	elseif t < burst + CLOUD then
		return { pos = apex, scale = 0, visible = false, phase = "cloud" }
	elseif t < burst + CLOUD + POP then
		local a = (t - burst - CLOUD) / POP
		return { pos = apex, scale = math.max(0, backOut(a)), visible = true, phase = "pop" }
	end
	local hopStart = burst + CLOUD + POP
	local hopEnd = math.max(hopStart + 0.3, total - LAND_EARLY)
	if t < hopEnd then
		local a = (t - hopStart) / (hopEnd - hopStart)
		local k = math.min(HOPS - 1, math.floor(a * HOPS))
		local local01 = a * HOPS - k
		local from = lerp(apex, feet, k / HOPS)
		local to = lerp(apex, feet, (k + 1) / HOPS)
		local p = lerp(from, to, local01) + Vector3.new(0, math.sin(math.pi * local01) * HOP_HEIGHT, 0)
		return { pos = p, scale = 1, visible = true, phase = "hops" }
	end
	return { pos = feet, scale = 1, visible = true, phase = "done" }
end

return SplorchPath
