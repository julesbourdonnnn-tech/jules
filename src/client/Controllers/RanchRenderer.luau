--!strict
-- RanchRenderer (paquet client-world, docs/04 §13.3, GDD §5.2, §6.6, §9.3, §11.2, §12.9).
-- Rendu des ranchs et de la place, entièrement côté client, à partir du miroir WorldStateController :
--   * squishies des enclos et du Bassin (SquishyBuilder) à leur place (WorldLayout.penSlot / poolSlot,
--     rang par uid comme Server/Ranch/Places : la portée du serveur se mesure depuis la place), flânerie
--     de 2 studs au plus ; niveaux de détail < 60 / 60-140 / > 140 studs (× lodScale), ranchs à
--     > 220 studs en silhouette seule et compteur « ×N » ; au plus budgets().animated squishies
--     animés à chaque image, les autres à 15 Hz ou immobiles ; UN workspace:BulkMoveTo par image ;
--   * animation de repos (Squash.idle calé sur PressTiming : les sommets du rebond sont les PERFECT),
--     profils d'écrasement (play), cœurs des jumeaux (pulseTwins), squishies à la clôture (Fence) ;
--   * squishy porté et monture dessinés sur le personnage (aucune soudure) ; un personnage nil ou en
--     réapparition n'affiche rien et ne lève rien ; couleur de selle et traînée sur la monture ;
--   * silhouette du meilleur squishy de chaque ranch à Y = 40 (best.s = 0 : aucune silhouette), avec
--     sa taille ; statue de la place (attributs Statue* posés par le serveur) ;
--   * panneau du ranch (nom ou alias, R, Jour, badge boop ou bouclier) ; thème et drapeau du ranch ;
--     titre au-dessus de la tête de chaque joueur (≤ 150 studs, px TV, alias si le nom est caché) ;
--   * étiquettes de prix et de niveau des dalles de MON ranch (≤ 20 studs) et glyphe de la leçon de
--     l'accueil au-dessus de l'objet, toujours par UI/WorldText (jamais un texte au sol) ;
--   * bulle « Boîte à dodo ! » (world.vat.dodo) sur ma Cuve quand une naissance va au Dodo ;
--   * portails des ranchs des autres solides sur ce client (le mien reste ouvert) ;
--   * contours (Highlight) : cible du jeu (PromptController.setTarget → highlightTarget) et Mythiques /
--     Secrets les plus proches, dans highlightQuota.target / .ranch ; lumières d'aura des Légendaires+
--     les plus proches dans lightQuota.squishies. Les lumières RanchLight / LampLight, la jarre de la
--     jauge et l'anneau du MEGA appartiennent à LightingController (note INT-WORLD-1).
-- Une seule connexion par image (RenderStepped) ; durées locales = sommes de dt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)
local Balance = require(Shared.Config.Balance)
local Layout = require(Shared.Config.Layout)
local Species = require(Shared.Config.Species)
local Rarities = require(Shared.Config.Rarities)
local Cosmetics = require(Shared.Config.Cosmetics)
local Pads = require(Shared.Config.Pads)
local Quests = require(Shared.Config.Quests)
local SizeScale = require(Shared.Logic.SizeScale)
local WorldLayout = require(Shared.Logic.WorldLayout)
local PressTiming = require(Shared.Logic.PressTiming)
local TargetRules = require(Shared.Logic.TargetRules)
local Formulas = require(Shared.Logic.Formulas)
local FusionRules = require(Shared.Logic.FusionRules)
local RanchLook = require(Shared.Logic.RanchLook)
local Prestige = require(Shared.Logic.Prestige)
local SquishyBuilder = require(Shared.Render.SquishyBuilder)
local Squash = require(Shared.Render.Squash)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local StateController = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local QualityController = require(Client.Controllers.QualityController)
local WorldText = require(Client.UI.WorldText)
local Text = require(Client.UI.Text)
local Format = require(Client.UI.Format)
local Util = require(Client.World.Util)
-- v2.0 (lot B4, étapes 3 et 4, D26) : état et décors v2.0 des ranchs (Render/RanchV2), tous derrière
-- les attributs de leurs interrupteurs ; interrupteurs coupés, aucun travail ni aucune instance de plus
local RanchV2 = require(Client.Render.RanchV2)
-- v2.0 (lot B4, étape 5, D16) : halo du propriétaire de chaque ranch (attributs HaloOn et Ascend)
local Halo = require(Client.Render.Halo)

local RanchRenderer = {}

-- Crochets pour B5 (lot B4, étape 4 ; plan B4 §2.2) :
--   * RanchRenderer.detail(slot) : « full » | « reduced », détail v2.0 du ranch (D6 : ranch courant et
--     ses 2 voisins complets ; Graphismes légers : mon ranch et le courant) ;
--   * RanchRenderer.elementCFrame(slot, id) : repère d'un élément v2.0 dessiné (paliers, Cuve, fontaine,
--     lampions, portail, geyser, cadre, anneau-soleil, maisonnette, Monuments, Déco perso), nil sinon ;
--   * RanchRenderer.ElementBuilt (slot, id) : un élément vient d'être construit pour de vrai (premier
--     passage, joué en cascade ; jamais au chargement ni au changement de ranch) ;
--   * Render/BuildCascade.Piece (slot, position, index) : chaque pièce d'une cascade qui sort.
RanchRenderer.ElementBuilt = RanchV2.ElementBuilt

-- Distances et cadences (GDD §5.2, §9.3, §12.9)
local LOD = {
	Full = 60, -- studs : complet et animé à chaque image
	Mid = 140, -- corps + yeux à 15 Hz
	Far = 220, -- ranch au-delà : silhouette seule
	FarBack = 200, -- hystérésis : le ranch revient sous 200 studs
	MidHz = 15,
	BuildsPerFrame = 6, -- constructions par image au plus (pas de pic)
	Wander = 2, -- studs au plus autour de la place
	WanderMin = 4,
	WanderMax = 8,
	SilhouetteY = 40,
	TitleDistance = 150,
	SignDistance = 150,
	SilhouetteDistance = 1200,
	StatueDistance = 300,
	DodoBubble = 3, -- s
	HeartTime = 1, -- s (pulseTwins)
	ReadyPuff = 1.04, -- corps gonflé de 4 % quand il est prêt
	PoolBob = 0.3, -- studs (Y ± 0,3 à 0,5 Hz)
	PoolHz = 0.5,
	CarryHeight = 1.2, -- studs au-dessus de la tête
	SlowRefresh = 0.5, -- s : contours, lumières, étiquettes, titres
	LessonHeight = 3,
}

local MYTHIC = 6
local LEGENDARY = 5

type Drawn = {
	slot: number,
	uid: string,
	handle: SquishyBuilder.Handle?,
	lod: number,
	scale: number,
	scaleAt: number,
	where: string, -- "pen" | "pool" | "fence" | "carry" | "ride"
	wander: Vector3,
	nextWander: number,
	rng: Random,
	offset: number, -- PressTiming.offset
	profile: string?,
	profileT: number,
	heartUntil: number,
	animAt: number,
	pos: Vector3,
	rarity: number,
	light: PointLight?,
	saddleKey: string,
	trail: Trail?,
}

local drawn: { [number]: { [string]: Drawn } } = {}
local ranks: { [number]: { [string]: number } } = {}
local dirty: { [number]: boolean } = {}
local farRanch: { [number]: boolean } = {}
local silhouettes: { [number]: { handle: SquishyBuilder.Handle?, sig: string, label: BillboardGui? } } = {}
local signs: { [number]: BillboardGui } = {}
local titles: { [number]: { gui: BillboardGui, character: Model } } = {}
local padLabels: { [string]: BillboardGui } = {}
local gateState: { [number]: boolean } = {}
local themed: { [number]: string } = {}
local originalColors: { [BasePart]: Color3 } = {}
local flags: { [number]: { model: Model, id: string } } = {}
local statue: { handle: SquishyBuilder.Handle?, sig: string, label: BillboardGui? } = { sig = "" }
local highlights: { Highlight } = {}
local targetHighlight: Highlight? = nil
local target: { slot: number, uid: string }? = nil
local dodoBubble: { gui: BillboardGui, untilT: number }? = nil
local lessonGui: BillboardGui? = nil
local hearts: { Part } = {}
local heartPool: { Part } = {}

