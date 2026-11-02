--!nocheck
-- EventService : défauts trouvés par la revue adversariale du lot chase (chaque test reproduit le
-- défaut avant sa correction).
--   1. Un EventState envoyé à UN joueur (PlayerReady, RequestWorld) effaçait l'envoi en attente pour
--      tous : un changement fait hors du tick (file des spectacles…) n'arrivait jamais aux autres.
--   2. Phases « party » : quand deux fêtes se chevauchent (payée pendant une fête d'administrateur ou
--      une Wobble Party), la fin de la première était émise avec l'index de la seconde (ou jamais).
--   3. partyUnplayed : un acheteur parti (remboursé à son départ par ProductService) puis revenu sur le
--      même serveur voyait ses anciens segments comptés une seconde fois.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000 -- vendredi 08:00:00 UTC (début d'heure) ; Rush à :05:00 → :06:30

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function lastState(w, p)
		local list = w.h:sentTo(p, "EventState")
		return list[#list] and list[#list][1]
	end

	describe("EventService (revue) › EventState", function()
		it(
			"une arrivée (RequestWorld, PlayerReady) n'efface jamais l'envoi en attente pour les autres",
			function()
				-- pendant un Rush : une entrée de la file attend la fin du Rush + 20 s (aucun départ au tick)
				local w = Brains.boot(Harness, { t0 = H0 + 310 })
				local a = Brains.join(w, 1)
				local b = Brains.join(w, 2)
				Brains.frames(w, 5)
				expect(#lastState(w, a).spectacle.queue).toBe(0)
				w.Event.enqueueSpectacle("splorch", a.UserId) -- changement hors du tick
				w.Signals.WorldRequested:Fire(b) -- état envoyé à b seul
				Brains.frames(w, 2)
				local st = lastState(w, a)
				expect(#st.spectacle.queue).toBe(1)
				expect(st.spectacle.queue[1].userId).toBe(a.UserId)
				-- même chose avec l'arrivée d'un joueur (PlayerReady)
				w.Event.cancelSpectacle(a.UserId)
				Brains.frames(w, 2)
				expect(#lastState(w, a).spectacle.queue).toBe(0)
				w.Event.enqueueSpectacle("splorch", b.UserId)
				local c = Brains.join(w, 3)
				Brains.frames(w, 2)
				expect(#lastState(w, a).spectacle.queue).toBe(1)
				expect(#lastState(w, c).spectacle.queue).toBe(1)
				clean(w)
			end
		)
	end)

	describe("EventService (revue) › phases des fêtes", function()
		it(
			"fêtes qui se chevauchent : chaque « party:start » a exactement une « party:end » du même index",
			function()
				local w = Brains.boot(Harness, { t0 = H0 + 60 })
				local a = Brains.join(w, 1)
				w.meta.admins[1] = true
				Brains.frames(w, 2)
				local starts, ends = {}, {}
				w.Signals.EventPhase:Connect(function(kind, phase, index)
					if kind == "party" and phase == "start" then
						table.insert(starts, index)
					elseif kind == "party" and phase == "end" then
						table.insert(ends, index)
					end
				end)
				-- fête d'administrateur, puis une Squish Party payée par-dessus (l'administrateur passe en pause)
				w.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", a, "party", "")
				Brains.frames(w, 2)
				w.Event.startSquishParty(a, false)
				Brains.frames(w, 2)
				expect(#starts).toBe(2)
				-- la Squish Party finit (600 s), puis la fête d'administrateur reprend et finit
				w.Clock.freeze(w.Clock.now() + 601)
				Brains.frames(w, 2)
				w.Clock.freeze(w.Clock.now() + 601)
				Brains.frames(w, 2)
				expect(w.Event.state().boost.kind).toBe("")
				table.sort(starts)
				table.sort(ends)
				expect(#ends).toBe(#starts)
				for i = 1, #starts do
					expect(ends[i]).toBe(starts[i])
				end
				clean(w)
			end
		)
	end)

	describe("EventService (revue) › Squish Party payée, jamais rendue deux fois", function()
		it("acheteur parti puis revenu : ses anciens segments ne comptent plus dans partyUnplayed", function()
			local w = Brains.boot(Harness, { t0 = H0 + 60 })
			local a = Brains.join(w, 1)
			local b = Brains.join(w, 2)
			Brains.frames(w, 2)
			-- b achète une fête ; a achète pendant la fête : son segment de 600 s attend, entier
			w.Event.startSquishParty(b, false)
			w.Event.startSquishParty(a, false)
			Brains.frames(w, 10)
			expect(w.Event.partyUnplayed(1)).toBe(600)
			-- a part (ProductService lui rend ces 600 s en boost personnel à sa sauvegarde de départ)…
			Bots.leave(a)
			w.h:settle(2)
			Brains.frames(w, 2)
			-- … et revient sur le même serveur : rien ne lui est dû une seconde fois
			local back = Brains.join(w, 1)
			Brains.frames(w, 2)
			expect(w.Event.partyUnplayed(back.UserId)).toBe(0)
			-- un nouvel achat de sa part compte normalement
			w.Event.startSquishParty(back, false)
			expect(w.Event.partyUnplayed(back.UserId)).toBe(600)
			-- la fête continue pour les autres (segments joués jusqu'au bout)
			expect(w.Event.state().boost.kind).toBe("squish")
			clean(w)
		end)
	end)
end
