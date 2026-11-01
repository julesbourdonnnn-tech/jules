--!nocheck
-- SquishyService : défauts trouvés par la revue adverse du paquet ranch (chaque test a d'abord échoué).
--   1. Règlement AVANT tout changement de la collection (naissance, fusion, vente, relâche, Dodo ↔
--      enclos, Lettres) : l'intervalle passé est intégré avec les squishies qui l'ont vraiment vécu
--      (docs/04 §11.5 : chaque intervalle avec le contexte de son début).
--   2. Lancer un jumeau dans un Bassin plein : le Bassin ne dépasse jamais ses places (invariant 3),
--      même pendant les 0,4 s de la fusion ; jumeau déjà pris par une fusion : Bassin plein = refus.
--   3. Résultat d'une fusion de deux squishies du Dodo : les places libérées comptent (jamais aux
--      Lettres quand le Dodo a une place, jamais plus de 20 Lettres).
--   4. Pass Grand Ranch retiré pendant la session : le surplus va dormir au Dodo, taille gardée.
--   5. Squishy en attente de Grand Splorch monté : descente ; attente sans fin fermée par son délai.
--   6. Pet-sitting : seulement depuis le côté rue de la clôture.
--   7. La Cuve ne tourne que joueur présent : le minuteur est mis en PAUSE au départ (reprend au
--      retour), une goutte en train d'éclore au départ n'est jamais perdue.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local function boot(before)
		local caught, timedOut = {}, {}
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function(name)
					table.insert(timedOut, name)
				end
				if before then
					before(w)
				end
			end,
		})
		w.caught, w.timedOut = caught, timedOut
		w.Ranch = w.h:require(S .. "RanchService")
		w.Economy = w.h:require(S .. "EconomyService")
		w.Squishy = w.h:require(S .. "SquishyService")
		w.Monetization = w.h:require(S .. "MonetizationService")
		w.MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		w.W = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		w.Formulas = w.h:require("ReplicatedStorage.Shared.Logic.Formulas")
		w.Invariants = w.h:require("ReplicatedStorage.Shared.Logic.Invariants")
		w.StateTimeouts = w.h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")
		w.Balance = w.h:require("ReplicatedStorage.Shared.Config.Balance")
		return w
	end

	local function clean(w, allowedWarning)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		local warnings = {}
		for _, line in w.h:warnings() do
			if not (allowedWarning and string.find(line, allowedWarning, 1, true)) then
				table.insert(warnings, line)
			end
		end
		expect(table.concat(warnings, "\n")).toBe("")
	end

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 0, z = 10, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	local function profile(w, squishies, overrides)
		local n = 0
		for uid in squishies or {} do
			n = math.max(n, tonumber(uid, 36))
		end
		local d = Bots.profile(w, {
			onboarding = { step = 11, done = true, demoDone = true },
			squishies = squishies or {},
			nextUid = n + 1,
		})
		d.stats.playSeconds = 10000
		d.tiles.seen = 15
		-- records de l'Étagère au-dessus des tailles des tests : aucun palier franchi pendant un règlement
		for s = 1, #d.trophies do
			d.trophies[s] = 1e9
		end
		d.biggestEver = 1e9
		for k, v in overrides or {} do
			d[k] = v
		end
		return d
	end

	local function fire(w, name, p, ...)
		w.RateLimit.clear(p)
		w.h:fireServer(R .. name, p, ...)
	end

	local function near(a, b, rel)
		local scale = math.max(1, math.abs(a), math.abs(b))
		return math.abs(a - b) <= (rel or 1e-9) * scale
	end

	local function standAt(w, p, uid)
		local c = w.Squishy.placeOf(p, uid)
		local pos = w.V3.new(c.X, 3, c.Z)
		w.MoveCheck.reset(p, pos, w.Clock.now())
		return pos
	end

	local function standPool(w, p)
		local c = w.W.anchor(w.Ranch.slotOf(p), "pool")
		local pos = w.V3.new(c.X + 6, 3, c.Z)
		w.MoveCheck.reset(p, pos, w.Clock.now())
		return pos
	end

	local function lastFeedback(w, p)
		local fb = w.h:sentTo(p, "Feedback")
		return fb[#fb] and fb[#fb][1].key
	end

	local function poolCount(data)
		local n = 0
		for _, r in data.squishies do
			if r.at == "pool" then
				n += 1
			end
		end
		return n
	end

	-- Pot attendu si l'intervalle [growth.t ; now] est intégré avec la collection d'AVANT le geste
	local function settledBefore(w, p)
		local data = w.DS.get(p)
		w.Economy.refresh(p)
		local growth0 = table.clone(data.growth)
		local ctx = w.Economy.incomeCtx(p)
		local K, S1 = w.Formulas.ranchIncome(data.squishies, growth0.G, ctx)
		local pot0 = data.pot
		return function(t1)
			return pot0 + w.Formulas.potGain(K, S1, growth0, growth0.t, t1)
		end
	end

	describe("SquishyService (revue) › règlement avant chaque changement de la collection", function()
		local function base(w)
			return profile(w, {
				["1"] = rec({ bf = 1, s = 1, st = 1, z = 1000 }),
				["2"] = rec({ s = 5, z = 400 }),
				["3"] = rec({ s = 9, z = 5000, at = "dodo" }),
				["4"] = rec({ s = 1, st = 1, z = 800 }),
				["5"] = rec({ s = 12, z = 3000, at = "mail" }),
			}, { tiles = { snack = 0, decor = 0, pens = 4, cozyBed = false, seen = 15 } })
		end

		it("Dodo → enclos : l'absent du Dodo ne rapporte rien pour l'intervalle passé", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, base(w))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local expected = settledBefore(w, p)
			w.Clock.advance(20)
			fire(w, "MoveSquishy", p, "3", "pen")
			expect(data.squishies["3"].at).toBe("pen")
			expect(near(data.pot, expected(w.Clock.now()))).toBe(true)
			clean(w)
		end)

		it("enclos → Dodo : le squishy rangé rapporte jusqu'au geste", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, base(w))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local expected = settledBefore(w, p)
			w.Clock.advance(20)
			fire(w, "MoveSquishy", p, "2", "dodo")
			expect(data.squishies["2"].at).toBe("dodo")
			expect(near(data.pot, expected(w.Clock.now()))).toBe(true)
			clean(w)
		end)

		it("vente et relâche : le squishy parti rapporte jusqu'au geste", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, base(w))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local expected = settledBefore(w, p)
			w.Clock.advance(20)
			fire(w, "Sell", p, { "2" }, false)
			expect(data.squishies["2"]).toBeNil()
			expect(near(data.pot, expected(w.Clock.now()))).toBe(true)
			local expected2 = settledBefore(w, p)
			w.Clock.advance(15)
			fire(w, "Release", p, { "4" }, false)
			expect(data.squishies["4"]).toBeNil()
			expect(near(data.pot, expected2(w.Clock.now()))).toBe(true)
			clean(w)
		end)

		it("naissance (give) et Lettres : le nouveau venu ne rapporte rien pour le passé", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, base(w))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local expected = settledBefore(w, p)
			w.Clock.advance(20)
			local uid, at = w.Squishy.give(p, { s = 20, m = 0, st = 0, z = 50000 }, "test")
			expect(at).toBe("pen")
			expect(uid ~= nil).toBe(true)
			expect(near(data.pot, expected(w.Clock.now()))).toBe(true)
			local expected2 = settledBefore(w, p)
			w.Clock.advance(25)
			fire(w, "ClaimMail", p, "5")
			expect(data.squishies["5"].at).toBe("pen")
			expect(near(data.pot, expected2(w.Clock.now()))).toBe(true)
			clean(w)
		end)

		it("fusion (FuseMenu) : les deux parents rapportent jusqu'à la fusion", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, base(w))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local expected = settledBefore(w, p)
			w.Clock.advance(20)
			fire(w, "FuseMenu", p, "1", "4")
			w.Clock.advance(0.5)
			w.Squishy.step(w.Clock.now(), {})
			expect(data.squishies["1"] == nil or data.squishies["4"] == nil).toBe(true)
			expect(near(data.pot, expected(w.Clock.now()))).toBe(true)
			clean(w)
		end)
	end)

	describe("SquishyService (revue) › capacités du Bassin, du Dodo et des Lettres", function()
		local function fullPool(w)
			local sq = { ["1"] = rec({ bf = 1, s = 1 }) }
			for i = 2, 5 do
				sq[tostring(i)] = rec({ s = i + 1, at = "pool" })
			end
			sq["1"].at = "pool"
			sq["6"] = rec({ s = 1 }) -- jumeau du Plop du Bassin
			sq["7"] = rec({ s = 1 }) -- un autre jumeau
			return profile(w, sq, { tiles = { snack = 0, decor = 0, pens = 4, cozyBed = false, seen = 15 } })
		end

		it(
			"jumeau lancé dans un Bassin plein : jamais plus de places que le Bassin, fusion quand même",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, fullPool(w))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				expect(poolCount(data)).toBe(5)
				standAt(w, p, "6")
				fire(w, "PickUp", p, "6")
				expect(w.Squishy.carried(p)).toBe("6")
				standPool(w, p)
				fire(w, "Throw", p)
				expect(w.Squishy.carried(p)).toBeNil()
				-- pendant les 0,4 s de la fusion : capacités respectées (invariant n° 3)
				expect(poolCount(data) <= 5).toBe(true)
				expect(w.Invariants.profile(data)).toEqual({})
				local fused = {}
				w.Signals.Fused:Connect(function(_, uid, k)
					table.insert(fused, { uid, k })
				end)
				w.Clock.advance(0.5)
				w.Squishy.step(w.Clock.now(), {})
				w.h:settle(1)
				expect(#fused).toBe(1)
				expect(poolCount(data) <= 5).toBe(true)
				expect(w.Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)

		it(
			"Bassin plein dont le seul jumeau fusionne déjà : refus doux, le squishy reste porté",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, fullPool(w))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				standAt(w, p, "6")
				fire(w, "PickUp", p, "6")
				standPool(w, p)
				fire(w, "Throw", p)
				expect(w.Squishy.carried(p)).toBeNil()
				-- dans les 0,4 s : un 3e Plop lancé ne trouve aucun jumeau libre et le Bassin est plein
				standAt(w, p, "7")
				fire(w, "PickUp", p, "7")
				expect(w.Squishy.carried(p)).toBe("7")
				standPool(w, p)
				fire(w, "Throw", p)
				expect(w.Squishy.carried(p)).toBe("7")
				expect(lastFeedback(w, p)).toBe("feedback.poolFull")
				expect(poolCount(data) <= 5).toBe(true)
				expect(w.Invariants.profile(data)).toEqual({})
				w.Clock.advance(0.5)
				w.Squishy.step(w.Clock.now(), {})
				expect(poolCount(data) <= 5).toBe(true)
				expect(w.Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)

		it(
			"Tout fusionner : deux jumeaux du Dodo plein, enclos et Lettres pleins → résultat au Dodo",
			function()
				local w = boot(function(w)
					local sq = {}
					local n = 0
					local function add(r)
						n += 1
						sq[tostring(n)] = r
					end
					add(rec({ bf = 1, s = 9, lk = true }))
					for i = 1, 3 do
						add(rec({ s = 9 + i, lk = true }))
					end
					-- Dodo plein : deux jumeaux (non verrouillés) + 58 verrouillés
					add(rec({ s = 2, at = "dodo" }))
					add(rec({ s = 2, at = "dodo" }))
					for _ = 1, 58 do
						add(rec({ s = 3, at = "dodo", lk = true }))
					end
					for _ = 1, 20 do
						add(rec({ s = 4, at = "mail", lk = true }))
					end
					Bots.saveProfile(w, 1, profile(w, sq))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local c = w.Squishy.counts(p)
				expect(c.pen).toBe(4)
				expect(c.dodo).toBe(60)
				expect(c.mail).toBe(20)
				fire(w, "FuseAll", p)
				for _ = 1, 10 do
					w.Clock.advance(0.1)
					w.Squishy.step(w.Clock.now(), {})
				end
				c = w.Squishy.counts(p)
				expect(c.mail).toBe(20)
				expect(c.dodo).toBe(59)
				expect(w.Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)

		it(
			"pass Grand Ranch retiré pendant la session : le surplus dort au Dodo, sa taille est gardée",
			function()
				local w = boot(function(w)
					local sq = {}
					for i = 1, 10 do
						sq[tostring(i)] = rec({ s = i, z = 1, zg = 0, bf = if i == 1 then 1 else 0 })
					end
					local d = profile(w, sq, {
						passes = { BigRanch = true },
						growth = { G = 1e6, g = 1, t = 0 },
					})
					Bots.saveProfile(w, 1, d)
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local sizes = {}
				for uid in data.squishies do
					sizes[uid] = w.Squishy.sizeOf(p, uid)
				end
				expect(w.Squishy.counts(p).penCapacity).toBe(10)
				-- Roblox répond que le pass n'est plus possédé (remboursement) : MonetizationService le retire
				data.passes.BigRanch = nil
				w.Monetization.PassRevoked:Fire(p, "BigRanch")
				w.h:settle(2)
				local c = w.Squishy.counts(p)
				expect(c.penCapacity).toBe(4)
				expect(c.pen + c.pool <= c.penCapacity).toBe(true)
				expect(c.dodo).toBe(6)
				for uid in data.squishies do
					expect(near(w.Squishy.sizeOf(p, uid), sizes[uid], 1e-6)).toBe(true)
				end
				expect(w.Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)
	end)

	describe("SquishyService (revue) › attente du Grand Splorch, pet-sitting", function()
		it("squishy monté qui part en attente de Grand Splorch : le joueur descend", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1, z = 5000 }) }))
			end)
			local p = Bots.join(1)
			fire(w, "Ride", p, true)
			expect(w.Squishy.riding(p)).toBe(true)
			w.Squishy.setWaiting(p, "1")
			expect(w.Squishy.riding(p)).toBe(false)
			clean(w)
		end)

		it("attente jamais fermée par SplorchService : fermée par son délai (file + spectacle)", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 2 }) }))
			end)
			local p = Bots.join(1)
			w.Squishy.setWaiting(p, "2")
			expect(w.Squishy.waiting(p)).toBe("2")
			local limit = w.StateTimeouts.seconds("splorchQueue") + w.StateTimeouts.seconds("spectacle")
			local elapsed = 0
			while elapsed < limit + 1 do
				w.Clock.advance(1)
				elapsed += 1
				w.Squishy.step(w.Clock.now(), {})
				for _, s in w.Squishy.openStates() do
					if s.name ~= "carry" then
						expect(
							w.StateTimeouts.expired(
								s.name,
								s.startedAt,
								w.Clock.now(),
								w.StateTimeouts.seconds("spectacle")
							)
						).toBe(false)
					end
				end
			end
			expect(w.Squishy.waiting(p)).toBeNil()
			expect(table.find(w.timedOut, "splorchQueue") ~= nil).toBe(true)
			clean(w)
		end)

		it("pet-sitting depuis l'intérieur du ranch (pas côté rue) : refusé", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 2 }) }))
				Bots.saveProfile(w, 2, profile(w, { ["1"] = rec({ bf = 1 }) }))
			end)
			local owner = Bots.join(1)
			local visitor = Bots.join(2)
			local slot = w.Ranch.slotOf(owner)
			w.Ranch.setFence(slot, { "2" }, "petsit")
			local point = w.W.fencePoint(slot, 1)
			-- 4 studs DANS le ranch, derrière la clôture (côté enclos)
			local inside = w.W.toWorld(slot, w.V3.new(w.W.toLocal(slot, point).X, 0, 4))
			w.MoveCheck.reset(visitor, w.V3.new(inside.X, 3, inside.Z), w.Clock.now())
			expect(w.Squishy.press(owner, "2", w.Clock.now(), visitor)).toBe(false)
			-- côté rue, à 4 studs : accepté
			local outside = w.W.toWorld(slot, w.V3.new(w.W.toLocal(slot, point).X, 0, -4))
			w.MoveCheck.reset(visitor, w.V3.new(outside.X, 3, outside.Z), w.Clock.now())
			expect(w.Squishy.press(owner, "2", w.Clock.now(), visitor)).toBe(true)
			clean(w)
		end)
	end)

	describe("SquishyService (revue) › la Cuve ne tourne que joueur présent (pause)", function()
		it(
			"départ à 20 s de la goutte : au retour, la goutte tombe 20 s plus tard (pas un intervalle entier)",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1 }) }))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				w.Squishy.step(w.Clock.now(), {})
				local interval = data.vat.fillAt - w.Clock.now()
				expect(interval > 30).toBe(true)
				-- joue jusqu'à 20 s de la goutte, puis part
				w.Clock.advance(interval - 20)
				w.Squishy.step(w.Clock.now(), {})
				Bots.leave(p)
				w.h:settle(3)
				-- revient une heure plus tard
				w.Clock.advance(3600)
				local p2 = Bots.join(1)
				local data2 = w.DS.get(p2)
				w.Squishy.step(w.Clock.now(), {})
				local left = data2.vat.fillAt - w.Clock.now()
				expect(left > 18 and left < 22).toBe(true)
				clean(w)
			end
		)

		it("départ pendant l'éclosion (2 s) : la goutte n'est pas perdue, elle éclot au retour", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1 }) }))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			w.Squishy.step(w.Clock.now(), {})
			local interval = data.vat.fillAt - w.Clock.now()
			w.Clock.advance(interval + 0.1)
			w.Squishy.step(w.Clock.now(), {}) -- la goutte tombe : éclosion dans 2 s
			local pulls = data.vat.pulls
			Bots.leave(p)
			w.h:settle(3)
			w.Clock.advance(600)
			local p2 = Bots.join(1)
			local data2 = w.DS.get(p2)
			expect(data2.vat.pulls).toBe(pulls)
			for _ = 1, 30 do
				w.Clock.advance(0.1)
				w.Squishy.step(w.Clock.now(), {})
			end
			expect(data2.vat.pulls).toBe(pulls + 1)
			clean(w)
		end)
	end)
end
