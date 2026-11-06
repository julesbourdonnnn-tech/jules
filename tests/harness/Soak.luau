--!nocheck
-- Robot de longue durée (docs/04 §17.1 c, §17.2 ; paquet chase) : serveur complet, N robots (16 par
-- défaut) qui jouent `hours` heures de temps simulé (SOAK_HOURS, 0,5 h par défaut ; 6 h dans
-- scripts/soak.sh), contrôles À CHAQUE TICK :
--   1. Invariants.profile de chaque profil (nombres finis et bornés, capacités, Meilleurs Amis, tenues,
--      tableaux denses) ;
--   2. uids : portage, fuite, attente et clôture désignent un squishy existant du bon profil ; une fuite
--      n'a jamais lieu pour un squishy hors de l'enclos ;
--   3. aucun état ouvert au-delà de son délai (openStates de chaque service + StateTimeouts.expired) ;
--   4. plafonds journaliers (Balance.Caps, CapsPerFriend) ; ≤ 10 fuites du Rush sur le serveur ;
--      aucune Wobble Party pendant la sieste de Big Plop ; aucun squishy à la clôture pour un joueur en
--      file de Grand Splorch ;
--   5. instances, connexions et threads stables (± 5 % + marge fixe) après la mise en route
--      (Harness:counts() et handlers de Server/Signals) ;
--   6. temps du tick (os.clock réel) : la spec échoue au-delà de 10 ms en moyenne sous Lune ;
--   7. zéro erreur, zéro avertissement (doublures meta comprises : DiagnosticsService.reportCaught).
-- Départs et retours (profil persisté), réapparitions, gigue et gels réseau ; fermeture (BindToClose)
-- avec tous les joueurs présents.
--   local report = Soak.run(Harness, { players = 16, hours = Soak.hours() })
--   report.problems (liste vide = sain), report.msPerTick, report.ticks
-- Options v2.0 (lot A3, Soak des Plopettes ; rien de changé sans elles) : opts.flags (interrupteurs
-- ouverts après le démarrage), opts.edit(d, i) (profil de départ du robot i), opts.check(w, now)
-- (contrôles de plus à chaque tick : liste de problèmes).
local Bots = require("./Bots")
local Brains = require("./Brains")

local Soak = {}

