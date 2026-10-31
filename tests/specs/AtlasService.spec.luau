--!nocheck
-- AtlasService : collection (uids), tri des perchoirs, Atlas, badges, jalons, espèces complètes,
-- réserve pleine, Starforge (fuse / fuseAll), libération, verrous, remotes malveillants, cycle de vie.

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000

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
			A = h:require("ServerScriptService.Server.Services.AtlasService"),
			E = h:require("ServerScriptService.Server.Services.EconomyService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			WS = h:require("ServerScriptService.Server.Services.WorldService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			Collection = h:require("ServerScriptService.Server.Economy.Collection"),
		}
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, data
	end

	local function codes(ctx, s, n, f, v)
		local out = {}
		for i = 1, n do
			out[i] = ctx.Nebbies.pack(s, f or 0, v or 0)
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

	local function feedbacks(h, p, key)
		local out = {}
		for _, args in h:sentTo(p, "Feedback") do
			if key == nil or args[1].key == key then
				table.insert(out, args[1])
			end
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

	describe("AtlasService › collection et Atlas", function()
		it("crée des uids u<n>, valide les entrées d'Atlas et les badges à l'encaissement", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local entries = {}
			ctx.Signals.AtlasEntry:Connect(function(pl, s, f, total)
				table.insert(entries, { s = s, f = f, total = total })
			end)
			local N = ctx.Nebbies
			local uids = ctx.A.addNebbies(p, {
				N.pack(1, 0, 0),
				N.pack(1, 0, 0),
				N.pack(9, 2, 1), -- Bluebell Frozen Golden
				N.pack(16, 0, 6), -- Cometcub Huge Starborn
				4096, -- code invalide : ignoré
				0 / 0,
			}, "parade")
			expect(uids).toEqual({ "u1", "u2", "u3", "u4" })
			expect(data.nextUid).toBe(5)
			expect(data.nebbies.u3).toEqual({ s = 9, f = 2, v = 1, st = 1 })
			expect(ctx.A.atlasCount(p)).toBe(3)
			expect(ctx.A.hasEntry(p, 9, 2)).toBe(true)
			expect(ctx.A.hasEntry(p, 9, 0)).toBe(false)
			expect(ctx.A.hasEntry(p, 0 / 0, 0)).toBe(false)
			expect(N.testBit(data.badges, N.badgeIndex("golden", 9))).toBe(true)
			expect(N.testBit(data.badges, N.badgeIndex("huge", 16))).toBe(true)
			expect(N.testBit(data.badges, N.badgeIndex("starborn", 16))).toBe(true)
			expect(N.testBit(data.badges, N.badgeIndex("golden", 16))).toBe(false)
			ctx.h:settle(1)
			expect(#entries).toBe(3)
			expect(entries[3].total).toBe(3)
			local cel = celebrations(ctx.h, p, "atlasNew")
			expect(#cel).toBe(1)
			expect(cel[1].data.entries[1]).toEqual({ s = 1, f = 0 })
			-- une entrée déjà connue ne recélèbre pas
			ctx.A.addNebbies(p, codes(ctx, 1, 1), "parade")
			expect(#celebrations(ctx.h, p, "atlasNew")).toBe(1)
			expect(ctx.A.record(p, "u1")).toEqual({ s = 1, f = 0, v = 0, st = 1 })
			expect(ctx.A.record(p, "u99")).toBeNil()
		end)

		it("ajoute des Nebbies avec étoiles (récompenses) bornées à ★1-★5", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 2, 1), "quest", 3)
			ctx.A.addNebbies(p, codes(ctx, 2, 1), "quest", 99)
			ctx.A.addNebbies(p, codes(ctx, 2, 1), "quest", 0 / 0)
			expect(data.nebbies.u1.st).toBe(3)
			expect(data.nebbies.u2.st).toBe(5)
			expect(data.nebbies.u3.st).toBe(1)
		end)

		it(
			"jalons d'Atlas : perchoirs, titre + style à 132 (NestService.unlock), bannière personnelle",
			function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				local N = ctx.Nebbies
				local list = {}
				for s = 1, N.SPECIES_COUNT do
					if N.isSpeciesEnabled(s) then
						for _, f in N.enabledForms() do
							if #list < 132 then
								table.insert(list, N.pack(s, f, 0))
							end
						end
					end
				end
				ctx.A.addNebbies(p, list, "code")
				expect(ctx.A.atlasCount(p)).toBe(132)
				expect(data.atlasRewards).toBe(132)
				expect(ctx.A.perchCount(p)).toBe(13)
				expect(data.unlocks.titles.cartographer).toBe(true)
				expect(data.unlocks.styles.constellation).toBe(true)
				expect(data.unlocks.themes.atlas).toBeNil()
				local milestones = celebrations(ctx.h, p, "atlasMilestone")
				expect(#milestones).toBe(11)
				expect(milestones[11].data.title).toBe("cartographer")
				local banners = ctx.h:sentTo(p, "Banner")
				expect(#banners).toBe(11)
				expect(banners[1][1].kind).toBe("atlasMilestone")
				expect(banners[1][1].personal).toBe(true)
				-- 26 espèces complètes (5 formes) : +100 Stardust chacune
				expect(#celebrations(ctx.h, p, "speciesComplete")).toBe(26)
				expect(data.stardust).toBe(2600)
				expect(ctx.N.hasUnlock(p, "titles", "cartographer")).toBe(true)
			end
		)

		it("espèce complète : +100 Stardust une seule fois", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			for _, f in ctx.Nebbies.enabledForms() do
				ctx.A.addNebbies(p, codes(ctx, 1, 1, f), "parade")
			end
			ctx.A.addNebbies(p, codes(ctx, 1, 1, 5), "parade")
			local done = celebrations(ctx.h, p, "speciesComplete")
			expect(#done).toBe(1)
			expect(done[1].data).toEqual({ s = 1, dust = 100 })
			expect(data.stardust).toBe(100)
		end)
	end)

	describe("AtlasService › perchoirs", function()
		it("perche les meilleurs revenus, règle le Glow et met à jour le taux et le Nid", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local N = ctx.Nebbies
			local changed = {}
			ctx.Signals.PerchesChanged:Connect(function(pl, n)
				table.insert(changed, n)
			end)
			ctx.A.addNebbies(
				p,
				{ N.pack(1, 0, 0), N.pack(16, 0, 0), N.pack(9, 0, 0), N.pack(23, 0, 0) },
				"parade"
			)
			expect(ctx.A.perched(p)).toEqual({ "u4", "u2", "u3" })
			expect(data.perchIncome).toBe(60 + 15 + 4)
			expect(data.idleRate).toBe(79)
			local nest = ctx.WS.nest(1)
			expect(nest:GetAttribute("PerchCount")).toBe(3)
			expect(nest:GetAttribute("PerchData")).toBe(
				string.format("%d.1,%d.1,%d.1", N.pack(23, 0, 0), N.pack(16, 0, 0), N.pack(9, 0, 0))
			)
			-- le revenu accumulé avant un changement de perchés est réglé à l'ancien taux
			ctx.Clock.advance(10)
			ctx.A.addNebbies(p, { N.pack(24, 0, 0) }, "parade")
			expect(data.glow).toBe(790)
			expect(data.perchIncome).toBe(60 + 60 + 15)
			-- amélioration Perchoirs → un perchoir de plus
			data.glow = 1000
			ctx.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "perches")
			ctx.h:settle(2)
			expect(ctx.A.perchCount(p)).toBe(4)
			expect(data.perchIncome).toBe(60 + 60 + 15 + 4)
			expect(nest:GetAttribute("PerchCount")).toBe(4)
			expect(changed).toEqual({ 4 }) -- (3 a été signalé au chargement)
		end)

		it("égalité de revenu : rareté décroissante puis uid le plus ancien", function()
			local ctx = boot()
			local p = join(ctx, 1)
			local N = ctx.Nebbies
			-- Commun Golden (1 × 4) = Peu commun (4)
			ctx.A.addNebbies(
				p,
				{ N.pack(1, 0, 1), N.pack(9, 0, 0), N.pack(2, 0, 1), N.pack(1, 0, 0) },
				"parade"
			)
			expect(ctx.A.perched(p)).toEqual({ "u2", "u1", "u3" })
			local ranked = ctx.Collection.rank({
				u10 = { s = 1, f = 0, v = 1, st = 1 },
				u9 = { s = 2, f = 0, v = 1, st = 1 },
				bad = { s = 0, f = 0, v = 0, st = 1 },
			})
			expect(ranked.uids).toEqual({ "u9", "u10" })
		end)

		it("pass Extra Perches à l'achat : +6 perchoirs ; Stash Plus : réserve 600", function()
			local ctx = boot(function(h)
				local M = h:require("ReplicatedStorage.Shared.Config.Monetization")
				M.Passes.ExtraPerches.id = 4001
				M.Passes.StashPlus.id = 4002
			end)
			local p = join(ctx, 1)
			expect(ctx.A.perchCount(p)).toBe(3)
			expect(ctx.A.stashCap(p)).toBe(300)
			ctx.h:grantPass(p, 4001)
			ctx.h:grantPass(p, 4002)
			ctx.h:settle(2)
			expect(ctx.A.perchCount(p)).toBe(9)
			expect(ctx.A.stashCap(p)).toBe(600)
			expect(ctx.WS.nest(1):GetAttribute("PerchCount")).toBe(9)
		end)
	end)

	describe("AtlasService › réserve pleine", function()
		it("libère d'abord les C/U/R non verrouillés les moins rentables de la réserve", function()
			local ctx = boot(function(h)
				h:require("ReplicatedStorage.Shared.Config.Balance").Stash.Base = 4
			end)
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 1, 7), "parade") -- 3 perchés + 4 en réserve : plein
			expect(count(data.nebbies)).toBe(7)
			local uids = ctx.A.addNebbies(p, codes(ctx, 16, 1), "parade") -- un Rare arrive
			expect(uids).toEqual({ "u8" })
			expect(count(data.nebbies)).toBe(7)
			expect(data.nebbies.u7).toBeNil() -- le Commun le plus récent part
			expect(data.stardust).toBe(1)
			local fb = feedbacks(ctx.h, p, "feedback.autoRelease")
			expect(fb[1].vars).toEqual({ count = 1, dust = 1 })
		end)

		it("sinon libère les nouveaux arrivants excédentaires ; jamais un verrouillé", function()
			local ctx = boot(function(h)
				h:require("ReplicatedStorage.Shared.Config.Balance").Stash.Base = 4
			end)
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 29, 3), "parade") -- 3 Légendaires perchés
			ctx.A.addNebbies(p, codes(ctx, 1, 4), "parade") -- réserve pleine
			for uid in data.nebbies do
				ctx.A.setLock(p, uid, true)
			end
			local uids = ctx.A.addNebbies(p, codes(ctx, 23, 1), "comet") -- un Épique arrive
			expect(uids).toEqual({})
			expect(data.nebbies.u8).toBeNil()
			expect(count(data.nebbies)).toBe(7)
			expect(data.stardust).toBe(60)
			-- un Cosmique n'est jamais libéré, même en excès
			local cosmic = ctx.A.addNebbies(p, codes(ctx, 36, 1), "comet")
			expect(#cosmic).toBe(1)
			expect(count(data.nebbies)).toBe(8)
		end)
	end)

	describe("AtlasService › Starforge", function()
		it("fusionne 3 identiques en ★2 contre 25 Stardust ; signal et célébration", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local fused = {}
			ctx.Signals.Fused:Connect(function(pl, stars)
				table.insert(fused, stars)
			end)
			ctx.A.addNebbies(p, codes(ctx, 23, 3), "parade")
			data.stardust = 30
			ctx.h:fireServer("ReplicatedStorage.Remotes.Fuse", p, "u1")
			expect(data.nebbies.u1.st).toBe(2)
			expect(count(data.nebbies)).toBe(1)
			expect(data.stardust).toBe(5)
			expect(data.perchIncome).toBe(60 * 3.5)
			ctx.h:settle(1)
			expect(fused).toEqual({ 2 })
			local cel = celebrations(ctx.h, p, "starforge")
			expect(cel[1].data).toEqual({ uid = "u1", s = 23, f = 0, v = 0, stars = 2 })
		end)

		it("refus : copies manquantes, verrouillées, Stardust insuffisante, ★5", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 2, 3), "parade")
			data.stardust = 10
			local ok, reason = ctx.A.fuse(p, "u1")
			expect(ok).toBe(false)
			expect(reason).toBe("feedback.notEnoughStardust")
			ctx.h:fireServer("ReplicatedStorage.Remotes.Fuse", p, "u1")
			expect(feedbacks(ctx.h, p, "feedback.notEnoughStardust")[1].vars.missing).toBe(15)
			data.stardust = 1000
			ctx.A.setLock(p, "u2", true)
			ok, reason = ctx.A.fuse(p, "u1")
			expect(reason).toBe("feedback.fuseNeedCopies")
			-- le verrouillé choisi reçoit l'étoile et garde son cadenas
			ok = ctx.A.fuse(p, "u2")
			expect(ok).toBe(true)
			expect(data.nebbies.u2).toEqual({ s = 2, f = 0, v = 0, st = 2, lk = true })
			ctx.A.addNebbies(p, codes(ctx, 3, 1), "quest", 5)
			ok, reason = ctx.A.fuse(p, "u4")
			expect(reason).toBe("feedback.fuseMaxStars")
			expect(ctx.A.fuse(p, "nope")).toBe(false)
		end)

		it("Tout fusionner : la fusion qui augmente le plus le revenu perché d'abord", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 1, 3), "parade")
			ctx.A.addNebbies(p, codes(ctx, 23, 3), "parade")
			data.stardust = 25
			expect(ctx.A.fuseAll(p)).toBe(1)
			-- l'Épique ★2 (210) remplace 3 Épiques perchés ; les Communs attendent
			expect(data.nebbies.u4.st).toBe(2)
			expect(data.nebbies.u1.st).toBe(1)
			expect(data.stardust).toBe(0)
			ctx.h:fireServer("ReplicatedStorage.Remotes.FuseAll", p)
			expect(feedbacks(ctx.h, p, "feedback.notEnoughStardust")[1].vars.missing).toBe(25)
		end)

		it("Tout fusionner en cascade : 9 Communs → 1 ★3 ; rien à fusionner → Feedback", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local fused = {}
			ctx.Signals.Fused:Connect(function(pl, stars)
				table.insert(fused, stars)
			end)
			ctx.A.addNebbies(p, codes(ctx, 1, 9), "parade")
			data.stardust = 3 * 25 + 120
			ctx.h:fireServer("ReplicatedStorage.Remotes.FuseAll", p)
			expect(count(data.nebbies)).toBe(1)
			local _, rec = next(data.nebbies)
			expect(rec.st).toBe(3)
			expect(data.stardust).toBe(0)
			ctx.h:settle(1)
			table.sort(fused)
			expect(fused).toEqual({ 2, 2, 2, 3 })
			local cel = celebrations(ctx.h, p, "starforge")
			expect(#cel).toBe(1)
			expect(cel[1].data.count).toBe(4)
			expect(cel[1].data.stars).toBe(3)
			local n, reason = ctx.A.fuseAllDetailed(p)
			expect(n).toBe(0)
			expect(reason).toBe("feedback.fuseNeedCopies")
		end)

		it("Tout fusionner ne consomme jamais un verrouillé", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 4, 4), "parade")
			ctx.A.setLock(p, "u1", true)
			ctx.A.setLock(p, "u2", true)
			data.stardust = 1000
			expect(ctx.A.fuseAll(p)).toBe(1)
			expect(data.nebbies.u1 ~= nil and data.nebbies.u2 ~= nil).toBe(true)
			expect(data.nebbies.u1.st + data.nebbies.u2.st).toBe(3)
		end)

		it("topSumAfter évalue une fusion sans retrier", function()
			local ctx = boot()
			local C = ctx.Collection
			local values = { 60, 60, 60, 15, 4, 1, 1, 1 }
			expect(C.topSumAfter(values, 3, 60, 3, 210)).toBe(210 + 15 + 4)
			expect(C.topSumAfter(values, 3, 1, 3, 3.5)).toBe(180)
			expect(C.topSumAfter({}, 3, 1, 3, 3.5)).toBe(3.5)
			C.applyFusion(values, 1, 3, 3.5)
			expect(values).toEqual({ 60, 60, 60, 15, 4, 3.5 })
		end)
	end)

	describe("AtlasService › libération et verrous", function()
		it("libère tout ou rien et crédite la Stardust par rareté", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 16, 1), "parade")
			ctx.A.addNebbies(p, codes(ctx, 1, 1), "quest", 2)
			ctx.A.addNebbies(p, codes(ctx, 36, 1), "comet")
			ctx.A.addNebbies(p, codes(ctx, 9, 1), "parade")
			ctx.A.setLock(p, "u4", true)
			-- un verrouillé : rien n'est libéré
			ctx.h:fireServer("ReplicatedStorage.Remotes.Release", p, { "u1", "u4" })
			expect(count(data.nebbies)).toBe(4)
			expect(feedbacks(ctx.h, p, "feedback.nebbyLocked")[1] ~= nil).toBe(true)
			-- un Cosmique : rien n'est libéré
			ctx.h:fireServer("ReplicatedStorage.Remotes.Release", p, { "u1", "u3" })
			expect(count(data.nebbies)).toBe(4)
			expect(feedbacks(ctx.h, p, "feedback.cannotRelease")[1] ~= nil).toBe(true)
			-- Rare ★1 (15) + Commun ★2 (3) (API directe : le remote est limité à 2 / s)
			expect(ctx.A.release(p, { "u1", "u2" })).toBe(18)
			expect(count(data.nebbies)).toBe(2)
			expect(data.stardust).toBe(18)
			expect(feedbacks(ctx.h, p, "feedback.released")[1].vars).toEqual({ count = 2, dust = 18 })
			expect(celebrations(ctx.h, p, "release")[1].data).toEqual({ count = 2, dust = 18 })
			local skus = {}
			for _, e in ctx.h.log.analytics do
				if e.method == "LogEconomyEvent" then
					skus[e.args[7]] = e.args[4]
				end
			end
			expect(skus.Release_rare).toBe(15)
			expect(skus.Release_common).toBe(3)
			-- déverrouillé puis libéré
			expect(ctx.A.setLock(p, "u4", false)).toBe(true)
			expect(data.nebbies.u4.lk).toBeNil()
			expect(ctx.A.release(p, { "u4" })).toBe(4)
		end)

		it("charges malveillantes : aucune erreur, aucune mutation", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			local other, otherData = join(ctx, 2)
			ctx.A.addNebbies(p, codes(ctx, 16, 2), "parade")
			ctx.A.addNebbies(other, codes(ctx, 16, 3), "parade")
			local big = {}
			for i = 1, 51 do
				big[i] = "u1"
			end
			local huge = {}
			for i = 1, 100000 do
				huge["k" .. i] = true
			end
			local releases = {
				nil,
				"u1",
				0 / 0,
				{},
				{ "u1", "u1" },
				{ "u1", 5 },
				{ [1] = "u1", [3] = "u2" },
				{ "u1", x = "u2" },
				{ string.rep("u", 13) },
				big,
				huge,
				{ "u3" }, -- uid d'un autre joueur (u3 n'existe pas chez p)
			}
			for _, payload in releases do
				ctx.A.releaseDetailed(p, payload)
			end
			expect(count(data.nebbies)).toBe(2)
			expect(data.stardust).toBe(0)
			for _, payload in releases do
				ctx.h:fireServer("ReplicatedStorage.Remotes.Release", p, payload)
			end
			for _, bad in { nil, 0 / 0, {}, string.rep("u", 13), 1, "u3" } do
				ctx.h:fireServer("ReplicatedStorage.Remotes.Fuse", p, bad)
				ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, bad, true)
			end
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u1", "yes")
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u1", 0 / 0)
			expect(count(data.nebbies)).toBe(2)
			expect(data.nebbies.u1.lk).toBeNil()
			expect(data.stardust).toBe(0)
			expect(count(otherData.nebbies)).toBe(3)
			expect(otherData.nebbies.u3.lk).toBeNil()
			expect(#feedbacks(ctx.h, p)).toBe(0)
		end)

		it("validUidList : séquentielle, 1-50 chaînes courtes et uniques", function()
			local ctx = boot()
			local C = ctx.Collection
			expect(C.validUidList({ "u1", "u2" }, 50, 12)).toEqual({ "u1", "u2" })
			expect(C.validUidList({}, 50, 12)).toBeNil()
			expect(C.validUidList({ "u1", "" }, 50, 12)).toBeNil()
			expect(C.validUidList({ "u1", "u1" }, 50, 12)).toBeNil()
			expect(C.validUidList({ [2] = "u1" }, 50, 12)).toBeNil()
			expect(C.validUidList("u1", 50, 12)).toBeNil()
		end)
	end)

	describe("AtlasService › cycle de vie", function()
		it("au chargement : perchoirs recalculés et affichés, jalons dus réclamés", function()
			local ctx = boot()
			local profile = ctx.Schema.defaults()
			profile.nebbies = {
				u1 = { s = 1, f = 0, v = 0, st = 1 },
				u2 = { s = 23, f = 0, v = 0, st = 2 },
				u7 = { s = 16, f = 0, v = 0, st = 1, lk = true },
			}
			profile.nextUid = 3 -- incohérent : corrigé pour éviter une collision
			profile.perchIncome = 999
			local N = ctx.Nebbies
			for s = 1, 6 do
				for f = 0, 1 do
					N.setBit(profile.atlas, N.atlasIndex(s, f))
				end
			end
			local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
			store:SetAsync("player_1", { data = profile })
			local p, data = join(ctx, 1)
			expect(data.nextUid).toBe(8)
			expect(data.perchIncome).toBe(210 + 15 + 1)
			expect(data.atlasRewards).toBe(12)
			expect(ctx.A.perchCount(p)).toBe(4)
			expect(ctx.A.perched(p)).toEqual({ "u2", "u7", "u1" })
			expect(ctx.WS.nest(1):GetAttribute("PerchCount")).toBe(4)
			local uids = ctx.A.addNebbies(p, codes(ctx, 2, 1), "parade")
			expect(uids).toEqual({ "u8" })
		end)

		it("joueur absent ou parti : rien n'est créé, aucune erreur", function()
			local ctx = boot()
			local p = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 1, 2), "parade")
			ctx.h:removePlayer(p)
			ctx.h:settle(3)
			expect(ctx.A.addNebbies(p, codes(ctx, 1, 1), "parade")).toEqual({})
			expect(ctx.A.perched(p)).toEqual({})
			expect(ctx.A.atlasCount(p)).toBe(0)
			expect(ctx.A.release(p, { "u1" })).toBe(0)
			expect(ctx.A.setLock(p, "u1", true)).toBe(false)
			expect(ctx.A.fuseAll(p)).toBe(0)
			expect(ctx.WS.nest(1):GetAttribute("PerchCount")).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	-- Bugs trouvés en revue : chaque test reproduit le défaut corrigé
	describe("AtlasService › revue", function()
		local function starforgeSpends(h)
			local out = {}
			for _, e in h.log.analytics do
				if
					e.method == "LogEconomyEvent"
					and string.sub(tostring(e.args[7]), 1, 10) == "Starforge_"
				then
					table.insert(out, { sku = e.args[7], amount = e.args[4] })
				end
			end
			return out
		end

		it(
			"Tout fusionner sur 646 Nebbies : chaque Nebby est groupé une fois, une dépense par ★",
			function()
				-- défaut : chaque fusion regroupait de nouveau toute la collection (O(n²), ≈ 0,8 s de gel
				-- du serveur pour 646 Nebbies) et écrivait un événement analytique par fusion (≈ 300)
				local ctx = boot()
				local p, data = join(ctx, 1)
				for i = 1, 646 do
					data.nebbies["u" .. i] = { s = 1, f = 0, v = 0, st = 1 }
				end
				data.nextUid = 647
				data.stardust = 100000
				ctx.A.refreshPerches(p)
				local fusedSignals = 0
				ctx.Signals.Fused:Connect(function()
					fusedSignals += 1
				end)
				local groupKeyCalls = 0
				local realGroupKey = ctx.Collection.groupKey
				ctx.Collection.groupKey = function(rec)
					groupKeyCalls += 1
					return realGroupKey(rec)
				end
				local fused = ctx.A.fuseAll(p)
				ctx.Collection.groupKey = realGroupKey
				-- 646 ★1 → 215 ★2 (+1) → 71 ★3 (+2) → 23 ★4 (+2) → 7 ★5 (+2)
				expect(fused).toBe(215 + 71 + 23 + 7)
				expect(count(data.nebbies)).toBe(1 + 2 + 2 + 2 + 7)
				local cost = 215 * 25 + 71 * 120 + 23 * 600 + 7 * 3000
				expect(data.stardust).toBe(100000 - cost)
				expect(groupKeyCalls <= 646 + 4).toBe(true)
				local spends = starforgeSpends(ctx.h)
				expect(#spends).toBe(4)
				local total = 0
				for _, s in spends do
					total += s.amount
				end
				expect(total).toBe(cost)
				ctx.h:settle(2)
				expect(fusedSignals).toBe(fused)
				expect(celebrations(ctx.h, p, "starforge")[1].data.stars).toBe(5)
			end
		)

		it("Tout fusionner : Stardust limitée, la meilleure hausse du revenu perché d'abord", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			-- 3 Épiques perchés (60) et 6 Communs en réserve : l'Épique ★2 d'abord
			ctx.A.addNebbies(p, codes(ctx, 1, 6), "parade")
			ctx.A.addNebbies(p, codes(ctx, 23, 3), "parade")
			data.stardust = 25 + 25
			expect(ctx.A.fuseAll(p)).toBe(2)
			local stars = {}
			for _, rec in data.nebbies do
				stars[rec.s] = (stars[rec.s] or 0) + rec.st
			end
			expect(stars[23]).toBe(2) -- les 3 Épiques → 1 ★2
			expect(stars[1]).toBe(2 + 3) -- 1 fusion de Communs sur 2 possibles
			expect(data.stardust).toBe(0)
			expect(starforgeSpends(ctx.h)).toEqual({ { sku = "Starforge_2", amount = 50 } })
		end)

		it("fusionTopSum (préfixes, O(log n)) = topSumAfter sur 2 000 cas aléatoires", function()
			local ctx = boot()
			local C = ctx.Collection
			local rng = ctx.h.globals.Random.new(7)
			for _ = 1, 2000 do
				local n = rng:NextInteger(3, 40)
				local values = {}
				for i = 1, n do
					values[i] = ({ 1, 4, 15, 60, 300, 3.5, 14, 52.5 })[rng:NextInteger(1, 8)]
				end
				table.sort(values, function(a, b)
					return a > b
				end)
				-- une valeur présente au moins 3 fois
				local a = values[rng:NextInteger(1, n)]
				local copies = 0
				for _, v in values do
					if v == a then
						copies += 1
					end
				end
				if copies >= 3 then
					local perches = rng:NextInteger(0, 50)
					local b = a * 3.5
					local prefix = C.prefixSums(values, perches + 3)
					expect(C.fusionTopSum(values, prefix, perches, a, 3, b)).toBeNear(
						C.topSumAfter(values, perches, a, 3, b)
					)
				end
			end
		end)

		it("insertByAge : ordre numérique des uids (u9 avant u10), sans retrier", function()
			local ctx = boot()
			local C = ctx.Collection
			local list = { "u2", "u9", "u100" }
			C.insertByAge(list, "u10")
			C.insertByAge(list, "u1")
			C.insertByAge(list, "u1000")
			expect(list).toEqual({ "u1", "u2", "u9", "u10", "u100", "u1000" })
			expect(C.olderFirst("u9", "u10")).toBe(true)
			expect(C.olderFirst("u10", "u9")).toBe(false)
		end)

		it(
			"appel avant le traitement du chargement : profil réparé d'abord (aucune collision d'uid)",
			function()
				-- défaut : la réparation (nextUid incohérent, enregistrements invalides) n'avait lieu que dans le
				-- handler Loaded d'AtlasService ; un service servi avant lui (reçu Starter Kit, pass…) écrasait u1
				local results = {}
				local ctx = boot(function(h)
					local DS = h:require("ServerScriptService.Server.Services.DataService")
					local A = h:require("ServerScriptService.Server.Services.AtlasService")
					local Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies")
					DS.Loaded:Connect(function(pl)
						results.uids = A.addNebbies(pl, { Nebbies.pack(2, 0, 0) }, "product")
						results.fuseOk = pcall(A.fuseAll, pl)
						results.lockOk = pcall(A.setLock, pl, "u9", true)
						results.releaseOk = pcall(A.release, pl, { "u9" })
					end)
				end)
				local profile = ctx.Schema.defaults()
				profile.nebbies = {
					u1 = { s = 23, f = 0, v = 0, st = 2 },
					u9 = 7, -- enregistrement invalide
					u10 = { s = "x", f = 0, v = 0, st = 1 },
				}
				profile.nextUid = 1 -- incohérent
				local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
				store:SetAsync("player_1", { data = profile })
				local _, data = join(ctx, 1)
				expect(results.uids).toEqual({ "u2" }) -- nextUid réparé (u1 existe), invalides retirés
				expect(data.nebbies.u1).toEqual({ s = 23, f = 0, v = 0, st = 2 })
				expect(data.nebbies.u9).toBeNil()
				expect(data.nebbies.u10).toBeNil()
				expect(results.fuseOk).toBe(true)
				expect(results.lockOk).toBe(true)
				expect(results.releaseOk).toBe(true)
				expect(#ctx.h.errors).toBe(0)
			end
		)

		it("départ pendant la sauvegarde : aucun état par joueur recréé après PlayerRemoving", function()
			-- défaut : DataService garde le profil pendant la sauvegarde de départ ; un appel pendant ce
			-- yield (perchCount, perched…) recréait les caches par joueur, jamais vidés ensuite
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.A.addNebbies(p, codes(ctx, 23, 2), "parade")
			expect(ctx.A.debugTracked(p)).toBe(true)
			local realGet = ctx.DS.get
			ctx.DS.get = function(pl)
				if pl == p then
					return data
				end
				return realGet(pl)
			end
			ctx.h:removePlayer(p)
			ctx.h:settle(2)
			expect(ctx.A.debugTracked(p)).toBe(false)
			-- appels tardifs (profil encore tenu par la sauvegarde)
			expect(ctx.A.perchCount(p)).toBe(3)
			expect(ctx.A.atlasCount(p)).toBe(1)
			expect(#ctx.A.perched(p)).toBe(2)
			ctx.A.refreshPerches(p)
			ctx.A.addNebbies(p, codes(ctx, 1, 1), "parade")
			ctx.DS.get = realGet
			expect(ctx.A.debugTracked(p)).toBe(false)
			expect(ctx.N.debugTracked(p)).toBe(false)
			expect(ctx.WS.nest(1):GetAttribute("OwnerUserId")).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)
end
