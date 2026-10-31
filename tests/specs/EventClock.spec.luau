--!nocheck
-- EventClock (paquet logic) : phases à des instants clés (minuit, :25, :55, samedi 16:00 et 16:20),
-- remplacement du planning pendant Starfall Saturday, répartition des météos sur 100 000 créneaux
-- (±1 point des poids normalisés), contenu et point d'impact de la Comète, rotations, déterminisme.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local E = h:require("ReplicatedStorage.Shared.Logic.EventClock")
	local Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies")
	local Events = h:require("ReplicatedStorage.Shared.Config.Events")

	local DAY = 86400
	-- samedi 31 octobre 2026 (jour UTC 20757) ; vendredi = 20756 ; lundi suivant = 20759
	local SAT = 20757 * DAY
	local S = SAT + 16 * 3600 -- 16:00 UTC, début du show
	local FRI = 20756 * DAY

	describe("EventClock — calendrier", function()
		it("jour, semaine (lundi 00:00 UTC) et jour de la semaine", function()
			expect(E.day(SAT)).toBe(20757)
			expect(E.weekday(SAT)).toBe(6)
			expect(E.weekday(FRI)).toBe(5)
			expect(E.weekday(SAT + DAY)).toBe(0)
			expect(E.weekday(0)).toBe(4) -- 01/01/1970 : jeudi
			local monday = SAT + 2 * DAY
			expect(E.weekday(monday)).toBe(1)
			expect(E.week(monday)).toBe(E.week(monday - 1) + 1)
			expect(E.week(SAT)).toBe(E.week(monday - 1))
			expect(E.week(345600)).toBe(0)
			expect(E.week(345599)).toBe(-1)
		end)

		it("rotations déterministes (w mod #table)", function()
			for w = 0, 30 do
				expect(E.featuredSpecies(w)).toBe(Events.Rotations.FeaturedSpecies[w % 12 + 1])
				expect(E.weeklyWanderer(w)).toBe(Events.Rotations.WeeklyWanderer[w % 5 + 1])
				expect(E.grandParadeLegendary(w)).toBe(Events.Rotations.GrandParadeLegendary[w % 3 + 1])
				expect(E.rotation("GrandParadeLegendary", w)).toBe(E.grandParadeLegendary(w))
			end
			expect(E.weeklyWanderer(-1)).toBe(Events.Rotations.WeeklyWanderer[5])
			local ok = pcall(E.rotation, "Nope", 1)
			expect(ok).toBe(false)
		end)
	end)

	describe("EventClock — météo (§4.15.1)", function()
		it("créneau de 6 min : fenêtre [+120 ; +270[, aucune hors fenêtre", function()
			local base = FRI + 3600 * 10 -- 10:00 vendredi = début d'un créneau
			expect(base % 360).toBe(0)
			expect(E.weather(base)).toBeNil()
			expect(E.weather(base + 119)).toBeNil()
			local w = E.weather(base + 120)
			expect(w).toBeTruthy()
			expect(w.slot).toBe(base // 360)
			expect(w.startsAt).toBe(base + 120)
			expect(w.endsAt).toBe(base + 270)
			expect(w.starfall).toBe(false)
			expect(w.key).toBe(E.weatherKeyForSlot(w.slot))
			expect(E.weather(base + 269.9).slot).toBe(w.slot)
			expect(E.weather(base + 270)).toBeNil()
			expect(E.weather(base + 359)).toBeNil()
		end)

		it("forme de la météo (Meteor Shower sans forme, Eclipse désactivée)", function()
			local seen = {}
			for slot = 1, 3000 do
				local key = E.weatherKeyForSlot(slot)
				seen[key] = true
				expect(key ~= "eclipse").toBe(true)
			end
			for _, key in { "aurora", "frost", "solar", "meteor", "rainbow" } do
				expect(seen[key]).toBe(true)
			end
			local t = FRI + 120
			for _ = 1, 400 do
				local w = E.weather(t)
				local expectedForm = ({ aurora = 1, frost = 2, solar = 3, rainbow = 5 })[w.key]
				expect(w.form).toBe(expectedForm)
				t += 360
			end
		end)

		it("répartition sur 100 000 créneaux à ±1 point des poids (somme normalisée)", function()
			local counts = {}
			local start = 4800000
			for slot = start, start + 99999 do
				local key = E.weatherKeyForSlot(slot)
				counts[key] = (counts[key] or 0) + 1
			end
			local total = 0
			for _, def in Events.Weather.Kinds do
				if Nebbies.isVersionEnabled(def.version) then
					total += def.weight
				end
			end
			for _, def in Events.Weather.Kinds do
				local expected = if Nebbies.isVersionEnabled(def.version) then def.weight / total else 0
				expect(((counts[def.key] or 0) / 100000)).toBeNear(expected, 0.01)
			end
		end)

		it("activer la v1.1 ajoute Eclipse et renormalise les poids (nouveau harnais)", function()
			local h2 = Harness.new()
			local N2 = h2:require("ReplicatedStorage.Shared.Config.Nebbies")
			N2.ENABLED_VERSIONS["v1.1"] = true
			local E2 = h2:require("ReplicatedStorage.Shared.Logic.EventClock")
			local eclipse, aurora = 0, 0
			for slot = 1, 50000 do
				local key = E2.weatherKeyForSlot(slot)
				if key == "eclipse" then
					eclipse += 1
				elseif key == "aurora" then
					aurora += 1
				end
			end
			expect(eclipse / 50000).toBeNear(10 / 110, 0.01)
			expect(aurora / 50000).toBeNear(30 / 110, 0.01)
		end)

		it("une fenêtre commence au plus 3 min 30 après n'importe quelle arrivée", function()
			local worst = 0
			for i = 0, 5000 do
				local t = FRI + i * 37.3
				if E.weather(t) == nil then
					worst = math.max(worst, E.nextWeather(t).startsAt - t)
				end
			end
			expect(worst <= 210).toBe(true)
		end)

		it("nextWeather : la prochaine fenêtre commence strictement après t", function()
			for i = 0, 300 do
				local t = FRI + i * 61
				local nw = E.nextWeather(t)
				expect(nw.startsAt > t).toBe(true)
				expect(nw.startsAt - t <= 360).toBe(true)
			end
			local base = FRI + 3600
			expect(E.nextWeather(base + 120).startsAt).toBe(base + 480)
			expect(E.nextWeather(base + 119).startsAt).toBe(base + 120)
		end)
	end)

	describe("EventClock — Grande Comète (§4.15.2)", function()
		it("impact à :00, :10, :20… ; alerte −8 s ; explosion +75 s", function()
			local t = FRI + 10 * 3600 -- 10:00
			expect(E.comet(t - 9)).toBeNil()
			local c = E.comet(t - 8)
			expect(c).toBeTruthy()
			expect(c.id).toBe(t)
			expect(c.impactAt).toBe(t)
			expect(c.warnAt).toBe(t - 8)
			expect(c.burstAt).toBe(t + 75)
			expect(c.starfall).toBe(false)
			expect(E.comet(t + 74.9).id).toBe(t)
			expect(E.comet(t + 75)).toBeNil()
			expect(E.comet(t + 591)).toBeNil()
			expect(E.comet(t + 592).id).toBe(t + 600)
			-- prochaine : warnAt > t
			expect(E.nextComet(t - 9).id).toBe(t)
			expect(E.nextComet(t - 8).id).toBe(t + 600)
			expect(E.nextComet(t + 100).id).toBe(t + 600)
		end)

		it("minuit : la Comète tombe pile à 00:00, aucune météo, la semaine change le lundi", function()
			local midnight = 20759 * DAY -- lundi
			expect(E.comet(midnight).impactAt).toBe(midnight)
			expect(E.weather(midnight)).toBeNil()
			expect(E.beacon(midnight)).toBeNil()
			expect(E.nextEvent(midnight - 30).kind).toBe("comet")
			expect(E.nextEvent(midnight - 30).at).toBe(midnight)
			expect(E.week(midnight)).toBe(E.week(midnight - 0.001) + 1)
		end)

		it("point d'impact dans le Cratère (r 10-40, sol du Cratère) et déterministe", function()
			for i = 0, 500 do
				local id = FRI + i * 600
				local p = E.cometImpact(id)
				local r = math.sqrt(p.X * p.X + p.Z * p.Z)
				expect(r >= 10 and r <= 40).toBe(true)
				expect(p.Y).toBeNear(0.3, 1e-6) -- Vector3 en flottants 32 bits
				expect(E.cometImpact(id)).toEqual(p)
			end
		end)

		it("contenu : Légendaire 80 / Mythique 18 / Cosmique 2, espèce activée de la rareté", function()
			local counts = { [5] = 0, [6] = 0, [7] = 0 }
			local n = 20000
			for i = 1, n do
				local rarity, s = E.cometContent(i * 600)
				counts[rarity] += 1
				expect(Nebbies.rarityOf(s)).toBe(rarity)
				expect(Nebbies.isSpeciesEnabled(s)).toBe(true)
			end
			expect(counts[5] / n).toBeNear(0.80, 0.015)
			expect(counts[6] / n).toBeNear(0.18, 0.015)
			expect(counts[7] / n).toBeNear(0.02, 0.005)
		end)
	end)

	describe("EventClock — Nuit de la Balise (§4.15.3)", function()
		it(":25-:28 et :55-:58, alerte 15 s avant", function()
			local hour = FRI + 9 * 3600
			expect(E.beacon(hour + 25 * 60 - 16)).toBeNil()
			local b = E.beacon(hour + 25 * 60 - 15)
			expect(b).toBeTruthy()
			expect(b.id).toBe(hour + 1500)
			expect(b.startsAt).toBe(hour + 1500)
			expect(b.warnAt).toBe(hour + 1485)
			expect(b.endsAt).toBe(hour + 1680)
			expect(E.beacon(hour + 28 * 60 - 0.5).id).toBe(hour + 1500)
			expect(E.beacon(hour + 28 * 60)).toBeNil()
			expect(E.beacon(hour + 55 * 60).startsAt).toBe(hour + 3300)
			expect(E.nextBeacon(hour).startsAt).toBe(hour + 1500)
			expect(E.nextBeacon(hour + 1490).startsAt).toBe(hour + 3300)
		end)
	end)

	describe("EventClock — Starfall Saturday (§4.15.5)", function()
		it("samedi 16:00-16:20 UTC uniquement, espèce vedette de la semaine", function()
			expect(E.starfall(S - 1)).toBeNil()
			local sf = E.starfall(S)
			expect(sf).toBeTruthy()
			expect(sf.startsAt).toBe(S)
			expect(sf.endsAt).toBe(S + 1200)
			expect(sf.week).toBe(E.week(S))
			expect(sf.featured).toBe(E.featuredSpecies(E.week(S)))
			expect(E.starfall(S + 1199).startsAt).toBe(S)
			expect(E.starfall(S + 1200)).toBeNil()
			expect(E.starfall(S - DAY)).toBeNil() -- vendredi 16:00
			expect(E.starfall(S + DAY)).toBeNil() -- dimanche 16:00
			expect(E.nextStarfall(S - 1).startsAt).toBe(S)
			expect(E.nextStarfall(S).startsAt).toBe(S + 7 * DAY)
			expect(E.nextStarfall(FRI).startsAt).toBe(S)
		end)

		it("16:00 : Rainbow continu pendant tout le show, fenêtres normales supprimées", function()
			for dt = 0, 1199, 7 do
				local w = E.weather(S + dt)
				expect(w).toBeTruthy()
				expect(w.key).toBe("rainbow")
				expect(w.form).toBe(5)
				expect(w.starfall).toBe(true)
				expect(w.startsAt).toBe(S)
				expect(w.endsAt).toBe(S + 1200)
			end
			-- juste avant le show : fenêtre normale de 15:56 (terminée à 15:58:30)
			expect(E.weather(S - 1)).toBeNil()
			expect(E.weather(S - 200).starfall).toBe(false)
			expect(E.nextWeather(S - 10).starfall).toBe(true)
			expect(E.nextWeather(S - 10).startsAt).toBe(S)
		end)

		it("16:00 à 16:18 : 7 Comètes toutes les 3 min, aucun impact normal dans la fenêtre", function()
			local ids = {}
			local t = S - 30
			while t < S + 1200 do
				local c = E.nextComet(t)
				if c.impactAt >= S + 1200 then
					break
				end
				expect(c.starfall).toBe(true)
				table.insert(ids, c.impactAt - S)
				t = c.warnAt
			end
			expect(ids).toEqual({ 0, 180, 360, 540, 720, 900, 1080 })
			expect(E.comet(S).starfall).toBe(true)
			expect(E.comet(S + 600).id).toBe(S + 540) -- 16:10 : comète du show, pas du planning normal
			expect(E.comet(S + 600).starfall).toBe(true)
		end)

		it("16:20 : retour au planning normal (Comète et météo)", function()
			local c = E.comet(S + 1200)
			expect(c.id).toBe(S + 1200)
			expect(c.starfall).toBe(false)
			local w = E.weather(S + 1200)
			expect(w).toBeTruthy()
			expect(w.starfall).toBe(false)
			expect(w.startsAt).toBe(S + 1200)
			expect(w.key).toBe(E.weatherKeyForSlot(w.slot))
			expect(E.nextComet(S + 1100).id).toBe(S + 1200)
		end)

		it("aucune Nuit de la Balise pendant Starfall (planning qui la ferait chevaucher)", function()
			for dt = -200, 1400, 5 do
				local b = E.beacon(S + dt)
				if b then
					expect(b.endsAt <= S or b.warnAt >= S + 1200).toBe(true)
				end
			end
			-- variante de configuration : Balise à :10 / :40 → celle de 16:10 est supprimée
			local h2 = Harness.new()
			local Ev2 = h2:require("ReplicatedStorage.Shared.Config.Events")
			Ev2.Beacon.Offset = 600
			local E2 = h2:require("ReplicatedStorage.Shared.Logic.EventClock")
			expect(E2.beacon(S + 600)).toBeNil()
			expect(E2.beacon(FRI + 16 * 3600 + 600).startsAt).toBe(FRI + 16 * 3600 + 600)
			expect(E2.nextBeacon(S).startsAt).toBe(S + 2400) -- 16:40
		end)

		it("pastille : égalité à 16:00 → Starfall ; ensuite Comètes du show", function()
			local n = E.nextEvent(S - 60)
			expect(n.kind).toBe("starfall")
			expect(n.at).toBe(S)
			n = E.nextEvent(S + 1)
			expect(n.kind).toBe("comet")
			expect(n.at).toBe(S + 180)
		end)
	end)

	describe("EventClock — pastille du HUD et robustesse", function()
		it("nextEvent : le plus proche, à un instant strictement futur", function()
			local hour = FRI + 9 * 3600
			local n = E.nextEvent(hour + 1)
			expect(n.kind).toBe("weather")
			expect(n.at).toBe(hour + 120)
			expect(n.key).toBe(E.weather(hour + 120).key)
			n = E.nextEvent(hour + 1490) -- pendant l'alerte de la Balise de :25
			expect(n.kind).toBe("beacon")
			expect(n.at).toBe(hour + 1500)
			n = E.nextEvent(hour + 595)
			expect(n.kind).toBe("comet")
			expect(n.at).toBe(hour + 600)
			for i = 0, 400 do
				local t = FRI + i * 113
				local e = E.nextEvent(t)
				expect(e.at > t).toBe(true)
				expect(e.at - t <= 600).toBe(true)
			end
		end)

		it("identique d'un harnais à l'autre (même planning sur tous les serveurs)", function()
			local h2 = Harness.new()
			local E2 = h2:require("ReplicatedStorage.Shared.Logic.EventClock")
			for i = 0, 200 do
				local t = S - 5000 + i * 97
				local a, b = E.weather(t), E2.weather(t)
				expect(a == nil and b == nil or (a and b and a.key == b.key and a.startsAt == b.startsAt)).toBeTruthy()
				expect(E.nextEvent(t)).toEqual(E2.nextEvent(t))
				expect(E.cometImpact(t // 600 * 600)).toEqual(E2.cometImpact(t // 600 * 600))
			end
		end)

		it("entrées non finies : aucune erreur", function()
			for _, x in { 0 / 0, math.huge, -math.huge } do
				E.weather(x)
				E.nextWeather(x)
				E.comet(x)
				E.nextComet(x)
				E.beacon(x)
				E.nextBeacon(x)
				E.starfall(x)
				E.nextStarfall(x)
				E.nextEvent(x)
				E.cometImpact(x)
				E.cometContent(x)
				E.featuredSpecies(x)
				expect(type(E.weatherKeyForSlot(x))).toBe("string")
			end
		end)
	end)
end
