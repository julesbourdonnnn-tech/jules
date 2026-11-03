--!nocheck
-- FocusGuard (découpe) — lot B1, étape 2 (GDD v2.0 §10.1 « cadre de sélection dessiné à l'intérieur
-- de l'élément », §10.6 règle 7 ; règle 14 du §10.8 ; docs/04 §27.8, N11) :
--   * le cadre de focus (FocusGuard.selectionImage) est dessiné À L'INTÉRIEUR de l'élément : trait blanc
--     de 6 px et liseré sombre de 2 px, aucun débord (FocusGuard.cursorOutset ≤ 0), une seule instance
--     jamais parentée, respiration douce (fixe en Mouvement réduit) ;
--   * chaque bouton sélectionnable du client (HUD, menu, panneaux, cartes) le porte ;
--   * dans CHAQUE panneau et CHAQUE onglet, à tv720, tv1080 et tv2160 : pour CHAQUE élément
--     sélectionnable, une fois sélectionné, le rectangle du cadre de focus est dans le rectangle de
--     découpe de chaque ancêtre qui découpe (ClipsDescendants, ScrollingFrame, CanvasGroup) ; un
--     élément d'une liste, d'une rangée ou d'un rail ne grossit jamais (N11) ;
--   * un élément sélectionné qui dépasse d'un ScrollingFrame y est ramené entier (FocusGuard).
-- Zéro trace : aucune erreur ni avertissement.

local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function inside(a, b): boolean
		return a.x >= b.x - 0.5
			and a.y >= b.y - 0.5
			and a.x + a.w <= b.x + b.w + 0.5
			and a.y + a.h <= b.y + b.h + 0.5
	end

	-- Ancêtres qui découpent (même règle que le moteur et que FocusGuard.clippers)
	local function clippers(obj)
		local out = {}
		local cur = obj.Parent
		while cur ~= nil and not cur:IsA("LayerCollector") do
			if
				cur:IsA("GuiObject")
				and (cur.ClipsDescendants or cur:IsA("ScrollingFrame") or cur:IsA("CanvasGroup"))
			then
				table.insert(out, cur)
			end
			cur = cur.Parent
		end
		return out
	end

	describe("FocusGuard (découpe) › cadre de focus dessiné à l'intérieur", function()
		it("trait blanc de 6 px, liseré sombre de 2 px, aucun débord, une seule instance", function()
			local h = TvAudit.client({})
			local FG = TvAudit.mod(h, "UI.FocusGuard")
			ApiAudit.start()
			local image = FG.selectionImage()
			local button = h.globals.Instance.new("TextButton")
			button.SelectionImageObject = image
			local issues = ApiAudit.stop()
			expect(table.concat(issues, "\n")).toBe("")
			expect(FG.selectionImage()).toBe(image)
			expect(image.Parent).toBeNil()
			local stroke = image:FindFirstChildOfClass("UIStroke")
			expect(stroke.Thickness).toBe(6)
			expect(stroke.Color).toBe(roblox.Color3.fromRGB(255, 255, 255))
			local edgeStroke = image.Edge:FindFirstChildOfClass("UIStroke")
			expect(edgeStroke.Thickness).toBe(2)
			local lum = 0.2126 * edgeStroke.Color.R
				+ 0.7152 * edgeStroke.Color.G
				+ 0.0722 * edgeStroke.Color.B
			expect(lum < 0.15).toBe(true)
			-- cadre blanc de 2 à 8 px dedans, liseré de 0 à 2 px dedans : bord extérieur au bord de l'élément
			expect(image.Size).toBe(UDim2.new(1, -16, 1, -16))
			expect(image.Edge.Size).toBe(UDim2.new(1, 12, 1, 12))
			expect(FG.cursorOutset(button)).toBe(0)
			-- l'ancien curseur de UI/Root débordait de 12 px (4 + 6 + 2) : la mesure le voit
			local Root = TvAudit.mod(h, "UI.Root")
			button.SelectionImageObject = Root.selectionImage()
			expect(FG.cursorOutset(button)).toBe(12)
			expect(table.concat(h.errors, "\n")).toBe("")
		end)

		it(
			"respire quand une sélection existe (0 à 0,35) ; plein sans sélection et en Mouvement réduit",
			function()
				local h = TvAudit.client({})
				local FG = TvAudit.mod(h, "UI.FocusGuard")
				local Juice = TvAudit.mod(h, "UI.Juice")
				local image = FG.selectionImage()
				local stroke = image:FindFirstChildOfClass("UIStroke")
				h.game.GuiService.SelectedObject = nil
				h:step(1 / 30, 10)
				expect(stroke.Transparency).toBe(0)
				local button = h.globals.Instance.new("TextButton")
				button.SelectionImageObject = image
				h.game.GuiService.SelectedObject = button
				local low, high = math.huge, -math.huge
				for _ = 1, 60 do
					h:step(1 / 30, 1)
					low = math.min(low, stroke.Transparency)
					high = math.max(high, stroke.Transparency)
				end
				expect(low >= 0).toBe(true)
				expect(high <= 0.35 + 1e-6).toBe(true)
				expect(high - low > 0.2).toBe(true)
				Juice.forceReducedMotion = true
				h:step(1 / 30, 3)
				expect(stroke.Transparency).toBe(0)
				Juice.forceReducedMotion = false
				h.game.GuiService.SelectedObject = nil
				h:step(1 / 30, 1)
				expect(stroke.Transparency).toBe(0)
			end
		)

		it(
			"ScrollingFrame : un élément sélectionné qui dépasse est ramené entier dans la découpe",
			function()
				local h = TvAudit.client({})
				local FG = TvAudit.mod(h, "UI.FocusGuard")
				local Root = TvAudit.mod(h, "UI.Root")
				local Instance = h.globals.Instance
				local safe = Root.safe("ClipTest", 30)
				local sf = Instance.new("ScrollingFrame")
				sf.Name = "List"
				sf.Size = UDim2.fromOffset(600, 400)
				sf.Position = UDim2.fromOffset(200, 200)
				sf.CanvasSize = UDim2.fromOffset(600, 1400)
				sf.Parent = safe
				local buttons = {}
				for i = 1, 12 do
					local b = Instance.new("TextButton")
					b.Name = "B" .. i
					b.Size = UDim2.fromOffset(500, 96)
					b.Position = UDim2.fromOffset(50, (i - 1) * 112 + 8)
					b.SelectionImageObject = FG.selectionImage()
					b.Parent = sf
					buttons[i] = b
				end
				for _, i in { 4, 9, 12, 2, 1 } do
					Layout.apply(h)
					h.game.GuiService.SelectedObject = buttons[i]
					h:settle(1)
					Layout.apply(h)
					FG.keepInside(buttons[i])
					Layout.apply(h)
					local r = Layout.rect(buttons[i])
					local o = FG.cursorOutset(buttons[i]) * r.k
					local foot = { x = r.x - o, y = r.y - o, w = r.w + 2 * o, h = r.h + 2 * o }
					expect({ i = i, inside = inside(foot, Layout.rect(sf)) }).toEqual({ i = i, inside = true })
				end
				expect(table.concat(h.errors, "\n")).toBe("")
			end
		)
	end)

	-- Chaque panneau, chaque onglet, chaque élément sélectionnable, à trois résolutions
	for _, pid in { "tv1080", "tv720", "tv2160" } do
		describe(
			"FocusGuard (découpe) › chaque élément sélectionné de chaque panneau › " .. pid,
			function()
				local ok, c = pcall(Screens.boot, Harness, Screens.profileById(pid), "fr", "mid")
				if not ok then
					it("démarrage du client", function()
						error(c)
					end)
					return
				end
				local FG = c.FocusGuard
				local image = FG.selectionImage()
				local clipBad, cursorBad, growBad = {}, {}, {}
				local checked = 0
				for _, entry in Screens.PANEL_TABS do
					local panel, tabs = entry[1], entry[2]
					for _, tab in tabs do
						local where = panel .. (if tab ~= "" then " › " .. tab else "")
						Screens.open(c, panel, if tab ~= "" then tab else nil)
						Screens.flushAll(c)
						Screens.layout(c)
						local win = c.PC.window(panel)
						local list = {}
						for _, obj in (win and win:GetDescendants() or {}) do
							if obj:IsA("GuiButton") and obj.Selectable and Layout.visible(obj) then
								table.insert(list, obj)
							end
						end
						for _, obj in list do
							if obj.Parent ~= nil and Layout.visible(obj) then
								c.h.game.GuiService.SelectedObject = obj
								Screens.frames(c, 8, 0.05)
								Screens.layout(c)
								if c.h.game.GuiService.SelectedObject == obj and Layout.visible(obj) then
									checked += 1
									if obj.SelectionImageObject ~= image then
										table.insert(cursorBad, where .. " : " .. Layout.name(obj))
									end
									local r = Layout.rect(obj)
									local o = math.max(0, FG.cursorOutset(obj)) * r.k
									local foot =
										{ x = r.x - o, y = r.y - o, w = r.w + 2 * o, h = r.h + 2 * o }
									for _, clip in clippers(obj) do
										local cr = Layout.rect(clip)
										if cr and not inside(foot, cr) then
											table.insert(
												clipBad,
												string.format(
													"%s : %s tranché par %s",
													where,
													Layout.name(obj),
													Layout.name(clip)
												)
											)
										end
									end
									-- N11 : un élément dans une liste, une rangée ou un cadre qui découpe ne grossit pas
									local scale = obj:FindFirstChild("JuiceScale")
									local listed = false
									for _, child in obj.Parent:GetChildren() do
										if child:IsA("UIListLayout") or child:IsA("UIGridLayout") then
											listed = true
										end
									end
									if
										(listed or #clippers(obj) > 0)
										and scale
										and math.abs(scale.Scale - 1) > 1e-3
										and obj:GetAttribute("Attention") ~= true
									then
										table.insert(
											growBad,
											string.format(
												"%s : %s grossi à %.3f",
												where,
												Layout.name(obj),
												scale.Scale
											)
										)
									end
								end
							end
						end
					end
				end
				-- menu (rail) : chaque entrée sélectionnée, cadre dans la découpe, jamais grossie (N11)
				Screens.closeAll(c)
				Screens.flushAll(c)
				pcall(c.PC.toggleMenu)
				Screens.frames(c, 8, 0.05)
				Screens.layout(c)
				local playerGui = c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
				local menu = playerGui:FindFirstChild("Menu")
				local railCount = 0
				for _, obj in (menu and menu:GetDescendants() or {}) do
					if obj:IsA("GuiButton") and obj.Selectable and Layout.visible(obj) then
						c.h.game.GuiService.SelectedObject = obj
						Screens.frames(c, 8, 0.05)
						Screens.layout(c)
						railCount += 1
						checked += 1
						if obj.SelectionImageObject ~= image then
							table.insert(cursorBad, "menu : " .. Layout.name(obj))
						end
						local scale = obj:FindFirstChild("JuiceScale")
						if
							scale
							and math.abs(scale.Scale - 1) > 1e-3
							and obj:GetAttribute("Attention") ~= true
						then
							table.insert(
								growBad,
								string.format("menu : %s grossi à %.3f", Layout.name(obj), scale.Scale)
							)
						end
						local r = Layout.rect(obj)
						local o = math.max(0, FG.cursorOutset(obj)) * r.k
						local foot = { x = r.x - o, y = r.y - o, w = r.w + 2 * o, h = r.h + 2 * o }
						for _, clip in clippers(obj) do
							local cr = Layout.rect(clip)
							if cr and not inside(foot, cr) then
								table.insert(
									clipBad,
									"menu : " .. Layout.name(obj) .. " tranché par " .. Layout.name(clip)
								)
							end
						end
					end
				end
				Screens.closeAll(c)
				it("menu : au moins 5 entrées du rail vérifiées", function()
					expect(railCount >= 5).toBe(true)
				end)
				it("au moins 150 éléments vérifiés", function()
					expect(checked >= 150).toBe(true)
				end)
				it(
					"chaque élément porte le cadre de focus dessiné à l'intérieur (FocusGuard)",
					function()
						expect(table.concat(cursorBad, "\n")).toBe("")
					end
				)
				it("le cadre de focus est dans la découpe de chaque ancêtre qui découpe", function()
					expect(table.concat(clipBad, "\n")).toBe("")
				end)
				it(
					"aucun élément d'une liste, d'une rangée ou d'un cadre qui découpe ne grossit",
					function()
						expect(table.concat(growBad, "\n")).toBe("")
					end
				)
				it("zéro trace", function()
					expect(table.concat(c.h.errors, "\n")).toBe("")
					expect(table.concat(c.h:warnings(), "\n")).toBe("")
				end)
				Harness.disposeAll()
			end
		)
	end
end
