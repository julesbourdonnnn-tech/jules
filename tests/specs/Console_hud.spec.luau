--!nocheck
-- Console_hud (paquet client-hud ; couche d, docs/04 §14, §17.1 d ; GDD §10.3, §10.4, §10.6) : PS5 sur
-- télé, manette seule : la carte « booped » est atteinte par △ → ✕ (entrée « ! ») → « Pas ce joueur »
-- avec la croix, ✕ et ○ seulement, puis ○ rend la main au jeu ; parcours à 3 touches depuis croix ↓
-- (InputController) sans faute ; glyphes PlayStation sur le HUD, la carte et les invites du monde ;
-- aucune touche du jeu derrière une fenêtre ; textes du monde ≥ 28 px TV à 20 studs aux 3 résolutions ;
-- clavier : la puce Menu montre la touche « M » de la disposition (AZERTY : Semicolon). Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local MockInstance = require("../harness/MockInstance")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local DONE = { step = 11, done = true, demoDone = true }

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(opts)
		opts = opts or {}
		local profile = opts.profile or {}
		profile.onboarding = profile.onboarding or DONE
		local h = TvAudit.client({ profile = profile, console = opts.console, before = opts.before })
		h:moveTo(h.localPlayer, Vector3.new(0, 3, 0))
		return h
	end

	describe("Console_hud › manette seule", function()
		it(
			"carte « booped » : △ → ✕ → croix → → ✕ « Pas ce joueur » ; ○ rend la main au jeu",
			function()
				local h = setup()
				local FG = TvAudit.mod(h, "UI.FocusGuard")
				local C = TvAudit.mod(h, "UI.Cards")
				h:fireClient(
					"ReplicatedStorage.Remotes.Celebrate",
					{ kind = "booped", data = { uid = "u5", species = 2, booperId = 77 } }
				)
				h:settle(1)
				-- la carte s'affiche sans prendre la sélection : le stick fait toujours marcher
				expect(h.game.GuiService.SelectedObject).toBeNil()
				expect(C.current().kind).toBe("booped")
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonY) -- △ (lié par InputController)
				expect(FG.isOpen("menu")).toBe(true)
				local PC = TvAudit.mod(h, "UI.PanelController")
				expect(h.game.GuiService.SelectedObject).toBe(PC.entryButton("Pending"))
				expect(table.concat(TvAudit.check(h, "menu : "), "\n")).toBe("")
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonA) -- ✕ sur « ! »
				local card = C.current()
				expect(card.kind).toBe("booped")
				expect(FG.isOpen("card:" .. card.id)).toBe(true)
				expect(table.concat(TvAudit.check(h, "carte : "), "\n")).toBe("")
				expect(h.game.GuiService.SelectedObject.Label.Text).toBe("Continue")
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.DPadRight)
				expect(h.game.GuiService.SelectedObject.Label.Text).toBe("Not this player")
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				expect(TvAudit.sent(h, "RefuseBooper")[1][1]).toBe(77)
				expect(FG.isOpen("card:" .. card.id)).toBe(false)
				expect(TvAudit.toGame(h)).toBe(true)
				expect(h.game.GuiService.SelectedObject).toBeNil()
				expect(TvAudit.mod(h, "Controllers.InputController").gameBound()).toBe(true)
				clean(h)
			end
		)

		it(
			"parcours à 3 touches depuis croix ↓ (InputController) : aucune faute, ○ revient toujours",
			function()
				local profile = TvAudit.richProfile()
				profile.onboarding = DONE
				local h = setup({ profile = profile })
				local report = TvAudit.walk(h)
				expect(table.concat(report.issues, "\n")).toBe("")
				local n = 0
				for _ in report.screens do
					n += 1
				end
				expect(n >= 10).toBe(true)
				clean(h)
			end
		)

		it("glyphes PlayStation sur le HUD, la carte et les invites du monde ; aucune lettre Xbox", function()
			local h = setup()
			local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
			WSC.event = function()
				return {
					features = {
						boopRush = "on",
						megaSquish = true,
						golden = true,
						jellyMoon = true,
						gauge = true,
					},
					boost = { kind = "", untilT = 0, byName = "" },
					gauge = { points = 0, target = 1, partyUntil = 0, restUntil = 0 },
					spectacle = { queue = {} },
				}
			end
			TvAudit.mod(h, "Controllers.ChaseController").cooldownLeft = function()
				return 1
			end
			TvAudit.mod(h, "Controllers.PromptController").current = function()
				return {
					kind = "squishy",
					slot = 1,
					uid = "u1",
					primary = "press",
					secondary = "pickup",
					ready = true,
					position = Vector3.new(0, 2, -6),
				}
			end
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "sleepy", data = { minutes = 60 } })
			h:fireClient("ReplicatedStorage.Remotes.ClapPrompt", { heroId = 5, endsAt = 1800000008 })
			h:settle(1)
			TvAudit.mod(h, "UI.HUD")._refresh()
			TvAudit.mod(h, "UI.Prompt")._step()
			local gui = h.localPlayer.PlayerGui
			expect(table.concat(TvAudit.glyphs(h, gui.HUD), "\n")).toBe("")
			expect(table.concat(TvAudit.glyphs(h, gui.Cards), "\n")).toBe("")
			local chip = TvAudit.mod(h, "UI.HUD").element("menuChip")
			expect(chip.Glyph:GetAttribute("GlyphKey")).toBe("ButtonY")
			expect(chip.Glyph:GetAttribute("GlyphMode")).toBe("image")
			-- invites du monde : icônes PlayStation (BillboardGui hors de PlayerGui, vérifiées une à une)
			for _, plate in TvAudit.mod(h, "UI.Prompt").plates() do
				local g = plate.Glyph
				expect(g:GetAttribute("GlyphMode")).toBe("image")
				expect(string.find(g.Image.Image, Gamepad.PS_GLYPHS, 1, true)).toBe(1)
			end
			clean(h)
		end)

		it("textes du monde ≥ 28 px TV à 20 studs en 1920 × 1080, 3840 × 2160 et 1280 × 720", function()
			local h = setup()
			local L = h:require("ReplicatedStorage.Shared.Config.Layout")
			local WT = TvAudit.mod(h, "UI.WorldText")
			TvAudit.mod(h, "Controllers.PromptController").current = function()
				return {
					kind = "pad",
					slot = 1,
					uid = "",
					tile = "snack",
					primary = "buy",
					secondary = "",
					ready = true,
					position = Vector3.new(4, 1, -8),
				}
			end
			for _, res in L.TestResolutions do
				local vp = Vector2.new(res.X, res.Y)
				TvAudit.setResolution(h, vp)
				local P = TvAudit.mod(h, "UI.Prompt")
				P._step()
				for _, gui in P.guis() do
					expect(WT.projectedPx(gui, vp) >= L.WorldText.MinProjected).toBe(true)
				end
			end
			clean(h)
		end)
	end)

	describe("Console_hud › clavier et souris (second)", function()
		it(
			"puce Menu : la touche « M » (QWERTY), Semicolon en AZERTY ; jamais un glyphe de manette",
			function()
				local h = setup({ console = false })
				local chip = TvAudit.mod(h, "UI.HUD").element("menuChip")
				expect(chip.Glyph:GetAttribute("GlyphKey")).toBe("M")
				expect(chip.Glyph:GetAttribute("GlyphMode")).toBe("text")
				clean(h)
				-- AZERTY : la touche marquée « M » est KeyCode.Semicolon ; KeyCode.M s'écrit « , »
				local h2 = setup({
					console = false,
					before = function()
						local orig = MockInstance.classMethods.UserInputService.GetStringForKeyCode
						MockInstance.classMethods.UserInputService.GetStringForKeyCode = function(self, kc)
							if kc == Enum.KeyCode.Semicolon then
								return "M"
							elseif kc == Enum.KeyCode.M then
								return ","
							end
							return orig(self, kc)
						end
					end,
				})
				local chip2 = TvAudit.mod(h2, "UI.HUD").element("menuChip")
				expect(chip2.Glyph:GetAttribute("GlyphKey")).toBe("Semicolon")
				expect(chip2.Glyph.Text.Text).toBe("M")
				-- le menu s'ouvre aussi par cette touche
				Gamepad.dispatch(h2, Enum.KeyCode.Semicolon, Enum.UserInputState.Begin)
				expect(TvAudit.mod(h2, "UI.PanelController").menuOpen()).toBe(true)
				clean(h2)
			end
		)

		it("clic sur la puce Menu : ouvre le menu ; clic sur la carte affichée : la rouvre", function()
			local h = setup({ console = false })
			local HUD = TvAudit.mod(h, "UI.HUD")
			local C = TvAudit.mod(h, "UI.Cards")
			HUD.element("menuChip").Activated:Fire()
			h:settle(1)
			expect(TvAudit.mod(h, "UI.PanelController").menuOpen()).toBe(true)
			TvAudit.tick(h, 0.5)
			TvAudit.mod(h, "UI.PanelController").closeAll()
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "sleepy", data = { minutes = 60 } })
			h:settle(1)
			C.frame("side").Activated:Fire()
			h:settle(1)
			expect(TvAudit.mod(h, "UI.FocusGuard").isOpen("card:" .. C.current().id)).toBe(true)
			clean(h)
		end)
	end)
	-- =========================================================================================
	-- v2.0 (lot B2, étape 4 ; N9, D14-D17) : manette seule sur le HUD et le rail v2.0
	-- =========================================================================================
	describe("Console_hud › HUD et rail v2.0 (lot B2)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local NOW = 1800000000

		it(
			"manette seule : △ ouvre le rail sur l'entrée de renaissance, croix jusqu'à Améliorations, ✕ l'ouvre, ○ revient puis rend la main ; glyphes PlayStation, aucune lettre Xbox",
			function()
				local c = S.client({
					snap = S.snap(1, function(p)
						p.ascend = 1
						p.R = 3
						p.bestR = 15
					end),
					profile = {
						R = 3,
						squishies = { a = TvAudit.squishy(1, { z = 1e15 }) },
						growth = { G = 0, g = 0, t = NOW },
						onboarding = DONE,
					},
				})
				local h = c.h
				h:moveTo(h.localPlayer, Vector3.new(0, 3, 0))
				S.run(c, 0.5)
				local HUD = TvAudit.mod(h, "UI.HUD")
				HUD._refresh()
				-- puce PETIT SPLORCH ! avec △ (glyphe PlayStation)
				local chip = HUD.element("specialChip")
				expect(chip:GetAttribute("Mode")).toBe("petit")
				expect(chip.Glyph:GetAttribute("GlyphKey")).toBe("ButtonY")
				expect(chip.Glyph:GetAttribute("GlyphMode")).toBe("image")
				Gamepad.tap(h, Enum.KeyCode.ButtonY)
				S.run(c, 0.5)
				local PC = c.PC
				local entry = PC.entryButton("SplorchPreview")
				expect(PC.menuOpen()).toBe(true)
				expect(h.game.GuiService.SelectedObject).toBe(entry)
				-- maintien du Petit Splorch : glyphe ✕ de la manette sur l'entrée
				expect(entry.Glyph:GetAttribute("GlyphKey")).toBe("ButtonA")
				expect(entry.Glyph:GetAttribute("GlyphMode")).toBe("image")
				local gui = h.localPlayer.PlayerGui
				expect(table.concat(TvAudit.glyphs(h, gui.HUD), "\n")).toBe("")
				expect(table.concat(TvAudit.glyphs(h, gui.Menu), "\n")).toBe("")
				expect(table.concat(TvAudit.check(h, "rail v2 : "), "\n")).toBe("")
				-- croix ↓ : Ranch, puis Améliorations ; ✕ l'ouvre
				Gamepad.tap(h, Enum.KeyCode.DPadDown)
				Gamepad.tap(h, Enum.KeyCode.DPadDown)
				expect(h.game.GuiService.SelectedObject).toBe(PC.entryButton("Upgrades"))
				S.run(c, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				S.run(c, 0.5)
				expect(PC.current()).toBe("Upgrades")
				-- ○ revient au rail (sur Améliorations), ○ encore rend la main au jeu
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				S.run(c, 0.5)
				expect(PC.current()).toBeNil()
				expect(h.game.GuiService.SelectedObject).toBe(PC.entryButton("Upgrades"))
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				S.run(c, 0.5)
				expect(PC.menuOpen()).toBe(false)
				expect(TvAudit.toGame(h)).toBe(true)
				expect(#TvAudit.sent(h, "GrandSplorch")).toBe(0)
				S.clean(c, expect)
			end
		)
	end)
end
