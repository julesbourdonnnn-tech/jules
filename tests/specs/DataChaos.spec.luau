--!nocheck
-- DataChaos (paquet ranch, docs/04 §17.1 couche e, §18.2) : le jeu complet sur un DataStore en
-- désordre (tests/harness/Chaos) : pannes au chargement et à la sauvegarde, latence, verrou entre deux
-- serveurs et retour immédiat sur l'autre, fermeture à 16 avec un magasin lent, migration de la
-- sauvegarde-témoin v0, profil abîmé réparé puis joué, reçu rejoué pendant une panne, mutations « au
-- départ » présentes dans la sauvegarde de départ (§1 règle 15), rebase hors ligne avant tout
-- règlement. Après CHAQUE écriture : valeur sérialisable par Roblox (aucun tableau à trous, aucune
-- table mixte) et Invariants.dense sur les tableaux du profil.
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
				-- (un vieil enregistrement réécrit tel quel avec le verrou peut ne pas avoir encore la clé)
				for _, path in { "trophies" } do
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

	local function server(shared, jobId, before)
		local caught = {}
		local w = Chaos.boot(Harness, Bots, shared, jobId, {
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
end
