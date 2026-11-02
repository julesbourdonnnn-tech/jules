--!nocheck
-- Cerveaux de robots et scènes du paquet chase (docs/04 §17.1 c), au-dessus de tests/harness/Bots :
--   local w = Brains.boot(Harness, { t0 = T })      -- serveur complet, stubs du paquet meta remplacés
--   local a = Brains.join(w, 1, { at = … })         -- joueur chargé, placé, PlayerReady émis
--   Brains.frames(w, 50)                            -- 5 s de jeu (Heartbeat → ChaseService.tick)
--   Bots.setBrain(p, Brains.presser(w))             -- cerveaux : presser, chasser, booper, monter…
-- Doublures du paquet meta (QuestService, CommunityService, LeaderboardService, DiagnosticsService) :
-- tant que ce paquet n'est pas livré, ses stubs lèvent « TODO(meta) » ; les specs du paquet chase les
-- remplacent avant h:boot() (docs/04 §18.1 « Isolation ») par des doublures réglables (w.meta) qui
-- comptent les erreurs attrapées (w.meta.caught : zéro trace) et les états fermés par délai.
local Bots = require("./Bots")

local Brains = {}

local S = "ServerScriptService.Server.Services."
Brains.S = S

local function noop() end

-- Remplace les stubs du paquet meta par des doublures (à appeler AVANT h:boot())
function Brains.stubMeta(w, opts)
	opts = opts or {}
	local h = w.h
	local meta = {
		playSeconds = {}, -- [userId] = s de jeu (défaut opts.playSeconds ou 3600 : bouclier levé)
		quiet = {}, -- [userId] = true : nouveau avant l'étape 9
		scripts = {}, -- [userId] = OnboardingScript
		names = {}, -- [userId] = nom d'affichage
		settings = {}, -- [userId] = { clé = valeur }
		blocked = {}, -- ["a:b"] = true
		claps = {}, -- appels openClapWindow
		admins = {}, -- [userId] = true
		caught = {}, -- reportCaught (où : erreur)
		timedOut = {}, -- stateTimedOut
	}
	w.meta = meta
	local Q = h:require(S .. "QuestService")
	Q.step = noop
	Q.stage = function()
		return 11
	end
	Q.isNewcomerQuiet = function(p)
		return meta.quiet[p.UserId] == true
	end
	Q.playSeconds = function(p)
		return meta.playSeconds[p.UserId] or opts.playSeconds or 3600
	end
	Q.script = function(p)
		return meta.scripts[p.UserId] or { active = false, runawayPaused = false, vatScripted = false }
	end
	Q.stamp = function()
		return false
	end
	Q.openStates = function()
		return {}
	end
	local C = h:require(S .. "CommunityService")
	C.step = noop
	C.displayName = function(p)
		return meta.names[p.UserId] or p.Name
	end
	C.friendsPresent = function()
		return 0
	end
	C.areFriends = function()
		return false
	end
	C.isBlocked = function(a, b)
		return meta.blocked[a.UserId .. ":" .. b.UserId] == true
			or meta.blocked[b.UserId .. ":" .. a.UserId] == true
	end
	C.setting = function(p, key)
		local s = p and meta.settings[p.UserId]
		if s and s[key] ~= nil then
			return s[key]
		end
		if key == "receiveGifts" then
			return true
		end
		return false
	end
	C.openClapWindow = function(hero, endsAt, viewers)
		table.insert(meta.claps, { hero = hero, endsAt = endsAt, viewers = viewers })
	end
	C.hasCosmetic = function()
		return false
	end
	C.openStates = function()
		return {}
	end
	C.unlockSession = noop
	local L = h:require(S .. "LeaderboardService")
	L.step = noop
	L.submit = noop
	L.isBanned = function()
		return false
	end
	local D = h:require(S .. "DiagnosticsService")
	D.step = noop
	D.report = noop
	D.reportCaught = function(where, err)
		table.insert(meta.caught, tostring(where) .. " : " .. tostring(err))
	end
	D.stateTimedOut = function(name, p)
		table.insert(meta.timedOut, { name = name, player = p })
	end
	D.isAdmin = function(p)
		return meta.admins[p.UserId] == true
	end
	D.counts = function()
		return { errors = #meta.caught, warnings = 0, timedOut = #meta.timedOut, keys = 0 }
	end
	D.snapshot = function()
		return {}
	end
	D.device = function()
		return { kind = 3, tenFoot = true }
	end
	return meta
end

-- Serveur complet du paquet chase : Bots.boot + doublures meta + raccourcis vers les services
function Brains.boot(Harness, opts)
	opts = opts or {}
	-- même monde que Bots.boot, mais os.clock est simulé AVANT tout require (RateLimit compte en temps
	-- réel : figé ici, il avance d'un tick par image, Bots.frame → w.onFrame)
	local h = Harness.new(opts.harness)
	local osClock = Bots.fakeOsClock(h)
	osClock.freeze()
	local w = {
		h = h,
		V3 = h.globals.Vector3,
		players = {},
		brains = {},
		net = {},
		onFrame = function()
			osClock.advance(Bots.DT)
		end,
		groundY = function()
			return 0
		end,
		tick = 0,
		osClock = osClock,
	}
	w.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
	w.Clock.freeze(opts.t0 or 1800000000)
	w.Schema = h:require("ServerScriptService.Server.Data.Schema")
	w.Signals = h:require("ServerScriptService.Server.Signals")
	w.DS = h:require(S .. "DataService")
	w.DS.Settings.RETRY_BASE_DELAY = 0.001
	w.DS.Settings.LOCKED_RETRY_DELAY = 0.01
	w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
	Bots.use(w)
	-- opts.stubMeta = false : vrais services du paquet meta (intégration, une fois livrés)
	if opts.stubMeta ~= false then
		Brains.stubMeta(w, opts)
	else
		w.meta = {
			caught = {},
			timedOut = {},
			playSeconds = {},
			quiet = {},
			scripts = {},
			names = {},
			settings = {},
			blocked = {},
			claps = {},
			admins = {},
		}
	end
	if opts.before then
		opts.before(w)
	end
	h:boot()
	local h = w.h
	w.Chase = h:require(S .. "ChaseService")
	w.Event = h:require(S .. "EventService")
	w.Rush = h:require(S .. "RushService")
	w.Splorch = h:require(S .. "SplorchService")
	w.Ranch = h:require(S .. "RanchService")
	w.Economy = h:require(S .. "EconomyService")
	w.Squishy = h:require(S .. "SquishyService")
	w.MC = h:require("ServerScriptService.Server.Util.MoveCheck")
	w.Activity = h:require("ServerScriptService.Server.Util.Activity")
	w.Tuning = h:require("ServerScriptService.Server.Movement.Tuning")
	w.Guard = h:require("ServerScriptService.Server.Chase.Guard")
	w.WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	w.SeededPath = h:require("ReplicatedStorage.Shared.Logic.SeededPath")
	w.EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock")
	w.ZoneRules = h:require("ReplicatedStorage.Shared.Logic.ZoneRules")
	w.Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas")
	w.StateTimeouts = h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")
	w.Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	w.Events = h:require("ReplicatedStorage.Shared.Config.Events")
	w.Features = h:require("ReplicatedStorage.Shared.Config.Features")
	w.Species = h:require("ReplicatedStorage.Shared.Config.Species")
	w.Mutations = h:require("ReplicatedStorage.Shared.Config.Mutations")
	w.Features.reset()
	return w
end

-- Profil prêt à jouer : accueil fini, mode choisi (rush), squishies donnés (liste { s, m, st, z, at, bf })
function Brains.profile(w, opts)
	opts = opts or {}
	local d = Bots.profile(w, {
		coins = opts.coins or 0,
		onboarding = { step = 11, done = true, demoDone = true },
		lastOnline = 0,
		R = opts.R or 0,
	})
	d.mode = {
		rush = opts.rush == true,
		chosen = opts.rush ~= nil,
		changedAt = 0,
		cardShown = opts.cardShown ~= false,
		postBoopCardShown = opts.postBoopCardShown == true,
	}
	d.stats.playSeconds = opts.playSeconds or 3600
	local n = 0
	for _, spec in opts.squishies or {} do
		n += 1
		local uid = tostring(n)
		d.squishies[uid] = {
			s = spec.s or 2,
			m = spec.m or 0,
			st = spec.st or 0,
			z = spec.z or 10,
			zg = 0,
			bf = spec.bf or 0,
			lk = false,
			o = "",
			at = spec.at or "pen",
			b = 0,
			gd = 0,
		}
	end
	d.nextUid = n + 1
	-- places d'enclos pour tous les squishies donnés (capacité 4 + niveau de la dalle Enclos)
	d.tiles.pens = math.max(d.tiles.pens or 0, math.clamp(n - 4, 0, 14))
	if opts.tiles then
		for k, v in opts.tiles do
			d.tiles[k] = v
		end
	end
	if opts.edit then
		opts.edit(d)
	end
	return d
end

-- Un joueur rejoint (profil sauvegardé d'abord si opts.profile), chargé, placé, prêt
function Brains.join(w, userId, opts)
	opts = opts or {}
	if opts.profile then
		Bots.saveProfile(w, userId, opts.profile)
	end
	local p = Bots.join(userId, { name = opts.name, wait = true })
	w.h:settle(3)
	for _ = 1, 20 do
		if w.Ranch.isReady(p) then
			break
		end
		w.h:settle(1)
	end
	if opts.at then
		Bots.place(p, opts.at)
	end
	return p
end

-- n ticks complets (Heartbeat → ChaseService.tick), cerveaux compris
function Brains.frames(w, n, brain)
	Bots.use(w)
	Bots.frames(n, brain or Bots.brains)
end

-- Position monde debout au point local (x, z) du ranch d'un joueur
function Brains.atRanch(w, p, x, z)
	local q = w.WL.toWorld(w.Ranch.slotOf(p), w.V3.new(x, 0, z))
	return Bots.ground(q.X, q.Z)
end

-- Créatures actives (ChaseService.active) d'une sorte
function Brains.creatures(w, kind)
	local out = {}
	for _, spawn in w.Chase.active() do
		if kind == nil or spawn.kind == kind then
			table.insert(out, spawn)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- Position au sol d'une créature diffusée à l'instant t (même code que le client)
function Brains.creaturePos(w, spawn, t)
	local pos = w.SeededPath.fromSpawn(spawn)(t)
	return w.V3.new(pos.X, w.WL.groundY(pos.X, pos.Z), pos.Z)
end

-- Place un joueur debout sur la créature (monde vrai et vu, comme un client qui l'a rejointe)
function Brains.standOn(w, p, spawn, t, offset)
	local c = Brains.creaturePos(w, spawn, t or w.Clock.now())
	local o = offset or w.V3.zero
	local target = Bots.ground(c.X + o.X, c.Z + o.Z)
	w.h:moveTo(p, target)
	return target
end

-- Zéro trace (doublures meta comprises)
function Brains.problems(w)
	local out = {}
	for _, line in w.meta.caught do
		table.insert(out, line)
	end
	for _, line in w.h.errors do
		table.insert(out, line)
	end
	for _, line in w.h:warnings() do
		table.insert(out, line)
	end
	return out
end

-- Ensemble des états ouverts de tous les services (invariant 6) et ceux qui ont dépassé leur délai
function Brains.openStates(w)
	local out = {}
	for _, name in
		{
			"RanchService",
			"SquishyService",
			"EventService",
			"RushService",
			"SplorchService",
			"ChaseService",
		}
	do
		local svc = w.h:require(S .. name)
		for _, st in svc.openStates() do
			table.insert(
				out,
				{ service = name, name = st.name, startedAt = st.startedAt, player = st.player }
			)
		end
	end
	return out
end

function Brains.expiredStates(w, now)
	local out = {}
	for _, st in Brains.openStates(w) do
		local ok, expired = pcall(w.StateTimeouts.expired, st.name, st.startedAt, now)
		if not ok then
			table.insert(out, st.service .. ":" .. st.name .. " (état inconnu)")
		elseif expired then
			table.insert(out, string.format("%s:%s depuis %.2f s", st.service, st.name, now - st.startedAt))
		end
	end
	return out
end

-- -------------------------------------------------------------------------------------------
-- Cerveaux (robot de longue durée) : chaque cerveau reçoit p à chaque tick
-- -------------------------------------------------------------------------------------------

-- Générateur pseudo-aléatoire à graine (Park-Miller), indépendant du moteur
local function rng(seed)
	local state = math.floor(seed or 1) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local r = {}
	function r:NextNumber(a, b)
		state = (state * 16807) % 2147483647
		local u = state / 2147483647
		if a ~= nil then
			return a + (b - a) * u
		end
		return u
	end
	function r:NextInteger(a, b)
		return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1)))
	end
	return r
end
Brains.rng = rng

-- Uids d'un joueur à un lieu donné
local function uidsAt(w, p, at)
	local out = {}
	for uid, rec in w.Squishy.records(p) do
		if rec.at == at then
			table.insert(out, uid)
		end
	end
	table.sort(out)
	return out
end
Brains.uidsAt = uidsAt

-- Joueur complet : presse chez lui, achète, fusionne, poursuit les créatures (□ et bond), boope au
-- Rush, presse le MEGA, monte, change de mode, lance son Grand Splorch ; erre entre ses actions
function Brains.player(w, seed)
	local r = rng(seed or 1)
	local target = nil
	local nextAction = 0
	return function(p)
		local now = w.Clock.now()
		local slot = w.Ranch.slotOf(p)
		if slot == 0 then
			return
		end
		-- déplacement : vers une créature visible proche, sinon vers un point du ranch ou de la ville
		local chase = nil
		local best = 60
		local root = Bots.rootOf(p)
		if root == nil then
			return
		end
		for _, spawn in w.Chase.active() do
			if not spawn.personal or spawn.ownerSlot == slot then
				local c = Brains.creaturePos(w, spawn, now)
				local d = (c - root.Position).Magnitude
				if d < best then
					best, chase = d, spawn
				end
			end
		end
		if chase then
			local c = Brains.creaturePos(w, chase, now)
			Bots.stepToward(p, Bots.ground(c.X, c.Z))
			if best < 5 then
				Bots.fire("Catch", p, chase.id, now)
			elseif best < 14 and r:NextNumber() < 0.05 then
				local d = (c - root.Position)
				Bots.fire(
					"Leap",
					p,
					d.X / math.max(1e-6, d.Magnitude),
					d.Z / math.max(1e-6, d.Magnitude),
					now
				)
			end
		else
			if target == nil or Bots.stepToward(p, target) then
				local choice = r:NextNumber()
				if choice < 0.6 then
					target = Brains.atRanch(w, p, r:NextNumber(-20, 20), r:NextNumber(20, 50))
				elseif choice < 0.8 then
					target = Bots.ground(r:NextNumber(-60, 60), r:NextNumber(-60, 60))
				else
					-- devant sa propre clôture, côté ranch (propriétaire proche pendant un Rush)
					local fp = w.WL.fencePoint(slot, 1)
					target = Bots.ground(fp.X, fp.Z)
				end
			end
		end
		if now < nextAction then
			return
		end
		nextAction = now + r:NextNumber(0.2, 1.5)
		local pens = uidsAt(w, p, "pen")
		local roll = r:NextNumber()
		if roll < 0.35 and #pens > 0 then
			Bots.fire("Press", p, pens[r:NextInteger(1, #pens)], now)
		elseif roll < 0.42 then
			Bots.fire("BuyTile", p, ({ "snack", "decor", "pens" })[r:NextInteger(1, 3)])
		elseif roll < 0.46 then
			Bots.fire("FuseAll", p)
		elseif roll < 0.50 then
			Bots.fire("Ride", p, r:NextNumber() < 0.5)
		elseif roll < 0.53 then
			Bots.fire("SetMode", p, r:NextNumber() < 0.7)
		elseif roll < 0.62 then
			Bots.fire("MegaPress", p, now)
		elseif roll < 0.72 then
			-- boop : squishy d'un autre ranch à la clôture
			for other in pairs(w.Chase.actors()) do
				local oslot = w.Ranch.slotOf(other)
				if other ~= p and oslot ~= 0 then
					local uids, reason = w.Ranch.fenceOf(oslot)
					if reason == "rush" and #uids > 0 then
						Bots.fire("BoopHold", p, other.UserId, uids[1], true)
						-- côté rue de la place n° 1 de la clôture (local Z < 0), à portée de boop
						local lp = w.WL.fencePointsLocal()[1]
						local q = w.WL.toWorld(oslot, w.V3.new(lp.X, 0, -2))
						target = Bots.ground(q.X, q.Z)
						break
					end
				end
			end
		elseif roll < 0.74 and #pens > 0 then
			Bots.fire("GrandSplorch", p, false, pens[1])
		elseif roll < 0.76 then
			Bots.fire("PickUp", p, pens[1] or "1")
		elseif roll < 0.78 then
			Bots.fire("Throw", p)
		elseif roll < 0.80 then
			Bots.fire("PutDown", p)
		end
	end
end

-- Cavalier : monte et descend, court et saute (position vraie relevée comme un client)
function Brains.rider(w, seed)
	local r = rng(seed or 2)
	local target = nil
	return function(p)
		if r:NextNumber() < 0.02 then
			Bots.fire("Ride", p, r:NextNumber() < 0.6)
		end
		if target == nil or Bots.stepToward(p, target, 2) then
			target = Bots.ground(r:NextNumber(-80, 80), r:NextNumber(-80, 80))
		end
	end
end

-- Tricheur borné (le robot vérifie qu'il ne gagne rien et ne casse rien) : spam de faux bonds et de
-- captures lointaines
function Brains.spammer(w, seed)
	local r = rng(seed or 3)
	return function(p)
		local now = w.Clock.now()
		Bots.fire("Leap", p, r:NextNumber(-1, 1), r:NextNumber(-1, 1), now + r:NextNumber(-1, 1))
		Bots.fire("Catch", p, r:NextInteger(1, 200), now - r:NextNumber(0, 2))
		Bots.fire("MegaPress", p, now)
	end
end

return Brains
