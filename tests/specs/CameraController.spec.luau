--!nocheck
-- CameraController (paquet client-world, docs/04 §13.3, GDD §9.1, §9.4, §10.4) : la caméra ne bouge
-- jamais toute seule sauf le travelling du Grand Splorch du héros (calé sur l'heure du serveur, rendu
-- à la fin ou au plus tard 10 s d'images après), rien en Mouvement réduit, version courte et Grand
-- Splorch d'un autre sans travelling (secousse atténuée par la distance), coup de focale qui revient
-- exactement, secousse bornée (≤ 0,4, ≤ 0,3 s) qui revient à zéro, MEGA seulement si l'interrupteur
-- est vrai, charges hostiles, zéro trace.

local roblox = require("@lune/roblox")
local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local T0 = 1796724120

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		local Prefs = h:require(base .. "Util.Prefs")
		Prefs.Init()
		local rm = opts.reducedMotion == true
		Prefs.reducedMotion = function()
			return rm
		end
		local WSC = h:require(base .. "Controllers.WorldStateController")
		local ev = opts.event
		WSC.event = function()
			return ev
		end
		WSC.mySlot = function()
			return 3
		end
		local Cam = h:require(base .. "Controllers.CameraController")
		Cam.Init()
		Cam.Start()
		local camera = h.workspace.CurrentCamera
		local c = { h = h, Cam = Cam, Clock = Clock, camera = camera }
		function c.setEvent(e)
			ev = e
		end
		function c.celebrate(kind, data)
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = kind, data = data })
			h:settle(1)
		end
		function c.run(seconds, advanceClock)
			local dt = 1 / 30
			for _ = 1, math.floor(seconds / dt + 0.5) do
				if advanceClock ~= false then
					Clock.advance(dt)
				end
				Cam._step(dt)
			end
		end
		function c.humanoid()
			local ch = h.localPlayer.Character
			return ch and ch:FindFirstChildOfClass("Humanoid")
		end
		function c.clean()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end
		return c
	end

	local function splorch(userId, short)
		return {
			userId = userId,
			level = 3,
			flyer = { s = 1, m = 0, st = 0, z = 10 },
			startedAt = T0,
			burstAt = T0 + 3.2,
			endsAt = T0 + 7.5,
			short = short == true,
		}
	end

	describe("CameraController", function()
		it("héros : travelling calé sur l'heure du serveur, caméra rendue à la fin", function()
			local c = client()
			local before = c.camera.CameraType
			c.celebrate("splorch", splorch(1))
			expect(c.Cam.busy()).toBe(true)
			c.run(1)
			expect(c.camera.CameraType).toBe(Enum.CameraType.Scriptable)
			c.run(7)
			expect(c.Cam.busy()).toBe(false)
			expect(c.camera.CameraType).toBe(before)
			c.clean()
		end)

		it("horloge figée : le travelling rend quand même la caméra après 10 s d'images", function()
			local c = client()
			c.Cam.splorch(T0, T0 + 3.2, T0 + 7.5)
			c.run(5, false)
			expect(c.Cam.busy()).toBe(true)
			c.run(6, false)
			expect(c.Cam.busy()).toBe(false)
			expect(c.camera.CameraType).toBe(Enum.CameraType.Custom)
			c.clean()
		end)

		it("Mouvement réduit : ni travelling, ni focale, ni secousse", function()
			local c = client({ reducedMotion = true })
			local fov = c.camera.FieldOfView
			c.celebrate("splorch", splorch(1))
			expect(c.Cam.busy()).toBe(false)
			c.Cam.fovPunch(6, 0.5)
			c.Cam.shake(0.4, 0.3)
			c.run(0.2)
			expect(c.camera.FieldOfView).toBe(fov)
			expect(c.camera.CameraType).toBe(Enum.CameraType.Custom)
			local hum = c.humanoid()
			if hum then
				expect(hum.CameraOffset).toBe(Vector3.zero)
			end
			c.clean()
		end)

		it("version courte et Grand Splorch d'un autre : jamais de travelling", function()
			local c = client()
			c.celebrate("splorch", splorch(1, true))
			expect(c.Cam.busy()).toBe(false)
			c.celebrate("splorch", splorch(2))
			expect(c.Cam.busy()).toBe(false)
			c.run(8)
			expect(c.camera.CameraType).toBe(Enum.CameraType.Custom)
			c.clean()
		end)

		it(
			"coup de focale : monte puis revient exactement ; secousse bornée qui revient à zéro",
			function()
				local c = client()
				local fov = c.camera.FieldOfView
				c.Cam.fovPunch(6, 0.5)
				c.run(0.1)
				expect(c.camera.FieldOfView > fov).toBe(true)
				expect(c.camera.FieldOfView <= fov + 6).toBe(true)
				c.run(0.6)
				expect(c.camera.FieldOfView).toBe(fov)
				local hum = c.humanoid()
				expect(hum ~= nil).toBe(true)
				c.Cam.shake(5, 5) -- demandé trop fort et trop long : borné
				local peak = 0
				for _ = 1, 6 do
					c.run(1 / 30)
					peak = math.max(peak, hum.CameraOffset.Magnitude)
				end
				expect(peak <= 0.4 * math.sqrt(2) + 1e-6).toBe(true)
				c.run(0.3)
				expect(hum.CameraOffset).toBe(Vector3.zero)
				c.clean()
			end
		)

		it("charges hostiles : rien ne bouge, aucune erreur", function()
			local c = client()
			local nan = 0 / 0
			for _, d in
				{
					{ userId = 1, startedAt = nan, burstAt = 1, endsAt = 2 },
					{ userId = 1, startedAt = T0, burstAt = T0, endsAt = T0 - 1 },
					{ userId = 1, startedAt = T0, burstAt = T0, endsAt = T0 + 999 },
					{ userId = "x" },
				}
			do
				c.celebrate("splorch", d)
			end
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", "x")
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "hatch", data = { rarity = nan } })
			c.h:settle(1)
			c.Cam.fovPunch(nan, 1)
			c.Cam.shake(nan, nan)
			expect(c.Cam.busy()).toBe(false)
			c.run(1)
			expect(c.camera.CameraType).toBe(Enum.CameraType.Custom)
			c.clean()
		end)

		it("MEGA : secousse à l'atterrissage seulement si megaSquish est vrai", function()
			local mega = {
				phase = "press",
				index = 4,
				landsAt = T0 + 0.1,
				endsAt = T0 + 20,
				target = 1,
				points = 0,
				species = 1,
				moon = false,
				result = "",
			}
			local c = client({ event = { mega = mega, features = { megaSquish = false } } })
			c.run(0.3)
			local hum = c.humanoid()
			expect(hum.CameraOffset).toBe(Vector3.zero)
			c.clean()
		end)
	end)
end
