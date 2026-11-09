--!nocheck
-- Upgrades_Budget (lot B2, étape 2 ; docs/04 §27.8 règle 20, §27.10 ; GDD v2.0 §10.7.10) : l'écran
-- Améliorations est construit UNE fois, au premier instantané valide (D2), puis seulement montré ou
-- caché :
--   * interrupteur coupé (aucune clé upgradeSnapshot) : aucune instance de l'écran, aucune intention ;
--   * après la première ouverture : objets d'interface (GuiObject) ≤ Layout.Upgrades.MaxInstances
--     (1 400, l'unité du GDD §10.7.10 et du budget de toute l'interface, §12.9 : 3 000 GuiObject) ;
--     instances (UICorner, UIStroke, UITextSizeConstraint comprises) relevées et bornées ;
--   * réouverture, changements d'onglet et de mode : 0 instance créée ;
--   * interface au chargement (HUD et écran, aucun autre panneau encore ouvert) ≤ 3 000 objets
--     d'interface ;
--   * interface entière, TOUS les panneaux construits (visite de tous les écrans) : relevé. Le budget
--     de 3 000 du §12.9 n'y est PAS tenu (journal B2-13, note croisée du lot B2) : les panneaux de la
--     v1.3 en prennent déjà ≈ 2 460 (Ranch ≈ 950, Squishydex ≈ 460, Diagnostics ≈ 250…) et l'écran
--     ≈ 1 200 (le GDD lui en donne 1 400). Garde contre une régression en attendant la décision :
--     l'écran n'ajoute que ses propres objets, et le total reste ≤ 3 800 (3 700 jusqu'à l'étape 3 ; le
--     HUD v2.0 et les glyphes dessinés de l'étape 4 en ajoutent 85, journal B2-49) ; ≤ 3 875 depuis le
--     lot B3, étape 1 (les 5 badges d'étoiles dessinés du Squishydex : + 75, journal B3-8).
-- Zéro trace.
local roblox = require("@lune/roblox")
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
				local whole = TvAudit.guiObjects(c.h)
				print(
					string.format(
						"    écran Améliorations : %d objets d'interface, %d instances ; interface au chargement : %d objets d'interface",
						gui,
						all,
						whole
					)
				)
				expect(gui <= S.Layout.Upgrades.MaxInstances).toBe(true)
				expect(whole <= 3000).toBe(true)
				-- relevé du lot B2 (garde contre une régression ; journal B2-19, B2-28) : 2 062 instances à l'étape 2,
				-- 2 106 à l'étape 3 (anneau du maintien : 25 ; glyphe de l'appareil du bandeau : 19)
				expect(all <= 2120).toBe(true)
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

	describe("Upgrades_Budget › interface entière, tous les panneaux construits", function()
		it(
			"relevé : l'écran n'ajoute que ses objets ; total ≤ 3 800 (3 000 du §12.9 non tenu, B2-13, B2-49)",
			function()
				local profile = TvAudit.richProfile()
				profile.squishies.u20.z = 300000 -- Grand Splorch prêt (aperçu construit)
				local c = S.client({ snap = S.snap(1), profile = profile, before = TvAudit.enableShop })
				c.h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
				c.h:settle(1)
				-- tous les écrans visités (chaque panneau construit une fois), puis l'écran ouvert
				TvAudit.run(c.h, { resolutions = { roblox.Vector2.new(1920, 1080) }, langs = { "en" } })
				S.open(c, "workshop")
				local screen = S.guiObjects(c)
				local whole = TvAudit.guiObjects(c.h)
				local parts = {}
				local safe = c.h.localPlayer.PlayerGui:FindFirstChild("Panels")
				safe = safe and safe:FindFirstChild("Safe")
				for _, w in if safe then safe:GetChildren() else {} do
					if
						string.sub(w.Name, 1, 6) == "Panel_" and not string.find(w.Name, "_Shadow", 1, true)
					then
						local n = 1
						for _, d in w:GetDescendants() do
							if d:IsA("GuiObject") then
								n += 1
							end
						end
						table.insert(parts, string.sub(w.Name, 7) .. " " .. n)
					end
				end
				table.sort(parts)
				print(
					string.format(
						"    interface entière : %d objets d'interface (écran %d, reste %d) ; panneaux : %s",
						whole,
						screen,
						whole - screen,
						table.concat(parts, ", ")
					)
				)
				-- chaque panneau de la v1.3 construit, l'écran compris
				expect(#parts >= 9).toBe(true)
				expect(screen <= S.Layout.Upgrades.MaxInstances).toBe(true)
				-- garde contre une régression en attendant la décision sur le budget de 3 000 (§12.9) :
				-- 3 681 à l'étape 3, 3 766 à l'étape 4 (HUD v2.0 et glyphes dessinés : + 85, journal B2-49) ;
				-- lot B3, étape 1 (D24, journal B3-8) : 3 841, + 75 = les 5 badges ★1-★5 de la fiche du
				-- Squishydex dessinés par UI/Text (étoile UI/Glyph de 15 objets, règle 18) : garde + 75
				expect(whole <= 3875).toBe(true)
				S.clean(c, expect)
			end
		)
	end)
end
