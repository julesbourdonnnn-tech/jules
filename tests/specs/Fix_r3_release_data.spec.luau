--!nocheck
-- Validation de publication r3 de Comet Conga, partie DataService (reprise) : attribut répliqué
-- Player « ProfileLoading » (numéro d'essai > 0) pendant toute l'attente du chargement (verrou d'un
-- autre serveur, retries), nil dès la réponse connue (chargé, échec définitif), toujours AVANT
-- l'instantané ou le renvoi ; contrat lu par src/first/Loading.client (Fix_r3_partage_2).
-- Retirés (gameplay) : mode menu du HUD, garde de l'écran de chargement d'InputController, Starborn.
local task = require("@lune/task")
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local STORE = "PlayerData_v1"

	local function boot()
		local h = Harness.new()
		Bots.extendSchema(h, { coins = 0 })
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		DS.Settings.RETRY_BASE_DELAY = 0.001
		h:boot()
		return h, DS
	end

	-- Valeurs successives de l'attribut ProfileLoading du prochain joueur, dès son entrée dans
	-- Players (avant PlayerAdded) ; snapshots = nombre d'instantanés déjà envoyés à chaque valeur
	local function watchNextPlayer(h)
		local seen, snapshots = {}, {}
		local conn
		conn = h.game.Players.ChildAdded:Connect(function(p)
			conn:Disconnect()
			p:GetAttributeChangedSignal("ProfileLoading"):Connect(function()
				table.insert(seen, p:GetAttribute("ProfileLoading") or "nil")
				table.insert(snapshots, #h:sentTo(p, "DataSnapshot"))
			end)
		end)
		return seen, snapshots
	end

	describe("Fix r3 release › DataService : attribut ProfileLoading", function()
		it("verrou d'un autre serveur : essais 1 à 5 en attente, puis nil avant l'instantané", function()
			local h, DS = boot()
			local store = h.game.DataStoreService:GetDataStore(STORE)
			store:SetAsync("player_31", {
				data = { version = 1, coins = 42, receipts = {} },
				lock = { jobId = "autre-serveur", time = os.time() },
			})
			local seen, snapshots = watchNextPlayer(h)
			local p = h:addPlayer({ userId = 31, name = "P31" })
			local data = DS.waitFor(p, 3)
			h:settle(2)
			expect(data ~= nil).toBe(true)
			expect(data.coins).toBe(42)
			-- 1 (arrivée), puis un numéro par essai : les essais 1 à 5 attendent le verrou, le 6e le vole
			expect(seen).toEqual({ 1, 2, 3, 4, 5, 6, "nil" })
			-- effacé AVANT l'instantané (l'écran de chargement ne retient plus Réessayer)
			expect(snapshots).toEqual({ 0, 0, 0, 0, 0, 0, 0 })
			expect(#h:sentTo(p, "DataSnapshot")).toBe(1)
			expect(p:GetAttribute("ProfileLoading")).toBeNil()
		end)

		it("chargement normal : posé puis effacé, jamais resté sur le joueur", function()
			local h, DS = boot()
			local seen = watchNextPlayer(h)
			local p = h:addPlayer({ userId = 32, name = "P32" })
			DS.waitFor(p, 2)
			h:settle(2)
			expect(seen).toEqual({ 1, "nil" })
			expect(p:GetAttribute("ProfileLoading")).toBeNil()
		end)

		it("échec définitif : effacé avant le renvoi", function()
			local h, DS = boot()
			h.dataStoreFailures = 100
			local seen = watchNextPlayer(h)
			local p = h:addPlayer({ userId = 33, name = "P33" })
			h:settle(30)
			local waited = os.clock()
			while #h.log.kicks == 0 and os.clock() - waited < 2 do
				task.wait(0.02)
			end
			expect(DS.get(p)).toBeNil()
			expect(#h.log.kicks).toBe(1)
			expect(seen).toEqual({ 1, 2, 3, 4, 5, 6, "nil" })
			expect(p:GetAttribute("ProfileLoading")).toBeNil()
			h.dataStoreFailures = 0
		end)
	end)
end
