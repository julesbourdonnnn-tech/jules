--!nocheck
-- PanelController (paquet client-panels) : défauts trouvés à la relecture, chacun reproduit avant sa
-- correction (GDD §9.2, §10.6 ; docs/04 §13.6, §14.2). Zéro trace.
--   * L1 / R1 (et Cards.Requested sur le panneau ouvert) changent d'onglet : la sélection restée sur la
--     page cachée était « sauvée » 0,25 s plus tard par FocusGuard et comptée comme un bug
--     (FocusRescued), avec un instant sans sélection ;
--   * une entrée du rail cachée pendant qu'elle est sélectionnée (carte « ! » rangée) : idem ;
--   * L2 / R2 : le panneau quitté retirait le voile, le flou et l'écran des panneaux puis les remettait
--     (voile qui clignote) et Changed passait par nil (le HUD réaffichait la puce Menu une image) ;
--   * flou du panneau resté sur l'ancienne caméra quand workspace.CurrentCamera change ;
--   * Guide du Squishydex : chaque ↓ / ↑ qui fait défiler jouait aussi le rebond de bout de liste
--     (son Bump, vibration listEnd) ; seul le vrai bout doit rebondir ;
--   * deux UIScale sur un même bouton (pulsation d'attention + appui) : Roblox n'en applique qu'un.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup(opts)
		local h = TvAudit.client(opts)
		local c = {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			FG = TvAudit.mod(h, "UI.FocusGuard"),
			sounds = {},
			haptics = {},
			reports = {},
		}
		local ER = TvAudit.mod(h, "Controllers.ErrorReporter")
		ER.report = function(kind, text)
			table.insert(c.reports, { kind = kind, text = text })
		end
		local Audio = TvAudit.mod(h, "Controllers.AudioController")
		local play = Audio.play
		Audio.play = function(name, ...)
			table.insert(c.sounds, name)
			return play(name, ...)
		end
		TvAudit.mod(h, "Util.Haptics").Played:Connect(function(name)
			table.insert(c.haptics, name)
		end)
		return c
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function sel(c)
		return c.h.game.GuiService.SelectedObject
	end

	-- la sélection est-elle dans la fenêtre active et affichée ?
	local function selectionOk(c)
		local top = c.FG.top()
		local s = sel(c)
		if top == nil or s == nil then
			return false
		end
		if s ~= top.root and not s:IsDescendantOf(top.root) then
			return false
		end
		Layout.apply(c.h)
		return Layout.visible(s)
	end

	local function count(list, name)
		local n = 0
		for _, v in list do
			if v == name then
				n += 1
			end
		end
		return n
	end

	local function pens(n)
		local sq = {}
		for i = 1, n do
			sq["u" .. i] = TvAudit.squishy(((i - 1) % 26) + 1, { z = 100 * i })
		end
		return sq
	end

	describe("PanelController › changement d'onglet sans sauvetage", function()
		it("R1 depuis une case de l'Enclos : sélection rendue tout de suite, aucun FocusRescued", function()
			local c = setup({ profile = { squishies = pens(8) } })
			c.PC.open("Ranch")
			TvAudit.tick(c.h, 0.5)
			local Ranch = TvAudit.mod(c.h, "UI.Panels.Ranch")
			expect(Ranch.currentTab()).toBe("pens")
			expect(sel(c).Name).toBe("Cell1")
			-- Dodo vide : la case sélectionnée disparaît avec l'onglet
			Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
			expect(Ranch.currentTab()).toBe("dodo")
			expect(selectionOk(c)).toBe(true)
			TvAudit.tick(c.h, 0.5)
			TvAudit.tick(c.h, 0.5)
			expect(c.FG.rescues()).toBe(0)
			expect(#c.reports).toBe(0)
			clean(c)
		end)

		it(
			"Squishydex : L1 / R1 de Espèces à Familles puis Guide, et Cards.Requested : jamais de sauvetage",
			function()
				local c = setup({})
				c.PC.open("Squishydex")
				TvAudit.tick(c.h, 0.5)
				expect(sel(c).Name).toBe("Cell1")
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
				expect(selectionOk(c)).toBe(true)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
				expect(selectionOk(c)).toBe(true)
				TvAudit.tick(c.h, 0.5)
				-- carte « nouvelle entrée » pendant que le Guide est ouvert : retour à Espèces
				TvAudit.mod(c.h, "UI.Cards").Requested:Fire("dex", "open")
				c.h:settle(2)
				expect(TvAudit.mod(c.h, "UI.Panels.Squishydex").currentTab()).toBe("species")
				expect(selectionOk(c)).toBe(true)
				TvAudit.tick(c.h, 0.5)
				TvAudit.tick(c.h, 0.5)
				expect(c.FG.rescues()).toBe(0)
				clean(c)
			end
		)

		it(
			"entrée « ! » sélectionnée puis rangée (plus de carte) : sélection sur une entrée visible, sans sauvetage",
			function()
				local c = setup({})
				local Cards = TvAudit.mod(c.h, "UI.Cards")
				local list = { { id = "card1", kind = "booped", blocking = false, data = {} } }
				Cards.pending = function()
					return list
				end
				c.PC.toggleMenu()
				TvAudit.tick(c.h, 0.5)
				expect(sel(c)).toBe(c.PC.entryButton("Pending"))
				table.clear(list)
				Cards.Changed:Fire()
				c.h:settle(2)
				expect(c.PC.entryButton("Pending").Visible).toBe(false)
				expect(selectionOk(c)).toBe(true)
				TvAudit.tick(c.h, 0.5)
				TvAudit.tick(c.h, 0.5)
				expect(c.FG.rescues()).toBe(0)
				clean(c)
			end
		)
	end)

	describe("PanelController › L2 / R2 sans clignotement", function()
		it("R2 : Changed ne passe jamais par nil, voile et écran des panneaux restent affichés", function()
			local c = setup({})
			local seen = {}
			c.PC.Changed:Connect(function(p)
				table.insert(seen, p or "nil")
			end)
			c.PC.open("Ranch")
			TvAudit.tick(c.h, 0.5)
			local gui = c.h.localPlayer.PlayerGui:FindFirstChild("Panels")
			local veil = gui:FindFirstChild("Veil")
			expect(gui.Enabled).toBe(true)
			local disabled, cleared = 0, 0
			gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if gui.Enabled == false then
					disabled += 1
				end
			end)
			veil:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
				if veil.BackgroundTransparency >= 0.99 then
					cleared += 1
				end
			end)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonR2)
			c.h:settle(2)
			expect(c.PC.current()).toBe("Squishydex")
			expect(seen).toEqual({ "Ranch", "Squishydex" })
			expect(disabled).toBe(0)
			expect(cleared).toBe(0)
			expect(gui.Enabled).toBe(true)
			-- open() direct d'un autre panneau (raccourci C, J…) : même règle
			TvAudit.tick(c.h, 0.5)
			c.PC.open("Objectives")
			c.h:settle(2)
			expect(seen).toEqual({ "Ranch", "Squishydex", "Objectives" })
			expect(disabled).toBe(0)
			-- fermeture réelle : le voile part et Changed dit nil
			TvAudit.tick(c.h, 0.5)
			c.PC.closeAll()
			c.h:settle(2)
			expect(seen[#seen]).toBe("nil")
			expect(gui.Enabled).toBe(false)
			clean(c)
		end)
	end)

	describe("PanelController › flou", function()
		it("caméra remplacée : le flou suit la caméra courante", function()
			local c = setup({})
			c.PC.open("Ranch")
			TvAudit.tick(c.h, 0.5)
			local ws = c.h.game.Workspace
			local old = ws.CurrentCamera
			expect(old:FindFirstChild("PanelBlur") ~= nil).toBe(true)
			c.PC.closeAll()
			TvAudit.tick(c.h, 0.5)
			local cam = c.h.globals.Instance.new("Camera")
			cam.Parent = ws
			ws.CurrentCamera = cam
			old:Destroy()
			c.h:settle(1)
			c.PC.open("Ranch")
			TvAudit.tick(c.h, 0.5)
			local blur = cam:FindFirstChild("PanelBlur")
			expect(blur ~= nil).toBe(true)
			expect(blur.Size).toBe(8)
			clean(c)
		end)
	end)

	describe("PanelController › bout de liste", function()
		it(
			"Guide : ↓ qui fait défiler ne rebondit pas ; ↓ au vrai bout rebondit (Bump, listEnd)",
			function()
				local c = setup({})
				c.PC.open("Squishydex", "guide")
				TvAudit.tick(c.h, 0.5)
				local guide = c.PC.window("Squishydex").Body.Page_guide.Guide
				expect(sel(c)).toBe(guide)
				table.clear(c.sounds)
				table.clear(c.haptics)
				local y0 = guide.Holder.Position.Y.Offset
				c.h:step(1 / 60, 2)
				Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
				c.h:settle(2)
				expect(guide.Holder.Position.Y.Offset < y0).toBe(true)
				expect(count(c.sounds, "Bump")).toBe(0)
				expect(count(c.haptics, "listEnd")).toBe(0)
				-- jusqu'au bout, puis un ↓ de plus : rebond
				local last = guide.Holder.Position.Y.Offset
				for _ = 1, 10 do
					TvAudit.tick(c.h, 0.3)
					Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
					c.h:settle(2)
					if guide.Holder.Position.Y.Offset == last then
						break
					end
					last = guide.Holder.Position.Y.Offset
				end
				expect(count(c.sounds, "Bump") >= 1).toBe(true)
				expect(count(c.haptics, "listEnd") >= 1).toBe(true)
				-- ↑ qui remonte ne rebondit pas
				table.clear(c.sounds)
				table.clear(c.haptics)
				TvAudit.tick(c.h, 0.3)
				Gamepad.tap(c.h, Enum.KeyCode.DPadUp)
				c.h:settle(2)
				expect(count(c.sounds, "Bump")).toBe(0)
				expect(count(c.haptics, "listEnd")).toBe(0)
				clean(c)
			end
		)
	end)

	describe("PanelController › animations du GDD §9.2", function()
		it(
			"ouverture : UIScale 0,85 → 1 en 0,22 s (Back Out) ; fermeture : 1 → 0,9 en 0,12 s (Quad In)",
			function()
				local c = setup({})
				local Juice = TvAudit.mod(c.h, "UI.Juice")
				local calls = {}
				local tween = Juice.tween
				Juice.tween = function(inst, duration, props, style, direction, ...)
					if
						inst.Name == "JuiceScale"
						and inst.Parent
						and string.sub(inst.Parent.Name, 1, 6) == "Panel_"
					then
						table.insert(
							calls,
							{ scale = props.Scale, d = duration, style = style, dir = direction }
						)
					end
					return tween(inst, duration, props, style, direction, ...)
				end
				c.PC.open("Ranch")
				TvAudit.tick(c.h, 0.5)
				expect(#calls >= 1).toBe(true)
				local open = calls[1]
				expect(open.scale).toBe(1)
				expect(open.d).toBe(0.22)
				expect(open.style).toBe(Enum.EasingStyle.Back)
				expect(open.dir).toBe(Enum.EasingDirection.Out)
				table.clear(calls)
				c.PC.closeAll()
				c.h:settle(2)
				expect(#calls >= 1).toBe(true)
				local close = calls[1]
				expect(close.scale).toBe(0.9)
				expect(close.d).toBe(0.12)
				expect(close.style).toBe(Enum.EasingStyle.Quad)
				expect(close.dir).toBe(Enum.EasingDirection.In)
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.window("Ranch").Visible).toBe(false)
				clean(c)
			end
		)
	end)

	describe("PanelController › un seul UIScale par objet", function()
		it(
			"rail avec Grand Splorch prêt (pulsation), Objectifs à réclamer : jamais deux UIScale sur un objet",
			function()
				local rich = TvAudit.richProfile()
				rich.squishies.u1.z = 1e9
				local c = setup({ profile = rich })
				c.PC.toggleMenu()
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.entries()[1]).toBe("SplorchPreview")
				Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Objectives")
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Squishydex")
				TvAudit.tick(c.h, 0.5)
				local doubles = {}
				for _, d in c.h.localPlayer.PlayerGui:GetDescendants() do
					if d:IsA("GuiObject") then
						local n = 0
						for _, child in d:GetChildren() do
							if child.ClassName == "UIScale" then
								n += 1
							end
						end
						if n > 1 then
							table.insert(doubles, Layout.name(d))
						end
					end
				end
				table.sort(doubles)
				expect(table.concat(doubles, "\n")).toBe("")
				clean(c)
			end
		)
	end)
end
