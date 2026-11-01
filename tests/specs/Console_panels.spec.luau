--!nocheck
-- Console PS5, groupe G3 « Panneaux » (docs/07-console-ps5.md §6.3-§6.7, §7, §9, §11 G3) sur le VRAI
-- client démarré en console (Main.client, 1920 × 1080, UIScale 1,5, zone sûre 64 × 36), manette seule :
--   * pour chaque panneau et chaque onglet : sélection par défaut dans la fenêtre, aucune fuite de la
--     sélection (Layout.escapes), tout atteignable (Layout.unreachable), audit console vide
--     (glyphes PlayStation, textes ≥ 18 px, zone sûre TV)
--   * en-tête à la manette : ○ « PadGlyph » sur Fermer / Retour (△ sur Fermer de la Supernova) au lieu
--     des « ✕ » / « ‹ » dessinés, L1 / R1 aux bouts des onglets, L2 / R2 aux coins de l'en-tête
--   * ○ recule d'un niveau (Supernova → Améliorer → bouton du rail d'origine) avec le son « Back »
--   * L1 / R1 : onglets en boucle (« Tab ») ; L2 / R2 : panneaux en boucle, garde du HUD respectée ;
--     R2 ne Dash pas panneau ouvert
--   * stick droit : défile la liste (absorbé) ; croix au bord : « Bump » + vibration « listEnd »
--   * Supernova maintenue à ✕ (Gamepad.press / release) : relâchement anticipé = rien, « holdStart »
--     journalisé ; refus hors du port : vibration « refuse »
--   * Boutique : re-sélection du bouton Acheter après la fenêtre d'achat ; Codes : Entrée du clavier
--     virtuel → envoi et sélection sur « Valider »
--   * Réserve de 60 Nebbies parcourue à la croix jusqu'au dernier (la sélection suit l'index)
--   * changement de contenu (fusion) : sélection toujours valide ; consignes « Choisis… » à la manette
--   * carte d'invitation : focusTarget → Accepter, Accepter ↔ Refuser, repère ✕
--   * API Roblox auditée (ApiAudit) : 0 écart ; 0 erreur, 0 avertissement
-- L'audit des textes ≥ 18 px en anglais ET en français, chaque liste défilante parcourue sur tout
-- son canevas, vit dans Fix_fin_client_panels_console.spec (ici : anglais, partie visible).
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)
	local K = Enum.KeyCode
	local PS = Gamepad.PS_GLYPHS
	local PASS_ID, PRODUCT_ID = 777001, 888001

	local function neb(s, st, lk)
		return { s = s, f = 0, v = 0, st = st or 1, lk = lk }
	end

	-- Profil riche : réserve de `stash` Nebbies, fusions possibles, Atlas débloqué, quêtes du jour
	local function profile(over)
		local nebbies = {}
		for i = 1, (over and over.stash) or 24 do
			nebbies["u" .. i] = neb((i % 5) + 1)
		end
		nebbies.f1, nebbies.f2, nebbies.f3 = neb(2), neb(2), neb(2)
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
			quests = {
				day = TODAY,
				list = {
					{ id = 1, p = 3, done = false, claimed = false },
					{ id = 2, p = 10, done = true, claimed = false },
					{ id = 3, p = 1, done = true, claimed = true },
				},
				rerolls = 0,
				starClaimed = false,
			},
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
			if k ~= "stash" then
				p[k] = v
			end
		end
		return p
	end

	-- Client console complet (Main.client) ; sons et vibrations journalisés
	local function boot(over, opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local Monetization = h:require("ReplicatedStorage.Shared.Config.Monetization")
		Monetization.Passes.VIPStar.id = PASS_ID
		Monetization.Products.GlowPouch.id = PRODUCT_ID
		local c = { h = h, Clock = Clock, sounds = {}, played = {}, Monetization = Monetization }
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
		h:fireClient(REMOTES .. "DataSnapshot", profile(over))
		h:step(1 / 60, 30)
		h:settle(3)
		c.PC = h:require(CLIENT .. "Controllers.PanelController")
		c.Input = h:require(CLIENT .. "Controllers.InputController")
		c.HUD = h:require(CLIENT .. "UI.HUD")
		c.Platform = h:require(CLIENT .. "Util.Platform")
		c.Haptics = h:require(CLIENT .. "Util.Haptics")
		c.Haptics.Played:Connect(function(name)
			table.insert(c.played, name)
		end)
		c.WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		table.clear(c.sounds)
		return c
	end

	local function finish(c, audited)
		local issues = if audited == false then {} else ApiAudit.stop()
		expect(table.concat(issues, "\n")).toBe("")
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function panel(c, name)
		return c.h:require(CLIENT .. "UI.Panels." .. name)
	end

	local function window(c)
		return c.h.localPlayer.PlayerGui.Panels.Safe.Window
	end

	local function frames(c, n, dt)
		for _ = 1, n or 3 do
			c.Clock.advance(dt or 1 / 30)
			c.h:step(dt or 1 / 30, 1)
		end
		c.h:settle(1)
	end

	-- Images avec la mise en page recalculée à chacune (comme le moteur : positions absolues à jour)
	local function laidFrames(c, n)
		for _ = 1, n do
			Layout.apply(c.h)
			frames(c, 1)
		end
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

	-- Panneau ouvert depuis le jeu (fermé avant), comme au rail
	local function openFresh(c, name, tab)
		c.PC.close()
		frames(c, 8)
		c.h.game.GuiService.SelectedObject = nil
		c.PC.open(name, if tab then { tab = tab } else nil)
		frames(c, 8)
		Layout.apply(c.h)
	end

	local function goHome(c)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", 1)
		local gate = c.WorldLayout.gateCFrame(1).Position
		me.Character.HumanoidRootPart.CFrame = CFrame.new(gate.X, 3, gate.Z)
	end

	local function goAway(c)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", 1)
		me.Character.HumanoidRootPart.CFrame = CFrame.new(0, 3, 30)
	end

	local function glyph(frame)
		return {
			key = frame:GetAttribute("GlyphKey"),
			mode = frame:GetAttribute("GlyphMode"),
			ps = type(frame.Image.Image) == "string" and string.find(frame.Image.Image, PS, 1, true) == 1,
			visible = Layout.visible(frame),
		}
	end

	local function psGlyph(key)
		return { key = key, mode = "image", ps = true, visible = true }
	end

	-- Contrôles d'un écran : sélection par défaut dans la fenêtre, ni fuite ni objet inatteignable,
	-- audit console vide
	local function checkScreen(c, label)
		local w = window(c)
		local start = selected(c)
		expect({ label = label, inside = start ~= nil and start:IsDescendantOf(w) }).toEqual({
			label = label,
			inside = true,
		})
		Layout.apply(c.h)
		expect({ label = label, visible = Layout.selectable(start) }).toEqual({
			label = label,
			visible = true,
		})
		expect({ label = label, escapes = Layout.names(Layout.escapes(c.h, w, start)) }).toEqual({
			label = label,
			escapes = "",
		})
		expect({ label = label, unreachable = Layout.names(Layout.unreachable(c.h, w, start)) }).toEqual({
			label = label,
			unreachable = "",
		})
		expect({ label = label, audit = table.concat(Gamepad.audit(c.h, { root = w }), "\n") }).toEqual({
			label = label,
			audit = "",
		})
	end

	-- Index de la case de Réserve sélectionnée (0 : la sélection n'est pas dans la grille)
	local function stashIndex(c)
		local sel = selected(c)
		local cell = sel and sel.Parent
		if cell and cell.Name == "Cell" then
			return cell:GetAttribute("Index"), cell:GetAttribute("Uid")
		end
		return 0, nil
	end

	-- =============================================================================================
	describe("Console G3 › chaque panneau et chaque onglet", function()
		it(
			"sélection par défaut dans la fenêtre, aucune fuite, tout atteignable, audit console vide",
			function()
				local c = boot({ stash = 60 })
				for i = 2, 4 do
					c.h:addPlayer({ userId = i, name = "P" .. i })
				end
				c.h:settle(2)
				local cases = {
					{ "Upgrades" },
					{ "Supernova" },
					{ "Collection", "perches" },
					{ "Collection", "stash" },
					{ "Collection", "forge" },
					{ "Collection", "atlas" },
					{ "Collection", "guide" },
					{ "Goals", "today" },
					{ "Goals", "calendar" },
					{ "Goals", "week" },
					{ "Shop", "passes" },
					{ "Shop", "boosts" },
					{ "Shop", "codes" },
					{ "Crew" },
					{ "Settings" },
				}
				for _, case in cases do
					openFresh(c, case[1], case[2])
					expect(c.PC.current()).toBe(case[1])
					if case[2] then
						expect(c.PC.currentTab(case[1])).toBe(case[2])
					end
					checkScreen(c, table.concat(case, "/"))
				end
				-- sélections par défaut documentées (docs/07 §7)
				openFresh(c, "Collection", "stash")
				expect(selected(c).Name).toBe("Select")
				openFresh(c, "Collection", "forge")
				expect(selected(c).Name).toBe("FuseAll")
				openFresh(c, "Shop", "passes")
				expect(selected(c).Name).toBe("Buy")
				openFresh(c, "Shop", "codes")
				expect(selected(c).Name).toBe("CodeBox")
				openFresh(c, "Settings")
				expect(selected(c).Name).toBe("Toggle")
				openFresh(c, "Supernova")
				expect(selected(c).Name).toBe("Hold")
				-- écran de retour (fenêtre réduite) : OK
				c.PC.close()
				frames(c, 8)
				panel(c, "ReturnScreen").present({ glow = 1200, seconds = 3600, nightShift = false })
				frames(c, 8)
				expect(c.PC.current()).toBe("ReturnScreen")
				expect(selected(c).Name).toBe("Ok")
				checkScreen(c, "ReturnScreen")
				finish(c)
			end
		)

		it("Objectifs › Accueil (chaîne d'accueil en cours) : mêmes contrôles", function()
			local c = boot({ onboarding = { step = 5, p = 0 } })
			for _, tab in { "today", "calendar", "week", "welcome" } do
				openFresh(c, "Goals", tab)
				expect(c.PC.currentTab("Goals")).toBe(tab)
				checkScreen(c, "Goals/" .. tab)
			end
			finish(c)
		end)

		it("changement d'onglet ou de contenu : la sélection n'est jamais un objet masqué", function()
			local c = boot({ nebbies = { f1 = neb(2), f2 = neb(2), f3 = neb(2), u1 = neb(7) } })
			-- Objectifs : « Réclamer » de l'onglet Aujourd'hui, puis onglet Semaine
			openFresh(c, "Goals", "today")
			local claim = selected(c)
			expect(claim.Name).toBe("Claim")
			c.PC.open("Goals", { tab = "week" })
			frames(c, 3)
			Layout.apply(c.h)
			expect(selected(c) ~= claim).toBe(true)
			expect(selected(c):IsDescendantOf(window(c))).toBe(true)
			expect(Layout.selectable(selected(c))).toBe(true)
			-- Forge : bouton Fusionner sélectionné, la fusion retire la ligne
			openFresh(c, "Collection", "forge")
			local fuse = c.PC.page("Collection").Body.Tab_forge.List.Fusion1.Fuse
			c.h.game.GuiService.SelectedObject = fuse
			frames(c, 2)
			c.h:fireClient(REMOTES .. "DataPatch", { nebbies = { f1 = neb(2, 2), u1 = neb(7) } }, {})
			frames(c, 4)
			Layout.apply(c.h)
			expect(fuse.Parent.Visible).toBe(false)
			expect(selected(c) ~= fuse).toBe(true)
			expect(selected(c):IsDescendantOf(window(c))).toBe(true)
			expect(Layout.selectable(selected(c))).toBe(true)
			-- sélection partie derrière la fenêtre (HUD) : ramenée dans la fenêtre
			c.h.game.GuiService.SelectedObject = c.h.localPlayer.PlayerGui.HUD.Safe.Rail.Shop.Button
			frames(c, 2)
			expect(selected(c):IsDescendantOf(window(c))).toBe(true)
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Console G3 › en-tête à la manette", function()
		it(
			"○ sur Fermer (« ✕ » masqué), L1 / R1 aux bouts des onglets, L2 / R2 aux coins de l'en-tête",
			function()
				local c = boot()
				openFresh(c, "Collection", "perches")
				local page = c.PC.page("Collection")
				local close = page.Header.Close
				expect(glyph(close.PadGlyph)).toEqual(psGlyph("ButtonB"))
				expect(close.Label.Visible).toBe(false)
				expect(glyph(page.PadL1)).toEqual(psGlyph("ButtonL1"))
				expect(glyph(page.PadR1)).toEqual(psGlyph("ButtonR1"))
				expect(glyph(page.Header.PadL2)).toEqual(psGlyph("ButtonL2"))
				expect(glyph(page.Header.PadR2)).toEqual(psGlyph("ButtonR2"))
				-- les repères ne recouvrent ni les onglets ni le titre
				Layout.apply(c.h)
				local l1 = Layout.rect(page.PadL1)
				local firstTab = Layout.rect(page.Tabs.Tab_perches)
				expect(l1.x + l1.w <= firstTab.x + 0.5).toBe(true)
				local r1 = Layout.rect(page.PadR1)
				local lastTab = Layout.rect(page.Tabs.Tab_guide)
				expect(lastTab.x + lastTab.w <= r1.x + 0.5).toBe(true)
				local l2 = Layout.rect(page.Header.PadL2)
				local title = Layout.rect(page.Header.Title)
				local r2 = Layout.rect(page.Header.PadR2)
				expect(l2.x + l2.w <= title.x + 0.5).toBe(true)
				expect(title.x + title.w <= r2.x + 0.5).toBe(true)
				expect(r2.x + r2.w <= Layout.rect(close).x + 0.5).toBe(true)
				-- panneau sans onglets : ni L1 ni R1
				openFresh(c, "Crew")
				local crew = c.PC.page("Crew")
				expect(crew:FindFirstChild("PadL1")).toBeNil()
				expect(glyph(crew.Header.PadR2)).toEqual(psGlyph("ButtonR2"))
				-- Supernova : ○ sur Retour (« ‹ » masqué), △ (tout fermer) sur Fermer
				openFresh(c, "Supernova")
				local nova = c.PC.page("Supernova").Header
				expect(glyph(nova.Back.PadGlyph)).toEqual(psGlyph("ButtonB"))
				expect(nova.Back.Label.Visible).toBe(false)
				expect(glyph(nova.Close.PadGlyph)).toEqual(psGlyph("ButtonY"))
				-- écran de retour (hors du cycle L2 / R2) : pas de L2 / R2
				c.PC.close()
				frames(c, 8)
				panel(c, "ReturnScreen").present({ glow = 10, seconds = 60, nightShift = false })
				frames(c, 4)
				local back = c.PC.page("ReturnScreen").Header
				expect(back.PadL2.Visible).toBe(false)
				expect(back.PadR2.Visible).toBe(false)
				expect(glyph(back.Close.PadGlyph)).toEqual(psGlyph("ButtonB"))
				finish(c)
			end
		)

		it(
			"clavier-souris : « ✕ » dessiné, aucun repère de manette ; la manette reprise : repères",
			function()
				local c = boot()
				openFresh(c, "Collection", "perches")
				local page = c.PC.page("Collection")
				-- le joueur passe au clavier
				c.h.lastInputType = Enum.UserInputType.Keyboard
				c.h.game.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
				c.h:settle(2)
				expect(c.Platform.usingGamepad()).toBe(false)
				expect(page.Header.Close.Label.Visible).toBe(true)
				expect(page.Header.Close.PadGlyph.Visible).toBe(false)
				expect(page.PadL1.Visible).toBe(false)
				expect(page.Header.PadL2.Visible).toBe(false)
				expect(page.Tabs.Position.X.Offset).toBe(0)
				-- consigne tactile / clavier de la Réserve
				c.PC.open("Collection", { tab = "stash" })
				frames(c, 2)
				local detail = page.Body.Tab_stash.Actions.Detail
				expect(detail.Text).toBe("Tap a Nebby to see it")
				-- manette reprise
				Gamepad.tap(c.h, K.DPadDown)
				c.h:settle(2)
				expect(page.Header.Close.Label.Visible).toBe(false)
				expect(page.Header.Close.PadGlyph.Visible).toBe(true)
				expect(detail.Text).toBe("Choose a Nebby to see it")
				finish(c)
			end
		)
	end)

	-- =============================================================================================
	describe("Console G3 › ○, L1 / R1, L2 / R2", function()
		it(
			"○ recule d'un niveau : Supernova → Améliorer → bouton du rail d'origine (« Back »)",
			function()
				local c = boot()
				local railUpgrades = c.h.localPlayer.PlayerGui.HUD.Safe.Rail.Upgrades.Button
				-- △ : menu du HUD, sélection posée sur le bouton Améliorer du rail, ✕ l'ouvre
				Gamepad.tap(c.h, K.ButtonY)
				c.h.game.GuiService.SelectedObject = railUpgrades
				frames(c, 2)
				Gamepad.tap(c.h, K.ButtonA)
				frames(c, 8)
				expect(c.PC.current()).toBe("Upgrades")
				expect(selected(c):IsDescendantOf(window(c))).toBe(true)
				-- bouton Supernova, ✕ : aperçu
				local novaButton = c.PC.page("Upgrades").Body.SupernovaButton
				c.h.game.GuiService.SelectedObject = novaButton
				frames(c, 2)
				Gamepad.tap(c.h, K.ButtonA)
				frames(c, 8)
				expect(c.PC.current()).toBe("Supernova")
				expect(selected(c).Name).toBe("Hold")
				table.clear(c.sounds)
				-- ○ : retour à Améliorer, sur le bouton Supernova
				expect(Gamepad.tap(c.h, K.ButtonB)).toBe("PanelBack")
				frames(c, 4)
				expect(c.PC.current()).toBe("Upgrades")
				expect(selected(c)).toBe(novaButton)
				-- ○ : fermeture, sélection rendue au bouton du rail d'origine
				expect(Gamepad.tap(c.h, K.ButtonB)).toBe("PanelBack")
				frames(c, 8)
				expect(c.PC.current()).toBeNil()
				expect(selected(c)).toBe(railUpgrades)
				expect(count(c.sounds, "Back")).toBe(2)
				expect(count(c.sounds, "Whoosh")).toBe(0)
				-- ○ encore : le menu du HUD rend la main au jeu (InputController)
				expect(Gamepad.tap(c.h, K.ButtonB)).toBe("CC_Close")
				expect(selected(c)).toBeNil()
				-- panneau ouvert sans sélection d'origine (raccourci) : ○ ferme sans rien sélectionner
				c.Input.openPanel("Shop")
				frames(c, 8)
				Gamepad.tap(c.h, K.ButtonB)
				frames(c, 8)
				expect(c.PC.current()).toBeNil()
				expect(selected(c)).toBeNil()
				finish(c)
			end
		)

		it("L1 / R1 : onglets en boucle (« Tab »), sélection sur l'onglet", function()
			local c = boot()
			openFresh(c, "Collection", "perches")
			table.clear(c.sounds)
			local order = {}
			for _ = 1, 5 do
				expect(Gamepad.tap(c.h, K.ButtonR1)).toBe("PanelTabNext")
				table.insert(order, c.PC.currentTab("Collection"))
			end
			expect(order).toEqual({ "stash", "forge", "atlas", "guide", "perches" })
			expect(selected(c).Name).toBe("Tab_perches")
			expect(Gamepad.tap(c.h, K.ButtonL1)).toBe("PanelTabPrev")
			expect(c.PC.currentTab("Collection")).toBe("guide")
			expect(selected(c).Name).toBe("Tab_guide")
			expect(count(c.sounds, "Tab")).toBe(6)
			expect(count(c.sounds, "Click")).toBe(0)
			finish(c)
		end)

		it("L2 / R2 : panneaux en boucle, Supernova = Améliorer, garde du HUD ; R2 ne Dash pas", function()
			local c = boot()
			openFresh(c, "Upgrades")
			table.clear(c.sounds)
			local order = {}
			for _ = 1, 6 do
				expect(Gamepad.tap(c.h, K.ButtonR2)).toBe("PanelNext")
				frames(c, 2)
				table.insert(order, c.PC.current())
				expect(selected(c):IsDescendantOf(window(c))).toBe(true)
			end
			expect(order).toEqual({ "Collection", "Goals", "Shop", "Crew", "Settings", "Upgrades" })
			expect(Gamepad.tap(c.h, K.ButtonL2)).toBe("PanelPrev")
			expect(c.PC.current()).toBe("Settings")
			expect(count(c.sounds, "Tab")).toBe(7)
			expect(count(c.sounds, "Whoosh")).toBe(0)
			-- R2 n'a jamais envoyé de Dash
			expect(#sent(c, "Dash")).toBe(0)
			-- Supernova compte comme Améliorer
			openFresh(c, "Supernova")
			Gamepad.tap(c.h, K.ButtonR2)
			expect(c.PC.current()).toBe("Collection")
			openFresh(c, "Supernova")
			Gamepad.tap(c.h, K.ButtonL2)
			expect(c.PC.current()).toBe("Settings")
			-- garde du HUD : Objectifs et Boutique pas encore affichés → sautés
			c.Input.setPanelGate(function(name)
				return name ~= "Goals" and name ~= "Shop"
			end)
			openFresh(c, "Collection")
			Gamepad.tap(c.h, K.ButtonR2)
			expect(c.PC.current()).toBe("Crew")
			Gamepad.tap(c.h, K.ButtonL2)
			expect(c.PC.current()).toBe("Collection")
			-- seul Améliorer autorisé : L2 / R2 ne font rien et leurs repères disparaissent
			c.Input.setPanelGate(function(name)
				return name == "Upgrades"
			end)
			openFresh(c, "Upgrades")
			expect(Gamepad.tap(c.h, K.ButtonR2)).toBe("PanelNext")
			expect(c.PC.current()).toBe("Upgrades")
			expect(c.PC.page("Upgrades").Header.PadR2.Visible).toBe(false)
			expect(c.PC.cyclePanel(1)).toBe(false)
			expect(#sent(c, "Dash")).toBe(0)
			-- panneau fermé : R2 rend le Dash
			c.PC.close()
			frames(c, 8)
			c.h.game.GuiService.SelectedObject = nil
			expect(Gamepad.tap(c.h, K.ButtonR2)).toBe("CC_Dash")
			expect(#sent(c, "Dash")).toBe(1)
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Console G3 › stick droit et bout de liste", function()
		it("stick droit : défile la liste du panneau, absorbé ; relâché : s'arrête", function()
			local c = boot()
			openFresh(c, "Collection", "guide")
			local list = c.PC.page("Collection").Body.Tab_guide.List
			expect(list.CanvasPosition.Y).toBe(0)
			expect(Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, -1))).toBe("PanelScroll")
			laidFrames(c, 10)
			local y = list.CanvasPosition.Y
			expect(y > 0).toBe(true)
			-- zone morte : un stick à peine poussé ne fait rien
			Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, -0.15))
			laidFrames(c, 10)
			expect(list.CanvasPosition.Y).toBe(y)
			-- vers le haut : on remonte, jamais au-dessus de 0
			Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, 1))
			laidFrames(c, 60)
			expect(list.CanvasPosition.Y).toBe(0)
			-- bas de la liste : borné (la dernière ligne affichée en bas de la liste)
			Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, -1))
			laidFrames(c, 200)
			local bottom = list.CanvasPosition.Y
			laidFrames(c, 20)
			expect(list.CanvasPosition.Y).toBe(bottom)
			local last = nil
			for _, child in list:GetChildren() do
				if child:IsA("TextLabel") and (last == nil or child.LayoutOrder > last.LayoutOrder) then
					last = child
				end
			end
			local lastRect, view = Layout.rect(last), Layout.rect(list)
			expect(math.abs(lastRect.y + lastRect.h - (view.y + view.h)) < 2).toBe(true)
			Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, 0))
			-- panneau fermé : le stick droit est rendu à la caméra
			c.PC.close()
			frames(c, 8)
			expect(Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, -1))).toBeNil()
			finish(c)
		end)

		it("croix au bord (onglet de gauche, ←) : « Bump » et vibration « listEnd »", function()
			local c = boot()
			openFresh(c, "Collection", "perches")
			expect(selected(c).Name).toBe("Tab_perches")
			c.Clock.advance(1)
			table.clear(c.sounds)
			table.clear(c.played)
			Gamepad.tap(c.h, K.DPadLeft)
			frames(c, 3)
			expect(selected(c).Name).toBe("Tab_perches")
			expect(count(c.sounds, "Bump")).toBe(1)
			expect(c.played).toEqual({ "listEnd" })
			local effects = 0
			for _, entry in c.h.log.haptics do
				if entry.kind == "effect" and entry.type == Enum.HapticEffectType.UIClick then
					effects += 1
				end
			end
			expect(effects).toBe(1)
			-- une croix qui déplace la sélection : rien
			table.clear(c.sounds)
			Gamepad.tap(c.h, K.DPadRight)
			frames(c, 3)
			expect(selected(c).Name).toBe("Tab_stash")
			expect(count(c.sounds, "Bump")).toBe(0)
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Console G3 › Supernova à la manette", function()
		it(
			"maintien ✕ : relâchement anticipé = rien, « holdStart » journalisé ; 1 s = un envoi",
			function()
				local c = boot()
				goHome(c)
				openFresh(c, "Supernova")
				local hold = c.PC.page("Supernova").Body.Hold
				expect(selected(c)).toBe(hold)
				expect(glyph(hold.PadGlyph)).toEqual(psGlyph("ButtonA"))
				table.clear(c.h.log.haptics)
				table.clear(c.played)
				-- relâché trop tôt
				Gamepad.press(c.h, K.ButtonA)
				frames(c, 8)
				Gamepad.release(c.h, K.ButtonA)
				frames(c, 40)
				expect(#sent(c, "Supernova")).toBe(0)
				expect(c.played[1]).toBe("holdStart")
				expect(c.h.log.haptics[1].kind).toBe("effect")
				expect(c.h.log.haptics[1].type).toBe(Enum.HapticEffectType.UIClick)
				-- maintenu 1 s
				c.Clock.advance(1)
				Gamepad.press(c.h, K.ButtonA)
				frames(c, 40)
				expect(#sent(c, "Supernova")).toBe(1)
				Gamepad.release(c.h, K.ButtonA)
				frames(c, 12)
				expect(count(c.played, "holdStart")).toBe(2)
				finish(c)
			end
		)

		it("hors du port sûr : refus avec vibration « refuse », rien d'envoyé", function()
			local c = boot()
			goAway(c)
			openFresh(c, "Supernova")
			c.Clock.advance(1)
			table.clear(c.played)
			Gamepad.press(c.h, K.ButtonA)
			frames(c, 40)
			Gamepad.release(c.h, K.ButtonA)
			frames(c, 4)
			expect(#sent(c, "Supernova")).toBe(0)
			expect(c.played).toEqual({ "refuse" })
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Console G3 › Boutique", function()
		it(
			"après la fenêtre d'achat Roblox, la sélection revient sur le bouton Acheter pressé",
			function()
				local c = boot()
				openFresh(c, "Shop", "passes")
				local buy = c.PC.page("Shop").Body.Tab_passes.VIPStar.Buy
				c.h.game.GuiService.SelectedObject = buy
				frames(c, 2)
				Gamepad.tap(c.h, K.ButtonA)
				expect(#c.h.log.prompts).toBe(1)
				expect(c.h.log.prompts[1].id).toBe(PASS_ID)
				-- la fenêtre Roblox prend la manette : sélection du jeu effacée
				c.h.game.GuiService.SelectedObject = nil
				frames(c, 4)
				expect(selected(c)).toBeNil()
				c.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(
					c.h.localPlayer,
					PASS_ID,
					false
				)
				frames(c, 2)
				expect(selected(c)).toBe(buy)
				-- produit (onglet Boosts & Glow)
				c.Clock.advance(2)
				c.PC.open("Shop", { tab = "boosts" })
				frames(c, 4)
				local pouch = c.PC.page("Shop").Body.Tab_boosts.GlowPouch.Buy
				c.h.game.GuiService.SelectedObject = pouch
				frames(c, 2)
				Gamepad.tap(c.h, K.ButtonA)
				expect(c.h.log.prompts[2].id).toBe(PRODUCT_ID)
				c.h.game.GuiService.SelectedObject = nil
				c.h.game.MarketplaceService.PromptProductPurchaseFinished:Fire(
					c.h.localPlayer.UserId,
					PRODUCT_ID,
					true
				)
				frames(c, 2)
				expect(selected(c)).toBe(pouch)
				-- panneau fermé entre-temps : rien n'est sélectionné
				c.Clock.advance(2)
				Gamepad.tap(c.h, K.ButtonA)
				c.PC.close()
				frames(c, 8)
				c.h.game.MarketplaceService.PromptProductPurchaseFinished:Fire(
					c.h.localPlayer.UserId,
					PRODUCT_ID,
					false
				)
				frames(c, 2)
				expect(selected(c)).toBeNil()
				finish(c)
			end
		)

		it("Codes : Entrée du clavier virtuel → code envoyé, sélection sur « Valider »", function()
			local c = boot()
			local received = {}
			c.h:find(REMOTES .. "RedeemCode").OnServerInvoke = function(_, code)
				table.insert(received, code)
				return "ok"
			end
			openFresh(c, "Shop", "codes")
			local codes = c.PC.page("Shop").Body.Tab_codes
			expect(selected(c)).toBe(codes.CodeBox)
			codes.CodeBox.Text = "lumora2026"
			codes.CodeBox.FocusLost:Fire(true)
			c.h:settle(3)
			frames(c, 2)
			expect(received).toEqual({ "LUMORA2026" })
			expect(selected(c)).toBe(codes.Redeem)
			-- champ quitté sans Entrée : rien n'est envoyé
			codes.CodeBox.Text = "OTHER"
			codes.CodeBox.FocusLost:Fire(false)
			c.h:settle(3)
			expect(#received).toBe(1)
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Console G3 › Réserve virtualisée à la croix", function()
		it(
			"60 Nebbies : la croix ↓ fait défiler d'une rangée, tous atteignables jusqu'au dernier",
			function()
				local c = boot({ stash = 60 })
				openFresh(c, "Collection", "stash")
				local C = panel(c, "Collection")
				local st = C._state()
				local total = #st.sorted
				expect(total).toBe(63)
				-- virtualisée : une poignée de cases affichées
				local shown = 0
				for _, cell in st.grid:cells() do
					if cell.Visible then
						shown += 1
					end
				end
				expect(shown <= 40).toBe(true)
				-- ↓ depuis « Sélectionner » : première case
				expect(selected(c).Name).toBe("Select")
				Gamepad.tap(c.h, K.DPadDown)
				local index = stashIndex(c)
				expect(index >= 1).toBe(true)
				-- ← jusqu'à la première case
				for _ = 1, 10 do
					if stashIndex(c) == 1 then
						break
					end
					Gamepad.tap(c.h, K.DPadLeft)
				end
				expect(stashIndex(c)).toBe(1)
				local columns = st.grid._columns
				expect(columns >= 2).toBe(true)
				-- chaque rangée : → jusqu'au bout (case par case), ← jusqu'à son début, puis ↓
				local visited = {}
				local function visit()
					local i, uid = stashIndex(c)
					expect(i > 0).toBe(true)
					expect(uid).toBe(st.sorted[i])
					visited[uid] = true
					return i
				end
				local rowStart = visit()
				for _ = 1, 20 do
					local rowEnd = math.min(rowStart + columns - 1, total)
					for k = rowStart + 1, rowEnd do
						Gamepad.tap(c.h, K.DPadRight)
						expect(visit()).toBe(k)
					end
					for k = rowEnd - 1, rowStart, -1 do
						Gamepad.tap(c.h, K.DPadLeft)
						expect(stashIndex(c)).toBe(k)
					end
					Gamepad.tap(c.h, K.DPadDown)
					local after = stashIndex(c)
					if after ~= rowStart + columns then
						break
					end
					rowStart = visit()
				end
				local n = 0
				for _ in visited do
					n += 1
				end
				expect(n).toBe(total)
				-- le dernier Nebby a été atteint et la grille a défilé
				expect(visited[st.sorted[total]]).toBe(true)
				expect(st.grid.scroll.CanvasPosition.Y > 0).toBe(true)
				-- ↑ jusqu'en haut : la grille remonte
				for _ = 1, 20 do
					Gamepad.tap(c.h, K.DPadUp)
					if stashIndex(c) == 0 then
						break
					end
				end
				expect(st.grid.scroll.CanvasPosition.Y).toBe(0)
				finish(c)
			end
		)

		it(
			"défilement au stick droit : la sélection suit l'index, puis reste dans la grille visible",
			function()
				local c = boot({ stash = 60 })
				openFresh(c, "Collection", "stash")
				local C = panel(c, "Collection")
				local st = C._state()
				Gamepad.tap(c.h, K.DPadDown)
				Gamepad.tap(c.h, K.DPadDown)
				local index, uid = stashIndex(c)
				expect(index > 1).toBe(true)
				-- défilement d'une demi-rangée : la case réaffectée garde le même Nebby sélectionné
				Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, -0.5))
				frames(c, 2)
				Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, 0))
				local i2, uid2 = stashIndex(c)
				expect(i2).toBe(index)
				expect(uid2).toBe(uid)
				-- très loin : la sélection reste sur une rangée entièrement visible
				Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, -1))
				frames(c, 60)
				Gamepad.stick(c.h, K.Thumbstick2, Vector2.new(0, 0))
				frames(c, 2)
				local i3 = stashIndex(c)
				expect(i3 > index).toBe(true)
				Layout.apply(c.h)
				-- case (pas le bouton, grossi de 6 % quand il est sélectionné)
				local cell = Layout.rect(selected(c).Parent)
				local view = Layout.rect(st.grid.scroll)
				expect(cell.y >= view.y - 0.5 and cell.y + cell.h <= view.y + view.h + 0.5).toBe(true)
				finish(c)
			end
		)

		it("consignes à la manette : « Choose a Nebby… », « Choose Nebbies to release »", function()
			local c = boot()
			openFresh(c, "Collection", "stash")
			local detail = c.PC.page("Collection").Body.Tab_stash.Actions.Detail
			expect(detail.Text).toBe("Choose a Nebby to see it")
			panel(c, "Collection")._setSelectMode(true)
			expect(detail.Text).toBe("Choose Nebbies to release")
			finish(c)
		end)
	end)

	-- =============================================================================================
	describe("Console G3 › carte d'invitation d'équipage", function()
		it(
			"focusTarget → Accepter (repère △ puis ✕), Accepter ↔ Refuser ; △ la sélectionne, → puis ✕ refuse",
			function()
				local c = boot()
				c.h:addPlayer({ userId = 2, name = "Mira" })
				c.h:settle(2)
				expect(c.PC.focusTarget()).toBeNil()
				c.h:fireClient(REMOTES .. "CrewInvitePrompt", { inviterId = 2, expiresAt = T0 + 20 })
				frames(c, 4)
				local card = c.h.localPlayer.PlayerGui.Panels.Safe.CrewInvite
				local accept, decline = card.Accept, card.Decline
				expect(c.PC.focusTarget()).toBe(accept)
				expect(accept.NextSelectionRight).toBe(decline)
				expect(decline.NextSelectionLeft).toBe(accept)
				-- rien n'est sélectionné en jeu : le repère montre △ (✕ ferait sauter le personnage)
				expect(glyph(accept.PadGlyph)).toEqual(psGlyph("ButtonY"))
				expect(accept.Label.Text).toBe("Join")
				expect(decline.Label.Text).toBe("No thanks")
				expect(card.SelectionBehaviorUp).toBe(Enum.SelectionBehavior.Stop)
				-- △ depuis le jeu : la carte d'abord
				c.h.game.GuiService.SelectedObject = nil
				Gamepad.tap(c.h, K.ButtonY)
				expect(selected(c)).toBe(accept)
				-- Accepter sélectionné : ✕ valide
				expect(glyph(accept.PadGlyph)).toEqual(psGlyph("ButtonA"))
				Layout.apply(c.h)
				expect(Layout.names(Layout.escapes(c.h, card, accept))).toBe("")
				expect(Layout.names(Layout.unreachable(c.h, card, accept))).toBe("")
				expect(table.concat(Gamepad.audit(c.h, { root = card }), "\n")).toBe("")
				-- → puis ✕ : refusée, carte retirée, sélection effacée
				Gamepad.tap(c.h, K.DPadRight)
				expect(selected(c)).toBe(decline)
				-- depuis Refuser : ← mène à Accepter
				expect(accept.PadGlyph:GetAttribute("GlyphKey")).toBe("DPadLeft")
				Gamepad.tap(c.h, K.ButtonA)
				frames(c, 2)
				local respond = sent(c, "CrewRespond")
				expect(#respond).toBe(1)
				expect(respond[1][1]).toBe(2)
				expect(respond[1][2]).toBe(false)
				expect(card.Visible).toBe(false)
				expect(selected(c)).toBeNil()
				expect(c.PC.focusTarget()).toBeNil()
				finish(c)
			end
		)
	end)
end
