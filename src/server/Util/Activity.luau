--!strict
-- Activité des joueurs (contrat v1.2, GDD v1.3 §4.22, §4.23 ; Config/Events.Activity). Contrat
-- (architecte) : module utilitaire du serveur, sans dépendance vers un service, appelable par tous
-- (comme RateLimit). Sert à compter les joueurs ACTIFS, N de l'objectif du MEGA et de la jauge :
-- un joueur absent du clavier (Pot automatique) ne rend plus l'objectif impossible pour les autres.
--   Activity.note(player, now)          -- intention de JEU acceptée (Config/Intents : activity = true)
--   Activity.noteMove(player, pos, now) -- position VALIDÉE du tick (ChaseService) : actif si le joueur
--                                       -- s'est éloigné d'au moins MoveStuds de son point d'ancrage
--   Activity.isActive(player, now)      -- activité dans les Window dernières secondes
--   Activity.lastIntent(player)         -- v2.0 (N23, lot A3) : instant de la dernière INTENTION
--                                       -- ACCEPTÉE (note), -math.huge sinon ; noteMove ne la change
--                                       -- jamais : un stick calé ne retarde pas la sieste des Plopettes
--   Activity.noteMenu(player, now)      -- v2.0 (N23, lot A4, décision du propriétaire du 6 novembre) :
--                                       -- navigation dans un menu (intention MenuActivity) : avance
--                                       -- lastIntent SEULEMENT (jamais lastActive : ni MEGA ni jauge)
-- La règle « à 60 studs du centre de la place pendant l'alerte du MEGA » est appliquée par
-- EventService.isActive (elle dépend de la phase du MEGA). Temps : Clock.now() passé par l'appelant
-- (les specs voyagent dans le temps). État oublié au départ (PlayerRemoving).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)

local Activity = {}

local lastActive: { [Player]: number } = {}
local anchors: { [Player]: Vector3 } = {}
-- v2.0 (N23) : dernière intention acceptée, à part de lastActive (que noteMove avance aussi)
local lastIntents: { [Player]: number } = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end

-- Activité (intention ou déplacement) à l'instant `now` : jauge et MEGA du jeu de base
local function mark(player: Player, now: number)
	local previous = lastActive[player]
	if previous == nil or now > previous then
		lastActive[player] = now
	end
end

-- Intention de jeu acceptée à l'instant `now`
function Activity.note(player: Player, now: number)
	if player.Parent == nil or not finite(now) then
		return
	end
	mark(player, now)
	local previous = lastIntents[player]
	if previous == nil or now > previous then
		lastIntents[player] = now
	end
end

-- v2.0 (N23, lot A4) : navigation dans un menu acceptée à l'instant `now` (intention MenuActivity) :
-- réveille les Plopettes (lastIntent) ; n'est jamais une activité de jeu (lastActive inchangé : joueurs
-- actifs du MEGA et de la jauge du jeu de base)
function Activity.noteMenu(player: Player, now: number)
	if player.Parent == nil or not finite(now) then
		return
	end
	local previous = lastIntents[player]
	if previous == nil or now > previous then
		lastIntents[player] = now
	end
end

-- Position validée du tick : le premier appel pose l'ancre ; un déplacement d'au moins MoveStuds depuis
-- l'ancre compte comme activité et déplace l'ancre (une marche lente finit toujours par compter, un
-- tremblement sur place jamais)
function Activity.noteMove(player: Player, pos: Vector3, now: number)
	if player.Parent == nil or typeof(pos) ~= "Vector3" or not finite(now) then
		return
	end
	if not (finite(pos.X) and finite(pos.Y) and finite(pos.Z)) then
		return
	end
	local anchor = anchors[player]
	if anchor == nil then
		anchors[player] = pos
		return
	end
	if (pos - anchor).Magnitude >= Events.Activity.MoveStuds then
		anchors[player] = pos
		mark(player, now) -- activité, jamais une intention (N23)
	end
end

-- Actif : une activité notée dans les Events.Activity.Window dernières secondes
function Activity.isActive(player: Player, now: number): boolean
	local at = lastActive[player]
	if at == nil or not finite(now) then
		return false
	end
	return now - at <= Events.Activity.Window
end

-- Instant de la dernière activité (-math.huge si aucune) : débogage et specs
function Activity.lastActive(player: Player): number
	return lastActive[player] or -math.huge
end

-- v2.0 (N23, lot A3) : instant de la dernière intention ACCEPTÉE (-math.huge si aucune) ; lu par
-- HelperService (sieste des Plopettes après Balance.Helpers.NapAfter s)
function Activity.lastIntent(player: Player): number
	return lastIntents[player] or -math.huge
end

-- Oublie le joueur (départ)
function Activity.clear(player: Player)
	lastActive[player] = nil
	anchors[player] = nil
	lastIntents[player] = nil
end

-- Remise à zéro complète (specs)
function Activity.reset()
	table.clear(lastActive)
	table.clear(anchors)
	table.clear(lastIntents)
end

Players.PlayerRemoving:Connect(Activity.clear)

return Activity