local animT = 0
local slowAcc = 0
local folder: Folder? = nil
local started = false
local connections: { any } = {}
local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}
local lastStats = {
	models = 0,
	parts = 0,
	animated = 0,
	highlights = 0,
	lights = 0,
	labels = 0,
	silhouettes = 0,
	fullRate = 0,
}

-- =============================================================================================
-- Outils
-- =============================================================================================

local function budgets(): any
	return Util.safe("QualityController.budgets", nil, QualityController.budgets)
		or {
			lodScale = 1,
			animated = 80,
			particles = 1,
			highlightQuota = { target = 1, chase = 7, ranch = 3 },
			lightQuota = { world = 16, ranch = 4, squishies = 4 },
		}
end

local function reducedMotion(): boolean
	return Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
end

local function lowGraphics(): boolean
	return Util.safe("Prefs.lowGraphics", false, Prefs.lowGraphics)
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
	local sub = (root :: Instance):FindFirstChild("Ranches")
	if sub == nil or not sub:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = "Ranches"
		created.Parent = root
		sub = created
	end
	folder = sub :: Folder
	return sub :: Folder
end

-- Modèle serveur d'un ranch (nil sans monde construit : specs, monde absent)
local function ranchModel(slot: number): Instance?
	local root = workspace:FindFirstChild("Wobbleton")
	local list = root and root:FindFirstChild("Ranches")
	return list and list:FindFirstChild(tostring(slot))
end

local function plazaChild(name: string): Instance?
	local root = workspace:FindFirstChild("Wobbleton")
	local plaza = root and root:FindFirstChild("Plaza")
	return plaza and plaza:FindFirstChild(name)
end

local function cameraPos(): Vector3
	local cam = workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position
	end
	local root = Util.localRoot()
	return if root then root.Position else Vector3.zero
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function characterOf(userId: number): Model?
	if userId == 0 then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	if character == nil then
		return nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return nil
	end
	return character
end

local function rootOf(character: Model?): BasePart?
	local r = character and character:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- Ordre de création d'un uid base 36 (Server/Ranch/Places.before)
local function before(a: string, b: string): boolean
	if #a ~= #b then
		return #a < #b
	end
	return a < b
end

local function rarityOf(species: number): number
	local def = Species.ById[species]
	return if def then def.rarity else 1
end

-- Squishies d'un ranch sans copie (lecture seule, à chaque image : budget PS4) ; repli : la copie
local function squishiesOf(slot: number): { [string]: Types.PublicSquishy }
	local view = (WorldStateController :: any).squishiesView
	if type(view) == "function" then
		return view(slot)
	end
	return WorldStateController.squishies(slot)
end

local function computeRanks(slot: number)
	local list = squishiesOf(slot)
	local byAt: { [string]: { string } } = { pen = {}, pool = {} }
	for uid, rec in list do
		local bucket = byAt[rec.at]
		if bucket then
			table.insert(bucket, uid)
		end
	end
	local out = {}
	for _, bucket in byAt do
		table.sort(bucket, before)
		for i, uid in bucket do
			out[uid] = i
		end
	end
	ranks[slot] = out
	dirty[slot] = false
end

-- Centre de la place d'un squishy (enclos ou Bassin), nil ailleurs
local function placeOf(slot: number, uid: string, rec: Types.PublicSquishy): Vector3?
	if dirty[slot] ~= false then
		computeRanks(slot)
	end
	local k = ranks[slot] and ranks[slot][uid]
	if k == nil then
		return nil
	end
	if rec.at == "pool" then
		return WorldLayout.poolSlot(slot, k)
	end
	return WorldLayout.penSlot(slot, k)
end

local function release(d: Drawn)
	if d.trail then
		d.trail:Destroy()
		d.trail = nil
	end
	local h = d.handle
	if h then
		d.handle = nil
		d.light = nil
		pcall(SquishyBuilder.release, h)
	end
end

-- v2.0 (lot B4, D19b) : couleurs des selles, traînées et drapeaux de la v2.0 (Cosmetics.ListV2 et
-- cosmétiques de la semaine) ; un identifiant de la v1.3 garde son rendu, un inconnu le repli d'aujourd'hui
local SADDLE_V2: { [string]: Color3 } = {
	confetti = Color3.fromRGB(255, 150, 200),
	goldenJelly = Color3.fromRGB(255, 205, 80),
	cosmos = Color3.fromRGB(70, 60, 150),
	titan = Color3.fromRGB(150, 160, 185),
	partyPopper = Color3.fromRGB(255, 125, 95),
	brick = Color3.fromRGB(205, 95, 65),
	icingSugar = Color3.fromRGB(235, 245, 255),
	cosmic = Color3.fromRGB(115, 75, 205),
	cookieSaddle = Color3.fromRGB(205, 150, 95),
}
local TRAIL_V2: { [string]: Color3 } = {
	confetti = Color3.fromRGB(255, 170, 220),
	jellyArc = Color3.fromRGB(140, 220, 255),
	streamers = Color3.fromRGB(255, 210, 120),
	littleHammers = Color3.fromRGB(205, 185, 150),
	colour = Color3.fromRGB(180, 255, 200),
	shootingStars = Color3.fromRGB(255, 245, 190),
	bubbleTrail = Color3.fromRGB(190, 230, 255),
}

local function saddleColorOf(slot: number, key: string): Color3
	local def = Cosmetics.ByKindId["saddle:" .. key]
	if def and def.color then
		return def.color
	end
	if def == nil and SADDLE_V2[key] then
		return SADDLE_V2[key]
	end
	return Cosmetics.RanchColors[slot] or Cosmetics.FreeRanchColor
end

local function build(d: Drawn, rec: Types.PublicSquishy, lod: number, scale: number)
	local ok, h = pcall(SquishyBuilder.build, {
		species = rec.s,
		mutation = rec.m,
		stars = rec.st,
		displayScale = scale,
		lod = lod,
		outfit = if rec.o ~= "" then rec.o else nil,
	}, clientFolder())
	if not ok or type(h) ~= "table" then
		return
	end
	d.handle = h
	d.lod = lod
	d.scale = scale
	pcall(SquishyBuilder.setParticles, h, if lowGraphics() then 0 else Util.num(budgets().particles, 1, 0, 1))
	if d.rarity >= LEGENDARY then
		local light = h.model:FindFirstChild("AuraLight", true)
		d.light = if light and light:IsA("PointLight") then light else nil
	end
end

-- =============================================================================================
-- Squishies : création, mise à jour, rendu
-- =============================================================================================

local function ensureDrawn(slot: number, uid: string, rec: Types.PublicSquishy): Drawn
	local list = drawn[slot]
	if list == nil then
		list = {}
		drawn[slot] = list
	end
	local d = list[uid]
	if d == nil then
		local seed = 0
		for i = 1, #uid do
			seed = (seed * 31 + string.byte(uid, i)) % 2147483647
		end
		d = {
			slot = slot,
			uid = uid,
			handle = nil,
			lod = 3,
			scale = 1,
			scaleAt = -math.huge,
			where = rec.at,
			wander = Vector3.zero,
			nextWander = 0,
			rng = Random.new(seed + slot * 7919),
			offset = 0,
			profile = nil,
			profileT = 0,
			heartUntil = 0,
			animAt = -math.huge,
			pos = Vector3.zero,
			rarity = rarityOf(rec.s),
			light = nil,
			saddleKey = "",
			trail = nil,
		}
		local r = WorldStateController.ranch(slot)
		d.offset = Util.safe("PressTiming.offset", 0, PressTiming.offset, if r then r.userId else 0, uid)
		list[uid] = d
	end
	return d
