--!nocheck
-- ChaseRenderer (paquet client-world, docs/04 §13.3, §18.2, GDD §9.4, §12.9) : créatures dessinées sur
-- leur trajet SeededPath, doublon ignoré, contours ≤ highlightQuota.chase (6 fuites du Rush + Golden ;
-- qualité réduite : 6), particules ≤ particleQuota.chase, disparition en rétrécissant à la fin (message
-- ou heure de fin passée), zéro trace.

local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local T0 = 1796724120

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function spawn(id, kind, over)
		local s = {
			id = id,
			kind = kind or "wild",
			species = 1,
			mutation = 0,
			size = 3,
			stars = 0,
			ownerSlot = if kind == "escape" then 5 else 0,
			booperSlot = 0,
			uid = "",
			path = "escape",
			seed = id * 13,
			t0 = T0,
			startNode = 1 + id % 20,
			awayAngle = id,
			center = { x = 0, z = 0 },
			speed = 16,
			duration = 25,
			personal = false,
		}
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		h:require(base .. "Util.Prefs").Init()
		local WSC = h:require(base .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local QC = h:require(base .. "Controllers.QualityController")
		if opts.reduced then
			QC.reduced = function()
				return true
			end
		end
		local CR = h:require(base .. "Controllers.ChaseRenderer")
		CR.Init()
		CR.Start()
		h.workspace.CurrentCamera.CFrame = CFrame.new(0, 40, 0)
		local c = { h = h, CR = CR, WSC = WSC, Clock = Clock, QC = QC }
		function c.spawn(list)
			h:fireClient("ReplicatedStorage.Remotes.ChaseEvent", { spawns = list, finishes = {} })
			h:settle(1)
		end
		function c.run(seconds)
			local dt = 1 / 30
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				Clock.advance(dt)
				CR._step(dt)
			end
			h:settle(1)
		end
		function c.clean()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end
		return c
	end

	describe("ChaseRenderer", function()
		it("créatures dessinées sur leur trajet ; doublon ignoré", function()
			local c = client()
			c.spawn({ spawn(1), spawn(2, "runaway", { path = "hop", center = { x = 100, z = 100 } }) })
			c.spawn({ spawn(1) })
			c.run(0.5)
			local st = c.CR.stats()
			expect(st.creatures).toBe(2)
			expect(st.models).toBe(2)
			local drawn = c.CR.positionOf(1)
			local truth = c.WSC.creaturePos(1, c.Clock.now())
			expect(math.abs(drawn.X - truth.X) < 0.01).toBe(true)
			expect(math.abs(drawn.Z - truth.Z) < 0.01).toBe(true)
			c.clean()
		end)

		it("contours ≤ highlightQuota.chase (6 fuites + Golden) ; qualité réduite : 6", function()
			local list = { spawn(50, "golden") }
			for i = 1, 9 do
				table.insert(list, spawn(i, "escape"))
			end
			local c = client()
			c.spawn(list)
			c.run(0.6)
			local quota = c.QC.budgets().highlightQuota.chase
			expect(quota).toBe(7)
			expect(c.CR.stats().highlights).toBe(7)
			local c2 = client({ reduced = true })
			c2.spawn(list)
			c2.run(0.6)
			expect(c2.CR.stats().highlights <= c2.QC.budgets().highlightQuota.chase).toBe(true)
			expect(c2.CR.stats().highlights).toBe(6)
			c.clean()
			c2.clean()
		end)

		it("particules dans particleQuota.chase (traînée dorée)", function()
			local c = client()
			c.spawn({ spawn(50, "golden"), spawn(51, "golden", { startNode = 4 }) })
			c.run(0.3)
			expect(c.CR.stats().particles <= c.QC.budgets().particleQuota.chase).toBe(true)
			local c2 = client({ reduced = true })
			c2.spawn({ spawn(50, "golden") })
			c2.run(0.3)
			expect(c2.CR.stats().particles <= c2.QC.budgets().particleQuota.chase).toBe(true)
			c.clean()
			c2.clean()
		end)

		it(
			"fin par message : rétrécit puis disparaît ; heure de fin passée sans message : disparaît aussi",
			function()
				local c = client()
				c.spawn({ spawn(1), spawn(2, "wild", { duration = 2 }) })
				c.run(0.2)
				c.h:fireClient(
					"ReplicatedStorage.Remotes.ChaseEvent",
					{ spawns = {}, finishes = { { id = 1, reason = "caught", bySlot = 1, t = T0 } } }
				)
				c.h:settle(1)
				c.run(0.1)
				expect(c.CR.positionOf(1)).toBe(nil)
				c.run(0.3)
				expect(c.CR.stats().creatures).toBe(1)
				c.run(2)
				expect(c.CR.stats().creatures).toBe(0)
				expect(c.CR.stats().models).toBe(0)
				c.clean()
			end
		)

		it("charges hostiles et caméra absente : aucune erreur", function()
			local c = client()
			c.spawn({ spawn(1, "wild", { species = 99999, size = 0 / 0 }), { id = "x" }, "y" })
			c.h.workspace.CurrentCamera = nil
			c.run(0.3)
			expect(c.CR.stats().creatures).toBe(1)
			local _ = Vector3
			c.clean()
		end)
	end)
end
