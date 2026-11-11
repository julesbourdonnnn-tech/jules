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
-- v2.0 (lot B5, étape 4 ; plan B5 D27) : BAIL de caméra à UN seul état gardé (type, sujet, focale,
-- CFrame) et priorités spectacle (« show » : travellings du Grand Splorch et de la Jelly Ascend) >
-- photo > jumelles (ces deux-là arrivent à l'étape 5) ; prendre un bail plus fort finit proprement le
-- plus faible (son rappel), rendre le dernier remet l'état gardé EXACTEMENT. Le travelling du Grand
-- Splorch passe par ce bail sans autre changement. CameraController.ascend (héros seul, interrupteur
-- JellyAscend ouvert, jamais en Mouvement réduit) suit la copie du Meilleur Ami (World/AscendPath) et
-- rend la caméra à endsAt, au plus tard Events.Spectacles.ascend.hardCut (12 s) d'images après.
-- v2.0 (lot B5, étape 5 ; plan B5 D24-D28 ; GDD v2.0 §7.5 ; N22) :
--   * MODE PHOTO « Cheese ! » (CameraController.photo(on), photoOn(), interrupteur PhotoMode) : bail
--     « photo », écran UI/PhotoHud (fenêtre bloquante « photo » de FocusGuard, HUD caché localement) ;
--     sticks, L2 / R2 et □ (WASD, flèches, Page préc. / suiv., F, Espace au clavier) liés par
--     ContextActionService:BindActionAtPriority et ABSORBÉS : le personnage ne bouge plus, et AUCUNE
--     propriété du personnage n'est écrite (il reste visible de tous, N22). Caméra en orbite autour
--     d'un point : 8 à 60 studs, 5° à 75° au-dessus de l'horizon, jamais sous le sol ; le point bouge
--     à 16 studs par seconde dans la zone d'entrée (mon ranch, le disque de la place, sinon 12 studs
--     autour du personnage). SetPhotoMode(on) part au plus une fois par 1,2 s, seulement le dernier
--     état voulu, jamais égal au dernier envoyé. Fin d'office : interrupteur coupé en direct, MON
--     Grand Splorch ou MON Ascension, mort ou réapparition, fenêtre fermée, 600 s ;
--   * ZOOM DES JUMELLES (CameraController.binoculars(slot | nil), appelé par UI/Binoculars) : bail
--     « binoculars » (le plus faible) ; caméra 18 studs au-dessus et 16 studs dehors du portail
--     regardé, tournée vers le centre du ranch (Z local 36), focale 50, atteinte en 0,4 s (tout de
--     suite en Mouvement réduit) ; aucun objet d'interface ; le personnage à plus de 14 studs du
--     portail referme les jumelles (Binoculars.close par un require paresseux et gardé).
-- Interrupteurs coupés : aucune liaison, aucune écoute en plus ; _step ne gagne qu'un test.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Events = require(Shared.Config.Events)
local Sounds = require(Shared.Config.Sounds)
local StateTimeouts = require(Shared.Logic.StateTimeouts)
local WorldLayout = require(Shared.Logic.WorldLayout)
local ZoneRules = require(Shared.Logic.ZoneRules)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Util = require(Client.World.Util)
local SplorchPath = require(Client.World.SplorchPath)
local AscendPath = require(Client.World.AscendPath)
local Flags = require(Client.World.Flags)
local AudioController = require(Client.Controllers.AudioController)

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
local ASCEND_CUT = Events.Spectacles.ascend.hardCut -- 12 s
local ASCEND_BACK = 30 -- studs devant le ranch (vers la place) : la caméra regarde la copie qui monte
local ASCEND_UP = 6
-- priorités des baux (D27)
local PRIORITY: { [string]: number } = { show = 3, photo = 2, binoculars = 1 }
local EPIC = 4
local LEGENDARY = 5
-- mode photo (D25-D27)
local PHOTO = {
	MinDist = 8,
	MaxDist = 60,
	StartDist = 20,
	MinPitch = math.rad(5),
	MaxPitch = math.rad(75),
	StartPitch = math.rad(25),
	Move = 16, -- studs par seconde (point visé)
	Turn = math.rad(120), -- par seconde (lacet, stick à fond)
	Tilt = math.rad(60), -- par seconde (tangage)
	Zoom = 24, -- studs par seconde
	DeadZone = 0.15,
	SelfRadius = 12, -- zone « autour du personnage »
	RanchX = 34, -- mon ranch : X local ± 34, Z local −2 … 74
	RanchZ = { -2, 74 },
	FocusUp = 3, -- point visé au-dessus du sol
	GroundGap = 1, -- la caméra reste au moins 1 stud au-dessus du sol
	Timeout = 600, -- s d'images (sortie d'office)
	SendEvery = 1.2, -- s entre deux SetPhotoMode
}
local PHOTO_PRIORITY = Enum.ContextActionPriority.High.Value + 50
local A_MOVE, A_TURN, A_ZOOM, A_FILTER = "PhotoMove", "PhotoTurn", "PhotoZoom", "PhotoFilter"
-- jumelles (D28)
local BINO = { Up = 18, Out = 16, LookZ = 36, Fov = 50, Time = 0.4, Leave = 14 }

