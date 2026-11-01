--!nocheck
-- Correctifs r6 « serveur 2 » de Comet Conga — DataService : sauvegarde de départ pendant une panne
-- DataStore.
-- Avant : 4 essais (≈ 14 s de backoff) puis plus rien ; tout ce qui avait été gagné depuis le début
-- de la panne était perdu (les autosaves échouaient aussi) et notre verrou restait dans
-- l'enregistrement (≈ 25 s de « ProfileLoading » au retour, sur un autre serveur). Maintenant, tant
-- que le serveur vit : nouveaux essais en arrière-plan (backoff plafonné, RELEASE_RETRY_WINDOW),
-- même instantané, même jeton de session ; une reconnexion sur ce serveur attend (REJOIN_WAIT) et
-- provoque un essai aussitôt, jamais de données périmées ; BindToClose attend ces essais.
-- Temps réel réduit ×1000 dans ces tests (5 s → 5 ms…).
local task = require("@lune/task")
local MockInstance = require("../harness/MockInstance")
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local STORE = "PlayerData_v1"

	local function waitUntil(cond, timeout)
		local start = os.clock()
		while not cond() and os.clock() - start < (timeout or 3) do
			task.wait(0.005)
		end
		return cond()
	end

	-- DataService seul (aucun autre service ne consomme les pannes injectées). Le harnais du test
	-- précédent est libéré d'abord : ses nouveaux essais encore vivants appelleraient le DataStore
	-- simulé (crochets globaux) du test suivant
	local previous = nil
	local function boot(settings)
		if previous then
			previous:dispose()
		end
		local h = Harness.new()
		Bots.extendSchema(h, { coins = 0, gems = 0 })
		previous = h
		h:require("ReplicatedStorage.Shared.Net").setup()
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		DS.Settings.RELEASE_RETRY_DELAY = 0.005
		DS.Settings.RELEASE_RETRY_MAX = 0.03
		DS.Settings.RELEASE_RETRY_WINDOW = 5
		DS.Settings.RELEASE_RETRY_POLL = 0.002
		for k, v in settings or {} do
			DS.Settings[k] = v
		end
		DS.Init()
		DS.Start()
		return h, DS
	end

	-- lecture directe du magasin simulé (sans yield, sans consommer de panne injectée)
	local function stored(h, userId)
		local store = h.dataStores[STORE .. "/global"]
		return store and MockInstance.state(store).data["player_" .. userId]
	end

	-- joueur chargé, 100 pièces sauvées, puis 500 gagnées pendant la panne qui commence
	local function joinThenOutage(h, DS, userId)
		local p = h:addPlayer({ userId = userId, name = "P" .. userId })
		local data = DS.waitFor(p, 3)
		assert(data ~= nil)
		DS.set(p, "coins", 100)
		assert(DS.saveNow(p))
		h.dataStoreFailures = 1000
		DS.set(p, "coins", 500)
		return p
	end

	describe("Fix r6 serveur 2 › DataService : départ pendant une panne DataStore", function()
		it(
			"panne au-delà des 4 essais de départ (≈ 14 s, puis 200 s simulées) : les dernières pièces sont écrites, verrou libéré",
			function()
				local h, DS = boot()
				local p = joinThenOutage(h, DS, 61)
				h:removePlayer(p)
				-- 4 essais de départ (2 + 4 + 8 ms) puis nouveaux essais en arrière-plan pendant
				-- 0,2 s (= 200 s à l'échelle réelle) : la panne dure toujours
				task.wait(0.2)
				expect(DS.get(p)).toBeNil()
				h.dataStoreFailures = 0
				local saved = waitUntil(function()
					return stored(h, 61).data.coins == 500
				end, 2)
				expect(saved).toBe(true)
				local rec = stored(h, 61)
				expect(rec.data.coins).toBe(500)
				expect(rec.lock).toBeNil()
			end
		)

		it(
			"reconnexion sur le même serveur pendant les nouveaux essais : attente, essai aussitôt, données à jour",
			function()
				local h, DS = boot({ RELEASE_RETRY_DELAY = 3, RELEASE_RETRY_MAX = 3, REJOIN_WAIT = 4 })
				local p = joinThenOutage(h, DS, 62)
				h:removePlayer(p)
				task.wait(0.05)
				local q = h:addPlayer({ userId = 62, name = "P62" })
				task.wait(0.05)
				-- toujours en attente de la sauvegarde de départ (jamais un chargement périmé)
				expect(DS.get(q)).toBeNil()
				expect(q:GetAttribute("ProfileLoading")).toBe(1)
				-- fin de panne : tant que la reconnexion attend, les essais sont rapprochés (sans attendre
				-- les 3 s du backoff), puis elle charge les pièces gagnées pendant la panne
				h.dataStoreFailures = 0
				local data = DS.waitFor(q, 1.5)
				expect(data ~= nil).toBe(true)
				expect(data.coins).toBe(500)
				expect(#h.log.kicks).toBe(0)
			end
		)

		it(
			"reconnexion arrivée pendant les 4 essais de départ : premier nouvel essai aussitôt, données à jour",
			function()
				local h, DS = boot({
					RETRY_BASE_DELAY = 0.02, -- 4 essais de départ en ≈ 0,28 s
					RELEASE_RETRY_DELAY = 3,
					RELEASE_RETRY_MAX = 3,
					REJOIN_WAIT = 4,
				})
				local p = joinThenOutage(h, DS, 68)
				-- la panne couvre exactement les 4 essais de départ (DataService seul consomme)
				h.dataStoreFailures = 4
				h:removePlayer(p)
				task.wait(0.03)
				local q = h:addPlayer({ userId = 68, name = "P68" })
				-- sans essai aussitôt, le premier nouvel essai attendrait 3 s
				local data = DS.waitFor(q, 1.5)
				expect(data ~= nil).toBe(true)
				expect(data.coins).toBe(500)
				expect(#h.log.kicks).toBe(0)
			end
		)

		it(
			"panne plus longue que REJOIN_WAIT : renvoi poli, puis la sauvegarde aboutit quand même",
			function()
				local h, DS = boot({ REJOIN_WAIT = 0.15 })
				local p = joinThenOutage(h, DS, 63)
				h:removePlayer(p)
				task.wait(0.02)
				local q = h:addPlayer({ userId = 63, name = "P63" })
				expect(waitUntil(function()
					return #h.log.kicks > 0
				end, 1)).toBe(true)
				expect(DS.get(q)).toBeNil()
				h:removePlayer(q)
				h.dataStoreFailures = 0
				expect(waitUntil(function()
					return stored(h, 63).data.coins == 500
				end, 2)).toBe(true)
				expect(stored(h, 63).lock).toBeNil()
				-- puis le retour charge les pièces gagnées pendant la panne
				local r = h:addPlayer({ userId = 63, name = "P63" })
				local data = DS.waitFor(r, 2)
				expect(data ~= nil and data.coins).toBe(500)
			end
		)

		it(
			"fenêtre écoulée : les nouveaux essais s'arrêtent et la reconnexion n'est plus bloquée",
			function()
				local h, DS = boot({ RELEASE_RETRY_WINDOW = 0.05 })
				local p = joinThenOutage(h, DS, 64)
				h:removePlayer(p)
				task.wait(0.4)
				local calls = h.stats.dataStoreCalls
				task.wait(0.1)
				expect(h.stats.dataStoreCalls).toBe(calls)
				local lost = false
				for _, line in h.log.output do
					if string.find(line, "PERTE", 1, true) and string.find(line, "P64", 1, true) then
						lost = true
					end
				end
				expect(lost).toBe(true)
				h.dataStoreFailures = 0
				-- verrou de ce serveur resté dans l'enregistrement : même JobId, repris sans attente
				local q = h:addPlayer({ userId = 64, name = "P64" })
				local data = DS.waitFor(q, 2)
				expect(data ~= nil and data.coins).toBe(100)
			end
		)

		it("BindToClose attend un nouvel essai de départ en cours et l'écrit avant la fin", function()
			local h, DS =
				boot({ RELEASE_RETRY_DELAY = 10, RELEASE_RETRY_MAX = 10, RELEASE_RETRY_POLL = 0.01 })
			local p = joinThenOutage(h, DS, 65)
			local other = h:addPlayer({ userId = 66, name = "P66" })
			h.dataStoreFailures = 0
			expect(DS.waitFor(other, 3) ~= nil).toBe(true)
			DS.set(other, "coins", 7)
			h.dataStoreFailures = 1000
			h:removePlayer(p)
			task.wait(0.05)
			-- le premier nouvel essai attendrait 10 s ; la panne finit, puis le serveur s'arrête
			h.dataStoreFailures = 0
			local start = os.clock()
			h:close()
			expect(os.clock() - start < 5).toBe(true)
			local rec = stored(h, 65)
			expect(rec.data.coins).toBe(500)
			expect(rec.lock).toBeNil()
			expect(stored(h, 66).data.coins).toBe(7)
		end)

		it(
			"verrou repris par un autre serveur pendant la panne : jamais écrasé, essais arrêtés",
			function()
				local h, DS = boot({ RELEASE_RETRY_DELAY = 0.02, RELEASE_RETRY_MAX = 0.02 })
				local p = joinThenOutage(h, DS, 67)
				h:removePlayer(p)
				task.wait(0.03)
				-- un autre serveur prend le verrou (écrit directement dans le magasin simulé), puis la
				-- panne finit : le nouvel essai voit le verrou étranger et s'arrête sans écrire
				local rec = stored(h, 67)
				rec.lock = { jobId = "autre-serveur", time = os.time() }
				rec.data.coins = 900
				h.dataStoreFailures = 0
				task.wait(0.3)
				local calls = h.stats.dataStoreCalls
				task.wait(0.1)
				expect(h.stats.dataStoreCalls).toBe(calls)
				local now = stored(h, 67)
				expect(now.data.coins).toBe(900)
				expect(now.lock.jobId).toBe("autre-serveur")
			end
		)
	end)
end
