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

-- Scène réservée : met en pause les cerveaux de tous les joueurs sauf `keep` ({ [Player] = true })
-- et renvoie la table des cibles qui les ramène à leur port sûr (à passer à walkAll, complétée
-- des cibles des acteurs de la scène). Bots.resume() rend la main à tous les cerveaux.
function Bots.sendHome(keep)
	local w = world()
	local targets = {}
	for _, p in w.players do
		if not keep[p] then
			if w.brains[p] then
				w.brains[p].paused = true
			end
			if p.Parent and Bots.rootOf(p) then
				targets[p] = Bots.harborPoint(p)
			end
		end
	end
	return targets
end

function Bots.resume()
	for _, b in world().brains do
		b.paused = false
	end
end

function Bots.brains()
	for _, p in world().players do
		Bots.brainStep(p)
	end
end

-- -------------------------------------------------------------------------------------------
-- Coupe mise en scène : la victime se constitue une file d'au moins `minLine` Nebbies, marche
-- 30 studs en ligne droite (hors port sûr) puis s'arrête ; le coupeur se place sur le côté,
-- attend que les règles de coupe l'autorisent (immunité de la victime, 2 coupes subies par
-- minute) puis traverse la file. Les cerveaux des deux joueurs sont mis en pause pendant la
-- scène (puis rendus). Retourne { n = file avant la coupe, snips = SnipEvent avant, dust =
-- Stardust du coupeur avant, event = SnipEvent de CETTE coupe ou nil, count = nombre de SnipEvent
-- de ce coupeur sur cette victime pendant la traversée, caughtDuring = Nebbies capturés par la
-- victime pendant la traversée, why = diagnostic si rien n'a été coupé }.
-- -------------------------------------------------------------------------------------------

function Bots.stageSnip(victim, snipper, minLine)
	local w = world()
	minLine = minLine or 7
	local b1, b2 = w.brains[victim], w.brains[snipper]
	if b1 then
		b1.paused = true
	end
	if b2 then
		b2.paused = true
	end
	local cross, side
	-- pendant la mise en place, les autres joueurs (cerveaux actifs), un Gloomwisp ou le coupeur
	-- lui-même (immobile, quand le trajet de la victime passe sur lui : le test balayé coupe aussi
	-- une file qui glisse sous un corps à l'arrêt) peuvent couper la victime : la scène reprend
	-- alors depuis le début (au plus 4 fois) pour que la traversée parte d'une file intacte
	for _ = 1, 4 do
		local spot = Bots.zonePoint(victim, 85, 0)
		Bots.walkAll({ [victim] = spot }, 400, Bots.brains)
		for _ = 1, 600 do
			if w.Conga.lineLength(victim) >= minLine then
				break
			end
			Bots.stepToward(victim, Bots.nearestWild(victim, 40) or spot)
			Bots.frame(Bots.brains)
		end
		assert(w.Conga.lineLength(victim) >= minLine, "stageSnip : la victime n'a pas constitué sa file")
		-- point de départ loin de tout port sûr (portes à r ≈ 131, ports de 25 studs) : r = 75,
		-- entre deux Nids ; la file suit
		Bots.walkAll({ [victim] = Bots.zonePoint(victim, 75, math.pi / 12) }, 400, Bots.brains)
		-- ligne droite de 30 studs, perpendiculaire au rayon
		local root = Bots.rootOf(victim).Position
		local dir = w.V3.new(-root.Z, 0, root.X).Unit
		local a = w.V3.new(root.X, 0, root.Z)
		local b = a + dir * 30
		Bots.walkAll({ [victim] = b }, 100, Bots.brains)
		Bots.frames(3, Bots.brains)
		-- le coupeur approche par le côté où il se trouve déjà (sans traverser la file en venant)
		cross = b - dir * 16
		side = w.V3.new(dir.Z, 0, -dir.X)
		if (Bots.rootOf(snipper).Position - cross):Dot(side) < 0 then
			side = -side
		end
		Bots.walkAll({ [snipper] = cross + side * 10 }, 600)
		while
			Bots.now() < Bots.lastSnipOf(victim) + 61
			or Bots.now() < (victim:GetAttribute("ImmuneUntil") or 0)
		do
			Bots.frame()
		end
		if w.Conga.lineLength(victim) >= minLine then
			break
		end
	end
	local out = {
		n = w.Conga.lineLength(victim),
		snips = Bots.countAll("SnipEvent"),
		dust = w.DS.get(snipper).stardust,
	}
	local lineEvents = Bots.countAll("LineEvent")
	Bots.walkAll({ [snipper] = cross - side * 10 }, 40)
	Bots.frames(2)
	-- captures de la victime pendant la traversée (un sauvage qui flâne jusqu'à elle)
	out.caughtDuring = 0
	local slot = w.Nest.slotOf(victim)
	local lists = Bots.allEvents("LineEvent")
	for i = lineEvents + 1, #lists do
		for _, op in lists[i] do
			if op.op == "add" and op.slot == slot then
				out.caughtDuring += #op.codes
			end
		end
	end
	local events = Bots.allEvents("SnipEvent")
	out.count = 0
	for i = out.snips + 1, #events do
		local e = events[i]
		if e.victimSlot == w.Nest.slotOf(victim) and e.snipperSlot == w.Nest.slotOf(snipper) then
			out.event = e
			out.count += 1
		end
	end
	if out.count == 0 then
		-- diagnostic : pourquoi la traversée n'a rien coupé ?
		local inHarbor = 0
		for _, node in w.Conga.nodePositions(victim) do
			if w.WL.inHarbor(node) then
				inHarbor += 1
			end
		end
		out.why = string.format(
			"file %d (%d au port sûr), immunité %.1f s, dernière coupe subie il y a %.1f s, coupeur à %s, zen %s, rookie %s/%s",
			w.Conga.lineLength(victim),
			inHarbor,
			(victim:GetAttribute("ImmuneUntil") or 0) - Bots.now(),
			Bots.now() - Bots.lastSnipOf(victim),
			tostring(Bots.rootOf(snipper) and Bots.rootOf(snipper).Position),
			tostring(w.Nest.isZen(victim)),
			tostring(w.Quest.isRookie(victim)),
			tostring(w.Quest.isRookie(snipper))
		)
	end
	if b1 then
		b1.paused = false
	end
	if b2 then
		b2.paused = false
	end
	return out
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
