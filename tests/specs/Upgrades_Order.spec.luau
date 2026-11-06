--!nocheck
-- Upgrades_Order (lot B2, étape 2 ; docs/04 §27.8 règle 1 « jamais retrié », règle 12 ; GDD v2.0
-- §10.7.4, §10.7.5) : 1 000 réponses UpgradeResult tirées au hasard (graine fixe) écran ouvert :
--   * l'ordre des lignes de chaque onglet ne change pas (positions identiques) ;
--   * la sélection reste où elle est (ligne ou carte) ;
--   * aucune carte du Conseillé ne change de famille (choisies à l'ouverture et au retour sur
--     l'onglet seulement) ; à la réouverture, elles sont choisies de nouveau.
-- Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")
local UpgradeRandom = require("../harness/UpgradeRandom")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	local function positions(c)
		local out = {}
		for _, tab in { "ranch", "helpers", "workshop" } do
			for i, id in c.Up._shown(tab) do
				local p = c.Up._row(id).Position
				out[tab .. "#" .. i] = id .. "@" .. p.X.Offset .. "," .. p.Y.Offset
			end
		end
		return out
	end

	local function feed(c, r, n, version)
		for _ = 1, n do
			version += 1
			local snap = S.snap(version, UpgradeRandom.edit(r, S.Upgrades))
			c.h:fireClient(
				"ReplicatedStorage.Remotes.UpgradeResult",
				UpgradeRandom.result(r, S.UpgradeMath, snap)
			)
		end
		c.h:settle(2)
		TvAudit.tick(c.h, 0.5)
		return version
	end

	describe("Upgrades_Order › 1 000 réponses écran ouvert", function()
		it("Conseillé : la carte sélectionnée et les 3 familles ne bougent pas", function()
			local c = S.client({ snap = S.snap(1) })
			S.open(c, "suggested")
			local card = c.Up._card(2)
			c.h.game.GuiService.SelectedObject = card
			TvAudit.tick(c.h, 0.2)
			local families = c.Up._cards()
			local order = positions(c)
			feed(c, UpgradeRandom.rng(7), 1000, 1)
			expect(c.h.game.GuiService.SelectedObject).toBe(card)
			expect(c.Up._cards()).toEqual(families)
			expect(positions(c)).toEqual(order)
			-- la carte garde sa famille : même identifiant (FocusId) qu'à l'ouverture
			expect(card:GetAttribute("FocusId")).toBe(families[2])
			S.clean(c, expect)
		end)

		it("Ranch et Atelier : ordre fixe, sélection en place, étoiles « Conseillé » figées", function()
			local c = S.client({ snap = S.snap(1) })
			for _, tab in { "ranch", "workshop" } do
				S.open(c, tab)
				local shown = c.Up._shown(tab)
				local row = c.Up._row(shown[3])
				c.h.game.GuiService.SelectedObject = row
				TvAudit.tick(c.h, 0.2)
				local order = positions(c)
				local advised = c.Up._advised()
				feed(c, UpgradeRandom.rng(if tab == "ranch" then 11 else 13), 500, c.US.current().version)
				expect(c.h.game.GuiService.SelectedObject).toBe(row)
				expect(positions(c)).toEqual(order)
				expect(c.Up._advised()).toEqual(advised)
				expect(c.Up._shown(tab)).toEqual(shown)
			end
			S.clean(c, expect)
		end)
	end)
end
