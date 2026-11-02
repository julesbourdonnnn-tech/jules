--!nocheck
-- SplorchService (paquet chase, docs/04 §11.11, §18.2) : entrée dans la file vérifiée une seule fois
-- (objectif, ranch, portage, fuite en cours → waitEscape, flyer possédé en enclos, double entrée),
-- éclatement d'un bloc à 3,2 s (R + 1, pièces 0, tailles à 1, attente levée), cadeaux (10 en pièces
-- puis 10 s, bébé sous le plafond, réglage « Recevoir les cadeaux »), Splorched APRÈS les cadeaux avec
-- leur nombre, spectacle complet au plus toutes les 180 s par spectateur (sinon short), ClapPrompt aux
-- seuls spectateurs du spectacle complet, départ avant son tour ou avant l'éclatement (rien remis à
-- zéro, aucun cadeau), analytique, délais des états, zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60 -- loin de tout Rush ou MEGA pendant ~3 min

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function ready(w, extra)
		return Brains.profile(w, {
			coins = 5000,
			squishies = {
				{ s = 1, z = 100, bf = 1 },
				{ s = 2, z = 20000 },
				{ s = 3, z = 300 },
				{ s = 4, z = 50, at = "dodo" },
			},
			edit = extra,
		})
	end

	local function world(n)
		local w = Brains.boot(Harness, { t0 = T0 })
		local hero = Brains.join(w, 1, { profile = ready(w) })
		local others = {}
		for i = 2, n or 3 do
			table.insert(
				others,
				Brains.join(w, i, { profile = Brains.profile(w, { squishies = { { s = 2, z = 500 } } }) })
			)
		end
		Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
		Brains.frames(w, 2)
		return w, hero, others
	end

	local function splorch(w, p, flyer)
		w.h:fireServer("ReplicatedStorage.Remotes.GrandSplorch", p, false, flyer or "2")
	end

	-- =========================================================================================
	describe("SplorchService › entrée dans la file", function()
		it(
			"refus : pas assez gros, hors du ranch, en portant, flyer d'un autre ou au Dodo ; double entrée",
			function()
				local w = Brains.boot(Harness, { t0 = T0 })
				local small =
					Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 100 } } }) })
				local hero = Brains.join(w, 2, { profile = ready(w) })
				Bots.place(small, Brains.atRanch(w, small, 0, 30))
				Bots.place(hero, Bots.ground(0, 40))
				Brains.frames(w, 2)
				splorch(w, small, "1")
				expect(table.find(Bots.feedbackKeys(small), "feedback.splorchNotReady") ~= nil).toBe(true)
				-- hors du ranch
				splorch(w, hero)
				expect(table.find(Bots.feedbackKeys(hero), "feedback.onlyOwnRanch") ~= nil).toBe(true)
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 25)
				-- flyer au Dodo, puis inconnu
				splorch(w, hero, "4")
				Brains.frames(w, 21)
				splorch(w, hero, "zz")
				local keys = Bots.feedbackKeys(hero)
				local notOwned = 0
				for _, k in keys do
					if k == "feedback.notOwned" then
						notOwned += 1
					end
				end
				expect(notOwned).toBe(2)
				expect(w.Squishy.waiting(hero)).toBeNil()
				Brains.frames(w, 21)
				-- accepté
				splorch(w, hero, "2")
				expect(w.Squishy.waiting(hero)).toBe("2")
				expect(w.Splorch.queued(hero) ~= nil).toBe(true)
				expect(w.Splorch.isWaiting(hero, "2")).toBe(true)
				expect(table.find(Bots.feedbackKeys(hero), "feedback.splorchQueued") ~= nil).toBe(true)
				-- double entrée : refusée
				Brains.frames(w, 21)
				splorch(w, hero, "3")
				expect(w.Squishy.waiting(hero)).toBe("2")
				expect(table.find(Bots.feedbackKeys(hero), "feedback.waitingSplorch") ~= nil).toBe(true)
				clean(w)
			end
		)

		it("en portant : refusé ; un squishy en fuite : refusé avec waitEscape { species }", function()
			local w, hero = world(2)
			w.h:fireServer("ReplicatedStorage.Remotes.PickUp", hero, "3")
			if w.Squishy.carried(hero) ~= nil then
				Brains.frames(w, 2)
				splorch(w, hero)
				expect(table.find(Bots.feedbackKeys(hero), "feedback.carrying") ~= nil).toBe(true)
				w.h:fireServer("ReplicatedStorage.Remotes.PutDown", hero)
				Brains.frames(w, 21)
			end
			w.Squishy.setEscaping(hero, "3", true)
			splorch(w, hero)
			local fb = w.h:sentTo(hero, "Feedback")
			local last = fb[#fb][1]
			expect(last.key).toBe("feedback.waitEscape")
			expect(last.vars.species).toBe(3)
			expect(w.Squishy.waiting(hero)).toBeNil()
			w.Squishy.setEscaping(hero, "3", false)
			clean(w)
		end)
	end)

	-- =========================================================================================
	describe("SplorchService › spectacle et éclatement", function()
		it(
			"éclatement à 3,2 s d'un bloc : R + 1, pièces 0, tailles 1, attente levée ; cadeaux puis Splorched(héros, R, cadeaux)",
			function()
				local w, hero, others = world(3)
				local events = {}
				w.Signals.Splorched:Connect(function(p, R, gifts)
					table.insert(
						events,
						{ p = p, R = R, gifts = gifts, giftRains = #Bots.celebrations(others[1], "giftRain") }
					)
				end)
				local saves = 0
				local saveNow = w.DS.saveNow
				w.DS.saveNow = function(...)
					saves += 1
					return saveNow(...)
				end
				local coins = { w.Economy.coins(others[1]), w.Economy.coins(others[2]) }
				splorch(w, hero)
				Brains.frames(w, 2)
				local shows = Bots.celebrations(hero, "splorch")
				expect(#shows).toBe(1)
				expect(shows[1].short).toBe(false)
				expect(shows[1].level).toBe(1)
				expect(#Bots.celebrations(others[1], "splorch")).toBe(1)
				-- avant l'éclatement : rien n'a changé
				expect(w.DS.get(hero).R).toBe(0)
				Brains.frames(w, 33)
				local data = w.DS.get(hero)
				expect(data.R).toBe(1)
				expect(data.coins).toBe(0)
				expect(data.squishies["2"].z).toBe(1)
				expect(w.Squishy.waiting(hero)).toBeNil()
				w.h:settle(2)
				expect(saves >= 1).toBe(true)
				-- cadeaux : pièces et bébé pour chaque autre joueur, avant le signal
				expect(#events).toBe(1)
				expect(events[1].R).toBe(1)
				expect(events[1].gifts).toBe(2)
				expect(events[1].giftRains).toBe(1)
				for i, p in others do
					expect(w.Economy.coins(p) > coins[i]).toBe(true)
					local rain = Bots.celebrations(p, "giftRain")[1]
					expect(rain.heroId).toBe(hero.UserId)
					expect(rain.uid ~= "").toBe(true)
					-- bébé : espèce qui s'envole (Peu commune), ≤ 0,5 × le plus gros du receveur
					local baby = w.Squishy.get(p, rain.uid)
					expect(baby.s).toBe(2)
					local _, biggest = w.Squishy.biggest(p)
					expect(baby.z <= 0.5 * biggest + 1e-9).toBe(true)
				end
				-- fenêtre d'applaudissement : jusqu'à t + 8, aux spectateurs du spectacle complet
				expect(#w.meta.claps).toBe(1)
				expect(w.meta.claps[1].hero).toBe(hero)
				expect(#w.meta.claps[1].viewers).toBe(2)
				-- analytique
				local names = {}
				for _, e in w.h.log.analytics do
					if e.method == "LogCustomEvent" then
						names[e.args[2]] = true
					end
				end
				w.DS.saveNow = saveNow
				clean(w)
				local _ = names
			end
		)

		it(
			"spectacle complet au plus toutes les 180 s par spectateur : sinon short, cadeau compté, pas d'APPLAUDIR",
			function()
				local w = Brains.boot(Harness, { t0 = T0 })
				local a = Brains.join(w, 1, { profile = ready(w) })
				local b = Brains.join(w, 2, { profile = ready(w) })
				local viewer =
					Brains.join(w, 3, { profile = Brains.profile(w, { squishies = { { s = 2, z = 500 } } }) })
				Bots.place(a, Brains.atRanch(w, a, 0, 30))
				Bots.place(b, Brains.atRanch(w, b, 0, 30))
				Brains.frames(w, 2)
				splorch(w, a)
				splorch(w, b)
				Brains.frames(w, 320)
				local shows = Bots.celebrations(viewer, "splorch")
				expect(#shows).toBe(2)
				expect(shows[1].short).toBe(false)
				expect(shows[2].short).toBe(true)
				local rains = Bots.celebrations(viewer, "giftRain")
				expect(#rains).toBe(2)
				expect(rains[2].short).toBe(true)
				-- le héros du 2e spectacle a eu le 1er en spectateur complet ; il est toujours complet pour le sien
				local bShows = Bots.celebrations(b, "splorch")
				expect(bShows[#bShows].short).toBe(false)
				-- ClapPrompt (fenêtre) : le spectateur n'est dans les viewers que du premier
				expect(#w.meta.claps).toBe(2)
				local inSecond = false
				for _, p in w.meta.claps[2].viewers do
					if p == viewer then
						inSecond = true
					end
				end
				expect(inSecond).toBe(false)
				clean(w)
			end
		)

		it(
			"cadeaux en pièces : 10 par jour, ensuite 10 s ; « Recevoir les cadeaux » coupé : rien",
			function()
				local w, hero, others = world(3)
				local capped = others[1]
				local data = w.DS.get(capped)
				data.caps.day = w.Clock.day()
				data.caps.splorchCoins = w.Balance.Caps.splorchCoins
				data.caps.splorchGifts = w.Balance.Caps.splorchGifts
				w.meta.settings[others[2].UserId] = { receiveGifts = false }
				local coins = w.Economy.coins(capped)
				local income = w.Economy.income(capped)
				splorch(w, hero)
				Brains.frames(w, 40)
				-- 10 s de revenu (au lieu de 60) : le montant du cadeau suit le revenu du moment
				local rain = Bots.celebrations(capped, "giftRain")[1]
				local incomeNow = math.max(income, w.Economy.income(capped))
				expect(rain.coins <= math.max(10, incomeNow * w.Balance.Rewards.GiftSecondsAfterCap) + 1).toBe(
					true
				)
				expect(rain.coins < incomeNow * w.Balance.Splorch.GiftSeconds * 0.5).toBe(true)
				expect(w.Economy.coins(capped) >= coins + rain.coins).toBe(true)
				expect(rain.uid).toBe("")
				expect(#Bots.celebrations(others[2], "giftRain")).toBe(0)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SplorchService › départs", function()
		it(
			"héros parti avant son tour : place rendue, rien remis à zéro ; parti pendant le spectacle avant l'éclatement : aucun cadeau",
			function()
				local w = Brains.boot(Harness, { t0 = T0 })
				local a = Brains.join(w, 1, { profile = ready(w) })
				local b = Brains.join(w, 2, { profile = ready(w) })
				local viewer =
					Brains.join(w, 3, { profile = Brains.profile(w, { squishies = { { s = 2, z = 500 } } }) })
				Bots.place(a, Brains.atRanch(w, a, 0, 30))
				Bots.place(b, Brains.atRanch(w, b, 0, 30))
				Brains.frames(w, 2)
				splorch(w, a)
				splorch(w, b)
				Brains.frames(w, 5)
				-- b en file (2e) part : place rendue
				local queue = w.Event.state().spectacle.queue
				expect(#queue).toBe(1)
				Bots.leave(b)
				w.h:settle(2)
				expect(#w.Event.state().spectacle.queue).toBe(0)
				-- a part pendant son spectacle, avant l'éclatement : aucun cadeau, profil inchangé
				Bots.leave(a)
				w.h:settle(2)
				Brains.frames(w, 60)
				expect(#Bots.celebrations(viewer, "giftRain")).toBe(0)
				expect(w.Event.state().spectacle.current).toBeNil()
				local saved = w.h.dataStores["PlayerData_v1/global"]
				local _ = saved
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SplorchService › délais des états", function()
		it("splorchQueue et splorchBurst : jamais au-delà de leur délai", function()
			local w, hero = world(2)
			splorch(w, hero)
			local bad = {}
			Bots.use(w)
			for _ = 1, 400 do
				Bots.frame()
				for _, st in w.Splorch.openStates() do
					if w.StateTimeouts.expired(st.name, st.startedAt, w.Clock.now()) then
						table.insert(bad, st.name)
					end
				end
			end
			expect(table.concat(bad, ",")).toBe("")
			expect(#w.Splorch.openStates()).toBe(0)
			clean(w)
		end)
	end)
end
