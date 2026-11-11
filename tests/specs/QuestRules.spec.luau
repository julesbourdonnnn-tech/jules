--!nocheck
-- QuestRules (paquet logic, docs/04 §12.1, GDD §7.3, §7.4, §4.17) : « Proposé si », tirage
-- déterministe, relance, progression, minuit en session, paliers, Squishydex.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- interrupteurs v2.0 coupés au départ (préréglage « cut » ; lot I, étape 2, D2 a, journal I-19) :
	-- chaque cas ouvre ce qu'il prouve
	local h = Harness.new({ flags = "cut" })
	local QR = h:require("ReplicatedStorage.Shared.Logic.QuestRules")
	local Quests = h:require("ReplicatedStorage.Shared.Config.Quests")

	local function ctx(changes)
		local c =
			{ R = 0, tilesLeft = 10, megaIn = 5000, friendOnServer = false, splorchEta = 1e9, stamps = 10 }
		for k, v in changes or {} do
			c[k] = v
		end
		return c
	end
	local function def(id)
		return Quests.Objectives[id]
	end
	local function dex(mutMasks, starMasks)
		local mut, stars = table.create(26, 0), table.create(26, 0)
		for s, m in mutMasks or {} do
			mut[s] = m
		end
		for s, m in starMasks or {} do
			stars[s] = m
		end
		return { mut = mut, stars = stars, rewards = 0 }
	end

	describe("QuestRules › « Proposé si »", function()
		it("chaque règle du GDD §7.4", function()
			expect(QR.eligible(def(1), ctx())).toBe(true)
			expect(QR.eligible(def(4), ctx({ tilesLeft = 2 }))).toBe(false)
			expect(QR.eligible(def(4), ctx({ tilesLeft = 3 }))).toBe(true)
			expect(QR.eligible(def(10), ctx({ megaIn = 1201 }))).toBe(false)
			expect(QR.eligible(def(10), ctx({ megaIn = 1200 }))).toBe(true)
			expect(QR.eligible(def(12), ctx())).toBe(false)
			expect(QR.eligible(def(12), ctx({ friendOnServer = true }))).toBe(true)
			expect(QR.eligible(def(14), ctx({ R = 0 }))).toBe(false)
			expect(QR.eligible(def(14), ctx({ R = 1 }))).toBe(true)
			expect(QR.eligible(def(15), ctx({ R = 2 }))).toBe(false)
			expect(QR.eligible(def(15), ctx({ R = 3 }))).toBe(true)
			expect(QR.eligible(def(16), ctx({ splorchEta = 1200 }))).toBe(true)
			expect(QR.eligible(def(16), ctx({ splorchEta = 1201 }))).toBe(false)
			expect(QR.eligible(def(18), ctx({ stamps = 119 }))).toBe(true)
			expect(QR.eligible(def(18), ctx({ stamps = 120 }))).toBe(false)
		end)

		it("valeurs bizarres : jamais proposé à tort (NaN, nil, règle inconnue)", function()
			expect(QR.eligible(def(16), ctx({ splorchEta = 0 / 0 }))).toBe(false)
			expect(QR.eligible(def(10), ctx({ megaIn = -5 }))).toBe(false)
			expect(QR.eligible(def(18), ctx({ stamps = 0 / 0 }))).toBe(false)
			expect(QR.eligible({ condition = "???" }, ctx())).toBe(false)
			expect(QR.eligible(nil, ctx())).toBe(false)
			expect(QR.eligible(def(1), nil)).toBe(true)
		end)
	end)

	describe("QuestRules › tirage et relance", function()
		it("jour 1 : « Presse 30 », « Attrape 2 », « Fais 1 fusion »", function()
			expect(QR.draw(1, 20000, ctx(), true)).toEqual({ 1, 3, 7 })
		end)

		it("un facile, un moyen, un difficile, proposables, déterministes par (jour, joueur)", function()
			for day = 20000, 20200 do
				local list = QR.draw(42, day, ctx({ R = 0 }), false)
				expect(#list).toBe(3)
				expect(def(list[1]).tier).toBe("easy")
				expect(def(list[2]).tier).toBe("medium")
				expect(def(list[3]).tier).toBe("hard")
				for _, id in list do
					expect(QR.eligible(def(id), ctx({ R = 0 }))).toBe(true)
				end
				expect(QR.draw(42, day, ctx({ R = 0 }), false)).toEqual(list)
			end
		end)

		it("relance : même niveau, différent des 3 actuels, proposable", function()
			local current = { 1, 7, 17 }
			for salt = 1, 50 do
				for slot = 1, 3 do
					local id = QR.reroll(
						7,
						20001,
						current,
						slot,
						ctx({ R = 5, friendOnServer = true, megaIn = 100 }),
						salt
					)
					expect(def(id).tier).toBe(def(current[slot]).tier)
					expect(table.find(current, id)).toBeNil()
				end
			end
		end)

		it("relance sans candidat : l'objectif actuel reste", function()
			-- difficile à R = 0 sans Grand Splorch proche et 200 tampons : seul 17 est proposable
			local id = QR.reroll(7, 20001, { 1, 7, 17 }, 3, ctx({ R = 0, stamps = 200 }), 1)
			expect(id).toBe(17)
		end)
	end)

	describe("QuestRules › progression", function()
		local function entry(id, p)
			return { id = id, p = p or 0, done = false, claimed = false }
		end

		it("compteur de sa statistique, terminé au but, rien de plus", function()
			local e = QR.apply(entry(1, 29), "press", 1)
			expect(e).toEqual({ id = 1, p = 30, done = true, claimed = false })
			expect(QR.apply(e, "press", 5).p).toBe(30)
			expect(QR.apply(entry(1), "catch", 5).p).toBe(0)
			expect(QR.apply(entry(1), "press", -5).p).toBe(0)
			expect(QR.apply(entry(1), "press", 0 / 0).p).toBe(0)
		end)

		it("série PERFECT : +1 par PERFECT, remise à 0 par une pression ratée", function()
			local e = entry(9)
			e = QR.apply(e, "press", 1, true)
			e = QR.apply(e, "press", 1, true)
			expect(e.p).toBe(2)
			e = QR.apply(e, "press", 1, false)
			expect(e.p).toBe(0)
			for _ = 1, 5 do
				e = QR.apply(e, "press", 1, true)
			end
			expect(e.done).toBe(true)
			-- terminé : une pression ratée ne retire rien
			expect(QR.apply(e, "press", 1, false).done).toBe(true)
		end)

		it("rend une copie (l'entrée d'origine ne bouge pas)", function()
			local e = entry(1, 3)
			local out = QR.apply(e, "press", 1)
			expect(e.p).toBe(3)
			expect(out.p).toBe(4)
		end)

		it("minuit : terminés réclamés d'office, en cours gardés pour la session", function()
			local list = {
				{ id = 1, p = 30, done = true, claimed = false },
				{ id = 7, p = 1, done = false, claimed = false },
				{ id = 17, p = 1, done = true, claimed = true },
			}
			local kept, claim = QR.rollover(list, true)
			expect(claim).toEqual({ 1 })
			expect(#kept).toBe(1)
			expect(kept[1].id).toBe(7)
			local kept2, claim2 = QR.rollover(list, false)
			expect(claim2).toEqual({})
			expect(#kept2).toBe(2)
		end)
	end)

	describe("QuestRules › Nourrir Plop et Squishydex", function()
		it("paliers de Nourrir Plop (jours au total)", function()
			expect(QR.plopReward(1).key).toBe("day1")
			expect(QR.plopReward(2).kind).toBe("coins")
			expect(QR.plopReward(4)).toBeNil()
			expect(QR.plopReward(100).id).toBe("goldenBowl")
			expect(QR.plopReward(0 / 0)).toBeNil()
		end)

		it("jalons atteints et non réclamés", function()
			local list = QR.dexMilestones(60, 10)
			expect(#list).toBe(2)
			expect(list[1].stamps).toBe(25)
			expect(list[2].stamps).toBe(50)
			expect(#QR.dexMilestones(260, 0)).toBe(9)
			expect(#QR.dexMilestones(5, 0)).toBe(0)
		end)

		it("tampons, badges d'étoiles, familles, pages dorées", function()
			-- Plop : page + Gelée + Néon ; Mochi Mew : page ; ★1 et ★2 pour Plop
			local d = dex({ [1] = 0x7, [5] = 0x1 }, { [1] = 0x3 })
			expect(QR.stampCount(d)).toBe(4)
			expect(QR.starBadges(d)).toBe(2)
			expect(QR.familyComplete(d, "jelly")).toBe(false)
			local full = dex({ [1] = 1, [2] = 1, [3] = 1, [4] = 1 })
			expect(QR.familyComplete(full, "jelly")).toBe(true)
			expect(QR.familyComplete(dex({ [25] = 1, [26] = 1 }), "secret")).toBe(false)
			-- page dorée : les 8 mutations hors Lunaire (bits 1-6, 8, 9)
			local golden = 0
			for _, m in { 1, 2, 3, 4, 5, 6, 8, 9 } do
				golden += 2 ^ m
			end
			expect(QR.goldenPages(dex({ [1] = golden + 1, [2] = golden }))).toBe(2)
			expect(QR.goldenPages(dex({ [1] = golden - 2 }))).toBe(0)
			expect(QR.stampCount(nil)).toBe(0)
		end)

		it("nouveau tampon : espèce, mutation ou badge d'étoiles encore vide", function()
			local d = dex({ [1] = 0x3 }, { [1] = 0x1 })
			expect(QR.isNewStamp(d, 5, 0, 0)).toBe(true)
			expect(QR.isNewStamp(d, 1, 0, 0)).toBe(false)
			expect(QR.isNewStamp(d, 1, 1, 0)).toBe(false)
			expect(QR.isNewStamp(d, 1, 2, 0)).toBe(true)
			expect(QR.isNewStamp(d, 1, 0, 1)).toBe(false)
			expect(QR.isNewStamp(d, 1, 0, 2)).toBe(true)
			expect(QR.isNewStamp(d, 999, 0, 0)).toBe(false)
			-- dex trop court (ancienne sauvegarde) : traité comme vide, jamais d'erreur
			expect(QR.isNewStamp({ mut = {}, stars = {} }, 26, 0, 0)).toBe(true)
		end)

		it(
			"familyEarned (contrat v1.2) : bonus gagné pour toujours, lu dans dex.fam[index de FamilyOrder]",
			function()
				local Species = h:require("ReplicatedStorage.Shared.Config.Species")
				local order = Species.FamilyOrder
				local function famDex(fam)
					return {
						mut = table.create(#Species.List, 0),
						stars = table.create(#Species.List, 0),
						fam = fam,
					}
				end
				local fam = table.create(#order, 0)
				local d = famDex(fam)
				for _, key in order do
					expect(QR.familyEarned(d, key)).toBe(false)
				end
				-- Kitty (index 2) gagnée : seule Kitty compte, même si aucune espèce n'est tamponnée (pour
				-- toujours : une espèce ajoutée plus tard ne retire jamais le bonus)
				fam[table.find(order, "kitty")] = 1
				expect(QR.familyEarned(d, "kitty")).toBe(true)
				expect(QR.familyEarned(d, "jelly")).toBe(false)
				expect(QR.familyComplete(d, "kitty")).toBe(false)
				-- Secrets : jamais de bonus, même avec une case abîmée à 1
				fam[table.find(order, "secret")] = 1
				expect(QR.familyEarned(d, "secret")).toBe(false)
				-- valeurs autres que 1, famille inconnue, dex abîmé : faux, jamais d'erreur
				fam[1] = 2
				expect(QR.familyEarned(d, "jelly")).toBe(false)
				fam[1] = true
				expect(QR.familyEarned(d, "jelly")).toBe(false)
				expect(QR.familyEarned(d, "dragon")).toBe(false)
				expect(QR.familyEarned({}, "kitty")).toBe(false)
				expect(QR.familyEarned(nil, "kitty")).toBe(false)
				expect(QR.familyEarned({ fam = "x" }, "kitty")).toBe(false)
				expect(QR.familyEarned(d, nil)).toBe(false)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- GDD v2.0 §7.5 (lot A1, docs/04 §27.7, §27.10) : semaine UTC, piste, Défis, Carnet
	-- ---------------------------------------------------------------------------------------------
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local DAY, WEEK = 86400, 604800
	-- horodatages UTC (calculés hors du jeu, calendrier grégorien) : (jour de la semaine, unix)
	local SUN_2026_12_27_235959 = 1798415999
	local MON_2026_12_28 = 1798416000
	local SUN_2027_01_03_235959 = 1799020799
	local MON_2027_01_04 = 1799020800
	local MON_2028_02_28_NOON = 1835352000
	local TUE_2028_02_29 = 1835395200 -- année bissextile
	local WED_2028_03_01 = 1835481600
	local MON_2028_03_06 = 1835913600

	describe("QuestRules › semaine UTC (weekIndex)", function()
		it("lundi 5 janvier 1970 00:00 UTC = semaine 0 ; une semaine = 604 800 s", function()
			expect(QR.weekIndex(345600)).toBe(0)
			expect(QR.weekIndex(345600 + WEEK - 1)).toBe(0)
			expect(QR.weekIndex(345600 + WEEK)).toBe(1)
			expect(QR.weekStart(0)).toBe(345600)
			expect(QR.weekStart(2973)).toBe(MON_2026_12_28)
		end)

		it(
			"bascules du dimanche 23:59:59 au lundi 00:00:00 et fins d'année (2026-12-28, 2027-01-04)",
			function()
				expect(QR.weekIndex(SUN_2026_12_27_235959)).toBe(2972)
				expect(QR.weekIndex(MON_2026_12_28)).toBe(2973)
				expect(QR.weekIndex(SUN_2027_01_03_235959)).toBe(2973) -- la semaine traverse le 1er janvier
				expect(QR.weekIndex(MON_2027_01_04)).toBe(2974)
				-- jamais un numéro de semaine de l'année (2026 a 53 semaines ISO) : les numéros se suivent
				expect(QR.weekIndex(MON_2027_01_04) - QR.weekIndex(MON_2026_12_28)).toBe(1)
			end
		)

		it("année bissextile : le 29 février est dans la semaine du lundi 28 février 2028", function()
			expect(QR.weekIndex(MON_2028_02_28_NOON)).toBe(3034)
			expect(QR.weekIndex(TUE_2028_02_29)).toBe(3034)
			expect(QR.weekIndex(WED_2028_03_01)).toBe(3034)
			expect(QR.weekIndex(MON_2028_03_06)).toBe(3035)
			expect(QR.weekStart(3035)).toBe(MON_2028_03_06)
		end)

		it("entrées illisibles ou antérieures à l'époque : semaine 0, jamais d'erreur", function()
			for _, x in { 0 / 0, math.huge, -math.huge, -5, 0, nil, "x", {} } do
				expect(QR.weekIndex(x)).toBe(0)
			end
			expect(QR.weekStart(-3)).toBe(345600)
			expect(QR.weekStart(0 / 0)).toBe(345600)
		end)
	end)

	describe("QuestRules › période de la piste (trackPeriod)", function()
		local function track(fpe)
			return {
				weeklyTrack = {
					period = 0,
					points = 0,
					claimed = { 0 },
					challenges = {},
					firstPeriodEnd = fpe,
				},
			}
		end

		it("1re période : de la 1re connexion au 2e lundi qui suit (8 à 14 jours de calendrier)", function()
			-- mercredi 30 décembre 2026 : fin le lundi 11 janvier 2027 (2e lundi), période 2974
			local wed = MON_2026_12_28 + 2 * DAY + 3600
			local p = QR.trackPeriod(track(0), wed)
			expect(p.first).toBe(true)
			expect(p.firstPeriodEnd).toBe(MON_2027_01_04 + WEEK)
			expect(p.endsAt).toBe(MON_2027_01_04 + WEEK)
			expect(p.period).toBe(2974)
			-- dimanche 23:59:59 : 7 jours et 1 s ; lundi 00:00:00 : 14 jours
			local late = QR.trackPeriod(track(0), SUN_2026_12_27_235959)
			expect(late.endsAt - SUN_2026_12_27_235959).toBe(WEEK + 1)
			local early = QR.trackPeriod(track(0), MON_2026_12_28)
			expect(early.endsAt - MON_2026_12_28).toBe(2 * WEEK)
			-- profil v1 (pas de piste) ou champ absent : fixée de la même façon
			expect(QR.trackPeriod({}, wed).firstPeriodEnd).toBe(p.firstPeriodEnd)
			expect(QR.trackPeriod({ weeklyTrack = {} }, wed).firstPeriodEnd).toBe(p.firstPeriodEnd)
		end)

		it(
			"la 1re période garde son numéro jusqu'à sa fin, puis les semaines normales se suivent",
			function()
				local fpe = MON_2027_01_04 + WEEK
				local ids = {}
				local t = MON_2026_12_28 + 2 * DAY
				local last = -1
				while t < fpe + 3 * WEEK do
					local p = QR.trackPeriod(track(fpe), t)
					expect(p.period >= last).toBe(true) -- jamais une période qui recule
					expect(t >= p.startsAt and t < p.endsAt).toBe(true)
					expect(p.firstPeriodEnd).toBe(fpe)
					if p.period ~= last then
						table.insert(ids, p.period)
					end
					last = p.period
					t += 3600
				end
				expect(ids).toEqual({ 2974, 2975, 2976, 2977 })
				-- à la seconde de la fin : semaine normale
				local after = QR.trackPeriod(track(fpe), fpe)
				expect(after.first).toBe(false)
				expect(after.period).toBe(2975)
				expect(after.endsAt - after.startsAt).toBe(WEEK)
				local before = QR.trackPeriod(track(fpe), fpe - 1)
				expect(before.first).toBe(true)
				expect(before.period).toBe(2974)
			end
		)

		it(
			"fin abîmée (pas un lundi, plus de 2 semaines plus tard, NaN) : 1re période finie, jamais de recul",
			function()
				local now = MON_2026_12_28 + 3 * DAY
				for _, bad in { MON_2027_01_04 + 5, MON_2027_01_04 + 5 * WEEK, 0 / 0, math.huge, -WEEK, "x" } do
					local p = QR.trackPeriod(track(bad), now)
					expect({ bad = tostring(bad), first = p.first, period = p.period }).toEqual({
						bad = tostring(bad),
						first = false,
						period = 2973,
					})
					-- la valeur rendue est sûre : relue, elle donne la même période
					expect(QR.trackPeriod(track(p.firstPeriodEnd), now).period).toBe(2973)
					expect(QR.trackPeriod(track(p.firstPeriodEnd), now).first).toBe(false)
				end
				expect(QR.trackPeriod(nil, now).first).toBe(true) -- profil illisible : comme un compte neuf
			end
		)

		it(
			"chaque période permet d'atteindre 24 points (12 paliers), même au joueur du week-end",
			function()
				local weekend = { [5] = true, [6] = true } -- samedi, dimanche
				local need = #Quests.WeeklyTrack.Tiers * Quests.WeeklyTrack.PointsPerTier
				expect(need).toBe(24)
				-- semaines normales autour des fins d'année et d'un 29 février
				for _, monday in { MON_2026_12_28, MON_2027_01_04, MON_2028_02_28_NOON - 12 * 3600 } do
					local p = QR.trackPeriod(track(1), monday + 1)
					expect(QR.trackMaxPoints(p.startsAt, p.endsAt)).toBe(7 * 6 + 15)
					expect(QR.trackMaxPoints(p.startsAt, p.endsAt, weekend)).toBe(27) -- GDD §7.5 : 12 + 15
				end
				-- 1re période, quelle que soit l'heure de la 1re connexion (toutes les heures sur 3 semaines)
				local t = MON_2026_12_28 - WEEK
				while t < MON_2027_01_04 + 2 * WEEK do
					local p = QR.trackPeriod(track(0), t)
					local points = QR.trackMaxPoints(t, p.endsAt, weekend)
					expect({ t = t, ok = points >= need, first = p.first }).toEqual({
						t = t,
						ok = true,
						first = true,
					})
					t += 3600
				end
			end
		)

		it("paliers de la piste : 1 palier = 2 points, 12 au plus", function()
			expect(QR.trackTier(0)).toBe(0)
			expect(QR.trackTier(1)).toBe(0)
			expect(QR.trackTier(2)).toBe(1)
			expect(QR.trackTier(23)).toBe(11)
			expect(QR.trackTier(24)).toBe(12)
			expect(QR.trackTier(57)).toBe(12)
			expect(QR.trackTier(0 / 0)).toBe(0)
			expect(QR.trackTier(-4)).toBe(0)
		end)
	end)

	describe("QuestRules › Défis de Splorch (challengeFeasible, drawChallenges)", function()
		local ALL_ETA = { splorches = 600, recordBeaten = 300, ascends = 900, megas = 1200 }

		it("12 Défis ; ceux de situation exigent une estimation qui tient dans le temps de jeu", function()
			expect(#Quests.Challenges).toBe(12)
			-- sans estimation : Grands Splorch, record, Ascension et MEGA ne sont jamais tirés
			for id, expected in { [1] = false, [3] = true, [4] = false, [5] = false, [6] = true, [9] = false } do
				expect({ id = id, ok = QR.challengeFeasible(id, {}) }).toEqual({ id = id, ok = expected })
			end
			expect(QR.challengeFeasible(1, { eta = { splorches = 1700 } })).toBe(true) -- 30 min par défaut
			expect(QR.challengeFeasible(1, { eta = { splorches = 1900 } })).toBe(false)
			expect(QR.challengeFeasible(1, { playMedian = 3600, eta = { splorches = 1900 } })).toBe(true)
			-- temps de jeu borné à [30 min ; 2 h] (jamais 2 h fixes, jamais moins de 30 min)
			expect(QR.challengePlaySeconds({ playMedian = 9 * 3600 })).toBe(7200)
			expect(QR.challengePlaySeconds({ playMedian = 60 })).toBe(1800)
			expect(QR.challengePlaySeconds(nil)).toBe(1800)
			expect(QR.challengePlaySeconds({ playMedian = 0 / 0 })).toBe(1800)
			expect(QR.challengeFeasible(4, { playMedian = 9 * 3600, eta = { recordBeaten = 7201 } })).toBe(
				false
			)
			-- estimation illisible ou négative : non faisable
			for _, bad in { 0 / 0, math.huge, -1, "x" } do
				expect(QR.challengeFeasible(4, { eta = { recordBeaten = bad } })).toBe(false)
			end
			-- une estimation donnée pour un Défi de jeu normal compte aussi
			expect(QR.challengeFeasible(12, { eta = { perfects = 4000 } })).toBe(false)
		end)

		it(
			"« Gagne 20 Confettis » retiré quand l'Atelier est complet ; « Nourris Plop 3 jours » après 3 jours",
			function()
				expect(QR.challengeFeasible(2, {})).toBe(true)
				expect(QR.challengeFeasible(2, { workshopDone = true })).toBe(false)
				expect(QR.challengeFeasible(10, {})).toBe(false)
				expect(QR.challengeFeasible(10, { daysPlayed = 2 })).toBe(false)
				expect(QR.challengeFeasible(10, { daysPlayed = 3 })).toBe(true)
			end
		)

		it(
			"« Fais une Jelly Ascend » seulement avec l'interrupteur JellyAscend ouvert (coupé et ouvert)",
			function()
				expect(Features.get("JellyAscend")).toBe(false)
				expect(QR.challengeFeasible(5, { eta = ALL_ETA })).toBe(false)
				assert(Features.set("JellyAscend", true))
				local okRun, err = pcall(function()
					expect(QR.challengeFeasible(5, { eta = ALL_ETA })).toBe(true)
					expect(QR.challengeFeasible(5, { eta = { ascends = 3600 } })).toBe(false)
				end)
				Features.reset()
				assert(okRun, err)
			end
		)

		it("identifiants inconnus : jamais faisables", function()
			for _, id in { 0, 13, -1, 1.5, 0 / 0, "1", nil } do
				expect(QR.challengeFeasible(id, { eta = ALL_ETA })).toBe(false)
			end
		end)

		it(
			"tirage : 3 Défis faisables, différents, déterministes par (joueur, période), sans dépendre des autres",
			function()
				local seen = {}
				for user = 1, 200 do
					for period = 2970, 2975 do
						local ctx = { playMedian = 3600, daysPlayed = user % 5, workshopDone = user % 3 == 0 }
						if user % 2 == 0 then
							ctx.eta = ALL_ETA
						end
						local list = QR.drawChallenges(user * 7919, period, ctx)
						expect(#list).toBe(3)
						expect(list[1] ~= list[2] and list[2] ~= list[3] and list[1] ~= list[3]).toBe(true)
						for _, id in list do
							expect({ id = id, ok = QR.challengeFeasible(id, ctx) }).toEqual({
								id = id,
								ok = true,
							})
							seen[id] = true
						end
						expect(QR.drawChallenges(user * 7919, period, ctx)).toEqual(list)
					end
				end
				-- tous les Défis faisables finissent par sortir (sauf l'Ascension, interrupteur coupé)
				for id = 1, 12 do
					expect({ id = id, seen = seen[id] == true }).toEqual({ id = id, seen = id ~= 5 })
				end
				-- situation où presque rien n'est faisable (estimations toutes trop longues) : complété
				local tight = {
					eta = { perfects = 1e9, catches = 1e9, newStamps = 1e9, rareHatches = 1e9, combo3 = 1e9 },
					workshopDone = true,
				}
				local list = QR.drawChallenges(42, 2974, tight)
				expect(#list).toBe(3)
				expect(list[1] ~= list[2] and list[2] ~= list[3] and list[1] ~= list[3]).toBe(true)
				expect(QR.drawChallenges(0 / 0, 0 / 0, nil)[3] ~= nil).toBe(true)
			end
		)
	end)

	describe("QuestRules › Carnet du Ranch (carnetTier)", function()
		it("paliers 50, 100, 250, 500, 1 000, 2 500, 5 000, 10 000 (GDD §7.5)", function()
			local cases = {
				[0] = 0,
				[49] = 0,
				[50] = 1,
				[99] = 1,
				[100] = 2,
				[250] = 3,
				[499] = 3,
				[500] = 4,
				[1000] = 5,
				[2500] = 6,
				[4999] = 6,
				[5000] = 7,
				[9999] = 7,
				[10000] = 8,
				[1e9] = 8,
			}
			for n, tier in cases do
				expect({ n = n, tier = QR.carnetTier(n) }).toEqual({ n = n, tier = tier })
			end
			expect(QR.carnetTier(0 / 0)).toBe(0)
			expect(QR.carnetTier(-5)).toBe(0)
			expect(QR.carnetTier(math.huge)).toBe(0) -- illisible : rien
			expect(QR.carnetNext(0)).toBe(50)
			expect(QR.carnetNext(50)).toBe(100)
			expect(QR.carnetNext(9999)).toBe(10000)
			expect(QR.carnetNext(10000)).toBeNil()
		end)
	end)

	describe("QuestRules › zéro trace", function()
		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
