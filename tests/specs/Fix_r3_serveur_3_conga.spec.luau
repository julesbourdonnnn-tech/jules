--!nocheck
-- Correctifs r3 « serveur 3 » — CongaService :
--   * un déplacement VALIDÉ de 40 studs ou plus (Dash + rafale après un gel réseau) ne remet plus
--     la trajectoire à zéro : miettes intermédiaires le long du pas, la file reste étalée sur son
--     chemin (autorité ET réseau) et reste coupable là où elle est dessinée
--   * RequestPath : une demande par slot et par seconde (une rafale de PathStream perdus ouvre un
--     trou dans toutes les files à la fois : toutes doivent être réparées)
--   * coupe sans Stardust (bouclier débutant, plafond du jour) : « +N libres ! » (snipDealtNoDust),
--     jamais « +0 ✦ » ; l'explication rookieNoDust au plus une fois par session
-- Les services des autres paquets sont des doublures (même montage que CongaService.spec).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 41
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

	-- Marche à vitesse constante jusqu'à `to` (un pas par tick)
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

	local function feedbackKeys(env, p)
		local out = {}
		for _, args in env.h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	local function countKey(list, key)
		local n = 0
		for _, k in list do
			if k == key then
				n += 1
			end
		end
		return n
	end

	-- File de `n` Nebbies du joueur `userId` (slot `slot`) le long de z = `z`, de x = 40 à x = 80
	local function lineAt(env, userId, slot, n, z)
		local p, data = join(env, userId, slot)
		data.upgrades.conga = math.max(0, n - 3)
		place(env, p, env.V3.new(40, 3, z))
		tick(env)
		feed(env, p, n)
		walk(env, p, env.V3.new(80, 3, z))
		tick(env, 2)
		return p, data
	end

	-- =========================================================================================

	describe("Fix r3 serveur 3 › grand pas validé : la file ne tombe jamais en tas", function()
		it(
			"Dash après 1,2 s d'arrêt puis 42 studs en un tick : file étalée, coupable, pas de signalement",
			function()
				local env = setup()
				local B, dataB = join(env, 2, 2)
				dataB.upgrades.conga = 7
				dataB.upgrades.stride = 20 -- Foulée maximale : 26 studs/s
				place(env, B, env.V3.new(-30, 3, 62))
				tick(env, 35) -- exemption terminée
				feed(env, B, 10)
				walk(env, B, env.V3.new(5, 3, 62))
				tick(env, 12) -- 1,2 s à l'arrêt
				expect(env.Conga.lineLength(B)).toBe(10)
				local before = env.Conga.nodePositions(B)
				local spanBefore = (before[1] - before[#before]).Magnitude
				expect(spanBefore > 15).toBe(true)
				env.h:fireServer("ReplicatedStorage.Remotes.Dash", B)
				local violations = env.MoveCheck.violations(B)
				env.h:moveTo(B, env.V3.new(47, 3, 62)) -- 42 studs en un tick
				tick(env)
				-- pas légal : accepté par MoveCheck (aucune infraction, aucun retour)
				expect(env.MoveCheck.violations(B)).toBe(violations)
				expect((env.MoveCheck.lastValid(B) - env.V3.new(47, 3, 62)).Magnitude < 0.01).toBe(true)
				local nodes = env.Conga.nodePositions(B)
				expect(#nodes).toBe(10)
				-- la file suit le chemin parcouru (5 → 47 puis l'ancien chemin), jamais un tas
				local span = (nodes[1] - nodes[#nodes]).Magnitude
				expect(span > 15).toBe(true)
				local distinct = {}
				for _, node in nodes do
					distinct[string.format("%.2f:%.2f", node.X, node.Z)] = true
				end
				local n = 0
				for _ in distinct do
					n += 1
				end
				expect(n).toBe(10)
				for _, node in nodes do
					expect(math.abs(node.Z - 62) < 0.5).toBe(true)
					expect(node.X <= 47 + 0.01).toBe(true)
				end
			end
		)

		it(
			"le réseau garde aussi le chemin : PathStream sans remise à zéro de la numérotation",
			function()
				local env = setup()
				local B, dataB = join(env, 2, 2)
				dataB.upgrades.conga = 7
				dataB.upgrades.stride = 20
				place(env, B, env.V3.new(-30, 3, 62))
				tick(env, 35)
				feed(env, B, 10)
				walk(env, B, env.V3.new(5, 3, 62))
				tick(env, 12)
				env.h:fireServer("ReplicatedStorage.Remotes.Dash", B)
				env.h:moveTo(B, env.V3.new(47, 3, 62))
				tick(env)
				tick(env, 2)
				-- un observateur qui demande le chemin du slot 2 reçoit toute la trajectoire : départ
				-- au-delà de 40 studs derrière la tête (une remise à zéro n'en garderait qu'un point)
				local O = join(env, 9, 9)
				tick(env)
				env.h:fireServer("ReplicatedStorage.Remotes.RequestPath", O, 2)
				local snaps = env.h:sentTo(O, "PathSnapshot")
				local last = snaps[#snaps]
				expect(last[1]).toBe(2)
				local _, runs = env.PC.decode(last[2])
				local points = 0
				local minX = math.huge
				for _, run in runs do
					for _, pt in run.points do
						points += 1
						minX = math.min(minX, pt.X)
					end
				end
				expect(points > 10).toBe(true)
				expect(minX < 47 - 40).toBe(true)
			end
		)
	end)

	describe("Fix r3 serveur 3 › RequestPath : une demande par slot et par seconde", function()
		it("11 slots troués dans la même image : 11 instantanés servis", function()
			local env = setup()
			local O = join(env, 1, 1)
			tick(env)
			for slot = 2, 12 do
				env.h:fireServer("ReplicatedStorage.Remotes.RequestPath", O, slot)
			end
			local snaps = env.h:sentTo(O, "PathSnapshot")
			expect(#snaps).toBe(11)
			local served = {}
			for _, args in snaps do
				served[args[1]] = true
			end
			for slot = 2, 12 do
				expect(served[slot]).toBe(true)
			end
			-- au-delà de 12 demandes (une par slot) dans la seconde : refusé
			for _ = 1, 5 do
				env.h:fireServer("ReplicatedStorage.Remotes.RequestPath", O, 3)
			end
			expect(#env.h:sentTo(O, "PathSnapshot")).toBe(12)
		end)
	end)

	describe("Fix r3 serveur 3 › coupe sans Stardust : jamais « +0 ✦ »", function()
		it("coupeur sous bouclier : « +N libres ! », explication une seule fois par session", function()
			local env = setup()
			local B = lineAt(env, 2, 2, 10, 60)
			local C = lineAt(env, 3, 3, 10, 76)
			local A = join(env, 1, 1)
			env.rookie[1] = true
			place(env, A, env.V3.new(66, 3, 52))
			tick(env, 35)
			walk(env, A, env.V3.new(66, 3, 68)) -- traverse la file de B
			tick(env, 20) -- recharge du coupeur
			walk(env, A, env.V3.new(66, 3, 84)) -- traverse la file de C
			local s = snips(env)
			expect(#s).toBe(2)
			expect(s[1].dust).toBe(0)
			expect(s[2].dust).toBe(0)
			local keys = feedbackKeys(env, A)
			expect(countKey(keys, "feedback.snipDealt")).toBe(0)
			expect(countKey(keys, "feedback.snipDealtNoDust")).toBe(2)
			expect(countKey(keys, "feedback.rookieNoDust")).toBe(1)
			local vars = nil
			for _, args in env.h:sentTo(A, "Feedback") do
				if args[1].key == "feedback.snipDealtNoDust" then
					vars = args[1].vars
				end
			end
			expect(vars.count).toBe(s[2].count)
			expect(vars.dust).toBeNil()
			expect(B ~= nil and C ~= nil).toBe(true)
		end)

		it("plafond du jour atteint : « +N libres ! » et capReached, jamais snipDealt à 0", function()
			local env = setup()
			env.dustCap = 0
			lineAt(env, 2, 2, 10, 60)
			local A = join(env, 1, 1)
			place(env, A, env.V3.new(66, 3, 52))
			tick(env, 35)
			walk(env, A, env.V3.new(66, 3, 68))
			expect(#snips(env)).toBe(1)
			local keys = feedbackKeys(env, A)
			expect(countKey(keys, "feedback.snipDealt")).toBe(0)
			expect(countKey(keys, "feedback.snipDealtNoDust")).toBe(1)
			expect(countKey(keys, "feedback.capReached")).toBe(1)
			expect(countKey(keys, "feedback.rookieNoDust")).toBe(0)
		end)

		it("vétéran avec Stardust : snipDealt inchangé", function()
			local env = setup()
			lineAt(env, 2, 2, 10, 60)
			local A = join(env, 1, 1)
			place(env, A, env.V3.new(66, 3, 52))
			tick(env, 35)
			walk(env, A, env.V3.new(66, 3, 68))
			local s = snips(env)
			expect(#s).toBe(1)
			expect(s[1].dust > 0).toBe(true)
			local keys = feedbackKeys(env, A)
			expect(countKey(keys, "feedback.snipDealt")).toBe(1)
			expect(countKey(keys, "feedback.snipDealtNoDust")).toBe(0)
		end)

		it("les deux langues ont la clé snipDealtNoDust", function()
			local env = setup()
			local Strings = env.h:require("ReplicatedStorage.Shared.Localization.Strings")
			local found = 0
			for _, lang in Strings do
				if type(lang) == "table" and lang["feedback.snipDealtNoDust"] ~= nil then
					found += 1
					expect(string.find(lang["feedback.snipDealtNoDust"], "{count}", 1, true) ~= nil).toBe(
						true
					)
				end
			end
			expect(found >= 2).toBe(true)
		end)
	end)
end
