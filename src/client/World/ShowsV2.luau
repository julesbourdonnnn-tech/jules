--!strict
-- ShowsV2 (lot B5, étape 4 ; GDD v2.0 §4.27 « Le moment, étape par étape », Petit Splorch, étapes du
-- record ; §9.4 lignes « Petit Splorch », « Jelly Ascend », « Pluie d'étoiles », « Palier » ; §11.5 un
-- seul grand spectacle à la fois ; §12.10 coupures dures ; plan B5 V1-V5, V9-V11, K9, K10, D17, D18,
-- D20) : les spectacles de la v2.0 dessinés par le client. VFXController reste le répartiteur de
-- Celebrate et le seul maître des budgets de particules (ses effets sont passés à start()).
--
--   ShowsV2.start(fx)          -- VFXController.Start : effets (burst, blobs, ring, stamp, floatText, flash)
--   ShowsV2.stop()             -- coupe tout, rend chaque instance (fin, specs)
--   ShowsV2.celebrate(kind, d) -- Celebrate v2.0 : petitSplorch, ascend, tier, recordStep, regainDone
--   ShowsV2.starRain(d)        -- vrai si ce giftRain est la Pluie d'étoiles de l'Ascension en cours
--   ShowsV2.paletteOf(slot)    -- 4 couleurs de la palette du spectacle du ranch, ou nil (couleurs v1.3)
--   ShowsV2.busy(slot?)        -- un spectacle de ShowsV2 vit (sur ce ranch)
--   ShowsV2.stats() / _state() / _configure(sources) / _step(dt)   -- specs, Diagnostics
--
-- Petit Splorch (D17) : piloté pour TOUS (propriétaire compris) par l'attribut PetitSplorchAt du dossier
-- du ranch (heure du serveur ; une écoute d'attribut par dossier de ranch, posées seulement tant que
-- l'interrupteur PetitSplorch est ouvert, aucune lecture par image) : 2,5 s, coupure dure à 4 s
-- d'images ; seulement pour un ranch en détail complet (RanchRenderer.detail) et hors d'un grand
-- spectacle. Une COPIE du squishy (le squishy public ranch.waiting, sinon ranch.best : le même pour le
-- propriétaire et ses voisins) saute (0-0,9 s), rétrécit (0,9-1,5 s) et disparaît dans un « pouf » ;
-- pluie de 30 confettis sur le ranch (palette). Celebrate("petitSplorch") donne au propriétaire seul
-- le petit texte « Plop est là ! ×2 ! » (clé splorch.show, nom réel, 32 px par UI/WorldText), SplorchPop
-- à la hauteur 1,2 et la vibration holdDone. Attribut plus vieux que 2,5 s, ranch en détail réduit : rien.
-- Jelly Ascend (V2) : Celebrate("ascend") à tous, interrupteur JellyAscend ouvert : 10 s, coupure dure à
-- Events.Spectacles.ascend.hardCut = 12 s d'images ; dessinée pour le héros et pour un ranch du héros en
-- détail complet (un client lointain ne crée rien mais retient le héros pour la Pluie d'étoiles) ; la
-- copie (taille copiée au départ, charge flyer) monte dans le faisceau jusqu'à l'élément de ciel
-- (World/AscendPath), éclat EXACTEMENT à burstAt (60 étincelles de la palette, anneau Neon), redescend
-- à sa NOUVELLE taille (Meilleur Ami n° 1 du miroir, bf = 1) et se pose à endsAt ; tampons « JELLY ASCEND
-- ★A » (ascend.stamp, étoile dessinée par UI/Text) puis ascend.show ; AscendCharge au début et
-- AscendBurst à burstAt (replis SplorchCharge, SplorchPop) ; héros seul : vibration ascend et éclair
-- blanc de 0,12 s (Juice.flash, jamais en Mouvement réduit). Aucune écriture de Lighting.
-- Pluie d'étoiles (V3) : giftRain dont heroId est le héros de l'Ascension en cours (jusqu'à endsAt +
-- 5 s, comme UI/Banners), short faux : 20 étincelles dorées sur la place en 3 s, son GiftRain ; le
-- texte « Pluie d'étoiles ! » est celui de UI/Banners (B3-54) : aucun second texte ici.
-- Étapes du record et retour au record (V4) : confettis sur MON ranch (30 ; 60 avec ConfettiGain,
-- repli Coin) ; les cartes sont celles du lot B3 : aucun texte ici.
-- Palier (V5, D20) : anneau Neon 0 → 40 studs en 0,6 s, 30 confettis, LevelUp, vibration tierUp, ola
-- par Personality.wave(slot) si les personnalités sont ouvertes ; 2,5 s ; aucun texte.
-- Palette (D18) : attribut Palette du ranch, « peachPalette » lu « peach » (jusqu'à l'étape I), nom
-- dans Visuals.Palettes ; absent ou inconnu : les couleurs de la v1.3 exactement.
-- Un seul grand spectacle à la fois (V11) : les moments locaux (Petit Splorch, Palier, étapes du
-- record) restent sans dessin pendant un Rush, un MEGA, un Grand Splorch, une Ascension ou la danse
-- (le son et la vibration du joueur restent : ils répondent à SON geste). Chaque état a sa coupure dure.
-- Interrupteurs coupés : aucune instance, aucune boucle par image, une seule écoute (Flags.Changed).
-- Système « shows » de Render/VisualBudget : 96 pièces (4 copies de squishy au plus).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Sounds = require(Shared.Config.Sounds)
local Species = require(Shared.Config.Species)
local Visuals = require(Shared.Config.Visuals)
local Formulas = require(Shared.Logic.Formulas)
local SizeScale = require(Shared.Logic.SizeScale)
local WorldLayout = require(Shared.Logic.WorldLayout)
local SquishyBuilder = require(Shared.Render.SquishyBuilder)

local Client = script.Parent.Parent
local Flags = require(Client.World.Flags)
local Util = require(Client.World.Util)
local AscendPath = require(Client.World.AscendPath)
local Personality = require(Client.World.Personality)
local Prefs = require(Client.Util.Prefs)
local Haptics = require(Client.Util.Haptics)
local AudioController = require(Client.Controllers.AudioController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local RanchRenderer = require(Client.Controllers.RanchRenderer)
local VisualBudget = require(Client.Render.VisualBudget)

local ShowsV2 = {}

-- Durées (GDD §9.4 ; contrat Balance.Ascend, Events.Spectacles)
local PETIT_TIME = Balance.SplorchV2.PetitShow.Duration -- 2,5 s
local PETIT_CUT = Balance.SplorchV2.PetitShow.HardCut -- 4 s
local ASCEND_CUT = Events.Spectacles.ascend.hardCut -- 12 s
local HOP_END = 0.9
local SHRINK_END = 1.5
local HOP_HEIGHT = 6
local PETIT_CONFETTI = 30
local PETIT_POUF = 10
local ASCEND_SPARKS = 60
local ASCEND_RING = 40
local SHOW_TEXT_AFTER = 2.5 -- s après l'éclat : « ×3 à chaque boucle ! »
local STAR_GRACE = 5 -- s après endsAt : héros retenu (comme UI/Banners, B3-54)
local STAR_TIME = 3
local STAR_SPARKS = 20
local STAR_WAVES = 5
local STAR_RADIUS = 20
local STAR_HEIGHT = 26
local TIER_TIME = 2.5
local TIER_RING = 40
local TIER_RING_TIME = 0.6
local TIER_CONFETTI = 30
local STEP_CONFETTI = 30
local REGAIN_CONFETTI = 60
local CONFETTI_HEIGHT = 12
local TEXT_SCALE = 0.8 -- × 40 px = 32 px (UI/WorldText)
local SHOW_CAP = 30 -- s : un grand spectacle du miroir compte ce temps-là au plus
local SYSTEM = "shows"
local LIMITS = table.freeze({ parts = 96, particles = 0, lights = 0 })
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 205, 60)
local PINK = Color3.fromRGB(255, 170, 210)
-- couleurs de la v1.3 (aucune palette) : confettis des moments de la v2.0
local DEFAULT_CONFETTI: { Color3 } = table.freeze({
	PINK,
	GOLD,
	Color3.fromRGB(150, 230, 200),
	Color3.fromRGB(150, 200, 255),
})

-- Palettes du spectacle (D18) : 4 couleurs par nom de Visuals.Palettes
local PALETTES: { [string]: { Color3 } } = {
	candy = table.freeze({
		Color3.fromRGB(255, 120, 180),
		Color3.fromRGB(255, 220, 90),
		Color3.fromRGB(120, 210, 255),
		Color3.fromRGB(255, 255, 255),
	}),
	mint = table.freeze({
		Color3.fromRGB(130, 235, 190),
		Color3.fromRGB(200, 255, 230),
		Color3.fromRGB(80, 200, 160),
		Color3.fromRGB(255, 255, 255),
	}),
	lavender = table.freeze({
		Color3.fromRGB(190, 160, 255),
		Color3.fromRGB(230, 210, 255),
		Color3.fromRGB(150, 120, 230),
		Color3.fromRGB(255, 220, 245),
	}),
	rainbow = table.freeze({
		Color3.fromRGB(255, 90, 90),
		Color3.fromRGB(255, 210, 70),
		Color3.fromRGB(90, 220, 120),
		Color3.fromRGB(90, 150, 255),
	}),
	softNight = table.freeze({
		Color3.fromRGB(70, 80, 160),
		Color3.fromRGB(140, 150, 230),
		Color3.fromRGB(255, 230, 150),
		Color3.fromRGB(200, 210, 255),
	}),
	icing = table.freeze({
		Color3.fromRGB(255, 250, 245),
		Color3.fromRGB(255, 200, 220),
		Color3.fromRGB(200, 235, 255),
		Color3.fromRGB(255, 235, 190),
	}),
	fireworks = table.freeze({
		Color3.fromRGB(255, 70, 70),
		Color3.fromRGB(255, 180, 40),
		Color3.fromRGB(80, 160, 255),
		Color3.fromRGB(255, 255, 255),
	}),
	peach = table.freeze({
		Color3.fromRGB(255, 190, 150),
		Color3.fromRGB(255, 160, 130),
		Color3.fromRGB(255, 225, 190),
		Color3.fromRGB(255, 140, 160),
	}),
}
-- noms de la semaine de Cosmetics (« peachPalette ») lus comme ceux de Visuals.Palettes jusqu'à I
local PALETTE_ALIAS: { [string]: string } = { peachPalette = "peach" }
local KNOWN_PALETTE: { [string]: boolean } = {}
for _, name in Visuals.Palettes do
	KNOWN_PALETTE[name] = true
end

export type Fx = {
	burst: (Vector3, Color3, number) -> (),
	ring: (Vector3, Color3, number, number) -> (),
	stamp: (string, { [string]: any }?, Color3?) -> (),
	floatText: (Vector3, string, Color3?, number?) -> (),
	flash: () -> (),
}

type Flyer = { s: number, m: number, st: number, size: number }

type Petit = {
	slot: number,
	userId: number,
	at: number,
	frames: number,
	handle: SquishyBuilder.Handle?,
	taken: number,
	base: Vector3,
	popped: boolean,
}

type Ascend = {
	slot: number,
	userId: number,
	hero: boolean,
	A: number,
	startedAt: number,
	burstAt: number,
	endsAt: number,
	frames: number,
	marks: { [string]: boolean },
	flyer: Flyer,
	upScale: number, -- displayScale de la taille copiée au départ
	newRatio: number?, -- nouvelle taille ÷ taille copiée (lue au premier instant après l'éclat)
	handle: SquishyBuilder.Handle?,
	taken: number,
}

type Rain = { frames: number, waves: number, rng: Random }

local fx: Fx? = nil
local started = false
local connections: { RBXScriptConnection } = {}
local attrConns: { [number]: RBXScriptConnection } = {}
local stepConn: RBXScriptConnection? = nil
local petits: { [number]: Petit } = {}
local ascend: Ascend? = nil
local heroMemo: { userId: number, untilT: number, rained: boolean }? = nil
local rain: Rain? = nil
local tierUntil = -math.huge
local declared = false

local counters = {
	petits = 0,
	petitTexts = 0,
	ascends = 0,
	ascendDrawn = 0,
	bursts = 0,
	starRains = 0,
	tiers = 0,
	recordSteps = 0,
	regains = 0,
	cut = 0,
	refused = 0,
	quiet = 0,
}

-- Sources remplaçables par les specs
local sources: {
	play: ((string, number?) -> ())?,
	haptic: ((string) -> ())?,
	flash: (() -> ())?,
} = {}

-- =============================================================================================
-- Outils
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function mySlot(): number
	return Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
end

local function myUserId(): number
	local me = Players.LocalPlayer
	return if me then me.UserId else 0
end

local function reducedMotion(): boolean
	return Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
end

-- Son de la v2.0 avec son repli (identifiant vide : le repli, K9) ; sons de la v1.3 : tels quels
local function playSound(name: string, fallback: string?, pitch: number?)
	local def: any = (Sounds :: any)[name]
	local key = name
	if fallback and not (type(def) == "table" and type(def.id) == "string" and def.id ~= "") then
		key = fallback
	end
	local fn = sources.play
	if fn then
		pcall(fn, key, pitch)
		return
	end
	Util.safe("AudioController.play", nil, AudioController.play, key, nil, pitch)
end

local function haptic(name: string)
	local fn = sources.haptic
	if fn then
		pcall(fn, name)
		return
	end
	Util.safe("Haptics.play", false, Haptics.play, name)
end

local function flash()
	if reducedMotion() then
		return
	end
	local fn = sources.flash
	if fn then
		pcall(fn)
		return
	end
	local f = fx
	if f then
		pcall(f.flash)
	end
end

local function ranchModel(slot: number): Instance?
	local root = workspace:FindFirstChild("Wobbleton")
	local list = root and root:FindFirstChild("Ranches")
	return list and list:FindFirstChild(tostring(slot))
end

local function validSlot(slot: any): boolean
	return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= WorldLayout.Const.Ranches
end

local function slotOf(userId: number): number
	if userId <= 0 then
		return 0
	end
	for s = 1, WorldLayout.Const.Ranches do
		local r = WorldStateController.ranch(s)
		if r and r.userId == userId then
			return s
		end
	end
	return 0
end

local function fullDetail(slot: number): boolean
	return Util.safe("RanchRenderer.detail", "reduced", RanchRenderer.detail, slot) == "full"
end

local function center(slot: number, height: number): Vector3
	local c = WorldLayout.toWorld(slot, Vector3.new(0, 0, 36))
	return Vector3.new(c.X, WorldLayout.groundY(c.X, c.Z) + height, c.Z)
end

-- Grand spectacle du miroir en cours : Rush, MEGA, Grand Splorch, Ascension, danse de la jauge
local function bigShow(): boolean
	local ev: any = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) ~= "table" then
		return false
	end
	if type(ev.rush) == "table" and ev.rush.active == true then
		return true
	end
	if type(ev.mega) == "table" and type(ev.mega.phase) == "string" and ev.mega.phase ~= "idle" then
		return true
	end
	local spectacle = ev.spectacle
	local current = if type(spectacle) == "table" then spectacle.current else nil
	if type(current) == "table" then
		local kind = current.kind
		if kind == "splorch" or kind == "dance" or kind == "ascend" then
			local ends = current.endsAt
			local now = Clock.now()
			return not finite(ends) or now <= math.min(ends, now + SHOW_CAP)
		end
	end
	return false
end

-- Moments locaux sans dessin : un grand spectacle du miroir, ou une Ascension en cours ici
local function quiet(): boolean
	return ascend ~= nil or bigShow()
end

-- Palette du spectacle du ranch (D18) : 4 couleurs, ou nil (couleurs de la v1.3)
function ShowsV2.paletteOf(slot: number): { Color3 }?
	if not validSlot(slot) then
		return nil
	end
	local model = ranchModel(slot)
	if model == nil then
		return nil
	end
	local ok, raw = pcall(function()
		return model:GetAttribute("Palette")
	end)
	if not ok or type(raw) ~= "string" or raw == "" or #raw > 32 then
		return nil
	end
	local name = PALETTE_ALIAS[raw] or raw
	if not KNOWN_PALETTE[name] then
		return nil
	end
	return PALETTES[name]
end

-- Gerbe de confettis aux couleurs données, `count` en tout (VFXController.burst : quota des effets)
local function confetti(pos: Vector3, colors: { Color3 }, count: number)
	local f = fx
	if f == nil then
		return
	end
	local n = #colors
	local left = count
	for i = 1, n do
		local share = math.floor(left / (n - i + 1) + 0.5)
		left -= share
		if share > 0 then
			pcall(f.burst, pos, colors[i], share)
		end
	end
end

local function confettiOf(slot: number): { Color3 }
	return ShowsV2.paletteOf(slot) or DEFAULT_CONFETTI
end

-- Squishy public du ranch pour la copie du Petit Splorch : ranch.waiting, sinon ranch.best
local function petitFlyer(slot: number): Flyer?
	local r: any = WorldStateController.ranch(slot)
	if type(r) ~= "table" then
		return nil
	end
	local now = Clock.now()
	if type(r.waiting) == "string" and r.waiting ~= "" then
		local rec: any = WorldStateController.squishiesView(slot)[r.waiting]
		if type(rec) == "table" and Species.ById[rec.s] then
			local size =
				Util.safe("WorldStateController.sizeOf", 0, WorldStateController.sizeOf, slot, r.waiting, now)
			return {
				s = rec.s,
				m = Util.int(rec.m, 0, 255) or 0,
				st = Util.int(rec.st, 0, 5) or 0,
				size = Util.num(size, 1, 0),
			}
		end
	end
	local best = r.best
	if type(best) == "table" and Species.ById[best.s] then
		local ok, size = pcall(function()
			return Formulas.sizeAt(best :: any, Formulas.G(r.growth, now))
		end)
		return {
			s = best.s,
			m = Util.int(best.m, 0, 255) or 0,
			st = 0,
			size = if ok and finite(size) then math.max(0, size) else Util.num(best.z, 1, 0),
		}
	end
	return nil
end

-- Construit une copie de squishy (budget « shows ») ; nil si le budget ou le moteur refuse
local function buildCopy(flyer: Flyer, scale: number): (SquishyBuilder.Handle?, number)
	if not declared then
		declared = VisualBudget.declare(SYSTEM, LIMITS)
	end
	local spec = {
		species = flyer.s,
		mutation = flyer.m,
		stars = flyer.st,
		displayScale = scale,
		lod = 1,
	}
	local okc, need = pcall(SquishyBuilder.partCount, spec :: any)
	local n = if okc and type(need) == "number" then need else 24
	if not VisualBudget.take(SYSTEM, n) then
		counters.refused += 1
		return nil, 0
	end
	local folder = workspace:FindFirstChild("ClientWorld")
	local holder = folder and folder:FindFirstChild("VFX")
	local ok, h = pcall(SquishyBuilder.build, spec :: any, holder or workspace)
	if not ok or type(h) ~= "table" then
		VisualBudget.release(SYSTEM, n)
		return nil, 0
	end
	pcall(SquishyBuilder.setParticles, h, 0)
	return h, n
end

local function releaseCopy(h: SquishyBuilder.Handle?, taken: number)
	if h then
		pcall(SquishyBuilder.release, h)
	end
	if taken > 0 then
		VisualBudget.release(SYSTEM, taken)
	end
end

local function pose(h: SquishyBuilder.Handle, at: Vector3, scale: number)
	local s = math.max(0.01, scale)
	pcall(SquishyBuilder.setSquash, h, s, s, s)
	local ok, parts, cframes = pcall(SquishyBuilder.pose, h, CFrame.new(at))
	if ok and type(parts) == "table" then
		for i, part in parts do
			part.CFrame = cframes[i]
		end
	end
end

local refreshLoop: () -> ()

-- =============================================================================================
-- Petit Splorch (D17)
-- =============================================================================================

local function finishPetit(slot: number, cut: boolean)
	local p = petits[slot]
	if p == nil then
		return
	end
	petits[slot] = nil
	releaseCopy(p.handle, p.taken)
	p.handle = nil
	p.taken = 0
	if cut then
		counters.cut += 1
	end
end

local function onPetitAttr(slot: number)
	if not Flags.on("PetitSplorch") or petits[slot] ~= nil then
		return
	end
	local model = ranchModel(slot)
	local at = if model then model:GetAttribute("PetitSplorchAt") else nil
	if not finite(at) then
		return
	end
	local now = Clock.now()
	local age = now - (at :: number)
	if age < -1 or age >= PETIT_TIME then
		return
	end
	if not fullDetail(slot) then
		return
	end
	if quiet() then
		counters.quiet += 1
		return
	end
	local r = WorldStateController.ranch(slot)
	if r == nil or r.userId == 0 then
		return
	end
	local p: Petit = {
		slot = slot,
		userId = r.userId,
		at = at :: number,
		frames = math.max(0, age),
		handle = nil,
		taken = 0,
		base = center(slot, 0),
		popped = false,
	}
	local flyer = petitFlyer(slot)
	if flyer then
		local h, n = buildCopy(flyer, SizeScale.display(flyer.size, "pen"))
		p.handle = h
		p.taken = n
	end
	petits[slot] = p
	counters.petits += 1
	refreshLoop()
end

local function stepPetit(p: Petit, now: number, dt: number)
	p.frames += dt
	local t = now - p.at
	local r = WorldStateController.ranch(p.slot)
	local gone = r == nil or r.userId ~= p.userId
	if t >= PETIT_TIME or p.frames >= PETIT_CUT or gone or not fullDetail(p.slot) or bigShow() then
		finishPetit(p.slot, t < PETIT_TIME)
		return
	end
	local h = p.handle
	if not p.popped and t >= SHRINK_END then
		p.popped = true
		local top = p.base + Vector3.new(0, 2, 0)
		local f = fx
		if f then
			pcall(f.burst, top, WHITE, PETIT_POUF)
		end
		confetti(center(p.slot, CONFETTI_HEIGHT), confettiOf(p.slot), PETIT_CONFETTI)
		releaseCopy(h, p.taken)
		p.handle = nil
		p.taken = 0
		return
	end
	if h == nil or p.popped then
		return
	end
	local dia = Balance.SizeScale.BaseDiameter * h.spec.displayScale
	if t < HOP_END then
		local k = math.max(0, t) / HOP_END
		pose(h, p.base + Vector3.new(0, dia * 0.5 + HOP_HEIGHT * math.sin(math.pi * k), 0), 1)
	else
		local k = 1 - (t - HOP_END) / (SHRINK_END - HOP_END)
		pose(h, p.base + Vector3.new(0, dia * 0.5 * k + 1, 0), k)
	end
end

local function attachPetit()
	for slot = 1, WorldLayout.Const.Ranches do
		if attrConns[slot] == nil then
			local model = ranchModel(slot)
			if model then
				attrConns[slot] = model:GetAttributeChangedSignal("PetitSplorchAt"):Connect(function()
					Util.guard("ShowsV2.petit", onPetitAttr, slot)
				end)
			end
		end
	end
end

local function detachPetit()
	for slot, c in attrConns do
		c:Disconnect()
		attrConns[slot] = nil
	end
	for slot in petits do
		finishPetit(slot, true)
	end
end

-- Celebrate("petitSplorch") : le propriétaire seul (texte, son, vibration)
local function onPetitCelebrate(d: any)
	if not Flags.on("PetitSplorch") then
		return
	end
	if d.userId ~= myUserId() or myUserId() == 0 then
		return
	end
	if not (finite(d.startedAt) and finite(d.endsAt)) or d.endsAt - d.startedAt > PETIT_CUT then
		return
	end
	if d.endsAt < d.startedAt then
		return
	end
	local slot = mySlot()
	local flyer = if slot > 0 then petitFlyer(slot) else nil
	local root = Util.localRoot()
	local f = fx
	if root and f then
		local name = Util.speciesName(if flyer then flyer.s else Species.PLOP)
		pcall(
			f.floatText,
			root.Position + Vector3.new(0, 4, 0),
			Util.t("splorch.show", { name = name }),
			GOLD,
			TEXT_SCALE
		)
		counters.petitTexts += 1
	end
	playSound("SplorchPop", nil, 1.2)
	haptic("holdDone")
end

-- =============================================================================================
-- Jelly Ascend (V2)
-- =============================================================================================

local function finishAscend(cut: boolean)
	local a = ascend
	if a == nil then
		return
	end
	ascend = nil
	releaseCopy(a.handle, a.taken)
	a.handle = nil
	a.taken = 0
	if cut then
		counters.cut += 1
	end
end

-- Nouvelle taille du Meilleur Ami n° 1 (miroir, bf = 1, même espèce) ÷ taille copiée ; 1 sinon
local function newRatio(a: Ascend, now: number): number
	for uid, rec: any in WorldStateController.squishiesView(a.slot) do
		if type(rec) == "table" and rec.bf == 1 and rec.s == a.flyer.s then
			local size =
				Util.safe("WorldStateController.sizeOf", 0, WorldStateController.sizeOf, a.slot, uid, now)
			local scale = SizeScale.display(Util.num(size, 0, 0), "pen")
			if finite(scale) and scale > 0 and a.upScale > 0 then
				return math.clamp(scale / a.upScale, 0.05, 20)
			end
		end
	end
	return 1
end

local function onAscend(d: any)
	if not Flags.on("JellyAscend") then
		return
	end
	local startedAt, burstAt, endsAt = d.startedAt, d.burstAt, d.endsAt
	if not (finite(startedAt) and finite(burstAt) and finite(endsAt)) then
		return
	end
	if endsAt <= startedAt or endsAt - startedAt > ASCEND_CUT or burstAt < startedAt or burstAt > endsAt then
		return
	end
	local userId = Util.num(d.userId, 0, 0, 2 ^ 53)
	if userId <= 0 or userId % 1 ~= 0 then
		return
	end
	local slot = slotOf(userId)
	if slot == 0 then
		return
	end
	local now = Clock.now()
	if now >= endsAt then
		return
	end
	-- un seul grand spectacle : une nouvelle Ascension remplace l'ancienne (la file du serveur n'en
	-- montre qu'une ; une charge en double du même héros est ignorée)
	local cur = ascend
	if cur then
		if cur.userId == userId and cur.startedAt == startedAt then
			return
		end
		finishAscend(true)
	end
	heroMemo = { userId = userId, untilT = endsAt + STAR_GRACE, rained = false }
	local hero = userId == myUserId()
	local raw = if type(d.flyer) == "table" then d.flyer else {}
	local flyer: Flyer = {
		s = if Species.ById[raw.s] then raw.s else Species.PLOP,
		m = Util.int(raw.m, 0, 255) or 0,
		st = Util.int(raw.st, 0, 5) or 0,
		size = Util.num(raw.z, 1, 0),
	}
	local a: Ascend = {
		slot = slot,
		userId = userId,
		hero = hero,
		A = math.floor(Util.num(d.ascend, 1, 1, 999)),
		startedAt = startedAt,
		burstAt = burstAt,
		endsAt = endsAt,
		frames = math.max(0, now - startedAt),
		marks = {},
		flyer = flyer,
		upScale = SizeScale.display(flyer.size, "pen"),
		newRatio = nil,
		handle = nil,
		taken = 0,
	}
	ascend = a
	counters.ascends += 1
	if hero or fullDetail(slot) then
		local h, n = buildCopy(flyer, a.upScale)
		a.handle = h
		a.taken = n
		if h then
			counters.ascendDrawn += 1
		end
	end
	refreshLoop()
end

local function once(a: Ascend, key: string, at: number, now: number): boolean
	if a.marks[key] or now < at then
		return false
	end
	a.marks[key] = true
	return true
end

local function stepAscend(a: Ascend, now: number, dt: number)
	a.frames += dt
	local r = WorldStateController.ranch(a.slot)
	local gone = r == nil or r.userId ~= a.userId
	if now >= a.endsAt or a.frames > ASCEND_CUT or gone or not Flags.on("JellyAscend") then
		finishAscend(now < a.endsAt)
		return
	end
	-- un spectateur dont le ranch du héros quitte le détail complet : plus rien de dessiné
	if a.handle and not a.hero and not fullDetail(a.slot) then
		releaseCopy(a.handle, a.taken)
		a.handle = nil
		a.taken = 0
	end
	local h = a.handle
	if h == nil then
		return
	end
	local s = AscendPath.sample(a.slot, a.startedAt, a.burstAt, a.endsAt, now)
	if s.grow > 0 and a.newRatio == nil then
		a.newRatio = newRatio(a, now)
	end
	local scale = if s.grow > 0 then (a.newRatio or 1) else 1
	pose(h, s.pos, scale)
	local f = fx
	if once(a, "charge", a.startedAt, now) then
		playSound("AscendCharge", "SplorchCharge")
	end
	if once(a, "burst", a.burstAt, now) then
		counters.bursts += 1
		local sky = select(2, AscendPath.endpoints(a.slot))
		confetti(sky, ShowsV2.paletteOf(a.slot) or { GOLD, WHITE, PINK, GOLD }, ASCEND_SPARKS)
		if f then
			pcall(f.ring, sky, GOLD, ASCEND_RING, 0.8)
			pcall(f.stamp, "ascend.stamp", { n = a.A }, GOLD)
		end
		playSound("AscendBurst", "SplorchPop")
		if a.hero then
			haptic("ascend")
			flash()
		end
	end
	if once(a, "show", a.burstAt + SHOW_TEXT_AFTER, now) and f then
		pcall(f.stamp, "ascend.show", nil, GOLD)
	end
end

-- =============================================================================================
-- Pluie d'étoiles (V3)
-- =============================================================================================

function ShowsV2.starRain(d: any): boolean
	local memo = heroMemo
	if type(d) ~= "table" or memo == nil or d.short == true or not Flags.on("JellyAscend") then
		return false
	end
	if Clock.now() > memo.untilT then
		heroMemo = nil
		return false
	end
	if d.heroId ~= memo.userId or memo.rained then
		return false
	end
	memo.rained = true
	counters.starRains += 1
	rain = { frames = 0, waves = 0, rng = Random.new(memo.userId % 2 ^ 31) }
	playSound("GiftRain")
	refreshLoop()
	return true
end

local function stepRain(r: Rain, dt: number)
	local wave = math.floor(r.frames / (STAR_TIME / STAR_WAVES)) + 1
	r.frames += dt
	while r.waves < math.min(wave, STAR_WAVES) do
		r.waves += 1
		local c = WorldLayout.plaza("center")
		local a = r.rng:NextNumber() * math.pi * 2
		local d = r.rng:NextNumber() * STAR_RADIUS
		local f = fx
		if f then
			pcall(
				f.burst,
				Vector3.new(c.X + math.cos(a) * d, c.Y + STAR_HEIGHT, c.Z + math.sin(a) * d),
				GOLD,
				STAR_SPARKS / STAR_WAVES
			)
		end
	end
	if r.frames >= STAR_TIME then
		rain = nil
	end
end

-- =============================================================================================
-- Palier, étapes du record, retour au record (V4, V5)
-- =============================================================================================

local function myRanchTiers(): boolean
	local slot = mySlot()
	local model = if slot > 0 then ranchModel(slot) else nil
	return model ~= nil and type(model:GetAttribute("TapisTier")) == "number"
end

local function onTier(d: any)
	-- RanchTiers ouvert : MON ranch porte l'attribut TapisTier (le client n'a pas d'autre signal)
	local tier = Util.int(d.tier, 1, 6)
	if tier == nil or type(d.family) ~= "string" or #d.family > 32 or not myRanchTiers() then
		return
	end
	local slot = mySlot()
	if slot == 0 then
		return
	end
	counters.tiers += 1
	playSound("LevelUp")
	haptic("tierUp")
	local now = Clock.now()
	if now < tierUntil or quiet() then
		counters.quiet += 1
		return
	end
	tierUntil = now + TIER_TIME
	local f = fx
	if f then
		pcall(f.ring, center(slot, 0.4), GOLD, TIER_RING, TIER_RING_TIME)
	end
	confetti(center(slot, CONFETTI_HEIGHT), confettiOf(slot), TIER_CONFETTI)
	if Util.safe("Personality.active", false, Personality.active) then
		Util.safe("Personality.wave", 0, Personality.wave, slot)
	end
end

local function onRecordConfetti(kind: string, d: any)
	local slot = mySlot()
	if slot == 0 then
		return
	end
	if kind == "recordStep" then
		local share = d.share
		if not Flags.on("RecordR") or not finite(share) or share <= 0 or share >= 1 then
			return
		end
		counters.recordSteps += 1
		if quiet() then
			counters.quiet += 1
			return
		end
		confetti(center(slot, CONFETTI_HEIGHT), confettiOf(slot), STEP_CONFETTI)
	else
		if not (Flags.on("PetitSplorch") or Flags.on("JellyAscend")) or not finite(d.bestR) then
			return
		end
		counters.regains += 1
		playSound("ConfettiGain", "Coin")
		if quiet() then
			counters.quiet += 1
			return
		end
		confetti(center(slot, CONFETTI_HEIGHT), confettiOf(slot), REGAIN_CONFETTI)
	end
end

-- =============================================================================================
-- Boucle et API
-- =============================================================================================

function ShowsV2._step(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	local now = Clock.now()
	for slot, p in petits do
		local ok, err = pcall(stepPetit, p, now, d)
		if not ok then
			Util.raise("ShowsV2.petit", tostring(err))
			finishPetit(slot, true)
		end
	end
	local a = ascend
	if a then
		local ok, err = pcall(stepAscend, a, now, d)
		if not ok then
			Util.raise("ShowsV2.ascend", tostring(err))
			finishAscend(true)
		end
	end
	local r = rain
	if r then
		stepRain(r, d)
	end
	refreshLoop()
end

local function needLoop(): boolean
	return next(petits) ~= nil or ascend ~= nil or rain ~= nil
end

function refreshLoop()
	if not started then
		return
	end
	local need = needLoop()
	if need and stepConn == nil then
		stepConn = RunService.RenderStepped:Connect(function(dt: number)
			Util.guard("ShowsV2.step", ShowsV2._step, dt)
		end)
	elseif not need and stepConn ~= nil then
		local c = stepConn :: RBXScriptConnection
		stepConn = nil
		c:Disconnect()
	end
end

local function onFlags()
	if Flags.on("PetitSplorch") then
		attachPetit()
	else
		detachPetit()
	end
	if not Flags.on("JellyAscend") then
		finishAscend(true)
		heroMemo = nil
		rain = nil
	end
	refreshLoop()
end

-- Celebrate v2.0 ; vrai si la sorte est de ce module (charge vérifiée ici, jamais d'erreur)
function ShowsV2.celebrate(kind: string, d: any): boolean
	if type(d) ~= "table" then
		return false
	end
	if kind == "petitSplorch" then
		onPetitCelebrate(d)
	elseif kind == "ascend" then
		onAscend(d)
	elseif kind == "tier" then
		onTier(d)
	elseif kind == "recordStep" or kind == "regainDone" then
		onRecordConfetti(kind, d)
	else
		return false
	end
	return true
end

-- Un spectacle de ShowsV2 vit (sur le ranch `slot` si donné)
function ShowsV2.busy(slot: number?): boolean
	if slot == nil then
		return needLoop()
	end
	local a = ascend
	return petits[slot] ~= nil or (a ~= nil and a.slot == slot)
end

-- Héros de l'Ascension en cours (ou retenu pour la Pluie d'étoiles), 0 sinon
function ShowsV2.heroId(): number
	local memo = heroMemo
	if memo and Clock.now() <= memo.untilT then
		return memo.userId
	end
	return 0
end

function ShowsV2.start(effects: Fx)
	if started then
		return
	end
	started = true
	fx = effects
	table.insert(
		connections,
		Flags.Changed:Connect(function()
			Util.guard("ShowsV2.flags", onFlags)
		end) :: any
	)
	onFlags()
end

function ShowsV2.stop()
	detachPetit()
	finishAscend(false)
	heroMemo = nil
	rain = nil
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	local c = stepConn
	stepConn = nil
	if c then
		c:Disconnect()
	end
	started = false
end

function ShowsV2.stats(): { [string]: number }
	local n = 0
	for _ in attrConns do
		n += 1
	end
	local live = 0
	for _ in petits do
		live += 1
	end
	return {
		petits = counters.petits,
		petitTexts = counters.petitTexts,
		ascends = counters.ascends,
		ascendDrawn = counters.ascendDrawn,
		bursts = counters.bursts,
		starRains = counters.starRains,
		tiers = counters.tiers,
		recordSteps = counters.recordSteps,
		regains = counters.regains,
		cut = counters.cut,
		refused = counters.refused,
		quiet = counters.quiet,
		livePetits = live,
		liveAscend = if ascend then 1 else 0,
		rain = if rain then 1 else 0,
		looping = if stepConn then 1 else 0,
		attrConnections = n,
		connections = #connections + n + (if stepConn then 1 else 0),
	}
end

function ShowsV2._state(): { [string]: any }
	local a = ascend
	local out: { [string]: any } = { petits = {}, ascend = nil }
	for slot, p in petits do
		out.petits[slot] = {
			model = if p.handle then p.handle.model else nil,
			scale = if p.handle then p.handle.spec.displayScale else nil,
			popped = p.popped,
		}
	end
	if a then
		out.ascend = {
			slot = a.slot,
			hero = a.hero,
			model = if a.handle then a.handle.model else nil,
			body = if a.handle then a.handle.body else nil,
			upScale = a.upScale,
			newRatio = a.newRatio,
			marks = table.clone(a.marks),
		}
	end
	return out
end

function ShowsV2._configure(options: any?)
	local o: any = if type(options) == "table" then options else {}
	sources.play = if type(o.play) == "function" then o.play else nil
	sources.haptic = if type(o.haptic) == "function" then o.haptic else nil
	sources.flash = if type(o.flash) == "function" then o.flash else nil
end

return ShowsV2