end

local function dropSlot(slot: number)
	local list = drawn[slot]
	if list then
		for _, d in list do
			release(d)
		end
	end
	drawn[slot] = nil
end

-- Où et comment dessiner un squishy : (lieu, position de base au sol, échelle affichée) ; nil = rien
local function placement(
	slot: number,
	uid: string,
	rec: Types.PublicSquishy,
	ranch: Types.RanchPublic,
	fenceIndex: { [string]: number }
): (string?, Vector3?, number)
	local size = WorldStateController.sizeOf(slot, uid)
	if ranch.carry == uid or ranch.ride == uid then
		local character = characterOf(ranch.userId)
		local root = rootOf(character)
		if root == nil then
			return nil, nil, 1
		end
		if ranch.ride == uid then
			local s = SizeScale.display(size, "ride", ranch.saddle)
			local hip = Balance.Ride.BaseHipHeight
				+ Balance.Ride.HipFactor * s * Balance.SizeScale.BaseDiameter
			return "ride", root.Position - Vector3.new(0, hip + 1, 0), s
		end
		local s = math.min(SizeScale.display(size, "pen"), 1.5)
		return "carry", root.Position + Vector3.new(0, 2.5 + LOD.CarryHeight, 0), s
	end
	local fi = fenceIndex[uid]
	if fi then
		return "fence", WorldLayout.fencePoint(slot, fi), SizeScale.display(size, "pen")
	end
	local place = placeOf(slot, uid, rec)
	if place == nil then
		return nil, nil, 1
	end
	return rec.at, place, SizeScale.display(size, if rec.at == "pool" then "pool" else "pen")
end

local function stepSquishy(
	d: Drawn,
	rec: Types.PublicSquishy,
	where: string,
	base: Vector3,
	scale: number,
	cam: Vector3,
	b: any,
	now: number,
	animBudget: { n: number },
	buildBudget: { n: number }
)
	local dist = (base - cam).Magnitude
	local k = Util.num(b.lodScale, 1, 0.1, 1)
	local lod = if dist < LOD.Full * k then 1 elseif dist < LOD.Mid * k then 2 else 3
	if where == "carry" or where == "ride" then
		lod = math.min(lod, 2)
	end
	if d.where ~= where then
		d.where = where
		d.animAt = -math.huge -- changement de lieu : nouvelle pose même immobile
	end
	if d.handle == nil then
		if buildBudget.n <= 0 then
			return
		end
		buildBudget.n -= 1
		build(d, rec, lod, scale)
		if d.handle == nil then
			return
		end
	end
	local h = d.handle :: SquishyBuilder.Handle
	if d.lod ~= lod then
		d.lod = lod
		pcall(SquishyBuilder.setLod, h, lod)
	end
	if math.abs(d.scale - scale) > d.scale * 0.01 then
		d.scale = scale
		d.animAt = -math.huge
		pcall(SquishyBuilder.setScale, h, scale)
	end
	-- cadence : complet à chaque image (budget animated), 15 Hz entre 60 et 140 studs, immobile au-delà
	local animate = false
	if lod == 1 and animBudget.n > 0 then
		animBudget.n -= 1
		animate = true
	elseif (lod <= 2 and animT - d.animAt >= 1 / LOD.MidHz) or (lod == 3 and d.animAt == -math.huge) then
		animate = true -- 15 Hz, ou première pose d'un squishy immobile
	end
	if not animate then
		return
	end
	d.animAt = animT
	-- flânerie à 2 studs au plus de la place (enclos seulement)
	if where == "pen" and animT >= d.nextWander then
		d.nextWander = animT + d.rng:NextNumber(LOD.WanderMin, LOD.WanderMax)
		local a = d.rng:NextNumber(0, math.pi * 2)
		local r = d.rng:NextNumber(0, LOD.Wander)
		d.wander = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	elseif where ~= "pen" then
		d.wander = Vector3.zero
	end
	local def = Species.ById[rec.s]
	local hz = if def then def.wobble.hz else 2
	local amp = (if def then def.wobble.amp else 0.1) * (if reducedMotion() then 0.5 else 1)
	local sx, sy, sz, hop = 1, 1, 1, 0
	if d.profile then
		local ok, a, bb, c, done =
			pcall(Squash.sample, d.profile, animT - d.profileT, if reducedMotion() then 0.5 else 1)
		if ok then
			sx, sy, sz = a, bb, c
			if done then
				d.profile = nil
			end
		else
			d.profile = nil
		end
	elseif where ~= "ride" and where ~= "carry" then
		local ok, a, bb, c, hh = pcall(Squash.idle, now, d.offset, hz, amp)
		if ok then
			sx, sy, sz, hop = a, bb, c, hh
		end
	end
	if where == "pen" and rec.ready <= now then
		sx, sy, sz = sx * LOD.ReadyPuff, sy * LOD.ReadyPuff, sz * LOD.ReadyPuff
	end
	pcall(SquishyBuilder.setSquash, h, sx, sy, sz)
	if lod <= 2 then
		pcall(SquishyBuilder.animate, h, now, reducedMotion())
	end
	local dia = Balance.SizeScale.BaseDiameter * scale
	local p = base + d.wander
	local y
	if where == "carry" or where == "ride" then
		y = p.Y + dia * 0.5
	else
		y = WorldLayout.groundY(p.X, p.Z) + dia * 0.5 + hop * dia
		if where == "pool" then
			y += math.sin(animT * math.pi * 2 * LOD.PoolHz + d.offset) * LOD.PoolBob
		end
	end
	local pos = Vector3.new(p.X, y, p.Z)
	d.pos = pos
	local look = cam - pos
	local cf = if Vector3.new(look.X, 0, look.Z).Magnitude > 0.1
		then CFrame.lookAt(pos, Vector3.new(cam.X, pos.Y, cam.Z))
		else CFrame.new(pos)
	if where == "ride" or where == "carry" then
		local r = WorldStateController.ranch(d.slot)
		local root = rootOf(characterOf(if r then r.userId else 0))
		if root then
			local lv = root.CFrame.LookVector
			cf = CFrame.lookAt(pos, pos + Vector3.new(lv.X, 0, lv.Z))
		end
	end
	local ok, parts, cframes = pcall(SquishyBuilder.pose, h, cf)
	if ok and type(parts) == "table" and type(cframes) == "table" then
		for i, part in parts do
			local c = cframes[i]
			if c then
				table.insert(bulkParts, part)
				table.insert(bulkCFrames, c)
			end
		end
	end
end

-- Couleur de selle et traînée de la monture (cosmétiques publics)
local function dressMount(d: Drawn, ranch: Types.RanchPublic)
	local h = d.handle
	if h == nil then
		return
	end
	local key = ranch.saddleColor .. "|" .. ranch.trail
	if d.saddleKey == key then
		return
	end
	d.saddleKey = key
	pcall(SquishyBuilder.setSaddleColor, h, saddleColorOf(d.slot, ranch.saddleColor))
	if d.trail then
		d.trail:Destroy()
		d.trail = nil
	end
	if ranch.trail ~= "" and not lowGraphics() then
		local def = Cosmetics.ByKindId["trail:" .. ranch.trail]
		local body = h.body
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailA"
		a0.Position = Vector3.new(0, 0.4, 0)
		a0.Parent = body
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailB"
		a1.Position = Vector3.new(0, -0.4, 0)
		a1.Parent = body
		local trail = Instance.new("Trail")
		trail.Name = "MountTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.5
		local color = if def and def.color
			then def.color
			elseif def == nil and TRAIL_V2[ranch.trail] then TRAIL_V2[ranch.trail]
			else Color3.fromRGB(255, 220, 240)
		trail.Color = ColorSequence.new(color)
		trail.Parent = body
		d.trail = trail
	end
end

