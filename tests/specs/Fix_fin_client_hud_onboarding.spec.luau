--!nocheck
-- Finition « fin-client-hud-onboarding » (HUD, accueil, ScreenFX, Juice, Panels/Model) :
--   1. Boutique sans article (tous les ids à 0) : l'icône du rail n'apparaît pas à Q6 ni au HUD
--      complet, B / L2-R2 ne l'ouvrent pas ; un id renseigné : elle apparaît comme avant
--   2. fin de Q4 : la main sur Collection dure tant que la carte « Star Atlas unlocked! » est à
--      l'écran (ScreenFX.CardOpened), sur la vraie suite de messages du serveur
--   3. Q6 entre deux fenêtres météo, la prochaine étant une Pluie de météores (sans forme) :
--      « Météo dans {time} » jusqu'à la prochaine météo utile, la pastille ne pulse pas
--   8. Quête d'accueil réussie : la barre du suivi se remplit, une coche, puis la quête suivante ;
--      le toast « questDone » nomme la quête
--   9. Repli du suivi de quête : zone tactile ≥ 44 px réels à 640 × 360 (toute la pastille)
--  10. Accueil : le compteur de file vide montre « 0/3 » et sa barre, pas « Catch Nebbies! »
--      (une seule instruction à l'écran, GDD §3)
--  11. Juice.press : doigt relevé hors du bouton (InputEnded) → le bouton revient à 1
--  12. Sur la plateforme du Nid à côté de l'arche, file non vide : « Walk under your arch! »
--  13. Dash maintenu plus de 1,5 s : pas de second Dash ni de secousse au relâchement
--   6. Porteur de la Comète au nom long : nom coupé (« … ») dans la pastille d'événement
--   7. Pastille d'événement qui pulse : jamais sur Réglages (téléviseur, petits téléphones)
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000

	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	-- Client isolé (HUD + accueil), monde et panneaux remplacés ; écran tactile par défaut
	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", touch = opts.touch ~= false })
		h.localPlayer.LocaleId = opts.locale or "en-us"
		h:createRemotes()
		if opts.reduced ~= false then
			h.game.GuiService.ReducedMotionEnabled = true
		end
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t0 or T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			Monetization = h:require("ReplicatedStorage.Shared.Config.Monetization"),
			Quests = h:require("ReplicatedStorage.Shared.Config.Quests"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Format = h:require("ReplicatedStorage.Shared.Util.Format"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Toast = h:require(CLIENT .. "UI.Toast"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
			Minimap = h:require(CLIENT .. "UI.Minimap"),
			Onboarding = h:require(CLIENT .. "Controllers.OnboardingController"),
			Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan"),
			length = 0,
			events = nil,
			open = nil,
			opened = {},
			toasts = {},
		}
		c.VFX.playDash = function() end
		c.VFX.playUpgrade = function() end
		c.WSC.localSlot = function()
			return 1
		end
		c.WSC.lineLength = function()
			return c.length
		end
		c.WSC.wilds = function()
			return {}
		end
		c.WSC.events = function()
			return c.events
		end
		c.Panels.open = function(name, args)
			table.insert(c.opened, name)
			c.open = name
			c.Panels.Opened:Fire(name)
			return true
		end
		c.Panels.close = function()
			local name = c.open
			c.open = nil
			if name then
				c.Panels.Closed:Fire(name)
			end
			return true
		end
		c.Panels.current = function()
			return c.open
		end
		local show = c.Toast.show
		c.Toast.show = function(text, kind)
			table.insert(c.toasts, text)
			return show(text, kind)
		end
		h.localPlayer.Character.HumanoidRootPart.CFrame =
			CFrame.new(c.WorldLayout.gateCFrame(1).Position + Vector3.new(0, 3, 0))
		local order = { "Root", "State", "Prefs", "FX", "Input", "HUD", "Minimap" }
		if opts.onboarding ~= false then
			table.insert(order, "Onboarding")
		end
		for _, name in order do
			if c[name].Init then
				c[name].Init()
			end
		end
		for _, name in order do
			if c[name].Start and name ~= "Root" and name ~= "State" then
				c[name].Start()
			end
		end
		return c
	end

	local function load(c, over)
		local p = Schema.defaults()
		for k, v in over or {} do
			p[k] = v
		end
		c.h:fireClient(REMOTES .. "DataSnapshot", p)
		c.h:settle(1)
	end

	local function patch(c, data)
		c.h:fireClient(REMOTES .. "DataPatch", data, {})
		c.h:settle(1)
	end

	local function frames(c, n, dt)
		for _ = 1, n or 3 do
			c.h:step(dt or 1 / 30, 1)
			c.h:settle(1)
		end
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
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

	-- écran simulé (comme Fix_r4_client_0) : HUD et accueil mesurés sous la barre Roblox
	local function screen(c, width, height, topbar)
		c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(width, height)
		local playerGui = c.h.localPlayer.PlayerGui
		for _, name in { "HUD", "Onboarding" } do
			local gui = playerGui:FindFirstChild(name)
			if gui then
				gui.AbsoluteSize = Vector2.new(width, height - topbar)
				gui.Safe.AbsoluteSize = gui.AbsoluteSize
			end
		end
		c.HUD._layoutActions()
		c.h:settle(1)
	end

	local function setIds(c, passId, productId)
		for _, def in c.Monetization.Passes do
			def.id = 0
		end
		for _, def in c.Monetization.Products do
			def.id = 0
		end
		if passId then
			c.Monetization.Passes.DoubleGlow.id = passId
		end
		if productId then
			c.Monetization.Products.GlowPouch.id = productId
		end
	end

	-- =============================================================================================
	-- 1. Boutique vide
	-- =============================================================================================
	describe("fin-client-hud-onboarding › boutique sans article : pas d'icône Boutique", function()
		it("Model.shopHasItems : faux avec tous les ids à 0, vrai dès un id (passe ou produit)", function()
			local c = setup({ onboarding = false })
			local Model = c.h:require(CLIENT .. "UI.Panels.Model")
			local view = Model.view(function()
				return nil
			end)
			setIds(c)
			expect(Model.shopHasItems(view, nil, T0)).toBe(false)
			setIds(c, 111)
			expect(Model.shopHasItems(view, nil, T0)).toBe(true)
			setIds(c, nil, 222)
			expect(Model.shopHasItems(view, nil, T0)).toBe(true)
			-- seul produit : le Starter Kit, déjà acheté → rien à montrer
			setIds(c)
			c.Monetization.Products.StarterKit.id = 333
			local bought = Model.view(function(key)
				return if key == "starterKit" then true else nil
			end)
			expect(Model.shopHasItems(bought, nil, T0)).toBe(false)
			expect(Model.shopHasItems(view, nil, T0)).toBe(true)
			setIds(c)
		end)

		it(
			"Q6, tous les ids à 0 : ni icône, ni B, ni L2/R2 ; un id renseigné : l'icône apparaît",
			function()
				local c = setup()
				setIds(c)
				load(c, { onboarding = { step = 6, p = 0 }, stats = { parades = 10, sessions = 0 } })
				frames(c, 10)
				expect(c.HUD.isRevealed("rail.Collection")).toBe(true)
				expect(c.HUD.isRevealed("rail.Shop")).toBe(false)
				expect(hud(c).Rail.Shop.Visible).toBe(false)
				-- B (raccourci) et L2 / R2 (garde de PanelController) : refusés
				expect(c.Input.togglePanel("Shop")).toBe(false)
				expect(c.Input.openPanel("Shop")).toBe(false)
				expect(c.Panels.allowed("Shop")).toBe(false)
				expect(table.find(c.opened, "Shop")).toBeNil()
				-- les autres panneaux du rail s'ouvrent toujours
				expect(c.Panels.allowed("Collection")).toBe(true)
				-- un id renseigné (ou chargé plus tard) : l'icône apparaît, la Boutique s'ouvre
				setIds(c, 4242)
				frames(c, 12)
				expect(c.HUD.isRevealed("rail.Shop")).toBe(true)
				expect(hud(c).Rail.Shop.Visible).toBe(true)
				expect(c.Panels.allowed("Shop")).toBe(true)
				expect(c.Input.openPanel("Shop")).toBe(true)
				expect(c.open).toBe("Shop")
				setIds(c)
				expect(#c.h:signalErrors()).toBe(0)
			end
		)

		it(
			"HUD complet (accueil fini), ids à 0 : pas d'icône Boutique ; avec un produit : comme avant",
			function()
				local c = setup()
				setIds(c)
				load(c, { onboarding = { step = 8, p = 0 }, stats = { parades = 50, sessions = 3 } })
				frames(c, 10)
				expect(c.HUD.isRevealed("rail.Goals")).toBe(true)
				expect(c.HUD.isRevealed("rail.Shop")).toBe(false)
				expect(c.Panels.allowed("Shop")).toBe(false)
				setIds(c, nil, 5151)
				frames(c, 12)
				expect(c.HUD.isRevealed("rail.Shop")).toBe(true)
				expect(c.Panels.allowed("Shop")).toBe(true)
				setIds(c)
			end
		)
	end)

	-- =============================================================================================
	-- 2. Main sur Collection pendant toute la carte « Star Atlas unlocked! »
	-- =============================================================================================
	describe("fin-client-hud-onboarding › fin de Q4 : la main dure tant que la carte de l'Atlas", function()
		local function atlasCard(c)
			for _, card in c.FX._state().cardList do
				local label = card.frame:FindFirstChild("Text")
				if label and string.find(label.Text, "Star Atlas", 1, true) then
					return card
				end
			end
			return nil
		end

		it("suite réelle (atlasNew ×3, questDone, questClaimed, atlasUnlocked, étape 5)", function()
			local c = setup()
			load(c, {
				onboarding = { step = 4, p = 0 },
				stats = { parades = 6, sessions = 0 },
				upgrades = { conga = 2 },
			})
			screen(c, 1280, 720, 36)
			frames(c, 10)
			local cardOpened = {}
			c.FX.CardOpened:Connect(function(kind)
				table.insert(cardOpened, kind)
			end)
			for s = 1, 3 do
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "atlasNew", data = { entries = { { s = s, f = 0 } } } }
				)
			end
			c.h:fireClient(
				REMOTES .. "Celebrate",
				{ kind = "questDone", data = { kind = "onboarding", slot = 1, id = "q4" } }
			)
			c.h:fireClient(REMOTES .. "Celebrate", { kind = "questClaimed", data = { stardust = 100 } })
			c.h:fireClient(
				REMOTES .. "Celebrate",
				{ kind = "atlasUnlocked", data = { count = 4, total = 150 } }
			)
			c.h:settle(2)
			patch(c, { onboarding = { step = 5, p = 0 }, stardust = 100 })
			local seen, covered, after = 0, 0, false
			for _ = 1, 260 do -- 8,7 s
				frames(c, 1)
				local on = c.Onboarding._state().attention["rail.Collection"] == true
				if atlasCard(c) ~= nil then
					seen += 1
					if on then
						covered += 1
					end
				elseif seen > 0 and not on then
					after = true
				end
			end
			expect(table.find(cardOpened, "atlasUnlocked") ~= nil).toBe(true)
			expect(seen > 60).toBe(true) -- la carte est bien restée ~3 s
			expect(covered).toBe(seen)
			-- et la main s'arrête après la carte
			expect(after).toBe(true)
			expect(c.Onboarding._state().attention["rail.Collection"] == true).toBe(false)
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)

	describe("fin-client-hud-onboarding › carte de l'Atlas entrée tout de suite (pile libre)", function()
		it(
			"icône Collection déjà affichée : une seule pulsation, avec la carte, pas de seconde",
			function()
				local c = setup()
				load(c, {
					onboarding = { step = 5, p = 0 },
					stats = { parades = 6, sessions = 0 },
					upgrades = { conga = 2 },
					stardust = 100,
				})
				screen(c, 1280, 720, 36)
				frames(c, 10)
				expect(c.HUD.isRevealed("rail.Collection")).toBe(true)
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "atlasUnlocked", data = { count = 4, total = 150 } }
				)
				c.h:settle(2)
				frames(c, 1)
				expect(c.FX._state().cards).toBe(1)
				expect(c.Onboarding._state().attention["rail.Collection"]).toBe(true)
				local offAt, again = nil, false
				for i = 1, 240 do -- 8 s
					frames(c, 1)
					local on = c.Onboarding._state().attention["rail.Collection"] == true
					if not on and offAt == nil then
						offAt = i
					elseif on and offAt ~= nil then
						again = true
					end
				end
				expect(offAt ~= nil and offAt >= 85 and offAt <= 110).toBe(true) -- ~3,2 s
				expect(again).toBe(false)
				expect(#c.h:signalErrors()).toBe(0)
			end
		)
	end)

	-- =============================================================================================
	-- 3. Q6 : la prochaine fenêtre est une Pluie de météores
	-- =============================================================================================
	describe(
		"fin-client-hud-onboarding › Q6 avant une Pluie de météores (aucune fenêtre ouverte)",
		function()
			local function meteorWindow(EventClock, t)
				local x = t
				for _ = 1, 500 do
					local w = EventClock.nextWeather(x)
					if w.key == "meteor" and w.form == nil then
						-- fenêtre précédente finie depuis au moins 120 s
						return w
					end
					x = w.startsAt
				end
				error("aucune Pluie de météores trouvée")
			end

			it(
				"règle pure : fait nextWeatherFormless → « Météo dans {time} », pastille immobile",
				function()
					local c = setup({ onboarding = false })
					local f = {
						step = 6,
						returning = false,
						parades = 8,
						conga = 3,
						stardust = 100,
						lineCount = 0,
						lineFull = false,
						upgradesOpen = false,
						canBuyConga = false,
						canBuyStride = false,
						canBuyPerches = false,
						rareTarget = false,
						weatherActive = false,
						weatherFormless = false,
						nextWeatherFormless = true,
						weatherTarget = false,
						cometActive = false,
					}
					expect(c.Plan.hint(f)).toBe("onboarding.waitWeatherIn")
					expect(c.Plan.attention(f).eventPill).toBeNil()
					f.nextWeatherFormless = false
					expect(c.Plan.hint(f)).toBe("onboarding.waitWeather")
					expect(c.Plan.attention(f).eventPill).toBe(true)
					-- une Comète à rejoindre passe devant
					f.nextWeatherFormless = true
					f.cometActive = true
					expect(c.Plan.hint(f)).toBe("onboarding.joinComet")
				end
			)

			it("112 s avant une vraie Pluie de météores : compte à rebours de la météo utile", function()
				local probe = setup({ onboarding = false })
				local w = meteorWindow(probe.EventClock, T0)
				local now = w.startsAt - 112
				local c = setup({ t0 = now })
				load(c, { onboarding = { step = 6, p = 0 }, stats = { parades = 12, sessions = 0 } })
				frames(c, 10)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeatherIn")
				expect(c.Onboarding._state().attention.eventPill == true).toBe(false)
				local wait = c.Plan.formWeatherIn(now)
				expect(wait > 112).toBe(true)
				local label = c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint.Text
				expect(label.Text).toBe("☁ Weather in " .. c.Format.clock(wait))
				-- la Pluie commence : même instruction (fenêtre sans forme en cours)
				c.events = {
					weather = { key = "meteor", startsAt = w.startsAt, endsAt = w.endsAt },
				}
				c.Clock.freeze(w.startsAt + 1)
				frames(c, 15)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeatherIn")
				expect(#c.h:signalErrors()).toBe(0)
			end)
		end
	)

	-- =============================================================================================
	-- 8. Quête d'accueil réussie : barre pleine, coche, puis quête suivante ; toast nommé
	-- =============================================================================================
	describe("fin-client-hud-onboarding › quête d'accueil réussie dans le suivi", function()
		it("Q2 → Q3 : barre remplie, « ✓ », puis le titre et la barre de Q3", function()
			local c = setup()
			load(c, {
				onboarding = { step = 2, p = 1 },
				stats = { parades = 3, sessions = 0 },
				upgrades = { conga = 1 },
			})
			frames(c, 12)
			local pill = hud(c).QuestTracker.Pill
			expect(c.HUD.isRevealed("questTracker")).toBe(true)
			expect(pill.Title.Text).toBe("Conga ×2")
			expect(math.abs(pill.Bar.Fill.Size.X.Scale - 0.5) < 1e-6).toBe(true)
			-- le serveur passe p à n puis à l'étape suivante dans la même image
			patch(c, { onboarding = { step = 3, p = 0 }, upgrades = { conga = 2 } })
			frames(c, 8) -- 0,27 s
			expect(pill.Icon.Text).toBe("✓")
			expect(pill.Title.Text).toBe("Conga ×2")
			expect(pill.Bar.Fill.Size.X.Scale).toBe(1)
			frames(c, 50) -- 1,9 s
			expect(pill.Title.Text).toBe("Parade of 6")
			expect(pill.Icon.Text ~= "✓").toBe(true)
			expect(pill.Bar.Fill.Size.X.Scale).toBe(0)
			expect(#c.h:signalErrors()).toBe(0)
		end)

		it(
			"toast « questDone » d'accueil : nom de la quête + ✓ (EN et FR) ; autres quêtes : inchangé",
			function()
				for _, case in { { "en-us", "Bank a Rare ✓" }, { "fr-fr", "Encaisse un Rare ✓" } } do
					local c = setup({ locale = case[1], onboarding = false })
					load(c, { onboarding = { step = 4, p = 0 } })
					c.h:fireClient(
						REMOTES .. "Celebrate",
						{ kind = "questDone", data = { kind = "onboarding", slot = 1, id = "q4" } }
					)
					c.h:settle(2)
					expect(c.toasts[#c.toasts]).toBe(case[2])
				end
				local c = setup({ onboarding = false })
				load(c)
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "questDone", data = { kind = "daily", slot = 2, id = 3 } }
				)
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "questDone", data = { kind = "onboarding", id = "nope" } }
				)
				c.h:settle(2)
				expect(c.toasts[#c.toasts - 1]).toBe("Quest complete!")
				expect(c.toasts[#c.toasts]).toBe("Quest complete!")
			end
		)
	end)

	-- =============================================================================================
	-- 9. Repli du suivi de quête : grande zone tactile
	-- =============================================================================================
	describe("fin-client-hud-onboarding › repli du suivi de quête au doigt", function()
		it(
			"640 × 360 : zone ≥ 44 px réels, dépliée et repliée ; un appui sur la pastille replie",
			function()
				local c = setup()
				load(c, { onboarding = { step = 3, p = 0 }, stats = { parades = 3, sessions = 0 } })
				frames(c, 10)
				screen(c, 640, 360, 36)
				frames(c, 35)
				local k = c.Root.scale()
				local holder = hud(c).QuestTracker
				local hit = holder:FindFirstChild("Hit")
				expect(hit ~= nil).toBe(true)
				expect(hit:IsA("GuiButton")).toBe(true)
				expect(hit.Selectable).toBe(false) -- la manette garde le petit bouton (graphe de sélection)
				expect(hit.Size.X.Offset * k >= 44).toBe(true)
				expect(hit.Size.Y.Offset * k >= 44).toBe(true)
				-- toute la pastille dépliée est couverte
				expect(hit.Size.X.Offset >= holder.Pill.Size.X.Offset).toBe(true)
				hit.Activated:Fire({ UserInputType = Enum.UserInputType.Touch }, 1)
				frames(c, 12)
				expect(c.HUD._state().trackerParts.collapsed).toBe(true)
				expect(hit.Size.X.Offset * k >= 44).toBe(true)
				expect(hit.Size.Y.Offset * k >= 44).toBe(true)
				hit.Activated:Fire({ UserInputType = Enum.UserInputType.Touch }, 1)
				frames(c, 12)
				expect(c.HUD._state().trackerParts.collapsed).toBe(false)
				expect(#c.h:signalErrors()).toBe(0)
			end
		)
	end)

	-- =============================================================================================
	-- 10. Une seule instruction : compteur de file pendant l'accueil
	-- =============================================================================================
	describe("fin-client-hud-onboarding › compteur de file vide pendant l'accueil", function()
		it(
			"Q1 : « 0/3 » et la barre, pas « Catch Nebbies! » ; accueil fini : texte d'invitation",
			function()
				local c = setup()
				load(c, { onboarding = { step = 1, p = 0 } })
				frames(c, 90)
				expect(c.Onboarding.currentHint() ~= nil).toBe(true)
				local pill = hud(c).LineCounter.Pill
				expect(pill.Empty.Visible).toBe(false)
				expect(pill.Count.Visible).toBe(true)
				expect(pill.Count.Text).toBe("0/3")
				expect(pill.Bar.Visible).toBe(true)
				patch(c, { onboarding = { step = 8, p = 0 } })
				frames(c, 10)
				expect(pill.Empty.Visible).toBe(true)
				expect(pill.Count.Visible).toBe(false)
			end
		)

		it("joueur qui revient (HUD complet) : texte d'invitation inchangé", function()
			local c = setup()
			load(c, { onboarding = { step = 8, p = 0 }, stats = { parades = 40, sessions = 4 } })
			frames(c, 10)
			expect(hud(c).LineCounter.Pill.Empty.Visible).toBe(true)
		end)
	end)

	-- =============================================================================================
	-- 11. Juice.press : relâchement hors du bouton
	-- =============================================================================================
	describe("fin-client-hud-onboarding › Juice.press, doigt relevé hors du bouton", function()
		it(
			"InputEnded du même toucher ramène l'échelle à 1 (pas de MouseButton1Up ni MouseLeave)",
			function()
				local c = setup({ onboarding = false, reduced = false })
				local Widgets = c.h:require(CLIENT .. "UI.Hud.Widgets")
				local a = Widgets.button("A", hud(c), roblox.Color3.new(1, 1, 1), false)
				local b = Widgets.button("B", hud(c), roblox.Color3.new(1, 1, 1), false)
				local uis = c.h.game.UserInputService
				local touch =
					{ UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.Begin }
				local other =
					{ UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.Begin }
				for _, button in { a, b } do
					button.InputBegan:Fire(if button == a then touch else other)
					button.MouseButton1Down:Fire(10, 10)
				end
				frames(c, 10)
				expect(math.abs(a.JuiceScale.Scale - 0.9) < 1e-3).toBe(true)
				expect(math.abs(b.JuiceScale.Scale - 0.9) < 1e-3).toBe(true)
				-- le premier doigt se relève ailleurs : seul son bouton revient
				uis.InputEnded:Fire(touch, false)
				frames(c, 15)
				expect(math.abs(a.JuiceScale.Scale - 1) < 1e-3).toBe(true)
				expect(math.abs(b.JuiceScale.Scale - 0.9) < 1e-3).toBe(true)
				uis.InputEnded:Fire(other, false)
				frames(c, 15)
				expect(math.abs(b.JuiceScale.Scale - 1) < 1e-3).toBe(true)
				-- souris relâchée hors du bouton : même retour
				local mouse = {
					UserInputType = Enum.UserInputType.MouseButton1,
					UserInputState = Enum.UserInputState.Begin,
				}
				a.InputBegan:Fire(mouse)
				a.MouseButton1Down:Fire(10, 10)
				frames(c, 10)
				expect(math.abs(a.JuiceScale.Scale - 0.9) < 1e-3).toBe(true)
				uis.InputEnded:Fire({
					UserInputType = Enum.UserInputType.MouseButton1,
					UserInputState = Enum.UserInputState.End,
				}, false)
				frames(c, 15)
				expect(math.abs(a.JuiceScale.Scale - 1) < 1e-3).toBe(true)
				expect(#c.h:signalErrors()).toBe(0)
			end
		)
	end)

	-- =============================================================================================
	-- 12. Sur la plateforme du Nid, à côté de l'arche
	-- =============================================================================================
	describe("fin-client-hud-onboarding › « Passe sous l'arche ! »", function()
		it(
			"règle pure : file à encaisser, au Nid hors de la porte → throughArch, guidage vers la porte",
			function()
				local c = setup({ onboarding = false })
				local f = {
					step = 1,
					returning = false,
					parades = 0,
					conga = 0,
					stardust = 0,
					lineCount = 3,
					lineFull = true,
					upgradesOpen = false,
					canBuyConga = false,
					canBuyStride = false,
					canBuyPerches = false,
					rareTarget = false,
					inHarborNotGate = true,
				}
				expect(c.Plan.hint(f)).toBe("onboarding.throughArch")
				expect(c.Plan.guide(f)).toBe("toGate")
				f.inHarborNotGate = false
				expect(c.Plan.hint(f)).toBe("onboarding.goHome")
				-- Q3 : la file contient la parade demandée
				f.step, f.parades, f.conga, f.lineCount, f.lineFull = 3, 3, 2, 6, false
				f.inHarborNotGate = true
				expect(c.Plan.hint(f)).toBe("onboarding.throughArch")
				expect(c.Plan.guide(f)).toBe("toGate")
				-- rien à encaisser : l'instruction ne change pas
				f.lineCount = 2
				expect(c.Plan.hint(f)).toBe("onboarding.findNebbies")
				-- textes EN / FR
				expect(c.Prefs.t("onboarding.throughArch")).toBe("Walk under your arch!")
			end
		)

		it(
			"contrôleur : plateforme du Nid → « Walk under your arch! », dans la porte → retour normal",
			function()
				local c = setup()
				c.length = 3
				load(c, { onboarding = { step = 1, p = 0 } })
				frames(c, 90)
				local root = c.h.localPlayer.Character.HumanoidRootPart
				local center = c.WorldLayout.nestCenter(1)
				root.CFrame = CFrame.new(center + Vector3.new(0, 3, 0))
				frames(c, 20)
				expect(c.WorldLayout.inOwnHarbor(1, root.Position)).toBe(true)
				expect(c.WorldLayout.inGateBox(1, root.Position)).toBe(false)
				expect(c.Onboarding.currentHint()).toBe("onboarding.throughArch")
				expect(c.Onboarding.guide()).toBe("toGate")
				expect(c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint.Text.Text).toBe("Walk under your arch!")
				-- loin du Nid : « Back to your Nest »
				root.CFrame = CFrame.new(c.WorldLayout.gateCFrame(1).Position * 0.4 + Vector3.new(0, 3, 0))
				frames(c, 20)
				expect(c.Onboarding.currentHint()).toBe("onboarding.goHome")
				expect(#c.h:signalErrors()).toBe(0)
			end
		)

		it("français : « Passe sous l'arche ! »", function()
			local c = setup({ locale = "fr-fr", onboarding = false })
			expect(c.Prefs.t("onboarding.throughArch")).toBe("Passe sous l'arche !")
		end)
	end)

	-- =============================================================================================
	-- 13. Dash maintenu
	-- =============================================================================================
	describe("fin-client-hud-onboarding › Dash maintenu plus de 1,5 s", function()
		it(
			"tactile maintenu 2 s : un seul Dash, aucune secousse au relâchement ; manette : Activated",
			function()
				local c = setup({ onboarding = false })
				load(c)
				c.HUD.reveal("dash", false)
				local refused = 0
				c.Input.DashRefused:Connect(function()
					refused += 1
				end)
				local button = hud(c).Dash.Button
				local touch =
					{ UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.Begin }
				button.InputBegan:Fire(touch)
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(1)
				frames(c, 60) -- doigt posé 2 s
				button.Activated:Fire(touch, 1)
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(1)
				expect(refused).toBe(0)
				-- souris maintenue : pareil
				c.Clock.advance(c.Formulas.dashCooldown(0) + 0.1)
				local mouse = {
					UserInputType = Enum.UserInputType.MouseButton1,
					UserInputState = Enum.UserInputState.Begin,
				}
				button.InputBegan:Fire(mouse)
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(2)
				frames(c, 75)
				button.Activated:Fire(mouse, 1)
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(2)
				expect(refused).toBe(0)
				-- manette (bouton sélectionné + ✕) : Activated seul envoie le Dash, même juste après
				c.Clock.advance(c.Formulas.dashCooldown(0) + 0.1)
				button.Activated:Fire(
					{ UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonA },
					1
				)
				c.h:settle(1)
				expect(#sent(c, "Dash")).toBe(3)
			end
		)
	end)

	-- =============================================================================================
	-- 6. Porteur de la Comète au nom long
	-- =============================================================================================
	describe("fin-client-hud-onboarding › pastille de la Comète portée, nom long", function()
		it("nom coupé à 10 caractères + « … » ; nom court intact", function()
			local c = setup({ onboarding = false })
			local EventPill = c.h:require(CLIENT .. "UI.Hud.EventPill")
			local ev = { comet = { phase = "carried", carrierId = 7, burstAt = T0 + 45, impactAt = T0 - 20 } }
			local state = EventPill.compute(ev, T0, c.Prefs.t, function()
				return "SuperLongPlayerName20"
			end)
			expect(state.vars.name).toBe("SuperLongP…")
			state = EventPill.compute(ev, T0, c.Prefs.t, function()
				return "Mira"
			end)
			expect(state.vars.name).toBe("Mira")
			state = EventPill.compute(ev, T0, c.Prefs.t, function()
				return "ÉléonoreÉléonore"
			end)
			expect(state.vars.name).toBe("ÉléonoreÉl…")
		end)
	end)
end
