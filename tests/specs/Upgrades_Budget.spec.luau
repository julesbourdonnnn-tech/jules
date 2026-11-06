--!nocheck
-- Upgrades_Budget (lot B2, étape 2 ; docs/04 §27.8 règle 20, §27.10 ; GDD v2.0 §10.7.10) : l'écran
-- Améliorations est construit UNE fois, au premier instantané valide (D2), puis seulement montré ou
-- caché :
--   * interrupteur coupé (aucune clé upgradeSnapshot) : aucune instance de l'écran, aucune intention ;
--   * après la première ouverture : objets d'interface (GuiObject) ≤ Layout.Upgrades.MaxInstances
--     (1 400, l'unité du GDD §10.7.10 et du budget de toute l'interface, §12.9 : 3 000 GuiObject) ;
--     instances (UICorner, UIStroke, UITextSizeConstraint comprises) relevées et bornées ;
--   * réouverture, changements d'onglet et de mode : 0 instance créée ;
--   * l'interface entière (HUD, panneaux, écran) reste ≤ 3 000 objets d'interface.
-- Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	describe("Upgrades_Budget › interrupteur coupé", function()
		it("aucune instance de l'écran, aucune fenêtre, aucune intention v2.0", function()
			local c = S.client({})
			expect(c.PC.window("Upgrades")).toBeNil()
			expect(c.PC.available("Upgrades")).toBe(false)
			c.PC.open("Upgrades", "ranch")
			TvAudit.tick(c.h, 0.5)
			expect(c.PC.isOpen("Upgrades")).toBe(false)
			expect(c.PC.window("Upgrades")).toBeNil()
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)
	end)

	describe("Upgrades_Budget › construit une fois, au premier instantané", function()
		it(
			"≤ 1 400 objets d'interface après la première ouverture ; 0 instance créée ensuite",
			function()
				local c = S.client({ snap = S.snap(1) })
				-- construit pendant le chargement (premier instantané valide), avant toute ouverture
				expect(c.PC.window("Upgrades") ~= nil).toBe(true)
				S.open(c, nil)
				local gui = S.guiObjects(c)
				local all = S.count(c)
				print(
					string.format("    écran Améliorations : %d objets d'interface, %d instances", gui, all)
				)
				expect(gui <= S.Layout.Upgrades.MaxInstances).toBe(true)
				-- relevé du lot B2, étape 2 (garde contre une régression ; journal B2-n)
				expect(all <= 2075).toBe(true)
				local base = #c.h.localPlayer.PlayerGui:GetDescendants()
				for _, tab in { "ranch", "helpers", "workshop", "suggested" } do
					c.Up.setTab(tab)
					TvAudit.tick(c.h, 0.2)
					c.Up.cycleMode()
					TvAudit.tick(c.h, 0.2)
				end
				c.PC.closeAll()
				TvAudit.tick(c.h, 1)
				for _ = 1, 3 do
					S.open(c, "workshop")
					c.PC.closeAll()
					TvAudit.tick(c.h, 1)
				end
				expect(#c.h.localPlayer.PlayerGui:GetDescendants()).toBe(base)
				expect(TvAudit.guiObjects(c.h) <= 3000).toBe(true)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)
	end)
end
