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
			expect(data.glow).toBe(0)
			expect(data.stardust).toBe(0)
			expect(data.version).toBe(1)
			local snaps = h:sentTo(p, "DataSnapshot")
			expect(#snaps).toBe(1)
			expect(snaps[1][1].receipts).toBeNil() -- clé privée jamais envoyée
		end)

		it("réplique les modifications par patchs groupés", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 11 })
			DS.waitFor(p, 2)
			DS.increment(p, "glow", 5)
			DS.increment(p, "glow", 7)
			h:settle(2)
			local patches = h:sentTo(p, "DataPatch")
			expect(#patches).toBe(1)
			expect(patches[1][1].glow).toBe(12)
		end)

		it("sauvegarde au départ et recharge la progression", function()
			local h, DS = boot()
			local p = h:addPlayer({ userId = 12 })
			DS.waitFor(p, 2)
			DS.set(p, "glow", 99)
			h:removePlayer(p)
			h:settle(5)
			local p2 = h:addPlayer({ userId = 12 })
			local data = DS.waitFor(p2, 2)
			expect(data.glow).toBe(99)
		end)

		it("ne charge pas tant qu'un autre serveur détient le verrou, puis le vole", function()
			local h, DS = boot()
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
			store:SetAsync("player_13", {
				data = { version = 1, glow = 42, receipts = {} },
				lock = { jobId = "autre-serveur", time = os.time() },
			})
			local p = h:addPlayer({ userId = 13 })
			local data = DS.waitFor(p, 3)
			expect(data ~= nil).toBeTruthy()
			expect(data.glow).toBe(42)
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
			DS.set(p, "glow", 1)
			expect(DS.saveNow(p)).toBe(true)
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
			local rec = store:GetAsync("player_16")
			rec.lock = { jobId = "autre-serveur", time = os.time() }
			rec.data.glow = 500
			store:SetAsync("player_16", rec)
			expect(DS.saveNow(p)).toBe(false)
			expect(store:GetAsync("player_16").data.glow).toBe(500)
		end)

		it("sauvegarde tout le monde à l'arrêt du serveur", function()
			local h, DS = boot()
			local a = h:addPlayer({ userId = 17 })
			local b = h:addPlayer({ userId = 18 })
			DS.waitFor(a, 2)
			DS.waitFor(b, 2)
			DS.set(a, "glow", 3)
			DS.set(b, "glow", 4)
			h:close()
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
			expect(store:GetAsync("player_17").data.glow).toBe(3)
			expect(store:GetAsync("player_18").data.glow).toBe(4)
			expect(store:GetAsync("player_18").lock).toBeNil()
		end)

		it("migre et complète une ancienne sauvegarde", function()
			local h, DS = boot()
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
			store:SetAsync("player_19", { data = { coins = 7 } })
			local p = h:addPlayer({ userId = 19 })
			local data = DS.waitFor(p, 2)
			-- v0 → v1 : les pièces deviennent du Glow, l'ancien champ n'est jamais effacé
			expect(data.glow).toBe(7)
			expect(data.coins).toBe(7)
			expect(data.version).toBe(1)
			expect(type(data.receipts)).toBe("table")
			expect(type(data.upgrades)).toBe("table")
			expect(data.upgrades.conga).toBe(0)
			expect(data.settings.lang).toBe("auto")
		end)

		it(
			"appelle les crochets onBeforeSave avant chaque écriture (règlement du revenu passif)",
			function()
				local h, DS = boot()
				local calls = 0
				DS.onBeforeSave(function(player, data)
					calls += 1
					data.glow += 10 -- simule un règlement : doit figurer dans la sauvegarde
				end)
				DS.onBeforeSave(function()
					error("crochet défaillant") -- ne doit jamais bloquer la sauvegarde
				end)
				local p = h:addPlayer({ userId = 20 })
				DS.waitFor(p, 2)
				expect(DS.saveNow(p)).toBe(true)
				expect(calls).toBe(1)
				local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
				expect(store:GetAsync("player_20").data.glow).toBe(10)
				h:removePlayer(p)
				h:settle(5)
				expect(calls).toBe(2)
				expect(store:GetAsync("player_20").data.glow).toBe(20)
				expect(store:GetAsync("player_20").lock).toBeNil()
			end
		)
	end)
end
