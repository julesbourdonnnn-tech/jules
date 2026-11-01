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
end
