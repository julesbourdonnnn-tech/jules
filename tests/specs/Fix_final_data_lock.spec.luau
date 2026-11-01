--!nocheck
-- Contre-vérification finale — DataService : reprise du verrou de session par un AUTRE serveur.
-- (Correctif final de Comet Conga, repris avec son test.)
-- Avant : loadRecord reprenait le verrou frais d'un autre serveur dès que ses essais étaient épuisés,
-- y compris par des ERREURS DataStore (panne) : verrou vu une seule fois, ou jamais. Le serveur A,
-- dont la sauvegarde de départ en panne ne réessayait que toutes les 30 s au plus, voyait alors son
-- verrou repris par B : « PERTE » de tout ce qui avait été gagné pendant la panne, et B chargeait le
-- profil d'avant la panne (chemin habituel d'un enfant : « Réessayer » de l'écran de chargement, ou
-- le renvoi après REJOIN_WAIT, l'envoient sur un autre serveur).
-- Maintenant : le verrou n'est repris qu'après LOAD_ATTEMPTS - 1 lectures RÉUSSIES qui l'ont vu
-- (au moins 30 s d'observation, DataStore en marche), jamais parce que des erreurs ont épuisé les
-- essais (renvoi poli sans rien écrire) ; RELEASE_RETRY_MAX = 16 s : après la panne, l'ancien
-- serveur écrit et libère le verrou bien avant.
-- Adaptation au serveur de 16 joueurs : RELEASE_RETRY_MAX 15 → 16 s (budget d'UpdateAsync d'un
-- serveur plein, voir (d)) et LOCKED_RETRY_DELAY 5 → 6 s (l'observation reste ≥ RELEASE_RETRY_MAX
-- + 10) ; les scènes ci-dessous gardent leurs deux chemins possibles (chargement direct ou renvoi).
-- Deux serveurs (deux harnais, JobId distincts, DataService seul) sur un même DataStore simulé ;
-- délais de production réduits d'un même facteur SCALE (mêmes rapports qu'en ligne).
local task = require("@lune/task")
local MockInstance = require("../harness/MockInstance")
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- 1 s de production = SCALE s de test
	local SCALE = 0.03
	-- délais de DataService réduits de SCALE (tous ceux qui comptent dans la course entre serveurs)
	local SCALED = {
		"LOCKED_RETRY_DELAY",
		"RETRY_BASE_DELAY",
		"REJOIN_WAIT",
		"RELEASE_RETRY_DELAY",
		"RELEASE_RETRY_MAX",
		"RELEASE_RETRY_WINDOW",
		"RELEASE_RETRY_POLL",
	}

	local function deepCopy(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function waitUntil(cond, timeout)
		local start = os.clock()
		while not cond() and os.clock() - start < (timeout or 3) do
			task.wait(0.005)
		end
		return cond()
	end

	local function sleepUntil(deadline)
		while os.clock() < deadline do
			task.wait(math.min(0.005, deadline - os.clock()))
		end
	end

	-- DataStore partagé par plusieurs serveurs : chaque serveur reçoit sa vue (appels numérotés par
	-- serveur). shared.down = panne (tout appel échoue) ; shared.before(server, n) juste avant le
	-- n-ième UpdateAsync de ce serveur (fin de panne liée à un essai précis) ; shared.fail(server, n)
	-- = ce seul appel échoue ; shared.runs = nombre d'exécutions de la transformation par appel
	-- (Roblox la rejoue sur un conflit d'écriture)
	local function sharedStore()
		local shared = { data = {}, down = false, calls = {}, log = {}, runs = 1 }
		function shared.view(server)
			local view = {}
			function view.GetAsync(_self, key)
				task.wait()
				if shared.down then
					error("502: API Services rejected request (GetAsync) [panne simulée]", 0)
				end
				return deepCopy(shared.data[key])
			end
			function view.UpdateAsync(_self, key, fn)
				local n = (shared.calls[server] or 0) + 1
				shared.calls[server] = n
				if shared.before then
					shared.before(server, n)
				end
				task.wait()
				local failed = shared.down or (shared.fail ~= nil and shared.fail(server, n))
				table.insert(shared.log, { server = server, n = n, ok = not failed, at = os.clock() })
				if failed then
					error("502: API Services rejected request (UpdateAsync) [panne simulée]", 0)
				end
				local new
				for _ = 1, shared.runs do
					new = fn(deepCopy(shared.data[key]), { Version = "1" })
				end
				if new ~= nil then
					shared.data[key] = deepCopy(new)
				end
				return deepCopy(shared.data[key])
			end
			return view
		end
		return shared
	end

	-- Harnais du test en cours : libérés à la fin du test, et au début du suivant (nouveaux essais
	-- en arrière-plan encore vivants si un test a échoué en route)
	local live = {}
	local function newServer(jobId)
		local h = Harness.new()
		Bots.extendSchema(h, { coins = 0, gems = 0 })
		h.game.JobId = jobId
		table.insert(live, h)
		return h
	end
	local function disposeAll()
		for _, h in live do
			h:dispose()
		end
		table.clear(live)
	end

	-- DataService seul sur ce serveur (comme Fix_r6_serveur_2_data), délais de production × SCALE,
	-- magasin = vue partagée `server`
	local function startDS(h, server, shared, overrides)
		Bots.extendSchema(h, { coins = 0, gems = 0 })
		h:require("ReplicatedStorage.Shared.Net").setup()
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		local S = DS.Settings
		for _, name in SCALED do
			S[name] *= SCALE
		end
		S.AUTOSAVE_INTERVAL = 1e6 -- aucune autosave pendant le test
		for k, v in overrides or {} do
			S[k] = v
		end
		-- GetDataStore (méthode de classe globale du harnais) rend la vue de CE serveur le temps
		-- de son Init
		local cm = MockInstance.classMethods.DataStoreService
		local original = cm.GetDataStore
		cm.GetDataStore = function()
			return shared.view(server)
		end
		local ok, err = pcall(DS.Init)
		cm.GetDataStore = original
		assert(ok, err)
		DS.Start()
		return DS
	end

	local function lines(h, needle)
		local out = {}
		for _, line in h.log.output do
			if string.find(line, needle, 1, true) then
				table.insert(out, line)
			end
		end
		return out
	end

	-- Valeurs successives de l'attribut ProfileLoading du prochain joueur de ce serveur
	local function watchNextPlayer(h)
		local seen = {}
		local conn
		conn = h.game.Players.ChildAdded:Connect(function(p)
			conn:Disconnect()
			p:GetAttributeChangedSignal("ProfileLoading"):Connect(function()
				table.insert(seen, p:GetAttribute("ProfileLoading") or "nil")
			end)
		end)
		return seen
	end

	-- Deux serveurs sur un même magasin ; sur A, le joueur `userId` a 100 pièces sauvées, puis gagne
	-- 500 pendant une panne qui commence, et part (sauvegarde de départ en échec : nouveaux essais
	-- de A en arrière-plan). Rend (shared, hA, hB, A, B, instant du départ)
	local function leaveDuringOutage(userId)
		disposeAll()
		local shared = sharedStore()
		local hA = newServer("serveur-A")
		local hB = newServer("serveur-B")
		local A = startDS(hA, "A", shared)
		local B = startDS(hB, "B", shared)
		local p = hA:addPlayer({ userId = userId, name = "P" .. userId, spawn = false })
		assert(A.waitFor(p, 2) ~= nil, "chargement sur A")
		A.set(p, "coins", 100)
		assert(A.saveNow(p), "sauvegarde avant la panne")
		shared.down = true
		A.set(p, "coins", 500)
		local left = os.clock()
		hA:removePlayer(p)
		return shared, hA, hB, A, B, left
	end

	-- La panne finit juste avant le 5e essai de B (sa première lecture du verrou de A) ; l'enfant
	-- arrive sur B `arrival` s (production) après son départ de A. Essais de B : arrivée + 0, 2, 6,
	-- 14 (erreurs), + 30 (1re lecture), + 36 (6e et dernier) ; nouveaux essais de départ de A : 19,
	-- 29, 45, 61, 77… s après son départ (Comet Conga avant le correctif : 19, 29, 49, 79… s). Selon
	-- que A écrit avant ou après le 6e essai de B, B charge tout de suite, ou renvoie poliment sans
	-- rien écrire et le retour charge : dans les deux cas les gains de la panne, aucune PERTE,
	-- verrou à B.
	-- Rend le chemin suivi ("direct" ou "renvoi").
	local function outageEndsBeforeFifthAttempt(userId, arrival)
		local key = "player_" .. userId
		local shared, hA, hB, _A, B, left = leaveDuringOutage(userId)
		shared.before = function(server, n)
			if server == "B" and n == 5 then
				shared.down = false
			end
		end
		sleepUntil(left + arrival * SCALE)
		local q = hB:addPlayer({ userId = userId, name = "P" .. userId, spawn = false })
		expect(waitUntil(function()
			return B.get(q) ~= nil or q.KickedWith ~= nil
		end, 4)).toBe(true)
		local data = B.get(q)
		local path = "direct"
		if data == nil then
			path = "renvoi"
			-- A n'avait pas encore écrit au 6e essai de B (2e lecture du verrou) : renvoi poli,
			-- verrou jamais pris par B ; A écrit puis libère, le retour charge les gains de la panne
			expect(string.find(q.KickedWith, "could not be loaded", 1, true) ~= nil).toBe(true)
			local atKick = shared.data[key].lock
			expect(atKick == nil or atKick.jobId == "serveur-A").toBe(true)
			expect(waitUntil(function()
				local rec = shared.data[key]
				return rec.lock == nil and rec.data.coins == 500
			end, 3)).toBe(true)
			hB:removePlayer(q)
			local r = hB:addPlayer({ userId = userId, name = "P" .. userId, spawn = false })
			data = B.waitFor(r, 3)
		end
		expect(data ~= nil and data.coins).toBe(500)
		-- B a bien vu le verrou de A au moins une fois (scène jouée comme prévu)
		expect(#lines(hB, "verrouillées par un autre serveur") >= 1).toBe(true)
		expect(lines(hA, "PERTE")).toEqual({})
		local rec = shared.data[key]
		expect(rec.data.coins).toBe(500)
		expect(rec.lock.jobId).toBe("serveur-B")
		disposeAll()
		return path
	end

	describe("Fix final › DataService : verrou d'un autre serveur après une panne", function()
		it(
			"(a) panne finie juste avant le 5e essai de B (1re lecture du verrou) : B charge les gains de la panne, A n'a aucune PERTE, le verrou finit à B",
			function()
				-- arrivée à 26,5 s : 1re lecture à ≈ 56,5 s, A écrit à 61 s, 6e essai de B à ≈ 62,5 s
				-- (charge tout de suite). Avant : A réessayait à 49 s (panne) puis 79 s, B reprenait
				-- le verrou au 6e essai avec le profil d'avant la panne
				outageEndsBeforeFifthAttempt(81, 26.5)
			end
		)

		it(
			"(a) même panne, A écrit juste après le 6e essai de B : renvoi poli sans rien écrire, puis le retour sur B charge les gains de la panne",
			function()
				-- arrivée à 22 s : 1re lecture à ≈ 52 s, 6e essai de B à ≈ 58 s, A écrit à 61 s
				outageEndsBeforeFifthAttempt(88, 22)
			end
		)

		it(
			"(a) panne finie à la 1re lecture du verrou par B : 30 s d'observation, A écrit avant (RELEASE_RETRY_MAX 16), B charge sans renvoi",
			function()
				local key = "player_82"
				local shared, hA, hB, _A, B, left = leaveDuringOutage(82)
				-- la panne finit juste avant le 1er essai de B
				shared.before = function(server, n)
					if server == "B" and n == 1 then
						shared.down = false
					end
				end
				-- arrivée 51,5 s après le départ : A vient de réessayer pendant la panne (45 s ; avant
				-- le correctif 49 s) ; prochain essai 61 s (avant : 79 s, après la reprise à 81,5 s)
				sleepUntil(left + 51.5 * SCALE)
				local q = hB:addPlayer({ userId = 82, name = "P82", spawn = false })
				local data = B.waitFor(q, 4)
				expect(data ~= nil and data.coins).toBe(500)
				expect(q.KickedWith).toBeNil()
				expect(#lines(hB, "verrouillées par un autre serveur") >= 1).toBe(true)
				expect(lines(hA, "PERTE")).toEqual({})
				local rec = shared.data[key]
				expect(rec.data.coins).toBe(500)
				expect(rec.lock.jobId).toBe("serveur-B")
				disposeAll()
			end
		)

		it(
			"(b) verrou frais d'un serveur disparu (personne ne réessaie) : toujours repris au 6e essai",
			function()
				disposeAll()
				local shared = sharedStore()
				shared.data.player_83 = {
					data = { version = 1, coins = 42, receipts = {} },
					lock = { jobId = "serveur-disparu", time = os.time() },
				}
				local hB = newServer("serveur-B")
				local B = startDS(hB, "B", shared)
				local seen = watchNextPlayer(hB)
				local q = hB:addPlayer({ userId = 83, name = "P83", spawn = false })
				local data = B.waitFor(q, 3)
				expect(data ~= nil and data.coins).toBe(42)
				expect(shared.calls.B).toBe(B.Settings.LOAD_ATTEMPTS)
				expect(seen).toEqual({ 1, 2, 3, 4, 5, 6, "nil" })
				expect(shared.data.player_83.lock.jobId).toBe("serveur-B")
				expect(q.KickedWith).toBeNil()
				disposeAll()
			end
		)

		it("(b) verrou expiré (plus vieux que LOCK_EXPIRY) : repris dès le 1er essai", function()
			disposeAll()
			local shared = sharedStore()
			local hB = newServer("serveur-B")
			local B = startDS(hB, "B", shared)
			shared.data.player_84 = {
				data = { version = 1, coins = 7, receipts = {} },
				lock = { jobId = "serveur-disparu", time = os.time() - B.Settings.LOCK_EXPIRY - 1 },
			}
			local q = hB:addPlayer({ userId = 84, name = "P84", spawn = false })
			local data = B.waitFor(q, 2)
			expect(data ~= nil and data.coins).toBe(7)
			expect(shared.calls.B).toBe(1)
			expect(shared.data.player_84.lock.jobId).toBe("serveur-B")
			disposeAll()
		end)

		-- Erreurs aux essais `failing`, verrou frais d'un autre serveur lu aux autres : renvoi poli au
		-- dernier essai, rien d'écrit, aucune attente après le dernier essai
		local function refusedAfterErrors(userId, failing)
			disposeAll()
			local shared = sharedStore()
			local key = "player_" .. userId
			shared.data[key] = {
				data = { version = 1, coins = 100, receipts = {} },
				lock = { jobId = "serveur-A", time = os.time(), session = "jeton-A" },
				meta = { created = 1, lastSave = 2, saves = 3 },
			}
			local before = deepCopy(shared.data[key])
			shared.fail = function(server, n)
				return server == "B" and failing[n] == true
			end
			local hB = newServer("serveur-B")
			-- attente après une lecture du verrou bien plus longue que le backoff des erreurs : un
			-- renvoi qui l'attendrait encore après le dernier essai se verrait
			local B = startDS(hB, "B", shared, { RETRY_BASE_DELAY = 0.002, LOCKED_RETRY_DELAY = 0.05 })
			local seen = watchNextPlayer(hB)
			local q = hB:addPlayer({ userId = userId, name = "P" .. userId, spawn = false })
			expect(waitUntil(function()
				return q.KickedWith ~= nil or B.get(q) ~= nil
			end, 3)).toBe(true)
			local kickedAt = os.clock()
			expect(B.get(q)).toBeNil()
			expect(q.KickedWith ~= nil and string.find(q.KickedWith, "could not be loaded", 1, true) ~= nil).toBe(
				true
			)
			expect(shared.calls.B).toBe(B.Settings.LOAD_ATTEMPTS)
			-- le dernier essai a lu le verrou (pas une erreur), et le renvoi a suivi sans attendre
			local last = shared.log[#shared.log]
			expect(last.server == "B" and last.n == B.Settings.LOAD_ATTEMPTS and last.ok).toBe(true)
			expect(kickedAt - last.at < B.Settings.LOCKED_RETRY_DELAY).toBe(true)
			expect(seen).toEqual({ 1, 2, 3, 4, 5, 6, "nil" })
			-- enregistrement et verrou intacts : ni données, ni verrou, ni méta écrits
			expect(shared.data[key]).toEqual(before)
			task.wait(0.1)
			expect(shared.calls.B).toBe(B.Settings.LOAD_ATTEMPTS)
			disposeAll()
		end

		it(
			"(c) erreurs aux essais 1 à 5, verrou vu au 6e : renvoi poli, enregistrement et verrou intacts",
			function()
				refusedAfterErrors(85, { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true })
			end
		)

		it(
			"(c) une seule erreur (essai 3) parmi les lectures du verrou : 4 lectures ne suffisent pas",
			function()
				refusedAfterErrors(86, { [3] = true })
			end
		)

		it(
			"(c) transformation rejouée par UpdateAsync (conflit) : chaque lecture compte une fois, verrou repris au 6e essai",
			function()
				disposeAll()
				local shared = sharedStore()
				shared.runs = 2
				shared.data.player_87 = {
					data = { version = 1, coins = 9, receipts = {} },
					lock = { jobId = "serveur-disparu", time = os.time() },
				}
				local hB = newServer("serveur-B")
				local B = startDS(hB, "B", shared)
				local seen = watchNextPlayer(hB)
				local q = hB:addPlayer({ userId = 87, name = "P87", spawn = false })
				local data = B.waitFor(q, 3)
				expect(data ~= nil and data.coins).toBe(9)
				expect(shared.calls.B).toBe(B.Settings.LOAD_ATTEMPTS)
				expect(seen).toEqual({ 1, 2, 3, 4, 5, 6, "nil" })
				disposeAll()
			end
		)

		it(
			"(d) invariant : l'observation du verrou (LOCKED_RETRY_DELAY × (LOAD_ATTEMPTS − 1)) dépasse d'au moins 10 s le plus long intervalle de nouvel essai de départ",
			function()
				local h = Harness.new()
				local S = h:require("ServerScriptService.Server.Services.DataService").Settings
				expect(S.LOCKED_RETRY_DELAY * (S.LOAD_ATTEMPTS - 1) >= S.RELEASE_RETRY_MAX + 10).toBe(true)
				expect(S.RELEASE_RETRY_MAX).toBe(16)
				-- pire attente d'un chargement (lectures du verrou et erreurs mêlées, aucune attente
				-- après le dernier essai) sous RETRY_MAX_WAIT (60 s) de src/first/Loading.client
				local worst = 0
				for attempt = 1, S.LOAD_ATTEMPTS - 1 do
					worst += math.max(math.min(2 ^ attempt, 16) * S.RETRY_BASE_DELAY, S.LOCKED_RETRY_DELAY)
				end
				expect(worst < 60).toBe(true)
				-- nouveaux essais de départ par minute et par joueur parti, sous le budget de base
				-- d'UpdateAsync (60 + 10 × joueurs par minute) pour un serveur PLEIN dont tous les joueurs
				-- sont partis (taille lue dans default.project.json : 16 joueurs ; Comet Conga : 12)
				local fs = require("@lune/fs")
				local serde = require("@lune/serde")
				local project = serde.decode("json", fs.readFile("default.project.json"))
				local maxPlayers = project.tree.Players["$properties"].MaxPlayers
				expect(maxPlayers >= 16).toBe(true)
				expect(maxPlayers * 60 / S.RELEASE_RETRY_MAX <= 60).toBe(true)
			end
		)
	end)
end
