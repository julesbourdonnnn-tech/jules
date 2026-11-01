--!nocheck
-- Panels/OutfitPreview (paquet client-panels ; GDD §8.3, §5.4 ; docs/04 §13.6) : aperçu 3D (modèle de
-- Render/SquishyBuilder dans un ViewportFrame, rendu à la réserve à la fermeture), choix du squishy,
-- « Mettre » (EquipOutfit(tenue, uid)) si un exemplaire est libre, « Retirer » (EquipOutfit(tenue, nil)),
-- tenue non possédée refusée sans envoi, ○ revient au panneau d'origine. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup(profile)
		local h = TvAudit.client({ profile = profile })
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			OP = TvAudit.mod(h, "UI.Panels.OutfitPreview"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function body(c)
		return c.PC.window("OutfitPreview").Body
	end

	local function press(c, obj)
		TvAudit.tick(c.h, 0.5)
		c.h.game.GuiService.SelectedObject = obj
		Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
	end

	describe("Panels/OutfitPreview", function()
		it(
			"« Mettre » par défaut ; EquipOutfit(tenue, uid du plus gros) ; modèle 3D construit puis rendu",
			function()
				local c = setup({
					squishies = {
						big = TvAudit.squishy(5, { z = 900 }),
						small = TvAudit.squishy(2, { z = 10 }),
					},
					outfits = { owned = { sweater = 1 }, worn = {} },
				})
				c.PC.open("Ranch", "style")
				c.PC.open("OutfitPreview", "sweater")
				expect(c.PC.current()).toBe("OutfitPreview")
				expect(c.PC.isOpen("Ranch")).toBe(true) -- empilé sur son panneau d'origine
				local b = body(c)
				expect(c.h.game.GuiService.SelectedObject).toBe(b.Wear)
				local state = c.OP._state()
				expect(state.outfit).toBe("sweater")
				expect(state.uid).toBe("big")
				expect(state.model).toBe(true)
				expect(#b.Viewport.WorldModel:GetChildren() > 0).toBe(true)
				press(c, b.Wear)
				local args = TvAudit.sent(c.h, "EquipOutfit")[1]
				expect(args[1]).toBe("sweater")
				expect(args[2]).toBe("big")
				press(c, b.Next)
				expect(c.OP._state().uid).toBe("small")
				-- ○ : retour au panneau d'origine, modèle rendu à la réserve
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBe("Ranch")
				expect(c.OP._state().model).toBe(false)
				clean(c)
			end
		)

		it(
			"porteur : « Retirer » (EquipOutfit(tenue, nil)) ; tous les exemplaires portés : « Mettre » refusé",
			function()
				local c = setup({
					squishies = {
						a = TvAudit.squishy(5, { z = 900, o = "plopBib" }),
						b = TvAudit.squishy(2, { z = 10 }),
					},
					outfits = { owned = { plopBib = 1 }, worn = {} },
				})
				c.PC.open("Ranch", "style")
				c.PC.open("OutfitPreview", "plopBib")
				local b = body(c)
				expect(c.OP._state().uid).toBe("a") -- le porteur d'abord
				expect(b.Wear.Label.Text).toBe("No outfit")
				press(c, b.Wear)
				local args = TvAudit.sent(c.h, "EquipOutfit")[1]
				expect(args[1]).toBe("plopBib")
				expect(args[2]).toBeNil()
				press(c, b.Next)
				press(c, b.Wear) -- l'unique exemplaire est déjà porté par « a »
				expect(#TvAudit.sent(c.h, "EquipOutfit")).toBe(1)
				-- tenue jamais achetée, vue depuis la Boutique : refusée, « Acheter » caché tant que l'id vaut 0
				c.OP.setTab("jellyCrown")
				press(c, b.Wear)
				expect(#TvAudit.sent(c.h, "EquipOutfit")).toBe(1)
				expect(b.Buy.Visible).toBe(false)
				clean(c)
			end
		)

		it("tenue inconnue ou aucun squishy : aucune erreur", function()
			local c = setup({ squishies = {} })
			c.PC.open("Settings")
			c.PC.open("OutfitPreview", "chapeauInconnu")
			expect(c.OP._state().outfit).toBe("plopBib")
			expect(c.OP._state().uid).toBeNil()
			press(c, body(c).Wear)
			expect(#TvAudit.sent(c.h, "EquipOutfit")).toBe(0)
			clean(c)
		end)
	end)
end