type Travel = {
	slot: number,
	startedAt: number,
	burstAt: number,
	endsAt: number,
	frames: number,
	shaken: boolean,
	leased: boolean,
}
type AscendTravel = {
	slot: number,
	userId: number,
	startedAt: number,
	burstAt: number,
	endsAt: number,
	frames: number,
	leased: boolean,
}
type Saved = { cameraType: Enum.CameraType, subject: Instance?, fov: number, cframe: CFrame }
type Photo = {
	zone: string, -- « ranch » | « plaza » | « self »
	slot: number,
	center: Vector3, -- centre du disque (place, personnage)
	radius: number,
	focus: Vector3,
	yaw: number,
	pitch: number,
	dist: number,
	stickMove: Vector2,
	stickTurn: Vector2,
	keys: { [Enum.KeyCode]: boolean },
	frames: number,
	conns: { RBXScriptConnection },
	hud: any,
}
type Bino = { slot: number, from: CFrame, fromFov: number, t: number }
type Punch = { degrees: number, duration: number, t: number }
type Shake = { amplitude: number, duration: number, t: number }

local travel: Travel? = nil
local ascendTravel: AscendTravel? = nil
local lease: string? = nil -- bail en cours (« show », « photo », « binoculars »)
local saved: Saved? = nil -- état de la caméra gardé à la prise du premier bail
local onLost: { [string]: () -> () } = {}
local punch: Punch? = nil
local shakeState: Shake? = nil
local baseFov: number? = nil
local spectators: { { burstAt: number } } = {}
local megaLandSeen = 0 -- index du MEGA dont l'atterrissage a déjà secoué
local photo: Photo? = nil
local bino: Bino? = nil
-- SetPhotoMode : dernier état voulu, dernier envoyé, heure du dernier envoi (D26)
local photoWanted = false
local photoSent = false
local photoSentAt = -math.huge
local photoPending = false
local photoCount = { entries = 0, exits = 0, sends = 0 }
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

-- =============================================================================================
-- Bail de caméra (D27)
-- =============================================================================================

-- Prend le bail `kind` ; faux si un bail plus fort le tient. Le premier bail garde l'état de la
-- caméra ; un bail plus fort finit le plus faible (son rappel `lost`), l'état gardé reste le même.
function CameraController.takeLease(kind: string, lost: (() -> ())?): boolean
	local rank = PRIORITY[kind]
	local cam = camera()
	if rank == nil or cam == nil then
		return false
	end
	local cur = lease
	if cur == kind then
		if lost then
			onLost[kind] = lost
		end
		return true
	end
	if cur ~= nil and PRIORITY[cur] > rank then
		return false
	end
	if cur == nil then
		saved = {
			cameraType = cam.CameraType,
			subject = cam.CameraSubject,
			fov = cam.FieldOfView,
			cframe = cam.CFrame,
		}
	else
		local cb = onLost[cur]
		onLost[cur] = nil
		if cb then
			Util.guard("CameraController.leaseLost", cb)
		end
	end
	lease = kind
	onLost[kind] = lost
	return true
end

