--!nocheck
-- Finition r5, HUD (src/client/UI/HUD.luau) : téléphones 640 × 360 sous la barre Roblox de 58 px
-- (la plus courante aujourd'hui sur Android bas de gamme). Le Dash, remonté par le bouton de saut,
-- recouvrait le suivi de quête : ni la colonne à gauche de la minicarte au-dessus du Dash, ni la
-- place sous le suivi ne tenaient. Dernier recours : une rangée, état à GAUCHE du suivi de quête,
-- au-dessus du Dash, sans toucher la pastille d'événement, Réglages ni la minicarte.
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	local function hudSetup()
		local h = Harness.new({ mode = "client", touch = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
		}
		c.VFX.playDash = function() end
		c.WSC.localSlot = function()
			return 1
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.Input.Init()
		c.HUD.Init()
		c.FX.Start()
		c.Input.Start()
		c.HUD.Start()
		c.HUD.revealAll()
		return c
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	-- écran simulé (comme Fix_client-hud_r2) : bouton de saut tactile de 70 px à (1, −95, 1, −90)
	local function screen(c, width, height, topbar)
		c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(width, height)
		local gui = c.h.localPlayer.PlayerGui.HUD
		gui.AbsoluteSize = Vector2.new(width, height - topbar)
		hud(c).AbsoluteSize = gui.AbsoluteSize
		local playerGui = c.h.localPlayer.PlayerGui
		local touchGui = playerGui:FindFirstChild("TouchGui")
		if touchGui == nil then
			touchGui = c.g.Instance.new("ScreenGui")
			touchGui.Name = "TouchGui"
			local frame = c.g.Instance.new("Frame")
			frame.Name = "TouchControlFrame"
			frame.Parent = touchGui
			local jump = c.g.Instance.new("ImageButton")
			jump.Name = "JumpButton"
			jump.Parent = frame
			touchGui.Parent = playerGui
		end
		local jump = touchGui.TouchControlFrame.JumpButton
		jump.AbsoluteSize = Vector2.new(70, 70)
		jump.AbsolutePosition = Vector2.new(width, height - topbar) + Vector2.new(-95, -90)
		c.HUD._layoutActions()
		c.h:settle(1)
	end

	local function rect(c, holder)
		local gui = c.h.localPlayer.PlayerGui.HUD
		local k = c.Root.scale()
		local W = gui.AbsoluteSize.X / k - 24
		local H = gui.AbsoluteSize.Y / k - 16
		local p, s, a = holder.Position, holder.Size, holder.AnchorPoint
		local x = p.X.Scale * W + p.X.Offset - a.X * s.X.Offset
		local y = p.Y.Scale * H + p.Y.Offset - a.Y * s.Y.Offset
		return { x0 = x, y0 = y, x1 = x + s.X.Offset, y1 = y + s.Y.Offset, W = W, H = H }
	end

	local function overlap(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
	end

	describe("Fix r5 HUD › 640 × 360 sous la barre Roblox de 58 px", function()
		it("état et suivi de quête sur une rangée au-dessus du Dash : rien ne se chevauche", function()
			local c = hudSetup()
			screen(c, 640, 360, 58)
			local dash = rect(c, hud(c).Dash)
			local ping = rect(c, hud(c).Ping)
			local tracker = rect(c, hud(c).QuestTracker)
			local status = rect(c, hud(c).Status)
			local pill = rect(c, hud(c).EventPill)
			local W = dash.W
			local minimap = { x0 = W - 166, y0 = 16, x1 = W - 16, y1 = 166 }
			local named = {
				dash = dash,
				ping = ping,
				tracker = tracker,
				status = status,
				pill = pill,
				minimap = minimap,
				crew = rect(c, hud(c).crew),
				settings = rect(c, hud(c).settings),
			}
			for _, a in { "tracker", "status" } do
				for name, b in named do
					if name ~= a then
						expect({ a = a, b = name, overlap = overlap(named[a], b) }).toEqual({
							a = a,
							b = name,
							overlap = false,
						})
					end
				end
				expect(named[a].x0 >= 0 and named[a].y0 >= 0).toBe(true)
			end
			-- même rangée, l'état à gauche du suivi, au-dessus du Dash et du Ping
			expect(status.y0).toBe(tracker.y0)
			expect(status.x1 <= tracker.x0 - 8 + 1e-6).toBe(true)
			expect(tracker.y1 <= math.min(dash.y0, ping.y0) - 8 + 1e-6).toBe(true)
			expect(#c.h:signalErrors()).toBe(0)
		end)

		it("barre de 36 px (place retrouvée) : la colonne d'avant, l'état sous le suivi", function()
			local c = hudSetup()
			screen(c, 640, 360, 36)
			local tracker = rect(c, hud(c).QuestTracker)
			local status = rect(c, hud(c).Status)
			expect(status.y0 >= tracker.y1).toBe(true)
			expect(overlap(tracker, rect(c, hud(c).Dash))).toBe(false)
		end)
	end)
end
