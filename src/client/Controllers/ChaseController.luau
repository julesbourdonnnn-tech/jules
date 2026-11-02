--!strict
-- ChaseController (paquet client-world, docs/04 §13.3, §10.1, GDD §4.12, §9.4 « Bondir »).
-- Bond et capture côté client :
--   * leap() (R2 / Maj) : bond SCRIPTÉ tout de suite (sensation immédiate) sur l'arc fixe de LeapRules
--     (12 studs en 0,35 s, sommet 2,5, image par image, arrêt devant le premier solide), visée
--     automatique sur la position future de la créature (PromptController.leapTarget), sinon droit
--     devant (stick, ou direction du personnage) ; Leap(dirX, dirZ, Clock.now()) envoyé au serveur ;
--     recharge Leap.Cooldown (4 s) ; ignoré pendant un portage (son Bump) ;
--   * tryCatch() (□ près d'une créature) : Catch(id, Clock.now()) si une créature attrapable est à
--     portée (5 studs à plat, 8 pour le propriétaire de sa fuite du Rush ; pieds ≤ Catch.MaxDY), sinon
--     l'appui est gardé Catch.InputBuffer (0,25 s) : une créature qui arrive à portée pendant ce temps
--     est attrapée ;
--   * marqueur blanc sur la créature visée par le prochain bond.
-- Les effets de capture ne se jouent qu'après la réponse du serveur (Celebrate « catch », VFXController).
-- Aucune règle ne dépend de la physique : le serveur rejoue la même géométrie (LeapRules.landing).
-- Une seule connexion par image (Heartbeat) ; le bond a sa sortie (fin de l'arc, personnage perdu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local LeapRules = require(Shared.Logic.LeapRules)
local ZoneRules = require(Shared.Logic.ZoneRules)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local StateController = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local AudioController = require(Client.Controllers.AudioController)
local VFXController = require(Client.Controllers.VFXController)
local CameraController = require(Client.Controllers.CameraController)
local PromptController = require(Client.Controllers.PromptController)
local Util = require(Client.World.Util)
local Catchable = require(Client.World.Catchable)

local ChaseController = {}

ChaseController.Leaped = Signal.new() :: Signal.Signal<>

local LEAP = Balance.Leap
local CATCH = Balance.Catch
local LEAP_FOV = 6 -- 70 → 76 en 0,1, retour en 0,4 (CameraController, pas en Mouvement réduit)
local LEAP_FOV_TIME = 0.5
local DUST = Color3.fromRGB(235, 225, 210)

type Leap = { from: Vector3, to: Vector3, t: number, look: Vector3 }

local lastLeapAt = -math.huge -- Clock.now() du dernier bond
local leaping: Leap? = nil
local bufferUntil = -math.huge -- animT jusqu'auquel l'appui □ est gardé
local animT = 0
local marker: Part? = nil
local started = false
local connections: { any } = {}

local function ctx(): Catchable.Ctx
	local slot = WorldStateController.mySlot()
	local ranch = if slot > 0 then WorldStateController.ranch(slot) else nil
	local golden = Util.safe("StateController.get", nil, StateController.get, "golden")
	local ev: any = WorldStateController.event()
	return {
		mySlot = slot,
		rush = ranch ~= nil and ranch.mode == "rush",
		features = if type(ev) == "table" and type(ev.features) == "table" then ev.features else {},
		goldenLastWin = if type(golden) == "table" then Util.num(golden.lastWinAt, 0, 0) else 0,
		unixNow = Clock.unix(),
	}
end

local function carrying(): boolean
	local slot = WorldStateController.mySlot()
	local ranch = if slot > 0 then WorldStateController.ranch(slot) else nil
	return ranch ~= nil and ranch.carry ~= ""
end

local function rootOffset(): number
	-- hausse de la racine de la monture : les pieds sont mesurés sous la monture (contrat v1.2)
	local slot = WorldStateController.mySlot()
	local ranch = if slot > 0 then WorldStateController.ranch(slot) else nil
	if ranch == nil or ranch.ride == "" then
		return 0
	end
	local def = Balance.Ride.Saddles[ranch.saddle]
	if def == nil then
		return 0
	end
	return Balance.Ride.HipFactor * def.scale * Balance.SizeScale.BaseDiameter
end

-- Créature attrapable à portée maintenant (id) ou nil
local function inReach(): number?
	local root = Util.localRoot()
	if root == nil then
		return nil
	end
	local now = Clock.now()
	local c = ctx()
	local feet = ZoneRules.feetY(root.Position.Y, rootOffset())
	local bestId, bestD = nil, math.huge
	for id, s in WorldStateController.creatures() do
		if Catchable.check(s, now, c) then
			local p = WorldStateController.creaturePos(id, now)
			if p then
				local d = ZoneRules.distXZ(root.Position, p)
				-- même mesure que le serveur (ChaseService : pieds − sol de la créature, WorldLayout.groundY) :
				-- jamais le dessus d'un solide (supportY), qui refuserait une capture que le serveur accepte
				local ground = WorldLayout.groundY(p.X, p.Z)
				if
					d <= Catchable.radius(s, c.mySlot)
					and math.abs(feet - ground) <= CATCH.MaxDY
					and d < bestD
				then
					bestId, bestD = id, d
				end
			end
		end
	end
	return bestId
end

local function sendCatch(id: number): boolean
	return Util.send("Catch", id, Clock.now())
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Recharge restante du bond (s)
function ChaseController.cooldownLeft(): number
	local left = lastLeapAt + LEAP.Cooldown - Clock.now()
	if left < 0 or left > LEAP.Cooldown then
		return 0 -- horloge décalée en arrière : jamais une recharge plus longue que prévu
	end
	return left
end

-- Bondit si possible (recharge, pas de portage, personnage présent, pas déjà en l'air)
function ChaseController.leap(): boolean
	if carrying() then
		Util.safe("AudioController.play", nil, AudioController.play, "Bump")
		return false
	end
	if leaping ~= nil or ChaseController.cooldownLeft() > 0 then
		return false
	end
	local root = Util.localRoot()
	if root == nil then
		return false
	end
	local now = Clock.now()
	local from = root.Position
	-- direction : la créature visée (position à l'atterrissage), sinon le stick, sinon le regard
	local dir: Vector3? = nil
	local aimed = Util.safe("PromptController.leapTarget", nil, PromptController.leapTarget)
	if type(aimed) == "number" then
		local p = WorldStateController.creaturePos(aimed, now + LEAP.Duration)
		if p then
			local v = Vector3.new(p.X - from.X, 0, p.Z - from.Z)
			if v.Magnitude > 0.1 then
				dir = v.Unit
			end
		end
	end
	if dir == nil then
		local player = Players.LocalPlayer
		local character = player and player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		local md = if hum then hum.MoveDirection else Vector3.zero
		if Vector3.new(md.X, 0, md.Z).Magnitude > 0.1 then
			dir = Vector3.new(md.X, 0, md.Z).Unit
		else
			local lv = root.CFrame.LookVector
			local flat = Vector3.new(lv.X, 0, lv.Z)
			dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
		end
	end
	local d = dir :: Vector3
	local valid = LeapRules.validDir(d.X, d.Z)
	if valid == nil then
		return false
	end
	-- l'intention part D'ABORD : un bond que le serveur ne connaîtrait pas (débit, remote absent) ne
	-- serait pas crédité par MoveCheck (déplacement refusé, joueur repoussé) : il n'est pas joué
	if not Util.send("Leap", valid.X, valid.Z, now) then
		return false
	end
	local to = LeapRules.landing(from, valid)
	lastLeapAt = now
	leaping = { from = from, to = to, t = 0, look = valid }
	Util.safe("AudioController.play", nil, AudioController.play, "Leap")
	Util.safe("CameraController.fovPunch", nil, CameraController.fovPunch, LEAP_FOV, LEAP_FOV_TIME)
	Util.safe("VFXController.burst", nil, VFXController.burst, from - Vector3.new(0, 2, 0), DUST, 6)
	ChaseController.Leaped:Fire()
	return true
end

-- Tente une capture (□) ; garde l'appui 0,25 s si la créature arrive à portée
function ChaseController.tryCatch(): boolean
	local id = inReach()
	if id then
		bufferUntil = -math.huge
		return sendCatch(id)
	end
	bufferUntil = animT + CATCH.InputBuffer
	return false
end

-- =============================================================================================
-- Image
-- =============================================================================================

local function stepLeap(dt: number)
	local lp = leaping
	if lp == nil then
		return
	end
	local root = Util.localRoot()
	lp.t += dt
	if root == nil then
		leaping = nil -- personnage perdu (mort, réapparition) : le bond s'arrête
		return
	end
	local alpha = math.clamp(lp.t / LEAP.Duration, 0, 1)
	local p = LeapRules.arc(lp.from, lp.to, alpha)
	root.CFrame = CFrame.lookAt(p, p + lp.look)
	-- arc scripté : aucune vitesse accumulée par la gravité pendant le bond (sinon le personnage
	-- retombe d'un coup à l'atterrissage)
	root.AssemblyLinearVelocity = Vector3.zero
	if alpha >= 1 then
		leaping = nil
	end
end

local function stepMarker()
	local id = Util.safe("PromptController.leapTarget", nil, PromptController.leapTarget)
	local pos = if type(id) == "number" then WorldStateController.creaturePos(id, Clock.now()) else nil
	if pos == nil then
		if marker then
			marker.Parent = nil
		end
		return
	end
	if marker == nil then
		local p = Instance.new("Part")
		p.Name = "LeapMarker"
		p.Shape = Enum.PartType.Cylinder
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 255, 255)
		p.Size = Vector3.new(0.2, 4, 4)
		marker = p
	end
	local m = marker :: Part
	local ground = WorldLayout.groundY(pos.X, pos.Z)
	m.CFrame = CFrame.new(pos.X, ground + 0.15, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
	if m.Parent == nil then
		local folder = workspace:FindFirstChild("ClientWorld") or workspace
		m.Parent = folder
	end
end

-- Une image (exposé aux specs ; appelé par Heartbeat)
function ChaseController._step(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	animT += d
	stepLeap(d)
	if animT <= bufferUntil then
		local id = inReach()
		if id then
			bufferUntil = -math.huge
			sendCatch(id)
		end
	end
	stepMarker()
end

-- Création des états ; aucun yield long
function ChaseController.Init()
	leaping = nil
end

-- Connexions et boucles
function ChaseController.Start()
	if started then
		return
	end
	started = true
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			Util.guard("ChaseController.step", ChaseController._step, dt)
		end)
	)
end

-- Bond en cours (specs)
function ChaseController.leaping(): boolean
	return leaping ~= nil
end

-- Coupe les connexions (fin de session, specs)
function ChaseController._stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	started = false
end

return ChaseController
