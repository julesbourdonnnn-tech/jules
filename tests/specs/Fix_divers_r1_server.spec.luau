--!nocheck
-- QA ronde 1, paquet « divers » (socle serveur) :
--   * DataService : reconnexion sur le même serveur pendant la sauvegarde de départ (aucun retour
--     en arrière), sauvegarde mise en file derrière le départ (jamais de verrou repris)
--   * MonetizationService : PromptGamePassPurchaseFinished n'est qu'un indice (possession vérifiée
--     par UserOwnsGamePassAsync), pass remboursé retiré à l'arrivée, charges malveillantes
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local STORE = "PlayerData_v1"
	local PASS_ID = 2101
	local OTHER_PASS_ID = 2102

	local function boot()
		local h = Harness.new()
		local cfg = h:require("ReplicatedStorage.Shared.Config.Monetization")
		cfg.Passes.TestVIP = { id = PASS_ID, price = 199, nameKey = "x", descKey = "x", order = 1 }
		cfg.Passes.TestGlow = { id = OTHER_PASS_ID, price = 99, nameKey = "x", descKey = "x", order = 2 }
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		DS.Settings.RETRY_BASE_DELAY = 0.05 -- backoff 0,1 / 0,2 / 0,4 s
		local M = h:require("ServerScriptService.Server.Services.MonetizationService")
		M.Settings.VERIFY_RETRY_DELAY = 0.02
		h:boot()
		return h, DS, M
	end

	local function stored(h, userId)
		return h.game.DataStoreService:GetDataStore(STORE):GetAsync("player_" .. userId)
	end

	local function waitUntil(cond, timeout)
		local start = os.clock()
		while not cond() and os.clock() - start < (timeout or 3) do
			task.wait(0.02)
		end
		return cond()
	end

	local function join(h, DS, userId)
		local p = h:addPlayer({ userId = userId, name = "P" .. userId })
		local data = DS.waitFor(p, 3)
		h:settle(3)
		return p, data
	end

	describe("Fix divers r1 › DataService : reconnexion sur le même serveur", function()
		it(
			"reconnexion pendant une sauvegarde de départ en échec : données les plus récentes chargées",
			function()
				local h, DS = boot()
				local p = join(h, DS, 50)
				-- progression gagnée depuis la dernière autosave (seulement en mémoire)
				DS.set(p, "stardust", 777)
				DS.set(p, "glow", 1234)
				h.dataStoreFailures = 1 -- la sauvegarde de départ échoue une fois, puis réessaie
				h:removePlayer(p)
				-- le joueur revient sur le MÊME serveur pendant le backoff
				local p2 = h:addPlayer({ userId = 50, name = "P50" })
				local d2 = DS.waitFor(p2, 3)
				expect(d2 ~= nil).toBe(true)
				expect(d2.stardust).toBe(777)
				expect(d2.glow).toBe(1234)
				h:settle(5)
				-- la nouvelle session sauvegarde : rien n'est perdu, elle tient le verrou
				expect(DS.saveNow(p2)).toBe(true)
				local rec = stored(h, 50)
				expect(rec.data.stardust).toBe(777)
				expect(rec.data.glow).toBe(1234)
				expect(rec.lock ~= nil).toBe(true)
				expect(#h.log.kicks).toBe(0)
			end
		)

		it("reconnexion immédiate après un départ normal : chargement sans attente inutile", function()
			local h, DS = boot()
			local p = join(h, DS, 51)
			DS.set(p, "glow", 64)
			h:removePlayer(p)
			local p2 = h:addPlayer({ userId = 51, name = "P51" })
			local d2 = DS.waitFor(p2, 3)
			expect(d2 ~= nil).toBe(true)
			expect(d2.glow).toBe(64)
		end)

		it(
			"départ toujours en cours après l'attente maximale : expulsion, jamais de profil périmé",
			function()
				local h, DS = boot()
				DS.Settings.REJOIN_WAIT = 0.05
				DS.Settings.RETRY_BASE_DELAY = 0.25 -- backoff de 0,5 s, plus long que l'attente
				local p = join(h, DS, 52)
				DS.set(p, "stardust", 555)
				h.dataStoreFailures = 1
				h:removePlayer(p)
				local p2 = h:addPlayer({ userId = 52, name = "P52" })
				expect(waitUntil(function()
					return #h.log.kicks >= 1
				end, 2)).toBe(true)
				expect(h.log.kicks[1].player).toBe(p2)
				expect(DS.get(p2)).toBeNil()
				-- la sauvegarde de départ finit par passer : progression intacte, verrou libéré
				expect(waitUntil(function()
					local rec = stored(h, 52)
					return rec ~= nil and rec.data ~= nil and rec.data.stardust == 555 and rec.lock == nil
				end, 3)).toBe(true)
				h:removePlayer(p2)
				h:settle(3)
				DS.Settings.RETRY_BASE_DELAY = 0.05
				local p3 = h:addPlayer({ userId = 52, name = "P52" })
				local d3 = DS.waitFor(p3, 3)
				expect(d3 ~= nil).toBe(true)
				expect(d3.stardust).toBe(555)
			end
		)

		it("le joueur repart pendant l'attente : rien n'est chargé ni verrouillé pour lui", function()
			local h, DS = boot()
			DS.Settings.RETRY_BASE_DELAY = 0.2
			local p = join(h, DS, 53)
			DS.set(p, "glow", 9)
			h.dataStoreFailures = 1
			h:removePlayer(p)
			local p2 = h:addPlayer({ userId = 53, name = "P53" })
			h:removePlayer(p2) -- reparti avant la fin de la sauvegarde de départ
			expect(waitUntil(function()
				local rec = stored(h, 53)
				return rec ~= nil and rec.data ~= nil and rec.data.glow == 9 and rec.lock == nil
			end, 3)).toBe(true)
			task.wait(0.2)
			expect(DS.get(p2)).toBeNil()
			expect(stored(h, 53).lock).toBeNil()
			expect(#h.log.kicks).toBe(0)
		end)
	end)

	describe("Fix divers r1 › DataService : sauvegarde en file derrière le départ", function()
		it("une sauvegarde qui attendait la sauvegarde de départ ne reprend pas le verrou", function()
			local h, DS = boot()
			local p = join(h, DS, 60)
			DS.set(p, "glow", 42)
			h.dataStoreFailures = 1 -- sauvegarde de départ en backoff : saveNow attend derrière elle
			h:removePlayer(p)
			local result = "pending"
			task.spawn(function()
				result = DS.saveNow(p) -- ex. ProcessReceipt d'un joueur en train de partir
			end)
			expect(waitUntil(function()
				return result ~= "pending"
			end, 3)).toBe(true)
			task.wait(0.2)
			expect(result).toBe(false)
			local rec = stored(h, 60)
			expect(rec.data.glow).toBe(42)
			expect(rec.lock).toBeNil() -- un autre serveur peut charger le joueur tout de suite
		end)

		it("une autosave lancée pendant le départ n'écrit rien après la libération", function()
			local h, DS = boot()
			DS.Settings.AUTOSAVE_INTERVAL = 0.05
			local p = join(h, DS, 61)
			DS.set(p, "glow", 7)
			h.dataStoreFailures = 1
			h:removePlayer(p)
			task.wait(0.6) -- plusieurs autosaves tombent pendant et après la sauvegarde de départ
			local rec = stored(h, 61)
			expect(rec.data.glow).toBe(7)
			expect(rec.lock).toBeNil()
		end)
	end)

	describe("Fix divers r1 › MonetizationService : possession vérifiée", function()
		it("signal d'achat usurpé (wasPurchased = true sans possession) : rien n'est accordé", function()
			local h, DS, M = boot()
			local granted, purchased = 0, 0
			M.PassGranted:Connect(function()
				granted += 1
			end)
			M.PassPurchased:Connect(function()
				purchased += 1
			end)
			local p, data = join(h, DS, 70)
			h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, PASS_ID, true)
			task.wait(0.3)
			expect(M.ownsPass(p, "TestVIP")).toBe(false)
			expect(data.passes.TestVIP).toBeNil()
			expect(granted).toBe(0)
			expect(purchased).toBe(0)
			-- rien n'est persisté
			expect(DS.saveNow(p)).toBe(true)
			expect(stored(h, 70).data.passes.TestVIP).toBeNil()
		end)

		it("achat en jeu réel : accordé une fois, PassGranted et PassPurchased une seule fois", function()
			local h, DS, M = boot()
			local granted, purchased = {}, {}
			M.PassGranted:Connect(function(_, key)
				table.insert(granted, key)
			end)
			M.PassPurchased:Connect(function(_, key)
				table.insert(purchased, key)
			end)
			local p = join(h, DS, 71)
			h:grantPass(p, PASS_ID)
			-- signal répété (double clic, exploit) : aucun doublon
			for _ = 1, 5 do
				h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, PASS_ID, true)
			end
			h:settle(3)
			expect(M.ownsPass(p, "TestVIP")).toBe(true)
			expect(granted).toEqual({ "TestVIP" })
			expect(purchased).toEqual({ "TestVIP" })
		end)

		it("propagation lente : la possession confirmée au 2e essai est accordée", function()
			local h, DS, M = boot()
			local p = join(h, DS, 72)
			-- 1re réponse « non possédé » (le signal arrive avant que Roblox ne reflète l'achat)…
			h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, PASS_ID, true)
			expect(M.ownsPass(p, "TestVIP")).toBe(false)
			-- … puis Roblox confirme : accordé au réessai
			h.ownedPasses[72] = { [PASS_ID] = true }
			expect(waitUntil(function()
				return M.ownsPass(p, "TestVIP")
			end, 2)).toBe(true)
		end)

		it(
			"pass enregistré mais plus possédé (remboursé) : retiré à l'arrivée, sans effets",
			function()
				local h, DS, M = boot()
				local store = h.game.DataStoreService:GetDataStore(STORE)
				local Schema = h:require("ServerScriptService.Server.Data.Schema")
				local profile = Schema.defaults()
				profile.passes = { TestVIP = true, TestGlow = true }
				store:SetAsync("player_73", { data = profile })
				h.ownedPasses[73] = { [OTHER_PASS_ID] = true } -- TestVIP remboursé, TestGlow possédé
				local granted, revoked = {}, {}
				M.PassGranted:Connect(function(_, key)
					granted[key] = (granted[key] or 0) + 1
				end)
				M.PassRevoked:Connect(function(_, key)
					table.insert(revoked, key)
				end)
				local p, data = join(h, DS, 73)
				h:settle(3)
				expect(revoked).toEqual({ "TestVIP" })
				expect(M.ownsPass(p, "TestVIP")).toBe(false)
				expect(data.passes.TestVIP).toBeNil()
				expect(M.ownsPass(p, "TestGlow")).toBe(true)
				expect(granted.TestVIP).toBeNil()
				expect(granted.TestGlow).toBe(1)
				-- le client est informé (patch de la clé passes)
				local seen = false
				for _, args in h:sentTo(p, "DataPatch") do
					if
						args[1].passes ~= nil
						and args[1].passes.TestVIP == nil
						and args[1].passes.TestGlow
					then
						seen = true
					end
				end
				expect(seen).toBe(true)
			end
		)

		it("panne de vérification à l'arrivée : le pass enregistré est conservé", function()
			local h, DS, M = boot()
			local store = h.game.DataStoreService:GetDataStore(STORE)
			local Schema = h:require("ServerScriptService.Server.Data.Schema")
			local profile = Schema.defaults()
			profile.passes = { TestVIP = true }
			store:SetAsync("player_74", { data = profile })
			local MockInstance = require("../harness/MockInstance")
			local methods = MockInstance.classMethods.MarketplaceService
			local original = methods.UserOwnsGamePassAsync
			methods.UserOwnsGamePassAsync = function()
				error("HTTP 503 (panne simulée)")
			end
			local p = join(h, DS, 74)
			h:settle(3)
			methods.UserOwnsGamePassAsync = original
			expect(M.ownsPass(p, "TestVIP")).toBe(true)
		end)

		it("charges malveillantes sur le signal d'achat : ignorées sans erreur", function()
			local h, DS, M = boot()
			local p = join(h, DS, 75)
			h.ownedPasses[75] = { [PASS_ID] = true } -- possédé : seul un signal valide l'accorderait
			local signal = h.game.MarketplaceService.PromptGamePassPurchaseFinished
			signal:Fire(p, tostring(PASS_ID), true)
			signal:Fire(p, 0 / 0, true)
			signal:Fire(p, math.huge, true)
			signal:Fire(p, nil, true)
			signal:Fire(p, { PASS_ID }, true)
			signal:Fire(p, PASS_ID, "yes")
			signal:Fire(p, PASS_ID, 1)
			signal:Fire(p, PASS_ID, false)
			signal:Fire(p, 999999, true)
			h:settle(3)
			expect(M.ownsPass(p, "TestVIP")).toBe(false)
			expect(#h.errors).toBe(0)
		end)

		it("le joueur part pendant la vérification : aucune erreur, aucun octroi", function()
			local h, DS, M = boot()
			M.Settings.VERIFY_RETRY_DELAY = 0.1
			local p = join(h, DS, 76)
			h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, PASS_ID, true)
			h:removePlayer(p)
			task.wait(0.5)
			expect(M.ownsPass(p, "TestVIP")).toBe(false)
			expect(#h.errors).toBe(0)
		end)
	end)
end