local function stepRanch(
	slot: number,
	cam: Vector3,
	b: any,
	now: number,
	animBudget: { n: number },
	buildBudget: { n: number }
)
	local ranch = WorldStateController.ranch(slot)
	if ranch == nil or ranch.userId == 0 then
		dropSlot(slot)
		return
	end
	local center = WorldLayout.anchor(slot, "silhouette")
	local dist = flat(center, cam)
	local k = Util.num(b.lodScale, 1, 0.1, 1)
	local far = farRanch[slot] == true
	if far and dist < LOD.FarBack * math.max(k, 1) then
		far = false
	elseif not far and dist > LOD.Far * k then
		far = true
	end
	farRanch[slot] = far
	local list = squishiesOf(slot)
	local mine = drawn[slot] or {}
	-- squishies disparus du miroir
	for uid, d in mine do
		if list[uid] == nil then
			release(d)
			mine[uid] = nil
		end
	end
	local fenceUids = WorldStateController.fence(slot)
	local fenceIndex: { [string]: number } = {}
	for i, uid in fenceUids do
		fenceIndex[uid] = i
	end
	for uid, rec in list do
		-- ranch lointain : silhouette seule, ni place ni taille calculées (sauf porté / monture, dessinés
		-- sur le personnage) ; budget PS4 : 16 ranchs × 24 squishies à chaque image sinon
		local onPlayer = uid == ranch.carry or uid == ranch.ride
		local where, base, scale = nil, nil, 1
		if not far or onPlayer then
			where, base, scale = placement(slot, uid, rec, ranch, fenceIndex)
		end
		if where == nil or base == nil then
			local d = mine[uid]
			if d then
				release(d)
			end
		else
			local d = ensureDrawn(slot, uid, rec)
			mine = drawn[slot] or mine
			stepSquishy(d, rec, where, base, scale, cam, b, now, animBudget, buildBudget)
			if where == "ride" then
				dressMount(d, ranch)
			end
		end
	end
end

-- =============================================================================================
-- Silhouettes, statue, panneaux, titres, dalles, portails, thèmes, drapeaux
-- =============================================================================================

local function silhouetteSize(ranch: Types.RanchPublic): number
	local best = ranch.best
	if type(best) ~= "table" or best.s == 0 then
		return 0
	end
	local G = Formulas.G(ranch.growth, Clock.now())
	return Formulas.clampSize(best.z + (G - best.zg))
end

local function stepSilhouette(slot: number)
	local ranch = WorldStateController.ranch(slot)
	local entry = silhouettes[slot]
	local best = if ranch then ranch.best else nil
	if ranch == nil or ranch.userId == 0 or type(best) ~= "table" or best.s == 0 then
		if entry then
			if entry.handle then
				pcall(SquishyBuilder.release, entry.handle)
			end
			if entry.label then
				pcall(WorldText.release, entry.label)
			end
			silhouettes[slot] = nil
		end
		return
	end
	if entry == nil then
		entry = { handle = nil, sig = "", label = nil }
		silhouettes[slot] = entry
	end
	local size = silhouetteSize(ranch)
	local scale = SizeScale.display(size, "silhouette")
	local sig = string.format("%d:%d:%.2f", best.s, best.m, scale)
	local center = WorldLayout.anchor(slot, "silhouette")
	local pos = Vector3.new(center.X, LOD.SilhouetteY, center.Z)
	if entry.sig ~= sig then
		local first = entry.handle == nil
			or not string.find(entry.sig, string.format("^%d:%d:", best.s, best.m))
		if first then
			if entry.handle then
				pcall(SquishyBuilder.release, entry.handle)
			end
			local ok, h = pcall(SquishyBuilder.build, {
				species = best.s,
				mutation = best.m,
				stars = 0,
				displayScale = scale,
				lod = 2,
			}, clientFolder())
			entry.handle = if ok then h else nil
		elseif entry.handle then
			pcall(SquishyBuilder.setScale, entry.handle, scale)
		end
		entry.sig = sig
		if entry.handle then
			local okp, parts, cframes = pcall(SquishyBuilder.pose, entry.handle, CFrame.new(pos))
			if okp and type(parts) == "table" then
				for i, part in parts do
					table.insert(bulkParts, part)
					table.insert(bulkCFrames, cframes[i])
				end
			end
		end
	end
	if entry.label == nil and entry.handle then
		local ok, gui = pcall(WorldText.create, entry.handle.body, {
			kind = "text",
			maxDistance = LOD.SilhouetteDistance,
			studsOffset = Vector3.new(0, Balance.SizeScale.BaseDiameter * scale * 0.5 + 2, 0),
			name = "Silhouette" .. slot,
		})
		entry.label = if ok then gui else nil
	end
	if entry.label then
		local text = Util.number(size)
		if farRanch[slot] then
			local n = 0
			for _ in WorldStateController.squishies(slot) do
				n += 1
			end
			text ..= "  ×" .. n
		end
		pcall(WorldText.setText, entry.label, text)
	end
end

local function stepStatue()
	local part = plazaChild("Statue")
	if part == nil or not part:IsA("BasePart") then
		return
	end
	local s = Util.int(part:GetAttribute("StatueSpecies"), 0, 65535) or 0
	local m = Util.int(part:GetAttribute("StatueMutation"), 0, 255) or 0
	local z = Util.num(part:GetAttribute("StatueSize"), 0, 0)
	local name = Util.str(part:GetAttribute("StatueName"), "", 40)
	local scale = SizeScale.display(z, "statue")
	local sig = string.format("%d:%d:%.2f:%s", s, m, scale, name)
	-- pièce remplacée (place reconstruite) : son étiquette a été rendue à la réserve de WorldText (et
	-- peut-être reprise par un autre objet) ; on l'oublie sans la toucher et tout est refait (lot B4)
	local label = statue.label
	if label and label.Adornee ~= part then
		statue.label = nil
		statue.sig = ""
	end
	if statue.sig == sig then
		return
	end
	statue.sig = sig
	if statue.handle then
		pcall(SquishyBuilder.release, statue.handle)
		statue.handle = nil
	end
	if statue.label == nil then
		local ok, gui = pcall(WorldText.create, part, {
			kind = "text",
			maxDistance = LOD.StatueDistance,
			studsOffset = Vector3.new(0, 3, 0),
			name = "StatueLabel",
		})
		statue.label = if ok then gui else nil
	end
	if s == 0 then
		if statue.label then
			pcall(WorldText.setText, statue.label, Util.t("world.statueEmpty"))
		end
		return
	end
	local ok, h = pcall(SquishyBuilder.build, {
		species = s,
		mutation = m,
		stars = 0,
		displayScale = scale,
		lod = 1,
	}, clientFolder())
	if ok and type(h) == "table" then
		statue.handle = h
		local top = part.Position + Vector3.new(0, part.Size.Y * 0.5, 0)
		local dia = Balance.SizeScale.BaseDiameter * scale
		local okp, parts, cframes =
			pcall(SquishyBuilder.pose, h, CFrame.new(top + Vector3.new(0, dia * 0.5, 0)))
		if okp and type(parts) == "table" then
			for i, p in parts do
				table.insert(bulkParts, p)
				table.insert(bulkCFrames, cframes[i])
			end
		end
	end
	if statue.label then
		local shown = if name ~= "" then name else Util.t("world.statueEmpty")
		pcall(
			WorldText.setText,
			statue.label,
			Util.t("world.statue", { name = shown, size = Util.number(z) })
		)
	end
end

-- Record R montré sur le panneau (lot B4, étape 5, D20) : l'attribut BestR du ranch quand le serveur le
-- pose (interrupteur RecordR : « ce qu'on voit suit le Record R », un joueur qui vient de faire une
-- Ascension ne lit pas « 0 »), sinon le r public de la v1.3 ; valeur illisible : le r public
local function recordOf(slot: number, ranch: Types.RanchPublic): number
	local model = ranchModel(slot)
	local attr = if model then model:GetAttribute("BestR") else nil
	if type(attr) == "number" and attr == attr and attr > -math.huge and attr < math.huge then
		return math.clamp(math.floor(attr), 0, Balance.Prestige.MaxR)
	end
	return Prestige.r(ranch :: any)
