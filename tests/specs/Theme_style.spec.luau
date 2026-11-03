--!nocheck
-- Theme_style (lot B1, étape 2 ; GDD v2.0 §10.1 « Style », critique m21 ; docs/04 §27.10 B1 « harnais
-- UIShadow et dégradé radial (absents → repli) ») : l'ombre `UIShadow` et le dégradé radial de
-- `UIGradient`, simulés par le harnais (MockInstance.styleFeatures, ApiAudit, EngineProps) :
--   * présents : la vraie ombre (noire, 50 %, 6 px vers le bas) et Type = « Radial », API vérifiée ;
--   * absents (ou un nom de propriété différent sur l'appareil) : REPLI À PLAT sous pcall, compté,
--     jamais une erreur : un Frame frère derrière la cible, 6 px plus bas, à 50 %, qui la suit (taille,
--     place, visibilité, parent, destruction) ; le dégradé reste linéaire.
-- Zéro trace : aucune erreur ni avertissement.

local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local MockInstance = require("../harness/MockInstance")
local EngineProps = require("../harness/EngineProps")
local ApiAudit = require("../harness/ApiAudit")

local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup(shadow: boolean, radial: boolean)
		MockInstance.styleFeatures.UIShadow = shadow
		MockInstance.styleFeatures.RadialGradient = radial
		local h = TvAudit.client({})
		local c = {
			h = h,
			Theme = TvAudit.mod(h, "UI.Theme"),
			Widgets = TvAudit.mod(h, "UI.Panels.Widgets"),
			Root = TvAudit.mod(h, "UI.Root"),
		}
		return c
	end

	local function done(c)
		MockInstance.styleFeatures.UIShadow = false
		MockInstance.styleFeatures.RadialGradient = false
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	describe("Theme › ombre et dégradé radial : présents dans le moteur", function()
		it(
			"UIShadow posée sur le panneau, noire à 50 %, 6 px vers le bas ; aucune ombre de repli",
			function()
				local c = setup(true, true)
				local before = c.Theme.styleFallbacks()
				ApiAudit.start()
				local panel = c.Widgets.frame({
					parent = c.Root.safe("StyleTest", 20),
					name = "Card",
					size = UDim2.fromOffset(400, 300),
					shadow = true,
				})
				local issues = ApiAudit.stop()
				expect(table.concat(issues, "\n")).toBe("")
				local shadow = panel:FindFirstChildOfClass("UIShadow")
				expect(shadow ~= nil).toBe(true)
				expect(shadow.Transparency).toBe(0.5)
				expect(shadow.Offset).toBe(Vector2.new(0, 6))
				expect(shadow.Color).toBe(roblox.Color3.new(0, 0, 0))
				expect(panel.Parent:FindFirstChild("Card_Shadow")).toBeNil()
				expect(c.Theme.styleFallbacks()).toBe(before)
				-- valeur par défaut du moteur connue des outils hors jeu
				expect(EngineProps.NEWER_DEFAULTS.UIShadow.Transparency).toBe(0.5)
				done(c)
			end
		)

		it("dégradé radial : Type = Radial, API vérifiée, aucun repli", function()
			local c = setup(true, true)
			local before = c.Theme.styleFallbacks()
			ApiAudit.start()
			local g = c.h.globals.Instance.new("UIGradient")
			local ok = c.Theme.radial(g)
			local issues = ApiAudit.stop()
			expect(table.concat(issues, "\n")).toBe("")
			expect(ok).toBe(true)
			expect(g.Type).toBe("Radial")
			expect(c.Theme.styleFallbacks()).toBe(before)
			done(c)
		end)
	end)

	describe("Theme › ombre et dégradé radial : absents du moteur (repli à plat)", function()
		it(
			"ombre de repli : Frame frère 6 px plus bas, 50 %, derrière la cible, compté, sans erreur",
			function()
				local c = setup(false, false)
				local counted = {}
				c.Theme.onStyleFallback = function(kind)
					table.insert(counted, kind)
				end
				local before = c.Theme.styleFallbacks()
				local safe = c.Root.safe("StyleTest", 20)
				ApiAudit.start()
				local panel = c.Widgets.frame({
					parent = safe,
					name = "Card",
					size = UDim2.fromOffset(400, 300),
					position = UDim2.fromOffset(100, 50),
					zIndex = 5,
					shadow = true,
				})
				local issues = ApiAudit.stop()
				expect(table.concat(issues, "\n")).toBe("")
				expect(panel:FindFirstChildOfClass("UIShadow")).toBeNil()
				local shadow = safe:FindFirstChild("Card_Shadow")
				expect(shadow ~= nil).toBe(true)
				expect(shadow.Size).toBe(panel.Size)
				expect(shadow.Position).toBe(UDim2.fromOffset(100, 56))
				expect(shadow.BackgroundTransparency).toBe(0.5)
				expect(shadow.ZIndex).toBe(4)
				expect(shadow:GetAttribute("Decorative")).toBe(true)
				expect(shadow.Selectable).toBe(false)
				expect(shadow:FindFirstChildOfClass("UICorner").CornerRadius).toBe(
					panel:FindFirstChildOfClass("UICorner").CornerRadius
				)
				expect(c.Theme.styleFallbacks()).toBe(before + 1)
				expect(counted).toEqual({ "shadow" })
				-- elle suit la cible : taille, place, visibilité, destruction
				panel.Size = UDim2.fromOffset(500, 320)
				panel.Position = UDim2.fromOffset(10, 20)
				panel.Visible = false
				expect(shadow.Size).toBe(UDim2.fromOffset(500, 320))
				expect(shadow.Position).toBe(UDim2.fromOffset(10, 26))
				expect(shadow.Visible).toBe(false)
				panel:Destroy()
				expect(shadow.Parent).toBeNil()
				c.Theme.onStyleFallback = nil
				done(c)
			end
		)

		it("cible pas encore parentée : l'ombre la rejoint à son parent", function()
			local c = setup(false, false)
			local panel = c.Widgets.frame({ name = "Late", size = UDim2.fromOffset(200, 100), shadow = true })
			local safe = c.Root.safe("StyleTest2", 20)
			panel.Parent = safe
			local shadow = safe:FindFirstChild("Late_Shadow")
			expect(shadow ~= nil).toBe(true)
			expect(shadow.Parent).toBe(safe)
			done(c)
		end)

		it(
			"cible rangée par un UIListLayout : aucune ombre de repli (elle serait un élément de la liste)",
			function()
				local c = setup(false, false)
				local safe = c.Root.safe("StyleTest4", 20)
				local list = c.h.globals.Instance.new("Frame")
				list.Parent = safe
				c.h.globals.Instance.new("UIListLayout").Parent = list
				local before = c.Theme.styleFallbacks()
				local card = c.Widgets.frame({
					parent = list,
					name = "Card",
					size = UDim2.fromOffset(200, 100),
					shadow = true,
				})
				expect(list:FindFirstChild("Card_Shadow")).toBeNil()
				expect(card.Parent).toBe(list)
				expect(c.Theme.styleFallbacks()).toBe(before + 1)
				done(c)
			end
		)

		it("dégradé radial absent : faux, dégradé linéaire inchangé, compté, sans erreur", function()
			local c = setup(false, false)
			local before = c.Theme.styleFallbacks()
			local g = c.h.globals.Instance.new("UIGradient")
			g.Rotation = 90
			expect(c.Theme.radial(g)).toBe(false)
			expect(g.Rotation).toBe(90)
			expect(c.Theme.styleFallbacks()).toBe(before + 1)
			-- appels hostiles : jamais une erreur
			expect(c.Theme.radial(nil)).toBe(false)
			local none, real = c.Theme.shadow(nil)
			expect(none).toBeNil()
			expect(real).toBe(false)
			done(c)
		end)

		it(
			"UIShadow présente mais un nom de propriété différent sur l'appareil : repli, sans erreur",
			function()
				local c = setup(true, false)
				local before = c.Theme.styleFallbacks()
				-- l'appareil ne connaît pas BlurRadius (nom supposé) : l'écriture lève
				local mt = getmetatable(c.h.globals.Instance.new("Frame"))
				local set = mt.__newindex
				mt.__newindex = function(self, key, value)
					if key == "BlurRadius" then
						error("BlurRadius is not a valid member of UIShadow")
					end
					return set(self, key, value)
				end
				local safe = c.Root.safe("StyleTest3", 20)
				local panel = c.Widgets.frame({
					parent = safe,
					name = "Odd",
					size = UDim2.fromOffset(200, 100),
					shadow = true,
				})
				mt.__newindex = set
				expect(panel:FindFirstChildOfClass("UIShadow")).toBeNil()
				expect(safe:FindFirstChild("Odd_Shadow") ~= nil).toBe(true)
				expect(c.Theme.styleFallbacks()).toBe(before + 1)
				done(c)
			end
		)
	end)
	describe("Harnais › compteur d'instances (règle 20 : budget par panneau, réouverture)", function()
		it("Instance.new et Clone comptés ; total des descendants d'une racine", function()
			local c = setup(false, false)
			local before = MockInstance.created()
			local f = c.Widgets.frame({ name = "Count", size = UDim2.fromOffset(100, 100) })
			-- cadre + UICorner + UIStroke
			expect(MockInstance.created() - before).toBe(3)
			expect(MockInstance.descendantCount(f)).toBe(2)
			local copy = f:Clone()
			expect(MockInstance.created() - before).toBe(6)
			expect(MockInstance.descendantCount(copy)).toBe(2)
			expect(MockInstance.descendantCount(nil)).toBe(0)
			done(c)
		end)
	end)
end
