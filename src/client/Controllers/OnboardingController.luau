--!strict
-- OnboardingController — paquet « client-hud » (docs/04-architecture.md §13.14).
-- Les 5 premières minutes (§3), pilotées par profile.onboarding (StateController) — le serveur
-- (QuestService) décide de la progression, ce module ne fait que montrer. Règles pures : Hud/OnboardingPlan.
-- Responsabilités :
--   * travelling caméra d'arrivée de 1,5 s (Scriptable, Sine InOut : ciel au-dessus du Nid → Cratère
--     → derrière le joueur), sauté en Mouvement réduit et pour les joueurs ayant fini l'accueil
--   * affichage progressif du HUD (HUD.reveal) : Glow, file, Dash à 1,5 s ; rail Améliorer après la
--     1re parade ; suivi de quête après le 1er achat ; Collection + Stardust à Q4 ; tout pour un
--     joueur qui revient (pas sa première session) ou ayant fini l'accueil (step 8)
--   * guidage : 6 empreintes Néon de la porte vers les Puffkins puis inversées vers la porte, arche
--     qui pulse en doré, Beam joueur → porte ; flèche au sol vers le Nebby le plus proche (ou vers la
--     porte quand la file est pleine) ; pilier bleu sur le Rare de Q4 ; main animée sur l'icône
--     Améliorer (HUD.attention) ; carte unique en surbrillance dans Améliorer (arguments
--     { focus = "conga" } posés via InputController.setPanelArgs) ; le Dash pulse au début de Q5
--   * jamais plus d'une instruction à l'écran (≤ 4 mots, "onboarding.*"), aucune fenêtre modale
--     (l'accueil n'ouvre jamais de panneau lui-même)
--   * message « Ton Nid travaille même quand tu dors » à 10 min de jeu (joueurs encore nouveaux)
-- Pièces 3D : dossier workspace.ClientOnboarding (ancrées, sans collision, réutilisées). Une seule
-- connexion Heartbeat ; temps d'animation = somme des dt (mesure graphique), temps de jeu = Clock.
-- GDD : §3, §7.1, §7.4, §10.1 (affichage progressif).
-- Dépendances : StateController, Util/Prefs, UI/Juice, WorldStateController, CongaRenderer,
-- PanelController, HUD, Logic/WorldLayout, Config/Quests, Shared/Util/Clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Nebbies = require(Shared.Config.Nebbies)
local Quests = require(Shared.Config.Quests)
local Balance = require(Shared.Config.Balance)
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Logic.Formulas)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local WorldStateController = require(Client.Controllers.WorldStateController)
local PanelController = require(Client.Controllers.PanelController)
local InputController = require(Client.Controllers.InputController)
local HUD = require(Client.UI.HUD)
local Plan = require(Client.UI.Hud.OnboardingPlan)
local Widgets = require(Client.UI.Hud.Widgets)
local Glow = require(Client.UI.Hud.Glow)

local OnboardingController = {}

-- Constantes (GDD §3) ---------------------------------------------------------------------------

