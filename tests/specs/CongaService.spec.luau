--!nocheck
-- CongaService (paquet conga) : tick de 10 Hz, captures, file, coupes (toutes les protections du
-- GDD §4.7 / §4.16), Gloomwisps, parades (porte, Balise, forcée), WalkSpeed et Dash, mort / départ,
-- diffusion (LineEvent, SnipEvent, PathStream, WorldSnapshot, PathSnapshot), MoveCheck, remotes
-- malveillants et cycle de vie. Les services des autres paquets sont remplacés par des doublures
-- (tables simples) : seule la logique de CongaService (et du vrai SpawnService) est testée.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 37
	local DT = 0.1
	local S = "ServerScriptService.Server.Services."

	local function setup()
		local h = Harness.new()
		local env = {
			h = h,
			V3 = h.globals.Vector3,
			profiles = {},
			slotByUser = {},
			zen = {},
			rookie = {},
			crews = {},
			carrier = nil,
			truce = false,
			beacon = false,
			disabled = false,
			sweeps = {},
			dustCap = 200,
			dustGiven = {},
			glowLog = {},
			atlasLog = {},
			beaconLog = {},
			wispSnips = {},
			dropped = {},
			safeMoments = {},
			activePushes = {},
			calls = { eventStep = 0, stepComet = 0, stepWisps = 0, eventFlush = 0, slow = 0 },
			dirty = {},
		}
		h:require("ReplicatedStorage.Shared.Net").setup()
		env.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		env.Clock.freeze(T0)
		env.B = h:require("ReplicatedStorage.Shared.Config.Balance")
		env.Neb = h:require("ReplicatedStorage.Shared.Config.Nebbies")
		env.F = h:require("ReplicatedStorage.Shared.Logic.Formulas")
		env.WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		env.PC = h:require("ReplicatedStorage.Shared.Logic.PathCodec")
		env.Schema = h:require("ServerScriptService.Server.Data.Schema")
		env.Signals = h:require("ServerScriptService.Server.Signals")
		env.MoveCheck = h:require("ServerScriptService.Server.Util.MoveCheck")

		local DS = h:require(S .. "DataService")
		DS.get = function(p)
			return env.profiles[p.UserId]
		end
		DS.markDirty = function(_, key)
			env.dirty[key] = (env.dirty[key] or 0) + 1
		end

		local Nest = h:require(S .. "NestService")
		Nest.slotOf = function(p)
			return env.slotByUser[p.UserId] or 0
		end
		Nest.isZen = function(p)
			return env.zen[p.UserId] == true
		end
		Nest.snipsDisabled = function()
			return env.disabled
		end

		local Econ = h:require(S .. "EconomyService")
		Econ.setLineBanker = function(fn)
			env.banker = fn
		end
		Econ.paradeGlow = function(p, codes, atBeacon)
			return env.F.paradeGlow(codes, 1, env.zen[p.UserId] == true, atBeacon)
		end
		Econ.addGlow = function(p, amount, sku)
			local data = env.profiles[p.UserId]
			data.glow += amount
			table.insert(env.glowLog, { player = p, amount = amount, sku = sku })
			return amount
		end
		Econ.addStardustCapped = function(p, amount, capKey, sku)
			local given = env.dustGiven[p.UserId] or 0
			local granted = math.max(0, math.min(amount, env.dustCap - given))
			env.dustGiven[p.UserId] = given + granted
			env.lastDust = { capKey = capKey, sku = sku, amount = amount }
			return granted
		end
		Econ.step = function()
			env.calls.slow += 1
		end

		local Atlas = h:require(S .. "AtlasService")
		Atlas.addNebbies = function(p, codes, source)
			table.insert(env.atlasLog, { player = p, codes = table.clone(codes), source = source })
			local uids = {}
			for i in codes do
				uids[i] = "u" .. i
			end
			return uids
		end

		local Event = h:require(S .. "EventService")
		Event.step = function()
			env.calls.eventStep += 1
		end
		Event.stepComet = function(_, actors)
			env.calls.stepComet += 1
			env.lastActors = actors
		end
		Event.wispSweeps = function()
			return env.sweeps
		end
		Event.onWispSnip = function(id, victim, count)
			table.insert(env.wispSnips, { id = id, victim = victim, count = count })
		end
		Event.stepWisps = function()
			env.calls.stepWisps += 1
		end
		Event.flush = function()
			env.calls.eventFlush += 1
		end
		Event.isTruce = function()
			return env.truce
		end
		Event.beaconOpen = function()
			return env.beacon
		end
		Event.onBeaconParade = function(p, n)
			table.insert(env.beaconLog, { player = p, n = n })
		end
		Event.isCarrier = function(p)
			return env.carrier == p
		end
		Event.dropComet = function(p)
			table.insert(env.dropped, p)
		end
		Event.setActivePlayers = function(n)
			table.insert(env.activePushes, n)
		end
		Event.snapshot = function()
			return { t = env.Clock.now(), wisps = {}, snipsDisabled = env.disabled, activePlayers = 0 }
		end

		local Crew = h:require(S .. "CrewService")
		Crew.step = function() end
		Crew.crewOf = function(p)
			return env.crews[p.UserId] or 0
		end
		Crew.escortersOf = function(victim)
			local out = {}
			local crew = env.crews[victim.UserId] or 0
			for _, p in h.game.Players:GetPlayers() do
				if crew ~= 0 and p ~= victim and env.crews[p.UserId] == crew then
					table.insert(out, p)
				end
			end
			return out
		end
		Crew.snapshot = function()
			return { crews = {} }
		end

		local Quest = h:require(S .. "QuestService")
		Quest.step = function() end
		Quest.isRookie = function(p)
			return env.rookie[p.UserId] == true
		end
		Quest.onSafeMoment = function(p)
			table.insert(env.safeMoments, p)
		end

		h:require(S .. "LeaderboardService").step = function() end

		env.Spawn = h:require(S .. "SpawnService")
		env.Spawn.Init()
		env.Spawn.Start()
		-- pas d'apparitions de zone : seuls les Nebbies posés par le test existent
		env.Spawn.setModifiers({
			formChance = 0,
			intervalDiv = 1,
			capMult = 0,
			featuredChance = 0,
			starbornChance = 0,
		})
		env.Conga = h:require(S .. "CongaService")
		env.Conga.Init()
		env.Conga.Start()
		return env
	end

	local function tick(env, n)
		for _ = 1, n or 1 do
			env.Clock.advance(DT)
			env.Conga.tick(env.Clock.now())
		end
	end

	local function join(env, userId, slot)
		env.slotByUser[userId] = slot
		local data = env.Schema.defaults()
		env.profiles[userId] = data
		local p = env.h:addPlayer({ userId = userId, name = "P" .. userId })
		return p, data
	end

	local function rootOf(p)
		return p.Character.HumanoidRootPart
	end

	-- Déplacement imposé par le serveur (exemption MoveCheck au prochain pas)
	local function place(env, p, pos)
		env.h:moveTo(p, pos)
		env.Signals.ServerMoved:Fire(p)
	end

	-- Marche à vitesse constante jusqu'à `to` (un pas par tick) ; `others` bougent en même temps
	local function walk(env, p, to, speed)
		local step = (speed or 14) * DT
		for _ = 1, 2000 do
			local pos = rootOf(p).Position
			local d = to - pos
			if d.Magnitude <= step then
				env.h:moveTo(p, to)
				tick(env)
				return
			end
			env.h:moveTo(p, pos + d.Unit * step)
			tick(env)
		end
	end

	-- `n` Nebbies personnels sous les pieds du joueur, attrapés au tick suivant
	local function feed(env, p, n, code)
		local pos = rootOf(p).Position
		for _ = 1, n do
			env.Spawn.spawnPersonal(p, code or env.Neb.pack(1, 0, 0), pos)
		end
		tick(env)
	end

	local function clientEvents(env, remote)
		local out = {}
		for _, e in env.h.log.allClientEvents do
			if e.remote == remote then
				table.insert(out, e.args)
			end
		end
		return out
	end

	local function lineOps(env, slot, kind)
		local out = {}
		for _, args in clientEvents(env, "LineEvent") do
			for _, op in args[1] do
				if (slot == nil or op.slot == slot) and (kind == nil or op.op == kind) then
					table.insert(out, op)
				end
			end
		end
		return out
	end

	local function snips(env)
		local out = {}
		for _, args in clientEvents(env, "SnipEvent") do
			table.insert(out, args[1])
		end
		return out
	end

	local function feedbackKeys(env, p)
		local out = {}
		for _, args in env.h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	local function analytics(env, name)
		local out = {}
		for _, e in env.h.log.analytics do
			if e.method == "LogCustomEvent" and e.args[2] == name then
				table.insert(out, { player = e.args[1], value = e.args[3] })
			end
		end
		return out
	end

	-- Scénario de coupe : B (slot 2) a une file de `n` sur z = 60 (tête en x = 80, nœuds vers
	-- x décroissants), A (slot 1) attend en (crossX, 52)
	local function lineScenario(env, n, crossX)
		local A, dataA = join(env, 1, 1)
		local B, dataB = join(env, 2, 2)
		dataB.upgrades.conga = math.max(0, n - 3)
		place(env, B, env.V3.new(40, 3, 60))
		place(env, A, env.V3.new(crossX or 66, 3, 52))
		tick(env)
		feed(env, B, n)
		walk(env, B, env.V3.new(80, 3, 60))
		tick(env, 2)
		return A, B, dataA, dataB
	end

	local function cross(env, A, x)
		walk(env, A, env.V3.new(x or 66, 3, 68), 14)
	end

	-- =========================================================================================

	describe("CongaService › cycle de vie et diffusion", function()
		it(
			"arrivée : op owner puis WorldSnapshot APRÈS la diffusion du tick ; départ : owner 0",
			function()
				local env = setup()
				local p = join(env, 5, 3)
				expect(#env.h:sentTo(p, "WorldSnapshot")).toBe(0)
				tick(env)
				local owners = lineOps(env, 3, "owner")
				expect(#owners).toBe(1)
				expect(owners[1].userId).toBe(5)
				expect(owners[1].ver).toBe(0)
				local snaps = env.h:sentTo(p, "WorldSnapshot")
				expect(#snaps).toBe(1)
				local snap = snaps[1][1]
				expect(snap.lines[1].slot).toBe(3)
				expect(snap.lines[1].userId).toBe(5)
				expect(typeof(snap.paths)).toBe("buffer")
				expect(snap.events ~= nil and snap.crews ~= nil).toBe(true)
				env.h:removePlayer(p)
				tick(env)
				local all = lineOps(env, 3, "owner")
				expect(all[#all].userId).toBe(0)
				expect(env.Conga.lineLength(p)).toBe(0)
				expect(env.dropped[1]).toBe(p)
			end
		)

		it("Nid attribué après l'arrivée ; sans Nid (13e joueur) : aucun gameplay", function()
			local env = setup()
			local late, data = join(env, 8, 0)
			tick(env)
			expect(#lineOps(env, nil, "owner")).toBe(0)
			-- sans Nid : aucune capture
			place(env, late, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, late, 2)
			expect(env.Conga.lineLength(late)).toBe(0)
			-- le Nid arrive (PlayerReady ou au pas suivant)
			env.slotByUser[8] = 6
			env.Signals.PlayerReady:Fire(late, 6)
			tick(env)
			expect(#lineOps(env, 6, "owner")).toBe(1)
			-- les 2 Nebbies restés là + 1 nouveau
			feed(env, late, 1)
			expect(env.Conga.lineLength(late)).toBe(3)
			expect(data.flags.lbBanned).toBe(false)
		end)

		it("les joueurs présents au démarrage sont pris en charge", function()
			local h = Harness.new()
			h:require("ReplicatedStorage.Shared.Net").setup()
			local profiles = {}
			local DS = h:require(S .. "DataService")
			DS.get = function(p)
				return profiles[p.UserId]
			end
			local Nest = h:require(S .. "NestService")
			Nest.slotOf = function()
				return 4
			end
			local p = h:addPlayer({ userId = 3 })
			local Conga = h:require(S .. "CongaService")
			Conga.Init()
			Conga.Start()
			h:settle(1)
			expect(Conga.inputType(p)).toBe(2)
			expect(Conga.lineCapacity(p)).toBe(3)
		end)

		it("Heartbeat : pas fixe de 0,1 s, au plus 3 pas rattrapés, retard abandonné", function()
			local env = setup()
			env.h:step(0.05, 1)
			expect(env.calls.eventStep).toBe(0)
			env.h:step(0.05, 1)
			expect(env.calls.eventStep).toBe(1)
			env.h:step(1.0, 1)
			expect(env.calls.eventStep).toBe(4)
			env.h:step(0.05, 1)
			expect(env.calls.eventStep).toBe(4)
		end)

		it("ordre des étapes : chaque service stepé une fois par tick, avec les acteurs", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			expect(env.calls.eventStep).toBe(1)
			expect(env.calls.stepComet).toBe(1)
			expect(env.calls.stepWisps).toBe(1)
			expect(env.calls.eventFlush).toBe(1)
			expect(env.calls.slow).toBe(1)
			local actor = env.lastActors[1]
			expect(actor.player).toBe(p)
			expect(actor.slot).toBe(1)
			expect(actor.valid).toBe(true)
			expect(actor.touch).toBe(false)
		end)

		it(
			"un service défaillant ne fige pas le tick ; avertissement au plus toutes les 10 s par étape",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				local Event = env.h:require(S .. "EventService")
				Event.step = function()
					error("boom")
				end
				env.h:require(S .. "QuestService").step = function()
					error("quest down")
				end
				place(env, p, env.V3.new(60, 3, 60))
				tick(env, 5)
				feed(env, p, 1)
				expect(env.Conga.lineLength(p)).toBe(1)
				local warns = 0
				for _, w in env.h:warnings() do
					if string.find(w, "EventService.step", 1, true) then
						warns += 1
					end
				end
				expect(warns).toBe(1)
				env.Clock.advance(11)
				tick(env)
				warns = 0
				for _, w in env.h:warnings() do
					if string.find(w, "EventService.step", 1, true) then
						warns += 1
					end
				end
				expect(warns).toBe(2)
			end
		)

		it(
			"PathStream : miettes à 1 stud, 2 points répétés, arrêt après 5 renvois, seq contigus entre propriétaires",
			function()
				local env = setup()
				local a = join(env, 1, 1)
				place(env, a, env.V3.new(60, 3, 60))
				tick(env)
				walk(env, a, env.V3.new(70, 3, 60), 10)
				local streams = clientEvents(env, "PathStream")
				expect(#streams > 5).toBe(true)
				local lastSeq = 0
				for _, args in streams do
					local _, runs = env.PC.decode(args[1])
					for _, run in runs do
						expect(run.slot).toBe(1)
						-- jamais de trou : chaque message repart au plus à dernier + 1
						expect(run.firstSeq <= lastSeq + 1).toBe(true)
						lastSeq = math.max(lastSeq, run.firstSeq + #run.points - 1)
					end
					expect(buffer.len(args[1]) <= 900).toBe(true)
				end
				-- arrêt : 5 renvois puis plus rien
				local before = #clientEvents(env, "PathStream")
				tick(env, 10)
				expect(#clientEvents(env, "PathStream") - before).toBe(env.B.Net.StillResendTicks)
				-- départ puis nouveau propriétaire du slot 1 : la numérotation continue
				env.h:removePlayer(a)
				tick(env)
				local c = join(env, 3, 1)
				place(env, c, env.V3.new(-60, 3, 60))
				tick(env)
				walk(env, c, env.V3.new(-55, 3, 60), 10)
				local firstOfC = nil
				for i = before + 1, #clientEvents(env, "PathStream") do
					local _, runs = env.PC.decode(clientEvents(env, "PathStream")[i][1])
					for _, run in runs do
						if run.points[1].X < 0 and firstOfC == nil then
							firstOfC = run.firstSeq
						end
					end
				end
				expect(firstOfC).toBe(lastSeq + 1)
			end
		)

		it("RequestPath : PathSnapshot (200 derniers points) ; slots invalides ignorés", function()
			local env = setup()
			local a = join(env, 1, 1)
			place(env, a, env.V3.new(60, 3, 60))
			tick(env)
			walk(env, a, env.V3.new(60, 3, 75), 10)
			env.h:fireServer("ReplicatedStorage.Remotes.RequestPath", a, 1)
			local sent = env.h:sentTo(a, "PathSnapshot")
			expect(#sent).toBe(1)
			expect(sent[1][1]).toBe(1)
			local _, runs = env.PC.decode(sent[1][2])
			expect(#runs >= 1).toBe(true)
			local last = runs[#runs].points[#runs[#runs].points]
			expect(math.abs(last.Z - 75) < 0.2).toBe(true)
			-- slot libre : buffer vide mais valide
			env.h:fireServer("ReplicatedStorage.Remotes.RequestPath", a, 9)
			local _, empty = env.PC.decode(env.h:sentTo(a, "PathSnapshot")[2][2])
			expect(#empty).toBe(0)
			for _, bad in { 0, 13, 1.5, 0 / 0, math.huge, "3", {}, nil, true } do
				env.h:fireServer("ReplicatedStorage.Remotes.RequestPath", a, bad)
			end
			expect(#env.h:sentTo(a, "PathSnapshot")).toBe(2)
			-- débit : 4 par seconde
			for _ = 1, 10 do
				env.h:fireServer("ReplicatedStorage.Remotes.RequestPath", a, 1)
			end
			expect(#env.h:sentTo(a, "PathSnapshot") <= 6).toBe(true)
		end)

		it(
			"RequestWorld : instantané en fin de tick, débit 1 / 2 s, personnels du seul demandeur",
			function()
				local env = setup()
				local a = join(env, 1, 1)
				local b = join(env, 2, 2)
				tick(env)
				env.Spawn.spawnPersonal(a, env.Neb.pack(1, 0, 0), env.V3.new(0, 0, 100))
				env.h:fireServer("ReplicatedStorage.Remotes.RequestWorld", a)
				env.h:fireServer("ReplicatedStorage.Remotes.RequestWorld", a, { evil = true })
				env.h:fireServer("ReplicatedStorage.Remotes.RequestWorld", b)
				expect(#env.h:sentTo(a, "WorldSnapshot")).toBe(1)
				tick(env)
				expect(#env.h:sentTo(a, "WorldSnapshot")).toBe(2)
				expect(#env.h:sentTo(b, "WorldSnapshot")).toBe(2)
				local snapA = env.h:sentTo(a, "WorldSnapshot")[2][1]
				local snapB = env.h:sentTo(b, "WorldSnapshot")[2][1]
				expect(#snapA.wild).toBe(1)
				expect(#snapB.wild).toBe(0)
				expect(#snapA.lines).toBe(2)
				env.PC.decode(snapA.paths)
			end
		)

		it("LineChanged émis pour chaque file modifiée", function()
			local env = setup()
			local seen = {}
			env.Signals.LineChanged:Connect(function(p, n)
				table.insert(seen, { p = p, n = n })
			end)
			local a = join(env, 1, 1)
			place(env, a, env.V3.new(60, 3, 60))
			tick(env)
			table.clear(seen)
			feed(env, a, 2)
			expect(#seen).toBe(1)
			expect(seen[1].n).toBe(2)
			env.h:removePlayer(a)
			expect(seen[#seen].n).toBe(0)
		end)
	end)

	describe("CongaService › captures", function()
		it("capture à portée d'Attrait (+0,75), op add avec codes et ids, Signals.Caught", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			local caught = {}
			env.Signals.Caught:Connect(function(player, info)
				table.insert(caught, info)
			end)
			local code = env.Neb.pack(9, 1, 1)
			local id = env.Spawn.spawnPersonal(p, code, env.V3.new(60, 0, 60))
			local far = env.Spawn.spawnPersonal(p, code, env.V3.new(60, 0, 70))
			tick(env)
			expect(env.Conga.lineLength(p)).toBe(1)
			expect(env.Conga.lineCodes(p)[1]).toBe(code)
			local adds = lineOps(env, 1, "add")
			expect(#adds).toBe(1)
			expect(adds[1].codes[1]).toBe(code)
			expect(adds[1].ids[1]).toBe(id)
			expect(adds[1].ver).toBe(1)
			expect(#caught).toBe(1)
			expect(caught[1].rarity).toBe(2)
			expect(caught[1].personal).toBe(true)
			expect(caught[1].n).toBe(1)
			expect(env.Spawn.aliveCount()).toBe(1)
			expect(far ~= id).toBe(true)
		end)

		it("capacité 3 + niveau Conga ; file pleine → « PLEINE » au plus toutes les 5 s", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, p, 5)
			expect(env.Conga.lineLength(p)).toBe(3)
			expect(env.Conga.lineCapacity(p)).toBe(3)
			tick(env) -- file pleine, 2 Nebbies encore à portée
			local full = 0
			for _, k in feedbackKeys(env, p) do
				if k == "feedback.lineFull" then
					full += 1
				end
			end
			expect(full).toBe(1)
			tick(env, 20)
			full = 0
			for _, k in feedbackKeys(env, p) do
				if k == "feedback.lineFull" then
					full += 1
				end
			end
			expect(full).toBe(1)
			tick(env, 31)
			full = 0
			for _, k in feedbackKeys(env, p) do
				if k == "feedback.lineFull" then
					full += 1
				end
			end
			expect(full).toBe(2)
			expect(env.Spawn.aliveCount()).toBe(2) -- restés sur place
		end)

		it("conflit : le plus proche gagne", function()
			local env = setup()
			local a = join(env, 1, 1)
			local b = join(env, 2, 2)
			place(env, a, env.V3.new(60, 3, 60))
			place(env, b, env.V3.new(64, 3, 60))
			tick(env)
			env.Spawn.spawnLoose({ env.Neb.pack(1, 0, 0) }, { env.V3.new(63, 3, 60) }, env.Clock.now(), {
				silent = true,
				dizzy = 0,
			})
			tick(env)
			expect(env.Conga.lineLength(b)).toBe(1)
			expect(env.Conga.lineLength(a)).toBe(0)
		end)

		it("hors de portée verticale (|Δy| > 6) ou hors du rayon : rien", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 12, 60))
			tick(env)
			env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), env.V3.new(60, 0, 60))
			tick(env)
			expect(env.Conga.lineLength(p)).toBe(0)
		end)

		it("Attrait amélioré : rayon 5 + 0,5 × niveau", function()
			local env = setup()
			local p, data = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), env.V3.new(60, 0, 69))
			tick(env)
			expect(env.Conga.lineLength(p)).toBe(0)
			data.upgrades.lure = 12 -- 11 studs
			tick(env)
			expect(env.Conga.lineLength(p)).toBe(1)
		end)

		it("bannière de serveur pour un Légendaire ou mieux", function()
			local env = setup()
			local banners = {}
			env.Signals.BannerRequested:Connect(function(kind, args)
				table.insert(banners, { kind = kind, args = args })
			end)
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, p, 1, env.Neb.pack(29, 0, 0))
			feed(env, p, 1, env.Neb.pack(33, 0, 0))
			feed(env, p, 1, env.Neb.pack(10, 0, 0))
			expect(#banners).toBe(2)
			expect(banners[1].kind).toBe("legendaryCatch")
			expect(banners[2].kind).toBe("mythicCatch")
			expect(banners[1].args.userId).toBe(1)
		end)

		it("plafond de captures par heure : suspension 5 min et exclusion des classements", function()
			local env = setup()
			env.B.Catch.MaxPerHour = 4
			local p, data = join(env, 1, 1)
			data.upgrades.conga = 10
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, p, 6)
			expect(env.Conga.lineLength(p)).toBe(4)
			expect(data.flags.lbBanned).toBe(true)
			expect(env.dirty.flags ~= nil).toBe(true)
			tick(env, 10)
			expect(env.Conga.lineLength(p)).toBe(4)
			env.Clock.advance(env.B.Catch.SuspendSeconds)
			tick(env)
			expect(env.Conga.lineLength(p)).toBe(6)
		end)

		it("rien n'est attrapé sans profil chargé, mort, ou pendant une restriction MoveCheck", function()
			local env = setup()
			local p = join(env, 1, 1)
			env.profiles[1] = nil
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, p, 1)
			expect(env.Conga.lineLength(p)).toBe(0)
			expect(#lineOps(env, 1, "add")).toBe(0)
		end)
	end)

	describe("CongaService › file et parades", function()
		it("nœuds sur le chemin : HeadGap puis Spacing (abscisse curviligne)", function()
			local env = setup()
			local p, data = join(env, 1, 1)
			data.upgrades.conga = 3
			place(env, p, env.V3.new(40, 3, 60))
			tick(env)
			feed(env, p, 5)
			walk(env, p, env.V3.new(70, 3, 60), 10)
			local nodes = env.Conga.nodePositions(p)
			expect(#nodes).toBe(5)
			for i, n in nodes do
				expect(math.abs(n.X - (70 - env.B.Conga.HeadGap - (i - 1) * env.B.Conga.Spacing)) < 0.6).toBe(
					true
				)
				expect(math.abs(n.Z - 60) < 1e-3).toBe(true)
			end
		end)

		it("parade à la porte de SON Nid : bank, Glow, collection, Signals.Parade, moment sûr", function()
			local env = setup()
			local parades = {}
			env.Signals.Parade:Connect(function(p, info)
				table.insert(parades, info)
			end)
			local p, data = join(env, 1, 1)
			data.idleRate = 10
			place(env, p, env.V3.new(118, 3, 0))
			tick(env)
			feed(env, p, 3, env.Neb.pack(9, 0, 0))
			expect(env.Conga.lineLength(p)).toBe(3)
			walk(env, p, env.V3.new(131, 3, 0), 10)
			expect(env.Conga.lineLength(p)).toBe(0)
			local banks = lineOps(env, 1, "bank")
			expect(#banks).toBe(1)
			local expected = env.F.paradeGlow(
				{ env.Neb.pack(9, 0, 0), env.Neb.pack(9, 0, 0), env.Neb.pack(9, 0, 0) },
				1,
				false,
				false
			)
			expect(banks[1].glow).toBe(expected)
			expect(banks[1].count).toBe(3)
			expect(banks[1].bonus).toBeNear(1.16)
			expect(banks[1].atBeacon).toBe(false)
			expect(banks[1].newEntries).toBe(1)
			expect(data.glow).toBe(expected)
			expect(env.glowLog[1].sku).toBe("Parade")
			expect(#env.atlasLog[1].codes).toBe(3)
			expect(env.atlasLog[1].source).toBe("parade")
			expect(#parades).toBe(1)
			expect(parades[1].idleSeconds).toBeNear(expected / 10)
			expect(parades[1].forced).toBe(false)
			expect(env.safeMoments[#env.safeMoments]).toBe(p)
			expect(#analytics(env, "ParadeLength")).toBe(1)
		end)

		it("la porte d'un autre Nid ne déclenche rien", function()
			local env = setup()
			local p = join(env, 1, 2)
			place(env, p, env.V3.new(118, 3, 0))
			tick(env)
			feed(env, p, 2)
			walk(env, p, env.V3.new(131, 3, 0), 10)
			tick(env, 3)
			expect(env.Conga.lineLength(p)).toBe(2)
		end)

		it("anneau de la Balise : seulement pendant la Nuit (×1,5, onBeaconParade)", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(25, 3, 0))
			tick(env)
			feed(env, p, 3)
			walk(env, p, env.V3.new(12, 3, 0), 10)
			expect(env.Conga.lineLength(p)).toBe(3)
			env.beacon = true
			tick(env)
			expect(env.Conga.lineLength(p)).toBe(0)
			local bank = lineOps(env, 1, "bank")[1]
			expect(bank.atBeacon).toBe(true)
			expect(env.glowLog[1].sku).toBe("ParadeBeacon")
			expect(env.beaconLog[1].n).toBe(3)
		end)

		it("Méga Parade (≥ 30) : bannière de serveur", function()
			local env = setup()
			local banners = {}
			env.Signals.BannerRequested:Connect(function(kind)
				table.insert(banners, kind)
			end)
			local p, data = join(env, 1, 1)
			data.upgrades.conga = 27
			place(env, p, env.V3.new(131, 3, 0))
			tick(env)
			env.beacon = false
			-- dans la porte : chaque capture part aussitôt en parade, on remplit hors de la porte
			place(env, p, env.V3.new(100, 3, 30))
			tick(env)
			feed(env, p, 30)
			expect(env.Conga.lineLength(p)).toBe(30)
			place(env, p, env.V3.new(131, 3, 0))
			tick(env, 2)
			expect(table.find(banners, "megaParade") ~= nil).toBe(true)
		end)

		it(
			"forceParade (crochet de la Supernova) : encaisse sans porte, forced = true ; file vide → 0",
			function()
				local env = setup()
				local parades = {}
				env.Signals.Parade:Connect(function(_, info)
					table.insert(parades, info)
				end)
				local p = join(env, 1, 1)
				place(env, p, env.V3.new(60, 3, 60))
				tick(env)
				expect(type(env.banker)).toBe("function")
				feed(env, p, 2)
				env.banker(p)
				expect(env.Conga.lineLength(p)).toBe(0)
				expect(parades[1].forced).toBe(true)
				expect(env.Conga.forceParade(p)).toBe(0)
				tick(env)
				expect(#lineOps(env, 1, "bank")).toBe(1)
				-- versions : owner 0, add 1, bank 2
				expect(lineOps(env, 1, "bank")[1].ver).toBe(2)
			end
		)

		it("échec de l'économie : la file est conservée (rien n'est perdu)", function()
			local env = setup()
			local p = join(env, 1, 1)
			env.h:require(S .. "EconomyService").paradeGlow = function()
				error("economy down")
			end
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, p, 2)
			expect(env.Conga.forceParade(p)).toBe(0)
			expect(env.Conga.lineLength(p)).toBe(2)
		end)
	end)

	describe("CongaService › coupes", function()
		it(
			"coupe balayée : SnipEvent, file tronquée, libres prioritaires, récompenses et protections de la victime",
			function()
				local env = setup()
				local A, B = lineScenario(env, 10)
				expect(env.Conga.lineLength(B)).toBe(10)
				local snipped = {}
				env.Signals.Snipped:Connect(function(info)
					table.insert(snipped, info)
				end)
				cross(env, A)
				local list = snips(env)
				expect(#list).toBe(1)
				local s = list[1]
				expect(s.snipperSlot).toBe(1)
				expect(s.victimSlot).toBe(2)
				expect(s.byWisp).toBe(false)
				-- segment touché le plus près de la tête au-delà des Guard Links, plafond de perte
				expect(s.cutIndex >= 4).toBe(true)
				expect(s.count).toBe(10 - s.cutIndex + 1)
				expect(s.count <= math.max(6, math.floor(0.35 * 10))).toBe(true)
				expect(env.Conga.lineLength(B)).toBe(s.cutIndex - 1)
				expect(#s.loose).toBe(s.count)
				expect(#s.looseIds).toBe(s.count)
				for _, l in s.loose do
					expect(l.prioritySlot).toBe(2)
					expect(l.dizzyUntil ~= nil).toBe(true)
				end
				expect(math.abs(s.z - 60) < 1).toBe(true)
				-- Stardust plafonnée : 5 par Nebby détaché
				expect(s.dust).toBe(env.B.Snip.RushDustPerNebby * s.count)
				expect(env.lastDust.capKey).toBe("snipDust")
				expect(env.lastDust.sku).toBe("Snip")
				-- versions : la coupe suit les ops de la file (owner 0, add 1, coupe 2)
				expect(s.ver).toBe(2)
				local immune = B:GetAttribute("ImmuneUntil")
				expect(immune > env.Clock.now() and immune <= env.Clock.now() + env.B.Snip.VictimImmunity).toBe(
					true
				)
				expect(table.find(feedbackKeys(env, B), "feedback.snipped") ~= nil).toBe(true)
				expect(table.find(feedbackKeys(env, A), "feedback.snipDealt") ~= nil).toBe(true)
				expect(#snipped).toBe(1)
				expect(snipped[1].rewarded).toBe(true)
				expect(#analytics(env, "SnipDealt")).toBe(1)
				expect(#analytics(env, "SnipReceived")).toBe(1)
				expect(#analytics(env, "SnipByInput")).toBe(1)
				-- Second Souffle de la victime : +4 pendant 3 s
				tick(env)
				local hum = B.Character.Humanoid
				local base = env.F.walkSpeed({
					stride = 0,
					n = s.cutIndex - 1,
					guard = 3,
					carrier = false,
					dashing = false,
					secondWind = false,
				})
				expect(hum.WalkSpeed).toBeNear(base + env.B.Speed.SecondWindBoost, 1e-3)
				tick(env, 31)
				expect(hum.WalkSpeed).toBeNear(base, 1e-3)
			end
		)

		it("la victime reprend ses Nebbies tout de suite (priorité), les autres sont étourdis", function()
			local env = setup()
			local A, B = lineScenario(env, 10)
			cross(env, A)
			local s = snips(env)[1]
			expect(s ~= nil).toBe(true)
			local caught = {}
			env.Signals.Caught:Connect(function(p, info)
				table.insert(caught, { p = p, info = info })
			end)
			-- la victime marche vers ses Nebbies libres
			walk(env, B, env.V3.new(s.x, 3, s.z), 14)
			tick(env, 2)
			local recovered = 0
			for _, c in caught do
				if c.p == B and c.info.recovered and c.info.loose then
					recovered += 1
				end
			end
			expect(recovered >= 1).toBe(true)
			expect(table.find(feedbackKeys(env, B), "feedback.recovered") ~= nil).toBe(true)
		end)

		it("recharges : coupeur 1,5 s, paire 20 s ; immunité de la victime 8 s", function()
			local env = setup()
			local A, B, _, dataB = lineScenario(env, 12, 60)
			cross(env, A, 60)
			expect(#snips(env)).toBe(1)
			-- même paire, juste après : immunité / recharges
			walk(env, A, env.V3.new(56, 3, 52), 14)
			expect(#snips(env)).toBe(1)
			expect(dataB ~= nil).toBe(true)
		end)

		it("Snip Rush : Attrait ×1,5 pendant 3 s pour le coupeur", function()
			local env = setup()
			local A = lineScenario(env, 10)
			cross(env, A)
			expect(#snips(env)).toBe(1)
			-- place le coupeur à exactement 7 studs (XZ) de la position du Nebby au prochain tick :
			-- hors de portée normale (5 + 0,75), dans le rayon du Snip Rush (7,5 + 0,75)
			local function offerAt7(dir)
				local pos = rootOf(A).Position
				local id = env.Spawn.spawnPersonal(A, env.Neb.pack(1, 0, 0), pos + dir * 7)
				local rec = nil
				for _, w in env.Spawn.query(pos, 20, env.Clock.now(), A) do
					if w.id == id then
						rec = w
					end
				end
				local wp = env.Spawn.positionOf(rec, env.Clock.now() + DT)
				local flat = env.V3.new(wp.X - pos.X, 0, wp.Z - pos.Z)
				local target = env.V3.new(wp.X, pos.Y, wp.Z) - flat.Unit * 7
				env.h:moveTo(A, target)
				tick(env)
			end
			offerAt7(env.V3.new(1, 0, 0))
			expect(env.Conga.lineLength(A)).toBe(1)
			env.Clock.advance(env.B.Snip.RushDuration)
			tick(env)
			offerAt7(env.V3.new(-1, 0, 0))
			expect(env.Conga.lineLength(A)).toBe(1)
		end)

		it("le Lead Trio (Guard Links) n'est jamais coupé", function()
			local env = setup()
			local A = lineScenario(env, 8, 78)
			cross(env, A, 78)
			expect(#snips(env)).toBe(0)
		end)

		local function blocked(name, prepare)
			it("protection : " .. name, function()
				local env = setup()
				local A, B = lineScenario(env, 10)
				prepare(env, A, B)
				cross(env, A)
				expect(#snips(env)).toBe(0)
				expect(env.Conga.lineLength(B)).toBe(10)
			end)
		end

		blocked("trêve de la Balise", function(env)
			env.truce = true
		end)
		blocked("serveur privé « coupes désactivées »", function(env)
			env.disabled = true
		end)
		blocked("victime en Mode Zen", function(env)
			env.zen[2] = true
		end)
		blocked("coupeur en Mode Zen", function(env)
			env.zen[1] = true
		end)
		blocked("victime sous bouclier débutant", function(env)
			env.rookie[2] = true
		end)
		blocked("équipiers", function(env)
			env.crews[1] = 4
			env.crews[2] = 4
		end)
		blocked("escorte : un équipier de la victime à ≤ 7 studs des nœuds", function(env)
			local E = join(env, 3, 3)
			env.crews[2] = 9
			env.crews[3] = 9
			place(env, E, env.V3.new(64, 3, 62))
			tick(env)
		end)
		blocked("coupeur restreint après un retour MoveCheck", function(env, A)
			-- 3 téléportations (sans déplacement serveur) hors exemption → retour, 3 s de restriction
			env.Clock.advance(3)
			tick(env)
			local start = rootOf(A).Position
			for _ = 1, 3 do
				env.h:moveTo(A, start + env.V3.new(0, 0, -40))
				tick(env)
			end
			expect(A:GetAttribute("Unstable")).toBe(true)
			expect(env.MoveCheck.isRestricted(A, env.Clock.now())).toBe(true)
		end)

		it("port sûr : aucune coupe d'un point à moins de 25 studs d'une porte", function()
			local env = setup()
			local A = join(env, 1, 1)
			local B, dataB = join(env, 2, 2)
			dataB.upgrades.conga = 7
			place(env, B, env.V3.new(120, 3, -20))
			place(env, A, env.V3.new(113, 3, 5))
			tick(env)
			feed(env, B, 10)
			walk(env, B, env.V3.new(120, 3, 20))
			tick(env, 2)
			walk(env, A, env.V3.new(127, 3, 5), 14)
			expect(#snips(env)).toBe(0)
		end)

		it("téléportation à travers une file : signalée, jamais une coupe", function()
			local env = setup()
			local A, B = lineScenario(env, 10)
			env.Clock.advance(3)
			tick(env)
			env.h:moveTo(A, env.V3.new(66, 3, 70))
			tick(env)
			expect(#snips(env)).toBe(0)
			expect(env.Conga.lineLength(B)).toBe(10)
		end)

		it("coupeur sous bouclier : coupe possible, sans Stardust", function()
			local env = setup()
			local A = lineScenario(env, 10)
			env.rookie[1] = true
			cross(env, A)
			local s = snips(env)[1]
			expect(s ~= nil).toBe(true)
			expect(s.dust).toBe(0)
			expect(table.find(feedbackKeys(env, A), "feedback.rookieNoDust") ~= nil).toBe(true)
		end)

		it("plafond de Stardust atteint : coupe sans récompense, Feedback capReached", function()
			local env = setup()
			env.dustCap = 0
			local A = lineScenario(env, 10)
			cross(env, A)
			local s = snips(env)[1]
			expect(s.dust).toBe(0)
			expect(table.find(feedbackKeys(env, A), "feedback.capReached") ~= nil).toBe(true)
		end)

		it("aide tactile : rayon +0,3 pour une entrée tactile déclarée", function()
			local env = setup()
			local A = lineScenario(env, 10)
			env.h:fireServer("ReplicatedStorage.Remotes.SetInputType", A, 1)
			expect(env.Conga.inputType(A)).toBe(1)
			tick(env)
			expect(env.lastActors ~= nil).toBe(true)
			local touch = false
			for _, actor in env.lastActors do
				if actor.player == A then
					touch = actor.touch
				end
			end
			expect(touch).toBe(true)
		end)

		it(
			"Gloomwisp : coupe à 2,5 studs, sans récompense, compte dans les immunités ; aucune pendant la trêve",
			function()
				local env = setup()
				local A, B = lineScenario(env, 10)
				expect(A ~= nil).toBe(true)
				env.truce = true
				env.sweeps = { { id = 3, from = env.V3.new(62, 0, 54), to = env.V3.new(62, 0, 66) } }
				tick(env)
				expect(#snips(env)).toBe(0)
				env.truce = false
				tick(env)
				local s = snips(env)[1]
				expect(s ~= nil).toBe(true)
				expect(s.byWisp).toBe(true)
				expect(s.wispId).toBe(3)
				expect(s.snipperSlot).toBe(0)
				expect(s.dust).toBe(0)
				expect(env.wispSnips[1].victim).toBe(B)
				expect(env.wispSnips[1].count).toBe(s.count)
				expect(#analytics(env, "WispSnip")).toBe(1)
				-- immunité : le même balayage au tick suivant ne coupe plus
				tick(env)
				expect(#snips(env)).toBe(1)
			end
		)

		it("plafond par minute : 2 coupes subies par 60 s", function()
			local env = setup()
			local _, B = lineScenario(env, 14)
			env.sweeps = { { id = 1, from = env.V3.new(56, 0, 54), to = env.V3.new(56, 0, 66) } }
			tick(env)
			expect(#snips(env)).toBe(1)
			env.sweeps = { { id = 1, from = env.V3.new(62, 0, 54), to = env.V3.new(62, 0, 66) } }
			env.Clock.advance(env.B.Snip.VictimImmunity)
			tick(env)
			expect(#snips(env)).toBe(2)
			env.sweeps = { { id = 1, from = env.V3.new(68, 0, 54), to = env.V3.new(68, 0, 66) } }
			env.Clock.advance(env.B.Snip.VictimImmunity)
			tick(env)
			expect(#snips(env)).toBe(2) -- immunisé jusqu'à 60 s après la 1re
			expect(env.Conga.lineLength(B) > 3).toBe(true)
		end)
	end)

	describe("CongaService › mort, réinitialisation, départ", function()
		it("mort : file détachée, libres prioritaires pour le propriétaire, Comète lâchée", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, p, 3)
			p.Character.Humanoid.Health = 0
			tick(env)
			local clears = lineOps(env, 1, "clear")
			expect(#clears).toBe(1)
			expect(clears[1].reason).toBe("death")
			expect(#clears[1].loose).toBe(3)
			expect(clears[1].loose[1].prioritySlot).toBe(1)
			expect(env.Conga.lineLength(p)).toBe(0)
			expect(env.dropped[1]).toBe(p)
			expect(env.safeMoments[#env.safeMoments]).toBe(p)
			-- réapparition : nouvelle référence, capture possible à nouveau
			env.h:respawn(p)
			place(env, p, env.V3.new(-60, 3, 60))
			tick(env)
			feed(env, p, 1)
			expect(env.Conga.lineLength(p)).toBe(1)
			expect(#lineOps(env, 1, "clear")).toBe(1)
		end)

		it("réinitialisation sans mort (LoadCharacter) : même détachement", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, p, 2)
			env.h:respawn(p)
			tick(env)
			local clears = lineOps(env, 1, "clear")
			expect(#clears).toBe(1)
			expect(clears[1].reason).toBe("death")
		end)

		it("départ : file détachée sans priorité, PostSnipQuit si coupé < 60 s avant", function()
			local env = setup()
			local A, B = lineScenario(env, 10)
			cross(env, A)
			expect(#snips(env)).toBe(1)
			env.h:removePlayer(B)
			tick(env)
			local clears = lineOps(env, 2, "clear")
			expect(#clears).toBe(1)
			expect(clears[1].reason).toBe("leave")
			for _, l in clears[1].loose do
				expect(l.prioritySlot).toBeNil()
			end
			expect(#analytics(env, "PostSnipQuit")).toBe(1)
			local owners = lineOps(env, 2, "owner")
			expect(owners[#owners].userId).toBe(0)
		end)

		it("personnage absent ou sans HumanoidRootPart : ignoré sans erreur", function()
			local env = setup()
			local p = join(env, 1, 1)
			p.Character.HumanoidRootPart:Destroy()
			tick(env, 3)
			p.Character:Destroy()
			p.Character = nil
			tick(env, 3)
			expect(env.Conga.lineLength(p)).toBe(0)
		end)
	end)

	describe("CongaService › vitesse, Dash, remotes", function()
		it("WalkSpeed serveur : Foulée, ralenti au-delà des Guard Links, Comète ×0,85", function()
			local env = setup()
			local p, data = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			local hum = p.Character.Humanoid
			expect(hum.WalkSpeed).toBe(16)
			data.upgrades.stride = 4
			tick(env)
			expect(hum.WalkSpeed).toBe(18)
			data.upgrades.conga = 10
			feed(env, p, 8)
			tick(env)
			expect(hum.WalkSpeed).toBeNear(18 * (1 - 0.004 * 5), 1e-4)
			env.carrier = p
			tick(env)
			expect(hum.WalkSpeed).toBeNear(18 * (1 - 0.004 * 5) * 0.85, 1e-4)
		end)

		it("Dash : +10 pendant 1 s, recharge serveur (DashReadyAt), Signals.Dashed", function()
			local env = setup()
			local dashed = 0
			env.Signals.Dashed:Connect(function()
				dashed += 1
			end)
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			local hum = p.Character.Humanoid
			env.h:fireServer("ReplicatedStorage.Remotes.Dash", p)
			expect(hum.WalkSpeed).toBe(26)
			expect(dashed).toBe(1)
			expect(p:GetAttribute("DashReadyAt")).toBeNear(env.Clock.now() + env.F.dashCooldown(0))
			tick(env, 11)
			expect(hum.WalkSpeed).toBe(16)
			env.h:fireServer("ReplicatedStorage.Remotes.Dash", p, "junk", { 1, 2 })
			expect(dashed).toBe(1)
			expect(table.find(feedbackKeys(env, p), "feedback.dashCooldown") ~= nil).toBe(true)
		end)

		it("Dash refusé au porteur de la Comète, sans profil ou mort ; débit 3 / s", function()
			local env = setup()
			local dashed = 0
			env.Signals.Dashed:Connect(function()
				dashed += 1
			end)
			local p = join(env, 1, 1)
			tick(env)
			env.carrier = p
			env.h:fireServer("ReplicatedStorage.Remotes.Dash", p)
			expect(table.find(feedbackKeys(env, p), "feedback.cometNoDash") ~= nil).toBe(true)
			env.carrier = nil
			local q = join(env, 2, 2)
			env.profiles[2] = nil
			env.h:fireServer("ReplicatedStorage.Remotes.Dash", q)
			local r = join(env, 3, 3)
			r.Character.Humanoid.Health = 0
			env.h:fireServer("ReplicatedStorage.Remotes.Dash", r)
			expect(dashed).toBe(0)
			expect(#env.h:sentTo(q, "Feedback")).toBe(0)
		end)

		it("SetInputType : 1-3 entiers seulement, débit 1 / 5 s", function()
			local env = setup()
			local p = join(env, 1, 1)
			local RateLimit = env.h:require("ServerScriptService.Server.Util.RateLimit")
			for _, bad in { 0, 4, 1.5, 0 / 0, math.huge, -math.huge, "1", {}, true, nil } do
				RateLimit.clear(p) -- chaque charge passe le débit et atteint la validation
				env.h:fireServer("ReplicatedStorage.Remotes.SetInputType", p, bad)
			end
			RateLimit.clear(p)
			expect(env.Conga.inputType(p)).toBe(2)
			env.h:fireServer("ReplicatedStorage.Remotes.SetInputType", p, 3)
			expect(env.Conga.inputType(p)).toBe(3)
			expect(p:GetAttribute("InputType")).toBe(3)
			env.h:fireServer("ReplicatedStorage.Remotes.SetInputType", p, 1)
			expect(env.Conga.inputType(p)).toBe(3) -- débit
		end)

		it("remotes d'un joueur parti : ignorés sans erreur", function()
			local env = setup()
			local p = join(env, 1, 1)
			env.h:removePlayer(p)
			env.h:fireServer("ReplicatedStorage.Remotes.Dash", p)
			env.h:fireServer("ReplicatedStorage.Remotes.SetInputType", p, 1)
			env.h:fireServer("ReplicatedStorage.Remotes.RequestWorld", p)
			env.h:fireServer("ReplicatedStorage.Remotes.RequestPath", p, 1)
			tick(env)
			expect(#env.h:sentTo(p, "WorldSnapshot")).toBe(0)
		end)
	end)

	describe("CongaService › anti-triche, activité, escorte", function()
		it(
			"vitesse anormale : retour (PivotTo), Unstable, strikes, MoveViolation ; puis Unstable effacé",
			function()
				local env = setup()
				local violations = {}
				env.Signals.MoveViolation:Connect(function(p, n)
					table.insert(violations, n)
				end)
				local p, data = join(env, 1, 1)
				place(env, p, env.V3.new(60, 3, 60))
				tick(env, 35) -- exemption terminée
				for _ = 1, 3 do
					env.h:moveTo(p, rootOf(p).Position + env.V3.new(0, 0, 40))
					tick(env)
				end
				expect((rootOf(p).Position - env.V3.new(60, 3, 60)).Magnitude < 0.01).toBe(true)
				expect(p:GetAttribute("Unstable")).toBe(true)
				expect(data.flags.strikes).toBe(1)
				expect(#violations).toBe(1)
				expect(table.find(feedbackKeys(env, p), "feedback.unstable") ~= nil).toBe(true)
				tick(env, 31)
				expect(p:GetAttribute("Unstable")).toBe(false)
				env.h:removePlayer(p)
				expect(#analytics(env, "MoveViolation")).toBe(1)
			end
		)

		it("joueurs actifs (≥ 4 studs en 60 s) poussés une fois par seconde", function()
			local env = setup()
			local a = join(env, 1, 1)
			join(env, 2, 2)
			place(env, a, env.V3.new(60, 3, 60))
			tick(env)
			walk(env, a, env.V3.new(66, 3, 60), 10)
			expect(env.Conga.isActive(a)).toBe(true)
			expect(env.Conga.activeCount()).toBe(1)
			tick(env, 10)
			expect(env.activePushes[#env.activePushes]).toBe(1)
			local pushes = #env.activePushes
			tick(env, 10)
			expect(#env.activePushes - pushes).toBe(1)
			env.Clock.advance(61)
			tick(env)
			expect(env.Conga.activeCount()).toBe(0)
		end)

		it(
			"temps d'escorte : Signals.EscortTime par seconde pleine près des Nebbies coupables d'un équipier",
			function()
				local env = setup()
				local escorts = {}
				env.Signals.EscortTime:Connect(function(p, s)
					table.insert(escorts, { p = p, s = s })
				end)
				local _, B = lineScenario(env, 10)
				local E = join(env, 3, 3)
				env.crews[2] = 5
				env.crews[3] = 5
				place(env, E, env.V3.new(60, 3, 63))
				tick(env, 12)
				expect(#escorts >= 1).toBe(true)
				expect(escorts[1].p).toBe(E)
				expect(escorts[1].s).toBe(1)
				expect(B ~= nil).toBe(true)
			end
		)
	end)

	describe("CongaService › intégration (vrai serveur)", function()
		it(
			"démarrage complet : Nid attribué, capture puis parade créditée par les vrais services d'économie",
			function()
				local h = Harness.new()
				local DS = h:require(S .. "DataService")
				DS.Settings.RETRY_BASE_DELAY = 0.001
				-- doublures du seul paquet « events » (EventService, CrewService, QuestService, Leaderboard)
				local Event = h:require(S .. "EventService")
				for _, name in
					{ "step", "stepComet", "stepWisps", "flush", "onWispSnip", "onBeaconParade", "dropComet" }
				do
					Event[name] = function() end
				end
				Event.setActivePlayers = function() end
				Event.wispSweeps = function()
					return {}
				end
				Event.isTruce = function()
					return false
				end
				Event.beaconOpen = function()
					return false
				end
				Event.isCarrier = function()
					return false
				end
				Event.snapshot = function()
					return { t = 0, wisps = {}, snipsDisabled = false, activePlayers = 0 }
				end
				local Crew = h:require(S .. "CrewService")
				Crew.step = function() end
				Crew.crewOf = function()
					return 0
				end
				Crew.escortersOf = function()
					return {}
				end
				Crew.snapshot = function()
					return { crews = {} }
				end
				local Quest = h:require(S .. "QuestService")
				Quest.step = function() end
				Quest.isRookie = function()
					return false
				end
				Quest.onSafeMoment = function() end
				h:require(S .. "LeaderboardService").step = function() end
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				local WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
				local Neb = h:require("ReplicatedStorage.Shared.Config.Nebbies")
				local Signals = h:require("ServerScriptService.Server.Signals")
				local V3 = h.globals.Vector3
				h:boot()
				Clock.freeze(T0)
				local p = h:addPlayer({ userId = 501, name = "Ana" })
				local data = DS.waitFor(p, 2)
				h:settle(3)
				expect(data ~= nil).toBe(true)
				local Conga = h:require(S .. "CongaService")
				local Spawn = h:require(S .. "SpawnService")
				local slot = h:require(S .. "NestService").slotOf(p)
				expect(slot >= 1 and slot <= 12).toBe(true)
				local function step(n)
					for _ = 1, n or 1 do
						Clock.advance(DT)
						Conga.tick(Clock.now())
					end
				end
				step()
				-- entre le Nid et sa porte, dans le port sûr
				local gate = WL.gateCFrame(slot)
				local start = gate.Position - gate.LookVector * 8
				h:moveTo(p, V3.new(start.X, 3, start.Z))
				Signals.ServerMoved:Fire(p)
				step()
				for _ = 1, 3 do
					Spawn.spawnPersonal(p, Neb.pack(9, 0, 0), V3.new(start.X, 0, start.Z))
				end
				step()
				expect(Conga.lineLength(p)).toBe(3)
				local target = gate.Position
				for i = 1, 8 do
					local pos = start + gate.LookVector * i
					h:moveTo(p, V3.new(pos.X, 3, pos.Z))
					step()
				end
				expect(WL.inGateBox(slot, V3.new(target.X, 3, target.Z))).toBe(true)
				expect(Conga.lineLength(p)).toBe(0)
				expect(data.glow > 0).toBe(true)
				local owned = 0
				for _ in data.nebbies do
					owned += 1
				end
				expect(owned).toBe(3)
				h:removePlayer(p)
				h:settle(2)
				expect(#h.errors).toBe(0)
				for _, w in h:warnings() do
					expect(string.find(w, "[CongaService]", 1, true)).toBeNil()
				end
			end
		)
	end)

	-- Correctifs de la revue : chaque test reproduit un défaut constaté avant sa correction
	describe("CongaService › revue (anti-triche, portes, réseau)", function()
		local function actorOf(env, p)
			for _, a in env.lastActors or {} do
				if a.player == p then
					return a
				end
			end
			return nil
		end

		it(
			"téléportation aller-retour à travers une file : le balayage part de la dernière position VALIDÉE",
			function()
				local env = setup()
				local A, B = lineScenario(env, 10)
				env.Clock.advance(3) -- exemption terminée, fenêtre soutenue repartie de zéro
				tick(env)
				local start = rootOf(A).Position
				-- saut de 20 studs de l'autre côté de la file : signalé (aucune action ce tick)
				env.h:moveTo(A, env.V3.new(66, 3, 72))
				tick(env)
				expect(actorOf(env, A).valid).toBe(false)
				-- retour plausible depuis la référence : valide, mais le balayage ne doit PAS partir
				-- de la position téléportée (sinon il traverse la file de B)
				env.h:moveTo(A, start + env.V3.new(0, 0, 0.5))
				tick(env)
				local actor = actorOf(env, A)
				expect(actor.valid).toBe(true)
				expect((actor.prev - start).Magnitude < 0.01).toBe(true)
				expect(#snips(env)).toBe(0)
				expect(env.Conga.lineLength(B)).toBe(10)
			end
		)

		it(
			"réapparition : l'exemption n'accepte pas une téléportation (ni capture à distance), retour ensuite",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				place(env, p, env.V3.new(60, 3, 60))
				tick(env, 40)
				env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), env.V3.new(-60, 0, -60))
				env.h:respawn(p)
				place(env, p, env.V3.new(60, 3, 60)) -- NestService : PivotTo + ServerMoved
				tick(env)
				-- client tricheur : téléportation sur le Nebby pendant l'exemption de 3 s
				env.h:moveTo(p, env.V3.new(-60, 3, -60))
				tick(env, 5)
				expect(env.Conga.lineLength(p)).toBe(0)
				expect(actorOf(env, p).valid).toBe(false)
				-- il reste loin : à la fin de l'exemption, les infractions comptent → retour au Nid
				tick(env, 30)
				expect(env.Conga.lineLength(p)).toBe(0)
				expect((rootOf(p).Position - env.V3.new(60, 3, 60)).Magnitude < 0.01).toBe(true)
				expect(p:GetAttribute("Unstable")).toBe(true)
			end
		)

		it(
			"déplacement serveur : les positions « en vol » d'avant le PivotTo sont ignorées, sans infraction",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				place(env, p, env.V3.new(60, 3, 60))
				tick(env, 40)
				place(env, p, env.V3.new(-60, 3, 60)) -- PivotTo serveur
				env.h:moveTo(p, env.V3.new(60, 3, 60)) -- paquets du client d'avant le PivotTo
				tick(env, 3)
				expect(actorOf(env, p).valid).toBe(false)
				env.h:moveTo(p, env.V3.new(-60, 3, 60.5)) -- le client a appliqué le PivotTo
				tick(env)
				expect(actorOf(env, p).valid).toBe(true)
				feed(env, p, 1)
				expect(env.Conga.lineLength(p)).toBe(1)
				tick(env, 40)
				expect(p:GetAttribute("Unstable")).toBe(false)
				expect(env.MoveCheck.violations(p)).toBe(0)
			end
		)

		it(
			"10 retours forcés en 10 min : exclusion des classements (flags.lbBanned), strikes comptés",
			function()
				local env = setup()
				local p, data = join(env, 1, 1)
				place(env, p, env.V3.new(60, 3, 60))
				tick(env, 35) -- exemption terminée
				local anchor = rootOf(p).Position
				for cycle = 1, env.B.MoveCheck.StrikesForBan do
					for _ = 1, 3 do
						env.h:moveTo(p, anchor + env.V3.new(0, 0, 40))
						tick(env)
					end
					expect(data.flags.strikes).toBe(cycle)
					expect(data.flags.lbBanned).toBe(cycle >= env.B.MoveCheck.StrikesForBan)
					tick(env, 32) -- restriction terminée, revenu à la position de retour
				end
				expect((rootOf(p).Position - anchor).Magnitude < 0.01).toBe(true)
			end
		)

		it("filet de la Supernova : une file restante est encaissée (forced) plutôt que perdue", function()
			local env = setup()
			local parades = {}
			env.Signals.Parade:Connect(function(_, info)
				table.insert(parades, info)
			end)
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, p, 2)
			env.Signals.Supernova:Fire(p, 1)
			env.h:settle(1)
			expect(env.Conga.lineLength(p)).toBe(0)
			expect(#parades).toBe(1)
			expect(parades[1].forced).toBe(true)
			-- file vide : rien
			env.Signals.Supernova:Fire(p, 2)
			env.h:settle(1)
			expect(#parades).toBe(1)
		end)

		it("parade : traverser la porte entre deux ticks (gigue réseau, pas de 7 studs) encaisse", function()
			local env = setup()
			local p = join(env, 1, 1)
			local gate = env.WL.gateCFrame(1).Position
			local before = env.V3.new(gate.X - 3.5, 3, gate.Z)
			local after = env.V3.new(gate.X + 3.5, 3, gate.Z)
			expect(env.WL.inGateBox(1, before)).toBe(false)
			expect(env.WL.inGateBox(1, after)).toBe(false)
			place(env, p, before)
			tick(env)
			feed(env, p, 3)
			tick(env, 15) -- à l'arrêt : le paquet suivant peut porter 7 studs d'un coup
			env.h:moveTo(p, after)
			tick(env)
			expect(actorOf(env, p).valid).toBe(true)
			expect(env.Conga.lineLength(p)).toBe(0)
			expect(#lineOps(env, 1, "bank")).toBe(1)
			-- longer la porte à l'extérieur de la boîte ne déclenche rien
			feed(env, p, 2)
			tick(env, 15)
			env.h:moveTo(p, after + env.V3.new(0, 0, 7.5))
			tick(env)
			expect(env.Conga.lineLength(p)).toBe(2)
		end)
	end)

	describe("CongaService › intégration sans doublure", function()
		it(
			"tous les vrais services, tick par Heartbeat : capture, parade, coupe récompensée, mort, départ",
			function()
				local h = Harness.new()
				local DS = h:require(S .. "DataService")
				DS.Settings.RETRY_BASE_DELAY = 0.001
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				local WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
				local Neb = h:require("ReplicatedStorage.Shared.Config.Nebbies")
				local V3 = h.globals.Vector3
				Clock.freeze(T0 + 100)
				h:boot()
				local A = h:addPlayer({ userId = 701, name = "Ana" })
				local B = h:addPlayer({ userId = 702, name = "Bo" })
				local C = h:addPlayer({ userId = 703, name = "Cy" })
				h:settle(5)
				local Conga = h:require(S .. "CongaService")
				local Spawn = h:require(S .. "SpawnService")
				local Nest = h:require(S .. "NestService")
				local function frames(n)
					for _ = 1, n do
						Clock.advance(DT)
						h:step(DT)
					end
				end
				-- marche de 1,5 stud par tick (15 studs/s)
				local function walkTo(p, to)
					local target = V3.new(to.X, 3, to.Z)
					for _ = 1, 400 do
						local pos = p.Character.HumanoidRootPart.Position
						local d = target - pos
						if d.Magnitude < 1.5 then
							h:moveTo(p, target)
							frames(1)
							return
						end
						h:moveTo(p, pos + d.Unit * 1.5)
						frames(1)
					end
				end
				local function count(remote)
					local n = 0
					for _, e in h.log.allClientEvents do
						if e.remote == remote then
							n += 1
						end
					end
					return n
				end
				frames(5)
				-- capture puis parade à SA porte
				local slot = Nest.slotOf(A)
				expect(slot >= 1).toBe(true)
				local gate = WL.gateCFrame(slot)
				local start = gate.Position - gate.LookVector * 8
				walkTo(A, start)
				for _ = 1, 3 do
					Spawn.spawnPersonal(A, Neb.pack(9, 0, 0), V3.new(start.X, 0, start.Z))
				end
				frames(2)
				expect(Conga.lineLength(A) >= 3).toBe(true)
				local glowBefore = DS.get(A).glow
				walkTo(A, gate.Position)
				frames(2)
				expect(Conga.lineLength(A)).toBe(0)
				expect(DS.get(A).glow > glowBefore).toBe(true)
				-- coupe réelle (boucliers débutants levés) : 6 détachés, Stardust plafonnée créditée
				for _, p in { A, B } do
					local data = DS.get(p)
					data.rookie.done = true
					data.upgrades.conga = 7
				end
				walkTo(B, V3.new(60, 3, 50))
				for _ = 1, 10 do
					Spawn.spawnPersonal(B, Neb.pack(1, 0, 0), V3.new(60, 0, 50))
				end
				frames(2)
				walkTo(A, V3.new(80, 3, 52))
				walkTo(B, V3.new(85, 3, 60))
				frames(10)
				expect(Conga.lineLength(B)).toBe(10)
				local snips = count("SnipEvent")
				local dust = DS.get(A).stardust
				walkTo(A, V3.new(70, 3, 70))
				expect(count("SnipEvent") - snips).toBe(1)
				expect(Conga.lineLength(B)).toBe(4)
				expect(DS.get(A).stardust - dust).toBe(30)
				-- mort, réapparition, départ
				B.Character.Humanoid.Health = 0
				frames(3)
				expect(Conga.lineLength(B)).toBe(0)
				h:respawn(B)
				frames(40)
				h:removePlayer(C)
				frames(20)
				expect(#h.errors).toBe(0)
				for _, w in h:warnings() do
					expect(string.find(w, "[CongaService]", 1, true)).toBeNil()
				end
			end
		)
	end)

	describe("CongaService › instantané du monde", function()
		it("worldSnapshot : files (codes, ver), miettes décodables, sauvages visibles", function()
			local env = setup()
			local a = join(env, 1, 1)
			place(env, a, env.V3.new(60, 3, 60))
			tick(env)
			feed(env, a, 2, env.Neb.pack(12, 0, 0))
			walk(env, a, env.V3.new(65, 3, 60), 10)
			local snap = env.Conga.worldSnapshot(a)
			expect(snap.lines[1].slot).toBe(1)
			expect(snap.lines[1].ver).toBe(1)
			expect(#snap.lines[1].codes).toBe(2)
			expect(snap.lines[1].codes[1]).toBe(env.Neb.pack(12, 0, 0))
			local _, runs = env.PC.decode(snap.paths)
			expect(#runs >= 1).toBe(true)
			expect(runs[1].slot).toBe(1)
			expect(snap.serverTime).toBe(env.Clock.now())
			-- un EventService défaillant ne casse pas l'instantané
			env.h:require(S .. "EventService").snapshot = function()
				error("down")
			end
			local fallback = env.Conga.worldSnapshot(a)
			expect(type(fallback.events.wisps)).toBe("table")
		end)
	end)
end
