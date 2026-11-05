--!nocheck
-- DataChaos (paquet ranch, docs/04 §17.1 couche e, §18.2) : le jeu complet sur un DataStore en
-- désordre (tests/harness/Chaos) : pannes au chargement et à la sauvegarde, latence, verrou entre deux
-- serveurs et retour immédiat sur l'autre, fermeture à 16 avec un magasin lent, migration de la
-- sauvegarde-témoin v0, profil abîmé réparé puis joué, reçu rejoué pendant une panne, mutations « au
-- départ » présentes dans la sauvegarde de départ (§1 règle 15), rebase hors ligne avant tout
-- règlement. Après CHAQUE écriture : valeur sérialisable par Roblox (aucun tableau à trous, aucune
-- table mixte) et Invariants.dense sur les tableaux du profil.
-- Schéma v2 (lot A2, docs/04 §27.2, §27.10) : les mêmes pannes sur des serveurs v2 (interrupteur figé
-- SchemaV2 ouvert DANS LE TEST, avant le premier require du schéma) : migration v1 → v2 au chargement
-- malgré les pannes, une seule fois même si la sauvegarde qui suit est perdue, quotas dépassés à
-- l'arrivée de 16 joueurs, reconnexion pendant la sauvegarde de départ, fermeture, profil v2 abîmé
-- réparé, déploiement progressif (un serveur v1 refuse le profil v2 sans rien écrire). Interrupteur
-- coupé (jeu de base) : un profil v1 est réécrit en v1, sans aucun champ v2.
local fs = require("@lune/fs")
local task = require("@lune/task")
local Bots = require("../harness/Bots")
local Chaos = require("../harness/Chaos")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local live = {}

	local function waitUntil(cond, timeout)
		local start = os.clock()
		while not cond() and os.clock() - start < (timeout or 5) do
			task.wait(0.005)
		end
		return cond()
	end

	-- Magasin partagé dont chaque écriture est vérifiée (tableaux denses du profil)
	local function newStore(h)
		local shared = Chaos.store()
		local Invariants = h:require("ReplicatedStorage.Shared.Logic.Invariants")
		shared.problems = {}
		shared.onWrite = function(key, value)
			local data = value and value.data
			if type(data) == "table" then
				-- (un vieil enregistrement réécrit tel quel avec le verrou peut ne pas avoir encore la clé ;
				-- tableaux v2 seulement dans un profil v2)
				for _, path in
					{ "trophies", "atelier", "atelierCosmetics", "decorBuilds", "carnet", "mastery" }
				do
					if data[path] ~= nil and not Invariants.dense(data[path]) then
						table.insert(shared.problems, key .. "." .. path)
					end
				end
				if type(data.dex) == "table" then
					for _, path in { "mut", "stars", "fam" } do
						if data.dex[path] ~= nil and not Invariants.dense(data.dex[path]) then
							table.insert(shared.problems, key .. ".dex." .. path)
						end
					end
				end
			end
		end
		return shared
	end

	-- Harnais d'un serveur v2 : Config/Features.Defaults.SchemaV2 ouvert dans CE harnais, avant que
	-- Data/Schema soit chargé (interrupteur figé : lu une fois, à la création du module)
	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require("ReplicatedStorage.Shared.Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local function bootWith(H, shared, jobId, before)
		local caught = {}
		local w = Chaos.boot(H, Bots, shared, jobId, {
			t0 = T0,
			before = function(w)
				local DS = w.DS.Settings
				DS.AUTOSAVE_INTERVAL = 1e6
				DS.RETRY_BASE_DELAY = 0.001
				DS.LOCKED_RETRY_DELAY = 0.01
				DS.RELEASE_RETRY_DELAY = 0.005
				DS.RELEASE_RETRY_MAX = 0.03
				DS.RELEASE_RETRY_WINDOW = 5
				DS.RELEASE_RETRY_POLL = 0.002
				DS.REJOIN_WAIT = 0.5
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				if before then
					before(w)
				end
			end,
		})
		w.caught = caught
		w.Economy = w.h:require(S .. "EconomyService")
		w.Squishy = w.h:require(S .. "SquishyService")
		w.Invariants = w.h:require("ReplicatedStorage.Shared.Logic.Invariants")
		table.insert(live, w.h)
		return w
	end

	local function server(shared, jobId, before)
		return bootWith(Harness, shared, jobId, before)
	end

	-- Serveur v2 (Schema.VERSION = 2)
	local function serverV2(shared, jobId, before)
		local w = bootWith(HarnessV2, shared, jobId, before)
		assert(w.Schema.VERSION == 2, "serveur v2 attendu")
		return w
	end

	local function disposeAll()
		for _, h in live do
			h:dispose()
		end
		table.clear(live)
	end

	-- Avertissements attendus (pannes simulées : DataService les journalise) ; rien d'autre
	local function clean(w, shared, allowed)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		local unexpected = {}
		for _, line in w.h:warnings() do
			local ok = false
			for _, pattern in allowed or {} do
				if string.find(line, pattern, 1, true) then
					ok = true
				end
			end
			if not ok then
				table.insert(unexpected, line)
			end
		end
		expect(table.concat(unexpected, "\n")).toBe("")
		expect(table.concat(shared.problems, "\n")).toBe("")
		expect(table.concat(shared.refused, "\n")).toBe("")
	end

	local FAIL_WARN = { "échec de sauvegarde", "panne simulée", "nouveaux essais", "nouvel essai" }

	describe("DataChaos › pannes, latence, verrou", function()
		it("pannes au chargement : chargé après les essais ; aucune donnée vide sauvegardée", function()
			disposeAll()
			local probe = Harness.new()
			local shared = newStore(probe)
			local w = server(shared, "A")
			shared.fail.UpdateAsync = 2
			local p = Bots.join(1)
			expect(w.DS.isLoaded(p)).toBe(true)
			w.Squishy.give(p, { s = 1, m = 0, st = 0, z = 5 }, "starter")
			Bots.leave(p)
			expect(waitUntil(function()
				local d = Chaos.record(shared, 1)
				return d ~= nil and d.nextUid == 2
			end)).toBe(true)
			local saved = Chaos.record(shared, 1)
			expect(w.Invariants.profile(saved)).toEqual({})
			clean(w, shared, FAIL_WARN)
			disposeAll()
		end)

		it(
			"latence et panne à la sauvegarde de départ : nouveaux essais, mutations de départ écrites (lastOnline)",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				local w = server(shared, "A")
				shared.latency = 0.002
				local p = Bots.join(1)
				w.Clock.advance(120)
				shared.fail.UpdateAsync = 3
				Bots.leave(p)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 1)
					return d ~= nil and d.lastOnline == T0 + 120
				end, 8)).toBe(true)
				local saved = Chaos.record(shared, 1)
				expect(saved.growth.t).toBe(T0 + 120)
				clean(w, shared, FAIL_WARN)
				disposeAll()
			end
		)

		it(
			"verrou entre deux serveurs : retour immédiat sur l'autre serveur, absence comptée une seule fois",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				local profile = probe:require("ServerScriptService.Server.Data.Schema").defaults()
				profile.onboarding = { step = 11, done = true, demoDone = true }
				profile.squishies = {
					["1"] = {
						s = 1,
						m = 0,
						st = 1,
						z = 1000,
						zg = 0,
						bf = 1,
						lk = false,
						o = "",
						at = "pen",
						b = 1,
						gd = 0,
					},
				}
				profile.nextUid = 2
				profile.lastOnline = T0 - 3600
				Chaos.seed(shared, 7, profile)
				local a = server(shared, "A")
				local pa = Bots.join(7)
				local da = a.DS.get(pa)
				local potAfterLoad = da.pot
				expect(potAfterLoad > 0).toBe(true) -- 1 h hors ligne, une fois
				a.Clock.advance(60)
				Bots.leave(pa)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 7)
					return d ~= nil and d.lastOnline == T0 + 60
				end)).toBe(true)
				local b = server(shared, "B")
				b.Clock.freeze(T0 + 61)
				local pb = Bots.join(7)
				expect(waitUntil(function()
					return b.DS.isLoaded(pb)
				end)).toBe(true)
				local db = b.DS.get(pb)
				-- 1 s d'absence : aucun gain hors ligne notable, jamais l'heure passée en jeu ni l'ancienne absence
				expect(db.pot < potAfterLoad + 60 * 100).toBe(true)
				expect(db.growth.t).toBe(T0 + 61)
				clean(a, shared, FAIL_WARN)
				clean(b, shared, FAIL_WARN)
				disposeAll()
			end
		)

		it(
			"fermeture du serveur à 16 joueurs avec un magasin lent : chaque profil écrit avec ses mutations de départ",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				local w = server(shared, "A")
				local players = {}
				for i = 1, 16 do
					players[i] = Bots.join(100 + i)
				end
				w.h:settle(3)
				shared.latency = 0.003
				w.Clock.advance(30)
				w.h:close()
				expect(waitUntil(function()
					for i = 1, 16 do
						local d = Chaos.record(shared, 100 + i)
						if d == nil or d.lastOnline ~= T0 + 30 then
							return false
						end
					end
					return true
				end, 10)).toBe(true)
				clean(w, shared, FAIL_WARN)
				disposeAll()
			end
		)
	end)

	describe("DataChaos › profils anciens ou abîmés", function()
		it("sauvegarde-témoin v0 : migrée, complétée, réparée, jouée, réécrite saine", function()
			disposeAll()
			local probe = Harness.new()
			local shared = newStore(probe)
			local Http = probe.game.HttpService
			local v0 = Http:JSONDecode(fs.readFile("tests/fixtures/profiles/v0.json"))
			Chaos.seed(shared, 9, v0)
			local w = server(shared, "A")
			local p = Bots.join(9)
			local data = w.DS.get(p)
			expect(data.coins).toBe(1234)
			expect(data.version).toBe(1)
			expect(w.Invariants.profile(data)).toEqual({})
			w.Squishy.give(p, { s = 1, m = 0, st = 0, z = 1 }, "starter")
			Bots.leave(p)
			expect(waitUntil(function()
				local d = Chaos.record(shared, 9)
				return d ~= nil and d.nextUid == 2
			end)).toBe(true)
			expect(w.Invariants.profile(Chaos.record(shared, 9))).toEqual({})
			clean(w, shared, FAIL_WARN)
			disposeAll()
		end)

		it(
			"profil abîmé (NaN, trous, tenues portées, plafonds) : réparé au chargement, joué, réécrit sain",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				local Schema = probe:require("ServerScriptService.Server.Data.Schema")
				local d = Schema.defaults()
				-- JSON ne garde ni NaN ni trous : on simule ce qu'un vieux bug aurait pu écrire de lisible
				d.coins = -50
				d.growth = { G = -3, g = "x", t = "?" }
				d.squishies = {
					["1"] = {
						s = 1,
						m = 99,
						st = 9,
						z = -5,
						zg = 0,
						bf = 1,
						lk = false,
						o = "sweater",
						at = "pen",
						b = 0,
						gd = -1,
					},
					["2"] = {
						s = 2,
						m = 0,
						st = 0,
						z = 3,
						zg = 0,
						bf = 1,
						lk = false,
						o = "",
						at = "moon",
						b = 0,
						gd = 0,
					},
				}
				d.nextUid = 1
				d.outfits = { owned = {}, worn = { ["1"] = "sweater" } }
				d.caps.petSitBy = { ["5"] = 99 }
				d.dex.fam = { 1 }
				Chaos.seed(shared, 11, d)
				local repaired = nil
				local w = server(shared, "A", function(w)
					w.Signals.ProfileRepaired:Connect(function(_, fixes)
						repaired = fixes
					end)
				end)
				local p = Bots.join(11)
				w.h:settle(2)
				local data = w.DS.get(p)
				expect(repaired ~= nil and #repaired > 0).toBe(true)
				expect(w.Invariants.profile(data)).toEqual({})
				expect(data.nextUid).toBe(3)
				-- jouer : ajout, vente, pression (rien ne casse un invariant)
				local uid = w.Squishy.give(p, { s = 1, m = 0, st = 0, z = 1 }, "test")
				expect(uid).toBe("3")
				expect(w.Invariants.profile(data)).toEqual({})
				Bots.leave(p)
				expect(waitUntil(function()
					local saved = Chaos.record(shared, 11)
					return saved ~= nil and saved.nextUid == 4
				end)).toBe(true)
				expect(w.Invariants.profile(Chaos.record(shared, 11))).toEqual({})
				clean(w, shared, FAIL_WARN)
				disposeAll()
			end
		)
	end)

	describe("DataChaos › achats pendant une panne", function()
		it(
			"reçu pendant une panne : jamais acquitté sans sauvegarde ; rejoué après la panne : crédité une fois",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				local w = server(shared, "A", function(w)
					local Monetization = w.h:require("ReplicatedStorage.Shared.Config.Monetization")
					Monetization.Products.OutfitSweater.id = 702
				end)
				local p = Bots.join(12)
				shared.down = true
				local first = w.h:purchaseProduct(p, 702, "R-1")
				expect(first.Name).toBe("NotProcessedYet")
				local data = w.DS.get(p)
				expect(data.outfits.owned.sweater).toBe(1) -- accordé en mémoire, reçu noté
				shared.down = false
				local again = w.h:purchaseProduct(p, 702, "R-1")
				expect(again.Name).toBe("PurchaseGranted")
				expect(data.outfits.owned.sweater).toBe(1)
				Bots.leave(p)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 12)
					return d ~= nil and table.find(d.receipts, "R-1") ~= nil
				end)).toBe(true)
				expect(Chaos.record(shared, 12).outfits.owned.sweater).toBe(1)
				clean(w, shared, FAIL_WARN)
				disposeAll()
			end
		)

		it("Chaos.check refuse ce que Roblox perdrait : tableau à trous, table mixte, NaN", function()
			expect((Chaos.check({ 1, 2, 3 }))).toBe(true)
			expect((Chaos.check({ a = { 1, 2 }, b = "x" }))).toBe(true)
			expect((Chaos.check({ 1, nil, 3 }))).toBe(false)
			expect((Chaos.check({ 1, 2, x = 1 }))).toBe(false)
			expect((Chaos.check({ a = 0 / 0 }))).toBe(false)
			expect((Chaos.check({ [1.5] = 1 }))).toBe(false)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- Schéma v2 (lot A2) : SchemaV2 ouvert dans le test (serverV2) ; interrupteur coupé ailleurs
	-- ---------------------------------------------------------------------------------------------
	local function readV1(h)
		return h.game.HttpService:JSONDecode(fs.readFile("tests/fixtures/profiles/v1.json"))
	end
	-- Profil v1 migré comme le fera un serveur v2 (étape pure + reconcile), pour les attentes
	local function migrated(h, v1)
		local Schema = h:require("ServerScriptService.Server.Data.Schema")
		local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")
		local d = Schema.migrate(Tables.deepCopy(v1), 1, 2)
		Tables.reconcile(d, Schema.defaultsFor(2))
		return d
	end
	local function hasWarning(w, pattern)
		for _, line in w.h:warnings() do
			if string.find(line, pattern, 1, true) then
				return true
			end
		end
		return false
	end

	describe("DataChaos › schéma v2 (SchemaV2 ouvert dans le test)", function()
		it(
			"interrupteur coupé (jeu de base) : un profil v1 est relu et réécrit en v1, sans aucun champ v2",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				Chaos.seed(shared, 20, readV1(probe))
				local w = server(shared, "A")
				expect(w.Schema.VERSION).toBe(1)
				local p = Bots.join(20)
				local data = w.DS.get(p)
				expect(data.version).toBe(1)
				Bots.leave(p)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 20)
					return d ~= nil and d.lastOnline == T0
				end)).toBe(true)
				local saved = Chaos.record(shared, 20)
				expect(saved.version).toBe(1)
				for key in w.Schema.OWNERS_V2 do
					if w.Schema.OWNERS_V1[key] == nil then
						expect({ key = key, saved = saved[key] }).toEqual({ key = key, saved = nil })
					end
				end
				expect(saved.tiles.star).toBeNil()
				expect(saved.tiles.pens).toBe(12) -- aucune place offerte
				expect(saved.ascend).toBe(0)
				clean(w, shared, FAIL_WARN)
				disposeAll()
			end
		)

		it(
			"profil v1 sur un serveur v2 : migré au chargement malgré deux pannes, sauvegardé v2 ; repris ailleurs : jamais migré deux fois",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				local v1 = readV1(probe)
				local expected = migrated(probe, v1)
				Chaos.seed(shared, 21, v1)
				local a = serverV2(shared, "A")
				shared.fail.UpdateAsync = 2
				local p = Bots.join(21)
				expect(a.DS.isLoaded(p)).toBe(true)
				local data = a.DS.get(p)
				expect({
					data.version,
					data.R,
					data.bestR,
					data.ascend,
					data.memoryR,
					data.confetti,
					data.confettiTotal,
					data.tiles.pens,
					data.unlocksSeen,
				}).toEqual({ 2, 12, 12, 0, 0, 139, 139, 14, 12 })
				expect(data.stats.upgradesBought).toBe(expected.stats.upgradesBought)
				expect(a.Invariants.profile(data)).toEqual({})
				Bots.leave(p)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 21)
					return d ~= nil and d.version == 2
				end)).toBe(true)
				local saved = Chaos.record(shared, 21)
				expect({ saved.confetti, saved.confettiTotal, saved.memoryR }).toEqual({ 139, 139, 0 })
				expect(a.Invariants.profile(saved)).toEqual({})
				-- un autre serveur v2 relit la v2 telle quelle : aucun rattrapage de plus
				local b = serverV2(shared, "B")
				local pb = Bots.join(21)
				expect(waitUntil(function()
					return b.DS.isLoaded(pb)
				end)).toBe(true)
				local db = b.DS.get(pb)
				expect({ db.version, db.confetti, db.confettiTotal, db.tiles.pens, db.bestR }).toEqual({
					2,
					139,
					139,
					14,
					12,
				})
				Bots.leave(pb)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 21)
					return d ~= nil and d.lastOnline == T0 and Chaos.record(shared, 21).confetti == 139
				end)).toBe(true)
				clean(a, shared, FAIL_WARN)
				clean(b, shared, FAIL_WARN)
				disposeAll()
			end
		)

		it(
			"sauvegarde perdue juste après la migration (panne jusqu'à l'abandon) : la v1 reste, le serveur suivant la migre à l'identique",
			function()
				-- traces voulues : départ en panne, abandon des nouveaux essais, verrou de A observé par B
				T.expectWarning("nouveaux essais en arrière-plan")
				T.expectWarning("abandonnée après")
				T.expectWarning("verrouillées par un autre serveur")
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				Chaos.seed(shared, 22, readV1(probe))
				local a = serverV2(shared, "A", function(w)
					w.DS.Settings.RELEASE_RETRY_WINDOW = 0.05
				end)
				local p = Bots.join(22)
				expect(a.DS.get(p).confetti).toBe(139)
				shared.down = true
				Bots.leave(p)
				expect(waitUntil(function()
					return hasWarning(a, "abandonnée")
				end, 8)).toBe(true)
				-- rien d'écrit : la sauvegarde du magasin est toujours la v1 (verrou de A posé)
				expect(Chaos.record(shared, 22).version).toBe(1)
				shared.down = false
				local b = serverV2(shared, "B")
				local pb = Bots.join(22, { timeout = 5 })
				expect(waitUntil(function()
					return b.DS.isLoaded(pb)
				end)).toBe(true)
				local db = b.DS.get(pb)
				expect({ db.version, db.confetti, db.confettiTotal, db.tiles.pens, db.bestR }).toEqual({
					2,
					139,
					139,
					14,
					12,
				})
				Bots.leave(pb)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 22)
					return d ~= nil and d.version == 2
				end)).toBe(true)
				expect(Chaos.record(shared, 22).confetti).toBe(139)
				clean(a, shared, { "panne simulée", "nouveaux essais", "PERTE" })
				clean(b, shared, { "verrouillées par un autre serveur" })
				disposeAll()
			end
		)

		it(
			"reconnexion sur le même serveur pendant la sauvegarde de départ (magasin lent, deux pannes) : la v2 relue",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				Chaos.seed(shared, 23, readV1(probe))
				local a = serverV2(shared, "A")
				local p = Bots.join(23)
				local uid = a.Squishy.give(p, { s = 1, m = 0, st = 0, z = 1 }, "starter")
				local nextUid = a.DS.get(p).nextUid
				shared.latency = 0.003
				shared.fail.UpdateAsync = 2
				Bots.leave(p)
				local p2 = Bots.join(23, { timeout = 5 })
				expect(waitUntil(function()
					return a.DS.isLoaded(p2)
				end, 8)).toBe(true)
				local d2 = a.DS.get(p2)
				expect({ d2.version, d2.confetti, d2.nextUid, d2.squishies[uid] ~= nil }).toEqual({
					2,
					139,
					nextUid,
					true,
				})
				expect(a.Invariants.profile(d2)).toEqual({})
				Bots.leave(p2)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 23)
					return d ~= nil and d.nextUid == nextUid and d.lastOnline == T0
				end, 8)).toBe(true)
				clean(a, shared, FAIL_WARN)
				disposeAll()
			end
		)

		it(
			"quotas dépassés (429) au chargement puis à la sauvegarde de départ : nouveaux essais, migré une fois, écrit en v2",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				Chaos.seed(shared, 24, readV1(probe))
				local a = serverV2(shared, "A", function(w)
					w.DS.Settings.RETRY_BASE_DELAY = 0.01 -- essais à 20, 40, 80 ms : la fenêtre glisse
				end)
				-- serveur très occupé : un appel au plus par fenêtre de 50 ms, une rafale vient de passer
				shared.quota = 1
				shared.quotaWindow = 0.05
				local function busy()
					table.insert(shared.calls, { server = "A", op = "UpdateAsync", at = os.clock() })
				end
				busy()
				local p = Bots.join(24, { timeout = 5 })
				expect(waitUntil(function()
					return a.DS.isLoaded(p)
				end, 5)).toBe(true)
				expect(hasWarning(a, "quota simulé")).toBe(true)
				expect(a.DS.get(p).confetti).toBe(139)
				task.wait(0.06)
				busy()
				Bots.leave(p)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 24)
					return d ~= nil and d.version == 2
				end, 5)).toBe(true)
				local saved = Chaos.record(shared, 24)
				expect({ saved.confetti, saved.tiles.pens }).toEqual({ 139, 14 })
				expect(a.Invariants.profile(saved)).toEqual({})
				shared.quota = nil
				clean(a, shared, { "quota simulé" })
				disposeAll()
			end
		)

		it(
			"fermeture (BindToClose) à 16 joueurs v1 sur un magasin lent : 16 profils v2 écrits, rattrapage exact",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				local want = {}
				for i = 1, 16 do
					local v1 = readV1(probe)
					v1.R = i + 2 -- Record R 3 à 18 : places offertes et Confettis différents
					Chaos.seed(shared, 300 + i, v1)
					want[i] = migrated(probe, v1)
				end
				local w = serverV2(shared, "A")
				local players = {}
				for i = 1, 16 do
					players[i] = Bots.join(300 + i)
				end
				w.h:settle(3)
				for i = 1, 16 do
					local d = w.DS.get(players[i])
					expect({ i = i, c = d.confetti, pens = d.tiles.pens, bestR = d.bestR }).toEqual({
						i = i,
						c = want[i].confetti,
						pens = want[i].tiles.pens,
						bestR = i + 2,
					})
				end
				shared.latency = 0.003
				w.Clock.advance(30)
				w.h:close()
				expect(waitUntil(function()
					for i = 1, 16 do
						local d = Chaos.record(shared, 300 + i)
						if d == nil or d.lastOnline ~= T0 + 30 or d.version ~= 2 then
							return false
						end
					end
					return true
				end, 10)).toBe(true)
				for i = 1, 16 do
					local d = Chaos.record(shared, 300 + i)
					expect({ i = i, c = d.confetti, total = d.confettiTotal }).toEqual({
						i = i,
						c = want[i].confetti,
						total = want[i].confettiTotal,
					})
					expect(w.Invariants.profile(d)).toEqual({})
				end
				clean(w, shared, FAIL_WARN)
				disposeAll()
			end
		)

		it(
			"profil v2 abîmé (champs v2 hors bornes) : réparé au chargement, joué, réécrit sain",
			function()
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				local d = migrated(probe, readV1(probe))
				d.bestR = 5 -- sous r = 12
				d.confetti, d.confettiTotal = 500, 100
				d.memoryR = 99
				d.atelier = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 } -- 12 cases pour 10 lignes ; Tremplin sans Ascension
				d.tiles.star = 3 -- Tapis 7 : Tapis Étoilé impossible
				d.hearts.givenTo = { 5, 5, 6 }
				d.cosmetics.theme = "celestial" -- 5 Ascensions
				d.decoPerso.slots[1] = 3 -- objet non possédé
				d.weeklyTrack.challenges = { { id = 1, p = 1, done = true }, { id = 1, p = 2, done = false } }
				d.unlocksSeen = 50
				Chaos.seed(shared, 25, d)
				local repaired = nil
				local w = serverV2(shared, "A", function(world)
					world.Signals.ProfileRepaired:Connect(function(_, fixes)
						repaired = fixes
					end)
				end)
				local p = Bots.join(25)
				w.h:settle(2)
				local data = w.DS.get(p)
				expect(repaired ~= nil).toBe(true)
				for _, path in
					{
						"bestR",
						"confettiTotal",
						"memoryR",
						"atelier",
						"springboard.cap",
						"star.cap",
						"hearts.givenTo",
						"cosmetics.theme",
						"decoPerso.slots.1",
						"weeklyTrack.challenges",
						"unlocksSeen",
					}
				do
					expect({ path = path, fixed = table.find(repaired, path) ~= nil }).toEqual({
						path = path,
						fixed = true,
					})
				end
				expect({
					data.bestR,
					data.confetti,
					data.confettiTotal,
					data.memoryR,
					#data.atelier,
					data.tiles.star,
					#data.hearts.givenTo,
					data.cosmetics.theme,
					data.decoPerso.slots[1],
					#data.weeklyTrack.challenges,
					data.unlocksSeen,
				}).toEqual({ 12, 500, 500, 0, 10, 0, 2, "color", 0, 1, 12 })
				expect(w.Invariants.profile(data)).toEqual({})
				w.Squishy.give(p, { s = 1, m = 0, st = 0, z = 1 }, "test")
				local nextUid = data.nextUid
				Bots.leave(p)
				expect(waitUntil(function()
					local saved = Chaos.record(shared, 25)
					return saved ~= nil and saved.nextUid == nextUid
				end)).toBe(true)
				local saved = Chaos.record(shared, 25)
				expect(w.Invariants.profile(saved)).toEqual({})
				expect(saved.confetti).toBe(500) -- jamais un Confetti de poche perdu
				clean(w, shared, FAIL_WARN)
				disposeAll()
			end
		)

		-- Lot A2 (journal A2-6) : la préparation (migration, reconcile) n'était pas protégée ; une
		-- erreur laissait le joueur sur l'écran de chargement, notre verrou posé dans l'enregistrement
		it(
			"préparation en échec (migration qui lève, sauvegarde illisible) : renvoi poli, verrou rendu, données intactes",
			function()
				T.expectWarning("préparation du profil")
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				Chaos.seed(shared, 27, readV1(probe))
				shared.data["player_28"] = { data = "illisible", meta = { created = 1, saves = 3 } }
				local before27 = Chaos.record(shared, 27)
				local w = serverV2(shared, "A", function(world)
					world.Schema.migrate = function()
						error("migration cassée (test)", 0)
					end
				end)
				local p27 = Bots.join(27, { wait = false })
				local p28 = Bots.join(28, { wait = false })
				expect(waitUntil(function()
					return #w.h.log.kicks == 2
				end)).toBe(true)
				expect(w.DS.get(p27)).toBeNil()
				expect(w.DS.get(p28)).toBeNil()
				w.h:settle(3)
				-- données intactes, verrou rendu (un autre serveur charge aussitôt)
				local Tables = probe:require("ReplicatedStorage.Shared.Util.Tables")
				expect(Tables.deepEqual(Chaos.record(shared, 27), before27)).toBe(true)
				expect(shared.data["player_27"].lock).toBeNil()
				expect(shared.data["player_28"].data).toBe("illisible")
				expect(shared.data["player_28"].lock).toBeNil()
				expect(table.concat(w.h.errors, "\n")).toBe("")
				disposeAll()
			end
		)

		it(
			"déploiement progressif : un serveur v1 refuse le profil v2 sans rien écrire ; un serveur v2 le relit",
			function()
				T.expectWarning("écrit par un schéma plus récent que v1")
				disposeAll()
				local probe = Harness.new()
				local shared = newStore(probe)
				Chaos.seed(shared, 26, readV1(probe))
				local a = serverV2(shared, "A")
				local p = Bots.join(26)
				Bots.leave(p)
				expect(waitUntil(function()
					local d = Chaos.record(shared, 26)
					return d ~= nil and d.version == 2
				end)).toBe(true)
				local writes = #shared.writes
				local before = shared.data["player_26"]
				local old = server(shared, "OLD")
				local po = Bots.join(26, { wait = false })
				expect(waitUntil(function()
					return #old.h.log.kicks == 1
				end)).toBe(true)
				expect(old.DS.get(po)).toBeNil()
				expect(#shared.writes).toBe(writes) -- rien écrit, pas même le verrou
				expect(shared.data["player_26"]).toBe(before)
				local c = serverV2(shared, "C")
				local pc = Bots.join(26)
				expect(waitUntil(function()
					return c.DS.isLoaded(pc)
				end)).toBe(true)
				expect(c.DS.get(pc).confetti).toBe(139)
				clean(a, shared, FAIL_WARN)
				clean(old, shared, { "schéma plus récent" })
				clean(c, shared, FAIL_WARN)
				disposeAll()
			end
		)
	end)
end
