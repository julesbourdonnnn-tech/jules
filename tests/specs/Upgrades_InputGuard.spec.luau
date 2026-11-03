--!nocheck
-- Upgrades_InputGuard (règle 17 du GDD v2.0 §10.8, « Un ✕ n'achète jamais par accident » ; §10.6
-- règle 6, §10.7.8, §10.7.9 ; docs/04 §27.8, N14) — PARTIE GÉNÉRIQUE du lot B1 : la garde d'entrée de
-- FocusGuard et le maintien de Widgets.hold, sur le vrai client console démarré, avec des fenêtres de
-- test (les cas de l'écran Améliorations lui-même appartiennent au lot B2).
--   * à l'ouverture de TOUTE fenêtre, ✕ (Entrée, clic) est ignoré tant que son relâchement n'est pas vu
--     et que Balance.Upgrades.GuardOpen (0,3 s) n'est pas passée ; « △ puis ✕ tenu 2 s : 0 achat » ;
--   * même règle avec GuardFocus (0,4 s) quand l'élément sous le focus change d'identifiant (sélection
--     rendue par le code, L1 / R1, attribut FocusId) ;
--   * un achat part à la fin d'un maintien de Balance.Upgrades.HoldSeconds (0,6 s), ×1 compris, de ✕,
--     d'Entrée ou du clic ; relâché avant : rien ;
--   * rien ne bloque l'entrée pour toujours (fin d'appui perdue, horloge recalée, fenêtre fermée) ;
--   * mêmes résultats interrupteur UpgradesScreen coupé et ouvert (sécurité du jeu de base).
-- Zéro trace : aucune erreur ni avertissement.

