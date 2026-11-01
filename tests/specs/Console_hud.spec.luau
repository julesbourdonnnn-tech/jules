--!nocheck
-- Console PS5, groupe G2 « HUD et écrans permanents » (docs/07-console-ps5.md §3-§7, §11 G2) : le VRAI
-- client démarré en console (Main.client, 1920 × 1080, UIScale 1,5, zone sûre 64 × 36), manette seule.
--   * icônes de touches « PadGlyph » (UI/Glyph) en images PlayStation : R2 Dash, croix ↑ Ping,
--     croix ↓ minicarte, croix → ACCLAMER, croix ← suivi de quête, △ au-dessus du rail ; touches
--     clavier « KeyCap » masquées ; cadre de sélection commun sur chaque bouton du HUD et la minicarte
--   * Gamepad.audit vide avec une bannière, 3 toasts, un tampon, un floater et la minicarte agrandie
--   * aucun chevauchement à 1080p : rangée du haut, colonne de droite, rail, compteur de file,
--     Dash / Ping, ACCLAMER, instruction d'accueil (icônes comprises)
--   * △ : carte d'invitation (PanelController.focusTarget()) > cible de l'accueil > pastille « ! » >
--     dernier panneau du rail ouvert > premier bouton ; Layout.unreachable vide sur le HUD et la minicarte (HUD complet,
--     ACCLAMER affiché, accueil Q1-Q3) ; ↑ depuis le 1er bouton du rail → Équipage
--   * croix ← replie le suivi de quête (InputController.QuestToggled)
--   * accueil à la manette : « Open Upgrade » + △, puis ✕ une fois Améliorer sélectionné ; la main
--     devient l'icône de la touche (R2 pendant la pulsation du Dash, Q5)
--   * écran de chargement : échelle TV (1,5 en 1080p, sans plafond), constantes égales à
--     Config/Console, « Réessayer » sélectionné avec l'icône ✕ PlayStation
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000
	local PS = Gamepad.PS_GLYPHS

	-- Client console complet (Main.client) avec un instantané de profil. La boutique a un article
	-- (id renseigné) : son icône fait partie du HUD complet (sans article, elle reste cachée)
	local function boot(snapshot, locale)
		local h = Harness.new({ mode = "client", console = true })
		h.localPlayer.LocaleId = locale or "en-us"
		h:createRemotes()
		h:require("ReplicatedStorage.Shared.Config.Monetization").Passes.DoubleGlow.id = 1
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h:boot()
		h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", snapshot)
		h:step(1 / 60, 30)
		h:settle(3)
		local c = {
			h = h,
			Clock = Clock,
			HUD = h:require(CLIENT .. "UI.HUD"),
			Root = h:require(CLIENT .. "UI.Root"),
			Minimap = h:require(CLIENT .. "UI.Minimap"),
			Banners = h:require(CLIENT .. "UI.Banners"),
			Toast = h:require(CLIENT .. "UI.Toast"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			Onboarding = h:require(CLIENT .. "Controllers.OnboardingController"),
			Platform = h:require(CLIENT .. "Util.Platform"),
		}
		return c
	end

	local function full()
		return boot({ glow = 5000, onboarding = { step = 8, p = 0 } })
	end

	local function gui(c, name)
		return c.h.localPlayer.PlayerGui[name].Safe
	end

	local function frames(c, n)
		c.h:step(1 / 30, n or 10)
		c.h:settle(2)
	end

	local function clearSelection(c)
		c.h.game.GuiService.SelectedObject = nil
		c.h:settle(1)
	end

	-- △ depuis le jeu (aucune sélection) ; retourne l'objet sélectionné
	local function triangle(c)
		clearSelection(c)
		Gamepad.tap(c.h, Enum.KeyCode.ButtonY)
		return Gamepad.selected(c.h)
	end

	local function cheerPrompt(c)
		c.HUD._onCheerPrompt({ heroId = 42, level = 3, expiresAt = c.Clock.now() + 10 })
		frames(c, 3)
	end

	local function expectEmpty(list, label)
		expect({ label = label, issues = table.concat(list, "\n") }).toEqual({ label = label, issues = "" })
	end

	local function expectReachable(c, start, label)
		Layout.apply(c.h)
		local playerGui = c.h.localPlayer.PlayerGui
		for _, root in { playerGui.HUD, playerGui.Minimap } do
			local missing = Layout.names(Layout.unreachable(c.h, root, start))
			expect({ label = label, root = root.Name, unreachable = missing }).toEqual({
				label = label,
				root = root.Name,
				unreachable = "",
			})
		end
	end

	local function glyphOf(frame)
		return {
			key = frame:GetAttribute("GlyphKey"),
			mode = frame:GetAttribute("GlyphMode"),
			image = frame.Image.Image,
			visible = Layout.visible(frame),
		}
	end

	local function psGlyph(key)
		local ps = ({
			ButtonA = "ButtonCross",
			ButtonY = "ButtonTriangle",
		})[key] or key
		return { key = key, mode = "image", image = PS .. ps .. "@2x.png", visible = true }
	end

	-- Blocs du HUD (rectangles d'écran, px) : chacun avec son propriétaire ; deux blocs de propriétaires
	-- différents ne doivent jamais se chevaucher
	local function blocks(c)
		Layout.apply(c.h)
		local hud = gui(c, "HUD")
		local out = {}
		local function add(owner, obj)
			if obj ~= nil and Layout.visible(obj) then
				local r = Layout.rect(obj)
				if r and r.w > 0 and r.h > 0 then
					table.insert(out, { owner = owner, name = Layout.name(obj), r = r })
				end
			end
		end
		local function withGlyph(owner, holder)
			add(owner, holder)
			if holder then
				for _, d in holder:GetDescendants() do
					if d.Name == "PadGlyph" then
						add(owner, d)
					end
				end
			end
		end
		for _, name in { "Glow", "Stardust", "crew", "settings", "EventPill", "Status", "LineCounter" } do
			withGlyph(name, hud:FindFirstChild(name))
		end
		add("EventPill", hud.EventPill:FindFirstChild("BeaconBar"))
		add("Status", hud.Status:FindFirstChild("Caption"))
		withGlyph("QuestTracker", hud.QuestTracker)
		withGlyph("Rail", hud.Rail)
		withGlyph("Rail", hud.RailGlyph)
		withGlyph("Dash", hud.Dash)
		withGlyph("Ping", hud.Ping)
		withGlyph("Cheer", hud.Cheer)
		withGlyph("Minimap", gui(c, "Minimap").Minimap)
		add("Hint", gui(c, "Onboarding"):FindFirstChild("Hint"))
		add("HandGlyph", hud:FindFirstChild("HandGlyph"))
		return out
	end

	local function overlaps(c)
		local list = blocks(c)
		local bad = {}
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				if a.owner ~= b.owner then
					local ra, rb = a.r, b.r
					if
						ra.x < rb.x + rb.w
						and rb.x < ra.x + ra.w
						and ra.y < rb.y + rb.h
						and rb.y < ra.y + ra.h
					then
						table.insert(bad, `{a.name} × {b.name}`)
					end
				end
			end
		end
		table.sort(bad)
		return bad, #list
	end

	describe("Console HUD › HUD complet en 1920 × 1080", function()
		it(
			"icônes PlayStation sur les boutons, touches clavier masquées, plus aucun « X » ni « ↑ »",
			function()
				local c = full()
				cheerPrompt(c)
				local hud = gui(c, "HUD")
				expect(hud.RootScale.Scale).toBe(1.5)
				expect(glyphOf(hud.Dash.Button.PadGlyph)).toEqual(psGlyph("ButtonR2"))
				expect(glyphOf(hud.Ping.Button.PadGlyph)).toEqual(psGlyph("DPadUp"))
				expect(glyphOf(gui(c, "Minimap").Minimap.PadGlyph)).toEqual(psGlyph("DPadDown"))
				expect(glyphOf(hud.Cheer.PadGlyph)).toEqual(psGlyph("DPadRight"))
				expect(glyphOf(hud.QuestTracker.PadGlyph)).toEqual(psGlyph("DPadLeft"))
				expect(glyphOf(hud.RailGlyph.PadGlyph)).toEqual(psGlyph("ButtonY"))
				-- △ au-dessus du rail, centré, sous la pastille Stardust
				Layout.apply(c.h)
				local rail, tri = Layout.rect(hud.Rail), Layout.rect(hud.RailGlyph.PadGlyph)
				expect(tri.y + tri.h <= rail.y).toBe(true)
				expect(math.abs((tri.x + tri.w / 2) - (rail.x + rail.w / 2)) < 0.5).toBe(true)
				expect(tri.y >= Layout.rect(hud.Stardust).y + Layout.rect(hud.Stardust).h).toBe(true)
				-- console : rail en colonne (pas de joystick tactile)
				expect(c.HUD._state().railColumns).toBe(1)
				-- touches du clavier masquées ; aucun texte « X » / « ↑ » visible
				for _, d in c.h.localPlayer.PlayerGui:GetDescendants() do
					if d.Name == "KeyCap" then
						expect({ cap = Layout.name(d), visible = Layout.visible(d) }).toEqual({
							cap = Layout.name(d),
							visible = false,
						})
					end
					if d:IsA("TextLabel") and Layout.visible(d) and (d.Text == "X" or d.Text == "↑") then
						expect(Layout.name(d)).toBe("aucun repère de touche en texte")
					end
				end
				expect(#c.h.errors).toBe(0)
			end
		)

		it("cadre de sélection doré commun sur chaque bouton du HUD et sur la minicarte", function()
			local c = full()
			cheerPrompt(c)
			local image = c.Root.selectionImage()
			local count = 0
			local roots = { gui(c, "HUD"), gui(c, "Minimap") }
			for _, root in roots do
				for _, d in root:GetDescendants() do
					if d:IsA("GuiButton") then
						count += 1
						expect({ button = Layout.name(d), image = d.SelectionImageObject == image }).toEqual({
							button = Layout.name(d),
							image = true,
						})
					end
				end
			end
			expect(count >= 11).toBe(true)
		end)

		it(
			"aucun chevauchement (ACCLAMER affiché) ; barre de la Balise sous la pastille, à côté de Réglages",
			function()
				local c = full()
				cheerPrompt(c)
				-- colonne de droite au complet : débutant, boost avec minuteur, connexion instable + légende
				local player = c.h.localPlayer
				player:SetAttribute("Rookie", true)
				player:SetAttribute("Unstable", true)
				c.h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ boosts = { personalUntil = T0 + 900 } },
					{}
				)
				frames(c, 10)
				expect(gui(c, "HUD").Status.Caption.Visible).toBe(true)
				local bad, n = overlaps(c)
				expect(n >= 18).toBe(true)
				expectEmpty(bad, "HUD complet + ACCLAMER")
				-- Balise : barre affichée, rétrécie dans la zone sûre TV pour ne pas toucher Réglages
				local hud = gui(c, "HUD")
				hud.EventPill.BeaconBar.Visible = true
				c.HUD._layoutActions()
				bad = overlaps(c)
				expectEmpty(bad, "barre de la Balise")
				expect(hud.EventPill.BeaconBar.Size.X.Offset).toBe(320)
			end
		)

		it(
			"Gamepad.audit vide avec une bannière, 3 toasts, un tampon, un floater et la minicarte agrandie",
			function()
				local c = full()
				cheerPrompt(c)
				c.Banners.show({
					kind = "megaParade",
					args = { userId = 7, name = "Mira", n = 32 },
					priority = 4,
				})
				c.Toast.show("Quest complete!", "success")
				c.Toast.show("Boost ×2 for 15 min", "reward")
				c.Toast.show("Not enough Glow", "error")
				c.FX.stamp("PARADE ×2.36!", Color3.new(1, 1, 1), "parade")
				c.FX.stamp("FULL!", Color3.new(1, 0, 0), "small")
				-- floater demandé au bord de l'écran : gardé dans la zone sûre TV
				c.FX.floater("+1,200", Vector2.new(4, 1076), Color3.new(1, 1, 1))
				c.FX.floater("+35 ✦", Vector2.new(960, 300), Color3.new(1, 1, 1))
				-- titre de Supernova et carte « NOUVEAU ! » de l'Atlas
				c.FX._onCelebrate({ kind = "supernova", data = { level = 4 } })
				c.FX._onCelebrate({ kind = "atlasNew", data = { entries = { { s = 1, f = 1 } } } })
				Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
				frames(c, 6)
				expect(c.Minimap.isExpanded()).toBe(true)
				expect(gui(c, "Minimap").Minimap.Size.X.Offset).toBe(300)
				expect(c.Banners.current() ~= nil).toBe(true)
				local shown = 0
				for _, t in gui(c, "Toasts").Stack:GetChildren() do
					if t.Name == "Toast" then
						shown += 1
					end
				end
				expect(shown).toBe(3)
				local stamp = c.FX._state().stamps.big.label
				expect(stamp.Visible).toBe(true)
				expectEmpty(Gamepad.audit(c.h), "audit console")
				-- minicarte agrandie : disque et icône dans la zone sûre TV (5 %)
				Layout.apply(c.h)
				local r = Layout.rect(gui(c, "Minimap").Minimap.Disc)
				expect(r.x >= 96 and r.y >= 54 and r.x + r.w <= 1824 and r.y + r.h <= 1026).toBe(true)
				expect(#c.h.errors).toBe(0)
			end
		)
	end)

	describe("Console HUD › textes en français et en anglais", function()
		it(
			"audit ≥ 18 px en en-us et fr-fr : Comète portée par un nom long, HUD complet, ACCLAMER",
			function()
				for _, locale in { "en-us", "fr-fr" } do
					local c = boot({ glow = 5000, onboarding = { step = 8, p = 0 } }, locale)
					local player = c.h.localPlayer
					player.DisplayName = "SuperLongPlayerName20"
					cheerPrompt(c)
					c.h:fireClient("ReplicatedStorage.Remotes.EventState", {
						t = c.Clock.now(),
						wisps = {},
						snipsDisabled = false,
						activePlayers = 2,
						comet = {
							id = T0 - 10,
							phase = "carried",
							x = 0,
							z = 0,
							code = 1700,
							warnAt = T0 - 30,
							impactAt = T0 - 10,
							burstAt = T0 + 45,
							carrierId = player.UserId,
							carrierSince = T0 - 2,
						},
					})
					c.h:settle(2)
					frames(c, 12)
					local label = gui(c, "HUD").EventPill.Pill.Text
					local expected = if locale == "fr-fr" then "COMÈTE" else "COMET"
					expect({ locale = locale, comet = string.find(label.Text, expected, 1, true) ~= nil }).toEqual({
						locale = locale,
						comet = true,
					})
					-- nom coupé, jamais le nom entier qui ferait rétrécir le texte sous 18 px
					expect({ locale = locale, cut = string.find(label.Text, "SuperLongP…", 1, true) ~= nil }).toEqual({
						locale = locale,
						cut = true,
					})
					expectEmpty(Gamepad.audit(c.h), "audit " .. locale)
					expect(#c.h.errors).toBe(0)
				end
			end
		)
	end)

	describe("Console HUD › △ et navigation", function()
		it("△ : premier bouton, dernier panneau du rail ouvert, pastille « ! », focusTarget", function()
			local c = full()
			local rail = gui(c, "HUD").Rail
			for _, name in { "Upgrades", "Collection", "Goals", "Shop", "Crew", "Settings" } do
				c.Panels.BadgeChanged:Fire(name, false)
			end
			c.h:settle(1)
			expect(triangle(c)).toBe(rail.Upgrades.Button)
			-- dernier panneau du rail ouvert (Supernova compte comme Améliorer)
			c.Panels.open("Shop")
			c.h:settle(2)
			c.Panels.close()
			c.h:settle(2)
			expect(triangle(c)).toBe(rail.Shop.Button)
			-- pastille « ! » prioritaire
			c.Panels.BadgeChanged:Fire("Collection", true)
			c.h:settle(1)
			expect(triangle(c)).toBe(rail.Collection.Button)
			-- cible hors fenêtre de PanelController (carte d'invitation) prioritaire
			local target = gui(c, "HUD").settings.Button
			c.Panels.focusTarget = function()
				return target
			end
			expect(triangle(c)).toBe(target)
			-- cible cachée : ignorée
			target.Visible = false
			expect(triangle(c)).toBe(rail.Collection.Button)
			target.Visible = true
			c.Panels.focusTarget = function()
				error("panne simulée")
			end
			expect(triangle(c)).toBe(rail.Collection.Button)
			expect(#c.h.errors).toBe(0)
		end)

		it(
			"HUD complet : tout le HUD et la minicarte atteignables depuis △ ; ↑ depuis le rail → Équipage",
			function()
				local c = full()
				local hud = gui(c, "HUD")
				local start = triangle(c)
				expect(start ~= nil).toBe(true)
				expectReachable(c, start, "HUD complet")
				expect(hud.Rail.Upgrades.Button.NextSelectionUp).toBe(hud.crew.Button)
				expect(hud.crew.Button.NextSelectionDown).toBe(hud.Rail.Upgrades.Button)
				expect(hud.settings.Button.NextSelectionRight).toBe(gui(c, "Minimap").Minimap.Disc)
				-- le rail s'arrête en bas (ACCLAMER absent)
				expect(hud.Rail.Shop.Button.NextSelectionDown).toBeNil()
				-- parcours à la croix : △, ↑ Équipage, → Réglages, → minicarte, ↓ suivi, ↓ Dash, ← Ping
				clearSelection(c)
				c.Panels.BadgeChanged:Fire("Goals", false)
				c.h:settle(1)
				local path = {}
				Gamepad.tap(c.h, Enum.KeyCode.ButtonY)
				for _, key in { "DPadUp", "DPadRight", "DPadRight", "DPadDown", "DPadDown", "DPadLeft" } do
					Gamepad.tap(c.h, Enum.KeyCode[key])
					table.insert(path, Layout.name(Gamepad.selected(c.h)))
				end
				expect(path).toEqual({
					"HUD.Safe.crew.Button",
					"HUD.Safe.settings.Button",
					"Minimap.Safe.Minimap.Disc",
					"HUD.Safe.QuestTracker.Pill.Toggle.Button",
					"HUD.Safe.Dash.Button",
					"HUD.Safe.Ping.Button",
				})
			end
		)

		it(
			"ACCLAMER affiché : atteignable (→ depuis le rail), sélection rendue quand il disparaît",
			function()
				local c = full()
				cheerPrompt(c)
				local hud = gui(c, "HUD")
				local start = triangle(c)
				expectReachable(c, start, "ACCLAMER")
				expect(hud.Rail.Upgrades.Button.NextSelectionRight).toBe(hud.Cheer.Button)
				expect(hud.Cheer.Button.NextSelectionRight).toBe(hud.Ping.Button)
				c.h.game.GuiService.SelectedObject = hud.Cheer.Button
				c.h:settle(1)
				-- 10 s plus tard, le bouton disparaît : la sélection revient au rail
				c.Clock.advance(11)
				frames(c, 3)
				expect(c.HUD._state().cheer).toBeNil()
				local selected = Gamepad.selected(c.h)
				expect(selected ~= hud.Cheer.Button).toBe(true)
				expect(selected == nil or selected:IsDescendantOf(hud.Rail)).toBe(true)
				expect(hud.Rail.Upgrades.Button.NextSelectionRight ~= hud.Cheer.Button).toBe(true)
			end
		)

		it("croix ← replie puis déplie le suivi de quête", function()
			local c = full()
			local tracker = gui(c, "HUD").QuestTracker
			expect(c.HUD._state().trackerParts.collapsed).toBe(false)
			Gamepad.tap(c.h, Enum.KeyCode.DPadLeft)
			frames(c, 3)
			expect(c.HUD._state().trackerParts.collapsed).toBe(true)
			expect(tracker.Pill.Size.X.Offset).toBe(72)
			-- l'icône suit le bord gauche de la pastille repliée
			Layout.apply(c.h)
			local pill, glyph = Layout.rect(tracker.Pill), Layout.rect(tracker.PadGlyph)
			expect(glyph.x + glyph.w <= pill.x).toBe(true)
			expect(pill.x - (glyph.x + glyph.w) < 16).toBe(true)
			Gamepad.tap(c.h, Enum.KeyCode.DPadLeft)
			frames(c, 3)
			expect(c.HUD._state().trackerParts.collapsed).toBe(false)
			expect(tracker.Pill.Size.X.Offset).toBe(260)
		end)
	end)

	describe("Console HUD › accueil à la manette (Q1-Q3, Q5)", function()
		local function onboarding()
			return boot({
				glow = 5000,
				onboarding = { step = 1, p = 0 },
				stats = { parades = 1, sessions = 0 },
				upgrades = { conga = 0 },
			})
		end

		-- profil modifié, puis 2 s : les éléments révélés ont fini leur pop et leur pulsation (1,4 s)
		local function patch(c, data)
			c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", data, {})
			frames(c, 60)
		end

		it(
			"Q1 : « Open Upgrade » avec △, puis ✕ une fois Améliorer sélectionné ; pas de main",
			function()
				local c = onboarding()
				frames(c, 12)
				expect(c.Onboarding.currentHint()).toBe("onboarding.openUpgrade")
				local hint = gui(c, "Onboarding").Hint
				expect(hint.Text.Text).toBe("Open Upgrade")
				expect(glyphOf(hint.PadGlyph)).toEqual(psGlyph("ButtonY"))
				expect(hint.Icon.Visible).toBe(false)
				local hud = gui(c, "HUD")
				expect(c.HUD._state().hand.Visible).toBe(false)
				expect(glyphOf(hud.HandGlyph)).toEqual(psGlyph("ButtonY"))
				expectEmpty(Gamepad.audit(c.h), "audit Q1")
				expectEmpty(overlaps(c), "chevauchements Q1")
				-- △ : la cible de l'accueil (Améliorer) est sélectionnée, puis ✕
				local upgrades = hud.Rail.Upgrades.Button
				expect(triangle(c)).toBe(upgrades)
				frames(c, 4)
				expect(glyphOf(hint.PadGlyph)).toEqual(psGlyph("ButtonA"))
				expect(glyphOf(hud.HandGlyph)).toEqual(psGlyph("ButtonA"))
				-- le Dash (seul autre bouton affiché) est atteignable
				expectReachable(c, upgrades, "Q1")
				expect(upgrades.NextSelectionRight).toBe(hud.Dash.Button)
				-- ✕ ouvre Améliorer
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				c.h:settle(2)
				expect(c.Panels.current()).toBe("Upgrades")
				expect(#c.h.errors).toBe(0)
			end
		)

		it(
			"Q6 (« Weather soon! ») : la pastille d'événement qui pulse ne touche jamais Réglages (zone sûre TV)",
			function()
				local c = boot({
					glow = 5000,
					onboarding = { step = 6, p = 0 },
					stats = { parades = 12, sessions = 0 },
					upgrades = { conga = 3 },
				})
				-- aucune fenêtre météo ouverte, la prochaine donne une forme : la pastille pulse
				local EventClock = c.h:require("ReplicatedStorage.Shared.Logic.EventClock")
				local t = T0
				for _ = 1, 200 do
					local w = EventClock.nextWeather(t)
					if w.form ~= nil then
						break
					end
					t = w.endsAt + 1
				end
				c.Clock.freeze(t)
				frames(c, 40)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeather")
				expect(c.Onboarding._state().attention.eventPill).toBe(true)
				local hud = gui(c, "HUD")
				local biggest = 1
				for _ = 1, 30 do -- plus d'une période de pulsation (0,8 s)
					frames(c, 1)
					biggest = math.max(biggest, hud.EventPill.HudScale.Scale)
					expectEmpty(overlaps(c), "chevauchements Q6")
					Layout.apply(c.h)
					local pill, settings = Layout.rect(hud.EventPill.Pill), Layout.rect(hud.settings)
					-- au moins 8 px de référence (12 px à l'échelle 1,5) entre Réglages et la pastille
					expect(pill.x - (settings.x + settings.w) >= 12 - 1e-3).toBe(true)
				end
				expect(biggest > 1.075).toBe(true)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("Q2 puis Q3 : HUD partiel entièrement atteignable depuis △, sans chevauchement", function()
			local c = onboarding()
			frames(c, 12)
			patch(c, { onboarding = { step = 2, p = 0 }, upgrades = { conga = 1 } })
			expect(c.HUD.isRevealed("settings")).toBe(true)
			expect(c.HUD.isRevealed("crew")).toBe(false)
			local start = triangle(c)
			expect(start ~= nil).toBe(true)
			expectReachable(c, start, "Q2")
			expectEmpty(overlaps(c), "chevauchements Q2")
			expectEmpty(Gamepad.audit(c.h), "audit Q2")
			patch(c, { onboarding = { step = 3, p = 0 } })
			expect(c.HUD.isRevealed("minimap")).toBe(true)
			expect(c.HUD.isRevealed("ping")).toBe(true)
			start = triangle(c)
			expectReachable(c, start, "Q3")
			expectEmpty(overlaps(c), "chevauchements Q3")
			expectEmpty(Gamepad.audit(c.h), "audit Q3")
			-- ACCLAMER pendant l'accueil : atteignable, sans recouvrir l'instruction
			cheerPrompt(c)
			expect(c.Onboarding._state().hintShown).toBe(true)
			expectReachable(c, triangle(c), "Q3 + ACCLAMER")
			expectEmpty(overlaps(c), "chevauchements Q3 + ACCLAMER")
			expect(#c.h.errors).toBe(0)
		end)

		it("Q5 : icône R2 pendant la pulsation du Dash", function()
			local c = onboarding()
			frames(c, 12)
			-- la pulsation du Dash dure 1,6 s : observée tout de suite
			c.h:fireClient(
				"ReplicatedStorage.Remotes.DataPatch",
				{ onboarding = { step = 5, p = 0 }, upgrades = { conga = 2 } },
				{}
			)
			frames(c, 12)
			local hud = gui(c, "HUD")
			expect(c.HUD._state().handTarget).toBe(c.HUD._state().elements.dash)
			expect(glyphOf(hud.HandGlyph)).toEqual(psGlyph("ButtonR2"))
			expect(c.HUD._state().hand.Visible).toBe(false)
			-- au-dessus du Dash, dans la zone sûre
			Layout.apply(c.h)
			local glyph, dash = Layout.rect(hud.HandGlyph), Layout.rect(hud.Dash.Button)
			expect(glyph.y + glyph.h <= dash.y).toBe(true)
			expectEmpty(Gamepad.audit(c.h), "audit Q5")
		end)

		it("clavier : « Tap Upgrade » et la main restent (comportement inchangé)", function()
			local c = onboarding()
			c.h.game.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
			frames(c, 12)
			expect(c.Platform.usingGamepad()).toBe(false)
			expect(c.Onboarding.currentHint()).toBe("onboarding.tapUpgrade")
			local hint = gui(c, "Onboarding").Hint
			expect(hint.Icon.Visible).toBe(true)
			expect(hint.PadGlyph.Visible).toBe(false)
			expect(c.HUD._state().hand.Visible).toBe(true)
			expect(gui(c, "HUD").HandGlyph.Visible).toBe(false)
			-- touches du clavier de retour, icônes de manette masquées
			expect(gui(c, "HUD").Dash.Button.KeyCap.Visible).toBe(true)
			expect(gui(c, "HUD").Dash.Button.KeyCap.Text).toBe("E")
			expect(gui(c, "HUD").Dash.Button.PadGlyph.Visible).toBe(false)
		end)
	end)

	describe("Console HUD › API Roblox", function()
		it(
			"accueil à la manette, △ / ✕, ACCLAMER, minicarte et écran d'échec : API valide (ApiAudit)",
			function()
				ApiAudit.start()
				local ok, err = pcall(function()
					local c = boot({
						glow = 5000,
						onboarding = { step = 1, p = 0 },
						stats = { parades = 1, sessions = 0 },
						upgrades = { conga = 0 },
					})
					frames(c, 12)
					triangle(c)
					frames(c, 4)
					c.h:fireClient(
						"ReplicatedStorage.Remotes.DataPatch",
						{ onboarding = { step = 8, p = 0 } },
						{}
					)
					frames(c, 12)
					cheerPrompt(c)
					Gamepad.tap(c.h, Enum.KeyCode.DPadLeft)
					Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
					frames(c, 4)
					c.h.game.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
					frames(c, 4)
					local h = Harness.new({ mode = "client", console = true })
					MockInstance.classMethods.ReplicatedFirst =
						{ RemoveDefaultLoadingScreen = function() end }
					h:run("ReplicatedFirst.Loading")
					MockInstance.classMethods.ReplicatedFirst = nil
					h:step(1, 21)
					expect(#c.h.errors + #h.errors).toBe(0)
					expect(table.concat(c.h:warnings(), "\n")).toBe("")
				end)
				local issues = ApiAudit.stop()
				expect(ok and true or err).toBe(true)
				expect(table.concat(issues, "\n")).toBe("")
			end
		)
	end)

	describe("Console HUD › écran de chargement", function()
		local SOURCE = "src/first/Loading.client.luau"

		local function run(opts)
			opts = opts or {}
			local h = Harness.new({ mode = "client", console = opts.console, viewport = opts.viewport })
			MockInstance.classMethods.ReplicatedFirst = {
				RemoveDefaultLoadingScreen = function() end,
			}
			h:run("ReplicatedFirst.Loading")
			MockInstance.classMethods.ReplicatedFirst = nil
			return h, h.localPlayer.PlayerGui:FindFirstChild("Loading")
		end

		local function stageScale(loading)
			return loading:FindFirstChild("Stage", true):FindFirstChildOfClass("UIScale").Scale
		end

		it(
			"console 1080p : échelle 1,5, « Réessayer » sélectionné avec l'icône ✕ PlayStation",
			function()
				local h, loading = run({ console = true })
				expect(stageScale(loading)).toBe(1.5)
				expect(Gamepad.selected(h)).toBeNil()
				h:step(1, 21)
				local fail = loading:FindFirstChild("Fail", true)
				expect(fail.Visible).toBe(true)
				expect(fail.FailScale.Scale).toBe(1.5)
				local button = fail.RetryButton
				expect(Gamepad.selected(h)).toBe(button)
				expect(button.SelectionImageObject ~= nil).toBe(true)
				expect(glyphOf(fail.PadGlyph)).toEqual(psGlyph("ButtonA"))
				Layout.apply(h)
				local g, b = Layout.rect(fail.PadGlyph), Layout.rect(button)
				expect(g.x + g.w <= b.x).toBe(true)
				expect(math.abs((g.y + g.h / 2) - (b.y + b.h / 2)) < 1).toBe(true)
				expectEmpty(Gamepad.audit(h), "audit chargement")
				-- ✕ sur « Réessayer » : téléportation demandée
				local teleports = 0
				MockInstance.classMethods.TeleportService.Teleport = function()
					teleports += 1
				end
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				expect(teleports).toBe(1)
				-- le client finit par être prêt : l'écran se ferme et rend la main au stick
				h.localPlayer:SetAttribute("ClientReady", true)
				h:settle(3)
				expect(h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
				expect(Gamepad.selected(h)).toBeNil()
			end
		)

		it(
			"téléviseur 4K : sans plafond (3) ; PC et téléphone : règle d'origine, rien de sélectionné",
			function()
				local _, tv = run({ console = true, viewport = Vector2.new(3840, 2160) })
				expect(stageScale(tv)).toBe(3)
				local h, pc = run()
				expect(stageScale(pc)).toBe(1.2)
				h:step(1, 21)
				local fail = pc:FindFirstChild("Fail", true)
				expect(fail.Visible).toBe(true)
				expect(fail.FailScale.Scale).toBe(1)
				expect(fail:FindFirstChild("PadGlyph")).toBeNil()
				expect(Gamepad.selected(h)).toBeNil()
				-- manette prise en main pendant l'écran d'échec : « Réessayer » sélectionné, icône ✕
				Gamepad.tap(h, Enum.KeyCode.DPadDown)
				expect(Gamepad.selected(h)).toBe(fail.RetryButton)
				expect(fail:FindFirstChild("PadGlyph") ~= nil).toBe(true)
				-- manette branchée sur PC : « Réessayer » sélectionné aussi
				local h2 = Harness.new({ mode = "client" })
				h2.game.UserInputService.GamepadEnabled = true
				MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
				h2:run("ReplicatedFirst.Loading")
				MockInstance.classMethods.ReplicatedFirst = nil
				h2:step(1, 21)
				expect(Gamepad.selected(h2)).toBe(
					h2.localPlayer.PlayerGui.Loading:FindFirstChild("RetryButton", true)
				)
			end
		)

		it("constantes d'échelle égales à Config/Console (écran autonome, non répliqué)", function()
			local h = Harness.new({ mode = "client" })
			local Console = h:require("ReplicatedStorage.Shared.Config.Console")
			local source = fs.readFile(SOURCE)
			local refX, refY = string.match(source, "local REFERENCE = Vector2%.new%((%d+), (%d+)%)")
			expect(tonumber(refX)).toBe(Console.Reference.X)
			expect(tonumber(refY)).toBe(Console.Reference.Y)
			local tvMin = string.match(source, "local TV_SCALE_MIN = ([%d%.]+)")
			expect(tonumber(tvMin)).toBe(Console.TvScale.Min)
		end)
	end)
end
