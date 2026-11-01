--!nocheck
-- Correctifs r4 « client-0 » (accueil, plateforme) :
--   * OnboardingController : sur les petits téléphones (640 × 360, 667 × 375), l'instruction d'accueil
--     ne recouvre plus le bouton Ping (ni le Dash) affiché à partir de Q3 : elle se décale à gauche
--     du coin des actions, sans toucher le rail ; ailleurs elle reste centrée (GDD §10.1 : un bouton
--     d'action n'est jamais recouvert)
--   * Platform.applyChatRule : sur console, la fenêtre de chat du CoreGui est aussi coupée par
--     StarterGui:SetCoreGuiEnabled(Chat, false) (ancien chat comme TextChatService, configurations
--     absentes), avec nouveaux essais si le CoreGui n'est pas encore prêt
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	-- =============================================================================================
	-- Instruction d'accueil hors du coin des actions
	-- =============================================================================================

	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	local function obSetup()
		local h = Harness.new({ mode = "client", touch = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		h.game.GuiService.ReducedMotionEnabled = true
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Toast = h:require(CLIENT .. "UI.Toast"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
			Minimap = h:require(CLIENT .. "UI.Minimap"),
			Onboarding = h:require(CLIENT .. "Controllers.OnboardingController"),
		}
		-- isolation : paquets client-world et client-panels remplacés
		c.VFX.playDash = function() end
		c.WSC.localSlot = function()
			return 1
		end
		c.WSC.lineLength = function()
			return 0
		end
		c.WSC.wilds = function()
			return {}
		end
		c.Panels.current = function()
			return nil
		end
		c.h.localPlayer.Character.HumanoidRootPart.CFrame =
			CFrame.new(c.WorldLayout.gateCFrame(1).Position + Vector3.new(0, 3, 0))
		local order = { "Root", "State", "Prefs", "FX", "Input", "HUD", "Minimap", "Onboarding" }
		for _, name in order do
			if c[name].Init then
				c[name].Init()
			end
		end
		for _, name in order do
			if c[name].Start and name ~= "Root" and name ~= "State" then
				c[name].Start()
			end
		end
		return c
	end

	local function obLoad(c, over)
		local p = Schema.defaults()
		for k, v in over or {} do
			p[k] = v
		end
		c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", p)
		c.h:settle(1)
	end

	local function obRun(c, n)
		for _ = 1, n or 3 do
			c.h:step(1 / 30, 1)
			c.h:settle(1)
		end
	end

	local function hudSafe(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	-- écran simulé (comme Fix_client-hud_r2) : AbsoluteSize = zone sous la barre Roblox, bouton de
	-- saut tactile de Roblox (70 px à (1, −95, 1, −90) sur petit écran)
	local function screen(c, width, height, topbar)
		c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(width, height)
		local playerGui = c.h.localPlayer.PlayerGui
		for _, name in { "HUD", "Onboarding" } do
			local gui = playerGui:FindFirstChild(name)
			if gui then
				gui.AbsoluteSize = Vector2.new(width, height - topbar)
				gui.Safe.AbsoluteSize = gui.AbsoluteSize
			end
		end
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
		local small = math.min(width, height) < 500
		local size = if small then 70 else 120
		local offset = if small then Vector2.new(-95, -90) else Vector2.new(-170, -210)
		jump.AbsoluteSize = Vector2.new(size, size)
		jump.AbsolutePosition = Vector2.new(width, height - topbar) + offset
		c.HUD._layoutActions()
		c.h:settle(1)
	end

	-- zone intérieure du HUD en px de référence (Safe ÷ échelle − marges 12/8 de Root.safe)
	local function content(c)
		local gui = c.h.localPlayer.PlayerGui.HUD
		local k = c.Root.scale()
		return gui.AbsoluteSize.X / k - 24, gui.AbsoluteSize.Y / k - 16
	end

	-- rectangle (px de référence de la zone intérieure) d'un objet placé dans Safe
	local function placed(c, obj)
		local W, H = content(c)
		local w = obj.Size.X.Scale * W + obj.Size.X.Offset
		local hh = obj.Size.Y.Scale * H + obj.Size.Y.Offset
		local x = obj.Position.X.Scale * W + obj.Position.X.Offset - obj.AnchorPoint.X * w
		local y = obj.Position.Y.Scale * H + obj.Position.Y.Offset - obj.AnchorPoint.Y * hh
		return { x0 = x, y0 = y, x1 = x + w, y1 = y + hh }
	end

	local function hint(c)
		return c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint
	end

	local function overlaps(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
	end

	-- rectangles des boutons du rail affichés (grille 2 × 2 des écrans bas : cellules de 80, écart 8)
	local function railRight(c)
		local rail = hudSafe(c).Rail
		return placed(c, rail).x1
	end

	describe(
		"Fix r4 client-0 › instruction d'accueil hors du coin Dash / Ping (petits téléphones)",
		function()
			it("640 × 360 et 667 × 375 : Ping et Dash jamais recouverts dès Q3, rail libre", function()
				local c = obSetup()
				obLoad(c, { onboarding = { step = 3, p = 0 } })
				obRun(c, 3)
				expect(c.Onboarding.currentHint() ~= nil).toBe(true)
				expect(c.HUD.isRevealed("ping")).toBe(true)
				for _, size in { { 640, 360, 36 }, { 667, 375, 36 }, { 640, 360, 58 }, { 568, 320, 36 } } do
					screen(c, size[1], size[2], size[3])
					obRun(c, 4)
					local label = size[1] .. "x" .. size[2] .. "/" .. size[3]
					local W = content(c)
					local h = placed(c, hint(c))
					local ping = placed(c, hudSafe(c).Ping)
					local dash = placed(c, hudSafe(c).Dash)
					expect({ screen = label, visible = hint(c).Visible }).toEqual({
						screen = label,
						visible = true,
					})
					expect({ screen = label, ping = overlaps(h, ping), dash = overlaps(h, dash) }).toEqual({
						screen = label,
						ping = false,
						dash = false,
					})
					-- écart d'au moins 8 px de référence avec le bouton Ping
					expect({ screen = label, gap = h.x1 + 8 <= ping.x0 + 1e-6 or h.y1 + 8 <= ping.y0 }).toEqual({
						screen = label,
						gap = true,
					})
					-- dans l'écran, à droite du rail (grille 2 × 2), même hauteur que la règle du HUD
					expect({ screen = label, inside = h.x0 >= 0 and h.x1 <= W }).toEqual({
						screen = label,
						inside = true,
					})
					expect({
						screen = label,
						rail = h.x0 >= railRight(c) or h.y0 >= placed(c, hudSafe(c).Rail).y1,
					}).toEqual({
						screen = label,
						rail = true,
					})
					-- même hauteur que la règle du HUD (arrondie au pixel)
					expect({ screen = label, top = math.abs(h.y0 - c.HUD.hintTop()) <= 0.5 }).toEqual({
						screen = label,
						top = true,
					})
					expect(hint(c).AnchorPoint).toEqual(Vector2.new(0.5, 0))
				end
				-- valeurs attendues (ticket) : centre 454 en 640 × 360, 499 en 667 × 375 (barre de 36 px)
				screen(c, 640, 360, 36)
				obRun(c, 4)
				local r = placed(c, hint(c))
				expect(math.abs((r.x0 + r.x1) / 2 - 454) <= 1).toBe(true)
				screen(c, 667, 375, 36)
				obRun(c, 4)
				r = placed(c, hint(c))
				expect(math.abs((r.x0 + r.x1) / 2 - 499) <= 1).toBe(true)
				expect(#c.h:signalErrors()).toBe(0)
			end)

			it("écran assez large (844 × 390, 1280 × 720) : instruction centrée, comme avant", function()
				local c = obSetup()
				obLoad(c, { onboarding = { step = 3, p = 0 } })
				obRun(c, 3)
				for _, size in { { 844, 390, 36 }, { 800, 360, 36 }, { 1280, 720, 36 } } do
					screen(c, size[1], size[2], size[3])
					obRun(c, 4)
					local label = size[1] .. "x" .. size[2]
					local position = hint(c).Position
					expect({ screen = label, x = position.X }).toEqual({
						screen = label,
						x = roblox.UDim.new(0.5, 0),
					})
					local h = placed(c, hint(c))
					expect({ screen = label, ping = overlaps(h, placed(c, hudSafe(c).Ping)) }).toEqual({
						screen = label,
						ping = false,
					})
				end
			end)

			it(
				"barre Roblox de 58 px (568 × 320, 640 × 360), Q6 avec les 4 boutons du rail : rien de recouvert",
				function()
					local c = obSetup()
					-- boutique avec un article : l'icône Boutique (case bas droite de la grille) est là
					c.h:require("ReplicatedStorage.Shared.Config.Monetization").Passes.DoubleGlow.id = 1
					obLoad(c, { onboarding = { step = 6, p = 0 }, stats = { parades = 12, sessions = 0 } })
					obRun(c, 12)
					expect(c.Onboarding.currentHint() ~= nil).toBe(true)
					expect(c.HUD.isRevealed("rail.Shop")).toBe(true)
					for _, size in { { 568, 320, 58 }, { 640, 360, 58 }, { 568, 320, 36 }, { 667, 375, 58 } } do
						screen(c, size[1], size[2], size[3])
						obRun(c, 4)
						local label = size[1] .. "x" .. size[2] .. "/" .. size[3]
						local W, H = content(c)
						local h = placed(c, hint(c))
						expect({ screen = label, visible = hint(c).Visible }).toEqual({
							screen = label,
							visible = true,
						})
						-- cases AFFICHÉES de la grille du rail (80 × 80, écart 8, ruban de 6 px de chaque côté)
						local rail = hudSafe(c).Rail
						local grid = rail:FindFirstChildOfClass("UIGridLayout")
						local perRow = grid.FillDirectionMaxCells
						local i = 0
						for _, name in { "Upgrades", "Collection", "Goals", "Shop" } do
							if rail[name].Visible then
								local col, row = i % perRow, i // perRow
								local x = rail.Position.X.Offset + col * 88
								local y = rail.Position.Y.Offset + row * 88
								local cell = { x0 = x - 6, y0 = y, x1 = x + 86, y1 = y + 80 }
								expect({ screen = label, button = name, hit = overlaps(h, cell) }).toEqual({
									screen = label,
									button = name,
									hit = false,
								})
								i += 1
							end
						end
						expect(i).toBe(4)
						for _, name in { "Ping", "Dash", "QuestTracker", "Status", "EventPill" } do
							expect({
								screen = label,
								button = name,
								hit = overlaps(h, placed(c, hudSafe(c)[name])),
							}).toEqual({
								screen = label,
								button = name,
								hit = false,
							})
						end
						-- dans l'écran, sous la pastille d'événement (16 + 48 + 8), au-dessus du compteur de file
						expect({ screen = label, inside = h.x0 >= 0 and h.x1 <= W and h.y0 >= 72 }).toEqual({
							screen = label,
							inside = true,
						})
						local line = placed(c, hudSafe(c).LineCounter)
						expect({ screen = label, line = overlaps(h, line) }).toEqual({
							screen = label,
							line = false,
						})
					end
					-- 640 × 360 : toujours sous la pile de toasts (règle du HUD), décalée à gauche du Ping
					screen(c, 640, 360, 58)
					obRun(c, 4)
					expect(math.abs(placed(c, hint(c)).y0 - c.HUD.hintTop()) <= 0.5).toBe(true)
					expect(hint(c).Position.X.Scale).toBe(0)
					-- 568 × 320 sous 58 px : pas de place entre le rail et le Ping → centrée, remontée
					screen(c, 568, 320, 58)
					obRun(c, 4)
					expect(hint(c).Position.X).toEqual(roblox.UDim.new(0.5, 0))
					expect(placed(c, hint(c)).y0 < c.HUD.hintTop()).toBe(true)
					expect(#c.h:signalErrors()).toBe(0)
				end
			)

			it("Q1 (Ping pas encore affiché) en 667 × 375 : instruction centrée, Dash libre", function()
				local c = obSetup()
				obLoad(c, { onboarding = { step = 1, p = 0 } })
				obRun(c, 3)
				expect(c.HUD.isRevealed("ping")).toBe(false)
				screen(c, 667, 375, 36)
				obRun(c, 4)
				expect(hint(c).Position.X).toEqual(roblox.UDim.new(0.5, 0))
				expect(overlaps(placed(c, hint(c)), placed(c, hudSafe(c).Dash))).toBe(false)
				-- le Ping apparaît (Q3) : l'instruction se décale
				obLoad(c, { onboarding = { step = 3, p = 0 } })
				obRun(c, 4)
				expect(c.HUD.isRevealed("ping")).toBe(true)
				expect(overlaps(placed(c, hint(c)), placed(c, hudSafe(c).Ping))).toBe(false)
				expect(hint(c).Position.X.Scale).toBe(0)
			end)
		end
	)

	-- =============================================================================================
	-- Chat coupé sur console quelle que soit la version du chat
	-- =============================================================================================

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = opts.console, touch = opts.touch })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local calls = {}
		local failures = opts.failures or 0
		MockInstance.classMethods.StarterGui.SetCoreGuiEnabled = function(_, kind, enabled)
			if failures > 0 then
				failures -= 1
				error("SetCoreGuiEnabled: CoreGui pas prêt (simulé)")
			end
			table.insert(calls, { kind = kind, enabled = enabled })
		end
		return h, calls
	end

	describe("Fix r4 client-0 › pas de fenêtre de chat sur console (CoreGui)", function()
		it(
			"console : SetCoreGuiEnabled(Chat, false), configurations TextChatService coupées aussi",
			function()
				local h, calls = client({ console = true })
				h:require(CLIENT .. "Util.Platform").Start()
				h:settle(2)
				expect(calls).toEqual({ { kind = Enum.CoreGuiType.Chat, enabled = false } })
				expect(h.game.TextChatService.ChatWindowConfiguration.Enabled).toBe(false)
				expect(h.game.TextChatService.BubbleChatConfiguration.Enabled).toBe(true)
				expect(#h:warnings()).toBe(0)
			end
		)

		it(
			"ancien chat (aucune configuration TextChatService) : la fenêtre est quand même coupée",
			function()
				local h, calls = client({ console = true })
				local Console = h:require("ReplicatedStorage.Shared.Config.Console")
				Console.ChatWaitTimeout = 0.2
				local tcs = h.game.TextChatService
				tcs.ChatVersion = Enum.ChatVersion.LegacyChatService
				for _, child in tcs:GetChildren() do
					child:Destroy()
				end
				h:require(CLIENT .. "Util.Platform").Start()
				h:settle(2)
				expect(calls).toEqual({ { kind = Enum.CoreGuiType.Chat, enabled = false } })
				expect(#h:warnings()).toBe(0)
				expect(#h.errors).toBe(0)
			end
		)

		it(
			"CoreGui pas encore prêt (2 échecs) : nouvel essai jusqu'à réussir, sans avertissement",
			function()
				local h, calls = client({ console = true, failures = 2 })
				h:require(CLIENT .. "Util.Platform").Start()
				h:settle(2)
				expect(#calls).toBe(0)
				local task = require("@lune/task")
				task.wait(1.2)
				h:settle(2)
				expect(calls).toEqual({ { kind = Enum.CoreGuiType.Chat, enabled = false } })
				expect(#h:warnings()).toBe(0)
			end
		)

		it("PC et téléphone : le chat du CoreGui n'est pas touché", function()
			for _, touch in { false, true } do
				local h, calls = client({ touch = touch })
				h:require(CLIENT .. "Util.Platform").Start()
				h:settle(2)
				expect(calls).toEqual({})
			end
		end)
	end)
end
