--!nocheck
-- ProfileRepair : défauts trouvés par la revue adverse du paquet ranch (chaque test a d'abord échoué).
-- Un squishy déplacé par la règle des capacités ne perd ni ne gagne jamais de taille :
--   * enclos / Bassin → Dodo ou Lettres (capacité réduite : pass Grand Ranch remboursé, profil abîmé) :
--     sa taille du moment z + (G − zg) est figée dans z (zg = 0), comme MoveSquishy vers le Dodo ;
--   * Dodo / Lettres → enclos (Lettres pleines) : zg = G, sa taille reste z (jamais + G offert).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local Repair = h:require("ServerScriptService.Server.Data.ProfileRepair")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")
	local Invariants = h:require("ReplicatedStorage.Shared.Logic.Invariants")
	local Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas")

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 0, z = 1, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	describe(
		"ProfileRepair (revue) › tailles gardées quand la règle des capacités déplace un squishy",
		function()
			it(
				"pass Grand Ranch retiré : le surplus de l'enclos dort au Dodo avec sa taille du moment",
				function()
					local d = Schema.defaults()
					d.growth = { G = 1e6, g = 1, t = 0 }
					for i = 1, 10 do
						d.squishies[tostring(i)] =
							rec({ s = i, z = 1 + i, zg = 100 * i, bf = if i == 1 then 1 else 0 })
					end
					d.nextUid = 37
					d.passes = {} -- Grand Ranch retiré : 4 places au lieu de 10
					local before = {}
					for uid, r in d.squishies do
						before[uid] = Formulas.sizeAt(r, d.growth.G)
					end
					local fixes = Repair.repair(d)
					expect(#fixes > 0).toBe(true)
					local moved = 0
					for uid, r in d.squishies do
						if r.at == "dodo" then
							moved += 1
							expect(r.zg).toBe(0)
						end
						expect(Formulas.sizeAt(r, d.growth.G)).toBe(before[uid])
					end
					expect(moved).toBe(6)
					expect(Invariants.profile(d)).toEqual({})
					-- idempotent
					expect(Repair.repair(d)).toEqual({})
				end
			)

			it(
				"Lettres pleines (21) et enclos libre : le 21e va à l'enclos sans grandir d'un coup",
				function()
					local d = Schema.defaults()
					d.growth = { G = 5e5, g = 1, t = 0 }
					for i = 1, 21 do
						d.squishies[tostring(i)] = rec({ s = 2, z = 7, zg = 0, at = "mail" })
					end
					d.nextUid = 37
					local fixes = Repair.repair(d)
					expect(#fixes > 0).toBe(true)
					local inPen = 0
					for _, r in d.squishies do
						if r.at == "pen" then
							inPen += 1
						end
						expect(Formulas.sizeAt(r, d.growth.G)).toBe(7)
					end
					expect(inPen).toBe(1)
					expect(Invariants.profile(d)).toEqual({})
					expect(Repair.repair(d)).toEqual({})
				end
			)
		end
	)
end
