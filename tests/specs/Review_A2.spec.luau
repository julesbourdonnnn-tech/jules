--!nocheck
-- Review_A2 (lot A2, relecture indépendante ; docs/04 §27.2, §27.4, §27.5, §27.14 ; GDD v2.0 §4.27,
-- §11.6) : défauts trouvés par la relecture du code serveur de la progression, chacun écrit ici AVANT
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
end
