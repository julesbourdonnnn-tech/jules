--!nocheck
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	describe("Build (décor en primitives)", function()
		it("construit arbres, rochers, nuages, lampes et panneaux sans erreur", function()
			local h = Harness.new()
			local Build = h:require("ServerScriptService.Server.World.Build")
			local g = h.globals
			local rng = g.Random.new(42)
			local root = Build.model("Decor", h.workspace)
			for i = 1, 5 do
				Build.tree(root, g.Vector3.new(i * 10, 0, 0), 1, rng)
				Build.rock(root, g.Vector3.new(i * 10, 0, 10), 1, rng)
			end
			Build.cloud(root, g.Vector3.new(0, 60, 0), 1, rng)
			Build.lamp(root, g.Vector3.new(0, 0, 0))
			Build.sign(root, g.CFrame.new(0, 5, 0), g.Vector2.new(8, 3), "Hello")
			local part = Build.part({ Name = "P", Parent = root })
			Build.billboard(part, "Label", 3)
			Build.particles(part, { Rate = 5 })
			local count = 0
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					count += 1
					expect(d.Anchored).toBe(true)
				end
			end
			expect(count).toBeGreaterThan(15)
			local tagged = h.game.CollectionService:GetTagged("Float")
			expect(#tagged).toBeGreaterThan(2)
		end)
	end)

	describe("Ambiance", function()
		it("applique le crépuscule sans erreur et de façon idempotente", function()
			local h = Harness.new()
			local L = h:require("ServerScriptService.Server.World.Lighting")
			L.applyTwilight()
			L.applyTwilight()
			expect(h.game.Lighting.ClockTime).toBe(18.4)
			local atmospheres = 0
			for _, c in h.game.Lighting:GetChildren() do
				if c.ClassName == "Atmosphere" then
					atmospheres += 1
				end
			end
			expect(atmospheres).toBe(1)
		end)
	end)

	describe("WorldFXController", function()
		it("anime Spin/Float/Pulse et oublie les objets détruits", function()
			local h = Harness.new({ mode = "client" })
			local FX = h:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldFXController")
			local g = h.globals
			local cs = h.game.CollectionService
			local spin = g.Instance.new("Part")
			spin.CFrame = g.CFrame.new(0, 10, 0)
			spin:SetAttribute("speed", 2)
			spin.Parent = h.workspace
			cs:AddTag(spin, "Spin")
			cs:AddTag(spin, "Float")
			FX.Start()
			local pulse = g.Instance.new("Part")
			pulse.Size = g.Vector3.new(2, 2, 2)
			pulse.Parent = h.workspace
			cs:AddTag(pulse, "Pulse")
			h:settle(2)
			h:step(1 / 60, 5)
			FX._step()
			expect(math.abs(spin.Position.Y - 10)).toBeLessThan(0.6)
			pulse:Destroy()
			FX._step()
			expect(FX._entries.Pulse[pulse]).toBeNil()
		end)
	end)
end
