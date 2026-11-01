--!nocheck
-- ProfileRepair (paquet ranch, docs/04 §8.5, §11.15, §18.2, GDD §12.6) : réparation en place, nommée,
-- idempotente, sans erreur sur un profil hostile ; profil réparé = profil sain (Invariants), jamais de
-- donnée valide perdue (64 espèces jamais tronquées, espèces futures gardées, clé coinBuy ignorée).
-- Note INT-REPAIR : appelée par DataService après migrate + reconcile, avant onPrepare ; ProfileRepaired
-- émis après Loaded.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local Repair = h:require("ServerScriptService.Server.Data.ProfileRepair")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")
	local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")
	local Invariants = h:require("ReplicatedStorage.Shared.Logic.Invariants")
	local Species = h:require("ReplicatedStorage.Shared.Config.Species")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Props = require("../harness/Props")

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 0, z = 1, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end
	local function has(list, path)
		return table.find(list, path) ~= nil
	end
	local function fresh()
		local d = Schema.defaults()
		d.squishies = { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 5, at = "pool" }) }
		d.nextUid = 3
		return d
	end
	-- même préparation que DataService : migrate + reconcile, puis réparation
	local function load(raw)
		local d = raw
		Tables.reconcile(d, Schema.defaults())
		return d, Repair.repair(d)
	end

	describe("ProfileRepair", function()
		it("profil neuf et profil ordinaire : aucune réparation, profil sain", function()
			local d = Schema.defaults()
			expect(Repair.repair(d)).toEqual({})
			expect(Invariants.profile(d)).toEqual({})
			local d2 = fresh()
			expect(Repair.repair(d2)).toEqual({})
			expect(Invariants.profile(d2)).toEqual({})
		end)

		it("nombres abîmés : NaN, infini, négatif, fractionnaire, mauvais type", function()
			local d, fixes = load({
				coins = 0 / 0,
				pot = -5,
				fame = math.huge,
				R = 2.5,
				biggestEver = "big",
				lastOnline = -1,
				growth = { G = 0 / 0, g = -1, t = math.huge },
				boosts = { personalLeft = -math.huge },
			})
			expect(d.coins).toBe(0)
			expect(d.pot).toBe(0)
			expect(d.fame).toBe(0) -- infini : valeur par défaut
			expect(d.R).toBe(2)
			expect(d.biggestEver).toBe(0)
			expect(d.lastOnline).toBe(0)
			expect(d.growth.G).toBe(0)
			expect(d.growth.g).toBe(0)
			expect(d.growth.t).toBe(0)
			expect(d.boosts.personalLeft).toBe(0)
			for _, path in { "coins", "pot", "fame", "R", "biggestEver", "growth.G", "growth.g", "growth.t" } do
				expect({ path = path, fixed = has(fixes, path) }).toEqual({ path = path, fixed = true })
			end
			expect(Invariants.profile(d)).toEqual({})
			-- pièces fractionnaires sous ExactBelow : arrondies vers le bas
			local d2 = fresh()
			d2.coins = 12.7
			expect(Repair.repair(d2)).toEqual({ "coins" })
			expect(d2.coins).toBe(12)
		end)

		it("clé de premier niveau au mauvais type : remplacée par sa valeur par défaut", function()
			local d, fixes = load({ squishies = "abc", tiles = 5, caps = true, dex = { mut = "x" } })
			expect(type(d.squishies)).toBe("table")
			expect(d.tiles).toEqual(Schema.defaults().tiles)
			expect(type(d.caps.petSitBy)).toBe("table")
			expect(#d.dex.mut).toBe(#Species.List)
			expect(has(fixes, "squishies")).toBe(true)
			expect(has(fixes, "tiles")).toBe(true)
			expect(has(fixes, "caps")).toBe(true)
			expect(has(fixes, "dex.mut")).toBe(true)
			expect(Invariants.profile(d)).toEqual({})
		end)

		it("squishy : gd entier ≥ 0, champs bornés, lieu valide (contrat v1.2)", function()
			local d = fresh()
			d.squishies["1"].gd = "today"
			d.squishies["2"].gd = -3
			d.squishies["3"] =
				rec({ gd = 2.5, m = 99, st = -1, z = 0 / 0, zg = -2, lk = 1, o = 7, at = "moon", b = 0 / 0 })
			d.nextUid = 4
			local fixes = Repair.repair(d)
			expect(d.squishies["1"].gd).toBe(0)
			expect(d.squishies["2"].gd).toBe(0)
			local r3 = d.squishies["3"]
			expect(r3.gd).toBe(2)
			expect(r3.m).toBe(9)
			expect(r3.st).toBe(0)
			expect(r3.z).toBe(1)
			expect(r3.zg).toBe(0)
			expect(r3.lk).toBe(false)
			expect(r3.o).toBe("")
			expect(r3.at).toBe("pen")
			expect(r3.b).toBe(0)
			for _, path in
				{ "squishies.1.gd", "squishies.2.gd", "squishies.3.gd", "squishies.3.at", "squishies.3.z" }
			do
				expect({ path = path, fixed = has(fixes, path) }).toEqual({ path = path, fixed = true })
			end
			expect(Invariants.profile(d)).toEqual({})
		end)

		it("uid abîmé ou ligne illisible retirés ; nextUid toujours au-delà du plus grand uid", function()
			local d = fresh()
			d.squishies["BAD!"] = rec()
			d.squishies["toolongid9"] = rec()
			d.squishies["9"] = "pas une table"
			d.squishies["zz"] = rec({ s = 0 / 0 })
			d.squishies["a"] = rec({ at = "dodo" })
			d.nextUid = 2
			local fixes = Repair.repair(d)
			expect(d.squishies["BAD!"]).toBeNil()
			expect(d.squishies["toolongid9"]).toBeNil()
			expect(d.squishies["9"]).toBeNil()
			expect(d.squishies["zz"]).toBeNil()
			expect(d.squishies["a"] ~= nil).toBe(true)
			expect(d.nextUid).toBe(tonumber("a", 36) + 1)
			expect(has(fixes, "nextUid")).toBe(true)
			expect(Invariants.profile(d)).toEqual({})
		end)

		it("espèce future (entier encore inconnu de ce serveur) : squishy gardé tel quel", function()
			local d = fresh()
			d.squishies["3"] = rec({ s = 40, at = "dodo" })
			d.nextUid = 4
			expect(Repair.repair(d)).toEqual({})
			expect(d.squishies["3"].s).toBe(40)
		end)

		it("Meilleurs Amis uniques : le plus ancien garde l'emplacement", function()
			local d = fresh()
			d.squishies["2"].bf = 1
			d.squishies["3"] = rec({ bf = 1, at = "dodo" })
			d.nextUid = 4
			local fixes = Repair.repair(d)
			expect(d.squishies["1"].bf).toBe(1)
			expect(d.squishies["2"].bf).toBe(0)
			expect(d.squishies["3"].bf).toBe(0)
			expect(has(fixes, "squishies.2.bf")).toBe(true)
			expect(Invariants.profile(d)).toEqual({})
		end)

		it("capacités : Bassin, enclos, Dodo et Lettres ramenés à leurs places", function()
			local d = Schema.defaults()
			local n = 0
			local function add(at, count)
				for _ = 1, count do
					n += 1
					d.squishies[string.format("%x", n)] = rec({ at = at })
				end
			end
			add("pool", 8) -- 8 dans le Bassin (5 places), 4 places d'enclos en tout
			add("pen", 6)
			add("dodo", 59)
			add("mail", 25)
			d.nextUid = n + 1
			local fixes = Repair.repair(d)
			expect(#fixes > 0).toBe(true)
			expect(Invariants.profile(d)).toEqual({})
			local counts = { pen = 0, pool = 0, dodo = 0, mail = 0 }
			local total = 0
			for _, r in d.squishies do
				counts[r.at] += 1
				total += 1
			end
			expect(counts.pen + counts.pool).toBe(4)
			expect(counts.dodo).toBe(60)
			expect(counts.mail).toBe(20)
			expect(total).toBe(84) -- 98 lignes : 14 au-delà de toutes les places (profil abîmé)
		end)

		it("dex.fam : dense en 0 / 1, allongé à #Species.FamilyOrder (contrat v1.2)", function()
			local d = fresh()
			d.dex.fam = { 1, true, 5 }
			local fixes = Repair.repair(d)
			expect(#d.dex.fam).toBe(#Species.FamilyOrder)
			expect(d.dex.fam[1]).toBe(1)
			expect(d.dex.fam[2]).toBe(1)
			expect(d.dex.fam[3]).toBe(1)
			expect(d.dex.fam[4]).toBe(0)
			expect(has(fixes, "dex.fam")).toBe(true)
			-- trous et clés étrangères : reconstruit
			local d2 = fresh()
			d2.dex.fam = { [1] = 1, [3] = 1, x = 1 }
			Repair.repair(d2)
			expect(d2.dex.fam[2]).toBe(0)
			expect(d2.dex.fam[3]).toBe(1)
			expect(d2.dex.fam.x).toBeNil()
			expect(Invariants.profile(d2)).toEqual({})
		end)

		it("tableaux de 64 espèces : jamais tronqués ; trous comblés à 0", function()
			local d = fresh()
			for s = 1, 64 do
				d.dex.mut[s] = bit32.bor(1, bit32.lshift(1, (s % 9) + 1))
				d.dex.stars[s] = s % 32
				d.trophies[s] = s * 1e9
			end
			expect(Repair.repair(d)).toEqual({})
			expect(#d.dex.mut).toBe(64)
			expect(#d.dex.stars).toBe(64)
			expect(#d.trophies).toBe(64)
			-- trou au milieu : reconstruit sans rien perdre au-delà
			local d2 = fresh()
			for s = 1, 64 do
				d2.trophies[s] = s
			end
			d2.trophies[30] = nil
			local fixes = Repair.repair(d2)
			expect(has(fixes, "trophies")).toBe(true)
			expect(#d2.trophies).toBe(64)
			expect(d2.trophies[30]).toBe(0)
			expect(d2.trophies[64]).toBe(64)
			-- tableau trop court : allongé à Species.List
			local d3 = fresh()
			d3.dex.stars = { 3 }
			Repair.repair(d3)
			expect(#d3.dex.stars).toBe(#Species.List)
			expect(d3.dex.stars[1]).toBe(3)
		end)

		it("tenues : outfits.worn vidé ; porteurs au-delà de owned retirés (contrat v1.2)", function()
			local d = fresh()
			d.outfits.worn = { ["1"] = "sweater" }
			d.outfits.owned = { sweater = 1, jellyCrown = "deux", [5] = 1 }
			d.squishies["1"].o = "sweater"
			d.squishies["2"].o = "sweater"
			d.squishies["3"] = rec({ o = "unknownHat", at = "dodo" })
			d.nextUid = 4
			local fixes = Repair.repair(d)
			expect(d.outfits.worn).toEqual({})
			expect(d.outfits.owned).toEqual({ sweater = 1, jellyCrown = 0 })
			expect(d.squishies["1"].o).toBe("sweater")
			expect(d.squishies["2"].o).toBe("")
			expect(d.squishies["3"].o).toBe("")
			expect(has(fixes, "outfits.worn")).toBe(true)
			expect(has(fixes, "squishies.2.o")).toBe(true)
			expect(Invariants.profile(d)).toEqual({})
		end)

		it(
			"plafonds : petSitIn, splorchCoins nombres ; petSitBy clés chaînes → entiers bornés",
			function()
				local d = fresh()
				d.caps.petSitIn = "x"
				d.caps.splorchCoins = 0 / 0
				d.caps.petSit = 1e9
				d.caps.petSitBy = { ["123"] = 50, ["456"] = 2.5, [7] = 1, abc = 3, ["789"] = "z" }
				local fixes = Repair.repair(d)
				expect(d.caps.petSitIn).toBe(0)
				expect(d.caps.splorchCoins).toBe(0)
				expect(d.caps.petSit).toBe(Balance.Caps.petSit)
				expect(d.caps.petSitBy).toEqual({
					["123"] = Balance.CapsPerFriend.petSit,
					["456"] = 2,
					["789"] = 0,
				})
				expect(has(fixes, "caps.petSitBy")).toBe(true)
				expect(has(fixes, "caps.petSitIn")).toBe(true)
				expect(Invariants.profile(d)).toEqual({})
				local d2 = fresh()
				d2.caps.petSitBy = "oops"
				Repair.repair(d2)
				expect(d2.caps.petSitBy).toEqual({})
			end
		)

		it("moon.lastSession réparé ; clé héritée coinBuy ignorée (ni lue ni effacée)", function()
			local d = fresh()
			d.moon.lastSession = -4
			d.coinBuy = { day = 3, n = 2 }
			d.caps.coinBuy = 7
			local fixes = Repair.repair(d)
			expect(d.moon.lastSession).toBe(0)
			expect(has(fixes, "moon.lastSession")).toBe(true)
			expect(d.coinBuy).toEqual({ day = 3, n = 2 })
			expect(d.caps.coinBuy).toBe(7)
			for _, path in fixes do
				expect(string.find(path, "coinBuy", 1, true)).toBeNil()
			end
		end)

		it("monture absente, relâchés au-delà de 12, objectifs illisibles, réglage hors liste", function()
			local d = fresh()
			d.mount = "zzz"
			d.released = {}
			for i = 1, 15 do
				d.released[i] = { s = 1, m = i % 3 }
			end
			d.released[16] = "x"
			d.objectives = { day = 5, list = { { id = 1 }, 2 }, rerolls = 0, allClaimed = false }
			d.settings.lang = "klingon"
			local fixes = Repair.repair(d)
			expect(d.mount).toBe("")
			expect(#d.released).toBe(Balance.Release.MeadowKeep)
			expect(d.objectives.list).toEqual({})
			expect(d.objectives.day).toBe(0)
			expect(d.settings.lang).toBe("auto")
			expect(has(fixes, "settings.lang")).toBe(true)
			expect(Invariants.profile(d)).toEqual({})
		end)

		it("idempotent : réparer deux fois ne change plus rien", function()
			local d, first = load({
				coins = -1,
				squishies = { ["1"] = rec({ gd = -1, bf = 2 }), ["2"] = rec({ bf = 2 }) },
				dex = { fam = { 2 } },
				outfits = { owned = {}, worn = { x = 1 } },
			})
			expect(#first > 0).toBe(true)
			local copy = Tables.deepCopy(d)
			expect(Repair.repair(d)).toEqual({})
			expect(d).toEqual(copy)
		end)

		it(
			"propriété : 400 profils hostiles → jamais d'erreur, profil sain, accepté par le DataStore",
			function()
				local store = h.game.DataStoreService:GetDataStore("RepairProps")
				local anyNum = Props.anyNumber()
				local anyVal = Props.any()
				local gen = Props.gen(function(rng)
					local d = {}
					-- clés du schéma aux valeurs bizarres (types, nombres limites)
					for key in Schema.defaults() do
						if rng.chance(0.3) then
							d[key] = anyVal.gen(rng)
						end
					end
					-- collection : lignes aux champs bizarres
					if rng.chance(0.8) then
						local sq = {}
						for i = 1, rng.int(0, 30) do
							local r = rec()
							for _, field in { "s", "m", "st", "z", "zg", "bf", "gd", "b" } do
								if rng.chance(0.25) then
									r[field] = anyNum.gen(rng)
								end
							end
							if rng.chance(0.1) then
								r.at = rng.pick({ "pen", "pool", "dodo", "mail", "moon", 3 })
							end
							if rng.chance(0.1) then
								r.o = rng.pick({ "sweater", "x", "" })
							end
							sq[if rng.chance(0.05) then "BAD" .. i else string.format("%x", i)] = r
						end
						d.squishies = sq
						d.nextUid = anyNum.gen(rng)
					end
					if rng.chance(0.5) then
						d.caps =
							{ petSitBy = { ["1"] = anyNum.gen(rng), [2] = 1 }, petSitIn = anyNum.gen(rng) }
					end
					-- les valeurs non JSON (cycles, Vector3) ne viennent jamais d'un vrai DataStore
					return d
				end)
				Props.check(400, gen, function(raw)
					-- un vrai DataStore rend du JSON : pas de cycle, pas d'Instance ni de Vector3
					local okJson, json = pcall(function()
						return h.game.HttpService:JSONEncode(raw)
					end)
					if not okJson then
						return true
					end
					local d = h.game.HttpService:JSONDecode(json)
					Tables.reconcile(d, Schema.defaults())
					local ok, fixes = pcall(Repair.repair, d)
					if not ok then
						return false, "erreur : " .. tostring(fixes)
					end
					local bad = Invariants.profile(d)
					-- espèce future gardée (seule violation tolérée)
					local kept = {}
					for _, path in bad do
						if not string.match(path, "^squishies%.[0-9a-z]+%.s$") then
							table.insert(kept, path)
						end
					end
					if #kept > 0 then
						return false, "invariants : " .. table.concat(kept, ", ")
					end
					local again = Repair.repair(d)
					if #again > 0 then
						return false, "non idempotent : " .. table.concat(again, ", ")
					end
					local okStore, err = pcall(function()
						store:SetAsync("k", d)
					end)
					if not okStore then
						return false, "DataStore : " .. tostring(err)
					end
					return true
				end)
			end
		)

		it("entrée qui n'est pas une table : aucune erreur", function()
			expect(Repair.repair(nil)).toEqual({ "profile" })
			expect(Repair.repair(42)).toEqual({ "profile" })
		end)
	end)

	describe("ProfileRepair › note INT-REPAIR (DataService)", function()
		it(
			"profil abîmé chargé : réparé avant onPrepare, ProfileRepaired émis après Loaded",
			function()
				local hh = Harness.new()
				local DS = hh:require("ServerScriptService.Server.Services.DataService")
				local Signals = hh:require("ServerScriptService.Server.Signals")
				DS.Settings.RETRY_BASE_DELAY = 0.001
				local store = hh.game.DataStoreService:GetDataStore(
					hh:require("ServerScriptService.Server.Data.Schema").STORE_NAME
				)
				local broken = Schema.defaults()
				broken.coins = -50
				broken.squishies = { ["1"] = rec({ gd = -2 }) }
				broken.nextUid = 2
				broken.outfits.worn = { ["1"] = "sweater" }
				store:SetAsync("player_401", { data = broken })
				local order = {}
				local seenInPrepare = nil
				DS.onPrepare(function(_, data)
					table.insert(order, "prepare")
					seenInPrepare = data.coins
				end)
				DS.Loaded:Connect(function()
					table.insert(order, "loaded")
				end)
				local repaired = nil
				Signals.ProfileRepaired:Connect(function(_, fixes)
					table.insert(order, "repaired")
					repaired = fixes
				end)
				hh:boot()
				local p = hh:addPlayer({ userId = 401, name = "Rex" })
				local data = DS.waitFor(p, 2)
				hh:settle(3)
				expect(data ~= nil).toBe(true)
				expect(seenInPrepare).toBe(0)
				expect(data.coins).toBe(0)
				expect(data.squishies["1"].gd).toBe(0)
				expect(data.outfits.worn).toEqual({})
				expect(order[1]).toBe("prepare")
				expect(table.find(order, "repaired") > table.find(order, "loaded")).toBe(true)
				expect(has(repaired, "coins")).toBe(true)
				expect(has(repaired, "squishies.1.gd")).toBe(true)
				expect(table.concat(hh.errors, "\n")).toBe("")
			end
		)

		it("profil sain : aucun ProfileRepaired", function()
			local hh = Harness.new()
			local DS = hh:require("ServerScriptService.Server.Services.DataService")
			local Signals = hh:require("ServerScriptService.Server.Signals")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			local fired = 0
			Signals.ProfileRepaired:Connect(function()
				fired += 1
			end)
			hh:boot()
			local p = hh:addPlayer({ userId = 402, name = "Zoe" })
			expect(DS.waitFor(p, 2) ~= nil).toBe(true)
			hh:settle(3)
			expect(fired).toBe(0)
		end)
	end)
end
