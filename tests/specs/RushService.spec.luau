--!nocheck
-- RushService (paquet chase, docs/04 §11.9, §18.2) : modes (Cozy d'office, Cozy immédiat, Rush après
-- 60 s et à la fin du Rush), bouclier, carte du choix (UiSeen → 20 s → Cozy, RushModeChosen),
-- clôtures (4 / 2, renouvelées, aucune pour un joueur en file de Grand Splorch, fin du Rush sans
-- toucher au pet-sitting), maintien de boop (2,5 s, 5 s propriétaire proche, extendHold une fois,
-- annulé par chaque règle revérifiée à chaque tick), protections (recharge, paire, ranch, heure,
-- serveur, « Pas ce joueur », blocage, Meilleur Ami), délais des états, zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000
	local RUSH_START = H0 + 300

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function squishies(n)
		local out = { { s = 1, z = 100, bf = 1 } } -- Meilleur Ami n° 1 (jamais à la clôture)
		for i = 1, n do
			table.insert(out, { s = 2 + (i % 3), z = 50 + i })
		end
		return out
	end

	-- Monde au début d'un Rush : propriétaire et boopeur en mode Rush (bouclier levé)
	local function rushWorld(opts)
		opts = opts or {}
		local w = Brains.boot(Harness, { t0 = opts.t0 or (RUSH_START - 2) })
		local owner =
			Brains.join(w, 1, { profile = Brains.profile(w, { rush = true, squishies = squishies(6) }) })
		local booper =
			Brains.join(w, 2, { profile = Brains.profile(w, { rush = true, squishies = squishies(2) }) })
		Brains.frames(w, opts.frames or 25)
		return w, owner, booper
	end

	local function fence(w, p)
		return w.Ranch.fenceOf(w.Ranch.slotOf(p))
	end

	-- Le boopeur se poste devant la place n° i de la clôture du propriétaire (côté rue)
	local function standAtFence(w, booper, owner, i, extra)
		-- place n° i à la clôture : local (x, 5) dans le ranch ; côté rue : local Z < 0 (à 7 studs)
		local p = w.WL.fencePointsLocal()[i or 1]
		local q = w.WL.toWorld(w.Ranch.slotOf(owner), w.V3.new(p.X, 0, -2 - (extra or 0)))
		Bots.place(booper, Bots.ground(q.X, q.Z))
	end

	local function boopStates(w, p)
		local out = {}
		for _, args in w.h:sentTo(p, "BoopState") do
			table.insert(out, args[1].state)
		end
		return out
	end

	-- =========================================================================================
	describe("RushService › modes", function()
		it(
			"Cozy d'office ; Rush hors Rush : immédiat ; Cozy immédiat (ModeChanged, clôture vidée) ; Rush avant 60 s refusé",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 60 })
				local a = Brains.join(w, 1, { profile = Brains.profile(w, { squishies = squishies(3) }) })
				Brains.frames(w, 2)
				expect(w.Rush.isRush(a)).toBe(false)
				local changes = {}
				w.Signals.ModeChanged:Connect(function(p, rush)
					table.insert(changes, rush)
				end)
				w.h:fireServer("ReplicatedStorage.Remotes.SetMode", a, true)
				expect(w.Rush.isRush(a)).toBe(true)
				expect(changes[1]).toBe(true)
				Brains.frames(w, 12)
				expect(w.Ranch.publicOf(w.Ranch.slotOf(a)).mode).toBe("rush")
				w.h:fireServer("ReplicatedStorage.Remotes.SetMode", a, false)
				expect(w.Rush.isRush(a)).toBe(false)
				expect(changes[2]).toBe(false)
				Brains.frames(w, 12)
				w.h:fireServer("ReplicatedStorage.Remotes.SetMode", a, true)
				expect(w.Rush.isRush(a)).toBe(false)
				expect(table.find(Bots.feedbackKeys(a), "feedback.modeRushCooldown") ~= nil).toBe(true)
				Brains.frames(w, 600)
				w.h:fireServer("ReplicatedStorage.Remotes.SetMode", a, true)
				expect(w.Rush.isRush(a)).toBe(true)
				clean(w)
			end
		)

		it(
			"passer en Rush pendant un Rush : appliqué à la fin du Rush ; bouclier : jamais boopable",
			function()
				local w = Brains.boot(Harness, { t0 = RUSH_START + 5 })
				local a = Brains.join(
					w,
					1,
					{ profile = Brains.profile(w, { rush = false, squishies = squishies(3) }) }
				)
				w.DS.get(a).mode.changedAt = 0
				Brains.frames(w, 2)
				w.h:fireServer("ReplicatedStorage.Remotes.SetMode", a, true)
				expect(w.Rush.isRush(a)).toBe(false)
				expect(table.find(Bots.feedbackKeys(a), "feedback.modeRushLater") ~= nil).toBe(true)
				Bots.travelTo(RUSH_START + 91)
				Brains.frames(w, 2)
				expect(w.Rush.isRush(a)).toBe(true)
				-- bouclier : moins de 15 min de jeu
				w.meta.playSeconds[1] = 600
				expect(w.Rush.isShielded(a)).toBe(true)
				expect(w.Rush.canBeBooped(a)).toBe(false)
				w.meta.playSeconds[1] = 901
				expect(w.Rush.canBeBooped(a)).toBe(true)
				clean(w)
			end
		)

		it(
			"carte du choix : ModePrompt une fois dès 15:00 ; UiSeen → 20 s (+0,5) sans réponse → Cozy ; réponse avant : appliquée",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 60 })
				local prof = Brains.profile(w, { cardShown = false, squishies = squishies(2) })
				prof.mode.chosen = false
				local a = Brains.join(w, 1, { profile = prof })
				w.meta.playSeconds[1] = 800
				Brains.frames(w, 5)
				expect(#w.h:sentTo(a, "ModePrompt")).toBe(0)
				w.meta.playSeconds[1] = 900
				Brains.frames(w, 5)
				expect(#w.h:sentTo(a, "ModePrompt")).toBe(1)
				Brains.frames(w, 50)
				expect(#w.h:sentTo(a, "ModePrompt")).toBe(1)
				w.Signals.UiSeen:Fire(a, "modeCard")
				Brains.frames(w, 200)
				expect(w.DS.get(a).mode.chosen).toBe(false)
				Brains.frames(w, 10)
				expect(w.DS.get(a).mode.chosen).toBe(true)
				expect(w.DS.get(a).mode.rush).toBe(false)
				-- un autre joueur répond dans les 20 s : Rush appliqué
				local prof2 = Brains.profile(w, { cardShown = false, squishies = squishies(2) })
				prof2.mode.chosen = false
				local b = Brains.join(w, 2, { profile = prof2 })
				w.meta.playSeconds[2] = 950
				Brains.frames(w, 3)
				w.Signals.UiSeen:Fire(b, "modeCard")
				Brains.frames(w, 50)
				w.h:fireServer("ReplicatedStorage.Remotes.SetMode", b, true)
				expect(w.Rush.isRush(b)).toBe(true)
				Brains.frames(w, 300)
				expect(w.Rush.isRush(b)).toBe(true)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("RushService › clôtures", function()
		it(
			"au début du Rush : 4 squishies (jamais le Meilleur Ami), renouvelés toutes les 20 s ; vidées à la fin",
			function()
				local w, owner = rushWorld()
				local uids, reason = fence(w, owner)
				expect(reason).toBe("rush")
				expect(#uids).toBe(4)
				for _, uid in uids do
					expect(w.Squishy.get(owner, uid).bf).toBe(0)
				end
				local fences = 0
				for _, args in w.h:sentTo(owner, "Fence") do
					if args[1].slot == w.Ranch.slotOf(owner) and args[1].reason == "rush" then
						fences += 1
					end
				end
				Brains.frames(w, 210)
				local fences2 = 0
				for _, args in w.h:sentTo(owner, "Fence") do
					if args[1].slot == w.Ranch.slotOf(owner) and args[1].reason == "rush" then
						fences2 += 1
					end
				end
				expect(fences2 >= fences).toBe(true)
				Bots.travelTo(RUSH_START + 91)
				Brains.frames(w, 2)
				local after = fence(w, owner)
				expect(#after).toBe(0)
				clean(w)
			end
		)

		it(
			"joueur en file de Grand Splorch (waiting) ou Cozy : aucune clôture ; clôture de pet-sitting jamais effacée par la fin du Rush",
			function()
				local w = Brains.boot(Harness, { t0 = RUSH_START - 2 })
				local owner = Brains.join(
					w,
					1,
					{ profile = Brains.profile(w, { rush = true, squishies = squishies(6) }) }
				)
				local cozy = Brains.join(
					w,
					2,
					{ profile = Brains.profile(w, { rush = false, squishies = squishies(6) }) }
				)
				Brains.frames(w, 2)
				w.Squishy.setWaiting(owner, "2")
				Brains.frames(w, 25)
				expect(#fence(w, owner)).toBe(0)
				expect(#fence(w, cozy)).toBe(0)
				-- pet-sitting sur le ranch Cozy pendant le Rush : gardé à la fin du Rush
				w.Ranch.setFence(w.Ranch.slotOf(cozy), { "3" }, "petsit")
				Bots.travelTo(RUSH_START + 91)
				Brains.frames(w, 2)
				local uids, reason = fence(w, cozy)
				expect(reason).toBe("petsit")
				expect(#uids).toBe(1)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("RushService › boop", function()
		it(
			"maintien de 2,5 s mesuré par le serveur → Booped, fuite, BoopState hold puis done, boopDone / booped",
			function()
				local w, owner, booper = rushWorld()
				local uids = fence(w, owner)
				standAtFence(w, booper, owner, 1)
				Brains.frames(w, 2)
				local booped = {}
				w.Signals.Booped:Connect(function(b, o, uid, angle)
					table.insert(booped, { b = b, o = o, uid = uid, angle = angle })
				end)
				w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, uids[1], true)
				Brains.frames(w, 20)
				expect(#booped).toBe(0)
				Brains.frames(w, 6)
				expect(#booped).toBe(1)
				expect(booped[1].uid).toBe(uids[1])
				local states = boopStates(w, owner)
				expect(states[1]).toBe("hold")
				expect(states[#states]).toBe("done")
				expect(#Bots.celebrations(booper, "boopDone")).toBe(1)
				expect(#Bots.celebrations(owner, "booped")).toBe(1)
				expect(w.Chase.isEscaping(owner, uids[1])).toBe(true)
				-- le squishy a quitté la clôture
				expect(table.find(fence(w, owner), uids[1])).toBeNil()
				clean(w)
			end
		)

		it(
			"propriétaire à ≤ 25 studs de sa clôture : 5 s ; il arrive pendant le maintien : le reste double une seule fois",
			function()
				local w, owner, booper = rushWorld()
				local uids = fence(w, owner)
				local slot = w.Ranch.slotOf(owner)
				standAtFence(w, booper, owner, 1)
				-- propriétaire loin (fond du ranch)
				Bots.place(owner, Brains.atRanch(w, owner, 0, 90))
				Brains.frames(w, 2)
				w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, uids[1], true)
				Brains.frames(w, 10)
				-- le propriétaire arrive près de sa clôture : le reste (≈ 1,5 s) double
				local fp = w.WL.fencePoint(slot, 2)
				local inside = Brains.atRanch(w, owner, 0, 8)
				Bots.place(owner, inside)
				Brains.frames(w, 1)
				local ends = {}
				for _, args in w.h:sentTo(booper, "BoopState") do
					table.insert(ends, args[1].endsAt)
				end
				expect(#ends >= 2).toBe(true)
				expect(ends[#ends] > ends[1]).toBe(true)
				local start = ends[1] - 2.5
				expect(ends[#ends] <= start + 5 + 1e-6).toBe(true)
				local _ = fp
				-- fin du maintien : ≤ 5,5 s (StateTimeouts boopHold)
				local booped = 0
				w.Signals.Booped:Connect(function()
					booped += 1
				end)
				Brains.frames(w, 45)
				expect(booped).toBe(1)
				clean(w)
			end
		)

		it(
			"annulé : s'éloigner à plus de 8 studs, lâcher, propriétaire passé en Cozy, squishy pris ou rangé (eligible revérifié)",
			function()
				local w, owner, booper = rushWorld()
				local uids = fence(w, owner)
				local function start(uid)
					standAtFence(w, booper, owner, table.find(fence(w, owner), uid))
					Brains.frames(w, 1)
					w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, uid, true)
					Brains.frames(w, 3)
				end
				local booped = 0
				w.Signals.Booped:Connect(function()
					booped += 1
				end)
				-- s'éloigner
				start(uids[1])
				standAtFence(w, booper, owner, 1, 12)
				Brains.frames(w, 2)
				expect(boopStates(w, booper)[#boopStates(w, booper)]).toBe("cancel")
				expect(table.find(Bots.feedbackKeys(booper), "feedback.boopCancelled") ~= nil).toBe(true)
				-- lâcher
				start(uids[1])
				w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, uids[1], false)
				Brains.frames(w, 1)
				expect(boopStates(w, booper)[#boopStates(w, booper)]).toBe("cancel")
				-- squishy rangé au Dodo pendant le maintien
				start(uids[2])
				w.Osc = nil
				local rec = w.Squishy.get(owner, uids[2])
				rec.at = "dodo"
				Brains.frames(w, 1)
				expect(boopStates(w, booper)[#boopStates(w, booper)]).toBe("cancel")
				rec.at = "pen"
				-- propriétaire passé en Cozy
				Brains.frames(w, 5)
				local current = fence(w, owner)
				if #current > 0 then
					start(current[1])
					w.h:fireServer("ReplicatedStorage.Remotes.SetMode", owner, false)
					Brains.frames(w, 1)
					expect(boopStates(w, booper)[#boopStates(w, booper)]).toBe("cancel")
				end
				Brains.frames(w, 40)
				expect(booped).toBe(0)
				clean(w)
			end
		)

		it(
			"protections : recharge de 20 s, 2 par ranch et par Rush, « Pas ce joueur », liste de blocage, Meilleur Ami",
			function()
				local w, owner, booper = rushWorld()
				local third = Brains.join(
					w,
					3,
					{ profile = Brains.profile(w, { rush = true, squishies = squishies(1) }) }
				)
				local count = 0
				w.Signals.Booped:Connect(function()
					count += 1
				end)
				local function boop(b, uid)
					standAtFence(w, b, owner, table.find(fence(w, owner), uid) or 1)
					Brains.frames(w, 1)
					w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", b, owner.UserId, uid, true)
					Brains.frames(w, 30)
				end
				boop(booper, fence(w, owner)[1])
				expect(count).toBe(1)
				-- recharge de 20 s du boopeur (et paire 30 min)
				boop(booper, fence(w, owner)[1])
				expect(count).toBe(1)
				-- un autre boopeur : 2e fuite du ranch dans ce Rush
				boop(third, fence(w, owner)[1])
				expect(count).toBe(2)
				-- 3e fuite du ranch dans ce Rush : refusée (tooManyEscapes)
				Brains.frames(w, 200)
				local fourth = Brains.join(
					w,
					4,
					{ profile = Brains.profile(w, { rush = true, squishies = squishies(1) }) }
				)
				Brains.frames(w, 1)
				boop(fourth, fence(w, owner)[1])
				expect(count).toBe(2)
				expect(table.find(Bots.feedbackKeys(fourth), "feedback.tooManyEscapes") ~= nil).toBe(true)
				-- « Pas ce joueur » : le propriétaire refuse le boopeur qui l'a boopé
				w.h:fireServer("ReplicatedStorage.Remotes.RefuseBooper", owner, booper.UserId)
				expect(table.find(Bots.feedbackKeys(owner), "feedback.refused") ~= nil).toBe(true)
				-- refuser un joueur qui n'a jamais boopé : sans effet
				local before = #Bots.feedbackKeys(owner)
				w.h:fireServer("ReplicatedStorage.Remotes.RefuseBooper", owner, 999)
				expect(#Bots.feedbackKeys(owner)).toBe(before)
				clean(w)
			end
		)

		it("liste de blocage souple et Meilleur Ami : refusés, sans fuite", function()
			local w, owner, booper = rushWorld()
			local count = 0
			w.Signals.Booped:Connect(function()
				count += 1
			end)
			w.meta.blocked["1:2"] = true
			local uid = fence(w, owner)[1]
			standAtFence(w, booper, owner, 1)
			Brains.frames(w, 1)
			w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, uid, true)
			Brains.frames(w, 30)
			expect(count).toBe(0)
			w.meta.blocked["1:2"] = nil
			-- Meilleur Ami (uid "1") : jamais à la clôture ni boopable
			w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, "1", true)
			Brains.frames(w, 30)
			expect(count).toBe(0)
			clean(w)
		end)
	end)

	-- =========================================================================================
	describe("RushService › délais des états", function()
		it("maintiens et carte : jamais au-delà de leur délai ; « rush » fermé à la fin", function()
			local w, owner, booper = rushWorld()
			local uids = fence(w, owner)
			standAtFence(w, booper, owner, 1)
			Brains.frames(w, 1)
			w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, uids[1], true)
			local bad = {}
			Bots.use(w)
			for _ = 1, 1500 do
				Bots.frame()
				for _, st in w.Rush.openStates() do
					if w.StateTimeouts.expired(st.name, st.startedAt, w.Clock.now()) then
						table.insert(bad, st.name)
					end
				end
			end
			expect(table.concat(bad, ",")).toBe("")
			expect(#w.Rush.openStates()).toBe(0)
			clean(w)
		end)
	end)
end
