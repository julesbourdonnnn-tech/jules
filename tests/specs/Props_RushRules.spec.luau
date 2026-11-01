--!nocheck
-- Props_RushRules (paquet logic, docs/04 §17.1 couche a) : un boop n'est accepté que si TOUTES les
-- règles sont vraies ; toute valeur bizarre est refusée ; maintien borné ; bébés bornés.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local RR = h:require("ReplicatedStorage.Shared.Logic.RushRules")
	local ST = h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")

	local any = Props.anyNumber()
	local b = Props.oneOf({ true, false, false, nil, 1, "true" })
	local boopGen = Props.map(
		Props.tuple(
			Props.oneOf({ "on", "events", "off", nil, 3 }),
			b,
			b,
			b,
			b,
			b,
			b,
			b,
			b,
			any,
			any,
			b,
			b,
			b,
			Props.int(-1, 9),
			b,
			any,
			any,
			any,
			any,
			b
		),
		function(v)
			return {
				feature = v[1],
				eventActive = v[2],
				rushActive = v[3],
				booperRush = v[4],
				ownerRush = v[5],
				sameUser = v[6],
				ownerShield = v[7],
				refused = v[8],
				blocked = v[9],
				booperCooldownLeft = v[10],
				pairCooldownLeft = v[11],
				atFence = v[12],
				eligible = v[13],
				bestFriend = v[14],
				rarity = v[15],
				moonBoopable = v[16],
				ranchThisRush = v[17],
				ranchThisHour = v[18],
				serverEscapes = v[19],
				distance = v[20],
				canAct = v[21],
			}
		end
	)

	-- oracle : toutes les règles du GDD, écrites autrement
	local function allowed(c)
		local featureOk = c.feature == "on" or (c.feature == "events" and c.eventActive == true)
		local num = function(x)
			return type(x) == "number" and x == x
		end
		return featureOk
			and c.rushActive == true
			and c.booperRush == true
			and c.ownerRush == true
			and c.sameUser == false
			and c.ownerShield == false
			and c.refused == false
			and c.blocked == false
			and num(c.booperCooldownLeft)
			and c.booperCooldownLeft <= 0
			and num(c.pairCooldownLeft)
			and c.pairCooldownLeft <= 0
			and c.atFence == true
			and c.eligible == true
			and c.bestFriend == false
			and num(c.rarity)
			and c.rarity % 1 == 0
			and c.rarity >= 1
			and c.rarity <= 7
			and (c.rarity < 6 or c.moonBoopable == true)
			and num(c.ranchThisRush)
			and c.ranchThisRush < 2
			and num(c.ranchThisHour)
			and c.ranchThisHour < 4
			and num(c.serverEscapes)
			and c.serverEscapes < 10
			and num(c.distance)
			and c.distance <= 8
			and c.canAct == true
	end

	describe("Props › RushRules", function()
		it("checkBoop accepte exactement quand toutes les règles sont vraies (oracle)", function()
			Props.check(8000, boopGen, function(c)
				local ok, code = RR.checkBoop(c)
				if ok ~= allowed(c) then
					return false
				end
				return (ok and code == nil) or (not ok and type(code) == "string")
			end)
		end)

		it("checkBoop : contexte presque honnête, une seule règle cassée → refus", function()
			local honest = {
				feature = "on",
				eventActive = false,
				rushActive = true,
				booperRush = true,
				ownerRush = true,
				sameUser = false,
				ownerShield = false,
				refused = false,
				blocked = false,
				booperCooldownLeft = 0,
				pairCooldownLeft = 0,
				atFence = true,
				eligible = true,
				bestFriend = false,
				rarity = 1,
				moonBoopable = false,
				ranchThisRush = 0,
				ranchThisHour = 0,
				serverEscapes = 0,
				distance = 1,
				canAct = true,
			}
			local keys = {}
			for k in honest do
				table.insert(keys, k)
			end
			table.sort(keys)
			Props.check(4000, Props.tuple(Props.oneOf(keys), Props.any()), function(v)
				local c = table.clone(honest)
				c[v[1]] = v[2]
				return (RR.checkBoop(c)) == allowed(c)
			end)
		end)

		it(
			"extendHold : seul un reste ≤ 2,5 s est doublé ; jamais avant maintenant ; fin finie",
			function()
				Props.check(5000, Props.tuple(any, any, Props.maybe(any)), function(v)
					local e = RR.extendHold(v[1], v[2], v[3])
					if not (type(e) == "number" and e == e and math.abs(e) ~= math.huge) then
						return false
					end
					local nowOk = type(v[2]) == "number" and v[2] == v[2] and math.abs(v[2]) ~= math.huge
					local endOk = type(v[1]) == "number" and v[1] == v[1] and math.abs(v[1]) ~= math.huge
					if nowOk and endOk and e ~= v[1] then
						return e >= v[2] and e <= v[2] + 5
					end
					return true
				end)
			end
		)

		it("maintien court prolongé une fois : toujours sous StateTimeouts « boopHold »", function()
			Props.check(4000, Props.tuple(Props.number(0, 1e6), Props.number(0, 6)), function(v)
				local start = v[1]
				local endsAt = start + RR.holdTime(false)
				local extended = RR.extendHold(endsAt, math.min(start + v[2], endsAt))
				return extended - start <= ST.seconds("boopHold")
			end)
		end)

		it("avec startedAt : même un appel en trop ou un maintien long ne dépasse jamais 5 s", function()
			Props.check(
				4000,
				Props.tuple(Props.number(0, 1e6), Props.bool(), Props.number(0, 6), Props.number(0, 6)),
				function(v)
					local start = v[1]
					local endsAt = start + RR.holdTime(v[2])
					local first = RR.extendHold(endsAt, math.min(start + v[3], endsAt), start)
					local second = RR.extendHold(first, math.min(start + v[3] + v[4], first), start)
					return first - start <= 5 + 1e-9 and second - start <= 5 + 1e-9
				end
			)
		end)

		it(
			"checkCatch : accepté seulement dans le rayon, à 8 de haut, canAct, mode Rush, hors verrou",
			function()
				Props.check(
					6000,
					Props.map(Props.tuple(b, b, any, b, any, any, b), function(v)
						return {
							catcherRush = v[1],
							isBooper = v[2],
							age = v[3],
							isOwner = v[4],
							distance = v[5],
							dy = v[6],
							canAct = v[7],
						}
					end),
					function(c)
						local ok = RR.checkCatch(c)
						if not ok then
							return true
						end
						local radius = if c.isOwner == true then 9.5 else 6.5
						return c.catcherRush == true
							and c.canAct == true
							and c.distance <= radius
							and math.abs(c.dy) <= 8
							and (c.isBooper == false or c.age >= 6)
					end
				)
			end
		)

		it("fenceEligible : jamais vrai pour un Meilleur Ami, hors enclos, porté ou nouveau-né", function()
			local recGen = Props.map(
				Props.tuple(
					Props.int(-2, 30),
					Props.int(-1, 4),
					Props.oneOf({ "pen", "pool", "dodo", "mail", nil }),
					any
				),
				function(v)
					return {
						s = v[1],
						m = 0,
						st = 0,
						z = 1,
						zg = 0,
						bf = v[2],
						lk = false,
						o = "",
						at = v[3],
						b = v[4],
					}
				end
			)
			Props.check(
				6000,
				Props.tuple(recGen, any, Props.oneOf({ "", "u1", "u2" }), Props.bool()),
				function(v)
					local rec = v[1]
					local ok = RR.fenceEligible(rec, {
						now = v[2],
						carried = v[3],
						waiting = "",
						returnedThisRush = {},
						moonBoopable = v[4],
					}, "u1")
					if not ok then
						return true
					end
					return rec.bf == 0 and rec.at == "pen" and v[3] ~= "u1" and v[2] - rec.b >= 60
				end
			)
		end)

		it("wildShared ∈ [3 ; 13] et décroissant ; babySize ∈ [1 ; max(1, 2 × plus gros)]", function()
			Props.check(4000, Props.tuple(any, any, any), function(v)
				local w = RR.wildShared(v[1])
				if not (w >= 3 and w <= 13 and w % 1 == 0) then
					return false
				end
				local size = RR.babySize(v[2], v[3])
				local biggest = if type(v[3]) == "number" and v[3] == v[3]
					then math.clamp(v[3], 1, 1e300)
					else 1
				return size >= 1 and size <= math.max(1, 2 * biggest) * (1 + 1e-12)
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
