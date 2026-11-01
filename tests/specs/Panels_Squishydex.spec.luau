--!nocheck
-- Panels/Squishydex (paquet client-panels ; GDD §4.17, §10.3 v1.3 ; docs/04 §13.6, contrat v1.2) :
-- onglets Espèces / Familles / Guide (plus de Mutations 26 × 9 ni d'Étoiles), grille par famille avec
-- silhouettes, fiche d'espèce (9 mutations en 3 × 3, badges d'étoiles, record), familles gagnées pour
-- toujours (dex.fam), Guide en lecture seule qui défile de 70 %, jalons à réclamer, UiSeen("dex").
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function dex(opts)
		local mut = table.create(26, 0)
		local stars = table.create(26, 0)
		for s, m in opts.mut or {} do
			mut[s] = m
		end
		for s, m in opts.stars or {} do
			stars[s] = m
		end
		return { mut = mut, stars = stars, fam = opts.fam or table.create(7, 0), rewards = opts.rewards or 0 }
	end

	local function setup(profile)
		local h = TvAudit.client({ profile = profile })
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			Dex = TvAudit.mod(h, "UI.Panels.Squishydex"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function sel(c)
		return c.h.game.GuiService.SelectedObject
	end

	local function body(c)
		return c.PC.window("Squishydex").Body
	end

	describe("Panels/Squishydex", function()
		it(
			"3 onglets seulement (Espèces, Familles, Guide) ; grille par famille, silhouettes grises",
			function()
				-- Plop (1) tamponné ; Wibble (2) inconnu
				local c = setup({ dex = dex({ mut = { [1] = 1 } }) })
				expect(c.Dex.tabs()).toEqual({ "species", "families", "guide" })
				c.PC.open("Squishydex")
				expect(c.Dex.currentTab()).toBe("species")
				local first = sel(c)
				expect(first.Name).toBe("Cell1")
				local row = first.Parent
				expect(row.Family.Text).toBe("Jelly")
				expect(first:FindFirstChild("Name").Text).toBe("Plop")
				expect(row.Cell2:FindFirstChild("Name").Text).toBe("???")
				expect(row.Cell2.Blob.Eye1.Visible).toBe(false)
				-- aucun onglet Mutations ni Étoiles dans la barre
				local strip = body(c).Tabs.Strip
				expect(strip:FindFirstChild("Tab_mutations")).toBeNil()
				expect(strip:FindFirstChild("Tab_stars")).toBeNil()
				-- UiSeen("dex") une seule fois par session
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Squishydex")
				local seen = 0
				for _, args in TvAudit.sent(c.h, "UiSeen") do
					if args[1] == "dex" then
						seen += 1
					end
				end
				expect(seen).toBe(1)
				clean(c)
			end
		)

		it("✕ ouvre la fiche : 9 mutations en 3 × 3, étoiles, record ; ○ revient à la case", function()
			-- Plop : page + Gelée (bit 1) + Doré (bit 4) ; badges ★1 et ★3 ; record 2,3 M (Argent)
			local trophies = table.create(26, 0)
			trophies[1] = 2345678
			local c = setup({
				dex = dex({ mut = { [1] = 1 + 2 + 16 }, stars = { [1] = 1 + 4 } }),
				trophies = trophies,
			})
			c.PC.open("Squishydex")
			local cell = sel(c)
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(c.Dex._sheet().open).toBe(true)
			expect(c.Dex._sheet().species).toBe(1)
			local sheet = body(c).Sheet
			expect(sel(c)).toBe(sheet.Mutation1)
			local names = {}
			for i = 1, 9 do
				table.insert(names, sheet["Mutation" .. i].Label.Text)
			end
			expect(names[1]).toBe("Jelly")
			expect(names[4]).toBe("Golden")
			expect(names[2]).toBe("???")
			expect(sheet.Found.Text).toBe("2 / 9 found")
			expect(sheet.Card.Record.Text).toContain("2.34M")
			expect(sheet.Card.Trophy.Text).toBe("Silver")
			-- la croix reste dans la fiche (3 × 3)
			Gamepad.tap(c.h, Enum.KeyCode.DPadRight)
			expect(sel(c)).toBe(sheet.Mutation2)
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
			expect(c.Dex._sheet().open).toBe(false)
			expect(sel(c)).toBe(cell)
			expect(c.PC.current()).toBe("Squishydex")
			clean(c)
		end)

		it("Familles : bonus gagné pour toujours (dex.fam) ; famille encore verrouillée par R", function()
			local fam = table.create(7, 0)
			fam[1] = 1 -- Jelly gagnée
			local c = setup({ dex = dex({ fam = fam }), R = 0 })
			c.PC.open("Squishydex", "families")
			local holder = body(c).Page_families.Families.Holder
			local texts = {}
			for _, row in holder:GetChildren() do
				if row.Visible then
					local f = row.Family
					texts[f:FindFirstChild("Name").Text] = f.Status.Text
				end
			end
			expect(texts.Jelly).toBe("Complete!")
			expect(texts.Axolo).toBe("Unlocks at Grand Splorch 1")
			clean(c)
		end)

		it(
			"Guide : 1re ligne sélectionnée, ↓ fait défiler de 70 %, ↑ en haut remonte aux onglets",
			function()
				local c = setup({})
				c.PC.open("Squishydex", "guide")
				local guide = body(c).Page_guide.Guide
				expect(sel(c)).toBe(guide)
				expect(guide.NextSelectionUp).toBe(body(c).Tabs.Strip.Tab_guide)
				local y0 = guide.Holder.Position.Y.Offset
				Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
				c.h:settle(2)
				expect(guide.Holder.Position.Y.Offset < y0).toBe(true)
				expect(sel(c)).toBe(guide)
				expect(guide.NextSelectionUp).toBe(guide)
				Gamepad.tap(c.h, Enum.KeyCode.DPadUp)
				c.h:settle(2)
				expect(guide.Holder.Position.Y.Offset).toBe(y0)
				-- le Guide montre la table de la Cuve et les règles du BOOP RUSH
				expect(guide.Holder.Line1.Text).toContain("Jelly Vat")
				local found = false
				for _, l in guide.Holder:GetChildren() do
					if l:IsA("TextLabel") and string.find(l.Text, "Best Friends never run away", 1, true) then
						found = true
					end
				end
				expect(found).toBe(true)
				clean(c)
			end
		)

		it(
			"jalon atteint : « Réclamer » visible et ClaimDexReward ; aucun jalon : bouton caché",
			function()
				-- 10 tampons (espèces 1 à 10, page seulement)
				local mut = {}
				for s = 1, 10 do
					mut[s] = 1
				end
				local c = setup({ dex = dex({ mut = mut }) })
				c.PC.open("Squishydex")
				local claim = body(c).Page_species.Claim
				expect(claim.Visible).toBe(true)
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = claim
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(#TvAudit.sent(c.h, "ClaimDexReward")).toBe(1)
				local c2 = setup({ dex = dex({ mut = mut, rewards = 10 }) })
				c2.PC.open("Squishydex")
				expect(body(c2).Page_species.Claim.Visible).toBe(false)
				clean(c)
				clean(c2)
			end
		)

		it("Squishydex abîmé (masques négatifs, NaN, chaînes) : aucun plantage", function()
			local c =
				setup({ dex = { mut = { -5, 0 / 0, "x" }, stars = "rien", fam = 3 }, trophies = "rien" })
			for _, tab in c.Dex.tabs() do
				c.PC.open("Squishydex", tab)
				TvAudit.tick(c.h, 0.5)
			end
			clean(c)
		end)
	end)
end
