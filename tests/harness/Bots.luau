--!nocheck
-- Joueurs simulés pour les tests d'intégration (Boot.spec, ClientGame.spec) : serveur complet
-- démarré avec tous les vrais services, déplacements pas à pas à une vitesse de marche honnête
-- (MoveCheck n'est jamais déclenché), « cerveaux » qui chassent les sauvages et rentrent parader,
-- horloge partagée (Shared/Util/Clock) avancée tick par tick ou par saut dans le temps.
--
--   local w = Bots.boot(Harness, { t0 = T, before = function(w) … end })
--   Bots.use(w)
--   local p = w.h:addPlayer({ userId = 1 }) ; table.insert(w.players, p) ; Bots.hunt(p)
--   Bots.frames(300, Bots.brains)       -- 30 s de jeu (10 Hz)

local Bots = {}

local S = "ServerScriptService.Server.Services."
Bots.DT = 0.1

local W = nil -- monde courant (Bots.use)

local function world()
	assert(W, "Bots : aucun monde (Bots.use)")
	return W
end

-- Démarre un serveur complet ; `opts.before(w)` s'exécute avant h:boot() (profils sauvegardés,
-- configuration). Le monde retourné devient le monde courant.
function Bots.boot(Harness, opts)
	opts = opts or {}
	local h = Harness.new()
	local w = { h = h, V3 = h.globals.Vector3, players = {}, brains = {}, onFrame = nil }
	w.DS = h:require(S .. "DataService")
	w.DS.Settings.RETRY_BASE_DELAY = 0.001
	w.DS.Settings.LOCKED_RETRY_DELAY = 0.01
	w.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	w.Clock.freeze(opts.t0)
	w.WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	w.EC = h:require("ReplicatedStorage.Shared.Logic.EventClock")
	w.F = h:require("ReplicatedStorage.Shared.Logic.Formulas")
	w.Neb = h:require("ReplicatedStorage.Shared.Config.Nebbies")
	w.B = h:require("ReplicatedStorage.Shared.Config.Balance")
	w.Mon = h:require("ReplicatedStorage.Shared.Config.Monetization")
	w.Schema = h:require("ServerScriptService.Server.Data.Schema")
	w.Signals = h:require("ServerScriptService.Server.Signals")
	W = w
	if opts.before then
		opts.before(w)
	end
	h:boot()
	-- journal des coupes (instant, victime) : les règles de coupe dépendent de l'historique
	w.snipLog = {}
	w.Signals.Snipped:Connect(function(info)
		table.insert(w.snipLog, { t = w.Clock.now(), victim = info.victim, snipper = info.snipper })
	end)
	w.Conga = h:require(S .. "CongaService")
	w.Spawn = h:require(S .. "SpawnService")
	w.Nest = h:require(S .. "NestService")
	w.Event = h:require(S .. "EventService")
	w.Economy = h:require(S .. "EconomyService")
	w.Atlas = h:require(S .. "AtlasService")
	w.Crew = h:require(S .. "CrewService")
	w.Quest = h:require(S .. "QuestService")
	w.Leader = h:require(S .. "LeaderboardService")
	w.World = h:require(S .. "WorldService")
	return w
end

function Bots.use(w)
	W = w
end

-- Profil déjà sauvegardé d'un joueur expérimenté (bouclier débutant terminé, accueil fini)
function Bots.veteranProfile(w, t0, glow)
	local d = w.Schema.defaults()
	d.glow = glow or 2000
	d.lastSettle = t0 - 600
	d.lastOnline = t0 - 3600
	d.rookie = { sessions = 12, playSeconds = 20000, done = true }
	d.onboarding = { step = 8, p = 0 }
	d.upgrades.conga = 9
	d.upgrades.lure = 3
	d.stats.sessions = 12
	return d
end

