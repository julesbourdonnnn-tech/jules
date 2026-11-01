--!nocheck
-- Socle client (Comet Conga) :
--   * Root : le conteneur Safe couvre tout l'écran APRÈS la mise à l'échelle (UIScale autour du coin
--     haut gauche), à toutes les résolutions (divers r1) ; Raise a Squishy, console d'abord (note
--     INT-TV) : une seule règle télé, max(0,5 ; min(L / 1920 ; H / 1080)), sans plafond
--   * Root.screen sans PlayerGui : erreur claire, jamais d'attente infinie (finition panels-console)
--   * Toast : la pile commence sous la zone des bannières (Toast.TopY), 3 toasts au plus (divers r1)
--   * Juice.press : doigt relevé hors du bouton → le bouton revient à 1 (finition hud-onboarding)
--   * pas de fenêtre de chat sur console, quelle que soit la version du chat (r4 client-0)
-- Adaptations : le bouton de Juice.press est un TextButton simple (Widgets du HUD de Comet Conga
-- absents) ; Toast.TopY est un champ du module (le HUD du jeu le règle) dont la valeur par défaut
-- garde la marge de Comet Conga.
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Vector2 = roblox.Vector2
local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	-- Root / Toast ------------------------------------------------------------------------------

	local function uiSetup()
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Root = h:require(CLIENT .. "UI.Root")
		Root.Init()
		return h, Root
	end

	local function near(a, b)
		return math.abs(a - b) < 1e-6
	end

	local function expectCovers(safe, s)
		expect(safe.AnchorPoint.X).toBe(0)
		expect(safe.AnchorPoint.Y).toBe(0)
		expect(safe.Position.X.Scale).toBe(0)
		expect(safe.Position.Y.Scale).toBe(0)
		-- taille × échelle = tout l'écran (UIScale appliqué autour du coin haut gauche)
		expect(near(safe.Size.X.Scale * s, 1)).toBe(true)
		expect(near(safe.Size.Y.Scale * s, 1)).toBe(true)
		expect(safe.Size.X.Offset).toBe(0)
		expect(safe.Size.Y.Offset).toBe(0)
		expect(near(safe.RootScale.Scale, s)).toBe(true)
	end

	describe("Fix divers r1 › Root : Safe plein écran à toutes les résolutions", function()
		it("1920×1080 : échelle 1, Safe = écran", function()
			local h, Root = uiSetup()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1920, 1080)
			local safe = Root.safe("TestA", 5)
			expect(Root.scale()).toBe(1)
			expectCovers(safe, 1)
			expect(h.localPlayer.PlayerGui.TestA.ResetOnSpawn).toBe(false)
		end)

		it("petite fenêtre 844×390 : échelle plancher 0,5 et Safe agrandi de 1/0,5", function()
			local h, Root = uiSetup()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(844, 390)
			local safe = Root.safe("TestB", 5)
			expect(Root.scale()).toBe(0.5)
			expectCovers(safe, 0.5)
		end)

		it("1280×720 : 0,667 ; 4K : 2, sans plafond ; Safe suit", function()
			local h, Root = uiSetup()
			local safe = Root.safe("TestC", 5)
			expect(near(Root.scale(), 2 / 3)).toBe(true)
			expectCovers(safe, 2 / 3)
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(3840, 2160)
			expect(Root.scale()).toBe(2)
		end)

		it("écran 4:3 : le cadre de référence 1920 de large tient (rapport de largeur)", function()
			local h, Root = uiSetup()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1536, 1152)
			expect(near(Root.scale(), 0.8)).toBe(true)
			expectCovers(Root.safe("TestD", 5), 0.8)
		end)

		it("rotation / redimensionnement : tous les écrans suivent, écrans détruits oubliés", function()
			local h, Root = uiSetup()
			local a = Root.safe("TestE", 5)
			local b = Root.safe("TestF", 6)
			local gone = Root.screen("TestG", 7)
			gone:Destroy()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(844, 390)
			h:settle(1)
			expectCovers(a, 0.5)
			expectCovers(b, 0.5)
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1920, 1080)
			h:settle(1)
			expectCovers(a, 1)
			expectCovers(b, 1)
			-- viewport dégénéré (caméra pas prête) : échelle 1, jamais de division par zéro
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1, 1)
			h:settle(1)
			expectCovers(a, 1)
		end)

		it(
			"un élément ancré à droite (1, −16) reste dans l'écran quelle que soit l'échelle",
			function()
				local h, Root = uiSetup()
				for _, size in { Vector2.new(844, 390), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
					h.workspace.CurrentCamera.ViewportSize = size
					h:settle(1)
					local safe = Root.safe("TestH", 5)
					local s = Root.scale()
					-- position écran du bord droit d'un enfant en (1, −16) : (Safe.X.Scale × W − 16) × s
					local right = (safe.Size.X.Scale * size.X - 16) * s
					expect(right <= size.X).toBe(true)
					expect(right >= size.X - 16 * 1.25 - 1e-6).toBe(true)
				end
			end
		)
	end)

	describe("Fix divers r1 › Toast : sous les bannières", function()
		it("la pile commence sous la zone des bannières (y ≥ 72 + 72 + 34)", function()
			local h = uiSetup()
			local Toast = h:require(CLIENT .. "UI.Toast")
			Toast.show("Quest complete!", "success")
			local stack = h.localPlayer.PlayerGui.Toasts.Safe.Stack
			-- valeur par défaut de Comet Conga : bannière (72 de haut, à y = 72) + barre de 34 + marge
			expect(stack.Position.Y.Scale).toBe(0)
			expect(stack.Position.Y.Offset >= 72 + 72 + 34).toBe(true)
			expect(stack.Position.X.Scale).toBe(0.5)
			expect(stack.AnchorPoint.X).toBe(0.5)
			-- 3 toasts au plus, toujours dans la pile
			for i = 1, 5 do
				Toast.show("t" .. i)
			end
			local n = 0
			for _, child in stack:GetChildren() do
				if child.Name == "Toast" then
					n += 1
				end
			end
			expect(n <= 3).toBe(true)
		end)
	end)

	-- OnboardingPlan (règles pures) -------------------------------------------------------------

	describe("Socle client › Toast.TopY réglable", function()
		it("le HUD du jeu peut placer la pile ; textes jamais sous 28 px TV", function()
			local h = uiSetup()
			local Toast = h:require(CLIENT .. "UI.Toast")
			Toast.TopY = 240
			Toast.show("Saved!", "success")
			local stack = h.localPlayer.PlayerGui.Toasts.Safe.Stack
			expect(stack.Position.Y.Offset).toBe(240)
			local label = stack:FindFirstChild("Toast").Label
			expect(label:FindFirstChildOfClass("UITextSizeConstraint").MinTextSize >= 28).toBe(true)
		end)
	end)

	describe("Socle client › UI/Root.screen sans PlayerGui", function()
		it("erreur claire qui nomme Root et l'écran, aucune attente infinie", function()
			local h = Harness.new({ mode = "client" })
			local Root = h:require(CLIENT .. "UI.Root")
			Root.PlayerGuiWait = 0.05
			h.localPlayer.PlayerGui.Parent = nil
			local ok, err = pcall(Root.screen, "HUD", 10)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "[Root]", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "PlayerGui", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "HUD", 1, true) ~= nil).toBe(true)
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)

		it(
			"PlayerGui présent : écran créé tout de suite (sans attendre) ; un même nom = même écran",
			function()
				local h = Harness.new({ mode = "client" })
				local Root = h:require(CLIENT .. "UI.Root")
				local gui = Root.screen("HUD", 10)
				expect(gui.Parent).toBe(h.localPlayer:FindFirstChildOfClass("PlayerGui"))
				expect(gui.Safe ~= nil).toBe(true)
				expect(gui.ResetOnSpawn).toBe(false)
				expect(Root.screen("HUD", 10)).toBe(gui)
				expect(table.concat(h:warnings(), "\n")).toBe("")
				expect(table.concat(h.errors, "\n")).toBe("")
			end
		)
	end)

	describe("Socle client › Juice.press, doigt relevé hors du bouton", function()
		it(
			"InputEnded du même toucher ramène l'échelle à 1 (pas de MouseButton1Up ni MouseLeave)",
			function()
				local h = uiSetup()
				local Root = h:require(CLIENT .. "UI.Root")
				local Juice = h:require(CLIENT .. "UI.Juice")
				local safe = Root.safe("PressTest", 5)
				local function button(name)
					local b = h.globals.Instance.new("TextButton")
					b.Name = name
					b.Parent = safe
					Juice.press(b)
					return b
				end
				local a, b = button("A"), button("B")
				local function frames(n)
					h:step(1 / 30, n)
					h:settle(1)
				end
				local uis = h.game.UserInputService
				local touch =
					{ UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.Begin }
				local other =
					{ UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.Begin }
				for _, btn in { a, b } do
					btn.InputBegan:Fire(if btn == a then touch else other)
					btn.MouseButton1Down:Fire(10, 10)
				end
				frames(10)
				expect(math.abs(a.JuiceScale.Scale - 0.9) < 1e-3).toBe(true)
				expect(math.abs(b.JuiceScale.Scale - 0.9) < 1e-3).toBe(true)
				-- le premier doigt se relève ailleurs : seul son bouton revient
				uis.InputEnded:Fire(touch, false)
				frames(15)
				expect(math.abs(a.JuiceScale.Scale - 1) < 1e-3).toBe(true)
				expect(math.abs(b.JuiceScale.Scale - 0.9) < 1e-3).toBe(true)
				uis.InputEnded:Fire(other, false)
				frames(15)
				expect(math.abs(b.JuiceScale.Scale - 1) < 1e-3).toBe(true)
				-- souris relâchée hors du bouton : même retour
				local mouse = {
					UserInputType = Enum.UserInputType.MouseButton1,
					UserInputState = Enum.UserInputState.Begin,
				}
				a.InputBegan:Fire(mouse)
				a.MouseButton1Down:Fire(10, 10)
				frames(10)
				expect(math.abs(a.JuiceScale.Scale - 0.9) < 1e-3).toBe(true)
				uis.InputEnded:Fire({
					UserInputType = Enum.UserInputType.MouseButton1,
					UserInputState = Enum.UserInputState.End,
				}, false)
				frames(15)
				expect(math.abs(a.JuiceScale.Scale - 1) < 1e-3).toBe(true)
				expect(#h:signalErrors()).toBe(0)
			end
		)
	end)

	-- Chat coupé sur console quelle que soit la version du chat
	local function chatClient(opts)
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
				local h, calls = chatClient({ console = true })
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
				local h, calls = chatClient({ console = true })
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
				local h, calls = chatClient({ console = true, failures = 2 })
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
				local h, calls = chatClient({ touch = touch })
				h:require(CLIENT .. "Util.Platform").Start()
				h:settle(2)
				expect(calls).toEqual({})
			end
		end)
	end)
end
