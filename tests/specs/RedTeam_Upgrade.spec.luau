--!nocheck
-- RedTeam_Upgrade (lot A2, étape 2 ; docs/04 §15, §17.1 couches b et g, §27.5, §27.10) : l'écran
-- Améliorations attaqué comme le ferait un tricheur. Rafales, modes hors de { 0, 1, 10 }, mauvais
-- types, NaN, nombres énormes, ids inconnus ou presque connus, ligne verrouillée, achat pendant un
-- Grand Splorch ou la sauvegarde de fin, deux requêtes rapides, deux serveurs : jamais une pièce ni un
-- Confetti en trop ou en moins, jamais un niveau au-delà de son plafond, jamais une monnaie négative,
-- NaN ou au-delà de son plafond, aucune erreur, aucun avertissement imprévu.
local Bots = require("../harness/Bots")
local Fuzz = require("../harness/Fuzz")
local Chaos = require("../harness/Chaos")
local Brains = require("../harness/Brains")
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."
	local REMOTE = "ReplicatedStorage.Remotes.BuyUpgrade"
	local FLAGS = { "UpgradesScreen", "Confetti", "Workshop", "StarMat", "Gloves", "Monuments", "RecordR" }

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 1, z = 10, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	local function profileOf(w, extra)
		local d = Bots.profile(w, {
			onboarding = { step = 11, done = true, demoDone = true },
			squishies = { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 5 }) },
			nextUid = 3,
		})
		d.tiles.seen = 15
		d.trophies[1] = 1e5
		d.trophies[5] = 1e5
		d.coins = 1e13
		d.R = 6
		d.bestR = 12
		d.unlocksSeen = 12
		d.confetti = 500
		d.confettiTotal = 500
		for k, v in extra or {} do
			d[k] = v
		end
		return d
	end

	local function setup(w, caught)
		w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
		local Diag = w.h:require(S .. "DiagnosticsService")
		Diag.reportCaught = function(where, err)
			table.insert(caught, where .. " : " .. tostring(err))
		end
		Diag.stateTimedOut = function() end
		w.F = w.h:require(L .. "Config.Features")
		for _, key in FLAGS do
			assert(w.F.set(key, true), key)
		end
	end

	local function boot(extra)
		local caught = {}
		local w = Bots.boot(HarnessV2, {
			t0 = T0,
			before = function(w)
				setup(w, caught)
				Bots.saveProfile(w, 1, profileOf(w, extra))
			end,
		})
		w.caught = caught
		w.Economy = w.h:require(S .. "EconomyService")
		w.UM = w.h:require(L .. "Logic.UpgradeMath")
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.Invariants = w.h:require(L .. "Logic.Invariants")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	-- Monnaies et niveaux toujours dans leurs bornes ; invariants v2 du profil
	local function sane(w, data)
		expect(type(data.coins) == "number" and data.coins == data.coins and data.coins >= 0).toBe(true)
		expect(data.confetti % 1 == 0 and data.confetti >= 0 and data.confetti <= data.confettiTotal).toBe(
			true
		)
		expect(data.confettiTotal <= 1e9).toBe(true)
		for _, id in w.UM.ids() do
			expect({ id = id, ok = w.UM.level(id, data) <= w.UM.maxLevel(id) }).toEqual({ id = id, ok = true })
		end
		expect(w.Invariants.profile(data)).toEqual({})
	end

	local function stable(data)
		local copy = {}
		for k, v in data do
			if k ~= "pot" and k ~= "growth" and k ~= "biggestEver" then
				copy[k] = v
			end
		end
		return copy
	end

	describe("RedTeam_Upgrade › rafales", function()
		it(
			"1 000 BuyUpgrade en une image (même niveau attendu) : au plus 10 traités, un seul achat, la somme exacte d'un niveau",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local calls = 0
				local original = w.Economy.buyUpgrade
				w.Economy.buyUpgrade = function(...)
					calls += 1
					return original(...)
				end
				local coins = data.coins
				local remote = w.h:find(REMOTE)
				for _ = 1, 1000 do
					remote.OnServerEvent:Fire(p, "decor", 1, 0)
				end
				w.h:settle(3)
				expect(calls <= 10).toBe(true)
				expect(data.tiles.decor).toBe(1)
				expect(data.coins).toBe(coins - w.UM.price("decor", 0, 6, 0, 12))
				sane(w, data)
				clean(w)
			end
		)

		it(
			"1 000 BuyUpgrade au niveau attendu exact (tricheur qui suit ses niveaux) : au plus 10 niveaux, chacun payé au prix exact",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local coins = data.coins
				local remote = w.h:find(REMOTE)
				for i = 0, 999 do
					remote.OnServerEvent:Fire(p, "gloves", 1, i % 40)
				end
				w.h:settle(3)
				local n = data.tiles.gloves
				expect(n >= 1 and n <= 10).toBe(true)
				local _, total = w.UM.bulk("gloves", 0, n, 6, 0, 12)
				expect(data.coins).toBe(coins - total)
				sane(w, data)
				clean(w)
			end
		)
	end)

	describe("RedTeam_Upgrade › charges hostiles", function()
		it(
			"Fuzz (couche des types) : chaque argument hostile tour à tour, sans débit : aucune mutation, aucune trace",
			function()
				local w = boot()
				local p = Bots.join(1)
				w.Economy.settle(p)
				local ok, path = Fuzz.profileUnchanged(w.h, p, function()
					Fuzz.attack(w.h, p, "BuyUpgrade", nil, {
						typeHostileOnly = true,
						tick = function()
							w.RateLimit.clear(p)
						end,
					})
					w.h:settle(2)
				end, { "pot", "growth", "biggestEver" })
				expect({ ok, path }).toEqual({ true, nil })
				clean(w)
			end
		)

		it(
			"modes hors de { 0, 1, 10 }, niveaux attendus et ids hostiles : aucune mutation, aucune réponse, aucune trace",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.Economy.settle(p)
				local payloads = {}
				for _, mode in
					{
						2,
						3,
						4,
						5,
						6,
						7,
						8,
						9,
						11,
						40,
						41,
						-1,
						0.5,
						0 / 0,
						math.huge,
						-math.huge,
						1e9,
						-1e9,
						2 ^ 53,
						1e308,
						"10",
						true,
						{},
						nil,
					}
				do
					table.insert(payloads, { "gloves", mode, 0 })
				end
				for _, level in { -1, 65, 1e9, 0.5, 0 / 0, math.huge, "0", false, {} } do
					table.insert(payloads, { "gloves", 1, level })
				end
				for _, id in
					{
						"",
						"x",
						"Gloves",
						"GLOVES",
						" gloves",
						"gloves ",
						"fun.",
						"fun.decoShop",
						"fun.fun.palettes",
						"helper.pip",
						"risesWithRecord",
						"decoPerso",
						string.rep("a", 25),
						string.rep("g", 10000),
						"\255\254",
						"glo\0ves",
						5,
						true,
						{},
					}
				do
					table.insert(payloads, { id, 1, 0 })
				end
				local ok, path = Fuzz.profileUnchanged(w.h, p, function()
					for _, args in payloads do
						w.RateLimit.clear(p)
						w.h:find(REMOTE).OnServerEvent:Fire(p, args[1], args[2], args[3])
					end
					w.h:settle(3)
				end, { "pot", "growth", "biggestEver" })
				expect({ ok, path }).toEqual({ true, nil })
				expect(#w.h:sentTo(p, "UpgradeResult")).toBe(0)
				sane(w, data)
				clean(w)
			end
		)

		it("-0 vaut le mode 0 (Max), jamais une faille : achat borné, payé au prix exact", function()
			local w = boot()
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local coins = data.coins
			w.h:fireServer(REMOTE, p, "decor", -0.0, 0)
			w.h:settle(2)
			local n = data.tiles.decor
			local _, total = w.UM.bulk("decor", 0, n, 6, 0, 12)
			expect(n >= 1 and n <= 18).toBe(true)
			expect(data.coins).toBe(coins - total)
			sane(w, data)
			clean(w)
		end)

		it(
			"ligne verrouillée, interrupteur coupé, ligne en lecture seule : 100 essais chacun, rien d'acheté",
			function()
				local w = boot({ bestR = 7 })
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.Economy.settle(p)
				local before = stable(data)
				local ok, path = Fuzz.profileUnchanged(w.h, p, function()
					for _ = 1, 100 do
						for _, args in
							{
								{ "monument", 1, 1 }, -- 2e Monument au Record R 8
								{ "school", 1, 0 }, -- interrupteur Helpers coupé
								{ "plume", 1, 0 }, -- Record R 12 et Helpers
								{ "springboard", 1, 0 }, -- après une Ascension seulement
								{ "decoShop", 1, 0 }, -- interrupteur DecoPerso coupé
								{ "star", 1, 0 }, -- Tapis 12 pas acheté
							}
						do
							w.RateLimit.clear(p)
							if args[1] == "monument" then
								data.tiles.monuments = 1
							end
							w.h:find(REMOTE).OnServerEvent:Fire(p, table.unpack(args))
						end
					end
					w.h:settle(3)
				end, { "pot", "growth", "biggestEver" })
				-- seul le Monument 1 (posé par le test) a changé le profil
				expect(path).toBe("profil.tiles.monuments")
				expect(ok).toBe(false)
				expect(data.tiles.monuments).toBe(1)
				for _, r in w.h:sentTo(p, "UpgradeResult") do
					expect({
						id = r[1].id,
						spent = r[1].spent,
						locked = r[1].reason == "upgrades.refused.locked",
					}).toEqual({
						id = r[1].id,
						spent = 0,
						locked = true,
					})
				end
				expect(before.coins).toBe(data.coins)
				sane(w, data)
				clean(w)
			end
		)

		it(
			"plafonds : Confettis et pièces ne dépassent jamais leurs bornes, même avec des montants énormes",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				for _, n in { 1e308, 2 ^ 53, 1e9, 1e9 + 1, 0 / 0, -1e9 } do
					w.Economy.addConfetti(p, n, "track")
				end
				expect(data.confettiTotal).toBe(1e9)
				expect(data.confetti <= data.confettiTotal).toBe(true)
				-- pièces énormes : un achat Max reste exact et la poche jamais négative
				data.coins = 1e300
				local r = w.Economy.buyUpgrade(p, "gloves", 0, 0)
				expect(r.to).toBe(40)
				expect(data.coins >= 0 and data.coins == data.coins).toBe(true)
				-- Confettis : tout l'Atelier puis rien de plus (pas assez → refus, jamais négatif)
				for _, id in w.UM.ids() do
					if w.UM.currency(id) == "confetti" then
						w.Economy.buyUpgrade(p, id, 0, w.UM.level(id, data))
					end
				end
				sane(w, data)
				clean(w)
			end
		)
	end)

	describe("RedTeam_Upgrade › robots", function()
		it(
			"16 joueurs, 4 000 actions au hasard (graine fixe) : achats justes ou périmés, gains, Grands Splorch, dalles, interrupteurs en direct ; débit exact, une réponse par achat, profils sains",
			function()
				local caught = {}
				local w = Bots.boot(HarnessV2, {
					t0 = T0,
					before = function(w)
						setup(w, caught)
						w.F.set("RanchTiers", true)
						for id = 1, 16 do
							local best = 8 + id
							Bots.saveProfile(
								w,
								id,
								profileOf(w, {
									R = id % 9,
									bestR = best,
									unlocksSeen = best,
									coins = 10 ^ (5 + id % 8),
								})
							)
						end
					end,
				})
				w.caught = caught
				local Economy = w.h:require(S .. "EconomyService")
				local UM = w.h:require(L .. "Logic.UpgradeMath")
				local Prestige = w.h:require(L .. "Logic.Prestige")
				local Invariants = w.h:require(L .. "Logic.Invariants")
				local players = Bots.spawn(16)
				local rng = Brains.rng(20261105)
				local ids = UM.ids()
				local toggles = {
					"UpgradesScreen",
					"Confetti",
					"Workshop",
					"StarMat",
					"Gloves",
					"Monuments",
					"RecordR",
					"RanchTiers",
				}
				local sources = {
					"splorch",
					"petit",
					"record",
					"fullPen",
					"track",
					"mastery",
					"regain",
					"ascend",
					"skipped",
				}
				local tiles = { "snack", "decor", "pens", "cozyBed" }
				local expectedAnswers, bought, stale = 0, 0, 0
				local problems = {}
				for step = 1, 4000 do
					local p = players[rng:NextInteger(1, 16)]
					local data = w.DS.get(p)
					local roll = rng:NextInteger(1, 100)
					if roll <= 55 then
						local id = ids[rng:NextInteger(1, #ids)]
						local mode = ({ 0, 1, 10 })[rng:NextInteger(1, 3)]
						local level = UM.level(id, data)
						local expected = if rng:NextNumber() < 0.85
							then level
							else math.max(0, level + rng:NextInteger(-2, 2))
						local key = if UM.currency(id) == "coins" then "coins" else "confetti"
						local cash = data[key]
						local r, a, best = Prestige.r(data), Prestige.ascend(data), Prestige.bestR(data)
						local res = Economy.buyUpgrade(p, id, mode, expected)
						if res ~= nil then
							expectedAnswers += 1
							if res.to > res.from then
								bought += 1
								local _, total = UM.bulk(res.id, res.from, res.to - res.from, r, a, best)
								if res.spent ~= total or cash - data[key] ~= total then
									table.insert(
										problems,
										string.format(
											"%d %s : débit %s / %s",
											step,
											id,
											tostring(cash - data[key]),
											tostring(total)
										)
									)
								end
							elseif res.reason == nil then
								stale += 1
								if cash ~= data[key] then
									table.insert(problems, step .. " périmé avec débit")
								end
							end
						end
					elseif roll <= 68 then
						Economy.addConfetti(p, rng:NextInteger(-3, 60), sources[rng:NextInteger(1, #sources)])
					elseif roll <= 72 then
						Economy.applySplorch(p)
					elseif roll <= 78 then
						local key = toggles[rng:NextInteger(1, #toggles)]
						w.F.set(key, not (w.F.get(key) == true))
					elseif roll <= 86 then
						Economy.addCoins(p, 10 ^ rng:NextInteger(2, 12), "Test")
					elseif roll <= 94 then
						w.Clock.advance(0.5)
						Economy.step(w.Clock.now())
					else
						local screen = w.F.get("UpgradesScreen") == true
						if Economy.buyTile(p, tiles[rng:NextInteger(1, #tiles)], "pad") and screen then
							expectedAnswers += 1
						end
					end
					if step % 250 == 0 then
						for _, q in players do
							local d = w.DS.get(q)
							local bad = Invariants.profile(d)
							if #bad > 0 then
								table.insert(
									problems,
									step .. " " .. q.Name .. " : " .. table.concat(bad, ", ")
								)
							end
							if
								not (
									d.coins >= 0
									and d.coins == d.coins
									and d.confetti >= 0
									and d.confetti <= d.confettiTotal
								)
							then
								table.insert(problems, step .. " " .. q.Name .. " : monnaies")
							end
						end
					end
				end
				w.h:settle(3)
				expect(table.concat(problems, "\n")).toBe("")
				local results = 0
				for _, q in players do
					results += #w.h:sentTo(q, "UpgradeResult")
				end
				expect(results).toBe(expectedAnswers)
				expect(bought > 100).toBe(true)
				expect(stale > 10).toBe(true)
				clean(w)
			end
		)
	end)

	describe("RedTeam_Upgrade › prestige, sauvegarde, deux serveurs", function()
		it(
			"pendant le spectacle de son Grand Splorch (vrai SplorchService) : « attends la fin du spectacle », rien d'acheté ; après : permis",
			function()
				local w = boot()
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local Squishy = w.h:require(S .. "SquishyService")
				local Splorch = w.h:require(S .. "SplorchService")
				-- le héros est prêt (plus gros ≥ objectif de r = 6) : la progression v2.0 rend la place d'un
				-- Grand Splorch que Prestige.apply refuserait (lot A2 étape 3, journal A2-27)
				w.Economy.settle(p)
				data.squishies["2"].z = 2 * w.Prestige.target(6)
				Squishy.setWaiting(p, "2")
				local now = w.Clock.now()
				w.Signals.SpectacleStarted:Fire("splorch", p.UserId, now)
				w.h:settle(2)
				local coins = data.coins
				local r = w.Economy.buyUpgrade(p, "gloves", 1, 0)
				expect(r.reason).toBe("upgrades.refused.busy")
				expect({ data.coins, data.tiles.gloves }).toEqual({ coins, 0 })
				-- éclatement puis fin du spectacle (tick du serveur)
				for _ = 1, 120 do
					w.Clock.advance(0.1)
					Splorch.step(w.Clock.now())
				end
				w.h:settle(3)
				-- le Grand Splorch a eu lieu (r + 1, pièces remises à zéro) ; le spectacle fini, l'achat passe
				expect(data.R).toBe(7)
				expect(w.Economy.buyUpgrade(p, "decor", 1, 0).reason).toBe("upgrades.refused.coins")
				data.coins = 1e13
				r = w.Economy.buyUpgrade(p, "decor", 1, w.UM.level("decor", data))
				expect(r.reason).toBeNil()
				expect(r.to).toBe(r.from + 1)
				sane(w, data)
				clean(w)
			end
		)

		it(
			"deux serveurs : tant que A tient la session, B ne peut rien acheter ; après le départ, B relit l'achat de A une seule fois",
			function()
				T.expectWarning("verrouillées par un autre serveur")
				local shared = Chaos.store()
				local caughtA, caughtB = {}, {}
				local a = Chaos.boot(HarnessV2, Bots, shared, "A", {
					t0 = T0,
					before = function(w)
						setup(w, caughtA)
						w.DS.Settings.LOCKED_RETRY_DELAY = 0.01
					end,
				})
				Chaos.seed(shared, 1, profileOf(a))
				local EconomyA = a.h:require(S .. "EconomyService")
				local p = Bots.join(1)
				local dataA = a.DS.get(p)
				local coins = dataA.coins
				local r = EconomyA.buyUpgrade(p, "gloves", 10, 0)
				local bought, spent = r.to, r.spent
				expect(bought >= 1).toBe(true)
				-- serveur B : le même joueur arrive pendant que A tient la session
				local b = Chaos.boot(HarnessV2, Bots, shared, "B", {
					t0 = T0,
					before = function(w)
						setup(w, caughtB)
						w.DS.Settings.LOCKED_RETRY_DELAY = 0.01
					end,
				})
				local EconomyB = b.h:require(S .. "EconomyService")
				local pb = Bots.join(1, { wait = false })
				expect(b.DS.get(pb)).toBeNil()
				expect(EconomyB.buyUpgrade(pb, "gloves", 10, 0)).toBeNil()
				expect(EconomyB.addConfetti(pb, 5, "track")).toBe(0)
				-- A part : sa sauvegarde de départ écrit l'achat
				Bots.use(a)
				Bots.leave(p)
				local start = os.clock()
				while (Chaos.record(shared, 1) or {}).lastOnline ~= T0 and os.clock() - start < 5 do
					task.wait(0.005)
				end
				local saved = Chaos.record(shared, 1)
				expect({ saved.tiles.gloves, saved.coins }).toEqual({ bought, coins - spent })
				-- B relit le profil (nouvelle arrivée) : l'achat une seule fois, rien de plus
				Bots.use(b)
				local pb2 = Bots.join(1)
				start = os.clock()
				while b.DS.get(pb2) == nil and os.clock() - start < 5 do
					task.wait(0.005)
				end
				local dataB = b.DS.get(pb2)
				expect({ dataB.tiles.gloves, dataB.coins }).toEqual({ bought, coins - spent })
				expect(table.concat(caughtA, "\n") .. table.concat(caughtB, "\n")).toBe("")
				a.h:dispose()
				b.h:dispose()
			end
		)
	end)
end
