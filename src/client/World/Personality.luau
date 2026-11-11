--!strict
-- Personality (lot B5 ; GDD §5.6 « Des squishies qui ont du caractère », §9.4 « Un achat », §11.5 ;
-- docs/04 §27.7 ; plan B5 D3, D4, D6 à D10, D29) : personnalités des squishies, entièrement côté
-- client, derrière l'interrupteur Personalities (World/Flags : le client ne lit jamais
-- Config/Features). Aucune pièce en plus, aucun trafic réseau, aucune règle du serveur n'en dépend.
--
--   Personality.active()                    -- vrai tant que Personalities est ouvert sur le serveur
--   Personality.Changed                     -- fn() quand active() change (déjà à jour quand il part)
--   Personality.pose(d, h, rec, where, base, cf, now) → CFrame
--                                           -- appelé par RanchRenderer.stepSquishy pour chaque squishy
--                                           -- dessiné et animé à cette image, APRÈS le calcul de sa
--                                           -- pose de repos (d.pos déjà écrit : le ciblage lit toujours
--                                           -- la place de repos) ; rend la pose à dessiner : la pose de
--                                           -- repos, ou la saynète composée dessus
--   Personality.forget(slot, uid)           -- le modèle de ce squishy est rendu à la réserve
--   Personality.setFace(slot, uid, face, seconds?)
--                                           -- visage (Config/Visuals.Faces) du squishy dessiné pour
--                                           -- `seconds` (60 s au plus, 60 s par défaut) ; vrai s'il est
--                                           -- posé ; faux et rien si l'interrupteur est coupé, si le
--                                           -- visage est inconnu ou si le squishy n'est pas dessiné
--   Personality.faceOf(slot, uid)           -- visage posé par ce module (« happy » sinon)
--   Personality.sceneOf(slot, uid)          -- saynète ou tour en cours (nil sinon)
--   Personality.wave(slot)                  -- la ola : un bond par squishy de l'enclos, décalé par la
--                                           -- colonne X de sa place ; rend le nombre de bonds
--   Personality.react(slot, kind, opts?)    -- réaction des squishies dessinés d'un ranch (0 = tous) :
--                                           -- "build" (se tournent vers opts.at, Ravi, petit saut ; une
--                                           -- fois toutes les 2 s par ranch), "delight", "surprise",
--                                           -- "starry" (regardent opts.at, opts.up : vers le ciel),
--                                           -- "sleep", "wake", "hearts" ; opts.uid : un seul squishy ;
--                                           -- opts.seconds : durée ; rend le nombre de squishies touchés
--   Personality.TrickLearned                -- fn(species, trickId) : nouveau tour d'une de MES espèces
--   Personality.stats()                     -- compteurs (specs, Diagnostics)
--
-- Saynètes (World/Scenes : 18 saynètes, 5 tours, données pures) :
--  * la personnalité vient de la colonne `perso` de Config/Species ; un hasard à graine par uid choisit
--    la saynète ; la suivante vient 8 à 20 s après la fin de la précédente ;
--  * seulement un squishy de l'enclos, en détail complet (niveau 1), à 40 studs de la caméra ou moins,
--    dans un ranch en détail complet (RanchRenderer.detail) ; 6 saynètes en cours au plus (3 en qualité
--    réduite ou en Graphismes légers), les plus proches d'abord ; les candidats sont triés une fois
--    par seconde au plus ; une 7e ne commence jamais, une saynète en cours n'est jamais coupée par la
--    limite ;
--  * jamais pour un squishy pressé (profil d'écrasement), ciblé (RanchRenderer.target), porté, dans le
--    Bassin, à la clôture, pendant un grand spectacle (EventState.spectacle : splorch, dance, ascend)
--    ni pendant le Petit Splorch de son propriétaire ; une pression ou un ciblage la termine à l'image
--    même (pose de repos) ;
--  * la pose est composée sur la pose de repos, CFrame seulement (aucune écriture de Size) ; le centre
--    du corps ne s'écarte jamais de plus de 2 studs, à plat, de la PLACE (flânerie comprise) ; d.pos
--    n'est jamais touché : positionOf et projected (la cible du jeu) lisent la pose de repos ;
--  * une saynète sur quatre d'un squishy qui connaît un tour est son plus beau tour (seuils de
--    Config/Quests.Mastery.Tricks : record de MON Étagère pour mes squishies, taille du squishy pour
--    ceux des autres) ; « Bravo » (EmoteShown, sorte 3) fait jouer son plus beau tour au Meilleur Ami
--    n° 1 du ranch de ce joueur ; un nouveau tour d'une de MES espèces est annoncé une fois par séance
--    et par (espèce, tour), jamais au chargement : message trick.new et son TrickPop (repli Pop).
-- Visages (Render/SquishyBuilder.setFace) et réactions : achat dans le ranch (Celebrate « tile »,
-- première pièce d'une cascade, RanchRenderer.ElementBuilt), série PERFECT, sirène du Rush, MEGA qui
-- atterrit à 120 studs ou moins, Grand Splorch d'un autre, début de la Jelly Moon, retour dans mon
-- ranch après 60 s dehors (Meilleur Ami : Ravi et 3 cœurs), joueur immobile 60 s (ceux à 15 studs
-- s'endorment). Un visage revient TOUJOURS à « happy » à la fin de sa durée (60 s au plus ; sommeil :
-- quand le joueur bouge, 300 s au plus), même si aucun message de fin n'arrive.
-- Ornements : gerbes de particules sur une attache réutilisée (20 particules en vie au plus, système
-- « life » de Render/VisualBudget : 0 pièce), « z » et « ? » en étiquettes de UI/WorldText (6 au plus).
-- Vermicelles d'une cascade (Render/BuildCascade.Piece) : 12 par construction, 24 pour un achat groupé,
-- dans le quota de particules de VFXController (VFXController.burst).
-- Prairie des copains : les 12 derniers relâchés de MON profil, en détail réduit (niveau 2), rebond de
-- repos à 15 Hz, aux places WorldLayout.meadowPoint(i, true) quand MON ranch porte l'attribut
-- Monuments, sinon meadowPoint(i) ; seulement tant que la caméra est à 140 studs ou moins.
--
-- Règles :
--  * interrupteur coupé : RanchRenderer n'appelle ni pose ni forget (un booléen local, relu sur
--    Changed) ; setFace, wave et react ne font rien ; aucune instance, aucune connexion (hors celle de
--    World/Flags, posée au chargement), aucun travail par image ;
--  * la boucle par image (RenderStepped) n'est branchée que tant que l'interrupteur est ouvert ET qu'il
--    y a quelque chose à faire vivre : un squishy dessiné, des relâchés à montrer dans la Prairie, une
--    gerbe ou une étiquette en vie ; aucune table créée par image en régime établi ;
--  * coupure en direct : chaque visage revient à « happy », les étiquettes, les attaches et la Prairie
--    sont rendues, les connexions coupées, AVANT que Changed parte ;
--  * RanchRenderer charge ce module (10e dans l'ordre du client) : RanchRenderer, VFXController et
--    UI/Toast ne sont requis qu'à la demande, sous pcall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)
local Balance = require(Shared.Config.Balance)
local Species = require(Shared.Config.Species)
local Quests = require(Shared.Config.Quests)
local Sounds = require(Shared.Config.Sounds)
local Pads = require(Shared.Config.Pads)
local WorldLayout = require(Shared.Logic.WorldLayout)
local SquishyBuilder = require(Shared.Render.SquishyBuilder)
local Squash = require(Shared.Render.Squash)

local Client = script.Parent.Parent
local Flags = require(Client.World.Flags)
local Scenes = require(Client.World.Scenes)
local Util = require(Client.World.Util)
local Prefs = require(Client.Util.Prefs)
local StateController = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local QualityController = require(Client.Controllers.QualityController)
local AudioController = require(Client.Controllers.AudioController)
local CameraController = require(Client.Controllers.CameraController)
local WorldText = require(Client.UI.WorldText)
local VisualBudget = require(Client.Render.VisualBudget)
local BuildCascade = require(Client.Render.BuildCascade)

local Personality = {}

Personality.Changed = Signal.new() :: Signal.Signal<>
Personality.TrickLearned = Signal.new() :: Signal.Signal<number, string>

local FLAG = "Personalities"
local DEFAULT_FACE = "happy"

-- Règles du GDD §5.6
local LIMIT = 2 -- studs à plat de la place, au plus
local SCOPE = 40 -- studs de la caméra, au plus, pour commencer une saynète
local CAP, CAP_REDUCED = 6, 3 -- saynètes en cours au plus
local GAP_MIN, GAP_MAX = 8, 20 -- secondes entre deux saynètes d'un squishy
local TRICK_EVERY = 4 -- une saynète sur quatre est le plus beau tour
local FRESH = 0.5 -- s : un squishy posé depuis moins longtemps est « dessiné et animé »
local SLOW = 1 -- s entre deux passes lentes (tri des candidats)
local FACE_CAP = 60 -- s : durée d'un visage, au plus
local SLEEP_CAP = 300 -- s : sommeil, au plus
local IDLE_AFTER = 60 -- s sans bouger : ceux à SLEEP_RADIUS studs s'endorment
local AWAY_AFTER = 60 -- s hors de mon ranch : accueil du Meilleur Ami au retour
local WELCOME_WAIT = 8 -- s pendant lesquelles l'accueil attend que le Meilleur Ami soit dessiné
local SLEEP_RADIUS = 15
local HEARTS_RADIUS = 8
local MEGA_RADIUS = 120
local MOVE_EPS = 0.5 -- studs : le joueur a bougé
local BUILD_GAP = 2 -- s : une réaction d'achat par ranch, au plus
local SHOW_CAP = 30 -- s : un grand spectacle bloque les saynètes ce temps-là au plus
local PRESTIGE_BLOCK = 4 -- s après PetitSplorchAt (coupure dure du Petit Splorch)
local BRAVO_WAIT = 3 -- s : un tour demandé par « Bravo » attend une place ce temps-là au plus
local ANNOUNCE_MAX = 3 -- annonces de tours au plus pour un même changement du profil
-- Ornements (D9)
local SYSTEM = "life"
local LIFE_LIMITS = table.freeze({ parts = 0, particles = 20, lights = 0 })
local FX_POOL = 6 -- attaches gardées
local PARTICLE_LIFE = 1.2 -- s
local LABELS_MAX = 6
local LABEL_DISTANCE = 60
-- Vermicelles d'une cascade (GDD §9.4)
local SPRINKLES, SPRINKLES_GROUP, SPRINKLE_CHUNK = 12, 24, 4
local CASCADE_GAP = 0.5 -- s sans pièce : la cascade suivante
-- Prairie des copains (D10)
local MEADOW_KEEP = Balance.Release.MeadowKeep
local MEADOW_NEAR, MEADOW_FAR = 140, 150
local MEADOW_HZ = 15
local MEADOW_LOD = 2

local BASE_D = Balance.SizeScale.BaseDiameter
local RANCHES = WorldLayout.Const.Ranches
local PEN_HALF = 22.5 -- demi-largeur des colonnes de l'enclos (repère du ranch)
local WAVE_SPREAD = 0.6 -- s entre la première et la dernière colonne de la ola
local PINK = Color3.fromRGB(255, 120, 170)
local GOLD = Color3.fromRGB(255, 205, 60)
local LABEL_TEXT: { [string]: string } = { z = "z", what = "?" }

-- Tours appris : seuils et clés de Config/Quests (identifiant = fin de la clé « trick.<id> »)
local TRICK_SIZES: { number } = {}
local TRICK_KEYS: { string } = {}
local TRICK_IDS: { string } = {}
for i, trick in Quests.Mastery.Tricks do
	TRICK_SIZES[i] = trick.size
	TRICK_KEYS[i] = trick.key
	TRICK_IDS[i] = string.match(trick.key, "([%w_]+)$") or ""
end

type Rec = {
	slot: number,
	uid: string,
	species: number,
	perso: string,
	rng: Random,
	gone: boolean,
	-- dernière pose vue (RanchRenderer)
	seenAt: number,
	where: string,
	lod: number,
	dia: number,
	pressed: boolean,
	px: number,
	py: number,
	pz: number,
	bx: number,
	bz: number,
	camDist: number,
	-- saynète
	nextAt: number,
	played: number,
	scene: string?,
	sceneAt: number,
	sceneDur: number,
	sceneFace: string,
	adornDone: boolean,
	homeW: number, -- lacet monde de la direction libre
	lookOn: boolean,
	lookX: number,
	lookZ: number,
	wantUntil: number, -- tour demandé par « Bravo », en attente d'une place
	-- bond et regard d'une réaction
	hopAt: number,
	hopDur: number,
	hopH: number,
	turnAt: number,
	turnUntil: number,
	turnX: number,
	turnZ: number,
	turnTilt: number,
	-- visage
	face: string,
	faceBy: string, -- "" | "scene" | "react" | "api"
	faceAt: number,
	faceUntil: number,
	sleeping: boolean,
	sleptEpoch: number,
	-- étiquette
	label: BillboardGui?,
	labelUntil: number,
}

type Fx = { att: Attachment, emitter: ParticleEmitter, n: number, at: number, rec: Rec? }
type MeadowSquishy = {
	handle: SquishyBuilder.Handle,
	x: number,
	z: number,
	ground: number,
	offset: number,
	hz: number,
	amp: number,
}

local on = Flags.on(FLAG)
local wired = false
local conns: { any } = {}
local stepConn: any = nil

local recs: { [number]: { [string]: Rec } } = {}
local recCount = 0
local running = 0
local cap = CAP
local faced: { [Rec]: boolean } = {}
local sleepers = 0
local idleEpoch = 0
local cand: { Rec } = {}
local wanting: { Rec } = {}
local labelRecs: { Rec } = {}
local fx: { Fx } = {}
local fxLive = 0
local detailFull: { [number]: boolean } = {}
local prestige: { [number]: boolean } = {}
local lastBuild: { [number]: number } = {}
local builtX: { [number]: number } = {}
local builtZ: { [number]: number } = {}

local camX, camY, camZ = 0, 0, 0
local slowAcc = 0
local mySlot = 0
local reducedMo = false
local particleFactor = 1
-- grand spectacle (EventState.spectacle)
local showOn, showUntil, blockedAll = false, 0, false
-- fronts d'EventState déjà vus (jamais de réaction à la première lecture)
local prevRush, prevMega, prevMoon = false, "idle", false
-- présence du joueur
local lastPos: Vector3? = nil
local lastMoveAt = 0
local lastInsideAt: number? = nil
local wasInside = false
local welcomeUntil = -math.huge
-- tours appris de MES espèces
local known: { [number]: number } = {}
local announced: { [number]: boolean } = {}
local armed = false
-- vermicelles
local sprinkle = { at = -math.huge, budget = 0, total = 0, seen = 0, sent = 0, left = 0, hue = 0 }
-- Prairie
local meadow = {
	wanted = {} :: { { s: number, m: number } },
	models = {} :: { MeadowSquishy },
	v2 = false,
	near = false,
	dirty = true,
	acc = 0,
	folder = nil :: Folder?,
	parts = {} :: { BasePart },
	cframes = {} :: { CFrame },
}
local counters =
	{ started = 0, cut = 0, finished = 0, tricks = 0, reactions = 0, announced = 0, sprinkles = 0 }

-- tables réutilisées (aucune création par image)
local sceneCtx: Scenes.Ctx = { reduced = false, look = 0, home = 0 }
local reactOpts: { [string]: any } = {}
local EMPTY: { [string]: any } = table.freeze({})

-- Sources remplaçables par les specs (_configure) : gerbe de vermicelles, message, son
local sources: {
	burst: ((Vector3, Color3, number) -> ())?,
	toast: ((string) -> ())?,
	play: ((string) -> ())?,
} =
	{}

-- =============================================================================================
-- Outils
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

local function smooth(u: number): number
	local x = clamp01(u)
	return x * x * (3 - 2 * x)
end

local function arc(u: number): number
	local x = clamp01(u)
	return 4 * x * (1 - x)
end

local function plateau(t: number, T: number, a: number, b: number): number
	if t <= 0 or t >= T then
		return 0
	end
	if t < a then
		return smooth(t / a)
	end
	if t > T - b then
		return smooth((T - t) / b)
	end
	return 1
end

local function validSlot(slot: any): boolean
	return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= RANCHES
end

-- Modules requis à la demande (RanchRenderer charge ce module ; VFXController charge RanchRenderer)
local rendererModule: any = nil
local function renderer(): any
	local m = rendererModule
	if m ~= nil then
		return m
	end
	local ok, mod = pcall(function(): any
		return require(Client.Controllers.RanchRenderer) :: any
	end)
	if ok and type(mod) == "table" and type(mod.handleOf) == "function" then
		rendererModule = mod
		return mod
	end
	return nil
end

-- Mode photo en cours (relecture B5, journal B5-62) : CameraController ne requiert ni ce module ni
-- RanchRenderer (aucune boucle de require) ; requis au chargement, jamais dans une image
local function photoOn(): boolean
	local ok, on = pcall(CameraController.photoOn)
	return ok and on == true
end

local function handleOf(slot: number, uid: string): SquishyBuilder.Handle?
	local rr = renderer()
	if rr == nil then
		return nil
	end
	local found, handle = pcall(rr.handleOf, slot, uid)
	if found and type(handle) == "table" then
		return handle
	end
	return nil
end

-- Cible du jeu (PromptController → RanchRenderer.highlightTarget) : ranch et uid, 0 et "" sans cible
local function target(): (number, string)
	local rr = rendererModule
	if rr == nil or type(rr.target) ~= "function" then
		return 0, ""
	end
	local ok, slot, uid = pcall(rr.target)
	if ok and type(slot) == "number" and type(uid) == "string" then
		return slot, uid
	end
	return 0, ""
end

local function ranchInstance(slot: number): Instance?
	local root = workspace:FindFirstChild("Wobbleton")
	local list = root and root:FindFirstChild("Ranches")
	return list and list:FindFirstChild(tostring(slot))
end

local function fresh(r: Rec, now: number): boolean
	return now - r.seenAt <= FRESH and r.seenAt <= now
end

-- =============================================================================================
-- Visages
-- =============================================================================================

-- Pose un visage sur le modèle du squishy (h : son modèle quand l'appelant l'a) ; vrai s'il est posé
local function applyFace(r: Rec, face: string, h: SquishyBuilder.Handle?): boolean
	local handle = h or handleOf(r.slot, r.uid)
	local ok = handle ~= nil and pcall(SquishyBuilder.setFace, handle :: SquishyBuilder.Handle, face)
	if face == DEFAULT_FACE then
		-- le visage de repos est noté même sans modèle (la réserve le rend toujours avec « happy »)
		r.face = DEFAULT_FACE
		r.faceBy = ""
		faced[r] = nil
		if r.sleeping then
			r.sleeping = false
			sleepers = math.max(0, sleepers - 1)
		end
		return ok
	end
	if not ok then
		return false
	end
	if r.sleeping then
		r.sleeping = false
		sleepers = math.max(0, sleepers - 1)
	end
	r.face = face
	faced[r] = true
	return true
end

-- Visage d'une réaction (ou de l'API) pour `seconds` secondes : il passe devant celui d'une saynète
local function timedFace(r: Rec, face: string, seconds: number, now: number, by: string): boolean
	if not applyFace(r, face, nil) then
		return false
	end
	r.faceBy = by
	r.faceAt = now
	r.faceUntil = now + math.clamp(seconds, 0.05, FACE_CAP)
	-- la saynète en cours reposera son visage à la fin de celui-ci
	r.sceneFace = ""
	return true
