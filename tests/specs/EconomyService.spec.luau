--!nocheck
-- EconomyService : règlement paresseux, M, hors ligne, améliorations, Supernova, Stardust et
-- plafonds du jour, boosts, crochet de sauvegarde, charges malveillantes et cycle de vie.

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- 15/01/2027, temps figé de départ
	local RARE = { s = 16, f = 0, v = 0, st = 1 } -- Cometcub ★1 : 15 Glow/s perché

	local function boot(before)
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		if before then
			before(h)
		end
		h:boot()
		return {
			h = h,
			Clock = Clock,
			DS = DS,
			E = h:require("ServerScriptService.Server.Services.EconomyService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
		}
	end

	-- Sauvegarde existante (profil complet) avant l'arrivée du joueur
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
		local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, data
	end

	-- Donne un revenu passif « perché » sans passer par la collection
	local function setIncome(ctx, p, income)
		local data = ctx.DS.get(p)
		ctx.E.settle(p)
		data.perchIncome = income
		ctx.E.refreshRate(p)
	end

	local function economyEvents(h, sku)
		local out = {}
		for _, e in h.log.analytics do
			if e.method == "LogEconomyEvent" and (sku == nil or e.args[7] == sku) then
				table.insert(out, e.args)
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

	local function celebrations(h, p, kind)
		local out = {}
		for _, args in h:sentTo(p, "Celebrate") do
			if kind == nil or args[1].kind == kind then
				table.insert(out, args[1])
			end
		end
		return out
	end

	describe("EconomyService › règlement paresseux", function()
		it("crédite floor(taux × dt + reste) et garde la fraction dans glowCarry", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			setIncome(ctx, p, 3) -- M = 1 → 3 Glow/s
			expect(data.idleRate).toBe(3)
			local settled = {}
			ctx.Signals.IdleSettled:Connect(function(pl, glow, seconds)
				table.insert(settled, { pl = pl, glow = glow, seconds = seconds })
			end)
			ctx.Clock.advance(10.5)
			expect(ctx.E.settle(p)).toBe(31)
			expect(data.glow).toBe(31)
			expect(data.glowCarry).toBeNear(0.5)
			ctx.Clock.advance(0.5)
			expect(ctx.E.settle(p)).toBe(2) -- 1,5 + 0,5 de reste
			expect(data.glow).toBe(33)
			expect(data.glowCarry).toBeNear(0)
			ctx.h:settle(1)
			expect(#settled).toBe(2)
			expect(settled[1].seconds).toBeNear(10.5)
			expect(settled[1].glow).toBe(31)
			expect(data.lastSettle).toBe(T0 + 11)
		end)

		it("step règle chaque joueur toutes les 30 s, décalé selon son index", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			local b, db = join(ctx, 2)
			setIncome(ctx, a, 1)
			setIncome(ctx, b, 1)
			local now = ctx.Clock.now()
			ctx.E.step(now) -- a : maintenant ; b : dans 15 s
			expect(da.lastSettle).toBe(now)
			ctx.Clock.advance(14)
			ctx.E.step(ctx.Clock.now())
			expect(db.glow).toBe(0)
			ctx.Clock.advance(1)
			ctx.E.step(ctx.Clock.now())
			expect(db.glow).toBe(15)
			expect(da.glow).toBe(0)
			ctx.Clock.advance(15)
			ctx.E.step(ctx.Clock.now())
			expect(da.glow).toBe(30)
		end)

		it("une fin de boost est réglée à l'instant exact (ancien taux puis nouveau)", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			setIncome(ctx, p, 10)
			ctx.E.grantPersonalBoost(p, 60)
			expect(data.idleRate).toBe(20)
			expect(ctx.E.hasBoost(p)).toBe(true)
			ctx.Clock.advance(100)
			ctx.E.step(ctx.Clock.now())
			-- 60 s à 20/s + 40 s à 10/s
			expect(data.glow).toBe(60 * 20 + 40 * 10)
			expect(data.idleRate).toBe(10)
			expect(ctx.E.hasBoost(p)).toBe(false)
		end)

		it("le crochet de sauvegarde règle le revenu passif avant chaque écriture", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			setIncome(ctx, p, 2)
			ctx.Clock.advance(50)
			expect(ctx.DS.saveNow(p)).toBe(true)
			local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
			local saved = store:GetAsync("player_1").data
			expect(saved.glow).toBe(100)
			expect(saved.lastOnline).toBe(T0 + 50)
			expect(data.glow).toBe(100)
		end)

		it("idleRate et lastSettle sont répliqués quand le taux change", function()
			local ctx = boot()
			local p = join(ctx, 1)
			ctx.h.log.clientEvents = {}
			setIncome(ctx, p, 4)
			ctx.h:settle(2)
			local patch = {}
			for _, args in ctx.h:sentTo(p, "DataPatch") do
				for k, v in args[1] do
					patch[k] = v
				end
			end
			expect(patch.idleRate).toBe(4)
			expect(patch.lastSettle).toBe(T0)
		end)
	end)

	describe("EconomyService › multiplicateur M", function()
		it("R, VIP, équipiers (max 3), Double Glow et boost ×2 non cumulable", function()
			local ctx = boot()
			seed(ctx, 1, { supernovas = 2, passes = { VIPStar = true, DoubleGlow = true } })
			local p, data = join(ctx, 1)
			-- (1 + 0,8 + 0,25) × 2
			expect(ctx.E.multiplier(p)).toBeNear(4.1)
			ctx.E.setCrewPresent(p, 5)
			expect(ctx.E.multiplier(p)).toBeNear((1 + 0.8 + 0.25 + 0.3) * 2)
			ctx.E.grantPersonalBoost(p, 100)
			ctx.E.setServerBoostUntil(T0 + 100)
			expect(ctx.E.multiplier(p)).toBeNear((1 + 0.8 + 0.25 + 0.3) * 2 * 2)
			setIncome(ctx, p, 10)
			expect(data.idleRate).toBeNear(10 * 2.35 * 4)
			ctx.E.setCrewPresent(p, 0)
			expect(data.idleRate).toBeNear(10 * 2.05 * 4)
		end)

		it("le boost de serveur règle tout le monde à l'ancien taux puis double le revenu", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			local b, db = join(ctx, 2)
			setIncome(ctx, a, 1)
			setIncome(ctx, b, 2)
			ctx.Clock.advance(10)
			ctx.E.setServerBoostUntil(T0 + 70)
			expect(da.glow).toBe(10)
			expect(db.glow).toBe(20)
			expect(da.idleRate).toBe(2)
			expect(db.idleRate).toBe(4)
			ctx.Clock.advance(100)
			ctx.E.settle(a)
			expect(da.glow).toBe(10 + 60 * 2 + 40 * 1)
		end)

		it("paradeGlow : M au moment de la parade, Conga Bonus plafonné en Zen", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local Nebbies = ctx.h:require("ReplicatedStorage.Shared.Config.Nebbies")
			local codes = {}
			for i = 1, 60 do
				codes[i] = Nebbies.pack(1, 0, 0)
			end
			-- 60 Communs : 1 200 × 5
			expect(ctx.E.paradeGlow(p, codes, false)).toBe(6000)
			expect(ctx.E.paradeGlow(p, codes, true)).toBe(9000)
			data.settings.zen = true
			expect(ctx.E.paradeGlow(p, codes, false)).toBe(3000)
			expect(ctx.E.paradeGlow(p, { "x", 0 / 0 }, false)).toBe(0)
		end)

		it("boosts personnels prolongés depuis max(maintenant, fin), jamais ×4", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.E.grantPersonalBoost(p, 600)
			ctx.E.grantPersonalBoost(p, 600)
			expect(data.boosts.personalUntil).toBe(T0 + 1200)
			ctx.Clock.advance(2000)
			ctx.E.grantPersonalBoost(p, 60)
			expect(data.boosts.personalUntil).toBe(T0 + 2060)
			ctx.E.grantPersonalBoost(p, 0 / 0)
			ctx.E.grantPersonalBoost(p, -5)
			ctx.E.grantPersonalBoost(p, math.huge)
			expect(data.boosts.personalUntil).toBe(T0 + 2060)
		end)
	end)

	describe("EconomyService › hors ligne et écran de retour", function()
		it("crédite 50 % du revenu sans boost ni équipage, et ouvre l'écran de retour", function()
			local ctx = boot()
			seed(ctx, 1, {
				supernovas = 1,
				nebbies = { u1 = RARE },
				nextUid = 2,
				perchIncome = 15,
				idleRate = 999, -- taux de la session précédente (boostée) : ignoré
				lastOnline = T0 - 3600,
				lastSettle = T0 - 3600,
				boosts = { personalUntil = T0 + 500 },
			})
			local p, data = join(ctx, 1)
			-- 15 × 1,4 × 3 600 × 0,5
			expect(data.glow).toBe(37800)
			expect(data.lastSettle).toBe(T0)
			expect(data.lastOnline).toBe(T0)
			local cel = celebrations(ctx.h, p, "offline")
			expect(#cel).toBe(1)
			expect(cel[1].data.glow).toBe(37800)
			expect(cel[1].data.seconds).toBe(3600)
			expect(cel[1].data.nightShift).toBe(false)
			expect(#economyEvents(ctx.h, "Offline")).toBe(1)
			-- le boost personnel encore actif s'applique au revenu EN LIGNE
			expect(data.idleRate).toBeNear(15 * 1.4 * 2)
		end)

		it("plafond 8 h ; Night Shift : 75 % pendant 12 h", function()
			local ctx = boot()
			seed(ctx, 1, { perchIncome = 1, lastOnline = T0 - 20 * 3600 })
			seed(ctx, 2, { perchIncome = 1, lastOnline = T0 - 20 * 3600, passes = { NightShift = true } })
			local _, d1 = join(ctx, 1)
			local p2, d2 = join(ctx, 2)
			expect(d1.glow).toBe(8 * 3600 * 0.5)
			expect(d2.glow).toBe(12 * 3600 * 0.75)
			local cel = celebrations(ctx.h, p2, "offline")
			expect(cel[1].data.seconds).toBe(12 * 3600)
			expect(cel[1].data.nightShift).toBe(true)
			expect(cel[1].data.away).toBe(20 * 3600)
		end)

		it("pas d'écran de retour sous le seuil ; rien au premier chargement", function()
			local ctx = boot()
			seed(ctx, 1, { perchIncome = 1, lastOnline = T0 - 100 })
			local p1, d1 = join(ctx, 1)
			expect(d1.glow).toBe(50)
			expect(#celebrations(ctx.h, p1, "offline")).toBe(0)
			local p2, d2 = join(ctx, 2)
			expect(d2.glow).toBe(0)
			expect(d2.lastOnline).toBe(T0)
			expect(#celebrations(ctx.h, p2, "offline")).toBe(0)
		end)

		it(
			"un PassGranted avant le traitement du profil ne crédite jamais le temps hors ligne en plein",
			function()
				local ctx = boot()
				seed(ctx, 1, {
					nebbies = { u1 = RARE },
					nextUid = 2,
					perchIncome = 15,
					idleRate = 15,
					lastSettle = T0 - 3600,
					lastOnline = T0 - 3600,
					passes = { DoubleGlow = true },
				})
				local _, data = join(ctx, 1)
				-- hors ligne avec Double Glow : 15 × 2 × 3 600 × 0,5, et pas 15 × 3 600 en ligne
				expect(data.glow).toBe(54000)
				expect(data.idleRate).toBe(30)
			end
		)

		it("départ puis retour : le temps d'absence est compté depuis la dernière sauvegarde", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			setIncome(ctx, p, 2)
			ctx.Clock.advance(10)
			ctx.h:removePlayer(p)
			ctx.h:settle(5)
			ctx.Clock.advance(1000)
			local _, d2 = join(ctx, 1)
			expect(data.glow).toBe(20)
			expect(d2.glow).toBe(20 + 1000) -- 2 × 1 000 × 0,5
		end)
	end)

	describe("EconomyService › améliorations", function()
		it("achète au coût du GDD après règlement, signale et célèbre", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local bought = {}
			ctx.Signals.UpgradeBought:Connect(function(pl, track, level)
				table.insert(bought, { track = track, level = level })
			end)
			setIncome(ctx, p, 5)
			ctx.Clock.advance(10) -- 50 Glow réglés à l'achat
			ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "conga")
			expect(data.upgrades.conga).toBe(1)
			expect(data.glow).toBe(0)
			expect(bought[1]).toEqual({ track = "conga", level = 1 })
			local cel = celebrations(ctx.h, p, "upgrade")
			expect(cel[1].data).toEqual({ track = "conga", level = 1 })
			local spends = economyEvents(ctx.h, "Upgrade_conga_1")
			expect(#spends).toBe(1)
			expect(spends[1][4]).toBe(50)
			expect(spends[1][6]).toBe("Shop")
		end)

		it("refuse sans assez de Glow (Feedback missing) et au niveau max", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			data.glow = 30
			ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "stride")
			expect(data.upgrades.stride).toBe(0)
			expect(data.glow).toBe(30)
			local fb = ctx.h:sentTo(p, "Feedback")
			expect(fb[#fb][1]).toEqual({
				key = "feedback.notEnoughGlow",
				vars = { missing = 50 },
				tone = "error",
			})
			data.upgrades.guard = 5
			data.glow = 10 ^ 9
			ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "guard")
			expect(data.upgrades.guard).toBe(5)
			expect(data.glow).toBe(10 ^ 9)
			expect(feedbackKeys(ctx.h, p)[2]).toBe("feedback.maxLevel")
			-- Conga : 12 + 5 × R
			data.upgrades.conga = 12
			expect(ctx.E.buyUpgrade(p, "conga")).toBe(false)
			data.supernovas = 1
			expect(ctx.E.buyUpgrade(p, "conga")).toBe(true)
			expect(data.upgrades.conga).toBe(13)
		end)

		it("ignore les charges malveillantes sans erreur ni mutation", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			data.glow = 10 ^ 6
			local before = data.glow
			-- arguments en trop ignorés (le débit est vérifié avant tout : l'appel valide d'abord)
			ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "conga", "extra", 0 / 0)
			for _, bad in
				{
					nil,
					0 / 0,
					math.huge,
					1,
					true,
					{},
					{ "conga" },
					"",
					"speed",
					string.rep("c", 5000),
					"Conga",
				}
			do
				ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, bad)
			end
			expect(data.upgrades.conga).toBe(1)
			expect(data.glow).toBe(before - 50)
			expect(#feedbackKeys(ctx.h, p)).toBe(0)
		end)

		it("limite le débit à 10 achats par seconde", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			data.glow = 10 ^ 12
			for _ = 1, 30 do
				ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "stride")
			end
			expect(data.upgrades.stride >= 10).toBe(true)
			expect(data.upgrades.stride <= 11).toBe(true)
		end)

		it("ignore un joueur dont le profil n'est pas chargé", function()
			local ctx = boot()
			ctx.h.dataStoreFailures = 100
			local p = ctx.h:addPlayer({ userId = 5 })
			ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "conga")
			ctx.h:fireServer("ReplicatedStorage.Remotes.Supernova", p)
			expect(ctx.E.settle(p)).toBe(0)
			expect(ctx.E.addGlow(p, 10, "Parade")).toBe(0)
			expect(ctx.E.idleRate(p)).toBe(0)
			ctx.h.dataStoreFailures = 0
			ctx.h:removePlayer(p)
		end)
	end)

	describe("EconomyService › Supernova", function()
		it("encaisse la file d'abord, puis paie, remet à zéro et garde le reste", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local banked = 0
			ctx.E.setLineBanker(function(pl)
				banked += 1
				ctx.E.addGlow(pl, 300000, "Parade")
			end)
			local signals, banners = {}, {}
			ctx.Signals.Supernova:Connect(function(pl, R)
				table.insert(signals, R)
			end)
			ctx.Signals.BannerRequested:Connect(function(kind, args)
				table.insert(banners, { kind = kind, level = args.level, userId = args.userId })
			end)
			data.glow = 150000
			data.glowCarry = 0.7
			data.stardust = 77
			data.upgrades = { conga = 7, stride = 4, lure = 3, perches = 6, guard = 2 }
			setIncome(ctx, p, 10)
			ctx.h:fireServer("ReplicatedStorage.Remotes.Supernova", p)
			expect(banked).toBe(1)
			expect(data.supernovas).toBe(1)
			expect(data.glow).toBe(0)
			expect(data.glowCarry).toBe(0)
			expect(data.upgrades).toEqual({ conga = 0, stride = 0, lure = 0, perches = 6, guard = 2 })
			expect(data.stardust).toBe(77)
			expect(data.idleRate).toBeNear(14)
			ctx.h:settle(1)
			expect(signals).toEqual({ 1 })
			expect(banners[1]).toEqual({ kind = "supernova", level = 1, userId = 1 })
			expect(celebrations(ctx.h, p, "supernova")[1].data.level).toBe(1)
			expect(#economyEvents(ctx.h, "Supernova_1")).toBe(1)
		end)

		it("refuse hors du port sûr de son Nid, sans encaisser la file", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local banked = 0
			ctx.E.setLineBanker(function()
				banked += 1
			end)
			data.glow = 10 ^ 7
			ctx.h:moveTo(p, ctx.h.globals.Vector3.new(0, 5, 0))
			ctx.h:fireServer("ReplicatedStorage.Remotes.Supernova", p)
			expect(data.supernovas).toBe(0)
			expect(banked).toBe(0)
			expect(feedbackKeys(ctx.h, p)[1]).toBe("feedback.notInHarbor")
			-- sans personnage non plus
			p.Character:Destroy()
			p.Character = nil
			expect(ctx.E.trySupernova(p)).toBe(false)
		end)

		it("refuse sans assez de Glow ; un crochet défaillant ne bloque pas", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.E.setLineBanker(function()
				error("file cassée")
			end)
			data.glow = 399999
			local ok, reason = ctx.E.trySupernova(p)
			expect(ok).toBe(false)
			expect(reason).toBe("feedback.notEnoughGlow")
			expect(data.glow).toBe(399999)
			local fb = ctx.h:sentTo(p, "Feedback")
			expect(fb[#fb][1].vars.missing).toBe(1)
			expect(#ctx.h:warnings() >= 1).toBe(true)
		end)

		it("débit 1 / 2 s : une rafale ne fait qu'une Supernova", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			data.glow = 10 ^ 9
			for _ = 1, 10 do
				ctx.h:fireServer("ReplicatedStorage.Remotes.Supernova", p)
			end
			expect(data.supernovas).toBe(1)
		end)

		it("aperçu : coût, gains, aura, gardé / remis à zéro", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			data.supernovas = 2
			data.glow = 50000000
			local preview = ctx.E.supernovaPreview(p)
			expect(preview.level).toBe(2)
			expect(preview.cost).toBe(ctx.Formulas.supernovaCost(2))
			expect(preview.canAfford).toBe(true)
			expect(preview.inHarbor).toBe(true)
			expect(preview.incomeNow).toBeNear(0.8)
			expect(preview.incomeNext).toBeNear(1.2)
			expect(preview.congaCapNow).toBe(22)
			expect(preview.congaCapNext).toBe(27)
			expect(preview.dashNow).toBe(6.5)
			expect(preview.dashNext).toBe(6.25)
			expect(preview.auraNext).toBe("silver")
			expect(preview.resets).toEqual({ "glow", "conga", "stride", "lure" })
			expect(preview.keeps).toEqual({
				"nebbies",
				"perches",
				"guard",
				"stardust",
				"atlas",
				"cosmetics",
				"quests",
				"stats",
			})
			data.supernovas = 3
			expect(ctx.E.supernovaPreview(p).auraNext).toBeNil()
		end)
	end)

	describe("EconomyService › Glow et Stardust", function()
		it("addGlow / addGlowSeconds / trySpendGlow : entiers, jamais négatifs ni NaN", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			expect(ctx.E.addGlow(p, 12.9, "Quest_q1", "Onboarding")).toBe(12)
			for _, bad in { 0 / 0, math.huge, -math.huge, -5, 0 } do
				expect(ctx.E.addGlow(p, bad, "Parade")).toBe(0)
				expect(ctx.E.addStardust(p, bad, "Snip")).toBe(0)
				expect(ctx.E.trySpendGlow(p, bad == 0 and -1 or bad, "x")).toBe(false)
			end
			expect(data.glow).toBe(12)
			expect(ctx.E.trySpendGlow(p, 13, "Upgrade_x")).toBe(false)
			expect(ctx.E.trySpendGlow(p, 12, "Upgrade_x")).toBe(true)
			expect(data.glow).toBe(0)
			-- 120 s de revenu, minimum respecté
			expect(ctx.E.addGlowSeconds(p, 120, "Comet", 500)).toBe(500)
			setIncome(ctx, p, 10)
			expect(ctx.E.addGlowSeconds(p, 120, "Comet", 500)).toBe(1200)
			expect(data.glow).toBe(1700)
			local onboarding = economyEvents(ctx.h, "Quest_q1")
			expect(onboarding[1][6]).toBe("Onboarding")
			expect(economyEvents(ctx.h, "Comet")[1][6]).toBe("Gameplay")
		end)

		it("Stardust : ajout et dépense", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			expect(ctx.E.addStardust(p, 40.7, "Quest_3")).toBe(40)
			expect(ctx.E.trySpendStardust(p, 41, "Starforge_2")).toBe(false)
			expect(ctx.E.trySpendStardust(p, 25, "Starforge_2")).toBe(true)
			expect(data.stardust).toBe(15)
			expect(ctx.E.trySpendStardust(p, 0 / 0, "Starforge_2")).toBe(false)
			expect(economyEvents(ctx.h, "Starforge_2")[1][6]).toBe("Shop")
		end)

		it("plafonds du jour UTC : coupes, Gloomwisps, acclamations, Duo, remise à zéro", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			expect(ctx.E.addStardustCapped(p, 180, "snipDust", "Snip")).toBe(180)
			expect(ctx.E.addStardustCapped(p, 50, "snipDust", "Snip")).toBe(20)
			expect(ctx.E.addStardustCapped(p, 5, "snipDust", "Snip")).toBe(0)
			expect(ctx.E.addStardustCapped(p, 10, "wispDust", "Wisp")).toBe(10)
			for _ = 1, 10 do
				expect(ctx.E.addStardustCapped(p, 5, "cheers", "Cheer")).toBe(5)
			end
			expect(ctx.E.addStardustCapped(p, 5, "cheers", "Cheer")).toBe(0)
			expect(ctx.E.addStardustCapped(p, 50, "duo", "Duo")).toBe(50)
			expect(ctx.E.addStardustCapped(p, 50, "duo", "Duo")).toBe(0)
			expect(data.stardust).toBe(200 + 10 + 50 + 50)
			expect(data.caps.day).toBe(ctx.Clock.day())
			-- clé inconnue, montants invalides
			expect(ctx.E.addStardustCapped(p, 5, "nope", "x")).toBe(0)
			expect(ctx.E.addStardustCapped(p, 0 / 0, "wispDust", "Wisp")).toBe(0)
			-- nouveau jour UTC
			ctx.Clock.advance(86400)
			expect(ctx.E.addStardustCapped(p, 500, "snipDust", "Snip")).toBe(200)
			expect(ctx.E.addStardustCapped(p, 50, "duo", "Duo")).toBe(50)
			expect(data.caps.cheers).toBe(0)
		end)
	end)

	describe("EconomyService › cycle de vie", function()
		it("joueurs déjà présents au démarrage, départ, équipiers nettoyés", function()
			local ctx = boot(function(h)
				h:addPlayer({ userId = 9, name = "Early" })
			end)
			local p = ctx.h.game.Players:GetPlayers()[1]
			ctx.h:settle(5)
			local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
			expect(data ~= nil).toBe(true)
			ctx.E.setCrewPresent(p, 2)
			expect(ctx.E.multiplier(p)).toBeNear(1.2)
			ctx.h:removePlayer(p)
			ctx.h:settle(3)
			expect(ctx.E.multiplier(p)).toBe(1)
			ctx.E.setCrewPresent(p, 3) -- joueur parti : ignoré
			expect(ctx.E.settle(p)).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("départ pendant l'encaissement de la file : pas de Supernova pour un joueur parti", function()
			-- défaut : DataService garde le profil pendant la sauvegarde de départ ; seule l'identité du
			-- profil était revérifiée après le crochet, la Supernova était donc accordée au joueur parti
			local ctx = boot()
			local p, data = join(ctx, 1)
			data.glow = 10 ^ 7
			local signals = 0
			ctx.Signals.Supernova:Connect(function()
				signals += 1
			end)
			ctx.E.setLineBanker(function(pl)
				ctx.h:removePlayer(pl) -- crochet lent : le joueur part pendant l'encaissement
			end)
			local ok = ctx.E.trySupernova(p)
			ctx.h:settle(3)
			expect(ok).toBe(false)
			expect(data.supernovas).toBe(0)
			expect(data.glow).toBe(10 ^ 7)
			expect(signals).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("profil corrompu au chargement : monnaies, reste, pistes, boosts et plafonds réparés", function()
			local ctx = boot()
			seed(ctx, 1, {
				glow = -50,
				glowCarry = 3,
				stardust = 12.7,
				supernovas = -1,
				upgrades = "x",
				boosts = 5,
				caps = 7,
				lastOnline = T0 - 100,
				lastSettle = T0 + 9999, -- dans le futur : ignoré
				nebbies = { u1 = RARE },
				nextUid = 2,
				perchIncome = 15,
			})
			local p, data = join(ctx, 1)
			expect(data.glow).toBe(750) -- 15 × 100 × 0,5 hors ligne, sur une base remise à 0
			expect(data.glowCarry).toBe(0)
			expect(data.stardust).toBe(12)
			expect(data.supernovas).toBe(0)
			expect(data.upgrades).toEqual({ conga = 0, stride = 0, lure = 0, perches = 0, guard = 0 })
			expect(data.boosts.personalUntil).toBe(0)
			expect(data.lastSettle).toBe(T0)
			expect(ctx.E.addStardustCapped(p, 50, "duo", "Duo")).toBe(50)
			expect(ctx.E.addStardustCapped(p, 500, "snipDust", "Snip")).toBe(200)
			ctx.Clock.advance(10)
			expect(ctx.E.settle(p)).toBe(150)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("réapparition et step sans personnage : aucune erreur", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			setIncome(ctx, p, 1)
			ctx.h:respawn(p)
			p.Character:Destroy()
			p.Character = nil
			ctx.Clock.advance(31)
			ctx.E.step(ctx.Clock.now())
			expect(data.glow).toBe(31)
			expect(ctx.E.supernovaPreview(p).inHarbor).toBe(false)
		end)
	end)
end
