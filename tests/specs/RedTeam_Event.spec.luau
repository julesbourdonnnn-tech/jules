--!nocheck
-- Contre-audit des événements (remarque A22, docs/04 §15, §17.1 g), écrit comme des attaques :
--   * MegaPress à 25 studs, plus vite que 0,4 s, tClient truqué (futur, passé lointain, NaN), hors de la
--     phase de pression, pieds à 12 studs au-dessus du pad ;
--   * GrandSplorch hors du ranch, en portant, flyer d'un autre ou au Dodo, double entrée dans la file,
--     pendant une fuite ;
--   * AdminCommand d'un non-administrateur : aucune réponse, aucune mutation (toutes les commandes).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function points(w)
		return w.Event.state().mega.points
	end

	describe("RedTeam_Event › MegaPress", function()
		it(
			"à 25 studs, pieds à 12 studs, hors phase : 0 point ; plus vite que 0,4 s : 1 appui compté sur 4",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 1190 })
				local a = Brains.join(w, 1)
				local pad = w.WL.plaza("megaPad")
				Bots.place(a, Bots.ground(pad.X + 3, pad.Z))
				Brains.frames(w, 2)
				-- alerte (avant l'atterrissage) : hors phase
				w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
				Brains.frames(w, 110)
				expect(w.Event.state().mega.phase).toBe("press")
				expect(points(w)).toBe(0)
				-- 25 studs
				Bots.place(a, Bots.ground(pad.X + 25, pad.Z))
				Brains.frames(w, 5)
				w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
				Brains.frames(w, 5)
				expect(points(w)).toBe(0)
				-- pieds à 12 studs au-dessus du pad (racine posée en l'air par le serveur)
				Bots.place(a, w.V3.new(pad.X, 3 + 12, pad.Z))
				Brains.frames(w, 1)
				w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
				expect(points(w)).toBe(0)
				-- au pad : 4 appuis à 0,1 s d'intervalle → 1 seul compté (recharge 0,4 s)
				Bots.place(a, Bots.ground(pad.X + 3, pad.Z))
				Brains.frames(w, 5)
				local presses0 = w.Event.state().mega.points
				for _ = 1, 3 do
					w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, w.Clock.now())
					Brains.frames(w, 1)
				end
				local gained = points(w) - presses0
				expect(gained == 1 or gained == 3).toBe(true)
				clean(w)
			end
		)

		it(
			"tClient truqué : futur ou passé lointain ramenés à maintenant (au plus le PERFECT d'un appui normal), NaN refusé",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 1199 })
				local a = Brains.join(w, 1)
				local pad = w.WL.plaza("megaPad")
				Bots.place(a, Bots.ground(pad.X + 3, pad.Z))
				Brains.frames(w, 20)
				local MegaRules = w.h:require("ReplicatedStorage.Shared.Logic.MegaRules")
				local landsAt = w.Event.state().mega.landsAt
				for _, offset in { 1000, -1000, 0.05, -0.34 } do
					local before = points(w)
					local now = w.Clock.now()
					w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, now + offset)
					local gained = points(w) - before
					local PressTiming = w.h:require("ReplicatedStorage.Shared.Logic.PressTiming")
					local expected = if MegaRules.isPerfect(
							landsAt,
							PressTiming.clampClientTime(now + offset, now)
						)
						then 3
						else 1
					expect(gained).toBe(expected)
					Brains.frames(w, 5)
				end
				local before = points(w)
				w.h:fireServer("ReplicatedStorage.Remotes.MegaPress", a, 0 / 0)
				expect(points(w)).toBe(before)
				clean(w)
			end
		)
	end)

	describe("RedTeam_Event › GrandSplorch", function()
		local function ready(w)
			return Brains.profile(w, {
				squishies = {
					{ s = 1, z = 100, bf = 1 },
					{ s = 2, z = 20000 },
					{ s = 3, z = 300 },
					{ s = 4, z = 50, at = "dodo" },
				},
			})
		end

		it(
			"hors du ranch, flyer d'un autre ou au Dodo, double entrée, pendant une fuite : aucune entrée en trop",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 60 })
				local a = Brains.join(w, 1, { profile = ready(w) })
				local b = Brains.join(w, 2, { profile = ready(w) })
				Bots.place(a, Bots.ground(0, 40))
				Brains.frames(w, 2)
				local function fire(p, flyer)
					w.h:fireServer("ReplicatedStorage.Remotes.GrandSplorch", p, true, flyer)
					Brains.frames(w, 21)
				end
				fire(a, "2") -- hors du ranch
				expect(w.Squishy.waiting(a)).toBeNil()
				Bots.place(a, Brains.atRanch(w, a, 0, 30))
				Brains.frames(w, 2)
				fire(a, "4") -- au Dodo
				fire(a, "9") -- inconnu (uid d'un autre profil possible)
				expect(w.Squishy.waiting(a)).toBeNil()
				-- pendant une fuite
				w.Squishy.setEscaping(a, "3", true)
				fire(a, "2")
				expect(w.Squishy.waiting(a)).toBeNil()
				w.Squishy.setEscaping(a, "3", false)
				-- B passe d'abord (spectacle en cours) ; A accepté derrière lui, puis double entrée de A
				Bots.place(b, Brains.atRanch(w, b, 0, 30))
				Brains.frames(w, 2)
				fire(b, "2")
				expect(w.Squishy.waiting(b)).toBe("2")
				fire(a, "2")
				expect(w.Squishy.waiting(a)).toBe("2")
				fire(a, "3")
				expect(w.Squishy.waiting(a)).toBe("2")
				expect(table.find(Bots.feedbackKeys(a), "feedback.waitingSplorch") ~= nil).toBe(true)
				local queued = 0
				for _, e in w.Event.state().spectacle.queue do
					if e.userId == 1 then
						queued += 1
					end
				end
				expect(queued).toBe(1)
				-- en portant : un troisième joueur prêt
				local c = Brains.join(w, 3, { profile = ready(w) })
				Bots.place(c, Brains.atRanch(w, c, 0, 30))
				Brains.frames(w, 2)
				w.h:fireServer("ReplicatedStorage.Remotes.PickUp", c, "3")
				if w.Squishy.carried(c) ~= nil then
					fire(c, "2")
					expect(w.Squishy.waiting(c)).toBeNil()
					expect(table.find(Bots.feedbackKeys(c), "feedback.carrying") ~= nil).toBe(true)
				end
				clean(w)
			end
		)
	end)

	describe("RedTeam_Event › AdminCommand", function()
		it("non-administrateur : aucune réponse, aucune mutation, pour chaque commande", function()
			local w = Brains.boot(Harness, { t0 = H0 + 60, harness = { isStudio = true } })
			local a = Brains.join(w, 1)
			Brains.frames(w, 2)
			local function sent()
				-- réponses à l'envoyeur (EventState peut partir pour une autre raison : on vérifie l'état)
				return #w.h:sentTo(a, "Feedback") + #w.h:sentTo(a, "Celebrate")
			end
			local before = sent()
			local state0 = w.Event.state()
			for _, cmd in
				{
					{ "party", "" },
					{ "feature", "MegaSquish=false" },
					{ "feature", "BoopRush=off" },
					{ "clock", "3600" },
					{ "forceRush", "" },
					{ "forceMega", "" },
					{ "testError", "client" },
					{ "testError", "server" },
					{ "photo", "on" },
				}
			do
				w.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", a, cmd[1], cmd[2])
				Brains.frames(w, 6)
			end
			expect(sent()).toBe(before)
			expect(w.Features.get("MegaSquish")).toBe(true)
			expect(w.Features.get("BoopRush")).toBe("on")
			expect(w.Clock.getOffset()).toBe(0)
			expect(w.Event.state().boost.kind).toBe("")
			expect(w.Event.rushActive()).toBe(state0.rush.active)
			expect(w.Event.state().mega.phase).toBe("idle")
			clean(w)
		end)
	end)
end
