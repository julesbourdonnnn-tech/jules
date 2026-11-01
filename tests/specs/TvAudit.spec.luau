--!nocheck
-- TvAudit (paquet client-panels ; couche d, docs/04 §17.1 d) : chaque contrôle de l'audit télé voit
-- bien la faute qu'il doit voir sur une interface construite exprès (et rien sur une interface saine),
-- puis le parcours à 3 touches du vrai client (profil neuf) ne trouve aucune faute et rend toujours la
-- main au jeu. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum
local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function screen(h, name)
		local Instance = h.globals.Instance
		local gui = Instance.new("ScreenGui")
		gui.Name = name
		gui.IgnoreGuiInset = true
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.Parent = gui
		gui.Parent = h.localPlayer.PlayerGui
		return root
	end

	local function label(h, parent, name, text, size, pos)
		local Instance = h.globals.Instance
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Text = text
		l.TextScaled = true
		l.Size = size
		l.Position = pos
		local c = Instance.new("UITextSizeConstraint")
		c.MinTextSize = 28
		c.MaxTextSize = 40
		c.Parent = l
		l.Parent = parent
		return l
	end

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	describe("TvAudit › contrôles", function()
		it(
			"overlaps : deux textes qui se recouvrent sont vus ; un texte dans son cadre ne l'est pas",
			function()
				local h = TvAudit.client({})
				local root = screen(h, "Test")
				label(h, root, "A", "Hello", UDim2.fromOffset(300, 60), UDim2.fromOffset(400, 400))
				label(h, root, "B", "World", UDim2.fromOffset(300, 60), UDim2.fromOffset(500, 420))
				local issues = TvAudit.overlaps(h, root)
				expect(#issues).toBe(1)
				expect(issues[1]).toContain("chevauchement")
				root.B.Position = UDim2.fromOffset(900, 420)
				local inner =
					label(h, root.A, "Inner", "Hi", UDim2.fromOffset(100, 40), UDim2.fromOffset(10, 10))
				local _ = inner
				expect(#TvAudit.overlaps(h, root)).toBe(0)
				clean(h)
			end
		)

		it("clipped : un texte qui ne tient pas à 28 px est vu ; un texte court ne l'est pas", function()
			local h = TvAudit.client({})
			local root = screen(h, "Test")
			label(
				h,
				root,
				"Long",
				"This sentence is far too long for its tiny box",
				UDim2.fromOffset(200, 40),
				UDim2.fromOffset(400, 400)
			)
			label(h, root, "Short", "OK", UDim2.fromOffset(200, 40), UDim2.fromOffset(400, 500))
			local issues = TvAudit.clipped(h, root)
			expect(#issues).toBe(1)
			expect(issues[1]).toContain("Long")
			clean(h)
		end)

		it(
			"outsideSafe : hors des 5 % vu ; décor (Decorative) ignoré ; partie coupée par un cadre ignorée",
			function()
				local h = TvAudit.client({})
				local root = screen(h, "Test")
				label(h, root, "Edge", "Edge", UDim2.fromOffset(200, 40), UDim2.fromOffset(10, 10))
				local issues = TvAudit.outsideSafe(h, root)
				expect(#issues).toBe(1)
				root.Edge:SetAttribute("Decorative", true)
				expect(#TvAudit.outsideSafe(h, root)).toBe(0)
				-- rangée à moitié visible dans un cadre qui coupe : seule la partie affichée compte
				local Instance = h.globals.Instance
				local clip = Instance.new("Frame")
				clip.Name = "Clip"
				clip.ClipsDescendants = true
				clip.Size = UDim2.fromOffset(400, 300)
				clip.Position = UDim2.fromOffset(400, 600)
				clip.Parent = root
				label(h, clip, "Half", "Half", UDim2.fromOffset(200, 200), UDim2.fromOffset(0, 250))
				expect(#TvAudit.outsideSafe(h, root)).toBe(0)
				clean(h)
			end
		)

		it(
			"boundBehindWindow : une touche du jeu liée derrière une fenêtre est vue ; △ seul est permis",
			function()
				local h = TvAudit.client({})
				local CAS = h.game:GetService("ContextActionService")
				CAS:BindActionAtPriority("GamePress", function() end, false, 3000, Enum.KeyCode.ButtonX)
				CAS:BindActionAtPriority(
					"MenuToggle",
					function() end,
					false,
					3000,
					Enum.KeyCode.ButtonY,
					Enum.KeyCode.DPadDown
				)
				expect(#TvAudit.boundBehindWindow(h)).toBe(0) -- aucune fenêtre : le jeu peut lier
				TvAudit.mod(h, "UI.PanelController").toggleMenu()
				local issues = TvAudit.boundBehindWindow(h)
				expect(#issues).toBe(1)
				expect(issues[1]).toContain("GamePress")
				clean(h)
			end
		)

		it("selection : posée en jeu, vide ou hors de la fenêtre active : vue", function()
			local h = TvAudit.client({})
			local root = screen(h, "Test")
			local Instance = h.globals.Instance
			local b = Instance.new("TextButton")
			b.Text = "B"
			b.Size = UDim2.fromOffset(200, 80)
			b.Position = UDim2.fromOffset(400, 400)
			b.Parent = root
			expect(#TvAudit.selection(h)).toBe(0)
			h.game.GuiService.SelectedObject = b
			expect(TvAudit.selection(h)[1]).toContain("posée en jeu")
			local PC = TvAudit.mod(h, "UI.PanelController")
			PC.toggleMenu()
			expect(#TvAudit.selection(h)).toBe(0)
			h.game.GuiService.SelectedObject = b
			expect(TvAudit.selection(h)[1]).toContain("hors de la fenêtre")
			h.game.GuiService.SelectedObject = nil
			expect(TvAudit.selection(h)[1]).toContain("vide")
			clean(h)
		end)
	end)

	describe("TvAudit › parcours à 3 touches", function()
		it(
			"profil neuf : menu, panneaux et onglets atteints à la croix, ✕ et ○ ; aucune faute ; ○ rend la main",
			function()
				local h = TvAudit.client({})
				local report = TvAudit.walk(h)
				expect(table.concat(report.issues, "\n")).toBe("")
				expect(report.screens.menu).toBe(true)
				local panels = {}
				for id in report.screens do
					local p = string.match(id, "^panel:(%w+)")
					if p then
						panels[p] = true
					end
				end
				for _, p in { "Ranch", "Squishydex", "Objectives", "Leaderboards", "Settings" } do
					expect({ panel = p, reached = panels[p] == true }).toEqual({ panel = p, reached = true })
				end
				expect(TvAudit.mod(h, "UI.FocusGuard").anyOpen()).toBe(false)
				expect(TvAudit.screenId(h)).toBe("game")
				Layout.apply(h)
				clean(h)
			end
		)
	end)
end
