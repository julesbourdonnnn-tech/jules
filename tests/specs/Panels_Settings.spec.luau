--!nocheck
-- Panels/Settings (paquet client-panels ; GDD §10.3 ; docs/04 §13.6) : interrupteurs (SetSetting),
-- mode Rush / Cozy (SetMode), choix (emote débloquée, langue), Clips caché si ClipsUnavailable,
-- « BOOP RUSH autorisé » pour le propriétaire d'un serveur privé seulement, Diagnostics pour les
-- administrateurs (après le « bonjour »), message du sommeil en bas, 1er interrupteur par défaut.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup(opts)
		local h = TvAudit.client(opts or {})
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			Settings = TvAudit.mod(h, "UI.Panels.Settings"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function keys(c)
		local out = {}
		for _, item in c.Settings._items() do
			table.insert(out, item.key)
		end
		return out
	end

	-- ligne d'un réglage (amenée à l'écran : la liste est virtualisée)
	local function rowFor(c, key)
		local control = c.Settings._controlFor(key)
		return if control then control.Parent else nil
	end

	describe("Panels/Settings", function()
		it(
			"lignes dans l'ordre du GDD ; 1er interrupteur par défaut ; ✕ envoie SetSetting(clé, valeur)",
			function()
				local c = setup()
				c.PC.open("Settings")
				expect(keys(c)).toEqual({
					"mode",
					"hideName",
					"receiveGifts",
					"clips",
					"reducedMotion",
					"lowGraphics",
					"music",
					"sfx",
					"vibration",
					"emoteLeft",
					"lang",
				})
				local row = rowFor(c, "hideName")
				expect(c.h.game.GuiService.SelectedObject).toBe(row.Toggle)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				local args = TvAudit.sent(c.h, "SetSetting")[1]
				expect(args[1]).toBe("hideName")
				expect(args[2]).toBe(true)
				-- le profil répliqué fait foi : sans DataPatch, l'interrupteur revient à sa valeur
				expect(c.PC.window("Settings").Body.SleepNote.Text).toBe(
					"Your squishies grow even while you sleep"
				)
				clean(c)
			end
		)

		it("mode Rush / Cozy → SetMode ; langue en boucle ; emote verrouillée absente du choix", function()
			local c = setup()
			c.PC.open("Settings")
			TvAudit.tick(c.h, 0.5)
			local mode = rowFor(c, "mode")
			c.h.game.GuiService.SelectedObject = mode.Choice
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(TvAudit.sent(c.h, "SetMode")[1][1]).toBe(true) -- Cozy → Rush
			local lang = rowFor(c, "lang")
			TvAudit.tick(c.h, 0.5)
			c.h.game.GuiService.SelectedObject = lang.Choice
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			local args = TvAudit.sent(c.h, "SetSetting")[1]
			expect(args[1]).toBe("lang")
			expect(args[2]).toBe("en")
			-- seule l'emote Bravo est débloquée : choix refusé sans envoi
			local emote = rowFor(c, "emoteLeft")
			TvAudit.tick(c.h, 0.5)
			c.h.game.GuiService.SelectedObject = emote.Choice
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(#TvAudit.sent(c.h, "SetSetting")).toBe(1)
			clean(c)
		end)

		it(
			"Clips caché sans capture vidéo ; « BOOP RUSH autorisé » pour le propriétaire du serveur privé",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("ClipsUnavailable", true)
				c.PC.open("Settings")
				expect(table.find(keys(c), "clips")).toBeNil()
				expect(table.find(keys(c), "allowRush")).toBeNil()
				local c2 = setup({
					before = function(h)
						h.game.PrivateServerOwnerId = 1 -- le joueur local (UserId 1)
					end,
				})
				c2.PC.open("Settings")
				expect(table.find(keys(c2), "allowRush") ~= nil).toBe(true)
				clean(c)
				clean(c2)
			end
		)

		it(
			"Diagnostics : seulement après le « bonjour » ; ✕ l'ouvre par-dessus, ○ revient aux Réglages",
			function()
				local c = setup()
				c.PC.open("Settings")
				expect(c.Settings._controlFor("diagnostics")).toBeNil()
				c.PC.closeAll()
				c.h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Settings")
				expect(table.find(keys(c), "diagnostics")).toBeNil() -- bouton fixe, hors de la liste
				local target = c.Settings._controlFor("diagnostics")
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = target
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.PC.current()).toBe("Diagnostics")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBe("Settings")
				expect(c.h.game.GuiService.SelectedObject).toBe(target)
				clean(c)
			end
		)
	end)
end
