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

	describe("Console_panels › v2.0 : piste, Carnet et Records (lot B3, étape 4)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }

		it(
			"R1 jusqu'à « Cette semaine » puis « Carnet » (1er palier sélectionné) ; Records : liste sélectionnée, ↓ en bout rebondit, ↑ remonte à l'onglet ; ○ → menu",
			function()
				local c = S.client({
					profile = {
						version = 2,
						onboarding = DONE,
						R = 10,
						bestR = 10,
						ascend = 1,
						objectives = {
							day = 20833,
							list = {
								{ id = 1, p = 0, done = false, claimed = false },
								{ id = 7, p = 0, done = false, claimed = false },
								{ id = 14, p = 0, done = false, claimed = false },
							},
							rerolls = 0,
							allClaimed = false,
						},
						weeklyTrack = {
							period = 2975,
							points = 4,
							claimed = { 3 },
							won = { 0 },
							challenges = {},
						},
						carnet = { 1 },
						stats = { upgradesBought = 120, splorches = 9, bestCombo = 3 },
						biggestEver = 5e6,
						plopDays = 3,
					},
				})
				S.event(c, UpgradeScreen.V2_ALL)
				local h, PC = c.h, c.PC
				local function sel()
					return h.game.GuiService.SelectedObject
				end
				local function tap(key)
					TvAudit.tick(h, 0.5)
					Gamepad.tap(h, key)
					TvAudit.tick(h, 0.5)
				end
				PC.open("Objectives")
				TvAudit.tick(h, 0.5)
				local Obj = TvAudit.mod(h, "UI.Panels.Objectives")
				expect(sel()).toBe(PC.window("Objectives").Body.Page_today.Card1.Action)
				tap(Enum.KeyCode.ButtonR1)
				expect(Obj.currentTab()).toBe("track")
				local body = PC.window("Objectives").Body
				expect(sel()).toBe(body.Page_track.Tier1)
				-- → parcourt les paliers, ↓ descend aux Défis (aucun : la page reste sur les paliers)
				tap(Enum.KeyCode.DPadRight)
				expect(sel()).toBe(body.Page_track.Tier2)
				tap(Enum.KeyCode.ButtonR1)
				expect(Obj.currentTab()).toBe("carnet")
				expect(sel()).toBe(body.Page_carnet.Cell1)
				tap(Enum.KeyCode.ButtonB)
				expect(PC.current()).toBeNil()
				expect(PC.menuOpen()).toBe(true)
				-- Squishydex › Records (dernier onglet : L1 depuis les Espèces)
				PC.open("Squishydex")
				TvAudit.tick(h, 0.5)
				local Dex = TvAudit.mod(h, "UI.Panels.Squishydex")
				tap(Enum.KeyCode.ButtonL1)
				expect(Dex.currentTab()).toBe("records")
				local dexBody = PC.window("Squishydex").Body
				local list = dexBody.Page_records.Records
				expect(sel()).toBe(list)
				-- tout le Livre tient à l'écran : ↓ rebondit (la sélection reste sur la liste), ↑ remonte
				-- à l'onglet Records
				tap(Enum.KeyCode.DPadDown)
				expect(sel()).toBe(list)
				expect(list.Holder.Position.Y.Offset).toBe(0)
				tap(Enum.KeyCode.DPadUp)
				expect(sel()).toBe(dexBody.Tabs.Strip.Tab_records)
				tap(Enum.KeyCode.ButtonB)
				expect(PC.current()).toBeNil()
				expect(PC.menuOpen()).toBe(true)
				clean(h)
			end
		)
	end)

	-- lot B3, étape 5 (D19, D25) : une carte de la v2.0 rangée dans « ! » se rouvre à la manette et son
	-- « Voir » ouvre l'écran qu'elle porte ; ○ sur la carte rouverte la range de nouveau
	describe("Console_panels › v2.0 : cartes rouvertes depuis « ! » (lot B3, étape 5)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }

		it(
			"△ → « ! » → ✕ rouvre la carte du palier ; ○ la range ; ✕ sur « Voir » ouvre Objectifs › Cette semaine ; maîtrise → fiche de l'espèce",
			function()
				local c = S.client({
					profile = {
						version = 2,
						onboarding = DONE,
						weeklyTrack = {
							period = 2975,
							points = 4,
							claimed = { 3 },
							won = { 0 },
							challenges = {},
						},
						carnet = { 1 },
						stats = { upgradesBought = 120 },
					},
				})
				S.event(c, UpgradeScreen.V2_ALL)
				local h, PC = c.h, c.PC
				local C = TvAudit.mod(h, "UI.Cards")
				local function sel()
					return h.game.GuiService.SelectedObject
				end
				local function tap(key)
					TvAudit.tick(h, 0.5)
					Gamepad.tap(h, key)
					TvAudit.tick(h, 0.5)
				end
				local function stow(kind, data)
					h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = kind, data = data })
					h:settle(1)
					c.Clock.advance(8.01)
					C._step()
					TvAudit.tick(h, 0.2)
				end
				stow("trackTier", { tier = 2, reward = "confetti" })
				expect(#C.pending()).toBe(1)
				tap(Enum.KeyCode.ButtonY)
				expect(PC.menuOpen()).toBe(true)
				local pending = PC.entryButton("Pending")
				h.game.GuiService.SelectedObject = pending
				tap(Enum.KeyCode.ButtonA)
				expect(C.current() ~= nil and C.current().kind).toBe("trackTier")
				local buttons = C.buttons()
				expect(sel()).toBe(buttons[1])
				expect(buttons[1].Label.Text).toBe("See")
				-- ○ : la carte se range, retour au rail sur « ! »
				tap(Enum.KeyCode.ButtonB)
				expect(#C.pending()).toBe(1)
				expect(PC.menuOpen()).toBe(true)
				h.game.GuiService.SelectedObject = PC.entryButton("Pending")
				tap(Enum.KeyCode.ButtonA)
				tap(Enum.KeyCode.ButtonA)
				expect(PC.current()).toBe("Objectives")
				expect(TvAudit.mod(h, "UI.Panels.Objectives").currentTab()).toBe("track")
				expect(#C.pending()).toBe(0)
				tap(Enum.KeyCode.ButtonB)
				-- maîtrise : la fiche des espèces du Squishydex
				stow("mastery", { species = 2 })
				PC.closeAll()
				TvAudit.tick(h, 0.5)
				tap(Enum.KeyCode.ButtonY)
				h.game.GuiService.SelectedObject = PC.entryButton("Pending")
				tap(Enum.KeyCode.ButtonA)
				expect(C.current().kind).toBe("mastery")
				tap(Enum.KeyCode.ButtonA)
				expect(PC.current()).toBe("Squishydex")
				expect(TvAudit.mod(h, "UI.Panels.Squishydex").currentTab()).toBe("species")
				clean(h)
			end
		)
	end)

	-- lot B3, étape 6 (journal B3-68 ; défaut de la v1.3 vu par la promenade ci-dessous) : L1 / R1 à travers
	-- un onglet VIDE (Dodo, Boîte aux lettres sans squishy : sa sélection par défaut est le bouton de son
	-- onglet) laissaient la sélection sur le bouton de l'onglet QUITTÉ : ✕ y ramenait. Après chaque L1 / R1,
	-- la sélection est dans la page de l'onglet affiché ou sur son propre bouton (GDD §10.6 : 1re case de
	-- l'onglet), interrupteurs coupés
	describe("Console_panels › L1 / R1 à travers un onglet vide (v1.3)", function()
		local Layout = require("../harness/Layout")
		it(
			"après chaque R1 puis L1, la sélection suit l'onglet affiché, jamais le bouton d'un autre onglet",
			function()
				local h = TvAudit.client({
					profile = {
						onboarding = { step = 11, done = true, demoDone = true },
						squishies = { a = TvAudit.squishy(1), b = TvAudit.squishy(2) },
					},
				})
				local PC = TvAudit.mod(h, "UI.PanelController")
				local Ranch = TvAudit.mod(h, "UI.Panels.Ranch")
				TvAudit.openMenu(h)
				h.game.GuiService.SelectedObject = PC.entryButton("Ranch")
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				TvAudit.tick(h, 0.5)
				expect(PC.current()).toBe("Ranch")
				local body = PC.window("Ranch").Body
				local wrong = {}
				local function look(step)
					local sel = h.game.GuiService.SelectedObject
					local tab = Ranch.currentTab()
					Layout.apply(h)
					local ok = sel ~= nil
						and sel:IsDescendantOf(body)
						and Layout.visible(sel)
						and (sel:GetAttribute("TvTab") ~= true or sel.Name == "Tab_" .. tab)
					if not ok then
						table.insert(
							wrong,
							`{step} : onglet {tab}, sélection {if sel then sel.Name else "nil"}`
						)
					end
				end
				local n = #Ranch.tabs()
				for i = 1, n do
					TvAudit.tick(h, 0.5)
					Gamepad.tap(h, Enum.KeyCode.ButtonR1)
					TvAudit.tick(h, 0.5)
					look("R1 n° " .. i)
				end
				for i = 1, n do
					TvAudit.tick(h, 0.5)
					Gamepad.tap(h, Enum.KeyCode.ButtonL1)
					TvAudit.tick(h, 0.5)
					look("L1 n° " .. i)
				end
				expect(table.concat(wrong, "\n")).toBe("")
				clean(h)
			end
		)
	end)

	-- lot B3, étape 6 (D25 ; journal B3-66) : promenade à la MANETTE seule (croix, ✕, ○, △, □, L1 / R1 :
	-- aucune fenêtre ouverte par le code) dans chaque écran v2.0 du lot B3, aux 3 résolutions et dans les
	-- 2 langues : sélections par défaut et retours de ○ de D25 ; sur chaque écran, aucune faute de
	-- TvAudit.check (sélection dans la fenêtre, rien ne s'échappe, aucun chevauchement ni texte coupé,
	-- glyphes PlayStation, zone sûre)
	describe(
		"Console_panels › v2.0 : promenade à la manette dans les écrans du lot B3 (étape 6)",
		function()
			local UpgradeScreen = require("../harness/UpgradeScreen")
			local MockInstance = require("../harness/MockInstance")
			local LayoutH = require("../harness/Layout")
			local S = UpgradeScreen.new(T.Harness)
			local DONE = { step = 11, done = true, demoDone = true }
			local OWNER = 22
			local A, B, X, Y =
				Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY
			local L1, R1 = Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1
			local UP, DOWN = Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown
			local WEEK, EPOCH = 604800, 345600

			local function ranchRow(slot, userId, me)
				return {
					slot = slot,
					userId = userId,
					name = if userId == me then "Moi" else "",
					hidden = userId ~= me,
					R = 0,
					fame = 0,
					day = 0,
					mode = "cozy",
					shield = false,
					boopable = false,
					tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
					vat = true,
					pool = true,
					vatFill = 0,
					growth = { G = 0, g = 0, t = 1800000000 },
					carry = "",
					ride = "",
					saddle = 0,
					waiting = "",
					theme = "",
					flag = "",
					title = "",
					saddleColor = "",
					trail = "",
					best = { s = 0, m = 0, z = 0, zg = 0 },
				}
			end

			it(
				"aperçu (onglets, maintien de 3 s, carte), Mon style (plan, choix), Records, piste, Carnet, halo, carte rouverte, jumelles ; ○ selon D25",
				function()
					local week = math.floor((1800000000 - EPOCH) / WEEK)
					local settings = TvAudit.defaults().settings
					settings.haloOn = true
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
							bestR = 15,
							ascend = 0,
							settings = settings,
							squishies = {
								a = TvAudit.squishy(1, { z = 3e15, bf = 1 }),
								b = TvAudit.squishy(5, { z = 2e15 }),
							},
							growth = { G = 0, g = 0, t = 1800000000 },
							cosmetics = {
								saddle = "classic",
								theme = "color",
								trail = "",
								title = "",
								flag = "",
								palette = "",
								cushions = "",
							},
							outfits = { owned = { plopBib = 1, partyHat = 1 }, worn = {} },
							decoPerso = { owned = { 0, 0 }, slots = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
							weeklyTrack = {
								period = week,
								firstPeriodEnd = EPOCH + (week - 4) * WEEK,
								points = 9,
								claimed = { 3 },
								won = { 0 },
								challenges = {
									{ id = 7, p = 1, done = false },
									{ id = 6, p = 1, done = true },
									{ id = 12, p = 17, done = false },
								},
								play = { 0, 0, 0, 0, 0, 0, 0 },
								playDay = 0,
							},
							carnet = { 1 },
							mastery = { 2 },
							hearts = { receivedTotal = 7, givenDay = 0, givenTo = {} },
							stats = { upgradesBought = 120, splorches = 9, bestCombo = 3, playSeconds = 400 },
							biggestEver = 3e15,
							plopDays = 3,
						},
						ranch = {
							AscendReady = true,
							HaloOn = true,
							DecoPerso = "1,0,0,0,0,0,0,0,0,0,0,0",
							BestR = 15,
						},
					})
					S.event(c, UpgradeScreen.V2_ALL)
					local h, PC = c.h, c.PC
					local me = h.localPlayer.UserId
					-- le voisin OWNER au ranch 2 (jumelles : preuve v2.0 BestR sur son modèle)
					h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
						seq = 1,
						ranches = { ["1"] = ranchRow(1, me, me), ["2"] = ranchRow(2, OWNER, me) },
						squishies = { ["1"] = {}, ["2"] = {} },
					})
					h:settle(1)
					local list = h.workspace.Wobbleton.Ranches
					local other = list:FindFirstChild("2")
					if other == nil then
						other = MockInstance.new("Model")
						other.Name = "2"
						other.Parent = list
					end
					other:SetAttribute("BestR", 5)
					local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
					local SP = TvAudit.mod(h, "UI.Panels.SplorchPreview")
					local Ranch = TvAudit.mod(h, "UI.Panels.Ranch")
					local Dex = TvAudit.mod(h, "UI.Panels.Squishydex")
					local Obj = TvAudit.mod(h, "UI.Panels.Objectives")
					local Cards = TvAudit.mod(h, "UI.Cards")
					local Bino = TvAudit.mod(h, "UI.Binoculars")
					local Prompt = TvAudit.mod(h, "Controllers.PromptController")
					local FG = c.FG
					local issues = {}
					local function sel()
						return h.game.GuiService.SelectedObject
					end
					local function nm(obj)
						return if obj then LayoutH.name(obj) else "nil"
					end
					local function tap(key)
						TvAudit.tick(h, 0.5)
						Gamepad.tap(h, key)
						TvAudit.tick(h, 0.5)
					end
					local function check(label)
						for _, issue in TvAudit.check(h, label) do
							table.insert(issues, issue)
						end
					end
					-- l'entrée `name` du rail, à la croix (↓ puis ↑)
					local function toEntry(name)
						local target = PC.entryButton(name)
						for _, key in { DOWN, UP } do
							for _ = 1, 10 do
								if sel() == target then
									return true
								end
								tap(key)
							end
						end
						return sel() == target
					end
					local function inRanch()
						h.localPlayer.Character.HumanoidRootPart.CFrame =
							h.globals.CFrame.new(WorldLayout.toWorld(1, roblox.Vector3.new(0, 3, 36)))
						S.run(c, 0.3)
					end
					local resolutions = {
						roblox.Vector2.new(1920, 1080),
						roblox.Vector2.new(3840, 2160),
						roblox.Vector2.new(1280, 720),
					}
					local round = 0
					for _, res in resolutions do
						TvAudit.setResolution(h, res)
						for _, lang in { "en", "fr" } do
							TvAudit.setLanguage(h, lang)
							round += 1
							local fr = lang == "fr"
							local label = `[{res.X}x{res.Y} {lang}] `
							expect(TvAudit.toGame(h)).toBe(true)
							inRanch()
							-- 1. Aperçu : △ → rail sur l'entrée de renaissance ; ✕ → onglet du Grand Splorch, maintien
							-- choisi ; R1 → Jelly Ascend, son maintien ; ✕ tenu 3 s → carte, « Oui » choisi après la
							-- garde ; ○ = « Plus tard » : carte ET aperçu fermés, retour sur l'entrée du rail
							tap(Y)
							local entry = PC.entryButton("SplorchPreview")
							expect(nm(sel())).toBe(nm(entry))
							tap(A)
							expect(PC.current()).toBe("SplorchPreview")
							expect(SP.currentTab()).toBe("splorch")
							local parts = SP._v2()
							expect(nm(sel())).toBe(nm(parts.hold))
							check(label .. "[aperçu/splorch] ")
							tap(R1)
							expect(SP.currentTab()).toBe("ascend")
							expect(nm(sel())).toBe(nm(parts.ascendHold))
							check(label .. "[aperçu/ascend] ")
							Gamepad.press(h, A)
							S.run(c, 3.2)
							expect(SP._state().card).toBe(true)
							Gamepad.release(h, A)
							S.run(c, 1.0)
							expect(SP._state().cardActive).toBe(true)
							expect(nm(sel())).toBe(nm(SP._v2().yes))
							check(label .. "[carte Prêt à monter ?] ")
							tap(B)
							expect(SP._state().card).toBe(false)
							expect(PC.isOpen("SplorchPreview")).toBe(false)
							expect(PC.menuOpen()).toBe(true)
							expect(nm(sel())).toBe(nm(entry))
							-- l'aperçu rouvert : ○ → le rail, sur l'entrée
							tap(A)
							expect(PC.current()).toBe("SplorchPreview")
							tap(B)
							expect(PC.current()).toBeNil()
							expect(nm(sel())).toBe(nm(entry))
							-- 2. Mon style : Ranch, R1 jusqu'à « Mon style » (l'habillage équipé choisi) ; ○ → sortes ;
							-- ↓ → Déco perso ; ✕ → emplacement 1 ; ✕ → choix (« Aucun » choisi) ; ○ → emplacement ;
							-- ○ → sortes ; ○ → rail
							expect(toEntry("Ranch")).toBe(true)
							tap(A)
							expect(PC.current()).toBe("Ranch")
							for _ = 1, 8 do
								if Ranch.currentTab() == "style" then
									break
								end
								tap(R1)
							end
							expect(Ranch.currentTab()).toBe("style")
							local strip = PC.window("Ranch").Body.Tabs.Strip
							expect(strip.Tab_style.Label.Text).toBe(if fr then "Mon style" else "My style")
							expect(strip.Tab_pads.Visible).toBe(false)
							expect(nm(sel())).toBe(nm(Ranch._styleCell("theme", "color")))
							check(label .. "[Mon style] ")
							tap(B)
							expect(nm(sel())).toBe(nm(Ranch._styleKindButton("theme")))
							tap(DOWN)
							expect(nm(sel())).toBe(nm(Ranch._styleKindButton("deco")))
							tap(A)
							expect(nm(sel())).toBe(nm(Ranch._decoSlot(1)))
							check(label .. "[plan de Déco perso] ")
							tap(A)
							expect(Ranch._state().pickerSlot).toBe(1)
							-- le choix s'ouvre sur l'objet posé dans l'emplacement (« Aucun » quand il est vide)
							local placed = nil
							for _, e in Ranch._styleEntries() do
								if e.equipped then
									placed = e
								end
							end
							expect(placed ~= nil and placed.n).toBe(1)
							expect(nm(sel())).toBe(nm(Ranch._styleCell(placed.kind, placed.id)))
							check(label .. "[choix de Déco perso] ")
							tap(B)
							expect(nm(sel())).toBe(nm(Ranch._decoSlot(1)))
							tap(B)
							expect(nm(sel())).toBe(nm(Ranch._styleKindButton("deco")))
							tap(B)
							expect(PC.current()).toBeNil()
							expect(PC.menuOpen()).toBe(true)
							-- 3. Records : Squishydex (rouvert sur les Espèces), L1 → Records, la liste choisie ;
							-- ↓ rebondit, ↑ → l'onglet ; ○ → rail
							expect(toEntry("Squishydex")).toBe(true)
							tap(A)
							expect(PC.current()).toBe("Squishydex")
							expect(Dex.currentTab()).toBe("species")
							tap(L1)
							expect(Dex.currentTab()).toBe("records")
							local dexBody = PC.window("Squishydex").Body
							expect(nm(sel())).toBe(nm(dexBody.Page_records.Records))
							check(label .. "[Records] ")
							tap(DOWN)
							expect(nm(sel())).toBe(nm(dexBody.Page_records.Records))
							tap(UP)
							expect(nm(sel())).toBe(nm(dexBody.Tabs.Strip.Tab_records))
							tap(B)
							expect(PC.current()).toBeNil()
							-- 4. Objectifs (rouverts sur le dernier onglet vu) : R1 jusqu'à « Cette semaine » (1er palier),
							-- R1 → Carnet (1re case) ; ○ → rail
							expect(toEntry("Objectives")).toBe(true)
							tap(A)
							expect(PC.current()).toBe("Objectives")
							for _ = 1, 6 do
								tap(R1)
								if Obj.currentTab() == "track" then
									break
								end
							end
							expect(Obj.currentTab()).toBe("track")
							local goals = PC.window("Objectives").Body
							expect(nm(sel())).toBe(nm(goals.Page_track.Tier1))
							check(label .. "[Cette semaine] ")
							tap(R1)
							expect(Obj.currentTab()).toBe("carnet")
							expect(nm(sel())).toBe(nm(goals.Page_carnet.Cell1))
							check(label .. "[Carnet] ")
							tap(B)
							expect(PC.current()).toBeNil()
							-- 5. Réglages : le 1er interrupteur choisi ; ↓ jusqu'à « Montrer mon halo » ; ✕ →
							-- SetSetting("haloOn", false) ; ○ → rail
							expect(toEntry("Settings")).toBe(true)
							tap(A)
							expect(PC.current()).toBe("Settings")
							local firstToggle = sel()
							expect(firstToggle ~= nil and firstToggle.Name).toBe("Toggle")
							local haloText = if fr then "Montrer mon halo" else "Show my halo"
							-- la ligne de la sélection (1er parent qui porte un libellé direct) dit « Montrer mon halo »
							local function onHalo()
								local cur = sel()
								for _ = 1, 3 do
									cur = cur and cur.Parent
									if cur == nil then
										return false
									end
									local labelled = false
									for _, d in cur:GetChildren() do
										if d:IsA("TextLabel") and d.Text ~= "" then
											labelled = true
											if d.Text == haloText then
												return true
											end
										end
									end
									if labelled then
										return false
									end
								end
								return false
							end
							for _ = 1, 10 do
								if onHalo() then
									break
								end
								tap(DOWN)
							end
							expect(onHalo()).toBe(true)
							check(label .. "[Réglages, halo] ")
							local before = #TvAudit.sent(h, "SetSetting")
							tap(A)
							local sets = TvAudit.sent(h, "SetSetting")
							expect(#sets).toBe(before + 1)
							expect(sets[#sets][1]).toBe("haloOn")
							expect(sets[#sets][2]).toBe(false)
							tap(B)
							expect(PC.current()).toBeNil()
							tap(B)
							expect(FG.anyOpen()).toBe(false)
							-- 6. Carte v2.0 rangée dans « ! » : △ → rail, ↓ → « ! », ✕ → carte rouverte (« Voir »
							-- choisi), ✕ → Objectifs › Cette semaine ; ○ → rail ; ○ → jeu
							h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
								kind = "trackTier",
								data = { tier = round, reward = "confetti" },
							})
							h:settle(1)
							c.Clock.advance(8.01)
							Cards._step()
							TvAudit.tick(h, 0.2)
							expect(#Cards.pending()).toBe(1)
							tap(Y)
							expect(PC.menuOpen()).toBe(true)
							expect(toEntry("Pending")).toBe(true)
							tap(A)
							expect(Cards.current() ~= nil and Cards.current().kind).toBe("trackTier")
							local buttons = Cards.buttons()
							expect(nm(sel())).toBe(nm(buttons[1]))
							expect(buttons[1].Label.Text).toBe(if fr then "Voir" else "See")
							check(label .. "[carte rouverte] ")
							tap(A)
							expect(PC.current()).toBe("Objectives")
							expect(Obj.currentTab()).toBe("track")
							expect(#Cards.pending()).toBe(0)
							tap(B)
							expect(PC.current()).toBeNil()
							tap(B)
							expect(FG.anyOpen()).toBe(false)
							-- 7. Jumelles : devant le portail du voisin, □ → fenêtre (le cœur choisi) ; ✕ → un
							-- GiveHeart(voisin) ; ○ → jeu
							h:moveTo(h.localPlayer, WorldLayout.gateOutside(2))
							S.run(c, 0.3)
							local target = Prompt.current()
							expect(target ~= nil and target.kind).toBe("binoculars")
							tap(X)
							expect(Bino.isOpen()).toBe(true)
							expect(nm(sel())).toBe(nm(Bino.button()))
							check(label .. "[jumelles] ")
							local hearts = #TvAudit.sent(h, "GiveHeart")
							tap(A)
							local given = TvAudit.sent(h, "GiveHeart")
							expect(#given).toBe(hearts + 1)
							expect(given[#given][1]).toBe(OWNER)
							S.run(c, 3.5)
							tap(B)
							expect(Bino.isOpen()).toBe(false)
							expect(FG.anyOpen()).toBe(false)
						end
					end
					expect(table.concat(issues, "\n")).toBe("")
					-- intentions de toute la promenade : un cœur et un halo par tour, rien d'autre
					expect(#TvAudit.sent(h, "JellyAscend")).toBe(0)
					expect(#TvAudit.sent(h, "GrandSplorch")).toBe(0)
					expect(#TvAudit.sent(h, "PlaceDeco")).toBe(0)
					expect(#TvAudit.sent(h, "EquipCosmetic")).toBe(0)
					expect(#TvAudit.sent(h, "GiveHeart")).toBe(round)
					S.clean(c, expect)
				end
			)
		end
	)

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
