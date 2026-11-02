--!strict
-- CameraController (paquet client-world, docs/04 §13.3, GDD §10.4, §9.1, §9.4).
-- La caméra ne bouge JAMAIS toute seule, sauf le travelling du Grand Splorch du héros (suit le vol
-- puis le retour du petit squishy, World/SplorchPath, calé sur l'heure du serveur), coupé en Mouvement
-- réduit. Coups de focale (fovPunch) et secousses (Humanoid.CameraOffset, amplitude ≤ 0,4, durée ≤
-- 0,3 s, bruit de Perlin), jamais en Mouvement réduit. Seul module qui touche la caméra : les effets
-- de caméra des moments de jeu (naissances, fusions, combo, MEGA, Grand Splorch) sont joués ici, sur
-- Celebrate et sur l'heure d'atterrissage du MEGA (VFXController, plus tôt dans l'ordre, ne peut pas
-- l'appeler). Chaque état a sa sortie : le travelling rend la caméra au plus tard StateTimeouts
-- « spectacle » (10 s d'images) après son début, même si l'horloge du jeu est figée ou décalée.
-- Une seule connexion par image (RenderStepped) ; les durées locales sont des sommes de dt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local StateTimeouts = require(Shared.Logic.StateTimeouts)
local WorldLayout = require(Shared.Logic.WorldLayout)
local ZoneRules = require(Shared.Logic.ZoneRules)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Util = require(Client.World.Util)
local SplorchPath = require(Client.World.SplorchPath)

local CameraController = {}

-- Valeurs de caméra (GDD §9.1, §9.4)
local CAM = {
	MaxShake = 0.4, -- studs (Humanoid.CameraOffset)
	MaxShakeTime = 0.3, -- s
	MaxFov = 12, -- degrés ajoutés au plus
	TravelBack = 34, -- studs derrière le petit squishy
	TravelUp = 14,
	HatchEpicFov = 3, -- 70 → 73 en 0,3
	FusionFov = 4, -- 70 → 74 en 0,3
	FovTime = 0.3,
	LegendShake = 0.25,
	ComboShake = 0.2,
	SplorchShake = 0.35, -- héros, à l'éclatement
	SplorchShakeRange = 200, -- autres : atténuée par la distance
	MegaShake = 0.4, -- × (1 − d / 120)
	MegaRange = 120,
}

local SPECTACLE_TIMEOUT = StateTimeouts.seconds("spectacle")
local EPIC = 4
local LEGENDARY = 5

type Travel = { slot: number, startedAt: number, burstAt: number, endsAt: number, frames: number, shaken: boolean }
type Punch = { degrees: number, duration: number, t: number }
type Shake = { amplitude: number, duration: number, t: number }

local travel: Travel? = nil
local punch: Punch? = nil
local shakeState: Shake? = nil
local baseFov: number? = nil
local baseType: Enum.CameraType? = nil
local spectators: { { burstAt: number } } = {}
local megaLandSeen = 0 -- index du MEGA dont l'atterrissage a déjà secoué
local started = false
local connections: { any } = {}

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function reducedMotion(): boolean
	return Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
end

local function humanoid(): Humanoid?
	local player = Players.LocalPlayer
	local character = player and player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function restoreCamera()
	local cam = camera()
	if cam and baseType ~= nil then
		cam.CameraType = baseType
	end
	baseType = nil
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Travelling du héros calé sur l'heure envoyée (rien en Mouvement réduit)
function CameraController.splorch(startedAt: number, burstAt: number, endsAt: number)
	if not (Util.finite(startedAt) and Util.finite(burstAt) and Util.finite(endsAt)) then
		return
	end
	if endsAt <= startedAt or endsAt - startedAt > SPECTACLE_TIMEOUT then
		return
	end
	if reducedMotion() or Clock.now() >= endsAt then
		return
	end
	local slot = WorldStateController.mySlot()
	if slot == 0 then
		return
	end
	travel = { slot = slot, startedAt = startedAt, burstAt = burstAt, endsAt = endsAt, frames = 0, shaken = false }
end

-- Coup de focale (pas en Mouvement réduit) ; un nouveau coup remplace l'ancien
function CameraController.fovPunch(degrees: number, duration: number)
	if reducedMotion() or not Util.finite(degrees) or not Util.finite(duration) or duration <= 0 then
		return
	end
	local cam = camera()
	if cam == nil then
		return
	end
	if baseFov == nil then
		baseFov = cam.FieldOfView
	end
	punch = { degrees = math.clamp(degrees, -CAM.MaxFov, CAM.MaxFov), duration = math.min(duration, 2), t = 0 }
end

-- Secousse bornée (pas en Mouvement réduit) ; la plus forte des deux gagne
function CameraController.shake(amplitude: number, duration: number)
	if reducedMotion() or not Util.finite(amplitude) or not Util.finite(duration) then
		return
	end
	local a = math.clamp(amplitude, 0, CAM.MaxShake)
	local d = math.clamp(duration, 0, CAM.MaxShakeTime)
	if a <= 0 or d <= 0 then
		return
	end
	local cur = shakeState
	if cur and cur.t < cur.duration and cur.amplitude > a then
		return
	end
	shakeState = { amplitude = a, duration = d, t = 0 }
end

-- Travelling en cours
function CameraController.busy(): boolean
	return travel ~= nil
end

-- =============================================================================================
-- Image
-- =============================================================================================

local function stepTravel(dt: number)
	local tr = travel
	if tr == nil then
		return
	end
	local cam = camera()
	local now = Clock.now()
	tr.frames += dt
	if cam == nil or now >= tr.endsAt or tr.frames > SPECTACLE_TIMEOUT or reducedMotion() then
		travel = nil
		restoreCamera()
		return
	end
	if baseType == nil then
		baseType = cam.CameraType
	end
	local root = Util.localRoot()
	local feet = if root then root.Position else nil
	local s = SplorchPath.sample(tr.slot, tr.startedAt, tr.burstAt, tr.endsAt, now, feet)
	local center = WorldLayout.plaza("center")
	local away = Vector3.new(s.pos.X - center.X, 0, s.pos.Z - center.Z)
	if away.Magnitude < 1 then
		away = Vector3.new(0, 0, 1)
	end
	local eye = s.pos + away.Unit * CAM.TravelBack + Vector3.new(0, CAM.TravelUp, 0)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(eye, s.pos)
	if not tr.shaken and now >= tr.burstAt then
		tr.shaken = true
		CameraController.shake(CAM.SplorchShake, CAM.MaxShakeTime)
	end
end

local function stepPunch(dt: number)
	local p = punch
	local cam = camera()
	if p == nil or cam == nil then
		return
	end
	p.t += dt
	local base = baseFov or 70
	if p.t >= p.duration or reducedMotion() then
		cam.FieldOfView = base
		punch = nil
		baseFov = nil
		return
	end
	-- montée rapide (20 %), retour plus lent (Quad InOut)
	local a = p.t / p.duration
	local k
	if a < 0.2 then
		k = a / 0.2
	else
		local b = (a - 0.2) / 0.8
		k = 1 - (if b < 0.5 then 2 * b * b else 1 - (-2 * b + 2) ^ 2 / 2)
	end
	cam.FieldOfView = base + p.degrees * k
end

local function stepShake(dt: number)
	local s = shakeState
	if s == nil then
		return
	end
	local hum = humanoid()
	s.t += dt
	if s.t >= s.duration or reducedMotion() or hum == nil then
		shakeState = nil
		if hum then
			hum.CameraOffset = Vector3.zero
		end
		return
	end
	local falloff = 1 - s.t / s.duration
	local seed = s.t * 40
	hum.CameraOffset = Vector3.new(
		math.noise(seed, 0.3) * s.amplitude * falloff,
		math.noise(0.7, seed) * s.amplitude * falloff,
		0
	)
end

-- Secousses des spectateurs (atténuées par la distance) et atterrissage du MEGA
local function stepWorld()
	local now = Clock.now()
	local root = Util.localRoot()
	for i = #spectators, 1, -1 do
		local sp = spectators[i]
		if now >= sp.burstAt then
			table.remove(spectators, i)
			if root and now - sp.burstAt < 1 then
				local d = ZoneRules.distXZ(root.Position, WorldLayout.plaza("megaPad"))
				local k = 1 - d / CAM.SplorchShakeRange
				if k > 0 then
					CameraController.shake(CAM.SplorchShake * k, CAM.MaxShakeTime)
				end
			end
		end
	end
	local ev: any = WorldStateController.event()
	if type(ev) ~= "table" or type(ev.mega) ~= "table" or type(ev.features) ~= "table" then
		return
	end
	if ev.features.megaSquish ~= true then
		return
	end
	local mega = ev.mega
	local index = Util.num(mega.index, 0)
	local landsAt = Util.num(mega.landsAt, 0)
	if index > megaLandSeen and landsAt > 0 and now >= landsAt then
		megaLandSeen = index
		if root and now - landsAt < 1 then
			local d = ZoneRules.distXZ(root.Position, WorldLayout.plaza("megaPad"))
			if d < CAM.MegaRange then
				CameraController.shake(CAM.MegaShake * (1 - d / CAM.MegaRange), CAM.MaxShakeTime)
			end
		end
	end
end

-- Une image (exposé aux specs ; appelé par RenderStepped)
function CameraController._step(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	stepTravel(d)
	stepPunch(d)
	stepShake(d)
	stepWorld()
end

-- =============================================================================================
-- Célébrations
-- =============================================================================================

local function onCelebrate(payload: any)
	if type(payload) ~= "table" or type(payload.data) ~= "table" then
		return
	end
	local kind, data = payload.kind, payload.data
	local me = Players.LocalPlayer
	if kind == "splorch" then
		if data.short == true then
			return
		end
		local startedAt, burstAt, endsAt = data.startedAt, data.burstAt, data.endsAt
		if me and data.userId == me.UserId then
			CameraController.splorch(startedAt, burstAt, endsAt)
		elseif Util.finite(burstAt) and #spectators < 8 then
			table.insert(spectators, { burstAt = burstAt })
		end
	elseif kind == "hatch" then
		local rarity = Util.num(data.rarity, 1)
		local mkey = Util.mutationKey(data.mutation)
		if rarity >= LEGENDARY or mkey == "flop" or mkey == "glitch" or mkey == "rainbow" then
			CameraController.shake(CAM.LegendShake, 0.25)
		elseif rarity >= EPIC then
			CameraController.fovPunch(CAM.HatchEpicFov, CAM.FovTime)
		end
	elseif kind == "fusion" then
		CameraController.fovPunch(CAM.FusionFov, CAM.FovTime)
		if Util.num(data.step, 1) >= 4 then
			CameraController.shake(CAM.ComboShake, 0.2)
		end
	elseif kind == "megaResult" then
		if data.success == true then
			CameraController.fovPunch(CAM.FusionFov, CAM.FovTime)
		end
	end
end

-- Création des états ; aucun yield long
function CameraController.Init()
	travel = nil
	punch = nil
	shakeState = nil
end

-- Connexions et boucles
function CameraController.Start()
	if started then
		return
	end
	started = true
	local remote = Util.remote("Celebrate")
	if remote then
		table.insert(
			connections,
			remote.OnClientEvent:Connect(function(payload: any)
				Util.guard("CameraController.Celebrate", onCelebrate, payload)
			end)
		)
	end
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt: number)
			Util.guard("CameraController.step", CameraController._step, dt)
		end)
	)
	-- MEGA déjà atterri à l'arrivée : aucune secousse rétroactive
	local ev: any = WorldStateController.event()
	if type(ev) == "table" and type(ev.mega) == "table" then
		megaLandSeen = Util.num(ev.mega.index, 0)
	end
end

return CameraController
