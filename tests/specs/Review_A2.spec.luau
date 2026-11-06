--!nocheck
-- Review_A2 (lot A2, relecture indépendante ; docs/04 §27.2, §27.4, §27.5, §27.14 ; GDD v2.0 §4.27,
-- §11.5) : défauts trouvés par la relecture du code serveur de la progression, chacun écrit ici AVANT
-- sa correction (rouge sur le code relu, vert après) :
--   * UpgradeBought émis pour TOUT achat, dalles comprises (docs/04 §27.4) : le chemin de la v1.3 de
--     BuyTile (écran coupé) ne l'émettait pas ; les attributs de palier du ranch [RanchTiers] restaient
--     ceux d'avant l'achat (et le Carnet d'A4 ne compterait pas l'achat) ;
--   * Record absolu (r = MaxR = 400) : l'attribut SplorchReady disait « prêt » alors que le Grand
--     Splorch est refusé ; un profil v2 dont la progression v2.0 est coupée (RecordR) passait r à 401
--     (invariant v2 r ≤ MaxR cassé, « réparé » au chargement suivant : un Grand Splorch rejoué) ;
--   * attributs du ranch calculés par RanchService (BestR, Monuments, paliers) : un interrupteur changé
--     en direct par LiveOps ne les posait ni ne les effaçait avant l'achat ou le prestige suivant ;
--   * décorations dorées (champ decorBuilds, docs/04 §27.2 et §27.14 : EconomyService, au Grand
--     Splorch) : jamais comptées ; chaque boucle jouée était perdue pour la décoration dorée.
-- Vérifiés sains (verts du premier coup, gardés) : même objectif à l'entrée et à l'application
-- (Formulas.splorchTarget = Prestige.target) ; plus gros vendu pendant son propre spectacle ; Jelly
-- Ascend avec le Meilleur Ami au Dodo ; robot de 8 joueurs × 1 500 actions (Confettis conservés,
-- Record R et A jamais en baisse, profils sains, zéro trace).
-- Les interrupteurs v2.0 sont ouverts DANS le test (Features.set) ; SchemaV2 (figé) dans le harnais
-- avant le premier require du schéma (recette de DataChaos).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."
	local R = "ReplicatedStorage.Remotes."

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

	-- Monde des services (Bots) : profil v2 du joueur 1, interrupteurs `flags` ouverts avant le départ
	local function boot(flags, edit, harness)
		local caught = {}
		local w = Bots.boot(harness or HarnessV2, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				w.F = w.h:require(L .. "Config.Features")
				for _, key in flags do
					assert(w.F.set(key, true), key)
				end
				local d = Bots.profile(w, {
					onboarding = { step = 11, done = true, demoDone = true },
					squishies = { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 5 }) },
					nextUid = 3,
				})
				d.tiles.seen = 15
				d.trophies[1] = 1e5
				d.coins = 1e14
				d.R = 6
				if d.version ~= nil and d.version >= 2 then
					d.bestR = 12
					d.unlocksSeen = 12
					d.tiles.monuments = 2
				end
				d.tiles.snack = 3
				d.tiles.decor = 5
				if edit then
					edit(d)
				end
				Bots.saveProfile(w, 1, d)
			end,
		})
		w.caught = caught
		w.Economy = w.h:require(S .. "EconomyService")
		w.Ranch = w.h:require(S .. "RanchService")
		w.World = w.h:require(S .. "WorldService")
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.TierRules = w.h:require(L .. "Logic.TierRules")
		w.Invariants = w.h:require(L .. "Logic.Invariants")
		w.Balance = w.h:require(L .. "Config.Balance")
		w.bought = {}
		w.Signals.UpgradeBought:Connect(function(p, id, from, to, currency)
			table.insert(w.bought, { p = p, id = id, from = from, to = to, currency = currency })
		end)
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	local function attr(w, p, name)
		local model = w.World.ranchModel(w.Ranch.slotOf(p))
		return model and model:GetAttribute(name)
	end

	-- =========================================================================================
	describe("Review_A2 › UpgradeBought pour tout achat, dalles comprises", function()
		it(
			"écran coupé (chemin de la v1.3 de BuyTile) : UpgradeBought émis, palier du Tapis du ranch recalculé [RanchTiers]",
			function()
				local w = boot({ "RanchTiers" })
				local p = Bots.join(1)
				w.h:settle(3)
				expect(attr(w, p, "TapisTier")).toBe(w.TierRules.of("snack", 3))
				Bots.fire("BuyTile", p, "snack")
				w.h:settle(3)
				local data = w.DS.get(p)
				expect(data.tiles.snack).toBe(4)
				expect(w.bought).toEqual({ { p = p, id = "snack", from = 3, to = 4, currency = "coins" } })
				expect(attr(w, p, "TapisTier")).toBe(w.TierRules.of("snack", 4))
				-- écran coupé : aucune réponse de l'écran
				expect(#w.h:sentTo(p, "UpgradeResult")).toBe(0)
				clean(w)
			end
		)

		it(
			"tout coupé (serveur v1, profil v1) : même achat qu'en v1.3, UpgradeBought en plus, aucun attribut ni envoi de plus",
			function()
				local w = boot({}, nil, Harness)
				local p = Bots.join(1)
				w.h:settle(3)
				Bots.fire("BuyTile", p, "decor")
				w.h:settle(3)
				local data = w.DS.get(p)
				expect(data.tiles.decor).toBe(6)
				expect(data.version).toBe(1)
				expect(w.bought).toEqual({ { p = p, id = "decor", from = 5, to = 6, currency = "coins" } })
				expect(attr(w, p, "TapisTier")).toBeNil()
				expect(#w.h:sentTo(p, "UpgradeResult")).toBe(0)
				expect(data.decorBuilds).toBeNil()
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("Review_A2 › attributs du ranch et interrupteurs changés en direct", function()
		it(
			"RecordR, Monuments et RanchTiers ouverts puis coupés en direct (LiveOps) : BestR, Monuments et paliers posés puis effacés au tick, sans achat ni prestige",
			function()
				local w = boot({})
				local p = Bots.join(1)
				w.h:settle(3)
				Bots.frames(15)
				expect(attr(w, p, "BestR")).toBeNil()
				expect(attr(w, p, "TapisTier")).toBeNil()
				for _, key in { "RecordR", "Monuments", "RanchTiers" } do
					assert(w.F.set(key, true), key)
				end
				Bots.frames(15)
				expect(attr(w, p, "BestR")).toBe(12)
				expect(attr(w, p, "Monuments")).toBe(2)
				expect(attr(w, p, "TapisTier")).toBe(w.TierRules.of("snack", 3))
				expect(attr(w, p, "GloveTier")).toBe(0)
				w.F.set("Monuments", false)
				w.F.set("RanchTiers", false)
				Bots.frames(15)
				expect(attr(w, p, "Monuments")).toBeNil()
				expect(attr(w, p, "TapisTier")).toBeNil()
				expect(attr(w, p, "GloveTier")).toBeNil()
				expect(attr(w, p, "BestR")).toBe(12)
				w.F.set("RecordR", false)
				Bots.frames(15)
				expect(attr(w, p, "BestR")).toBeNil()
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("Review_A2 › décorations dorées (decorBuilds)", function()
		local function ready(d)
			d.squishies["2"].z = 1e30
		end

		it(
			"chaque prestige v2.0 (Grand Splorch, Petit Splorch, Jelly Ascend) compte une boucle pour chaque décoration construite, bornée à 10 ; rien d'autre ne change",
			function()
				local w = boot({ "RecordR", "Confetti", "JellyAscend", "PetitSplorch" }, function(d)
					ready(d)
					d.R, d.bestR, d.unlocksSeen = 12, 12, 12
					d.decorBuilds[2] = 10
					d.decorBuilds[7] = 4
				end)
				local p = Bots.join(1)
				w.h:settle(3)
				local data = w.DS.get(p)
				-- Grand Splorch (nouveau Record R 13) : décorations 1 à 5 construites dans cette boucle
				local _, report = w.Economy.applyPrestige(p, "splorch")
				expect(report.applied).toBe(true)
				expect(report.kind).toBe("splorch")
				expect(data.decorBuilds).toEqual({ 1, 10, 1, 1, 1, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
				w.h:settle(3)
				local patched = false
				for _, args in w.h:sentTo(p, "DataPatch") do
					if args[1].decorBuilds ~= nil then
						patched = true
					end
				end
				expect(patched).toBe(true)
				-- boucle suivante (r 15, condition de la 1re Ascension) : 3 décorations, puis la Jelly Ascend
				data.tiles.decor = 3
				ready(data)
				data.R, data.bestR = 15, 15
				local _, asc = w.Economy.applyPrestige(p, "ascend")
				expect(asc.applied).toBe(true)
				expect(data.decorBuilds).toEqual({ 2, 10, 2, 1, 1, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
				-- remontée : Petit Splorch (r après ≤ Record R), 7 décorations
				data.tiles.decor = 7
				ready(data)
				local _, petit = w.Economy.applyPrestige(p, "petit")
				expect(petit.applied).toBe(true)
				expect(petit.kind).toBe("petit")
				expect(data.decorBuilds).toEqual({ 3, 10, 3, 2, 2, 1, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
				-- prestige refusé (pas prêt) : rien compté
				local _, refused = w.Economy.applyPrestige(p, "petit")
				expect(refused.applied).toBe(false)
				expect(data.decorBuilds).toEqual({ 3, 10, 3, 2, 2, 1, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
				expect(w.Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)

		it("progression v2.0 coupée (RecordR) : le Grand Splorch de la v1.3 ne compte rien", function()
			local w = boot({}, ready)
			local p = Bots.join(1)
			w.h:settle(3)
			local data = w.DS.get(p)
			local before = table.clone(data.decorBuilds)
			w.Economy.applySplorch(p)
			expect(data.decorBuilds).toEqual(before)
			clean(w)
		end)
	end)

	-- =========================================================================================
	describe("Review_A2 › même objectif à l'entrée et à l'application", function()
		it(
			"Formulas.splorchTarget (entrée dans la file, SplorchReady) = Prestige.target (Prestige.apply, départ du spectacle) pour r = 0 … MaxR",
			function()
				local h = Harness.new({ mode = "server" })
				local Formulas = h:require(L .. "Logic.Formulas")
				local Prestige = h:require(L .. "Logic.Prestige")
				local Balance = h:require(L .. "Config.Balance")
				local diff = {}
				for r = 0, Balance.Prestige.MaxR do
					if Formulas.splorchTarget(r) ~= Prestige.target(r) then
						table.insert(diff, r)
					end
				end
				expect(diff).toEqual({})
			end
		)
	end)

	-- =========================================================================================
	-- Record absolu (r = MaxR) : monde complet (Brains), le héros chez lui
	-- =========================================================================================
	local function world(flags, edit)
		local w = Brains.boot(HarnessV2, { t0 = T0 })
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.Invariants = w.h:require(L .. "Logic.Invariants")
		w.World = w.h:require(S .. "WorldService")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		for _, key in flags do
			assert(w.Features.set(key, true), key)
		end
		local maxR = w.Balance.Prestige.MaxR
		local hero = Brains.join(w, 1, {
			profile = Brains.profile(w, {
				coins = 5000,
				R = maxR,
				squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = w.Balance.Numbers.Max } },
				edit = function(d)
					d.bestR = maxR
					d.unlocksSeen = maxR
					if edit then
						edit(d)
					end
				end,
			}),
		})
		Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
		Brains.frames(w, 2)
		return w, hero
	end

	local function brainsClean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	describe("Review_A2 › Record absolu (r = MaxR)", function()
		it(
			"progression v2.0 : SplorchReady faux au Record absolu (le Grand Splorch y est refusé : « Record absolu ! »)",
			function()
				local w, hero = world({ "RecordR" })
				local maxR = w.Balance.Prestige.MaxR
				expect(w.Squishy.biggest(hero) ~= nil).toBe(true)
				Brains.frames(w, 30)
				expect(attr(w, hero, "SplorchReady")).toBe(false)
				w.h:fireServer(R .. "GrandSplorch", hero, false, "2")
				Brains.frames(w, 120)
				expect(table.find(Bots.feedbackKeys(hero), "splorch.recordAbsolute") ~= nil).toBe(true)
				expect(w.DS.get(hero).R).toBe(maxR)
				brainsClean(w)
			end
		)

		it(
			"profil v2, progression v2.0 coupée (RecordR) : refusé aussi, r jamais au-delà de MaxR (invariant v2)",
			function()
				local w, hero = world({})
				local maxR = w.Balance.Prestige.MaxR
				w.h:fireServer(R .. "GrandSplorch", hero, false, "2")
				Brains.frames(w, 150)
				local data = w.DS.get(hero)
				expect(data.R).toBe(maxR)
				expect(w.Splorch.queued(hero)).toBeNil()
				expect(table.find(Bots.feedbackKeys(hero), "splorch.recordAbsolute") ~= nil).toBe(true)
				expect(w.Invariants.profile(data)).toEqual({})
				brainsClean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("Review_A2 › filets du spectacle", function()
		local function untilKind(w, hero, kind)
			for _ = 1, 400 do
				local shows = Bots.celebrations(hero, kind)
				if #shows > 0 then
					return shows[#shows]
				end
				Brains.frames(w, 1)
			end
			return nil
		end

		-- Lot A4 (D6, attente changée, journal A4-13) : la vente du plus gros PENDANT son propre spectacle
		-- v2.0 est maintenant REFUSÉE (héros protégé : feedback.waitingSplorch, rien ne bouge) et le
		-- Grand Splorch s'applique ; le filet PrestigeRefused reste couvert : le plus gros disparaît par un
		-- chemin qui n'est pas une intention (profil changé directement pendant le spectacle suivant)
		it(
			"plus gros vendu PENDANT son spectacle : vente refusée (héros protégé), prestige appliqué ; plus gros disparu par un autre chemin : rien appliqué ni donné, attente levée, aucun état coincé ; le Grand Splorch suivant passe",
			function()
				local w = Brains.boot(HarnessV2, { t0 = T0 })
				w.World = w.h:require(S .. "WorldService")
				w.Invariants = w.h:require(L .. "Logic.Invariants")
				local RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
				for _, key in { "RecordR", "Confetti", "PetitSplorch", "JellyAscend" } do
					assert(w.Features.set(key, true), key)
				end
				local hero = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						coins = 5000,
						R = 1,
						squishies = {
							{ s = 1, z = 100, bf = 1 },
							{ s = 2, z = 40000 },
							{ s = 3, z = 300 },
							{ s = 4, z = 50 },
						},
						edit = function(d)
							d.bestR = 1
							d.unlocksSeen = 1
						end,
					}),
				})
				local other = Brains.join(w, 2, {
					profile = Brains.profile(w, { squishies = { { s = 2, z = 500 } } }),
				})
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				w.h:fireServer(R .. "GrandSplorch", hero, false, "3")
				local show = untilKind(w, hero, "splorch")
				expect(show ~= nil).toBe(true)
				local refusedBefore = #Bots.feedbackKeys(hero)
				w.h:fireServer(R .. "Sell", hero, { "2" }, true)
				w.h:settle(1)
				-- héros protégé : vente refusée, un seul Feedback neutre, rien ne bouge
				expect(w.Squishy.get(hero, "2") ~= nil).toBe(true)
				local keys = Bots.feedbackKeys(hero)
				expect(#keys).toBe(refusedBefore + 1)
				expect(keys[#keys]).toBe("feedback.waitingSplorch")
				Brains.frames(w, 120)
				local data = w.DS.get(hero)
				expect(data.R).toBe(2)
				expect(data.bestR).toBe(2)
				expect(w.Squishy.waiting(hero)).toBeNil()
				expect(w.Splorch.queuedKind(hero)).toBeNil()
				expect(w.Splorch.canPrestige(hero)).toBe(true)
				expect(w.Splorch.counters().PrestigeRefused or 0).toBe(0)
				expect(w.Invariants.profile(data)).toEqual({})
				-- spectacle fini : la vente est acceptée de nouveau
				RateLimit.clear(hero)
				w.h:fireServer(R .. "Sell", hero, { "4" }, true)
				w.h:settle(1)
				expect(w.Squishy.get(hero, "4")).toBeNil()
				-- filet de sûreté : le plus gros disparaît PENDANT le spectacle suivant par un chemin qui
				-- n'est pas une intention : rien appliqué ni donné, attente levée, aucun état coincé
				w.Economy.settle(hero)
				data.squishies["2"].z = 1e6
				w.Economy.refresh(hero)
				RateLimit.clear(hero)
				local gifts = #Bots.celebrations(other, "giftRain")
				w.h:fireServer(R .. "GrandSplorch", hero, false, "3")
				local shows = #Bots.celebrations(hero, "splorch")
				for _ = 1, 400 do
					if #Bots.celebrations(hero, "splorch") > shows then
						break
					end
					Brains.frames(w, 1)
				end
				expect(#Bots.celebrations(hero, "splorch")).toBe(shows + 1)
				w.Economy.settle(hero)
				data.squishies["2"] = nil
				w.Economy.refresh(hero)
				Brains.frames(w, 120)
				expect(data.R).toBe(2)
				expect(data.bestR).toBe(2)
				expect(w.Squishy.waiting(hero)).toBeNil()
				expect(w.Splorch.queuedKind(hero)).toBeNil()
				expect(w.Splorch.canPrestige(hero)).toBe(true)
				expect(#Bots.celebrations(other, "giftRain")).toBe(gifts)
				expect(w.Splorch.counters().PrestigeRefused).toBe(1)
				expect(w.Invariants.profile(data)).toEqual({})
				-- la boucle continue : prêt de nouveau, le Grand Splorch suivant s'applique
				w.Economy.settle(hero)
				data.squishies["3"].z = 1e7
				w.Economy.refresh(hero)
				RateLimit.clear(hero)
				w.h:fireServer(R .. "GrandSplorch", hero, false, "3")
				Brains.frames(w, 200)
				expect(w.DS.get(hero).R).toBe(3)
				expect(w.Squishy.waiting(hero)).toBeNil()
				brainsClean(w)
			end
		)

		it(
			"Jelly Ascend quand le Meilleur Ami n° 1 dort au Dodo : il monte dans le faisceau, l'Ascension s'applique, rien ne reste en attente",
			function()
				local w = Brains.boot(HarnessV2, { t0 = T0 })
				w.World = w.h:require(S .. "WorldService")
				w.Invariants = w.h:require(L .. "Logic.Invariants")
				for _, key in { "RecordR", "Confetti", "PetitSplorch", "JellyAscend" } do
					assert(w.Features.set(key, true), key)
				end
				local hero = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						coins = 5000,
						R = 15,
						squishies = {
							{ s = 1, z = 100, bf = 1, at = "dodo" },
							{ s = 2, z = 20000 },
							{ s = 3, z = 300 },
						},
						edit = function(d)
							d.bestR = 15
							d.unlocksSeen = 15
						end,
					}),
				})
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				w.h:fireServer(R .. "JellyAscend", hero, true)
				expect(w.Splorch.queuedKind(hero)).toBe("ascend")
				local show = untilKind(w, hero, "ascend")
				expect(show ~= nil).toBe(true)
				expect(show.flyer.s).toBe(1)
				Brains.frames(w, 150)
				local data = w.DS.get(hero)
				expect(data.ascend).toBe(1)
				expect(data.squishies["1"].at).toBe("dodo")
				expect(w.Squishy.waiting(hero)).toBeNil()
				expect(w.Splorch.canPrestige(hero)).toBe(true)
				expect(w.Invariants.profile(data)).toEqual({})
				brainsClean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("Review_A2 › robots de la progression (relecture)", function()
		it(
			"8 joueurs, 1 500 actions au hasard (graine fixe) : achats, Grands et Petits Splorch, Jelly Ascend, départs et retours, interrupteurs en direct ; Confettis conservés, Record R et A jamais en baisse, profils sains, zéro trace",
			function()
				local w = Brains.boot(HarnessV2, { t0 = T0 })
				local ALL = {
					"UpgradesScreen",
					"Confetti",
					"Workshop",
					"StarMat",
					"Gloves",
					"Monuments",
					"RecordR",
					"JellyAscend",
					"PetitSplorch",
					"RanchTiers",
				}
				for _, key in ALL do
					assert(w.Features.set(key, true), key)
				end
				local UM = w.h:require(L .. "Logic.UpgradeMath")
				local Prestige = w.h:require(L .. "Logic.Prestige")
				local Invariants = w.h:require(L .. "Logic.Invariants")
				local RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
				local rng = Brains.rng(20261106)
				local problems = {}
				local function problem(line)
					if #problems < 25 then
						table.insert(problems, line)
					end
				end
				-- registre des Confettis par joueur (ConfettiChanged : gains et dépenses), Record R et A vus
				local ledger = {}
				w.Signals.ConfettiChanged:Connect(function(pl, delta, _source)
					local l = ledger[pl.UserId]
					l.pocket += delta
					if delta > 0 then
						l.total += delta
					end
				end)
				local ascends, petits, splorches = 0, 0, 0
				w.Signals.PrestigeApplied:Connect(function(_pl, kind)
					if kind == "ascend" then
						ascends += 1
					elseif kind == "petit" then
						petits += 1
					else
						splorches += 1
					end
				end)
				local N = 8
				local players = {}
				local function profileOf(i)
					local kind = i % 3
					return Brains.profile(w, {
						coins = 10 ^ (4 + i % 5),
						R = if kind == 0 then 1 elseif kind == 1 then 14 else 37,
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 50 }, { s = 3, z = 40 } },
						tiles = { snack = 6, decor = 4 },
						edit = function(d)
							d.bestR = if kind == 0 then 1 elseif kind == 1 then 14 else 40
							d.ascend = if kind == 2 then 2 else 0
							d.regainBonusA = 0
							d.unlocksSeen = d.bestR
							d.confetti, d.confettiTotal = 200, 200
						end,
					})
				end
				local function join(i, fresh)
					local p = Brains.join(w, i, { profile = if fresh then profileOf(i) else nil })
					Bots.place(p, Brains.atRanch(w, p, 0, 30))
					players[i] = p
					local d = w.DS.get(p)
					if fresh then
						ledger[i] =
							{ pocket = d.confetti, total = d.confettiTotal, best = d.bestR, A = d.ascend }
					end
					return p
				end
				for i = 1, N do
					join(i, true)
				end
				Brains.frames(w, 5)
				local ids = UM.ids()
				local bought, stale = 0, 0
				local function check(step)
					for i, p in players do
						local d = if p.Parent ~= nil then w.DS.get(p) else nil
						if d ~= nil then
							local l = ledger[i]
							local bad = Invariants.profile(d)
							if #bad > 0 then
								problem(step .. " joueur " .. i .. " : " .. table.concat(bad, ", "))
							end
							if d.confetti ~= l.pocket or d.confettiTotal ~= l.total then
								problem(
									string.format(
										"%d joueur %d : Confettis %s / %s, attendu %s / %s",
										step,
										i,
										tostring(d.confetti),
										tostring(d.confettiTotal),
										tostring(l.pocket),
										tostring(l.total)
									)
								)
								l.pocket, l.total = d.confetti, d.confettiTotal
							end
							if d.bestR < l.best or d.ascend < l.A then
								problem(step .. " joueur " .. i .. " : Record R ou A en baisse")
							end
							l.best, l.A = d.bestR, d.ascend
						end
					end
				end
				for step = 1, 1500 do
					local i = rng:NextInteger(1, N)
					local p = players[i]
					local data = w.DS.get(p)
					local roll = rng:NextInteger(1, 100)
					if data == nil then
						Brains.frames(w, 1)
					elseif roll <= 35 then
						local id = ids[rng:NextInteger(1, #ids)]
						local mode = ({ 0, 1, 10 })[rng:NextInteger(1, 3)]
						local level = UM.level(id, data)
						local key = if UM.currency(id) == "coins" then "coins" else "confetti"
						w.Economy.settle(p)
						local cash = data[key]
						local r, a, best = Prestige.r(data), Prestige.ascend(data), Prestige.bestR(data)
						local res = w.Economy.buyUpgrade(p, id, mode, level)
						if res ~= nil and res.to > res.from then
							bought += 1
							local _, total = UM.bulk(res.id, res.from, res.to - res.from, r, a, best)
							-- au-delà de 2^53 les pièces sont des réels : le débit est arrondi au réel
							-- représentable le plus proche (moins d'une unité du dernier chiffre de la caisse)
							local tol = if cash < 9007199254740992 then 0 else cash * 4.5e-16
							if res.spent ~= total or math.abs((cash - data[key]) - total) > tol then
								problem(
									string.format(
										"%d %s : %d → %d, débit %s, payé %s, somme exacte %s",
										step,
										id,
										res.from,
										res.to,
										tostring(cash - data[key]),
										tostring(res.spent),
										tostring(total)
									)
								)
							end
						elseif res ~= nil and res.reason == nil then
							stale += 1
						end
					elseif roll <= 52 then
						-- la boucle finit : plus gros à l'objectif, puis le Grand (ou Petit) Splorch
						local uid = "2"
						if data.squishies[uid] ~= nil and data.squishies[uid].at == "pen" then
							w.Economy.settle(p)
							local target = Prestige.target(Prestige.r(data))
							data.squishies[uid].z = math.max(data.squishies[uid].z, target * 1.05)
							w.Economy.refresh(p)
							RateLimit.clear(p)
							Bots.fire("GrandSplorch", p, false, uid)
						end
					elseif roll <= 58 then
						-- boucle record jouée jusqu'à la condition de l'Ascension (raccourci du test : r et
						-- Record R ensemble, jamais l'un sans l'autre), puis la Jelly Ascend
						if Prestige.r(data) == Prestige.bestR(data) and w.Splorch.canPrestige(p) then
							local need = Prestige.reqR(Prestige.ascend(data) + 1)
							if need <= w.Balance.Prestige.MaxR and data.R < need then
								data.R, data.bestR = need, need
								w.DS.markDirty(p, "R")
								w.DS.markDirty(p, "bestR")
							end
						end
						RateLimit.clear(p)
						Bots.fire("JellyAscend", p, true)
					elseif roll <= 66 then
						local key = ALL[rng:NextInteger(1, #ALL)]
						w.Features.set(key, not (w.Features.get(key) == true))
					elseif roll <= 70 then
						Bots.leave(p)
						players[i] = nil
						Brains.frames(w, rng:NextInteger(1, 60))
						join(i, false)
					elseif roll <= 74 then
						w.Economy.addCoins(p, 10 ^ rng:NextInteger(3, 14), "Test")
					else
						Brains.frames(w, rng:NextInteger(1, 40))
					end
					check(step)
				end
				-- fin : tout rouvert, spectacles finis
				for _, key in ALL do
					w.Features.set(key, true)
				end
				Brains.frames(w, 200)
				check(1501)
				expect(table.concat(problems, "\n")).toBe("")
				expect(bought > 40).toBe(true)
				expect(splorches > 5).toBe(true)
				expect(petits > 5).toBe(true)
				expect(ascends >= 1).toBe(true)
				brainsClean(w)
			end
		)
	end)
end
