--!nocheck
-- ChaseController (paquet client-world, docs/04 §13.3, §10.1, §18.2, GDD §4.12) : bond scripté sur
-- l'arc de LeapRules (12 studs en 0,35 s, même point d'atterrissage que le serveur, arrêt devant un
-- solide), Leap(dirX, dirZ, Clock.now()), recharge de 4 s, refusé en portant, visée sur la position
-- future de la créature visée, Catch(id, Clock.now()) à portée, tampon d'entrée de 0,25 s (gardé puis
-- oublié), personnage absent toléré, zéro trace.

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local T0 = 1796724120

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId, over)
		local r = {
			slot = slot,
			userId = userId,
			name = "P",
			hidden = false,
			R = 0,
			fame = 0,
			day = 0,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = T0 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = 0, m = 0, z = 0, zg = 0 },
		}
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end

	local function wild(id)
		return {
			id = id,
			kind = "wild",
			species = 1,
			mutation = 0,
			size = 3,
			stars = 0,
			ownerSlot = 0,
			booperSlot = 0,
			uid = "",
			path = "escape",
			seed = 7,
			t0 = T0,
			startNode = 3,
			awayAngle = 0.5,
			center = { x = 0, z = 0 },
			speed = 16,
			duration = 25,
			personal = false,
		}
	end

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		h:require(base .. "Util.Prefs").Init()
		h:require(base .. "Controllers.StateController").Init()
		local WSC = h:require(base .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local PC = h:require(base .. "Controllers.PromptController")
		local aimed = nil
		PC.leapTarget = function()
			return aimed
		end
		local CC = h:require(base .. "Controllers.ChaseController")
		CC.Init()
		CC.Start()
		h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
			seq = 1,
			ranches = { ["3"] = ranch(3, 1, opts.ranch) },
			squishies = { ["3"] = {} },
		})
		h:settle(1)
		local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local LeapRules = h:require("ReplicatedStorage.Shared.Logic.LeapRules")
		local c =
			{ h = h, WSC = WSC, CC = CC, Clock = Clock, WorldLayout = WorldLayout, LeapRules = LeapRules }
		function c.root()
			local ch = h.localPlayer.Character
			return ch and ch:FindFirstChild("HumanoidRootPart")
		end
		function c.place(pos, look)
			local p = Vector3.new(pos.X, WorldLayout.supportY(pos) + 3, pos.Z)
			c.root().CFrame = CFrame.lookAt(p, p + (look or Vector3.new(0, 0, -1)))
			return p
		end
		function c.aim(id)
			aimed = id
		end
		function c.run(seconds)
			local dt = 1 / 60
			for _ = 1, math.floor(seconds / dt + 0.5) do
				Clock.advance(dt)
				CC._step(dt)
			end
		end
		function c.sent(name)
			local out = {}
			for _, e in h.log.serverEvents do
				if e.remote == name then
					table.insert(out, e.args)
				end
			end
			return out
		end
		function c.spawn(s)
			h:fireClient("ReplicatedStorage.Remotes.ChaseEvent", { spawns = { s }, finishes = {} })
			h:settle(1)
		end
		function c.clean()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end
		return c
	end

	local function flatDist(a, b)
		return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
	end

	describe("ChaseController", function()
		it(
			"bond : Leap(dirX, dirZ, Clock.now()), arc de 12 studs en 0,35 s, point d'atterrissage de LeapRules",
			function()
				local c = client()
				local from =
					c.place(c.WorldLayout.plaza("center") + Vector3.new(0, 0, 30), Vector3.new(1, 0, 0))
				local leaped = 0
				c.CC.Leaped:Connect(function()
					leaped += 1
				end)
				expect(c.CC.leap()).toBe(true)
				local sent = c.sent("Leap")
				expect(#sent).toBe(1)
				expect(math.abs(sent[1][1] - 1) < 1e-6).toBe(true)
				expect(math.abs(sent[1][2]) < 1e-6).toBe(true)
				expect(sent[1][3]).toBe(T0)
				c.run(0.2)
				local mid = c.root().Position
				expect(mid.Y > from.Y).toBe(true) -- en l'air (sommet 2,5 studs)
				c.run(0.25)
				local landing = c.LeapRules.landing(from, Vector3.new(1, 0, 0))
				expect(flatDist(c.root().Position, landing) < 0.05).toBe(true)
				expect(c.CC.leaping()).toBe(false)
				c.h:settle(1)
				expect(leaped).toBe(1)
				c.clean()
			end
		)

		it("recharge de 4 s : un second bond est refusé, cooldownLeft décroît", function()
			local c = client()
			c.place(c.WorldLayout.plaza("center") + Vector3.new(0, 0, 30))
			expect(c.CC.leap()).toBe(true)
			c.run(1)
			expect(c.CC.leap()).toBe(false)
			expect(math.abs(c.CC.cooldownLeft() - 3) < 0.05).toBe(true)
			c.run(3.1)
			expect(c.CC.cooldownLeft()).toBe(0)
			expect(c.CC.leap()).toBe(true)
			expect(#c.sent("Leap")).toBe(2)
			c.clean()
		end)

		it("arrêt devant un solide : même raccourci que le serveur (mur de clôture)", function()
			local c = client()
			local inside = c.WorldLayout.toWorld(3, Vector3.new(0, 0, 66))
			local back = c.WorldLayout.toWorld(3, Vector3.new(0, 0, 80)) - inside
			local dir = Vector3.new(back.X, 0, back.Z).Unit
			local from = c.place(inside, dir)
			expect(c.CC.leap()).toBe(true)
			c.run(0.5)
			local landing = c.LeapRules.landing(from, dir)
			expect(flatDist(landing, from) < 11.9).toBe(true)
			expect(flatDist(c.root().Position, landing) < 0.05).toBe(true)
			c.clean()
		end)

		it("en portant : aucun bond, aucun envoi ; sans personnage : aucun bond", function()
			local c = client({ ranch = { carry = "a" } })
			c.place(c.WorldLayout.plaza("center") + Vector3.new(0, 0, 30))
			expect(c.CC.leap()).toBe(false)
			expect(#c.sent("Leap")).toBe(0)
			local c2 = client()
			c2.h.localPlayer.Character:Destroy()
			c2.h.localPlayer.Character = nil
			expect(c2.CC.leap()).toBe(false)
			c2.run(0.5)
			c.clean()
			c2.clean()
		end)

		it("visée automatique : direction vers la position de la créature à l'atterrissage", function()
			local c = client()
			c.spawn(wild(9))
			local future = c.WSC.creaturePos(9, T0 + 0.35)
			local from = c.place(future + Vector3.new(8, 0, 0), Vector3.new(0, 0, 1))
			c.aim(9)
			expect(c.CC.leap()).toBe(true)
			local sent = c.sent("Leap")[1]
			local want = (Vector3.new(future.X - from.X, 0, future.Z - from.Z)).Unit
			expect(math.abs(sent[1] - want.X) < 1e-3).toBe(true)
			expect(math.abs(sent[2] - want.Z) < 1e-3).toBe(true)
			c.clean()
		end)

		it("capture : Catch(id, Clock.now()) à portée ; tampon de 0,25 s gardé puis oublié", function()
			local c = client()
			c.spawn(wild(5))
			local p0 = c.WSC.creaturePos(5, T0)
			c.place(p0 + Vector3.new(2, 0, 0))
			expect(c.CC.tryCatch()).toBe(true)
			local sent = c.sent("Catch")
			expect(#sent).toBe(1)
			expect(sent[1][1]).toBe(5)
			expect(sent[1][2]).toBe(T0)
			-- un point du trajet hors de portée maintenant, à portée dans 0,2 s
			local now = c.Clock.now()
			local ahead = nil
			for k = 1, 60 do
				local q = c.WSC.creaturePos(5, now + k * 0.02)
				if
					flatDist(q, c.WSC.creaturePos(5, now)) > 6
					and flatDist(q, c.WSC.creaturePos(5, now + 0.2)) < 4
				then
					ahead = q
					break
				end
			end
			expect(ahead ~= nil).toBe(true)
			c.place(ahead)
			expect(c.CC.tryCatch()).toBe(false)
			c.run(0.22)
			expect(#c.sent("Catch")).toBe(2)
			-- loin : le tampon expire sans envoi
			local far = c.WSC.creaturePos(5, c.Clock.now()) + Vector3.new(40, 0, 0)
			c.place(far)
			expect(c.CC.tryCatch()).toBe(false)
			c.run(0.5)
			expect(#c.sent("Catch")).toBe(2)
			c.clean()
		end)
		-- Revue client-world : l'écart vertical de la capture se mesure comme le serveur (ChaseService :
		-- pieds − WorldLayout.groundY(créature)), jamais depuis le dessus d'un solide (supportY)
		it(
			"capture : écart vertical mesuré comme le serveur (sol de la créature, pas un solide)",
			function()
				local c = client()
				local Balance = c.h:require("ReplicatedStorage.Shared.Config.Balance")
				local found = nil
				for i, s in c.WorldLayout.solidsView() do
					if i > 1 and found == nil then
						local ground = c.WorldLayout.groundY(s.cx, s.cz)
						if s.top - ground > Balance.Catch.MaxDY + 1 then
							local half = math.min(s.hx, s.hz)
							if half <= 3 then
								local ax = if s.hx <= s.hz
									then Vector3.new(s.ux, 0, s.uz)
									else Vector3.new(-s.uz, 0, s.ux)
								local out = Vector3.new(s.cx, 0, s.cz) + ax * (half + 0.8)
								if not c.WorldLayout.blocked(out.X, out.Z, 0.5) then
									found = { center = Vector3.new(s.cx, 0, s.cz), out = out }
								end
							end
						end
					end
				end
				expect(found ~= nil).toBe(true)
				c.spawn(wild(1))
				c.WSC.creaturePos = function()
					return found.center
				end
				c.place(found.out)
				expect(c.CC.tryCatch()).toBe(true)
				expect(#c.sent("Catch")).toBe(1)
				c.clean()
			end
		)

		-- Revue client-world : un bond que le serveur ne connaîtra pas (intention Leap non partie)
		-- n'est jamais joué (sinon : déplacement non crédité, repoussé par MoveCheck)
		it(
			"bond : rien si l'intention Leap n'est pas partie ; vitesse de la racine nulle pendant l'arc",
			function()
				local c = client()
				local Util = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.Util")
				local real = Util.send
				local block = true
				Util.send = function(name, ...)
					if name == "Leap" and block then
						return false
					end
					return real(name, ...)
				end
				local from = c.place(c.WorldLayout.plaza("center") + Vector3.new(0, 0, 30))
				expect(c.CC.leap()).toBe(false)
				c.run(0.5)
				expect((c.root().Position - from).Magnitude < 0.01).toBe(true)
				expect(c.CC.cooldownLeft()).toBe(0)
				block = false
				c.root().AssemblyLinearVelocity = Vector3.new(0, -60, 0)
				expect(c.CC.leap()).toBe(true)
				c.run(1 / 60)
				expect(c.root().AssemblyLinearVelocity.Magnitude < 0.01).toBe(true)
				c.run(0.5)
				expect(#c.sent("Leap")).toBe(1)
				c.clean()
			end
		)
	end)
end