-- Heures de temps simulé (variable d'environnement SOAK_HOURS, défaut 0,5)
function Soak.hours(default)
	local ok, process = pcall(require, "@lune/process")
	if ok and process and process.env then
		local raw = tonumber(process.env.SOAK_HOURS)
		if raw and raw > 0 then
			return raw
		end
	end
	return default or 0.5
end

local function signalHandlers(w)
	local n = 0
	for _, signal in w.Signals do
		if type(signal) == "table" and type(signal._handlers) == "table" then
			n += #signal._handlers
		end
	end
	return n
end

local function count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Profil de départ varié (mode, taille, R, collection)
local function profileFor(w, i, rng)
	local squishies = { { s = 1, z = 50 + i, bf = 1 } }
	local n = 3 + (i % 6)
	for k = 1, n do
		table.insert(squishies, { s = 2 + ((i + k) % 20), m = (i * k) % 4, z = 20 + rng:NextNumber(0, 2000) })
	end
	if i % 5 == 0 then
		-- prêt pour le Grand Splorch
		table.insert(squishies, { s = 3, z = 16000 })
	end
	return Brains.profile(w, {
		rush = i % 3 ~= 0,
		coins = math.floor(rng:NextNumber(0, 50000)),
		R = i % 4,
		squishies = squishies,
		edit = if w.soakEdit
			then function(d)
				w.soakEdit(d, i)
			end
			else nil,
	})
end

-- Contrôles d'un tick ; rend la liste des problèmes trouvés (vide = sain)
local function checkTick(w, Invariants, Balance, now)
	local out = {}
	for _, p in w.players do
		if p.Parent ~= nil and w.DS.isLoaded(p) then
			local data = w.DS.get(p)
			for _, v in Invariants.profile(data) do
				table.insert(out, "profil " .. p.UserId .. " : " .. v)
			end
			local carried = w.Squishy.carried(p)
			if carried and data.squishies[carried] == nil then
				table.insert(out, "portage d'un uid absent " .. carried)
			end
			local waiting = w.Squishy.waiting(p)
			if waiting and data.squishies[waiting] == nil then
				table.insert(out, "attente d'un uid absent " .. waiting)
			end
			-- plafonds du jour
			if type(data.caps) == "table" then
				for key, cap in Balance.Caps do
					local v = data.caps[key]
					if type(v) == "number" and v > cap then
						table.insert(out, string.format("plafond %s dépassé (%s > %s)", key, v, cap))
					end
				end
				if type(data.caps.petSitBy) == "table" then
					for _, v in data.caps.petSitBy do
						if v > Balance.CapsPerFriend.petSit then
							table.insert(out, "plafond petSitBy dépassé")
						end
					end
				end
			end
			-- aucun squishy à la clôture pendant l'attente du Grand Splorch
			local slot = w.Ranch.slotOf(p)
			if waiting and slot ~= 0 then
				local uids, reason = w.Ranch.fenceOf(slot)
				if reason == "rush" and #uids > 0 then
					table.insert(out, "clôture du Rush pendant l'attente du Grand Splorch")
				end
			end
		end
	end
	-- fuites du Rush : uid existant, squishy marqué en fuite, ≤ 10 sur le serveur
	local escapes = 0
	for _, spawn in w.Chase.active() do
		if spawn.kind == "escape" then
			escapes += 1
			local owner = w.Ranch.playerAt(spawn.ownerSlot)
			if owner == nil then
				table.insert(out, "fuite sans propriétaire présent")
			elseif w.Squishy.get(owner, spawn.uid) == nil then
				table.insert(out, "fuite d'un uid absent " .. spawn.uid)
			end
		end
	end
	if escapes > w.Events.Rush.ServerMax then
		table.insert(out, "plus de 10 fuites du Rush sur le serveur")
	end
	-- aucune Wobble Party pendant la sieste
	local st = w.Event.state()
	if st.boost.kind == "wobble" and st.gauge.restUntil > now then
		table.insert(out, "Wobble Party pendant la sieste de Big Plop")
	end
	for _, line in Brains.expiredStates(w, now) do
		table.insert(out, "état expiré : " .. line)
	end
	return out
end

function Soak.run(Harness, opts)
	opts = opts or {}
	local hours = opts.hours or Soak.hours()
	local nPlayers = opts.players or 16
	local seed = opts.seed or 42
	local w = Brains.boot(Harness, {
		t0 = opts.t0 or (1800000000 + 3600 * 24 * 2 + 50),
		-- paquet meta livré : vrais services par défaut (opts.stubMeta = true : doublures)
		stubMeta = opts.stubMeta == true,
	})
	local Invariants = w.h:require("ReplicatedStorage.Shared.Logic.Invariants")
	local Balance = w.Balance
	for _, key in opts.flags or {} do
		assert(w.Features.set(key, true), key)
	end
	w.soakEdit = opts.edit
	local rng = Brains.rng(seed)
	local report = { problems = {}, ticks = 0, msPerTick = 0, counts = {} }
	local function problem(line)
		if #report.problems < 50 then
			table.insert(report.problems, string.format("t+%.1f : %s", w.Clock.now() - (opts.t0 or 0), line))
		end
	end

	-- arrivées
	local brainsOf = {}
	local function setBrain(p, i)
		local kind = i % 8
		local brain = if kind == 7
			then Brains.spammer(w, seed + i)
			elseif kind == 6 then Brains.rider(w, seed + i)
			else Brains.player(w, seed + i)
		brainsOf[p] = brain
		Bots.setBrain(p, brain)
	end
	for i = 1, nPlayers do
		local p = Brains.join(w, i, { profile = profileFor(w, i, rng) })
		setBrain(p, i)
		if i % 4 == 0 then
			Bots.jitter(p, 2 + (i % 2))
		end
	end

	-- mise en route : 30 s
	Brains.frames(w, 300)
	local base = w.h:counts()
	local baseHandlers = signalHandlers(w)
	report.counts.start = {
		instances = base.instances,
		connections = base.connections,
		threads = base.threads,
		handlers = baseHandlers,
	}

	local totalTicks = math.floor(hours * 3600 / Bots.DT)
	-- temps du tick du SERVEUR (ChaseService.tick, appelé par le Heartbeat) : les cerveaux des robots
	-- et le réseau simulé ne sont pas comptés
	local spent = 0
	local serverTicks = 0
	local tick = w.Chase.tick
	w.Chase.tick = function(now)
		local t0 = os.clock()
		tick(now)
		spent += os.clock() - t0
		serverTicks += 1
	end
	local nextId = nPlayers + 1
	Bots.use(w)
	for tick = 1, totalTicks do
		-- vie des joueurs : départs et retours (profil persisté), réapparitions, gels réseau
		if tick % 600 == 0 and #w.players > 0 then
			local p = w.players[rng:NextInteger(1, #w.players)]
			local roll = rng:NextNumber()
			if roll < 0.3 then
				local userId = p.UserId
				Bots.leave(p)
				w.h:settle(2)
				-- retour sur le même serveur (profil persisté par DataService)
				local back = Brains.join(w, userId)
				setBrain(back, userId)
			elseif roll < 0.6 then
				Bots.respawn(p)
			elseif roll < 0.8 then
				Bots.freeze(p, rng:NextNumber(0.7, 1.5))
			elseif #w.players < 16 then
				local q = Brains.join(w, nextId, { profile = profileFor(w, nextId, rng) })
				setBrain(q, nextId)
				nextId += 1
			end
		end
		Bots.frame(Bots.brains)
		report.ticks += 1
		local now = w.Clock.now()
		for _, line in checkTick(w, Invariants, Balance, now) do
			problem(line)
		end
		if opts.check then
			for _, line in opts.check(w, now) do
				problem(line)
			end
		end
		if #report.problems >= 50 then
			break
		end
		-- instances, connexions, threads stables (contrôlé toutes les 10 s : coût du parcours)
		if tick % 100 == 0 then
			local c = w.h:counts()
			local handlers = signalHandlers(w)
			local function stable(name, value, ref)
				if value > ref * 1.05 + 200 then
					problem(string.format("%s en hausse : %d → %d", name, ref, value))
				end
			end
			stable("instances", c.instances, base.instances)
			stable("connexions", c.connections, base.connections)
			stable("threads", c.threads, base.threads + 50)
			stable("handlers des Signals", handlers, baseHandlers)
		end
	end
	w.Chase.tick = tick
	report.serverTicks = serverTicks
	report.msPerTick = if serverTicks > 0 then spent / serverTicks * 1000 else 0
	local c = w.h:counts()
	report.counts.finish = {
		instances = c.instances,
		connections = c.connections,
		threads = c.threads,
		handlers = signalHandlers(w),
	}
	-- fermeture à pleine charge (BindToClose)
	w.h:close()
	w.h:settle(3)
	for _, line in Brains.problems(w) do
		problem("trace : " .. line)
	end
	report.world = w
	report.players = count(w.players)
	return report
end

return Soak
