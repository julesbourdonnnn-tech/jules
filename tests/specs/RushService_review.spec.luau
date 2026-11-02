--!nocheck
-- RushService : défauts trouvés par la revue adversariale du lot chase (chaque test reproduit le
-- défaut avant sa correction).
--   1. Fuite jamais créée (erreur dans ChaseService.startEscape, comptée par Guard) : la place
--      activeEscapes du squishy restait posée jusqu'au départ du propriétaire. Le squishy revenait à la
--      clôture (rien ne l'en avait retiré) mais plus personne ne pouvait le booper (refus muet), et la
--      place comptait dans le plafond du serveur. Une place de fuite a maintenant un délai : celui de
--      la fuite (StateTimeouts « escape »).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local RUSH_START = 1800000000 + 300

	local function standAtFence(w, booper, owner, i)
		local p = w.WL.fencePointsLocal()[i or 1]
		local q = w.WL.toWorld(w.Ranch.slotOf(owner), w.V3.new(p.X, 0, -2))
		Bots.place(booper, Bots.ground(q.X, q.Z))
	end

	local function holdsOf(w, booper)
		local n = 0
		for _, st in w.Rush.openStates() do
			if st.name == "boopHold" and st.player == booper then
				n += 1
			end
		end
		return n
	end

	describe("RushService (revue) › place de fuite", function()
		it("fuite jamais créée : le squishy redevient boopable après le délai de la fuite", function()
			local w = Brains.boot(Harness, { t0 = RUSH_START - 2 })
			-- un seul squishy hors Meilleur Ami : c'est lui, à chaque renouvellement de la clôture
			local owner = Brains.join(w, 1, {
				profile = Brains.profile(
					w,
					{ rush = true, squishies = { { s = 1, z = 100, bf = 1 }, { s = 3, z = 60 } } }
				),
			})
			local booper = Brains.join(w, 2, { profile = Brains.profile(w, { rush = true }) })
			local other = Brains.join(w, 3, { profile = Brains.profile(w, { rush = true }) })
			Brains.frames(w, 25)
			local uids = w.Ranch.fenceOf(w.Ranch.slotOf(owner))
			expect(#uids).toBe(1)
			local uid = uids[1]
			standAtFence(w, booper, owner, 1)
			Brains.frames(w, 2)
			-- la création de la fuite échoue (erreur attrapée par Guard dans ChaseService.startEscape)
			local sizeOf = w.Squishy.sizeOf
			w.Squishy.sizeOf = function()
				error("panne simulée")
			end
			w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", booper, owner.UserId, uid, true)
			Brains.frames(w, 30)
			w.Squishy.sizeOf = sizeOf
			expect(w.Chase.isEscaping(owner, uid)).toBe(false)
			-- après le délai d'une fuite (25 s) et un renouvellement de la clôture : boopable à nouveau
			Brains.frames(w, 270)
			expect(table.find(w.Ranch.fenceOf(w.Ranch.slotOf(owner)), uid) ~= nil).toBe(true)
			standAtFence(w, other, owner, 1)
			Brains.frames(w, 2)
			w.h:fireServer("ReplicatedStorage.Remotes.BoopHold", other, owner.UserId, uid, true)
			Brains.frames(w, 1)
			expect(holdsOf(w, other)).toBe(1)
			-- seule trace : l'erreur simulée, comptée une fois
			local problems = Brains.problems(w)
			for _, line in problems do
				expect(string.find(line, "panne simulée", 1, true) ~= nil).toBe(true)
			end
			expect(#Brains.expiredStates(w, w.Clock.now())).toBe(0)
		end)
	end)
end
