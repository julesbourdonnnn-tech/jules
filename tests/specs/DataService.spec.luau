--!nocheck
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function boot(opts)
		local h = Harness.new(opts)
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
			local snaps = h:sentTo(p, "DataSnapshot")
			expect(#snaps).toBe(1)
			expect(snaps[1][1].receipts).toBeNil() -- clé privée jamais envoyée
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

		it("ne charge pas tant qu'un autre serveur détient le verrou, puis le vole", function()
			local h, DS = boot()
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
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
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
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
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
			expect(store:GetAsync("player_17").data.coins).toBe(3)
			expect(store:GetAsync("player_18").data.coins).toBe(4)
			expect(store:GetAsync("player_18").lock).toBeNil()
		end)

		it("migre et complète une ancienne sauvegarde", function()
			local h, DS = boot()
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
			store:SetAsync("player_19", { data = { coins = 7 } })
			local p = h:addPlayer({ userId = 19 })
			local data = DS.waitFor(p, 2)
			expect(data.coins).toBe(7)
			expect(data.version).toBe(1)
			expect(type(data.receipts)).toBe("table")
		end)
	end)
end