end

-- Les visages arrivés au bout de leur durée reviennent à « happy » (horloge recalée : aussi)
local function expireFaces(now: number)
	for r in faced do
		local age = now - r.faceAt
		if now >= r.faceUntil or age < 0 or age > (if r.sleeping then SLEEP_CAP else FACE_CAP) then
			if r.sleeping then
				r.sleptEpoch = idleEpoch -- réveillé par le temps : plus de sommeil avant que le joueur bouge
			end
			applyFace(r, DEFAULT_FACE, nil)
			r.sceneFace = ""
		end
	end
end

-- =============================================================================================
-- Ornements : étiquettes « z » / « ? » et gerbes de particules
-- =============================================================================================

local function releaseLabel(r: Rec)
	local gui = r.label
	if gui == nil then
		return
	end
	r.label = nil
	pcall(WorldText.release, gui)
	local i = table.find(labelRecs, r)
	if i then
		table.remove(labelRecs, i)
	end
end

local function showLabel(r: Rec, h: SquishyBuilder.Handle, kind: string, seconds: number, now: number)
	local text = LABEL_TEXT[kind]
	if text == nil or r.label ~= nil or #labelRecs >= LABELS_MAX then
		return
	end
	local ok, gui = pcall(WorldText.create, h.body, {
		kind = "plus",
		maxDistance = LABEL_DISTANCE,
		studsOffset = Vector3.new(0, r.dia * 0.75 + 0.8, 0),
		name = "LifeLabel",
		photoHide = true, -- caché en mode photo (lot I, étape 5, D22)
	})
	if not ok or gui == nil then
		return
	end
	pcall(WorldText.setText, gui, text)
	r.label = gui
	r.labelUntil = now + seconds
	table.insert(labelRecs, r)