end

-- Attribut booléen v2.0 du modèle du ranch (absent tant que son interrupteur est coupé : faux)
local function ranchFlag(slot: number, name: string): boolean
	local model = ranchModel(slot)
	return model ~= nil and model:GetAttribute(name) == true
end

-- Panneau du ranch : « Mira · ♛2 · Jour 42 · Booper » (ordre de la v1.3). Lot B4, étape 5 : la couronne
-- est DESSINÉE (repère Text.CROWN, UI/Glyph.crown : « ♛ » n'est dans aucune police du jeu, D20, dans les
-- deux états des interrupteurs) ; « PRÊT ! » (world.ready) à la fin tant que le ranch porte SplorchReady
local function signText(slot: number, ranch: Types.RanchPublic): string
	if ranch.userId == 0 then
		return Util.t("name.ranch", { n = slot })
	end
	local name = if ranch.hidden or ranch.name == "" then Util.displayName("", ranch.userId) else ranch.name
	local parts = { name }
	local record = recordOf(slot, ranch)
	if record > 0 then
		table.insert(parts, Text.CROWN .. Format.count(record))
	end
	if ranch.day > 0 then
		table.insert(parts, Util.t("world.ranchDay", { n = math.floor(ranch.day) }))
	end
	if ranch.mode == "rush" then
		if ranch.shield then
			table.insert(parts, Util.t("hud.status.shield"))
		elseif ranch.boopable then
			table.insert(parts, Util.t("prompt.boop"))
		end
	end
	if ranchFlag(slot, "SplorchReady") then
		table.insert(parts, Util.t("world.ready"))
	end
	return table.concat(parts, " · ")
end

local function stepSign(slot: number)
	local model = ranchModel(slot)
	local anchor = model and model:FindFirstChild("Sign")
	local ranch = WorldStateController.ranch(slot)
	local gui = signs[slot]
	if anchor == nil or ranch == nil then
		if gui then
			pcall(WorldText.release, gui)
			signs[slot] = nil
		end
		return
	end
	if gui == nil or gui.Parent == nil then
		local ok, created = pcall(WorldText.create, anchor, {
			kind = "text",
			maxDistance = LOD.SignDistance,
			name = "Sign" .. slot,
		})
		if not ok then
			return
		end
		gui = created
		signs[slot] = created
	end
	pcall(WorldText.setText, gui :: BillboardGui, signText(slot, ranch))
end

-- Ascensions montrées par le halo (lot B4, étape 5, D16) : A quand le ranch porte HaloOn = true
-- [RanchSkins] et Ascend ≥ 1 [JellyAscend] ; 0 sinon (aucun halo, plaque de la v1.3)
local function haloAscend(slot: number): number
	local model = ranchModel(slot)
	if model == nil or model:GetAttribute("HaloOn") ~= true then
		return 0
	end
	local a = model:GetAttribute("Ascend")
	if type(a) ~= "number" or a ~= a or a < 1 or a == math.huge then
		return 0
	end
	return math.min(math.floor(a), Balance.Prestige.MaxA)
end

local function titleText(slot: number, ranch: Types.RanchPublic): string
	local title = if ranch.title ~= "" then Util.t("cosmetic.title." .. ranch.title) else ""
	local text = title
	if ranch.hidden or ranch.name == "" then
		local alias = Util.displayName("", ranch.userId)
		text = if title ~= "" then alias .. " · " .. title else alias
	end
	-- v2.0 (D16) : une goutte dessinée (repère Text.DROP) et le nombre d'Ascensions à la fin de la plaque
	local a = haloAscend(slot)
	if a > 0 then
		local drop = Text.DROP .. Format.count(a)
		text = if text ~= "" then text .. " · " .. drop else drop
	end
	return text
end

local function stepTitle(slot: number)
	local ranch = WorldStateController.ranch(slot)
	local entry = titles[slot]
	local character = if ranch then characterOf(ranch.userId) else nil
	local head = character and character:FindFirstChild("Head")
	local text = if ranch then titleText(slot, ranch) else ""
	if ranch == nil or head == nil or text == "" then
		if entry then
			pcall(WorldText.release, entry.gui)
			titles[slot] = nil
		end
		return
	end
	if entry and (entry.character ~= character or entry.gui.Parent == nil) then
		pcall(WorldText.release, entry.gui)
		entry = nil
		titles[slot] = nil
	end
	if entry == nil then
		local ok, gui = pcall(WorldText.create, head :: Instance, {
			kind = "text",
			maxDistance = LOD.TitleDistance,
			studsOffset = Vector3.new(0, 2.5, 0),
			name = "Title" .. slot,
		})
		if not ok then
			return
		end
		entry = { gui = gui, character = character :: Model }
		titles[slot] = entry
	end
	pcall(WorldText.setText, (entry :: any).gui, text)
end

