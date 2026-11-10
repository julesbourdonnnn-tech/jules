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

	describe("Panels/Squishydex › focus (B2-63, lot B3)", function()
		it(
			"parcours à 3 touches sur un profil neuf en anglais aux 3 résolutions : aucun FocusRescued:panel:Squishydex ; rouvert depuis le menu, il montre les Espèces",
			function()
				local c = setup({})
				local r = TvAudit.run(c.h, { langs = { "en" } })
				expect(table.concat(r.issues, "\n")).toBe("")
				local lost = 0
				for _, e in TvAudit.mod(c.h, "Controllers.ErrorReporter").entries() do
					if string.find(e.text, "FocusRescued:panel:Squishydex", 1, true) then
						lost += e.count
					end
				end
				expect(lost).toBe(0)
				-- la cause : le panneau rouvrait sur son dernier onglet ; un chemin vers la fiche d'une espèce
				-- (menu → Squishydex → case) posait alors la sélection sur une case de la page cachée
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Squishydex", "guide")
				TvAudit.tick(c.h, 0.5)
				expect(c.Dex.currentTab()).toBe("guide")
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Squishydex")
				TvAudit.tick(c.h, 0.5)
				expect(c.Dex.currentTab()).toBe("species")
				expect(sel(c):IsDescendantOf(body(c).Page_species)).toBe(true)
				clean(c)
			end
		)
	end)

	describe("Panels/Squishydex › v2.0 (lot B3, Records et maîtrise)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local V2 = UpgradeScreen.V2_ALL

		-- profil v2 : Record R 30, A = 3, plus gros squishy 1e300, une espèce maîtrisée (Plop : ★5, page
		-- dorée, Trophée Cristal), 7 cœurs reçus, 600 niveaux, 99 999 Confettis gagnés
		local function v2profile(edit)
			local p = {
				version = 2,
				R = 30,
				bestR = 30,
				ascend = 3,
				biggestEver = 1e300,
				confettiTotal = 99999,
				stats = { bestCombo = 12, splorches = 40, upgradesBought = 600 },
				mastery = { 2 },
				plopDays = 8,
				hearts = { receivedTotal = 7, givenDay = 0, givenTo = {} },
				dex = dex({ mut = { [1] = 1023, [2] = 1 }, stars = { [1] = 31, [2] = 16 } }),
				trophies = { [1] = 2e12, [2] = 10 },
			}
			if edit then
				edit(p)
			end
			return p
		end

		local function v2client(opts)
			opts = opts or {}
			local c = S.client({ profile = v2profile(opts.edit), lang = opts.lang })
			if opts.flags ~= false then
				S.event(c, opts.flags or V2)
			end
			c.Dex = TvAudit.mod(c.h, "UI.Panels.Squishydex")
			return c
		end

		local function openTab(c, tab)
			c.PC.closeAll()
			TvAudit.tick(c.h, 0.5)
			c.PC.open("Squishydex", tab)
			TvAudit.tick(c.h, 0.5)
		end

		local function lines(list)
			local out = {}
			for i = 1, 12 do
				local l = list.Holder:FindFirstChild("Line" .. i)
				if l and l.Visible then
					table.insert(out, (string.gsub(l.Text, "\n", " ")))
				end
			end
			return out
		end

		local function openSheetOf(c, row, col)
			openTab(c, "species")
			local cell = body(c).Page_species.Species.Holder:FindFirstChild("Row" .. row)["Cell" .. col]
			S.select(c, cell)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			TvAudit.tick(c.h, 0.5)
			return body(c).Sheet
		end

		it(
			"Records : onglet en dernier, Livre des records lu dans le profil (1e300, 99 999), liste sélectionnée",
			function()
				local c = v2client()
				openTab(c, "records")
				expect(c.Dex.tabs()).toEqual({ "species", "families", "guide", "records" })
				expect(c.Dex.currentTab()).toBe("records")
				local list = body(c).Page_records.Records
				expect(S.selected(c)).toBe(list)
				local got = lines(list)
				expect(#got).toBe(10)
				expect(got[1]).toContain("Biggest squishy: ")
				expect(string.find(got[1], "inf", 1, true)).toBeNil()
				expect(string.find(got[1], "nan", 1, true)).toBeNil()
				expect(got[2]).toBe("Best combo: ×12")
				expect(got[3]).toBe("Grand Splorches: 40")
				expect(got[4]).toBe("Jelly Ascends: 3")
				expect(got[5]).toBe("Best Grand Splorch: 30")
				expect(got[6]).toBe("Confetti earned: 99,999")
				expect(got[7]).toBe("Masteries: 1 / 26")
				expect(got[8]).toBe("Plop days: 8")
				expect(got[9]).toBe("Hearts received: 7")
				expect(got[10]).toBe("Upgrades bought: 600")
				S.clean(c, expect)
			end
		)

		it(
			"Records : champs absents ou hostiles → 0, aucune trace ; un système coupé n'a pas sa ligne",
			function()
				local c = v2client({
					lang = "fr",
					edit = function(p)
						p.biggestEver = 0 / 0
						p.stats = "x"
						p.hearts = nil
						p.confettiTotal = -math.huge
						p.mastery = "y"
					end,
					flags = { RecordR = true, Confetti = true },
				})
				openTab(c, "records")
				local got = lines(body(c).Page_records.Records)
				expect(got).toEqual({
					"Plus gros squishy : 0",
					"Meilleur combo : ×0",
					"Grands Splorch : 0",
					"Meilleur Grand Splorch : 30",
					"Confettis gagnés : 0",
					"Jours de Plop : 8",
					"Améliorations achetées : 0",
				})
				S.clean(c, expect)
			end
		)

		it(
			"maîtrise : colonne de la fiche (compte n / m, 3 cases cochées, dorées quand l'espèce est maîtrisée ; partielle sinon)",
			function()
				local c = v2client()
				local sheet = openSheetOf(c, 1, 1) -- Plop : maîtrisé
				local m = sheet.Mastery
				expect(m.Visible).toBe(true)
				expect(m.Title.Text).toBe("Masteries: 1 / 26")
				local W = TvAudit.mod(c.h, "UI.Panels.Widgets")
				for i = 1, 3 do
					expect(m["Box" .. i].Check:GetAttribute("Icon")).toBe("check")
					expect(m["Box" .. i].BackgroundColor3).toBe(W.Colors.Gold)
				end
				expect(m.Box2.Label.Text).toBe("Golden page")
				expect(m.Box3.Label.Text).toBe("Crystal")
				-- ○ puis la 2e espèce (★5 seulement) : 1 case faite (verte), 2 à faire
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				TvAudit.tick(c.h, 0.5)
				sheet = openSheetOf(c, 1, 2)
				m = sheet.Mastery
				expect(m.Box1.Check:GetAttribute("Icon")).toBe("check")
				expect(m.Box1.BackgroundColor3).toBe(W.Colors.Success)
				expect(m.Box2.Check:GetAttribute("Icon")).toBe("")
				expect(m.Box3.BackgroundColor3).toBe(W.Colors.Card)
				S.clean(c, expect)
			end
		)

		it(
			"onglets et colonnes seulement avec leur interrupteur et un profil v2 ; coupés : Squishydex de la v1.3 (rien de la v2.0 construit)",
			function()
				-- RecordR seul : l'onglet Records, pas la maîtrise
				local c = v2client({ flags = { RecordR = true } })
				openTab(c, "records")
				expect(c.Dex.currentTab()).toBe("records")
				local sheet = openSheetOf(c, 1, 1)
				expect(sheet:FindFirstChild("Mastery")).toBeNil()
				S.clean(c, expect)
				-- Mastery seul : la colonne, pas l'onglet
				local c2 = v2client({ flags = { Mastery = true } })
				openTab(c2, "records")
				expect(c2.Dex.tabs()).toEqual({ "species", "families", "guide" })
				expect(c2.Dex.currentTab()).toBe("species")
				expect(body(c2):FindFirstChild("Page_records")).toBeNil()
				expect(openSheetOf(c2, 1, 1).Mastery.Visible).toBe(true)
				S.clean(c2, expect)
				-- coupés, puis profil v1 : rien de la v2.0
				for _, case in
					{ { flags = false }, {
						edit = function(p)
							p.version = 1
						end,
					} }
				do
					local c3 = v2client(case)
					openTab(c3, "records")
					expect(c3.Dex.tabs()).toEqual({ "species", "families", "guide" })
					expect(body(c3):FindFirstChild("Page_records")).toBeNil()
					expect(body(c3).Tabs.Strip:FindFirstChild("Tab_records")).toBeNil()
					expect(openSheetOf(c3, 1, 1):FindFirstChild("Mastery")).toBeNil()
					S.noV2Intent(c3, expect)
					S.clean(c3, expect)
				end
				-- coupés en direct, panneau rouvert : plus d'onglet Records ni de colonne
				local c4 = v2client()
				openTab(c4, "records")
				S.event(c4, nil)
				openTab(c4, "records")
				expect(c4.Dex.currentTab()).toBe("species")
				expect(body(c4).Tabs.Strip.Tab_records.Visible).toBe(false)
				expect(openSheetOf(c4, 1, 1).Mastery.Visible).toBe(false)
				S.clean(c4, expect)
			end
		)
	end)
end
