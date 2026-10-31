--!nocheck
-- QA round 4 — fixer r4-ui-1, UI/Root.selectionImage : le curseur manette avait le même or que les
-- contours « choisi / marqué » de Widgets.highlight (langue choisie, cosmétique équipé, Nebbies
-- marqués, quête réclamable, carte de quête, Supernova payable) : à 3 m, un anneau doré de 4 px
-- à côté d'un anneau doré de 3 px ne se distinguait plus. Le curseur a désormais sa propre couleur
-- (blanc), un trait plus épais (6 px), un liseré sombre extérieur (cartes claires) et respire
-- doucement (fixe en Mouvement réduit).
local roblox = require("@lune/roblox")
local ApiAudit = require("../harness/ApiAudit")

local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

	local function setup()
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local c = {
			h = h,
			Root = h:require(CLIENT .. "UI.Root"),
			Theme = h:require(CLIENT .. "UI.Theme"),
			Juice = h:require(CLIENT .. "UI.Juice"),
			Widgets = h:require(CLIENT .. "UI.Panels.Widgets"),
		}
		return c
	end

	local function same(a, b)
		return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
	end

	describe("Fix r4-ui-1 › curseur manette distinct des contours d'état", function()
		it(
			"couleur et forme propres : ni l'or ni le cyan des contours, plus épais, liseré sombre",
			function()
				local c = setup()
				ApiAudit.start()
				local image = c.Root.selectionImage()
				local button = c.h.globals.Instance.new("TextButton")
				button.SelectionImageObject = image
				local issues = ApiAudit.stop()
				expect(table.concat(issues, "\n")).toBe("")
				local stroke = image:FindFirstChildOfClass("UIStroke")
				-- jamais une couleur de Widgets.highlight
				for _, color in { c.Theme.Colors.Gold, c.Widgets.CYAN, c.Theme.Colors.Danger } do
					expect(same(stroke.Color, color)).toBe(false)
				end
				-- plus épais que le contour d'état (3 px)
				expect(stroke.Thickness > 3).toBe(true)
				expect(stroke.Thickness).toBe(6)
				-- liseré sombre juste à l'extérieur du trait (cadre imbriqué de 6 px de plus par côté)
				local edge = image:FindFirstChild("Edge")
				expect(edge ~= nil).toBe(true)
				expect(edge.Size).toBe(UDim2.new(1, 12, 1, 12))
				local edgeStroke = edge:FindFirstChildOfClass("UIStroke")
				expect(edgeStroke.Thickness).toBe(2)
				local luminance = 0.2126 * edgeStroke.Color.R
					+ 0.7152 * edgeStroke.Color.G
					+ 0.0722 * edgeStroke.Color.B
				expect(luminance < 0.15).toBe(true)
				-- toujours une seule instance, jamais parentée
				expect(c.Root.selectionImage()).toBe(image)
				expect(image.Parent).toBeNil()
			end
		)

		it(
			"respiration douce quand une sélection existe ; fixe sans sélection et en Mouvement réduit",
			function()
				local c = setup()
				local image = c.Root.selectionImage()
				local stroke = image:FindFirstChildOfClass("UIStroke")
				-- sans sélection : trait plein
				c.h:step(1 / 30, 20)
				expect(stroke.Transparency).toBe(0)
				-- sélection : la transparence varie dans [0 ; 0,35]
				local button = c.h.globals.Instance.new("TextButton")
				button.SelectionImageObject = image
				c.h.game.GuiService.SelectedObject = button
				local low, high = math.huge, -math.huge
				for _ = 1, 60 do
					c.h:step(1 / 30, 1)
					low = math.min(low, stroke.Transparency)
					high = math.max(high, stroke.Transparency)
				end
				expect(low >= 0).toBe(true)
				expect(high <= 0.35 + 1e-6).toBe(true)
				expect(high - low > 0.2).toBe(true)
				-- Mouvement réduit : plein, immobile
				c.Juice.forceReducedMotion = true
				c.h:step(1 / 30, 1)
				expect(stroke.Transparency).toBe(0)
				c.h:step(1 / 30, 10)
				expect(stroke.Transparency).toBe(0)
				-- de retour : respire de nouveau ; sélection effacée : plein
				c.Juice.forceReducedMotion = false
				c.h:step(1 / 30, 8)
				expect(stroke.Transparency > 0).toBe(true)
				c.h.game.GuiService.SelectedObject = nil
				c.h:step(1 / 30, 1)
				expect(stroke.Transparency).toBe(0)
				expect(#c.h.errors).toBe(0)
			end
		)
	end)
end
