--!nocheck
-- Remotes du paquet meta (docs/04 §17.1 b) : chaque intention de QuestService, CommunityService et
-- DiagnosticsService attaquée par tests/harness/Fuzz (mauvais types, nil, NaN, ±inf, nombres énormes,
-- chaînes de 100 000 caractères, UTF-8 invalide, tables profondes, mixtes ou à trous, uid d'un autre
-- joueur, arguments en trop) → aucune mutation du profil de l'attaquant ni d'un autre joueur, aucune
-- erreur (ZeroLog) ; rafale de 1 000 messages → seau à jetons au débit de Config/Intents ; Activity.note
-- seulement pour une intention de jeu acceptée.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local Fuzz = require("../harness/Fuzz")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
	local OWNERS = { QuestService = true, CommunityService = true, DiagnosticsService = true }

	local function world()
		local w = Brains.boot(Harness, { t0 = T0, stubMeta = false })
		w.h:makeFriends(1, 2)
		local p =
			Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 1, z = 100, bf = 1 } } }) })
		local q = Brains.join(w, 2, { profile = Brains.profile(w, { squishies = { { s = 2, z = 50 } } }) })
		w.h:settle(3)
		Brains.frames(w, 2)
		return w, p, q
	end

	local function intents(w)
		local Intents = w.h:require("ReplicatedStorage.Shared.Config.Intents")
		local names = {}
		for name, spec in Intents do
			if OWNERS[spec.owner] then
				table.insert(names, name)
			end
		end
		table.sort(names)
		return names, Intents
	end

	describe("Remotes_Meta", function()
		it(
			"chaque intention du paquet reçoit les charges hostiles : profils inchangés, aucune erreur",
			function()
				local w, p, q = world()
				local names = intents(w)
				-- 16 : + MenuActivity (lot A4, N23, journal A4-12) ; 19 : + PlaceDeco, GiveHeart, SetPhotoMode
				-- (lot A4, étape 5, note INT-V2-INTENTS, journal A4-37) ; 20 : + ClientMetric (lot A4,
				-- étape 6, D29, journal A4-44)
				expect(#names).toBe(20)
				local attacked = 0
				for _, name in names do
					local function attack()
						local sent = Fuzz.attack(w.h, p, name, nil, {
							uid = "1",
							otherUid = "zz",
							userId = q.UserId,
							typeHostileOnly = true,
							tick = function()
								w.osClock.advance(11) -- seaux remplis : chaque charge atteint la validation
							end,
						})
						attacked += sent
					end
					local okP, diffP = Fuzz.profileUnchanged(w.h, p, function()
						local okQ, diffQ = Fuzz.profileUnchanged(w.h, q, attack)
						if not okQ then
							error(name .. " : profil de l'autre joueur changé à " .. tostring(diffQ))
						end
					end)
					if not okP then
						error(name .. " : profil de l'attaquant changé à " .. tostring(diffP))
					end
				end
				expect(attacked > 16 * 25).toBe(true)
				local D = w.h:require("ServerScriptService.Server.Services.DiagnosticsService")
				expect(D.counts().errors).toBe(0)
			end
		)

		it(
			"rafale de 1 000 messages : le seau à jetons laisse passer au plus le débit de Config/Intents",
			function()
				local w, p, q = world()
				local names, Intents = intents(w)
				for _, name in names do
					w.osClock.advance(60)
					local passed = Fuzz.rate(w.h, p, name, 1000, { userId = q.UserId })
					local capacity = Intents[name].rate[1]
					if passed > capacity then
						error(name .. " : " .. passed .. " messages passés pour un débit de " .. capacity)
					end
					expect(passed >= 1).toBe(true)
				end
			end
		)

		it("Activity.note : seulement pour une intention de jeu ACCEPTÉE (activity = true)", function()
			local w, p = world()
			local Activity = w.h:require("ServerScriptService.Server.Util.Activity")
			local WL = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
			local before = Activity.lastActive(p)
			-- UiSeen (interface) : jamais une activité
			w.h:fireServer("ReplicatedStorage.Remotes.UiSeen", p, "dex")
			expect(Activity.lastActive(p)).toBe(before)
			-- FeedPlop de loin : refusé, aucune activité
			w.h:fireServer("ReplicatedStorage.Remotes.FeedPlop", p, true)
			expect(Activity.lastActive(p)).toBe(before)
			-- FeedPlop au bol : accepté
			local bowl = WL.anchor(w.Ranch.slotOf(p), "bowl")
			Bots.place(p, Bots.ground(bowl.X + 2, bowl.Z))
			Brains.frames(w, 3)
			w.osClock.advance(2)
			local t = w.Clock.now()
			w.h:fireServer("ReplicatedStorage.Remotes.FeedPlop", p, true)
			expect(Activity.lastActive(p)).toBe(t)
		end)
	end)
end
