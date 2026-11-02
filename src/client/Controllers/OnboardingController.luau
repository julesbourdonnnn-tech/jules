--!strict
-- OnboardingController (paquet client-hud, docs/04 §13.5) : les 5 premières minutes (GDD §3) côté
-- client. Le serveur (QuestService) tient l'étape et les événements scriptés ; le client montre :
--   * une seule consigne à la fois (glyphe 64 + mot 40 px TV, 4 mots au plus, Config/Quests.Onboarding
--     .Steps[].hint / glyph) pour la prochaine étape : dans la place de la puce spéciale du HUD
--     (HUD.setHint) quand l'invite du monde (UI/Prompt) ne la montre pas déjà au-dessus de l'objet ;
--     « Marcher » (glyphe du stick) seulement après Quests.Onboarding.WalkHintAfter (4 s) sans bouger ;
--     « Monter » seulement quand une selle existe ;
--   * aucune étape ne bloque : une consigne non suivie se range après StepTimeout (90 s), Big Plop la
--     remontre 90 s plus tard (cycle borné), l'accueil continue ; reprise après une mort ou un retour
--     (la consigne se réaffiche) ;
--   * affichage progressif du HUD (HUD.reveal) : au début, seul le compteur de pièces ; le HUD complet
--     à l'étape 10 (objectifs vus) ou pour un joueur qui revient ;
--   * glyphes L1 R1 « Choisir » pendant 4 s, une seule fois, après la démonstration de Big Plop, s'il
--     n'a jamais changé de cible ;
--   * leçon du menu (△ / croix ↓ ; M au clavier) : la puce Menu apparaît quand le menu s'ouvre
--     (Hud/Lesson, partagé avec InputController) ;
--   * événements discrets avant l'étape 9 (LightingController.setQuiet, Banners.setQuiet ; musique
--     −12 dB : note INT-AUDIO, AudioController n'a pas encore de volume de musique).
-- Une boucle par image (à 10 Hz) ; temps par Clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Quests = require(Shared.Config.Quests)
local Formulas = require(Shared.Logic.Formulas)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local LightingController = require(Client.Controllers.LightingController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local HUD = require(Client.UI.HUD)
local Banners = require(Client.UI.Banners)
local Prompt = require(Client.UI.Prompt)
local InputController = require(Client.Controllers.InputController)
local Util = require(Client.UI.Hud.Util)
local Lesson = require(Client.UI.Hud.Lesson)

local OnboardingController = {}

local ONB = Quests.Onboarding
local TICK = 0.1
local MOVE_EPS = 0.3 -- studs : en dessous, le personnage n'a pas bougé
local DEMO_STEP = 8 -- après la démonstration (premier tirage, ~2:45-3:00), « Choisir » une fois

-- Étape minimale à partir de laquelle chaque élément du HUD est montré pendant l'accueil (GDD §3 :
-- au début, seul le compteur de pièces ; horloge du prochain événement vers 3:00 ; HUD complet à 5:00)
local REVEAL_AT: { [string]: number } = {
	coins = 0,
	message = 0,
	specialChip = 0,
	leap = 0,
	targetCard = 1,
	goalTracker = 5,
	fame = 7,
	eventPill = 8,
	status = 8,
	gauge = 9,
	megaBar = 9,
	menuChip = 99, -- leçon du menu (Lesson.menuUnlocked)
}

-- Mot de chaque consigne (Config/Quests.Onboarding.Steps[].hint)
local HINT_KEYS: { [string]: string } = {
	press = "prompt.press",
	walk = "prompt.walk",
	pickup = "prompt.pickup",
	leap = "prompt.leap",
	ride = "prompt.ride",
	menu = "prompt.menu",
}

local started = false
local acc = math.huge
local currentStep = -1
local quietNow: boolean? = nil
local hintStep = -1
local hintSince = 0
local lastMoveAt = 0
local lastPos: Vector3? = nil
local chooseShownAt: number? = nil
local chooseDone = false
local cycledOnce = false
local lastHint: string? = nil
local revealedAll: boolean? = nil

-- =============================================================================================
-- Outils
-- =============================================================================================

local function stepDef(step: number): Quests.OnboardingStep?
	for _, def in ONB.Steps do
		if def.step == step then
			return def
		end
	end
	return nil
end

local function mySlot(): number
	return Util.num(Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot), 0, 0, 64)
end

local function hasSaddle(): boolean
	local slot = mySlot()
	if slot > 0 then
		local ranch = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, slot)
		if type(ranch) == "table" and Util.num(ranch.saddle, 0) > 0 then
			return true
		end
	end
	local biggest = Util.num(State.get("biggestEver"), 0, 0)
	return Util.safe("Formulas.saddleLevel", 0, Formulas.saddleLevel, biggest) > 0
end

local function inOwnRanch(): boolean
	local pos = Util.rootPos()
	local slot = mySlot()
	return pos ~= nil and slot > 0 and WorldLayout.inRanch(slot, pos :: Vector3)
end

local function setHint(action: string?, key: string?)
	local id = if key then (action or "") .. "|" .. key else nil
	if id == lastHint then
		return
	end
	lastHint = id
	Util.safe("HUD.setHint", nil, HUD.setHint, action, key)
