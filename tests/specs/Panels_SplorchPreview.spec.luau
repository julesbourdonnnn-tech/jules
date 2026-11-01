--!nocheck
-- Panels/SplorchPreview (paquet client-panels ; GDD §4.15, §10.3 ; docs/04 §13.6, contrat v1.2) :
-- visible seulement quand le Grand Splorch est prêt, 3 tuiles « Tu gagnes », pièces perdues en rouge
-- et « Dépenser d'abord » (Ranch › Dalles, gardées d'abord), choix du squishy qui s'envole (défaut :
-- le plus gros qui n'est pas Meilleur Ami), case Filmer (cachée sans capture), maintien de 1,5 s puis
-- GrandSplorch une seule fois, PLUS de 2e confirmation (recentBuy ignoré), feedback.waitEscape
-- pendant une fuite, « Rentre dans ton ranch » hors du ranch, Détails et ○. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000

	local function readyProfile(extra)
		local p = {
			squishies = {
				best = TvAudit.squishy(1, { z = 30000, bf = 1 }), -- Meilleur Ami : pas l'envol par défaut
				flyer = TvAudit.squishy(5, { z = 20000 }),
				small = TvAudit.squishy(2, { z = 10 }),
			},
			growth = { G = 0, g = 1, t = NOW },
			coins = 4000,
			pot = 1000,
			R = 0,
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
		}
		for k, v in extra or {} do
			p[k] = v
		end
		return p
	end

	local function setup(profile)
		local h = TvAudit.client({ profile = profile, now = NOW })
		local c = {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			SP = TvAudit.mod(h, "UI.Panels.SplorchPreview"),
			Clock = h:require("ReplicatedStorage.Shared.Util.Clock"),
		}
		return c
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function main(c)
		return c.PC.window("SplorchPreview").Body.Main
	end

	local function holdButton(c)
		return main(c).Hold
	end

	local function hold(c, seconds)
		TvAudit.tick(c.h, 0.5)
		c.h.game.GuiService.SelectedObject = holdButton(c)
		c.h:settle(1)
		Gamepad.press(c.h, Enum.KeyCode.ButtonA)
		c.Clock.advance(seconds)
		c.h:step(1 / 60, 2)
		Gamepad.release(c.h, Enum.KeyCode.ButtonA)
		c.h:settle(2)
	end

	describe("Panels/SplorchPreview", function()
		it(
			"invisible tant que le plus gros n'atteint pas l'objectif ; entrée du rail quand c'est prêt",
			function()
				local c = setup({
					squishies = { a = TvAudit.squishy(1, { z = 100 }) },
					growth = { G = 0, g = 1, t = NOW },
				})
				expect(c.SP.visible()).toBe(false)
				local c2 = setup(readyProfile())
				expect(c2.SP.visible()).toBe(true)
				expect(c2.PC.entries()[1]).toBe("SplorchPreview")
				clean(c)
				clean(c2)
			end
		)

		it(
			"tuiles, pièces perdues, envol par défaut, maintien 1,5 s → GrandSplorch(film, flyer), sans 2e confirmation",
			function()
				local c = setup(readyProfile())
				c.PC.open("SplorchPreview")
				local m = main(c)
				expect(c.h.game.GuiService.SelectedObject).toBe(holdButton(c))
				expect(m.Tile1.Text.Text).toBe("Growth ×2 forever")
				expect(m.Tile2.Text.Text).toBe("Axolo family") -- déblocage de R = 1
				expect(m.Tile3.Text.Text).toBe("+5 Fame")
				expect(m.Lose.Visible).toBe(true)
				expect(m.Lose.Text).toContain("5,000") -- pièces + Pot
				expect(m.SpendFirst.Visible).toBe(true)
				expect(c.SP._state().flyer).toBe("flyer")
				expect(m.FlyerName.Text).toBe("Mochi Mew")
				-- relâché avant 1,5 s : rien
				hold(c, 1.0)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(0)
				hold(c, 1.6)
				local sent = TvAudit.sent(c.h, "GrandSplorch")
				expect(#sent).toBe(1)
				expect(sent[1][1]).toBe(true) -- Filmer (réglage clips par défaut)
				expect(sent[1][2]).toBe("flyer")
				-- l'aperçu se ferme aussitôt (aucune 2e confirmation)
				expect(c.PC.current()).toBeNil()
				clean(c)
			end
		)

		it("choix du squishy qui s'envole ; case Filmer décochée ; Filmer caché sans capture", function()
			local c = setup(readyProfile())
			c.PC.open("SplorchPreview")
			local m = main(c)
			TvAudit.tick(c.h, 0.5)
			c.h.game.GuiService.SelectedObject = m.NextFlyer
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(c.SP._state().flyer).toBe("best")
			c.h.game.GuiService.SelectedObject = m.Film.Toggle
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(c.SP._state().film).toBe(false)
			hold(c, 1.6)
			local sent = TvAudit.sent(c.h, "GrandSplorch")[1]
			expect(sent[1]).toBe(false)
			expect(sent[2]).toBe("best")
			-- appareil sans capture (VFXController pose ClipsUnavailable) : plus de case
			local c2 = setup(readyProfile())
			c2.h.localPlayer:SetAttribute("ClipsUnavailable", true)
			c2.PC.open("SplorchPreview")
			expect(main(c2).Film.Visible).toBe(false)
			hold(c2, 1.6)
			expect(TvAudit.sent(c2.h, "GrandSplorch")[1][1]).toBe(false)
			clean(c)
			clean(c2)
		end)

		it(
			"squishy en fuite : feedback.waitEscape et maintien refusé ; hors du ranch : « Rentre dans ton ranch »",
			function()
				local c = setup(readyProfile())
				local WSC = TvAudit.mod(c.h, "Controllers.WorldStateController")
				WSC.mySlot = function()
					return 4
				end
				WSC.creatures = function()
					return {
						[9] = {
							id = 9,
							kind = "escape",
							species = 5,
							ownerSlot = 4,
							t0 = NOW - 2,
							duration = 20,
						},
					}
				end
				c.PC.open("SplorchPreview")
				local m = main(c)
				expect(m.Status.Visible).toBe(true)
				expect(m.Status.Text).toBe("Wait for Mochi Mew to come home!")
				hold(c, 1.6)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(0)
				-- la fuite finit (t0 + duration passé) ; le personnage est sur la place, hors de son ranch
				-- (position du personnage, Logic/WorldLayout) : « Rentre dans ton ranch », maintien refusé
				c.Clock.advance(30)
				c.h:step(1 / 60, 2)
				expect(m.Status.Text).toBe("Go back to your ranch")
				hold(c, 1.6)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(0)
				-- de retour dans son ranch : plus de message, le maintien part
				local WorldLayout = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
				local root = c.h.localPlayer.Character.HumanoidRootPart
				root.CFrame = c.h.globals.CFrame.new(WorldLayout.toWorld(4, Vector3.new(0, 3, 36)))
				c.h:step(1 / 60, 2)
				expect(m.Status.Visible).toBe(false)
				hold(c, 1.6)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(1)
				clean(c)
			end
		)

		it(
			"« Dépenser d'abord » : Ranch › Dalles, gardées d'abord ; Détails puis ○ ; ○ au menu",
			function()
				local c = setup(readyProfile())
				c.PC.open("SplorchPreview")
				local m = main(c)
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = m.Details
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.SP._state().details).toBe(true)
				local d = c.PC.window("SplorchPreview").Body.DetailsPage
				expect(d.Next.Text).toContain("39")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.SP._state().details).toBe(false)
				expect(c.h.game.GuiService.SelectedObject).toBe(m.Details)
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = m.SpendFirst
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.PC.current()).toBe("Ranch")
				local Ranch = TvAudit.mod(c.h, "UI.Panels.Ranch")
				expect(Ranch.currentTab()).toBe("pads")
				expect(Ranch._state().keptFirst).toBe(true)
				-- 4 000 pièces : l'Enclos (1 200) est la moins chère des dalles gardées payables
				expect(c.h.game.GuiService.SelectedObject).toBe(Ranch._tileButton("pens"))
				clean(c)
			end
		)

		it("recentBuy ignoré : aucune 2e étape même si l'aperçu le signale", function()
			local c = setup(readyProfile())
			local Formulas = c.h:require("ReplicatedStorage.Shared.Logic.Formulas")
			local preview = Formulas.splorchPreview
			Formulas.splorchPreview = function(data, ctx)
				local p = preview(data, ctx)
				p.recentBuy = true
				return p
			end
			c.PC.open("SplorchPreview")
			hold(c, 1.6)
			expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(1)
			clean(c)
		end)
	end)
end