local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum
local UDim2 = roblox.UDim2
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup(flagOn: boolean)
		local h = TvAudit.client({})
		local c = {
			h = h,
			FG = TvAudit.mod(h, "UI.FocusGuard"),
			Root = TvAudit.mod(h, "UI.Root"),
			Widgets = TvAudit.mod(h, "UI.Panels.Widgets"),
			Clock = h:require("ReplicatedStorage.Shared.Util.Clock"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			Features = h:require("ReplicatedStorage.Shared.Config.Features"),
		}
		c.Features.set("UpgradesScreen", flagOn)
		-- aucune fenêtre du jeu ouverte au départ (la garde part de zéro)
		TvAudit.toGame(h)
		TvAudit.tick(h, 1)
		return c
	end

	local function teardown(c)
		c.Features.reset()
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	-- avance l'horloge du jeu de `dt` par pas de 1/30 s (boucles Heartbeat des maintiens)
	local function run(c, dt: number)
		local steps = math.max(1, math.floor(dt * 30 + 0.5))
		for _ = 1, steps do
			c.Clock.advance(dt / steps)
			c.h:step(dt / steps, 1)
		end
		c.h:settle(1)
	end

	-- Fenêtre de test : un bouton à maintenir (achat) et un bouton ordinaire
	local function window(c, name: string)
		local safe = c.Root.safe("Guard_" .. name, 30)
		local root = c.h.globals.Instance.new("Frame")
		root.Name = name
		root.Size = UDim2.fromOffset(900, 500)
		root.Position = UDim2.fromOffset(400, 200)
		root.Parent = safe
		local counts = { bought = 0, clicked = 0 }
		local hold = c.Widgets.hold({
			parent = root,
			name = "Buy",
			size = UDim2.fromOffset(360, 112),
			position = UDim2.fromOffset(40, 40),
			key = "common.ok",
			duration = c.Balance.Upgrades.HoldSeconds,
			onComplete = function()
				counts.bought += 1
			end,
		})
		local button = c.Widgets.button({
			parent = root,
			name = "Plain",
			size = UDim2.fromOffset(360, 112),
			position = UDim2.fromOffset(460, 40),
			key = "common.ok",
			onActivate = function()
				counts.clicked += 1
			end,
		})
		local w = {
			name = name,
			root = root,
			blocking = false,
			default = function()
				return hold.button
			end,
			onBack = function()
				return false
			end,
		}
		return w, hold, button, counts
	end

	local function input(keyCode, state, kind)
		return {
			KeyCode = keyCode,
			UserInputType = kind or Enum.UserInputType.Keyboard,
			UserInputState = state,
			Position = Vector3.zero,
			Delta = Vector3.zero,
		}
	end

	for _, flagOn in { false, true } do
		local tag = if flagOn then "interrupteur ouvert" else "interrupteur coupé"
		describe("Upgrades_InputGuard (générique) › " .. tag, function()
			it("valeurs du contrat : GuardOpen 0,3 s, GuardFocus 0,4 s, HoldSeconds 0,6 s", function()
				local c = setup(flagOn)
				expect(c.Balance.Upgrades.GuardOpen).toBe(0.3)
				expect(c.Balance.Upgrades.GuardFocus).toBe(0.4)
				expect(c.Balance.Upgrades.HoldSeconds).toBe(0.6)
				teardown(c)
			end)

			it("△ puis ✕ tenu 2 s : 0 achat ; puis ✕ tenu 0,6 s : exactement 1", function()
				local c = setup(flagOn)
				local w, hold, _, counts = window(c, "W1")
				-- △ ouvre la fenêtre (le bouton d'achat a le focus d'office)
				c.FG.open(w)
				c.h:settle(1)
				expect(c.h.game.GuiService.SelectedObject).toBe(hold.button)
				run(c, 0.1)
				Gamepad.press(c.h, Enum.KeyCode.ButtonA)
				run(c, 2)
				expect(hold.holding()).toBe(false)
				Gamepad.release(c.h, Enum.KeyCode.ButtonA)
				run(c, 0.2)
				expect(counts.bought).toBe(0)
				-- relâchement vu, garde passée : un vrai maintien achète une fois
				Gamepad.press(c.h, Enum.KeyCode.ButtonA)
				run(c, 0.7)
				Gamepad.release(c.h, Enum.KeyCode.ButtonA)
				run(c, 0.2)
				expect(counts.bought).toBe(1)
				teardown(c)
			end)

			it(
				"vrai client : △ ouvre le menu, ✕ tenu 2 s aussitôt : rien n'est ouvert ; ✕ ensuite : le panneau",
				function()
					local c = setup(flagOn)
					local PC = TvAudit.mod(c.h, "UI.PanelController")
					-- △ (InputController ; avant la leçon du menu, l'ouverture par le code)
					Gamepad.tap(c.h, Enum.KeyCode.ButtonY)
					c.h:settle(1)
					if not c.FG.isOpen("menu") then
						PC.toggleMenu()
						c.h:settle(1)
					end
					expect(c.FG.isOpen("menu")).toBe(true)
					local selected = c.h.game.GuiService.SelectedObject
					expect(selected ~= nil).toBe(true)
					run(c, 0.1)
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 2)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.3)
					expect(c.FG.names()).toEqual({ "menu" })
					expect(PC.current()).toBeNil()
					-- appui suivant, garde passée : l'entrée sélectionnée s'ouvre
					c.h.game.GuiService.SelectedObject = selected
					c.h:settle(1)
					Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.3)
					expect(#c.FG.names() >= 1 and c.FG.names()[#c.FG.names()] ~= "menu").toBe(true)
					TvAudit.toGame(c.h)
					teardown(c)
				end
			)

			it("✕ déjà enfoncé à l'ouverture et tenu : rien, même après la garde", function()
				local c = setup(flagOn)
				local w, hold, _, counts = window(c, "W2")
				-- ✕ appuyé dans le jeu (aucune sélection), la fenêtre s'ouvre pendant l'appui
				Gamepad.press(c.h, Enum.KeyCode.ButtonA)
				c.FG.open(w)
				run(c, 1.5)
				expect(hold.holding()).toBe(false)
				expect(c.FG.confirmReady()).toBe(false)
				Gamepad.release(c.h, Enum.KeyCode.ButtonA)
				run(c, 0.1)
				expect(counts.bought).toBe(0)
				-- juste après ce relâchement, un Activated de ce même appui est encore refusé ; ensuite libre
				expect(c.FG.confirmReady()).toBe(false)
				run(c, 0.3)
				expect(c.FG.confirmReady()).toBe(true)
				teardown(c)
			end)

			it(
				"maintien de 0,6 s exactement : relâché à 0,5 s rien ; à 0,6 s un achat ; rien en double",
				function()
					local c = setup(flagOn)
					local w, hold, _, counts = window(c, "W3")
					c.FG.open(w)
					run(c, 0.5)
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.5)
					expect(hold.holding()).toBe(true)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.1)
					expect(counts.bought).toBe(0)
					expect(hold.fill.Size.X.Scale).toBe(0) -- l'anneau se vide
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.6 + 1 / 30)
					expect(counts.bought).toBe(1)
					-- tenu encore 2 s : jamais un 2e achat sans relâcher
					run(c, 2)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.1)
					expect(counts.bought).toBe(1)
					teardown(c)
				end
			)

			it("10 appuis de ✕ à 100 ms : aucun achat (chaque appui est plus court que 0,6 s)", function()
				local c = setup(flagOn)
				local w, _, _, counts = window(c, "W4")
				c.FG.open(w)
				run(c, 0.5)
				for _ = 1, 10 do
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.05)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.05)
				end
				expect(counts.bought).toBe(0)
				teardown(c)
			end)

			it("Entrée et clic de la souris : même garde et même maintien de 0,6 s", function()
				local c = setup(flagOn)
				local w, hold, _, counts = window(c, "W5")
				local uis = c.h.game.UserInputService
				c.FG.open(w)
				-- Entrée 0,1 s après l'ouverture, tenue 1 s : rien
				run(c, 0.1)
				uis.InputBegan:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.Begin), true)
				run(c, 1)
				uis.InputEnded:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.End), true)
				run(c, 0.1)
				expect(counts.bought).toBe(0)
				-- Entrée tenue 0,6 s après la garde : un achat
				uis.InputBegan:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.Begin), true)
				run(c, 0.7)
				uis.InputEnded:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.End), true)
				run(c, 0.1)
				expect(counts.bought).toBe(1)
				-- souris : fenêtre rouverte, clic maintenu 0,1 s après l'ouverture : rien
				c.FG.closeNow(w.name)
				run(c, 0.5)
				c.FG.open(w)
				run(c, 0.1)
				local mouse = Enum.UserInputType.MouseButton1
				uis.InputBegan:Fire(input(nil, Enum.UserInputState.Begin, mouse), false)
				hold.button.MouseButton1Down:Fire(0, 0)
				run(c, 1)
				uis.InputEnded:Fire(input(nil, Enum.UserInputState.End, mouse), false)
				hold.button.MouseButton1Up:Fire(0, 0)
				run(c, 0.1)
				expect(counts.bought).toBe(1)
				-- clic maintenu 0,6 s après la garde : un achat de plus
				uis.InputBegan:Fire(input(nil, Enum.UserInputState.Begin, mouse), false)
				hold.button.MouseButton1Down:Fire(0, 0)
				run(c, 0.7)
				uis.InputEnded:Fire(input(nil, Enum.UserInputState.End, mouse), false)
				run(c, 0.1)
				expect(counts.bought).toBe(2)
				teardown(c)
			end)

			it(
				"bouton ordinaire : ✕ à 0,1 s ignoré, à 0,35 s accepté ; activation par le code aussi",
				function()
					local c = setup(flagOn)
					local w, _, button, counts = window(c, "W6")
					c.FG.open(w)
					c.h.game.GuiService.SelectedObject = button
					run(c, 0.1)
					Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
					expect(counts.clicked).toBe(0)
					run(c, 0.25)
					Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
					expect(counts.clicked).toBe(1)
					-- activation sans appui connu (code) : jugée sur l'horloge seule
					c.FG.closeNow(w.name)
					run(c, 0.5)
					c.FG.open(w)
					c.h.game.GuiService.SelectedObject = button
					button.Activated:Fire()
					expect(counts.clicked).toBe(1)
					run(c, 0.31)
					button.Activated:Fire()
					expect(counts.clicked).toBe(2)
					teardown(c)
				end
			)

			it("élément sous le focus changé (code, L1 / R1, FocusId) : GuardFocus 0,4 s", function()
				local c = setup(flagOn)
				local w, hold, button, counts = window(c, "W7")
				c.FG.open(w)
				run(c, 0.5)
				-- l'élément sélectionné disparaît : FocusGuard rend la sélection (identifiant changé)
				c.h.game.GuiService.SelectedObject = button
				c.h:settle(1)
				button.Visible = false
				c.FG.refocus()
				expect(c.h.game.GuiService.SelectedObject).toBe(hold.button)
				button.Visible = true
				c.h.game.GuiService.SelectedObject = button
				run(c, 0.2)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(0)
				run(c, 0.25)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(1)
				-- L1 (onglet) dans une fenêtre : même garde
				Gamepad.tap(c.h, Enum.KeyCode.ButtonL1)
				run(c, 0.2)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(1)
				run(c, 0.25)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(2)
				-- l'élément sélectionné change d'identifiant (FocusId : carte recalculée)
				button:SetAttribute("FocusId", "snack")
				run(c, 0.5)
				button:SetAttribute("FocusId", "pens")
				run(c, 0.2)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(2)
				run(c, 0.25)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(3)
				-- navigation du joueur à la croix : aucune garde (le joueur voit où il va)
				c.h.game.GuiService.SelectedObject = hold.button
				run(c, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.DPadRight)
				expect(c.h.game.GuiService.SelectedObject).toBe(button)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(4)
				teardown(c)
			end)

			it(
				"Widgets.holdOn : 0,6 s par défaut, progression, relâché trop tôt signalé, Entrée sur le bouton survolé",
				function()
					local c = setup(flagOn)
					local w, _, button, counts = window(c, "W9")
					local alphas, early = {}, 0
					local hold = c.Widgets.holdOn(button, {
						onComplete = function()
							counts.bought += 1
						end,
						onProgress = function(alpha)
							table.insert(alphas, alpha)
						end,
						onEarly = function()
							early += 1
						end,
					})
					expect(hold.duration).toBe(c.Balance.Upgrades.HoldSeconds)
					c.FG.open(w)
					c.h.game.GuiService.SelectedObject = button
					run(c, 0.5)
					-- relâché à 0,3 s : rien, signalé une fois, progression remise à 0
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.3)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.05)
					expect(counts.bought).toBe(0)
					expect(early).toBe(1)
					expect(alphas[#alphas]).toBe(0)
					-- tenu 0,6 s : un achat, progression croissante jusqu'à 1
					table.clear(alphas)
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.7)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.05)
					expect(counts.bought).toBe(1)
					expect(early).toBe(1)
					local top = 0
					for i = 2, #alphas do
						top = math.max(top, alphas[i])
					end
					expect(top).toBe(1)
					-- clavier-souris : aucune sélection, Entrée maintenue sur le bouton survolé
					c.h.game.GuiService.SelectedObject = nil
					c.h:settle(1)
					button.MouseEnter:Fire(0, 0)
					local uis = c.h.game.UserInputService
					uis.InputBegan:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.Begin), false)
					run(c, 0.7)
					uis.InputEnded:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.End), false)
					run(c, 0.05)
					expect(counts.bought).toBe(2)
					-- souris partie (et aucune sélection à cet instant ; une fenêtre ouverte la rend en 0,25 s,
					-- FocusGuard règle 3) : Entrée ne maintient plus rien
					button.MouseLeave:Fire(0, 0)
					c.h.game.GuiService.SelectedObject = nil
					c.h:settle(1)
					uis.InputBegan:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.Begin), false)
					run(c, 0.7)
					uis.InputEnded:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.End), false)
					run(c, 0.05)
					expect(counts.bought).toBe(2)
					-- jamais par Activated : un clic d'Activated seul n'achète rien
					button.Activated:Fire()
					run(c, 0.7)
					expect(counts.bought).toBe(2)
					teardown(c)
				end
			)

			it("jamais bloqué : fin d'appui perdue, fenêtre du jeu quittée, horloge recalée", function()
				local c = setup(flagOn)
				local w, _, button, counts = window(c, "W8")
				c.FG.open(w)
				c.h.game.GuiService.SelectedObject = button
				-- ✕ appuyé pendant la garde, puis la fin d'appui se perd (menu de Roblox)
				run(c, 0.1)
				Gamepad.press(c.h, Enum.KeyCode.ButtonA)
				c.h._padConfirm = nil
				c.h.game.UserInputService.WindowFocusReleased:Fire()
				run(c, 0.5)
				-- l'appui suivant est jugé seul : accepté
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(1)
				-- horloge du jeu recalée d'une heure en arrière juste après une ouverture : garde expirée
				c.FG.closeNow(w.name)
				run(c, 0.5)
				c.FG.open(w)
				c.h.game.GuiService.SelectedObject = button
				c.Clock.advance(-3600)
				c.h:step(1 / 30, 1)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(counts.clicked).toBe(2)
				-- état de la garde lisible (Diagnostics) et sans garde après sa durée
				c.FG.closeNow(w.name)
				c.FG.open(w)
				expect(c.FG.guardInfo().active).toBe(true)
				run(c, 0.35)
				expect(c.FG.guardInfo().active).toBe(false)
				expect(c.FG.confirmReady()).toBe(true)
				c.FG.closeNow(w.name)
				teardown(c)
			end)
		end)
	end
end
