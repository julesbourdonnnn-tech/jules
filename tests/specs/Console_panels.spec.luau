--!nocheck
-- Console_panels (paquet client-panels ; couche d, docs/04 §14, §17.1 d) : PS5 sur télé, profil
-- riche (Boutique ouverte, Grand Splorch prêt, Diagnostics d'administrateur) : chaque écran atteint
-- avec la croix, ✕ et ○ seulement, sélection jamais vide ni hors de la fenêtre active, aucune touche
-- du jeu derrière une fenêtre, glyphes PlayStation, ○ revient toujours ; même chose au clavier et à la
-- souris (Retour arrière = ○, clic = ✕, libellés des touches au clavier). Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local ApiAudit = require("../harness/ApiAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function richClient(opts)
		opts = opts or {}
		local profile = TvAudit.richProfile()
		-- Grand Splorch prêt (R = 3 : objectif 260 000)
		profile.squishies.u20.z = 300000
		local h = TvAudit.client({
			console = opts.console,
			before = TvAudit.enableShop,
			profile = profile,
		})
		h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
		h:settle(1)
		return h
	end

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	describe("Console_panels › manette (PS5, 1920 × 1080)", function()
		it("tous les écrans atteints à 3 touches, sans faute ; ○ rend toujours la main au jeu", function()
			local h = richClient()
			local report = TvAudit.walk(h)
			expect(table.concat(report.issues, "\n")).toBe("")
			local panels = {}
			for id in report.screens do
				local p = string.match(id, "^panel:(%w+)")
				if p then
					panels[p] = true
				end
			end
			for _, p in
				{
					"Ranch",
					"Squishydex",
					"Objectives",
					"Leaderboards",
					"Shop",
					"Settings",
					"SplorchPreview",
					"OutfitPreview",
					"Diagnostics",
				}
			do
				expect({ panel = p, reached = panels[p] == true }).toEqual({ panel = p, reached = true })
			end
			-- sous-niveaux atteints : fiche d'un squishy, fiche d'espèce, Détails, exemples… au moins 30 écrans
			local n = 0
			for _ in report.screens do
				n += 1
			end
			expect(n >= 30).toBe(true)
			clean(h)
		end)

		it(
			"glyphes : ○ du bouton Fermer, L1 / R1, L2 / R2 et ✕ du maintien en icônes PlayStation",
			function()
				local h = richClient()
				local PC = TvAudit.mod(h, "UI.PanelController")
				PC.open("SplorchPreview")
				local win = PC.window("SplorchPreview")
				local close = win.Header.Close.Glyph
				expect(close:GetAttribute("GlyphKey")).toBe("ButtonB")
				expect(close.Image.Image).toContain(Gamepad.PS_GLYPHS)
				local holdGlyph = win.Body.Main.Hold.Glyph
				expect(holdGlyph:GetAttribute("GlyphKey")).toBe("ButtonA")
				TvAudit.tick(h, 0.5)
				PC.open("Ranch")
				local found = {}
				for _, d in PC.window("Ranch"):GetDescendants() do
					local key = d:GetAttribute("GlyphKey")
					if type(key) == "string" and key ~= "" and d.Visible then
						found[key] = true
					end
				end
				for _, key in { "ButtonB", "ButtonL1", "ButtonR1", "ButtonL2", "ButtonR2" } do
					expect({ key = key, shown = found[key] == true }).toEqual({ key = key, shown = true })
				end
				expect(#TvAudit.glyphs(h, PC.window("Ranch"))).toBe(0)
				clean(h)
			end
		)
	end)

	describe("Console_panels › API Roblox", function()
		it(
			"chaque classe créée, propriété écrite et membre lu par le menu et les panneaux existe (ApiAudit)",
			function()
				ApiAudit.start()
				local ok, err = pcall(function()
					local h = richClient()
					local PC = TvAudit.mod(h, "UI.PanelController")
					PC.toggleMenu()
					for _, panel in
						{
							"Ranch",
							"Squishydex",
							"Objectives",
							"Leaderboards",
							"Shop",
							"Settings",
							"SplorchPreview",
							"Diagnostics",
						}
					do
						TvAudit.tick(h, 0.5)
						PC.open(panel)
						local mod = TvAudit.mod(h, "UI.Panels." .. panel)
						for _, tab in mod.tabs() do
							mod.setTab(tab)
							TvAudit.tick(h, 0.1)
						end
					end
					TvAudit.tick(h, 0.5)
					PC.open("OutfitPreview", "sweater")
					TvAudit.tick(h, 0.5)
					PC.closeAll()
					TvAudit.mod(h, "UI.ReturnScreen").show({
						seconds = 600,
						uid = "u1",
						species = 1,
						grew = 5,
						pot = 5,
						splorchReady = true,
						nearlyReady = false,
					})
					h:step(1 / 60, 3)
					clean(h)
				end)
				local issues = ApiAudit.stop()
				expect(ok and "" or tostring(err)).toBe("")
				expect(table.concat(issues, "\n")).toBe("")
			end
		)
	end)

	-- v2.0 (lot B2, étape 5 ; GDD §10.7.1, §10.7.2, N9) : l'écran Améliorations atteint à la manette en 3
	-- appuis depuis le jeu (△ ouvre le rail sur Ranch, ↓ descend sur Améliorations, juste dessous, ✕
	-- l'ouvre) ; interrupteur UpgradesScreen coupé (aucun instantané du serveur) : aucune entrée, les
	-- mêmes appuis ouvrent le Squishydex comme dans la v1.3, aucune intention v2.0
	describe("Console_panels › v2.0 : Améliorations (lot B2)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }

		local function threePresses(c)
			local h = c.h
			TvAudit.tick(h, 0.5)
			Gamepad.tap(h, Enum.KeyCode.ButtonY)
			TvAudit.tick(h, 0.5)
			local afterMenu = h.game.GuiService.SelectedObject
			Gamepad.tap(h, Enum.KeyCode.DPadDown)
			TvAudit.tick(h, 0.5)
			Gamepad.tap(h, Enum.KeyCode.ButtonA)
			TvAudit.tick(h, 0.5)
			return afterMenu
		end

		it(
			"△, ↓, ✕ : l'écran Améliorations s'ouvre sur Conseillé ; ○ revient au rail puis au jeu",
			function()
				local c = S.client({ snap = S.snap(1), profile = { onboarding = DONE } })
				local h, PC = c.h, c.PC
				local first = threePresses(c)
				expect(first).toBe(PC.entryButton("Ranch"))
				expect(PC.current()).toBe("Upgrades")
				expect(c.Up.isOpen()).toBe(true)
				expect(c.Up.currentTab()).toBe("suggested")
				-- sélection sur la première carte du Conseillé, dans la fenêtre de l'écran
				local sel = h.game.GuiService.SelectedObject
				expect(sel ~= nil and sel:IsDescendantOf(PC.window("Upgrades"))).toBe(true)
				expect(sel).toBe(c.Up._card(1))
				-- ✕ de l'ouverture : rien acheté (garde d'entrée, maintien de 0,6 s)
				expect(#TvAudit.sent(h, "BuyUpgrade")).toBe(0)
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				TvAudit.tick(h, 0.5)
				expect(PC.current()).toBeNil()
				expect(PC.menuOpen()).toBe(true)
				expect(h.game.GuiService.SelectedObject).toBe(PC.entryButton("Upgrades"))
				expect(TvAudit.toGame(h)).toBe(true)
				S.clean(c, expect)
			end
		)

		it(
			"interrupteur coupé : aucune entrée Améliorations ; △, ↓, ✕ ouvrent le Squishydex (v1.3)",
			function()
				local c = S.client({ profile = { onboarding = DONE } })
				local h, PC = c.h, c.PC
				expect(PC.entryButton("Upgrades")).toBeNil()
				expect(PC.window("Upgrades")).toBeNil()
				local first = threePresses(c)
				expect(first).toBe(PC.entryButton("Ranch"))
				expect(PC.current()).toBe("Squishydex")
				S.noV2Intent(c, expect)
				expect(TvAudit.toGame(h)).toBe(true)
				S.clean(c, expect)
			end
		)

		it(
			"parcours à 3 touches avec l'écran Améliorations : chaque onglet atteint, sans faute ; ○ rend toujours la main",
			function()
				local profile = TvAudit.richProfile()
				profile.upgradeSnapshot = S.snap(1)
				local h = TvAudit.client({ before = TvAudit.enableShop, profile = profile })
				local report = TvAudit.walk(h, { maxScreens = 120 })
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
				expect(#TvAudit.sent(h, "BuyUpgrade")).toBe(0)
				clean(h)
			end
		)
	end)

	-- Lot B3, étape 2 (D9, D25 ; GDD §10.6) : aperçu de renaissance à la manette seule, interrupteurs v2.0
	-- ouverts DANS le test (EventState.features.v2), Grand Splorch ET Jelly Ascend prêts
	describe("Console_panels › v2.0 : aperçus de renaissance (lot B3)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }

		it(
			"entrée de renaissance → aperçu, maintien sélectionné ; R1 → onglet Jelly Ascend (son maintien) ; L1 → retour ; ○ → menu sur l'entrée",
			function()
				local snap = S.snap(1, function(p)
					p.R = 15
					p.bestR = 15
					p.ascend = 0
				end)
				local c = S.client({
					snap = snap,
					profile = {
						version = 2,
						onboarding = DONE,
						R = 15,
						squishies = {
							a = TvAudit.squishy(1, { z = 3e15, bf = 1 }),
							b = TvAudit.squishy(5, { z = 2e15 }),
						},
						growth = { G = 0, g = 0, t = 1800000000 },
					},
					ranch = { AscendReady = true },
				})
				S.event(c, UpgradeScreen.V2_ALL)
				local h, PC = c.h, c.PC
				local SP = TvAudit.mod(h, "UI.Panels.SplorchPreview")
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonY)
				TvAudit.tick(h, 0.5)
				local entry = PC.entryButton("SplorchPreview")
				expect(h.game.GuiService.SelectedObject).toBe(entry)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				TvAudit.tick(h, 0.5)
				expect(PC.current()).toBe("SplorchPreview")
				expect(SP.currentTab()).toBe("splorch")
				local parts = SP._v2()
				expect(h.game.GuiService.SelectedObject).toBe(parts.hold)
				Gamepad.tap(h, Enum.KeyCode.ButtonR1)
				TvAudit.tick(h, 0.5)
				expect(SP.currentTab()).toBe("ascend")
				expect(h.game.GuiService.SelectedObject).toBe(parts.ascendHold)
				Gamepad.tap(h, Enum.KeyCode.ButtonL1)
				TvAudit.tick(h, 0.5)
				expect(SP.currentTab()).toBe("splorch")
				expect(h.game.GuiService.SelectedObject).toBe(parts.hold)
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				TvAudit.tick(h, 0.5)
				expect(PC.current()).toBeNil()
				expect(PC.menuOpen()).toBe(true)
				expect(h.game.GuiService.SelectedObject).toBe(entry)
				expect(TvAudit.toGame(h)).toBe(true)
				expect(#TvAudit.sent(h, "JellyAscend")).toBe(0)
				expect(#TvAudit.sent(h, "GrandSplorch")).toBe(0)
				S.clean(c, expect)
			end
		)
	end)

	describe("Console_panels › v2.0 : Mon style et Déco perso (lot B3)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local Layout = require("../harness/Layout")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }

		it(
			"onglet Mon style à la croix ; sortes ↓ ; plan : chaque emplacement atteint ; choix ; ○ : choix → emplacement → sortes → menu",
			function()
				local c = S.client({
					snap = S.snap(1),
					profile = {
						version = 2,
						onboarding = DONE,
						R = 10,
						bestR = 10,
						ascend = 1,
						plopDays = 8,
						stats = { playSeconds = 400 },
						cosmetics = { saddle = "classic", theme = "color", trail = "", title = "", flag = "" },
						decoPerso = { owned = { 0, 0 }, slots = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
						squishies = { a = TvAudit.squishy(1) },
					},
					ranch = { DecoPerso = "1,0,0,0,0,0,0,0,0,0,0,0" },
				})
				S.event(c, UpgradeScreen.V2_ALL)
				local h, PC = c.h, c.PC
				local Ranch = TvAudit.mod(h, "UI.Panels.Ranch")
				local function sel()
					return h.game.GuiService.SelectedObject
				end
				PC.open("Ranch", "pens")
				TvAudit.tick(h, 0.5)
				local tabs = PC.window("Ranch").Body.Tabs.Strip
				local guard = 0
				while sel() ~= tabs.Tab_style and guard < 14 do
					guard += 1
					if sel():IsDescendantOf(tabs) then
						Gamepad.tap(h, Enum.KeyCode.DPadRight)
					else
						Gamepad.tap(h, Enum.KeyCode.DPadUp)
					end
				end
				expect(sel()).toBe(tabs.Tab_style)
				expect(tabs.Tab_style.Label.Text).toBe("My style")
				expect(tabs.Tab_pads.Visible).toBe(false)
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				TvAudit.tick(h, 0.5)
				expect(Ranch.currentTab()).toBe("style")
				-- ○ : de la grille à la liste des sortes ; ↓ : Déco perso ; ✕ : l'emplacement 1
				h.game.GuiService.SelectedObject = Ranch._styleCell("theme", "color")
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				expect(sel()).toBe(Ranch._styleKindButton("theme"))
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.DPadDown)
				expect(sel()).toBe(Ranch._styleKindButton("deco"))
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				TvAudit.tick(h, 0.5)
				expect(sel()).toBe(Ranch._decoSlot(1))
				Layout.apply(h)
				expect(#Layout.unreachable(h, Ranch._decoSlot(1).Parent, Ranch._decoSlot(1))).toBe(0)
				-- → depuis l'emplacement 2 (en bas, au milieu) : un autre emplacement, jamais hors du panneau
				h.game.GuiService.SelectedObject = Ranch._decoSlot(2)
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.DPadRight)
				expect(sel():IsDescendantOf(PC.window("Ranch"))).toBe(true)
				h.game.GuiService.SelectedObject = Ranch._decoSlot(2)
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				TvAudit.tick(h, 0.5)
				expect(Ranch._state().pickerSlot).toBe(2)
				expect(sel()).toBe(Ranch._styleCell("deco", ""))
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				TvAudit.tick(h, 0.5)
				expect(sel()).toBe(Ranch._decoSlot(2))
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				TvAudit.tick(h, 0.5)
				expect(sel()).toBe(Ranch._styleKindButton("deco"))
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				TvAudit.tick(h, 0.5)
				expect(PC.current()).toBeNil()
				expect(#TvAudit.sent(h, "PlaceDeco")).toBe(0)
				clean(h)
			end
		)
	end)

	describe("Console_panels › clavier et souris (second)", function()
		it(
			"clic = ✕, Retour arrière = ○, libellés des touches du clavier ; aucune touche manette affichée",
			function()
				local h = richClient({ console = false })
				local PC = TvAudit.mod(h, "UI.PanelController")
				local FG = TvAudit.mod(h, "UI.FocusGuard")
				PC.toggleMenu()
				-- clic sur l'entrée Ranch du rail, après la garde d'ouverture (InputGuard, GDD v2.0 §10.6
				-- règle 6, N14 : un clic 0 s après l'ouverture du menu est ignoré)
				TvAudit.tick(h, 0.5)
				PC.entryButton("Ranch").Activated:Fire()
				h:settle(2)
				expect(PC.current()).toBe("Ranch")
				local close = PC.window("Ranch").Header.Close.Glyph
				expect(close:GetAttribute("GlyphMode")).toBe("text")
				expect(close.Text.Text).toBe("⌫")
				-- L1 / R1 n'ont pas de touche au clavier : masqués
				local l1 = PC.window("Ranch").Body.Tabs:FindFirstChild("Glyph")
				expect(l1 == nil or l1.Visible == false).toBe(true)
				-- Retour arrière : FocusGuard (même liaison que ○)
				TvAudit.tick(h, 0.5)
				Gamepad.dispatch(h, Enum.KeyCode.Backspace, Enum.UserInputState.Begin)
				h:settle(2)
				expect(PC.current()).toBeNil()
				expect(PC.menuOpen()).toBe(true)
				TvAudit.tick(h, 0.5)
				Gamepad.dispatch(h, Enum.KeyCode.Backspace, Enum.UserInputState.Begin)
				h:settle(2)
				expect(FG.anyOpen()).toBe(false)
				-- le bouton Fermer (souris) ferme aussi le panneau
				PC.open("Squishydex")
				TvAudit.tick(h, 0.5)
				PC.window("Squishydex").Header.Close.Activated:Fire()
				h:settle(2)
				expect(PC.current()).toBeNil()
				clean(h)
			end
		)
	end)
end
