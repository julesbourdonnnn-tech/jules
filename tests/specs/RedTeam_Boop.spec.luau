--!nocheck
-- Contre-audit du BOOP RUSH (docs/04 §15, §17.1 g ; GDD §4.21.4), écrit comme des attaques :
--   * booper de loin (12 studs), depuis l'intérieur du ranch (repoussé), avec une racine truquée ;
--   * squishy pris (PickUp) pendant un maintien → annulé ; rangé au Dodo pendant un maintien → annulé ;
--   * booper son propre squishy, un ranch Cozy, un ranch sous bouclier, le Meilleur Ami, un squishy
--     absent de la clôture ;
--   * client qui n'envoie jamais « lâché » : le maintien finit à son heure (≤ 5,5 s) ;
--   * rafale de BoopHold sur plusieurs squishies : un seul maintien ; même paire au Rush suivant : refusé
--     (30 min) ; 10 fuites au plus sur le serveur.
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
		local out = { { s = 1, z = 100, bf = 1 } }
		for i = 1, n do
			table.insert(out, { s = 2 + (i % 3), z = 50 + i })
		end
		return out
	end

	local function world(extra)
		local w = Brains.boot(Harness, { t0 = RUSH_START - 2 })
		local owner =
			Brains.join(w, 1, { profile = Brains.profile(w, { rush = true, squishies = squishies(6) }) })
		local booper =
			Brains.join(w, 2, { profile = Brains.profile(w, { rush = true, squishies = squishies(1) }) })
		if extra then
			extra(w)
		end
		Brains.frames(w, 25)
		return w, owner, booper
	end

	local function fence(w, p)
		return w.Ranch.fenceOf(w.Ranch.slotOf(p))
	end

	local function standAt(w, booper, owner, i, back)
		local p = w.WL.fencePointsLocal()[i or 1]
		local q = w.WL.toWorld(w.Ranch.slotOf(owner), w.V3.new(p.X, 0, -2 - (back or 0)))
		Bots.place(booper, Bots.ground(q.X, q.Z))
	end

	local function counter(w)
		local box = { n = 0 }
		w.Signals.Booped:Connect(function()
			box.n += 1
		end)
		return box
	end

	local function hold(w, booper, owner, uid)
		w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, uid, true)
	end

	describe("RedTeam_Boop › distance et position", function()
		it(
			"de loin (12 studs côté rue) : refusé ; depuis l'intérieur du ranch : repoussé, refusé ; racine truquée : position validée",
			function()
				local w, owner, booper = world()
				local booped = counter(w)
				local uid = fence(w, owner)[1]
				standAt(w, booper, owner, 1, 10)
				Brains.frames(w, 2)
				hold(w, booper, owner, uid)
				Brains.frames(w, 30)
				expect(booped.n).toBe(0)
				-- dans le ranch, collé au squishy : l'intrus est repoussé hors du ranch
				local p = w.WL.fencePointsLocal()[1]
				local inside = w.WL.toWorld(w.Ranch.slotOf(owner), w.V3.new(p.X, 0, 6))
				Bots.place(booper, Bots.ground(inside.X, inside.Z))
				Brains.frames(w, 2)
				expect(w.WL.inRanch(w.Ranch.slotOf(owner), booper.Character.HumanoidRootPart.Position)).toBe(
					false
				)
				-- racine qui saute devant la clôture (sans placement serveur) : position validée inchangée
				standAt(w, booper, owner, 1, 40)
				Brains.frames(w, 40)
				local q = w.WL.toWorld(w.Ranch.slotOf(owner), w.V3.new(p.X, 0, -2))
				w.h:moveTo(booper, Bots.ground(q.X, q.Z))
				Brains.frames(w, 1)
				hold(w, booper, owner, uid)
				Brains.frames(w, 30)
				expect(booped.n).toBe(0)
				clean(w)
			end
		)
	end)

	describe("RedTeam_Boop › squishy qui quitte la clôture", function()
		it(
			"pris (PickUp) pendant le maintien → annulé ; rangé au Dodo pendant le maintien → annulé",
			function()
				local w, owner, booper = world()
				local booped = counter(w)
				-- propriétaire au milieu de son enclos (portée de PickUp), loin de sa clôture ? non : à 25+ studs
				local uids = fence(w, owner)
				standAt(w, booper, owner, table.find(fence(w, owner), uids[1]))
				Brains.frames(w, 2)
				hold(w, booper, owner, uids[1])
				Brains.frames(w, 5)
				-- le propriétaire prend le squishy (portée vérifiée par SquishyService depuis sa place)
				local place = w.Squishy.placeOf(owner, uids[1])
				if place then
					Bots.place(owner, Bots.ground(place.X, place.Z))
					Brains.frames(w, 1)
					w.h:fireServer("ReplicatedStorage.Remotes.PickUp", owner, uids[1])
				end
				Brains.frames(w, 30)
				expect(booped.n).toBe(0)
				if w.Squishy.carried(owner) ~= nil then
					w.h:fireServer("ReplicatedStorage.Remotes.PutDown", owner)
				end
				-- rangé au Dodo
				Brains.frames(w, 5)
				local current = fence(w, owner)
				if #current > 0 then
					standAt(w, booper, owner, 1)
					Brains.frames(w, 1)
					hold(w, booper, owner, current[1])
					Brains.frames(w, 5)
					w.h:fireServer("ReplicatedStorage.Remotes.MoveSquishy", owner, current[1], "dodo")
					Brains.frames(w, 30)
					expect(booped.n).toBe(0)
					expect(w.Squishy.get(owner, current[1]).at).toBe("dodo")
				end
				clean(w)
			end
		)
	end)

	describe("RedTeam_Boop › cibles interdites", function()
		it(
			"son propre squishy, un ranch Cozy, un ranch sous bouclier, le Meilleur Ami, un squishy absent de la clôture : refusés",
			function()
				local w, owner, booper = world(function(w)
					local cozy = Brains.join(
						w,
						3,
						{ profile = Brains.profile(w, { rush = false, squishies = squishies(4) }) }
					)
					local shielded = Brains.join(
						w,
						4,
						{ profile = Brains.profile(w, { rush = true, squishies = squishies(4) }) }
					)
					w.meta.playSeconds[4] = 100
					w.cozy, w.shielded = cozy, shielded
				end)
				local booped = counter(w)
				-- propre squishy (le propriétaire boope sa clôture)
				local uid = fence(w, owner)[1]
				standAt(w, owner, owner, 1)
				Brains.frames(w, 2)
				hold(w, owner, owner, uid)
				Brains.frames(w, 30)
				-- ranch Cozy / sous bouclier : aucune clôture, boop refusé
				expect(#fence(w, w.cozy)).toBe(0)
				expect(#fence(w, w.shielded)).toBe(0)
				standAt(w, booper, w.cozy, 1)
				Brains.frames(w, 1)
				hold(w, booper, w.cozy, "2")
				Brains.frames(w, 30)
				standAt(w, booper, w.shielded, 1)
				Brains.frames(w, 1)
				hold(w, booper, w.shielded, "2")
				Brains.frames(w, 30)
				-- Meilleur Ami, squishy absent de la clôture
				standAt(w, booper, owner, 1)
				Brains.frames(w, 1)
				hold(w, booper, owner, "1")
				Brains.frames(w, 30)
				local absent = nil
				for _, u in { "2", "3", "4", "5", "6", "7" } do
					if table.find(fence(w, owner), u) == nil then
						absent = u
					end
				end
				if absent then
					hold(w, booper, owner, absent)
					Brains.frames(w, 30)
				end
				expect(booped.n).toBe(0)
				clean(w)
			end
		)
	end)

	describe("RedTeam_Boop › temps et rafales", function()
		it(
			"client qui n'envoie jamais « lâché » : fin à son heure (2,5 s), état fermé avant 5,5 s ; rafale : un seul maintien",
			function()
				local w, owner, booper = world()
				local booped = counter(w)
				local uids = fence(w, owner)
				standAt(w, booper, owner, 1)
				Brains.frames(w, 2)
				for _, uid in uids do
					hold(w, booper, owner, uid)
				end
				local holds = 0
				for _, st in w.Rush.openStates() do
					if st.name == "boopHold" then
						holds += 1
					end
				end
				expect(holds).toBe(1)
				Brains.frames(w, 27)
				expect(booped.n).toBe(1)
				for _, st in w.Rush.openStates() do
					expect(st.name ~= "boopHold").toBe(true)
				end
				clean(w)
			end
		)

		it("même paire boopeur → ranch au Rush suivant (moins de 30 min) : refusé", function()
			local w, owner, booper = world()
			local booped = counter(w)
			standAt(w, booper, owner, 1)
			Brains.frames(w, 2)
			hold(w, booper, owner, fence(w, owner)[1])
			Brains.frames(w, 30)
			expect(booped.n).toBe(1)
			Bots.travelTo(RUSH_START + 600 + 1)
			Brains.frames(w, 25)
			standAt(w, booper, owner, 1)
			Brains.frames(w, 2)
			local uids = fence(w, owner)
			if #uids > 0 then
				hold(w, booper, owner, uids[1])
				Brains.frames(w, 30)
			end
			expect(booped.n).toBe(1)
			clean(w)
		end)
	end)
end
