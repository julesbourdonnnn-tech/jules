--!nocheck
-- Minimap (paquet client-hud) : projection monde → carte (nord en haut, bornée au cercle), points des
-- joueurs depuis les miettes serveur (taille selon la file, joueur local distingué), Nids (couleur du
-- propriétaire / libre), Gloomwisps, Comète clignotante, agrandissement 150 → 300 (M, appui),
-- affichage progressif via le HUD, données absentes ou absurdes (docs §13.13, GDD §6.4).
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local UDim2 = roblox.UDim2

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
			Zones = h:require("ReplicatedStorage.Shared.Config.Zones"),
			Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
			Minimap = h:require(CLIENT .. "UI.Minimap"),
			slot = 0,
			owners = {},
			heads = {},
			lengths = {},
			events = nil,
			wisps = {},
			comet = nil,
		}
		-- isolation : miroir du monde (paquet client-world) remplacé
		c.WSC.localSlot = function()
			return c.slot
		end
		c.WSC.userAt = function(slot)
			return c.owners[slot] or 0
		end
		c.WSC.lineLength = function(slot)
			return c.lengths[slot] or 0
		end
		c.WSC.trail = function(slot)
			local head = c.heads[slot]
			if head == nil then
				return nil
			end
			return {
				head = function()
					return head
				end,
			}
		end
		c.WSC.events = function()
			return c.events
		end
		c.WSC.wispPosition = function(id)
			return c.wisps[id]
		end
		c.WSC.cometPosition = function()
			return c.comet
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.Input.Init()
		c.HUD.Init()
		c.Minimap.Init()
		c.FX.Start()
		c.Input.Start()
		c.HUD.Start()
		c.Minimap.Start()
		return c
	end

	local function holder(c)
		return c.h.localPlayer.PlayerGui.Minimap.Safe.Minimap
	end

	local function update(c)
		c.Minimap._update(c.Clock.now())
	end

	describe("Minimap › projection", function()
		it("centre, bords, nord en haut, bornée au cercle, entrées absurdes", function()
			local c = setup()
			local P = c.Minimap.project
			expect(P(Vector3.new(0, 50, 0))).toEqual(Vector2.new(0.5, 0.5))
			local east = P(Vector3.new(c.Zones.Island.Radius, 0, 0))
			expect(east.X > 0.95 and east.X <= 1).toBe(true)
			expect(east.Y).toBeNear(0.5, 1e-6)
			local north = P(Vector3.new(0, 0, -100))
			expect(north.Y < 0.5).toBe(true)
			local far = P(Vector3.new(5000, 0, 5000))
			expect((far - Vector2.new(0.5, 0.5)).Magnitude).toBeNear(0.5, 1e-4)
			expect(P(Vector3.new(0 / 0, 0, 1))).toEqual(Vector2.new(0.5, 0.5))
			expect(P(Vector3.new(math.huge, 0, 1))).toEqual(Vector2.new(0.5, 0.5))
			expect(P("x")).toEqual(Vector2.new(0.5, 0.5))
			-- les 12 Nids sont dans le disque
			for slot = 1, 12 do
				local p = P(c.WorldLayout.nestCenter(slot))
				expect((p - Vector2.new(0.5, 0.5)).Magnitude < 0.5).toBe(true)
			end
		end)
	end)

	describe("Minimap › affichage et taille", function()
		it("cachée jusqu'au reveal du HUD ; M, appui : 150 ↔ 300", function()
			local c = setup()
			local frame = holder(c)
			expect(frame.Visible).toBe(false)
			c.Minimap.toggle() -- pas encore affichée : sans effet
			expect(frame.Size).toEqual(UDim2.fromOffset(150, 150))
			c.HUD.reveal("minimap", true)
			expect(frame.Visible).toBe(true)
			c.Input.MinimapToggled:Fire()
			c.h:settle(1)
			expect(c.Minimap.isExpanded()).toBe(true)
			expect(frame.Size).toEqual(UDim2.fromOffset(300, 300))
			frame.Disc.Activated:Fire()
			c.h:settle(1)
			expect(frame.Size).toEqual(UDim2.fromOffset(150, 150))
			c.Minimap.setExpanded(true)
			expect(frame.Size).toEqual(UDim2.fromOffset(300, 300))
		end)
	end)

	describe("Minimap › contenu", function()
		it(
			"un point par joueur depuis les miettes, le local depuis son personnage ; Nids colorés",
			function()
				local c = setup()
				c.slot = 3
				c.owners = { [3] = 1, [5] = 77 }
				c.heads = { [5] = Vector3.new(60, 0, 0), [7] = Vector3.new(0, 0, 60) }
				c.lengths = { [5] = 20 }
				c.h.localPlayer.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(-90, 3, 0)
				update(c)
				local st = c.Minimap._state()
				local other = st.playerDots[5]
				local mine = st.playerDots[3]
				expect(other.Visible).toBe(true)
				local p = c.Minimap.project(Vector3.new(60, 0, 0))
				expect(other.Position).toEqual(UDim2.fromScale(p.X, p.Y))
				expect(mine.Visible).toBe(true)
				local q = c.Minimap.project(Vector3.new(-90, 0, 0))
				expect(mine.Position).toEqual(UDim2.fromScale(q.X, q.Y))
				expect(mine:FindFirstChildOfClass("UIStroke").Color).toEqual(roblox.Color3.new(1, 1, 1))
				-- file longue : point plus gros
				expect(other.Size.X.Offset > 7).toBe(true)
				-- slot sans propriétaire (miettes résiduelles) : caché
				expect(st.playerDots[7].Visible).toBe(false)
				expect(st.playerDots[1].Visible).toBe(false)
				expect(st.nestDots[5].BackgroundColor3).toEqual(c.Cosmetics.NestColors[5])
				expect(st.nestDots[6].BackgroundColor3).toEqual(c.Cosmetics.FreeNestColor)
				expect(st.heading.Visible).toBe(true)
				-- revue : un GuiObject tourne autour de son CENTRE ; la pointe doit orbiter autour du
				-- point local, donc le pivot (centre) est sur le point et la pointe dans sa moitié haute
				expect(st.heading.AnchorPoint).toEqual(roblox.Vector2.new(0.5, 0.5))
				expect(st.heading.Position).toEqual(mine.Position)
				local tip = st.heading.Tip
				expect(tip.Position).toEqual(UDim2.new())
				expect(tip.Size.Y.Offset * 2).toBe(st.heading.Size.Y.Offset)
				expect(st.heading.BackgroundTransparency).toBe(1)
				-- personnage absent : le point local suit la tête de ses miettes
				c.h.localPlayer.Character = nil
				c.heads[3] = Vector3.new(10, 0, 10)
				update(c)
				local r = c.Minimap.project(Vector3.new(10, 0, 10))
				expect(mine.Position).toEqual(UDim2.fromScale(r.X, r.Y))
			end
		)

		it(
			"Gloomwisps violets (éclatés masqués), Comète : impact pendant l'alerte, au sol, absente",
			function()
				local c = setup()
				c.wisps = { [1] = Vector3.new(30, 0, 30), [2] = Vector3.new(-30, 0, 30) }
				c.events = {
					t = T0,
					wisps = {
						{ id = 1, seed = 1, t0 = T0 },
						{ id = 2, seed = 2, t0 = T0 },
						{ id = 3, seed = 3, t0 = T0 },
					},
					comet = {
						id = 600,
						phase = "warn",
						x = 40,
						z = -20,
						code = 1,
						warnAt = T0,
						impactAt = T0 + 8,
						burstAt = T0 + 83,
					},
				}
				update(c)
				local st = c.Minimap._state()
				local visible = 0
				for _, entry in st.wispPool do
					if entry.frame.Visible then
						visible += 1
					end
				end
				expect(visible).toBe(2)
				local p = c.Minimap.project(Vector3.new(40, 0, -20))
				expect(st.comet.Visible).toBe(true)
				expect(st.comet.Position).toEqual(UDim2.fromScale(p.X, p.Y))
				c.events.comet.phase = "ground"
				c.comet = Vector3.new(-10, 0, 5)
				c.wisps[2] = nil
				update(c)
				local q = c.Minimap.project(c.comet)
				expect(st.comet.Position).toEqual(UDim2.fromScale(q.X, q.Y))
				visible = 0
				for _, entry in st.wispPool do
					if entry.frame.Visible then
						visible += 1
					end
				end
				expect(visible).toBe(1)
				-- clignotement à 2 Hz
				local seen = {}
				for _ = 1, 8 do
					c.h:step(0.125, 1)
					seen[st.comet.BackgroundTransparency] = true
				end
				expect(seen[0] and seen[0.7]).toBe(true)
				c.events.comet.phase = "banked"
				update(c)
				expect(st.comet.Visible).toBe(false)
				c.events = nil
				update(c)
				expect(st.comet.Visible).toBe(false)
			end
		)

		it("mise à jour à 10 Hz par Heartbeat, sans erreur avec un monde vide", function()
			local c = setup()
			c.slot = 2
			c.owners = { [2] = 1 }
			c.h:step(1 / 60, 12)
			expect(c.Minimap._state().playerDots[2].Visible).toBe(true)
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)
end
