--!nocheck
-- Migration_I (lot I, étape 1, items C3, C4, T9 du plan I) : preuve que l'ouverture de SchemaV2 ne
-- perd rien. Serveurs de la configuration de lancement (SchemaV2 ouvert), vrai DataService, magasin
-- simulé partagé (tests/harness/Chaos, recette de DataChaos). Pour chaque forme de profil v1.3 (joueur
-- neuf, v1.json, vétéran, profils partiels ou abîmés, v0.json, profil abîmé de DataChaos) :
--   * chargé et migré UNE fois (version 2), sauvegardé, rechargé sur un autre serveur ;
--   * le JSON sauvegardé est celui que le serveur suivant charge, et sa sauvegarde suivante est la même ;
--   * le deuxième chargement ne répare rien (aucun ProfileRepaired) et ne migre plus (Confettis égaux) ;
--   * chaque valeur v1.3 d'un profil sain survit exactement (pièces, squishies, cosmétiques, records,
--     Squishydex, objectifs, pass, reçus, réglages…) ; les champs migrés suivent Schema.MIGRATION_V2.
-- Et la règle D3 (docs/04 §27.2) : un profil v2 sur un serveur v1.3 et un profil v3 sur le serveur de
-- lancement sont refusés sans rien écrire (ni données ni verrou), avec le seul avertissement attendu.
local fs = require("@lune/fs")
local task = require("@lune/task")
local Bots = require("../harness/Bots")
local Chaos = require("../harness/Chaos")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local DAY = math.floor(T0 / 86400)
	local S = "ServerScriptService.Server.Services."
	local live = {}

	local function waitUntil(cond, timeout)
		local start = os.clock()
		while not cond() and os.clock() - start < (timeout or 5) do
			task.wait(0.005)
		end
		return cond()
	end

	local function disposeAll()
		for _, h in live do
			h:dispose()
		end
		table.clear(live)
	end

	-- Préréglage fixé pour tous les serveurs d'un appel
	local function harnessWith(preset)
		return setmetatable({
			new = function(options)
				local o = table.clone(options or {})
				o.flags = preset
				return Harness.new(o)
			end,
		}, { __index = Harness })
	end

	-- Serveur complet sur le magasin partagé ; `preset` nil : configuration livrée (lancement)
	local function server(shared, jobId, preset)
		local w = Chaos.boot(if preset then harnessWith(preset) else Harness, Bots, shared, jobId, {
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
				w.repaired = {}
				w.Signals.ProfileRepaired:Connect(function(player, fixes)
					table.insert(w.repaired, { userId = player.UserId, fixes = fixes })
				end)
			end,
		})
		w.Invariants = w.h:require("ReplicatedStorage.Shared.Logic.Invariants")
		w.Tables = w.h:require("ReplicatedStorage.Shared.Util.Tables")
		table.insert(live, w.h)
		return w
	end

	-- Aucune erreur ; seuls les avertissements permis
	local function clean(w, shared, allowed)
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

	local function newStore()
		local shared = Chaos.store()
		shared.problems = {}
		shared.onWrite = function(key, value)
			local ok, why = Chaos.check(value)
			if not ok then
				table.insert(shared.problems, key .. " : " .. tostring(why))
			end
		end
		return shared
	end

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

	-- Feuilles d'une table : chemin → valeur (table vide = "{}")
	local function leaves(t, prefix, out)
		out = out or {}
		local empty = true
		for k, v in t do
			empty = false
			local path = if prefix == "" then tostring(k) else prefix .. "." .. tostring(k)
			if type(v) == "table" then
				leaves(v, path, out)
			else
				out[path] = v
			end
		end
		if empty and prefix ~= "" then
			out[prefix] = "{}"
		end
		return out
	end

	-- Différences entre deux profils (chemins), triées
	local function diff(a, b)
		local la, lb = leaves(a, ""), leaves(b, "")
		local out = {}
		for path, v in la do
			if lb[path] ~= v and not (v ~= v and lb[path] ~= lb[path]) then
				table.insert(out, path)
			end
		end
		for path in lb do
			if la[path] == nil then
				table.insert(out, path)
			end
		end
		table.sort(out)
		return out
	end

	-- Écritures faites par les services au premier chargement d'une séance (jamais par la migration) :
	-- présence (lastOnline au départ, sessions, croissance remise à l'heure), piste de la semaine fixée
	-- au premier chargement v2 (QuestService), jour de jeu de la piste
	local SESSION_PATHS = {
		["lastOnline"] = true,
		["growth.t"] = true,
		["stats.sessions"] = true,
		["weeklyTrack.firstPeriodEnd"] = true,
		["weeklyTrack.period"] = true,
		["weeklyTrack.playDay"] = true,
	}
	local function sessionPath(path)
		return SESSION_PATHS[path] == true or string.match(path, "^weeklyTrack%.play%.") ~= nil
	end

	-- ---------------------------------------------------------------------------------------------
	-- Formes de profils v1.3 (construites sur Schema.defaultsV1 d'un serveur v1.3)
	-- ---------------------------------------------------------------------------------------------
	local probe = Harness.new({ flags = "v13" })
	local SchemaV1 = probe:require("ServerScriptService.Server.Data.Schema")
	local Species = probe:require("ReplicatedStorage.Shared.Config.Species")
	local Mutations = probe:require("ReplicatedStorage.Shared.Config.Mutations")
	local Monetization = probe:require("ReplicatedStorage.Shared.Config.Monetization")
	local Cosmetics = probe:require("ReplicatedStorage.Shared.Config.Cosmetics")
	local Http = probe.game.HttpService
	local function readJson(name)
		return Http:JSONDecode(fs.readFile("tests/fixtures/profiles/" .. name))
	end

	-- uid = base 36 de nextUid (minuscules), comme SquishyService
	local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
	local function base36(n)
		local out = ""
		repeat
			local k = n % 36
			out = string.sub(DIGITS, k + 1, k + 1) .. out
			n = n // 36
		until n == 0
		return out
	end

	local function rec(s, opts)
		opts = opts or {}
		return {
			s = s,
			m = opts.m or 0,
			st = opts.st or 0,
			z = opts.z or 100,
			zg = 0,
			bf = 0,
			lk = opts.lk == true,
			o = opts.o or "",
			at = opts.at or "pen",
			b = 1,
			gd = 0,
		}
	end

	-- profil v1.3 sain du jour T0 (aucune remise à zéro du jour, aucun gain hors ligne)
	local function today(d)
		d.firstJoin = T0 - 86400 * 40
		d.lastOnline = T0
		d.growth.t = T0
		d.caps.day = DAY
		d.lastFeedDay = DAY
		d.objectives.day = DAY
		d.onboarding = { step = 11, done = true, demoDone = true }
		return d
	end

	-- vétéran : Record R 24, Squishydex plein, tous les cosmétiques de la v1.3 (pass, tenues, jours de
	-- Plop, tampons), réglages changés, records, 1e30 pièces
	local function veteran()
		local d = today(SchemaV1.defaultsV1())
		d.R = 24
		d.coins = 1e30
		d.pot = 1e20
		d.fame = 123456789
		d.plopDays = 80
		d.biggestEver = 1e12
		d.tiles = { snack = 12, decor = 18, pens = 14, cozyBed = true, seen = 255 }
		for key in Monetization.Passes do
			d.passes[key] = true
		end
		local outfits = {}
		for _, def in Cosmetics.List do
			if def.kind == "outfit" then
				d.outfits.owned[def.id] = 2
				table.insert(outfits, def.id)
			end
		end
		local mask = 2 ^ (Mutations.Count + 1) - 1
		for s = 1, #Species.List do
			d.dex.mut[s] = mask
			d.dex.stars[s] = 31
			d.trophies[s] = 1e9 + s
		end
		for f = 1, #Species.FamilyOrder do
			d.dex.fam[f] = 1
		end
		for i = 1, 30 do
			local at = if i <= 18 then "pen" elseif i <= 24 then "pool" elseif i <= 28 then "dodo" else "mail"
			d.squishies[base36(i)] = rec(((i - 1) % #Species.List) + 1, {
				z = 1e6 * i,
				m = i % 3,
				st = i % 4,
				lk = i == 3,
				o = if i <= #outfits then outfits[i] else "",
				at = at,
			})
		end
		d.nextUid = 31
		d.mount = base36(5)
		d.cosmetics =
			{ saddle = "royal", trail = "musicNotes", title = "", theme = "candyNight", flag = "squishydex" }
		d.settings.music = false
		d.settings.sfx = false
		d.settings.lang = "fr"
		d.stats.presses = 123456
		d.stats.perfects = 9999
		d.stats.bestCombo = 77
		d.stats.splorches = 24
		d.stats.playSeconds = 3600 * 200
		d.receipts = { "achat-1", "achat-2", "achat-3" }
		d.objectives.list = {
			{ id = 1, p = 30, done = true, claimed = false },
			{ id = 7, p = 1, done = false, claimed = false },
			{ id = 14, p = 0, done = false, claimed = false },
		}
		d.golden.lastWinAt = T0 - 100
		d.moon.lastSession = 12
		d.released = { { s = 1, m = 0 }, { s = 2, m = 1 } }
		return d
	end

	-- profils partiels ou abîmés (tables absentes, mauvais types, nombres énormes, clés inconnues). Un
	-- DataStore ne garde jamais NaN ni l'infini (JSON : SetAsync les refuse) : un profil sauvegardé
	-- peut porter « NaN » en texte, jamais le nombre ; le nombre NaN en mémoire est prouvé par
	-- ProfileRepair, ProfileRepair_v2 et DataChaos
	local function partials()
		local out = {}
		local a = today(SchemaV1.defaultsV1())
		a.tiles = nil
		a.stats = nil
		a.dex = "cassé"
		a.cosmetics = nil
		a.R = 7
		out.missing = a
		local b = today(SchemaV1.defaultsV1())
		b.coins = "NaN"
		b.pot = 1e308
		b.R = "douze"
		b.fame = -5
		b.squishies = { ["1"] = rec(1, { z = "NaN" }), ["2"] = rec(0), ["3"] = "x" }
		b.nextUid = 2
		b.settings = { music = "oui", lang = 42 }
		out.wrongTypes = b
		local c = today(SchemaV1.defaultsV1())
		c.coins = 1e308
		c.pot = 1e305
		c.R = 1e9
		c.biggestEver = 1e308
		c.squishies = { ["1"] = rec(2, { z = 1e299 }) }
		c.nextUid = 2
		out.huge = c
		local d = today(SchemaV1.defaultsV1())
		d.R = 3
		d.unknownKey = { nested = true, n = 3 }
		d.legacyGold = 77
		d.tiles.legacyPad = 9
		out.unknownKeys = d
		-- profil v1 portant des champs v2 périmés (essai, vieux bug) : la migration les remet à zéro
		local e = today(SchemaV1.defaultsV1())
		e.R = 5
		e.bestR = 99
		e.confetti = 1e9
		e.ascendDay = -3
		e.tiles.star = 8
		out.staleV2 = e
		return out
	end

	-- profil abîmé de DataChaos (trous, tenues portées, plafonds ; « NaN » en texte, seule forme qu'un
	-- DataStore peut rendre)
	local function chaosBroken()
		local d = today(SchemaV1.defaultsV1())
		d.coins = "NaN"
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
		return d
	end

	-- Valeurs v1.3 qui doivent survivre exactement (chemins de feuilles du profil v1)
	local function v1Leaves(d)
		local out = {}
		for path, v in leaves(d, "") do
			if path ~= "version" and path ~= "tiles.pens" and not sessionPath(path) then
				out[path] = v
			end
		end
		return out
	end

	-- Feuilles v1.3 perdues : la valeur du serveur de lancement n'est ni celle de la même séance sur
	-- un serveur v1.3 (référence : gains hors ligne, jour, croissance…), ni celle de la sauvegarde de
	-- départ (une tenue v2.0 portée que la v1.3 retirait est gardée par la v2, lot A4 A4-14)
	local function lostAgainst(ref, orig, after)
		local lost = {}
		for path, v in ref do
			if after[path] ~= v and after[path] ~= orig[path] then
				table.insert(lost, path .. " : " .. tostring(v) .. " → " .. tostring(after[path]))
			end
		end
		table.sort(lost)
		return lost
	end

	-- Une séance sur un serveur du préréglage donné : sauvegarde de départ (référence v1.3)
	local function sessionOn(preset, seed, userId)
		local shared = newStore()
		Chaos.seed(shared, userId, seed)
		local w = server(shared, "REF", preset)
		local p = Bots.join(userId)
		expect(w.DS.isLoaded(p)).toBe(true)
		local writes = #shared.writes
		Bots.leave(p)
		expect(waitUntil(function()
			local raw = shared.data["player_" .. userId]
			return #shared.writes > writes and raw ~= nil and raw.lock == nil
		end)).toBe(true)
		local saved = deepCopy(Chaos.record(shared, userId))
		clean(w, shared)
		disposeAll()
		return saved
	end

	-- Cycle complet : chargé sur A (migration), sauvegardé, rechargé sur B, sauvegardé ; rend les
	-- étapes pour les attentes propres à chaque forme
	local function cycle(seed, userId, opts)
		opts = opts or {}
		local shared = newStore()
		if seed ~= nil then
			Chaos.seed(shared, userId, seed)
		end
		local a = server(shared, "A")
		expect(a.Schema.VERSION).toBe(2)
		local p = Bots.join(userId)
		expect(a.DS.isLoaded(p)).toBe(true)
		local first = a.DS.get(p)
		local loaded = deepCopy(first)
		expect({ step = "chargé", version = first.version }).toEqual({ step = "chargé", version = 2 })
		expect({ step = "chargé", bad = a.Invariants.profile(first) }).toEqual({ step = "chargé", bad = {} })
		local firstRepairs = a.repaired
		Bots.leave(p)
		expect(waitUntil(function()
			local d = Chaos.record(shared, userId)
			return d ~= nil and d.version == 2 and #shared.writes > 0
		end)).toBe(true)
		-- départ écrit, verrou rendu
		expect(waitUntil(function()
			local raw = shared.data["player_" .. userId]
			return raw ~= nil and raw.lock == nil
		end)).toBe(true)
		local saved1 = deepCopy(Chaos.record(shared, userId))
		expect({ step = "sauvegardé", bad = a.Invariants.profile(saved1) }).toEqual({
			step = "sauvegardé",
			bad = {},
		})
		expect((Chaos.check(saved1))).toBe(true)
		clean(a, shared, opts.allowed)

		-- deuxième serveur : la v2 relue telle quelle
		local b = server(shared, "B")
		local pb = Bots.join(userId)
		expect(b.DS.isLoaded(pb)).toBe(true)
		local second = deepCopy(b.DS.get(pb))
		expect({ step = "rechargé", repairs = b.repaired }).toEqual({ step = "rechargé", repairs = {} })
		-- le JSON sauvegardé est ce que le serveur suivant charge (seules les écritures de séance
		-- diffèrent, et seulement si le premier départ les a changées)
		local changed = {}
		for _, path in diff(saved1, second) do
			if not sessionPath(path) then
				table.insert(changed, path)
			end
		end
		expect({ step = "rechargé", changed = changed }).toEqual({ step = "rechargé", changed = {} })
		expect(second.confetti).toBe(saved1.confetti)
		expect(second.confettiTotal).toBe(saved1.confettiTotal)
		local writesBefore = #shared.writes
		Bots.leave(pb)
		expect(waitUntil(function()
			local raw = shared.data["player_" .. userId]
			return #shared.writes > writesBefore and raw ~= nil and raw.lock == nil
		end)).toBe(true)
		local saved2 = deepCopy(Chaos.record(shared, userId))
		-- deuxième sauvegarde = la première, sauf les écritures de la séance (une séance de plus)
		local changed2 = {}
		for _, path in diff(saved1, saved2) do
			if not sessionPath(path) then
				table.insert(changed2, path)
			end
		end
		expect({ step = "deuxième départ", changed = changed2 }).toEqual({
			step = "deuxième départ",
			changed = {},
		})
		expect(saved2.stats.sessions).toBe(saved1.stats.sessions + 1)
		expect(saved2.version).toBe(2)
		clean(b, shared, opts.allowed)
		disposeAll()
		return { loaded = loaded, saved = saved1, second = second, firstRepairs = firstRepairs }
	end

	-- ---------------------------------------------------------------------------------------------
	describe("Migration_I › profils v1.3 sur le serveur de lancement (SchemaV2 ouvert)", function()
		it("joueur neuf (aucune sauvegarde) : profil v2 par défaut, sauvegardé, relu identique", function()
			disposeAll()
			local r = cycle(nil, 401)
			expect(r.saved.version).toBe(2)
			expect({ r.saved.R, r.saved.bestR, r.saved.confetti, r.saved.ascendDay }).toEqual({ 0, 0, 0, 0 })
			expect(r.saved.onboarding.welcomeV2Pending).toBe(false)
		end)

		it(
			"v1.json : migré une fois (114 + 25 Confettis, Enclos 12 → 14), chaque valeur v1.3 gardée, relu identique",
			function()
				disposeAll()
				local v1 = readJson("v1.json")
				local before = v1Leaves(v1)
				local r = cycle(deepCopy(v1), 402)
				local s = r.saved
				expect({ s.version, s.R, s.bestR, s.ascend, s.confetti, s.confettiTotal, s.tiles.pens }).toEqual({
					2,
					12,
					12,
					0,
					139,
					139,
					14,
				})
				-- 114 = Σ (3 + min(k, 20)) pour k = 1 … 12 ; + 25 : une place offerte sur une dalle pleine
				expect(SchemaV1.confettiCatchUp(12)).toBe(114)
				expect({ s.unlocksSeen, s.ascendDay, s.memoryR }).toEqual({ 12, 0, 0 })
				expect(s.onboarding.welcomeV2Pending).toBe(true)
				-- chaque valeur v1.3 survit : v1.json est d'un autre jour (gains hors ligne, objectifs du
				-- jour, plafonds remis à zéro…) ; la même séance sur un serveur v1.3 donne la référence, et
				-- le serveur de lancement doit garder chaque feuille v1 qu'elle garde
				disposeAll()
				local ref = v1Leaves(sessionOn("v13", deepCopy(v1), 402))
				expect(ref["R"]).toBe(12)
				local after = leaves(s, "")
				expect(lostAgainst(ref, before, after)).toEqual({})
				-- et chaque feuille de la sauvegarde de départ que la v1.3 garde existe encore (rien d'effacé)
				for path in before do
					if ref[path] ~= nil then
						expect({ path = path, kept = after[path] ~= nil }).toEqual({
							path = path,
							kept = true,
						})
					end
				end
			end
		)

		it(
			"vétéran (R 24, Squishydex plein, tous les cosmétiques, pass, réglages, records, 1e30 pièces) : rien perdu, migré une fois, relu identique",
			function()
				disposeAll()
				local v = veteran()
				local before = v1Leaves(v)
				local r = cycle(deepCopy(v), 403)
				local s = r.saved
				expect({ step = "réparé au 1er chargement", repairs = r.firstRepairs }).toEqual({
					step = "réparé au 1er chargement",
					repairs = {},
				})
				-- pièces, squishies (uid, espèce, taille, mutation, tenue), cosmétiques, records, Squishydex,
				-- objectifs, pass, reçus, réglages : chaque feuille v1.3
				disposeAll()
				local ref = v1Leaves(sessionOn("v13", deepCopy(v), 403))
				local after = leaves(s, "")
				expect(lostAgainst(ref, before, after)).toEqual({})
				for path in before do
					if ref[path] ~= nil then
						expect({ path = path, kept = after[path] ~= nil }).toEqual({
							path = path,
							kept = true,
						})
					end
				end
				expect(s.coins).toBe(1e30)
				expect(s.squishies[base36(7)].o).toBe(v.squishies[base36(7)].o)
				expect(s.cosmetics.saddle).toBe("royal")
				expect(s.passes.SaddlesTrails).toBe(true)
				expect(s.receipts).toEqual({ "achat-1", "achat-2", "achat-3" })
				-- migration exacte (Schema.MIGRATION_V2) : R 24, Enclos plein (14) → 4 places offertes en
				-- Confettis (+25 chacune), décorations construites 18
				local want = SchemaV1.confettiCatchUp(24) + 4 * SchemaV1.MIGRATION_V2.FullPenBonus
				expect({ s.bestR, s.confetti, s.confettiTotal, s.tiles.pens, s.unlocksSeen }).toEqual({
					24,
					want,
					want,
					14,
					24,
				})
				expect(s.stats.upgradesBought).toBe(12 + 18 + 14 + 1)
				for k = 1, 18 do
					expect(s.decorBuilds[k]).toBe(1)
				end
			end
		)

		it(
			"profils partiels ou abîmés (tables absentes, mauvais types, NaN, nombres énormes, clés inconnues, champs v2 périmés) : réparés et migrés au 1er chargement, rien à réparer au 2e",
			function()
				for name, d in partials() do
					disposeAll()
					local r = cycle(d, 410 + #name)
					expect({ name = name, version = r.saved.version }).toEqual({ name = name, version = 2 })
					if name == "unknownKeys" then
						-- les clés inconnues sont gardées (on n'efface jamais un champ)
						expect(r.saved.unknownKey).toEqual({ nested = true, n = 3 })
						expect(r.saved.legacyGold).toBe(77)
						expect(r.saved.tiles.legacyPad).toBe(9)
						expect(r.saved.confetti).toBe(SchemaV1.confettiCatchUp(3))
					elseif name == "staleV2" then
						-- les champs v2 d'un profil v1 repartent de leur valeur migrée
						expect({ r.saved.bestR, r.saved.confetti, r.saved.ascendDay, r.saved.tiles.star }).toEqual({
							5,
							SchemaV1.confettiCatchUp(5) + 0,
							0,
							0,
						})
					elseif name == "missing" then
						expect(r.saved.R).toBe(7)
						expect(r.saved.bestR).toBe(7)
						expect(type(r.saved.dex)).toBe("table")
					end
				end
			end
		)

		it(
			"sauvegarde-témoin v0 et profil abîmé de DataChaos : migrés en v2, réparés une seule fois, relus identiques",
			function()
				disposeAll()
				local r0 = cycle(readJson("v0.json"), 420)
				expect(r0.saved.version).toBe(2)
				expect(r0.saved.coins).toBe(1234)
				expect(r0.saved.passes.VIPStar).toBe(true)
				disposeAll()
				local rb = cycle(chaosBroken(), 421)
				expect(#rb.firstRepairs > 0).toBe(true)
				expect(rb.saved.nextUid).toBe(3)
				disposeAll()
			end
		)
	end)

	describe("Migration_I › profils d'un schéma plus récent (règle D3)", function()
		local function refused(seed, userId, preset, version)
			T.expectWarning("écrit par un schéma plus récent que v" .. version)
			disposeAll()
			local shared = newStore()
			Chaos.seed(shared, userId, seed)
			local before = deepCopy(shared.data["player_" .. userId])
			local writes = #shared.writes
			local w = server(shared, "OLD", preset)
			expect(w.Schema.VERSION).toBe(version)
			local p = Bots.join(userId, { wait = false })
			expect(waitUntil(function()
				return #w.h.log.kicks == 1
			end)).toBe(true)
			expect(w.DS.get(p)).toBeNil()
			expect(w.DS.saveNow(p)).toBe(false)
			Bots.leave(p)
			w.h:settle(3)
			-- rien d'écrit : ni données ni verrou
			expect(#shared.writes).toBe(writes)
			expect(shared.data["player_" .. userId]).toEqual(before)
			expect(shared.data["player_" .. userId].lock).toBeNil()
			clean(w, shared, { "schéma plus récent" })
			disposeAll()
		end

		it(
			"profil v2 (v1.json migré) sur un serveur v1.3 (SchemaV2 coupé) : refusé, rien d'écrit",
			function()
				local Tables = probe:require("ReplicatedStorage.Shared.Util.Tables")
				local v2 = SchemaV1.migrate(readJson("v1.json"), 1, 2)
				Tables.reconcile(v2, SchemaV1.defaultsFor(2))
				refused(v2, 430, "v13", 1)
			end
		)

		it("profil v3 (inconnu de ce code) sur le serveur de lancement : refusé, rien d'écrit", function()
			local Tables = probe:require("ReplicatedStorage.Shared.Util.Tables")
			local v3 = SchemaV1.migrate(readJson("v1.json"), 1, 2)
			Tables.reconcile(v3, SchemaV1.defaultsFor(2))
			v3.version = 3
			v3.futureField = { a = 1 }
			refused(v3, 431, nil, 2)
		end)
	end)
end