-- Halo du propriétaire du ranch (D16) : gouttes autour de sa tête tant que le ranch porte HaloOn et
-- Ascend ≥ 1 ; rien sans personnage (interrupteurs coupés : une lecture d'attribut par ranch toutes les 0,5 s)
local function stepHalo(slot: number)
	local a = haloAscend(slot)
	local ranch = if a > 0 then WorldStateController.ranch(slot) else nil
	local character = if ranch then characterOf(ranch.userId) else nil
	Halo.sync(slot, character, a, cameraPos())
end

-- v2.0 (lot B4, D11) [StarMat] : au-delà du Tapis 12, la dalle du Tapis que le serveur laisse allumée
-- (visible, Maxed = false) achète le Tapis Étoilé ; c'est le signal de l'interrupteur côté client (le
-- client ne lit jamais Config/Features). Niveau affiché (13 … 20) et prix : MON profil
-- (StateController) par RanchLook.padLabel, la copie de PadRules. Interrupteur coupé : dalle cachée par
-- le serveur, rien de plus que la v1.3.
local STAR_ON = table.freeze({ StarMat = true })
local SNACK_MAX = Balance.Tiles.snack.Levels
local myProfile: { [string]: any } = setmetatable({}, {
	__index = function(_, key)
		return StateController.get(key)
	end,
}) :: any

local function levelOf(tiles: Types.Tiles, key: string): number
	local v = (tiles :: any)[key]
	if type(v) == "boolean" then
		return if v then 1 else 0
	end
	return Util.num(v, 0, 0)
end

-- Étiquettes de prix et de niveau des dalles de MON ranch (UI/WorldText, ≤ 20 studs)
local function stepPads()
	local slot = WorldStateController.mySlot()
	local model = if slot > 0 then ranchModel(slot) else nil
	local folderPads = model and model:FindFirstChild("Pads")
	local ranch = if slot > 0 then WorldStateController.ranch(slot) else nil
	local seen: { [string]: boolean } = {}
	if folderPads and ranch then
		for _, key in Pads.Order do
			local def = Pads.Defs[key]
			local pad = folderPads:FindFirstChild(tostring(def.socket))
			local id = slot .. ":" .. key
			local lvl = levelOf(ranch.tiles, key)
			local cost = Formulas.tileCost(key, lvl, ranch.R)
			local visible = pad ~= nil
				and pad:IsA("BasePart")
				and pad.Transparency < 1
				and pad:GetAttribute("Maxed") ~= true
				and cost < math.huge
			-- Tapis Étoilé : dalle du Tapis allumée par le serveur au-delà du Tapis 12 (D11)
			local star: RanchLook.PadLabel? = nil
			if
				not visible
				and key == "snack"
				and lvl >= SNACK_MAX
				and pad ~= nil
				and pad:IsA("BasePart")
				and pad.Transparency < 1
				and pad:GetAttribute("Maxed") ~= true
			then
				local label = RanchLook.padLabel(myProfile, key, STAR_ON)
				if label.lit then
					star = label
					visible = true
				end
			end
			if visible then
				seen[id] = true
				local gui = padLabels[id]
				if gui == nil or gui.Parent == nil then
					local ok, created = pcall(WorldText.create, pad :: Instance, {
						kind = "text",
						maxDistance = Layout.WorldText.TileLabelDistance,
						studsOffset = Vector3.new(0, 3, 0),
						name = "PadLabel" .. def.socket,
					})
					gui = if ok then created else nil
					padLabels[id] = gui :: any
				end
				if gui then
					local text = if star
						then Util.t(
							"celebrate.tileBuilt",
							{ name = Util.t("upgrades.family.star"), n = star.level }
						) .. " · " .. Util.number(star.price)
						else Util.t("celebrate.tileBuilt", { name = Util.t("pad." .. key), n = lvl + 1 })
							.. " · "
							.. Util.number(cost)
					pcall(WorldText.setText, gui, text)
				end
			end
		end
	end
	for id, gui in padLabels do
		if not seen[id] then
			pcall(WorldText.release, gui)
			padLabels[id] = nil
		end
	end
end

-- Portails des ranchs des autres solides sur ce client ; le mien reste ouvert
local function stepGate(slot: number)
	local mine = WorldStateController.mySlot()
	local ranch = WorldStateController.ranch(slot)
	local solid = slot ~= mine and ranch ~= nil and ranch.userId ~= 0
	if gateState[slot] == solid then
		return
	end
	local model = ranchModel(slot)
	local gate = model and model:FindFirstChild("Gate")
	local membrane = gate and gate:FindFirstChild("Membrane")
	if membrane and membrane:IsA("BasePart") then
		membrane.CanCollide = solid
		gateState[slot] = solid
	end
end

local THEME_COLORS: { [string]: Color3 } = {
	moonlit = Color3.fromRGB(90, 100, 170),
	candyNight = Color3.fromRGB(150, 90, 170),
}

local FLAG_COLORS: { [string]: Color3 } = {
	squishydex = Color3.fromRGB(255, 210, 80),
	day14 = Color3.fromRGB(255, 150, 190),
	-- v2.0 (lot B4, D19b)
	nine = Color3.fromRGB(120, 200, 255),
	splorchRoyal = Color3.fromRGB(200, 60, 125),
	buildingSite = Color3.fromRGB(255, 190, 60),
	strawberryFlag = Color3.fromRGB(240, 90, 110),
}

-- Thème du ranch : teinte des poteaux et des lisses de la clôture (couleur d'origine gardée).
-- v2.0 (lot B4, D14) [RanchSkins] : un des 11 habillages v2.0, seulement si le ranch porte HaloOn,
-- habille clôture, sol des enclos et portail (Render/RanchV2) ; les 3 de la v1.3 rendent comme avant
local function stepTheme(slot: number)
	local ranch = WorldStateController.ranch(slot)
	local theme = if ranch and ranch.userId ~= 0 then ranch.theme else ""
	local skin = if RanchLook.isV2Skin(theme) then RanchV2.skinFor(slot, theme) else nil
	local key = if skin then "v2:" .. theme else theme
	if themed[slot] == key then
		return
	end
	local model = ranchModel(slot)
	local fence = model and model:FindFirstChild("Fence")
	if fence == nil then
		return
	end
	themed[slot] = key
	if skin == nil then
		RanchV2.clearSkin(slot)
	end
	local color = if skin then nil else THEME_COLORS[theme]
	for _, part in fence:GetDescendants() do
		if part:IsA("BasePart") then
			if color then
				if originalColors[part] == nil then
					originalColors[part] = part.Color
				end
				part.Color = color
			elseif originalColors[part] then
				part.Color = originalColors[part]
				originalColors[part] = nil
			end
		end
	end
	if skin then
		RanchV2.applySkin(slot, model :: Instance, skin)
	end
end

-- Drapeau du ranch : petit mât et drapeau à côté du panneau (pièces du client, ancrées, non solides)
local function stepFlag(slot: number)
	local ranch = WorldStateController.ranch(slot)
	local id = if ranch and ranch.userId ~= 0 then ranch.flag else ""
	local entry = flags[slot]
	if entry and entry.id == id then
		return
	end
	if entry then
		entry.model:Destroy()
		flags[slot] = nil
	end
	if id == "" then
		return
	end
	local gatePos = WorldLayout.anchor(slot, "gate")
	local sign = WorldLayout.anchor(slot, "sign")
	local side = WorldLayout.toWorld(slot, Vector3.new(6, 0, 0)) - WorldLayout.toWorld(slot, Vector3.zero)
	local base = Vector3.new(gatePos.X, WorldLayout.groundY(gatePos.X, gatePos.Z), gatePos.Z) + side
	local model = Instance.new("Model")
	model.Name = "Flag" .. slot
	local pole = Instance.new("Part")
	pole.Name = "Pole"
	pole.Anchored = true
	pole.CanCollide = false
	pole.CanQuery = false
	pole.CanTouch = false
	pole.CastShadow = false
	pole.Size = Vector3.new(0.4, 10, 0.4)
	pole.Color = Color3.fromRGB(250, 250, 250)
	pole.CFrame = CFrame.new(base + Vector3.new(0, 5, 0))
	pole.Parent = model
	local cloth = Instance.new("Part")
	cloth.Name = "Cloth"
	cloth.Anchored = true
	cloth.CanCollide = false
	cloth.CanQuery = false
	cloth.CanTouch = false
	cloth.CastShadow = false
	cloth.Size = Vector3.new(3, 2, 0.2)
	cloth.Color = FLAG_COLORS[id] or Color3.fromRGB(255, 255, 255)
	cloth.CFrame = CFrame.lookAt(base + Vector3.new(0, 8.8, 0), Vector3.new(sign.X, base.Y + 8.8, sign.Z))
		* CFrame.new(1.6, 0, 0)
	cloth.Parent = model
	model.Parent = clientFolder()
	flags[slot] = { model = model, id = id }
end

-- =============================================================================================
-- Contours, lumières, cœurs, bulle du Dodo, leçon
-- =============================================================================================

local function newHighlight(name: string): Highlight
	local h = Instance.new("Highlight")
	h.Name = name
	h.FillTransparency = 1
	h.OutlineTransparency = 0
	h.OutlineColor = Color3.fromRGB(255, 255, 255)
	h.Enabled = false
	h.Parent = clientFolder()
	return h
end

local function stepHighlights(cam: Vector3, b: any)
	local quota = b.highlightQuota or {}
	local ranchQuota = Util.num(quota.ranch, 0, 0, 3)
	local targetQuota = Util.num(quota.target, 0, 0, 1)
	-- cible du jeu
	local tgt = target
	local tModel: Model? = nil
	if tgt and targetQuota > 0 then
		local d = drawn[tgt.slot] and drawn[tgt.slot][tgt.uid]
		if d and d.handle then
			tModel = d.handle.model
		end
	end
	if tModel then
		if targetHighlight == nil then
			targetHighlight = newHighlight("TargetHighlight")
		end
		local th = targetHighlight :: Highlight
		th.Adornee = tModel
		th.Enabled = true
	elseif targetHighlight then
		targetHighlight.Enabled = false
		targetHighlight.Adornee = nil
	end
	-- Mythiques et Secrets les plus proches (≤ 140 studs)
	local list: { { d: Drawn, dist: number } } = {}
	for _, ranch in drawn do
		for _, d in ranch do
			if d.handle and d.rarity >= MYTHIC and d.handle.model ~= tModel then
				local dist = (d.pos - cam).Magnitude
				if dist < LOD.Mid then
					table.insert(list, { d = d, dist = dist })
				end
			end
		end
	end
	table.sort(list, function(x, y)
		return x.dist < y.dist
	end)
	for i = 1, 3 do
		local item = if i <= ranchQuota then list[i] else nil
		local hl = highlights[i]
		if item then
			if hl == nil then
				hl = newHighlight("RareHighlight" .. i)
				highlights[i] = hl
			end
			hl.OutlineColor = Color3.fromRGB(255, 230, 120)
			hl.Adornee = (item.d.handle :: SquishyBuilder.Handle).model
			hl.Enabled = true
		elseif hl then
			hl.Enabled = false
			hl.Adornee = nil
		end
	end
end

local function stepLights(cam: Vector3, b: any)
	local quota = Util.num(b.lightQuota and b.lightQuota.squishies, 4, 0, 4)
	local range = Util.num(b.lightRange, math.huge, 0)
	local list: { { d: Drawn, dist: number } } = {}
	for _, ranch in drawn do
		for _, d in ranch do
			if d.light then
				table.insert(list, { d = d, dist = (d.pos - cam).Magnitude })
			end
		end
	end
	table.sort(list, function(x, y)
		return x.dist < y.dist
	end)
	for i, item in list do
		local on = i <= quota and item.dist <= range
		local light = item.d.light :: PointLight
		if light.Enabled ~= on then
			light.Enabled = on
		end
	end
end

local function heartPart(): Part
	local p = table.remove(heartPool)
	if p then
		return p
	end
	local part = Instance.new("Part")
	part.Name = "TwinHeart"
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 120, 170)
	part.Size = Vector3.new(0.6, 0.6, 0.6)
	return part
end

local function stepHearts()
	for _, p in hearts do
		p.Parent = nil
		table.insert(heartPool, p)
	end
	table.clear(hearts)
	local slot = WorldStateController.mySlot()
	local list = drawn[slot]
	if list == nil then
		return
	end
	for _, d in list do
		if d.heartUntil > animT and d.handle then
			local part = heartPart()
			local s = if reducedMotion()
				then 1
				else 1 + 0.25 * (0.5 + 0.5 * math.sin(animT * math.pi * 2 * 1.5))
			part.Size = Vector3.new(0.6, 0.6, 0.6) * s
			local dia = Balance.SizeScale.BaseDiameter * d.scale
			part.CFrame = CFrame.new(d.pos + Vector3.new(0, dia * 0.6 + 0.8, 0))
			part.Parent = clientFolder()
			table.insert(hearts, part)
		end
	end
end

local function stepDodo()
	local bubble = dodoBubble
	if bubble and animT >= bubble.untilT then
		pcall(WorldText.release, bubble.gui)
		dodoBubble = nil
	end
end

local function showDodo()
	local slot = WorldStateController.mySlot()
	local model = if slot > 0 then ranchModel(slot) else nil
	local vat = model and model:FindFirstChild("Vat")
	if vat == nil then
		return
	end
	local adornee: Instance = vat
	if vat:IsA("Model") then
		adornee = vat:FindFirstChild("Lid") or vat:FindFirstChildWhichIsA("BasePart") or vat
	end
	if dodoBubble then
		dodoBubble.untilT = animT + LOD.DodoBubble
		return
	end
	local ok, gui = pcall(WorldText.create, adornee, {
		kind = "text",
		maxDistance = 80,
		studsOffset = Vector3.new(0, 4, 0),
		name = "VatDodo",
	})
	if ok then
		pcall(WorldText.setText, gui, Util.t("world.vat.dodo"))
		dodoBubble = { gui = gui, untilT = animT + LOD.DodoBubble }
	end
end

local LESSON_BINDINGS: { [string]: { keyboard: Enum.KeyCode, gamepad: Enum.KeyCode } } = {
	action = { keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonX },
	pickup = { keyboard = Enum.KeyCode.Q, gamepad = Enum.KeyCode.ButtonB },
}

-- Glyphe de la leçon de l'accueil au-dessus de mon squishy le plus proche (presser, prendre)
local function stepLesson()
	local ob = Util.safe("StateController.get", nil, StateController.get, "onboarding")
	local glyph: string? = nil
	if type(ob) == "table" and ob.done ~= true then
		local step = Util.num(ob.step, 0)
		for _, def in Quests.Onboarding.Steps do
			if def.step == step + 1 then
				glyph = def.glyph
				break
			end
		end
	end
	local binding = if glyph then LESSON_BINDINGS[glyph] else nil
	local slot = WorldStateController.mySlot()
	local best: Drawn? = nil
	local root = Util.localRoot()
	if binding and root and drawn[slot] then
		local bestD = math.huge
		for _, d in drawn[slot] do
			local dist = (d.pos - root.Position).Magnitude
			if d.handle and d.where == "pen" and dist < bestD then
				best, bestD = d, dist
			end
		end
	end
	if best == nil or binding == nil then
		if lessonGui then
			pcall(WorldText.release, lessonGui)
			lessonGui = nil
		end
		return
	end
	local body = ((best :: Drawn).handle :: SquishyBuilder.Handle).body
	if lessonGui == nil or lessonGui.Adornee ~= body then
		if lessonGui then
			pcall(WorldText.release, lessonGui)
		end
		local ok, gui = pcall(WorldText.create, body, {
			kind = "glyph",
			maxDistance = 40,
			studsOffset = Vector3.new(0, LOD.LessonHeight, 0),
			name = "LessonGlyph",
		})
		lessonGui = if ok then gui else nil
		if lessonGui then
			pcall(WorldText.setGlyph, lessonGui, binding :: any, Layout.WorldText.Glyph)
		end
	end
end

-- =============================================================================================
-- Image
-- =============================================================================================

local function countStats(fullRate: number)
	local models, parts, animated, lights = 0, 0, 0, 0
	for _, ranch in drawn do
		for _, d in ranch do
			if d.handle then
				models += 1
				parts += #d.handle.parts
				if d.lod == 1 then
					animated += 1
				end
				if d.light and d.light.Enabled then
					lights += 1
				end
			end
		end
	end
	local hl = 0
	for _, h in highlights do
		if h.Enabled then
			hl += 1
		end
	end
	if targetHighlight and targetHighlight.Enabled then
		hl += 1
	end
	local labels = 0
	for _ in padLabels do
		labels += 1
	end
	local sil = 0
	for _, s in silhouettes do
		if s.handle then
			sil += 1
		end
	end
	lastStats = {
		models = models,
		parts = parts,
		animated = animated,
		highlights = hl,
		lights = lights,
		labels = labels,
		silhouettes = sil,
		fullRate = fullRate,
	}
end

-- Une image (exposé aux specs ; appelé par RenderStepped)
function RanchRenderer._step(dt: number)
	animT += Util.num(dt, 0, 0, 1)
	local cam = cameraPos()
	local b = budgets()
	local now = Clock.now()
	table.clear(bulkParts)
	table.clear(bulkCFrames)
	local animBudget = { n = Util.num(b.animated, 80, 0, 400) }
	local buildBudget = { n = LOD.BuildsPerFrame }
	if WorldStateController.ready() then
		for slot = 1, WorldLayout.Const.Ranches do
			-- pas isolé par ranch : une donnée abîmée dans un ranch ne fige jamais tout le monde (sans
			-- cela, l'image s'arrêtait avant BulkMoveTo pour les 16 ranchs, erreur signalée une fois)
			Util.guard("RanchRenderer.ranch", stepRanch, slot, cam, b, now, animBudget, buildBudget)
		end
	end
	slowAcc += Util.num(dt, 0, 0, 1)
	if slowAcc >= LOD.SlowRefresh then
		slowAcc = 0
		if not RanchV2.watchedAll then
			Util.guard("RanchRenderer.v2watch", RanchV2.watch)
		end
		for slot = 1, WorldLayout.Const.Ranches do
			Util.guard("RanchRenderer.silhouette", stepSilhouette, slot)
			Util.guard("RanchRenderer.sign", stepSign, slot)
			Util.guard("RanchRenderer.title", stepTitle, slot)
			Util.guard("RanchRenderer.halo", stepHalo, slot)
			Util.guard("RanchRenderer.gate", stepGate, slot)
			Util.guard("RanchRenderer.theme", stepTheme, slot)
			Util.guard("RanchRenderer.flag", stepFlag, slot)
		end
		Util.guard("RanchRenderer.statue", stepStatue)
		Util.guard("RanchRenderer.pads", stepPads)
		Util.guard("RanchRenderer.highlights", stepHighlights, cam, b)
		Util.guard("RanchRenderer.lights", stepLights, cam, b)
		Util.guard("RanchRenderer.lesson", stepLesson)
	end
	stepHearts()
	stepDodo()
	-- v2.0 (lot B4, D19) : décors v2.0 seulement tant qu'un ranch en porte (un test sinon)
	if RanchV2.on then
		Util.guard("RanchRenderer.v2", RanchV2.step, dt, now)
	end
	if Halo.on then
		Util.guard("RanchRenderer.halo", Halo.step, dt)
	end
	if #bulkParts > 0 then
		local ok, err = pcall(function()
			workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			Util.raise("RanchRenderer.bulk", tostring(err))
		end
	end
	countStats(Util.num(b.animated, 80, 0, 400) - animBudget.n)
end

-- =============================================================================================
-- Signaux
-- =============================================================================================

local function onCelebrate(payload: any)
	if type(payload) ~= "table" or type(payload.data) ~= "table" then
		return
	end
	local data = payload.data
	if payload.kind == "hatch" then
		if data.at == "dodo" then
			showDodo()
		end
		-- v2.0 (lot B4, étape 4) : étincelles des buses de ma Cuve sur une naissance mutée (rien sans Cuve v2.0)
		if RanchV2.on then
			Util.guard("RanchRenderer.v2hatch", RanchV2.onHatch, data)
		end
	elseif payload.kind == "press" and type(data.uid) == "string" then
		local slot = WorldStateController.mySlot()
		if data.petsit == true then
			-- pet-sitting : le squishy pressé est celui de l'ami, à SA clôture
			slot = 0
			for s = 1, WorldLayout.Const.Ranches do
				if squishiesOf(s)[data.uid] ~= nil then
					slot = s
					break
				end
			end
		end
		RanchRenderer.play(slot, data.uid, if data.perfect == true then "perfect" else "press")
	elseif payload.kind == "fusion" and type(data.uid) == "string" then
		RanchRenderer.play(WorldStateController.mySlot(), data.uid, "fuse")
	end
end

-- Création des états ; aucun yield long
function RanchRenderer.Init()
	drawn = {}
	ranks = {}
	dirty = {}
end

-- Connexions et boucles
function RanchRenderer.Start()
	if started then
		return
	end
	started = true
	RanchV2.start({
		skinChanged = function(slot: number)
			themed[slot] = nil
		end,
	})
	Util.guard("RanchRenderer.v2watch", RanchV2.watch)
	table.insert(
		connections,
		WorldStateController.SquishyChanged:Connect(function(slot: number)
			dirty[slot] = true
		end)
	)
	table.insert(
		connections,
		WorldStateController.RanchChanged:Connect(function(slot: number, fields: { string })
			dirty[slot] = true
			if type(fields) == "table" and table.find(fields, "*") then
				gateState[slot] = nil
				themed[slot] = nil
			end
			RanchV2.onRanchChanged(slot, fields)
		end)
	)
	table.insert(
		connections,
		QualityController.Changed:Connect(function()
			RanchV2.onQualityChanged()
			for _, ranch in drawn do
				for _, d in ranch do
					if d.handle then
						local factor = if lowGraphics() then 0 else Util.num(budgets().particles, 1, 0, 1)
						pcall(SquishyBuilder.setParticles, d.handle, factor)
					end
				end
			end
		end)
	)
	local remote = Util.remote("Celebrate")
	if remote then
		table.insert(
			connections,
			remote.OnClientEvent:Connect(function(payload: any)
				Util.guard("RanchRenderer.Celebrate", onCelebrate, payload)
			end)
		)
	end
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt: number)
			Util.guard("RanchRenderer.step", RanchRenderer._step, dt)
		end)
	)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Détail v2.0 d'un ranch (« full » | « reduced ») : crochet pour B5 (lot B4, étape 4)
