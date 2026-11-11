--!nocheck
-- SquishyService v2.0 (lot A4, étape 2 ; docs/04 §27.7, §27.13 N1 ; GDD v2.0 §4.27, §4.28) : restes du
-- serveur adressés au propriétaire de SquishyService (notes d'A3 du 6 novembre, 0 h 40 et 1 h 10 ;
-- A2 RESTE 7 ; plan du lot A4 D6, D7, D21) :
--   * helperPressed(owner, uid, now) : la Plopette pose la même recharge que la pression du joueur
--     (8 s : le joueur ne represse pas le squishy juste après) et l'état public « pas prêt » (ready) ;
--   * busy(player, uid) : réservé par une fusion (FuseMenu) jusqu'à la fusion, ou en fuite ;
--   * héros protégé pendant son spectacle v2.0 (D6) : Sell, Release, FuseMenu, FuseAll et le lancer
--     qui fusionne refusés (feedback.waitingSplorch, rien ne bouge), « Tout fusionner » commencé avant
--     le spectacle en pause jusqu'à sa fin, animation du Petit Splorch comprise ; acceptés après ;
--     chemin de la v1.3 (profil v1, interrupteurs coupés) inchangé ;
--   * N1 (D7) : après Prestige.apply("ascend") (RecordR ouvert), Cuve (niveau, intervalle), familles
--     et places de Meilleur Ami suivent le Record R ; profil v1 : R, comme avant ;
--   * tenues v2.0 (D21) : connues d'un profil v2 seulement, toujours bornées par outfits.owned.
-- Interrupteurs ouverts DANS le test (Features.set) ; SchemaV2 (figé) dans le harnais avant le premier
-- require du schéma (recette de DataChaos).
local Flags = require("../harness/Flags")
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60 -- loin de tout Rush ou MEGA pendant ~4 min
	local L = "ReplicatedStorage.Shared."
	local R = "ReplicatedStorage.Remotes."
	local V2 = { "RecordR", "Confetti", "PetitSplorch", "JellyAscend" }

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- opts : v1 (serveur v1 : profils v1), flags (interrupteurs ouverts)
	local function boot(opts)
		opts = opts or {}
		-- opts.v1 : serveur de la v1.3 (préréglage « v13 », tests/harness/Flags, lot I D2 a) ; sinon la
		-- configuration livrée, SchemaV2 ouvert (chemin du lancement)
		local w = Brains.boot(if opts.v1 then Flags.harness(Harness, "v13") else HarnessV2, { t0 = T0 })
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.Odds = w.h:require(L .. "Logic.Odds")
		w.Invariants = w.h:require(L .. "Logic.Invariants")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		for _, key in opts.flags or {} do
			assert(w.Features.set(key, true), key)
		end
		w.fused = 0
		w.Signals.Fused:Connect(function()
			w.fused += 1
		end)
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	-- intention envoyée (seau à jetons vidé : la règle du serveur seule décide)
	local function fire(w, name, p, ...)
		w.RateLimit.clear(p)
		w.h:fireServer(R .. name, p, ...)
		w.h:settle(1)
	end

	local function feedbacks(p)
		return Bots.feedbackKeys(p)
	end

	-- le joueur debout à 1 stud de la place d'un squishy (enclos ou Bassin)
	local function standAt(w, p, uid)
		local c = w.Squishy.placeOf(p, uid)
		Bots.place(p, Bots.ground(c.X + 1, c.Z))
		Brains.frames(w, 2)
	end

	-- le joueur au bord du Bassin (portée du lancer)
	local function standPool(w, p)
		local c = w.WL.anchor(w.Ranch.slotOf(p), "pool")
		Bots.place(p, Bots.ground(c.X + 6, c.Z))
		Brains.frames(w, 2)
	end

	-- échéances de fusion ouvertes du joueur (« fusion », « combo »)
	local function jobsOf(w, p)
		local n = 0
		for _, s in w.Squishy.openStates() do
			if s.player == p and (s.name == "fusion" or s.name == "combo") then
				n += 1
			end
		end
		return n
	end

	-- avance jusqu'au départ du spectacle du héros (Celebrate « splorch ») ; rend vrai s'il est parti
	local function untilShow(w, hero)
		local before = #Bots.celebrations(hero, "splorch")
		for _ = 1, 400 do
			if #Bots.celebrations(hero, "splorch") > before then
				return true
			end
			Brains.frames(w, 1)
		end
		return false
	end

	-- héros prêt au Grand Splorch (r = 1 → 2, record) : « 2 » le plus gros (objectif atteint), « 3 » le
	-- squishy qui s'envole ; `extra` : squishies de plus (uids 4, 5…)
	local function heroProfile(w, extra, edit)
		local squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 40000 }, { s = 3, z = 300 } }
		for _, spec in extra or {} do
			table.insert(squishies, spec)
		end
		return Brains.profile(w, {
			coins = 5000,
			R = 1,
			squishies = squishies,
			edit = function(d)
				if d.version ~= nil and d.version >= 2 then
					d.bestR = 1
					d.unlocksSeen = 1
				end
				if edit then
					edit(d)
				end
			end,
		})
	end

	-- =========================================================================================
	describe("SquishyService v2 › recharge posée par une Plopette (helperPressed)", function()
		it(
			"la pression du joueur juste après celle d'une Plopette est refusée (recharge) ; l'heure publique « prête » est posée ; 8 s plus tard, acceptée",
			function()
				local w = boot()
				local p = Brains.join(w, 1, {
					profile = Brains.profile(
						w,
						{ squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 200 } } }
					),
				})
				standAt(w, p, "2")
				local data = w.DS.get(p)
				local now = w.Clock.now()
				local patches = #w.h:sentTo(p, "RanchPatch")
				w.Squishy.helperPressed(p, "2", now)
				expect(w.Squishy.readyAt(p, "2")).toBe(now + w.Balance.Press.Cooldown)
				local coins = data.coins
				expect(w.Squishy.press(p, "2", now, nil)).toBe(false)
				expect(data.coins).toBe(coins)
				-- état public : « pas prêt jusqu'à now + 8 » envoyé au tick suivant (RanchPatch groupé)
				Brains.frames(w, 1)
				local ready = nil
				local sent = w.h:sentTo(p, "RanchPatch")
				for i = patches + 1, #sent do
					for _, op in sent[i][1].ops do
						if op.uid == "2" and op.op == "update" then
							ready = op.rec.ready
						end
					end
				end
				expect(ready).toBe(now + w.Balance.Press.Cooldown)
				-- la recharge passée : la pression du joueur est acceptée
				Brains.frames(w, 80)
				expect(w.Squishy.press(p, "2", w.Clock.now(), nil)).toBe(true)
				expect(data.coins > coins).toBe(true)
				clean(w)
			end
		)

		it(
			"entrées bizarres : uid inconnu, NaN, joueur parti, squishy au Dodo (recharge seule, rien de publié) : aucune erreur, rien de gardé",
			function()
				local w = boot()
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 200, at = "dodo" } },
					}),
				})
				Brains.frames(w, 2)
				local now = w.Clock.now()
				w.Squishy.helperPressed(p, "zz", now)
				w.Squishy.helperPressed(p, 5 :: any, now)
				w.Squishy.helperPressed(p, "1", 0 / 0)
				w.Squishy.helperPressed(p, "1", math.huge)
				w.Squishy.helperPressed("joueur" :: any, "1", now)
				expect(w.Squishy.readyAt(p, "zz")).toBe(0)
				expect(w.Squishy.readyAt(p, "1")).toBe(0)
				-- squishy au Dodo : recharge, aucune opération publique (il n'est pas dessiné au ranch)
				local patches = #w.h:sentTo(p, "RanchPatch")
				w.Squishy.helperPressed(p, "2", now)
				expect(w.Squishy.readyAt(p, "2")).toBe(now + w.Balance.Press.Cooldown)
				Brains.frames(w, 1)
				local sent = w.h:sentTo(p, "RanchPatch")
				for i = patches + 1, #sent do
					for _, op in sent[i][1].ops do
						expect(op.uid ~= "2").toBe(true)
					end
				end
				-- joueur parti : rien n'est retenu pour lui
				Bots.leave(p)
				w.h:settle(2)
				w.Squishy.helperPressed(p, "1", now)
				expect(w.Squishy.readyAt(p, "1")).toBe(0)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SquishyService v2 › squishy occupé (busy)", function()
		it(
			"busy : vrai pour les deux jumeaux d'une fusion (FuseMenu) jusqu'à la fusion, et pour un squishy en fuite ; faux sinon",
			function()
				local w = boot()
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						squishies = {
							{ s = 1, z = 100, bf = 1 },
							{ s = 5, z = 60 },
							{ s = 5, z = 60 },
							{ s = 6, z = 70 },
						},
					}),
				})
				Bots.place(p, Brains.atRanch(w, p, 0, 30))
				Brains.frames(w, 2)
				for _, uid in { "1", "2", "3", "4" } do
					expect(w.Squishy.busy(p, uid)).toBe(false)
				end
				fire(w, "FuseMenu", p, "2", "3")
				expect(w.Squishy.busy(p, "2")).toBe(true)
				expect(w.Squishy.busy(p, "3")).toBe(true)
				expect(w.Squishy.busy(p, "4")).toBe(false)
				Brains.frames(w, 6) -- 0,6 s > 0,4 s : fusionnés
				expect(w.fused).toBe(1)
				expect(w.Squishy.busy(p, "2")).toBe(false)
				expect(w.Squishy.busy(p, "3")).toBe(false)
				-- en fuite (Rush) : occupé ; de retour : libre
				w.Squishy.setEscaping(p, "4", true)
				expect(w.Squishy.busy(p, "4")).toBe(true)
				w.Squishy.setEscaping(p, "4", false)
				expect(w.Squishy.busy(p, "4")).toBe(false)
				-- entrées bizarres : faux, aucune erreur
				expect(w.Squishy.busy(p, 7 :: any)).toBe(false)
				expect(w.Squishy.busy(p, "zz")).toBe(false)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SquishyService v2 › héros protégé pendant son spectacle (D6)", function()
		it(
			"progression v2.0 : pendant son spectacle, Sell, Release, FuseMenu, FuseAll et le lancer qui fusionne sont refusés (feedback.waitingSplorch, rien ne bouge) ; acceptés après",
			function()
				local w = boot({ flags = V2 })
				local hero = Brains.join(w, 1, {
					profile = heroProfile(w, {
						{ s = 4, z = 50 }, -- 4 : à vendre, puis à relâcher
						{ s = 5, z = 60 }, -- 5, 6 : jumeaux (FuseMenu)
						{ s = 5, z = 60 },
						{ s = 6, z = 70 }, -- 7 : lancé sur son jumeau 8 du Bassin
						{ s = 6, z = 70, at = "pool" },
						{ s = 7, z = 80 }, -- 9 : seul de son espèce
					}),
				})
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				local data = w.DS.get(hero)
				fire(w, "GrandSplorch", hero, false, "3")
				expect(untilShow(w, hero)).toBe(true)
				expect(w.Economy.prestigeV2(hero)).toBe(true)
				expect(w.Economy.prestigeBusy(hero)).toBe(true)
				local before = #data.released
				local fame = data.fame
				-- vente, relâche, fusions : refusées, un Feedback neutre chacune, rien ne bouge
				for _, case in
					{
						{ "Sell", { "4" }, true },
						{ "Release", { "4" }, true },
						{ "FuseMenu", "5", "6" },
						{ "FuseAll" },
					}
				do
					local n = #feedbacks(hero)
					fire(w, case[1], hero, table.unpack(case, 2))
					local keys = feedbacks(hero)
					expect({ intent = case[1], n = #keys - n, key = keys[#keys] }).toEqual({
						intent = case[1],
						n = 1,
						key = "feedback.waitingSplorch",
					})
				end
				expect(data.squishies["4"] ~= nil).toBe(true)
				expect(#data.released).toBe(before)
				expect(data.fame).toBe(fame)
				expect(w.Squishy.busy(hero, "5")).toBe(false)
				expect(jobsOf(w, hero)).toBe(0)
				-- lancer sur un jumeau du Bassin : refusé, le squishy reste porté (prendre reste permis)
				standAt(w, hero, "7")
				fire(w, "PickUp", hero, "7")
				expect(w.Squishy.carried(hero)).toBe("7")
				standPool(w, hero)
				local n = #feedbacks(hero)
				fire(w, "Throw", hero)
				expect(w.Squishy.carried(hero)).toBe("7")
				expect(#feedbacks(hero)).toBe(n + 1)
				expect(feedbacks(hero)[n + 1]).toBe("feedback.waitingSplorch")
				expect(data.squishies["7"].at).toBe("pen")
				expect(jobsOf(w, hero)).toBe(0)
				expect(w.fused).toBe(0)
				fire(w, "PutDown", hero)
				-- le spectacle fini (prestige appliqué) : tout est accepté de nouveau
				for _ = 1, 300 do
					if not w.Economy.prestigeBusy(hero) then
						break
					end
					Brains.frames(w, 1)
				end
				expect(w.Economy.prestigeBusy(hero)).toBe(false)
				expect(data.R).toBe(2)
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				fire(w, "Sell", hero, { "4" }, true)
				expect(data.squishies["4"]).toBeNil()
				fire(w, "Release", hero, { "9" }, true)
				expect(data.squishies["9"]).toBeNil()
				expect(#data.released).toBe(before + 1)
				fire(w, "FuseMenu", hero, "5", "6")
				expect(w.Squishy.busy(hero, "5")).toBe(true)
				Brains.frames(w, 6)
				expect(w.fused).toBe(1)
				standAt(w, hero, "7")
				fire(w, "PickUp", hero, "7")
				standPool(w, hero)
				fire(w, "Throw", hero)
				expect(w.Squishy.carried(hero)).toBeNil()
				Brains.frames(w, 6)
				expect(w.fused).toBe(2)
				expect(w.Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)

		it(
			"« Tout fusionner » commencé avant le spectacle : aucune paire de plus pendant le spectacle, la suite après",
			function()
				local w = boot({ flags = V2 })
				local hero = Brains.join(w, 1, {
					profile = heroProfile(w, {
						{ s = 5, z = 60 },
						{ s = 5, z = 60 },
						{ s = 6, z = 60 },
						{ s = 6, z = 60 },
						{ s = 7, z = 60 },
						{ s = 7, z = 60 },
						{ s = 8, z = 60 },
						{ s = 8, z = 60 },
					}),
				})
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				fire(w, "FuseAll", hero)
				for _ = 1, 20 do
					if w.fused >= 1 then
						break
					end
					Brains.frames(w, 1)
				end
				expect(w.fused).toBe(1)
				fire(w, "GrandSplorch", hero, false, "2")
				expect(untilShow(w, hero)).toBe(true)
				-- l'échéance déjà posée avant le spectacle peut finir ; ensuite, aucune nouvelle
				local empty = false
				local guard = 0
				while w.Economy.prestigeBusy(hero) and guard < 300 do
					local jobs = jobsOf(w, hero)
					if empty then
						expect(jobs).toBe(0)
					end
					empty = empty or jobs == 0
					Brains.frames(w, 1)
					guard += 1
				end
				expect(empty).toBe(true)
				expect(w.Economy.prestigeBusy(hero)).toBe(false)
				expect(w.fused <= 2).toBe(true)
				-- après le spectacle : le plan reprend jusqu'au bout (4 paires)
				Brains.frames(w, 40)
				expect(w.fused).toBe(4)
				expect(jobsOf(w, hero)).toBe(0)
				expect(w.Invariants.profile(w.DS.get(hero))).toEqual({})
				clean(w)
			end
		)

		it(
			"Petit Splorch : pendant son animation (2,5 s), la vente est refusée ; après, acceptée",
			function()
				local w = boot({ flags = V2 })
				local hero = Brains.join(w, 1, {
					profile = heroProfile(w, { { s = 4, z = 50 } }, function(d)
						d.bestR = 5
						d.unlocksSeen = 5
					end),
				})
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				local data = w.DS.get(hero)
				fire(w, "GrandSplorch", hero, false, "3")
				expect(data.R).toBe(2) -- Petit Splorch : appliqué tout de suite, hors file
				expect(w.Economy.prestigeBusy(hero)).toBe(true)
				local n = #feedbacks(hero)
				fire(w, "Sell", hero, { "4" }, true)
				expect(data.squishies["4"] ~= nil).toBe(true)
				expect(feedbacks(hero)[n + 1]).toBe("feedback.waitingSplorch")
				Brains.frames(w, 30)
				expect(w.Economy.prestigeBusy(hero)).toBe(false)
				fire(w, "Sell", hero, { "4" }, true)
				expect(data.squishies["4"]).toBeNil()
				clean(w)
			end
		)

		it(
			"chemin de la v1.3 (profil v1, interrupteurs coupés) : vente et fusion pendant son spectacle acceptées, comme aujourd'hui",
			function()
				local w = boot({ v1 = true })
				local hero = Brains.join(w, 1, {
					profile = heroProfile(w, { { s = 4, z = 50 }, { s = 5, z = 60 }, { s = 5, z = 60 } }),
				})
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				local data = w.DS.get(hero)
				expect(data.version).toBe(1)
				fire(w, "GrandSplorch", hero, false, "3")
				expect(untilShow(w, hero)).toBe(true)
				expect(w.Economy.prestigeV2(hero)).toBe(false)
				fire(w, "Sell", hero, { "4" }, true)
				expect(data.squishies["4"]).toBeNil()
				fire(w, "FuseMenu", hero, "5", "6")
				expect(w.Squishy.busy(hero, "5")).toBe(true)
				Brains.frames(w, 150)
				expect(w.fused).toBe(1)
				expect(data.R).toBe(2)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SquishyService v2 › N1 : ce qui est débloqué suit le Record R", function()
		-- tirages de la Cuve (contexte de Odds.roll) : capturés sans rien changer au tirage
		local function captureRolls(w)
			local rolls = {}
			local original = w.Odds.roll
			w.Odds.roll = function(stream, ctx)
				if type(ctx) == "table" and ctx.families ~= nil then
					table.insert(rolls, ctx)
				end
				return original(stream, ctx)
			end
			return rolls
		end

		-- une goutte de la Cuve tout de suite (2 s d'éclosion) ; rend l'intervalle posé dans le même tick
		-- (minuteur reparti : floor(now + intervalle + 0,5))
		local function hatchNow(w, p, rolls)
			local data = w.DS.get(p)
			data.vat.fillAt = 1
			for _ = 1, 60 do
				Brains.frames(w, 1)
				if #rolls >= 1 and data.vat.fillAt > 1 then
					return data.vat.fillAt - w.Clock.now()
				end
			end
			return -1
		end

		it(
			"après Prestige.apply(« ascend ») (RecordR ouvert) : niveau et intervalle de la Cuve, familles et 3e place de Meilleur Ami suivent le Record R, pas r = 0",
			function()
				local w = boot({ flags = V2 })
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						R = 15,
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 200 } },
						edit = function(d)
							d.bestR = 15
							d.unlocksSeen = 15
						end,
					}),
				})
				Bots.place(p, Brains.atRanch(w, p, 0, 30))
				Brains.frames(w, 2)
				local data = w.DS.get(p)
				local _, report = w.Economy.applyPrestige(p, "ascend")
				expect(report ~= nil and report.applied).toBe(true)
				expect({ R = data.R, bestR = data.bestR, A = data.ascend }).toEqual({
					R = 0,
					bestR = 15,
					A = 1,
				})
				local rolls = captureRolls(w)
				local interval = hatchNow(w, p, rolls)
				local want = w.Formulas.vatInterval(15, false)
				expect(math.abs(interval - want) <= 0.51).toBe(true)
				expect(math.abs(interval - w.Formulas.vatInterval(0, false)) > 10).toBe(true)
				expect(#rolls).toBe(1)
				local level = w.Formulas.vatLevel(15)
				expect({ q = rolls[1].quality, n = rolls[1].nozzles }).toEqual({
					q = level.quality,
					n = level.nozzles,
				})
				expect(rolls[1].families).toEqual(w.Odds.unlockedFamilies(15))
				local Tables = w.h:require(L .. "Util.Tables")
				expect(Tables.deepEqual(w.Odds.unlockedFamilies(0), w.Odds.unlockedFamilies(15))).toBe(false)
				-- 3e place de Meilleur Ami (Record R ≥ 10) : ouverte, r = 0 n'y change rien
				fire(w, "SetBestFriend", p, "2", 3)
				expect(data.squishies["2"].bf).toBe(3)
				expect(w.Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)

		it("profil v1 (serveur v1, interrupteurs coupés) : tout suit R, exactement comme avant", function()
			for _, case in { { R = 2, slot3 = false }, { R = 12, slot3 = true } } do
				local w = boot({ v1 = true })
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						R = case.R,
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 200 } },
					}),
				})
				Bots.place(p, Brains.atRanch(w, p, 0, 30))
				Brains.frames(w, 2)
				local data = w.DS.get(p)
				expect(data.version).toBe(1)
				local rolls = captureRolls(w)
				local interval = hatchNow(w, p, rolls)
				expect(math.abs(interval - w.Formulas.vatInterval(case.R, false)) <= 0.51).toBe(true)
				expect(#rolls).toBe(1)
				expect(rolls[1].quality).toBe(w.Formulas.vatLevel(case.R).quality)
				expect(rolls[1].families).toEqual(w.Odds.unlockedFamilies(case.R))
				fire(w, "SetBestFriend", p, "2", 3)
				expect({ R = case.R, slot3 = data.squishies["2"].bf == 3 }).toEqual({
					R = case.R,
					slot3 = case.slot3,
				})
				clean(w)
			end
		end)
	end)

	-- =========================================================================================
	describe("SquishyService v2 › tenues v2.0 (D21)", function()
		it(
			"profil v2 : partyHat possédé une fois : portée par un squishy, refusée au 2e (notOwned) ; polkaBow donnée par grantOutfit ; non possédée : notOwned",
			function()
				local w = boot()
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 200 }, { s = 3, z = 300 } },
						edit = function(d)
							d.outfits.owned.partyHat = 1
						end,
					}),
				})
				Brains.frames(w, 2)
				local data = w.DS.get(p)
				fire(w, "EquipOutfit", p, "partyHat", "2")
				expect(data.squishies["2"].o).toBe("partyHat")
				fire(w, "EquipOutfit", p, "partyHat", "3")
				expect(data.squishies["3"].o).toBe("")
				expect(feedbacks(p)[#feedbacks(p)]).toBe("feedback.notOwned")
				fire(w, "EquipOutfit", p, "starGlasses", "3")
				expect(data.squishies["3"].o).toBe("")
				expect(feedbacks(p)[#feedbacks(p)]).toBe("feedback.notOwned")
				expect(w.Squishy.grantOutfit(p, "polkaBow", 1)).toBe(1)
				fire(w, "EquipOutfit", p, "polkaBow", "3")
				expect(data.squishies["3"].o).toBe("polkaBow")
				expect(w.Squishy.grantOutfit(p, "buildersCrown", 1)).toBe(1)
				expect(w.Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)

		it(
			"profil v1 : tenues v2.0 inconnues (refus muet, aucune tenue donnée) : exactement comme avant",
			function()
				local w = boot({ v1 = true })
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 200 } },
						edit = function(d)
							d.outfits.owned.partyHat = 1
						end,
					}),
				})
				Brains.frames(w, 2)
				local data = w.DS.get(p)
				local n = #feedbacks(p)
				fire(w, "EquipOutfit", p, "partyHat", "2")
				expect(data.squishies["2"].o).toBe("")
				expect(#feedbacks(p)).toBe(n)
				expect(w.Squishy.grantOutfit(p, "polkaBow", 1)).toBe(0)
				expect(data.outfits.owned.polkaBow).toBeNil()
				-- tenue de la v1.3 : inchangée
				expect(w.Squishy.grantOutfit(p, "sweater", 1)).toBe(1)
				fire(w, "EquipOutfit", p, "sweater", "2")
				expect(data.squishies["2"].o).toBe("sweater")
				clean(w)
			end
		)
	end)
end
