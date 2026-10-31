--!nocheck
-- NestService : attribution des Nids (amis, plus petit libre, 13e joueur), attributs, placement,
-- PlayerReady, perchoirs affichés, constellation, réglages (Zen, langue, serveur privé),
-- cosmétiques (sources, temporaires), remotes malveillants et cycle de vie.

local task = require("@lune/task")

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
			N = h:require("ServerScriptService.Server.Services.NestService"),
			WS = h:require("ServerScriptService.Server.Services.WorldService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			V3 = h.globals.Vector3,
		}
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, data
	end

	local function feedbackKeys(h, p)
		local out = {}
		for _, args in h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	local function lastFeedback(h, p)
		local fb = h:sentTo(p, "Feedback")
		return fb[#fb] and fb[#fb][1]
	end

	local function farFromHome(ctx, p)
		ctx.h:moveTo(p, ctx.V3.new(0, 5, 0))
	end

	describe("NestService › attribution", function()
		it("plus petit Nid libre, attributs du Nid et du joueur, apparition et PlayerReady", function()
			local ctx = boot()
			local ready = {}
			ctx.Signals.PlayerReady:Connect(function(pl, slot)
				table.insert(ready, { id = pl.UserId, slot = slot })
			end)
			local moved = 0
			ctx.Signals.ServerMoved:Connect(function()
				moved += 1
			end)
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			expect(ctx.N.slotOf(a)).toBe(1)
			expect(ctx.N.slotOf(b)).toBe(2)
			expect(ctx.N.playerAt(2)).toBe(b)
			expect(ctx.N.playerAt(3)).toBeNil()
			local nest = ctx.WS.nest(2)
			expect(nest:GetAttribute("OwnerUserId")).toBe(2)
			expect(nest:GetAttribute("OwnerName")).toBe("P2")
			expect(nest:GetAttribute("Color")).toEqual(ctx.Cosmetics.NestColors[2])
			expect(nest:GetAttribute("Supernovas")).toBe(0)
			expect(nest:GetAttribute("LineStyle")).toBe("default")
			expect(nest:GetAttribute("NestTheme")).toBe("default")
			expect(nest:GetAttribute("Title")).toBe("")
			expect(b:GetAttribute("Slot")).toBe(2)
			expect(b:GetAttribute("Zen")).toBe(false)
			expect(b:GetAttribute("VIP")).toBe(false)
			expect(b.RespawnLocation).toBe(ctx.WS.spawnLocation(2))
			ctx.h:settle(1)
			expect(ready).toEqual({ { id = 1, slot = 1 }, { id = 2, slot = 2 } })
			-- personnage posé sur le Nid, tourné vers le centre
			local expected = (ctx.WorldLayout.nestCFrame(2) + ctx.V3.new(0, 3, 0)).Position
			local root = b.Character.HumanoidRootPart
			expect((root.Position - expected).Magnitude < 1e-3).toBe(true)
			expect(ctx.N.inOwnHarbor(b)).toBe(true)
			expect(moved >= 2).toBe(true)
		end)

		it("ami présent : Nid libre le plus proche du sien (anneau de 12)", function()
			local ctx = boot()
			local players = {}
			for i = 1, 5 do
				players[i] = join(ctx, i)
			end
			ctx.h:removePlayer(players[3])
			ctx.h:removePlayer(players[1])
			ctx.h:settle(2)
			-- ami du joueur 5 : le Nid 6 (voisin) plutôt que le plus petit libre (1)
			ctx.h:makeFriends(50, 5)
			local f5 = join(ctx, 50)
			expect(ctx.N.slotOf(f5)).toBe(6)
			-- ami du joueur 2 : Nids 1 et 3 à égale distance → le plus petit
			ctx.h:makeFriends(20, 2)
			local f2 = join(ctx, 20)
			expect(ctx.N.slotOf(f2)).toBe(1)
			-- sans ami : plus petit libre
			local x = join(ctx, 99)
			expect(ctx.N.slotOf(x)).toBe(3)
		end)

		it("13e joueur : slot 0 et Feedback, puis le premier Nid libéré lui revient", function()
			local ctx = boot()
			local players = {}
			for i = 1, 12 do
				players[i] = join(ctx, i)
			end
			local late = join(ctx, 13)
			expect(ctx.N.slotOf(late)).toBe(0)
			expect(late:GetAttribute("Slot")).toBe(0)
			expect(feedbackKeys(ctx.h, late)).toEqual({ "feedback.noNest" })
			expect(ctx.N.inOwnHarbor(late)).toBe(false)
			ctx.N.teleportHome(late) -- sans Nid : rien
			local ready = {}
			ctx.Signals.PlayerReady:Connect(function(pl, slot)
				table.insert(ready, slot)
			end)
			ctx.h:removePlayer(players[7])
			ctx.h:settle(3)
			expect(ctx.N.slotOf(late)).toBe(7)
			expect(ctx.WS.nest(7):GetAttribute("OwnerUserId")).toBe(13)
			expect(ready).toEqual({ 7 })
		end)

		it("départ : Nid gris, perchoirs détruits, slot réutilisé ; réapparition replacée", function()
			local ctx = boot()
			local a = join(ctx, 1)
			ctx.N.setPerchCount(a, 5)
			expect(ctx.WS.perchCount(1)).toBe(5)
			farFromHome(ctx, a)
			ctx.h:respawn(a)
			expect(ctx.N.inOwnHarbor(a)).toBe(true)
			ctx.h:removePlayer(a)
			ctx.h:settle(3)
			local nest = ctx.WS.nest(1)
			expect(nest:GetAttribute("OwnerUserId")).toBe(0)
			expect(nest:GetAttribute("OwnerName")).toBe("")
			expect(nest:GetAttribute("Color")).toEqual(ctx.Cosmetics.FreeNestColor)
			expect(nest:GetAttribute("PerchCount")).toBe(0)
			expect(nest:GetAttribute("PerchData")).toBe("")
			expect(ctx.WS.perchCount(1)).toBe(0)
			expect(ctx.N.slotOf(a)).toBe(0)
			expect(ctx.N.playerAt(1)).toBeNil()
			local b = join(ctx, 2)
			expect(ctx.N.slotOf(b)).toBe(1)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("joueurs déjà présents au démarrage et arrivée sans personnage", function()
			local ctx = boot(function(h)
				h:addPlayer({ userId = 7, name = "Early" })
			end)
			ctx.h:settle(5)
			local early = ctx.h.game.Players:GetPlayers()[1]
			expect(ctx.N.slotOf(early)).toBe(1)
			local ghost = ctx.h:addPlayer({ userId = 8, spawn = false })
			ctx.h:settle(3)
			expect(ctx.N.slotOf(ghost)).toBe(2)
			expect(ctx.N.inOwnHarbor(ghost)).toBe(false)
			expect(ctx.N.inOwnHarbor(ghost, ctx.WorldLayout.nestCenter(2))).toBe(true)
			expect(ctx.N.inOwnHarbor(ghost, ctx.WorldLayout.nestCenter(3))).toBe(false)
			ctx.N.teleportHome(ghost)
			ctx.h:respawn(ghost)
			expect(ctx.N.inOwnHarbor(ghost)).toBe(true)
		end)
	end)

	describe("NestService › perchoirs et constellation", function()
		it("PerchData « code.étoiles » ; valeurs mémorisées avant l'attribution du Nid", function()
			local ctx = boot()
			local a = join(ctx, 1)
			ctx.N.setPerchDisplay(a, {
				{ code = 23, stars = 2 },
				{ code = 0 / 0, stars = 1 },
				{ code = 16, stars = 9 },
				{ code = 1040, stars = 1 },
			})
			expect(ctx.WS.nest(1):GetAttribute("PerchData")).toBe("23.2,1040.1")
			ctx.N.setPerchCount(a, 0 / 0)
			ctx.N.setPerchCount(a, 999)
			expect(ctx.WS.nest(1):GetAttribute("PerchCount")).toBe(46)
			ctx.N.setPerchDisplay(a, "nope")
		end)

		it("Supernova : attribut Supernovas du Nid et du joueur", function()
			local ctx = boot()
			local a, data = join(ctx, 1)
			data.supernovas = 4
			ctx.Signals.Supernova:Fire(a, 4)
			ctx.h:settle(1)
			expect(ctx.WS.nest(1):GetAttribute("Supernovas")).toBe(4)
			expect(a:GetAttribute("Supernovas")).toBe(4)
		end)
	end)

	describe("NestService › réglages", function()
		it("Zen : port sûr, recharge 60 s, Feedback, signal et analytique", function()
			local ctx = boot()
			local a, data = join(ctx, 1)
			local changes = {}
			ctx.Signals.SettingChanged:Connect(function(pl, key, value)
				table.insert(changes, { key = key, value = value })
			end)
			farFromHome(ctx, a)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", a, "zen", true)
			expect(data.settings.zen).toBe(false)
			expect(lastFeedback(ctx.h, a).key).toBe("feedback.notInHarbor")
			ctx.N.teleportHome(a)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", a, "zen", true)
			expect(data.settings.zen).toBe(true)
			expect(ctx.N.isZen(a)).toBe(true)
			expect(a:GetAttribute("Zen")).toBe(true)
			expect(lastFeedback(ctx.h, a).key).toBe("feedback.zenOn")
			ctx.Clock.advance(20)
			local ok, reason = ctx.N.applySetting(a, "zen", false)
			expect(ok).toBe(false)
			expect(reason).toBe("feedback.zenCooldown")
			expect(lastFeedback(ctx.h, a).vars.seconds).toBe(40)
			ctx.Clock.advance(40)
			expect(ctx.N.applySetting(a, "zen", false)).toBe(true)
			expect(ctx.N.isZen(a)).toBe(false)
			expect(lastFeedback(ctx.h, a).key).toBe("feedback.zenOff")
			ctx.h:settle(1)
			expect(changes).toEqual({ { key = "zen", value = true }, { key = "zen", value = false } })
			local zen = {}
			for _, e in ctx.h.log.analytics do
				if e.method == "LogCustomEvent" and e.args[2] == "ZenToggled" then
					table.insert(zen, e.args[3])
				end
			end
			expect(zen).toEqual({ 1, 0 })
		end)

		it("autres réglages sauvegardés et langue ; valeurs invalides ignorées", function()
			local ctx = boot()
			local a, data = join(ctx, 1)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", a, "lang", "fr")
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", a, "autoCrew", false)
			expect(data.settings.lang).toBe("fr")
			expect(data.settings.autoCrew).toBe(false)
			expect(ctx.N.setting(a, "lang")).toBe("fr")
			expect(ctx.N.setting(a, "music")).toBe(true)
			expect(ctx.N.setting(a, "privateNoSnip")).toBe(false)
			ctx.Clock.advance(5)
			local before = table.clone(data.settings)
			local bad = {
				{ "lang", "de" },
				{ "lang", true },
				{ "lang", string.rep("f", 500) },
				{ "music", "yes" },
				{ "music", 0 / 0 },
				{ "zen", 1 },
				{ "nope", true },
				{ nil, true },
				{ {}, true },
				{ 0 / 0, false },
				{ string.rep("z", 5000), true },
			}
			for i, pair in bad do
				if i % 4 == 0 then
					task.wait(1.05) -- débit réel : 4 / s
				end
				ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", a, pair[1], pair[2])
			end
			expect(data.settings).toEqual(before)
			expect(#feedbackKeys(ctx.h, a)).toBe(0)
		end)

		it("« Coupes désactivées » : propriétaire du serveur privé seulement (mémoire)", function()
			local ctx = boot()
			local a, data = join(ctx, 1)
			local b = join(ctx, 2)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", a, "privateNoSnip", true)
			expect(ctx.N.snipsDisabled()).toBe(false)
			expect(lastFeedback(ctx.h, a).key).toBe("feedback.ownerOnly")
			ctx.h.game.PrivateServerOwnerId = 2
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", a, "privateNoSnip", true)
			expect(ctx.N.snipsDisabled()).toBe(false)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", b, "privateNoSnip", true)
			expect(ctx.N.snipsDisabled()).toBe(true)
			expect(ctx.N.setting(a, "privateNoSnip")).toBe(true)
			expect(data.settings.privateNoSnip).toBeNil()
		end)
	end)

	describe("NestService › cosmétiques", function()
		it("équipe un style possédé ; refuse sinon (notOwned) ; titre vide = aucun", function()
			local ctx = boot()
			local a, data = join(ctx, 1)
			ctx.h:fireServer("ReplicatedStorage.Remotes.EquipCosmetic", a, "style", "royal_star")
			expect(data.cosmetics.style).toBe("default")
			expect(lastFeedback(ctx.h, a).key).toBe("feedback.notOwned")
			ctx.N.unlock(a, "styles", "comet_tail")
			expect(data.unlocks.styles.comet_tail).toBe(true)
			local cel = ctx.h:sentTo(a, "Celebrate")
			expect(cel[#cel][1]).toEqual({ kind = "unlock", data = { kind = "styles", id = "comet_tail" } })
			ctx.h:fireServer("ReplicatedStorage.Remotes.EquipCosmetic", a, "style", "comet_tail")
			expect(data.cosmetics.style).toBe("comet_tail")
			expect(a:GetAttribute("LineStyle")).toBe("comet_tail")
			expect(ctx.WS.nest(1):GetAttribute("LineStyle")).toBe("comet_tail")
			expect(lastFeedback(ctx.h, a).key).toBe("feedback.styleEquipped")
			expect(ctx.N.equip(a, "title", "")).toBe(true)
			expect(ctx.N.equip(a, "theme", "")).toBe(false)
			-- déjà débloqué : pas de seconde célébration
			local n = #ctx.h:sentTo(a, "Celebrate")
			ctx.N.unlock(a, "styles", "comet_tail")
			ctx.N.unlock(a, "styles", "does_not_exist")
			ctx.N.unlock(a, "hats", "comet_tail")
			expect(#ctx.h:sentTo(a, "Celebrate")).toBe(n)
		end)

		it("sources : pass VIP (badge, thème Or Royal), statistique, Atlas, R atteint", function()
			local ctx = boot()
			local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
			local profile = ctx.Schema.defaults()
			profile.passes = { VIPStar = true }
			profile.stats.cometsBanked = 10
			local Nebbies = ctx.h:require("ReplicatedStorage.Shared.Config.Nebbies")
			local n = 0
			for s = 1, 36 do
				for f = 0, 3 do
					if n < 132 then
						Nebbies.setBit(profile.atlas, Nebbies.atlasIndex(s, f))
						n += 1
					end
				end
			end
			store:SetAsync("player_1", { data = profile })
			local a, data = join(ctx, 1)
			expect(a:GetAttribute("VIP")).toBe(true)
			expect(ctx.N.hasUnlock(a, "styles", "royal_star")).toBe(true)
			expect(ctx.N.hasUnlock(a, "titles", "comet_hunter")).toBe(true)
			expect(ctx.N.hasUnlock(a, "titles", "beacon_keeper")).toBe(false)
			expect(ctx.N.hasUnlock(a, "titles", "cartographer")).toBe(true)
			expect(ctx.N.hasUnlock(a, "themes", "atlas")).toBe(false)
			expect(ctx.N.hasUnlock(a, "styles", "rainbow_ripple")).toBe(false)
			expect(ctx.N.hasUnlock(a, "nope", "x")).toBe(false)
			expect(ctx.N.equip(a, "theme", "royal_gold")).toBe(true)
			expect(data.cosmetics.nestTheme).toBe("royal_gold")
			expect(ctx.WS.nest(1):GetAttribute("NestTheme")).toBe("royal_gold")
			local platform = ctx.WS.nest(1):FindFirstChild("Platform")
			expect(platform.Color).toEqual(ctx.Cosmetics.Themes.royal_gold.platform)
			-- source « supernova » (aucun cosmétique au lancement : vérifiée sur une config de test)
			ctx.Cosmetics.Titles.nova_test = { order = 99, source = { kind = "supernova", supernovas = 3 } }
			expect(ctx.N.hasUnlock(a, "titles", "nova_test")).toBe(false)
			data.supernovas = 3
			expect(ctx.N.hasUnlock(a, "titles", "nova_test")).toBe(true)
		end)

		it(
			"déblocage temporaire de session ; équipé mais plus possédé → affiché par défaut",
			function()
				local ctx = boot()
				local a, data = join(ctx, 1)
				ctx.N.grantTemporary(a, "titles", "conga_royal")
				expect(ctx.N.equip(a, "title", "conga_royal")).toBe(true)
				expect(a:GetAttribute("Title")).toBe("conga_royal")
				expect(data.unlocks.titles.conga_royal).toBeNil()
				ctx.h:removePlayer(a)
				ctx.h:settle(5)
				local b, d2 = join(ctx, 1)
				expect(d2.cosmetics.title).toBe("conga_royal") -- le choix est gardé…
				expect(b:GetAttribute("Title")).toBe("") -- … mais pas affiché sans le déblocage
				ctx.N.grantTemporary(b, "titles", "conga_royal")
				expect(b:GetAttribute("Title")).toBe("conga_royal")
				expect(ctx.WS.nest(1):GetAttribute("Title")).toBe("conga_royal")
			end
		)

		it("EquipCosmetic malveillant : aucune erreur, aucune mutation", function()
			local ctx = boot()
			local a, data = join(ctx, 1)
			local before = table.clone(data.cosmetics)
			local bad = {
				{ "style", "royal_star" },
				{ "styles", "default" },
				{ "hat", "default" },
				{ nil, nil },
				{ "style", 0 / 0 },
				{ "title", string.rep("t", 500) },
				{ {}, "default" },
				{ "theme", "atlas" },
			}
			for i, pair in bad do
				if i % 2 == 1 and i > 1 then
					task.wait(0.55) -- débit réel : 2 / s
				end
				ctx.h:fireServer("ReplicatedStorage.Remotes.EquipCosmetic", a, pair[1], pair[2])
			end
			expect(data.cosmetics).toEqual(before)
			for _, key in feedbackKeys(ctx.h, a) do
				expect(key).toBe("feedback.notOwned")
			end
		end)
	end)

	-- Bugs trouvés en revue : chaque test reproduit le défaut corrigé
	describe("NestService › revue", function()
		it("départ pendant la vérification d'amitié : aucun cache recréé, aucun Nid pris", function()
			-- défaut : IsFriendsWith yield ; un joueur parti pendant l'appel retrouvait une entrée dans
			-- friendCache (et l'ami une entrée à son UserId), jamais vidées
			local MockInstance = require("../harness/MockInstance")
			local ctx = boot()
			local a = join(ctx, 1)
			local realAreFriends = MockInstance.areFriends
			MockInstance.areFriends = function(x, y)
				task.wait(0.05)
				return realAreFriends(x, y)
			end
			ctx.h:makeFriends(1, 2)
			local b = ctx.h:addPlayer({ userId = 2, name = "B" })
			ctx.h:removePlayer(b) -- pendant IsFriendsWith
			ctx.h:settle(5)
			task.wait(0.1)
			ctx.h:settle(3)
			MockInstance.areFriends = realAreFriends
			expect(ctx.N.slotOf(b)).toBe(0)
			expect(ctx.WS.nest(2):GetAttribute("OwnerUserId")).toBe(0)
			expect(ctx.N.debugTracked(b)).toBe(false)
			-- l'ami resté ne garde rien au UserId du parti
			expect(ctx.N.slotOf(a)).toBe(1)
			-- un ami qui part pendant la vérification d'un arrivant
			MockInstance.areFriends = function(x, y)
				task.wait(0.05)
				return realAreFriends(x, y)
			end
			ctx.h:makeFriends(1, 3)
			local c = ctx.h:addPlayer({ userId = 3, name = "C" })
			ctx.h:removePlayer(a)
			ctx.h:settle(5)
			task.wait(0.1)
			ctx.h:settle(3)
			MockInstance.areFriends = realAreFriends
			expect(ctx.N.debugTracked(a)).toBe(false)
			expect(ctx.N.slotOf(c) > 0).toBe(true)
			expect(#ctx.h.errors).toBe(0)
		end)

		it(
			"appels tardifs après le départ (perchoirs, titre temporaire) : rien n'est mémorisé",
			function()
				local ctx = boot()
				local a = join(ctx, 1)
				ctx.N.setPerchCount(a, 4)
				ctx.N.setPerchDisplay(a, { { code = 1, stars = 1 } })
				ctx.h:removePlayer(a)
				ctx.h:settle(3)
				ctx.N.setPerchCount(a, 6)
				ctx.N.setPerchDisplay(a, { { code = 2, stars = 1 } })
				ctx.N.grantTemporary(a, "titles", "conga_royal")
				expect(ctx.N.debugTracked(a)).toBe(false)
				expect(ctx.WS.nest(1):GetAttribute("PerchCount")).toBe(0)
				expect(ctx.WS.nest(1):GetAttribute("PerchData")).toBe("")
			end
		)
	end)
end
