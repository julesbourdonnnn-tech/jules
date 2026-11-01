--!nocheck
-- FocusGuard (paquet client-panels) : les 8 règles du focus (GDD §10.6, docs/04 §14.2) sur le vrai
-- client console démarré ; fenêtres de test construites avec UI/Root. Zéro trace : aucune erreur,
-- aucun avertissement (ErrorReporter.report est espionné : un sauvetage est un signalement attendu).
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum
local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup()
		local h = TvAudit.client({})
		local c = {
			h = h,
			FG = TvAudit.mod(h, "UI.FocusGuard"),
			Root = TvAudit.mod(h, "UI.Root"),
			Clock = h:require("ReplicatedStorage.Shared.Util.Clock"),
			reports = {},
		}
		local ER = TvAudit.mod(h, "Controllers.ErrorReporter")
		ER.report = function(kind, text)
			table.insert(c.reports, { kind = kind, text = text })
		end
		return c
	end

	-- Fenêtre de test : cadre et n boutons
	local function window(c, name, n, opts)
		opts = opts or {}
		local safe = c.Root.safe("Test_" .. name, 20)
		local Instance = c.h.globals.Instance
		local root = Instance.new("Frame")
		root.Name = name
		root.Size = UDim2.fromOffset(800, 600)
		root.Position = UDim2.fromOffset(400, 200)
		root.Parent = safe
		local buttons = {}
		for i = 1, n do
			local b = Instance.new("TextButton")
			b.Name = "B" .. i
			b.Text = "B" .. i
			b.Size = UDim2.fromOffset(300, 80)
			b.Position = UDim2.fromOffset(20, 20 + (i - 1) * 100)
			b.Parent = root
			buttons[i] = b
		end
		local w = {
			name = name,
			root = root,
			blocking = opts.blocking == true,
			default = opts.default or function()
				return buttons[1]
			end,
			onBack = opts.onBack or function()
				return false
			end,
			opener = opts.opener,
		}
		return w, buttons, root
	end

	local function later(c, dt)
		c.Clock.advance(dt or 0.3)
		c.h:step(1 / 60, 1)
		c.h:settle(1)
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	describe(
		"FocusGuard › règles 1, 3, 7 : une source, sélection dans la fenêtre, SelectionGroup Stop",
		function()
			it("ouvrir une fenêtre pose la sélection par défaut et verrouille sa racine", function()
				local c = setup()
				local w, buttons, root = window(c, "A", 3)
				c.FG.open(w)
				expect(c.h.game.GuiService.SelectedObject).toBe(buttons[1])
				expect(c.FG.top().name).toBe("A")
				expect(c.FG.anyOpen()).toBe(true)
				expect(root.SelectionGroup).toBe(true)
				expect(root.SelectionBehaviorUp).toBe(Enum.SelectionBehavior.Stop)
				expect(root.SelectionBehaviorDown).toBe(Enum.SelectionBehavior.Stop)
				expect(root.SelectionBehaviorLeft).toBe(Enum.SelectionBehavior.Stop)
				expect(root.SelectionBehaviorRight).toBe(Enum.SelectionBehavior.Stop)
				-- la croix ne fait jamais sortir la sélection de la fenêtre
				Layout.apply(c.h)
				expect(#Layout.escapes(c.h, root, buttons[1])).toBe(0)
				Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
				expect(c.h.game.GuiService.SelectedObject).toBe(buttons[2])
				clean(c)
			end)

			it(
				"sélection vidée ou sortie de la fenêtre : rendue en 0,25 s au dernier objet affiché",
				function()
					local c = setup()
					local w, buttons = window(c, "A", 3)
					c.FG.open(w)
					c.h.game.GuiService.SelectedObject = buttons[2]
					c.h:settle(1)
					c.h.game.GuiService.SelectedObject = nil
					c.h:step(1 / 60, 1)
					-- pas avant 0,25 s
					later(c, 0.1)
					expect(c.h.game.GuiService.SelectedObject).toBeNil()
					later(c, 0.2)
					expect(c.h.game.GuiService.SelectedObject).toBe(buttons[2])
					expect(c.FG.rescues()).toBe(1)
					expect(#c.reports).toBe(1)
					expect(c.reports[1].text).toContain("FocusRescued")
					-- objet détruit (liste rechargée) : défaut de l'écran
					buttons[2]:Destroy()
					c.h:step(1 / 60, 1)
					later(c, 0.3)
					expect(c.h.game.GuiService.SelectedObject).toBe(buttons[1])
					expect(c.FG.rescues()).toBe(2)
					-- sélection posée hors de la fenêtre active
					local _, other = window(c, "B", 1)
					c.h.game.GuiService.SelectedObject = other[1]
					c.h:step(1 / 60, 1)
					later(c, 0.3)
					expect(c.h.game.GuiService.SelectedObject).toBe(buttons[1])
					clean(c)
				end
			)
		end
	)

	describe("FocusGuard › règle 2 : en jeu, aucune sélection", function()
		it(
			"une sélection posée sans fenêtre est effacée en 0,25 s ; l'écran de chargement est exempté",
			function()
				local c = setup()
				local _, buttons = window(c, "A", 1)
				c.h.game.GuiService.SelectedObject = buttons[1]
				c.h:step(1 / 60, 1)
				later(c, 0.3)
				expect(c.h.game.GuiService.SelectedObject).toBeNil()
				expect(c.FG.rescues()).toBe(1)
				-- ScreenGui « Loading » (src/first : Réessayer sélectionné d'office) : jamais touché
				local Instance = c.h.globals.Instance
				local loading = Instance.new("ScreenGui")
				loading.Name = "Loading"
				local retry = Instance.new("TextButton")
				retry.Parent = loading
				loading.Parent = c.h.localPlayer.PlayerGui
				c.h.game.GuiService.SelectedObject = retry
				c.h:step(1 / 60, 1)
				later(c, 1)
				expect(c.h.game.GuiService.SelectedObject).toBe(retry)
				expect(c.FG.rescues()).toBe(1)
				clean(c)
			end
		)
	end)

	describe("FocusGuard › règle 3 : fenêtre de Roblox (hold), 60 s au plus", function()
		it(
			"tenue sans sauvetage, rendue à release() ; rendue de force après 60 s (sauvetage compté)",
			function()
				local c = setup()
				local w, buttons = window(c, "Shop", 2)
				c.FG.open(w)
				c.FG.hold(60)
				expect(c.FG.held()).toBe(true)
				c.h.game.GuiService.SelectedObject = nil
				c.h:step(1 / 60, 1)
				later(c, 30)
				expect(c.h.game.GuiService.SelectedObject).toBeNil()
				expect(c.FG.rescues()).toBe(0)
				c.FG.release()
				expect(c.h.game.GuiService.SelectedObject).toBe(buttons[1])
				expect(c.FG.rescues()).toBe(0)
				-- jamais relâchée : rendue de force au bout de 60 s
				c.FG.hold(600) -- borné à 60 s
				c.h.game.GuiService.SelectedObject = nil
				later(c, 59)
				expect(c.h.game.GuiService.SelectedObject).toBeNil()
				later(c, 2)
				expect(c.h.game.GuiService.SelectedObject).toBe(buttons[1])
				expect(c.FG.held()).toBe(false)
				expect(c.FG.rescues()).toBe(1)
				-- valeurs hostiles : NaN, négatif → bornées, sans erreur
				c.FG.hold(0 / 0)
				c.FG.release()
				c.FG.hold(-5)
				later(c, 0.1)
				expect(c.FG.held()).toBe(false)
				clean(c)
			end
		)
	end)

	describe("FocusGuard › règle 4 : fermer rend la sélection à l'ouvreur, ou au jeu", function()
		it(
			"fenêtre empilée : retour au bouton qui l'a ouverte ; dernière fenêtre : sélection vide",
			function()
				local c = setup()
				local wa, a = window(c, "A", 3)
				c.FG.open(wa)
				c.h.game.GuiService.SelectedObject = a[3]
				c.h:settle(1)
				local wb, b = window(c, "B", 2)
				c.FG.open(wb) -- ouvreur implicite : la sélection courante (a[3])
				expect(c.h.game.GuiService.SelectedObject).toBe(b[1])
				later(c, 0.5)
				c.FG.close("B")
				expect(c.FG.top().name).toBe("A")
				expect(c.h.game.GuiService.SelectedObject).toBe(a[3])
				later(c, 0.5)
				c.FG.close("A")
				expect(c.FG.anyOpen()).toBe(false)
				expect(c.h.game.GuiService.SelectedObject).toBeNil()
				-- WindowOpened / WindowClosed
				local events = {}
				c.FG.WindowOpened:Connect(function(n)
					table.insert(events, "open:" .. n)
				end)
				c.FG.WindowClosed:Connect(function(n)
					table.insert(events, "close:" .. n)
				end)
				c.FG.open(wa)
				c.FG.closeNow("A")
				expect(events).toEqual({ "open:A", "close:A" })
				clean(c)
			end
		)
	end)

	describe("FocusGuard › règle 5 : ○ remonte d'un niveau partout", function()
		it(
			"sous-niveau géré, fermeture, erreur dans onBack, aucune fenêtre ; ○ lié seulement fenêtre ouverte",
			function()
				local c = setup()
				local level = 1
				local wa = window(c, "A", 2, {
					onBack = function()
						if level > 0 then
							level -= 1
							return true
						end
						return false
					end,
				})
				expect(c.h.actionBindings.FocusGuardBack).toBeNil()
				c.FG.open(wa)
				expect(c.h.actionBindings.FocusGuardBack ~= nil).toBe(true)
				later(c, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB) -- sous-niveau géré
				expect(c.FG.isOpen("A")).toBe(true)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB) -- premier niveau : fermée
				expect(c.FG.isOpen("A")).toBe(false)
				expect(c.h.actionBindings.FocusGuardBack).toBeNil()
				expect(c.FG.back()).toBe(false)
				-- onBack qui lève : la fenêtre se ferme quand même (toujours une sortie), sans trace
				local wb = window(c, "B", 1, {
					onBack = function()
						error("panne de test")
					end,
				})
				c.FG.open(wb)
				later(c, 0.5)
				expect(c.FG.back()).toBe(true)
				expect(c.FG.isOpen("B")).toBe(false)
				-- Retour arrière au clavier : même liaison
				c.FG.open(wb)
				expect(table.find(c.h.actionBindings.FocusGuardBack.keys, Enum.KeyCode.Backspace) ~= nil).toBe(
					true
				)
				clean(c)
			end
		)
	end)

	describe("FocusGuard › règle 6 : double appui ignoré (0,35 s)", function()
		it("close et back juste après l'ouverture sont ignorés ; closeNow passe", function()
			local c = setup()
			local wa = window(c, "A", 1)
			c.FG.open(wa)
			expect(c.FG.canClose("A")).toBe(false)
			c.FG.close("A")
			expect(c.FG.isOpen("A")).toBe(true)
			expect(c.FG.back()).toBe(true)
			expect(c.FG.isOpen("A")).toBe(true)
			later(c, 0.4)
			expect(c.FG.canClose("A")).toBe(true)
			c.FG.closeNow("A")
			c.FG.open(wa)
			c.FG.closeNow("A") -- transition voulue par le code : sans garde
			expect(c.FG.isOpen("A")).toBe(false)
			clean(c)
		end)
	end)

	describe("FocusGuard › règle 8 et cycle de vie", function()
		it(
			"racine détruite sans fermeture : fenêtre fermée d'office, sauvetage compté et signalé",
			function()
				local c = setup()
				local wa, a = window(c, "A", 1)
				c.FG.open(wa)
				local wb, _, rootB = window(c, "B", 1)
				c.FG.open(wb)
				rootB:Destroy()
				c.h:step(1 / 60, 1)
				expect(c.FG.isOpen("B")).toBe(false)
				expect(c.FG.top().name).toBe("A")
				expect(c.FG.rescues()).toBe(1)
				expect(c.reports[1].text).toContain("lost:B")
				later(c, 0.3)
				expect(c.h.game.GuiService.SelectedObject).toBe(a[1])
				clean(c)
			end
		)

		it("charges hostiles : open sans table, sans racine, nom absent → ignorés sans erreur", function()
			local c = setup()
			c.FG.open(nil)
			c.FG.open({})
			c.FG.open({ name = 5, root = nil })
			c.FG.close("absente")
			c.FG.closeNow("absente")
			expect(c.FG.anyOpen()).toBe(false)
			expect(c.FG.top()).toBeNil()
			-- défaut qui lève : premier objet sélectionnable affiché
			local wa, a = window(c, "A", 2, {
				default = function()
					error("défaut cassé")
				end,
			})
			c.FG.open(wa)
			expect(c.h.game.GuiService.SelectedObject).toBe(a[1])
			clean(c)
		end)
	end)
end