end

local function applyQuiet(quiet: boolean)
	if quietNow == quiet then
		return
	end
	quietNow = quiet
	Util.safe("LightingController.setQuiet", nil, LightingController.setQuiet, quiet)
	Util.safe("Banners.setQuiet", nil, Banners.setQuiet, quiet)
end

local function applyReveal(now: number)
	local done = Lesson.known() and Lesson.done()
	if done then
		if revealedAll ~= true then
			revealedAll = true
			Util.safe("HUD.reveal", nil, HUD.reveal, "all", true)
		end
		return
	end
	revealedAll = false
	local step = Lesson.step()
	for name, at in REVEAL_AT do
		local visible = step >= at
		if name == "menuChip" then
			visible = Lesson.menuUnlocked(now)
		end
		Util.safe("HUD.reveal", nil, HUD.reveal, name, visible)
	end
end

-- =============================================================================================
-- Consignes
-- =============================================================================================

local function trackMove(now: number)
	local pos = Util.rootPos()
	if pos == nil then
		lastPos = nil
		return
	end
	local prev = lastPos
	if prev == nil or (pos - prev).Magnitude > MOVE_EPS then
		lastMoveAt = now
		lastPos = pos
	end
end

-- La consigne est-elle déjà montrée par une invite du monde au-dessus de l'objet ?
local function promptShows(): boolean
	local plates = Util.safe("Prompt.plates", {}, Prompt.plates)
	return type(plates) == "table" and #plates > 0
end

local function hintFor(now: number): (string?, string?)
	if not Lesson.known() or Lesson.done() then
		return nil, nil
	end
	local step = Lesson.step()
	local nextStep = step + 1
	if nextStep ~= hintStep then
		hintStep = nextStep
		hintSince = now
	end
	-- aucune étape ne bloque : 90 s affichée, 90 s rangée, puis Big Plop la remontre
	local cycle = ONB.StepTimeout
	local phase = math.floor(math.max(0, now - hintSince) / cycle) % 2
	local def = stepDef(nextStep)
	local hint = if def then def.hint else nil
	if hint ~= nil and phase == 0 then
		local key = HINT_KEYS[hint]
		if hint == "walk" then
			if now - lastMoveAt >= ONB.WalkHintAfter then
				return "move", key
			end
		elseif hint == "ride" then
			if hasSaddle() then
				return "ride", key
			end
		elseif hint == "menu" then
			if Lesson.menuUnlocked(now) then
				return "menu", key
			end
		elseif hint == "press" or hint == "pickup" or hint == "leap" then
			-- l'invite du monde (« □ Presser », « ○ Prendre », « □ Attraper ») est la consigne
			if not promptShows() then
				return def and def.glyph or "action", key
			end
		end
	end
	-- « Choisir » (L1 R1) : une seule fois, 4 s, après la démonstration, dans son ranch
	if not chooseDone and not cycledOnce and step >= DEMO_STEP and inOwnRanch() then
		if chooseShownAt == nil then
			chooseShownAt = now
		end
		if now - (chooseShownAt :: number) < ONB.TargetChooseHint then
			return "target", "prompt.choose"
		end
		chooseDone = true
	end
	return nil, nil
end

local function tick(now: number)
	trackMove(now)
	local known = Lesson.known()
	local step = Lesson.step()
	if step ~= currentStep then
		currentStep = step
	end
	applyQuiet(not known or (not Lesson.done() and step < Lesson.QuietUntilStep))
	applyReveal(now)
	local action, key = hintFor(now)
	setHint(action, key)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function OnboardingController.Init()
	currentStep = -1
end

-- Connexions et boucles
function OnboardingController.Start()
	if started then
		return
	end
	started = true
	Net.event("Celebrate").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and payload.kind == "onboarding" and type(payload.data) == "table" then
			Lesson.note(Util.num(payload.data.step, 0, 0, 99))
			acc = math.huge
		end
	end)
	InputController.Action:Connect(function(action: string)
		if action == "cycle" then
			cycledOnce = true
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player.CharacterAdded:Connect(function()
			-- reprise après une mort ou un retour : la consigne en cours se réaffiche
			hintStep = -1
			lastPos = nil
			lastMoveAt = Clock.now()
			acc = math.huge
		end)
	end
	-- profil reçu ou étape changée : mode discret et affichage du HUD appliqués tout de suite
	State.observe("onboarding", function()
		tick(Clock.now())
	end)
	lastMoveAt = Clock.now()
	RunService.Heartbeat:Connect(function(dt: number)
		acc += Util.num(dt, 0, 0, 1)
		if acc >= TICK then
			acc = 0
			tick(Clock.now())
		end
	end)
	tick(Clock.now())
end

-- Étape d'accueil connue du client
function OnboardingController.step(): number
	return Lesson.step()
end

-- Événements discrets (avant l'étape 9 ; aussi tant que le profil n'est pas connu)
function OnboardingController.quiet(): boolean
	if not Lesson.known() then
		return true
	end
	return not Lesson.done() and Lesson.step() < Lesson.QuietUntilStep
end

-- Un tour tout de suite (specs ; la boucle par image fait de même)
function OnboardingController._tick()
	tick(Clock.now())
end

return OnboardingController
