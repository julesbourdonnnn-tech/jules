--!nocheck
-- EconomyPacing (paquet logic) : PORTE BLOQUANTE du GDD §4.18. Simule 200 joueurs de référence sur
-- 28 jours avec les vraies tables (Config/*) et les vraies formules (Logic/Formulas, EventClock,
-- WorldLayout) ; échoue si la médiane d'un jalon sort de sa tolérance. Modèle et hypothèses :
-- tests/sim/Pacing.luau ; réglages et mesures : docs/04-architecture.md §17.
local Pacing = require("../sim/Pacing")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- Dépendances fraîches (chaque harnais a ses propres instances de modules)
	local function loadDeps(tweak)
		local h = Harness.new()
		local deps = {}
		for _, name in { "Balance", "Nebbies", "Zones", "Events", "Quests" } do
			deps[name] = h:require("ReplicatedStorage.Shared.Config." .. name)
		end
		if tweak then
			tweak(deps)
		end
		for _, name in { "Formulas", "EventClock", "WorldLayout" } do
			deps[name] = h:require("ReplicatedStorage.Shared.Logic." .. name)
		end
		return deps
	end

	local function inside(gate, value)
		return (gate.min == nil or value >= gate.min) and (gate.max == nil or value <= gate.max)
	end

	describe("EconomyPacing — porte du GDD §4.18 (200 joueurs × 28 jours)", function()
		local result = nil

		it("simule 200 joueurs de référence sur 28 jours sans incohérence", function()
			result = Pacing.run(loadDeps(), 200, 28)
			print("\n  Médianes simulées (200 joueurs × 28 jours) :\n" .. Pacing.report(result))
			expect(#result.players).toBe(200)
			for _, p in result.players do
				expect(p.finalR == p.finalR and p.finalR >= 0).toBe(true)
				expect(p.finalAtlas >= 0 and p.finalAtlas <= 150).toBe(true)
				-- les jalons arrivent dans l'ordre
				expect(p.sn3Day <= p.sn6Day and p.sn6Day <= p.sn10Day).toBe(true)
				expect(p.atlas50Day <= p.atlas80Day).toBe(true)
				expect(p.firstParade <= p.firstUpgrade).toBe(true)
			end
		end)

		for _, gate in Pacing.Gates do
			it(`médiane dans la tolérance : {gate.label}`, function()
				expect(result).toBeTruthy()
				local m = result.medians[gate.key]
				if not inside(gate, m) then
					error(
						`{gate.label} : médiane {m} hors de [{tostring(gate.min or "—")} ; {tostring(
							gate.max
						)}] — régler Config/Balance (valeurs) et consigner dans docs §17`
					)
				end
			end)
		end
	end)

	describe("EconomyPacing — fiabilité de la porte", function()
		it("déterministe : deux simulations identiques donnent les mêmes jalons", function()
			local a = Pacing.run(loadDeps(), 12, 6)
			local b = Pacing.run(loadDeps(), 12, 6)
			for i = 1, 12 do
				expect(a.players[i]).toEqual(b.players[i])
			end
		end)

		it("la porte a des dents : une Supernova 10 fois moins chère la fait échouer", function()
			local cheap = Pacing.run(
				loadDeps(function(deps)
					local sn = deps.Balance.Supernova
					for i = 1, #sn.Costs do
						sn.Costs[i] = math.floor(sn.Costs[i] / 10)
					end
					sn.BeyondBase = math.floor(sn.BeyondBase / 10)
				end),
				40,
				10
			)
			local failed = {}
			for _, gate in Pacing.Gates do
				if not inside(gate, cheap.medians[gate.key]) then
					failed[gate.key] = true
				end
			end
			-- Supernova 1 trop tôt, Supernovas 6 et 10 bien avant leur fenêtre
			expect(failed.sn1Minutes).toBe(true)
			expect(failed.sn6Star3Day).toBe(true)
			expect(cheap.medians.sn6Day < 6).toBe(true)
			expect(cheap.medians.sn10Day < 18).toBe(true)
		end)

		it("la porte suit la configuration : 3 fois plus de formes météo accélèrent l'Atlas", function()
			local base = Pacing.run(loadDeps(), 30, 10)
			local rich = Pacing.run(
				loadDeps(function(deps)
					deps.Balance.Spawn.WeatherFormChance =
						math.min(1, deps.Balance.Spawn.WeatherFormChance * 3)
				end),
				30,
				10
			)
			local function meanAtlas(r)
				local sum = 0
				for _, p in r.players do
					sum += p.finalAtlas
				end
				return sum / #r.players
			end
			expect(meanAtlas(rich) > meanAtlas(base)).toBe(true)
		end)
	end)
end
