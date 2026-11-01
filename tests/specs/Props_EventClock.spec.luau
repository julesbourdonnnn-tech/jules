--!nocheck
-- Props_EventClock (paquet logic, docs/04 §17.1 couche a) : pour tout instant, chaque phase est
-- l'occurrence en cours ou la prochaine, cohérente, et la pastille annonce un départ futur proche.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local EC = h:require("ReplicatedStorage.Shared.Logic.EventClock")
	local times = Props.number(0, 4e9)

	describe("Props › EventClock", function()
		it("rush : en cours ou prochain, 90 s, sirène 10 s avant, au plus 600 s d'attente", function()
			Props.check(5000, times, function(t)
				local r = EC.rush(t)
				return t < r.endsAt
					and r.endsAt - r.startsAt == 90
					and r.startsAt - r.sirenAt == 10
					and r.startsAt - t <= 600
					and r.active == (t >= r.startsAt)
					and r.index % 1 == 0
			end)
		end)

		it("mega : en cours ou prochain, 60 s + 5 s, alerte 15 s avant, au plus 1 800 s d'attente", function()
			Props.check(5000, times, function(t)
				local m = EC.mega(t)
				return t < m.burstEndsAt
					and m.endsAt - m.landsAt == 60
					and m.burstEndsAt - m.endsAt == 5
					and m.landsAt - m.warnAt == 15
					and m.landsAt - t <= 1800
					and m.active == (t >= m.landsAt)
			end)
		end)

		it("golden : en cours ou prochain, 30 s, au plus 1 230 s d'attente", function()
			Props.check(5000, times, function(t)
				local g = EC.golden(t)
				return t < g.endsAt
					and g.endsAt - g.spawnAt == 30
					and g.spawnAt - t <= 1230
					and g.active == (t >= g.spawnAt)
			end)
		end)

		it("moon : en cours ou prochaine, 20 min, séance 1 … 5, au plus une semaine d'attente", function()
			Props.check(5000, times, function(t)
				local m = EC.moon(t)
				return t < m.endsAt
					and m.endsAt - m.startsAt == 1200
					and m.session >= 1
					and m.session <= 5
					and m.startsAt - t <= 7 * 86400
					and m.active == (t >= m.startsAt)
			end)
		end)

		it("pastille : départ strictement futur, au plus 600 s (un Rush toutes les 10 min)", function()
			Props.check(5000, times, function(t)
				local e = EC.nextEvent(t)
				return e.at > t and e.at - t <= 600
			end)
		end)

		it("jamais un Rush et un MEGA actifs en même temps", function()
			Props.check(8000, times, function(t)
				return not (EC.rush(t).active and EC.mega(t).active)
			end)
		end)

		it("megaSpecies ∈ [1 ; 24], costume chaîne, seed entière, entrées bizarres sûres", function()
			Props.check(4000, Props.anyNumber(), function(t)
				local s = EC.megaSpecies(t)
				return s >= 1
					and s <= 24
					and type(EC.costume(t)) == "string"
					and EC.seed("rush", t) % 1 == 0
					and type(EC.rushMoonBoopable(t)) == "boolean"
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