-- Rend le bail `kind` (sans effet s'il ne le tient pas) : l'état gardé revient exactement
function CameraController.giveLease(kind: string)
	if lease ~= kind then
		return
	end
	lease = nil
	onLost[kind] = nil
	local s = saved
	saved = nil
	local cam = camera()
	if s == nil or cam == nil then
		return
	end
	cam.CameraType = s.cameraType
	local subject = s.subject
	if subject ~= nil and subject.Parent ~= nil then
		cam.CameraSubject = subject
	end
	if punch == nil then
		cam.FieldOfView = s.fov
	else
		baseFov = s.fov -- le coup de focale en cours rendra cette focale-là
	end
	cam.CFrame = s.cframe
end

-- Bail en cours (nil : la caméra est au joueur)
function CameraController.leaseHolder(): string?
	return lease
end

local function restoreCamera()
	CameraController.giveLease("show")
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
	travel = {
		slot = slot,
		startedAt = startedAt,
		burstAt = burstAt,
		endsAt = endsAt,
		frames = 0,
		shaken = false,
		leased = false,
	}
end

-- Caméra de la Jelly Ascend du héros (D27) : suit la copie du Meilleur Ami (World/AscendPath)
function CameraController.ascend(startedAt: number, burstAt: number, endsAt: number)
	if not (Util.finite(startedAt) and Util.finite(burstAt) and Util.finite(endsAt)) then
		return
	end
	if endsAt <= startedAt or endsAt - startedAt > ASCEND_CUT or burstAt < startedAt or burstAt > endsAt then
		return
	end
	if reducedMotion() or Clock.now() >= endsAt or not Flags.on("JellyAscend") then
		return
	end
	local slot = WorldStateController.mySlot()
	local me = Players.LocalPlayer
	if slot == 0 or me == nil then
		return
	end
	ascendTravel = {
		slot = slot,
		userId = me.UserId,
		startedAt = startedAt,
		burstAt = burstAt,
		endsAt = endsAt,
		frames = 0,
		leased = false,
	}
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
	punch =
		{ degrees = math.clamp(degrees, -CAM.MaxFov, CAM.MaxFov), duration = math.min(duration, 2), t = 0 }
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
	return travel ~= nil or ascendTravel ~= nil
end

-- =============================================================================================
-- Mode photo « Cheese ! » (lot B5, étape 5 ; D24-D27)
-- =============================================================================================

local function lazy(name: string): any?
	local folder = Client:FindFirstChild("UI")
	local mod = folder and folder:FindFirstChild(name)
	if mod == nil or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, found = pcall(require, mod)
	return if ok and type(found) == "table" then found else nil
end

-- SetPhotoMode : au plus une fois par 1,2 s, seulement le dernier état voulu, jamais égal au dernier
-- envoyé (fire-and-forget : état en mémoire et analytique du serveur)
local function flushPhotoIntent()
	if photoWanted == photoSent then
		photoPending = false
		return
	end
	local now = Clock.now()
	if now - photoSentAt < PHOTO.SendEvery and now >= photoSentAt then
		photoPending = true
		return
	end
	photoPending = false
	photoSent = photoWanted
	photoSentAt = now
	photoCount.sends += 1
	local remote = Util.remote("SetPhotoMode")
	if remote then
		local on = photoSent
		pcall(function()
			remote:FireServer(on)
		end)
	end
end

local function wantPhoto(on: boolean)
	photoWanted = on
	flushPhotoIntent()
end

-- Point visé ramené dans la zone d'entrée (D27)
local function clampFocus(p: Photo, pos: Vector3): Vector3
	local x, z = pos.X, pos.Z
	if p.zone == "ranch" then
		local l = WorldLayout.toLocal(p.slot, pos)
		local lx = math.clamp(l.X, -PHOTO.RanchX, PHOTO.RanchX)
		local lz = math.clamp(l.Z, PHOTO.RanchZ[1], PHOTO.RanchZ[2])
		local w = WorldLayout.toWorld(p.slot, Vector3.new(lx, 0, lz))
		x, z = w.X, w.Z
	else
		local dx, dz = x - p.center.X, z - p.center.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > p.radius then
			x = p.center.X + dx / d * p.radius
			z = p.center.Z + dz / d * p.radius
		end
	end
	return Vector3.new(x, WorldLayout.groundY(x, z) + PHOTO.FocusUp, z)
end

-- Œil de la caméra : orbite autour du point visé, jamais sous le sol
local function photoEye(p: Photo): Vector3
	local c = math.cos(p.pitch)
	local eye = p.focus
		+ Vector3.new(c * math.sin(p.yaw) * p.dist, math.sin(p.pitch) * p.dist, c * math.cos(p.yaw) * p.dist)
	local floor = WorldLayout.groundY(eye.X, eye.Z) + PHOTO.GroundGap
	if eye.Y < floor then
		eye = Vector3.new(eye.X, floor, eye.Z)
	end
	return eye
end

local function axis(keys: { [Enum.KeyCode]: boolean }, plus: Enum.KeyCode, minus: Enum.KeyCode): number
	return (if keys[plus] then 1 else 0) - (if keys[minus] then 1 else 0)
end

local function dead(v: Vector2): Vector2
	if v.Magnitude < PHOTO.DeadZone then
		return Vector2.zero
	end
	return v
end

local function capUnit(v: Vector2): Vector2
	return if v.Magnitude > 1 then v.Unit else v
end

local function endPhoto(closeHud: boolean, giveBack: boolean)
	local p = photo
	if p == nil then
		return
	end
	photo = nil
	photoCount.exits += 1
	for _, name in { A_MOVE, A_TURN, A_ZOOM, A_FILTER } do
		ContextActionService:UnbindAction(name)
	end
	for _, c in p.conns do
		c:Disconnect()
	end
	table.clear(p.conns)
	if giveBack then
		CameraController.giveLease("photo")
	end
	if closeHud and p.hud then
		pcall(p.hud.close)
	end
	wantPhoto(false)
end

local function onPhotoAction(
	name: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	local p = photo
	if p == nil then
		return Enum.ContextActionResult.Pass
	end
	local key = input.KeyCode
	local down = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
	if key == Enum.KeyCode.Thumbstick1 or key == Enum.KeyCode.Thumbstick2 then
		local v = if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
			then Vector2.zero
			else dead(Vector2.new(input.Position.X, input.Position.Y))
		if key == Enum.KeyCode.Thumbstick1 then
			p.stickMove = v
		else
			p.stickTurn = v
		end
		if v.Magnitude > 0 and p.hud then
			pcall(p.hud.noteInput)
		end
		return Enum.ContextActionResult.Sink
	end
	if state == Enum.UserInputState.Begin then
		p.keys[key] = true
		if p.hud then
			pcall(p.hud.noteInput)
		end
		if name == A_FILTER and p.hud then
			pcall(p.hud.cycleFilter)
		end
	elseif not down then
		p.keys[key] = nil
	end
	return Enum.ContextActionResult.Sink
end

local function bindPhoto()
	ContextActionService:BindActionAtPriority(
		A_MOVE,
		onPhotoAction,
		false,
		PHOTO_PRIORITY,
		Enum.KeyCode.Thumbstick1,
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Space
	)
	ContextActionService:BindActionAtPriority(
		A_TURN,
		onPhotoAction,
		false,
		PHOTO_PRIORITY,
		Enum.KeyCode.Thumbstick2,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right
	)
	ContextActionService:BindActionAtPriority(
		A_ZOOM,
		onPhotoAction,
		false,
		PHOTO_PRIORITY,
		Enum.KeyCode.ButtonL2,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.PageUp,
		Enum.KeyCode.PageDown
	)
	ContextActionService:BindActionAtPriority(
		A_FILTER,
		onPhotoAction,
		false,
		PHOTO_PRIORITY,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.F
	)
end

-- Zone d'entrée (D27) : mon ranch, sinon le disque de la place, sinon 12 studs autour du personnage
local function entryZone(at: Vector3): (string, number, Vector3, number)
	local slot = WorldStateController.mySlot()
	if slot > 0 then
		local l = WorldLayout.toLocal(slot, at)
		if math.abs(l.X) <= PHOTO.RanchX and l.Z >= PHOTO.RanchZ[1] and l.Z <= PHOTO.RanchZ[2] then
			return "ranch", slot, at, 0
		end
	end
	local center = WorldLayout.plaza("center")
	if ZoneRules.distXZ(at, center) <= WorldLayout.Const.PlazaRadius then
		return "plaza", 0, center, WorldLayout.Const.PlazaRadius
	end
	return "self", 0, at, PHOTO.SelfRadius
end

-- Entre (vrai) ou sort (faux) du mode photo ; vrai : le mode photo est actif après l'appel
function CameraController.photo(on: boolean): boolean
	if on ~= true then
		endPhoto(true, true)
		return false
	end
	if photo ~= nil then
		return true
	end
	if not Flags.on("PhotoMode") then
		return false
	end
	local player = Players.LocalPlayer
	local root = Util.localRoot()
	local cam = camera()
	if player == nil or root == nil or cam == nil then
		return false
	end
	local hud = lazy("PhotoHud")
	if hud == nil then
		return false
	end
	-- le bail : faux pendant un spectacle ; les jumelles se referment (leur rappel)
	local p: Photo
	if
		not CameraController.takeLease("photo", function()
			-- un spectacle prend la caméra : fin du mode photo SANS rendre le bail (il n'est plus à nous)
			endPhoto(true, false)
		end)
	then
		return false
	end
	local zone, slot, center, radius = entryZone(root.Position)
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local yaw = if flat.Magnitude > 1e-3 then math.atan2(-flat.X, -flat.Z) else 0
	p = {
		zone = zone,
		slot = slot,
		center = center,
		radius = radius,
		focus = root.Position,
		yaw = yaw,
		pitch = PHOTO.StartPitch,
		dist = PHOTO.StartDist,
		stickMove = Vector2.zero,
		stickTurn = Vector2.zero,
		keys = {},
		frames = 0,
		conns = {},
		hud = hud,
	}
	p.focus = clampFocus(p, root.Position)
	photo = p
	photoCount.entries += 1
	local ok, opened = pcall(hud.open, function()
		-- fenêtre fermée (○, ✕ sur le bouton, autre fenêtre, FocusGuard) : l'écran est déjà fermé
		endPhoto(false, true)
	end)
	if not ok or opened ~= true then
		endPhoto(false, true)
		return false
	end
	bindPhoto()
	-- sorties d'office : interrupteur coupé en direct, réapparition, mort
	table.insert(
		p.conns,
		Flags.Changed:Connect(function()
			if not Flags.on("PhotoMode") then
				endPhoto(true, true)
			end
		end)
	)
	table.insert(
		p.conns,
		player.CharacterAdded:Connect(function()
			endPhoto(true, true)
		end)
	)
	local hum = humanoid()
	if hum then
		table.insert(
			p.conns,
			hum.Died:Connect(function()
				endPhoto(true, true)
			end)
		)
	end
	local cheese: any = (Sounds :: any).Cheese
	Util.safe(
		"AudioController.play",
		nil,
		AudioController.play,
		if type(cheese) == "table"
				and type(cheese.id) == "string"
				and cheese.id ~= ""
			then "Cheese"
			else "Click"
	)
	wantPhoto(true)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(photoEye(p), p.focus)
	return true
end

-- Mode photo actif ?
function CameraController.photoOn(): boolean
	return photo ~= nil
end

local function stepPhoto(dt: number)
	local p = photo
	if p == nil then
		return
	end
	local cam = camera()
	p.frames += dt
	if cam == nil or p.frames > PHOTO.Timeout or Util.localRoot() == nil then
		endPhoto(true, true)
		return
	end
	local keys = p.keys
	local move = capUnit(
		p.stickMove
			+ Vector2.new(
				axis(keys, Enum.KeyCode.D, Enum.KeyCode.A),
				axis(keys, Enum.KeyCode.W, Enum.KeyCode.S)
			)
	)
	local turn = capUnit(
		p.stickTurn
			+ Vector2.new(
				axis(keys, Enum.KeyCode.Right, Enum.KeyCode.Left),
				axis(keys, Enum.KeyCode.Up, Enum.KeyCode.Down)
			)
	)
	local zoom = (if keys[Enum.KeyCode.ButtonL2] or keys[Enum.KeyCode.PageDown] then 1 else 0)
		- (if keys[Enum.KeyCode.ButtonR2] or keys[Enum.KeyCode.PageUp] then 1 else 0)
	p.yaw = (p.yaw - turn.X * PHOTO.Turn * dt) % (2 * math.pi)
	p.pitch = math.clamp(p.pitch - turn.Y * PHOTO.Tilt * dt, PHOTO.MinPitch, PHOTO.MaxPitch)
	p.dist = math.clamp(p.dist + zoom * PHOTO.Zoom * dt, PHOTO.MinDist, PHOTO.MaxDist)
	if move.Magnitude > 0 then
		local s, c = math.sin(p.yaw), math.cos(p.yaw)
		local forward = Vector3.new(-s, 0, -c)
		local right = Vector3.new(c, 0, -s)
		p.focus = clampFocus(p, p.focus + (right * move.X + forward * move.Y) * (PHOTO.Move * dt))
	end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(photoEye(p), p.focus)
	if p.hud then
		pcall(p.hud.tick)
	end
end

-- État du mode photo (specs) : zone, point visé, œil, distance, angles
function CameraController._photoState(): { [string]: any }?
	local p = photo
	if p == nil then
		return nil
	end
	return {
		zone = p.zone,
		slot = p.slot,
		center = p.center,
		radius = p.radius,
		focus = p.focus,
		eye = photoEye(p),
		dist = p.dist,
		pitch = p.pitch,
		yaw = p.yaw,
		frames = p.frames,
	}
end

-- Compteurs du mode photo et de SetPhotoMode (specs, Diagnostics)
function CameraController.photoStats(): { [string]: any }
	return {
		entries = photoCount.entries,
		exits = photoCount.exits,
		sends = photoCount.sends,
		wanted = photoWanted,
		sent = photoSent,
		pending = photoPending,
	}
end

-- =============================================================================================
-- Zoom des jumelles (lot B5, étape 5 ; D28)
-- =============================================================================================

local function binoView(slot: number): CFrame
	local gate = WorldLayout.toWorld(slot, Vector3.zero)
	local out = WorldLayout.toWorld(slot, Vector3.new(0, 0, -BINO.Out))
	local eye = Vector3.new(out.X, gate.Y + BINO.Up, out.Z)
	return CFrame.lookAt(eye, WorldLayout.toWorld(slot, Vector3.new(0, 0, BINO.LookZ)))
end

local function closeBinocularsWindow()
	local b = lazy("Binoculars")
	if b and type(b.close) == "function" then
		pcall(b.close)
	end
end

-- Regarde le ranch `slot` (nil : rend la caméra) ; appelé par UI/Binoculars
function CameraController.binoculars(slot: number?)
	if
		type(slot) ~= "number"
		or slot ~= slot
		or slot % 1 ~= 0
		or slot < 1
		or slot > WorldLayout.Const.Ranches
	then
		if bino ~= nil then
			bino = nil
			CameraController.giveLease("binoculars")
		end
		return
	end
	local cur = bino
	if cur ~= nil and cur.slot == slot then
		return
	end
	local cam = camera()
	if cam == nil then
		return
	end
	if
		not CameraController.takeLease("binoculars", function()
			-- un bail plus fort (photo, spectacle) : les jumelles se referment, le bail n'est plus à nous
			bino = nil
			closeBinocularsWindow()
		end)
	then
		return
	end
	bino = {
		slot = slot,
		from = cam.CFrame,
		fromFov = cam.FieldOfView,
		t = if reducedMotion() then BINO.Time else 0,
	}
	cam.CameraType = Enum.CameraType.Scriptable
	if reducedMotion() then
		cam.CFrame = binoView(slot)
		cam.FieldOfView = BINO.Fov
	end
end

-- Vue des jumelles en cours (specs)
function CameraController.binocularsSlot(): number?
	local b = bino
	return if b then b.slot else nil
end

local function stepBinoculars(dt: number)
	local b = bino
	if b == nil then
		return
	end
	local cam = camera()
	local root = Util.localRoot()
	local gate = WorldLayout.toWorld(b.slot, Vector3.zero)
	if cam == nil or root == nil or ZoneRules.distXZ(root.Position, gate) > BINO.Leave then
		-- le joueur s'éloigne : la caméra revient, la fenêtre se referme
		bino = nil
		CameraController.giveLease("binoculars")
		closeBinocularsWindow()
		return
	end
	b.t += dt
	local k = math.clamp(b.t / BINO.Time, 0, 1)
	k = k * k * (3 - 2 * k)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = b.from:Lerp(binoView(b.slot), k)
	cam.FieldOfView = b.fromFov + (BINO.Fov - b.fromFov) * k
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
		if tr.leased then
			restoreCamera()
		end
		return
	end
	if not tr.leased then
		-- un seul travelling de spectacle, le plus récent (relecture approfondie B5, journal B5-65) : le
		-- bail « show » est partagé ; sans ceci, la fin du Grand Splorch rendait la caméra pendant que
		-- la Jelly Ascend continuait de l'écrire, et sa fin ne la rendait plus (caméra scriptée)
		ascendTravel = nil
		-- le bail « show » garde l'état de la caméra (comme baseType avant, à la première image)
		tr.leased = CameraController.takeLease("show", function()
			travel = nil
		end)
		if not tr.leased then
			travel = nil
			return
		end
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

-- Caméra de la Jelly Ascend : devant le ranch (vers la place), regarde la copie qui monte et redescend
local function stepAscend(dt: number)
	local tr = ascendTravel
	if tr == nil then
		return
	end
	local cam = camera()
	local now = Clock.now()
	tr.frames += dt
	local r = WorldStateController.ranch(tr.slot)
	local gone = r == nil or r.userId ~= tr.userId
	if
		cam == nil
		or now >= tr.endsAt
		or tr.frames > ASCEND_CUT
		or reducedMotion()
		or gone
		or not Flags.on("JellyAscend")
	then
		ascendTravel = nil
		if tr.leased then
			CameraController.giveLease("show")
		end
		return
	end
	if not tr.leased then
		travel = nil -- un seul travelling de spectacle
		tr.leased = CameraController.takeLease("show", function()
			ascendTravel = nil
		end)
		if not tr.leased then
			ascendTravel = nil
			return
		end
	end
	local s = AscendPath.sample(tr.slot, tr.startedAt, tr.burstAt, tr.endsAt, now)
	local look = WorldLayout.v2Anchor(tr.slot, "sky").LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, 1)
	end
	local eye = s.pos + flat.Unit * ASCEND_BACK + Vector3.new(0, ASCEND_UP, 0)
	local c = cam :: Camera
	c.CameraType = Enum.CameraType.Scriptable
	c.CFrame = CFrame.lookAt(eye, s.pos)
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
	if ascendTravel then
		stepAscend(d)
	end
	-- lot B5 (étape 5) : mode photo, jumelles, SetPhotoMode en attente (un seul test)
	if photo or bino or photoPending then
		stepPhoto(d)
		stepBinoculars(d)
		if photoPending then
			flushPhotoIntent()
		end
	end
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
			-- MON Grand Splorch : fin du mode photo (aussi en Mouvement réduit, sans travelling)
			endPhoto(true, true)
			CameraController.splorch(startedAt, burstAt, endsAt)
		elseif Util.finite(burstAt) and #spectators < 8 then
			table.insert(spectators, { burstAt = burstAt })
		end
	elseif kind == "ascend" then
		-- v2.0 (lot B5) : héros seul, interrupteur JellyAscend ouvert (vérifié par ascend)
		if me and data.userId == me.UserId and me.UserId ~= 0 then
			endPhoto(true, true)
			CameraController.ascend(data.startedAt, data.burstAt, data.endsAt)
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
	ascendTravel = nil
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

-- Coupe les connexions (fin de session, specs)
function CameraController._stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	-- un travelling en cours rend la caméra (bail « show »)
	travel = nil
	ascendTravel = nil
	CameraController.giveLease("show")
	endPhoto(true, true)
	CameraController.binoculars(nil)
	started = false
end

return CameraController
