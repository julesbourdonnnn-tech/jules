--!nocheck
-- Bitset (paquet A1, docs/04 §27.2, §27.7) : ensembles de bits du profil v2 en mots de 32 bits.
-- Bords des mots (31/32/33, 64), indices et mots hostiles, comptage, croissance sans perte, et
-- passage par JSON et Tables.reconcile (200 espèces de maîtrise, 64 objets de Déco perso), comme une
-- sauvegarde DataStore puis un chargement.
local serde = require("@lune/serde")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local Bitset = h:require("ReplicatedStorage.Shared.Logic.Bitset")
	local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")

	-- Référence lente et évidente : liste des bits posés de 1 à n
	local function bitsOf(set, n)
		local out = {}
		for i = 1, n do
			if Bitset.has(set, i) then
				table.insert(out, i)
			end
		end
		return out
	end

	describe("Bitset › mots de 32 bits", function()
		it("new(n) : ceil(n / 32) mots à 0, au moins 1 ; n illisible → 1 mot", function()
			expect(Bitset.new(1)).toEqual({ 0 })
			expect(Bitset.new(32)).toEqual({ 0 })
			expect(Bitset.new(33)).toEqual({ 0, 0 })
			expect(Bitset.new(64)).toEqual({ 0, 0 })
			expect(Bitset.new(65)).toEqual({ 0, 0, 0 })
			expect(#Bitset.new(200)).toBe(7)
			expect(#Bitset.new(Upgrades.CosmeticBits)).toBe(1)
			for _, bad in { 0, -3, 0 / 0, math.huge, -math.huge, "12", nil } do
				expect(#Bitset.new(bad)).toBe(if bad == math.huge then Bitset.MaxBits // 32 else 1)
			end
			-- même taille que les ensembles vides du schéma v2
			local d = Schema.defaultsFor(2)
			expect(#d.decoPerso.owned).toBe(#Bitset.new(64))
			expect(#d.carnet).toBe(#Bitset.new(8))
			expect(#d.atelierCosmetics).toBe(#Bitset.new(Upgrades.CosmeticBits))
		end)

		it("bords des mots : bits 31, 32, 33 et 64 posés, lus et enlevés un par un", function()
			local set = Bitset.new(64)
			for _, i in { 31, 32, 33, 64 } do
				Bitset.set(set, i)
			end
			expect(bitsOf(set, 64)).toEqual({ 31, 32, 33, 64 })
			-- bit 32 = bit de poids fort du 1er mot ; 33 = bit de poids faible du 2e
			expect(set[1]).toBe(2 ^ 30 + 2 ^ 31)
			expect(set[2]).toBe(1 + 2 ^ 31)
			expect(Bitset.count(set)).toBe(4)
			Bitset.clear(set, 32)
			expect(bitsOf(set, 64)).toEqual({ 31, 33, 64 })
			Bitset.clear(set, 33)
			expect(set[2]).toBe(2 ^ 31)
			Bitset.clear(set, 64)
			Bitset.clear(set, 31)
			expect(set).toEqual({ 0, 0 })
			-- poser deux fois, enlever un bit absent : sans effet
			Bitset.set(set, 1)
			Bitset.set(set, 1)
			Bitset.clear(set, 2)
			expect(set).toEqual({ 1, 0 })
			expect(Bitset.count(set)).toBe(1)
		end)

		it("set au-delà de la taille : allonge sans trou ; has hors de l'ensemble : faux", function()
			local set = Bitset.new(8)
			expect(Bitset.has(set, 200)).toBe(false)
			Bitset.set(set, 200)
			expect(#set).toBe(7)
			for w = 1, 7 do
				expect(type(set[w])).toBe("number")
			end
			expect(Bitset.has(set, 200)).toBe(true)
			expect(Bitset.count(set)).toBe(1)
			-- clear d'un bit lointain ne crée aucun mot
			local small = Bitset.new(8)
			Bitset.clear(small, 4000)
			expect(#small).toBe(1)
		end)

		it("indices hostiles : jamais un bit, jamais d'erreur, jamais d'ensemble géant", function()
			local set = Bitset.new(64)
			for _, bad in
				{ 0, -1, 1.5, 0 / 0, math.huge, -math.huge, 1e9, Bitset.MaxBits + 1, "3", true, nil }
			do
				Bitset.set(set, bad)
				Bitset.clear(set, bad)
				expect(Bitset.has(set, bad)).toBe(false)
			end
			expect(set).toEqual({ 0, 0 })
			-- le plus grand indice permis reste possible
			Bitset.set(set, Bitset.MaxBits)
			expect(#set).toBe(Bitset.MaxBits // 32)
			expect(Bitset.has(set, Bitset.MaxBits)).toBe(true)
		end)

		it(
			"mots abîmés (NaN, négatif, ≥ 2^32, non entier, chaîne, trou) : lus comme 0, réparés à l'écriture",
			function()
				local set = { 0 / 0, -5, 2 ^ 32, 1.5, "7" }
				expect(Bitset.count(set)).toBe(0)
				for i = 1, 160 do
					expect(Bitset.has(set, i)).toBe(false)
				end
				Bitset.set(set, 33)
				expect(set[2]).toBe(1)
				Bitset.grow(set, 160)
				expect(set).toEqual({ 0, 1, 0, 0, 0 })
				-- un ensemble qui n'est pas une table : rien, jamais d'erreur
				for _, bad in { nil, 3, "x", true } do
					expect(Bitset.has(bad, 1)).toBe(false)
					expect(Bitset.count(bad)).toBe(0)
					Bitset.set(bad, 1)
					Bitset.clear(bad, 1)
					Bitset.grow(bad, 64)
				end
				-- trou au milieu : grow le bouche avec 0 sans perdre les bits des autres mots
				local holed = { 1 }
				holed[3] = 4
				Bitset.grow(holed, 96)
				expect(holed).toEqual({ 1, 0, 4 })
				expect(bitsOf(holed, 96)).toEqual({ 1, 67 })
			end
		)

		it("grow ne raccourcit jamais et garde chaque bit ; countRange compte une plage", function()
			local set = Bitset.new(64)
			Bitset.set(set, 5)
			Bitset.set(set, 64)
			Bitset.grow(set, 8)
			expect(#set).toBe(2)
			Bitset.grow(set, 200)
			expect(#set).toBe(7)
			expect(bitsOf(set, 224)).toEqual({ 5, 64 })
			expect(Bitset.countRange(set, 1, 6)).toBe(1)
			expect(Bitset.countRange(set, 6, 59)).toBe(1)
			expect(Bitset.countRange(set, 6, 58)).toBe(0)
			expect(Bitset.countRange(set, 0, 10)).toBe(0)
			expect(Bitset.countRange(set, 1, 0 / 0)).toBe(0)
		end)

		it(
			"propriété : 5 000 suites d'opérations = la référence (ensemble Lua) ; mots entiers de [0 ; 2^32[",
			function()
				Props.check(
					5000,
					Props.array(Props.tuple(Props.bool(), Props.int(-5, 140)), 40),
					function(ops)
						local set = Bitset.new(70)
						local ref = {}
						for _, op in ops do
							local add, i = op[1], op[2]
							if add then
								Bitset.set(set, i)
								if i >= 1 then
									ref[i] = true
								end
							else
								Bitset.clear(set, i)
								ref[i] = nil
							end
						end
						local n = 0
						for i = 1, 160 do
							if Bitset.has(set, i) ~= (ref[i] == true) then
								return false
							end
							if ref[i] then
								n += 1
							end
						end
						for _, w in set do
							if type(w) ~= "number" or w ~= w or w < 0 or w >= 2 ^ 32 or w % 1 ~= 0 then
								return false
							end
						end
						return Bitset.count(set) == n
					end
				)
			end
		)
	end)

	describe("Bitset › sauvegarde (JSON) et chargement (reconcile)", function()
		it(
			"200 espèces de maîtrise et 64 objets de Déco perso passent JSON puis reconcile sans perdre un bit",
			function()
				local d = Schema.defaultsFor(2)
				Bitset.grow(d.mastery, 200)
				local mastery = { 1, 26, 31, 32, 33, 64, 65, 96, 97, 128, 150, 199, 200 }
				for _, i in mastery do
					Bitset.set(d.mastery, i)
				end
				local owned = {}
				for i = 1, 64 do
					if i % 3 == 0 or i == 1 or i == 32 or i == 33 or i == 64 then
						Bitset.set(d.decoPerso.owned, i)
						table.insert(owned, i)
					end
				end
				for i = 1, Upgrades.CosmeticBits do
					Bitset.set(d.atelierCosmetics, i)
				end
				local back = serde.decode("json", serde.encode("json", d))
				Tables.reconcile(back, Schema.defaultsFor(2))
				expect(#back.mastery).toBe(7)
				expect(bitsOf(back.mastery, 224)).toEqual(mastery)
				expect(#back.decoPerso.owned).toBe(2)
				expect(bitsOf(back.decoPerso.owned, 64)).toEqual(owned)
				expect(Bitset.count(back.atelierCosmetics)).toBe(Upgrades.CosmeticBits)
				-- chaque mot reste un entier exact (le bit 32 vaut 2^31 : jamais un nombre négatif)
				for _, w in back.decoPerso.owned do
					expect(w >= 0 and w < 2 ^ 32 and w % 1 == 0).toBe(true)
				end
				expect(back.decoPerso.owned[1] >= 2 ^ 31).toBe(true)
			end
		)

		it(
			"une maîtrise d'une seule espèce de plus (26 → 27 espèces) : grow garde l'ancien mot",
			function()
				local d = Schema.defaultsFor(2)
				Bitset.set(d.mastery, 26)
				local back = serde.decode("json", serde.encode("json", d))
				Tables.reconcile(back, Schema.defaultsFor(2))
				Bitset.grow(back.mastery, 27)
				Bitset.set(back.mastery, 27)
				expect(bitsOf(back.mastery, 32)).toEqual({ 26, 27 })
				Bitset.grow(back.mastery, 33)
				expect(#back.mastery).toBe(2)
				expect(bitsOf(back.mastery, 64)).toEqual({ 26, 27 })
			end
		)
	end)
end