local DISPLAY_ORDER = 20
local HINT_SIZE = Vector2.new(400, 56)
local HINT_Y = 232 -- sous la pile de toasts
local FOOTPRINTS = 6
local FOOTPRINT_SIZE = Vector3.new(0.9, 0.12, 1.5)
local FOOTPRINT_STAGGER = 0.15
local FOOTPRINT_SIDE = 0.55
local GOLD = Color3.fromRGB(255, 210, 90)
local RARE_BLUE = Color3.fromRGB(80, 160, 255)
local PILLAR_HEIGHT, PILLAR_WIDTH = 30, 1.5
local ARROW_DISTANCE = 4.5
local ARROW_CLOSE = 7 -- studs : cible atteinte, flèche masquée
local ARCH_BALLS = 7
local ARCH_SIZE_MIN, ARCH_SIZE_MAX = 1.1, 1.8
local TRAVEL_TIME = 1.5
local TRAVEL_SAFETY = 3 -- s : la caméra est rendue quoi qu'il arrive
-- s : le profil arrive souvent AVANT le personnage (chargement DataStore plus court que celui de
-- l'avatar) ; on attend le personnage et le Nid au plus ce temps avant de renoncer au travelling
local INTRO_WAIT = 2.5
local GUIDE_REFRESH = 0.2
local DASH_PULSE = 1.6
local NEST_WORKS_AT = 600 -- 10 min de jeu
local NEST_WORKS_HOLD = 6
local NEST_WORKS_MAX_PLAY = 7200 -- joueurs encore nouveaux (< 2 h de jeu cumulé)
local FOCUS_ARGS = table.freeze({ focus = "conga" })
local ROOT_TO_FEET = 3

local HINT_ICONS: { [string]: string } = {
	["onboarding.catch"] = "◉",
	["onboarding.goHome"] = "⌂",
	["onboarding.tapUpgrade"] = "▲",
	["onboarding.buyConga"] = "✚",
	["onboarding.findNebbies"] = "◉",
	["onboarding.catchRare"] = "◆",
	["onboarding.buyStride"] = "»",
	["onboarding.weather"] = "☁",
	["onboarding.perches"] = "▣",
	["onboarding.nestWorks"] = "☾",
}

local ATTENTION_ELEMENTS: { Types.HudElement } = { "rail.Upgrades", "dash" }

-- Q4 : rareté minimale du Rare à encaisser (config)
local RARE_MIN = (function(): number
	for _, q in Quests.Onboarding do
		if q.goal.kind == "bankRarity" and q.goal.minRarity then
			return q.goal.minRarity :: number
		end
	end
	return 3
end)()

-- État ------------------------------------------------------------------------------------------

local started = false
local profileSeen = false
local firstStep = -1
-- Sessions passées lues dans l'instantané d'arrivée. DataService envoie l'instantané AVANT
-- DataService.Loaded, où QuestService ajoute la session courante (+1 répliqué ≤ 1 s plus tard) :
-- dans l'instantané, ≥ 1 = au moins une session précédente = joueur qui revient.
local snapshotSessions: number? = nil
local introStarted = false
local introDone = false
local introWaitUntil: number? = nil
local cameraTween: Tween? = nil
local dirty = true
local frameTime = 0
local lastGuide = -math.huge
local lastEval = -math.huge
local travelUntil: number? = nil
local sessionStart: number? = nil
local nestWorksShown = false
local nestWorksUntil = -math.huge
local dashPulsed = false
local dashPulseUntil = -math.huge
local upgradesOpen = false
local currentHintKey: string? = nil
local attentionState: { [string]: boolean } = {}
local focusSet = false
local guideMode: Plan.Guide? = nil
local facts: Plan.Facts? = nil

local hintFrame: CanvasGroup? = nil
local hintLabel: TextLabel? = nil
local hintIcon: TextLabel? = nil
local hintScale: UIScale? = nil

local folder: Folder? = nil
local footprints: { BasePart } = {}
local footMode: string? = nil
local archBalls: { BasePart } = {}
local archSlot = 0
local beam: Beam? = nil
local beamStart: Attachment? = nil
local beamEnd: Attachment? = nil
local beamAnchor: BasePart? = nil
local arrowParts: { BasePart } = {}
local pillar: BasePart? = nil
local targetWildId: number? = nil
local rareWildId: number? = nil

-- Outils ----------------------------------------------------------------------------------------

local function isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x: any, default: number): number
	return if isFinite(x) then x :: number else default
end

local function sub(key: string): { [string]: any }
	local value = State.get(key)
	return if type(value) == "table" then value else {}
end

local function currentStep(): number
	return math.clamp(math.floor(num(sub("onboarding").step, 0)), 0, Plan.DONE)
end

local function rootPart(): BasePart?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function feet(pos: Vector3): Vector3
	return Vector3.new(pos.X, WorldLayout.groundY(pos.X, pos.Z) + 0.12, pos.Z)
end

