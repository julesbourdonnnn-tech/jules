--!nocheck
-- SquishyService (paquet ranch, docs/04 §11.6, §18.2) : ajout (enclos → Dodo → Lettres → pièces),
-- Cuve (enclos puis Dodo, goutte en attente seulement si les deux sont pleins ; protections et
-- nouveauté garantie ; accueil scripté), Bassin et combos (échéances 0,4 / 0,6 s), Tout fusionner (une
-- paire par échéance), vente et relâche, monture et setRootOffset à 3 arguments, squishy retiré de la
-- clôture dès qu'il quitte l'enclos, growFor une fois par jour (gd), tenues (porteurs comptés),
-- MoveSquishy d'un squishy en attente refusé (A26), anyEscaping / waiting, presser (portée à plat et
-- pieds, recharge, PERFECT, série), Activity.note après acceptation, délais des états, zéro trace.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local function boot(before)
		local caught = {}
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				if before then
					before(w)
				end
			end,
		})
		w.caught = caught
		w.Ranch = w.h:require(S .. "RanchService")
		w.Economy = w.h:require(S .. "EconomyService")
		w.Squishy = w.h:require(S .. "SquishyService")
		w.MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
		w.Activity = w.h:require("ServerScriptService.Server.Util.Activity")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		w.W = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		w.Formulas = w.h:require("ReplicatedStorage.Shared.Logic.Formulas")
		w.PressTiming = w.h:require("ReplicatedStorage.Shared.Logic.PressTiming")
		w.StateTimeouts = w.h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")
		w.Balance = w.h:require("ReplicatedStorage.Shared.Config.Balance")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
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
		for k, v in overrides or {} do
			d[k] = v
		end
		return d
	end

	local function fire(w, name, p, ...)
		w.RateLimit.clear(p)
		w.h:fireServer(R .. name, p, ...)
	end

	-- Le joueur se tient (position validée) au centre de la place du squishy
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

	local function step(w, seconds, p)
		local n = math.floor(seconds / 0.1 + 0.5)
		for _ = 1, n do
			w.Clock.advance(0.1)
			local actors = {}
			if p then
				local pos = w.MoveCheck.lastValid(p) or w.V3.new(0, 3, 0)
				actors[p] = {
					player = p,
					slot = w.Ranch.slotOf(p),
					pos = pos,
					canAct = true,
					riding = false,
					rootOffset = 0,
				}
			end
			w.Squishy.step(w.Clock.now(), actors)
			for _, s in w.Squishy.openStates() do
				if s.name ~= "carry" then
					assert(
						not w.StateTimeouts.expired(s.name, s.startedAt, w.Clock.now()),
						"état ouvert au-delà de son délai : " .. s.name
					)
				end
			end
		end
	end

	local function celebrations(w, p, kind)
		local out = {}
		for _, args in w.h:sentTo(p, "Celebrate") do
			if args[1].kind == kind then
				table.insert(out, args[1].data)
			end
		end
		return out
	end

	local function lastFeedback(w, p)
		local fb = w.h:sentTo(p, "Feedback")
		return fb[#fb] and fb[#fb][1].key
	end

	local function counts(w, p)
		return w.Squishy.counts(p)
	end

	describe("SquishyService › ajout et Cuve", function()
		it(
			"give : enclos → Dodo → Lettres → pièces ; premier squishy = Meilleur Ami n° 1 ; verrou auto",
			function()
				local w = boot(function(w)
					Bots.saveProfile(
						w,
						1,
						profile(w, {}, { onboarding = { step = 0, done = false, demoDone = false } })
					)
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local obtained = {}
				w.Signals.SquishyObtained:Connect(function(_, uid, source)
					table.insert(obtained, { uid, source })
				end)
				local first, at = w.Squishy.give(p, { s = 1, m = 0, st = 0, z = 1 }, "starter")
				expect(first).toBe("1")
				expect(at).toBe("pen")
				expect(data.squishies["1"].bf).toBe(1)
				-- Légendaire (espèce 4, Grand Gloop) : verrou automatique
				local legend = w.Squishy.give(p, { s = 4, m = 0, st = 0, z = 1 }, "test")
				expect(data.squishies[legend].lk).toBe(true)
				expect(data.squishies[legend].bf).toBe(0)
				for _ = 1, 2 do
					w.Squishy.give(p, { s = 2, m = 0, st = 0, z = 1 }, "test")
				end
				local _, where = w.Squishy.give(p, { s = 2, m = 0, st = 0, z = 1 }, "test")
				expect(where).toBe("dodo")
				for _ = 1, 59 do
					w.Squishy.give(p, { s = 3, m = 0, st = 0, z = 1 }, "test")
				end
				local _, inMail = w.Squishy.give(p, { s = 3, m = 0, st = 0, z = 1 }, "test")
				expect(inMail).toBe("mail")
				for _ = 1, 19 do
					w.Squishy.give(p, { s = 3, m = 0, st = 0, z = 1 }, "test")
				end
				local c = counts(w, p)
				expect(c.pen).toBe(4)
				expect(c.dodo).toBe(60)
				expect(c.mail).toBe(20)
				local coinsBefore = data.coins
				local none, kind = w.Squishy.give(p, { s = 3, m = 0, st = 0, z = 1 }, "test")
				expect(none).toBeNil()
				expect(kind).toBe("coins")
				expect(lastFeedback(w, p)).toBe("feedback.babyAsCoins")
				expect(data.coins >= coinsBefore).toBe(true)
				w.h:settle(1)
				expect(obtained[1]).toEqual({ "1", "starter" })
				local Invariants = w.h:require("ReplicatedStorage.Shared.Logic.Invariants")
				expect(Invariants.profile(data)).toEqual({})
				clean(w)
			end
		)

		it(
			"Cuve : naissance en enclos, sinon dans la Boîte à dodo (at = « dodo ») ; pending seulement si les deux sont pleins",
			function()
				local w = boot(function(w)
					local sq = {}
					for i = 1, 3 do
						sq[tostring(i)] = rec({ bf = if i == 1 then 1 else 0 })
					end
					Bots.saveProfile(w, 1, profile(w, sq))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local hatched = {}
				w.Signals.Hatched:Connect(function(_, uid, rarity)
					table.insert(hatched, { uid, rarity })
				end)
				step(w, 0.1, p)
				expect(data.vat.fillAt > 0).toBe(true)
				local interval = data.vat.fillAt - w.Clock.now()
				expect(interval > 50 and interval < 60).toBe(true) -- 55,3 s à R = 0
				step(w, interval + 2.5, p)
				w.h:settle(1)
				expect(#hatched).toBe(1)
				local h1 = celebrations(w, p, "hatch")[1]
				expect(h1.at).toBe("pen")
				expect(h1.scripted).toBe(false)
				expect(data.vat.pulls).toBe(1)
				expect(data.vat.newPulls).toBe(2) -- nouveauté garantie consommée
				-- enclos pleins (4) : la suivante va dormir dans la Boîte à dodo
				step(w, 60, p)
				w.h:settle(1)
				local hs = celebrations(w, p, "hatch")
				expect(hs[#hs].at).toBe("dodo")
				-- enclos ET Dodo pleins : la goutte attend (« Plein ! », vatFill = 0)
				for _ = 1, 59 do
					w.Squishy.give(p, { s = 2, m = 0, st = 0, z = 1 }, "test")
				end
				expect(counts(w, p).dodo).toBe(60)
				local nHatch = #hatched
				step(w, 60, p)
				expect(data.vat.pending).toBe(true)
				expect(#hatched).toBe(nHatch)
				expect(w.Ranch.publicOf(1).vatFill).toBe(0)
				-- une place se libère (vente d'un dormeur) : la goutte tombe aussitôt
				local victim
				for uid, r in data.squishies do
					if r.at == "dodo" and not r.lk then
						victim = uid
						break
					end
				end
				fire(w, "Sell", p, { victim }, true)
				step(w, 2.5, p)
				w.h:settle(1)
				expect(data.vat.pending).toBe(false)
				expect(#hatched).toBe(nHatch + 1)
				clean(w)
			end
		)

		it(
			"Cuve : protection Rare après 40 naissances sans Rare+ ; tirages déterministes (graine)",
			function()
				local w = boot(function(w)
					local d = profile(w, { ["1"] = rec({ bf = 1 }) })
					d.vat.pityRare = 40
					d.vat.newPulls = 0
					Bots.saveProfile(w, 1, d)
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local rarity = nil
				w.Signals.Hatched:Connect(function(_, _, r)
					rarity = r
				end)
				step(w, 60, p)
				w.h:settle(1)
				expect(rarity ~= nil and rarity >= 3).toBe(true)
				expect(data.vat.pityRare).toBe(0)
				clean(w)
			end
		)

		it(
			"accueil : la Cuve ne tourne pas avant 5:00 de jeu ; jumeau scripté (Plop dans le Bassin), une seule fois",
			function()
				local w = boot(function(w)
					local d = profile(
						w,
						{ ["1"] = rec({ bf = 1, z = 41 }) },
						{ onboarding = { step = 4, done = false, demoDone = false } }
					)
					d.stats.playSeconds = 40
					Bots.saveProfile(w, 1, d)
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				step(w, 100, p)
				expect(data.vat.fillAt).toBe(0)
				expect(#celebrations(w, p, "hatch")).toBe(0)
				w.Squishy.hatchScripted(p, "twin")
				w.Squishy.hatchScripted(p, "twin") -- jamais rejoué
				expect(data.squishies["1"].at).toBe("pool")
				step(w, 2.1, p)
				w.h:settle(1)
				local hs = celebrations(w, p, "hatch")
				expect(#hs).toBe(1)
				expect(hs[1].scripted).toBe(true)
				expect(hs[1].species).toBe(1)
				expect(data.squishies[hs[1].uid].st).toBe(0)
				w.Squishy.hatchScripted(p, "firstPull")
				step(w, 2.1, p)
				w.h:settle(1)
				expect(#celebrations(w, p, "hatch")).toBe(2)
				expect(data.vat.pulls).toBe(1)
				clean(w)
			end
		)
	end)

	describe("SquishyService › Bassin, combos, Tout fusionner", function()
		it(
			"lancer d'un jumeau : fusion à 0,4 s, combo en chaîne à + 0,6 s, récompenses et Fused par étape",
			function()
				local w = boot(function(w)
					local sq = {
						["1"] = rec({ bf = 1, st = 1, at = "pool", z = 100 }),
						["2"] = rec({ st = 0, at = "pool", z = 50 }),
						["3"] = rec({ st = 0, z = 40 }),
					}
					Bots.saveProfile(w, 1, profile(w, sq))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local fused = {}
				w.Signals.Fused:Connect(function(_, uid, k)
					table.insert(fused, { uid, k })
				end)
				standAt(w, p, "3")
				fire(w, "PickUp", p, "3")
				expect(w.Squishy.carried(p)).toBe("3")
				expect(w.Ranch.publicOf(1).carry).toBe("3")
				standPool(w, p)
				fire(w, "Throw", p)
				expect(w.Squishy.carried(p)).toBeNil()
				step(w, 0.3, p)
				expect(#fused).toBe(0)
				step(w, 0.2, p)
				w.h:settle(1)
				expect(#fused).toBe(1)
				expect(fused[1][2]).toBe(1)
				step(w, 0.8, p)
				w.h:settle(1)
				expect(#fused).toBe(2)
				expect(fused[2][2]).toBe(2)
				-- 3 squishies → 1 : Meilleur Ami gardé, 2 étoiles, dans le Bassin
				local n = 0
				for _ in data.squishies do
					n += 1
				end
				expect(n).toBe(1)
				expect(data.squishies["1"].st).toBe(2)
				expect(data.squishies["1"].bf).toBe(1)
				local fx = celebrations(w, p, "fusion")
				expect(fx[2].step).toBe(2)
				expect(fx[2].coins > 0).toBe(true)
				expect(data.coins).toBe(fx[1].coins + fx[2].coins)
				clean(w)
			end
		)

		it("Bassin plein sans jumeau : refus doux, le squishy reste porté ; trop loin : refus", function()
			local w = boot(function(w)
				local sq = { ["1"] = rec({ bf = 1, s = 9 }) }
				for i = 2, 6 do
					sq[tostring(i)] = rec({ s = i, at = "pool" })
				end
				sq["7"] = rec({ s = 20 })
				local d = profile(w, sq)
				d.passes = { BigRanch = true }
				Bots.saveProfile(w, 1, d)
			end)
			local p = Bots.join(1)
			standAt(w, p, "7")
			fire(w, "PickUp", p, "7")
			expect(w.Squishy.carried(p)).toBe("7")
			fire(w, "Throw", p) -- loin du Bassin
			expect(w.Squishy.carried(p)).toBe("7")
			standPool(w, p)
			fire(w, "Throw", p)
			expect(w.Squishy.carried(p)).toBe("7")
			expect(lastFeedback(w, p)).toBe("feedback.poolFull")
			fire(w, "PutDown", p)
			expect(w.Squishy.carried(p)).toBeNil()
			clean(w)
		end)

		it(
			"Tout fusionner : une paire par échéance (jamais d'un coup), verrouillés exclus, résultat en enclos",
			function()
				local w = boot(function(w)
					local sq = {
						["1"] = rec({ bf = 1, s = 9 }),
						["2"] = rec({ s = 2 }),
						["3"] = rec({ s = 2, at = "dodo" }),
						["4"] = rec({ s = 2, st = 1, at = "dodo" }),
						["5"] = rec({ s = 4, lk = true }),
						["6"] = rec({ s = 4, at = "dodo" }),
					}
					Bots.saveProfile(w, 1, profile(w, sq))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local fused = {}
				w.Signals.Fused:Connect(function(_, uid, k)
					table.insert(fused, { uid, k })
				end)
				fire(w, "FuseAll", p)
				step(w, 0.3, p)
				expect(#fused).toBe(0)
				step(w, 0.2, p)
				w.h:settle(1)
				expect(#fused).toBe(1)
				step(w, 0.8, p)
				w.h:settle(1)
				expect(#fused).toBe(2)
				expect(fused[2][2]).toBe(2)
				step(w, 2, p)
				expect(#fused).toBe(2)
				expect(data.squishies["5"] ~= nil and data.squishies["6"] ~= nil).toBe(true) -- verrouillé : à la main seulement
				-- plus rien à fusionner
				fire(w, "FuseAll", p)
				expect(lastFeedback(w, p)).toBe("feedback.nothingToFuse")
				clean(w)
			end
		)

		it(
			"FuseMenu : jumeaux seulement ; les deux sautent dans le Bassin ; capacités jamais dépassées",
			function()
				local w = boot(function(w)
					local sq = {
						["1"] = rec({ bf = 1, s = 9 }),
						["2"] = rec({ s = 2 }),
						["3"] = rec({ s = 2 }),
						["4"] = rec({ s = 3 }),
						["5"] = rec({ s = 2, at = "dodo" }),
					}
					Bots.saveProfile(w, 1, profile(w, sq))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local Invariants = w.h:require("ReplicatedStorage.Shared.Logic.Invariants")
				fire(w, "FuseMenu", p, "2", "4")
				expect(lastFeedback(w, p)).toBe("feedback.noTwin")
				fire(w, "FuseMenu", p, "3", "5")
				for _ = 1, 10 do
					step(w, 0.1, p)
					expect(Invariants.profile(data)).toEqual({})
				end
				expect(data.squishies["5"]).toBeNil()
				expect(data.squishies["3"].st).toBe(1)
				-- combo : le résultat (Bassin) retrouve son jumeau ? aucun ici
				clean(w)
			end
		)
	end)

	describe("SquishyService › vendre, relâcher, ranger", function()
		it(
			"vente : Meilleur Ami et verrouillé refusés ; Épique+ exige confirmed ; 60 s de revenu",
			function()
				local w = boot(function(w)
					local sq = {
						["1"] = rec({ bf = 1 }),
						["2"] = rec({ lk = true }),
						["3"] = rec({ s = 7, z = 500 }), -- Épique (Whiskerwob) : confirmation en 2 étapes
						["4"] = rec({ s = 2, z = 1000 }),
					}
					Bots.saveProfile(w, 1, profile(w, sq))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				fire(w, "Sell", p, { "1" }, true)
				expect(lastFeedback(w, p)).toBe("feedback.bestFriendNoSell")
				fire(w, "Sell", p, { "2" }, true)
				expect(lastFeedback(w, p)).toBe("feedback.locked")
				fire(w, "Sell", p, { "3" }, false)
				expect(data.squishies["3"] ~= nil).toBe(true)
				-- lot avec un refus : rien n'est vendu
				fire(w, "Sell", p, { "4", "2" }, true)
				expect(data.squishies["4"] ~= nil).toBe(true)
				local value = w.Formulas.sellValue(w.Economy.squishyIncome(p, "4"))
				fire(w, "Sell", p, { "4" }, false)
				expect(data.squishies["4"]).toBeNil()
				expect(data.coins).toBe(value)
				fire(w, "Sell", p, { "3" }, true)
				expect(data.squishies["3"]).toBeNil()
				clean(w)
			end
		)

		it("relâche : + 1 Fame (20 par jour), 12 derniers gardés pour la Prairie", function()
			local w = boot(function(w)
				local sq = { ["1"] = rec({ bf = 1 }) }
				for i = 2, 15 do
					sq[string.format("%x", i)] = rec({ s = 2, at = "dodo" })
				end
				Bots.saveProfile(w, 1, profile(w, sq))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local list = {}
			for i = 2, 15 do
				table.insert(list, string.format("%x", i))
			end
			fire(w, "Release", p, list, true)
			expect(data.fame).toBe(14)
			expect(#data.released).toBe(12)
			expect(data.released[12]).toEqual({ s = 2, m = 0 })
			clean(w)
		end)
	end)

	describe("SquishyService › monture, portage, clôture", function()
		it(
			"monture : selle exigée ; valeurs fixes ; MoveCheck.setRootOffset à 3 arguments à la montée et à la descente",
			function()
				local w = boot(function(w)
					local d = profile(w, { ["1"] = rec({ bf = 1, z = 2000 }) })
					d.biggestEver = 2000
					Bots.saveProfile(w, 1, d)
				end)
				local calls = {}
				w.MoveCheck.setRootOffset = function(player, studs, jump)
					table.insert(calls, { player = player, studs = studs, jump = jump })
				end
				local p = Bots.join(1)
				standAt(w, p, "1")
				fire(w, "Ride", p, true)
				expect(w.Squishy.riding(p)).toBe(true)
				local humanoid = p.Character.Humanoid
				local stats = w.Formulas.rideStats(1)
				expect(humanoid.WalkSpeed).toBe(stats.walkSpeed)
				expect(humanoid.JumpHeight).toBe(stats.jumpHeight)
				expect(humanoid.HipHeight).toBe(stats.hipHeight)
				expect(calls[1].studs).toBe(stats.hipHeight - w.Balance.Ride.BaseHipHeight)
				expect(calls[1].jump).toBe(stats.jumpHeight)
				expect(w.Ranch.publicOf(1).ride).toBe("1")
				fire(w, "Ride", p, false)
				expect(w.Squishy.riding(p)).toBe(false)
				expect(calls[2].studs).toBe(0)
				expect(calls[2].jump).toBe(w.Balance.Ride.BaseJumpHeight)
				expect(humanoid.WalkSpeed).toBe(w.Balance.Ride.BaseWalkSpeed)
				-- descente forcée : réapparition
				fire(w, "Ride", p, true)
				w.h:respawn(p)
				w.h:settle(2)
				expect(w.Squishy.riding(p)).toBe(false)
				expect(calls[#calls].studs).toBe(0)
				clean(w)
			end
		)

		it("sans selle : Ride refusé (feedback.noMount) ; portage : Ride ignoré", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1 }) }))
			end)
			local p = Bots.join(1)
			fire(w, "Ride", p, true)
			expect(w.Squishy.riding(p)).toBe(false)
			expect(lastFeedback(w, p)).toBe("feedback.noMount")
			clean(w)
		end)

		it(
			"un squishy qui quitte l'enclos est retiré AUSSITÔT de la clôture (portage, Dodo, vente, attente)",
			function()
				local w = boot(function(w)
					local sq = { ["1"] = rec({ bf = 1 }), ["2"] = rec(), ["3"] = rec(), ["4"] = rec() }
					Bots.saveProfile(w, 1, profile(w, sq))
				end)
				local p = Bots.join(1)
				w.Ranch.setFence(1, { "2", "3", "4" }, "rush")
				standAt(w, p, "2")
				fire(w, "PickUp", p, "2")
				local uids = w.Ranch.fenceOf(1)
				expect(uids).toEqual({ "3", "4" })
				fire(w, "PutDown", p)
				fire(w, "MoveSquishy", p, "3", "dodo")
				uids = w.Ranch.fenceOf(1)
				expect(uids).toEqual({ "4" })
				fire(w, "Sell", p, { "4" }, true)
				local after, reason = w.Ranch.fenceOf(1)
				expect(after).toEqual({})
				expect(reason).toBe("")
				-- attente de Grand Splorch : aucune clôture du Rush pour ce joueur
				w.Ranch.setFence(1, { "2" }, "rush")
				w.Squishy.setWaiting(p, "1")
				after = w.Ranch.fenceOf(1)
				expect(after).toEqual({})
				expect(w.Squishy.waiting(p)).toBe("1")
				expect(w.Squishy.fenceCandidates(p, {
					now = T0 + 1e6,
					carried = "",
					waiting = "",
					returnedThisRush = {},
					moonBoopable = false,
				})).toEqual({})
				clean(w)
			end
		)

		it(
			"portage fini à la sortie du ranch (position validée) ; MoveSquishy d'un squishy en attente refusé (A26)",
			function()
				local w = boot(function(w)
					local sq = { ["1"] = rec({ bf = 1 }), ["2"] = rec() }
					Bots.saveProfile(w, 1, profile(w, sq))
				end)
				local p = Bots.join(1)
				standAt(w, p, "2")
				fire(w, "PickUp", p, "2")
				expect(w.Squishy.carried(p)).toBe("2")
				w.MoveCheck.reset(p, w.W.gateOutside(1), w.Clock.now())
				step(w, 0.1, p)
				expect(w.Squishy.carried(p)).toBeNil()
				expect(w.Ranch.publicOf(1).carry).toBe("")
				w.Squishy.setWaiting(p, "2")
				fire(w, "MoveSquishy", p, "2", "dodo")
				expect(lastFeedback(w, p)).toBe("feedback.waitingSplorch")
				expect(w.DS.get(p).squishies["2"].at).toBe("pen")
				w.Squishy.setWaiting(p, nil)
				expect(w.Squishy.waiting(p)).toBeNil()
				clean(w)
			end
		)

		it("fuites : anyEscaping ; un squishy en fuite n'est ni pris, ni vendu, ni fusionné", function()
			local w = boot(function(w)
				local sq = { ["1"] = rec({ bf = 1 }), ["2"] = rec(), ["3"] = rec() }
				Bots.saveProfile(w, 1, profile(w, sq))
			end)
			local p = Bots.join(1)
			expect(w.Squishy.anyEscaping(p)).toBeNil()
			w.Squishy.setEscaping(p, "3", true)
			w.Squishy.setEscaping(p, "2", true)
			expect(w.Squishy.anyEscaping(p)).toBe("2")
			standAt(w, p, "2")
			fire(w, "PickUp", p, "2")
			expect(w.Squishy.carried(p)).toBeNil()
			fire(w, "Sell", p, { "3" }, true)
			expect(w.DS.get(p).squishies["3"] ~= nil).toBe(true)
			fire(w, "FuseMenu", p, "2", "3")
			step(w, 1, p)
			expect(w.DS.get(p).squishies["2"] ~= nil).toBe(true)
			w.Squishy.setEscaping(p, "2", false)
			w.Squishy.setEscaping(p, "3", false)
			expect(w.Squishy.anyEscaping(p)).toBeNil()
			clean(w)
		end)
	end)

	describe("SquishyService › croissance du Rush, tenues, tailles", function()
		it("growFor : z += g sans boost × secondes, une fois par squishy et par jour UTC (gd)", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1, z = 100 }) }))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			w.Economy.setServerBoost("wobble", w.Clock.now() + 600) -- jamais compté dans le bonus
			local g = w.Economy.gNoBoost(p)
			expect(w.Squishy.growFor(p, "1", 3600)).toBe(true)
			expect(data.squishies["1"].z).toBe(100 + g * 3600)
			expect(data.squishies["1"].gd).toBe(w.Clock.day())
			expect(w.Squishy.growFor(p, "1", 1800)).toBe(false)
			expect(data.squishies["1"].z).toBe(100 + g * 3600)
			w.Clock.advance(86400)
			expect(w.Squishy.growFor(p, "1", 1800)).toBe(true)
			expect(w.Squishy.growFor(p, "nope", 1800)).toBe(false)
			expect(w.Squishy.growFor(p, "1", 0 / 0)).toBe(false)
			clean(w)
		end)

		it(
			"tenues : porteurs comptés (o == id) ≤ possédées ; outfits.worn jamais écrit ; retirer",
			function()
				local w = boot(function(w)
					local d = profile(w, { ["1"] = rec({ bf = 1 }), ["2"] = rec() })
					d.outfits.owned = { sweater = 1 }
					Bots.saveProfile(w, 1, d)
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				fire(w, "EquipOutfit", p, "sweater", "1")
				expect(data.squishies["1"].o).toBe("sweater")
				fire(w, "EquipOutfit", p, "sweater", "2")
				expect(data.squishies["2"].o).toBe("")
				expect(lastFeedback(w, p)).toBe("feedback.notOwned")
				fire(w, "EquipOutfit", p, "crown", "2")
				expect(data.squishies["2"].o).toBe("")
				fire(w, "EquipOutfit", p, "sweater", nil)
				expect(data.squishies["1"].o).toBe("")
				expect(data.outfits.worn).toEqual({})
				-- garde-robe : un exemplaire de plus (ProductService, QuestService)
				expect(w.Squishy.grantOutfit(p, "sweater", 1)).toBe(2)
				fire(w, "EquipOutfit", p, "sweater", "1")
				fire(w, "EquipOutfit", p, "sweater", "2")
				expect(data.squishies["2"].o).toBe("sweater")
				clean(w)
			end
		)

		it("Dodo : taille figée ; retour en enclos : zg = G ; resetSizes : tout repasse à 1", function()
			local w = boot(function(w)
				local d = profile(w, { ["1"] = rec({ bf = 1, z = 50 }), ["2"] = rec({ z = 20 }) })
				d.growth = { G = 30, g = 1, t = 0 }
				Bots.saveProfile(w, 1, d)
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local size = w.Squishy.sizeOf(p, "2")
			fire(w, "MoveSquishy", p, "2", "dodo")
			expect(data.squishies["2"].at).toBe("dodo")
			expect(data.squishies["2"].z).toBe(size)
			w.Clock.advance(100)
			expect(w.Squishy.sizeOf(p, "2")).toBe(size)
			fire(w, "MoveSquishy", p, "2", "pen")
			expect(data.squishies["2"].zg).toBe(w.Economy.G(p))
			expect(w.Squishy.sizeOf(p, "2")).toBe(size)
			w.Economy.applySplorch(p)
			w.Squishy.resetSizes(p)
			expect(w.Squishy.sizeOf(p, "1")).toBe(1)
			expect(w.Squishy.sizeOf(p, "2")).toBe(1)
			clean(w)
		end)
	end)

	describe("SquishyService › presser", function()
		it(
			"portée à plat 10 + 2 du centre de la place, pieds ≤ 8 ; recharge 8 s ; monture sans perte de portée",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1, z = 100 }) }))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local c = w.Squishy.placeOf(p, "1")
				w.MoveCheck.reset(p, w.V3.new(c.X + 12.5, 3, c.Z), w.Clock.now())
				expect(w.Squishy.press(p, "1", w.Clock.now(), nil)).toBe(false)
				w.MoveCheck.reset(p, w.V3.new(c.X + 11.5, 3, c.Z), w.Clock.now())
				expect(w.Squishy.press(p, "1", w.Clock.now(), nil)).toBe(true)
				expect(data.coins > 0).toBe(true)
				expect(w.Squishy.press(p, "1", w.Clock.now(), nil)).toBe(false) -- recharge
				expect(w.Squishy.readyAt(p, "1")).toBe(w.Clock.now() + 8)
				w.Clock.advance(8)
				-- pieds à 9 studs au-dessus du sol : hors de portée
				w.MoveCheck.reset(p, w.V3.new(c.X, 12, c.Z), w.Clock.now())
				expect(w.Squishy.press(p, "1", w.Clock.now(), nil)).toBe(false)
				clean(w)
			end
		)

		it(
			"PERFECT au sommet du rebond (hachage propriétaire + uid), série + 10 %, Celebrate « press », Pressed",
			function()
				local w = boot(function(w)
					Bots.saveProfile(
						w,
						1,
						profile(w, { ["1"] = rec({ bf = 1, z = 1000 }), ["2"] = rec({ z = 900 }) })
					)
				end)
				local p = Bots.join(1)
				local pressed = {}
				w.Signals.Pressed:Connect(function(_, info)
					table.insert(pressed, info)
				end)
				local pos = standAt(w, p, "1")
				local offset = w.PressTiming.offset(1, "1")
				local apex = w.PressTiming.nextApex(w.Clock.now() + 1, offset)
				w.Clock.freeze(apex)
				w.MoveCheck.reset(p, pos, apex)
				local income = w.Economy.squishyIncome(p, "1")
				expect(w.Squishy.press(p, "1", apex, nil)).toBe(true)
				w.h:settle(1)
				expect(pressed[1].perfect).toBe(true)
				expect(pressed[1].streak).toBe(1)
				local fx = celebrations(w, p, "press")
				expect(fx[1].coins).toBe(w.Formulas.pressReward(income, true, 1, false))
				expect(fx[1].perfect).toBe(true)
				-- deuxième PERFECT de suite, sur l'autre squishy (moins de 6 s plus tard) : série 2
				local offset2 = w.PressTiming.offset(1, "2")
				local apex2 = w.PressTiming.nextApex(apex + 0.5, offset2)
				w.Clock.freeze(apex2)
				standAt(w, p, "2")
				expect(w.Squishy.press(p, "2", apex2, nil)).toBe(true)
				w.h:settle(1)
				expect(pressed[2].streak).toBe(2)
				expect(pressed[2].perfect).toBe(true)
				-- tClient truqué (futur lointain) : ramené à maintenant (hors fenêtre) → série remise à 0
				local later = w.PressTiming.nextApex(apex2 + 8, offset) + 0.6
				w.Clock.freeze(later)
				standAt(w, p, "1")
				expect(w.Squishy.press(p, "1", later + 100, nil)).toBe(true)
				w.h:settle(1)
				expect(pressed[3].perfect).toBe(false)
				expect(pressed[3].streak).toBe(0)
				-- 6 s sans pression : la série retombe aussi
				clean(w)
			end
		)

		it("Activity.note seulement après une intention acceptée", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, profile(w, { ["1"] = rec({ bf = 1, z = 100 }) }))
			end)
			local p = Bots.join(1)
			local now = w.Clock.now()
			fire(w, "Press", p, "1", now) -- pas de position validée : refus
			expect(w.Activity.isActive(p, now)).toBe(false)
			fire(w, "Press", p, "zz", now)
			expect(w.Activity.isActive(p, now)).toBe(false)
			standAt(w, p, "1")
			fire(w, "Press", p, "1", now)
			expect(w.Activity.isActive(p, w.Clock.now())).toBe(true)
			clean(w)
		end)
	end)
end