function RanchRenderer.detail(slot: number): string
	return RanchV2.detail(slot)
end

-- Repère d'un élément v2.0 dessiné sur ce ranch, nil sinon : crochet pour B5 (lot B4, étape 4)
function RanchRenderer.elementCFrame(slot: number, id: string): CFrame?
	return RanchV2.elementCFrame(slot, id)
end

-- Position dessinée d'un squishy (cible, effets) ; repli : centre de sa place
function RanchRenderer.positionOf(slot: number, uid: string): Vector3?
	if type(slot) ~= "number" or type(uid) ~= "string" then
		return nil
	end
	local d = drawn[slot] and drawn[slot][uid]
	if d and d.handle then
		return d.pos
	end
	local rec = WorldStateController.squishies(slot)[uid]
	if rec == nil then
		return nil
	end
	local place = placeOf(slot, uid, rec)
	if place == nil then
		return nil
	end
	return Vector3.new(place.X, WorldLayout.groundY(place.X, place.Z) + 1, place.Z)
end

-- Joue un profil d'écrasement (Render/Squash) sur un squishy
function RanchRenderer.play(slot: number, uid: string, profile: string)
	if type(slot) ~= "number" or type(uid) ~= "string" or type(profile) ~= "string" then
		return
	end
	local d = drawn[slot] and drawn[slot][uid]
	if d == nil then
		return
	end
	if Squash.duration(profile) <= 0 then
		return
	end
	d.profile = profile
	d.profileT = animT