local function canBuy(track: Types.UpgradeTrack, level: number, glow: number): boolean
	local r = math.max(0, math.floor(num(State.get("supernovas"), 0)))
	if level >= Formulas.upgradeMaxLevel(track, r) then
		return false
	end
	return glow >= Formulas.upgradeCost(track, level)
end

-- Nebby sauvage attrapable le plus proche (rareté minimale facultative), nil si aucun
local function nearestWild(from: Vector3, minRarity: number?): (number?, Vector3?)
	local slot = WorldStateController.localSlot()
	local now = Clock.now()
	local bestId: number? = nil
	local bestPos: Vector3? = nil
	local bestDistance = math.huge
	for id, wild in WorldStateController.wilds() do
		local catchable = wild.dizzyUntil <= now or wild.prioritySlot == slot
		local s = Nebbies.unpack(wild.code)
		if catchable and (minRarity == nil or Nebbies.rarityOf(s) >= minRarity) then
			local pos = WorldStateController.wildPosition(wild, now)
			-- les Nebbies personnels (accueil, Rare de Q4) passent avant les autres
			local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
			if wild.personal then
				d *= 0.5
			end
			if d < bestDistance then
				bestDistance = d
				bestId = id
				bestPos = pos
			end
		end
	end
	return bestId, bestPos
end

local function wildPos(id: number?): Vector3?
	if id == nil then
		return nil
	end
	local wild = WorldStateController.wilds()[id]
	if wild == nil then
		return nil
	end
	return WorldStateController.wildPosition(wild, Clock.now())
end

-- Faits observés (entrée des règles pures)
local function gather(): Plan.Facts
	local step = currentStep()
	local stats = sub("stats")
	local upgrades = sub("upgrades")
	local rookie = sub("rookie")
	local conga = math.floor(num(upgrades.conga, 0))
	local stride = math.floor(num(upgrades.stride, 0))
	local perches = math.floor(num(upgrades.perches, 0))
	local slot = WorldStateController.localSlot()
	local n = if slot ~= 0 then WorldStateController.lineLength(slot) else 0
	local glow = Glow.predicted()
	local root = rootPart()
	local rareTarget = false
	if step >= 1 and step < Plan.DONE and Quests.Onboarding[step].goal.kind == "bankRarity" and root then
		local id = nearestWild(root.Position, RARE_MIN)
		rareWildId = id
		rareTarget = id ~= nil
	else
		rareWildId = nil
	end
	local sessions = math.max(num(rookie.sessions, 0), num(stats.sessions, 0))
	local seen = snapshotSessions
	return {
		step = step,
		-- instantané d'arrivée (avant le +1 du serveur) ≥ 1, ou valeur courante ≥ 2 (après le +1) ;
		-- accueil déjà avancé à l'arrivée (Q2+) : HUD complet aussi
		returning = (seen ~= nil and seen >= 1) or sessions >= 2 or firstStep >= 2,
		parades = math.floor(num(stats.parades, 0)),
		conga = conga,
		stardust = math.floor(num(State.get("stardust"), 0)),
		lineCount = n,
		lineFull = slot ~= 0 and n >= Formulas.congaCapacity(conga),
		upgradesOpen = upgradesOpen,
		canBuyConga = canBuy("conga", conga, glow),
		canBuyStride = canBuy("stride", stride, glow),
		canBuyPerches = canBuy("perches", perches, glow),
		rareTarget = rareTarget,
	}
end

-- Instruction à l'écran ---------------------------------------------------------------------------

