--!nocheck
-- Relecture des écrans et de la manette du lot B4 (ranch qui évolue et monde v2.0) : défauts trouvés en
-- regardant les captures de l'outil d'écrans (tools/screens, groupe « world », tv1080, tv720, tv2160, FR
-- et EN) et en jouant les flux du lot à la manette sur le vrai client console ; chaque cas montré rouge
-- avant sa correction (docs/04 §27.12, lignes B4-83 et suivantes). Interrupteurs v2.0 ouverts DANS le
-- test (instantané fabriqué de l'écran Améliorations). Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local UpgradeScreen = require("../harness/UpgradeScreen")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	local function tap(c, key)
		Gamepad.tap(c.h, key)
		TvAudit.tick(c.h, 0.5)
	end

	local function selected(c)
		return c.h.game.GuiService.SelectedObject
	end

	-- Client console avec l'instantané de l'écran Améliorations (kiosque construit), personnage à 5 studs
	-- du comptoir du kiosque de Big Plop : invite □ « Atelier »
	local function atKiosk()
		local c = S.client({ snap = S.snap(1) })
		local h = c.h
		c.WV = TvAudit.mod(h, "Render.WorldV2")
		c.Prompts = TvAudit.mod(h, "Controllers.PromptController")
		c.Plates = TvAudit.mod(h, "UI.Prompt")
		pcall(TvAudit.mod(h, "Controllers.LightingController").refresh)
		TvAudit.tick(h, 0.6)
		local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		h:moveTo(h.localPlayer, WorldLayout.plaza("kiosk") + Vector3.new(4, 3, -3))
		TvAudit.tick(h, 0.6)
		return c
	end

	-- Défaut 1 (B4-83) : □ sur le kiosque ouvrait l'écran Améliorations PAR le menu (PanelController.open
	-- ouvre toujours le rail dessous) : ○ ramenait au rail du menu (entrée « Améliorations » sélectionnée,
	-- invite du kiosque cachée derrière la fenêtre), il fallait un 2e ○ pour revenir au jeu. GDD §10.6,
	-- table de navigation : Améliorations, ○ « → ce qui l'a ouvert (menu, aperçu du Grand Splorch, jeu) »,
	-- et règle 4 « Fermer une fenêtre rend la sélection à ce qui l'a ouverte (le bouton du menu), ou au jeu ».
	describe("Review_B4_screens › kiosque de Big Plop à la manette (GDD §10.6, §11.1)", function()
		it(
			"□ ouvre l'Atelier sans achat ni changement de mode ; ○ rend la main au jeu en un appui",
			function()
				local c = atKiosk()
				expect(c.WV.kioskOpen()).toBe(true)
				local t = c.Prompts.current()
				expect(t ~= nil and t.kind).toBe("kiosk")
				expect(#c.Plates.plates()).toBe(1)
				-- □ : l'écran s'ouvre sur l'Atelier, 1re ligne sélectionnée ; le relâchement de □ (le mode de l'écran
				-- est aussi sur □) ne change pas le mode
				Gamepad.press(c.h, Enum.KeyCode.ButtonX)
				TvAudit.tick(c.h, 0.6)
				Gamepad.release(c.h, Enum.KeyCode.ButtonX)
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.isOpen("Upgrades")).toBe(true)
				expect(c.Up.currentTab()).toBe("workshop")
				expect(c.Up.mode()).toBe(1)
				local first = c.Up._row(c.Up._shown("workshop")[1])
				expect(first ~= nil).toBe(true)
				expect(selected(c)).toBe(first)
				-- ○ : écran ET rail fermés, aucune sélection (le stick fait marcher), l'invite revient
				tap(c, Enum.KeyCode.ButtonB)
				expect(c.PC.isOpen("Upgrades")).toBe(false)
				expect(table.concat(c.FG.names(), ",")).toBe("")
				expect(selected(c)).toBe(nil)
				TvAudit.tick(c.h, 0.6)
				t = c.Prompts.current()
				expect(t ~= nil and t.kind).toBe("kiosk")
				expect(#c.Plates.plates()).toBe(1)
				-- □ de nouveau : l'Atelier se rouvre, mode revenu à ×1
				tap(c, Enum.KeyCode.ButtonX)
				expect(c.PC.isOpen("Upgrades")).toBe(true)
				expect(c.Up.currentTab()).toBe("workshop")
				expect(c.Up.mode()).toBe(1)
				tap(c, Enum.KeyCode.ButtonB)
				expect(table.concat(c.FG.names(), ",")).toBe("")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"ouvert depuis le menu : ○ revient au rail (inchangé) ; depuis le kiosque puis R2 : ○ revient au rail",
			function()
				local c = atKiosk()
				-- menu ouvert d'abord (△), puis l'écran : ○ revient au bouton du rail
				c.PC.openMenu("Upgrades")
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Upgrades")
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.isOpen("Upgrades")).toBe(true)
				tap(c, Enum.KeyCode.ButtonB)
				expect(c.PC.isOpen("Upgrades")).toBe(false)
				expect(c.FG.isOpen("menu")).toBe(true)
				expect(selected(c) ~= nil and selected(c).Name).toBe("Entry_Upgrades")
				tap(c, Enum.KeyCode.ButtonB)
				expect(table.concat(c.FG.names(), ",")).toBe("")
				TvAudit.tick(c.h, 0.6)
				-- kiosque, puis R2 (panneau suivant : on navigue dans le menu) : ○ revient au rail de ce panneau
				tap(c, Enum.KeyCode.ButtonX)
				expect(c.PC.isOpen("Upgrades")).toBe(true)
				tap(c, Enum.KeyCode.ButtonR2)
				local other = c.PC.current()
				expect(other ~= nil and other ~= "Upgrades").toBe(true)
				tap(c, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBe(nil)
				expect(c.FG.isOpen("menu")).toBe(true)
				expect(selected(c) ~= nil and selected(c).Name).toBe("Entry_" .. tostring(other))
				tap(c, Enum.KeyCode.ButtonB)
				expect(table.concat(c.FG.names(), ",")).toBe("")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)
	end)
end
