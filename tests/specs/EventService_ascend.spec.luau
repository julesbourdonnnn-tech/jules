--!nocheck
-- EventService_ascend (lot A4, étape 3 ; décisions D3, D4, D5, D7, D26, D27 du plan ; docs/04 §27.4, §27.5,
-- §27.6, §27.12 A4-17 et suivantes ; GDD v2.0 §2.4, §4.23, §4.27, §7.5 m9) : la Jelly Ascend dans la file
-- des grands spectacles sous sa propre sorte « ascend », ce que compte chaque prestige, la Pluie d'étoiles,
-- la bannière et la qualité des bébés au Record R.
--   * sorte « ascend » : entrée de file comme un Grand Splorch (place, ranch, attente), spectacle de 10 s
--     (éclatement à 4,0 s, coupure 12 s), 20 s d'écart gardés avant un Rush avec SA durée, un seul prestige
--     par joueur, départ du héros avant 4,0 s (spectacle effacé, aussi entre 3,2 et 4,0 s) ou après
--     (spectacle gardé), queuedStartAt et spectacleUserId ;
--   * jauge et fête : Petit Splorch + 5 / + 0 (aucun Splorched : ni stats.splorches, ni objectif du jour),
--     Grand Splorch + 25 / + 1, Jelly Ascend + 0 / + 1, MEGA réussi : fête + 3 une fois ;
--   * Pluie d'étoiles (vérification, D27) : 120 s de revenu pour chaque autre joueur, 3 par jour, rien au
--     héros ; bannière « ascend » de priorité 1 ;
--   * bébés du MEGA et de la Lune de la qualité du Record R après une Ascension ; chemin v1 identique.
-- Interrupteurs v2.0 ouverts DANS le test (Features.set) ; SchemaV2 (figé) posé dans le harnais avant le
-- premier require du schéma (recette de DataChaos).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000 -- vendredi 08:00:00 UTC (début d'heure)
	local T0 = H0 + 60 -- loin de tout Rush ou MEGA pendant ~3 min 30 s
	local L = "ReplicatedStorage.Shared."
	local R = "ReplicatedStorage.Remotes."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local FLAGS = { "RecordR", "Confetti", "JellyAscend", "PetitSplorch", "Fete" }

	-- opts : v1 (serveur v1, interrupteurs de lancement), flags (liste ouverte, défaut FLAGS), t0, stubMeta
	local function boot(opts)
		opts = opts or {}
		local w = Brains.boot(
			if opts.v1 then Harness else HarnessV2,
			{ t0 = opts.t0 or T0, stubMeta = opts.stubMeta }
		)
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		w.Notify = w.h:require("ServerScriptService.Server.Util.Notify")
		w.Babies = w.h:require("ServerScriptService.Server.Chase.Babies")
		if not opts.v1 then
			for _, key in opts.flags or FLAGS do
				assert(w.Features.set(key, true), key)
			end
		end
		w.prestiges = {}
		w.Signals.PrestigeApplied:Connect(function(p, kind, fromR, toR, A)
			table.insert(w.prestiges, { p = p, kind = kind, fromR = fromR, toR = toR, A = A })
		end)
		w.splorched = {}
		w.Signals.Splorched:Connect(function(p, r, gifts)
			table.insert(w.splorched, { p = p, r = r, gifts = gifts })
		end)
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	-- Joueur prêt pour sa 1re Jelly Ascend (r = Record R = 15) ; Meilleur Ami n° 1 = uid "1" ; `edit`
	local function veteran(w, edit)
		return Brains.profile(w, {
			coins = 5000,
			R = 15,
			squishies = {
				{ s = 1, z = 100, bf = 1 },
				{ s = 2, z = 20000 },
				{ s = 3, z = 300 },
				{ s = 4, z = 50, at = "dodo" },
			},
			tiles = { snack = 12, decor = 10 },
			edit = function(d)
				d.bestR = 15
				if edit then
					edit(d)
				end
			end,
		})
	end

	-- Après une Ascension : A = 1, Record R 15, r = R0, plus gros de taille z
	local function climber(w, R0, z, edit)
		return Brains.profile(w, {
			coins = 7000,
			R = R0,
			squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = z }, { s = 3, z = 300 } },
			tiles = { snack = 6, decor = 4 },
			edit = function(d)
				d.bestR = 15
				d.ascend = 1
				if edit then
					edit(d)
				end
			end,
		})
	end

	local function spectator(w)
		return Brains.profile(w, { squishies = { { s = 2, z = 500 }, { s = 5, z = 400 } } })
	end

	-- monde : héros (userId 1) chez lui, `n - 1` spectateurs
	local function world(opts)
		opts = opts or {}
		local w = boot(opts)
		local hero = Brains.join(w, 1, { profile = (opts.profile or veteran)(w) })
		local others = {}
		for i = 2, opts.n or 3 do
			table.insert(others, Brains.join(w, i, { profile = spectator(w) }))
		end
		Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
		Brains.frames(w, 2)
		return w, hero, others
	end

	local function ascend(w, p)
		w.h:fireServer(R .. "JellyAscend", p, true)
	end

	local function splorch(w, p, flyer)
		w.h:fireServer(R .. "GrandSplorch", p, false, flyer or "2")
	end

	local function lastState(w, p)
		local list = w.h:sentTo(p, "EventState")
		return list[#list] and list[#list][1]
	end

	-- entrées de la file (charge d'EventState construite à l'instant) de ce joueur
	local function entriesOf(w, userId)
		local out = {}
		for _, entry in w.Event.state().spectacle.queue do
			if entry.userId == userId then
				table.insert(out, entry)
			end
		end
		return out
	end

	-- images jusqu'au départ du spectacle du héros (Celebrate `kind`) ; rend sa charge (`seen` : déjà vus)
	local function untilStart(w, hero, kind, max, seen)
		for _ = 1, max or 400 do
			local shows = Bots.celebrations(hero, kind)
			if #shows > (seen or 0) then
				return shows[#shows]
			end
			Brains.frames(w, 1)
		end
		return nil
	end

	local function untilTime(w, t)
		for _ = 1, 4000 do
			if w.Clock.now() >= t then
				return
			end
			Brains.frames(w, 1)
		end
	end

	-- profil écrit dans le DataStore simulé (sans appel au magasin)
	local function saved(w, userId)
		local store = w.h.dataStores[w.Schema.STORE_NAME .. "/global"]
		local record = store and MockInstance.state(store).data["player_" .. tostring(userId)]
		return record and record.data
	end

	local function gauge(w)
		return w.Event.state().gauge.points
	end

	local function near(a, b)
		return math.abs(a - b) < 1e-6
	end

	-- =========================================================================================
	describe("EventService_ascend › sorte « ascend » dans la file", function()
		it(
			"entrée comme un Grand Splorch (sorte, place, ranch, attente), spectacle de 10 s (éclatement 4,0 s, coupure 12 s), queuedStartAt et spectacleUserId, jamais Splorched",
			function()
				local w, hero, others = world()
				-- une place d'absent devant lui (Grand Splorch de 7,5 s) : son entrée attend dans la file
				local first = w.Event.enqueueSpectacle("splorch", 900001)
				ascend(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBe("ascend")
				local mine = entriesOf(w, hero.UserId)
				expect(#mine).toBe(1)
				expect(mine[1].kind).toBe("ascend")
				expect(mine[1].position).toBe(2)
				expect(mine[1].slot).toBe(w.Ranch.slotOf(hero))
				expect(mine[1].startAt).toBe(first + w.Events.SpectacleGap)
				expect(w.Event.queuedStartAt(hero.UserId)).toBe(mine[1].startAt)
				expect(w.Splorch.queued(hero)).toBe(mine[1].startAt)
				-- la place d'attente est un état minuté « splorchQueue » (délai de la file)
				local queuedState = false
				for _, st in w.Event.openStates() do
					if st.name == "splorchQueue" and st.player == hero then
						queuedState = true
					end
				end
				expect(queuedState).toBe(true)
				-- l'entrée arrive aussi aux clients avec sa sorte
				Brains.frames(w, 1)
				local seen = false
				for _, entry in lastState(w, others[1]).spectacle.queue do
					if entry.userId == hero.UserId then
						seen = entry.kind == "ascend"
					end
				end
				expect(seen).toBe(true)
				-- départ : 20 s après le spectacle de devant
				local show = untilStart(w, hero, "ascend")
				expect(show ~= nil).toBe(true)
				expect(show.startedAt >= first + w.Events.SpectacleGap - 1e-9).toBe(true)
				local c = w.Event.state().spectacle.current
				expect(c.kind).toBe("ascend")
				expect(c.userId).toBe(hero.UserId)
				expect(near(c.burstAt - c.startedAt, w.Balance.Ascend.BurstAt)).toBe(true)
				expect(near(c.endsAt - c.startedAt, w.Events.Spectacles.ascend.duration)).toBe(true)
				expect(c.endsAt - c.startedAt <= w.Events.Spectacles.ascend.hardCut).toBe(true)
				expect(w.Event.spectacleUserId()).toBe(hero.UserId)
				expect(w.Event.queuedStartAt(hero.UserId)).toBeNil()
				Brains.frames(w, 1)
				expect(lastState(w, others[1]).spectacle.current.kind).toBe("ascend")
				-- reste du spectacle compté avec SA durée : attente prévue d'une entrée derrière lui
				w.Event.enqueueSpectacle("dance", 0)
				local q = w.Event.state().spectacle.queue
				local now = w.Clock.now()
				expect(near(q[1].eta, w.Events.SpectacleGap + (c.endsAt - now))).toBe(true)
				expect(q[1].startAt >= c.startedAt + w.Events.SpectacleGap - 1e-9).toBe(true)
				-- encore là à 9,9 s, effacé à 10 s (jamais au-delà de la coupure de 12 s)
				untilTime(w, c.startedAt + 9.85)
				expect(w.Event.state().spectacle.current ~= nil).toBe(true)
				expect(w.Event.state().spectacle.current.userId).toBe(hero.UserId)
				untilTime(w, c.startedAt + 10.05)
				local after = w.Event.state().spectacle.current
				expect(after == nil or after.userId ~= hero.UserId).toBe(true)
				expect(w.Event.spectacleUserId() ~= hero.UserId).toBe(true)
				-- appliquée à 4,0 s ; une Ascension n'émet jamais Splorched
				expect(w.DS.get(hero).ascend).toBe(1)
				expect(#w.splorched).toBe(0)
				clean(w)
			end
		)

		it(
			"20 s d'écart gardés avant un Rush avec la durée de 10 s : un Grand Splorch de 7,5 s passe encore, l'Ascension attend la fin du Rush + 20 s",
			function()
				-- Rush de :05:00 à :06:30 : un spectacle qui part à :04:31 finit à :04:41 (Ascension), trop près
				-- du Rush (20 s), ou à :04:38,5 (Grand Splorch), encore à 20 s
				local t = H0 + 271
				local wA = boot({ t0 = t })
				local rush = wA.EventClock.rush(H0 + 300)
				local startA = wA.Event.enqueueSpectacle("ascend", 900001)
				expect(startA).toBe(rush.endsAt + wA.Events.SpectacleGap)
				local started = {}
				wA.Signals.SpectacleStarted:Connect(function(kind, userId, at)
					table.insert(started, { kind = kind, userId = userId, at = at })
				end)
				Bots.use(wA)
				Bots.travelTo(rush.endsAt + 15)
				expect(#started).toBe(0)
				Brains.frames(wA, 60)
				expect(#started).toBe(1)
				expect(started[1].kind).toBe("ascend")
				expect(started[1].at >= rush.endsAt + wA.Events.SpectacleGap - 1e-9).toBe(true)
				clean(wA)
				-- même instant, Grand Splorch : tout de suite
				local wB = boot({ t0 = t })
				local startB = wB.Event.enqueueSpectacle("splorch", 900001)
				expect(startB >= t and startB < t + 1).toBe(true)
				clean(wB)
			end
		)

		it(
			"un seul prestige par joueur : une seule entrée dans la file (Grand Splorch puis Jelly Ascend, et l'inverse) ; même entrée rendue deux fois",
			function()
				-- prêt aussi pour le Grand Splorch 16 (record)
				local function both(ww)
					return veteran(ww, function(d)
						d.squishies["2"].z = 3e10
					end)
				end
				local w, hero = world({ profile = both })
				w.Event.enqueueSpectacle("splorch", 900001)
				splorch(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBe("splorch")
				w.RateLimit.clear(hero)
				ascend(w, hero)
				local keys = Bots.feedbackKeys(hero)
				expect(keys[#keys]).toBe("ascend.queued")
				local mine = entriesOf(w, hero.UserId)
				expect(#mine).toBe(1)
				expect(mine[1].kind).toBe("splorch")
				clean(w)
				-- l'inverse : Ascension en file, Grand Splorch refusé
				local w2, hero2 = world({ profile = both })
				w2.Event.enqueueSpectacle("splorch", 900001)
				ascend(w2, hero2)
				w2.RateLimit.clear(hero2)
				splorch(w2, hero2)
				local keys2 = Bots.feedbackKeys(hero2)
				expect(keys2[#keys2]).toBe("feedback.waitingSplorch")
				local mine2 = entriesOf(w2, hero2.UserId)
				expect(#mine2).toBe(1)
				expect(mine2[1].kind).toBe("ascend")
				-- EventService rend la même entrée pour la même sorte et le même joueur
				local again = w2.Event.enqueueSpectacle("ascend", hero2.UserId)
				expect(again).toBe(mine2[1].startAt)
				expect(#entriesOf(w2, hero2.UserId)).toBe(1)
				clean(w2)
			end
		)

		it(
			"départ du héros avant 4,0 s (ici 3,6 s, après l'éclatement d'un Grand Splorch) : spectacle effacé aussitôt, EventState renvoyé, rien d'appliqué",
			function()
				local w, hero, others = world()
				ascend(w, hero)
				local show = untilStart(w, hero, "ascend")
				untilTime(w, show.startedAt + 3.6)
				expect(w.Event.state().spectacle.current.kind).toBe("ascend")
				local before = #w.h:sentTo(others[1], "EventState")
				Bots.leave(hero)
				w.h:settle(2)
				expect(w.Event.state().spectacle.current).toBeNil()
				expect(w.Event.spectacleUserId()).toBe(0)
				expect(#w.h:sentTo(others[1], "EventState") > before).toBe(true)
				expect(lastState(w, others[1]).spectacle.current).toBeNil()
				Brains.frames(w, 30)
				expect(#w.prestiges).toBe(0)
				expect(#Bots.celebrations(others[1], "giftRain")).toBe(0)
				local data = saved(w, 1)
				expect(data.ascend).toBe(0)
				expect(data.R).toBe(15)
				clean(w)
			end
		)

		it(
			"départ du héros après 4,0 s : Ascension appliquée, le spectacle continue chez les autres jusqu'à 10 s",
			function()
				local w, hero, others = world()
				ascend(w, hero)
				local show = untilStart(w, hero, "ascend")
				untilTime(w, show.startedAt + 4.1)
				expect(w.DS.get(hero).ascend).toBe(1)
				Bots.leave(hero)
				w.h:settle(2)
				local c = w.Event.state().spectacle.current
				expect(c ~= nil and c.kind == "ascend" and c.userId == 1).toBe(true)
				expect(lastState(w, others[1]).spectacle.current ~= nil).toBe(true)
				untilTime(w, show.startedAt + 9.85)
				expect(w.Event.state().spectacle.current ~= nil).toBe(true)
				untilTime(w, show.startedAt + 10.05)
				expect(w.Event.state().spectacle.current).toBeNil()
				expect(saved(w, 1).ascend).toBe(1)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService_ascend › jauge et place en fête de chaque prestige", function()
		it(
			"Petit Splorch : jauge + 5, fête + 0, aucun Splorched ; stats.splorches et l'objectif du jour « Fais un Grand Splorch » inchangés",
			function()
				local w, hero = world({
					profile = function(ww)
						return climber(ww, 3, 300000, function(d)
							d.objectives = {
								day = ww.Clock.day(),
								list = { { id = 16, p = 0, done = false, claimed = false } },
							}
							d.objectives.rerolls = 0
							d.objectives.allClaimed = false
						end)
					end,
				})
				local splorches = w.DS.get(hero).stats.splorches
				local g0 = gauge(w)
				splorch(w, hero)
				-- appliqué tout de suite (hors file), mesure exacte au même instant
				expect(w.DS.get(hero).R).toBe(4)
				expect(#w.prestiges).toBe(1)
				expect(w.prestiges[1].kind).toBe("petit")
				expect(gauge(w) - g0).toBe(w.Events.Gauge.Points.petitSplorch)
				expect(gauge(w) - g0).toBe(5)
				expect(w.Event.fetePoints()).toBe(0)
				expect(#w.splorched).toBe(0)
				Brains.frames(w, 5)
				local data = w.DS.get(hero)
				expect(data.stats.splorches).toBe(splorches)
				expect(data.objectives.list[1].p).toBe(0)
				expect(data.objectives.list[1].done).toBe(false)
				clean(w)
			end
		)

		it(
			"Grand Splorch v2.0 : jauge + 25, fête + 1, stats.splorches + 1 et l'objectif du jour fait ; Jelly Ascend : jauge + 0, fête + 1",
			function()
				local w, hero = world({
					profile = function(ww)
						return veteran(ww, function(d)
							d.squishies["2"].z = 3e10
							d.objectives = {
								day = ww.Clock.day(),
								list = { { id = 16, p = 0, done = false, claimed = false } },
							}
							d.objectives.rerolls = 0
							d.objectives.allClaimed = false
						end)
					end,
				})
				-- mesures au même instant : avant (Confettis versés, juste avant PrestigeApplied) et après
				-- (PrestigeApplied et Splorched, gestionnaires du spec branchés APRÈS ceux d'EventService)
				local marks = {}
				w.Signals.ConfettiChanged:Connect(function(p, delta, source)
					if p == hero and delta > 0 and marks[source] == nil then
						marks[source] = { gauge = gauge(w), fete = w.Event.fetePoints() }
					end
				end)
				local atPrestige = {}
				w.Signals.PrestigeApplied:Connect(function(p, kind)
					if p == hero then
						atPrestige[kind] = { gauge = gauge(w), fete = w.Event.fetePoints() }
					end
				end)
				local atSplorched = nil
				w.Signals.Splorched:Connect(function(p)
					if p == hero then
						atSplorched = { gauge = gauge(w), fete = w.Event.fetePoints() }
					end
				end)
				local splorches = w.DS.get(hero).stats.splorches
				splorch(w, hero)
				local show = untilStart(w, hero, "splorch")
				untilTime(w, show.startedAt + 3.4)
				expect(w.DS.get(hero).R).toBe(16)
				expect(atPrestige.splorch ~= nil and atSplorched ~= nil).toBe(true)
				-- PrestigeApplied(« splorch ») ne compte rien ; Splorched : + 25 et + 1
				expect(atPrestige.splorch.gauge).toBe(marks.splorch.gauge)
				expect(atPrestige.splorch.fete).toBe(marks.splorch.fete)
				expect(atSplorched.gauge - atPrestige.splorch.gauge).toBe(25)
				expect(atSplorched.fete - atPrestige.splorch.fete).toBe(1)
				expect(w.Event.fetePoints()).toBe(1)
				Brains.frames(w, 2)
				local data = w.DS.get(hero)
				expect(data.stats.splorches).toBe(splorches + 1)
				expect(data.objectives.list[1].p).toBe(1)
				expect(data.objectives.list[1].done).toBe(true)
				-- puis sa Jelly Ascend (r = 16 ≥ 15, prête) : jauge + 0, fête + 1
				untilTime(w, show.startedAt + 8)
				w.RateLimit.clear(hero)
				ascend(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBe("ascend")
				local a = untilStart(w, hero, "ascend", 600)
				untilTime(w, a.startedAt + 4.1)
				expect(w.DS.get(hero).ascend).toBe(1)
				expect(atPrestige.ascend ~= nil and marks.ascend ~= nil).toBe(true)
				expect(atPrestige.ascend.gauge).toBe(marks.ascend.gauge)
				expect(atPrestige.ascend.fete - marks.ascend.fete).toBe(1)
				expect(w.Event.fetePoints()).toBe(2)
				expect(#w.splorched).toBe(1)
				clean(w)
			end
		)

		it(
			"signaux seuls : PrestigeApplied « petit » + 5, « ascend » 0, « splorch » 0 ; Splorched + 25",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				Brains.frames(w, 2)
				local function delta(fn)
					local g, f = gauge(w), w.Event.fetePoints()
					fn()
					return gauge(w) - g, w.Event.fetePoints() - f
				end
				local g, f = delta(function()
					w.Signals.PrestigeApplied:Fire(a, "petit", 3, 4, 1)
				end)
				expect({ g, f }).toEqual({ 5, 0 })
				g, f = delta(function()
					w.Signals.PrestigeApplied:Fire(a, "ascend", 15, 3, 1)
				end)
				expect({ g, f }).toEqual({ 0, 1 })
				g, f = delta(function()
					w.Signals.PrestigeApplied:Fire(a, "splorch", 15, 16, 0)
				end)
				expect({ g, f }).toEqual({ 0, 0 })
				g, f = delta(function()
					w.Signals.Splorched:Fire(a, 16, 0)
				end)
				expect({ g, f }).toEqual({ 25, 1 })
				-- Fete coupé : aucun point de fête (la jauge compte toujours)
				w.Features.set("Fete", false)
				g, f = delta(function()
					w.Signals.Splorched:Fire(a, 17, 0)
				end)
				expect({ g, f }).toEqual({ 25, 0 })
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService_ascend › Pluie d'étoiles et bannière", function()
		it(
			"Pluie d'étoiles : chaque autre joueur reçoit 120 s de revenu, 3 par jour ; le héros rien de sa propre Ascension",
			function()
				local w = boot()
				local heroes = {}
				for i = 1, 4 do
					local p = Brains.join(w, i, { profile = veteran(w) })
					table.insert(heroes, p)
				end
				local watcher = Brains.join(w, 5, { profile = spectator(w) })
				for _, p in heroes do
					Bots.place(p, Brains.atRanch(w, p, 0, 30))
				end
				Brains.frames(w, 2)
				local rains = {} -- [userId] = { seconds… }
				local addIncomeSeconds = w.Economy.addIncomeSeconds
				w.Economy.addIncomeSeconds = function(p, seconds, sku, ...)
					if sku == "StarRain" then
						rains[p.UserId] = rains[p.UserId] or {}
						table.insert(rains[p.UserId], seconds)
					end
					return addIncomeSeconds(p, seconds, sku, ...)
				end
				local showsByHero = {}
				w.Signals.SpectacleStarted:Connect(function(kind, userId)
					if kind == "ascend" then
						showsByHero[userId] = (showsByHero[userId] or 0) + 1
					end
				end)
				for _, p in heroes do
					ascend(w, p)
					expect(w.Splorch.queuedKind(p)).toBe("ascend")
				end
				-- 4 Ascensions à 20 s d'écart (avant le Rush de :05)
				Brains.frames(w, 4 * 200)
				for _, p in heroes do
					expect(w.DS.get(p).ascend).toBe(1)
					expect(showsByHero[p.UserId]).toBe(1)
				end
				-- chaque héros : 3 pluies (celles des 3 autres), jamais la sienne
				for _, p in heroes do
					expect(#(rains[p.UserId] or {})).toBe(3)
					for _, seconds in rains[p.UserId] do
						expect(seconds).toBe(w.Balance.Ascend.StarRainSeconds)
					end
					for _, celebration in Bots.celebrations(p, "giftRain") do
						expect(celebration.heroId ~= p.UserId).toBe(true)
					end
				end
				-- le spectateur : 4 Ascensions vues, 3 pluies payées (plafond du jour)
				expect(#rains[watcher.UserId]).toBe(w.Balance.CapsV2.starRain)
				expect(w.Balance.CapsV2.starRain).toBe(3)
				expect(w.DS.get(watcher).caps.starRain).toBe(3)
				expect(w.Balance.Ascend.StarRainSeconds).toBe(120)
				w.Economy.addIncomeSeconds = addIncomeSeconds
				clean(w)
			end
		)

		it(
			"bannière « ascend » : priorité 1 (Events.Banners.PriorityV2) ; passe avant une bannière de priorité 4 demandée avant elle",
			function()
				local w = boot({ stubMeta = false })
				local a = Brains.join(w, 1, { profile = veteran(w) })
				local b = Brains.join(w, 2, { profile = spectator(w) })
				Brains.frames(w, 2)
				expect(w.Notify.BANNER_PRIORITY.ascend).toBe(1)
				expect(w.Notify.BANNER_PRIORITY.ascend).toBe(w.Events.Banners.PriorityV2.ascend)
				local before = #w.h:sentTo(b, "Banner")
				w.Notify.banner("legendHatch", { userId = 2, name = "B", species = 3 }, b)
				w.Notify.banner("ascend", { ascend = 1 }, a)
				local sent = w.h:sentTo(b, "Banner")
				for _ = 1, 60 do
					Brains.frames(w, 1)
					sent = w.h:sentTo(b, "Banner")
					if #sent > before then
						break
					end
				end
				expect(#sent > before).toBe(true)
				local first = sent[before + 1][1]
				expect(first.kind).toBe("ascend")
				expect(first.priority).toBe(1)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService_ascend › bébés au Record R (N1)", function()
		local function onPad(w, p, dx)
			local pad = w.WL.plaza("megaPad")
			Bots.place(p, Bots.ground(pad.X + (dx or 0), pad.Z))
		end

		-- MEGA réussi par un seul joueur ; rend la liste des R reçus par Babies.mega
		local function megaRun(w, p)
			local seen = {}
			local mega = w.Babies.mega
			w.Babies.mega = function(rng, R0, ...)
				table.insert(seen, R0)
				return mega(rng, R0, ...)
			end
			onPad(w, p, 5)
			Brains.frames(w, 210)
			expect(w.Event.state().mega.phase).toBe("press")
			for _ = 1, 110 do
				w.h:fireServer(R .. "MegaPress", p, w.Clock.now())
				Brains.frames(w, 5)
			end
			Brains.frames(w, 80)
			expect(w.Event.state().mega.result).toBe("success")
			w.Babies.mega = mega
			return seen
		end

		it(
			"MEGA réussi après une Ascension : bébés de la qualité du Record R (15, pas r = 3) ; fête + 3 une fois par MEGA ; profil v1 : R",
			function()
				local w = boot({ t0 = H0 + 1180 })
				local p = Brains.join(w, 1, { profile = climber(w, 3, 200) })
				Brains.frames(w, 2)
				local seen = megaRun(w, p)
				expect(#seen).toBe(3)
				for _, value in seen do
					expect(value).toBe(15)
				end
				expect(w.Event.fetePoints()).toBe(w.Events.Fete.Points.mega)
				expect(w.Event.fetePoints()).toBe(3)
				clean(w)
				-- serveur v1 (interrupteurs de lancement) : R du profil, comme avant
				local w1 = boot({ v1 = true, t0 = H0 + 1180 })
				local p1 = Brains.join(
					w1,
					1,
					{ profile = Brains.profile(w1, { R = 3, squishies = { { s = 2, z = 200 } } }) }
				)
				Brains.frames(w1, 2)
				local seen1 = megaRun(w1, p1)
				expect(#seen1).toBe(3)
				for _, value in seen1 do
					expect(value).toBe(3)
				end
				expect(w1.Event.fetePoints()).toBe(0)
				expect(w1.Event.state().fete).toBeNil()
				clean(w1)
			end
		)

		it("Goutte de Lune après une Ascension : bébé Lunaire de la qualité du Record R", function()
			local MOON = H0 + 32 * 3600 -- samedi 16:00 UTC
			local w = boot({ t0 = MOON - 5 })
			local p = Brains.join(w, 1, { profile = climber(w, 3, 200) })
			local seen = {}
			local lunar = w.Babies.lunar
			w.Babies.lunar = function(rng, R0, ...)
				table.insert(seen, R0)
				return lunar(rng, R0, ...)
			end
			local altar = w.WL.plaza("altar")
			Bots.place(p, Bots.ground(altar.X, altar.Z))
			Brains.frames(w, 3200)
			Bots.use(w)
			Bots.travelTo(w.EventClock.moon(MOON).endsAt + 0.05)
			Brains.frames(w, 3)
			expect(#Bots.celebrations(p, "lunarDrop")).toBe(1)
			expect(seen).toEqual({ 15 })
			w.Babies.lunar = lunar
			clean(w)
		end)
	end)

	-- =========================================================================================
	describe("EventService_ascend › chemin v1 identique", function()
		it(
			"serveur v1 : Grand Splorch « splorch » (7,5 s, éclatement 3,2 s), Splorched + 25 à la jauge, aucune Ascension en file, EventState sans clé v2.0",
			function()
				local w = boot({ v1 = true })
				local hero = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						coins = 5000,
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 20000 }, { s = 3, z = 300 } },
					}),
				})
				local other = Brains.join(w, 2, { profile = spectator(w) })
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				ascend(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBeNil()
				expect(#w.Event.state().spectacle.queue).toBe(0)
				-- jauge au départ du spectacle ; autres faits qui comptent à la jauge pendant la mesure
				local g0 = nil
				local others = 0
				w.Signals.SpectacleStarted:Connect(function()
					g0 = gauge(w)
					others = 0
				end)
				for _, name in { "Pressed", "Hatched", "Fused", "Caught", "NearCatch", "Fed" } do
					w.Signals[name]:Connect(function()
						others += 1
					end)
				end
				splorch(w, hero)
				local show = untilStart(w, hero, "splorch")
				local c = w.Event.state().spectacle.current
				expect(c.kind).toBe("splorch")
				expect(near(c.burstAt - c.startedAt, w.Balance.Splorch.BurstAt)).toBe(true)
				expect(near(c.endsAt - c.startedAt, w.Events.Spectacles.splorch.duration)).toBe(true)
				untilTime(w, show.startedAt + 3.4)
				expect(w.DS.get(hero).R).toBe(1)
				expect(#w.splorched).toBe(1)
				expect(#w.prestiges).toBe(0)
				-- + 25 depuis le départ (aucun autre fait de jauge pendant ces 3,4 s)
				expect(others).toBe(0)
				expect(gauge(w) - g0).toBe(25)
				expect(w.Event.fetePoints()).toBe(0)
				Brains.frames(w, 2)
				local st = lastState(w, other)
				local keys = {}
				for k in st do
					table.insert(keys, k)
				end
				table.sort(keys)
				expect(table.concat(keys, ",")).toBe(
					"boost,features,gauge,golden,mega,moon,offset,rush,spectacle"
				)
				clean(w)
			end
		)
	end)
end