-- Écrit un profil dans le DataStore simulé (avant l'arrivée du joueur)
function Bots.saveProfile(w, userId, data)
	local store = w.h.game.DataStoreService:GetDataStore(w.Schema.STORE_NAME)
	store:SetAsync("player_" .. userId, { data = data })
end

-- -------------------------------------------------------------------------------------------
-- Temps, déplacements, journaux
-- -------------------------------------------------------------------------------------------

function Bots.now()
	return world().Clock.now()
end

function Bots.rootOf(p)
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then
		return root
	end
	return nil
end

-- position au sol + 3 (hauteur de la HumanoidRootPart)
function Bots.ground(x, z)
	local w = world()
	return w.V3.new(x, w.WL.groundY(x, z) + 3, z)
end

-- un pas de marche (≤ 1,5 stud par tick = 15 studs/s, sous toute WalkSpeed du jeu) ; vrai si arrivé
function Bots.stepToward(p, target, stride)
	local w = world()
	local root = Bots.rootOf(p)
	if not root then
		return true
	end
	local pos = root.Position
	local d = w.V3.new(target.X - pos.X, 0, target.Z - pos.Z)
	local dist = d.Magnitude
	stride = stride or 1.5
	if dist <= stride then
		w.h:moveTo(p, Bots.ground(target.X, target.Z))
		return true
	end
	local nxt = pos + d.Unit * stride
	w.h:moveTo(p, Bots.ground(nxt.X, nxt.Z))
	return false
end

-- un tick serveur complet (Heartbeat → CongaService.tick) ; `brain` déplace les joueurs avant
function Bots.frame(brain)
	local w = world()
	if brain then
		brain()
	end
	w.Clock.advance(Bots.DT)
	w.h:step(Bots.DT)
	if w.onFrame then
		w.onFrame()
	end
end

function Bots.frames(n, brain)
	for _ = 1, n do
		Bots.frame(brain)
	end
end

-- marche de plusieurs joueurs vers leurs cibles (`extra` : cerveau des autres) ; vrai si arrivés
function Bots.walkAll(targets, maxTicks, extra)
	for _ = 1, maxTicks or 600 do
		local done = true
		for p, target in targets do
			if p.Parent and not Bots.stepToward(p, target) then
				done = false
			end
		end
		Bots.frame(extra)
		if done then
			return true
		end
	end
	return false
end

-- saut dans le temps (personne ne bouge pendant le saut)
function Bots.travelTo(t)
	local w = world()
	assert(t >= w.Clock.now(), "voyage dans le passé")
	w.Clock.freeze(t)
	Bots.frames(2)
end

function Bots.allEvents(remote)
	local out = {}
	for _, e in world().h.log.allClientEvents do
		if e.remote == remote then
			table.insert(out, e.args[1])
		end
	end
	return out
end

function Bots.countAll(remote)
	return #Bots.allEvents(remote)
end

function Bots.lineOps(kind, slot)
	local out = {}
	for _, list in Bots.allEvents("LineEvent") do
		for _, op in list do
			if op.op == kind and (slot == nil or op.slot == slot) then
				table.insert(out, op)
			end
		end
	end
	return out
end

function Bots.sentTo(p, remote)
	return world().h:sentTo(p, remote)
end

-- clés de Feedback reçues par un joueur
function Bots.feedbackKeys(p)
	local out = {}
	for _, args in Bots.sentTo(p, "Feedback") do
		table.insert(out, args[1].key)
	end
	return out
end

function Bots.celebrations(p, kind)
	local out = {}
	for _, args in Bots.sentTo(p, "Celebrate") do
		if args[1].kind == kind then
			table.insert(out, args[1].data)
		end
	end
	return out
end

-- instant de la dernière coupe subie (-inf si aucune)
function Bots.lastSnipOf(victim)
	local t = -math.huge
	for _, e in world().snipLog do
		if e.victim == victim then
			t = math.max(t, e.t)
		end
	end
	return t
end

function Bots.fire(remote, p, ...)
	world().h:fireServer("ReplicatedStorage.Remotes." .. remote, p, ...)
end

function Bots.gateOf(p)
	local w = world()
	return w.WL.gateCFrame(w.Nest.slotOf(p)).Position
end

-- point du port sûr du joueur, entre sa porte et son Nid
function Bots.harborPoint(p)
	local w = world()
	local gate = Bots.gateOf(p)
	return gate + (w.WL.nestCenter(w.Nest.slotOf(p)) - gate).Unit * 6
end

-- point à la distance r du centre, dans la direction de la porte du joueur (± décalage d'angle)
function Bots.zonePoint(p, r, dAngle)
	local w = world()
	local g = Bots.gateOf(p)
	local a = math.atan2(g.Z, g.X) + (dAngle or 0)
	return w.V3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- -------------------------------------------------------------------------------------------
-- « Cerveau » : chasse le sauvage attrapable le plus proche, rentre à SA porte (ou à l'anneau de
-- la Balise pendant la Nuit) quand la file atteint sa cible, recommence.
-- -------------------------------------------------------------------------------------------

function Bots.nearestWild(p, maxR)
	local w = world()
	local root = Bots.rootOf(p)
	if not root then
		return nil
	end
	local t = Bots.now()
	local best, bestD = nil, math.huge
	for _, wild in w.Spawn.query(root.Position, maxR, t, p) do
		if w.Spawn.canCatch(p, w.Nest.slotOf(p), wild, t) then
			local pos = w.Spawn.positionOf(wild, t)
			local d = (pos - root.Position).Magnitude
			if d < bestD then
				best, bestD = pos, d
			end
		end
	end
	return best
end

-- confie un joueur à un cerveau (cible de file, zone de chasse)
function Bots.hunt(p, target, radius, angle)
	world().brains[p] = {
		mode = "hunt",
		target = target or 4,
		radius = radius or 140,
		angle = angle or 0,
		parades = 0,
		paused = false,
	}
end

function Bots.brainStep(p)
	local w = world()
	local b = w.brains[p]
	if not b or b.paused or not p.Parent or not Bots.rootOf(p) then
		return
	end
	local n = w.Conga.lineLength(p)
	if b.mode == "hunt" then
		local want = math.min(b.target, w.Conga.lineCapacity(p))
		if n >= want then
			b.mode = "bank"
		else
			local target = Bots.nearestWild(p, 60) or Bots.zonePoint(p, b.radius, b.angle)
			Bots.stepToward(p, target)
			return
		end
	end
	if b.mode == "bank" then
		if n == 0 then
			b.mode = "hunt"
			b.parades += 1
			return
		end
		local target = if w.Event.beaconOpen() then Bots.zonePoint(p, 12, 0) else Bots.gateOf(p)
		Bots.stepToward(p, target)
	end
end

function Bots.brains()
	for _, p in world().players do
		Bots.brainStep(p)
	end
end

-- Erreurs de scripts et avertissements (dont « Infinite yield possible ») depuis le démarrage
function Bots.problems()
	local w = world()
	local out = table.clone(w.h.errors)
	for _, line in w.h:warnings() do
		table.insert(out, line)
	end
	return out
end

return Bots
