--!nocheck
-- Props_QuestRules (paquet logic, docs/04 §17.1 couche a) : tirages toujours proposables, progression
-- bornée, comptes du Squishydex bornés, entrées bizarres sûres.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local QR = h:require("ReplicatedStorage.Shared.Logic.QuestRules")
	local Quests = h:require("ReplicatedStorage.Shared.Config.Quests")

	local any = Props.anyNumber()
	local ctxGen = Props.map(
		Props.tuple(any, any, any, Props.oneOf({ true, false, nil }), any, any),
		function(v)
			return {
				R = v[1],
				tilesLeft = v[2],
				megaIn = v[3],
				friendOnServer = v[4],
				splorchEta = v[5],
				stamps = v[6],
			}
		end
	)
	local dexGen = Props.map(Props.tuple(Props.array(any, 30), Props.array(any, 30)), function(v)
		return { mut = v[1], stars = v[2], rewards = 0 }
	end)

	describe("Props › QuestRules", function()
		it(
			"draw : 3 objectifs (facile, moyen, difficile) toujours proposables, pour toute situation",
			function()
				Props.check(4000, Props.tuple(any, Props.int(0, 100000), ctxGen), function(v)
					local list = QR.draw(v[1], v[2], v[3], false)
					if #list ~= 3 then
						return false
					end
					local tiers = { "easy", "medium", "hard" }
					for i, id in list do
						local def = Quests.Objectives[id]
						if not def or def.tier ~= tiers[i] then
							return false
						end
						-- « always » existe dans chaque niveau : le tirage est toujours proposable
						if not QR.eligible(def, v[3]) then
							return false
						end
					end
					return true
				end)
			end
		)

		it("reroll : même niveau, hors des 3 actuels (sauf s'il n'y a aucun autre choix)", function()
			Props.check(
				4000,
				Props.tuple(any, Props.int(0, 100000), ctxGen, Props.int(1, 3), any),
				function(v)
					local current = QR.draw(v[1], v[2], v[3], false)
					local id = QR.reroll(v[1], v[2], current, v[4], v[3], v[5])
					local def = Quests.Objectives[id]
					local old = Quests.Objectives[current[v[4]]]
					if not def or def.tier ~= old.tier then
						return false
					end
					return id == current[v[4]] or table.find(current, id) == nil
				end
			)
		end)

		it("apply : 0 ≤ p ≤ but, terminé ⇔ p = but, jamais d'erreur", function()
			local entryGen = Props.map(Props.tuple(Props.int(-1, 20), any, Props.bool()), function(v)
				return { id = v[1], p = v[2], done = v[3], claimed = false }
			end)
			local stats = Props.oneOf({ "press", "perfect", "perfectStreak", "fusion", "stamps", "??", nil })
			Props.check(
				6000,
				Props.tuple(entryGen, stats, any, Props.oneOf({ true, false, nil })),
				function(v)
					local out = QR.apply(v[1], v[2], v[3], v[4])
					local def = Quests.Objectives[out.id]
					if type(out.p) ~= "number" or out.p ~= out.p or out.p < 0 then
						return false
					end
					if def and def.id == out.id and not v[1].done then
						return out.p <= def.goal and (out.done == (out.p >= def.goal))
					end
					return true
				end
			)
		end)

		it(
			"rollover : chaque objectif non réclamé est gardé ou réclamé, jamais perdu ni doublé",
			function()
				local entryGen = Props.map(
					Props.tuple(Props.int(1, 18), Props.bool(), Props.bool()),
					function(v)
						return { id = v[1], p = 1, done = v[2], claimed = v[3] }
					end
				)
				Props.check(4000, Props.tuple(Props.array(entryGen, 3), Props.bool()), function(v)
					local kept, claim = QR.rollover(v[1], v[2])
					local unclaimed = 0
					for _, e in v[1] do
						if not e.claimed then
							unclaimed += 1
						end
					end
					return #kept + #claim == unclaimed
				end)
			end
		)

		it("Squishydex : comptes bornés (260 tampons, 130 badges, 26 pages) pour tout tableau", function()
			Props.check(4000, dexGen, function(d)
				local stamps, badges, pages = QR.stampCount(d), QR.starBadges(d), QR.goldenPages(d)
				return stamps >= 0
					and stamps <= 260
					and badges >= 0
					and badges <= 130
					and pages >= 0
					and pages <= 26
			end)
		end)

		it("isNewStamp, familyComplete, familyEarned, plopReward, dexMilestones : jamais d'erreur", function()
			Props.check(4000, Props.tuple(dexGen, any, any, any, Props.any()), function(v)
				local a = QR.isNewStamp(v[1], v[2], v[3], v[4])
				local b = QR.familyComplete(v[1], v[5])
				local e = QR.familyEarned(v[1], v[5])
				local r = QR.plopReward(v[2])
				local m = QR.dexMilestones(v[3], v[4])
				return type(a) == "boolean"
					and type(b) == "boolean"
					and type(e) == "boolean"
					and (r == nil or type(r) == "table")
					and type(m) == "table"
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
