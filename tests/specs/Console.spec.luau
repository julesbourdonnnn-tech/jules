--!nocheck
-- Socle console PS5 (docs/07-console-ps5.md) : Util/Platform (console, écran, entrée préférée,
-- glyphes, échelle, zone sûre), UI/Glyph, Util/Haptics, UI/Root sur téléviseur, règle « pas de
-- fenêtre de chat sur console », et le harnais console (Harness.new({ console = true }),
-- tests/harness/Gamepad, tests/harness/Layout). Démarrage complet du client en console manette seule,
-- API Roblox auditée (tests/harness/ApiAudit).
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({
			mode = "client",
			console = opts.console,
			touch = opts.touch,
			viewport = opts.viewport,
		})
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		return h, Clock
	end

	local function platform(h)
		return h:require(CLIENT .. "Util.Platform")
	end

	describe("Console › Platform", function()
		it("PC : pas de console, écran Medium, clavier-souris", function()
			local h = client()
			local P = platform(h)
			P.Init()
			expect(P.isTenFoot()).toBe(false)
			expect(P.displaySize()).toBe(Enum.DisplaySize.Medium)
			expect(P.isLargeDisplay()).toBe(false)
			expect(P.inputKind()).toBe(P.KEYBOARD)
			expect(P.chatWindowAllowed()).toBe(true)
		end)

		it("téléphone : écran Small, tactile", function()
			local h = client({ touch = true })
			local P = platform(h)
			P.Init()
			expect(P.displaySize()).toBe(Enum.DisplaySize.Small)
			expect(P.inputKind()).toBe(P.TOUCH)
		end)

		it("console : 10 pieds, écran Large, manette", function()
			local h = client({ console = true })
			local P = platform(h)
			P.Init()
			expect(P.isTenFoot()).toBe(true)
			expect(P.isLargeDisplay()).toBe(true)
			expect(P.inputKind()).toBe(P.GAMEPAD)
			expect(P.usingGamepad()).toBe(true)
			expect(P.gamepadConnected()).toBe(true)
			expect(P.chatWindowAllowed()).toBe(false)
		end)

		it("IsTenFootInterface qui échoue (moteur ancien) : pas de console, sans erreur", function()
			local h = client()
			MockInstance.classMethods.GuiService.IsTenFootInterface = function()
				error("not a valid member")
			end
			local P = platform(h)
			expect(P.isTenFoot()).toBe(false)
			expect(P.chatWindowAllowed()).toBe(true)
			expect(#h.errors).toBe(0)
		end)

		it(
			"l'entrée préférée suit le dernier changement (LastInputTypeChanged ou PreferredInput)",
			function()
				local h = client()
				local P = platform(h)
				P.Init()
				local reasons = {}
				P.Changed:Connect(function(reason)
					table.insert(reasons, reason)
				end)
				local uis = h.game.UserInputService
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
				h:settle(1)
				expect(P.inputKind()).toBe(P.GAMEPAD)
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Focus) -- sans effet
				h:settle(1)
				expect(P.inputKind()).toBe(P.GAMEPAD)
				uis.PreferredInput = Enum.PreferredInput.Touch
				h:settle(1)
				expect(P.inputKind()).toBe(P.TOUCH)
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
				h:settle(1)
				expect(P.inputKind()).toBe(P.KEYBOARD)
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.MouseMovement) -- même type : pas de signal
				h:settle(1)
				expect(reasons).toEqual({ "input", "input", "input" })
				uis.GamepadConnected:Fire(Enum.UserInputType.Gamepad2)
				h.game.GuiService.ViewportDisplaySize = Enum.DisplaySize.Large
				h:settle(1)
				expect(reasons[4]).toBe("gamepad")
				expect(reasons[5]).toBe("display")
				expect(P.isLargeDisplay()).toBe(true)
			end
		)

		it("glyphes : PlayStation sur console, jamais de lettre Xbox en repli", function()
			local h = client({ console = true })
			local P = platform(h)
			local square = P.glyph(Enum.KeyCode.ButtonX)
			expect(square.gamepad).toBe(true)
			expect(square.image).toBe(Gamepad.PS_GLYPHS .. "ButtonSquare@2x.png")
			expect(P.glyph(Enum.KeyCode.ButtonA).image).toBe(Gamepad.PS_GLYPHS .. "ButtonCross@2x.png")
			-- repli (icône indisponible) : losange pour les boutons de façade, texte neutre sinon
			MockInstance.classMethods.UserInputService.GetImageForKeyCode = function()
				return ""
			end
			local fallback = {}
			for _, name in { "ButtonA", "ButtonB", "ButtonX", "ButtonY" } do
				local g = P.glyph(Enum.KeyCode[name])
				expect(g.image).toBeNil()
				expect(g.text).toBe("")
				fallback[name] = g.slot
			end
			expect(fallback).toEqual({
				ButtonA = "bottom",
				ButtonB = "right",
				ButtonX = "left",
				ButtonY = "top",
			})
			expect(P.glyph(Enum.KeyCode.ButtonL1).text).toBe("L1")
			expect(P.glyph(Enum.KeyCode.ButtonR2).text).toBe("R2")
			expect(P.glyph(Enum.KeyCode.DPadUp).text).toBe("↑")
			-- l'appel qui échoue donne aussi le repli
			MockInstance.classMethods.UserInputService.GetImageForKeyCode = function()
				error("boom")
			end
			expect(P.glyph(Enum.KeyCode.ButtonY).slot).toBe("top")
			expect(#h.errors).toBe(0)
		end)

		it("glyphes du clavier : disposition du joueur, noms courts des touches spéciales", function()
			local h = client()
			local P = platform(h)
			expect(P.glyph(Enum.KeyCode.Q).text).toBe("Q")
			expect(P.glyph(Enum.KeyCode.One).text).toBe("1")
			expect(P.glyph(Enum.KeyCode.LeftShift).text).toBe("Shift")
			expect(P.glyph(Enum.KeyCode.Escape).text).toBe("Esc")
			expect(P.glyph(Enum.KeyCode.Q).gamepad).toBe(false)
			-- AZERTY : la touche physique Q s'écrit « A »
			MockInstance.classMethods.UserInputService.GetStringForKeyCode = function(_, kc)
				return if kc == Enum.KeyCode.Q then "a" else kc.Name
			end
			expect(P.glyph(Enum.KeyCode.Q).text).toBe("A")
		end)

		it("échelle : ordinaire bornée à 1,25, téléviseur proportionnelle (1,5 en 1080p)", function()
			local h = client()
			local P = platform(h)
			expect(P.uiScale(Vector2.new(1280, 720), false)).toBe(1)
			expect(P.uiScale(Vector2.new(1920, 1080), false)).toBe(1.25)
			expect(P.uiScale(Vector2.new(844, 390), false)).toBe(0.6)
			expect(P.uiScale(Vector2.new(1920, 1080), true)).toBe(1.5)
			expect(P.uiScale(Vector2.new(3840, 2160), true)).toBe(3)
			expect(P.uiScale(Vector2.new(1280, 720), true)).toBe(1)
			expect(P.uiScale(Vector2.new(2560, 1080), true)).toBe(1.5)
			expect(P.uiScale(Vector2.new(0, 0), true)).toBe(1)
			-- sans argument : caméra et écran courants (PC 1280 × 720)
			expect(P.uiScale()).toBe(1)
		end)

		it("zone sûre : marges ordinaires, 5 % de l'écran sur téléviseur", function()
			local h = client()
			local P = platform(h)
			expect(P.safePadding(Vector2.new(1920, 1080), false)).toBe(Vector2.new(12, 8))
			expect(P.safePadding(Vector2.new(1920, 1080), true)).toBe(Vector2.new(64, 36))
			expect(P.safePadding(Vector2.new(1280, 720), true)).toBe(Vector2.new(64, 36))
			expect(P.safePadding(Vector2.new(3840, 2160), true)).toBe(Vector2.new(64, 36))
		end)
	end)

	describe("Console › Root sur téléviseur", function()
		it("console 1920 × 1080 : UIScale 1,5 et zone sûre TV (64 × 36 px de référence)", function()
			local h = client({ console = true })
			local Root = h:require(CLIENT .. "UI.Root")
			Root.Init()
			local safe = Root.safe("Test", 1)
			expect(safe.RootScale.Scale).toBe(1.5)
			local pad = safe:FindFirstChildOfClass("UIPadding")
			expect(pad.PaddingLeft.Offset).toBe(64)
			expect(pad.PaddingRight.Offset).toBe(64)
			expect(pad.PaddingTop.Offset).toBe(36)
			expect(pad.PaddingBottom.Offset).toBe(36)
			expect(Root.padding()).toBe(Vector2.new(64, 36))
			-- un bouton collé au coin haut gauche de Safe reste dans la zone sûre TV
			local button = h.globals.Instance.new("TextButton")
			button.Size = UDim2.fromOffset(80, 80)
			button.Text = ""
			button.Parent = safe
			Layout.apply(h)
			local r = Layout.rect(button)
			expect(r.x).toBe(96) -- 5 % de 1920
			expect(r.y >= 54).toBe(true) -- 5 % de 1080 (sous la barre Roblox)
			expect(r.w).toBe(120) -- 80 × 1,5
			expect(#Gamepad.audit(h)).toBe(0)
		end)

		it("cadre de sélection commun : trait blanc de 6 px bordé de sombre, une seule instance", function()
			local h = client({ console = true })
			local Root = h:require(CLIENT .. "UI.Root")
			ApiAudit.start()
			local image = Root.selectionImage()
			local button = h.globals.Instance.new("TextButton")
			button.SelectionImageObject = image
			local issues = ApiAudit.stop()
			expect(table.concat(issues, "\n")).toBe("")
			expect(Root.selectionImage()).toBe(image)
			expect(image.Parent).toBeNil()
			-- r4 : le curseur a sa propre couleur (blanc, jamais l'or des états « choisi / marqué » de
			-- Widgets.highlight) et un liseré sombre extérieur (cartes claires) ; voir Fix_r4_ui_1_root
			local stroke = image:FindFirstChildOfClass("UIStroke")
			expect(stroke.Thickness).toBe(6)
			expect(stroke.Color).toBe(roblox.Color3.fromRGB(255, 255, 255))
			expect(image.Edge:FindFirstChildOfClass("UIStroke").Thickness).toBe(2)
			expect(image.Size).toBe(UDim2.new(1, 8, 1, 8))
		end)

		it("PC : échelle et marges inchangées ; écran devenu Large : recalculées", function()
			local h = client()
			local Root = h:require(CLIENT .. "UI.Root")
			local P = platform(h)
			P.Init()
			Root.Init()
			local safe = Root.safe("Test", 1)
			expect(safe.RootScale.Scale).toBe(1)
			expect(safe:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset).toBe(12)
			h.game.Workspace.CurrentCamera.ViewportSize = Vector2.new(1920, 1080)
			h:settle(1)
			expect(safe.RootScale.Scale).toBe(1.25)
			h.game.GuiService.ViewportDisplaySize = Enum.DisplaySize.Large
			h:settle(2)
			expect(safe.RootScale.Scale).toBe(1.5)
			expect(safe:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset).toBe(64)
		end)
	end)

	describe("Console › règle du chat", function()
		local function configs(h)
			local tcs = h.game.TextChatService
			return tcs.ChatWindowConfiguration, tcs.ChatInputBarConfiguration, tcs.BubbleChatConfiguration
		end

		it("console : fenêtre et barre de saisie désactivées, bulles gardées", function()
			local h = client({ console = true })
			local P = platform(h)
			P.Start()
			h:settle(2)
			local window, bar, bubbles = configs(h)
			expect(window.Enabled).toBe(false)
			expect(bar.Enabled).toBe(false)
			expect(bubbles.Enabled).toBe(true)
		end)

		it("PC et téléphone : rien n'est changé", function()
			for _, touch in { false, true } do
				local h = client({ touch = touch })
				platform(h).Start()
				h:settle(2)
				local window, bar = configs(h)
				expect(window.Enabled).toBe(true)
				expect(bar.Enabled).toBe(true)
			end
		end)

		it(
			"configuration créée en retard par le moteur, ou absente : attente bornée, sans avertissement",
			function()
				local h = client({ console = true })
				local Console = h:require("ReplicatedStorage.Shared.Config.Console")
				Console.ChatWaitTimeout = 0.2
				local window, bar = configs(h)
				window.Parent = nil
				bar:Destroy()
				platform(h).Start()
				h:settle(2)
				window.Parent = h.game.TextChatService
				local task = require("@lune/task")
				task.wait(0.3)
				h:settle(2)
				expect(window.Enabled).toBe(false)
				expect(#h:warnings()).toBe(0)
				expect(#h.errors).toBe(0)
			end
		)
	end)

	describe("Console › UI/Glyph", function()
		it(
			"suit le périphérique : PlayStation à la manette, touche au clavier, masqué au tactile",
			function()
				local h = client()
				local P = platform(h)
				P.Init()
				local Glyph = h:require(CLIENT .. "UI.Glyph")
				local parent = h.globals.Instance.new("Frame")
				local g = Glyph.new(parent, { keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonR2 })
				expect(g.frame.Visible).toBe(true)
				expect(g.frame:GetAttribute("GlyphMode")).toBe("text")
				expect(g.frame.Text.Text).toBe("E")
				expect(g.frame.Size).toBe(UDim2.fromOffset(36, 36))
				-- touche longue : pastille élargie, texte lisible
				local shift = Glyph.new(parent, { keyboard = Enum.KeyCode.LeftShift })
				expect(shift.frame.Text.Text).toBe("Shift")
				expect(shift.frame.Size).toBe(UDim2.fromOffset(90, 36))
				shift:destroy()
				local uis = h.game.UserInputService
				h.console = true -- icônes PlayStation (PlayStation branchée)
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
				h:settle(2)
				expect(g.frame:GetAttribute("GlyphKey")).toBe("ButtonR2")
				expect(g.frame:GetAttribute("GlyphMode")).toBe("image")
				expect(g.frame.Image.Image).toBe(Gamepad.PS_GLYPHS .. "ButtonR2@2x.png")
				expect(g.frame.Image.Visible).toBe(true)
				expect(g.frame.Text.Visible).toBe(false)
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
				h:settle(2)
				expect(g.frame.Visible).toBe(false)
				expect(g:shown()).toBe(false)
				expect(g.frame:GetAttribute("GlyphMode")).toBe("hidden")
				-- liaison sans touche clavier : masquée au clavier
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
				h:settle(2)
				g:set({ gamepad = Enum.KeyCode.ButtonB })
				expect(g.frame.Visible).toBe(false)
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
				h:settle(2)
				expect(g.frame:GetAttribute("GlyphKey")).toBe("ButtonB")
				-- repli losange quand l'icône manque
				MockInstance.classMethods.UserInputService.GetImageForKeyCode = function()
					return ""
				end
				g:refresh()
				expect(g.frame:GetAttribute("GlyphMode")).toBe("diamond")
				expect(g.frame.Diamond.right.BackgroundTransparency).toBe(0)
				expect(g.frame.Diamond.left.BackgroundTransparency).toBe(0.7)
				g:destroy()
				expect(g.frame.Parent).toBeNil()
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
				h:settle(2)
				expect(#h.errors).toBe(0)
			end
		)

		it("cadre détruit par son parent : retiré des mises à jour, sans erreur", function()
			local h = client({ console = true })
			platform(h).Init()
			local Glyph = h:require(CLIENT .. "UI.Glyph")
			local parent = h.globals.Instance.new("Frame")
			local g = Glyph.new(parent, { gamepad = Enum.KeyCode.ButtonY })
			expect(g.frame:GetAttribute("GlyphKey")).toBe("ButtonY")
			parent:Destroy()
			h.game.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
			h:settle(2)
			expect(g:shown()).toBe(false)
			expect(#h.errors).toBe(0)
		end)
	end)

	describe("Console › Util/Haptics", function()
		local function setup(opts)
			local h, Clock = client(opts)
			platform(h).Init()
			local Prefs = h:require(CLIENT .. "Util.Prefs")
			local Haptics = h:require(CLIENT .. "Util.Haptics")
			return h, Clock, Prefs, Haptics
		end

		it("manette : HapticEffect du type de l'événement, une instance réutilisée par type", function()
			local h, Clock, _, Haptics = setup({ console = true })
			expect(Haptics.play("snipped")).toBe(true)
			expect(#h.log.haptics).toBe(1)
			expect(h.log.haptics[1].kind).toBe("effect")
			expect(h.log.haptics[1].type).toBe(Enum.HapticEffectType.GameplayCollision)
			Clock.advance(1)
			expect(Haptics.play("snipped")).toBe(true)
			local count = 0
			for _, d in h.workspace:GetChildren() do
				if d.ClassName == "HapticEffect" then
					count += 1
				end
			end
			expect(count).toBe(1)
			expect(Haptics.play("inconnu")).toBe(false)
		end)

		it(
			"modération : délai minimal, sauf priorité supérieure ; atténuation sous le seuil ignorée",
			function()
				local h, Clock, _, Haptics = setup({ console = true })
				expect(Haptics.play("parade")).toBe(true)
				expect(Haptics.play("refuse")).toBe(false) -- moins prioritaire, trop tôt
				expect(Haptics.play("parade")).toBe(false) -- même priorité, trop tôt
				expect(Haptics.play("supernova")).toBe(true) -- plus prioritaire
				Clock.advance(0.3)
				expect(Haptics.play("refuse")).toBe(true)
				Clock.advance(1)
				expect(Haptics.play("cometImpact", 0.2)).toBe(false)
				expect(Haptics.play("cometImpact", 0.9)).toBe(true)
				expect(#h.log.haptics).toBe(4)
			end
		)

		it("repli SetMotor si HapticEffect est indisponible, coupé après la durée", function()
			local h, _, _, Haptics = setup({ console = true })
			local realNew = h.globals.Instance.new
			h.globals.Instance.new = function(className, parent)
				if className == "HapticEffect" then
					error('Unable to create an Instance of type "HapticEffect"')
				end
				return realNew(className, parent)
			end
			expect(Haptics.play("cometGrab", 0.5)).toBe(true)
			local first = h.log.haptics[1]
			expect(first.kind).toBe("motor")
			expect(first.motor).toBe(Enum.VibrationMotor.Large)
			expect(first.value).toBe(0.25)
			local task = require("@lune/task")
			task.wait(0.2)
			h:settle(2)
			expect(h.log.haptics[2].value).toBe(0)
		end)

		it("clavier-souris : jamais ; téléphone : seulement les événements « mobile »", function()
			local h, _, _, Haptics = setup()
			expect(Haptics.play("supernova")).toBe(false)
			local h2, _, _, Haptics2 = setup({ touch = true })
			expect(Haptics2.play("snipped")).toBe(false)
			-- téléphone sans vibration (harnais) : catchEpic demandé mais non pris en charge
			expect(Haptics2.play("catchEpic")).toBe(false)
			expect(#h.log.haptics + #h2.log.haptics).toBe(0)
		end)

		it("réglage « vibration » du profil (Config/Settings) suivi en direct", function()
			local h, Clock, Prefs, Haptics = setup({ console = true })
			local State = h:require(CLIENT .. "Controllers.StateController")
			State.Init()
			Prefs.Init()
			Prefs.Start()
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { settings = { vibration = false } })
			h:settle(2)
			expect(Haptics.play("supernova")).toBe(false)
			h:fireClient("ReplicatedStorage.Remotes.DataPatch", { settings = { vibration = true } }, {})
			h:settle(2)
			Clock.advance(1)
			expect(Haptics.play("supernova")).toBe(true)
		end)

		it("réglage « vibration » à false : aucune vibration", function()
			local h, _, Prefs, Haptics = setup({ console = true })
			Prefs.get = function(key)
				if key == "vibration" then
					return false
				end
				return nil
			end
			expect(Haptics.enabled()).toBe(false)
			expect(Haptics.play("supernova")).toBe(false)
			expect(#h.log.haptics).toBe(0)
		end)
	end)

	describe("Console › harnais (Gamepad, Layout)", function()
		-- Petite interface : grille 2 × 2 de boutons dans une fenêtre SelectionGroup, un bouton dehors
		local function ui(h, behavior)
			local Instance = h.globals.Instance
			local gui = Instance.new("ScreenGui")
			gui.Name = "Nav"
			gui.Parent = h.localPlayer.PlayerGui
			local window = Instance.new("Frame")
			window.Name = "Window"
			window.Size = UDim2.fromOffset(400, 300)
			window.Position = UDim2.fromOffset(400, 200)
			window.SelectionGroup = true
			if behavior then
				for _, dir in { "Up", "Down", "Left", "Right" } do
					window["SelectionBehavior" .. dir] = behavior
				end
			end
			window.Parent = gui
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.fromOffset(150, 100)
			grid.CellPadding = UDim2.fromOffset(20, 20)
			grid.Parent = window
			local buttons = {}
			for i = 1, 4 do
				local b = Instance.new("TextButton")
				b.Name = "B" .. i
				b.LayoutOrder = i
				b.Text = "Bouton " .. i
				b.TextScaled = true
				b.Parent = window
				buttons[i] = b
			end
			local outside = Instance.new("TextButton")
			outside.Name = "Outside"
			outside.Size = UDim2.fromOffset(100, 100)
			outside.Position = UDim2.fromOffset(100, 250)
			outside.Text = ""
			outside.Parent = gui
			local hidden = Instance.new("TextButton")
			hidden.Name = "Hidden"
			hidden.Visible = false
			hidden.Parent = window
			Layout.apply(h)
			return gui, window, buttons, outside
		end

		it("Layout : grille, positions absolues et visibilité", function()
			local h = client()
			local _, window, buttons = ui(h)
			local r1, r2, r3 = Layout.rect(buttons[1]), Layout.rect(buttons[2]), Layout.rect(buttons[3])
			expect({ r1.x, r1.y, r1.w, r1.h }).toEqual({ 400, 258, 150, 100 })
			expect({ r2.x, r2.y }).toEqual({ 570, 258 })
			expect({ r3.x, r3.y }).toEqual({ 400, 378 })
			expect(buttons[2].AbsolutePosition).toBe(Vector2.new(570, 200))
			expect(buttons[2].AbsoluteSize).toBe(Vector2.new(150, 100))
			expect(Layout.selectable(window)).toBe(false) -- un Frame n'est pas sélectionnable
			expect(#Layout.selectables(h, window)).toBe(4) -- le bouton masqué ne compte pas
		end)

		it("Layout : liste, marges intérieures, UIScale et contraintes de taille", function()
			local h = client()
			local Instance = h.globals.Instance
			local gui = Instance.new("ScreenGui")
			gui.IgnoreGuiInset = true
			gui.Parent = h.localPlayer.PlayerGui
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromScale(1, 1)
			frame.Parent = gui
			local scale = Instance.new("UIScale")
			scale.Scale = 2
			scale.Parent = frame
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = roblox.UDim.new(0, 10)
			pad.PaddingTop = roblox.UDim.new(0, 5)
			pad.Parent = frame
			local list = Instance.new("UIListLayout")
			list.Padding = roblox.UDim.new(0, 4)
			list.Parent = frame
			local a = Instance.new("Frame")
			a.Size = UDim2.fromOffset(50, 20)
			a.LayoutOrder = 2
			a.Parent = frame
			local b = Instance.new("Frame")
			b.Size = UDim2.new(2, 0, 0, 30)
			b.LayoutOrder = 1
			b.Parent = frame
			local limit = Instance.new("UISizeConstraint")
			limit.MaxSize = Vector2.new(100, 1000)
			limit.Parent = b
			Layout.apply(h)
			local rb, ra = Layout.rect(b), Layout.rect(a)
			expect({ rb.x, rb.y, rb.w, rb.h }).toEqual({ 20, 10, 200, 60 })
			expect({ ra.x, ra.y, ra.w, ra.h }).toEqual({ 20, 78, 100, 40 })
		end)

		it("navigation : explicite d'abord, puis géométrique dans le SelectionGroup", function()
			local h = client()
			local _, window, buttons, outside = ui(h)
			expect(Layout.step(h, buttons[1], "Right")).toBe(buttons[2])
			expect(Layout.step(h, buttons[1], "Down")).toBe(buttons[3])
			expect(Layout.step(h, buttons[4], "Up")).toBe(buttons[2])
			buttons[1].NextSelectionRight = buttons[4]
			expect(Layout.step(h, buttons[1], "Right")).toBe(buttons[4])
			-- Escape (défaut) : la sélection sort de la fenêtre vers la gauche
			expect(Layout.step(h, buttons[1], "Left")).toBe(outside)
			expect(Layout.names(Layout.escapes(h, window, buttons[1]))).toBe("Nav.Outside")
			expect(#Layout.unreachable(h, window, buttons[1])).toBe(0)
		end)

		it("navigation : SelectionBehavior Stop garde la sélection dans la fenêtre", function()
			local h = client()
			local _, window, buttons = ui(h, Enum.SelectionBehavior.Stop)
			expect(Layout.step(h, buttons[1], "Left")).toBeNil()
			expect(#Layout.escapes(h, window, buttons[1])).toBe(0)
			buttons[4].Visible = false
			Layout.apply(h)
			expect(Layout.step(h, buttons[2], "Down")).toBe(buttons[3])
			expect(Layout.step(h, buttons[3], "Right")).toBe(buttons[2])
			expect(#Layout.unreachable(h, window, buttons[1])).toBe(0)
		end)

		it("Gamepad : actions CAS par priorité, Pass propage, Sink arrête ; navigation et ✕", function()
			local h = client({ console = true })
			local cas = h.game.ContextActionService
			local calls = {}
			cas:BindAction("Low", function(name, state)
				table.insert(calls, name .. ":" .. state.Name)
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.ButtonB)
			cas:BindActionAtPriority("High", function(name, state)
				table.insert(calls, name .. ":" .. state.Name)
				return Enum.ContextActionResult.Pass
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
			expect(Gamepad.tap(h, Enum.KeyCode.ButtonB)).toBe("Low")
			expect(calls).toEqual({ "High:Begin", "Low:Begin", "High:End", "Low:End" })
			cas:UnbindAction("Low")
			table.clear(calls)
			expect(Gamepad.tap(h, Enum.KeyCode.ButtonB)).toBeNil()
			expect(#calls).toBe(2)
			-- sélection active : la croix navigue, ✕ active au relâchement
			local _, _, buttons = ui(h, Enum.SelectionBehavior.Stop)
			local activated = 0
			buttons[2].Activated:Connect(function()
				activated += 1
			end)
			local gained = 0
			buttons[2].SelectionGained:Connect(function()
				gained += 1
			end)
			h.game.GuiService.SelectedObject = buttons[1]
			Gamepad.tap(h, Enum.KeyCode.DPadRight)
			expect(Gamepad.selected(h)).toBe(buttons[2])
			expect(gained).toBe(1)
			Gamepad.press(h, Enum.KeyCode.ButtonA)
			expect(activated).toBe(0)
			Gamepad.release(h, Enum.KeyCode.ButtonA)
			expect(activated).toBe(1)
			Gamepad.tap(h, Enum.KeyCode.DPadLeft)
			Gamepad.tap(h, Enum.KeyCode.DPadLeft) -- bord de la fenêtre (Stop) : reste
			expect(Gamepad.selected(h)).toBe(buttons[1])
		end)

		it("audit : glyphe non PlayStation, lettre Xbox, petit texte, hors zone sûre", function()
			local h = client({ console = true })
			local Instance = h.globals.Instance
			local gui = Instance.new("ScreenGui")
			gui.IgnoreGuiInset = true
			gui.Parent = h.localPlayer.PlayerGui
			local cap = Instance.new("TextLabel")
			cap.Name = "Cap"
			cap.Text = "X"
			cap.TextSize = 24
			cap.Size = UDim2.fromOffset(40, 40)
			cap.Position = UDim2.fromOffset(400, 400)
			cap.Parent = gui
			local tiny = Instance.new("TextLabel")
			tiny.Name = "Tiny"
			tiny.Text = "Bonjour"
			tiny.TextScaled = true
			tiny.Size = UDim2.fromOffset(200, 12)
			tiny.Position = UDim2.fromOffset(400, 500)
			tiny.Parent = gui
			local edge = Instance.new("TextButton")
			edge.Name = "Edge"
			edge.Text = ""
			edge.Size = UDim2.fromOffset(80, 80)
			edge.Parent = gui
			local fake = Instance.new("Frame")
			fake.Name = "Fake"
			fake.Size = UDim2.fromOffset(36, 36)
			fake.Position = UDim2.fromOffset(600, 600)
			fake:SetAttribute("GlyphKey", "ButtonX")
			fake.Parent = gui
			local image = Instance.new("ImageLabel")
			image.Name = "Image"
			image.Image = Gamepad.XBOX_GLYPHS .. "ButtonX@2x.png"
			image.Parent = fake
			local issues = Gamepad.audit(h)
			expect(#issues).toBe(4)
			local text = table.concat(issues, "\n")
			expect(string.find(text, "glyphe non PlayStation", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "texte de bouton Xbox", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "texte trop petit", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "hors de la zone sûre TV : ScreenGui.Edge", 1, true) ~= nil).toBe(true)
			-- décoratif : ignoré
			tiny:SetAttribute("Decorative", true)
			expect(#Gamepad.audit(h)).toBe(3)
		end)
	end)

	describe("Console › interfaces entre groupes", function()
		it(
			"InputController.setPanelGate transmet la garde du HUD à PanelController ; focusTarget vide",
			function()
				local h = client({ console = true })
				local Input = h:require(CLIENT .. "Controllers.InputController")
				local PC = h:require(CLIENT .. "Controllers.PanelController")
				expect(type(Input.QuestToggled.Connect)).toBe("function")
				expect(PC.allowed("Shop")).toBe(true)
				Input.setPanelGate(function(name)
					return name ~= "Shop"
				end)
				expect(PC.allowed("Shop")).toBe(false)
				expect(PC.allowed("Upgrades")).toBe(true)
				PC.setGate(function()
					error("garde en panne")
				end)
				expect(PC.allowed("Upgrades")).toBe(false)
				Input.setPanelGate(nil)
				expect(PC.allowed("Shop")).toBe(true)
				expect(PC.focusTarget()).toBeNil()
			end
		)
	end)

	describe("Console › projet", function()
		it(
			"curseur virtuel désactivé : navigation directionnelle seule (StarterGui.VirtualCursorMode)",
			function()
				local fs = require("@lune/fs")
				local serde = require("@lune/serde")
				local project = serde.decode("json", fs.readFile("default.project.json"))
				expect(project.tree.StarterGui["$properties"].VirtualCursorMode).toBe("Disabled")
			end
		)
	end)

	describe("Console › démarrage complet en console, manette seule", function()
		it(
			"Main.client : sans erreur ni avertissement, API Roblox valide, échelle TV, chat coupé",
			function()
				local h = client({ console = true })
				ApiAudit.start()
				local ok, err = pcall(function()
					h:boot()
					h:fireClient(
						"ReplicatedStorage.Remotes.DataSnapshot",
						{ glow = 5, onboarding = { step = 8, p = 0 } }
					)
					h:step(1 / 60, 30)
					h:settle(3)
				end)
				local issues = ApiAudit.stop()
				expect(ok and true or err).toBe(true)
				expect(table.concat(issues, "\n")).toBe("")
				expect(table.concat(h.errors, "\n")).toBe("")
				expect(table.concat(h:warnings(), "\n")).toBe("")
				local P = platform(h)
				expect(P.inputKind()).toBe(P.GAMEPAD)
				expect(h.localPlayer.PlayerGui.HUD.Safe.RootScale.Scale).toBe(1.5)
				expect(h.game.TextChatService.ChatWindowConfiguration.Enabled).toBe(false)
				expect(h.game.TextChatService.ChatInputBarConfiguration.Enabled).toBe(false)
				-- aucune sélection au départ : le stick fait marcher le personnage
				expect(Gamepad.selected(h)).toBeNil()
				Layout.apply(h)
				expect(#Layout.selectables(h) > 0).toBe(true)
			end
		)
	end)
end
