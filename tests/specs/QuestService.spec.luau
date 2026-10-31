--!nocheck
-- QuestService : sessions, chaîne d'accueil Q1-Q7 (récompenses automatiques, entonnoir, accueil
-- dirigé, Rare garanti), quêtes du jour (tirage déterministe, filtres, relances, Étoile du jour,
-- remise à zéro), Grand Défilé, calendrier indulgent, codes, bouclier débutant, statistiques et
-- titres, temps de jeu, charges malveillantes et cycle de vie.

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC
	local DAY = 86400

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			Q = h:require("ServerScriptService.Server.Services.QuestService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			Econ = h:require("ServerScriptService.Server.Services.EconomyService"),
			Atlas = h:require("ServerScriptService.Server.Services.AtlasService"),
			Spawn = h:require("ServerScriptService.Server.Services.SpawnService"),
			Crew = h:require("ServerScriptService.Server.Services.CrewService"),
			Monet = h:require("ServerScriptService.Server.Services.MonetizationService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			Codes = h:require("ServerScriptService.Server.Data.Codes"),
			QuestLogic = h:require("ServerScriptService.Server.Events.QuestLogic"),
			Quests = h:require("ReplicatedStorage.Shared.Config.Quests"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			calls = { welcome = {}, directed = {}, rare = {}, nebbies = {}, unlocks = {} },
		}
		if opts.noRateLimit then
			local RateLimit = h:require("ServerScriptService.Server.Util.RateLimit")
			RateLimit.allow = function()
				return true
			end
		end
		h:boot()
		local Spawn, Atlas, N = ctx.Spawn, ctx.Atlas, ctx.N
		Spawn.spawnWelcome = function(p)
			table.insert(ctx.calls.welcome, p)
			return {}
		end
		Spawn.setDirected = function(p, on)
			table.insert(ctx.calls.directed, { p = p, on = on })
		end
		Spawn.spawnGuaranteedRare = function(p)
			table.insert(ctx.calls.rare, p)
			return 1
		end
		local addNebbies = Atlas.addNebbies
		Atlas.addNebbies = function(p, codes, source, stars)
			table.insert(ctx.calls.nebbies, { player = p, codes = codes, source = source })
			return addNebbies(p, codes, source, stars)
		end
		local unlock = N.unlock
		N.unlock = function(p, kind, id)
			table.insert(ctx.calls.unlocks, { p = p, kind = kind, id = id })
			return unlock(p, kind, id)
		end
		return ctx
	end

	local function seed(ctx, userId, fields)
		local profile = ctx.Schema.defaults()
		for k, v in fields do
			profile[k] = v
		end
		local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
		store:SetAsync("player_" .. userId, { data = profile })
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, ctx.DS.get(p)
	end

	local function parade(ctx, count, codes, extra)
		local list = codes
		if list == nil then
			list = {}
			for _ = 1, count do
				table.insert(list, ctx.Nebbies.pack(ctx.Nebbies.Named.Welcome, 0, 0))
			end
		end
		local info = {
			count = count,
			codes = list,
			uids = {},
			glow = 0,
			bonus = 1,
			atBeacon = false,
			idleSeconds = 0,
			newEntries = 0,
			forced = false,
		}
		for k, v in extra or {} do
			info[k] = v
		end
		return info
	end

	local function catch(ctx, s, f, extra)
		local info = {
			code = ctx.Nebbies.pack(s, f or 0, 0),
			rarity = ctx.Nebbies.rarityOf(s),
			zone = "meadow",
			loose = false,
			recovered = false,
			personal = false,
			n = 1,
		}
		for k, v in extra or {} do
			info[k] = v
		end
		return info
	end

	local function feedbackKeys(h, p)
		local out = {}
		for _, args in h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
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

	local function funnelSteps(h, p)
		local out = {}
		for _, e in h.log.analytics do
			if e.method == "LogOnboardingFunnelStepEvent" and e.args[1] == p then
				table.insert(out, e.args[2])
			end
		end
		return out
	end

	local function customEvents(h, name)
		local out = {}
		for _, e in h.log.analytics do
			if e.method == "LogCustomEvent" and e.args[2] == name then
				table.insert(out, e.args[3])
			end
		end
		return out
	end

	local function has(list, v)
		return table.find(list, v) ~= nil
	end

	local function setList(ctx, p, data, ids)
		local list = {}
		for _, id in ids do
			table.insert(list, { id = id, p = 0, done = false, claimed = false })
		end
		data.quests.list = list
		data.quests.rerolls = 0
		data.quests.starClaimed = false
		data.quests.day = ctx.Clock.day()
	end

	-- ---------------------------------------------------------------------------------------------
	describe("QuestService › session et accueil", function()
		it("première session : compteurs, bouclier, quêtes du jour, accueil lancé, entonnoir 1", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			expect(data.rookie.sessions).toBe(1)
			expect(data.stats.sessions).toBe(1)
			expect(p:GetAttribute("Rookie")).toBe(true)
			expect(ctx.Q.isRookie(p)).toBe(true)
			local day = ctx.Clock.day()
			expect(data.quests.day).toBe(day)
			local ids = {}
			for _, e in data.quests.list do
				table.insert(ids, e.id)
				expect(e.p).toBe(0)
				expect(e.done).toBe(false)
			end
			expect(ids).toEqual(ctx.Q.drawDaily(1, day, false, false))
			expect(data.weekly.week).toBe(ctx.Clock.week())
			expect(data.onboarding.step).toBe(1)
			expect(ctx.Q.onboardingStep(p)).toBe(1)
			expect(#ctx.calls.welcome).toBe(1)
			expect(ctx.calls.directed[1].on).toBe(true)
			expect(has(funnelSteps(ctx.h, p), 1)).toBe(true)
		end)

		it("clés initialisées à l'arrivée : répliquées ensemble au premier passage de step", function()
			local ctx = boot()
			local p = join(ctx, 1)
			local function patchedKeys()
				local keys = {}
				for _, args in ctx.h:sentTo(p, "DataPatch") do
					for k in args[1] do
						keys[k] = true
					end
				end
				return keys
			end
			expect(patchedKeys().quests).toBeNil()
			ctx.Q.step(ctx.Clock.now())
			ctx.h:settle(2)
			local keys = patchedKeys()
			for _, k in { "quests", "weekly", "rookie", "stats", "onboarding" } do
				expect({ key = k, sent = keys[k] == true }).toEqual({ key = k, sent = true })
			end
			local patches = ctx.h:sentTo(p, "DataPatch")
			expect(patches[#patches][1].quests.day).toBe(ctx.Clock.day())
		end)

		it(
			"chaîne Q1-Q7 : récompenses automatiques, étapes d'entonnoir, accueil dirigé, Rare garanti",
			function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				local S = ctx.Signals
				local g0, d0 = data.glow, data.stardust
				-- Q1 : parade de 4 (une parade de 3 ne suffit pas)
				S.Parade:Fire(p, parade(ctx, 3))
				expect(data.onboarding.step).toBe(1)
				expect(data.onboarding.p).toBe(3)
				S.Parade:Fire(p, parade(ctx, 4))
				expect(data.onboarding.step).toBe(2)
				expect(data.glow - g0).toBe(50)
				local done = celebrations(ctx.h, p, "questDone")
				expect(done[1].kind).toBe("onboarding")
				expect(done[1].id).toBe("q1")
				expect(celebrations(ctx.h, p, "questClaimed")[1].glow).toBe(50)
				-- Q2 : 2 niveaux de Conga (la Foulée ne compte pas)
				S.UpgradeBought:Fire(p, "stride", 1)
				expect(data.onboarding.p).toBe(0)
				S.UpgradeBought:Fire(p, "conga", 1)
				S.UpgradeBought:Fire(p, "conga", 2)
				expect(data.onboarding.step).toBe(3)
				expect(data.glow - g0).toBe(130)
				-- Q3 : parade de 6 → fin de l'accueil dirigé, Rare garanti au début de Q4
				S.Parade:Fire(p, parade(ctx, 6))
				expect(data.onboarding.step).toBe(4)
				expect(data.glow - g0).toBe(280)
				expect(ctx.calls.directed[#ctx.calls.directed].on).toBe(false)
				expect(#ctx.calls.rare).toBe(1)
				-- Q4 : encaisser un Rare
				S.Parade:Fire(p, parade(ctx, 5))
				expect(data.onboarding.step).toBe(4)
				local rare = ctx.Nebbies.speciesOfRarity(3)[1]
				S.Parade:Fire(p, parade(ctx, 2, { ctx.Nebbies.pack(rare, 0, 0), ctx.Nebbies.pack(1, 0, 0) }))
				expect(data.onboarding.step).toBe(5)
				expect(data.stardust - d0).toBe(100)
				-- Q5 : Foulée
				S.UpgradeBought:Fire(p, "stride", 2)
				expect(data.onboarding.step).toBe(6)
				-- Q6 : capture d'une forme météo
				S.Caught:Fire(p, catch(ctx, 1, 0))
				expect(data.onboarding.step).toBe(6)
				S.Caught:Fire(p, catch(ctx, 1, 1))
				expect(data.onboarding.step).toBe(7)
				expect(data.stardust - d0).toBe(150)
				-- Q7 : 10 perchoirs → boost personnel 10 min
				S.PerchesChanged:Fire(p, 9)
				expect(data.onboarding.step).toBe(7)
				S.PerchesChanged:Fire(p, 10)
				expect(data.onboarding.step).toBe(8)
				expect(ctx.Q.onboardingStep(p)).toBe(8)
				expect(data.boosts.personalUntil >= ctx.Clock.now() + 600).toBe(true)
				expect(has(feedbackKeys(ctx.h, p), "feedback.boostOn")).toBe(true)
				expect(#ctx.calls.rare).toBe(1)
				local steps = funnelSteps(ctx.h, p)
				for _, step in { 1, 2, 3, 4, 5, 6, 7, 8, 9 } do
					expect({ step = step, sent = has(steps, step) }).toEqual({ step = step, sent = true })
				end
				-- la chaîne terminée ne bouge plus
				S.Parade:Fire(p, parade(ctx, 30))
				expect(data.onboarding.step).toBe(8)
			end
		)

		it(
			"Q6 accepte aussi la participation à une Comète ; Q7 déjà atteinte se valide au démarrage",
			function()
				local ctx = boot()
				local onboarding = { step = 6, p = 0 }
				seed(
					ctx,
					2,
					{ onboarding = onboarding, rookie = { sessions = 3, playSeconds = 9000, done = true } }
				)
				ctx.Atlas.perchCount = function()
					return 12
				end
				local p, data = join(ctx, 2)
				expect(data.onboarding.step).toBe(6)
				ctx.Signals.CometParticipation:Fire(p, "near")
				-- Q7 commence avec 12 perchoirs : terminée aussitôt
				expect(data.onboarding.step).toBe(8)
				expect(has(funnelSteps(ctx.h, p), 9)).toBe(true)
				expect(has(funnelSteps(ctx.h, p), 1)).toBe(false) -- pas la première session
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("QuestService › quêtes du jour (§7.5)", function()
		it(
			"tirage déterministe : un par niveau, sans doublon, JcJ exclues en Zen, Équipage si récent",
			function()
				local ctx = boot()
				local Q, QL = ctx.Q, ctx.QuestLogic
				local sawCrew, sawPvp = false, false
				for day = 20000, 20300 do
					local ids = Q.drawDaily(42, day, false, false)
					expect(ids).toEqual(Q.drawDaily(42, day, false, false))
					expect(#ids).toBe(3)
					for i, id in ids do
						local q = QL.dailyById[id]
						expect(q.tier).toBe(ctx.Quests.DailyTierOrder[i])
						expect(q.crew == true).toBe(false)
						if q.pvp then
							sawPvp = true
						end
					end
					for _, id in Q.drawDaily(42, day, true, false) do
						expect(QL.dailyById[id].pvp == true).toBe(false)
					end
					for _, id in Q.drawDaily(42, day, false, true) do
						if QL.dailyById[id].crew then
							sawCrew = true
						end
					end
				end
				expect(sawPvp).toBe(true)
				expect(sawCrew).toBe(true)
				-- deux joueurs n'ont pas toujours les mêmes quêtes
				local differ = false
				for day = 20000, 20030 do
					local a, b = Q.drawDaily(1, day, false, false), Q.drawDaily(2, day, false, false)
					if a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3] then
						differ = true
					end
				end
				expect(differ).toBe(true)
				expect(QL.crewRecent(0, 20000)).toBe(false)
				expect(QL.crewRecent(19993, 20000)).toBe(true)
				expect(QL.crewRecent(19992, 20000)).toBe(false)
			end
		)

		it("progression, réclamation unique, quête non finie refusée, Étoile du jour", function()
			local ctx = boot({ noRateLimit = true })
			local p, data = join(ctx, 1)
			setList(ctx, p, data, { 1, 9, 21 }) -- 40 captures, parade de 15, Comète tenue 10 s
			local S = ctx.Signals
			for _ = 1, 39 do
				S.Caught:Fire(p, catch(ctx, 1, 0))
			end
			expect(data.quests.list[1].p).toBe(39)
			expect(data.quests.list[1].done).toBe(false)
			S.Caught:Fire(p, catch(ctx, 1, 0))
			expect(data.quests.list[1].done).toBe(true)
			local done = celebrations(ctx.h, p, "questDone")
			expect(done[#done].kind).toBe("daily")
			expect(done[#done].slot).toBe(1)
			local d0 = data.stardust
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 2)
			expect(has(feedbackKeys(ctx.h, p), "feedback.questNotDone")).toBe(true)
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 1)
			expect(data.quests.list[1].claimed).toBe(true)
			expect(data.stardust - d0).toBe(ctx.Quests.DailyTiers.easy.stardust)
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 1)
			expect(data.stardust - d0).toBe(ctx.Quests.DailyTiers.easy.stardust)
			expect(has(feedbackKeys(ctx.h, p), "feedback.alreadyClaimed")).toBe(true)
			-- « 1 parade d'au moins 15 » : la meilleure parade compte, pas la somme
			S.Parade:Fire(p, parade(ctx, 12))
			S.Parade:Fire(p, parade(ctx, 12))
			expect(data.quests.list[2].p).toBe(12)
			S.Parade:Fire(p, parade(ctx, 15))
			expect(data.quests.list[2].done).toBe(true)
			S.CometHeld:Fire(p, 6)
			S.CometHeld:Fire(p, 4.5)
			expect(data.quests.list[3].done).toBe(true)
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 2)
			expect(data.quests.starClaimed).toBe(false)
			local before = data.boosts.personalUntil
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 3)
			expect(data.quests.starClaimed).toBe(true)
			expect(data.boosts.personalUntil - math.max(before, ctx.Clock.now()) >= 899).toBe(true)
			expect(data.stardust - d0).toBe(
				ctx.Quests.DailyTiers.easy.stardust
					+ ctx.Quests.DailyTiers.medium.stardust
					+ ctx.Quests.DailyTiers.hard.stardust
			)
		end)

		it("filtres de mesure : rareté, zone, forme météo, Balise, revenu d'une parade", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			setList(ctx, p, data, { 8, 13, 25 }) -- Balise ×5, Cratère ×10, parade ≥ 10 min de revenu
			local S = ctx.Signals
			S.Parade:Fire(p, parade(ctx, 4))
			expect(data.quests.list[1].p).toBe(0)
			S.Parade:Fire(p, parade(ctx, 5, nil, { atBeacon = true }))
			expect(data.quests.list[1].done).toBe(true)
			S.Caught:Fire(p, catch(ctx, 1, 0, { zone = "glade" }))
			expect(data.quests.list[2].p).toBe(0)
			S.Caught:Fire(p, catch(ctx, 1, 0, { zone = "crater" }))
			expect(data.quests.list[2].p).toBe(1)
			S.Parade:Fire(p, parade(ctx, 3, nil, { idleSeconds = 599.9 }))
			expect(data.quests.list[3].done).toBe(false)
			S.Parade:Fire(p, parade(ctx, 3, nil, { idleSeconds = 600 }))
			expect(data.quests.list[3].done).toBe(true)
			setList(ctx, p, data, { 10, 11, 19 }) -- 5 Rares+, 3 formes météo, 3 Épiques+
			local epic = ctx.Nebbies.speciesOfRarity(4)[1]
			S.Caught:Fire(p, catch(ctx, 1, 0))
			S.Caught:Fire(p, catch(ctx, epic, 2))
			expect(data.quests.list[1].p).toBe(1)
			expect(data.quests.list[2].p).toBe(1)
			expect(data.quests.list[3].p).toBe(1)
		end)

		it("relance : même niveau, sans doublon, 1 par jour (+1 VIP), jamais d'une quête finie", function()
			local ctx = boot({ noRateLimit = true })
			local p, data = join(ctx, 1)
			local day = ctx.Clock.day()
			local before = {}
			for _, e in data.quests.list do
				table.insert(before, e.id)
			end
			local exclude = {}
			for _, id in before do
				exclude[id] = true
			end
			local expected = ctx.QuestLogic.reroll(1, day, 0, 1, "easy", exclude, false, false)
			ctx.h:fireServer("ReplicatedStorage.Remotes.RerollQuest", p, 1)
			expect(data.quests.rerolls).toBe(1)
			expect(data.quests.list[1].id).toBe(expected)
			expect(ctx.QuestLogic.dailyById[expected].tier).toBe("easy")
			expect(expected ~= before[1]).toBe(true)
			ctx.h:fireServer("ReplicatedStorage.Remotes.RerollQuest", p, 2)
			expect(data.quests.rerolls).toBe(1)
			expect(data.quests.list[2].id).toBe(before[2])
			expect(has(feedbackKeys(ctx.h, p), "feedback.noReroll")).toBe(true)
			-- VIP : une relance de plus
			ctx.Monet.ownsPass = function(_, key)
				return key == "VIPStar"
			end
			data.quests.list[3].done = true
			ctx.h:fireServer("ReplicatedStorage.Remotes.RerollQuest", p, 3)
			expect(data.quests.rerolls).toBe(1) -- quête finie : jamais relancée
			ctx.h:fireServer("ReplicatedStorage.Remotes.RerollQuest", p, 2)
			expect(data.quests.rerolls).toBe(2)
			expect(data.quests.list[2].id ~= before[2]).toBe(true)
			ctx.h:fireServer("ReplicatedStorage.Remotes.RerollQuest", p, 1)
			expect(data.quests.rerolls).toBe(2)
		end)

		it("passage en Zen : les quêtes JcJ non finies sont remplacées sans coûter de relance", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			setList(ctx, p, data, { 1, 12, 23 })
			ctx.Signals.SettingChanged:Fire(p, "zen", true)
			local list = data.quests.list
			expect(list[1].id).toBe(1)
			expect(ctx.QuestLogic.dailyById[list[2].id].tier).toBe("medium")
			expect(ctx.QuestLogic.dailyById[list[2].id].pvp == true).toBe(false)
			expect(ctx.QuestLogic.dailyById[list[3].id].tier).toBe("hard")
			expect(ctx.QuestLogic.dailyById[list[3].id].pvp == true).toBe(false)
			expect(data.quests.rerolls).toBe(0)
		end)

		it("remise à zéro à 00:00 UTC et Grand Défilé remis à zéro le lundi", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			data.quests.rerolls = 1
			data.weekly.banked = 120
			local day0 = ctx.Clock.day()
			local next = (day0 + 1) * DAY + 5
			ctx.Clock.freeze(next)
			ctx.Q.step(next)
			expect(data.quests.day).toBe(day0 + 1)
			expect(data.quests.rerolls).toBe(0)
			local ids = {}
			for _, e in data.quests.list do
				table.insert(ids, e.id)
			end
			expect(ids).toEqual(ctx.Q.drawDaily(1, day0 + 1, false, false))
			expect(data.weekly.banked).toBe(120) -- samedi : même semaine
			local monday = next + ctx.Clock.untilNextWeek(next) + 5
			ctx.Clock.freeze(monday)
			ctx.Q.step(monday)
			expect(data.weekly.week).toBe(ctx.Clock.week(monday))
			expect(data.weekly.banked).toBe(0)
			expect(data.weekly.claimed).toBe(false)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("QuestService › Grand Défilé et calendrier (§7.3, §7.5)", function()
		it("300 Nebbies encaissés → Légendaire de la semaine + 300, une seule fois", function()
			local ctx = boot({ noRateLimit = true })
			local p, data = join(ctx, 1)
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "weekly", 1)
			expect(has(feedbackKeys(ctx.h, p), "feedback.questNotDone")).toBe(true)
			ctx.Signals.Parade:Fire(p, parade(ctx, 150))
			ctx.Signals.Parade:Fire(p, parade(ctx, 150))
			expect(data.weekly.banked).toBe(300)
			local done = celebrations(ctx.h, p, "questDone")
			expect(done[#done].kind).toBe("weekly")
			local d0 = data.stardust
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "weekly", 1)
			expect(data.weekly.claimed).toBe(true)
			expect(data.stardust - d0).toBe(300)
			local legendary = ctx.EventClock.rotation("GrandParadeLegendary", ctx.Clock.week())
			local call = ctx.calls.nebbies[#ctx.calls.nebbies]
			expect(call.codes[1]).toBe(ctx.Nebbies.pack(legendary, 0, 0))
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "weekly", 1)
			expect(data.stardust - d0).toBe(300)
		end)

		it("calendrier indulgent : une fois par jour, un jour manqué met en pause, cycle de 7", function()
			local ctx = boot({ noRateLimit = true })
			local p, data = join(ctx, 1)
			local function claim()
				ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimDaily", p)
			end
			local g0 = data.glow
			claim()
			expect(data.glow - g0).toBe(500) -- 5 min de revenu, minimum 500
			expect(data.daily.step).toBe(2)
			expect(data.daily.day).toBe(ctx.Clock.day())
			local cel = celebrations(ctx.h, p, "dailyClaimed")
			expect(cel[1].day).toBe(1)
			expect(cel[1].glow).toBe(500)
			claim()
			expect(data.daily.step).toBe(2)
			expect(has(feedbackKeys(ctx.h, p), "feedback.dailyAlready")).toBe(true)
			-- jour 2 : 50 Stardust
			local d0 = data.stardust
			ctx.Clock.freeze(T0 + DAY)
			claim()
			expect(data.stardust - d0).toBe(50)
			-- trois jours sans venir : on reprend au jour 3 (boost)
			ctx.Clock.freeze(T0 + 4 * DAY)
			local b0 = data.boosts.personalUntil
			claim()
			expect(data.daily.step).toBe(4)
			expect(data.boosts.personalUntil > b0).toBe(true)
			for day = 5, 8 do
				ctx.Clock.freeze(T0 + day * DAY)
				claim()
			end
			expect(data.daily.step).toBe(1) -- après le jour 7, le cycle recommence
			local codes = {}
			for _, call in ctx.calls.nebbies do
				if call.source == "login" then
					table.insert(codes, call.codes[1])
				end
			end
			expect(codes[1]).toBe(ctx.Nebbies.pack(ctx.Nebbies.Named.CalendarDay5, 0, 0))
			local wanderer = ctx.EventClock.rotation("WeeklyWanderer", ctx.Clock.week())
			expect(codes[2]).toBe(ctx.Nebbies.pack(wanderer, 0, 0))
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("QuestService › codes (§4.17)", function()
		it(
			"COMETCONGA : ok une fois par compte, majuscules, statuts invalid / expired / used / busy",
			function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				local q = join(ctx, 2)
				local d0 = data.stardust
				expect(ctx.h:invokeServer("ReplicatedStorage.Remotes.RedeemCode", p, "cometconga")).toBe("ok")
				expect(data.stardust - d0).toBe(200)
				expect(data.codes.COMETCONGA).toBe(true)
				expect(data.boosts.personalUntil >= ctx.Clock.now() + 600).toBe(true)
				-- débit 1 / 3 s
				expect(ctx.h:invokeServer("ReplicatedStorage.Remotes.RedeemCode", p, "COMETCONGA")).toBe(
					"busy"
				)
				expect(ctx.Q.redeem(p, "COMETCONGA")).toBe("used")
				expect(data.stardust - d0).toBe(200)
				expect(ctx.Q.redeem(p, "NOPE")).toBe("invalid")
				expect(ctx.Q.redeem(p, "bad code!")).toBe("invalid")
				expect(ctx.Q.redeem(p, string.rep("A", 21))).toBe("invalid")
				expect(ctx.Q.redeem(p, "")).toBe("invalid")
				ctx.Codes.OLDIE = { expires = 1, reward = { stardust = 5 } }
				expect(ctx.Q.redeem(p, "oldie")).toBe("expired")
				-- charge d'un autre type par le remote
				expect(ctx.h:invokeServer("ReplicatedStorage.Remotes.RedeemCode", q, { "COMETCONGA" })).toBe(
					"invalid"
				)
				-- profil pas chargé
				local get = ctx.DS.get
				ctx.DS.get = function()
					return nil
				end
				expect(ctx.Q.redeem(q, "COMETCONGA")).toBe("busy")
				ctx.DS.get = get
				expect(ctx.Q.redeem(q, "COMETCONGA")).toBe("ok")
				-- jamais envoyé au client
				for _, args in ctx.h:sentTo(p, "DataPatch") do
					expect(args[1].codes).toBeNil()
				end
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("QuestService › bouclier débutant (§4.16)", function()
		it("toute la première session, même après 40 min", function()
			local ctx = boot()
			local p = join(ctx, 1)
			for i = 1, 60 do
				ctx.Clock.freeze(T0 + i * 40)
				ctx.Q.step(T0 + i * 40)
			end
			expect(ctx.Q.isRookie(p)).toBe(true)
			ctx.Q.onSafeMoment(p)
			expect(ctx.Q.isRookie(p)).toBe(true)
		end)

		it("2e session après 30 min de jeu : fin à l'arrivée (file vide), bannière et signal", function()
			local ctx = boot()
			seed(ctx, 1, { rookie = { sessions = 1, playSeconds = 2000, done = false } })
			local ended = {}
			ctx.Signals.RookieEnded:Connect(function(pl)
				table.insert(ended, pl)
			end)
			local p, data = join(ctx, 1)
			expect(data.rookie.sessions).toBe(2)
			expect(data.rookie.done).toBe(true)
			expect(p:GetAttribute("Rookie")).toBe(false)
			expect(ctx.Q.isRookie(p)).toBe(false)
			expect(ended[1]).toBe(p)
			local banner = ctx.h:sentTo(p, "Banner")
			expect(banner[#banner][1].kind).toBe("rookieEnd")
			expect(banner[#banner][1].personal).toBe(true)
			expect(#customEvents(ctx.h, "RookieShieldEnded")).toBe(1)
		end)

		it("fin jamais en pleine course : attend le moment sûr (parade ou file vide)", function()
			local ctx = boot()
			seed(ctx, 1, { rookie = { sessions = 1, playSeconds = 1790, done = false } })
			local p, data = join(ctx, 1)
			expect(ctx.Q.isRookie(p)).toBe(true)
			ctx.Signals.LineChanged:Fire(p, 5)
			local t = ctx.Clock.now()
			for i = 1, 20 do
				ctx.Clock.freeze(t + i)
				ctx.Q.step(t + i)
			end
			expect(ctx.Q.isRookie(p)).toBe(true)
			expect(data.rookie.done).toBe(false)
			ctx.Q.onSafeMoment(p)
			expect(ctx.Q.isRookie(p)).toBe(false)
			expect(p:GetAttribute("Rookie")).toBe(false)
			ctx.Q.onSafeMoment(p) -- déjà fini : rien
			expect(#customEvents(ctx.h, "RookieShieldEnded")).toBe(1)
		end)

		it("Supernova : bouclier dû (2e session), file vide → fini ; entonnoir 10", function()
			local ctx = boot()
			seed(ctx, 1, { rookie = { sessions = 1, playSeconds = 60, done = false } })
			local p, data = join(ctx, 1)
			expect(ctx.Q.isRookie(p)).toBe(true)
			ctx.Signals.LineChanged:Fire(p, 3)
			data.supernovas = 1
			ctx.Signals.Supernova:Fire(p, 1)
			expect(ctx.Q.isRookie(p)).toBe(true)
			expect(has(funnelSteps(ctx.h, p), 10)).toBe(true)
			ctx.Signals.LineChanged:Fire(p, 0)
			ctx.Q.onSafeMoment(p)
			expect(ctx.Q.isRookie(p)).toBe(false)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("QuestService › statistiques, titres et temps de jeu", function()
		it("compteurs alimentés par les signaux et titres de statistiques débloqués", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			local b, db = join(ctx, 2)
			local S = ctx.Signals
			for _ = 1, 9 do
				S.CometEvent:Fire({ kind = "bank", id = 1, player = a })
			end
			local function titled(p, id)
				for _, c in ctx.calls.unlocks do
					if c.p == p and c.kind == "titles" and c.id == id then
						return true
					end
				end
				return false
			end
			expect(titled(a, "comet_hunter")).toBe(false)
			S.CometEvent:Fire({ kind = "bank", id = 2, player = a })
			expect(da.stats.cometsBanked).toBe(10)
			expect(titled(a, "comet_hunter")).toBe(true)
			S.CometEvent:Fire({ kind = "pickup", id = 3, player = a })
			expect(da.stats.cometsBanked).toBe(10)
			S.BeaconResult:Fire(true, { a, b })
			S.BeaconResult:Fire(false, { a })
			expect(da.stats.beaconWins).toBe(1)
			expect(db.stats.beaconWins).toBe(1)
			S.EscortTime:Fire(a, 30)
			S.EscortTime:Fire(a, 0 / 0)
			expect(da.stats.escortSeconds).toBe(30)
			S.Snipped:Fire({ snipper = a, victim = b, count = 4, byWisp = false, rewarded = true, dust = 20 })
			S.Snipped:Fire({ snipper = nil, victim = b, count = 2, byWisp = true, rewarded = false, dust = 0 })
			expect(da.stats.snipsDealt).toBe(1)
			expect(da.stats.nebbiesSnipped).toBe(4)
			expect(db.stats.snipsTaken).toBe(2)
			S.Cheered:Fire(a, b)
			expect(da.stats.cheersGiven).toBe(1)
			expect(db.stats.cheersReceived).toBe(1)
			S.Fused:Fire(a, 2)
			S.WispPopped:Fire(a)
			S.CometHeld:Fire(a, 4)
			expect(da.stats.fusions).toBe(1)
			expect(da.stats.wispsPopped).toBe(1)
			expect(da.stats.cometsHeld).toBe(1)
			S.Caught:Fire(a, catch(ctx, 1, 0))
			S.Parade:Fire(a, parade(ctx, 7))
			S.Parade:Fire(a, parade(ctx, 3))
			expect(da.stats.catches).toBe(1)
			expect(da.stats.parades).toBe(2)
			expect(da.stats.longestParade).toBe(7)
			-- équipage : dernier jour d'équipage
			ctx.Crew.crewOf = function(p)
				return if p == a then 3 else 0
			end
			S.CrewChanged:Fire({ a, b })
			expect(da.stats.lastCrewDay).toBe(ctx.Clock.day())
			expect(db.stats.lastCrewDay).toBe(0)
		end)

		it("temps de jeu écrit toutes les 10 s, complété avant chaque sauvegarde et au départ", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local t = ctx.Clock.now()
			for i = 1, 25 do
				ctx.Clock.freeze(t + i)
				ctx.Q.step(t + i)
			end
			expect(data.stats.playSeconds).toBe(20)
			expect(data.rookie.playSeconds).toBe(20)
			ctx.DS.saveNow(p)
			expect(data.stats.playSeconds).toBe(25)
			ctx.Clock.freeze(t + 27)
			ctx.h:removePlayer(p)
			ctx.h:settle(3)
			expect(data.stats.playSeconds).toBe(27)
			expect(#customEvents(ctx.h, "SessionLength")).toBe(1)
		end)

		it("retour : 2e session, pas d'entonnoir 1 ni de nouveaux Puffkins", function()
			local ctx = boot()
			local p = join(ctx, 1)
			ctx.h:removePlayer(p)
			ctx.h:settle(5)
			local p2, data = join(ctx, 1)
			expect(data.rookie.sessions).toBe(2)
			expect(data.stats.sessions).toBe(2)
			expect(#ctx.calls.welcome).toBe(1)
			expect(has(funnelSteps(ctx.h, p2), 1)).toBe(false)
			-- reprise de Q1 : l'accueil dirigé est réactivé
			expect(ctx.calls.directed[#ctx.calls.directed].p).toBe(p2)
			expect(ctx.calls.directed[#ctx.calls.directed].on).toBe(true)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("QuestService › charges malveillantes et cycle de vie", function()
		it("ClaimQuest / RerollQuest / ClaimDaily : charges invalides sans mutation ni erreur", function()
			local ctx = boot({ noRateLimit = true })
			local p, data = join(ctx, 1)
			local Tables = ctx.h:require("ReplicatedStorage.Shared.Util.Tables")
			local snapshot = Tables.deepCopy({
				quests = data.quests,
				weekly = data.weekly,
				daily = data.daily,
				onboarding = data.onboarding,
				stardust = data.stardust,
				glow = data.glow,
			})
			local bad = { 0 / 0, math.huge, -math.huge, -1, 0, 4, 1.5, "1", {}, true, string.rep("x", 1000) }
			local R = "ReplicatedStorage.Remotes."
			for _, v in bad do
				ctx.h:fireServer(R .. "ClaimQuest", p, "daily", v)
				ctx.h:fireServer(R .. "ClaimQuest", p, v, 1)
				ctx.h:fireServer(R .. "RerollQuest", p, v)
			end
			ctx.h:fireServer(R .. "ClaimQuest", p)
			ctx.h:fireServer(R .. "ClaimQuest", p, "hack", 1)
			ctx.h:fireServer(R .. "ClaimQuest", p, "weekly", 2)
			ctx.h:fireServer(R .. "ClaimQuest", p, "onboarding", 2)
			ctx.h:fireServer(R .. "RerollQuest", p)
			expect({
				quests = data.quests,
				weekly = data.weekly,
				daily = data.daily,
				onboarding = data.onboarding,
				stardust = data.stardust,
				glow = data.glow,
			}).toEqual(snapshot)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("débit : ClaimDaily martelé ne crédite qu'une fois", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local g0 = data.glow
			for _ = 1, 20 do
				ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimDaily", p)
			end
			expect(data.glow - g0).toBe(500)
			expect(data.daily.step).toBe(2)
		end)

		it("signaux pour un joueur parti ou sans profil : aucune erreur, aucun effet", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.h:removePlayer(p)
			ctx.h:settle(3)
			expect(function()
				ctx.Signals.Caught:Fire(p, catch(ctx, 1, 0))
				ctx.Signals.Parade:Fire(p, parade(ctx, 4))
				ctx.Signals.Caught:Fire("p", catch(ctx, 1, 0))
				ctx.Signals.Caught:Fire(p, { code = 0 / 0 })
				ctx.Signals.Parade:Fire(p, { count = -1 })
				ctx.Q.onSafeMoment(p)
				ctx.Q.step(0 / 0)
			end).notToThrow()
			expect(ctx.Q.isRookie(p)).toBe(false)
			expect(ctx.Q.onboardingStep(p)).toBe(0)
			expect(data.onboarding.step).toBe(1)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("QuestService › revue : sauvegarde de départ, parades vides", function()
		local function saved(ctx, userId)
			local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
			local record = store:GetAsync("player_" .. userId)
			return record and record.data
		end

		it("départ : le temps de jeu depuis le dernier step est dans la sauvegarde écrite", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local t = ctx.Clock.now()
			for i = 1, 12 do
				ctx.Clock.freeze(t + i)
				ctx.Q.step(t + i)
			end
			expect(data.stats.playSeconds).toBe(10)
			-- départ 4 s après le dernier passage (gel du tick) : la sauvegarde de DataService est
			-- copiée avant le PlayerRemoving de QuestService, le crochet doit tout compter
			ctx.Clock.freeze(t + 16)
			ctx.h:removePlayer(p)
			ctx.h:settle(5)
			local record = saved(ctx, 1)
			expect(record.stats.playSeconds).toBe(16)
			expect(record.rookie.playSeconds).toBe(16)
			-- et rien n'est compté deux fois en mémoire
			expect(data.stats.playSeconds).toBe(16)
		end)

		it("une parade vide (count = 0) ne compte ni en statistique ni pour les quêtes", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			setList(ctx, p, data, { 2, 9, 18 }) -- « Fais 5 parades » en facile
			local parades = data.stats.parades
			ctx.Signals.Parade:Fire(p, parade(ctx, 0, {}))
			expect(data.stats.parades).toBe(parades)
			expect(data.quests.list[1].p).toBe(0)
			expect(data.weekly.banked).toBe(0)
			ctx.Signals.Parade:Fire(p, parade(ctx, 3))
			expect(data.stats.parades).toBe(parades + 1)
			expect(data.quests.list[1].p).toBe(1)
		end)

		it(
			"calendrier jour 3 : le boost est annoncé une seule fois (Celebrate, pas de Feedback en double)",
			function()
				local ctx = boot({ noRateLimit = true })
				local p, data = join(ctx, 1)
				data.daily.step = 3
				local b0 = data.boosts.personalUntil
				ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimDaily", p)
				expect(data.boosts.personalUntil > b0).toBe(true)
				local cel = celebrations(ctx.h, p, "dailyClaimed")
				expect(cel[1].day).toBe(3)
				expect(cel[1].boostSeconds).toBe(ctx.Quests.Calendar[3].boostSeconds)
				expect(has(feedbackKeys(ctx.h, p), "feedback.boostOn")).toBe(false)
				-- ailleurs (code promo), le boost reste annoncé par Feedback
				expect(ctx.Q.redeem(p, "cometconga")).toBe("ok")
				expect(has(feedbackKeys(ctx.h, p), "feedback.boostOn")).toBe(true)
			end
		)
	end)
end
