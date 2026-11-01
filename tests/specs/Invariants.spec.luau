--!nocheck
-- Invariants (paquet logic, docs/04 §8.5, §12.1, §17.2) : un profil neuf est sain ; chaque violation
-- est nommée ; tableaux denses, uid, nombres bornés, capacités, Meilleurs Amis, tenues.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local I = h:require("ReplicatedStorage.Shared.Logic.Invariants")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")

	local function rec(extra)
		local r = { s = 1, m = 0, st = 0, z = 1, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100 }
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

		it("Meilleurs Amis : un seul squishy par emplacement", function()
			local d = healthy()
			d.squishies["2"].bf = 1
			expect(has(I.profile(d), "bestFriend.1")).toBe(true)
		end)

		it(
			"tenues : portées par des uid existants, jamais plus que possédées, listes cohérentes",
			function()
				local d = healthy()
				d.outfits.owned.sweater = 1
				d.outfits.worn.sweater = { "1" }
				d.squishies["1"].o = "sweater"
				expect(I.profile(d)).toEqual({})
				d.outfits.worn.sweater = { "1", "2" }
				d.squishies["2"].o = "sweater"
				expect(has(I.profile(d), "outfits.worn.sweater.count")).toBe(true)
				local e = healthy()
				e.outfits.owned.sweater = 2
				e.outfits.worn.sweater = { "77" }
				expect(has(I.profile(e), "outfits.worn.sweater.77")).toBe(true)
				local f = healthy()
				f.squishies["2"].o = "jellyCrown"
				expect(has(I.profile(f), "squishies.2.o.worn")).toBe(true)
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
			d.caps.petSit = 301
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
