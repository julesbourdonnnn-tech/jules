--!nocheck
-- Props_Odds (paquet logic, docs/04 §17.1 couche a) : tables à 100 %, naissances toujours valides,
-- « 1 sur X » = inverse du produit des chances, entrées bizarres sûres.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local Odds = h:require("ReplicatedStorage.Shared.Logic.Odds")
	local Hash = h:require("ReplicatedStorage.Shared.Logic.Hash")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Species = h:require("ReplicatedStorage.Shared.Config.Species")
	local Mutations = h:require("ReplicatedStorage.Shared.Config.Mutations")

	local any = Props.anyNumber()
	local families = Props.oneOf({
		nil,
		{},
		{ jelly = true },
		{ jelly = true, kitty = true, froggy = true },
		{ axolo = true, spiky = true },
		{ secret = true },
		{ bunny = true, spiky = true, axolo = true, jelly = true, kitty = true, froggy = true },
	})
	local ctxGen = Props.map(
		Props.tuple(
			any,
			any,
			Props.bool(),
			families,
			Props.maybe(any),
			Props.maybe(any),
			Props.maybe(Props.int(0, 12)),
			Props.maybe(any),
			Props.bool()
		),
		function(v)
			return {
				quality = v[1],
				nozzles = v[2],
				moon = v[3],
				unix = 0,
				families = v[4],
				pityRare = v[5],
				pityEpic = v[6],
				forceMutation = v[7],
				mutationMult = v[8],
				newPull = v[9],
				owned = { [1] = true, [5] = true },
			}
		end
	)

	describe("Props › Odds", function()
		it("chaque table de qualité somme à 100 %", function()
			Props.check(500, Props.int(-5, 15), function(q)
				local sum = 0
				for _, p in Odds.rarityTable(q) do
					sum += p
				end
				return math.abs(sum - 100) < 1e-9
			end)
		end)

		it("chances de mutation : chacune dans [0 ; 1], total ≤ 100 %", function()
			Props.check(4000, Props.tuple(any, Props.bool(), Props.maybe(any)), function(v)
				local c = Odds.mutationChances(v[1], v[2], v[3])
				local total = 0
				for id = 1, Mutations.Count do
					local p = c[id]
					if not (type(p) == "number" and p >= 0 and p <= 1) then
						return false
					end
					total += p
				end
				return total <= 1 + 1e-12
			end)
		end)

		it(
			"roll : espèce connue, rareté de l'espèce, mutation 0 … 9, compteurs ≥ 0, jamais d'erreur",
			function()
				Props.check(6000, Props.tuple(any, ctxGen), function(v)
					local r = Odds.roll(Hash.stream(v[1]), v[2])
					local def = Species.ById[r.species]
					return def ~= nil
						and r.rarity == def.rarity
						and r.mutation >= 0
						and r.mutation <= Mutations.Count
						and r.mutation % 1 == 0
						and r.pityRare >= 0
						and r.pityEpic >= 0
						and r.oneIn >= 0
						and r.oneIn == r.oneIn
				end)
			end
		)

		it(
			"roll : familles respectées (hors repli sur Plop) et Secrets seulement Royal ou Moonplop",
			function()
				Props.check(4000, Props.tuple(any, ctxGen), function(v)
					local ctx = v[2]
					local r = Odds.roll(Hash.stream(v[1]), ctx)
					local def = Species.ById[r.species]
					if def.family == "secret" then
						return r.species == Species.ROYAL or (r.species == Species.MOON and ctx.moon == true)
					end
					if type(ctx.families) == "table" and r.species ~= Species.PLOP then
						return ctx.families[def.family] == true
					end
					return true
				end)
			end
		)

		it("roll : la protection garantit Rare+ (40) et Épique+ (150)", function()
			Props.check(
				3000,
				Props.tuple(any, Props.int(0, 8), Props.int(40, 500), Props.int(0, 500)),
				function(v)
					local r = Odds.roll(Hash.stream(v[1]), {
						quality = v[2],
						nozzles = 0,
						moon = false,
						unix = 0,
						pityRare = v[3],
						pityEpic = v[4],
					})
					if v[4] >= 150 then
						return r.rarity >= 4
					end
					return r.rarity >= 3
				end
			)
		end)

		it(
			"« 1 sur X » : inverse du produit des chances (2 chiffres significatifs), ou 0 si impossible",
			function()
				Props.check(
					4000,
					Props.tuple(
						Props.int(1, 7),
						Props.int(0, 9),
						Props.int(0, 8),
						Props.int(0, 5),
						Props.bool()
					),
					function(v)
						local rarity, mutation, q, n, moon = v[1], v[2], v[3], v[4], v[5]
						local pr = Balance.Vat.Quality[q][rarity] / 100
						local chances = Odds.mutationChances(n, moon)
						local pm
						if mutation == 0 then
							pm = 1
							for _, p in chances do
								pm -= p
							end
						else
							pm = chances[mutation]
						end
						local x = Odds.oneIn(rarity, mutation, q, n, moon)
						if pr * pm <= 0 then
							return x == 0
						end
						local exact = 1 / (pr * pm)
						return x == tonumber(string.format("%.1e", exact))
							and math.abs(x - exact) <= 0.05 * exact
					end
				)
			end
		)

		it("rollRarity / rollMutation / speciesFor : valeurs sûres pour toute entrée", function()
			Props.check(5000, Props.tuple(any, any, any, any, Props.any(), Props.bool()), function(v)
				local rarity = Odds.rollRarity(v[1], v[2], v[3], v[4])
				local mutation = Odds.rollMutation(v[2], v[1], v[6], v[3])
				local species = Odds.speciesFor(v[1], v[5], v[5], v[6], v[2], v[4], v[6])
				return rarity >= 1
					and rarity <= 7
					and mutation >= 0
					and mutation <= 9
					and Species.ById[species] ~= nil
			end)
		end)

		it("unlockedFamilies : croissant en R, jamais les Secrets", function()
			Props.check(2000, Props.int(0, 50), function(R)
				local a, b = Odds.unlockedFamilies(R), Odds.unlockedFamilies(R + 1)
				for key in a do
					if not b[key] then
						return false
					end
				end
				return a.secret == nil
			end)
		end)

		it("seed : entier 32 bits pour tout couple", function()
			Props.check(3000, Props.tuple(any, any), function(v)
				local s = Odds.seed(v[1], v[2])
				return s >= 0 and s < 2 ^ 32 and s % 1 == 0
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
