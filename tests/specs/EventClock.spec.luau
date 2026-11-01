--!nocheck
-- EventClock (paquet logic, docs/04 §4, §12.1, GDD §2.4, §12.4) : instants clés (minuit, :04:50,
-- :05:00, :06:30, :19:45, :20:00, :21:05, samedi 15:59:59, 16:00, 16:20, 22:20, dimanche 16:00,
-- changement de semaine) et 100 000 créneaux : un seul grand spectacle fixe à la fois, ≥ 20 s d'écart.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local EC = h:require("ReplicatedStorage.Shared.Logic.EventClock")
	local Events = h:require("ReplicatedStorage.Shared.Config.Events")
	local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")

	local SAT = 1793404800 -- samedi 31/10/2026 00:00:00 UTC
	local SUN = SAT + 86400
	local MONDAY_NEXT = SAT + 2 * 86400
	local function at(base, hh, mm, ss)
		return base + hh * 3600 + mm * 60 + (ss or 0)
	end

	describe("EventClock › instants clés", function()
		it("le samedi de référence est bien un samedi (Util/Clock)", function()
			expect(Clock.weekday(SAT)).toBe(6)
			expect(Clock.weekday(SUN)).toBe(0)
			expect(Clock.week(MONDAY_NEXT)).toBe(Clock.week(SAT) + 1)
		end)

		it("minuit : prochain Rush à :05, Golden à :00:30, MEGA à :20, Lune à 16:00", function()
			local t = SAT
			local r = EC.rush(t)
			expect(r.active).toBe(false)
			expect(r.startsAt - t).toBe(300)
			expect(r.sirenAt - t).toBe(290)
			local g = EC.golden(t)
			expect(g.active).toBe(false)
			expect(g.spawnAt - t).toBe(30)
			local m = EC.mega(t)
			expect(m.landsAt - t).toBe(1200)
			expect(m.warnAt - t).toBe(1185)
			local moon = EC.moon(t)
			expect(moon.active).toBe(false)
			expect(moon.session).toBe(1)
			expect(moon.startsAt).toBe(at(SAT, 16, 0))
		end)

		it(":04:50 sirène, :05:00 Rush (90 s), :06:30 fini → prochain à :15", function()
			local siren = EC.rush(at(SAT, 0, 4, 50))
			expect(siren.active).toBe(false)
			expect(siren.sirenAt).toBe(at(SAT, 0, 4, 50))
			local start = EC.rush(at(SAT, 0, 5, 0))
			expect(start.active).toBe(true)
			expect(start.startsAt).toBe(at(SAT, 0, 5, 0))
			expect(start.endsAt).toBe(at(SAT, 0, 6, 30))
			expect(start.index).toBe(siren.index)
			local after = EC.rush(at(SAT, 0, 6, 30))
			expect(after.active).toBe(false)
			expect(after.startsAt).toBe(at(SAT, 0, 15, 0))
			expect(after.index).toBe(start.index + 1)
			-- index global : numéro du créneau depuis l'époque
			expect(start.index).toBe(math.floor((at(SAT, 0, 5, 0) - 300) / 600))
		end)

		it(":19:45 alerte, :20:00 MEGA (60 s + 5 s), :21:05 fini → prochain à :50", function()
			local warn = EC.mega(at(SAT, 0, 19, 45))
			expect(warn.active).toBe(false)
			expect(warn.warnAt).toBe(at(SAT, 0, 19, 45))
			local lands = EC.mega(at(SAT, 0, 20, 0))
			expect(lands.active).toBe(true)
			expect(lands.endsAt).toBe(at(SAT, 0, 21, 0))
			expect(lands.burstEndsAt).toBe(at(SAT, 0, 21, 5))
			expect(lands.moon).toBe(false)
			local burst = EC.mega(at(SAT, 0, 21, 4))
			expect(burst.active).toBe(true)
			local done = EC.mega(at(SAT, 0, 21, 5))
			expect(done.active).toBe(false)
			expect(done.landsAt).toBe(at(SAT, 0, 50, 0))
		end)

		it("Golden Wobbler : :00:30, :10:30, :30:30, :40:30 (30 s), index distincts", function()
			local spawns = {}
			local t = at(SAT, 3, 0, 0)
			local seen = {}
			for _ = 1, 4 do
				local g = EC.golden(t)
				table.insert(spawns, g.spawnAt - at(SAT, 3, 0, 0))
				expect(seen[g.index]).toBeNil()
				seen[g.index] = true
				expect(EC.golden(g.spawnAt).active).toBe(true)
				expect(EC.golden(g.endsAt - 0.001).active).toBe(true)
				t = g.endsAt
			end
			expect(spawns).toEqual({ 30, 630, 1830, 2430 })
			expect(EC.golden(at(SAT, 3, 41, 0)).spawnAt).toBe(at(SAT, 4, 0, 30))
		end)

		it("samedi 15:59:59, 16:00, 16:20 : séance 1 de la Lune et MEGA MOON SQUISH", function()
			local before = EC.moon(at(SAT, 15, 59, 59))
			expect(before.active).toBe(false)
			expect(before.startsAt).toBe(at(SAT, 16, 0))
			local during = EC.moon(at(SAT, 16, 0))
			expect(during.active).toBe(true)
			expect(during.session).toBe(1)
			expect(during.endsAt).toBe(at(SAT, 16, 20))
			local ended = EC.moon(at(SAT, 16, 20))
			expect(ended.active).toBe(false)
			expect(ended.session).toBe(2)
			expect(ended.startsAt).toBe(at(SAT, 18, 0))
			expect(EC.mega(at(SAT, 16, 20)).moon).toBe(true)
			expect(EC.mega(at(SAT, 16, 50)).moon).toBe(false)
			expect(EC.mega(at(SAT, 18, 20)).moon).toBe(true)
			expect(EC.mega(at(SAT, 15, 20)).moon).toBe(false)
		end)

		it(
			"22:20 → dimanche 16:00 (séance 5) → changement de semaine (samedi suivant, séance 1)",
			function()
				local last = EC.moon(at(SAT, 22, 20))
				expect(last.active).toBe(false)
				expect(last.session).toBe(5)
				expect(last.startsAt).toBe(at(SUN, 16, 0))
				local sunday = EC.moon(at(SUN, 16, 0))
				expect(sunday.active).toBe(true)
				expect(sunday.session).toBe(5)
				expect(EC.mega(at(SUN, 16, 20)).moon).toBe(true)
				local nextWeek = EC.moon(at(SUN, 16, 20))
				expect(nextWeek.active).toBe(false)
				expect(nextWeek.session).toBe(1)
				expect(nextWeek.startsAt).toBe(at(SAT + 7 * 86400, 16, 0))
				local monday = EC.moon(MONDAY_NEXT)
				expect(monday.startsAt).toBe(at(SAT + 7 * 86400, 16, 0))
			end
		)

		it("Rush de :05 et :15 pendant la Lune : Mythiques et Secrets boopables", function()
			expect(EC.rushMoonBoopable(at(SAT, 16, 5))).toBe(true)
			expect(EC.rushMoonBoopable(at(SAT, 16, 15, 30))).toBe(true)
			expect(EC.rushMoonBoopable(at(SAT, 16, 25))).toBe(false)
			expect(EC.rushMoonBoopable(at(SAT, 17, 5))).toBe(false)
			expect(EC.rushMoonBoopable(at(SUN, 16, 5))).toBe(true)
			expect(EC.rushMoonBoopable(at(SAT + 86400 * 2, 16, 5))).toBe(false) -- lundi
			-- avant le Rush : on parle du prochain (16:05 pendant la séance de 16:00)
			expect(EC.rushMoonBoopable(at(SAT, 16, 1))).toBe(true)
		end)

		it("pastille : prochain départ strictement après t", function()
			local e = EC.nextEvent(at(SAT, 16, 0))
			expect(e.kind).toBe("golden")
			expect(e.at).toBe(at(SAT, 16, 0, 30))
			local r = EC.nextEvent(at(SAT, 16, 1))
			expect(r.kind).toBe("rush")
			expect(r.at).toBe(at(SAT, 16, 5))
			local m = EC.nextEvent(at(SAT, 16, 17))
			expect(m.kind).toBe("mega")
			expect(m.at).toBe(at(SAT, 16, 20))
			-- interrupteurs du serveur : sans MEGA ni Golden
			local only = EC.nextEventOf(at(SAT, 16, 17), { rush = true, moon = true })
			expect(only.kind).toBe("rush")
			expect(only.at).toBe(at(SAT, 16, 25))
			expect(EC.nextEventOf(at(SAT, 1, 0), {})).toBeNil()
			local moon = EC.nextEventOf(at(SAT, 1, 0), { moon = true })
			expect(moon.at).toBe(at(SAT, 16, 0))
		end)

		it("espèce du géant : rotation, jamais un Secret, même résultat pendant tout le MEGA", function()
			local s = EC.megaSpecies(at(SAT, 0, 20))
			expect(EC.megaSpecies(at(SAT, 0, 20, 59))).toBe(s)
			expect(EC.megaSpecies(at(SAT, 0, 19, 45))).toBe(s)
			local seen = {}
			local t = SAT
			for _ = 1, 48 do
				local m = EC.mega(t)
				local sp = EC.megaSpecies(m.landsAt)
				expect(sp >= 1 and sp <= 24).toBe(true)
				seen[sp] = true
				t = m.burstEndsAt
			end
			local count = 0
			for _ in seen do
				count += 1
			end
			expect(count).toBe(24)
		end)

		it("graines et costumes", function()
			expect(EC.seed("rush", 5)).toBe(EC.seed("rush", 5))
			expect(EC.seed("rush", 5) ~= EC.seed("rush", 6)).toBe(true)
			expect(EC.seed("rush", 5) ~= EC.seed("golden", 5)).toBe(true)
			expect(EC.costume(1797033600)).toBe("winter2026")
			expect(EC.costume(1797033599)).toBe("")
			expect(EC.costume(1799452800)).toBe("kings2027")
			expect(EC.costume(0 / 0)).toBe("")
		end)

		it("entrées bizarres : lues comme t = 0, jamais d'erreur", function()
			expect(EC.rush(0 / 0)).toEqual(EC.rush(0))
			expect(EC.mega(math.huge)).toEqual(EC.mega(0))
			expect(EC.moon(nil)).toEqual(EC.moon(0))
			expect(EC.golden(-math.huge)).toEqual(EC.golden(0))
		end)
	end)

	describe("EventClock › 100 000 créneaux", function()
		it("Rush et MEGA ne se chevauchent jamais et restent à ≥ 20 s l'un de l'autre", function()
			local gap = Events.SpectacleGap
			local intervals = {}
			local start = 1792972800 -- un lundi
			for i = 0, 99999 do
				local r = EC.rush(start + i * 600 + 1)
				table.insert(intervals, { r.startsAt, r.endsAt })
			end
			local stop = start + 100000 * 600
			local t = start
			while t < stop do
				local m = EC.mega(t)
				table.insert(intervals, { m.warnAt, m.burstEndsAt })
				t = m.burstEndsAt
			end
			table.sort(intervals, function(a, b)
				return a[1] < b[1]
			end)
			local worst = math.huge
			for i = 2, #intervals do
				worst = math.min(worst, intervals[i][1] - intervals[i - 1][2])
			end
			expect(worst >= gap).toBe(true)
		end)

		it("phases cohérentes : active ⇔ début ≤ t < fin, index croissants", function()
			local start = 1792972800
			local lastRush, lastMega = -math.huge, -math.huge
			for i = 0, 99999 do
				local t = start + i * 37.3
				local r = EC.rush(t)
				expect(r.active == (t >= r.startsAt and t < r.endsAt)).toBe(true)
				expect(t < r.endsAt).toBe(true)
				expect(r.index >= lastRush).toBe(true)
				lastRush = r.index
				local m = EC.mega(t)
				expect(m.active == (t >= m.landsAt and t < m.burstEndsAt)).toBe(true)
				expect(m.index >= lastMega).toBe(true)
				lastMega = m.index
			end
		end)
	end)

	describe("EventClock › zéro trace", function()
		it("aucune erreur ni aucun avertissement", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
