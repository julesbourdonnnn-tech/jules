--!strict
-- Étape d'accueil connue du client (GDD §3, Config/Quests.Onboarding), partagée par
-- OnboardingController (consignes, affichage progressif, mode discret) et InputController (leçon du
-- menu) : un seul calcul, aucun appel vers un module plus tardif.
--   * étape = la plus haute de onboarding.step (profil répliqué) et de la dernière Celebrate
--     "onboarding" reçue (note) ; accueil fini = onboarding.done ou étape ≥ ObjectivesStep (10) ;
--   * jeu cumulé estimé = stats.playSeconds du profil + temps de la session (Clock) ;
--   * leçon du menu : le menu s'ouvre une fois la balade faite (étape 9) et la carte des objectifs
--     arrivée (Quests.Onboarding.ObjectivesAt de jeu), ou l'étape 10 atteinte ; filet « aucune
--     étape ne bloque » : toujours ouvert après ScriptUntil + StepTimeout de jeu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Quests = require(Shared.Config.Quests)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)
local Util = require(Client.UI.Hud.Util)

local Lesson = {}

local ONB = Quests.Onboarding
Lesson.ObjectivesStep = ONB.MenuLessonStep -- 10 : objectifs vus, HUD complet
Lesson.QuietUntilStep = ONB.EventsQuietUntilStep -- 9

local celebrated = 0
local sessionStart: number? = nil
local playedAtStart = 0

-- Étape d'accueil atteinte (0 tant que le profil n'est pas arrivé)
function Lesson.step(): number
	local o = State.get("onboarding")
	local fromProfile = if type(o) == "table" then Util.num(o.step, 0, 0, 99) else 0
	return math.max(fromProfile, celebrated)
end

-- Célébration "onboarding" reçue (étape atteinte, jamais en arrière)
function Lesson.note(step: number)
	local s = math.floor(Util.num(step, 0, 0, 99))
	if s > celebrated then
		celebrated = s
	end
end

-- Profil reçu ?
function Lesson.known(): boolean
	return State.ready == true and type(State.get("onboarding")) == "table"
end

-- Accueil fini (HUD complet, aucune consigne, événements normaux)
function Lesson.done(): boolean
	local o = State.get("onboarding")
	if type(o) == "table" and o.done == true then
		return true
	end
	return Lesson.step() >= Lesson.ObjectivesStep
end

-- Jeu cumulé estimé (s) : profil à l'arrivée + session
function Lesson.played(now: number): number
	local stats = State.get("stats")
	local fromProfile = if type(stats) == "table" then Util.num(stats.playSeconds, 0, 0) else 0
	if sessionStart == nil and State.ready == true then
		sessionStart = now
		playedAtStart = fromProfile
	end
	local start = sessionStart
	local session = if start then math.max(0, now - start) else 0
	return math.max(fromProfile, playedAtStart + session)
end

-- Le menu peut-il s'ouvrir (leçon du menu commencée ou passée) ?
function Lesson.menuUnlocked(now: number): boolean
	if Lesson.done() then
		return true
	end
	local played = Lesson.played(now)
	if Lesson.step() >= Lesson.ObjectivesStep - 1 and played >= ONB.ObjectivesAt then
		return true
	end
	return played >= ONB.ScriptUntil + ONB.StepTimeout
end

-- Remise à zéro (specs)
function Lesson._reset()
	celebrated = 0
	sessionStart = nil
	playedAtStart = 0
end

-- Horloge de la session (specs)
function Lesson._now(): number
	return Clock.now()
end

return Lesson
