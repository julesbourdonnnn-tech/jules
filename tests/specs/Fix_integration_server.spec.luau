--!nocheck
-- Intégration serveur (notes des paquets appliquées par l'équipe d'intégration) :
--   * note meta n° 3 : ChaseService mesure chaque tick et appelle DiagnosticsService.noteTick(ms) ;
--   * note meta n° 4 : analytique du GDD §16.3 envoyée par RushService (ModeAtSessionEnd,
--     CozyAfterBoop, RefuseBooper, PostBoopQuit, QuitBaseline) et SquishyService (HatchRarity,
--     MutationGot, ComboLength, RideStart) ;
--   * note client-panels n° 5 : AdminCommand("photo", "") bascule le mode photo (Diagnostics › Outils).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000
	local RUSH_START = H0 + 300
	local R = "ReplicatedStorage.Remotes."

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	-- événements personnalisés envoyés à AnalyticsService : { name, value, player }
	local function custom(w, name)
		local out = {}
		for _, c in w.h.log.analytics do
			if c.method == "LogCustomEvent" and c.args[2] == name then
				table.insert(out, { player = c.args[1], value = c.args[3], fields = c.args[4] })
			end
		end
		return out
	end

	local function squishies(n)
		local out = { { s = 1, z = 100, bf = 1 } }
		for i = 1, n do
			table.insert(out, { s = 2 + (i % 3), z = 50 + i })
		end
		return out
	end

	describe("Intégration serveur › Diagnostics : durée du tick", function()
		it(
			"chaque tick de ChaseService appelle DiagnosticsService.noteTick avec une durée finie ≥ 0",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 60 })
				local D = w.h:require(Brains.S .. "DiagnosticsService")
				local seen = {}
				D.noteTick = function(ms)
					table.insert(seen, ms)
				end
				Brains.join(w, 1, { profile = Brains.profile(w, { squishies = squishies(2) }) })
				Brains.frames(w, 20)
				expect(#seen >= 20).toBe(true)
				for _, ms in seen do
					expect(type(ms) == "number" and ms == ms and ms >= 0 and ms < math.huge).toBe(true)
				end
				clean(w)
			end
		)
	end)

	describe("Intégration serveur › analytique du Rush (GDD §16.3)", function()
		it(
			"boop subi puis Cozy dans les 2 min : CozyAfterBoop ; « Pas ce joueur » : RefuseBooper ; départ < 2 min après : PostBoopQuit ; sans boop : QuitBaseline ; ModeAtSessionEnd",
			function()
				local w = Brains.boot(Harness, { t0 = RUSH_START - 2 })
				local owner = Brains.join(
					w,
					1,
					{ profile = Brains.profile(w, { rush = true, squishies = squishies(6) }) }
				)
				local booper = Brains.join(
					w,
					2,
					{ profile = Brains.profile(w, { rush = true, squishies = squishies(2) }) }
				)
				Brains.frames(w, 25)
				local uids = w.Ranch.fenceOf(w.Ranch.slotOf(owner))
				expect(#uids > 0).toBe(true)
				local lp = w.WL.fencePointsLocal()[1]
				local q = w.WL.toWorld(w.Ranch.slotOf(owner), w.V3.new(lp.X, 0, -2))
				Bots.place(booper, Bots.ground(q.X, q.Z))
				Brains.frames(w, 2)
				w.h:fireServer(R .. "BoopHold", booper, owner.UserId, uids[1], true)
				Brains.frames(w, 30)
				expect(#Bots.celebrations(owner, "booped")).toBe(1)
				-- « Pas ce joueur », puis Cozy dans les 2 min
				w.h:fireServer(R .. "RefuseBooper", owner, booper.UserId)
				Brains.frames(w, 5)
				expect(#custom(w, "RefuseBooper")).toBe(1)
				expect(custom(w, "RefuseBooper")[1].player).toBe(owner)
				w.h:fireServer(R .. "SetMode", owner, false)
				Brains.frames(w, 2)
				expect(#custom(w, "CozyAfterBoop")).toBe(1)
				-- départ du propriétaire moins de 2 min après son premier boop subi
				Bots.leave(owner)
				w.h:settle(3)
				local quits = custom(w, "PostBoopQuit")
				expect(#quits).toBe(1)
				expect(quits[1].value >= 0 and quits[1].value < 120).toBe(true)
				local modes = custom(w, "ModeAtSessionEnd")
				expect(#modes).toBe(1)
				expect(modes[1].value).toBe(0) -- parti en Cozy
				expect(#custom(w, "QuitBaseline")).toBe(0)
				-- le boopeur n'a jamais été boopé : départ de référence, parti en Rush
				Bots.leave(booper)
				w.h:settle(3)
				expect(#custom(w, "QuitBaseline")).toBe(1)
				local last = custom(w, "ModeAtSessionEnd")
				expect(last[#last].value).toBe(1)
				expect(#custom(w, "PostBoopQuit")).toBe(1)
				clean(w)
			end
		)
	end)

	describe("Intégration serveur › analytique des squishies (GDD §16.3)", function()
		it(
			"première balade : RideStart une fois par session ; Tout fusionner : ComboLength (all = 1)",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 60 })
				local list = squishies(2)
				table.insert(list, { s = 5, z = 30 })
				table.insert(list, { s = 5, z = 31 })
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						squishies = list,
						edit = function(d)
							d.biggestEver = 2000 -- selle débloquée
						end,
					}),
					at = nil,
				})
				Bots.place(p, Brains.atRanch(w, p, 0, 40))
				Brains.frames(w, 5)
				for _ = 1, 3 do
					w.h:fireServer(R .. "Ride", p, true)
					Brains.frames(w, 6)
					w.h:fireServer(R .. "Ride", p, false)
					Brains.frames(w, 6)
				end
				local rides = custom(w, "RideStart")
				expect(#rides).toBe(1)
				expect(rides[1].value).toBe(3600)
				w.h:fireServer(R .. "FuseAll", p)
				Brains.frames(w, 40)
				local combos = custom(w, "ComboLength")
				expect(#combos >= 1).toBe(true)
				local all = combos[#combos]
				expect(all.value >= 1).toBe(true)
				clean(w)
			end
		)

		it("éclosion de la Cuve : HatchRarity (et MutationGot pour une mutation)", function()
			local w = Brains.boot(Harness, { t0 = H0 + 60 })
			local p = Brains.join(w, 1, { profile = Brains.profile(w, { squishies = squishies(1) }) })
			Brains.frames(w, 5)
			-- goutte prête : la Cuve éclot au tick suivant (2 s d'éclosion)
			w.DS.get(p).vat.fillAt = 1
			Brains.frames(w, 40)
			local hatched = custom(w, "HatchRarity")
			expect(#hatched >= 1).toBe(true)
			expect(hatched[1].value >= 1).toBe(true)
			for _, m in custom(w, "MutationGot") do
				expect(m.value ~= 0).toBe(true)
			end
			clean(w)
		end)
	end)

	describe("Intégration serveur › AdminCommand photo (Diagnostics › Outils)", function()
		it(
			"« photo » sans argument bascule ; « on » / « off » imposent ; non-administrateur : rien",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 60 })
				local admin = Brains.join(w, 1, { profile = Brains.profile(w, { squishies = squishies(1) }) })
				local other = Brains.join(w, 2, { profile = Brains.profile(w, { squishies = squishies(1) }) })
				w.meta.admins[1] = true
				local function photos(p)
					local out = {}
					for _, data in Bots.celebrations(p, "photo") do
						table.insert(out, data.on)
					end
					return out
				end
				for _, arg in { "", "", "on", "on", "off", "" } do
					w.h:fireServer(R .. "AdminCommand", admin, "photo", arg)
					Brains.frames(w, 6)
				end
				expect(photos(admin)).toEqual({ true, false, true, true, false, true })
				w.h:fireServer(R .. "AdminCommand", other, "photo", "")
				Brains.frames(w, 6)
				expect(#photos(other)).toBe(0)
				clean(w)
			end
		)
	end)
end
