--!nocheck
-- ProfileRepair v2 (lot A2, docs/04 §27.2, §27.10) : un profil de version ≥ 2 est réparé sur
-- Schema.defaultsFor(2) avec les bornes de chaque champ v2 ; un profil v1 exactement comme dans la
-- version de test. Profil réparé = profil sain (Logic/Invariants v2), idempotent, jamais d'erreur,
-- accepté par le DataStore et identique après un aller-retour JSON ; aucune donnée valide perdue
-- (clés inconnues gardées, ensembles de bits jamais tronqués en deçà de Bitset.MaxBits) ; une valeur
-- illisible ne donne jamais rien deux fois (bonus de retour, × 1,25 de la 1re boucle record, bit
-- non possédé, carte déjà vue). Champ memoryR (décision INT-A1-MEMORY, journal A2-1) : chaîne
-- complète profil neuf, profil v1 migré et profil abîmé réparé, jusqu'à Prestige.firstRecordLoop.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- serveur v1.3 (préréglage « v13 », lot I D2 a / D10) : Schema.defaults() de ce fichier est le
	-- profil v1 (entrée de la migration, gardée tant que le code v1 existe) ; les profils v2 sont
	-- construits par defaultsFor(2) ; le chemin du lancement (serveur v2, vrai DataService) : Migration_I
	local h = Harness.new({ flags = "v13" })
	local Repair = h:require("ServerScriptService.Server.Data.ProfileRepair")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")
	local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")
	local Invariants = h:require("ReplicatedStorage.Shared.Logic.Invariants")
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local Bitset = h:require("ReplicatedStorage.Shared.Logic.Bitset")
	local Species = h:require("ReplicatedStorage.Shared.Config.Species")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")
	local Quests = h:require("ReplicatedStorage.Shared.Config.Quests")
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local Props = require("../harness/Props")
	local Chaos = require("../harness/Chaos")

	local W = Upgrades.WorkshopIndex
	local MAX_R, MAX_A = Balance.Prestige.MaxR, Balance.Prestige.MaxA

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
	-- Profil v2 sain : défauts v2, deux squishies, champs de premier niveau remplacés
	local function healthy(fields)
		local d = Schema.defaultsFor(2)
		d.squishies = { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 5, at = "pool" }) }
		d.nextUid = 3
		for k, v in fields or {} do
			d[k] = v
		end
		return d
	end
	-- En cours de jeu après deux Ascensions : r 9, Record R 21, A 2, tout acheté sous les plafonds
	local function played()
		local d = healthy({
			R = 9,
			bestR = 21,
			ascend = 2,
			regainBonusA = 1,
			memoryR = 0,
			confetti = 40,
			confettiTotal = 900,
			unlocksSeen = 21,
		})
		d.tiles.snack, d.tiles.star, d.tiles.gloves, d.tiles.school, d.tiles.monuments =
			12, Prestige.starCap(9), 40, 20, 8
		d.tiles.cozyBed = true
		d.atelier[W.springboard] = 3
		d.atelier[W.plume] = 1
		d.atelier[W.gift] = 2
		Bitset.set(d.atelierCosmetics, 1)
		Bitset.set(d.atelierCosmetics, 11)
		d.decorBuilds[1] = 10
		Bitset.set(d.carnet, 8)
		Bitset.set(d.mastery, #Species.List)
		d.weeklyTrack = {
			period = 120,
			points = 30,
			claimed = { 4095 },
			challenges = { { id = 12, p = 30, done = true }, { id = 3, p = 2, done = false } },
			firstPeriodEnd = 1800604800,
			-- lot A4 : 2 cosmétiques de la semaine gagnés, 7 jours de jeu, dernier jour écrit
			won = { 3 },
			play = { 1800, 0, 600, 86400, 0, 3600, 120 },
			playDay = 20759,
		}
		Bitset.set(d.decoPerso.owned, 1)
		Bitset.set(d.decoPerso.owned, 40)
		d.decoPerso.slots[1], d.decoPerso.slots[12] = 1, 40
		d.hearts = { givenDay = 20759, givenTo = { 101, 102 }, receivedTotal = 77 }
		d.cosmetics.theme = "royal" -- Record R ≥ 20
		d.caps.fameSplorch, d.caps.starRain = 50, 3
		d.stats.upgradesBought, d.stats.petitSplorches = 345, 12
		d.season.frostDays = 4
		-- lot A4 : compteurs de la méta, palette et coussins choisis, halo caché
		d.stats.objectivesClaimed, d.stats.tracksDone, d.moon.sessions = 40, 2, 3
		d.cosmetics.palette, d.cosmetics.cushions = "candy", "pinkCushions"
		d.settings.haloOn = false
		return d
	end
	local function readJson(name)
		local d = serde.decode("json", fs.readFile("tests/fixtures/profiles/" .. name))
		for _, r in d.squishies do
			if r.b == nil then
				r.b = 0 -- heure de naissance absente des témoins (posée à 0 par la réparation v1)
			end
		end
		return d
	end
	-- Comme DataService (serveur v2) : migrate + reconcile, puis réparation
	local function loadV2(raw)
		local d = Schema.migrate(raw, if type(raw.version) == "number" then raw.version else 0, 2)
		Tables.reconcile(d, Schema.defaultsFor(2))
		return d, Repair.repair(d)
	end
	-- Réparé = sain, idempotent, JSON aller-retour exact, accepté par Roblox
	local function settled(d)
		expect(Invariants.profile(d)).toEqual({})
		local copy = Tables.deepCopy(d)
		expect(Repair.repair(d)).toEqual({})
		expect(Tables.deepEqual(d, copy)).toBe(true)
		expect(Tables.deepEqual(serde.decode("json", serde.encode("json", d)), d)).toBe(true)
		expect((Chaos.check(d))).toBe(true)
	end

	describe("ProfileRepair v2 › profils sains et frontière v1 / v2", function()
		it("profils v2 sains : défauts, profil joué : rien à réparer, profil sain", function()
			expect(Features.Defaults.SchemaV2).toBe(false) -- jeu de base : schéma v2 coupé
			for name, d in { defaults = healthy(), played = played() } do
				expect({ name = name, fixes = Repair.repair(d) }).toEqual({ name = name, fixes = {} })
				expect({ name = name, bad = Invariants.profile(d) }).toEqual({ name = name, bad = {} })
			end
		end)

		it(
			"témoin v2.json et v1.json migré : seulement les réparations v1 de v1.json, aucun champ v2 touché",
			function()
				-- v1.json (version de test) porte deux valeurs que la réparation v1 corrige déjà
				-- (onboarding.step, tenue portée) : la v2 n'en ajoute aucune. Lot A4 (D21, attente
				-- changée, journal A4-14) : la tenue portée de v1.json est « partyHat », tenue de la v2.0 :
				-- inconnue d'un profil v1 (retirée, comme avant), gardée sur un profil v2 (possédée : 1)
				local v1 = readJson("v1.json")
				local v1Fixes = Repair.repair(v1)
				expect(v1Fixes).toEqual({ "onboarding.step", "squishies.2.o" })
				expect(v1.squishies["2"].o).toBe("")
				v1Fixes = { "onboarding.step" }
				local witness = readJson("v2.json")
				Tables.reconcile(witness, Schema.defaultsFor(2))
				local migrated = Schema.migrate(readJson("v1.json"), 1, 2)
				Tables.reconcile(migrated, Schema.defaultsFor(2))
				for name, d in { witness = witness, migrated = migrated } do
					local before = Tables.deepCopy(d)
					expect({ name = name, fixes = Repair.repair(d) }).toEqual({ name = name, fixes = v1Fixes })
					expect({ name = name, o = d.squishies["2"].o }).toEqual({ name = name, o = "partyHat" })
					expect({ name = name, bad = Invariants.profile(d) }).toEqual({ name = name, bad = {} })
					for key in Schema.OWNERS_V2 do
						expect({ name = name, key = key, same = Tables.deepEqual(d[key], before[key]) }).toEqual({
							name = name,
							key = key,
							same = true,
						})
					end
				end
			end
		)

		it("profil v1 : réparé exactement comme avant (aucun champ v2 lu, ajouté ni écrit)", function()
			local d = Schema.defaults()
			expect(d.version).toBe(1)
			d.squishies = { ["1"] = rec() }
			d.nextUid = 2
			d.R = 500 -- v1 : borné à 1e6, pas à MaxR
			d.bestR = -7 -- clé inconnue de la v1 : ni lue ni effacée
			d.weeklyTrack = "x"
			d.cosmetics.theme = "neon" -- habillage v2 : pas vérifié en v1
			-- champs du lot A4 : inconnus de la v1, ni lus ni écrits
			d.settings.haloOn = 5
			d.moon.sessions = -1
			d.cosmetics.palette = 7
			local fixes = Repair.repair(d)
			expect(fixes).toEqual({})
			expect(d.R).toBe(500)
			expect(d.bestR).toBe(-7)
			expect(d.weeklyTrack).toBe("x")
			expect(d.cosmetics.theme).toBe("neon")
			expect({ d.settings.haloOn, d.moon.sessions, d.cosmetics.palette }).toEqual({ 5, -1, 7 })
			expect(d.cosmetics.cushions).toBeNil()
			expect(d.memoryR).toBeNil()
			expect(d.confetti).toBeNil()
			expect(d.tiles.star).toBeNil()
		end)

		it("clé inconnue (champ futur) gardée ; aucune clé du schéma v2 effacée", function()
			local d = played()
			d.futureField = { a = 1, b = { 2, 3 } }
			d.tiles.futureTile = 4
			expect(Repair.repair(d)).toEqual({})
			expect(d.futureField).toEqual({ a = 1, b = { 2, 3 } })
			expect(d.tiles.futureTile).toBe(4)
		end)
	end)

	describe("ProfileRepair v2 › chaque champ : bornes et valeurs sûres", function()
		-- { chemin réparé attendu, abîmer(d), vérifier(d) }
		local cases = {
			{
				"version",
				function(d)
					d.version = 2.5
				end,
				function(d)
					return d.version == 2
				end,
			},
			{
				"R",
				function(d)
					d.R = 401
					d.bestR = 401
				end,
				function(d)
					return d.R == MAX_R and d.bestR == MAX_R
				end,
			},
			{
				"bestR",
				function(d)
					d.R, d.bestR = 9, 4
				end,
				function(d)
					return d.bestR == 9 -- bestR = max(bestR, r)
				end,
			},
			{
				"bestR",
				function(d)
					d.bestR = 0 / 0
				end,
				function(d)
					return d.bestR == d.R
				end,
			},
			{
				"bestR",
				function(d)
					d.bestR = 1e9
				end,
				function(d)
					return d.bestR == MAX_R
				end,
			},
			{
				"ascend",
				function(d)
					d.ascend = 61
				end,
				function(d)
					return d.ascend == MAX_A
				end,
			},
			{
				"ascend",
				function(d)
					d.ascend = "deux"
				end,
				function(d)
					return d.ascend == 0 and d.regainBonusA == 0
				end,
			},
			{
				"regainBonusA",
				function(d)
					d.regainBonusA = 3 -- A = 2
				end,
				function(d)
					return d.regainBonusA == 2
				end,
			},
			{
				"regainBonusA",
				function(d)
					d.regainBonusA = 0 / 0
				end,
				function(d)
					return d.regainBonusA == 2 -- illisible : déjà donné pour A (jamais deux fois)
				end,
			},
			{
				"memoryR",
				function(d)
					d.memoryR = 22 -- au-delà du Record R 21
				end,
				function(d)
					return d.memoryR == 0
				end,
			},
			{
				"memoryR",
				function(d)
					d.memoryR = -1
				end,
				function(d)
					return d.memoryR == 0
				end,
			},
			{
				"memoryR",
				function(d)
					d.memoryR = 14.7
				end,
				function(d)
					return d.memoryR == 14
				end,
			},
			{
				"memoryR",
				function(d)
					d.memoryR = "21"
				end,
				function(d)
					return d.memoryR == 0
				end,
			},
			{
				"confetti",
				function(d)
					d.confetti = -3
				end,
				function(d)
					return d.confetti == 0 and d.confettiTotal == 900
				end,
			},
			{
				"confettiTotal",
				function(d)
					d.confetti, d.confettiTotal = 50, 9
				end,
				function(d)
					return d.confetti == 50 and d.confettiTotal == 50 -- total relevé, poche gardée
				end,
			},
			{
				"confettiTotal",
				function(d)
					d.confettiTotal = 2e9
				end,
				function(d)
					return d.confettiTotal == 1e9
				end,
			},
			{
				"tiles.gloves",
				function(d)
					d.tiles.gloves = 41
				end,
				function(d)
					return d.tiles.gloves == 40
				end,
			},
			{
				"tiles.school",
				function(d)
					d.tiles.school = 2.5
				end,
				function(d)
					return d.tiles.school == 2
				end,
			},
			{
				"tiles.monuments",
				function(d)
					d.tiles.monuments = 0 / 0
				end,
				function(d)
					return d.tiles.monuments == 0
				end,
			},
			{
				"star.cap",
				function(d)
					d.tiles.star = 8 -- r = 9 : plafond de la boucle
				end,
				function(d)
					return d.tiles.star == Prestige.starCap(9)
				end,
			},
			{
				"star.cap",
				function(d)
					d.tiles.snack = 11 -- Tapis Étoilé seulement après le Tapis 12
				end,
				function(d)
					return d.tiles.star == 0 and d.tiles.snack == 11
				end,
			},
			{
				"monument.cap",
				function(d)
					d.R, d.bestR, d.ascend, d.regainBonusA = 9, 9, 0, 0
					d.unlocksSeen = 9
					d.tiles.monuments = 3 -- Record R 9 : 2 Monuments ouverts
					d.atelier[W.springboard], d.atelier[W.plume] = 0, 0
					d.cosmetics.theme = "color"
				end,
				function(d)
					return d.tiles.monuments == 2
				end,
			},
			{
				"cozyBed.cap",
				function(d)
					d.R, d.bestR, d.ascend, d.regainBonusA = 2, 2, 0, 0
					d.unlocksSeen = 2
					d.tiles.snack, d.tiles.star, d.tiles.gloves, d.tiles.school, d.tiles.monuments =
						0, 0, 0, 0, 0
					d.atelier[W.springboard], d.atelier[W.plume] = 0, 0
					d.cosmetics.theme = "color"
				end,
				function(d)
					return d.tiles.cozyBed == false
				end,
			},
			{
				"springboard.cap",
				function(d)
					d.ascend, d.regainBonusA = 0, 0 -- Tremplin : A ≥ 1
				end,
				function(d)
					return d.atelier[W.springboard] == 0 and d.atelier[W.plume] == 1
				end,
			},
			{
				"atelier",
				function(d)
					table.insert(d.atelier, 5) -- une case de trop
				end,
				function(d)
					return #d.atelier == #Upgrades.WorkshopRows and d.atelier[W.gift] == 2
				end,
			},
			{
				"atelier",
				function(d)
					d.atelier = { 0, 2 } -- trop court (vieux catalogue)
				end,
				function(d)
					return #d.atelier == #Upgrades.WorkshopRows and d.atelier[2] == 2
				end,
			},
			{
				"atelier.gift",
				function(d)
					d.atelier[W.gift] = 9 -- 2 niveaux
				end,
				function(d)
					return d.atelier[W.gift] == 2
				end,
			},
			{
				"atelierCosmetics",
				function(d)
					d.atelierCosmetics = { [1] = 1025, [3] = 5, x = 1 }
				end,
				function(d)
					return Tables.deepEqual(d.atelierCosmetics, { 1025, 0, 5 })
				end,
			},
			{
				"fun.palettes.cap",
				function(d)
					d.R, d.bestR, d.ascend, d.regainBonusA = 0, 0, 0, 0
					d.unlocksSeen = 0
					d.tiles.snack, d.tiles.star, d.tiles.gloves, d.tiles.school, d.tiles.monuments =
						0, 0, 0, 0, 0
					d.tiles.cozyBed = false
					d.atelier = Schema.defaultsFor(2).atelier
					d.cosmetics.theme = "color"
					d.decoPerso.slots = Schema.defaultsFor(2).decoPerso.slots
				end,
				function(d)
					return not Bitset.has(d.atelierCosmetics, 1) and not Bitset.has(d.atelierCosmetics, 11)
				end,
			},
			{
				"decorBuilds",
				function(d)
					d.decorBuilds = { 11, -1, 2.5 }
				end,
				function(d)
					return #d.decorBuilds == 18
						and d.decorBuilds[1] == 10
						and d.decorBuilds[2] == 0
						and d.decorBuilds[3] == 2
				end,
			},
			{
				"stats.upgradesBought",
				function(d)
					d.stats.upgradesBought = 3.5
				end,
				function(d)
					return d.stats.upgradesBought == 3
				end,
			},
			{
				"stats.petitSplorches",
				function(d)
					d.stats.petitSplorches = -4
				end,
				function(d)
					return d.stats.petitSplorches == 0
				end,
			},
			{
				"unlocksSeen",
				function(d)
					d.unlocksSeen = 30
				end,
				function(d)
					return d.unlocksSeen == 21
				end,
			},
			{
				"unlocksSeen",
				function(d)
					d.unlocksSeen = 0 / 0
				end,
				function(d)
					return d.unlocksSeen == 21 -- illisible : aucune carte « Nouveau » remontrée
				end,
			},
			{
				"carnet",
				function(d)
					d.carnet = { 0 / 0 }
				end,
				function(d)
					return Tables.deepEqual(d.carnet, { 0 })
				end,
			},
			{
				"mastery",
				function(d)
					d.mastery = {}
				end,
				function(d)
					return #d.mastery == math.max(1, math.ceil(#Species.List / 32)) and d.mastery[1] == 0
				end,
			},
			{
				"weeklyTrack.points",
				function(d)
					d.weeklyTrack.points = 2e6
				end,
				function(d)
					return d.weeklyTrack.points == 1e6
				end,
			},
			{
				"weeklyTrack.claimed",
				function(d)
					d.weeklyTrack.claimed = { 4294967296 }
				end,
				function(d)
					return Tables.deepEqual(d.weeklyTrack.claimed, { 0 })
				end,
			},
			{
				"weeklyTrack.firstPeriodEnd",
				function(d)
					d.weeklyTrack.firstPeriodEnd = -1
				end,
				function(d)
					return d.weeklyTrack.firstPeriodEnd == 0
				end,
			},
			{
				"weeklyTrack.challenges",
				function(d)
					d.weeklyTrack.challenges = {
						{ id = 12, p = 30, done = true },
						{ id = 12, p = 1, done = false }, -- doublon
						{ id = 99, p = 1, done = false }, -- inconnu
						{ id = 4, p = -2, done = "oui" },
						{ id = 5, p = 1, done = false },
						{ id = 6, p = 1, done = false }, -- au-delà de 3
					}
				end,
				function(d)
					local list = d.weeklyTrack.challenges
					return #list == Quests.WeeklyTrack.ChallengesPerWeek
						and list[1].id == 12
						and list[2].id == 4
						and list[2].p == 0
						and list[2].done == false
						and list[3].id == 5
				end,
			},
			{
				"onboarding.nextBuyShown",
				function(d)
					d.onboarding.nextBuyShown = 1
				end,
				function(d)
					return d.onboarding.nextBuyShown == false
				end,
			},
			{
				"season.frostDays",
				function(d)
					d.season.frostDays = 0 / 0
				end,
				function(d)
					return d.season.frostDays == 0 and type(d.season.premium) == "boolean"
				end,
			},
			{
				"caps.fameSplorch",
				function(d)
					d.caps.fameSplorch = 51
				end,
				function(d)
					return d.caps.fameSplorch == Balance.CapsV2.fameSplorch
				end,
			},
			{
				"caps.starRain",
				function(d)
					d.caps.starRain = -1
				end,
				function(d)
					return d.caps.starRain == 0
				end,
			},
			{
				"decoPerso.slots.2",
				function(d)
					d.decoPerso.slots[2] = 7 -- objet non possédé
				end,
				function(d)
					return d.decoPerso.slots[2] == 0 and d.decoPerso.slots[1] == 1
				end,
			},
			{
				"decoPerso.slots.3",
				function(d)
					d.decoPerso.slots[3] = 1 -- déjà posé à l'emplacement 1
				end,
				function(d)
					return d.decoPerso.slots[3] == 0 and d.decoPerso.slots[1] == 1
				end,
			},
			{
				"decoPerso.slots",
				function(d)
					d.decoPerso.slots = { 1, 41, 2.5 }
				end,
				function(d)
					local s = d.decoPerso.slots
					return #s == 12 and s[1] == 1 and s[2] == 0 and s[3] == 0
				end,
			},
			{
				"decoPerso.owned",
				function(d)
					d.decoPerso.owned = { 1 }
				end,
				function(d)
					return #d.decoPerso.owned == 2 and d.decoPerso.slots[12] == 0 -- objet 40 plus possédé
				end,
			},
			{
				"hearts.givenTo",
				function(d)
					local list = { 5, 5, 1.5, "x" }
					for i = 1, 30 do
						table.insert(list, 1000 + i)
					end
					d.hearts.givenTo = list
				end,
				function(d)
					local g = d.hearts.givenTo
					return #g == Balance.Hearts.PerDay and g[1] == 5 and g[2] == 1001
				end,
			},
			{
				"hearts.givenTo",
				function(d)
					d.hearts.givenTo = { [1] = 7, [3] = 9, x = 4 } -- à trous (vieux bug) : entrées gardées
				end,
				function(d)
					return Tables.deepEqual(d.hearts.givenTo, { 7, 9 })
				end,
			},
			{
				"hearts.receivedTotal",
				function(d)
					d.hearts.receivedTotal = -1
				end,
				function(d)
					return d.hearts.receivedTotal == 0
				end,
			},
			-- lot A4 (docs/04 §27.12 A4-4) : compteurs, piste, palette, coussins, halo, taille des emplacements
			{
				"stats.objectivesClaimed",
				function(d)
					d.stats.objectivesClaimed = 2.5
				end,
				function(d)
					return d.stats.objectivesClaimed == 2
				end,
			},
			{
				"stats.tracksDone",
				function(d)
					d.stats.tracksDone = -3
				end,
				function(d)
					return d.stats.tracksDone == 0
				end,
			},
			{
				"moon.sessions",
				function(d)
					d.moon.sessions = 1e10
				end,
				function(d)
					return d.moon.sessions == 1e9 and d.moon.lastSession == 0
				end,
			},
			{
				"moon.sessions",
				function(d)
					d.moon.sessions = 0 / 0
				end,
				function(d)
					return d.moon.sessions == 0
				end,
			},
			{
				"weeklyTrack.won",
				function(d)
					d.weeklyTrack.won = { "x", 2 ^ 32 }
				end,
				function(d)
					return Tables.deepEqual(d.weeklyTrack.won, { 0, 0 })
				end,
			},
			{
				"weeklyTrack.won",
				function(d)
					d.weeklyTrack.won = 5
				end,
				function(d)
					return Tables.deepEqual(d.weeklyTrack.won, { 0 })
				end,
			},
			{
				"weeklyTrack.play",
				function(d)
					d.weeklyTrack.play = { 90000, -1, 2.5, 0, 0, 0, 0, 7, 8 }
				end,
				function(d)
					return Tables.deepEqual(d.weeklyTrack.play, { 86400, 0, 2, 0, 0, 0, 0 })
				end,
			},
			{
				"weeklyTrack.play",
				function(d)
					d.weeklyTrack.play = { [2] = 60 } -- à trous (vieux bug) : allongé à 7 cases
				end,
				function(d)
					return Tables.deepEqual(d.weeklyTrack.play, { 0, 60, 0, 0, 0, 0, 0 })
				end,
			},
			{
				"weeklyTrack.playDay",
				function(d)
					d.weeklyTrack.playDay = -5
				end,
				function(d)
					return d.weeklyTrack.playDay == 0
				end,
			},
			{
				"cosmetics.palette",
				function(d)
					d.cosmetics.palette = "inconnue"
				end,
				function(d)
					return d.cosmetics.palette == "" and d.cosmetics.cushions == "pinkCushions"
				end,
			},
			{
				"cosmetics.palette",
				function(d)
					d.cosmetics.palette = 3
				end,
				function(d)
					return d.cosmetics.palette == ""
				end,
			},
			{
				"cosmetics.cushions",
				function(d)
					d.cosmetics.cushions = "peachPalette" -- une palette, pas des coussins
				end,
				function(d)
					return d.cosmetics.cushions == "" and d.cosmetics.palette == "candy"
				end,
			},
			{
				"settings.haloOn",
				function(d)
					d.settings.haloOn = "oui"
				end,
				function(d)
					return d.settings.haloOn == true
				end,
			},
			{
				"decoPerso.slots.9",
				function(d)
					d.decoPerso.slots[1], d.decoPerso.slots[9] = 0, 1 -- petit objet sur un grand emplacement
				end,
				function(d)
					return d.decoPerso.slots[9] == 0 and d.decoPerso.slots[12] == 40
				end,
			},
			{
				"decoPerso.slots.2",
				function(d)
					d.decoPerso.slots[12], d.decoPerso.slots[2] = 0, 40 -- grand objet sur un petit emplacement
				end,
				function(d)
					return d.decoPerso.slots[2] == 0 and d.decoPerso.slots[1] == 1
				end,
			},
			{
				"cosmetics.theme",
				function(d)
					d.cosmetics.theme = "rainbowUnknown"
				end,
				function(d)
					return d.cosmetics.theme == "color"
				end,
			},
			{
				"cosmetics.theme",
				function(d)
					d.cosmetics.theme = "celestial" -- A ≥ 5, A = 2
				end,
				function(d)
					return d.cosmetics.theme == "color"
				end,
			},
			{
				"cosmetics.theme",
				function(d)
					d.cosmetics.theme = "moonlit" -- Squishydex : 160 tampons
				end,
				function(d)
					return d.cosmetics.theme == "color"
				end,
			},
		}

		it("chaque valeur abîmée : réparée, nommée, profil sain, idempotent", function()
			for i, case in cases do
				local d = played()
				case[2](d)
				local fixes = Repair.repair(d)
				expect({ case = i, path = case[1], fixed = has(fixes, case[1]) }).toEqual({
					case = i,
					path = case[1],
					fixed = true,
				})
				expect({ case = i, path = case[1], value = case[3](d) == true }).toEqual({
					case = i,
					path = case[1],
					value = true,
				})
				expect({ case = i, path = case[1], bad = Invariants.profile(d) }).toEqual({
					case = i,
					path = case[1],
					bad = {},
				})
				expect({ case = i, again = Repair.repair(d) }).toEqual({ case = i, again = {} })
			end
		end)

		it(
			"lot A4 : chaque palette et chaque coussin connus gardés ; « » gardé ; objet à sa taille gardé",
			function()
				local palettes = {
					"candy",
					"mint",
					"lavender",
					"rainbow",
					"softNight",
					"icing",
					"fireworks",
					"peachPalette",
				}
				for _, id in palettes do
					local d = played()
					d.cosmetics.palette = id
					expect({ id = id, fixes = Repair.repair(d) }).toEqual({ id = id, fixes = {} })
				end
				local d = played()
				d.cosmetics.palette, d.cosmetics.cushions = "", ""
				expect(Repair.repair(d)).toEqual({})
				-- chaque objet possédé posé sur chaque emplacement de sa taille : gardé
				local C = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				for n, item in C.DecoPerso do
					for slot, size in C.DecoSlots do
						local x = played()
						x.decoPerso.owned = { 4294967295, 255 }
						x.decoPerso.slots = table.create(12, 0)
						x.decoPerso.slots[slot] = n
						local fixes = Repair.repair(x)
						local kept = x.decoPerso.slots[slot] == n
						expect({ n = n, slot = slot, kept = kept }).toEqual({
							n = n,
							slot = slot,
							kept = item.size == size,
						})
						expect({ n = n, slot = slot, fixes = #fixes }).toEqual({
							n = n,
							slot = slot,
							fixes = if item.size == size then 0 else 1,
						})
					end
				end
			end
		)

		it("habillages gagnés gardés (Record R, A, Squishydex, jours de Plop)", function()
			for _, pair in
				{
					{ "caramel", { bestR = 3 } },
					{ "royal", { bestR = 21 } },
					{ "aurora", { ascend = 3 } },
					{ "moonlit", { dexRewards = 160 } },
					{ "candyNight", { plopDays = 75 } },
					{ "color", {} },
				}
			do
				local d = healthy({ R = 3, bestR = pair[2].bestR or 3, unlocksSeen = 0 })
				d.ascend = pair[2].ascend or 0
				d.dex.rewards = pair[2].dexRewards or 0
				d.plopDays = pair[2].plopDays or 0
				d.cosmetics.theme = pair[1]
				expect({ theme = pair[1], fixes = Repair.repair(d) }).toEqual({ theme = pair[1], fixes = {} })
				expect(d.cosmetics.theme).toBe(pair[1])
			end
		end)

		-- lot A4 (D21, journal A4-14) : SquishyService connaît les tenues v2.0 d'un profil v2 ; la
		-- réparation les retirait de chaque squishy à chaque chargement (tenue perdue, ProfileRepaired)
		it(
			"tenues v2.0 portées (partyHat, starGlasses, buildersCrown, polkaBow) gardées sur un profil v2 ; profil v1 : retirées comme avant",
			function()
				for _, id in { "partyHat", "starGlasses", "buildersCrown", "polkaBow" } do
					local d = played()
					d.outfits.owned[id] = 1
					d.squishies["1"].o = id
					expect({ id = id, fixes = Repair.repair(d) }).toEqual({ id = id, fixes = {} })
					expect(d.squishies["1"].o).toBe(id)
					settled(d)
					-- profil v1 : tenue inconnue de la v1.3, retirée (réparation d'aujourd'hui)
					local v1 = Schema.defaults()
					v1.squishies = { ["1"] = rec({ o = id }) }
					v1.nextUid = 2
					v1.outfits.owned[id] = 1
					expect({ id = id, fixes = Repair.repair(v1) }).toEqual({
						id = id,
						fixes = { "squishies.1.o" },
					})
					expect(v1.squishies["1"].o).toBe("")
				end
			end
		)

		it(
			"ensembles de bits : un mot au-delà de la taille n'est jamais tronqué (espèce future)",
			function()
				local d = played()
				d.mastery = { 4294967295, 4294967295, 4294967295, 7 } -- 4 mots : 104 espèces futures
				expect(Repair.repair(d)).toEqual({})
				expect(#d.mastery).toBe(4)
				local big = played()
				big.carnet = table.create(200, 1) -- au-delà de Bitset.MaxBits : ramené à 128 mots
				Repair.repair(big)
				expect(#big.carnet).toBe(Bitset.MaxBits // 32)
				settled(big)
			end
		)

		it("clés de premier niveau v2 au mauvais type : remplacées par leur valeur par défaut", function()
			local d = played()
			d.atelier = "x"
			d.weeklyTrack = 5
			d.decoPerso = true
			d.hearts = { givenTo = "x" }
			d.mastery = false
			d.memoryR = { 1 }
			local fixes = Repair.repair(d)
			for _, path in { "atelier", "weeklyTrack", "decoPerso", "hearts.givenTo", "mastery", "memoryR" } do
				expect({ path = path, fixed = has(fixes, path) }).toEqual({ path = path, fixed = true })
			end
			expect(d.memoryR).toBe(0)
			settled(d)
		end)
	end)

	describe("ProfileRepair v2 › memoryR et la 1re boucle record (INT-A1-MEMORY)", function()
		-- Grands et Petits Splorch jusqu'à r = target (plus gros squishy rendu prêt à chaque fois)
		local now = 1000
		local function splorchTo(d, target)
			while Prestige.r(d) < target do
				d.squishies["1"].z = Prestige.target(Prestige.r(d))
				d.squishies["1"].zg = 0
				d.growth.G = 0
				now += 10
				local _, report = Prestige.apply(d, "splorch", now)
				assert(report.applied, "Splorch refusé à r = " .. Prestige.r(d))
			end
		end
		local function ascend(d)
			now += 10
			local _, report = Prestige.apply(d, "ascend", now)
			assert(report.applied, "Ascension refusée")
		end
		-- Joue : jusqu'à la condition de la 1re Ascension, Ascension, retour au record, record suivant
		local function chain(d)
			local req = Prestige.reqR(1)
			splorchTo(d, req)
			expect(Prestige.firstRecordLoop(d)).toBe(false) -- A = 0 : aucun retour au record
			ascend(d)
			expect({ A = d.ascend, memoryR = d.memoryR }).toEqual({ A = 1, memoryR = 0 })
			splorchTo(d, req - 1)
			expect(Prestige.firstRecordLoop(d)).toBe(false) -- r < Record R
			splorchTo(d, req)
			-- retour au record : Record R noté, 1re boucle record reconnue (× 1,25)
			expect({ memoryR = d.memoryR, bonus = d.regainBonusA, first = Prestige.firstRecordLoop(d) }).toEqual({
				memoryR = req,
				bonus = 1,
				first = true,
			})
			expect(Repair.repair(d)).toEqual({}) -- profil de jeu sain : rien à réparer
			expect(Prestige.firstRecordLoop(d)).toBe(true)
			splorchTo(d, req + 1)
			expect({ bestR = d.bestR, first = Prestige.firstRecordLoop(d) }).toEqual({
				bestR = req + 1,
				first = false,
			})
			expect(Invariants.profile(d)).toEqual({})
		end

		it("profil neuf : memoryR = 0, puis la chaîne complète jusqu'au × 1,25", function()
			local d = healthy()
			expect(d.memoryR).toBe(0)
			expect(Prestige.firstRecordLoop(d)).toBe(false)
			chain(d)
		end)

		it("profil v1 migré (v1.json, Record R 12) : memoryR = 0, puis la chaîne complète", function()
			local d = loadV2(readJson("v1.json"))
			expect(d.memoryR).toBe(0)
			expect(Prestige.firstRecordLoop(d)).toBe(false)
			chain(d)
		end)

		it(
			"profil abîmé réparé : memoryR illisible → 0, jamais un × 1,25 inventé ; valeur saine gardée",
			function()
				-- juste après un retour au record (r = Record R = 15, A = 1, bonus donné pour A)
				local function atRegain(memoryR)
					return healthy({
						R = 15,
						bestR = 15,
						ascend = 1,
						regainBonusA = 1,
						memoryR = memoryR,
						unlocksSeen = 15,
					})
				end
				for _, bad in { 0 / 0, "15", -15, 16, 1e300, { 15 }, true } do
					local d = atRegain(bad)
					local fixes = Repair.repair(d)
					expect({ bad = tostring(bad), fixed = has(fixes, "memoryR"), m = d.memoryR }).toEqual({
						bad = tostring(bad),
						fixed = true,
						m = 0,
					})
					expect(Prestige.firstRecordLoop(d)).toBe(false)
					settled(d)
				end
				local ok = atRegain(15)
				expect(Repair.repair(ok)).toEqual({})
				expect(Prestige.firstRecordLoop(ok)).toBe(true)
				-- champ absent (profil v2 écrit avant la décision) : reconcile le crée à 0
				local old = atRegain(0)
				old.memoryR = nil
				Tables.reconcile(old, Schema.defaultsFor(2))
				expect(old.memoryR).toBe(0)
				expect(Repair.repair(old)).toEqual({})
				expect(Prestige.firstRecordLoop(old)).toBe(false)
				-- puis la chaîne repart normalement
				local d = atRegain(0 / 0)
				Repair.repair(d)
				d.R, d.bestR, d.regainBonusA, d.unlocksSeen = 0, 0, 0, 0
				d.ascend = 0
				chain(d)
			end
		)
	end)

	describe("ProfileRepair v2 › propriétés (graine fixe)", function()
		it(
			"400 profils v2 abîmés au hasard : jamais d'erreur, sain, idempotent, JSON exact, accepté par Roblox",
			function()
				local anyNum = Props.anyNumber()
				local anyVal = Props.any()
				local V2_TOP = {
					"bestR",
					"ascend",
					"regainBonusA",
					"memoryR",
					"confetti",
					"confettiTotal",
					"atelier",
					"atelierCosmetics",
					"decorBuilds",
					"carnet",
					"weeklyTrack",
					"mastery",
					"unlocksSeen",
					"decoPerso",
					"hearts",
					"R",
					"version",
				}
				local function numbers(rng, n)
					local t = {}
					for i = 1, n do
						if rng.chance(0.9) then
							t[i] = if rng.chance(0.5) then rng.int(0, 50) else anyNum.gen(rng)
						end
					end
					if rng.chance(0.1) then
						t.x = 1
					end
					return t
				end
				local gen = Props.gen(function(rng)
					local d = played()
					d.version = 2
					for _, key in V2_TOP do
						local r = rng.next()
						if r < 0.15 then
							d[key] = anyVal.gen(rng)
						elseif r < 0.4 then
							d[key] = if type(d[key]) == "table"
								then numbers(rng, rng.int(0, 30))
								else anyNum.gen(rng)
						elseif r < 0.55 and type(d[key]) == "number" then
							d[key] = rng.int(-5, 500)
						end
					end
					for _, key in { "star", "gloves", "school", "monuments", "snack", "decor", "pens" } do
						if rng.chance(0.3) then
							d.tiles[key] = if rng.chance(0.5) then rng.int(-2, 45) else anyNum.gen(rng)
						end
					end
					if rng.chance(0.2) then
						d.tiles.cozyBed = anyVal.gen(rng)
					end
					if type(d.weeklyTrack) == "table" and rng.chance(0.5) then
						local list = {}
						for i = 1, rng.int(0, 6) do
							list[i] = {
								id = if rng.chance(0.8) then rng.int(0, 14) else anyVal.gen(rng),
								p = anyNum.gen(rng),
								done = if rng.chance(0.8) then rng.chance(0.5) else anyVal.gen(rng),
							}
						end
						d.weeklyTrack.challenges = list
					end
					if type(d.decoPerso) == "table" and rng.chance(0.5) then
						d.decoPerso.slots = numbers(rng, rng.int(0, 15))
					end
					if type(d.hearts) == "table" and rng.chance(0.5) then
						d.hearts.givenTo = numbers(rng, rng.int(0, 30))
					end
					for _, pair in
						{
							{ "stats", "upgradesBought" },
							{ "stats", "petitSplorches" },
							{ "season", "frostDays" },
							{ "caps", "fameSplorch" },
							{ "caps", "starRain" },
							{ "onboarding", "nextBuyShown" },
							{ "onboarding", "welcomeV2Pending" },
						}
					do
						if rng.chance(0.15) then
							d[pair[1]][pair[2]] = anyVal.gen(rng)
						end
					end
					if rng.chance(0.3) then
						d.cosmetics.theme =
							rng.pick({ "color", "neon", "celestial", "moonlit", "x", "royal" })
					end
					return d
				end)
				Props.check(400, gen, function(raw)
					-- un vrai DataStore rend du JSON : pas de cycle, pas de Vector3
					local okJson, json = pcall(serde.encode, "json", raw)
					if not okJson then
						return true
					end
					local d = serde.decode("json", json)
					-- comme DataService sur un serveur v2 : version illisible = la plus ancienne (migrée) ;
					-- version plus récente = refusée sans rien lire
					local version = if type(d.version) == "number" and d.version == d.version
						then d.version
						else 0
					if version > 2 then
						return true
					end
					local ok, fixes = pcall(function()
						Schema.migrate(d, version, 2)
						Tables.reconcile(d, Schema.defaultsFor(2))
						return Repair.repair(d)
					end)
					if not ok then
						return false, "erreur : " .. tostring(fixes)
					end
					if not (type(d.version) == "number" and d.version >= 2) then
						return false, "version perdue"
					end
					local bad = Invariants.profile(d)
					if #bad > 0 then
						return false, "invariants : " .. table.concat(bad, ", ")
					end
					local again = Repair.repair(d)
					if #again > 0 then
						return false, "non idempotent : " .. table.concat(again, ", ")
					end
					if not Tables.deepEqual(serde.decode("json", serde.encode("json", d)), d) then
						return false, "JSON"
					end
					local okRoblox, why = Chaos.check(d)
					if not okRoblox then
						return false, "Roblox : " .. tostring(why)
					end
					-- jamais un × 1,25 hors d'un vrai retour au record
					if Prestige.firstRecordLoop(d) and d.memoryR ~= d.bestR then
						return false, "firstRecordLoop"
					end
					return true
				end)
			end
		)

		it("profil v1 migré puis abîmé au hasard (200 cas) : même garanties", function()
			local anyNum = Props.anyNumber()
			local gen = Props.gen(function(rng)
				local d = readJson("v1.json")
				for _, key in { "R", "coins", "pot", "ascend", "fame" } do
					if rng.chance(0.3) then
						d[key] = anyNum.gen(rng)
					end
				end
				for _, key in { "snack", "decor", "pens" } do
					if rng.chance(0.3) then
						d.tiles[key] = anyNum.gen(rng)
					end
				end
				if rng.chance(0.2) then
					d.tiles.cozyBed = rng.chance(0.5)
				end
				if rng.chance(0.2) then
					d.version = rng.pick({ 0, 1, "1", 0.5 })
				end
				return d
			end)
			Props.check(200, gen, function(raw)
				local okJson, json = pcall(serde.encode, "json", raw)
				if not okJson then
					return true
				end
				local d = serde.decode("json", json)
				local version = if type(d.version) == "number" and d.version == d.version
					then d.version
					else 0
				local ok, err = pcall(function()
					Schema.migrate(d, version, 2)
					Tables.reconcile(d, Schema.defaultsFor(2))
					Repair.repair(d)
				end)
				if not ok then
					return false, "erreur : " .. tostring(err)
				end
				local bad = Invariants.profile(d)
				if #bad > 0 then
					return false, "invariants : " .. table.concat(bad, ", ")
				end
				if #Repair.repair(d) > 0 then
					return false, "non idempotent"
				end
				if d.memoryR ~= 0 or d.bestR < Prestige.r(d) then
					return false, "progression"
				end
				return true
			end)
		end)
	end)
end
