--!nocheck
-- CrewService : équipages automatiques d'amis, invitations, départs, escorte, bonus d'équipage
-- (joueurs actifs), pings, acclamations, file des bannières de serveur, cadeau Duo, charges
-- malveillantes et cycle de vie.

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		if opts.noRateLimit then
			local RateLimit = h:require("ServerScriptService.Server.Util.RateLimit")
			RateLimit.allow = function()
				return true
			end
		end
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			C = h:require("ServerScriptService.Server.Services.CrewService"),
			Econ = h:require("ServerScriptService.Server.Services.EconomyService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Notify = h:require("ServerScriptService.Server.Util.Notify"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			Tuning = h:require("ServerScriptService.Server.Events.Tuning"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			V3 = h.globals.Vector3,
			present = {},
			changed = {},
		}
		h:boot()
		local setCrewPresent = ctx.Econ.setCrewPresent
		ctx.Econ.setCrewPresent = function(p, n)
			table.insert(ctx.present, { p = p, n = n })
			return setCrewPresent(p, n)
		end
		ctx.Signals.CrewChanged:Connect(function(list)
			table.insert(ctx.changed, list)
		end)
		return ctx
	end

	local function seed(ctx, userId, settings)
		local profile = ctx.Schema.defaults()
		for k, v in settings do
			profile.settings[k] = v
		end
		local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
		store:SetAsync("player_" .. userId, { data = profile })
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(3)
		return p, ctx.DS.get(p)
	end

	local R = "ReplicatedStorage.Remotes."

	local function feedbackKeys(h, p)
		local out = {}
		for _, args in h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	local function lastFeedback(h, p, key)
		local found = nil
		for _, args in h:sentTo(p, "Feedback") do
			if args[1].key == key then
				found = args[1]
			end
		end
		return found
	end

	local function allEvents(h, remote)
		local out = {}
		for _, e in h.log.allClientEvents do
			if e.remote == remote then
				table.insert(out, e.args[1])
			end
		end
		return out
	end

	local function has(list, v)
		return table.find(list, v) ~= nil
	end

	local function sorted(list)
		local copy = table.clone(list)
		table.sort(copy)
		return copy
	end

	-- ---------------------------------------------------------------------------------------------
	describe("CrewService › équipages automatiques (§6.1)", function()
		it("deux amis présents avec « Équipage auto » forment un équipage", function()
			local ctx = boot()
			ctx.h:makeFriends(1, 2)
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			expect(ctx.C.crewOf(a) ~= 0).toBe(true)
			expect(ctx.C.crewOf(a)).toBe(ctx.C.crewOf(b))
			expect(ctx.C.areCrewmates(a, b)).toBe(true)
			expect(ctx.C.areCrewmates(a, a)).toBe(false)
			expect(a:GetAttribute("CrewId")).toBe(ctx.C.crewOf(a))
			expect(b:GetAttribute("CrewId")).toBe(ctx.C.crewOf(a))
			local snap = ctx.C.snapshot()
			expect(#snap.crews).toBe(1)
			expect(sorted(snap.crews[1].userIds)).toEqual({ 1, 2 })
			local states = allEvents(ctx.h, "CrewState")
			expect(#states[#states].crews).toBe(1)
			expect(#ctx.changed >= 1).toBe(true)
			expect(ctx.C.crewmates(a)[1]).toBe(b)
			expect(ctx.C.escortersOf(b)[1]).toBe(a)
			local analytics = 0
			for _, e in ctx.h.log.analytics do
				if e.method == "LogCustomEvent" and e.args[2] == "CrewFormed" then
					analytics += 1
				end
			end
			expect(analytics >= 1).toBe(true)
		end)

		it(
			"pas d'équipage auto si l'un des deux l'a désactivé ; pas d'équipage entre inconnus",
			function()
				local ctx = boot()
				seed(ctx, 2, { autoCrew = false })
				ctx.h:makeFriends(1, 2)
				local a = join(ctx, 1)
				local b = join(ctx, 2)
				local c = join(ctx, 3)
				expect(ctx.C.crewOf(a)).toBe(0)
				expect(ctx.C.crewOf(b)).toBe(0)
				expect(ctx.C.crewOf(c)).toBe(0)
				expect(a:GetAttribute("CrewId")).toBe(0)
				-- réactivé : l'équipage se forme
				ctx.DS.get(b).settings.autoCrew = true
				ctx.Signals.SettingChanged:Fire(b, "autoCrew", true)
				ctx.h:settle(2)
				expect(ctx.C.areCrewmates(a, b)).toBe(true)
			end
		)

		it("4 au plus : le cinquième ami reste seul", function()
			local ctx = boot()
			for i = 1, 5 do
				for j = i + 1, 5 do
					ctx.h:makeFriends(i, j)
				end
			end
			local players = {}
			for i = 1, 5 do
				players[i] = join(ctx, i)
			end
			local snap = ctx.C.snapshot()
			expect(#snap.crews).toBe(1)
			expect(#snap.crews[1].userIds).toBe(ctx.Balance.Crew.MaxSize)
			expect(ctx.C.crewOf(players[5])).toBe(0)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CrewService › invitations, départs (§6.1)", function()
		it(
			"invitation acceptée, refusée, expirée, refusée par réglage, déjà équipiers, plein",
			function()
				local ctx = boot({ noRateLimit = true })
				local a = join(ctx, 10)
				local b = join(ctx, 11)
				local c, dc = join(ctx, 12)
				local d = join(ctx, 13)
				local e = join(ctx, 14)
				local f = join(ctx, 15)
				ctx.h:fireServer(R .. "CrewInvite", a, 11)
				local prompt = ctx.h:sentTo(b, "CrewInvitePrompt")
				expect(#prompt).toBe(1)
				expect(prompt[1][1].inviterId).toBe(10)
				expect(prompt[1][1].expiresAt).toBe(T0 + ctx.Balance.Crew.InviteTTL)
				expect(lastFeedback(ctx.h, a, "feedback.crewInviteSent").vars.name).toBe(b.DisplayName)
				ctx.h:fireServer(R .. "CrewRespond", b, 10, true)
				expect(ctx.C.areCrewmates(a, b)).toBe(true)
				expect(lastFeedback(ctx.h, a, "feedback.crewJoined").vars.name).toBe(b.DisplayName)
				-- déjà équipiers
				ctx.h:fireServer(R .. "CrewInvite", a, 11)
				expect(has(feedbackKeys(ctx.h, a), "feedback.crewAlready")).toBe(true)
				-- refus
				ctx.h:fireServer(R .. "CrewInvite", a, 12)
				ctx.h:fireServer(R .. "CrewRespond", c, 10, false)
				expect(ctx.C.crewOf(c)).toBe(0)
				expect(lastFeedback(ctx.h, a, "feedback.crewDeclined").vars.name).toBe(c.DisplayName)
				-- réponse déjà consommée : ignorée en silence
				ctx.h:fireServer(R .. "CrewRespond", c, 10, true)
				expect(ctx.C.crewOf(c)).toBe(0)
				-- expirée
				ctx.h:fireServer(R .. "CrewInvite", a, 12)
				ctx.Clock.freeze(T0 + ctx.Balance.Crew.InviteTTL + 1)
				ctx.h:fireServer(R .. "CrewRespond", c, 10, true)
				expect(ctx.C.crewOf(c)).toBe(0)
				expect(has(feedbackKeys(ctx.h, c), "feedback.crewExpired")).toBe(true)
				-- la cible refuse les invitations
				dc.settings.refuseInvites = true
				ctx.h:fireServer(R .. "CrewInvite", a, 12)
				expect(lastFeedback(ctx.h, a, "feedback.crewRefuses").vars.name).toBe(c.DisplayName)
				expect(#ctx.h:sentTo(c, "CrewInvitePrompt")).toBe(2)
				-- plein à 4
				for _, p in { d, e } do
					ctx.h:fireServer(R .. "CrewInvite", a, p.UserId)
					ctx.h:fireServer(R .. "CrewRespond", p, 10, true)
				end
				expect(#ctx.C.crewmates(a)).toBe(3)
				ctx.h:fireServer(R .. "CrewInvite", a, 15)
				expect(has(feedbackKeys(ctx.h, a), "feedback.crewFull")).toBe(true)
				expect(#ctx.h:sentTo(f, "CrewInvitePrompt")).toBe(0)
				-- f invite b (équipage plein) : b quitte le sien pour celui de f s'il accepte
				ctx.h:fireServer(R .. "CrewInvite", f, 11)
				ctx.h:fireServer(R .. "CrewRespond", b, 15, true)
				expect(ctx.C.areCrewmates(b, f)).toBe(true)
				expect(ctx.C.areCrewmates(a, b)).toBe(false)
				expect(#ctx.C.crewmates(a)).toBe(2)
			end
		)

		it("quitter : équipage d'un seul membre dissous, attributs remis à 0, Feedback", function()
			local ctx = boot({ noRateLimit = true })
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			ctx.h:fireServer(R .. "CrewInvite", a, 2)
			ctx.h:fireServer(R .. "CrewRespond", b, 1, true)
			expect(ctx.C.areCrewmates(a, b)).toBe(true)
			ctx.h:fireServer(R .. "CrewLeave", b)
			expect(ctx.C.crewOf(a)).toBe(0)
			expect(ctx.C.crewOf(b)).toBe(0)
			expect(a:GetAttribute("CrewId")).toBe(0)
			expect(b:GetAttribute("CrewId")).toBe(0)
			expect(has(feedbackKeys(ctx.h, b), "feedback.crewLeft")).toBe(true)
			expect(#ctx.C.snapshot().crews).toBe(0)
			-- sans équipage : rien
			ctx.h:fireServer(R .. "CrewLeave", b)
			local n = 0
			for _, k in feedbackKeys(ctx.h, b) do
				if k == "feedback.crewLeft" then
					n += 1
				end
			end
			expect(n).toBe(1)
		end)

		it("départ du serveur : retiré de l'équipage, invitations nettoyées", function()
			local ctx = boot({ noRateLimit = true })
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			local c = join(ctx, 3)
			for _, p in { b, c } do
				ctx.h:fireServer(R .. "CrewInvite", a, p.UserId)
				ctx.h:fireServer(R .. "CrewRespond", p, 1, true)
			end
			expect(#ctx.C.crewmates(a)).toBe(2)
			local d = join(ctx, 4)
			ctx.h:fireServer(R .. "CrewInvite", a, 4)
			ctx.h:removePlayer(a)
			ctx.h:settle(2)
			expect(ctx.C.areCrewmates(b, c)).toBe(true)
			expect(#ctx.C.crewmates(b)).toBe(1)
			ctx.h:fireServer(R .. "CrewRespond", d, 1, true)
			expect(ctx.C.crewOf(d)).toBe(0)
			ctx.h:removePlayer(b)
			ctx.h:settle(2)
			expect(ctx.C.crewOf(c)).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("débit : 1 invitation / 3 s", function()
			local ctx = boot()
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			local c = join(ctx, 3)
			ctx.h:fireServer(R .. "CrewInvite", a, 2)
			ctx.h:fireServer(R .. "CrewInvite", a, 3)
			expect(#ctx.h:sentTo(b, "CrewInvitePrompt")).toBe(1)
			expect(#ctx.h:sentTo(c, "CrewInvitePrompt")).toBe(0)
		end)

		it("charges malveillantes : aucune mutation, aucune erreur", function()
			local ctx = boot({ noRateLimit = true })
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			local bad = { 0 / 0, math.huge, -math.huge, 1.5, "2", {}, true, 999, 1 }
			for _, v in bad do
				ctx.h:fireServer(R .. "CrewInvite", a, v)
				ctx.h:fireServer(R .. "CrewRespond", b, v, true)
				ctx.h:fireServer(R .. "CrewRespond", b, 1, v)
				ctx.h:fireServer(R .. "Cheer", a, v)
				if v ~= 1 then
					ctx.h:fireServer(R .. "Ping", a, v)
				end
			end
			ctx.h:fireServer(R .. "CrewInvite", a)
			ctx.h:fireServer(R .. "CrewRespond", b)
			ctx.h:fireServer(R .. "CrewLeave", a, "x")
			expect(#ctx.h:sentTo(b, "CrewInvitePrompt")).toBe(0)
			expect(ctx.C.crewOf(a)).toBe(0)
			expect(ctx.C.crewOf(b)).toBe(0)
			expect(#allEvents(ctx.h, "PingShow")).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CrewService › bonus d'équipage et escorte (§6.1)", function()
		it("équipiers présents ET actifs (≥ 4 studs en 60 s) poussés à EconomyService", function()
			local ctx = boot({ noRateLimit = true })
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			ctx.h:fireServer(R .. "CrewInvite", a, 2)
			ctx.h:fireServer(R .. "CrewRespond", b, 1, true)
			local function lastFor(p)
				local n = nil
				for _, e in ctx.present do
					if e.p == p then
						n = e.n
					end
				end
				return n
			end
			ctx.C.step(T0)
			expect(lastFor(a) or 0).toBe(0)
			local root = b.Character.HumanoidRootPart.Position
			ctx.h:moveTo(b, root + ctx.V3.new(10, 0, 0))
			ctx.Clock.freeze(T0 + 1)
			ctx.C.step(T0 + 1)
			expect(lastFor(a)).toBe(1)
			expect(lastFor(b) or 0).toBe(0) -- a n'a pas bougé
			ctx.Clock.freeze(T0 + 1 + ctx.Balance.Spawn.ActiveWindow + 1)
			ctx.C.step(T0 + 1 + ctx.Balance.Spawn.ActiveWindow + 1)
			expect(lastFor(a)).toBe(0)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CrewService › pings et acclamations (§6.3, §6.6)", function()
		it("ping 1-6 diffusé à tous ; débit 1 / 1,5 s", function()
			local ctx = boot()
			local a = join(ctx, 1)
			ctx.h:fireServer(R .. "Ping", a, 3)
			ctx.h:fireServer(R .. "Ping", a, 4)
			local pings = allEvents(ctx.h, "PingShow")
			expect(#pings).toBe(1)
			expect(pings[1]).toEqual({ userId = 1, kind = 3 })
		end)

		it("pings hors bornes ignorés", function()
			local ctx = boot({ noRateLimit = true })
			local a = join(ctx, 1)
			for _, v in { 0, 7, -1, 2.5, "1", 0 / 0 } do
				ctx.h:fireServer(R .. "Ping", a, v)
			end
			expect(#allEvents(ctx.h, "PingShow")).toBe(0)
			ctx.h:fireServer(R .. "Ping", a, 6)
			expect(#allEvents(ctx.h, "PingShow")).toBe(1)
		end)

		it(
			"Supernova : bouton pour tous sauf le héros, +5 une fois par Supernova, plafond, compte au héros",
			function()
				local ctx = boot({ noRateLimit = true })
				local hero = join(ctx, 1)
				local a, da = join(ctx, 2)
				local b = join(ctx, 3)
				local c, dc = join(ctx, 4)
				local cheered = {}
				ctx.Signals.Cheered:Connect(function(x, y)
					table.insert(cheered, { x, y })
				end)
				ctx.Signals.Supernova:Fire(hero, 2)
				ctx.h:settle(1)
				expect(#ctx.h:sentTo(hero, "CheerPrompt")).toBe(0)
				local prompt = ctx.h:sentTo(a, "CheerPrompt")[1][1]
				expect(prompt).toEqual({ heroId = 1, level = 2, expiresAt = T0 + ctx.Balance.Cheer.Window })
				local d0 = da.stardust
				ctx.h:fireServer(R .. "Cheer", a, 1)
				ctx.h:fireServer(R .. "Cheer", a, 1)
				expect(da.stardust - d0).toBe(ctx.Balance.Cheer.Dust)
				expect(#cheered).toBe(1)
				expect(cheered[1][1]).toBe(a)
				expect(cheered[1][2]).toBe(hero)
				-- le héros ne s'acclame pas lui-même
				ctx.h:fireServer(R .. "Cheer", hero, 1)
				expect(#cheered).toBe(1)
				-- plafond du jour : acclamation comptée, sans Stardust
				dc.caps.day = ctx.Clock.day()
				dc.caps.cheers = ctx.Balance.DailyCaps.cheers
				local c0 = dc.stardust
				ctx.h:fireServer(R .. "Cheer", c, 1)
				expect(dc.stardust).toBe(c0)
				expect(has(feedbackKeys(ctx.h, c), "feedback.capReached")).toBe(true)
				expect(#cheered).toBe(2)
				-- fenêtre fermée : refusé ; le héros apprend combien l'ont acclamé
				ctx.Clock.freeze(T0 + ctx.Balance.Cheer.Window)
				ctx.C.step(T0 + ctx.Balance.Cheer.Window)
				ctx.h:fireServer(R .. "Cheer", b, 1)
				expect(#cheered).toBe(2)
				expect(lastFeedback(ctx.h, hero, "feedback.cheersReceived").vars.n).toBe(2)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CrewService › bannières de serveur (§6.5)", function()
		it("file de 3 triée par priorité, une diffusion toutes les 3 s, 1 / 10 s par source", function()
			local ctx = boot()
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			local c = join(ctx, 3)
			local d = join(ctx, 4)
			local N = ctx.Notify
			N.banner("weather", { key = "aurora", endsAt = T0 + 150 })
			local shown = allEvents(ctx.h, "Banner")
			expect(#shown).toBe(1)
			expect(shown[1].kind).toBe("weather")
			expect(shown[1].priority).toBe(N.BANNER_PRIORITY.weather)
			N.banner("megaParade", { userId = 1, name = "P1", n = 31 }, a)
			N.banner("megaParade", { userId = 1, name = "P1", n = 40 }, a) -- même source < 10 s
			N.banner("serverRecord", { userId = 4, name = "P4", n = 50 }, d)
			N.banner("mythicCatch", { userId = 2, name = "P2", code = 36 }, b)
			N.banner("legendaryCatch", { userId = 3, name = "P3", code = 29 }, c)
			N.banner("nope", {})
			local queued = ctx.C.queuedBanners()
			expect(#queued).toBe(ctx.Tuning.BannerQueueMax)
			expect(queued[1].kind).toBe("mythicCatch")
			expect(queued[2].kind).toBe("megaParade")
			expect(queued[2].args.n).toBe(31)
			expect(queued[3].kind).toBe("legendaryCatch")
			ctx.C.step(T0 + 1)
			expect(#allEvents(ctx.h, "Banner")).toBe(1)
			ctx.C.step(T0 + 3)
			shown = allEvents(ctx.h, "Banner")
			expect(#shown).toBe(2)
			expect(shown[2].kind).toBe("mythicCatch")
			ctx.C.step(T0 + 6)
			ctx.C.step(T0 + 9)
			shown = allEvents(ctx.h, "Banner")
			expect(#shown).toBe(4)
			expect(shown[3].kind).toBe("megaParade")
			expect(shown[4].kind).toBe("legendaryCatch")
			-- 10 s plus tard, la même source peut de nouveau
			ctx.Clock.freeze(T0 + 10)
			ctx.C.banner("megaParade", { n = 33 }, a)
			expect(#ctx.C.queuedBanners()).toBe(1)
			ctx.C.step(T0 + 12)
			shown = allEvents(ctx.h, "Banner")
			expect(#shown).toBe(5)
			expect(shown[5].args.n).toBe(33)
		end)

		it("arguments nettoyés (valeurs simples seulement)", function()
			local ctx = boot()
			local a = join(ctx, 1)
			ctx.Notify.banner(
				"weather",
				{ key = "frost", nan = 0 / 0, inf = math.huge, who = a, list = { 1 } }
			)
			local shown = allEvents(ctx.h, "Banner")
			expect(shown[1].args).toEqual({ key = "frost" })
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CrewService › cadeau Duo (§6.2)", function()
		it("10 min cumulées avec un ami : 50 Stardust aux deux, une fois par jour", function()
			local ctx = boot()
			ctx.h:makeFriends(1, 2)
			local a, da = join(ctx, 1)
			local b, db = join(ctx, 2)
			local a0, b0 = da.stardust, db.stardust
			local t = T0
			ctx.C.step(t)
			while t < T0 + ctx.Balance.Crew.DuoSeconds - 5 do
				t += 5
				ctx.Clock.freeze(t)
				ctx.C.step(t)
			end
			expect(da.stardust).toBe(a0)
			for _ = 1, 3 do
				t += 5
				ctx.Clock.freeze(t)
				ctx.C.step(t)
			end
			expect(da.stardust - a0).toBe(ctx.Balance.Crew.DuoDust)
			expect(db.stardust - b0).toBe(ctx.Balance.Crew.DuoDust)
			expect(lastFeedback(ctx.h, a, "feedback.duoGift").vars.name).toBe(b.DisplayName)
			expect(lastFeedback(ctx.h, b, "feedback.duoGift").vars.name).toBe(a.DisplayName)
			-- encore 10 min le même jour : rien de plus
			for _ = 1, 125 do
				t += 5
				ctx.Clock.freeze(t)
				ctx.C.step(t)
			end
			expect(da.stardust - a0).toBe(ctx.Balance.Crew.DuoDust)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CrewService › cycle de vie", function()
		it("arrivée : CrewState complet et attribut CrewId = 0 ; step tolère un temps non fini", function()
			local ctx = boot()
			local a = join(ctx, 1)
			expect(#ctx.h:sentTo(a, "CrewState") >= 1).toBe(true)
			expect(a:GetAttribute("CrewId")).toBe(0)
			expect(function()
				ctx.C.step(0 / 0)
				ctx.C.step(math.huge)
			end).notToThrow()
			expect(ctx.C.crewOf(a)).toBe(0)
			expect(#ctx.C.crewmates(a)).toBe(0)
			expect(#ctx.C.escortersOf(a)).toBe(0)
		end)

		it("départs : caches d'amitié et paires Duo nettoyés (pas de croissance sans fin)", function()
			local ctx = boot()
			ctx.h:makeFriends(1, 2)
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			local counts = ctx.C.debugCounts()
			expect(counts.friendCache >= 1).toBe(true)
			expect(counts.duoPairs).toBe(1)
			-- un ami part : la paire Duo reste (temps cumulé du jour), plus le cache de l'ami parti
			ctx.h:removePlayer(a)
			ctx.h:settle(2)
			expect(ctx.C.debugCounts().friendCache).toBe(0)
			expect(ctx.C.debugCounts().duoPairs).toBe(1)
			ctx.h:removePlayer(b)
			ctx.h:settle(2)
			expect(ctx.C.debugCounts()).toEqual({ friendCache = 0, duoPairs = 0 })
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CrewService › revue : priorités, toasts, UserIds", function()
		it(
			"une bannière plus prioritaire du même joueur n'est jamais avalée (Supernova après Méga Parade)",
			function()
				local ctx = boot()
				local a = join(ctx, 1)
				local b = join(ctx, 2)
				local N = ctx.Notify
				-- file occupée : la Supernova remplace en file les bannières moins importantes du
				-- même joueur, nées de la même action (parade forcée record + Méga Parade)
				N.banner("weather", { key = "aurora", endsAt = T0 + 150 })
				N.banner("serverRecord", { userId = 1, name = "P1", n = 35 }, a)
				N.banner("megaParade", { userId = 1, name = "P1", n = 35 }, a)
				N.banner("supernova", { userId = 1, name = "P1", level = 4 }, a)
				N.banner("megaParade", { userId = 1, name = "P1", n = 36 }, a) -- moins importante : ignorée
				local queued = ctx.C.queuedBanners()
				expect(#queued).toBe(1)
				expect(queued[1].kind).toBe("supernova")
				ctx.C.step(T0 + 3)
				local shown = allEvents(ctx.h, "Banner")
				expect(#shown).toBe(2)
				expect(shown[2].kind).toBe("supernova")
				expect(shown[2].args.level).toBe(4)
				-- file libre : la Méga Parade part tout de suite, la Supernova suit 3 s plus tard
				ctx.Clock.freeze(T0 + 20)
				N.banner("megaParade", { userId = 2, name = "P2", n = 31 }, b)
				N.banner("supernova", { userId = 2, name = "P2", level = 1 }, b)
				N.banner("legendaryCatch", { userId = 2, name = "P2", code = 29 }, b) -- < 10 s, moins importante
				shown = allEvents(ctx.h, "Banner")
				expect(shown[#shown].kind).toBe("megaParade")
				ctx.C.step(T0 + 23)
				shown = allEvents(ctx.h, "Banner")
				expect(shown[#shown].kind).toBe("supernova")
				expect(#ctx.C.queuedBanners()).toBe(0)
			end
		)

		it("équipage formé : toast avec les deux noms, aussi pour un équipage automatique", function()
			local ctx = boot({ noRateLimit = true })
			ctx.h:makeFriends(1, 2)
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			expect(ctx.C.areCrewmates(a, b)).toBe(true)
			-- l'hôte (premier chargé) apprend l'arrivée de l'ami, l'ami apprend qui l'accueille
			expect(lastFeedback(ctx.h, a, "feedback.crewJoined").vars.name).toBe(b.DisplayName)
			expect(lastFeedback(ctx.h, b, "feedback.crewWelcome").vars.name).toBe(a.DisplayName)
			-- invitation acceptée : l'invité reçoit aussi son toast, les membres le leur (une fois)
			local c = join(ctx, 3)
			ctx.h:fireServer(R .. "CrewInvite", a, 3)
			ctx.h:fireServer(R .. "CrewRespond", c, 1, true)
			expect(lastFeedback(ctx.h, c, "feedback.crewWelcome").vars.name).toBe(a.DisplayName)
			expect(lastFeedback(ctx.h, b, "feedback.crewJoined").vars.name).toBe(c.DisplayName)
			local n = 0
			for _, args in ctx.h:sentTo(a, "Feedback") do
				if args[1].key == "feedback.crewJoined" and args[1].vars.name == c.DisplayName then
					n += 1
				end
			end
			expect(n).toBe(1)
		end)

		it("UserId hors de la plage int64 : rejeté avant GetPlayerByUserId (aucune erreur)", function()
			local MockInstance = require("../harness/MockInstance")
			local ctx = boot({ noRateLimit = true })
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			-- comme Roblox : la conversion en int64 échoue au-delà de 2^63
			local methods = MockInstance.classMethods.Players
			local original = methods.GetPlayerByUserId
			methods.GetPlayerByUserId = function(self, id)
				if math.abs(id) >= 2 ^ 63 then
					error("Unable to cast double to int64")
				end
				return original(self, id)
			end
			for _, v in { 2 ^ 63, 2 ^ 70, -2 ^ 64, 1e300 } do
				ctx.h:fireServer(R .. "CrewInvite", a, v)
				ctx.h:fireServer(R .. "CrewRespond", b, v, true)
				ctx.h:fireServer(R .. "Cheer", a, v)
			end
			ctx.h:settle(2)
			methods.GetPlayerByUserId = original
			expect(#ctx.h.errors).toBe(0)
			expect(#ctx.h:sentTo(b, "CrewInvitePrompt")).toBe(0)
		end)
	end)
end
