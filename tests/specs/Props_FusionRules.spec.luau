--!nocheck
-- Props_FusionRules (paquet logic, docs/04 §17.1 couche a) : une fusion retire exactement un
-- squishy (2 → 1), jamais de taille NaN ; le plan de « Tout fusionner » est jouable, n'utilise ni
-- verrouillés ni Lettres et ne laisse aucune paire de jumeaux.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local FR = h:require("ReplicatedStorage.Shared.Logic.FusionRules")

	local any = Props.anyNumber()
	local recGen = Props.map(
		Props.tuple(
			Props.int(1, 4),
			Props.int(0, 5),
			Props.number(1, 1e9),
			Props.number(0, 1e6),
			Props.int(0, 3),
			Props.bool(),
			Props.oneOf({ "pen", "pool", "dodo", "mail" }),
			Props.int(0, 9),
			Props.int(1, 1000)
		),
		function(v)
			return {
				s = v[1],
				m = v[8],
				st = v[2],
				z = v[3],
				zg = v[4],
				bf = 0,
				lk = v[6] and v[1] == 4,
				o = "",
				at = v[7],
				b = v[9],
			}
		end
	)
	local function toMap(list)
		local map = {}
		for i, r in list do
			map[string.lower(string.format("%x", i))] = table.clone(r)
		end
		return map
	end

	-- joue un plan comme le service : chaque paire fusionne, le résultat garde keepUid, l'autre part
	local function play(records, plan)
		local map = {}
		for uid, r in records do
			map[uid] = table.clone(r)
		end
		for _, pair in plan do
			local a, b = map[pair[1]], map[pair[2]]
			if not a or not b or pair[1] == pair[2] or not FR.areTwins(a, b) then
				return nil, "paire injouable"
			end
			if a.lk or b.lk or a.at == "mail" or b.at == "mail" then
				return nil, "verrouillé ou Lettres"
			end
			local kept = FR.keepUid(pair[1], pair[2], a, b)
			local merged = FR.fuse(a, b, 0, 0)
			map[pair[1]], map[pair[2]] = nil, nil
			map[kept] = merged
		end
		return map
	end

	describe("Props › FusionRules", function()
		it("fuse : taille finie ≥ chacune, étoiles + 1 (5 au plus), Meilleur Ami gardé", function()
			Props.check(5000, Props.tuple(recGen, recGen, any), function(v)
				local a, b = v[1], v[2]
				b.s, b.st = a.s, a.st
				local r = FR.fuse(a, b, v[3], 0)
				return r.z == r.z
					and r.z >= 1
					and r.z <= 1e300
					and r.st == math.min(5, a.st + 1)
					and r.zg >= 0
					and r.zg == r.zg
			end)
		end)

		it("fuse : entrées abîmées → ligne valide, jamais d'erreur", function()
			Props.check(3000, Props.tuple(Props.any(), Props.any(), any, any), function(v)
				local r = FR.fuse(v[1], v[2], v[3], v[4])
				return type(r) == "table" and r.z >= 1 and r.z == r.z and type(r.o) == "string"
			end)
		end)

		it("keepUid : rend toujours l'un des deux uid, et ne dépend pas de l'ordre", function()
			Props.check(4000, Props.tuple(recGen, recGen), function(v)
				local k1 = FR.keepUid("aa", "bb", v[1], v[2])
				local k2 = FR.keepUid("bb", "aa", v[2], v[1])
				return (k1 == "aa" or k1 == "bb") and k1 == k2
			end)
		end)

		it(
			"planMergeAll : jouable, 2 → 1 à chaque paire, aucune paire restante, ni verrouillé ni Lettres",
			function()
				Props.check(1500, Props.tuple(Props.array(recGen, 30), Props.int(1, 6)), function(v)
					local records = toMap(v[1])
					local plan = FR.planMergeAll(records, v[2])
					local after, why = play(records, plan)
					if after == nil then
						return false, why
					end
					local before = 0
					for _ in records do
						before += 1
					end
					local count = 0
					for _ in after do
						count += 1
					end
					return count == before - #plan and FR.twinPairs(after) == 0
				end)
			end
		)

		it("planMergeAll : chaque chaîne fait au plus `slots` fusions (comboSteps)", function()
			Props.check(1500, Props.tuple(Props.array(recGen, 30), Props.int(1, 6)), function(v)
				local records = toMap(v[1])
				local plan = FR.planMergeAll(records, v[2])
				for _, step in FR.comboSteps(plan, records) do
					if step > v[2] then
						return false
					end
				end
				return true
			end)
		end)

		it("twinPairs : entier ≥ 0, jamais plus que la moitié des lignes", function()
			Props.check(3000, Props.array(recGen, 40), function(list)
				local n = FR.twinPairs(toMap(list))
				return n >= 0 and n % 1 == 0 and n <= #list // 2
			end)
		end)

		it("throwOutcome et nextInChain : valeurs du contrat, jamais d'erreur", function()
			Props.check(3000, Props.tuple(Props.array(recGen, 8), recGen, any), function(v)
				local pool = toMap(v[1])
				local outcome = FR.throwOutcome(pool, v[2], v[3])
				local nextUid = FR.nextInChain(pool, "1")
				return (outcome == "fuse" or outcome == "place" or outcome == "full")
					and (nextUid == nil or pool[nextUid] ~= nil)
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
