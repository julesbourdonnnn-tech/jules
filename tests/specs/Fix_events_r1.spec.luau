--!nocheck
-- Correctifs QA du paquet « events » (tour 1) :
--  * Starfall Saturday : un seul Starborn garanti par compte et par show (reconnexion sur le même
--    serveur, changement de serveur : marque stats.starfallGift du profil) ; présence comptée par
--    UserId (un retour sur le même serveur garde le temps déjà passé)
--  * récompenses par compte : Balise (+40 / +15) et port de Comète (+50) ne se rouvrent pas en
--    revenant sur le serveur
--  * départ : cadeau Starfall et dernier port de Comète écrits dans la sauvegarde de départ quel
--    que soit l'ordre des connexions PlayerRemoving (crochet DataService.onBeforeSave), sans
--    session fantôme dans QuestService
--  * LeaderboardService : classement mondial Star Atlas lu toutes les 120 s (attribut « Atlas »)
--  * QuestService : PlayerReady émis avant son Start() (profil chargé sans yield) → accueil lancé

local Vector3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC
	local SAT = 1800115200 -- samedi 16/01/2027 16:00:00 UTC (Starfall Saturday)

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new({ isStudio = opts.isStudio })
		Vector3 = h.globals.Vector3
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or (T0 - 100))
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local Tuning = h:require("ServerScriptService.Server.Events.Tuning")
		Tuning.DataStoreRetryDelay = 0.001
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			Tuning = Tuning,
			E = h:require("ServerScriptService.Server.Services.EventService"),
			Q = h:require("ServerScriptService.Server.Services.QuestService"),
			L = h:require("ServerScriptService.Server.Services.LeaderboardService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			Atlas = h:require("ServerScriptService.Server.Services.AtlasService"),
			Spawn = h:require("ServerScriptService.Server.Services.SpawnService"),
			World = h:require("ServerScriptService.Server.Services.WorldService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			Events = h:require("ReplicatedStorage.Shared.Config.Events"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			Strings = h:require("ReplicatedStorage.Shared.Localization.Strings"),
			calls = { nebbies = {}, welcome = {} },
		}
		if opts.before then
			opts.before(ctx)
		end
		h:boot()
		local addNebbies = ctx.Atlas.addNebbies
		ctx.Atlas.addNebbies = function(p, codes, source, stars)
			table.insert(ctx.calls.nebbies, { player = p, userId = p.UserId, codes = codes, source = source })
			return addNebbies(p, codes, source, stars)
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

	local function at(ctx, t)
		ctx.Clock.freeze(t)
		ctx.E.step(t)
	end

	-- pas de 5 s (= Tuning.MaxStepGap) de `from` à `to` ; retourne le dernier instant
	local function run(ctx, from, to)
		local t = from
		while t < to do
			t = math.min(t + 5, to)
			at(ctx, t)
		end
		return t
	end

	local function actor(ctx, p, pos, prev)
		return {
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
	end

	local function savedRecord(ctx, userId)
		return ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1"):GetAsync("player_" .. userId)
	end

	local function featuredOf(ctx)
		return ctx.EventClock.featuredSpecies(ctx.Clock.week(SAT))
	end

	local function starborns(ctx, data)
		local featured = featuredOf(ctx)
		local bit = ctx.Nebbies.Variants.starborn.bit
		local n = 0
		for _, rec in data.nebbies do
			if rec.s == featured and rec.v == bit then
				n += 1
			end
		end
		return n
	end

	local function gifts(ctx, userId)
		local n = 0
		for _, call in ctx.calls.nebbies do
			if call.source == "starfall" and call.userId == userId then
				n += 1
			end
		end
		return n
	end

	local function feedbackKeys(ctx, p)
		local out = {}
		for _, args in ctx.h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	-- Départ avec un ordre de connexions PlayerRemoving défavorable (Roblox ne garantit pas l'ordre
	-- d'appel) : les connexions dont la source contient un des motifs de `first` passent d'abord.
	-- `detached` : le Player a déjà quitté Players quand les connexions tournent (événements différés).
	local function leave(ctx, p, first, detached)
		local signal = ctx.h.game.Players.PlayerRemoving
		local handlers = signal._handlers
		local front, rest = {}, {}
		for _, pattern in first do
			for _, conn in handlers do
				local source = debug.info(conn._fn, "s") or ""
				if string.find(source, pattern, 1, true) and table.find(front, conn) == nil then
					table.insert(front, conn)
				end
			end
		end
		for _, conn in handlers do
			if table.find(front, conn) == nil then
				table.insert(rest, conn)
			end
		end
		table.clear(handlers)
		for _, conn in front do
			table.insert(handlers, conn)
		end
		for _, conn in rest do
			table.insert(handlers, conn)
		end
		if detached then
			p.Parent = nil
		end
		signal:Fire(p)
		if p.Character then
			p.Character:Destroy()
			p.Character = nil
		end
		p.Parent = nil
		ctx.h:settle(5)
	end

	-- Contrat proposé (notes d'intégration) : DataService passe `release` à ses crochets. Simulé ici
	-- en enveloppant les crochets enregistrés AVANT le démarrage.
	local function withReleaseFlag(c)
		c.releasing = {}
		local register = c.DS.onBeforeSave
		c.DS.onBeforeSave = function(fn)
			register(function(player, data)
				fn(player, data, c.releasing[player] == true)
			end)
		end
	end

	-- ---------------------------------------------------------------------------------------------
	describe("Fix events r1 › Starfall Saturday : un Starborn garanti par compte et par show", function()
		it("qualifié, parti puis revenu sur le même serveur jusqu'à la fin : un seul Starborn", function()
			local ctx = boot({ t = SAT - 50 })
			local SF = ctx.Events.Starfall
			local a = join(ctx, 1)
			at(ctx, SAT)
			local t = run(ctx, SAT, SAT + SF.PresenceSeconds + 10)
			ctx.h:removePlayer(a)
			ctx.h:settle(5)
			expect(gifts(ctx, 1)).toBe(1)
			local a2 = join(ctx, 1)
			run(ctx, t, SAT + SF.Duration + 5)
			expect(ctx.E.snapshot().starfall).toBeNil()
			expect(gifts(ctx, 1)).toBe(1)
			ctx.h:removePlayer(a2)
			ctx.h:settle(5)
			local saved = savedRecord(ctx, 1).data
			expect(starborns(ctx, saved)).toBe(1)
			expect(saved.stats.starfallGift).toBe(SAT)
		end)

		it("changement de serveur : le Starborn déjà reçu ailleurs n'est jamais redonné", function()
			local A = boot({ t = SAT - 50 })
			local SF = A.Events.Starfall
			local a = join(A, 1)
			at(A, SAT)
			run(A, SAT, SAT + SF.PresenceSeconds + 10)
			A.h:removePlayer(a)
			A.h:settle(5)
			local record = savedRecord(A, 1)
			expect(starborns(A, record.data)).toBe(1)
			expect(record.data.stats.starfallGift).toBe(SAT)

			-- serveur B (même DataStore) : 5 min de plus puis départ pendant le show
			local tB = SAT + SF.PresenceSeconds + 20
			local B = boot({ t = tB })
			B.h.game.DataStoreService:GetDataStore("PlayerData_v1"):SetAsync("player_1", record)
			local b = join(B, 1)
			at(B, tB)
			local endB = run(B, tB, tB + SF.PresenceSeconds + 10)
			B.h:removePlayer(b)
			B.h:settle(5)
			expect(gifts(B, 1)).toBe(0)
			record = savedRecord(B, 1)
			expect(starborns(B, record.data)).toBe(1)

			-- serveur C : présent jusqu'à la fin du show (remise de fin)
			local C = boot({ t = endB })
			C.h.game.DataStoreService:GetDataStore("PlayerData_v1"):SetAsync("player_1", record)
			local c = join(C, 1)
			at(C, endB)
			run(C, endB, SAT + SF.Duration + 5)
			expect(C.E.snapshot().starfall).toBeNil()
			expect(gifts(C, 1)).toBe(0)
			expect(starborns(C, C.DS.get(c))).toBe(1)
			expect(table.find(feedbackKeys(C, c), "feedback.starfallGift")).toBeNil()
		end)

		it("présence comptée par compte : un retour sur le même serveur garde le temps passé", function()
			local ctx = boot({ t = SAT - 50 })
			local SF = ctx.Events.Starfall
			local a = join(ctx, 1)
			at(ctx, SAT)
			local t = run(ctx, SAT, SAT + 180) -- 3 min
			ctx.h:removePlayer(a)
			ctx.h:settle(5)
			t = run(ctx, t, SAT + SF.Duration - 180) -- absent : rien ne s'ajoute
			local a2 = join(ctx, 1)
			run(ctx, t, SAT + SF.Duration + 5) -- 3 min de plus, présent à la fin
			expect(gifts(ctx, 1)).toBe(1)
			expect(table.find(feedbackKeys(ctx, a2), "feedback.starfallGift") ~= nil).toBe(true)
			-- arrivé trop tard (moins de 5 min au total) : rien
			local ctx2 = boot({ t = SAT - 50 })
			at(ctx2, SAT)
			local t2 = run(ctx2, SAT, SAT + SF.Duration - 120)
			local late = join(ctx2, 2)
			run(ctx2, t2, SAT + SF.Duration + 5)
			expect(gifts(ctx2, 2)).toBe(0)
			expect(late.Parent ~= nil).toBe(true)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix events r1 › récompenses d'événement par compte (reconnexion)", function()
		local B1 = T0 + 1500 -- Nuit de la Balise (:25:00)
		local T1 = T0 + 600 -- impact de Comète

		it("Balise : un contributeur déjà payé qui revient ne touche pas une 2e fois", function()
			local ctx = boot()
			local WinDust = ctx.Balance.Beacon.WinDust
			local a, da = join(ctx, 1)
			ctx.E.setActivePlayers(1)
			at(ctx, B1 - 15)
			at(ctx, B1)
			local goal = ctx.E.snapshot().beacon.goal
			local d0 = da.stardust
			ctx.E.onBeaconParade(a, goal)
			expect(ctx.E.snapshot().beacon.phase).toBe("success")
			expect(da.stardust - d0).toBe(WinDust)
			ctx.h:removePlayer(a)
			ctx.h:settle(5)
			local a2, da2 = join(ctx, 1)
			local d1 = da2.stardust
			at(ctx, B1 + 30)
			ctx.E.onBeaconParade(a2, 3) -- contribution « tardive » du même compte
			expect(da2.stardust - d1).toBe(0)
			expect(ctx.E.snapshot().beacon.topUserId).toBe(1)
			-- un autre compte, contributeur tardif : payé normalement
			local b, db = join(ctx, 2)
			local b0 = db.stardust
			ctx.E.onBeaconParade(b, 1)
			expect(db.stardust - b0).toBe(WinDust)
		end)

		it("Balise : contributeur parti avant la réussite puis revenu → payé une fois", function()
			local ctx = boot()
			local WinDust = ctx.Balance.Beacon.WinDust
			local results = {}
			ctx.Signals.BeaconResult:Connect(function(success, list)
				table.insert(results, { success = success, list = list })
			end)
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			ctx.E.setActivePlayers(2)
			at(ctx, B1 - 15)
			at(ctx, B1)
			local goal = ctx.E.snapshot().beacon.goal
			ctx.E.onBeaconParade(a, goal - 1)
			ctx.h:removePlayer(a)
			ctx.h:settle(5)
			local a2, da2 = join(ctx, 1)
			local d0 = da2.stardust
			at(ctx, B1 + 10)
			ctx.E.onBeaconParade(b, 1)
			expect(ctx.E.snapshot().beacon.phase).toBe("success")
			expect(da2.stardust - d0).toBe(WinDust)
			expect(results[1].success).toBe(true)
			expect(table.find(results[1].list, a2) ~= nil).toBe(true)
			expect(table.find(results[1].list, a)).toBeNil()
			-- le meilleur contributeur reste ce compte (total cumulé par UserId)
			expect(ctx.E.snapshot().beacon.topUserId).toBe(1)
			ctx.E.onBeaconParade(a2, 2)
			expect(da2.stardust - d0).toBe(WinDust)
		end)

		it("Comète : la récompense de port (≥ 3 s) est donnée une fois par compte", function()
			local ctx = boot()
			local HoldDust = ctx.Balance.Comet.HoldDust
			local a, da = join(ctx, 1)
			at(ctx, T1)
			local impact = ctx.EventClock.cometImpact(T1)
			local pos = Vector3.new(impact.X, 3, impact.Z)
			local d0 = da.stardust
			ctx.E.stepComet(T1, { actor(ctx, a, pos) })
			expect(ctx.E.carrier()).toBe(a)
			at(ctx, T1 + 3.5)
			ctx.E.stepComet(T1 + 3.5, { actor(ctx, a, pos) })
			expect(da.stardust - d0).toBe(HoldDust)
			ctx.h:removePlayer(a)
			ctx.h:settle(5)
			expect(ctx.E.carrier()).toBeNil()
			local a2, da2 = join(ctx, 1)
			local d1 = da2.stardust
			local snap = ctx.E.snapshot().comet
			local ground = Vector3.new(snap.x, 3, snap.z)
			at(ctx, T1 + 10)
			ctx.E.stepComet(T1 + 10, { actor(ctx, a2, ground) })
			expect(ctx.E.carrier()).toBe(a2)
			at(ctx, T1 + 15)
			ctx.E.stepComet(T1 + 15, { actor(ctx, a2, ground) })
			expect(da2.stardust - d1).toBe(0)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe(
		"Fix events r1 › départ : sauvegarde complète quel que soit l'ordre PlayerRemoving",
		function()
			local T1 = T0 + 600

			local function qualify(ctx)
				local SF = ctx.Events.Starfall
				local a = join(ctx, 1)
				at(ctx, SAT)
				run(ctx, SAT, SAT + SF.PresenceSeconds + 10)
				return a
			end

			local function carryComet(ctx)
				local a, da = join(ctx, 1)
				at(ctx, T1)
				da.quests.list = { { id = 21, p = 0, done = false, claimed = false } }
				da.quests.day = ctx.Clock.day()
				local impact = ctx.EventClock.cometImpact(T1)
				ctx.E.stepComet(T1, { actor(ctx, a, Vector3.new(impact.X, 3, impact.Z)) })
				expect(ctx.E.carrier()).toBe(a)
				at(ctx, T1 + 2)
				return a
			end

			it(
				"Starfall, DataService d'abord et Player déjà retiré (différé) : Starborn sauvegardé",
				function()
					local ctx = boot({ t = SAT - 50 })
					local a = qualify(ctx)
					leave(ctx, a, { "DataService" }, true)
					expect(starborns(ctx, savedRecord(ctx, 1).data)).toBe(1)
					expect(savedRecord(ctx, 1).data.stats.starfallGift).toBe(SAT)
				end
			)

			it("Comète, DataService d'abord et Player déjà retiré : dernier port sauvegardé", function()
				local ctx = boot()
				local a = carryComet(ctx)
				leave(ctx, a, { "DataService" }, true)
				expect(ctx.E.carrier()).toBeNil()
				local saved = savedRecord(ctx, 1).data
				expect(saved.quests.list[1].p).toBeNear(2)
				expect(saved.stats.cometsHeld).toBe(1)
			end)

			it(
				"drapeau `release` des crochets (contrat proposé), DataService d'abord : tout est écrit",
				function()
					local ctx = boot({ t = SAT - 50, before = withReleaseFlag })
					local a = qualify(ctx)
					ctx.releasing[a] = true
					leave(ctx, a, { "DataService" }, false)
					expect(starborns(ctx, savedRecord(ctx, 1).data)).toBe(1)
					local ctx2 = boot({ before = withReleaseFlag })
					local b = carryComet(ctx2)
					ctx2.releasing[b] = true
					leave(ctx2, b, { "DataService" }, false)
					local saved = savedRecord(ctx2, 1).data
					expect(saved.quests.list[1].p).toBeNear(2)
					expect(saved.stats.cometsHeld).toBe(1)
				end
			)

			it("QuestService avant DataService : progression écrite, aucune session fantôme", function()
				local ctx = boot({ before = withReleaseFlag })
				local a = carryComet(ctx)
				ctx.releasing[a] = true
				leave(ctx, a, { "QuestService", "DataService" }, false)
				local saved = savedRecord(ctx, 1).data
				expect(saved.quests.list[1].p).toBeNear(2)
				expect(saved.stats.cometsHeld).toBe(1)
				expect(saved.stats.sessions).toBe(1)
				expect(saved.rookie.sessions).toBe(1)
				-- un signal arrivé après le départ ne recrée rien
				ctx.Signals.CometHeld:Fire(a, 5)
				ctx.h:settle(2)
				expect(ctx.DS.get(a)).toBeNil()
			end)

			it(
				"départ ordinaire : un seul cadeau malgré le crochet ET la connexion PlayerRemoving",
				function()
					local ctx = boot({ t = SAT - 50, before = withReleaseFlag })
					local a = qualify(ctx)
					ctx.releasing[a] = true
					ctx.h:removePlayer(a)
					ctx.h:settle(5)
					expect(gifts(ctx, 1)).toBe(1)
					expect(starborns(ctx, savedRecord(ctx, 1).data)).toBe(1)
				end
			)
		end
	)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix events r1 › classement mondial Star Atlas (§6.7)", function()
		local function step(ctx, t)
			ctx.Clock.freeze(t)
			ctx.L.step(t)
			ctx.h:settle(3)
		end

		it("top 10 lu toutes les 120 s, attribut Atlas de la stèle, bannis présents retirés", function()
			local ctx = boot({ t = T0 })
			local board = ctx.World.board()
			expect(board:GetAttribute("Atlas")).toBe("")
			local a = join(ctx, 1)
			local _, db = join(ctx, 2)
			db.flags.lbBanned = true
			local store = ctx.h.game.DataStoreService:GetOrderedDataStore("AtlasAllTime")
			store:SetAsync("500", 90)
			store:SetAsync("2", 50)
			store:SetAsync("1", 30)
			step(ctx, T0)
			expect(ctx.L.atlasTop()).toEqual({
				{ userId = 500, name = "User500", n = 90 },
				{ userId = 1, name = "P1", n = 30 },
			})
			expect(board:GetAttribute("Atlas")).toBe("500:User500:90;1:P1:30")
			for i = 1, 12 do
				store:SetAsync(tostring(600 + i), 100 + i)
			end
			step(ctx, T0 + 60)
			expect(#ctx.L.atlasTop()).toBe(2)
			step(ctx, T0 + 120)
			local top = ctx.L.atlasTop()
			expect(#top).toBe(ctx.Balance.Leaderboard.TopWeekly)
			expect(top[1].userId).toBe(612)
			-- la copie retournée ne touche pas l'état interne
			table.clear(top)
			expect(#ctx.L.atlasTop()).toBe(ctx.Balance.Leaderboard.TopWeekly)
			expect(a.Parent ~= nil).toBe(true)
		end)

		it("une entrée d'Atlas écrite puis relue apparaît sur la stèle", function()
			local ctx = boot({ t = T0 })
			local a = join(ctx, 1)
			step(ctx, T0)
			ctx.Signals.AtlasEntry:Fire(a, 1, 0, 7)
			step(ctx, T0 + 60) -- vidage de la file d'écriture
			step(ctx, T0 + 120) -- lecture
			expect(ctx.L.atlasTop()).toEqual({ { userId = 1, name = "P1", n = 7 } })
			expect(ctx.World.board():GetAttribute("Atlas")).toBe("1:P1:7")
		end)

		it("lecture en panne : nouvelles tentatives, l'affichage précédent est gardé", function()
			local ctx = boot({ t = T0 })
			local store = ctx.h.game.DataStoreService:GetOrderedDataStore("AtlasAllTime")
			store:SetAsync("9", 12)
			step(ctx, T0)
			expect(#ctx.L.atlasTop()).toBe(1)
			ctx.h.dataStoreFailures = 6 -- semaine (3 essais) puis Star Atlas (3 essais)
			step(ctx, T0 + 120)
			ctx.h:settle(5)
			expect(ctx.h.dataStoreFailures).toBe(0)
			expect(ctx.L.atlasTop()).toEqual({ { userId = 9, name = "User9", n = 12 } })
			step(ctx, T0 + 240)
			expect(#ctx.L.atlasTop()).toBe(1)
		end)

		it("textes de la stèle en anglais et en français", function()
			local ctx = boot({ t = T0 })
			for _, key in { "board.atlas", "board.atlasEntry" } do
				expect(type(ctx.Strings.en[key])).toBe("string")
				expect(type(ctx.Strings.fr[key])).toBe("string")
			end
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix events r1 › QuestService : PlayerReady avant son Start()", function()
		it("joueur déjà là, profil chargé sans yield (Studio, mémoire) : accueil lancé", function()
			local ctx = boot({
				t = T0,
				isStudio = true,
				before = function(c)
					c.h.dataStoreFailures = 1 -- sonde de Studio en échec → magasin en mémoire (sans yield)
					local p = c.h:_newPlayer({ userId = 1, name = "Solo" })
					p.Parent = c.h.game.Players
					c.solo = p
					c.Spawn.spawnWelcome = function(player)
						table.insert(c.calls.welcome, player)
						return {}
					end
				end,
			})
			ctx.h:settle(5)
			local p = ctx.solo
			expect(ctx.DS.usingMemoryStore).toBe(true)
			expect(ctx.N.slotOf(p) > 0).toBe(true)
			expect(ctx.Q.onboardingStep(p)).toBe(1)
			expect(#ctx.calls.welcome).toBe(1)
			-- un PlayerReady tardif (rattrapage déjà fait) ne relance pas l'accueil
			ctx.Signals.PlayerReady:Fire(p, ctx.N.slotOf(p))
			ctx.h:settle(2)
			expect(#ctx.calls.welcome).toBe(1)
			expect(ctx.Q.onboardingStep(p)).toBe(1)
			expect(ctx.DS.get(p).stats.sessions).toBe(1)
		end)

		it("démarrage ordinaire : un seul accueil par session", function()
			local ctx = boot({
				t = T0,
				before = function(c)
					c.Spawn.spawnWelcome = function(player)
						table.insert(c.calls.welcome, player)
						return {}
					end
				end,
			})
			local p = join(ctx, 3)
			expect(ctx.Q.onboardingStep(p)).toBe(1)
			expect(#ctx.calls.welcome).toBe(1)
			ctx.Signals.PlayerReady:Fire(p, ctx.N.slotOf(p))
			ctx.h:settle(2)
			expect(#ctx.calls.welcome).toBe(1)
		end)
	end)
end
