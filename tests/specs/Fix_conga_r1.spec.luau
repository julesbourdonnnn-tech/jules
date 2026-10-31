--!nocheck
-- Correctifs du paquet conga, revue QA (tour 1) :
--   * vol bas (HipHeight relevé, CFrame décalé de 4 à 14 studs) : la file ne doit jamais quitter le
--     sol, sinon ni un coupeur au sol ni un Gloomwisp ne la coupent (|Δy| ≤ Snip.MaxDy) ; MoveCheck
--     compte le vol bas prolongé (> sol + RootHeight + MaxDy pendant > HoverTime) comme infraction,
--     un vrai saut (JumpHeight 7,2) jamais.
-- Les services des autres paquets sont des doublures (même montage que CongaService.spec).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 37
	local DT = 0.1
	local S = "ServerScriptService.Server.Services."
	-- saut Roblox du projet (default.project.json) : JumpHeight 7,2, gravité 196,2
	local JUMP_HEIGHT = 7.2
	local GRAVITY = 196.2

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
		env.Tuning = h:require("ServerScriptService.Server.Conga.Tuning")

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

	-- Marche à vitesse constante jusqu'à `to` (un pas par tick), à la hauteur de `to`
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
	local function feed(env, p, n)
		local pos = rootOf(p).Position
		for _ = 1, n do
			env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), pos)
		end
		tick(env)
	end

	local function snips(env)
		local out = {}
		for _, e in env.h.log.allClientEvents do
			if e.remote == "SnipEvent" then
				table.insert(out, e.args[1])
			end
		end
		return out
	end

	-- Hauteur maximale d'une miette : la racine d'un personnage debout
	local function crumbTop(env, p)
		return env.WL.groundY(p.X, p.Z) + env.Tuning.RootHeight
	end

	local function expectLineOnGround(env, player)
		local nodes = env.Conga.nodePositions(player)
		expect(#nodes > 0).toBe(true)
		for _, node in nodes do
			expect(node.Y <= crumbTop(env, node) + 1e-6).toBe(true)
		end
	end

	-- MoveCheck « aveugle » au vol de `player` (un décor non modélisé sous ses pieds, par exemple) :
	-- isole la règle des miettes de CongaService de celle de MoveCheck
	local function blindMoveCheck(env, player, lift)
		local original = env.MoveCheck.step
		env.MoveCheck.step = function(p, pos, dt, now, groundY)
			if p == player then
				groundY += lift
			end
			return original(p, pos, dt, now, groundY)
		end
	end

	-- B (slot 2) attrape `n` Nebbies au sol en (x0, 3, 60), s'élève de `hover` studs puis marche en
	-- planant jusqu'à (x1, 3 + hover, 60) ; A (slot 1) attend au sol en (ax, 3, 52)
	local function hoverScenario(env, n, x0, x1, hover, ax, blind)
		local A = join(env, 1, 1)
		local B, dataB = join(env, 2, 2)
		dataB.upgrades.conga = math.max(0, n - 3)
		if blind then
			blindMoveCheck(env, B, hover)
		end
		place(env, B, env.V3.new(x0, 3, 60))
		place(env, A, env.V3.new(ax, 3, 52))
		tick(env)
		feed(env, B, n)
		tick(env, 35) -- exemptions terminées
		expect(env.Conga.lineLength(B)).toBe(n)
		-- montée en un tick (≤ 5,8 studs : un saut passe), puis marche en planant
		env.h:moveTo(B, env.V3.new(x0, 3 + hover, 60))
		tick(env)
		walk(env, B, env.V3.new(x1, 3 + hover, 60))
		tick(env, 2)
		return A, B
	end

	-- A traverse la file de B au sol (z = 52 → 68) à l'abscisse `x`
	local function crossAt(env, A, x)
		walk(env, A, env.V3.new(x, 3, 52))
		walk(env, A, env.V3.new(x, 3, 68))
	end

	-- =========================================================================================

	describe("Correctifs conga r1 › vol bas : la file reste au sol et se coupe", function()
		it("plané de 5 studs que MoveCheck ne voit pas : file au sol, un coupeur au sol la coupe", function()
			local env = setup()
			local A, B = hoverScenario(env, 10, 40, 80, 5, 66, true)
			expect(B:GetAttribute("Unstable") == true).toBe(false)
			expect(env.MoveCheck.violations(B)).toBe(0)
			expectLineOnGround(env, B)
			crossAt(env, A, 66)
			local list = snips(env)
			expect(#list).toBe(1)
			local s = list[1]
			expect(s.byWisp).toBe(false)
			expect(s.count).toBe(6)
			expect(env.Conga.lineLength(B)).toBe(s.cutIndex - 1)
			-- point touché (et Nebbies libres) au sol, pas en l'air
			expect(s.y <= env.WL.groundY(s.x, s.z) + env.Tuning.RootHeight + 1e-6).toBe(true)
		end)

		it("plané de 5 studs : un Gloomwisp (corps à sol + 3) coupe la file", function()
			local env = setup()
			local _, B = hoverScenario(env, 10, 40, 80, 5, 20, true)
			local y = env.WL.groundY(62, 60) + env.Tuning.RootHeight
			env.sweeps = { { id = 7, from = env.V3.new(62, y, 54), to = env.V3.new(62, y, 66) } }
			tick(env)
			local s = snips(env)[1]
			expect(s ~= nil).toBe(true)
			expect(s.byWisp).toBe(true)
			expect(s.wispId).toBe(7)
			expect(env.Conga.lineLength(B)).toBe(s.cutIndex - 1)
			expect(env.wispSnips[1].victim).toBe(B)
		end)

		it("plané réel : signalé par MoveCheck (retour, Unstable), sa file au sol est coupée", function()
			local env = setup()
			local violations = {}
			env.Signals.MoveViolation:Connect(function(p, n)
				if p ~= nil then
					table.insert(violations, n)
				end
			end)
			-- file constituée au sol de x = 20 à x = 55, puis 20 studs en planant à + 5
			local A, B = hoverScenario(env, 10, 20, 55, 0, 57, false)
			env.h:moveTo(B, env.V3.new(55, 8, 60))
			tick(env)
			walk(env, B, env.V3.new(75, 8, 60))
			tick(env, 5)
			expect(B:GetAttribute("Unstable")).toBe(true)
			expect(env.MoveCheck.violations(B) >= env.B.MoveCheck.FlagsToRewind).toBe(true)
			expect(#violations >= 1).toBe(true)
			expect(env.profiles[2].flags.strikes >= 1).toBe(true)
			expectLineOnGround(env, B)
			-- la partie de la file tracée en planant (nœuds 4 et 5, x > 55) se coupe au sol
			local nodes = env.Conga.nodePositions(B)
			expect(nodes[5].X > 55).toBe(true)
			local mid = (nodes[4] + nodes[5]) / 2
			crossAt(env, A, mid.X)
			local list = snips(env)
			expect(#list).toBe(1)
			expect(list[1].cutIndex).toBe(5)
			expect(env.Conga.lineLength(B)).toBe(4)
		end)

		it("un saut ne soulève jamais la file ; sauter par-dessus une file ne la coupe pas", function()
			local env = setup()
			local A, B = hoverScenario(env, 10, 30, 65, 0, 40, false)
			-- B saute sur place puis en avançant un peu : miettes au sol, aucune infraction
			local v0 = math.sqrt(2 * GRAVITY * JUMP_HEIGHT)
			local airtime = 2 * v0 / GRAVITY
			for hop = 1, 4 do
				local t = 0
				while t < airtime do
					t += DT
					local y = 3 + math.max(0, v0 * t - GRAVITY * t * t / 2)
					local x = rootOf(B).Position.X + (if hop > 2 then 0.5 else 0)
					env.h:moveTo(B, env.V3.new(x, y, 60))
					tick(env)
				end
			end
			env.h:moveTo(B, env.V3.new(rootOf(B).Position.X, 3, 60))
			tick(env, 5)
			expect(env.MoveCheck.violations(B)).toBe(0)
			expect(B:GetAttribute("Unstable") == true).toBe(false)
			expectLineOnGround(env, B)
			-- A saute par-dessus la file entre les nœuds 5 et 6 (sommet du saut au-dessus de la file) :
			-- pas de coupe (GDD §4.7, |Δy| > 4)
			local nodes = env.Conga.nodePositions(B)
			local mid = (nodes[5] + nodes[6]) / 2
			expect(env.WL.inHarbor(mid)).toBe(false)
			walk(env, A, env.V3.new(mid.X, 3, 56))
			tick(env, 5)
			local t = 0
			local z = 56
			while t < airtime do
				t += DT
				z += 1.4
				local y = 3 + math.max(0, v0 * t - GRAVITY * t * t / 2)
				env.h:moveTo(A, env.V3.new(mid.X, y, z))
				tick(env)
			end
			expect(z > 62.8).toBe(true)
			expect(env.MoveCheck.violations(A)).toBe(0)
			expect(#snips(env)).toBe(0)
			expect(env.Conga.lineLength(B)).toBe(10)
			-- au même endroit, retraverser au sol coupe bien la file (elle était là)
			env.h:moveTo(A, env.V3.new(mid.X, 3, z))
			tick(env, 5)
			walk(env, A, env.V3.new(mid.X, 3, 52))
			expect(#snips(env)).toBe(1)
			expect(env.Conga.lineLength(B)).toBe(4)
		end)
	end)

	describe("Correctifs conga r1 › MoveCheck : vol bas prolongé", function()
		local function mc()
			local h = Harness.new()
			return h:require("ServerScriptService.Server.Util.MoveCheck"),
				h:require("ReplicatedStorage.Shared.Config.Balance"),
				h:require("ServerScriptService.Server.Conga.Tuning"),
				h.globals.Vector3
		end

		-- joueur apparu à `start`, exemption terminée, premier pas normal à T0
		local function newPlayer(MC, B, start)
			local player = { Name = "Hover" }
			MC.noteSpeed(player, 16, T0 - 10)
			MC.reset(player, start, T0 - B.MoveCheck.Exemption)
			local p = { player = player, pos = start, now = T0 }
			assert(MC.step(player, start, DT, T0, 0) == "ok")
			return p
		end

		local function move(MC, p, delta, ground)
			p.now += DT
			p.pos = p.pos + delta
			return MC.step(p.player, p.pos, DT, p.now, ground or 0)
		end

		it("sauts enchaînés en marchant pendant 10 s (JumpHeight 7,2) : aucune infraction", function()
			local MC, B, _, V3 = mc()
			local p = newPlayer(MC, B, V3.new(-80, 3, 0))
			local v0 = math.sqrt(2 * GRAVITY * JUMP_HEIGHT)
			local airtime = 2 * v0 / GRAVITY
			local t = 0
			for _ = 1, 100 do
				t += DT
				-- sauts enchaînés : 0,05 s au sol entre deux sauts
				local phase = t % (airtime + 0.05)
				local y = 3 + math.max(0, v0 * phase - GRAVITY * phase * phase / 2)
				local target = V3.new(p.pos.X + 1.6, y, 0)
				expect(move(MC, p, target - p.pos)).toBe("ok")
			end
			expect(MC.violations(p.player)).toBe(0)
		end)

		it("juste sous le seuil (racine à sol + 6,9) pendant 5 s : jamais une infraction", function()
			local MC, B, Tuning, V3 = mc()
			local top = Tuning.RootHeight + B.Snip.MaxDy
			local p = newPlayer(MC, B, V3.new(60, 3, 0))
			expect(move(MC, p, V3.new(0, top - 0.1 - 3, 0))).toBe("ok")
			for _ = 1, 50 do
				expect(move(MC, p, V3.new(1.5, 0, 0))).toBe("ok")
			end
			expect(MC.violations(p.player)).toBe(0)
		end)

		it(
			"vol bas à sol + 8 : toléré 1 s, puis infraction comptée à chaque tick, retour à la 3e",
			function()
				local MC, B, Tuning, V3 = mc()
				expect(Tuning.HoverTime).toBe(1)
				local p = newPlayer(MC, B, V3.new(60, 3, 0))
				expect(move(MC, p, V3.new(0, 5, 0))).toBe("ok") -- racine à sol + 8
				for _ = 1, 9 do
					expect(move(MC, p, V3.new(1.4, 0, 0))).toBe("ok")
				end
				local lastOk = p.pos
				local verdicts = {}
				for _ = 1, 4 do
					local verdict, back = move(MC, p, V3.new(1.4, 0, 0))
					table.insert(verdicts, verdict)
					if verdict == "ok" then
						lastOk = p.pos
					elseif verdict == "rewind" then
						-- position non acceptée : retour vers la dernière position valide
						expect(back).toEqual(lastOk)
					end
				end
				-- au plus un tick de flottement sur la frontière des 1 s
				local firstFlag = table.find(verdicts, "flag")
				expect(firstFlag ~= nil and firstFlag <= 2).toBe(true)
				local rewindAt = table.find(verdicts, "rewind")
				expect(rewindAt).toBe(firstFlag + 2)
				expect(MC.violations(p.player)).toBe(3)
				expect(MC.recentRewinds(p.player, p.now)).toBe(1)
				expect(MC.isRestricted(p.player, p.now)).toBe(true)
				expect(MC.lastValid(p.player)).toEqual(lastOk)
			end
		)

		it("le sol compte : la même hauteur au-dessus d'une marche haute n'est pas un vol", function()
			local MC, B, _, V3 = mc()
			local p = newPlayer(MC, B, V3.new(60, 3, 0))
			move(MC, p, V3.new(0, 5, 0), 5)
			for _ = 1, 30 do
				expect(move(MC, p, V3.new(1.4, 0, 0), 5)).toBe("ok")
			end
			-- sol inconnu (NaN) : jamais d'infraction de hauteur
			for _ = 1, 30 do
				expect(move(MC, p, V3.new(1.4, 0, 0), 0 / 0)).toBe("ok")
			end
			expect(MC.violations(p.player)).toBe(0)
		end)

		it("exemption après une apparition : un vol bas n'y est jamais compté ni ramené", function()
			local MC, B, _, V3 = mc()
			local player = {}
			MC.noteSpeed(player, 16, T0)
			local pos = V3.new(30, 9, 30)
			MC.reset(player, pos, T0)
			local now = T0
			local verdicts = {}
			while now < T0 + B.MoveCheck.Exemption - DT do
				now += DT
				verdicts[MC.step(player, pos, DT, now, 0)] = true
			end
			expect(verdicts.rewind).toBeNil()
			expect(MC.violations(player)).toBe(0)
			expect(MC.recentRewinds(player, now)).toBe(0)
			-- après l'exemption, le vol bas compte (hoverSince repart du reset)
			local last
			for _ = 1, 3 do
				now += DT
				last = MC.step(player, pos, DT, now, 0)
			end
			expect(last).toBe("rewind")
			-- clear oublie le vol en cours
			MC.clear(player)
			expect(MC.step(player, pos, DT, now + DT, 0)).toBe("ok")
		end)
	end)
end
