--!strict
-- VFXController (paquet client-world, docs/04 §13.3, §10.3, §14.4, GDD §9.1, §9.4, §9.5).
-- Effets des moments de jeu, sur Celebrate et sur les signaux du miroir : pression (gouttes, pièces,
-- « +N »), PERFECT et série, dalle construite, Pot, naissances par rareté et révélation de mutation
-- (Flop, Glitch, Arc-en-ciel en grand), fusion et combo, captures, ATCHOUM, Grand Splorch (7,5 s, vol du
-- petit squishy sur World/SplorchPath, éclatement, pluie de cadeaux), MEGA (atterrissage, pression,
-- éclatement, échec), jauge pleine, Nourrir Plop, achat, fanfare.
--   * Réserves : 120 gouttes, 20 textes « +N » (UI/WorldText, sorte « plus »), anneaux, pièces,
--     émetteurs ; particules dans particleQuota.vfx (déjà multiplié par le facteur de qualité).
--   * Mouvement réduit : pas de flash ; écrasements × 0,5 (les secousses et focales sont à
--     CameraController). Aucun clignotement au-dessus de 3 Hz.
--   * Vibrations (Util/Haptics, catalogue Config/Console) : perfect (0,3 + 0,03 × série) / 0,45, fusion
--     (0,4 + 0,05 × (k − 1)) / 0,65, comboBig, catch, tileBuy, boopDone, hatchLegend, megaLand atténuée,
--     megaPop, splorch (héros) ; pressTick SEULEMENT sur une pression PERFECT du MEGA (megaPress), 2 par
--     seconde au plus (VFXController est le seul à la borner). Une pression ordinaire ne vibre jamais.
--   * Grand Splorch d'un autre en version courte (data.short) : ni capsule, ni vibration ; pluie de
--     cadeaux courte : message celebrate.giftShort seulement.
--   * Clips automatiques (GDD §9.5) : Légendaire+, Arc-en-ciel / Glitch / Flop, COMBO ×5, mon Grand
--     Splorch ; seulement si le réglage clips, l'interrupteur du serveur features.clips et
--     PolicyService.IsContentSharingAllowed (en cache, pcall) le permettent ; CaptureService sous
--     pcall ; arrêt au plus tard 8 s après (StateTimeouts « clip ») ; carte « clip » de Cards SEULEMENT
--     si StartVideoCaptureAsync a rendu Success ; sinon plus aucun essai dans la session et attribut
--     local ClipsUnavailable = true (Settings et SplorchPreview cachent leur case). Jamais d'avertissement.
--   * Effets d'événement seulement si l'interrupteur du serveur est vrai (event().features).
-- Une seule connexion par image (RenderStepped) ; durées locales = sommes de dt.

local CaptureService = game:GetService("CaptureService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Console = require(Shared.Config.Console)
local Layout = require(Shared.Config.Layout)
local Species = require(Shared.Config.Species)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Pads = require(Shared.Config.Pads)
local StateTimeouts = require(Shared.Logic.StateTimeouts)
local WorldLayout = require(Shared.Logic.WorldLayout)
local MegaRules = require(Shared.Logic.MegaRules)
local SizeScale = require(Shared.Logic.SizeScale)
local ZoneRules = require(Shared.Logic.ZoneRules)
local SquishyBuilder = require(Shared.Render.SquishyBuilder)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Haptics = require(Client.Util.Haptics)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local QualityController = require(Client.Controllers.QualityController)
local RanchRenderer = require(Client.Controllers.RanchRenderer)
local Root = require(Client.UI.Root)
local Juice = require(Client.UI.Juice)
local WorldText = require(Client.UI.WorldText)
local Util = require(Client.World.Util)
local SplorchPath = require(Client.World.SplorchPath)

local VFXController = {}

-- Réserves et durées (GDD §9.1, §9.4)
local CFG = {
	Blobs = 120, -- gouttes de gelée réutilisées
	Texts = 20, -- « +N » en vol
	Coins = 30,
	FloatRise = 3, -- studs en 0,8 s
	FloatTime = 0.8,
	FloatDistance = 40, -- studs (WorldText « plus »)
	BlobLife = 0.7,
	CoinUp = 0.5,
	CoinFly = 0.4,
	ParticleLife = 0.6, -- s de vie comptée d'une gerbe
	StampTime = 1.1,
	StampText = 96, -- px TV (au plus : TextScaled le réduit pour tenir dans la zone sûre)
	StampHeight = 150, -- px TV
	StampWidth = 680, -- px TV : zone libre du HUD entre ses colonnes (voir stamp)
	StampOffsetY = -54, -- px TV : centre à 486 px TV en 1080p (milieu de la zone sûre, remonté)
	PolicyRetry = 30, -- s entre deux demandes à PolicyService restée sans réponse
	PressTickPerSecond = 2,
	MegaRange = 120,
	CapsuleFall = 1.2,
	CapsuleHop = 1.5,
	FireworkHeight = 60,
}

local CLIP_TIMEOUT = StateTimeouts.seconds("clip")
local SPECTACLE_TIMEOUT = StateTimeouts.seconds("spectacle")
local EPIC, LEGENDARY, MYTHIC = 4, 5, 6
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 205, 60)
local PINK = Color3.fromRGB(255, 170, 210)

-- finish : remise en réserve / destruction ; appelée à la fin normale ET si update lève (sinon une
-- erreur laisserait un compteur de réserve à jamais occupé, ou un spectacle bloqué)
type Effect = {
	kind: string,
	t: number,
	life: number,
	update: (Effect, number) -> boolean,
	finish: (() -> ())?,
}

local effects: { Effect } = {}
local blobPool: { Part } = {}
local blobLive = 0
local coinPool: { Part } = {}
local coinLive = 0
local ringPool: { Part } = {}
local emitterPool: { Part } = {}
local textLive = 0
local particleLive: { { n: number, untilT: number } } = {}
local animT = 0
local folder: Folder? = nil
local started = false
local connections: { any } = {}
local stampLabel: TextLabel? = nil
local stampUntil = 0
local pressTicks: { number } = {}
local megaSeen = 0
local megaGiant: { handle: any, landsAt: number, endsAt: number, base: Vector3, beatT: number }? = nil
local partySeen = 0
local eventSeen = false -- premier EventState vu : rien de rétroactif (MEGA déjà atterri, fête en cours)
local splorches: { [number]: any } = {}

