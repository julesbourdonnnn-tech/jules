--!nocheck
-- Invariants (paquet logic, docs/04 §8.5, §12.1, §17.2) : un profil neuf est sain ; chaque violation
-- est nommée ; tableaux denses, uid, nombres bornés, capacités, Meilleurs Amis, tenues.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local I = h:require("ReplicatedStorage.Shared.Logic.Invariants")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 0, z = 1, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end
	local function healthy()
		local d = Schema.defaults()
		d.squishies = { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 5, at = "pool" }) }
		d.nextUid = 3
		return d
	end
	local function has(list, path)
		return table.find(list, path) ~= nil
	end

	describe("Invariants", function()
		it("profil neuf (Schema.defaults) et profil de jeu ordinaire : aucune violation", function()
			expect(I.profile(Schema.defaults())).toEqual({})
			expect(I.profile(healthy())).toEqual({})
		end)

		it(
			"nombres : pièces, Pot, Fame, G hors bornes, NaN, infini, pièces non entières sous 1e15",
			function()
				local d = healthy()
				d.coins = -1
				d.pot = 0 / 0
				d.fame = math.huge
				d.growth.G = -5
				local v = I.profile(d)
				expect(has(v, "coins")).toBe(true)
				expect(has(v, "pot")).toBe(true)
				expect(has(v, "fame")).toBe(true)
				expect(has(v, "growth.G")).toBe(true)
				local e = healthy()
				e.coins = 10.5
				expect(has(I.profile(e), "coins.integer")).toBe(true)
				local f = healthy()
				f.coins = 2e15 + 0.5
				expect(I.profile(f)).toEqual({})
			end
		)

		it("squishies : champs nommés (taille, espèce, lieu, uid, nextUid)", function()
			local d = healthy()
			d.squishies["2"].z = 0
			d.squishies["2"].s = 99
			d.squishies["2"].at = "moon"
			d.squishies["Bad!"] = rec()
			d.squishies["9"] = rec()
			local v = I.profile(d)
			expect(has(v, "squishies.2.z")).toBe(true)
			expect(has(v, "squishies.2.s")).toBe(true)
			expect(has(v, "squishies.2.at")).toBe(true)
			expect(has(v, "squishies.Bad!.uid")).toBe(true)
			expect(has(v, "squishies.9.nextUid")).toBe(true) -- uid ≥ nextUid : collision future
		end)

		it("capacités : enclos + Bassin ≤ 24, Bassin ≤ 6, Dodo ≤ 60, Lettres ≤ 20", function()
			local d = healthy()
			d.squishies = {}
			for i = 1, 25 do
				d.squishies[tostring(i)] = rec() -- « 1 » … « 25 » en base 36 : tous < 100
			end
			d.nextUid = 100
			expect(has(I.profile(d), "capacity.pen")).toBe(true)
			local e = healthy()
			e.squishies = {}
			for i = 1, 7 do
				e.squishies[tostring(i)] = rec({ at = "pool" })
			end
			e.nextUid = 100
			expect(has(I.profile(e), "capacity.pool")).toBe(true)
			local f = healthy()
			f.squishies = {}
			for i = 1, 21 do
				f.squishies[tostring(i)] = rec({ at = "mail" })
			end
			f.nextUid = 100
			expect(has(I.profile(f), "capacity.mail")).toBe(true)
		end)

		it(
			"capacités du joueur (§17.2 n° 3) : enclos + Bassin ≤ penCapacity, Bassin ≤ poolSlots",
			function()
				-- dalle Enclos au niveau 0, sans Grand Ranch : 4 places (le profil sain en a 2)
				local d = healthy()
				for i = 3, 5 do
					d.squishies[tostring(i)] = rec()
				end
				d.nextUid = 100
				expect(has(I.profile(d), "capacity.pen")).toBe(true) -- 5 pour 4 places
				d.tiles.pens = 1
				expect(has(I.profile(d), "capacity.pen")).toBe(false) -- 5 places
				d.tiles.pens = 0
				d.passes.BigRanch = true
				expect(has(I.profile(d), "capacity.pen")).toBe(false) -- 4 + 6 places
				-- Bassin : 5 places, 6 avec le bonus Axolo gagné pour toujours (dex.fam)
				local e = healthy()
				e.squishies = {}
				for i = 1, 6 do
					e.squishies[tostring(i)] = rec({ at = "pool" })
				end
				e.tiles.pens = 5
				e.nextUid = 100
				expect(has(I.profile(e), "capacity.pool")).toBe(true)
				local Species = h:require("ReplicatedStorage.Shared.Config.Species")
				e.dex.fam[table.find(Species.FamilyOrder, "axolo")] = 1
				expect(has(I.profile(e), "capacity.pool")).toBe(false)
			end
		)

		it("Meilleurs Amis : un seul squishy par emplacement", function()
			local d = healthy()
			d.squishies["2"].bf = 1
			expect(has(I.profile(d), "bestFriend.1")).toBe(true)
		end)

		it(
			"tenues (contrat v1.2) : porteurs dérivés de squishies[uid].o, jamais plus que possédées ; worn vide",
			function()
				local d = healthy()
				d.outfits.owned.sweater = 1
				d.squishies["1"].o = "sweater"
				expect(I.profile(d)).toEqual({}) -- worn = {} (Schema) : accepté
				d.outfits.worn = nil
				expect(I.profile(d)).toEqual({}) -- worn absent : accepté
				d.squishies["2"].o = "sweater" -- 2 porteurs pour 1 exemplaire
				expect(has(I.profile(d), "outfits.owned.sweater.count")).toBe(true)
				d.outfits.owned.sweater = 2
				expect(I.profile(d)).toEqual({})
				-- tenue jamais possédée
				local f = healthy()
				f.squishies["2"].o = "jellyCrown"
				expect(has(I.profile(f), "outfits.owned.jellyCrown.count")).toBe(true)
				-- worn obsolète : toujours vide (§17.2 invariant 4)
				local g = healthy()
				g.outfits.owned.sweater = 1
				g.outfits.worn.sweater = { "1" }
				g.squishies["1"].o = "sweater"
				expect(has(I.profile(g), "outfits.worn")).toBe(true)
				-- owned abîmé : nombres entiers ≥ 0
				local k = healthy()
				k.outfits.owned.sweater = -1
				expect(has(I.profile(k), "outfits.owned.sweater")).toBe(true)
				k.outfits.owned.sweater = 0 / 0
				expect(has(I.profile(k), "outfits.owned.sweater")).toBe(true)
				local m = healthy()
				m.outfits.owned = nil
				expect(has(I.profile(m), "outfits")).toBe(true)
			end
		)

		it(
			"contrat v1.2 : dex.fam dense en 0/1, caps.petSitBy ≤ CapsPerFriend.petSit, gd entier ≥ 0",
			function()
				local B = h:require("ReplicatedStorage.Shared.Config.Balance")
				local Species = h:require("ReplicatedStorage.Shared.Config.Species")
				-- dex.fam
				local d = healthy()
				expect(#d.dex.fam).toBe(#Species.FamilyOrder)
				d.dex.fam[2] = 1
				expect(I.profile(d)).toEqual({})
				d.dex.fam[2] = 2
				expect(has(I.profile(d), "dex.fam")).toBe(true)
				d.dex.fam[2] = true
				expect(has(I.profile(d), "dex.fam")).toBe(true)
				d.dex.fam = { 0, 1 } -- trop court
				expect(has(I.profile(d), "dex.fam")).toBe(true)
				d.dex.fam = { [1] = 0, [3] = 1 } -- à trous
				expect(has(I.profile(d), "dex.fam")).toBe(true)
				d.dex.fam = nil
				expect(has(I.profile(d), "dex.fam")).toBe(true)
				-- caps.petSitBy
				local e = healthy()
				e.caps.petSitBy["123456"] = B.CapsPerFriend.petSit
				e.caps.petSitBy["-1"] = 0 -- joueur de test de Studio
				expect(I.profile(e)).toEqual({})
				e.caps.petSitBy["123456"] = B.CapsPerFriend.petSit + 1
				expect(has(I.profile(e), "caps.petSitBy.123456")).toBe(true)
				e.caps.petSitBy["123456"] = 2.5
				expect(has(I.profile(e), "caps.petSitBy.123456")).toBe(true)
				e.caps.petSitBy["123456"] = 0 / 0
				expect(has(I.profile(e), "caps.petSitBy.123456")).toBe(true)
				local f = healthy()
				f.caps.petSitBy[123456] = 3 -- clé nombre : table mixte refusée par le DataStore
				expect(has(I.profile(f), "caps.petSitBy.123456")).toBe(true)
				f.caps.petSitBy = "x"
				expect(has(I.profile(f), "caps.petSitBy")).toBe(true)
				-- plafonds scalaires du contrat v1.2 vérifiés comme les autres
				local c = healthy()
				c.caps.petSitIn = B.Caps.petSitIn + 1
				c.caps.splorchCoins = -1
				local v = I.profile(c)
				expect(has(v, "caps.petSitIn")).toBe(true)
				expect(has(v, "caps.splorchCoins")).toBe(true)
				-- gd : entier ≥ 0
				local g = healthy()
				g.squishies["1"].gd = 20400
				expect(I.profile(g)).toEqual({})
				for _, bad in { -1, 1.5, 0 / 0, math.huge, "3" } do
					g.squishies["1"].gd = bad
					expect({ bad = tostring(bad), hit = has(I.profile(g), "squishies.1.gd") }).toEqual({
						bad = tostring(bad),
						hit = true,
					})
				end
				g.squishies["1"].gd = nil
				expect(has(I.profile(g), "squishies.1.gd")).toBe(true)
			end
		)

		it("tableaux denses d'une case par espèce (trophées, Squishydex)", function()
			local d = healthy()
			d.trophies[3] = nil
			d.dex.mut = { 1, 2 }
			local v = I.profile(d)
			expect(has(v, "trophies")).toBe(true)
			expect(has(v, "dex.mut")).toBe(true)
		end)

		it("niveaux bornés : dalles, plafonds du jour, Cuve, monture", function()
			local d = healthy()
			d.tiles.snack = 13
			d.caps.petSit = 101
			d.vat.newPulls = 4
			d.mount = "zz"
			local v = I.profile(d)
			expect(has(v, "tiles.snack")).toBe(true)
			expect(has(v, "caps.petSit")).toBe(true)
			expect(has(v, "vat.newPulls")).toBe(true)
			expect(has(v, "mount")).toBe(true)
		end)

		it("number, dense, uid", function()
			expect(I.number(5, 0, 10)).toBe(true)
			expect(I.number(0 / 0, 0, 10)).toBe(false)
			expect(I.number(math.huge, 0, math.huge)).toBe(false)
			expect(I.number("5", 0, 10)).toBe(false)
			expect(I.dense({})).toBe(true)
			expect(I.dense({ 1, 2, 3 })).toBe(true)
			expect(I.dense({ 1, nil, 3 })).toBe(false)
			expect(I.dense({ 1, 2, x = 3 })).toBe(false)
			expect(I.dense({ [0] = 1 })).toBe(false)
			expect(I.dense("x")).toBe(false)
			expect(I.uid("1")).toBe(true)
			expect(I.uid("zzzzzzzz")).toBe(true)
			expect(I.uid("zzzzzzzzz")).toBe(false)
			expect(I.uid("")).toBe(false)
			expect(I.uid("A1")).toBe(false)
			expect(I.uid(12)).toBe(false)
		end)

		it("profil illisible : une violation, jamais d'erreur", function()
			expect(I.profile(nil)).toEqual({ "profile" })
			expect(#I.profile({}) > 10).toBe(true)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
