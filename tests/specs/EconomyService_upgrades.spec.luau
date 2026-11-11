--!nocheck
-- EconomyService_upgrades (lot A2, étape 2 ; docs/04 §27.5, §27.7, §27.10, §27.14 ; GDD v2.0 §4.6,
-- §4.26, §10.8 règles 6, 12, 13) : achats de l'écran Améliorations et Confettis côté serveur.
--   * interrupteurs coupés : BuyUpgrade ne fait rien (aucune réponse, aucune mutation), BuyTile et les
--     patchs de la v1.3 inchangés ;
--   * chaque mode (×1, ×10, Max) : somme EXACTE UpgradeMath (niveau 0, 1, maximum, plafonds), un seul
--     bloc, refus « périmé » muet (UpgradeResult sans raison, compté UpgradeStale), refus avec leur
--     raison (locked, maxed, loopCap, coins, confetti, busy), modes hors de { 0, 1, 10 } refusés AVANT
--     UpgradeMath.plan ;
--   * addConfetti : seul écrivain des gains, bornes, sources, plafonds ; buyUpgrade : seul puits ;
--   * BuyTile = même chemin [UpgradesScreen] ; Tapis Étoilé par la dalle du Tapis (N21) [StarMat] ;
--   * instantané versionné (UpgradeResult et DataPatch de la même image : même version) ;
--   * Prestige.validateConfig au chargement et en direct ; contextes d'A1 (Gants, Monuments, Sac de
--     nuit) ; Grand Splorch d'un profil v2 : Record R jamais sous r.
-- Les interrupteurs v2.0 sont ouverts DANS le test (Features.set) ; SchemaV2 (figé) dans le harnais
-- avant le premier require du schéma (recette de DataChaos).
local Flags = require("../harness/Flags")
local Bots = require("../harness/Bots")
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."

	-- Harnais d'un serveur v2 : SchemaV2 ouvert avant que Data/Schema soit chargé
	-- serveur v2 parti de la « coupure d'urgence » (préréglage « cut » : SchemaV2 seul ouvert ; lot I,
	-- étape 2, D2 a, journal I-19) : chaque cas ouvre lui-même ses interrupteurs (Features.set) et
	-- Features.reset() revient à « tout coupé » ; le chemin du lancement est couvert par Boot et Soak
	local HarnessV2 = Flags.harness(Harness, "cut")

	-- interrupteurs de l'étape (lot A2, achats) ; Helpers et DecoPerso ouvrent l'École, Plume et la
	-- ligne decoShop de l'Atelier
	local ALL = { "UpgradesScreen", "Confetti", "Workshop", "StarMat", "Gloves", "Monuments", "RecordR" }
	local EVERY = {
		"UpgradesScreen",
		"Confetti",
		"Workshop",
		"StarMat",
		"Gloves",
		"Monuments",
		"RecordR",
		"Helpers",
		"DecoPerso",
	}

	local function rec(extra)
		local r = {
			s = 1,
			m = 0,
			st = 1,
			z = 1000,
			zg = 0,
			bf = 0,
			lk = false,
			o = "",
			at = "pen",
			b = 100,
			gd = 0,
		}
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	-- opts : v1 (serveur v1), flags (liste ouverte, défaut ALL), profile(d) (profil sauvegardé)
	local function boot(opts)
		opts = opts or {}
		local caught = {}
		-- opts.v1 : serveur de la v1.3 (préréglage « v13 », tests/harness/Flags, lot I D2 a) ; sinon la
		-- configuration livrée, SchemaV2 ouvert (chemin du lancement)
		local w = Bots.boot(if opts.v1 then Flags.harness(Harness, "v13") else HarnessV2, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				w.F = w.h:require(L .. "Config.Features")
				for _, key in opts.flags or ALL do
					assert(w.F.set(key, true), key)
				end
				local d = Bots.profile(w, {
					onboarding = { step = 11, done = true, demoDone = true },
					squishies = {
						["1"] = rec({ bf = 1 }),
						["2"] = rec({ s = 5, z = 400 }),
						["3"] = rec({ s = 9, z = 50 }),
					},
					nextUid = 4,
				})
				d.tiles.seen = 15
				for _, s in { 1, 5, 9 } do
					d.trophies[s] = 1e5
				end
				d.coins = 1e14
				if not opts.v1 then
					d.R = 6
					d.bestR = 24
					d.confetti = 100000
					d.confettiTotal = 100000
					d.unlocksSeen = 24
				end
				if opts.profile then
					opts.profile(d)
				end
				Bots.saveProfile(w, 1, d)
			end,
		})
		w.caught = caught
		w.Economy = w.h:require(S .. "EconomyService")
		w.Ranch = w.h:require(S .. "RanchService")
		w.Squishy = w.h:require(S .. "SquishyService")
		w.UM = w.h:require(L .. "Logic.UpgradeMath")
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.Formulas = w.h:require(L .. "Logic.Formulas")
		w.Balance = w.h:require(L .. "Config.Balance")
		w.Upgrades = w.h:require(L .. "Config.Upgrades")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
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

	local function deepEqual(a, b)
		if a == b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return a ~= a and b ~= b
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	-- Premier écart entre deux profils (chemin), nil s'ils sont égaux
	local function diffPath(a, b, path)
		path = path or "profil"
		if type(a) ~= "table" or type(b) ~= "table" then
			if a == b or (a ~= a and b ~= b) then
				return nil
			end
			return path .. " : " .. tostring(a) .. " → " .. tostring(b)
		end
		for k, v in a do
			local d = diffPath(v, b[k], path .. "." .. tostring(k))
			if d then
				return d
			end
		end
		for k, v in b do
			if a[k] == nil then
				return path .. "." .. tostring(k) .. " : nil → " .. tostring(v)
			end
		end
		return nil
	end

	-- Profil sans les champs que le règlement fait bouger tout seul (Pot, croissance cumulée)
	local function stable(data)
		local copy = deepCopy(data)
		copy.pot = nil
		copy.growth = nil
		return copy
	end

	local function price(w, data, id, level)
		return w.UM.price(id, level, w.Prestige.r(data), w.Prestige.ascend(data), w.Prestige.bestR(data))
	end

	local function bulk(w, data, id, from, n)
		local _, total =
			w.UM.bulk(id, from, n, w.Prestige.r(data), w.Prestige.ascend(data), w.Prestige.bestR(data))
		return total
	end

	local function results(w, p)
		local out = {}
		for _, args in w.h:sentTo(p, "UpgradeResult") do
			table.insert(out, args[1])
		end
		return out
	end

	local function patchesWithSnapshot(w, p)
		local out = {}
		for _, args in w.h:sentTo(p, "DataPatch") do
			if type(args[1]) == "table" and args[1].upgradeSnapshot ~= nil then
				table.insert(out, args[1].upgradeSnapshot)
			end
		end
		return out
	end

	local function setLevel(w, data, id, level)
		local def = w.Upgrades.ById[id]
		if def then
			local field = string.match(def.profileKey, "^tiles%.(%w+)$")
			data.tiles[field] = if id == "cozyBed" then level >= 1 else level
			return
		end
		local index = w.Upgrades.WorkshopIndex[id]
		if index then
			data.atelier[index] = level
			return
		end
		error("setLevel : " .. id)
	end

	describe("EconomyService_upgrades › interrupteurs coupés (jeu de base)", function()
		it(
			"serveur v1, tout coupé : BuyUpgrade sans effet ni réponse, BuyTile de la v1.3, aucun instantané dans les patchs",
			function()
				local w = boot({ v1 = true, flags = {} })
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.Economy.settle(p)
				local before = stable(data)
				for _, args in { { "snack", 1, 0 }, { "gloves", 0, 0 }, { "decor", 10, 0 } } do
					w.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, table.unpack(args))
				end
				w.h:settle(3)
				expect(deepEqual(stable(data), before)).toBe(true)
				expect(w.Economy.buyUpgrade(p, "snack", 1, 0)).toBeNil()
				expect(#results(w, p)).toBe(0)
				-- BuyTile : prix de la v1.3 (Formulas.tileCost), aucune réponse UpgradeResult
				local cost = w.Formulas.tileCost("snack", 0, data.R)
				w.h:fireServer("ReplicatedStorage.Remotes.BuyTile", p, "snack")
				w.h:settle(3)
				expect(data.tiles.snack).toBe(1)
				expect(data.coins).toBe(1e14 - cost)
				expect(#results(w, p)).toBe(0)
				expect(#patchesWithSnapshot(w, p)).toBe(0)
				-- l'instantané d'arrivée ne porte rien de nouveau
				for _, args in w.h:sentTo(p, "DataSnapshot") do
					expect(args[1].upgradeSnapshot).toBeNil()
				end
				expect(w.Economy.addConfetti(p, 10, "splorch")).toBe(0)
				expect({ w.Economy.pressBonus(p) }).toEqual({})
				expect(w.Economy.incomeCtx(p).monuments).toBeNil()
				clean(w)
			end
		)

		it(
			"serveur v2, tout coupé : profil v2 intouché par BuyUpgrade et addConfetti ; aucun attribut v2 sur le ranch",
			function()
				local w = boot({ flags = {} })
				local p = Bots.join(1)
				local data = w.DS.get(p)
				expect(data.version).toBe(2)
				w.Economy.settle(p)
				local before = stable(data)
				w.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "gloves", 1, 0)
				w.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "gift", 1, 0)
				w.h:settle(3)
				expect(w.Economy.addConfetti(p, 10, "splorch")).toBe(0)
				expect(deepEqual(stable(data), before)).toBe(true)
				expect(#results(w, p)).toBe(0)
				expect(#patchesWithSnapshot(w, p)).toBe(0)
				local model = w.h:require(S .. "WorldService").ranchModel(w.Ranch.slotOf(p))
				for _, name in { "BestR", "SplorchReady", "Monuments", "TapisTier", "GloveTier", "ApronTier" } do
					expect({ name = name, v = model:GetAttribute(name) }).toEqual({ name = name, v = nil })
				end
				clean(w)
			end
		)
	end)

	describe("EconomyService_upgrades › sommes exactes", function()
		it(
			"×1 : somme exacte UpgradeMath au niveau 0, au niveau 1 et au dernier niveau, puis « maximum » ; chaque famille et chaque ligne",
			function()
				local w = boot({ flags = EVERY })
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local ids = {
					"snack",
					"decor",
					"pens",
					"gloves",
					"school",
					"monument",
					"gift",
					"startMat",
					"magnet",
					"superStreak",
					"keptDecor",
					"nightBag",
					"nightPot",
					"plume",
					"decoShop",
				}
				for _, id in ids do
					local max = w.UM.maxLevel(id)
					for _, from in { 0, 1, max - 1 } do
						if from >= 0 and from < max then
							setLevel(w, data, id, from)
							data.coins = 1e14
							data.confetti = 100000
							local currency = w.UM.currency(id)
							local cashKey = if currency == "coins" then "coins" else "confetti"
							local before = data[cashKey]
							local expected = price(w, data, id, from)
							local r = w.Economy.buyUpgrade(p, id, 1, from)
							expect({ id = id, from = from, to = r.to, spent = r.spent, reason = r.reason }).toEqual({
								id = id,
								from = from,
								to = from + 1,
								spent = expected,
								reason = nil,
							})
							expect({ id = id, debit = before - data[cashKey] }).toEqual({
								id = id,
								debit = expected,
							})
							expect(w.UM.level(id, data)).toBe(from + 1)
						end
					end
					-- au maximum : refus « maximum », rien de changé
					local snap = stable(data)
					local r = w.Economy.buyUpgrade(p, id, 1, max)
					expect({ id = id, reason = r.reason, spent = r.spent }).toEqual({
						id = id,
						reason = "upgrades.refused.maxed",
						spent = 0,
					})
					expect(deepEqual(stable(data), snap)).toBe(true)
				end
				-- « Pour le plaisir » : identifiant canonique ou nu, objets dans l'ordre (bits), puis maximum
				local before = data.confetti
				local r = w.Economy.buyUpgrade(p, "palettes", 1, 0)
				expect({ r.id, r.to, r.spent }).toEqual({ "fun.palettes", 1, 20 })
				r = w.Economy.buyUpgrade(p, "fun.palettes", 10, 1)
				expect({ r.to, r.spent }).toEqual({ 6, 100 })
				expect(before - data.confetti).toBe(120)
				expect(w.UM.level("fun.palettes", data)).toBe(6)
				expect(w.Economy.buyUpgrade(p, "fun.palettes", 1, 6).reason).toBe("upgrades.refused.maxed")
				r = w.Economy.buyUpgrade(p, "fun.title", 1, 0)
				expect({ r.to, r.spent }).toEqual({ 1, 100 })
				clean(w)
			end
		)

		it(
			"×10 et Max : somme exacte niveau par niveau (UpgradeMath.bulk), partielle quand l'argent manque, bornée par le plafond et BulkMax",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				-- ×10 avec juste de quoi payer 7 niveaux des Gants
				local seven = bulk(w, data, "gloves", 0, 7)
				local eighth = price(w, data, "gloves", 7)
				data.coins = seven + eighth - 1
				local r = w.Economy.buyUpgrade(p, "gloves", 10, 0)
				expect({ r.from, r.to, r.spent, r.reason }).toEqual({ 0, 7, seven, nil })
				expect(data.coins).toBe(eighth - 1)
				expect(data.tiles.gloves).toBe(7)
				-- Max : jusqu'au plafond de la ligne (40 niveaux = BulkMax)
				data.coins = 1e15
				data.tiles.gloves = 0
				local all = bulk(w, data, "gloves", 0, 40)
				r = w.Economy.buyUpgrade(p, "gloves", 0, 0)
				expect({ r.to, r.spent }).toEqual({ 40, all })
				expect(data.coins).toBe(1e15 - all)
				expect(w.Balance.Upgrades.BulkMax).toBe(40)
				-- Max des décorations à partir de 5 : 13 niveaux, somme niveau par niveau
				data.coins = 1e14
				data.tiles.decor = 5
				local thirteen = bulk(w, data, "decor", 5, 13)
				local sum = 0
				for lv = 5, 17 do
					sum += price(w, data, "decor", lv)
				end
				expect(thirteen).toBe(sum)
				r = w.Economy.buyUpgrade(p, "decor", 0, 5)
				expect({ r.to, r.spent }).toEqual({ 18, sum })
				-- Monuments : plafond du Record R (bestR 24 → 10) ; Record R 9 → 2 ouverts
				data.tiles.monuments = 0
				data.bestR = 9
				r = w.Economy.buyUpgrade(p, "monument", 10, 0)
				expect(r.to).toBe(2)
				expect(r.spent).toBe(bulk(w, data, "monument", 0, 2))
				expect(w.Economy.buyUpgrade(p, "monument", 1, 2).reason).toBe("upgrades.refused.locked")
				-- Confettis : Sac de nuit 6 + 12 payables sur 3 niveaux (Max) → 2 niveaux, 18 Confettis
				data.confetti = 18 + 19
				data.confettiTotal = 100000
				r = w.Economy.buyUpgrade(p, "nightBag", 0, 0)
				expect({ r.to, r.spent, r.currency }).toEqual({ 2, 18, "confetti" })
				expect(data.confetti).toBe(19)
				expect(data.confettiTotal).toBe(100000)
				clean(w)
			end
		)

		it(
			"un seul bloc : une monnaie débitée une fois, un UpgradeBought (avant, après), un TileBought par niveau ; champ illisible : rien n'est écrit",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local bought, tiles, confetti = {}, {}, {}
				w.Signals.UpgradeBought:Connect(function(player, id, from, to, currency)
					table.insert(bought, { id, from, to, currency })
				end)
				w.Signals.TileBought:Connect(function(player, tile, level)
					table.insert(tiles, { tile, level })
				end)
				w.Signals.ConfettiChanged:Connect(function(player, delta, source)
					table.insert(confetti, { delta, source })
				end)
				local sets = 0
				local original = w.DS.set
				w.DS.set = function(player, key, value)
					if player == p and (key == "coins" or key == "confetti") then
						sets += 1
					end
					return original(player, key, value)
				end
				local r = w.Economy.buyUpgrade(p, "snack", 10, 0)
				w.h:settle(2)
				expect(r.to).toBe(10)
				expect(bought).toEqual({ { "snack", 0, 10, "coins" } })
				expect(#tiles).toBe(10)
				expect(tiles[1]).toEqual({ "snack", 1 })
				expect(tiles[10]).toEqual({ "snack", 10 })
				expect(sets).toBe(1)
				-- Confettis : un débit, un ConfettiChanged négatif « spend »
				r = w.Economy.buyUpgrade(p, "magnet", 0, 0)
				w.h:settle(2)
				expect({ r.to, r.spent }).toEqual({ 3, 26 })
				expect(confetti).toEqual({ { -26, "spend" } })
				expect(sets).toBe(2)
				-- Atelier illisible pendant la session : refus, AUCUNE écriture (ni Confettis, ni niveaux)
				w.DS.set = original
				data.atelier = nil
				local before = stable(data)
				r = w.Economy.buyUpgrade(p, "gift", 1, 0)
				expect(r.reason).toBe("upgrades.refused.confetti")
				expect(deepEqual(stable(data), before)).toBe(true)
				clean(w)
			end
		)
	end)

	describe("EconomyService_upgrades › périmé, refus, modes", function()
		it(
			"périmé (niveau attendu ≠ niveau actuel) : UpgradeResult muet (raison nil, from = to, rien de dépensé), compté UpgradeStale, aucun Feedback",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				data.tiles.gloves = 3
				local before = stable(data)
				local feedback = #w.h:sentTo(p, "Feedback")
				for _, expected in { 0, 2, 4, 64 } do
					local r = w.Economy.buyUpgrade(p, "gloves", 1, expected)
					expect({ r.from, r.to, r.spent, r.reason, r.id }).toEqual({ 3, 3, 0, nil, "gloves" })
				end
				expect(w.Economy.counters().UpgradeStale).toBe(4)
				expect(deepEqual(stable(data), before)).toBe(true)
				expect(#w.h:sentTo(p, "Feedback")).toBe(feedback)
				-- chaque réponse est envoyée (le client sait qu'il n'y a rien à attendre)
				expect(#results(w, p)).toBe(4)
				clean(w)
			end
		)

		it(
			"deux appuis rapides (même niveau attendu, même image) : exactement un achat ; le second est périmé",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local coins = data.coins
				local remote = w.h:find("ReplicatedStorage.Remotes.BuyUpgrade")
				remote.OnServerEvent:Fire(p, "gloves", 1, 0)
				remote.OnServerEvent:Fire(p, "gloves", 1, 0)
				w.h:settle(3)
				expect(data.tiles.gloves).toBe(1)
				expect(data.coins).toBe(coins - price(w, { R = 6, bestR = 24 }, "gloves", 0))
				local list = results(w, p)
				expect(#list).toBe(2)
				expect({ list[1].to, list[1].reason }).toEqual({ 1, nil })
				expect({ list[2].from, list[2].to, list[2].spent }).toEqual({ 1, 1, 0 })
				expect(w.Economy.counters().UpgradeStale).toBe(1)
				clean(w)
			end
		)

		it(
			"refus avec leur raison, sans aucune mutation : verrouillé, interrupteur de la famille coupé, plafond de la boucle, pièces, Confettis, occupé",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local function refused(id, mode, expected, reason)
					w.Economy.settle(p) -- règlement (Pot, record de taille) fait avant : seul l'achat compte
					local before = stable(data)
					local r = w.Economy.buyUpgrade(p, id, mode, expected)
					expect({ id = id, reason = r.reason, to = r.to, spent = r.spent }).toEqual({
						id = id,
						reason = reason,
						to = expected,
						spent = 0,
					})
					expect({ id = id, diff = diffPath(before, stable(data)) }).toEqual({ id = id })
				end
				-- Tapis Étoilé : Tapis 12 pas encore acheté → fermé ; acheté, r = 5 → niveau suivant dans une
				-- boucle plus haute
				refused("star", 1, 0, "upgrades.refused.locked")
				data.tiles.snack = 12
				data.R = 5
				refused("star", 1, 0, "upgrades.refused.loopCap")
				-- École : interrupteur Helpers coupé ; Plume (Record R 12) aussi
				refused("school", 1, 0, "upgrades.refused.locked")
				refused("plume", 1, 0, "upgrades.refused.locked")
				-- Gants : Record R 0 (profil neuf)
				data.R = 0
				data.bestR = 0
				refused("gloves", 1, 0, "upgrades.refused.locked")
				data.R = 6
				data.bestR = 24
				-- interrupteur coupé en direct
				w.F.set("Gloves", false)
				refused("gloves", 1, 0, "upgrades.refused.locked")
				w.F.set("Gloves", true)
				-- pièces, Confettis
				data.coins = 0
				refused("gloves", 1, 0, "upgrades.refused.coins")
				data.confetti = 2
				refused("gift", 0, 0, "upgrades.refused.confetti")
				data.coins = 1e14
				data.confetti = 1000
				-- un prestige en cours (sonde de SplorchService)
				w.Economy.setBusyProbe(function(player)
					return player == p
				end)
				refused("gloves", 1, 0, "upgrades.refused.busy")
				refused("gift", 1, 0, "upgrades.refused.busy")
				-- une sonde en erreur : refus sûr (et l'erreur comptée par Diagnostics)
				w.Economy.setBusyProbe(function()
					error("sonde cassée")
				end)
				refused("gloves", 1, 0, "upgrades.refused.busy")
				expect(#w.caught).toBe(1)
				table.clear(w.caught)
				w.Economy.setBusyProbe(function()
					return false
				end)
				expect(w.Economy.buyUpgrade(p, "gloves", 1, 0).to).toBe(1)
				clean(w)
			end
		)

		it(
			"modes hors de { 0, 1, 10 } refusés AVANT UpgradeMath.plan (qui accepte 0-40) : aucune réponse, aucune mutation",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local planned = 0
				local original = w.UM.plan
				w.UM.plan = function(...)
					planned += 1
					return original(...)
				end
				local before = stable(data)
				for _, mode in
					{
						2,
						3,
						5,
						9,
						11,
						20,
						40,
						-1,
						0.5,
						1.5,
						0 / 0,
						math.huge,
						-math.huge,
						1e9,
						2 ^ 53,
						"1",
						true,
					}
				do
					expect(w.Economy.buyUpgrade(p, "gloves", mode, 0)).toBeNil()
					w.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, "gloves", mode, 0)
					w.RateLimit.clear(p)
				end
				w.h:settle(2)
				expect(planned).toBe(0)
				expect(#results(w, p)).toBe(0)
				expect(deepEqual(stable(data), before)).toBe(true)
				-- les trois modes permis passent par plan
				for _, mode in { 1, 10, 0 } do
					w.Economy.buyUpgrade(p, "decor", mode, w.UM.level("decor", data))
				end
				expect(planned).toBe(3)
				clean(w)
			end
		)

		it(
			"profil non chargé, joueur parti, sauvegarde de fin commencée : refus propre (rien d'écrit)",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				-- sauvegarde de fermeture du serveur en cours (BindToClose) : « occupé », rien d'écrit
				local coins = data.coins
				task.spawn(function()
					w.h:close()
				end)
				expect(w.DS.isClosing(p)).toBe(true)
				local r = w.Economy.buyUpgrade(p, "gloves", 1, 0)
				expect(r.reason).toBe("upgrades.refused.busy")
				expect(data.coins).toBe(coins)
				expect(data.tiles.gloves).toBe(0)
				w.h:settle(5)
				-- joueur parti : aucune réponse
				Bots.leave(p)
				w.h:settle(5)
				expect(w.Economy.buyUpgrade(p, "gloves", 1, 0)).toBeNil()
				-- jamais chargé (joueur que DataService n'a jamais vu)
				local q = w.h:_newPlayer({ userId = 99, name = "Ghost" })
				expect(w.Economy.buyUpgrade(q, "gloves", 1, 0)).toBeNil()
				expect(w.Economy.addConfetti(q, 5, "splorch")).toBe(0)
				clean(w)
			end
		)
	end)

	describe("EconomyService_upgrades › Confettis", function()
		it(
			"addConfetti : seul écrivain des gains, sources connues, entier, poche ≤ total ≤ 1e9 ; ConfettiChanged à chaque gain",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				data.confetti = 10
				data.confettiTotal = 50
				local changed = {}
				w.Signals.ConfettiChanged:Connect(function(player, delta, source)
					table.insert(changed, { delta, source })
				end)
				local sum = 0
				for i, source in
					{
						"splorch",
						"petit",
						"skipped",
						"ascend",
						"regain",
						"record",
						"fullPen",
						"track",
						"mastery",
					}
				do
					expect(w.Economy.addConfetti(p, i, source)).toBe(i)
					sum += i
				end
				expect(w.Economy.addConfetti(p, 2.9, "track")).toBe(2)
				sum += 2
				expect({ data.confetti, data.confettiTotal }).toEqual({ 10 + sum, 50 + sum })
				w.h:settle(2)
				expect(#changed).toBe(10)
				expect(changed[1]).toEqual({ 1, "splorch" })
				-- refus : montant illisible, négatif, nul ; source inconnue (dont le puits « spend »)
				local before = stable(data)
				for _, args in
					{
						{ 0, "splorch" },
						{ -5, "splorch" },
						{ 0 / 0, "splorch" },
						{ math.huge, "splorch" },
						{ "5", "splorch" },
						{ 5, "spend" },
						{ 5, "hack" },
						{ 5, nil },
					}
				do
					expect(w.Economy.addConfetti(p, args[1], args[2])).toBe(0)
				end
				expect(deepEqual(stable(data), before)).toBe(true)
				expect(w.Economy.counters().ConfettiRefused).toBe(8)
				-- plafond 1e9 du total (la poche ne le dépasse jamais)
				data.confettiTotal = 1e9 - 3
				expect(w.Economy.addConfetti(p, 10, "track")).toBe(3)
				expect(data.confettiTotal).toBe(1e9)
				expect(w.Economy.addConfetti(p, 10, "track")).toBe(0)
				expect(w.Economy.counters().ConfettiCapped).toBe(1)
				expect(data.confetti <= data.confettiTotal).toBe(true)
				-- interrupteur coupé : rien
				w.F.set("Confetti", false)
				data.confettiTotal = 100
				data.confetti = 50
				expect(w.Economy.addConfetti(p, 5, "track")).toBe(0)
				expect(data.confetti).toBe(50)
				clean(w)
			end
		)

		it(
			"aucun module du serveur n'écrit les Confettis hors d'EconomyService (addConfetti, buyUpgrade)",
			function()
				local fs = require("@lune/fs")
				local function scan(dir)
					for _, entry in fs.readDir(dir) do
						local full = dir .. "/" .. entry
						if fs.isDir(full) then
							scan(full)
						elseif
							string.match(entry, "%.luau$")
							and full ~= "src/server/Services/EconomyService.luau"
						then
							local src = fs.readFile(full)
							for _, pattern in
								{
									"%.confetti%s*=[^=]",
									"%.confettiTotal%s*=[^=]",
									'"confetti"%s*,',
									'"confettiTotal"%s*,',
								}
							do
								local found = string.find(src, pattern) ~= nil
								if
									full == "src/server/Data/Schema.luau"
									or full == "src/server/Data/ProfileRepair.luau"
								then
									found = false -- schéma (défauts, migration) et réparation au chargement
								end
								expect({ file = full, pattern = pattern, found = found }).toEqual({
									file = full,
									pattern = pattern,
									found = false,
								})
							end
						end
					end
				end
				scan("src/server")
			end
		)
	end)

	describe("EconomyService_upgrades › BuyTile, Tapis Étoilé, instantané", function()
		it(
			"BuyTile = même chemin [UpgradesScreen] : prix UpgradeMath, UpgradeResult, TileBought, célébration ; refus du panneau : Feedback et raison",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local tiles = {}
				w.Signals.TileBought:Connect(function(player, tile, level)
					table.insert(tiles, { tile, level })
				end)
				local expected = price(w, data, "decor", 0)
				w.h:fireServer("ReplicatedStorage.Remotes.BuyTile", p, "decor")
				w.h:settle(3)
				expect(data.tiles.decor).toBe(1)
				expect(data.coins).toBe(1e14 - expected)
				local list = results(w, p)
				expect(#list).toBe(1)
				expect({ list[1].id, list[1].from, list[1].to, list[1].spent }).toEqual({
					"decor",
					0,
					1,
					expected,
				})
				expect(tiles).toEqual({ { "decor", 1 } })
				expect(#Bots.celebrations(p, "tile")).toBe(1)
				-- refus faute de pièces (panneau) : Feedback de la v1.3 ET UpgradeResult avec la raison
				data.coins = 3
				w.RateLimit.clear(p)
				w.h:fireServer("ReplicatedStorage.Remotes.BuyTile", p, "decor")
				w.h:settle(3)
				expect(data.tiles.decor).toBe(1)
				expect(data.coins).toBe(3)
				local keys = Bots.feedbackKeys(p)
				expect(keys[#keys]).toBe("feedback.notEnoughCoins")
				list = results(w, p)
				expect(list[#list].reason).toBe("upgrades.refused.coins")
				clean(w)
			end
		)

		it(
			"Tapis Étoilé par la dalle du Tapis (N21) [StarMat] : niveau 13 acheté au-delà du Tapis 12 dans une boucle r = 6, puis dalle éteinte ; coupé : « niveau maximal »",
			function()
				local w = boot({
					profile = function(d)
						d.tiles.snack = 12
					end,
				})
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local PadRules = w.h:require("ServerScriptService.Server.Ranch.PadRules")
				expect(PadRules.visible(data, "snack")).toBe(true)
				expect({ PadRules.target(data, "snack") }).toEqual({ "star", 0 })
				local expected = price(w, data, "star", 0)
				expect(w.Economy.buyTile(p, "snack", "pad")).toBe(true)
				expect({ data.tiles.snack, data.tiles.star }).toEqual({ 12, 1 })
				expect(data.coins).toBe(1e14 - expected)
				local c = Bots.celebrations(p, "tile")
				expect({ c[#c].tile, c[#c].level }).toEqual({ "snack", 13 })
				-- plafond de la boucle (r = 6 : 1 niveau) : dalle éteinte
				expect(PadRules.visible(data, "snack")).toBe(false)
				expect(w.Economy.buyTile(p, "snack", "pad")).toBe(false)
				-- r = 10 : 8 niveaux ouverts
				data.R = 10
				expect(PadRules.visible(data, "snack")).toBe(true)
				-- interrupteur coupé : règle de la v1.3 (Tapis 12 = dalle éteinte, « niveau maximal »)
				w.F.set("StarMat", false)
				expect(PadRules.visible(data, "snack")).toBe(false)
				w.Economy.buyTile(p, "snack", "panel", true)
				local keys = Bots.feedbackKeys(p)
				expect(keys[#keys]).toBe("feedback.maxLevel")
				expect(data.tiles.star).toBe(1)
				clean(w)
			end
		)

		it(
			"Tapis Étoilé ouvert, écran coupé : les 4 dalles gardent le chemin et le prix de la v1.3 (Formulas.tileCost), aucune réponse UpgradeResult",
			function()
				local w = boot({ flags = { "StarMat" } })
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local cost = w.Formulas.tileCost("decor", 0, data.R)
				expect(w.Economy.buyTile(p, "decor", "panel", true)).toBe(true)
				expect(data.coins).toBe(1e14 - cost)
				expect(#results(w, p)).toBe(0)
				-- Tapis 12 : la dalle achète le Tapis Étoilé (UpgradeMath), toujours sans réponse
				data.tiles.snack = 12
				local star = price(w, data, "star", 0)
				local coins = data.coins
				expect(w.Economy.buyTile(p, "snack", "pad")).toBe(true)
				expect(data.tiles.star).toBe(1)
				expect(data.coins).toBe(coins - star)
				expect(#results(w, p)).toBe(0)
				clean(w)
			end
		)

		it(
			"instantané versionné : version + 1 à chaque contenu changé, jamais sinon ; UpgradeResult et DataPatch de la même image portent la même version",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.h:settle(3)
				-- arrivée : l'instantané d'arrivée le porte
				local arrival = w.h:sentTo(p, "DataSnapshot")
				expect(arrival[#arrival][1].upgradeSnapshot ~= nil).toBe(true)
				local s1 = w.Economy.snapshot(p)
				local s2 = w.Economy.snapshot(p)
				expect(s2.version).toBe(s1.version)
				local r = w.Economy.buyUpgrade(p, "gloves", 1, 0)
				expect(r.snapshot.version).toBe(s1.version + 1)
				expect(r.snapshot.levels.gloves).toBe(1)
				expect(r.snapshot.coins).toBe(math.floor(data.coins))
				w.h:settle(3)
				local patched = patchesWithSnapshot(w, p)
				expect(patched[#patched].version).toBe(r.snapshot.version)
				expect(patched[#patched].levels.gloves).toBe(1)
				-- patch d'une clé que l'instantané ne montre pas : pas d'instantané
				local n = #patchesWithSnapshot(w, p)
				w.DS.set(p, "fame", 7)
				w.h:settle(3)
				expect(#patchesWithSnapshot(w, p)).toBe(n)
				-- Confettis gagnés : nouvelle version, dans le patch
				w.Economy.addConfetti(p, 5, "track")
				w.h:settle(3)
				patched = patchesWithSnapshot(w, p)
				expect(patched[#patched].version).toBe(r.snapshot.version + 1)
				expect(patched[#patched].confetti).toBe(data.confetti)
				-- un plafond qui s'ouvre (interrupteur en direct) change le contenu
				local before = w.Economy.snapshot(p).version
				w.F.set("Gloves", false)
				local after = w.Economy.snapshot(p)
				expect(after.version).toBe(before + 1)
				expect(after.caps.gloves).toBe(0)
				clean(w)
			end
		)

		it(
			"profil v1 sur un serveur où les interrupteurs sont ouverts : aucune ligne v2.0 notée (plafond 0, refus)",
			function()
				local w = boot({ v1 = true })
				local p = Bots.join(1)
				local data = w.DS.get(p)
				expect(data.version).toBe(1)
				local snap = w.Economy.snapshot(p)
				for _, id in { "star", "gloves", "school", "monument", "gift", "nightBag", "fun.palettes" } do
					expect({ id = id, cap = snap.caps[id] }).toEqual({ id = id, cap = 0 })
				end
				local before = stable(data)
				expect(w.Economy.buyUpgrade(p, "gloves", 1, 0).reason).toBe("upgrades.refused.locked")
				expect(deepEqual(stable(data), before)).toBe(true)
				-- les 4 dalles de la v1.3 restent achetables par l'écran
				local r = w.Economy.buyUpgrade(p, "pens", 1, data.tiles.pens)
				expect(r.to).toBe(before.tiles.pens + 1)
				expect(w.Economy.addConfetti(p, 5, "track")).toBe(0)
				expect(data.confetti).toBeNil()
				clean(w)
			end
		)
	end)

	describe("EconomyService_upgrades › configuration, contextes d'A1, Grand Splorch v2", function()
		it(
			"Prestige.validateConfig au chargement et à chaque changement en direct : refus compté (ConfigRefused) ; configuration en vigueur refusée = achats « occupé »",
			function()
				local w = boot()
				local p = Bots.join(1)
				expect({ w.Economy.configOk() }).toEqual({ true })
				expect(w.Economy.counters().ConfigRefused).toBeNil()
				-- une configuration proposée en direct, invalide : refusée et comptée, l'actuelle reste
				local bad = deepCopy(w.Balance)
				bad.Ascend.GrowthMult = 0.5
				local ok, why = w.Economy.validateConfig(bad)
				expect({ ok, why }).toEqual({ false, "Ascend.GrowthMult" })
				expect(w.Economy.counters().ConfigRefused).toBe(1)
				expect({ w.Economy.configOk() }).toEqual({ true })
				-- la configuration en vigueur abîmée, puis un interrupteur changé en direct : revérifiée
				local saved = w.Balance.Ascend.GrowthMult
				w.Balance.Ascend.GrowthMult = 0.5
				w.F.set("Monuments", false)
				w.Economy.step(w.Clock.now())
				expect({ w.Economy.configOk() }).toEqual({ false, "Ascend.GrowthMult" })
				expect(w.Economy.counters().ConfigRefused).toBe(2)
				expect(w.Economy.buyUpgrade(p, "gloves", 1, 0).reason).toBe("upgrades.refused.busy")
				-- réparée, interrupteur rouvert : acceptée
				w.Balance.Ascend.GrowthMult = saved
				w.F.set("Monuments", true)
				w.Economy.step(w.Clock.now())
				expect({ w.Economy.configOk() }).toEqual({ true })
				expect(w.Economy.buyUpgrade(p, "gloves", 1, 0).to).toBe(1)
				clean(w)
			end
		)

		it(
			"contextes d'A1 ouverts : Gants et Super Série (pression), Monuments (revenu), Tapis Étoilé (croissance) ; coupés : valeurs de la v1.3",
			function()
				local w = boot({
					flags = {
						"UpgradesScreen",
						"Confetti",
						"Workshop",
						"StarMat",
						"Gloves",
						"Monuments",
						"RecordR",
					},
				})
				local p = Bots.join(1)
				local data = w.DS.get(p)
				data.tiles.gloves = 10
				data.atelier[w.Upgrades.WorkshopIndex.superStreak] = 2
				data.tiles.monuments = 3
				expect({ w.Economy.pressBonus(p) }).toEqual({ 10, 2 })
				w.Economy.refresh(p)
				expect(w.Economy.incomeCtx(p).monuments).toBe(3)
				-- pression : × (1 + 0,025 × 10), série jusqu'à 7
				expect(w.Formulas.pressReward(1000, false, 0, false, 10, 2)).toBe(
					math.floor(w.Formulas.pressReward(1000, false, 0, false) * 1.25)
				)
				expect(w.Formulas.streakMax(2)).toBe(w.Balance.Press.StreakMax + 2)
				-- Tapis Étoilé au-dessus du Tapis 12 : croissance plus forte
				data.tiles.snack = 12
				w.Economy.refresh(p)
				local g12 = w.Economy.gNoBoost(p)
				data.tiles.star = 1
				w.Economy.refresh(p)
				expect(w.Economy.gNoBoost(p) > g12).toBe(true)
				-- coupés en direct : contextes de la v1.3
				for _, key in { "Gloves", "Workshop", "Monuments", "StarMat" } do
					w.F.set(key, false)
				end
				w.Economy.refresh(p)
				expect({ w.Economy.pressBonus(p) }).toEqual({})
				expect(w.Economy.incomeCtx(p).monuments).toBeNil()
				expect(w.Economy.gNoBoost(p)).toBe(g12)
				clean(w)
			end
		)

		it(
			"vraie pression (SquishyService) : Gants × (1 + 0,025 × niveau) [Gloves] ; coupé : récompense de la v1.3",
			function()
				for _, case in
					{ { flags = ALL, gloves = 10 }, { flags = { "UpgradesScreen" }, gloves = nil } }
				do
					local w = boot({
						flags = case.flags,
						profile = function(d)
							d.tiles.gloves = 10
						end,
					})
					local p = Bots.join(1)
					local data = w.DS.get(p)
					local MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
					local QuestRules = w.h:require(L .. "Logic.QuestRules")
					local c = w.Squishy.placeOf(p, "1")
					MoveCheck.reset(p, w.h.globals.Vector3.new(c.X, 3, c.Z), w.Clock.now())
					local income = w.Economy.squishyIncome(p, "1")
					local kitty = QuestRules.familyEarned(data.dex, "kitty")
					local coins = data.coins
					w.h:fireServer("ReplicatedStorage.Remotes.Press", p, "1", w.Clock.now())
					w.h:settle(2)
					local presses = Bots.celebrations(p, "press")
					expect(#presses).toBe(1)
					local d = presses[1]
					local expected =
						w.Formulas.pressReward(income, d.perfect, d.streak, kitty, case.gloves, nil)
					expect(d.coins).toBe(expected)
					expect(data.coins).toBe(coins + expected)
					local v13 = w.Formulas.pressReward(income, d.perfect, d.streak, kitty)
					if case.gloves == nil then
						-- au bit près, la formule de la v1.3 (4 arguments)
						expect(d.coins).toBe(v13)
					else
						expect(math.abs(d.coins - v13 * 1.25) <= 1).toBe(true)
					end
					clean(w)
				end
			end
		)

		it(
			"hors ligne : Sac de nuit +1 h par niveau [Workshop] ; coupé : limite de la v1.3 (8 h)",
			function()
				for _, case in { { flags = ALL, hours = 10 }, { flags = { "UpgradesScreen" }, hours = 8 } } do
					local w = boot({
						flags = case.flags,
						profile = function(d)
							d.lastOnline = T0 - 20 * 3600
							d.atelier[6] = 2 -- Sac de nuit (WorkshopRows[6])
						end,
					})
					local p = Bots.join(1)
					w.h:settle(3)
					local back = Bots.celebrations(p, "return")
					expect(#back).toBe(1)
					expect(back[1].seconds).toBe(case.hours * 3600)
					clean(w)
				end
			end
		)

		it(
			"Grand Splorch d'un profil v2 : le Record R suit r dans le même bloc (jamais sous r), même RecordR coupé ; un Record R plus haut reste ; familles de la boucle à zéro",
			function()
				local w = boot({
					flags = {},
					profile = function(d)
						d.R = 12
						d.bestR = 12
					end,
				})
				local p = Bots.join(1)
				local data = w.DS.get(p)
				-- familles de la boucle (Tapis Étoilé, Gants, École) remises à zéro avec le Tapis ; Monuments
				-- et Enclos gardés
				data.tiles.snack = 12
				data.tiles.star = 2
				data.tiles.gloves = 9
				data.tiles.school = 4
				data.tiles.monuments = 3
				local pens = data.tiles.pens
				w.Economy.applySplorch(p)
				expect({ data.R, data.bestR }).toEqual({ 13, 13 })
				expect({ data.tiles.snack, data.tiles.star, data.tiles.gloves, data.tiles.school }).toEqual({
					0,
					0,
					0,
					0,
				})
				expect({ data.tiles.monuments, data.tiles.pens }).toEqual({ 3, pens })
				data.bestR = 20
				w.Economy.applySplorch(p)
				expect({ data.R, data.bestR }).toEqual({ 14, 20 })
				local Invariants = w.h:require(L .. "Logic.Invariants")
				expect(Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)
	end)

	-- Lot I, étape 2 (D25 du lot B2, plan I M5, journal I-15) : l'écran Améliorations coupé en direct
	describe("EconomyService_upgrades › coupure en direct de l'écran (D25 du lot B2)", function()
		it(
			"UpgradesScreen coupé en direct : un DataPatch retire upgradeSnapshot à chaque joueur chargé (et rien d'autre) ; plus aucun patch ne le porte ; rouvert : il revient",
			function()
				local w = boot({})
				local p = Bots.join(1)
				local q = Bots.join(2)
				w.h:settle(3)
				local snaps = w.h:sentTo(p, "DataSnapshot")
				expect(#snaps >= 1 and snaps[#snaps][1].upgradeSnapshot ~= nil).toBe(true)
				local function drops(player)
					local out = {}
					for _, args in w.h:sentTo(player, "DataPatch") do
						if type(args[2]) == "table" and table.find(args[2], "upgradeSnapshot") then
							table.insert(out, args)
						end
					end
					return out
				end
				expect(#drops(p)).toBe(0)
				local d = w.DS.get(p)
				d.coins += 5
				w.DS.markDirty(p, "coins")
				Bots.frames(20)
				local before = #patchesWithSnapshot(w, p)
				expect(before >= 1).toBe(true)
				-- coupure en direct (commande LiveOps d'un administrateur → Features.set)
				expect(w.F.set("UpgradesScreen", false)).toBe(true)
				Bots.frames(20)
				for _, player in { p, q } do
					local list = drops(player)
					expect(#list).toBe(1)
					expect(list[1][1]).toEqual({})
					expect(list[1][2]).toEqual({ "upgradeSnapshot" })
					expect(list[1][3]).toBeNil()
				end
				-- les patchs suivants (pièces qui coulent) ne le portent plus
				d.coins += 5
				w.DS.markDirty(p, "coins")
				Bots.frames(20)
				expect(#patchesWithSnapshot(w, p)).toBe(before)
				expect(#drops(p)).toBe(1)
				-- rouvert : le patch suivant qui touche ce qu'il montre le porte de nouveau
				expect(w.F.set("UpgradesScreen", true)).toBe(true)
				Bots.frames(10)
				d.coins += 5
				w.DS.markDirty(p, "coins")
				Bots.frames(20)
				expect(#patchesWithSnapshot(w, p) > before).toBe(true)
				expect(#drops(p)).toBe(1)
				clean(w)
			end
		)
	end)
end
