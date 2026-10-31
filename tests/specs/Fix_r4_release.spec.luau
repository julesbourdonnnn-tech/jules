--!nocheck
-- Validation de publication r4 : notes croisées des correcteurs, appliquées hors de leurs fichiers.
--   1. Fenêtres Roblox qui tiennent la manette (docs/07 §6.6, §6.7, §7) : Panels/Shop appelle
--      PanelController.holdSelection(true) après un appel réussi à PromptGamePassPurchase /
--      PromptProductPurchase (même si la sélection a bougé entre ✕ et l'ouverture), Panels/Crew
--      après PromptGameInvite et rend la sélection sur SocialService.GameInvitePromptClosed.
--   2. InputController, panneau ouvert : Q, M et F passent (ni roue de pings, ni minicarte, ni
--      ACCLAMER derrière la fenêtre) ; togglePanel ignore une fermeture qui suit l'ouverture du même
--      panneau de moins de Config/Console.ToggleCloseGuard (double appui sur le rail).
--   3. VFXController.playUpgrade(track, level, silent) : la reprise différée après la fermeture
--      d'un panneau ne rejoue pas LevelUp (déjà entendu à l'achat).
--   4. « Réessayer » de l'écran de chargement : même curseur que UI/Root.selectionImage.
--   5. OnboardingController : Q6 pendant une Pluie de météores → « Weather in {time} » rafraîchi
--      chaque seconde ; fin de Q4 (Celebrate « atlasUnlocked ») → l'icône Collection pulse 3 s et
--      Collection s'ouvre une fois sur l'Atlas ; △ de l'instruction masqué tant que la carte
--      d'invitation d'équipage annonce △ sur Accepter.
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")
local MockInstance = require("../harness/MockInstance")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)
	local K = Enum.KeyCode
	local BEGIN = Enum.UserInputState.Begin
	local PASS_ID = 777001

	local function profile(over)
		local nebbies = {}
		for i = 1, 12 do
			nebbies["u" .. i] = { s = (i % 5) + 1, f = 0, v = 0, st = 1 }
		end
		local p = {
			version = 1,
			glow = 500000,
			glowCarry = 0,
			lastSettle = T0,
			lastOnline = T0,
			idleRate = 120,
			stardust = 5000,
			supernovas = 0,
			upgrades = { conga = 0, stride = 0, lure = 0, perches = 2, guard = 0 },
			boosts = { personalUntil = 0 },
			caps = { day = 0, snipDust = 0, wispDust = 0, cheers = 0, duo = false },
			nebbies = nebbies,
			nextUid = 100,
			perchIncome = 120,
			atlas = { 255, 255, 3, 0, 0, 0, 0 },
			badges = { 0, 0, 0, 0 },
			atlasRewards = 0,
			onboarding = { step = 8, p = 0 },
			daily = { day = TODAY - 1, step = 2 },
			quests = { day = TODAY, list = {}, rerolls = 0, starClaimed = false },
			weekly = { week = 0, banked = 0, claimed = false },
			rookie = { sessions = 3, playSeconds = 4000, done = true },
			settings = {
				zen = false,
				reducedMotion = false,
				lowGraphics = false,
				music = true,
				sfx = true,
				vibration = true,
				autoCrew = true,
				refuseInvites = false,
				lang = "en",
			},
			cosmetics = { style = "default", title = "", nestTheme = "default" },
			unlocks = { styles = {}, titles = {}, themes = {} },
			weeklyBest = { week = 0, conga = 0 },
			starterKit = false,
			stats = {},
			passes = {},
		}
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	-- Client complet (console par défaut), profil vétéran ou instantané donné
	local function boot(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = opts.console ~= false })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local Monetization = h:require("ReplicatedStorage.Shared.Config.Monetization")
		Monetization.Passes.VIPStar.id = PASS_ID
		if opts.audit ~= false then
			ApiAudit.start()
		end
		h:boot()
		h:fireClient(REMOTES .. "DataSnapshot", opts.snapshot or profile(opts.over))
		h:step(1 / 60, 30)
		h:settle(3)
		local c = {
			h = h,
			Clock = Clock,
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			Onboarding = h:require(CLIENT .. "Controllers.OnboardingController"),
			Audio = h:require(CLIENT .. "Controllers.AudioController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan"),
			Format = h:require("ReplicatedStorage.Shared.Util.Format"),
			minimap = 0,
			cheers = 0,
		}
		c.Input.MinimapToggled:Connect(function()
			c.minimap += 1
		end)
		c.Input.CheerRequested:Connect(function()
			c.cheers += 1
		end)
		return c
	end

	local function finish(c, audited)
		local issues = if audited == false then {} else ApiAudit.stop()
		expect(table.concat(issues, "\n")).toBe("")
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

	local function selected(c)
		return Gamepad.selected(c.h)
	end

	local function window(c)
		return c.h.localPlayer.PlayerGui.Panels.Safe.Window
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	local function openFresh(c, name, tab)
		c.PC.close()
		frames(c, 8)
		c.h.game.GuiService.SelectedObject = nil
		c.PC.open(name, if tab then { tab = tab } else nil)
		frames(c, 8)
		Layout.apply(c.h)
	end

	-- Un autre objet sélectionnable affiché de la fenêtre que `except`
	local function otherSelectable(c, except)
		for _, d in window(c):GetDescendants() do
			if d:IsA("GuiButton") and d ~= except and d.Selectable and Layout.visible(d) then
				return d
			end
		end
		return nil
	end

	-- Sons joués (AudioController.play espionné) ; rendre() remet l'original
	local function spyAudio(c)
		local played = {}
		local original = c.Audio.play
		c.Audio.play = function(name, ...)
			table.insert(played, name)
			return original(name, ...)
		end
		return played, function()
			c.Audio.play = original
		end
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

	-- =============================================================================================
	-- 1. Fenêtres Roblox qui tiennent la manette
	-- =============================================================================================

	describe("Release r4 › fenêtres Roblox : sélection retenue puis rendue", function()
		it(
			"Boutique : retenue même si la sélection a bougé entre ✕ et l'ouverture de la fenêtre",
			function()
				local c = boot()
				openFresh(c, "Shop", "passes")
				local buy = c.PC.page("Shop").Body.Tab_passes.VIPStar.Buy
				c.h.game.GuiService.SelectedObject = buy
				frames(c, 2)
				Gamepad.tap(c.h, K.ButtonA)
				expect(#c.h.log.prompts).toBe(1)
				expect(c.h.log.prompts[1].id).toBe(PASS_ID)
				-- la croix déplace la sélection pendant que Roblox charge la fenêtre d'achat
				local other = otherSelectable(c, buy)
				expect(other ~= nil).toBe(true)
				c.h.game.GuiService.SelectedObject = other
				frames(c, 2)
				expect(selected(c)).toBe(other)
				-- la fenêtre prend la manette : sélection laissée vide jusqu'à la fin de l'achat
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 150)
				expect(selected(c)).toBeNil()
				c.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(
					c.h.localPlayer,
					PASS_ID,
					false
				)
				frames(c, 2)
				expect(selected(c)).toBe(buy)
				-- retenue tombée : un effacement plus tard est rendu
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 2)
				expect(selected(c)).toBe(buy)
				finish(c)
			end
		)

		it("Équipage : « Inviter un ami » retenue jusqu'à GameInvitePromptClosed, puis rendue", function()
			local c = boot()
			openFresh(c, "Crew")
			local friend = c.PC.page("Crew"):FindFirstChild("InviteFriend", true)
			expect(friend ~= nil).toBe(true)
			c.h.game.GuiService.SelectedObject = friend
			frames(c, 2)
			Gamepad.tap(c.h, K.ButtonA)
			c.h:settle(2)
			expect(#c.h.log.invites).toBe(1)
			c.h.game.GuiService.SelectedObject = nil
			frames(c, 150) -- 5 s : bien au-delà de la fenêtre de repli de 3 s
			expect(selected(c)).toBeNil()
			local social = c.h.game:GetService("SocialService")
			-- fenêtre d'un autre joueur (jamais côté client, mais filtrée) : rien ne change
			social.GameInvitePromptClosed:Fire(c.h.game, {})
			frames(c, 2)
			expect(selected(c)).toBeNil()
			social.GameInvitePromptClosed:Fire(c.h.localPlayer, {})
			frames(c, 2)
			expect(selected(c)).toBe(friend)
			-- panneau fermé entre-temps : la fermeture de la fenêtre ne sélectionne rien
			Gamepad.tap(c.h, K.ButtonA)
			c.h:settle(2)
			expect(#c.h.log.invites).toBe(2)
			c.PC.close()
			frames(c, 8)
			c.h.game.GuiService.SelectedObject = nil
			social.GameInvitePromptClosed:Fire(c.h.localPlayer, {})
			frames(c, 2)
			expect(selected(c)).toBeNil()
			finish(c)
		end)
	end)

	-- =============================================================================================
	-- 2. InputController : clavier panneau ouvert, double appui
	-- =============================================================================================

	describe("Release r4 › InputController : panneau ouvert et double appui", function()
		it("panneau ouvert : Q, M et F passent ; panneau fermé, ils agissent", function()
			local c = boot({ console = false })
			openFresh(c, "Upgrades")
			c.Input.setCheerAvailable(true)
			for _, key in { K.Q, K.M, K.F } do
				expect({ key = key.Name, action = Gamepad.dispatch(c.h, key, BEGIN) }).toEqual({
					key = key.Name,
				})
			end
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(c.minimap).toBe(0)
			expect(c.cheers).toBe(0)
			expect(c.PC.current()).toBe("Upgrades")
			c.PC.close()
			frames(c, 8)
			local actions = c.Input._actions
			expect(Gamepad.dispatch(c.h, K.Q, BEGIN)).toBe(actions.wheel)
			expect(c.Input.isPingWheelOpen()).toBe(true)
			expect(Gamepad.dispatch(c.h, K.Q, BEGIN)).toBe(actions.wheel)
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(Gamepad.dispatch(c.h, K.M, BEGIN)).toBe(actions.minimap)
			expect(c.minimap).toBe(1)
			expect(Gamepad.dispatch(c.h, K.F, BEGIN)).toBe(actions.cheer)
			expect(c.cheers).toBe(1)
			finish(c)
		end)

		it("roue déjà ouverte quand un panneau s'ouvre : Q la referme encore", function()
			local c = boot({ console = false })
			c.Input.openPingWheel()
			expect(c.Input.isPingWheelOpen()).toBe(true)
			c.PC.open("Upgrades")
			frames(c, 8)
			if c.Input.isPingWheelOpen() then
				expect(Gamepad.dispatch(c.h, K.Q, BEGIN)).toBe(c.Input._actions.wheel)
			end
			expect(c.Input.isPingWheelOpen()).toBe(false)
			finish(c)
		end)

		it(
			"double appui sur un bouton du rail : la fermeture < 0,35 s après l'ouverture est ignorée",
			function()
				local c = boot({ console = false })
				local button = hud(c).Rail.Upgrades.Button
				button.Activated:Fire()
				c.h:settle(1)
				expect(c.PC.current()).toBe("Upgrades")
				frames(c, 3) -- 0,1 s
				button.Activated:Fire()
				c.h:settle(1)
				frames(c, 8)
				expect(c.PC.current()).toBe("Upgrades")
				-- raccourci clavier (U) dans la même fenêtre de temps : ignoré aussi
				c.PC.close()
				frames(c, 8)
				expect(c.PC.current()).toBeNil()
				expect(Gamepad.dispatch(c.h, K.U, BEGIN)).toBe(c.Input._actions.panels)
				c.h:settle(1)
				expect(c.PC.current()).toBe("Upgrades")
				Gamepad.dispatch(c.h, K.U, BEGIN)
				c.h:settle(1)
				frames(c, 8)
				expect(c.PC.current()).toBe("Upgrades")
				-- au-delà de 0,35 s : le second appui ferme
				frames(c, 6)
				button.Activated:Fire()
				c.h:settle(1)
				frames(c, 8)
				expect(c.PC.current()).toBeNil()
				-- autre panneau : jamais retenu (bascule vers Collection immédiate)
				button.Activated:Fire()
				c.h:settle(1)
				expect(c.PC.current()).toBe("Upgrades")
				hud(c).Rail.Collection.Button.Activated:Fire()
				c.h:settle(1)
				frames(c, 8)
				expect(c.PC.current()).toBe("Collection")
				finish(c)
			end
		)
	end)

	-- =============================================================================================
	-- 3. Amélioration : LevelUp une seule fois
	-- =============================================================================================

	describe("Release r4 › amélioration achetée panneau ouvert : LevelUp une seule fois", function()
		it(
			"playUpgrade(…, true) muet ; Celebrate upgrade panneau ouvert puis fermé : un LevelUp",
			function()
				local c = boot()
				local played, restore = spyAudio(c)
				c.VFX.playUpgrade("conga", 2, true)
				expect(count(played, "LevelUp")).toBe(0)
				c.VFX.playUpgrade("conga", 2)
				expect(count(played, "LevelUp")).toBe(1)
				frames(c, 60)
				table.clear(played)
				openFresh(c, "Upgrades")
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "upgrade", data = { track = "conga", level = 1 } }
				)
				frames(c, 4)
				expect(count(played, "LevelUp")).toBe(1)
				c.PC.close()
				frames(c, 90) -- reprise différée de l'effet du monde, muette
				expect(count(played, "LevelUp")).toBe(1)
				restore()
				finish(c)
			end
		)
	end)

	-- =============================================================================================
	-- 4. Écran de chargement : même curseur que UI/Root
	-- =============================================================================================

	describe("Release r4 › « Réessayer » : curseur de UI/Root.selectionImage", function()
		it("trait blanc de 6 px, liseré sombre de 2 px, débord 4 px, coins 16 / 22", function()
			local h = Harness.new({ mode = "client", console = true })
			MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
			h:run("ReplicatedFirst.Loading")
			MockInstance.classMethods.ReplicatedFirst = nil
			local loading = h.localPlayer.PlayerGui:FindFirstChild("Loading")
			h:step(1, 21)
			local button = loading:FindFirstChild("Fail", true).RetryButton
			expect(Gamepad.selected(h)).toBe(button)
			local image = button.SelectionImageObject
			local ref =
				Harness.new({ mode = "client", console = true }):require(CLIENT .. "UI.Root").selectionImage()
			local function shape(frame)
				local stroke = frame:FindFirstChildOfClass("UIStroke")
				local corner = frame:FindFirstChildOfClass("UICorner")
				local edge = frame:FindFirstChild("Edge")
				local edgeStroke = edge and edge:FindFirstChildOfClass("UIStroke")
				local edgeCorner = edge and edge:FindFirstChildOfClass("UICorner")
				return {
					size = tostring(frame.Size),
					anchor = tostring(frame.AnchorPoint),
					color = tostring(stroke.Color),
					thickness = stroke.Thickness,
					mode = stroke.ApplyStrokeMode.Name,
					corner = tostring(corner.CornerRadius),
					edgeSize = edge and tostring(edge.Size),
					edgeAnchor = edge and tostring(edge.AnchorPoint),
					edgeColor = edgeStroke and tostring(edgeStroke.Color),
					edgeThickness = edgeStroke and edgeStroke.Thickness,
					edgeMode = edgeStroke and edgeStroke.ApplyStrokeMode.Name,
					edgeCorner = edgeCorner and tostring(edgeCorner.CornerRadius),
				}
			end
			expect(shape(image)).toEqual(shape(ref))
			expect(shape(image).thickness).toBe(6)
			expect(shape(image).edgeThickness).toBe(2)
			h.localPlayer:SetAttribute("ClientReady", true)
			h:settle(3)
			expect(#h.errors).toBe(0)
		end)
	end)

	-- =============================================================================================
	-- 5. Accueil : Pluie de météores, Atlas débloqué, △ et carte d'invitation
	-- =============================================================================================

	describe("Release r4 › accueil (OnboardingController)", function()
		it(
			"Q6 pendant une Pluie de météores : « Weather in {time} », compte à rebours chaque seconde",
			function()
				local c = boot({ over = { onboarding = { step = 6, p = 0 } } })
				c.h:fireClient(REMOTES .. "EventState", {
					t = c.Clock.now(),
					wisps = {},
					snipsDisabled = false,
					activePlayers = 1,
					weather = { key = "meteor", startsAt = c.Clock.now() - 10, endsAt = c.Clock.now() + 300 },
				})
				frames(c, 12)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeatherIn")
				local function expected()
					local s = c.Plan.formWeatherIn(c.Clock.now())
					expect(s ~= nil).toBe(true)
					return c.Prefs.t("onboarding.waitWeatherIn", { time = c.Format.clock(s) })
				end
				local state = c.Onboarding._state()
				local first = state.hintLabel.Text
				expect(first).toBe(expected())
				expect(string.find(first, "{time}", 1, true)).toBeNil()
				expect(state.hintIcon.Text).toBe("◷")
				-- la pastille d'événement ne pulse pas (elle montre la pluie en cours)
				expect(state.attention.eventPill == true).toBe(false)
				frames(c, 31)
				expect(state.hintLabel.Text).toBe(expected())
				expect(state.hintLabel.Text ~= first).toBe(true)
				-- langue : retraduite avec le compte à rebours
				c.Prefs._onSettings({ lang = "fr" })
				frames(c, 2)
				expect(state.hintLabel.Text).toBe(expected())
				expect(string.find(state.hintLabel.Text, "Météo", 1, true) ~= nil).toBe(true)
				finish(c)
			end
		)

		it("fin de Q4 : l'icône Collection pulse 3 s et Collection s'ouvre une fois sur l'Atlas", function()
			-- première session : arrivée à Q1 (travelling d'arrivée tenté ou abandonné après 2,5 s),
			-- puis Q4 en cours (HUD encore partiel)
			local c = boot({
				over = {
					onboarding = { step = 1, p = 0 },
					rookie = { sessions = 0, playSeconds = 0, done = false },
					stats = { parades = 0, sessions = 0 },
					upgrades = { conga = 0, stride = 0, lure = 0, perches = 0, guard = 0 },
				},
			})
			frames(c, 120)
			expect(c.Onboarding._state().introDone).toBe(true)
			c.h:fireClient(REMOTES .. "DataPatch", {
				onboarding = { step = 4, p = 0 },
				stats = { parades = 4, sessions = 0 },
				upgrades = { conga = 3, stride = 1, lure = 0, perches = 0, guard = 0 },
			}, {})
			frames(c, 60)
			expect(c.HUD.isRevealed("stardust")).toBe(true)
			expect(c.HUD.isRevealed("rail.Collection")).toBe(false)
			c.h:fireClient(
				REMOTES .. "Celebrate",
				{ kind = "atlasUnlocked", data = { count = 5, total = 150 } }
			)
			frames(c, 4)
			-- pas encore affichée : la pulsation attend l'icône
			expect(c.Onboarding._state().attention["rail.Collection"] == true).toBe(false)
			c.h:fireClient(REMOTES .. "DataPatch", { onboarding = { step = 5, p = 0 } }, {})
			frames(c, 4)
			expect(c.HUD.isRevealed("rail.Collection")).toBe(true)
			expect(c.Onboarding._state().attention["rail.Collection"]).toBe(true)
			frames(c, 100) -- 3,3 s
			expect(c.Onboarding._state().attention["rail.Collection"]).toBe(false)
			-- première ouverture : onglet Atlas ; la suivante garde le dernier onglet choisi
			expect(c.Input.openPanel("Collection")).toBe(true)
			frames(c, 8)
			expect(c.PC.current()).toBe("Collection")
			expect(c.PC.currentTab("Collection")).toBe("atlas")
			c.PC.close()
			frames(c, 8)
			c.PC.open("Collection", { tab = "perches" })
			frames(c, 8)
			c.PC.close()
			frames(c, 8)
			expect(c.Input.openPanel("Collection")).toBe(true)
			frames(c, 8)
			expect(c.PC.currentTab("Collection")).toBe("perches")
			finish(c)
		end)

		it(
			"Q1 à la manette : △ de l'instruction masqué tant que la carte d'invitation l'annonce",
			function()
				local c = boot({
					snapshot = {
						glow = 5000,
						onboarding = { step = 1, p = 0 },
						stats = { parades = 1, sessions = 0 },
						upgrades = { conga = 0 },
					},
					audit = false,
				})
				frames(c, 12)
				expect(c.Onboarding.currentHint()).toBe("onboarding.openUpgrade")
				local hint = c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint
				expect(hint.PadGlyph:GetAttribute("GlyphKey")).toBe("ButtonY")
				expect(hint.Icon.Visible).toBe(false)
				c.h:addPlayer({ userId = 2, name = "Mira" })
				c.h:settle(2)
				c.h:fireClient(
					REMOTES .. "CrewInvitePrompt",
					{ inviterId = 2, expiresAt = c.Clock.now() + 20 }
				)
				frames(c, 12)
				local card = c.h.localPlayer.PlayerGui.Panels.Safe.CrewInvite
				expect(c.PC.focusTarget()).toBe(card.Accept)
				expect(card.Accept.PadGlyph:GetAttribute("GlyphKey")).toBe("ButtonY")
				-- un seul △ à l'écran : celui de la carte ; l'instruction reprend son icône dessinée
				expect(hint.PadGlyph:GetAttribute("GlyphKey") ~= "ButtonY").toBe(true)
				expect(hint.Icon.Visible).toBe(true)
				-- carte refusée : le △ revient à côté de l'instruction
				c.h.game.GuiService.SelectedObject = card.Decline
				frames(c, 2)
				Gamepad.tap(c.h, K.ButtonA)
				frames(c, 12)
				expect(c.PC.focusTarget()).toBeNil()
				expect(hint.PadGlyph:GetAttribute("GlyphKey")).toBe("ButtonY")
				expect(hint.Icon.Visible).toBe(false)
				finish(c, false)
			end
		)
	end)
end
