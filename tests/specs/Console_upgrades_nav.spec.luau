--!nocheck
-- Console_upgrades_nav (lot B2, étape 2 ; docs/04 §27.8 règles 13, 14, 17 ; GDD v2.0 §10.6, §10.7.3 à
-- §10.7.5, §10.7.8) : l'écran Améliorations à la manette SEULE (croix, ✕, ○, □, L1 / R1), sur le vrai
-- client console :
--   * graphe de la croix : cartes ← → (bouts : rebond), ↓ sur une carte = Bump, ↑ = onglets, ↑ encore
--     = bouton de mode ; ↓ depuis le mode = l'onglet actif ; lignes ↑ ↓ (première ↑ = onglets,
--     dernière ↓ = rebond), ← → rien ;
--   * L1 / R1 font tourner les 4 onglets ; ✕ sur un onglet le choisit ; la sélection rendue est la
--     première carte ou la première ligne montrée ;
--   * ✕ sur le bouton de mode et □ (raccourci) : ×1 → ×10 → Max → ×1 ; le mode revient à ×1 à chaque
--     ouverture ;
--   * lignes en lecture seule (Plopettes, « Monte avec ton record ») : sélectionnables, ✕ joue Bump,
--     sans vibration ; carte « Jelly Ascend » : ✕ ouvre son aperçu ;
--   * ○ ferme l'écran (retour à ce qui l'a ouvert), dans chaque état ;
--   * aucune intention v2.0 envoyée (les achats arrivent à l'étape 3).
-- Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local UpgradeScreen = require("../harness/UpgradeScreen")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	local function sel(c)
		return c.h.game.GuiService.SelectedObject
	end

	local function tap(c, key)
		Gamepad.tap(c.h, key)
		TvAudit.tick(c.h, 0.5)
	end

	-- Sons et vibrations relevés (AudioController.play, Haptics.play)
	local function record(c)
		local log = { sounds = {}, haptics = {} }
		local Audio = TvAudit.mod(c.h, "Controllers.AudioController")
		local Haptics = TvAudit.mod(c.h, "Util.Haptics")
		local play, buzz = Audio.play, Haptics.play
		Audio.play = function(name, ...)
			table.insert(log.sounds, name)
			return play(name, ...)
		end
		Haptics.play = function(name, ...)
			table.insert(log.haptics, name)
			return buzz(name, ...)
		end
		function log.clear()
			table.clear(log.sounds)
			table.clear(log.haptics)
		end
		return log
	end

	local function rich(p)
		p.tiles.school = 5
		p.bestR = 12
	end

	describe("Console_upgrades_nav › croix, ✕, ○, □, L1 / R1", function()
		it("Conseillé : cartes ← →, ↓ Bump, ↑ onglets puis bouton de mode, ↓ retour", function()
			local c = S.client({ snap = S.snap(1, rich) })
			S.open(c, "suggested")
			local log = record(c)
			expect(sel(c)).toBe(c.Up._card(1))
			tap(c, Enum.KeyCode.DPadRight)
			expect(sel(c)).toBe(c.Up._card(2))
			tap(c, Enum.KeyCode.DPadRight)
			expect(sel(c)).toBe(c.Up._card(3))
			log.clear()
			tap(c, Enum.KeyCode.DPadRight) -- bout : rebond
			expect(sel(c)).toBe(c.Up._card(3))
			expect(table.find(log.sounds, "Bump") ~= nil).toBe(true)
			log.clear()
			tap(c, Enum.KeyCode.DPadDown) -- ↓ sur une carte : Bump
			expect(sel(c)).toBe(c.Up._card(3))
			expect(table.find(log.sounds, "Bump") ~= nil).toBe(true)
			tap(c, Enum.KeyCode.DPadUp)
			expect(sel(c)).toBe(c.Up._tab("suggested"))
			tap(c, Enum.KeyCode.DPadUp)
			expect(sel(c)).toBe(c.Up._modeButton())
			tap(c, Enum.KeyCode.DPadDown)
			expect(sel(c)).toBe(c.Up._tab("suggested"))
			tap(c, Enum.KeyCode.DPadDown)
			expect(sel(c)).toBe(c.Up._card(1))
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it("L1 / R1 : les 4 onglets en boucle, sélection sur la première carte ou ligne", function()
			local c = S.client({ snap = S.snap(1, rich) })
			S.open(c, "suggested")
			local order = { "ranch", "helpers", "workshop", "suggested" }
			for _, tab in order do
				tap(c, Enum.KeyCode.ButtonR1)
				expect(c.Up.currentTab()).toBe(tab)
				local first = if tab == "suggested" then c.Up._card(1) else c.Up._row(c.Up._shown(tab)[1])
				expect(sel(c)).toBe(first)
			end
			tap(c, Enum.KeyCode.ButtonL1)
			expect(c.Up.currentTab()).toBe("workshop")
			-- ✕ sur un onglet : le choisit (la sélection reste sur l'onglet)
			tap(c, Enum.KeyCode.DPadUp)
			expect(sel(c)).toBe(c.Up._tab("workshop"))
			tap(c, Enum.KeyCode.DPadLeft)
			expect(sel(c)).toBe(c.Up._tab("helpers"))
			tap(c, Enum.KeyCode.ButtonA)
			expect(c.Up.currentTab()).toBe("helpers")
			expect(sel(c)).toBe(c.Up._tab("helpers"))
			tap(c, Enum.KeyCode.DPadDown)
			expect(sel(c)).toBe(c.Up._row(c.Up._shown("helpers")[1]))
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it("lignes : ↑ ↓, première ↑ = onglet, dernière ↓ = rebond, ← → rien", function()
			local c = S.client({ snap = S.snap(1, rich) })
			S.open(c, "ranch")
			local shown = c.Up._shown("ranch")
			expect(sel(c)).toBe(c.Up._row(shown[1]))
			for i = 2, #shown do
				tap(c, Enum.KeyCode.DPadDown)
				expect(sel(c)).toBe(c.Up._row(shown[i]))
			end
			local log = record(c)
			tap(c, Enum.KeyCode.DPadDown)
			expect(sel(c)).toBe(c.Up._row(shown[#shown]))
			expect(table.find(log.sounds, "Bump") ~= nil).toBe(true)
			tap(c, Enum.KeyCode.DPadLeft)
			expect(sel(c)).toBe(c.Up._row(shown[#shown]))
			tap(c, Enum.KeyCode.DPadRight)
			expect(sel(c)).toBe(c.Up._row(shown[#shown]))
			-- la ligne choisie reste entière dans la vue (une ligne de marge quand c'est possible)
			for _ = 1, #shown - 1 do
				tap(c, Enum.KeyCode.DPadUp)
			end
			expect(sel(c)).toBe(c.Up._row(shown[1]))
			tap(c, Enum.KeyCode.DPadUp)
			expect(sel(c)).toBe(c.Up._tab("ranch"))
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it(
			"mode : ✕ et □ font ×1 → ×10 → Max → ×1 ; retour à ×1 à chaque ouverture",
			function()
				local c = S.client({ snap = S.snap(1, rich) })
				S.open(c, "ranch")
				local mb = c.Up._modeButton()
				c.h.game.GuiService.SelectedObject = mb
				TvAudit.tick(c.h, 0.5)
				expect(c.Up.mode()).toBe(1)
				tap(c, Enum.KeyCode.ButtonA)
				expect(c.Up.mode()).toBe(10)
				tap(c, Enum.KeyCode.ButtonX) -- □ : raccourci
				expect(c.Up.mode()).toBe(0)
				tap(c, Enum.KeyCode.ButtonA)
				expect(c.Up.mode()).toBe(1)
				tap(c, Enum.KeyCode.ButtonX)
				expect(c.Up.mode()).toBe(10)
				-- le libellé du bouton suit le mode
				local label = mb:FindFirstChild("Label")
				expect(label.Text).toBe("×10")
				c.PC.closeAll()
				TvAudit.tick(c.h, 1)
				S.open(c, "ranch")
				expect(c.Up.mode()).toBe(1)
				expect(label.Text).toBe("×1")
				-- □ fermé : ne fait rien (action déliée)
				c.PC.closeAll()
				TvAudit.tick(c.h, 1)
				tap(c, Enum.KeyCode.ButtonX)
				expect(c.Up.mode()).toBe(1)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it("lignes en lecture seule : sélectionnables, ✕ joue Bump sans vibration", function()
			local c = S.client({ snap = S.snap(1, rich), ranch = { HelperMode = "nap" } })
			S.open(c, "helpers")
			local log = record(c)
			for _, id in { "helper.pip", "helper.plume" } do
				local row = c.Up._row(id)
				expect(row.Selectable).toBe(true)
				c.h.game.GuiService.SelectedObject = row
				TvAudit.tick(c.h, 0.5)
				log.clear()
				tap(c, Enum.KeyCode.ButtonA)
				expect(log.sounds).toEqual({ "Bump" })
				expect(#log.haptics).toBe(0)
			end
			S.open(c, "workshop")
			c.h.game.GuiService.SelectedObject = c.Up._row("risesWithRecord")
			TvAudit.tick(c.h, 0.5)
			log.clear()
			tap(c, Enum.KeyCode.ButtonA)
			expect(log.sounds).toEqual({ "Bump" })
			expect(#log.haptics).toBe(0)
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it("○ ferme l'écran depuis chaque onglet, les onglets et le bouton de mode", function()
			local c = S.client({ snap = S.snap(1, rich) })
			for _, tab in { "suggested", "ranch", "helpers", "workshop" } do
				for _, where in { "content", "tab", "mode" } do
					S.open(c, tab)
					if where == "tab" then
						c.h.game.GuiService.SelectedObject = c.Up._tab(tab)
					elseif where == "mode" then
						c.h.game.GuiService.SelectedObject = c.Up._modeButton()
					end
					TvAudit.tick(c.h, 0.5)
					tap(c, Enum.KeyCode.ButtonB)
					expect(c.PC.isOpen("Upgrades")).toBe(false)
					expect(c.Up.isOpen()).toBe(false)
				end
			end
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it("carte « Jelly Ascend » : ✕ ouvre l'aperçu sur l'Ascension (N24)", function()
			local function ready(p)
				for k, v in
					{ snack = 12, star = 8, decor = 18, pens = 14, cozyBed = true, gloves = 40, school = 20 }
				do
					p.tiles[k] = v
				end
				p.coins = 0
				p.R = 20
				p.bestR = 20
			end
			local c = S.client({ snap = S.snap(1, ready), ranch = { AscendReady = true } })
			TvAudit.tick(c.h, 1)
			c.Clock.advance(S.Balance.Ascend.DeclineCardAfter + 1)
			TvAudit.tick(c.h, 0.5)
			local opened = {}
			local open = c.PC.open
			c.PC.open = function(panel, tab)
				table.insert(opened, panel .. ":" .. tostring(tab))
				return open(panel, tab)
			end
			S.open(c, "suggested")
			local i = table.find(c.Up._cards(), "ascend")
			expect(i ~= nil).toBe(true)
			c.h.game.GuiService.SelectedObject = c.Up._card(i)
			TvAudit.tick(c.h, 0.5)
			tap(c, Enum.KeyCode.ButtonA)
			expect(table.find(opened, "SplorchPreview:ascend") ~= nil).toBe(true)
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)
	end)
end
