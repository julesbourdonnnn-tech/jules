--!nocheck
-- Correctifs « finition serveur anti-triche » (EventService, CongaService, NestService,
-- LeaderboardService) : chaque test reproduit un défaut constaté avant sa correction.
--   1. Récompenses de proximité de la Comète (+15 Stardust, 30 s de revenu à ≤ 20 studs) : le
--      point d'arrivée d'un tick en rafale (bond, instant de l'explosion déterministe) comptait ;
--      le filet sans acteurs lisait la racine brute du client.
--   2. catchable() (CongaService) appelait SpawnService sans protection : une erreur arrêtait
--      tout le reste du tick (Comète, coupes, parades, diffusion) pour tout le monde.
--   3. Serveur réglé au-delà de 12 places dans le Creator Hub : le 13e joueur restait sans Nid
--      (aucun jeu possible) indéfiniment ; renvoi poli après un délai, annulé si un Nid se libère.
--   4. Titre « Roi / Reine de la Conga » jamais retiré quand la semaine change en cours de
--      session (GDD §5.3 : le titre ne vaut que la semaine suivant le classement).

local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- =========================================================================================
	-- 1. Récompenses de proximité de la Comète (EventService seul, acteurs construits)
	-- =========================================================================================

	local TC = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC (impact de Comète, :00)
	local T1 = TC + 600

	local function eventBoot()
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(TC - 100)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		h:boot()
		return {
			h = h,
			V3 = h.globals.Vector3,
			Clock = Clock,
			DS = DS,
			E = h:require("ServerScriptService.Server.Services.EventService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			MC = h:require("ServerScriptService.Server.Util.MoveCheck"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
	end

	local function eventJoin(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, ctx.DS.get(p)
	end

	local function at(ctx, t)
		ctx.Clock.freeze(t)
		ctx.E.step(t)
	end

	local function actor(ctx, p, pos, prev, extra)
		local a = {
			player = p,
			userId = p.UserId,
			slot = ctx.N.slotOf(p),
			pos = pos,
			prev = prev or pos,
			valid = true,
			zen = false,
			crewId = 0,
			rookie = false,
			touch = false,
		}
		for k, v in extra or {} do
			a[k] = v
		end
		return a
	end

	-- MoveCheck du joueur : immobile 1,2 s à `from`, puis bond jusqu'à `to` (rafale : dette de budget)
	-- (hauteurs posées sur le sol de l'île : racine debout à sol + 3)
	local function blink(ctx, p, from, to, t)
		local WL = ctx.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local function standing(v)
			return ctx.V3.new(v.X, WL.groundY(v.X, v.Z) + 3, v.Z)
		end
		local a, b = standing(from), standing(to)
		ctx.MC.noteSpeed(p, 16, t - 10)
		ctx.MC.reset(p, a, t - 5)
		local now = t - 1.3
		while now < t - 0.05 do
			now += 0.1
			ctx.MC.step(p, a, 0.1, now, WL.groundY(a.X, a.Z))
		end
		local verdict, _, burst = ctx.MC.step(p, b, 0.1, t, WL.groundY(b.X, b.Z))
		assert(verdict == "ok" and burst == true, `bond non accepté en rafale : {verdict}`)
		return b
	end

	describe("Fix fin serveur anti-triche › récompenses de proximité de la Comète", function()
		it(
			"explosion : un bond dans les 20 studs (tick en rafale ou suivant) ne rapporte rien ; debout là, si",
			function()
				local ctx = eventBoot()
				local carrier = eventJoin(ctx, 1)
				local honest, dh = eventJoin(ctx, 2)
				local blinker, db = eventJoin(ctx, 3)
				local late, dl = eventJoin(ctx, 4)
				local flagged, df = eventJoin(ctx, 5)
				at(ctx, T1)
				local impact = ctx.EventClock.cometImpact(T1)
				local pa = ctx.V3.new(impact.X, 3, impact.Z)
				ctx.E.stepComet(T1, { actor(ctx, carrier, pa) })
				expect(ctx.E.carrier()).toBe(carrier)
				local tb = T1 + 75
				local far = pa + ctx.V3.new(0, 0, 36)
				local inside = pa + ctx.V3.new(0, 0, 12)
				-- bond au tick de l'explosion (acteur en rafale : pos = arrivée, prev = départ)
				blink(ctx, blinker, far, inside, tb)
				-- bond au tick PRÉCÉDENT : encore en dette, prev = pos = arrivée
				blink(ctx, late, far + ctx.V3.new(4, 0, 0), inside + ctx.V3.new(2, 0, 0), tb - 0.1)
				ctx.MC.step(late, inside + ctx.V3.new(2, 0, 0), 0.1, tb, 0)
				expect(ctx.MC.canAct(late, tb)).toBe(false)
				local h0, b0, l0, f0 = dh.stardust, db.stardust, dl.stardust, df.stardust
				at(ctx, tb)
				ctx.E.stepComet(tb, {
					actor(ctx, carrier, pa),
					actor(ctx, honest, pa + ctx.V3.new(0, 0, -15)),
					actor(ctx, blinker, inside, far, { valid = false }),
					actor(
						ctx,
						late,
						inside + ctx.V3.new(2, 0, 0),
						inside + ctx.V3.new(2, 0, 0),
						{ valid = false }
					),
					-- tick signalé (position refusée) d'un joueur qui peut agir : à sa dernière position
					-- validée (prev = pos), qui est bien dans les 20 studs
					actor(ctx, flagged, inside + ctx.V3.new(-3, 0, 0), nil, { valid = false }),
				})
				expect(ctx.E.snapshot().comet.phase).toBe("burst")
				expect(dh.stardust - h0).toBe(ctx.Balance.Comet.NearDust)
				expect(df.stardust - f0).toBe(ctx.Balance.Comet.NearDust)
				expect(db.stardust).toBe(b0)
				expect(dl.stardust).toBe(l0)
			end
		)

		it("encaissement : un bond à côté de la porte du porteur ne rapporte rien", function()
			local ctx = eventBoot()
			local carrier = eventJoin(ctx, 1)
			local honest, dh = eventJoin(ctx, 2)
			local blinker, db = eventJoin(ctx, 3)
			at(ctx, T1)
			local impact = ctx.EventClock.cometImpact(T1)
			local pa = ctx.V3.new(impact.X, 3, impact.Z)
			ctx.E.stepComet(T1, { actor(ctx, carrier, pa) })
			local WL = ctx.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
			local gate = WL.gateCFrame(ctx.N.slotOf(carrier)).Position
			local tb = T1 + 30
			local far = gate + ctx.V3.new(8, 0, 24)
			local inside = gate + ctx.V3.new(8, 0, 0)
			blink(ctx, blinker, far, inside, tb)
			local h0, b0 = dh.stardust, db.stardust
			at(ctx, tb)
			ctx.E.stepComet(tb, {
				actor(ctx, carrier, gate),
				actor(ctx, honest, gate + ctx.V3.new(-8, 0, 0)),
				actor(ctx, blinker, inside, far, { valid = false }),
			})
			expect(ctx.E.snapshot().comet.phase).toBe("banked")
			expect(dh.stardust - h0).toBe(ctx.Balance.Comet.NearDust)
			expect(db.stardust).toBe(b0)
		end)

		it(
			"filet sans acteurs : dernière position validée par MoveCheck, jamais la racine brute",
			function()
				local ctx = eventBoot()
				local honest, dh = eventJoin(ctx, 2)
				local raw, dr = eventJoin(ctx, 3)
				local debt, dd = eventJoin(ctx, 4)
				at(ctx, T1)
				local impact = ctx.EventClock.cometImpact(T1)
				local pa = ctx.V3.new(impact.X, 3, impact.Z)
				local near = pa + ctx.V3.new(0, 0, 10)
				local far = pa + ctx.V3.new(0, 0, 60)
				local tb = T1 + 77
				-- honnête : validé là où il est
				ctx.MC.reset(honest, near, tb - 5)
				ctx.h:moveTo(honest, near)
				-- racine brute posée près de l'impact par le client, référence MoveCheck loin
				ctx.MC.reset(raw, far, tb - 5)
				ctx.h:moveTo(raw, near + ctx.V3.new(2, 0, 0))
				-- arrivé près de l'impact par un bond : en dette de budget d'action
				blink(ctx, debt, near + ctx.V3.new(-2, 0, 24), near + ctx.V3.new(-2, 0, 0), tb - 0.1)
				ctx.h:moveTo(debt, near + ctx.V3.new(-2, 0, 0))
				local h0, r0, d0 = dh.stardust, dr.stardust, dd.stardust
				at(ctx, tb)
				expect(ctx.E.snapshot().comet.phase).toBe("burst")
				expect(dh.stardust - h0).toBe(ctx.Balance.Comet.NearDust)
				expect(dr.stardust).toBe(r0)
				expect(dd.stardust).toBe(d0)
				expect(#ctx.h.errors).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	-- 2. catchable() protégé : une erreur de SpawnService n'arrête plus le tick
	-- =========================================================================================

	local T0 = 1800000000 + 41
	local DT = 0.1
	local S = "ServerScriptService.Server.Services."

	-- même montage que CongaService.spec / Fix_r4_serveur_3 (doublures des autres paquets)
	local function congaSetup()
		local h = Harness.new()
		local env = { h = h, V3 = h.globals.Vector3, profiles = {}, slotByUser = {} }
		h:require("ReplicatedStorage.Shared.Net").setup()
		env.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		env.Clock.freeze(T0)
		env.Neb = h:require("ReplicatedStorage.Shared.Config.Nebbies")
		env.F = h:require("ReplicatedStorage.Shared.Logic.Formulas")
		env.WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		env.Schema = h:require("ServerScriptService.Server.Data.Schema")
		env.Signals = h:require("ServerScriptService.Server.Signals")
		local DS = h:require(S .. "DataService")
		DS.get = function(p)
			return env.profiles[p.UserId]
		end
		DS.markDirty = function() end
		local Nest = h:require(S .. "NestService")
		Nest.slotOf = function(p)
			return env.slotByUser[p.UserId] or 0
		end
		Nest.isZen = function()
			return false
		end
		Nest.snipsDisabled = function()
			return false
		end
		local Econ = h:require(S .. "EconomyService")
		Econ.setLineBanker = function() end
		Econ.paradeGlow = function(_, codes, atBeacon)
			return env.F.paradeGlow(codes, 1, false, atBeacon)
		end
		Econ.addGlow = function(_, amount)
			return amount
		end
		Econ.addStardustCapped = function(_, amount)
			return amount
		end
		Econ.step = function() end
		local Atlas = h:require(S .. "AtlasService")
		Atlas.addNebbies = function(_, codes)
			local uids = {}
			for i in codes do
				uids[i] = "u" .. i
			end
			return uids
		end
		local Event = h:require(S .. "EventService")
		Event.step = function() end
		Event.stepComet = function() end
		Event.wispSweeps = function()
			return {}
		end
		Event.onWispSnip = function() end
		Event.stepWisps = function() end
		Event.flush = function() end
		Event.isTruce = function()
			return false
		end
		Event.beaconOpen = function()
			return false
		end
		Event.onBeaconParade = function() end
		Event.isCarrier = function()
			return false
		end
		Event.dropComet = function() end
		Event.setActivePlayers = function() end
		Event.snapshot = function()
			return { t = env.Clock.now(), wisps = {}, snipsDisabled = false, activePlayers = 0 }
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
		env.Spawn = h:require(S .. "SpawnService")
		env.Spawn.Init()
		env.Spawn.Start()
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

	local function place(env, p, pos)
		env.h:moveTo(p, pos)
		env.Signals.ServerMoved:Fire(p)
	end

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

	local function feed(env, p, n)
		local pos = rootOf(p).Position
		for _ = 1, n do
			env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), pos)
		end
		tick(env)
	end

	local function count(env, remote, pred)
		local n = 0
		for _, e in env.h.log.allClientEvents do
			if e.remote == remote then
				if remote == "SnipEvent" then
					n += 1
				else
					for _, op in e.args[1] do
						if pred(op) then
							n += 1
						end
					end
				end
			end
		end
		return n
	end

	-- A (slot 1) traverse la file de B (slot 2, z = 60) ; P (slot 3) rentre parader à sa porte ;
	-- `sabotage(env)` casse SpawnService avant les déplacements
	local function scenario(sabotage)
		local env = congaSetup()
		local A = join(env, 1, 1)
		local B, dataB = join(env, 2, 2)
		local P = join(env, 3, 3)
		dataB.upgrades.conga = 7
		place(env, B, env.V3.new(40, 3, 60))
		place(env, A, env.V3.new(66, 3, 46))
		local gate = env.WL.gateCFrame(3)
		local look = gate.LookVector
		local g = env.V3.new(gate.Position.X, 3, gate.Position.Z)
		place(env, P, g - look * 10)
		tick(env)
		feed(env, B, 10)
		feed(env, P, 3)
		walk(env, B, env.V3.new(80, 3, 60))
		tick(env, 20)
		sabotage(env)
		local errors = 0
		local ok = pcall(function()
			for _ = 1, 30 do
				local pa = rootOf(A).Position
				if pa.Z < 73 then
					env.h:moveTo(A, pa + env.V3.new(0, 0, 1.4))
				end
				local pp = rootOf(P).Position
				local target = g + look * 6
				local d = target - pp
				if d.Magnitude > 1.4 then
					env.h:moveTo(P, pp + d.Unit * 1.4)
				end
				local tickOk = pcall(tick, env)
				if not tickOk then
					errors += 1
				end
			end
		end)
		return env, ok, errors
	end

	describe("Fix fin serveur anti-triche › catchable protégé (CongaService)", function()
		it(
			"SpawnService.positionOf lève une erreur : le tick continue, coupe et parade traitées",
			function()
				local env, ok, errors = scenario(function(env)
					-- un candidat (query intacte) dont la position lève une erreur dans catchable()
					local fake = env.Spawn.query
					env.Spawn.query = function(pos, radius, now, player)
						local list = fake(pos, radius, now, player)
						table.insert(list, { id = 987654, code = env.Neb.pack(1, 0, 0) })
						return list
					end
					env.Spawn.positionOf = function()
						error("panne simulée de SpawnService.positionOf")
					end
				end)
				expect(ok).toBe(true)
				expect(errors).toBe(0)
				expect(count(env, "SnipEvent")).toBe(1)
				expect(count(env, "LineEvent", function(op)
					return op.op == "bank" and op.slot == 3
				end)).toBe(1)
			end
		)

		it("SpawnService.canCatch lève une erreur : même chose", function()
			local env, ok, errors = scenario(function(env)
				local fake = env.Spawn.query
				env.Spawn.query = function(pos, radius, now, player)
					local list = fake(pos, radius, now, player)
					table.insert(list, { id = 987655, code = env.Neb.pack(1, 0, 0), pos = pos, t0 = now })
					return list
				end
				env.Spawn.positionOf = function(_, _)
					return env.V3.new(0, 3, 0)
				end
				env.Spawn.canCatch = function()
					error("panne simulée de SpawnService.canCatch")
				end
			end)
			expect(ok).toBe(true)
			expect(errors).toBe(0)
			expect(count(env, "SnipEvent")).toBe(1)
			expect(count(env, "LineEvent", function(op)
				return op.op == "bank" and op.slot == 3
			end)).toBe(1)
		end)
	end)

	-- =========================================================================================
	-- 3. Serveur trop grand : le joueur sans Nid est renvoyé poliment (NestService)
	-- =========================================================================================

	local function nestBoot()
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(TC)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		h:boot()
		local ctx = {
			h = h,
			DS = DS,
			N = h:require("ServerScriptService.Server.Services.NestService"),
			WS = h:require("ServerScriptService.Server.Services.WorldService"),
		}
		ctx.N.Settings.NoNestKickDelay = 0.3
		return ctx
	end

	local function nestJoin(ctx, userId, locale)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId, locale = locale })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p
	end

	local function kicksOf(ctx, p)
		local out = {}
		for _, k in ctx.h.log.kicks do
			if k.player == p then
				table.insert(out, k.message)
			end
		end
		return out
	end

	local function wait(ctx, seconds)
		task.wait(seconds)
		ctx.h:settle(2)
	end

	describe("Fix fin serveur anti-triche › serveur trop grand : renvoi poli sans Nid", function()
		it(
			"13e joueur (français) : slot 0 et Feedback, puis renvoyé après le délai, message dans sa langue",
			function()
				local ctx = nestBoot()
				for i = 1, 12 do
					nestJoin(ctx, i)
				end
				local late = nestJoin(ctx, 13, "fr-fr")
				expect(ctx.N.slotOf(late)).toBe(0)
				local feedback = {}
				for _, args in ctx.h:sentTo(late, "Feedback") do
					table.insert(feedback, args[1].key)
				end
				expect(feedback).toEqual({ "feedback.noNest" })
				expect(#kicksOf(ctx, late)).toBe(0) -- pas tout de suite
				wait(ctx, 0.5)
				expect(kicksOf(ctx, late)).toEqual({ "Cette île est pleine ! Rejoins un autre serveur." })
				local logged = false
				for _, e in ctx.h.log.analytics do
					if
						e.method == "LogCustomEvent"
						and e.args[1] == late
						and e.args[2] == "ServerFullKick"
					then
						logged = true
					end
				end
				expect(logged).toBe(true)
				expect(#ctx.h.errors).toBe(0)
			end
		)

		it(
			"anglais par défaut ; un Nid libéré pendant le délai lui est attribué et annule le renvoi",
			function()
				local ctx = nestBoot()
				local players = {}
				for i = 1, 12 do
					players[i] = nestJoin(ctx, i)
				end
				local a = nestJoin(ctx, 13)
				local b = nestJoin(ctx, 14, "en-gb")
				expect(ctx.N.slotOf(a)).toBe(0)
				expect(ctx.N.slotOf(b)).toBe(0)
				ctx.h:removePlayer(players[5])
				ctx.h:settle(3)
				expect(ctx.N.slotOf(a)).toBe(5)
				wait(ctx, 0.5)
				expect(#kicksOf(ctx, a)).toBe(0)
				expect(kicksOf(ctx, b)).toEqual({ "This island is full! Join another server." })
				expect(ctx.N.debugTracked(b)).toBe(true) -- encore là dans le harnais (Kick simulé)
				ctx.h:removePlayer(b)
				ctx.h:settle(2)
				expect(ctx.N.debugTracked(b)).toBe(false)
			end
		)

		it("parti avant la fin du délai : aucun renvoi, aucune erreur, aucun état gardé", function()
			local ctx = nestBoot()
			for i = 1, 12 do
				nestJoin(ctx, i)
			end
			local late = nestJoin(ctx, 13)
			ctx.h:removePlayer(late)
			ctx.h:settle(2)
			wait(ctx, 0.5)
			expect(#kicksOf(ctx, late)).toBe(0)
			expect(ctx.N.debugTracked(late)).toBe(false)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	-- =========================================================================================
	-- 4. Titre « Roi / Reine de la Conga » retiré au changement de semaine (LeaderboardService)
	-- =========================================================================================

	describe(
		"Fix fin serveur anti-triche › couronne : changement de semaine en cours de session",
		function()
			it(
				"l'ancien Roi absent du nouveau top 10 perd le titre ; un joueur couronné de nouveau le garde",
				function()
					local h = Harness.new()
					local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
					Clock.freeze(TC)
					local DS = h:require("ServerScriptService.Server.Services.DataService")
					DS.Settings.RETRY_BASE_DELAY = 0.001
					DS.Settings.LOCKED_RETRY_DELAY = 0.01
					local LTuning = h:require("ServerScriptService.Server.Events.Tuning")
					LTuning.DataStoreRetryDelay = 0.001
					local week = Clock.week(TC)
					local stores = h.game.DataStoreService
					stores:GetOrderedDataStore("WeeklyConga_" .. (week - 1)):SetAsync("1", 44)
					stores:GetOrderedDataStore("WeeklyConga_" .. (week - 1)):SetAsync("2", 30)
					h:boot()
					local L = h:require("ServerScriptService.Server.Services.LeaderboardService")
					local N = h:require("ServerScriptService.Server.Services.NestService")
					local function joinL(userId)
						local p = h:addPlayer({ userId = userId, name = "P" .. userId })
						h:settle(3)
						DS.waitFor(p, 2)
						h:settle(2)
						return p, DS.get(p)
					end
					local a = joinL(1)
					local b = joinL(2)
					local c = joinL(3)
					L.step(TC)
					h:settle(5)
					expect(N.hasUnlock(a, "titles", "conga_royal")).toBe(true)
					expect(N.hasUnlock(b, "titles", "conga_royal")).toBe(true)
					expect(N.hasUnlock(c, "titles", "conga_royal")).toBe(false)
					-- a porte le titre
					expect(N.equip(a, "titles", "conga_royal")).toBe(true)
					expect(a:GetAttribute("Title")).toBe("conga_royal")
					-- semaine écoulée : le nouveau top 10 (semaine `week`) contient b et c, plus a
					stores:GetOrderedDataStore("WeeklyConga_" .. week):SetAsync("2", 50)
					stores:GetOrderedDataStore("WeeklyConga_" .. week):SetAsync("3", 20)
					local monday = TC + Clock.untilNextWeek(TC) + 1
					Clock.freeze(monday)
					L.step(monday)
					h:settle(5)
					expect(N.hasUnlock(a, "titles", "conga_royal")).toBe(false)
					expect(a:GetAttribute("Title")).toBe("") -- titre équipé mais plus possédé : par défaut
					expect(N.hasUnlock(b, "titles", "conga_royal")).toBe(true)
					expect(N.hasUnlock(c, "titles", "conga_royal")).toBe(true)
					-- sans effet sur un joueur qui n'avait rien ; jamais d'erreur
					N.revokeTemporary(c, "titles", "nope")
					N.revokeTemporary(c, "bad", "conga_royal")
					expect(#h.errors).toBe(0)
				end
			)
		end
	)
end
