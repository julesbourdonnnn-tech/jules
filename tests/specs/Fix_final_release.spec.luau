--!nocheck
-- Validation finale (passe de durcissement) :
--   * GDD §9.4 : côté coupeur, « Snip » est plus aigu (VFXController passe une hauteur à
--     AudioController.play(name, variation?, pitch?)) ; victime et témoins gardent la hauteur 1
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	local function setup()
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Audio = h:require(CLIENT .. "Controllers.AudioController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			played = {},
		}
		c.State.Init()
		c.WSC.Init()
		c.VFX.Init()
		c.WSC.Start()
		c.VFX.Start()
		c.Audio.play = function(name, variation, pitch)
			table.insert(c.played, { name = name, variation = variation, pitch = pitch })
		end
		h.localPlayer:SetAttribute("Slot", 2)
		h.localPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(Vector3.new(0, 3, 0))
		return c
	end

	local function snip(c, snipperSlot, victimSlot)
		c.WSC.Snipped:Fire({
			snipperSlot = snipperSlot,
			victimSlot = victimSlot,
			ver = 1,
			cutIndex = 1,
			count = 0,
			looseIds = {},
			loose = {},
			byWisp = false,
			x = 4,
			y = 3,
			z = 0,
			dust = 0,
		})
	end

	local function lastSnip(c)
		for i = #c.played, 1, -1 do
			if c.played[i].name == "Snip" then
				return c.played[i]
			end
		end
		return nil
	end

	describe("Validation finale › « Snip » plus aigu côté coupeur (GDD §9.4)", function()
		it("coupeur : hauteur 1,2 ; victime et témoin : hauteur par défaut", function()
			local c = setup()
			snip(c, 2, 5) -- le joueur local coupe
			local mine = lastSnip(c)
			expect(mine ~= nil).toBe(true)
			expect(mine.pitch).toBeNear(1.2, 1e-9)
			expect(mine.variation).toBeNear(0.02, 1e-9)
			snip(c, 5, 2) -- le joueur local est coupé
			local victim = lastSnip(c)
			expect(victim ~= mine).toBe(true)
			expect(victim.pitch).toBeNil()
			expect(victim.variation).toBeNear(0.08, 1e-9)
			snip(c, 5, 6) -- coupe entre deux autres joueurs, tout près
			local witness = lastSnip(c)
			expect(witness ~= victim).toBe(true)
			expect(witness.pitch).toBeNil()
			expect(#c.h.errors).toBe(0)
		end)
	end)
end
