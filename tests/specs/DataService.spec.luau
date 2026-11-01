--!nocheck
-- DataService (repris de Comet Conga) : profil par défaut et instantané, patchs groupés, sauvegarde
-- au départ, verrou d'un autre serveur, pannes DataStore, renvoi plutôt qu'un profil vide, session
-- reprise ailleurs jamais écrasée, BindToClose, migration, crochets onBeforeSave.
-- Données neutres : le schéma générique est complété de clés fictives (coins, gems) par
-- Bots.extendSchema (le schéma du jeu viendra de l'architecte).
local task = require("@lune/task")
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local STORE = "PlayerData_v1"

	local function boot(opts)
		local h = Harness.new(opts)
		Bots.extendSchema(h, { coins = 0, gems = 0 })
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		DS.Settings.RETRY_BASE_DELAY = 0.001
		h:boot()
		return h, DS
	end

	describe("DataService", function()
		it("charge les valeurs par défaut et envoie un instantané", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 10 })
			local data = DS.waitFor(p, 2)
			expect(data ~= nil).toBeTruthy()
			expect(data.coins).toBe(0)
			expect(data.gems).toBe(0)
			expect(data.version).toBe(1)
			expect(data.settings.lang).toBe("auto")
			local snaps = h:sentTo(p, "DataSnapshot")
			expect(#snaps).toBe(1)
			expect(snaps[1][1].receipts).toBeNil() -- clé privée jamais envoyée
			expect(snaps[1][1].flags).toBeNil()
			expect(snaps[1][1].codes).toBeNil()
			expect(snaps[1][1].coins).toBe(0)
		end)

		it("réplique les modifications par patchs groupés", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 11 })
			DS.waitFor(p, 2)
			DS.increment(p, "coins", 5)
			DS.increment(p, "coins", 7)
			h:settle(2)
			local patches = h:sentTo(p, "DataPatch")
			expect(#patches).toBe(1)
			expect(patches[1][1].coins).toBe(12)
		end)

		it("increment refuse un delta non fini ou une clé non numérique", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 21 })
			DS.waitFor(p, 2)
			expect(function()
				DS.increment(p, "coins", 0 / 0)
			end).toThrow()
			expect(function()
				DS.increment(p, "coins", math.huge)
			end).toThrow()
			expect(function()
				DS.increment(p, "settings", 1)
			end).toThrow()
			expect(DS.get(p).coins).toBe(0)
			-- joueur sans profil : nil, aucune erreur
			expect(DS.increment({ Name = "Nobody", Parent = nil }, "coins", 1)).toBeNil()
		end)

		it("sauvegarde au départ et recharge la progression", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 12 })
			DS.waitFor(p, 2)
			DS.set(p, "coins", 99)
			h:removePlayer(p)
			h:settle(5)
			local p2 = h:addPlayer({ userId = 12 })
			local data = DS.waitFor(p2, 2)
			expect(data.coins).toBe(99)
		end)

		it("ne charge pas tant qu'un autre serveur détient le verrou, puis le reprend", function()
			local h, DS = boot()
			local store = h.game.DataStoreService:GetDataStore(STORE)
			store:SetAsync("player_13", {
				data = { version = 1, coins = 42, receipts = {} },
				lock = { jobId = "autre-serveur", time = os.time() },
			})
			local p = h:addPlayer({ userId = 13 })
			local data = DS.waitFor(p, 3)
			expect(data ~= nil).toBeTruthy()
			expect(data.coins).toBe(42)
		end)

		it("survit aux pannes DataStore (retries)", function()
			local h, DS = boot()
			h.dataStoreFailures = 3
			local p = h:addPlayer({ userId = 14 })
			local data = DS.waitFor(p, 3)
			expect(data ~= nil).toBeTruthy()
		end)

		it("expulse le joueur si le chargement échoue définitivement (jamais de données vides)", function()
			local h, DS = boot()
			h.dataStoreFailures = 100
			local p = h:addPlayer({ userId = 15 })
			h:settle(30)
			task.wait(0.3)
			expect(DS.get(p)).toBeNil()
			expect(#h.log.kicks).toBe(1)
			h.dataStoreFailures = 0
		end)

		it("ne réécrit pas des données reprises par un autre serveur", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 16 })
			DS.waitFor(p, 2)
			DS.set(p, "coins", 1)
			expect(DS.saveNow(p)).toBe(true)
			local store = h.game.DataStoreService:GetDataStore(STORE)
			local rec = store:GetAsync("player_16")
			rec.lock = { jobId = "autre-serveur", time = os.time() }
			rec.data.coins = 500
			store:SetAsync("player_16", rec)
			expect(DS.saveNow(p)).toBe(false)
			expect(store:GetAsync("player_16").data.coins).toBe(500)
		end)

		it("sauvegarde tout le monde à l'arrêt du serveur", function()
			local h, DS = boot()
			local a = h:addPlayer({ userId = 17 })
			local b = h:addPlayer({ userId = 18 })
			DS.waitFor(a, 2)
			DS.waitFor(b, 2)
			DS.set(a, "coins", 3)
			DS.set(b, "coins", 4)
			h:close()
			local store = h.game.DataStoreService:GetDataStore(STORE)
			expect(store:GetAsync("player_17").data.coins).toBe(3)
			expect(store:GetAsync("player_18").data.coins).toBe(4)
			expect(store:GetAsync("player_18").lock).toBeNil()
		end)

		it("migre et complète une ancienne sauvegarde (sans version : v0)", function()
			local h = Harness.new()
			local Schema = Bots.extendSchema(h, { coins = 0, gems = 0 })
			-- étape de migration d'exemple (le jeu ajoutera les siennes) : « gold » devient « coins »
			local calls = {}
			local migrate = Schema.migrate
			Schema.migrate = function(data, from)
				table.insert(calls, from)
				data = migrate(data, from)
				if from < 1 and type(data.gold) == "number" and data.coins == nil then
					data.coins = data.gold
				end
				return data
			end
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			h:boot()
			local store = h.game.DataStoreService:GetDataStore(STORE)
			store:SetAsync("player_19", { data = { gold = 7 } })
			local p = h:addPlayer({ userId = 19 })
			local data = DS.waitFor(p, 2)
			expect(calls).toEqual({ 0 })
			-- l'ancien champ n'est jamais effacé ; les champs manquants sont créés
			expect(data.coins).toBe(7)
			expect(data.gold).toBe(7)
			expect(data.version).toBe(1)
			expect(type(data.receipts)).toBe("table")
			expect(data.settings.lang).toBe("auto")
			expect(data.flags.strikes).toBe(0)
			-- version illisible (sauvegarde abîmée) : traitée comme v0
			store:SetAsync("player_20", { data = { version = "v?", gems = 3 } })
			local q = h:addPlayer({ userId = 20 })
			local d2 = DS.waitFor(q, 2)
			expect(d2.version).toBe(1)
			expect(d2.gems).toBe(3)
			expect(calls[#calls]).toBe(0)
		end)

		it(
			"appelle les crochets onBeforeSave avant chaque écriture (règlement d'un revenu passif)",
			function()
				local h, DS = boot()
				local calls = 0
				DS.onBeforeSave(function(player, data)
					calls += 1
					data.coins += 10 -- simule un règlement : doit figurer dans la sauvegarde
				end)
				DS.onBeforeSave(function()
					error("crochet défaillant") -- ne doit jamais bloquer la sauvegarde
				end)
				local p = h:addPlayer({ userId = 22 })
				DS.waitFor(p, 2)
				expect(DS.saveNow(p)).toBe(true)
				expect(calls).toBe(1)
				local store = h.game.DataStoreService:GetDataStore(STORE)
				expect(store:GetAsync("player_22").data.coins).toBe(10)
				h:removePlayer(p)
				h:settle(5)
				expect(calls).toBe(2)
				expect(store:GetAsync("player_22").data.coins).toBe(20)
				expect(store:GetAsync("player_22").lock).toBeNil()
			end
		)

		it("RequestSnapshot : renvoie l'instantané, limité à 2 par 10 s", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 23 })
			DS.waitFor(p, 2)
			for _ = 1, 6 do
				h:fireServer("ReplicatedStorage.Remotes.RequestSnapshot", p, { evil = true })
			end
			h:settle(2)
			-- 1 instantané d'arrivée + 2 redemandes au plus (charges ignorées)
			expect(#h:sentTo(p, "DataSnapshot")).toBe(3)
			expect(#h.errors).toBe(0)
		end)
	end)
end