end

local function expireLabels(now: number)
	for i = #labelRecs, 1, -1 do
		local r = labelRecs[i]
		if now >= r.labelUntil or r.labelUntil - now > FACE_CAP then
			releaseLabel(r)
		end
	end
end

local function freeFx(entry: Fx)
	if entry.n > 0 then
		VisualBudget.release(SYSTEM, entry.n, "particles")
		entry.n = 0
		fxLive = math.max(0, fxLive - 1)
	end
	entry.rec = nil
	if entry.att.Parent ~= nil then
		entry.att.Parent = nil
	end
end

local function expireFx(now: number)
	for _, entry in fx do
		if entry.n > 0 and (now - entry.at >= PARTICLE_LIFE or now < entry.at) then
			freeFx(entry)
		end
	end
end

-- Gerbe de `count` particules au-dessus du squishy ; jamais plus de 20 particules en vie
local function emit(r: Rec, h: SquishyBuilder.Handle, color: Color3, count: number, now: number)
	if particleFactor <= 0 then
		return
	end
	local n = math.max(1, math.floor(count * particleFactor + 0.5))
	n = math.min(n, LIFE_LIMITS.particles - VisualBudget.used(SYSTEM, "particles"))
	if n <= 0 then
		return
	end
	local entry: Fx? = nil
	for _, e in fx do
		if e.n == 0 then
			entry = e
			break
		end
	end
	if entry == nil then
		if #fx >= FX_POOL then
			return
		end
		local att = Instance.new("Attachment")
		att.Name = "LifeFx"
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Burst"
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.7, PARTICLE_LIFE)
		emitter.Speed = NumberRange.new(2, 4)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.Parent = att
		local created: Fx = { att = att, emitter = emitter, n = 0, at = 0, rec = nil }
		table.insert(fx, created)
		entry = created
	end
	local e = entry :: Fx
	if not VisualBudget.take(SYSTEM, n, "particles") then
		return
	end
	e.n = n
	e.at = now
	e.rec = r
	fxLive += 1
	e.att.Position = Vector3.new(0, h.body.Size.Y * 0.55, 0)
	e.att.Parent = h.body
	e.emitter.Color = ColorSequence.new(color)
	e.emitter:Emit(n)
end

-- =============================================================================================
-- Saynètes
-- =============================================================================================

-- Niveau de tour (0 … 5) d'une taille
local function levelOf(size: any): number
	if type(size) ~= "number" or size ~= size then
		return 0
	end
	local level = 0
	for i, threshold in TRICK_SIZES do
		if size >= threshold then
			level = i
		end
	end
	return level
end

-- Plus beau tour connu d'un squishy : record de MON Étagère pour mes squishies, sa taille pour les autres
local function trickLevel(r: Rec): number
	if r.slot == mySlot and mySlot ~= 0 then
		local trophies = StateController.get("trophies")
		return levelOf(if type(trophies) == "table" then trophies[r.species] else nil)
	end
	return levelOf(Util.safe("WorldStateController.sizeOf", 0, WorldStateController.sizeOf, r.slot, r.uid))
end

-- défini plus bas : un tour demandé par « Bravo » prend la place qui se libère
local serveWanting: (number) -> ()

-- Fin d'une saynète (naturelle ou coupée) : visage et étiquette rendus, prochaine dans 8 à 20 s
local function endScene(r: Rec, now: number, cut: boolean, h: SquishyBuilder.Handle?)
	if r.scene == nil then
		return
	end
	r.scene = nil
	running = math.max(0, running - 1)
	if cut then
		counters.cut += 1
	else
		counters.finished += 1
	end
	if r.faceBy == "scene" then
		applyFace(r, DEFAULT_FACE, h)
	end
	r.sceneFace = ""
	releaseLabel(r)
	r.nextAt = now + r.rng:NextNumber(GAP_MIN, GAP_MAX)
	if #wanting > 0 then
		serveWanting(now)
	end
end

-- Commence la saynète `id` ; vrai si elle est commencée
local function startScene(r: Rec, id: string, now: number): boolean
	local duration = Scenes.duration(id)
	if duration <= 0 or r.scene ~= nil then
		return false
	end
	r.scene = id
	r.sceneAt = now
	r.sceneDur = duration
	r.sceneFace = ""
	r.adornDone = false
	running += 1
	counters.started += 1
	-- direction libre : vers la place (au hasard quand il y est)
	local hx, hz = r.bx - r.px, r.bz - r.pz
	if hx * hx + hz * hz > 0.01 then
		r.homeW = math.atan2(-hx, -hz)
	else
		r.homeW = r.rng:NextNumber(-math.pi, math.pi)
	end
	-- point regardé : le joueur, le voisin le plus proche, la dernière décoration construite
	r.lookOn = false
	if id == "hello" then
		local root = Util.localRoot()
		if root then
			r.lookOn, r.lookX, r.lookZ = true, root.Position.X, root.Position.Z
		end
	elseif id == "what" then
		local x, z = builtX[r.slot], builtZ[r.slot]
		if x == nil or z == nil then
			local vat = WorldLayout.anchor(r.slot, "vat")
			x, z = vat.X, vat.Z
		end
		r.lookOn, r.lookX, r.lookZ = true, x, z
	elseif id == "kiss" then
		local best = math.huge
		local list = recs[r.slot]
		if list then
			for _, other in list do
				if other ~= r and other.where == "pen" and fresh(other, now) then
					local dx, dz = other.px - r.px, other.pz - r.pz
					local d2 = dx * dx + dz * dz
					if d2 < best then
						best = d2
						r.lookOn, r.lookX, r.lookZ = true, other.px, other.pz
					end
				end
			end
		end
	end
	return true
end

