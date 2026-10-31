--!nocheck
-- Correctifs « restes serveur gameplay » :
--   * Q12 : démarrage du serveur isolé (un Init / Start qui lève n'empêche pas le tick de 10 Hz)
--   * Q5  : quêtes du jour et Grand Défilé terminés mais pas réclamés encaissés au passage de
--           00:00 UTC / du lundi (step, réclamation juste après minuit, chargement après des jours
--           d'absence), jamais deux fois
--   * Q27 : partir puis revenir ne remet pas à zéro le plafond d'Épiques d'explosion de Comète
--   * Q9  : secondes de Glow Party payées et pas encore écoulées rendues à l'acheteur à l'arrêt
--   * N78 : CrewService relit l'amitié déjà vérifiée par NestService (pas d'appel web en double)
--   * Q2  : seuils de MoveCheck côté serveur seulement (jamais dans ReplicatedStorage)
local fs = require("@lune/fs")
local Bots = require("../harness/Bots")
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC
	local DAY = 86400
	local S = "ServerScriptService.Server.Services."
	local STORE = "PlayerData_v1"

	-- Serveur complet (tous les vrais services) ; `before(ctx)` avant h:boot()
	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or T0)
		local DS = h:require(S .. "DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		if opts.noRateLimit then
			h:require("ServerScriptService.Server.Util.RateLimit").allow = function()
				return true
			end
		end
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			Q = h:require(S .. "QuestService"),
			E = h:require(S .. "EventService"),
			Econ = h:require(S .. "EconomyService"),
			Atlas = h:require(S .. "AtlasService"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			QuestLogic = h:require("ServerScriptService.Server.Events.QuestLogic"),
			Quests = h:require("ReplicatedStorage.Shared.Config.Quests"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			nebbies = {},
			boosts = {},
		}
		if opts.before then
			opts.before(ctx)
		end
		h:boot()
		local addNebbies = ctx.Atlas.addNebbies
		ctx.Atlas.addNebbies = function(p, codes, source, stars)
			table.insert(ctx.nebbies, { player = p, codes = codes, source = source })
			return addNebbies(p, codes, source, stars)
		end
		local grantPersonalBoost = ctx.Econ.grantPersonalBoost
		ctx.Econ.grantPersonalBoost = function(p, seconds)
			table.insert(ctx.boosts, { player = p, seconds = seconds })
			return grantPersonalBoost(p, seconds)
		end
		return ctx
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, ctx.DS.get(p)
	end

	local function seed(ctx, userId, fields)
		local profile = ctx.Schema.defaults()
		for k, v in fields do
			profile[k] = v
		end
		ctx.h.game.DataStoreService:GetDataStore(STORE):SetAsync("player_" .. userId, { data = profile })
	end

	local function stored(ctx, userId)
		return ctx.h.game.DataStoreService:GetDataStore(STORE):GetAsync("player_" .. userId)
	end

	local function celebrations(h, p, kind)
		local out = {}
		for _, args in h:sentTo(p, "Celebrate") do
			if args[1].kind == kind then
				table.insert(out, args[1].data)
			end
		end
		return out
	end

	local function feedbackKeys(h, p)
		local out = {}
		for _, args in h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	local function has(list, v)
		return table.find(list, v) ~= nil
	end

	local function tierDust(ctx, id)
		return ctx.Quests.DailyTiers[ctx.QuestLogic.dailyById[id].tier].stardust
	end

	local function boostsOf(ctx, p)
		local out = {}
		for _, b in ctx.boosts do
			if b.player == p then
				table.insert(out, b.seconds)
			end
		end
		return out
	end

	-- quêtes du jour d'un joueur : `states[i]` = "open" | "done" | "claimed"
	local function setStates(ctx, data, states)
		for i, st in states do
			local entry = data.quests.list[i]
			local goal = ctx.QuestLogic.dailyById[entry.id].goal
			entry.p = if st == "open" then 0 else goal.n
			entry.done = st ~= "open"
			entry.claimed = st == "claimed"
		end
	end

	-- =========================================================================================
	describe("Correctifs restes serveur › démarrage isolé (Q12)", function()
		it("un Start et un Init qui lèvent : avertis, et le tick de 10 Hz de CongaService tourne", function()
			local w = Bots.boot(Harness, {
				t0 = T0,
				before = function(w)
					-- ex. LeaderboardService.Start → setBoard → WorldService.board() en échec
					w.h:require(S .. "LeaderboardService").Start = function()
						error("panne simulée au démarrage")
					end
					w.h:require(S .. "QuestService").Init = function()
						error("panne simulée à l'initialisation")
					end
				end,
			})
			local h = w.h
			local p = h:addPlayer({ userId = 1, name = "A" })
			h:settle(5)
			w.DS.waitFor(p, 2)
			h:settle(2)
			local ticks = 0
			local tick = w.Conga.tick
			w.Conga.tick = function(now)
				ticks += 1
				return tick(now)
			end
			Bots.frames(20)
			expect(ticks > 0).toBe(true)
			-- le tick diffuse : op « owner » du Nid du joueur et WorldSnapshot d'arrivée
			expect(#Bots.lineOps("owner") > 0).toBe(true)
			expect(#h:sentTo(p, "WorldSnapshot") >= 1).toBe(true)
			local start, init = false, false
			for _, line in h:warnings() do
				if string.find(line, "[Server] LeaderboardService Start:", 1, true) then
					start = string.find(line, "panne simulée au démarrage", 1, true) ~= nil
				elseif string.find(line, "[Server] QuestService Init:", 1, true) then
					init = string.find(line, "panne simulée à l'initialisation", 1, true) ~= nil
				end
			end
			expect(start).toBe(true)
			expect(init).toBe(true)
		end)
	end)

	-- =========================================================================================
	describe("Correctifs restes serveur › quêtes dues au passage de 00:00 UTC (Q5)", function()
		it("minuit (step) : terminées non réclamées payées, Étoile du jour, une seule fois", function()
			local ctx = boot({ noRateLimit = true })
			local p, data = join(ctx, 1)
			local day0 = ctx.Clock.day()
			setStates(ctx, data, { "done", "claimed", "done" })
			local old = data.quests.list
			local expected = tierDust(ctx, old[1].id) + tierDust(ctx, old[3].id)
			local d0 = data.stardust
			local claimed0 = #celebrations(ctx.h, p, "questClaimed")
			local midnight = (day0 + 1) * DAY + 5
			ctx.Clock.freeze(midnight)
			ctx.Q.step(midnight)
			expect(data.stardust - d0).toBe(expected)
			local cel = celebrations(ctx.h, p, "questClaimed")
			expect(#cel - claimed0).toBe(2)
			expect(cel[#cel - 1].kind).toBe("daily")
			expect(cel[#cel - 1].slot).toBe(1)
			expect(cel[#cel].slot).toBe(3)
			-- les 3 réclamées : Étoile du jour (boost 15 min)
			expect(boostsOf(ctx, p)).toEqual({ ctx.Quests.DailyStar.boostSeconds })
			-- nouveau tirage, rien de fait
			expect(data.quests.day).toBe(day0 + 1)
			for _, e in data.quests.list do
				expect(e.done).toBe(false)
				expect(e.claimed).toBe(false)
			end
			-- aucun double paiement : autre passage lent, réclamations sur les nouvelles quêtes
			ctx.Q.step(midnight + 10)
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 1)
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 3)
			expect(data.stardust - d0).toBe(expected)
			expect(#boostsOf(ctx, p)).toBe(1)
			expect(#celebrations(ctx.h, p, "questClaimed") - claimed0).toBe(2)
		end)

		it(
			"réclamation juste après 00:00 UTC : payée une fois, sans « quête pas terminée »",
			function()
				local ctx = boot({ noRateLimit = true })
				local p, data = join(ctx, 1)
				local day0 = ctx.Clock.day()
				setStates(ctx, data, { "open", "done", "open" })
				local expected = tierDust(ctx, data.quests.list[2].id)
				local d0 = data.stardust
				-- le serveur n'a pas encore fait son passage lent de minuit quand le clic arrive
				ctx.Clock.freeze((day0 + 1) * DAY + 1)
				ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 2)
				expect(data.stardust - d0).toBe(expected)
				expect(has(feedbackKeys(ctx.h, p), "feedback.questNotDone")).toBe(false)
				local cel = celebrations(ctx.h, p, "questClaimed")
				expect(#cel).toBe(1)
				expect(cel[1].slot).toBe(2)
				-- pas toutes réclamées : pas d'Étoile du jour
				expect(#boostsOf(ctx, p)).toBe(0)
				expect(data.quests.day).toBe(day0 + 1)
				-- 2e clic : la nouvelle quête n'est pas finie, rien de plus
				ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 2)
				expect(data.stardust - d0).toBe(expected)
				expect(has(feedbackKeys(ctx.h, p), "feedback.questNotDone")).toBe(true)
			end
		)

		it(
			"lundi 00:00 : Grand Défilé terminé payé avec la Légendaire de SA semaine, une fois",
			function()
				local ctx = boot({ noRateLimit = true })
				local p, data = join(ctx, 1)
				local week0 = ctx.Clock.week()
				data.weekly.banked = ctx.Quests.Weekly.goal.n + 12
				local d0 = data.stardust
				local monday = T0 + ctx.Clock.untilNextWeek(T0) + 5
				ctx.Clock.freeze(monday)
				ctx.Q.step(monday)
				local week1 = ctx.Clock.week(monday)
				expect(week1).toBe(week0 + 1)
				expect(data.stardust - d0).toBe(ctx.Quests.Weekly.reward.stardust)
				local legendary = ctx.EventClock.rotation("GrandParadeLegendary", week0)
				local call = ctx.nebbies[#ctx.nebbies]
				expect(call.player).toBe(p)
				expect(call.codes[1]).toBe(ctx.Nebbies.pack(legendary, 0, 0))
				local cel = celebrations(ctx.h, p, "questClaimed")
				expect(cel[#cel].kind).toBe("weekly")
				expect(cel[#cel].code).toBe(ctx.Nebbies.pack(legendary, 0, 0))
				expect(data.weekly.week).toBe(week1)
				expect(data.weekly.banked).toBe(0)
				expect(data.weekly.claimed).toBe(false)
				-- aucun double paiement
				local calls = #ctx.nebbies
				ctx.Q.step(monday + 10)
				ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "weekly", 1)
				expect(data.stardust - d0).toBe(ctx.Quests.Weekly.reward.stardust)
				expect(#ctx.nebbies).toBe(calls)
				expect(has(feedbackKeys(ctx.h, p), "feedback.questNotDone")).toBe(true)
			end
		)

		it("Grand Défilé déjà réclamé ou pas terminé : rien au lundi", function()
			local ctx = boot()
			local _, data = join(ctx, 1)
			data.weekly.banked = ctx.Quests.Weekly.goal.n - 1
			local d0 = data.stardust
			local monday = T0 + ctx.Clock.untilNextWeek(T0) + 5
			ctx.Clock.freeze(monday)
			ctx.Q.step(monday)
			expect(data.stardust).toBe(d0)
			data.weekly.banked = ctx.Quests.Weekly.goal.n
			data.weekly.claimed = true
			local monday2 = monday + 7 * DAY
			ctx.Clock.freeze(monday2)
			ctx.Q.step(monday2)
			expect(data.stardust).toBe(d0)
			expect(#ctx.nebbies).toBe(0)
		end)

		it(
			"retour après des jours d'absence : tout ce qui était dû est payé au chargement, une fois",
			function()
				local ctx = boot()
				local day0 = math.floor(T0 / DAY)
				local oldDay = day0 - 9
				local oldWeek = ctx.Clock.week(T0) - 1
				local ids = ctx.QuestLogic.drawDaily(1, oldDay, false, false)
				local list = {}
				for i, id in ids do
					local goal = ctx.QuestLogic.dailyById[id].goal
					table.insert(list, { id = id, p = goal.n, done = true, claimed = i == 2 })
				end
				seed(ctx, 1, {
					stardust = 7,
					quests = { day = oldDay, list = list, rerolls = 1, starClaimed = false },
					weekly = { week = oldWeek, banked = 320, claimed = false },
				})
				local p, data = join(ctx, 1)
				local expected = tierDust(ctx, ids[1])
					+ tierDust(ctx, ids[3])
					+ ctx.Quests.Weekly.reward.stardust
				expect(data.stardust).toBe(7 + expected)
				expect(data.quests.day).toBe(day0)
				expect(data.quests.rerolls).toBe(0)
				expect(data.weekly.week).toBe(ctx.Clock.week(T0))
				expect(data.weekly.banked).toBe(0)
				local legendary = ctx.EventClock.rotation("GrandParadeLegendary", oldWeek)
				local found = false
				for _, c in ctx.nebbies do
					if c.player == p and c.codes[1] == ctx.Nebbies.pack(legendary, 0, 0) then
						found = true
					end
				end
				expect(found).toBe(true)
				expect(boostsOf(ctx, p)).toEqual({ ctx.Quests.DailyStar.boostSeconds })
				-- départ (sauvegarde) puis retour : rien n'est payé deux fois
				local paid = data.stardust
				local nebbies = #ctx.nebbies
				ctx.h:removePlayer(p)
				ctx.h:settle(10)
				expect(stored(ctx, 1).data.stardust).toBe(paid)
				local p2, data2 = join(ctx, 1)
				expect(data2.stardust).toBe(paid)
				expect(#ctx.nebbies).toBe(nebbies)
				expect(#boostsOf(ctx, p2)).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	describe("Correctifs restes serveur › plafond d'Épiques d'explosion (Q27)", function()
		it(
			"partir puis revenir sur le même serveur ne permet pas un 2e Épique de la même explosion",
			function()
				local h = Harness.new()
				h:require("ReplicatedStorage.Shared.Net").setup()
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(T0)
				local Neb = h:require("ReplicatedStorage.Shared.Config.Nebbies")
				local V3 = h.globals.Vector3
				local Spawn = h:require(S .. "SpawnService")
				Spawn.Init()
				Spawn.Start()
				local now = Clock.now()
				local codes = {}
				for i = 1, 5 do
					codes[i] = Neb.pack(Neb.speciesOfRarity(4)[1], 0, 0)
				end
				local spawns = Spawn.spawnLoose(codes, { V3.new(30, 3, 0) }, now, {
					group = "burst:1",
					groupCap = 1,
					dizzy = 0,
				})
				local function wild(id, p)
					for _, w in Spawn.query(V3.new(0, 0, 0), 400, Clock.now(), p) do
						if w.id == id then
							return w
						end
					end
					return nil
				end
				local p = h:addPlayer({ userId = 9, name = "Rejoin" })
				expect(Spawn.canCatch(p, 1, wild(spawns[1].id, p), now + 1)).toBe(true)
				expect(Spawn.consume(spawns[1].id, p) ~= nil).toBe(true)
				expect(Spawn.canCatch(p, 1, wild(spawns[2].id, p), now + 1)).toBe(false)
				h:removePlayer(p)
				local again = h:addPlayer({ userId = 9, name = "Rejoin" })
				expect(Spawn.canCatch(again, 1, wild(spawns[2].id, again), now + 1)).toBe(false)
				-- un autre joueur peut toujours en attraper un
				local other = h:addPlayer({ userId = 10, name = "Other" })
				expect(Spawn.canCatch(other, 2, wild(spawns[2].id, other), now + 1)).toBe(true)
				-- le groupe disparaît avec son dernier Nebby : pas de fuite
				for i = 2, 5 do
					Spawn.consume(spawns[i].id, { UserId = 100 + i })
				end
				expect(Spawn.groupCount()).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	describe("Correctifs restes serveur › Glow Party à l'arrêt du serveur (Q9)", function()
		local function party(ctx)
			local a, dataA = join(ctx, 1)
			local b, dataB = join(ctx, 2)
			return a, dataA, b, dataB
		end

		it(
			"secondes payées pas encore écoulées → boost personnel de l'acheteur, persisté, une fois",
			function()
				local ctx = boot({ t = T0 - 100 })
				local a, dataA, b, dataB = party(ctx)
				local t = T0 + 100
				ctx.Clock.freeze(t)
				ctx.E.step(t)
				ctx.E.queueGlowParty(a, 600)
				ctx.E.queueGlowParty(a, 600)
				ctx.Clock.freeze(t + 300)
				ctx.E.step(t + 300)
				local beforeA = dataA.boosts.personalUntil
				local beforeB = dataB.boosts.personalUntil
				ctx.h:close()
				-- 1200 payées, 300 écoulées
				expect(boostsOf(ctx, a)).toEqual({ 900 })
				expect(#boostsOf(ctx, b)).toBe(0)
				expect(dataA.boosts.personalUntil).toBe(math.max(t + 300, beforeA) + 900)
				expect(dataB.boosts.personalUntil).toBe(beforeB)
				-- la sauvegarde de fermeture emporte le boost rendu
				expect(stored(ctx, 1).data.boosts.personalUntil).toBe(dataA.boosts.personalUntil)
			end
		)

		it("Glow Party en file derrière une Nuit d'Or : toute la durée payée est rendue", function()
			local ctx = boot({ t = T0 - 100 })
			local a = party(ctx)
			local t = T0 + 100
			ctx.Clock.freeze(t)
			ctx.E.step(t)
			ctx.E.runLiveOps("goldenNight")
			local endsAt = ctx.E.snapshot().serverBoost.endsAt
			expect(endsAt > t).toBe(true)
			expect(ctx.E.queueGlowParty(a, 600)).toBe(endsAt + 600)
			ctx.Clock.freeze(t + 60)
			ctx.E.step(t + 60)
			ctx.h:close()
			expect(boostsOf(ctx, a)).toEqual({ 600 })
		end)

		it("durée payée écoulée, ou acheteur parti : rien à rendre, aucune erreur", function()
			local ctx = boot({ t = T0 - 100 })
			local a, _, b = party(ctx)
			local t = T0 + 100
			ctx.Clock.freeze(t)
			ctx.E.step(t)
			ctx.E.queueGlowParty(a, 600)
			ctx.E.queueGlowParty(b, 600)
			ctx.h:removePlayer(b)
			ctx.h:settle(5)
			ctx.Clock.freeze(t + 700)
			ctx.E.step(t + 700)
			ctx.h:close()
			-- a : ses 600 s sont écoulées ; b (parti) : sa plage tournait encore pour les autres
			expect(#boostsOf(ctx, a)).toBe(0)
			expect(#ctx.boosts).toBe(0)
		end)
	end)

	-- =========================================================================================
	describe("Correctifs restes serveur › amitiés vérifiées une seule fois (N78)", function()
		it(
			"arrivée d'un joueur : un seul IsFriendsWith par paire (NestService), CrewService relit",
			function()
				local calls = {}
				local ctx = boot({
					before = function(ctx)
						local inner = MockInstance.areFriends
						MockInstance.areFriends = function(a, b)
							local key = math.min(a, b) .. ":" .. math.max(a, b)
							calls[key] = (calls[key] or 0) + 1
							return inner(a, b)
						end
						for i = 1, 4 do
							for j = i + 1, 4 do
								ctx.h:makeFriends(i, j)
							end
						end
					end,
				})
				local Crew = ctx.h:require(S .. "CrewService")
				local players = {}
				for i = 1, 5 do
					players[i] = join(ctx, i)
				end
				ctx.h:settle(5)
				local total = 0
				for key, n in calls do
					total += n
					expect({ pair = key, calls = n }).toEqual({ pair = key, calls = 1 })
				end
				-- 5 joueurs : 10 paires, chacune vérifiée une fois (sans le correctif : deux fois)
				expect(total).toBe(10)
				-- les équipages d'amis se forment toujours (Équipage auto activé par défaut)
				expect(Crew.areCrewmates(players[1], players[2])).toBe(true)
				expect(Crew.areCrewmates(players[3], players[4])).toBe(true)
				expect(Crew.crewOf(players[5])).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	describe("Correctifs restes serveur › seuils anti-triche côté serveur (Q2)", function()
		it(
			"Balance.MoveCheck n'existe plus ; MoveCheck.Config = Conga/Tuning.MoveCheck, mêmes valeurs",
			function()
				local h = Harness.new()
				local B = h:require("ReplicatedStorage.Shared.Config.Balance")
				expect(B.MoveCheck).toBeNil()
				local MC = h:require("ServerScriptService.Server.Util.MoveCheck")
				local Tuning = h:require("ServerScriptService.Server.Conga.Tuning")
				expect(MC.Config == Tuning.MoveCheck).toBe(true)
				expect(MC.Config).toEqual({
					Margin = 1.5,
					Slack = 4,
					SpeedWindow = 0.5,
					MaxClimbSpeed = 12,
					FlagsToRewind = 3,
					FlagWindow = 5,
					RewindLockout = 3,
					Exemption = 3,
					MaxAltitude = 14,
					AltitudeTime = 1.5,
					MaxRadius = 182,
					MinY = -5,
					StrikesForBan = 10,
					StrikeWindow = 600,
				})
			end
		)

		it("aucun module répliqué (src/shared, src/client, src/first) ne porte ces seuils", function()
			local offenders = {}
			local function walk(dir)
				if not fs.isDir(dir) then
					return
				end
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						walk(path)
					elseif string.sub(name, -5) == ".luau" then
						local src = fs.readFile(path)
						for _, needle in
							{ "StrikesForBan", "FlagsToRewind", "MaxClimbSpeed", "RewindLockout" }
						do
							if string.find(src, needle, 1, true) then
								table.insert(offenders, path .. " : " .. needle)
							end
						end
					end
				end
			end
			for _, root in { "src/shared", "src/client", "src/first" } do
				walk(root)
			end
			expect(offenders).toEqual({})
		end)
	end)
end
