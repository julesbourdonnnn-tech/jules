--!nocheck
-- Correctifs « restes serveur : économie et passes » :
--   * PassRevoked : un pass remboursé, retiré par la vérification d'arrivée PENDANT que
--     UserOwnsGamePassAsync yield, retire ses effets (idleRate, perchoirs, badge VIP, thème)
--   * « Merci ! » et analytique Pass_* seulement pour un achat VÉRIFIÉ (PassPurchased), jamais sur
--     le signal brut PromptGamePassPurchaseFinished (falsifiable)
--   * produit : attribution atomique vis-à-vis du reçu (un effet en échec n'empêche pas d'enregistrer
--     le reçu ; une redélivrance n'accorde rien de plus)
--   * attribut Player GuardLinks (rendu des files des autres joueurs) au chargement, à l'achat et
--     après une Supernova
--   * complément hors ligne quand la vérification des passes finit après le calcul du chargement
--     (achat sur le site pendant l'absence), jamais rétroactif pour un achat en jeu
--   * invariants de développement (GDD §12.6), actifs seulement dans Studio
--   * « chez soi » : l'arrière de sa plateforme de Nid compte pour la Supernova et le Zen
local task = require("@lune/task")
local Bots = require("../harness/Bots")
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local RARE = { s = 16, f = 0, v = 0, st = 1 } -- Cometcub ★1 : 15 Glow/s perché

	local PRODUCT_IDS = {
		GlowPouch = 501,
		GlowSack = 502,
		GlowCrate = 503,
		GlowParty = 504,
		StardustJar = 505,
		StarterKit = 506,
	}
	local PASS_IDS = {
		VIPStar = 601,
		DoubleGlow = 602,
		NightShift = 603,
		ExtraPerches = 604,
		StashPlus = 605,
		CongaStyles = 606,
	}

	-- opts.isStudio : invariants actifs ; opts.yieldOwnership (s) : UserOwnsGamePassAsync yield
	-- (comme le vrai appel web) ; opts.onOwnership() : appelé à chaque réponse
	local function boot(opts)
		opts = opts or {}
		local h = Harness.new({ isStudio = opts.isStudio == true })
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local M = h:require("ReplicatedStorage.Shared.Config.Monetization")
		for key, id in PRODUCT_IDS do
			M.Products[key].id = id
		end
		for key, id in PASS_IDS do
			M.Passes[key].id = id
		end
		local Mon = h:require("ServerScriptService.Server.Services.MonetizationService")
		Mon.Settings.VERIFY_ATTEMPTS = 2
		Mon.Settings.VERIFY_RETRY_DELAY = 0.02
		-- EventService isolé : file de Glow Party simulée
		local Ev = h:require("ServerScriptService.Server.Services.EventService")
		Ev.queueGlowParty = function(_buyer, seconds)
			return Clock.now() + seconds
		end
		if opts.yieldOwnership then
			local methods = MockInstance.classMethods.MarketplaceService
			local original = methods.UserOwnsGamePassAsync
			methods.UserOwnsGamePassAsync = function(self, userId, passId)
				task.wait(opts.yieldOwnership)
				if opts.onOwnership then
					opts.onOwnership(Clock)
				end
				return original(self, userId, passId)
			end
		end
		h:boot()
		return {
			h = h,
			Clock = Clock,
			DS = DS,
			M = M,
			Mon = Mon,
			Enum = h.globals.Enum,
			V3 = h.globals.Vector3,
			E = h:require("ServerScriptService.Server.Services.EconomyService"),
			A = h:require("ServerScriptService.Server.Services.AtlasService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			P = h:require("ServerScriptService.Server.Services.ProductService"),
			Inv = h:require("ServerScriptService.Server.Economy.Invariants"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			F = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Zones = h:require("ReplicatedStorage.Shared.Config.Zones"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
	end

	local function seed(ctx, userId, fields)
		local profile = ctx.Schema.defaults()
		for k, v in fields do
			profile[k] = v
		end
		local store = ctx.h.game.DataStoreService:GetDataStore(ctx.Schema.STORE_NAME)
		store:SetAsync("player_" .. userId, { data = profile })
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, data
	end

	local function rares(n)
		local out = {}
		for i = 1, n do
			out["u" .. i] = table.clone(RARE)
		end
		return out
	end

	local function celebrations(h, p, kind)
		local out = {}
		for _, args in h:sentTo(p, "Celebrate") do
			if args[1].kind == kind then
				table.insert(out, args[1])
			end
		end
		return out
	end

	local function customEvents(h, name)
		local n = 0
		for _, e in h.log.analytics do
			if e.method == "LogCustomEvent" and e.args[2] == name then
				n += 1
			end
		end
		return n
	end

	local function economyEvents(h, sku)
		local out = {}
		for _, e in h.log.analytics do
			if e.method == "LogEconomyEvent" and e.args[7] == sku then
				table.insert(out, e.args)
			end
		end
		return out
	end

	local function invariantWarnings(h)
		local out = {}
		for _, line in h:warnings() do
			if string.find(line, "INVARIANT", 1, true) then
				table.insert(out, line)
			end
		end
		return out
	end

	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	local function hasMatch(list, pattern)
		for _, line in list do
			if string.find(line, pattern, 1, true) then
				return true
			end
		end
		return false
	end

	-- ---------------------------------------------------------------------------------------------

	describe("Fix restes economy › pass remboursé (PassRevoked)", function()
		it("retiré pendant une vérification qui yield : taux, perchoirs, VIP et thème suivent", function()
			local ctx = boot({ isStudio = true, yieldOwnership = 0.05 })
			-- profil enregistré avec 3 passes, tous remboursés depuis (Roblox : non possédés)
			seed(ctx, 1, {
				nebbies = rares(9),
				nextUid = 10,
				perchIncome = 9 * 15,
				passes = { DoubleGlow = true, ExtraPerches = true, VIPStar = true },
				cosmetics = { style = "default", title = "", nestTheme = "royal_gold" },
			})
			local p, data = join(ctx, 1)
			-- pendant la vérification : effets des passes enregistrés (9 perchoirs, ×2, VIP)
			expect(ctx.A.perchCount(p)).toBe(9)
			task.wait(0.6) -- 6 vérifications × 0,05 s
			ctx.h:settle(3)
			expect(ctx.Mon.ownsPass(p, "DoubleGlow")).toBe(false)
			expect(ctx.Mon.ownsPass(p, "ExtraPerches")).toBe(false)
			expect(ctx.Mon.ownsPass(p, "VIPStar")).toBe(false)
			expect(ctx.A.perchCount(p)).toBe(3)
			expect(data.perchIncome).toBe(45)
			expect(ctx.E.multiplier(p)).toBe(1)
			expect(data.idleRate).toBe(data.perchIncome * ctx.E.multiplier(p))
			expect(data.idleRate).toBe(45)
			expect(p:GetAttribute("VIP")).toBe(false)
			expect(p:GetAttribute("NestTheme")).toBe("default")
			local nest = ctx.h.game.Workspace:FindFirstChild("Nests", true)
			if nest then
				local own = nest:FindFirstChild(string.format("Nest_%02d", ctx.N.slotOf(p)))
				if own then
					expect(own:GetAttribute("PerchCount")).toBe(3)
					expect(own:GetAttribute("NestTheme")).toBe("default")
				end
			end
			-- les invariants de développement ne voient rien d'incohérent à la sauvegarde
			expect(ctx.DS.saveNow(p)).toBe(true)
			expect(invariantWarnings(ctx.h)).toEqual({})
			expect(#ctx.h.errors).toBe(0)
		end)

		it("un pass encore possédé reste appliqué (aucun retrait sans réponse négative)", function()
			local ctx = boot({ yieldOwnership = 0.05 })
			seed(ctx, 1, {
				nebbies = rares(9),
				nextUid = 10,
				perchIncome = 9 * 15,
				passes = { DoubleGlow = true, ExtraPerches = true },
			})
			ctx.h.ownedPasses[1] = { [PASS_IDS.DoubleGlow] = true } -- Extra Perches remboursé
			local p, data = join(ctx, 1)
			task.wait(0.6)
			ctx.h:settle(3)
			expect(ctx.Mon.ownsPass(p, "DoubleGlow")).toBe(true)
			expect(ctx.A.perchCount(p)).toBe(3)
			expect(data.idleRate).toBe(45 * 2)
		end)
	end)

	describe("Fix restes economy › « Merci ! » sur achat vérifié seulement", function()
		it("signal d'achat falsifié : ni Celebrate ni analytique Pass_*", function()
			local ctx = boot()
			local p = join(ctx, 1)
			local signal = ctx.h.game.MarketplaceService.PromptGamePassPurchaseFinished
			for _ = 1, 3 do
				signal:Fire(p, PASS_IDS.VIPStar, true)
				signal:Fire(p, PASS_IDS.DoubleGlow, true)
			end
			task.wait(0.2) -- toutes les vérifications (2 essais) sont terminées
			ctx.h:settle(2)
			expect(ctx.Mon.ownsPass(p, "VIPStar")).toBe(false)
			expect(#celebrations(ctx.h, p, "purchase")).toBe(0)
			expect(customEvents(ctx.h, "Pass_VIPStar")).toBe(0)
			expect(customEvents(ctx.h, "Pass_DoubleGlow")).toBe(0)
		end)

		it(
			"achat en jeu réel : un seul « Merci ! » et un seul Pass_*, même si le signal se répète",
			function()
				local ctx = boot()
				local p = join(ctx, 1)
				ctx.h:grantPass(p, PASS_IDS.VIPStar)
				for _ = 1, 3 do
					ctx.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(
						p,
						PASS_IDS.VIPStar,
						true
					)
				end
				ctx.h:settle(3)
				expect(ctx.Mon.ownsPass(p, "VIPStar")).toBe(true)
				local thanks = celebrations(ctx.h, p, "purchase")
				expect(#thanks).toBe(1)
				expect(thanks[1].data).toEqual({ pass = "VIPStar" })
				expect(customEvents(ctx.h, "Pass_VIPStar")).toBe(1)
			end
		)

		it("pass possédé à l'arrivée : ni « Merci ! » ni Pass_*", function()
			local ctx = boot()
			ctx.h.ownedPasses[1] = { [PASS_IDS.NightShift] = true }
			local p = join(ctx, 1)
			ctx.h:settle(3)
			expect(ctx.Mon.ownsPass(p, "NightShift")).toBe(true)
			expect(#celebrations(ctx.h, p, "purchase")).toBe(0)
			expect(customEvents(ctx.h, "Pass_NightShift")).toBe(0)
		end)
	end)

	describe("Fix restes economy › attribution d'un produit atomique vis-à-vis du reçu", function()
		it(
			"un effet en échec : reçu enregistré, autres effets accordés, redélivrance sans effet",
			function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				local original = ctx.A.addNebbies
				ctx.A.addNebbies = function()
					error("AtlasService en panne (simulée)")
				end
				local Decision = ctx.Enum.ProductPurchaseDecision
				expect(ctx.h:purchaseProduct(p, PRODUCT_IDS.StarterKit, "kit1")).toBe(
					Decision.PurchaseGranted
				)
				expect(table.find(data.receipts, "kit1") ~= nil).toBe(true)
				-- les effets qui ont réussi sont là ; celui en échec est signalé
				expect(data.starterKit).toBe(true)
				expect(data.unlocks.styles.comet_tail).toBe(true)
				expect(data.boosts.personalUntil).toBe(T0 + 1200)
				expect(count(data.nebbies)).toBe(0)
				expect(hasMatch(ctx.h:warnings(), "[ProductService]")).toBe(true)
				ctx.h:settle(1)
				expect(customEvents(ctx.h, "ProductEffectFailed_StarterKit")).toBe(1)
				-- Roblox redélivre le même reçu (acquittement perdu) : rien n'est accordé deux fois
				ctx.A.addNebbies = original
				expect(ctx.h:purchaseProduct(p, PRODUCT_IDS.StarterKit, "kit1")).toBe(
					Decision.PurchaseGranted
				)
				expect(data.boosts.personalUntil).toBe(T0 + 1200)
				expect(count(data.nebbies)).toBe(0)
				local n = 0
				for _, id in data.receipts do
					if id == "kit1" then
						n += 1
					end
				end
				expect(n).toBe(1)
			end
		)

		it("avant toute mutation (Glow Party non mise en file) : reçu NON enregistré", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local Ev = ctx.h:require("ServerScriptService.Server.Services.EventService")
			Ev.queueGlowParty = function()
				error("EventService indisponible")
			end
			local Decision = ctx.Enum.ProductPurchaseDecision
			expect(ctx.h:purchaseProduct(p, PRODUCT_IDS.GlowParty, "party1")).toBe(Decision.NotProcessedYet)
			expect(table.find(data.receipts, "party1")).toBeNil()
			expect(#celebrations(ctx.h, p, "purchase")).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	describe("Fix restes economy › attribut GuardLinks", function()
		it("au chargement, à l'achat (fonction et remote) et après une Supernova", function()
			local ctx = boot()
			expect(ctx.F.guardLinks(2) ~= ctx.F.guardLinks(0)).toBe(true)
			seed(ctx, 1, { upgrades = { conga = 0, stride = 0, lure = 0, perches = 0, guard = 2 } })
			local veteran = join(ctx, 1)
			expect(veteran:GetAttribute("GuardLinks")).toBe(ctx.F.guardLinks(2))
			local p, data = join(ctx, 2)
			expect(p:GetAttribute("GuardLinks")).toBe(ctx.F.guardLinks(0))
			data.glow = 10 ^ 9
			expect(ctx.E.buyUpgrade(p, "guard")).toBe(true)
			expect(p:GetAttribute("GuardLinks")).toBe(ctx.F.guardLinks(1))
			ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "guard")
			expect(data.upgrades.guard).toBe(2)
			expect(p:GetAttribute("GuardLinks")).toBe(ctx.F.guardLinks(2))
			-- une autre piste ne change rien ; la Supernova garde les Guard Links
			ctx.E.buyUpgrade(p, "conga")
			expect(p:GetAttribute("GuardLinks")).toBe(ctx.F.guardLinks(2))
			expect(ctx.E.trySupernova(p)).toBe(true)
			expect(data.upgrades.guard).toBe(2)
			expect(p:GetAttribute("GuardLinks")).toBe(ctx.F.guardLinks(2))
		end)
	end)

	describe("Fix restes economy › hors ligne et passes vérifiés après le calcul", function()
		it("passes achetés sur le site pendant l'absence : complément crédité une fois", function()
			local ctx = boot({ yieldOwnership = 0.05 })
			seed(ctx, 1, {
				nebbies = { u1 = RARE },
				nextUid = 2,
				perchIncome = 15,
				lastOnline = T0 - 3600,
				lastSettle = T0 - 3600,
			})
			ctx.h.ownedPasses[1] = { [PASS_IDS.NightShift] = true, [PASS_IDS.DoubleGlow] = true }
			local p, data = join(ctx, 1)
			-- calcul du chargement : passes pas encore vérifiés (50 % × 1 h × 15)
			expect(data.glow).toBe(27000)
			task.wait(0.6)
			ctx.h:settle(3)
			-- 15 × 2 (Double Glow) × 3 600 × 0,75 (Night Shift)
			expect(data.glow).toBe(81000)
			local offline = economyEvents(ctx.h, "Offline")
			expect(#offline).toBe(2)
			expect(offline[2][4]).toBe(54000)
			expect(offline[2][6]).toBe("TimedReward")
			local cel = celebrations(ctx.h, p, "offline")
			expect(#cel).toBe(2)
			expect(cel[2].data.glow).toBe(81000)
			expect(cel[2].data.nightShift).toBe(true)
			expect(cel[2].data.seconds).toBe(3600)
			expect(cel[2].data.away).toBe(3600)
			-- un autre PassGranted (achat en jeu ensuite) ne recrédite rien
			ctx.h:grantPass(p, PASS_IDS.VIPStar)
			task.wait(0.2)
			ctx.h:settle(2)
			expect(data.glow).toBe(81000)
			expect(#economyEvents(ctx.h, "Offline")).toBe(2)
		end)

		it("pass acheté EN JEU juste après l'arrivée : jamais rétroactif", function()
			local ctx = boot({ yieldOwnership = 0.05 })
			seed(ctx, 1, {
				nebbies = { u1 = RARE },
				nextUid = 2,
				perchIncome = 15,
				lastOnline = T0 - 3600,
				lastSettle = T0 - 3600,
			})
			local p, data = join(ctx, 1)
			expect(data.glow).toBe(27000)
			task.wait(0.6)
			ctx.h:settle(2)
			ctx.h:grantPass(p, PASS_IDS.NightShift)
			task.wait(0.3)
			ctx.h:settle(3)
			expect(ctx.Mon.ownsPass(p, "NightShift")).toBe(true)
			expect(data.glow).toBe(27000)
			expect(#economyEvents(ctx.h, "Offline")).toBe(1)
			expect(#celebrations(ctx.h, p, "offline")).toBe(1)
		end)

		it("vérification d'arrivée trop tardive (> 30 s) : aucun complément", function()
			local ctx = boot({
				yieldOwnership = 0.02,
				onOwnership = function(Clock)
					Clock.advance(10) -- 6 vérifications : 60 s
				end,
			})
			seed(ctx, 1, {
				nebbies = { u1 = RARE },
				nextUid = 2,
				perchIncome = 15,
				lastOnline = T0 - 3600,
				lastSettle = T0 - 3600,
			})
			ctx.h.ownedPasses[1] = { [PASS_IDS.NightShift] = true }
			local p = join(ctx, 1)
			task.wait(0.4)
			ctx.h:settle(3)
			expect(ctx.Mon.ownsPass(p, "NightShift")).toBe(true)
			expect(#economyEvents(ctx.h, "Offline")).toBe(1)
			expect(#celebrations(ctx.h, p, "offline")).toBe(1)
		end)
	end)

	describe("Fix restes economy › invariants de développement (GDD §12.6)", function()
		it("hors Studio : aucun contrôle, aucun avertissement", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			expect(ctx.Inv.enabled()).toBe(false)
			data.stardust = -5
			expect(ctx.Inv.check(p, data, "test")).toEqual({})
			expect(ctx.DS.saveNow(p)).toBe(true)
			expect(invariantWarnings(ctx.h)).toEqual({})
		end)

		it("Studio : partie normale (achats, perchoirs, Supernova, départ) sans violation", function()
			local ctx = boot({ isStudio = true })
			local p, data = join(ctx, 1)
			expect(ctx.Inv.enabled()).toBe(true)
			local codes = {}
			for _ = 1, 8 do
				table.insert(codes, 16 * 1) -- Cometcub ★1 (code = espèce, forme 0, variantes 0)
			end
			ctx.A.addNebbies(p, codes, "parade")
			data.glow = 10 ^ 9
			for _, track in { "perches", "perches", "guard", "conga", "stride", "lure" } do
				expect(ctx.E.buyUpgrade(p, track)).toBe(true)
			end
			ctx.Clock.advance(100)
			expect(ctx.E.trySupernova(p)).toBe(true)
			expect(ctx.Inv.check(p, data, "test")).toEqual({})
			expect(ctx.DS.saveNow(p)).toBe(true)
			ctx.h:removePlayer(p)
			ctx.h:settle(5)
			expect(invariantWarnings(ctx.h)).toEqual({})
			expect(#ctx.h.errors).toBe(0)
		end)

		it("Studio : chaque invariant violé est signalé (sans erreur ni réparation)", function()
			local ctx = boot({ isStudio = true })
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, { 16 }, "parade")
			expect(data.perchIncome).toBe(15)
			local function violations(mutate)
				local saved = {}
				for k, v in data do
					saved[k] = if type(v) == "table" then table.clone(v) else v
				end
				mutate()
				local out = ctx.Inv.check(p, data, "test")
				for k, v in saved do
					data[k] = v
				end
				return out
			end
			expect(hasMatch(
				violations(function()
					data.glow = 0 / 0
				end),
				"glow"
			)).toBe(true)
			expect(hasMatch(
				violations(function()
					data.stardust = -1
				end),
				"stardust"
			)).toBe(true)
			expect(hasMatch(
				violations(function()
					data.glow = 12.5
				end),
				"glow"
			)).toBe(true)
			expect(hasMatch(
				violations(function()
					data.glowCarry = 1
				end),
				"glowCarry"
			)).toBe(true)
			expect(hasMatch(
				violations(function()
					data.upgrades.conga = 999
				end),
				"upgrades.conga"
			)).toBe(true)
			expect(hasMatch(
				violations(function()
					data.nebbies.u99 = { s = 999, f = 0, v = 0, st = 1 }
				end),
				"u99"
			)).toBe(true)
			-- le perché n'existe plus (libéré sans recalcul) : revenu perché incohérent
			expect(hasMatch(
				violations(function()
					data.nebbies = {}
				end),
				"perchIncome"
			)).toBe(true)
			expect(hasMatch(
				violations(function()
					data.perchIncome = 1234
				end),
				"perchIncome"
			)).toBe(true)
			-- profil malformé : signalé, jamais d'erreur
			expect(#violations(function()
				data.upgrades = "oops"
				data.nebbies = 7
			end) >= 2).toBe(true)
			-- l'état réel est intact et sain
			expect(ctx.Inv.check(p, data, "test")).toEqual({})
			-- crochet de sauvegarde : la violation est signalée bruyamment
			data.stardust = -3
			ctx.DS.saveNow(p)
			local warned = invariantWarnings(ctx.h)
			expect(#warned >= 1).toBe(true)
			expect(hasMatch(warned, "sauvegarde")).toBe(true)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	describe("Fix restes economy › invariants sur un serveur complet (Studio)", function()
		it("chasse, parades, améliorations par remote, Supernova, départs : aucune violation", function()
			local TW = T0 + 37 + 3600 * 5 -- hors fenêtre de Comète et de Balise
			local w = Bots.boot(Harness, {
				t0 = TW,
				before = function(w)
					w.h.isStudio = true
					for i = 1, 3 do
						Bots.saveProfile(
							w,
							40 + i,
							Bots.veteranProfile(w, TW, if i == 3 then 450000 else 2000)
						)
					end
				end,
			})
			Bots.use(w)
			local Inv = w.h:require("ServerScriptService.Server.Economy.Invariants")
			expect(Inv.enabled()).toBe(true)
			for i = 1, 3 do
				local p = w.h:addPlayer({ userId = 40 + i, name = "V" .. i })
				table.insert(w.players, p)
			end
			w.h:settle(10)
			Bots.frames(5)
			for i, p in w.players do
				Bots.hunt(p, 4, 120, (i - 2) * 0.4)
			end
			Bots.frames(300, Bots.brains)
			for _, p in w.players do
				w.DS.get(p).glow += 5000
				Bots.fire("BuyUpgrade", p, "perches")
				Bots.fire("BuyUpgrade", p, "guard")
				expect(p:GetAttribute("GuardLinks")).toBe(w.F.guardLinks(w.DS.get(p).upgrades.guard))
			end
			Bots.frames(100, Bots.brains)
			local hero = w.players[3]
			w.brains[hero].paused = true
			Bots.walkAll({ [hero] = Bots.harborPoint(hero) }, 500, Bots.brains)
			task.wait(2.05) -- débit réel du remote Supernova
			Bots.fire("Supernova", hero)
			expect(w.DS.get(hero).supernovas).toBe(1)
			local parades = 0
			for _, p in w.players do
				parades += w.brains[p].parades
				local violations = Inv.check(p, w.DS.get(p), "test")
				expect(violations).toEqual({})
				expect(w.DS.saveNow(p)).toBe(true)
			end
			expect(parades >= 1).toBe(true)
			for _, p in w.players do
				w.h:removePlayer(p)
			end
			w.h:settle(10)
			expect(invariantWarnings(w.h)).toEqual({})
			expect(#w.h.errors).toBe(0)
		end)
	end)

	describe("Fix restes economy › « chez soi » : toute sa plateforme de Nid", function()
		it(
			"WorldLayout : arrière de la plateforme oui, au-delà non ; zone anti-coupe inchangée",
			function()
				local ctx = boot()
				local WL, Zones, Balance = ctx.WL, ctx.Zones, ctx.Balance
				local half = Zones.Nests.PlatformDiameter / 2
				for slot = 1, Zones.Nests.Count do
					local c = WL.nestCenter(slot)
					local out = c.Unit -- de la porte vers le fond de la plateforme (vers l'extérieur)
					local rear = c + out * half
					local gate = WL.gateCFrame(slot).Position
					local dx, dz = rear.X - gate.X, rear.Z - gate.Z
					expect(math.sqrt(dx * dx + dz * dz) > Balance.Snip.HarborRadius).toBe(true)
					expect(WL.inOwnHarbor(slot, rear)).toBe(true)
					expect(WL.inOwnHarbor(slot, c + out * (half + 0.9))).toBe(true)
					expect(WL.inOwnHarbor(slot, c + out * (half + 1.5))).toBe(false)
					expect(WL.inOwnHarbor(slot % Zones.Nests.Count + 1, rear)).toBe(false)
					-- la zone protégée des coupes (toutes les portes) ne s'étend pas
					expect(WL.inHarbor(rear)).toBe(false)
				end
				expect(WL.inOwnHarbor(1, ctx.V3.new(0 / 0, 0, 0 / 0))).toBe(false)
			end
		)

		it("Supernova et Zen acceptés depuis l'arrière de sa plateforme", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local slot = ctx.N.slotOf(p)
			expect(slot > 0).toBe(true)
			local c = ctx.WL.nestCenter(slot)
			local rear = c + c.Unit * (ctx.Zones.Nests.PlatformDiameter / 2 - 0.5)
			ctx.h:moveTo(p, ctx.V3.new(rear.X, 3, rear.Z))
			expect(ctx.N.inOwnHarbor(p)).toBe(true)
			expect(ctx.E.supernovaPreview(p).inHarbor).toBe(true)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", p, "zen", true)
			expect(ctx.N.isZen(p)).toBe(true)
			data.glow = ctx.F.supernovaCost(0)
			expect(ctx.E.trySupernova(p)).toBe(true)
			expect(data.supernovas).toBe(1)
		end)
	end)
end