-- Le squishy peut commencer (ou garder) une saynète : enclos, détail complet, ni pressé ni endormi,
-- aucun grand spectacle, aucun Petit Splorch de son propriétaire
local function free(r: Rec, now: number): boolean
	return r.where == "pen"
		and r.lod == 1
		and not r.pressed
		and not r.sleeping
		and not blockedAll
		and prestige[r.slot] ~= true
		and fresh(r, now)
end

-- Saynète suivante d'un squishy : une sur quatre est son plus beau tour
local function pick(r: Rec): string
	r.played += 1
	if r.played % TRICK_EVERY == 0 then
		local level = trickLevel(r)
		if level > 0 and TRICK_IDS[level] ~= "" then
			counters.tricks += 1
			return TRICK_IDS[level]
		end
	end
	local list = Scenes.of(r.perso)
	if #list == 0 then
		list = Scenes.of("curious")
	end
	return list[r.rng:NextInteger(1, #list)]
end

local function byDistance(a: Rec, b: Rec): boolean
	if a.camDist ~= b.camDist then
		return a.camDist < b.camDist
	end
	if a.slot ~= b.slot then
		return a.slot < b.slot
	end
	return a.uid < b.uid
end

-- Passe lente : saynètes dont le squishy n'est plus posé terminées, puis départs dans la limite, les
-- plus proches d'abord (un seul tri par passe)
local function schedule(now: number)
	local tSlot, tUid = target()
	table.clear(cand)
	for _, list in recs do
		for _, r in list do
			if r.scene ~= nil then
				if now - r.sceneAt >= r.sceneDur or now < r.sceneAt then
					endScene(r, now, false, nil)
				end
			elseif not blockedAll then
				if r.nextAt - now > GAP_MAX then
					r.nextAt = now + r.rng:NextNumber(GAP_MIN, GAP_MAX) -- horloge recalée en arrière
				end
				if
					now >= r.nextAt
					and r.camDist <= SCOPE
					and detailFull[r.slot] == true
					and free(r, now)
					and not (r.slot == tSlot and r.uid == tUid)
				then
					table.insert(cand, r)
				end
			end
		end
	end
	if running < cap and #cand > 0 then
		if #cand > 1 then
			table.sort(cand, byDistance)
		end
		for _, r in cand do
			if running >= cap then
				break
			end
			startScene(r, pick(r), now)
		end
	end
	table.clear(cand)
end

-- Tour demandé par « Bravo » : tout de suite s'il reste une place, sinon dès qu'une se libère
local function wantTrick(r: Rec, now: number): boolean
	local level = trickLevel(r)
	if level <= 0 or TRICK_IDS[level] == "" or r.scene ~= nil or not free(r, now) then
		return false
	end
	local tSlot, tUid = target()
	if r.slot == tSlot and r.uid == tUid then
		return false
	end
	if running < cap then
		counters.tricks += 1
		return startScene(r, TRICK_IDS[level], now)
	end
	if r.wantUntil < now then
		table.insert(wanting, r)
	end
	r.wantUntil = now + BRAVO_WAIT
	return true
end

serveWanting = function(now: number)
	local tSlot, tUid = target()
	for i = #wanting, 1, -1 do
		local r = wanting[i]
		local aimed = r.slot == tSlot and r.uid == tUid
		if r.gone or aimed or now > r.wantUntil or r.scene ~= nil or not free(r, now) then
			r.wantUntil = -math.huge
			table.remove(wanting, i)
		end
	end
	for _ = 1, #wanting do
		if running >= cap then
			break
		end
		local r = table.remove(wanting, 1) :: Rec
		r.wantUntil = -math.huge
		local level = trickLevel(r)
		if level > 0 and TRICK_IDS[level] ~= "" then
			counters.tricks += 1
			startScene(r, TRICK_IDS[level], now)
		end
	end
end

-- Visage et ornement de la saynète à l'instant t (appelé depuis pose : le modèle est là)
local function sceneTick(r: Rec, id: string, t: number, h: SquishyBuilder.Handle, now: number)
	local face = Scenes.face(id, t) or DEFAULT_FACE
	if face ~= r.sceneFace then
		r.sceneFace = face
		if r.faceBy == "" or r.faceBy == "scene" then
			if applyFace(r, face, h) and face ~= DEFAULT_FACE then
				r.faceBy = "scene"
				r.faceAt = now
				r.faceUntil = r.sceneAt + r.sceneDur + 0.25
			end
		end
	end
	if not r.adornDone then
		local kind, n, from, to = Scenes.adorn(id)
		if kind == nil then
			r.adornDone = true
		elseif t >= from then
			r.adornDone = true
			if n <= 0 then
				showLabel(r, h, kind, to - from, now)
			elseif kind == "hearts" then
				local near = id ~= "hearts"
				if not near then
					-- « Cœurs » : seulement si le joueur est à 8 studs ou moins
					local root = Util.localRoot()
					if root then
						local dx, dz = root.Position.X - r.px, root.Position.Z - r.pz
						near = dx * dx + dz * dz <= HEARTS_RADIUS * HEARTS_RADIUS
					end
				end
				if near then
					emit(r, h, PINK, n, now)
				end
			else
				emit(r, h, GOLD, n, now)
			end
		end
	end
end

-- Pose de la saynète composée sur la pose de repos : le centre du corps reste à LIMIT studs à plat
-- de la place (flânerie, déplacement de la saynète et bascule compris) ; CFrame seulement
local function compose(
	cf: CFrame,
	base: Vector3,
	half: number,
	dx: number,
	dy: number,
	dz: number,
	yaw: number,
	pitch: number,
	roll: number,
	pivot: number
): CFrame
	local p = cf.Position
	local rot = CFrame.Angles(0, yaw, 0)
	if pitch ~= 0 then
		rot *= CFrame.Angles(pitch, 0, 0)
	end
	if roll ~= 0 then
		rot *= CFrame.Angles(0, 0, roll)
	end
	local lift = clamp01(pivot) * half
	-- bascule : le centre du corps (half au-dessus du dessous) se décale à plat
	local up = rot.UpVector
	local lean = half - lift
	local centre = cf:VectorToWorldSpace(Vector3.new(dx + up.X * lean, 0, dz + up.Z * lean))
	local ox, oz = p.X + centre.X - base.X, p.Z + centre.Z - base.Z
	local m = math.sqrt(ox * ox + oz * oz)
	local sx, sz = 0, 0
	if m > LIMIT then
		local f = LIMIT / m
		sx, sz = ox * f - ox, oz * f - oz
	end
	local move = cf:VectorToWorldSpace(Vector3.new(dx, 0, dz))
	local out = CFrame.new(p.X + move.X + sx, p.Y + dy, p.Z + move.Z + sz) * cf.Rotation
	if lift > 0 then
		return out * CFrame.new(0, lift, 0) * rot * CFrame.new(0, -lift, 0)
	end
	return out * rot
end
Personality._compose = compose

local function newRec(slot: number, uid: string, pub: any, now: number): Rec
	local species = if type(pub) == "table" and type(pub.s) == "number" then pub.s else 0
	if Species.ById[species] == nil then
		local view =
			Util.safe("WorldStateController.squishiesView", EMPTY, WorldStateController.squishiesView, slot)
		local found = (view :: any)[uid]
		species = if type(found) == "table" and type(found.s) == "number" then found.s else Species.PLOP
	end
	local def = Species.ById[species]
	local seed = 0
	for i = 1, #uid do
		seed = (seed * 31 + string.byte(uid, i)) % 2147483647
	end
	local rng = Random.new(seed + slot * 104729 + 17)
	local r: Rec = {
		slot = slot,
		uid = uid,
		species = species,
		perso = if def then def.perso else "curious",
		rng = rng,
		gone = false,
		seenAt = -math.huge,
		where = "",
		lod = 3,
		dia = BASE_D,
		pressed = false,
		px = 0,
		py = 0,
		pz = 0,
		bx = 0,
		bz = 0,
		camDist = math.huge,
		nextAt = now + rng:NextNumber(0, GAP_MAX),
		played = 0,
		scene = nil,
		sceneAt = 0,
		sceneDur = 0,
		sceneFace = "",
		adornDone = false,
		homeW = 0,
		lookOn = false,
		lookX = 0,
		lookZ = 0,
		wantUntil = -math.huge,
		hopAt = -math.huge,
		hopDur = 0,
		hopH = 0,
		turnAt = 0,
		turnUntil = -math.huge,
		turnX = 0,
		turnZ = 0,
		turnTilt = 0,
		face = DEFAULT_FACE,
		faceBy = "",
		faceAt = 0,
		faceUntil = -math.huge,
		sleeping = false,
		sleptEpoch = -1,
		label = nil,
		labelUntil = -math.huge,
	}
	local list = recs[slot]
	if list == nil then
		list = {}
		recs[slot] = list
	end
	list[uid] = r
	recCount += 1
	return r
end

local function recOf(slot: number, uid: string): Rec?
	local list = recs[slot]
	return if list then list[uid] else nil
end

-- =============================================================================================
-- Réactions
-- =============================================================================================

-- Le squishy est dessiné et animé (visage visible : détail complet ou réduit)
local function reachable(r: Rec, now: number): boolean
	return r.lod <= 2 and fresh(r, now)
end

local function turnTo(r: Rec, at: Vector3, seconds: number, tilt: number, now: number)
	if r.where ~= "pen" then
		return
	end
	r.turnAt = now
	r.turnUntil = now + seconds
	r.turnX, r.turnZ = at.X, at.Z
	r.turnTilt = tilt
end

local function hop(r: Rec, delay: number, duration: number, height: number, now: number)
	if r.where ~= "pen" then
		return
	end
	r.hopAt = now + delay
	r.hopDur = duration
	r.hopH = height * (if reducedMo then 0.5 else 1)
end

local function sleep(r: Rec, now: number): boolean
	if r.sleeping or r.sleptEpoch == idleEpoch then
		return false
	end
	if not applyFace(r, "sleepy", nil) then
		return false
	end
	r.faceBy = "react"
	r.faceAt = now
	r.faceUntil = now + SLEEP_CAP
	r.sceneFace = ""
	r.sleeping = true
	sleepers += 1
	-- endormi : sa saynète s'arrête (le visage du sommeil reste)
	if r.scene ~= nil then
		endScene(r, now, true, nil)
	end
	return true
end

local function reactOne(
	r: Rec,
	kind: string,
	at: Vector3?,
	seconds: number?,
	up: boolean,
	now: number
): boolean
	if kind == "build" then
		timedFace(r, "delighted", seconds or 1.6, now, "react")
		if at then
			turnTo(r, at, 1.6, 0, now)
		end
		hop(r, 0, 0.35, 0.25 * r.dia, now)
		return true
	elseif kind == "delight" then
		return timedFace(r, "delighted", seconds or 2, now, "react")
	elseif kind == "surprise" then
		return timedFace(r, "surprised", seconds or 2.5, now, "react")
	elseif kind == "starry" then
		local length = seconds or 6
		if at then
			turnTo(r, at, length, if up then math.rad(15) else 0, now)
		end
		return timedFace(r, "starry", length, now, "react")
	elseif kind == "sleep" then
		return sleep(r, now)
	elseif kind == "wake" then
		if r.sleeping then
			applyFace(r, DEFAULT_FACE, nil)
			return true
		end
		return false
	elseif kind == "hearts" then
		local handle = handleOf(r.slot, r.uid)
		if handle then
			emit(r, handle, PINK, 3, now)
			return true
		end
	end
	return false
end

-- =============================================================================================
-- Pose (RanchRenderer.stepSquishy) et oubli
-- =============================================================================================

local wire: () -> ()
local ensureStep: () -> ()

function Personality.pose(
	d: any,
	h: SquishyBuilder.Handle,
	pub: Types.PublicSquishy,
	where: string,
	base: Vector3,
	cf: CFrame,
	now: number
): CFrame
	if not on or type(d) ~= "table" then
		return cf
	end
	local slot, uid = d.slot, d.uid
	if type(slot) ~= "number" or type(uid) ~= "string" then
		return cf
	end
	if not wired then
		wire()
	end
	local list = recs[slot]
	local r = if list then list[uid] else nil
	if r == nil then
		r = newRec(slot, uid, pub, now)
	end
	local p = cf.Position
	r.seenAt = now
	r.where = where
	r.lod = if type(d.lod) == "number" then d.lod else 3
	r.dia = BASE_D * (if type(d.scale) == "number" then d.scale else 1)
	r.pressed = d.profile ~= nil
	r.px, r.py, r.pz = p.X, p.Y, p.Z
	r.bx, r.bz = base.X, base.Z
	local cx, cy, cz = p.X - camX, p.Y - camY, p.Z - camZ
	r.camDist = math.sqrt(cx * cx + cy * cy + cz * cz)
	if stepConn == nil then
		ensureStep()
	end

	local dx, dy, dz, yaw, pitch, roll, pivot = 0, 0, 0, 0, 0, 0, 0
	local moved = false
	local id = r.scene
	if id ~= nil then
		local tSlot, tUid = target()
		if
			r.pressed
			or where ~= "pen"
			or blockedAll
			or prestige[slot] == true
			or (tSlot == slot and tUid == uid)
		then
			-- pression, ciblage, portage, spectacle : la saynète s'arrête à cette image
			endScene(r, now, true, h)
		else
			local t = now - r.sceneAt
			if t >= r.sceneDur or t < 0 then
				endScene(r, now, false, h)
			else
				local lv = cf.LookVector
				local rest = math.atan2(-lv.X, -lv.Z)
				sceneCtx.reduced = reducedMo
				sceneCtx.home = r.homeW - rest
				sceneCtx.look = if r.lookOn then math.atan2(p.X - r.lookX, p.Z - r.lookZ) - rest else 0
				dx, dy, dz, yaw, pitch, roll, pivot = Scenes.sample(id, t, r.dia, sceneCtx)
				sceneTick(r, id, t, h, now)
				moved = true
			end
		end
	end
	if not moved and where == "pen" and not r.pressed then
		-- bond et regard d'une réaction (jamais pendant une saynète, jamais pour la cible du jeu)
		local ht = now - r.hopAt
		local hopping = ht >= 0 and ht < r.hopDur
		local turning = now < r.turnUntil and now >= r.turnAt
		if hopping or turning then
			local tSlot, tUid = target()
			if not (tSlot == slot and tUid == uid) then
				if hopping then
					dy = r.hopH * arc(ht / r.hopDur)
					moved = true
				end
				if turning then
					local lv = cf.LookVector
					local rest = math.atan2(-lv.X, -lv.Z)
					local e = plateau(now - r.turnAt, r.turnUntil - r.turnAt, 0.25, 0.3)
					local a = (math.atan2(p.X - r.turnX, p.Z - r.turnZ) - rest) % (2 * math.pi)
					if a > math.pi then
						a -= 2 * math.pi
					end
					if reducedMo then
						a = math.clamp(a, -Scenes.MAX_REDUCED_ANGLE, Scenes.MAX_REDUCED_ANGLE)
					end
					yaw = a * e
					pitch = r.turnTilt * e * (if reducedMo then 0.5 else 1)
					moved = true
				end
			end
		end
	end
	if not moved then
		return cf
	end
	return compose(cf, base, h.body.Size.Y * 0.5, dx, dy, dz, yaw, pitch, roll, pivot)
end

-- Le modèle de ce squishy est rendu à la réserve (il y repart avec « happy », sans rien de ce module)
function Personality.forget(slot: number, uid: string)
	local list = recs[slot]
	local r = if list then list[uid] else nil
	if r == nil then
		return
	end
	r.gone = true
	if r.scene ~= nil then
		r.scene = nil
		running = math.max(0, running - 1)
		counters.cut += 1
	end
	if r.sleeping then
		r.sleeping = false
		sleepers = math.max(0, sleepers - 1)
	end
	faced[r] = nil
	releaseLabel(r)
	for _, entry in fx do
		if entry.rec == r then
			freeFx(entry)
		end
	end
	(list :: { [string]: Rec })[uid] = nil
	recCount = math.max(0, recCount - 1)
	if next(list :: { [string]: Rec }) == nil then
		recs[slot] = nil
	end
end

-- =============================================================================================
-- Tours appris de MES espèces : annonce
-- =============================================================================================

local function say(text: string)
	local custom = sources.toast
	if custom then
		pcall(custom, text)
		return
	end
	local ok, toast = pcall(function(): any
		return require(Client.UI.Toast) :: any
	end)
	if ok and type(toast) == "table" and type(toast.message) == "function" then
		pcall(toast.message, text, "reward")
	end
end

local function playSound(name: string)
	local custom = sources.play
	if custom then
		pcall(custom, name)
		return
	end
	Util.safe("AudioController.play", nil, AudioController.play, name)
end

-- Relit les records de MON Étagère : un tour gagné depuis la dernière lecture est annoncé (une fois par
-- séance et par espèce et tour) ; la première lecture ne fait qu'armer (jamais d'annonce au chargement).
-- Une espèce dont le record APPARAÎT après l'armement déjà au-dessus d'un seuil annonce son plus beau
-- tour, une fois (lot I, étape 5, décision D23 du plan I ; constat B5-69 d).
local function scanTrophies()
	local list = StateController.get("trophies")
	if type(list) ~= "table" then
		return
	end
	local told = 0
	for species, size in list do
		if type(species) == "number" then
			local level = levelOf(size)
			local before = known[species]
			known[species] = level
			if armed and level > (before or 0) and Species.ById[species] ~= nil then
				local key = species * 8 + level
				if not announced[key] and told < ANNOUNCE_MAX then
					announced[key] = true
					told += 1
					counters.announced += 1
					Personality.TrickLearned:Fire(species, TRICK_IDS[level])
					say(Util.t("trick.new", { name = Util.t(TRICK_KEYS[level]) }))
					local def: any = (Sounds :: any).TrickPop
					local hasSound = type(def) == "table" and type(def.id) == "string" and def.id ~= ""
					playSound(if hasSound then "TrickPop" else "Pop")
				end
			end
		end
	end
	armed = true
end

-- =============================================================================================
-- Prairie des copains
-- =============================================================================================

local function meadowFolder(): Folder
	local f = meadow.folder
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
	local folder = Instance.new("Folder")
	folder.Name = "Meadow"
	folder.Parent = root
	meadow.folder = folder
	return folder
end

local function releaseMeadow()
	for _, m in meadow.models do
		pcall(SquishyBuilder.release, m.handle)
	end
	table.clear(meadow.models)
end

-- Les 12 derniers relâchés lisibles de MON profil (le plus récent à la fin)
local function refreshWanted()
	local wanted = meadow.wanted
	local released = StateController.get("released")
	local list: { { s: number, m: number } } = {}
	if type(released) == "table" then
		for i = math.max(1, #released - MEADOW_KEEP + 1), #released do
			local e = released[i]
			if type(e) == "table" and type(e.s) == "number" and Species.ById[e.s] ~= nil then
				table.insert(list, { s = e.s, m = if type(e.m) == "number" then e.m else 0 })
			end
		end
	end
	local same = #list == #wanted
	if same then
		for i, e in list do
			if wanted[i].s ~= e.s or wanted[i].m ~= e.m then
				same = false
				break
			end
		end
	end
	if not same then
		releaseMeadow()
		meadow.wanted = list
	end
end

local function buildMeadow(i: number)
	local w = meadow.wanted[i]
	local ok, handle = pcall(SquishyBuilder.build, {
		species = w.s,
		mutation = w.m,
		stars = 0,
		displayScale = 1,
		lod = MEADOW_LOD,
	}, meadowFolder())
	if not ok or type(handle) ~= "table" then
		-- construction impossible : la liste est raccourcie (aucun nouvel essai par image)
		table.remove(meadow.wanted, i)
		return
	end
	pcall(SquishyBuilder.setParticles, handle, 0)
	local p = WorldLayout.meadowPoint(i, meadow.v2)
	local def = Species.ById[w.s]
	meadow.models[i] = {
		handle = handle,
		x = p.X,
		z = p.Z,
		ground = WorldLayout.groundY(p.X, p.Z),
		offset = i * 0.37,
		hz = if def then def.wobble.hz else 2,
		amp = if def then def.wobble.amp else 0.1,
	}
end

-- Passe lente : liste, disposition (Prairie v2 tant que MON ranch porte Monuments), distance
local function meadowSlow()
	if meadow.dirty then
		meadow.dirty = false
		refreshWanted()
	end
	local mine = if mySlot > 0 then ranchInstance(mySlot) else nil
	local v2 = mine ~= nil and mine:GetAttribute("Monuments") ~= nil
	if v2 ~= meadow.v2 then
		meadow.v2 = v2
		releaseMeadow()
	end
	if #meadow.wanted == 0 then
		meadow.near = false
		return
	end
	local c = WorldLayout.meadowCenter(v2)
	local dx, dz = camX - c.X, camZ - c.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	if meadow.near then
		if dist > MEADOW_FAR then
			meadow.near = false
			releaseMeadow()
		end
	elseif dist <= MEADOW_NEAR then
		meadow.near = true
	end
end

-- Une image : un modèle construit au plus, rebond de repos à 15 Hz, un seul BulkMoveTo
local function meadowStep(dt: number, now: number)
	local models = meadow.models
	if meadow.near and #models < #meadow.wanted then
		buildMeadow(#models + 1)
		meadow.acc = math.huge -- première pose tout de suite
	end
	if #models == 0 then
		return
	end
	meadow.acc += dt
	if meadow.acc < 1 / MEADOW_HZ then
		return
	end
	meadow.acc = 0
	local parts, cframes = meadow.parts, meadow.cframes
	table.clear(parts)
	table.clear(cframes)
	local k = if reducedMo then 0.5 else 1
	for _, m in models do
		local ok, sx, sy, sz, bounce = pcall(Squash.idle, now, m.offset, m.hz, m.amp * k)
		if not ok then
			sx, sy, sz, bounce = 1, 1, 1, 0
		end
		pcall(SquishyBuilder.setSquash, m.handle, sx, sy, sz)
		pcall(SquishyBuilder.animate, m.handle, now, reducedMo)
		local y = m.ground + BASE_D * 0.5 + (bounce :: number) * BASE_D
		local pos = Vector3.new(m.x, y, m.z)
		local lx, lz = camX - m.x, camZ - m.z
		local cf = if lx * lx + lz * lz > 0.01
			then CFrame.lookAt(pos, Vector3.new(camX, y, camZ))
			else CFrame.new(pos)
		local posed, list, frames = pcall(SquishyBuilder.pose, m.handle, cf)
		if posed and type(list) == "table" and type(frames) == "table" then
			for i, part in list do
				local c = frames[i]
				if c then
					table.insert(parts, part)
					table.insert(cframes, c)
				end
			end
		end
	end
	if #parts > 0 then
		local ok, err =
			pcall(workspace.BulkMoveTo, workspace, parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		if not ok then
			Util.raise("Personality.meadow", tostring(err))
		end
	end
end

-- =============================================================================================
-- Présence du joueur : immobile 60 s, retour dans son ranch après 60 s dehors
-- =============================================================================================

local function wakeAll()
	idleEpoch += 1
	if sleepers <= 0 then
		return
	end
	for r in faced do
		if r.sleeping then
			applyFace(r, DEFAULT_FACE, nil)
			r.sceneFace = ""
		end
	end
end

local function bestFriend(slot: number): Rec?
	local view: any =
		Util.safe("WorldStateController.squishiesView", EMPTY, WorldStateController.squishiesView, slot)
	local best, bestRank = nil, math.huge
	for uid, pub in view do
		if type(pub) == "table" and type(pub.bf) == "number" and pub.bf >= 1 and pub.bf < bestRank then
			local r = recOf(slot, uid)
			if r then
				best, bestRank = r, pub.bf
			end
		end
	end
	return best
end

local function presence(now: number)
	local root = Util.localRoot()
	if root == nil then
		return
	end
	local p = root.Position
	local before = lastPos
	if photoOn() then
		-- relecture B5 (journal B5-62) : en mode photo le personnage ne bouge pas (sticks pris par la
		-- caméra) mais le joueur joue : jamais « immobile », l'attente de 60 s repart de la sortie
		lastPos = p
		lastMoveAt = now
	elseif before == nil or (p - before).Magnitude > MOVE_EPS or now < lastMoveAt then
		lastPos = p
		lastMoveAt = now
		wakeAll()
	elseif now - lastMoveAt >= IDLE_AFTER then
		-- immobile depuis 60 s : ceux à 15 studs s'endorment
		for _, list in recs do
			for _, r in list do
				if not r.sleeping and (r.where == "pen" or r.where == "pool") and reachable(r, now) then
					local dx, dz = r.px - p.X, r.pz - p.Z
					if dx * dx + dz * dz <= SLEEP_RADIUS * SLEEP_RADIUS and sleep(r, now) then
						counters.reactions += 1
					end
				end
			end
		end
	end
	if mySlot > 0 then
		local inside = WorldLayout.inRanch(mySlot, p)
		if inside then
			local last = lastInsideAt
			if last ~= nil and last ~= math.huge and now - last >= AWAY_AFTER then
				welcomeUntil = now + WELCOME_WAIT
			end
			lastInsideAt = now
			if now < welcomeUntil then
				-- le Meilleur Ami accueille le joueur dès qu'il est dessiné : Ravi et 3 cœurs
				local friend = bestFriend(mySlot)
				if friend and reachable(friend, now) then
					welcomeUntil = -math.huge
					counters.reactions += 1
					timedFace(friend, "delighted", 3, now, "react")
					reactOne(friend, "hearts", nil, nil, false, now)
				end
			end
		end
		wasInside = inside
	end
end

-- =============================================================================================
-- Signaux (branchés seulement tant que l'interrupteur est ouvert)
-- =============================================================================================

local function slotOfUser(userId: any): number
	if type(userId) ~= "number" or userId == 0 then
		return 0
	end
	for slot = 1, RANCHES do
		local ranch = WorldStateController.ranch(slot)
		if ranch and ranch.userId == userId then
			return slot
		end
	end
	return 0
end

-- Grand spectacle en cours (EventState.spectacle) : aucune saynète
local function readShow(ev: any, now: number)
	local spectacle = if type(ev) == "table" then ev.spectacle else nil
	local current = if type(spectacle) == "table" then spectacle.current else nil
	local kind = if type(current) == "table" then current.kind else nil
	if kind == "splorch" or kind == "dance" or kind == "ascend" then
		local ends = (current :: any).endsAt
		showOn = true
		showUntil = if finite(ends) then math.min(ends + 0.5, now + SHOW_CAP) else now + SHOW_CAP
	else
		showOn = false
	end
	blockedAll = showOn and now <= showUntil
end

-- EventState : fronts du Rush, du MEGA et de la Jelly Moon (la première lecture ne fait qu'armer)
local function readEvent(arm: boolean)
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) ~= "table" then
		return
	end
	local now = Clock.now()
	readShow(ev, now)
	local rush = type(ev.rush) == "table" and ev.rush.active == true
	local mega = if type(ev.mega) == "table" and type(ev.mega.phase) == "string"
		then ev.mega.phase
		else "idle"
	local moon = type(ev.moon) == "table" and ev.moon.active == true
	if not arm then
		if rush and not prevRush then
			-- sirène du Rush : Surpris
			counters.reactions += 1
			Personality.react(0, "surprise", nil)
		end
		if mega == "press" and prevMega ~= "press" then
			-- le MEGA atterrit : Surpris pour ceux à 120 studs ou moins du point de chute
			local pad = WorldLayout.plaza("megaPad")
			counters.reactions += 1
			for _, list in recs do
				for _, r in list do
					local dx, dz = r.px - pad.X, r.pz - pad.Z
					if reachable(r, now) and dx * dx + dz * dz <= MEGA_RADIUS * MEGA_RADIUS then
						timedFace(r, "surprised", 3, now, "react")
					end
				end
			end
		end
		if moon and not prevMoon then
			-- début de la Jelly Moon : Étoilé, ils regardent le ciel au-dessus de la place
			counters.reactions += 1
			table.clear(reactOpts)
			reactOpts.at = WorldLayout.plaza("center")
			reactOpts.up = true
			reactOpts.seconds = 6
			Personality.react(0, "starry", reactOpts)
		end
	end
	prevRush, prevMega, prevMoon = rush, mega, moon
end

local function onEvent()
	readEvent(false)
end

local function onCelebrate(payload: any)
	if type(payload) ~= "table" or type(payload.data) ~= "table" then
		return
	end
	local kind, d = payload.kind, payload.data
	if kind == "tile" then
		-- achat d'une dalle de MON ranch : tous se tournent vers elle, Ravi, petit saut
		local slot = Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
		local def = if type(d.tile) == "string" then (Pads.Defs :: any)[d.tile] else nil
		if slot > 0 and def then
			table.clear(reactOpts)
			reactOpts.at = WorldLayout.padSocket(slot, def.socket)
			Personality.react(slot, "build", reactOpts)
		end
	elseif kind == "press" then
		-- série PERFECT au plus haut : Ravi
		if d.perfect == true and type(d.streak) == "number" and d.streak >= Balance.Press.StreakMax then
			local slot = Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
			if d.petsit == true and type(d.uid) == "string" then
				slot = 0
				for s, list in recs do
					if list[d.uid] ~= nil then
						slot = s
						break
					end
				end
			end
			if slot > 0 then
				counters.reactions += 1
				table.clear(reactOpts)
				reactOpts.seconds = 2
				Personality.react(slot, "delight", reactOpts)
			end
		end
	elseif kind == "splorch" then
		-- Grand Splorch d'un autre : Étoilé, ils regardent la place
		local me = Util.localPlayer()
		if me ~= nil and finite(d.userId) and d.userId ~= me.UserId and finite(d.endsAt) then
			local left = d.endsAt - Clock.now()
			if left > 0 then
				counters.reactions += 1
				table.clear(reactOpts)
				reactOpts.at = WorldLayout.plaza("center")
				reactOpts.seconds = math.clamp(left, 1, 12)
				Personality.react(0, "starry", reactOpts)
			end
		end
	end
end

-- « Bravo » (croix ←) d'un propriétaire : le Meilleur Ami n° 1 de son ranch joue son plus beau tour
local function onEmote(payload: any)
	if type(payload) ~= "table" or payload.kind ~= 3 then
		return
	end
	local slot = slotOfUser(payload.userId)
	if slot == 0 then
		return
	end
	local friend = bestFriend(slot)
	if friend then
		wantTrick(friend, Clock.now())
	end
end

local function onState(key: any)
	if key == "trophies" then
		scanTrophies()
	elseif key == "released" then
		meadow.dirty = true
		if stepConn == nil then
			ensureStep()
		end
	end
end

-- Vermicelles d'une cascade : 12 par construction, 24 pour un achat groupé, répartis sur ses pièces
local function onPiece(slot: any, position: any, index: any)
	if not validSlot(slot) or typeof(position) ~= "Vector3" then
		return
	end
	local now = Clock.now()
	local sp = sprinkle
	if sp.left <= 0 or now - sp.at > CASCADE_GAP or now < sp.at then
		local ok, jobs, total = pcall(BuildCascade.playing)
		local grouped = ok and type(jobs) == "number" and jobs >= 2
		sp.budget = if grouped then SPRINKLES_GROUP else SPRINKLES
		sp.total = if ok and type(total) == "number" and total >= 1 then total else 1
		sp.seen, sp.sent = 0, 0
		sp.left = sp.total
	end
	sp.at = now
	sp.seen += 1
	sp.left -= 1
	local due = math.floor(sp.budget * math.min(sp.seen, sp.total) / sp.total)
	local n = due - sp.sent
	if n >= SPRINKLE_CHUNK or (sp.left <= 0 and n > 0) then
		sp.sent = due
		sp.hue = (sp.hue + 0.381966) % 1
		counters.sprinkles += n
		local where = position + Vector3.new(0, 1, 0)
		local color = Color3.fromHSV(sp.hue, 0.5, 1)
		local custom = sources.burst
		if custom then
			pcall(custom, where, color, n)
		else
			local ok, vfx = pcall(function(): any
				return require(Client.Controllers.VFXController) :: any
			end)
			if ok and type(vfx) == "table" and type(vfx.burst) == "function" then
				pcall(vfx.burst, where, color, n)
			end
		end
	end
	if index == 1 then
		table.clear(reactOpts)
		reactOpts.at = position
		Personality.react(slot, "build", reactOpts)
	end
end

-- Un élément v2.0 vient d'être construit pour de vrai : les squishies du ranch se tournent vers lui
local function onElement(slot: any, id: any)
	if not validSlot(slot) or type(id) ~= "string" then
		return
	end
	local rr = renderer()
	if rr == nil or type(rr.elementCFrame) ~= "function" then
		return
	end
	local ok, cf = pcall(rr.elementCFrame, slot, id)
	if ok and typeof(cf) == "CFrame" then
		table.clear(reactOpts)
		reactOpts.at = cf.Position
		Personality.react(slot, "build", reactOpts)
	end
end

-- =============================================================================================
-- Boucle par image (branchée seulement tant qu'il y a quelque chose à faire vivre)
-- =============================================================================================

local function hasWork(): boolean
	return recCount > 0
		or #meadow.models > 0
		or #meadow.wanted > 0
		or meadow.dirty
		or fxLive > 0
		or #labelRecs > 0
end

local function stopStep()
	local c = stepConn
	if c then
		stepConn = nil
		c:Disconnect()
	end
	-- la présence n'est plus suivie : au retour, « dedans » repart de zéro si le joueur y était
	if wasInside and lastInsideAt ~= nil then
		lastInsideAt = math.huge
	end
	lastPos = nil
end

-- Passe lente (1 Hz) : qualité, détail des ranchs, présence, Prairie, départs des saynètes
local function slow(now: number)
	mySlot = Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
	local low = Util.safe("Prefs.lowGraphics", false, Prefs.lowGraphics)
	local reduced = low or Util.safe("QualityController.reduced", false, QualityController.reduced)
	cap = if reduced then CAP_REDUCED else CAP
	reducedMo = Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
	local budgets: any = Util.safe("QualityController.budgets", nil, QualityController.budgets)
	particleFactor = if low
		then 0.3
		else Util.num(if type(budgets) == "table" then budgets.particles else 1, 1, 0, 1)
	blockedAll = showOn and now <= showUntil
	local rr = renderer()
	for slot in recs do
		local full = false
		if rr ~= nil and type(rr.detail) == "function" then
			local ok, level = pcall(rr.detail, slot)
			full = ok and level == "full"
		end
		detailFull[slot] = full
		local model = ranchInstance(slot)
		local at = if model then model:GetAttribute("PetitSplorchAt") else nil
		prestige[slot] = type(at) == "number" and now - at >= -1 and now - at < PRESTIGE_BLOCK
	end
	presence(now)
	meadowSlow()
	schedule(now)
	if #wanting > 0 then
		serveWanting(now)
	end
	if not hasWork() then
		stopStep()
	end
end

-- Une image (exposé aux specs ; appelé par RenderStepped)
function Personality._step(dt: number)
	if not on then
		return
	end
	local now = Clock.now()
	local cam = workspace.CurrentCamera
	if cam then
		local p = cam.CFrame.Position
		camX, camY, camZ = p.X, p.Y, p.Z
	end
	if next(faced) ~= nil then
		expireFaces(now)
	end
	if fxLive > 0 then
		expireFx(now)
	end
	if #labelRecs > 0 then
		expireLabels(now)
	end
	if sleepers > 0 then
		-- le joueur bouge : tout le monde se réveille à l'image même
		local root = Util.localRoot()
		local before = lastPos
		if root and before and (root.Position - before).Magnitude > MOVE_EPS then
			lastPos = root.Position
			lastMoveAt = now
			wakeAll()
		end
	end
	local d = Util.num(dt, 0, 0, 1)
	meadowStep(d, now)
	slowAcc += d
	if slowAcc >= SLOW then
		slowAcc = 0
		slow(now)
	end
end

ensureStep = function()
	if stepConn ~= nil or not on or not wired or not hasWork() then
		return
	end
	slowAcc = SLOW -- première passe lente dès la première image
	stepConn = RunService.RenderStepped:Connect(function(dt: number)
		Util.guard("Personality.step", Personality._step, dt)
	end)
end

-- Branche les signaux à l'ouverture de l'interrupteur (dès que RanchRenderer est chargé)
wire = function()
	if wired or not on then
		return
	end
	local rr = renderer()
	if rr == nil then
		return
	end
	wired = true
	VisualBudget.declare(SYSTEM, LIFE_LIMITS)
	local now = Clock.now()
	mySlot = Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
	reducedMo = Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
	armed = false
	table.clear(known)
	lastPos = nil
	lastMoveAt = now
	lastInsideAt = nil
	wasInside = false
	welcomeUntil = -math.huge
	meadow.dirty = true
	readEvent(true)
	scanTrophies()
	local function connect(signal: any, fn: (...any) -> (), where: string)
		if signal ~= nil then
			table.insert(
				conns,
				signal:Connect(function(...)
					Util.guard(where, fn, ...)
				end)
			)
		end
	end
	connect(WorldStateController.EventChanged, onEvent, "Personality.event")
	connect(WorldStateController.EmoteShown, onEmote, "Personality.emote")
	connect(StateController.Changed, onState, "Personality.state")
	connect(BuildCascade.Piece, onPiece, "Personality.piece")
	connect(rr.ElementBuilt, onElement, "Personality.element")
	local remote = Util.remote("Celebrate")
	if remote then
		connect(remote.OnClientEvent, onCelebrate, "Personality.celebrate")
	end
	ensureStep()
end

-- Coupure de l'interrupteur : tout ce que ce module a posé est rendu
local function shutdown()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	local c = stepConn
	if c then
		stepConn = nil
		c:Disconnect()
	end
	wired = false
	for slot, list in recs do
		for uid, r in list do
			r.gone = true
			if r.face ~= DEFAULT_FACE then
				local handle = handleOf(slot, uid)
				if handle then
					pcall(SquishyBuilder.setFace, handle, DEFAULT_FACE)
				end
			end
			releaseLabel(r)
		end
	end
	table.clear(recs)
	recCount = 0
	running = 0
	sleepers = 0
	table.clear(faced)
	table.clear(cand)
	table.clear(wanting)
	table.clear(labelRecs)
	for _, entry in fx do
		freeFx(entry)
		entry.att:Destroy()
	end
	table.clear(fx)
	fxLive = 0
	releaseMeadow()
	table.clear(meadow.wanted)
	meadow.near = false
	meadow.dirty = true
	local folder = meadow.folder
	if folder then
		meadow.folder = nil
		folder:Destroy()
	end
	table.clear(detailFull)
	table.clear(prestige)
	table.clear(lastBuild)
	table.clear(builtX)
	table.clear(builtZ)
	showOn, blockedAll = false, false
	sprinkle.left = 0
	welcomeUntil = -math.huge
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Vrai tant que l'interrupteur Personalities est ouvert sur le serveur
function Personality.active(): boolean
	return on
end

-- Pose un visage sur le squishy dessiné, pour `seconds` secondes (60 au plus) ; vrai s'il est posé
function Personality.setFace(slot: number, uid: string, face: string, seconds: number?): boolean
	if not on or type(slot) ~= "number" or type(uid) ~= "string" or type(face) ~= "string" then
		return false
	end
	if table.find(SquishyBuilder.FACES, face) == nil then
		return false
	end
	if not wired then
		wire()
	end
	if handleOf(slot, uid) == nil then
		return false
	end
	local now = Clock.now()
	local r = recOf(slot, uid) or newRec(slot, uid, nil, now)
	if face == DEFAULT_FACE then
		return applyFace(r, DEFAULT_FACE, nil)
	end
	local ok = timedFace(r, face, if finite(seconds) then seconds :: number else FACE_CAP, now, "api")
	if ok and stepConn == nil then
		ensureStep()
	end
	return ok
end

-- Visage posé par ce module sur ce squishy (« happy » sinon)
function Personality.faceOf(slot: number, uid: string): string
	local r = if type(slot) == "number" and type(uid) == "string" then recOf(slot, uid) else nil
	return if r then r.face else DEFAULT_FACE
end

-- Saynète ou tour en cours de ce squishy (nil sinon)
function Personality.sceneOf(slot: number, uid: string): string?
	local r = if type(slot) == "number" and type(uid) == "string" then recOf(slot, uid) else nil
	return if r then r.scene else nil
end

-- La ola (palier du ranch) : un bond par squishy de l'enclos, colonne par colonne
function Personality.wave(slot: number): number
	if not on or not validSlot(slot) then
		return 0
	end
	local list = recs[slot]
	if list == nil then
		return 0
	end
	local now = Clock.now()
	local n = 0
	for _, r in list do
		if r.where == "pen" and reachable(r, now) then
			local lx = WorldLayout.toLocal(slot, Vector3.new(r.bx, 0, r.bz)).X
			hop(r, clamp01((lx + PEN_HALF) / (2 * PEN_HALF)) * WAVE_SPREAD, 0.45, 0.5 * r.dia, now)
			n += 1
		end
	end
	return n
end

-- Réaction des squishies dessinés d'un ranch (0 : tous les ranchs) ; rend le nombre de squishies touchés
function Personality.react(slot: number, kind: string, opts: any?): number
	if not on or type(slot) ~= "number" or type(kind) ~= "string" then
		return 0
	end
	if slot ~= 0 and not validSlot(slot) then
		return 0
	end
	local o: any = if type(opts) == "table" then opts else EMPTY
	local at: Vector3? = if typeof(o.at) == "Vector3" then o.at else nil
	local seconds: number? = if finite(o.seconds) then math.clamp(o.seconds, 0.1, FACE_CAP) else nil
	local only: string? = if type(o.uid) == "string" then o.uid else nil
	local up = o.up == true
	local now = Clock.now()
	if kind == "build" then
		if slot == 0 then
			return 0
		end
		if at then
			builtX[slot], builtZ[slot] = at.X, at.Z
		end
		local last = lastBuild[slot]
		if last ~= nil and now - last < BUILD_GAP and now >= last then
			return 0 -- une fois toutes les 2 s au plus
		end
		lastBuild[slot] = now
		counters.reactions += 1
	end
	local n = 0
	for s, list in recs do
		if slot == 0 or s == slot then
			for uid, r in list do
				if (only == nil or only == uid) and reachable(r, now) then
					if reactOne(r, kind, at, seconds, up, now) then
						n += 1
					end
				end
			end
		end
	end
	return n
end

-- Compteurs (specs, Diagnostics)
function Personality.stats(): { [string]: number }
	return {
		records = recCount,
		running = running,
		cap = cap,
		faced = (function(): number
			local n = 0
			for _ in faced do
				n += 1
			end
			return n
		end)(),
		sleepers = sleepers,
		labels = #labelRecs,
		bursts = fxLive,
		attachments = #fx,
		particles = VisualBudget.used(SYSTEM, "particles"),
		meadow = #meadow.models,
		wanting = #wanting,
		connections = #conns + (if stepConn ~= nil then 1 else 0),
		stepping = if stepConn ~= nil then 1 else 0,
		started = counters.started,
		finished = counters.finished,
		cut = counters.cut,
		tricks = counters.tricks,
		reactions = counters.reactions,
		announced = counters.announced,
		sprinkles = counters.sprinkles,
	}
end

-- Specs : joue la saynète ou le tour `id` sur ce squishy dessiné, tout de suite (les règles d'arrêt
-- et la limite de saynètes en cours restent en vigueur ; ni l'horaire ni la distance ne comptent)
function Personality._play(slot: number, uid: string, id: string): boolean
	if not on or type(slot) ~= "number" or type(uid) ~= "string" or type(id) ~= "string" then
		return false
	end
	local r = recOf(slot, uid)
	local now = Clock.now()
	if r == nil or r.scene ~= nil or running >= cap or not free(r, now) then
		return false
	end
	local tSlot, tUid = target()
	if tSlot == slot and tUid == uid then
		return false
	end
	return startScene(r, id, now)
end

-- Specs : sources remplacées (gerbe de vermicelles, message, son) ; nil rend celles du vrai client
function Personality._configure(options: any?)
	local o: any = if type(options) == "table" then options else EMPTY
	sources.burst = if type(o.burst) == "function" then o.burst else nil
	sources.toast = if type(o.toast) == "function" then o.toast else nil
	sources.play = if type(o.play) == "function" then o.play else nil
end

-- Une seule connexion pour la séance : l'interrupteur vu du client (World/Flags)
Flags.Changed:Connect(function()
	local now = Flags.on(FLAG)
	if now == on then
		return
	end
	on = now
	if on then
		wire()
	else
		shutdown()
	end
	Personality.Changed:Fire()
end)

return Personality
