--!nocheck
-- Layout_panels (paquet client-panels ; couche d, GDD §10.1, §10.3 ; docs/04 §14.1, §17.1 d) : le
-- parcours à 3 touches sur un profil riche en 1920 × 1080, 3840 × 2160 et 1280 × 720 (barre de Roblox
-- de 58 px comprise), en anglais puis en français : aucun chevauchement, aucun texte coupé ni sous
-- 28 px TV, rien hors de la zone sûre de 5 %, glyphes PlayStation ; puis le budget d'objets
-- d'interface (≤ 3 000 GuiObject avec tous les panneaux construits, docs/04 §18.3). Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")

local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	describe("Layout_panels › 3 résolutions × 2 langues", function()
		it("aucune faute de disposition sur aucun écran ; ≤ 3 000 objets d'interface", function()
			local profile = TvAudit.richProfile()
			profile.squishies.u20.z = 300000 -- Grand Splorch prêt
			local h = TvAudit.client({ before = TvAudit.enableShop, profile = profile })
			h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
			h:settle(1)
			local report = TvAudit.run(h, {
				resolutions = { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) },
				langs = { "en", "fr" },
			})
			expect(table.concat(report.issues, "\n")).toBe("")
			local n = 0
			for _ in report.screens do
				n += 1
			end
			expect(n >= 30).toBe(true)
			-- tous les panneaux sont construits à ce stade (une seule fois chacun)
			local gui = TvAudit.guiObjects(h)
			expect(gui <= 3000).toBe(true)
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)
	end)

	-- v2.0 (lot B2, étape 5) : même parcours avec l'instantané du serveur (interrupteur UpgradesScreen
	-- ouvert DANS le test) : rail v2.0, écran Améliorations et ses 4 onglets, HUD v2.0 ; budgets : écran
	-- ≤ 1 400 objets d'interface (règle 20, GDD §10.7.10), interface au chargement ≤ 3 000 (§12.9) ;
	-- interface entière, tous les panneaux construits : garde de non-régression ≤ 3 800 (journal B2-13,
	-- B2-49 : les 3 000 du §12.9 ne tiennent pas avec la v1.3 entière plus l'écran, décision demandée)
	describe("Layout_panels › v2.0 : écran Améliorations et rail v2.0 (lot B2)", function()
		it("aucune faute de disposition sur aucun écran, 3 résolutions × 2 langues ; budgets", function()
			local UpgradeScreen = require("../harness/UpgradeScreen")
			local S = UpgradeScreen.new(T.Harness)
			local profile = TvAudit.richProfile()
			profile.squishies.u20.z = 300000 -- Grand Splorch prêt
			profile.upgradeSnapshot = S.snap(1)
			local h = TvAudit.client({ before = TvAudit.enableShop, profile = profile })
			h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
			h:settle(1)
			-- au chargement : HUD v2.0, rail et écran Améliorations construits, aucun autre panneau ouvert
			local atLoad = TvAudit.guiObjects(h)
			local report = TvAudit.run(h, {
				resolutions = { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) },
				langs = { "en", "fr" },
				maxScreens = 120,
			})
			expect(table.concat(report.issues, "\n")).toBe("")
			local tabs = {}
			for id in report.screens do
				local tab = string.match(id, "^panel:Upgrades/(%w+)")
				if tab then
					tabs[tab] = true
				end
			end
			for _, tab in { "suggested", "ranch", "helpers", "workshop" } do
				expect({ tab = tab, reached = tabs[tab] == true }).toEqual({ tab = tab, reached = true })
			end
			local PC = TvAudit.mod(h, "UI.PanelController")
			local screen = 0
			for _, d in PC.window("Upgrades"):GetDescendants() do
				if d:IsA("GuiObject") then
					screen += 1
				end
			end
			local whole = TvAudit.guiObjects(h)
			print(
				string.format(
					"    objets d'interface : chargement %d, écran %d, tout construit %d",
					atLoad,
					screen + 1,
					whole
				)
			)
			expect(screen + 1 <= 1400).toBe(true)
			expect(atLoad <= 3000).toBe(true)
			expect(whole <= 3800).toBe(true)
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)
	end)
end
