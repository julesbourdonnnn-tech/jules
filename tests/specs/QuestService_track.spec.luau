--!nocheck
-- QuestService v2.0 (lot A4, étape 4 ; GDD v2.0 §7.5, §4.27, §4.29 ; docs/04 §27.2, §27.7 ; décisions
-- D7, D9-D12, D14, D15, D32-D35 du plan du lot A4) : statistiques à vie, jeu des 7 derniers jours, piste
-- de la semaine (2 points par objectif terminé, 5 par Défi, paliers livrés tout seuls dans l'ordre,
-- réclamés après leur récompense), Défis de Splorch (faisables, jamais deux fois, déterministes), Carnet du
-- Ranch, cartes « Bienvenue dans la v2 ! » et « Nouveau », tenues du Record R, étapes du record, jours de
-- givre, puce « Prochain achat », N1 (Record R) ; interrupteurs coupés : profil et envois d'aujourd'hui.
-- Interrupteurs ouverts DANS le test (Features.set) ; SchemaV2 (figé) dans le harnais avant le premier
-- require du schéma (recette de DataChaos). Zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- vendredi 15 janvier 2027, 08:01 UTC (semaine 2975 du lundi 11 janvier)
	local T0 = 1800000000 + 60
	local DAY = 86400
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."
	local R = "ReplicatedStorage.Remotes."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- opts : v1 (serveur v1 : profils v1), flags (interrupteurs ouverts), t0
	local function boot(opts)
		opts = opts or {}
		local w =
			Brains.boot(if opts.v1 then Harness else HarnessV2, { t0 = opts.t0 or T0, stubMeta = false })
		w.Q = w.h:require(S .. "QuestService")
		w.QR = w.h:require(L .. "Logic.QuestRules")
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.Bitset = w.h:require(L .. "Logic.Bitset")
		w.Quests = w.h:require(L .. "Config.Quests")
		w.Cosmetics = w.h:require(L .. "Config.Cosmetics")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		for _, key in opts.flags or {} do
			assert(w.Features.set(key, true), key)
		end
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	-- joueur prêt (profil v2 du serveur v2, ou v1 du serveur v1) ; edit(d) avant la sauvegarde
	local function join(w, id, edit, squishies)
		return Brains.join(w, id, {
			profile = Brains.profile(w, {
				squishies = squishies or { { s = 1, z = 100, bf = 1 }, { s = 2, z = 50 } },
				edit = edit,
			}),
		})
	end

	local function data(w, p)
		return w.DS.get(p)
	end

	local function cards(p, kind)
		return Bots.celebrations(p, kind)
	end

	-- intention envoyée (seau à jetons vidé : la règle du serveur seule décide)
	local function fire(w, name, p, ...)
		w.RateLimit.clear(p)
		w.h:fireServer(R .. name, p, ...)
		w.h:settle(1)
	end

	-- cartes de la v2.0 envoyées par QuestService (étape 4)
	local V2_CARDS = { "trackTier", "carnet", "welcomeV2", "unlock2", "recordStep" }
	local function v2Cards(p)
		local n = 0
		for _, kind in V2_CARDS do
			n += #cards(p, kind)
		end
		return n
	end

	local function catchInfo(kind)
		return {
			kind = kind or "runaway",
			species = 2,
			rarity = 1,
			mutation = 0,
			ownerId = 0,
			hero = false,
			byLeap = false,
			babyUid = "",
		}
	end

	local function entry(id, p, done)
		return { id = id, p = p or 0, done = done == true, claimed = false }
	end

	-- objectifs du jour posés (jour d'aujourd'hui : rien de tiré à la connexion)
	local function objectives(w, list)
		return { day = w.Clock.day(), list = list, rerolls = 0, allClaimed = false }
	end

	-- piste de la période en cours (1re période finie : aucune remise à zéro à la connexion)
	local function trackAt(w, opts)
		opts = opts or {}
		local week = w.QR.weekIndex(w.Clock.now())
		return {
			period = week,
			points = opts.points or 0,
			claimed = opts.claimed or w.Bitset.new(12),
			challenges = opts.challenges or {
				{ id = 3, p = 0, done = false },
				{ id = 6, p = 0, done = false },
				{ id = 12, p = 0, done = false },
			},
			firstPeriodEnd = w.QR.weekStart(week),
			won = opts.won or w.Bitset.new(8),
			play = table.create(7, 0),
			playDay = 0,
		}
	end

	-- fait le Défi `id` par ses signaux (comme le jeu les émet)
	local function doChallenge(w, p, id)
		local def = w.Quests.Challenges[id]
		local S = w.Signals
		local n = def.target
		if def.stat == "splorches" then
			for _ = 1, n do
				S.Splorched:Fire(p, 1, 0)
			end
		elseif def.stat == "confettiEarned" then
			S.ConfettiChanged:Fire(p, n, "splorch")
		elseif def.stat == "upgradesBought" then
			S.UpgradeBought:Fire(p, "gloves", 0, n, "coins")
		elseif def.stat == "recordBeaten" then
			S.RecordReached:Fire(p, 1)
		elseif def.stat == "ascends" then
			S.PrestigeApplied:Fire(p, "ascend", 15, 0, 1)
		elseif def.stat == "combo3" then
			S.Fused:Fire(p, "1", 3)
		elseif def.stat == "rareHatches" then
			for _ = 1, n do
				S.Hatched:Fire(p, "1", 3)
			end
		elseif def.stat == "newStamps" then
			S.Stamped:Fire(p, n)
		elseif def.stat == "megas" then
			for _ = 1, n do
				S.MegaJoined:Fire(p, 50, true)
			end
		elseif def.stat == "feedDays" then
			for i = 1, n do
				S.Fed:Fire(p, i)
			end
		elseif def.stat == "catches" then
			for _ = 1, n do
				S.Caught:Fire(p, catchInfo("runaway"))
			end
		elseif def.stat == "perfects" then
			for i = 1, n do
				S.Pressed:Fire(p, { uid = "1", perfect = true, streak = i })
			end
		end
	end

	local function press(w, p, n, perfect)
		for i = 1, n do
			w.Signals.Pressed:Fire(p, { uid = "1", perfect = perfect == true, streak = i })
		end
	end

	-- taille du plus gros squishy d'enclos portée à `share` de l'objectif de la boucle (données du test)
	local function setShare(w, p, share)
		local d = data(w, p)
		local target = w.Prestige.target(w.Prestige.r(d))
		local uid, size = w.Squishy.biggest(p)
		local rec = d.squishies[uid]
		rec.z += share * target - size
	end

	-- liste triée et aplatie (comparaison de deux parties)
	local function ser(v)
		if type(v) == "table" then
			local keys = {}
			for k in v do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			local parts = {}
			for _, k in keys do
				table.insert(parts, tostring(k) .. "=" .. ser(v[k]))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return tostring(v)
	end

	describe("QuestService v2.0 › objectifs du jour et Record R (N1)", function()
		it(
			"remontée après une Ascension : jamais « Fais un Grand Splorch » (un Petit Splorch ne compte pas) ; combo ×2 et Rare suivent le Record R",
			function()
				local w = boot()
				local today = w.Clock.day()
				-- un joueur à qui l'ancien contexte (R = r = 0, Grand Splorch « tout de suite » : le plus gros a
				-- atteint l'objectif de la boucle) donnait l'objectif 16 en relançant la case difficile
				local old = {
					R = 0,
					tilesLeft = 0,
					megaIn = math.huge,
					friendOnServer = false,
					splorchEta = 0,
					stamps = 0,
				}
				local id
				for u = 1, 300 do
					if w.QR.reroll(u, today, { 1, 8, 17 }, 3, old, 1) == 16 then
						id = u
						break
					end
				end
				expect(id ~= nil).toBe(true)
				local p = join(w, id, function(d)
					d.R = 0
					d.bestR = 15
					d.ascend = 1
					d.objectives = {
						day = today,
						list = {
							{ id = 1, p = 0, done = false, claimed = false },
							{ id = 8, p = 0, done = false, claimed = false },
							{ id = 17, p = 0, done = false, claimed = false },
						},
						rerolls = 0,
						allClaimed = false,
					}
				end, { { s = 1, z = 100, bf = 1 }, { s = 2, z = 20000 } })
				expect(w.Prestige.nextKind(data(w, p))).toBe("petit")
				w.RateLimit.clear(p)
				w.h:fireServer(R .. "RerollObjective", p, 3)
				w.h:settle(1)
				local o = data(w, p).objectives
				expect(o.rerolls).toBe(1)
				-- difficile : 14 (combo ×2, Record R ≥ 1), 15 (Rare, Record R ≥ 3) ou 18 ; jamais 16
				local hard = o.list[3].id
				expect({ hard = hard, ok = hard == 14 or hard == 15 or hard == 18 }).toEqual({
					hard = hard,
					ok = true,
				})
				clean(w)
			end
		)
	end)

	describe("QuestService v2.0 › statistiques à vie (D34)", function()
		it(
			"stats.upgradesBought += to − from (× 10 compris), profil v2 seulement ; un profil v1 qui achète par BuyTile (v1.3) reste intact",
			function()
				local w = boot()
				local p = join(w, 1, function(d)
					d.coins = 1e12
				end)
				local d = data(w, p)
				expect(d.stats.upgradesBought).toBe(0)
				local snack = d.tiles.snack
				fire(w, "BuyTile", p, "snack")
				expect(d.tiles.snack).toBe(snack + 1)
				expect(d.stats.upgradesBought).toBe(1)
				w.Signals.UpgradeBought:Fire(p, "gloves", 3, 13, "coins")
				expect(d.stats.upgradesBought).toBe(11)
				-- signaux illisibles : rien
				w.Signals.UpgradeBought:Fire(p, "gloves", 13, 13, "coins")
				w.Signals.UpgradeBought:Fire(p, "gloves", 0 / 0, 5, "coins")
				w.Signals.UpgradeBought:Fire(p, "gloves", 5, math.huge, "coins")
				expect(d.stats.upgradesBought).toBe(11)
				clean(w)

				local v1 = boot({ v1 = true })
				local q = join(v1, 1, function(e)
					e.coins = 1e12
				end)
				local e = data(v1, q)
				expect(e.version).toBe(1)
				local before = e.tiles.snack
				fire(v1, "BuyTile", q, "snack")
				expect(e.tiles.snack).toBe(before + 1)
				expect(e.stats.upgradesBought).toBe(nil)
				expect(e.carnet).toBe(nil)
				expect(e.weeklyTrack).toBe(nil)
				clean(v1)
			end
		)

		it(
			"un Petit Splorch ne compte que dans stats.petitSplorches (ni stats.splorches, ni l'objectif « Fais un Grand Splorch », ni le Défi 1)",
			function()
				local w = boot({ flags = { "WeeklyTrack" } })
				local p = join(w, 1, function(d)
					d.objectives = objectives(w, { entry(1), entry(8), entry(16) })
					d.weeklyTrack = trackAt(w, { challenges = { { id = 1, p = 0, done = false } } })
				end)
				local d = data(w, p)
				local splorches = d.stats.splorches
				w.Signals.PrestigeApplied:Fire(p, "petit", 4, 5, 1)
				expect(d.stats.petitSplorches).toBe(1)
				expect(d.stats.splorches).toBe(splorches)
				expect(d.objectives.list[3].p).toBe(0)
				expect(d.weeklyTrack.challenges[1].p).toBe(0)
				-- un Grand Splorch (Splorched) compte partout
				w.Signals.Splorched:Fire(p, 6, 0)
				expect(d.stats.petitSplorches).toBe(1)
				expect(d.stats.splorches).toBe(splorches + 1)
				expect(d.objectives.list[3].done).toBe(true)
				expect(d.weeklyTrack.challenges[1].p).toBe(1)
				clean(w)
			end
		)

		it(
			"objectifs réclamés à vie : à la main, à minuit, à la connexion (dans l'instantané)",
			function()
				local w = boot()
				local p = join(w, 1, function(d)
					d.objectives = objectives(w, { entry(1, 30, true), entry(8, 5, true), entry(9, 0) })
				end)
				local d = data(w, p)
				expect(d.stats.objectivesClaimed).toBe(0)
				fire(w, "ClaimObjective", p, 1)
				expect(d.stats.objectivesClaimed).toBe(1)
				-- minuit en session : le terminé est réclamé tout seul, l'objectif en cours est gardé
				w.Clock.advance(w.Clock.untilNextDay() + 1)
				Brains.frames(w, 1)
				expect(d.stats.objectivesClaimed).toBe(2)
				expect(#d.objectives.list).toBe(1)
				press(w, p, 5, true)
				expect(d.objectives.list[1].done).toBe(true)
				-- départ, retour : le terminé du jour passé est réclamé à la connexion
				Bots.leave(p)
				w.h:settle(5)
				local q = Brains.join(w, 1)
				local snap = w.h:sentTo(q, "DataSnapshot")
				expect(snap[#snap][1].stats.objectivesClaimed).toBe(3)
				expect(data(w, q).stats.objectivesClaimed).toBe(3)
				clean(w)
			end
		)
	end)

	describe("QuestService v2.0 › piste de la semaine [WeeklyTrack]", function()
		it(
			"première période : de la 1re connexion au 2e lundi (8 à 14 jours), 24 points possibles (27 au joueur du week-end) ; 3 Défis distincts",
			function()
				local monday = 345600 + 2975 * 604800 -- lundi 11 janvier 2027 00:00 UTC
				for _, t in { T0, monday, monday + 7 * DAY - 1 } do
					local w = boot({ t0 = t, flags = { "WeeklyTrack" } })
					local p = join(w, 1)
					local track = data(w, p).weeklyTrack
					local fpe = track.firstPeriodEnd
					expect({ t = t, monday = (fpe - 345600) % 604800 }).toEqual({ t = t, monday = 0 })
					local days = (fpe - t) / DAY
					expect({ t = t, ok = days > 7 and days <= 14 }).toEqual({ t = t, ok = true })
					expect(track.period).toBe(w.QR.weekIndex(fpe) - 1)
					expect(track.points).toBe(0)
					expect(#track.challenges).toBe(3)
					local ids = {}
					for _, c in track.challenges do
						expect(ids[c.id]).toBe(nil)
						ids[c.id] = true
						expect(c.p).toBe(0)
						expect(c.done).toBe(false)
					end
					-- 24 points toujours possibles, aussi au joueur du week-end
					expect(w.QR.trackMaxPoints(t, fpe) >= 24).toBe(true)
					expect(w.QR.trackMaxPoints(t, fpe, { [5] = true, [6] = true }) >= 24).toBe(true)
					clean(w)
				end
				local w = boot()
				local week = w.QR.weekIndex(T0)
				expect(
					w.QR.trackMaxPoints(
						w.QR.weekStart(week),
						w.QR.weekStart(week + 1),
						{ [5] = true, [6] = true }
					)
				).toBe(27)
				clean(w)
			end
		)

		it(
			"2 points par objectif terminé (6 par jour au plus) ; paliers livrés tout seuls dans l'ordre, Confettis par addConfetti « track »",
			function()
				local w = boot({ flags = { "WeeklyTrack", "Confetti" } })
				local p = join(w, 1, function(d)
					d.objectives = objectives(w, { entry(1), entry(3), entry(7) })
					d.weeklyTrack = trackAt(w)
				end)
				local d = data(w, p)
				local earned = {}
				w.Signals.ConfettiChanged:Connect(function(_, delta, source)
					table.insert(earned, source .. ":" .. delta)
				end)
				press(w, p, 30)
				expect(d.weeklyTrack.points).toBe(2)
				expect(d.confetti).toBe(2)
				w.Signals.Caught:Fire(p, catchInfo("runaway"))
				w.Signals.Caught:Fire(p, catchInfo("escape"))
				expect(d.weeklyTrack.points).toBe(4)
				w.Signals.Fused:Fire(p, "1", 1)
				w.Signals.Fused:Fire(p, "1", 1)
				expect(d.weeklyTrack.points).toBe(6)
				-- plus rien : les 3 objectifs du jour sont terminés
				press(w, p, 40)
				w.Signals.Fused:Fire(p, "1", 1)
				expect(d.weeklyTrack.points).toBe(6)
				expect(d.confetti).toBe(2 + 2 + 3)
				expect(earned).toEqual({ "track:2", "track:2", "track:3" })
				local tiers = cards(p, "trackTier")
				expect(tiers).toEqual({
					{ tier = 1, reward = "confetti" },
					{ tier = 2, reward = "confetti" },
					{ tier = 3, reward = "confetti" },
				})
				for i = 1, 12 do
					expect({ i = i, claimed = w.Bitset.has(d.weeklyTrack.claimed, i) }).toEqual({
						i = i,
						claimed = i <= 3,
					})
				end
				clean(w)
			end
		)

		it(
			"5 points par Défi terminé (une fois), aux points de la période où il a été tiré",
			function()
				local w = boot({ flags = { "WeeklyTrack", "Confetti" } })
				local p = join(w, 1)
				local d = data(w, p)
				local first = d.weeklyTrack.challenges[1]
				doChallenge(w, p, first.id)
				expect(first.done).toBe(true)
				expect(first.p).toBe(w.Quests.Challenges[first.id].target)
				expect(d.weeklyTrack.points).toBe(5)
				doChallenge(w, p, first.id)
				expect(first.p).toBe(w.Quests.Challenges[first.id].target)
				expect(d.weeklyTrack.points).toBe(5)
				expect(#cards(p, "trackTier")).toBe(2)
				for i = 2, 3 do
					doChallenge(w, p, d.weeklyTrack.challenges[i].id)
				end
				expect(d.weeklyTrack.points).toBe(15)
				expect(#cards(p, "trackTier")).toBe(7)
				clean(w)
			end
		)

		it(
			"paliers 1 à 12 dans l'ordre : Gouttes chanceuses (4, 8), cosmétique de la semaine (période % 8 + 1, bit won), nœud à pois dans la garde-robe ; déjà gagné : rien de plus",
			function()
				-- semaine 2979 (2979 % 8 + 1 = 4 : nœud à pois), vendredi 12 février 2027 08:00 UTC
				local t = 345600 + 2979 * 604800 + 4 * DAY + 8 * 3600
				local w = boot({ t0 = t, flags = { "WeeklyTrack", "Confetti" } })
				expect(w.Cosmetics.WeeklyRotation[2979 % 8 + 1].id).toBe("polkaBow")
				local p = join(w, 1, function(d)
					d.objectives = objectives(w, { entry(1), entry(3), entry(7) })
					d.weeklyTrack = trackAt(w, { points = 22 })
				end)
				local d = data(w, p)
				-- à la connexion : les paliers 1 à 11 attendaient, livrés dans l'ordre
				local tiers = cards(p, "trackTier")
				expect(#tiers).toBe(11)
				for i, c in tiers do
					local reward = w.Quests.WeeklyTrack.Tiers[i]
					expect(c).toEqual({
						tier = i,
						reward = if type(reward) == "number" then "confetti" else reward,
					})
				end
				expect(d.confetti).toBe(2 + 2 + 3 + 3 + 4 + 4 + 5 + 5 + 6)
				expect(#cards(p, "luckyDrop")).toBe(2)
				expect(w.Bitset.has(d.weeklyTrack.claimed, 12)).toBe(false)
				-- 2 points de plus : palier 12, le cosmétique de la semaine
				press(w, p, 30)
				expect(d.weeklyTrack.points).toBe(24)
				tiers = cards(p, "trackTier")
				expect(tiers[12]).toEqual({ tier = 12, reward = "outfit.polkaBow" })
				expect(w.Bitset.has(d.weeklyTrack.won, 4)).toBe(true)
				expect(w.Bitset.count(d.weeklyTrack.won)).toBe(1)
				expect(d.outfits.owned.polkaBow).toBe(1)
				expect(d.stats.tracksDone).toBe(1)
				expect(d.confetti).toBe(34)
				clean(w)

				-- même cosmétique déjà gagné (8 semaines plus tôt) : le palier 12 est livré sans rien de plus
				local w2 = boot({ t0 = t, flags = { "WeeklyTrack", "Confetti" } })
				local claimed = w2.Bitset.new(12)
				for i = 1, 11 do
					w2.Bitset.set(claimed, i)
				end
				local won = w2.Bitset.new(8)
				w2.Bitset.set(won, 4)
				local q = join(w2, 2, function(e)
					e.weeklyTrack = trackAt(w2, { points = 24, claimed = claimed, won = won })
				end)
				local e = data(w2, q)
				expect(cards(q, "trackTier")).toEqual({ { tier = 12, reward = "" } })
				expect(e.outfits.owned.polkaBow or 0).toBe(0)
				expect(e.stats.tracksDone).toBe(1)
				expect(e.confetti).toBe(0)
				clean(w2)
			end
		)

		it(
			"un palier attend tant que les Confettis sont coupés, puis il est livré (dans l'ordre)",
			function()
				local w = boot({ flags = { "WeeklyTrack" } })
				local p = join(w, 1, function(d)
					d.weeklyTrack = trackAt(w, { points = 8 })
				end)
				local d = data(w, p)
				expect(#cards(p, "trackTier")).toBe(0)
				for i = 1, 4 do
					expect(w.Bitset.has(d.weeklyTrack.claimed, i)).toBe(false)
				end
				Brains.frames(w, 120)
				expect(#cards(p, "trackTier")).toBe(0)
				assert(w.Features.set("Confetti", true))
				Brains.frames(w, 120)
				local tiers = cards(p, "trackTier")
				expect(tiers).toEqual({
					{ tier = 1, reward = "confetti" },
					{ tier = 2, reward = "confetti" },
					{ tier = 3, reward = "confetti" },
					{ tier = 4, reward = "drop" },
				})
				expect(d.confetti).toBe(7)
				Brains.frames(w, 120)
				expect(#cards(p, "trackTier")).toBe(4)
				clean(w)
			end
		)

		it(
			"changement de période seulement à la session suivante : un Défi en cours reste, ses points vont à sa période",
			function()
				-- dimanche 17 janvier 2027, 23:58 UTC (semaine 2975)
				local t = 345600 + 2976 * 604800 - 120
				local w = boot({ t0 = t, flags = { "WeeklyTrack", "Confetti" } })
				local p = join(w, 1, function(d)
					-- objectifs du jour que les pressions ne font pas avancer
					d.objectives = objectives(w, { entry(3), entry(8), entry(17) })
					d.weeklyTrack = trackAt(w, {
						challenges = {
							{ id = 12, p = 0, done = false },
							{ id = 11, p = 0, done = false },
							{ id = 6, p = 0, done = false },
						},
					})
				end)
				local d = data(w, p)
				expect(d.weeklyTrack.period).toBe(2975)
				press(w, p, 20, true)
				expect(d.weeklyTrack.challenges[1].p).toBe(20)
				-- lundi 00:01 : même session, même période, Défi gardé
				w.Clock.advance(180)
				Brains.frames(w, 5)
				expect(w.QR.weekIndex(w.Clock.now())).toBe(2976)
				expect(d.weeklyTrack.period).toBe(2975)
				press(w, p, 10, true)
				expect(d.weeklyTrack.challenges[1].done).toBe(true)
				expect(d.weeklyTrack.points).toBe(5)
				-- session suivante : nouvelle période
				Bots.leave(p)
				w.h:settle(5)
				local q = Brains.join(w, 1)
				local e = data(w, q)
				expect(e.weeklyTrack.period).toBe(2976)
				expect(e.weeklyTrack.points).toBe(0)
				expect(w.Bitset.count(e.weeklyTrack.claimed)).toBe(0)
				expect(#e.weeklyTrack.challenges).toBe(3)
				for _, c in e.weeklyTrack.challenges do
					expect(c.p).toBe(0)
				end
				clean(w)
			end
		)

		it("« Gagne 20 Confettis » ignore les Confettis de la piste (et les dépenses)", function()
			local w = boot({ flags = { "WeeklyTrack", "Confetti" } })
			local p = join(w, 1, function(d)
				d.weeklyTrack = trackAt(w, { points = 4, challenges = { { id = 2, p = 0, done = false } } })
			end)
			local d = data(w, p)
			expect(d.confetti).toBe(4) -- paliers 1 et 2 à la connexion (source « track »)
			expect(d.weeklyTrack.challenges[1].p).toBe(0)
			w.Signals.ConfettiChanged:Fire(p, -3, "spend")
			w.Signals.ConfettiChanged:Fire(p, 5, "track")
			expect(d.weeklyTrack.challenges[1].p).toBe(0)
			w.Signals.ConfettiChanged:Fire(p, 5, "splorch")
			expect(d.weeklyTrack.challenges[1].p).toBe(5)
			w.Signals.ConfettiChanged:Fire(p, 15, "ascend")
			expect(d.weeklyTrack.challenges[1].done).toBe(true)
			expect(d.weeklyTrack.points).toBe(9)
			clean(w)
		end)

		it(
			"jeu des 7 derniers jours : secondes entières par jour UTC, cases des jours sautés vidées",
			function()
				local w = boot({ flags = { "WeeklyTrack" } })
				local p = join(w, 1, function(d)
					local track = trackAt(w)
					track.play = { 100, 200, 300, 400, 500, 600, 700 }
					track.playDay = w.Clock.day() - 2
					d.weeklyTrack = track
				end)
				local d = data(w, p)
				Brains.frames(w, 105) -- 10,5 s de jeu
				local today = w.Clock.day()
				local play = d.weeklyTrack.play
				expect(d.weeklyTrack.playDay).toBe(today)
				expect(play[(today - 1) % 7 + 1]).toBe(0) -- jour sauté
				expect(play[(today - 2) % 7 + 1]).toBe(
					({ 100, 200, 300, 400, 500, 600, 700 })[(today - 2) % 7 + 1]
				)
				local s = play[today % 7 + 1]
				expect(s >= 10 and s <= 11 and s % 1 == 0).toBe(true)
				-- jour suivant : la nouvelle case repart de 0
				w.Clock.advance(w.Clock.untilNextDay() + 1)
				Brains.frames(w, 11)
				expect(d.weeklyTrack.playDay).toBe(today + 1)
				expect(play[(today + 1) % 7 + 1] <= 62).toBe(true) -- un tick compte au plus 60 s de jeu
				clean(w)
			end
		)
	end)

	describe("QuestService v2.0 › Défis de Splorch (Meta/ChallengeCtx, D11)", function()
		it(
			"situation : médiane des 7 jours (aucune sans une minute de jeu), jours joués, Atelier complet",
			function()
				local w = boot()
				local C = w.h:require("ServerScriptService.Server.Meta.ChallengeCtx")
				local Upgrades = w.h:require(L .. "Config.Upgrades")
				expect(C.playMedian(nil)).toBe(nil)
				expect(C.playMedian({ 0, 0, 0, 0, 0, 0, 0 })).toBe(nil)
				expect(C.playMedian({ 59, 0, 0, 0, 0, 0, 0 })).toBe(nil)
				expect(C.playMedian({ 3600, 3600, 0, 0, 0, 0, 0 })).toBe(0)
				expect(w.QR.challengePlaySeconds({ playMedian = 0 })).toBe(1800)
				expect(w.QR.challengePlaySeconds({ playMedian = nil })).toBe(1800)
				expect(C.playMedian({ 10, 20, 30, 40, 50, 60, 70 })).toBe(40)
				expect(C.playMedian({ 7200, 7200, 7200, 7200, 100, 0, 0 })).toBe(7200)
				expect(C.playMedian({ 0 / 0, math.huge, -5, "x", 600, 600, 600 })).toBe(0)
				expect(C.daysPlayed({ 3600, 3600, 0, 0, 0, 0, 0 })).toBe(2)
				expect(C.daysPlayed({ 60, 59, 61, 0, 0, 0, 86400 })).toBe(3)
				expect(C.daysPlayed("x")).toBe(0)
				local d = w.Schema.defaultsFor(2)
				expect(C.workshopDone(d)).toBe(false)
				for i, row in Upgrades.WorkshopRows do
					d.atelier[i] = #row.costs
				end
				expect(C.workshopDone(d)).toBe(false) -- « Pour le plaisir » pas fini
				for i = 1, Upgrades.CosmeticBits do
					w.Bitset.set(d.atelierCosmetics, i)
				end
				expect(C.workshopDone(d)).toBe(true)
				d.atelier[#Upgrades.WorkshopRows] -= 1 -- Déco perso de l'Atelier : 23 / 24
				expect(C.workshopDone(d)).toBe(false)
				expect(C.workshopDone({})).toBe(false)
				clean(w)
			end
		)

		it(
			"estimations : 2 Grands Splorch et record sur une boucle record seulement ; Jelly Ascend prête ou à une boucle ; 2 MEGA au calendrier ; Confettis coupés : jamais",
			function()
				local w = boot()
				local C = w.h:require("ServerScriptService.Server.Meta.ChallengeCtx")
				local P = w.Prestige
				local function prof(r, best, A, g)
					local d = w.Schema.defaultsFor(2)
					d.R = r
					d.bestR = best
					d.ascend = A
					d.growth = { G = 0, g = g, t = 0 }
					return d
				end
				local function input(biggest, opts)
					opts = opts or {}
					return {
						now = T0,
						biggest = biggest,
						recordR = opts.recordR ~= false,
						mega = opts.mega == true,
						confetti = opts.confetti ~= false,
					}
				end
				local target = P.target(2)
				local g = target / 1000
				local e = C.etas(prof(2, 2, 0, g), input(0.9 * target))
				expect(e.recordBeaten).toBeNear(100, 1e-6)
				expect(e.splorches).toBeNear(100 + P.target(3) / g, 1e-6)
				expect(e.ascends).toBe(nil)
				expect(e.megas).toBe(nil)
				expect(e.confettiEarned).toBe(nil)
				-- interrupteur RecordR coupé : jamais le Défi « nouveau Record R »
				e = C.etas(prof(2, 2, 0, g), input(0.9 * target, { recordR = false }))
				expect(e.recordBeaten).toBe(nil)
				expect(e.splorches ~= nil).toBe(true)
				-- remontée après une Ascension (r < Record R) : ni record ni 2 Grands Splorch
				e = C.etas(prof(1, 5, 1, 1e30), input(1e30))
				expect(e.recordBeaten).toBe(nil)
				expect(e.splorches).toBe(nil)
				-- croissance nulle : aucune estimation ; objectif atteint : 0
				expect(C.etas(prof(2, 2, 0, 0), input(0.5 * target)).recordBeaten).toBe(nil)
				expect(C.etas(prof(2, 2, 0, 0), input(target)).recordBeaten).toBe(0)
				-- Jelly Ascend : prête (r ≥ 15) → 0 ; à la fin de la boucle (r = 14) → durée de la boucle ; plus loin → rien
				expect(C.etas(prof(15, 15, 0, 1), input(0)).ascends).toBe(0)
				expect(C.etas(prof(14, 14, 0, P.target(14) / 600), input(0)).ascends).toBeNear(600, 1e-6)
				expect(C.etas(prof(13, 13, 0, 1e30), input(0)).ascends).toBe(nil)
				-- 2 MEGA SQUISH (08:01 : MEGA à 08:20 et 08:50, 60 s de pression et 5 s d'éclatement)
				expect(C.etas(prof(0, 0, 0, 0), input(0, { mega = true })).megas).toBe(3005)
				-- Confettis coupés : « Gagne 20 Confettis » jamais faisable
				expect(C.etas(prof(0, 0, 0, 0), input(0, { confetti = false })).confettiEarned).toBe(
					math.huge
				)
				expect(w.QR.challengeFeasible(2, C.build(prof(0, 0, 0, 0), input(0, { confetti = false })))).toBe(
					false
				)
				clean(w)
			end
		)

		it(
			"tirage : 3 Défis distincts, déterministes par joueur et période, jamais un Défi impossible (minDays, Atelier complet, estimation ; nouveau compte : 30 min)",
			function()
				local w = boot()
				local C = w.h:require("ServerScriptService.Server.Meta.ChallengeCtx")
				local Upgrades = w.h:require(L .. "Config.Upgrades")
				local fresh = w.Schema.defaultsFor(2)
				local input = { now = T0, biggest = 0, recordR = true, mega = true, confetti = true }
				-- nouveau compte : ni minDays, ni Défi de situation (aucune croissance, MEGA trop loin pour 30 min)
				local allowed =
					{ [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [11] = true, [12] = true }
				local seen = {}
				for u = 1, 40 do
					for period = 2970, 2979 do
						local ids = w.QR.drawChallenges(u, period, C.build(fresh, input))
						expect(#ids).toBe(3)
						expect(ids).toEqual(w.QR.drawChallenges(u, period, C.build(fresh, input)))
						local one = {}
						for _, id in ids do
							expect({ id = id, ok = allowed[id] == true, twice = one[id] == true }).toEqual({
								id = id,
								ok = true,
								twice = false,
							})
							one[id] = true
							seen[id] = true
						end
					end
				end
				expect(seen[2]).toBe(true)
				-- joueur de 2 h par jour, 7 jours joués : MEGA et « Nourris Plop 3 jours » deviennent possibles
				local regular = w.Schema.defaultsFor(2)
				regular.weeklyTrack.play = { 7200, 7200, 7200, 7200, 7200, 7200, 7200 }
				local got = {}
				for u = 1, 60 do
					for _, id in w.QR.drawChallenges(u, 2975, C.build(regular, input)) do
						got[id] = true
					end
				end
				expect(got[9]).toBe(true)
				expect(got[10]).toBe(true)
				-- Atelier complet : « Gagne 20 Confettis » n'est plus tiré
				for i, row in Upgrades.WorkshopRows do
					regular.atelier[i] = #row.costs
				end
				for i = 1, Upgrades.CosmeticBits do
					w.Bitset.set(regular.atelierCosmetics, i)
				end
				for u = 1, 60 do
					expect(table.find(w.QR.drawChallenges(u, 2975, C.build(regular, input)), 2)).toBe(nil)
				end
				clean(w)
			end
		)
	end)

	describe("QuestService v2.0 › Carnet du Ranch [Carnet]", function()
		it(
			"paliers : bit et carte au passage du seuil, une fois ; couronne de chantier au 10 000 ; interrupteur coupé : rien",
			function()
				local w = boot({ flags = { "Carnet" } })
				local p = join(w, 1, function(d)
					d.stats.upgradesBought = 49
				end)
				local d = data(w, p)
				expect(#cards(p, "carnet")).toBe(0)
				w.Signals.UpgradeBought:Fire(p, "snack", 0, 1, "coins")
				expect(d.stats.upgradesBought).toBe(50)
				expect(w.Bitset.has(d.carnet, 1)).toBe(true)
				expect(cards(p, "carnet")).toEqual({ { tier = 1, reward = "title.builder" } })
				w.Signals.UpgradeBought:Fire(p, "snack", 1, 2, "coins")
				expect(#cards(p, "carnet")).toBe(1)
				d.stats.upgradesBought = 9999
				w.Signals.UpgradeBought:Fire(p, "snack", 2, 3, "coins")
				local list = cards(p, "carnet")
				expect(#list).toBe(8)
				for i = 2, 8 do
					expect(list[i]).toEqual({
						tier = i,
						reward = w.Quests.Carnet.Rewards[w.Quests.Carnet.Tiers[i]],
					})
				end
				expect(w.Bitset.count(d.carnet)).toBe(8)
				expect(d.outfits.owned.buildersCrown).toBe(1)
				w.Signals.UpgradeBought:Fire(p, "snack", 3, 13, "coins")
				expect(#cards(p, "carnet")).toBe(8)
				expect(d.outfits.owned.buildersCrown).toBe(1)
				clean(w)

				local off = boot()
				local q = join(off, 1, function(e)
					e.stats.upgradesBought = 49
				end)
				off.Signals.UpgradeBought:Fire(q, "snack", 0, 1, "coins")
				local e = data(off, q)
				expect(e.stats.upgradesBought).toBe(50)
				expect(off.Bitset.count(e.carnet)).toBe(0)
				expect(#cards(q, "carnet")).toBe(0)
				clean(off)
			end
		)

		it(
			"premier chargement v2 (carte « Bienvenue » en attente) : les paliers déjà atteints sont posés sans carte",
			function()
				local w = boot({ flags = { "Carnet", "RecordR" } })
				local p = join(w, 1, function(d)
					d.R = 4
					d.bestR = 4
					d.unlocksSeen = 4
					d.onboarding.welcomeV2Pending = true
					d.stats.upgradesBought = 120
				end)
				local d = data(w, p)
				expect(w.Bitset.has(d.carnet, 1)).toBe(true)
				expect(w.Bitset.has(d.carnet, 2)).toBe(true)
				expect(w.Bitset.has(d.carnet, 3)).toBe(false)
				expect(#cards(p, "carnet")).toBe(0)
				expect(#cards(p, "welcomeV2")).toBe(1)
				-- le palier suivant, lui, a sa carte
				d.stats.upgradesBought = 249
				w.Signals.UpgradeBought:Fire(p, "snack", 0, 1, "coins")
				expect(cards(p, "carnet")).toEqual({ { tier = 3, reward = "flag.buildingSite" } })
				clean(w)
			end
		)
	end)

	describe("QuestService v2.0 › cartes du Record R [RecordR]", function()
		it(
			"« Bienvenue dans la v2 ! » une fois (profil migré avec R ≥ 1 : 3 déblocages les plus hauts), jamais pour un nouveau",
			function()
				local w = boot({ flags = { "RecordR" } })
				-- profil v1 (version de test) chargé par un serveur v2 : migration
				local v2 = Brains.profile(w, { R = 5, squishies = { { s = 1, z = 100, bf = 1 } } })
				local v1 = w.Schema.defaultsV1()
				for k in v1 do
					if v2[k] ~= nil then
						v1[k] = v2[k]
					end
				end
				v1.version = 1
				local p = Brains.join(w, 1, { profile = v1 })
				local d = data(w, p)
				expect(d.version).toBe(2)
				local want = {}
				for r = 5, 1, -1 do
					for _, key in w.Prestige.unlocksFor(r) do
						if #want < 3 and table.find(want, key) == nil then
							table.insert(want, key)
						end
					end
				end
				expect(#want).toBe(3)
				expect(cards(p, "welcomeV2")).toEqual({ { highlights = want } })
				expect(#cards(p, "unlock2")).toBe(0)
				expect(d.onboarding.welcomeV2Pending).toBe(false)
				expect(d.unlocksSeen).toBe(5)
				Bots.leave(p)
				w.h:settle(5)
				local q = Brains.join(w, 1)
				expect(#cards(q, "welcomeV2")).toBe(0)
				expect(#cards(q, "unlock2")).toBe(0)
				-- un nouveau joueur : jamais
				local n = Brains.join(w, 2, { profile = Bots.profile(w, {}) })
				Brains.frames(w, 2)
				expect(#cards(n, "welcomeV2")).toBe(0)
				expect(#cards(n, "unlock2")).toBe(0)
				clean(w)
			end
		)

		it(
			"« Nouveau » à chaque nouveau Record R ; une seule carte pour ceux manqués ; tenues du Record R (R7, R16) une fois",
			function()
				local w = boot({ flags = { "RecordR" } })
				local p = join(w, 1, function(d)
					d.R = 6
					d.bestR = 6
					d.unlocksSeen = 3
				end)
				local d = data(w, p)
				expect(cards(p, "unlock2")).toEqual({ { recordR = 6, keys = w.Prestige.unlocksFor(6) } })
				expect(d.unlocksSeen).toBe(6)
				expect(d.outfits.owned.partyHat).toBe(nil)
				d.R = 7
				d.bestR = 7
				w.Signals.RecordReached:Fire(p, 7)
				expect(cards(p, "unlock2")[2]).toEqual({ recordR = 7, keys = w.Prestige.unlocksFor(7) })
				expect(d.unlocksSeen).toBe(7)
				expect(d.outfits.owned.partyHat).toBe(1)
				w.Signals.RecordReached:Fire(p, 7)
				expect(#cards(p, "unlock2")).toBe(2)
				expect(d.outfits.owned.partyHat).toBe(1)
				clean(w)
				-- rattrapage à la connexion : Record R 16 sans les tenues
				local w2 = boot({ flags = { "RecordR" } })
				local q = join(w2, 1, function(e)
					e.R = 16
					e.bestR = 16
					e.unlocksSeen = 16
				end)
				local e = data(w2, q)
				expect(#cards(q, "unlock2")).toBe(0)
				expect(e.outfits.owned.partyHat).toBe(1)
				expect(e.outfits.owned.starGlasses).toBe(1)
				clean(w2)
			end
		)

		it(
			"étapes du record à 25 / 50 / 75 %, une fois chacune par boucle, boucle record seulement, jamais dans la file",
			function()
				local w = boot({ flags = { "RecordR" } })
				local p = join(w, 1, function(d)
					d.R = 2
					d.bestR = 2
				end, { { s = 1, z = 10, bf = 1 }, { s = 2, z = 10 } })
				local function look(share)
					setShare(w, p, share)
					Brains.frames(w, 25)
				end
				look(0.1)
				expect(#cards(p, "recordStep")).toBe(0)
				look(0.3)
				look(0.3)
				look(0.55)
				look(0.9)
				look(0.95)
				expect(cards(p, "recordStep")).toEqual({ { share = 0.25 }, { share = 0.5 }, { share = 0.75 } })
				-- nouvelle boucle (prestige) : remise à zéro ; trois étapes passées d'un coup : une seule carte
				local d = data(w, p)
				d.R = 3
				d.bestR = 3
				w.Signals.PrestigeApplied:Fire(p, "splorch", 2, 3, 0)
				look(0.8)
				expect(#cards(p, "recordStep")).toBe(4)
				expect(cards(p, "recordStep")[4]).toEqual({ share = 0.75 })
				-- prestige du joueur dans la file : rien
				d.R = 4
				d.bestR = 4
				w.Signals.PrestigeApplied:Fire(p, "splorch", 3, 4, 0)
				local uid = w.Squishy.biggest(p)
				w.Squishy.setWaiting(p, uid)
				look(0.6)
				expect(#cards(p, "recordStep")).toBe(4)
				w.Squishy.setWaiting(p, nil)
				look(0.6)
				expect(#cards(p, "recordStep")).toBe(5)
				-- remontée (r < Record R) : jamais
				d.R = 1
				d.bestR = 6
				d.ascend = 1
				w.Signals.PrestigeApplied:Fire(p, "ascend", 4, 1, 1)
				look(0.3)
				look(0.9)
				expect(#cards(p, "recordStep")).toBe(5)
				clean(w)
				-- première vue de la session : les étapes déjà passées sont posées sans carte
				local w2 = boot({ flags = { "RecordR" } })
				local q = join(w2, 1, function(e)
					e.R = 2
					e.bestR = 2
				end, { { s = 1, z = 10, bf = 1 }, { s = 2, z = 10 } })
				setShare(w2, q, 0.6)
				Brains.frames(w2, 25)
				expect(#cards(q, "recordStep")).toBe(0)
				setShare(w2, q, 0.8)
				Brains.frames(w2, 25)
				expect(cards(q, "recordStep")).toEqual({ { share = 0.75 } })
				clean(w2)
			end
		)
	end)

	describe("QuestService v2.0 › jours de givre et puce « Prochain achat »", function()
		it(
			"jours de givre : + 1 par jour où Plop est nourri pendant le costume d'hiver (interrupteur et dates), profil v2 seulement",
			function()
				-- dimanche 20 décembre 2026, 10:00 UTC (costume winter2026 : 12 décembre → 9 janvier)
				local t = 1797033600 + 8 * DAY + 10 * 3600
				local function feed(w, p)
					local slot = w.Ranch.slotOf(p)
					local b = w.WL.anchor(slot, "bowl")
					Bots.place(p, Bots.ground(b.X + 2, b.Z))
					Brains.frames(w, 3)
					fire(w, "FeedPlop", p, true)
					Brains.frames(w, 21)
				end
				local w = boot({ t0 = t })
				local p = join(w, 1)
				local d = data(w, p)
				feed(w, p)
				expect(d.plopDays).toBe(1)
				expect(d.season.frostDays).toBe(1)
				w.Clock.advance(w.Clock.untilNextDay() + 60)
				Brains.frames(w, 2)
				feed(w, p)
				expect(d.plopDays).toBe(2)
				expect(d.season.frostDays).toBe(2)
				-- costume coupé : plus rien
				assert(w.Features.set("Costumes", ""))
				w.Clock.advance(w.Clock.untilNextDay() + 60)
				Brains.frames(w, 2)
				feed(w, p)
				expect(d.plopDays).toBe(3)
				expect(d.season.frostDays).toBe(2)
				clean(w)
				-- hors des dates (15 janvier) : rien
				local w2 = boot()
				local q = join(w2, 1)
				feed(w2, q)
				expect(data(w2, q).plopDays).toBe(1)
				expect(data(w2, q).season.frostDays).toBe(0)
				clean(w2)
				-- profil v1 (même dates) : aucune clé v2
				local w3 = boot({ v1 = true, t0 = t })
				local r = join(w3, 1)
				feed(w3, r)
				expect(data(w3, r).plopDays).toBe(1)
				expect(data(w3, r).season.frostDays).toBe(nil)
				clean(w3)
			end
		)

		it(
			"« Prochain achat » vu (UiSeen nextBuy) : onboarding.nextBuyShown une fois, profil v2 et écran Améliorations ouvert seulement",
			function()
				local w = boot()
				local p = join(w, 1)
				fire(w, "UiSeen", p, "nextBuy")
				expect(data(w, p).onboarding.nextBuyShown).toBe(false)
				assert(w.Features.set("UpgradesScreen", true))
				local q = join(w, 2)
				local before = #w.h:sentTo(q, "DataPatch")
				fire(w, "UiSeen", q, "nextBuy")
				expect(data(w, q).onboarding.nextBuyShown).toBe(true)
				Brains.frames(w, 1)
				local after = #w.h:sentTo(q, "DataPatch")
				fire(w, "UiSeen", q, "nextBuy")
				Brains.frames(w, 1)
				expect(#w.h:sentTo(q, "DataPatch")).toBe(after)
				expect(after > before).toBe(true)
				clean(w)
				-- profil v1 : aucune clé v2
				local v1 = boot({ v1 = true })
				assert(v1.Features.set("UpgradesScreen", true))
				local r = join(v1, 1)
				fire(v1, "UiSeen", r, "nextBuy")
				expect(data(v1, r).onboarding.nextBuyShown).toBe(nil)
				clean(v1)
			end
		)
	end)

	describe("QuestService v2.0 › interrupteurs coupés : le jeu d'aujourd'hui", function()
		-- partie jouée : objectifs, achats, prestiges, Confettis, tampons, MEGA, bol vu, temps de jeu
		local function play(w, p)
			press(w, p, 35, true)
			fire(w, "BuyTile", p, "snack")
			w.Signals.UpgradeBought:Fire(p, "gloves", 0, 10, "coins")
			w.Signals.PrestigeApplied:Fire(p, "petit", 2, 3, 1)
			w.Signals.RecordReached:Fire(p, 3)
			w.Signals.ConfettiChanged:Fire(p, 20, "splorch")
			w.Signals.Stamped:Fire(p, 5)
			w.Signals.Fed:Fire(p, 3)
			w.Signals.Hatched:Fire(p, "1", 4)
			w.Signals.MegaJoined:Fire(p, 50, true)
			w.Signals.Fused:Fire(p, "1", 3)
			w.Signals.Caught:Fire(p, catchInfo("runaway"))
			fire(w, "UiSeen", p, "nextBuy")
			Brains.frames(w, 60)
		end

		local function run(flags)
			local w = boot({ v1 = true, flags = flags })
			local p = join(w, 1, function(d)
				d.coins = 1e12
				d.R = 2
				d.objectives = objectives(w, { entry(1), entry(9), entry(14) })
			end)
			play(w, p)
			local sent = {}
			for _, e in w.h.log.clientEvents do
				if e.player == p then
					table.insert(sent, e.remote .. ser(e.args))
				end
			end
			local out = { profile = ser(data(w, p)), sent = sent, v2 = v2Cards(p), d = data(w, p) }
			clean(w)
			return out, w
		end

		it(
			"profil v1 (SchemaV2 coupé) : aucun champ v2 écrit, aucune carte v2, mêmes données et mêmes envois que sans les interrupteurs de QuestService",
			function()
				local off, w = run({})
				local on = run({ "WeeklyTrack", "Carnet", "RecordR", "UpgradesScreen", "Confetti" })
				expect(off.v2).toBe(0)
				expect(on.v2).toBe(0)
				expect(on.profile).toBe(off.profile)
				for i = 1, math.max(#on.sent, #off.sent) do
					if on.sent[i] ~= off.sent[i] then
						local a, b = off.sent[i] or "-", on.sent[i] or "-"
						local k = 1
						while k <= #a and string.sub(a, k, k) == string.sub(b, k, k) do
							k += 1
						end
						print("DIFF", i, k, string.sub(a, math.max(1, k - 150), k + 150))
						print("DIFF", i, k, string.sub(b, math.max(1, k - 150), k + 150))
						break
					end
				end
				expect(#on.sent).toBe(#off.sent)
				for i, line in off.sent do
					expect({ i = i, line = on.sent[i] }).toEqual({ i = i, line = line })
				end
				-- aucune clé de la v2 dans le profil (premier niveau et sous-clés des tables de la v1)
				local v1 = w.Schema.defaultsV1()
				for key, value in off.d do
					expect({ key = key, known = v1[key] ~= nil }).toEqual({ key = key, known = true })
					if type(value) == "table" and type(v1[key]) == "table" then
						for _, sub in
							{
								"upgradesBought",
								"petitSplorches",
								"objectivesClaimed",
								"tracksDone",
								"frostDays",
								"nextBuyShown",
								"welcomeV2Pending",
							}
						do
							expect({ key = key, sub = sub, value = value[sub] }).toEqual({
								key = key,
								sub = sub,
								value = nil,
							})
						end
					end
				end
			end
		)

		it(
			"profil v2, interrupteurs coupés : piste, Carnet, cartes et Record R vus intacts, aucune carte v2 (seuls les compteurs à vie avancent)",
			function()
				local w = boot()
				local p = join(w, 1, function(d)
					d.coins = 1e12
					d.R = 3
					d.bestR = 3
					d.unlocksSeen = 0
					d.onboarding.welcomeV2Pending = true
					d.stats.upgradesBought = 49
					d.objectives = objectives(w, { entry(1), entry(9), entry(14) })
				end, { { s = 1, z = 1e9, bf = 1 }, { s = 2, z = 50 } })
				local d = data(w, p)
				local track = ser(d.weeklyTrack)
				play(w, p)
				expect(ser(d.weeklyTrack)).toBe(track)
				expect(w.Bitset.count(d.carnet)).toBe(0)
				expect(d.unlocksSeen).toBe(0)
				expect(d.onboarding.welcomeV2Pending).toBe(true)
				expect(d.onboarding.nextBuyShown).toBe(false)
				expect(d.season.frostDays).toBe(0)
				expect(v2Cards(p)).toBe(0)
				-- compteurs à vie (D34) : profil v2, sans interrupteur
				expect(d.stats.upgradesBought).toBe(49 + 1 + 10)
				expect(d.stats.petitSplorches).toBe(1)
				clean(w)
			end
		)
	end)
end