local function buildHint()
	if hintFrame and hintFrame.Parent then
		return
	end
	local safe = Root.safe("Onboarding", DISPLAY_ORDER)
	local s = Create("UIScale", { Name = "HintScale", Scale = 1 })
	local icon = Widgets.label({
		name = "Icon",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(0, 10, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		maxSize = 36,
		color = Theme.Colors.Gold,
		strokeThickness = 2,
		zIndex = 3,
	})
	icon.AutoLocalize = false
	local label = Widgets.label({
		name = "Text",
		size = UDim2.new(1, -72, 1, -12),
		position = UDim2.fromOffset(60, 6),
		maxSize = 28,
		xAlign = Enum.TextXAlignment.Left,
		strokeThickness = 2,
		zIndex = 3,
	})
	local frame = Create("CanvasGroup", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HINT_Y),
		Size = UDim2.fromOffset(HINT_SIZE.X, HINT_SIZE.Y),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0.15,
		GroupTransparency = 1,
		Visible = false,
		Parent = safe,
	}, {
		Widgets.corner(UDim.new(0, 16)),
		Widgets.stroke(Theme.Colors.Gold, 2.5),
		s,
		icon,
		label,
	})
	hintFrame = frame
	hintLabel = label
	hintIcon = icon
	hintScale = s
end

local function showHint(key: string?)
	if key == currentHintKey then
		return
	end
	currentHintKey = key
	buildHint()
	local frame, label, icon, s = hintFrame, hintLabel, hintIcon, hintScale
	if frame == nil or label == nil or icon == nil or s == nil then
		return
	end
	if key == nil then
		local tween = Juice.tween(frame, 0.2, { GroupTransparency = 1 })
		tween.Completed:Once(function()
			if currentHintKey == nil then
				frame.Visible = false
			end
		end)
		return
	end
	label.Text = Prefs.t(key)
	icon.Text = HINT_ICONS[key] or "★"
	frame.Visible = true
	frame.GroupTransparency = 1
	Juice.tween(frame, 0.15, { GroupTransparency = 0 })
	if Prefs.reducedMotion() then
		s.Scale = 1
	else
		s.Scale = 0.8
		Juice.tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	AudioController.play("Pop", 0.05)
end

-- Pièces 3D -------------------------------------------------------------------------------------

local function ensureFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local existing = workspace:FindFirstChild("ClientOnboarding")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ClientOnboarding"
	made.Parent = workspace
	folder = made
	return made
end

