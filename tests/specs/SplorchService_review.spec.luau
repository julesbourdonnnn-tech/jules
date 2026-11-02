--!nocheck
-- SplorchService : défauts trouvés par la revue adversariale du lot chase (chaque test reproduit le
-- défaut avant sa correction).
--   1. Éclatement en erreur (attrapée par Guard) avant SquishyService.setWaiting(hero, nil) : le flyer
--      restait « en attente de Grand Splorch » pour toute la session (plus de Grand Splorch possible,
--      aucune clôture du Rush, fuites personnelles en pause).
--   2. Filet de la file : toute attente de plus de 490 s était annulée sans un mot, même quand
--      EventService avait encore l'entrée et allait lancer le spectacle (file longue). Le filet ne
--      rend plus que les places qu'EventService a perdues.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60 -- loin de tout Rush ou MEGA pendant ~3 min

	local function ready(w)
		return Brains.profile(w, {
			coins = 5000,
			squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 20000 }, { s = 3, z = 300 } },
		})
	end

	local function world(t0)
		local w = Brains.boot(Harness, { t0 = t0 or T0 })
		local hero = Brains.join(w, 1, { profile = ready(w) })
		local other =
			Brains.join(w, 2, { profile = Brains.profile(w, { squishies = { { s = 2, z = 500 } } }) })
		Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
		Brains.frames(w, 2)
		return w, hero, other
	end

	local function splorch(w, p, flyer)
		w.h:fireServer("ReplicatedStorage.Remotes.GrandSplorch", p, false, flyer or "2")
	end

	local function only(w, needle)
		for _, line in Brains.problems(w) do
			expect(string.find(line, needle, 1, true) ~= nil).toBe(true)
		end
	end

	describe("SplorchService (revue) › éclatement en erreur", function()
		it("l'attente du flyer est toujours levée, même si l'éclatement échoue", function()
			local w, hero = world()
			local apply = w.Economy.applySplorch
			w.Economy.applySplorch = function()
				error("panne simulée")
			end
			splorch(w, hero)
			expect(w.Squishy.waiting(hero)).toBe("2")
			Brains.frames(w, 150)
			w.Economy.applySplorch = apply
			expect(w.Squishy.waiting(hero)).toBeNil()
			expect(w.Splorch.queued(hero)).toBeNil()
			only(w, "panne simulée")
			expect(#Brains.expiredStates(w, w.Clock.now())).toBe(0)
		end)
	end)

	describe("SplorchService (revue) › filet de la file", function()
		it(
			"file longue : l'entrée encore tenue par EventService n'est jamais annulée par le filet",
			function()
				local w, hero = world()
				-- 26 grands spectacles d'absents devant (EventService les lance, SplorchService les ignore)
				for i = 1, 26 do
					w.Event.enqueueSpectacle("splorch", 900000 + i)
				end
				splorch(w, hero)
				expect(w.Squishy.waiting(hero)).toBe("2")
				local starts = 0
				w.Signals.SpectacleStarted:Connect(function(kind, userId)
					if kind == "splorch" and userId == hero.UserId then
						starts += 1
					end
				end)
				-- 26 × 20 s devant lui (et le Rush de :05 au milieu) : au-delà de l'ancien filet de 490 s
				for _ = 1, 160 do
					w.Clock.freeze(w.Clock.now() + 5)
					Brains.frames(w, 2)
				end
				expect(starts).toBe(1)
				expect(w.Squishy.waiting(hero)).toBeNil()
			end
		)

		it("place perdue par EventService : l'attente est rendue au tick suivant", function()
			local w, hero = world()
			-- un spectacle d'absent devant lui : sa place attend
			w.Event.enqueueSpectacle("splorch", 900001)
			splorch(w, hero)
			Brains.frames(w, 2)
			expect(w.Splorch.queued(hero) ~= nil).toBe(true)
			-- EventService perd l'entrée (coupure, panne) sans prévenir SplorchService
			local cancel = w.Event.cancelSpectacle
			w.Event.cancelSpectacle = function() end
			cancel(hero.UserId)
			Brains.frames(w, 25)
			w.Event.cancelSpectacle = cancel
			expect(w.Splorch.queued(hero)).toBeNil()
			expect(w.Squishy.waiting(hero)).toBeNil()
		end)
	end)
end
