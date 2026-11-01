--!nocheck
-- Server/Util/RateLimit (repris de Comet Conga) : seau à jetons par joueur et par action, horloge
-- technique os.clock figée par le test (Bots.fakeOsClock : aucune vraie attente, aucun test instable
-- sur une machine chargée), joueur parti refusé sans rien retenir, état oublié au départ.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function setup()
		local h = Harness.new()
		local clock = Bots.fakeOsClock(h)
		local RL = h:require("ServerScriptService.Server.Util.RateLimit")
		clock.freeze()
		return h, RL, clock
	end

	describe("RateLimit", function()
		it("rafale bornée à maxCalls, puis remplissage à maxCalls / perSeconds", function()
			local h, RL, clock = setup()
			local p = h:addPlayer({ userId = 1, spawn = false })
			local granted = 0
			for _ = 1, 10 do
				if RL.allow(p, "Buy", 5, 1) then
					granted += 1
				end
			end
			expect(granted).toBe(5)
			clock.advance(0.25) -- 1,25 jeton (jamais pile 1 : flottants)
			expect(RL.allow(p, "Buy", 5, 1)).toBe(true)
			expect(RL.allow(p, "Buy", 5, 1)).toBe(false)
			clock.advance(10) -- jamais plus que maxCalls
			granted = 0
			for _ = 1, 10 do
				if RL.allow(p, "Buy", 5, 1) then
					granted += 1
				end
			end
			expect(granted).toBe(5)
		end)

		it("seaux séparés par joueur et par action", function()
			local h, RL = setup()
			local a = h:addPlayer({ userId = 1, spawn = false })
			local b = h:addPlayer({ userId = 2, spawn = false })
			expect(RL.allow(a, "Ping", 1, 1.2)).toBe(true)
			expect(RL.allow(a, "Ping", 1, 1.2)).toBe(false)
			expect(RL.allow(a, "Boop", 1, 20)).toBe(true)
			expect(RL.allow(b, "Ping", 1, 1.2)).toBe(true)
		end)

		it("joueur déjà parti : refusé sans rien retenir ; départ : tout est oublié", function()
			local h, RL = setup()
			local p = h:addPlayer({ userId = 3, spawn = false })
			expect(RL.allow(p, "Buy", 1, 60)).toBe(true)
			expect(RL.allow(p, "Buy", 1, 60)).toBe(false)
			h:removePlayer(p)
			expect(RL.allow(p, "Buy", 1, 60)).toBe(false)
			-- reconnexion (même instance réutilisée par le test) : seau neuf après PlayerRemoving
			p.Parent = h.game.Players
			expect(RL.allow(p, "Buy", 1, 60)).toBe(true)
			RL.clear(p)
			expect(RL.allow(p, "Buy", 1, 60)).toBe(true)
		end)
	end)
end
