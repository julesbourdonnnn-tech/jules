--!nocheck
-- Passe finale « fin-server-data-publish » — socle serveur (DataService, MonetizationService) :
--   * serveur en ligne : GetDataStore en échec = DataStore indisponible, JAMAIS de repli en mémoire
--     (profil vide jamais sauvegardé) ; le joueur qui arrive est renvoyé (LOAD_FAILED_MESSAGE), un
--     reçu Robux n'est pas acquitté ; nouvel essai en arrière-plan, chargements rétablis ensuite ;
--     Studio : repli en mémoire inchangé
--   * MonetizationService : magasin en mémoire hors de Studio → reçu NotProcessedYet (défense en
--     profondeur)
--   * chargement en échec définitif : aucune attente de backoff après le dernier essai (renvoi
--     aussitôt)
--   * chaque écriture UpdateAsync d'un profil porte { UserId } (demandes d'effacement Roblox)
--   * flux d'arrivée sans connexion Heartbeat (règle 7 du contrat : seul le tick de CongaService)
--   * signal PromptGamePassPurchaseFinished falsifié en boucle : appels UserOwnsGamePassAsync bornés
--     (RateLimit + réponse « non possédé » retenue), un achat réel reste accordé
local task = require("@lune/task")
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local STORE = "PlayerData_v1"
	local PRODUCT_ID = 1501
	local PASS_ID = 2501
	local OTHER_PASS_ID = 2502

	local function waitUntil(cond, timeout)
		local start = os.clock()
		while not cond() and os.clock() - start < (timeout or 3) do
			task.wait(0.01)
		end
		return cond()
	end

	-- opts.isStudio ; opts.brokenStore : GetDataStore(PlayerData_v1) lève tant que state.broken ;
	-- opts.kickLeaves : un Kick fait partir le joueur (comme sur Roblox) ; opts.recordWaits : liste
	-- des task.wait(t) appelés par le code de DataService ; opts.before(ctx) avant h:boot()
	local function boot(opts)
		opts = opts or {}
		local h = Harness.new({ isStudio = opts.isStudio == true })
		local state = { broken = opts.brokenStore == true, getCalls = 0 }
		if opts.brokenStore then
			local methods = MockInstance.classMethods.DataStoreService
			local realGet = methods.GetDataStore
			methods.GetDataStore = function(self, name, scope)
				if name == STORE then
					state.getCalls += 1
					if state.broken then
						error("DataStore indisponible [panne simulée]", 0)
					end
				end
				return realGet(self, name, scope)
			end
		end
		if opts.kickLeaves then
			local onKick = MockInstance.onKick
			MockInstance.onKick = function(player, message)
				onKick(player, message)
				task.defer(function()
					if player.Parent ~= nil then
						h:removePlayer(player)
					end
				end)
			end
		end
		local waits = nil
		if opts.recordWaits then
			waits = {}
			local realTask = h.globals.task
			h.globals.task = setmetatable({
				wait = function(t)
					table.insert(waits, t or 0)
					return realTask.wait(t)
				end,
			}, { __index = realTask })
		end
		local cfg = h:require("ReplicatedStorage.Shared.Config.Monetization")
		cfg.Products.TestDust = { id = PRODUCT_ID, price = 99, nameKey = "x", descKey = "x", order = 1 }
		cfg.Passes.TestVIP = { id = PASS_ID, price = 199, nameKey = "x", descKey = "x", order = 1 }
		cfg.Passes.TestGlow = { id = OTHER_PASS_ID, price = 99, nameKey = "x", descKey = "x", order = 2 }
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		if waits then
			h.globals.task = getmetatable(h.globals.task).__index -- seul DataService est espionné
		end
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		if DS.Settings.STORE_RETRY_DELAY ~= nil then
			DS.Settings.STORE_RETRY_DELAY = 0.02
			DS.Settings.STORE_RETRY_MAX = 0.05
		end
		local M = h:require("ServerScriptService.Server.Services.MonetizationService")
		M.Settings.VERIFY_RETRY_DELAY = 0.001
		local ctx = { h = h, DS = DS, M = M, state = state, waits = waits, credited = 0 }
		if opts.before then
			opts.before(ctx)
		end
		h:boot()
		M.registerProduct("TestDust", function(player)
			ctx.credited += 1
			DS.increment(player, "stardust", 100)
			return true
		end)
		return ctx
	end

	local function stored(ctx, userId)
		return ctx.h.dataStores[STORE .. "/global"]
			and MockInstance.state(ctx.h.dataStores[STORE .. "/global"]).data["player_" .. userId]
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		local data = ctx.DS.waitFor(p, 3)
		ctx.h:settle(3)
		return p, data
	end

	-- ---------------------------------------------------------------------------------------------
	describe(
		"Fix r5 serveur data › serveur en ligne sans DataStore : jamais de repli en mémoire",
		function()
			it("GetDataStore en échec hors Studio : renvoi, aucun profil, reçu non acquitté", function()
				local ctx = boot({ brokenStore = true, kickLeaves = true })
				local h, DS = ctx.h, ctx.DS
				local Enum = h.globals.Enum
				expect(DS.usingMemoryStore).toBe(false)
				local p = h:addPlayer({ userId = 1, name = "P1" })
				-- un reçu Robux arrive pendant le chargement
				local decision = nil
				task.spawn(function()
					decision = h:purchaseProduct(p, PRODUCT_ID, "achat-1")
				end)
				expect(waitUntil(function()
					return #h.log.kicks > 0
				end, 3)).toBe(true)
				expect(waitUntil(function()
					return decision ~= nil
				end, 3)).toBe(true)
				expect(#h.log.kicks).toBe(1)
				expect(string.find(h.log.kicks[1].message, "could not be loaded", 1, true) ~= nil).toBe(true)
				expect(DS.get(p)).toBeNil()
				expect(DS.usingMemoryStore).toBe(false)
				expect(decision).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
				expect(ctx.credited).toBe(0)
				-- « Réessayer » de l'écran de chargement : l'attribut d'attente n'est plus posé
				expect(p:GetAttribute("ProfileLoading")).toBeNil()
			end)

			it(
				"DataStore retrouvé en arrière-plan : les arrivées suivantes chargent et sauvegardent",
				function()
					local ctx = boot({ brokenStore = true, kickLeaves = true })
					local h, DS = ctx.h, ctx.DS
					local Enum = h.globals.Enum
					-- toujours en panne : premier joueur renvoyé
					h:addPlayer({ userId = 2, name = "P2" })
					expect(waitUntil(function()
						return #h.log.kicks > 0
					end, 3)).toBe(true)
					local before = ctx.state.getCalls
					expect(waitUntil(function()
						return ctx.state.getCalls > before
					end, 2)).toBe(true) -- nouvel essai en arrière-plan
					ctx.state.broken = false
					expect(waitUntil(function()
						return ctx.state.getCalls > before + 1
					end, 2)).toBe(true)
					h:settle(2)
					local p, data = join(ctx, 3)
					expect(data ~= nil).toBe(true)
					expect(DS.usingMemoryStore).toBe(false)
					expect(#h.log.kicks).toBe(1)
					-- les écritures vont dans le vrai DataStore
					expect(h:purchaseProduct(p, PRODUCT_ID, "achat-3")).toBe(
						Enum.ProductPurchaseDecision.PurchaseGranted
					)
					local rec = stored(ctx, 3)
					expect(rec ~= nil).toBe(true)
					expect(rec.data.stardust).toBe(100)
				end
			)

			it(
				"Studio : GetDataStore en échec → repli en mémoire inchangé (jeu jouable, achats d'essai)",
				function()
					local ctx = boot({ brokenStore = true, isStudio = true })
					local h, DS = ctx.h, ctx.DS
					local Enum = h.globals.Enum
					expect(DS.usingMemoryStore).toBe(true)
					local p, data = join(ctx, 4)
					expect(data ~= nil).toBe(true)
					expect(#h.log.kicks).toBe(0)
					expect(h:purchaseProduct(p, PRODUCT_ID, "essai-4")).toBe(
						Enum.ProductPurchaseDecision.PurchaseGranted
					)
					expect(ctx.credited).toBe(1)
					expect(stored(ctx, 4)).toBeNil() -- rien dans le DataStore simulé : mémoire seulement
				end
			)

			it(
				"MonetizationService : magasin en mémoire hors Studio → NotProcessedYet, rien crédité",
				function()
					local ctx = boot()
					local h, DS = ctx.h, ctx.DS
					local Enum = h.globals.Enum
					local p, data = join(ctx, 5)
					DS.usingMemoryStore = true -- état anormal en ligne (défense en profondeur)
					expect(h:purchaseProduct(p, PRODUCT_ID, "achat-5")).toBe(
						Enum.ProductPurchaseDecision.NotProcessedYet
					)
					expect(ctx.credited).toBe(0)
					expect(data.stardust).toBe(0)
					-- dans Studio, les achats d'essai restent acquittés
					h.isStudio = true
					expect(h:purchaseProduct(p, PRODUCT_ID, "achat-5")).toBe(
						Enum.ProductPurchaseDecision.PurchaseGranted
					)
					expect(ctx.credited).toBe(1)
				end
			)
		end
	)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix r5 serveur data › chargement en échec définitif", function()
		it("aucune attente de backoff après le dernier essai : renvoi aussitôt", function()
			local ctx = boot({ recordWaits = true })
			local h, DS = ctx.h, ctx.DS
			h.dataStoreFailures = 1000
			local p = h:addPlayer({ userId = 6, name = "P6" })
			expect(waitUntil(function()
				return #h.log.kicks > 0
			end, 3)).toBe(true)
			h.dataStoreFailures = 0
			expect(DS.get(p)).toBeNil()
			-- backoff de DataService (RETRY_BASE_DELAY = 0,001 s : 0,002 … 0,016 s) ; les autres attentes
			-- du module (0,1 s, autosave, flux) sont hors de cette plage
			local backoff = {}
			for _, t in ctx.waits do
				if t > 0.0015 and t < 0.05 then
					table.insert(backoff, t)
				end
			end
			expect(#backoff).toBe(DS.Settings.LOAD_ATTEMPTS - 1)
			expect(backoff).toEqual({ 0.002, 0.004, 0.008, 0.016, 0.016 })
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix r5 serveur data › écritures liées au UserId (droit à l'effacement)", function()
		it("chargement, sauvegarde, départ et libération du verrou passent { UserId }", function()
			local ctx = boot({
				before = function(c)
					local methods = MockInstance.classMethods.DataStore
					local real = methods.UpdateAsync
					c.writes = {}
					c.leaveDuringLoad = nil
					methods.UpdateAsync = function(self, key, fn)
						if self.Name ~= STORE then
							return real(self, key, fn)
						end
						if c.leaveDuringLoad == key then
							-- le joueur part pendant son chargement (releaseLoadLock ensuite)
							c.leaveDuringLoad = nil
							local id = tonumber(string.match(key, "%d+"))
							local pl = c.h.game.Players:GetPlayerByUserId(id)
							c.h.game.Players.PlayerRemoving:Fire(pl)
							pl.Parent = nil
						end
						return real(self, key, function(old, info)
							local new, userIds = fn(old, info)
							if new ~= nil then
								table.insert(c.writes, { key = key, userIds = userIds })
							end
							return new, userIds
						end)
					end
				end,
			})
			local h, DS = ctx.h, ctx.DS
			local p = join(ctx, 7)
			DS.set(p, "glow", 5)
			expect(DS.saveNow(p)).toBe(true)
			h:removePlayer(p)
			h:settle(5)
			ctx.leaveDuringLoad = "player_8"
			h:addPlayer({ userId = 8, name = "P8" })
			h:settle(10)
			expect(stored(ctx, 8) ~= nil).toBe(true)
			expect(stored(ctx, 8).lock).toBeNil() -- verrou du chargement abandonné libéré
			local byKey = {}
			for _, w in ctx.writes do
				byKey[w.key] = (byKey[w.key] or 0) + 1
				local id = tonumber(string.match(w.key, "%d+"))
				expect({ key = w.key, userIds = w.userIds }).toEqual({ key = w.key, userIds = { id } })
			end
			expect(byKey.player_7).toBe(3) -- chargement, saveNow, départ
			expect(byKey.player_8).toBe(2) -- chargement, libération du verrou
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix r5 serveur data › flux d'arrivée sans Heartbeat (contrat, règle 7)", function()
		it("DataService n'ouvre aucune connexion Heartbeat ; le flux se termine quand même", function()
			local h = Harness.new()
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			Clock.freeze(1800000000)
			h:require("ReplicatedStorage.Shared.Net").setup()
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			local Schema = h:require("ServerScriptService.Server.Data.Schema")
			local heartbeat = h.game.RunService.Heartbeat
			local before = #heartbeat._handlers
			DS.Init()
			DS.Start()
			expect(#heartbeat._handlers).toBe(before)
			local profile = Schema.defaults()
			profile.nebbies = {}
			for i = 1, 180 do
				profile.nebbies["u" .. i] = { s = 1 + (i % 30), f = i % 6, v = 0, st = 1 }
			end
			profile.nextUid = 181
			h.game.DataStoreService:GetDataStore(STORE):SetAsync("player_9", { data = profile })
			local p = h:addPlayer({ userId = 9, name = "P9" })
			local data = DS.waitFor(p, 3)
			expect(data ~= nil).toBe(true)
			local snap = h:sentTo(p, "DataSnapshot")[1][1]
			local view = table.clone(snap.nebbies)
			local inline = 0
			for _ in view do
				inline += 1
			end
			expect(inline).toBe(DS.Settings.SNAPSHOT_INLINE)
			-- aucun Heartbeat : seul le temps (Clock) avance, la boucle du flux fait le reste
			for _ = 1, 40 do
				Clock.advance(0.1)
				h:settle(2)
			end
			for _, args in h:sentTo(p, "DataPatch") do
				local entries = args[3]
				if type(entries) == "table" and entries.nebbies then
					for uid, r in entries.nebbies.set or {} do
						view[uid] = r
					end
				end
			end
			local n = 0
			for uid, r in data.nebbies do
				n += 1
				expect(view[uid] ~= nil).toBe(true)
			end
			expect(n).toBe(180)
			-- flux terminé : la boucle s'arrête (aucun envoi de plus)
			local sent = #h:sentTo(p, "DataPatch")
			for _ = 1, 10 do
				Clock.advance(0.5)
				h:settle(2)
			end
			expect(#h:sentTo(p, "DataPatch")).toBe(sent)
			h:removePlayer(p)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix r5 serveur data › signal d'achat de pass falsifié en boucle", function()
		local function countOwnershipCalls(h)
			local methods = MockInstance.classMethods.MarketplaceService
			local real = methods.UserOwnsGamePassAsync
			local counter = { n = 0 }
			methods.UserOwnsGamePassAsync = function(self, userId, passId)
				counter.n += 1
				return real(self, userId, passId)
			end
			return counter
		end

		it(
			"50 signaux falsifiés : appels UserOwnsGamePassAsync bornés ; un achat réel reste accordé",
			function()
				local ctx = boot()
				local h, M = ctx.h, ctx.M
				local p = join(ctx, 10)
				h:settle(3)
				local calls = countOwnershipCalls(h)
				local signal = h.game.MarketplaceService.PromptGamePassPurchaseFinished
				for _ = 1, 50 do
					signal:Fire(p, PASS_ID, true)
					h:settle(2) -- chaque vérification se termine avant le signal suivant
				end
				h:settle(3)
				expect(M.ownsPass(p, "TestVIP")).toBe(false)
				-- une seule vérification (3 essais) : la réponse « non possédé » est retenue
				expect(calls.n).toBe(M.Settings.VERIFY_ATTEMPTS)
				-- achat réel d'un autre pass juste après : accordé
				h:grantPass(p, OTHER_PASS_ID)
				expect(waitUntil(function()
					return M.ownsPass(p, "TestGlow")
				end, 2)).toBe(true)
			end
		)

		it("signaux falsifiés sur plusieurs passes : plafond RateLimit par joueur", function()
			local ctx = boot()
			local h, M = ctx.h, ctx.M
			local cfg = h:require("ReplicatedStorage.Shared.Config.Monetization")
			local p = join(ctx, 11)
			h:settle(3)
			local calls = countOwnershipCalls(h)
			local signal = h.game.MarketplaceService.PromptGamePassPurchaseFinished
			-- 2 passes de test en alternance, mémoire « non possédé » oubliée entre deux salves
			for _ = 1, 25 do
				signal:Fire(p, PASS_ID, true)
				signal:Fire(p, OTHER_PASS_ID, true)
				h:settle(2)
				M.Settings.NOT_OWNED_MEMORY = 0
			end
			task.wait(0.1) -- dernières vérifications terminées
			-- mémoire désactivée : seul RateLimit borne (plusieurs vérifications, jamais plus que le plafond)
			expect(calls.n > 2 * M.Settings.VERIFY_ATTEMPTS).toBe(true)
			expect(calls.n <= M.Settings.VERIFY_RATE_CALLS * M.Settings.VERIFY_ATTEMPTS).toBe(true)
			expect(M.ownsPass(p, "TestVIP")).toBe(false)
			expect(cfg.Passes.TestVIP.id).toBe(PASS_ID)
			expect(#h.errors).toBe(0)
		end)
	end)
end
