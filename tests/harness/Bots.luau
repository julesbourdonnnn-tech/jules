--!nocheck
-- Boîte à outils générique de joueurs simulés pour les tests d'intégration (remplace les Bots de
-- Comet Conga, propres à son jeu). Les paquets du jeu l'étendent (cerveaux, scènes) dans leurs specs
-- ou dans un module de harnais à eux, sans la modifier pour un seul jeu.
--
--   local w = Bots.boot(Harness, { t0 = T, before = function(w) … end })   -- serveur complet
--   local players = Bots.spawn(16)                 -- 16 joueurs, personnages, profils chargés
--   Bots.walkAll({ [p] = Bots.ground(20, 0) })     -- marche honnête (≤ 15 studs/s)
--   Bots.jitter(p, 2)                              -- paquets réseau groupés par deux (3 : par trois)
--   Bots.freeze(p, 0.7)                            -- gel réseau de 0,7 s, puis rattrapage d'un coup
--   local mc = Bots.moveCheck()                    -- MoveCheck appelé à chaque tick, comme le fera
--                                                     le service du tick de jeu ; mc.count(p, "flag")…
--   Bots.frames(100, Bots.brains)                  -- 10 s de jeu (10 Hz), cerveaux compris
--
-- Modèle réseau : chaque joueur simulé a une position « vraie » (son client) et une position « vue »
-- par le serveur (sa HumanoidRootPart). stepToward / walkAll déplacent la position vraie ; à chaque
-- tick, Bots.frame applique la règle réseau du joueur (normal : vue = vraie ; jitter n : la vue ne
-- change qu'un tick sur n ; gel : la vue reste figée jusqu'à la fin du gel, puis rattrape d'un coup).
-- Seul un déplacement de la position vraie en attente est appliqué : une racine déplacée directement
-- par le test (w.h:moveTo, triche simulée) n'est jamais « corrigée » par le réseau simulé.
-- L'horloge partagée (Shared/Util/Clock) est figée et avance de Bots.DT par tick.

local Bots = {}

local S = "ServerScriptService.Server.Services."
Bots.DT = 0.1 -- s : un tick serveur (10 Hz)
Bots.ROOT_HEIGHT = 3 -- hauteur de la HumanoidRootPart au-dessus du sol (personnage debout)
Bots.STRIDE = 1.5 -- studs par tick (15 studs/s, sous la marche à 16)

local W = nil -- monde courant (Bots.use)

local function world()
	assert(W, "Bots : aucun monde (Bots.use)")
	return W
end

-- -------------------------------------------------------------------------------------------
-- Démarrage, profils
-- -------------------------------------------------------------------------------------------

-- Ajoute au schéma générique des clés de jeu fictives (ex. { coins = 0, items = {} }) : les specs du
-- socle exercent DataService avec des données neutres. À appeler AVANT h:boot().
function Bots.extendSchema(h, fields)
	local Schema = h:require("ServerScriptService.Server.Data.Schema")
	local base = Schema.defaults
	Schema.defaults = function()
		local d = base()
		for k, v in fields do
			if d[k] == nil then
				d[k] = if type(v) == "table" then table.clone(v) else v
			end
		end
		return d
	end
	for k in fields do
		Schema.OWNERS[k] = Schema.OWNERS[k] or "(test)"
	end
	return Schema
end

-- Démarre un serveur complet (Main.server : tous les services de ORDER). opts.t0 : instant figé de
-- l'horloge partagée ; opts.before(w) : avant h:boot() (profils sauvegardés, réglages) ;
-- opts.groundY(x, z) : hauteur du sol (défaut : 0 partout) ; opts.schema : clés de jeu fictives
-- (Bots.extendSchema) ; opts.slowData : garde les délais de production de DataService.
-- Le monde retourné devient le monde courant.
function Bots.boot(Harness, opts)
	opts = opts or {}
	-- opts.preset : préréglage des interrupteurs v2.0 (tests/harness/Flags, lot I) ; sinon celui de
	-- opts.harness.flags, sinon les valeurs livrées
	local hopts = table.clone(opts.harness or {})
	if opts.preset ~= nil then
		hopts.flags = opts.preset
	end
	local h = Harness.new(hopts)
	local w = {
		h = h,
		V3 = h.globals.Vector3,
		players = {},
		brains = {},
		net = {},
		onFrame = nil,
		groundY = opts.groundY or function()
			return 0
		end,
		tick = 0,
	}
	w.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	w.Clock.freeze(opts.t0 or 1800000000)
	if opts.schema then
		Bots.extendSchema(h, opts.schema)
	end
	w.Schema = h:require("ServerScriptService.Server.Data.Schema")
	w.Signals = h:require("ServerScriptService.Server.Signals")
	w.DS = h:require(S .. "DataService")
	if not opts.slowData then
		w.DS.Settings.RETRY_BASE_DELAY = 0.001
		w.DS.Settings.LOCKED_RETRY_DELAY = 0.01
	end
	W = w
	if opts.before then
		opts.before(w)
	end
	h:boot()
	return w
end

function Bots.use(w)
	W = w
end

-- Profil sauvegardé : valeurs par défaut du schéma + `overrides` (copie)
function Bots.profile(w, overrides)
	local d = w.Schema.defaults()
	for k, v in overrides or {} do
		d[k] = v
	end
	return d
end

-- Écrit un profil dans le DataStore simulé (avant l'arrivée du joueur)
function Bots.saveProfile(w, userId, data)
	local store = w.h.game.DataStoreService:GetDataStore(w.Schema.STORE_NAME)
	store:SetAsync("player_" .. userId, { data = data })
end

-- -------------------------------------------------------------------------------------------
-- Joueurs
-- -------------------------------------------------------------------------------------------

function Bots.rootOf(p)
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then
		return root
	end
	return nil
end

-- position au sol + ROOT_HEIGHT (hauteur de la HumanoidRootPart d'un personnage debout)
function Bots.ground(x, z)
	local w = world()
	return w.V3.new(x, w.groundY(x, z) + Bots.ROOT_HEIGHT, z)
end

-- État réseau d'un joueur simulé (créé à la demande à partir de sa racine)
local function netOf(p)
	local w = world()
	local n = w.net[p]
	if n == nil then
		local root = Bots.rootOf(p)
		n = { truePos = root and root.Position, pending = false, group = 1, freezeUntil = -math.huge }
		w.net[p] = n
	end
	return n
end

-- Un joueur rejoint le serveur ; personnage créé, profil attendu (opts.wait = false : pas
-- d'attente), placé en opts.at (Vector3, comme un placement serveur) s'il est donné
function Bots.join(userId, opts)
	opts = opts or {}
	local w = world()
	local p = w.h:addPlayer({
		userId = userId,
		name = opts.name or ("Bot" .. userId),
		locale = opts.locale,
		spawn = opts.spawn,
	})
	table.insert(w.players, p)
	if opts.wait ~= false then
		w.DS.waitFor(p, opts.timeout or 3)
	end
	if opts.at and Bots.rootOf(p) then
		Bots.place(p, opts.at)
	end
	return p
end

-- `n` joueurs (userIds firstId, firstId + 1…), placés en cercle de rayon opts.radius (défaut 40)
-- autour de opts.center (défaut l'origine) ; rend la liste
function Bots.spawn(n, opts)
	opts = opts or {}
	local w = world()
	local first = opts.firstId or (#w.players + 1)
	local radius = opts.radius or 40
	local cx, cz = 0, 0
	if opts.center then
		cx, cz = opts.center.X, opts.center.Z
	end
	local out = {}
	for i = 1, n do
		local a = 2 * math.pi * (i - 1) / n
		local at = if opts.at
			then opts.at(i)
			else Bots.ground(cx + math.cos(a) * radius, cz + math.sin(a) * radius)
		table.insert(out, Bots.join(first + i - 1, { at = at, locale = opts.locale }))
	end
	w.h:settle(3)
	return out
end

-- Départ d'un joueur (PlayerRemoving, personnage détruit)
function Bots.leave(p)
	local w = world()
	w.brains[p] = nil
	w.net[p] = nil
	local i = table.find(w.players, p)
	if i then
		table.remove(w.players, i)
	end
	w.h:removePlayer(p)
end

-- Placement imposé par le serveur (PivotTo) : position vraie = vue, Signals.ServerMoved émis
function Bots.place(p, pos)
	local w = world()
	w.h:moveTo(p, pos)
	local n = netOf(p)
	n.truePos = pos
	n.pending = false
	n.freezeUntil = -math.huge
	w.Signals.ServerMoved:Fire(p)
end

-- Réapparition (nouveau personnage), placé en `pos` s'il est donné
function Bots.respawn(p, pos)
	local w = world()
	w.h:respawn(p)
	w.net[p] = nil
	if pos then
		Bots.place(p, pos)
	end
end

-- -------------------------------------------------------------------------------------------
-- Réseau simulé : paquets groupés, gels
-- -------------------------------------------------------------------------------------------

-- Paquets groupés : la position vue par le serveur ne change qu'un tick sur `group` (1 = normal,
-- 2 = par deux, 3 = par trois : gigue réseau honnête)
function Bots.jitter(p, group)
	netOf(p).group = math.max(1, math.floor(group or 1))
end

-- Gel réseau de `seconds` : la position vue reste figée, puis rattrape la vraie d'un coup
function Bots.freeze(p, seconds)
	netOf(p).freezeUntil = world().Clock.now() + seconds
end

-- Position vraie (client) d'un joueur simulé
function Bots.truePos(p)
	return netOf(p).truePos
end

-- Applique la règle réseau de chaque joueur (appelé par Bots.frame avant le tick serveur) : la
-- position vraie en attente arrive au serveur, sauf pendant un gel ou entre deux paquets groupés
local function applyNet()
	local w = world()
	for p, n in w.net do
		local root = p.Parent and Bots.rootOf(p)
		if root and n.truePos and n.pending then
			-- marge de 1e-6 s : l'horloge figée avance par pas de 0,1 (flottants)
			local frozen = w.Clock.now() < n.freezeUntil - 1e-6
			local grouped = n.group > 1 and (w.tick % n.group) ~= 0
			if not frozen and not grouped then
				n.pending = false
				w.h:moveTo(p, n.truePos)
			end
		end
	end
end

-- -------------------------------------------------------------------------------------------
-- Temps et déplacements
-- -------------------------------------------------------------------------------------------

function Bots.now()
	return world().Clock.now()
end

-- un pas de marche de la position vraie (≤ `stride` studs, défaut 1,5 = 15 studs/s) ; vrai si arrivé
function Bots.stepToward(p, target, stride)
	local w = world()
	if not Bots.rootOf(p) then
		return true
	end
	local n = netOf(p)
	local pos = n.truePos or Bots.rootOf(p).Position
	local d = w.V3.new(target.X - pos.X, 0, target.Z - pos.Z)
	local dist = d.Magnitude
	stride = stride or Bots.STRIDE
	n.pending = true
	if dist <= stride then
		n.truePos = Bots.ground(target.X, target.Z)
		return true
	end
	local nxt = pos + d.Unit * stride
	n.truePos = Bots.ground(nxt.X, nxt.Z)
	return false
end

-- un tick serveur complet : `brain` déplace les joueurs, puis règle réseau, horloge + Bots.DT,
-- Heartbeat, w.onFrame
function Bots.frame(brain)
	local w = world()
	if brain then
		brain()
	end
	w.tick += 1
	applyNet()
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

-- -------------------------------------------------------------------------------------------
-- Cerveaux : fonction(p) appelée à chaque tick par Bots.brains (les paquets du jeu écrivent les
-- leurs : chasser, presser, rentrer…). Bots.wander : cerveau d'exemple, va-et-vient entre deux points.
-- -------------------------------------------------------------------------------------------

function Bots.setBrain(p, fn)
	world().brains[p] = fn
end

function Bots.brains()
	local w = world()
	for _, p in w.players do
		local fn = w.brains[p]
		if fn and p.Parent and Bots.rootOf(p) then
			fn(p)
		end
	end
end

function Bots.wander(a, b)
	local toB = true
	return function(p)
		if Bots.stepToward(p, if toB then b else a) then
			toB = not toB
		end
	end
end

-- -------------------------------------------------------------------------------------------
-- MoveCheck appelé à chaque tick (comme le fera le service du tick de jeu) : noteSpeed au WalkSpeed
-- du Humanoid, reset à chaque nouveau personnage et à chaque Signals.ServerMoved, step sur la
-- racine vue par le serveur. Un verdict "rewind" ramène la racine (PivotTo).
--   local mc = Bots.moveCheck() ; … ; mc.count(p, "flag"), mc.count(p, "rewind"), mc.bursts(p)
-- -------------------------------------------------------------------------------------------

function Bots.moveCheck()
	local w = world()
	local MC = w.h:require("ServerScriptService.Server.Util.MoveCheck")
	local stats = {}
	local seen = {}
	local function statsOf(p)
		local s = stats[p]
		if s == nil then
			s = { ok = 0, flag = 0, rewind = 0, burst = 0 }
			stats[p] = s
		end
		return s
	end
	local moved = w.Signals.ServerMoved:Connect(function(p)
		local root = Bots.rootOf(p)
		if root then
			MC.reset(p, root.Position, w.Clock.now())
		end
	end)
	local previous = w.onFrame
	w.onFrame = function()
		if previous then
			previous()
		end
		local now = w.Clock.now()
		for _, p in w.players do
			local root = p.Parent and Bots.rootOf(p)
			if root then
				local character = p.Character
				if seen[p] ~= character then
					seen[p] = character
					MC.reset(p, root.Position, now)
				end
				local hum = character:FindFirstChildOfClass("Humanoid")
				MC.noteSpeed(p, hum.WalkSpeed, now)
				local verdict, back, burst =
					MC.step(p, root.Position, Bots.DT, now, w.groundY(root.Position.X, root.Position.Z))
				local s = statsOf(p)
				s[verdict] += 1
				if burst then
					s.burst += 1
				end
				if verdict == "rewind" and back then
					-- PivotTo du serveur : le client reprend de là
					w.h:moveTo(p, back)
					local n = netOf(p)
					n.truePos = back
					n.pending = false
				end
			end
		end
	end
	local mc = { MoveCheck = MC }
	function mc.count(p, verdict)
		return statsOf(p)[verdict]
	end
	function mc.bursts(p)
		return statsOf(p).burst
	end
	-- infractions + retours de tous les joueurs (contrôle « joueurs honnêtes »)
	function mc.problems()
		local n = 0
		for _, s in stats do
			n += s.flag + s.rewind
		end
		return n
	end
	function mc.stop()
		moved:Disconnect()
		w.onFrame = previous
	end
	return mc
end

-- -------------------------------------------------------------------------------------------
-- Journaux
-- -------------------------------------------------------------------------------------------

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

function Bots.fire(remote, p, ...)
	world().h:fireServer("ReplicatedStorage.Remotes." .. remote, p, ...)
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

-- os.clock des modules montés (RateLimit, attentes techniques) contrôlé par le test : horloge
-- réelle jusqu'à ctl.freeze(), puis instant figé + ctl.advance(dt). À appeler AVANT de requérir
-- les modules concernés. Aucune vraie attente, aucune dépendance au temps réel (leçon de Comet
-- Conga : tests instables sur une machine chargée).
function Bots.fakeOsClock(h)
	local ctl = { frozenAt = nil, offset = 0 }
	local realOs = os
	h.globals.os = setmetatable({
		clock = function()
			return (ctl.frozenAt or realOs.clock()) + ctl.offset
		end,
	}, { __index = realOs })
	function ctl.freeze()
		ctl.frozenAt = realOs.clock()
	end
	function ctl.advance(dt)
		ctl.offset += dt
	end
	return ctl
end

return Bots
