--!nocheck
-- Odds (paquet logic, docs/04 §12.1, GDD §4.5, §4.9) : règles exactes des naissances et 1 million de
-- tirages à graine fixe (chaque rareté et chaque mutation à ±3 écarts-types de la table affichée).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local Odds = h:require("ReplicatedStorage.Shared.Logic.Odds")
	local Hash = h:require("ReplicatedStorage.Shared.Logic.Hash")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Species = h:require("ReplicatedStorage.Shared.Config.Species")
	local Mutations = h:require("ReplicatedStorage.Shared.Config.Mutations")

	local function within3Sigma(count, n, p)
		local sigma = math.sqrt(n * p * (1 - p))
		return math.abs(count - n * p) <= 3 * sigma + 1e-9
	end

	describe("Odds › familles et raretés", function()
		it(
			"familles débloquées : Jelly, Kitty, Froggy ; Axolo R ≥ 1 ; Bunny R ≥ 3 ; Spiky R ≥ 5",
			function()
				expect(Odds.unlockedFamilies(0)).toEqual({ jelly = true, kitty = true, froggy = true })
				expect(Odds.unlockedFamilies(1)).toEqual({
					jelly = true,
					kitty = true,
					froggy = true,
					axolo = true,
				})
				expect(Odds.unlockedFamilies(4).bunny).toBe(true)
				expect(Odds.unlockedFamilies(4).spiky).toBeNil()
				expect(Odds.unlockedFamilies(5).spiky).toBe(true)
				expect(Odds.unlockedFamilies(99).secret).toBeNil()
				expect(Odds.unlockedFamilies(0 / 0)).toEqual({ jelly = true, kitty = true, froggy = true })
			end
		)

		it("rarityTable : copie de la table de qualité (bornée à 0 … 8)", function()
			expect(Odds.rarityTable(1)).toEqual({ 74, 21, 4, 0.9, 0.1, 0, 0 })
			expect(Odds.rarityTable(-3)).toEqual(Balance.Vat.Quality[0])
			expect(Odds.rarityTable(42)).toEqual(Balance.Vat.Quality[8])
			local t = Odds.rarityTable(1)
			t[1] = 0
			expect(Balance.Vat.Quality[1][1]).toBe(74)
		end)

		it("rollRarity : tranches cumulées, puis protection (40 → Rare, 150 → Épique)", function()
			expect(Odds.rollRarity(1, 0, 0, 0)).toBe(1)
			expect(Odds.rollRarity(1, 0.7399, 0, 0)).toBe(1)
			expect(Odds.rollRarity(1, 0.74, 0, 0)).toBe(2)
			expect(Odds.rollRarity(1, 0.95, 0, 0)).toBe(3)
			expect(Odds.rollRarity(1, 0.99, 0, 0)).toBe(4)
			expect(Odds.rollRarity(1, 0.9995, 0, 0)).toBe(5)
			expect(Odds.rollRarity(1, 0.1, 39, 0)).toBe(1)
			expect(Odds.rollRarity(1, 0.1, 40, 0)).toBe(3)
			expect(Odds.rollRarity(1, 0.1, 0, 149)).toBe(1)
			expect(Odds.rollRarity(1, 0.1, 0, 150)).toBe(4)
			expect(Odds.rollRarity(1, 0.9995, 40, 150)).toBe(5) -- la protection ne baisse jamais
			expect(Odds.rollRarity(1, 0 / 0, 0, 0)).toBe(1)
		end)
	end)

	describe("Odds › mutations", function()
		it("chances : total 7,6 % (buses 0), 26,6 % (buses 5), 56,2 % (buses 5 + Lune)", function()
			local function total(c)
				local s = 0
				for _, p in c do
					s += p
				end
				return s
			end
			expect(total(Odds.mutationChances(0, false))).toBeNear(0.076045, 1e-9)
			expect(total(Odds.mutationChances(5, false))).toBeNear(0.076045 * 3.5, 1e-9)
			expect(total(Odds.mutationChances(5, true))).toBeNear(0.076045 * 7 + 0.03, 1e-9)
			local c = Odds.mutationChances(5, true)
			expect(c[7]).toBe(0.03) -- Lunaire jamais multipliée par les buses
			expect(c[9]).toBeNear(0.000005 * 3.5 * 2, 1e-15)
			expect(Odds.mutationChances(0, false)[7]).toBe(0)
		end)

		it("multiplicateur qui dépasse 100 % : ramené proportionnellement à 100 %", function()
			local c = Odds.mutationChances(5, true, 2)
			local s = 0
			for _, p in c do
				s += p
			end
			expect(s).toBeNear(1, 1e-12)
			expect(c[1] / c[2]).toBeNear(2, 1e-9)
		end)

		it("rollMutation : un seul nombre, chances cumulées depuis la plus rare (Flop d'abord)", function()
			expect(Odds.rollMutation(0, 0, false)).toBe(9) -- Flop
			expect(Odds.rollMutation(0.000004, 0, false)).toBe(9)
			expect(Odds.rollMutation(0.000006, 0, false)).toBe(8) -- Glitch
			expect(Odds.rollMutation(0.07, 0, false)).toBe(1) -- Gelée en dernier
			expect(Odds.rollMutation(0.5, 0, false)).toBe(0)
			expect(Odds.rollMutation(0.5, 5, true)).toBe(1) -- Gelée : [0,4475 ; 0,532[
			expect(Odds.rollMutation(0.545, 5, true)).toBe(7) -- Lunaire à part, après Gelée : [0,532 ; 0,562[
			expect(Odds.rollMutation(0.99, 5, true)).toBe(0)
		end)
	end)

	describe("Odds › espèces", function()
		local base = { jelly = true, kitty = true, froggy = true }

		it("à chances égales parmi les espèces de la rareté dans les familles débloquées", function()
			-- Communs à R = 0 : Plop (1), Mochi Mew (5), Ribbit Drop (9)
			expect(Odds.speciesFor(1, base, nil, false, 0, 0, false)).toBe(1)
			expect(Odds.speciesFor(1, base, nil, false, 0.34, 0, false)).toBe(5)
			expect(Odds.speciesFor(1, base, nil, false, 0.99, 0, false)).toBe(9)
			-- Mythique à R = 0 : seule Blossompurr (Kitty)
			expect(Odds.speciesFor(6, base, nil, false, 0.5, 0, false)).toBe(8)
		end)

		it("aucune espèce de la rareté : rareté juste en dessous, jusqu'à Commun", function()
			-- Légendaire sans Jelly, Axolo, Spiky : on descend à Épique (Kitty, Froggy)
			local fam = { kitty = true, froggy = true }
			local s = Odds.speciesFor(5, fam, nil, false, 0, 0, false)
			expect(Species.ById[s].rarity).toBe(4)
			-- aucune famille : repli sur Plop
			expect(Odds.speciesFor(3, {}, nil, false, 0.5, 0, false)).toBe(1)
		end)

		it("Secret : Royal Plop ; pendant la Lune, Royal ou Moonplop à chances égales", function()
			expect(Odds.speciesFor(7, base, nil, false, 0.9, 0, false)).toBe(Species.ROYAL)
			expect(Odds.speciesFor(7, base, nil, false, 0.1, 0, true)).toBe(Species.ROYAL)
			expect(Odds.speciesFor(7, base, nil, false, 0.9, 0, true)).toBe(Species.MOON)
		end)

		it("nouveauté garantie : une espèce non tamponnée de la rareté tirée s'il en reste", function()
			local owned = { [1] = true, [5] = true }
			for i = 0, 9 do
				expect(Odds.speciesFor(1, base, owned, true, i / 10, 0, false)).toBe(9)
			end
			-- toutes possédées : tirage normal
			local all = { [1] = true, [5] = true, [9] = true }
			expect(Odds.speciesFor(1, base, all, true, 0, 0, false)).toBe(1)
		end)

		it("espèce publiée plus tard : jamais tirée avant sa date (Species.isReleased)", function()
			local def = Species.ById[3]
			local old = def.release
			def.release = 5000
			for i = 0, 20 do
				expect(Odds.speciesFor(3, base, nil, false, i / 21, 4999, false) ~= 3).toBe(true)
			end
			expect(Odds.speciesFor(3, base, nil, false, 0, 5000, false)).toBe(3)
			def.release = old
		end)
	end)

	describe("Odds › naissance complète", function()
		it("roll : rareté, espèce, mutation, « 1 sur X » et compteurs de protection", function()
			local r = Odds.roll(
				Hash.stream(7),
				{ quality = 1, nozzles = 0, moon = false, unix = 0, families = { jelly = true } }
			)
			expect(Species.ById[r.species].family).toBe("jelly")
			expect(r.rarity).toBe(Species.ById[r.species].rarity)
			expect(r.pityRare == 0 or r.pityRare == 1).toBe(true)
			expect(r.usedNewPull).toBe(false)
		end)

		it("roll : mutation imposée (Golden Doré, Goutte de Lune Lunaire)", function()
			for seed = 1, 50 do
				local r = Odds.roll(
					Hash.stream(seed),
					{ quality = 4, nozzles = 0, moon = false, unix = 0, forceMutation = 4 }
				)
				expect(r.mutation).toBe(4)
			end
		end)

		it("roll : plafond de rareté, compteurs remis à 0 par un Rare+ / Épique+", function()
			for seed = 1, 200 do
				local r = Odds.roll(Hash.stream(seed), {
					quality = 8,
					nozzles = 5,
					moon = true,
					unix = 0,
					maxRarity = 2,
					pityRare = 10,
					pityEpic = 20,
				})
				expect(r.rarity <= 2).toBe(true)
				expect(r.pityRare).toBe(11)
				expect(r.pityEpic).toBe(21)
			end
			local forced = Odds.roll(
				Hash.stream(1),
				{ quality = 1, nozzles = 0, moon = false, unix = 0, pityRare = 40, pityEpic = 150 }
			)
			expect(forced.rarity >= 4).toBe(true)
			expect(forced.pityRare).toBe(0)
			expect(forced.pityEpic).toBe(0)
		end)

		it("roll : déterministe (même graine, même naissance) et contexte abîmé sûr", function()
			local ctx = { quality = 3, nozzles = 2, moon = false, unix = 0 }
			expect(Odds.roll(Hash.stream(99), ctx)).toEqual(Odds.roll(Hash.stream(99), ctx))
			local r = Odds.roll(nil, nil)
			expect(Species.ById[r.species] ~= nil).toBe(true)
		end)

		it("oneIn : Flop Plop au départ = 1 sur 270 000 (GDD §4.5), impossible → 0", function()
			expect(Odds.oneIn(1, 9, 1, 0, false)).toBe(270000)
			expect(Odds.oneIn(8, 0, 1, 0, false)).toBe(0) -- rareté hors table
			expect(Odds.oneIn(1, 7, 1, 0, false)).toBe(0) -- Lunaire hors Lune
			-- sans mutation : 1 / (P(rareté) × (1 − total des mutations))
			local expected = 1 / (0.74 * (1 - 0.076045))
			expect(Odds.oneIn(1, 0, 1, 0, false)).toBe(tonumber(string.format("%.1e", expected)))
		end)

		it("seed : déterministe, différente par compteur et par joueur", function()
			expect(Odds.seed(1, 1)).toBe(Odds.seed(1, 1))
			expect(Odds.seed(1, 1) ~= Odds.seed(1, 2)).toBe(true)
			expect(Odds.seed(1, 1) ~= Odds.seed(2, 1)).toBe(true)
		end)
	end)

	describe("Odds › 1 million de tirages (graine fixe, ±3 écarts-types)", function()
		it("raretés de la table de qualité 4 et mutations des buses 3 (sans Lune)", function()
			local N = 1000000
			local rng = Hash.stream(20261101)
			local rarity = table.create(7, 0)
			local mutation = {}
			for id = 0, Mutations.Count do
				mutation[id] = 0
			end
			local ctx = { quality = 4, nozzles = 3, moon = false, unix = 0, families = nil }
			for _ = 1, N do
				local r = Odds.roll(rng, ctx)
				rarity[r.rarity] += 1
				mutation[r.mutation] += 1
			end
			local row = Balance.Vat.Quality[4]
			for i = 1, 7 do
				expect({ rarity = i, ok = within3Sigma(rarity[i], N, row[i] / 100) }).toEqual({
					rarity = i,
					ok = true,
				})
			end
			local chances = Odds.mutationChances(3, false)
			local none = 1
			for id, p in chances do
				none -= p
				expect({ mutation = id, ok = within3Sigma(mutation[id], N, p) }).toEqual({
					mutation = id,
					ok = true,
				})
			end
			expect(within3Sigma(mutation[0], N, none)).toBe(true)
		end)

		it("pendant la Lune : Lunaire à 3 %, Secrets partagés entre Royal et Moonplop", function()
			local N = 200000
			local rng = Hash.stream(424242)
			local lunar, royal, moon = 0, 0, 0
			local ctx = { quality = 8, nozzles = 5, moon = true, unix = 0 }
			for _ = 1, N do
				local r = Odds.roll(rng, ctx)
				if r.mutation == 7 then
					lunar += 1
				end
				if r.species == Species.ROYAL then
					royal += 1
				elseif r.species == Species.MOON then
					moon += 1
				end
			end
			expect(within3Sigma(lunar, N, 0.03)).toBe(true)
			local secrets = royal + moon
			expect(within3Sigma(secrets, N, 0.0004)).toBe(true)
			expect(math.abs(royal - moon) <= 3 * math.sqrt(secrets) + 1).toBe(true)
		end)
	end)

	describe("Odds › zéro trace", function()
		it("aucune erreur ni aucun avertissement", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
