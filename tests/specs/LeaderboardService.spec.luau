--!nocheck
-- LeaderboardService : tableau en direct (top 5), record du serveur, meilleure parade de la
-- semaine (weeklyBest), file d'écriture OrderedDataStore (60 s, nouvelles tentatives, bannis
-- jamais écrits), lecture du top 10 mondial (120 s), titre « Roi / Reine de la Conga », semaine
-- suivante, charges invalides et cycle de vie.

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local Tuning = h:require("ServerScriptService.Server.Events.Tuning")
		Tuning.DataStoreRetryDelay = 0.001
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			L = h:require("ServerScriptService.Server.Services.LeaderboardService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			World = h:require("ServerScriptService.Server.Services.WorldService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			banners = {},
			crowned = {},
		}
		if opts.before then
			opts.before(ctx)
		end
		h:boot()
		local grant = ctx.N.grantTemporary
		ctx.N.grantTemporary = function(p, kind, id)
			table.insert(ctx.crowned, { p = p, kind = kind, id = id })
			return grant(p, kind, id)
		end
		ctx.Signals.BannerRequested:Connect(function(kind, args, source)
			table.insert(ctx.banners, { kind = kind, args = args, source = source })
		end)
		return ctx
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, ctx.DS.get(p)
	end

	local function parade(count)
		return {
			count = count,
			codes = {},
			uids = {},
			glow = 0,
			bonus = 1,
			atBeacon = false,
			idleSeconds = 0,
			newEntries = 0,
			forced = false,
		}
	end

	local function ordered(ctx, name)
		return ctx.h.game.DataStoreService:GetOrderedDataStore(name)
	end

	local function storedValue(ctx, name, userId)
		return ordered(ctx, name):GetAsync(tostring(userId))
	end

	local function board(ctx, attribute)
		return ctx.World.board():GetAttribute(attribute)
	end

	local function step(ctx, t)
		ctx.Clock.freeze(t)
		ctx.L.step(t)
		ctx.h:settle(3)
	end

	-- ---------------------------------------------------------------------------------------------
	describe("LeaderboardService › tableau du serveur (§6.4)", function()
		it("top 5 des congas en cours, une mise à jour par seconde, noms Roblox", function()
			local ctx = boot()
			local players = {}
			for i = 1, 7 do
				players[i] = join(ctx, i)
				ctx.Signals.LineChanged:Fire(players[i], i * 3)
			end
			ctx.Signals.LineChanged:Fire(players[1], 0)
			step(ctx, T0)
			local top = ctx.L.liveTop()
			expect(#top).toBe(ctx.Balance.Leaderboard.TopLive)
			expect(top[1]).toEqual({ userId = 7, name = "P7", n = 21 })
			expect(top[5].userId).toBe(3)
			expect(board(ctx, "Live")).toBe("7:P7:21;6:P6:18;5:P5:15;4:P4:12;3:P3:9")
			-- moins d'une seconde plus tard : pas de mise à jour
			ctx.Signals.LineChanged:Fire(players[2], 40)
			step(ctx, T0 + 0.5)
			expect(ctx.L.liveTop()[1].userId).toBe(7)
			step(ctx, T0 + 1)
			expect(ctx.L.liveTop()[1]).toEqual({ userId = 2, name = "P2", n = 40 })
			-- départ : retiré du tableau
			ctx.h:removePlayer(players[2])
			ctx.h:settle(2)
			step(ctx, T0 + 2)
			for _, e in ctx.L.liveTop() do
				expect(e.userId ~= 2).toBe(true)
			end
		end)

		it("record du serveur : le premier en silence, bannière quand il est battu", function()
			local ctx = boot()
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			expect(ctx.L.serverRecord()).toBeNil()
			ctx.Signals.Parade:Fire(a, parade(10))
			expect(ctx.L.serverRecord()).toEqual({ userId = 1, name = "P1", n = 10 })
			expect(board(ctx, "Record")).toBe("1:P1:10")
			expect(#ctx.banners).toBe(0)
			ctx.Signals.Parade:Fire(b, parade(15))
			expect(ctx.L.serverRecord().userId).toBe(2)
			expect(board(ctx, "Record")).toBe("2:P2:15")
			expect(ctx.banners[1].kind).toBe("serverRecord")
			expect(ctx.banners[1].args.n).toBe(15)
			expect(ctx.banners[1].source).toBe(b)
			ctx.Signals.Parade:Fire(a, parade(12))
			expect(ctx.L.serverRecord().userId).toBe(2)
			expect(#ctx.banners).toBe(1)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("LeaderboardService › classements mondiaux (§6.7)", function()
		it(
			"meilleure parade de la semaine : profil, file d'écriture vidée toutes les 60 s, bannis exclus",
			function()
				local ctx = boot()
				local a, da = join(ctx, 1)
				local c, dc = join(ctx, 3)
				step(ctx, T0)
				local week = ctx.Clock.week()
				local store = "WeeklyConga_" .. week
				ctx.Signals.Parade:Fire(a, parade(10))
				ctx.Signals.Parade:Fire(a, parade(8))
				expect(da.weeklyBest).toEqual({ week = week, conga = 10 })
				dc.flags.lbBanned = true
				ctx.Signals.Parade:Fire(c, parade(20))
				expect(dc.weeklyBest.conga).toBe(20)
				ctx.Signals.AtlasEntry:Fire(a, 1, 0, 7)
				ctx.Signals.AtlasEntry:Fire(c, 1, 0, 9)
				step(ctx, T0 + 30)
				expect(storedValue(ctx, store, 1)).toBeNil()
				step(ctx, T0 + 60)
				expect(storedValue(ctx, store, 1)).toBe(10)
				expect(storedValue(ctx, store, 3)).toBeNil()
				expect(storedValue(ctx, "AtlasAllTime", 1)).toBe(7)
				expect(storedValue(ctx, "AtlasAllTime", 3)).toBeNil()
				-- un record plus bas n'écrase jamais un meilleur score déjà stocké
				ordered(ctx, store):SetAsync("1", 50)
				ctx.Signals.Parade:Fire(a, parade(12))
				step(ctx, T0 + 120)
				expect(storedValue(ctx, store, 1)).toBe(50)
			end
		)

		it("pannes DataStore : nouvelles tentatives puis remise en file, écrit au vidage suivant", function()
			local ctx = boot()
			local a = join(ctx, 1)
			step(ctx, T0)
			local store = "WeeklyConga_" .. ctx.Clock.week()
			ctx.Signals.Parade:Fire(a, parade(9))
			ctx.h.dataStoreFailures = 3
			step(ctx, T0 + 60)
			ctx.h:settle(5)
			expect(ctx.h.dataStoreFailures).toBe(0)
			expect(storedValue(ctx, store, 1)).toBeNil()
			step(ctx, T0 + 120)
			ctx.h:settle(5)
			expect(storedValue(ctx, store, 1)).toBe(9)
		end)

		it("top 10 mondial lu toutes les 120 s et affiché sur la stèle", function()
			local ctx = boot()
			local week = 0
			local a = join(ctx, 1)
			week = ctx.Clock.week()
			local s = ordered(ctx, "WeeklyConga_" .. week)
			s:SetAsync("500", 90)
			s:SetAsync("501", 80)
			s:SetAsync("1", 30)
			step(ctx, T0)
			local top = ctx.L.weeklyTop()
			expect(#top).toBe(3)
			expect(top[1]).toEqual({ userId = 500, name = "User500", n = 90 })
			expect(top[3]).toEqual({ userId = 1, name = "P1", n = 30 })
			expect(board(ctx, "Weekly")).toBe("500:User500:90;501:User501:80;1:P1:30")
			for i = 1, 12 do
				s:SetAsync(tostring(600 + i), 100 + i)
			end
			step(ctx, T0 + 60)
			expect(#ctx.L.weeklyTop()).toBe(3)
			step(ctx, T0 + 120)
			top = ctx.L.weeklyTop()
			expect(#top).toBe(ctx.Balance.Leaderboard.TopWeekly)
			expect(top[1].userId).toBe(612)
			expect(a.Parent ~= nil).toBe(true)
		end)

		it(
			"titre « Roi / Reine de la Conga » : top 10 de la semaine précédente, à l'arrivée",
			function()
				local ctx = boot({
					before = function(c)
						local week = c.Clock.week()
						local s = c.h.game.DataStoreService:GetOrderedDataStore("WeeklyConga_" .. (week - 1))
						s:SetAsync("1", 44)
						s:SetAsync("2", 3)
						s:SetAsync("4", 12)
					end,
				})
				local a = join(ctx, 1)
				local b = join(ctx, 2)
				local c = join(ctx, 3)
				step(ctx, T0)
				local function crowned(p)
					for _, e in ctx.crowned do
						if e.p == p and e.kind == "titles" and e.id == "conga_royal" then
							return true
						end
					end
					return false
				end
				expect(crowned(a)).toBe(true)
				expect(crowned(b)).toBe(true)
				expect(crowned(c)).toBe(false)
				-- arrivée après la lecture : couronné au chargement du profil
				local d = join(ctx, 4)
				expect(crowned(d)).toBe(true)
			end
		)

		it("semaine suivante : weeklyBest remis à zéro, tableau hebdo vidé, nouvelle couronne", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			step(ctx, T0)
			ctx.Signals.Parade:Fire(a, parade(14))
			local week = ctx.Clock.week()
			local monday = T0 + ctx.Clock.untilNextWeek(T0) + 1
			ordered(ctx, "WeeklyConga_" .. week):SetAsync("1", 14)
			step(ctx, monday)
			expect(da.weeklyBest).toEqual({ week = week + 1, conga = 0 })
			expect(ctx.L.weeklyTop()).toEqual({})
			local function crowned()
				for _, e in ctx.crowned do
					if e.p == a then
						return true
					end
				end
				return false
			end
			expect(crowned()).toBe(true)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("LeaderboardService › charges invalides et cycle de vie", function()
		it("longueurs et parades absurdes ignorées sans erreur", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			expect(function()
				ctx.Signals.LineChanged:Fire(a, 0 / 0)
				ctx.Signals.LineChanged:Fire(a, math.huge)
				ctx.Signals.LineChanged:Fire(a, "9")
				ctx.Signals.Parade:Fire(a, { count = 0 / 0 })
				ctx.Signals.Parade:Fire(a, { count = 1.5 })
				ctx.Signals.Parade:Fire(a, { count = -4 })
				ctx.Signals.Parade:Fire(a, nil)
				ctx.Signals.AtlasEntry:Fire(a, 1, 0, 0 / 0)
				ctx.L.step(0 / 0)
			end).notToThrow()
			step(ctx, T0)
			expect(#ctx.L.liveTop()).toBe(0)
			expect(ctx.L.serverRecord()).toBeNil()
			expect(da.weeklyBest.conga).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("weeklyBest remis à la semaine courante à l'arrivée, répliqué au step suivant", function()
			local ctx = boot()
			local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
			local Schema = ctx.h:require("ServerScriptService.Server.Data.Schema")
			local profile = Schema.defaults()
			profile.weeklyBest = { week = ctx.Clock.week() - 3, conga = 77 }
			store:SetAsync("player_5", { data = profile })
			local p, data = join(ctx, 5)
			expect(data.weeklyBest).toEqual({ week = ctx.Clock.week(), conga = 0 })
			local function sent()
				for _, args in ctx.h:sentTo(p, "DataPatch") do
					if args[1].weeklyBest ~= nil then
						return true
					end
				end
				return false
			end
			expect(sent()).toBe(false)
			step(ctx, T0)
			expect(sent()).toBe(true)
		end)

		it("stèle initialisée au démarrage ; une parade d'un joueur parti n'écrit rien", function()
			local ctx = boot()
			expect(board(ctx, "Live")).toBe("")
			expect(board(ctx, "Record")).toBe("")
			expect(board(ctx, "Weekly")).toBe("")
			local a = join(ctx, 1)
			ctx.h:removePlayer(a)
			ctx.h:settle(3)
			ctx.Signals.Parade:Fire(a, parade(20))
			expect(ctx.L.serverRecord()).toBeNil()
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("LeaderboardService › revue : pannes, fermeture, anti-triche", function()
		local function crownedIds(ctx)
			local out = {}
			for _, e in ctx.crowned do
				if e.kind == "titles" and e.id == "conga_royal" then
					table.insert(out, e.p.UserId)
				end
			end
			return out
		end

		it("couronne : lecture en échec au démarrage, nouvel essai à la lecture suivante", function()
			local ctx = boot({
				before = function(c)
					local week = c.Clock.week()
					local s = c.h.game.DataStoreService:GetOrderedDataStore("WeeklyConga_" .. (week - 1))
					s:SetAsync("1", 44)
				end,
			})
			local a = join(ctx, 1)
			-- couronne (3 essais) et top 10 de la semaine (3 essais) en panne au premier passage
			ctx.h.dataStoreFailures = 6
			step(ctx, T0)
			ctx.h:settle(5)
			expect(ctx.h.dataStoreFailures).toBe(0)
			expect(#crownedIds(ctx)).toBe(0)
			step(ctx, T0 + 60)
			expect(#crownedIds(ctx)).toBe(0)
			step(ctx, T0 + 120)
			ctx.h:settle(5)
			expect(crownedIds(ctx)).toEqual({ 1 })
			-- connue : plus de nouvelle lecture de la couronne
			step(ctx, T0 + 240)
			ctx.h:settle(5)
			expect(crownedIds(ctx)).toEqual({ 1 })
			expect(a.Parent ~= nil).toBe(true)
		end)

		it("fermeture du serveur : les records en file sont écrits (BindToClose)", function()
			local ctx = boot()
			local a = join(ctx, 1)
			step(ctx, T0)
			local store = "WeeklyConga_" .. ctx.Clock.week()
			ctx.Signals.Parade:Fire(a, parade(17))
			ctx.Signals.AtlasEntry:Fire(a, 1, 0, 11)
			step(ctx, T0 + 30) -- avant le vidage des 60 s
			expect(storedValue(ctx, store, 1)).toBeNil()
			ctx.h:close()
			ctx.h:settle(3)
			expect(storedValue(ctx, store, 1)).toBe(17)
			expect(storedValue(ctx, "AtlasAllTime", 1)).toBe(11)
		end)

		it("joueur signalé APRÈS la mise en file de son record : jamais écrit", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			step(ctx, T0)
			local store = "WeeklyConga_" .. ctx.Clock.week()
			ctx.Signals.Parade:Fire(a, parade(40))
			ctx.Signals.AtlasEntry:Fire(a, 1, 0, 12)
			-- CongaService pose le drapeau (1 500 captures / h) avant le vidage
			da.flags.lbBanned = true
			step(ctx, T0 + 60)
			ctx.h:settle(3)
			expect(storedValue(ctx, store, 1)).toBeNil()
			expect(storedValue(ctx, "AtlasAllTime", 1)).toBeNil()
			-- et la file ne le garde pas pour plus tard
			da.flags.lbBanned = false
			step(ctx, T0 + 120)
			ctx.h:settle(3)
			expect(storedValue(ctx, store, 1)).toBeNil()
		end)
	end)
end
