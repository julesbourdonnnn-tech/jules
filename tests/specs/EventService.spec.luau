--!nocheck
-- EventService (paquet chase, docs/04 §11.10, §18.2) : phases idempotentes, EventState (arrivée,
-- interrupteurs), jauge à source unique (Grand Splorch = +25 exactement, pression ordinaire = 0),
-- objectif 600 × max(2, N actifs), danse → Wobble Party → sieste de 20 min, MEGA (N actifs à
-- l'atterrissage, portée à plat + pieds, recharge, PERFECT, paliers, échec et indulgence), joueurs actifs,
-- file des spectacles (place, attente prévue, Rush, coupure à 480 s, héros parti avant l'éclatement),
-- Squish Party (prolongée de 600 s, partyUnplayed, priorité sur la Wobble Party), Jelly Moon
-- (moon.lastSession d'un serveur à l'autre), AdminCommand ("clock" ignoré hors Studio, non-admin
-- ignoré), délais des états, zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000 -- vendredi 08:00:00 UTC (début d'heure)

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function boot(opts)
		opts = opts or {}
		opts.t0 = opts.t0 or (H0 + 60)
		return Brains.boot(Harness, opts)
	end

	local function phases(w)
		local out = {}
		w.Signals.EventPhase:Connect(function(kind, phase, index)
			table.insert(out, kind .. ":" .. phase .. ":" .. tostring(index))
		end)
		return out
	end

	local function lastState(w, p)
		local list = w.h:sentTo(p, "EventState")
		return list[#list] and list[#list][1]
	end

	local function countOf(list, value)
		local n = 0
		for _, v in list do
			if v == value then
				n += 1
			end
		end
		return n
	end

	-- =========================================================================================
	describe("EventService › phases et EventState", function()
		it(
			"Rush : siren, start, end une seule fois par index (ticks répétés au même instant compris)",
			function()
				local w = boot({ t0 = H0 + 285 })
				local seen = phases(w)
				Brains.join(w, 1)
				Brains.frames(w, 60)
				w.Event.step(w.Clock.now(), w.Chase.actors())
				w.Event.step(w.Clock.now(), w.Chase.actors())
				Brains.frames(w, 1000)
				local rush = w.EventClock.rush(H0 + 300)
				expect(countOf(seen, "rush:siren:" .. rush.index)).toBe(1)
				expect(countOf(seen, "rush:start:" .. rush.index)).toBe(1)
				expect(countOf(seen, "rush:end:" .. rush.index)).toBe(1)
				clean(w)
			end
		)

		it(
			"EventState à l'arrivée (features complets) ; renvoyé à tous après AdminCommand « feature » d'un admin",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				local b = Brains.join(w, 2)
				w.meta.admins[1] = true
				Brains.frames(w, 2)
				local st = lastState(w, a)
				expect(st ~= nil).toBe(true)
				expect(st.features.megaSquish).toBe(true)
				expect(st.features.boopRush).toBe("on")
				expect(type(st.features.costume)).toBe("string")
				expect(st.gauge.restUntil).toBe(0)
				local before = #w.h:sentTo(b, "EventState")
				w.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", a, "feature", "MegaSquish=false")
				expect(#w.h:sentTo(b, "EventState")).toBe(before + 1)
				expect(lastState(w, b).features.megaSquish).toBe(false)
				expect(w.Features.get("MegaSquish")).toBe(false)
				clean(w)
			end
		)

		it(
			"AdminCommand d'un non-administrateur : aucune réponse, aucune mutation ; « clock » ignoré hors Studio",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				Brains.frames(w, 2)
				local sent = #w.h:sentTo(a, "EventState")
					+ #w.h:sentTo(a, "Feedback")
					+ #w.h:sentTo(a, "Celebrate")
				w.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", a, "feature", "MegaSquish=false")
				w.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", a, "party", "")
				expect(w.Features.get("MegaSquish")).toBe(true)
				expect(w.Event.state().boost.kind).toBe("")
				expect(
					#w.h:sentTo(a, "EventState") + #w.h:sentTo(a, "Feedback") + #w.h:sentTo(a, "Celebrate")
				).toBe(sent)
				-- administrateur, serveur en ligne (pas Studio) : l'horloge ne bouge pas
				w.meta.admins[1] = true
				Brains.frames(w, 10)
				w.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", a, "clock", "3600")
				expect(w.Clock.getOffset()).toBe(0)
				clean(w)
			end
		)

		it("« clock » en Studio : décalage appliqué et diffusé (EventState.offset)", function()
			local w = boot({ harness = { isStudio = true } })
			local a = Brains.join(w, 1)
			w.meta.admins[1] = true
			Brains.frames(w, 2)
			w.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", a, "clock", "120")
			expect(w.Clock.getOffset()).toBe(120)
			expect(lastState(w, a).offset).toBe(120)
			w.Clock.setOffset(0)
			clean(w)
		end)
	end)

	-- =========================================================================================
	describe("EventService › jauge (source unique)", function()
		it(
			"un Grand Splorch = +25 exactement ; pression ordinaire 0 ; PERFECT 1 ; pet-sitting 2 ; naissance 2 ; fusion 3 ; captures 4 / 6 ; de près 4 / 2 ; bol 10",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				Brains.frames(w, 2)
				local function points()
					return w.Event.state().gauge.points
				end
				local function after(fn)
					local before = w.Event.state().gauge.points
					fn()
					Brains.frames(w, 12)
					return w.Event.state().gauge.points - before
				end
				expect(after(function()
					w.Signals.Splorched:Fire(a, 1, 3)
				end)).toBe(25)
				expect(after(function()
					w.Signals.Pressed:Fire(a, { uid = "1", perfect = false, streak = 0 })
				end)).toBe(0)
				expect(after(function()
					w.Signals.Pressed:Fire(a, { uid = "1", perfect = true, streak = 1 })
				end)).toBe(1)
				expect(after(function()
					w.Signals.Pressed:Fire(a, { uid = "1", perfect = true, streak = 1, visitor = a })
				end)).toBe(2)
				expect(after(function()
					w.Signals.Hatched:Fire(a, "1", 1)
				end)).toBe(2)
				expect(after(function()
					w.Signals.Fused:Fire(a, "1", 1)
					w.Signals.Fused:Fire(a, "1", 2)
				end)).toBe(6)
				expect(after(function()
					w.Signals.Caught:Fire(a, { kind = "runaway" })
				end)).toBe(4)
				expect(after(function()
					w.Signals.Caught:Fire(a, { kind = "escape" })
				end)).toBe(6)
				expect(after(function()
					w.Signals.NearCatch:Fire(a, "golden")
				end)).toBe(4)
				expect(after(function()
					w.Signals.NearCatch:Fire(a, "rush")
				end)).toBe(2)
				expect(after(function()
					w.Signals.Fed:Fire(a, 3)
				end)).toBe(10)
				expect(points()).toBe(25 + 1 + 2 + 2 + 6 + 4 + 6 + 4 + 2 + 10)
				clean(w)
			end
		)

		it("objectif = 600 × max(2, N actifs) en direct ; un joueur absent ne compte pas", function()
			local w = boot()
			local players = {}
			for i = 1, 4 do
				table.insert(players, Brains.join(w, i))
			end
			Brains.frames(w, 2)
			-- personne d'actif : 600 × 2
			expect(w.Event.state().gauge.target).toBe(1200)
			local now = w.Clock.now()
			for i = 1, 3 do
				w.Activity.note(players[i], now)
			end
			Brains.frames(w, 12)
			expect(w.Event.activeCount(w.Clock.now())).toBe(3)
			expect(w.Event.state().gauge.target).toBe(1800)
			-- 2 min plus tard : plus personne d'actif
			Brains.frames(w, 1210)
			expect(w.Event.activeCount(w.Clock.now())).toBe(1)
			clean(w)
		end)

		it(
			"pleine → danse (file) → WOBBLE PARTY 5 min (×2, jauge figée) → 0 → sieste de 20 min sans fête",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				Brains.frames(w, 2)
				local boosts = {}
				local set = w.Economy.setServerBoost
				w.Economy.setServerBoost = function(kind, untilT)
					table.insert(boosts, kind)
					return set(kind, untilT)
				end
				local started = {}
				w.Signals.SpectacleStarted:Connect(function(kind)
					table.insert(started, kind)
				end)
				w.Event.addGauge(5000)
				Brains.frames(w, 2)
				expect(started[1]).toBe("dance")
				Brains.frames(w, 85)
				expect(w.Event.state().boost.kind).toBe("wobble")
				expect(boosts[#boosts]).toBe("wobble")
				-- jauge figée pendant la fête
				w.Signals.Splorched:Fire(a, 1, 0)
				Brains.frames(w, 2)
				expect(w.Event.state().gauge.partyUntil > w.Clock.now()).toBe(true)
				Bots.travelTo(w.Clock.now() + 299)
				Brains.frames(w, 20)
				local st = w.Event.state()
				expect(st.boost.kind).toBe("")
				expect(st.gauge.points).toBe(0)
				expect(st.gauge.restUntil > w.Clock.now() + 1100).toBe(true)
				-- pendant la sieste : les points comptent, aucune fête même pleine
				w.Event.addGauge(5000)
				Brains.frames(w, 20)
				expect(w.Event.state().gauge.points).toBe(w.Event.state().gauge.target)
				expect(#started).toBe(1)
				Bots.travelTo(st.gauge.restUntil + 1)
				-- la danse part dès que la file le permet (jamais pendant un Rush ou un MEGA)
				for _ = 1, 1200 do
					if started[2] then
						break
					end
					Brains.frames(w, 1)
				end
				expect(started[2]).toBe("dance")
				w.Economy.setServerBoost = set
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService › MEGA SQUISH", function()
		local function megaWorld(n)
			local w = boot({ t0 = H0 + 1180 })
			local players = {}
			for i = 1, n do
				table.insert(
					players,
					Brains.join(w, i, { profile = Brains.profile(w, { squishies = { { s = 2, z = 200 } } }) })
				)
			end
			return w, players
		end

		local function onPad(w, p, dx)
			local pad = w.WL.plaza("megaPad")
			Bots.place(p, Bots.ground(pad.X + (dx or 0), pad.Z))
		end

		it(
			"N = joueurs actifs à l'atterrissage (place pendant l'alerte comprise) ; objectif MegaRules.target(N, 0)",
			function()
				-- 130 s avant l'atterrissage : B va sur la place (son activité de déplacement expire avant
				-- l'alerte, il compte par la règle de la place) ; A a une intention acceptée ; C et D restent
				-- chez eux sans rien faire
				local w = boot({ t0 = H0 + 1200 - 130 })
				local players = {}
				for i = 1, 4 do
					table.insert(players, Brains.join(w, i))
				end
				onPad(w, players[2], 30)
				Brains.frames(w, 1000)
				w.Activity.note(players[1], w.Clock.now())
				Brains.frames(w, 310)
				local st = w.Event.state()
				expect(st.mega.phase).toBe("press")
				local MegaRules = w.h:require("ReplicatedStorage.Shared.Logic.MegaRules")
				expect(st.mega.target).toBe(MegaRules.target(2, 0))
				clean(w)
			end
		)

		it(
			"MegaPress : à plat ≤ 20 studs et pieds ≤ 8, recharge 0,4 s, hors phase refusé ; réussite : bébés, revenu, Fame, MegaJoined",
			function()
				local w, players = megaWorld(1)
				local a = players[1]
				onPad(w, a, 5)
				Brains.frames(w, 150)
				-- avant l'atterrissage : refusé
				w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
				expect(w.Event.state().mega.points).toBe(0)
				Brains.frames(w, 60)
				expect(w.Event.state().mega.phase).toBe("press")
				local joined = {}
				w.Signals.MegaJoined:Connect(function(p, pts, ok)
					table.insert(joined, { p = p, pts = pts, ok = ok })
				end)
				local fame = w.DS.get(a).fame
				local megaBabies = 0
				w.Signals.SquishyObtained:Connect(function(p, _, source)
					if p == a and source == "mega" then
						megaBabies += 1
					end
				end)
				local count0 = 0
				for _ in w.Squishy.records(a) do
					count0 += 1
				end
				-- deux appuis au même instant : le second refusé (recharge)
				w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
				w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
				local p1 = w.Event.state().mega.points
				Brains.frames(w, 1)
				expect(w.Event.state().mega.points == 1 or w.Event.state().mega.points == 3).toBe(true)
				local _ = p1
				-- presser jusqu'à l'objectif (une pression toutes les 0,5 s)
				for _ = 1, 110 do
					w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
					Brains.frames(w, 5)
				end
				Brains.frames(w, 80)
				local st = w.Event.state()
				expect(st.mega.result).toBe("success")
				expect(#joined).toBe(1)
				expect(joined[1].ok).toBe(true)
				local count1 = 0
				for _ in w.Squishy.records(a) do
					count1 += 1
				end
				expect(megaBabies).toBe(3) -- ≥ 80 points : 3 bébés
				expect(count1 - count0 >= 3).toBe(true)
				expect(w.DS.get(a).fame).toBe(fame + 1)
				local res = Bots.celebrations(a, "megaResult")
				expect(res[1].success).toBe(true)
				expect(res[1].babies).toBe(3)
				clean(w)
			end
		)

		it("à 25 studs ou pieds à 9 studs : refusé ; échec → indulgence 0,8 au MEGA suivant", function()
			local w, players = megaWorld(1)
			local a = players[1]
			Brains.frames(w, 210)
			onPad(w, a, 25)
			Brains.frames(w, 1)
			w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
			expect(w.Event.state().mega.points).toBe(0)
			local pad = w.WL.plaza("megaPad")
			Bots.place(a, w.V3.new(pad.X, 3 + 9, pad.Z))
			Brains.frames(w, 5)
			w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
			expect(w.Event.state().mega.points).toBe(0)
			Bots.travelTo(H0 + 1200 + 66)
			Brains.frames(w, 2)
			expect(w.Event.state().mega.phase).toBe("idle")
			Bots.travelTo(H0 + 1800 + 1200 + 1)
			Brains.frames(w, 2)
			local MegaRules = w.h:require("ReplicatedStorage.Shared.Logic.MegaRules")
			expect(w.Event.state().mega.target).toBe(MegaRules.target(1, 1))
			clean(w)
		end)

		it("interrupteur MegaSquish coupé : aucun MEGA", function()
			local w = boot({ t0 = H0 + 1180 })
			w.Features.set("MegaSquish", false)
			Brains.join(w, 1)
			Brains.frames(w, 300)
			expect(w.Event.state().mega.phase).toBe("idle")
			clean(w)
		end)
	end)

	-- =========================================================================================
	describe("EventService › file des spectacles", function()
		it(
			"place et attente prévue ; 20 s entre deux départs ; jamais pendant un Rush (fin + 20 s) ; annulation",
			function()
				local w = boot({ t0 = H0 + 280 })
				local players = {}
				for i = 1, 3 do
					table.insert(players, Brains.join(w, i))
				end
				Brains.frames(w, 2)
				local now = w.Clock.now()
				local s1 = w.Event.enqueueSpectacle("splorch", 1)
				local s2 = w.Event.enqueueSpectacle("splorch", 2)
				local s3 = w.Event.enqueueSpectacle("splorch", 3)
				-- Rush de :05 à :06:30 : premier départ possible avant le Rush ? non (7,5 s + 20 s d'écart) ;
				-- les trois après la fin du Rush, à 20 s d'intervalle
				local rush = w.EventClock.rush(H0 + 300)
				expect(s1 >= now).toBe(true)
				if s1 > now + 1 then
					expect(s1).toBe(rush.endsAt + 20)
				end
				expect(s2).toBe(s1 + 20)
				expect(s3).toBe(s2 + 20)
				-- même entrée si déjà en file
				expect(w.Event.enqueueSpectacle("splorch", 2)).toBe(s2)
				Brains.frames(w, 2)
				local q = w.Event.state().spectacle.queue
				expect(#q).toBe(3)
				expect(q[2].position).toBe(2)
				expect(q[2].slot).toBe(w.Ranch.slotOf(players[2]))
				expect(q[2].userId).toBe(2)
				-- annulation : les suivants avancent
				w.Event.cancelSpectacle(2)
				Brains.frames(w, 2)
				q = w.Event.state().spectacle.queue
				expect(#q).toBe(2)
				expect(q[2].userId).toBe(3)
				expect(q[2].position).toBe(2)
				clean(w)
			end
		)

		it(
			"héros parti pendant son spectacle avant l'éclatement : current effacé aussitôt et EventState renvoyé",
			function()
				local w = boot()
				-- héros vraiment prêt (plus gros au-delà de l'objectif de r = 0) : avec la progression v2.0
				-- ouverte, SplorchService rend la place d'un héros qui ne l'est pas au départ du spectacle
				-- (« SplorchNotReadyAtStart », lot A2) ; lot I, étape 2, journal I-19
				local ready =
					math.ceil(w.h:require("ReplicatedStorage.Shared.Logic.Formulas").splorchTarget(0) * 1.05)
				local a = Brains.join(
					w,
					1,
					{ profile = Brains.profile(w, { squishies = { { s = 2, z = ready } } }) }
				)
				local b = Brains.join(w, 2)
				Brains.frames(w, 2)
				-- le héros attend son Grand Splorch (squishy qui s'envole), comme après GrandSplorch
				w.Squishy.setWaiting(a, "1")
				w.Event.enqueueSpectacle("splorch", 1)
				Brains.frames(w, 2)
				expect(w.Event.state().spectacle.current ~= nil).toBe(true)
				local before = #w.h:sentTo(b, "EventState")
				Bots.leave(a)
				w.h:settle(2)
				expect(w.Event.state().spectacle.current).toBeNil()
				expect(#w.h:sentTo(b, "EventState") > before).toBe(true)
				expect(lastState(w, b).spectacle.current).toBeNil()
				clean(w)
			end
		)

		it("coupure dure : une entrée qui attend 480 s part aussitôt (filet)", function()
			local w = boot()
			Brains.join(w, 1)
			Brains.frames(w, 2)
			-- file bloquée artificiellement par un spectacle fixe sans fin (Rush forcé prolongé)
			local rushPhase = w.Event.rushPhase
			local started = {}
			w.Signals.SpectacleStarted:Connect(function(kind, userId)
				table.insert(started, userId)
			end)
			local EventClock = w.EventClock
			local rush = EventClock.rush
			EventClock.rush = function(t)
				return { active = true, index = 1, sirenAt = 0, startsAt = 0, endsAt = t + 1000 }
			end
			w.Event.enqueueSpectacle("splorch", 1)
			Brains.frames(w, 4790)
			expect(#started).toBe(0)
			Brains.frames(w, 20)
			expect(started[1]).toBe(1)
			EventClock.rush = rush
			local _ = rushPhase
			clean(w)
		end)
	end)

	-- =========================================================================================
	describe("EventService › Squish Party", function()
		it(
			"10 min ×2 ; un reçu pendant la fête la prolonge de 600 s ; partyUnplayed par acheteur ; payée avant la Wobble Party",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				local b = Brains.join(w, 2)
				Brains.frames(w, 2)
				expect(w.Event.canStartParty()).toBe(true)
				expect(w.Event.startSquishParty(a, true)).toBe(true)
				Brains.frames(w, 2)
				expect(w.Event.canStartParty()).toBe(false)
				expect(w.Event.state().boost.kind).toBe("squish")
				expect(math.abs(w.Event.partyUnplayed(1) - 600) <= 0.3).toBe(true)
				Brains.frames(w, 100)
				expect(w.Event.startSquishParty(b, false)).toBe(true)
				Brains.frames(w, 1)
				expect(math.abs(w.Event.partyUnplayed(1) - 590) <= 0.3).toBe(true)
				expect(w.Event.partyUnplayed(2)).toBe(600)
				local st = w.Event.state()
				expect(math.abs(st.boost.untilT - (w.Clock.now() + 590 + 600)) <= 0.5).toBe(true)
				-- jauge pleine pendant la fête payée : la Wobble Party attend (en pause), jamais cumulée
				w.Event.addGauge(5000)
				Brains.frames(w, 100)
				expect(w.Event.state().boost.kind).toBe("squish")
				-- fin des deux segments, puis la Wobble Party (5 min)
				Bots.travelTo(w.Clock.now() + 1200)
				Brains.frames(w, 20)
				expect(w.Event.state().boost.kind).toBe("wobble")
				expect(w.Event.partyUnplayed(1)).toBe(0)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService › Jelly Moon", function()
		local MOON = H0 + 32 * 3600 -- samedi 16:00 UTC

		it(
			"Autel : ≥ 5 min de présence → Goutte de Lune à la fin (Lunaire), moon.lastSession ; jamais deux fois par compte",
			function()
				local w = boot({ t0 = MOON - 5 })
				local a = Brains.join(w, 1)
				local b = Brains.join(w, 2)
				local altar = w.WL.plaza("altar")
				Bots.place(a, Bots.ground(altar.X, altar.Z))
				Brains.frames(w, 3200)
				Bots.use(w)
				local session = w.EventClock.moon(MOON)
				expect(session.active).toBe(true)
				Bots.travelTo(session.endsAt + 0.05)
				Brains.frames(w, 3)
				local drops = Bots.celebrations(a, "lunarDrop")
				expect(#drops).toBe(1)
				expect(drops[1].mutation).toBe(w.Mutations.LUNAR)
				expect(#Bots.celebrations(b, "lunarDrop")).toBe(0)
				local id = w.DS.get(a).moon.lastSession
				expect(id > 0).toBe(true)
				-- autre serveur, même séance : rien (profil sauvegardé avec lastSession)
				local w2 = boot({ t0 = MOON - 5 })
				local prof = Brains.profile(w2, {
					edit = function(d)
						d.moon.lastSession = id
					end,
				})
				local a2 = Brains.join(w2, 1, { profile = prof })
				Bots.place(a2, Bots.ground(altar.X, altar.Z))
				Brains.frames(w2, 3200)
				Bots.use(w2)
				Bots.travelTo(session.endsAt + 0.05)
				Brains.frames(w2, 3)
				expect(#Bots.celebrations(a2, "lunarDrop")).toBe(0)
				clean(w)
				clean(w2)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService › délais des états", function()
		it(
			"MEGA, fêtes, sieste, spectacles : aucun état ouvert au-delà de son délai sur 45 min",
			function()
				local w = boot({ t0 = H0 + 60 })
				local a = Brains.join(w, 1)
				Brains.frames(w, 2)
				w.Event.addGauge(5000)
				w.Event.startSquishParty(a, false)
				w.Event.enqueueSpectacle("splorch", 1)
				local worst = {}
				Bots.use(w)
				for _ = 1, 27000 do
					Bots.frame()
					local now = w.Clock.now()
					for _, st in w.Event.openStates() do
						if w.StateTimeouts.expired(st.name, st.startedAt, now) then
							table.insert(worst, st.name)
						end
					end
					if #worst > 0 then
						break
					end
				end
				expect(table.concat(worst, ",")).toBe("")
				clean(w)
			end
		)
	end)
end
