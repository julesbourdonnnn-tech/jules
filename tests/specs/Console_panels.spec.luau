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

	describe("Console_panels › clavier et souris (second)", function()
		it(
			"clic = ✕, Retour arrière = ○, libellés des touches du clavier ; aucune touche manette affichée",
			function()
				local h = richClient({ console = false })
				local PC = TvAudit.mod(h, "UI.PanelController")
				local FG = TvAudit.mod(h, "UI.FocusGuard")
				PC.toggleMenu()
				-- clic sur l'entrée Ranch du rail
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
