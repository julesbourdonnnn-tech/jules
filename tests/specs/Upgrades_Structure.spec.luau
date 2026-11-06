--!nocheck
-- Upgrades_Structure (lot B2, étape 2 ; docs/04 §27.8 règles 2 et 20, §27.10 ; GDD v2.0 §10.7.5) :
-- l'écran Améliorations est une structure FIXE : 30 lignes (une par identifiant, toute la session) et
-- 3 cartes, construites une fois ; rien n'est créé ni détruit écran ouvert.
--   * 1 000 réponses UpgradeResult valides (achats et refus tirés au hasard, graine fixe) sur chaque
--     onglet et dans chaque mode : même nombre d'instances, mêmes objets (aucune ligne recréée) ;
--   * une réouverture crée 0 instance ;
--   * chaque ligne garde son identifiant (FocusId) toute la session.
-- Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")
local UpgradeRandom = require("../harness/UpgradeRandom")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	describe("Upgrades_Structure › construction unique", function()
		it(
			"1 000 réponses : même nombre d'instances, mêmes objets ; réouverture : 0 instance créée",
			function()
				local c = S.client({ snap = S.snap(1) })
				S.open(c, "suggested")
				local gui = c.h.localPlayer.PlayerGui
				-- lignes et cartes : un objet par identifiant, toute la session
				local objects = {}
				for _, tab in { "ranch", "helpers", "workshop" } do
					for _, id in c.Up._shown(tab) do
						objects[id] = c.Up._row(id)
					end
				end
				local cards = { c.Up._card(1), c.Up._card(2), c.Up._card(3) }
				local base = #gui:GetDescendants()
				local r = UpgradeRandom.rng(20261106)
				local version = 1
				local tabs = { "suggested", "ranch", "helpers", "workshop" }
				for i = 1, 1000 do
					version += 1
					local snap = S.snap(version, UpgradeRandom.edit(r, S.Upgrades))
					c.h:fireClient(
						"ReplicatedStorage.Remotes.UpgradeResult",
						UpgradeRandom.result(r, S.UpgradeMath, snap)
					)
					if i % 50 == 0 then
						c.Up.setTab(tabs[(i / 50) % 4 + 1])
						c.Up.cycleMode()
						TvAudit.tick(c.h, 0.1)
						expect(#gui:GetDescendants()).toBe(base)
					end
				end
				c.h:settle(2)
				TvAudit.tick(c.h, 1)
				expect(c.US.current().version).toBe(version)
				expect(#gui:GetDescendants()).toBe(base)
				for id, obj in objects do
					expect(c.Up._row(id)).toBe(obj)
					expect(obj:GetAttribute("FocusId")).toBe(id)
				end
				for i, card in cards do
					expect(c.Up._card(i)).toBe(card)
				end
				-- réouverture (chaque onglet) : 0 instance créée
				for _, tab in tabs do
					c.PC.closeAll()
					TvAudit.tick(c.h, 1)
					S.open(c, tab)
					expect(#gui:GetDescendants()).toBe(base)
				end
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)
	end)
end
