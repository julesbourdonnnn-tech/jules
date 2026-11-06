--!nocheck
-- Server/Util/Activity (contrat v1.2, GDD v1.3 §4.22, §4.23) : joueurs ACTIFS du MEGA et de la jauge.
-- Intention de jeu acceptée ou déplacement validé ≥ MoveStuds dans les Window dernières secondes ;
-- tremblement sur place jamais compté ; entrées bizarres sans effet ni erreur ; état oublié au départ.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Vector3 = require("@lune/roblox").Vector3

	local function setup()
		local h = Harness.new()
		local Activity = h:require("ServerScriptService.Server.Util.Activity")
		local Events = h:require("ReplicatedStorage.Shared.Config.Events")
		Activity.reset()
		return h, Activity, Events
	end

	describe("Activity", function()
		it("intention acceptée : actif pendant Window secondes, puis inactif", function()
			local h, Activity, Events = setup()
			local p = h:addPlayer({ userId = 11, spawn = false })
			expect(Activity.isActive(p, 1000)).toBe(false)
			Activity.note(p, 1000)
			expect(Activity.isActive(p, 1000)).toBe(true)
			expect(Activity.isActive(p, 1000 + Events.Activity.Window)).toBe(true)
			expect(Activity.isActive(p, 1000 + Events.Activity.Window + 0.1)).toBe(false)
			-- une note plus ancienne ne recule jamais l'instant de la dernière activité
			Activity.note(p, 900)
			expect(Activity.lastActive(p)).toBe(1000)
			expect(#h.errors).toBe(0)
		end)

		it(
			"déplacement validé : MoveStuds depuis l'ancre compte, un tremblement sur place jamais",
			function()
				local h, Activity, Events = setup()
				local p = h:addPlayer({ userId = 12, spawn = false })
				local step = Events.Activity.MoveStuds
				Activity.noteMove(p, Vector3.new(0, 3, 0), 10) -- ancre
				expect(Activity.isActive(p, 10)).toBe(false)
				for i = 1, 200 do
					-- va-et-vient de 1 stud pendant 20 s : jamais actif
					local x = if i % 2 == 0 then 1 else 0
					Activity.noteMove(p, Vector3.new(x, 3, 0), 10 + i * 0.1)
				end
				expect(Activity.isActive(p, 30)).toBe(false)
				Activity.noteMove(p, Vector3.new(step, 3, 0), 31)
				expect(Activity.isActive(p, 31)).toBe(true)
				expect(Activity.lastActive(p)).toBe(31)
				-- marche lente : chaque pas de MoveStuds depuis la nouvelle ancre compte
				Activity.noteMove(p, Vector3.new(step * 1.5, 3, 0), 200)
				expect(Activity.lastActive(p)).toBe(31)
				Activity.noteMove(p, Vector3.new(step * 2, 3, 0), 201)
				expect(Activity.lastActive(p)).toBe(201)
				expect(#h.errors).toBe(0)
			end
		)

		it("entrées bizarres (NaN, inf, mauvais types) : aucun effet, aucune erreur", function()
			local h, Activity = setup()
			local p = h:addPlayer({ userId = 13, spawn = false })
			Activity.note(p, 0 / 0)
			Activity.note(p, math.huge)
			Activity.noteMove(p, Vector3.new(0 / 0, 0, 0), 5)
			Activity.noteMove(p, "pos" :: any, 5)
			Activity.noteMove(p, Vector3.new(0, 0, 0), 0 / 0)
			expect(Activity.isActive(p, 5)).toBe(false)
			expect(Activity.isActive(p, 0 / 0)).toBe(false)
			expect(Activity.lastActive(p)).toBe(-math.huge)
			expect(#h.errors).toBe(0)
		end)

		it("départ du joueur : tout est oublié ; joueur déjà parti : rien n'est retenu", function()
			local h, Activity = setup()
			local p = h:addPlayer({ userId = 14, spawn = false })
			Activity.note(p, 50)
			expect(Activity.isActive(p, 50)).toBe(true)
			h:removePlayer(p)
			h:settle(1)
			expect(Activity.isActive(p, 50)).toBe(false)
			Activity.note(p, 60)
			expect(Activity.lastActive(p)).toBe(-math.huge)
			expect(#h.errors).toBe(0)
		end)

		-- v2.0 (lot A3, N23, docs/04 §27.7) : instant de la dernière intention ACCEPTÉE (sieste des
		-- Plopettes) ; un déplacement (stick calé) ne la change jamais ; jauge et MEGA inchangés
		it("lastIntent : seule une intention acceptée l'avance ; noteMove jamais (N23)", function()
			local h, Activity, Events = setup()
			local p = h:addPlayer({ userId = 15, spawn = false })
			expect(Activity.lastIntent(p)).toBe(-math.huge)
			Activity.note(p, 100)
			expect(Activity.lastIntent(p)).toBe(100)
			Activity.note(p, 90) -- jamais en arrière
			expect(Activity.lastIntent(p)).toBe(100)
			-- stick calé : 60 s de marche, MoveStuds après MoveStuds
			local step = Events.Activity.MoveStuds
			Activity.noteMove(p, Vector3.new(0, 3, 0), 101)
			for i = 1, 60 do
				Activity.noteMove(p, Vector3.new(step * i, 3, 0), 101 + i)
			end
			expect(Activity.lastActive(p)).toBe(161) -- activité de la v1.3 : inchangée
			expect(Activity.isActive(p, 161)).toBe(true)
			expect(Activity.lastIntent(p)).toBe(100)
			-- entrées bizarres : rien
			Activity.note(p, 0 / 0)
			Activity.note(p, math.huge)
			expect(Activity.lastIntent(p)).toBe(100)
			-- départ : oublié
			h:removePlayer(p)
			h:settle(1)
			expect(Activity.lastIntent(p)).toBe(-math.huge)
			Activity.note(p, 200)
			expect(Activity.lastIntent(p)).toBe(-math.huge)
			expect(#h.errors).toBe(0)
		end)

		-- v2.0 (lot A4, N23, décision du propriétaire du 6 novembre) : la navigation dans un menu
		-- (intention MenuActivity) réveille les Plopettes sans être une activité de jeu
		it(
			"noteMenu : avance lastIntent seulement, jamais lastActive (MEGA, jauge) ; jamais en arrière ; entrées bizarres et départ sans effet",
			function()
				local h, Activity = setup()
				local p = h:addPlayer({ userId = 16, spawn = false })
				Activity.noteMenu(p, 300)
				expect(Activity.lastIntent(p)).toBe(300)
				expect(Activity.lastActive(p)).toBe(-math.huge)
				expect(Activity.isActive(p, 300)).toBe(false)
				Activity.noteMenu(p, 250) -- jamais en arrière
				expect(Activity.lastIntent(p)).toBe(300)
				-- une intention de jeu plus ancienne ne recule pas lastIntent, mais compte pour lastActive
				Activity.note(p, 290)
				expect(Activity.lastIntent(p)).toBe(300)
				expect(Activity.lastActive(p)).toBe(290)
				Activity.noteMenu(p, 0 / 0)
				Activity.noteMenu(p, math.huge)
				Activity.noteMenu(p, -math.huge)
				expect(Activity.lastIntent(p)).toBe(300)
				expect(Activity.lastActive(p)).toBe(290)
				h:removePlayer(p)
				h:settle(1)
				Activity.noteMenu(p, 400) -- joueur parti : rien n'est retenu
				expect(Activity.lastIntent(p)).toBe(-math.huge)
				expect(#h.errors).toBe(0)
			end
		)
	end)
end