-- Clips
local clipState = {
	unavailable = false,
	capturing = false,
	startedAt = 0,
	policy = nil :: boolean?,
	policyAt = -math.huge, -- animT de la dernière demande à PolicyService
	policyBusy = false,
	stopped = false,
}

-- =============================================================================================
-- Outils
-- =============================================================================================

local function budgets(): any
	return Util.safe("QualityController.budgets", nil, QualityController.budgets)
		or { particles = 1, particleQuota = { vfx = 120 } }
end

local function reducedMotion(): boolean
	return Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
end

local function features(): { [string]: any }
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) == "table" and type(ev.features) == "table" then
		return ev.features
	end
	return {}
end

local function play(name: string, variation: number?, pitch: number?)
	Util.safe("AudioController.play", nil, AudioController.play, name, variation, pitch)
end

local function haptic(name: string, scale: number?)
	local s = if scale then math.clamp(scale, 0, 1) else nil
	Util.safe("Haptics.play", false, Haptics.play, name, s)
end

local function clientFolder(): Folder
	local f = folder
	if f and f.Parent ~= nil then
		return f
	end
	local root = workspace:FindFirstChild("ClientWorld")
	if root == nil then
		local created = Instance.new("Folder")
		created.Name = "ClientWorld"
		created.Parent = workspace
		root = created
	end
	local sub = (root :: Instance):FindFirstChild("VFX")
	if sub == nil or not sub:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = "VFX"
		created.Parent = root
		sub = created
	end
	folder = sub :: Folder
	return sub :: Folder
end

local function plainPart(name: string, shape: Enum.PartType, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	return p
end

local function addEffect(kind: string, life: number, update: (Effect, number) -> boolean, finish: (() -> ())?)
	table.insert(effects, { kind = kind, t = 0, life = life, update = update, finish = finish })
end

local function myPos(): Vector3?
	local root = Util.localRoot()
	return if root then root.Position else nil
end

local function mySlot(): number
	return Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
end

local function particlesInUse(): number
	local n = 0
	for i = #particleLive, 1, -1 do
		local p = particleLive[i]
		if p.untilT <= animT then
			table.remove(particleLive, i)
		else
			n += p.n
		end
	end
	return n
end

local function roman(n: number): string
	local values = { 10, 9, 5, 4, 1 }
	local symbols = { "X", "IX", "V", "IV", "I" }
	local out = ""
	local v = math.clamp(math.floor(n), 1, 99)
	for i, value in values do
		while v >= value do
			out ..= symbols[i]
			v -= value
		end
	end
	return out
end

local function speciesColor(id: any): Color3
	local def = if type(id) == "number" then Species.ById[id] else nil
	return if def then def.colors.main else PINK
end

local function rarityColor(r: number): Color3
	local def = Rarities.List[r]
	return if def then def.color else WHITE
end

-- =============================================================================================
-- API des effets
-- =============================================================================================

-- Gerbe de particules (bornée par particleQuota.vfx)
function VFXController.burst(pos: Vector3, color: Color3, count: number)
	if not Util.vec(pos) or typeof(color) ~= "Color3" then
		return
	end
	local b = budgets()
	local quota = Util.num(b.particleQuota and b.particleQuota.vfx, 120, 0, 120)
	local want = math.floor(Util.num(count, 0, 0, 200) * Util.num(b.particles, 1, 0, 1))
	local n = math.min(want, quota - particlesInUse())
	if n <= 0 then
		return
	end
	local holder = table.remove(emitterPool)
	if holder == nil then
		local p = plainPart("VfxEmitter", Enum.PartType.Block, Enum.Material.SmoothPlastic)
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		local e = Instance.new("ParticleEmitter")
		e.Name = "Burst"
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.3, CFG.ParticleLife)
		e.Speed = NumberRange.new(6, 14)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = p
		holder = p
	end
	local part = holder :: Part
	part.CFrame = CFrame.new(pos)
	part.Parent = clientFolder()
	local emitter = part:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter.Color = ColorSequence.new(color)
		emitter:Emit(n)
	end
	table.insert(particleLive, { n = n, untilT = animT + CFG.ParticleLife })
	local function finish()
		part.Parent = nil
		table.insert(emitterPool, part)
	end
	addEffect("burst", CFG.ParticleLife, function(e: Effect, _dt: number): boolean
		if e.t >= e.life then
			finish()
			return false
		end
		return true
	end, finish)
end

-- Gouttes de gelée (réserve de 120 Balls réutilisées)
function VFXController.blobs(pos: Vector3, color: Color3, count: number)
	if not Util.vec(pos) or typeof(color) ~= "Color3" then
		return
	end
	local n = math.min(math.floor(Util.num(count, 0, 0, CFG.Blobs)), CFG.Blobs - blobLive)
	for _ = 1, n do
		local blob = table.remove(blobPool)
			or plainPart("Blob", Enum.PartType.Ball, Enum.Material.SmoothPlastic)
		local b = blob :: Part
		b.Color = color
		local size = 0.3 + math.random() * 0.4
		b.Size = Vector3.new(size, size, size)
		b.CFrame = CFrame.new(pos)
		b.Parent = clientFolder()
		blobLive += 1
		local a = math.random() * math.pi * 2
		local v = Vector3.new(
			math.cos(a) * (4 + math.random() * 6),
			8 + math.random() * 8,
			math.sin(a) * (4 + math.random() * 6)
		)
		local function finish()
			b.Parent = nil
			table.insert(blobPool, b)
			blobLive -= 1
		end
		addEffect("blob", CFG.BlobLife, function(e: Effect, _dt: number): boolean
			if e.t >= e.life then
				finish()
				return false
			end
			local t = e.t
			local p = pos + v * t + Vector3.new(0, -30 * t * t, 0)
			local k = 1 - t / e.life -- disparaît en rétrécissant
			b.Size = Vector3.new(size, size, size) * k
			b.CFrame = CFrame.new(p)
			return true
		end, finish)
	end