end

-- Fait pulser 1 s les cœurs des jumeaux d'un squishy du ranch local
function RanchRenderer.pulseTwins(uid: string)
	local slot = WorldStateController.mySlot()
	if slot == 0 or type(uid) ~= "string" then
		return
	end
	local list = WorldStateController.squishies(slot)
	local rec = list[uid]
	if rec == nil then
		return
	end
	for other, r in list do
		if other ~= uid and Util.safe("FusionRules.areTwins", false, FusionRules.areTwins, rec, r) then
			local d = drawn[slot] and drawn[slot][other]
			if d then
				d.heartUntil = animT + LOD.HeartTime
			end
		end
	end
end

-- Contour de la cible du jeu (appelé par PromptController ; nil = aucune)
function RanchRenderer.highlightTarget(slot: number?, uid: string?)
	if type(slot) == "number" and type(uid) == "string" then
		target = { slot = slot, uid = uid }
	else
		target = nil
	end
end

-- Squishies candidats projetés à l'écran (clic souris) : ceux de mon ranch
function RanchRenderer.projected(camera: Camera): { TargetRules.Projected }
	local out: { TargetRules.Projected } = {}
	if camera == nil then
		return out
	end
	local slot = WorldStateController.mySlot()
	local list = drawn[slot]
	if list == nil then
		return out
	end
	for uid, d in list do
		if d.handle and (d.where == "pen" or d.where == "pool") then
			local ok, screen, onScreen = pcall(function()
				return camera:WorldToViewportPoint(d.pos)
			end)
			if ok and typeof(screen) == "Vector3" and onScreen and screen.Z > 0 then
				local dia = Balance.SizeScale.BaseDiameter * d.scale
				local fov = math.rad(Util.num(camera.FieldOfView, 70, 1, 120))
				local vh = Util.num(camera.ViewportSize.Y, 1080, 1)
				local radius = (dia * 0.5) / (screen.Z * math.tan(fov / 2)) * vh * 0.5
				table.insert(
					out,
					{ id = uid, screen = Vector2.new(screen.X, screen.Y), radius = radius, depth = screen.Z }
				)
			end
		end
	end
	return out
end

-- Compteurs de budget (modèles, pièces, animés, contours, lumières) pour les specs
function RanchRenderer.stats(): { [string]: number }
	return table.clone(lastStats)
end

-- Rarities et Types gardés pour les types publics
local _ = Rarities

-- Coupe les connexions (fin de session, specs)
function RanchRenderer._stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	RanchV2.stop()
	Halo.stop()
	started = false
end

return RanchRenderer