local function neonPart(name: string, color: Color3, shape: Enum.PartType?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Shape = shape or Enum.PartType.Block
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Parent = ensureFolder()
	return part
end

local function hideParts(parts: { BasePart })
	for _, part in parts do
		part.Transparency = 1
	end
end

-- Empreintes : de la porte vers les Puffkins (ou l'inverse), allumées une à une
local function setFootprints(mode: string?)
	if mode == footMode then
		return
	end
	local slot = WorldStateController.localSlot()
	if mode ~= nil and slot == 0 then
		return -- Nid pas encore connu : réessayé à la prochaine évaluation
	end
	footMode = mode
	if mode == nil then
		hideParts(footprints)
		return
	end
	while #footprints < FOOTPRINTS do
		table.insert(footprints, neonPart("Footprint", GOLD))
	end
	local gate = WorldLayout.gateCFrame(slot).Position
	local points = WorldLayout.welcomePoints(slot, Balance.Spawn.WelcomeCount)
	local sum = Vector3.zero
	for _, p in points do
		sum += p
	end
	local target = if #points > 0 then sum / #points else gate
	local from = if mode == "toPuffkins" then gate else target
	local to = if mode == "toPuffkins" then target else gate
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if flat.Magnitude < 1e-3 then
		hideParts(footprints)
		return
	end
	local dir = flat.Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for i, part in footprints do
		local along = from + flat * (i / (FOOTPRINTS + 1))
		local pos = feet(along + side * (if i % 2 == 0 then FOOTPRINT_SIDE else -FOOTPRINT_SIDE))
		part.CFrame = CFrame.lookAt(pos, pos + dir)
		part.Transparency = 0
		if Prefs.reducedMotion() then
			part.Size = FOOTPRINT_SIZE
		else
			part.Size = Vector3.new(0.05, FOOTPRINT_SIZE.Y, 0.05)
			Juice.tween(
				part,
				0.25,
				{ Size = FOOTPRINT_SIZE },
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out,
				(i - 1) * FOOTPRINT_STAGGER
			)
		end
	end
end

-- Arche de la porte qui pulse en doré (7 boules Néon le long de l'arche)
local function setArch(on: boolean)
	local slot = WorldStateController.localSlot()
	if not on or slot == 0 then
		hideParts(archBalls)
		archSlot = 0
		return
	end
	while #archBalls < ARCH_BALLS do
		table.insert(archBalls, neonPart("ArchGlow", GOLD, Enum.PartType.Ball))
	end
	if archSlot ~= slot then
		archSlot = slot
		local gate = WorldLayout.gateCFrame(slot)
		local n = Zones.Nests
		for i, ball in archBalls do
			local a = math.pi * (i - 1) / (ARCH_BALLS - 1)
			local offset = Vector3.new(
				-n.GatePostOffset * math.cos(a),
				n.ArchBottomY + (n.ArchTopY - n.ArchBottomY) * math.sin(a),
				0
			)
			ball.CFrame = CFrame.new(gate:PointToWorldSpace(offset))
		end
	end
	for _, ball in archBalls do
		ball.Transparency = 0
	end
end

-- Faisceau joueur → porte
local function setBeam(on: boolean)
	local root = rootPart()
	local slot = WorldStateController.localSlot()
	if not on or root == nil or slot == 0 then
		local b = beam
		if b then
			b.Enabled = false
		end
		return
	end
	local anchorPart = beamAnchor
	if anchorPart == nil or anchorPart.Parent == nil then
		local made = neonPart("BeamAnchor", GOLD)
		made.Transparency = 1
		local attachment = Instance.new("Attachment")
		attachment.Name = "BeamEnd"
		attachment.Parent = made
		beamEnd = attachment
		beamAnchor = made
		anchorPart = made
	end
	local a = anchorPart :: BasePart
	a.CFrame = CFrame.new(WorldLayout.gateCFrame(slot).Position + Vector3.new(0, 2, 0))
	local start = beamStart
	if start == nil or start.Parent ~= root then
		if start then
			start:Destroy()
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "OnboardingBeam"
		attachment.Position = Vector3.new(0, -1, 0)
		attachment.Parent = root
		beamStart = attachment
		start = attachment
	end
	local b = beam
	if b == nil or b.Parent == nil then
		local made = Instance.new("Beam")
		made.Name = "OnboardingBeam"
		made.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 245, 200))
		made.Width0 = 0.5
		made.Width1 = 0.5
		made.FaceCamera = true
		made.LightEmission = 1
		made.Transparency = NumberSequence.new(0.25)
		made.Parent = a
		b = made
		beam = made
	end
	local bm = b :: Beam
	bm.Attachment0 = start
	bm.Attachment1 = beamEnd
	bm.Enabled = true
end

-- Flèche au sol (fût + chevron)
local function ensureArrow()
	if #arrowParts > 0 and arrowParts[1].Parent then
		return
	end
	table.clear(arrowParts)
	table.insert(arrowParts, neonPart("ArrowShaft", GOLD))
	table.insert(arrowParts, neonPart("ArrowHeadL", GOLD))
	table.insert(arrowParts, neonPart("ArrowHeadR", GOLD))
end

local function placeArrow(target: Vector3?)
	local root = rootPart()
	if target == nil or root == nil then
		hideParts(arrowParts)
		return
	end
	local from = root.Position - Vector3.new(0, ROOT_TO_FEET, 0)
	local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	if flat.Magnitude < ARROW_CLOSE then
		hideParts(arrowParts)
		return
	end
	ensureArrow()
	local dir = flat.Unit
	local bob = if Prefs.reducedMotion() then 0 else math.sin(frameTime * 2 * math.pi / 0.9) * 0.4
	local center = feet(from + dir * (ARROW_DISTANCE + bob))
	local base = CFrame.lookAt(center, center + dir)
	local shaft, left, right = arrowParts[1], arrowParts[2], arrowParts[3]
	shaft.Size = Vector3.new(0.45, 0.12, 2.4)
	shaft.CFrame = base
	left.Size = Vector3.new(0.4, 0.12, 1.4)
	right.Size = Vector3.new(0.4, 0.12, 1.4)
	local tip = base * CFrame.new(0, 0, -1.2)
	left.CFrame = tip * CFrame.Angles(0, math.rad(40), 0) * CFrame.new(0, 0, 0.6)
	right.CFrame = tip * CFrame.Angles(0, math.rad(-40), 0) * CFrame.new(0, 0, 0.6)
	for _, part in arrowParts do
		part.Transparency = 0
	end
end

-- Pilier bleu sur le Rare de Q4
local function placePillar(pos: Vector3?)
	local p = pillar
	if pos == nil then
		if p then
			p.Transparency = 1
		end
		return
	end
	if p == nil or p.Parent == nil then
		local made = neonPart("RarePillar", RARE_BLUE, Enum.PartType.Cylinder)
		made.Size = Vector3.new(PILLAR_HEIGHT, PILLAR_WIDTH, PILLAR_WIDTH)
		pillar = made
		p = made
	end
	local part = p :: BasePart
	local ground = feet(pos)
	part.CFrame = CFrame.new(ground + Vector3.new(0, PILLAR_HEIGHT / 2, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	part.Transparency = 0.35
end

local function setGuide(mode: Plan.Guide?)
	guideMode = mode
	local step = currentStep()
	-- toute première course (Puffkins de bienvenue : seulement à la première session)
	local intro = step == 1
		and facts ~= nil
		and (facts :: Plan.Facts).parades < 1
		and not (facts :: Plan.Facts).returning
	-- empreintes + arche + faisceau pendant la toute première course ; flèche ensuite
	setFootprints(if intro and (mode == "toPuffkins" or mode == "toGate") then mode else nil)
	setArch(mode == "toGate")
	setBeam(intro and mode == "toGate")
	if mode ~= "toNebbies" and mode ~= "toRare" and not (mode == "toGate" and not intro) then
		hideParts(arrowParts)
	end
	if mode ~= "toRare" then
		placePillar(nil)
	end
end

local function stepGuide()
	local mode = guideMode
	local now = frameTime
	-- arche : pulsation douce (taille, ≤ 1 Hz)
	if mode == "toGate" and #archBalls > 0 then
		local k = 0.5 + 0.5 * math.sin(now * 2 * math.pi / 1.2)
		local size = if Prefs.reducedMotion()
			then ARCH_SIZE_MAX
			else ARCH_SIZE_MIN + (ARCH_SIZE_MAX - ARCH_SIZE_MIN) * k
		for _, ball in archBalls do
			ball.Size = Vector3.new(size, size, size)
		end
	end
	local root = rootPart()
	if root == nil then
		hideParts(arrowParts)
		return
	end
	if mode == "toNebbies" then
		if now - lastGuide >= GUIDE_REFRESH or targetWildId == nil then
			lastGuide = now
			targetWildId = nearestWild(root.Position, nil)
		end
		placeArrow(wildPos(targetWildId))
	elseif mode == "toRare" then
		local pos = wildPos(rareWildId)
		placePillar(pos)
		placeArrow(pos)
		if pos == nil then
			dirty = true -- Rare attrapé ou disparu : nouveau guidage
		end
	elseif mode == "toGate" and footMode == nil then
		local slot = WorldStateController.localSlot()
		placeArrow(if slot ~= 0 then WorldLayout.gateCFrame(slot).Position else nil)
	end
end

local function clearGuide()
	setFootprints(nil)
	setArch(false)
	setBeam(false)
	hideParts(arrowParts)
	placePillar(nil)
	guideMode = nil
end

-- Travelling d'arrivée (1,5 s) ----------------------------------------------------------------------

local function finishIntro()
	if introDone then
		return
	end
	introDone = true
	travelUntil = nil
	-- filet de sécurité déclenché pendant le travelling : le tween ne doit pas continuer de
	-- déplacer la caméra une fois rendue au contrôleur Custom
	local running = cameraTween
	cameraTween = nil
	if running and running.PlaybackState == Enum.PlaybackState.Playing then
		running:Cancel()
	end
	local camera = workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
	-- 1,5 s : le HUD apparaît avec 3 éléments (Glow, file, Dash)
	for _, element in { "glow", "line", "dash" } :: { Types.HudElement } do
		HUD.reveal(element, true)
	end
	dirty = true
end

local function travel()
	local camera = workspace.CurrentCamera
	local root = rootPart()
	local slot = WorldStateController.localSlot()
	if camera == nil or root == nil or slot == 0 or Prefs.reducedMotion() then
		finishIntro()
		return
	end
	local nest = WorldLayout.nestCenter(slot)
	local sky = CFrame.lookAt(nest + Vector3.new(0, 70, 0) + nest.Unit * 20, nest)
	local crater = CFrame.lookAt(nest * 0.55 + Vector3.new(0, 45, 0), Vector3.zero)
	local look = root.CFrame.LookVector
	local behind = CFrame.lookAt(root.Position - look * 12 + Vector3.new(0, 6, 0), root.Position + look * 4)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = sky
	travelUntil = frameTime + TRAVEL_SAFETY
	local half = TRAVEL_TIME / 2
	local first =
		Juice.tween(camera, half, { CFrame = crater }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	cameraTween = first
	first.Completed:Once(function()
		if introDone then
			return
		end
		local second =
			Juice.tween(camera, half, { CFrame = behind }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		cameraTween = second
		second.Completed:Once(function()
			finishIntro()
		end)
	end)
end

-- Le travelling a besoin de la caméra, du personnage et du Nid
local function travelReady(): boolean
	return workspace.CurrentCamera ~= nil and rootPart() ~= nil and WorldStateController.localSlot() ~= 0
end

-- Évaluation ------------------------------------------------------------------------------------

local function setAttention(element: Types.HudElement, on: boolean)
	if attentionState[element] == on then
		return
	end
	attentionState[element] = on
	HUD.attention(element, on)
end

local function evaluate()
	dirty = false
	lastEval = frameTime
	local f = gather()
	facts = f
	if not introStarted then
		local returning = f.returning or f.step >= 2
		local newcomer = not returning and f.step <= 1 and f.parades < 1
		if newcomer and not Prefs.reducedMotion() and not travelReady() then
			-- personnage ou Nid pas encore là : attente bornée avant de renoncer au travelling
			local deadline = introWaitUntil or (frameTime + INTRO_WAIT)
			introWaitUntil = deadline
			if frameTime < deadline then
				dirty = true
				return
			end
		end
		introStarted = true
		firstStep = f.step
		f.returning = returning
		-- nouveau joueur : travelling puis HUD de base ; sinon tout de suite
		if newcomer then
			travel()
			if not introDone then
				return
			end
		else
			introDone = true
		end
	end
	if not introDone then
		return
	end
	-- affichage progressif (jamais retiré) : animé pendant la partie, direct au chargement
	if Plan.complete(f) then
		HUD.revealAll()
	else
		for _, element in Plan.reveals(f) do
			if not HUD.isRevealed(element) then
				HUD.reveal(element, profileSeen)
			end
		end
	end
	profileSeen = true
	-- une seule instruction (le message de fin de 10 min passe devant)
	local hint = Plan.hint(f)
	if Clock.now() < nestWorksUntil then
		hint = "onboarding.nestWorks"
	end
	showHint(hint)
	-- attention (main sur Améliorer, Dash au début de Q5)
	if f.step == 5 and not dashPulsed then
		dashPulsed = true
		dashPulseUntil = frameTime + DASH_PULSE
	end
	local attention = Plan.attention(f)
	for _, element in ATTENTION_ELEMENTS do
		local on = attention[element] == true or (element == "dash" and frameTime < dashPulseUntil)
		setAttention(element, on)
	end
	-- panneau Améliorer à une seule carte pendant le premier achat
	local focus = f.step == 1 and f.parades >= 1 and f.conga < 1
	if focus ~= focusSet then
		focusSet = focus
		InputController.setPanelArgs("Upgrades", if focus then FOCUS_ARGS else nil)
	end
	-- guidage au sol
	local mode = Plan.guide(f)
	if f.step >= Plan.DONE or f.step < 1 then
		clearGuide()
	else
		setGuide(mode)
	end
end

local function onFrame(dt: number)
	frameTime += if isFinite(dt) then math.clamp(dt, 0, 0.25) else 0
	local until_ = travelUntil
	if until_ ~= nil and frameTime >= until_ then
		finishIntro() -- filet de sécurité : la caméra n'est jamais laissée en Scriptable
	end
	if not State.ready then
		return
	end
	local now = Clock.now()
	if sessionStart == nil then
		sessionStart = now
	end
	-- « Ton Nid travaille même quand tu dors » à 10 min de jeu
	local start = sessionStart :: number
	if not nestWorksShown and now - start >= NEST_WORKS_AT then
		nestWorksShown = true
		if num(sub("stats").playSeconds, 0) < NEST_WORKS_MAX_PLAY then
			nestWorksUntil = now + NEST_WORKS_HOLD
			dirty = true
		end
	end
	if currentHintKey == "onboarding.nestWorks" and now >= nestWorksUntil then
		dirty = true
	end
	if attentionState.dash and frameTime >= dashPulseUntil then
		dirty = true
	end
	-- l'état d'achat dépend du Glow prédit (qui monte sans patch) : réévaluation périodique
	if dirty or (introDone and frameTime - lastEval >= GUIDE_REFRESH * 2) then
		evaluate()
	end
	if introDone then
		stepGuide()
	end
end

-- API -------------------------------------------------------------------------------------------

-- Étape d'accueil affichée (miroir de profile.onboarding.step)
function OnboardingController.step(): number
	return currentStep()
end

-- Instruction courante (clé "onboarding.*") ou nil
function OnboardingController.currentHint(): string?
	return currentHintKey
end

-- Mode de guidage au sol courant (tests)
function OnboardingController.guide(): string?
	return guideMode
end

function OnboardingController.Init()
	buildHint()
end

function OnboardingController.Start()
	if started then
		return
	end
	started = true
	if not State.ready then
		-- lu au moment même de l'instantané d'arrivée (avant tout patch : valeur sans la session
		-- courante) ; si l'instantané est déjà appliqué, seule la règle « ≥ 2 » reste sûre
		State.ReadySignal:Once(function()
			snapshotSessions = math.max(num(sub("rookie").sessions, 0), num(sub("stats").sessions, 0))
		end)
	end
	local function markDirty()
		dirty = true
	end
	for _, key in { "onboarding", "stats", "upgrades", "rookie", "stardust", "supernovas" } do
		State.observe(key, markDirty)
	end
	WorldStateController.LineOp:Connect(markDirty)
	WorldStateController.WildAdded:Connect(markDirty)
	WorldStateController.WildRemoved:Connect(markDirty)
	WorldStateController.OwnerChanged:Connect(function()
		archSlot = 0
		footMode = nil
		dirty = true
	end)
	PanelController.Opened:Connect(function(name: Types.PanelName)
		if name == "Upgrades" then
			upgradesOpen = true
			dirty = true
		end
	end)
	PanelController.Closed:Connect(function(name: Types.PanelName)
		if name == "Upgrades" then
			upgradesOpen = false
			dirty = true
		end
	end)
	Prefs.LanguageChanged:Connect(function()
		local key = currentHintKey
		local label = hintLabel
		if key and label then
			label.Text = Prefs.t(key)
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player.CharacterAdded:Connect(function()
			footMode = nil
			dirty = true
		end)
	end
	RunService.Heartbeat:Connect(onFrame)
end

-- Exposé pour les tests
OnboardingController._state = function()
	return {
		introDone = introDone,
		facts = facts,
		footprints = footprints,
		footMode = footMode,
		archBalls = archBalls,
		beam = beam,
		arrowParts = arrowParts,
		pillar = pillar,
		attention = attentionState,
		folder = folder,
		hintFrame = hintFrame,
		nestWorksUntil = nestWorksUntil,
	}
end

return OnboardingController
