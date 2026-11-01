--!nocheck
-- QuestRules (paquet logic, docs/04 §12.1, GDD §7.3, §7.4, §4.17) : « Proposé si », tirage
-- déterministe, relance, progression, minuit en session, paliers, Squishydex.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
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

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
