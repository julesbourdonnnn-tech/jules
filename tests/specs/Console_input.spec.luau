--!nocheck
-- Console G1 « entrées, audio, vibrations » (docs/07-console-ps5.md §6, §9, §11) sur le VRAI client
-- démarré en console PS5 manette seule (Harness.new({ console = true }) + h:boot()) :
--   * R2 et □ (Carré) envoient le Dash ; L1 / R1 / L2 restent libres en jeu ;
--   * △ entre dans le menu du HUD (sélection) puis rend la main ; ○ rend la main ; △ panneau ouvert :
--     tout fermer, sélection effacée ; son « Back » à chaque retour ;
--   * croix ← : InputController.QuestToggled ;
--   * roue de pings : audit console vide, ○ (« PadGlyph » ButtonB, icône PlayStation) au centre à
--     la place du « ✕ » dessiné, repère ✕ « Envoyer », stick + ✕ envoie le Ping visé, croix ← / →
--     en anneau, ○ ferme (« Back ») ;
--   * son « Select » quand la sélection se déplace, pas à la pose initiale ni à l'effacement ;
--   * vibrations du jeu (Util/Haptics → h.log.haptics) : capture Épique, coupe subie, Comète,
--     Supernova du héros ; aucune au clavier-souris ni avec le réglage « Vibrations » coupé ;
--   * API Roblox auditée (ApiAudit) : 0 écart ; 0 erreur, 0 avertissement.
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local K = Enum.KeyCode

	-- Client complet démarré (console PS5 par défaut) avec un profil à l'accueil terminé (étape 8).
	-- Les sons joués sont journalisés (c.sounds), comme les vibrations jouées (c.played).
	local function boot(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = opts.pc ~= true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = { h = h, Clock = Clock, sounds = {}, played = {}, quest = 0 }
		local Audio = h:require(CLIENT .. "Controllers.AudioController")
		local play = Audio.play
		Audio.play = function(name, ...)
			table.insert(c.sounds, name)
			return play(name, ...)
		end
		if opts.audit ~= false then
			ApiAudit.start()
		end
		h:boot()
		local snapshot = { glow = 5, onboarding = { step = 8, p = 0 } }
		if opts.settings then
			snapshot.settings = opts.settings
		end
		h:fireClient(REMOTES .. "DataSnapshot", snapshot)
		h:step(1 / 60, 30)
		h:settle(3)
		c.Input = h:require(CLIENT .. "Controllers.InputController")
		c.Panels = h:require(CLIENT .. "Controllers.PanelController")
		c.Platform = h:require(CLIENT .. "Util.Platform")
		c.Haptics = h:require(CLIENT .. "Util.Haptics")
		c.Haptics.Played:Connect(function(name)
			table.insert(c.played, name)
		end)
		c.Input.QuestToggled:Connect(function()
			c.quest += 1
		end)
		table.clear(c.sounds)
		return c
	end

	-- Fin de test : API Roblox valide, ni erreur ni avertissement
	local function finish(c, audited)
		local issues = if audited == false then {} else ApiAudit.stop()
		expect(table.concat(issues, "\n")).toBe("")
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
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

	local function gui(c, name)
		return c.h.localPlayer.PlayerGui:FindFirstChild(name)
	end

	local function wheel(c)
		return gui(c, "PingWheel").Safe.Wheel
	end

	-- Une direction de la croix qui déplace la sélection courante (nil : aucune)
	local function movingDirection(c)
		Layout.apply(c.h)
		local selected = Gamepad.selected(c.h)
		for _, dir in { "Down", "Up", "Right", "Left" } do
			local nxt = Layout.step(c.h, selected, dir)
			if nxt ~= nil and nxt ~= selected then
				return K["DPad" .. dir]
			end
		end
		return nil
	end

	-- Monde minimal : le joueur local occupe le Nid 2 (sa file), un autre joueur le Nid 6
	local function world(c, wild)
		local h = c.h
		local PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec")
		h.localPlayer:SetAttribute("Slot", 2)
		h:fireClient(REMOTES .. "WorldSnapshot", {
			serverTime = T0,
			tick = 1,
			lines = {
				{ slot = 2, userId = h.localPlayer.UserId, ver = 0, codes = {} },
				{ slot = 6, userId = 60, ver = 0, codes = {} },
			},
			paths = PathCodec.encode(1, {}),
			wild = wild or {},
			events = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 2 },
			crews = { crews = {} },
		})
		h:settle(2)
	end

	-- Vibrations demandées (HapticEffect joué ou moteur allumé ; l'arrêt du moteur ne compte pas)
	local function vibrations(c)
		local n = 0
		for _, entry in c.h.log.haptics do
			if entry.kind == "effect" or (entry.kind == "motor" and entry.value > 0) then
				n += 1
			end
		end
		return n
	end

	-- Code d'un Nebby Épique (Config/Nebbies)
	local function epicCode(c)
		local Nebbies = c.h:require("ReplicatedStorage.Shared.Config.Nebbies")
		local species = Nebbies.speciesOfRarity(4)[1]
		return Nebbies.pack(species, 0, 0)
	end

	-- Capture Épique du joueur local puis coupe de sa file par le Nid 6
	local function epicCatchThenSnipped(c)
		local code = epicCode(c)
		world(c, { { id = 4, code = code, x = 2, z = 2, seed = 1, t0 = T0, life = 30 } })
		c.h:fireClient(
			REMOTES .. "LineEvent",
			{ { op = "add", slot = 2, ver = 1, codes = { code }, ids = { 4 } } }
		)
		c.h:settle(2)
		c.Clock.advance(1)
		c.h:fireClient(REMOTES .. "SnipEvent", {
			snipperSlot = 6,
			victimSlot = 2,
			ver = 2,
			cutIndex = 1,
			count = 1,
			looseIds = {},
			loose = {},
			byWisp = false,
			x = 1,
			y = 3,
			z = 1,
			dust = 0,
		})
		c.h:settle(2)
	end

	describe("Console G1 › entrées de la DualSense", function()
		it("R2 et □ envoient le Dash ; L1, R1 et L2 restent libres en jeu", function()
			local c = boot()
			expect(c.Platform.inputKind()).toBe(c.Platform.GAMEPAD)
			expect(c.Input.inputType()).toBe(3)
			expect(Gamepad.tap(c.h, K.ButtonR2)).toBe("CC_Dash")
			expect(#sent(c, "Dash")).toBe(1)
			-- recharge : □ est refusé localement, rien n'est envoyé
			Gamepad.tap(c.h, K.ButtonX)
			expect(#sent(c, "Dash")).toBe(1)
			c.Clock.advance(30)
			expect(Gamepad.tap(c.h, K.ButtonX)).toBe("CC_Dash")
			expect(#sent(c, "Dash")).toBe(2)
			c.Clock.advance(30)
			for _, key in { K.ButtonL1, K.ButtonR1, K.ButtonL2 } do
				expect(Gamepad.tap(c.h, key)).toBeNil()
			end
			expect(#sent(c, "Dash")).toBe(2)
			expect(Gamepad.selected(c.h)).toBeNil()
			finish(c)
		end)

		it(
			"△ sélectionne le menu du HUD, la croix déplace la sélection (« Select »), △ puis ○ rendent la main (« Back »)",
			function()
				local c = boot()
				expect(Gamepad.selected(c.h)).toBeNil()
				expect(Gamepad.tap(c.h, K.ButtonY)).toBe("CC_Rail")
				local first = Gamepad.selected(c.h)
				expect(first ~= nil).toBe(true)
				expect(first:IsDescendantOf(gui(c, "HUD"))).toBe(true)
				-- pose initiale par le code : aucun son de navigation
				expect(count(c.sounds, "Select")).toBe(0)
				local dir = movingDirection(c)
				expect(dir ~= nil).toBe(true)
				Gamepad.tap(c.h, dir)
				expect(Gamepad.selected(c.h) ~= first).toBe(true)
				expect(count(c.sounds, "Select")).toBe(1)
				-- au plus un son par Config/Console.NavSoundInterval (horloge figée : pas de 2e son)
				local second = Gamepad.selected(c.h)
				Gamepad.tap(c.h, movingDirection(c))
				expect(Gamepad.selected(c.h) ~= second).toBe(true)
				expect(count(c.sounds, "Select")).toBe(1)
				c.Clock.advance(0.1)
				Gamepad.tap(c.h, movingDirection(c))
				expect(count(c.sounds, "Select")).toBe(2)
				-- △ : retour au jeu, sélection effacée (aucun « Select » à l'effacement)
				expect(Gamepad.tap(c.h, K.ButtonY)).toBe("CC_Rail")
				expect(Gamepad.selected(c.h)).toBeNil()
				expect(count(c.sounds, "Back")).toBe(1)
				expect(count(c.sounds, "Select")).toBe(2)
				-- ○ : même retour au jeu
				Gamepad.tap(c.h, K.ButtonY)
				expect(Gamepad.selected(c.h) ~= nil).toBe(true)
				expect(Gamepad.tap(c.h, K.ButtonB)).toBe("CC_Close")
				expect(Gamepad.selected(c.h)).toBeNil()
				expect(count(c.sounds, "Back")).toBe(2)
				-- en jeu, sans sélection ni roue : ○ est laissé aux autres
				expect(Gamepad.tap(c.h, K.ButtonB)).toBeNil()
				expect(count(c.sounds, "Back")).toBe(2)
				finish(c)
			end
		)

		it(
			"△ panneau ouvert : le panneau se ferme et la sélection est effacée (pas de rail derrière)",
			function()
				local c = boot()
				local rail = 0
				c.Input.RailRequested:Connect(function()
					rail += 1
				end)
				expect(c.Input.openPanel("Upgrades")).toBe(true)
				c.h:step(1 / 30, 10)
				expect(c.Panels.current()).toBe("Upgrades")
				expect(Gamepad.tap(c.h, K.ButtonY)).toBe("CC_Rail")
				c.h:step(1 / 30, 10)
				expect(c.Panels.current()).toBeNil()
				expect(Gamepad.selected(c.h)).toBeNil()
				expect(rail).toBe(0)
				expect(count(c.sounds, "Back")).toBe(1)
				finish(c)
			end
		)

		it("croix ← : suivi de quête replié / déplié (QuestToggled), seulement en jeu", function()
			local c = boot()
			expect(Gamepad.tap(c.h, K.DPadLeft)).toBe("CC_Quest")
			expect(c.quest).toBe(1)
			-- sélection active (menu du HUD) : la croix navigue, QuestToggled n'est pas émis
			Gamepad.tap(c.h, K.ButtonY)
			Gamepad.tap(c.h, K.DPadLeft)
			expect(c.quest).toBe(1)
			-- panneau ouvert, même sans sélection : le suivi derrière la fenêtre ne bouge pas
			Gamepad.tap(c.h, K.ButtonY)
			expect(c.Input.openPanel("Upgrades")).toBe(true)
			c.h.game.GuiService.SelectedObject = nil
			expect(Gamepad.tap(c.h, K.DPadLeft)).toBeNil()
			expect(c.quest).toBe(1)
			c.Panels.close()
			c.h:step(1 / 30, 10)
			expect(Gamepad.tap(c.h, K.DPadLeft)).toBe("CC_Quest")
			expect(c.quest).toBe(2)
			finish(c)
		end)
	end)

	describe("Console G1 › roue de pings à la manette", function()
		it(
			"croix ↑ : audit console vide, ○ au centre (PadGlyph ButtonB, icône PlayStation), ✕ « Envoyer »",
			function()
				local c = boot()
				expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
				c.h:step(1 / 30, 10)
				expect(c.Input.isPingWheelOpen()).toBe(true)
				local w = wheel(c)
				expect(w.Visible).toBe(true)
				expect(table.concat(Gamepad.audit(c.h, { root = w }), "\n")).toBe("")
				-- centre : ○ à la place du « ✕ » dessiné
				local center = w.Close.Button
				local pad = center.PadGlyph
				expect(pad.Visible).toBe(true)
				expect(pad:GetAttribute("GlyphKey")).toBe("ButtonB")
				expect(pad:GetAttribute("GlyphMode")).toBe("image")
				expect(string.find(pad.Image.Image, Gamepad.PS_GLYPHS, 1, true)).toBe(1)
				expect(center.Icon.Visible).toBe(false)
				-- repère ✕ « Envoyer » (PlayStation) et « Fermer »
				expect(w.SendHint.Visible).toBe(true)
				expect(w.SendHint.SendGlyph:GetAttribute("GlyphKey")).toBe("ButtonA")
				expect(string.find(w.SendHint.SendGlyph.Image.Image, Gamepad.PS_GLYPHS, 1, true)).toBe(1)
				expect(w.SendHint.Label.Text).toBe("Send")
				expect(w.CloseHint.Visible).toBe(true)
				expect(w.CloseHint.Text).toBe("Close")
				-- touches 1-6 du clavier masquées à la manette
				for i = 1, 6 do
					expect(w["Sector" .. i].Button.KeyCap.Visible).toBe(false)
				end
				-- aucune sélection GuiService dans la roue : la croix, le stick et ✕ vont à la roue
				expect(Gamepad.selected(c.h)).toBeNil()
				finish(c)
			end
		)

		it(
			"stick + ✕ envoie le Ping visé ; croix ← / → en anneau ; ○ ferme sans envoyer (« Back »)",
			function()
				local c = boot()
				Gamepad.tap(c.h, K.DPadUp)
				-- stick en bas à droite : secteur 3 (« Comète ! », sans emote), son de navigation
				expect(Gamepad.stick(c.h, K.Thumbstick1, Vector2.new(0.87, -0.5))).toBe("CC_PingStick")
				expect(count(c.sounds, "Select")).toBe(1)
				expect(Gamepad.tap(c.h, K.ButtonA)).toBe("CC_PingConfirm")
				expect(#sent(c, "Ping")).toBe(1)
				expect(sent(c, "Ping")[1][1]).toBe(3)
				expect(c.Input.isPingWheelOpen()).toBe(false)
				-- croix : le 1er appui vise le secteur 1, puis l'anneau boucle (← depuis 1 → 6)
				c.Clock.advance(2)
				Gamepad.tap(c.h, K.DPadUp)
				expect(Gamepad.tap(c.h, K.DPadRight)).toBe("CC_PingNav")
				c.Clock.advance(0.1)
				expect(Gamepad.tap(c.h, K.DPadLeft)).toBe("CC_PingNav")
				expect(c.quest).toBe(0) -- roue ouverte : la croix ← ne replie pas le suivi de quête
				local w = wheel(c)
				expect(w.Sector6.Button:FindFirstChildOfClass("UIStroke").Thickness).toBe(4)
				-- ○ : fermée sans envoyer, son « Back »
				expect(Gamepad.tap(c.h, K.ButtonB)).toBe("CC_Close")
				expect(c.Input.isPingWheelOpen()).toBe(false)
				expect(w.Visible).toBe(false)
				expect(#sent(c, "Ping")).toBe(1)
				expect(count(c.sounds, "Back")).toBe(1)
				-- ✕ sans secteur visé : la roue se ferme sans envoyer
				Gamepad.tap(c.h, K.DPadUp)
				expect(Gamepad.tap(c.h, K.ButtonA)).toBe("CC_PingConfirm")
				expect(c.Input.isPingWheelOpen()).toBe(false)
				expect(#sent(c, "Ping")).toBe(1)
				finish(c)
			end
		)

		it("clavier-souris : « ✕ » dessiné et touches 1-6, aucun repère de manette", function()
			local c = boot({ pc = true })
			c.Input.openPingWheel()
			c.h:step(1 / 30, 10)
			local w = wheel(c)
			expect(w.Close.Button.Icon.Visible).toBe(true)
			expect(w.Close.Button.PadGlyph.Visible).toBe(false)
			expect(w.SendHint.Visible).toBe(false)
			expect(w.CloseHint.Visible).toBe(false)
			expect(w.Sector1.Button.KeyCap.Visible).toBe(true)
			-- la manette prise en main : repères de la manette aussitôt
			Gamepad.tap(c.h, K.DPadRight)
			expect(c.Input.inputType()).toBe(3)
			expect(w.Close.Button.PadGlyph.Visible).toBe(true)
			expect(w.Close.Button.Icon.Visible).toBe(false)
			expect(w.SendHint.Visible).toBe(true)
			expect(w.Sector1.Button.KeyCap.Visible).toBe(false)
			finish(c)
		end)
	end)

	describe("Console G1 › vibrations du jeu (Util/Haptics)", function()
		it("capture Épique et coupe subie : vibrations journalisées sur la manette", function()
			local c = boot()
			epicCatchThenSnipped(c)
			expect(table.find(c.played, "catchEpic") ~= nil).toBe(true)
			expect(table.find(c.played, "snipped") ~= nil).toBe(true)
			local effects = 0
			for _, entry in c.h.log.haptics do
				if entry.kind == "effect" and entry.type == Enum.HapticEffectType.GameplayCollision then
					effects += 1
				end
			end
			expect(effects >= 2).toBe(true)
			finish(c)
		end)

		it("Comète (alerte, impact proche, ramassage) et Supernova du héros", function()
			local c = boot()
			world(c)
			local root = c.h.localPlayer.Character.HumanoidRootPart
			local comet = {
				id = T0 + 8,
				phase = "warn",
				x = root.Position.X + 10,
				z = root.Position.Z,
				code = 1700,
				warnAt = T0,
				impactAt = T0 + 8,
				burstAt = T0 + 83,
			}
			local function state(phase, extra)
				local cm = table.clone(comet)
				cm.phase = phase
				for k, v in extra or {} do
					cm[k] = v
				end
				return { t = c.Clock.now(), wisps = {}, snipsDisabled = false, activePlayers = 2, comet = cm }
			end
			c.h:fireClient(REMOTES .. "EventState", state("warn"))
			c.h:settle(2)
			expect(table.find(c.played, "cometWarn") ~= nil).toBe(true)
			c.Clock.advance(8.5)
			c.h:fireClient(REMOTES .. "EventState", state("ground"))
			c.h:settle(2)
			expect(table.find(c.played, "cometImpact") ~= nil).toBe(true)
			c.Clock.advance(1)
			c.h:fireClient(
				REMOTES .. "EventState",
				state("carried", { carrierId = c.h.localPlayer.UserId, carrierSince = c.Clock.now() })
			)
			c.h:settle(2)
			expect(table.find(c.played, "cometGrab") ~= nil).toBe(true)
			c.Clock.advance(1)
			c.h:fireClient(REMOTES .. "Celebrate", { kind = "supernova", data = { level = 1 } })
			c.h:settle(2)
			expect(table.find(c.played, "supernova") ~= nil).toBe(true)
			finish(c)
		end)

		it("clavier-souris : aucune vibration", function()
			local c = boot({ pc = true })
			expect(c.Input.inputType()).toBe(2)
			epicCatchThenSnipped(c)
			expect(#c.played).toBe(0)
			expect(vibrations(c)).toBe(0)
			finish(c)
		end)

		it("réglage « Vibrations » coupé (settings.vibration = false) : aucune vibration", function()
			local c = boot({ settings = { vibration = false } })
			epicCatchThenSnipped(c)
			expect(#c.played).toBe(0)
			expect(vibrations(c)).toBe(0)
			-- VFXController.haptic (contrat) respecte aussi le réglage
			local VFX = c.h:require(CLIENT .. "Controllers.VFXController")
			VFX.haptic(0.5, 0.1)
			expect(vibrations(c)).toBe(0)
			finish(c)
		end)

		it(
			"VFXController.haptic : manette d'abord sur console, délai minimal commun avec Util/Haptics",
			function()
				local c = boot()
				local VFX = c.h:require(CLIENT .. "Controllers.VFXController")
				VFX.haptic(0.5, 0.05)
				expect(vibrations(c)).toBe(1)
				expect(c.h.log.haptics[1].kind).toBe("motor")
				expect(c.h.log.haptics[1].inputType).toBe(Enum.UserInputType.Gamepad1)
				VFX.haptic(0.5, 0.05) -- trop tôt
				expect(vibrations(c)).toBe(1)
				c.Clock.advance(1)
				expect(c.Haptics.play("parade")).toBe(true)
				expect(vibrations(c)).toBe(2)
				VFX.haptic(0.5, 0.05) -- juste après une vibration de Util/Haptics : ignorée
				expect(vibrations(c)).toBe(2)
				c.Clock.advance(1)
				VFX.haptic(0 / 0, 0.05) -- valeurs absurdes : ignorées
				expect(vibrations(c)).toBe(2)
				VFX.haptic(0.5, 0.05)
				expect(vibrations(c)).toBe(3)
				c.h:settle(2)
				finish(c)
			end
		)
	end)
end