end

-- Texte qui monte (« +1,2K ») : UI/WorldText (taille fixe à l'écran), jamais un texte en studs
function VFXController.floatText(pos: Vector3, text: string, color: Color3?, scale: number?)
	if not Util.vec(pos) or type(text) ~= "string" or text == "" or textLive >= CFG.Texts then
		return
	end
	local anchor = plainPart("FloatAnchor", Enum.PartType.Block, Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = clientFolder()
	local ok, gui = pcall(
		WorldText.create,
		anchor,
		{ kind = "plus", maxDistance = CFG.FloatDistance, name = "FloatText" }
	)
	if not ok then
		anchor:Destroy()
		return
	end
	pcall(WorldText.setText, gui, text)
	if scale and Util.finite(scale) then
		pcall(WorldText.setTextSize, gui, math.floor(math.clamp(scale, 0.8, 2) * 40))
	end
	local label = gui:FindFirstChildWhichIsA("TextLabel", true)
	if label and color then
		label.TextColor3 = color
	end
	textLive += 1
	local function finish()
		pcall(WorldText.release, gui)
		anchor:Destroy()
		textLive -= 1
	end
	addEffect("text", CFG.FloatTime, function(e: Effect, _dt: number): boolean
		if e.t >= e.life then
			finish()
			return false
		end
		local a = e.t / e.life
		anchor.CFrame = CFrame.new(pos + Vector3.new(0, CFG.FloatRise * (1 - (1 - a) * (1 - a)), 0))
		return true
	end, finish)
end

-- Grand tampon à l'écran (« PERFECT ! », « COMBO x5 ! ») : un seul à la fois, le nouveau remplace
function VFXController.stamp(key: string, vars: { [string]: any }?, color: Color3?)
	local text = Util.t(key, vars)
	if text == "" then
		return
	end
	local label = stampLabel
	if label == nil or label.Parent == nil then
		local ok, safe = pcall(Root.safe, "VFXStamp", 40)
		if not ok or safe == nil then
			return
		end
		local created = Instance.new("TextLabel")
		created.Name = "Stamp"
		created.AnchorPoint = Vector2.new(0.5, 0.5)
		-- au milieu de l'écran, dans la zone que le HUD laisse libre : sous l'emplacement de message
		-- (Layout.Hud.message, bas à 310 px TV), entre la colonne de gauche (536) et la carte de droite
		-- (1 304), au-dessus de la puce d'action (822). Avant : toute la largeur de la zone sûre à 32 %
		-- de la hauteur, un long tampon passait sur la puce Menu (outil d'écrans, Screens_display.spec).
		-- TextScaled borné à 96 px (et 28 px TV au moins) : une longue cote
		-- (« SECRET … · 1 sur 1 000 000 000 ») tient sur deux lignes
		created.Position = UDim2.new(0.5, 0, 0.5, CFG.StampOffsetY)
		created.Size = UDim2.fromOffset(CFG.StampWidth, CFG.StampHeight)
		created.BackgroundTransparency = 1
		created.Font = Enum.Font.FredokaOne
		created.TextSize = CFG.StampText
		created.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = CFG.StampText
		limit.MinTextSize = Layout.Text.Min
		limit.Parent = created
		created.TextStrokeTransparency = 0
		created.TextStrokeColor3 = Color3.fromRGB(60, 30, 60)
		created.Visible = false
		created.Parent = safe
		label = created
		stampLabel = created
	end
	local l = label :: TextLabel
	l.Text = text
	l.TextColor3 = color or GOLD
	l.Visible = true
	stampUntil = animT + CFG.StampTime
	if not reducedMotion() then
		Util.safe("Juice.popIn", nil, Juice.popIn, l)
	end
end

-- Pièces qui volent vers le compteur (arc 0,5 s puis vol 0,4 s, Quad In)
function VFXController.flyCoins(from: Vector3, count: number)
	if not Util.vec(from) then
		return
	end
	local n = math.min(math.floor(Util.num(count, 0, 0, CFG.Coins)), CFG.Coins - coinLive)
	for i = 1, n do
		local coin = table.remove(coinPool)
		if coin == nil then
			local p = plainPart("Coin", Enum.PartType.Cylinder, Enum.Material.SmoothPlastic)
			p.Color = GOLD
			p.Size = Vector3.new(0.15, 0.7, 0.7)
			coin = p
		end
		local c = coin :: Part
		c.CFrame = CFrame.new(from)
		c.Parent = clientFolder()
		coinLive += 1
		local a = (i / math.max(1, n)) * math.pi * 2
		local up = from + Vector3.new(math.cos(a) * 2.5, 4, math.sin(a) * 2.5)
		local delayT = (i - 1) * 0.03
		local function finish()
			c.Parent = nil
			table.insert(coinPool, c)
			coinLive -= 1
		end
		addEffect("coin", delayT + CFG.CoinUp + CFG.CoinFly, function(e: Effect, _dt: number): boolean
			if e.t >= e.life then
				finish()
				return false
			end
			local t = math.max(0, e.t - delayT)
			local p
			if t < CFG.CoinUp then
				local k = t / CFG.CoinUp
				p = from:Lerp(up, k) + Vector3.new(0, math.sin(math.pi * k) * 2, 0)
			else
				local k = (t - CFG.CoinUp) / CFG.CoinFly
				local cam = workspace.CurrentCamera
				local target = if cam
					then cam.CFrame.Position + cam.CFrame.UpVector * 4 - cam.CFrame.RightVector * 6
					else up
				p = up:Lerp(target, k * k)
			end
			c.CFrame = CFrame.new(p) * CFrame.Angles(0, e.t * 8, math.pi / 2)
			return true
		end, finish)
	end
end

-- Anneau Neon qui s'élargit puis disparaît en s'amincissant
function VFXController.ring(pos: Vector3, color: Color3, diameter: number, duration: number)
	if not Util.vec(pos) or typeof(color) ~= "Color3" then
		return
	end
	local dia = Util.num(diameter, 4, 0.1, 200)
	local life = Util.num(duration, 0.25, 0.05, 3)
	local ring = table.remove(ringPool) or plainPart("Ring", Enum.PartType.Cylinder, Enum.Material.Neon)
	local r = ring :: Part
	r.Color = color
	r.Parent = clientFolder()
	local function finish()
		r.Parent = nil
		table.insert(ringPool, r)
	end
	addEffect("ring", life, function(e: Effect, _dt: number): boolean
		if e.t >= e.life then
			finish()
			return false
		end
		local a = e.t / e.life
		local d = math.max(0.05, dia * (1 - (1 - a) * (1 - a)))
		r.Size = Vector3.new(0.3 * (1 - a) + 0.02, d, d)
		r.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
		return true
	end, finish)
end

-- Colonne Neon (naissance Rare et plus) : Ø 1,5 → 0, hauteur 25, 0,8 s
local function pillar(pos: Vector3, color: Color3)
	local p = plainPart("Pillar", Enum.PartType.Cylinder, Enum.Material.Neon)
	p.Color = color
	p.Parent = clientFolder()
	local function finish()
		p:Destroy()
	end
	addEffect("pillar", 0.8, function(e: Effect, _dt: number): boolean
		if e.t >= e.life then
			finish()
			return false
		end
		local k = 1 - e.t / e.life
		p.Size = Vector3.new(25, 1.5 * k + 0.05, 1.5 * k + 0.05)
		p.CFrame = CFrame.new(pos + Vector3.new(0, 12.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		return true
	end, finish)
end

-- Capsule de bébé qui tombe près du joueur, éclate, puis le bébé saute vers son ranch
function VFXController.capsule(pos: Vector3, species: number)
	if not Util.vec(pos) then
		return
	end
	local capsule = plainPart("Capsule", Enum.PartType.Ball, Enum.Material.SmoothPlastic)
	capsule.Size = Vector3.new(2, 2, 2)
	capsule.Color = speciesColor(species)
	capsule.Parent = clientFolder()
	local top = pos + Vector3.new(0, 30, 0)
	local burstDone = false
	local baby: any = nil
	local home = WorldLayout.anchor(math.max(1, mySlot()), "gate")
	local function finish()
		if capsule.Parent then
			capsule:Destroy()
		end
		if baby then
			pcall(SquishyBuilder.release, baby)
		end
	end
	addEffect("capsule", CFG.CapsuleFall + CFG.CapsuleHop, function(e: Effect, _dt: number): boolean
		if e.t >= e.life then
			finish()
			return false
		end
		if e.t < CFG.CapsuleFall then
			local k = e.t / CFG.CapsuleFall
			capsule.CFrame = CFrame.new(top:Lerp(pos, k * k))
			return true
		end
		if not burstDone then
			burstDone = true
			capsule:Destroy()
			VFXController.burst(pos, WHITE, 14)
			play("BabyGet")
			if Species.ById[species] then
				local ok, h = pcall(SquishyBuilder.build, {
					species = species,
					mutation = 0,
					stars = 0,
					displayScale = 0.6,
					lod = 2,
				}, clientFolder())
				baby = if ok then h else nil
			end
		end
		if baby then
			local k = (e.t - CFG.CapsuleFall) / CFG.CapsuleHop
			local hop = (k * 3) % 1
			local p = pos:Lerp(Vector3.new(home.X, pos.Y, home.Z), k * 0.25)
				+ Vector3.new(0, math.sin(math.pi * hop) * 3 + 0.6, 0)
			local okp, parts, cframes = pcall(SquishyBuilder.pose, baby, CFrame.new(p))
			if okp and type(parts) == "table" then
				for i, part in parts do
					part.CFrame = cframes[i]
				end
			end
		end
		return true
	end, finish)
end

-- Compteurs (particules actives, instances en réserve) pour les specs de budget
function VFXController.stats(): { [string]: number }
	return {
		particles = particlesInUse(),
		blobs = blobLive,
		texts = textLive,
		coins = coinLive,
		effects = #effects,
		pooledBlobs = #blobPool,
		capturing = if clipState.capturing then 1 else 0,
	}
end

-- =============================================================================================
-- Clips automatiques (GDD §9.5)
-- =============================================================================================

local function markUnavailable()
	clipState.unavailable = true
	local player = Players.LocalPlayer
	if player then
		pcall(function()
			player:SetAttribute("ClipsUnavailable", true)
		end)
	end
end

local function pushClipCard(capture: any)
	local ok, Cards = pcall(function()
		return require(Client.UI.Cards) :: any
	end)
	if not ok or type(Cards) ~= "table" then
		return
	end
	Util.safe("Cards.push", "", Cards.push, {
		id = "",
		kind = "clip",
		blocking = false,
		data = {
			save = function()
				pcall(function()
					CaptureService:PromptSaveCapturesToGallery({ capture }, function() end)
				end)
			end,
			share = function()
				pcall(function()
					CaptureService:PromptShareCapture(capture, "", function() end, function() end)
				end)
			end,
		},
	})
end

local function stopClip()
	if not clipState.capturing or clipState.stopped then
		return
	end
	clipState.stopped = true
	pcall(function()
		CaptureService:StopVideoCapture()
	end)
end

local function checkPolicy()
	local player = Players.LocalPlayer
	if player == nil or clipState.policyBusy then
		return
	end
	clipState.policyBusy = true
	clipState.policyAt = animT
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	clipState.policyBusy = false
	if ok and type(info) == "table" then
		clipState.policy = info.IsContentSharingAllowed == true
		if clipState.policy == false then
			markUnavailable()
		end
	end
end

local function clipsAllowed(): boolean
	if clipState.unavailable or clipState.capturing then
		return false
	end
	if Util.safe("Prefs.get", nil, Prefs.get, "clips") == false then
		return false
	end
	if features().clips ~= true then
		return false
	end
	-- seulement sur une réponse POSITIVE de PolicyService (GDD §9.5) : sans réponse (appel qui a
	-- levé), aucune capture, et une nouvelle demande au plus toutes les 30 s
	if clipState.policy == nil then
		if not clipState.policyBusy and animT - clipState.policyAt >= CFG.PolicyRetry then
			task.spawn(checkPolicy)
		end
		return false
	end
	return clipState.policy == true
end

-- Démarre une capture vidéo automatique (sans effet si les clips ne sont pas permis)
function VFXController.clip(): boolean
	if not clipsAllowed() then
		return false
	end
	clipState.capturing = true
	clipState.stopped = false
	clipState.startedAt = animT
	task.spawn(function()
		local success = false
		local ok, result = pcall(function()
			return CaptureService:StartVideoCaptureAsync(function(capture: any)
				clipState.capturing = false
				if success and capture ~= nil then
					pushClipCard(capture)
				end
			end, {})
		end)
		success = ok and result == Enum.VideoCaptureStartedResult.Success
		if not success then
			clipState.capturing = false
			markUnavailable()
		end
	end)
	return true
end

-- =============================================================================================
-- MEGA : pression PERFECT du joueur local (pressTick, 2 par seconde au plus)
-- =============================================================================================

-- Appelé par InputController juste après l'envoi de MegaPress(tClient) : vibration pressTick
-- seulement sur une pression PERFECT (MegaRules.isPerfect), bornée ici à 2 par seconde
function VFXController.megaPress(tClient: number): boolean
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) ~= "table" or type(ev.mega) ~= "table" or features().megaSquish ~= true then
		return false
	end
	if ev.mega.phase ~= "press" or not Util.finite(tClient) then
		return false
	end
	local perfect =
		Util.safe("MegaRules.isPerfect", false, MegaRules.isPerfect, Util.num(ev.mega.landsAt, 0), tClient)
	local pad = WorldLayout.plaza("megaPad")
	VFXController.floatText(
		pad + Vector3.new(0, 14, 0),
		if perfect then "+3" else "+1",
		if perfect then GOLD else WHITE
	)
	if not perfect then
		return false
	end
	for i = #pressTicks, 1, -1 do
		if animT - pressTicks[i] >= 1 then
			table.remove(pressTicks, i)
		end
	end
	if #pressTicks >= CFG.PressTickPerSecond then
		return false
	end
	table.insert(pressTicks, animT)
	haptic("pressTick")
	return true
end

-- =============================================================================================
-- Célébrations
-- =============================================================================================

local function squishyPos(uid: any): Vector3?
	local slot = mySlot()
	if slot > 0 and type(uid) == "string" then
		local p = Util.safe("RanchRenderer.positionOf", nil, RanchRenderer.positionOf, slot, uid)
		if p then
			return p
		end
	end
	return myPos()
end

local function onPress(d: any)
	local pos = if d.petsit == true then myPos() else squishyPos(d.uid)
	if pos == nil then
		return
	end
	local slot = mySlot()
	local list = if slot > 0 then WorldStateController.squishies(slot) else {}
	local rec = if type(d.uid) == "string" then list[d.uid] else nil
	local color = speciesColor(if rec then rec.s else nil)
	VFXController.blobs(pos, color, 8)
	local coins = Util.num(d.coins, 0, 0)
	if coins > 0 then
		VFXController.flyCoins(pos, 6 + math.random(0, 4))
		VFXController.floatText(
			pos + Vector3.new(0, 2, 0),
			Util.t("celebrate.plus", { n = Util.number(coins) }),
			GOLD
		)
	end
	local streak = math.floor(Util.num(d.streak, 0, 0, Balance.Press.StreakMax))
	if d.perfect == true then
		VFXController.ring(pos, WHITE, 1.6 * 2 * 2, 0.25)
		VFXController.burst(pos, WHITE, 14)
		play("Perfect", nil, 1.0595 ^ streak)
		local def = Console.Haptics.Events.perfect
		haptic("perfect", (0.3 + 0.03 * streak) / def.strength)
		if streak >= Balance.Press.StreakMax then
			VFXController.burst(pos, GOLD, 20)
			VFXController.stamp("celebrate.streakMax", { n = streak })
			play("StreakMax")
		else
			VFXController.stamp("celebrate.perfect")
		end
	else
		play("Press", 0.08)
	end
end

local function onHatch(d: any)
	local slot = mySlot()
	local pos = if slot > 0 then WorldLayout.anchor(slot, "vat") + Vector3.new(0, 5, 0) else myPos()
	if pos == nil then
		return
	end
	local rarity = math.floor(Util.num(d.rarity, 1, 1, 7))
	local mkey = Util.mutationKey(d.mutation)
	local special = mkey == "flop" or mkey == "glitch" or mkey == "rainbow"
	local color = rarityColor(rarity)
	local name = Util.speciesName(d.species)
	local odds = Util.number(Util.num(d.oneIn, 0, 0))
	VFXController.burst(pos, color, if rarity >= 3 then 20 else 10)
	if rarity >= 3 then
		pillar(pos, color)
	end
	if rarity >= LEGENDARY or special then
		VFXController.burst(pos, if mkey == "flop" then GOLD else color, if rarity >= MYTHIC then 60 else 40)
		if not reducedMotion() then
			Util.safe("Juice.flash", nil, Juice.flash, if mkey == "flop" then GOLD else WHITE, 0.3, 0.12)
		end
		if rarity >= MYTHIC then
			VFXController.ring(pos, Color3.fromHSV(math.random(), 0.6, 1), 30, 1)
		end
		haptic("hatchLegend")
		play(if mkey == "flop" then "Blorp" else "HatchLegend", nil, if rarity == 7 then 0.9 else 1)
		VFXController.clip()
	elseif rarity >= EPIC then
		haptic("catch")
		play("HatchRare")
	elseif rarity >= 3 then
		play("HatchRare")
	else
		play("Hatch")
	end
	local scale = 0.8 + (rarity - 1) * (0.8 / 6)
	if mkey == "flop" then
		VFXController.stamp("celebrate.flop", { odds = odds }, GOLD)
	elseif mkey == "glitch" then
		VFXController.stamp("celebrate.glitch", { odds = odds })
	elseif mkey == "rainbow" then
		VFXController.stamp("celebrate.rainbow", { odds = odds })
	elseif rarity >= MYTHIC then
		VFXController.stamp("celebrate.secretTag", { species = name, odds = odds }, color)
	end
	VFXController.floatText(
		pos + Vector3.new(0, 2, 0),
		Util.t("celebrate.hatch", { species = name }),
		color,
		scale
	)
	if d.isNew == true then
		VFXController.floatText(pos + Vector3.new(0, 4, 0), Util.t("celebrate.newEntry"), GOLD)
	end
	local mut = if type(d.mutation) == "number" then Mutations.ById[d.mutation] else nil
	if mut and d.mutation ~= 0 and not special then
		VFXController.burst(pos, mut.color, 10)
		play("MutationReveal")
	end
end

local function onFusion(d: any)
	local pos = squishyPos(d.uid)
	if pos == nil then
		return
	end
	local k = math.floor(Util.num(d.step, 1, 1, 6))
	local slot = mySlot()
	local list = if slot > 0 then WorldStateController.squishies(slot) else {}
	local rec = if type(d.uid) == "string" then list[d.uid] else nil
	local color = speciesColor(if rec then rec.s else nil)
	VFXController.burst(pos, color, 24 + (k - 1) * 4)
	VFXController.ring(pos, WHITE, 5, 0.2)
	local stars = math.floor(Util.num(d.stars, 0, 0, 5))
	if stars > 0 then
		VFXController.floatText(pos + Vector3.new(0, 2, 0), Util.t("celebrate.star", { n = stars }), GOLD)
	end
	local def = Console.Haptics.Events.fusion
	if k >= 2 then
		VFXController.stamp("celebrate.combo", { n = k }, GOLD)
		play("ComboStep", nil, 1 + 0.08 * k)
	else
		play("Fuse")
	end
	if k >= 5 then
		VFXController.burst(pos, GOLD, 50)
		play("ComboBig")
		VFXController.clip()
	end
	if k >= 4 then
		haptic("comboBig")
	else
		haptic("fusion", (0.4 + 0.05 * (k - 1)) / def.strength)
	end
end

local function onCatch(d: any)
	local pos = myPos()
	if pos == nil then
		return
	end
	local name = Util.speciesName(d.species)
	VFXController.burst(pos, if d.kind == "golden" then GOLD else WHITE, if d.hero == true then 30 else 14)
	if d.hero == true then
		VFXController.stamp("celebrate.hero", nil, GOLD)
		play("HeroCatch")
		haptic("catch", 0.5 / Console.Haptics.Events.catch.strength)
	else
		play(if d.kind == "golden" then "CatchGolden" else "Catch")
		haptic("catch")
	end
	local key = if d.kind == "escape" and d.hero ~= true then "celebrate.babyGet" else "celebrate.catch"
	VFXController.floatText(pos + Vector3.new(0, 3, 0), Util.t(key, { species = name }))
	local coins = Util.num(d.coins, 0, 0)
	if coins > 0 then
		VFXController.flyCoins(pos, 6)
	end
end

local function onBoopDone(d: any)
	local me = Players.LocalPlayer
	if me and d.ownerId == me.UserId then
		return -- le propriétaire ne vibre jamais quand son squishy s'enfuit
	end
	local pos = myPos()
	if pos == nil then
		return
	end
	VFXController.burst(pos + Vector3.new(0, 2, 0), PINK, 20)
	VFXController.stamp("celebrate.achoo", nil, PINK)
	play("Sneeze")
	haptic("boopDone")
end

-- Grand Splorch : vol du petit squishy (World/SplorchPath), éclatement, cadeaux, titres
local function onSplorch(d: any)
	if not (Util.finite(d.startedAt) and Util.finite(d.burstAt) and Util.finite(d.endsAt)) then
		return
	end
	if d.endsAt <= d.startedAt or d.endsAt - d.startedAt > SPECTACLE_TIMEOUT then
		return
	end
	local me = Players.LocalPlayer
	local hero = me ~= nil and d.userId == me.UserId and d.short ~= true
	local slot = 0
	for s = 1, WorldLayout.Const.Ranches do
		local r = WorldStateController.ranch(s)
		if r and r.userId == d.userId and r.userId ~= 0 then
			slot = s
			break
		end
	end
	if slot == 0 then
		return
	end
	local id = math.floor(Util.num(d.userId, 0))
	if splorches[id] then
		return
	end
	local flyer = if type(d.flyer) == "table" then d.flyer else {}
	local ok, handle = pcall(SquishyBuilder.build, {
		species = if Species.ById[flyer.s] then flyer.s else Species.PLOP,
		mutation = Util.int(flyer.m, 0, 255) or 0,
		stars = Util.int(flyer.st, 0, 5) or 0,
		displayScale = SizeScale.display(Util.num(flyer.z, 1, 0), "pen"),
		lod = 1,
	}, clientFolder())
	local state = {
		handle = if ok then handle else nil,
		marks = {} :: { [string]: boolean },
		frames = 0,
	}
	splorches[id] = state
	local level = math.floor(Util.num(d.level, 1, 1, 99))
	local function once(key: string, at: number): boolean
		if state.marks[key] or Clock.now() < at then
			return false
		end
		state.marks[key] = true
		return true
	end
	if
		hero
		and Util.safe("Players.attr", true, function()
			return (me :: Player):GetAttribute("SplorchFilm") ~= false
		end)
	then
		VFXController.clip()
	end
	local function finishSplorch()
		if state.handle then
			pcall(SquishyBuilder.release, state.handle)
			state.handle = nil
		end
		splorches[id] = nil
	end
	addEffect("splorch", SPECTACLE_TIMEOUT, function(_e: Effect, dt: number): boolean
		state.frames += dt
		local now = Clock.now()
		-- le héros est parti (son ranch est libéré ou repris) : le serveur annule le spectacle, il
		-- s'arrête aussi ici (plus d'éclatement, de titre ni de cadeaux ; variante ClientReplay)
		local heroRanch = WorldStateController.ranch(slot)
		local heroLeft = heroRanch == nil or heroRanch.userId ~= id
		if now >= d.endsAt or state.frames > SPECTACLE_TIMEOUT or heroLeft then
			finishSplorch()
			return false
		end
		local target = nil
		local owner = Players:GetPlayerByUserId(id)
		local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			target = root.Position - Vector3.new(0, 2, 0)
		end
		local s = SplorchPath.sample(slot, d.startedAt, d.burstAt, d.endsAt, now, target)
		if state.handle then
			local sc = if s.visible then s.scale else 0.01
			pcall(SquishyBuilder.setSquash, state.handle, sc, sc, sc)
			local okp, parts, cframes = pcall(SquishyBuilder.pose, state.handle, CFrame.new(s.pos))
			if okp and type(parts) == "table" then
				for i, part in parts do
					part.CFrame = cframes[i]
				end
			end
		end
		local apex = select(2, SplorchPath.endpoints(slot))
		if once("charge", d.startedAt + 2) then
			play("SplorchCharge")
		end
		if once("burst", d.burstAt) then
			VFXController.blobs(apex, PINK, 60)
			VFXController.ring(apex - Vector3.new(0, 36, 0), WHITE, 80, 0.8)
			play("SplorchPop")
			if hero then
				haptic("splorch")
				if not reducedMotion() then
					Util.safe("Juice.flash", nil, Juice.flash, WHITE, 0.3, 0.1)
				end
			end
		end
		if once("gifts", d.burstAt + 0.8) then
			play("GiftRain")
		end
		if once("title", d.burstAt + 2) and not d.short then
			VFXController.stamp("celebrate.splorchTitle", { roman = roman(level) }, GOLD)
			if hero then
				play("Reward")
			end
		end
		if hero and once("back", d.endsAt - 0.2) and me then
			local p = myPos()
			if p then
				VFXController.floatText(
					p + Vector3.new(0, 4, 0),
					Util.t("celebrate.splorchBack", { name = Util.speciesName(flyer.s) }),
					GOLD
				)
			end
		end
		return true
	end, finishSplorch)
end

local function onGiftRain(d: any)
	local pos = myPos()
	if pos == nil then
		return
	end
	local name = Util.displayName(d.heroName, d.heroId)
	if d.short == true then
		-- version courte : cadeau déjà compté ; ni capsule, ni vibration ; un message seulement
		VFXController.floatText(
			pos + Vector3.new(0, 4, 0),
			Util.t("celebrate.giftShort", { name = name }),
			GOLD
		)
		return
	end
	VFXController.flyCoins(pos + Vector3.new(0, 10, 0), 6 + math.random(0, 4))
	if type(d.uid) == "string" and d.uid ~= "" then
		local a = math.random() * math.pi * 2
		VFXController.capsule(pos + Vector3.new(math.cos(a) * 4, 0, math.sin(a) * 4), Util.num(d.species, 0))
	end
	haptic("catch")
	VFXController.floatText(pos + Vector3.new(0, 4, 0), Util.t("celebrate.giftRain", { name = name }), GOLD)
end

local function onMegaResult(d: any)
	if features().megaSquish ~= true then
		return
	end
	local pad = WorldLayout.plaza("megaPad")
	local giant = megaGiant
	if d.success == true then
		VFXController.blobs(pad + Vector3.new(0, 10, 0), PINK, 80)
		VFXController.burst(pad + Vector3.new(0, 10, 0), GOLD, 60)
		VFXController.stamp("celebrate.megaSplorch", nil, GOLD)
		play("MegaPop")
		play("GiftRain")
		haptic("megaPop")
		if not reducedMotion() then
			Util.safe("Juice.flash", nil, Juice.flash, WHITE, 0.3, 0.12)
		end
		local pos = myPos()
		local babies = math.floor(Util.num(d.babies, 0, 0, 3))
		if pos then
			for i = 1, babies do
				local a = i * 2.1
				VFXController.capsule(pos + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5), 0)
			end
		end
		if giant then
			pcall(SquishyBuilder.release, giant.handle)
			megaGiant = nil
		end
	else
		VFXController.stamp("celebrate.megaFail")
		play("MegaSigh")
		if giant then
			giant.endsAt = math.min(giant.endsAt, Clock.now() + 2)
		end
	end
end

local function onCelebrate(payload: any)
	if type(payload) ~= "table" or type(payload.data) ~= "table" then
		return
	end
	local kind, d = payload.kind, payload.data
	if kind == "press" then
		onPress(d)
	elseif kind == "tile" then
		local slot = mySlot()
		local def = if type(d.tile) == "string" then Pads.Defs[d.tile] else nil
		local pos = if slot > 0 and def then WorldLayout.padSocket(slot, def.socket) else myPos()
		if pos then
			VFXController.burst(pos + Vector3.new(0, 1, 0), Color3.fromHSV(math.random(), 0.5, 1), 12)
			local label = Util.t("celebrate.tileBuilt", {
				name = Util.t("pad." .. tostring(d.tile)),
				n = math.floor(Util.num(d.level, 1, 0, 1000)),
			})
			VFXController.floatText(pos + Vector3.new(0, 3, 0), label)
		end
		play("TileBuild")
		haptic("tileBuy")
	elseif kind == "pot" then
		local slot = mySlot()
		local pos = if slot > 0 then WorldLayout.anchor(slot, "pot") + Vector3.new(0, 3, 0) else myPos()
		if pos then
			VFXController.flyCoins(pos, 12 + math.random(0, 8))
			VFXController.floatText(
				pos + Vector3.new(0, 2, 0),
				Util.t("celebrate.plus", { n = Util.number(Util.num(d.coins, 0, 0)) }),
				GOLD
			)
		end
		play("PotCollect")
	elseif kind == "hatch" then
		onHatch(d)
	elseif kind == "fusion" then
		onFusion(d)
	elseif kind == "catch" then
		onCatch(d)
	elseif kind == "boopDone" then
		onBoopDone(d)
	elseif kind == "splorch" then
		onSplorch(d)
	elseif kind == "giftRain" then
		onGiftRain(d)
	elseif kind == "megaResult" then
		onMegaResult(d)
	elseif kind == "lunarDrop" or kind == "luckyDrop" then
		local pos = myPos()
		if pos then
			VFXController.capsule(pos + Vector3.new(3, 0, 3), Util.num(d.species, 0))
			VFXController.floatText(pos + Vector3.new(0, 4, 0), Util.t("celebrate." .. kind), GOLD)
		end
	elseif kind == "plopDay" then
		local slot = mySlot()
		if slot > 0 then
			VFXController.burst(WorldLayout.anchor(slot, "bowl") + Vector3.new(0, 2, 0), PINK, 6)
		end
		VFXController.stamp("celebrate.plopDay", { n = math.floor(Util.num(d.day, 0, 0)) }, PINK)
		play("FeedPlop")
	elseif kind == "purchase" then
		local pos = myPos()
		if pos then
			VFXController.flyCoins(pos + Vector3.new(0, 12, 0), 30)
		end
		play("Reward")
	elseif kind == "fanfare" then
		local center = WorldLayout.plaza("center")
		for i = 1, 3 do
			local a = i * 2.1
			VFXController.burst(
				center + Vector3.new(math.cos(a) * 20, CFG.FireworkHeight, math.sin(a) * 20),
				Color3.fromHSV(i / 3, 0.6, 1),
				30
			)
		end
		play("Fanfare")
	end
end

-- =============================================================================================
-- Événements du miroir (seulement si l'interrupteur du serveur est vrai)
-- =============================================================================================

local function stepEvents()
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) ~= "table" or type(ev.features) ~= "table" then
		return
	end
	local now = Clock.now()
	local mega = ev.mega
	if type(mega) == "table" and ev.features.megaSquish == true then
		local index = Util.num(mega.index, 0)
		local landsAt = Util.num(mega.landsAt, 0)
		local endsAt = Util.num(mega.endsAt, 0)
		if index > megaSeen and landsAt > 0 and now >= landsAt and now < endsAt and now - landsAt < 1 then
			megaSeen = index
			local pad = WorldLayout.plaza("megaPad")
			for i = 0, 2 do
				VFXController.ring(pad + Vector3.new(0, 0.5 + i * 0.2, 0), WHITE, 60, 0.6 + i * 0.15)
			end
			VFXController.burst(pad + Vector3.new(0, 1, 0), Color3.fromRGB(230, 220, 210), 40)
			play("MegaLand")
			local p = myPos()
			if p then
				local dist = ZoneRules.distXZ(p, pad)
				if dist < CFG.MegaRange then
					haptic("megaLand", 1 - dist / CFG.MegaRange)
				end
			end
			if megaGiant == nil then
				local ok, h = pcall(SquishyBuilder.build, {
					species = if Species.ById[mega.species] then mega.species else Species.PLOP,
					mutation = 0,
					stars = 0,
					displayScale = 10,
					lod = 1,
				}, clientFolder())
				if ok then
					megaGiant = { handle = h, landsAt = landsAt, endsAt = endsAt + 1, base = pad, beatT = -1 }
				end
			end
		end
	end
	local giant = megaGiant
	if giant then
		if now >= giant.endsAt or ev.features.megaSquish ~= true then
			pcall(SquishyBuilder.release, giant.handle)
			megaGiant = nil
		else
			local fall = math.clamp((now - giant.landsAt + 0.6) / 0.6, 0, 1)
			local dia = Balance.SizeScale.BaseDiameter * 10
			local y = giant.base.Y + dia * 0.5 + (1 - fall * fall) * 120
			local dent = if animT - giant.beatT < 0.08 then 0.96 else 1
			pcall(SquishyBuilder.setSquash, giant.handle, 2 - dent, dent, 2 - dent)
			local okp, parts, cframes =
				pcall(SquishyBuilder.pose, giant.handle, CFrame.new(giant.base.X, y, giant.base.Z))
			if okp and type(parts) == "table" then
				for i, part in parts do
					part.CFrame = cframes[i]
				end
			end
		end
	end
	local gauge = ev.gauge
	if type(gauge) == "table" then
		local partyUntil = Util.num(gauge.partyUntil, 0)
		if not eventSeen then
			eventSeen = true
			partySeen = partyUntil
		elseif partyUntil > partySeen then
			partySeen = partyUntil
			if ev.features.gauge == true and partyUntil > now then
				VFXController.burst(WorldLayout.plaza("gauge") + Vector3.new(0, 8, 0), GOLD, 40)
				play("GaugeFull")
			end
		end
	end
end

-- =============================================================================================
-- Image
-- =============================================================================================

-- Une image (exposé aux specs ; appelé par RenderStepped)
function VFXController._step(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	animT += d
	for i = #effects, 1, -1 do
		local e = effects[i]
		e.t += d
		local ok, keep = pcall(e.update, e, d)
		if not ok then
			Util.raise("VFXController.effect:" .. e.kind, tostring(keep))
			table.remove(effects, i)
			-- l'effet qui a levé rend quand même sa réserve (et libère son spectacle)
			if e.finish then
				pcall(e.finish)
			end
		elseif not keep then
			table.remove(effects, i)
		end
	end
	if stampLabel and stampLabel.Visible and animT >= stampUntil then
		stampLabel.Visible = false
	end
	if clipState.capturing and not clipState.stopped and animT - clipState.startedAt >= CLIP_TIMEOUT then
		stopClip()
	elseif clipState.capturing and animT - clipState.startedAt >= CLIP_TIMEOUT + 5 then
		clipState.capturing = false -- capture jamais rendue par le moteur : l'état se ferme quand même
	end
	stepEvents()
end

-- Création des états ; aucun yield long
function VFXController.Init()
	effects = {}
end

-- Connexions et boucles
function VFXController.Start()
	if started then
		return
	end
	started = true
	local remote = Util.remote("Celebrate")
	if remote then
		table.insert(
			connections,
			remote.OnClientEvent:Connect(function(payload: any)
				Util.guard("VFXController.Celebrate", onCelebrate, payload)
			end)
		)
	end
	table.insert(
		connections,
		WorldStateController.MegaBeat:Connect(function()
			local giant = megaGiant
			if giant then
				giant.beatT = animT
			end
		end)
	)
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt: number)
			Util.guard("VFXController.step", VFXController._step, dt)
		end)
	)
	task.spawn(checkPolicy)
end

-- Coupe les connexions (fin de session, specs)
function VFXController._stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	started = false
end

return VFXController
