--!nocheck
-- CommunityService (paquet meta, docs/04 §11.8, §18.2) : amis et FriendsChanged, pet-sitting (clôture
-- d'un ami côté rue, libérée quand il part et pendant le Rush, réappliquée après ; PetPress : plafonds
-- 100 / 100 / 20 par ami, 2 s de revenu × 2 si PERFECT, PetSitRewarded à 3 arguments seulement sous le
-- plafond), bannières (priorité, 3 au plus, 3 s, 10 s par source, nouveaux discrets), réglages, nom
-- caché, cosmétiques, unlockSession, emotes, applaudissements (openClapWindow avec spectateurs),
-- liste de blocage souple, états minutés, zéro trace.
local Flags = require("../harness/Flags")
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60 -- loin du prochain Rush (~ 3 min)
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local function world(before, harness)
		local w = Brains.boot(harness or Harness, { t0 = T0, stubMeta = false, before = before })
		w.C = w.h:require(S .. "CommunityService")
		w.WL = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		return w
	end

	-- Profils v2 (recette de DataChaos : SchemaV2 posé avant le premier require du schéma)
	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require("ReplicatedStorage.Shared.Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local function owned(w, id, n)
		local list = {}
		for i = 1, n or 4 do
			table.insert(list, { s = 2, z = 50 + i })
		end
		return Brains.join(w, id, { profile = Brains.profile(w, { squishies = list }) })
	end

	local function friends(w)
		w.h:makeFriends(1, 2)
		local owner = owned(w, 1, 4)
		local visitor = owned(w, 2, 2)
		w.h:settle(3)
		Bots.place(owner, Brains.atRanch(w, owner, 0, 30))
		return owner, visitor
	end

	-- côté rue, à ≤ 10 studs des places 1 et 2 de la clôture (repère local (−27, 5) et (−12, 5)) et
	-- à ≤ 12 studs de chacune (portée de la pression)
	local function street(w, owner, x)
		return Brains.atRanch(w, owner, x or -19.5, -1)
	end

	local function fence(w, owner)
		local uids, reason = w.Ranch.fenceOf(w.Ranch.slotOf(owner))
		return uids, reason
	end

	local function caps(w, p)
		return w.DS.get(p).caps
	end

	describe("CommunityService › amis", function()
		it(
			"amis présents comptés à l'arrivée et au départ : FriendsChanged, bonus d'amis, cache",
			function()
				local w = world()
				local changes = {}
				w.Signals.FriendsChanged:Connect(function(p, n)
					table.insert(changes, { p.UserId, n })
				end)
				local owner, visitor = friends(w)
				expect(w.C.friendsPresent(owner)).toBe(1)
				expect(w.C.friendsPresent(visitor)).toBe(1)
				expect(w.C.areFriends(owner, visitor)).toBe(true)
				local stranger = owned(w, 3, 1)
				w.h:settle(3)
				expect(w.C.areFriends(owner, stranger)).toBe(false)
				expect(w.C.friendsPresent(stranger)).toBe(0)
				Bots.leave(visitor)
				w.h:settle(3)
				expect(w.C.friendsPresent(owner)).toBe(0)
				local last = changes[#changes]
				expect(last[1]).toBe(1)
				expect(last[2]).toBe(0)
			end
		)
	end)

	describe("CommunityService › pet-sitting", function()
		it(
			"ami côté rue à ≤ 10 studs : 3 squishies à la clôture ; parti : libérés ; jamais pour un inconnu",
			function()
				local w = world()
				local owner, visitor = friends(w)
				Bots.place(visitor, street(w, owner))
				Brains.frames(w, 8)
				local uids, reason = fence(w, owner)
				expect(reason).toBe("petsit")
				expect(#uids).toBe(3)
				-- la liste reste stable tant que l'ami est là
				Brains.frames(w, 10)
				local again = fence(w, owner)
				expect(again).toEqual(uids)
				Bots.place(visitor, Bots.ground(0, 0))
				Brains.frames(w, 8)
				local after, r2 = fence(w, owner)
				expect(#after).toBe(0)
				expect(r2).toBe("")
				local stranger = owned(w, 3, 1)
				Bots.place(stranger, street(w, owner))
				Brains.frames(w, 8)
				expect(#fence(w, owner)).toBe(0)
			end
		)

		it(
			"pendant le Rush : clôture de pet-sitting effacée ; réappliquée au step qui suit la fin du Rush",
			function()
				local w = world()
				local owner, visitor = friends(w)
				Bots.place(visitor, street(w, owner))
				Brains.frames(w, 8)
				expect(#fence(w, owner)).toBe(3)
				w.Signals.EventPhase:Fire("rush", "start", 1)
				Brains.frames(w, 8)
				local _, reason = fence(w, owner)
				expect(reason ~= "petsit").toBe(true)
				w.Signals.EventPhase:Fire("rush", "end", 1)
				Brains.frames(w, 2)
				local uids, r2 = fence(w, owner)
				expect(r2).toBe("petsit")
				expect(#uids).toBe(3)
			end
		)

		it(
			"PetPress : 2 s de revenu (× 2 si PERFECT), plafonds consommés, PetSitRewarded(visiteur, propriétaire, vrai)",
			function()
				local w = world()
				local owner, visitor = friends(w)
				Bots.place(visitor, street(w, owner))
				Brains.frames(w, 8)
				local uids = fence(w, owner)
				local rewarded = {}
				w.Signals.PetSitRewarded:Connect(function(v, o, helpful)
					table.insert(rewarded, { v = v, o = o, helpful = helpful })
				end)
				local perfect = nil
				w.Signals.Pressed:Connect(function(_, info)
					perfect = info.perfect
				end)
				local Economy = w.h:require(S .. "EconomyService")
				local income = Economy.income(visitor)
				local before = w.DS.get(visitor).coins
				local ownerCoins = w.DS.get(owner).coins
				w.h:fireServer(R .. "PetPress", visitor, owner.UserId, uids[1], w.Clock.now())
				expect(#rewarded).toBe(1)
				expect(rewarded[1].v).toBe(visitor)
				expect(rewarded[1].o).toBe(owner)
				expect(rewarded[1].helpful).toBe(true)
				local gained = w.DS.get(visitor).coins - before
				local expected = math.max(1, math.floor(income * (if perfect then 4 else 2)))
				expect(math.abs(gained - expected) <= 1).toBe(true)
				expect(w.DS.get(owner).coins > ownerCoins).toBe(true)
				expect(caps(w, visitor).petSit).toBe(1)
				expect(caps(w, owner).petSitIn).toBe(1)
				expect(caps(w, visitor).petSitBy[tostring(owner.UserId)]).toBe(1)
				-- même squishy : recharge de 8 s, refus muet
				w.osClock.advance(1)
				w.h:fireServer(R .. "PetPress", visitor, owner.UserId, uids[1], w.Clock.now())
				expect(#rewarded).toBe(1)
			end
		)

		it(
			"« Plus serviable » : 20 par ami et par jour (3e argument faux au-delà) ; 100 récompensées, 100 reçues",
			function()
				local w = world()
				local owner, visitor = friends(w)
				Bots.place(visitor, street(w, owner))
				Brains.frames(w, 8)
				local uids = fence(w, owner)
				local rewarded = {}
				w.Signals.PetSitRewarded:Connect(function(_, _, helpful)
					table.insert(rewarded, helpful)
				end)
				caps(w, visitor).day = w.Clock.day()
				caps(w, visitor).petSitBy[tostring(owner.UserId)] = 20
				w.h:fireServer(R .. "PetPress", visitor, owner.UserId, uids[1], w.Clock.now())
				expect(rewarded).toEqual({ false })
				-- plafond du visiteur atteint : refusé avant toute pression
				caps(w, visitor).petSit = 100
				w.osClock.advance(1)
				w.h:fireServer(R .. "PetPress", visitor, owner.UserId, uids[2], w.Clock.now())
				expect(#rewarded).toBe(1)
				expect(table.find(Bots.feedbackKeys(visitor), "feedback.capReached") ~= nil).toBe(true)
				-- plafond du propriétaire atteint (second compte) : refusé
				caps(w, visitor).petSit = 0
				caps(w, owner).day = w.Clock.day()
				caps(w, owner).petSitIn = 100
				local ownerCoins = w.DS.get(owner).coins
				w.osClock.advance(1)
				w.h:fireServer(R .. "PetPress", visitor, owner.UserId, uids[2], w.Clock.now())
				expect(#rewarded).toBe(1)
				expect(w.DS.get(owner).coins).toBe(ownerCoins)
			end
		)

		it("refusé : pas ami, bloqué, propriétaire inconnu, squishy pas à la clôture", function()
			local w = world()
			local owner, visitor = friends(w)
			local stranger = owned(w, 3, 1)
			Bots.place(visitor, street(w, owner))
			Bots.place(stranger, street(w, owner, -20))
			Brains.frames(w, 8)
			local uids = fence(w, owner)
			local n = 0
			w.Signals.PetSitRewarded:Connect(function()
				n += 1
			end)
			w.h:fireServer(R .. "PetPress", stranger, owner.UserId, uids[2], w.Clock.now())
			w.h:fireServer(R .. "PetPress", visitor, 999, uids[1], w.Clock.now())
			w.h:fireServer(R .. "PetPress", visitor, owner.UserId, "zz", w.Clock.now())
			w.h:fireServer(R .. "ReportBlocked", owner, { visitor.UserId })
			w.osClock.advance(1)
			w.h:fireServer(R .. "PetPress", visitor, owner.UserId, uids[1], w.Clock.now())
			expect(n).toBe(0)
			expect(w.C.isBlocked(visitor, owner)).toBe(true)
			expect(w.C.isBlocked(owner, visitor)).toBe(true)
		end)
	end)

	describe("CommunityService › bannières", function()
		it(
			"file : priorité, 3 au plus, 3 s chacune, 10 s par joueur source ; nom caché → name vide",
			function()
				local w = world()
				local a = owned(w, 1, 1)
				local b = owned(w, 2, 1)
				local Notify = w.h:require("ServerScriptService.Server.Util.Notify")
				w.DS.get(b).settings.hideName = true
				Notify.banner("goldenCaught", { species = 3 }, a)
				Notify.banner("goldenCaught", { species = 3 }, a) -- même source dans les 10 s : jetée
				Notify.banner("splorch", {}, b)
				Notify.banner("legendHatch", { species = 9 }, nil)
				Notify.banner("squishParty", {}, nil)
				Notify.banner("wobbleParty", {}, nil) -- file pleine, moins prioritaire : jetée
				w.h:settle(1)
				local seen = {}
				for _ = 1, 4 do
					w.C.step(w.Clock.now(), {})
					w.Clock.advance(3.1)
				end
				for _, e in w.h:sentTo(a, "Banner") do
					table.insert(seen, e[1].kind)
				end
				-- file pleine à l'arrivée de squishParty (7, moins prioritaire que tout) : jetée ; wobbleParty aussi
				expect(seen).toEqual({ "splorch", "legendHatch", "goldenCaught" })
				local first = w.h:sentTo(a, "Banner")[1][1]
				expect(first.args.name).toBe("")
				expect(first.args.userId).toBe(2)
				expect(first.priority).toBe(1)
			end
		)

		it(
			"nouveau avant l'étape 9 : bannières mises en attente, données après l'étape 9 si elles ont moins de 30 s",
			function()
				local w = world()
				local veteran = owned(w, 1, 1)
				local newbie = Brains.join(w, 2, { profile = Bots.profile(w, {}) })
				local Notify = w.h:require("ServerScriptService.Server.Util.Notify")
				Notify.banner("legendHatch", { species = 9 }, veteran)
				w.h:settle(1)
				w.C.step(w.Clock.now(), {})
				expect(#w.h:sentTo(veteran, "Banner")).toBe(1)
				expect(#w.h:sentTo(newbie, "Banner")).toBe(0)
				w.DS.get(newbie).onboarding.step = 9
				w.Clock.advance(3.1)
				w.C.step(w.Clock.now(), {})
				expect(#w.h:sentTo(newbie, "Banner")).toBe(1)
			end
		)
	end)

	describe("CommunityService › réglages, cosmétiques, emotes", function()
		it(
			"SetSetting : types et valeurs de Config/Settings ; hideName → SettingChanged, nom public vide",
			function()
				local w = world()
				local p = owned(w, 1, 1)
				local changed = {}
				w.Signals.SettingChanged:Connect(function(_, key, value)
					table.insert(changed, { key, value })
				end)
				w.h:fireServer(R .. "SetSetting", p, "hideName", true)
				expect(w.DS.get(p).settings.hideName).toBe(true)
				expect(w.C.displayName(p)).toBe("")
				expect(w.Ranch.publicOf(w.Ranch.slotOf(p)).hidden).toBe(true)
				expect(w.Ranch.publicOf(w.Ranch.slotOf(p)).name).toBe("")
				w.osClock.advance(1)
				w.h:fireServer(R .. "SetSetting", p, "lang", "de") -- valeur hors liste
				w.h:fireServer(R .. "SetSetting", p, "hideName", "oui") -- mauvais type
				w.h:fireServer(R .. "SetSetting", p, "nope", true) -- clé inconnue
				w.osClock.advance(1)
				w.h:fireServer(R .. "SetSetting", p, "emoteLeft", "crown") -- pas débloquée
				w.h:fireServer(R .. "SetSetting", p, "allowRush", true) -- pas propriétaire du serveur privé
				expect(#changed).toBe(1)
				expect(w.DS.get(p).settings.lang).toBe("auto")
				expect(w.C.setting(p, "allowRush")).toBe(false)
			end
		)

		-- Lot A4 (D24, docs/04 §27.12 A4-2) : « Montrer mon halo » (Config/Settings since = 2) n'est
		-- jamais écrit dans un profil v1 ni quand RanchSkins est coupé (le jeu de base ne l'écrit jamais)
		it(
			"SetSetting « haloOn » : refusé sur un profil v1 et RanchSkins coupé (rien d'écrit ni d'envoyé) ; accepté sur un profil v2 avec RanchSkins",
			function()
				local function patches(w, p)
					w.h:settle(2)
					return #w.h:sentTo(p, "DataPatch")
				end
				-- profil v1 (serveur de la v1.3, préréglage « v13 », lot I D2 a) : refusé, interrupteur coupé
				-- puis ouvert
				local w = world(nil, Flags.harness(Harness, "v13"))
				local p = owned(w, 1, 1)
				local changed = 0
				w.Signals.SettingChanged:Connect(function()
					changed += 1
				end)
				local F = w.h:require("ReplicatedStorage.Shared.Config.Features")
				local before = patches(w, p)
				w.h:fireServer(R .. "SetSetting", p, "haloOn", false)
				w.osClock.advance(1)
				expect(F.set("RanchSkins", true)).toBe(true)
				w.h:fireServer(R .. "SetSetting", p, "haloOn", false)
				w.osClock.advance(1)
				expect(w.DS.get(p).version).toBe(1)
				expect(w.DS.get(p).settings.haloOn).toBeNil()
				expect(patches(w, p)).toBe(before)
				expect(changed).toBe(0)
				-- profil v2 : RanchSkins coupé → refusé, rien d'envoyé ; ouvert → écrit et envoyé (départ « cut » :
				-- RanchSkins est ouvert au lancement depuis le lot I, I-24)
				local w2 = world(nil, Flags.harness(Harness, "cut"))
				local q = owned(w2, 1, 1)
				local F2 = w2.h:require("ReplicatedStorage.Shared.Config.Features")
				local seen = {}
				w2.Signals.SettingChanged:Connect(function(_, key, value)
					table.insert(seen, { key, value })
				end)
				expect(w2.DS.get(q).version).toBe(2)
				expect(w2.DS.get(q).settings.haloOn).toBe(true)
				local before2 = patches(w2, q)
				w2.h:fireServer(R .. "SetSetting", q, "haloOn", false)
				w2.osClock.advance(1)
				expect(w2.DS.get(q).settings.haloOn).toBe(true)
				expect(patches(w2, q)).toBe(before2)
				expect(F2.set("RanchSkins", true)).toBe(true)
				w2.h:fireServer(R .. "SetSetting", q, "haloOn", "non") -- mauvais type
				w2.osClock.advance(1)
				w2.h:fireServer(R .. "SetSetting", q, "haloOn", false)
				expect(w2.DS.get(q).settings.haloOn).toBe(false)
				expect(seen).toEqual({ { "haloOn", false } })
				expect(patches(w2, q) > before2).toBe(true)
			end
		)

		it(
			"EquipCosmetic : débloqué seulement ; unlockSession (titre de la semaine) vu aussitôt, perdu au départ",
			function()
				local w = world()
				local p = owned(w, 1, 1)
				w.h:fireServer(R .. "EquipCosmetic", p, "title", "stamp_hunter")
				expect(w.DS.get(p).cosmetics.title).toBe("")
				w.C.unlockSession(p, "title", "stamp_hunter")
				expect(w.C.hasCosmetic(p, "title", "stamp_hunter")).toBe(true)
				-- une carte « unlock » de titre ; depuis l'ouverture de DecoPerso au lancement (lot I, I-24), le
				-- profil de test (1 h de jeu) gagne aussi le fanion des 5 min (carte « unlock » de sorte deco)
				local titles = {}
				for _, d in Bots.celebrations(p, "unlock") do
					if d.kind == "title" then
						table.insert(titles, d.id)
					end
				end
				expect(titles).toEqual({ "stamp_hunter" })
				w.osClock.advance(1)
				w.h:fireServer(R .. "EquipCosmetic", p, "title", "stamp_hunter")
				expect(w.DS.get(p).cosmetics.title).toBe("stamp_hunter")
				expect(w.Ranch.publicOf(w.Ranch.slotOf(p)).title).toBe("stamp_hunter")
				-- sources : gratuit, jours de Plop
				expect(w.C.hasCosmetic(p, "saddle", "classic")).toBe(true)
				expect(w.C.hasCosmetic(p, "saddle", "peach")).toBe(false)
				w.DS.get(p).plopDays = 3
				expect(w.C.hasCosmetic(p, "saddle", "peach")).toBe(true)
				expect(w.C.hasCosmetic(p, "saddle", "inconnue")).toBe(false)
				Bots.leave(p)
				w.h:settle(3)
				expect(w.C.hasCosmetic(p, "title", "stamp_hunter")).toBe(false)
			end
		)

		it(
			"Emote : EmoteShow à tous et Emoted ; la croix ← suit settings.emoteLeft s'il est débloqué",
			function()
				local w = world()
				local p = owned(w, 1, 1)
				local q = owned(w, 2, 1)
				local emoted = {}
				w.Signals.Emoted:Connect(function(_, kind)
					table.insert(emoted, kind)
				end)
				w.h:fireServer(R .. "Emote", p, 1)
				w.osClock.advance(1.3)
				w.DS.get(p).settings.emoteLeft = "bellyFlop"
				w.DS.get(p).plopDays = 10
				w.h:fireServer(R .. "Emote", p, 3)
				expect(emoted).toEqual({ 1, 3 })
				local shows = {}
				for _, e in w.h.log.allClientEvents do
					if e.remote == "EmoteShow" then
						table.insert(shows, e.args[1])
					end
				end
				expect(#shows).toBe(2)
				expect(shows[1].emote).toBe("wave")
				expect(shows[2].emote).toBe("bellyFlop")
				local _ = q
			end
		)
	end)

	describe("CommunityService › applaudissements", function()
		it(
			"ClapPrompt aux seuls spectateurs ; Clap d'eux seulement, une fois, 10 s de revenu ; clapCount au héros",
			function()
				local w = world()
				local hero = owned(w, 1, 1)
				local viewer = owned(w, 2, 1)
				local other = owned(w, 3, 1)
				w.C.openClapWindow(hero, w.Clock.now() + 8, { viewer })
				expect(#w.h:sentTo(viewer, "ClapPrompt")).toBe(1)
				expect(#w.h:sentTo(other, "ClapPrompt")).toBe(0)
				expect(#w.h:sentTo(hero, "ClapPrompt")).toBe(0)
				local before = w.DS.get(viewer).coins
				local otherCoins = w.DS.get(other).coins
				w.h:fireServer(R .. "Clap", other, hero.UserId)
				w.h:fireServer(R .. "Clap", viewer, hero.UserId)
				w.h:fireServer(R .. "Clap", viewer, hero.UserId)
				expect(w.DS.get(viewer).coins > before).toBe(true)
				expect(w.DS.get(other).coins).toBe(otherCoins)
				expect(caps(w, viewer).claps).toBe(1)
				local counts = Bots.celebrations(hero, "clapCount")
				expect(#counts).toBe(1)
				expect(counts[1].n).toBe(1)
				-- états minutés : la fenêtre ne dépasse jamais 8 s
				local open = w.C.openStates()
				expect(#open).toBe(1)
				expect(open[1].name).toBe("clapWindow")
				w.Clock.advance(8.1)
				w.C.step(w.Clock.now(), {})
				expect(#w.C.openStates()).toBe(0)
				w.osClock.advance(1)
				w.h:fireServer(R .. "Clap", viewer, hero.UserId)
				expect(caps(w, viewer).claps).toBe(1)
			end
		)

		it(
			"sans liste : tous sauf le héros ; une fin demandée au-delà de 8 s est ramenée à 8 s",
			function()
				local w = world()
				local hero = owned(w, 1, 1)
				local a = owned(w, 2, 1)
				w.C.openClapWindow(hero, w.Clock.now() + 60, nil)
				local prompt = w.h:sentTo(a, "ClapPrompt")[1][1]
				expect(prompt.heroId).toBe(1)
				expect(prompt.endsAt - w.Clock.now() <= 8).toBe(true)
			end
		)
	end)

	describe("CommunityService › revue", function()
		it(
			"amitié retirée pendant une absence : à son retour, plus d'ami (cache d'amitié oublié au départ)",
			function()
				local w = world()
				local owner, visitor = friends(w)
				expect(w.C.areFriends(owner, visitor)).toBe(true)
				Bots.leave(visitor)
				w.h:settle(2)
				w.h.friends[1] = {}
				w.h.friends[2] = {}
				local back = owned(w, 2, 2)
				w.h:settle(3)
				expect(w.C.areFriends(owner, back)).toBe(false)
				expect(w.C.friendsPresent(owner)).toBe(0)
			end
		)
	end)
end
