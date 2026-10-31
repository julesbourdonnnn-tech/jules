--!strict
-- VFXController — paquet « client-world » (docs/04-architecture.md §13.8).
-- Effets 3D du §9 (le juice d'écran — tampons, pièces volantes, vignette — est dans UI/ScreenFX,
-- paquet client-hud). Réserves d'instances (aucune création en rafale), une animation par propriété,
-- fondus de pièces 3D en RÉTRÉCISSANT (Transparency reste 0 ou 1). Mouvement réduit : pas de
-- secousse, de coup de focale ni de flash. Graphismes légers : particules × 0,3, pas de Trail sauf
-- la Comète, Highlight seulement sur le porteur, lumières coupées au-delà de 60 studs.
-- Responsabilités (réactions aux signaux de WorldStateController, répartition imposée du §13.2) :
--   * capture : 10 particules couleur de rareté, « +1 Puffkin » (taille selon la rareté), « ? » doré
--     si nouvelle entrée ; Rare+ : colonne Néon 0,6 s ; Épique+ : focale 70 → 74 → 70, vibration ;
--     Légendaire+ : colonne de 4 s (tout le serveur) ; Mythique+ : confettis, flash, secousse
--   * coupe : 12 étincelles, « SNIP ! » 3D (Elastic Out) au point touché ; victime : traînées de
--     vitesse 3 s ; coupeur : anneau Snip Rush de 6 studs pendant 3 s ; Gloomwisp : « miam ! »
--   * parade : « +valeur » sur les 12 premiers puis un total, 3 feux d'artifice si ≥ 15, flash de
--     l'arche ; Balise : 5 orbes vers la Balise
--   * Comète : traversée du ciel (6 s), impact (3 anneaux, PointLight, pilier, secousse selon la
--     distance), porteur (anneau de 8 boules dorées, Highlight, faisceau de 200 studs), vol (son),
--     encaissement (5 feux) / explosion (l'orbe clignote 3 fois)
--   * Gloomwisp éclaté, Supernova (séquence de 2,5 s sur l'augmentation de l'attribut Supernovas
--     d'un Nid, nouvelle étoile de constellation), amélioration (anneau au sol, silhouette fantôme,
--     perchoir), Dash (Trail + focale), bouclier débutant (bulles qui éclatent), Zen (anneau
--     turquoise), étoile bleue des équipiers, étincelles roses d'immunité, pings (BillboardGui 4 × 4,
--     2,5 s, visible à 200 studs), acclamations (arc de confettis vers le Nid du héros)
-- Une seule connexion RenderStepped (animations suivies image par image).
-- GDD : §9.1 (fonctions), §9.4, §11.6, §13.2.
-- Dépendances : StateController, AudioController, Util/Prefs, UI/Juice, WorldStateController,
-- CongaRenderer, Render/NebbyBuilder, Logic/WorldLayout, Logic/Formulas, Config/*,
-- Shared/Util/Clock, World/{Fx,FloatText}.

local CollectionService = game:GetService("CollectionService")
local HapticService = game:GetService("HapticService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Nebbies = require(Shared.Config.Nebbies)
local Zones = require(Shared.Config.Zones)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Formulas = require(Shared.Logic.Formulas)
local NebbyBuilder = require(Shared.Render.NebbyBuilder)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Juice = require(Client.UI.Juice)
local WorldStateController = require(Client.Controllers.WorldStateController)
local CongaRenderer = require(Client.Controllers.CongaRenderer)
local Fx = require(Client.World.Fx)
local FloatText = require(Client.World.FloatText)

local VFXController = {}

-- Constantes (GDD §9.4, §11.6, §12.8) ------------------------------------------------------------------

local Render = Balance.Render
local EFFECT_RANGE = 160 -- studs : effets locaux joués seulement près du point de vue
local SOUND_RANGE = 120
local EMITTERS = 6
local MAX_EMIT = 60 -- particules par appel
local PARTICLE_WINDOW = 1 -- s : durée de vie typique d'une particule (budget ≤ 300 à l'écran)
local RING_START_THICKNESS, RING_END_THICKNESS = 0.4, 0.05
local PILLAR_DIAMETER = 1.5
local PILLAR_HEIGHT = 30
local LEGEND_PILLAR_HEIGHT = 160
local LEGEND_PILLAR_SECONDS = 4
local RARE_PILLAR_SECONDS = 0.6
local CATCH_PARTICLES = 10
local CONFETTI = 60
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 110, 150),
	Color3.fromRGB(120, 220, 255),
	Color3.fromRGB(255, 230, 110),
	Color3.fromRGB(150, 255, 170),
}
local EPIC_FOV, EPIC_FOV_OUT, EPIC_FOV_BACK = 4, 0.1, 0.15
local DASH_FOV, DASH_FOV_OUT, DASH_FOV_BACK = 8, 0.12, 0.5
local DASH_SECONDS = Balance.Dash.Duration
local MYTHIC_FLASH_ALPHA, MYTHIC_FLASH_SECONDS = 0.35, 0.12
local MYTHIC_SHAKE, SHAKE_SECONDS = 0.3, 0.3
local SNIP_SPARKS = 12
local SNIP_RUSH_DIAMETER = 6
local WISP_PUFFS = 6
local WISP_SPARKS = 16
local WISP_DARK = Color3.fromRGB(45, 35, 80)
local PARADE_FLOATS = 12
local PARADE_FLOAT_STEP = 0.06
local PARADE_COLOR = Color3.fromRGB(255, 220, 110)
local FIREWORK_RISE = 0.5
local FIREWORK_HEIGHT = 16
local FIREWORK_SPARKS = 24
local ARCH_FLASH_SECONDS = 0.35
local BEACON_ORBS, BEACON_ORB_SECONDS = 5, 0.5
local COMET_RING_COUNT, COMET_RING_RADIUS, COMET_RING_SECONDS, COMET_RING_STAGGER = 3, 60, 0.8, 0.15
local COMET_LIGHT_RANGE, COMET_LIGHT_PEAK, COMET_LIGHT_REST, COMET_LIGHT_SECONDS = 40, 8, 1, 1
local COMET_SHAKE, COMET_SHAKE_RANGE = 0.4, 120
local COMET_BEAM_HEIGHT, COMET_BEAM_WIDTH = 200, 3
local COMET_GOLD = Color3.fromRGB(255, 205, 60)
local CARRIER_BALLS, CARRIER_RADIUS, CARRIER_SPIN, CARRIER_LIFT = 8, 2.2, 1.2, 1.5
local IMPACT_FRESH = 2 -- s : impact rejoué seulement s'il vient d'avoir lieu
local SUPERNOVA_BEAM_HEIGHT, SUPERNOVA_BEAM_WIDTH = 300, 8
local SUPERNOVA_SPHERE = 40
local SUPERNOVA_COLOR = Color3.fromRGB(255, 245, 220)
local SUPERNOVA_BRIGHTNESS = 0.5
local STAR_POP = 1.2
local STAR_TRACE_SECONDS = 0.6
local CHEER_WINDOW = Balance.Cheer.Window + 2
local CHEER_SECONDS = 1
local UPGRADE_RING = 12
local UPGRADE_RING_SECONDS = 0.4
local GHOST_SECONDS = 1
local ZEN_FADE = 0.3
local PING_SIZE = 4
local PING_POOL = 6
local PING_POP = 0.25
local PING_FADE = 0.2
local BUBBLE_POP_STEP = 0.05
local ROOT_TO_FEET = 3
-- s après l'arrivée d'un propriétaire pendant lesquelles le premier changement de l'attribut
-- Supernovas est le chargement de son profil (pas une Supernova)
local SUPERNOVA_ARM_SECONDS = 30
local ANIM_WARN_INTERVAL = 10
local HAPTIC_INPUTS = { Enum.UserInputType.Touch, Enum.UserInputType.Gamepad1 }
local BEACON_TOP = Vector3.new(0, Zones.Beacon.StarY, 0) -- étoile au sommet de la Balise
local TAU = 2 * math.pi

-- État ------------------------------------------------------------------------------------------------------

type Anim = (t: number) -> boolean -- true quand l'animation est finie

type PingEntry = {
	attachment: Attachment,
	gui: BillboardGui,
	label: TextLabel,
	scale: UIScale,
	userId: number,
	untilAt: number,
	token: number,
	tweens: { Tween }, -- tweens de l'affichage en cours (annulés quand la bulle est reprise)
}

type ArchFlash = { original: Color3, token: number }

type CarrierFx = {
	balls: { BasePart },
	highlight: Highlight,
	top: Attachment,
	bottom: Attachment,
	beam: Beam,
}

local started = false
local folder: Folder? = nil
local anchor: BasePart? = nil
local anims: { Anim } = {}
local emitters: { { part: BasePart, emitter: ParticleEmitter } } = {}
local emitterCursor = 0
local emittedLog: { { at: number, n: number } } = {}
local ringPool: { BasePart } = {}
local ballPool: { BasePart } = {}
local fovBase: number? = nil
local fovToken = 0
local correction: ColorCorrectionEffect? = nil
local supernovaSeen: { [number]: number } = {}
local supernovaLoaded: { [number]: boolean } = {} -- profil du propriétaire du Nid déjà chargé
local supernovaOwnerAt: { [number]: number } = {} -- instant du dernier changement de propriétaire
local lastHero: { slot: number, at: number }? = nil
local zenRings: { [Player]: BasePart } = {}
local crewStars: { [Player]: BillboardGui } = {}
local immunity: { [Player]: Sparkles } = {}
local pings: { PingEntry } = {}
local pingCursor = 0
local sky: Model? = nil
local skyCometId: number? = nil
local groundBeam: { top: Attachment, bottom: Attachment, beam: Beam }? = nil
local carrierFx: CarrierFx? = nil
local lastCometPos: Vector3? = nil
local lastCometId: number? = nil
local warnedComet: number? = nil
local impactedComet: number? = nil
local rushRing: { part: BasePart, untilAt: number }? = nil
local archFlash: { [BasePart]: ArchFlash } = setmetatable({}, { __mode = "k" }) :: any
local playerConns: { [Player]: { RBXScriptConnection } } = {}
local rookieWas = false
local lastAnimWarn = -math.huge
local lastStatus = -math.huge

-- Outils ----------------------------------------------------------------------------------------------------

local function reduced(): boolean
	return Prefs.reducedMotion()
end

local function low(): boolean
	return Prefs.lowGraphics()
end

local function vfxFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local created = Fx.folder(Fx.clientWorld(), "VFX")
	folder = created
	return created
end

local function anchorPart(): BasePart
	local a = anchor
	if a and a.Parent then
		return a
	end
	local created = Fx.anchor("VFXAnchor", vfxFolder())
	anchor = created
	return created
end

local function localRoot(): BasePart?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local part = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function focus(): Vector3
	local root = localRoot()
	if root then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

local function near(pos: Vector3, range: number): boolean
	return (pos - focus()).Magnitude <= range
end

local function playSound(name: string, pos: Vector3?, variation: number?)
	if pos == nil or near(pos, SOUND_RANGE) then
		AudioController.play(name, variation)
	end
end

local function rootOfUser(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local part = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

-- Position (racine) d'un joueur : personnage s'il est chargé, sinon tête de ses miettes serveur
local function userPosition(userId: number): Vector3?
	local root = rootOfUser(userId)
	if root then
		return root.Position
	end
	local slot = WorldStateController.slotOf(userId)
	if slot ~= 0 then
		return CongaRenderer.headPosition(slot)
	end
	return nil
end

local function addAnim(fn: Anim)
	table.insert(anims, fn)
end

local function rarityDef(code: number): Nebbies.RarityDef
	local s = Nebbies.unpack(code)
	return Nebbies.Rarities[Nebbies.rarityOf(s)] or Nebbies.Rarities[1]
end

-- Réserves de pièces -----------------------------------------------------------------------------------------

local function takeRing(color: Color3): BasePart
	local part = table.remove(ringPool) or Fx.ring("FxRing", 1, RING_START_THICKNESS, color)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Parent = vfxFolder()
	return part
end

local function giveRing(part: BasePart)
	part.Parent = nil
	table.insert(ringPool, part)
end

local function takeBall(color: Color3, size: number): BasePart
	local part = table.remove(ballPool) or Fx.part("FxBall", "Ball", Vector3.one, color)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Size = Vector3.one * size
	part.Parent = vfxFolder()
	return part
end

local function giveBall(part: BasePart)
	part.Parent = nil
	table.insert(ballPool, part)
end

local function buildEmitters()
	if #emitters > 0 and emitters[1].part.Parent then
		return
	end
	table.clear(emitters)
	for i = 1, EMITTERS do
		local part = Fx.part("Emitter" .. i, "Block", Vector3.one * 0.5, Color3.new(1, 1, 1))
		part.Transparency = 1
		part.Parent = vfxFolder()
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Burst"
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(8, 16)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 4
		emitter.LightEmission = 0.8
		emitter.Size = NumberSequence.new(0.45, 0)
		emitter.Parent = part
		emitters[i] = { part = part, emitter = emitter }
	end
end

-- Particules encore à l'écran (fenêtre glissante) : budget ≤ Render.MaxParticles
local function particleBudget(now: number): number
	local alive = 0
	for i = #emittedLog, 1, -1 do
		local e = emittedLog[i]
		if now - e.at > PARTICLE_WINDOW then
			table.remove(emittedLog, i)
		else
			alive += e.n
		end
	end
	return math.max(0, Render.MaxParticles - alive)
end

-- Tweens de pièces 3D (Juice : une seule animation par propriété)
local function tween(
	inst: Instance,
	seconds: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	return Juice.tween(inst, seconds, props, style, dir)
end

-- API publique (GDD §9.1) -----------------------------------------------------------------------------------

-- Texte « +N » dans le monde (réserve de 20 BillboardGui)
function VFXController.floatText(worldPos: Vector3, text: string, color: Color3, scale: number?)
	FloatText.show(worldPos, text, color, scale)
end

-- Onde Néon au sol (Cylinder plat) de 0 à `radius`
function VFXController.ring(worldPos: Vector3, radius: number, color: Color3, duration: number)
	if radius ~= radius or radius <= 0 or duration ~= duration then
		return
	end
	local part = takeRing(color)
	local seconds = math.max(0.05, duration)
	part.Size = Vector3.new(RING_START_THICKNESS, 0.2, 0.2)
	part.CFrame = CFrame.new(worldPos + Vector3.new(0, 0.15, 0)) * Fx.FLAT
	tween(part, seconds, { Size = Vector3.new(RING_END_THICKNESS, radius * 2, radius * 2) })
	task.delay(seconds, function()
		giveRing(part)
	end)
end

-- ParticleEmitter:Emit sur un émetteur réutilisé (× 0,3 en Graphismes légers, budget ≤ 300)
function VFXController.burst(worldPos: Vector3, color: Color3, count: number)
	if count ~= count or count <= 0 then
		return
	end
	buildEmitters()
	local now = Clock.now()
	local n = math.floor(count * (if low() then Render.LowGraphicsParticleMult else 1) + 0.5)
	n = math.min(n, MAX_EMIT, particleBudget(now))
	if n <= 0 then
		return
	end
	emitterCursor = emitterCursor % #emitters + 1
	local e = emitters[emitterCursor]
	e.part.CFrame = CFrame.new(worldPos)
	e.emitter.Color = ColorSequence.new(color)
	e.emitter:Emit(n)
	table.insert(emittedLog, { at = now, n = n })
end

-- Colonne Néon qui s'amincit
function VFXController.pillar(worldPos: Vector3, color: Color3, duration: number, height: number?)
	local h = height or PILLAR_HEIGHT
	if h ~= h or h <= 0 or duration ~= duration then
		return
	end
	local part = takeRing(color)
	local seconds = math.max(0.05, duration)
	part.Size = Vector3.new(h, PILLAR_DIAMETER, PILLAR_DIAMETER)
	part.CFrame = CFrame.new(worldPos + Vector3.new(0, h / 2, 0)) * Fx.FLAT
	tween(
		part,
		seconds,
		{ Size = Vector3.new(h, 0.05, 0.05) },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	task.delay(seconds, function()
		giveRing(part)
	end)
end

-- Coup de focale (ignoré en Mouvement réduit)
function VFXController.fovPunch(delta: number, outTime: number, backTime: number)
	if reduced() or delta ~= delta then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local base = fovBase or camera.FieldOfView
	fovBase = base
	fovToken += 1
	local token = fovToken
	local out = tween(camera, math.max(0.01, outTime), { FieldOfView = base + delta })
	out.Completed:Once(function()
		if fovToken ~= token then
			return
		end
		local back = tween(
			camera,
			math.max(0.01, backTime),
			{ FieldOfView = base },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		back.Completed:Once(function()
			if fovToken == token then
				fovBase = nil
			end
		end)
	end)
end

-- Vibration mobile / manette via HapticService si supportée
function VFXController.haptic(strength: number, duration: number)
	if strength ~= strength or duration ~= duration then
		return
	end
	local power = math.clamp(strength, 0, 1)
	local motor = Enum.VibrationMotor.Small
	-- mobile d'abord (GDD §9.1 « vibration mobile »), puis manette
	local inputType: Enum.UserInputType? = nil
	for _, candidate in HAPTIC_INPUTS do
		local ok, supported = pcall(function()
			return HapticService:IsVibrationSupported(candidate)
				and HapticService:IsMotorSupported(candidate, motor)
		end)
		if ok and supported then
			inputType = candidate
			break
		end
	end
	if inputType == nil then
		return
	end
	pcall(function()
		HapticService:SetMotor(inputType, motor, power)
	end)
	task.delay(math.clamp(duration, 0, 1), function()
		pcall(function()
			HapticService:SetMotor(inputType, motor, 0)
		end)
	end)
end

-- Feux d'artifice Néon : une boule monte puis éclate (décalés de 0,15 s)
function VFXController.fireworks(worldPos: Vector3, count: number, color: Color3?)
	if count ~= count or count <= 0 then
		return
	end
	local rng = Random.new()
	for k = 1, math.min(math.floor(count), 8) do
		local c = color or CONFETTI_COLORS[(k - 1) % #CONFETTI_COLORS + 1]
		task.delay((k - 1) * 0.15, function()
			local offset = Vector3.new(
				rng:NextNumber(-6, 6),
				FIREWORK_HEIGHT + rng:NextNumber(-3, 4),
				rng:NextNumber(-6, 6)
			)
			local top = worldPos + offset
			if reduced() then
				VFXController.burst(top, c, FIREWORK_SPARKS)
				return
			end
			local ball = takeBall(c, 0.8)
			ball.CFrame = CFrame.new(worldPos)
			tween(ball, FIREWORK_RISE, { CFrame = CFrame.new(top) })
			task.delay(FIREWORK_RISE, function()
				giveBall(ball)
				VFXController.burst(top, c, FIREWORK_SPARKS)
				VFXController.ring(top, 4, c, 0.3)
			end)
		end)
	end
end

-- Dash local confirmé par InputController : Trail aux pieds 1 s, nuage, focale 70 → 78 → 70
function VFXController.playDash()
	local root = localRoot()
	if root == nil then
		return
	end
	VFXController.burst(root.Position - Vector3.new(0, ROOT_TO_FEET - 0.5, 0), Color3.new(1, 1, 1), 8)
	VFXController.fovPunch(DASH_FOV, DASH_FOV_OUT, DASH_FOV_BACK)
	if low() then
		return -- pas de Trail en Graphismes légers (sauf la Comète)
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "DashTrail0"
	a0.Position = Vector3.new(0, -ROOT_TO_FEET + 1, 0.5)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "DashTrail1"
	a1.Position = Vector3.new(0, -ROOT_TO_FEET + 0.2, 0.5)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "DashTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(170, 235, 255), Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = root
	task.delay(DASH_SECONDS, function()
		trail:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- Amélioration (anneau, fantôme Conga, perchoir) — appelé par ScreenFX sur Celebrate "upgrade"
function VFXController.playUpgrade(track: string, level: number)
	local root = localRoot()
	AudioController.play("LevelUp")
	if root == nil then
		return
	end
	local feet = root.Position - Vector3.new(0, ROOT_TO_FEET, 0)
	VFXController.ring(feet, UPGRADE_RING, Color3.fromRGB(120, 230, 255), UPGRADE_RING_SECONDS)
	local slot = WorldStateController.localSlot()
	if track == "conga" then
		-- silhouette fantôme (Ball ForceField) au bout de la file pendant 1 s
		local positions = CongaRenderer.nodePositions(slot)
		local tail = positions[#positions]
		local spot = if tail
			then tail + Vector3.new(0, -ROOT_TO_FEET + 1, 0)
			else feet + root.CFrame.LookVector * -Balance.Conga.HeadGap + Vector3.new(0, 1, 0)
		local ghost = takeBall(Color3.fromRGB(200, 240, 255), 1.8)
		ghost.Material = Enum.Material.ForceField
		ghost.CFrame = CFrame.new(spot + Vector3.new(0, 0.9, 0))
		tween(
			ghost,
			GHOST_SECONDS,
			{ Size = Vector3.one * 0.1 },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		task.delay(GHOST_SECONDS, function()
			giveBall(ghost)
		end)
	elseif track == "perches" and slot ~= 0 then
		local count = math.max(CongaRenderer.perchCount(slot), math.floor(level))
		local top = CongaRenderer.perchTop(slot, math.clamp(count, 1, 46))
		if top then
			VFXController.burst(top, Color3.fromRGB(150, 110, 70), 10)
		end
	end
end

-- Séquence de Supernova (2,5 s) au Nid du slot
function VFXController.playSupernova(slot: number, level: number)
	if type(slot) ~= "number" or slot < 1 or slot > Zones.Nests.Count or slot % 1 ~= 0 then
		return
	end
	local center = WorldLayout.nestCenter(slot)
	local hero = slot == WorldStateController.localSlot()
	local visible = hero or near(center, 400)
	lastHero = { slot = slot, at = Clock.now() }
	if hero or near(center, SOUND_RANGE * 1.5) then
		AudioController.play("Supernova")
	end
	if not visible then
		return
	end
	-- t = 0 : éclairage surexposé + teinte blanche (héros, sauf Mouvement réduit : pas de flash)
	if hero and not reduced() then
		local cc = correction
		if cc == nil or cc.Parent == nil then
			-- effet posé sur la caméra (et non dans Lighting, piloté par LightingController)
			local created = Instance.new("ColorCorrectionEffect")
			created.Name = "VFXSupernova"
			created.Brightness = 0
			created.TintColor = Color3.new(1, 1, 1)
			created.Parent = workspace.CurrentCamera or Lighting
			correction = created
			cc = created
		end
		local c = cc :: ColorCorrectionEffect
		tween(c, 0.6, { Brightness = SUPERNOVA_BRIGHTNESS, TintColor = Color3.fromRGB(255, 250, 240) })
		task.delay(2, function()
			tween(c, 0.5, { Brightness = 0, TintColor = Color3.new(1, 1, 1) })
		end)
		Juice.cameraShake(MYTHIC_SHAKE, SHAKE_SECONDS)
	end
	-- t = 0,3 : faisceau du Nid vers le ciel (largeur 0 → 8)
	task.delay(0.3, function()
		local beam = takeRing(SUPERNOVA_COLOR)
		beam.Size = Vector3.new(SUPERNOVA_BEAM_HEIGHT, 0.1, 0.1)
		beam.CFrame = CFrame.new(center + Vector3.new(0, SUPERNOVA_BEAM_HEIGHT / 2, 0)) * Fx.FLAT
		tween(
			beam,
			0.4,
			{ Size = Vector3.new(SUPERNOVA_BEAM_HEIGHT, SUPERNOVA_BEAM_WIDTH, SUPERNOVA_BEAM_WIDTH) }
		)
		task.delay(1.5, function()
			tween(
				beam,
				0.5,
				{ Size = Vector3.new(SUPERNOVA_BEAM_HEIGHT, 0.05, 0.05) },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			task.delay(0.5, function()
				giveRing(beam)
			end)
		end)
	end)
	-- t = 0,6 : sphère Néon 0 → 40 en 0,8 s (Quad Out) puis effondrement 0,4 s (Back In)
	task.delay(0.6, function()
		local sphere = takeBall(SUPERNOVA_COLOR, 0.1)
		sphere.CFrame = CFrame.new(center + Vector3.new(0, 6, 0))
		if reduced() then
			sphere.Size = Vector3.one * SUPERNOVA_SPHERE
			task.delay(1.2, function()
				giveBall(sphere)
			end)
			return
		end
		tween(sphere, 0.8, { Size = Vector3.one * SUPERNOVA_SPHERE })
		task.delay(0.8, function()
			tween(sphere, 0.4, { Size = Vector3.one * 0.1 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.delay(0.4, function()
				giveBall(sphere)
			end)
		end)
	end)
	-- nouvelle étoile de constellation : pop 0 → 1,2 (Back Out) puis Beam tracé en 0,6 s
	task.delay(0.6, function()
		local star = CongaRenderer.constellationStar(slot, math.floor(level))
		if star == nil then
			return
		end
		local size = star.Size
		if not reduced() then
			star.Size = Vector3.one * 0.05
			tween(
				star,
				0.3,
				{ Size = Vector3.one * STAR_POP },
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
		end
		VFXController.burst(star.Position, SUPERNOVA_COLOR, 12)
		local beam = star:FindFirstChildOfClass("Beam")
		local prev = CongaRenderer.constellationStar(slot, math.floor(level) - 1)
		local link = star:FindFirstChild("Link")
		if beam and prev and link and link:IsA("Attachment") and not reduced() then
			local moving = Instance.new("Attachment")
			moving.Name = "StarTrace"
			moving.Position = prev.Position
			moving.Parent = anchorPart()
			beam.Attachment1 = moving
			local start = Clock.now()
			local from, to = prev.Position, star.Position
			addAnim(function(t: number): boolean
				local a = (t - start) / STAR_TRACE_SECONDS
				if a >= 1 or beam.Parent == nil then
					if beam.Parent then
						beam.Attachment1 = link
					end
					moving:Destroy()
					return true
				end
				moving.Position = from:Lerp(to, Fx.quadOut(a))
				return false
			end)
		end
		task.delay(0.3, function()
			if star.Parent then
				star.Size = size
			end
		end)
	end)
end

-- Réactions : capture ------------------------------------------------------------------------------------------

local function isNewEntry(code: number): boolean
	local atlas = State.get("atlas")
	if type(atlas) ~= "table" then
		return false
	end
	local s, f = Nebbies.unpack(code)
	return not Nebbies.testBit(atlas, Nebbies.atlasIndex(s, f))
end

local function onCaught(slot: number, code: number, _id: number, pos: Vector3?)
	local at = pos or CongaRenderer.headPosition(slot)
	if at == nil then
		return
	end
	local p = at :: Vector3
	local rarity = rarityDef(code)
	local mine = slot ~= 0 and slot == WorldStateController.localSlot()
	-- Légendaire+ : colonne de 4 s visible par tout le serveur
	if rarity.banner then
		VFXController.pillar(p, rarity.color, LEGEND_PILLAR_SECONDS, LEGEND_PILLAR_HEIGHT)
	end
	if not mine and not near(p, EFFECT_RANGE) then
		return
	end
	VFXController.burst(p, rarity.color, CATCH_PARTICLES)
	if rarity.pillar and not rarity.banner then
		VFXController.pillar(p, rarity.color, RARE_PILLAR_SECONDS, PILLAR_HEIGHT)
	end
	if rarity.id >= 6 then
		for i, c in CONFETTI_COLORS do
			VFXController.burst(
				p + Vector3.new(0, 2, 0),
				if i == 1 then rarity.color else c,
				CONFETTI / #CONFETTI_COLORS
			)
		end
	end
	if not mine then
		return
	end
	local s = Nebbies.unpack(code)
	local species = Nebbies.Species[s]
	local scale = 0.8 + 0.8 * math.clamp((rarity.id - 1) / 5, 0, 1)
	FloatText.show(
		p + Vector3.new(0, 3, 0),
		Prefs.t("stamp.catch", { species = if species then species.name else "" }),
		rarity.color,
		scale
	)
	if isNewEntry(code) then
		FloatText.show(
			p + Vector3.new(0, 5.5, 0),
			Prefs.t("world.newEntry"),
			Color3.fromRGB(255, 205, 60),
			1.2
		)
	end
	AudioController.play(if rarity.id >= 3 then "CatchRare" else "Catch", 0.05)
	if rarity.id >= 4 then
		VFXController.fovPunch(EPIC_FOV, EPIC_FOV_OUT, EPIC_FOV_BACK)
		VFXController.haptic(0.4, 0.08)
	end
	if rarity.id >= 6 and not reduced() then
		Juice.flash(Color3.new(1, 1, 1), MYTHIC_FLASH_ALPHA, MYTHIC_FLASH_SECONDS)
		Juice.cameraShake(MYTHIC_SHAKE, SHAKE_SECONDS)
	end
end

-- Réactions : coupe --------------------------------------------------------------------------------------------

local function speedTrails(root: BasePart, seconds: number)
	if low() then
		VFXController.burst(root.Position - Vector3.new(0, ROOT_TO_FEET - 0.5, 0), Color3.new(1, 1, 1), 6)
		return
	end
	local made: { Instance } = {}
	for _, side in { -0.6, 0.6 } do
		local a0 = Instance.new("Attachment")
		a0.Name = "SpeedTrail0"
		a0.Position = Vector3.new(side, -ROOT_TO_FEET + 0.8, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "SpeedTrail1"
		a1.Position = Vector3.new(side, -ROOT_TO_FEET + 0.2, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = "SecondWind"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.3
		trail.FaceCamera = true
		trail.LightEmission = 0.7
		trail.Color = ColorSequence.new(Cosmetics.Readability.Snippable, Color3.new(1, 1, 1))
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Parent = root
		table.insert(made, trail)
		table.insert(made, a0)
		table.insert(made, a1)
	end
	task.delay(seconds, function()
		for _, inst in made do
			inst:Destroy()
		end
	end)
end

local function snipRush()
	local existing = rushRing
	local untilAt = Clock.now() + Balance.Snip.RushDuration
	if existing then
		existing.untilAt = untilAt
		return
	end
	local part = takeRing(Cosmetics.Readability.Snippable)
	part.Size = Vector3.new(0.15, SNIP_RUSH_DIAMETER, SNIP_RUSH_DIAMETER)
	local entry = { part = part, untilAt = untilAt }
	rushRing = entry
	addAnim(function(t: number): boolean
		local root = localRoot()
		if t >= entry.untilAt or root == nil then
			rushRing = nil
			giveRing(part)
			return true
		end
		local feet = root.Position - Vector3.new(0, ROOT_TO_FEET - 0.1, 0)
		part.CFrame = CFrame.new(feet) * CFrame.Angles(0, t * 2, 0) * Fx.FLAT
		return false
	end)
end

local function onSnipped(payload: Types.SnipEventPayload)
	local point = Vector3.new(payload.x, payload.y, payload.z)
	local localSlot = WorldStateController.localSlot()
	local victim = localSlot ~= 0 and payload.victimSlot == localSlot
	local snipper = localSlot ~= 0 and payload.snipperSlot == localSlot
	if not (victim or snipper or near(point, EFFECT_RANGE)) then
		return
	end
	VFXController.burst(point, Color3.new(1, 1, 1), SNIP_SPARKS)
	FloatText.show(point + Vector3.new(0, 2.5, 0), Prefs.t("stamp.snip"), Color3.new(1, 1, 1), 1.4, "stamp")
	if payload.byWisp then
		FloatText.show(point + Vector3.new(0, 5, 0), Prefs.t("stamp.nom"), Color3.fromRGB(200, 170, 255), 0.9)
		VFXController.burst(point, WISP_DARK, WISP_PUFFS)
	end
	playSound("Snip", point, if snipper then 0.02 else 0.08)
	if payload.count > 0 then
		playSound("Scatter", point)
	end
	if victim then
		local root = localRoot()
		if root then
			speedTrails(root, Balance.Speed.SecondWindDuration)
		end
	end
	if snipper then
		snipRush()
	end
end

-- Réactions : parade ---------------------------------------------------------------------------------------------

local function flashArch(slot: number)
	if reduced() then
		return
	end
	for _, part in CollectionService:GetTagged("NestArch") do
		if part:IsA("BasePart") and part:GetAttribute("slot") == slot then
			-- couleur d'origine lue UNE fois par flash en cours : un second flash pendant le premier
			-- relirait le blanc et laisserait l'arche blanche pour toujours
			local entry = archFlash[part]
			if entry == nil then
				entry = { original = part.Color, token = 0 }
				archFlash[part] = entry
			end
			local e = entry :: ArchFlash
			e.token += 1
			local token = e.token
			tween(part, ARCH_FLASH_SECONDS / 3, { Color = Color3.new(1, 1, 1) })
			task.delay(ARCH_FLASH_SECONDS / 3, function()
				if e.token ~= token then
					return
				end
				tween(part, ARCH_FLASH_SECONDS * 2 / 3, { Color = e.original })
				task.delay(ARCH_FLASH_SECONDS * 2 / 3, function()
					if e.token == token and archFlash[part] == e then
						archFlash[part] = nil
					end
				end)
			end)
		end
	end
end

local function beaconOrbs(from: Vector3)
	local target = BEACON_TOP
	for k = 1, BEACON_ORBS do
		task.delay((k - 1) * 0.05, function()
			local orb = takeBall(Zones.Beacon.RingColor, 0.7)
			local start = from + Vector3.new(math.cos(k * 1.3) * 1.5, 1 + k * 0.3, math.sin(k * 1.3) * 1.5)
			orb.CFrame = CFrame.new(start)
			if reduced() then
				task.delay(BEACON_ORB_SECONDS, function()
					giveBall(orb)
				end)
				return
			end
			local t0 = Clock.now()
			addAnim(function(t: number): boolean
				local a = (t - t0) / BEACON_ORB_SECONDS
				if a >= 1 then
					giveBall(orb)
					return true
				end
				local p = start:Lerp(target, Fx.quadIn(a)) + Vector3.new(0, Fx.arc(a, 6), 0)
				orb.CFrame = CFrame.new(p)
				return false
			end)
		end)
	end
end

local function onBanked(slot: number, op: Types.LineBankOp)
	local gate = WorldLayout.gateCFrame(slot)
	local gatePos = gate.Position
	local mine = slot ~= 0 and slot == WorldStateController.localSlot()
	local head = CongaRenderer.headPosition(slot) or gatePos
	if op.atBeacon then
		if mine or near(head, EFFECT_RANGE) then
			beaconOrbs(head)
			FloatText.show(
				BEACON_TOP + Vector3.new(0, 4, 0),
				Prefs.t("world.plus", { amount = op.count }),
				Zones.Beacon.RingColor,
				1
			)
		end
	end
	-- parade à la Balise : tout se passe à la Balise (proximité, totaux, feux), pas à la porte du Nid
	local origin = if op.atBeacon then head else gatePos
	if not mine and not near(origin, EFFECT_RANGE) then
		return
	end
	if mine then
		AudioController.play("Bank")
	end
	if not op.atBeacon then
		flashArch(slot)
	end
	-- « +valeur » sur les 12 premiers (parts du Glow réel), puis le total
	local codes = WorldStateController.previousCodes(slot)
	local total = 0
	for _, code in codes do
		total += Formulas.paradeValue(code)
	end
	local shown = math.min(#codes, PARADE_FLOATS)
	if mine and total > 0 and op.glow > 0 then
		for k = 1, shown do
			local share = op.glow * Formulas.paradeValue(codes[k]) / total
			task.delay((k - 1) * PARADE_FLOAT_STEP, function()
				local jitter = Vector3.new(math.cos(k * 2.4) * 2.5, 2 + (k % 3), math.sin(k * 2.4) * 2.5)
				FloatText.show(
					origin + jitter,
					Prefs.t("world.plus", { amount = Prefs.number(math.max(1, math.floor(share))) }),
					PARADE_COLOR,
					0.6
				)
			end)
		end
	end
	if op.glow > 0 then
		task.delay(shown * PARADE_FLOAT_STEP + 0.15, function()
			FloatText.show(
				origin + Vector3.new(0, 7, 0),
				Prefs.t("world.plus", { amount = Prefs.number(math.floor(op.glow)) }),
				PARADE_COLOR,
				if mine then 1.6 else 1
			)
		end)
	end
	if op.count >= Balance.Parade.FireworksMin then
		local above = if op.atBeacon then BEACON_TOP else WorldLayout.nestCenter(slot) + Vector3.new(0, 4, 0)
		VFXController.fireworks(above, 3)
	end
end

-- Réactions : Comète ---------------------------------------------------------------------------------------------

local function dropSky()
	if sky then
		sky:Destroy()
		sky = nil
		skyCometId = nil
	end
end

local function dropGroundBeam()
	local g = groundBeam
	if g then
		g.beam:Destroy()
		g.top:Destroy()
		g.bottom:Destroy()
		groundBeam = nil
	end
end

local function dropCarrier()
	local c = carrierFx
	if c then
		for _, ball in c.balls do
			giveBall(ball)
		end
		c.highlight:Destroy()
		c.beam:Destroy()
		c.top:Destroy()
		c.bottom:Destroy()
		carrierFx = nil
	end
end

local function makeBeam(name: string, color: Color3, width: number): (Attachment, Attachment, Beam)
	local parent = anchorPart()
	local bottom = Instance.new("Attachment")
	bottom.Name = name .. "Bottom"
	bottom.Parent = parent
	local top = Instance.new("Attachment")
	top.Name = name .. "Top"
	top.Parent = parent
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Width0 = width
	beam.Width1 = width
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0.25, 0.9)
	beam.Parent = parent
	return bottom, top, beam
end

local function impact(c: Types.CometState)
	local point = Vector3.new(c.x, WorldLayout.groundY(c.x, c.z), c.z)
	playSound("CometImpact", nil)
	for k = 1, COMET_RING_COUNT do
		task.delay((k - 1) * COMET_RING_STAGGER, function()
			VFXController.ring(point, COMET_RING_RADIUS, COMET_GOLD, COMET_RING_SECONDS)
		end)
	end
	VFXController.burst(point + Vector3.new(0, 2, 0), COMET_GOLD, 30)
	-- PointLight 0 → 8 → 1 en 1 s (portée 40)
	local holder = Fx.part("CometFlash", "Block", Vector3.one * 0.2, COMET_GOLD, Enum.Material.SmoothPlastic)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(point + Vector3.new(0, 4, 0))
	holder.Parent = vfxFolder()
	local light = Instance.new("PointLight")
	light.Range = COMET_LIGHT_RANGE
	light.Brightness = 0
	light.Color = COMET_GOLD
	light.Shadows = false
	light.Enabled = not low() or near(point, Render.LowGraphicsLightDistance)
	light.Parent = holder
	tween(light, COMET_LIGHT_SECONDS * 0.3, { Brightness = COMET_LIGHT_PEAK })
	task.delay(COMET_LIGHT_SECONDS * 0.3, function()
		tween(light, COMET_LIGHT_SECONDS * 0.7, { Brightness = COMET_LIGHT_REST })
	end)
	task.delay(COMET_LIGHT_SECONDS + 2, function()
		holder:Destroy()
	end)
	local d = (point - focus()).Magnitude
	if d < COMET_SHAKE_RANGE then
		Juice.cameraShake(COMET_SHAKE * (1 - d / COMET_SHAKE_RANGE), SHAKE_SECONDS)
	end
end

local function cometChanged(new: Types.EventStatePayload, old: Types.EventStatePayload?)
	local c = new.comet
	local prev = if old then old.comet else nil
	if c == nil then
		dropSky()
		dropGroundBeam()
		dropCarrier()
		return
	end
	local samePrev = prev ~= nil and prev.id == c.id
	local now = Clock.now()
	if c.phase == "warn" then
		if warnedComet ~= c.id then
			warnedComet = c.id
			AudioController.play("CometWarn")
		end
	else
		dropSky()
	end
	if c.phase == "ground" or c.phase == "carried" then
		if
			impactedComet ~= c.id
			and now - c.impactAt < IMPACT_FRESH
			and (not samePrev or prev.phase == "warn")
		then
			impactedComet = c.id
			impact(c)
		elseif impactedComet ~= c.id then
			impactedComet = c.id -- arrivée en cours de Comète : pas d'impact rejoué
		end
	end
	if c.phase ~= "ground" then
		dropGroundBeam()
	end
	if c.phase == "carried" then
		if samePrev and prev.phase == "carried" and prev.carrierId ~= c.carrierId then
			playSound("CometSwipe", nil)
		end
	else
		dropCarrier()
	end
	if c.phase == "banked" and (not samePrev or prev.phase ~= "banked") then
		local at = lastCometPos or Vector3.new(c.x, WorldLayout.groundY(c.x, c.z), c.z)
		VFXController.fireworks(at, Balance.Comet.BurstCount, COMET_GOLD)
		playSound("Reward", at)
	elseif c.phase == "burst" and (not samePrev or prev.phase ~= "burst") then
		local at = lastCometPos or Vector3.new(c.x, WorldLayout.groundY(c.x, c.z) + 3, c.z)
		local orb = takeBall(Color3.fromRGB(255, 230, 180), 3)
		orb.CFrame = CFrame.new(at)
		local t0 = now
		addAnim(function(t: number): boolean
			local a = (t - t0) / 0.5
			if a >= 1 then
				giveBall(orb)
				VFXController.burst(at, COMET_GOLD, 40)
				VFXController.ring(at, 10, COMET_GOLD, 0.4)
				return true
			end
			local on = math.floor(a * 6) % 2 == 0
			orb.Size = Vector3.one * (if on then 3.4 else 2.2)
			return false
		end)
		playSound("Reward", at)
	end
	lastCometId = c.id
end

-- Animations suivies chaque image : ciel, pilier au sol, porteur
local function stepComet(t: number)
	local ev = WorldStateController.events()
	local c = if ev then ev.comet else nil
	if c == nil then
		return
	end
	local pos = WorldStateController.cometPosition(t)
	if pos then
		lastCometPos = pos
	end
	if c.phase == "warn" and pos and t < c.impactAt then
		local alpha = (t - (c.impactAt - Balance.Comet.SkySeconds)) / Balance.Comet.SkySeconds
		if alpha >= 0 then
			if sky == nil or skyCometId ~= c.id then
				dropSky()
				local model = NebbyBuilder.buildCometSky()
				model.Parent = vfxFolder()
				sky = model
				skyCometId = c.id
			end
			local core = (sky :: Model).PrimaryPart
			if core then
				core.CFrame = CFrame.new(pos)
			end
		end
	elseif sky then
		dropSky()
	end
	if c.phase == "ground" and pos then
		local g = groundBeam
		if g == nil then
			local bottom, top, beam = makeBeam("CometPillar", COMET_GOLD, COMET_BEAM_WIDTH)
			g = { bottom = bottom, top = top, beam = beam }
			groundBeam = g
		end
		local gb = g :: { top: Attachment, bottom: Attachment, beam: Beam }
		gb.bottom.Position = pos
		gb.top.Position = pos + Vector3.new(0, COMET_BEAM_HEIGHT, 0)
	end
	if c.phase == "carried" and pos and c.carrierId then
		local fx = carrierFx
		if fx == nil then
			local balls = {}
			for k = 1, CARRIER_BALLS do
				balls[k] = takeBall(COMET_GOLD, 0.5)
			end
			local hl = Instance.new("Highlight")
			hl.Name = "CometCarrier"
			hl.FillColor = COMET_GOLD
			hl.OutlineColor = COMET_GOLD
			hl.FillTransparency = 0.7
			hl.DepthMode = Enum.HighlightDepthMode.Occluded
			hl.Parent = vfxFolder()
			local bottom, top, beam = makeBeam("CarrierBeam", COMET_GOLD, COMET_BEAM_WIDTH)
			fx = { balls = balls, highlight = hl, bottom = bottom, top = top, beam = beam }
			carrierFx = fx
		end
		local f = fx :: CarrierFx
		local player = Players:GetPlayerByUserId(c.carrierId)
		local character = if player then player.Character else nil
		if f.highlight.Adornee ~= character then
			f.highlight.Adornee = character
		end
		local ringCenter = pos + Vector3.new(0, CARRIER_LIFT, 0)
		for k, ball in f.balls do
			local angle = TAU * CARRIER_SPIN * t + (k - 1) * TAU / CARRIER_BALLS
			ball.CFrame =
				CFrame.new(ringCenter + Vector3.new(math.cos(angle), 0, math.sin(angle)) * CARRIER_RADIUS)
		end
		f.bottom.Position = pos
		f.top.Position = pos + Vector3.new(0, COMET_BEAM_HEIGHT, 0)
	end
end

-- Réactions : Gloomwisp éclaté -------------------------------------------------------------------------------

local function wispPopped(id: number)
	local model = CongaRenderer.wispModel(id)
	local at: Vector3? = nil
	if model and model.PrimaryPart then
		at = model.PrimaryPart.Position
	end
	if at == nil or not near(at, EFFECT_RANGE) then
		return
	end
	local p = at :: Vector3
	VFXController.burst(p, Color3.new(1, 1, 1), WISP_SPARKS)
	playSound("WispPop", p)
	if not reduced() then
		-- écrasement : Y 0,6 puis X 0,6 en 0,15 s, puis disparition en rétrécissant (Block + mesh
		-- Sphere : une pièce Ball ne se déforme pas)
		local puff = Fx.part("WispPuff", "Block", Vector3.one * 2.4, WISP_DARK, Enum.Material.SmoothPlastic)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = puff
		puff.CFrame = CFrame.new(p)
		puff.Parent = vfxFolder()
		tween(puff, 0.075, { Size = Vector3.new(2.4, 1.44, 2.4) })
		task.delay(0.075, function()
			tween(puff, 0.075, { Size = Vector3.new(1.44, 1.44, 2.4) })
			task.delay(0.075, function()
				tween(
					puff,
					0.15,
					{ Size = Vector3.one * 0.05 },
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
				task.delay(0.15, function()
					puff:Destroy()
				end)
			end)
		end)
	end
	-- une petite lueur s'envole
	local glow = takeBall(Color3.fromRGB(230, 220, 255), 0.6)
	glow.CFrame = CFrame.new(p)
	tween(glow, 0.8, { CFrame = CFrame.new(p + Vector3.new(0, 8, 0)), Size = Vector3.one * 0.05 })
	task.delay(0.8, function()
		giveBall(glow)
	end)
end

local function onEventChanged(new: Types.EventStatePayload, old: Types.EventStatePayload?)
	cometChanged(new, old)
	local before: { [number]: boolean } = {}
	if old then
		for _, w in old.wisps do
			before[w.id] = w.poppedAt ~= nil
		end
	end
	for _, w in new.wisps do
		if w.poppedAt ~= nil and before[w.id] == false then
			wispPopped(w.id)
		end
	end
end

-- Joueurs : Zen, étoile d'équipier, immunité, fin du bouclier débutant ---------------------------------------

-- Anneau Zen sous les pieds ; masqué tant que le personnage n'est pas chargé (mort, streaming) :
-- sinon il resterait figé à l'origine du monde (au pied de la Balise) ou à sa dernière position
local function placeZenRing(player: Player, ring: BasePart)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		ring.CFrame = CFrame.new(root.Position - Vector3.new(0, ROOT_TO_FEET - 0.1, 0)) * Fx.FLAT
		if ring.Parent == nil then
			ring.Parent = vfxFolder()
		end
	elseif ring.Parent ~= nil then
		ring.Parent = nil
	end
end

local function zenFor(player: Player, on: boolean)
	local ring = zenRings[player]
	if on and ring == nil then
		local part = takeRing(Cosmetics.Readability.Zen)
		part.Size = Vector3.new(0.12, 0.1, 0.1)
		zenRings[player] = part
		placeZenRing(player, part)
		if reduced() then
			part.Size = Vector3.new(0.12, 5, 5)
		else
			tween(part, ZEN_FADE, { Size = Vector3.new(0.12, 5, 5) })
		end
		if player == Players.LocalPlayer then
			AudioController.play("Click")
		end
	elseif not on and ring then
		zenRings[player] = nil
		tween(ring, ZEN_FADE, { Size = Vector3.new(0.12, 0.05, 0.05) })
		task.delay(ZEN_FADE, function()
			giveRing(ring)
		end)
	end
end

local function crewStarFor(player: Player, on: boolean)
	local gui = crewStars[player]
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if on and head and head:IsA("BasePart") then
		if gui == nil then
			local g = Instance.new("BillboardGui")
			g.Name = "CrewStar"
			g.Size = UDim2.fromScale(1.6, 1.6)
			g.StudsOffset = Vector3.new(0, 2.6, 0)
			g.AlwaysOnTop = false
			g.LightInfluence = 0
			g.MaxDistance = 150
			g.ResetOnSpawn = false
			local label = Instance.new("TextLabel")
			label.Name = "Star"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Text = "★"
			label.TextColor3 = Cosmetics.CrewStar
			label.Parent = g
			g.Parent = vfxFolder()
			crewStars[player] = g
			gui = g
		end
		local g = gui :: BillboardGui
		if g.Adornee ~= head then
			g.Adornee = head
		end
	elseif gui then
		crewStars[player] = nil
		gui:Destroy()
	end
end

local function immunityFor(player: Player, now: number)
	local untilAt = player:GetAttribute("ImmuneUntil")
	local on = type(untilAt) == "number" and untilAt > now
	local sparkles = immunity[player]
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if on and root then
		if sparkles == nil or sparkles.Parent ~= root then
			if sparkles then
				sparkles:Destroy()
			end
			local s = Instance.new("Sparkles")
			s.Name = "Immunity"
			s.SparkleColor = Cosmetics.Readability.Immune
			s.Parent = root
			immunity[player] = s
		end
	elseif sparkles then
		immunity[player] = nil
		sparkles:Destroy()
	end
end

local function rookieEnded()
	local slot = WorldStateController.localSlot()
	local positions = CongaRenderer.nodePositions(slot)
	for i, p in positions do
		task.delay((i - 1) * BUBBLE_POP_STEP, function()
			VFXController.burst(p, Cosmetics.Readability.Rookie, 6)
			if i == 1 then
				AudioController.play("Pop")
			end
		end)
	end
end

-- Connexions par joueur, coupées à son départ (sinon un attribut changé après PlayerRemoving
-- recréerait un anneau Zen ou une étoile jamais nettoyés)
local function trackPlayer(player: Player)
	if playerConns[player] then
		return
	end
	local conns: { RBXScriptConnection } = {}
	playerConns[player] = conns
	table.insert(
		conns,
		player:GetAttributeChangedSignal("Zen"):Connect(function()
			if playerConns[player] == conns then
				zenFor(player, player:GetAttribute("Zen") == true)
			end
		end)
	)
	if player == Players.LocalPlayer then
		rookieWas = player:GetAttribute("Rookie") == true
		table.insert(
			conns,
			player:GetAttributeChangedSignal("Rookie"):Connect(function()
				local rookie = player:GetAttribute("Rookie") == true
				-- seule la FIN du bouclier (vrai → faux) fait éclater les bulles ; nil → faux au
				-- chargement du profil d'un joueur confirmé ne joue rien
				if rookieWas and not rookie then
					rookieEnded()
				end
				rookieWas = rookie
			end)
		)
	end
	table.insert(
		conns,
		player.CharacterAdded:Connect(function()
			task.defer(function()
				if playerConns[player] == conns then
					crewStarFor(player, WorldStateController.isCrewmate(player.UserId))
				end
			end)
		end)
	)
	if player:GetAttribute("Zen") == true then
		zenFor(player, true)
	end
end

local function untrackPlayer(player: Player)
	local conns = playerConns[player]
	playerConns[player] = nil
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
	end
	zenFor(player, false)
	crewStarFor(player, false)
	local s = immunity[player]
	if s then
		immunity[player] = nil
		s:Destroy()
	end
end

local function refreshCrewStars()
	for _, player in Players:GetPlayers() do
		crewStarFor(player, WorldStateController.isCrewmate(player.UserId))
	end
end

-- Pings ----------------------------------------------------------------------------------------------------------

local function pingEntry(): PingEntry
	pingCursor = pingCursor % PING_POOL + 1
	local entry = pings[pingCursor]
	if entry then
		return entry
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Ping" .. pingCursor
	attachment.Parent = anchorPart()
	local gui = Instance.new("BillboardGui")
	gui.Name = "Ping"
	gui.Size = UDim2.fromScale(PING_SIZE, PING_SIZE)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = Balance.Ping.Range
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Adornee = attachment
	local frame = Instance.new("Frame")
	frame.Name = "Bubble"
	frame.Size = UDim2.fromScale(1, 0.5)
	frame.Position = UDim2.fromScale(0, 0.25)
	frame.BackgroundColor3 = Color3.fromRGB(40, 30, 70)
	frame.BackgroundTransparency = 0.15
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	gui.Parent = attachment
	local created: PingEntry = {
		attachment = attachment,
		gui = gui,
		label = label,
		scale = scale,
		userId = 0,
		untilAt = 0,
		token = 0,
		tweens = {},
	}
	pings[pingCursor] = created
	return created
end

local function onPing(userId: number, kind: number)
	local pos = userPosition(userId)
	if pos == nil or not near(pos, Balance.Ping.Range) then
		return
	end
	local e = pingEntry()
	e.token += 1
	local token = e.token
	-- bulle reprise : le fondu de l'affichage précédent ne doit pas effacer le nouveau ping
	for _, tw in e.tweens do
		tw:Cancel()
	end
	table.clear(e.tweens)
	e.userId = userId
	e.untilAt = Clock.now() + Balance.Ping.Duration
	e.attachment.Position = pos + Vector3.new(0, 4, 0)
	e.label.Text = Prefs.t("ping." .. kind)
	e.label.TextTransparency = 0
	e.gui.Enabled = true
	if reduced() then
		e.scale.Scale = 1
	else
		e.scale.Scale = 0
		table.insert(
			e.tweens,
			Juice.tween(e.scale, PING_POP, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		)
	end
	AudioController.play("Ping")
	task.delay(Balance.Ping.Duration, function()
		if e.token ~= token then
			return
		end
		table.insert(e.tweens, Juice.tween(e.label, PING_FADE, { TextTransparency = 1 }))
		task.delay(PING_FADE, function()
			if e.token == token then
				e.gui.Enabled = false
			end
		end)
	end)
end

local function stepPings(t: number)
	for _, e in pings do
		if e.gui.Enabled and t < e.untilAt then
			local pos = userPosition(e.userId)
			if pos then
				e.attachment.Position = pos + Vector3.new(0, 4, 0)
			end
		end
	end
end

-- Acclamation : arc de confettis vers le Nid du héros ----------------------------------------------------------

local function onCheer()
	local hero = lastHero
	local root = localRoot()
	if hero == nil or root == nil or Clock.now() - hero.at > CHEER_WINDOW then
		return
	end
	AudioController.play("Cheer")
	local from = root.Position + Vector3.new(0, 2, 0)
	local to = WorldLayout.nestCenter(hero.slot) + Vector3.new(0, 15, 0)
	VFXController.burst(from, CONFETTI_COLORS[1], 10)
	VFXController.burst(from, CONFETTI_COLORS[2], 10)
	local bottom, top, beam = makeBeam("CheerArc", CONFETTI_COLORS[3], 0.8)
	bottom.Position = from
	top.Position = from
	beam.Segments = 20
	beam.CurveSize0 = 30
	beam.CurveSize1 = -10
	beam.Color = ColorSequence.new(CONFETTI_COLORS[1], CONFETTI_COLORS[2])
	local t0 = Clock.now()
	addAnim(function(t: number): boolean
		local a = (t - t0) / CHEER_SECONDS
		if a >= 1 then
			beam:Destroy()
			bottom:Destroy()
			top:Destroy()
			VFXController.burst(to, CONFETTI_COLORS[4], 20)
			return true
		end
		top.Position = from:Lerp(to, Fx.quadOut(a))
		return false
	end)
end

-- Supernova : surveillance de l'attribut Supernovas des Nids ------------------------------------------------------

-- Le profil du propriétaire est-il chargé ? NestService pose OwnerUserId dès l'arrivée, puis
-- Supernovas (et l'attribut Supernovas du Player) seulement au chargement du profil. Une valeur
-- > 0 sur le Nid, ou l'attribut du Player déjà posé, prouvent que le chargement a eu lieu.
local function ownerLoaded(model: Instance): boolean
	local value = model:GetAttribute("Supernovas")
	if type(value) == "number" and value > 0 then
		return true
	end
	local owner = model:GetAttribute("OwnerUserId")
	local player = if type(owner) == "number" and owner ~= 0 then Players:GetPlayerByUserId(owner) else nil
	return player ~= nil and type(player:GetAttribute("Supernovas")) == "number"
end

local function trackNest(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local slot = model:GetAttribute("Slot")
	if type(slot) ~= "number" then
		return
	end
	local s = slot :: number
	local current = model:GetAttribute("Supernovas")
	supernovaSeen[s] = if type(current) == "number" then current else 0
	supernovaLoaded[s] = ownerLoaded(model)
	supernovaOwnerAt[s] = Clock.now()
	model:GetAttributeChangedSignal("Supernovas"):Connect(function()
		local value = model:GetAttribute("Supernovas")
		if type(value) ~= "number" then
			return
		end
		local before = supernovaSeen[s] or 0
		supernovaSeen[s] = value
		if not supernovaLoaded[s] then
			-- premier changement depuis l'arrivée du propriétaire : c'est le chargement de son profil
			-- (un joueur qui arrive avec R = 1 ne déclenche pas de fausse Supernova), sauf s'il vient
			-- longtemps après (profil à R = 0 : aucun changement au chargement)
			supernovaLoaded[s] = true
			if Clock.now() - (supernovaOwnerAt[s] or -math.huge) < SUPERNOVA_ARM_SECONDS then
				return
			end
		end
		local owner = model:GetAttribute("OwnerUserId")
		-- une hausse pendant que le même propriétaire occupe le Nid = une Supernova (pas une arrivée)
		if value == before + 1 and type(owner) == "number" and owner ~= 0 then
			VFXController.playSupernova(s, value)
		end
	end)
	model:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		local value = model:GetAttribute("Supernovas")
		supernovaSeen[s] = if type(value) == "number" then value else 0
		supernovaLoaded[s] = ownerLoaded(model)
		supernovaOwnerAt[s] = Clock.now()
	end)
end

-- Image ------------------------------------------------------------------------------------------------------

local function onFrame()
	local t = Clock.now()
	for i = #anims, 1, -1 do
		local ok, done = pcall(anims[i], t)
		if not ok and t - lastAnimWarn >= ANIM_WARN_INTERVAL then
			lastAnimWarn = t
			warn("[VFXController] animation :", done)
		end
		if not ok or done then
			table.remove(anims, i)
		end
	end
	stepComet(t)
	stepPings(t)
	for player, ring in zenRings do
		placeZenRing(player, ring)
	end
	if t - lastStatus >= 0.1 or t < lastStatus then
		lastStatus = t
		for _, player in Players:GetPlayers() do
			immunityFor(player, t)
			-- étoile d'équipier entretenue à 10 Hz : une tête répliquée en retard (streaming,
			-- réapparition) la retrouve sans attendre le prochain CrewState
			crewStarFor(player, WorldStateController.isCrewmate(player.UserId))
		end
	end
end

-- Cycle de vie ---------------------------------------------------------------------------------------------------

function VFXController.Init()
	vfxFolder()
	anchorPart()
end

function VFXController.Start()
	if started then
		return
	end
	started = true
	WorldStateController.Caught:Connect(onCaught)
	WorldStateController.Snipped:Connect(onSnipped)
	WorldStateController.Banked:Connect(onBanked)
	WorldStateController.EventChanged:Connect(onEventChanged)
	WorldStateController.PingShown:Connect(onPing)
	WorldStateController.CrewsChanged:Connect(refreshCrewStars)
	for _, model in CollectionService:GetTagged("Nest") do
		trackNest(model)
	end
	CollectionService:GetInstanceAddedSignal("Nest"):Connect(trackNest)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(untrackPlayer)
	-- InputController est plus tardif (§13.1) : on écoute son signal, chargé au démarrage
	local ok, input = pcall(function()
		return require(Client.Controllers.InputController) :: any
	end)
	if ok and type(input) == "table" and input.CheerRequested then
		input.CheerRequested:Connect(onCheer)
	end
	RunService.RenderStepped:Connect(onFrame)
end

-- Ajouts du paquet client-world (tests et budgets) --------------------------------------------------------------

-- Particules émises encore comptées dans la fenêtre du budget (≤ Render.MaxParticles)
function VFXController.particlesAlive(): number
	return Render.MaxParticles - particleBudget(Clock.now())
end

function VFXController.activeAnims(): number
	return #anims
end

function VFXController.lastCometId(): number?
	return lastCometId
end

return VFXController
