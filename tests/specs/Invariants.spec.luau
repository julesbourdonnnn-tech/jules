--!nocheck
-- Invariants (paquet logic, docs/04 §8.5, §12.1, §17.2) : un profil neuf est sain ; chaque violation
-- est nommée ; tableaux denses, uid, nombres bornés, capacités, Meilleurs Amis, tenues.
-- Profil v2 (lot A1, docs/04 §27.2) : bornes de chaque champ v2, plafonds des niveaux, ensembles de
-- bits, piste, Déco perso, cœurs ; juste après un prestige (afterPrestige) ; profil v1 inchangé.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- serveur v1.3 (préréglage « v13 », lot I D2 a / D10) : Schema.defaults() de ce fichier est le
	-- profil v1 (entrée de la migration, gardée tant que le code v1 existe) ; les profils v2 sont
	-- construits par defaultsFor(2) ; le chemin du lancement (serveur v2, vrai DataService) : Migration_I
	local h = Harness.new({ flags = "v13" })
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
	end)

	-- ---------------------------------------------------------------------------------------------
	-- Profil v2 (lot A1, docs/04 §27.2) : seulement pour version ≥ 2 (schéma derrière SchemaV2)
	-- ---------------------------------------------------------------------------------------------
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")
	local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local W = Upgrades.WorkshopIndex

	local function healthyV2(fields)
		local d = Schema.defaultsFor(2)
		d.squishies = { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 5, at = "pool" }) }
		d.nextUid = 3
		for k, v in fields or {} do
			d[k] = v
		end
		return d
	end
	-- Témoins de tests/fixtures/profiles : leurs squishies n'ont pas `b` (heure de naissance, posée à
	-- 0 par ProfileRepair au chargement, comme DataService le fait avant tout invariant)
	local function readJson(name)
		local d = serde.decode("json", fs.readFile("tests/fixtures/profiles/" .. name))
		for _, r in d.squishies do
			if r.b == nil then
				r.b = 0
			end
		end
		return d
	end

	describe("Invariants › profil v2", function()
		it(
			"profils v2 sains : défauts, sauvegarde-témoin v2.json, v1.json migré, profil de jeu",
			function()
				expect(Features.Defaults.SchemaV2).toBe(false) -- schéma v2 coupé : rien ne change en v1
				expect(I.profile(Schema.defaultsFor(2))).toEqual({})
				expect(I.profile(healthyV2())).toEqual({})
				local v2 = readJson("v2.json")
				Tables.reconcile(v2, Schema.defaultsFor(2))
				expect(I.profile(v2)).toEqual({})
				local migrated = Schema.migrate(readJson("v1.json"), 1, 2)
				Tables.reconcile(migrated, Schema.defaultsFor(2))
				expect(I.profile(migrated)).toEqual({})
				-- en cours de jeu après une Ascension : r 9, Record R 21, A 2, Tapis Étoilé plafonné par r
				local d = healthyV2({
					R = 9,
					bestR = 21,
					ascend = 2,
					regainBonusA = 1,
					confetti = 40,
					confettiTotal = 900,
				})
				d.tiles.snack, d.tiles.star, d.tiles.gloves, d.tiles.school, d.tiles.monuments =
					12, 4, 40, 20, 8
				d.atelier[W.springboard] = 3
				d.atelier[W.plume] = 1
				d.unlocksSeen = 21
				expect(I.profile(d)).toEqual({})
			end
		)

		it("profil v1 : exactement les invariants de la v1.3 (les champs v2 ne sont pas lus)", function()
			local d = healthy()
			expect(d.version).toBe(1)
			d.bestR = -7
			d.confetti = 0 / 0
			d.weeklyTrack = "x"
			d.R = 500 -- v1 : R borné à 1e6, pas à MaxR
			expect(I.profile(d)).toEqual({})
		end)

		it("progression : R ≤ bestR ≤ MaxR, A ≤ MaxA, bonus de retour ≤ A", function()
			local cases = {
				{ { R = 401, bestR = 401 }, "R" },
				{ { R = 5, bestR = 4 }, "bestR" },
				{ { R = 5, bestR = 401 }, "bestR" },
				{ { bestR = 2.5 }, "bestR" },
				{ { bestR = 0 / 0 }, "bestR" },
				{ { ascend = 61 }, "ascend" },
				{ { ascend = -1 }, "ascend" },
				{ { ascend = 2, regainBonusA = 3 }, "regainBonusA" },
			}
			for _, case in cases do
				local v = I.profile(healthyV2(case[1]))
				expect({ case = case[2], found = has(v, case[2]) }).toEqual({ case = case[2], found = true })
			end
		end)

		it("Confettis : entiers de 0 à 1e9, en poche ≤ total gagné", function()
			expect(has(I.profile(healthyV2({ confetti = -1 })), "confetti")).toBe(true)
			expect(has(I.profile(healthyV2({ confetti = 1.5, confettiTotal = 9 })), "confetti")).toBe(true)
			expect(has(I.profile(healthyV2({ confettiTotal = 2e9 })), "confettiTotal")).toBe(true)
			expect(has(I.profile(healthyV2({ confetti = 10, confettiTotal = 9 })), "confetti.total")).toBe(
				true
			)
			expect(I.profile(healthyV2({ confetti = 1e9, confettiTotal = 1e9 }))).toEqual({})
		end)

		it(
			"niveaux : bornes, Tapis Étoilé après le Tapis 12 et sous le plafond de r, plafond de chaque ligne",
			function()
				local function tiles(R, bestR, t)
					local d = healthyV2({ R = R, bestR = bestR, unlocksSeen = 0 })
					for k, v in t do
						d.tiles[k] = v
					end
					return I.profile(d)
				end
				expect(has(tiles(10, 10, { star = 9, snack = 12 }), "tiles.star")).toBe(true)
				expect(has(tiles(10, 10, { star = 2, snack = 11 }), "tiles.star.snack")).toBe(true)
				expect(has(tiles(7, 7, { star = 3, snack = 12 }), "tiles.star.loopCap")).toBe(true)
				expect(tiles(7, 7, { star = 2, snack = 12 })).toEqual({})
				expect(has(tiles(10, 10, { gloves = 41 }), "tiles.gloves")).toBe(true)
				expect(has(tiles(10, 10, { school = 21 }), "tiles.school")).toBe(true)
				expect(has(tiles(30, 30, { monuments = 11 }), "tiles.monuments")).toBe(true)
				-- plafonds par le Record R : Gants dès 1, École dès 2, Monument n à 6, 8 … 24, Lit dès 3
				expect(has(tiles(0, 0, { gloves = 1 }), "gloves.cap")).toBe(true)
				expect(tiles(1, 1, { gloves = 40 })).toEqual({})
				expect(has(tiles(1, 1, { school = 1 }), "school.cap")).toBe(true)
				expect(has(tiles(9, 9, { monuments = 3 }), "monument.cap")).toBe(true)
				expect(tiles(9, 9, { monuments = 2 })).toEqual({})
				expect(has(tiles(2, 2, { cozyBed = true }), "cozyBed.cap")).toBe(true)
				-- après une Ascension, r redescend : les Monuments et les Gants (Record R) restent valables
				expect(tiles(0, 24, { monuments = 10, gloves = 12 })).toEqual({})
			end
		)

		it("Atelier : une case par ligne, ≤ son nombre de niveaux, ouverte par le Record R ou A", function()
			local d = healthyV2({ bestR = 1, R = 1 })
			d.atelier[W.gift] = 3
			expect(has(I.profile(d), "atelier.gift")).toBe(true)
			local e = healthyV2()
			table.remove(e.atelier)
			expect(has(I.profile(e), "atelier")).toBe(true)
			local f = healthyV2({ bestR = 20, R = 20 })
			f.atelier[W.springboard] = 1 -- Tremplin : A ≥ 1
			expect(has(I.profile(f), "springboard.cap")).toBe(true)
			local g = healthyV2({ bestR = 11, R = 11 })
			g.atelier[W.plume] = 1 -- Plume : Record R ≥ 12
			expect(has(I.profile(g), "plume.cap")).toBe(true)
			local k = healthyV2()
			k.atelier[W.magnet] = 1 -- rien avant le premier Grand Splorch
			expect(has(I.profile(k), "magnet.cap")).toBe(true)
		end)

		it("ensembles de bits, décorations dorées, statistiques, cartes « Nouveau »", function()
			local cases = {
				{
					"atelierCosmetics",
					function(d)
						d.atelierCosmetics = {}
					end,
				},
				{
					"carnet",
					function(d)
						d.carnet = { -1 }
					end,
				},
				{
					"mastery",
					function(d)
						d.mastery = { 2 ^ 32 }
					end,
				},
				{
					"decorBuilds",
					function(d)
						d.decorBuilds = { 1, 2 }
					end,
				},
				{
					"decorBuilds.4",
					function(d)
						d.decorBuilds[4] = 11
					end,
				},
				{
					"stats.upgradesBought",
					function(d)
						d.stats.upgradesBought = -1
					end,
				},
				{
					"stats.petitSplorches",
					function(d)
						d.stats.petitSplorches = 0.5
					end,
				},
				{
					"unlocksSeen",
					function(d)
						d.unlocksSeen = 1
					end,
				}, -- au-delà du Record R 0
			}
			for _, case in cases do
				local d = healthyV2()
				case[2](d)
				local v = I.profile(d)
				expect({ case = case[1], found = has(v, case[1]) }).toEqual({ case = case[1], found = true })
			end
			local big = healthyV2()
			big.mastery = table.create(200, 0) -- 200 mots : au-delà de Bitset.MaxBits
			expect(has(I.profile(big), "mastery")).toBe(true)
		end)

		it("piste de la semaine, accueil, saison, plafonds du jour v2", function()
			local cases = {
				{
					"weeklyTrack",
					function(d)
						d.weeklyTrack = nil
					end,
				},
				{
					"weeklyTrack.points",
					function(d)
						d.weeklyTrack.points = -2
					end,
				},
				{
					"weeklyTrack.claimed",
					function(d)
						d.weeklyTrack.claimed = {}
					end,
				},
				{
					"weeklyTrack.firstPeriodEnd",
					function(d)
						d.weeklyTrack.firstPeriodEnd = 0 / 0
					end,
				},
				{
					"weeklyTrack.challenges",
					function(d)
						d.weeklyTrack.challenges = {
							{ id = 1, p = 0, done = false },
							{ id = 2, p = 0, done = false },
							{ id = 3, p = 0, done = false },
							{ id = 4, p = 0, done = false },
						}
					end,
				},
				{
					"weeklyTrack.challenges.2",
					function(d)
						d.weeklyTrack.challenges =
							{ { id = 1, p = 0, done = false }, { id = 1, p = 1, done = false } }
					end,
				},
				{
					"weeklyTrack.challenges.1",
					function(d)
						d.weeklyTrack.challenges = { { id = 13, p = 0, done = false } }
					end,
				},
				{
					"onboarding.v2",
					function(d)
						d.onboarding.welcomeV2Pending = nil
					end,
				},
				{
					"season.frostDays",
					function(d)
						d.season.frostDays = -1
					end,
				},
				{
					"caps.fameSplorch",
					function(d)
						d.caps.fameSplorch = 51
					end,
				},
				{
					"caps.starRain",
					function(d)
						d.caps.starRain = 0 / 0
					end,
				},
				-- lot A4 (docs/04 §27.12 A4-4) : mêmes bornes que ProfileRepair
				{
					"weeklyTrack.won",
					function(d)
						d.weeklyTrack.won = { 1.5 }
					end,
				},
				{
					"weeklyTrack.won",
					function(d)
						d.weeklyTrack.won = nil
					end,
				},
				{
					"weeklyTrack.play",
					function(d)
						d.weeklyTrack.play = { 0, 0, 0, 0, 0, 0 } -- 6 cases
					end,
				},
				{
					"weeklyTrack.play",
					function(d)
						d.weeklyTrack.play[4] = 86401
					end,
				},
				{
					"weeklyTrack.playDay",
					function(d)
						d.weeklyTrack.playDay = 2.5
					end,
				},
				{
					"moon.sessions",
					function(d)
						d.moon.sessions = -1
					end,
				},
				{
					"stats.objectivesClaimed",
					function(d)
						d.stats.objectivesClaimed = 0 / 0
					end,
				},
				{
					"stats.tracksDone",
					function(d)
						d.stats.tracksDone = nil
					end,
				},
				{
					"cosmetics.palette",
					function(d)
						d.cosmetics.palette = "inconnue"
					end,
				},
				{
					"cosmetics.cushions",
					function(d)
						d.cosmetics.cushions = "candy" -- une palette, pas des coussins
					end,
				},
				{
					"settings.haloOn",
					function(d)
						d.settings.haloOn = nil
					end,
				},
			}
			for _, case in cases do
				local d = healthyV2()
				case[2](d)
				local v = I.profile(d)
				expect({ case = case[1], found = has(v, case[1]) }).toEqual({ case = case[1], found = true })
			end
			local ok = healthyV2()
			ok.weeklyTrack.challenges = { { id = 3, p = 4, done = false }, { id = 12, p = 30, done = true } }
			ok.caps.fameSplorch, ok.caps.starRain = 50, 3
			expect(I.profile(ok)).toEqual({})
			-- lot A4 : valeurs permises (chaque palette et chaque coussin connus, « » compris)
			ok.weeklyTrack.won = { 255 }
			ok.weeklyTrack.play = { 86400, 0, 1, 2, 3, 4, 5 }
			ok.weeklyTrack.playDay = 20759
			ok.moon.sessions, ok.stats.objectivesClaimed, ok.stats.tracksDone = 4, 100, 4
			ok.settings.haloOn = false
			ok.cosmetics.cushions = "pinkCushions"
			for _, id in
				{
					"",
					"candy",
					"mint",
					"lavender",
					"rainbow",
					"softNight",
					"icing",
					"fireworks",
					"peachPalette",
				}
			do
				ok.cosmetics.palette = id
				expect({ id = id, bad = I.profile(ok) }).toEqual({ id = id, bad = {} })
			end
		end)

		it(
			"Déco perso : emplacement vers un objet possédé, jamais deux fois ; cœurs : 20 receveurs au plus",
			function()
				local d = healthyV2()
				-- objets 2 et 3 (petits), 6 et 8 (grands) ; attente changée au lot A4 (D18, journal A4-4) :
				-- l'objet 3 (petit) était posé sur l'emplacement 9 (grand), désormais refusé
				d.decoPerso.owned[1] = 2 + 4 + 32 + 128
				d.decoPerso.slots[1], d.decoPerso.slots[9] = 2, 6
				d.hearts.givenTo = { 101, 102, -5 }
				d.hearts.givenDay, d.hearts.receivedTotal = 20400, 17
				expect(I.profile(d)).toEqual({})
				local cases = {
					{
						"decoPerso.slots.2",
						function(x)
							x.decoPerso.slots[2] = 1
						end,
					}, -- objet 1 non possédé
					{
						"decoPerso.slots.3",
						function(x)
							x.decoPerso.slots[3] = 2
						end,
					}, -- objet 2 déjà posé
					{
						"decoPerso.slots.4",
						function(x)
							x.decoPerso.slots[4] = 41
						end,
					},
					{
						"decoPerso.slots.10",
						function(x)
							x.decoPerso.slots[10] = 3
						end,
					}, -- petit objet sur un grand emplacement (lot A4)
					{
						"decoPerso.slots.5",
						function(x)
							x.decoPerso.slots[5] = 8
						end,
					}, -- grand objet sur un petit emplacement (lot A4)
					{
						"decoPerso.slots",
						function(x)
							x.decoPerso.slots[13] = 0
						end,
					},
					{
						"decoPerso.owned",
						function(x)
							x.decoPerso.owned = { 0 }
						end,
					}, -- 64 bits : 2 mots
					{
						"hearts.givenTo",
						function(x)
							x.hearts.givenTo = table.create(21, 1)
						end,
					},
					{
						"hearts.givenTo",
						function(x)
							x.hearts.givenTo = { 101, 101 }
						end,
					},
					{
						"hearts.givenDay",
						function(x)
							x.hearts.givenDay = -1
						end,
					},
				}
				for _, case in cases do
					local x = Tables.deepCopy(d)
					case[2](x)
					local v = I.profile(x)
					expect({ case = case[1], found = has(v, case[1]) }).toEqual({
						case = case[1],
						found = true,
					})
				end
			end
		)

		it(
			"bitset : mots entiers de 32 bits, au moins ceil(n / 32), jamais plus que Bitset.MaxBits",
			function()
				expect(I.bitset({ 0 }, 11)).toBe(true)
				expect(I.bitset({ 0, 4294967295 }, 64)).toBe(true)
				expect(I.bitset({ 0 }, 64)).toBe(false)
				expect(I.bitset({}, 1)).toBe(false)
				expect(I.bitset({ 1.5 }, 8)).toBe(false)
				expect(I.bitset({ 0 / 0 }, 8)).toBe(false)
				expect(I.bitset({ [2] = 1 }, 8)).toBe(false)
				expect(I.bitset("x", 8)).toBe(false)
			end
		)
	end)

	describe("Invariants › juste après un prestige (Prestige.apply)", function()
		local function readyV2(fields)
			local d = healthyV2(fields)
			d.growth = { G = 0, g = 1, t = 0 }
			d.squishies["1"].z = Prestige.target(Prestige.r(d))
			d.squishies["3"] = rec({ at = "dodo", z = 77 })
			d.squishies["4"] = rec({ at = "mail", z = 5 })
			d.nextUid = 5
			return d
		end

		it(
			"Grand Splorch, Petit Splorch, Ascension : profil sain, toutes les tailles à 1, décorations gardées ≤ 12",
			function()
				local d = readyV2({ R = 14, bestR = 14, unlocksSeen = 14 })
				d.tiles.snack, d.tiles.decor, d.tiles.star, d.tiles.gloves, d.tiles.school = 12, 18, 8, 30, 10
				d.atelier[W.keptDecor] = 2
				d.atelier[W.startMat] = 3
				local _, report = Prestige.apply(d, "splorch", 100)
				expect(report.applied).toBe(true)
				expect(I.afterPrestige(d)).toEqual({})
				expect(d.tiles.decor).toBe(12) -- 3 (R8) + 3 (R14) + 2 × 3 (Atelier) = 12 au plus
				-- une suite de prestiges jusqu'à deux Ascensions : jamais une violation
				local function step(kind)
					d.squishies["1"].z = Prestige.target(Prestige.r(d))
					d.growth = { G = 0, g = 1, t = 0 }
					local _, r = Prestige.apply(d, kind, 100)
					expect({ kind = kind, applied = r.applied }).toEqual({ kind = kind, applied = true })
					d.unlocksSeen = Prestige.bestR(d)
					expect(I.afterPrestige(d)).toEqual({})
				end
				step("splorch") -- 16 (Ascension prête dès 15)
				expect(Prestige.ascendReady(d)).toBe(true)
				step("ascend")
				expect({ Prestige.r(d), Prestige.bestR(d) }).toEqual({ 0, 16 })
				for _ = 1, 3 do
					step("splorch") -- Petits Splorch de la remontée (sorte effective « petit »)
				end
				expect(Prestige.ascend(d)).toBe(1)
			end
		)

		it(
			"violations nommées : une taille restée grande, des décorations de trop, des Gants gardés",
			function()
				local d = readyV2({ R = 9, bestR = 9, unlocksSeen = 9 })
				d.tiles.decor = 9
				Prestige.apply(d, "splorch", 100)
				expect(I.afterPrestige(d)).toEqual({})
				local a = Tables.deepCopy(d)
				a.squishies["3"].z = 77
				expect(has(I.afterPrestige(a), "prestige.squishies.3.size")).toBe(true)
				local b = Tables.deepCopy(d)
				b.tiles.decor = 4 -- 3 gardées au Record R 10
				expect(has(I.afterPrestige(b), "prestige.tiles.decor")).toBe(true)
				local c = Tables.deepCopy(d)
				c.tiles.gloves = 1
				expect(has(I.afterPrestige(c), "prestige.tiles.gloves")).toBe(true)
				local e = Tables.deepCopy(d)
				e.growth.G = 5
				expect(has(I.afterPrestige(e), "prestige.growth.G")).toBe(true)
				expect(I.afterPrestige(nil)).toEqual({ "profile" })
			end
		)
	end)

	describe("Invariants › zéro trace", function()
		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
