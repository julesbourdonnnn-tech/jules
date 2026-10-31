--!nocheck
-- Console PS5 : validation de publication (notes croisées des groupes G1-G3, docs/07-console-ps5.md
-- §6.3-§6.5, §9.1) sur le VRAI client démarré en console, manette seule :
--   * □ (ButtonX) panneau ouvert : absorbé sans Dash, comme R2 ; panneau fermé : □ rend le Dash ;
--     le clavier (Maj) garde le Dash panneau ouvert ;
--   * △ dans un panneau ouvert depuis le rail : tout se ferme et AUCUNE sélection n'est rendue au rail,
--     ni tout de suite ni après l'animation de fermeture (seul ○ / back() la rend) ;
--   * Supernova confirmée à ✕ panneau ouvert : « holdStart » au maintien, puis UNE seule vibration
--     « supernova » (celle d'InputController à l'arrivée de Celebrate), pas de doublon du panneau ;
--   * pings à emote (2 « point », 4 « cheer », 6 « wave ») envoyés à la croix en anneau : Humanoid:
--     PlayEmote est une vraie méthode Roblox (ApiAudit sans écart) et reçoit le bon nom d'emote.
--   * API Roblox auditée (ApiAudit) : 0 écart ; 0 erreur, 0 avertissement.
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local K = Enum.KeyCode

	-- Client console complet (Main.client), accueil terminé ; sons et vibrations journalisés
	local function boot(snapshot)
		local h = Harness.new({ mode = "client", console = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = { h = h, Clock = Clock, sounds = {}, played = {} }
		local Audio = h:require(CLIENT .. "Controllers.AudioController")
		local play = Audio.play
		Audio.play = function(name, ...)
			table.insert(c.sounds, name)
			return play(name, ...)
		end
		ApiAudit.start()
		h:boot()
		local data = { glow = 5, onboarding = { step = 8, p = 0 } }
		for k, v in snapshot or {} do
			data[k] = v
		end
		h:fireClient(REMOTES .. "DataSnapshot", data)
		h:step(1 / 60, 30)
		h:settle(3)
		c.PC = h:require(CLIENT .. "Controllers.PanelController")
		c.Input = h:require(CLIENT .. "Controllers.InputController")
		c.WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local Haptics = h:require(CLIENT .. "Util.Haptics")
		Haptics.Played:Connect(function(name)
			table.insert(c.played, name)
		end)
		table.clear(c.sounds)
		return c
	end

	local function finish(c)
		expect(table.concat(ApiAudit.stop(), "\n")).toBe("")
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function frames(c, n)
		for _ = 1, n or 3 do
			c.Clock.advance(1 / 30)
			c.h:step(1 / 30, 1)
		end
		c.h:settle(1)
	end

	local function sent(c, remote)
		local out = {}
		for _, e in c.h.log.serverEvents do
			if e.remote == remote then
				table.insert(out, e.args)
			end
		end
		return out
	end

	local function count(list, value)
		local n = 0
		for _, v in list do
			if v == value then
				n += 1
			end
		end
		return n
	end

	local function selected(c)
		return Gamepad.selected(c.h)
	end

	-- △ puis bouton Améliorer du rail sélectionné, ✕ : panneau ouvert depuis le rail (origine connue)
	local function openFromRail(c)
		local railUpgrades = c.h.localPlayer.PlayerGui.HUD.Safe.Rail.Upgrades.Button
		expect(Gamepad.tap(c.h, K.ButtonY)).toBe("CC_Rail")
		c.h.game.GuiService.SelectedObject = railUpgrades
		frames(c, 2)
		Gamepad.tap(c.h, K.ButtonA)
		frames(c, 8)
		expect(c.PC.current()).toBe("Upgrades")
		return railUpgrades
	end

	-- Joueur dans le port sûr de son Nid (Supernova autorisée)
	local function goHome(c)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", 1)
		local gate = c.WorldLayout.gateCFrame(1).Position
		me.Character.HumanoidRootPart.CFrame = CFrame.new(gate.X, 3, gate.Z)
	end

	-- Roue ouverte à la croix ↑ ; `steps` appuis en anneau (→ positif, ← négatif ; le 1er vise le
	-- secteur 1) ; ✕ envoie le secteur visé
	local function pingByRing(c, steps)
		expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
		local key = if steps >= 0 then K.DPadRight else K.DPadLeft
		expect(Gamepad.tap(c.h, K.DPadRight)).toBe("CC_PingNav")
		for _ = 2, math.abs(steps) do
			expect(Gamepad.tap(c.h, key)).toBe("CC_PingNav")
		end
		expect(Gamepad.tap(c.h, K.ButtonA)).toBe("CC_PingConfirm")
		c.h:settle(2)
		c.Clock.advance(2) -- débit des pings : 1 / 1,5 s
	end

	describe("Console › validation de publication (notes croisées G1-G3)", function()
		it(
			"□ panneau ouvert : absorbé sans Dash (comme R2) ; panneau fermé : Dash ; Maj garde le Dash",
			function()
				local c = boot()
				expect(c.Input.openPanel("Upgrades")).toBe(true)
				frames(c, 8)
				expect(c.PC.current()).toBe("Upgrades")
				-- □ : absorbé, rien d'envoyé, le panneau reste ouvert
				expect(Gamepad.tap(c.h, K.ButtonX)).toBe("CC_Dash")
				expect(#sent(c, "Dash")).toBe(0)
				expect(c.PC.current()).toBe("Upgrades")
				-- R2 : panneau suivant (PanelController), jamais de Dash
				expect(Gamepad.tap(c.h, K.ButtonR2)).toBe("PanelNext")
				frames(c, 4)
				expect(#sent(c, "Dash")).toBe(0)
				-- clavier panneau ouvert : Maj garde le Dash (WASD fait toujours marcher)
				local shift = Gamepad.input(K.LeftShift, Enum.UserInputState.Begin)
				shift.UserInputType = Enum.UserInputType.Keyboard
				expect(Gamepad.dispatch(c.h, K.LeftShift, Enum.UserInputState.Begin, shift)).toBe("CC_Dash")
				expect(#sent(c, "Dash")).toBe(1)
				-- △ ferme tout ; □ rend le Dash (après la recharge)
				expect(Gamepad.tap(c.h, K.ButtonY)).toBe("CC_Rail")
				frames(c, 8)
				expect(c.PC.current()).toBeNil()
				c.Clock.advance(30)
				expect(Gamepad.tap(c.h, K.ButtonX)).toBe("CC_Dash")
				expect(#sent(c, "Dash")).toBe(2)
				finish(c)
			end
		)

		it(
			"△ dans un panneau ouvert depuis le rail : aucune sélection rendue, même après l'animation",
			function()
				local c = boot()
				local rail = openFromRail(c)
				expect(selected(c) ~= nil and selected(c) ~= rail).toBe(true)
				expect(Gamepad.tap(c.h, K.ButtonY)).toBe("CC_Rail")
				expect(c.PC.current()).toBeNil()
				expect(selected(c)).toBeNil()
				-- fin de l'animation de fermeture et tâches différées : toujours rien de sélectionné
				frames(c, 30)
				expect(selected(c)).toBeNil()
				-- contrôle : ○ (back) rend bien la sélection au bouton du rail d'origine
				openFromRail(c)
				expect(Gamepad.tap(c.h, K.ButtonB)).toBe("PanelBack")
				frames(c, 30)
				expect(c.PC.current()).toBeNil()
				expect(selected(c)).toBe(rail)
				finish(c)
			end
		)

		it(
			"Supernova confirmée à ✕ : « holdStart » puis une seule vibration « supernova »",
			function()
				local c = boot({ glow = 10 ^ 12 })
				goHome(c)
				c.PC.open("Supernova")
				frames(c, 8)
				expect(c.PC.current()).toBe("Supernova")
				expect(selected(c).Name).toBe("Hold")
				c.Clock.advance(1)
				table.clear(c.played)
				Gamepad.press(c.h, K.ButtonA)
				frames(c, 40)
				Gamepad.release(c.h, K.ButtonA)
				frames(c, 4)
				expect(#sent(c, "Supernova")).toBe(1)
				-- le serveur célèbre la Supernova du héros
				c.h:fireClient(REMOTES .. "Celebrate", { kind = "supernova", data = { level = 1 } })
				c.h:settle(2)
				frames(c, 30)
				expect(count(c.played, "holdStart")).toBe(1)
				expect(count(c.played, "supernova")).toBe(1)
				finish(c)
			end
		)

		it("pings à emote 2, 4 et 6 à la croix : Humanoid:PlayEmote audité, bons noms d'emote", function()
			local c = boot()
			-- PlayEmote du harnais absent (comme une emote non équipée) : l'appel protégé ne casse
			-- rien et la lecture du membre est une vraie méthode Roblox pour l'audit
			pingByRing(c, 2)
			pingByRing(c, 4)
			pingByRing(c, -2) -- 1 puis ← : secteur 6
			local kinds = {}
			for _, args in sent(c, "Ping") do
				table.insert(kinds, args[1])
			end
			expect(kinds).toEqual({ 2, 4, 6 })
			-- emotes réellement demandées au personnage
			local played = {}
			local humanoid = c.h.localPlayer.Character.Humanoid
			humanoid.PlayEmote = function(_, name)
				table.insert(played, name)
				return true
			end
			pingByRing(c, 2)
			pingByRing(c, 4)
			pingByRing(c, -2)
			expect(played).toEqual({ "point", "cheer", "wave" })
			expect(#sent(c, "Ping")).toBe(6)
			finish(c)
		end)
	end)
end
